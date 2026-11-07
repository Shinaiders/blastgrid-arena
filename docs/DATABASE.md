# BlastGrid Arena — Banco de dados

Versão 1.1 (2026-11-06). Status: **implementado** em `server/migrations/0001_init` (Dia 04), com runner
em `server/internal/persistence`. Decisões: ARCHITECTURE D-06 (PostgreSQL ≥ 16 + pgx/pgxpool), D-07 (migrations
SQL próprias), D-16 (estado de partida só em memória).

## 1. Princípios

- PostgreSQL guarda **contas, perfis, catálogo, inventário, resultados e agregados** — nunca o estado
  tick a tick de uma partida.
- A partida vive em memória na goroutine da sala; ao terminar, o resultado é gravado em **uma transação**
  (`matches` + `match_players` + `player_statistics` + `rankings`).
- Leituras quentes (ranking, perfil) são servidas por índices; nada de `COUNT(*)` ou `ORDER BY` sem índice
  em tabelas que crescem.
- Sem Redis até existir necessidade real (várias instâncias, filas, presença compartilhada).

## 2. Convenções

| Item | Convenção |
|---|---|
| Chaves primárias | `bigint GENERATED ALWAYS AS IDENTITY` internas; ids públicos expostos na API/protocolo com prefixo (`u_31`, `m_77`) |
| Tempo | `timestamptz`, sempre UTC; colunas `created_at`/`updated_at` com `DEFAULT now()` |
| Texto | `text` + `CHECK` de tamanho (não `varchar(n)`) |
| Enums | `text` + `CHECK (col IN (...))` — mais fácil de migrar que `CREATE TYPE` |
| Ids de catálogo | `text` estável (`sparky_a`, `range_up`) para coincidir com o cliente e o protocolo |
| Exclusão | `ON DELETE CASCADE` só de dono → dependentes (usuário → perfil, inventário); resultados de partida usam `ON DELETE SET NULL` para preservar histórico |
| Nomes | `snake_case`, tabelas no plural |

## 3. Tabelas

### users
Conta de autenticação, independente de plataforma.

| Coluna | Tipo | Notas |
|---|---|---|
| id | bigint PK | |
| email | text NULL | único (case-insensitive, índice em `lower(email)`); NULL para convidado |
| password_hash | text NULL | argon2id (formato PHC); NULL para convidado/Steam-only |
| steam_id | bigint NULL | único; preenchido **só** após validar Steam Auth Ticket no backend (Fase 6) |
| kind | text | `registered` \| `guest` |
| status | text | `active` \| `banned` \| `deleted` |
| created_at, updated_at, last_login_at | timestamptz | |

### user_profiles
1:1 com `users`. Dados exibidos publicamente.

| Coluna | Tipo | Notas |
|---|---|---|
| user_id | bigint PK FK users | |
| display_name | text | 3–20 chars, único case-insensitive |
| avatar | text NULL | id de asset do jogo, não URL externa |
| selected_character | text FK characters | |
| selected_skin | text FK skins NULL | |
| country | text NULL | ISO-3166 alfa-2 opcional |

### characters / skins (catálogo)
`characters(id text PK, name, base_speed int, base_bombs int, base_range int, enabled bool)` — stats em
unidades da simulação (militiles/tick). Inicialmente todos iguais (GDD §4).
`skins(id text PK, character_id FK, name, rarity text CHECK, enabled bool)` — puramente visual.
Catálogo é populado pela própria migration (dados de seed versionados).

### player_inventory
`(user_id FK, item_kind text CHECK IN ('character','skin'), item_id text, acquired_at, source text)`,
PK `(user_id, item_kind, item_id)`. Sem moeda/pagamento na fase atual.

### matches
| Coluna | Tipo | Notas |
|---|---|---|
| id | bigint PK | |
| mode | text | `ffa` \| `team` \| `lms` \| `practice` (practice offline não é gravado) |
| seed | bigint | seed u32 do mapa (reprodutibilidade/depuração) |
| tick_rate | smallint | |
| started_at, ended_at | timestamptz | |
| duration_ticks | int | |
| end_reason | text | `last_alive` \| `time_up` \| `draw` \| `aborted` |
| winner_user_id | bigint NULL FK users SET NULL | |
| server_version | text | versão do binário que arbitrou |

### match_players
PK `(match_id, slot)`; `user_id` FK SET NULL; `place smallint`, `score int`, `kills`, `deaths`, `blocks`,
`powerups smallint`, `platform text` (`web|windows|linux|macos`), `disconnected bool`,
`rating_before int`, `rating_after int`.

### player_statistics
Agregado por usuário (1 linha), atualizado na transação de fim de partida:
`user_id PK`, `matches_played`, `wins`, `draws`, `kills`, `deaths`, `blocks_destroyed`,
`powerups_collected`, `best_score`, `total_score bigint`, `play_time_ticks bigint`, `updated_at`.

### rankings
Rating por temporada e modo, para permitir resets sem perder histórico.

| Coluna | Tipo | Notas |
|---|---|---|
| season | smallint | temporada (1 na v1) |
| mode | text | |
| user_id | bigint FK users CASCADE | |
| rating | int | inicial 1000; algoritmo multi-jogador (Elo par a par) definido na Fase 4 |
| matches, wins | int | |
| updated_at | timestamptz | |

PK `(season, mode, user_id)`.

### achievements
Catálogo `achievements(id text PK, name, description, hidden bool)` + progresso
`player_achievements(user_id, achievement_id, progress int, unlocked_at timestamptz NULL)`,
PK `(user_id, achievement_id)`. (A segunda tabela faz parte de "achievements" no briefing; os ids
coincidem com os de conquistas da Steam na Fase 6.)

### Planejadas para a Fase 3 (fora do Dia 04)
- `auth_sessions(id, user_id, refresh_token_hash bytea, user_agent, platform, created_at, expires_at,
  revoked_at)` — tokens de renovação guardados só como hash (SHA-256), rotação a cada uso.
(`schema_migrations(version bigint PK, name text, applied_at timestamptz)` já existe: é criada pelo runner.)

## 4. Índices

| Índice | Consulta atendida |
|---|---|
| `rankings (season, mode, rating DESC, user_id)` | top N e paginação por keyset (`WHERE (rating, user_id) < ($1,$2)`) |
| `users (lower(email)) UNIQUE WHERE email IS NOT NULL` | login |
| `users (steam_id) UNIQUE WHERE steam_id IS NOT NULL` | login Steam |
| `user_profiles (lower(display_name)) UNIQUE` | unicidade e busca de jogador |
| `match_players (user_id, match_id DESC)` | histórico do jogador |
| `matches (ended_at DESC)` | partidas recentes / limpeza |

Posição de um jogador no ranking: `COUNT(*) WHERE season=$1 AND mode=$2 AND rating > $3` usando o mesmo
índice (index-only scan). Se ficar caro com muitos jogadores, materializar faixas por job periódico.

## 5. Transações

- Fim de partida: `BEGIN` → `INSERT matches` → `INSERT match_players` (batch `pgx.Batch`) → `UPSERT
  player_statistics` → `UPSERT rankings` com `SELECT ... FOR UPDATE` das linhas dos participantes em ordem
  de `user_id` (evita deadlock) → `COMMIT`. Falha ⇒ retry até 3× para `serialization_failure`/`deadlock`;
  persistindo, o resultado é logado em JSON para reprocessamento.
- Helper único `persistence.WithTx(ctx, pool, func(pgx.Tx) error)` para todas as escritas multi-tabela.
- Nível de isolamento padrão `READ COMMITTED`; o lock explícito cobre a atualização de rating.

## 6. Migrations

- Arquivos `server/migrations/NNNN_descricao.up.sql` e `.down.sql` (4 dígitos, sequenciais).
- Runner próprio em Go (D-07): lê os arquivos (embutidos com `embed.FS`), aplica os pendentes em ordem,
  cada um na sua transação, registra em `schema_migrations`; usa `pg_advisory_lock` para que duas
  instâncias não migrem ao mesmo tempo.
- Execução: subcomando `api migrate up|down N|status` e, opcionalmente, na inicialização com
  `BG_MIGRATE_ON_START=true` (dev).
- No compose, o serviço `migrate` (mesma imagem, `command: migrate up`) roda antes da API.
- O runner recusa operar se o banco tiver uma versão que o binário não conhece (binário desatualizado)
  e exige versões contíguas a partir de 0001 com par up/down.
- Toda migration precisa de `down` funcional; o teste de integração aplica tudo, reverte tudo e aplica de novo.
- Testes de integração: `BG_TEST_DATABASE_URL` aponta para um banco descartável; cada teste cria um schema
  próprio (`internal/persistence/pgtest`) e o remove ao final. Sem a variável, os testes de banco são pulados.

### 0001_init — notas de implementação
- Seed de catálogo: 4 personagens `sparky_a..d` (Volt, Ember, Moss, Frost) com stats iguais (200
  militiles/tick = 4,0 tiles/s a 20 Hz, 1 bomba, alcance 2 — GDD §4–5), uma skin `*_default` cada e 3
  conquistas iniciais.
- `rankings.mode` aceita só modos ranqueados (`ffa`, `team`, `lms`); `matches.mode` aceita também `practice`.
- `match_players.slot` 0–7 e `place` 1–8 (até 8 jogadores).
- Índice de ranking `rankings_leaderboard_idx (season, mode, rating DESC, user_id DESC)`: o teste
  `TestLeaderboardUsesIndex` confirma via `EXPLAIN` que o top N/keyset usa o índice sem `Sort`.
- Migrations já publicadas nunca são editadas — corrige-se com uma nova.

## 7. Conexão (pgxpool)

| Variável | Padrão | Uso |
|---|---|---|
| `BG_DATABASE_URL` | — (obrigatória fora de dev) | DSN `postgres://user:pass@host:5432/db?sslmode=...` |
| `BG_DB_MAX_CONNS` | 10 | `pool_max_conns` |
| `BG_DB_MIN_CONNS` | 1 | |
| `BG_DB_CONNECT_TIMEOUT` | 5s | timeout de conexão |

Toda query recebe `context` com timeout (padrão 3 s). `/readyz` executa `pool.Ping` com timeout de 1 s.

## 8. Retenção e backup

- `match_players`/`matches`: mantidos indefinidamente na v1 (volume pequeno: ~1 KB/partida).
- Convidados sem partidas há 30 dias: limpeza por job (Fase 4).
- Backup: `pg_dump -Fc` diário com retenção de 7 dias (DEPLOYMENT.md).
