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

	cfg := Config{
		Env:               Env(strings.ToLower(str("BG_ENV", string(EnvDev)))),
		HTTPAddr:          str("BG_HTTP_ADDR", ":8080"),
		LogFormat:         strings.ToLower(str("BG_LOG_FORMAT", "json")),
		ReadHeaderTimeout: dur("BG_READ_HEADER_TIMEOUT", 5*time.Second),
		ReadTimeout:       dur("BG_READ_TIMEOUT", 10*time.Second),
		WriteTimeout:      dur("BG_WRITE_TIMEOUT", 10*time.Second),
		IdleTimeout:       dur("BG_IDLE_TIMEOUT", 60*time.Second),
		ShutdownTimeout:   dur("BG_SHUTDOWN_TIMEOUT", 30*time.Second),
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

	if err := errors.Join(errs...); err != nil {
		return Config{}, fmt.Errorf("configuração inválida: %w", err)
	}
	return cfg, nil
}
