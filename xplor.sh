#!/usr/bin/env bash

LS_CMD=$(command -pv ls 2>/dev/null); LS_CMD=${LS_CMD:-/bin/ls}
DIRNAME_CMD=$(command -pv dirname 2>/dev/null); DIRNAME_CMD=${DIRNAME_CMD:-/usr/bin/dirname}
CLEAR_CMD=$(command -pv clear 2>/dev/null); CLEAR_CMD=${CLEAR_CMD:-/usr/bin/clear}
CP_CMD=$(command -pv cp 2>/dev/null); CP_CMD=${CP_CMD:-/bin/cp}
MV_CMD=$(command -pv mv 2>/dev/null); MV_CMD=${MV_CMD:-/bin/mv}
RM_CMD=$(command -pv rm 2>/dev/null); RM_CMD=${RM_CMD:-/bin/rm}

CURRENT_DIR="${1:-$PWD}"
SELECTED=0
FILTER=""

declare -A CURSOR_POS
declare -A FOLDER_CACHE

CLIP_MODE=""
CLIP_ITEM=""
CLIP_PATH=""

# ---------- Sorting ----------
bubblesort() {
    local arr=("$@") tmp n=${#arr[@]}
    for ((i=0;i<n;i++)); do
        for ((j=0;j<n-i-1;j++)); do
            if [[ "${arr[j]}" > "${arr[j+1]}" ]]; then
                tmp="${arr[j]}"; arr[j]="${arr[j+1]}"; arr[j+1]="$tmp"
            fi
        done
    done
    echo "${arr[@]}"
}

# ---------- Human size ----------
human_size() {
    local s=$1 u=("B" "K" "M" "G") i=0
    while (( s >= 1024 && i < 3 )); do
        s=$((s/1024)); ((i++))
    done
    echo "${s}${u[i]}"
}

# ---------- Folder item count ----------
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

# ---------- File metadata ----------
file_meta() {
    local line
    line=$("$LS_CMD" -ln "$1" 2>/dev/null)
    set -- $line
    PERM="$1"; SIZE_BYTES="$5"; MTIME="$6 $7 $8"
}

# ---------- Clipboard ----------
copy_item() {
    local ITEM="${ITEMS[$SELECTED]}"
    CLIP_MODE="copy"
    CLIP_ITEM="$ITEM"
    CLIP_PATH="$(cd "$CURRENT_DIR" && pwd)/$ITEM"
}

move_item() {
    local ITEM="${ITEMS[$SELECTED]}"
    CLIP_MODE="move"
    CLIP_ITEM="$ITEM"
    CLIP_PATH="$(cd "$CURRENT_DIR" && pwd)/$ITEM"
}

paste_item() {
    [[ -z "$CLIP_ITEM" || -z "$CLIP_PATH" || ! -e "$CLIP_PATH" ]] && return
    local DEST="$CURRENT_DIR/$CLIP_ITEM"

    if [[ "$CLIP_MODE" == "copy" ]]; then
        "$CP_CMD" -r "$CLIP_PATH" "$DEST"
    elif [[ "$CLIP_MODE" == "move" ]]; then
        "$MV_CMD" "$CLIP_PATH" "$DEST"
        CLIP_MODE=""; CLIP_ITEM=""; CLIP_PATH=""
    fi
    FOLDER_CACHE=()
}

delete_item() {
    local ITEM="${ITEMS[$SELECTED]}"
    "$CLEAR_CMD"
    read -rp "Delete '$ITEM'? (y/N): " CONFIRM
    [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && return
    "$RM_CMD" -rf "$CURRENT_DIR/$ITEM"
    SELECTED=0
    FOLDER_CACHE=()
}

# ---------- Draw UI ----------
draw_screen() {
    "$CLEAR_CMD"

    TERM_HEIGHT=${LINES:-20}
    VISIBLE_LINES=$((TERM_HEIGHT - 9))

    mapfile -t ALL_ITEMS < <("$LS_CMD" -A "$CURRENT_DIR")
    FOLDERS=(); FILES=()

    for ITEM in "${ALL_ITEMS[@]}"; do
        if [[ -n "$FILTER" ]]; then
            shopt -s nocasematch
            [[ "$ITEM" != *"$FILTER"* ]] && shopt -u nocasematch && continue
            shopt -u nocasematch
        fi

        [[ -d "$CURRENT_DIR/$ITEM" ]] && FOLDERS+=("$ITEM") || FILES+=("$ITEM")
    done

    FOLDERS=($(bubblesort "${FOLDERS[@]}"))
    FILES=($(bubblesort "${FILES[@]}"))
    ITEMS=("${FOLDERS[@]}" "${FILES[@]}")
    ITEM_COUNT=${#ITEMS[@]}

    if (( ITEM_COUNT == 0 )); then
        START=0; END=-1
    elif (( ITEM_COUNT <= VISIBLE_LINES )); then
        START=0; END=$((ITEM_COUNT-1))
    else
        START=$((SELECTED - VISIBLE_LINES / 2))
        ((START<0)) && START=0
        END=$((START + VISIBLE_LINES - 1))
        ((END>=ITEM_COUNT)) && END=$((ITEM_COUNT - 1))
    fi

    echo "📁  xplor.sh — File Explorer"
    echo "$CURRENT_DIR"
    [[ -n "$FILTER" ]] && echo "🔎 Filter: $FILTER"
    [[ -n "$CLIP_ITEM" ]] && echo "📋 Clipboard: [$CLIP_MODE] $CLIP_ITEM"
    echo "--------------------------------------------------------------------------------"
    printf " %-30s  %-8s  %-10s  %s\n" "Name" "Size" "Perms" "Modified"
    echo "--------------------------------------------------------------------------------"

    if (( ITEM_COUNT == 0 )); then
        echo " (no results — press Esc or Backspace to clear search)"
    else
        for ((i=START; i<=END; i++)); do
            ITEM="${ITEMS[$i]}"
            PATH="$CURRENT_DIR/$ITEM"
            file_meta "$PATH"

            if [[ -d "$PATH" ]]; then
                ICON="📁"; COLOR="\e[34m"; DISPLAY="$ITEM/"
                SIZE="$(folder_count "$PATH") items"
            elif [[ -x "$PATH" ]]; then
                ICON="🚀"; COLOR="\e[33m"; DISPLAY="$ITEM"
                SIZE=$(human_size "$SIZE_BYTES")
            else
                ICON="📄"; COLOR="\e[37m"; DISPLAY="$ITEM"
                SIZE=$(human_size "$SIZE_BYTES")
            fi

            if [[ $i -eq $SELECTED ]]; then
                printf "> ${COLOR}${ICON} %-30s  %-8s  %-10s  %s\e[0m\n" \
                    "$DISPLAY" "$SIZE" "$PERM" "$MTIME"
            else
                printf "  ${COLOR}${ICON} %-30s  %-8s  %-10s  %s\e[0m\n" \
                    "$DISPLAY" "$SIZE" "$PERM" "$MTIME"
            fi
        done
    fi

    echo "--------------------------------------------------------------------------------"
    echo "[↑/↓] Move  [Enter] Open  [Backspace] Up/Clear  [/] Search  [c] Copy  [m] Move  [p] Paste  [d] Delete  [q] Quit"
}

# ---------- Open ----------
open_item() {
    local TOTAL=${#ITEMS[@]}
    (( TOTAL == 0 )) && return

    local ITEM="${ITEMS[$SELECTED]}"
    local PATH="$CURRENT_DIR/$ITEM"

    if [[ -d "$PATH" ]]; then
        CURSOR_POS["$CURRENT_DIR"]=$SELECTED
        CURRENT_DIR="$PATH"
        SELECTED=${CURSOR_POS["$CURRENT_DIR"]:-0}
        FOLDER_CACHE=()
    elif [[ -f "$PATH" ]]; then
        "$CLEAR_CMD"; less "$PATH"
    fi
}

# ---------- Key handling ----------
key_input() {
    read -rsn1 key
    case "$key" in
        $'\x1b')
            read -rsn2 -t 0.01 key2
            case "$key2" in
                "[A") ((SELECTED--)) ;;
                "[B") ((SELECTED++)) ;;
                *) FILTER=""; SELECTED=0 ;;
            esac
            ;;
        "") open_item ;;
        $'\x7f')
            if (( ${#ITEMS[@]} == 0 )); then
                FILTER=""; SELECTED=0; return
            fi
            CURSOR_POS["$CURRENT_DIR"]=$SELECTED
            CURRENT_DIR=$("$DIRNAME_CMD" "$CURRENT_DIR")
            SELECTED=${CURSOR_POS["$CURRENT_DIR"]:-0}
            FOLDER_CACHE=()
            ;;
        /)
            "$CLEAR_CMD"
            read -rp "Search: " FILTER
            SELECTED=0
            ;;
        c) copy_item ;;
        m) move_item ;;
        p) paste_item ;;
        d) delete_item ;;
        q)
            "$CLEAR_CMD"
            echo "$CURRENT_DIR"
            exit 0
            ;;
    esac
}

# ---------- Main ----------
while true; do
    draw_screen
    ITEM_COUNT=${#ITEMS[@]}
    (( ITEM_COUNT > 0 && SELECTED < 0 )) && SELECTED=$((ITEM_COUNT - 1))
    (( ITEM_COUNT > 0 && SELECTED >= ITEM_COUNT )) && SELECTED=0
    key_input
done

