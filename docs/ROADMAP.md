# BlastGrid Arena — Roadmap por fases

Detalhamento diário das Fases 1 e 2: `docs/ROADMAP_DIARIO.md` (inclui o registro de execução).
Status: ⬜ não iniciado · 🟨 em andamento · ✅ concluído.

| Fase | Objetivo | Status |
|---|---|---|
| 1 — Fundação | Ambiente, docs, backend Go mínimo com health checks, PostgreSQL + migrations, Docker, projeto Godot | 🟨 (Dias 01–02 concluídos) |
| 2 — Protótipo jogável offline | Arena, personagem, bombas, explosões, power-ups, bots, HUD, menus, export Web | ⬜ |
| 3 — Servidor Go | Autenticação, salas, WebSocket, protocolo v1, simulação autoritativa, validação, testes multi-cliente | ⬜ |
| 4 — Multiplayer competitivo | Salas públicas/privadas, matchmaking, 4–8 jogadores, reconexão, pontuação, estatísticas, ranking | ⬜ |
| 5 — Cross-platform | Navegador × desktop na mesma sala, macOS via navegador, build macOS opcional, desempenho | ⬜ |
| 6 — Steam | Steamworks isolado (auth ticket validado no backend), lobbies, convites, conquistas | ⬜ |
| 7 — Publicação | Hospedagem web, deploy Go, HTTPS/WSS, builds, página e assets de loja | ⬜ |

## Critérios de saída

- **Fase 1:** `go test ./...` e `go vet ./...` verdes; `/healthz` e `/readyz` (com banco) respondendo;
  migrations aplicam e revertem; projeto Godot importa headless sem erros.
- **Fase 2:** partida Practice/FFA local completa contra 3 bots; testes de regras headless verdes;
  cenários de conformidade em `tests/scenarios/`; build Web exportada e carregando.
- **Fase 3:** mesma bateria de cenários passando no Go; 4 e 8 clientes simulados numa sala; comandos
  inválidos/replay rejeitados.

## Riscos conhecidos

| Risco | Mitigação |
|---|---|
| Divergência Go × GDScript nas regras | Ponto fixo + ticks + PRNG próprio + cenários compartilhados (ARCHITECTURE D-11/12/14) |
| Rede restrita na VM de automação (módulos Go, Docker) | `GOPROXY=direct`; validação Docker no Mac (ARCHITECTURE §7) |
| Latência no navegador (WebSocket/TCP) | Medir na Fase 5; WebRTC/Pion só com dados que justifiquem |
| Custos de distribuição macOS | Web como via oficial para Mac até aprovação |
