package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
)

type checkResult struct {
	Name  string `json:"name"`
	OK    bool   `json:"ok"`
	Error string `json:"error,omitempty"`
}

// handleHealthz: liveness. Não toca em dependências externas.
func (s *Server) handleHealthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"status": "ok", "version": s.opts.Version})
}

// handleReadyz: readiness. 503 durante o shutdown ou se alguma dependência falhar.
func (s *Server) handleReadyz(w http.ResponseWriter, r *http.Request) {
	if s.draining.Load() {
		writeJSON(w, http.StatusServiceUnavailable, map[string]any{"status": "draining"})
		return
	}
	status, code := "ready", http.StatusOK
	results := make([]checkResult, 0, len(s.opts.Checks))
	for _, c := range s.opts.Checks {
		ctx, cancel := context.WithTimeout(r.Context(), s.opts.ReadyTimeout)
		err := c.Check(ctx)
		cancel()
		res := checkResult{Name: c.Name, OK: err == nil}
		if err != nil {
			// Detalhe vai para o log; a resposta pública só diz qual check falhou.
			s.log.Warn("readyz: dependência indisponível", "check", c.Name, "err", err)
			res.Error = "unavailable"
			status, code = "not_ready", http.StatusServiceUnavailable
		}
		results = append(results, res)
	}
	writeJSON(w, code, map[string]any{"status": status, "checks": results})
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}
