#!/bin/bash

# Path to the conservation mode control file
conservation_file="/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode"

# Define colors
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
RESET="\e[0m"

# Check current conservation mode status
check_conservation_mode() {
    if [[ ! -f "$conservation_file" ]]; then
        echo -e "${RED}Error:${RESET} Conservation mode file not found at $conservation_file"
        exit 1
    fi

    mode=$(cat "$conservation_file")
    if [[ "$mode" -eq 1 ]]; then
        echo -e "${GREEN}Conservation mode is currently ON.${RESET}"
    else
        echo -e "${RED}Conservation mode is currently OFF.${RESET}"
    fi
    toggle_conservation_mode
}

# Toggle conservation mode
toggle_conservation_mode() {
    while true; do
        echo
        echo -e "${BLUE}Change conservation mode?${RESET}"
        echo -e "  ${GREEN}on${RESET}   = Enable"
        echo -e "  ${RED}off${RESET}  = Disable"
        echo -e "  ${YELLOW}skip${RESET} = Leave as-is"
        echo
        read -r -p "Enter choice: " choice

        case "$choice" in
            on|ON|On)
                echo 1 | sudo tee "$conservation_file" >/dev/null
                echo -e "${GREEN}Conservation mode has been turned ON.${RESET}"
                break
                ;;
            off|OFF|Off)
                echo 0 | sudo tee "$conservation_file" >/dev/null
                echo -e "${RED}Conservation mode has been turned OFF.${RESET}"
                break
                ;;
            skip|SKIP|Skip)
                echo -e "${YELLOW}Conservation mode remains unchanged.${RESET}"
                break
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter on, off, or skip.${RESET}"
                ;;
        esac
    done
}

# Main
check_conservation_mode

