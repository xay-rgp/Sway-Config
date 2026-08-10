#!/bin/bash
# =============================================================================
# Arch Linux Setup Script
# Installs packages, AUR helper (yay), AUR packages, and deploys config files
# =============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# =============================================================================
# Pre-flight checks
# =============================================================================

if [ "$EUID" -eq 0 ]; then
    error "Do not run this script as root. Run as your regular user."
fi

if ! command -v pacman &>/dev/null; then
    error "pacman not found. This script is for Arch Linux only."
fi

info "Starting Arch Linux setup..."

# =============================================================================
# Enable multilib repository
# =============================================================================

info "Enabling multilib repository..."
if grep -q "^\[multilib\]" /etc/pacman.conf; then
    warn "multilib already enabled — skipping."
else
    sudo python3 - <<'EOF'
import re

with open("/etc/pacman.conf", "r") as f:
    content = f.read()

content = re.sub(r'#(\[multilib\])\n#(Include = /etc/pacman.d/mirrorlist)', r'\1\n\2', content)

with open("/etc/pacman.conf", "w") as f:
    f.write(content)
EOF
    success "multilib enabled."
fi

info "Syncing package databases..."
sudo pacman -Syy
success "Package databases synced."

# =============================================================================
# System update
# =============================================================================

info "Updating system..."
sudo pacman -Syu --noconfirm
success "System updated."

# =============================================================================
# Pacman packages
# =============================================================================

PACMAN_PACKAGES=(
    # Core tools
    git
    base-devel         # Required for yay / AUR builds

    # Desktop / WM
    sway
    swaybg
    waybar
    wofi
    nautilus

    # Terminal
    kitty

    # Fonts (required for waybar icons)
    ttf-font-awesome
    ttf-nerd-fonts-symbols

    # Apps
    discord
    fastfetch

    # Flatpak
    flatpak
)

info "Installing pacman packages..."
sudo pacman -S --noconfirm --needed "${PACMAN_PACKAGES[@]}"
success "Pacman packages installed."

# Install steam separately to preserve the driver selection prompt
info "Installing Steam (select your graphics drivers when prompted)..."
sudo pacman -S --needed steam
success "Steam installed."

# =============================================================================
# Flatpak setup
# =============================================================================

info "Adding Flathub remote..."
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
success "Flathub remote added."

info "Installing MissionCenter (system monitor)..."
flatpak install -y flathub io.missioncenter.MissionCenter
success "MissionCenter installed."

info "Installing Laser..."
flatpak install -y flathub nl.andreasknoben.Laser
success "Laser installed."

# =============================================================================
# Yay AUR helper
# =============================================================================

if command -v yay &>/dev/null; then
    warn "yay is already installed — skipping."
else
    info "Installing yay AUR helper..."
    YAY_BUILD_DIR="$(mktemp -d)"
    git clone https://aur.archlinux.org/yay.git "$YAY_BUILD_DIR/yay"
    (cd "$YAY_BUILD_DIR/yay" && makepkg -si --noconfirm)
    rm -rf "$YAY_BUILD_DIR"
    success "yay installed."
fi

# =============================================================================
# AUR packages
# =============================================================================

AUR_PACKAGES=(
    helium-browser-bin
    protonup
    visual-studio-code-bin
)

info "Installing AUR packages via yay..."
yay -S --noconfirm --needed "${AUR_PACKAGES[@]}"
success "AUR packages installed."

info "Running ProtonUp to install GE-Proton..."
protonup
success "GE-Proton installed."

# =============================================================================
# Clone config repo and deploy config files
# =============================================================================

REPO_URL="https://github.com/xay-rgp/Config-files.git"
REPO_DIR="$(mktemp -d)/Config-files"

info "Cloning config repo..."
git clone "$REPO_URL" "$REPO_DIR"
success "Repo cloned to $REPO_DIR."

# Map: source path (relative to repo root) → destination directory
declare -A CONFIG_MAP=(
    ["kitty/kitty.conf"]="$HOME/.config/kitty"
    ["sway/config"]="$HOME/.config/sway"
    ["sway/mywallpaper.png"]="$HOME/.config/sway"
    ["waybar/config.jsonc"]="$HOME/.config/waybar"
    ["waybar/style.css"]="$HOME/.config/waybar"
    ["wofi/style.css"]="$HOME/.config/wofi"
    ["fastfetch/config.jsonc"]="$HOME/.config/fastfetch"
)

info "Deploying config files..."
for src_rel in "${!CONFIG_MAP[@]}"; do
    src="$REPO_DIR/$src_rel"
    dest_dir="${CONFIG_MAP[$src_rel]}"

    if [ ! -f "$src" ]; then
        warn "Source not found, skipping: $src_rel"
        continue
    fi

    mkdir -p "$dest_dir"

    cp "$src" "$dest_dir/"
    success "Deployed: $src_rel → $dest_dir/"
done

# Clean up temp repo
rm -rf "$REPO_DIR"

# =============================================================================
# Add fastfetch to .bashrc
# =============================================================================

info "Adding fastfetch to ~/.bashrc..."
if grep -q "fastfetch" "$HOME/.bashrc"; then
    warn "fastfetch already in ~/.bashrc — skipping."
else
    {
        echo ""
        echo "# Launch fastfetch on terminal start"
        echo "fastfetch"
    } >> "$HOME/.bashrc"
    success "fastfetch added to ~/.bashrc."
fi

# =============================================================================
# Done
# =============================================================================

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Setup complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Next steps:"
echo "  1. Log out and select 'Sway' from your display manager, or run: sway"
echo "  2. Check waybar and wofi are working after logging in"
echo ""
