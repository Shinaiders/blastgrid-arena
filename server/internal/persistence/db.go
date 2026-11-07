// Package persistence concentra o acesso ao PostgreSQL: pool pgx, helper de
// transação com retry e o runner de migrations (docs/DATABASE.md §5–7).
package persistence

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// PoolConfig são os parâmetros do pool vindos de internal/config.
type PoolConfig struct {
	URL            string
	MaxConns       int32
	MinConns       int32
	ConnectTimeout time.Duration
}

// Open cria o pool e confirma a conexão com um Ping dentro de ConnectTimeout.
// Erros nunca incluem a URL (contém a senha).
func Open(ctx context.Context, c PoolConfig) (*pgxpool.Pool, error) {
	pc, err := pgxpool.ParseConfig(c.URL)
	if err != nil {
		return nil, fmt.Errorf("BG_DATABASE_URL inválida: %w", redact(err))
	}
	if c.MaxConns > 0 {
		pc.MaxConns = c.MaxConns
	}
	if c.MinConns >= 0 {
		pc.MinConns = c.MinConns
	}
	if c.ConnectTimeout > 0 {
		pc.ConnConfig.ConnectTimeout = c.ConnectTimeout
	}
	pc.ConnConfig.RuntimeParams["application_name"] = "blastgrid-api"

	pool, err := pgxpool.NewWithConfig(ctx, pc)
	if err != nil {
		return nil, fmt.Errorf("criar pool: %w", err)
	}
	pingCtx, cancel := context.WithTimeout(ctx, pc.ConnConfig.ConnectTimeout)
	defer cancel()
	if err := pool.Ping(pingCtx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("conectar ao banco: %w", err)
	}
	return pool, nil
}

// PingCheck devolve a função usada pelo /readyz (o timeout vem do ctx).
func PingCheck(pool *pgxpool.Pool) func(ctx context.Context) error {
	return func(ctx context.Context) error { return pool.Ping(ctx) }
}

// redact evita que a mensagem de parse do pgx carregue a DSN original.
func redact(err error) error {
	return fmt.Errorf("formato não reconhecido (%T)", err)
}
