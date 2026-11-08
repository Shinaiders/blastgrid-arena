# BlastGrid Arena — Deploy

Versão 1.2 (2026-11-08). Status: `server/Dockerfile`, `docker-compose.yml`, `.env.example`,
`deploy/Caddyfile`, `.github/workflows/ci.yml` e `scripts/export-web.sh` estão implementados (Fases 1–7).
Nenhum serviço pago é dependência: as opções pagas aparecem marcadas e só serão adotadas com aprovação.

## 1. Artefatos

| Artefato | Origem | Destino |
|---|---|---|
| Binário `api` (Go, estático, `CGO_ENABLED=0`) | `server/cmd/api` (`server/Dockerfile`) | imagem Docker (`gcr.io/distroless/static-debian12:nonroot`), usuário não-root |
| Migrations | `server/migrations` embutidas no binário (`embed.FS`) | `api migrate up` |
| Build Web | export Godot `Web` via `./scripts/export-web.sh` | arquivos estáticos em `client/build/web/` (`index.html`, `.wasm`, `.pck`, `.js`) |
| Builds desktop | export Godot Windows/Linux/macOS (`client/export_presets.cfg`) | Steam (Fase 6) / download |
| Proxy reverso TLS/WSS | `deploy/Caddyfile` | Caddy servindo `/srv/blastgrid-web` + proxy para `api:8080` |
| Pipeline CI | `.github/workflows/ci.yml` | GitHub Actions (`backend`, `client`, `docker`) |

### Exportação da build Web (`scripts/export-web.sh`)

```bash
./scripts/export-web.sh              # valida export templates e gera client/build/web/index.html
./scripts/export-web.sh --serve 8000 # exporta e serve localmente em http://127.0.0.1:8000
```

## 2. Configuração (variáveis de ambiente)

Prefixo `BG_`. Validadas na inicialização; valor inválido ⇒ o processo não sobe (erro claro no log).

| Variável | Padrão | Descrição |
|---|---|---|
| `BG_ENV` | `dev` | `dev` \| `prod` (em `prod`, exige `BG_DATABASE_URL`, origens explícitas e segredos) |
| `BG_HTTP_ADDR` | `:8080` | endereço de escuta (HTTP + `/ws`) |
| `BG_LOG_LEVEL` | `info` | `debug` \| `info` \| `warn` \| `error` |
| `BG_LOG_FORMAT` | `json` | `json` \| `text` (text só para dev) |
| `BG_DATABASE_URL` | — | DSN PostgreSQL |
| `BG_DB_MAX_CONNS` / `BG_DB_MIN_CONNS` | `10` / `1` | pool pgx (máx. 1–100; mín. ≤ máx.) |
| `BG_DB_CONNECT_TIMEOUT` | `5s` | timeout de conexão e do ping inicial |
| `BG_MIGRATE_ON_START` | `false` | aplica migrations ao subir (só dev) |
| `BG_ALLOWED_ORIGINS` | `http://localhost:*` em dev | lista separada por vírgula para CORS e `OriginPatterns` do WS |
| `BG_TICK_RATE` | `20` | 20–30 |
| `BG_READ_HEADER_TIMEOUT` | `5s` | `http.Server.ReadHeaderTimeout` |
| `BG_READ_TIMEOUT` / `BG_WRITE_TIMEOUT` | `10s` / `10s` | rotas HTTP (o `/ws` usa deadlines próprios) |
| `BG_IDLE_TIMEOUT` | `60s` | keep-alive |
| `BG_SHUTDOWN_TIMEOUT` | `30s` | prazo do graceful shutdown |
| `BG_AUTH_SECRET` | — (obrigatória em prod) | chave HMAC dos access tokens (Fase 3) |
| `BG_STEAM_WEB_API_KEY` / `BG_STEAM_APP_ID` | — (opcionais) | validação de session tickets Steam em produção (`POST /v1/auth/steam`, Fase 6) |

Segredos nunca vão para o repositório: `.env` está no `.gitignore`; `.env.example` só com valores de dev.

## 3. Health checks

| Rota | Significado | Uso |
|---|---|---|
| `GET /healthz` | processo vivo (não toca no banco) | liveness / `HEALTHCHECK` do Docker (`/api healthcheck`, pois a imagem distroless não tem curl) |
| `GET /readyz` | pronto para tráfego: banco responde (`Ping` ≤ 1 s) e não está em shutdown | readiness / proxy |

Durante o shutdown `/readyz` passa a responder 503 imediatamente, para o proxy parar de mandar tráfego novo.

## 4. Ambiente de desenvolvimento

```
cp .env.example .env             # opcional; os padrões do compose servem para dev
docker compose up -d db          # PostgreSQL 16 com volume local
cd server && go run ./cmd/api    # BG_DATABASE_URL apontando para localhost:5432
# ou tudo em container:
docker compose up --build        # db → migrate (job único: api migrate up) → api :8080
curl localhost:8080/readyz       # {"checks":[{"name":"database","ok":true}],"status":"ready"}
```

Subcomandos do binário: `api` (servidor), `api migrate up|down [N]|status`, `api healthcheck`.

No Mac: Docker Desktop (gratuito para uso pessoal/empresas pequenas — verificar a licença se houver uso
comercial de maior porte), OrbStack (gratuito para uso pessoal) ou **Colima** (open source, sem restrição).
Na VM de automação não há Docker (ARCHITECTURE §7): lá se validam sintaxe e testes Go sem container.

## 5. Produção (Fase 7) — topologia mínima (`deploy/Caddyfile`)

```
Internet ──443──► Caddy (deploy/Caddyfile: TLS automático Let's Encrypt, HTTP/1.1 + upgrade WS)
                    ├── /            → arquivos da build Web (/srv/blastgrid-web)
                    ├── /v1/*        → api:8080 (+ /healthz, /readyz)
                    └── /ws          → api:8080 (WebSocket, flush_interval -1, timeouts 65s)
                  api (container) ──► PostgreSQL 16 (container com volume ou gerenciado)
```

- **Proxy/TLS (`deploy/Caddyfile`):** Caddy (Apache-2.0) — certificados gratuitos e renovação automática,
  headers de segurança (`X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`,
  `Referrer-Policy: strict-origin-when-cross-origin`), compressão `zstd`/`gzip`, entrega estática de
  `/srv/blastgrid-web` (`BG_WEB_ROOT`) e reverse proxy de `/v1/*`, `/healthz`, `/readyz` e `/ws` para
  `api:8080` (`BG_API_UPSTREAM`). Alternativa: nginx + certbot. Ambos gratuitos.
- **Hospedagem do servidor:** uma VPS pequena (2 vCPU / 2–4 GB) é suficiente para a v1. **Tem custo
  mensal → requer aprovação.** Opções gratuitas existem (ex.: camadas "always free" de nuvens públicas),
  mas com limites e políticas que mudam; avaliar na Fase 7 com dados atuais antes de decidir.
- **Build Web (`scripts/export-web.sh`):** gerada em `client/build/web/` e publicada no `/srv/blastgrid-web`
  do Caddy ou em itch.io, GitHub Pages ou Cloudflare Pages (gratuitos). Como o export é single-thread, não
  precisa de headers COOP/COEP. Se ficar em domínio diferente da API, incluir a origem em `BG_ALLOWED_ORIGINS`.
- **WebSocket atrás do proxy:** em `deploy/Caddyfile`, `read_timeout` e `write_timeout` de `/ws` são de `65s`
  (> intervalo de ping de 2 s com folga) e `flush_interval -1` desativa o buffering de resposta.

## 6. Deploy e atualização (`.github/workflows/ci.yml`)

1. CI em `.github/workflows/ci.yml` (GitHub Actions, gratuito para repositório público e com cota no privado)
   executa três jobs em paralelo:
   - `backend`: Go 1.27 + container `postgres:16-alpine`, rodando `gofmt -l .`, `go vet ./...` e
     `go test -race -v ./...` com `BG_TEST_DATABASE_URL`.
   - `client`: baixa o binário headless do Godot `4.7.2-stable` para Linux e executa
     `godot --headless --path client --import` e `godot --headless --path client -s res://tests/run_tests.gd`.
   - `docker`: executa `docker build` de `server/Dockerfile` para validar a imagem de produção.
2. Imagem marcada com o hash do commit; publicada no GitHub Container Registry (gratuito na cota).
3. Na VPS: `docker compose pull && docker compose run --rm api migrate up && docker compose up -d`.
4. **Drenagem:** como partidas vivem em memória, o container antigo recebe SIGTERM, para de aceitar salas
   (`/readyz` = 503) e espera as partidas terminarem até `BG_SHUTDOWN_TIMEOUT`. Para deploy sem derrubar
   partidas, subir a nova versão em outra porta, trocar o upstream do Caddy (`BG_API_UPSTREAM`) e só então
   parar a antiga (blue/green manual na v1). Ajustar `stop_grace_period` do compose ≥ `BG_SHUTDOWN_TIMEOUT`.
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
