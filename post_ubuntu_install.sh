#!/bin/bash
set -euo pipefail

# ------------------------------
# Logging
# ------------------------------
exec > >(tee -i ~/post_install.log)
exec 2>&1
echo "=== Starting post-install script ==="

# ------------------------------
# Update & Upgrade
# ------------------------------
echo "Updating system..."
sudo apt update -y && sudo apt upgrade -y

# ------------------------------
# Install apt packages (stable/system/security)
# ------------------------------
echo "Installing core packages..."
apt_packages=(
  timeshift
  dconf-editor
  rhythmbox
  usbguard
  flameshot
  ufw
  gnome-tweaks
  python3-nautilus
  nemo-python
  gir1.2-nautilus-3.0
  nautilus-image-converter
  sshfs
  neofetch
  clamav
  kazam
  chkrootkit
  fail2ban
  rkhunter
)
sudo apt install -y "${apt_packages[@]}"

# ------------------------------
# Ensure Snap is installed
# ------------------------------
if ! command -v snap >/dev/null 2>&1; then
    echo "Snap not found. Installing snapd..."
    sudo apt install -y snapd
fi

# ------------------------------
# Snap apps (latest security updates)
# ------------------------------
echo "Installing Snap apps..."
sudo snap install vlc
sudo snap install telegram-desktop

# ------------------------------
# Ensure Flatpak is installed
# ------------------------------
if ! command -v flatpak >/dev/null 2>&1; then
    echo "Flatpak not found. Installing flatpak..."
    sudo apt install -y flatpak
fi

# ------------------------------
# Flatpak apps (newer versions, better GNOME integration)
# ------------------------------
echo "Installing Flatpak apps..."
if ! flatpak remote-list | grep -q flathub; then
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi

flatpak install -y flathub org.gimp.GIMP
flatpak install -y flathub org.blender.Blender

# ------------------------------
# Enable Security & Updates
# ------------------------------
echo "Configuring security tools..."
sudo ufw enable
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
sudo rkhunter --update
sudo freshclam  # update ClamAV

# ------------------------------
# Cleanup
# ------------------------------
echo "Cleaning up..."
sudo apt autoremove -y && sudo apt autoclean -y

# ------------------------------
# Final System Info
# ------------------------------
echo "=== Post-install complete ==="
neofetch

