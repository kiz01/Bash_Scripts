#!/bin/bash
sudo apt update && sudo apt upgrade -y
sudo apt install vlc gimp blender timeshift dconf-editor rhythmbox usbguard gnome-sushi flameshot timeshift ufw telegram-desktop steghide gnome-tweaks python3-nautilus nemo-python gir1.2-nautilus-3.0 sshfs neofetch python3-tk python-is-python3 nautilus-image-converter macchanger clamav kazam testdisk finger speedtest-cli chkrootkit fail2ban rkhunter -y
sudo apt autoremove && sudo apt autoclean -y
