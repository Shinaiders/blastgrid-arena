# BlastGrid Arena

Jogo 2D multiplayer competitivo de arena em grid (bombas, explosões em cruz, power-ups), com identidade visual original.

- **Cliente:** Godot 4 (GDScript, renderer Compatibility) — Web (WASM/WebGL 2, single-thread), Windows, Linux, macOS opcional.
- **Servidor:** Go (`net/http`, `github.com/coder/websocket`, `pgx`), autoritativo, um único serviço modular.
- **Banco:** PostgreSQL com migrations SQL versionadas.
- **Infra:** Docker / Docker Compose, logs estruturados, health checks, configuração por env vars.

Tudo gratuito/open source. Nenhum serviço pago é dependência.

## Estado atual

Fase 1 (Fundação) em andamento — ver `docs/ROADMAP_DIARIO.md` para o progresso dia a dia
e `docs/ROADMAP.md` para a visão por fases.

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

Versões de referência (verificadas em 2026-11-05): Go 1.27.3, Godot 4.7.2-stable, Git 2.34+.

Na VM Linux usada pela automação diária (sem root):

```bash
scripts/setup-dev-vm.sh            # instala Go e Godot em ~/tools
source <(scripts/setup-dev-vm.sh env)
```

Em máquina própria, instale Go ≥ 1.27, Godot 4.7.x stable, Docker e PostgreSQL ≥ 16 normalmente.
