#!/usr/bin/env bash
# ==============================================================================
#  install-unreal-engine.sh - Dynamic Unreal Engine 5.x Installer & SpaceMouse
#  Maintained by TuxOfValhalla <agnar1984@gmail.com>
# ==============================================================================
set -euo pipefail

C_CYAN='\033[1;36m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[1;31m'
C_RESET='\033[0m'
C_BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${C_CYAN}"
cat << 'EOF_BANNER'
  .==============================================================.
  |  UNREAL ENGINE 5 (UNIVERSAL) INSTALLER & SPACEMOUSE BRIDGE   |
  |  Supports UE 5.4, 5.5, 5.6, 5.7, 5.8+ with CUDA/OpenCL & HID |
  *==============================================================*
EOF_BANNER
echo -e "${C_RESET}"

# --- [ 1. LOCATE ARCHIVE & AUTO-DETECT ENGINE VERSION ] ---
ZIP_FILE=""
SEARCH_PATHS=(
    "$SCRIPT_DIR"
    "${HOME:-/root}/Games"
    "${HOME:-/root}/Downloads"
    "${HOME:-/root}/Downloads/UnrealEngine"
    "/tmp"
)

# Search for any Unreal Engine 5.x zip archive
for spath in "${SEARCH_PATHS[@]}"; do
    [ -d "$spath" ] || continue
    match=$(find "$spath" -maxdepth 2 \( -iname "*Unreal*Engine*5*.zip" -o -iname "Linux_Unreal_Engine_5*.zip" \) 2>/dev/null | head -n1 || true)
    if [ -n "$match" ] && [ -f "$match" ]; then
        ZIP_FILE="$match"
        break
    fi
done

DETECTED_VERSION=""
if [ -n "$ZIP_FILE" ]; then
    ZIP_NAME=$(basename "$ZIP_FILE")
    if [[ "$ZIP_NAME" =~ (5\.[0-9]+(\.[0-9]+)?) ]]; then
        DETECTED_VERSION="${BASH_REMATCH[1]}"
    fi
fi

VERSION="${UNREAL_VERSION:-${DETECTED_VERSION:-5.8.0}}"
MAJOR_MINOR=$(echo "$VERSION" | cut -d. -f1-2)
DEFAULT_INSTALL_DIR="/opt/unreal-engine-${MAJOR_MINOR}"

# --- [ 2. CLI ARGUMENT PARSING ] ---
TARGET_DIR="${UNREAL_INSTALL_DIR:-}"
AUTO_CONFIRM=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install-dir|-d)
            TARGET_DIR="$2"
            shift 2
            ;;
        --version|-v)
            VERSION="$2"
            MAJOR_MINOR=$(echo "$VERSION" | cut -d. -f1-2)
            DEFAULT_INSTALL_DIR="/opt/unreal-engine-${MAJOR_MINOR}"
            shift 2
            ;;
        --yes|-y|--batch)
            AUTO_CONFIRM=1
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Usage: $0 [--install-dir <path>] [--version <5.x>] [-y]" >&2
            exit 1
            ;;
    esac
done

echo -e "Target Engine Release: ${C_GREEN}Unreal Engine ${VERSION}${C_RESET} (Branch: ${MAJOR_MINOR})"

# --- [ 3. INTERACTIVE DESTINATION SELECTION (METHOD C) ] ---
if [ -z "$TARGET_DIR" ]; then
    if [ "$AUTO_CONFIRM" -eq 1 ]; then
        TARGET_DIR="$DEFAULT_INSTALL_DIR"
    else
        echo -e "\n${C_BOLD}Select installation destination for Unreal Engine ${MAJOR_MINOR}:${C_RESET}"
        echo -e "  [1] Standard FHS system directory: ${C_CYAN}${DEFAULT_INSTALL_DIR}${C_RESET} (Default)"
        echo -e "  [2] Custom location (e.g. secondary NVMe mount, e.g. /opt/games/UnrealEngine-${MAJOR_MINOR})"
        echo ""
        read -r -p "Enter choice [1/2] (Default: 1): " CHOICE
        case "${CHOICE:-1}" in
            1)
                TARGET_DIR="$DEFAULT_INSTALL_DIR"
                ;;
            2)
                read -r -p "Enter custom destination directory: " USER_DIR
                if [ -z "$USER_DIR" ]; then
                    echo -e "${C_YELLOW}No directory provided. Defaulting to ${DEFAULT_INSTALL_DIR}${C_RESET}"
                    TARGET_DIR="$DEFAULT_INSTALL_DIR"
                else
                    TARGET_DIR="$USER_DIR"
                fi
                ;;
            *)
                echo -e "${C_YELLOW}Invalid choice. Defaulting to ${DEFAULT_INSTALL_DIR}${C_RESET}"
                TARGET_DIR="$DEFAULT_INSTALL_DIR"
                ;;
        esac
    fi
fi

TARGET_DIR=$(realpath -m "$TARGET_DIR")
echo -e "\nTarget installation directory: ${C_GREEN}${TARGET_DIR}${C_RESET}"

# Check available disk space (require at least 70GB)
TARGET_PARENT=$(dirname "$TARGET_DIR")
[ -d "$TARGET_PARENT" ] || mkdir -p "$TARGET_PARENT" 2>/dev/null || true
AVAIL_KB=$(df -kP "$TARGET_PARENT" 2>/dev/null | tail -1 | awk '{print $4}')
if [ -n "$AVAIL_KB" ] && [ "$AVAIL_KB" -lt 70000000 ]; then
    echo -e "${C_YELLOW}Warning: Less than 70GB of free space detected on target mount."
    echo -e "Unreal Engine 5 requires ~30GB for the archive and ~75GB extracted.${C_RESET}"
fi

# Validate archive availability if binaries not present
if [ -z "$ZIP_FILE" ] && [ ! -d "$TARGET_DIR/Engine/Binaries/Linux" ]; then
    echo -e "\n${C_RED}Error: Unreal Engine 5 archive not found.${C_RESET}"
    echo -e "Please download ${C_CYAN}Linux_Unreal_Engine_${VERSION}.*.zip${C_RESET} (or your preferred 5.x version) from:"
    echo -e "  --> ${C_BOLD}https://www.unrealengine.com/linux${C_RESET}"
    echo -e "Place the downloaded ZIP file into ${C_CYAN}$SCRIPT_DIR${C_RESET} or ${C_CYAN}${HOME}/Downloads/${C_RESET}, and run this script again."
    exit 1
fi

# --- [ 4. EXTRACTION / PLACEMENT ] ---
if [ ! -d "$TARGET_DIR/Engine/Binaries/Linux" ]; then
    echo -e "\n${C_CYAN}--> [1/4] Extracting Unreal Engine archive (${ZIP_FILE})...${C_RESET}"
    mkdir -p "$TARGET_DIR"
    unzip -q -o "$ZIP_FILE" -d "$TARGET_DIR"
    
    # Flatten single top-level directory if present
    SUB_DIR=$(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -type d -name "Linux_Unreal_Engine*" -o -name "UnrealEngine*" 2>/dev/null | head -n1 || true)
    if [ -n "$SUB_DIR" ] && [ -d "$SUB_DIR/Engine" ]; then
        echo -e " • Adjusting directory hierarchy..."
        mv "$SUB_DIR"/* "$TARGET_DIR/"
        rmdir "$SUB_DIR" 2>/dev/null || true
    fi
else
    echo -e "\n${C_GREEN}• Unreal Engine binaries already present in ${TARGET_DIR} [Saved I/O]${C_RESET}"
fi

# --- [ 5. INJECT INSTALLED BUILD MANIFEST (SPOOFING) ] ---
echo -e "\n${C_CYAN}--> [2/4] Injecting InstalledBuild manifest (${VERSION})...${C_RESET}"
mkdir -p "$TARGET_DIR/Engine/Build"
cat << EOF_INST > "$TARGET_DIR/Engine/Build/InstalledBuild.txt"
${VERSION}-0+++UE5+Release-${MAJOR_MINOR}
EOF_INST

chmod +x "$TARGET_DIR/Engine/Binaries/Linux/UnrealEditor" 2>/dev/null || true
chmod +x "$TARGET_DIR/Engine/Build/BatchFiles/Linux/"*.sh 2>/dev/null || true

# --- [ 6. INJECT 3DCONNEXION SPACEMOUSE PLUGIN ] ---
echo -e "\n${C_CYAN}--> [3/4] Injecting OpenUnrealSpaceMouse Plugin (6-DoF HID Integration)...${C_RESET}"
PLUGIN_DEST="$TARGET_DIR/Engine/Plugins/Marketplace/SpaceMouse"
mkdir -p "$PLUGIN_DEST"

if [ -d "$SCRIPT_DIR/plugins/SpaceMouse" ]; then
    echo -e " • Copying bundled SpaceMouse plugin to ${PLUGIN_DEST}..."
    cp -a "$SCRIPT_DIR/plugins/SpaceMouse"/* "$PLUGIN_DEST/"
else
    echo -e " • Cloning OpenUnrealSpaceMouse plugin from repository..."
    git clone --depth 1 --branch develop --recurse-submodules https://github.com/microdee/OpenUnrealSpaceMouse.git "$PLUGIN_DEST"
    rm -rf "$PLUGIN_DEST/.git"
fi

if [ -f "$PLUGIN_DEST/SpaceMouse.uplugin" ]; then
    sed -i 's|"EnabledByDefault": false|"EnabledByDefault": true|g' "$PLUGIN_DEST/SpaceMouse.uplugin"
fi
echo -e "${C_GREEN}✓ SpaceMouse plugin deployed to engine marketplace tier!${C_RESET}"

# --- [ 7. DEPLOY SYSTEM LAUNCHER & DESKTOP INTEGRATION ] ---
echo -e "\n${C_CYAN}--> [4/4] Deploying system launcher, CUDA/OpenCL wrappers & desktop icon...${C_RESET}"

# Symlink decoupling if installed to custom mount
if [ "$TARGET_DIR" != "$DEFAULT_INSTALL_DIR" ]; then
    echo "$TARGET_DIR" | sudo tee "/etc/unreal-engine-${MAJOR_MINOR}.conf" >/dev/null
    echo "$TARGET_DIR" | sudo tee "/etc/unreal-engine.conf" >/dev/null
    sudo rm -f "$DEFAULT_INSTALL_DIR" 2>/dev/null || true
    sudo ln -sfn "$TARGET_DIR" "$DEFAULT_INSTALL_DIR"
    echo -e " • Created symlink: ${DEFAULT_INSTALL_DIR} -> ${TARGET_DIR}"
fi

# Deploy wrapper script
sudo install -m 755 "$SCRIPT_DIR/unreal-engine-wrapper.sh" /usr/bin/unreal-engine
sudo ln -sf /usr/bin/unreal-engine "/usr/bin/unreal-engine-5"
sudo ln -sf /usr/bin/unreal-engine "/usr/bin/unreal-engine-${MAJOR_MINOR}"

# Dynamically generate desktop entry for this version
DESK_FILE="/usr/share/applications/unreal-engine-${MAJOR_MINOR}.desktop"
sudo tee "$DESK_FILE" >/dev/null << EOF_DESK_ENTRY
[Desktop Entry]
Type=Application
Version=1.5
Name=Unreal Engine ${MAJOR_MINOR}
GenericName=Game Engine Editor
Comment=Real-time 3D creation tool with Nanite, Lumen and SpaceMouse support
Icon=ue5
Exec=unreal-engine %F
Terminal=false
MimeType=application/x-unreal-project;
Categories=Development;
Keywords=3D;Game;Engine;Editor;Vulkan;Nanite;Lumen;SpaceMouse;
StartupNotify=true
StartupWMClass=UnrealEditor
EOF_DESK_ENTRY

# Deploy icons
if [ -f "$SCRIPT_DIR/ue5.png" ]; then
    sudo install -m 644 "$SCRIPT_DIR/ue5.png" /usr/share/pixmaps/ue5.png
    sudo mkdir -p /usr/share/icons/hicolor/256x256/apps
    sudo install -m 644 "$SCRIPT_DIR/ue5.png" /usr/share/icons/hicolor/256x256/apps/ue5.png
fi

# Update desktop cache
sudo update-desktop-database -q /usr/share/applications 2>/dev/null || true
sudo gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor 2>/dev/null || true

echo -e "\n------------------------------------------------------------------"
echo -e "${C_GREEN}${C_BOLD}SUCCESS! Unreal Engine ${VERSION} is fully installed & configured!${C_RESET}"
echo -e "• Installed path: ${TARGET_DIR}"
echo -e "• SpaceMouse 6-DoF HID plugin: ${PLUGIN_DEST}"
echo -e "• Launcher commands: ${C_CYAN}unreal-engine${C_RESET}, ${C_CYAN}unreal-engine-5${C_RESET}, ${C_CYAN}unreal-engine-${MAJOR_MINOR}${C_RESET}"
echo -e "• Graphical launcher: 'Unreal Engine ${MAJOR_MINOR}' in application menu under Development"
echo -e "------------------------------------------------------------------\n"
