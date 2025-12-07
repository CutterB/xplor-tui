#!/usr/bin/env bash

# ===== Minimal-safe command detection =====
LS_CMD=$(command -pv ls 2>/dev/null); LS_CMD=${LS_CMD:-/bin/ls}
DIRNAME_CMD=$(command -pv dirname 2>/dev/null); DIRNAME_CMD=${DIRNAME_CMD:-/usr/bin/dirname}
CLEAR_CMD=$(command -pv clear 2>/dev/null); CLEAR_CMD=${CLEAR_CMD:-/usr/bin/clear}

# ===== State =====
CURRENT_DIR="${1:-$PWD}"
SELECTED=0
FILTER=""
declare -A CURSOR_POS
declare -A FOLDER_CACHE

# ===== Pure Bash alphabetical sort =====
bubblesort() {
    local arr=("$@") tmp
    local n=${#arr[@]}
    for ((i=0;i<n;i++)); do
        for ((j=0;j<n-i-1;j++)); do
            if [[ "${arr[j],,}" > "${arr[j+1],,}" ]]; then
                tmp="${arr[j]}"
                arr[j]="${arr[j+1]}"
                arr[j+1]="$tmp"
            fi
        done
    done
    echo "${arr[@]}"
}

# ===== Human-readable size =====
human_size() {
    local s=$1
    local u=("B" "K" "M" "G")
    local i=0
    while (( s >= 1024 && i < 3 )); do
        s=$((s/1024))
        ((i++))
    done
    echo "${s}${u[i]}"
}

# ===== Folder item counter (PURE Bash, cached, NO basename) =====
folder_count() {
    local dir="$1"
    [[ -n "${FOLDER_CACHE[$dir]}" ]] && echo "${FOLDER_CACHE[$dir]}" && return

    local count=0 f name
    for f in "$dir"/* "$dir"/.*; do
        name="${f##*/}"
        [[ "$name" == "." || "$name" == ".." ]] && continue
        [[ -e "$f" ]] && ((count++))
    done

    FOLDER_CACHE["$dir"]=$count
    echo "$count"
}

# ===== Permissions, Size, Modified Time via ls ONLY =====
file_meta() {
    local path="$1"
    local line size

    line=$("$LS_CMD" -ln "$path" 2>/dev/null)

    set -- $line
    PERM="$1"
    SIZE_BYTES="$5"
    MTIME="$6 $7 $8"
}

draw_screen() {
    "$CLEAR_CMD"

    TERM_HEIGHT=${LINES:-20}
    VISIBLE_LINES=$((TERM_HEIGHT-9))

    mapfile -t ALL_ITEMS < <("$LS_CMD" -A "$CURRENT_DIR")

    FOLDERS=()
    FILES=()

    for ITEM in "${ALL_ITEMS[@]}"; do
        [[ -n "$FILTER" && "${ITEM,,}" != *"${FILTER,,}"* ]] && continue
        [[ -d "$CURRENT_DIR/$ITEM" ]] && FOLDERS+=("$ITEM") || FILES+=("$ITEM")
    done

    FOLDERS=($(bubblesort "${FOLDERS[@]}"))
    FILES=($(bubblesort "${FILES[@]}"))
    ITEMS=("${FOLDERS[@]}" "${FILES[@]}")
    ITEM_COUNT=${#ITEMS[@]}

    if (( ITEM_COUNT <= VISIBLE_LINES )); then
        START=0; END=$((ITEM_COUNT-1))
    else
        START=$((SELECTED - VISIBLE_LINES / 2))
        ((START<0)) && START=0
        END=$((START + VISIBLE_LINES - 1))
        ((END>=ITEM_COUNT)) && END=$((ITEM_COUNT - 1))
        ((START=END-VISIBLE_LINES+1))
        ((START<0)) && START=0
    fi

    echo "📁  xplor.sh — File Explorer"
    echo "$CURRENT_DIR"
    [[ -n "$FILTER" ]] && echo "🔎 Filter: $FILTER"
    echo "--------------------------------------------------------------------------------"
    printf " %-30s  %-8s  %-10s  %s\n" "Name" "Size" "Perms" "Modified"
    echo "--------------------------------------------------------------------------------"

    for ((i=START; i<=END; i++)); do
        ITEM="${ITEMS[$i]}"
        PATH="$CURRENT_DIR/$ITEM"
        file_meta "$PATH"
        COLOR_EXT=""

        if [[ -d "$PATH" ]]; then
            ICON="📁"; COLOR="\e[34m"; DISPLAY="$ITEM/"
            COUNT=$(folder_count "$PATH")
            SIZE="$COUNT items"
        elif [[ -x "$PATH" ]]; then
            ICON="🚀"; COLOR="\e[33m"; DISPLAY="$ITEM"
            SIZE=$(human_size "$SIZE_BYTES")
        else
            ICON="📄"; COLOR="\e[37m"
            NAME="${ITEM%.*}"; EXT="${ITEM##*.}"
            if [[ "$EXT" != "$ITEM" ]]; then
                DISPLAY="$NAME.$EXT"
                COLOR_EXT="\e[36m"
            else
                DISPLAY="$ITEM"
            fi
            SIZE=$(human_size "$SIZE_BYTES")
        fi

        if [[ $i -eq $SELECTED ]]; then
            printf "> ${COLOR}${ICON} %-30s${COLOR_EXT}  %-8s  %-10s  %s\e[0m\n" "$DISPLAY" "$SIZE" "$PERM" "$MTIME"
        else
            printf "  ${COLOR}${ICON} %-30s${COLOR_EXT}  %-8s  %-10s  %s\e[0m\n" "$DISPLAY" "$SIZE" "$PERM" "$MTIME"
        fi
    done

    echo "--------------------------------------------------------------------------------"
    echo "[↑/↓] Move  [Enter] Open  [Backspace] Up  [/] Search  [q] Quit"
}

open_item() {
    local ITEM="${ITEMS[$SELECTED]}"
    local PATH="$CURRENT_DIR/$ITEM"

    if [[ -d "$PATH" ]]; then
        CURSOR_POS["$CURRENT_DIR"]=$SELECTED
        CURRENT_DIR="$PATH"
        SELECTED=${CURSOR_POS["$CURRENT_DIR"]:-0}
    elif [[ -f "$PATH" ]]; then
        "$CLEAR_CMD"
        echo "--- Viewing: $ITEM ---"
        echo
        less "$PATH"
    fi
}

key_input() {
    read -rsn1 key
    case "$key" in
        $'\x1b')
            read -rsn2 key2
            case "$key$key2" in
                $'\x1b[A') ((SELECTED--)) ;;
                $'\x1b[B') ((SELECTED++)) ;;
            esac
            ;;
        "") open_item ;;
        $'\x7f')
            CURSOR_POS["$CURRENT_DIR"]=$SELECTED
            CURRENT_DIR=$("$DIRNAME_CMD" "$CURRENT_DIR")
            SELECTED=${CURSOR_POS["$CURRENT_DIR"]:-0}
            ;;
        /)
            "$CLEAR_CMD"
            read -rp "Search: " FILTER
            SELECTED=0
            ;;
        q)
            "$CLEAR_CMD"
            echo "$CURRENT_DIR"
            exit 0
            ;;
    esac
}

while true; do
    draw_screen

    ITEM_COUNT=${#ITEMS[@]}

    ((SELECTED < 0)) && SELECTED=$((ITEM_COUNT - 1))
    ((SELECTED >= ITEM_COUNT)) && SELECTED=0

    key_input
done

