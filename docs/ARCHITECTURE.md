# BlastGrid Arena — Arquitetura e decisões técnicas

Versão 0.1 (2026-11-05). Cada decisão tem um id (`D-xx`) para ser referenciada em commits e docs.

## 1. Visão geral

```
 ┌───────────── Cliente Godot 4 (GDScript) ─────────────┐        ┌──────────── Servidor Go (1 serviço) ────────────┐
 │ UI / cenas ── gameplay (render, áudio, input)        │        │ net/http: auth, perfil, salas, ranking, healthz │
 │          │                                           │  WSS   │ websocket (coder/websocket) ── sessões          │
 │   rules/ simulação pura (offline + predição) ◄───────┼────────┼─► rooms ── simulation (autoritativa, ticks)     │
 │          │                                           │  JSON  │          │                                      │
 │   networking/ WebSocketPeer + protocolo v1           │        │ persistence (pgx) ── PostgreSQL                 │
 └──────────────────────────────────────────────────────┘        └─────────────────────────────────────────────────┘
                     tests/scenarios/*.json  ◄── conformidade compartilhada ──►  go test
```

## 2. Decisões

| Id | Decisão | Motivo |
|---|---|---|
| D-01 | Godot **4.7.2-stable**, GDScript, renderer **Compatibility** | Único renderer que exporta para Web (WebGL 2); mesmo look em todas as plataformas |
| D-02 | Export Web **single-thread** | Dispensa SharedArrayBuffer/COOP-COEP; compatível com Safari e hospedagem estática simples |
| D-03 | Go **1.27.3**, um único serviço modular (`server/internal/...`) | Briefing: sem microserviços prematuros |
| D-04 | HTTP só com `net/http` (roteador nativo com padrões `GET /path/{id}`) | Sem framework; menos dependências |
| D-05 | WebSocket: `github.com/coder/websocket` | Briefing; API com `context`, sem dependências transitivas |
| D-06 | PostgreSQL ≥ 16 via `github.com/jackc/pgx/v5` (`pgxpool`) | Briefing; pool nativo, transações explícitas |
| D-07 | Migrations SQL versionadas (`server/migrations/NNNN_nome.up.sql`/`.down.sql`), aplicadas por um runner próprio pequeno em Go com tabela `schema_migrations` | Evita dependência extra; SQL puro revisável. Reavaliar `golang-migrate` se surgir necessidade |
| D-08 | Logs `log/slog` em JSON; config só por env vars | Briefing; 12-factor |
| D-09 | Protocolo v1 em **JSON** com envelope `{v, t, seq, ack, data}`; binário só se medição justificar | Briefing; depuração fácil |
| D-10 | Simulação em **ticks fixos**, inicialmente **20 Hz** (50 ms), configurável até 30 Hz | Faixa do briefing; 20 Hz dá pavio = 50 ticks exatos. Cliente interpola/prediz |
| D-11 | Posições em **ponto fixo inteiro**: 1 tile = 1000 unidades; tempo em ticks | Determinismo idêntico Go × GDScript (sem divergência de float) |
| D-12 | PRNG especificado (**xorshift32**, seed u32) para mapa e drops | `rand` do Go e `RandomNumberGenerator` da Godot dão sequências diferentes |
| D-13 | Regras do jogo em GDScript **sem nós** (`RefCounted`) em `client/scripts/rules/` | Testável headless; reaproveitado offline e na predição |
| D-14 | Cenários de conformidade JSON em `tests/scenarios/` na raiz, lidos pelos testes Go e Godot | Uma fonte de verdade para as duas implementações |
| D-15 | Transporte atrás de interface (`Transport` no cliente, `Conn` no servidor) | Permite WebRTC/Pion no futuro sem tocar na lógica |
| D-16 | Estado das partidas só em memória; PostgreSQL recebe resultado no fim, em transação | Briefing; sem Redis até haver necessidade real |
| D-17 | Steam isolado em `client/scripts/platform/` e carregado só em builds nativas (feature tag) | Web não pode depender de Steamworks |
| D-18 | macOS: preset Universal sem assinatura/notarização | Notarização exige Apple Developer pago — não aprovado; Web é a via oficial para Mac |

## 3. Cliente (Godot)

```
client/
  project.godot           # Compatibility, input map, autoloads
  scenes/{main,menu,arena,players,bombs,powerups,ui}/
  scripts/
    rules/                # regras puras: grid, movimento, bombas, explosões, power-ups (D-13)
    gameplay/             # nós que renderizam/animam o estado das regras
    ai/                   # bots (mapa de perigo, BFS)
    networking/           # Transport, WebSocketPeer, protocolo, reconexão, predição/reconciliação
    platform/             # Steam (nativo), detecção de plataforma
    ui/                   # HUD e menus
  resources/powerups/     # um Resource por power-up
  tests/                  # testes headless (script runner próprio, sem plugin pago)
```

Offline (Fases 2): `rules` roda localmente a 20 Hz; a camada visual interpola entre ticks.
Online (Fase 3+): o cliente envia **intenções** (direção, colocar bomba) com `seq`; prediz o próprio
movimento com `rules`; reconcilia ao receber o estado com `ack`. Outros jogadores são interpolados.

## 4. Servidor (Go)

```
server/
  cmd/api/main.go         # wiring, sinal, graceful shutdown
  internal/
    config/               # env vars → struct validada
    http/                 # rotas, middlewares (timeouts, request id, limites de tamanho)
    auth/ users/ profiles/ ranking/
    lobby/ matchmaking/
    game/rules/           # mesmas regras do cliente (fonte da verdade)
    game/simulation/      # loop de ticks por sala
    game/rooms/           # ciclo de vida da sala, entrada/saída
    websocket/            # aceitar conexão, origem, rate limit, codec do protocolo
    persistence/          # pgxpool, migrations, repositórios
    security/             # rate limiting, validação, replay protection
  migrations/
```

Pacotes só são criados quando recebem código real.

Concorrência: uma goroutine por sala é dona do estado (sem locks no estado de jogo); conexões enviam
comandos por canal com buffer limitado; mensagens excedentes são descartadas e contadas (rate limit).

## 5. Determinismo e conformidade

- xorshift32: `x ^= x << 13; x ^= x >> 17; x ^= x << 5` em u32 (no GDScript, mascarar com `& 0xFFFFFFFF`
  após cada shift, pois `int` é 64 bits com sinal).
- Ordem de resolução por tick: entradas → movimento → colocação de bombas → pavios → explosões/cadeia →
  destruição/drops → coleta → eliminações → condição de vitória.
- Cenário = estado inicial + lista de entradas por tick + asserções de estado esperado.

## 6. Segurança (resumo; detalhes em NETWORK_PROTOCOL.md §9, MULTIPLAYER.md §8 e DEPLOYMENT.md §9)

Validação de todas as mensagens, tamanho máximo de frame, rate limit por conexão, `OriginPatterns` no
accept do WebSocket, `seq` monotônico contra replay, servidor nunca aceita resultado vindo do cliente.

## 7. Ambiente verificado e incompatibilidades (2026-11-05)

Ambiente da automação diária: VM Linux Ubuntu 22.04.5, **aarch64**, 4 vCPU, 3,8 GiB RAM, sem root
(sudo bloqueado por "no new privileges"), rede por proxy com allowlist. Host: macOS arm64.

| Ferramenta | Situação | Versão |
|---|---|---|
| Git | presente | 2.34.1 |
| Go | ausente → instalado em `~/tools` via conda-forge (`scripts/setup-dev-vm.sh`) | 1.27.3 linux/arm64 |
| Godot | ausente → instalado em `~/tools` via GitHub Releases (SHA-512 conferido) | 4.7.2.stable.official.ed1daf0bf |
| Docker / Compose | ausente; **não instalável** (sem root, Docker Hub bloqueado) | — |
| PostgreSQL | ausente; sem apt (sem root) | — |

Incompatibilidades e mitigação:

1. **VM efêmera** — ferramentas fora da pasta do projeto somem entre execuções. Mitigação:
   `scripts/setup-dev-vm.sh` idempotente, com hashes fixados; validado numa instalação limpa.
2. **`proxy.golang.org` e `sum.golang.org` bloqueados** — módulos via `GOPROXY=direct`, `GOSUMDB=off`.
   `go.sum` ainda fixa hashes; revalidar com `GOSUMDB` ligado numa máquina com rede aberta (pendência).
3. **`gopkg.in` bloqueado** — `pgx/v5` puxa transitivamente `gopkg.in/yaml.v3` (via testify de
   `pgservicefile`). A resolver no Dia 04 (ex.: `replace` apontando para o espelho no GitHub, ou baixar
   em máquina com rede aberta e versionar só `go.sum`). `coder/websocket` baixa sem problema.
4. **Docker indisponível na VM** — o Dia 04 valida `Dockerfile`/`docker-compose.yml` sintaticamente aqui
   e a subida real deve ser feita no Mac (Docker Desktop/OrbStack/Colima, gratuitos para uso pessoal —
   confirmar licença do Docker Desktop se uso comercial). Para testes de integração na VM, avaliar
   PostgreSQL do conda-forge em espaço de usuário.
5. **Export Web/desktop** exige export templates (`.tpz` do GitHub, grande) — baixar quando o export
   for validado (Dia 14); o Dia 05 valida apenas import headless e presets.
6. **WebSocket no navegador** não permite cabeçalhos customizados — autenticação do WS por token na
   primeira mensagem (ou query de uso único), não por header `Authorization`.
7. **Godot nativo pode não enviar `Origin`** — o `Accept` do coder/websocket só verifica origem quando o
   header existe; clientes nativos são autenticados por token, não por origem.
8. **macOS nativo** — assinatura/notarização exigem programa pago da Apple → não adotado (D-18).
9. **Arquitetura arm64 da VM** — editor Linux arm64; exportar Windows/Linux x86_64 é suportado pelos
   templates oficiais, mas o binário x86_64 não pode ser executado na VM para teste.
