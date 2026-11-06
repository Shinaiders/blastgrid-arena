# BlastGrid Arena — Deploy

Versão 1.0 (2026-11-06). Status: **plano**. `Dockerfile`, `docker-compose.yml` e `.env.example` são
criados no Dia 04; o deploy de produção é da Fase 7. Nenhum serviço pago é dependência: as opções pagas
aparecem marcadas e só serão adotadas com aprovação.

## 1. Artefatos

| Artefato | Origem | Destino |
|---|---|---|
| Binário `api` (Go, estático, `CGO_ENABLED=0`) | `server/cmd/api` | imagem Docker (`gcr.io/distroless/static` ou `scratch` + CA certs), usuário não-root |
| Migrations | `server/migrations` embutidas no binário (`embed.FS`) | `api migrate up` |
| Build Web | export Godot `Web` | arquivos estáticos (`index.html`, `.wasm`, `.pck`, `.js`) |
| Builds desktop | export Godot Windows/Linux/macOS | Steam (Fase 6) / download |

## 2. Configuração (variáveis de ambiente)

Prefixo `BG_`. Validadas na inicialização; valor inválido ⇒ o processo não sobe (erro claro no log).

| Variável | Padrão | Descrição |
|---|---|---|
| `BG_ENV` | `dev` | `dev` \| `prod` (em `prod`, exige `BG_DATABASE_URL`, origens explícitas e segredos) |
| `BG_HTTP_ADDR` | `:8080` | endereço de escuta (HTTP + `/ws`) |
| `BG_LOG_LEVEL` | `info` | `debug` \| `info` \| `warn` \| `error` |
| `BG_LOG_FORMAT` | `json` | `json` \| `text` (text só para dev) |
| `BG_DATABASE_URL` | — | DSN PostgreSQL |
| `BG_DB_MAX_CONNS` / `BG_DB_MIN_CONNS` | `10` / `1` | pool pgx |
| `BG_MIGRATE_ON_START` | `false` | aplica migrations ao subir (só dev) |
| `BG_ALLOWED_ORIGINS` | `http://localhost:*` em dev | lista separada por vírgula para CORS e `OriginPatterns` do WS |
| `BG_TICK_RATE` | `20` | 20–30 |
| `BG_READ_HEADER_TIMEOUT` | `5s` | `http.Server.ReadHeaderTimeout` |
| `BG_READ_TIMEOUT` / `BG_WRITE_TIMEOUT` | `10s` / `10s` | rotas HTTP (o `/ws` usa deadlines próprios) |
| `BG_IDLE_TIMEOUT` | `60s` | keep-alive |
| `BG_SHUTDOWN_TIMEOUT` | `30s` | prazo do graceful shutdown |
| `BG_AUTH_SECRET` | — (obrigatória em prod) | chave HMAC dos access tokens (Fase 3) |

Segredos nunca vão para o repositório: `.env` está no `.gitignore`; `.env.example` só com valores de dev.

## 3. Health checks

| Rota | Significado | Uso |
|---|---|---|
| `GET /healthz` | processo vivo (não toca no banco) | liveness / `HEALTHCHECK` do Docker |
| `GET /readyz` | pronto para tráfego: banco responde (`Ping` ≤ 1 s) e não está em shutdown | readiness / proxy |

Durante o shutdown `/readyz` passa a responder 503 imediatamente, para o proxy parar de mandar tráfego novo.

## 4. Ambiente de desenvolvimento

```
docker compose up -d db          # PostgreSQL 16 com volume local
cd server && go run ./cmd/api    # BG_DATABASE_URL apontando para localhost:5432
# ou tudo em container:
docker compose up --build
```

No Mac: Docker Desktop (gratuito para uso pessoal/empresas pequenas — verificar a licença se houver uso
comercial de maior porte), OrbStack (gratuito para uso pessoal) ou **Colima** (open source, sem restrição).
Na VM de automação não há Docker (ARCHITECTURE §7): lá se validam sintaxe e testes Go sem container.

## 5. Produção (Fase 7) — topologia mínima

```
Internet ──443──► Caddy (TLS automático Let's Encrypt, HTTP/1.1 + upgrade WS)
                    ├── /            → arquivos da build Web (ou hospedagem estática separada)
                    ├── /v1/*        → api:8080
                    └── /ws          → api:8080 (WebSocket, timeouts longos)
                  api (container) ──► PostgreSQL 16 (container com volume ou gerenciado)
```

- **Proxy/TLS:** Caddy (Apache-2.0) — certificados gratuitos e renovação automática. Alternativa: nginx +
  certbot. Ambos gratuitos.
- **Hospedagem do servidor:** uma VPS pequena (2 vCPU / 2–4 GB) é suficiente para a v1. **Tem custo
  mensal → requer aprovação.** Opções gratuitas existem (ex.: camadas "always free" de nuvens públicas),
  mas com limites e políticas que mudam; avaliar na Fase 7 com dados atuais antes de decidir.
- **Build Web:** itch.io, GitHub Pages ou Cloudflare Pages (gratuitos). Como o export é single-thread, não
  precisa de headers COOP/COEP. Se ficar em domínio diferente da API, incluir a origem em `BG_ALLOWED_ORIGINS`.
- **WebSocket atrás do proxy:** timeout de leitura do proxy > intervalo de ping (2 s) com folga (ex.: 60 s);
  sem buffering de resposta para `/ws`.

## 6. Deploy e atualização

1. CI (GitHub Actions, gratuito para repositório público e com cota no privado) roda `go vet`, `go test
   -race ./...`, testes headless Godot e build da imagem.
2. Imagem marcada com o hash do commit; publicada no GitHub Container Registry (gratuito na cota).
3. Na VPS: `docker compose pull && docker compose run --rm api migrate up && docker compose up -d`.
4. **Drenagem:** como partidas vivem em memória, o container antigo recebe SIGTERM, para de aceitar salas
   (`/readyz` = 503) e espera as partidas terminarem até `BG_SHUTDOWN_TIMEOUT`. Para deploy sem derrubar
   partidas, subir a nova versão em outra porta, trocar o upstream do Caddy e só então parar a antiga
   (blue/green manual na v1). Ajustar `stop_grace_period` do compose ≥ `BG_SHUTDOWN_TIMEOUT`.
5. Migrations devem ser compatíveis com a versão anterior do binário (expandir → migrar → contrair).

## 7. Observabilidade

- Logs JSON (`log/slog`) no stdout: `time, level, msg, request_id, room_id, match_id, player_id, platform`.
  Eventos obrigatórios: start/stop, conexão aceita/fechada (com código), sala criada/destruída, partida
  iniciada/terminada, rate limit, mensagens inválidas, erros de persistência.
- Métricas (Fase 4+): `GET /metrics` em formato texto Prometheus, implementado à mão ou com a lib oficial
  (Apache-2.0), protegido por rede interna. Grafana/Prometheus são gratuitos e opcionais.

## 8. Backup e recuperação

- `pg_dump -Fc` diário via cron no host ou container auxiliar; retenção de 7 dias local + cópia externa
  (destino gratuito a definir; armazenamento pago só com aprovação).
- Teste de restauração mensal num banco descartável (`pg_restore` + `api migrate status`).

## 9. Segurança operacional

- Container sem root, sistema de arquivos read-only, só a porta 8080 exposta para o proxy.
- PostgreSQL sem porta pública; senha forte via variável; `sslmode=require` se o banco for externo.
- Rate limit HTTP por IP nas rotas de autenticação (Fase 3) além do limite por conexão no WS.
