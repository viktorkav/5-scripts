#!/bin/bash
# scanner-espaco.sh — Mostra os maiores arquivos e pastas do disco (Linux)
# Uso: ./scanner-espaco.sh [pasta] [quantidade]   (padrao: ~  20)

set -eo pipefail

YELLOW='\033[1;33m'
RED='\033[1;31m'
BOLD='\033[1m'
DIM='\033[0;90m'
RESET='\033[0m'

TARGET="${1:-.}"
TARGET="${TARGET%/}"
COUNT="${2:-20}"

if [ ! -d "$TARGET" ]; then
    echo "Erro: '$TARGET' nao e um diretorio valido." >&2
    exit 1
fi

colorize_size() {
    local size_str="$1"
    local kb="$2"
    if [ "$kb" -ge 5242880 ]; then
        printf "${RED}%s${RESET}" "$size_str"
    elif [ "$kb" -ge 1048576 ]; then
        printf "${YELLOW}%s${RESET}" "$size_str"
    else
        printf "%s" "$size_str"
    fi
}

human_size_kb() {
    local kb=$1
    if [ "$kb" -ge 1048576 ]; then
        echo "$(echo "scale=1; $kb / 1048576" | bc) GB"
    elif [ "$kb" -ge 1024 ]; then
        echo "$((kb / 1024)) MB"
    else
        echo "${kb} KB"
    fi
}

echo ""
echo -e "  Escaneando ${BOLD}$TARGET${RESET}..."
echo -e "  ${DIM}(isso pode levar alguns segundos)${RESET}"
echo ""

# -- Top pastas --
echo -e "  ${BOLD}$COUNT maiores pastas:${RESET}"
echo ""

TMPWORK=$(mktemp -d)
trap 'rm -rf "$TMPWORK"' EXIT

# du pode falhar se nao ha subdiretorios — capturar output sem pipefail
du -sk "$TARGET"/*/ 2>/dev/null | sort -rn | head -n "$COUNT" > "$TMPWORK/dirs.txt" || true

if [ -s "$TMPWORK/dirs.txt" ]; then
    while IFS= read -r line; do
        size_kb=$(echo "$line" | awk '{print $1}')
        path=$(echo "$line" | awk '{$1=""; print $0}' | sed 's/^ //')
        size_str=$(human_size_kb "$size_kb")
        colored=$(colorize_size "$size_str" "$size_kb")
        display_path=$(echo "$path" | sed "s|$HOME|~|" | sed 's|/$||')
        printf "  %8b  %s\n" "$colored" "$display_path"
    done < "$TMPWORK/dirs.txt"
else
    echo -e "  ${DIM}(nenhuma subpasta encontrada)${RESET}"
fi

echo ""

# -- Top arquivos --
echo -e "  ${BOLD}$COUNT maiores arquivos:${RESET}"
echo ""

# Linux: stat -c '%s %n' em vez de stat -f '%z %N'
find "$TARGET" -maxdepth 4 -type f -not -path '*/\.*' 2>/dev/null | \
    xargs stat -c '%s %n' 2>/dev/null | \
    sort -rn | \
    head -n "$COUNT" > "$TMPWORK/files.txt" || true

if [ -s "$TMPWORK/files.txt" ]; then
    while IFS= read -r line; do
        bytes=$(echo "$line" | awk '{print $1}')
        path=$(echo "$line" | awk '{$1=""; print $0}' | sed 's/^ //')
        size_kb=$((bytes / 1024))
        size_str=$(human_size_kb "$size_kb")
        colored=$(colorize_size "$size_str" "$size_kb")
        display_path=$(echo "$path" | sed "s|$HOME|~|")
        printf "  %8b  %s\n" "$colored" "$display_path"
    done < "$TMPWORK/files.txt"
else
    echo -e "  ${DIM}(nenhum arquivo encontrado)${RESET}"
fi

echo ""

# -- Resumo do disco --
if command -v df &>/dev/null; then
    disk_info=$(df -h "$TARGET" | tail -1)
    used=$(echo "$disk_info" | awk '{print $3}')
    total=$(echo "$disk_info" | awk '{print $2}')
    pct=$(echo "$disk_info" | awk '{print $5}')
    echo -e "  ${BOLD}Disco:${RESET} ${used} usados de ${total} (${pct})"
fi
echo ""
