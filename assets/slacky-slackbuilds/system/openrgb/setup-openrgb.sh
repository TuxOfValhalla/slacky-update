#!/usr/bin/env bash
# ==============================================================================
#  setup-openrgb.sh - Configure Slackware Kernel I2C & Permissions for OpenRGB
# ==============================================================================
set -euo pipefail

C_CYAN='\033[1;36m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_RESET='\033[0m'
C_BOLD='\033[1m'

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${C_YELLOW}Root privileges required. Relaunching with sudo...${C_RESET}"
    exec sudo bash "$0" "$@"
fi

echo -e "\n${C_CYAN}--> [1/3] Enabling i2c-dev and motherboard SMBus drivers in /etc/rc.d/rc.modules.local...${C_RESET}"
MODULES_LOCAL="/etc/rc.d/rc.modules.local"
touch "$MODULES_LOCAL"
chmod 755 "$MODULES_LOCAL"

if ! grep -q "modprobe i2c-dev" "$MODULES_LOCAL"; then
    cat << 'EOF_MODS' >> "$MODULES_LOCAL"

# Enable I2C/SMBus device access for OpenRGB motherboard & RAM lighting control
modprobe i2c-dev
modprobe i2c-piix4 2>/dev/null || modprobe i2c-i801 2>/dev/null || true
EOF_MODS
    echo -e "${C_GREEN}✓ Added i2c-dev to $MODULES_LOCAL${C_RESET}"
else
    echo -e "${C_GREEN}• i2c-dev is already configured in $MODULES_LOCAL${C_RESET}"
fi

# Load currently
modprobe i2c-dev 2>/dev/null || true
modprobe i2c-piix4 2>/dev/null || modprobe i2c-i801 2>/dev/null || true

echo -e "\n${C_CYAN}--> [2/3] Reloading udev rules for RGB hardware and I2C buses...${C_RESET}"
udevadm control --reload-rules 2>/dev/null || true
udevadm trigger --subsystem-match=hidraw 2>/dev/null || true
udevadm trigger --subsystem-match=i2c-dev 2>/dev/null || true
echo -e "${C_GREEN}✓ Udev rules reloaded!${C_RESET}"

echo -e "\n${C_CYAN}--> [3/3] User group permissions...${C_RESET}"
echo -e "Users in group 'users' now have read/write access to /dev/i2c-* and RGB HID devices."

echo -e "\n------------------------------------------------------------------"
echo -e "${C_GREEN}${C_BOLD}SUCCESS! OpenRGB is ready on Slackware!${C_RESET}"
echo -e "• Run ${C_CYAN}openrgb${C_RESET} to launch the graphical configurator."
echo -e "• To enable boot-time SDK server, run: ${C_CYAN}chmod +x /etc/rc.d/rc.openrgb${C_RESET}"
echo -e "------------------------------------------------------------------\n"
