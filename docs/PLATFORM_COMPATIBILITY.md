# BlastGrid Arena — Compatibilidade de plataformas

Versão 1.0 (2026-11-06). Status: **requisitos e plano de testes**. Presets de exportação são criados no
Dia 05; o export real é validado no Dia 14 (Web) e na Fase 5/6 (desktop). Decisões: ARCHITECTURE D-01,
D-02, D-17, D-18.

## 1. Matriz

| Plataforma | Build | Prioridade | Distribuição | Custo | Estado |
|---|---|---|---|---|---|
| Windows x86_64 | export nativo Godot | 1 | Steam / download | Steam Direct: taxa por app (**requer aprovação**) | planejado |
| Linux x86_64 | export nativo Godot | 1 | Steam / download | idem | planejado |
| Web (Chrome, Edge, Firefox, Safari) | WASM + WebGL 2, single-thread | 2 (via oficial sem custo) | hospedagem estática | gratuito (itch.io / GitHub Pages / Cloudflare Pages) | planejado |
| macOS via navegador | build Web | 2 | idem Web | gratuito | planejado — via oficial para Mac |
| macOS nativo (Universal 2) | export nativo, sem assinatura | opcional | download direto | assinatura/notarização exige Apple Developer pago → **não adotado** | preset apenas |

Todas as plataformas usam o **mesmo protocolo e o mesmo servidor** (MULTIPLAYER.md §1).

## 2. Regras de projeto para manter tudo compatível

1. Renderer **Compatibility** (OpenGL 3.3 / WebGL 2) em todas as plataformas — mesmo visual e um único
   caminho de shaders.
2. Nenhuma GDExtension/plugin nativo no núcleo do jogo. Steamworks (GodotSteam ou similar, MIT) só
   entra na Fase 6, isolado em `scripts/platform/` e carregado apenas quando `OS.has_feature("steam")`
   (feature tag customizada nos presets nativos). A build Web nunca referencia a extensão.
3. Rede apenas por `WebSocketPeer` (funciona nativo e no navegador). Nada de `ENetMultiplayerPeer`,
   `PacketPeerUDP` ou `HTTPRequest` bloqueante específico de plataforma.
4. Sem threads obrigatórias (`Thread`/`WorkerThreadPool`) na lógica do jogo — o export Web é
   single-thread (D-02). Bots e simulação cabem no orçamento do frame.
5. Arquivos: só `user://` para configurações/salvamento (no navegador vira IndexedDB). Nenhum caminho absoluto.
6. Tamanho da build Web: meta < 40 MB comprimido (templates Godot ~ 9–10 MB em WASM); assets otimizados.

## 3. Web — restrições conhecidas

| Tema | Restrição | Tratamento |
|---|---|---|
| Threads | export com threads exige SharedArrayBuffer + headers COOP/COEP | single-thread (D-02); dispensa headers especiais |
| HTTPS / WSS | página `https` não pode abrir `ws://` (mixed content) | produção sempre `wss://`; dev em `http://localhost` |
| Cabeçalhos WS | navegador não permite headers customizados no WebSocket | token no `hello` (NETWORK_PROTOCOL §4) |
| Origem | navegador envia `Origin` | servidor valida com `BG_ALLOWED_ORIGINS` |
| CORS | API HTTP chamada de outro domínio | middleware CORS com a mesma lista de origens |
| Áudio | autoplay bloqueado até interação do usuário | iniciar áudio após o primeiro clique/tecla (tela inicial) |
| Foco/teclas | ESC sai de fullscreen no navegador; algumas teclas são capturadas pelo browser | pausa também em P / Start; `preventDefault` padrão do export para setas e espaço |
| Fullscreen | só após gesto do usuário | botão nas Configurações |
| Aba em segundo plano | `requestAnimationFrame` desacelera; timers limitados a ~1 Hz | servidor continua a simulação; ao voltar, cliente aplica `state` completo e reconcilia |
| Gamepad | Gamepad API só reporta após o primeiro botão pressionado | mensagem "pressione um botão" na tela de controles |
| Safari | WebGL 2 disponível desde Safari 15; histórico de bugs com permessage-deflate | compressão WS desligada na v1; testar Safari ≥ 17 no Mac |
| Memória | dispositivos móveis/limitados | fora do escopo (desktop browsers); não bloquear, mas não otimizar ainda |

## 4. Desktop

- **Windows/Linux:** export x86_64 oficial; Linux também arm64 se a Steam exigir no futuro (não exige hoje).
  O editor da VM de automação é arm64: export x86_64 é possível, mas o binário não roda na VM — testes de
  execução são feitos no Mac (via build Web) ou em máquina x86_64.
- **macOS:** preset Universal 2 sem assinatura. Para abrir localmente: clique direito → Abrir, ou
  `xattr -dr com.apple.quarantine BlastGrid.app`. Distribuição pública nativa fica bloqueada até aprovação
  de custo (Apple Developer Program). Enquanto isso, Mac = navegador.
- **Steam Deck/Linux:** o export Linux roda no SteamOS; validar controles e resolução 1280×800 na Fase 6.

## 5. Entrada

- Input Map da Godot: `move_up/down/left/right`, `place_bomb`, `pause`, com teclado (WASD + setas, Espaço,
  ESC/P) e gamepad (D-pad, analógico esquerdo com zona morta 0,4, botão sul, Start). Configurado no Dia 05.
- Remapeamento salvo em `user://input.cfg`, válido em todas as plataformas.
- Layout de teclado: usar `physical_keycode` para WASD (funciona em AZERTY/Dvorak).

## 6. Resolução e UI

- Resolução base 1280×720, `stretch_mode = canvas_items`, `aspect = expand`; a arena 15×13 em tiles de 48 px
  (720×624) cabe com HUD lateral.
- Pixel snap ligado para sprites; fontes com fallback incluído no projeto (licença OFL).
- DPI alto (Retina) tratado pelo stretch; testar 1080p, 1440p e 4K.

## 7. Plano de testes de compatibilidade

| Teste | Quando | Como |
|---|---|---|
| Import headless do projeto | Dia 05 | `godot --headless --import` na VM |
| Export Web carrega e roda | Dia 14 | export headless + servidor estático local + smoke test com Chromium headless (Playwright) |
| Chrome / Edge / Firefox | Fase 5 | manual no Mac + roteiro |
| Safari (macOS) | Fase 5 | manual no Mac do usuário |
| Windows × navegador na mesma sala | Fase 5 | 2 clientes reais + servidor local/staging |
| Linux nativo | Fase 5/6 | máquina ou VM x86_64 |
| macOS nativo (opcional) | Fase 5 | build Universal sem assinatura no Mac do usuário |
| Gamepad USB/Bluetooth | Fase 5 | manual em desktop e navegador |

Cada teste registra: data, versão do cliente/servidor, navegador/SO e resultado real (sem marcar como
testado o que não foi executado).
