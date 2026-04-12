#!/bin/bash
# cacar-duplicatas.sh — Encontra arquivos duplicados por hash SHA-256
# Uso: ./cacar-duplicatas.sh [pasta] [tamanho-minimo-bytes]
# Padrão: ~/  com mínimo de 1 KB
# Nenhum arquivo é deletado — apenas listados.

set -eo pipefail

YELLOW='\033[1;33m'
RED='\033[1;31m'
GREEN='\033[1;32m'
BOLD='\033[1m'
DIM='\033[0;90m'
RESET='\033[0m'

TARGET="${1:-.}"
TARGET="${TARGET%/}"
MIN_SIZE="${2:-1024}"

if [ ! -d "$TARGET" ]; then
    echo "Erro: '$TARGET' não é um diretório válido." >&2
    exit 1
fi

TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT

SIZE_FILE="$TMPDIR_WORK/sizes"
HASH_FILE="$TMPDIR_WORK/hashes"

human_size() {
    local bytes=$1
    if [ "$bytes" -ge 1073741824 ]; then
        echo "$(echo "scale=1; $bytes / 1073741824" | bc) GB"
    elif [ "$bytes" -ge 1048576 ]; then
        echo "$(echo "scale=1; $bytes / 1048576" | bc) MB"
    elif [ "$bytes" -ge 1024 ]; then
        echo "$((bytes / 1024)) KB"
    else
        echo "${bytes} B"
    fi
}

echo ""
echo -e "  Escaneando ${BOLD}$TARGET${RESET}..."
echo -e "  ${DIM}(ignorando arquivos < $(human_size "$MIN_SIZE"))${RESET}"
echo ""

# Passo 1: Listar arquivos com tamanho
echo -ne "  Listando arquivos...\r"
find "$TARGET" -type f -size +"${MIN_SIZE}c" \
    -not -path '*/\.*' \
    -not -path '*/node_modules/*' \
    -not -path '*/.venv/*' \
    -not -path '*/venv/*' \
    -not -path '*/__pycache__/*' \
    -not -path '*/.git/*' \
    2>/dev/null | while IFS= read -r f; do
    size=$(stat -f '%z' "$f" 2>/dev/null || echo 0)
    echo "$size|$f"
done > "$SIZE_FILE"

total_files=$(wc -l < "$SIZE_FILE" | tr -d ' ')
echo -e "  ${BOLD}$total_files${RESET} arquivos encontrados"
echo ""

# Passo 2: Encontrar tamanhos duplicados (pré-filtro)
echo -ne "  Agrupando por tamanho...\r"
awk -F'|' '{print $1}' "$SIZE_FILE" | sort | uniq -d > "$TMPDIR_WORK/dup_sizes"

if [ ! -s "$TMPDIR_WORK/dup_sizes" ]; then
    echo -e "  ${GREEN}✓ Nenhuma duplicata encontrada.${RESET}"
    echo ""
    exit 0
fi

# Passo 3: Filtrar apenas candidatos
> "$TMPDIR_WORK/candidates"
while read -r dup_size; do
    grep "^${dup_size}|" "$SIZE_FILE" >> "$TMPDIR_WORK/candidates" || true
done < "$TMPDIR_WORK/dup_sizes"

candidates=$(wc -l < "$TMPDIR_WORK/candidates" | tr -d ' ')
echo -e "  ${BOLD}$candidates${RESET} candidatos a duplicata (mesmo tamanho)"

# Passo 4: Calcular hashes
hashed=0
> "$HASH_FILE"
while IFS='|' read -r size filepath; do
    hash=$(shasum -a 256 "$filepath" 2>/dev/null | awk '{print $1}')
    if [ -n "$hash" ]; then
        echo "$hash|$size|$filepath" >> "$HASH_FILE"
    fi
    hashed=$((hashed + 1))
    if [ $((hashed % 50)) -eq 0 ]; then
        echo -ne "\r  Calculando hashes... $hashed/$candidates"
    fi
done < "$TMPDIR_WORK/candidates"

echo -e "\r  Calculando hashes... ${GREEN}feito${RESET}          "
echo ""

# Passo 5: Encontrar hashes duplicados
awk -F'|' '{print $1}' "$HASH_FILE" | sort | uniq -d > "$TMPDIR_WORK/dup_hashes"

if [ ! -s "$TMPDIR_WORK/dup_hashes" ]; then
    echo -e "  ${GREEN}✓ Nenhuma duplicata encontrada.${RESET}"
    echo ""
    exit 0
fi

# Passo 6: Exibir resultados
echo -e "  ${BOLD}Duplicatas encontradas:${RESET}"
echo ""

group_num=0
total_dup_files=0
total_recoverable=0

while read -r dup_hash; do
    group_num=$((group_num + 1))

    # Coletar dados desse grupo
    group_lines=$(grep "^${dup_hash}|" "$HASH_FILE")
    copies=$(echo "$group_lines" | wc -l | tr -d ' ')
    first_size=$(echo "$group_lines" | head -1 | awk -F'|' '{print $2}')
    recoverable=$((first_size * (copies - 1)))
    total_recoverable=$((total_recoverable + recoverable))
    total_dup_files=$((total_dup_files + copies))

    echo -e "  ${YELLOW}Grupo $group_num${RESET} — $copies cópias — ${RED}$(human_size "$recoverable")${RESET} recuperáveis"
    echo -e "  ${DIM}SHA-256: ${dup_hash:0:16}...${RESET}"

    echo "$group_lines" | while IFS='|' read -r _ _ filepath; do
        display="${filepath/$HOME/\~}"
        echo "    $display"
    done
    echo ""
done < "$TMPDIR_WORK/dup_hashes"

# Resumo
echo "  ─────────────────────────────────"
echo -e "  ${BOLD}Resumo:${RESET}"
echo -e "  Grupos de duplicatas:  ${BOLD}$group_num${RESET}"
echo -e "  Arquivos duplicados:   ${BOLD}$total_dup_files${RESET}"
echo -e "  Espaço recuperável:    ${RED}${BOLD}$(human_size "$total_recoverable")${RESET}"
echo "  ─────────────────────────────────"
echo ""
echo -e "  ${DIM}Nenhum arquivo foi deletado. Revise a lista acima e delete manualmente.${RESET}"
echo ""
