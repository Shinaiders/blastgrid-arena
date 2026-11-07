// Package pgtest prepara bancos isolados para testes de integração.
//
// Os testes rodam contra o PostgreSQL apontado por BG_TEST_DATABASE_URL e são
// pulados (t.Skip) se ela não estiver definida. Cada chamada cria um schema
// exclusivo e devolve uma URL com search_path apontando para ele, então
// pacotes testados em paralelo não interferem entre si.
package pgtest

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"net/url"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
)

// EnvVar é a variável que habilita os testes de integração.
const EnvVar = "BG_TEST_DATABASE_URL"

// URL devolve a DSN de um schema novo e vazio; o schema é removido no fim do teste.
func URL(t testing.TB) string {
	t.Helper()
	base := os.Getenv(EnvVar)
	if base == "" {
		t.Skipf("%s não definida; teste de integração com PostgreSQL pulado", EnvVar)
	}
	var b [6]byte
	_, _ = rand.Read(b[:])
	schema := "t_" + hex.EncodeToString(b[:])

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	conn, err := pgx.Connect(ctx, base)
	if err != nil {
		t.Fatalf("pgtest: conectar: %v", err)
	}
	defer conn.Close(ctx)
	if _, err := conn.Exec(ctx, "CREATE SCHEMA "+schema); err != nil {
		t.Fatalf("pgtest: criar schema: %v", err)
	}
	t.Cleanup(func() {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		c, err := pgx.Connect(ctx, base)
		if err != nil {
			t.Errorf("pgtest: limpeza: %v", err)
			return
		}
		defer c.Close(ctx)
		if _, err := c.Exec(ctx, "DROP SCHEMA "+schema+" CASCADE"); err != nil {
			t.Errorf("pgtest: remover schema: %v", err)
		}
	})

	u, err := url.Parse(base)
	if err != nil {
		t.Fatalf("pgtest: %s inválida", EnvVar)
	}
	q := u.Query()
	q.Set("search_path", schema)
	u.RawQuery = q.Encode()
	return u.String()
}
