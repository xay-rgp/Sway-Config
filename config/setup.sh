#!/usr/bin/env bash

# =============================================================================
# Arch Linux Setup Script
#
# Installs:
#   - Pacman packages
#   - Steam (interactive)
#   - Flatpak + Flathub applications
#   - yay AUR helper
#   - AUR packages
#   - ProtonUp-Qt
#   - Sway / Waybar / Wofi / Kitty / Fastfetch configs
#
# Run as a normal user:
#   chmod +x setup.sh
#   ./setup.sh
# =============================================================================

set -Eeuo pipefail

# =============================================================================
# Colors
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# =============================================================================
# Output helpers
# =============================================================================

info() {
    echo -e "${CYAN}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    exit 1
}

# =============================================================================
# Error handling
# =============================================================================

trap 'echo -e "${RED}[ERROR]${NC} Script failed on line $LINENO."; exit 1' ERR

# =============================================================================
# Configuration
# =============================================================================

REPO_URL="${REPO_URL:-https://github.com/xay-rgp/configsv3.git}"

TEMP_DIR=""
BACKUP_DIR=""
REPO_DIR=""

# =============================================================================
# Cleanup
# =============================================================================

cleanup() {
    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

trap cleanup EXIT

# =============================================================================
# Pre-flight checks
# =============================================================================

check_requirements() {
    info "Running pre-flight checks..."

    if [[ "$EUID" -eq 0 ]]; then
        error "Do not run this script as root. Run it as your regular user."
    fi

    if ! command -v bash >/dev/null 2>&1; then
        error "Bash is required."
    fi

    if ! command -v pacman >/dev/null 2>&1; then
        error "pacman not found. This script is for Arch Linux."
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        error "sudo is required."
    fi

    info "Checking sudo access..."

    sudo -v

    success "Pre-flight checks passed."
}

# =============================================================================
# Enable multilib
# =============================================================================

enable_multilib() {
    info "Checking multilib repository..."

    if grep -Eq '^[[:space:]]*\[multilib\][[:space:]]*$' /etc/pacman.conf; then
        warn "multilib is already enabled."
        return
    fi

    info "Enabling multilib..."

    sudo sed -i \
        '/^[[:space:]]*#\[multilib\][[:space:]]*$/,/^[[:space:]]*#Include = \/etc\/pacman\.d\/mirrorlist[[:space:]]*$/ {
            s/^[[:space:]]*#\[multilib\][[:space:]]*$/[multilib]/
            s/^[[:space:]]*#Include = \/etc\/pacman\.d\/mirrorlist[[:space:]]*$/Include = \/etc\/pacman.d\/mirrorlist/
        }' \
        /etc/pacman.conf

    if ! grep -Eq '^[[:space:]]*\[multilib\][[:space:]]*$' /etc/pacman.conf; then
        error "Failed to enable multilib."
    fi

    success "multilib enabled."
}

# =============================================================================
# Update system
# =============================================================================

update_system() {
    info "Synchronizing package databases and updating system..."

    sudo pacman -Syu --noconfirm

    success "System updated."
}

# =============================================================================
# Install pacman packages
# =============================================================================

install_pacman_packages() {
    local packages=(
        # Core tools
        git
        base-devel

        # Desktop / WM
        sway
        swaybg
        waybar
        wofi
        nautilus

        # Terminal
        kitty

        # Fonts
        ttf-font-awesome
        ttf-nerd-fonts-symbols
        ttf-nerd-fonts-symbols-mono

        # Apps
        discord
        fastfetch

        # Flatpak
        flatpak
    )

    info "Installing pacman packages..."

    sudo pacman -S --noconfirm --needed "${packages[@]}"

    success "Pacman packages installed."
}

# =============================================================================
# Steam
# =============================================================================

install_steam() {
    info "Installing Steam..."
    warn "Steam installation is interactive so you can choose the appropriate drivers."

    sudo pacman -S --needed steam

    success "Steam installed."
}

# =============================================================================
# Flatpak
# =============================================================================

setup_flatpak() {
    info "Setting up Flatpak..."

    if ! command -v flatpak >/dev/null 2>&1; then
        error "Flatpak was not installed correctly."
    fi

    info "Adding Flathub remote..."

    flatpak remote-add \
        --if-not-exists \
        flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo

    success "Flathub configured."

    info "Installing MissionCenter..."

    flatpak install -y flathub io.missioncenter.MissionCenter

    success "MissionCenter installed."

    info "Installing Laser..."

    flatpak install -y flathub nl.andreasknoben.Laser

    success "Laser installed."
}

# =============================================================================
# Install yay
# =============================================================================

install_yay() {
    if command -v yay >/dev/null 2>&1; then
        warn "yay is already installed."
        return
    fi

    info "Installing yay AUR helper..."

    TEMP_DIR="$(mktemp -d)"

    git clone \
        https://aur.archlinux.org/yay.git \
        "$TEMP_DIR/yay"

    (
        cd "$TEMP_DIR/yay"
        makepkg -si --noconfirm
    )

    if ! command -v yay >/dev/null 2>&1; then
        error "yay installation failed."
    fi

    success "yay installed."

    rm -rf "$TEMP_DIR"
    TEMP_DIR=""
}

# =============================================================================
# Install AUR packages
# =============================================================================

install_aur_packages() {
    local packages=(
        helium-browser-bin
        protonup-qt
        visual-studio-code-bin
    )

    info "Installing AUR packages..."

    yay -S --noconfirm --needed "${packages[@]}"

    success "AUR packages installed."
}

# =============================================================================
# ProtonUp-Qt
# =============================================================================

setup_protonup() {
    if ! command -v protonup-qt >/dev/null 2>&1; then
        warn "ProtonUp-Qt command was not found."
        warn "You can launch ProtonUp-Qt manually after setup."
        return
    fi

    info "ProtonUp-Qt is installed."

    echo
    echo "GE-Proton can be installed through ProtonUp-Qt."
    echo "Launch it from your application menu when ready."
    echo
}

# =============================================================================
# Clone configuration repository
# =============================================================================

clone_config_repository() {
    TEMP_DIR="$(mktemp -d)"
    REPO_DIR="$TEMP_DIR/configsv3"

    info "Cloning configuration repository..."

    git clone \
        "$REPO_URL" \
        "$REPO_DIR"

    if [[ ! -d "$REPO_DIR" ]]; then
        error "Configuration repository was not cloned."
    fi

    success "Configuration repository cloned."
}

# =============================================================================
# Backup existing configurations
# =============================================================================

backup_existing_configs() {
    BACKUP_DIR="$HOME/.config/arch-setup-backup-$(date +%Y%m%d-%H%M%S)"

    local files=(
        "$HOME/.config/kitty/kitty.conf"
        "$HOME/.config/sway/config"
        "$HOME/.config/sway/mywallpaper.png"
        "$HOME/.config/waybar/config.jsonc"
        "$HOME/.config/waybar/style.css"
        "$HOME/.config/wofi/style.css"
        "$HOME/.config/fastfetch/config.jsonc"
    )

    local backed_up=false

    info "Checking for existing configuration files..."

    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            mkdir -p "$BACKUP_DIR"
            cp -a "$file" "$BACKUP_DIR/"
            backed_up=true
        fi
    done

    if [[ "$backed_up" == true ]]; then
        success "Existing configuration files backed up to:"
        echo "  $BACKUP_DIR"
    else
        BACKUP_DIR=""
        info "No existing configuration files needed backing up."
    fi
}

# =============================================================================
# Deploy configuration
# =============================================================================

deploy_configs() {
    info "Deploying configuration files..."

    declare -A CONFIG_MAP=(
        ["config/kitty/kitty.conf"]="$HOME/.config/kitty"
        ["config/sway/config"]="$HOME/.config/sway"
        ["config/sway/mywallpaper.png"]="$HOME/.config/sway"
        ["config/waybar/config.jsonc"]="$HOME/.config/waybar"
        ["config/waybar/style.css"]="$HOME/.config/waybar"
        ["config/wofi/style.css"]="$HOME/.config/wofi"
        ["config/fastfetch/config.jsonc"]="$HOME/.config/fastfetch"
    )

    local src_rel
    local src
    local dest_dir
    local dest

    for src_rel in "${!CONFIG_MAP[@]}"; do

        src="$REPO_DIR/$src_rel"
        dest_dir="${CONFIG_MAP[$src_rel]}"
        dest="$dest_dir/$(basename "$src")"

        if [[ ! -f "$src" ]]; then
            warn "Source not found, skipping: $src_rel"
            continue
        fi

        mkdir -p "$dest_dir"

        # Fixed: Removed the incompatible -D flag when using a explicit target filename combined with mkdir -p
        install -m 644 "$src" "$dest"

        success "Deployed: $src_rel"
    done
}

# =============================================================================
# Verify wallpaper
# =============================================================================

verify_wallpaper() {
    local wallpaper="$HOME/.config/sway/mywallpaper.png"

    if [[ -f "$wallpaper" ]]; then
        success "Wallpaper installed successfully."

        echo
        echo "Wallpaper:"
        echo "  $wallpaper"

        echo
        echo "File information:"
        file "$wallpaper"
    else
        warn "Wallpaper was not found after deployment."
    fi
}

# =============================================================================
# Configure .bashrc
# =============================================================================

configure_bashrc() {
    local bashrc="$HOME/.bashrc"

    info "Checking ~/.bashrc..."

    touch "$bashrc"

    if grep -Eq '^[[:space:]]*fastfetch[[:space:]]*$' "$bashrc"; then
        warn "fastfetch already exists in ~/.bashrc."
        return
    fi

    {
        echo
        echo "# Launch fastfetch on terminal start"
        echo "fastfetch"
    } >> "$bashrc"

    success "fastfetch added to ~/.bashrc."
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}       Arch Linux Setup Script${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo

    info "Starting Arch Linux setup..."

    check_requirements
    enable_multilib
    update_system
    install_pacman_packages
    install_steam
    setup_flatpak
    install_yay
    install_aur_packages
    setup_protonup
    clone_config_repository
    backup_existing_configs
    deploy_configs
    verify_wallpaper
    configure_bashrc

    echo
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}          Setup complete!${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo

    echo "Next steps:"
    echo "  1. Log out and select Sway from your display manager."
    echo "  2. Or run: sway"
    echo "  3. Check that Waybar and Wofi are working."
    echo "  4. Launch ProtonUp-Qt and install GE-Proton if needed."

    if [[ -n "${BACKUP_DIR:-}" ]]; then
        echo
        echo "Previous configs were backed up to:"
        echo "  $BACKUP_DIR"
    fi

    echo

    success "Arch Linux setup finished."
}

main "$@"
