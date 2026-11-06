# BlastGrid Arena — Protocolo de rede v1

Versão do documento 1.0 (2026-11-06). Status: **especificação** — a implementação começa na Fase 3
(servidor `server/internal/websocket`, cliente `client/scripts/networking`). Decisões referenciadas:
ARCHITECTURE D-09 (JSON), D-10 (ticks), D-11 (ponto fixo), D-15 (transporte abstrato).

O protocolo é o **mesmo** para todas as plataformas (Godot Web, Windows, Linux, macOS, Steam).
Não usa o multiplayer de alto nível da Godot (`MultiplayerAPI`/RPC); o cliente fala JSON puro via
`WebSocketPeer`.

## 1. Transporte

| Item | Valor |
|---|---|
| URL | `wss://<host>/ws` (produção) · `ws://localhost:8080/ws` (dev) |
| Subprotocolo | `blastgrid.v1` (header `Sec-WebSocket-Protocol`; Godot: `WebSocketPeer.supported_protocols`) |
| Frames | **texto**, UTF-8, um objeto JSON por frame; frames binários são reservados (§12) |
| Tamanho máximo cliente→servidor | 4 KiB por frame (`Conn.SetReadLimit(4096)`); excedeu ⇒ close `1009` |
| Tamanho máximo servidor→cliente | 64 KiB por frame (cliente configura `inbound_buffer_size` ≥ 64 KiB) |
| Compressão | desligada na v1 (permessage-deflate custa CPU por conexão e o Safari tem histórico de bugs) |
| Keepalive | `ping`/`pong` de aplicação a cada 2 s (§6); sem pong por 10 s ⇒ conexão considerada morta |

O servidor rejeita o upgrade (HTTP 400) se o cliente não oferecer `blastgrid.v1`. Clientes web são
filtrados por `Origin` (`websocket.AcceptOptions.OriginPatterns`, configurado por `BG_ALLOWED_ORIGINS`);
clientes nativos podem não enviar `Origin` e são autenticados apenas por token (ARCHITECTURE §7 item 7).

## 2. Envelope

Toda mensagem, nos dois sentidos:

```json
{"v": 1, "t": "input", "seq": 42, "ack": 1337, "data": {"dir": "up", "bomb": false, "tick": 2051}}
```

| Campo | Tipo | Obrigatório | Significado |
|---|---|---|---|
| `v` | int | sim | versão do protocolo; v1 = `1`. Diferente ⇒ close `4003` |
| `t` | string | sim | tipo da mensagem (`[a-z_.]{1,32}`) |
| `seq` | int ≥ 1 | sim | sequência **do remetente**, estritamente crescente por conexão lógica (sobrevive a `resume`) |
| `ack` | int ≥ 0 | não | último `seq` recebido do outro lado (cliente→servidor) ou último `seq` de **input** processado pela simulação (servidor→cliente, ver §7) |
| `data` | object | sim | payload do tipo; `{}` quando vazio |

Regras de decodificação (servidor): JSON estrito, objeto na raiz, inteiros dentro de ±2^53, campos
desconhecidos **ignorados** (compatibilidade para frente), tipo desconhecido ⇒ `error{code:"unknown_type"}`
sem fechar. `seq` ≤ último aceito ⇒ mensagem descartada e contada como replay (§9).

## 3. Unidades

- **Posição:** inteiros em militiles (1 tile = 1000). Centro da célula (cx, cy) = `(cx*1000+500, cy*1000+500)`.
- **Tempo de jogo:** ticks. Taxa v1 = 20 Hz (50 ms/tick), anunciada em `welcome.tick_rate`.
- **Tempo de relógio:** milissegundos inteiros (`*_ms`), relógio monotônico do servidor desde o boot.
- **Direções:** `"none" | "up" | "down" | "left" | "right"`.

Valores das regras em ticks a 20 Hz (GDD): pavio 50 · chama 10 · escudo 120 · velocidade base
200 mt/tick (4 tiles/s), +25 por power-up, máximo 350 (7 tiles/s).

## 4. Ciclo de vida da conexão

```
cliente                                   servidor
  │── upgrade /ws (blastgrid.v1) ───────────►│
  │── hello {token, client} ────────────────►│  (até 5 s; senão close 4002)
  │◄──────────────── welcome {session...} ───│  ou close 4001
  │── room.join / room.create ──────────────►│  (Fase 3)
  │◄─────────────────────────── room.state ──│
  │◄─────────────── match.start {seed...} ───│
  │── input ... (a cada mudança / tick) ────►│
  │◄──────────── state (a cada tick, 20 Hz) ─│
  │◄──────────────── match.end {resultado} ──│
```

Autenticação vai **na primeira mensagem**, não em header: o WebSocket do navegador não permite
cabeçalhos customizados (ARCHITECTURE §7 item 6). O token é o access token obtido pela API HTTP
(`POST /v1/auth/login` ou `POST /v1/auth/guest`, Fase 3).

## 5. Mensagens

### 5.1 Sessão

**`hello`** (C→S)
```json
{"v":1,"t":"hello","seq":1,"data":{"token":"<access token>","client":{"platform":"web","version":"0.1.0","build":"a71e553"}}}
```
`platform ∈ {web, windows, linux, macos}`; `version` semver do cliente. Versão abaixo do mínimo do servidor
⇒ `error{code:"client_outdated"}` + close `4003`.

**`welcome`** (S→C)
```json
{"v":1,"t":"welcome","seq":1,"ack":1,"data":{"session_id":"s_8f2c","player_id":"u_31","tick_rate":20,"server_time_ms":81234567,"resume_token":"<opaco>","resume_window_s":30}}
```

**`resume`** (C→S, substitui `hello` numa reconexão)
```json
{"v":1,"t":"resume","seq":57,"data":{"resume_token":"<opaco>","last_server_seq":1311}}
```
O `seq` continua de onde parou. Válido por `resume_window_s` após a queda. Sucesso ⇒ `welcome` e, se
houver partida, um `state` completo (`full:true`). Falha ⇒ `error{code:"resume_failed"}`; o cliente faz
`hello` novo (e perde a vaga na partida se a janela expirou). Conexão antiga da mesma sessão é fechada
com `4005`.

### 5.2 Relógio

**`ping`** (C→S) `{"t0": <ms do cliente>}` · **`pong`** (S→C) `{"t0": <eco>, "ts": <server ms>, "tick": <tick atual da sala ou 0>}`

Ver §6.

### 5.3 Salas (Fase 3)

| Tipo | Dir. | `data` |
|---|---|---|
| `room.create` | C→S | `{"mode":"ffa","max_players":4,"private":false}` |
| `room.join` | C→S | `{"room_id":"r_12"}` ou `{"code":"KX7Q"}` (privada) |
| `room.leave` | C→S | `{}` |
| `room.ready` | C→S | `{"ready":true,"character":"sparky_a","skin":"default"}` |
| `room.state` | S→C | `{"room_id","mode","max_players","host","players":[{"id","name","ready","slot","platform"}],"status":"waiting\|starting\|in_match"}` |

Listagem de salas e matchmaking ficam na API HTTP (`GET /v1/rooms`), não no WebSocket.

### 5.4 Partida

**`match.start`** (S→C)
```json
{"v":1,"t":"match.start","seq":200,"data":{"match_id":"m_77","seed":3141592653,"cols":15,"rows":13,"start_tick":60,"tick_rate":20,"duration_ticks":3600,"rules":{"fuse":50,"flame":10,"base_range":2,"base_bombs":1,"base_speed":200},"players":[{"id":"u_31","slot":0,"spawn":[1,1]},{"id":"u_40","slot":1,"spawn":[13,1]}]}}
```
O mapa **não** é enviado: o cliente gera o mesmo grid a partir do `seed` (ARCHITECTURE D-12). O tick
`start_tick` é a contagem regressiva (3 s); entradas antes dele são ignoradas.

**`input`** (C→S) — intenção, nunca posição
```json
{"v":1,"t":"input","seq":43,"ack":512,"data":{"tick":2051,"dir":"left","bomb":true}}
```
- `dir`: direção mantida a partir desse input (estado, não evento). `bomb`: pedido de colocar bomba (evento).
- `tick`: tick em que o cliente **espera** que o input seja aplicado (estimado pelo relógio, §6).
- Enviado quando muda a direção, quando aperta bomba e, no mínimo, a cada 5 ticks (heartbeat de input).
- O servidor enfileira por jogador e aplica no próximo tick ≥ `tick`; inputs com `tick` mais de 20 ticks
  no passado são aplicados no tick atual; mais de 40 ticks no futuro ⇒ descartados (`bad_tick`).
- No máximo **um input aplicado por tick por jogador**; havendo vários, vale o último `dir` e qualquer
  `bomb:true` da janela.

**`state`** (S→C) — a cada tick
```json
{"v":1,"t":"state","seq":1311,"ack":43,"data":{"tick":2052,"full":false,
 "players":[{"id":"u_31","x":1500,"y":3500,"dir":"left","alive":true,"speed":225,"bombs":2,"range":3,"shield":0}],
 "bombs":[{"id":19,"owner":"u_31","cx":1,"cy":3,"fuse":48,"range":3}],
 "events":[{"k":"bomb_placed","id":19,"owner":"u_31","cx":1,"cy":3}]}}
```
- `ack` = `seq` do último `input` **deste** jogador já aplicado pela simulação — base da reconciliação (§7).
- `players` e `bombs` são sempre completos (no máx. 8 jogadores e dezenas de bombas ⇒ < 4 KiB).
- O grid não é repetido: mudanças de tile vêm em `events`. Com `full:true` (após `resume` ou a cada
  200 ticks) vem também `"grid":"<195 dígitos, linha a linha: 0=EMPTY 1=WALL 2=BLOCK>"` e `"powerups":[...]`.

Eventos (`events[].k`), em ordem de resolução dentro do tick (ARCHITECTURE §5):

| `k` | Campos |
|---|---|
| `bomb_placed` | `id, owner, cx, cy` |
| `explosion` | `bomb_id, cells:[[cx,cy],...]` (inclui cadeia; uma entrada por bomba) |
| `block_destroyed` | `cx, cy, drop` (`null` ou id do power-up: `range_up`, `bomb_up`, `speed_up`, `shield`) |
| `powerup_collected` | `player, cx, cy, kind` |
| `powerup_destroyed` | `cx, cy` |
| `shield_broken` | `player` |
| `player_eliminated` | `player, by` (`by` = dono da bomba; igual a `player` ⇒ autoeliminação) |
| `player_disconnected` / `player_reconnected` | `player` |

**`match.end`** (S→C)
```json
{"v":1,"t":"match.end","seq":4100,"data":{"match_id":"m_77","tick":3402,"reason":"last_alive","winner":"u_31","results":[{"player":"u_31","place":1,"score":540,"kills":3,"blocks":14,"powerups":5,"deaths":0}]}}
```
`reason ∈ {last_alive, time_up, draw, aborted}`; `winner` = `null` em empate. Resultado é calculado e
persistido **apenas** pelo servidor; não existe mensagem cliente→servidor de pontuação ou vitória.

### 5.5 Erros

**`error`** (S→C) `{"code":"...","msg":"texto curto para log","ref":<seq que causou ou 0>}`

| `code` | Fecha? | Quando |
|---|---|---|
| `bad_message` | não (fecha após 10 em 10 s) | JSON inválido, campo obrigatório ausente ou tipo errado |
| `unknown_type` | não | `t` desconhecido |
| `bad_tick` | não | `input.tick` fora da janela |
| `not_in_room` / `room_full` / `room_not_found` | não | operações de sala |
| `rate_limited` | não (fecha com 4004 se persistir) | §9 |
| `client_outdated` | sim (4003) | versão abaixo do mínimo |
| `resume_failed` | não | token inválido/expirado |

## 6. Sincronização de relógio

1. Cliente envia `ping{t0}` com `Time.get_ticks_msec()`; recebe `pong{t0, ts, tick}` em `t1`.
2. `rtt = t1 - t0`; `offset = ts + rtt/2 - t1` (estilo NTP/Cristian).
3. Mantém as 8 últimas amostras; usa o `offset` da amostra de **menor RTT** e a **mediana** do RTT
   para exibição de latência no HUD.
4. Tick estimado do servidor: `tick_srv ≈ tick_ref + (agora + offset - ts_ref) / 50`.
5. Tick-alvo dos inputs: `tick_srv + ceil((rtt/2 + 1 tick de margem) / 50)` — o input chega antes de o
   servidor simular aquele tick.

Pings a cada 2 s (a cada 500 ms nos primeiros 3 s após `welcome`, para convergir rápido).

## 7. Predição, reconciliação e interpolação

- **Jogador local:** o cliente aplica o próprio input imediatamente usando as mesmas regras
  (`client/scripts/rules`, ARCHITECTURE D-13) e guarda `(seq, tick, dir, bomb)` num buffer circular.
- **Reconciliação:** ao receber `state` com `ack = N`, o cliente parte da posição autoritativa, descarta
  inputs ≤ N e **re-simula** os inputs pendentes. Diferença < 30 mt ⇒ corrige suavemente em ~100 ms;
  maior ⇒ teleporte. Bombas preditas sem confirmação após 2·RTT são removidas.
- **Outros jogadores e bombas:** interpolação com atraso de renderização de 2 ticks (100 ms) entre os
  dois `state` mais recentes; sem extrapolação além de 1 tick.
- **Eventos destrutivos** (explosão, eliminação, coleta) **nunca** são preditos: só aparecem quando o
  servidor os confirma. A pré-visualização da área de perigo é apenas visual.

## 8. Reconexão

- Queda detectada por erro de socket ou falta de `pong` por 10 s.
- Cliente tenta `resume` com backoff exponencial 0,5 s → 1 → 2 → 4 → 8 s (+ jitter de até 250 ms),
  até esgotar `resume_window_s`.
- Durante a desconexão o jogador fica **parado** no servidor (dir `none`, sem bombas), mas continua
  vulnerável. Expirada a janela, é marcado como desconectado e eliminado no fim da partida para fins
  de ranking (regra da Fase 4).
- O servidor guarda as últimas 64 mensagens enviadas por sessão; se `last_server_seq` estiver na janela,
  reenvia as que faltam, senão manda `state` com `full:true`.

## 9. Segurança e limites

| Proteção | Regra v1 |
|---|---|
| Autenticação | `hello` com token válido em até 5 s; antes disso só `hello`/`resume`/`ping` são aceitos |
| Origem | `OriginPatterns` para navegadores; nativos sem `Origin` aceitos só com token |
| Tamanho | 4 KiB por frame de entrada |
| Rate limit | token bucket por conexão: 40 msg/s, rajada 80. Estouro ⇒ descarta + `rate_limited`; 3 s seguidos ⇒ close 4004 |
| Replay | `seq` estritamente crescente; repetidos/antigos descartados |
| Validação de input | `dir` no enum, `bomb` booleano, `tick` na janela; velocidade e colisão **recalculadas** pelo servidor |
| Autoridade | posição, bombas, explosões, drops, eliminações e pontuação existem só no servidor |
| Fila | buffer de comandos por conexão limitado (64); cheio ⇒ descarta o mais antigo e conta |

## 10. Códigos de fechamento

| Código | Motivo |
|---|---|
| 1000 | normal (saída voluntária) |
| 1001 | servidor desligando (graceful shutdown) — cliente deve tentar `resume` em outro momento |
| 1008 | violação de política genérica |
| 1009 | frame acima do limite |
| 4001 | autenticação falhou |
| 4002 | `hello` não chegou a tempo |
| 4003 | versão de protocolo/cliente incompatível |
| 4004 | rate limit persistente |
| 4005 | sessão substituída por outra conexão |

## 11. Versionamento

- Mudanças **aditivas** (novo campo opcional, novo tipo, novo evento) mantêm `v:1`; receptores ignoram
  o que não conhecem.
- Mudança incompatível ⇒ `v:2` + subprotocolo `blastgrid.v2`; o servidor aceita as duas durante a transição.
- Este documento é a fonte da verdade; cada mudança atualiza a seção e uma linha no histórico (§14).

## 12. Evolução para binário

Só se a medição (Fase 5) mostrar `state` como gargalo de banda/CPU. Plano: frames binários com cabeçalho
fixo `u8 versão | u8 tipo | u32 seq | u32 ack` + payload por tipo em little-endian, mantendo os mesmos
tipos e semântica deste documento; negociado por subprotocolo `blastgrid.v1+bin`. JSON continua para depuração.

## 13. Testes previstos

- **Codec (Go e GDScript):** fixtures em `tests/protocol/*.json` (mensagens válidas e inválidas com o
  resultado esperado), lidas pelos dois lados — mesmo modelo dos cenários de regra (ARCHITECTURE D-14).
- **Servidor:** limites de tamanho, rate limit, replay de `seq`, timeout de `hello`, `resume` dentro/fora
  da janela, 4 e 8 clientes simulados (`go test` com `httptest` + `coder/websocket` como cliente).
- **Cliente:** reconciliação com perda/atraso simulados; teste headless contra o servidor local.

## 14. Histórico

| Data | Versão | Mudança |
|---|---|---|
| 2026-11-06 | 1.0 | Especificação inicial |
