#!/usr/bin/env bash
# ============================================================
#  Loki Shell Config Installer
#  Applies Loki's ZSH configuration from bundled files.
#  https://github.com/UnExplainableFish52/pvtcfg
#
#  USAGE:
#    chmod +x install.sh && ./install.sh
#
#  The installer expects the following files to be present
#  in the SAME directory as this script:
#    .p10k.zsh
#    .zshrc.bak.*
#    aliases.bak.*
#    env.bak.*
#    functions.bak.*
#    keybinds.bak.*
#    local.bak.*
#    options.bak.*
#    night_temple_samurai.jpg   (optional wallpaper)
#    secondwallpp.jpg           (optional wallpaper)
# ============================================================

set -euo pipefail

# ---------------------------
# Colors & formatting
# ---------------------------
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
WHITE='\033[1;37m'

# ---------------------------
# Resolve script directory
# ---------------------------
# All bundled config files live next to this script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------
# Config
# ---------------------------
BACKUP_DIR="$HOME/.config/loki-shell-backup"
ZSH_CONFIG_DIR="$HOME/.zsh_config"
PICTURES_DIR="$HOME/Pictures"

# ---------------------------
# Helpers
# ---------------------------
info()    { echo -e "${CYAN}[*]${RESET} $1"; }
success() { echo -e "${GREEN}[✓]${RESET} $1"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $1"; }
fail()    { echo -e "${RED}[✗]${RESET} $1"; exit 1; }

# Resolve a single file from a glob pattern in SCRIPT_DIR.
# Returns the first match or empty string.
resolve_file() {
    local pattern="$1"
    local match
    match=$(find "$SCRIPT_DIR" -maxdepth 1 -name "$pattern" -print -quit 2>/dev/null)
    echo "$match"
}

# Copy a bundled file to a destination.
# Usage: install_file <glob_pattern> <destination_path> <label>
install_file() {
    local pattern="$1"
    local dest="$2"
    local label="$3"

    local src
    src="$(resolve_file "$pattern")"

    if [[ -z "$src" ]]; then
        warn "Source not found for pattern: ${pattern} -- skipping ${label}"
        return 1
    fi

    cp -f "$src" "$dest"
    success "${label}  -->  ${dest}"
}

# ---------------------------
# Banner
# ---------------------------
print_banner() {
    echo ""
    echo -e "${MAGENTA}${BOLD}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║                                               ║"
    echo "  ║        Loki  Shell  Config  Installer         ║"
    echo "  ║                                               ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${RESET}"
    echo -e "  ${DIM}ZSH configuration by Loki${RESET}"
    echo -e "  ${DIM}https://github.com/UnExplainableFish52/pvtcfg${RESET}"
    echo ""
}

# ---------------------------
# Refuse to run as root
# ---------------------------
refuse_root() {
    if [[ "$EUID" -eq 0 ]]; then
        fail "Do NOT run this script as root or with sudo.\n  Run it as your normal user: ${WHITE}./install.sh${RESET}\n  The script will ask for sudo only when installing packages."
    fi
}

# ---------------------------
# Detect package manager
# ---------------------------
detect_pkg_manager() {
    if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
    elif command -v pacman &>/dev/null; then
        PKG_MANAGER="pacman"
    elif command -v zypper &>/dev/null; then
        PKG_MANAGER="zypper"
    elif command -v apk &>/dev/null; then
        PKG_MANAGER="apk"
    else
        PKG_MANAGER="unknown"
    fi
}

# ---------------------------
# Install dependencies
# ---------------------------
install_dependencies() {
    info "Checking and installing dependencies..."
    echo ""

    detect_pkg_manager

    local packages_to_install=()

    # Check for zsh
    if ! command -v zsh &>/dev/null; then
        packages_to_install+=("zsh")
    else
        success "zsh is already installed"
    fi

    # Check for git
    if ! command -v git &>/dev/null; then
        packages_to_install+=("git")
    else
        success "git is already installed"
    fi

    # Check for curl
    if ! command -v curl &>/dev/null; then
        packages_to_install+=("curl")
    else
        success "curl is already installed"
    fi

    # Install missing packages
    if [[ ${#packages_to_install[@]} -gt 0 ]]; then
        info "Installing: ${packages_to_install[*]}"

        case "$PKG_MANAGER" in
            apt)
                sudo apt-get update -qq
                sudo apt-get install -y -qq "${packages_to_install[@]}"
                ;;
            dnf)
                sudo dnf install -y -q "${packages_to_install[@]}"
                ;;
            pacman)
                sudo pacman -Sy --noconfirm --needed "${packages_to_install[@]}"
                ;;
            zypper)
                sudo zypper install -y -n "${packages_to_install[@]}"
                ;;
            apk)
                sudo apk add --no-cache "${packages_to_install[@]}"
                ;;
            *)
                warn "Unknown package manager. Please install manually: ${packages_to_install[*]}"
                ;;
        esac

        # Verify installation
        for pkg in "${packages_to_install[@]}"; do
            if command -v "$pkg" &>/dev/null; then
                success "${pkg} installed successfully"
            else
                warn "${pkg} may not have installed correctly"
            fi
        done
    fi

    echo ""

    # Install Oh My Zsh if not present
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        info "Installing Oh My Zsh..."
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        success "Oh My Zsh installed"
    else
        success "Oh My Zsh is already installed"
    fi

    # Install Powerlevel10k theme if not present
    local p10k_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    if [[ ! -d "$p10k_dir" ]]; then
        info "Installing Powerlevel10k theme..."
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir" 2>&1 | while read -r line; do
            echo -e "  ${DIM}${line}${RESET}"
        done
        success "Powerlevel10k installed"
    else
        success "Powerlevel10k is already installed"
    fi

    # Install zsh-autosuggestions if not present
    local autosug_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
    if [[ ! -d "$autosug_dir" ]]; then
        info "Installing zsh-autosuggestions plugin..."
        git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git "$autosug_dir" 2>&1 | while read -r line; do
            echo -e "  ${DIM}${line}${RESET}"
        done
        success "zsh-autosuggestions installed"
    else
        success "zsh-autosuggestions is already installed"
    fi

    # Install zsh-syntax-highlighting if not present
    local synhl_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"
    if [[ ! -d "$synhl_dir" ]]; then
        info "Installing zsh-syntax-highlighting plugin..."
        git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$synhl_dir" 2>&1 | while read -r line; do
            echo -e "  ${DIM}${line}${RESET}"
        done
        success "zsh-syntax-highlighting installed"
    else
        success "zsh-syntax-highlighting is already installed"
    fi

    echo ""
}

# ---------------------------
# Verify bundled files exist
# ---------------------------
verify_bundled_files() {
    info "Verifying bundled config files in: ${SCRIPT_DIR}/"
    echo ""

    local missing=0

    # Check for the essential files
    local required_patterns=(
        ".zshrc.bak.*"
        ".p10k.zsh"
        "aliases.bak.*"
        "env.bak.*"
        "functions.bak.*"
        "keybinds.bak.*"
        "local.bak.*"
        "options.bak.*"
    )

    for pattern in "${required_patterns[@]}"; do
        local found
        found="$(resolve_file "$pattern")"
        if [[ -n "$found" ]]; then
            success "Found: $(basename "$found")"
        else
            warn "Missing: ${pattern}"
            ((missing++))
        fi
    done

    echo ""

    if [[ $missing -gt 0 ]]; then
        fail "Missing ${missing} required config file(s). Ensure all files are in: ${SCRIPT_DIR}/"
    fi

    success "All required config files are present"
    echo ""
}

# ---------------------------
# Consent prompt
# ---------------------------
ask_consent() {
    echo -e "${YELLOW}${BOLD}  ⚠  WARNING${RESET}"
    echo ""
    echo -e "  This script will ${RED}${BOLD}OVERWRITE${RESET} your current shell configuration:"
    echo ""
    echo -e "    ${WHITE}~/.zshrc${RESET}"
    echo -e "    ${WHITE}~/.p10k.zsh${RESET}"
    echo -e "    ${WHITE}~/.zsh_config/aliases.zsh${RESET}"
    echo -e "    ${WHITE}~/.zsh_config/env.zsh${RESET}"
    echo -e "    ${WHITE}~/.zsh_config/functions.zsh${RESET}"
    echo -e "    ${WHITE}~/.zsh_config/keybinds.zsh${RESET}"
    echo -e "    ${WHITE}~/.zsh_config/local.zsh${RESET}"
    echo -e "    ${WHITE}~/.zsh_config/options.zsh${RESET}"
    echo ""
    echo -e "  Your existing configs will be safely backed up to:"
    echo -e "    ${CYAN}${BACKUP_DIR}/<timestamp>/${RESET}"
    echo ""
    echo -e "  ${DIM}Make sure you understand what you are doing.${RESET}"
    echo ""

    echo -ne "  ${BOLD}Do you want to proceed? (y/N):${RESET} "
    read -r answer

    if [[ ! "$answer" =~ ^[yY]$ ]]; then
        echo ""
        info "Installation cancelled. Nothing was changed."
        echo -e "  ${DIM}See you next time!${RESET}"
        echo ""
        exit 0
    fi

    echo ""
}

# ---------------------------
# Backup existing configs
# ---------------------------
backup_existing() {
    local timestamp
    timestamp="$(date +%Y%m%d-%H%M%S)"
    local backup_dest="${BACKUP_DIR}/${timestamp}"

    info "Backing up existing configs to: ${backup_dest}/"

    mkdir -p "$backup_dest"

    local backed_up=0

    # Back up ~/.zshrc
    if [[ -f "$HOME/.zshrc" ]]; then
        cp "$HOME/.zshrc" "$backup_dest/zshrc"
        success "~/.zshrc"
        ((backed_up++)) || true
    fi

    # Back up ~/.p10k.zsh
    if [[ -f "$HOME/.p10k.zsh" ]]; then
        cp "$HOME/.p10k.zsh" "$backup_dest/p10k.zsh"
        success "~/.p10k.zsh"
        ((backed_up++)) || true
    fi

    # Back up all files in ~/.zsh_config/
    if [[ -d "$ZSH_CONFIG_DIR" ]]; then
        mkdir -p "$backup_dest/zsh_config"
        local f
        for f in "$ZSH_CONFIG_DIR"/*.zsh; do
            if [[ -f "$f" ]]; then
                cp "$f" "$backup_dest/zsh_config/"
                success "$f"
                ((backed_up++)) || true
            fi
        done
    fi

    if [[ $backed_up -eq 0 ]]; then
        warn "No existing config files found to back up (fresh install)."
    else
        success "Backed up ${backed_up} file(s) securely"
    fi

    echo ""
}

# ---------------------------
# Install config files
# ---------------------------
install_configs() {
    info "Installing Loki's configuration files..."
    echo ""

    # Ensure ~/.zsh_config/ exists
    mkdir -p "$ZSH_CONFIG_DIR"

    # --- Main ZSH config ---
    install_file ".zshrc.bak.*"       "$HOME/.zshrc"                    ".zshrc"

    # --- Powerlevel10k config ---
    install_file ".p10k.zsh"          "$HOME/.p10k.zsh"                 ".p10k.zsh"

    # --- Modular configs ---
    install_file "aliases.bak.*"      "$ZSH_CONFIG_DIR/aliases.zsh"     "aliases.zsh"
    install_file "env.bak.*"          "$ZSH_CONFIG_DIR/env.zsh"         "env.zsh"
    install_file "functions.bak.*"    "$ZSH_CONFIG_DIR/functions.zsh"   "functions.zsh"
    install_file "keybinds.bak.*"     "$ZSH_CONFIG_DIR/keybinds.zsh"    "keybinds.zsh"
    install_file "local.bak.*"        "$ZSH_CONFIG_DIR/local.zsh"       "local.zsh"
    install_file "options.bak.*"      "$ZSH_CONFIG_DIR/options.zsh"     "options.zsh"

    echo ""
}

# ---------------------------
# Install wallpapers
# ---------------------------
install_wallpapers() {
    local has_wallpapers=false

    # Check if any wallpapers exist before printing the header
    if [[ -f "$SCRIPT_DIR/night_temple_samurai.jpg" ]] || [[ -f "$SCRIPT_DIR/secondwallpp.jpg" ]]; then
        has_wallpapers=true
    fi

    if [[ "$has_wallpapers" == true ]]; then
        info "Copying wallpapers to: ${PICTURES_DIR}/"
        mkdir -p "$PICTURES_DIR"

        if [[ -f "$SCRIPT_DIR/night_temple_samurai.jpg" ]]; then
            cp "$SCRIPT_DIR/night_temple_samurai.jpg" "$PICTURES_DIR/night_temple_samurai.jpg"
            success "night_temple_samurai.jpg  -->  ${PICTURES_DIR}/"
        fi

        if [[ -f "$SCRIPT_DIR/secondwallpp.jpg" ]]; then
            cp "$SCRIPT_DIR/secondwallpp.jpg" "$PICTURES_DIR/twilight_landscape.jpg"
            success "secondwallpp.jpg  -->  ${PICTURES_DIR}/twilight_landscape.jpg"
        fi

        echo ""
    fi
}

# ---------------------------
# Set ZSH as default shell
# ---------------------------
set_default_shell() {
    local zsh_path
    zsh_path="$(command -v zsh 2>/dev/null)"

    if [[ -z "$zsh_path" ]]; then
        warn "zsh not found. Skipping default shell change."
        return
    fi

    # Check if zsh is already the default
    if [[ "$SHELL" == "$zsh_path" ]]; then
        success "zsh is already your default shell"
        echo ""
        return
    fi

    info "Changing your default shell to zsh..."
    echo -e "  ${DIM}You may be prompted for your password.${RESET}"

    # Ensure zsh is listed in /etc/shells
    if ! grep -qx "$zsh_path" /etc/shells 2>/dev/null; then
        echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
    fi

    if chsh -s "$zsh_path"; then
        success "Default shell changed to zsh"
    else
        warn "Could not change default shell. Run manually: chsh -s ${zsh_path}"
    fi

    echo ""
}

# ---------------------------
# Farewell
# ---------------------------
print_done() {
    echo -e "${GREEN}${BOLD}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║                                               ║"
    echo "  ║       Installation complete!                  ║"
    echo "  ║                                               ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${RESET}"
    echo -e "  To apply the new config, either:"
    echo -e "    ${CYAN}1.${RESET} Restart your terminal"
    echo -e "    ${CYAN}2.${RESET} Run: ${WHITE}exec zsh${RESET}"
    echo ""
    echo -e "  ${DIM}Your old configs are safe in:${RESET}"
    echo -e "  ${CYAN}${BACKUP_DIR}/${RESET}"
    echo ""

    if [[ -d "$PICTURES_DIR" ]]; then
        local has_wp=false
        [[ -f "$PICTURES_DIR/night_temple_samurai.jpg" ]] && has_wp=true
        [[ -f "$PICTURES_DIR/twilight_landscape.jpg" ]] && has_wp=true
        if [[ "$has_wp" == true ]]; then
            echo -e "  ${DIM}Wallpapers saved to:${RESET}"
            echo -e "  ${CYAN}${PICTURES_DIR}/${RESET}"
            echo ""
        fi
    fi

    echo -e "  ${MAGENTA}${BOLD}Enjoy the shell, traveler.${RESET}"
    echo ""
}

# ============================================================
# Main
# ============================================================
main() {
    print_banner
    refuse_root
    verify_bundled_files
    install_dependencies
    ask_consent
    backup_existing
    install_configs
    install_wallpapers
    set_default_shell
    print_done
}

main "$@"
