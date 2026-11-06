// Package httpapi monta o servidor HTTP: rotas, middlewares, health checks e
// o ciclo de vida (Serve/Shutdown) com timeouts.
//
// O diretório se chama httpapi (e não http, como no esboço do briefing) para
// não colidir com o nome do pacote net/http.
package httpapi

import (
	"context"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"sync/atomic"
	"time"
)

// MaxBodyBytes limita o corpo de qualquer requisição HTTP (as rotas REST da
// Fase 3 trafegam JSON pequeno; o WebSocket tem limite próprio por frame).
const MaxBodyBytes = 1 << 20

// ReadinessCheck é uma dependência consultada por /readyz (ex.: banco, no Dia 04).
type ReadinessCheck struct {
	Name  string
	Check func(ctx context.Context) error
}

// Options configura o servidor.
type Options struct {
	Addr              string
	ReadHeaderTimeout time.Duration
	ReadTimeout       time.Duration
	WriteTimeout      time.Duration
	IdleTimeout       time.Duration
	// ReadyTimeout é o prazo de cada verificação de /readyz (padrão 1 s).
	ReadyTimeout time.Duration
	Checks       []ReadinessCheck
	Version      string
}

// Server encapsula *http.Server com o estado de prontidão.
type Server struct {
	log      *slog.Logger
	opts     Options
	srv      *http.Server
	draining atomic.Bool
}

// New cria o servidor com as rotas registradas.
func New(log *slog.Logger, opts Options) *Server {
	if opts.ReadyTimeout <= 0 {
		opts.ReadyTimeout = time.Second
	}
	s := &Server{log: log, opts: opts}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.handleHealthz)
	mux.HandleFunc("GET /readyz", s.handleReadyz)

	s.srv = &http.Server{
		Addr:              opts.Addr,
		Handler:           s.middleware(mux),
		ReadHeaderTimeout: opts.ReadHeaderTimeout,
		ReadTimeout:       opts.ReadTimeout,
		WriteTimeout:      opts.WriteTimeout,
		IdleTimeout:       opts.IdleTimeout,
		MaxHeaderBytes:    16 << 10,
		ErrorLog:          slog.NewLogLogger(log.Handler(), slog.LevelWarn),
	}
	return s
}

// Handler expõe a pilha completa (middlewares + rotas), útil em testes.
func (s *Server) Handler() http.Handler { return s.srv.Handler }

// Serve atende em ln até Shutdown. Retorna nil no encerramento normal.
func (s *Server) Serve(ln net.Listener) error {
	s.log.Info("http: escutando", "addr", ln.Addr().String())
	if err := s.srv.Serve(ln); err != nil && !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}

// Shutdown marca o servidor como "drenando" (/readyz passa a 503), para de
// aceitar conexões novas e espera as requisições em andamento até ctx expirar.
func (s *Server) Shutdown(ctx context.Context) error {
	s.draining.Store(true)
	s.log.Info("http: iniciando graceful shutdown")
	err := s.srv.Shutdown(ctx)
	if err != nil {
		s.log.Warn("http: shutdown não concluiu no prazo; forçando fechamento", "err", err)
		_ = s.srv.Close()
	}
	return err
}
