#!/usr/bin/env bash
# Instala Go e Godot em espaço de usuário ($HOME/tools) na VM Linux (arm64/x86_64)
# usada pela tarefa diária. Não exige root. Idempotente: pula o que já existe.
# Uso: source <(scripts/setup-dev-vm.sh env)   -> exporta PATH/GOROOT
#      scripts/setup-dev-vm.sh                 -> instala e mostra versões
#
# Por que conda-forge para o Go: na VM, go.dev/dl.google.com estão fora do
# allowlist de rede; conda.anaconda.org e github.com estão liberados.
set -euo pipefail

GO_VERSION="1.27.3"
GODOT_VERSION="4.7.2-stable"
TOOLS="${TOOLS_DIR:-$HOME/tools}"

case "$(uname -m)" in
  aarch64|arm64)
    GO_SUBDIR="linux-aarch64"
    GO_PKG="go-1.27.3-nocgo_h43188bd_0.conda"
    GO_SHA256="75a38701958c00e4e4b8c48b3a724133390ddcd1caba600f9a340ce8654d4eaf"
    GODOT_ZIP="Godot_v${GODOT_VERSION}_linux.arm64.zip"
    ;;
  x86_64)
    # Pacote linux-64 equivalente; o hash deve ser conferido no repodata do conda-forge.
    GO_SUBDIR="linux-64"
    GO_PKG="${GO_PKG_X86_64:?defina GO_PKG_X86_64 e GO_SHA256_X86_64 para x86_64}"
    GO_SHA256="${GO_SHA256_X86_64:?}"
    GODOT_ZIP="Godot_v${GODOT_VERSION}_linux.x86_64.zip"
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
  echo "export GOPROXY=direct GOSUMDB=off"
}

if [[ "${1:-}" == "env" ]]; then print_env; exit 0; fi

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

eval "$(print_env)"
echo "go:    $(go version)"
echo "godot: $(godot --version 2>/dev/null | tail -1)"
echo "git:   $(git --version)"
