#!/bin/bash
# setup-workspace.sh — Multi-monitor workspace manager para macOS
# Uso:
#   setup-workspace                  Menu interativo (carregar ou gravar)
#   setup-workspace <perfil>         Executa um perfil
#   setup-workspace --save <nome>    Grava o layout atual como perfil
#   setup-workspace --detect         Mostra monitores conectados
#   setup-workspace --init           Cria config editável
#
# Config: ~/.config/workspace-profiles.conf
#
# Formato do config:
#   # Mapeamento de monitores (rode --detect pra ver os disponíveis)
#   monitor.1=Nome do Display
#   monitor.2=Nome do Display
#
#   # Perfis: perfil|App Name|monitor|posição
#   # Posições nomeadas: left, right, full, top, bottom,
#   #   top-left, top-right, bottom-left, bottom-right
#   # Posições customizadas: x%,y%,w%,h%  (porcentagem da área visível)

set -eo pipefail

GREEN='\033[1;32m'
CYAN='\033[1;36m'
DIM='\033[0;90m'
BOLD='\033[1m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

CONFIG_FILE="${WORKSPACE_CONFIG:-$HOME/.config/workspace-profiles.conf}"

TMPWORK=$(mktemp -d)
trap 'rm -rf "$TMPWORK"' EXIT

# Processos de sistema a ignorar na captura
SKIP_PROCS="Dock|SystemUIServer|Spotlight|Control Center|Notification Center|WindowManager|AirPlayUIAgent|TextInputMenuAgent|Siri|loginwindow|universalAccessAuthWarn|Finder_Status|ScreenSaverEngine|UserNotificationCenter|CoreServicesUIAgent"

# ═══════════════════════════════════════════
# Detecção de monitores via JXA + NSScreen
# ═══════════════════════════════════════════

detect_displays() {
    osascript -l JavaScript -e '
ObjC.import("AppKit");
var screens = $.NSScreen.screens;
var mainH = screens.objectAtIndex(0).frame.size.height;
var lines = [];
for (var i = 0; i < screens.count; i++) {
    var s = screens.objectAtIndex(i);
    var f = s.frame;
    var vf = s.visibleFrame;
    lines.push(
        s.localizedName.js + "|" +
        Math.round(f.origin.x) + "|" +
        Math.round(mainH - f.origin.y - f.size.height) + "|" +
        Math.round(f.size.width) + "|" +
        Math.round(f.size.height) + "|" +
        Math.round(vf.origin.x) + "|" +
        Math.round(mainH - vf.origin.y - vf.size.height) + "|" +
        Math.round(vf.size.width) + "|" +
        Math.round(vf.size.height)
    );
}
lines.join("\n");
' > "$TMPWORK/displays.txt" 2>/dev/null
}

show_displays() {
    detect_displays

    if [ ! -s "$TMPWORK/displays.txt" ]; then
        echo -e "  ${RED}Nenhum display detectado.${RESET}"
        return 1
    fi

    echo ""
    echo -e "  ${BOLD}Monitores conectados:${RESET}"
    echo ""
    printf "  %-4s %-22s %-14s %-12s %s\n" "#" "Nome" "Resolução" "Orientação" "Origem"
    printf "  %-4s %-22s %-14s %-12s %s\n" "──" "────────────────────" "────────────" "──────────" "──────────"

    local idx=0
    while IFS='|' read -r name fx fy fw fh vx vy vw vh; do
        idx=$((idx + 1))
        local orient="paisagem"
        if [ "$fh" -gt "$fw" ]; then
            orient="retrato"
        fi
        printf "  %-4s %-22s %dx%-10d %-12s (%d, %d)\n" "$idx" "$name" "$fw" "$fh" "$orient" "$fx" "$fy"
    done < "$TMPWORK/displays.txt"

    echo ""
    echo -e "  ${BOLD}Para usar no config, adicione o mapeamento:${RESET}"
    echo ""

    idx=0
    while IFS='|' read -r name _ _ _ _ _ _ _ _; do
        idx=$((idx + 1))
        echo -e "  ${CYAN}monitor.${idx}=${name}${RESET}"
    done < "$TMPWORK/displays.txt"

    echo ""
    echo -e "  ${DIM}Salve em: $CONFIG_FILE${RESET}"
    echo ""
}

# ═══════════════════════════════════════════
# Resolução de display
# ═══════════════════════════════════════════

resolve_display() {
    local monitor_num="$1"
    local display_name=""

    if [ -f "$CONFIG_FILE" ]; then
        display_name=$(grep "^monitor\.${monitor_num}=" "$CONFIG_FILE" 2>/dev/null | head -1 | sed 's/^monitor\.[0-9]*=//')
    fi

    local line=""

    if [ -n "$display_name" ]; then
        line=$(grep -i "$display_name" "$TMPWORK/displays.txt" 2>/dev/null | head -1)
    fi

    if [ -z "$line" ]; then
        line=$(sed -n "${monitor_num}p" "$TMPWORK/displays.txt" 2>/dev/null)
    fi

    if [ -z "$line" ]; then
        line=$(head -1 "$TMPWORK/displays.txt")
    fi

    echo "$line"
}

get_display_bounds() {
    resolve_display "$1" | awk -F'|' '{print $6, $7, $8, $9}'
}

get_display_name() {
    resolve_display "$1" | awk -F'|' '{print $1}'
}

# Reverso: nome do display → número no config
display_name_to_config_num() {
    local target_name="$1"

    # Tentar mapear pelo config
    if [ -f "$CONFIG_FILE" ]; then
        while IFS= read -r line; do
            case "$line" in
                monitor.*=*)
                    local num="${line#monitor.}"
                    num="${num%%=*}"
                    local pattern="${line#*=}"
                    if echo "$target_name" | grep -qi "$pattern" 2>/dev/null; then
                        echo "$num"
                        return
                    fi
                    ;;
            esac
        done < "$CONFIG_FILE"
    fi

    # Fallback: índice no displays.txt
    local idx=0
    while IFS='|' read -r name _rest; do
        idx=$((idx + 1))
        if [ "$name" = "$target_name" ]; then
            echo "$idx"
            return
        fi
    done < "$TMPWORK/displays.txt"
    echo "1"
}

# ═══════════════════════════════════════════
# Cálculo de posição
# ═══════════════════════════════════════════

calculate_bounds() {
    local position="$1"
    local vx="$2" vy="$3" vw="$4" vh="$5"

    if echo "$position" | grep -qE '^[0-9]+,[0-9]+,[0-9]+,[0-9]+$'; then
        local px py pw ph
        px=$(echo "$position" | cut -d, -f1)
        py=$(echo "$position" | cut -d, -f2)
        pw=$(echo "$position" | cut -d, -f3)
        ph=$(echo "$position" | cut -d, -f4)
        awk "BEGIN {
            printf \"%d %d %d %d\",
                $vx + $vw * $px / 100,
                $vy + $vh * $py / 100,
                $vw * $pw / 100,
                $vh * $ph / 100
        }"
        return
    fi

    local half_w=$((vw / 2))
    local half_h=$((vh / 2))

    case "$position" in
        left)         echo "$vx $vy $half_w $vh" ;;
        right)        echo "$((vx + half_w)) $vy $half_w $vh" ;;
        full)         echo "$vx $vy $vw $vh" ;;
        top)          echo "$vx $vy $vw $half_h" ;;
        bottom)       echo "$vx $((vy + half_h)) $vw $half_h" ;;
        top-left)     echo "$vx $vy $half_w $half_h" ;;
        top-right)    echo "$((vx + half_w)) $vy $half_w $half_h" ;;
        bottom-left)  echo "$vx $((vy + half_h)) $half_w $half_h" ;;
        bottom-right) echo "$((vx + half_w)) $((vy + half_h)) $half_w $half_h" ;;
        *)            echo "$vx $vy $vw $vh" ;;
    esac
}

# Detecta posição nomeada a partir de porcentagens, ou retorna custom
detect_position_name() {
    awk -v px="$1" -v py="$2" -v pw="$3" -v ph="$4" '
    function abs(x) { return x < 0 ? -x : x }
    BEGIN {
        t = 5
        if (abs(px)<=t && abs(py)<=t && abs(pw-100)<=t && abs(ph-100)<=t) { print "full"; exit }
        if (abs(px)<=t && abs(py)<=t && abs(pw-50)<=t  && abs(ph-100)<=t) { print "left"; exit }
        if (abs(px-50)<=t && abs(py)<=t && abs(pw-50)<=t && abs(ph-100)<=t) { print "right"; exit }
        if (abs(px)<=t && abs(py)<=t && abs(pw-100)<=t && abs(ph-50)<=t) { print "top"; exit }
        if (abs(px)<=t && abs(py-50)<=t && abs(pw-100)<=t && abs(ph-50)<=t) { print "bottom"; exit }
        if (abs(px)<=t && abs(py)<=t && abs(pw-50)<=t && abs(ph-50)<=t) { print "top-left"; exit }
        if (abs(px-50)<=t && abs(py)<=t && abs(pw-50)<=t && abs(ph-50)<=t) { print "top-right"; exit }
        if (abs(px)<=t && abs(py-50)<=t && abs(pw-50)<=t && abs(ph-50)<=t) { print "bottom-left"; exit }
        if (abs(px-50)<=t && abs(py-50)<=t && abs(pw-50)<=t && abs(ph-50)<=t) { print "bottom-right"; exit }
        printf "%d,%d,%d,%d", px, py, pw, ph
    }'
}

# ═══════════════════════════════════════════
# Gestão de apps e janelas
# ═══════════════════════════════════════════

open_app() {
    local app="$1"
    if ! pgrep -xq "$app" 2>/dev/null; then
        open -a "$app" 2>/dev/null || {
            echo -e "  ${DIM}✗ $app não encontrado${RESET}"
            return 1
        }
        local waited=0
        while ! pgrep -xq "$app" 2>/dev/null && [ $waited -lt 10 ]; do
            sleep 0.5
            waited=$((waited + 1))
        done
    fi
    local pid
    pid=$(pgrep -x "$app" 2>/dev/null | head -1 || echo "?")
    echo -e "  ${GREEN}✓${RESET} $app  ${DIM}(pid $pid)${RESET}"
    return 0
}

get_window_count() {
    local app="$1"
    osascript -e "
tell application \"System Events\"
    tell process \"$app\"
        return count of windows
    end tell
end tell
" 2>/dev/null || echo "0"
}

create_window() {
    local app="$1"
    case "$app" in
        Finder)
            osascript -e 'tell application "Finder" to make new Finder window' 2>/dev/null ;;
        "Google Chrome")
            osascript -e 'tell application "Google Chrome" to make new window' 2>/dev/null ;;
        Safari)
            osascript -e 'tell application "Safari" to make new document' 2>/dev/null ;;
        *)
            osascript -e "
tell application \"System Events\"
    tell process \"$app\"
        try
            click menu item \"New Window\" of menu \"File\" of menu bar 1
        on error
            try
                click menu item \"New Window\" of menu \"Shell\" of menu bar 1
            end try
        end try
    end tell
end tell
" 2>/dev/null ;;
    esac
    sleep 0.3
}

position_window() {
    local app="$1"
    local win_idx="$2"
    local x="$3" y="$4" w="$5" h="$6"

    osascript -e "
tell application \"$app\" to activate
delay 0.15
tell application \"System Events\"
    tell process \"$app\"
        try
            set position of window $win_idx to {${x}, ${y}}
            set size of window $win_idx to {${w}, ${h}}
        end try
    end tell
end tell
" 2>/dev/null
}

# ═══════════════════════════════════════════
# Captura de layout
# ═══════════════════════════════════════════

# Captura todas as janelas visíveis via System Events
capture_windows() {
    osascript -l JavaScript -e '
var se = Application("System Events");
var procs = se.processes.whose({visible: true});
var results = [];
for (var i = 0; i < procs.length; i++) {
    try {
        var proc = procs[i];
        var name = proc.name();
        var wins = proc.windows();
        for (var j = 0; j < wins.length; j++) {
            try {
                var pos = wins[j].position();
                var sz = wins[j].size();
                if (sz[0] > 80 && sz[1] > 80) {
                    results.push(name + "|" + Math.round(pos[0]) + "|" + Math.round(pos[1]) + "|" + Math.round(sz[0]) + "|" + Math.round(sz[1]));
                }
            } catch(e) {}
        }
    } catch(e) {}
}
results.join("\n");
' > "$TMPWORK/all_windows.txt" 2>/dev/null

    # Filtrar processos de sistema
    grep -v -E "^($SKIP_PROCS)\|" "$TMPWORK/all_windows.txt" > "$TMPWORK/windows.txt" 2>/dev/null || true
}

# Determina em qual display está uma janela (pelo canto top-left)
find_display_for_point() {
    local wx="$1" wy="$2"

    local best_idx=1
    local best_name=""
    local best_dist=999999999

    local idx=0
    while IFS='|' read -r name fx fy fw fh vx vy vw vh; do
        idx=$((idx + 1))
        # Checar se o ponto está dentro do frame do display
        if [ "$wx" -ge "$fx" ] && [ "$wx" -lt "$((fx + fw))" ] && \
           [ "$wy" -ge "$fy" ] && [ "$wy" -lt "$((fy + fh))" ]; then
            echo "$idx|$name|$vx|$vy|$vw|$vh"
            return
        fi
        # Calcular distância pro centro do display (fallback)
        local cx=$((fx + fw / 2))
        local cy=$((fy + fh / 2))
        local dx=$((wx - cx))
        local dy=$((wy - cy))
        # Distância manhattan (evita overflow de multiplicação)
        local dist=$((dx > 0 ? dx : -dx))
        dist=$((dist + (dy > 0 ? dy : -dy)))
        if [ "$dist" -lt "$best_dist" ]; then
            best_dist=$dist
            best_idx=$idx
            best_name="$name"
        fi
    done < "$TMPWORK/displays.txt"

    # Fallback: display mais próximo
    local vline
    vline=$(sed -n "${best_idx}p" "$TMPWORK/displays.txt")
    local vx vy vw vh
    vx=$(echo "$vline" | awk -F'|' '{print $6}')
    vy=$(echo "$vline" | awk -F'|' '{print $7}')
    vw=$(echo "$vline" | awk -F'|' '{print $8}')
    vh=$(echo "$vline" | awk -F'|' '{print $9}')
    echo "$best_idx|$best_name|$vx|$vy|$vw|$vh"
}

# Orquestra captura e salva perfil
save_profile() {
    local profile_name="$1"

    echo ""
    echo -e "  ${DIM}Detectando monitores...${RESET}"
    detect_displays

    if [ ! -s "$TMPWORK/displays.txt" ]; then
        echo -e "  ${RED}Falha ao detectar monitores.${RESET}"
        return 1
    fi

    echo -e "  ${DIM}Capturando janelas...${RESET}"
    capture_windows

    if [ ! -s "$TMPWORK/windows.txt" ]; then
        echo -e "  ${RED}Nenhuma janela encontrada.${RESET}"
        return 1
    fi

    # Gerar linhas do perfil
    > "$TMPWORK/profile_lines.txt"

    echo ""
    echo -e "  ${BOLD}Layout capturado:${RESET}"
    echo ""

    while IFS='|' read -r app wx wy ww wh; do
        [ -z "$app" ] && continue

        # Encontrar display
        local display_info
        display_info=$(find_display_for_point "$wx" "$wy")
        local didx dname dvx dvy dvw dvh
        IFS='|' read -r didx dname dvx dvy dvw dvh <<< "$display_info"

        # Calcular porcentagens relativas ao display
        local px py pw ph
        px=$(awk "BEGIN {printf \"%d\", ($wx - $dvx) * 100 / $dvw}")
        py=$(awk "BEGIN {printf \"%d\", ($wy - $dvy) * 100 / $dvh}")
        pw=$(awk "BEGIN {printf \"%d\", $ww * 100 / $dvw}")
        ph=$(awk "BEGIN {printf \"%d\", $wh * 100 / $dvh}")

        # Detectar posição nomeada
        local position
        position=$(detect_position_name "$px" "$py" "$pw" "$ph")

        # Número do monitor no config
        local config_num
        config_num=$(display_name_to_config_num "$dname")

        echo "$profile_name|$app|$config_num|$position" >> "$TMPWORK/profile_lines.txt"

        printf "  ${GREEN}✓${RESET} %-20s → ${BOLD}%-20s${RESET}  ${CYAN}%s${RESET}\n" "$app" "$dname" "$position"
    done < "$TMPWORK/windows.txt"

    local total
    total=$(wc -l < "$TMPWORK/profile_lines.txt" | tr -d ' ')
    echo ""
    echo -e "  ${BOLD}$total janelas${RESET} em ${BOLD}$(awk -F'|' '{print $3}' "$TMPWORK/profile_lines.txt" | sort -u | wc -l | tr -d ' ')${RESET} monitores"

    # Confirmar
    echo ""
    if [ -t 0 ] || [ -e /dev/tty ]; then
        printf "  Salvar perfil ${CYAN}\"$profile_name\"${RESET}? [S/n]: "
        local confirm
        read -r confirm < /dev/tty 2>/dev/null || confirm="s"
        case "$confirm" in
            [nN]*) echo -e "  ${DIM}Cancelado.${RESET}"; echo ""; return 0 ;;
        esac
    fi

    # Garantir que o config existe com mapeamento de monitores
    mkdir -p "$(dirname "$CONFIG_FILE")"
    if [ ! -f "$CONFIG_FILE" ]; then
        # Criar config com mapeamento
        echo "# workspace-profiles.conf" > "$CONFIG_FILE"
        echo "# Formato: perfil|App Name|monitor|posição" >> "$CONFIG_FILE"
        echo "" >> "$CONFIG_FILE"
        echo "# ── Mapeamento de monitores ──" >> "$CONFIG_FILE"
        local idx=0
        while IFS='|' read -r name _ _ _ _ _ _ _ _; do
            idx=$((idx + 1))
            echo "monitor.${idx}=${name}" >> "$CONFIG_FILE"
        done < "$TMPWORK/displays.txt"
        echo "" >> "$CONFIG_FILE"
    fi

    # Remover perfil antigo se existir
    if grep -q "^$profile_name|" "$CONFIG_FILE" 2>/dev/null; then
        # Remover linhas do perfil antigo
        local tmp_conf
        tmp_conf=$(mktemp)
        grep -v "^$profile_name|" "$CONFIG_FILE" > "$tmp_conf"
        mv "$tmp_conf" "$CONFIG_FILE"
    fi

    # Adicionar novo perfil
    echo "" >> "$CONFIG_FILE"
    echo "# ── $profile_name (gravado em $(date '+%Y-%m-%d %H:%M')) ──" >> "$CONFIG_FILE"
    cat "$TMPWORK/profile_lines.txt" >> "$CONFIG_FILE"

    echo ""
    echo -e "  ${GREEN}✓ Perfil \"$profile_name\" salvo em $CONFIG_FILE${RESET}"
    echo -e "  ${DIM}Para restaurar: setup-workspace $profile_name${RESET}"
    echo ""
}

# ═══════════════════════════════════════════
# Config e perfis
# ═══════════════════════════════════════════

get_profile_lines() {
    if [ -f "$CONFIG_FILE" ]; then
        grep -v '^#' "$CONFIG_FILE" | grep -v '^$' | grep -v '^monitor\.' | grep '|' || true
    fi
}

list_profiles_inline() {
    local profiles
    profiles=$(get_profile_lines)
    if [ -z "$profiles" ]; then
        echo ""
        return
    fi
    echo "$profiles" | awk -F'|' '{print $1}' | sort -u | paste -sd', ' -
}

list_profiles() {
    local profiles
    profiles=$(get_profile_lines)

    if [ -z "$profiles" ]; then
        return 1
    fi

    local profile_names
    profile_names=$(echo "$profiles" | awk -F'|' '{print $1}' | sort -u)

    while read -r pname; do
        [ -z "$pname" ] && continue
        apps=$(echo "$profiles" | awk -F'|' -v p="$pname" '$1 == p {print $2}' | sort -u | paste -sd', ' -)
        printf "     ${CYAN}%-12s${RESET} %s\n" "$pname" "$apps"
    done <<< "$profile_names"
    return 0
}

# ═══════════════════════════════════════════
# Execução do perfil
# ═══════════════════════════════════════════

run_profile() {
    local target_profile="$1"
    local all_lines
    all_lines=$(get_profile_lines)

    local profile_lines
    profile_lines=$(echo "$all_lines" | awk -F'|' -v p="$target_profile" '$1 == p')

    if [ -z "$profile_lines" ]; then
        echo ""
        echo -e "  Perfil '${RED}$target_profile${RESET}' não encontrado."
        echo ""
        list_profiles
        exit 1
    fi

    echo ""
    echo -e "  Carregando perfil: ${CYAN}$target_profile${RESET}"

    echo -e "  ${DIM}Detectando monitores...${RESET}"
    detect_displays

    if [ ! -s "$TMPWORK/displays.txt" ]; then
        echo -e "  ${RED}Falha ao detectar monitores.${RESET}"
        exit 1
    fi

    local display_count
    display_count=$(wc -l < "$TMPWORK/displays.txt" | tr -d ' ')
    echo -e "  ${DIM}$display_count monitores detectados${RESET}"

    echo ""
    echo "  Abrindo apps..."

    local unique_apps
    unique_apps=$(echo "$profile_lines" | awk -F'|' '{print $2}' | sort -u)

    while read -r app; do
        [ -z "$app" ] && continue
        open_app "$app" || true
    done <<< "$unique_apps"

    sleep 1

    echo ""
    echo "  Preparando janelas..."

    while read -r app; do
        [ -z "$app" ] && continue
        local needed
        needed=$(echo "$profile_lines" | awk -F'|' -v a="$app" '$2 == a' | wc -l | tr -d ' ')
        local current
        current=$(get_window_count "$app")

        if [ "$current" -lt "$needed" ]; then
            local to_create=$((needed - current))
            echo -e "  ${DIM}Criando $to_create janela(s) extra de $app${RESET}"
            local i=0
            while [ $i -lt "$to_create" ]; do
                create_window "$app"
                i=$((i + 1))
            done
        fi
    done <<< "$unique_apps"

    sleep 0.5

    echo ""
    echo "  Posicionando janelas..."

    while read -r app; do
        [ -z "$app" ] && continue

        local app_entries
        app_entries=$(echo "$profile_lines" | awk -F'|' -v a="$app" '$2 == a')

        local win_idx=1
        while IFS='|' read -r _ _ monitor position; do
            local bounds
            bounds=$(get_display_bounds "$monitor")
            local vx vy vw vh
            read -r vx vy vw vh <<< "$bounds"

            local wx wy ww wh
            read -r wx wy ww wh <<< "$(calculate_bounds "$position" "$vx" "$vy" "$vw" "$vh")"

            position_window "$app" "$win_idx" "$wx" "$wy" "$ww" "$wh"

            local display_name
            display_name=$(get_display_name "$monitor")

            echo -e "  ${GREEN}✓${RESET} $app [${win_idx}] → ${BOLD}$display_name${RESET}  ${DIM}$position (${wx},${wy} ${ww}x${wh})${RESET}"

            win_idx=$((win_idx + 1))
        done <<< "$app_entries"

    done <<< "$unique_apps"

    echo ""
    echo -e "  ${GREEN}✓ Workspace \"$target_profile\" pronto.${RESET}"
    echo ""
}

# ═══════════════════════════════════════════
# Gerar config
# ═══════════════════════════════════════════

generate_config() {
    mkdir -p "$(dirname "$CONFIG_FILE")"

    detect_displays

    local mapping=""
    if [ -s "$TMPWORK/displays.txt" ]; then
        local idx=0
        while IFS='|' read -r name _ _ _ _ _ _ _ _; do
            idx=$((idx + 1))
            mapping="${mapping}monitor.${idx}=${name}
"
        done < "$TMPWORK/displays.txt"
    fi

    cat > "$CONFIG_FILE" <<CONF
# workspace-profiles.conf
# Formato: perfil|App Name|monitor|posição
#
# Posições nomeadas:
#   left, right, full, top, bottom
#   top-left, top-right, bottom-left, bottom-right
#
# Posições customizadas (porcentagem da área visível):
#   x%,y%,largura%,altura%
#   Exemplo: 0,0,100,45 = topo com 45% da altura

# ── Mapeamento de monitores ──
# (rode setup-workspace --detect pra atualizar)
${mapping}
CONF

    echo ""
    echo -e "  ${GREEN}✓${RESET} Config criada em ${BOLD}$CONFIG_FILE${RESET}"

    if [ -s "$TMPWORK/displays.txt" ]; then
        echo ""
        echo -e "  Monitores detectados e mapeados:"
        local idx=0
        while IFS='|' read -r name _ _ fw fh _ _ _ _; do
            idx=$((idx + 1))
            echo -e "    ${CYAN}monitor.$idx${RESET} = $name (${fw}x${fh})"
        done < "$TMPWORK/displays.txt"
    fi

    echo ""
    echo -e "  ${DIM}Rode ${BOLD}setup-workspace${RESET}${DIM} pra gravar seu primeiro perfil.${RESET}"
    echo ""
}

# ═══════════════════════════════════════════
# Menu interativo
# ═══════════════════════════════════════════

interactive_menu() {
    echo ""

    local has_profiles=false
    local profile_list
    profile_list=$(list_profiles_inline)
    if [ -n "$profile_list" ]; then
        has_profiles=true
    fi

    echo -e "  ${BOLD}Setup Workspace${RESET}"
    echo ""

    if $has_profiles; then
        echo -e "  ${CYAN}1)${RESET} Carregar perfil"
        list_profiles
        echo ""
    fi

    echo -e "  ${CYAN}2)${RESET} Gravar layout atual como perfil"
    echo ""

    if $has_profiles; then
        printf "  Escolha [1/2]: "
    else
        echo -e "  ${DIM}Nenhum perfil salvo ainda.${RESET}"
        echo ""
        printf "  Pressione ENTER pra gravar o layout atual: "
    fi

    local choice
    read -r choice < /dev/tty

    case "$choice" in
        1)
            if ! $has_profiles; then
                echo -e "  ${RED}Nenhum perfil disponível.${RESET}"
                return 1
            fi
            echo ""
            printf "  Nome do perfil: "
            local profile
            read -r profile < /dev/tty
            if [ -z "$profile" ]; then
                echo -e "  ${DIM}Cancelado.${RESET}"
                return 0
            fi
            run_profile "$profile"
            ;;
        2|"")
            echo ""
            printf "  Nome pro novo perfil: "
            local name
            read -r name < /dev/tty
            if [ -z "$name" ]; then
                echo -e "  ${DIM}Cancelado.${RESET}"
                return 0
            fi
            # Sanitizar nome (lowercase, sem espaços)
            name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
            save_profile "$name"
            ;;
        *)
            # Tentar tratar como nome de perfil direto
            if $has_profiles && echo "$profile_list" | grep -qw "$choice"; then
                run_profile "$choice"
            else
                echo -e "  ${RED}Opção inválida.${RESET}"
                return 1
            fi
            ;;
    esac
}

# ═══════════════════════════════════════════
# Main
# ═══════════════════════════════════════════

case "${1:-}" in
    "")
        interactive_menu
        ;;
    --detect)
        show_displays
        ;;
    --save)
        if [ -z "${2:-}" ]; then
            echo "Uso: setup-workspace --save <nome-do-perfil>"
            exit 1
        fi
        save_profile "$2"
        ;;
    --init)
        generate_config
        ;;
    --help|-h)
        echo ""
        echo "  Uso: setup-workspace [comando]"
        echo ""
        echo "  Comandos:"
        echo "    (sem args)          Menu interativo (carregar ou gravar)"
        echo "    <perfil>            Abre e posiciona apps do perfil"
        echo "    --save <nome>       Grava o layout atual como perfil"
        echo "    --detect            Mostra monitores conectados"
        echo "    --init              Cria arquivo de configuração"
        echo "    --help              Mostra esta ajuda"
        echo ""
        echo "  Config: $CONFIG_FILE"
        echo ""
        ;;
    *)
        run_profile "$1"
        ;;
esac
