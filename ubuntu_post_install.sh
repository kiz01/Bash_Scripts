#!/bin/bash
sudo apt-get update; sudo apt-get upgrade -y
sudo apt-get autoremove -y
sudo apt-get autoclean -y
sudo apt install vlc gimp blender timeshift kazam dconf-editor rhythmbox flameshot timeshift ufw telegram-desktop steghide gnome-tweaks neofetch python3-tk python-is-python3 nautilus-image-converter macchanger chkrootkit rkhunter -y

sudo chkrootkit -y
sudo rkhunter -s --sk
