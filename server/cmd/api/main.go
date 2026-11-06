// Comando api: servidor HTTP do BlastGrid Arena.
//
// Lê a configuração de variáveis BG_* (docs/DEPLOYMENT.md), sobe o servidor
// HTTP e faz graceful shutdown em SIGINT/SIGTERM respeitando BG_SHUTDOWN_TIMEOUT.
package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/signal"
	"syscall"

	"github.com/Shinaiders/blastgrid-arena/server/internal/config"
	"github.com/Shinaiders/blastgrid-arena/server/internal/httpapi"
	"github.com/Shinaiders/blastgrid-arena/server/internal/logging"
)

// version é sobrescrita no build: -ldflags "-X main.version=<commit>".
var version = "dev"

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := run(ctx, os.Getenv, os.Stdout, nil); err != nil {
		fmt.Fprintln(os.Stderr, "api:", err)
		os.Exit(1)
	}
}

// run é o corpo do processo, separado de main para ser testável.
// Encerra quando ctx é cancelado (sinal) ou o servidor falha.
// Se listening != nil, recebe o endereço efetivo assim que o socket abre.
func run(ctx context.Context, getenv func(string) string, logOut io.Writer, listening chan<- string) error {
	cfg, err := config.Load(getenv)
	if err != nil {
		return err
	}
	log := logging.New(logOut, cfg.LogLevel, cfg.LogFormat)
	log.Info("api: iniciando", "version", version, "env", cfg.Env, "addr", cfg.HTTPAddr)

	srv := httpapi.New(log, httpapi.Options{
		Addr:              cfg.HTTPAddr,
		ReadHeaderTimeout: cfg.ReadHeaderTimeout,
		ReadTimeout:       cfg.ReadTimeout,
		WriteTimeout:      cfg.WriteTimeout,
		IdleTimeout:       cfg.IdleTimeout,
		Version:           version,
		// Checks de prontidão (banco) entram no Dia 04.
	})

	ln, err := net.Listen("tcp", cfg.HTTPAddr)
	if err != nil {
		return fmt.Errorf("escutar em %s: %w", cfg.HTTPAddr, err)
	}
	if listening != nil {
		listening <- ln.Addr().String()
	}

	serveErr := make(chan error, 1)
	go func() { serveErr <- srv.Serve(ln) }()

	select {
	case err := <-serveErr:
		if err != nil {
			return fmt.Errorf("servidor http: %w", err)
		}
		return nil
	case <-ctx.Done():
		log.Info("api: sinal de encerramento recebido", "shutdown_timeout", cfg.ShutdownTimeout.String())
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), cfg.ShutdownTimeout)
	defer cancel()
	shutdownErr := srv.Shutdown(shutdownCtx)
	if err := <-serveErr; err != nil {
		return fmt.Errorf("servidor http: %w", err)
	}
	if shutdownErr != nil && !errors.Is(shutdownErr, context.DeadlineExceeded) {
		return fmt.Errorf("shutdown: %w", shutdownErr)
	}
	log.Info("api: encerrado")
	return nil
}
