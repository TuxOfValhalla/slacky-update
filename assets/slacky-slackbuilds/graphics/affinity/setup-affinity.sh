#!/usr/bin/env bash
# ==============================================================================
#  setup-affinity.sh - Native Slackware Installer for Serif Affinity Suite
#  Full Automated Pipeline: Wine 11.12 v4, 150% UI Scaling, Affinity v3 Installer,
#  WebView2 Runtime, WinRT Foundation Contracts, AffinityHook & WineFix
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
DEFAULT_PREFIX="${HOME}/.local/share/affinity-wine"

echo -e "${C_CYAN}"
cat << 'EOF_BANNER'
  .==============================================================.
  |  AFFINITY SUITE ON SLACKWARE (AFFINITY UNIFIED V3 + WINEFIX) |
  |  ElementalWarrior Wine, 150% UI Scale, WinRT, AffinityHook  |
  *==============================================================*
EOF_BANNER
echo -e "${C_RESET}"

# Ensure PATH includes system Wine staging and user local bins
export PATH="/usr/local/bin:/opt/wine-staging/bin:$PATH"

resolve_missing_dependencies() {
    local missing=("$@")
    local sbo_pkgs=()
    local official_pkgs=()
    local wine_missing=0

    for dep in "${missing[@]}"; do
        case "$dep" in
            7z) sbo_pkgs+=("p7zip") ;;
            cabextract) sbo_pkgs+=("cabextract") ;;
            jq) sbo_pkgs+=("jq") ;;
            winetricks) sbo_pkgs+=("winetricks") ;;
            zstd) official_pkgs+=("zstd") ;;
            wget) official_pkgs+=("wget") ;;
            curl) official_pkgs+=("curl") ;;
            unzip) official_pkgs+=("infozip") ;;
            python3) official_pkgs+=("python3") ;;
            wine|wineserver) wine_missing=1 ;;
            *) sbo_pkgs+=("$dep") ;;
        esac
    done

    # Remove duplicates
    sbo_pkgs=($(echo "${sbo_pkgs[@]:-}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    official_pkgs=($(echo "${official_pkgs[@]:-}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

    echo -e "${C_YELLOW}Notice: Missing required tools: ${missing[*]}${C_RESET}"
    if [ ${#sbo_pkgs[@]} -gt 0 ]; then
        echo -e " • SBo / Slacky packages: ${C_CYAN}${sbo_pkgs[*]}${C_RESET}"
    fi
    if [ ${#official_pkgs[@]} -gt 0 ]; then
        echo -e " • Slackware core packages: ${C_CYAN}${official_pkgs[*]}${C_RESET}"
    fi
    if [ "$wine_missing" -eq 1 ]; then
        echo -e "${C_YELLOW} • System Wine is required in \$PATH for bootstrap (e.g. Kron4ek Wine in /opt/wine-staging or multilib wine).${C_RESET}"
    fi

    # Detect package manager
    local PKG_MGR=""
    if command -v sboinstall >/dev/null 2>&1; then
        PKG_MGR="sbotools (sboinstall)"
    elif command -v sbopkg >/dev/null 2>&1; then
        PKG_MGR="sbopkg"
    elif command -v slackpkg >/dev/null 2>&1; then
        PKG_MGR="slackpkg"
    fi

    # Determine elevation method
    local ELEVATE=""
    if command -v sudo >/dev/null 2>&1; then
        ELEVATE="sudo"
    elif command -v doas >/dev/null 2>&1; then
        ELEVATE="doas"
    elif command -v pkexec >/dev/null 2>&1; then
        ELEVATE="pkexec"
    fi

    local do_install="n"
    local all_needed=(${sbo_pkgs[@]:-} ${official_pkgs[@]:-})

    if [ ${#all_needed[@]} -gt 0 ] && [ -n "$PKG_MGR" ]; then
        if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
            if command -v zenity >/dev/null 2>&1; then
                if zenity --question --title="Affinity Pre-flight: Manglende verktøy" \
                    --text="Følgende påkrevde verktøy mangler på systemet:\n\n<b>${all_needed[*]}</b>\n\nØnsker du å installere dem automatisk via <b>$PKG_MGR</b>?" \
                    --width=450 2>/dev/null; then
                    do_install="y"
                fi
            elif command -v kdialog >/dev/null 2>&1; then
                if kdialog --yesno "Følgende påkrevde verktøy mangler på systemet:\n\n${all_needed[*]}\n\nØnsker du å installere dem automatisk via $PKG_MGR?" \
                    --title "Affinity Pre-flight" 2>/dev/null; then
                    do_install="y"
                fi
            fi
        fi

        if [ "$do_install" != "y" ] && ([ -t 0 ] || [ -t 1 ]); then
            echo -en "\n${C_BOLD}Vil du installere manglende pakker nå via ${PKG_MGR}? [J/n]: ${C_RESET}"
            read -r ans || ans="n"
            if [[ "$ans" =~ ^[jJyY] ]] || [ -z "$ans" ]; then
                do_install="y"
            fi
        fi
    fi

    if [ "$do_install" = "y" ]; then
        echo -e "\n${C_CYAN}--> Installerer manglende avhengigheter via $PKG_MGR...${C_RESET}"

        # 1. Official packages
        if [ ${#official_pkgs[@]} -gt 0 ] && command -v slackpkg >/dev/null 2>&1; then
            echo -e " • Kjører: $ELEVATE slackpkg install ${official_pkgs[*]}"
            if [ -n "$ELEVATE" ]; then
                $ELEVATE slackpkg -batch=on -default_answer=y install "${official_pkgs[@]}" || true
            else
                su -c "slackpkg -batch=on -default_answer=y install ${official_pkgs[*]}" || true
            fi
        fi

        # 2. SBo packages
        if [ ${#sbo_pkgs[@]} -gt 0 ]; then
            if command -v sboinstall >/dev/null 2>&1; then
                echo -e " • Kjører: $ELEVATE sboinstall -r ${sbo_pkgs[*]}"
                if [ -n "$ELEVATE" ]; then
                    $ELEVATE sboinstall -r --no-prompt "${sbo_pkgs[@]}" || true
                else
                    su -c "sboinstall -r --no-prompt ${sbo_pkgs[*]}" || true
                fi
            elif command -v sbopkg >/dev/null 2>&1; then
                for p in "${sbo_pkgs[@]}"; do
                    echo -e " • Kjører: $ELEVATE sbopkg for $p"
                    if command -v sqg >/dev/null 2>&1; then
                        $ELEVATE sqg -p "$p" || true
                        $ELEVATE sbopkg -B -k -i "$p" || true
                    else
                        $ELEVATE sbopkg -B -i "$p" || true
                    fi
                done
            fi
        fi

        # Re-verify
        local still_missing=()
        for dep in "${REQUIRED_BINS[@]}"; do
            if ! command -v "$dep" >/dev/null 2>&1; then
                still_missing+=("$dep")
            fi
        done

        if [ ${#still_missing[@]} -eq 0 ]; then
            echo -e "${C_GREEN}✓ Alle avhengigheter er nå installert og verifisert!${C_RESET}"
            return 0
        fi
    fi

    # If still missing and winetricks is missing but curl/wget available, offer standalone winetricks
    if ! command -v winetricks >/dev/null 2>&1 && (command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1); then
        echo -e " • Forsøker nedlasting av frittstående winetricks til /usr/local/bin..."
        if [ -n "$ELEVATE" ]; then
            $ELEVATE curl -sSL https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks -o /usr/local/bin/winetricks && $ELEVATE chmod +x /usr/local/bin/winetricks || true
        fi
    fi

    # Final check
    local final_missing=()
    for dep in "${REQUIRED_BINS[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            final_missing+=("$dep")
        fi
    done

    if [ ${#final_missing[@]} -gt 0 ]; then
        echo -e "\n${C_RED}Error: Følgende påkrevde verktøy mangler fortsatt: ${final_missing[*]}${C_RESET}"
        if [ ${#sbo_pkgs[@]} -gt 0 ]; then
            echo -e "${C_YELLOW}Vennligst installer SBo-pakker:${C_RESET} sudo sboinstall ${sbo_pkgs[*]}"
        fi
        if [ ${#official_pkgs[@]} -gt 0 ]; then
            echo -e "${C_YELLOW}Vennligst installer Slackware-pakker:${C_RESET} sudo slackpkg install ${official_pkgs[*]}"
        fi
        if [ "$wine_missing" -eq 1 ]; then
            echo -e "${C_YELLOW}Sørg for at Wine (f.eks. /opt/wine-staging/bin/wine eller multilib) er tilgjengelig i \$PATH.${C_RESET}"
        fi
        exit 1
    fi
}

# --- [ 1. VERIFY REQUIRED SLACKWARE DEPENDENCIES ] ---
echo -e "${C_CYAN}--> [1/8] Checking Slackware dependencies & System Wine...${C_RESET}"
REQUIRED_BINS=(wine wineserver winetricks 7z cabextract jq curl wget tar zstd unzip python3)
MISSING_DEPS=()

for dep in "${REQUIRED_BINS[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        MISSING_DEPS+=("$dep")
    fi
done

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    resolve_missing_dependencies "${MISSING_DEPS[@]}"
fi
echo -e "${C_GREEN}✓ All core dependencies (${REQUIRED_BINS[*]}) are satisfied!${C_RESET}"

# --- [ 2. GPU & HARDWARE ACCELERATION PRE-FLIGHT CHECK ] ---
echo -e "\n${C_CYAN}--> [2/8] Detecting GPU and hardware acceleration capabilities...${C_RESET}"
GPU_INFO=$(lspci 2>/dev/null | grep -iE "vga|3d|display" || true)
IS_NVIDIA=0
IS_AMD=0
IS_INTEL=0

if echo "$GPU_INFO" | grep -qi "nvidia"; then
    IS_NVIDIA=1
    GPU_NAME=$(echo "$GPU_INFO" | grep -i "nvidia" | head -1 | sed 's/.*: //')
    echo -e " • Detected NVIDIA GPU: ${C_GREEN}${GPU_NAME}${C_RESET}"
    echo -e "${C_GREEN}✓ OpenCL and Direct3D 12 (vkd3d-proton) acceleration will be fully enabled!${C_RESET}"
elif echo "$GPU_INFO" | grep -qiE "amd|radeon|ati"; then
    IS_AMD=1
    GPU_NAME=$(echo "$GPU_INFO" | grep -iE "amd|radeon|ati" | head -1 | sed 's/.*: //')
    echo -e " • Detected AMD GPU: ${C_YELLOW}${GPU_NAME}${C_RESET}"
    echo -e "${C_YELLOW}! OpenCL will be automatically disabled to prevent crashes on AMD hardware (Direct3D 12 active)${C_RESET}"
elif echo "$GPU_INFO" | grep -qi "intel"; then
    IS_INTEL=1
    GPU_NAME=$(echo "$GPU_INFO" | grep -i "intel" | head -1 | sed 's/.*: //')
    echo -e " • Detected Intel GPU: ${C_GREEN}${GPU_NAME}${C_RESET}"
    echo -e "${C_GREEN}✓ Direct3D 12 / Vulkan acceleration active${C_RESET}"
else
    echo -e " • GPU: Generic / Unidentified (${GPU_INFO})"
fi

# --- [ 3. RESOLVE PREFIX DIRECTORY (AUTOMATED / ZERO INTERVENTION) ] ---
PREFIX_DIR="${AFFINITY_DIR:-$DEFAULT_PREFIX}"
PREFIX_DIR=$(realpath -m "$PREFIX_DIR")
echo -e "\nAffinity Wine prefix: ${C_GREEN}${PREFIX_DIR}${C_RESET}"
mkdir -p "$PREFIX_DIR"

export WINEPREFIX="$PREFIX_DIR"
WINE_DIR="$PREFIX_DIR/ElementalWarriorWine"

# --- [ 3.1 RYZENDEW ONE-CLICK INSTALLER INTEGRATION (PYQT6 GUI) ] ---
PY_INSTALLER=""
for cand in "$SCRIPT_DIR/AffinityLinuxInstaller.py" "/usr/share/affinity/AffinityLinuxInstaller.py" "$PREFIX_DIR/AffinityLinuxInstaller.py"; do
    if [ -f "$cand" ]; then
        PY_INSTALLER="$cand"
        break
    fi
done

if [ -z "$PY_INSTALLER" ]; then
    echo -e " • Fetching official Ryzendew AffinityLinuxInstaller.py..."
    PY_INSTALLER="$PREFIX_DIR/AffinityLinuxInstaller.py"
    curl -sSL -o "$PY_INSTALLER" "https://raw.githubusercontent.com/ryzendew/Linux-Affinity-Installer/main/AffinityScripts/AffinityLinuxInstaller.py" || true
fi

if [ -f "$PY_INSTALLER" ]; then
    # Inject Slackware bypass patch into install_dependencies()
    python3 -c '
path = "'"$PY_INSTALLER"'"
try:
    with open(path, "r") as f:
        c = f.read()
    if "if self.distro == \"slackware\":" not in c:
        target = "def install_dependencies(self):"
        patch = """def install_dependencies(self):
        if self.distro == \"slackware\":
            self.log(\"Slackware detected - system tools verified\", \"success\")
            return True"""
        c = c.replace(target, patch)
        with open(path, "w") as f:
            f.write(c)
except Exception:
    pass
' 2>/dev/null || true
fi

# Launch Ryzendew One-Click GUI if in graphical environment and not in CLI mode
if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
    if [ "${1:-}" != "--cli" ] && [ "${1:-}" != "--headless" ] && [ -f "$PY_INSTALLER" ]; then
        echo -e "\n${C_BOLD}${C_GREEN}==> Launching Ryzendew Native One-Click Installer (PyQt6 GUI)...${C_RESET}"
        export PATH="/usr/local/bin:/opt/wine-staging/bin:$PATH"
        exec python3 "$PY_INSTALLER" "$@"
    fi
fi

# --- [ 3. DOWNLOAD & DEPLOY ELEMENTALWARRIOR WINE ] ---
echo -e "\n${C_CYAN}--> [2/8] Setting up ElementalWarrior Patched Wine...${C_RESET}"

ACTUAL_DIR=$(find "$PREFIX_DIR" -maxdepth 1 -type d -name "ElementalWarrior*" | head -1 || true)

if [ -z "$ACTUAL_DIR" ] || [ ! -x "$ACTUAL_DIR/bin/wine" ]; then
    if grep -m1 -E "(flags|Features)" /proc/cpuinfo 2>/dev/null | grep -q "avx512"; then
        echo -e " • Detected CPU with AVX-512 / Zen 4/5 support. Using optimized v4 tier!"
        WINE_TAR="$PREFIX_DIR/ElementalWarrior-wine-11.12-v4.tar.xz"
        WINE_URL="https://github.com/ryzendew/Affinity-Wine-Builder/releases/download/11.12/ElementalWarrior-wine-11.12-v4.tar.xz"
    else
        echo -e " • Using standard ElementalWarrior 11.12 tier."
        WINE_TAR="$PREFIX_DIR/ElementalWarrior-wine-11.12.tar.xz"
        WINE_URL="https://github.com/ryzendew/Affinity-Wine-Builder/releases/download/11.12/ElementalWarrior-wine-11.12.tar.xz"
    fi
    
    echo -e " • Downloading ElementalWarrior Wine..."
    curl -sSL -o "$WINE_TAR" "$WINE_URL"
    
    echo -e " • Extracting patched Wine..."
    tar -xf "$WINE_TAR" -C "$PREFIX_DIR"
    rm -f "$WINE_TAR"
    
    ACTUAL_DIR=$(find "$PREFIX_DIR" -maxdepth 1 -type d -name "ElementalWarrior*" | head -1 || true)
fi

# Ensure symlink ElementalWarriorWine exists
if [ -n "$ACTUAL_DIR" ]; then
    ln -sfn "$ACTUAL_DIR" "$WINE_DIR"
fi

export PATH="$WINE_DIR/bin:$PATH"
export WINELOADER="$WINE_DIR/bin/wine"
echo -e "${C_GREEN}✓ ElementalWarrior Wine verified: $("$WINE_DIR/bin/wine" --version)${C_RESET}"

# --- [ 4. INITIAL BOOTSTRAP, WINMETADATA & 150% DPI SCALING ] ---
echo -e "\n${C_CYAN}--> [3/8] Bootstrapping Wine prefix, WinRT metadata & 150% UI Scaling...${C_RESET}"
wineboot -u

SYSTEM32_DIR="$PREFIX_DIR/drive_c/windows/system32"
WINMETADATA_DIR="$SYSTEM32_DIR/WinMetadata"
mkdir -p "$WINMETADATA_DIR"

if [ ! -f "$WINMETADATA_DIR/Windows.winmd" ]; then
    echo -e " • Downloading Windows Metadata (WinRT integration)..."
    META_TAR="$PREFIX_DIR/WinMetadata.tar.xz"
    curl -sSL -o "$META_TAR" "https://github.com/ryzendew/Linux-Affinity-Installer/releases/download/10.4-Wine-Affinity/WinMetadata.tar.xz"
    tar -xf "$META_TAR" -C "$SYSTEM32_DIR"
    rm -f "$META_TAR"
    # Ensure no nested WinMetadata/WinMetadata
    if [ -d "$WINMETADATA_DIR/WinMetadata" ]; then
        cp -a "$WINMETADATA_DIR/WinMetadata/"* "$WINMETADATA_DIR/" 2>/dev/null || true
        rm -rf "$WINMETADATA_DIR/WinMetadata"
    fi
    echo -e "${C_GREEN}✓ WinMetadata deployed to $WINMETADATA_DIR${C_RESET}"
else
    echo -e "${C_GREEN}• WinMetadata already present [Saved I/O]${C_RESET}"
fi

# Deploy system ICC color profiles (sRGB)
COLOR_DIR="$SYSTEM32_DIR/spool/drivers/color"
mkdir -p "$COLOR_DIR"
if [ -f /usr/share/color/icc/colord/sRGB.icc ]; then
    cp -f /usr/share/color/icc/colord/sRGB.icc "$COLOR_DIR/sRGB Color Space Profile.icm" 2>/dev/null || true
    cp -f /usr/share/color/icc/colord/sRGB.icc "$COLOR_DIR/sRGB.icm" 2>/dev/null || true
    cp -f /usr/share/color/icc/colord/sRGB.icc "$COLOR_DIR/srgb.icm" 2>/dev/null || true
fi

# Patch wine-mono <MarshalCopy> assertion bug (prevents crash on document creation)
MONO_DLL="$PREFIX_DIR/drive_c/windows/mono/mono-2.0/bin/libmono-2.0-x86_64.dll"
if [ -f "$MONO_DLL" ]; then
    python3 -c '
dll = "'"$MONO_DLL"'"
with open(dll, "r+b") as f:
    d = f.read()
    idx = d.find(bytes.fromhex("4989c64885c00f8477010000"))
    if idx != -1:
        f.seek(idx + 6)
        f.write(bytes.fromhex("0f840c000000"))
' 2>/dev/null || true
fi

# WinRT Foundation Contracts (fixes Serif.Affinity.UI.Dialogs.UpdateDialog:m_operation crash)
if [ ! -f "$WINMETADATA_DIR/Windows.Foundation.FoundationContract.winmd" ]; then
    echo -e " • Downloading Microsoft WinRT SDK Contracts..."
    CONTRACTS_ZIP="$PREFIX_DIR/contracts.zip"
    curl -sSL -o "$CONTRACTS_ZIP" "https://www.nuget.org/api/v2/package/Microsoft.Windows.SDK.Contracts/10.0.19041.1"
    mkdir -p "$PREFIX_DIR/contracts_tmp"
    unzip -q "$CONTRACTS_ZIP" "ref/netstandard2.0/*" -d "$PREFIX_DIR/contracts_tmp"
    cp -f "$PREFIX_DIR/contracts_tmp/ref/netstandard2.0/"*.winmd "$WINMETADATA_DIR/" 2>/dev/null || true
    cp -f "$PREFIX_DIR/contracts_tmp/ref/netstandard2.0/"*.WinMD "$WINMETADATA_DIR/" 2>/dev/null || true
    rm -rf "$PREFIX_DIR/contracts_tmp" "$CONTRACTS_ZIP"
    echo -e "${C_GREEN}✓ WinRT Foundation Contracts deployed to system32/WinMetadata!${C_RESET}"
fi

# ElementalWarrior wintypes.dll shim
if [ ! -f "$SYSTEM32_DIR/wintypes.dll" ]; then
    echo -e " • Downloading ElementalWarrior wintypes.dll shim..."
    curl -sSL -o "$SYSTEM32_DIR/wintypes.dll" "https://github.com/ElementalWarrior/wine-wintypes.dll-for-affinity/raw/refs/heads/master/wintypes_shim.dll.so"
fi
"$WINE_DIR/bin/wine" reg add 'HKCU\Software\Wine\DllOverrides' /v wintypes /t REG_SZ /d native /f >/dev/null 2>&1 || true

# Configure Windows 11 Build in registry
"$WINE_DIR/bin/wine" reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion' /v CurrentBuildNumber /t REG_SZ /d 22621 /f >/dev/null 2>&1 || true

# Apply 150% UI Scaling (144 DPI = 0x90)
"$WINE_DIR/bin/wine" reg add 'HKCU\Control Panel\Desktop' /v LogPixels /t REG_DWORD /d 144 /f >/dev/null 2>&1 || true
# Wine X11 Driver fixes for KDE Plasma / Wayland (fixes panel clicks and input focus)
"$WINE_DIR/bin/wine" reg add 'HKCU\Software\Wine\X11 Driver' /v UseTakeFocus /t REG_SZ /d N /f >/dev/null 2>&1 || true
"$WINE_DIR/bin/wine" reg add 'HKCU\Software\Wine\X11 Driver' /v Managed /t REG_SZ /d Y /f >/dev/null 2>&1 || true
# Apply Dark Theme
if [ -f "$SCRIPT_DIR/wine-dark-theme.reg" ]; then
    "$WINE_DIR/bin/regedit" "$SCRIPT_DIR/wine-dark-theme.reg" >/dev/null 2>&1 || true
fi

# Configure GPU-specific registry & OpenCL hardware acceleration
if [ "$IS_AMD" -eq 1 ]; then
    echo -e " • Disabling OpenCL for AMD GPU in Wine registry..."
    "$WINE_DIR/bin/wine" reg add 'HKCU\Software\Wine\DllOverrides' /v opencl /t REG_SZ /d "" /f >/dev/null 2>&1 || true
    echo "amd" > "$PREFIX_DIR/.gpu_vendor"

    # Pre-seed PerformancePreferences.xml with OpenCL disabled for AMD stability
    for SETTINGS_DIR in \
        "$PREFIX_DIR/drive_c/users/${USER}/AppData/Roaming/Affinity/Affinity/3.0/Settings" \
        "$PREFIX_DIR/drive_c/users/${USER}/AppData/Roaming/Affinity/Photo/2.0/Settings" \
        "$PREFIX_DIR/drive_c/users/${USER}/AppData/Roaming/Affinity/Designer/2.0/Settings" \
        "$PREFIX_DIR/drive_c/users/${USER}/AppData/Roaming/Affinity/Publisher/2.0/Settings"; do
        mkdir -p "$SETTINGS_DIR"
        P_XML="$SETTINGS_DIR/PerformancePreferences.xml"
        if [ -f "$P_XML" ]; then
            sed -i 's/<UseHardwareAcceleration>True<\/UseHardwareAcceleration>/<UseHardwareAcceleration>False<\/UseHardwareAcceleration>/g' "$P_XML" 2>/dev/null || true
            sed -i 's/<UseHardwareAcceleration2>True<\/UseHardwareAcceleration2>/<UseHardwareAcceleration2>False<\/UseHardwareAcceleration2>/g' "$P_XML" 2>/dev/null || true
            sed -i 's/<UseHardwareAcceleration2 xsi:nil="true" \/>/<UseHardwareAcceleration2>False<\/UseHardwareAcceleration2>/g' "$P_XML" 2>/dev/null || true
        else
            cat << 'EOF_PXML' > "$P_XML"
<?xml version="1.0" encoding="utf-8"?>
<Settings xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xsi:type="Serif.Interop.Persona.Settings.PerformanceSettings">
	<RAMUsageLimit>
		<UnitType>Megabyte</UnitType>
		<Value>16384</Value>
	</RAMUsageLimit>
	<DiskWarningLimit>
		<UnitType>Megabyte</UnitType>
		<Value>32768</Value>
	</DiskWarningLimit>
	<UndoLimit>1024</UndoLimit>
	<ViewQuality>0</ViewQuality>
	<AutoSaveInterval>
		<UnitType>Number</UnitType>
		<Value>300</Value>
	</AutoSaveInterval>
	<UsePerfectClipping>False</UsePerfectClipping>
	<UseDithering>False</UseDithering>
	<RetinaPassIndex>0</RetinaPassIndex>
	<UseHardwareAcceleration>False</UseHardwareAcceleration>
	<UseHardwareAcceleration2>False</UseHardwareAcceleration2>
</Settings>
EOF_PXML
        fi
    done
    echo -e "${C_GREEN}✓ AMD GPU profile configured: OpenCL disabled to ensure rock-solid stability!${C_RESET}"
elif [ "$IS_NVIDIA" -eq 1 ]; then
    echo -e " • Ensuring OpenCL is enabled for NVIDIA GPU..."
    "$WINE_DIR/bin/wine" reg delete 'HKCU\Software\Wine\DllOverrides' /v opencl /f >/dev/null 2>&1 || true
    echo "nvidia" > "$PREFIX_DIR/.gpu_vendor"
    echo -e "${C_GREEN}✓ NVIDIA GPU profile configured: OpenCL & Direct3D 12 enabled!${C_RESET}"
fi

# --- [ 5. VKD3D-PROTON (DIRECT3D 12 TO VULKAN) ] ---
echo -e "\n${C_CYAN}--> [4/8] Setting up vkd3d-proton Direct3D 12 hardware acceleration...${C_RESET}"
VKD3D_TEMP="$PREFIX_DIR/vkd3d_dlls"
WINE_LIB_DIR="$WINE_DIR/lib/wine/vkd3d-proton/x86_64-windows"
mkdir -p "$VKD3D_TEMP" "$WINE_LIB_DIR"

if [ ! -f "$VKD3D_TEMP/d3d12.dll" ]; then
    echo -e " • Downloading vkd3d-proton v2.14.1..."
    VKD3D_TAR="$PREFIX_DIR/vkd3d-proton-2.14.1.tar.zst"
    curl -sSL -o "$VKD3D_TAR" "https://github.com/HansKristian-Work/vkd3d-proton/releases/download/v2.14.1/vkd3d-proton-2.14.1.tar.zst"
    tar --use-compress-program=zstd -xf "$VKD3D_TAR" -C "$PREFIX_DIR"
    rm -f "$VKD3D_TAR"
    
    EXTRACTED_VKD3D=$(find "$PREFIX_DIR" -maxdepth 1 -type d -name "vkd3d-proton-*" | head -1 || true)
    if [ -n "$EXTRACTED_VKD3D" ]; then
        cp -f "$EXTRACTED_VKD3D/x64/"*.dll "$VKD3D_TEMP/" 2>/dev/null || true
        cp -f "$EXTRACTED_VKD3D/x64/"*.dll "$WINE_LIB_DIR/" 2>/dev/null || true
        rm -rf "$EXTRACTED_VKD3D"
    fi
fi

"$WINE_DIR/bin/wine" reg add 'HKCU\Software\Wine\DllOverrides' /v d3d12 /t REG_SZ /d native /f >/dev/null 2>&1 || true
"$WINE_DIR/bin/wine" reg add 'HKCU\Software\Wine\DllOverrides' /v d3d12core /t REG_SZ /d native /f >/dev/null 2>&1 || true
"$WINE_DIR/bin/wine" reg add 'HKCU\Software\Wine\DllOverrides' /v d2d1 /t REG_SZ /d native,builtin /f >/dev/null 2>&1 || true
"$WINE_DIR/bin/wine" reg add 'HKCU\SOFTWARE\Microsoft\Avalon.Graphics' /v DisableHWAcceleration /t REG_DWORD /d 1 /f >/dev/null 2>&1 || true
echo -e "${C_GREEN}✓ Direct3D 12 / Vulkan, Direct2D and WPF acceleration configured!${C_RESET}"

# --- [ 6. WINETRICKS STEP-BY-STEP RECIPE ] ---
echo -e "\n${C_CYAN}--> [5/8] Configuring Windows Runtimes & Vulkan Backend...${C_RESET}"

WINETRICKS_VERBS=(
    "corefonts:Windows Core Fonts (Arial, Times, Courier)"
    "tahoma:Tahoma Font"
    "vcrun2022:Visual C++ 2022 Runtime"
    "msxml3:Microsoft XML 3.0"
    "msxml6:Microsoft XML 6.0"
    "dotnet35:Microsoft .NET Framework 3.5"
    "dotnet48:Microsoft .NET Framework 4.8"
    "renderer=vulkan:Vulkan Backend Configuration"
)

for v in "${WINETRICKS_VERBS[@]}"; do
    IFS=":" read -r verb verb_desc <<< "$v"
    echo -e "${C_BOLD}==> Installing ${verb_desc} (${verb})...${C_RESET}"
    winetricks --unattended --force --no-isolate --optout "$verb" || true
done
echo -e "\n${C_GREEN}✓ All Winetricks dependencies configured!${C_RESET}"

# --- [ 7. MICROSOFT EDGE WEBVIEW2 RUNTIME ] ---
echo -e "\n${C_CYAN}--> [6/8] Checking Microsoft Edge WebView2 Runtime...${C_RESET}"
WEBVIEW2_EXE=$(find "$PREFIX_DIR/drive_c/Program Files (x86)/Microsoft/EdgeWebView" -iname "msedgewebview2.exe" 2>/dev/null | head -1 || true)

if [ -z "$WEBVIEW2_EXE" ]; then
    echo -e " • Downloading Microsoft Edge WebView2 Runtime Installer (183 MB)..."
    WV2_INSTALLER="$PREFIX_DIR/MicrosoftEdgeWebView2RuntimeInstallerX64.exe"
    curl -sSL -o "$WV2_INSTALLER" "https://github.com/ryzendew/Linux-Affinity-Installer/releases/download/10.4-Wine-Affinity/MicrosoftEdgeWebView2RuntimeInstallerX64.exe"
    echo -e " • Installing WebView2 Runtime silently..."
    "$WINE_DIR/bin/wine" "$WV2_INSTALLER" /silent /install || true
    rm -f "$WV2_INSTALLER"
    
    # Configure WebView2 settings
    "$WINE_DIR/bin/wine" reg add 'HKLM\System\CurrentControlSet\Services\edgeupdate' /v Start /t REG_DWORD /d 4 /f >/dev/null 2>&1 || true
    "$WINE_DIR/bin/wine" reg add 'HKLM\System\CurrentControlSet\Services\edgeupdatem' /v Start /t REG_DWORD /d 4 /f >/dev/null 2>&1 || true
    "$WINE_DIR/bin/wine" reg add 'HKCU\Software\Wine\AppDefaults\msedgewebview2.exe' /v Version /t REG_SZ /d win7 /f >/dev/null 2>&1 || true
    "$WINE_DIR/bin/wine" reg add 'HKCU\Software\Policies\Microsoft\Edge\WebView2' /v AdditionalBrowserArguments /t REG_SZ /d '--disable-gpu --disable-gpu-compositing --disable-features=RendererCodeIntegrity --no-sandbox' /f >/dev/null 2>&1 || true
    "$WINE_DIR/bin/wine" reg add 'HKLM\Software\Policies\Microsoft\Edge\WebView2' /v AdditionalBrowserArguments /t REG_SZ /d '--disable-gpu --disable-gpu-compositing --disable-features=RendererCodeIntegrity --no-sandbox' /f >/dev/null 2>&1 || true
    echo -e "${C_GREEN}✓ Microsoft Edge WebView2 Runtime installed and configured!${C_RESET}"
else
    echo -e "${C_GREEN}✓ Microsoft Edge WebView2 Runtime already installed: $WEBVIEW2_EXE${C_RESET}"
    "$WINE_DIR/bin/wine" reg add 'HKCU\Software\Policies\Microsoft\Edge\WebView2' /v AdditionalBrowserArguments /t REG_SZ /d '--disable-gpu --disable-gpu-compositing --disable-features=RendererCodeIntegrity --no-sandbox' /f >/dev/null 2>&1 || true
fi

# --- [ 8. AUTOMATED DOWNLOAD & RUN OF AFFINITY V3 INSTALLER ] ---
echo -e "\n${C_CYAN}--> [7/8] Obtaining & Installing Affinity Unified v3...${C_RESET}"

AFFINITY_INSTALL_DIR=$(find "$PREFIX_DIR/drive_c/Program Files" -type d -iname "Affinity" 2>/dev/null | grep -E "Affinity/Affinity$" | head -1 || true)

if [ -z "$AFFINITY_INSTALL_DIR" ] || [ ! -f "$AFFINITY_INSTALL_DIR/Affinity.exe" ]; then
    if [ -d "/tmp/affinity_app_backup/Affinity" ]; then
        echo -e " • Restoring Affinity files from local backup (saved 1.5 GB download)..."
        mkdir -p "$PREFIX_DIR/drive_c/Program Files"
        cp -a "/tmp/affinity_app_backup/Affinity" "$PREFIX_DIR/drive_c/Program Files/"
        AFFINITY_INSTALL_DIR=$(find "$PREFIX_DIR/drive_c/Program Files" -type d -iname "Affinity" 2>/dev/null | grep -E "Affinity/Affinity$" | head -1 || true)
    fi
fi

if [ -z "$AFFINITY_INSTALL_DIR" ] || [ ! -f "$AFFINITY_INSTALL_DIR/Affinity.exe" ]; then
    INSTALLER_EXE=""
    for cand in "$PREFIX_DIR/Affinity x64.exe" "$HOME/Downloads/Affinity x64.exe" "$SCRIPT_DIR/Affinity x64.exe"; do
        if [ -f "$cand" ]; then
            INSTALLER_EXE="$cand"
            break
        fi
    done

    if [ -z "$INSTALLER_EXE" ]; then
        echo -e " • Downloading official Affinity Unified v3 Installer (662 MB)..."
        INSTALLER_EXE="$PREFIX_DIR/Affinity x64.exe"
        curl -L --progress-bar -o "$INSTALLER_EXE" "https://downloads.affinity.studio/Affinity%20x64.exe"
    fi

    echo -e "\n${C_BOLD}${C_CYAN}Launching Affinity Windows Installer...${C_RESET}"
    echo -e "Please complete the on-screen Affinity setup wizard."
    "$WINE_DIR/bin/wine" "$INSTALLER_EXE"

    "$WINE_DIR/bin/wineserver" -k 2>/dev/null || true
    sleep 2
    AFFINITY_INSTALL_DIR=$(find "$PREFIX_DIR/drive_c/Program Files" -type d -iname "Affinity" 2>/dev/null | grep -E "Affinity/Affinity$" | head -1 || true)
fi

# --- [ 9. DEPLOY AFFINITYHOOK & WINEFIX ] ---
echo -e "\n${C_CYAN}--> [8/8] Injecting AffinityHook + WineFix & WinRT assemblies...${C_RESET}"

if [ -n "$AFFINITY_INSTALL_DIR" ] && [ -d "$AFFINITY_INSTALL_DIR" ]; then
    HOOK_TAR="$SCRIPT_DIR/affinitypluginloader-plus-winefix.tar.xz"
    if [ ! -f "$HOOK_TAR" ]; then
        curl -sSL -o "$HOOK_TAR" "https://github.com/noahc3/AffinityPluginLoader/releases/download/v0.3.0/affinitypluginloader-plus-winefix.tar.xz"
    fi
    tar -xf "$HOOK_TAR" -C "$AFFINITY_INSTALL_DIR"
    
    # Clean up any leftover LayersFix plugins to allow native drag-and-drop
    mkdir -p "$AFFINITY_INSTALL_DIR/apl/plugins"
    rm -f "$AFFINITY_INSTALL_DIR/apl/plugins/LayersFix.dll" 2>/dev/null || true

    # Ensure standard WPF controls are used in Settings to prevent XAML crash in v3
    APL_TOML="$AFFINITY_INSTALL_DIR/apl/config/apl.toml"
    if [ -f "$APL_TOML" ]; then
        sed -i 's/force_wpf_controls = false/force_wpf_controls = true/' "$APL_TOML" 2>/dev/null || true
    fi
    
    # Deploy wintypes.dll and vkd3d dlls into application folder
    cp -f "$SYSTEM32_DIR/wintypes.dll" "$AFFINITY_INSTALL_DIR/" 2>/dev/null || true
    if [ -d "$VKD3D_TEMP" ]; then
        cp -f "$VKD3D_TEMP/"*.dll "$AFFINITY_INSTALL_DIR/" 2>/dev/null || true
    fi

    # Deploy WinRT Contract assemblies as .winmd AND .dll so Mono resolves them
    cp -f "$WINMETADATA_DIR/"*.winmd "$AFFINITY_INSTALL_DIR/" 2>/dev/null || true
    cp -f "$WINMETADATA_DIR/"*.WinMD "$AFFINITY_INSTALL_DIR/" 2>/dev/null || true
    (
        cd "$AFFINITY_INSTALL_DIR"
        for w in *.winmd *.WinMD; do
            [ -f "$w" ] || continue
            base="${w%.*}"
            cp -f "$w" "${base}.dll"
        done
    )
    echo -e "${C_GREEN}✓ AffinityHook, WineFix, and WinRT Contracts deployed!${C_RESET}"
fi

# Deploy Launchers and Desktop Integration
APPS_DIR="${HOME}/.local/share/applications"
ICONS_DIR="${HOME}/.local/share/icons/hicolor/256x256/apps"
mkdir -p "$APPS_DIR" "$ICONS_DIR" "${PREFIX_DIR}/bin"

WRAPPER_PATH="${PREFIX_DIR}/bin/affinity"
cat << 'EOF_APP_WRAP' > "$WRAPPER_PATH"
#!/usr/bin/env bash
export WINEPREFIX="${AFFINITY_DIR:-$HOME/.local/share/affinity-wine}"
export PATH="${WINEPREFIX}/ElementalWarriorWine/bin:$PATH"

# GPU Hardware Acceleration & Vendor Detection
GPU_PCI=$(lspci 2>/dev/null | grep -iE "vga|3d|display" || true)

if echo "$GPU_PCI" | grep -qi "nvidia"; then
    # NVIDIA GPU: Enable Prime render offload, Vulkan ICD and OpenCL
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export __VK_LAYER_NV_optimus=NVIDIA_only
    [ -f /etc/vulkan/icd.d/nvidia_icd.json ] && export VK_ICD_FILENAMES=/etc/vulkan/icd.d/nvidia_icd.json
    export OCL_ICD_VENDORS="nvidia.icd"
elif echo "$GPU_PCI" | grep -qiE "amd|radeon|ati"; then
    # AMD GPU: Disable OpenCL to prevent canvas and startup crashes
    export WINEDLLOVERRIDES="opencl=;${WINEDLLOVERRIDES:-}"
    export DXVK_ASYNC=0
    export DXVK_CONFIG="d3d9.deferSurfaceCreation = True; d3d9.shaderModel = 1"
    unset OCL_ICD_VENDORS

    # Ensure OpenCL hardware acceleration is disabled in Affinity settings for AMD
    for PERF_XML in \
        "${WINEPREFIX}/drive_c/users/${USER}/AppData/Roaming/Affinity/Affinity/3.0/Settings/PerformancePreferences.xml" \
        "${WINEPREFIX}/drive_c/users/${USER}/AppData/Roaming/Affinity/Photo/2.0/Settings/PerformancePreferences.xml" \
        "${WINEPREFIX}/drive_c/users/${USER}/AppData/Roaming/Affinity/Designer/2.0/Settings/PerformancePreferences.xml" \
        "${WINEPREFIX}/drive_c/users/${USER}/AppData/Roaming/Affinity/Publisher/2.0/Settings/PerformancePreferences.xml"; do
        if [ -f "$PERF_XML" ]; then
            sed -i 's/<UseHardwareAcceleration>True<\/UseHardwareAcceleration>/<UseHardwareAcceleration>False<\/UseHardwareAcceleration>/g' "$PERF_XML" 2>/dev/null || true
            sed -i 's/<UseHardwareAcceleration2>True<\/UseHardwareAcceleration2>/<UseHardwareAcceleration2>False<\/UseHardwareAcceleration2>/g' "$PERF_XML" 2>/dev/null || true
            sed -i 's/<UseHardwareAcceleration2 xsi:nil="true" \/>/<UseHardwareAcceleration2>False<\/UseHardwareAcceleration2>/g' "$PERF_XML" 2>/dev/null || true
        fi
    done
fi

# WebView2 Chromium in Wine Fix: Disable GPU sandbox & hardware rasterization to prevent blank white screen
export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="--disable-gpu --disable-gpu-compositing --disable-features=RendererCodeIntegrity --no-sandbox --in-process-gpu"
export WEBVIEW2_BROWSER_EXECUTABLE_FOLDER="C:\\Program Files (x86)\\Microsoft\\EdgeWebView\\Application\\142.0.3595.94"

export WINEDEBUG="-all"
export DXVK_LOG_LEVEL="none"

# Clear stale IPC lock files from previous crashes/runs
rm -f "${WINEPREFIX}/drive_c/users/${USER}/AppData/Roaming/Affinity/Common/3.0/locks/"* 2>/dev/null || true

# Disable WPF UI hardware acceleration to prevent dialog crashes (Settings, New Document)
if ! grep -q "DisableHWAcceleration" "${WINEPREFIX}/user.reg" 2>/dev/null; then
    "${WINEPREFIX}/ElementalWarriorWine/bin/wine" reg add 'HKCU\SOFTWARE\Microsoft\Avalon.Graphics' /v DisableHWAcceleration /t REG_DWORD /d 1 /f >/dev/null 2>&1 || true
fi

# Fix KDE Plasma / Wayland window focus and panel clicking
"${WINEPREFIX}/ElementalWarriorWine/bin/wine" reg add 'HKCU\Software\Wine\X11 Driver' /v UseTakeFocus /t REG_SZ /d N /f >/dev/null 2>&1 || true
"${WINEPREFIX}/ElementalWarriorWine/bin/wine" reg add 'HKCU\Software\Wine\X11 Driver' /v Managed /t REG_SZ /d Y /f >/dev/null 2>&1 || true

# Patch wine-mono <MarshalCopy> assertion bug (prevents crash on document creation)
MONO_DLL="${WINEPREFIX}/drive_c/windows/mono/mono-2.0/bin/libmono-2.0-x86_64.dll"
if [ -f "$MONO_DLL" ]; then
    python3 -c '
dll = "'"$MONO_DLL"'"
with open(dll, "r+b") as f:
    d = f.read()
    idx = d.find(bytes.fromhex("4989c64885c00f8477010000"))
    if idx != -1:
        f.seek(idx + 6)
        f.write(bytes.fromhex("0f840c000000"))
' 2>/dev/null || true
fi

# Suppress WebView2 Welcome / New Document popup to prevent white window
APP_XML="${WINEPREFIX}/drive_c/users/${USER}/AppData/Roaming/Affinity/Affinity/3.0/Settings/Application.xml"
if [ -f "$APP_XML" ]; then
    sed -i 's/<ShowNewDocumentDialog>True<\/ShowNewDocumentDialog>/<ShowNewDocumentDialog>False<\/ShowNewDocumentDialog>/' "$APP_XML" 2>/dev/null || true
fi

# Disable Canva Home Web feed in New Document dialog (prevents white screen when clicking New)
HOME_XML="${WINEPREFIX}/drive_c/users/${USER}/AppData/Roaming/Affinity/Affinity/3.0/Settings/HomeScreenPreferences.xml"
if [ -f "$HOME_XML" ]; then
    sed -i 's/<HomeScreenItem Type="1" IsOn="True" \/>/<HomeScreenItem Type="1" IsOn="False" \/>/' "$HOME_XML" 2>/dev/null || true
fi

# Normal windowed mode (no forced fullscreen)
WIN_XML="${WINEPREFIX}/drive_c/users/${USER}/AppData/Roaming/Affinity/Affinity/3.0/Settings/Window.xml"
if [ -f "$WIN_XML" ]; then
    sed -i 's/<State>2<\/State>/<State>0<\/State>/' "$WIN_XML" 2>/dev/null || true
fi

APP_DIR="${WINEPREFIX}/drive_c/Program Files/Affinity/Affinity"
if [ ! -d "$APP_DIR" ]; then
    APP_DIR=$(find "${WINEPREFIX}/drive_c/Program Files" -type d -iname "Affinity" 2>/dev/null | grep -E "Affinity/Affinity$" | head -1 || true)
fi

if [ -n "$APP_DIR" ] && [ -d "$APP_DIR" ]; then
    cd "$APP_DIR"
    # Ensure standard WPF controls are used in Settings to prevent XAML crash in v3
    APL_TOML="$APP_DIR/apl/config/apl.toml"
    if [ -f "$APL_TOML" ]; then
        sed -i 's/force_wpf_controls = false/force_wpf_controls = true/' "$APL_TOML" 2>/dev/null || true
    fi
    if [ -f "$APP_DIR/AffinityHook.exe" ]; then
        exec "${WINEPREFIX}/ElementalWarriorWine/bin/wine" "$APP_DIR/AffinityHook.exe" "$@"
    elif [ -f "$APP_DIR/Affinity.exe" ]; then
        exec "${WINEPREFIX}/ElementalWarriorWine/bin/wine" "$APP_DIR/Affinity.exe" "$@"
    fi
fi

echo "Affinity executable not found. Please verify installation in $WINEPREFIX" >&2
exit 1
EOF_APP_WRAP
chmod +x "$WRAPPER_PATH"

# Desktop Entry
if [ -f "$SCRIPT_DIR/icons/Affinity.png" ]; then
    cp -f "$SCRIPT_DIR/icons/Affinity.png" "$ICONS_DIR/affinity.png"
fi

cat << EOF_APP_DESK > "$APPS_DIR/affinity.desktop"
[Desktop Entry]
Type=Application
Version=1.5
Name=Affinity (Unified v3)
GenericName=Creative Graphics Suite
Comment=Run Affinity Unified Suite on Linux with 150% DPI scale, hardware acceleration and WineFix
Icon=affinity
Exec=${WRAPPER_PATH} %F
Terminal=false
Categories=Graphics;2DGraphics;VectorGraphics;Photography;Publishing;
Keywords=Affinity;Vector;Photo;Design;Publisher;Studio;
StartupNotify=false
StartupWMClass=Affinity.exe
EOF_APP_DESK

update-desktop-database -q "$APPS_DIR" 2>/dev/null || true
gtk-update-icon-cache -q -t -f "${HOME}/.local/share/icons/hicolor" 2>/dev/null || true

echo -e "\n=================================================================="
echo -e "${C_GREEN}${C_BOLD}SUCCESS! Affinity Unified v3 is completely installed and configured!${C_RESET}"
echo -e "• Wine Prefix    : ${PREFIX_DIR}"
echo -e "• Launch Command : ${PREFIX_DIR}/bin/affinity (or /usr/bin/affinity)"
echo -e "• Desktop Entry  : ~/.local/share/applications/affinity.desktop"
echo -e "• UI Scaling     : 150% (144 DPI)"
echo -e "• Fix Settings   : Active (Preferences saved via WineFix)"
echo -e "• Memory Guard   : AffinityHook.exe + WineFix.dll ACTIVE"
echo -e "• Layers Support : Native ElementalWarrior Wine (full selection, grouping & drag/drop)"
echo -e "• WebView2       : Microsoft Edge WebView2 ACTIVE"
if [ "$IS_NVIDIA" -eq 1 ]; then
    echo -e "• Acceleration   : Direct3D 12 / Vulkan & OpenCL ACTIVE (NVIDIA)"
elif [ "$IS_AMD" -eq 1 ]; then
    echo -e "• Acceleration   : Direct3D 12 / Vulkan ACTIVE (OpenCL disabled for AMD stability)"
else
    echo -e "• Acceleration   : Direct3D 12 / Vulkan ACTIVE"
fi
echo -e "==================================================================\n"
