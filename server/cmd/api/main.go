// Comando api: servidor HTTP do BlastGrid Arena.
//
// Uso:
//
//	api                      sobe o servidor (padrão)
//	api migrate up           aplica as migrations pendentes
//	api migrate down [N]     reverte as N últimas (padrão 1)
//	api migrate status       lista as migrations e quando foram aplicadas
//	api healthcheck          GET /healthz local; exit 0 se 200 (HEALTHCHECK do Docker)
//
// Lê a configuração de variáveis BG_* (docs/DEPLOYMENT.md), sobe o servidor
// HTTP e faz graceful shutdown em SIGINT/SIGTERM respeitando BG_SHUTDOWN_TIMEOUT.
package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/Shinaiders/blastgrid-arena/server/internal/config"
	"github.com/Shinaiders/blastgrid-arena/server/internal/httpapi"
	"github.com/Shinaiders/blastgrid-arena/server/internal/logging"
	"github.com/Shinaiders/blastgrid-arena/server/internal/persistence"
	"github.com/Shinaiders/blastgrid-arena/server/migrations"
)

// version é sobrescrita no build: -ldflags "-X main.version=<commit>".
var version = "dev"

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := dispatch(ctx, os.Args[1:], os.Getenv, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "api:", err)
		os.Exit(1)
	}
}

// dispatch escolhe o subcomando.
func dispatch(ctx context.Context, args []string, getenv func(string) string, out io.Writer) error {
	if len(args) == 0 || args[0] == "serve" {
		return run(ctx, getenv, out, nil)
	}
	switch args[0] {
	case "migrate":
		return migrateCmd(ctx, args[1:], getenv, out)
	case "healthcheck":
		return healthcheck(ctx, getenv)
	default:
		return fmt.Errorf("subcomando desconhecido %q (use: serve | migrate up|down [N]|status | healthcheck)", args[0])
	}
}

// run é o corpo do servidor, separado de main para ser testável.
// Encerra quando ctx é cancelado (sinal) ou o servidor falha.
// Se listening != nil, recebe o endereço efetivo assim que o socket abre.
func run(ctx context.Context, getenv func(string) string, logOut io.Writer, listening chan<- string) error {
	cfg, err := config.Load(getenv)
	if err != nil {
		return err
	}
	log := logging.New(logOut, cfg.LogLevel, cfg.LogFormat)
	log.Info("api: iniciando", "version", version, "env", cfg.Env, "addr", cfg.HTTPAddr)

	var checks []httpapi.ReadinessCheck
	if cfg.DatabaseURL == "" {
		log.Warn("api: BG_DATABASE_URL vazia; subindo sem banco (somente dev)")
	} else {
		pool, err := openDB(ctx, cfg)
		if err != nil {
			return err
		}
		defer pool.Close()
		log.Info("db: conectado", "max_conns", cfg.DBMaxConns, "min_conns", cfg.DBMinConns)
		if cfg.MigrateOnStart {
			if err := migrateUp(ctx, pool, log); err != nil {
				return err
			}
		}
		checks = append(checks, httpapi.ReadinessCheck{Name: "database", Check: persistence.PingCheck(pool)})
	}

	srv := httpapi.New(log, httpapi.Options{
		Addr:              cfg.HTTPAddr,
		ReadHeaderTimeout: cfg.ReadHeaderTimeout,
		ReadTimeout:       cfg.ReadTimeout,
		WriteTimeout:      cfg.WriteTimeout,
		IdleTimeout:       cfg.IdleTimeout,
		Version:           version,
		Checks:            checks,
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

func openDB(ctx context.Context, cfg config.Config) (*pgxpool.Pool, error) {
	return persistence.Open(ctx, persistence.PoolConfig{
		URL:            cfg.DatabaseURL,
		MaxConns:       cfg.DBMaxConns,
		MinConns:       cfg.DBMinConns,
		ConnectTimeout: cfg.DBConnectTimeout,
	})
}

func newMigrator(pool *pgxpool.Pool, log *slog.Logger) (*persistence.Migrator, error) {
	ms, err := persistence.LoadMigrations(migrations.FS)
	if err != nil {
		return nil, err
	}
	return persistence.NewMigrator(pool, ms, log), nil
}

func migrateUp(ctx context.Context, pool *pgxpool.Pool, log *slog.Logger) error {
	m, err := newMigrator(pool, log)
	if err != nil {
		return err
	}
	applied, err := m.Up(ctx)
	if err != nil {
		return err
	}
	log.Info("migrate: up concluído", "applied", len(applied))
	return nil
}

// migrateCmd implementa "api migrate up|down [N]|status".
func migrateCmd(ctx context.Context, args []string, getenv func(string) string, out io.Writer) error {
	if len(args) == 0 {
		return errors.New("migrate: use up | down [N] | status")
	}
	cfg, err := config.Load(getenv)
	if err != nil {
		return err
	}
	if cfg.DatabaseURL == "" {
		return errors.New("migrate: BG_DATABASE_URL não definida")
	}
	log := logging.New(out, cfg.LogLevel, cfg.LogFormat)
	pool, err := openDB(ctx, cfg)
	if err != nil {
		return err
	}
	defer pool.Close()
	m, err := newMigrator(pool, log)
	if err != nil {
		return err
	}

	switch args[0] {
	case "up":
		if len(args) != 1 {
			return errors.New("migrate up não aceita argumentos")
		}
		return migrateUp(ctx, pool, log)
	case "down":
		n := 1
		if len(args) == 2 {
			if n, err = strconv.Atoi(args[1]); err != nil || n < 1 {
				return fmt.Errorf("migrate down: N inválido %q", args[1])
			}
		} else if len(args) > 2 {
			return errors.New("migrate down aceita no máximo um argumento")
		}
		reverted, err := m.Down(ctx, n)
		if err != nil {
			return err
		}
		log.Info("migrate: down concluído", "reverted", len(reverted))
		return nil
	case "status":
		st, err := m.Status(ctx)
		if err != nil {
			return err
		}
		for _, s := range st {
			applied := "pendente"
			if s.AppliedAt != nil {
				applied = s.AppliedAt.UTC().Format(time.RFC3339)
			}
			fmt.Fprintf(out, "%04d  %-30s  %s\n", s.Version, s.Name, applied)
		}
		return nil
	default:
		return fmt.Errorf("migrate: subcomando desconhecido %q", args[0])
	}
}

// healthcheck consulta /healthz na porta configurada (imagem distroless não tem curl).
func healthcheck(ctx context.Context, getenv func(string) string) error {
	cfg, err := config.Load(getenv)
	if err != nil {
		return err
	}
	_, port, err := net.SplitHostPort(cfg.HTTPAddr)
	if err != nil {
		return fmt.Errorf("healthcheck: BG_HTTP_ADDR: %w", err)
	}
	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, "http://127.0.0.1:"+port+"/healthz", nil)
	if err != nil {
		return err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("healthcheck: %w", err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("healthcheck: status %d", resp.StatusCode)
	}
	return nil
}
