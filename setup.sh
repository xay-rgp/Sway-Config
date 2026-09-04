#!/usr/bin/env bash
# ==============================================================================
# Arch Linux Sway Desktop Setup
# ==============================================================================
#
# Installs the required packages, Flatpak applications, yay, AUR packages,
# and deploys repository configuration files for a Sway desktop environment.
#
# Usage:
#   ./setup.sh
#
# Important:
#  - Run this as a normal (non-root) user with sudo privileges.
#  - The script will call sudo for system-level operations only.
#  - AUR builds (makepkg) are always run as the normal user.
#
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# ------------------------------------------------------------------------------
# Colors and logging helpers
# ------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()    { printf "%b [INFO]    %b\n"    "${BLUE}" "${NC} $*"; }
success() { printf "%b [SUCCESS] %b\n"    "${GREEN}" "${NC} $*"; }
warn()    { printf "%b [WARN]    %b\n"    "${YELLOW}" "${NC} $*"; }
error()   { printf "%b [ERROR]   %b\n"    "${RED}" "${NC} $*"; }

# ------------------------------------------------------------------------------
# Error handling
# ------------------------------------------------------------------------------
on_error() {
    local exit_code=$?
    error "Command failed at line $1. Exit code: ${exit_code}"
    exit "${exit_code}"
}
trap 'on_error $LINENO' ERR

# ------------------------------------------------------------------------------
# Determine target user and paths
# ------------------------------------------------------------------------------
# Script must be run as a normal user (not root). If the user invoked this via
# sudo, SUDO_USER may be set — but we prefer to run as the original desktop user.
if [[ "$(id -u)" -eq 0 ]]; then
    error "This script must NOT be run as root. Run it as the normal desktop user (with sudo available)."
    exit 1
fi

# Determine the target desktop user (do not hard-code)
TARGET_USER="${SUDO_USER:-${USER:-$(id -un)}}"
TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
if [[ -z "${TARGET_HOME}" ]]; then
    error "Could not determine home directory for user '${TARGET_USER}'."
    exit 1
fi

# Prevent accidental root config installs
if [[ "${TARGET_HOME}" == "/root" ]]; then
    error "Refusing to install desktop configuration into /root. Run as a normal user."
    exit 1
fi

# Directory of this script (assumed repository root or where this file lives)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_CONFIG_DIR="${SCRIPT_DIR}/config"

info "Running as user: ${TARGET_USER}"
info "User home: ${TARGET_HOME}"
info "Repository config dir: ${REPO_CONFIG_DIR}"

# ------------------------------------------------------------------------------
# Package lists and variables (edit here if you want to adjust packages)
# ------------------------------------------------------------------------------
PACMAN_PACKAGES=(
    steam
    discord
    flatpak
    pavucontrol
    kitty
    waybar
    fastfetch
    sway
    wofi
)

# GPU driver package candidate lists (documented and easy to edit)
DRIVERS_AMD=( "mesa" "xf86-video-amdgpu" )         # AMD: mesa + optional xf86 driver for X11
DRIVERS_INTEL=( "mesa" "xf86-video-intel" )       # Intel: mesa + optional xf86 driver for older hardware
DRIVERS_NVIDIA=( "nvidia" "nvidia-utils" )        # Proprietary NVIDIA - DO NOT install unless you choose it

# Flatpak apps to install from Flathub
FLATPAK_APPS=(
    "nl.andreasknoben.Laser"            # Laser
    "io.missioncenter.MissionCenter"    # Mission Center
)

# AUR packages to install via yay
AUR_PACKAGES=(
    "helium-browser-bin"
)

# ------------------------------------------------------------------------------
# Helpers: checks
# ------------------------------------------------------------------------------
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

require_sudo() {
    if ! command_exists sudo ; then
        error "sudo is required but not installed. Install sudo and ensure your user has sudo privileges."
        exit 1
    fi
}

# Check whether a pacman package is installed
pacman_installed() {
    local pkg="$1"
    pacman -Qi "$pkg" &>/dev/null
}

# Check whether a flatpak app is installed for the user
flatpak_app_installed() {
    local app_id="$1"
    if command_exists flatpak; then
        # Check both user and system installs
        flatpak list --app --columns=application | grep -xFq "$app_id" &>/dev/null
    else
        return 1
    fi
}

# ------------------------------------------------------------------------------
# 1. ENABLE MULTILIB
# ------------------------------------------------------------------------------
enable_multilib() {
    info "Checking if multilib is enabled in /etc/pacman.conf..."

    # Check for an uncommented [multilib] header
    if grep -E '^[[:space:]]*\[multilib\]' /etc/pacman.conf >/dev/null 2>&1; then
        success "multilib repository already present and enabled."
        return 0
    fi

    # If there exists a commented multilib block, uncomment it.
    if grep -E '^[[:space:]]*#\s*\[multilib\]' /etc/pacman.conf >/dev/null 2>&1; then
        info "Uncommenting the multilib block in /etc/pacman.conf..."
        # This sed command removes leading '#' from the [multilib] line and the following Include line.
        # It uses a range from the commented header to the commented Include line.
        sudo sed -n '1,$p' /etc/pacman.conf >/tmp/pacman.conf.before
        sudo sed -i '/^#\s*\[multilib\]/,/^#\s*Include = \/etc\/pacman.d\/mirrorlist/ s/^#\s*//' /etc/pacman.conf
        success "multilib block uncommented."
        info "Refreshing pacman DB (required after changing repositories)..."
        sudo pacman -Sy --noconfirm
        return 0
    fi

    # If there is no multilib block at all, append a safe multilib block at the end.
    info "No multilib block found, appending a standard multilib block to /etc/pacman.conf..."
    # We append the block in one operation to avoid duplicate entries on repeated runs.
    sudo bash -c 'cat >> /etc/pacman.conf <<EOF

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF'
    success "multilib block appended."
    info "Refreshing pacman DB (required after adding repositories)..."
    sudo pacman -Sy --noconfirm
}

# ------------------------------------------------------------------------------
# 2. INSTALL PACMAN PACKAGES (with options for GPU drivers)
# ------------------------------------------------------------------------------
detect_gpu() {
    # Try to detect GPU vendor via lspci. If pciutils isn't installed, try to install it first.
    local vendor=""
    if ! command_exists lspci; then
        warn "lspci (pciutils) not found; installing pciutils to detect GPU (requires sudo)..."
        sudo pacman -S --noconfirm pciutils || warn "Failed to install pciutils; GPU detection may be limited."
    fi

    if command_exists lspci; then
        # Look for VGA/3D controller lines and try to identify vendor
        local gpu_line
        gpu_line="$(lspci -nnk | grep -E 'VGA|3D' | head -n1 || true)"
        if [[ -n "$gpu_line" ]]; then
            case "$gpu_line" in
                *NVIDIA*|*Nvidia*|*nvidia*)
                    vendor="nvidia";;
                *AMD*|*Advanced Micro Devices*|*ATI*)
                    vendor="amd";;
                *Intel*|*Integrated Graphics*)
                    vendor="intel";;
                *)
                    vendor="unknown";;
            esac
            info "Detected GPU line: ${gpu_line}"
        else
            vendor="unknown"
            warn "Could not find a VGA/3D controller line with lspci."
        fi
    else
        vendor="unknown"
        warn "Unable to run lspci for GPU detection."
    fi

    echo "${vendor}"
}

choose_and_install_drivers() {
    local vendor
    vendor="$(detect_gpu)"
    info "GPU vendor guess: ${vendor}"

    # Present options for user to explicitly choose drivers. We never silently install drivers.
    echo ""
    info "Driver installation choices:"
    echo "  1) No driver packages (skip)"
    echo "  2) Install AMD recommended packages: ${DRIVERS_AMD[*]}"
    echo "  3) Install Intel recommended packages: ${DRIVERS_INTEL[*]}"
    echo "  4) Install NVIDIA (proprietary) recommended packages: ${DRIVERS_NVIDIA[*]}"
    echo ""
    warn "If you're unsure, choose option 1 and install drivers manually later. Do NOT install conflicting drivers."
    printf "Your choice [default: 1]: "
    read -r choice || choice=1

    local selected=()
    case "${choice}" in
        2)
            selected=("${DRIVERS_AMD[@]}");;
        3)
            selected=("${DRIVERS_INTEL[@]}");;
        4)
            selected=("${DRIVERS_NVIDIA[@]}");;
        *)
            info "Skipping GPU driver installation."
            return 0;;
    esac

    # Check for conflicts: e.g., don't install nvidia and mesa-only choices that would conflict.
    if [[ " ${selected[*]} " == *"nvidia"* ]] && pacman_installed "xf86-video-amdgpu" ; then
        warn "NVIDIA selection may conflict with already installed AMD drivers. Confirm to continue."
        read -rp "Proceed with installing NVIDIA driver packages? [y/N]: " yn
        case "${yn}" in [Yy]* ) ;; * ) info "Driver installation cancelled."; return 0;; esac
    fi

    # Install the chosen driver packages via pacman
    info "Installing chosen driver packages: ${selected[*]}"
    sudo pacman -S --noconfirm --needed "${selected[@]}"
    success "GPU driver candidate packages installation attempted."
}

install_pacman_packages() {
    info "Installing required pacman packages..."
    local to_install=()
    for pkg in "${PACMAN_PACKAGES[@]}"; do
        if pacman_installed "$pkg"; then
            info "Skipping already installed package: $pkg"
        else
            to_install+=("$pkg")
        fi
    done

    if [[ "${#to_install[@]}" -gt 0 ]]; then
        info "Packages to install: ${to_install[*]}"
        sudo pacman -S --noconfirm --needed "${to_install[@]}"
        success "Pacman packages installed (or already present)."
    else
        success "All pacman packages already installed."
    fi

    # Offer GPU driver installation after core packages are in place
    choose_and_install_drivers
}

# ------------------------------------------------------------------------------
# 3. FLATPAK: install and configure Flathub + install apps
# ------------------------------------------------------------------------------
setup_flatpak_and_apps() {
    if ! command_exists flatpak; then
        warn "flatpak was expected but is not available. Installing via pacman..."
        sudo pacman -S --noconfirm flatpak
    fi

    # Prefer a system Flathub remote so all users can access it. If system remote is blocked
    # or you prefer a user remote, change --system to --user or remove it.
    info "Ensuring Flathub remote exists (system remote)..."
    if sudo flatpak remote-info --system flathub &>/dev/null; then
        info "Flathub system remote already configured."
    else
        # Try to add system Flathub remote; if it fails, fall back to user remote.
        if sudo flatpak remote-add --if-not-exists --system flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null; then
            success "Flathub added as a system remote."
        else
            warn "Failed to add Flathub as a system remote; attempting to add as a user remote instead..."
            if flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; then
                success "Flathub added as a user remote."
            else
                warn "Could not add Flathub remote automatically. You may need to add it manually."
            fi
        fi
    fi

    # Install requested Flatpak applications (non-interactive)
    for app in "${FLATPAK_APPS[@]}"; do
        if flatpak_app_installed "$app"; then
            info "Skipping Flatpak app already installed: $app"
        else
            info "Installing Flatpak app: $app (from flathub)"
            # Use --noninteractive to avoid prompts
            if sudo flatpak install --noninteractive --assumeyes --from "https://dl.flathub.org/repo/appstream/${app}.desktop" 2>/dev/null; then
                success "Installed $app via flatpak (system)."
            else
                # Try user install as fallback
                if flatpak install --noninteractive flathub "$app" &>/dev/null; then
                    success "Installed $app via flatpak (user)."
                else
                    warn "Failed to install $app via flatpak automatically."
                fi
            fi
        fi
    done
}

# ------------------------------------------------------------------------------
# 4. INSTALL YAY (AUR helper)
# ------------------------------------------------------------------------------
install_yay() {
    if command_exists yay; then
        success "yay already available; skipping build."
        return 0
    fi

    info "Preparing to build and install 'yay' from AUR..."

    # Ensure base-devel and git are installed for makepkg
    local required=(base-devel git)
    local to_install=()
    for pkg in "${required[@]}"; do
        if ! pacman_installed "$pkg"; then
            to_install+=("$pkg")
        fi
    done
    if [[ "${#to_install[@]}" -gt 0 ]]; then
        info "Installing dependencies for building AUR packages: ${to_install[*]}"
        sudo pacman -S --noconfirm --needed "${to_install[@]}"
    fi

    # Build yay in a temporary location in /tmp and as the normal user.
    # makepkg MUST NOT be run as root — running as root can create packages owned by root
    # and it's a security risk. We're running this script as the normal user so this
    # makepkg will also run as the normal user.
    local build_dir
    build_dir="$(mktemp -d -t "${TARGET_USER}-yay-build-XXXX")"
    info "Cloning yay AUR repo into: ${build_dir}"
    git clone https://aur.archlinux.org/yay.git "${build_dir}/yay"
    pushd "${build_dir}/yay" >/dev/null
    info "Building yay package with makepkg (as ${TARGET_USER})..."
    # --noconfirm to pacman calls triggered by makepkg; this still uses the user's environment
    makepkg -si --noconfirm
    popd >/dev/null

    # Clean up
    info "Cleaning up build directory: ${build_dir}"
    rm -rf "${build_dir}"
    if command_exists yay; then
        success "yay installed successfully."
    else
        warn "yay build finished but 'yay' was not found on PATH."
    fi
}

# ------------------------------------------------------------------------------
# 5. INSTALL AUR PACKAGES (uses yay)
# ------------------------------------------------------------------------------
install_aur_packages() {
    if ! command_exists yay; then
        warn "yay is not available; skipping AUR package installation."
        return 1
    fi

    for pkg in "${AUR_PACKAGES[@]}"; do
        if pacman_installed "$pkg"; then
            info "AUR package already installed via pacman: $pkg"
        else
            info "Installing AUR package via yay: $pkg"
            # --noconfirm makes yay non-interactive. --answerdiff=None prevents diff prompts.
            yay -S --noconfirm --nodiff --nocleanmenu "$pkg" || warn "yay failed to install $pkg"
        fi
    done
}

# ------------------------------------------------------------------------------
# 6. Install configuration files from repo -> user's home
# ------------------------------------------------------------------------------
timestamp() {
    date +"%Y-%m-%d-%H%M%S"
}

backup_path() {
    local dst="$1"
    local ts
    ts="$(timestamp)"
    echo "${dst}.backup-${ts}"
}

# Copy repository config tree into user's home with backups and proper permissions.
install_configs() {
    info "Installing configuration files from repository into ${TARGET_USER} home."

    if [[ ! -d "${REPO_CONFIG_DIR}" ]]; then
        warn "No config/ directory found in repository (${REPO_CONFIG_DIR}). Skipping config installation."
        return 0
    fi

    # Determine safe copy command (prefer rsync for better behavior; fallback to cp -a)
    local copy_cmd
    if command_exists rsync; then
        copy_cmd="rsync -aH --no-owner --no-group"
    else
        copy_cmd="cp -a"
    fi

    # We will iterate top-level entries in config/ and map them to ~/.config or other locations.
    # Common mappings:
    #  - config/sway -> ~/.config/sway
    #  - config/waybar -> ~/.config/waybar
    #  - config/wofi -> ~/.config/wofi
    #  - config/kitty -> ~/.config/kitty
    #  - config/fastfetch -> ~/.config/fastfetch
    #  - other directories or files: place under ~/.local/share or ~/.config as appropriate.

    # For each entry, compute destination and copy with backup if destination exists.
    shopt -s dotglob nullglob
    for entry in "${REPO_CONFIG_DIR}"/*; do
        name="$(basename "${entry}")"
        case "${name}" in
            sway|waybar|wofi|kitty|fastfetch)
                dest_dir="${TARGET_HOME}/.config/${name}"
                ;;
            wallpapers|backgrounds)
                dest_dir="${TARGET_HOME}/.local/share/backgrounds"
                ;;
            fonts)
                dest_dir="${TARGET_HOME}/.local/share/fonts"
                ;;
            *)
                # Fallback: place unknown top-level directories in ~/.config/<name>
                dest_dir="${TARGET_HOME}/.config/${name}"
                ;;
        esac

        info "Preparing to install '${name}' -> ${dest_dir}"

        # Create parent directory if needed
        mkdir -p "$(dirname "${dest_dir}")"
        # Backup existing destination if it exists (file or directory)
        if [[ -e "${dest_dir}" || -L "${dest_dir}" ]]; then
            local bkp
            bkp="$(backup_path "${dest_dir}")"
            info "Backing up existing path '${dest_dir}' to '${bkp}'"
            mv "${dest_dir}" "${bkp}"
            success "Backup created: ${bkp}"
        fi

        # Ensure destination parent exists
        mkdir -p "${dest_dir}"

        # Copy content. Use rsync or cp depending on availability.
        if [[ "${copy_cmd}" == rsync* ]]; then
            # rsync: preserve executability; avoid changing ownership (--no-owner --no-group)
            rsync -aH --no-owner --no-group "${entry}/" "${dest_dir}/"
        else
            # cp -a: attempts to preserve modes and timestamps
            cp -a "${entry}/." "${dest_dir}/"
        fi

        # Ensure correct ownership for the target user (if script run as another user this will adjust)
        # We'll adjust ownership only if we can run chown (no sudo required if we're the target user).
        if id -u "${TARGET_USER}" >/dev/null 2>&1; then
            chown -R "${TARGET_USER}":"${TARGET_USER}" "${dest_dir}" || warn "Failed to chown ${dest_dir} to ${TARGET_USER}"
        fi

        # Make sure any scripts inside dest_dir are executable if they were executable in repo.
        # cp/rsync preserve executable bit, but confirm scripts have reasonable permissions.
        find "${dest_dir}" -type f -name "*.sh" -exec chmod +x {} + 2>/dev/null || true

        success "Installed '${name}' to ${dest_dir}"
    done
    shopt -u dotglob nullglob
}

# ------------------------------------------------------------------------------
# 7. Basic final verification and summary
# ------------------------------------------------------------------------------
final_verification() {
    info "Running final verification checks..."

    local missing_pkgs=()
    for pkg in "${PACMAN_PACKAGES[@]}"; do
        if ! pacman_installed "$pkg"; then
            missing_pkgs+=("$pkg")
        fi
    done

    local missing_flatpaks=()
    for app in "${FLATPAK_APPS[@]}"; do
        if ! flatpak_app_installed "$app"; then
            missing_flatpaks+=("$app")
        fi
    done

    local missing_aur=()
    for pkg in "${AUR_PACKAGES[@]}"; do
        if ! pacman_installed "$pkg"; then
            missing_aur+=("$pkg")
        fi
    done

    success "Verification summary:"
    if [[ "${#missing_pkgs[@]}" -eq 0 ]]; then
        success "  All required pacman packages appear installed."
    else
        warn "  Missing pacman packages: ${missing_pkgs[*]}"
    fi

    if [[ "${#missing_flatpaks[@]}" -eq 0 ]]; then
        success "  All Flatpak applications appear installed."
    else
        warn "  Missing Flatpak apps: ${missing_flatpaks[*]}"
    fi

    if [[ "${#missing_aur[@]}" -eq 0 ]]; then
        success "  All AUR packages appear installed."
    else
        warn "  Missing AUR packages: ${missing_aur[*]}"
    fi

    # Check some key configuration files
    local config_checks=(
        "${TARGET_HOME}/.config/sway/config"
        "${TARGET_HOME}/.config/waybar/config.jsonc"
        "${TARGET_HOME}/.config/kitty/kitty.conf"
        "${TARGET_HOME}/.config/fastfetch/config.jsonc"
    )
    for cf in "${config_checks[@]}"; do
        if [[ -e "${cf}" ]]; then
            success "  Config present: ${cf}"
        else
            warn "  Config missing: ${cf}"
        fi
    done

    # Check yay
    if command_exists yay; then
        success "  yay is available in PATH."
    else
        warn "  yay not found in PATH."
    fi

    # Check helium
    if pacman_installed "helium-browser-bin"; then
        success "  helium-browser-bin is installed."
    else
        warn "  helium-browser-bin not installed."
    fi
}

# ------------------------------------------------------------------------------
# Main flow
# ------------------------------------------------------------------------------
main() {
    info "Starting Arch Linux Sway setup..."

    require_sudo

    # 1) Enable multilib (idempotent)
    enable_multilib

    # 2) Update core DB (safe: already done after enabling multilib)
    info "Doing a full system refresh (pacman -Syu) to ensure packages are available (this may take time)..."
    sudo pacman -Syu --noconfirm

    # 3) Install pacman packages (skips already-installed ones)
    install_pacman_packages

    # 4) Setup Flatpak and install apps
    setup_flatpak_and_apps

    # 5) Install yay (AUR helper)
    install_yay

    # 6) Install AUR packages using yay (helium)
    install_aur_packages

    # 7) Install repository configuration into user's home (with backups)
    install_configs

    # 8) Final verification
    final_verification

    success "Setup complete. Next steps:"
    echo "  - Review configs in ${TARGET_HOME}/.config/"
    echo "  - If you changed GPU drivers, reboot to load new drivers."
    echo "  - Start sway with: exec sway (from a TTY/login manager) or log out and choose Sway session."
    echo ""
}

main "$@"
