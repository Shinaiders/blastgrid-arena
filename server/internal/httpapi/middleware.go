package httpapi

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"log/slog"
	"net/http"
	"time"
)

type ctxKey int

const requestIDKey ctxKey = iota

// RequestIDHeader é aceito na entrada (se válido) e sempre devolvido na resposta.
const RequestIDHeader = "X-Request-ID"

// RequestID devolve o id da requisição guardado no contexto ("" se ausente).
func RequestID(ctx context.Context) string {
	id, _ := ctx.Value(requestIDKey).(string)
	return id
}

// middleware aplica, de fora para dentro: request id, log de acesso,
// recuperação de panic e limite de corpo.
func (s *Server) middleware(next http.Handler) http.Handler {
	next = http.MaxBytesHandler(next, MaxBodyBytes)
	next = s.recoverer(next)
	return s.accessLog(next)
}

func (s *Server) accessLog(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get(RequestIDHeader)
		if !validRequestID(id) {
			id = newRequestID()
		}
		w.Header().Set(RequestIDHeader, id)
		r = r.WithContext(context.WithValue(r.Context(), requestIDKey, id))

		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)

		lvl := slog.LevelInfo
		if r.URL.Path == "/healthz" || r.URL.Path == "/readyz" {
			lvl = slog.LevelDebug // health checks frequentes não poluem o log em info
		}
		if rec.status >= 500 {
			lvl = slog.LevelError
		}
		s.log.Log(r.Context(), lvl, "http: requisição",
			"request_id", id,
			"method", r.Method,
			"path", r.URL.Path,
			"status", rec.status,
			"bytes", rec.bytes,
			"duration_ms", time.Since(start).Milliseconds(),
			"remote", r.RemoteAddr,
		)
	})
}

func (s *Server) recoverer(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if v := recover(); v != nil {
				if v == http.ErrAbortHandler {
					panic(v)
				}
				s.log.Error("http: panic no handler", "request_id", RequestID(r.Context()), "panic", v)
				writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal"})
			}
		}()
		next.ServeHTTP(w, r)
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status      int
	bytes       int
	wroteHeader bool
}

func (r *statusRecorder) WriteHeader(code int) {
	if !r.wroteHeader {
		r.status, r.wroteHeader = code, true
	}
	r.ResponseWriter.WriteHeader(code)
}

func (r *statusRecorder) Write(b []byte) (int, error) {
	r.wroteHeader = true
	n, err := r.ResponseWriter.Write(b)
	r.bytes += n
	return n, err
}

// Unwrap permite a http.ResponseController alcançar o writer original
// (necessário para Hijack no upgrade WebSocket da Fase 3).
func (r *statusRecorder) Unwrap() http.ResponseWriter { return r.ResponseWriter }

func validRequestID(id string) bool {
	if id == "" || len(id) > 64 {
		return false
	}
	for _, c := range id {
		if !(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '-' || c == '_') {
			return false
		}
	}
	return true
}

func newRequestID() string {
	var b [16]byte
	_, _ = rand.Read(b[:]) // crypto/rand.Read não falha desde o Go 1.24
	return hex.EncodeToString(b[:])
}
