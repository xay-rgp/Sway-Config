#!/usr/bin/env bash
# ==============================================================================
# Arch Linux Sway Desktop Setup
# ==============================================================================
#
# Installs:
#   - Pacman packages
#   - Multilib support
#   - GPU/Vulkan packages for Steam/Proton
#   - Flatpak + Flathub applications
#   - yay
#   - AUR packages
#   - Repository configuration files
#
# Usage:
#   chmod +x setup.sh
#   ./setup.sh
#
# IMPORTANT:
#   Run this as a normal user with sudo privileges.
#   DO NOT run this script as root.
#
# ==============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

# ------------------------------------------------------------------------------
# Colors
# ------------------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
    printf '%b[INFO]%b %s\n' "${BLUE}" "${NC}" "$*" >&2
}

success() {
    printf '%b[SUCCESS]%b %s\n' "${GREEN}" "${NC}" "$*"
}

warn() {
    printf '%b[WARN]%b %s\n' "${YELLOW}" "${NC}" "$*" >&2
}

error() {
    printf '%b[ERROR]%b %s\n' "${RED}" "${NC}" "$*" >&2
}

# ------------------------------------------------------------------------------
# Error handling
# ------------------------------------------------------------------------------

on_error() {
    local exit_code=$?
    local line_number="${1:-unknown}"

    error "Command failed at line ${line_number}. Exit code: ${exit_code}."
    exit "${exit_code}"
}

trap 'on_error "${LINENO}"' ERR

# ------------------------------------------------------------------------------
# Basic checks
# ------------------------------------------------------------------------------

if [[ "$(id -u)" -eq 0 ]]; then
    error "Do not run this script as root."
    error "Run it as your normal desktop user with sudo privileges."
    exit 1
fi

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

require_sudo() {
    if ! command_exists sudo; then
        error "sudo is required but was not found."
        exit 1
    fi

    if ! sudo -v; then
        error "Your account does not appear to have working sudo privileges."
        exit 1
    fi
}

pacman_installed() {
    pacman -Q "$1" >/dev/null 2>&1
}

# ------------------------------------------------------------------------------
# User / paths
# ------------------------------------------------------------------------------

TARGET_USER="$(id -un)"
TARGET_HOME="${HOME}"

if [[ -z "${TARGET_HOME}" || "${TARGET_HOME}" == "/root" ]]; then
    error "Invalid target home directory: ${TARGET_HOME:-<empty>}"
    exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_CONFIG_DIR="${SCRIPT_DIR}/config"

info "Running as user: ${TARGET_USER}"
info "Home directory: ${TARGET_HOME}"
info "Repository config directory: ${REPO_CONFIG_DIR}"

# ------------------------------------------------------------------------------
# Package lists
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
    pciutils
)

FLATPAK_APPS=(
    "nl.andreasknoben.Laser"
    "io.missioncenter.MissionCenter"
)

AUR_PACKAGES=(
    "helium-browser-bin"
)

# ------------------------------------------------------------------------------
# Utility: install pacman packages
# ------------------------------------------------------------------------------

install_pacman_packages() {
    local packages=("$@")
    local missing=()

    for pkg in "${packages[@]}"; do
        if pacman_installed "${pkg}"; then
            info "Already installed: ${pkg}"
        else
            missing+=("${pkg}")
        fi
    done

    if ((${#missing[@]} == 0)); then
        success "All requested pacman packages are already installed."
        return 0
    fi

    info "Installing pacman packages:"
    printf '  %s\n' "${missing[@]}"

    sudo pacman -S --needed --noconfirm "${missing[@]}"

    success "Pacman package installation complete."
}

# ------------------------------------------------------------------------------
# Enable multilib
# ------------------------------------------------------------------------------

enable_multilib() {
    local pacman_conf="/etc/pacman.conf"

    info "Checking multilib configuration..."

    if grep -Eq '^[[:space:]]*\[multilib\][[:space:]]*$' "${pacman_conf}"; then
        success "multilib is already enabled."
        return 0
    fi

    if grep -Eq '^[[:space:]]*#[[:space:]]*\[multilib\][[:space:]]*$' "${pacman_conf}"; then
        info "Enabling existing multilib section..."

        sudo sed -i \
            -e '/^[[:space:]]*#[[:space:]]*\[multilib\][[:space:]]*$/s/^[[:space:]]*#//' \
            -e '/^[[:space:]]*#[[:space:]]*Include[[:space:]]*=[[:space:]]*\/etc\/pacman\.d\/mirrorlist[[:space:]]*$/s/^[[:space:]]*#//' \
            "${pacman_conf}"

        success "multilib section enabled."
    else
        info "No multilib section found. Adding one..."

        sudo tee -a "${pacman_conf}" >/dev/null <<'EOF'

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF

        success "multilib section added."
    fi

    info "Refreshing package databases and performing full system upgrade..."
    sudo pacman -Syu --noconfirm
}

# ------------------------------------------------------------------------------
# GPU detection
# ------------------------------------------------------------------------------

detect_gpu() {
    local gpu_line=""

    if ! command_exists lspci; then
        warn "lspci is unavailable; installing pciutils..."
        sudo pacman -S --needed --noconfirm pciutils
    fi

    gpu_line="$(
        lspci -nnk 2>/dev/null |
            grep -Ei 'VGA compatible controller|3D controller|Display controller' |
            head -n1 ||
            true
    )"

    if [[ -z "${gpu_line}" ]]; then
        printf '%s\n' "unknown"
        return 0
    fi

    info "Detected GPU: ${gpu_line}"

    if [[ "${gpu_line}" =~ [Nn][Vv][Ii][Dd][Ii][Aa] ]]; then
        printf '%s\n' "nvidia"
    elif [[ "${gpu_line}" =~ [Aa][Mm][Dd]|[Aa][Tt][Ii] ]]; then
        printf '%s\n' "amd"
    elif [[ "${gpu_line}" =~ [Ii][Nn][Tt][Ee][Ll] ]]; then
        printf '%s\n' "intel"
    else
        printf '%s\n' "unknown"
    fi
}

# ------------------------------------------------------------------------------
# Steam / Vulkan packages
# ------------------------------------------------------------------------------

install_steam_vulkan_packages() {
    local vendor
    local packages=()

    vendor="$(detect_gpu)"

    info "GPU vendor detected: ${vendor}"

    case "${vendor}" in
        amd)
            packages=(
                vulkan-radeon
                lib32-vulkan-radeon
                lib32-mesa
            )
            ;;

        intel)
            packages=(
                vulkan-intel
                lib32-vulkan-intel
                lib32-mesa
            )
            ;;

        nvidia)
            packages=(
                nvidia-utils
                lib32-nvidia-utils
            )
            ;;

        *)
            packages=(
                mesa
                lib32-mesa
            )
            ;;
    esac

    printf '\n'
    printf 'Install Vulkan / 32-bit Steam compatibility packages? [Y/n]: '

    local answer
    read -r answer
    answer="${answer:-Y}"

    if [[ "${answer}" =~ ^[Yy]$ ]]; then
        info "Installing:"
        printf '  %s\n' "${packages[@]}"

        sudo pacman -S --needed --noconfirm "${packages[@]}"

        success "Vulkan / Steam compatibility packages installed."
    else
        info "Skipping Vulkan / Steam compatibility packages."
    fi
}

# ------------------------------------------------------------------------------
# Flatpak
# ------------------------------------------------------------------------------

flatpak_app_installed() {
    local app_id="$1"

    if ! command_exists flatpak; then
        return 1
    fi

    flatpak list \
        --app \
        --columns=application \
        --user 2>/dev/null |
        grep -Fxq "${app_id}" && return 0

    flatpak list \
        --app \
        --columns=application \
        --system 2>/dev/null |
        grep -Fxq "${app_id}"
}

setup_flatpak() {
    if ! command_exists flatpak; then
        info "Installing Flatpak..."
        sudo pacman -S --needed --noconfirm flatpak
    fi

    info "Checking Flathub..."

    if sudo flatpak remotes --system 2>/dev/null |
        awk '$1 == "flathub" { found=1 } END { exit !found }'; then

        info "System Flathub remote already exists."
    else
        info "Adding system Flathub remote..."

        sudo flatpak remote-add \
            --if-not-exists \
            --system \
            flathub \
            https://dl.flathub.org/repo/flathub.flatpakrepo

        success "Flathub configured."
    fi

    for app in "${FLATPAK_APPS[@]}"; do
        if flatpak_app_installed "${app}"; then
            info "Flatpak already installed: ${app}"
            continue
        fi

        info "Installing Flatpak: ${app}"

        sudo flatpak install \
            --system \
            --noninteractive \
            --assumeyes \
            flathub \
            "${app}"

        success "Installed Flatpak: ${app}"
    done
}

# ------------------------------------------------------------------------------
# yay
# ------------------------------------------------------------------------------

install_yay() {
    if command_exists yay; then
        success "yay is already installed."
        return 0
    fi

    info "Installing dependencies required to build yay..."

    sudo pacman -S \
        --needed \
        --noconfirm \
        base-devel \
        git

    local build_dir
    build_dir="$(mktemp -d)"

    cleanup_yay_build() {
        rm -rf "${build_dir}"
    }

    trap cleanup_yay_build EXIT

    info "Cloning yay AUR repository..."

    git clone \
        https://aur.archlinux.org/yay.git \
        "${build_dir}/yay"

    cd "${build_dir}/yay"

    info "Building yay as ${TARGET_USER}..."

    makepkg -si --noconfirm

    if command_exists yay; then
        success "yay installed successfully."
    else
        error "yay installation completed but yay was not found in PATH."
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# AUR packages
# ------------------------------------------------------------------------------

install_aur_packages() {
    if ! command_exists yay; then
        error "yay is not available."
        return 1
    fi

    for pkg in "${AUR_PACKAGES[@]}"; do
        if pacman_installed "${pkg}"; then
            info "AUR package already installed: ${pkg}"
            continue
        fi

        info "Installing AUR package: ${pkg}"

        yay -S \
            --noconfirm \
            --needed \
            --answerdiff=None \
            --answerclean=None \
            "${pkg}"

        success "Installed AUR package: ${pkg}"
    done
}

# ------------------------------------------------------------------------------
# Configuration installation
# ------------------------------------------------------------------------------

timestamp() {
    date '+%Y-%m-%d-%H%M%S'
}

backup_path() {
    printf '%s.backup-%s\n' "$1" "$(timestamp)"
}

install_entry() {
    local source="$1"
    local destination="$2"

    if [[ -e "${destination}" || -L "${destination}" ]]; then
        local backup
        backup="$(backup_path "${destination}")"

        info "Backing up ${destination}"
        mv -- "${destination}" "${backup}"

        success "Backup created: ${backup}"
    fi

    if [[ -d "${source}" ]]; then
        mkdir -p "${destination}"

        if command_exists rsync; then
            rsync -a \
                --no-owner \
                --no-group \
                "${source}/" \
                "${destination}/"
        else
            cp -a "${source}/." "${destination}/"
        fi
    else
        mkdir -p "$(dirname "${destination}")"
        cp -a "${source}" "${destination}"
    fi

    chown -R "${TARGET_USER}:${TARGET_USER}" "${destination}" 2>/dev/null || true

    if [[ -d "${destination}" ]]; then
        find "${destination}" \
            -type f \
            -name '*.sh' \
            -exec chmod +x {} +
    fi
}

install_configs() {
    if [[ ! -d "${REPO_CONFIG_DIR}" ]]; then
        warn "No config directory found:"
        warn "  ${REPO_CONFIG_DIR}"
        return 0
    fi

    info "Installing repository configuration..."

    shopt -s nullglob dotglob

    local entry
    local name
    local destination

    for entry in "${REPO_CONFIG_DIR}"/*; do
        name="$(basename "${entry}")"

        case "${name}" in
            sway|waybar|wofi|kitty|fastfetch)
                destination="${TARGET_HOME}/.config/${name}"
                ;;

            wallpapers|backgrounds)
                destination="${TARGET_HOME}/.local/share/backgrounds"
                ;;

            fonts)
                destination="${TARGET_HOME}/.local/share/fonts"
                ;;

            *)
                destination="${TARGET_HOME}/.config/${name}"
                ;;
        esac

        info "Installing ${name} -> ${destination}"

        install_entry "${entry}" "${destination}"

        success "Installed ${name}"
    done

    shopt -u nullglob dotglob
}

# ------------------------------------------------------------------------------
# Verification
# ------------------------------------------------------------------------------

final_verification() {
    printf '\n'
    info "Running final verification..."

    local failures=0

    # Pacman packages
    for pkg in "${PACMAN_PACKAGES[@]}"; do
        if pacman_installed "${pkg}"; then
            success "Pacman: ${pkg}"
        else
            warn "Missing pacman package: ${pkg}"
            failures=$((failures + 1))
        fi
    done

    # Flatpaks
    for app in "${FLATPAK_APPS[@]}"; do
        if flatpak_app_installed "${app}"; then
            success "Flatpak: ${app}"
        else
            warn "Missing Flatpak: ${app}"
            failures=$((failures + 1))
        fi
    done

    # AUR
    for pkg in "${AUR_PACKAGES[@]}"; do
        if pacman_installed "${pkg}"; then
            success "AUR: ${pkg}"
        else
            warn "Missing AUR package: ${pkg}"
            failures=$((failures + 1))
        fi
    done

    # yay
    if command_exists yay; then
        success "yay is available."
    else
        warn "yay is not available."
        failures=$((failures + 1))
    fi

    # Important configs
    local config_files=(
        "${TARGET_HOME}/.config/sway/config"
        "${TARGET_HOME}/.config/waybar/config.jsonc"
        "${TARGET_HOME}/.config/kitty/kitty.conf"
        "${TARGET_HOME}/.config/fastfetch/config.jsonc"
    )

    for config in "${config_files[@]}"; do
        if [[ -f "${config}" ]]; then
            success "Config: ${config}"
        else
            warn "Missing config: ${config}"
        fi
    done

    printf '\n'

    if ((failures == 0)); then
        success "All package verification checks passed."
    else
        warn "${failures} package/component verification check(s) failed."
    fi
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

main() {
    info "Starting Arch Linux Sway desktop setup..."

    require_sudo

    # Enable multilib and perform a full upgrade.
    enable_multilib

    # Install core packages.
    install_pacman_packages "${PACMAN_PACKAGES[@]}"

    # Optional Steam/Proton graphics support.
    install_steam_vulkan_packages

    # Flatpak + Flathub apps.
    setup_flatpak

    # AUR helper.
    install_yay

    # AUR packages.
    install_aur_packages

    # Repository configs.
    install_configs

    # Verification.
    final_verification

    printf '\n'
    success "Setup complete!"

    printf '\n'
    printf '%bNext steps:%b\n' "${BLUE}" "${NC}"
    printf '  - Review: %s/.config/\n' "${TARGET_HOME}"
    printf '  - Reboot if you installed/changed GPU drivers.\n'
    printf '  - Start Sway from a TTY with: sway\n'
    printf '\n'
}

main "$@"
