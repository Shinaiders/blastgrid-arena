package persistence_test

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"github.com/Shinaiders/blastgrid-arena/server/internal/persistence"
)

func migrated(t *testing.T) (context.Context, interface {
	Exec(context.Context, string, ...any) (pgconn.CommandTag, error)
	QueryRow(context.Context, string, ...any) pgx.Row
	Query(context.Context, string, ...any) (pgx.Rows, error)
	Begin(context.Context) (pgx.Tx, error)
}) {
	pool := newPool(t)
	if _, err := newMigrator(t, pool).Up(context.Background()); err != nil {
		t.Fatal(err)
	}
	return context.Background(), pool
}

func pgCode(err error) string {
	var pe *pgconn.PgError
	if errors.As(err, &pe) {
		return pe.Code
	}
	return ""
}

func TestSchemaSeedAndConstraints(t *testing.T) {
	ctx, db := migrated(t)

	var chars, skins, achs int
	if err := db.QueryRow(ctx, `SELECT (SELECT count(*) FROM characters), (SELECT count(*) FROM skins), (SELECT count(*) FROM achievements)`).Scan(&chars, &skins, &achs); err != nil {
		t.Fatal(err)
	}
	if chars != 4 || skins != 4 || achs != 3 {
		t.Fatalf("seed: characters=%d skins=%d achievements=%d", chars, skins, achs)
	}

	var uid int64
	if err := db.QueryRow(ctx, `INSERT INTO users (email, password_hash) VALUES ('Ana@Example.com', 'x') RETURNING id`).Scan(&uid); err != nil {
		t.Fatal(err)
	}
	// email único sem diferenciar maiúsculas
	if _, err := db.Exec(ctx, `INSERT INTO users (email) VALUES ('ana@example.COM')`); pgCode(err) != "23505" {
		t.Errorf("email duplicado (case-insensitive) deveria violar unique, veio %v", err)
	}
	// convidado não pode ter credenciais
	if _, err := db.Exec(ctx, `INSERT INTO users (kind, email) VALUES ('guest', 'g@x.io')`); pgCode(err) != "23514" {
		t.Errorf("convidado com email deveria violar check, veio %v", err)
	}
	if _, err := db.Exec(ctx, `INSERT INTO user_profiles (user_id, display_name) VALUES ($1, 'Ana')`, uid); err != nil {
		t.Fatal(err)
	}
	var gid int64
	if err := db.QueryRow(ctx, `INSERT INTO users (kind) VALUES ('guest') RETURNING id`).Scan(&gid); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(ctx, `INSERT INTO user_profiles (user_id, display_name) VALUES ($1, 'ANA')`, gid); pgCode(err) != "23505" {
		t.Errorf("display_name duplicado deveria violar unique, veio %v", err)
	}
	if _, err := db.Exec(ctx, `INSERT INTO user_profiles (user_id, display_name) VALUES ($1, 'ab')`, gid); pgCode(err) != "23514" {
		t.Errorf("display_name curto deveria violar check, veio %v", err)
	}

	// partida: vencedor apagado vira NULL, histórico preservado
	var mid int64
	err := db.QueryRow(ctx, `INSERT INTO matches (mode, seed, tick_rate, started_at, ended_at, duration_ticks, end_reason, winner_user_id, server_version)
		VALUES ('ffa', 4294967295, 20, now() - interval '3 min', now(), 3600, 'last_alive', $1, 'test') RETURNING id`, gid).Scan(&mid)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(ctx, `INSERT INTO match_players (match_id, slot, user_id, place, platform) VALUES ($1, 0, $2, 1, 'web'), ($1, 1, $3, 2, 'linux')`, mid, gid, uid); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(ctx, `INSERT INTO match_players (match_id, slot, place, platform) VALUES ($1, 8, 3, 'web')`, mid); pgCode(err) != "23514" {
		t.Errorf("slot 8 (9º jogador) deveria violar check, veio %v", err)
	}
	if _, err := db.Exec(ctx, `DELETE FROM users WHERE id = $1`, gid); err != nil {
		t.Fatal(err)
	}
	var winner *int64
	var players int
	if err := db.QueryRow(ctx, `SELECT winner_user_id, (SELECT count(*) FROM match_players WHERE match_id = $1) FROM matches WHERE id = $1`, mid).Scan(&winner, &players); err != nil {
		t.Fatal(err)
	}
	if winner != nil || players != 2 {
		t.Errorf("após apagar usuário: winner=%v players=%d (esperado nil, 2)", winner, players)
	}
}

// TestLeaderboardUsesIndex garante que o top N e a paginação keyset usam o índice de ranking.
func TestLeaderboardUsesIndex(t *testing.T) {
	ctx, db := migrated(t)
	if _, err := db.Exec(ctx, `INSERT INTO users (kind) SELECT 'guest' FROM generate_series(1, 300)`); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(ctx, `INSERT INTO rankings (season, mode, user_id, rating) SELECT 1, 'ffa', id, 800 + (id * 37) % 500 FROM users`); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(ctx, `ANALYZE rankings`); err != nil {
		t.Fatal(err)
	}
	tx, err := db.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, `SET LOCAL enable_seqscan = off`); err != nil {
		t.Fatal(err)
	}
	var plan strings.Builder
	rows, err := tx.Query(ctx, `EXPLAIN SELECT user_id, rating FROM rankings
		WHERE season = 1 AND mode = 'ffa' AND (rating, user_id) < (1100, 50)
		ORDER BY rating DESC, user_id DESC LIMIT 20`)
	if err != nil {
		t.Fatal(err)
	}
	for rows.Next() {
		var line string
		_ = rows.Scan(&line)
		plan.WriteString(line + "\n")
	}
	if err := rows.Err(); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(plan.String(), "rankings_leaderboard_idx") || strings.Contains(plan.String(), "Sort") {
		t.Errorf("plano não usa o índice de ranking sem sort:\n%s", plan.String())
	}
}

func TestWithTx(t *testing.T) {
	ctx, db := migrated(t)

	// erro em fn ⇒ rollback
	sentinel := errors.New("falhou")
	err := persistence.WithTx(ctx, db, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `INSERT INTO users (kind) VALUES ('guest')`); err != nil {
			return err
		}
		return sentinel
	})
	if !errors.Is(err, sentinel) {
		t.Fatalf("esperava sentinel, veio %v", err)
	}
	var n int
	_ = db.QueryRow(ctx, `SELECT count(*) FROM users`).Scan(&n)
	if n != 0 {
		t.Fatalf("rollback não aconteceu: %d usuários", n)
	}

	// erro transitório ⇒ repete; sucesso na 2ª tentativa grava uma vez só
	attempts := 0
	err = persistence.WithTx(ctx, db, func(tx pgx.Tx) error {
		attempts++
		if _, err := tx.Exec(ctx, `INSERT INTO users (kind) VALUES ('guest')`); err != nil {
			return err
		}
		if attempts == 1 {
			return &pgconn.PgError{Code: "40001", Message: "simulado"}
		}
		return nil
	})
	if err != nil || attempts != 2 {
		t.Fatalf("retry: attempts=%d err=%v", attempts, err)
	}
	_ = db.QueryRow(ctx, `SELECT count(*) FROM users`).Scan(&n)
	if n != 1 {
		t.Fatalf("esperava 1 usuário após retry, há %d", n)
	}

	// erro transitório persistente ⇒ desiste após MaxTxAttempts
	attempts = 0
	err = persistence.WithTx(ctx, db, func(tx pgx.Tx) error {
		attempts++
		return &pgconn.PgError{Code: "40P01", Message: "deadlock simulado"}
	})
	if err == nil || attempts != persistence.MaxTxAttempts || !persistence.IsRetryable(err) {
		t.Fatalf("esperava desistir após %d tentativas: attempts=%d err=%v", persistence.MaxTxAttempts, attempts, err)
	}
}

func TestOpenErrorDoesNotLeakPassword(t *testing.T) {
	_, err := persistence.Open(context.Background(), persistence.PoolConfig{URL: "postgres://u:senha-secreta@127.0.0.1:1/db?connect_timeout=1"})
	if err == nil {
		t.Fatal("esperava erro de conexão")
	}
	if strings.Contains(err.Error(), "senha-secreta") {
		t.Fatalf("erro vaza a senha: %v", err)
	}
}
