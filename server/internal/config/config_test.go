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
		"BG_DATABASE_URL":     "postgres://bg:segredo@db:5432/blastgrid?sslmode=disable",
		"BG_DB_MAX_CONNS":     "20",
		"BG_DB_MIN_CONNS":     "2",
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
	if cfg.DBMaxConns != 20 || cfg.DBMinConns != 2 || cfg.DBConnectTimeout != 5*time.Second || cfg.MigrateOnStart {
		t.Errorf("config de banco inesperada: %+v", cfg)
	}
}

func TestDatabaseRules(t *testing.T) {
	cases := []struct {
		name    string
		env     map[string]string
		wantErr string // "" = deve passar
	}{
		{"dev sem banco", nil, ""},
		{"prod sem banco", map[string]string{"BG_ENV": "prod"}, "BG_DATABASE_URL: obrigatória"},
		{"migrate on start em prod", map[string]string{"BG_ENV": "prod", "BG_DATABASE_URL": "postgres://a:b@h/d", "BG_MIGRATE_ON_START": "true"}, "BG_MIGRATE_ON_START"},
		{"migrate on start sem url", map[string]string{"BG_MIGRATE_ON_START": "true"}, "exige BG_DATABASE_URL"},
		{"migrate on start dev", map[string]string{"BG_DATABASE_URL": "postgres://a:b@h/d", "BG_MIGRATE_ON_START": "1"}, ""},
		{"min > max", map[string]string{"BG_DB_MAX_CONNS": "2", "BG_DB_MIN_CONNS": "5"}, "BG_DB_MIN_CONNS"},
		{"max fora da faixa", map[string]string{"BG_DB_MAX_CONNS": "0"}, "BG_DB_MAX_CONNS"},
		{"bool inválido", map[string]string{"BG_MIGRATE_ON_START": "talvez"}, "BG_MIGRATE_ON_START"},
		{"esquema errado", map[string]string{"BG_DATABASE_URL": "mysql://a:b@h/d"}, "BG_DATABASE_URL"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := Load(envMap(tc.env))
			if tc.wantErr == "" {
				if err != nil {
					t.Fatalf("esperava sucesso, veio %v", err)
				}
				return
			}
			if err == nil || !strings.Contains(err.Error(), tc.wantErr) {
				t.Fatalf("esperava erro com %q, veio %v", tc.wantErr, err)
			}
		})
	}
}

func TestDatabaseURLNotLeakedInError(t *testing.T) {
	_, err := Load(envMap(map[string]string{"BG_DATABASE_URL": "mysql://u:senha-super-secreta@h/d"}))
	if err == nil || strings.Contains(err.Error(), "senha-super-secreta") {
		t.Fatalf("erro não deve conter a senha: %v", err)
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
