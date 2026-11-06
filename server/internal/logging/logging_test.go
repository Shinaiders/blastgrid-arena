package logging

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"strings"
	"testing"
)

func TestJSONOutputAndLevel(t *testing.T) {
	var buf bytes.Buffer
	log := New(&buf, slog.LevelInfo, "json")
	log.Debug("oculto")
	log.Info("visivel", "room_id", "r1")

	lines := strings.Split(strings.TrimSpace(buf.String()), "\n")
	if len(lines) != 1 {
		t.Fatalf("esperava 1 linha (debug filtrado), veio %d: %q", len(lines), buf.String())
	}
	var rec map[string]any
	if err := json.Unmarshal([]byte(lines[0]), &rec); err != nil {
		t.Fatalf("saída não é JSON: %v", err)
	}
	if rec["msg"] != "visivel" || rec["room_id"] != "r1" || rec["service"] != "blastgrid-api" || rec["level"] != "INFO" {
		t.Errorf("registro inesperado: %v", rec)
	}
}

func TestTextFormat(t *testing.T) {
	var buf bytes.Buffer
	New(&buf, slog.LevelDebug, "text").Debug("oi")
	if !strings.Contains(buf.String(), "level=DEBUG") || !strings.Contains(buf.String(), "msg=oi") {
		t.Errorf("saída text inesperada: %q", buf.String())
	}
}
