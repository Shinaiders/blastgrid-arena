# syntax=docker/dockerfile:1
# Imagem de produção da API (docs/DEPLOYMENT.md §1): binário Go estático em
# distroless, usuário não-root, migrations embutidas no binário.

FROM golang:1.27-alpine AS build
WORKDIR /src
# Dependências primeiro para aproveitar o cache de camadas.
COPY go.mod go.sum ./
RUN go mod download && go mod verify
COPY . .
ARG VERSION=dev
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o /out/api ./cmd/api

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/api /api
USER nonroot:nonroot
ENV BG_HTTP_ADDR=:8080
EXPOSE 8080
# distroless não tem curl/wget: o próprio binário faz o GET /healthz.
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 CMD ["/api", "healthcheck"]
ENTRYPOINT ["/api"]
