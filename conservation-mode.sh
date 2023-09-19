#!/bin/bash

# Define the file path
conservation_file="/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode"

# Function to check if Conservation mode is running
check_conservation_mode() {
  mode=$(cat "$conservation_file")
  if [ "$mode" -eq 1 ]; then
    echo "Conservation mode is currently ON."
    toggle_conservation_mode
  else
    echo "Conservation mode is currently OFF."
    toggle_conservation_mode
  fi
}

# Function to toggle Conservation mode ON
toggle_conservation_mode() {
  read -p "Do you want to change Conservation mode (1 to enable, 0 to disable, or 2 to leave it as it is)? " choice
  if [ "$choice" -eq 1 ]; then
    echo 1 | sudo tee "$conservation_file" >/dev/null
    echo "Conservation mode has been turned ON."
  elif [ "$choice" -eq 0 ]; then
    echo 0 | sudo tee "$conservation_file" >/dev/null
    echo "Conservation mode has been turned OFF."
  else
    echo "Conservation mode remains unchanged."
  fi
}

# Main script
check_conservation_mode

