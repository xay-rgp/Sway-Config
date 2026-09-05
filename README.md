# Sway-Config

Sway (Wayland) dotfiles for Arch Linux, with a setup script to provision a fresh install.




## Usage

```bash
chmod +x setup.sh
./setup.sh
```

Run as a normal user (not root) — it calls `sudo` internally when needed.

## What the script does

- Enables multilib and syncs pacman
- Installs: discord, flatpak, swaybg, librewolf, wofi, waybar, kitty, nautilus, fastfetch, base-devel, git, go
- Installs steam separately and interactively, so you can pick the correct vulkan driver
- Installs yay (AUR helper)
- Installs Mission Center via Flatpak
- Copies everything from `config/` into `~/.config/`
- Adds `fastfetch` to `~/.bashrc`
