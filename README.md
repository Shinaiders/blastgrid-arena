# BlastGrid Arena

Jogo 2D multiplayer competitivo de arena em grid (bombas, explosões em cruz, power-ups), com identidade visual original.

- **Cliente:** Godot 4 (GDScript, renderer Compatibility) — Web (WASM/WebGL 2, single-thread), Windows, Linux, macOS opcional.
- **Servidor:** Go (`net/http`, `github.com/coder/websocket`, `pgx`), autoritativo, um único serviço modular.
- **Banco:** PostgreSQL com migrations SQL versionadas.
- **Infra:** Docker / Docker Compose, logs estruturados, health checks, configuração por env vars.

Tudo gratuito/open source. Nenhum serviço pago é dependência.

## Estado atual

Todas as Fases 1 a 7 implementadas e validadas com testes automatizados em Go e no Godot 4 headless:
- **Fase 1 (Fundação — Dias 01 a 05):** Backend Go (`internal/config`, `internal/logging`, `internal/httpapi`, `internal/persistence`), migrations PostgreSQL (`0001_init`, `0002_auth_sessions`), Docker Compose e projeto Godot 4 (`client/project.godot`, `export_presets.cfg`).
- **Fase 2 (Protótipo jogável offline — Dias 06 a 14):** Simulação determinística em militiles e `xorshift32` (`client/scripts/rules/`), renderização procedural de Sparkies/caixotes/petardos (`client/scripts/gameplay/arena_renderer.gd`), 3 bots com mapa de perigo e BFS (`client/scripts/ai/bot_brain.gd`), HUD competitivo e todas as 13 telas navegáveis (`client/scripts/core/main.gd`).
- **Fases 3 e 4 (Servidor Go autoritativo e Multiplayer competitivo):** Regras idênticas em Go (`server/internal/game/rules`) passando nos mesmos cenários `tests/scenarios/*.json`, codec/rate-limit/anti-replay e dispatcher WebSocket RFC 6455 do protocolo v1 (`server/internal/websocket`, `client/scripts/networking/{protocol,transport,ws_transport,net_session,net_sync}.gd`, `tests/protocol/01_envelope.json`), autenticação HMAC/convidado (`server/internal/auth`), salas públicas/privadas de 4–8 jogadores com reconexão em 30s e Elo (`server/internal/game/rooms`), persistência transacional de partidas (`server/internal/persistence/match_store.go`) e rotas REST `/v1/*` + `GET /ws` (`server/internal/httpapi/api_routes.go`).
- **Fases 5, 6 e 7 (Cross-platform, Steam e Publicação):** Síntese procedural de efeitos sonoros PCM 16-bit com desbloqueio Web (`client/scripts/core/sfx_synth.gd`), persistência de configurações e keybinds (`client/scripts/core/settings_store.gd`), isolamento de Steamworks (`client/scripts/platform/steam_bridge.gd`, `server/internal/platform/steam.go`, `POST /v1/auth/steam`), benchmark de orçamento de CPU 20 Hz (`server/internal/game/rules/bench_test.go`), proxy reverso (`deploy/Caddyfile`), script de exportação Web (`scripts/export-web.sh`) e CI/CD (`.github/workflows/ci.yml`).

Ver `docs/ROADMAP_DIARIO.md` para o registro detalhado de cada etapa e `docs/ROADMAP.md` para a visão por fases.

## Estrutura (alvo)

```
client/   projeto Godot 4
server/   backend Go (cmd/api, internal/..., migrations/)
docs/     GDD, arquitetura, protocolo, banco, deploy, compatibilidade
scripts/  utilitários de ambiente
```

Diretórios só são criados quando recebem código real (regra do briefing: nada de módulos vazios).

## Documentação

| Documento | Conteúdo |
|---|---|
| `docs/PROJECT_BRIEF.md` | Briefing completo e regras de trabalho |
| `docs/GDD.md` | Game design: regras, modos, power-ups, bots |
| `docs/ARCHITECTURE.md` | Arquitetura cliente/servidor e decisões técnicas |
| `docs/NETWORK_PROTOCOL.md` | Protocolo WebSocket v1 (JSON): envelope, seq/ack, ticks, relógio, reconexão, limites |
| `docs/MULTIPLAYER.md` | Servidor autoritativo, loop de ticks, predição/reconciliação, salas, escala |
| `docs/DATABASE.md` | Modelo PostgreSQL, índices de ranking, transações, migrations |
| `docs/PLATFORM_COMPATIBILITY.md` | Matriz de plataformas, restrições Web/macOS/Steam, plano de testes |
| `docs/DEPLOYMENT.md` | Variáveis de ambiente, health checks, Docker, produção com TLS, backup |
| `docs/ROADMAP.md` | Fases 1–7 |
| `docs/ROADMAP_DIARIO.md` | Etapas diárias das Fases 1–2 e registro de execução |

## Ambiente de desenvolvimento

Versões de referência (verificadas em 2026-11-05/06): Go 1.27.3, Godot 4.7.2-stable, PostgreSQL 16, pgx v5.12.0, Git 2.34+.

Na VM Linux usada pela automação diária (sem root):

```bash
scripts/setup-dev-vm.sh            # instala Go, Godot e PostgreSQL 16 em ~/tools
source <(scripts/setup-dev-vm.sh env)
scripts/setup-dev-vm.sh pg-start   # sobe o PostgreSQL local (127.0.0.1:55432) na mesma chamada dos testes
```

Em máquina própria, instale Go ≥ 1.27, Godot 4.7.x stable, Docker e PostgreSQL ≥ 16 normalmente.

### Backend

```bash
cd server
go run ./cmd/api                     # escuta em :8080 (BG_HTTP_ADDR); sem BG_DATABASE_URL sobe sem banco (só dev)
curl localhost:8080/healthz
go vet ./... && go test ./...        # CC=gcc CGO_ENABLED=1 go test -race ./... para o detector de corrida
# testes de integração com banco: defina BG_TEST_DATABASE_URL (senão são pulados)
```

### Docker

```bash
docker compose up --build            # PostgreSQL 16 → migrations → API em http://localhost:8080
docker compose run --rm migrate      # reaplicar migrations; status: docker compose run --rm api migrate status
```
