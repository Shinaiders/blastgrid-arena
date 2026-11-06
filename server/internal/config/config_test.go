package config

import (
	"log/slog"
	"strings"
	"testing"
	"time"
)

func envMap(m map[string]string) func(string) string {
	return func(k string) string { return m[k] }
}

func TestLoadDefaults(t *testing.T) {
	cfg, err := Load(envMap(nil))
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if cfg.Env != EnvDev || cfg.HTTPAddr != ":8080" || cfg.LogLevel != slog.LevelInfo || cfg.LogFormat != "json" {
		t.Errorf("defaults inesperados: %+v", cfg)
	}
	if cfg.ReadHeaderTimeout != 5*time.Second || cfg.ReadTimeout != 10*time.Second ||
		cfg.WriteTimeout != 10*time.Second || cfg.IdleTimeout != 60*time.Second ||
		cfg.ShutdownTimeout != 30*time.Second {
		t.Errorf("timeouts padrão inesperados: %+v", cfg)
	}
}

func TestLoadOverrides(t *testing.T) {
	cfg, err := Load(envMap(map[string]string{
		"BG_ENV":              "PROD",
		"BG_HTTP_ADDR":        "127.0.0.1:9000",
		"BG_LOG_LEVEL":        "debug",
		"BG_LOG_FORMAT":       "json",
		"BG_SHUTDOWN_TIMEOUT": "2s",
		"BG_IDLE_TIMEOUT":     " 90s ",
	}))
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if cfg.Env != EnvProd || cfg.HTTPAddr != "127.0.0.1:9000" || cfg.LogLevel != slog.LevelDebug {
		t.Errorf("overrides não aplicados: %+v", cfg)
	}
	if cfg.ShutdownTimeout != 2*time.Second || cfg.IdleTimeout != 90*time.Second {
		t.Errorf("durações não aplicadas: %+v", cfg)
	}
}

func TestLoadInvalidCollectsAllErrors(t *testing.T) {
	_, err := Load(envMap(map[string]string{
		"BG_ENV":           "staging",
		"BG_LOG_LEVEL":     "verbose",
		"BG_LOG_FORMAT":    "xml",
		"BG_READ_TIMEOUT":  "dez",
		"BG_WRITE_TIMEOUT": "-1s",
		"BG_HTTP_ADDR":     "8080",
	}))
	if err == nil {
		t.Fatal("esperava erro")
	}
	for _, key := range []string{"BG_ENV", "BG_LOG_LEVEL", "BG_LOG_FORMAT", "BG_READ_TIMEOUT", "BG_WRITE_TIMEOUT", "BG_HTTP_ADDR"} {
		if !strings.Contains(err.Error(), key) {
			t.Errorf("erro não menciona %s: %v", key, err)
		}
	}
}

func TestTextLogRejectedInProd(t *testing.T) {
	_, err := Load(envMap(map[string]string{"BG_ENV": "prod", "BG_LOG_FORMAT": "text"}))
	if err == nil || !strings.Contains(err.Error(), "BG_LOG_FORMAT") {
		t.Fatalf("esperava erro de BG_LOG_FORMAT em prod, veio %v", err)
	}
}
