#!/usr/bin/env bash
# BlastGrid Arena — Exporta a build Web do cliente Godot 4 e opcionalmente
# sobe um servidor HTTP local para teste rápido (docs/DEPLOYMENT.md §1 e §5).
#
# Uso:
#   ./scripts/export-web.sh              # apenas gera client/build/web/index.html
#   ./scripts/export-web.sh --serve      # exporta e serve em http://127.0.0.1:8000
#   ./scripts/export-web.sh --serve 3000 # exporta e serve na porta informada
#
# Variáveis opcionais:
#   GODOT_BIN — caminho ou nome do binário do Godot (padrão: godot).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLIENT_DIR="${ROOT_DIR}/client"
OUT_DIR="${CLIENT_DIR}/build/web"
OUT_FILE="build/web/index.html"
GODOT_BIN="${GODOT_BIN:-godot}"

if ! command -v "${GODOT_BIN}" >/dev/null 2>&1; then
	echo "Erro: binário do Godot ('${GODOT_BIN}') não encontrado no PATH." >&2
	echo "Defina GODOT_BIN=/caminho/para/godot ou adicione o Godot 4.7.2 ao PATH." >&2
	exit 1
fi

GODOT_RAW_VERSION="$("${GODOT_BIN}" --version 2>/dev/null | head -n 1 | tr -d '\r')"
# Exemplo de saída de `godot --version`: "4.7.2.stable.official.f8a3c1234"
# O diretório de templates usa os componentes até o canal (ex.: "4.7.2.stable").
TEMPLATE_VERSION="$(echo "${GODOT_RAW_VERSION}" | awk -F. '{print $1"."$2"."$3"."$4}')"

check_templates() {
	local candidates=(
		"${HOME}/Library/Application Support/Godot/export_templates/${TEMPLATE_VERSION}"
		"${HOME}/.local/share/godot/export_templates/${TEMPLATE_VERSION}"
		"${APPDATA:-}/Godot/export_templates/${TEMPLATE_VERSION}"
	)
	for dir in "${candidates[@]}"; do
		if [[ -n "${dir}" && -f "${dir}/web_nothreads_release.zip" ]]; then
			return 0
		fi
	done
	return 1
}

if ! check_templates; then
	cat >&2 <<EOF
Erro: export templates do Godot (${TEMPLATE_VERSION}) para Web não encontrados.

Para instalar:
  1. Pelo editor: Editor -> Manage Export Templates -> Download and Install
  2. Ou via linha de comando (substitua a versão se necessário):
     curl -fL -o /tmp/templates.tpz \\
       "https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"
     unzip -q /tmp/templates.tpz
     # Mova a pasta 'templates/' para:
     #   macOS: ~/Library/Application Support/Godot/export_templates/${TEMPLATE_VERSION}
     #   Linux: ~/.local/share/godot/export_templates/${TEMPLATE_VERSION}
EOF
	exit 1
fi

mkdir -p "${OUT_DIR}"

echo "==> Importando recursos do projeto..."
"${GODOT_BIN}" --headless --path "${CLIENT_DIR}" --import

echo "==> Exportando preset 'Web' para ${OUT_DIR}/index.html..."
"${GODOT_BIN}" --headless --path "${CLIENT_DIR}" --export-release "Web" "${OUT_FILE}"

if [[ ! -f "${OUT_DIR}/index.html" ]]; then
	echo "Erro: a exportação terminou sem gerar ${OUT_DIR}/index.html." >&2
	exit 1
fi

echo "==> Build Web concluída em: ${OUT_DIR}"

if [[ "${1:-}" == "--serve" ]]; then
	PORT="${2:-8000}"
	echo "==> Servindo ${OUT_DIR} em http://127.0.0.1:${PORT} (Ctrl+C para encerrar)..."
	exec python3 -m http.server "${PORT}" --bind 127.0.0.1 --directory "${OUT_DIR}"
fi
