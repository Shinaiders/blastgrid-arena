// Package logging cria o logger estruturado (log/slog) do processo.
package logging

import (
	"io"
	"log/slog"
)

// New devolve um *slog.Logger escrevendo em w no formato "json" ou "text".
// Qualquer formato diferente de "text" usa JSON (config já valida os valores).
func New(w io.Writer, level slog.Level, format string) *slog.Logger {
	opts := &slog.HandlerOptions{Level: level}
	var h slog.Handler
	if format == "text" {
		h = slog.NewTextHandler(w, opts)
	} else {
		h = slog.NewJSONHandler(w, opts)
	}
	return slog.New(h).With("service", "blastgrid-api")
}
