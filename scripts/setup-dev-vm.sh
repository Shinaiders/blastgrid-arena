#!/usr/bin/env bash
# Instala Go e Godot em espaço de usuário ($HOME/tools) na VM Linux (arm64/x86_64)
# usada pela tarefa diária. Não exige root. Idempotente: pula o que já existe.
# Também instala PostgreSQL 16 (conda-forge via micromamba) e monta um GOPROXY file:// com os
# módulos gopkg.in/golang.org/x que a rede da VM não alcança (scripts/vm-gomirror.sh).
# Uso: source <(scripts/setup-dev-vm.sh env)   -> exporta PATH/GOROOT/GOPROXY
#      scripts/setup-dev-vm.sh                 -> instala e mostra versões
#      scripts/setup-dev-vm.sh pg-start        -> sobe o PostgreSQL local (porta 55432) e cria os bancos
#
# Por que conda-forge para o Go: na VM, go.dev/dl.google.com estão fora do
# allowlist de rede; conda.anaconda.org e github.com estão liberados.
set -euo pipefail

GO_VERSION="1.27.3"
GODOT_VERSION="4.7.2-stable"
MICROMAMBA_VERSION="2.10.0"
PG_MAJOR="16"
PG_PORT="55432"
# Módulos que o go.mod precisa e que só chegam pela cópia no GitHub (atualizar junto com o go.sum).
GO_MIRRORED=(
  "gopkg.in/yaml.v3 v3.0.0-20200313102051-9f266ea9e77c"
  "gopkg.in/yaml.v3 v3.0.1"
  "gopkg.in/check.v1 v0.0.0-20161208181325-20d25e280405"
  "golang.org/x/text v0.41.0"
  "golang.org/x/sync v0.22.0"
)
TOOLS="${TOOLS_DIR:-$HOME/tools}"

case "$(uname -m)" in
  aarch64|arm64)
    GO_SUBDIR="linux-aarch64"
    GO_PKG="go-1.27.3-nocgo_h43188bd_0.conda"
    GO_SHA256="75a38701958c00e4e4b8c48b3a724133390ddcd1caba600f9a340ce8654d4eaf"
    GODOT_ZIP="Godot_v${GODOT_VERSION}_linux.arm64.zip"
    MM_ARCH="linux-aarch64"
    ;;
  x86_64)
    # Pacote linux-64 equivalente; o hash deve ser conferido no repodata do conda-forge.
    GO_SUBDIR="linux-64"
    GO_PKG="${GO_PKG_X86_64:?defina GO_PKG_X86_64 e GO_SHA256_X86_64 para x86_64}"
    GO_SHA256="${GO_SHA256_X86_64:?}"
    GODOT_ZIP="Godot_v${GODOT_VERSION}_linux.x86_64.zip"
    MM_ARCH="linux-64"
    ;;
  *) echo "arquitetura não suportada: $(uname -m)" >&2; exit 1 ;;
esac

GOROOT_DIR="$TOOLS/go-$GO_VERSION/go"
GODOT_BIN="$TOOLS/${GODOT_ZIP%.zip}"

print_env() {
  echo "export GOROOT=$GOROOT_DIR"
  echo "export GOPATH=\$HOME/gopath"
  echo "export PATH=$GOROOT_DIR/bin:$TOOLS/bin:\$PATH"
  # proxy.golang.org e sum.golang.org bloqueados na VM: módulos vêm direto do VCS.
  # go.sum continua fixando os hashes; revalidar com sum.golang.org fora da VM.
  echo "export GOPROXY=file://$TOOLS/goproxy,direct GOSUMDB=off GOFLAGS=-modcacherw"
  # O Go do conda-forge vem com CC=/dev/null; o gcc do sistema habilita go test -race.
  echo "export CC=gcc"
  echo "export PATH=$TOOLS/pg/bin:\$PATH"
  echo "export BG_TEST_DATABASE_URL=postgres://blastgrid:blastgrid@127.0.0.1:$PG_PORT/blastgrid_test?sslmode=disable"
}

pg_start() {
  local data="$TOOLS/pgdata"
  export PATH="$TOOLS/pg/bin:$PATH"
  if [[ ! -d "$data" ]]; then
    initdb -D "$data" -U postgres --auth=trust -E UTF8 >/dev/null
    local fresh=1
  fi
  if ! pg_ctl -D "$data" status >/dev/null 2>&1; then
    rm -f "$data/postmaster.pid"
    pg_ctl -D "$data" -o "-p $PG_PORT -k /tmp -c listen_addresses=127.0.0.1" -l "$TOOLS/pg.log" -w start >/dev/null
  fi
  if [[ "${fresh:-0}" == 1 ]]; then
    psql -h 127.0.0.1 -p "$PG_PORT" -U postgres -q -c "CREATE ROLE blastgrid LOGIN PASSWORD 'blastgrid'" \
      -c "CREATE DATABASE blastgrid OWNER blastgrid" -c "CREATE DATABASE blastgrid_test OWNER blastgrid"
  fi
  echo "postgres: $(postgres --version) em 127.0.0.1:$PG_PORT"
}

if [[ "${1:-}" == "env" ]]; then print_env; exit 0; fi
# Processos em segundo plano não sobrevivem entre chamadas do device_bash: subir o banco
# na mesma chamada dos testes (scripts/setup-dev-vm.sh pg-start && go test ./...).
if [[ "${1:-}" == "pg-start" ]]; then pg_start; exit 0; fi

mkdir -p "$TOOLS/bin"

if [[ ! -x "$GOROOT_DIR/bin/go" ]]; then
  echo ">> instalando Go $GO_VERSION (conda-forge $GO_SUBDIR)"
  tmp="$(mktemp -d)"
  curl -fsSL "https://conda.anaconda.org/conda-forge/$GO_SUBDIR/$GO_PKG" -o "$tmp/$GO_PKG"
  echo "$GO_SHA256  $tmp/$GO_PKG" | sha256sum -c -
  (cd "$tmp" && unzip -q "$GO_PKG")
  mkdir -p "$TOOLS/go-$GO_VERSION"
  zstd -dc "$tmp"/pkg-*.tar.zst | tar -x -C "$TOOLS/go-$GO_VERSION"
  rm -rf "$tmp"
fi

if [[ ! -x "$GODOT_BIN" ]]; then
  echo ">> instalando Godot $GODOT_VERSION"
  tmp="$(mktemp -d)"
  base="https://github.com/godotengine/godot/releases/download/$GODOT_VERSION"
  curl -fsSL "$base/$GODOT_ZIP" -o "$tmp/$GODOT_ZIP"
  curl -fsSL "$base/SHA512-SUMS.txt" -o "$tmp/SHA512-SUMS.txt"
  (cd "$tmp" && grep " $GODOT_ZIP\$" SHA512-SUMS.txt | sha512sum -c -)
  unzip -oq "$tmp/$GODOT_ZIP" -d "$TOOLS"
  rm -rf "$tmp"
fi
ln -sf "$GODOT_BIN" "$TOOLS/bin/godot"

if [[ ! -x "$TOOLS/pg/bin/postgres" ]]; then
  echo ">> instalando PostgreSQL $PG_MAJOR (conda-forge via micromamba $MICROMAMBA_VERSION)"
  curl -fsSL -o "$TOOLS/bin/micromamba" \
    "https://github.com/mamba-org/micromamba-releases/releases/download/$MICROMAMBA_VERSION-0/micromamba-$MM_ARCH"
  chmod +x "$TOOLS/bin/micromamba"
  MAMBA_ROOT_PREFIX="$TOOLS/mamba" "$TOOLS/bin/micromamba" create -y -q -p "$TOOLS/pg" -c conda-forge "postgresql=$PG_MAJOR"
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for m in "${GO_MIRRORED[@]}"; do
  read -r mod ver <<<"$m"
  [[ -f "$TOOLS/goproxy/$mod/@v/$ver.zip" ]] || TOOLS_DIR="$TOOLS" bash "$here/vm-gomirror.sh" "$mod" "$ver"
done

eval "$(print_env)"
echo "go:    $(go version)"
echo "godot: $(godot --version 2>/dev/null | tail -1)"
echo "git:   $(git --version)"
echo "pg:    $(postgres --version)"
