#!/usr/bin/env bash
# Install a permanent, Git-tracked Zsh configuration, with or without sudo.
# Download this file alone, or run it from a clone. The working directory is irrelevant.
set -euo pipefail

# Small, self-contained UI: standalone downloads need no extra files or tools.
RESET='' BOLD='' GRAY='' GOLD='' GREEN='' CYAN=''
COLOR_MODE=none UI_WIDTH=80 UI_UTF8=false
PLAIN=false PREVIEW=false NO_ANSI=false CURRENT_STAGE='preflight'
SPINNER_PID='' CURRENT_STEP=0 LOG_FILE=''
PIXEL_FG=() PIXEL_BG=()
PALETTE_SYMBOLS='.gyhsdvGcb'
# Hand-placed pixels: gold horns, slate hair, cream face, green cape, blue magic.
# Two pixel rows share one terminal row. Dots leave the terminal background alone.
LOKI_PIXELS=(
  'b..........y..........y.....'
  '.b........yy.........yy.....'
  '.bc......yy.........yy......'
  '..cc.....yg.........yg......'
  '..c......yg.........yg......'
  '..cc......yg..hhhh..yg......'
  '.cccc......yggyyyyggg.......'
  '...cc.....hhgyyyygyhh.......'
  '....cg...hhsssssssssshh.....'
  '....g....hhssddsssdsshh.....'
  '....g....hhsssssssssshh.....'
  '....g.....hssssdsdsssh......'
  '....g......hssssdsssh.......'
  '....g.......hhhhhhhv........'
  '....g.....hvvsyyvvvGvv......'
  '.....g...hvvvGvvGGvGvvvvv...'
  '......g.hvvvhGvGhhvGvvvvvvv.'
  '.......hvGvhGvGhhhvGvvvvvv..'
  '........hGvhGvGhhhvGvvv.....'
  '........hGvhGvGhhhhGv.......'
  '.......hhGvhGvGhhhhh........'
  '.......hGGvhGvGhhh..........'
  '.........dhh..hhd...........'
  '.........ddd..ddd...........'
)

set_palette() {
  local index code
  local -a rgb=('' '211;157;47' '247;211;111' '70;80;96' '239;230;188'
    '35;44;56' '79;153;66' '44;107;58' '48;187;219' '38;130;184')
  local -a indexed=(0 178 222 240 230 237 71 29 80 32)
  local -a basic=(0 33 93 90 97 30 32 32 96 36)
  COLOR_MODE="$1"
  RESET=$'\033[0m' BOLD=$'\033[1m'
  GRAY=$'\033[90m' GOLD=$'\033[33m' GREEN=$'\033[32m' CYAN=$'\033[36m'
  for (( index=1; index<${#rgb[@]}; index++ )); do
    case "$COLOR_MODE" in
      truecolor)
        printf -v code '\033[38;2;%sm' "${rgb[index]}"; PIXEL_FG[index]="$code"
        printf -v code '\033[48;2;%sm' "${rgb[index]}"; PIXEL_BG[index]="$code" ;;
      256)
        printf -v code '\033[38;5;%sm' "${indexed[index]}"; PIXEL_FG[index]="$code"
        printf -v code '\033[48;5;%sm' "${indexed[index]}"; PIXEL_BG[index]="$code" ;;
      *)
        printf -v code '\033[%sm' "${basic[index]}"; PIXEL_FG[index]="$code"
        printf -v code '\033[%sm' "$(( ${basic[index]} + 10 ))"; PIXEL_BG[index]="$code" ;;
    esac
  done
  GOLD="${PIXEL_FG[1]}" GREEN="${PIXEL_FG[6]}" CYAN="${PIXEL_FG[8]}"
}

init_style() {
  local locale="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
  UI_WIDTH="${COLUMNS:-80}"
  if [[ -z "${COLUMNS:-}" && -t 1 ]] && command -v tput >/dev/null 2>&1; then
    UI_WIDTH="$(tput cols 2>/dev/null || printf '80')"
  fi
  [[ "$UI_WIDTH" =~ ^[0-9]{1,3}$ ]] || UI_WIDTH=80
  UI_WIDTH=$((10#$UI_WIDTH))
  (( UI_WIDTH > 0 )) || UI_WIDTH=1
  case "$locale" in *UTF-8*|*utf-8*|*UTF8*|*utf8*) UI_UTF8=true ;; esac
  if [[ -t 1 && "${TERM:-dumb}" != dumb && -z "${NO_COLOR+x}" && "$NO_ANSI" == false && "$PLAIN" == false ]]; then
    case "${COLORTERM:-}:${TERM:-}" in
      *truecolor*|*24bit*|*direct*) set_palette truecolor ;;
      *256color*) set_palette 256 ;;
      *) set_palette basic ;;
    esac
  fi
}

fail() {
  if [[ -t 2 && "${TERM:-dumb}" != dumb && -z "${NO_COLOR+x}" && "$NO_ANSI" == false && "$PLAIN" == false ]]; then
    printf '\033[31;1m  error\033[0m  %s\n' "$*" >&2
  else
    printf 'zshcfg: %s\n' "$*" >&2
  fi
  exit 1
}

center_line() {
  local text="$1" style="${2:-}" width="${3:-${#1}}" padding=0
  (( UI_WIDTH > width )) && padding=$(( (UI_WIDTH - width) / 2 ))
  printf '%*s%s%s%s\n' "$padding" '' "$style" "$text" "$RESET"
}

loki_art() {
  local row col top bottom prefix fg bg glyph last_fg last_bg padding
  padding=$(( (UI_WIDTH - 28) / 2 ))
  for (( row=0; row<${#LOKI_PIXELS[@]}; row+=2 )); do
    printf '%*s' "$padding" ''
    last_fg='' last_bg=''
    for (( col=0; col<28; col++ )); do
      top="${LOKI_PIXELS[row]:col:1}" bottom="${LOKI_PIXELS[row+1]:col:1}"
      fg='' bg=$'\033[49m' glyph=' '
      if [[ "$top" != . ]]; then
        prefix="${PALETTE_SYMBOLS%%"$top"*}"; fg="${PIXEL_FG[${#prefix}]}"; glyph='▀'
        if [[ "$bottom" != . ]]; then
          prefix="${PALETTE_SYMBOLS%%"$bottom"*}"; bg="${PIXEL_BG[${#prefix}]}"
        fi
      elif [[ "$bottom" != . ]]; then
        prefix="${PALETTE_SYMBOLS%%"$bottom"*}"; fg="${PIXEL_FG[${#prefix}]}"; glyph='▄'
      fi
      if [[ "$fg" != "$last_fg" ]]; then printf '%s' "$fg"; last_fg="$fg"; fi
      if [[ "$bg" != "$last_bg" ]]; then printf '%s' "$bg"; last_bg="$bg"; fi
      printf '%s' "$glyph"
    done
    printf '%s\n' "$RESET"
  done
}

banner() {
  local line
  # Redirection, dumb terminals, plain mode and NO_COLOR get a small text header.
  if [[ "$PLAIN" == true || "$COLOR_MODE" == none ]]; then
    if [[ -t 1 && "$PLAIN" == false ]]; then center_line 'SHCFG'; else printf 'SHCFG\n'; fi
    return
  fi
  printf '\n'
  if [[ "$UI_UTF8" == true ]] && (( UI_WIDTH >= 33 )); then
    while IFS= read -r line; do center_line "$line" "$GOLD$BOLD" 33; done <<'TITLE'
█████  █   █  █████  █████  █████
█      █   █  █      █      █
█████  █████  █      ████   █  ██
    █  █   █  █      █      █   █
█████  █   █  █████  █      █████
TITLE
  else
    center_line 'SHCFG' "$GOLD$BOLD"
  fi
  if [[ "$UI_UTF8" == true ]] && (( UI_WIDTH >= 28 )); then
    printf '\n'
    loki_art
  fi
  printf '\n'
  if (( UI_WIDTH >= 32 )); then center_line 'Zsh environment setup' "$GRAY"; fi
  printf '\n'
}

detail() { printf '  %s%-10s%s %s\n' "$GRAY" "$1" "$RESET" "$2"; }
stage_line() {
  local symbol="$1" style="$2" label="$CURRENT_STAGE" limit=$(( UI_WIDTH - 6 ))
  (( limit > 0 )) || limit=1
  if [[ "$COLOR_MODE" != none ]]; then
    printf '\r\033[2K  %s%s%s  %.*s' "$style" "$symbol" "$RESET" "$limit" "$label" >&3
  else
    printf '  %s  %s' "$symbol" "$label" >&3
  fi
}

spinner_loop() {
  local frame=0 frames='|/-\'
  while :; do
    stage_line "${frames:frame:1}" "$CYAN"
    sleep 0.12
    frame=$(( (frame + 1) % 4 ))
  done
}

pause_spinner() {
  if [[ -n "$SPINNER_PID" ]]; then
    kill "$SPINNER_PID" 2>/dev/null || true
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_PID=''
    printf '\r\033[2K' >&3
  fi
}

resume_spinner() {
  if [[ "$COLOR_MODE" != none && "$CURRENT_STEP" != 0 ]]; then
    spinner_loop &
    SPINNER_PID=$!
  fi
}

step() {
  CURRENT_STEP="$1" CURRENT_STAGE="$2"
  resume_spinner
}

complete_step() {
  pause_spinner
  stage_line '*' "$GREEN"
  printf '\n' >&3
  CURRENT_STEP=0
}
finish() {
  printf '\n  %s%s%s\n' "$GREEN" "${1:-Configuration ready.}" "$RESET"
  detail 'edit' "nano \"$CONFIG_HOME/.zsh_config/aliases.zsh\""
  detail 'reload' 'exec zsh'
  detail 'publish' 'shcfgpush'
  detail 'pull' 'shcfgpull'
  detail 'commands' 'shcfghelp'
  if [[ -n "$LOG_FILE" ]]; then detail 'log' "$LOG_FILE"; fi
  printf '\n'
}

# sudo may change HOME to /root. Resolve the original caller from the account
# database instead, and verify the UID before touching any configuration files.
INSTALL_USER="$(id -un)"
INSTALL_UID="$EUID"
INSTALL_HOME="$HOME"
INSTALL_SHELL="${SHELL:-}"
if (( EUID == 0 )) && [[ -n "${SUDO_USER:-}" ]]; then
  caller_record="$(getent passwd "$SUDO_USER")" || fail "Cannot resolve sudo caller: $SUDO_USER"
  IFS=: read -r INSTALL_USER _ INSTALL_UID _ _ INSTALL_HOME INSTALL_SHELL <<< "$caller_record"
  [[ "$INSTALL_UID" =~ ^[0-9]+$ && "$INSTALL_UID" == "${SUDO_UID:-}" ]] || fail 'Sudo caller name and UID do not match.'
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
CONFIG_HOME="${ZSHCFG_HOME:-$INSTALL_HOME}"
[[ "$CONFIG_HOME" == /* && "$CONFIG_HOME" != / ]] || { printf 'An absolute, non-root home path is required.\n' >&2; exit 1; }
REPO="$CONFIG_HOME/.local/share/zshcfg/repo"
REMOTE="${ZSHCFG_REMOTE:-https://github.com/UnExplainableFish52/pvtcfg.git}"
BRANCH="${ZSHCFG_BRANCH:-main}"
ASSUME_YES=false
SKIP_DEPS=false
NO_CHSH=false
STAMP="$(date +%Y-%m-%d_%H-%M-%S)-$$"
declare -a INSTALLED=() BACKUPS=()
ACTIVATING=false

info() { printf '  %s\n' "$*"; }
confirm() {
  local answer='n'
  pause_spinner
  printf '\n  %s?%s %s [y/N] ' "$CYAN" "$RESET" "$1"
  read -r answer || true
  printf '\n'
  [[ "$answer" == [yY] ]]
}
as_admin() {
  if (( EUID == 0 )); then
    "$@"
  else
    # Authentication stays in the foreground, outside the captured stage output.
    pause_spinner
    sudo -v <&4 >&3 2>&5
    resume_spinner
    sudo -n "$@"
  fi
}
as_user() {
  # Git, downloads, backups and links belong to the installing user, not root.
  if (( EUID == 0 && INSTALL_UID != 0 )); then
    sudo -H -u "$INSTALL_USER" -- "$@"
  else
    "$@"
  fi
}

for option in "$@"; do
  case "$option" in
    --yes) ASSUME_YES=true ;;
    --skip-deps) SKIP_DEPS=true ;;
    --no-chsh) NO_CHSH=true ;;
    --no-color) NO_ANSI=true ;;
    --plain) PLAIN=true ;;
    --preview) PREVIEW=true ;;
    --help)
      printf 'Usage: bash install.sh [--yes] [--skip-deps] [--no-chsh] [--no-color] [--plain] [--preview]\n'
      printf '  --no-color  Disable ANSI styling (also respects NO_COLOR).\n'
      printf '  --plain     Use a compact banner without ANSI styling.\n'
      printf '  --preview   Show the interface without installing or changing files.\n'
      printf 'Install target: %s (%s)\n' "$INSTALL_USER" "$CONFIG_HOME"
      printf 'ZSHCFG_HOME selects an alternate home directory for isolated testing.\n'
      printf 'ZSHCFG_REMOTE / ZSHCFG_BRANCH select a fork or branch for standalone bootstrap.\n'
      exit 0 ;;
    *) fail "Unknown option: $option" ;;
  esac
done
init_style

if [[ "$PREVIEW" == true ]]; then
  exec 3>&1
  trap 'pause_spinner; exit 130' INT
  trap 'pause_spinner; exit 143' TERM
  banner
  info 'Preview only; no files changed.'
  preview_stage=0
  for label in 'Tools and plugins' 'Configuration' 'Dotfiles' 'Login shell'; do
    preview_stage=$((preview_stage + 1))
    step "$preview_stage" "$label"
    if [[ "$COLOR_MODE" != none ]]; then sleep 0.6; fi
    complete_step
  done
  printf '\n'
  exit 0
fi

# Config activation is reversible. Dependencies and the checkout are kept on failure.
rollback() {
  local result=$? i
  pause_spinner
  if (( result != 0 && CURRENT_STEP != 0 )); then
    stage_line '!' "$GOLD"
    printf '\n' >&3
  fi
  if [[ "$ACTIVATING" == true ]]; then
    printf 'zshcfg: Activation failed; restoring replaced configuration files.\n' >&5
    set +e
    for (( i=${#INSTALLED[@]}-1; i>=0; i-- )); do
      as_user rm -f -- "${INSTALLED[i]}"
      if [[ -n "${BACKUPS[i]}" ]]; then as_user mv -- "${BACKUPS[i]}" "${INSTALLED[i]}"; fi
    done
  fi
  if (( result != 0 )); then
    if [[ -n "$LOG_FILE" && -s "$LOG_FILE" ]]; then
      printf '\n' >&5
      tail -n 15 -- "$LOG_FILE" >&5 || true
      printf '\nFull log: %s\n' "$LOG_FILE" >&5
    fi
    printf 'zshcfg: Installation stopped during: %s. Fix the error above, then rerun.\n' "$CURRENT_STAGE" >&5
  fi
  exit "$result"
}
trap rollback EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

install_packages() {
  local tool manager package
  local -a wanted=() packages=()
  local -a tools=(zsh git curl nano fzf rg bat eza python3)
  for tool in "${tools[@]}"; do
    if [[ "$tool" == bat ]] && command -v batcat >/dev/null 2>&1; then continue; fi
    command -v "$tool" >/dev/null 2>&1 || wanted+=("$tool")
  done
  if ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import venv, ensurepip' 2>/dev/null; then
    wanted+=(venv)
  fi
  if (( ${#wanted[@]} == 0 )); then
    info 'All required command-line tools are already available.'
    return 0
  fi

  for manager in apt-get dnf pacman zypper apk; do
    command -v "$manager" >/dev/null 2>&1 && break
  done
  command -v "$manager" >/dev/null 2>&1 || fail "Install these missing tools manually, then rerun: ${wanted[*]}"
  for tool in "${wanted[@]}"; do
    package="$tool"
    case "$tool" in
      rg) package=ripgrep ;;
      python3) [[ "$manager" != pacman ]] || package=python ;;
      venv)
        case "$manager" in
          apt-get) package=python3-venv ;;
          pacman) package=python ;;
          *) package=python3 ;;
        esac ;;
    esac
    [[ " ${packages[*]} " == *" $package "* ]] || packages+=("$package")
  done
  info "Installing missing packages using $manager: ${packages[*]}"
  case "$manager" in
    apt-get) as_admin apt-get update; as_admin apt-get install -y "${packages[@]}" ;;
    dnf) as_admin dnf install -y "${packages[@]}" ;;
    pacman) as_admin pacman -S --needed --noconfirm "${packages[@]}" ;;
    zypper) as_admin zypper --non-interactive install "${packages[@]}" ;;
    apk) as_admin apk add "${packages[@]}" ;;
  esac
  for tool in "${tools[@]}"; do
    if [[ "$tool" == bat ]] && command -v batcat >/dev/null 2>&1; then continue; fi
    command -v "$tool" >/dev/null 2>&1 || fail "Missing after installation: $tool. Configuration has not been replaced."
  done
  python3 -c 'import venv, ensurepip' || fail 'Python venv support is missing.'
}

clone_dependency() {
  local url="$1" destination="$2" expected="$3"
  info "Shell component: ${destination##*/}"
  if [[ ! -e "$destination" ]]; then
    as_user mkdir -p -- "$(dirname -- "$destination")"
    as_user git clone --depth=1 "$url" "$destination"
  fi
  [[ -f "$destination/$expected" ]] || fail "Incomplete dependency: $destination (expected $expected)."
}

install_dependencies() {
  install_packages
  # Clone directly: the Oh My Zsh installer must not overwrite .zshrc first.
  clone_dependency https://github.com/ohmyzsh/ohmyzsh.git "$CONFIG_HOME/.oh-my-zsh" oh-my-zsh.sh
  clone_dependency https://github.com/romkatv/powerlevel10k.git "$CONFIG_HOME/.oh-my-zsh/custom/themes/powerlevel10k" powerlevel10k.zsh-theme
  clone_dependency https://github.com/zsh-users/zsh-autosuggestions.git "$CONFIG_HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" zsh-autosuggestions.plugin.zsh
  clone_dependency https://github.com/zsh-users/zsh-syntax-highlighting.git "$CONFIG_HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" zsh-syntax-highlighting.plugin.zsh
}

prepare_repo() {
  as_user mkdir -p -- "$(dirname -- "$REPO")"
  [[ ! -L "$REPO" ]] || fail "The permanent checkout cannot be a symlink: $REPO"
  if [[ -e "$REPO" ]]; then
    [[ -d "$REPO/.git" ]] || fail "Existing path is not a normal Git checkout: $REPO"
    info 'Keeping the existing permanent checkout. Use zshcfg pull for updates.'
  elif [[ -f "$SCRIPT_DIR/.zshrc" && -f "$SCRIPT_DIR/bin/zshcfg" && -d "$SCRIPT_DIR/.git" ]]; then
    local source_status
    source_status="$(as_user git -C "$SCRIPT_DIR" status --porcelain)" || fail 'The installing user must be able to read the source Git checkout.'
    [[ -z "$source_status" ]] || fail 'The source checkout has uncommitted changes. Commit them before installing.'
    as_user git clone --no-hardlinks "$SCRIPT_DIR" "$REPO"
    # A local clone should continue syncing with the original online remote.
    local source_remote source_branch
    source_remote="$(as_user git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null || printf '%s' "$REMOTE")"
    as_user git -C "$REPO" remote set-url origin "$source_remote"
    source_branch="$(as_user git -C "$REPO" symbolic-ref --short HEAD)"
    as_user git -C "$REPO" config "branch.$source_branch.remote" origin
    as_user git -C "$REPO" config "branch.$source_branch.merge" "refs/heads/$source_branch"
  else
    as_user git clone --branch "$BRANCH" "$REMOTE" "$REPO"
  fi
  [[ -f "$REPO/bin/zshcfg" && -f "$REPO/.zshrc" && -f "$REPO/VERSION" && -d "$REPO/zsh" ]] || fail 'The selected remote does not contain the new zshcfg layout. Select the implementation branch until it is merged.'
  bash -n "$REPO/install.sh"
  bash -n "$REPO/bin/zshcfg"
  local file
  for file in "$REPO/.zshrc" "$REPO/.p10k.zsh" "$REPO"/zsh/*.zsh; do zsh -n "$file"; done
  [[ -f "$REPO/.nanorc" ]] || fail 'The checkout is missing .nanorc.'
}

link_file() {
  local source="$1" destination="$2" backup=''
  if [[ -L "$destination" && "$(readlink -f -- "$destination")" == "$source" ]]; then
    info "Already linked: $destination"
    return
  fi
  if [[ -e "$destination" || -L "$destination" ]]; then
    backup="$destination.bak.$STAMP"
    [[ ! -e "$backup" && ! -L "$backup" ]] || fail "Backup already exists: $backup"
    if [[ -L "$destination" && -f "$destination" ]]; then
      # Freeze old linked contents; later Git updates must not alter the backup.
      as_user cp -pL -- "$destination" "$backup"
      as_user rm -- "$destination"
    else
      as_user mv -- "$destination" "$backup"
    fi
    info "Backup: $backup"
  fi
  INSTALLED+=("$destination")
  BACKUPS+=("$backup")
  as_user ln -s -- "$source" "$destination"
  info "Linked: $destination"
}

activate_config() {
  local module destination
  local -a sources=("$REPO/.zshrc" "$REPO/.p10k.zsh" "$REPO/.nanorc" "$REPO/bin/zshcfg")
  local -a destinations=("$CONFIG_HOME/.zshrc" "$CONFIG_HOME/.p10k.zsh" "$CONFIG_HOME/.nanorc" "$CONFIG_HOME/.local/bin/zshcfg")
  for module in env options aliases functions keybinds; do
    sources+=("$REPO/zsh/$module.zsh")
    destinations+=("$CONFIG_HOME/.zsh_config/$module.zsh")
  done
  # Keep the module directory real so local.zsh stays outside the checkout.
  [[ ! -L "$CONFIG_HOME/.zsh_config" ]] || fail 'Existing ~/.zsh_config is a symlink; preserve/move it before installing individual module links.'
  as_user mkdir -p -- "$CONFIG_HOME/.zsh_config" "$CONFIG_HOME/.local/bin"
  for destination in "${destinations[@]}"; do
    [[ ! -d "$destination" ]] || fail "A directory occupies a file destination: $destination"
  done
  for module in "${sources[@]}"; do [[ -f "$module" ]] || fail "Missing source: $module"; done

  ACTIVATING=true
  local i
  for (( i=0; i<${#sources[@]}; i++ )); do link_file "${sources[i]}" "${destinations[i]}"; done
  # Never overwrite an existing local override (including symlinks).
  if [[ ! -e "$CONFIG_HOME/.zsh_config/local.zsh" && ! -L "$CONFIG_HOME/.zsh_config/local.zsh" ]]; then
    (umask 077; as_user cp -- "$REPO/zsh/local.example.zsh" "$CONFIG_HOME/.zsh_config/local.zsh")
  fi
  ACTIVATING=false
}

offer_default_shell() {
  CURRENT_STAGE='Login shell (skipped)'
  [[ "$NO_CHSH" != true ]] || return 0
  # Alternate-home installations are for fixtures/staging, not account changes.
  [[ "$CONFIG_HOME" == "$INSTALL_HOME" ]] || return 0
  CURRENT_STAGE='Login shell (unchanged)'
  local zsh_path
  zsh_path="$(command -v zsh)"
  [[ "$INSTALL_SHELL" != "$zsh_path" ]] || return 0
  if confirm 'Set Zsh as the default login shell?'; then
    if ! grep -qxF "$zsh_path" /etc/shells; then
      info "Zsh must be listed in /etc/shells first: $zsh_path"
      return 0
    fi
    if as_user chsh -s "$zsh_path"; then
      CURRENT_STAGE='Login shell'
    else
      info "Login shell unchanged. Run: chsh -s $zsh_path"
    fi
  fi
}

exec 3>&1 4<&0 5>&2
banner
detail 'home' "$CONFIG_HOME"
printf '\n'
info 'Existing files get dated backups; local.zsh stays private.'
if [[ "$ASSUME_YES" != true ]]; then
  confirm 'Install tools and link the configuration?' || { info 'Installation cancelled.'; exit 0; }
fi
as_user mkdir -p -- "$CONFIG_HOME/.local/state/zshcfg"
LOG_FILE="$CONFIG_HOME/.local/state/zshcfg/install-$STAMP.log"
as_user bash -c 'umask 077; set -o noclobber; : > "$1"' install-log "$LOG_FILE"
printf '\n'
step 1 'Tools and plugins'
{
  if [[ "$SKIP_DEPS" != true ]]; then
    install_dependencies
  else
    info 'Dependency installation skipped; using existing tools.'
    CURRENT_STAGE='Tools and plugins (existing)'
  fi
  command -v git >/dev/null 2>&1 || fail 'Git is required.'
  command -v zsh >/dev/null 2>&1 || fail 'Zsh is required.'
} >> "$LOG_FILE" 2>&1
complete_step
step 2 'Configuration'
prepare_repo >> "$LOG_FILE" 2>&1
complete_step
step 3 'Dotfiles'
activate_config >> "$LOG_FILE" 2>&1
complete_step
step 4 'Login shell'
offer_default_shell
complete_step
finish
