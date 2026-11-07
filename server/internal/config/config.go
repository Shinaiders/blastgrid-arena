// Package config carrega e valida a configuração do servidor a partir de
// variáveis de ambiente com prefixo BG_ (ver docs/DEPLOYMENT.md §2).
//
// Valores inválidos fazem Load retornar erro: o processo não deve subir com
// configuração ambígua.
package config

import (
	"errors"
	"fmt"
	"log/slog"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// Env identifica o ambiente de execução.
type Env string

const (
	EnvDev  Env = "dev"
	EnvProd Env = "prod"
)

// Config é a configuração validada do processo.
type Config struct {
	Env       Env
	HTTPAddr  string
	LogLevel  slog.Level
	LogFormat string // "json" | "text"

	ReadHeaderTimeout time.Duration
	ReadTimeout       time.Duration
	WriteTimeout      time.Duration
	IdleTimeout       time.Duration
	ShutdownTimeout   time.Duration

	// Banco (docs/DATABASE.md §7). DatabaseURL vazio só é aceito em dev:
	// o servidor sobe sem banco e /readyz não inclui o check "database".
	DatabaseURL      string
	DBMaxConns       int32
	DBMinConns       int32
	DBConnectTimeout time.Duration
	MigrateOnStart   bool
}

// Load lê a configuração usando getenv (normalmente os.Getenv; injetável em testes).
// Todos os erros de validação são reunidos num único erro.
func Load(getenv func(string) string) (Config, error) {
	var errs []error
	str := func(key, def string) string {
		if v := strings.TrimSpace(getenv(key)); v != "" {
			return v
		}
		return def
	}
	dur := func(key string, def time.Duration) time.Duration {
		raw := str(key, "")
		if raw == "" {
			return def
		}
		d, err := time.ParseDuration(raw)
		if err != nil {
			errs = append(errs, fmt.Errorf("%s: duração inválida %q", key, raw))
			return def
		}
		if d <= 0 {
			errs = append(errs, fmt.Errorf("%s: deve ser > 0, recebido %q", key, raw))
			return def
		}
		return d
	}

	i32 := func(key string, def, lo, hi int32) int32 {
		raw := str(key, "")
		if raw == "" {
			return def
		}
		n, err := strconv.ParseInt(raw, 10, 32)
		if err != nil || int32(n) < lo || int32(n) > hi {
			errs = append(errs, fmt.Errorf("%s: esperado inteiro entre %d e %d, recebido %q", key, lo, hi, raw))
			return def
		}
		return int32(n)
	}
	boolean := func(key string, def bool) bool {
		raw := str(key, "")
		if raw == "" {
			return def
		}
		b, err := strconv.ParseBool(raw)
		if err != nil {
			errs = append(errs, fmt.Errorf("%s: esperado true|false, recebido %q", key, raw))
			return def
		}
		return b
	}

	cfg := Config{
		Env:               Env(strings.ToLower(str("BG_ENV", string(EnvDev)))),
		HTTPAddr:          str("BG_HTTP_ADDR", ":8080"),
		LogFormat:         strings.ToLower(str("BG_LOG_FORMAT", "json")),
		ReadHeaderTimeout: dur("BG_READ_HEADER_TIMEOUT", 5*time.Second),
		ReadTimeout:       dur("BG_READ_TIMEOUT", 10*time.Second),
		WriteTimeout:      dur("BG_WRITE_TIMEOUT", 10*time.Second),
		IdleTimeout:       dur("BG_IDLE_TIMEOUT", 60*time.Second),
		ShutdownTimeout:   dur("BG_SHUTDOWN_TIMEOUT", 30*time.Second),
		DatabaseURL:       str("BG_DATABASE_URL", ""),
		DBMaxConns:        i32("BG_DB_MAX_CONNS", 10, 1, 100),
		DBMinConns:        i32("BG_DB_MIN_CONNS", 1, 0, 100),
		DBConnectTimeout:  dur("BG_DB_CONNECT_TIMEOUT", 5*time.Second),
		MigrateOnStart:    boolean("BG_MIGRATE_ON_START", false),
	}

	if cfg.Env != EnvDev && cfg.Env != EnvProd {
		errs = append(errs, fmt.Errorf("BG_ENV: esperado dev|prod, recebido %q", cfg.Env))
	}

	switch lvl := strings.ToLower(str("BG_LOG_LEVEL", "info")); lvl {
	case "debug":
		cfg.LogLevel = slog.LevelDebug
	case "info":
		cfg.LogLevel = slog.LevelInfo
	case "warn":
		cfg.LogLevel = slog.LevelWarn
	case "error":
		cfg.LogLevel = slog.LevelError
	default:
		errs = append(errs, fmt.Errorf("BG_LOG_LEVEL: esperado debug|info|warn|error, recebido %q", lvl))
	}

	switch cfg.LogFormat {
	case "json":
	case "text":
		if cfg.Env == EnvProd {
			errs = append(errs, errors.New("BG_LOG_FORMAT: text não é permitido em prod (use json)"))
		}
	default:
		errs = append(errs, fmt.Errorf("BG_LOG_FORMAT: esperado json|text, recebido %q", cfg.LogFormat))
	}

	if !strings.Contains(cfg.HTTPAddr, ":") {
		errs = append(errs, fmt.Errorf("BG_HTTP_ADDR: esperado host:porta ou :porta, recebido %q", cfg.HTTPAddr))
	}

	if cfg.DBMinConns > cfg.DBMaxConns {
		errs = append(errs, fmt.Errorf("BG_DB_MIN_CONNS (%d) não pode ser maior que BG_DB_MAX_CONNS (%d)", cfg.DBMinConns, cfg.DBMaxConns))
	}
	if cfg.DatabaseURL != "" {
		// Não ecoar a URL no erro: ela contém a senha.
		if u, err := url.Parse(cfg.DatabaseURL); err != nil || (u.Scheme != "postgres" && u.Scheme != "postgresql") || u.Host == "" {
			errs = append(errs, errors.New("BG_DATABASE_URL: esperado postgres://usuario:senha@host:porta/banco"))
		}
	}
	if cfg.Env == EnvProd {
		if cfg.DatabaseURL == "" {
			errs = append(errs, errors.New("BG_DATABASE_URL: obrigatória em prod"))
		}
		if cfg.MigrateOnStart {
			errs = append(errs, errors.New("BG_MIGRATE_ON_START: não permitido em prod (use \"api migrate up\")"))
		}
	}
	if cfg.MigrateOnStart && cfg.DatabaseURL == "" {
		errs = append(errs, errors.New("BG_MIGRATE_ON_START: exige BG_DATABASE_URL"))
	}

	if err := errors.Join(errs...); err != nil {
		return Config{}, fmt.Errorf("configuração inválida: %w", err)
	}
	return cfg, nil
}
