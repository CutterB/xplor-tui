#!/usr/bin/env bash

# ---------- Minimal command discovery ----------
LS_CMD=$(command -pv ls 2>/dev/null)
LS_CMD=${LS_CMD:-/bin/ls}
DIRNAME_CMD=$(command -pv dirname 2>/dev/null)
DIRNAME_CMD=${DIRNAME_CMD:-/usr/bin/dirname}
CLEAR_CMD=$(command -pv clear 2>/dev/null)
CP_CMD=$(command -pv cp 2>/dev/null)
CP_CMD=${CP_CMD:-/bin/cp}
MV_CMD=$(command -pv mv 2>/dev/null)
MV_CMD=${MV_CMD:-/bin/mv}
RM_CMD=$(command -pv rm 2>/dev/null)
RM_CMD=${RM_CMD:-/bin/rm}
SED_CMD=$(command -pv sed 2>/dev/null)
SED_CMD=${SED_CMD:-/bin/sed}
VI_CMD=$(command -pv vi 2>/dev/null)
VI_CMD=${VI_CMD:-vi}

# ---------- ANSI helpers (no tput) ----------
clr() { printf '\033[2J\033[H'; }
move() { printf '\033[%d;%dH' "$1" "$2"; }
rev_on() { printf '\033[7m'; }
dim_on() { printf '\033[2m'; }
dim_off() { printf '\033[22m'; }
reset() { printf '\033[0m'; }

# ---------- State: two panes ----------
PANE_ACTIVE=0 # 0=left, 1=right
PANE_DIR[0]="${1:-$PWD}"
PANE_DIR[1]="${2:-$PWD}"
PANE_SEL[0]=0
PANE_SEL[1]=0
PANE_FILTER[0]=""
PANE_FILTER[1]=""

# Clipboard (single item)
CLIP_MODE="" # copy|move
CLIP_NAME=""
CLIP_SRC=""

# ---------- Sorting (no sort) ----------
bubblesort() {
  local arr=("$@") tmp n=${#arr[@]}
  for ((i = 0; i < n; i++)); do
    for ((j = 0; j < n - i - 1; j++)); do
      if [[ "${arr[j]}" > "${arr[j + 1]}" ]]; then
        tmp="${arr[j]}"
        arr[j]="${arr[j + 1]}"
        arr[j + 1]="$tmp"
      fi
    done
  done
  echo "${arr[@]}"
}

# ---------- Build items for a pane (global ITEMS/ITEM_COUNT) ----------
build_items() {
  local dir="$1" filter="$2"
  local -a all folders files
  local item path

  ITEMS=()
  ITEM_COUNT=0

  mapfile -t all < <("$LS_CMD" -A "$dir" 2>/dev/null)

  for item in "${all[@]}"; do
    [[ -n "$filter" && "$item" != *"$filter"* ]] && continue
    path="$dir/$item"
    [[ -d "$path" ]] && folders+=("$item") || files+=("$item")
  done

  folders=($(bubblesort "${folders[@]}"))
  files=($(bubblesort "${files[@]}"))
  ITEMS=("${folders[@]}" "${files[@]}")
  ITEM_COUNT=${#ITEMS[@]}
}

# ---------- Truncate ----------
truncate() {
  local s="$1" w="$2"
  if ((${#s} <= w)); then
    printf "%s" "$s"
  else
    local cut=$((w - 1))
    ((cut < 0)) && cut=0
    printf "%s…" "${s:0:cut}"
  fi
}

# ---------- Text-editable detection (fixed case patterns) ----------
is_text_editable() {
  local name="$1"
  local ext="${name##*.}"

  case "$name" in
  Makefile | Dockerfile | README | LICENSE | COPYING | .gitignore | .gitattributes | .editorconfig) return 0 ;;
  esac

  [[ "$ext" == "$name" ]] && return 1

  case "$ext" in
  txt | md | rst | log | ini | conf | cfg | toml | yaml | yml | json | xml | csv | tsv | env | gitignore | editorconfig | diff | patch)
    return 0
    ;;
  sh | bash | zsh | ksh | fish | profile | bashrc | zshrc)
    return 0
    ;;
  py | rb | pl | php | js | ts | jsx | tsx | lua | go | rs | c | h | cpp | hpp | cc | java | kt | cs | swift)
    return 0
    ;;
  sql | html | css | scss | sass)
    return 0
    ;;
  service | timer | socket | mount | target | path)
    return 0
    ;;
  vim | vimrc | tmux)
    return 0
    ;;
  esac

  return 1
}

# ---------- Preview (sed only) ----------
preview_text() {
  local path="$1" max_lines="$2"
  "$SED_CMD" -n "1,${max_lines}p" "$path" 2>/dev/null || echo "(binary/unreadable)"
}

# ---------- Draw one pane ----------
draw_pane() {
  local pane="$1" x="$2" y="$3" w="$4" h="$5"

  local dir="${PANE_DIR[$pane]}"
  local sel="${PANE_SEL[$pane]}"
  local filter="${PANE_FILTER[$pane]}"

  build_items "$dir" "$filter"

  if ((ITEM_COUNT == 0)); then
    sel=0
  else
    ((sel < 0)) && sel=$((ITEM_COUNT - 1))
    ((sel >= ITEM_COUNT)) && sel=0
  fi
  PANE_SEL[$pane]="$sel"

  move "$y" "$x"
  if ((pane == PANE_ACTIVE)); then rev_on; fi
  printf " %-*s " $((w - 2)) "$(truncate "$dir" $((w - 2)))"
  reset

  move $((y + 1)) "$x"
  dim_on
  if [[ -n "$filter" ]]; then
    printf " %-*s " $((w - 2)) "$(truncate "Filter: $filter" $((w - 2)))"
  else
    printf " %-*s " $((w - 2)) "$(truncate "Filter: (none)" $((w - 2)))"
  fi
  dim_off

  local body_y=$((y + 2))
  local body_h=$((h - 2))
  local row

  for ((row = 0; row < body_h; row++)); do
    move $((body_y + row)) "$x"
    printf " %-*s " $((w - 2)) ""
  done

  if ((ITEM_COUNT == 0)); then
    move "$body_y" "$x"
    dim_on
    printf " %-*s " $((w - 2)) "$(truncate "(empty)" $((w - 2)))"
    dim_off
    return
  fi

  local i start end item icon line
  if ((ITEM_COUNT <= body_h)); then
    start=0
    end=$((ITEM_COUNT - 1))
  else
    start=$((sel - body_h / 2))
    ((start < 0)) && start=0
    end=$((start + body_h - 1))
    ((end >= ITEM_COUNT)) && end=$((ITEM_COUNT - 1))
    start=$((end - body_h + 1))
    ((start < 0)) && start=0
  fi

  row=0
  for ((i = start; i <= end; i++)); do
    item="${ITEMS[$i]}"
    [[ -d "$dir/$item" ]] && icon="📁" || icon="📄"
    line="$icon $item"
    move $((body_y + row)) "$x"
    if ((i == sel && pane == PANE_ACTIVE)); then rev_on; fi
    printf " %-*s " $((w - 2)) "$(truncate "$line" $((w - 2)))"
    reset
    ((row++))
    ((row >= body_h)) && break
  done
}

# ---------- Draw full UI ----------
draw_screen() {
  local cols=${COLUMNS:-80}
  local lines=${LINES:-24}

  local top=1
  local footer_h=3
  local preview_h=6
  local pane_h=$((lines - footer_h - preview_h - 1))
  ((pane_h < 6)) && pane_h=6

  local pane_w=$((cols / 2))
  ((pane_w < 20)) && pane_w=20

  local left_x=1
  local right_x=$((pane_w + 1))

  if [[ -n "$CLEAR_CMD" ]]; then "$CLEAR_CMD"; else clr; fi

  draw_pane 0 "$left_x" "$top" "$pane_w" "$pane_h"
  draw_pane 1 "$right_x" "$top" $((cols - pane_w + 1)) "$pane_h"

  # Preview area
  local preview_y=$((top + pane_h + 1))
  move "$preview_y" 1
  dim_on
  printf "%-*s" "$cols" ""
  dim_off
  move "$preview_y" 1
  printf " Preview (active: %s) " "$([[ $PANE_ACTIVE -eq 0 ]] && echo Left || echo Right)"

  local adir="${PANE_DIR[$PANE_ACTIVE]}"
  local afilter="${PANE_FILTER[$PANE_ACTIVE]}"
  local asel="${PANE_SEL[$PANE_ACTIVE]}"
  build_items "$adir" "$afilter"

  local path=""
  if ((ITEM_COUNT > 0)); then
    path="$adir/${ITEMS[$asel]}"
  fi

  local max_lines=$((preview_h - 2))
  local py=$((preview_y + 1))
  local l
  for ((l = 0; l < max_lines; l++)); do
    move $((py + l)) 1
    printf "%-*s" "$cols" ""
  done

  move "$py" 1
  if [[ -z "$path" ]]; then
    dim_on
    printf "%s" "(nothing selected)"
    dim_off
  elif [[ -d "$path" ]]; then
    printf "Directory: %s" "${path##*/}"
  else
    preview_text "$path" "$max_lines" | {
      local line row=0
      while IFS= read -r line && ((row < max_lines)); do
        move $((py + row)) 1
        printf "%s" "$(truncate "$line" "$cols")"
        ((row++))
      done
    }
  fi

  # Footer
  local footer_y=$((lines - footer_h + 1))
  move "$footer_y" 1
  printf "%-*s" "$cols" ""
  move "$footer_y" 1
  printf "[Tab] Switch  [↑/↓] Move  [Enter] Open/Edit  [Backspace] Up  [/] Filter  [Esc] Clear Filter"

  move $((footer_y + 1)) 1
  printf "%-*s" "$cols" ""
  move $((footer_y + 1)) 1
  printf "[c] Copy  [m] Move  [p] Paste->Other  [r] Rename  [n] New Folder  [f] New File  [d] Delete  [q] Quit"
}

# ---------- Helpers ----------
active_dir() { echo "${PANE_DIR[$PANE_ACTIVE]}"; }
inactive_dir() { echo "${PANE_DIR[$((1 - PANE_ACTIVE))]}"; }

active_item_path() {
  local dir="${PANE_DIR[$PANE_ACTIVE]}"
  local filter="${PANE_FILTER[$PANE_ACTIVE]}"
  local sel="${PANE_SEL[$PANE_ACTIVE]}"
  build_items "$dir" "$filter"
  ((ITEM_COUNT == 0)) && return 1
  echo "$dir/${ITEMS[$sel]}"
}

# ---------- Enter behavior: folder->enter, text->vi, other->pager ----------
open_item() {
  local p
  p="$(active_item_path)" || return 0
  if [[ -d "$p" ]]; then
    PANE_DIR[$PANE_ACTIVE]="$p"
    PANE_SEL[$PANE_ACTIVE]=0
    PANE_FILTER[$PANE_ACTIVE]=""
    return 0
  fi

  if is_text_editable "${p##*/}"; then
    if [[ -n "$CLEAR_CMD" ]]; then "$CLEAR_CMD"; else clr; fi
    echo "Editing: ${p##*/}"
    echo "Exit editor to return (vi: Esc, then :q, Enter)"
    echo "------------------------------------------------"
    "$VI_CMD" "$p"
  else
    if [[ -n "$CLEAR_CMD" ]]; then "$CLEAR_CMD"; else clr; fi
    echo "Viewing: ${p##*/}"
    echo "Press 'q' to return"
    echo "------------------------------------------------"
    "${PAGER:-less}" "$p"
  fi
}

go_up() {
  local dir="${PANE_DIR[$PANE_ACTIVE]}"
  PANE_DIR[$PANE_ACTIVE]=$("$DIRNAME_CMD" "$dir" 2>/dev/null || echo "${dir%/*}")
  [[ -z "${PANE_DIR[$PANE_ACTIVE]}" ]] && PANE_DIR[$PANE_ACTIVE]="/"
  PANE_SEL[$PANE_ACTIVE]=0
  PANE_FILTER[$PANE_ACTIVE]=""
}

do_copy() {
  local p
  p="$(active_item_path)" || return 0
  CLIP_MODE="copy"
  CLIP_NAME="${p##*/}"
  CLIP_SRC="$p"
}
do_move() {
  local p
  p="$(active_item_path)" || return 0
  CLIP_MODE="move"
  CLIP_NAME="${p##*/}"
  CLIP_SRC="$p"
}

do_paste() {
  [[ -z "$CLIP_MODE" || -z "$CLIP_SRC" || -z "$CLIP_NAME" ]] && return 0
  [[ ! -e "$CLIP_SRC" ]] && return 0
  local dest_dir
  dest_dir="$(inactive_dir)"
  local dest="$dest_dir/$CLIP_NAME"

  if [[ "$CLIP_MODE" == "copy" ]]; then
    "$CP_CMD" -r "$CLIP_SRC" "$dest" 2>/dev/null
  else
    "$MV_CMD" "$CLIP_SRC" "$dest" 2>/dev/null
    CLIP_MODE=""
    CLIP_NAME=""
    CLIP_SRC=""
  fi
}

do_delete() {
  local p
  p="$(active_item_path)" || return 0
  if [[ -n "$CLEAR_CMD" ]]; then "$CLEAR_CMD"; else clr; fi
  printf "Delete '%s'? (y/N): " "${p##*/}"
  read -r ans
  [[ "$ans" != "y" && "$ans" != "Y" ]] && return 0
  "$RM_CMD" -rf "$p" 2>/dev/null
  PANE_SEL[$PANE_ACTIVE]=0
}

do_rename() {
  local p
  p="$(active_item_path)" || return 0
  local dir="${p%/*}" old="${p##*/}"
  if [[ -n "$CLEAR_CMD" ]]; then "$CLEAR_CMD"; else clr; fi
  printf "Rename '%s' to: " "$old"
  read -r new
  [[ -z "$new" || "$new" == "$old" ]] && return 0
  if [[ -e "$dir/$new" ]]; then
    printf "Target exists. Overwrite? (y/N): "
    read -r ans
    [[ "$ans" != "y" && "$ans" != "Y" ]] && return 0
  fi
  "$MV_CMD" "$dir/$old" "$dir/$new" 2>/dev/null
}

do_new_folder() {
  local dir
  dir="$(active_dir)"
  if [[ -n "$CLEAR_CMD" ]]; then "$CLEAR_CMD"; else clr; fi
  printf "New folder name: "
  read -r name
  [[ -z "$name" ]] && return 0
  mkdir -p "$dir/$name" 2>/dev/null
}

do_new_file() {
  local dir
  dir="$(active_dir)"
  if [[ -n "$CLEAR_CMD" ]]; then "$CLEAR_CMD"; else clr; fi
  printf "New file name: "
  read -r name
  [[ -z "$name" ]] && return 0
  : >"$dir/$name" 2>/dev/null
}

do_filter() {
  if [[ -n "$CLEAR_CMD" ]]; then "$CLEAR_CMD"; else clr; fi
  printf "Filter (active pane): "
  read -r q
  PANE_FILTER[$PANE_ACTIVE]="$q"
  PANE_SEL[$PANE_ACTIVE]=0
}

clear_filter() {
  PANE_FILTER[$PANE_ACTIVE]=""
  PANE_SEL[$PANE_ACTIVE]=0
}

# ---------- Key loop ----------
while true; do
  draw_screen
  IFS= read -rsn1 key

  case "$key" in
  $'\t') PANE_ACTIVE=$((1 - PANE_ACTIVE)) ;;
  "") open_item ;;
  $'\x7f') go_up ;;
  /) do_filter ;;
  $'\x1b')
    IFS= read -rsn2 -t 0.02 k2
    case "$k2" in
    "[A") PANE_SEL[$PANE_ACTIVE]=$((PANE_SEL[$PANE_ACTIVE] - 1)) ;;
    "[B") PANE_SEL[$PANE_ACTIVE]=$((PANE_SEL[$PANE_ACTIVE] + 1)) ;;
    *) clear_filter ;;
    esac
    ;;
  c) do_copy ;;
  m) do_move ;;
  p) do_paste ;;
  r) do_rename ;;
  n) do_new_folder ;;
  f) do_new_file ;;
  d) do_delete ;;
  q)
    if [[ -n "$CLEAR_CMD" ]]; then "$CLEAR_CMD"; else clr; fi
    echo "${PANE_DIR[$PANE_ACTIVE]}"
    exit 0
    ;;
  esac
done
