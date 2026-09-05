#!/usr/bin/env bash
#
# Arch Linux setup script for Sway-Config dotfiles
#
# Expects to be run from the root of the repo, with dotfiles laid out like:
#   ./config/sway/config
#   ./config/sway/mywallpaper.png
#   ./config/waybar/config.jsonc
#   ./config/waybar/style.css
#   ./config/wofi/style.css
#   ./config/kitty/kitty.conf
#   ./config/fastfetch/config.jsonc
#
# Usage:
#   chmod +x setup.sh
#   ./setup.sh
#
# NOTE: Everything runs with --noconfirm EXCEPT the `steam` install itself,
# which is left interactive so you can pick the correct vulkan driver
# provider (nvidia/amd/intel) when pacman prompts for it.
#
# yay is installed as an AUR helper for your own future use, even though
# nothing in this script currently needs the AUR (librewolf is in the
# official 'extra' repo).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"

log()  { echo -e "\e[1;32m[+]\e[0m $*"; }
warn() { echo -e "\e[1;33m[!]\e[0m $*"; }
err()  { echo -e "\e[1;31m[-]\e[0m $*" >&2; }

if [[ $EUID -eq 0 ]]; then
    err "Don't run this script as root directly — run it as your normal user."
    err "It will call sudo itself whenever it needs elevated privileges."
    exit 1
fi

# Keep sudo alive for the whole script
sudo -v
( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT

### ---------------------------------------------------------------------
### 1. Enable multilib
### ---------------------------------------------------------------------
log "Enabling multilib repository..."
if grep -q "^\[multilib\]" /etc/pacman.conf; then
    log "multilib already enabled, skipping."
else
    sudo cp /etc/pacman.conf /etc/pacman.conf.bak
    sudo sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' /etc/pacman.conf
fi

log "Syncing package databases..."
sudo pacman -Syu --noconfirm

### ---------------------------------------------------------------------
### 2. Install official repo packages (noconfirm) - everything except steam
### ---------------------------------------------------------------------
PACMAN_PACKAGES=(
    sway
    discord
    flatpak
    swaybg
    librewolf
    wofi
    waybar
    kitty
    nautilus
    fastfetch
    base-devel
    git
    go
)

log "Installing pacman packages: ${PACMAN_PACKAGES[*]}"
sudo pacman -S --needed --noconfirm "${PACMAN_PACKAGES[@]}"

### ---------------------------------------------------------------------
### 3. Install steam interactively so the vulkan driver provider prompt
###    stays selectable
### ---------------------------------------------------------------------
log "Installing steam (interactive — pick the correct vulkan driver / lib32 provider when prompted)..."
sudo pacman -S --needed steam

### ---------------------------------------------------------------------
### 4. Install yay (AUR helper)
### ---------------------------------------------------------------------
if ! command -v yay >/dev/null 2>&1; then
    log "Installing yay AUR helper..."
    BUILD_DIR="$(mktemp -d)"
    git clone --depth 1 https://aur.archlinux.org/yay.git "$BUILD_DIR/yay"
    (cd "$BUILD_DIR/yay" && makepkg -si --noconfirm)
    rm -rf "$BUILD_DIR"
else
    log "yay already installed, skipping."
fi

### ---------------------------------------------------------------------
### 5. Flatpak + Mission Center
### ---------------------------------------------------------------------
log "Setting up flathub remote..."
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

log "Installing Mission Center from Flathub..."
sudo flatpak install -y flathub io.missioncenter.MissionCenter

### ---------------------------------------------------------------------
### 6. Deploy dotfiles
### ---------------------------------------------------------------------
log "Deploying config files..."

mkdir -p "$HOME/.config/sway" \
         "$HOME/.config/waybar" \
         "$HOME/.config/wofi" \
         "$HOME/.config/kitty" \
         "$HOME/.config/fastfetch"

copy_config() {
    local src="$1" dst="$2"
    if [[ -f "$src" ]]; then
        cp -f "$src" "$dst"
        log "  -> $dst"
    else
        warn "  Missing source file: $src (skipped)"
    fi
}

copy_config "$CONFIG_DIR/sway/config"              "$HOME/.config/sway/config"
copy_config "$CONFIG_DIR/sway/mywallpaper.png"     "$HOME/.config/sway/mywallpaper.png"
copy_config "$CONFIG_DIR/waybar/config.jsonc"      "$HOME/.config/waybar/config.jsonc"
copy_config "$CONFIG_DIR/waybar/style.css"         "$HOME/.config/waybar/style.css"
copy_config "$CONFIG_DIR/wofi/style.css"           "$HOME/.config/wofi/style.css"
copy_config "$CONFIG_DIR/kitty/kitty.conf"         "$HOME/.config/kitty/kitty.conf"
copy_config "$CONFIG_DIR/fastfetch/config.jsonc"   "$HOME/.config/fastfetch/config.jsonc"

### ---------------------------------------------------------------------
### 7. Add fastfetch to .bashrc
### ---------------------------------------------------------------------
log "Adding fastfetch to ~/.bashrc..."
if ! grep -qxF 'fastfetch' "$HOME/.bashrc" 2>/dev/null; then
    echo -e '\n# Run fastfetch on shell start\nfastfetch' >> "$HOME/.bashrc"
    log "  Added."
else
    log "  Already present, skipping."
fi

log "Done! Log out and start sway (or reboot) to load the new config."
warn "Remember: this script did NOT touch your GPU/vulkan driver packages beyond the steam prompt — install lib32-nvidia-utils / lib32-vulkan-radeon / lib32-vulkan-intel yourself if the prompt didn't cover it."
