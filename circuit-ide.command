#!/bin/bash
# Circuit IDE Launcher
# Double-click this file to launch Circuit IDE

cd "$(dirname "$0")"

# Clear screen and set title
clear
echo -e "\033]0;Circuit IDE\007"

# Colors
CYAN='\033[96m'
GREEN='\033[92m'
MAGENTA='\033[95m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}║            ${BOLD}Circuit IDE Launcher${RESET}${CYAN}                 ║${RESET}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${GREEN}1)${RESET} ${BOLD}GUI${RESET}          Desktop app (Qt)        ${DIM}— Full IDE experience${RESET}"
echo -e "  ${GREEN}2)${RESET} ${BOLD}Terminal IDE${RESET}  TUI in this terminal     ${DIM}— Textual-based IDE${RESET}"
echo -e "  ${GREEN}3)${RESET} ${BOLD}CLI Agent${RESET}    Chat in this terminal    ${DIM}— Lightweight agent${RESET}"
echo ""
read -p "  Select mode [1]: " choice
choice=${choice:-1}

case "$choice" in
    1)
        echo ""
        echo -e "  ${CYAN}Launching GUI...${RESET}"
        python3.11 -m circuit_ide_gui "$@"
        ;;
    2)
        echo ""
        echo -e "  ${CYAN}Launching Terminal IDE...${RESET}"
        python3.11 -m circuit_ide "$@"
        ;;
    3)
        echo ""
        echo -e "  ${CYAN}Launching CLI Agent...${RESET}"
        python3.11 circuit_agent.py "$@"
        ;;
    *)
        echo ""
        echo -e "  ${BOLD}Invalid choice.${RESET} Launching GUI..."
        python3.11 -m circuit_ide_gui "$@"
        ;;
esac
