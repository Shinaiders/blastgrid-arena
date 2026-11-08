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

	"github.com/Shinaiders/blastgrid-arena/server/internal/platform"
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

func TestV1AuthRoomsMatchmakingAndRankings(t *testing.T) {
	s := New(testLogger(io.Discard), Options{Version: "test"})
	h := s.Handler()

	// 1. Login de convidado
	reqGuest := httptest.NewRequest("POST", "/v1/auth/guest", strings.NewReader(`{"display_name":"VoltHero"}`))
	recGuest := httptest.NewRecorder()
	h.ServeHTTP(recGuest, reqGuest)
	if recGuest.Code != http.StatusOK {
		t.Fatalf("guest login: %d %s", recGuest.Code, recGuest.Body.String())
	}
	var guestResp map[string]any
	_ = json.Unmarshal(recGuest.Body.Bytes(), &guestResp)
	tok, _ := guestResp["access_token"].(string)
	if tok == "" {
		t.Fatal("access_token vazio")
	}

	authHdr := map[string]string{"Authorization": "Bearer " + tok}

	// 2. Perfil autenticado
	recProf, bodyProf := do(t, h, "GET", "/v1/profile", authHdr)
	if recProf.Code != http.StatusOK || bodyProf["profile"] == nil {
		t.Fatalf("profile: %d %v", recProf.Code, bodyProf)
	}

	// 3. Matchmaking cria/entra em sala pública
	reqMM := httptest.NewRequest("POST", "/v1/matchmaking/enqueue", strings.NewReader(`{"mode":"ffa","max_players":4,"platform":"web"}`))
	reqMM.Header.Set("Authorization", "Bearer "+tok)
	recMM := httptest.NewRecorder()
	h.ServeHTTP(recMM, reqMM)
	if recMM.Code != http.StatusOK {
		t.Fatalf("matchmaking: %d %s", recMM.Code, recMM.Body.String())
	}

	// 4. Listagem de salas e ranking
	recRooms, _ := do(t, h, "GET", "/v1/rooms", nil)
	if recRooms.Code != http.StatusOK {
		t.Fatalf("rooms: %d", recRooms.Code)
	}
	recRank, _ := do(t, h, "GET", "/v1/rankings", nil)
	if recRank.Code != http.StatusOK {
		t.Fatalf("rankings: %d", recRank.Code)
	}
}

func TestAuthAndRoomsEndpoints(t *testing.T) {
	TestV1AuthRoomsMatchmakingAndRankings(t)
}

func TestSteamAuthEndpoint(t *testing.T) {
	s := New(testLogger(io.Discard), Options{Version: "test"})
	h := s.Handler()

	if s.Dispatcher() == nil {
		t.Fatal("s.Dispatcher() não deve ser nil")
	}

	const steamID uint64 = 76561198000000001
	validTicket := platform.BuildMockTicket(steamID, 480)

	// 1. Ticket válido
	validBody := map[string]any{
		"ticket":       validTicket,
		"app_id":       480,
		"display_name": "SteamVolt",
	}
	rawValid, _ := json.Marshal(validBody)
	reqValid := httptest.NewRequest("POST", "/v1/auth/steam", bytes.NewReader(rawValid))
	recValid := httptest.NewRecorder()
	h.ServeHTTP(recValid, reqValid)

	if recValid.Code != http.StatusOK {
		t.Fatalf("auth steam válido: esperado 200, veio %d %s", recValid.Code, recValid.Body.String())
	}
	var respValid struct {
		AccessToken string         `json:"access_token"`
		SteamID     uint64         `json:"steam_id"`
		User        map[string]any `json:"user"`
	}
	if err := json.Unmarshal(recValid.Body.Bytes(), &respValid); err != nil {
		t.Fatalf("json inválido: %v", err)
	}
	if respValid.AccessToken == "" {
		t.Fatal("access_token não veio na resposta")
	}
	if respValid.SteamID != steamID {
		t.Fatalf("steam_id esperado %d, veio %d", steamID, respValid.SteamID)
	}
	if respValid.User == nil {
		t.Fatal("user não veio na resposta")
	}

	// 2. Ticket inválido -> 401 Unauthorized
	invalidBody := map[string]any{
		"ticket": "invalid_ticket_hex_123",
		"app_id": 480,
	}
	rawInvalid, _ := json.Marshal(invalidBody)
	reqInvalid := httptest.NewRequest("POST", "/v1/auth/steam", bytes.NewReader(rawInvalid))
	recInvalid := httptest.NewRecorder()
	h.ServeHTTP(recInvalid, reqInvalid)

	if recInvalid.Code != http.StatusUnauthorized {
		t.Fatalf("auth steam inválido: esperado 401, veio %d %s", recInvalid.Code, recInvalid.Body.String())
	}

	// 3. GET /ws sem cabeçalhos de WebSocket upgrade -> 400 Bad Request
	reqWS := httptest.NewRequest("GET", "/ws", nil)
	recWS := httptest.NewRecorder()
	h.ServeHTTP(recWS, reqWS)
	if recWS.Code != http.StatusBadRequest {
		t.Fatalf("GET /ws sem upgrade esperado 400, veio %d %s", recWS.Code, recWS.Body.String())
	}
}
