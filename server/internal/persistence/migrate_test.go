package persistence_test

import (
	"context"
	"strings"
	"sync"
	"testing"
	"testing/fstest"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/Shinaiders/blastgrid-arena/server/internal/persistence"
	"github.com/Shinaiders/blastgrid-arena/server/internal/persistence/pgtest"
	"github.com/Shinaiders/blastgrid-arena/server/migrations"
)

func TestLoadMigrationsEmbedded(t *testing.T) {
	ms, err := persistence.LoadMigrations(migrations.FS)
	if err != nil {
		t.Fatalf("LoadMigrations: %v", err)
	}
	if len(ms) == 0 || ms[0].Version != 1 || ms[0].Name != "init" {
		t.Fatalf("migrations embutidas inesperadas: %+v", ms)
	}
}

func TestLoadMigrationsValidation(t *testing.T) {
	file := func(s string) *fstest.MapFile { return &fstest.MapFile{Data: []byte(s)} }
	cases := map[string]struct {
		fs      fstest.MapFS
		wantErr string
	}{
		"sem down":     {fstest.MapFS{"0001_a.up.sql": file("select 1")}, "sem par"},
		"lacuna":       {fstest.MapFS{"0001_a.up.sql": file("x"), "0001_a.down.sql": file("x"), "0003_c.up.sql": file("x"), "0003_c.down.sql": file("x")}, "faltando 0002"},
		"nome ruim":    {fstest.MapFS{"1_a.up.sql": file("x")}, "nome inválido"},
		"nomes trocam": {fstest.MapFS{"0001_a.up.sql": file("x"), "0001_b.down.sql": file("x")}, "nomes diferentes"},
		"ok": {fstest.MapFS{"0001_a.up.sql": file("x"), "0001_a.down.sql": file("y"), "0002_b.up.sql": file("x"),
			"0002_b.down.sql": file("y"), "README.md": file("ignorado")}, ""},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			ms, err := persistence.LoadMigrations(tc.fs)
			if tc.wantErr == "" {
				if err != nil || len(ms) != 2 || ms[1].Version != 2 {
					t.Fatalf("esperava 2 migrations, veio %v %+v", err, ms)
				}
				return
			}
			if err == nil || !strings.Contains(err.Error(), tc.wantErr) {
				t.Fatalf("esperava erro %q, veio %v", tc.wantErr, err)
			}
		})
	}
}

func newPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := pgtest.URL(t)
	ctx := context.Background()
	pool, err := persistence.Open(ctx, persistence.PoolConfig{URL: url, MaxConns: 8, MinConns: 0, ConnectTimeout: 5 * time.Second})
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

func newMigrator(t *testing.T, pool *pgxpool.Pool) *persistence.Migrator {
	t.Helper()
	ms, err := persistence.LoadMigrations(migrations.FS)
	if err != nil {
		t.Fatal(err)
	}
	return persistence.NewMigrator(pool, ms, nil)
}

func countTables(t *testing.T, pool *pgxpool.Pool) int {
	t.Helper()
	var n int
	err := pool.QueryRow(context.Background(),
		`SELECT count(*) FROM information_schema.tables WHERE table_schema = current_schema() AND table_name <> 'schema_migrations'`).Scan(&n)
	if err != nil {
		t.Fatal(err)
	}
	return n
}

// TestMigrateUpDownUp: aplica tudo, reverte tudo e aplica de novo (DATABASE.md §6).
func TestMigrateUpDownUp(t *testing.T) {
	pool := newPool(t)
	m := newMigrator(t, pool)
	ctx := context.Background()

	applied, err := m.Up(ctx)
	if err != nil {
		t.Fatalf("Up: %v", err)
	}
	if len(applied) == 0 {
		t.Fatal("Up não aplicou nada num banco vazio")
	}
	want := []string{"users", "user_profiles", "characters", "skins", "matches", "match_players",
		"rankings", "player_statistics", "achievements", "player_achievements", "player_inventory"}
	for _, tbl := range want {
		var ok bool
		if err := pool.QueryRow(ctx, `SELECT to_regclass($1) IS NOT NULL`, tbl).Scan(&ok); err != nil || !ok {
			t.Errorf("tabela %s ausente (err=%v)", tbl, err)
		}
	}
	if n := countTables(t, pool); n != len(want) {
		t.Errorf("esperava %d tabelas, há %d", len(want), n)
	}

	again, err := m.Up(ctx)
	if err != nil || len(again) != 0 {
		t.Fatalf("Up idempotente: aplicou %v, err %v", again, err)
	}
	if p, err := m.Pending(ctx); err != nil || p != 0 {
		t.Fatalf("Pending = %d, %v", p, err)
	}

	reverted, err := m.Down(ctx, len(applied))
	if err != nil || len(reverted) != len(applied) {
		t.Fatalf("Down: %v %v", reverted, err)
	}
	if n := countTables(t, pool); n != 0 {
		t.Fatalf("após down restaram %d tabelas", n)
	}
	st, err := m.Status(ctx)
	if err != nil {
		t.Fatal(err)
	}
	for _, s := range st {
		if s.AppliedAt != nil {
			t.Errorf("%04d ainda marcada como aplicada", s.Version)
		}
	}

	if _, err := m.Up(ctx); err != nil {
		t.Fatalf("Up após Down: %v", err)
	}
	if n := countTables(t, pool); n != len(want) {
		t.Errorf("reaplicação: esperava %d tabelas, há %d", len(want), n)
	}
}

// TestMigrateConcurrent: várias instâncias migrando ao mesmo tempo não colidem (advisory lock).
func TestMigrateConcurrent(t *testing.T) {
	pool := newPool(t)
	ctx := context.Background()
	const workers = 4
	var wg sync.WaitGroup
	results := make([][]int64, workers)
	errs := make([]error, workers)
	for i := range workers {
		wg.Add(1)
		go func() {
			defer wg.Done()
			results[i], errs[i] = newMigrator(t, pool).Up(ctx)
		}()
	}
	wg.Wait()
	total := 0
	for i := range workers {
		if errs[i] != nil {
			t.Fatalf("worker %d: %v", i, errs[i])
		}
		total += len(results[i])
	}
	ms, _ := persistence.LoadMigrations(migrations.FS)
	if total != len(ms) {
		t.Fatalf("cada migration deve ser aplicada uma única vez: total %d, esperado %d", total, len(ms))
	}
}

func TestMigrateRejectsUnknownVersion(t *testing.T) {
	pool := newPool(t)
	m := newMigrator(t, pool)
	ctx := context.Background()
	if _, err := m.Up(ctx); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `INSERT INTO schema_migrations (version, name) VALUES (9999, 'futura')`); err != nil {
		t.Fatal(err)
	}
	if _, err := m.Up(ctx); err == nil || !strings.Contains(err.Error(), "9999") {
		t.Fatalf("esperava erro de versão desconhecida, veio %v", err)
	}
}

func TestMigrationFailureRollsBack(t *testing.T) {
	pool := newPool(t)
	ctx := context.Background()
	bad := []persistence.Migration{
		{Version: 1, Name: "ok", Up: "CREATE TABLE a (id int)", Down: "DROP TABLE a"},
		{Version: 2, Name: "quebrada", Up: "CREATE TABLE b (id int); SELECT * FROM nao_existe", Down: "DROP TABLE b"},
	}
	m := persistence.NewMigrator(pool, bad, nil)
	applied, err := m.Up(ctx)
	if err == nil || !strings.Contains(err.Error(), "0002_quebrada") {
		t.Fatalf("esperava falha em 0002, veio %v", err)
	}
	if len(applied) != 1 {
		t.Fatalf("0001 deveria ter sido aplicada: %v", applied)
	}
	var exists bool
	_ = pool.QueryRow(ctx, `SELECT to_regclass('b') IS NOT NULL`).Scan(&exists)
	if exists {
		t.Fatal("tabela b não deveria existir: a transação da 0002 devia ter sido revertida")
	}
	if p, _ := m.Pending(ctx); p != 1 {
		t.Fatalf("Pending = %d, esperado 1", p)
	}
}
