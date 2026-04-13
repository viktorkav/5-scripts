#!/bin/bash
# scanner-wifi.sh — Escaneia redes Wi-Fi e sugere o melhor canal
# Uso: ./scanner-wifi.sh
# macOS: usa system_profiler + ipconfig
# Linux: usa nmcli

set -eo pipefail

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
BOLD='\033[1m'
DIM='\033[0;90m'
RESET='\033[0m'

TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT

PARSED_FILE="$TMPDIR_WORK/parsed.txt"
CHANNEL_COUNTS="$TMPDIR_WORK/channel_counts.txt"

# ── Detectar rede atual ──

get_current_ssid() {
    if [[ "$OSTYPE" == darwin* ]]; then
        ipconfig getsummary en0 2>/dev/null | awk -F' : ' '/^ *SSID/{print $2}'
    else
        nmcli -t -f active,ssid dev wifi 2>/dev/null | grep '^yes' | cut -d: -f2 || echo ""
    fi
}

get_current_channel() {
    if [[ "$OSTYPE" == darwin* ]]; then
        # scutil expõe o canal via AirPort state
        scutil <<< "show State:/Network/Interface/en0/AirPort" 2>/dev/null | awk '/CHANNEL/{print $3; exit}'
    else
        iwconfig 2>/dev/null | awk '/Channel/{gsub(/[^0-9]/,"",$2); print $2}'
    fi
}

# ── Scan de redes ──

scan_networks() {
    if [[ "$OSTYPE" == darwin* ]]; then
        echo -e "  ${DIM}(isso pode levar alguns segundos)${RESET}"
        local profiler_out
        profiler_out=$(system_profiler SPAirPortDataType 2>/dev/null)

        if [ -z "$profiler_out" ]; then
            echo "Erro: não foi possível escanear redes Wi-Fi." >&2
            exit 1
        fi

        # Formato do system_profiler:
        #   Current Network Information:
        #     NomeRede:
        #       Channel: 36 (5GHz, 80MHz)
        #   Other Local Wi-Fi Networks:
        #     NomeRede:
        #       Channel: 1 (2GHz, 20MHz)
        echo "$profiler_out" | awk '
            /Current Network Information:|Other Local Wi-Fi Networks:/ { capture=1; next }
            capture && /^[^ ]/ { capture=0 }
            capture && /^            [^ ].*:$/ {
                ssid=$0
                gsub(/^ +/, "", ssid)
                gsub(/ *:$/, "", ssid)
            }
            capture && /Channel:/ {
                ch=$0
                gsub(/.*Channel: */, "", ch)
                gsub(/ .*/, "", ch)
                if (ssid != "" && ch != "") {
                    print ch "|" ssid
                    ssid=""
                }
            }
        ' >> "$PARSED_FILE"
    elif command -v nmcli &>/dev/null; then
        nmcli -t -f SSID,CHAN dev wifi list 2>/dev/null | while IFS=: read -r ssid chan; do
            [ -n "$chan" ] && [ "$ssid" != "--" ] && echo "${chan}|${ssid}" >> "$PARSED_FILE"
        done
    else
        echo "Erro: nenhuma ferramenta de scan Wi-Fi encontrada." >&2
        exit 1
    fi
}

# ── Barra de sinal ──

signal_bar() {
    local count=$1
    local bar=""
    local i=0
    while [ $i -lt 8 ]; do
        if [ $i -lt "$count" ]; then
            bar="${bar}█"
        else
            bar="${bar}░"
        fi
        i=$((i + 1))
    done
    echo "$bar"
}

# ── Main ──

echo ""
echo -e "  Escaneando redes Wi-Fi..."
echo ""

current_ssid=$(get_current_ssid)
current_channel=$(get_current_channel)

> "$PARSED_FILE"
scan_networks

# Aviso sobre nomes ocultos no macOS
if [[ "$OSTYPE" == darwin* ]] && grep -q "<redacted>" "$PARSED_FILE" 2>/dev/null; then
    echo -e "  ${DIM}Nomes ocultos pelo macOS. Para ver os SSIDs, rode: sudo ./scanner-wifi.sh${RESET}"
    echo ""
fi

if [ ! -s "$PARSED_FILE" ]; then
    echo -e "  ${RED}Nenhuma rede encontrada.${RESET}"
    echo -e "  ${DIM}Verifique se o Wi-Fi está ligado.${RESET}"
    exit 1
fi

# ── Contar redes por canal ──

# Canais 2.4 GHz (1-14)
echo -e "  ${BOLD}Redes encontradas (2.4 GHz):${RESET}"
echo ""
printf "  %-6s %-6s %-10s %s\n" "Canal" "Redes" "Sinal" "Nomes"
printf "  %-6s %-6s %-10s %s\n" "─────" "─────" "────────" "──────────────────────────────"

best_24_ch=""
best_24_count=999

for ch in 1 2 3 4 5 6 7 8 9 10 11 12 13; do
    count=$(awk -F'|' -v c="$ch" '$1 == c' "$PARSED_FILE" | wc -l | tr -d ' ')
    names=$(awk -F'|' -v c="$ch" '$1 == c {print $2}' "$PARSED_FILE" | paste -sd', ' -)

    # Rastrear melhor canal não-sobreposto
    case $ch in
        1|6|11)
            if [ "$count" -lt "$best_24_count" ]; then
                best_24_count=$count
                best_24_ch=$ch
            fi
            ;;
    esac

    # Pular canais vazios que não são 1, 6 ou 11
    if [ "$count" -eq 0 ]; then
        case $ch in
            1|6|11) ;;
            *) continue ;;
        esac
    fi

    bar=$(signal_bar "$count")

    # Destacar rede do usuário
    if [ -n "$current_ssid" ] && echo "$names" | grep -q "$current_ssid"; then
        names=$(echo "$names" | sed "s/$current_ssid/$(printf "${GREEN}${current_ssid}${RESET}")/")
    fi

    if [ "$count" -ge 5 ]; then
        printf "  ${RED}%4d    %d    %s${RESET}  %b\n" "$ch" "$count" "$bar" "$names"
    elif [ "$count" -ge 3 ]; then
        printf "  ${YELLOW}%4d    %d    %s${RESET}  %b\n" "$ch" "$count" "$bar" "$names"
    elif [ "$count" -eq 0 ]; then
        printf "  %4d    %d    %s  ${DIM}(vazio)${RESET}\n" "$ch" "$count" "$bar"
    else
        printf "  %4d    %d    %s  %b\n" "$ch" "$count" "$bar" "$names"
    fi
done

echo ""

# ── 5 GHz ──

has_5ghz=false
best_5_ch=""
best_5_count=999

for ch in 36 40 44 48 52 56 60 64 149 153 157 161 165; do
    count=$(awk -F'|' -v c="$ch" '$1 == c' "$PARSED_FILE" | wc -l | tr -d ' ')
    if [ "$count" -gt 0 ]; then
        has_5ghz=true
    fi
done

if $has_5ghz; then
    echo -e "  ${BOLD}Redes encontradas (5 GHz):${RESET}"
    echo ""
    printf "  %-6s %-6s %-10s %s\n" "Canal" "Redes" "Sinal" "Nomes"
    printf "  %-6s %-6s %-10s %s\n" "─────" "─────" "────────" "──────────────────────────────"

    for ch in 36 40 44 48 52 56 60 64 149 153 157 161 165; do
        count=$(awk -F'|' -v c="$ch" '$1 == c' "$PARSED_FILE" | wc -l | tr -d ' ')
        names=$(awk -F'|' -v c="$ch" '$1 == c {print $2}' "$PARSED_FILE" | paste -sd', ' -)

        if [ "$count" -eq 0 ]; then
            if [ -z "$best_5_ch" ]; then
                best_5_ch=$ch
                best_5_count=0
            fi
            continue
        fi

        if [ "$count" -lt "$best_5_count" ]; then
            best_5_count=$count
            best_5_ch=$ch
        fi

        bar=$(signal_bar "$count")

        if [ -n "$current_ssid" ] && echo "$names" | grep -q "$current_ssid"; then
            names=$(echo "$names" | sed "s/$current_ssid/$(printf "${GREEN}${current_ssid}${RESET}")/")
        fi

        printf "  %4d    %d    %s  %b\n" "$ch" "$count" "$bar" "$names"
    done

    echo ""
fi

# ── Diagnóstico ──

echo "  ─────────────────────────────────"
echo -e "  ${BOLD}Diagnóstico:${RESET}"
echo ""

if [ -n "$current_ssid" ]; then
    echo -e "  Sua rede:        ${GREEN}$current_ssid${RESET}"
else
    echo -e "  Sua rede:        ${DIM}(não detectada)${RESET}"
fi

if [ -n "$current_channel" ]; then
    current_count=$(awk -F'|' -v c="$current_channel" '$1 == c' "$PARSED_FILE" | wc -l | tr -d ' ')
    if [ "$current_count" -ge 5 ]; then
        echo -e "  Canal atual:     ${RED}$current_channel — CONGESTIONADO ($current_count redes)${RESET}"
    elif [ "$current_count" -ge 3 ]; then
        echo -e "  Canal atual:     ${YELLOW}$current_channel — MODERADO ($current_count redes)${RESET}"
    else
        echo -e "  Canal atual:     ${GREEN}$current_channel — BOM ($current_count redes)${RESET}"
    fi
fi

echo ""
echo -e "  ${BOLD}Recomendação:${RESET}"

if [ -n "$best_24_ch" ]; then
    if [ "$best_24_count" -eq 0 ]; then
        echo -e "  Canal ideal 2.4: ${GREEN}$best_24_ch — LIVRE${RESET}"
    else
        echo -e "  Canal ideal 2.4: ${GREEN}$best_24_ch ($best_24_count redes — menos congestionado)${RESET}"
    fi
fi

if [ -n "$best_5_ch" ]; then
    if [ "$best_5_count" -eq 0 ]; then
        echo -e "  Canal ideal 5G:  ${GREEN}$best_5_ch — LIVRE${RESET}"
    else
        echo -e "  Canal ideal 5G:  ${GREEN}$best_5_ch ($best_5_count redes — menos congestionado)${RESET}"
    fi
fi

echo "  ─────────────────────────────────"
echo ""
echo -e "  ${DIM}Acesse o painel do roteador (geralmente 192.168.1.1)${RESET}"
echo -e "  ${DIM}e altere o canal nas configurações de Wi-Fi.${RESET}"
echo ""
