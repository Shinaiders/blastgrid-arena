# BlastGrid Arena — Roadmap diário (Fases 1 e 2)

Uma etapa por dia, executada pela tarefa agendada das 08h.
Regra: executar **somente a primeira etapa não marcada**, testar, marcar `[x]` com data e notas, commitar e parar.
Briefing completo: `docs/PROJECT_BRIEF.md`.

## FASE 1 — Fundação

- [x] **Dia 01 — Ambiente e base do repositório** (2026-11-05)
  Verificar Godot 4 (estável), Go, Docker, PostgreSQL, Git (instalar no ambiente se faltar e registrar versões).
  `git init`, `.gitignore`, `README.md`. Criar `docs/GDD.md`, `docs/ARCHITECTURE.md`, `docs/ROADMAP.md` com as decisões técnicas e incompatibilidades encontradas.

- [x] **Dia 02 — Documentação técnica** (2026-11-06)
  `docs/NETWORK_PROTOCOL.md` (v1 JSON, envelope, seq de comandos, ticks), `docs/DATABASE.md`, `docs/MULTIPLAYER.md`, `docs/PLATFORM_COMPATIBILITY.md`, `docs/DEPLOYMENT.md`.

- [x] **Dia 03 — Backend Go mínimo** (2026-11-06)
  `server/go.mod`, `cmd/api/main.go`, `internal/config` (env vars), logs estruturados (`log/slog`), `internal/http` com `GET /healthz` e `GET /readyz`, timeouts, graceful shutdown. Testes `go test ./...` e `go vet`.

- [x] **Dia 04 — PostgreSQL, migrations e Docker** (2026-11-07)
  Migrations SQL versionadas (users, user_profiles, characters, skins, matches, match_players, rankings, player_statistics, achievements, player_inventory + índices de ranking). Conexão pgx com pool, readiness checando o banco. `server/Dockerfile` multi-stage, `docker-compose.yml`, `.env.example`. Validar subida e health check.

- [ ] **Dia 05 — Projeto Godot**
  `client/project.godot` (Godot 4, renderer Compatibility), input map (WASD, setas, espaço, ESC, gamepad), presets de exportação Web (single-thread), Windows, Linux e macOS (Universal, sem assinatura). Cena `main` mínima. Validar import headless.

## FASE 2 — Primeiro protótipo jogável (offline)

- [ ] **Dia 06 — Regras do grid**
  Grid 15x13, tipos de tile, geração com paredes fixas e blocos destrutíveis variáveis, cantos de spawn livres. Script de regras puro (sem nós) + testes headless. Cenários de conformidade em `tests/scenarios/*.json` (compartilháveis com o Go).

- [ ] **Dia 07 — Personagem e movimentação**
  Movimento em 4 direções, suave e alinhado ao grid (corner sliding), colisões precisas. Testes.

- [ ] **Dia 08 — Bombas**
  Colocação, detonação em 2,5 s, limite por jogador, bomba bloqueia passagem exceto para quem acabou de colocá-la (anti-prisão). Testes.

- [ ] **Dia 09 — Explosões**
  Explosão em cruz com alcance configurável, destruição de blocos, reação em cadeia, eliminação de jogadores. Testes de cadeia e eliminação.

- [ ] **Dia 10 — Power-ups**
  Drop ao destruir blocos; alcance, +bombas, velocidade, escudo temporário; sistema expansível (Resource por power-up). Testes.

- [ ] **Dia 11 — Visual original**
  Sprites placeholder originais (gerados/desenhados no projeto), animações de caminhada/vitória/derrota, partículas de explosão, cores por jogador.

- [ ] **Dia 12 — Bots**
  3 bots: mapa de perigo, rotas seguras (BFS), fuga de explosões, bombas estratégicas, coleta de power-ups, busca de adversários.

- [ ] **Dia 13 — HUD e fluxo de partida**
  Modos Practice e Free For All local (1 jogador + 3 bots): cronômetro, vivos, eliminações, pontuação, power-ups; pausa; condição de vitória; tela de resultado.

- [ ] **Dia 14 — Menus, export Web e fechamento**
  Splash, tela inicial, seleção de modo. Exportar Web e validar build. Atualizar docs e ROADMAP com o que foi implementado e o que ficou pendente para a Fase 3.

## Registro de execução

<!-- A tarefa diária adiciona aqui: data — etapa — resultado dos testes — observações -->
- 2026-11-05 — Dia 01 — Go 1.27.3 (conda-forge) e Godot 4.7.2-stable (GitHub, SHA-512 ok) instalados em ~/tools via `scripts/setup-dev-vm.sh`, validado em instalação limpa; `go run` de teste ok; `godot --headless --version` ok; Git 2.34.1. `git init`, .gitignore, README, GDD, ARCHITECTURE, ROADMAP criados. Nenhum teste de código (ainda não há código). — Pendências: Docker e PostgreSQL indisponíveis na VM (sem root, Docker Hub bloqueado) → validar compose no Mac no Dia 04; proxy.golang.org/sum.golang.org/gopkg.in bloqueados → GOPROXY=direct, GOSUMDB=off e resolver gopkg.in/yaml.v3 (dep transitiva do pgx) no Dia 04.
- 2026-11-06 — Dia 02 — Criados NETWORK_PROTOCOL.md (v1 JSON: envelope v/t/seq/ack/data, subprotocolo `blastgrid.v1`, hello/resume, ping/pong NTP, input/state/eventos, limites 4 KiB e 40 msg/s, close codes 4001–4005), DATABASE.md, MULTIPLAYER.md, PLATFORM_COMPATIBILITY.md, DEPLOYMENT.md (env vars `BG_*`); links no README/ARCHITECTURE. Validação: script Python conferiu os 8 blocos JSON de exemplo (todos parseiam) e referências entre docs (ok); conversões de regras para ticks a 20 Hz conferidas à mão. Sem testes de código (etapa só de documentação). — Pendências: as mesmas do Dia 01 (Docker/PostgreSQL fora da VM, gopkg.in bloqueado); fixtures `tests/protocol/` e tabela `auth_sessions` ficam para a Fase 3.
  - Obs. Dia 02: commit f8faaa6 gravado, mas o git deixou `.git/HEAD.lock` e `.git/objects/maintenance.lock` (exclusão bloqueada na VM). Remover no Mac (`rm .git/HEAD.lock .git/objects/maintenance.lock`) antes do próximo commit; esta nota ficou fora do commit.
- 2026-11-06 — Dia 03 — `server/` criado: módulo `github.com/Shinaiders/blastgrid-arena/server` (go 1.27, sem dependências externas), `cmd/api` (signal.NotifyContext, graceful shutdown com `BG_SHUTDOWN_TIMEOUT`), `internal/config` (BG_ENV, BG_HTTP_ADDR, BG_LOG_LEVEL/FORMAT, timeouts; erros agregados), `internal/logging` (slog JSON/text), `internal/httpapi` (`GET /healthz`, `GET /readyz` com checks plugáveis e 503 durante drenagem, X-Request-ID, log de acesso, recover, limite de corpo 1 MiB, timeouts do http.Server). Testes executados na VM (Go 1.27.3 arm64): `gofmt -l` limpo; `go vet ./...` ok; `go test -count=3 ./...` ok (4 pacotes, 13 testes, incl. shutdown com requisição em andamento e processo ponta a ponta em porta efêmera); `CC=gcc CGO_ENABLED=1 go test -race ./...` ok; smoke com binário real: /healthz 200, /readyz 200, SIGTERM → exit 0 com logs de encerramento; `BG_ENV=prod BG_LOG_FORMAT=text` → exit 1. Também: `.gitignore` recriado (não estava no repositório reenviado), `CC=gcc` no `setup-dev-vm.sh`, ARCHITECTURE/README atualizados (pacote `httpapi` em vez de `http` para não colidir com net/http). — Pendências: `.DS_Store` está versionado (remover com `git rm --cached .DS_Store`); readiness do banco, Docker e `.env.example` no Dia 04; Docker/PostgreSQL e gopkg.in seguem indisponíveis na VM.
  - Obs. Dia 03: commit a669c41 gravado, mas o git deixou `.git/HEAD.lock`, `.git/objects/maintenance.lock` e ~28 `.git/objects/??/tmp_obj_*` (exclusão bloqueada na VM; a limpeza automática foi negada). Antes do próximo commit, no Mac: `rm .git/HEAD.lock .git/objects/maintenance.lock && find .git/objects -name 'tmp_obj_*' -delete`. Esta nota ficou fora do commit.
- 2026-11-07 — Dia 04 — Concluído o trabalho iniciado em 2026-11-06 (sem commit naquela execução): `server/migrations/0001_init` (users, user_profiles, characters, skins, matches, match_players, rankings, player_statistics, achievements + player_achievements, player_inventory; índice `rankings_leaderboard_idx`; seed de 4 personagens/skins/3 conquistas), runner próprio em `internal/persistence` (embed.FS, pg_advisory_lock, transação por migration, recusa versão desconhecida), `WithTx` com retry 40001/40P01, pool pgxpool (pgx v5.12.0) e `/readyz` checando o banco; subcomandos `api migrate up|down [N]|status` e `api healthcheck`; `server/Dockerfile` multi-stage (golang:1.27-alpine → distroless nonroot), `docker-compose.yml` (db → migrate → api), `.env.example`. Ambiente reinstalado (VM nova): Go 1.27.3, Godot 4.7.2-stable, PostgreSQL 16.15 (conda-forge), Git 2.34.1; `setup-dev-vm.sh` agora chama `vm-gomirror.sh` via `bash` (mount sem bit de execução). Testes executados na VM: `go mod verify` ok; `gofmt -l` limpo; `go vet ./...` ok; `go test -count=1 -v ./...` ok com `BG_TEST_DATABASE_URL` no PostgreSQL 16 local (5 pacotes; 9 testes de banco rodaram, nenhum pulado: up/down/up, migração concorrente, versão desconhecida, rollback de migration com erro, constraints/seed, ranking via índice sem Sort no EXPLAIN, WithTx); `go test -race ./...` ok. Smoke com binário estático (`CGO_ENABLED=0`, mesmo comando do Dockerfile): `migrate status` pendente → `migrate up` aplica 0001 → reexecução idempotente (0 aplicadas) → 12 tabelas; `/healthz` 200, `/readyz` 200 com banco e 503 com o PostgreSQL parado; `api healthcheck` exit 0; SIGTERM → exit 0. `docker-compose.yml` validado só como YAML (serviços e depends_on). Limpeza: removidos os `.lock`/`tmp_obj_*` antigos do `.git` e um temporário do gofmt versionado por engano (`server/internal/httpapi/server.go.<n>`); `.DS_Store` saiu do índice. — Pendências: **Docker não existe na VM** → `docker compose up --build` e o build da imagem não foram executados; validar no Mac (`docker compose up --build` e `curl localhost:8080/readyz`). `/readyz` 503 é logado como ERROR (avaliar WARN).
