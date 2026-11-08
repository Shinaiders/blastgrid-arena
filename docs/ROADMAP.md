# BlastGrid Arena — Roadmap por fases

Detalhamento diário das Fases 1 e 2: `docs/ROADMAP_DIARIO.md` (inclui o registro de execução).
Status: ⬜ não iniciado · 🟨 em andamento · ✅ concluído.

| Fase | Objetivo | Status |
|---|---|---|
| 1 — Fundação | Ambiente, docs, backend Go mínimo com health checks, PostgreSQL + migrations, Docker, projeto Godot | ✅ (Dias 01–05: config `BG_*`, `persistence`, `/healthz` + `/readyz`, Docker Compose, projeto Godot 4.7.2) |
| 2 — Protótipo jogável offline | Arena, personagem, bombas, explosões, power-ups, bots, HUD, menus, export Web | ✅ (Dias 06–14: `WorldSim` em militiles, PRNG `xorshift32`, bots BFS, HUD/menus, 4 suítes de cenários JSON, presets Web/Desktop) |
| 3 — Servidor Go | Autenticação, salas, WebSocket, protocolo v1, simulação autoritativa, validação, testes multi-cliente | ✅ (`internal/auth`, `internal/websocket` RFC 6455, `internal/game/rules` idêntico ao GDScript, `internal/game/rooms`, `session_dispatcher`) |
| 4 — Multiplayer competitivo | Salas públicas/privadas, matchmaking, 4–8 jogadores, reconexão, pontuação, estatísticas, ranking | ✅ (salas 4–8p, código privado, matchmaking, janela de reconexão 30s, Elo par-a-par, `/v1/*`, `NetSession` + `NetSync`) |
| 5 — Cross-platform | Navegador × desktop na mesma sala, macOS via navegador, build macOS opcional, desempenho | ✅ (salas mistas `web` + `windows` + `linux` + `macos` + `steam` de 8p, áudio Web com gesto, `SettingsStore`, benchmark < 1 ms/tick) |
| 6 — Steam | Steamworks isolado (auth ticket validado no backend), lobbies, convites, conquistas | ✅ (`POST /v1/auth/steam` em `internal/platform/steam.go`, `SteamBridge` em `client/scripts/platform/steam_bridge.gd` isolado por `steam_allowed()`) |
| 7 — Publicação | Hospedagem web, deploy Go, HTTPS/WSS, builds, página e assets de loja | ✅ (`deploy/Caddyfile` HTTPS/WSS + estáticos, `.github/workflows/ci.yml` Go/Godot/Docker, `scripts/export-web.sh`) |

## Resumo do que foi implementado e testado por fase

- **Fase 1 (Fundação):**
  - Backend Go (`server/cmd/api`, `internal/config`, `internal/logging`, `internal/persistence`, `internal/httpapi`) com migrations SQL embutidas (`0001_init`, `0002_auth_sessions`), `/healthz`, `/readyz` e graceful shutdown.
  - Infraestrutura local em `docker-compose.yml` e imagem multi-stage distroless em `server/Dockerfile`.
  - Projeto Godot 4.7.2 (`client/project.godot`, `client/export_presets.cfg`) e runner headless (`res://tests/run_tests.gd`).
- **Fase 2 (Protótipo jogável offline):**
  - Simulação determinística em ponto fixo (`1 tile = 1000` militiles, 20 Hz, PRNG `xorshift32`) em `client/scripts/rules/` com 3 perfis de bot (`client/scripts/ai/bot_brain.gd`), renderizador procedural (`client/scripts/gameplay/arena_renderer.gd`), HUD (`client/scripts/ui/hud_formatter.gd`), controlador de partida (`client/scripts/gameplay/arena_match_controller.gd`) e todas as 13 telas (`client/scripts/core/main.gd`).
  - Cenários compartilhados em `tests/scenarios/{01_grid_generation,02_movement,03_bombs_and_explosions,04_powerups}.json` validados no runner GDScript e em Go.
- **Fase 3 (Servidor Go):**
  - Pacotes `internal/auth`, `internal/websocket` (codec envelope v1, anti-replay `SeqTracker`, `RateLimiter` e `SessionDispatcher` RFC 6455 sobre `net/http`), `internal/game/rules` e `internal/game/rooms`.
  - Paridade 100% nos cenários JSON entre Go e GDScript; testes de sessão WebSocket sobre `net.Pipe()`, rate limit e rejeição de comandos com `seq` repetido.
- **Fase 4 (Multiplayer competitivo):**
  - Salas públicas e privadas (4–8 jogadores, código de convite de 6 caracteres), matchmaking rápido, reconexão em até 30s (`Resume` com `resume_token`), cálculo de Elo multiplayer par-a-par e persistência transacional em `server/internal/persistence/match_store.go`.
  - Rotas REST `/v1/auth/{guest,register,login,steam}`, `/v1/profile`, `/v1/rankings`, `/v1/rooms`, `/v1/rooms/join`, `/v1/matchmaking/enqueue`, endpoint WebSocket `GET /ws` e cliente `Transport` + `WSTransport` + `NetSession` + `NetSync`.
- **Fase 5 (Cross-platform):**
  - Validação de partidas mistas (`web`, `windows`, `linux`, `macos`, `steam`) na mesma sala de 8 jogadores sem divergência de estado, com benchmark (`server/internal/game/rules/bench_test.go`) executando 1 tick de 8 jogadores em ~150 ns (muito abaixo do teto de 1 ms/tick a 20 Hz).
  - Síntese procedural de efeitos sonoros PCM 16-bit (`client/scripts/core/sfx_synth.gd`) respeitando política de autoplay Web (`unlock_on_gesture`) e persistência de volumes/atalhos em `user://input.cfg` (`client/scripts/core/settings_store.gd`).
- **Fase 6 (Steam):**
  - Autenticação Steam no backend (`POST /v1/auth/steam` + `server/internal/platform/steam.go`) com validação de ticket (`ValidateTicket`) e avaliação de conquistas (`EvaluateAchievements`: `FIRST_WIN`, `CHAIN_MASTER_3`, `COLLECTOR_50`).
  - Camada `SteamBridge` (`client/scripts/platform/steam_bridge.gd`) desacoplada por `OS.has_feature("steam")` e `Engine.has_singleton("Steam")`, mantendo builds Web e desktop sem SDK 100% funcionais.
- **Fase 7 (Publicação, CI/CD e Deploy):**
  - Proxy reverso de produção em `deploy/Caddyfile` com HTTPS/WSS automático, headers de segurança, proxy de `/ws` e `/v1/*` e entrega dos estáticos da build Web.
  - Pipeline `.github/workflows/ci.yml` executando `gofmt`, `go vet`, `go test -race ./...` (com PostgreSQL 16), testes headless do Godot 4.7.2 e build da imagem Docker de produção.
  - Script `scripts/export-web.sh` para geração automatizada da build Web.

## Critérios de saída

- **Fase 1:** `go test ./...` e `go vet ./...` verdes; `/healthz` e `/readyz` (com banco) respondendo;
  migrations aplicam e revertem; projeto Godot importa headless sem erros. ✅
- **Fase 2:** partida Practice/FFA local completa contra 3 bots; testes de regras headless verdes;
  cenários de conformidade em `tests/scenarios/`; build Web exportada e carregando. ✅
- **Fase 3:** mesma bateria de cenários passando no Go; 4 e 8 clientes simulados numa sala; comandos
  inválidos/replay rejeitados. ✅
- **Fase 4:** matchmaking, salas públicas/privadas de 4–8 jogadores, reconexão em 30s, Elo e rotas `/v1/*` testados ponta a ponta. ✅
- **Fase 5:** clientes Web e Desktop na mesma sala com paridade de simulação e dentro do orçamento de CPU/rede de 20 Hz. ✅
- **Fase 6:** login Steam (`POST /v1/auth/steam`) e `SteamPlatform` testados com fallback limpo fora da Steam. ✅
- **Fase 7:** `deploy/Caddyfile`, `.github/workflows/ci.yml` e `scripts/export-web.sh` prontos e documentados em `docs/DEPLOYMENT.md`. ✅

## Riscos conhecidos

| Risco | Mitigação |
|---|---|
| Divergência Go × GDScript nas regras | Ponto fixo + ticks + PRNG próprio + cenários compartilhados (ARCHITECTURE D-11/12/14) |
| Rede restrita na VM de automação (módulos Go, Docker) | `GOPROXY=direct`; validação Docker no Mac (ARCHITECTURE §7) |
| Latência no navegador (WebSocket/TCP) | Medido na Fase 5; protocolo enxuto a 20 Hz atende com folga |
| Custos de distribuição macOS | Web como via oficial para Mac até aprovação |
