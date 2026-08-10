#!/bin/bash

# Arch Linux Setup Script for Sway Configuration
# This script sets up a complete Arch Linux environment with:
# - Multilib support (32-bit packages)
# - yay AUR helper
# - Helium browser from AUR
# - Flatpak with Mission Center and Laser
# - Steam and Discord
# - Sway, Waybar, Kitty, Wofi, Pavucontrol, and Fastfetch
# - Configuration file setup
# - System update

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    print_error "This script should NOT be run as root. Run it as a regular user."
    exit 1
fi

print_status "Starting Arch Linux Sway setup..."

# =============================================================================
# 1. ENABLE MULTILIB
# =============================================================================
print_status "Enabling multilib support..."

if grep -q "^\[multilib\]" /etc/pacman.conf; then
    print_warning "Multilib is already enabled"
else
    print_status "Adding multilib repository to pacman.conf..."
    sudo sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' /etc/pacman.conf
    print_success "Multilib enabled"
fi

# Update package database
print_status "Updating package database..."
sudo pacman -Sy

# =============================================================================
# 2. INSTALL YAY AUR HELPER
# =============================================================================
print_status "Installing yay AUR helper..."

if command -v yay &> /dev/null; then
    print_warning "yay is already installed"
else
    print_status "Building and installing yay from source..."
    cd /tmp
    rm -rf yay 2>/dev/null || true
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ~
    print_success "yay installed successfully"
fi

# =============================================================================
# 3. INSTALL CORE DEPENDENCIES
# =============================================================================
print_status "Installing core packages..."

CORE_PACKAGES=(
    "base-devel"
    "git"
    "wget"
    "curl"
)

sudo pacman -S --noconfirm "${CORE_PACKAGES[@]}" || print_warning "Some core packages failed to install"

# =============================================================================
# 4. INSTALL HELIUM BROWSER FROM AUR
# =============================================================================
print_status "Installing Helium browser from AUR..."

if pacman -Q helium-browser-bin &> /dev/null; then
    print_warning "Helium browser is already installed"
else
    yay -S --noconfirm helium-browser-bin || print_warning "Helium browser installation failed"
fi

# =============================================================================
# 5. INSTALL FLATPAK
# =============================================================================
print_status "Installing Flatpak..."

if command -v flatpak &> /dev/null; then
    print_warning "Flatpak is already installed"
else
    sudo pacman -S --noconfirm flatpak
    print_success "Flatpak installed"
fi

# Add Flathub repository
print_status "Adding Flathub repository..."
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || print_warning "Flathub repository already added or failed to add"

# =============================================================================
# 6. INSTALL FLATPAK APPLICATIONS
# =============================================================================
print_status "Installing Mission Center from Flathub..."
flatpak install --noninteractive flathub io.missioncenter.MissionCenter || print_warning "Mission Center installation failed"

print_status "Installing Laser from Flathub..."
flatpak install --noninteractive flathub nl.andreasknoben.Laser || print_warning "Laser installation failed"

# =============================================================================
# 7. INSTALL STEAM AND DISCORD
# =============================================================================
print_status "Installing Steam..."
sudo pacman -S steam || print_warning "Steam installation failed"

print_status "Installing Discord..."
sudo pacman -S --noconfirm discord || print_warning "Discord installation failed"

# =============================================================================
# 8. INSTALL SWAY AND MINIMAL DEPENDENCIES
# =============================================================================
print_status "Installing Sway and minimal dependencies..."

SWAY_PACKAGES=(
    "sway"              # Tiling window manager
    "waybar"            # Status bar
    "kitty"             # Terminal emulator
    "wofi"              # Application launcher
    "pavucontrol"       # Audio control GUI
    "fastfetch"         # System info display
    "xdg-desktop-portal" # Portal support
    "xdg-desktop-portal-wlr" # Wayland portal backend
    "polkit"            # Authorization framework
)

sudo pacman -S --noconfirm "${SWAY_PACKAGES[@]}" || print_warning "Some Sway packages failed to install"

print_success "Sway and dependencies installed"

# =============================================================================
# 9. UPDATE SYSTEM
# =============================================================================
print_status "Updating system packages..."

sudo pacman -Syu --noconfirm || print_warning "Some packages failed to update"
print_success "System updated"

# =============================================================================
# 10. COPY CONFIGURATION FILES TO HOME DIRECTORY
# =============================================================================
print_status "Setting up configuration files..."

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SOURCE="$SCRIPT_DIR/config"

# Create necessary directories
mkdir -p ~/.config/sway
mkdir -p ~/.config/waybar
mkdir -p ~/.config/kitty
mkdir -p ~/.local/share/backgrounds

print_status "Copying configuration files..."

# Copy Sway configuration
if [ -f "$CONFIG_SOURCE/sway/config" ]; then
    cp "$CONFIG_SOURCE/sway/config" ~/.config/sway/
    print_success "Sway config copied to ~/.config/sway/"
else
    print_warning "Sway config not found at $CONFIG_SOURCE/sway/config"
fi

# Copy Waybar configuration
if [ -f "$CONFIG_SOURCE/waybar/config" ]; then
    cp "$CONFIG_SOURCE/waybar/config" ~/.config/waybar/
    print_success "Waybar config copied to ~/.config/waybar/"
else
    print_warning "Waybar config not found at $CONFIG_SOURCE/waybar/config"
fi

if [ -f "$CONFIG_SOURCE/waybar/style.css" ]; then
    cp "$CONFIG_SOURCE/waybar/style.css" ~/.config/waybar/
    print_success "Waybar style copied to ~/.config/waybar/"
else
    print_warning "Waybar style not found at $CONFIG_SOURCE/waybar/style.css"
fi

# Copy Kitty configuration
if [ -f "$CONFIG_SOURCE/kitty/kitty.conf" ]; then
    cp "$CONFIG_SOURCE/kitty/kitty.conf" ~/.config/kitty/
    print_success "Kitty config copied to ~/.config/kitty/"
else
    print_warning "Kitty config not found at $CONFIG_SOURCE/kitty/kitty.conf"
fi

# =============================================================================
# 11. COPY WALLPAPER
# =============================================================================
print_status "Setting up wallpaper..."

# Copy wallpapers to backgrounds directory
if [ -d "$CONFIG_SOURCE/wallpapers" ]; then
    cp -r "$CONFIG_SOURCE/wallpapers"/* ~/.local/share/backgrounds/
    print_success "Wallpapers copied to ~/.local/share/backgrounds/"
else
    print_warning "Wallpapers directory not found at $CONFIG_SOURCE/wallpapers"
fi

# If there's a specific wallpaper file in the repo root or config directory
if [ -f "$CONFIG_SOURCE/wallpaper.png" ]; then
    cp "$CONFIG_SOURCE/wallpaper.png" ~/.local/share/backgrounds/
    print_success "Main wallpaper copied to ~/.local/share/backgrounds/"
elif [ -f "$SCRIPT_DIR/wallpaper.png" ]; then
    cp "$SCRIPT_DIR/wallpaper.png" ~/.local/share/backgrounds/
    print_success "Main wallpaper copied to ~/.local/share/backgrounds/"
else
    print_warning "No wallpaper found. You can manually add wallpapers to ~/.local/share/backgrounds/"
fi

# =============================================================================
# 12. SETUP COMPLETE
# =============================================================================
print_success "Setup complete!"
echo ""
print_status "Next steps:"
echo "  1. Review and customize configuration files in ~/.config/"
echo "  2. Set your preferred wallpaper in ~/.config/sway/config (wallpapers in ~/.local/share/backgrounds/)"
echo "  3. Log out and log back in, or run: exec sway"
echo ""
print_status "Configuration locations:"
echo "  - Sway: ~/.config/sway/config"
echo "  - Waybar: ~/.config/waybar/"
echo "  - Kitty: ~/.config/kitty/kitty.conf"
echo "  - Wallpapers: ~/.local/share/backgrounds/"
echo ""
print_warning "Applications installed: sway, waybar, kitty, wofi, pavucontrol, fastfetch"
echo ""
