# Projeto: BlastGrid Arena

Atue como um arquiteto de software sênior, desenvolvedor de jogos multiplayer e especialista em Godot Engine 4 e Go (Golang).

Quero desenvolver um jogo 2D multiplayer competitivo inspirado na mecânica clássica de Bomberman, mas com identidade visual, personagens, mapas, mecânicas e sistemas originais.

O jogo deverá ser multiplataforma, com prioridade para:

1. Steam (Windows e Linux).
2. Navegadores (Chrome, Edge, Firefox e Safari).
3. macOS nativo como plataforma opcional, desde que a distribuição não exija custos adicionais que não sejam aprovados previamente.

A versão de navegador deverá funcionar também em computadores macOS, permitindo que jogadores dessa plataforma participem das mesmas partidas online.

O objetivo é desenvolver um jogo comercialmente apresentável, utilizando tecnologias gratuitas, open source e uma arquitetura preparada para crescimento.

# 1. Stack tecnológica obrigatória

## Game Client

- Godot Engine 4, versão estável.
- GDScript.
- Renderer Compatibility.
- WebAssembly.
- WebGL 2.0.
- Godot WebSocketPeer para comunicação com o backend.
- Git para versionamento.

## Backend

- Go (Golang), versão estável disponível no ambiente.
- net/http para APIs HTTP.
- github.com/coder/websocket para comunicação WebSocket.
- PostgreSQL para persistência.
- pgx para conexão com PostgreSQL.
- Migrations SQL.
- Docker e Docker Compose.

## Infraestrutura

- Backend compilado como binário Go.
- Container Docker para produção.
- PostgreSQL.
- HTTPS/WSS.
- Logs estruturados.
- Health checks.
- Configurações por variáveis de ambiente.

Não utilizar NestJS, Node.js, Firebase, Supabase ou serviços pagos como dependências obrigatórias da arquitetura.

Não utilizar Unity, Unreal Engine ou C#.

Evitar microserviços desnecessários. Começar com um backend Go modular, organizado em um único serviço.

# 2. Conceito visual e gameplay

Nome provisório: BlastGrid Arena.

Criar um jogo 2D com visão top-down, visual cartoon, personagens pequenos e expressivos, cenários coloridos e efeitos visuais de explosões.

Referência estética:
- Arenas quadriculadas.
- Obstáculos destrutíveis.
- Paredes de pedra.
- Personagens estilizados.
- Bombas com explosões em cruz.
- Power-ups coloridos.
- Efeitos de partículas.
- Interface competitiva moderna.

Não copiar personagens, sprites, nomes, mapas ou recursos protegidos de Bomberman ou outros jogos.

Criar uma identidade visual original.

# 3. Mecânicas principais

Criar arenas baseadas em grid.

Dimensões iniciais:
- 15 colunas.
- 13 linhas.
- Paredes indestrutíveis.
- Blocos destrutíveis.
- Áreas livres para movimentação.
- Distribuição variável dos obstáculos.

## Personagens

- Movimentação em quatro direções.
- Movimento suave com alinhamento ao grid.
- Colisões precisas.
- Animações de caminhada.
- Animações de vitória e derrota.
- Identificação visual dos jogadores.
- Sistema preparado para diferentes personagens e skins.

## Bombas

- Posicionamento de bombas.
- Detonação inicialmente em 2,5 segundos.
- Alcance configurável.
- Explosão em cruz.
- Destruição de blocos.
- Eliminação de adversários.
- Reação em cadeia.
- Bloqueio de passagem pelas bombas.
- Controle de colisões.
- Proteção contra situações em que a movimentação deixe o jogador preso indevidamente.

## Power-ups

- Aumento de alcance das explosões.
- Aumento da quantidade de bombas.
- Aumento da velocidade.
- Escudo temporário.
- Poderes especiais.
- Sistema expansível para futuras habilidades.

# 4. Modos de jogo

Preparar:

- Free For All.
- Team Battle.
- Last Man Standing.
- Practice.

Implementar inicialmente Free For All e Practice.

Configuração inicial:
- 4 participantes por partida.
- Arquitetura preparada para até 8 jogadores.

Criar três bots para partidas de treinamento.

Os bots devem:
- Procurar adversários.
- Evitar explosões.
- Posicionar bombas estrategicamente.
- Coletar power-ups.
- Evitar armadilhas.
- Identificar rotas seguras.

# 5. Arquitetura do Backend Go

Esta é uma das partes mais importantes do projeto.

O backend deve ser desenvolvido em Go e ser independente da engine Godot.

Estruturar o projeto de forma modular.

Responsabilidades do backend:

## API HTTP

Criar endpoints para:

- Health check.
- Cadastro e autenticação.
- Sessões.
- Perfil do jogador.
- Estatísticas.
- Ranking.
- Criação de salas.
- Consulta de salas.
- Entrada e saída de salas.
- Histórico de partidas.
- Resultados das partidas.

## WebSocket

Criar comunicação em tempo real utilizando:

github.com/coder/websocket

A comunicação deve funcionar tanto para:
- Godot Windows.
- Godot Linux.
- Godot macOS.
- Godot Web.

Utilizar WSS em produção.

Criar um protocolo de comunicação versionado, documentado e independente de plataforma.

Inicialmente utilizar mensagens JSON para facilitar desenvolvimento e depuração.

Preparar uma evolução para mensagens binárias caso os testes de desempenho justifiquem.

## Servidor autoritativo

O servidor Go deve ser responsável pela autoridade das partidas online.

O servidor deve validar:

- Movimentação.
- Velocidade dos jogadores.
- Posicionamento de bombas.
- Tempo de detonação.
- Alcance das explosões.
- Colisões.
- Destruição de blocos.
- Coleta de power-ups.
- Eliminações.
- Condições de vitória.
- Pontuação.

Nunca aceitar do cliente a informação de que ele venceu, eliminou alguém ou conseguiu determinada pontuação sem validação do servidor.

O cliente deverá enviar intenções e comandos de entrada.

O servidor deverá processar as ações e enviar estados validados.

Implementar:
- Identificadores sequenciais de comandos.
- Ticks de simulação.
- Sincronização de relógios.
- Interpolação.
- Predição local para melhorar a sensação de movimentação.
- Reconciliação quando o servidor corrigir uma posição.
- Proteção contra comandos inválidos.
- Limites de frequência de mensagens.

Começar avaliando uma simulação de 20 a 30 ticks por segundo, ajustando após testes reais.

A simulação online do Go será a fonte definitiva da verdade.

A simulação local em GDScript será utilizada para treinamento offline e predição visual, seguindo os mesmos parâmetros e casos de teste das regras do servidor.

Criar testes de conformidade com cenários compartilhados para evitar diferenças entre as duas implementações.

# 6. Sistema de multiplayer cross-platform

O jogo deverá permitir que:

- Jogadores da Steam joguem juntos.
- Jogadores do navegador joguem juntos.
- Jogadores macOS pelo navegador participem.
- Todos entrem na mesma sala.
- Todos participem da mesma partida.
- Todos compartilhem o mesmo ranking.

Não criar sistemas separados de matchmaking para cada plataforma.

Criar uma camada de transporte independente da lógica do jogo.

Começar com WebSocket para todos os clientes, utilizando o mesmo protocolo.

Não utilizar o protocolo multiplayer interno da Godot como se fosse automaticamente compatível com um servidor WebSocket Go.

Implementar um cliente WebSocket próprio em GDScript, com mensagens documentadas e tratamento de reconexão.

Preparar uma interface que permita futuramente implementar WebRTC DataChannels utilizando Pion no backend Go, caso os testes de latência demonstrem necessidade.

Não adicionar complexidade de WebRTC na primeira versão sem justificativa técnica.

# 7. Banco de dados

Utilizar PostgreSQL.

Criar estrutura inicial para:

- users.
- user_profiles.
- characters.
- skins.
- matches.
- match_players.
- rankings.
- player_statistics.
- achievements.
- player_inventory.

Preparar migrations SQL versionadas.

Regras importantes:
- Não armazenar o estado completo de cada frame no PostgreSQL.
- Manter o estado ativo das partidas em memória no servidor Go.
- Persistir resultados ao término das partidas.
- Criar índices para consultas de ranking.
- Evitar consultas desnecessárias.
- Preparar sistema de transações.

Não utilizar Redis inicialmente.

Adicionar Redis somente quando existir necessidade real de compartilhamento de estado, filas ou escalabilidade horizontal.

# 8. Sistema de autenticação

Criar uma camada de autenticação independente da plataforma.

Preparar:

## Browser
- Autenticação por conta do jogo.
- Sessão segura.
- Opção de convidado para testes.
- Token de acesso e renovação.

## Steam
- Integração futura com autenticação Steamworks.
- Validar Steam Authentication Tickets no backend.
- Vincular conta Steam ao perfil do jogo.

Não confiar em identificadores Steam enviados livremente pelo cliente.

A integração Steam deve ser opcional e isolada para builds nativas.

A versão web não pode depender de Steamworks.

# 9. Telas do jogo

Criar:

1. Splash Screen.
2. Tela inicial.
3. Login.
4. Seleção de personagens.
5. Seleção de modos.
6. Lobby.
7. Busca por partidas.
8. Arena.
9. Menu de pausa.
10. Resultado da partida.
11. Ranking.
12. Perfil.
13. Configurações.

Durante o jogo exibir:

- Cronômetro.
- Jogadores vivos.
- Eliminações.
- Pontuação.
- Power-ups.
- Identificação dos participantes.
- Indicador de conexão.
- Latência aproximada.

Criar interfaces com aparência comercial, moderna e consistente.

# 10. Controles

Teclado:
- WASD para movimentação.
- Setas direcionais como alternativa.
- Espaço para posicionar bomba.
- ESC para pausar.

Preparar suporte a controles USB e Bluetooth através do sistema de input da Godot.

Preparar mapeamento de comandos para controle e teclado.

# 11. Compatibilidade com plataformas

A compatibilidade deve ser tratada como requisito desde o início.

## Windows

Exportação desktop nativa.

Compatível com Steam.

## Linux

Exportação desktop nativa.

Compatível com Steam.

## macOS

Preparar preset opcional de exportação para macOS.

Preferir binário Universal 2, cobrindo Intel e Apple Silicon.

Testar o aplicativo localmente quando houver ambiente macOS disponível.

Não exigir assinatura paga para desenvolver ou testar localmente.

Antes de implementar assinatura, certificados ou notarização, verificar se existe custo adicional.

Não contratar plano Apple Developer ou qualquer serviço pago sem aprovação.

Se a publicação nativa no macOS exigir custos adicionais que não tenham sido aprovados, manter a versão web como opção oficial para usuários de Mac.

## Web

A versão web deverá ser prioridade para distribuição sem custos adicionais de plataforma.

Utilizar:
- HTML5.
- WebAssembly.
- WebGL 2.0.
- Renderer Compatibility.
- Exportação single-thread.
- Compatibilidade com navegadores modernos.

Evitar dependências nativas que impeçam a exportação Web.

Não utilizar plugins que exijam bibliotecas incompatíveis com navegador.

# 12. Organização dos diretórios

Estruturar o repositório assim:

blastgrid-arena/
  client/
    project.godot
    assets/
      characters/
      maps/
      effects/
      audio/
      ui/
    scenes/
      main/
      menu/
      arena/
      players/
      bombs/
      powerups/
      ui/
    scripts/
      core/
      gameplay/
      ai/
      networking/
      platform/
      ui/
    resources/
    export_presets.cfg/

  server/
    go.mod
    cmd/
      api/
        main.go
    internal/
      config/
      http/
      auth/
      users/
      profiles/
      lobby/
      matchmaking/
      game/
        engine/
        simulation/
        rooms/
        rules/
      websocket/
      ranking/
      persistence/
      platform/
      security/
    migrations/
    tests/

  docs/
    GDD.md
    ARCHITECTURE.md
    NETWORK_PROTOCOL.md
    DATABASE.md
    MULTIPLAYER.md
    DEPLOYMENT.md
    PLATFORM_COMPATIBILITY.md
    ROADMAP.md

  docker-compose.yml
  .env.example
  .gitignore
  README.md

Ajustar os diretórios se houver uma justificativa arquitetural.

Não criar arquivos ou módulos vazios apenas para preencher estrutura.

# 13. Segurança e qualidade

Implementar:
- Validação de todas as mensagens recebidas.
- Limites de tamanho dos pacotes.
- Rate limiting.
- Verificação de origem das conexões web.
- Autenticação das sessões.
- Proteção contra replay de comandos.
- Proteção contra manipulação de pontuação.
- Logs de eventos importantes.
- Graceful shutdown.
- Timeouts.
- Tratamento de desconexões.
- Testes de concorrência no backend.
- Testes de integração.
- Testes de simulação.

Não confiar na interface do jogo para impor regras competitivas.

# 14. Testes

Criar testes para:

- Movimentação.
- Colisões.
- Explosões.
- Reação em cadeia.
- Destruição de blocos.
- Power-ups.
- Eliminações.
- Vitória.
- Sincronização.
- Desconexões.
- Reconexões.
- Salas com 4 jogadores.
- Salas com 8 jogadores.
- Comunicação entre builds diferentes.

Validar a exportação para navegador e testar em Chrome, Firefox, Edge e Safari quando os ambientes estiverem disponíveis.

Criar testes específicos para o protocolo de mensagens entre Godot e Go.

# 15. Organização das fases

Não desenvolver todo o projeto de uma vez.

## FASE 1 — Fundação

- Verificar ambiente.
- Verificar Godot.
- Verificar Go.
- Criar estrutura de diretórios.
- Criar documentação.
- Criar projeto Godot.
- Criar backend Go.
- Criar configuração Docker.
- Criar endpoint de health check.
- Criar PostgreSQL e migrations iniciais.

## FASE 2 — Primeiro protótipo jogável

- Criar arena.
- Criar personagem.
- Criar movimentação.
- Criar colisões.
- Criar bombas.
- Criar explosões.
- Criar destruição de blocos.
- Criar power-ups.
- Criar bots.
- Criar HUD.

O objetivo é ter um jogo funcional, mesmo sem multiplayer online.

## FASE 3 — Servidor Go

- Criar sistema de autenticação.
- Criar sistema de salas.
- Criar comunicação WebSocket.
- Criar protocolo de mensagens.
- Implementar servidor autoritativo.
- Implementar controle de partidas.
- Implementar validação de ações.
- Criar testes com múltiplos clientes.

## FASE 4 — Multiplayer competitivo

- Salas públicas.
- Salas privadas.
- Matchmaking.
- Quatro a oito jogadores.
- Reconexão.
- Sistema de pontuação.
- Estatísticas.
- Ranking.

## FASE 5 — Cross-platform

- Testar multiplayer local.
- Testar comunicação pelo navegador.
- Testar conexão entre Windows e navegador.
- Validar macOS pelo navegador.
- Preparar build nativa opcional macOS.
- Testar compatibilidade e desempenho.
- Corrigir problemas.

## FASE 6 — Steam

- Preparar integração Steamworks.
- Autenticação.
- Identidade dos jogadores.
- Lobbies.
- Convites.
- Conquistas.
- Estatísticas.
- Builds Windows e Linux.
- Preparar build macOS caso seja viável sem custos adicionais não aprovados.

## FASE 7 — Publicação

- Preparar hospedagem web.
- Preparar deploy Go.
- Configurar HTTPS/WSS.
- Preparar builds.
- Criar página do jogo.
- Preparar assets de loja.
- Documentar instalação e publicação.

# 16. Regras de trabalho do Claude Code

Antes de desenvolver:

1. Analisar os arquivos da pasta.
2. Verificar versões e ferramentas instaladas.
3. Identificar incompatibilidades.
4. Criar GDD.md.
5. Criar ARCHITECTURE.md.
6. Criar ROADMAP.md.
7. Documentar as decisões técnicas.

Durante o desenvolvimento:

- Criar arquivos reais.
- Implementar funcionalidades reais.
- Não entregar apenas exemplos de código.
- Validar cada etapa.
- Testar as alterações.
- Corrigir erros antes de avançar.
- Documentar funcionalidades implementadas.
- Evitar código duplicado.
- Manter o projeto simples e modular.
- Não implementar funcionalidades futuras antes de estabelecer as fundações necessárias.

Não afirmar que um teste foi realizado se não foi executado.

Não adicionar serviços pagos, APIs pagas, plugins premium ou assinaturas sem minha autorização.

Se uma tecnologia gerar custos adicionais, apresentar uma alternativa gratuita antes de adotá-la.

Não substituir Go no backend por outra linguagem.

Não substituir Godot no cliente por outra engine.

# OBJETIVO FINAL

Construir o BlastGrid Arena: um jogo 2D multiplayer competitivo, com identidade visual própria, backend autoritativo em Go e cliente desenvolvido em Godot 4.

O mesmo jogo deverá permitir partidas entre jogadores da Steam, Windows, Linux e navegadores, incluindo usuários de macOS.

A prioridade será construir uma base sólida, gratuita para desenvolver, fácil de manter, com boa performance e preparada para crescer.

Comece analisando o ambiente e execute a FASE 1. Em seguida, implemente a primeira versão jogável da FASE 2.

Não tente implementar todo o projeto em uma única etapa.