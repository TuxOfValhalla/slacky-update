#!/usr/bin/env bash
# --- [ UNDERPANTS GNOMES: CACHYOS GAMING & HARDWARE MASTER SUITE ] ---

set -euo pipefail

# --- [ REPOSITORY ENDPOINTS ] ---
CACHYOS_MAIN_REPO="https://mirror.cachyos.org/repo/x86_64/cachyos"
CACHYOS_EXTRA_REPO="https://mirror.cachyos.org/repo/x86_64/cachyos-extra"
ARCH_EXTRA_REPO="https://geo.mirror.pkgbuild.com/extra/os/x86_64"
ARCH_MULTILIB_REPO="https://geo.mirror.pkgbuild.com/multilib/os/x86_64"

# --- [ GAMING SUITE REGISTRY ] ---
# Key: id | Name | Category | Primary Pkg Pattern | Lib32 Pattern | Extra Pkg Pattern | Repos
get_gaming_catalog() {
    cat << 'CATALOG_EOF'
mangohud|MangoHud (+ 32-bit Multilib & mangoapp)|engine|mangohud-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|lib32-mangohud-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|glfw-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|cachyos-extra-v3,arch-extra,arch-multilib,cachyos
gamemode|Feral GameMode (+ 32-bit Multilib & Governor)|engine|gamemode-(?:[0-9]+%3A)?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|lib32-gamemode-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||cachyos-extra-v3,arch-extra,arch-multilib,cachyos
goverlay|GOverlay (MangoHud GUI Configurator)|engine|goverlay-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||qt6pas-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|arch-extra,cachyos
vram-booster|Dynamic VRAM Booster & Foreground Shield (dmemcg)|engine|dmemcg-booster-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst||plasma-foreground-booster-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst|cachyos,chaotic-aur,arch-extra
scx|Sched-EXT SCX Schedulers, Tools & Manager|engine|scx-manager-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||scx-scheds(?:-git)?-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,scx-tools(?:-git)?-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|cachyos,arch-extra
ananicy|Ananicy-CPP & CachyOS Rules (Auto-Priority & Latency)|engine|ananicy-cpp(?:-git)?-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst||cachyos-ananicy-rules(?:-git)?-[0-9a-zA-Z_\.%:-]*\.pkg\.tar\.zst|cachyos,cachyos-extra-v3
gamescope|Gamescope (Micro-Compositor & HDR/Upscaling)|engine|gamescope-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|lib32-gamescope-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|libavif-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|cachyos,arch-extra
retroarch|RetroArch (Multi-System Emulator & Shaders)|engine|retroarch-(?:[0-9]+%3A)?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||retroarch-assets-ozone-(?:[0-9]+%3A)?[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst|arch-extra,cachyos
heroic|Heroic Games Launcher (Epic, GOG, Amazon)|launcher|heroic-games-launcher-bin-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||cachyos,arch-extra
lutris|Lutris Gaming Platform Manager|launcher|lutris(?:-git)?-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||webkit2gtk-4\.1-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libsoup3-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,python-moddb-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,python-pypresence-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,python-evdev-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,python-distro-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|cachyos,arch-extra
faugus|Faugus Launcher (Fast Proton Launcher)|launcher|faugus-launcher-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||python-vdf-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,icoextract-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,python-pefile-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|cachyos
protonplus|ProtonPlus (Wine/GE & Proton Manager)|launcher|(?:proton-plus|protonplus)-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||cachyos,arch-extra
steam|Steam (Valve Gaming Platform & Proton)|launcher|steam-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||arch-multilib,cachyos
steam-devices|Steam Controller & Gamepad Udev Rules|launcher|game-devices-udev-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||cachyos,arch-extra
lact|LACT (AMD/Intel GPU Overclocking & Fans)|hardware|lact-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||arch-extra,cachyos
openrgb|OpenRGB (Hardware RGB Lighting Control)|hardware|openrgb(?:-git)?-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||cachyos,arch-extra
solaar|Solaar (Logitech Wireless Device Manager)|hardware|solaar-(?:[0-9]+%3A)?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||python-pyudev-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,python-typing_extensions-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,python-xlib-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|arch-extra,cachyos-extra-v3,cachyos
coolercontrol|CoolerControl (All-in-One Liquid & Fan Control)|hardware|coolercontrol-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||coolercontrold-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|cachyos,arch-extra
asusctl|ASUS ROG Laptop Control Daemon & CLI|hardware|asusctl-(?:[0-9]+%3A)?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||arch-extra,cachyos
zenpower3|ZenPower AMD Ryzen Telemetry Driver (DKMS)|hardware|zenpower3-dkms-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst|||chaotic-aur,cachyos,arch-extra
v4l2loopback|V4L2 Loopback Virtual Video Device (DKMS)|hardware|v4l2loopback-dkms-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst|||arch-extra,cachyos,chaotic-aur
rtl8821cu|Realtek RTL8821CU USB Wi-Fi Driver (DKMS)|hardware|rtl8821cu-dkms-git-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst|||chaotic-aur,cachyos
rtl88x2bu|Realtek RTL88x2BU USB Wi-Fi Driver (DKMS)|hardware|rtl88x2bu-dkms-git-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst|||chaotic-aur,cachyos
rtl8812au|Realtek RTL8812AU High-Power Wi-Fi Driver (DKMS)|hardware|rtl8812au-dkms-git-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst|||chaotic-aur,cachyos
broadcom-wl|Broadcom 802.11 Linux STA Wireless Driver (DKMS)|hardware|broadcom-wl-dkms-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst|||arch-extra,cachyos
r8125|Realtek 2.5GbE Ethernet Network Driver (DKMS)|hardware|r8125-dkms-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst|||cachyos-extra-v3,cachyos-extra,cachyos
easyeffects|EasyEffects Studio Audio DSP & JackHack96 Presets|audio|easyeffects-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||lsp-plugins-lv2-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,calf-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,mda\.lv2-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,zam-plugins-lv2-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,zita-convolver-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,rnnoise-[0-9a-zA-Z_\.:-]*\.pkg\.tar\.zst,libbs2b-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,soundtouch-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libebur128-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,webrtc-audio-processing-(?:2|1)-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst,lilv-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,serd-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,sord-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,sratom-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,qt6-graphs-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,onetbb-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libmysofa-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,zix-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|arch-extra,cachyos
pear-desktop|Pear Desktop (YouTube Music with Custom Plugins)|audio|pear-desktop-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||electron42-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libjpeg-turbo-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|chaotic-aur,chaotic-cdn,arch-extra
audacity|Audacity (Digital Audio Editor & Recording Studio)|audio|audacity-(?:[0-9]+%3A)?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||suil-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,lilv-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,serd-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,sord-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,sratom-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,zix-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,portsmf-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,portaudio-(?:[0-9]+%3A)?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,portmidi-(?:[0-9]+%3A)?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libsbsms-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,vamp-plugin-sdk-(?:[0-9]+%3A)?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,soundtouch-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,twolame-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libid3tag-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libsoxr-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libmspack-(?:[0-9]+%3A)?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,wxwidgets-gtk3-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,wxwidgets-common-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libjpeg-turbo-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|arch-extra,cachyos-extra-v3,cachyos
yabridge|Yabridge (+ yabridgectl VST2/VST3 Plugin Bridge)|audio|yabridge-(?:bin-)?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||yabridgectl-(?:bin-)?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|cachyos,arch-extra,chaotic-aur
spotify|Spotify Launcher (Official Native Client Bootstrap)|audio|spotify-launcher-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||sequoia-sqv-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libayatana-appindicator-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libayatana-indicator-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,ayatana-ido-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libcurl-gnutls-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|arch-extra,cachyos,arch-core
inkscape|Inkscape (Professional Vector Graphics Editor)|creative|inkscape-(?:[0-9]+%3A)?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||lib2geom-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,double-conversion-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,graphicsmagick-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libcdr-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,poppler-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libvisio-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libwpg-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,librevenge-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|cachyos-extra-v3,arch-extra,cachyos
darktable|Darktable (Advanced RAW Photo Workflow & Editor)|creative|darktable-(?:[0-9]+%3A)?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||libavif-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libheif-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libde265-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libyuv-(?:r)?[0-9a-zA-Z_\.\+-]*\.pkg\.tar\.zst,rav1e-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,svt-av1-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,openh264-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,pugixml-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,colord-gtk-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,osm-gps-map-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,gmic-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,flickcurl-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|cachyos-extra-v3,arch-extra,cachyos
syncthing|Syncthing (Continuous P2P File Synchronization)|tools|syncthing-(?:[0-9]+%3A)?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||arch-extra,cachyos-extra-v3,cachyos
obs-studio|OBS Studio (Isolated App-Bundle & Python 3.14)|streaming|obs-studio-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst||python-3\.[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst,mbedtls-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst,obs-studio-plugin-browser-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst,cef-minimal-obs(?:-bin)?-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst,libdatachannel-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst,libjuice-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst,librist-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst,libusrsctp-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst|arch-extra,arch-core,cachyos
obs-vkcapture|OBS VKCapture (+ 32-bit Multilib Vulkan/GL)|streaming|obs-vkcapture-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|lib32-obs-vkcapture-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||cachyos,arch-extra
obs-move-transition|OBS Move Transition (Source & Scene Motion)|streaming|obs-move-transition(?:-bin|-git)?-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||chaotic-aur,cachyos-extra,cachyos
obs-source-record|OBS Source Record (Isolated ISO Track Recording)|streaming|obs-source-record(?:-bin|-git)?-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||chaotic-aur,cachyos-extra,cachyos
obs-pipewire-audio-capture|OBS PipeWire Audio Capture (Per-App Audio Routing)|streaming|obs-pipewire-audio-capture(?:-bin|-git)?-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||chaotic-aur,cachyos-extra,cachyos
obs-advanced-scene-switcher|OBS Advanced Scene Switcher (Automation Engine)|streaming|obs-advanced-scene-switcher(?:-bin|-git)?-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||opencv-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst|chaotic-aur,cachyos-extra,arch-extra,cachyos
obs-multi-rtmp|OBS Multi-RTMP (Simultaneous Multi-Streaming)|streaming|obs-multi-rtmp(?:-bin|-git)?-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||chaotic-aur,cachyos-extra,cachyos
obs-composite-blur|OBS Composite Blur (Gaussian/Box/Motion Blur)|streaming|obs-composite-blur(?:-bin|-git)?-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||chaotic-aur,cachyos-extra,cachyos
obs-teleport|OBS Teleport (Ultra-Low Latency NDI/LAN Stream)|streaming|obs-teleport(?:-bin|-git)?-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||chaotic-aur,cachyos-extra,cachyos
discord|Official Discord Linux Client|social|discord-[0-9][a-zA-Z0-9_\.:-]*\.pkg\.tar\.zst|||arch-extra,cachyos
vesktop|Vesktop (Discord Client with Vencord & Wayland Screen)|social|vesktop(?:-bin)?-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||cachyos
sunshine|Sunshine (Self-Hosted Game Stream Host)|social|sunshine-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||libayatana-appindicator-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,miniupnpc-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,numactl-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|cachyos,arch-extra
google-chrome|Google Chrome (Official Web Browser)|browser|google-chrome-[0-9a-zA-Z_\.:-]*\.pkg\.tar\.zst|||chaotic-aur,chaotic-cdn,cachyos
microsoft-edge|Microsoft Edge (Official Web Browser)|browser|microsoft-edge-(?:stable|beta|dev)-bin-[0-9a-zA-Z_\.:-]*\.pkg\.tar\.zst|||chaotic-aur,chaotic-cdn,cachyos
brave|Brave Browser (Privacy Browser with AdBlock)|browser|brave-bin-(?:1%3A)?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||cachyos,chaotic-aur,chaotic-cdn
zen-browser|Zen Browser (High-Performance Gecko Browser)|browser|zen-browser-bin-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||cachyos,chaotic-aur,chaotic-cdn
sbctl|sbctl (Secure Boot Key Manager & Signer)|bootloader|sbctl-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||arch-extra,cachyos
CATALOG_EOF
}

# --- [ HELPER FUNCTIONS ] ---
is_gaming_pkg_whitelisted() {
    local pkg_id="$1"
    # Pre-release filter toggle (strictly filter unverified/dormant packages)
    local filter_untested=true
    if [ "${filter_untested}" != "true" ]; then
        return 0
    fi

    # Always show packages if they are already installed on the system
    local cur_ver
    cur_ver=$(get_installed_gaming_pkg_version "${pkg_id}" 2>/dev/null || echo "NONE")
    if [ "${cur_ver}" != "NONE" ]; then
        return 0
    fi

    # Whitelist of verified suites for v0.14.0 Coco Jambo
    case "${pkg_id}" in
        mangohud|gamemode|goverlay|vram-booster|scx|ananicy|gamescope|retroarch|\
        heroic|lutris|faugus|protonplus|steam-devices|steam|\
        lact|openrgb|solaar|coolercontrol|asusctl|\
        zenpower3|v4l2loopback|rtl8821cu|rtl88x2bu|rtl8812au|broadcom-wl|r8125|\
        easyeffects|pear-desktop|audacity|spotify|yabridge|\
        inkscape|darktable|syncthing|\
        obs-studio|obs-vkcapture|obs-move-transition|obs-source-record|\
        obs-pipewire-audio-capture|obs-advanced-scene-switcher|obs-multi-rtmp|\
        obs-composite-blur|obs-teleport|discord|vesktop|sunshine|\
        google-chrome|microsoft-edge|brave|zen-browser|sbctl)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_vram_booster_supported() {
    # AMD and Intel GPUs have in-kernel dmemcg support
    if [ "${HAS_AMD:-false}" = "true" ] || [ "${HAS_INTEL:-false}" = "true" ]; then
        return 0
    fi

    # Check for NVIDIA GPU
    if [ "${HAS_NVIDIA:-false}" = "true" ] || [ -d /proc/driver/nvidia ] || (lspci 2>/dev/null | grep -iE 'vga|3d' | grep -qi nvidia); then
        local nv_ver="0"
        if command -v nvidia-smi >/dev/null 2>&1; then
            nv_ver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n 1 | tr -d ' ' || echo "0")
        elif [ -f /proc/driver/nvidia/version ]; then
            nv_ver=$(grep -o -E '[0-9]+\.[0-9]+(\.[0-9]+)?' /proc/driver/nvidia/version 2>/dev/null | head -n 1 || echo "0")
        elif ls /var/log/packages/cachyos-nvidia-utils-* 1>/dev/null 2>&1; then
            nv_ver=$(basename "$(ls /var/log/packages/cachyos-nvidia-utils-* 2>/dev/null | head -n 1)" | sed -E 's/cachyos-nvidia-utils-([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/' || echo "0")
        fi

        local major_ver
        major_ver=$(echo "${nv_ver}" | cut -d'.' -f1)
        if [ -n "${major_ver}" ] && [ "${major_ver}" -ge 615 ] 2>/dev/null; then
            return 0
        else
            return 1
        fi
    fi

    if uname -r | grep -qi cachyos; then
        return 0
    fi

    return 1
}

export_gaming_catalog_json() {
    local catalog_raw
    catalog_raw=$(get_gaming_catalog)

    python3 - "${catalog_raw}" << 'PYJSONEXPORT'
import sys, json, os, glob, re, shutil, subprocess

raw_catalog = sys.argv[1]
installed_pkgs = {}

# Fast cache installed packages from /var/log/packages
pkg_log_dir = "/var/log/packages"
if os.path.exists(pkg_log_dir):
    for f in os.listdir(pkg_log_dir):
        parts = f.rsplit('-', 3)
        if len(parts) >= 2:
            p_name = parts[0]
            p_ver = parts[1] if len(parts) >= 4 else "INSTALLED"
            for pref in ("underpants-", "cachyos-gnome-", "cachyos-gnome-gnome-"):
                if p_name.startswith(pref):
                    p_name = p_name[len(pref):]
            vm = re.match(r"^(.+?)-([0-9].*)$", p_name)
            if vm:
                p_name = vm.group(1)
                if p_ver.isdigit() or p_ver == "INSTALLED":
                    p_ver = vm.group(2)
            installed_pkgs[p_name.lower()] = p_ver

# Binary, driver and service probe fallback table
BINARY_MAP = {
    "mangohud": ["mangohud", "mangoapp"],
    "gamemode": ["gamemoded", "gamemoderun"],
    "goverlay": ["goverlay"],
    "vram-booster": ["dmemcg-service", "dmemcg"],
    "scx": ["scx_manager", "scx_lavd", "scx_bpfland", "scx_rusty"],
    "ananicy": ["ananicy-cpp", "ananicy"],
    "gamescope": ["gamescope"],
    "retroarch": ["retroarch"],
    "heroic": ["heroic"],
    "lutris": ["lutris"],
    "faugus": ["faugus-launcher", "faugus"],
    "protonplus": ["protonplus", "proton-plus"],
    "steam": ["steam", "/usr/bin/steam"],
    "steam-devices": ["/lib/udev/rules.d/60-steam-input.rules", "/usr/lib/udev/rules.d/60-steam-input.rules", "/etc/udev/rules.d/60-steam-input.rules"],
    "lact": ["lact", "lactd"],
    "openrgb": ["openrgb"],
    "solaar": ["solaar"],
    "coolercontrol": ["coolercontrol", "coolercontrold"],
    "asusctl": ["asusctl", "supergfxd"],
    "zenpower3": ["/var/lib/dkms/zenpower*", "/usr/src/zenpower3*"],
    "v4l2loopback": ["/var/lib/dkms/v4l2loopback*", "/usr/src/v4l2loopback*"],
    "rtl8821cu": ["/var/lib/dkms/rtl8821cu*", "/var/lib/dkms/8821cu*"],
    "rtl88x2bu": ["/var/lib/dkms/rtl88x2bu*", "/var/lib/dkms/88x2bu*"],
    "rtl8812au": ["/var/lib/dkms/rtl8812au*", "/var/lib/dkms/8812au*"],
    "broadcom-wl": ["/var/lib/dkms/broadcom-wl*", "/var/lib/dkms/wl*"],
    "r8125": ["/var/lib/dkms/r8125*"],
    "obs-studio": ["obs"],
    "obs-vkcapture": ["obs-vkcapture", "/usr/lib64/obs-plugins/linux-vkcapture.so", "/usr/lib/obs-plugins/linux-vkcapture.so"],
    "obs-move-transition": ["/usr/lib64/obs-plugins/move-transition.so", "/opt/obs-studio/lib/obs-plugins/move-transition.so"],
    "obs-source-record": ["/usr/lib64/obs-plugins/source-record.so", "/opt/obs-studio/lib/obs-plugins/source-record.so"],
    "obs-pipewire-audio-capture": ["/usr/lib64/obs-plugins/linux-pipewire-audio.so", "/opt/obs-studio/lib/obs-plugins/linux-pipewire-audio.so"],
    "obs-advanced-scene-switcher": ["/usr/lib64/obs-plugins/advanced-scene-switcher.so", "/opt/obs-studio/lib/obs-plugins/advanced-scene-switcher.so"],
    "obs-multi-rtmp": ["/usr/lib64/obs-plugins/obs-multi-rtmp.so", "/opt/obs-studio/lib/obs-plugins/obs-multi-rtmp.so"],
    "obs-composite-blur": ["/usr/lib64/obs-plugins/composite-blur.so", "/opt/obs-studio/lib/obs-plugins/composite-blur.so"],
    "obs-teleport": ["/usr/lib64/obs-plugins/obs-teleport.so", "/opt/obs-studio/lib/obs-plugins/obs-teleport.so"],
    "discord": ["discord", "/opt/discord/Discord"],
    "vesktop": ["vesktop"],
    "sunshine": ["sunshine"],
    "easyeffects": ["easyeffects"],
    "pear-desktop": ["pear-desktop"],
    "audacity": ["audacity"],
    "spotify": ["spotify"],
    "yabridge": ["yabridgectl"],
    "inkscape": ["inkscape"],
    "darktable": ["darktable"],
    "syncthing": ["syncthing"],
    "google-chrome": ["google-chrome", "google-chrome-stable"],
    "microsoft-edge": ["microsoft-edge", "microsoft-edge-stable"],
    "brave": ["brave", "brave-browser"],
    "zen-browser": ["zen-browser", "zen"],
    "sbctl": ["sbctl"]
}

for pid, cands in BINARY_MAP.items():
    if pid in installed_pkgs:
        continue
    for cand in cands:
        if cand.startswith('/'):
            if glob.glob(cand):
                installed_pkgs[pid] = "INSTALLED"
                break
        else:
            bp = shutil.which(cand) or (os.path.exists(f"/usr/bin/{cand}") and f"/usr/bin/{cand}") or (os.path.exists(f"/usr/local/bin/{cand}") and f"/usr/local/bin/{cand}")
            if bp:
                ver = "INSTALLED"
                try:
                    out = subprocess.run([bp, "--version"], capture_output=True, text=True, timeout=1).stdout
                    vm = re.search(r'([0-9]+\.[0-9]+(?:\.[0-9]+)?)', out)
                    if vm:
                        ver = vm.group(1)
                except Exception:
                    pass
                installed_pkgs[pid] = ver
                break

CATEGORY_TITLES = {
    "engine": "The Engine: Performance, HUD & Schedulers",
    "launcher": "Storefronts & Launcher Managers",
    "hardware": "Hardware Control, Tuning & DKMS Drivers",
    "streaming": "OBS Studio & Video Recording Plugins",
    "audio": "Studio Audio DSP & Acoustic Processing",
    "creative": "Creative, 3D & Photography Studio",
    "social": "Voice Chat, Community & Game Streaming",
    "tools": "Power Tools & Media Sync",
    "browser": "Web Navigators & Browsers",
    "bootloader": "Secure Boot & UEFI Utilities"
}

CATEGORY_ICONS = {
    "engine": "utilities-system-monitor",
    "launcher": "applications-games",
    "hardware": "preferences-system",
    "streaming": "obs-studio",
    "audio": "audio-card",
    "creative": "applications-graphics",
    "social": "user-available",
    "tools": "system-file-manager",
    "browser": "applications-internet",
    "bootloader": "system-lock-screen"
}

PKG_DESCRIPTIONS = {
    "mangohud": "High-performance Vulkan/OpenGL overlay with hardware telemetry and mangoapp integration.",
    "gamemode": "Feral GameMode auto-governor prioritizing games and multilib 32-bit processes.",
    "goverlay": "Graphical Qt6 configurator for MangoHud, vkBasalt, and ReplaySorcery.",
    "vram-booster": "Dynamic VRAM cgroups booster prioritizing GPU memory for active game windows.",
    "scx": "Sched-EXT eBPF user-space CPU schedulers and manager for minimal frame latency.",
    "ananicy": "Auto-nice daemon applying CachyOS latency and priority rules to gaming workloads.",
    "gamescope": "Valve SteamOS micro-compositor with HDR, integer scaling, and FSR upscaling.",
    "retroarch": "Multi-system game emulator frontend with Ozone/XMB shaders and PipeWire audio.",
    "heroic": "Native Epic Games, GOG, and Amazon Games launcher manager.",
    "lutris": "Open gaming platform managing Wine, Proton, emulators, and runner prefixes.",
    "faugus": "Ultra-fast lightweight Proton game launcher.",
    "protonplus": "Modern Wine-GE, Proton-GE, and compatibility tool manager.",
    "steam": "Official Valve Steam platform launcher & Proton compatibility runtime client.",
    "steam-devices": "Gamepad and controller udev hardware rules for Steam, DualSense, Xbox & Switch.",
    "lact": "AMD & Intel Linux GPU overclocking, fan curve, and power state manager.",
    "openrgb": "Universal RGB lighting control suite supporting hundreds of hardware devices.",
    "solaar": "Logitech Unifying and Lightspeed receiver and device configuration utility.",
    "coolercontrol": "Liquid cooling, fan speed curves, and AIO pump control daemon & GUI.",
    "asusctl": "ASUS ROG and TUF laptop performance profile, fan, and aura LED control CLI & daemon.",
    "zenpower3": "AMD Ryzen Zen 1-5 voltage, current, and core telemetry driver for MangoHud (DKMS).",
    "v4l2loopback": "Video4Linux2 virtual loopback device driver for OBS Virtual Camera (DKMS).",
    "rtl8821cu": "Realtek RTL8821CU USB Wi-Fi network adapter driver (DKMS).",
    "rtl88x2bu": "Realtek RTL88x2BU USB Wi-Fi network adapter driver (DKMS).",
    "rtl8812au": "Realtek RTL8812AU high-power USB Wi-Fi network adapter driver (DKMS).",
    "broadcom-wl": "Broadcom 802.11a/b/g/n wireless network adapter driver (DKMS).",
    "r8125": "Realtek PCIe 2.5 Gigabit Ethernet network adapter driver (DKMS).",
    "obs-studio": "Professional open source video recording and live streaming studio app-bundle.",
    "obs-vkcapture": "OBS Vulkan and OpenGL game capture layer with 32-bit multilib support.",
    "obs-move-transition": "Smooth movement animations for OBS sources and scene elements.",
    "obs-source-record": "Isolated track and clean ISO video recording filter for OBS Studio.",
    "obs-pipewire-audio-capture": "Direct per-application audio source capture and routing for OBS.",
    "obs-advanced-scene-switcher": "Advanced automated scene switcher and automation macro engine for OBS.",
    "obs-multi-rtmp": "Simultaneous live streaming to multiple platforms (Twitch, YouTube, Kick).",
    "obs-composite-blur": "GPU-accelerated box, Gaussian, and motion blur filter for OBS.",
    "obs-teleport": "Ultra-low latency LAN/NDI video streaming across local networks.",
    "discord": "Official Discord Linux voice and text chat client.",
    "vesktop": "Custom Discord client with Vencord plugins and Wayland screen share.",
    "sunshine": "Self-hosted low-latency game stream host for Moonlight streaming.",
    "easyeffects": "Studio-grade PipeWire audio DSP with JackHack96 presets and equalizer.",
    "pear-desktop": "YouTube Music client with custom audio plugins and equalizer.",
    "audacity": "Multi-track audio editor and digital recording workstation.",
    "spotify": "Official Spotify native Linux client bootstrap with Sequoia verification.",
    "yabridge": "Modern VST2/VST3/CLAP Windows audio plugin bridge for Linux DAWs.",
    "inkscape": "Professional vector graphics editor for illustration and design.",
    "darktable": "Professional RAW photography workflow application and virtual lighttable.",
    "syncthing": "Continuous decentralized peer-to-peer file synchronization service.",
    "google-chrome": "Official Google Chrome web browser.",
    "microsoft-edge": "Official Microsoft Edge web browser.",
    "brave": "Privacy-focused web browser with built-in ad and tracker blocking.",
    "zen-browser": "High-performance Firefox Gecko-based web browser with split-views.",
    "sbctl": "UEFI Secure Boot key manager, enrollment, and file signing utility."
}

items = []
for line in raw_catalog.strip().split("\n"):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    parts = line.split("|")
    if len(parts) < 3:
        continue
    pkg_id, name, cat = parts[0], parts[1], parts[2]
    
    inst_ver = "NONE"
    for cand in (pkg_id, f"underpants-{pkg_id}", f"cachyos-gnome-{pkg_id}"):
        if cand in installed_pkgs:
            inst_ver = installed_pkgs[cand]
            break
    
    desc = PKG_DESCRIPTIONS.get(pkg_id, f"High-performance native workstation component ({name})")
    cat_title = CATEGORY_TITLES.get(cat, cat.capitalize())
    cat_icon = CATEGORY_ICONS.get(cat, "package-x-generic")

    items.append({
        "id": pkg_id,
        "name": name,
        "category": cat,
        "category_title": cat_title,
        "category_icon": cat_icon,
        "installed_version": inst_ver,
        "is_installed": (inst_ver != "NONE"),
        "description": desc
    })

print(json.dumps(items, indent=2))
PYJSONEXPORT
}

is_elf_binary() {
    [ -f "$1" ] || return 1
    local magic
    magic=$(head -c 4 "$1" 2>/dev/null || true)
    [[ "${magic}" == $'\x7fELF' ]]
}

audit_user_hardware_groups() {
    local target_user="${SUDO_USER:-${USER:-}}"
    [ -n "${target_user}" ] || return 0
    [ "${target_user}" != "root" ] || return 0

    local needed_groups=("input" "plugdev" "video" "audio" "uucp")
    local missing_groups=()

    for grp in "${needed_groups[@]}"; do
        if getent group "${grp}" >/dev/null 2>&1; then
            if ! id -nG "${target_user}" 2>/dev/null | grep -qw "${grp}"; then
                missing_groups+=("${grp}")
            fi
        fi
    done

    if [ "${#missing_groups[@]}" -gt 0 ]; then
        log_info "Hardware Access Check: User '${target_user}' is missing from groups: ${missing_groups[*]}"
        echo -n "Would you like to add '${target_user}' to these groups for unprivileged device access? [Y/n]: "
        read -r reply_grp
        reply_grp=${reply_grp:-Y}
        if [[ "${reply_grp}" =~ ^[YyJjSsOo]$ ]]; then
            validate_privileges
            local grp_csv
            grp_csv=$(IFS=,; echo "${missing_groups[*]}")
            sudo usermod -a -G "${grp_csv}" "${target_user}" 2>/dev/null || true
            log_success "Added '${target_user}' to groups: ${missing_groups[*]} (takes effect on next login)."
        fi
    fi
}

audit_multilib_readiness() {
    local pkg_id="$1"
    if [ "${pkg_id}" = "gamemode" ] || [ "${pkg_id}" = "mangohud" ] || [ "${pkg_id}" = "obs-vkcapture" ] || [ "${pkg_id}" = "yabridge" ] || [ "${pkg_id}" = "steam" ]; then
        if ! ls /var/log/packages/*multilib* >/dev/null 2>&1 && \
           ! ls /var/log/packages/*compat32* >/dev/null 2>&1 && \
           [ ! -f /lib/libc.so.6 ] && [ ! -f /lib/ld-linux.so.2 ] && \
           [ ! -f /usr/lib/libc.so.6 ] && [ ! -f /usr/lib/libc.so ]; then
            log_warn "Notice: 32-bit Multilib is not detected on this system."
            log_warn "32-bit libraries for ${pkg_id} will be deployed, but 32-bit games require Slackware Multilib."
            log_info "Tip: Alien Bob's multilib repository provides 32-bit compatibility for Slackware x86_64."
        fi
    fi
}

# --- [ PACKAGE STATUS RESOLUTION ] ---
get_installed_gaming_pkg_version() {
    local pkg_id="$1"
    python3 - "${pkg_id}" << 'PYPKGVERCHECK'
import sys, os, re, glob, shutil, subprocess

target_id = sys.argv[1].lower()
pkg_dir = '/var/log/packages'
found = []

if os.path.exists(pkg_dir):
    for f in os.listdir(pkg_dir):
        parts = f.rsplit('-', 3)
        if len(parts) >= 2:
            p_name = parts[0].lower()
            p_ver = parts[1] if len(parts) >= 4 else "INSTALLED"
            for pref in ("underpants-", "cachyos-gnome-", "cachyos-gnome-gnome-"):
                if p_name.startswith(pref):
                    p_name = p_name[len(pref):]
            vm = re.match(r"^(.+?)-([0-9].*)$", p_name)
            if vm:
                p_name = vm.group(1)
                if p_ver.isdigit() or p_ver == "INSTALLED":
                    p_ver = vm.group(2)
            if p_name == target_id:
                found.append(p_ver)

if found:
    print(found[-1])
    sys.exit(0)

# Binary probe fallback
BINARY_MAP = {
    "mangohud": ["mangohud", "mangoapp"],
    "gamemode": ["gamemoded", "gamemoderun"],
    "goverlay": ["goverlay"],
    "vram-booster": ["dmemcg-service", "dmemcg"],
    "scx": ["scx_manager", "scx_lavd", "scx_bpfland", "scx_rusty"],
    "ananicy": ["ananicy-cpp", "ananicy"],
    "gamescope": ["gamescope"],
    "retroarch": ["retroarch"],
    "heroic": ["heroic"],
    "lutris": ["lutris"],
    "faugus": ["faugus-launcher", "faugus"],
    "protonplus": ["protonplus", "proton-plus"],
    "steam": ["steam", "/usr/bin/steam"],
    "steam-devices": ["/lib/udev/rules.d/60-steam-input.rules", "/usr/lib/udev/rules.d/60-steam-input.rules", "/etc/udev/rules.d/60-steam-input.rules"],
    "lact": ["lact", "lactd"],
    "openrgb": ["openrgb"],
    "solaar": ["solaar"],
    "coolercontrol": ["coolercontrol", "coolercontrold"],
    "asusctl": ["asusctl", "supergfxd"],
    "zenpower3": ["/var/lib/dkms/zenpower*", "/usr/src/zenpower3*"],
    "v4l2loopback": ["/var/lib/dkms/v4l2loopback*", "/usr/src/v4l2loopback*"],
    "rtl8821cu": ["/var/lib/dkms/rtl8821cu*", "/var/lib/dkms/8821cu*"],
    "rtl88x2bu": ["/var/lib/dkms/rtl88x2bu*", "/var/lib/dkms/88x2bu*"],
    "rtl8812au": ["/var/lib/dkms/rtl8812au*", "/var/lib/dkms/8812au*"],
    "broadcom-wl": ["/var/lib/dkms/broadcom-wl*", "/var/lib/dkms/wl*"],
    "r8125": ["/var/lib/dkms/r8125*"],
    "obs-studio": ["obs"],
    "obs-vkcapture": ["obs-vkcapture", "/usr/lib64/obs-plugins/linux-vkcapture.so", "/usr/lib/obs-plugins/linux-vkcapture.so"],
    "obs-move-transition": ["/usr/lib64/obs-plugins/move-transition.so", "/opt/obs-studio/lib/obs-plugins/move-transition.so"],
    "obs-source-record": ["/usr/lib64/obs-plugins/source-record.so", "/opt/obs-studio/lib/obs-plugins/source-record.so"],
    "obs-pipewire-audio-capture": ["/usr/lib64/obs-plugins/linux-pipewire-audio.so", "/opt/obs-studio/lib/obs-plugins/linux-pipewire-audio.so"],
    "obs-advanced-scene-switcher": ["/usr/lib64/obs-plugins/advanced-scene-switcher.so", "/opt/obs-studio/lib/obs-plugins/advanced-scene-switcher.so"],
    "obs-multi-rtmp": ["/usr/lib64/obs-plugins/obs-multi-rtmp.so", "/opt/obs-studio/lib/obs-plugins/obs-multi-rtmp.so"],
    "obs-composite-blur": ["/usr/lib64/obs-plugins/composite-blur.so", "/opt/obs-studio/lib/obs-plugins/composite-blur.so"],
    "obs-teleport": ["/usr/lib64/obs-plugins/obs-teleport.so", "/opt/obs-studio/lib/obs-plugins/obs-teleport.so"],
    "discord": ["discord", "/opt/discord/Discord"],
    "vesktop": ["vesktop"],
    "sunshine": ["sunshine"],
    "easyeffects": ["easyeffects"],
    "pear-desktop": ["pear-desktop"],
    "audacity": ["audacity"],
    "spotify": ["spotify"],
    "yabridge": ["yabridgectl"],
    "inkscape": ["inkscape"],
    "darktable": ["darktable"],
    "syncthing": ["syncthing"],
    "google-chrome": ["google-chrome", "google-chrome-stable"],
    "microsoft-edge": ["microsoft-edge", "microsoft-edge-stable"],
    "brave": ["brave", "brave-browser"],
    "zen-browser": ["zen-browser", "zen"],
    "sbctl": ["sbctl"]
}

if target_id in BINARY_MAP:
    for cand in BINARY_MAP[target_id]:
        if cand.startswith('/'):
            if glob.glob(cand):
                print("INSTALLED")
                sys.exit(0)
        else:
            bp = shutil.which(cand) or (os.path.exists(f"/usr/bin/{cand}") and f"/usr/bin/{cand}") or (os.path.exists(f"/usr/local/bin/{cand}") and f"/usr/local/bin/{cand}")
            if bp:
                ver = "INSTALLED"
                try:
                    out = subprocess.run([bp, "--version"], capture_output=True, text=True, timeout=1).stdout
                    vm = re.search(r'([0-9]+\.[0-9]+(?:\.[0-9]+)?)', out)
                    if vm:
                        ver = vm.group(1)
                except Exception:
                    pass
                print(ver)
                sys.exit(0)

print("NONE")
PYPKGVERCHECK
}

check_all_installed_gaming_updates_fast() {
    local catalog_raw
    catalog_raw=$(get_gaming_catalog 2>/dev/null || echo "")
    python3 - "${catalog_raw}" << 'PYFASTCHECK'
import sys, os, re, time, datetime, json, urllib.request, urllib.parse, hashlib, concurrent.futures

raw_catalog_lines = sys.argv[1].strip().splitlines()

def get_cache_dir():
    for d in ['/var/cache/slacky-update', os.path.expanduser('~/.cache/slacky-update'), '/tmp/slacky-update-cache']:
        try:
            os.makedirs(d, exist_ok=True)
            test_f = os.path.join(d, '.write_test')
            with open(test_f, 'w') as f: f.write('1')
            os.remove(test_f)
            return d
        except Exception:
            continue
    return '/tmp'

cache_dir = get_cache_dir()

def get_chaotic_fastest_mirror(cdir):
    m_file = os.path.join(cdir, 'chaotic_fastest_mirror.json')
    now = time.time()
    today_dt = datetime.datetime.now()
    is_thursday = (today_dt.weekday() == 3)
    today_str = today_dt.strftime('%Y-%m-%d')

    if os.path.exists(m_file):
        try:
            with open(m_file, 'r', encoding='utf-8') as f:
                d = json.load(f)
            cached_m = d.get('mirror')
            last_ts = d.get('timestamp', 0)
            last_day = d.get('date', '')
            if last_day == today_str and cached_m:
                return cached_m
            elif not is_thursday and (now - last_ts) < (7 * 86400) and cached_m:
                return cached_m
        except Exception:
            pass

    return 'https://cdn-mirror.chaotic.cx/chaotic-aur/x86_64/'

chaotic_fastest = get_chaotic_fastest_mirror(cache_dir)

repos = {
    "cachyos": "https://mirror.cachyos.org/repo/x86_64/cachyos/",
    "cachyos-v3": "https://mirror.cachyos.org/repo/x86_64_v3/cachyos-v3/",
    "cachyos-extra": "https://mirror.cachyos.org/repo/x86_64/cachyos-extra/",
    "cachyos-extra-v3": "https://mirror.cachyos.org/repo/x86_64_v3/cachyos-extra-v3/",
    "chaotic-aur": chaotic_fastest,
    "chaotic-cdn": "https://cdn-mirror.chaotic.cx/chaotic-aur/x86_64/",
    "arch-core": "https://geo.mirror.pkgbuild.com/core/os/x86_64/",
    "arch-extra": "https://geo.mirror.pkgbuild.com/extra/os/x86_64/",
    "arch-multilib": "https://geo.mirror.pkgbuild.com/multilib/os/x86_64/"
}

catalog = {}
for line in raw_catalog_lines:
    if not line.strip() or line.strip().startswith('#'):
        continue
    left_parts = line.split("|", 3)
    if len(left_parts) >= 4:
        pid, name, cat, remainder = left_parts
        right_parts = remainder.rsplit("|", 3)
        if len(right_parts) == 4:
            main_pat, l32_pat, ext_pat, repos_str = right_parts
            r_list = [r.strip() for r in repos_str.split(",") if r.strip()]
            href_pat = rf'href=[\'\"]?({main_pat})[\'\"]?' if main_pat else None
            catalog[pid] = (name, href_pat, r_list)

def fetch_url_cached(url, cdir, ttl=1800):
    url_hash = hashlib.sha256(url.encode('utf-8')).hexdigest()[:16]
    cache_file = os.path.join(cdir, f'repo_idx_{url_hash}.html')
    now = time.time()
    if os.path.exists(cache_file):
        try:
            mtime = os.path.getmtime(cache_file)
            if (now - mtime) < ttl:
                with open(cache_file, 'r', encoding='utf-8', errors='ignore') as f:
                    return f.read()
        except Exception:
            pass
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64)"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            content = resp.read().decode("utf-8", errors="ignore")
            try:
                with open(cache_file, 'w', encoding='utf-8', errors='ignore') as f:
                    f.write(content)
            except Exception:
                pass
            return content
    except Exception:
        return ""

def clean_pkg_version(pid, raw_v):
    v = urllib.parse.unquote(str(raw_v))
    v = re.sub(r'\.pkg\.tar\.(?:zst|xz|gz)$', '', v)
    v = re.sub(r'-(?:x86_64(?:_v[0-9]+)?|noarch|i[3-6]86|any|aarch64)(?:-[0-9a-zA-Z_]+)?$', '', v)
    v = re.sub(r'-[0-9]+(?:\.[0-9]+)?$', '', v)
    v = re.sub(r'^[0-9]+(?:%3A|:|_)', '', v)
    if pid:
        pid_clean = pid.replace("-", "")
        v = re.sub(rf'^(?:underpants-|cachyos-gnome-)?(?:{re.escape(pid)}|{re.escape(pid_clean)})(?:-bin|-git|-manager|-launcher|-rules|-udev)?-', '', v, flags=re.IGNORECASE)
    v = re.sub(r'^[a-zA-Z0-9_\-+]+?-([0-9])', r'\1', v)
    return v

def parse_version_key(v_str):
    clean = clean_pkg_version('', v_str)
    parts = re.split(r'[-._+~]', clean)
    res = []
    for p in parts:
        if p.isdigit():
            res.append((0, int(p), ''))
        else:
            num = ''.join(c for c in p if c.isdigit())
            res.append((1, int(num) if num else 0, p))
    return res

def is_strictly_greater(v1, v2):
    return parse_version_key(v1) > parse_version_key(v2)

pkg_log_dir = "/var/log/packages"
installed_pkgs = os.listdir(pkg_log_dir) if os.path.exists(pkg_log_dir) else []

def parse_installed_pkg(pkg):
    clean = re.sub(r'\.(t[xg]z|tlz)$', '', pkg)
    m = re.match(r'^(.*?)-([0-9][a-zA-Z0-9_\.:~-]*)-(?:x86_64(?:_v[0-9]+)?|i[3-6]86|noarch|arm|aarch64)-[0-9a-zA-Z_]+$', clean)
    if m:
        name = m.group(1)
        ver = m.group(2)
        ver = re.sub(r'-[0-9]+(?:\.[0-9]+)?$', '', ver)
        ver = re.sub(r'^[0-9]+(?:%3A|:|_)', '', ver)
        return name, ver
    return clean, 'NONE'

detected_installed = {}
for pkg in installed_pkgs:
    name, ver = parse_installed_pkg(pkg)
    if ver == 'NONE':
        continue
    for pid in catalog:
        if name in (f"underpants-{pid}", f"cachyos-gnome-{pid}", f"cachyos-gnome-gnome-{pid}", pid, f"{pid}-bin", f"{pid}-git", f"{pid}-manager", f"{pid}-launcher"):
            detected_installed[pid] = ver

needed_repos = set()
for pid in detected_installed:
    if pid in catalog:
        _, pat, r_list = catalog[pid]
        if pat:
            for rk in r_list:
                u = repos.get(rk)
                if u:
                    needed_repos.add(u)

with concurrent.futures.ThreadPoolExecutor(max_workers=min(max(len(needed_repos), 1), 8)) as ex:
    repo_contents = dict(zip(needed_repos, ex.map(lambda u: fetch_url_cached(u, cache_dir), needed_repos)))

def check_single_package(pid, cur_ver):
    if pid not in catalog:
        return None
    name, pat, r_list = catalog[pid]
    if not pat or pid == "steam-devices":
        return None
    all_candidates = []
    for rk in r_list:
        base_u = repos.get(rk, "")
        html = repo_contents.get(base_u, "")
        if not html:
            continue
        try:
            matches = re.findall(pat, html)
        except Exception:
            matches = []
        if matches:
            for m in matches:
                raw_pkg = m[0] if isinstance(m, tuple) else m
                cv = clean_pkg_version(pid, raw_pkg)
                if cv:
                    all_candidates.append(cv)
    if all_candidates:
        all_candidates.sort(key=parse_version_key)
        best_ver = all_candidates[-1]
        if is_strictly_greater(best_ver, cur_ver):
            return f"{name} {best_ver} (Installed: {cur_ver})"
    return None

updates = []
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
    futures = [ex.submit(check_single_package, pid, ver) for pid, ver in detected_installed.items()]
    for f in concurrent.futures.as_completed(futures):
        res = f.result()
        if res:
            updates.append(res)

for u in sorted(updates):
    print(u)
PYFASTCHECK
}

resolve_cachyos_gaming_upstream_metadata() {
    local pkg_id="$1"
    
    python3 - "${pkg_id}" << 'PYRESOLVE'
import sys, os, re, time, datetime, json, urllib.request, urllib.parse, hashlib, concurrent.futures

pkg_id = sys.argv[1]

if pkg_id == "steam-devices":
    print("1.0.0.61 BUNDLED NONE NONE")
    sys.exit(0)

def get_cache_dir():
    for d in ['/var/cache/slacky-update', os.path.expanduser('~/.cache/slacky-update'), '/tmp/slacky-update-cache']:
        try:
            os.makedirs(d, exist_ok=True)
            test_f = os.path.join(d, '.write_test')
            with open(test_f, 'w') as f: f.write('1')
            os.remove(test_f)
            return d
        except Exception:
            continue
    return '/tmp'

cache_dir = get_cache_dir()

def get_chaotic_fastest_mirror(cdir):
    m_file = os.path.join(cdir, 'chaotic_fastest_mirror.json')
    now = time.time()
    today_dt = datetime.datetime.now()
    is_thursday = (today_dt.weekday() == 3)
    today_str = today_dt.strftime('%Y-%m-%d')

    if os.path.exists(m_file):
        try:
            with open(m_file, 'r', encoding='utf-8') as f:
                d = json.load(f)
            cached_m = d.get('mirror')
            last_ts = d.get('timestamp', 0)
            last_day = d.get('date', '')
            if last_day == today_str and cached_m:
                return cached_m
            elif not is_thursday and (now - last_ts) < (7 * 86400) and cached_m:
                return cached_m
        except Exception:
            pass

    mirrors = [
        'https://cdn-mirror.chaotic.cx/chaotic-aur/x86_64/',
        'https://geo-mirror.chaotic.cx/chaotic-aur/x86_64/',
        'https://de-1-mirror.chaotic.cx/chaotic-aur/x86_64/',
        'https://de-2-mirror.chaotic.cx/chaotic-aur/x86_64/',
        'https://de-4-mirror.chaotic.cx/chaotic-aur/x86_64/',
        'https://es-mirror.chaotic.cx/chaotic-aur/x86_64/',
        'https://bg-mirror.chaotic.cx/chaotic-aur/x86_64/',
        'https://nl-1-mirror.chaotic.cx/chaotic-aur/x86_64/',
        'https://fr-1-mirror.chaotic.cx/chaotic-aur/x86_64/',
        'https://ca-mirror.chaotic.cx/chaotic-aur/x86_64/',
        'https://us-mi-mirror.chaotic.cx/chaotic-aur/x86_64/',
        'https://us-ut-mirror.chaotic.cx/chaotic-aur/x86_64/'
    ]

    def ping_m(u):
        t0 = time.time()
        try:
            req = urllib.request.Request(u + 'chaotic-mirrorlist.pkg.tar.zst', headers={'User-Agent': 'Mozilla/5.0', 'Range': 'bytes=0-256'})
            with urllib.request.urlopen(req, timeout=1.8) as resp:
                resp.read(256)
                return ((time.time() - t0) * 1000, u)
        except Exception:
            return (999999, u)

    best_url = 'https://cdn-mirror.chaotic.cx/chaotic-aur/x86_64/'
    best_lat = 999999
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=len(mirrors)) as ex:
            results = list(ex.map(ping_m, mirrors))
        valid = [r for r in results if r[0] < 90000]
        if valid:
            valid.sort(key=lambda x: x[0])
            best_lat, best_url = valid[0]
    except Exception:
        pass

    try:
        with open(m_file, 'w', encoding='utf-8') as f:
            json.dump({
                'mirror': best_url,
                'latency_ms': round(best_lat, 2) if best_lat < 90000 else None,
                'timestamp': now,
                'date': today_str,
                'day_of_week': today_dt.strftime('%A')
            }, f, indent=2)
    except Exception:
        pass

    return best_url

chaotic_fastest = get_chaotic_fastest_mirror(cache_dir)

repos = {
    "cachyos": "https://mirror.cachyos.org/repo/x86_64/cachyos/",
    "cachyos-v3": "https://mirror.cachyos.org/repo/x86_64_v3/cachyos-v3/",
    "cachyos-extra": "https://mirror.cachyos.org/repo/x86_64/cachyos-extra/",
    "cachyos-extra-v3": "https://mirror.cachyos.org/repo/x86_64_v3/cachyos-extra-v3/",
    "chaotic-aur": chaotic_fastest,
    "chaotic-cdn": "https://cdn-mirror.chaotic.cx/chaotic-aur/x86_64/",
    "arch-core": "https://geo.mirror.pkgbuild.com/core/os/x86_64/",
    "arch-extra": "https://geo.mirror.pkgbuild.com/extra/os/x86_64/",
    "arch-multilib": "https://geo.mirror.pkgbuild.com/multilib/os/x86_64/"
}

catalog = {
    "mangohud": (r'href=[\'\"]?(mangohud-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', r'href=[\'\"]?(lib32-mangohud-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', r'href=[\'\"]?(glfw-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["cachyos-extra-v3", "arch-extra", "cachyos"], ["arch-multilib", "cachyos"]),
    "gamemode": (r'href=[\'\"]?(gamemode-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', r'href=[\'\"]?(lib32-gamemode-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, ["cachyos-extra-v3", "arch-extra", "cachyos"], ["arch-multilib", "cachyos"]),
    "goverlay": (r'href=[\'\"]?(goverlay-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, r'href=[\'\"]?(qt6pas-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["arch-extra", "cachyos"], []),
    "scx": (r'href=[\'\"]?(scx-manager-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(scx-scheds(?:-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(scx-tools(?:-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["cachyos", "arch-extra"], []),
    "easyeffects": (r'href=[\'\"]?(easyeffects-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(lsp-plugins-lv2-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(calf-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(mda\.lv2-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(zam-plugins-lv2-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(zita-convolver-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(rnnoise-(?:1%3A|1:)?([0-9a-zA-Z_\.:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libbs2b-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(soundtouch-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libebur128-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(webrtc-audio-processing-(?:2|1)-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(lilv-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(serd-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(sord-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(sratom-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(qt6-graphs-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(onetbb-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libmysofa-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(zix-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["arch-extra", "cachyos", "arch-core"], []),
    "pear-desktop": (r'href=[\'\"]?(pear-desktop-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(electron42-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libjpeg-turbo-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["chaotic-aur", "chaotic-cdn", "arch-extra"], []),
    "yabridge": (r'href=[\'\"]?(yabridge-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', r'href=[\'\"]?(lib32-yabridge-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', r'href=[\'\"]?(yabridgectl-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["arch-extra", "cachyos", "chaotic-aur"], ["arch-multilib", "cachyos"]),
    "audacity": (r'href=[\'\"]?(audacity-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(suil-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(lilv-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(serd-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(sord-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(sratom-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(zix-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(portsmf-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(portaudio-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(portmidi-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libsbsms-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(vamp-plugin-sdk-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(soundtouch-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(twolame-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libid3tag-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libsoxr-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libmspack-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(wxwidgets-gtk3-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(wxwidgets-common-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libjpeg-turbo-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["arch-extra", "cachyos-extra-v3", "cachyos", "arch-core"], []),
    "spotify": (r'href=[\'\"]?(spotify(?:-launcher)?-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(sequoia-sqv-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libayatana-appindicator-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libayatana-indicator-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(ayatana-ido-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libcurl-gnutls-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["arch-extra", "cachyos-extra-v3", "cachyos", "arch-core"], []),
    "inkscape": (r'href=[\'\"]?(inkscape-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(lib2geom-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(double-conversion-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(graphicsmagick-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libcdr-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(poppler-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libvisio-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libwpg-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(librevenge-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["cachyos-extra-v3", "arch-extra", "cachyos"], []),
    "darktable": (r'href=[\'\"]?(darktable-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(libavif-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libheif-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libde265-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libyuv-((?:r[0-9]+|[0-9])[a-zA-Z0-9_\.\+%-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(rav1e-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(svt-av1-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(openh264-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(pugixml-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(colord-gtk-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(osm-gps-map-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(gmic-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(flickcurl-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["cachyos-extra-v3", "arch-extra", "cachyos"], []),
    "syncthing": (r'href=[\'\"]?(syncthing-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-extra", "cachyos-extra-v3", "cachyos"], []),
    "ananicy": (r'href=[\'\"]?(ananicy-cpp(?:-git)?-([0-9a-zA-Z_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(cachyos-ananicy-rules(?:-git)?-([0-9a-zA-Z_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libbpf-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["cachyos", "cachyos-extra-v3", "arch-core"], []),
    "gamescope": (r'href=[\'\"]?(gamescope-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', r'href=[\'\"]?(lib32-gamescope-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', r'href=[\'\"]?(libavif-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["cachyos", "arch-extra"], ["cachyos", "arch-multilib"]),
    "heroic": (r'href=[\'\"]?(heroic-games-launcher-bin-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos", "arch-extra"], []),
    "lutris": (r'href=[\'\"]?(lutris(?:-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(webkit2gtk-4\.1-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libsoup3-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(python-moddb-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(python-pypresence-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(python-evdev-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(python-distro-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["arch-extra", "cachyos", "arch-core", "cachyos-extra-v3"], []),
    "faugus": (r'href=[\'\"]?(faugus-launcher-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(python-vdf-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(icoextract-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(python-pefile-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["cachyos", "arch-extra"], []),
    "protonplus": (r'href=[\'\"]?((?:proton-plus|protonplus)-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos", "arch-extra"], []),
    "steam": (r'href=[\'\"]?(steam-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-multilib", "cachyos"], []),
    "steam-devices": (None, None, None, [], []),
    "retroarch": (r'href=[\'\"]?(retroarch-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, r'href=[\'\"]?(retroarch-assets-ozone-(?:[0-9]+%3A)?([0-9a-zA-Z_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["arch-extra", "cachyos"], []),
    "lact": (r'href=[\'\"]?(lact-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-extra", "cachyos"], []),
    "openrgb": (r'href=[\'\"]?(openrgb(?:-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos", "arch-extra"], []),
    "solaar": (r'href=[\'\"]?(solaar-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(python-pyudev-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(python-typing_extensions-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(python-xlib-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["arch-extra", "cachyos-extra-v3", "cachyos"], []),
    "coolercontrol": (r'href=[\'\"]?(coolercontrol-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, r'href=[\'\"]?(coolercontrold-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["cachyos", "arch-extra"], []),
    "asusctl": (r'href=[\'\"]?(asusctl-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-extra", "cachyos"], []),
    "brave": (r'href=[\'\"]?(brave-bin-(?:1%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos", "chaotic-aur", "chaotic-cdn"], []),
    "zen-browser": (r'href=[\'\"]?(zen-browser-bin-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos", "chaotic-aur", "chaotic-cdn"], []),
    "google-chrome": (r'href=[\'\"]?(google-chrome-([0-9][a-zA-Z0-9_\.:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "chaotic-cdn", "cachyos"], []),
    "microsoft-edge": (r'href=[\'\"]?(microsoft-edge-(?:stable|beta|dev)-bin-([0-9][a-zA-Z0-9_\.:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "chaotic-cdn", "cachyos"], []),
    "obs-studio": (r'href=[\'\"]?(obs-studio-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(python-(3\.[0-9a-zA-Z_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(mbedtls-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(obs-studio-plugin-browser-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(cef-minimal-obs(?:-bin)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libdatachannel-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libjuice-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(librist-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libusrsctp-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["arch-extra", "cachyos", "cachyos-extra-v3", "chaotic-aur", "arch-core"], []),
    "discord": (r'href=[\'\"]?(discord-(?:[0-9]+%3A|[0-9]+:)?([0-9][a-zA-Z0-9_\.:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-extra", "cachyos"], []),
    "vesktop": (r'href=[\'\"]?(vesktop(?:-bin)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos"], []),
    "obs-vkcapture": (r'href=[\'\"]?(obs-vkcapture-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', r'href=[\'\"]?(lib32-obs-vkcapture-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, ["cachyos", "arch-extra"], ["cachyos", "arch-multilib"]),
    "obs-move-transition": (r'href=[\'\"]?(obs-move-transition(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos-extra", "cachyos"], []),
    "obs-source-record": (r'href=[\'\"]?(obs-source-record(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos-extra", "cachyos"], []),
    "obs-pipewire-audio-capture": (r'href=[\'\"]?(obs-pipewire-audio-capture(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos-extra", "cachyos"], []),
    "obs-advanced-scene-switcher": (r'href=[\'\"]?(obs-advanced-scene-switcher(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(opencv-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["chaotic-aur", "cachyos-extra", "arch-extra", "cachyos"], []),
    "obs-multi-rtmp": (r'href=[\'\"]?(obs-multi-rtmp(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos-extra", "cachyos"], []),
    "obs-composite-blur": (r'href=[\'\"]?(obs-composite-blur(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos-extra", "cachyos"], []),
    "obs-teleport": (r'href=[\'\"]?(obs-teleport(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos-extra", "cachyos"], []),
    "zenpower3": (r'href=[\'\"]?(zenpower3-dkms-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos", "arch-extra"], []),
    "v4l2loopback": (r'href=[\'\"]?(v4l2loopback-dkms-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-extra", "cachyos", "chaotic-aur"], []),
    "rtl8821cu": (r'href=[\'\"]?(rtl8821cu-dkms-git-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos"], []),
    "rtl88x2bu": (r'href=[\'\"]?(rtl88x2bu-dkms-git-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos"], []),
    "rtl8812au": (r'href=[\'\"]?(rtl8812au-dkms-git-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos"], []),
    "broadcom-wl": (r'href=[\'\"]?(broadcom-wl-dkms-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-extra", "cachyos"], []),
    "r8125": (r'href=[\'\"]?(r8125-dkms-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos-extra-v3", "cachyos-extra", "cachyos"], []),
    "sunshine": (r'href=[\'\"]?(sunshine-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(libayatana-appindicator-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(miniupnpc-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(numactl-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["cachyos", "arch-extra"], []),
    "vram-booster": (r'href=[\'\"]?(dmemcg-booster-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, r'href=[\'\"]?(plasma-foreground-booster-([0-9a-zA-Z_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["cachyos", "chaotic-aur", "arch-extra"], []),
    "limine": (r'href=[\'\"]?(limine-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos", "arch-extra"], []),
    "limine-entry-tool": (r'href=[\'\"]?(limine-entry-tool-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos"], []),
    "limine-snapper-sync": (r'href=[\'\"]?(limine-snapper-sync-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos"], []),
    "sbctl": (r'href=[\'\"]?(sbctl-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-extra", "cachyos"], [])
}

if pkg_id not in catalog:
    print("NONE NONE NONE NONE")
    sys.exit(0)

main_pat, lib32_pat, extra_pat, main_repos, lib32_repos = catalog[pkg_id]

def fetch_url_cached(url, cdir, ttl=1800):
    url_hash = hashlib.sha256(url.encode('utf-8')).hexdigest()[:16]
    cache_file = os.path.join(cdir, f'repo_idx_{url_hash}.html')
    now = time.time()
    if os.path.exists(cache_file):
        try:
            mtime = os.path.getmtime(cache_file)
            if (now - mtime) < ttl:
                with open(cache_file, 'r', encoding='utf-8', errors='ignore') as f:
                    return f.read()
        except Exception:
            pass
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64)"})
        with urllib.request.urlopen(req, timeout=6) as resp:
            content = resp.read().decode("utf-8", errors="ignore")
            try:
                with open(cache_file, 'w', encoding='utf-8', errors='ignore') as f:
                    f.write(content)
            except Exception:
                pass
            return content
    except Exception:
        return ""

def clean_pkg_version(pid, raw_v):
    v = urllib.parse.unquote(str(raw_v))
    v = re.sub(r'\.pkg\.tar\.(?:zst|xz|gz)$', '', v)
    v = re.sub(r'-(?:x86_64(?:_v[0-9]+)?|noarch|i[3-6]86|any|aarch64)(?:-[0-9a-zA-Z_]+)?$', '', v)
    v = re.sub(r'-[0-9]+(?:\.[0-9]+)?$', '', v)
    v = re.sub(r'^[0-9]+(?:%3A|:|_)', '', v)
    if pid:
        pid_clean = pid.replace("-", "")
        v = re.sub(rf'^(?:underpants-|cachyos-gnome-)?(?:{re.escape(pid)}|{re.escape(pid_clean)})(?:-bin|-git|-manager|-launcher|-rules|-udev)?-', '', v, flags=re.IGNORECASE)
    v = re.sub(r'^[a-zA-Z0-9_\-+]+?-([0-9])', r'\1', v)
    return v

def parse_version_key(v_str):
    clean = clean_pkg_version('', v_str)
    parts = re.split(r'[-._+~]', clean)
    res = []
    for p in parts:
        if p.isdigit():
            res.append((0, int(p), ''))
        else:
            num = ''.join(c for c in p if c.isdigit())
            res.append((1, int(num) if num else 0, p))
    return res

def fetch_match(pat, r_list, pid=''):
    if not pat:
        return None, None
    candidates = []
    for r_key in r_list:
        base_url = repos.get(r_key, "")
        if not base_url:
            continue
        html = fetch_url_cached(base_url, cache_dir)
        if not html:
            continue
        try:
            matches = re.findall(pat, html)
        except Exception:
            matches = []
        for m in matches:
            if isinstance(m, tuple):
                fn = m[0]
                ver = m[1] if len(m) > 1 else m[0]
            else:
                fn = m
                ver = m
            clean_v = clean_pkg_version(pid, ver)
            url = base_url.rstrip("/") + "/" + fn
            candidates.append((clean_v, url, ver))
    if candidates:
        candidates.sort(key=lambda c: parse_version_key(c[0]))
        best = candidates[-1]
        return best[2], best[1]
    return None, None

aur_pkg_names = {
    "google-chrome": ("google-chrome", "google-chrome-{ver}-x86_64.pkg.tar.zst"),
    "microsoft-edge": ("microsoft-edge-stable-bin", "microsoft-edge-stable-bin-{ver}-x86_64.pkg.tar.zst"),
    "brave": ("brave-bin", "brave-bin-{ver}-x86_64.pkg.tar.zst"),
    "zen-browser": ("zen-browser-bin", "zen-browser-bin-{ver}-x86_64.pkg.tar.zst"),
    "zenpower3": ("zenpower3-dkms", "zenpower3-dkms-{ver}-x86_64.pkg.tar.zst"),
    "v4l2loopback": ("v4l2loopback-dkms-git", "v4l2loopback-dkms-git-{ver}-x86_64.pkg.tar.zst"),
    "rtl8821cu": ("rtl8821cu-dkms-git", "rtl8821cu-dkms-git-{ver}-x86_64.pkg.tar.zst"),
    "rtl88x2bu": ("rtl88x2bu-dkms-git", "rtl88x2bu-dkms-git-{ver}-x86_64.pkg.tar.zst"),
    "rtl8812au": ("rtl8812au-dkms-git", "rtl8812au-dkms-git-{ver}-x86_64.pkg.tar.zst"),
    "obs-pipewire-audio-capture": ("obs-pipewire-audio-capture", "obs-pipewire-audio-capture-{ver}-x86_64.pkg.tar.zst")
}

github_and_direct_pkgs = {
    "obs-move-transition": {
        "type": "github_release",
        "repo": "exeldro/obs-move-transition",
        "asset_pattern": r"move-transition-([0-9\.]+)-x86_64-linux-gnu\.deb"
    },
    "obs-source-record": {
        "type": "github_release",
        "repo": "exeldro/obs-source-record",
        "asset_pattern": r"source-record-([0-9\.]+)-ubuntu.*\.tar\.gz"
    },
    "obs-advanced-scene-switcher": {
        "type": "github_release",
        "repo": "WarmUpTill/SceneSwitcher",
        "asset_pattern": r"advanced-scene-switcher-([0-9\.]+)-x86_64-ubuntu.*-linux-gnu\.deb"
    },
    "obs-multi-rtmp": {
        "type": "github_release",
        "repo": "sorayuki/obs-multi-rtmp",
        "asset_pattern": r"obs-multi-rtmp-([0-9\.]+)-x86_64-linux-gnu-ubuntu.*\.deb"
    },
    "obs-composite-blur": {
        "type": "github_release",
        "repo": "FiniteSingularity/obs-composite-blur",
        "asset_pattern": r"obs-composite-blur-([0-9\.]+)-ubuntu.*\.zip"
    },
    "obs-teleport": {
        "type": "github_release",
        "repo": "fzwoch/obs-teleport",
        "asset_pattern": r"obs-teleport\.zip"
    }
}

main_ver, main_url = None, None

if pkg_id in github_and_direct_pkgs:
    meta = github_and_direct_pkgs[pkg_id]
    if meta["type"] == "direct_url":
        main_ver = meta["version"]
        main_url = meta["url"]
    elif meta["type"] == "github_release":
        try:
            gh_url = f"https://api.github.com/repos/{meta['repo']}/releases"
            raw = fetch_url_cached(gh_url, cache_dir, ttl=1800)
            if raw:
                releases = json.loads(raw)
                for rel in releases:
                    tag = rel.get("tag_name", "").lstrip("v")
                    for asset in rel.get("assets", []):
                        aname = asset.get("name", "")
                        m = re.search(meta["asset_pattern"], aname)
                        if m:
                            main_ver = m.group(1) if m.groups() else tag
                            main_url = asset.get("browser_download_url")
                            break
                    if main_ver and main_url:
                        break
        except Exception:
            pass

if not main_ver or not main_url:
    main_ver, main_url = fetch_match(main_pat, main_repos, pkg_id)

if (not main_ver or not main_url) and pkg_id in aur_pkg_names:
    aur_name, filename_tmpl = aur_pkg_names[pkg_id]
    try:
        rpc_url = f"https://aur.archlinux.org/rpc/v5/info?arg[]={aur_name}"
        rpc_raw = fetch_url_cached(rpc_url, cache_dir, ttl=1800)
        if rpc_raw:
            data = json.loads(rpc_raw)
            for r in data.get("results", []):
                if r.get("Name") == aur_name:
                    v = r.get("Version")
                    main_ver = v
                    fn = filename_tmpl.format(ver=v)
                    main_url = f"{chaotic_fastest.rstrip('/')}/{fn}"
                    break
    except Exception:
        pass

if not main_ver or not main_url:
    for repo_cand in ("multilib", "extra", "core"):
        try:
            api_url = f"https://archlinux.org/packages/{repo_cand}/x86_64/{pkg_id}/json/"
            raw_json = fetch_url_cached(api_url, cache_dir, ttl=1800)
            if raw_json:
                data = json.loads(raw_json)
                fn = data.get("filename")
                v = data.get("pkgver")
                if fn and v:
                    main_ver = v
                    main_url = f"https://geo.mirror.pkgbuild.com/{repo_cand}/os/x86_64/{fn}"
                    break
        except Exception:
            pass

if not main_ver or not main_url:
    print("NONE NONE NONE NONE")
    sys.exit(0)

lib32_url = "NONE"
if lib32_pat:
    _, l32_u = fetch_match(lib32_pat, lib32_repos or main_repos, pkg_id)
    if l32_u:
        lib32_url = l32_u

extra_url = "NONE"
if extra_pat:
    patterns = extra_pat if isinstance(extra_pat, (list, tuple)) else [extra_pat]
    extra_repo_list = list(dict.fromkeys(main_repos + ["arch-extra", "arch-core", "cachyos-extra", "cachyos", "chaotic-aur", "chaotic-cdn"]))
    extra_urls = []
    for p in patterns:
        _, ext_u = fetch_match(p, extra_repo_list)
        if ext_u:
            extra_urls.append(ext_u)
        elif "cef-minimal-obs" in p:
            try:
                rpc_url = "https://aur.archlinux.org/rpc/v5/info?arg[]=cef-minimal-obs-bin"
                rpc_raw = fetch_url_cached(rpc_url, cache_dir, ttl=1800)
                if rpc_raw:
                    data = json.loads(rpc_raw)
                    for r in data.get("results", []):
                        if r.get("Name") == "cef-minimal-obs-bin":
                            v = r.get("Version")
                            extra_urls.append(f"{chaotic_fastest.rstrip('/')}/cef-minimal-obs-bin-{v}-x86_64.pkg.tar.zst")
                            break
            except Exception:
                pass
    if extra_urls:
        extra_url = ",".join(extra_urls)

clean_ver = clean_pkg_version(pkg_id, main_ver)
print(f"{clean_ver} {main_url} {lib32_url} {extra_url}")
PYRESOLVE
}

resolve_multiple_gaming_upstreams_batch() {
    local target_pids=("$@")
    [ ${#target_pids[@]} -gt 0 ] || return 0

    python3 - "${target_pids[@]}" << 'PYBATCHRESOLVE'
import sys, os, re, time, datetime, json, urllib.request, urllib.parse, hashlib, concurrent.futures

pkg_ids = sys.argv[1:]

def get_cache_dir():
    for d in ['/var/cache/slacky-update', os.path.expanduser('~/.cache/slacky-update'), '/tmp/slacky-update-cache']:
        try:
            os.makedirs(d, exist_ok=True)
            test_f = os.path.join(d, '.write_test')
            with open(test_f, 'w') as f: f.write('1')
            os.remove(test_f)
            return d
        except Exception:
            continue
    return '/tmp'

cache_dir = get_cache_dir()

def get_chaotic_fastest_mirror(cdir):
    m_file = os.path.join(cdir, 'chaotic_fastest_mirror.json')
    now = time.time()
    today_dt = datetime.datetime.now()
    is_thursday = (today_dt.weekday() == 3)
    today_str = today_dt.strftime('%Y-%m-%d')

    if os.path.exists(m_file):
        try:
            with open(m_file, 'r', encoding='utf-8') as f:
                d = json.load(f)
            cached_m = d.get('mirror')
            last_ts = d.get('timestamp', 0)
            last_day = d.get('date', '')
            if last_day == today_str and cached_m:
                return cached_m
            elif not is_thursday and (now - last_ts) < (7 * 86400) and cached_m:
                return cached_m
        except Exception:
            pass

    mirrors = [
        'https://cdn-mirror.chaotic.cx/chaotic-aur/x86_64/',
        'https://geo-mirror.chaotic.cx/chaotic-aur/x86_64/',
        'https://de-1-mirror.chaotic.cx/chaotic-aur/x86_64/',
        'https://de-2-mirror.chaotic.cx/chaotic-aur/x86_64/',
        'https://de-4-mirror.chaotic.cx/chaotic-aur/x86_64/',
        'https://es-mirror.chaotic.cx/chaotic-aur/x86_64/',
        'https://bg-mirror.chaotic.cx/chaotic-aur/x86_64/',
        'https://nl-1-mirror.chaotic.cx/chaotic-aur/x86_64/',
        'https://fr-1-mirror.chaotic.cx/chaotic-aur/x86_64/',
        'https://ca-mirror.chaotic.cx/chaotic-aur/x86_64/',
        'https://us-mi-mirror.chaotic.cx/chaotic-aur/x86_64/',
        'https://us-ut-mirror.chaotic.cx/chaotic-aur/x86_64/'
    ]

    def ping_m(u):
        t0 = time.time()
        try:
            req = urllib.request.Request(u + 'chaotic-mirrorlist.pkg.tar.zst', headers={'User-Agent': 'Mozilla/5.0', 'Range': 'bytes=0-256'})
            with urllib.request.urlopen(req, timeout=1.8) as resp:
                resp.read(256)
                return ((time.time() - t0) * 1000, u)
        except Exception:
            return (999999, u)

    best_url = 'https://cdn-mirror.chaotic.cx/chaotic-aur/x86_64/'
    best_lat = 999999
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=len(mirrors)) as ex:
            results = list(ex.map(ping_m, mirrors))
        valid = [r for r in results if r[0] < 90000]
        if valid:
            valid.sort(key=lambda x: x[0])
            best_lat, best_url = valid[0]
    except Exception:
        pass

    try:
        with open(m_file, 'w', encoding='utf-8') as f:
            json.dump({'mirror': best_url, 'timestamp': now, 'date': today_str, 'latency_ms': best_lat}, f)
    except Exception:
        pass
    return best_url

chaotic_fastest = get_chaotic_fastest_mirror(cache_dir)

repos = {
    "cachyos": "https://mirror.cachyos.org/repo/x86_64/cachyos/",
    "cachyos-v3": "https://mirror.cachyos.org/repo/x86_64_v3/cachyos-v3/",
    "cachyos-extra": "https://mirror.cachyos.org/repo/x86_64/cachyos-extra/",
    "cachyos-extra-v3": "https://mirror.cachyos.org/repo/x86_64_v3/cachyos-extra-v3/",
    "chaotic-aur": chaotic_fastest,
    "chaotic-cdn": "https://cdn-mirror.chaotic.cx/chaotic-aur/x86_64/",
    "arch-core": "https://geo.mirror.pkgbuild.com/core/os/x86_64/",
    "arch-extra": "https://geo.mirror.pkgbuild.com/extra/os/x86_64/",
    "arch-multilib": "https://geo.mirror.pkgbuild.com/multilib/os/x86_64/"
}

catalog = {
    "mangohud": (r'href=[\'\"]?(mangohud-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', r'href=[\'\"]?(lib32-mangohud-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', r'href=[\'\"]?(glfw-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["cachyos-extra-v3", "arch-extra", "cachyos"], ["arch-multilib", "cachyos"]),
    "gamemode": (r'href=[\'\"]?(gamemode-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', r'href=[\'\"]?(lib32-gamemode-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, ["cachyos-extra-v3", "arch-extra", "cachyos"], ["arch-multilib", "cachyos"]),
    "goverlay": (r'href=[\'\"]?(goverlay-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, r'href=[\'\"]?(qt6pas-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["arch-extra", "cachyos"], []),
    "scx": (r'href=[\'\"]?(scx-manager-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(scx-scheds(?:-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(scx-tools(?:-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["cachyos", "arch-extra"], []),
    "easyeffects": (r'href=[\'\"]?(easyeffects-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(lsp-plugins-lv2-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(calf-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(mda\.lv2-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(zam-plugins-lv2-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(zita-convolver-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(rnnoise-(?:1%3A|1:)?([0-9a-zA-Z_\.:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libbs2b-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(soundtouch-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libebur128-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(webrtc-audio-processing-(?:2|1)-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(lilv-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(serd-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(sord-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(sratom-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(qt6-graphs-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(onetbb-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libmysofa-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(zix-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["arch-extra", "cachyos", "arch-core"], []),
    "pear-desktop": (r'href=[\'\"]?(pear-desktop-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(electron42-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libjpeg-turbo-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["chaotic-aur", "chaotic-cdn", "arch-extra"], []),
    "yabridge": (r'href=[\'\"]?(yabridge-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', r'href=[\'\"]?(lib32-yabridge-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', r'href=[\'\"]?(yabridgectl-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["arch-extra", "cachyos", "chaotic-aur"], ["arch-multilib", "cachyos"]),
    "audacity": (r'href=[\'\"]?(audacity-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(suil-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(lilv-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(serd-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(sord-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(sratom-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(zix-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(portsmf-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(portaudio-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(portmidi-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libsbsms-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(vamp-plugin-sdk-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(soundtouch-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(twolame-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libid3tag-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libsoxr-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libmspack-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(wxwidgets-gtk3-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(wxwidgets-common-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libjpeg-turbo-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["arch-extra", "cachyos-extra-v3", "cachyos", "arch-core"], []),
    "spotify": (r'href=[\'\"]?(spotify(?:-launcher)?-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(sequoia-sqv-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libayatana-appindicator-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libayatana-indicator-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(ayatana-ido-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libcurl-gnutls-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["arch-extra", "cachyos-extra-v3", "cachyos", "arch-core"], []),
    "inkscape": (r'href=[\'\"]?(inkscape-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(lib2geom-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(double-conversion-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(graphicsmagick-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libcdr-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(poppler-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libvisio-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libwpg-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(librevenge-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["cachyos-extra-v3", "arch-extra", "cachyos"], []),
    "darktable": (r'href=[\'\"]?(darktable-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(libavif-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libheif-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libde265-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libyuv-((?:r[0-9]+|[0-9])[a-zA-Z0-9_\.\+%-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(rav1e-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(svt-av1-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(openh264-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(pugixml-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(colord-gtk-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(osm-gps-map-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(gmic-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(flickcurl-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["cachyos-extra-v3", "arch-extra", "cachyos"], []),
    "syncthing": (r'href=[\'\"]?(syncthing-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-extra", "cachyos-extra-v3", "cachyos"], []),
    "ananicy": (r'href=[\'\"]?(ananicy-cpp(?:-git)?-([0-9a-zA-Z_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(cachyos-ananicy-rules(?:-git)?-([0-9a-zA-Z_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libbpf-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["cachyos", "cachyos-extra-v3", "arch-core"], []),
    "gamescope": (r'href=[\'\"]?(gamescope-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', r'href=[\'\"]?(lib32-gamescope-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', r'href=[\'\"]?(libavif-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["cachyos", "arch-extra"], ["cachyos", "arch-multilib"]),
    "heroic": (r'href=[\'\"]?(heroic-games-launcher-bin-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos", "arch-extra"], []),
    "lutris": (r'href=[\'\"]?(lutris(?:-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(webkit2gtk-4\.1-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libsoup3-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(python-moddb-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(python-pypresence-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(python-evdev-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(python-distro-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["arch-extra", "cachyos", "arch-core", "cachyos-extra-v3"], []),
    "faugus": (r'href=[\'\"]?(faugus-launcher-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(python-vdf-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(icoextract-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(python-pefile-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["cachyos", "arch-extra"], []),
    "protonplus": (r'href=[\'\"]?((?:proton-plus|protonplus)-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos", "arch-extra"], []),
    "steam": (r'href=[\'\"]?(steam-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-multilib", "cachyos"], []),
    "steam-devices": (None, None, None, [], []),
    "retroarch": (r'href=[\'\"]?(retroarch-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, r'href=[\'\"]?(retroarch-assets-ozone-(?:[0-9]+%3A)?([0-9a-zA-Z_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["arch-extra", "cachyos"], []),
    "lact": (r'href=[\'\"]?(lact-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-extra", "cachyos"], []),
    "openrgb": (r'href=[\'\"]?(openrgb(?:-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos", "arch-extra"], []),
    "solaar": (r'href=[\'\"]?(solaar-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(python-pyudev-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(python-typing_extensions-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(python-xlib-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["arch-extra", "cachyos-extra-v3", "cachyos"], []),
    "coolercontrol": (r'href=[\'\"]?(coolercontrol-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, r'href=[\'\"]?(coolercontrold-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["cachyos", "arch-extra"], []),
    "asusctl": (r'href=[\'\"]?(asusctl-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-extra", "cachyos"], []),
    "brave": (r'href=[\'\"]?(brave-bin-(?:1%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos", "chaotic-aur", "chaotic-cdn"], []),
    "zen-browser": (r'href=[\'\"]?(zen-browser-bin-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos", "chaotic-aur", "chaotic-cdn"], []),
    "google-chrome": (r'href=[\'\"]?(google-chrome-([0-9][a-zA-Z0-9_\.:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "chaotic-cdn", "cachyos"], []),
    "microsoft-edge": (r'href=[\'\"]?(microsoft-edge-(?:stable|beta|dev)-bin-([0-9][a-zA-Z0-9_\.:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "chaotic-cdn", "cachyos"], []),
    "obs-studio": (r'href=[\'\"]?(obs-studio-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(python-(3\.[0-9a-zA-Z_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(mbedtls-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(obs-studio-plugin-browser-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(cef-minimal-obs(?:-bin)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libdatachannel-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libjuice-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(librist-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(libusrsctp-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["arch-extra", "arch-core", "cachyos"], []),
    "discord": (r'href=[\'\"]?(discord-(?:[0-9]+%3A|[0-9]+:)?([0-9][a-zA-Z0-9_\.:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-extra", "cachyos"], []),
    "vesktop": (r'href=[\'\"]?(vesktop(?:-bin)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos"], []),
    "obs-vkcapture": (r'href=[\'\"]?(obs-vkcapture-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', r'href=[\'\"]?(lib32-obs-vkcapture-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, ["cachyos", "arch-extra"], ["cachyos", "arch-multilib"]),
    "obs-move-transition": (r'href=[\'\"]?(obs-move-transition(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos-extra", "cachyos"], []),
    "obs-source-record": (r'href=[\'\"]?(obs-source-record(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos-extra", "cachyos"], []),
    "obs-pipewire-audio-capture": (r'href=[\'\"]?(obs-pipewire-audio-capture(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos-extra", "cachyos"], []),
    "obs-advanced-scene-switcher": (r'href=[\'\"]?(obs-advanced-scene-switcher(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(opencv-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["chaotic-aur", "cachyos-extra", "arch-extra", "cachyos"], []),
    "obs-multi-rtmp": (r'href=[\'\"]?(obs-multi-rtmp(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos-extra", "cachyos"], []),
    "obs-composite-blur": (r'href=[\'\"]?(obs-composite-blur(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos-extra", "cachyos"], []),
    "obs-teleport": (r'href=[\'\"]?(obs-teleport(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos-extra", "cachyos"], []),
    "zenpower3": (r'href=[\'\"]?(zenpower3-dkms-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos", "arch-extra"], []),
    "v4l2loopback": (r'href=[\'\"]?(v4l2loopback-dkms-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-extra", "cachyos", "chaotic-aur"], []),
    "rtl8821cu": (r'href=[\'\"]?(rtl8821cu-dkms-git-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos"], []),
    "rtl88x2bu": (r'href=[\'\"]?(rtl88x2bu-dkms-git-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos"], []),
    "rtl8812au": (r'href=[\'\"]?(rtl8812au-dkms-git-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos"], []),
    "broadcom-wl": (r'href=[\'\"]?(broadcom-wl-dkms-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-extra", "cachyos"], []),
    "r8125": (r'href=[\'\"]?(r8125-dkms-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos-extra-v3", "cachyos-extra", "cachyos"], []),
    "sunshine": (r'href=[\'\"]?(sunshine-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(libayatana-appindicator-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(miniupnpc-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(numactl-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["cachyos", "arch-extra"], []),
    "vram-booster": (r'href=[\'\"]?(dmemcg-booster-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, r'href=[\'\"]?(plasma-foreground-booster-([0-9a-zA-Z_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["cachyos", "chaotic-aur", "arch-extra"], []),
    "limine": (r'href=[\'\"]?(limine-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos", "arch-extra"], []),
    "limine-entry-tool": (r'href=[\'\"]?(limine-entry-tool-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos"], []),
    "limine-snapper-sync": (r'href=[\'\"]?(limine-snapper-sync-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos"], []),
    "sbctl": (r'href=[\'\"]?(sbctl-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-extra", "cachyos"], [])
}

def fetch_url_cached(url, cdir, ttl=1800):
    url_hash = hashlib.sha256(url.encode('utf-8')).hexdigest()[:16]
    cache_file = os.path.join(cdir, f'repo_idx_{url_hash}.html')
    now = time.time()
    if os.path.exists(cache_file):
        try:
            mtime = os.path.getmtime(cache_file)
            if (now - mtime) < ttl:
                with open(cache_file, 'r', encoding='utf-8', errors='ignore') as f:
                    return f.read()
        except Exception:
            pass
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64)"})
        with urllib.request.urlopen(req, timeout=6) as resp:
            content = resp.read().decode("utf-8", errors="ignore")
            try:
                with open(cache_file, 'w', encoding='utf-8', errors='ignore') as f:
                    f.write(content)
            except Exception:
                pass
            return content
    except Exception:
        return ""

def clean_pkg_version(pid, raw_v):
    v = urllib.parse.unquote(str(raw_v))
    v = re.sub(r'\.pkg\.tar\.(?:zst|xz|gz)$', '', v)
    v = re.sub(r'-(?:x86_64(?:_v[0-9]+)?|noarch|i[3-6]86|any|aarch64)(?:-[0-9a-zA-Z_]+)?$', '', v)
    v = re.sub(r'-[0-9]+(?:\.[0-9]+)?$', '', v)
    v = re.sub(r'^[0-9]+(?:%3A|:|_)', '', v)
    if pid:
        pid_clean = pid.replace("-", "")
        v = re.sub(rf'^(?:underpants-|cachyos-gnome-)?(?:{re.escape(pid)}|{re.escape(pid_clean)})(?:-bin|-git|-manager|-launcher|-rules|-udev)?-', '', v, flags=re.IGNORECASE)
    v = re.sub(r'^[a-zA-Z0-9_\-+]+?-([0-9])', r'\1', v)
    return v

def parse_version_key(v_str):
    clean = clean_pkg_version('', v_str)
    parts = re.split(r'[-._+~]', clean)
    res = []
    for p in parts:
        if p.isdigit():
            res.append((0, int(p), ''))
        else:
            num = ''.join(c for c in p if c.isdigit())
            res.append((1, int(num) if num else 0, p))
    return res

def fetch_match(pat, r_list, pid=''):
    if not pat:
        return None, None
    candidates = []
    for r_key in r_list:
        base_url = repos.get(r_key, "")
        if not base_url:
            continue
        html = fetch_url_cached(base_url, cache_dir)
        if not html:
            continue
        try:
            matches = re.findall(pat, html)
        except Exception:
            matches = []
        for m in matches:
            if isinstance(m, tuple):
                fn = m[0]
                ver = m[1] if len(m) > 1 else m[0]
            else:
                fn = m
                ver = m
            clean_v = clean_pkg_version(pid, ver)
            url = base_url.rstrip("/") + "/" + fn
            candidates.append((clean_v, url, ver))
    if candidates:
        candidates.sort(key=lambda c: parse_version_key(c[0]))
        best = candidates[-1]
        return best[2], best[1]
    return None, None

aur_pkg_names = {
    "google-chrome": ("google-chrome", "google-chrome-{ver}-x86_64.pkg.tar.zst"),
    "microsoft-edge": ("microsoft-edge-stable-bin", "microsoft-edge-stable-bin-{ver}-x86_64.pkg.tar.zst"),
    "brave": ("brave-bin", "brave-bin-{ver}-x86_64.pkg.tar.zst"),
    "zen-browser": ("zen-browser-bin", "zen-browser-bin-{ver}-x86_64.pkg.tar.zst"),
    "zenpower3": ("zenpower3-dkms", "zenpower3-dkms-{ver}-x86_64.pkg.tar.zst"),
    "v4l2loopback": ("v4l2loopback-dkms-git", "v4l2loopback-dkms-git-{ver}-x86_64.pkg.tar.zst"),
    "rtl8821cu": ("rtl8821cu-dkms-git", "rtl8821cu-dkms-git-{ver}-x86_64.pkg.tar.zst"),
    "rtl88x2bu": ("rtl88x2bu-dkms-git", "rtl88x2bu-dkms-git-{ver}-x86_64.pkg.tar.zst"),
    "rtl8812au": ("rtl8812au-dkms-git", "rtl8812au-dkms-git-{ver}-x86_64.pkg.tar.zst"),
    "obs-pipewire-audio-capture": ("obs-pipewire-audio-capture", "obs-pipewire-audio-capture-{ver}-x86_64.pkg.tar.zst")
}

github_and_direct_pkgs = {
    "obs-move-transition": {
        "type": "github_release",
        "repo": "exeldro/obs-move-transition",
        "asset_pattern": r"move-transition-([0-9\.]+)-x86_64-linux-gnu\.deb"
    },
    "obs-source-record": {
        "type": "github_release",
        "repo": "exeldro/obs-source-record",
        "asset_pattern": r"source-record-([0-9\.]+)-ubuntu.*\.tar\.gz"
    },
    "obs-advanced-scene-switcher": {
        "type": "github_release",
        "repo": "WarmUpTill/SceneSwitcher",
        "asset_pattern": r"advanced-scene-switcher-([0-9\.]+)-x86_64-ubuntu.*-linux-gnu\.deb"
    },
    "obs-multi-rtmp": {
        "type": "github_release",
        "repo": "sorayuki/obs-multi-rtmp",
        "asset_pattern": r"obs-multi-rtmp-([0-9\.]+)-x86_64-linux-gnu-ubuntu.*\.deb"
    },
    "obs-composite-blur": {
        "type": "github_release",
        "repo": "FiniteSingularity/obs-composite-blur",
        "asset_pattern": r"obs-composite-blur-([0-9\.]+)-ubuntu.*\.zip"
    },
    "obs-teleport": {
        "type": "github_release",
        "repo": "fzwoch/obs-teleport",
        "asset_pattern": r"obs-teleport\.zip"
    }
}

def resolve_single(pid):
    if pid == "steam-devices":
        return pid, "1.0.0.61", "BUNDLED", "NONE", "NONE"
    if pid not in catalog:
        return pid, "NONE", "NONE", "NONE", "NONE"

    main_ver, main_url = None, None

    if pid in github_and_direct_pkgs:
        meta = github_and_direct_pkgs[pid]
        if meta["type"] == "direct_url":
            main_ver = meta["version"]
            main_url = meta["url"]
        elif meta["type"] == "github_release":
            try:
                gh_url = f"https://api.github.com/repos/{meta['repo']}/releases"
                raw = fetch_url_cached(gh_url, cache_dir, ttl=1800)
                if raw:
                    releases = json.loads(raw)
                    for rel in releases:
                        tag = rel.get("tag_name", "").lstrip("v")
                        for asset in rel.get("assets", []):
                            aname = asset.get("name", "")
                            m = re.search(meta["asset_pattern"], aname)
                            if m:
                                main_ver = m.group(1) if m.groups() else tag
                                main_url = asset.get("browser_download_url")
                                break
                        if main_ver and main_url:
                            break
            except Exception:
                pass

    main_pat, lib32_pat, extra_pat, main_repos, lib32_repos = catalog[pid]

    if not main_ver or not main_url:
        main_ver, main_url = fetch_match(main_pat, main_repos, pid)

    if (not main_ver or not main_url) and pid in aur_pkg_names:
        aur_name, filename_tmpl = aur_pkg_names[pid]
        try:
            rpc_url = f"https://aur.archlinux.org/rpc/v5/info?arg[]={aur_name}"
            rpc_raw = fetch_url_cached(rpc_url, cache_dir, ttl=1800)
            if rpc_raw:
                data = json.loads(rpc_raw)
                for r in data.get("results", []):
                    if r.get("Name") == aur_name:
                        v = r.get("Version")
                        main_ver = v
                        fn = filename_tmpl.format(ver=v)
                        main_url = f"{chaotic_fastest.rstrip('/')}/{fn}"
                        break
        except Exception:
            pass

    if not main_ver or not main_url:
        for repo_cand in ("multilib", "extra", "core"):
            try:
                api_url = f"https://archlinux.org/packages/{repo_cand}/x86_64/{pid}/json/"
                raw_json = fetch_url_cached(api_url, cache_dir, ttl=1800)
                if raw_json:
                    data = json.loads(raw_json)
                    fn = data.get("filename")
                    v = data.get("pkgver")
                    if fn and v:
                        main_ver = v
                        main_url = f"https://geo.mirror.pkgbuild.com/{repo_cand}/os/x86_64/{fn}"
                        break
            except Exception:
                pass

    if not main_ver or not main_url:
        return pid, "NONE", "NONE", "NONE", "NONE"

    lib32_url = "NONE"
    if lib32_pat:
        _, l32_u = fetch_match(lib32_pat, lib32_repos or main_repos, pid)
        if l32_u:
            lib32_url = l32_u

    extra_url = "NONE"
    if extra_pat:
        patterns = extra_pat if isinstance(extra_pat, (list, tuple)) else [extra_pat]
        extra_repo_list = list(dict.fromkeys(main_repos + ["arch-extra", "arch-core", "cachyos-extra", "cachyos", "chaotic-aur", "chaotic-cdn"]))
        extra_urls = []
        for p in patterns:
            _, ext_u = fetch_match(p, extra_repo_list)
            if ext_u:
                extra_urls.append(ext_u)
            elif "cef-minimal-obs" in p:
                try:
                    rpc_url = "https://aur.archlinux.org/rpc/v5/info?arg[]=cef-minimal-obs-bin"
                    rpc_raw = fetch_url_cached(rpc_url, cache_dir, ttl=1800)
                    if rpc_raw:
                        data = json.loads(rpc_raw)
                        for r in data.get("results", []):
                            if r.get("Name") == "cef-minimal-obs-bin":
                                v = r.get("Version")
                                extra_urls.append(f"{chaotic_fastest.rstrip('/')}/cef-minimal-obs-bin-{v}-x86_64.pkg.tar.zst")
                                break
                except Exception:
                    pass
        if extra_urls:
            extra_url = ",".join(extra_urls)

    clean_ver = clean_pkg_version(pid, main_ver)
    return pid, clean_ver, main_url, lib32_url, extra_url

with concurrent.futures.ThreadPoolExecutor(max_workers=min(len(pkg_ids), 16)) as ex:
    results = list(ex.map(resolve_single, pkg_ids))

for pid, ver, m_u, l_u, e_u in results:
    print(f"{pid}|{ver}|{m_u}|{l_u}|{e_u}")
PYBATCHRESOLVE
}

# --- [ PACKAGE CLEANUP & RESOLUTION ] ---
cleanup_foreign_gaming_pkgs() {
    local pkg_id="$1"
    local patterns=()
    case "${pkg_id}" in
        mangohud)
            patterns=("mangohud-[0-9]*" "mangohud-common-[0-9]*" "MangoHud-[0-9]*" "lib32-mangohud-[0-9]*")
            ;;
        gamemode)
            patterns=("gamemode-[0-9]*" "feral-gamemode-[0-9]*" "lib32-gamemode-[0-9]*")
            ;;
        goverlay)
            patterns=("goverlay-[0-9]*")
            ;;
        scx)
            patterns=("scx-[0-9]*" "scx-manager-[0-9]*" "scx-scheds-[0-9]*" "scx-tools-[0-9]*" "cachyos-gnome-scx-[0-9]*")
            ;;
        easyeffects)
            patterns=("easyeffects-[0-9]*" "cachyos-gnome-easyeffects-[0-9]*")
            ;;
        pear-desktop)
            patterns=("pear-desktop-[0-9]*" "cachyos-gnome-pear-desktop-[0-9]*")
            ;;
        ananicy)
            patterns=("ananicy-[0-9]*" "ananicy-cpp-[0-9]*" "cachyos-ananicy-rules-[0-9]*" "cachyos-gnome-ananicy-r[0-9]*")
            ;;
        gamescope)
            patterns=("gamescope-[0-9]*" "lib32-gamescope-[0-9]*")
            ;;
        heroic)
            patterns=("heroic-[0-9]*" "heroic-games-launcher-[0-9]*" "heroic-bin-[0-9]*")
            ;;
        lutris)
            patterns=("lutris-[0-9]*")
            sudo rm -f /usr/share/applications/net.lutris.Lutris1.desktop /usr/share/pixmaps/*lutris* /usr/share/pixmaps/*Lutris* 2>/dev/null || rm -f /usr/share/applications/net.lutris.Lutris1.desktop /usr/share/pixmaps/*lutris* /usr/share/pixmaps/*Lutris* 2>/dev/null || true
            ;;
        faugus)
            patterns=("faugus-[0-9]*" "faugus-launcher-[0-9]*")
            ;;
        protonplus)
            patterns=("protonplus-[0-9]*" "proton-plus-[0-9]*")
            ;;
        steam)
            patterns=("steam-[0-9]*" "steam-launcher-[0-9]*" "underpants-steam-[0-9]*" "cachyos-gnome-steam-[0-9]*")
            ;;
        steam-devices)
            patterns=("game-devices-udev-[0-9]*" "steam-devices-[0-9]*")
            ;;
        lact)
            patterns=("lact-[0-9]*" "lact-r[0-9]*" "cachyos-gnome-lact-r[0-9]*")
            ;;
        openrgb)
            patterns=("openrgb-[0-9]*" "openrgb-r[0-9]*" "cachyos-gnome-openrgb-r[0-9]*")
            ;;
        brave)
            patterns=("brave-bin-[0-9]*" "brave-browser-[0-9]*" "brave-[0-9]*")
            ;;
        zen-browser)
            patterns=("zen-browser-bin-[0-9]*" "zen-browser-[0-9]*")
            ;;
        vivaldi)
            patterns=("vivaldi-[0-9]*" "vivaldi-ffmpeg-codecs-[0-9]*")
            ;;
        google-chrome)
            patterns=("google-chrome-[0-9]*" "google-chrome-stable-[0-9]*")
            ;;
        microsoft-edge)
            patterns=("microsoft-edge-[0-9]*" "microsoft-edge-stable-[0-9]*" "microsoft-edge-stable-bin-[0-9]*")
            ;;
        opera)
            patterns=("opera-[0-9]*" "opera-ffmpeg-codecs-[0-9]*")
            ;;
        obs-studio)
            patterns=("obs-studio-[0-9]*" "obs-[0-9]*")
            ;;
        discord)
            patterns=("discord-[0-9]*")
            ;;
        vesktop)
            patterns=("vesktop-[0-9]*" "vesktop-bin-[0-9]*")
            ;;
        obs-vkcapture)
            patterns=("obs-vkcapture-[0-9]*" "lib32-obs-vkcapture-[0-9]*")
            ;;
        sunshine)
            patterns=("sunshine-[0-9]*")
            ;;
        yabridge)
            patterns=("yabridge-[0-9]*" "lib32-yabridge-[0-9]*" "yabridgectl-[0-9]*")
            ;;
        audacity)
            patterns=("audacity-[0-9]*")
            ;;
        spotify)
            patterns=("spotify-[0-9]*" "spotify-launcher-[0-9]*")
            ;;
        inkscape)
            patterns=("inkscape-[0-9]*")
            ;;
        darktable)
            patterns=("darktable-[0-9]*")
            ;;
        retroarch)
            patterns=("retroarch-[0-9]*" "retroarch-assets-[0-9]*")
            ;;
        solaar)
            patterns=("solaar-[0-9]*")
            ;;
        coolercontrol)
            patterns=("coolercontrol-[0-9]*" "coolercontrold-[0-9]*")
            ;;
        asusctl)
            patterns=("asusctl-[0-9]*")
            ;;
        syncthing)
            patterns=("syncthing-[0-9]*")
            ;;
        limine)
            patterns=("limine-[0-9]*")
            ;;
        limine-entry-tool)
            patterns=("limine-entry-tool-[0-9]*")
            ;;
        limine-snapper-sync)
            patterns=("limine-snapper-sync-[0-9]*")
            ;;
        obs-move-transition)
            patterns=("obs-move-transition-[0-9]*")
            ;;
        obs-source-record)
            patterns=("obs-source-record-[0-9]*")
            ;;
        obs-pipewire-audio-capture)
            patterns=("obs-pipewire-audio-capture-[0-9]*")
            ;;
        obs-advanced-scene-switcher)
            patterns=("obs-advanced-scene-switcher-[0-9]*")
            ;;
        obs-multi-rtmp)
            patterns=("obs-multi-rtmp-[0-9]*")
            ;;
        obs-composite-blur)
            patterns=("obs-composite-blur-[0-9]*")
            ;;
        obs-teleport)
            patterns=("obs-teleport-[0-9]*")
            ;;
        zenpower3)
            patterns=("zenpower3-[0-9]*" "zenpower3-dkms-[0-9]*" "zenpower-[0-9]*")
            ;;
        v4l2loopback)
            patterns=("v4l2loopback-[0-9]*" "v4l2loopback-dkms-[0-9]*")
            ;;
        rtl8821cu)
            patterns=("rtl8821cu-[0-9]*" "rtl8821cu-dkms-[0-9]*" "rtl8821cu-dkms-git-[0-9]*")
            ;;
        rtl88x2bu)
            patterns=("rtl88x2bu-[0-9]*" "rtl88x2bu-dkms-[0-9]*" "rtl88x2bu-dkms-git-[0-9]*")
            ;;
        rtl8812au)
            patterns=("rtl8812au-[0-9]*" "rtl8812au-dkms-[0-9]*" "rtl8812au-dkms-git-[0-9]*")
            ;;
        broadcom-wl)
            patterns=("broadcom-wl-[0-9]*" "broadcom-wl-dkms-[0-9]*")
            ;;
        r8125)
            patterns=("r8125-[0-9]*" "r8125-dkms-[0-9]*")
            ;;
        sbctl)
            patterns=("sbctl-[0-9]*")
            ;;
    esac

    for pat in "${patterns[@]}" "underpants-${pkg_id}-[0-9]*" "cachyos-gnome-${pkg_id}-[0-9]*"; do
        for p in /var/log/packages/${pat}; do
            [ -f "${p}" ] || continue
            local bname
            bname=$(basename "${p}")
            log_info "Removing older or superseded package: ${bname}..."
            validate_privileges
            sudo "${PKG_REMOVE_CMD}" "${bname}" 2>/dev/null || true
        done
    done
}

# --- [ TRANSMUTATION & BUILD ENGINE ] ---
transmute_and_deploy_gaming_pkg() {
    local pkg_id="$1"
    local pre_cache_dir="${2:-}"
    local pre_ver="${3:-}"
    local pre_main_url="${4:-}"
    local pre_lib32_url="${5:-}"
    local pre_extra_url="${6:-}"
    
    # Pre-flight readiness checks
    audit_multilib_readiness "${pkg_id}"
    if [ "${pkg_id}" = "solaar" ] || [ "${pkg_id}" = "steam-devices" ] || [ "${pkg_id}" = "openrgb" ] || [ "${pkg_id}" = "coolercontrol" ] || [ "${pkg_id}" = "sunshine" ] || [ "${pkg_id}" = "steam" ]; then
        audit_user_hardware_groups
    fi

    if [ "${pkg_id}" = "scx" ]; then
        local running_kver
        running_kver=$(uname -r)
        if [ ! -d /sys/kernel/sched_ext ] && [[ ! "${running_kver}" =~ (cachyos|sched_ext) ]]; then
            log_warn "Active running kernel (${running_kver}) does not support Sched-EXT (sched_ext)."
            log_warn "Sched-EXT requires a kernel compiled with sched_ext support (such as CachyOS)."
            echo -n "Do you wish to proceed with installing scx anyway? [y/N]: "
            read -r reply_scx
            if [[ ! "${reply_scx}" =~ ^[YyJjSsOo]$ ]]; then
                log_info "scx installation aborted by user."
                return 0
            fi
        fi
    fi

    if [ "${pkg_id}" = "yabridge" ]; then
        if ! command -v wine >/dev/null 2>&1; then
            log_warn "Wine was not detected on this system."
            log_warn "yabridge requires Wine to bridge Windows VST2/VST3 plugins into Linux DAWs."
            echo -n "Do you wish to proceed with installing yabridge anyway? [y/N]: "
            read -r reply_wine
            if [[ ! "${reply_wine}" =~ ^[YyJjSsOo]$ ]]; then
                log_info "yabridge installation aborted by user."
                return 0
            fi
        fi
    fi

    local ver="${pre_ver}"
    local main_url="${pre_main_url}"
    local lib32_url="${pre_lib32_url}"
    local extra_url="${pre_extra_url}"

    if [ -z "${ver}" ] || [ "${ver}" = "NONE" ]; then
        log_info "Resolving upstream package metadata for ${pkg_id}..."
        read -r ver main_url lib32_url extra_url <<< "$(resolve_cachyos_gaming_upstream_metadata "${pkg_id}" || echo "NONE NONE NONE NONE")"
    fi

    if [ "${ver}" = "NONE" ] || [ -z "${main_url}" ] || [ "${main_url}" = "NONE" ]; then
        log_error "Failed to resolve CachyOS upstream package for: ${pkg_id}"
        return 1
    fi

    log_info "Transmuting ${pkg_id} (v${ver}) to native Slackware txz package..."

    local staging_base
    staging_base=$(mktemp -d "$(get_user_staging_dir)/gnome-${pkg_id}-${ver}.XXXXXX" 2>/dev/null || mktemp -d /tmp/slacky-gnome.XXXXXX)
    local cache_dir="${staging_base}/downloads"
    local staging_root="${staging_base}/pkg"
    local tmp_extract="${staging_base}/extract"
    trap 'rm -rf "${staging_base:-}" 2>/dev/null || true' INT TERM

    mkdir -p "${cache_dir}" "${staging_root}" "${tmp_extract}/main" "${tmp_extract}/lib32" "${tmp_extract}/extra"

    if [ -n "${pre_cache_dir}" ] && [ -d "${pre_cache_dir}" ]; then
        cp -a "${pre_cache_dir}"/* "${cache_dir}/" 2>/dev/null || true
    fi

    if [ "${main_url}" = "BUNDLED" ]; then
        if [ "${pkg_id}" = "steam-devices" ]; then
            log_info "Deploying bundled Steam controller & Gamepad udev rules..."
            local udev_dir=""
            for cand in "${APP_DIR}/../assets/udev/game-devices-udev" \
                        "/usr/share/slacky-update/assets/udev/game-devices-udev" \
                        "/usr/local/lib/slacky-update/assets/udev/game-devices-udev"; do
                if [ -d "${cand}" ]; then
                    udev_dir="${cand}"
                    break
                fi
            done
            mkdir -p "${staging_root}/lib/udev/rules.d"
            if [ -n "${udev_dir}" ]; then
                cp -a "${udev_dir}"/*.rules "${staging_root}/lib/udev/rules.d/" 2>/dev/null || true
            fi
        fi
    else
        local main_file="${cache_dir}/$(basename "${main_url}")"
        local dl_items=()
        if [ ! -f "${main_file}" ] || [ ! -s "${main_file}" ]; then
            if [[ "${main_url}" =~ (cachyos\.org|pkgbuild\.com|archlinux\.org|chaotic\.cx) ]] && [[ "${main_url}" =~ \.pkg\.tar\.zst$ ]]; then
                dl_items+=("${main_url}|${main_file}|${main_url}.sig|${main_file}.sig")
            else
                dl_items+=("${main_url}|${main_file}")
            fi
        fi

        if [ "${lib32_url}" != "NONE" ] && [ -n "${lib32_url}" ]; then
            local lib32_file="${cache_dir}/$(basename "${lib32_url}")"
            if [ ! -f "${lib32_file}" ] || [ ! -s "${lib32_file}" ]; then
                if [[ "${lib32_url}" =~ (cachyos\.org|pkgbuild\.com|archlinux\.org|chaotic\.cx) ]] && [[ "${lib32_url}" =~ \.pkg\.tar\.zst$ ]]; then
                    dl_items+=("${lib32_url}|${lib32_file}|${lib32_url}.sig|${lib32_file}.sig")
                else
                    dl_items+=("${lib32_url}|${lib32_file}")
                fi
            fi
        fi

        if [ "${extra_url}" != "NONE" ] && [ -n "${extra_url}" ]; then
            IFS=',' read -ra EXTRA_URLS <<< "${extra_url}"
            for single_extra_url in "${EXTRA_URLS[@]}"; do
                [ -n "${single_extra_url}" ] || continue
                local extra_file="${cache_dir}/$(basename "${single_extra_url}")"
                if [ ! -f "${extra_file}" ] || [ ! -s "${extra_file}" ]; then
                    if [[ "${single_extra_url}" =~ (cachyos\.org|pkgbuild\.com|archlinux\.org|chaotic\.cx) ]] && [[ "${single_extra_url}" =~ \.pkg\.tar\.zst$ ]]; then
                        dl_items+=("${single_extra_url}|${extra_file}|${single_extra_url}.sig|${extra_file}.sig")
                    else
                        dl_items+=("${single_extra_url}|${extra_file}")
                    fi
                fi
            done
        fi

        if [ ${#dl_items[@]} -gt 0 ]; then
            if ! download_parallel_pacman "Underpants Gnomes: ${pkg_id}" "${dl_items[@]}"; then
                log_error "Failed to download packages for ${pkg_id}."
                rm -rf "${staging_base}"
                return 1
            fi
        fi

        if [ -f "${main_file}.sig" ]; then
            if ! verify_cachyos_gpg_signature "${main_file}" "${main_file}.sig"; then
                log_error "GPG signature verification failed for ${pkg_id}! Aborting transmutation to protect system integrity."
                rm -rf "${staging_base}"
                return 1
            fi
        elif [[ "${main_url}" =~ (cachyos\.org|pkgbuild\.com|archlinux\.org|chaotic\.cx) ]] && [[ "${main_url}" =~ \.pkg\.tar\.zst$ ]]; then
            log_error "Missing required GPG signature for official upstream package ${pkg_id}!"
            rm -rf "${staging_base}"
            return 1
        fi

        if [[ "${main_file}" =~ \.deb$ ]]; then
            (
                cd "${tmp_extract}/main"
                ar x "${main_file}" 2>/dev/null || true
                if [ -f data.tar.zst ]; then
                    tar --zstd -xf data.tar.zst 2>/dev/null || true
                elif [ -f data.tar.xz ]; then
                    tar -xf data.tar.xz 2>/dev/null || true
                elif [ -f data.tar.gz ]; then
                    tar -xf data.tar.gz 2>/dev/null || true
                fi
                rm -f control.tar.* data.tar.* debian-binary 2>/dev/null || true
            )
        elif [[ "${main_file}" =~ \.zip$ ]] || [[ "${main_url}" =~ download\?file= ]]; then
            unzip -q -o "${main_file}" -d "${tmp_extract}/main" 2>/dev/null || true
            find "${tmp_extract}/main" -type f \( -name "*.tar.gz" -o -name "*.tar.xz" -o -name "*.tgz" \) | while read -r inner_tar; do
                tar -xf "${inner_tar}" -C "${tmp_extract}/main" 2>/dev/null || true
                rm -f "${inner_tar}" 2>/dev/null || true
            done
        else
            tar --zstd -xf "${main_file}" -C "${tmp_extract}/main" 2>/dev/null || tar -xf "${main_file}" -C "${tmp_extract}/main" 2>/dev/null || true
        fi
    fi

    # Extract 32-bit Multilib if present
    if [ "${lib32_url}" != "NONE" ] && [ -n "${lib32_url}" ]; then
        local lib32_file="${cache_dir}/$(basename "${lib32_url}")"
        if [ -f "${lib32_file}" ]; then
            if ! verify_cachyos_gpg_signature "${lib32_file}" "${lib32_file}.sig"; then
                log_error "GPG signature verification failed for 32-bit ${pkg_id}! Aborting."
                rm -rf "${staging_base}"
                return 1
            fi
            tar --zstd -xf "${lib32_file}" -C "${tmp_extract}/lib32" 2>/dev/null || true
        fi
    fi

    # Extract Extra subpackage(s) if present (e.g. scx-scheds, python-vdf, icoextract, pefile)
    if [ "${extra_url}" != "NONE" ] && [ -n "${extra_url}" ]; then
        IFS=',' read -ra EXTRA_URLS <<< "${extra_url}"
        local extra_idx=0
        for single_extra_url in "${EXTRA_URLS[@]}"; do
            [ -n "${single_extra_url}" ] || continue
            extra_idx=$((extra_idx + 1))
            local extra_file="${cache_dir}/$(basename "${single_extra_url}")"
            if [ -f "${extra_file}" ]; then
                if [ -f "${extra_file}.sig" ]; then
                    if ! verify_cachyos_gpg_signature "${extra_file}" "${extra_file}.sig"; then
                        log_warn "GPG signature verification failed for auxiliary $(basename "${single_extra_url}"). Skipping."
                        continue
                    fi
                fi
                mkdir -p "${tmp_extract}/extra_${extra_idx}"
                tar --zstd -xf "${extra_file}" -C "${tmp_extract}/extra_${extra_idx}" 2>/dev/null || tar -xf "${extra_file}" -C "${tmp_extract}/extra_${extra_idx}" 2>/dev/null || true
            fi
        done
    fi

    # Map file hierarchy into Slackware standard structure:
    if [ "${pkg_id}" = "obs-studio" ]; then
        log_info "Packaging OBS Studio as isolated App-Bundle in /opt/obs-studio..."
        mkdir -p "${staging_root}/opt/obs-studio/bin" \
                 "${staging_root}/opt/obs-studio/lib" \
                 "${staging_root}/opt/obs-studio/share" \
                 "${staging_root}/usr/bin" \
                 "${staging_root}/usr/share" \
                 "${staging_root}/install"

        # Copy main package into /opt/obs-studio
        if [ -d "${tmp_extract}/main/usr/bin" ]; then
            cp -a "${tmp_extract}/main/usr/bin/." "${staging_root}/opt/obs-studio/bin/"
        fi
        if [ -d "${tmp_extract}/main/usr/lib" ]; then
            cp -a "${tmp_extract}/main/usr/lib/." "${staging_root}/opt/obs-studio/lib/"
        fi
        if [ -d "${tmp_extract}/main/usr/share" ]; then
            cp -a "${tmp_extract}/main/usr/share/." "${staging_root}/opt/obs-studio/share/"
            if [ -d "${tmp_extract}/main/usr/share/applications" ]; then
                mkdir -p "${staging_root}/usr/share/applications"
                cp -a "${tmp_extract}/main/usr/share/applications/." "${staging_root}/usr/share/applications/"
            fi
            if [ -d "${tmp_extract}/main/usr/share/icons" ]; then
                mkdir -p "${staging_root}/usr/share/icons"
                cp -a "${tmp_extract}/main/usr/share/icons/." "${staging_root}/usr/share/icons/"
            fi
            if [ -d "${tmp_extract}/main/usr/share/pixmaps" ]; then
                mkdir -p "${staging_root}/usr/share/pixmaps"
                cp -a "${tmp_extract}/main/usr/share/pixmaps/." "${staging_root}/usr/share/pixmaps/"
            fi
            if [ -d "${tmp_extract}/main/usr/share/metainfo" ]; then
                mkdir -p "${staging_root}/usr/share/metainfo"
                cp -a "${tmp_extract}/main/usr/share/metainfo/." "${staging_root}/usr/share/metainfo/"
            fi
        fi

        # Copy auxiliary packages (bundled python 3.14/3.13, mbedtls, browser plugin, CEF, WebRTC) into /opt/obs-studio/lib
        for extra_dir in "${tmp_extract}"/extra*; do
            [ -d "${extra_dir}" ] || continue
            if [ -d "${extra_dir}/usr/lib" ]; then
                cp -a "${extra_dir}/usr/lib/." "${staging_root}/opt/obs-studio/lib/"
            fi
            if [ -d "${extra_dir}/usr/lib64" ]; then
                cp -a "${extra_dir}/usr/lib64/." "${staging_root}/opt/obs-studio/lib/"
            fi
            if [ -d "${extra_dir}/usr/share" ]; then
                cp -a "${extra_dir}/usr/share/." "${staging_root}/opt/obs-studio/share/"
            fi
            if [ -d "${extra_dir}/opt" ]; then
                cp -a "${extra_dir}/opt/." "${staging_root}/opt/"
            fi
        done

        # If CEF shared library is missing, cleanly omit obs-browser plugin to prevent startup error popup
        if [ ! -f "${staging_root}/opt/obs-studio/lib/libcef.so" ] && \
           [ ! -f "${staging_root}/opt/obs-studio/lib/cef/libcef.so" ] && \
           [ ! -f "${staging_root}/opt/obs-studio/lib/obs-plugins/libcef.so" ] && \
           [ ! -f "${staging_root}/opt/obs-studio/lib/obs-plugins/obs-browser/libcef.so" ]; then
            rm -f "${staging_root}/opt/obs-studio/lib/obs-plugins/obs-browser.so" 2>/dev/null || true
            rm -rf "${staging_root}/opt/obs-studio/share/obs/obs-plugins/obs-browser" 2>/dev/null || true
        fi

        # Create wrapper scripts
        cat << 'OBS_WRAPPER_EOF' > "${staging_root}/usr/bin/obs"
#!/bin/sh
# OBS Studio Isolated App-Bundle Launcher for Slackware
export OBS_PATH="/opt/obs-studio"
export LD_LIBRARY_PATH="/opt/obs-studio/lib:/opt/obs-studio/lib/obs-plugins:/opt/obs-studio/lib/cef:${LD_LIBRARY_PATH:-}"

# Auto-bridge external system plugins into user profile if not directly inside bundle
if [ -d /usr/lib64/obs-plugins ]; then
  for ext_so in /usr/lib64/obs-plugins/*.so; do
    [ -f "${ext_so}" ] || continue
    bname=$(basename "${ext_so}")
    pname="${bname%.so}"
    if [ ! -f "/opt/obs-studio/lib/obs-plugins/${bname}" ]; then
      mkdir -p "${HOME}/.config/obs-studio/plugins/${pname}/bin/64bit" 2>/dev/null || true
      ln -sf "${ext_so}" "${HOME}/.config/obs-studio/plugins/${pname}/bin/64bit/${bname}" 2>/dev/null || true
      if [ -d "/usr/share/obs/obs-plugins/${pname}" ]; then
        mkdir -p "${HOME}/.config/obs-studio/plugins/${pname}" 2>/dev/null || true
        ln -sfn "/usr/share/obs/obs-plugins/${pname}" "${HOME}/.config/obs-studio/plugins/${pname}/data" 2>/dev/null || true
      fi
    fi
  done
fi

for pyd in /opt/obs-studio/lib/python3.*; do
  if [ -d "$pyd" ]; then
    export PYTHONHOME="$pyd"
    export PYTHONPATH="$pyd:$pyd/site-packages:${PYTHONPATH:-}"
    break
  fi
done
exec /opt/obs-studio/bin/obs "$@"
OBS_WRAPPER_EOF
        chmod 755 "${staging_root}/usr/bin/obs"

        if [ -f "${staging_root}/opt/obs-studio/bin/obs-ffmpeg-mux" ]; then
            cat << 'OBS_MUX_EOF' > "${staging_root}/usr/bin/obs-ffmpeg-mux"
#!/bin/sh
export LD_LIBRARY_PATH="/opt/obs-studio/lib:${LD_LIBRARY_PATH:-}"
exec /opt/obs-studio/bin/obs-ffmpeg-mux "$@"
OBS_MUX_EOF
            chmod 755 "${staging_root}/usr/bin/obs-ffmpeg-mux"
        fi

        for df in "${staging_root}/usr/share/applications"/*.desktop; do
            [ -f "${df}" ] || continue
            sed -i 's|^Exec=obs.*|Exec=/usr/bin/obs %U|g; s|^TryExec=obs.*|TryExec=/usr/bin/obs|g' "${df}"
        done
    elif [ "${pkg_id}" = "lutris" ]; then
        log_info "Packaging Lutris as isolated App-Bundle in /opt/lutris..."
        mkdir -p "${staging_root}/opt/lutris/bin" \
                 "${staging_root}/opt/lutris/lib" \
                 "${staging_root}/opt/lutris/share" \
                 "${staging_root}/usr/bin" \
                 "${staging_root}/usr/share" \
                 "${staging_root}/install"

        # Copy main package into /opt/lutris
        if [ -d "${tmp_extract}/main/usr/bin" ]; then
            cp -a "${tmp_extract}/main/usr/bin/." "${staging_root}/opt/lutris/bin/"
        fi
        if [ -d "${tmp_extract}/main/usr/lib" ]; then
            cp -a "${tmp_extract}/main/usr/lib/." "${staging_root}/opt/lutris/lib/"
        fi
        if [ -d "${tmp_extract}/main/usr/share" ]; then
            cp -a "${tmp_extract}/main/usr/share/." "${staging_root}/opt/lutris/share/"
            if [ -d "${tmp_extract}/main/usr/share/applications" ]; then
                mkdir -p "${staging_root}/usr/share/applications"
                cp -a "${tmp_extract}/main/usr/share/applications/." "${staging_root}/usr/share/applications/"
            fi
            if [ -d "${tmp_extract}/main/usr/share/icons" ]; then
                mkdir -p "${staging_root}/usr/share/icons"
                cp -a "${tmp_extract}/main/usr/share/icons/." "${staging_root}/usr/share/icons/"
            fi
            if [ -d "${tmp_extract}/main/usr/share/pixmaps" ]; then
                mkdir -p "${staging_root}/usr/share/pixmaps"
                cp -a "${tmp_extract}/main/usr/share/pixmaps/." "${staging_root}/usr/share/pixmaps/"
            fi
            if [ -d "${tmp_extract}/main/usr/share/metainfo" ]; then
                mkdir -p "${staging_root}/usr/share/metainfo"
                cp -a "${tmp_extract}/main/usr/share/metainfo/." "${staging_root}/usr/share/metainfo/"
            fi
        fi

        # Universal application icon harvesting for Lutris (hicolor, breeze, breeze-dark, pixmaps)
        mkdir -p "${staging_root}/usr/share/icons/hicolor/scalable/apps" \
                 "${staging_root}/usr/share/icons/hicolor/128x128/apps" \
                 "${staging_root}/usr/share/icons/hicolor/64x64/apps" \
                 "${staging_root}/usr/share/icons/hicolor/48x48/apps" \
                 "${staging_root}/usr/share/icons/hicolor/32x32/apps" \
                 "${staging_root}/usr/share/icons/hicolor/24x24/apps" \
                 "${staging_root}/usr/share/icons/hicolor/22x22/apps" \
                 "${staging_root}/usr/share/icons/hicolor/16x16/apps" \
                 "${staging_root}/usr/share/icons/breeze/apps/48" \
                 "${staging_root}/usr/share/icons/breeze/apps/32" \
                 "${staging_root}/usr/share/icons/breeze-dark/apps/48" \
                 "${staging_root}/usr/share/icons/breeze-dark/apps/32" \
                 "${staging_root}/usr/share/pixmaps" \
                 "${staging_root}/usr/share/applications"

        # Copy actual PNG/SVG icon files into standard resolutions
        for sz in 16x16 22x22 24x24 32x32 48x48 64x64 128x128 256x256 512x512 scalable; do
            local src_dir="${tmp_extract}/main/usr/share/icons/hicolor/${sz}/apps"
            if [ -d "${src_dir}" ]; then
                mkdir -p "${staging_root}/usr/share/icons/hicolor/${sz}/apps"
                for src_file in "${src_dir}"/*; do
                    [ -f "${src_file}" ] || continue
                    local bname
                    bname=$(basename "${src_file}")
                    if [[ "${bname}" =~ \.svg$ ]]; then
                        cp -L "${src_file}" "${staging_root}/usr/share/icons/hicolor/${sz}/apps/net.lutris.Lutris.svg" 2>/dev/null || true
                        ln -sf "net.lutris.Lutris.svg" "${staging_root}/usr/share/icons/hicolor/${sz}/apps/lutris.svg" 2>/dev/null || true
                    elif [[ "${bname}" =~ \.png$ ]]; then
                        cp -L "${src_file}" "${staging_root}/usr/share/icons/hicolor/${sz}/apps/net.lutris.Lutris.png" 2>/dev/null || true
                        ln -sf "net.lutris.Lutris.png" "${staging_root}/usr/share/icons/hicolor/${sz}/apps/lutris.png" 2>/dev/null || true
                    fi
                done
            fi
        done

        # Populate /usr/share/pixmaps with real image files (dereferenced with cp -L)
        rm -f "${staging_root}/usr/share/pixmaps"/*lutris* 2>/dev/null || true
        if [ -f "${staging_root}/usr/share/icons/hicolor/128x128/apps/net.lutris.Lutris.png" ]; then
            cp -L "${staging_root}/usr/share/icons/hicolor/128x128/apps/net.lutris.Lutris.png" "${staging_root}/usr/share/pixmaps/net.lutris.Lutris.png" 2>/dev/null || true
            cp -L "${staging_root}/usr/share/icons/hicolor/128x128/apps/net.lutris.Lutris.png" "${staging_root}/usr/share/pixmaps/lutris.png" 2>/dev/null || true
            cp -L "${staging_root}/usr/share/icons/hicolor/128x128/apps/net.lutris.Lutris.png" "${staging_root}/usr/share/icons/breeze/apps/48/net.lutris.Lutris.png" 2>/dev/null || true
            cp -L "${staging_root}/usr/share/icons/hicolor/128x128/apps/net.lutris.Lutris.png" "${staging_root}/usr/share/icons/breeze/apps/48/lutris.png" 2>/dev/null || true
            cp -L "${staging_root}/usr/share/icons/hicolor/128x128/apps/net.lutris.Lutris.png" "${staging_root}/usr/share/icons/breeze-dark/apps/48/net.lutris.Lutris.png" 2>/dev/null || true
            cp -L "${staging_root}/usr/share/icons/hicolor/128x128/apps/net.lutris.Lutris.png" "${staging_root}/usr/share/icons/breeze-dark/apps/48/lutris.png" 2>/dev/null || true
        elif [ -f "${staging_root}/usr/share/icons/hicolor/64x64/apps/net.lutris.Lutris.png" ]; then
            cp -L "${staging_root}/usr/share/icons/hicolor/64x64/apps/net.lutris.Lutris.png" "${staging_root}/usr/share/pixmaps/net.lutris.Lutris.png" 2>/dev/null || true
            cp -L "${staging_root}/usr/share/icons/hicolor/64x64/apps/net.lutris.Lutris.png" "${staging_root}/usr/share/pixmaps/lutris.png" 2>/dev/null || true
        fi

        if [ -f "${staging_root}/usr/share/icons/hicolor/scalable/apps/net.lutris.Lutris.svg" ]; then
            cp -L "${staging_root}/usr/share/icons/hicolor/scalable/apps/net.lutris.Lutris.svg" "${staging_root}/usr/share/pixmaps/net.lutris.Lutris.svg" 2>/dev/null || true
            cp -L "${staging_root}/usr/share/icons/hicolor/scalable/apps/net.lutris.Lutris.svg" "${staging_root}/usr/share/pixmaps/lutris.svg" 2>/dev/null || true
            cp -L "${staging_root}/usr/share/icons/hicolor/scalable/apps/net.lutris.Lutris.svg" "${staging_root}/usr/share/icons/breeze/apps/48/net.lutris.Lutris.svg" 2>/dev/null || true
            cp -L "${staging_root}/usr/share/icons/hicolor/scalable/apps/net.lutris.Lutris.svg" "${staging_root}/usr/share/icons/breeze/apps/48/lutris.svg" 2>/dev/null || true
            cp -L "${staging_root}/usr/share/icons/hicolor/scalable/apps/net.lutris.Lutris.svg" "${staging_root}/usr/share/icons/breeze-dark/apps/48/net.lutris.Lutris.svg" 2>/dev/null || true
            cp -L "${staging_root}/usr/share/icons/hicolor/scalable/apps/net.lutris.Lutris.svg" "${staging_root}/usr/share/icons/breeze-dark/apps/48/lutris.svg" 2>/dev/null || true
        fi

        # Remove duplicate mime helper desktop file
        rm -f "${staging_root}/usr/share/applications/net.lutris.Lutris1.desktop" 2>/dev/null || true

        # Write clean desktop entries with absolute icon paths to guarantee instant display
        cat << 'LUTRIS_DESKTOP_EOF' > "${staging_root}/usr/share/applications/net.lutris.Lutris.desktop"
[Desktop Entry]
Name=Lutris
Comment=Video game preservation platform for Slackware
Exec=/usr/bin/lutris %U
Icon=/usr/share/pixmaps/net.lutris.Lutris.png
Terminal=false
Type=Application
StartupWMClass=lutris
Categories=Game;
MimeType=x-scheme-handler/lutris;
LUTRIS_DESKTOP_EOF

        cat << 'LUTRIS_DESKTOP_ALT_EOF' > "${staging_root}/usr/share/applications/lutris.desktop"
[Desktop Entry]
Name=Lutris
Comment=Video game preservation platform for Slackware
Exec=/usr/bin/lutris %U
Icon=/usr/share/pixmaps/lutris.png
Terminal=false
Type=Application
StartupWMClass=lutris
Categories=Game;
MimeType=x-scheme-handler/lutris;
LUTRIS_DESKTOP_ALT_EOF

        # Copy auxiliary packages (webkit2gtk, libsoup, python-moddb, python-pypresence, python-evdev, python-distro)
        for extra_dir in "${tmp_extract}"/extra*; do
            [ -d "${extra_dir}" ] || continue
            if [ -d "${extra_dir}/usr/lib" ]; then
                cp -a "${extra_dir}/usr/lib/." "${staging_root}/opt/lutris/lib/"
            fi
            if [ -d "${extra_dir}/usr/lib64" ]; then
                cp -a "${extra_dir}/usr/lib64/." "${staging_root}/opt/lutris/lib/"
            fi
            if [ -d "${extra_dir}/usr/share" ]; then
                cp -a "${extra_dir}/usr/share/." "${staging_root}/opt/lutris/share/"
            fi
        done

        # Patch webconnect_dialog.py in Lutris site-packages so WebKit2 absence is non-fatal:
        python3 - "${staging_root}" << 'PYPATCH'
import sys, os, glob, re

root_dir = sys.argv[1]
for path in glob.glob(os.path.join(root_dir, "opt", "lutris", "**", "webconnect_dialog.py"), recursive=True):
    try:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()

        safe_replacement = """try:
    try:
        gi.require_version("WebKit2", "4.1")
    except Exception:
        gi.require_version("WebKit2", "4.0")
    from gi.repository import WebKit2
except Exception:
    class _DummyWebKit:
        def __getattr__(self, name):
            return object
    WebKit2 = _DummyWebKit()"""

        new_content = re.sub(
            r'try:\s+gi\.require_version\("WebKit2",\s*"4\.1"\).*?from\s+gi\.repository\s+import\s+WebKit2',
            safe_replacement,
            content,
            flags=re.DOTALL
        )
        if new_content == content:
            new_content = re.sub(
                r'gi\.require_version\("WebKit2".*?from\s+gi\.repository\s+import\s+WebKit2',
                safe_replacement,
                content,
                flags=re.DOTALL
            )

        with open(path, "w", encoding="utf-8") as f:
            f.write(new_content)
    except Exception:
        pass
PYPATCH

        # Create launcher wrapper
        cat << 'LUTRIS_WRAPPER_EOF' > "${staging_root}/usr/bin/lutris"
#!/bin/sh
# Lutris Isolated App-Bundle Launcher for Slackware
export LUTRIS_PATH="/opt/lutris"
export GI_TYPELIB_PATH="/opt/lutris/lib/girepository-1.0:/usr/lib64/girepository-1.0:${GI_TYPELIB_PATH:-}"
export LD_LIBRARY_PATH="/opt/lutris/lib:/opt/lutris/lib64:${LD_LIBRARY_PATH:-}"
for sp in /opt/lutris/lib/python3.*/site-packages /opt/lutris/lib64/python3.*/site-packages; do
  if [ -d "$sp" ]; then
    export PYTHONPATH="$sp:${PYTHONPATH:-}"
  fi
done
exec /usr/bin/python3 /opt/lutris/bin/lutris "$@"
LUTRIS_WRAPPER_EOF
        chmod 755 "${staging_root}/usr/bin/lutris"

        for df in "${staging_root}/usr/share/applications"/*.desktop; do
            [ -f "${df}" ] || continue
            sed -i 's|^Exec=lutris.*|Exec=/usr/bin/lutris %U|g; s|^TryExec=lutris.*|TryExec=/usr/bin/lutris|g' "${df}"
        done
    elif [ "${pkg_id}" = "pear-desktop" ]; then
        log_info "Packaging Pear Desktop (YouTube Music) as isolated App-Bundle in /opt/pear-desktop..."
        mkdir -p "${staging_root}/opt/pear-desktop" \
                 "${staging_root}/opt/pear-desktop/lib" \
                 "${staging_root}/opt/pear-desktop/resources" \
                 "${staging_root}/usr/bin" \
                 "${staging_root}/usr/share/applications" \
                 "${staging_root}/usr/share/icons" \
                 "${staging_root}/usr/share/pixmaps" \
                 "${staging_root}/install"

        # Copy Electron42 runtime and auxiliary libraries (libjpeg.so.8) into /opt/pear-desktop
        for extra_dir in "${tmp_extract}"/extra*; do
            [ -d "${extra_dir}" ] || continue
            if [ -d "${extra_dir}/usr/lib/electron42" ]; then
                cp -a "${extra_dir}/usr/lib/electron42/." "${staging_root}/opt/pear-desktop/"
            fi
            if [ -d "${extra_dir}/usr/lib" ]; then
                cp -a "${extra_dir}/usr/lib"/libjpeg*.so* "${staging_root}/opt/pear-desktop/lib/" 2>/dev/null || true
                cp -a "${extra_dir}/usr/lib"/libturbojpeg*.so* "${staging_root}/opt/pear-desktop/lib/" 2>/dev/null || true
            fi
            if [ -d "${extra_dir}/usr/lib64" ]; then
                cp -a "${extra_dir}/usr/lib64"/libjpeg*.so* "${staging_root}/opt/pear-desktop/lib/" 2>/dev/null || true
                cp -a "${extra_dir}/usr/lib64"/libturbojpeg*.so* "${staging_root}/opt/pear-desktop/lib/" 2>/dev/null || true
            fi
        done

        # Copy app.asar and unpacked assets into /opt/pear-desktop
        if [ -d "${tmp_extract}/main/usr/lib/pear-desktop" ]; then
            cp -a "${tmp_extract}/main/usr/lib/pear-desktop/." "${staging_root}/opt/pear-desktop/"
            if [ -f "${tmp_extract}/main/usr/lib/pear-desktop/app.asar" ]; then
                cp -a "${tmp_extract}/main/usr/lib/pear-desktop/app.asar" "${staging_root}/opt/pear-desktop/resources/"
            fi
            if [ -d "${tmp_extract}/main/usr/lib/pear-desktop/app.asar.unpacked" ]; then
                cp -a "${tmp_extract}/main/usr/lib/pear-desktop/app.asar.unpacked" "${staging_root}/opt/pear-desktop/resources/"
            fi
        fi

        # Ensure electron binary permissions
        [ -f "${staging_root}/opt/pear-desktop/electron" ] && chmod 755 "${staging_root}/opt/pear-desktop/electron"
        [ -f "${staging_root}/opt/pear-desktop/chrome-sandbox" ] && chmod 4755 "${staging_root}/opt/pear-desktop/chrome-sandbox" 2>/dev/null || true

        # Copy desktop files
        if [ -d "${tmp_extract}/main/usr/share/applications" ]; then
            cp -a "${tmp_extract}/main/usr/share/applications/." "${staging_root}/usr/share/applications/"
        fi

        # Create standard /usr/share/applications/pear-desktop.desktop
        cat << 'PEAR_DESKTOP_EOF' > "${staging_root}/usr/share/applications/pear-desktop.desktop"
[Desktop Entry]
Name=Pear Desktop
GenericName=YouTube Music Desktop
Comment=YouTube Music Desktop App with Custom Plugins
Exec=/usr/bin/pear-desktop %U
Terminal=false
Type=Application
Icon=pear-desktop
Categories=AudioVideo;Audio;Player;Music;
StartupWMClass=pear-desktop
MimeType=x-scheme-handler/youtubemusic;
PEAR_DESKTOP_EOF

        # Copy icons
        if [ -d "${tmp_extract}/main/usr/share/icons" ]; then
            cp -a "${tmp_extract}/main/usr/share/icons/." "${staging_root}/usr/share/icons/"
        fi
        if [ -d "${tmp_extract}/main/usr/lib/pear-desktop/app.asar.unpacked/assets/generated/icons/png" ]; then
            for isize in 16 24 32 48 64 128 256 512 1024; do
                local icon_src="${tmp_extract}/main/usr/lib/pear-desktop/app.asar.unpacked/assets/generated/icons/png/${isize}x${isize}.png"
                if [ -f "${icon_src}" ]; then
                    mkdir -p "${staging_root}/usr/share/icons/hicolor/${isize}x${isize}/apps"
                    cp -a "${icon_src}" "${staging_root}/usr/share/icons/hicolor/${isize}x${isize}/apps/pear-desktop.png"
                    cp -a "${icon_src}" "${staging_root}/usr/share/icons/hicolor/${isize}x${isize}/apps/youtube-music.png"
                    cp -a "${icon_src}" "${staging_root}/usr/share/icons/hicolor/${isize}x${isize}/apps/com.github.th-ch.youtube-music.png"
                fi
            done
        fi

        # Cross-desktop icon symmetry
        if [ -d "${staging_root}/usr/share/icons" ]; then
            find "${staging_root}/usr/share/icons" -type f -name "com.github.th-ch.youtube-music.png" | while read -r icon_file; do
                icon_dir="$(dirname "${icon_file}")"
                ln -sf "com.github.th-ch.youtube-music.png" "${icon_dir}/pear-desktop.png" 2>/dev/null || true
                ln -sf "com.github.th-ch.youtube-music.png" "${icon_dir}/youtube-music.png" 2>/dev/null || true
            done
        fi
        mkdir -p "${staging_root}/usr/share/pixmaps"
        if [ -f "${staging_root}/usr/share/icons/hicolor/128x128/apps/com.github.th-ch.youtube-music.png" ]; then
            cp -a "${staging_root}/usr/share/icons/hicolor/128x128/apps/com.github.th-ch.youtube-music.png" "${staging_root}/usr/share/pixmaps/pear-desktop.png" 2>/dev/null || true
            cp -a "${staging_root}/usr/share/icons/hicolor/128x128/apps/com.github.th-ch.youtube-music.png" "${staging_root}/usr/share/pixmaps/youtube-music.png" 2>/dev/null || true
            cp -a "${staging_root}/usr/share/icons/hicolor/128x128/apps/com.github.th-ch.youtube-music.png" "${staging_root}/usr/share/pixmaps/com.github.th-ch.youtube-music.png" 2>/dev/null || true
        fi

        # Create launcher wrapper
        cat << 'PEAR_WRAPPER_EOF' > "${staging_root}/usr/bin/pear-desktop"
#!/bin/sh
# Pear Desktop (YouTube Music) Isolated App-Bundle Launcher for Slackware
export LD_LIBRARY_PATH="/opt/pear-desktop:/opt/pear-desktop/lib:${LD_LIBRARY_PATH:-}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
PEAR_USER_FLAGS=""
if [ -f "$XDG_CONFIG_HOME/pear-flags.conf" ]; then
    PEAR_USER_FLAGS="$(grep -v '^#' "$XDG_CONFIG_HOME/pear-flags.conf" | tr '\n' ' ')"
fi
export ELECTRON_IS_DEV=0
exec /opt/pear-desktop/electron /opt/pear-desktop/app.asar ${PEAR_USER_FLAGS} "$@"
PEAR_WRAPPER_EOF
        chmod 755 "${staging_root}/usr/bin/pear-desktop"
        ln -sf pear-desktop "${staging_root}/usr/bin/youtube-music"

        for df in "${staging_root}/usr/share/applications"/*.desktop; do
            [ -f "${df}" ] || continue
            sed -i 's|^Exec=.*|Exec=/usr/bin/pear-desktop %U|g; s|^TryExec=.*|TryExec=/usr/bin/pear-desktop|g' "${df}"
        done
    else
        # Standard native package transmutation:
        mkdir -p "${staging_root}/usr/bin" \
                 "${staging_root}/usr/lib64" \
                 "${staging_root}/usr/lib" \
                 "${staging_root}/usr/share" \
                 "${staging_root}/etc" \
                 "${staging_root}/lib/udev/rules.d" \
                 "${staging_root}/install"

        # Copy files from main extract:
        if [ -d "${tmp_extract}/main/opt" ]; then
            mkdir -p "${staging_root}/opt"
            cp -a "${tmp_extract}/main/opt/." "${staging_root}/opt/"
        fi

        if [ -d "${tmp_extract}/main/usr/bin" ]; then
            cp -a "${tmp_extract}/main/usr/bin/." "${staging_root}/usr/bin/"
        fi

        if [ -d "${tmp_extract}/main/usr/share" ]; then
            cp -a "${tmp_extract}/main/usr/share/." "${staging_root}/usr/share/"
        fi

        if [ -d "${tmp_extract}/main/etc" ]; then
            cp -a "${tmp_extract}/main/etc/." "${staging_root}/etc/"
        fi

        if [ -d "${tmp_extract}/main/usr/lib/udev/rules.d" ]; then
            cp -a "${tmp_extract}/main/usr/lib/udev/rules.d/." "${staging_root}/lib/udev/rules.d/"
        elif [ -d "${tmp_extract}/main/lib/udev/rules.d" ]; then
            cp -a "${tmp_extract}/main/lib/udev/rules.d/." "${staging_root}/lib/udev/rules.d/"
        fi

        if [ -d "${tmp_extract}/main/usr/lib" ]; then
            (
                cd "${tmp_extract}/main/usr/lib"
                find . -maxdepth 1 ! -name "." ! -name "udev" ! -name "systemd" ! -name "environment.d" -exec cp -a {} "${staging_root}/usr/lib64/" \; 2>/dev/null || true
            )
        fi

        if [ -d "${tmp_extract}/main/usr/src" ]; then
            mkdir -p "${staging_root}/usr/src"
            cp -a "${tmp_extract}/main/usr/src/." "${staging_root}/usr/src/"
        fi

        # OBS Plugin Transmutation Bridge
        if [[ "${pkg_id}" =~ ^obs- ]] && [ "${pkg_id}" != "obs-studio" ] && [ "${pkg_id}" != "obs-vkcapture" ]; then
            mkdir -p "${staging_root}/usr/lib64/obs-plugins" \
                     "${staging_root}/usr/share/obs/obs-plugins" \
                     "${staging_root}/opt/obs-studio/lib/obs-plugins" \
                     "${staging_root}/opt/obs-studio/share/obs/obs-plugins"

            # 1. Copy plugin subdirectories (like advanced-scene-switcher-plugins)
            find "${tmp_extract}/main" -mindepth 1 -type d -name "*-plugins" ! -name "obs-plugins" | while read -r psubdir; do
                cp -a "${psubdir}" "${staging_root}/usr/lib64/obs-plugins/" 2>/dev/null || true
                cp -a "${psubdir}" "${staging_root}/opt/obs-studio/lib/obs-plugins/" 2>/dev/null || true
            done

            # 2. Copy only top-level 64-bit .so plugin binaries (excluding modular subplugins inside subdirs)
            find "${tmp_extract}/main" -type f \( -name "*.so" -o -name "*.so.*" \) | while read -r so_file; do
                if file "${so_file}" 2>/dev/null | grep -qE "ARM|aarch64|32-bit"; then
                    continue
                fi
                # Do NOT copy files that belong inside subdirectories (like advanced-scene-switcher-plugins/)
                if echo "${so_file}" | grep -qE "/[a-zA-Z0-9_\-]+-plugins/"; then
                    continue
                fi
                bso=$(basename "${so_file}")
                # For advanced-scene-switcher, ensure sub-plugins are only kept in the subfolder
                if [ "${pkg_id}" = "obs-advanced-scene-switcher" ]; then
                    if [ "${bso}" != "advanced-scene-switcher.so" ] && [ "${bso}" != "advanced-scene-switcher-lib.so.1" ]; then
                        continue
                    fi
                fi
                cp -a "${so_file}" "${staging_root}/usr/lib64/obs-plugins/${bso}" 2>/dev/null || true
                cp -a "${so_file}" "${staging_root}/opt/obs-studio/lib/obs-plugins/${bso}" 2>/dev/null || true
            done

            # 3. Copy data directories (locales, shaders, etc.)
            if [ -d "${tmp_extract}/main/usr/share/obs/obs-plugins" ]; then
                cp -a "${tmp_extract}/main/usr/share/obs/obs-plugins/." "${staging_root}/usr/share/obs/obs-plugins/" 2>/dev/null || true
                cp -a "${tmp_extract}/main/usr/share/obs/obs-plugins/." "${staging_root}/opt/obs-studio/share/obs/obs-plugins/" 2>/dev/null || true
            fi

            find "${tmp_extract}/main" -type d -name "data" | while read -r ddir; do
                pname=$(basename "$(dirname "${ddir}")")
                if [ "${pname}" != "share" ] && [ "${pname}" != "main" ] && [ "${pname}" != "extract" ] && [ "${pname}" != "obs-plugins" ]; then
                    mkdir -p "${staging_root}/usr/share/obs/obs-plugins/${pname}" \
                             "${staging_root}/opt/obs-studio/share/obs/obs-plugins/${pname}"
                    cp -a "${ddir}/." "${staging_root}/usr/share/obs/obs-plugins/${pname}/" 2>/dev/null || true
                    cp -a "${ddir}/." "${staging_root}/opt/obs-studio/share/obs/obs-plugins/${pname}/" 2>/dev/null || true
                fi
            done
        fi

        # Copy 32-bit Multilib files -> Slackware /usr/lib
        if [ -d "${tmp_extract}/lib32/usr/lib32" ]; then
            (
                cd "${tmp_extract}/lib32/usr/lib32"
                find . -maxdepth 1 ! -name "." ! -name "udev" ! -name "systemd" -exec cp -a {} "${staging_root}/usr/lib/" \; 2>/dev/null || true
            )
        elif [ -d "${tmp_extract}/lib32/usr/lib" ]; then
            (
                cd "${tmp_extract}/lib32/usr/lib"
                find . -maxdepth 1 ! -name "." ! -name "udev" ! -name "systemd" -exec cp -a {} "${staging_root}/usr/lib/" \; 2>/dev/null || true
            )
        fi

        # Copy Extra subpackage files:
        for extra_dir in "${tmp_extract}"/extra*; do
            [ -d "${extra_dir}" ] || continue
            if [ -d "${extra_dir}/usr/bin" ]; then
                cp -a "${extra_dir}/usr/bin/." "${staging_root}/usr/bin/"
            fi
            if [ -d "${extra_dir}/usr/lib" ]; then
                (
                    cd "${extra_dir}/usr/lib"
                    find . -maxdepth 1 ! -name "." ! -name "udev" ! -name "systemd" -exec cp -a {} "${staging_root}/usr/lib64/" \; 2>/dev/null || true
                )
            fi
            if [ -d "${extra_dir}/usr/lib64" ]; then
                (
                    cd "${extra_dir}/usr/lib64"
                    find . -maxdepth 1 ! -name "." ! -name "udev" ! -name "systemd" -exec cp -a {} "${staging_root}/usr/lib64/" \; 2>/dev/null || true
                )
            fi
            if [ -d "${extra_dir}/usr/share" ]; then
                cp -a "${extra_dir}/usr/share/." "${staging_root}/usr/share/"
            fi
            if [ -d "${extra_dir}/etc" ]; then
                mkdir -p "${staging_root}/etc"
                cp -a "${extra_dir}/etc/." "${staging_root}/etc/"
            fi
            if [ -d "${extra_dir}/usr/src" ]; then
                mkdir -p "${staging_root}/usr/src"
                cp -a "${extra_dir}/usr/src/." "${staging_root}/usr/src/"
            fi
        done

        # Remap Python site-packages from upstream (e.g. python3.14, python3.13) to host Slackware Python (python3.12)
        local py_sys_ver
        py_sys_ver=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null || echo "3.12")
        
        mkdir -p "${staging_root}/usr/lib64/python${py_sys_ver}/site-packages"
        for pydir in "${staging_root}/usr/lib64"/python3.* "${staging_root}/usr/lib"/python3.*; do
            [ -d "${pydir}/site-packages" ] || continue
            if [ "${pydir}" != "${staging_root}/usr/lib64/python${py_sys_ver}" ]; then
                log_info "Remapping Python site-packages ($(basename "${pydir}")) -> python${py_sys_ver}..."
                find "${pydir}/site-packages" -type f -name "*.so" 2>/dev/null | while read -r so_file; do
                    local bso
                    bso=$(basename "${so_file}")
                    if [[ "${bso}" =~ \.cpython-(31[3-9]|3[2-9][0-9]) ]] && [[ ! "${bso}" =~ \.abi3\. ]]; then
                        log_warn "Omitting incompatible binary CPython extension (${bso}) from host site-packages."
                        rm -f "${so_file}" 2>/dev/null || true
                    fi
                done
                cp -a "${pydir}/site-packages/." "${staging_root}/usr/lib64/python${py_sys_ver}/site-packages/"
                rm -rf "${pydir}" 2>/dev/null || true
            fi
        done
        find "${staging_root}/usr/lib64/python${py_sys_ver}/site-packages" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    fi

    # Browser conveniences in /usr/bin:
    if [ "${pkg_id}" = "brave" ]; then
        [ -f "${staging_root}/opt/brave.com/brave/brave" ] && [ ! -e "${staging_root}/usr/bin/brave" ] && ln -sf /opt/brave.com/brave/brave "${staging_root}/usr/bin/brave"
        [ -f "${staging_root}/usr/bin/brave-browser" ] && [ ! -e "${staging_root}/usr/bin/brave" ] && ln -sf brave-browser "${staging_root}/usr/bin/brave"
    fi
    if [ "${pkg_id}" = "zen-browser" ]; then
        [ -f "${staging_root}/opt/zen-browser/zen" ] && [ ! -e "${staging_root}/usr/bin/zen" ] && ln -sf /opt/zen-browser/zen "${staging_root}/usr/bin/zen"
        [ -f "${staging_root}/opt/zen-browser/zen" ] && [ ! -e "${staging_root}/usr/bin/zen-browser" ] && ln -sf /opt/zen-browser/zen "${staging_root}/usr/bin/zen-browser"
    fi
    if [ "${pkg_id}" = "google-chrome" ]; then
        [ -f "${staging_root}/usr/bin/google-chrome-stable" ] && [ ! -e "${staging_root}/usr/bin/google-chrome" ] && ln -sf google-chrome-stable "${staging_root}/usr/bin/google-chrome"
        [ -f "${staging_root}/opt/google/chrome/google-chrome" ] && [ ! -e "${staging_root}/usr/bin/google-chrome" ] && ln -sf /opt/google/chrome/google-chrome "${staging_root}/usr/bin/google-chrome"
    fi
    if [ "${pkg_id}" = "microsoft-edge" ]; then
        [ -f "${staging_root}/usr/bin/microsoft-edge-stable" ] && [ ! -e "${staging_root}/usr/bin/microsoft-edge" ] && ln -sf microsoft-edge-stable "${staging_root}/usr/bin/microsoft-edge"
        [ -f "${staging_root}/usr/bin/microsoft-edge" ] && [ ! -e "${staging_root}/usr/bin/edge" ] && ln -sf microsoft-edge "${staging_root}/usr/bin/edge"
        [ -f "${staging_root}/opt/microsoft/msedge/microsoft-edge" ] && [ ! -e "${staging_root}/usr/bin/microsoft-edge" ] && ln -sf /opt/microsoft/msedge/microsoft-edge "${staging_root}/usr/bin/microsoft-edge"
    fi
    if [ "${pkg_id}" = "vesktop" ]; then
        [ -f "${staging_root}/opt/vesktop/vesktop" ] && [ ! -e "${staging_root}/usr/bin/vesktop" ] && ln -sf /opt/vesktop/vesktop "${staging_root}/usr/bin/vesktop"
    fi

    # Universal Vulkan Layer Manifest Remapping for Slackware 64-bit & Multilib:
    for layer_dir in "${staging_root}/usr/share/vulkan/implicit_layer.d" \
                     "${staging_root}/usr/share/vulkan/explicit_layer.d" \
                     "${staging_root}/etc/vulkan/implicit_layer.d" \
                     "${staging_root}/etc/vulkan/explicit_layer.d"; do
        [ -d "${layer_dir}" ] || continue
        for jf in "${layer_dir}"/*.json; do
            [ -f "${jf}" ] || continue
            local bjf
            bjf=$(basename "${jf}")
            if [[ "${bjf}" == *"x86_64"* ]] || [[ "${bjf}" == *"64"* ]] || [ "${bjf}" = "MangoHud.json" ] || [ "${bjf}" = "MangoApp.json" ] || [ "${bjf}" = "obs_vkcapture.json" ]; then
                # 64-bit manifest: rewrite /usr/lib/ to /usr/lib64/
                sed -i 's|/usr/lib/mangohud/|/usr/lib64/mangohud/|g; s|/usr/lib/libMango|/usr/lib64/libMango|g; s|/usr/lib/libmango|/usr/lib64/libmango|g; s|/usr/lib/libobs|/usr/lib64/libobs|g; s|/usr/lib/libVkLayer|/usr/lib64/libVkLayer|g' "${jf}"
            elif [[ "${bjf}" == *"x86"* ]] || [[ "${bjf}" == *"i686"* ]] || [[ "${bjf}" == *"32"* ]] || [[ "${bjf}" == *"lib32"* ]]; then
                # 32-bit manifest: rewrite /usr/lib32/ to /usr/lib/
                sed -i 's|/usr/lib32/|/usr/lib/|g' "${jf}"
            fi
        done
        # Ensure standard non-suffixed symlinks exist (e.g. MangoHud.json -> MangoHud.x86_64.json)
        if [ -f "${layer_dir}/MangoHud.x86_64.json" ] && [ ! -e "${layer_dir}/MangoHud.json" ]; then
            ln -sf MangoHud.x86_64.json "${layer_dir}/MangoHud.json"
        fi
        if [ -f "${layer_dir}/MangoApp.x86_64.json" ] && [ ! -e "${layer_dir}/MangoApp.json" ]; then
            ln -sf MangoApp.x86_64.json "${layer_dir}/MangoApp.json"
        fi
        if [ -f "${layer_dir}/obs_vkcapture_x86_64.json" ] && [ ! -e "${layer_dir}/obs_vkcapture.json" ]; then
            ln -sf obs_vkcapture_x86_64.json "${layer_dir}/obs_vkcapture.json"
        fi
        if [ -f "${layer_dir}/obs_vkcapture_64.json" ] && [ ! -e "${layer_dir}/obs_vkcapture.json" ]; then
            ln -sf obs_vkcapture_64.json "${layer_dir}/obs_vkcapture.json"
        fi
    done

    # Service & Special Integrations:
    if [ "${pkg_id}" = "mangohud" ]; then
        # Fix /usr/bin/mangohud launcher script paths
        if [ -f "${staging_root}/usr/bin/mangohud" ]; then
            sed -i 's|/usr/lib/mangohud/|/usr/lib64/mangohud/|g; s|/usr/lib32/mangohud/|/usr/lib/mangohud/|g; s|/usr/lib32/|/usr/lib/|g' "${staging_root}/usr/bin/mangohud"
            chmod 755 "${staging_root}/usr/bin/mangohud"
        fi

        # Create library symlinks for compatibility in /usr/lib64 and /usr/lib
        if [ -d "${staging_root}/usr/lib64/mangohud" ]; then
            for so in "${staging_root}/usr/lib64/mangohud"/*.so*; do
                [ -f "${so}" ] || continue
                local soname
                soname=$(basename "${so}")
                [ -e "${staging_root}/usr/lib64/${soname}" ] || ln -sf "mangohud/${soname}" "${staging_root}/usr/lib64/${soname}"
            done
        fi
        if [ -d "${staging_root}/usr/lib/mangohud" ]; then
            for so in "${staging_root}/usr/lib/mangohud"/*.so*; do
                [ -f "${so}" ] || continue
                local soname
                soname=$(basename "${so}")
                [ -e "${staging_root}/usr/lib/${soname}" ] || ln -sf "mangohud/${soname}" "${staging_root}/usr/lib/${soname}"
            done
        fi

        # Default configuration template
        mkdir -p "${staging_root}/usr/share/mangohud"
        if [ -f "${staging_root}/usr/share/doc/mangohud/MangoHud.conf.example" ]; then
            cp -a "${staging_root}/usr/share/doc/mangohud/MangoHud.conf.example" "${staging_root}/usr/share/mangohud/MangoHud.conf" 2>/dev/null || true
        fi
    fi

    if [ "${pkg_id}" = "goverlay" ]; then
        # If /usr/lib64/goverlay or /usr/lib/goverlay is an ELF binary, move it to /usr/bin/goverlay
        if [ -f "${staging_root}/usr/lib64/goverlay" ]; then
            if is_elf_binary "${staging_root}/usr/lib64/goverlay"; then
                mv -f "${staging_root}/usr/lib64/goverlay" "${staging_root}/usr/bin/goverlay"
            else
                rm -f "${staging_root}/usr/lib64/goverlay"
            fi
        fi
        if [ -f "${staging_root}/usr/lib/goverlay" ]; then
            if is_elf_binary "${staging_root}/usr/lib/goverlay"; then
                mv -f "${staging_root}/usr/lib/goverlay" "${staging_root}/usr/bin/goverlay"
            else
                rm -f "${staging_root}/usr/lib/goverlay"
            fi
        fi

        # If /usr/lib64/pascube or /usr/lib/pascube is an ELF binary, move it to /usr/bin/pascube
        if [ -f "${staging_root}/usr/lib64/pascube" ]; then
            if is_elf_binary "${staging_root}/usr/lib64/pascube"; then
                mv -f "${staging_root}/usr/lib64/pascube" "${staging_root}/usr/bin/pascube"
            else
                rm -f "${staging_root}/usr/lib64/pascube"
            fi
        fi
        if [ -f "${staging_root}/usr/lib/pascube" ]; then
            if is_elf_binary "${staging_root}/usr/lib/pascube"; then
                mv -f "${staging_root}/usr/lib/pascube" "${staging_root}/usr/bin/pascube"
            else
                rm -f "${staging_root}/usr/lib/pascube"
            fi
        fi

        # Ensure binaries in /usr/bin are executable
        [ -f "${staging_root}/usr/bin/goverlay" ] && chmod 755 "${staging_root}/usr/bin/goverlay"
        [ -f "${staging_root}/usr/bin/pascube" ] && chmod 755 "${staging_root}/usr/bin/pascube"

        # Create compatibility symlinks in /usr/lib64 and /usr/lib pointing to /usr/bin binaries
        mkdir -p "${staging_root}/usr/lib64" "${staging_root}/usr/lib"
        rm -rf "${staging_root}/usr/lib64/goverlay" "${staging_root}/usr/lib/goverlay" 2>/dev/null || true
        rm -rf "${staging_root}/usr/lib64/pascube" "${staging_root}/usr/lib/pascube" 2>/dev/null || true

        if [ -f "${staging_root}/usr/bin/goverlay" ]; then
            ln -sf /usr/bin/goverlay "${staging_root}/usr/lib64/goverlay"
            ln -sf /usr/bin/goverlay "${staging_root}/usr/lib/goverlay"
        fi
        if [ -f "${staging_root}/usr/bin/pascube" ]; then
            ln -sf /usr/bin/pascube "${staging_root}/usr/lib64/pascube"
            ln -sf /usr/bin/pascube "${staging_root}/usr/lib/pascube"
        fi
    fi

    if [[ "${pkg_id}" =~ ^obs- ]] && [ "${pkg_id}" != "obs-studio" ]; then
        # Bridge plugin and plugin data into isolated OBS Studio bundle in /opt/obs-studio
        mkdir -p "${staging_root}/opt/obs-studio/lib/obs-plugins" \
                 "${staging_root}/opt/obs-studio/share/obs/obs-plugins"
        for sopath in "${staging_root}"/usr/lib64/obs-plugins/*.so "${staging_root}"/usr/lib/obs-plugins/*.so; do
            [ -f "${sopath}" ] || continue
            local soname
            soname=$(basename "${sopath}")
            ln -sf "/usr/lib64/obs-plugins/${soname}" "${staging_root}/opt/obs-studio/lib/obs-plugins/${soname}"
        done
        for datapath in "${staging_root}"/usr/share/obs/obs-plugins/*; do
            [ -d "${datapath}" ] || continue
            local dataname
            dataname=$(basename "${datapath}")
            ln -sf "/usr/share/obs/obs-plugins/${dataname}" "${staging_root}/opt/obs-studio/share/obs/obs-plugins/${dataname}"
        done

        if [ "${pkg_id}" = "obs-vkcapture" ]; then
            # Multilib 32-bit Vulkan layer manifest for 32-bit games
            local vklayer_dir="${staging_root}/usr/share/vulkan/implicit_layer.d"
            if [ -f "${staging_root}/usr/lib/libVkLayer_obs_vkcapture.so" ] && [ ! -f "${vklayer_dir}/obs_vkcapture_32.json" ]; then
                mkdir -p "${vklayer_dir}"
                cat << 'VK32_EOF' > "${vklayer_dir}/obs_vkcapture_32.json"
{
    "file_format_version": "1.1.2",
    "layer": {
        "name": "VK_LAYER_OBS_vkcapture_32",
        "type": "GLOBAL",
        "library_path": "/usr/lib/libVkLayer_obs_vkcapture.so",
        "api_version": "1.4.350",
        "implementation_version": "1",
        "description": "OBS Linux game capture (32-bit multilib)",
        "functions": {
            "vkNegotiateLoaderLayerInterfaceVersion": "OBS_Negotiate"
        },
        "enable_environment": {
            "OBS_VKCAPTURE": "1"
        },
        "disable_environment": {
            "DISABLE_OBS_VKCAPTURE": "1"
        }
    }
}
VK32_EOF
            fi
        fi
    fi

    if [ "${pkg_id}" = "zenpower3" ]; then
        mkdir -p "${staging_root}/etc/modprobe.d" "${staging_root}/etc/modules-load.d"
        cat << 'ZEN_EOF' > "${staging_root}/etc/modprobe.d/zenpower.conf"
# Generated by slacky-update Underpants Gnomes
# Blacklist default k10temp to allow zenpower full access to Zen SVI2 telemetry
blacklist k10temp
ZEN_EOF
        echo "zenpower" > "${staging_root}/etc/modules-load.d/zenpower.conf"
    fi

    if [ "${pkg_id}" = "v4l2loopback" ]; then
        mkdir -p "${staging_root}/etc/modprobe.d" "${staging_root}/etc/modules-load.d"
        cat << 'V4L2_EOF' > "${staging_root}/etc/modprobe.d/v4l2loopback.conf"
# Generated by slacky-update Underpants Gnomes
options v4l2loopback devices=1 video_nr=10 card_label="OBS Virtual Camera" exclusive_caps=1
V4L2_EOF
        echo "v4l2loopback" > "${staging_root}/etc/modules-load.d/v4l2loopback.conf"
    fi

    if [ "${pkg_id}" = "darktable" ]; then
        # Darktable binary RUNPATH points to $ORIGIN/../lib/darktable
        # Ensure /usr/lib/darktable symlinks to /usr/lib64/darktable on Slackware 64-bit
        mkdir -p "${staging_root}/usr/lib" "${staging_root}/usr/lib64/darktable" "${staging_root}/etc/ld.so.conf.d"
        rm -rf "${staging_root}/usr/lib/darktable" 2>/dev/null || true
        ln -sf /usr/lib64/darktable "${staging_root}/usr/lib/darktable"
        echo "/usr/lib64/darktable" > "${staging_root}/etc/ld.so.conf.d/darktable.conf"

        # Lua 5.4 binary compatibility symlinks on Slackware
        if [ -f "/usr/lib64/liblua.so.5.4" ] || [ -f "${staging_root}/usr/lib64/liblua.so.5.4" ]; then
            [ ! -e "${staging_root}/usr/lib64/liblua5.4.so.5.4" ] && ln -sf liblua.so.5.4 "${staging_root}/usr/lib64/liblua5.4.so.5.4"
            [ ! -e "${staging_root}/usr/lib64/liblua5.4.so" ] && ln -sf liblua.so.5.4 "${staging_root}/usr/lib64/liblua5.4.so"
        fi
    fi

    if [ "${pkg_id}" = "inkscape" ]; then
        # Inkscape internal library RUNPATH points to $ORIGIN/../lib/inkscape
        # Ensure /usr/lib/inkscape symlinks to /usr/lib64/inkscape on Slackware 64-bit
        mkdir -p "${staging_root}/usr/lib" "${staging_root}/usr/lib64/inkscape" "${staging_root}/etc/ld.so.conf.d"
        rm -rf "${staging_root}/usr/lib/inkscape" 2>/dev/null || true
        ln -sf /usr/lib64/inkscape "${staging_root}/usr/lib/inkscape"
        echo "/usr/lib64/inkscape" > "${staging_root}/etc/ld.so.conf.d/inkscape.conf"
    fi

    if [ "${pkg_id}" = "lact" ]; then
        mkdir -p "${staging_root}/etc/rc.d"
        cat << 'LACT_RC_EOF' > "${staging_root}/etc/rc.d/rc.lact"
#!/bin/sh
#
# /etc/rc.d/rc.lact - LACT daemon service script for Slackware
#

PIDFILE="/run/lactd.pid"
SOCKFILE="/run/lactd.sock"
BIN="/usr/bin/lact"

lact_start() {
  if [ -x "$BIN" ]; then
    echo "Starting LACT daemon: $BIN daemon"
    rm -f "$SOCKFILE" "$PIDFILE"
    $BIN daemon > /var/log/lactd.log 2>&1 &
    echo $! > "$PIDFILE"
  fi
}

lact_stop() {
  echo "Stopping LACT daemon..."
  if [ -f "$PIDFILE" ]; then
    kill -TERM $(cat "$PIDFILE") 2>/dev/null
    rm -f "$PIDFILE"
  else
    pkill -TERM -f "$BIN daemon" 2>/dev/null
  fi
  rm -f "$SOCKFILE"
}

lact_restart() {
  lact_stop
  sleep 1
  lact_start
}

lact_status() {
  if pgrep -f "$BIN daemon" > /dev/null 2>&1; then
    echo "LACT daemon is running."
    $BIN cli profile get 2>/dev/null || true
  else
    echo "LACT daemon is NOT running."
  fi
}

case "$1" in
  'start')
    lact_start
    ;;
  'stop')
    lact_stop
    ;;
  'restart')
    lact_restart
    ;;
  'status')
    lact_status
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status}"
    exit 1
    ;;
esac
LACT_RC_EOF
        chmod 755 "${staging_root}/etc/rc.d/rc.lact"
    fi

    if [ "${pkg_id}" = "ananicy" ]; then
        mkdir -p "${staging_root}/etc/rc.d"
        cat << 'ANANICY_RC_EOF' > "${staging_root}/etc/rc.d/rc.ananicy-cpp"
#!/bin/sh
#
# /etc/rc.d/rc.ananicy-cpp - Ananicy C++ auto-nice daemon for Slackware
#

PIDFILE="/run/ananicy-cpp.pid"
BIN="/usr/bin/ananicy-cpp"

ananicy_start() {
  if [ -x "$BIN" ]; then
    echo "Starting Ananicy C++ daemon: $BIN start --manual-scanning"
    if ! pgrep -x ananicy-cpp > /dev/null 2>&1; then
      $BIN --force-remove-semaphore 2>/dev/null || true
      rm -f "$PIDFILE" /var/run/ananicy-cpp.pid /dev/shm/sem.*ananicy* /dev/shm/*ananicy* 2>/dev/null || true
    fi
    if [ -d /sys/kernel/tracing ] && ! mountpoint -q /sys/kernel/tracing 2>/dev/null; then
      mount -t tracefs nodev /sys/kernel/tracing 2>/dev/null || true
    fi
    $BIN start --manual-scanning > /var/log/ananicy-cpp.log 2>&1 &
  fi
}

ananicy_stop() {
  echo "Stopping Ananicy C++ daemon..."
  pkill -TERM -x ananicy-cpp 2>/dev/null || true
  sleep 0.5
  pkill -KILL -x ananicy-cpp 2>/dev/null || true
  $BIN --force-remove-semaphore 2>/dev/null || true
  rm -f "$PIDFILE" /var/run/ananicy-cpp.pid /dev/shm/sem.*ananicy* /dev/shm/*ananicy* 2>/dev/null || true
}

ananicy_restart() {
  ananicy_stop
  sleep 1
  ananicy_start
}

ananicy_status() {
  if pgrep -x ananicy-cpp > /dev/null 2>&1 || pgrep -f "$BIN" > /dev/null 2>&1; then
    echo "Ananicy C++ daemon is running."
  else
    echo "Ananicy C++ daemon is NOT running."
  fi
}

case "$1" in
  'start')
    ananicy_start
    ;;
  'stop')
    ananicy_stop
    ;;
  'restart')
    ananicy_restart
    ;;
  'status')
    ananicy_status
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status}"
    exit 1
    ;;
esac
ANANICY_RC_EOF
        chmod 755 "${staging_root}/etc/rc.d/rc.ananicy-cpp"
    fi

    if [ "${pkg_id}" = "scx" ]; then
        mkdir -p "${staging_root}/etc/rc.d" "${staging_root}/etc/dbus-1/system.d"
        if [ -f "${staging_root}/usr/share/dbus-1/system.d/org.scx.Loader.conf" ]; then
            cp -a "${staging_root}/usr/share/dbus-1/system.d/org.scx.Loader.conf" "${staging_root}/etc/dbus-1/system.d/" 2>/dev/null || true
        fi
        cat << 'SCX_RC_EOF' > "${staging_root}/etc/rc.d/rc.scx"
#!/bin/sh
# /etc/rc.d/rc.scx - Sched-EXT Gaming Scheduler & Loader Daemon for Slackware

DEFAULT_SCHED="${SCX_SCHED:-scx_lavd}"

scx_start() {
    if command -v scx_loader >/dev/null 2>&1; then
        echo "Starting Sched-EXT loader daemon (scx_loader)..."
        nohup scx_loader >/var/log/scx_loader.log 2>&1 &
    elif command -v "${DEFAULT_SCHED}" >/dev/null 2>&1; then
        echo "Starting Sched-EXT gaming scheduler: ${DEFAULT_SCHED}"
        nohup "${DEFAULT_SCHED}" >/var/log/scx.log 2>&1 &
    else
        echo "Sched-EXT scheduler or scx_loader not found."
    fi
}

scx_stop() {
    echo "Stopping Sched-EXT schedulers..."
    pkill -x scx_loader 2>/dev/null || true
    pkill -f "scx_" 2>/dev/null || true
}

scx_status() {
    if pgrep -x scx_loader >/dev/null 2>&1; then
        echo "Sched-EXT loader daemon is active (PID: $(pgrep -x scx_loader))"
    fi
    if pgrep -f "scx_" | grep -v "$(pgrep -x scx_loader 2>/dev/null)" >/dev/null 2>&1; then
        echo "Sched-EXT scheduler is active: $(pgrep -a -f "scx_" | grep -v "scx_loader" | head -n1)"
    elif ! pgrep -x scx_loader >/dev/null 2>&1; then
        echo "No Sched-EXT scheduler or loader running."
    fi
}

case "$1" in
    start) scx_start ;;
    stop) scx_stop ;;
    restart) scx_stop; sleep 1; scx_start ;;
    status) scx_status ;;
    *) echo "Usage: $0 {start|stop|restart|status}" ;;
esac
SCX_RC_EOF
        chmod 755 "${staging_root}/etc/rc.d/rc.scx"
    fi

    if [ "${pkg_id}" = "easyeffects" ]; then
        log_info "Fetching JackHack96 EasyEffects studio presets & impulse responses..."
        mkdir -p "${staging_root}/etc/easyeffects/output" \
                 "${staging_root}/etc/easyeffects/irs" \
                 "${staging_root}/etc/skel/.config/easyeffects/output" \
                 "${staging_root}/etc/skel/.config/easyeffects/irs"
        
        local presets_tar="${staging_base}/easyeffects-presets.tar.gz"
        curl -fsSL "https://github.com/JackHack96/EasyEffects-Presets/archive/refs/heads/master.tar.gz" -o "${presets_tar}" 2>/dev/null || true
        if [ -f "${presets_tar}" ]; then
            local extract_tmp="${staging_base}/presets_tmp"
            mkdir -p "${extract_tmp}"
            tar -xzf "${presets_tar}" -C "${extract_tmp}" 2>/dev/null || true
            local p_root
            p_root=$(find "${extract_tmp}" -maxdepth 1 -type d -name "EasyEffects-Presets*" | head -n1)
            if [ -n "${p_root}" ] && [ -d "${p_root}" ]; then
                cp -a "${p_root}"/*.json "${staging_root}/etc/easyeffects/output/" 2>/dev/null || true
                cp -a "${p_root}"/*.json "${staging_root}/etc/skel/.config/easyeffects/output/" 2>/dev/null || true
                if [ -d "${p_root}/irs" ]; then
                    cp -a "${p_root}/irs"/* "${staging_root}/etc/easyeffects/irs/" 2>/dev/null || true
                    cp -a "${p_root}/irs"/* "${staging_root}/etc/skel/.config/easyeffects/irs/" 2>/dev/null || true
                fi
            fi
            rm -rf "${extract_tmp}" "${presets_tar}" 2>/dev/null || true
        fi
    fi

    if [ "${pkg_id}" = "openrgb" ]; then
        mkdir -p "${staging_root}/lib/udev/rules.d"
        cat << 'OPENRGB_UDEV_EOF' > "${staging_root}/lib/udev/rules.d/60-openrgb.rules"
# OpenRGB Udev rules for Slackware
SUBSYSTEM=="usb", ATTR{idVendor}=="*", MODE="0666", TAG+="uaccess"
SUBSYSTEM=="hidraw", MODE="0666", TAG+="uaccess"
KERNEL=="i2c-[0-9]*", GROUP="users", MODE="0666"
OPENRGB_UDEV_EOF

        # Ensure cross-desktop icon compatibility (KDE Plasma, XFCE, GNOME)
        if [ -d "${staging_root}/usr/share/icons" ]; then
            find "${staging_root}/usr/share/icons" -type f -name "org.openrgb.OpenRGB.png" | while read -r icon_file; do
                icon_dir="$(dirname "${icon_file}")"
                ln -sf "org.openrgb.OpenRGB.png" "${icon_dir}/openrgb.png" 2>/dev/null || true
            done
            find "${staging_root}/usr/share/icons" -type f -name "org.openrgb.OpenRGB.svg" | while read -r icon_file; do
                icon_dir="$(dirname "${icon_file}")"
                ln -sf "org.openrgb.OpenRGB.svg" "${icon_dir}/openrgb.svg" 2>/dev/null || true
            done
        fi
        mkdir -p "${staging_root}/usr/share/pixmaps"
        if [ -f "${staging_root}/usr/share/icons/hicolor/128x128/apps/org.openrgb.OpenRGB.png" ]; then
            cp -a "${staging_root}/usr/share/icons/hicolor/128x128/apps/org.openrgb.OpenRGB.png" "${staging_root}/usr/share/pixmaps/openrgb.png" 2>/dev/null || true
            cp -a "${staging_root}/usr/share/icons/hicolor/128x128/apps/org.openrgb.OpenRGB.png" "${staging_root}/usr/share/pixmaps/org.openrgb.OpenRGB.png" 2>/dev/null || true
        elif [ -f "${staging_root}/usr/share/icons/hicolor/scalable/apps/org.openrgb.OpenRGB.svg" ]; then
            cp -a "${staging_root}/usr/share/icons/hicolor/scalable/apps/org.openrgb.OpenRGB.svg" "${staging_root}/usr/share/pixmaps/openrgb.svg" 2>/dev/null || true
            cp -a "${staging_root}/usr/share/icons/hicolor/scalable/apps/org.openrgb.OpenRGB.svg" "${staging_root}/usr/share/pixmaps/org.openrgb.OpenRGB.svg" 2>/dev/null || true
        fi
    fi

    if [ "${pkg_id}" = "gamemode" ]; then
        mkdir -p "${staging_root}/usr/lib64" "${staging_root}/usr/lib" "${staging_root}/etc/rc.d"
        if [ -f "${staging_root}/usr/lib64/libgamemode.so.0" ] && [ ! -e "${staging_root}/usr/lib64/libgamemode.so" ]; then
            ln -sf libgamemode.so.0 "${staging_root}/usr/lib64/libgamemode.so"
        fi
        if [ -f "${staging_root}/usr/lib/libgamemode.so.0" ] && [ ! -e "${staging_root}/usr/lib/libgamemode.so" ]; then
            ln -sf libgamemode.so.0 "${staging_root}/usr/lib/libgamemode.so"
        fi
        cat << 'GAMEMODE_RC_EOF' > "${staging_root}/etc/rc.d/rc.gamemode"
#!/bin/sh
# /etc/rc.d/rc.gamemode - Feral GameMode daemon service for Slackware
BIN="/usr/bin/gamemoded"

gamemode_start() {
  if [ -x "$BIN" ]; then
    echo "Starting GameMode daemon: $BIN -d"
    $BIN -d >/var/log/gamemoded.log 2>&1 &
  fi
}
gamemode_stop() {
  echo "Stopping GameMode daemon..."
  pkill -x gamemoded 2>/dev/null || true
}
gamemode_status() {
  if pgrep -x gamemoded >/dev/null 2>&1; then
    echo "GameMode daemon is running (PID: $(pgrep -x gamemoded))."
  else
    echo "GameMode daemon is NOT running."
  fi
}
case "$1" in
  start) gamemode_start ;;
  stop) gamemode_stop ;;
  restart) gamemode_stop; sleep 1; gamemode_start ;;
  status) gamemode_status ;;
  *) echo "Usage: $0 {start|stop|restart|status}" ;;
esac
GAMEMODE_RC_EOF
        chmod 755 "${staging_root}/etc/rc.d/rc.gamemode"
    fi

    if [ "${pkg_id}" = "coolercontrol" ]; then
        mkdir -p "${staging_root}/etc/rc.d" "${staging_root}/lib/udev/rules.d"
        cat << 'COOLER_RC_EOF' > "${staging_root}/etc/rc.d/rc.coolercontrol"
#!/bin/sh
# /etc/rc.d/rc.coolercontrol - CoolerControl daemon for Slackware
BIN="/usr/bin/coolercontrold"
PIDFILE="/run/coolercontrold.pid"

cooler_start() {
  if [ -x "$BIN" ]; then
    echo "Starting CoolerControl daemon: $BIN"
    $BIN >/var/log/coolercontrold.log 2>&1 &
    echo $! > "$PIDFILE"
  fi
}
cooler_stop() {
  echo "Stopping CoolerControl daemon..."
  if [ -f "$PIDFILE" ]; then
    kill -TERM $(cat "$PIDFILE") 2>/dev/null || true
    rm -f "$PIDFILE"
  else
    pkill -TERM -x coolercontrold 2>/dev/null || true
  fi
}
cooler_status() {
  if pgrep -x coolercontrold >/dev/null 2>&1; then
    echo "CoolerControl daemon is running (PID: $(pgrep -x coolercontrold))."
  else
    echo "CoolerControl daemon is NOT running."
  fi
}
case "$1" in
  start) cooler_start ;;
  stop) cooler_stop ;;
  restart) cooler_stop; sleep 1; cooler_start ;;
  status) cooler_status ;;
  *) echo "Usage: $0 {start|stop|restart|status}" ;;
esac
COOLER_RC_EOF
        chmod 755 "${staging_root}/etc/rc.d/rc.coolercontrol"
    fi

    if [ "${pkg_id}" = "solaar" ]; then
        mkdir -p "${staging_root}/lib/udev/rules.d"
        cat << 'SOLAAR_UDEV_EOF' > "${staging_root}/lib/udev/rules.d/42-logitech-unify-permissions.rules"
# Solaar Logitech Unifying and Lightspeed receiver udev rules for Slackware
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="046d", MODE="0666", TAG+="uaccess"
SUBSYSTEM=="usb", ATTRS{idVendor}=="046d", MODE="0666", TAG+="uaccess"
SOLAAR_UDEV_EOF

        # Ensure Solaar gracefully handles missing/optional evdev module on Slackware
        for div_py in $(find "${staging_root}" -name "diversion.py" -type f 2>/dev/null); do
            python3 -c "
import sys
p = sys.argv[1]
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()
target = 'if platform.system() in (\"Darwin\", \"Windows\"):\n    evdev = None\nelse:\n    import evdev'
replacement = 'try:\n    import evdev\nexcept Exception:\n    evdev = None'
if target in c:
    c = c.replace(target, replacement)
    with open(p, 'w', encoding='utf-8') as f:
        f.write(c)
" "${div_py}" 2>/dev/null || true
        done
        # Clean out any partial/broken CPython 3.14 evdev module tree if present
        rm -rf "${staging_root}/usr/lib64/python"*/site-packages/evdev 2>/dev/null || true
    fi

    if [ "${pkg_id}" = "asusctl" ]; then
        mkdir -p "${staging_root}/etc/rc.d"
        cat << 'ASUS_RC_EOF' > "${staging_root}/etc/rc.d/rc.asusd"
#!/bin/sh
# /etc/rc.d/rc.asusd - ASUS ROG/TUF Control Daemon for Slackware
BIN="/usr/bin/asusd"
PIDFILE="/run/asusd.pid"

asus_start() {
  if [ -x "$BIN" ]; then
    echo "Starting ASUS control daemon: $BIN"
    $BIN >/var/log/asusd.log 2>&1 &
    echo $! > "$PIDFILE"
  fi
}
asus_stop() {
  echo "Stopping ASUS control daemon..."
  if [ -f "$PIDFILE" ]; then
    kill -TERM $(cat "$PIDFILE") 2>/dev/null || true
    rm -f "$PIDFILE"
  else
    pkill -TERM -x asusd 2>/dev/null || true
  fi
}
asus_status() {
  if pgrep -x asusd >/dev/null 2>&1; then
    echo "ASUS control daemon is running (PID: $(pgrep -x asusd))."
  else
    echo "ASUS control daemon is NOT running."
  fi
}
case "$1" in
  start) asus_start ;;
  stop) asus_stop ;;
  restart) asus_stop; sleep 1; asus_start ;;
  status) asus_status ;;
  *) echo "Usage: $0 {start|stop|restart|status}" ;;
esac
ASUS_RC_EOF
        chmod 755 "${staging_root}/etc/rc.d/rc.asusd"
    fi

    if [ "${pkg_id}" = "syncthing" ]; then
        mkdir -p "${staging_root}/etc/rc.d"
        cat << 'SYNCTHING_RC_EOF' > "${staging_root}/etc/rc.d/rc.syncthing"
#!/bin/sh
# /etc/rc.d/rc.syncthing - Syncthing P2P daemon service for Slackware
BIN="/usr/bin/syncthing"

syncthing_start() {
  if [ -x "$BIN" ]; then
    echo "Starting Syncthing service..."
    su - nobody -s /bin/sh -c "$BIN serve --no-browser --home=/var/lib/syncthing >/var/log/syncthing.log 2>&1 &" 2>/dev/null || true
  fi
}
syncthing_stop() {
  echo "Stopping Syncthing service..."
  pkill -TERM -x syncthing 2>/dev/null || true
}
syncthing_status() {
  if pgrep -x syncthing >/dev/null 2>&1; then
    echo "Syncthing is running (PID: $(pgrep -x syncthing))."
  else
    echo "Syncthing is NOT running."
  fi
}
case "$1" in
  start) syncthing_start ;;
  stop) syncthing_stop ;;
  restart) syncthing_stop; sleep 1; syncthing_start ;;
  status) syncthing_status ;;
  *) echo "Usage: $0 {start|stop|restart|status}" ;;
esac
SYNCTHING_RC_EOF
        chmod 755 "${staging_root}/etc/rc.d/rc.syncthing"
    fi

    if [ "${pkg_id}" = "yabridge" ]; then
        mkdir -p "${staging_root}/usr/bin" "${staging_root}/usr/lib64" "${staging_root}/usr/lib"
        [ -f "${staging_root}/usr/bin/yabridgectl" ] && chmod 755 "${staging_root}/usr/bin/yabridgectl"
        # Mirror libraries to /usr/lib so yabridgectl and DAWs auto-discover yabridge on Slackware 64-bit
        for yso in "${staging_root}/usr/lib64"/libyabridge*.so; do
            if [ -f "${yso}" ]; then
                local ysoname
                ysoname=$(basename "${yso}")
                [ -e "${staging_root}/usr/lib/${ysoname}" ] || ln -sf "../lib64/${ysoname}" "${staging_root}/usr/lib/${ysoname}"
            fi
        done
    fi

    if [ "${pkg_id}" = "spotify" ]; then
        [ -f "${staging_root}/usr/bin/spotify-launcher" ] && [ ! -e "${staging_root}/usr/bin/spotify" ] && ln -sf spotify-launcher "${staging_root}/usr/bin/spotify"
        mkdir -p "${staging_root}/usr/lib64"
        if [ ! -e "${staging_root}/usr/lib64/libayatana-appindicator3.so.1" ]; then
            ln -sf libappindicator3.so.1 "${staging_root}/usr/lib64/libayatana-appindicator3.so.1"
            ln -sf libappindicator3.so.1 "${staging_root}/usr/lib64/libayatana-appindicator3.so"
            ln -sf libappindicator.so.1 "${staging_root}/usr/lib64/libayatana-appindicator.so.1"
            ln -sf libappindicator.so.1 "${staging_root}/usr/lib64/libayatana-appindicator.so"
        fi
        if [ ! -e "${staging_root}/usr/lib64/libayatana-indicator3.so.7" ]; then
            ln -sf libindicator3.so.7 "${staging_root}/usr/lib64/libayatana-indicator3.so.7"
            ln -sf libindicator3.so.7 "${staging_root}/usr/lib64/libayatana-indicator3.so"
            ln -sf libindicator.so.7 "${staging_root}/usr/lib64/libayatana-indicator.so.7"
            ln -sf libindicator.so.7 "${staging_root}/usr/lib64/libayatana-indicator.so"
        fi
        if [ ! -e "${staging_root}/usr/lib64/libcurl-gnutls.so.4" ]; then
            ln -sf libcurl.so.4 "${staging_root}/usr/lib64/libcurl-gnutls.so.4"
            ln -sf libcurl.so.4 "${staging_root}/usr/lib64/libcurl-gnutls.so"
        fi
    fi

    if [ "${pkg_id}" = "audacity" ]; then
        # Audacity installs internal private libraries to /usr/lib/audacity or /usr/lib64/audacity.
        # Ensure symmetric directories and symlinks for both /usr/lib64 and /usr/lib
        mkdir -p "${staging_root}/usr/lib64" "${staging_root}/usr/lib" "${staging_root}/etc/ld.so.conf.d"
        for subdir in audacity suil-0 wx; do
            if [ -d "${staging_root}/usr/lib64/${subdir}" ] && [ ! -d "${staging_root}/usr/lib/${subdir}" ]; then
                ln -sf "../lib64/${subdir}" "${staging_root}/usr/lib/${subdir}"
            elif [ -d "${staging_root}/usr/lib/${subdir}" ] && [ ! -d "${staging_root}/usr/lib64/${subdir}" ]; then
                cp -a "${staging_root}/usr/lib/${subdir}" "${staging_root}/usr/lib64/"
                rm -rf "${staging_root}/usr/lib/${subdir}"
                ln -sf "../lib64/${subdir}" "${staging_root}/usr/lib/${subdir}"
            fi
        done

        # Register library paths in dynamic linker config
        cat << 'AUDACITY_LD_EOF' > "${staging_root}/etc/ld.so.conf.d/audacity.conf"
/usr/lib64/audacity
/usr/lib/audacity
/usr/lib64
/usr/lib
AUDACITY_LD_EOF

        # Wrap /usr/bin/audacity to ensure LD_LIBRARY_PATH always finds private libraries
        if [ -f "${staging_root}/usr/bin/audacity" ]; then
            mv -f "${staging_root}/usr/bin/audacity" "${staging_root}/usr/lib64/audacity/audacity.bin" 2>/dev/null || true
            cat << 'AUDACITY_WRAPPER_EOF' > "${staging_root}/usr/bin/audacity"
#!/bin/sh
# Audacity wrapper for Slackware ensuring private shared libraries resolve
export LD_LIBRARY_PATH="/usr/lib64/audacity:/usr/lib/audacity:/usr/lib64:/usr/lib:${LD_LIBRARY_PATH:-}"
if [ -x /usr/lib64/audacity/audacity.bin ]; then
    exec /usr/lib64/audacity/audacity.bin "$@"
elif [ -x /usr/lib/audacity/audacity.bin ]; then
    exec /usr/lib/audacity/audacity.bin "$@"
elif [ -x /usr/lib64/audacity/audacity ]; then
    exec /usr/lib64/audacity/audacity "$@"
elif [ -x /usr/lib/audacity/audacity ]; then
    exec /usr/lib/audacity/audacity "$@"
else
    exec /usr/bin/audacity.bin "$@"
fi
AUDACITY_WRAPPER_EOF
            chmod 755 "${staging_root}/usr/bin/audacity"
        fi

        # Ensure cross-desktop icon compatibility (KDE Plasma Wayland, XFCE, GNOME)
        if [ -d "${staging_root}/usr/share/icons" ]; then
            for sz in 16x16 22x22 24x24 32x32 48x48 64x64 128x128 256x256 512x512; do
                if [ -f "${staging_root}/usr/share/icons/hicolor/${sz}/audacity.png" ]; then
                    mkdir -p "${staging_root}/usr/share/icons/hicolor/${sz}/apps"
                    mv -f "${staging_root}/usr/share/icons/hicolor/${sz}/audacity.png" "${staging_root}/usr/share/icons/hicolor/${sz}/apps/audacity.png"
                    ln -sf audacity.png "${staging_root}/usr/share/icons/hicolor/${sz}/apps/Audacity.png" 2>/dev/null || true
                elif [ -f "${staging_root}/usr/share/icons/hicolor/${sz}/apps/audacity.png" ]; then
                    ln -sf audacity.png "${staging_root}/usr/share/icons/hicolor/${sz}/apps/Audacity.png" 2>/dev/null || true
                fi
            done
            if [ -f "${staging_root}/usr/share/icons/hicolor/scalable/apps/audacity.svg" ]; then
                ln -sf audacity.svg "${staging_root}/usr/share/icons/hicolor/scalable/apps/Audacity.svg" 2>/dev/null || true
            fi
        fi
        mkdir -p "${staging_root}/usr/share/pixmaps"
        if [ -f "${staging_root}/usr/share/icons/hicolor/48x48/apps/audacity.png" ]; then
            cp -a "${staging_root}/usr/share/icons/hicolor/48x48/apps/audacity.png" "${staging_root}/usr/share/pixmaps/audacity.png" 2>/dev/null || true
            cp -a "${staging_root}/usr/share/icons/hicolor/48x48/apps/audacity.png" "${staging_root}/usr/share/pixmaps/Audacity.png" 2>/dev/null || true
        elif [ -f "${staging_root}/usr/share/icons/hicolor/32x32/apps/audacity.png" ]; then
            cp -a "${staging_root}/usr/share/icons/hicolor/32x32/apps/audacity.png" "${staging_root}/usr/share/pixmaps/audacity.png" 2>/dev/null || true
            cp -a "${staging_root}/usr/share/icons/hicolor/32x32/apps/audacity.png" "${staging_root}/usr/share/pixmaps/Audacity.png" 2>/dev/null || true
        fi
        if [ -f "${staging_root}/usr/share/icons/hicolor/scalable/apps/audacity.svg" ]; then
            cp -a "${staging_root}/usr/share/icons/hicolor/scalable/apps/audacity.svg" "${staging_root}/usr/share/pixmaps/audacity.svg" 2>/dev/null || true
        fi
    fi

    if [ "${pkg_id}" = "steam" ]; then
        # Ensure /usr/lib/steam and /usr/lib64/steam are fully populated and symlinks are relative
        if [ -d "${staging_root}/usr/lib64/steam" ] && [ ! -d "${staging_root}/usr/lib/steam" ]; then
            mkdir -p "${staging_root}/usr/lib"
            cp -a "${staging_root}/usr/lib64/steam" "${staging_root}/usr/lib/"
        elif [ -d "${staging_root}/usr/lib/steam" ] && [ ! -d "${staging_root}/usr/lib64/steam" ]; then
            mkdir -p "${staging_root}/usr/lib64"
            cp -a "${staging_root}/usr/lib/steam" "${staging_root}/usr/lib64/"
        fi

        # Fix relative symlinks inside both /usr/lib/steam and /usr/lib64/steam
        for sdir in "${staging_root}/usr/lib/steam" "${staging_root}/usr/lib64/steam"; do
            [ -d "${sdir}" ] || continue
            (
                cd "${sdir}"
                rm -f steam
                ln -sf bin_steam.sh steam
            )
        done

        # Ensure /usr/bin/steam is a robust wrapper that checks both /usr/lib64/steam and /usr/lib/steam
        cat << 'STEAM_BIN_EOF' > "${staging_root}/usr/bin/steam"
#!/bin/sh
# Steam launcher wrapper for Slackware Linux
if [ -x /usr/lib64/steam/steam ]; then
    exec /usr/lib64/steam/steam "$@"
elif [ -x /usr/lib/steam/steam ]; then
    exec /usr/lib/steam/steam "$@"
elif [ -x /usr/lib64/steam/bin_steam.sh ]; then
    exec /usr/lib64/steam/bin_steam.sh "$@"
elif [ -x /usr/lib/steam/bin_steam.sh ]; then
    exec /usr/lib/steam/bin_steam.sh "$@"
else
    echo "Error: Steam launcher binary not found in /usr/lib64/steam or /usr/lib/steam" >&2
    exit 1
fi
STEAM_BIN_EOF
        chmod 755 "${staging_root}/usr/bin/steam"
    fi

    if [ "${pkg_id}" = "steam-devices" ] || [ "${pkg_id}" = "steam" ]; then
        mkdir -p "${staging_root}/lib/udev/rules.d"
        cat << 'STEAM_UDEV_EOF' > "${staging_root}/lib/udev/rules.d/60-steam-input.rules"
# Steam Controller and Gamepad Udev rules for Slackware
# Valve USB & Wireless
SUBSYSTEM=="usb", ATTRS{idVendor}=="28de", MODE="0666", TAG+="uaccess"
KERNEL=="uinput", MODE="0660", GROUP="users", TAG+="uaccess"
# DualShock 4 & DualSense
KERNEL=="hidraw*", ATTRS{idVendor}=="054c", MODE="0666", TAG+="uaccess"
# Nintendo Switch Pro
KERNEL=="hidraw*", ATTRS{idVendor}=="057e", MODE="0666", TAG+="uaccess"
# Xbox Wireless
KERNEL=="hidraw*", ATTRS{idVendor}=="045e", MODE="0666", TAG+="uaccess"
STEAM_UDEV_EOF
    fi

    if [ "${pkg_id}" = "sunshine" ]; then
        mkdir -p "${staging_root}/lib/udev/rules.d"
        cat << 'SUNSHINE_UDEV_EOF' > "${staging_root}/lib/udev/rules.d/60-sunshine.rules"
# Sunshine Game Stream Host - virtual input and controller udev rules for Slackware
KERNEL=="uinput", SUBSYSTEM=="misc", OPTIONS+="static_node=uinput", TAG+="uaccess", MODE="0660", GROUP="input"
KERNEL=="uhid", GROUP="input", MODE="0660", TAG+="uaccess"
SUNSHINE_UDEV_EOF
    fi

    if [ "${pkg_id}" = "vram-booster" ]; then
        mkdir -p "${staging_root}/usr/bin" "${staging_root}/etc/rc.d"

        if [ -f "${staging_root}/usr/bin/dmemcg-booster" ]; then
            mv -f "${staging_root}/usr/bin/dmemcg-booster" "${staging_root}/usr/bin/dmemcg-booster-cachyos" 2>/dev/null || true
        fi

        cat << 'DMEMCG_BIN_EOF' > "${staging_root}/usr/bin/dmemcg-booster"
#!/usr/bin/env python3
"""
dmemcg-booster - Dynamic Device Memory Cgroups (dmemcg) & Resizable BAR VRAM Optimizer for Slackware Linux
Part of the Underpants Gnomes Gaming Suite (slacky-update)
"""
import sys, os, re, time, subprocess, signal

CGROUP_ROOT = "/sys/fs/cgroup"
GAMING_SLICE = "/sys/fs/cgroup/dmemcg-gaming"
PIDFILE = "/run/dmemcg-booster.pid"
LOGFILE = "/var/log/dmemcg-booster.log"

GAME_PROCESS_NAMES = {
    "steam", "steamwebhelper", "wine-preloader", "wine64-preloader",
    "wineserver", "proton", "gamescope", "faugus-launcher", "heroic",
    "lutris", "retroarch", "vkcube", "yabridge-host", "yabridgectl",
    "mangohud", "gamemoded", "goverlay", "obs", "obs64"
}

def log(msg):
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] [dmemcg-booster] {msg}"
    print(line)
    try:
        with open(LOGFILE, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass

def init_cgroups():
    if not os.path.exists(CGROUP_ROOT):
        try:
            os.makedirs(CGROUP_ROOT, exist_ok=True)
            subprocess.run(["mount", "-t", "cgroup2", "none", CGROUP_ROOT], check=False)
        except Exception as e:
            log(f"Warning mounting cgroup2: {e}")

    subtree = os.path.join(CGROUP_ROOT, "cgroup.subtree_control")
    if os.path.exists(subtree):
        try:
            with open(subtree, "w") as f:
                f.write("+memory +io\n")
        except Exception:
            try:
                with open(subtree, "w") as f:
                    f.write("+memory\n")
            except Exception as e:
                log(f"Subtree controller setup note: {e}")

    os.makedirs(GAMING_SLICE, exist_ok=True)

    # Configure high priority memory & I/O for gaming slice
    for conf, val in [("memory.high", "max"), ("memory.low", "2G"), ("memory.min", "1G"), ("io.weight", "1000")]:
        p = os.path.join(GAMING_SLICE, conf)
        if os.path.exists(p):
            try:
                with open(p, "w") as f:
                    f.write(f"{val}\n")
            except Exception:
                pass

def get_nvidia_info():
    info = {"detected": False, "driver": "Unknown", "rebar": "Unknown", "vram_total": "Unknown", "vram_free": "Unknown"}
    try:
        res = subprocess.run(["nvidia-smi", "-q", "-d", "MEMORY"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=3)
        if res.returncode == 0 and res.stdout.strip():
            out = res.stdout
            info["detected"] = True
            m_kmd = re.search(r"KMD Version\s*:\s*([0-9\.]+)", out) or re.search(r"Driver Version\s*:\s*([0-9\.]+)", out)
            if m_kmd:
                info["driver"] = m_kmd.group(1)

            m_tot = re.search(r"FB Memory Usage.*?\n\s*Total\s*:\s*([0-9]+\s*MiB)", out, re.DOTALL)
            if m_tot:
                info["vram_total"] = m_tot.group(1)

            m_free = re.search(r"FB Memory Usage.*?\n\s*Free\s*:\s*([0-9]+\s*MiB)", out, re.DOTALL)
            if m_free:
                info["vram_free"] = m_free.group(1)

            m_bar1 = re.search(r"BAR1 Memory Usage.*?\n\s*Total\s*:\s*([0-9]+)\s*MiB", out, re.DOTALL)
            if m_bar1:
                bar1_val = int(m_bar1.group(1))
                if bar1_val >= 1024:
                    info["rebar"] = f"Active ({bar1_val} MiB / {round(bar1_val/1024, 1)} GiB Full BAR)"
                elif bar1_val > 256:
                    info["rebar"] = f"Partial ({bar1_val} MiB)"
                else:
                    info["rebar"] = f"Disabled ({bar1_val} MiB)"
            return info
    except Exception:
        pass

    if os.path.exists("/proc/driver/nvidia/version"):
        info["detected"] = True
        try:
            with open("/proc/driver/nvidia/version", "r") as f:
                content = f.read()
                m = re.search(r'NVRM version:\s+([0-9\.]+)', content)
                if m:
                    info["driver"] = m.group(1)
        except Exception:
            pass

    return info

def optimize_gpu_hardware():
    # NVIDIA persistence mode & auto-boost
    if os.path.exists("/usr/bin/nvidia-smi"):
        try:
            subprocess.run(["nvidia-smi", "-pm", "1"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            subprocess.run(["nvidia-smi", "--auto-boost-permission=0"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        except Exception:
            pass

    # AMD GPU performance level
    if os.path.exists("/sys/class/drm"):
        for card in os.listdir("/sys/class/drm"):
            dpm = f"/sys/class/drm/{card}/device/power_dpm_force_performance_level"
            if os.path.exists(dpm):
                try:
                    with open(dpm, "w") as f:
                        f.write("auto\n")
                except Exception:
                    pass

def get_boosted_pids():
    procs_file = os.path.join(GAMING_SLICE, "cgroup.procs")
    if os.path.exists(procs_file):
        try:
            with open(procs_file, "r") as f:
                return set(line.strip() for line in f if line.strip())
        except Exception:
            pass
    return set()

def boost_pid(pid):
    procs_file = os.path.join(GAMING_SLICE, "cgroup.procs")
    try:
        with open(procs_file, "a") as f:
            f.write(f"{pid}\n")
        subprocess.run(["renice", "-n", "-5", "-p", str(pid)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        subprocess.run(["ionice", "-c", "2", "-n", "0", "-p", str(pid)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        return True
    except Exception:
        return False

def get_plasma_foreground_pid():
    # Detect active window in KDE Plasma Wayland or X11 / Gamescope
    for cmd in [
        ["kdotool", "getactivewindow", "getwindowpid"],
        ["xdotool", "getactivewindow", "getwindowpid"]
    ]:
        try:
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=0.5)
            if res.returncode == 0 and res.stdout.strip().isdigit():
                return res.stdout.strip()
        except Exception:
            pass
    return None

def scan_and_boost_games():
    boosted = get_boosted_pids()
    count = 0

    # 1. Boost active KDE Plasma / Gamescope foreground window (plasma-foreground-booster)
    fg_pid = get_plasma_foreground_pid()
    if fg_pid and fg_pid not in boosted:
        try:
            with open(f"/proc/{fg_pid}/comm", "r") as f:
                fg_comm = f.read().strip()
            if fg_comm not in ["plasmashell", "kwin_wayland", "systemsettings", "konsole", "zsh", "bash"]:
                if boost_pid(fg_pid):
                    log(f"⚡ Foreground GPU Shield: Boosted active window '{fg_comm}' (PID {fg_pid}) into dmemcg-gaming slice")
                    count += 1
                    boosted.add(str(fg_pid))
        except Exception:
            pass

    # 2. Boost game engines, Proton, Wine, Steam, and GPU compute processes
    try:
        pids = [p for p in os.listdir("/proc") if p.isdigit()]
        for p in pids:
            if p in boosted:
                continue
            comm_path = f"/proc/{p}/comm"
            cmdline_path = f"/proc/{p}/cmdline"
            if not os.path.exists(comm_path):
                continue
            try:
                with open(comm_path, "r") as f:
                    comm = f.read().strip()
                match = comm in GAME_PROCESS_NAMES or comm.startswith("wine") or comm.startswith("proton")
                if not match and os.path.exists(cmdline_path):
                    with open(cmdline_path, "rb") as f:
                        cmdline = f.read().decode("utf-8", errors="ignore")
                        if any(g in cmdline for g in ["steamapps", "Proton", "wine64"]):
                            match = True
                if match:
                    if boost_pid(p):
                        log(f"⚡ Boosted gaming process: {comm} (PID {p}) into dmemcg-gaming slice")
                        count += 1
            except Exception:
                continue
    except Exception:
        pass
    return count

def run_daemon():
    log("Starting dmemcg-booster VRAM shield & cgroups manager daemon...")
    init_cgroups()
    optimize_gpu_hardware()
    
    nv = get_nvidia_info()
    if nv["detected"]:
        log(f"Detected NVIDIA GPU (Driver: {nv['driver']}, ReBAR: {nv['rebar']}, VRAM: {nv['vram_total']})")

    while True:
        try:
            scan_and_boost_games()
            time.sleep(3)
        except KeyboardInterrupt:
            log("Stopping dmemcg-booster daemon.")
            break
        except Exception:
            time.sleep(5)

def print_status():
    print("=== [ dmemcg-booster Status ] ===")
    nv = get_nvidia_info()
    if nv["detected"]:
        print(f"GPU Driver:     NVIDIA {nv['driver']}")
        print(f"VRAM Total:     {nv['vram_total']}")
        print(f"VRAM Free:      {nv['vram_free']}")
        print(f"Resizable BAR:  {nv['rebar']}")
    else:
        print("GPU Driver:     Generic DRM / AMD / Intel")
    
    cg_active = os.path.exists(GAMING_SLICE)
    print(f"Cgroups v2:     {'Active (' + GAMING_SLICE + ')' if cg_active else 'Inactive'}")
    
    boosted = get_boosted_pids()
    print(f"Boosted Procs:  {len(boosted)} active process(es)")
    if boosted:
        for pid in list(boosted)[:10]:
            try:
                with open(f"/proc/{pid}/comm", "r") as f:
                    comm = f.read().strip()
                print(f"  • PID {pid}: {comm}")
            except Exception:
                pass
        if len(boosted) > 10:
            print(f"  ... and {len(boosted) - 10} more")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        arg = sys.argv[1]
        if arg in ["status", "--status"]:
            print_status()
            sys.exit(0)
        elif arg in ["--use-system-bus", "--daemon", "start", "-d"]:
            run_daemon()
            sys.exit(0)
        elif arg in ["boost", "--boost"] and len(sys.argv) > 2:
            init_cgroups()
            target = sys.argv[2]
            if target.isdigit():
                if boost_pid(target):
                    print(f"Successfully boosted PID {target}")
                else:
                    print(f"Failed to boost PID {target}")
            sys.exit(0)
        elif arg in ["rebar", "--rebar"]:
            nv = get_nvidia_info()
            print(f"Resizable BAR Status: {nv.get('rebar', 'Unknown')}")
            sys.exit(0)
        elif arg in ["-h", "--help"]:
            print("Usage: dmemcg-booster [status|boost <PID>|rebar|--use-system-bus|--daemon]")
            sys.exit(0)
    run_daemon()
DMEMCG_BIN_EOF
        chmod 755 "${staging_root}/usr/bin/dmemcg-booster"

        cat << 'RC_DMEMCG_EOF' > "${staging_root}/etc/rc.d/rc.dmemcg-booster"
#!/bin/sh
#
# /etc/rc.d/rc.dmemcg-booster - Device Memory Cgroups (dmemcg) VRAM Booster Daemon for Slackware
#

PIDFILE="/run/dmemcg-booster.pid"
BIN="/usr/bin/dmemcg-booster"

dmemcg_mount_cgroup2() {
  if [ -d /sys/fs/cgroup ] && ! mountpoint -q /sys/fs/cgroup 2>/dev/null; then
    mount -t cgroup2 none /sys/fs/cgroup 2>/dev/null || true
  fi
  if [ -f /sys/fs/cgroup/cgroup.subtree_control ]; then
    echo "+memory +io" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || \
    echo "+memory" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || true
  fi
}

dmemcg_start() {
  if [ -x "$BIN" ]; then
    echo "Starting dmemcg-booster VRAM daemon: $BIN --use-system-bus"
    dmemcg_mount_cgroup2
    if ! pgrep -f "$BIN" > /dev/null 2>&1; then
      rm -f "$PIDFILE" 2>/dev/null || true
      $BIN --use-system-bus > /var/log/dmemcg-booster.log 2>&1 &
      echo $! > "$PIDFILE" 2>/dev/null || true
    fi
  fi
}

dmemcg_stop() {
  echo "Stopping dmemcg-booster VRAM daemon..."
  pkill -TERM -f "$BIN" 2>/dev/null || true
  sleep 0.5
  pkill -KILL -f "$BIN" 2>/dev/null || true
  rm -f "$PIDFILE" 2>/dev/null || true
}

dmemcg_restart() {
  dmemcg_stop
  sleep 1
  dmemcg_start
}

dmemcg_status() {
  if pgrep -f "$BIN" > /dev/null 2>&1; then
    echo "dmemcg-booster is running."
    if [ -x "$BIN" ]; then
      "$BIN" status
    fi
  else
    echo "dmemcg-booster is NOT running."
  fi
}

case "$1" in
  'start')
    dmemcg_start
    ;;
  'stop')
    dmemcg_stop
    ;;
  'restart')
    dmemcg_restart
    ;;
  'status')
    dmemcg_status
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status}"
    exit 1
esac
RC_DMEMCG_EOF
        chmod 755 "${staging_root}/etc/rc.d/rc.dmemcg-booster"
    fi

    # Clean Arch metadata
    rm -f "${staging_root}/.BUILDINFO" "${staging_root}/.INSTALL" "${staging_root}/.MTREE" "${staging_root}/.PKGINFO"

    # Check if this package delivers udev hardware rules
    local has_udev_rules=0
    if [ -d "${staging_root}/lib/udev/rules.d" ] || [ -d "${staging_root}/etc/udev/rules.d" ] || [ -d "${staging_root}/usr/lib/udev/rules.d" ]; then
        if find "${staging_root}/lib/udev/rules.d" "${staging_root}/etc/udev/rules.d" "${staging_root}/usr/lib/udev/rules.d" -type f -name "*.rules" 2>/dev/null | grep -q .; then
            has_udev_rules=1
        fi
    fi

    # Write Slackware slack-desc
    local pkg_name="underpants-${pkg_id}"
    cat << DESC_EOF > "${staging_root}/install/slack-desc"
${pkg_name}: ${pkg_name} (Underpants Gnomes CachyOS Gaming Suite)
${pkg_name}:
${pkg_name}: High-performance native gaming and hardware utility (${pkg_id}),
${pkg_name}: optimized and packaged directly from CachyOS / Arch for Slackware.
${pkg_name}:
${pkg_name}: Part of the Underpants Gnomes Gaming Master Suite.
${pkg_name}: Maintained by slacky-update.
${pkg_name}:
${pkg_name}: 🧙 💰 Step 3: PROFIT!!!
${pkg_name}:
DESC_EOF

    # Write doinst.sh
    cat << 'DOINST_EOF' > "${staging_root}/install/doinst.sh"
if [ -x /sbin/ldconfig ]; then
  /sbin/ldconfig 2>/dev/null || true
fi
if [ -x /usr/bin/update-desktop-database ]; then
  /usr/bin/update-desktop-database /usr/share/applications 2>/dev/null || true
fi
if [ -x /usr/bin/gtk-update-icon-cache ]; then
  /usr/bin/gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
fi
if [ -x /usr/bin/glib-compile-schemas ]; then
  /usr/bin/glib-compile-schemas /usr/share/glib-2.0/schemas 2>/dev/null || true
fi
if [ -x /usr/bin/update-mime-database ]; then
  /usr/bin/update-mime-database /usr/share/mime 2>/dev/null || true
fi
DOINST_EOF

    if [ "${has_udev_rules}" -eq 1 ]; then
        cat << 'UDEV_DOINST_EOF' >> "${staging_root}/install/doinst.sh"
if [ -x /sbin/udevadm ]; then
  /sbin/udevadm control --reload-rules 2>/dev/null || true
  /sbin/udevadm trigger 2>/dev/null || true
fi
UDEV_DOINST_EOF
    fi

    cat << 'DOINST_TAIL_EOF' >> "${staging_root}/install/doinst.sh"
if [ -f /lib64/libelogind.so.0 ] && [ ! -e /usr/lib64/libsystemd.so.0 ]; then
  mkdir -p /usr/lib64
  ln -sf /lib64/libelogind.so.0 /usr/lib64/libsystemd.so.0 2>/dev/null || true
fi
if [ -f /lib/libelogind.so.0 ] && [ ! -e /usr/lib/libsystemd.so.0 ]; then
  mkdir -p /usr/lib
  ln -sf /lib/libelogind.so.0 /usr/lib/libsystemd.so.0 2>/dev/null || true
fi
if [ -f /usr/share/vulkan/implicit_layer.d/MangoHud.x86_64.json ] && [ ! -e /usr/share/vulkan/implicit_layer.d/MangoHud.json ]; then
  ln -sf MangoHud.x86_64.json /usr/share/vulkan/implicit_layer.d/MangoHud.json 2>/dev/null || true
fi
if [ -f /usr/share/vulkan/implicit_layer.d/MangoApp.x86_64.json ] && [ ! -e /usr/share/vulkan/implicit_layer.d/MangoApp.json ]; then
  ln -sf MangoApp.x86_64.json /usr/share/vulkan/implicit_layer.d/MangoApp.json 2>/dev/null || true
fi
if [ -f /usr/share/vulkan/implicit_layer.d/obs_vkcapture_64.json ] && [ ! -e /usr/share/vulkan/implicit_layer.d/obs_vkcapture.json ]; then
  ln -sf obs_vkcapture_64.json /usr/share/vulkan/implicit_layer.d/obs_vkcapture.json 2>/dev/null || true
fi
if [ -d /opt/obs-studio ]; then
  mkdir -p /opt/obs-studio/lib/obs-plugins /opt/obs-studio/share/obs/obs-plugins 2>/dev/null || true
  if [ -d /usr/lib64/obs-plugins ]; then
    # Clean up stray modular sub-plugins erroneously placed in root plugin directories by earlier builds
    for stray_so in /usr/lib64/obs-plugins/advanced-scene-switcher-*.so /opt/obs-studio/lib/obs-plugins/advanced-scene-switcher-*.so; do
      [ -f "${stray_so}" ] || continue
      rm -f "${stray_so}" 2>/dev/null || true
    done
    for obsitem in /usr/lib64/obs-plugins/*; do
      [ -e "${obsitem}" ] || continue
      obsbname=$(basename "${obsitem}")
      ( cd /opt/obs-studio/lib/obs-plugins && rm -rf "${obsbname}" && ln -sf "${obsitem}" "${obsbname}" 2>/dev/null || true )
    done
  fi
  if [ -d /usr/share/obs/obs-plugins ]; then
    for obsdir in /usr/share/obs/obs-plugins/*; do
      [ -d "${obsdir}" ] || continue
      obsbname=$(basename "${obsdir}")
      ( cd /opt/obs-studio/share/obs/obs-plugins && rm -rf "${obsbname}" && ln -sf "${obsdir}" "${obsbname}" 2>/dev/null || true )
    done
  fi
fi
if [ -d /usr/lib64/darktable ] && [ ! -e /usr/lib/darktable ]; then
  mkdir -p /usr/lib
  ln -sf /usr/lib64/darktable /usr/lib/darktable 2>/dev/null || true
fi
if [ -f /usr/lib64/liblua.so.5.4 ] && [ ! -e /usr/lib64/liblua5.4.so.5.4 ]; then
  ln -sf liblua.so.5.4 /usr/lib64/liblua5.4.so.5.4 2>/dev/null || true
  ln -sf liblua.so.5.4 /usr/lib64/liblua5.4.so 2>/dev/null || true
fi
if [ -f /usr/lib64/libappindicator3.so.1 ] && [ ! -e /usr/lib64/libayatana-appindicator3.so.1 ]; then
  ln -sf libappindicator3.so.1 /usr/lib64/libayatana-appindicator3.so.1 2>/dev/null || true
  ln -sf libappindicator3.so.1 /usr/lib64/libayatana-appindicator3.so 2>/dev/null || true
  ln -sf libappindicator.so.1 /usr/lib64/libayatana-appindicator.so.1 2>/dev/null || true
  ln -sf libappindicator.so.1 /usr/lib64/libayatana-appindicator.so 2>/dev/null || true
fi
if [ -f /usr/lib64/libindicator3.so.7 ] && [ ! -e /usr/lib64/libayatana-indicator3.so.7 ]; then
  ln -sf libindicator3.so.7 /usr/lib64/libayatana-indicator3.so.7 2>/dev/null || true
  ln -sf libindicator3.so.7 /usr/lib64/libayatana-indicator3.so 2>/dev/null || true
  ln -sf libindicator.so.7 /usr/lib64/libayatana-indicator.so.7 2>/dev/null || true
  ln -sf libindicator.so.7 /usr/lib64/libayatana-indicator.so 2>/dev/null || true
fi
if [ -f /usr/lib64/libcurl.so.4 ] && [ ! -e /usr/lib64/libcurl-gnutls.so.4 ]; then
  ln -sf libcurl.so.4 /usr/lib64/libcurl-gnutls.so.4 2>/dev/null || true
  ln -sf libcurl.so.4 /usr/lib64/libcurl-gnutls.so 2>/dev/null || true
fi
if [ -f /usr/lib64/libyabridge-vst2.so ] || [ -f /usr/lib64/libyabridge-chainloader-vst2.so ]; then
  mkdir -p /usr/lib
  for yso in /usr/lib64/libyabridge*.so; do
    if [ -f "${yso}" ]; then
      ysoname=$(basename "${yso}")
      [ -e "/usr/lib/${ysoname}" ] || ln -sf "../lib64/${ysoname}" "/usr/lib/${ysoname}" 2>/dev/null || true
    fi
  done
fi
if [ -d /usr/lib64/steam ] && [ ! -e /usr/lib/steam ]; then
  mkdir -p /usr/lib
  ln -sf ../lib64/steam /usr/lib/steam 2>/dev/null || true
elif [ -d /usr/lib/steam ] && [ ! -e /usr/lib64/steam ]; then
  mkdir -p /usr/lib64
  ln -sf ../lib/steam /usr/lib64/steam 2>/dev/null || true
fi
if [ -d /usr/lib64/steam ] && [ -f /usr/lib64/steam/bin_steam.sh ] && [ ! -e /usr/lib64/steam/steam ]; then
  ( cd /usr/lib64/steam && ln -sf bin_steam.sh steam 2>/dev/null || true )
fi
if [ -d /usr/lib/steam ] && [ -f /usr/lib/steam/bin_steam.sh ] && [ ! -e /usr/lib/steam/steam ]; then
  ( cd /usr/lib/steam && ln -sf bin_steam.sh steam 2>/dev/null || true )
fi

# Slackware rc.local integration for daemons:
if [ -f /etc/rc.d/rc.ananicy-cpp ]; then
  chmod 755 /etc/rc.d/rc.ananicy-cpp 2>/dev/null || true
  if [ -f /etc/rc.d/rc.local ] && ! grep -q "rc.ananicy-cpp" /etc/rc.d/rc.local 2>/dev/null; then
    cat << 'RC_EOF' >> /etc/rc.d/rc.local

# Start Ananicy C++ auto-nice daemon:
if [ -x /etc/rc.d/rc.ananicy-cpp ]; then
  /etc/rc.d/rc.ananicy-cpp start
fi
RC_EOF
  fi
  if [ -f /etc/rc.d/rc.local_shutdown ] && ! grep -q "rc.ananicy-cpp" /etc/rc.d/rc.local_shutdown 2>/dev/null; then
    cat << 'RC_EOF' >> /etc/rc.d/rc.local_shutdown

# Stop Ananicy C++ auto-nice daemon:
if [ -x /etc/rc.d/rc.ananicy-cpp ]; then
  /etc/rc.d/rc.ananicy-cpp stop
fi
RC_EOF
  fi
fi

if [ -f /etc/rc.d/rc.lact ]; then
  chmod 755 /etc/rc.d/rc.lact 2>/dev/null || true
  if [ -f /etc/rc.d/rc.local ] && ! grep -q "rc.lact" /etc/rc.d/rc.local 2>/dev/null; then
    cat << 'RC_EOF' >> /etc/rc.d/rc.local

# Start LACT GPU control daemon:
if [ -x /etc/rc.d/rc.lact ]; then
  /etc/rc.d/rc.lact start
fi
RC_EOF
  fi
  if [ -f /etc/rc.d/rc.local_shutdown ] && ! grep -q "rc.lact" /etc/rc.d/rc.local_shutdown 2>/dev/null; then
    cat << 'RC_EOF' >> /etc/rc.d/rc.local_shutdown

# Stop LACT GPU control daemon:
if [ -x /etc/rc.d/rc.lact ]; then
  /etc/rc.d/rc.lact stop
fi
RC_EOF
  fi
fi

if [ -f /etc/rc.d/rc.scx ]; then
  chmod 755 /etc/rc.d/rc.scx 2>/dev/null || true
  if [ -f /etc/rc.d/rc.local ] && ! grep -q "rc.scx" /etc/rc.d/rc.local 2>/dev/null; then
    cat << 'RC_EOF' >> /etc/rc.d/rc.local

# Start Sched-EXT gaming scheduler:
if [ -x /etc/rc.d/rc.scx ]; then
  /etc/rc.d/rc.scx start
fi
RC_EOF
  fi
  if [ -f /etc/rc.d/rc.local_shutdown ] && ! grep -q "rc.scx" /etc/rc.d/rc.local_shutdown 2>/dev/null; then
    cat << 'RC_EOF' >> /etc/rc.d/rc.local_shutdown

# Stop Sched-EXT gaming scheduler:
if [ -x /etc/rc.d/rc.scx ]; then
  /etc/rc.d/rc.scx stop
fi
RC_EOF
  fi
fi

if [ -f /etc/rc.d/rc.coolercontrol ]; then
  chmod 755 /etc/rc.d/rc.coolercontrol 2>/dev/null || true
  if [ -f /etc/rc.d/rc.local ] && ! grep -q "rc.coolercontrol" /etc/rc.d/rc.local 2>/dev/null; then
    cat << 'RC_EOF' >> /etc/rc.d/rc.local

# Start CoolerControl daemon:
if [ -x /etc/rc.d/rc.coolercontrol ]; then
  /etc/rc.d/rc.coolercontrol start
fi
RC_EOF
  fi
  if [ -f /etc/rc.d/rc.local_shutdown ] && ! grep -q "rc.coolercontrol" /etc/rc.d/rc.local_shutdown 2>/dev/null; then
    cat << 'RC_EOF' >> /etc/rc.d/rc.local_shutdown

# Stop CoolerControl daemon:
if [ -x /etc/rc.d/rc.coolercontrol ]; then
  /etc/rc.d/rc.coolercontrol stop
fi
RC_EOF
  fi
fi

if [ -f /etc/rc.d/rc.asusd ]; then
  chmod 755 /etc/rc.d/rc.asusd 2>/dev/null || true
  if [ -f /etc/rc.d/rc.local ] && ! grep -q "rc.asusd" /etc/rc.d/rc.local 2>/dev/null; then
    cat << 'RC_EOF' >> /etc/rc.d/rc.local

# Start ASUS control daemon:
if [ -x /etc/rc.d/rc.asusd ]; then
  /etc/rc.d/rc.asusd start
fi
RC_EOF
  fi
  if [ -f /etc/rc.d/rc.local_shutdown ] && ! grep -q "rc.asusd" /etc/rc.d/rc.local_shutdown 2>/dev/null; then
    cat << 'RC_EOF' >> /etc/rc.d/rc.local_shutdown

# Stop ASUS control daemon:
if [ -x /etc/rc.d/rc.asusd ]; then
  /etc/rc.d/rc.asusd stop
fi
RC_EOF
  fi
fi

if [ -f /etc/rc.d/rc.syncthing ]; then
  chmod 755 /etc/rc.d/rc.syncthing 2>/dev/null || true
  if [ -f /etc/rc.d/rc.local ] && ! grep -q "rc.syncthing" /etc/rc.d/rc.local 2>/dev/null; then
    cat << 'RC_EOF' >> /etc/rc.d/rc.local

# Start Syncthing service:
if [ -x /etc/rc.d/rc.syncthing ]; then
  /etc/rc.d/rc.syncthing start
fi
RC_EOF
  fi
  if [ -f /etc/rc.d/rc.local_shutdown ] && ! grep -q "rc.syncthing" /etc/rc.d/rc.local_shutdown 2>/dev/null; then
    cat << 'RC_EOF' >> /etc/rc.d/rc.local_shutdown

# Stop Syncthing service:
if [ -x /etc/rc.d/rc.syncthing ]; then
  /etc/rc.d/rc.syncthing stop
fi
RC_EOF
  fi
fi

if [ -f /etc/rc.d/rc.dmemcg-booster ]; then
  chmod 755 /etc/rc.d/rc.dmemcg-booster 2>/dev/null || true
  if [ -f /etc/rc.d/rc.local ] && ! grep -q "rc.dmemcg-booster" /etc/rc.d/rc.local 2>/dev/null; then
    cat << 'RC_EOF' >> /etc/rc.d/rc.local

# Start dmemcg-booster VRAM daemon:
if [ -x /etc/rc.d/rc.dmemcg-booster ]; then
  /etc/rc.d/rc.dmemcg-booster start
fi
RC_EOF
  fi
  if [ -f /etc/rc.d/rc.local_shutdown ] && ! grep -q "rc.dmemcg-booster" /etc/rc.d/rc.local_shutdown 2>/dev/null; then
    cat << 'RC_EOF' >> /etc/rc.d/rc.local_shutdown

# Stop dmemcg-booster VRAM daemon:
if [ -x /etc/rc.d/rc.dmemcg-booster ]; then
  /etc/rc.d/rc.dmemcg-booster stop
fi
RC_EOF
  fi
fi

if [ -d /etc/easyeffects/output ]; then
  for u_home in /home/*; do
    [ -d "${u_home}" ] || continue
    u_uid=$(stat -c '%u' "${u_home}" 2>/dev/null || echo 0)
    [ "${u_uid}" -ge 1000 ] || continue
    u_name=$(basename "${u_home}")
    mkdir -p "${u_home}/.config/easyeffects/output" "${u_home}/.config/easyeffects/irs" 2>/dev/null || true
    cp -n /etc/easyeffects/output/*.json "${u_home}/.config/easyeffects/output/" 2>/dev/null || true
    if [ -d /etc/easyeffects/irs ]; then
      cp -n /etc/easyeffects/irs/* "${u_home}/.config/easyeffects/irs/" 2>/dev/null || true
    fi
    for jf in "${u_home}/.config/easyeffects/output"/*.json; do
      [ -f "${jf}" ] || continue
      sed -i "s|<PRESETS_DIRECTORY>|${u_home}/.config/easyeffects|g" "${jf}" 2>/dev/null || true
    done
    chown -R "${u_name}:users" "${u_home}/.config/easyeffects" 2>/dev/null || true
  done
fi

# DKMS Kernel Driver Auto-registration & Compilation
if [ -x /usr/sbin/dkms ] || [ -x /usr/bin/dkms ]; then
  DKMS_BIN=$(command -v dkms 2>/dev/null || echo "/usr/sbin/dkms")
  for dconf in /usr/src/*/dkms.conf; do
    [ -f "${dconf}" ] || continue
    ddir=$(dirname "${dconf}")
    dname=$(basename "${ddir}")
    mod_name=$(grep -E '^\s*PACKAGE_NAME=' "${dconf}" 2>/dev/null | head -n1 | cut -d= -f2 | tr -d '"'\'' ')
    mod_ver=$(grep -E '^\s*PACKAGE_VERSION=' "${dconf}" 2>/dev/null | head -n1 | cut -d= -f2 | tr -d '"'\'' ')
    [ -z "${mod_name}" ] && mod_name=$(echo "${dname}" | sed -E 's/-[0-9].*//')
    [ -z "${mod_ver}" ] && mod_ver=$(echo "${dname}" | sed -E 's/^[a-zA-Z0-9_\-]+-//')
    if [ -n "${mod_name}" ] && [ -n "${mod_ver}" ]; then
      if [ ! -e "/usr/src/${mod_name}-${mod_ver}" ] && [ -d "${ddir}" ]; then
        ln -sf "${dname}" "/usr/src/${mod_name}-${mod_ver}" 2>/dev/null || true
      fi
      "${DKMS_BIN}" add -m "${mod_name}" -v "${mod_ver}" 2>/dev/null || true
      for kdir in /lib/modules/*; do
        [ -d "${kdir}/build" ] || continue
        kver=$(basename "${kdir}")
        "${DKMS_BIN}" build -m "${mod_name}" -v "${mod_ver}" -k "${kver}" 2>/dev/null || true
        "${DKMS_BIN}" install -m "${mod_name}" -v "${mod_ver}" -k "${kver}" 2>/dev/null || true
      done
    fi
  done
fi

if [ -f /etc/modules-load.d/zenpower.conf ]; then
  /sbin/modprobe -r k10temp 2>/dev/null || true
  /sbin/modprobe zenpower 2>/dev/null || true
fi
if [ -f /etc/modules-load.d/v4l2loopback.conf ]; then
  /sbin/modprobe v4l2loopback 2>/dev/null || true
fi
DOINST_TAIL_EOF
    chmod 755 "${staging_root}/install/doinst.sh"

    # Permissions
    chmod -R u=rwX,go=rX "${staging_root}"
    [ -d "${staging_root}/etc/rc.d" ] && chmod 755 "${staging_root}/etc/rc.d/"* 2>/dev/null || true

    log_info "Assembling Slackware package: ${pkg_name}-${ver}-x86_64-1_slacky.txz..."
    local txz_out="${staging_base}/${pkg_name}-${ver}-x86_64-1_slacky.txz"
    rm -f "${txz_out}"
    (
        cd "${staging_root}"
        "${PKG_MAKE_CMD}" -l y -c n --compress -1 "${txz_out}" >/dev/null 2>&1
    )

    if [ -f "${txz_out}" ]; then
        chmod 644 "${txz_out}"
        cleanup_foreign_gaming_pkgs "${pkg_id}"
        validate_privileges
        log_info "Installing ${pkg_name} to system..."
        sudo "${PKG_UPGRADE_CMD}" --install-new --reinstall "${txz_out}"

        log_info "[1/4] Updating dynamic linker cache (ldconfig)..."
        sudo /sbin/ldconfig 2>/dev/null || true

        log_info "[2/4] Registering desktop application entries & GSettings..."
        if [ -x /usr/bin/update-desktop-database ]; then
            sudo /usr/bin/update-desktop-database /usr/share/applications 2>/dev/null || true
        fi
        if [ -x /usr/bin/glib-compile-schemas ]; then
            sudo /usr/bin/glib-compile-schemas /usr/share/glib-2.0/schemas 2>/dev/null || true
        fi

        log_info "[3/4] Rebuilding GTK/KDE icon theme cache & MIME database..."
        if [ -x /usr/bin/gtk-update-icon-cache ]; then
            sudo /usr/bin/gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
            [ -d /usr/share/icons/breeze ] && sudo /usr/bin/gtk-update-icon-cache -f -t /usr/share/icons/breeze 2>/dev/null || true
            [ -d /usr/share/icons/breeze-dark ] && sudo /usr/bin/gtk-update-icon-cache -f -t /usr/share/icons/breeze-dark 2>/dev/null || true
        fi
        if [ -x /usr/bin/update-mime-database ]; then
            sudo /usr/bin/update-mime-database /usr/share/mime 2>/dev/null || true
        fi

        # Conditional hardware device udev trigger
        if [ "${has_udev_rules}" -eq 1 ]; then
            log_info "[*] Reloading hardware device udev rules..."
            if [ -x /sbin/udevadm ]; then
                sudo /sbin/udevadm control --reload-rules 2>/dev/null || true
                sudo /sbin/udevadm trigger 2>/dev/null || true
            fi
        fi

        # GameMode libelogind D-Bus compatibility symlink
        if [ "${pkg_id}" = "gamemode" ]; then
            if [ -f /lib64/libelogind.so.0 ] && [ ! -e /usr/lib64/libsystemd.so.0 ]; then
                sudo mkdir -p /usr/lib64
                sudo ln -sf /lib64/libelogind.so.0 /usr/lib64/libsystemd.so.0 2>/dev/null || true
            fi
            if [ -f /lib/libelogind.so.0 ] && [ ! -e /usr/lib/libsystemd.so.0 ]; then
                sudo mkdir -p /usr/lib
                sudo ln -sf /lib/libelogind.so.0 /usr/lib/libsystemd.so.0 2>/dev/null || true
            fi
        fi

        # Start daemons if applicable
        if [ "${pkg_id}" = "lact" ] && [ -x /etc/rc.d/rc.lact ]; then
            sudo /etc/rc.d/rc.lact start 2>/dev/null || true
        elif [ "${pkg_id}" = "ananicy" ] && [ -x /etc/rc.d/rc.ananicy-cpp ]; then
            sudo /etc/rc.d/rc.ananicy-cpp restart 2>/dev/null || true
        elif [ "${pkg_id}" = "scx" ]; then
            if [ -f /usr/share/dbus-1/system.d/org.scx.Loader.conf ] && [ ! -f /etc/dbus-1/system.d/org.scx.Loader.conf ]; then
                sudo cp -a /usr/share/dbus-1/system.d/org.scx.Loader.conf /etc/dbus-1/system.d/ 2>/dev/null || true
            fi
            sudo killall -HUP dbus-daemon 2>/dev/null || true
            if [ -x /etc/rc.d/rc.scx ]; then
                sudo /etc/rc.d/rc.scx restart 2>/dev/null || true
            fi
        elif [ "${pkg_id}" = "easyeffects" ]; then
            if [ -d /etc/easyeffects/output ]; then
                for u_home in "${HOME:-}" /home/*; do
                    [ -d "${u_home}" ] || continue
                    [ -w "${u_home}" ] || continue
                    mkdir -p "${u_home}/.config/easyeffects/output" "${u_home}/.config/easyeffects/irs" 2>/dev/null || true
                    cp -n /etc/easyeffects/output/*.json "${u_home}/.config/easyeffects/output/" 2>/dev/null || true
                    if [ -d /etc/easyeffects/irs ]; then
                        cp -n /etc/easyeffects/irs/* "${u_home}/.config/easyeffects/irs/" 2>/dev/null || true
                    fi
                    for jf in "${u_home}/.config/easyeffects/output"/*.json; do
                        [ -f "${jf}" ] || continue
                        sed -i "s|<PRESETS_DIRECTORY>|${u_home}/.config/easyeffects|g" "${jf}" 2>/dev/null || true
                    done
                done
            fi
        elif [ "${pkg_id}" = "coolercontrol" ] && [ -x /etc/rc.d/rc.coolercontrol ]; then
            sudo /etc/rc.d/rc.coolercontrol restart 2>/dev/null || true
        elif [ "${pkg_id}" = "asusctl" ] && [ -x /etc/rc.d/rc.asusd ]; then
            sudo /etc/rc.d/rc.asusd restart 2>/dev/null || true
        elif [ "${pkg_id}" = "syncthing" ] && [ -x /etc/rc.d/rc.syncthing ]; then
            sudo /etc/rc.d/rc.syncthing restart 2>/dev/null || true
        elif [ "${pkg_id}" = "vram-booster" ] && [ -x /etc/rc.d/rc.dmemcg-booster ]; then
            sudo /etc/rc.d/rc.dmemcg-booster restart 2>/dev/null || true
        elif [ "${pkg_id}" = "openrgb" ]; then
            # Clean up / migrate legacy AppImage desktop entries in user autostart and local applications
            for u_home in /home/* "${HOME:-}"; do
                [ -d "${u_home}" ] || continue
                for d_dir in "${u_home}/.config/autostart" "${u_home}/.local/share/applications"; do
                    [ -d "${d_dir}" ] || continue
                    for f in "${d_dir}"/*[oO]pen[rR][gG][bB]*.desktop; do
                        [ -f "${f}" ] || continue
                        sed -i -E 's|Exec=.*[oO]pen[rR][gG][bB].*AppImage|Exec=/usr/bin/openrgb|g; s|Exec=.*OpenRGB-[^ ]*|Exec=/usr/bin/openrgb|g' "${f}" 2>/dev/null || true
                    done
                done
            done
        elif [ "${pkg_id}" = "limine" ]; then
            if command -v is_limine_installed >/dev/null 2>&1 && [ "$(is_limine_installed)" = "true" ]; then
                log_info "[*] Limine bootloader package updated: syncing EFI payload, configuration & BLAKE2B enrollment..."
                backup_limine_self_heal 2>/dev/null || true
                generate_limine_configuration 2>/dev/null || true
                enroll_and_sign_limine 2>/dev/null || true
            fi
        elif [ "${pkg_id}" = "sbctl" ]; then
            if command -v is_limine_installed >/dev/null 2>&1 && [ "$(is_limine_installed)" = "true" ]; then
                log_info "[*] sbctl updated: re-signing Limine EFI payload..."
                sign_limine_efi_sbctl 2>/dev/null || true
            fi
        fi

        log_info "[4/4] Synchronizing system status & background registry..."
        sleep 0.5
        trigger_silent_background_refresh 2>/dev/null || true
        log_success "${pkg_name} (v${ver}) deployed successfully!"
    else
        log_error "Failed to create ${pkg_name} txz package."
        rm -rf "${staging_base}"
        return 1
    fi

    rm -rf "${staging_base}" 2>/dev/null || true
    trap - INT TERM
}

deploy_gaming_packages_batch() {
    local target_pkg_ids=("$@")
    [ ${#target_pkg_ids[@]} -gt 0 ] || return 0

    log_info "Resolving upstream package metadata for ${#target_pkg_ids[@]} selected packages in parallel..."
    local metadata_raw
    metadata_raw=$(resolve_multiple_gaming_upstreams_batch "${target_pkg_ids[@]}")
    if [ -z "${metadata_raw}" ]; then
        log_error "Failed to resolve upstream package metadata for batch."
        return 1
    fi

    local staging_base
    staging_base=$(mktemp -d "$(get_user_staging_dir)/gnome-batch.XXXXXX" 2>/dev/null || mktemp -d /tmp/slacky-gnome-batch.XXXXXX)
    local batch_cache="${staging_base}/downloads"
    mkdir -p "${batch_cache}"
    trap 'rm -rf "${staging_base:-}" 2>/dev/null || true' INT TERM

    local dl_items=()
    local valid_entries=()

    while IFS='|' read -r pid ver main_url lib32_url extra_url; do
        [ -n "${pid}" ] || continue
        if [ "${ver}" = "NONE" ] || [ -z "${main_url}" ] || [ "${main_url}" = "NONE" ]; then
            log_warn "Skipping unresolved package: ${pid}"
            continue
        fi
        valid_entries+=("${pid}|${ver}|${main_url}|${lib32_url}|${extra_url}")

        if [ "${main_url}" != "BUNDLED" ]; then
            local mf="${batch_cache}/$(basename "${main_url}")"
            if [[ "${main_url}" =~ (cachyos\.org|pkgbuild\.com|archlinux\.org|chaotic\.cx) ]] && [[ "${main_url}" =~ \.pkg\.tar\.zst$ ]]; then
                dl_items+=("${main_url}|${mf}|${main_url}.sig|${mf}.sig")
            else
                dl_items+=("${main_url}|${mf}")
            fi

            if [ "${lib32_url}" != "NONE" ] && [ -n "${lib32_url}" ]; then
                local lf="${batch_cache}/$(basename "${lib32_url}")"
                if [[ "${lib32_url}" =~ (cachyos\.org|pkgbuild\.com|archlinux\.org|chaotic\.cx) ]] && [[ "${lib32_url}" =~ \.pkg\.tar\.zst$ ]]; then
                    dl_items+=("${lib32_url}|${lf}|${lib32_url}.sig|${lf}.sig")
                else
                    dl_items+=("${lib32_url}|${lf}")
                fi
            fi

            if [ "${extra_url}" != "NONE" ] && [ -n "${extra_url}" ]; then
                IFS=',' read -ra EXTRA_URLS <<< "${extra_url}"
                for single_extra_url in "${EXTRA_URLS[@]}"; do
                    [ -n "${single_extra_url}" ] || continue
                    local ef="${batch_cache}/$(basename "${single_extra_url}")"
                    if [[ "${single_extra_url}" =~ (cachyos\.org|pkgbuild\.com|archlinux\.org|chaotic\.cx) ]] && [[ "${single_extra_url}" =~ \.pkg\.tar\.zst$ ]]; then
                        dl_items+=("${single_extra_url}|${ef}|${single_extra_url}.sig|${ef}.sig")
                    else
                        dl_items+=("${single_extra_url}|${ef}")
                    fi
                done
            fi
        fi
    done <<< "${metadata_raw}"

    local total_pkgs=${#valid_entries[@]}
    if [ "${total_pkgs}" -eq 0 ]; then
        log_warn "No valid packages to install."
        rm -rf "${staging_base}"
        return 0
    fi

    if [ ${#dl_items[@]} -gt 0 ]; then
        echo ""
        log_info "⚡ Starting Unified Parallel Batch Download (${total_pkgs} packages • ${#dl_items[@]} files)..."
        if ! download_parallel_pacman "Underpants Gnomes Batch (${total_pkgs} packages)" "${dl_items[@]}"; then
            log_error "Failed to complete parallel download batch."
            rm -rf "${staging_base}"
            return 1
        fi
    fi

    # Phase 2: Decoupled Sequential Transmutation & Installation
    validate_privileges
    local current_idx=1
    local success_count=0

    for entry in "${valid_entries[@]}"; do
        IFS='|' read -r pid ver main_url lib32_url extra_url <<< "${entry}"
        echo ""
        echo -e "${CYAN}${BOLD}================================================================================${RESET}"
        echo -e "${YELLOW}${BOLD} 🧙 [${current_idx}/${total_pkgs}] Transmuting & Deploying: ${pid} (v${ver}) ${RESET}"
        echo -e "${CYAN}${BOLD}================================================================================${RESET}"
        if transmute_and_deploy_gaming_pkg "${pid}" "${batch_cache}" "${ver}" "${main_url}" "${lib32_url}" "${extra_url}"; then
            success_count=$((success_count + 1))
        else
            log_error "Failed to deploy ${pid}. Continuing with remaining batch..."
        fi
        current_idx=$((current_idx + 1))
    done

    rm -rf "${staging_base}" 2>/dev/null || true
    echo ""
    log_success "🎉 Batch deployment complete! ${success_count}/${total_pkgs} packages successfully installed!"
}

uninstall_cachyos_gaming_pkg() {
    local pkg_id="$1"
    validate_privileges
    local found=0
    for p in /var/log/packages/underpants-${pkg_id}-* /var/log/packages/cachyos-gnome-${pkg_id}-*; do
        [ -f "${p}" ] || continue
        local bname
        bname=$(basename "${p}")
        log_info "Removing package: ${bname}..."
        
        # Stop daemon if running
        if [ "${pkg_id}" = "lact" ] && [ -x /etc/rc.d/rc.lact ]; then
            sudo /etc/rc.d/rc.lact stop 2>/dev/null || true
        elif [ "${pkg_id}" = "scx" ] && [ -x /etc/rc.d/rc.scx ]; then
            sudo /etc/rc.d/rc.scx stop 2>/dev/null || true
        elif [ "${pkg_id}" = "ananicy" ] && [ -x /etc/rc.d/rc.ananicy-cpp ]; then
            sudo /etc/rc.d/rc.ananicy-cpp stop 2>/dev/null || true
        elif [ "${pkg_id}" = "coolercontrol" ] && [ -x /etc/rc.d/rc.coolercontrol ]; then
            sudo /etc/rc.d/rc.coolercontrol stop 2>/dev/null || true
        elif [ "${pkg_id}" = "asusctl" ] && [ -x /etc/rc.d/rc.asusd ]; then
            sudo /etc/rc.d/rc.asusd stop 2>/dev/null || true
        elif [ "${pkg_id}" = "syncthing" ] && [ -x /etc/rc.d/rc.syncthing ]; then
            sudo /etc/rc.d/rc.syncthing stop 2>/dev/null || true
        elif [ "${pkg_id}" = "vram-booster" ] && [ -x /etc/rc.d/rc.dmemcg-booster ]; then
            sudo /etc/rc.d/rc.dmemcg-booster stop 2>/dev/null || true
        elif [ "${pkg_id}" = "gamemode" ] && [ -x /etc/rc.d/rc.gamemode ]; then
            sudo /etc/rc.d/rc.gamemode stop 2>/dev/null || true
        elif [ "${pkg_id}" = "sunshine" ]; then
            pkill -x sunshine 2>/dev/null || true
        fi

        # Safely remove multi-line rc.local / rc.local_shutdown persistence blocks without leaving orphaned 'fi' tokens
        for rc_file in /etc/rc.d/rc.local /etc/rc.d/rc.local_shutdown; do
            [ -f "${rc_file}" ] || continue
            python3 -c "
import sys, re
path = sys.argv[1]
target = sys.argv[2]
try:
    with open(path, 'r', encoding='utf-8') as f:
        c = f.read()
    # Regex removes comment + if ... fi block atomically
    c = re.sub(rf'(?m)^#[^\n]*\nif\s+\[\s+-[xf]\s+/etc/rc\.d/{re.escape(target)}\s+\];\s+then\n\s+/etc/rc\.d/{re.escape(target)}\s+(?:start|stop)[^\n]*\nfi\n?', '', c)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(c)
except Exception:
    pass
" "${rc_file}" "rc.${pkg_id}" 2>/dev/null || true
        done

        sudo "${PKG_REMOVE_CMD}" "${bname}"
        found=1
    done

    if [ "${found}" -eq 1 ]; then
        if [ -d /opt/obs-studio ]; then
            find /opt/obs-studio/lib/obs-plugins /opt/obs-studio/share/obs/obs-plugins -xtype l -delete 2>/dev/null || true
        fi
        log_info "[1/3] Updating dynamic linker cache (ldconfig)..."
        sudo /sbin/ldconfig 2>/dev/null || true
        log_info "[2/3] Registering desktop application entries & GSettings..."
        if [ -x /usr/bin/update-desktop-database ]; then
            sudo /usr/bin/update-desktop-database /usr/share/applications 2>/dev/null || true
        fi
        if [ -x /usr/bin/glib-compile-schemas ]; then
            sudo /usr/bin/glib-compile-schemas /usr/share/glib-2.0/schemas 2>/dev/null || true
        fi
        log_info "[3/3] Rebuilding GTK/KDE icon theme cache & MIME database..."
        if [ -x /usr/bin/gtk-update-icon-cache ]; then
            sudo /usr/bin/gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
        fi
        if [ -x /usr/bin/update-mime-database ]; then
            sudo /usr/bin/update-mime-database /usr/share/mime 2>/dev/null || true
        fi
        sleep 0.5
        trigger_silent_background_refresh 2>/dev/null || true
        log_success "${pkg_id} uninstalled cleanly."
    else
        log_warn "No installed package found for: ${pkg_id}"
    fi
}

sync_all_installed_cachyos_gaming_packages() {
    log_info "Auditing installed Underpants Gnomes Gaming packages for upstream updates..."
    local outdated_pids=()
    
    while IFS='|' read -r pkg_id name cat main_pat l32_pat ext_pat repos; do
        [[ -z "${pkg_id}" || "${pkg_id}" =~ ^# ]] && continue
        local cur_ver
        cur_ver=$(get_installed_gaming_pkg_version "${pkg_id}")
        [ "${cur_ver}" != "NONE" ] || continue

        local latest_ver main_u l32_u ext_u
        read -r latest_ver main_u l32_u ext_u <<< "$(resolve_cachyos_gaming_upstream_metadata "${pkg_id}" || echo "NONE NONE NONE NONE")"
        
        if [ "${latest_ver}" != "NONE" ] && [ -n "${latest_ver}" ]; then
            local is_newer
            is_newer=$(compare_versions_strictly_greater "${latest_ver}" "${cur_ver}" 2>/dev/null || echo "false")
            if [ "${is_newer}" = "true" ]; then
                log_info "Upgrade available for ${name}: v${cur_ver} -> v${latest_ver}"
                outdated_pids+=("${pkg_id}")
            fi
        fi
    done <<< "$(get_gaming_catalog)"

    if [ ${#outdated_pids[@]} -gt 0 ]; then
        log_info "Deploying unified batch upgrade for ${#outdated_pids[@]} packages..."
        deploy_gaming_packages_batch "${outdated_pids[@]}"
    else
        log_info "All installed Underpants Gnomes Gaming packages are up to date."
    fi
    trigger_silent_background_refresh 2>/dev/null || true
}

# --- [ INTERACTIVE TUI GAMING MASTER STATION ] ---
interactive_cachyos_gaming_menu() {
    set_terminal_title "slacky-update: Underpants Gnomes Gaming Master Suite"

    # Category keys and human labels
    local CAT_KEYS=("engine" "launcher" "hardware" "streaming" "social" "audio" "creative" "tools" "browser" "bootloader")
    local CAT_TITLES=(
        "⚡ The Engine: Performance, HUD & Schedulers"
        "🎮 Storefronts & Launcher Managers"
        "🔧 Hardware Control, Tuning & DKMS Drivers"
        "🎬 OBS Studio & Video Production Plugins"
        "💬 Voice Chat, Social & Game Streaming"
        "🎧 Studio Audio DSP & Acoustic Processing"
        "🎨 Creative, 3D & Photography Studio"
        "🛠️ Power Tools & Media Sync"
        "🌐 Web Navigators & Browsers"
        "🛡️ Secure Boot & UEFI Utilities"
    )

    while true; do
        echo ""
        echo -e "${BLUE}${BOLD}"
        echo "================================================================================"
        echo " 🧙  UNDERPANTS GNOMES: CACHYOS GAMING & HARDWARE MASTER SUITE (SLACKWARE)  🧙 "
        echo "================================================================================"
        echo -e "${RESET}"
        echo -e " ${CYAN}Step 1: Steal Underpants  •  Step 2: Transmute to Slackware  •  Step 3: PROFIT!${RESET}"

        local index=1
        local item_ids=()
        local item_names=()
        local item_statuses=()
        local item_cats=()

        # Fast one-pass status resolution for all packages
        declare -A FAST_INSTALLED_MAP=()
        while IFS='=' read -r c_id c_ver; do
            [ -n "${c_id}" ] || continue
            FAST_INSTALLED_MAP["${c_id}"]="${c_ver}"
        done < <(python3 - << 'PYTUIFASTMAP'
import os, glob, shutil, subprocess, re

installed = {}
pkg_dir = '/var/log/packages'
if os.path.exists(pkg_dir):
    for f in os.listdir(pkg_dir):
        parts = f.rsplit('-', 3)
        if len(parts) >= 2:
            p_name = parts[0]
            p_ver = parts[1] if len(parts) >= 4 else "INSTALLED"
            for pref in ("underpants-", "cachyos-gnome-", "cachyos-gnome-gnome-"):
                if p_name.startswith(pref):
                    p_name = p_name[len(pref):]
            vm = re.match(r"^(.+?)-([0-9].*)$", p_name)
            if vm:
                p_name = vm.group(1)
                if p_ver.isdigit() or p_ver == "INSTALLED":
                    p_ver = vm.group(2)
            installed[p_name] = p_ver

# Check binaries & explicit files
BINARY_MAP = {
    "gamemode": ["gamemoded", "/usr/bin/gamemoded"],
    "mangohud": ["mangohud", "mangoapp"],
    "goverlay": ["goverlay"],
    "scx": ["scx_loader", "scx_lavd", "scx_rusty", "scx_bpfland"],
    "ananicy": ["ananicy-cpp", "/usr/bin/ananicy-cpp"],
    "vram-booster": ["dmemcg-booster", "/usr/bin/dmemcg-booster"],
    "gamescope": ["gamescope"],
    "retroarch": ["retroarch"],
    "steam": ["steam", "/usr/bin/steam"],
    "steam-devices": ["/lib/udev/rules.d/60-steam-input.rules", "/usr/lib/udev/rules.d/60-steam-input.rules", "/etc/udev/rules.d/60-steam-input.rules"],
    "lact": ["lact", "lactd"],
    "openrgb": ["openrgb"],
    "solaar": ["solaar"],
    "coolercontrol": ["coolercontrol", "coolercontrold"],
    "asusctl": ["asusctl", "supergfxd"],
    "zenpower3": ["/var/lib/dkms/zenpower*", "/usr/src/zenpower3*", "/usr/src/zenpower*"],
    "v4l2loopback": ["/var/lib/dkms/v4l2loopback*", "/usr/src/v4l2loopback*"],
    "rtl8821cu": ["/var/lib/dkms/rtl8821cu*", "/usr/lib/dkms/8821cu*"],
    "rtl88x2bu": ["/var/lib/dkms/rtl88x2bu*", "/usr/lib/dkms/8821cu*"],
    "rtl8812au": ["/var/lib/dkms/rtl8812au*", "/usr/lib/dkms/8812au*"],
    "broadcom-wl": ["/var/lib/dkms/broadcom-wl*", "/usr/lib/dkms/wl*"],
    "r8125": ["/var/lib/dkms/r8125*"],
    "obs-studio": ["obs"],
    "obs-vkcapture": ["obs-vkcapture", "/usr/lib64/obs-plugins/linux-vkcapture.so", "/usr/lib/obs-plugins/linux-vkcapture.so"],
    "obs-move-transition": ["/usr/lib64/obs-plugins/move-transition.so", "/opt/obs-studio/lib/obs-plugins/move-transition.so"],
    "obs-source-record": ["/usr/lib64/obs-plugins/source-record.so", "/opt/obs-studio/lib/obs-plugins/source-record.so"],
    "obs-pipewire-audio-capture": ["/usr/lib64/obs-plugins/linux-pipewire-audio.so", "/opt/obs-studio/lib/obs-plugins/linux-pipewire-audio.so"],
    "obs-advanced-scene-switcher": ["/usr/lib64/obs-plugins/advanced-scene-switcher.so", "/opt/obs-studio/lib/obs-plugins/advanced-scene-switcher.so"],
    "obs-multi-rtmp": ["/usr/lib64/obs-plugins/obs-multi-rtmp.so", "/opt/obs-studio/lib/obs-plugins/obs-multi-rtmp.so"],
    "obs-composite-blur": ["/usr/lib64/obs-plugins/composite-blur.so", "/opt/obs-studio/lib/obs-plugins/composite-blur.so"],
    "obs-teleport": ["/usr/lib64/obs-plugins/obs-teleport.so", "/opt/obs-studio/lib/obs-plugins/obs-teleport.so"],
    "discord": ["discord", "/opt/discord/Discord"],
    "vesktop": ["vesktop"],
    "sunshine": ["sunshine"],
    "easyeffects": ["easyeffects"],
    "pear-desktop": ["pear-desktop"],
    "audacity": ["audacity"],
    "spotify": ["spotify"],
    "yabridge": ["yabridgectl"],
    "inkscape": ["inkscape"],
    "darktable": ["darktable"],
    "syncthing": ["syncthing"],
    "google-chrome": ["google-chrome", "google-chrome-stable"],
    "microsoft-edge": ["microsoft-edge", "microsoft-edge-stable"],
    "brave": ["brave", "brave-browser"],
    "zen-browser": ["zen-browser", "zen"],
    "sbctl": ["sbctl"]
}

for pid, cands in BINARY_MAP.items():
    if pid in installed:
        continue
    for cand in cands:
        if cand.startswith('/'):
            if glob.glob(cand):
                installed[pid] = "INSTALLED"
                break
        else:
            bp = shutil.which(cand) or (os.path.exists(f"/usr/bin/{cand}") and f"/usr/bin/{cand}") or (os.path.exists(f"/usr/local/bin/{cand}") and f"/usr/local/bin/{cand}")
            if bp:
                ver = "INSTALLED"
                try:
                    out = subprocess.run([bp, "--version"], capture_output=True, text=True, timeout=1).stdout
                    vm = re.search(r'([0-9]+\.[0-9]+(?:\.[0-9]+)?)', out)
                    if vm:
                        ver = vm.group(1)
                except Exception:
                    pass
                installed[pid] = ver
                break

for k, v in installed.items():
    print(f"{k}={v}")
PYTUIFASTMAP
        )

        # Render categories in a clean 2-column grid
        for ci in "${!CAT_KEYS[@]}"; do
            local ckey="${CAT_KEYS[ci]}"
            local ctitle="${CAT_TITLES[ci]}"

            # Pre-calculate category items
            local cat_total=0
            local cat_installed=0
            local cat_entries=()

            while IFS='|' read -r pkg_id name cat main_pat l32_pat ext_pat repos; do
                [[ -z "${pkg_id}" || "${pkg_id}" =~ ^# ]] && continue
                [ "${cat}" = "${ckey}" ] || continue
                if ! is_gaming_pkg_whitelisted "${pkg_id}"; then
                    continue
                fi
                if [ "${pkg_id}" = "vram-booster" ] && ! is_vram_booster_supported; then
                    continue
                fi
                local cur_ver="${FAST_INSTALLED_MAP[${pkg_id}]:-NONE}"
                cat_total=$((cat_total + 1))
                if [ "${cur_ver}" != "NONE" ]; then
                    cat_installed=$((cat_installed + 1))
                fi
                cat_entries+=("${pkg_id}|${name}|${cur_ver}")
            done <<< "$(get_gaming_catalog)"

            [ ${cat_total} -gt 0 ] || continue

            # Category Section Header
            echo -e "\n${CYAN}${BOLD}── 📦 ${ctitle}${RESET} ${YELLOW}[${cat_installed}/${cat_total} installed]${RESET} ${CYAN}──${RESET}"

            # Render 2-by-2 grid for category items
            local num_entries=${#cat_entries[@]}
            for ((ei=0; ei < num_entries; ei+=2)); do
                # Column 1
                IFS='|' read -r p_id1 p_name1 p_ver1 <<< "${cat_entries[ei]}"
                item_ids+=("${p_id1}")
                item_names+=("${p_name1}")
                item_statuses+=("${p_ver1}")
                item_cats+=("${ckey}")
                local idx1=$index
                index=$((index + 1))

                local badge1
                if [ "${p_ver1}" != "NONE" ]; then
                    local sv1="${p_ver1}"
                    if [ "${sv1}" = "INSTALLED" ]; then
                        sv1="Inst"
                    elif [ ${#sv1} -gt 6 ]; then
                        sv1="${sv1:0:5}…"
                    fi
                    badge1="${GREEN}[v${sv1} ✓]${RESET}"
                else
                    badge1="${RED}[Not Inst]${RESET}"
                fi

                local sname1="${p_name1}"
                if [ ${#sname1} -gt 24 ]; then
                    sname1="${sname1:0:23}…"
                fi
                local col1
                col1=$(printf " ${BOLD}%2d.${RESET} %-24s %b" "${idx1}" "${sname1}" "${badge1}")

                # Column 2
                local col2=""
                if [ $((ei + 1)) -lt ${num_entries} ]; then
                    IFS='|' read -r p_id2 p_name2 p_ver2 <<< "${cat_entries[ei+1]}"
                    item_ids+=("${p_id2}")
                    item_names+=("${p_name2}")
                    item_statuses+=("${p_ver2}")
                    item_cats+=("${ckey}")
                    local idx2=$index
                    index=$((index + 1))

                    local badge2
                    if [ "${p_ver2}" != "NONE" ]; then
                        local sv2="${p_ver2}"
                        if [ "${sv2}" = "INSTALLED" ]; then
                            sv2="Inst"
                        elif [ ${#sv2} -gt 6 ]; then
                            sv2="${sv2:0:5}…"
                        fi
                        badge2="${GREEN}[v${sv2} ✓]${RESET}"
                    else
                        badge2="${RED}[Not Inst]${RESET}"
                    fi

                    local sname2="${p_name2}"
                    if [ ${#sname2} -gt 24 ]; then
                        sname2="${sname2:0:23}…"
                    fi
                    col2=$(printf "   ${BOLD}%2d.${RESET} %-24s %b" "${idx2}" "${sname2}" "${badge2}")
                fi

                echo -e "${col1}${col2}"
            done
        done

        echo -e "\n${BLUE}================================================================================"
        echo -e " ${BOLD}Batch & Automation Actions:${RESET}"
        echo -e "  ${CYAN}${BOLD}S.${RESET}  🔍 Search & Transmute Upstream Packages (30,000+ CachyOS & Arch Packages)"
        echo -e "  ${GREEN}${BOLD}A.${RESET}  ⚡ 1-Click Total Gaming Rig (Deploy All ${#item_ids[@]} Components in Unified Batch)"
        echo -e "  ${MAGENTA}${BOLD}O.${RESET}  🎬 1-Click OBS Creator & Streamer Suite (Deploy Complete OBS Power-Pack)"
        echo -e "  ${YELLOW}${BOLD}U.${RESET}  🔄 Synchronize & Upgrade All Installed Gaming Packages"
        echo -e "  ${RED}${BOLD}D.${RESET}  🗑️  Uninstall a Component"
        echo -e "  ${BOLD}Q.${RESET}  🚪 Catch You on the Flip Side (Return to Main Menu)"
        echo -e "${BLUE}================================================================================${RESET}"
        echo ""
        read -r -p "Pick your play [1-${#item_ids[@]} (multi e.g. 1 3 5 or 1-4), S, O, A, U, D, Q]: " user_choice
        user_choice=$(echo "${user_choice}" | tr '[:lower:]' '[:upper:]' | xargs)

        case "${user_choice}" in
            Q|"")
                trigger_silent_background_refresh 2>/dev/null || true
                break
                ;;
            S|SEARCH)
                gnomes_interactive_station
                ;;
            O|OBS)
                echo ""
                local obs_pids=()
                for oi in "${!item_ids[@]}"; do
                    if [[ "${item_ids[oi]}" =~ ^obs- ]]; then
                        obs_pids+=("${item_ids[oi]}")
                    fi
                done
                log_info "Starting 1-Click OBS Creator Suite Deployment (${#obs_pids[@]} packages in unified batch)..."
                validate_privileges
                deploy_gaming_packages_batch "${obs_pids[@]}"
                echo ""
                read -r -p "Press Enter to continue..."
                ;;
            A)
                echo ""
                log_info "Starting 1-Click Total Gaming Rig Deployment (${#item_ids[@]} packages in unified batch)..."
                validate_privileges
                deploy_gaming_packages_batch "${item_ids[@]}"
                echo ""
                read -r -p "Press Enter to continue..."
                ;;
            U)
                echo ""
                validate_privileges
                sync_all_installed_cachyos_gaming_packages
                echo ""
                read -r -p "Press Enter to continue..."
                ;;
            D)
                echo ""
                read -r -p "Enter number or package ID to uninstall [1-${#item_ids[@]}]: " del_input
                del_input=$(echo "${del_input}" | xargs)
                if [[ "${del_input}" =~ ^[0-9]+$ ]] && [ "${del_input}" -ge 1 ] && [ "${del_input}" -le "${#item_ids[@]}" ]; then
                    local target_del_idx=$((del_input - 1))
                    local del_id="${item_ids[${target_del_idx}]}"
                    uninstall_cachyos_gaming_pkg "${del_id}"
                elif [ -n "${del_input}" ]; then
                    uninstall_cachyos_gaming_pkg "${del_input}"
                else
                    log_warn "Invalid selection."
                fi
                echo ""
                read -r -p "Press Enter to continue..."
                ;;
            *)
                # Parse single, comma-separated, space-separated or range numbers (e.g. 1, 3, 5 or 1 3 5 or 1-4)
                local clean_input
                clean_input=$(echo "${user_choice}" | tr ',' ' ')
                local selected_pids=()
                
                for token in ${clean_input}; do
                    if [[ "${token}" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                        local start_n="${BASH_REMATCH[1]}"
                        local end_n="${BASH_REMATCH[2]}"
                        for ((n=start_n; n<=end_n; n++)); do
                            if [ "$n" -ge 1 ] && [ "$n" -le "${#item_ids[@]}" ]; then
                                selected_pids+=("${item_ids[$((n - 1))]}")
                            fi
                        done
                    elif [[ "${token}" =~ ^[0-9]+$ ]]; then
                        if [ "${token}" -ge 1 ] && [ "${token}" -le "${#item_ids[@]}" ]; then
                            selected_pids+=("${item_ids[$((token - 1))]}")
                        fi
                    fi
                done

                # Deduplicate selected_pids
                local unique_pids=()
                for p in "${selected_pids[@]}"; do
                    local already=0
                    for u in "${unique_pids[@]}"; do
                        if [ "${u}" = "${p}" ]; then
                            already=1
                            break
                        fi
                    done
                    if [ "${already}" -eq 0 ]; then
                        unique_pids+=("${p}")
                    fi
                done

                if [ ${#unique_pids[@]} -gt 0 ]; then
                    echo ""
                    if [ ${#unique_pids[@]} -eq 1 ]; then
                        log_info "Deploying single package: ${unique_pids[0]}..."
                        transmute_and_deploy_gaming_pkg "${unique_pids[0]}" || log_error "Failed to deploy ${unique_pids[0]}"
                    else
                        log_info "Deploying ${#unique_pids[@]} selected packages in unified batch..."
                        deploy_gaming_packages_batch "${unique_pids[@]}"
                    fi
                    echo ""
                    read -r -p "Press Enter to continue..."
                else
                    log_warn "Invalid selection."
                    sleep 1
                fi
                ;;
        esac
    done
}
