# BlastGrid Arena — Game Design Document

Versão 0.1 (2026-11-05). Documento vivo: valores numéricos são iniciais e serão ajustados em playtest.
Os valores marcados como **regra** são parâmetros compartilhados entre a simulação Go (autoritativa)
e a simulação GDScript (offline/predição) e devem constar nos cenários de conformidade (`tests/scenarios/`).

## 1. Visão

Arena top-down 2D, partidas curtas (≈3 min), 4 jogadores (arquitetura até 8). Cada jogador coloca bombas
que explodem em cruz, destrói blocos, coleta power-ups e elimina adversários. Último vivo (ou maior
pontuação no fim do tempo) vence.

Pilares:
1. **Leitura instantânea** — grid claro, perigo sempre visível (área de explosão prevista).
2. **Justiça competitiva** — servidor autoritativo; mesma regra online e offline.
3. **Partidas curtas e caóticas** — reações em cadeia e power-ups criam viradas.
4. **Identidade original** — nenhum personagem, sprite, nome ou mapa de Bomberman ou outro jogo.

## 2. Identidade visual (original)

- Tema: "oficina de fogos de artifício" num parque de diversões noturno — blocos destrutíveis são
  caixotes de confete, paredes fixas são pilares de pedra com lanternas, bombas são "petardos" esféricos
  com pavio luminoso.
- Personagens: pequenos robôs-mascote ("Sparkies") de cabeça grande, cada um com cor e silhueta próprias.
  Cores de jogador: coral, ciano, lima, âmbar (5–8: violeta, rosa, azul, branco).
- Explosão: cruz de faíscas e confete; partículas curtas para não poluir a leitura do grid.
- Placeholders são gerados no próprio projeto (formas simples); nenhum asset de terceiros sem licença livre.

## 3. Arena

| Parâmetro | Valor | Tipo |
|---|---|---|
| Dimensões | 15 colunas × 13 linhas | regra |
| Borda | parede indestrutível em todo o perímetro | regra |
| Pilares | parede indestrutível em (x, y) com x e y pares (interno) | regra |
| Blocos destrutíveis | densidade 55–70% das células livres restantes, sorteada por seed | regra (seed) |
| Zona de spawn | cada canto: a célula de spawn + 2 vizinhas em "L" ficam sempre livres | regra |

Tipos de tile: `EMPTY`, `WALL` (indestrutível), `BLOCK` (destrutível). Bombas, power-ups e chamas são
entidades sobre o tile, não tipos de tile.

Geração é determinística a partir de um `seed` inteiro (mesmo seed ⇒ mesmo mapa em Go e GDScript),
usando um PRNG simples especificado (ver ARCHITECTURE §5) — não o RNG nativo de cada linguagem.

Spawns (4 jogadores): (1,1), (13,1), (1,11), (13,11). Para 5–8 jogadores, pontos médios das bordas
(7,1), (7,11), (1,6), (13,6) com as mesmas regras de área livre.

## 4. Personagem

- Movimento em 4 direções, contínuo, com velocidade em tiles/s.
- **Alinhamento ao grid:** o personagem anda pelo centro dos corredores. Ao pedir uma direção
  perpendicular perto de uma esquina, ele "desliza" para o centro do corredor (corner sliding) se o
  desvio for ≤ 40% de um tile (**regra**).
- Colisão contra `WALL`, `BLOCK` e bombas (ver §5); hitbox do jogador menor que um tile.
- Velocidade base: 4,0 tiles/s; +0,5 por power-up; máximo 7,0 (**regra**).
- Animações: idle, caminhada (4 direções), vitória, derrota; identificação por cor + tag de nome.
- Sistema de personagens/skins: personagem define stats base (inicialmente todos iguais); skin é só visual.

## 5. Bombas

| Parâmetro | Valor | Tipo |
|---|---|---|
| Pavio | 2,5 s | regra |
| Bombas simultâneas (base) | 1 | regra |
| Alcance (base) | 2 tiles | regra |
| Duração da chama | 0,5 s | regra |

- Bomba é colocada na célula em que o centro do jogador está; no máximo uma bomba por célula.
- Bomba bloqueia passagem. **Anti-prisão:** o jogador que a colocou (e qualquer outro jogador que já
  esteja sobrepondo a célula no momento da colocação) pode atravessá-la até sair completamente dela;
  depois disso ela passa a bloqueá-lo também.

## 6. Explosões

- Cruz a partir da célula da bomba, até `alcance` tiles em cada direção.
- `WALL` interrompe a chama (não é atingida). `BLOCK` é destruído e interrompe a chama naquela direção.
- Chama atinge bomba ⇒ essa bomba detona no mesmo tick (**reação em cadeia**, resolvida em ordem
  determinística: fila FIFO por tick, empate por id da bomba).
- Chama atinge jogador ⇒ eliminado (salvo escudo). Chama atinge power-up já exposto ⇒ destruído.
- Um bloco destruído só pode gerar drop depois que a chama daquele tick termina de ser resolvida.

## 7. Power-ups

| Power-up | Efeito | Limite |
|---|---|---|
| Faísca (alcance) | +1 alcance | 8 |
| Petardo extra | +1 bomba simultânea | 8 |
| Turbina (velocidade) | +0,5 tiles/s | 7,0 tiles/s |
| Bolha (escudo) | absorve 1 explosão ou expira em 6 s | não acumula |

- Chance de drop ao destruir bloco: 30% (**regra**, sorteio pelo mesmo PRNG da partida).
- Pesos de drop: alcance 35, bombas 35, velocidade 20, escudo 10.
- Sistema expansível: cada power-up é um `Resource` no Godot e um tipo registrado no Go, com id estável
  (`range_up`, `bomb_up`, `speed_up`, `shield`). Poderes especiais (chute de bomba, bomba remota etc.)
  entram depois do protótipo.

## 8. Modos

| Modo | Status | Regra |
|---|---|---|
| Practice | Fase 2 | 1 jogador + 3 bots, sem ranking |
| Free For All | Fase 2 (offline) / Fase 3–4 (online) | 4 jogadores, último vivo vence; tempo 3 min |
| Last Man Standing | futuro | séries de rounds, eliminação acumulada |
| Team Battle | futuro | 2×2 / 4×4, fogo amigo configurável |

Fim de partida FFA: último vivo vence. Se o tempo acabar, vence maior pontuação entre os vivos;
empate ⇒ empate. Eliminações simultâneas no mesmo tick do último par ⇒ empate.

Pontuação (servidor valida): eliminação +100, bloco +10, power-up coletado +5, vitória +300,
autoeliminação −50.

## 9. Bots (Practice)

Três bots com o mesmo conjunto de regras do jogador (sem trapaça de informação além do estado do jogo):
- Mapa de perigo: células que serão atingidas por bombas ativas (considerando cadeia) e tempo até isso.
- BFS para rota segura; só coloca bomba se existir rota de fuga alcançável antes da detonação.
- Prioridades: sobreviver > fugir > coletar power-up próximo > destruir blocos > caçar adversário.
- Dificuldade via tempo de reação e erro intencional (fácil/médio/difícil).

## 10. Controles

Teclado: WASD / setas, Espaço = bomba, ESC = pausa. Gamepad: analógico esquerdo/D-pad, botão sul = bomba,
Start = pausa. Mapeamento via Input Map da Godot, remapeável nas Configurações.

## 11. Telas

Splash, Inicial, Login, Seleção de personagem, Seleção de modo, Lobby, Busca de partida, Arena, Pausa,
Resultado, Ranking, Perfil, Configurações. HUD: cronômetro, vivos, eliminações, pontuação, power-ups,
participantes, indicador de conexão e latência (online).
