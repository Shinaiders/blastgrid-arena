# BlastGrid Arena — Arquitetura multiplayer

Versão 1.0 (2026-11-06). Status: **projeto** (implementação nas Fases 3–5). Mensagens e formatos:
`NETWORK_PROTOCOL.md`. Regras do jogo: `GDD.md`.

## 1. Modelo

- **Servidor autoritativo** em Go: a simulação da sala é a única fonte da verdade.
- **Clientes enviam intenções** (`dir`, `bomb`) — nunca posições, acertos, eliminações ou pontuação.
- **Mesmo protocolo e mesma sala para todas as plataformas**: navegador (inclusive Mac), Windows, Linux,
  Steam. Não há matchmaking ou ranking separado por plataforma; a plataforma é só um atributo do jogador
  (estatística e diagnóstico).
- **Simulação determinística duplicada**: Go (autoridade) e GDScript (offline + predição) implementam as
  mesmas regras em inteiros (militiles, ticks, xorshift32), verificadas pelos cenários de conformidade
  em `tests/scenarios/` (ARCHITECTURE D-11, D-12, D-14).

## 2. Componentes do servidor

```
conexão WS ──► websocket.Session ──(chan cmd, cap 64)──► rooms.Room (1 goroutine) ──► simulation.World
     ▲                │                                        │
     └── writer goroutine ◄──(chan out, cap 128)───────────────┘ snapshot/eventos por tick
```

| Componente | Responsabilidade |
|---|---|
| `websocket` | upgrade, origem, `hello`/`resume`, decodificação e validação do envelope, rate limit, uma goroutine de leitura e uma de escrita por conexão |
| `rooms` | ciclo de vida da sala (waiting → starting → in_match → finished), entrada/saída, ready, slots, dono do `World` |
| `game/simulation` | loop de ticks, fila de inputs por jogador, aplicação de regras, geração de `state`/eventos |
| `game/rules` | regras puras (grid, movimento, bombas, explosões, power-ups) — sem I/O |
| `lobby` / `matchmaking` | listagem, salas privadas por código, fila de matchmaking (Fase 4) |
| `persistence` | gravação do resultado em transação ao fim da partida |

**Concorrência:** cada `Room` é dona exclusiva do seu estado (sem mutex no estado de jogo). Sessões
comunicam-se com a sala só por canais com buffer limitado; um cliente lento nunca bloqueia o tick — se o
canal de saída encher, as mensagens `state` mais antigas são descartadas (o próximo `state` é completo
para jogadores/bombas) e, persistindo por 5 s, a conexão é fechada.

## 3. Loop de simulação

- Taxa 20 Hz (`BG_TICK_RATE`, aceito 20–30). `time.Ticker` + contador de ticks; atraso acumulado maior
  que 5 ticks ⇒ log de alerta e "pulo" controlado (não tenta compensar indefinidamente).
- Ordem por tick (ARCHITECTURE §5): entradas → movimento → bombas → pavios → explosões/cadeia →
  destruição/drops → coleta → eliminações → vitória.
- Após o tick: monta `state` com eventos do tick e envia a cada sessão com o `ack` daquele jogador.
- Orçamento: < 1 ms por tick por sala de 8 jogadores (meta para ~200 salas por vCPU); medido com
  benchmark `go test -bench` na Fase 3.

## 4. Cliente

| Camada | Arquivo/pasta (planejado) | Função |
|---|---|---|
| Transporte | `scripts/networking/transport.gd` (interface) + `ws_transport.gd` (`WebSocketPeer`) | conectar, enviar, receber frames, estado da conexão |
| Protocolo | `scripts/networking/protocol.gd` | encode/decode do envelope, validação, `seq`/`ack` |
| Sessão | `scripts/networking/net_session.gd` (autoload) | `hello`/`resume`, ping/relógio, reconexão com backoff |
| Sincronização | `scripts/networking/net_sync.gd` | buffer de inputs, predição, reconciliação, interpolação |
| Regras | `scripts/rules/` | mesma simulação usada offline |

`WebSocketPeer` é polled no `_process`; o processamento de rede e a simulação local rodam em passos
fixos de 50 ms acumulados (não no `_physics_process` variável), para coincidir com o tick do servidor.

## 5. Latência — técnicas

| Técnica | Aplicação |
|---|---|
| Predição local | só o movimento e a colocação de bomba do próprio jogador |
| Reconciliação | re-simulação a partir do `state` autoritativo + inputs pendentes (`ack`) |
| Interpolação | outros jogadores/bombas com 100 ms de atraso de renderização |
| Sem predição | explosões, eliminações, drops e coletas — aparecem só confirmados |
| Tolerância | inputs atrasados até 20 ticks são aplicados no tick atual (sem "rebobinar" o mundo) |

Não há lag compensation retroativa (rewind): no gênero, explosões ocupam células inteiras e duram 10
ticks, o que torna a resolução no tempo do servidor justa e simples. Reavaliar com dados da Fase 5.

## 6. Salas e partidas

- Tamanho: 2–8 jogadores; padrão 4 (spawns no GDD §3). `max_players` fixado na criação.
- Fluxo: `waiting` (entrada/saída livre) → todos `ready` (ou matchmaking cheio) → `starting` (contagem de
  3 s = 60 ticks) → `in_match` → `finished` (resultado persistido, sala volta a `waiting` ou é destruída).
- Sala vazia por 60 s é destruída. Partida com 1 jogador conectado por 30 s termina como `aborted`.
- Seed do mapa: `crypto/rand` no servidor, enviado em `match.start`.

## 7. Desconexão e reconexão

- Até `resume_window_s` (30 s): personagem parado e vulnerável; vaga reservada; `resume` recupera a sessão.
- Após a janela: `player_disconnected` definitivo; o jogador continua no mundo parado até morrer ou a
  partida acabar; conta como derrota no ranking (anti "rage quit").
- Graceful shutdown do servidor: para de aceitar salas novas, espera partidas em andamento até
  `BG_SHUTDOWN_TIMEOUT` (padrão 30 s; partidas FFA duram ≤ 3 min, então em deploy usa-se drenagem — ver
  DEPLOYMENT.md), depois fecha conexões com 1001.

## 8. Anti-trapaça (resumo)

- Velocidade, colisões, limite de bombas, alcance e pavio vêm do estado do servidor, nunca do cliente.
- `seq` estritamente crescente (anti-replay), rate limit, tamanho máximo de frame, janela de `tick`.
- Informação oculta: no gênero todo o estado é visível (sem fog of war), porém
  não há fog of war; drops ocultos dentro de blocos **não** são enviados até o bloco ser destruído.
- Resultados e pontuação só gravados pelo servidor; endpoints HTTP não aceitam resultado de partida.

## 9. Transporte alternativo (futuro)

A interface `Transport` (cliente) e `Conn` (servidor) isola o WebSocket. WebRTC DataChannels (Pion no Go,
`WebRTCPeerConnection` na Godot) só entram se a Fase 5 medir problemas de head-of-line blocking do TCP que
afetem a jogabilidade — o protocolo de mensagens não muda, apenas o canal (não confiável/não ordenado
para `input`/`state`, confiável para o resto).

## 10. Escala

- v1: **uma instância** do servidor; todas as salas em memória. Capacidade estimada (a confirmar em teste
  de carga): ~1000 conexões simultâneas numa VPS de 2 vCPU.
- Próximo passo, se necessário: várias instâncias com sala "presa" a uma instância (o matchmaking
  devolve o endereço `wss` da instância), e só então um armazenamento compartilhado (Redis) para
  presença/filas.

## 11. Testes

| Teste | Onde |
|---|---|
| Conformidade de regras Go × GDScript | `tests/scenarios/*.json` |
| Codec do protocolo Go × GDScript | `tests/protocol/*.json` |
| Sala com 4 e com 8 clientes simulados, partida completa | `server/internal/game/rooms` (`go test -race`) |
| Desconexão/reconexão dentro e fora da janela | `server/internal/websocket` |
| Inputs inválidos, replay, flood | `server/internal/websocket`, `security` |
| Cliente headless Godot contra servidor local | Fase 5 |
| Navegador × desktop na mesma sala | Fase 5 (manual + roteiro) |
