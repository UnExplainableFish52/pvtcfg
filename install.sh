#!/usr/bin/env bash
# Install a permanent, Git-tracked Zsh configuration, with or without sudo.
# Download this file alone, or run it from a clone. The working directory is irrelevant.
set -euo pipefail

fail() { printf 'zshcfg: %s\n' "$*" >&2; exit 1; }

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

info() { printf 'zshcfg: %s\n' "$*"; }
confirm() {
  local answer='n'
  read -r -p "$1 [y/N] " answer || true
  [[ "$answer" == [yY] ]]
}
as_admin() {
  if (( EUID == 0 )); then "$@"; else sudo "$@"; fi
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
    --help)
      printf 'Usage: bash install.sh [--yes] [--skip-deps] [--no-chsh]\n'
      printf 'Install target: %s (%s)\n' "$INSTALL_USER" "$CONFIG_HOME"
      printf 'ZSHCFG_HOME selects an alternate home directory for isolated testing.\n'
      printf 'ZSHCFG_REMOTE / ZSHCFG_BRANCH select a fork or branch for standalone bootstrap.\n'
      exit 0 ;;
    *) fail "Unknown option: $option" ;;
  esac
done

# Config activation is reversible. Dependencies and the checkout are kept on failure.
rollback() {
  local result=$? i
  if [[ "$ACTIVATING" == true ]]; then
    printf 'zshcfg: Activation failed; restoring replaced configuration files.\n' >&2
    set +e
    for (( i=${#INSTALLED[@]}-1; i>=0; i-- )); do
      as_user rm -f -- "${INSTALLED[i]}"
      if [[ -n "${BACKUPS[i]}" ]]; then as_user mv -- "${BACKUPS[i]}" "${INSTALLED[i]}"; fi
    done
  fi
  exit "$result"
}
trap rollback EXIT

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
  (( ${#wanted[@]} )) || return 0

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
    [[ -z "$source_status" ]] || fail 'Commit your checkout changes before installing so the permanent clone includes them.'
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
  [[ "$NO_CHSH" != true ]] || return 0
  # Alternate-home installations are for fixtures/staging, not account changes.
  [[ "$CONFIG_HOME" == "$INSTALL_HOME" ]] || return 0
  local zsh_path
  zsh_path="$(command -v zsh)"
  [[ "$INSTALL_SHELL" != "$zsh_path" ]] || return 0
  if confirm 'Make Zsh your default login shell?'; then
    if ! grep -qxF "$zsh_path" /etc/shells; then
      info "Zsh must be listed in /etc/shells first: $zsh_path"
      return 0
    fi
    as_user chsh -s "$zsh_path" || info "Could not change login shell. You can run: chsh -s $zsh_path"
  fi
}

info "Installing for: $INSTALL_USER ($CONFIG_HOME)"
info "Permanent checkout: $REPO"
info 'Existing config files will get adjacent dated backups; wallpapers are ignored.'
if [[ "$ASSUME_YES" != true ]]; then
  confirm 'Install the tools and link this configuration?' || { info 'Installation cancelled.'; exit 0; }
fi
if [[ "$SKIP_DEPS" != true ]]; then
  install_dependencies
else
  info 'Dependency installation skipped; existing dependencies are your responsibility.'
fi
command -v git >/dev/null 2>&1 || fail 'Git is required.'
command -v zsh >/dev/null 2>&1 || fail 'Zsh is required.'
prepare_repo
activate_config
offer_default_shell
info 'Installation complete. Open a new terminal or run: exec zsh'
info 'nano uses line numbers; cat uses bat; ls uses eza when available.'
