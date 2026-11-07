package persistence

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"log/slog"
	"regexp"
	"sort"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// migrationLockKey identifica o pg_advisory_lock das migrations ("BlastGri").
const migrationLockKey int64 = 0x426C617374477269

var migrationFile = regexp.MustCompile(`^(\d{4})_([a-z0-9_]+)\.(up|down)\.sql$`)

// Migration é um par up/down carregado dos arquivos NNNN_nome.{up,down}.sql.
type Migration struct {
	Version int64
	Name    string
	Up      string
	Down    string
}

// MigrationStatus descreve uma migration conhecida pelo binário.
type MigrationStatus struct {
	Migration
	AppliedAt *time.Time // nil = pendente
}

// LoadMigrations lê e valida as migrations de fsys (raiz do FS): exige pares
// up/down, nomes no padrão, versões únicas e contíguas a partir de 1.
func LoadMigrations(fsys fs.FS) ([]Migration, error) {
	entries, err := fs.ReadDir(fsys, ".")
	if err != nil {
		return nil, fmt.Errorf("ler migrations: %w", err)
	}
	byVersion := map[int64]*Migration{}
	for _, e := range entries {
		if e.IsDir() || e.Name() == "migrations.go" {
			continue
		}
		m := migrationFile.FindStringSubmatch(e.Name())
		if m == nil {
			if len(e.Name()) > 4 && e.Name()[len(e.Name())-4:] == ".sql" {
				return nil, fmt.Errorf("migration com nome inválido: %s (esperado NNNN_nome.up|down.sql)", e.Name())
			}
			continue
		}
		v, _ := strconv.ParseInt(m[1], 10, 64)
		body, err := fs.ReadFile(fsys, e.Name())
		if err != nil {
			return nil, err
		}
		mg := byVersion[v]
		if mg == nil {
			mg = &Migration{Version: v, Name: m[2]}
			byVersion[v] = mg
		} else if mg.Name != m[2] {
			return nil, fmt.Errorf("versão %04d com nomes diferentes: %q e %q", v, mg.Name, m[2])
		}
		if m[3] == "up" {
			mg.Up = string(body)
		} else {
			mg.Down = string(body)
		}
	}
	out := make([]Migration, 0, len(byVersion))
	for _, mg := range byVersion {
		if mg.Up == "" || mg.Down == "" {
			return nil, fmt.Errorf("migration %04d_%s sem par up/down (ou arquivo vazio)", mg.Version, mg.Name)
		}
		out = append(out, *mg)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Version < out[j].Version })
	for i, mg := range out {
		if mg.Version != int64(i+1) {
			return nil, fmt.Errorf("migrations devem ser contíguas a partir de 0001: faltando %04d", i+1)
		}
	}
	return out, nil
}

// Migrator aplica e reverte migrations com lock consultivo, cada uma na sua transação.
type Migrator struct {
	pool       *pgxpool.Pool
	migrations []Migration
	log        *slog.Logger
}

// NewMigrator cria o runner. log pode ser nil.
func NewMigrator(pool *pgxpool.Pool, migrations []Migration, log *slog.Logger) *Migrator {
	if log == nil {
		log = slog.New(slog.DiscardHandler)
	}
	return &Migrator{pool: pool, migrations: migrations, log: log}
}

// Up aplica todas as pendentes em ordem e devolve as versões aplicadas.
func (m *Migrator) Up(ctx context.Context) ([]int64, error) {
	var done []int64
	err := m.locked(ctx, func(conn *pgx.Conn) error {
		applied, err := appliedVersions(ctx, conn)
		if err != nil {
			return err
		}
		if err := m.checkKnown(applied); err != nil {
			return err
		}
		for _, mg := range m.migrations {
			if _, ok := applied[mg.Version]; ok {
				continue
			}
			start := time.Now()
			err := WithTx(ctx, conn, func(tx pgx.Tx) error {
				if _, err := tx.Exec(ctx, mg.Up); err != nil {
					return err
				}
				_, err := tx.Exec(ctx, `INSERT INTO schema_migrations (version, name) VALUES ($1, $2)`, mg.Version, mg.Name)
				return err
			})
			if err != nil {
				return fmt.Errorf("aplicar %04d_%s: %w", mg.Version, mg.Name, err)
			}
			m.log.Info("migrate: aplicada", "version", mg.Version, "name", mg.Name, "took", time.Since(start).String())
			done = append(done, mg.Version)
		}
		return nil
	})
	return done, err
}

// Down reverte as n últimas migrations aplicadas (n ≥ 1) e devolve as versões revertidas.
func (m *Migrator) Down(ctx context.Context, n int) ([]int64, error) {
	if n < 1 {
		return nil, errors.New("down: n deve ser ≥ 1")
	}
	var done []int64
	err := m.locked(ctx, func(conn *pgx.Conn) error {
		applied, err := appliedVersions(ctx, conn)
		if err != nil {
			return err
		}
		if err := m.checkKnown(applied); err != nil {
			return err
		}
		for i := len(m.migrations) - 1; i >= 0 && len(done) < n; i-- {
			mg := m.migrations[i]
			if _, ok := applied[mg.Version]; !ok {
				continue
			}
			err := WithTx(ctx, conn, func(tx pgx.Tx) error {
				if _, err := tx.Exec(ctx, mg.Down); err != nil {
					return err
				}
				_, err := tx.Exec(ctx, `DELETE FROM schema_migrations WHERE version = $1`, mg.Version)
				return err
			})
			if err != nil {
				return fmt.Errorf("reverter %04d_%s: %w", mg.Version, mg.Name, err)
			}
			m.log.Info("migrate: revertida", "version", mg.Version, "name", mg.Name)
			done = append(done, mg.Version)
		}
		return nil
	})
	return done, err
}

// Status lista todas as migrations do binário com a data de aplicação.
func (m *Migrator) Status(ctx context.Context) ([]MigrationStatus, error) {
	var out []MigrationStatus
	err := m.locked(ctx, func(conn *pgx.Conn) error {
		applied, err := appliedVersions(ctx, conn)
		if err != nil {
			return err
		}
		if err := m.checkKnown(applied); err != nil {
			return err
		}
		for _, mg := range m.migrations {
			st := MigrationStatus{Migration: mg}
			if at, ok := applied[mg.Version]; ok {
				st.AppliedAt = &at
			}
			out = append(out, st)
		}
		return nil
	})
	return out, err
}

// Pending informa quantas migrations ainda não foram aplicadas.
func (m *Migrator) Pending(ctx context.Context) (int, error) {
	st, err := m.Status(ctx)
	if err != nil {
		return 0, err
	}
	n := 0
	for _, s := range st {
		if s.AppliedAt == nil {
			n++
		}
	}
	return n, nil
}

// checkKnown recusa operar se o banco tem versões que este binário não conhece
// (binário mais antigo que o esquema).
func (m *Migrator) checkKnown(applied map[int64]time.Time) error {
	known := make(map[int64]bool, len(m.migrations))
	for _, mg := range m.migrations {
		known[mg.Version] = true
	}
	for v := range applied {
		if !known[v] {
			return fmt.Errorf("o banco tem a migration %04d, desconhecida por este binário (binário desatualizado?)", v)
		}
	}
	return nil
}

// locked reserva uma conexão, cria schema_migrations se preciso e segura o
// pg_advisory_lock de sessão durante fn, para que duas instâncias não migrem juntas.
func (m *Migrator) locked(ctx context.Context, fn func(conn *pgx.Conn) error) error {
	c, err := m.pool.Acquire(ctx)
	if err != nil {
		return fmt.Errorf("migrate: conexão: %w", err)
	}
	defer c.Release()
	conn := c.Conn()
	if _, err := conn.Exec(ctx, `SELECT pg_advisory_lock($1)`, migrationLockKey); err != nil {
		return fmt.Errorf("migrate: lock: %w", err)
	}
	defer func() {
		if _, err := conn.Exec(context.WithoutCancel(ctx), `SELECT pg_advisory_unlock($1)`, migrationLockKey); err != nil {
			// Sem unlock a sessão segura o lock; descartar a conexão o libera.
			_ = conn.Close(context.WithoutCancel(ctx))
		}
	}()
	if _, err := conn.Exec(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (
		version    bigint PRIMARY KEY,
		name       text NOT NULL,
		applied_at timestamptz NOT NULL DEFAULT now()
	)`); err != nil {
		return fmt.Errorf("migrate: criar schema_migrations: %w", err)
	}
	return fn(conn)
}

func appliedVersions(ctx context.Context, conn *pgx.Conn) (map[int64]time.Time, error) {
	rows, err := conn.Query(ctx, `SELECT version, applied_at FROM schema_migrations`)
	if err != nil {
		return nil, fmt.Errorf("migrate: ler schema_migrations: %w", err)
	}
	out := map[int64]time.Time{}
	var v int64
	var at time.Time
	_, err = pgx.ForEachRow(rows, []any{&v, &at}, func() error {
		out[v] = at
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("migrate: ler schema_migrations: %w", err)
	}
	return out, nil
}
