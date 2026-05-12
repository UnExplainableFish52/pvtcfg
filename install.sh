#!/usr/bin/env bash
# ============================================================
#  Loki Shell Config Installer
#  Applies Loki's ZSH configuration from the pvtcfg repository
#  https://github.com/UnExplainableFish52/pvtcfg
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
# Config
# ---------------------------
REPO_URL="https://github.com/UnExplainableFish52/pvtcfg.git"
CLONE_DIR="$HOME/Documents/pvtcfg-install-tmp"
BACKUP_DIR="$HOME/Documents/shell/old-config"
ZSH_CONFIG_DIR="$HOME/.zsh_config"
PICTURES_DIR="$HOME/Pictures"

# ---------------------------
# Helpers
# ---------------------------
info()    { echo -e "${CYAN}[*]${RESET} $1"; }
success() { echo -e "${GREEN}[✓]${RESET} $1"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $1"; }
fail()    { echo -e "${RED}[✗]${RESET} $1"; exit 1; }

# Copy a single file from the cloned repo to its destination.
# Usage: install_file <glob_pattern> <destination_path>
# The glob pattern is matched inside $CLONE_DIR.
install_file() {
    local pattern="$1"
    local dest="$2"
    local label="$3"

    # Expand the glob (take the first match)
    local src
    src=$(find "$CLONE_DIR" -maxdepth 1 -name "$pattern" -print -quit 2>/dev/null)

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
    echo -e "  ${DIM}${REPO_URL}${RESET}"
    echo ""
}

# ---------------------------
# Prerequisite checks
# ---------------------------
check_prerequisites() {
    info "Checking prerequisites..."

    if ! command -v git &>/dev/null; then
        fail "git is not installed. Please install git first and re-run this script."
    fi
    success "git found"

    if ! command -v zsh &>/dev/null; then
        warn "zsh is not installed. The config files will be copied,"
        warn "but they won't work until you install zsh."
        echo ""
    else
        success "zsh found"
    fi

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
    echo -e "  Your existing configs will be backed up to:"
    echo -e "    ${CYAN}${BACKUP_DIR}/${RESET}"
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
        ((backed_up++))
    fi

    # Back up ~/.p10k.zsh
    if [[ -f "$HOME/.p10k.zsh" ]]; then
        cp "$HOME/.p10k.zsh" "$backup_dest/p10k.zsh"
        success "~/.p10k.zsh"
        ((backed_up++))
    fi

    # Back up all files in ~/.zsh_config/
    if [[ -d "$ZSH_CONFIG_DIR" ]]; then
        local f
        for f in "$ZSH_CONFIG_DIR"/*.zsh; do
            if [[ -f "$f" ]]; then
                cp "$f" "$backup_dest/"
                success "$f"
                ((backed_up++))
            fi
        done
    fi

    if [[ $backed_up -eq 0 ]]; then
        warn "No existing config files found to back up."
    else
        success "Backed up ${backed_up} file(s)"
    fi

    echo ""
}

# ---------------------------
# Clone the repository
# ---------------------------
clone_repo() {
    info "Cloning repository to: ${CLONE_DIR}/"

    # Clean up if it exists from a previous run
    if [[ -d "$CLONE_DIR" ]]; then
        warn "Staging directory already exists. Removing it..."
        rm -rf "$CLONE_DIR"
    fi

    git clone --depth 1 "$REPO_URL" "$CLONE_DIR" 2>&1 | while read -r line; do
        echo -e "  ${DIM}${line}${RESET}"
    done

    if [[ ! -d "$CLONE_DIR" ]]; then
        fail "Clone failed. Check your internet connection and try again."
    fi

    success "Repository cloned successfully"
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
    info "Copying wallpapers to: ${PICTURES_DIR}/"

    mkdir -p "$PICTURES_DIR"

    local copied=0

    if [[ -f "$CLONE_DIR/night_temple_samurai.jpg" ]]; then
        cp "$CLONE_DIR/night_temple_samurai.jpg" "$PICTURES_DIR/night_temple_samurai.jpg"
        success "night_temple_samurai.jpg  -->  ${PICTURES_DIR}/"
        ((copied++))
    fi

    if [[ -f "$CLONE_DIR/secondwallpp.jpg" ]]; then
        cp "$CLONE_DIR/secondwallpp.jpg" "$PICTURES_DIR/twilight_landscape.jpg"
        success "secondwallpp.jpg  -->  ${PICTURES_DIR}/twilight_landscape.jpg"
        ((copied++))
    fi

    if [[ $copied -eq 0 ]]; then
        warn "No wallpaper images found in the repository."
    fi

    echo ""
}

# ---------------------------
# Cleanup
# ---------------------------
cleanup() {
    info "Cleaning up staging directory..."
    rm -rf "$CLONE_DIR"
    success "Removed ${CLONE_DIR}/"
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
    echo -e "    ${CYAN}2.${RESET} Run: ${WHITE}source ~/.zshrc${RESET}"
    echo ""
    echo -e "  ${DIM}Your old configs are safe in:${RESET}"
    echo -e "  ${CYAN}${BACKUP_DIR}/${RESET}"
    echo ""
    echo -e "  ${DIM}Wallpapers were saved to:${RESET}"
    echo -e "  ${CYAN}${PICTURES_DIR}/${RESET}"
    echo ""
    echo -e "  ${MAGENTA}${BOLD}Enjoy the shell, traveler.${RESET}"
    echo ""
}

# ============================================================
# Main
# ============================================================
main() {
    print_banner
    check_prerequisites
    ask_consent
    backup_existing
    clone_repo
    install_configs
    install_wallpapers
    cleanup
    print_done
}

main "$@"
