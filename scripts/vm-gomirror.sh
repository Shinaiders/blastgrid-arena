#!/usr/bin/env bash
# Espelha um módulo gopkg.in/* ou golang.org/x/* (a partir do GitHub) num GOPROXY file:// local.
# Motivo: na VM da automação, proxy.golang.org, sum.golang.org, gopkg.in e golang.org estão fora do
# allowlist de rede; github.com está liberado. Os zips são montados com `git archive` sem entradas de
# diretório, o que reproduz o hash h1: oficial — conferido em 2026-11-06 contra o go.sum do pgx v5.12.0
# (24/24 linhas iguais). Fora da VM nada disso é necessário: use o GOPROXY padrão.
# uso: scripts/vm-gomirror.sh <módulo> <versão>
set -euo pipefail
mod="$1"; ver="$2"
case "$mod" in
  golang.org/x/*) pkg=x-${mod#golang.org/x/}; gh=golang/${mod#golang.org/x/};;
  gopkg.in/*) name=${mod#gopkg.in/}; pkg=${name%.v*}
    case "$pkg" in yaml) gh=go-yaml/yaml;; check) gh=go-check/check;; *) gh="go-$pkg/$pkg";; esac;;
  *) echo "módulo não suportado: $mod" >&2; exit 1;;
esac
repo=${TOOLS_DIR:-$HOME/tools}/mirrors/$pkg.git
[ -d "$repo" ] || git clone -q --bare "https://github.com/$gh.git" "$repo"
out=${TOOLS_DIR:-$HOME/tools}/goproxy/$mod/@v; mkdir -p "$out"
case "$ver" in *-*-*) rev="${ver##*-}";; *) rev="${ver%+incompatible}";; esac
full=$(git -C "$repo" rev-parse "$rev^{commit}")
t=$(date -u -d "$(git -C "$repo" show -s --format=%cI "$full")" +%Y-%m-%dT%H:%M:%SZ)
if git -C "$repo" cat-file -e "$full:go.mod" 2>/dev/null; then git -C "$repo" show "$full:go.mod" > "$out/$ver.mod"; else echo "module $mod" > "$out/$ver.mod"; fi
printf '{"Version":"%s","Time":"%s"}\n' "$ver" "$t" > "$out/$ver.info"
git -C "$repo" archive --format=zip --prefix="$mod@$ver/" "$full" > "$out/$ver.raw.zip"
# o h1 do Go cobre só arquivos regulares: remover entradas de diretório do zip do git archive
python3 - "$out/$ver.raw.zip" "$out/$ver.zip" <<'PY'
import sys, zipfile
src, dst = sys.argv[1:]
with zipfile.ZipFile(src) as zi, zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as zo:
    for i in zi.infolist():
        if not i.is_dir():
            zo.writestr(i.filename, zi.read(i))
PY
rm "$out/$ver.raw.zip"
ls "$out" | grep '\.info$' | sed 's/\.info$//' > "$out/list"
echo "ok $mod@$ver ($gh $full)"
