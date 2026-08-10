# Sway-Config

Automated Arch Linux setup script for Sway tiling window manager with essential applications and configurations.

---

## What It Does

### System Setup
- ✅ Enables multilib (32-bit support)
- ✅ Installs and configures yay (AUR helper)
- ✅ Updates system packages

### Applications
- ✅ **Sway** - Tiling window manager
- ✅ **Waybar** - Status bar
- ✅ **Kitty** - Terminal emulator
- ✅ **Wofi** - Application launcher
- ✅ **Pavucontrol** - Audio control
- ✅ **Fastfetch** - System info

### Additional Tools
- ✅ Steam (with driver selection)
- ✅ Discord
- ✅ Helium Browser (AUR)
- ✅ Flatpak + Mission Center + Laser

### Configuration
- ✅ Copies all config files to `~/.config/`
- ✅ Deploys wallpapers to `~/.local/share/backgrounds/`
- ✅ Creates necessary directories

---

## Quick Start

```bash
git clone https://github.com/xay-rgp/Sway-Config.git
cd Sway-Config
chmod +x setup.sh
./setup.sh
```

**Requirements:**
- Regular user (NOT root)
- Fresh Arch Linux installation
- Internet connection
- 10GB+ free space

---

## After Installation

1. Review configs in `~/.config/`
2. Set wallpaper in `~/.config/sway/config`
3. Log out and back in, or run: `exec sway`

---

## Config Locations

- **Sway:** `~/.config/sway/config`
- **Waybar:** `~/.config/waybar/`
- **Kitty:** `~/.config/kitty/kitty.conf`
- **Wallpapers:** `~/.local/share/backgrounds/`

---

## Notes

⚠️ Do NOT run as root  
⚠️ Steam installation will prompt for GPU drivers  
⚠️ Full installation takes 30-60 minutes

---

**Happy Sway'ing!** 🎯
