package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

func testLogger(w io.Writer) *slog.Logger {
	return slog.New(slog.NewJSONHandler(w, &slog.HandlerOptions{Level: slog.LevelDebug}))
}

func do(t *testing.T, h http.Handler, method, path string, hdr map[string]string) (*httptest.ResponseRecorder, map[string]any) {
	t.Helper()
	req := httptest.NewRequest(method, path, nil)
	for k, v := range hdr {
		req.Header.Set(k, v)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	var body map[string]any
	if strings.HasPrefix(rec.Header().Get("Content-Type"), "application/json") {
		if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
			t.Fatalf("JSON inválido: %v (%q)", err, rec.Body.String())
		}
	}
	return rec, body
}

func TestHealthz(t *testing.T) {
	s := New(testLogger(io.Discard), Options{Version: "test"})
	rec, body := do(t, s.Handler(), "GET", "/healthz", nil)
	if rec.Code != 200 || body["status"] != "ok" || body["version"] != "test" {
		t.Fatalf("healthz: %d %v", rec.Code, body)
	}
	if rec.Header().Get("Cache-Control") != "no-store" {
		t.Error("healthz deveria ter Cache-Control: no-store")
	}
}

func TestReadyzChecks(t *testing.T) {
	var failing bool
	s := New(testLogger(io.Discard), Options{Checks: []ReadinessCheck{
		{Name: "fake", Check: func(context.Context) error {
			if failing {
				return errors.New("segredo interno: senha=xyz")
			}
			return nil
		}},
	}})

	rec, body := do(t, s.Handler(), "GET", "/readyz", nil)
	if rec.Code != 200 || body["status"] != "ready" {
		t.Fatalf("readyz ok: %d %v", rec.Code, body)
	}

	failing = true
	rec, body = do(t, s.Handler(), "GET", "/readyz", nil)
	if rec.Code != 503 || body["status"] != "not_ready" {
		t.Fatalf("readyz falha: %d %v", rec.Code, body)
	}
	if strings.Contains(rec.Body.String(), "senha") {
		t.Error("readyz vazou detalhe interno do erro")
	}
}

func TestReadyzCheckTimeout(t *testing.T) {
	s := New(testLogger(io.Discard), Options{ReadyTimeout: 20 * time.Millisecond, Checks: []ReadinessCheck{
		{Name: "lento", Check: func(ctx context.Context) error { <-ctx.Done(); return ctx.Err() }},
	}})
	start := time.Now()
	rec, _ := do(t, s.Handler(), "GET", "/readyz", nil)
	if rec.Code != 503 {
		t.Fatalf("esperava 503, veio %d", rec.Code)
	}
	if time.Since(start) > time.Second {
		t.Error("timeout do check não foi respeitado")
	}
}

func TestMethodAndNotFound(t *testing.T) {
	s := New(testLogger(io.Discard), Options{})
	if rec, _ := do(t, s.Handler(), "POST", "/healthz", nil); rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("POST /healthz: esperava 405, veio %d", rec.Code)
	}
	if rec, _ := do(t, s.Handler(), "GET", "/nada", nil); rec.Code != http.StatusNotFound {
		t.Errorf("GET /nada: esperava 404, veio %d", rec.Code)
	}
}

func TestRequestIDAndAccessLog(t *testing.T) {
	var buf bytes.Buffer
	s := New(testLogger(&buf), Options{})

	rec, _ := do(t, s.Handler(), "GET", "/healthz", map[string]string{RequestIDHeader: "abc-123"})
	if got := rec.Header().Get(RequestIDHeader); got != "abc-123" {
		t.Errorf("request id válido deveria ser preservado, veio %q", got)
	}
	rec, _ = do(t, s.Handler(), "GET", "/healthz", map[string]string{RequestIDHeader: "inj\"ecao<script>"})
	if got := rec.Header().Get(RequestIDHeader); len(got) != 32 {
		t.Errorf("request id inválido deveria ser substituído por um gerado, veio %q", got)
	}

	var rec0 map[string]any
	if err := json.Unmarshal(bytes.SplitN(buf.Bytes(), []byte("\n"), 2)[0], &rec0); err != nil {
		t.Fatalf("log não é JSON: %v", err)
	}
	if rec0["request_id"] != "abc-123" || rec0["path"] != "/healthz" || rec0["status"] != float64(200) {
		t.Errorf("log de acesso inesperado: %v", rec0)
	}
}

func TestRecoverer(t *testing.T) {
	var buf bytes.Buffer
	s := New(testLogger(&buf), Options{})
	h := s.middleware(http.HandlerFunc(func(http.ResponseWriter, *http.Request) { panic("boom") }))
	rec, body := do(t, h, "GET", "/x", nil)
	if rec.Code != 500 || body["error"] != "internal" {
		t.Fatalf("panic: %d %v", rec.Code, body)
	}
	if !strings.Contains(buf.String(), "panic no handler") {
		t.Error("panic não foi logado")
	}
}

func TestBodyLimit(t *testing.T) {
	s := New(testLogger(io.Discard), Options{})
	var readErr error
	h := s.middleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, readErr = io.ReadAll(r.Body)
	}))
	req := httptest.NewRequest("POST", "/x", bytes.NewReader(make([]byte, MaxBodyBytes+1)))
	h.ServeHTTP(httptest.NewRecorder(), req)
	var mbe *http.MaxBytesError
	if !errors.As(readErr, &mbe) {
		t.Fatalf("esperava MaxBytesError, veio %v", readErr)
	}
}

// TestGracefulShutdown sobe um servidor real, mantém uma requisição em
// andamento, chama Shutdown e verifica que: /readyz vira 503 durante a
// drenagem, a requisição em andamento termina com sucesso e Serve retorna nil.
func TestGracefulShutdown(t *testing.T) {
	s := New(testLogger(io.Discard), Options{ReadHeaderTimeout: time.Second})
	inFlight := make(chan struct{})
	release := make(chan struct{})
	mux := http.NewServeMux()
	mux.Handle("/", s.Handler())
	mux.HandleFunc("GET /slow", func(w http.ResponseWriter, r *http.Request) {
		close(inFlight)
		<-release
		w.Write([]byte("done"))
	})
	s.srv.Handler = mux

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	base := "http://" + ln.Addr().String()
	serveErr := make(chan error, 1)
	go func() { serveErr <- s.Serve(ln) }()

	var wg sync.WaitGroup
	wg.Add(1)
	var slowBody string
	var slowErr error
	go func() {
		defer wg.Done()
		resp, err := http.Get(base + "/slow")
		if err != nil {
			slowErr = err
			return
		}
		defer resp.Body.Close()
		b, _ := io.ReadAll(resp.Body)
		slowBody = string(b)
	}()
	<-inFlight

	shutdownErr := make(chan error, 1)
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		shutdownErr <- s.Shutdown(ctx)
	}()

	// Durante a drenagem a prontidão reporta 503 (verificado direto no handler,
	// pois o listener já não aceita conexões novas).
	deadline := time.Now().Add(2 * time.Second)
	for !s.draining.Load() && time.Now().Before(deadline) {
		time.Sleep(5 * time.Millisecond)
	}
	if rec, body := do(t, s.Handler(), "GET", "/readyz", nil); rec.Code != 503 || body["status"] != "draining" {
		t.Errorf("readyz durante shutdown: %d %v", rec.Code, body)
	}

	close(release)
	wg.Wait()
	if slowErr != nil || slowBody != "done" {
		t.Fatalf("requisição em andamento não concluiu: body=%q err=%v", slowBody, slowErr)
	}
	if err := <-shutdownErr; err != nil {
		t.Fatalf("Shutdown: %v", err)
	}
	if err := <-serveErr; err != nil {
		t.Fatalf("Serve: %v", err)
	}
}
