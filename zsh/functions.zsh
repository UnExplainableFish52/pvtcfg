# ---- tp: semantic teleport menu + fuzzy search ----
# Usage:
#   tp                 -> interactive menu
#   tp c|i|t|p...      -> direct jump (single-key)
#   tp <text>          -> fuzzy search among known dirs (non-interactive best match)
#   tp -s <text>       -> list matches
#   tp -f              -> interactive picker (requires fzf)

# Resolve Documents dir robustly (XDG aware)
_tp_docs_dir() {
  local docs=""
  if command -v xdg-user-dir >/dev/null 2>&1; then
    docs="$(xdg-user-dir DOCUMENTS 2>/dev/null)"
  fi
  if [[ -z "$docs" || "$docs" == "$HOME" ]]; then
    docs="$HOME/Documents"
  fi
  print -r -- "$docs"
}

# function to check for recent files modified with sorting, filepath and info
function check_recent_files() {
    find "$@" -type f -printf '%T@ %T+ %p\n' | sort -nr | cut -d' ' -f2-
}

_tp_mkdir() { command mkdir -p -- "$1" 2>/dev/null; }

# Empty directory contents (includes nested dirs). Keeps the directory itself.
_tp_empty_dir_contents() {
  emulate -L zsh
  local dir="$1"
  [[ -d "$dir" && ! -L "$dir" && "${dir:A}" != / && "${dir:A}" != "${HOME:A}" ]] || return 1
  local -a entries=( "$dir"/*(DN) )
  (( ${#entries} )) || return 0
  command rm -rf -- "${entries[@]}"
}

# TSH: reset a dedicated scratch workspace and enter it in the CURRENT shell.
# Every invocation discards the previous contents, including hidden files.
# This is a working directory, not a child shell or an isolated shell environment.
TSH() {
  emulate -L zsh
  (( $# == 0 )) || { print -u2 -r -- 'Usage: TSH (no arguments)'; return 1; }

  [[ "$HOME" == /* && -d "$HOME" && "${HOME:A}" != / ]] || {
    print -u2 -r -- 'TSH: HOME must be an existing absolute home directory.'
    return 1
  }

  local docs="$HOME/Documents"
  local base="$docs/shell"
  local workspace="$base/temp_session"
  local component

  # Refuse symlinked parents or targets, and files where directories are expected.
  # A symlink INSIDE the scratch directory is removed without following its target.
  for component in "$docs" "$base" "$workspace"; do
    if [[ -L "$component" || ( -e "$component" && ! -d "$component" ) ]]; then
      print -u2 -r -- "TSH: refusing non-directory or symlink: $component"
      return 1
    fi
  done

  command mkdir -p -- "$workspace" || return 1
  # Enter before deleting so a failed cd cannot clear an inaccessible workspace.
  builtin cd -- "$workspace" || return 1
  _tp_empty_dir_contents "$workspace" || {
    print -u2 -r -- 'TSH: reset failed; some previous contents may remain.'
    return 1
  }
  print -r -- "TSH: fresh workspace at $workspace"
}

tsh() { TSH "$@"; }

# Build candidate list: "key<TAB>label<TAB>path"
_tp_candidates() {
  local docs="$(_tp_docs_dir)"
  local codes="$docs/codes"
  local temp="$codes/temp"
  local notes="$docs/notes"

  printf '%s\t%s\t%s\n' \
    c codes "$codes" \
    p codes "$codes" \
    t temp "$temp" \
    i zsh_config "$HOME/.zsh_config" \
    d downloads "$HOME/Downloads" \
    n notes "$notes" \
    b local_bin "$HOME/.local/bin" \
    s ssh "$HOME/.ssh" \
    h home "$HOME"
}

# Non-interactive fuzzy scorer: prefers substring matches; shorter label/path wins.
# Returns best matching path for a query, or empty.
_tp_best_match_path() {
  local q="$1"
  local bestPath=""
  local bestScore=999999

  [[ -z "$q" ]] && return 1
  q="${q:l}"  # lowercase

  local key label dest hay score pos
  while IFS=$'\t' read -r key label dest; do
    hay="${key} ${label} ${dest}"
    hay="${hay:l}"

    # If query is substring, score by (position + length); else skip
    pos="$(awk -v a="$hay" -v b="$q" 'BEGIN{print index(a,b)}' 2>/dev/null)"
    [[ -z "$pos" ]] && continue
    (( pos == 0 )) && continue

    # Lower is better
    score=$(( pos + ${#hay} ))
    if (( score < bestScore )); then
      bestScore="$score"
      bestPath="$dest"
    fi
  done < <(_tp_candidates)

  [[ -n "$bestPath" ]] && print -r -- "$bestPath"
}

# List matches for a query (for -s mode)
_tp_list_matches() {
  local q="$1"
  q="${q:l}"
  local key label dest hay
  while IFS=$'\t' read -r key label dest; do
    hay="${key} ${label} ${dest}"
    hay="${hay:l}"
    if [[ "$hay" == *"$q"* ]]; then
      print -P "%F{cyan}%B${key}%b%f  %F{yellow}${label}%f  %F{green}${dest}%f"
    fi
  done < <(_tp_candidates)
}

tp() {
  local docs="$(_tp_docs_dir)"
  local codes="$docs/codes"
  local temp="$codes/temp"

  # Ensure base dirs exist
  _tp_mkdir "$codes"
  _tp_mkdir "$temp"

  local arg1="${1:-}"
  local arg2="${2:-}"

  # ---- flags ----
  if [[ "$arg1" == "-f" ]]; then
    if ! command -v fzf >/dev/null 2>&1; then
      print -P "%F{red}%Bfzf not found.%b%f Install it or use: tp <text>"
      return 1
    fi

    local picked
    picked="$(_tp_candidates | fzf --with-nth=1,2,3 --delimiter=$'\t' --prompt='tp> ' --ansi)"
    [[ -z "$picked" ]] && return 0

    local key label dest
    IFS=$'\t' read -r key label dest <<< "$picked"

    # Handle temp empty prompt if selecting temp
    if [[ "$key" == "t" ]]; then
      print -P "%F{yellow}%BTemp directory:%b%f $dest"
      echo -n "Empty temp contents (including subfolders) before cd? (y/N): "
      local ans; read -r ans
      if [[ "$ans" == [yY] ]]; then
        _tp_empty_dir_contents "$dest" || return 1
        print -P "%F{green}%BTemp emptied.%b%f"
      fi
    fi

    builtin cd -- "$dest"
    return $?
  fi

  if [[ "$arg1" == "-s" ]]; then
    [[ -z "$arg2" ]] && { print -P "%F{red}%BUsage:%b%f tp -s <text>"; return 1; }
    _tp_list_matches "$arg2"
    return 0
  fi

  # ---- direct single-key ----
  if [[ -n "$arg1" && ${#arg1} -eq 1 ]]; then
    case "$arg1" in
      c|p) builtin cd -- "$codes"; return $? ;;
      i) builtin cd -- "$HOME/.zsh_config"; return $? ;;
      d) builtin cd -- "$HOME/Downloads"; return $? ;;
      n) _tp_mkdir "$docs/notes"; builtin cd -- "$docs/notes"; return $? ;;
      b) _tp_mkdir "$HOME/.local/bin"; builtin cd -- "$HOME/.local/bin"; return $? ;;
      s) builtin cd -- "$HOME/.ssh"; return $? ;;
      h) builtin cd -- "$HOME"; return $? ;;
      t)
        print -P "%F{yellow}%BTemp directory:%b%f $temp"
        echo -n "Empty temp contents (including subfolders) before cd? (y/N): "
        local ans; read -r ans
        if [[ "$ans" == [yY] ]]; then
          _tp_empty_dir_contents "$temp" || return 1
          print -P "%F{green}%BTemp emptied.%b%f"
        fi
        builtin cd -- "$temp"
        return $?
        ;;
      q|"") return 0 ;;
    esac
  fi

  # ---- fuzzy text mode ----
  if [[ -n "$arg1" ]]; then
    local best="$(_tp_best_match_path "$arg1")"
    if [[ -z "$best" ]]; then
      print -P "%F{red}%BNo match for:%b%f $arg1"
      print -P "%F{yellow}%BTip:%b%f try: tp -s $arg1  (to see matches) or tp -f (interactive)"
      return 1
    fi

    # If fuzzy matched temp, still ask to empty
    if [[ "$best" == */temp ]]; then
      print -P "%F{yellow}%BTemp directory:%b%f $best"
      echo -n "Empty temp contents (including subfolders) before cd? (y/N): "
      local ans; read -r ans
      if [[ "$ans" == [yY] ]]; then
        _tp_empty_dir_contents "$best" || return 1
        print -P "%F{green}%BTemp emptied.%b%f"
      fi
    fi

    builtin cd -- "$best"
    return $?
  fi

  # ---- menu mode ----
  print -P "%F{cyan}%Btp menu:%b%f"
  print "  c  -> ${codes}"
  print "  p  -> ${codes}"
  print "  t  -> ${temp}"
  print "  i  -> $HOME/.zsh_config"
  print "  d  -> $HOME/Downloads"
  print "  n  -> ${docs}/notes"
  print "  b  -> $HOME/.local/bin"
  print "  s  -> $HOME/.ssh"
  print "  h  -> $HOME"
  print "  q  -> quit"
  print "  tip: tp <text> (fuzzy) | tp -s <text> (list) | tp -f (fzf picker)"
  echo -n "Choose: "
  local choice; read -r choice
  tp "$choice"
}

# ---- rand / random / rint: random integer generator ----
# Usage:
#   rand              -> 1..100
#   rand N            -> 1..N
#   rand A B          -> A..B  (order doesn't matter)
#
# Integer = whole number (no decimals)

_rint_core() {
  local a="$1"
  local b="$2"

  if (( a > b )); then
    local tmp="$a"; a="$b"; b="$tmp"
  fi

  local range=$(( b - a + 1 ))
  if (( range <= 0 )); then
    print -P "%F{red}%BInvalid range.%b%f"
    return 1
  fi

  # Better spread than plain RANDOM
  local r=$(( (RANDOM << 15) ^ RANDOM ))
  local val=$(( a + (r % range) ))
  print -- "$val"
}

rand() {
  if (( $# == 0 )); then
    _rint_core 1 100
  elif (( $# == 1 )); then
    [[ "$1" == <-> ]] || { print -P "%F{red}%BUsage:%b%f rand [max] or rand [min] [max]"; return 1; }
    (( $1 >= 1 )) || { print -P "%F{red}%BMax must be >= 1%b%f"; return 1; }
    _rint_core 1 "$1"
  elif (( $# == 2 )); then
    [[ "$1" == -<-> || "$1" == <-> ]] || { print -P "%F{red}%BIntegers only.%b%f"; return 1; }
    [[ "$2" == -<-> || "$2" == <-> ]] || { print -P "%F{red}%BIntegers only.%b%f"; return 1; }
    _rint_core "$1" "$2"
  else
    print -P "%F{red}%BUsage:%b%f rand | rand MAX | rand MIN MAX"
    return 1
  fi
}

random() { rand "$@"; }
rint()   { rand "$@"; }

# python vevn configs 
mkvenv(){
python3 -m venv "$1" && cd "$1" && source bin/activate
}
