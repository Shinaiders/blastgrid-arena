package persistence

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// MaxTxAttempts é o total de tentativas de WithTx para erros transitórios.
const MaxTxAttempts = 3

// TxBeginner é satisfeito por *pgxpool.Pool, *pgx.Conn e pgx.Tx.
type TxBeginner interface {
	Begin(ctx context.Context) (pgx.Tx, error)
}

// WithTx executa fn numa transação READ COMMITTED. Commit se fn retornar nil;
// rollback caso contrário. Em serialization_failure (40001) ou
// deadlock_detected (40P01) repete fn até MaxTxAttempts vezes — portanto fn
// deve ser idempotente em relação a efeitos fora do banco.
func WithTx(ctx context.Context, db TxBeginner, fn func(pgx.Tx) error) error {
	var err error
	for attempt := 1; attempt <= MaxTxAttempts; attempt++ {
		err = runTx(ctx, db, fn)
		if err == nil || !IsRetryable(err) || ctx.Err() != nil {
			return err
		}
	}
	return fmt.Errorf("transação falhou após %d tentativas: %w", MaxTxAttempts, err)
}

func runTx(ctx context.Context, db TxBeginner, fn func(pgx.Tx) error) (err error) {
	tx, err := db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin: %w", err)
	}
	defer func() {
		if err != nil {
			// Rollback com contexto próprio: ctx pode já estar cancelado.
			_ = tx.Rollback(context.WithoutCancel(ctx))
		}
	}()
	if err = fn(tx); err != nil {
		return err
	}
	if err = tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit: %w", err)
	}
	return nil
}

// IsRetryable informa se o erro é transitório (serialização ou deadlock).
func IsRetryable(err error) bool {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) {
		return pgErr.Code == "40001" || pgErr.Code == "40P01"
	}
	return false
}
