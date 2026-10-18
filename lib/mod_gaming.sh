#!/usr/bin/env bash
# --- [ UNDERPANTS GNOMES: CACHYOS GAMING & HARDWARE MASTER SUITE ] ---

set -euo pipefail

# --- [ REPOSITORY ENDPOINTS ] ---
CACHYOS_MAIN_REPO="https://mirror.cachyos.org/repo/x86_64/cachyos"
CACHYOS_EXTRA_REPO="https://mirror.cachyos.org/repo/x86_64/cachyos-extra"
ARCH_EXTRA_REPO="https://geo.mirror.pkgbuild.com/extra/os/x86_64"
ARCH_MULTILIB_REPO="https://geo.mirror.pkgbuild.com/multilib/os/x86_64"

# Dynamically load fastest ranked repos if available
_ranked_conf="${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/slacky-update/ranked_mirrors.json"
[ -f "/var/cache/slacky-update/ranked_mirrors.json" ] && [ ! -f "${_ranked_conf}" ] && _ranked_conf="/var/cache/slacky-update/ranked_mirrors.json"
if [ -f "${_ranked_conf}" ]; then
    _c_prim=$(grep -o '"cachyos_primary": *"[^"]*"' "${_ranked_conf}" 2>/dev/null | cut -d'"' -f4 || echo "")
    _a_prim=$(grep -o '"arch_primary": *"[^"]*"' "${_ranked_conf}" 2>/dev/null | cut -d'"' -f4 || echo "")
    [ -n "${_c_prim}" ] && CACHYOS_MAIN_REPO="${_c_prim}/x86_64/cachyos" && CACHYOS_EXTRA_REPO="${_c_prim}/x86_64/cachyos-extra"
    [ -n "${_a_prim}" ] && ARCH_EXTRA_REPO="${_a_prim}/extra/os/x86_64" && ARCH_MULTILIB_REPO="${_a_prim}/multilib/os/x86_64"
fi

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
openghub|OpenGHub (Logitech G HUB Native Linux Companion)|hardware|openghub(?:-bin|-git)?-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||webkit2gtk-4\.1-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libsoup3-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libmanette-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|aur,chaotic-aur,github,cachyos,arch-extra|hidden
coolercontrol|CoolerControl (All-in-One Liquid & Fan Control)|hardware|coolercontrol-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||coolercontrold-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|cachyos,arch-extra
asusctl|ASUS ROG Laptop Control Daemon & CLI|hardware|asusctl-(?:[0-9]+%3A)?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||arch-extra,cachyos
zenpower3|ZenPower AMD Ryzen Telemetry Driver (DKMS)|hardware|zenpower3-dkms-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst|||chaotic-aur,cachyos,arch-extra
v4l2loopback|V4L2 Loopback Virtual Video Device (DKMS)|hardware|v4l2loopback-dkms-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst|||arch-extra,cachyos,chaotic-aur
rtl8821cu|Realtek RTL8821CU USB Wi-Fi Driver (DKMS)|hardware|rtl8821cu-morrownr-dkms-git-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst|||chaotic-aur,cachyos
rtl88x2bu|Realtek RTL88x2BU USB Wi-Fi Driver (DKMS)|hardware|rtl88x2bu-dkms-git-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst|||chaotic-aur,cachyos|hidden
rtl8812au|Realtek RTL8812AU High-Power Wi-Fi Driver (DKMS)|hardware|rtl8812au-dkms-git-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst|||chaotic-aur,cachyos|hidden
broadcom-wl|Broadcom 802.11 Linux STA Wireless Driver (DKMS)|hardware|broadcom-wl-dkms-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst|||arch-extra,cachyos
r8125|Realtek 2.5GbE Ethernet Network Driver (DKMS)|hardware|r8125-dkms-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst|||chaotic-aur,cachyos-extra-v3,cachyos-extra,cachyos
spacenav|3Dconnexion SpaceMouse Master Suite (spacenavd, libspnav & spnavcfg)|hardware|spacenavd-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst||libspnav-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst,spnavcfg-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst|arch-extra,cachyos,chaotic-aur
volt-gui|Volt GUI (AMD Ryzen Undervolt & Curve Optimizer GUI)|hardware|volt-gui(?:-bin)?-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst||zenpower3-dkms-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst,ryzenadj-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst|chaotic-aur,chaotic-cdn,cachyos,arch-extra,aur,github|hidden
easyeffects|EasyEffects Studio Audio DSP & JackHack96 Presets|audio|easyeffects-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||lsp-plugins-lv2-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,calf-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,mda\.lv2-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,zam-plugins-lv2-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,zita-convolver-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,rnnoise-[0-9a-zA-Z_\.:-]*\.pkg\.tar\.zst,libbs2b-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,soundtouch-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libebur128-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,webrtc-audio-processing-[12]-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst,lilv-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,serd-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,sord-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,sratom-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,qt6-graphs-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,onetbb-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libmysofa-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,zix-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|arch-extra,cachyos
pear-desktop|Pear Desktop (YouTube Music with Custom Plugins)|audio|pear-desktop-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||electron42-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libjpeg-turbo-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|chaotic-aur,chaotic-cdn,arch-extra
audacity|Audacity (Digital Audio Editor & Recording Studio)|audio|audacity-(?:[0-9]+%3A)?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||suil-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,lilv-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,serd-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,sord-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,sratom-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,zix-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,portsmf-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,portaudio-(?:[0-9]+%3A)?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,portmidi-(?:[0-9]+%3A)?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libsbsms-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,vamp-plugin-sdk-(?:[0-9]+%3A)?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,soundtouch-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,twolame-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libid3tag-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libsoxr-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libmspack-(?:[0-9]+%3A)?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,wxwidgets-gtk3-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,wxwidgets-common-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libjpeg-turbo-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|arch-extra,cachyos-extra-v3,cachyos
yabridge|Yabridge (+ yabridgectl VST2/VST3 Plugin Bridge)|audio|yabridge-(?:bin-)?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||yabridgectl-(?:bin-)?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|cachyos,arch-extra,chaotic-aur
spotify|Spotify Launcher (Official Native Client Bootstrap)|audio|spotify-launcher-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||sequoia-sqv-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libayatana-appindicator-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libayatana-indicator-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,ayatana-ido-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libcurl-gnutls-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|arch-extra,cachyos,arch-core
inkscape|Inkscape (Professional Vector Graphics Editor)|creative|inkscape-(?:[0-9]+%3A)?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||lib2geom-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,double-conversion-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,graphicsmagick-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libcdr-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,poppler-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libvisio-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libwpg-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,librevenge-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|cachyos-extra-v3,arch-extra,cachyos
darktable|Darktable (Advanced RAW Photo Workflow & Editor)|creative|darktable-(?:[0-9]+(?:%3A|:))?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||libavif-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libheif-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libde265-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libyuv-(?:r)?[0-9a-zA-Z_\.\+-]*\.pkg\.tar\.zst,rav1e-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,svt-av1-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,openh264-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,pugixml-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,colord-gtk-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,osm-gps-map-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,gmic-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,flickcurl-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|cachyos-extra-v3,arch-extra,cachyos
dvcp-aac|DaVinci Resolve AAC Audio Bridge (GloriousEggroll Native AAC Fix)|creative|dvcp-aac-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst|||github,gloriouseggroll
bambu-studio|Bambu Studio (High-Speed 3D Slicer for Bambu Lab)|creative|BambuStudio_ubuntu24\.04-v[0-9][0-9.]*-[0-9]+\.AppImage||webkit2gtk-4\.1-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libsoup3-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libavif-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libyuv-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,rav1e-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,svt-av1-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|github,arch-extra,cachyos
blender|Blender (3D Creation & Animation Studio)|creative|blender-(?:[0-9]+(?:%3A|:))?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||onetbb-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,openimageio-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,opencolorio-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,embree-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,openimagedenoise-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,alembic-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,openvdb-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|cachyos-extra-v3,arch-extra,cachyos
freecad|FreeCAD (Parametric Open-Source 3D CAD Modeler)|creative|freecad-(?:[0-9]+(?:%3A|:))?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||opencascade-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,med-file-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,coin-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|cachyos-extra-v4,cachyos-extra-v3,arch-extra,cachyos
plasticity|Plasticity (3D CAD for Concept Artists & Industrial Design)|creative|plasticity-bin-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst|||chaotic-aur,chaotic-cdn,aur,cachyos|hidden
storyboarder|Storyboarder (Fast Visual Storytelling & Pre-Vis Animatics)|creative|storyboarder-bin-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst|||chaotic-aur,chaotic-cdn,aur,cachyos|hidden
syncthing|Syncthing (Continuous P2P File Synchronization)|tools|syncthing-(?:[0-9]+(?:%3A|:))?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||arch-extra,cachyos-extra-v3,cachyos
antigravity|Google Antigravity 2.0 (AI Agent Command Center & IDE)|tools|antigravity(?:-bin|-ide)?-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst|||chaotic-aur,chaotic-cdn,cachyos,aur
claude-desktop|Anthropic Claude Desktop (Official Linux Beta App)|tools|claude-desktop-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst|||aur,anthropic
claude-code|Anthropic Claude Code (Official Terminal AI Agent)|tools|claude-code-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst|||npm,anthropic
gemini-cli|Google Gemini CLI (Official Terminal AI Agent)|tools|gemini-cli-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst|||npm,google
gnome-disk-utility|GNOME Disk Utility (Storage Management & S.M.A.R.T. + libhandy)|tools|gnome-disk-utility-(?:[0-9]+(?:%3A|:))?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||libhandy-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst,libdvdread-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst|cachyos-extra-v4,cachyos-extra-v3,arch-extra,cachyos
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
brave|Brave Browser (Privacy Browser with AdBlock)|browser|brave-bin-(?:1(?:%3A|:))?[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||cachyos,chaotic-aur,chaotic-cdn
zen-browser|Zen Browser (High-Performance Gecko Browser)|browser|zen-browser-bin-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||cachyos,chaotic-aur,chaotic-cdn
opera|Opera Web Browser (Fast & Secure with Built-In Free VPN)|browser|opera-[0-9a-zA-Z_\.:-]*\.pkg\.tar\.zst|||chaotic-aur,chaotic-cdn,cachyos|hidden
sbctl|sbctl (Secure Boot Key Manager & Signer)|bootloader|sbctl-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||arch-extra,cachyos
limine|Limine Bootloader (>= 12.x EFI & Tools)|bootloader|limine-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||cachyos
limine-entry-tool|Limine Entry Tool (Config & Enrollment Generator)|bootloader|limine-entry-tool-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||cachyos
limine-snapper-sync|Limine Snapper Sync (Btrfs Snapshot Integrator)|bootloader|limine-snapper-sync-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||cachyos
hyprland-noctalia|Hyprland Mac-like Desktop Suite (Noctalia Shell, Portals & Display Tools)|desktop|hyprland-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||noctalia-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,xdg-desktop-portal-hyprland-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,hyprlock-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,hypridle-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,hyprpaper-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,hyprpicker-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,hyprland-guiutils-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,aquamarine-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,hyprlang-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,hyprcursor-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,hyprgraphics-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,hyprutils-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,hyprpolkitagent-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,hyprwire-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,hyprtoolkit-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,sdbus-cpp-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,tomlplusplus-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,muparser-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,re2-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,md4c-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,lua-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libical-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,ddcui-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,wlr-randr-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,nwg-displays-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,python-i3ipc-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libjpeg-turbo-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|cachyos-extra-v3,cachyos-v3,cachyos,arch-extra,chaotic-aur
hyprland-core|Hyprland Minimal Core Compositor (+ Wayland Portals, Lock & Display Tools)|desktop|hyprland-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst||xdg-desktop-portal-hyprland-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,hyprlock-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,hypridle-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,hyprpaper-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,hyprpicker-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,hyprland-guiutils-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,aquamarine-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,hyprlang-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,hyprcursor-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,hyprgraphics-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,hyprutils-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,hyprpolkitagent-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,hyprwire-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,hyprtoolkit-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,sdbus-cpp-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,tomlplusplus-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,muparser-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,re2-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,lua-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,ddcui-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,wlr-randr-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,nwg-displays-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,python-i3ipc-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst,libjpeg-turbo-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|cachyos-extra-v3,cachyos-v3,cachyos,arch-extra
hyprpicker|Hyprpicker (Wayland Eyedropper & Color Picker)|desktop|hyprpicker-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||cachyos-extra-v3,cachyos-v3,cachyos,arch-extra
hyprmod|HyprMod (GTK4/Libadwaita Hyprland Visual Settings & Rules Editor)|desktop||||aur,github
mactahoe-icons|Mac Tahoe Icon Theme (27 macOS Tahoe Variants for KDE/GTK)|ricing||||aur,github
mactahoe-cursors|Mac Tahoe Cursor Theme (macOS Tahoe Cursors for X11 & Wayland)|ricing||||aur,github
whitesur-icons|WhiteSur Icon Theme (macOS Big Sur & Sonoma Icon Suite)|ricing||||aur,github
whitesur-cursors|WhiteSur Cursor Theme (macOS Cursors with Animated Spinners)|ricing||||aur,github
CATALOG_EOF
}

# --- [ HELPER FUNCTIONS ] ---
# 6A-176: folder that holds slacky_vendor_fetch.py (next to gnomes_pacman.py); empty when it is missing, and then the vendor
# builds stop instead of downloading without a check.
_slacky_vendor_fetch_dir() {
    local d
    for d in "${GNOMES_PY:+$(dirname "${GNOMES_PY}")}" "${APP_DIR:-}" "${SCRIPT_DIR:-}/../lib" /usr/share/slacky-update/lib /usr/local/lib/slacky-update; do
        [ -n "${d}" ] && [ -f "${d}/slacky_vendor_fetch.py" ] && { printf '%s' "${d}"; return 0; }
    done
    return 0
}

# 6A-163..170, 6A-178: catalog ids whose upstream package does not exist in any repo this tool reads (checked 2026-10-14: no
# rtl88x2bu / rtl8812au in chaotic-aur, CachyOS or Arch; 2026-10-15: no opera in any of its repos; volt-gui, plasticity and storyboarder are AUR only, 6A-190). They carry the "hidden" catalog flag; this gives the plain reason.
gaming_pkg_unavailable_reason() {
    case "$1" in
        rtl88x2bu|rtl8812au)
            echo "There is no ready-made package for this Wi-Fi driver in the sources this tool uses, so it cannot be installed here."
            ;;
        opera)
            # 6A-178: no repository this tool reads carries an Opera package (checked 2026-10-15)
            echo "Opera is not offered here, because none of the sources this tool uses carries a package for it."
            ;;
        volt-gui|plasticity|storyboarder)
            # 6A-190: these three exist only in the Arch user repository (AUR) and have no signed download this tool could check
            # (checked 2026-10-15), so the rows carry the "hidden" catalog flag. A source may be added later: then remove
            # "hidden" from the catalog row and this case.
            case "$1" in
                volt-gui) echo "Volt GUI is not offered here, because its only source has no signed download that this tool can check." ;;
                plasticity) echo "Plasticity is not offered here, because its only source has no signed download that this tool can check." ;;
                storyboarder) echo "Storyboarder is not offered here, because its only source has no signed download that this tool can check." ;;
            esac
            ;;
    esac
}

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
        lact|openrgb|solaar|openghub|coolercontrol|asusctl|spacenav|volt-gui|\
        zenpower3|v4l2loopback|rtl8821cu|rtl88x2bu|rtl8812au|broadcom-wl|r8125|\
        easyeffects|pear-desktop|audacity|spotify|yabridge|\
        inkscape|darktable|dvcp-aac|bambu-studio|blender|freecad|plasticity|storyboarder|\
        syncthing|antigravity|claude-desktop|claude-code|gemini-cli|gnome-disk-utility|\
        obs-studio|obs-vkcapture|obs-move-transition|obs-source-record|\
        obs-pipewire-audio-capture|obs-advanced-scene-switcher|obs-multi-rtmp|\
        obs-composite-blur|obs-teleport|discord|vesktop|sunshine|\
        google-chrome|microsoft-edge|brave|zen-browser|opera|sbctl|limine|limine-entry-tool|limine-snapper-sync|\
        hyprland-noctalia|hyprland-core|hyprmod|\
        mactahoe-icons|mactahoe-cursors|whitesur-icons|whitesur-cursors)
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
            canon_name = p_name.lower()
            for sfx in ("-bin", "-git", "-manager", "-launcher", "-desktop", "-appimage"):
                if canon_name.endswith(sfx):
                    canon_name = canon_name[:-len(sfx)]
                    break
            if canon_name not in installed_pkgs or p_ver > installed_pkgs[canon_name]:
                installed_pkgs[canon_name] = p_ver

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
    "openghub": ["openghub", "/usr/bin/openghub"],
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
    "dvcp-aac": ["/opt/resolve/IOPlugins/aac_decoder_probe.dvcp.bundle", "/opt/resolve/IOPlugins/aac_fdk_plugin.dvcp.bundle"],
    "syncthing": ["syncthing"],
    "antigravity": ["antigravity", "/usr/bin/antigravity", "/usr/bin/agy", "/opt/antigravity/antigravity", "/opt/Antigravity/antigravity"],
    "claude-desktop": ["claude-desktop", "/usr/bin/claude-desktop", "/usr/lib/claude-desktop/claude-desktop", "/opt/claude-desktop/claude-desktop"],
    "claude-code": ["claude-code", "/usr/bin/claude-code", "/opt/claude-code/claude-code", "/opt/claude-code/claude"],
    "gemini-cli": ["gemini-cli", "/usr/bin/gemini-cli", "/usr/bin/gemini", "/opt/gemini-cli/bundle/gemini.js"],
    "google-chrome": ["google-chrome", "google-chrome-stable"],
    "microsoft-edge": ["microsoft-edge", "microsoft-edge-stable"],
    "brave": ["brave", "brave-browser"],
    "zen-browser": ["zen-browser", "zen"],
    "opera": ["opera", "/usr/bin/opera", "/usr/lib64/opera/opera", "/usr/lib/opera/opera"],
    "gnome-disk-utility": ["gnome-disks", "/usr/bin/gnome-disks"],
    "spacenav": ["spacenavd", "spnavcfg", "/usr/bin/spacenavd"],
    "volt-gui": ["volt-gui", "/usr/bin/volt-gui", "/opt/volt-gui/volt-gui", "/opt/volt-gui/volt-gui.py"],
    "bambu-studio": ["bambu-studio", "/usr/bin/bambu-studio", "/opt/bambu-studio/bin/bambu-studio", "/usr/bin/BambuStudio"],
    "blender": ["blender", "/usr/bin/blender", "/opt/blender/blender"],
    "freecad": ["freecad", "FreeCAD", "/usr/bin/freecad", "/usr/bin/FreeCAD", "/usr/lib64/freecad/bin/FreeCAD"],
    "plasticity": ["plasticity", "/usr/bin/plasticity", "/opt/plasticity/plasticity", "/opt/Plasticity/plasticity"],
    "storyboarder": ["storyboarder", "/usr/bin/storyboarder", "/opt/storyboarder/storyboarder", "/opt/Storyboarder/storyboarder"],
    "sbctl": ["sbctl"],
    "hyprland-noctalia": ["hyprland", "noctalia", "/usr/bin/Hyprland", "noctalia-shell"],
    "hyprland-core": ["hyprland", "/usr/bin/Hyprland"],
    "hyprmod": ["hyprmod", "/usr/bin/hyprmod"],
    "mactahoe-icons": ["/usr/share/icons/MacTahoe", "/usr/share/icons/MacTahoe-dark"],
    "mactahoe-cursors": ["/usr/share/icons/MacTahoe-cursors", "/usr/share/icons/MacTahoe-dark-cursors"],
    "whitesur-icons": ["/usr/share/icons/WhiteSur", "/usr/share/icons/WhiteSur-dark"],
    "whitesur-cursors": ["/usr/share/icons/WhiteSur-cursors", "/usr/share/icons/WhiteSur-dark-cursors"]
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
    "desktop": "Desktop Environments & Wayland Shells",
    "ricing": "Ricing & Desktop Customization (Icons & Cursors)",
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
    "desktop": "preferences-desktop-display",
    "ricing": "preferences-desktop-theme",
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
    "hyprland-noctalia": "Curated Mac-like Wayland desktop suite powered by Noctalia Shell (topbar, dock, launcher, control center) and Hyprland.",
    "hyprland-core": "Minimalist Hyprland Wayland compositor with core portals, lock daemons, and Slacky environment wrapper.",
    "hyprmod": "Native GTK4/Libadwaita visual settings editor for Hyprland (monitors, animations, keybindings, rules, live preview, modular Lua config support).",
    "mactahoe-icons": "Complete macOS Tahoe style vector icon theme for KDE Plasma, XFCE, and GTK desktops (27 variants).",
    "mactahoe-cursors": "macOS Tahoe cursor theme for X11 and Wayland desktops (light and dark variants).",
    "whitesur-icons": "macOS Big Sur, Monterey and Sonoma style icon theme with extensive application coverage.",
    "whitesur-cursors": "Classic macOS cursor theme with animated spinning beachball and dark/light variants.",
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
    "openghub": "Native Linux reimplementation of Logitech G HUB (HID++ 2.0, DPI, profiles, LIGHTSYNC, macros, force feedback wheels).",
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
    "dvcp-aac": "DaVinci Resolve Studio AAC audio bridge (GloriousEggroll) for native AAC playback and export.",
    "syncthing": "Continuous decentralized peer-to-peer file synchronization service.",
    "antigravity": "Google Antigravity 2.0 multi-agent coding and AI command center platform.",
    "claude-desktop": "Anthropic Claude Desktop Linux Beta app (AI Chat, Cowork & Claude Code).",
    "claude-code": "Anthropic Claude Code terminal AI agent (Autonomous coding and workflow tool).",
    "gemini-cli": "Google Gemini CLI terminal AI agent (Code generation, terminal agent & debugging).",
    "google-chrome": "Official Google Chrome web browser.",
    "microsoft-edge": "Official Microsoft Edge web browser.",
    "brave": "Privacy-focused web browser with built-in ad and tracker blocking.",
    "zen-browser": "High-performance Firefox Gecko-based web browser with split-views.",
    "opera": "Fast and secure web browser with built-in free VPN and messaging sidebars.",
    "gnome-disk-utility": "GNOME Disk Utility for storage management, partition editing & S.M.A.R.T. health.",
    "spacenav": "Complete 3Dconnexion SpaceMouse driver suite with daemon, library, and configuration GUI.",
    "volt-gui": "Graphical voltage and power management interface for AMD Ryzen curve optimization.",
    "bambu-studio": "High-speed 3D slicer for Bambu Lab printers with automated NVIDIA/WebKit acceleration.",
    "blender": "Professional 3D creation suite (modeling, animation, Cycles & EEVEE-Next rendering).",
    "freecad": "Parametric open-source 3D CAD modeler for engineering, mechanics & product design.",
    "plasticity": "Fast NURBS & CAD modeling software for concept artists and industrial designers.",
    "storyboarder": "Rapid visual storytelling and animatics creation tool for directors and artists.",
    "sbctl": "UEFI Secure Boot key manager, enrollment, and file signing utility."
}

def split_catalog_row(line):
    # 6A-250: split on "|" only outside (...) and [...] so regex alternations like (?:-bin|-git) stay inside their field.
    out, cur, depth, i = [], [], 0, 0
    while i < len(line):
        ch = line[i]
        if ch == "\\" and i + 1 < len(line):
            cur.append(line[i:i + 2]); i += 2; continue
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth = max(0, depth - 1)
        if ch == "|" and depth == 0:
            out.append("".join(cur)); cur = []
        else:
            cur.append(ch)
        i += 1
    out.append("".join(cur))
    return out

items = []
for line in raw_catalog.strip().split("\n"):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    parts = split_catalog_row(line)
    # 6A-250: a row has 7 fields (+ the optional 8th "hidden"). Anything else is a catalog bug: fail loudly.
    if len(parts) not in (7, 8) or (len(parts) == 8 and parts[7].strip() != "hidden"):
        sys.stderr.write("Catalog row is malformed (%d fields): %s\n" % (len(parts), parts[0]))
        sys.exit(1)
    pkg_id, name, cat = parts[0], parts[1], parts[2]
    if len(parts) == 8:
        continue
    
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

# 6A-250 self-check: every catalog row must parse into the right fields and no hidden row may be exported.
# Prints nothing and returns 0 when fine; prints one sentence on stderr and returns 1 otherwise (used by tests).
gaming_catalog_selfcheck() {
    local exported hidden_ids id
    if ! exported=$(export_gaming_catalog_json); then
        echo "Catalog self-check failed: a catalog row has the wrong number of fields." >&2
        return 1
    fi
    hidden_ids=$(get_gaming_catalog | grep -v '^#' | grep '|hidden$' | cut -d'|' -f1)
    for id in ${hidden_ids}; do
        if printf '%s' "${exported}" | grep -q "\"id\": \"${id}\""; then
            echo "Catalog self-check failed: hidden entry ${id} is listed." >&2
            return 1
        fi
    done
    printf '%s' "${exported}" | grep -q '"id": "openghub"' && {
        echo "Catalog self-check failed: openghub is hidden but listed." >&2
        return 1
    }
    return 0
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
            canon_name = p_name
            for sfx in ("-bin", "-git", "-manager", "-launcher", "-desktop", "-appimage"):
                if canon_name.endswith(sfx):
                    canon_name = canon_name[:-len(sfx)]
                    break
            if p_name == target_id or canon_name == target_id:
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
    "openghub": ["openghub", "/usr/bin/openghub"],
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
    "dvcp-aac": ["/opt/resolve/IOPlugins/aac_decoder_probe.dvcp.bundle", "/opt/resolve/IOPlugins/aac_fdk_plugin.dvcp.bundle"],
    "syncthing": ["syncthing"],
    "antigravity": ["antigravity", "/usr/bin/antigravity", "/usr/bin/agy", "/opt/antigravity/antigravity", "/opt/Antigravity/antigravity"],
    "claude-desktop": ["claude-desktop", "/usr/bin/claude-desktop", "/usr/bin/claude", "/usr/lib/claude-desktop/claude-desktop", "/opt/claude-desktop/claude-desktop"],
    "claude-code": ["claude-code", "/usr/bin/claude-code", "/opt/claude-code/claude-code", "/opt/claude-code/claude"],
    "gemini-cli": ["gemini-cli", "/usr/bin/gemini-cli", "/usr/bin/gemini", "/opt/gemini-cli/bundle/gemini.js"],
    "google-chrome": ["google-chrome", "google-chrome-stable"],
    "microsoft-edge": ["microsoft-edge", "microsoft-edge-stable"],
    "brave": ["brave", "brave-browser"],
    "zen-browser": ["zen-browser", "zen"],
    "opera": ["opera", "/usr/bin/opera", "/usr/lib64/opera/opera", "/usr/lib/opera/opera"],
    "gnome-disk-utility": ["gnome-disks", "/usr/bin/gnome-disks"],
    "spacenav": ["spacenavd", "spnavcfg", "/usr/bin/spacenavd"],
    "volt-gui": ["volt-gui", "/usr/bin/volt-gui", "/opt/volt-gui/volt-gui", "/opt/volt-gui/volt-gui.py"],
    "bambu-studio": ["bambu-studio", "/usr/bin/bambu-studio", "/opt/bambu-studio/bin/bambu-studio", "/usr/bin/BambuStudio"],
    "blender": ["blender", "/usr/bin/blender", "/opt/blender/blender"],
    "freecad": ["freecad", "FreeCAD", "/usr/bin/freecad", "/usr/bin/FreeCAD", "/usr/lib64/freecad/bin/FreeCAD"],
    "plasticity": ["plasticity", "/usr/bin/plasticity", "/opt/plasticity/plasticity", "/opt/Plasticity/plasticity"],
    "storyboarder": ["storyboarder", "/usr/bin/storyboarder", "/opt/storyboarder/storyboarder", "/opt/Storyboarder/storyboarder"],
    "sbctl": ["sbctl"],
    "hyprland-noctalia": ["hyprland", "noctalia", "/usr/bin/Hyprland", "noctalia-shell"],
    "hyprland-core": ["hyprland", "/usr/bin/Hyprland"],
    "hyprmod": ["hyprmod", "/usr/bin/hyprmod"]
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
    SLACKY_LIB_DIR="$(slacky_mirrors_lib_dir)" python3 - "${catalog_raw}" << 'PYFASTCHECK'
import sys, os, re, time, datetime, json, urllib.request, urllib.parse, hashlib, concurrent.futures

raw_catalog_lines = sys.argv[1].strip().splitlines()

def get_cache_dir():
    for d in ['/var/cache/slacky-update', os.path.expanduser('~/.cache/slacky-update')]:
        try:
            os.makedirs(d, exist_ok=True)
            test_f = os.path.join(d, '.write_test')
            with open(test_f, 'w') as f: f.write('1')
            os.remove(test_f)
            return d
        except Exception:
            continue
    # 6A-17: no fixed /tmp fallback (predictable path, lost on reboot); a private temp dir instead
    return __import__('tempfile').mkdtemp(prefix='slacky-update-cache.')

cache_dir = get_cache_dir()

# 6A-182: one shared helper (lib/slacky_mirrors.py) instead of three copies; the daily rule and the cache file
# (chaotic_fastest_mirror.json) are defined there. Without the module the geo mirror is used.
if os.environ.get('SLACKY_LIB_DIR'):
    sys.path.insert(0, os.environ['SLACKY_LIB_DIR'])
try:
    import slacky_mirrors as _slacky_mirrors
    def get_chaotic_fastest_mirror(cdir):
        return _slacky_mirrors.chaotic_fastest(cdir)
except Exception:
    def get_chaotic_fastest_mirror(cdir):
        return 'https://geo-mirror.chaotic.cx/chaotic-aur/x86_64/'

chaotic_fastest = get_chaotic_fastest_mirror(cache_dir)

def detect_cpu_tier() -> str:
    cpuinfo = "/proc/cpuinfo"
    if not os.path.exists(cpuinfo):
        return "generic"
    try:
        with open(cpuinfo, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
        if all(flag in content for flag in ["avx512f", "avx512bw", "avx512cd", "avx512dq", "avx512vl"]):
            if "AuthenticAMD" in content:
                return "znver4"
            return "v4"
        elif all(flag in content for flag in ["avx2", "fma", "bmi1", "bmi2"]):
            return "v3"
    except Exception:
        pass
    return "generic"

cpu_tier = detect_cpu_tier()

def expand_repos_for_tier(r_list, tier):
    res = []
    for r in r_list:
        if r in ("cachyos-extra-v3", "cachyos-extra"):
            if tier == "znver4":
                for cand in ["cachyos-extra-znver4", "cachyos-extra-v4", "cachyos-extra-v3", "cachyos-extra"]:
                    if cand not in res: res.append(cand)
            elif tier == "v4":
                for cand in ["cachyos-extra-v4", "cachyos-extra-v3", "cachyos-extra"]:
                    if cand not in res: res.append(cand)
            elif tier == "v3":
                for cand in ["cachyos-extra-v3", "cachyos-extra"]:
                    if cand not in res: res.append(cand)
            else:
                if "cachyos-extra" not in res: res.append("cachyos-extra")
        elif r in ("cachyos-v3", "cachyos"):
            if tier == "znver4":
                for cand in ["cachyos-znver4", "cachyos-v4", "cachyos-v3", "cachyos"]:
                    if cand not in res: res.append(cand)
            elif tier == "v4":
                for cand in ["cachyos-v4", "cachyos-v3", "cachyos"]:
                    if cand not in res: res.append(cand)
            elif tier == "v3":
                for cand in ["cachyos-v3", "cachyos"]:
                    if cand not in res: res.append(cand)
            else:
                if "cachyos" not in res: res.append("cachyos")
        else:
            if r not in res: res.append(r)
    return res

c_base = "https://mirror.cachyos.org/repo"
repos = {
    "cachyos": f"{c_base}/x86_64/cachyos/",
    "cachyos-extra": f"{c_base}/x86_64/cachyos-extra/",
    "cachyos-v3": f"{c_base}/x86_64_v3/cachyos-v3/",
    "cachyos-extra-v3": f"{c_base}/x86_64_v3/cachyos-extra-v3/",
    "cachyos-v4": f"{c_base}/x86_64_v4/cachyos-v4/",
    "cachyos-extra-v4": f"{c_base}/x86_64_v4/cachyos-extra-v4/",
    "cachyos-znver4": f"{c_base}/x86_64_v4/cachyos-znver4/",
    "cachyos-extra-znver4": f"{c_base}/x86_64_v4/cachyos-extra-znver4/",
    "chaotic-aur": chaotic_fastest,
    "chaotic-cdn": chaotic_fastest,
    "arch-core": "https://geo.mirror.pkgbuild.com/core/os/x86_64/",
    "arch-extra": "https://geo.mirror.pkgbuild.com/extra/os/x86_64/",
    "arch-multilib": "https://geo.mirror.pkgbuild.com/multilib/os/x86_64/"
}

if cpu_tier == "generic":
    repos["cachyos-v3"] = repos["cachyos"]
    repos["cachyos-extra-v3"] = repos["cachyos-extra"]
    repos["cachyos-v4"] = repos["cachyos"]
    repos["cachyos-extra-v4"] = repos["cachyos-extra"]
    repos["cachyos-znver4"] = repos["cachyos"]
    repos["cachyos-extra-znver4"] = repos["cachyos-extra"]

catalog = {}
for line in raw_catalog_lines:
    if not line.strip() or line.strip().startswith('#'):
        continue
    # 6A-250: the last field is "hidden" or the repo list; regexes may contain "|", so only the tail is trusted
    if line.rstrip().endswith("|hidden"):
        continue
    left_parts = line.split("|", 3)
    if len(left_parts) >= 4:
        pid, name, cat, remainder = left_parts
        right_parts = remainder.rsplit("|", 3)
        if len(right_parts) == 4:
            main_pat, l32_pat, ext_pat, repos_str = right_parts
            r_list = [r.strip() for r in repos_str.split(",") if r.strip()]
            href_pat = rf'href=[\'\"]?(?:\./)?({main_pat})[\'\"]?' if main_pat else None
            l32_href_pat = rf'href=[\'\"]?(?:\./)?({l32_pat})[\'\"]?' if l32_pat else None
            catalog[pid] = (name, href_pat, l32_href_pat, r_list)

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
        headers = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64)"}
        if os.path.exists(cache_file):
            try:
                import email.utils
                mtime = os.path.getmtime(cache_file)
                if mtime > 0:
                    headers["If-Modified-Since"] = email.utils.formatdate(mtime, usegmt=True)
            except Exception:
                pass
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=5) as resp:
            content = resp.read().decode("utf-8", errors="ignore")
            try:
                with open(cache_file, 'w', encoding='utf-8', errors='ignore') as f:
                    f.write(content)
            except Exception:
                pass
            return content
    except urllib.error.HTTPError as he:
        if he.code == 304 and os.path.exists(cache_file):
            try:
                os.utime(cache_file, (now, now))
                with open(cache_file, 'r', encoding='utf-8', errors='ignore') as f:
                    return f.read()
            except Exception:
                pass
        return ""
    except Exception:
        if os.path.exists(cache_file):
            try:
                with open(cache_file, 'r', encoding='utf-8', errors='ignore') as f:
                    return f.read()
            except Exception:
                pass
        return ""

# 6A-322: the Arch package name differs from the catalog id for these (the JSON lookup answered 404 for the id)
ARCH_API_NAMES = {"spotify": "spotify-launcher", "v4l2loopback": "v4l2loopback-dkms"}
ARCH_API_ARCH = {"v4l2loopback": "any"}   # a DKMS source package is arch=any in the Arch API

def clean_pkg_version(pid, raw_v):
    v = urllib.parse.unquote(str(raw_v))
    v = re.sub(r'\.pkg\.tar\.(?:zst|xz|gz)$', '', v)
    v = re.sub(r'-(?:x86_64(?:_v[0-9]+)?|noarch|i[3-6]86|any|aarch64)(?:-[0-9a-zA-Z_]+)?$', '', v)
    v = re.sub(r'-[0-9]+(?:\.[0-9]+)?$', '', v)
    if pid:
        pid_clean = pid.replace("-", "")
        v = re.sub(rf'^(?:underpants-|cachyos-gnome-)?(?:{re.escape(pid)}|{re.escape(pid_clean)})(?:-bin|-git|-manager|-launcher|-rules|-udev)?-', '', v, flags=re.IGNORECASE)
    v = re.sub(r'^[0-9]+(?:%3A|:|_)', '', v)
    v = re.sub(r'^[a-zA-Z0-9_\-+]+?-([0-9])', r'\1', v)
    v = re.sub(r'^[0-9]+(?:%3A|:|_)', '', v)
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
    # 6A-153: only packages the curated suite built itself (_slacky) are curated; a _gnomes app belongs to gnomes,
    # an SBo or stock package to its own updater (was: discord/lutris/... reported twice and rebuilt over gnomes)
    if not re.sub(r'\.(t[xg]z|tlz)$', '', pkg).endswith('_slacky'):
        continue
    name, ver = parse_installed_pkg(pkg)
    if ver == 'NONE':
        continue
    clean_name = re.sub(r'^(underpants|cachyos-gnome|cachyos-gnome-gnome)-', '', name)
    for sfx in ('-bin', '-git', '-manager', '-launcher', '-desktop', '-appimage'):
        if clean_name.endswith(sfx):
            clean_name = clean_name[:-len(sfx)]
            break
    for pid in catalog:
        if clean_name == pid or name == pid:
            if pid not in detected_installed or is_strictly_greater(ver, detected_installed[pid]):
                detected_installed[pid] = ver

needed_repos = set()
for pid in detected_installed:
    if pid in catalog:
        _, pat, l32_pat, r_list = catalog[pid]
        if pat:
            for rk in expand_repos_for_tier(r_list, cpu_tier):
                if rk in ("arch-extra", "arch-core", "arch-multilib"):
                    continue
                u = repos.get(rk)
                if u:
                    needed_repos.add(u)
        if l32_pat:
            for rk in expand_repos_for_tier(["cachyos-extra-v3", "cachyos-v3", "arch-multilib"], cpu_tier):
                u = repos.get(rk)
                if u:
                    needed_repos.add(u)

needed_repos_list = list(needed_repos)[:10]
with concurrent.futures.ThreadPoolExecutor(max_workers=min(max(len(needed_repos_list), 1), 8)) as ex:
    repo_contents = dict(zip(needed_repos_list, ex.map(lambda u: fetch_url_cached(u, cache_dir), needed_repos_list)))

# WP-2: a version the user rolled back from (gnomes --rollback) is not offered again; a newer release is
try:
    with open('/var/cache/slacky-update/gnomes/rollback-holds.json') as _fh:
        rollback_holds = {k: v for k, v in json.load(_fh).items() if isinstance(v, dict)}
except Exception:
    rollback_holds = {}

def rolled_back(pid, best_ver):
    for b in (f"underpants-{pid}", f"cachyos-gnome-{pid}", pid):
        h = rollback_holds.get(b)
        if h and not is_strictly_greater(best_ver, h.get("skip_version", "")):
            return True
    return False

# 6A-242: the six OBS plugins are DEPLOYED from GitHub releases (github_and_direct_pkgs in the resolver below), so the update scan must
# ask the same source: newest non-prerelease, non-draft release that has an asset matching the same pattern (keep the patterns identical
# to the resolver table). One https call to api.github.com per repo, 5 s timeout, 4 MiB cap, cached 30 min in the same file the resolver
# uses (unauthenticated limit is 60/h; 6 repos at most every 30 min is 12/h). Any failure = no candidate = no update listed, silent.
GITHUB_OBS_SCAN = {
    "obs-move-transition": ("exeldro/obs-move-transition", r"move-transition-([0-9\.]+)-x86_64-linux-gnu\.deb"),
    "obs-source-record": ("exeldro/obs-source-record", r"source-record-([0-9\.]+)-ubuntu.*\.tar\.gz"),
    "obs-advanced-scene-switcher": ("WarmUpTill/SceneSwitcher", r"advanced-scene-switcher-([0-9\.]+)-x86_64-ubuntu.*-linux-gnu\.deb"),
    "obs-multi-rtmp": ("sorayuki/obs-multi-rtmp", r"obs-multi-rtmp-([0-9\.]+)-x86_64-linux-gnu-ubuntu.*\.deb"),
    "obs-composite-blur": ("FiniteSingularity/obs-composite-blur", r"obs-composite-blur-([0-9\.]+)-(?:x86_64-linux-gnu\.deb|ubuntu.*\.zip)"),
    "obs-teleport": ("fzwoch/obs-teleport", r"Teleport-([0-9\.]+)-Linux-x86_64\.zip"),
}
GH_SCAN_CAP = 4 << 20

def gh_releases_cached(repo, cdir, ttl=1800):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo or ""):
        return []
    url = f"https://api.github.com/repos/{repo}/releases"
    cache_file = os.path.join(cdir, f"repo_idx_{hashlib.sha256(url.encode('utf-8')).hexdigest()[:16]}.html")

    def load_cache():
        try:
            if os.path.getsize(cache_file) > GH_SCAN_CAP:
                return None
            with open(cache_file, "r", encoding="utf-8", errors="ignore") as f:
                data = json.loads(f.read())
            return data if isinstance(data, list) else None
        except Exception:
            return None

    try:
        if (time.time() - os.path.getmtime(cache_file)) < ttl:
            data = load_cache()
            if data is not None:
                return data
    except Exception:
        pass
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64)", "Accept": "application/vnd.github+json"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            if not resp.geturl().startswith("https://api.github.com/"):
                raise ValueError("redirected away from api.github.com")
            raw = resp.read(GH_SCAN_CAP + 1)
        if len(raw) > GH_SCAN_CAP:
            raise ValueError("answer too large")
        data = json.loads(raw.decode("utf-8", errors="ignore"))
        if not isinstance(data, list):
            raise ValueError("not a release list")
        try:
            tmp = cache_file + f".{os.getpid()}.tmp"
            with open(tmp, "wb") as f:
                f.write(raw)
            os.replace(tmp, cache_file)
        except Exception:
            pass
        return data
    except Exception:
        stale = load_cache()
        return stale if stale is not None else []

def github_obs_version(pid):
    repo, asset_re = GITHUB_OBS_SCAN[pid]
    for rel in gh_releases_cached(repo, cache_dir):
        if not isinstance(rel, dict) or rel.get("prerelease") or rel.get("draft"):
            continue
        tag = str(rel.get("tag_name", "")).lstrip("v")
        for asset in rel.get("assets") or []:
            m = re.search(asset_re, str(asset.get("name", "")) if isinstance(asset, dict) else "")
            if m:
                ver = m.group(1) if m.groups() else tag   # the same way the deploy takes it
                return ver if re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", ver or "") else None
    return None

# 6A-296 (F3): the boot loader (limine) and sbctl are held at the installed MAJOR version: an update inside the same major is offered,
# a higher major is never installed automatically (a new Limine may change its config or command line and leave a menu that does
# not boot). Nothing is held when the package is not installed yet.
MAJOR_HOLD_PIDS = ("limine", "sbctl")
def version_major(v):
    m = re.match(r'[0-9]+', clean_pkg_version('', str(v)))
    return int(m.group(0)) if m else None

def installed_major(pid):
    best = None
    try:
        for e in os.listdir("/var/log/packages"):
            m = re.match(re.escape(pid) + r'-([0-9][^-]*)-(?:x86_64|noarch|i[3-6]86)-[^-]+$', e)
            if m:
                mj = version_major(m.group(1))
                if mj is not None and (best is None or mj > best):
                    best = mj
    except OSError:
        pass
    return best

def major_held(pid, ver, inst_major=None):
    if pid not in MAJOR_HOLD_PIDS:
        return False
    im = inst_major if inst_major is not None else installed_major(pid)
    if im is None:
        return False
    vm = version_major(ver)
    return vm is None or vm > im

MAJOR_HELD = []
# 6A-306 (V4): ids for which no upstream source answered at all (offline, mirror down): these are "could not check", never "up to date"
LOOKED = set()

def check_single_package(pid, cur_ver):
    if pid not in catalog:
        return None
    name, pat, l32_pat, r_list = catalog[pid]
    if pid == "steam-devices":
        return None
    main_candidates = []

    # 6A-65: hyprmod is built from a locked, checksummed source set (HYPRMOD_LOCK in the build recipe); only a new lock in a
    # new slacky-update build offers an update, never a moving AUR/GitHub version
    if pid == "hyprmod":
        LOOKED.add(pid)
        main_candidates.append("0.4.0")
    # 6A-192: the official Bambu Lab release (newest non-prerelease with the Ubuntu 24.04 AppImage); the AUR source package is not it
    elif pid == "bambu-studio":
        try:
            raw_json = fetch_url_cached("https://api.github.com/repos/bambulab/BambuStudio/releases", cache_dir, ttl=1800)
            if raw_json:
                LOOKED.add(pid)
            for rel in (json.loads(raw_json) if raw_json else []):
                if rel.get("prerelease") or rel.get("draft"):
                    continue
                if any(re.search(r"^BambuStudio_(?:ubuntu24\.04|ubu24)-v[0-9][0-9.]*-[0-9]+\.AppImage$", a.get("name", "")) for a in rel.get("assets", [])):
                    cv = clean_pkg_version(pid, rel.get("tag_name", "").lstrip("v"))
                    if cv:
                        main_candidates.append(cv)
                    break
        except Exception:
            pass
    # 6A-242: the six GitHub-deployed OBS plugins are checked against GitHub releases, not the Arch/CachyOS repos
    elif pid in GITHUB_OBS_SCAN:
        gv = github_obs_version(pid)
        if gv or gh_releases_cached(GITHUB_OBS_SCAN[pid][0], cache_dir):
            LOOKED.add(pid)
        if gv:
            cv = clean_pkg_version(pid, gv)
            if cv:
                main_candidates.append(cv)
    # 6A-193: the four themes are built from pinned commit archives (same pins as the Rust engine); no moving AUR version
    elif pid in ("mactahoe-icons", "mactahoe-cursors", "whitesur-icons", "whitesur-cursors"):
        LOOKED.add(pid)
        main_candidates.append({"mactahoe-icons": "2026.09.10.r0.839848b9", "mactahoe-cursors": "2026.09.10.r0.839848b9",
                                "whitesur-icons": "2026.09.10", "whitesur-cursors": "2025.04.05.r0.e190baf6"}[pid])
    # 6A-306 (V4): the same live sources the resolver uses (npm registry, GitHub release); no fixed version number anywhere
    elif pid in ("claude-code", "gemini-cli", "dvcp-aac"):
        try:
            if pid == "dvcp-aac":
                raw_json = fetch_url_cached("https://api.github.com/repos/GloriousEggroll/dvcp-aac/releases/latest", cache_dir, ttl=1800)
                live_v = (json.loads(raw_json).get("tag_name") or "").lstrip("v") if raw_json else ""
            else:
                npm_name = "@anthropic-ai/claude-code-linux-x64" if pid == "claude-code" else "@google/gemini-cli"
                raw_json = fetch_url_cached(f"https://registry.npmjs.org/{npm_name}/latest", cache_dir, ttl=1800)
                live_v = (json.loads(raw_json).get("version") or "") if raw_json else ""
            if live_v:
                LOOKED.add(pid)
                cv = clean_pkg_version(pid, live_v)
                if cv:
                    main_candidates.append(cv)
        except Exception:
            pass
    # Fast AUR RPC API check for AUR / GitHub packages
    elif any(r in ("aur", "aur-rpc", "github") for r in r_list):
        try:
            aur_map = {
                "openghub": "openghub-bin",
                "mactahoe-icons": "mactahoe-icon-theme-git",
                "mactahoe-cursors": "mactahoe-cursor-theme-git",
                "whitesur-icons": "whitesur-icon-theme",
                "whitesur-cursors": "whitesur-cursor-theme-git"
            }
            aur_id = aur_map.get(pid, pid)
            aur_url = f"https://aur.archlinux.org/rpc/v5/info?arg[]={aur_id}"
            raw_json = fetch_url_cached(aur_url, cache_dir, ttl=1800)
            if raw_json:
                LOOKED.add(pid)
                data = json.loads(raw_json)
                results = data.get("results", [])
                if results:
                    v = results[0].get("Version")
                    if v:
                        cv = clean_pkg_version(pid, v)
                        if cv:
                            main_candidates.append(cv)
        except Exception:
            pass

    # Fast Arch Linux JSON API check for Arch Extra / Multilib packages
    if any(r in ("arch-extra", "arch-core", "arch-multilib") for r in r_list):
        for repo_cand in ("extra", "multilib", "core"):
            try:
                api_url = f"https://archlinux.org/packages/{repo_cand}/{ARCH_API_ARCH.get(pid, 'x86_64')}/{ARCH_API_NAMES.get(pid, pid)}/json/"
                raw_json = fetch_url_cached(api_url, cache_dir, ttl=1800)
                if raw_json:
                    LOOKED.add(pid)
                    data = json.loads(raw_json)
                    v = data.get("pkgver")
                    if v:
                        cv = clean_pkg_version(pid, v)
                        if cv:
                            main_candidates.append(cv)
                            break
            except Exception:
                pass

    if pat:
        for rk in expand_repos_for_tier(r_list, cpu_tier):
            base_u = repos.get(rk, "")
            html = repo_contents.get(base_u, "")
            if not html:
                continue
            LOOKED.add(pid)
            try:
                matches = re.findall(pat, html)
            except Exception:
                matches = []
            if matches:
                for m in matches:
                    raw_pkg = m[0] if isinstance(m, tuple) else m
                    cv = clean_pkg_version(pid, raw_pkg)
                    if cv:
                        main_candidates.append(cv)

    if pid in MAJOR_HOLD_PIDS and main_candidates:
        _im = version_major(cur_ver)
        _kept = [c for c in main_candidates if not major_held(pid, c, _im)]
        if len(_kept) != len(main_candidates):
            MAJOR_HELD.append(f"{pid}|{name}|{cur_ver}|{max(main_candidates, key=parse_version_key)}")
        main_candidates = _kept

    # 6A-322: spacenavd is in no Arch / CachyOS / Chaotic list (the Rust app reads a signed Debian index for it, owner decision 2026-10-15);
    # an empty answer here is "could not check", never "up to date" (6A-298 / 6A-306 exit code)
    if pid == "spacenav" and not main_candidates:
        LOOKED.discard(pid)

    if not main_candidates:
        return None

    # Multilib Version Intersection: Packages with 32-bit components must have matching 32-bit versions
    if l32_pat:
        l32_candidates = []
        for l32_name in (f"lib32-{pid}", f"lib32-{pid.replace('-bin', '')}"):
            try:
                api_url = f"https://archlinux.org/packages/multilib/x86_64/{l32_name}/json/"
                raw_json = fetch_url_cached(api_url, cache_dir, ttl=1800)
                if raw_json:
                    data = json.loads(raw_json)
                    v = data.get("pkgver")
                    if v:
                        cv = clean_pkg_version(l32_name, v)
                        if cv:
                            l32_candidates.append(cv)
                            break
            except Exception:
                pass

        multilib_rkeys = expand_repos_for_tier(["cachyos-extra-v3", "cachyos-v3", "arch-multilib"], cpu_tier)
        for rk in multilib_rkeys:
            base_u = repos.get(rk, "")
            html = repo_contents.get(base_u, "")
            if not html:
                continue
            try:
                matches = re.findall(l32_pat, html)
            except Exception:
                matches = []
            if matches:
                for m in matches:
                    raw_pkg = m[0] if isinstance(m, tuple) else m
                    cv = clean_pkg_version(f"lib32-{pid}", raw_pkg)
                    if cv:
                        l32_candidates.append(cv)

        # Intersection: only accept versions present in BOTH 64-bit and 32-bit
        intersected = [v for v in set(main_candidates) if v in set(l32_candidates)]
        if not intersected:
            return None
        intersected.sort(key=parse_version_key)
        best_ver = intersected[-1]
        if is_strictly_greater(best_ver, cur_ver) and not rolled_back(pid, best_ver):
            return f"{pid}|{name}|{cur_ver}|{best_ver}"
        return None

    main_candidates.sort(key=parse_version_key)
    best_ver = main_candidates[-1]
    if is_strictly_greater(best_ver, cur_ver) and not rolled_back(pid, best_ver):
        return f"{pid}|{name}|{cur_ver}|{best_ver}"
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

# 6A-296 (F3): versions held back for a new major are written for the update step, which tells the user in one sentence
for _d in ("/var/cache/slacky-update", os.path.expanduser("~/.cache/slacky-update")):
    _hp = os.path.join(_d, "major_hold.txt")
    try:
        if MAJOR_HELD and _d == cache_dir:
            with open(_hp + ".tmp", "w") as _f:
                _f.write("\n".join(sorted(set(MAJOR_HELD))) + "\n")
            os.replace(_hp + ".tmp", _hp)
        elif os.path.exists(_hp):
            os.remove(_hp)
    except Exception:
        pass

# 6A-306 (V4): the list above is complete for everything that could be checked. Exit 3 = some installed items could not be
# checked (the caller keeps the list and records "could not check"); exit 1 = none of them could be checked.
_unchecked = [x for x in detected_installed if x in catalog and x != "steam-devices" and x not in LOOKED]
if _unchecked:
    sys.exit(1 if len(_unchecked) == len([x for x in detected_installed if x in catalog and x != "steam-devices"]) else 3)
PYFASTCHECK
}

resolve_cachyos_gaming_upstream_metadata() {
    local pkg_id="$1"
    
    SLACKY_LIB_DIR="$(slacky_mirrors_lib_dir)" python3 - "${pkg_id}" << 'PYRESOLVE'
import sys, os, re, time, datetime, json, urllib.request, urllib.parse, hashlib, concurrent.futures

pkg_id = sys.argv[1]

if pkg_id == "steam-devices":
    print("1.0.0.61 BUNDLED NONE NONE")
    sys.exit(0)

if pkg_id == "hyprmod":
    # 6A-65: locked version (must match HYPRMOD_LOCK in the build recipe)
    print("0.4.0 GITHUB_WHEELS NONE NONE")
    sys.exit(0)
if pkg_id == "antigravity":
    ver = None   # 6A-306 (V4): no made-up fallback version; a failed lookup is "could not check"
    try:
        aur_url = "https://aur.archlinux.org/rpc/v5/info?arg[]=antigravity"
        req = urllib.request.Request(aur_url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64)"})
        with urllib.request.urlopen(req, timeout=6) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            results = data.get("results", [])
            if results:
                ver = (results[0].get("Version") or "").split("-")[0] or ver
    except Exception:
        pass
    print(f"{ver} AUR_ANTIGRAVITY NONE NONE" if ver else "NONE NONE NONE NONE")
    sys.exit(0)

if pkg_id == "claude-desktop":
    ver = None
    try:
        # 6A-310 (V6): the newest version in Anthropic's own apt index (the file is checked against that index at build time)
        if os.environ.get('SLACKY_LIB_DIR'):
            sys.path.insert(0, os.environ['SLACKY_LIB_DIR'])
        import slacky_vendor_fetch as _vf
        ver = _vf.apt_latest_version("claude-desktop") or ver
    except Exception:
        pass
    print(f"{ver} DEB_CLAUDE_DESKTOP NONE NONE" if ver else "NONE NONE NONE NONE")
    sys.exit(0)

if pkg_id == "claude-code":
    ver = None
    try:
        npm_url = "https://registry.npmjs.org/@anthropic-ai/claude-code-linux-x64/latest"
        req = urllib.request.Request(npm_url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64)"})
        with urllib.request.urlopen(req, timeout=6) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            ver = data.get("version") or ver
    except Exception:
        pass
    print(f"{ver} NPM_CLAUDE_CODE NONE NONE" if ver else "NONE NONE NONE NONE")
    sys.exit(0)

if pkg_id == "gemini-cli":
    ver = None
    try:
        npm_url = "https://registry.npmjs.org/@google/gemini-cli/latest"
        req = urllib.request.Request(npm_url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64)"})
        with urllib.request.urlopen(req, timeout=6) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            ver = data.get("version") or ver
    except Exception:
        pass
    print(f"{ver} NPM_GEMINI_CLI NONE NONE" if ver else "NONE NONE NONE NONE")
    sys.exit(0)

if pkg_id == "dvcp-aac":
    ver = None
    try:
        gh_url = "https://api.github.com/repos/GloriousEggroll/dvcp-aac/releases/latest"
        req = urllib.request.Request(gh_url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64)"})
        with urllib.request.urlopen(req, timeout=6) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            ver = (data.get("tag_name") or "").lstrip("v") or ver
    except Exception:
        pass
    print(f"{ver} GITHUB_DVCP_AAC NONE NONE" if ver else "NONE NONE NONE NONE")
    sys.exit(0)

if pkg_id in ("mactahoe-icons", "mactahoe-cursors", "whitesur-icons", "whitesur-cursors"):
    # 6A-193: pinned commit archives (THEME_PINS in the build recipe, same pins as the Rust engine); only a new pin in a new
    # slacky-update build offers an update, never a moving AUR version
    ver = {"mactahoe-icons": "2026.09.10.r0.839848b9", "mactahoe-cursors": "2026.09.10.r0.839848b9",
           "whitesur-icons": "2026.09.10", "whitesur-cursors": "2025.04.05.r0.e190baf6"}[pkg_id]
    print(f"{ver} GITHUB_THEME NONE NONE")
    sys.exit(0)

def get_cache_dir():
    for d in ['/var/cache/slacky-update', os.path.expanduser('~/.cache/slacky-update')]:
        try:
            os.makedirs(d, exist_ok=True)
            test_f = os.path.join(d, '.write_test')
            with open(test_f, 'w') as f: f.write('1')
            os.remove(test_f)
            return d
        except Exception:
            continue
    # 6A-17: no fixed /tmp fallback (predictable path, lost on reboot); a private temp dir instead
    return __import__('tempfile').mkdtemp(prefix='slacky-update-cache.')

cache_dir = get_cache_dir()

# 6A-182: one shared helper (lib/slacky_mirrors.py) instead of three copies; the daily rule and the cache file
# (chaotic_fastest_mirror.json) are defined there. Without the module the geo mirror is used.
if os.environ.get('SLACKY_LIB_DIR'):
    sys.path.insert(0, os.environ['SLACKY_LIB_DIR'])
try:
    import slacky_mirrors as _slacky_mirrors
    def get_chaotic_fastest_mirror(cdir):
        return _slacky_mirrors.chaotic_fastest(cdir)
except Exception:
    def get_chaotic_fastest_mirror(cdir):
        return 'https://geo-mirror.chaotic.cx/chaotic-aur/x86_64/'

chaotic_fastest = get_chaotic_fastest_mirror(cache_dir)

def detect_cpu_tier() -> str:
    cpuinfo = "/proc/cpuinfo"
    if not os.path.exists(cpuinfo):
        return "generic"
    try:
        with open(cpuinfo, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
        if all(flag in content for flag in ["avx512f", "avx512bw", "avx512cd", "avx512dq", "avx512vl"]):
            if "AuthenticAMD" in content:
                return "znver4"
            return "v4"
        elif all(flag in content for flag in ["avx2", "fma", "bmi1", "bmi2"]):
            return "v3"
    except Exception:
        pass
    return "generic"

cpu_tier = detect_cpu_tier()

def expand_repos_for_tier(r_list, tier):
    res = []
    for r in r_list:
        if r in ("cachyos-extra-v3", "cachyos-extra"):
            if tier == "znver4":
                for cand in ["cachyos-extra-znver4", "cachyos-extra-v4", "cachyos-extra-v3", "cachyos-extra"]:
                    if cand not in res: res.append(cand)
            elif tier == "v4":
                for cand in ["cachyos-extra-v4", "cachyos-extra-v3", "cachyos-extra"]:
                    if cand not in res: res.append(cand)
            elif tier == "v3":
                for cand in ["cachyos-extra-v3", "cachyos-extra"]:
                    if cand not in res: res.append(cand)
            else:
                if "cachyos-extra" not in res: res.append("cachyos-extra")
        elif r in ("cachyos-v3", "cachyos"):
            if tier == "znver4":
                for cand in ["cachyos-znver4", "cachyos-v4", "cachyos-v3", "cachyos"]:
                    if cand not in res: res.append(cand)
            elif tier == "v4":
                for cand in ["cachyos-v4", "cachyos-v3", "cachyos"]:
                    if cand not in res: res.append(cand)
            elif tier == "v3":
                for cand in ["cachyos-v3", "cachyos"]:
                    if cand not in res: res.append(cand)
            else:
                if "cachyos" not in res: res.append("cachyos")
        else:
            if r not in res: res.append(r)
    return res

c_base = "https://mirror.cachyos.org/repo"
repos = {
    "cachyos": f"{c_base}/x86_64/cachyos/",
    "cachyos-extra": f"{c_base}/x86_64/cachyos-extra/",
    "cachyos-v3": f"{c_base}/x86_64_v3/cachyos-v3/",
    "cachyos-extra-v3": f"{c_base}/x86_64_v3/cachyos-extra-v3/",
    "cachyos-v4": f"{c_base}/x86_64_v4/cachyos-v4/",
    "cachyos-extra-v4": f"{c_base}/x86_64_v4/cachyos-extra-v4/",
    "cachyos-znver4": f"{c_base}/x86_64_v4/cachyos-znver4/",
    "cachyos-extra-znver4": f"{c_base}/x86_64_v4/cachyos-extra-znver4/",
    "chaotic-aur": chaotic_fastest,
    "chaotic-cdn": chaotic_fastest,
    "arch-core": "https://geo.mirror.pkgbuild.com/core/os/x86_64/",
    "arch-extra": "https://geo.mirror.pkgbuild.com/extra/os/x86_64/",
    "arch-multilib": "https://geo.mirror.pkgbuild.com/multilib/os/x86_64/"
}

if cpu_tier == "generic":
    repos["cachyos-v3"] = repos["cachyos"]
    repos["cachyos-extra-v3"] = repos["cachyos-extra"]
    repos["cachyos-v4"] = repos["cachyos"]
    repos["cachyos-extra-v4"] = repos["cachyos-extra"]
    repos["cachyos-znver4"] = repos["cachyos"]
    repos["cachyos-extra-znver4"] = repos["cachyos-extra"]

catalog = {
    "mangohud": (r'href=[\'\"]?(?:\./)?(mangohud-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', r'href=[\'\"]?(?:\./)?(lib32-mangohud-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', r'href=[\'\"]?(?:\./)?(glfw-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["cachyos-extra-v3", "arch-extra", "cachyos"], ["arch-multilib", "cachyos"]),
    "gamemode": (r'href=[\'\"]?(?:\./)?(gamemode-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', r'href=[\'\"]?(?:\./)?(lib32-gamemode-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, ["cachyos-extra-v3", "arch-extra", "cachyos"], ["arch-multilib", "cachyos"]),
    "goverlay": (r'href=[\'\"]?(?:\./)?(goverlay-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, r'href=[\'\"]?(?:\./)?(qt6pas-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["arch-extra", "cachyos"], []),
    "scx": (r'href=[\'\"]?(?:\./)?(scx-manager-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(scx-scheds(?:-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(scx-tools(?:-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["cachyos", "arch-extra"], []),
    "easyeffects": (r'href=[\'\"]?(?:\./)?(easyeffects-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(lsp-plugins-lv2-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(calf-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(mda\.lv2-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(zam-plugins-lv2-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(zita-convolver-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(rnnoise-(?:1%3A|1:)?([0-9a-zA-Z_\.:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libbs2b-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(soundtouch-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libebur128-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(webrtc-audio-processing-(?:2|1)-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(lilv-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(serd-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(sord-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(sratom-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(qt6-graphs-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(onetbb-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libmysofa-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(zix-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["arch-extra", "cachyos", "arch-core"], []),
    "pear-desktop": (r'href=[\'\"]?(?:\./)?(pear-desktop-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(electron42-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libjpeg-turbo-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["chaotic-aur", "chaotic-cdn", "arch-extra"], []),
    # 6A-189: no repository carries lib32-yabridge, so the 32-bit part is not required (same as the Rust app): the lib32 pattern is None
    "yabridge": (r'href=[\'\"]?(?:\./)?(yabridge-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, r'href=[\'\"]?(?:\./)?(yabridgectl-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["arch-extra", "cachyos", "chaotic-aur"], ["arch-multilib", "cachyos"]),
    "audacity": (r'href=[\'\"]?(?:\./)?(audacity-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(suil-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(lilv-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(serd-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(sord-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(sratom-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(zix-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(portsmf-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(portaudio-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(portmidi-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libsbsms-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(vamp-plugin-sdk-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(soundtouch-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(twolame-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libid3tag-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libsoxr-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libmspack-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(wxwidgets-gtk3-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(wxwidgets-common-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libjpeg-turbo-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["arch-extra", "cachyos-extra-v3", "cachyos", "arch-core"], []),
    "spotify": (r'href=[\'\"]?(?:\./)?(spotify(?:-launcher)?-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(sequoia-sqv-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libayatana-appindicator-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libayatana-indicator-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(ayatana-ido-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libcurl-gnutls-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["arch-extra", "cachyos-extra-v3", "cachyos", "arch-core"], []),
    "inkscape": (r'href=[\'\"]?(?:\./)?(inkscape-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(lib2geom-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(double-conversion-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(graphicsmagick-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libcdr-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(poppler-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libvisio-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libwpg-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(librevenge-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["cachyos-extra-v3", "arch-extra", "cachyos"], []),
    "darktable": (r'href=[\'\"]?(?:\./)?(darktable-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(libavif-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libheif-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libde265-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libyuv-((?:r[0-9]+|[0-9])[a-zA-Z0-9_\.\+%-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(rav1e-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(svt-av1-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(openh264-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(pugixml-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(colord-gtk-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(osm-gps-map-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(gmic-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(flickcurl-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["cachyos-extra-v3", "arch-extra", "cachyos"], []),
    "syncthing": (r'href=[\'\"]?(?:\./)?(syncthing-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-extra", "cachyos-extra-v3", "cachyos"], []),
    "antigravity": (r'href=[\'\"]?(?:\./)?(antigravity(?:-bin|-ide)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "chaotic-cdn", "cachyos", "arch-extra"], []),
    "ananicy": (r'href=[\'\"]?(?:\./)?(ananicy-cpp(?:-git)?-([0-9a-zA-Z_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(cachyos-ananicy-rules(?:-git)?-([0-9a-zA-Z_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libbpf-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["cachyos", "cachyos-extra-v3", "arch-core"], []),
    "gamescope": (r'href=[\'\"]?(?:\./)?(gamescope-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', r'href=[\'\"]?(?:\./)?(lib32-gamescope-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', r'href=[\'\"]?(?:\./)?(libavif-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["cachyos", "arch-extra"], ["cachyos", "arch-multilib"]),
    "heroic": (r'href=[\'\"]?(?:\./)?(heroic-games-launcher-bin-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos", "arch-extra"], []),
    "lutris": (r'href=[\'\"]?(?:\./)?(lutris(?:-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(webkit2gtk-4\.1-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libsoup3-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(python-moddb-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(python-pypresence-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(python-evdev-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(python-distro-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["arch-extra", "cachyos", "arch-core", "cachyos-extra-v3"], []),
    "faugus": (r'href=[\'\"]?(?:\./)?(faugus-launcher-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(python-vdf-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(icoextract-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(python-pefile-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["cachyos", "arch-extra"], []),
    "protonplus": (r'href=[\'\"]?(?:\./)?((?:proton-plus|protonplus)-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos", "arch-extra"], []),
    "steam": (r'href=[\'\"]?(?:\./)?(steam-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-multilib", "cachyos"], []),
    "steam-devices": (None, None, None, [], []),
    "retroarch": (r'href=[\'\"]?(?:\./)?(retroarch-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, r'href=[\'\"]?(?:\./)?(retroarch-assets-ozone-(?:[0-9]+%3A)?([0-9a-zA-Z_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["arch-extra", "cachyos"], []),
    "lact": (r'href=[\'\"]?(?:\./)?(lact-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-extra", "cachyos"], []),
    "openrgb": (r'href=[\'\"]?(?:\./)?(openrgb(?:-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos", "arch-extra"], []),
    "solaar": (r'href=[\'\"]?(?:\./)?(solaar-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(python-pyudev-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(python-typing_extensions-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(python-xlib-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["arch-extra", "cachyos-extra-v3", "cachyos"], []),
    "openghub": (r'href=[\'\"]?(?:\./)?(openghub(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(webkit2gtk-4\.1-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libsoup3-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libmanette-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["arch-extra", "cachyos", "chaotic-aur"], []),
    # 6A-192: the program is the official GitHub release AppImage (github_and_direct_pkgs below); these are its library parts
    "bambu-studio": (r'href=[\'\"]?(?:\./)?(BambuStudio_ubuntu24\.04-v([0-9][0-9.]*)-[0-9]+\.AppImage)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(webkit2gtk-4\.1-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libsoup3-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libavif-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libyuv-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(rav1e-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(svt-av1-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["arch-extra", "cachyos"], []),
    "coolercontrol": (r'href=[\'\"]?(?:\./)?(coolercontrol-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, r'href=[\'\"]?(?:\./)?(coolercontrold-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["cachyos", "arch-extra"], []),
    "asusctl": (r'href=[\'\"]?(?:\./)?(asusctl-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-extra", "cachyos"], []),
    "brave": (r'href=[\'\"]?(?:\./)?(brave-bin-(?:1(?:%3A|:))?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos", "chaotic-aur", "chaotic-cdn"], []),
    "zen-browser": (r'href=[\'\"]?(?:\./)?(zen-browser-bin-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos", "chaotic-aur", "chaotic-cdn"], []),
    "google-chrome": (r'href=[\'\"]?(?:\./)?(google-chrome-([0-9][a-zA-Z0-9_\.:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "chaotic-cdn", "cachyos"], []),
    "microsoft-edge": (r'href=[\'\"]?(?:\./)?(microsoft-edge-(?:stable|beta|dev)-bin-([0-9][a-zA-Z0-9_\.:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "chaotic-cdn", "cachyos"], []),
    "obs-studio": (r'href=[\'\"]?(?:\./)?(obs-studio-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(python-(3\.[0-9a-zA-Z_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(mbedtls-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(obs-studio-plugin-browser-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(cef-minimal-obs(?:-bin)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libdatachannel-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libjuice-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(librist-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libusrsctp-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["arch-extra", "cachyos", "cachyos-extra-v3", "chaotic-aur", "arch-core"], []),
    "discord": (r'href=[\'\"]?(?:\./)?(discord-(?:[0-9]+%3A|[0-9]+:)?([0-9][a-zA-Z0-9_\.:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-extra", "cachyos"], []),
    "vesktop": (r'href=[\'\"]?(?:\./)?(vesktop(?:-bin)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos"], []),
    "obs-vkcapture": (r'href=[\'\"]?(?:\./)?(obs-vkcapture-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', r'href=[\'\"]?(?:\./)?(lib32-obs-vkcapture-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, ["cachyos", "arch-extra"], ["cachyos", "arch-multilib"]),
    "obs-move-transition": (r'href=[\'\"]?(?:\./)?(obs-move-transition(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos-extra", "cachyos"], []),
    "obs-source-record": (r'href=[\'\"]?(?:\./)?(obs-source-record(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos-extra", "cachyos"], []),
    "obs-pipewire-audio-capture": (r'href=[\'\"]?(?:\./)?(obs-pipewire-audio-capture(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos-extra", "cachyos"], []),
    "obs-advanced-scene-switcher": (r'href=[\'\"]?(?:\./)?(obs-advanced-scene-switcher(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(opencv-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["chaotic-aur", "cachyos-extra", "arch-extra", "cachyos"], []),
    "obs-multi-rtmp": (r'href=[\'\"]?(?:\./)?(obs-multi-rtmp(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos-extra", "cachyos"], []),
    "obs-composite-blur": (r'href=[\'\"]?(?:\./)?(obs-composite-blur(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos-extra", "cachyos"], []),
    "obs-teleport": (r'href=[\'\"]?(?:\./)?(obs-teleport(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos-extra", "cachyos"], []),
    "zenpower3": (r'href=[\'\"]?(?:\./)?(zenpower3-dkms-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos", "arch-extra"], []),
    "v4l2loopback": (r'href=[\'\"]?(?:\./)?(v4l2loopback-dkms-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-extra", "cachyos", "chaotic-aur"], []),
    "rtl8821cu": (r'href=[\'\"]?(?:\./)?(rtl8821cu-morrownr-dkms-git-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos"], []),
    "rtl88x2bu": (r'href=[\'\"]?(?:\./)?(rtl88x2bu-dkms-git-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos"], []),
    "rtl8812au": (r'href=[\'\"]?(?:\./)?(rtl8812au-dkms-git-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos"], []),
    "broadcom-wl": (r'href=[\'\"]?(?:\./)?(broadcom-wl-dkms-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-extra", "cachyos"], []),
    "r8125": (r'href=[\'\"]?(?:\./)?(r8125-dkms-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos-extra-v3", "cachyos-extra", "cachyos"], []),
    "sunshine": (r'href=[\'\"]?(?:\./)?(sunshine-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(libayatana-appindicator-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(miniupnpc-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(numactl-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["cachyos", "arch-extra"], []),
    "vram-booster": (r'href=[\'\"]?(?:\./)?(dmemcg-booster-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, r'href=[\'\"]?(?:\./)?(plasma-foreground-booster-([0-9a-zA-Z_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["cachyos", "chaotic-aur", "arch-extra"], []),
    "limine": (r'href=[\'\"]?(?:\./)?(limine-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos", "arch-extra"], []),
    "limine-entry-tool": (r'href=[\'\"]?(?:\./)?(limine-entry-tool-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos"], []),
    "limine-snapper-sync": (r'href=[\'\"]?(?:\./)?(limine-snapper-sync-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos"], []),
    "sbctl": (r'href=[\'\"]?(?:\./)?(sbctl-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-extra", "cachyos"], []),
    "hyprland-noctalia": (r'href=[\'\"]?(?:\./)?(hyprland-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(libjpeg-turbo-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',  # 6A-13: libjpeg.so.8 for libhyprgraphics
        r'href=[\'\"]?(?:\./)?(noctalia(?:-shell)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(xdg-desktop-portal-hyprland-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprlock-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hypridle-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprpaper-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprpicker-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprland-guiutils-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(aquamarine-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprlang-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprcursor-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprgraphics-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprutils-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprpolkitagent-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprwire-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprtoolkit-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(sdbus-cpp-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(tomlplusplus-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(muparser-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(re2-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(md4c-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(lua-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libical-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(ddcui-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(wlr-randr-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(nwg-displays-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(python-i3ipc-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["cachyos-extra-v3", "cachyos-v3", "cachyos", "arch-extra", "chaotic-aur"], []),
    "hyprland-core": (r'href=[\'\"]?(?:\./)?(hyprland-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(libjpeg-turbo-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',  # 6A-13: libjpeg.so.8 for libhyprgraphics
        r'href=[\'\"]?(?:\./)?(xdg-desktop-portal-hyprland-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprlock-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hypridle-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprpaper-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprpicker-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprland-guiutils-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(aquamarine-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprlang-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprcursor-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprgraphics-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprutils-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprpolkitagent-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprwire-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprtoolkit-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(sdbus-cpp-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(tomlplusplus-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(muparser-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(re2-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(lua-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(ddcui-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(wlr-randr-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(nwg-displays-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(python-i3ipc-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["cachyos-extra-v3", "cachyos-v3", "cachyos", "arch-extra"], []),
    "hyprpicker": (r'href=[\'\"]?(?:\./)?(hyprpicker-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos-extra-v3", "cachyos-v3", "cachyos", "arch-extra"], [])
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

# 6A-322: the Arch package name differs from the catalog id for these (the JSON lookup answered 404 for the id)
ARCH_API_NAMES = {"spotify": "spotify-launcher", "v4l2loopback": "v4l2loopback-dkms"}
ARCH_API_ARCH = {"v4l2loopback": "any"}   # a DKMS source package is arch=any in the Arch API

def clean_pkg_version(pid, raw_v):
    v = urllib.parse.unquote(str(raw_v))
    v = re.sub(r'\.pkg\.tar\.(?:zst|xz|gz)$', '', v)
    v = re.sub(r'-(?:x86_64(?:_v[0-9]+)?|noarch|i[3-6]86|any|aarch64)(?:-[0-9a-zA-Z_]+)?$', '', v)
    v = re.sub(r'-[0-9]+(?:\.[0-9]+)?$', '', v)
    if pid:
        pid_clean = pid.replace("-", "")
        v = re.sub(rf'^(?:underpants-|cachyos-gnome-)?(?:{re.escape(pid)}|{re.escape(pid_clean)})(?:-bin|-git|-manager|-launcher|-rules|-udev)?-', '', v, flags=re.IGNORECASE)
    v = re.sub(r'^[0-9]+(?:%3A|:|_)', '', v)
    v = re.sub(r'^[a-zA-Z0-9_\-+]+?-([0-9])', r'\1', v)
    v = re.sub(r'^[0-9]+(?:%3A|:|_)', '', v)
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

# 6A-296 (F3): the boot loader (limine) and sbctl are held at the installed MAJOR version: an update inside the same major is offered,
# a higher major is never installed automatically (a new Limine may change its config or command line and leave a menu that does
# not boot). Nothing is held when the package is not installed yet.
MAJOR_HOLD_PIDS = ("limine", "sbctl")
def version_major(v):
    m = re.match(r'[0-9]+', clean_pkg_version('', str(v)))
    return int(m.group(0)) if m else None

def installed_major(pid):
    best = None
    try:
        for e in os.listdir("/var/log/packages"):
            m = re.match(re.escape(pid) + r'-([0-9][^-]*)-(?:x86_64|noarch|i[3-6]86)-[^-]+$', e)
            if m:
                mj = version_major(m.group(1))
                if mj is not None and (best is None or mj > best):
                    best = mj
    except OSError:
        pass
    return best

def major_held(pid, ver, inst_major=None):
    if pid not in MAJOR_HOLD_PIDS:
        return False
    im = inst_major if inst_major is not None else installed_major(pid)
    if im is None:
        return False
    vm = version_major(ver)
    return vm is None or vm > im

def fetch_match(pat, r_list, pid=''):
    if not pat:
        return None, None
    candidates = []
    for r_key in expand_repos_for_tier(r_list, cpu_tier):
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
    if pid in MAJOR_HOLD_PIDS:
        _im = installed_major(pid)
        candidates = [c for c in candidates if not major_held(pid, c[0], _im)]
    if candidates:
        candidates.sort(key=lambda c: parse_version_key(c[0]))
        best = candidates[-1]
        return best[2], best[1]
    return None, None

def fetch_all_matches(pat, r_list, pid=''):
    if not pat:
        return {}
    res = {}
    for r_key in expand_repos_for_tier(r_list, cpu_tier):
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
            if clean_v not in res:
                res[clean_v] = (url, ver)
    return res

aur_pkg_names = {
    "google-chrome": ("google-chrome", "google-chrome-{ver}-x86_64.pkg.tar.zst"),
    "antigravity": ("antigravity", "antigravity-{ver}-x86_64.pkg.tar.zst"),
    "microsoft-edge": ("microsoft-edge-stable-bin", "microsoft-edge-stable-bin-{ver}-x86_64.pkg.tar.zst"),
    "brave": ("brave-bin", "brave-bin-{ver}-x86_64.pkg.tar.zst"),
    "zen-browser": ("zen-browser-bin", "zen-browser-bin-{ver}-x86_64.pkg.tar.zst"),
    "opera": ("opera", "opera-{ver}-x86_64.pkg.tar.zst"),
    "plasticity": ("plasticity-bin", "plasticity-bin-{ver}-x86_64.pkg.tar.zst"),
    "storyboarder": ("storyboarder-bin", "storyboarder-bin-{ver}-x86_64.pkg.tar.zst"),
    "volt-gui": ("volt-gui-bin", "volt-gui-bin-{ver}-x86_64.pkg.tar.zst"),
    "zenpower3": ("zenpower3-dkms", "zenpower3-dkms-{ver}-x86_64.pkg.tar.zst"),
    "v4l2loopback": ("v4l2loopback-dkms-git", "v4l2loopback-dkms-git-{ver}-x86_64.pkg.tar.zst"),
    "rtl8821cu": ("rtl8821cu-morrownr-dkms-git", "rtl8821cu-morrownr-dkms-git-{ver}-x86_64.pkg.tar.zst"),
    "rtl88x2bu": ("rtl88x2bu-dkms-git", "rtl88x2bu-dkms-git-{ver}-x86_64.pkg.tar.zst"),
    "rtl8812au": ("rtl8812au-dkms-git", "rtl8812au-dkms-git-{ver}-x86_64.pkg.tar.zst"),
    "obs-pipewire-audio-capture": ("obs-pipewire-audio-capture", "obs-pipewire-audio-capture-{ver}-x86_64.pkg.tar.zst")
}

github_and_direct_pkgs = {
    "obs-move-transition": {
        "type": "github_release",
        "repo": "exeldro/obs-move-transition",
        "asset_pattern": r"move-transition-([0-9\.]+)-x86_64-linux-gnu\.deb",
        "skip_prerelease": True
    },
    "obs-source-record": {
        "type": "github_release",
        "repo": "exeldro/obs-source-record",
        "asset_pattern": r"source-record-([0-9\.]+)-ubuntu.*\.tar\.gz",
        "skip_prerelease": True
    },
    "obs-advanced-scene-switcher": {
        "type": "github_release",
        "repo": "WarmUpTill/SceneSwitcher",
        "asset_pattern": r"advanced-scene-switcher-([0-9\.]+)-x86_64-ubuntu.*-linux-gnu\.deb",
        "skip_prerelease": True
    },
    "obs-multi-rtmp": {
        "type": "github_release",
        "repo": "sorayuki/obs-multi-rtmp",
        "asset_pattern": r"obs-multi-rtmp-([0-9\.]+)-x86_64-linux-gnu-ubuntu.*\.deb",
        "skip_prerelease": True
    },
    "obs-composite-blur": {
        "type": "github_release",
        "repo": "FiniteSingularity/obs-composite-blur",
        "asset_pattern": r"obs-composite-blur-([0-9\.]+)-(?:x86_64-linux-gnu\.deb|ubuntu.*\.zip)",
        "skip_prerelease": True
    },
    "obs-teleport": {
        "type": "github_release",
        "repo": "fzwoch/obs-teleport",
        "asset_pattern": r"Teleport-([0-9\.]+)-Linux-x86_64\.zip",
        "skip_prerelease": True
    },
    "openghub": {
        "type": "github_release",
        "repo": "Slyvan25/OpenGHub",
        "asset_pattern": r"OpenGHub_([0-9\.]+)_amd64\.deb",
        "fallback_version": "0.1.4",
        "fallback_url": "https://github.com/Slyvan25/OpenGHub/releases/download/v0.1.4/OpenGHub_0.1.4_amd64.deb"
    },
    # 6A-192: official Bambu Lab release AppImage (the AUR / Chaotic name bambu-studio-bin is dead); the newest release that
    # is not a prerelease. The build checks the download against the SHA-256 of the release API (slacky_vendor_fetch.py).
    "bambu-studio": {
        "type": "github_release",
        "repo": "bambulab/BambuStudio",
        "asset_pattern": r"^BambuStudio_(?:ubuntu24\.04|ubu24)-v([0-9][0-9.]*)-[0-9]+\.AppImage$",
        "skip_prerelease": True
    }
}

main_ver, main_url, lib32_url = None, None, "NONE"

if lib32_pat:
    main_matches = fetch_all_matches(main_pat, main_repos, pkg_id)
    for repo_cand in ("multilib", "extra", "core"):
        try:
            api_url = f"https://archlinux.org/packages/{repo_cand}/x86_64/{pkg_id}/json/"
            raw_json = fetch_url_cached(api_url, cache_dir, ttl=1800)
            if raw_json:
                data = json.loads(raw_json)
                fn = data.get("filename")
                v = data.get("pkgver")
                if fn and v:
                    cv = clean_pkg_version(pkg_id, v)
                    url = f"https://geo.mirror.pkgbuild.com/{repo_cand}/os/x86_64/{fn}"
                    if cv not in main_matches:
                        main_matches[cv] = (url, v)
                    break
        except Exception:
            pass

    lib32_matches = fetch_all_matches(lib32_pat, lib32_repos or main_repos, f"lib32-{pkg_id}")
    for l32_name in (f"lib32-{pkg_id}", f"lib32-{pkg_id.replace('-bin', '')}"):
        try:
            api_url = f"https://archlinux.org/packages/multilib/x86_64/{l32_name}/json/"
            raw_json = fetch_url_cached(api_url, cache_dir, ttl=1800)
            if raw_json:
                data = json.loads(raw_json)
                fn = data.get("filename")
                v = data.get("pkgver")
                if fn and v:
                    cv = clean_pkg_version(f"lib32-{pkg_id}", v)
                    url = f"https://geo.mirror.pkgbuild.com/multilib/os/x86_64/{fn}"
                    if cv not in lib32_matches:
                        lib32_matches[cv] = (url, v)
                    break
        except Exception:
            pass

    common_vers = [v for v in main_matches if v in lib32_matches]
    if common_vers:
        common_vers.sort(key=parse_version_key)
        best_v = common_vers[-1]
        main_url, main_ver = main_matches[best_v]
        lib32_url, _ = lib32_matches[best_v]
else:
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
                        if meta.get("skip_prerelease") and (rel.get("prerelease") or rel.get("draft")):
                            continue
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
            if (not main_ver or not main_url) and "fallback_url" in meta:
                main_ver = meta.get("fallback_version", "0.1.4")
                main_url = meta.get("fallback_url")

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
                api_url = f"https://archlinux.org/packages/{repo_cand}/{ARCH_API_ARCH.get(pkg_id, 'x86_64')}/{ARCH_API_NAMES.get(pkg_id, pkg_id)}/json/"
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

if main_ver and main_url and major_held(pkg_id, main_ver):
    main_ver = main_url = None   # 6A-296 (F3): also the Arch fall-back must not bring a new major
if not main_ver or not main_url:
    print("NONE NONE NONE NONE")
    sys.exit(0)

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

    SLACKY_LIB_DIR="$(slacky_mirrors_lib_dir)" python3 - "${target_pids[@]}" << 'PYBATCHRESOLVE'
import sys, os, re, time, datetime, json, urllib.request, urllib.parse, hashlib, concurrent.futures

pkg_ids = sys.argv[1:]

def get_cache_dir():
    for d in ['/var/cache/slacky-update', os.path.expanduser('~/.cache/slacky-update')]:
        try:
            os.makedirs(d, exist_ok=True)
            test_f = os.path.join(d, '.write_test')
            with open(test_f, 'w') as f: f.write('1')
            os.remove(test_f)
            return d
        except Exception:
            continue
    # 6A-17: no fixed /tmp fallback (predictable path, lost on reboot); a private temp dir instead
    return __import__('tempfile').mkdtemp(prefix='slacky-update-cache.')

cache_dir = get_cache_dir()

# 6A-182: one shared helper (lib/slacky_mirrors.py) instead of three copies; the daily rule and the cache file
# (chaotic_fastest_mirror.json) are defined there. Without the module the geo mirror is used.
if os.environ.get('SLACKY_LIB_DIR'):
    sys.path.insert(0, os.environ['SLACKY_LIB_DIR'])
try:
    import slacky_mirrors as _slacky_mirrors
    def get_chaotic_fastest_mirror(cdir):
        return _slacky_mirrors.chaotic_fastest(cdir)
except Exception:
    def get_chaotic_fastest_mirror(cdir):
        return 'https://geo-mirror.chaotic.cx/chaotic-aur/x86_64/'

chaotic_fastest = get_chaotic_fastest_mirror(cache_dir)

def detect_cpu_tier() -> str:
    cpuinfo = "/proc/cpuinfo"
    if not os.path.exists(cpuinfo):
        return "generic"
    try:
        with open(cpuinfo, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
        if all(flag in content for flag in ["avx512f", "avx512bw", "avx512cd", "avx512dq", "avx512vl"]):
            if "AuthenticAMD" in content:
                return "znver4"
            return "v4"
        elif all(flag in content for flag in ["avx2", "fma", "bmi1", "bmi2"]):
            return "v3"
    except Exception:
        pass
    return "generic"

cpu_tier = detect_cpu_tier()

def expand_repos_for_tier(r_list, tier):
    res = []
    for r in r_list:
        if r in ("cachyos-extra-v3", "cachyos-extra"):
            if tier == "znver4":
                for cand in ["cachyos-extra-znver4", "cachyos-extra-v4", "cachyos-extra-v3", "cachyos-extra"]:
                    if cand not in res: res.append(cand)
            elif tier == "v4":
                for cand in ["cachyos-extra-v4", "cachyos-extra-v3", "cachyos-extra"]:
                    if cand not in res: res.append(cand)
            elif tier == "v3":
                for cand in ["cachyos-extra-v3", "cachyos-extra"]:
                    if cand not in res: res.append(cand)
            else:
                if "cachyos-extra" not in res: res.append("cachyos-extra")
        elif r in ("cachyos-v3", "cachyos"):
            if tier == "znver4":
                for cand in ["cachyos-znver4", "cachyos-v4", "cachyos-v3", "cachyos"]:
                    if cand not in res: res.append(cand)
            elif tier == "v4":
                for cand in ["cachyos-v4", "cachyos-v3", "cachyos"]:
                    if cand not in res: res.append(cand)
            elif tier == "v3":
                for cand in ["cachyos-v3", "cachyos"]:
                    if cand not in res: res.append(cand)
            else:
                if "cachyos" not in res: res.append("cachyos")
        else:
            if r not in res: res.append(r)
    return res

c_base = "https://mirror.cachyos.org/repo"
repos = {
    "cachyos": f"{c_base}/x86_64/cachyos/",
    "cachyos-extra": f"{c_base}/x86_64/cachyos-extra/",
    "cachyos-v3": f"{c_base}/x86_64_v3/cachyos-v3/",
    "cachyos-extra-v3": f"{c_base}/x86_64_v3/cachyos-extra-v3/",
    "cachyos-v4": f"{c_base}/x86_64_v4/cachyos-v4/",
    "cachyos-extra-v4": f"{c_base}/x86_64_v4/cachyos-extra-v4/",
    "cachyos-znver4": f"{c_base}/x86_64_v4/cachyos-znver4/",
    "cachyos-extra-znver4": f"{c_base}/x86_64_v4/cachyos-extra-znver4/",
    "chaotic-aur": chaotic_fastest,
    "chaotic-cdn": chaotic_fastest,
    "arch-core": "https://geo.mirror.pkgbuild.com/core/os/x86_64/",
    "arch-extra": "https://geo.mirror.pkgbuild.com/extra/os/x86_64/",
    "arch-multilib": "https://geo.mirror.pkgbuild.com/multilib/os/x86_64/"
}

if cpu_tier == "generic":
    repos["cachyos-v3"] = repos["cachyos"]
    repos["cachyos-extra-v3"] = repos["cachyos-extra"]
    repos["cachyos-v4"] = repos["cachyos"]
    repos["cachyos-extra-v4"] = repos["cachyos-extra"]
    repos["cachyos-znver4"] = repos["cachyos"]
    repos["cachyos-extra-znver4"] = repos["cachyos-extra"]

catalog = {
    "mangohud": (r'href=[\'\"]?(?:\./)?(mangohud-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', r'href=[\'\"]?(?:\./)?(lib32-mangohud-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', r'href=[\'\"]?(?:\./)?(glfw-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["cachyos-extra-v3", "arch-extra", "cachyos"], ["arch-multilib", "cachyos"]),
    "gamemode": (r'href=[\'\"]?(?:\./)?(gamemode-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', r'href=[\'\"]?(?:\./)?(lib32-gamemode-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, ["cachyos-extra-v3", "arch-extra", "cachyos"], ["arch-multilib", "cachyos"]),
    "goverlay": (r'href=[\'\"]?(?:\./)?(goverlay-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, r'href=[\'\"]?(?:\./)?(qt6pas-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["arch-extra", "cachyos"], []),
    "scx": (r'href=[\'\"]?(?:\./)?(scx-manager-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(scx-scheds(?:-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(scx-tools(?:-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["cachyos", "arch-extra"], []),
    "easyeffects": (r'href=[\'\"]?(?:\./)?(easyeffects-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(lsp-plugins-lv2-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(calf-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(mda\.lv2-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(zam-plugins-lv2-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(zita-convolver-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(rnnoise-(?:1%3A|1:)?([0-9a-zA-Z_\.:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libbs2b-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(soundtouch-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libebur128-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(webrtc-audio-processing-(?:2|1)-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(lilv-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(serd-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(sord-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(sratom-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(qt6-graphs-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(onetbb-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libmysofa-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(zix-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["arch-extra", "cachyos", "arch-core"], []),
    "pear-desktop": (r'href=[\'\"]?(?:\./)?(pear-desktop-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(electron42-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libjpeg-turbo-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["chaotic-aur", "chaotic-cdn", "arch-extra"], []),
    # 6A-189: no repository carries lib32-yabridge, so the 32-bit part is not required (same as the Rust app): the lib32 pattern is None
    "yabridge": (r'href=[\'\"]?(?:\./)?(yabridge-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, r'href=[\'\"]?(?:\./)?(yabridgectl-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["arch-extra", "cachyos", "chaotic-aur"], ["arch-multilib", "cachyos"]),
    "audacity": (r'href=[\'\"]?(?:\./)?(audacity-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(suil-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(lilv-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(serd-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(sord-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(sratom-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(zix-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(portsmf-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(portaudio-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(portmidi-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libsbsms-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(vamp-plugin-sdk-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(soundtouch-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(twolame-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libid3tag-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libsoxr-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libmspack-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(wxwidgets-gtk3-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(wxwidgets-common-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libjpeg-turbo-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["arch-extra", "cachyos-extra-v3", "cachyos", "arch-core"], []),
    "spotify": (r'href=[\'\"]?(?:\./)?(spotify(?:-launcher)?-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(sequoia-sqv-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libayatana-appindicator-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libayatana-indicator-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(ayatana-ido-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libcurl-gnutls-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["arch-extra", "cachyos-extra-v3", "cachyos", "arch-core"], []),
    "inkscape": (r'href=[\'\"]?(?:\./)?(inkscape-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(lib2geom-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(double-conversion-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(graphicsmagick-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libcdr-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(poppler-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libvisio-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libwpg-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(librevenge-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["cachyos-extra-v3", "arch-extra", "cachyos"], []),
    "darktable": (r'href=[\'\"]?(?:\./)?(darktable-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(libavif-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libheif-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libde265-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libyuv-((?:r[0-9]+|[0-9])[a-zA-Z0-9_\.\+%-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(rav1e-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(svt-av1-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(openh264-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(pugixml-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(colord-gtk-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(osm-gps-map-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(gmic-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(flickcurl-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["cachyos-extra-v3", "arch-extra", "cachyos"], []),
    "syncthing": (r'href=[\'\"]?(?:\./)?(syncthing-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-extra", "cachyos-extra-v3", "cachyos"], []),
    "antigravity": (r'href=[\'\"]?(?:\./)?(antigravity(?:-bin|-ide)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "chaotic-cdn", "cachyos", "arch-extra"], []),
    "ananicy": (r'href=[\'\"]?(?:\./)?(ananicy-cpp(?:-git)?-([0-9a-zA-Z_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(cachyos-ananicy-rules(?:-git)?-([0-9a-zA-Z_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libbpf-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["cachyos", "cachyos-extra-v3", "arch-core"], []),
    "gamescope": (r'href=[\'\"]?(?:\./)?(gamescope-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', r'href=[\'\"]?(?:\./)?(lib32-gamescope-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', r'href=[\'\"]?(?:\./)?(libavif-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["cachyos", "arch-extra"], ["cachyos", "arch-multilib"]),
    "heroic": (r'href=[\'\"]?(?:\./)?(heroic-games-launcher-bin-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos", "arch-extra"], []),
    "lutris": (r'href=[\'\"]?(?:\./)?(lutris(?:-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(webkit2gtk-4\.1-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libsoup3-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(python-moddb-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(python-pypresence-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(python-evdev-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(python-distro-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["arch-extra", "cachyos", "arch-core", "cachyos-extra-v3"], []),
    "faugus": (r'href=[\'\"]?(?:\./)?(faugus-launcher-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(python-vdf-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(icoextract-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(python-pefile-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["cachyos", "arch-extra"], []),
    "protonplus": (r'href=[\'\"]?(?:\./)?((?:proton-plus|protonplus)-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos", "arch-extra"], []),
    "steam": (r'href=[\'\"]?(?:\./)?(steam-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-multilib", "cachyos"], []),
    "steam-devices": (None, None, None, [], []),
    "retroarch": (r'href=[\'\"]?(?:\./)?(retroarch-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, r'href=[\'\"]?(?:\./)?(retroarch-assets-ozone-(?:[0-9]+%3A)?([0-9a-zA-Z_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["arch-extra", "cachyos"], []),
    "lact": (r'href=[\'\"]?(?:\./)?(lact-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-extra", "cachyos"], []),
    "openrgb": (r'href=[\'\"]?(?:\./)?(openrgb(?:-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos", "arch-extra"], []),
    "solaar": (r'href=[\'\"]?(?:\./)?(solaar-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(python-pyudev-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(python-typing_extensions-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(python-xlib-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["arch-extra", "cachyos-extra-v3", "cachyos"], []),
    "openghub": (r'href=[\'\"]?(?:\./)?(openghub(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(webkit2gtk-4\.1-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libsoup3-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libmanette-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["arch-extra", "cachyos", "chaotic-aur"], []),
    # 6A-192: the program is the official GitHub release AppImage (github_and_direct_pkgs below); these are its library parts
    "bambu-studio": (r'href=[\'\"]?(?:\./)?(BambuStudio_ubuntu24\.04-v([0-9][0-9.]*)-[0-9]+\.AppImage)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(webkit2gtk-4\.1-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libsoup3-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libavif-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libyuv-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(rav1e-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(svt-av1-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["arch-extra", "cachyos"], []),
    "coolercontrol": (r'href=[\'\"]?(?:\./)?(coolercontrol-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, r'href=[\'\"]?(?:\./)?(coolercontrold-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["cachyos", "arch-extra"], []),
    "asusctl": (r'href=[\'\"]?(?:\./)?(asusctl-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-extra", "cachyos"], []),
    "brave": (r'href=[\'\"]?(?:\./)?(brave-bin-(?:1(?:%3A|:))?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos", "chaotic-aur", "chaotic-cdn"], []),
    "zen-browser": (r'href=[\'\"]?(?:\./)?(zen-browser-bin-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos", "chaotic-aur", "chaotic-cdn"], []),
    "google-chrome": (r'href=[\'\"]?(?:\./)?(google-chrome-([0-9][a-zA-Z0-9_\.:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "chaotic-cdn", "cachyos"], []),
    "microsoft-edge": (r'href=[\'\"]?(?:\./)?(microsoft-edge-(?:stable|beta|dev)-bin-([0-9][a-zA-Z0-9_\.:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "chaotic-cdn", "cachyos"], []),
    "obs-studio": (r'href=[\'\"]?(?:\./)?(obs-studio-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(python-(3\.[0-9a-zA-Z_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(mbedtls-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(obs-studio-plugin-browser-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(cef-minimal-obs(?:-bin)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libdatachannel-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libjuice-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(librist-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libusrsctp-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["arch-extra", "arch-core", "cachyos"], []),
    "discord": (r'href=[\'\"]?(?:\./)?(discord-(?:[0-9]+%3A|[0-9]+:)?([0-9][a-zA-Z0-9_\.:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-extra", "cachyos"], []),
    "vesktop": (r'href=[\'\"]?(?:\./)?(vesktop(?:-bin)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos"], []),
    "obs-vkcapture": (r'href=[\'\"]?(?:\./)?(obs-vkcapture-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', r'href=[\'\"]?(?:\./)?(lib32-obs-vkcapture-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, ["cachyos", "arch-extra"], ["cachyos", "arch-multilib"]),
    "obs-move-transition": (r'href=[\'\"]?(?:\./)?(obs-move-transition(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos-extra", "cachyos"], []),
    "obs-source-record": (r'href=[\'\"]?(?:\./)?(obs-source-record(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos-extra", "cachyos"], []),
    "obs-pipewire-audio-capture": (r'href=[\'\"]?(?:\./)?(obs-pipewire-audio-capture(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos-extra", "cachyos"], []),
    "obs-advanced-scene-switcher": (r'href=[\'\"]?(?:\./)?(obs-advanced-scene-switcher(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(opencv-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["chaotic-aur", "cachyos-extra", "arch-extra", "cachyos"], []),
    "obs-multi-rtmp": (r'href=[\'\"]?(?:\./)?(obs-multi-rtmp(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos-extra", "cachyos"], []),
    "obs-composite-blur": (r'href=[\'\"]?(?:\./)?(obs-composite-blur(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos-extra", "cachyos"], []),
    "obs-teleport": (r'href=[\'\"]?(?:\./)?(obs-teleport(?:-bin|-git)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos-extra", "cachyos"], []),
    "zenpower3": (r'href=[\'\"]?(?:\./)?(zenpower3-dkms-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos", "arch-extra"], []),
    "v4l2loopback": (r'href=[\'\"]?(?:\./)?(v4l2loopback-dkms-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-extra", "cachyos", "chaotic-aur"], []),
    "rtl8821cu": (r'href=[\'\"]?(?:\./)?(rtl8821cu-morrownr-dkms-git-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos"], []),
    "rtl88x2bu": (r'href=[\'\"]?(?:\./)?(rtl88x2bu-dkms-git-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos"], []),
    "rtl8812au": (r'href=[\'\"]?(?:\./)?(rtl8812au-dkms-git-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos"], []),
    "broadcom-wl": (r'href=[\'\"]?(?:\./)?(broadcom-wl-dkms-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-extra", "cachyos"], []),
    "r8125": (r'href=[\'\"]?(?:\./)?(r8125-dkms-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "cachyos-extra-v3", "cachyos-extra", "cachyos"], []),
    "sunshine": (r'href=[\'\"]?(?:\./)?(sunshine-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(libayatana-appindicator-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(miniupnpc-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(numactl-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["cachyos", "arch-extra"], []),
    "vram-booster": (r'href=[\'\"]?(?:\./)?(dmemcg-booster-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, r'href=[\'\"]?(?:\./)?(plasma-foreground-booster-([0-9a-zA-Z_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["cachyos", "chaotic-aur", "arch-extra"], []),
    "limine": (r'href=[\'\"]?(?:\./)?(limine-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos", "arch-extra"], []),
    "limine-entry-tool": (r'href=[\'\"]?(?:\./)?(limine-entry-tool-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos"], []),
    "limine-snapper-sync": (r'href=[\'\"]?(?:\./)?(limine-snapper-sync-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos"], []),
    "sbctl": (r'href=[\'\"]?(?:\./)?(sbctl-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["arch-extra", "cachyos"], []),
    "hyprland-noctalia": (r'href=[\'\"]?(?:\./)?(hyprland-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(libjpeg-turbo-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',  # 6A-13: libjpeg.so.8 for libhyprgraphics
        r'href=[\'\"]?(?:\./)?(noctalia(?:-shell)?-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(xdg-desktop-portal-hyprland-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprlock-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hypridle-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprpaper-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprpicker-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprland-guiutils-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(aquamarine-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprlang-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprcursor-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprgraphics-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprutils-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprpolkitagent-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprwire-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprtoolkit-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(sdbus-cpp-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(tomlplusplus-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(muparser-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(re2-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(md4c-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(lua-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libical-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(ddcui-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(wlr-randr-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(nwg-displays-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(python-i3ipc-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["cachyos-extra-v3", "cachyos-v3", "cachyos", "arch-extra", "chaotic-aur"], []),
    "hyprland-core": (r'href=[\'\"]?(?:\./)?(hyprland-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(libjpeg-turbo-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',  # 6A-13: libjpeg.so.8 for libhyprgraphics
        r'href=[\'\"]?(?:\./)?(xdg-desktop-portal-hyprland-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprlock-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hypridle-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprpaper-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprpicker-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprland-guiutils-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(aquamarine-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprlang-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprcursor-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprgraphics-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprutils-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprpolkitagent-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprwire-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(hyprtoolkit-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(sdbus-cpp-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(tomlplusplus-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(muparser-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(re2-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(lua-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(ddcui-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(wlr-randr-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(nwg-displays-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(python-i3ipc-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["cachyos-extra-v3", "cachyos-v3", "cachyos", "arch-extra"], []),
    "hyprpicker": (r'href=[\'\"]?(?:\./)?(hyprpicker-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["cachyos-extra-v3", "cachyos-v3", "cachyos", "arch-extra"], []),
    "mactahoe-icons": (None, None, None, [], []),
    "mactahoe-cursors": (None, None, None, [], []),
    "whitesur-icons": (None, None, None, [], []),
    "whitesur-cursors": (None, None, None, [], []),
    "opera": (r'href=[\'\"]?(?:\./)?(opera-([0-9a-zA-Z_\.:-]*)\.pkg\.tar\.zst)[\'\"]?', None, None, ["chaotic-aur", "chaotic-cdn", "cachyos"], []),
    "gnome-disk-utility": (r'href=[\'\"]?(?:\./)?(gnome-disk-utility-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(libhandy-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(libdvdread-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["cachyos-extra-v4", "cachyos-extra-v3", "arch-extra", "cachyos"], []),
    "spacenav": (r'href=[\'\"]?(?:\./)?(spacenavd-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', None, [
        r'href=[\'\"]?(?:\./)?(libspnav-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?',
        r'href=[\'\"]?(?:\./)?(spnavcfg-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
    ], ["arch-extra", "cachyos", "chaotic-aur"], [])
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

# 6A-322: the Arch package name differs from the catalog id for these (the JSON lookup answered 404 for the id)
ARCH_API_NAMES = {"spotify": "spotify-launcher", "v4l2loopback": "v4l2loopback-dkms"}
ARCH_API_ARCH = {"v4l2loopback": "any"}   # a DKMS source package is arch=any in the Arch API

def clean_pkg_version(pid, raw_v):
    v = urllib.parse.unquote(str(raw_v))
    v = re.sub(r'\.pkg\.tar\.(?:zst|xz|gz)$', '', v)
    v = re.sub(r'-(?:x86_64(?:_v[0-9]+)?|noarch|i[3-6]86|any|aarch64)(?:-[0-9a-zA-Z_]+)?$', '', v)
    v = re.sub(r'-[0-9]+(?:\.[0-9]+)?$', '', v)
    if pid:
        pid_clean = pid.replace("-", "")
        v = re.sub(rf'^(?:underpants-|cachyos-gnome-)?(?:{re.escape(pid)}|{re.escape(pid_clean)})(?:-bin|-git|-manager|-launcher|-rules|-udev)?-', '', v, flags=re.IGNORECASE)
    v = re.sub(r'^[0-9]+(?:%3A|:|_)', '', v)
    v = re.sub(r'^[a-zA-Z0-9_\-+]+?-([0-9])', r'\1', v)
    v = re.sub(r'^[0-9]+(?:%3A|:|_)', '', v)
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

# 6A-296 (F3): the boot loader (limine) and sbctl are held at the installed MAJOR version: an update inside the same major is offered,
# a higher major is never installed automatically (a new Limine may change its config or command line and leave a menu that does
# not boot). Nothing is held when the package is not installed yet.
MAJOR_HOLD_PIDS = ("limine", "sbctl")
def version_major(v):
    m = re.match(r'[0-9]+', clean_pkg_version('', str(v)))
    return int(m.group(0)) if m else None

def installed_major(pid):
    best = None
    try:
        for e in os.listdir("/var/log/packages"):
            m = re.match(re.escape(pid) + r'-([0-9][^-]*)-(?:x86_64|noarch|i[3-6]86)-[^-]+$', e)
            if m:
                mj = version_major(m.group(1))
                if mj is not None and (best is None or mj > best):
                    best = mj
    except OSError:
        pass
    return best

def major_held(pid, ver, inst_major=None):
    if pid not in MAJOR_HOLD_PIDS:
        return False
    im = inst_major if inst_major is not None else installed_major(pid)
    if im is None:
        return False
    vm = version_major(ver)
    return vm is None or vm > im

def fetch_match(pat, r_list, pid=''):
    if not pat:
        return None, None
    candidates = []
    for r_key in expand_repos_for_tier(r_list, cpu_tier):
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
    if pid in MAJOR_HOLD_PIDS:
        _im = installed_major(pid)
        candidates = [c for c in candidates if not major_held(pid, c[0], _im)]
    if candidates:
        candidates.sort(key=lambda c: parse_version_key(c[0]))
        best = candidates[-1]
        return best[2], best[1]
    return None, None

def fetch_all_matches(pat, r_list, pid=''):
    if not pat:
        return {}
    res = {}
    for r_key in expand_repos_for_tier(r_list, cpu_tier):
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
            if clean_v not in res:
                res[clean_v] = (url, ver)
    return res

aur_pkg_names = {
    "google-chrome": ("google-chrome", "google-chrome-{ver}-x86_64.pkg.tar.zst"),
    "antigravity": ("antigravity", "antigravity-{ver}-x86_64.pkg.tar.zst"),
    "microsoft-edge": ("microsoft-edge-stable-bin", "microsoft-edge-stable-bin-{ver}-x86_64.pkg.tar.zst"),
    "brave": ("brave-bin", "brave-bin-{ver}-x86_64.pkg.tar.zst"),
    "zen-browser": ("zen-browser-bin", "zen-browser-bin-{ver}-x86_64.pkg.tar.zst"),
    "opera": ("opera", "opera-{ver}-x86_64.pkg.tar.zst"),
    "plasticity": ("plasticity-bin", "plasticity-bin-{ver}-x86_64.pkg.tar.zst"),
    "storyboarder": ("storyboarder-bin", "storyboarder-bin-{ver}-x86_64.pkg.tar.zst"),
    "volt-gui": ("volt-gui-bin", "volt-gui-bin-{ver}-x86_64.pkg.tar.zst"),
    "zenpower3": ("zenpower3-dkms", "zenpower3-dkms-{ver}-x86_64.pkg.tar.zst"),
    "v4l2loopback": ("v4l2loopback-dkms-git", "v4l2loopback-dkms-git-{ver}-x86_64.pkg.tar.zst"),
    "rtl8821cu": ("rtl8821cu-morrownr-dkms-git", "rtl8821cu-morrownr-dkms-git-{ver}-x86_64.pkg.tar.zst"),
    "rtl88x2bu": ("rtl88x2bu-dkms-git", "rtl88x2bu-dkms-git-{ver}-x86_64.pkg.tar.zst"),
    "rtl8812au": ("rtl8812au-dkms-git", "rtl8812au-dkms-git-{ver}-x86_64.pkg.tar.zst"),
    "obs-pipewire-audio-capture": ("obs-pipewire-audio-capture", "obs-pipewire-audio-capture-{ver}-x86_64.pkg.tar.zst")
}

github_and_direct_pkgs = {
    "obs-move-transition": {
        "type": "github_release",
        "repo": "exeldro/obs-move-transition",
        "asset_pattern": r"move-transition-([0-9\.]+)-x86_64-linux-gnu\.deb",
        "skip_prerelease": True
    },
    "obs-source-record": {
        "type": "github_release",
        "repo": "exeldro/obs-source-record",
        "asset_pattern": r"source-record-([0-9\.]+)-ubuntu.*\.tar\.gz",
        "skip_prerelease": True
    },
    "obs-advanced-scene-switcher": {
        "type": "github_release",
        "repo": "WarmUpTill/SceneSwitcher",
        "asset_pattern": r"advanced-scene-switcher-([0-9\.]+)-x86_64-ubuntu.*-linux-gnu\.deb",
        "skip_prerelease": True
    },
    "obs-multi-rtmp": {
        "type": "github_release",
        "repo": "sorayuki/obs-multi-rtmp",
        "asset_pattern": r"obs-multi-rtmp-([0-9\.]+)-x86_64-linux-gnu-ubuntu.*\.deb",
        "skip_prerelease": True
    },
    "obs-composite-blur": {
        "type": "github_release",
        "repo": "FiniteSingularity/obs-composite-blur",
        "asset_pattern": r"obs-composite-blur-([0-9\.]+)-(?:x86_64-linux-gnu\.deb|ubuntu.*\.zip)",
        "skip_prerelease": True
    },
    "obs-teleport": {
        "type": "github_release",
        "repo": "fzwoch/obs-teleport",
        "asset_pattern": r"Teleport-([0-9\.]+)-Linux-x86_64\.zip",
        "skip_prerelease": True
    },
    "openghub": {
        "type": "github_release",
        "repo": "Slyvan25/OpenGHub",
        "asset_pattern": r"OpenGHub_([0-9\.]+)_amd64\.deb",
        "fallback_version": "0.1.4",
        "fallback_url": "https://github.com/Slyvan25/OpenGHub/releases/download/v0.1.4/OpenGHub_0.1.4_amd64.deb"
    },
    # 6A-192: official Bambu Lab release AppImage (the AUR / Chaotic name bambu-studio-bin is dead); the newest release that
    # is not a prerelease. The build checks the download against the SHA-256 of the release API (slacky_vendor_fetch.py).
    "bambu-studio": {
        "type": "github_release",
        "repo": "bambulab/BambuStudio",
        "asset_pattern": r"^BambuStudio_(?:ubuntu24\.04|ubu24)-v([0-9][0-9.]*)-[0-9]+\.AppImage$",
        "skip_prerelease": True
    }
}

def resolve_single(pid):
    if pid == "steam-devices":
        return pid, "1.0.0.61", "BUNDLED", "NONE", "NONE"
    if pid == "antigravity":
        ver = None   # 6A-306 (V4): no made-up fallback version; a failed lookup is "could not check"
        try:
            aur_url = "https://aur.archlinux.org/rpc/v5/info?arg[]=antigravity"
            raw = fetch_url_cached(aur_url, cache_dir, ttl=1800)
            if raw:
                data = json.loads(raw)
                results = data.get("results", [])
                if results:
                    ver = (results[0].get("Version") or "").split("-")[0] or ver
        except Exception:
            pass
        return (pid, ver, "AUR_ANTIGRAVITY", "NONE", "NONE") if ver else (pid, "NONE", "NONE", "NONE", "NONE")
    if pid == "claude-desktop":
        ver = None
        try:
            # 6A-310 (V6): the newest version in Anthropic's own apt index (the file is checked against that index at build time)
            import slacky_vendor_fetch as _vf
            ver = _vf.apt_latest_version("claude-desktop") or ver
        except Exception:
            pass
        return (pid, ver, "DEB_CLAUDE_DESKTOP", "NONE", "NONE") if ver else (pid, "NONE", "NONE", "NONE", "NONE")
    if pid == "claude-code":
        ver = None
        try:
            npm_url = "https://registry.npmjs.org/@anthropic-ai/claude-code-linux-x64/latest"
            raw = fetch_url_cached(npm_url, cache_dir, ttl=1800)
            if raw:
                data = json.loads(raw)
                ver = data.get("version") or ver
        except Exception:
            pass
        return (pid, ver, "NPM_CLAUDE_CODE", "NONE", "NONE") if ver else (pid, "NONE", "NONE", "NONE", "NONE")
    if pid == "gemini-cli":
        ver = None
        try:
            npm_url = "https://registry.npmjs.org/@google/gemini-cli/latest"
            raw = fetch_url_cached(npm_url, cache_dir, ttl=1800)
            if raw:
                data = json.loads(raw)
                ver = data.get("version") or ver
        except Exception:
            pass
        return (pid, ver, "NPM_GEMINI_CLI", "NONE", "NONE") if ver else (pid, "NONE", "NONE", "NONE", "NONE")
    if pid == "dvcp-aac":
        ver = None
        try:
            gh_url = "https://api.github.com/repos/GloriousEggroll/dvcp-aac/releases/latest"
            raw = fetch_url_cached(gh_url, cache_dir, ttl=1800)
            if raw:
                data = json.loads(raw)
                ver = (data.get("tag_name") or "").lstrip("v") or ver
        except Exception:
            pass
        return (pid, ver, "GITHUB_DVCP_AAC", "NONE", "NONE") if ver else (pid, "NONE", "NONE", "NONE", "NONE")
    if pid == "spacenav":
        pat = r'href=[\'\"]?(?:\./)?(spacenavd-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
        ver, url = fetch_match(pat, ["arch-extra", "cachyos", "chaotic-aur"], pid)
        ver = ver or "NONE"
        extra1 = ""
        e_ver1, e_url1 = fetch_match(r'href=[\'\"]?(?:\./)?(libspnav-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["arch-extra", "cachyos", "chaotic-aur"], "libspnav")
        if e_url1:
            extra1 = e_url1
        extra2 = ""
        e_ver2, e_url2 = fetch_match(r'href=[\'\"]?(?:\./)?(spnavcfg-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["arch-extra", "cachyos", "chaotic-aur"], "spnavcfg")
        if e_url2:
            extra2 = e_url2
        return pid, ver, url or "NONE", extra1 or "NONE", extra2 or "NONE"
    if pid == "gnome-disk-utility":
        pat = r'href=[\'\"]?(?:\./)?(gnome-disk-utility-(?:[0-9]+%3A)?([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
        ver, url = fetch_match(pat, ["cachyos-extra-v4", "cachyos-extra-v3", "arch-extra", "cachyos"], pid)
        ver = ver or "NONE"
        extra1 = ""
        e_ver1, e_url1 = fetch_match(r'href=[\'\"]?(?:\./)?(libhandy-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["cachyos-extra-v4", "cachyos-extra-v3", "arch-extra", "cachyos"], "libhandy")
        if e_url1:
            extra1 = e_url1
        extra2 = ""
        e_ver2, e_url2 = fetch_match(r'href=[\'\"]?(?:\./)?(libdvdread-([0-9][a-zA-Z0-9_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?', ["cachyos-extra-v4", "cachyos-extra-v3", "arch-extra", "cachyos"], "libdvdread")
        if e_url2:
            extra2 = e_url2
        return pid, ver, url or "NONE", extra1 or "NONE", extra2 or "NONE"
    if pid == "volt-gui":
        pat = r'href=[\'\"]?(?:\./)?(volt-gui(?:-bin)?-([0-9a-zA-Z_\.%:-]*)\.pkg\.tar\.zst)[\'\"]?'
        ver, url = fetch_match(pat, ["chaotic-aur", "chaotic-cdn", "cachyos"], pid)
        if not ver or not url:
            try:
                aur_url = "https://aur.archlinux.org/rpc/v5/info?arg[]=volt-gui-bin"
                raw = fetch_url_cached(aur_url, cache_dir, ttl=1800)
                if raw:
                    data = json.loads(raw)
                    results = data.get("results", [])
                    if results:
                        ver = results[0].get("Version") or "NONE"
                        url = f"{chaotic_fastest.rstrip('/')}/volt-gui-bin-{ver}-x86_64.pkg.tar.zst"
            except Exception:
                pass
        ver = ver or "NONE"
        return pid, ver, url or "NONE", "NONE", "NONE"
    if pid in ("mactahoe-icons", "mactahoe-cursors", "whitesur-icons", "whitesur-cursors"):
        # 6A-193: pinned versions (see THEME_PINS in the build recipe)
        ver = {"mactahoe-icons": "2026.09.10.r0.839848b9", "mactahoe-cursors": "2026.09.10.r0.839848b9",
               "whitesur-icons": "2026.09.10", "whitesur-cursors": "2025.04.05.r0.e190baf6"}[pid]
        return pid, ver, "GITHUB_THEME", "NONE", "NONE"
    if pid not in catalog:
        return pid, "NONE", "NONE", "NONE", "NONE"

    main_ver, main_url, lib32_url = None, None, "NONE"
    main_pat, lib32_pat, extra_pat, main_repos, lib32_repos = catalog[pid]

    if lib32_pat:
        main_matches = fetch_all_matches(main_pat, main_repos, pid)
        for repo_cand in ("multilib", "extra", "core"):
            try:
                api_url = f"https://archlinux.org/packages/{repo_cand}/x86_64/{pid}/json/"
                raw_json = fetch_url_cached(api_url, cache_dir, ttl=1800)
                if raw_json:
                    data = json.loads(raw_json)
                    fn = data.get("filename")
                    v = data.get("pkgver")
                    if fn and v:
                        cv = clean_pkg_version(pid, v)
                        url = f"https://geo.mirror.pkgbuild.com/{repo_cand}/os/x86_64/{fn}"
                        if cv not in main_matches:
                            main_matches[cv] = (url, v)
                        break
            except Exception:
                pass

        lib32_matches = fetch_all_matches(lib32_pat, lib32_repos or main_repos, f"lib32-{pid}")
        for l32_name in (f"lib32-{pid}", f"lib32-{pid.replace('-bin', '')}"):
            try:
                api_url = f"https://archlinux.org/packages/multilib/x86_64/{l32_name}/json/"
                raw_json = fetch_url_cached(api_url, cache_dir, ttl=1800)
                if raw_json:
                    data = json.loads(raw_json)
                    fn = data.get("filename")
                    v = data.get("pkgver")
                    if fn and v:
                        cv = clean_pkg_version(f"lib32-{pid}", v)
                        url = f"https://geo.mirror.pkgbuild.com/multilib/os/x86_64/{fn}"
                        if cv not in lib32_matches:
                            lib32_matches[cv] = (url, v)
                        break
            except Exception:
                pass

        common_vers = [v for v in main_matches if v in lib32_matches]
        if common_vers:
            common_vers.sort(key=parse_version_key)
            best_v = common_vers[-1]
            main_url, main_ver = main_matches[best_v]
            lib32_url, _ = lib32_matches[best_v]
    else:
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
                            if meta.get("skip_prerelease") and (rel.get("prerelease") or rel.get("draft")):
                                continue
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
                if (not main_ver or not main_url) and "fallback_url" in meta:
                    main_ver = meta.get("fallback_version", "0.1.4")
                    main_url = meta.get("fallback_url")

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
                    api_url = f"https://archlinux.org/packages/{repo_cand}/{ARCH_API_ARCH.get(pid, 'x86_64')}/{ARCH_API_NAMES.get(pid, pid)}/json/"
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

    if main_ver and main_url and major_held(pid, main_ver):
        main_ver = main_url = None   # 6A-296 (F3): also the Arch fall-back must not bring a new major
    if not main_ver or not main_url:
        return pid, "NONE", "NONE", "NONE", "NONE"

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

# 6A-196: the Hyprland suites (hyprland-noctalia, hyprland-core) and hyprpicker ship some of the same files, and the suites
# ship hyprpicker itself. Policy (coordinator recommendation, owner confirmation pending; change HERE only): the two suites
# and hyprpicker are mutually exclusive. Installing a suite replaces the other suite and a separate hyprpicker; hyprpicker
# alone is skipped when a suite that already contains it is installed.
GAMING_HYPR_SUITES="hyprland-noctalia hyprland-core"
GAMING_HYPR_PICKER_PKGS="hyprland-noctalia hyprland-core hyprpicker"   # base names (without the underpants- prefix) that own hyprpicker's files
# Extra cleanup_foreign_gaming_pkgs patterns of a Hyprland id: the other suite's and hyprpicker's real (underpants-/cachyos-gnome-) names.
gaming_hypr_exclusive_patterns() {
    local pkg_id="$1" s
    case "${pkg_id}" in
        hyprland-noctalia|hyprland-core)
            for s in ${GAMING_HYPR_SUITES} hyprpicker; do
                [ "${s}" = "${pkg_id}" ] && continue
                printf '%s\n' "underpants-${s}-[0-9]*" "cachyos-gnome-${s}-[0-9]*"
            done ;;
    esac
}
# Returns 0 and prints one plain sentence when pkg_id must be skipped because an installed suite already ships it.
gaming_hypr_exclusive_skip() {
    local pkg_id="$1" db="${GAMING_PKGLOG_DIR:-/var/log/packages}" s f
    [ "${pkg_id}" = "hyprpicker" ] || return 1
    for s in ${GAMING_HYPR_SUITES}; do
        for f in "${db}/underpants-${s}-"[0-9]* "${db}/cachyos-gnome-${s}-"[0-9]*; do
            [ -e "${f}" ] || continue
            echo "Hyprpicker is already part of the installed ${s} desktop, so it is not installed on its own."
            return 0
        done
    done
    return 1
}

# 6A-195: no link (or file) with a name the package rules refuse. Links: the Rust packer's plain-name rule (letters, digits and
# . _ + @ % , = : - / only, in the link's path and in its target). Files: names with shell-special characters or control
# characters (a stray "}" from an upstream typo). Dropped with one log line; the package is built without them.
gaming_drop_odd_names() {
    local staging_root="$1"
    [ -d "${staging_root}" ] || return 0
    local n
    n=$(python3 -I - "${staging_root}" << 'DROP_ODD_NAMES_EOF'
import os, re, sys
root = sys.argv[1]
plain = re.compile(r'^[A-Za-z0-9._+@%,=:/-]+$')
bad_file = re.compile(r'[\x00-\x1f\x7f{}$`\\;|&<>"]')
dropped = 0
for d, dirs, files in os.walk(root):
    rel_d = os.path.relpath(d, root)
    if rel_d == "install" or rel_d.startswith("install" + os.sep):
        continue
    for name in files + [x for x in dirs if os.path.islink(os.path.join(d, x))]:
        full = os.path.join(d, name)
        if os.path.islink(full):
            rel = os.path.relpath(full, root)
            if not plain.match(rel) or not plain.match(os.readlink(full)):
                os.unlink(full)
                dropped += 1
        elif bad_file.search(name):
            os.unlink(full)
            dropped += 1
print(dropped)
DROP_ODD_NAMES_EOF
) || return 1
    if [ "${n:-0}" -gt 0 ] 2>/dev/null; then
        log_info "Left out ${n} link(s) or file(s) with unusual names."
    fi
    return 0
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
            # 6A-4: only stray files no installed package lists (old builds); tracked files belong to pkgtools
            local stray
            for stray in /usr/share/applications/net.lutris.Lutris1.desktop /usr/share/pixmaps/*lutris* /usr/share/pixmaps/*Lutris*; do
                [ -e "${stray}" ] || continue
                grep -qsxF "${stray#/}" /var/log/packages/* && continue
                sudo rm -f "${stray}" 2>/dev/null || true
            done
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
            # 6A-187: only the older game-devices-udev build is replaced. The SlackBuilds.org steam-devices package is never
            # removed: it owns the Valve rules file 60-steam-input.rules (the footprint guard leaves that file out of our package)
            patterns=("game-devices-udev-[0-9]*")
            ;;
        lact)
            patterns=("lact-[0-9]*" "lact-r[0-9]*" "cachyos-gnome-lact-r[0-9]*")
            ;;
        openrgb)
            patterns=("openrgb-[0-9]*" "openrgb-r[0-9]*" "cachyos-gnome-openrgb-r[0-9]*")
            ;;
        solaar)
            patterns=("solaar-[0-9]*" "cachyos-gnome-solaar-[0-9]*")
            ;;
        openghub)
            patterns=("openghub-[0-9]*" "openghub-bin-[0-9]*" "openghub-git-[0-9]*" "cachyos-gnome-openghub-[0-9]*")
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
            patterns=("google-chrome-[0-9]*" "google-chrome-stable-[0-9]*" "google-chrome-stable_*" "google-chrome-the-latest-*")
            ;;
        microsoft-edge)
            patterns=("microsoft-edge-[0-9]*" "microsoft-edge-stable-[0-9]*" "microsoft-edge-stable-bin-[0-9]*" "microsoft-edge-stable_*" "microsoft-edge-bin-[0-9]*")
            ;;
        opera)
            patterns=("opera-[0-9]*" "opera-ffmpeg-codecs-[0-9]*")
            ;;
        bambu-studio)
            # 6A-192: the older build of this program was called bambu-studio (built from the dead AUR name)
            patterns=("bambu-studio-[0-9]*")
            ;;
        obs-studio)
            patterns=("obs-studio-[0-9]*" "obs-[0-9]*")
            ;;
        discord)
            patterns=("discord-[0-9]*" "discord-canary-[0-9]*" "discord-ptb-[0-9]*")
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
        antigravity)
            patterns=("antigravity-[0-9]*" "antigravity-bin-[0-9]*" "antigravity-ide-[0-9]*")
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
            patterns=("rtl8821cu-[0-9]*" "rtl8821cu-dkms-[0-9]*" "rtl8821cu-dkms-git-[0-9]*" "rtl8821cu-morrownr-dkms-git-[0-9]*")
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
        hyprland-noctalia|hyprland-core)
            patterns=("hyprland-[0-9]*" "hyprland-noctalia-[0-9]*" "hyprland-core-[0-9]*" "noctalia-[0-9]*" "noctalia-shell-[0-9]*" "cachyos-gnome-hyprland-[0-9]*" "underpants-hyprland-[0-9]*")
            # 6A-196: the patterns above never matched the installed underpants- names of the other suite; add them (and hyprpicker)
            while IFS= read -r _hx; do [ -n "${_hx}" ] && patterns+=("${_hx}"); done < <(gaming_hypr_exclusive_patterns "${pkg_id}")
            ;;
    esac

    # Antigravity is upgraded atomically via upgradepkg old%new to protect running instances
    if [ "${pkg_id}" = "antigravity" ]; then
        return 0
    fi

    # 6A-4: match the installed package's exact base name (name-version-arch-build stripped), never a loose
    # filename glob. Runs AFTER the new underpants-<id> is installed, so removepkg keeps every file the new
    # package owns and the app is never missing if the install fails. The package being installed is left to
    # upgradepkg; official Slackware packages (build field without a tag) are never removed.
    local new_base="underpants-${pkg_id}"
    local p bname base build pat name
    for p in /var/log/packages/*; do
        [ -f "${p}" ] || continue
        bname="${p##*/}"
        base="${bname%-*-*-*}"
        build="${bname##*-}"
        [ "${base}" != "${bname}" ] || continue
        [ "${base}" = "${new_base}" ] && continue
        for pat in "${patterns[@]}" "underpants-${pkg_id}-[0-9]*" "cachyos-gnome-${pkg_id}-[0-9]*"; do
            name="${pat%-\[0-9\]\*}"
            name="${name%-r\[0-9\]\*}"
            # shellcheck disable=SC2053
            [[ "${base}" == ${name} ]] || continue
            if [[ "${build}" =~ ^[0-9]+$ ]]; then
                log_warn "Leaving ${bname} installed: it is an official Slackware package."
                break
            fi
            log_info "Removing older or superseded package: ${bname}..."
            validate_privileges
            sudo "${PKG_REMOVE_CMD}" "${bname}" >/dev/null 2>&1 || log_warn "Could not remove ${bname}. Remove it by hand with: removepkg ${bname}"
            break
        done
    done
}

# 6A-6c: rc.local / rc.local_shutdown block helpers (spec: docs/rclocal_spec.md). Printed into each curated package's
# doinst.sh and douninst.sh, so the package works without slacky-update installed. Blocks are marker-delimited and
# self-contained; every change is syntax-checked (sh -n) before and after, written via a temp file in the same directory
# and swapped in with a .slacky-bak backup; unbalanced markers or a broken file make it refuse and leave the file as is.
slacky_rc_helpers() {
    cat << 'SU_RC_HELPERS_EOF'
su_rc_log() { echo "slacky-update: rc.local: $*" >&2; }
su_rc_syntax_ok() { [ -z "$(sh -n "$1" 2>&1)" ]; }
su_rc_markers_ok() {
  awk '
    { l=$0; sub(/\r$/,"",l) }
    l ~ /^# >>> slacky-update:[A-Za-z0-9._+-]+ >>>$/ {
      n=l; sub(/^# >>> slacky-update:/,"",n); sub(/ >>>$/,"",n)
      if (open != "") bad=1; open=n; next }
    l ~ /^# <<< slacky-update:[A-Za-z0-9._+-]+ <<<$/ {
      n=l; sub(/^# <<< slacky-update:/,"",n); sub(/ <<<$/,"",n)
      if (open == "" || open != n) bad=1; open=""; next }
    END { exit (bad || open != "") }' "$1"
}
su_rc_has_block() { awk -v b="# >>> slacky-update:$2 >>>" '{ l=$0; sub(/\r$/,"",l) } l==b { f=1 } END { exit !f }' "$1"; }
su_rc_commit() { cp -p "$1" "$1.slacky-bak" && mv -f "$2" "$1"; }
su_rc_add() { # FILE NAME < body
  su_f=$(readlink -f "$1") || return 1; su_n=$2; su_body=$(cat)
  [ -f "$su_f" ] || return 1
  su_rc_markers_ok "$su_f" || { su_rc_log "unbalanced markers in $su_f, left unchanged"; return 1; }
  su_rc_syntax_ok "$su_f" || { su_rc_log "$su_f has a syntax error, left unchanged"; return 1; }
  su_rc_has_block "$su_f" "$su_n" && return 0
  if tr -d '\n' <"$su_f" | grep -q "$(printf '\r')"; then su_rc_log "$su_f has CRLF line endings, left unchanged"; return 1; fi
  if grep -v '^[[:space:]]*#' "$su_f" | grep -q "rc\.$su_n"; then return 0; fi
  if tr -d '\r' <"$su_f" | grep -v '^[[:space:]]*\(#.*\)\{0,1\}$' | tail -n 1 | grep -q '^[[:space:]]*exit\([[:space:]]\|$\)'; then
    su_rc_log "$su_f ends with exit, left unchanged"; return 1; fi
  su_t=$(mktemp "$su_f.slacky.XXXXXX") || return 1
  cp -p "$su_f" "$su_t" || { rm -f "$su_t"; return 1; }
  { cat "$su_f"; [ -n "$(tail -c 1 "$su_f")" ] && printf '\n'
    printf '\n# >>> slacky-update:%s >>>\n%s\n# <<< slacky-update:%s <<<\n' "$su_n" "$su_body" "$su_n"; } >"$su_t"
  if su_rc_markers_ok "$su_t" && su_rc_syntax_ok "$su_t"; then su_rc_commit "$su_f" "$su_t"
  else rm -f "$su_t"; su_rc_log "result would be invalid, $su_f unchanged"; return 1; fi
}
su_rc_remove() { # FILE NAME
  su_f=$(readlink -f "$1") || return 1; su_n=$2
  [ -f "$su_f" ] || return 0
  su_rc_has_block "$su_f" "$su_n" || return 0
  su_rc_markers_ok "$su_f" || { su_rc_log "unbalanced markers in $su_f, left unchanged"; return 1; }
  su_rc_syntax_ok "$su_f" || { su_rc_log "$su_f has a syntax error, left unchanged"; return 1; }
  su_t=$(mktemp "$su_f.slacky.XXXXXX") || return 1
  cp -p "$su_f" "$su_t" || { rm -f "$su_t"; return 1; }
  awk -v b="# >>> slacky-update:$su_n >>>" -v e="# <<< slacky-update:$su_n <<<" '
    { l=$0; sub(/\r$/,"",l) }
    skip { if (l == e) skip=0; next }
    l == b { hold=0; skip=1; next }
    { if (hold) print held; hold=0
      if (l == "") { held=$0; hold=1; next }
      print }
    END { if (hold) print held }' "$su_f" >"$su_t"
  if su_rc_markers_ok "$su_t" && su_rc_syntax_ok "$su_t" && ! su_rc_has_block "$su_t" "$su_n"; then su_rc_commit "$su_f" "$su_t"
  else rm -f "$su_t"; su_rc_log "result would be invalid, $su_f unchanged"; return 1; fi
}
su_rc_migrate() { # FILE NAME VERB "Comment text"  - exact old 4-line unmarked block -> marked block
  su_f=$(readlink -f "$1") || return 1; su_n=$2; su_v=$3; su_c="# $4:"
  [ -f "$su_f" ] || return 0
  { su_rc_markers_ok "$su_f" && su_rc_syntax_ok "$su_f"; } || return 1
  su_rc_has_block "$su_f" "$su_n" && return 0
  su_t=$(mktemp "$su_f.slacky.XXXXXX") || return 1
  cp -p "$su_f" "$su_t"
  awk -v c="$su_c" -v n="$su_n" -v v="$su_v" '
    { L[NR]=$0; sub(/\r$/,"",L[NR]); R[NR]=$0 }
    END { i=1
      while (i<=NR) {
        if (L[i]==c && L[i+1]=="if [ -x /etc/rc.d/rc." n " ]; then" && L[i+2]=="  /etc/rc.d/rc." n " " v && L[i+3]=="fi") {
          found=1; i+=4
          print "# >>> slacky-update:" n " >>>"; print "if [ -x /etc/rc.d/rc." n " ]; then"
          print "  /etc/rc.d/rc." n " " v; print "fi"; print "# <<< slacky-update:" n " <<<"; continue }
        print R[i]; i++ }
      exit found?0:3 }' "$su_f" >"$su_t"
  if [ $? -ne 0 ]; then rm -f "$su_t"; return 0; fi
  if su_rc_markers_ok "$su_t" && su_rc_syntax_ok "$su_t"; then su_rc_commit "$su_f" "$su_t"
  else rm -f "$su_t"; return 1; fi
}
# Daemons whose packages may ship /etc/rc.d/rc.NAME: "NAME|Description" (description = the old block comment)
SU_RC_DAEMONS="ananicy-cpp|Ananicy C++ auto-nice daemon
lact|LACT GPU control daemon
scx|Sched-EXT gaming scheduler
coolercontrol|CoolerControl daemon
asusd|ASUS control daemon
syncthing|Syncthing service
dmemcg-booster|dmemcg-booster VRAM daemon"
# 6A-83: kernel modules to load at boot, "MODULE|file that shows the package is installed". Slackware never reads
# modules-load.d; its place for this is /etc/rc.d/rc.modules.local (a sysadmin file pkgtools never overwrites).
SU_RC_MODULES="zenpower|/etc/modprobe.d/zenpower.conf
v4l2loopback|/etc/modprobe.d/v4l2loopback.conf
i2c-dev|/usr/bin/ddcui"
su_mod_listed() { grep -v '^[[:space:]]*#' "$1" 2>/dev/null | grep -qE "modprobe([[:space:]]+-[a-z]+)*[[:space:]]+$2([[:space:]]|\$)"; }
SU_RC_HELPERS_EOF
}

# 6A-166 / 6A-168: the DKMS source folders a package ships, one line each: "folder|module|version". Names come from the
# folder's own dkms.conf (same fallbacks as the doinst block); an entry with odd characters is left out.
slacky_dkms_own_entries() {
    local staging_root="$1" dconf ddir dname mod_name mod_ver
    for dconf in "${staging_root}"/usr/src/*/dkms.conf; do
        [ -f "${dconf}" ] || continue
        ddir=$(dirname "${dconf}")
        dname=$(basename "${ddir}")
        mod_name=$(grep -E '^\s*PACKAGE_NAME=' "${dconf}" 2>/dev/null | head -n1 | cut -d= -f2 | tr -d '"'\'' ' || true)
        mod_ver=$(grep -E '^\s*PACKAGE_VERSION=' "${dconf}" 2>/dev/null | head -n1 | cut -d= -f2 | tr -d '"'\'' ' || true)
        [ -z "${mod_name}" ] && mod_name=$(echo "${dname}" | sed -E 's/-[0-9].*//')
        [ -z "${mod_ver}" ] && mod_ver=$(echo "${dname}" | sed -E 's/^[a-zA-Z0-9_\-]+-//')
        [[ "${dname}|${mod_name}|${mod_ver}" =~ ^[A-Za-z0-9._+-]+\|[A-Za-z0-9._+-]+\|[A-Za-z0-9._+-]+$ ]] || continue
        printf '%s|%s|%s\n' "${dname}" "${mod_name}" "${mod_ver}"
    done
}

# --- [ TRANSMUTATION & BUILD ENGINE ] ---
# 6A-64: write the generated Hyprland hardware environment into a marked block of the user's own
# ~/.config/hypr/hyprland.env. Lines outside the block (the user's own) are never touched; the file is written as the
# user (never root-owned in the home directory); a missing user (pure root context) means nothing is written.
write_user_hypr_env_block() {
    local content="$1" user="${SUDO_USER:-${USER:-}}" home
    [ -n "${user}" ] && [ "${user}" != "root" ] || return 0
    home=$(getent passwd "${user}" 2>/dev/null | cut -d: -f6)
    [ -n "${home}" ] && [ -d "${home}" ] || return 0
    local f="${home}/.config/hypr/hyprland.env"
    local py='
import os, sys
f, content = sys.argv[1], sys.argv[2].rstrip("\n")
b = "# >>> slacky-update: hardware environment (generated; put your own lines outside this block) >>>"
e = "# <<< slacky-update: hardware environment <<<"
old = open(f, encoding="utf-8").read() if os.path.exists(f) else ""
keep, inside = [], False
for line in old.splitlines():
    if line.strip() == b:
        inside = True
        continue
    if line.strip().startswith(e):
        inside = False
        rest = line.strip()[len(e):].strip()
        if rest:
            keep.append(rest)
        continue
    if not inside:
        keep.append(line)
while keep and not keep[-1].strip():
    keep.pop()
out = "\n".join(keep + ([""] if keep else []) + [b, content, e]) + "\n"
os.makedirs(os.path.dirname(f), exist_ok=True)
tmp = f + ".slacky-tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    fh.write(out)
os.replace(tmp, f)
'
    if [ "$(id -u)" -eq 0 ]; then
        sudo -u "${user}" python3 -I -c "${py}" "${f}" "${content}" 2>/dev/null || true
    else
        python3 -I -c "${py}" "${f}" "${content}" 2>/dev/null || true
    fi
}

# 6A-75/6A-78: display-GPU facts for the Hyprland configurator, read from world-readable sysfs only (no lspci, no
# root). SLACKY_SYSFS_ROOT lets tests point it at a fake tree. Sets:
#   HYPR_DRM_ORDER     PCI slots for AQ_DRM_DEVICES (primary first, then every other GPU with a connected output);
#                      empty on a single GPU, or when only one GPU drives outputs on a desktop (no variable needed)
#   HYPR_NV_SW_CURSOR  true only for NVIDIA older than Turing (device id below 0x1e00, i.e. older than the GTX 16xx
#                      series) or an NVIDIA card whose id cannot be read; newer cards use Hyprland's own default
hypr_gpu_facts() {
    local sys="${SLACKY_SYSFS_ROOT:-}/sys"
    HYPR_DRM_ORDER=""
    HYPR_NV_SW_CURSOR=false
    HYPR_NV_DISPLAY=false   # 6A-82: an NVIDIA card drives the screens (not a render-only laptop dGPU)
    # 6A-128: HYPR_NV_BOUND = an NVIDIA card is bound to the nvidia driver (false on nouveau);
    # HYPR_DISPLAY_VENDOR = vendor id of the GPU that drives the screens (a GPU with connected outputs wins over boot_vga)
    HYPR_NV_BOUND=false
    HYPR_DISPLAY_VENDOR=""
    local nv_boot=false nv_conn=false other_conn=false drv
    local boot_ven="" boot_conn=false first_out_ven="" panel_ven=""
    local card dev cls ven did slot boot st name conn panel n=0
    local primary="" primary_panel=false boot_slot="" first_out="" others=""
    for card in "${sys}"/class/drm/card[0-9]*; do
        case "${card##*/}" in *-*) continue ;; esac
        dev="${card}/device"
        [ -e "${dev}" ] || continue
        cls=$(cat "${dev}/class" 2>/dev/null || true)
        case "${cls}" in 0x03*) ;; *) continue ;; esac
        slot=$(basename "$(readlink -f "${dev}")")
        ven=$(cat "${dev}/vendor" 2>/dev/null || true)
        did=$(cat "${dev}/device" 2>/dev/null || true)
        boot=$(cat "${dev}/boot_vga" 2>/dev/null || echo 0)
        n=$((n + 1))
        if [ "${ven}" = "0x10de" ]; then
            case "${did}" in
                0x[0-9a-fA-F]*) [ $((did)) -lt $((0x1e00)) ] && HYPR_NV_SW_CURSOR=true ;;
                *) HYPR_NV_SW_CURSOR=true ;;
            esac
        fi
        conn=false
        panel=false
        for st in "${card}"-*/status; do
            [ -f "${st}" ] || continue
            [ "$(cat "${st}" 2>/dev/null)" = "connected" ] || continue
            conn=true
            name="${st%/status}"
            name="${name##*/}"
            case "${name#*-}" in eDP*|LVDS*|DSI*) panel=true ;; esac
        done
        if [ "${ven}" = "0x10de" ]; then
            [ "${boot}" = "1" ] && nv_boot=true
            [ "${conn}" = "true" ] && nv_conn=true
            drv=$(readlink "${dev}/driver" 2>/dev/null || true)
            [ "${drv##*/}" = "nvidia" ] && HYPR_NV_BOUND=true
        elif [ "${conn}" = "true" ]; then
            other_conn=true
        fi
        if [ "${panel}" = "true" ] && [ -z "${primary}" ]; then
            primary="${slot}"
            primary_panel=true
            panel_ven="${ven}"
        fi
        if [ "${boot}" = "1" ]; then
            boot_slot="${slot}"
            boot_ven="${ven}"
            boot_conn="${conn}"
        fi
        if [ "${conn}" = "true" ]; then
            [ -z "${first_out}" ] && first_out="${slot}" && first_out_ven="${ven}"
            others="${others} ${slot}"
        fi
    done
    if [ "${nv_boot}" = "true" ] && [ "${other_conn}" != "true" ] || { [ "${nv_conn}" = "true" ] && [ "${other_conn}" != "true" ]; }; then
        HYPR_NV_DISPLAY=true
    fi
    if [ -n "${panel_ven}" ]; then
        HYPR_DISPLAY_VENDOR="${panel_ven}"
    elif [ "${boot_conn}" = "true" ] || { [ -z "${first_out_ven}" ] && [ -n "${boot_ven}" ]; }; then
        HYPR_DISPLAY_VENDOR="${boot_ven}"
    else
        HYPR_DISPLAY_VENDOR="${first_out_ven}"
    fi
    [ "${n}" -ge 2 ] || return 0
    [ -n "${primary}" ] || primary="${boot_slot:-${first_out}}"
    [ -n "${primary}" ] || return 0
    local order="${primary}" s
    for s in ${others}; do
        [ "${s}" = "${primary}" ] || order="${order} ${s}"
    done
    # A desktop whose monitors all hang off one GPU needs no variable (Hyprland picks that GPU itself)
    if [ "${order}" = "${primary}" ] && [ "${primary_panel}" != "true" ]; then
        return 0
    fi
    HYPR_DRM_ORDER="${order}"
}

# 6A-128: true when an AMD GPU drives the screens (after hypr_gpu_facts). Unknown display vendor keeps the old rule
# (AMD present and no Intel GPU), so a machine sysfs cannot describe is not changed.
hypr_display_is_amd() {
    case "${HYPR_DISPLAY_VENDOR:-}" in
        0x1002) return 0 ;;
        "") [ "${HAS_INTEL:-false}" != "true" ]; return ;;
    esac
    return 1
}

# 6A-76: true (exit 0) when __GLX_VENDOR_LIBRARY_NAME=nvidia is still needed on a single-NVIDIA machine. It is only
# dropped after a live check proves that X11 programs already get NVIDIA's OpenGL without it; when the check cannot run
# (no display, no glxinfo, run without the user's session) the variable is kept, so nothing can get worse.
hypr_glx_vendor_var_needed() {
    [ -n "${DISPLAY:-}" ] || return 0
    command -v glxinfo >/dev/null 2>&1 || return 0
    local out
    out=$(env -u LD_LIBRARY_PATH -u __GLX_VENDOR_LIBRARY_NAME timeout 5 glxinfo -B 2>/dev/null || true)
    case "${out}" in
        *"OpenGL vendor string: NVIDIA"*) return 1 ;;
    esac
    return 0
}

# 6A-80: writes modules/hdr.lua.suggestions from the EDID of every connected monitor that supports HDR (PQ). The file
# is a template refreshed by the tool, never loaded by Hyprland (Lua only loads *.lua) and never a user file. Reads
# world-readable EDID; serial numbers are never written. $1 = target modules dir.
write_hypr_hdr_suggestions() {
    local mods="$1"
    [ -d "${mods}" ] || return 0
    local py='
import glob, os, sys
sysroot, out = sys.argv[1], sys.argv[2]
def name_and_range(e):
    name, rng = "", None
    for off in (54, 72, 90, 108):
        d = e[off:off + 18]
        if len(d) < 18 or d[0] or d[1]:
            continue
        if d[3] == 0xFC:
            name = d[5:18].split(b"\n")[0].decode("ascii", "replace").strip()
        elif d[3] == 0xFD:
            lo, hi = d[5], d[6]
            if d[4] & 0x01: lo += 255
            if d[4] & 0x02: hi += 255
            rng = (lo, hi)
    return name, rng
def hdr_info(e):
    eotf = []
    for i in range(1, len(e) // 128):
        b = e[i * 128:(i + 1) * 128]
        if len(b) < 4 or b[0] != 0x02:
            continue
        p, end = 4, min(b[2], 127)
        while p < end:
            tag, ln = b[p] >> 5, b[p] & 0x1F
            blk = b[p + 1:p + 1 + ln]
            if tag == 7 and ln >= 2 and blk[0] == 6:
                bits = blk[1]
                if bits & 0x04: eotf.append("PQ")
                if bits & 0x08: eotf.append("HLG")
            p += 1 + ln
    return eotf
lines = []
for st in sorted(glob.glob(os.path.join(sysroot, "sys/class/drm/card*-*/status"))):
    try:
        if open(st).read().strip() != "connected":
            continue
        e = open(os.path.join(os.path.dirname(st), "edid"), "rb").read()
    except OSError:
        continue
    if len(e) < 128 or e[:8] != bytes([0, 255, 255, 255, 255, 255, 255, 0]):
        continue
    eotf = hdr_info(e)
    if "PQ" not in eotf:
        continue
    conn = os.path.basename(os.path.dirname(st)).split("-", 1)[1]
    name, rng = name_and_range(e)
    desc = name or "monitor"
    vrr = ""
    if rng and rng[1] > rng[0]:
        vrr = ", variable refresh %d-%d Hz" % rng
    lines.append("-- %s: %s, HDR (%s)%s" % (conn, desc, "+".join(eotf), vrr))
    lines.append("--   add to the existing hl.monitor line for this output:  bitdepth = 10, cm = \"hdr\"" + (", vrr = 3" if vrr else ""))
    lines.append("--   example: hl.monitor({ output = \"%s\", mode = \"preferred\", position = \"auto\", scale = 1.0, bitdepth = 10, cm = \"hdr\"%s })" % (conn, ", vrr = 3" if vrr else ""))
    lines.append("")
if not lines:
    sys.exit(0)
head = [
    "-- HDR suggestions made by slacky-update from your monitors (EDID). This file is NOT loaded by Hyprland.",
    "-- To use a line: copy the keys into modules/monitors.lua (same output name) and save; Hyprland applies it at once.",
    "-- vrr = 3 turns variable refresh on for fullscreen games and videos only. Remove the keys again to undo.",
    "-- This file is rewritten by slacky-update; keep your own changes in monitors.lua.",
    "",
]
tmp = out + ".slacky-tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    fh.write("\n".join(head + lines))
os.replace(tmp, out)
'
    python3 -I -c "${py}" "${SLACKY_SYSFS_ROOT:-/}" "${mods}/hdr.lua.suggestions" 2>/dev/null || true
}

# SS-4 / 6A-105 (owner decision 2026-10-13): one menu writer. The limine-snapper-sync snapper plugin stays (snapshots
# must reach the Limine menu), but in our build:
#  - the plugin only places an order (/var/cache/slacky-update/boot-menu-pending) while a slacky-update run holds the
#    run lock /run/lock/slacky-update.lock; the run's boot commit or the hourly job rebuilds the menu once;
#  - /usr/bin/limine-snapper-sync does the same check, and fails closed when the boot lock
#    /run/lock/boot-partition.lock cannot be taken: upstream ignored the timeout (mutex_lock's return value was not
#    checked) and wrote limine.conf, enrolled and signed the boot loader unlocked; it also deleted and recreated the
#    lock file when it could not open it (a new file means no exclusion at all).
# Applied to the staging tree at build time. Returns 1 when an anchor is missing (upstream changed): the caller then
# refuses to build the package rather than ship an unpatched menu writer.
patch_limine_snapper_sync_staging() {
    local root="${1:-}"
    local wrapper="${root}/usr/bin/limine-snapper-sync"
    local plugins=() p
    for p in "${root}/usr/lib64/snapper/plugins/10-limine-snapper-sync" "${root}/usr/lib/snapper/plugins/10-limine-snapper-sync"; do
        [ -f "${p}" ] && plugins+=("${p}")
    done
    [ -n "${root}" ] && [ -f "${wrapper}" ] && [ "${#plugins[@]}" -gt 0 ] || return 1

    local guard_plugin guard_wrapper
    guard_plugin=$(cat << 'LSS_PLUGIN_EOF'
# slacky-update SS-4 (6A-105): one menu writer. While a slacky-update run holds its run lock, only leave an order:
# the run's boot commit (or the hourly slacky-snapper-limine-sync job) rebuilds, enrolls and signs the menu once.
case "${1:-}" in
create-snapshot-post | delete-snapshot-post | modify-snapshot-post)
	if [[ "${2:-}" == "/" ]] && [[ -e /run/lock/slacky-update.lock ]] \
		&& ! flock -n /run/lock/slacky-update.lock true 2>/dev/null; then
		mkdir -p /var/cache/slacky-update 2>/dev/null || true
		: >/var/cache/slacky-update/boot-menu-pending 2>/dev/null || true
		exit 0
	fi
	;;
esac
LSS_PLUGIN_EOF
)
    guard_wrapper=$(cat << 'LSS_WRAPPER_EOF'
# slacky-update SS-4 (6A-105): one menu writer.
slacky_menu_order() {
	mkdir -p /var/cache/slacky-update 2>/dev/null || true
	: >/var/cache/slacky-update/boot-menu-pending 2>/dev/null || true
}
# Fail closed: without the boot lock nothing is written; the order is served by the next lock holder or the hourly job.
slacky_menu_order_fail_closed() {
	slacky_menu_order
	ENABLE_MUTEX=false
	warning_msg $"The startup menu is busy. It will be updated automatically later."
	exit 75
}
# A slacky-update run holds its run lock: its own boot commit rebuilds the menu once, so only leave the order.
if ! $RESTORE_MODE && [[ -e /run/lock/slacky-update.lock ]] && ! flock -n /run/lock/slacky-update.lock true 2>/dev/null; then
	slacky_menu_order
	ENABLE_MUTEX=false
	exit 0
fi
LSS_WRAPPER_EOF
)

    local f tmp
    for f in "${plugins[@]}"; do
        grep -q 'slacky-update SS-4' "${f}" && continue
        tmp="${f}.ss4.$$"
        # after the first "set -euo pipefail" (before any snapshot work or async start)
        SS4_GUARD="${guard_plugin}" awk 'BEGIN{d=0; g=ENVIRON["SS4_GUARD"]} {print} !d && $0=="set -euo pipefail" {print ""; print g; d=1}' "${f}" > "${tmp}" || { rm -f "${tmp}"; return 1; }
        grep -q 'slacky-update SS-4' "${tmp}" || { rm -f "${tmp}"; return 1; }
        cat "${tmp}" > "${f}" && rm -f "${tmp}"
    done

    if ! grep -q 'slacky-update SS-4' "${wrapper}"; then
        tmp="${wrapper}.ss4.$$"
        # 1. no delete-and-recreate of the lock file; 2. a failed lock = fail closed; 3. run-lock check before the lock
        SS4_GUARD="${guard_wrapper}" awk '
            BEGIN { r = 0; m = 0; i = 0; g = ENVIRON["SS4_GUARD"] }
            /^[ \t]*rm -f "\$\{BOOT_PARTITION_LOCK\}"[ \t]*$/ && !r { print "\t\treturn 1"; skip = 1; r = 1; next }
            skip == 1 && /^[ \t]*exec 200>"\$\{BOOT_PARTITION_LOCK\}"[ \t]*$/ { skip = 0; next }
            $0 == "if $ENABLE_MUTEX; then" && !i { print g; print ""; i = 1 }
            $0 == "\tmutex_lock \"${SCRIPT_NAME}\"" && !m { print "\tmutex_lock \"${SCRIPT_NAME}\" || slacky_menu_order_fail_closed"; m = 1; next }
            { print }
            END { if (!(r && m && i)) exit 3 }
        ' "${wrapper}" > "${tmp}" || { rm -f "${tmp}"; return 1; }
        if grep -q 'rm -f "${BOOT_PARTITION_LOCK}"' "${tmp}" \
            || ! grep -q 'mutex_lock "${SCRIPT_NAME}" || slacky_menu_order_fail_closed' "${tmp}" \
            || ! grep -q 'slacky-update SS-4' "${tmp}"; then
            rm -f "${tmp}"
            return 1
        fi
        cat "${tmp}" > "${wrapper}" && rm -f "${tmp}"
    fi
    bash -n "${wrapper}" 2>/dev/null || return 1
    for f in "${plugins[@]}"; do
        bash -n "${f}" 2>/dev/null || return 1
    done
    return 0
}

# 6A-125: one plain error and the build's staging is removed. Uses the caller's local staging_base (bash dynamic scope);
# the caller returns 1 itself.
# 6A-295 (V1): a file downloaded from a GitHub release must equal the SHA-256 ("digest") and size that the GitHub release API names for
# that exact asset. Any doubt (no digest, other size, API unreachable, rate limit) refuses the file with one plain sentence.
# $1 = downloaded file, $2 = the https://github.com/<owner>/<repo>/releases/download/<tag>/<name> address it came from.
gaming_verify_github_asset() {
    python3 -I - "$1" "$2" "$(_slacky_vendor_fetch_dir)" << 'PYVERIFY_GH_ASSET'
import sys, os, re, json, urllib.parse, urllib.error
path, url, lib_dir = sys.argv[1], sys.argv[2], sys.argv[3]
if not lib_dir or not os.path.isfile(os.path.join(lib_dir, "slacky_vendor_fetch.py")):
    raise SystemExit("slacky_vendor_fetch.py was not found, so the download cannot be verified")
sys.path.insert(0, lib_dir)
import slacky_vendor_fetch as vf
m = re.fullmatch(r"https://github\.com/([A-Za-z0-9._-]{1,100}/[A-Za-z0-9._-]{1,100})/releases/download/([^/?#]+)/([^/?#]+)", url)
if not m:
    raise SystemExit("the download address is not a GitHub release address")
repo, tag, name = m.group(1), urllib.parse.unquote(m.group(2)), urllib.parse.unquote(m.group(3))
try:
    body = vf._read_capped("https://api.github.com/repos/%s/releases/tags/%s" % (repo, urllib.parse.quote(tag, safe="")), 4 << 20, 20)
    rel = json.loads(body)
except urllib.error.HTTPError as exc:
    if exc.code in (403, 429):
        raise SystemExit("GitHub is limiting requests right now, please try again in an hour")
    raise SystemExit("GitHub does not know this release")
except Exception:
    raise SystemExit("GitHub could not be asked for the checksum")
want = None
for a in (rel.get("assets") or []) if isinstance(rel, dict) else []:
    if isinstance(a, dict) and a.get("name") == name and a.get("state") == "uploaded":
        if urllib.parse.unquote(str(a.get("browser_download_url"))) == urllib.parse.unquote(url):
            want = a
        break
if want is None:
    raise SystemExit("GitHub does not list this file")
dg, size = want.get("digest"), want.get("size")
if not isinstance(dg, str) or not re.fullmatch(r"sha256:[0-9a-fA-F]{64}", dg):
    raise SystemExit("GitHub publishes no checksum for this file")
if not isinstance(size, int) or isinstance(size, bool) or os.path.getsize(path) != size:
    raise SystemExit("the file has the wrong size")
if vf.file_digest(path, "sha256") != dg[7:].lower():
    raise SystemExit("the checksum does not match")
PYVERIFY_GH_ASSET
}

# 6A-313 (N4): free space before a curated build. Downloads, the unpacked tree and the finished package all live in the build
# folder, and the install writes under /opt (and /). One plain sentence names the space needed and where; nothing is created.
# Needs can be overridden for tests with SLACKY_BUILD_NEED_MB / SLACKY_OPT_NEED_MB; SLACKY_OPT_DIR picks the install folder.
gaming_space_precheck() {
    local build_dir="$1" opt_dir="${SLACKY_OPT_DIR:-/opt}"
    local need_build="${SLACKY_BUILD_NEED_MB:-3072}" need_opt="${SLACKY_OPT_NEED_MB:-1536}"
    local b_line o_line b_dev o_dev b_free o_free
    while [ -n "${build_dir}" ] && [ ! -d "${build_dir}" ] && [ "${build_dir}" != "/" ]; do build_dir=$(dirname "${build_dir}"); done
    [ -d "${opt_dir}" ] || opt_dir="/"
    b_line=$(df -Pm "${build_dir:-/}" 2>/dev/null | awk 'NR==2{print $1" "$4}') || true
    o_line=$(df -Pm "${opt_dir}" 2>/dev/null | awk 'NR==2{print $1" "$4}') || true
    b_dev="${b_line%% *}"; b_free="${b_line##* }"
    o_dev="${o_line%% *}"; o_free="${o_line##* }"
    # a lookup that fails is not a reason to stop a build
    [[ "${b_free}" =~ ^[0-9]+$ ]] || return 0
    if [ "${b_dev}" = "${o_dev}" ] && [[ "${o_free}" =~ ^[0-9]+$ ]]; then
        if [ "${b_free}" -lt $((need_build + need_opt)) ]; then
            log_error "There is not enough free disk space to build this: about $((need_build + need_opt)) MB are needed but only ${b_free} MB are free on ${build_dir:-/}. Nothing was changed."
            return 1
        fi
        return 0
    fi
    if [ "${b_free}" -lt "${need_build}" ]; then
        log_error "There is not enough free disk space to build this: about ${need_build} MB are needed in ${build_dir:-/} but only ${b_free} MB are free. Nothing was changed."
        return 1
    fi
    if [[ "${o_free}" =~ ^[0-9]+$ ]] && [ "${o_free}" -lt "${need_opt}" ]; then
        log_error "There is not enough free disk space to install this: about ${need_opt} MB are needed in ${opt_dir} but only ${o_free} MB are free. Nothing was changed."
        return 1
    fi
    return 0
}

gaming_build_failed() {
    log_error "${1}"
    if [ -n "${staging_base:-}" ] && [ -d "${staging_base}" ]; then
        rm -rf "${staging_base}" 2>/dev/null || true
    fi
    return 0
}

# 6A-129 (M7): admin-editable config files a curated package ships as .new (Slackware config() pattern)
GAMING_CONFIG_NEW_FILES="etc/scx_loader.toml etc/ananicy.d/ananicy.conf"  # not modprobe.d: 6A-83 uses those files as package markers

# 6A-129: the first upgrade from a package that listed the plain file deletes it (upgradepkg removes files the new
# package no longer lists). Put back the copy saved before the upgrade and drop an identical .new.
# $1 = root ("" on the real system), $2 = dir with saved copies, rest = relative config paths.
gaming_restore_kept_configs() {
    local root="$1" saved_dir="$2" cfg_rel saved
    shift 2
    for cfg_rel in "$@"; do
        saved="${saved_dir}/${cfg_rel//\//_}"
        [ -f "${saved}" ] || continue
        [ -e "${root}/${cfg_rel}" ] && continue
        sudo install -m 644 -o root -g root "${saved}" "${root}/${cfg_rel}" 2>/dev/null \
            || { log_warn "Your settings in /${cfg_rel} could not be put back; a copy is in /${cfg_rel}.new."; continue; }
        if [ -f "${root}/${cfg_rel}.new" ] && cmp -s "${saved}" "${root}/${cfg_rel}.new"; then
            sudo rm -f "${root}/${cfg_rel}.new" 2>/dev/null || true
        fi
    done
    return 0
}

# 6A-125: true when the build left the program it is meant to install (a stub package is never built).
gaming_payload_present() {
    local pkg_id="$1" main_url="$2" staging_root="$3" tmp_extract="$4" p
    case "${pkg_id}" in
        hyprmod)
            for p in "${staging_root}"/usr/lib*/python3*/site-packages/hyprmod; do [ -d "${p}" ] && return 0; done
            return 1 ;;
        mactahoe-icons|mactahoe-cursors|whitesur-icons|whitesur-cursors)
            [ -n "$(find "${staging_root}/usr/share/icons" -mindepth 2 -type f -print -quit 2>/dev/null)" ]; return ;;
        antigravity)
            [ -n "$(find "${staging_root}/opt/antigravity" -type f -print -quit 2>/dev/null)" ]; return ;;
        claude-desktop)
            for p in usr/lib/claude-desktop opt/claude-desktop usr/share/claude-desktop usr/lib64/claude-desktop; do
                [ -n "$(find "${staging_root}/${p}" -type f -print -quit 2>/dev/null)" ] && return 0
            done
            return 1 ;;
        claude-code)
            [ -s "${staging_root}/opt/claude-code/claude-code" ]; return ;;
        gemini-cli)
            [ -s "${staging_root}/opt/gemini-cli/bundle/gemini.js" ]; return ;;
        dvcp-aac)
            # 6A-188: the plugin files are *.dvcp (the old check looked for *.so and refused every rebuild as empty): any file below the plugin folder counts
            [ -n "$(find "${staging_root}/opt/resolve/IOPlugins" -type f -print -quit 2>/dev/null)" ]; return ;;
    esac
    if [ "${main_url}" = "BUNDLED" ]; then
        [ -n "$(find "${staging_root}" -type f -name '*.rules' -print -quit 2>/dev/null)" ]; return
    fi
    # Archive recipes: something besides pacman metadata was extracted (main, lib32 or extra parts)
    [ -n "$(find "${tmp_extract}" -mindepth 2 \( -type f -o -type l \) ! -name '.PKGINFO' ! -name '.MTREE' \
        ! -name '.BUILDINFO' ! -name '.INSTALL' ! -name '.CHANGELOG' -print -quit 2>/dev/null)" ]
}

# 6A-125: the build sets its own INT/TERM trap; the caller's trap (e.g. the batch's) is restored afterwards.
# Called with errexit active, a failure still ends the script exactly as before.
# 6A-125 (verifier BLOCKER-1): inside a full update the run owns INT/TERM (SS-3 stop model: finish the step, then the
# boot chain); a curated build must never exit the run or reset its traps. Standalone deploys keep their own traps.
_gaming_trap_set() {
    [ "${SLACKY_UPDATE_RUNNING:-0}" = "1" ] && return 0
    trap "$1; exit 130" INT
    trap "$1; exit 143" TERM
}
_gaming_trap_reset() {
    [ "${SLACKY_UPDATE_RUNNING:-0}" = "1" ] && return 0
    trap - INT TERM
}

transmute_and_deploy_gaming_pkg() {
    local _tdg_prev_int _tdg_prev_term _tdg_rc
    _tdg_prev_int=$(trap -p INT)
    _tdg_prev_term=$(trap -p TERM)
    _transmute_and_deploy_gaming_pkg_impl "$@"
    _tdg_rc=$?
    _gaming_trap_reset
    if [ -n "${_tdg_prev_int}" ]; then eval "${_tdg_prev_int}"; fi
    if [ -n "${_tdg_prev_term}" ]; then eval "${_tdg_prev_term}"; fi
    return "${_tdg_rc}"
}

_transmute_and_deploy_gaming_pkg_impl() {
    local pkg_id="$1"
    local pre_cache_dir="${2:-}"
    local pre_ver="${3:-}"
    local pre_main_url="${4:-}"
    local pre_lib32_url="${5:-}"
    local pre_extra_url="${6:-}"
    local _unavail_why
    _unavail_why=$(gaming_pkg_unavailable_reason "${pkg_id}")
    if [ -n "${_unavail_why}" ]; then
        log_warn "${pkg_id}: ${_unavail_why}"
        return 1
    fi
    # rec 3: an installed gnomes build of the same program is never replaced by the curated build
    if gaming_pkg_owned_by_gnomes "${pkg_id}"; then
        log_warn "$(gaming_pkg_other_engine_sentence "${pkg_id}")"
        return 1
    fi
    
    # 6A-196: hyprpicker alone is skipped when an installed Hyprland suite already ships it
    local _hx_why
    if _hx_why=$(gaming_hypr_exclusive_skip "${pkg_id}"); then
        log_info "${_hx_why}"
        return 0
    fi

    # Pre-flight readiness checks
    audit_multilib_readiness "${pkg_id}"
    if [ "${pkg_id}" = "solaar" ] || [ "${pkg_id}" = "openghub" ] || [ "${pkg_id}" = "steam-devices" ] || [ "${pkg_id}" = "openrgb" ] || [ "${pkg_id}" = "coolercontrol" ] || [ "${pkg_id}" = "sunshine" ] || [ "${pkg_id}" = "steam" ]; then
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
        echo -e "${CYAN}${BOLD}Transmuting & Deploying: ${pkg_id}${RESET}"
        read -r ver main_url lib32_url extra_url <<< "$(resolve_cachyos_gaming_upstream_metadata "${pkg_id}" || echo "NONE NONE NONE NONE")"
    fi

    if [ "${ver}" = "NONE" ] || [ -z "${main_url}" ] || [ "${main_url}" = "NONE" ]; then
        log_error "Failed to resolve CachyOS upstream package for: ${pkg_id}"
        return 1
    fi

    gaming_space_precheck "$(get_user_staging_dir)" || return 1  # 6A-313 (N4)
    local staging_base
    staging_base=$(mktemp -d "$(get_user_staging_dir)/gnome-${pkg_id}-${ver}.XXXXXX" 2>/dev/null || mktemp -d /tmp/slacky-gnome.XXXXXX)
    local cache_dir="${staging_base}/downloads"
    local staging_root="${staging_base}/pkg"
    local tmp_extract="${staging_base}/extract"
    # 6A-125: Ctrl-C/TERM removes this build's staging (and a batch's, if any) and stops; it never packs leftovers
    local _tdg_clean
    _tdg_clean="rm -rf -- $(printf '%q' "${staging_base}")${_GAMING_BATCH_STAGING:+ $(printf '%q' "${_GAMING_BATCH_STAGING}")} 2>/dev/null"
    _gaming_trap_set "${_tdg_clean}"

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
    elif [ "${main_url}" = "GITHUB_WHEELS" ] || [ "${pkg_id}" = "hyprmod" ]; then
        log_info "Transmuting and building ${pkg_id} (${ver}) from GitHub / PyPI wheel ecosystem..."
        python3 - "${staging_root}" "${ver}" << 'PYBUILD_HYPRMOD' || { gaming_build_failed "hyprmod was not built. Nothing was changed."; return 1; }
import sys, os, urllib.request, tarfile, tempfile, subprocess, glob, shutil, hashlib

staging_root = sys.argv[1]
ver = sys.argv[2]
headers = {'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36'}

# 6A-65: locked source set. hyprmod from its release tag (sha256 identical to the AUR PKGBUILD); its five libraries as the
# exact PyPI wheels (immutable files). A download whose checksum differs is refused and nothing is built.
# To move to a new hyprmod release: update every entry here and the "0.4.0" in the two version checks, in one build.
HYPRMOD_LOCK = {
    "version": "0.4.0",
    "source": ("https://github.com/BlueManCZ/hyprmod/archive/refs/tags/v0.4.0.tar.gz",
               "fd3672ad5257bb65038fd7442553fd1a8cfb5c41a0320186797368a7f2abbc9f", "hyprmod-0.4.0"),
    "wheels": [
        ("https://files.pythonhosted.org/packages/f0/fe/59edb40c675b4d2e48d9474626ec8b549bcfb6f0113b845b3d01408a8b1b/hyprland_config-0.9.17-py3-none-any.whl",
         "4bbf49efe070a27531dccfed96477189d6c9f108107857864dbff6a5ab74894b"),
        ("https://files.pythonhosted.org/packages/ea/e5/5515c5d0ef146622250cc9cbdfdf1b603b77087553becb1191501de88d71/hyprland_monitors-0.9.0-py3-none-any.whl",
         "0f6eeb3dae2a9db0a5eaaeca09aa63f4ff0d31d6ff7dbe763245b501208f1989"),
        ("https://files.pythonhosted.org/packages/0f/24/66d5aad64573e38a5ec31820f3a920ff6a79364a329dba7f3e708bced536/hyprland_schema-0.7.1-py3-none-any.whl",
         "97637f24ac593232e388f99b079c4166cc8e321775e9097470f3b467cda551dc"),
        ("https://files.pythonhosted.org/packages/e4/74/e156c61e041b357591749aa480257b129e4c9a186faed98fd72551c68049/hyprland_socket-0.12.2-py3-none-any.whl",
         "4f1d007b7f9165447c39c66c578012bd2628331aeadb3a81c2fe2229711dc4d7"),
        ("https://files.pythonhosted.org/packages/c9/43/4452549ec8208ef093c1cdd880ab2f6e0f3b0a3916dc00b7d3b8f94f83df/hyprland_state-0.4.7-py3-none-any.whl",
         "ef4e4db2f0769d49c1c3291ebb8ddcaa9fc1d59c1022e0a75407b49b794ab269"),
    ],
}
if ver != HYPRMOD_LOCK["version"]:
    print(f"   hyprmod {ver} was asked for, building the locked version {HYPRMOD_LOCK['version']}.")

def fetch_verified(url, sha, dest):
    req = urllib.request.Request(url, headers=headers)
    h = hashlib.sha256()
    with urllib.request.urlopen(req, timeout=30) as resp, open(dest, 'wb') as f:
        while True:
            chunk = resp.read(1 << 16)
            if not chunk:
                break
            h.update(chunk)
            f.write(chunk)
    if h.hexdigest() != sha:
        print(f"   {os.path.basename(dest)} does not match its known checksum. Not building hyprmod.")
        sys.exit(1)

with tempfile.TemporaryDirectory() as tmpdir:
    dist_dir = os.path.join(tmpdir, 'dist')
    os.makedirs(dist_dir, exist_ok=True)
    for url, sha in HYPRMOD_LOCK["wheels"]:
        fetch_verified(url, sha, os.path.join(dist_dir, url.rsplit('/', 1)[1]))
    src_url, src_sha, src_top = HYPRMOD_LOCK["source"]
    tar_path = os.path.join(tmpdir, 'hyprmod.tar.gz')
    fetch_verified(src_url, src_sha, tar_path)
    with tarfile.open(tar_path, 'r:gz') as tf:
        tf.extractall(tmpdir, filter='data')
    hyprmod_src = os.path.join(tmpdir, src_top)
    subprocess.run(['python3', '-m', 'build', '--wheel', '--no-isolation', '--outdir', dist_dir], cwd=hyprmod_src, check=True)

    for w in sorted(glob.glob(os.path.join(dist_dir, '*.whl'))):
        subprocess.run(['python3', '-m', 'installer', '--destdir', staging_root, w], check=True)

    os.makedirs(os.path.join(staging_root, 'usr/share/applications'), exist_ok=True)
    os.makedirs(os.path.join(staging_root, 'usr/share/icons/hicolor/scalable/apps'), exist_ok=True)
    os.makedirs(os.path.join(staging_root, 'usr/share/metainfo'), exist_ok=True)

    if os.path.exists(os.path.join(hyprmod_src, 'data/applications/io.github.bluemancz.hyprmod.desktop')):
        shutil.copy(os.path.join(hyprmod_src, 'data/applications/io.github.bluemancz.hyprmod.desktop'), os.path.join(staging_root, 'usr/share/applications/'))
    if os.path.exists(os.path.join(hyprmod_src, 'data/icons/hicolor/scalable/apps/io.github.bluemancz.hyprmod.svg')):
        shutil.copy(os.path.join(hyprmod_src, 'data/icons/hicolor/scalable/apps/io.github.bluemancz.hyprmod.svg'), os.path.join(staging_root, 'usr/share/icons/hicolor/scalable/apps/'))
    if os.path.exists(os.path.join(hyprmod_src, 'data/metainfo/io.github.bluemancz.hyprmod.metainfo.xml')):
        shutil.copy(os.path.join(hyprmod_src, 'data/metainfo/io.github.bluemancz.hyprmod.metainfo.xml'), os.path.join(staging_root, 'usr/share/metainfo/'))
PYBUILD_HYPRMOD
    elif [ "${main_url}" = "GITHUB_THEME" ] || [ "${pkg_id}" = "mactahoe-icons" ] || [ "${pkg_id}" = "mactahoe-cursors" ] || [ "${pkg_id}" = "whitesur-icons" ] || [ "${pkg_id}" = "whitesur-cursors" ]; then
        log_info "Transmuting and building ${pkg_id} (${ver}) from a pinned GitHub source archive..."
        # 6A-193: one pinned commit archive per project, SHA-256 checked (same pins as the Rust curated engine). Never a git clone of
        # a moving branch. The project's own install.sh runs only on the verified archive.
        python3 - "${staging_root}" "${pkg_id}" "${ver}" << 'PYBUILD_THEME' || { gaming_build_failed "${pkg_id} could not be built. Nothing was changed."; return 1; }  # 6A-125
import sys, os, re, tempfile, subprocess, shutil, tarfile, hashlib, urllib.request

staging_root = sys.argv[1]
pkg_id = sys.argv[2]
ver = sys.argv[3]

# 6A-193 pins (raising one is a slacky-update release, like HYPRMOD_LOCK): MacTahoe 839848b9 (tag 2026-09-10), WhiteSur icons
# 73d8040d (tag 2026-09-10), WhiteSur cursors e190baf6 (2025-04-05, no tags). Values equal the Rust recipes_desktop.rs.
THEME_PINS = {
    "mactahoe": ("https://github.com/vinceliuice/MacTahoe-icon-theme/archive/839848b9a8a38a92a6936e30c4abe35cc6f2546d.tar.gz",
                 "00cb36a3883e40687ade9f57a0c1dd3e14fda84b73efc69aa86e2be67f32ab0a", 64 << 20, "2026.09.10.r0.839848b9"),
    "whitesur-icons": ("https://github.com/vinceliuice/WhiteSur-icon-theme/archive/73d8040da51a9ed74e47c7366e7e9ff437601a5c.tar.gz",
                       "96661649071d8a9664b40d42abea75286175234473106156e9a4b25f54e6cb0c", 64 << 20, "2026.09.10"),
    "whitesur-cursors": ("https://github.com/vinceliuice/WhiteSur-cursors/archive/e190baf618ed95ee217d2fd45589bd309b37672b.tar.gz",
                         "35c817c2c26bc4d2c06801cfe6c924a068ad771d3846c5203b04d1c893dd5664", 16 << 20, "2025.04.05.r0.e190baf6"),
}
pin_key = {"mactahoe-icons": "mactahoe", "mactahoe-cursors": "mactahoe",
           "whitesur-icons": "whitesur-icons", "whitesur-cursors": "whitesur-cursors"}[pkg_id]
url, want_sha, max_bytes, pinned_ver = THEME_PINS[pin_key]
if ver != pinned_ver:
    print(f"   {pkg_id} {ver} was asked for, building the pinned version {pinned_ver}.")

def fetch_verified(dest):
    h = hashlib.sha256()
    total = 0
    if not url.startswith("https://github.com/"):
        raise SystemExit(1)
    src = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64)"}), timeout=30)
    with src, open(dest, "wb") as f:
        while True:
            chunk = src.read(1 << 16)
            if not chunk:
                break
            total += len(chunk)
            if total > max_bytes:
                print(f"   {pkg_id}: the download is larger than expected. Not building.")
                sys.exit(1)
            h.update(chunk)
            f.write(chunk)
    if h.hexdigest() != want_sha:
        print(f"   {pkg_id}: the download does not match its known checksum. Not building.")
        sys.exit(1)

with tempfile.TemporaryDirectory() as tmpdir:
    icons_dest = os.path.join(staging_root, "usr/share/icons")
    os.makedirs(icons_dest, exist_ok=True)
    tar_path = os.path.join(tmpdir, "theme.tar.gz")
    fetch_verified(tar_path)
    src_dir = os.path.join(tmpdir, "src")
    os.makedirs(src_dir)
    with tarfile.open(tar_path, "r:gz") as tf:
        tf.extractall(src_dir, filter="data")
    tops = [d for d in os.listdir(src_dir) if os.path.isdir(os.path.join(src_dir, d))]
    if len(tops) != 1:
        print(f"   {pkg_id}: the archive has an unexpected layout. Not building.")
        sys.exit(1)
    repo_dir = os.path.join(src_dir, tops[0])

    def run_install_script():
        script = os.path.join(repo_dir, "install.sh")
        with open(script, "r", errors="replace") as fh:
            body = fh.read()
        # the pinned script is known to only copy files and link them; anything that reaches for the network or root is refused
        if re.search(r"\b(git\s+clone|curl|wget|sudo|pkexec)\b", body):
            print(f"   {pkg_id}: the install script of the pinned archive does something unexpected. Not building.")
            sys.exit(1)
        subprocess.run(["sed", "-i", "/gtk-update-icon-cache/d", "install.sh"], cwd=repo_dir, check=True)
        subprocess.run(["bash", "./install.sh", "-d", icons_dest, "-t", "all"], cwd=repo_dir, check=True, stdout=subprocess.DEVNULL)  # silent on success

    if pkg_id in ("mactahoe-icons", "whitesur-icons"):
        run_install_script()
    elif pkg_id == "mactahoe-cursors":
        if os.path.exists(os.path.join(repo_dir, "cursors/dist")):
            shutil.copytree(os.path.join(repo_dir, "cursors/dist"), os.path.join(icons_dest, "MacTahoe-cursors"), dirs_exist_ok=True)
        if os.path.exists(os.path.join(repo_dir, "cursors/dist-dark")):
            shutil.copytree(os.path.join(repo_dir, "cursors/dist-dark"), os.path.join(icons_dest, "MacTahoe-dark-cursors"), dirs_exist_ok=True)
    elif pkg_id == "whitesur-cursors":  # 6A-126: was shell syntax (SyntaxError, theme builds never worked)
        if os.path.exists(os.path.join(repo_dir, "dist")):
            shutil.copytree(os.path.join(repo_dir, "dist"), os.path.join(icons_dest, "WhiteSur-cursors"), dirs_exist_ok=True)
        if os.path.exists(os.path.join(repo_dir, "dist-dark")):
            shutil.copytree(os.path.join(repo_dir, "dist-dark"), os.path.join(icons_dest, "WhiteSur-dark-cursors"), dirs_exist_ok=True)
PYBUILD_THEME
    elif [ "${main_url}" = "AUR_ANTIGRAVITY" ] || [ "${pkg_id}" = "antigravity" ]; then
        log_info "Transmuting and building ${pkg_id} (${ver}) from upstream Google Antigravity & AUR ecosystem..."
        python3 - "${staging_root}" "${cache_dir}" "${ver}" "$(_slacky_vendor_fetch_dir)" << 'PYBUILD_ANTIGRAVITY' || { gaming_build_failed "${pkg_id} could not be built. Nothing was changed."; return 1; }  # 6A-125
import sys, os, tempfile, subprocess, shutil, re, urllib.request, tarfile, hashlib

staging_root = sys.argv[1]
cache_dir = sys.argv[2]
ver = sys.argv[3]
lib_dir = sys.argv[4] if len(sys.argv) > 4 else ""
# 6A-311 (V5): the safe unpacker and Google's own checksum live in slacky_vendor_fetch.py; without it nothing is unpacked
if not lib_dir or not os.path.isfile(os.path.join(lib_dir, "slacky_vendor_fetch.py")):
    raise RuntimeError("slacky_vendor_fetch.py was not found, so the download cannot be verified")
sys.path.insert(0, lib_dir)
import slacky_vendor_fetch as vf

env = os.environ.copy()
env["GIT_TERMINAL_PROMPT"] = "0"
# 6A-311 (V5): no endless wait on a dead network (give up below 1 KB/s for 30 s)
env["GIT_HTTP_LOW_SPEED_LIMIT"] = "1024"
env["GIT_HTTP_LOW_SPEED_TIME"] = "30"

with tempfile.TemporaryDirectory() as tmpdir:
    aur_dir = os.path.join(tmpdir, "aur")
    try:
        subprocess.run(["git", "clone", "--depth", "1", "https://aur.archlinux.org/antigravity.git", aur_dir], env=env, check=True, capture_output=True, timeout=90)
    except Exception as e:
        print(f"Warning: AUR git clone failed ({e}), using default tarball resolution.")
        os.makedirs(aur_dir, exist_ok=True)

    pkgbuild_path = os.path.join(aur_dir, "PKGBUILD")
    build_id = "6046815158665216"
    expected_b2 = ""
    if os.path.exists(pkgbuild_path):
        try:
            with open(pkgbuild_path, "r", encoding="utf-8") as f:
                c = f.read()
            bm = re.search(r'_build=([0-9]+)', c)
            if bm:
                build_id = bm.group(1)
            vm = re.search(r'pkgver=([0-9\.]+)', c)
            if vm:
                ver = vm.group(1)
            # 6A-6b: Google publishes no checksum; the AUR PKGBUILD carries a BLAKE2b-512 (b2sum) of this tarball
            hm = re.search(r"b2sums_x86_64=\(\s*['\"]([0-9a-f]{128})['\"]", c)
            if hm:
                expected_b2 = hm.group(1)
        except Exception:
            pass

    tar_url = f"https://storage.googleapis.com/antigravity-public/antigravity-hub/{ver}-{build_id}/linux-x64/Antigravity.tar.gz"
    local_tar = os.path.join(cache_dir, f"Antigravity-{ver}-x86_64.tar.gz")

    def b2sum_of(path):
        h = hashlib.blake2b()
        with open(path, "rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 20), b""):
                h.update(chunk)
        return h.hexdigest()

    def sha256_of(path):
        h = hashlib.sha256()
        with open(path, "rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 20), b""):
                h.update(chunk)
        return h.hexdigest()

    # 6A-311 (V5): Google's own update service names the SHA-256 of the build it offers; when that is the build we are
    # about to download, it is the trust anchor. Otherwise the AUR maintainer's BLAKE2b is used and a mismatch is refused.
    vendor_sha = vf.antigravity_vendor_sha256(tar_url)

    def tar_ok(path):
        if vendor_sha:
            return sha256_of(path) == vendor_sha
        return b2sum_of(path) == expected_b2

    def refuse(msg):
        print(msg, file=sys.stderr)
        sys.exit(1)

    if not vendor_sha and not expected_b2:
        refuse("Antigravity was not installed: no checksum could be read from Google or from the AUR package recipe, "
               "so the download cannot be verified. Try again later.")

    # 6A-6b: a cached archive must match too (before, any file over 1 MB was reused forever)
    if os.path.exists(local_tar) and not tar_ok(local_tar):
        print("Cached Antigravity archive does not match its checksum; downloading it again.")
        os.remove(local_tar)

    if not os.path.exists(local_tar) or os.path.getsize(local_tar) < 1000000:
        print(f"Downloading upstream Antigravity {ver} from {tar_url}...")
        download_ok = False
        try:
            subprocess.run(["curl", "-#", "-fSL", "--connect-timeout", "15", "--speed-limit", "1024", "--speed-time", "30", "-m", "1800",
                            "-A", "Mozilla/5.0 (X11; Linux x86_64)", "-o", local_tar, tar_url], check=True, timeout=1900)  # 6A-311: timeouts
            if os.path.exists(local_tar) and os.path.getsize(local_tar) > 1000000:
                download_ok = True
        except Exception:
            pass

        if not download_ok:
            req = urllib.request.Request(tar_url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"})
            with urllib.request.urlopen(req, timeout=120) as resp, open(local_tar, "wb") as f:
                shutil.copyfileobj(resp, f)

    if not os.path.exists(local_tar) or os.path.getsize(local_tar) < 1000000:
        raise RuntimeError(f"Failed to download valid Antigravity archive from {tar_url}")
    if not tar_ok(local_tar):
        os.remove(local_tar)
        refuse("Antigravity was not installed: the download does not match its published checksum "
               + ("(from Google)" if vendor_sha else "(from the AUR recipe, Google publishes none for this build)")
               + ". The file was deleted; try again later.")

    print(f"Extracting {local_tar} into /opt/antigravity...")
    opt_dest = os.path.join(staging_root, "opt/antigravity")
    os.makedirs(opt_dest, exist_ok=True)

    with tarfile.open(local_tar, "r:gz") as tf:
        try:
            vf.extract_safe(tf, opt_dest)  # 6A-311/6A-314 (V5, F5): member check, never a bare extractall
        except vf.VendorError as exc:
            refuse(f"Antigravity was not installed: the archive has an unsafe entry ({exc}).")

    # Flatten if unpacked into a single top-level directory
    subdirs = [d for d in os.listdir(opt_dest) if os.path.isdir(os.path.join(opt_dest, d)) and d.lower().startswith("antigravity")]
    if len(subdirs) == 1 and not os.path.exists(os.path.join(opt_dest, "antigravity")):
        nested = os.path.join(opt_dest, subdirs[0])
        for item in os.listdir(nested):
            shutil.move(os.path.join(nested, item), opt_dest)
        os.rmdir(nested)

    # Ensure binary executable permissions
    main_bin = os.path.join(opt_dest, "antigravity")
    if os.path.exists(main_bin):
        os.chmod(main_bin, 0o755)
    sandbox_bin = os.path.join(opt_dest, "chrome-sandbox")
    if os.path.exists(sandbox_bin):
        try:
            os.chmod(sandbox_bin, 0o4755)
        except Exception:
            pass

    # Install applications desktop file and icons
    apps_dest = os.path.join(staging_root, "usr/share/applications")
    pix_dest = os.path.join(staging_root, "usr/share/pixmaps")
    hicolor_dest = os.path.join(staging_root, "usr/share/icons/hicolor/512x512/apps")
    os.makedirs(apps_dest, exist_ok=True)
    os.makedirs(pix_dest, exist_ok=True)
    os.makedirs(hicolor_dest, exist_ok=True)

    desktop_file = os.path.join(apps_dest, "antigravity.desktop")
    if os.path.exists(os.path.join(aur_dir, "antigravity.desktop")):
        shutil.copy(os.path.join(aur_dir, "antigravity.desktop"), desktop_file)
    else:
        with open(desktop_file, "w", encoding="utf-8") as df:
            df.write("""[Desktop Entry]
Name=Antigravity 2.0
Comment=AI Agent Command Center & IDE
GenericName=Agent Orchestrator
Exec=/usr/bin/antigravity %F
Icon=antigravity
Type=Application
StartupNotify=false
StartupWMClass=Antigravity
Categories=Development;IDE;TextEditor;Utility;
MimeType=application/x-antigravity-workspace;
""")

    if os.path.exists(os.path.join(aur_dir, "antigravity.png")):
        shutil.copy(os.path.join(aur_dir, "antigravity.png"), os.path.join(pix_dest, "antigravity.png"))
        shutil.copy(os.path.join(aur_dir, "antigravity.png"), os.path.join(hicolor_dest, "antigravity.png"))
    elif os.path.exists("/usr/share/pixmaps/antigravity.png"):
        shutil.copy("/usr/share/pixmaps/antigravity.png", os.path.join(pix_dest, "antigravity.png"))
        shutil.copy("/usr/share/pixmaps/antigravity.png", os.path.join(hicolor_dest, "antigravity.png"))
PYBUILD_ANTIGRAVITY
    elif [ "${main_url}" = "DEB_CLAUDE_DESKTOP" ] || [ "${pkg_id}" = "claude-desktop" ]; then
        log_info "Transmuting and building ${pkg_id} (${ver}) from official Anthropic Debian release..."
        python3 - "${staging_root}" "${cache_dir}" "${ver}" "$(_slacky_vendor_fetch_dir)" << 'PYBUILD_CLAUDE_DESKTOP' || { gaming_build_failed "${pkg_id} could not be built. Nothing was changed."; return 1; }  # 6A-125
import sys, os, tempfile, subprocess, shutil, urllib.request, tarfile

staging_root = sys.argv[1]
cache_dir = sys.argv[2]
ver = sys.argv[3]
lib_dir = sys.argv[4] if len(sys.argv) > 4 else ""
# 6A-176: the vendor's own published checksum is read and checked before anything is unpacked (fail closed)
if not lib_dir or not os.path.isfile(os.path.join(lib_dir, "slacky_vendor_fetch.py")):
    raise RuntimeError("slacky_vendor_fetch.py was not found, so the download cannot be verified")
sys.path.insert(0, lib_dir)
import slacky_vendor_fetch as vf

local_deb = os.path.join(cache_dir, f"claude-desktop_{ver}_amd64.deb")
try:
    deb_url, deb_sha256, deb_size = vf.apt_record("claude-desktop", ver)
    print(f"Downloading official Claude Desktop {ver} from {deb_url}...")
    vf.download_verified(deb_url, local_deb, "sha256", deb_sha256, deb_size if deb_size > 0 else 512 << 20)
except vf.VendorError as exc:
    raise RuntimeError(f"The Claude Desktop download could not be verified ({exc})")

print(f"Extracting {local_deb} payload into staging root...")
with tempfile.TemporaryDirectory() as tmpdir:
    subprocess.run(["ar", "x", local_deb], cwd=tmpdir, check=True)
    data_tar = None
    for cand in ["data.tar.xz", "data.tar.zst", "data.tar.gz"]:
        p = os.path.join(tmpdir, cand)
        if os.path.exists(p):
            data_tar = p
            break
    if not data_tar:
        raise RuntimeError("No data.tar payload found inside debian archive")
    
    if data_tar.endswith(".zst"):
        plain_tar = os.path.join(tmpdir, "data.tar")
        with open(plain_tar, "wb") as zout:
            subprocess.run(["zstd", "-dc", data_tar], stdout=zout, check=True)
        data_tar = plain_tar
    # 6A-176: member check instead of a bare extractall (a Debian package may link to absolute paths, which stay links)
    with tarfile.open(data_tar) as tf:
        vf.extract_safe(tf, staging_root, allow_absolute_links=True)

lintian_dir = os.path.join(staging_root, "usr/share/lintian")
if os.path.exists(lintian_dir):
    shutil.rmtree(lintian_dir, ignore_errors=True)

for sb in [
    os.path.join(staging_root, "usr/lib/claude-desktop/chrome-sandbox"),
    os.path.join(staging_root, "opt/claude-desktop/chrome-sandbox")
]:
    if os.path.exists(sb):
        try:
            os.chmod(sb, 0o4755)
        except Exception:
            pass
PYBUILD_CLAUDE_DESKTOP
    elif [ "${main_url}" = "NPM_CLAUDE_CODE" ] || [ "${pkg_id}" = "claude-code" ]; then
        log_info "Transmuting and building ${pkg_id} (${ver}) from official Anthropic Claude Code release..."
        python3 - "${staging_root}" "${cache_dir}" "${ver}" "$(_slacky_vendor_fetch_dir)" << 'PYBUILD_CLAUDE_CODE' || { gaming_build_failed "${pkg_id} could not be built. Nothing was changed."; return 1; }  # 6A-125
import sys, os, tempfile, subprocess, shutil, urllib.request, tarfile

staging_root = sys.argv[1]
cache_dir = sys.argv[2]
ver = sys.argv[3]
lib_dir = sys.argv[4] if len(sys.argv) > 4 else ""
# 6A-176: the vendor's own published checksum is read and checked before anything is unpacked (fail closed)
if not lib_dir or not os.path.isfile(os.path.join(lib_dir, "slacky_vendor_fetch.py")):
    raise RuntimeError("slacky_vendor_fetch.py was not found, so the download cannot be verified")
sys.path.insert(0, lib_dir)
import slacky_vendor_fetch as vf

try:
    tar_url, tar_sha512 = vf.npm_record("@anthropic-ai/claude-code-linux-x64", ver)
    local_tar = os.path.join(cache_dir, f"claude-code-linux-x64-{ver}.tgz")
    print(f"Downloading official Claude Code {ver} from {tar_url}...")
    vf.download_verified(tar_url, local_tar, "sha512", tar_sha512, 256 << 20)
except vf.VendorError as exc:
    raise RuntimeError(f"The Claude Code download could not be verified ({exc})")

print(f"Extracting {local_tar} into /opt/claude-code...")
opt_dir = os.path.join(staging_root, "opt/claude-code")
os.makedirs(opt_dir, exist_ok=True)

with tempfile.TemporaryDirectory() as tmpdir:
    with tarfile.open(local_tar, "r:*") as tf:
        vf.extract_safe(tf, tmpdir)  # 6A-176: filter='data' (or the equivalent member check), never a bare extractall
    pkg_dir = os.path.join(tmpdir, "package")
    if not os.path.exists(pkg_dir):
        pkg_dir = tmpdir
    
    claude_bin = os.path.join(pkg_dir, "claude")
    if not os.path.exists(claude_bin):
        for root, _, files in os.walk(tmpdir):
            if "claude" in files:
                claude_bin = os.path.join(root, "claude")
                break
    
    if os.path.exists(claude_bin):
        target_bin = os.path.join(opt_dir, "claude-code")
        shutil.copy2(claude_bin, target_bin)
        os.chmod(target_bin, 0o755)
    else:
        raise RuntimeError("No claude binary found inside extracted package")

usr_bin = os.path.join(staging_root, "usr/bin")
os.makedirs(usr_bin, exist_ok=True)
wrapper_path = os.path.join(usr_bin, "claude-code")
with open(wrapper_path, "w", encoding="utf-8") as wf:
    wf.write("""#!/bin/sh
# Anthropic Claude Code CLI Launcher for Slackware
exec /opt/claude-code/claude-code "$@"
""")
os.chmod(wrapper_path, 0o755)

cli_symlink = os.path.join(usr_bin, "claude-cli")
if not os.path.exists(cli_symlink):
    os.symlink("claude-code", cli_symlink)
PYBUILD_CLAUDE_CODE
    elif [ "${main_url}" = "NPM_GEMINI_CLI" ] || [ "${pkg_id}" = "gemini-cli" ]; then
        log_info "Transmuting and building ${pkg_id} (${ver}) from official Google Gemini CLI release..."
        python3 - "${staging_root}" "${cache_dir}" "${ver}" "$(_slacky_vendor_fetch_dir)" << 'PYBUILD_GEMINI_CLI' || { gaming_build_failed "${pkg_id} could not be built. Nothing was changed."; return 1; }  # 6A-125
import sys, os, tempfile, subprocess, shutil, urllib.request, tarfile

staging_root = sys.argv[1]
cache_dir = sys.argv[2]
ver = sys.argv[3]
lib_dir = sys.argv[4] if len(sys.argv) > 4 else ""
# 6A-176: the vendor's own published checksum is read and checked before anything is unpacked (fail closed)
if not lib_dir or not os.path.isfile(os.path.join(lib_dir, "slacky_vendor_fetch.py")):
    raise RuntimeError("slacky_vendor_fetch.py was not found, so the download cannot be verified")
sys.path.insert(0, lib_dir)
import slacky_vendor_fetch as vf

try:
    tar_url, tar_sha512 = vf.npm_record("@google/gemini-cli", ver)
    local_tar = os.path.join(cache_dir, f"gemini-cli-{ver}.tgz")
    print(f"Downloading official Gemini CLI {ver} from {tar_url}...")
    vf.download_verified(tar_url, local_tar, "sha512", tar_sha512, 96 << 20)
except vf.VendorError as exc:
    raise RuntimeError(f"The Gemini CLI download could not be verified ({exc})")

print(f"Extracting {local_tar} into /opt/gemini-cli...")
opt_dir = os.path.join(staging_root, "opt/gemini-cli")
os.makedirs(opt_dir, exist_ok=True)

with tempfile.TemporaryDirectory() as tmpdir:
    with tarfile.open(local_tar, "r:*") as tf:
        vf.extract_safe(tf, tmpdir)  # 6A-176: filter='data' (or the equivalent member check), never a bare extractall
    pkg_dir = os.path.join(tmpdir, "package")
    if not os.path.exists(pkg_dir):
        pkg_dir = tmpdir
    
    for item in os.listdir(pkg_dir):
        s = os.path.join(pkg_dir, item)
        d = os.path.join(opt_dir, item)
        if os.path.isdir(s):
            shutil.copytree(s, d, dirs_exist_ok=True)
        else:
            shutil.copy2(s, d)

usr_bin = os.path.join(staging_root, "usr/bin")
os.makedirs(usr_bin, exist_ok=True)
wrapper_path = os.path.join(usr_bin, "gemini-cli")
with open(wrapper_path, "w", encoding="utf-8") as wf:
    wf.write("""#!/bin/sh
# Google Gemini CLI Launcher for Slackware
NODE_BIN="$(which node 2>/dev/null || echo /usr/bin/node)"
if [ ! -x "${NODE_BIN}" ]; then
    echo "Error: Node.js (>=20) is required to run gemini-cli." >&2
    exit 1
fi
exec "${NODE_BIN}" /opt/gemini-cli/bundle/gemini.js "$@"
""")
os.chmod(wrapper_path, 0o755)

gemini_symlink = os.path.join(usr_bin, "gemini")
if not os.path.exists(gemini_symlink):
    os.symlink("gemini-cli", gemini_symlink)
PYBUILD_GEMINI_CLI
    elif [ "${main_url}" = "GITHUB_DVCP_AAC" ] || [ "${pkg_id}" = "dvcp-aac" ]; then
        log_info "Transmuting and building ${pkg_id} (${ver}) from GloriousEggroll dvcp-aac release..."
        python3 -I - "${staging_root}" "${cache_dir}" "${ver}" "$(_slacky_vendor_fetch_dir)" << 'PYBUILD_DVCP_AAC' || { gaming_build_failed "${pkg_id} could not be built. Nothing was changed."; return 1; }  # 6A-125
import sys, os, tempfile, shutil, tarfile, re, json, urllib.parse, urllib.error

staging_root = sys.argv[1]
cache_dir = sys.argv[2]
ver = sys.argv[3]

# 6A-295 (V1): the archive is accepted only when it equals the SHA-256 that the GitHub release API names for this exact asset
# (slacky_vendor_fetch.download_verified keeps no unchecked file); it is unpacked with the safe extractor, never a bare extractall
lib_dir = sys.argv[4] if len(sys.argv) > 4 else ""
if not lib_dir or not os.path.isfile(os.path.join(lib_dir, "slacky_vendor_fetch.py")):
    raise SystemExit("slacky_vendor_fetch.py was not found, so the download cannot be verified")
sys.path.insert(0, lib_dir)
import slacky_vendor_fetch as vf

if not re.fullmatch(r"[0-9A-Za-z._-]{1,40}", ver):
    raise SystemExit("the dvcp-aac version is not acceptable")
asset = "aac-plugin-release.tar.gz"
tar_url = f"https://github.com/GloriousEggroll/dvcp-aac/releases/download/{ver}/{asset}"
local_tar = os.path.join(cache_dir, f"dvcp-aac-{ver}.tar.gz")

try:
    rel = json.loads(vf._read_capped("https://api.github.com/repos/GloriousEggroll/dvcp-aac/releases/tags/" + urllib.parse.quote(ver, safe=""), 4 << 20, 20))
except urllib.error.HTTPError as exc:
    raise SystemExit("GitHub is limiting requests right now, please try again in an hour" if exc.code in (403, 429) else "GitHub does not know this release")
except Exception:
    raise SystemExit("GitHub could not be asked for the checksum")
want = None
for a in (rel.get("assets") or []) if isinstance(rel, dict) else []:
    if isinstance(a, dict) and a.get("name") == asset and a.get("state") == "uploaded" and a.get("browser_download_url") == tar_url:
        want = a
        break
dg = want.get("digest") if want else None
if not isinstance(dg, str) or not re.fullmatch(r"sha256:[0-9a-fA-F]{64}", dg):
    raise SystemExit("GitHub publishes no checksum for the dvcp-aac archive")
print(f"Downloading GloriousEggroll dvcp-aac {ver} from {tar_url}...")
try:
    vf.download_verified(tar_url, local_tar, "sha256", dg[7:], 64 << 20)
except vf.VendorError as exc:
    raise SystemExit("The dvcp-aac download could not be verified (%s)" % exc)

print(f"Extracting {local_tar} into DaVinci Resolve IOPlugins directory...")
plugins_dest = os.path.join(staging_root, "opt/resolve/IOPlugins")
os.makedirs(plugins_dest, exist_ok=True)

with tempfile.TemporaryDirectory() as tmpdir:
    with tarfile.open(local_tar, "r:gz") as tf:
        try:
            vf.extract_safe(tf, tmpdir)
        except vf.VendorError as exc:
            raise SystemExit("The dvcp-aac archive is not safe (%s)" % exc)
    
    # Locate .bundle directories
    for root, dirs, files in os.walk(tmpdir):
        for d in dirs:
            if d.endswith(".bundle"):
                src_bundle = os.path.join(root, d)
                dst_bundle = os.path.join(plugins_dest, d)
                if os.path.exists(dst_bundle):
                    shutil.rmtree(dst_bundle)
                shutil.copytree(src_bundle, dst_bundle)
                print(f"Installed DaVinci Resolve IOPlugin bundle: {d}")

# Set clean permissions
for root, dirs, files in os.walk(plugins_dest):
    for d in dirs:
        os.chmod(os.path.join(root, d), 0o755)
    for f in files:
        os.chmod(os.path.join(root, f), 0o755 if f.endswith(".so") else 0o644)
PYBUILD_DVCP_AAC
    else
        local main_file="${cache_dir}/$(basename "${main_url}")"
        local dl_items=()
        if [ ! -f "${main_file}" ] || [ ! -s "${main_file}" ]; then
            if slacky_signed_repo_url "${main_url}"; then
                dl_items+=("${main_url}|${main_file}|${main_url}.sig|${main_file}.sig")
            else
                dl_items+=("${main_url}|${main_file}")
            fi
        fi

        if [ "${lib32_url}" != "NONE" ] && [ -n "${lib32_url}" ]; then
            local lib32_file="${cache_dir}/$(basename "${lib32_url}")"
            if [ ! -f "${lib32_file}" ] || [ ! -s "${lib32_file}" ]; then
                if slacky_signed_repo_url "${lib32_url}"; then
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
                    if slacky_signed_repo_url "${single_extra_url}"; then
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

        if [ "${pkg_id}" = "bambu-studio" ]; then
            # 6A-192: the download must be the asset of exactly this version with the size and SHA-256 the GitHub release API names
            python3 - "${main_file}" "${ver}" "$(_slacky_vendor_fetch_dir)" << 'PYVERIFY_BAMBU' || { gaming_build_failed "The download for ${pkg_id} could not be verified. Nothing was changed."; rm -f "${main_file}" 2>/dev/null; return 1; }
import sys, os
main_file, ver, lib_dir = sys.argv[1], sys.argv[2], sys.argv[3]
if not lib_dir or not os.path.isfile(os.path.join(lib_dir, "slacky_vendor_fetch.py")):
    raise SystemExit("slacky_vendor_fetch.py was not found, so the download cannot be verified")
sys.path.insert(0, lib_dir)
import slacky_vendor_fetch as vf
try:
    vf.verify_github_asset(main_file, vf.BAMBU_REPO, vf.BAMBU_ASSET_RE, ver)
except vf.VendorError as exc:
    raise SystemExit("The Bambu Studio download could not be verified (%s)" % exc)
PYVERIFY_BAMBU
        elif [[ "${main_url}" =~ ^https://github\.com/[^/]+/[^/]+/releases/download/ ]]; then
            # 6A-295 (V1): OBS plugins and OpenGHub come from GitHub releases; the file must match the checksum the release API names
            if ! gaming_verify_github_asset "${main_file}" "${main_url}"; then
                rm -f "${main_file}" 2>/dev/null || true
                gaming_build_failed "The download for ${pkg_id} could not be verified. Nothing was changed."
                return 1
            fi
        fi

        if [ -f "${main_file}.sig" ]; then
            if ! verify_cachyos_gpg_signature "${main_file}" "${main_file}.sig" "${main_url}"; then
                log_error "GPG signature verification failed for ${pkg_id}! Aborting transmutation to protect system integrity."
                rm -rf "${staging_base}"
                return 1
            fi
        elif slacky_signed_repo_url "${main_url}"; then
            log_error "Missing required GPG signature for official upstream package ${pkg_id}!"
            rm -rf "${staging_base}"
            return 1
        fi

        # 6A-125: an archive that does not unpack stops the build (errexit is off when called from the batch)
        local extract_ok=1
        if [[ "${main_file}" =~ \.deb$ ]]; then
            (
                cd "${tmp_extract}/main" || exit 1
                ar x "${main_file}" 2>/dev/null || exit 1
                if [ -f data.tar.zst ]; then
                    tar --zstd -xf data.tar.zst 2>/dev/null || exit 1
                elif [ -f data.tar.xz ]; then
                    tar -xf data.tar.xz 2>/dev/null || exit 1
                elif [ -f data.tar.gz ]; then
                    tar -xf data.tar.gz 2>/dev/null || exit 1
                else
                    exit 1
                fi
                rm -f control.tar.* data.tar.* debian-binary 2>/dev/null || true
            ) || extract_ok=0
        elif [[ "${main_file}" =~ \.AppImage$ ]]; then
            # 6A-192: unsquashfs at the image offset (the file is never executed); the NEEDED entries of older builds are fixed
            mkdir -p "${tmp_extract}/main/opt"
            python3 - "${main_file}" "${tmp_extract}/main/opt/bambu-studio-${ver}" "$(_slacky_vendor_fetch_dir)" << 'PYUNPACK_APPIMAGE' || extract_ok=0
import sys, os
src, dest, lib_dir = sys.argv[1], sys.argv[2], sys.argv[3]
if not lib_dir or not os.path.isfile(os.path.join(lib_dir, "slacky_vendor_fetch.py")):
    raise SystemExit("slacky_vendor_fetch.py was not found")
sys.path.insert(0, lib_dir)
import slacky_vendor_fetch as vf
try:
    vf.unpack_appimage(src, dest)
    vf.fix_needed(dest)
except vf.VendorError as exc:
    raise SystemExit("The AppImage could not be unpacked (%s)" % exc)
PYUNPACK_APPIMAGE
        elif [[ "${main_file}" =~ \.zip$ ]] || [[ "${main_url}" =~ download\?file= ]]; then
            # 6A-295 (V1): a zip with an absolute or ".." member name is refused before anything is unpacked
            if ! { unzip -Z1 "${main_file}" 2>/dev/null | grep -qE '^/|(^|/)\.\.(/|$)'; } && unzip -q -o "${main_file}" -d "${tmp_extract}/main" 2>/dev/null; then
                find "${tmp_extract}/main" -type f \( -name "*.tar.gz" -o -name "*.tar.xz" -o -name "*.tgz" \) | while read -r inner_tar; do
                    tar -xf "${inner_tar}" -C "${tmp_extract}/main" 2>/dev/null || exit 1
                    rm -f "${inner_tar}" 2>/dev/null || true
                done || extract_ok=0
            else
                extract_ok=0
            fi
        else
            tar --zstd -xf "${main_file}" -C "${tmp_extract}/main" 2>/dev/null || tar -xf "${main_file}" -C "${tmp_extract}/main" 2>/dev/null || extract_ok=0
        fi
        if [ "${extract_ok}" -ne 1 ]; then
            gaming_build_failed "The download for ${pkg_id} could not be unpacked. Nothing was changed."
            return 1
        fi
    fi

    # Extract 32-bit Multilib if present
    if [ "${lib32_url}" != "NONE" ] && [ -n "${lib32_url}" ]; then
        local lib32_file="${cache_dir}/$(basename "${lib32_url}")"
        if [ -f "${lib32_file}" ]; then
            if ! verify_cachyos_gpg_signature "${lib32_file}" "${lib32_file}.sig" "${lib32_url}"; then
                log_error "GPG signature verification failed for 32-bit ${pkg_id}! Aborting."
                rm -rf "${staging_base}"
                return 1
            fi
            if ! tar --zstd -xf "${lib32_file}" -C "${tmp_extract}/lib32" 2>/dev/null; then
                gaming_build_failed "The 32-bit part of ${pkg_id} could not be unpacked. Nothing was changed."  # 6A-125
                return 1
            fi
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
                # 6A-125: a part that fails its signature check (or lacks one from a signed repo) stops the build;
                # skipping it used to install an incomplete app and report success
                if [ -f "${extra_file}.sig" ]; then
                    if ! verify_cachyos_gpg_signature "${extra_file}" "${extra_file}.sig" "${single_extra_url}"; then
                        gaming_build_failed "A part of ${pkg_id} failed its signature check. Nothing was changed."
                        return 1
                    fi
                elif slacky_signed_repo_url "${single_extra_url}"; then
                    gaming_build_failed "A part of ${pkg_id} has no signature to check. Nothing was changed."
                    return 1
                fi
                mkdir -p "${tmp_extract}/extra_${extra_idx}"
                if ! { tar --zstd -xf "${extra_file}" -C "${tmp_extract}/extra_${extra_idx}" 2>/dev/null || tar -xf "${extra_file}" -C "${tmp_extract}/extra_${extra_idx}" 2>/dev/null; }; then
                    gaming_build_failed "A part of ${pkg_id} could not be unpacked. Nothing was changed."
                    return 1
                fi
            fi
        done
    fi

    # 6A-125: never package a build that did not produce its program
    if ! gaming_payload_present "${pkg_id}" "${main_url}" "${staging_root}" "${tmp_extract}"; then
        gaming_build_failed "${pkg_id} was not built because its download was empty or incomplete. Nothing was changed."
        return 1
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
    elif [ "${pkg_id}" = "openghub" ]; then
        log_info "Packaging OpenGHub as isolated App-Bundle in /opt/openghub..."
        mkdir -p "${staging_root}/opt/openghub/bin" \
                 "${staging_root}/opt/openghub/lib" \
                 "${staging_root}/usr/bin" \
                 "${staging_root}/usr/share" \
                 "${staging_root}/lib/udev/rules.d" \
                 "${staging_root}/install"

        # Copy main package into /opt/openghub
        if [ -d "${tmp_extract}/main/usr/bin" ]; then
            cp -a "${tmp_extract}/main/usr/bin/." "${staging_root}/opt/openghub/bin/"
        elif [ -d "${tmp_extract}/main/opt" ]; then
            cp -a "${tmp_extract}/main/opt/." "${staging_root}/opt/"
        fi
        if [ -d "${tmp_extract}/main/usr/lib" ]; then
            cp -a "${tmp_extract}/main/usr/lib/." "${staging_root}/opt/openghub/lib/"
        fi
        if [ -d "${tmp_extract}/main/usr/share" ]; then
            cp -a "${tmp_extract}/main/usr/share/." "${staging_root}/usr/share/"
        fi

        # Copy auxiliary packages (webkit2gtk-4.1, libsoup3, libmanette) into /opt/openghub/lib
        for extra_dir in "${tmp_extract}"/extra*; do
            [ -d "${extra_dir}" ] || continue
            if [ -d "${extra_dir}/usr/lib" ]; then
                cp -a "${extra_dir}/usr/lib/." "${staging_root}/opt/openghub/lib/"
            fi
            if [ -d "${extra_dir}/usr/lib64" ]; then
                cp -a "${extra_dir}/usr/lib64/." "${staging_root}/opt/openghub/lib/"
            fi
        done

        # Create isolated launcher wrapper
        cat << 'OPENGHUB_WRAPPER_EOF' > "${staging_root}/usr/bin/openghub"
#!/bin/sh
# OpenGHub Native Linux Companion Launcher for Slackware
export OPEN_GHUB_DIR="/opt/openghub"
export LD_LIBRARY_PATH="${OPEN_GHUB_DIR}/lib:${LD_LIBRARY_PATH:-}"
export WEBKIT_EXEC_PATH="${OPEN_GHUB_DIR}/lib/webkit2gtk-4.1:/usr/lib64/webkit2gtk-4.1:/usr/lib/webkit2gtk-4.1"
export WEBKIT_INJECTED_BUNDLE_PATH="${OPEN_GHUB_DIR}/lib/webkit2gtk-4.1/injected-bundle:/usr/lib64/webkit2gtk-4.1/injected-bundle:/usr/lib/webkit2gtk-4.1/injected-bundle"
export WEBKIT_DISABLE_DMABUF_RENDERER=1
export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1

REAL_BIN="${OPEN_GHUB_DIR}/bin/OpenGHub"
if [ ! -x "${REAL_BIN}" ]; then
  REAL_BIN="${OPEN_GHUB_DIR}/bin/openghub"
fi
if [ ! -x "${REAL_BIN}" ]; then
  REAL_BIN="${OPEN_GHUB_DIR}/openghub"
fi

exec "${REAL_BIN}" "$@"
OPENGHUB_WRAPPER_EOF
        chmod 755 "${staging_root}/usr/bin/openghub"
        ln -sf openghub "${staging_root}/usr/bin/OpenGHub"
        ln -sf openghub "${staging_root}/usr/bin/open-g-hub"
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
                # (6A-171: the OBS folder "obs-plugins" itself is NOT such a subfolder; its loose libraries are bridged)
                if dirname "${so_file#"${tmp_extract}/main/"}" | tr '/' '\n' | grep -vx "obs-plugins" | grep -qxE "[a-zA-Z0-9_-]+-plugins"; then
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
                echo -e "  ${CYAN}•${RESET} Remapping Python site-packages ($(basename "${pydir}")) -> python${py_sys_ver}..."
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

    # Host Sovereignty Shield: Prevent auxiliary packages from conflicting with Slackware base
    if [ "${pkg_id}" = "hyprland-noctalia" ] || [ "${pkg_id}" = "hyprland-core" ]; then
        # 1. Never overwrite Slackware's native Lua interpreter binary
        rm -f "${staging_root}/usr/bin/lua" "${staging_root}/usr/bin/luac" 2>/dev/null || true
        # 2. Never overwrite development symlinks that belong to Slackware base
        rm -f "${staging_root}/usr/lib64/liblua.so" "${staging_root}/usr/lib64/libical.so" "${staging_root}/usr/lib64/libicalss.so" "${staging_root}/usr/lib64/libicalvcal.so" 2>/dev/null || true
        # 3. Clean up headers from auxiliary packages that Slackware already manages
        rm -rf "${staging_root}/usr/include/lua"* "${staging_root}/usr/include/libical"* 2>/dev/null || true
        # 6A-66: 4. the uwsm login entry only when uwsm exists (otherwise a dead entry in the login screen)
        command -v uwsm >/dev/null 2>&1 || rm -f "${staging_root}/usr/share/wayland-sessions/hyprland-uwsm.desktop"
        # 5. build-only files: no headers ship, so cmake/pkg-config files and code generators have no use on the host
        rm -rf "${staging_root}/usr/lib64/cmake" "${staging_root}/usr/lib64/pkgconfig" "${staging_root}/usr/share/pkgconfig" 2>/dev/null || true
        rm -f "${staging_root}/usr/bin/hyprwire-scanner" "${staging_root}/usr/bin/sdbus-c++-xml2cpp" "${staging_root}/usr/bin/md2html" \
              "${staging_root}/usr/share/man/man1/md2html.1.gz" 2>/dev/null || true
        # 6. modules-load.d is not read on Slackware (ddcui's i2c-dev must come from rc.modules.local)
        rm -rf "${staging_root}/usr/lib64/modules-load.d" "${staging_root}/usr/lib/modules-load.d" 2>/dev/null || true
        # 7. empty directories left by the steps above
        find "${staging_root}/lib/udev" "${staging_root}/usr/lib64" -depth -type d -empty -delete 2>/dev/null || true
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
        [ -f "${staging_root}/opt/microsoft/msedge/microsoft-edge" ] && [ ! -e "${staging_root}/usr/bin/microsoft-edge" ] && ln -sf /opt/microsoft/msedge/microsoft-edge "${staging_root}/usr/bin/microsoft-edge"        # 6A-175: the Arch package links Microsoft's apt repository helper as a ROOT cron job (/etc/cron.daily/microsoft-edge); it is
        # written for apt-based systems and has no place here. Dropped here as well as by the footprint guard (which also covers
        # report mode). The program itself keeps opt/microsoft/msedge/cron/microsoft-edge.
        rm -f -- "${staging_root}/etc/cron.daily/microsoft-edge"
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
        # Fix /usr/bin/mangohud launcher script paths & inject font synchronization
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
        # 6A-74: goverlay 1.9.4 ships the program as the FILE usr/lib/goverlay (merged into usr/lib64); move it aside
        # before the directory of the same name is created (mkdir failed with "File exists" and the deploy stopped)
        local gv
        for gv in "${staging_root}/usr/lib64/goverlay" "${staging_root}/usr/lib/goverlay"; do
            if [ -f "${gv}" ] && is_elf_binary "${gv}"; then
                mv -f "${gv}" "${staging_root}/usr/bin/goverlay.slacky-elf" 2>/dev/null || { mkdir -p "${staging_root}/usr/bin" && mv -f "${gv}" "${staging_root}/usr/bin/goverlay.slacky-elf"; }
            fi
        done
        mkdir -p "${staging_root}/usr/lib64/goverlay" "${staging_root}/usr/lib/goverlay" "${staging_root}/usr/bin"
        if [ -f "${staging_root}/usr/bin/goverlay.slacky-elf" ]; then
            mv -f "${staging_root}/usr/bin/goverlay.slacky-elf" "${staging_root}/usr/lib64/goverlay/goverlay-bin"
        fi
        # If /usr/lib64/goverlay or /usr/lib/goverlay or /usr/bin/goverlay is an ELF binary, move it to /usr/lib64/goverlay/goverlay-bin
        if [ -f "${staging_root}/usr/bin/goverlay" ] && is_elf_binary "${staging_root}/usr/bin/goverlay"; then
            mv -f "${staging_root}/usr/bin/goverlay" "${staging_root}/usr/lib64/goverlay/goverlay-bin"
        elif [ -f "${staging_root}/usr/lib64/goverlay" ] && is_elf_binary "${staging_root}/usr/lib64/goverlay"; then
            mv -f "${staging_root}/usr/lib64/goverlay" "${staging_root}/usr/lib64/goverlay/goverlay-bin"
        elif [ -f "${staging_root}/usr/lib/goverlay" ] && is_elf_binary "${staging_root}/usr/lib/goverlay"; then
            mv -f "${staging_root}/usr/lib/goverlay" "${staging_root}/usr/lib64/goverlay/goverlay-bin"
        fi

        # If /usr/lib64/pascube or /usr/lib/pascube is an ELF binary, move it to /usr/bin/pascube
        if [ -f "${staging_root}/usr/lib64/pascube" ] && is_elf_binary "${staging_root}/usr/lib64/pascube"; then
            mv -f "${staging_root}/usr/lib64/pascube" "${staging_root}/usr/bin/pascube"
        elif [ -f "${staging_root}/usr/lib/pascube" ] && is_elf_binary "${staging_root}/usr/lib/pascube"; then
            mv -f "${staging_root}/usr/lib/pascube" "${staging_root}/usr/bin/pascube"
        fi

        # Write smart launcher script for GOverlay that automatically syncs MangoHud font_file_text & font mesh upon exit
        cat <<'EOF' > "${staging_root}/usr/bin/goverlay"
#!/usr/bin/env bash
# Slacky-Update GOverlay Smart Wrapper with Automatic MangoHud Font Sync
if [ -x "/usr/lib64/goverlay/goverlay-bin" ]; then
    /usr/lib64/goverlay/goverlay-bin "$@"
elif [ -x "/usr/lib/goverlay/goverlay-bin" ]; then
    /usr/lib/goverlay/goverlay-bin "$@"
elif [ -x "/usr/lib64/goverlay/goverlay" ]; then
    /usr/lib64/goverlay/goverlay "$@"
elif [ -x "/usr/lib/goverlay/goverlay" ]; then
    /usr/lib/goverlay/goverlay "$@"
fi

# Automatically synchronize MangoHud font_file -> font_file_text, current_font.ttf local copy & font_size
python3 -c '
import os, glob, shutil

# Mirror /usr/local/share/fonts to /usr/share/fonts
if os.path.isdir("/usr/local/share/fonts"):
    os.makedirs("/usr/share/fonts", exist_ok=True)
    for root, dirs, files in os.walk("/usr/local/share/fonts"):
        rel = os.path.relpath(root, "/usr/local/share/fonts")
        target_dir = os.path.join("/usr/share/fonts", rel) if rel != "." else "/usr/share/fonts"
        os.makedirs(target_dir, exist_ok=True)
        for f in files:
            src_f = os.path.join(root, f)
            dst_f = os.path.join(target_dir, f)
            try:
                if not os.path.exists(dst_f):
                    try:
                        os.link(src_f, dst_f)
                    except Exception:
                        shutil.copy2(src_f, dst_f)
            except Exception:
                pass

mconf = os.path.expanduser("~/.config/MangoHud/MangoHud.conf")
mconf_dir = os.path.dirname(mconf)
if os.path.isfile(mconf):
    try:
        with open(mconf, "r", encoding="utf-8") as f:
            lines = f.readlines()
        has_font_file = False
        font_file_val = ""
        font_size_val = ""
        for l in lines:
            ls = l.strip()
            if ls.startswith("font_file="):
                has_font_file = True
                font_file_val = ls.split("=", 1)[1]
            elif ls.startswith("font_size="):
                font_size_val = ls.split("=", 1)[1]
        if has_font_file and font_file_val:
            cur_font = os.path.join(mconf_dir, "current_font.ttf")
            cur_font_text = os.path.join(mconf_dir, "current_font_text.ttf")
            resolved_font = font_file_val
            if resolved_font.startswith("/usr/local/share/fonts/"):
                resolved_font = resolved_font.replace("/usr/local/share/fonts/", "/usr/share/fonts/", 1)
            
            # If font_file points to an external file, copy it locally into ~/.config/MangoHud/
            if os.path.isfile(resolved_font) and os.path.abspath(resolved_font) not in [os.path.abspath(cur_font), os.path.abspath(cur_font_text)]:
                try:
                    if os.path.islink(cur_font) or os.path.exists(cur_font):
                        os.remove(cur_font)
                    shutil.copy2(resolved_font, cur_font)
                except Exception:
                    pass
                try:
                    if os.path.islink(cur_font_text) or os.path.exists(cur_font_text):
                        os.remove(cur_font_text)
                    shutil.copy2(resolved_font, cur_font_text)
                except Exception:
                    pass
            elif not os.path.exists(cur_font):
                for cand in [resolved_font, "/usr/share/fonts/Apple/SF-Pro-Italic.ttf", "/usr/local/share/fonts/Apple/SF-Pro-Italic.ttf", "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf"]:
                    if os.path.isfile(cand):
                        try:
                            shutil.copy2(cand, cur_font)
                            shutil.copy2(cand, cur_font_text)
                            break
                        except Exception:
                            pass
            
            new_lines = []
            has_updated_font_file_text = False
            has_updated_font_size_text = False
            has_font_file_text_in_orig = any(x.strip().startswith("font_file_text=") for x in lines)
            has_font_size_text_in_orig = any(x.strip().startswith("font_size_text=") for x in lines)
            for l in lines:
                ls = l.strip()
                if ls.startswith("font_file="):
                    new_lines.append(f"font_file={cur_font}\n")
                    if not has_font_file_text_in_orig and not has_updated_font_file_text:
                        new_lines.append(f"font_file_text={cur_font_text}\n")
                        has_updated_font_file_text = True
                elif ls.startswith("font_file_text="):
                    new_lines.append(f"font_file_text={cur_font_text}\n")
                    has_updated_font_file_text = True
                elif ls.startswith("font_size="):
                    new_lines.append(l)
                    if font_size_val and not has_font_size_text_in_orig and not has_updated_font_size_text:
                        new_lines.append(f"font_size_text={font_size_val}\n")
                        has_updated_font_size_text = True
                elif ls.startswith("font_size_text=") and font_size_val:
                    new_lines.append(f"font_size_text={font_size_val}\n")
                    has_updated_font_size_text = True
                else:
                    new_lines.append(l)
            with open(mconf, "w", encoding="utf-8") as f:
                f.writelines(new_lines)
    except Exception:
        pass
' 2>/dev/null || true
EOF
        chmod 755 "${staging_root}/usr/bin/goverlay"
        [ -f "${staging_root}/usr/bin/pascube" ] && chmod 755 "${staging_root}/usr/bin/pascube"

        # Create compatibility symlinks in /usr/lib64 and /usr/lib pointing to real binary
        ln -sf /usr/lib64/goverlay/goverlay-bin "${staging_root}/usr/lib64/goverlay/goverlay" 2>/dev/null || true
        ln -sf /usr/lib64/goverlay/goverlay-bin "${staging_root}/usr/lib/goverlay/goverlay" 2>/dev/null || true
        if [ -f "${staging_root}/usr/bin/pascube" ]; then
            ln -sf /usr/bin/pascube "${staging_root}/usr/lib64/pascube" 2>/dev/null || true
            ln -sf /usr/bin/pascube "${staging_root}/usr/lib/pascube" 2>/dev/null || true
            ln -sf /usr/bin/pascube "${staging_root}/usr/lib64/goverlay/pascube" 2>/dev/null || true
            ln -sf /usr/bin/pascube "${staging_root}/usr/lib/goverlay/pascube" 2>/dev/null || true
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
        # 6A-83: boot loading via rc.modules.local (doinst), not modules-load.d (never read on Slackware)
        mkdir -p "${staging_root}/etc/modprobe.d"
        cat << 'ZEN_EOF' > "${staging_root}/etc/modprobe.d/zenpower.conf"
# Generated by slacky-update Underpants Gnomes
# Blacklist default k10temp to allow zenpower full access to Zen SVI2 telemetry
blacklist k10temp
ZEN_EOF
    fi

    if [ "${pkg_id}" = "v4l2loopback" ]; then
        mkdir -p "${staging_root}/etc/modprobe.d"
        cat << 'V4L2_EOF' > "${staging_root}/etc/modprobe.d/v4l2loopback.conf"
# Generated by slacky-update Underpants Gnomes
options v4l2loopback devices=1 video_nr=10 card_label="OBS Virtual Camera" exclusive_caps=1
V4L2_EOF
    fi

    if [ "${pkg_id}" = "limine-snapper-sync" ]; then
        # SS-4 / 6A-105: one menu writer (see patch_limine_snapper_sync_staging). Refuse to build an unpatched copy.
        if ! patch_limine_snapper_sync_staging "${staging_root}"; then
            log_error "limine-snapper-sync changed upstream and could not be made safe for the startup menu. It was not updated."
            rm -rf "${staging_base}"
            return 1
        fi
    fi

    if [ "${pkg_id}" = "darktable" ]; then
        # Darktable binary RUNPATH points to $ORIGIN/../lib/darktable
        # Ensure /usr/lib/darktable symlinks to /usr/lib64/darktable on Slackware 64-bit
        mkdir -p "${staging_root}/usr/lib" "${staging_root}/usr/lib64/darktable"
        rm -rf "${staging_root}/usr/lib/darktable" 2>/dev/null || true
        ln -sf /usr/lib64/darktable "${staging_root}/usr/lib/darktable"
        # 6A-163: no etc/ld.so.conf.d file (it would change the linker path of the whole system); the RUNPATH above is enough
        rm -f "${staging_root}/etc/ld.so.conf.d/darktable.conf" 2>/dev/null || true

        # Lua 5.4 binary compatibility symlinks on Slackware
        if [ -f "/usr/lib64/liblua.so.5.4" ] || [ -f "${staging_root}/usr/lib64/liblua.so.5.4" ]; then
            [ ! -e "${staging_root}/usr/lib64/liblua5.4.so.5.4" ] && ln -sf liblua.so.5.4 "${staging_root}/usr/lib64/liblua5.4.so.5.4"
            [ ! -e "${staging_root}/usr/lib64/liblua5.4.so" ] && ln -sf liblua.so.5.4 "${staging_root}/usr/lib64/liblua5.4.so"
        fi
    fi

    if [ "${pkg_id}" = "inkscape" ]; then
        # Inkscape internal library RUNPATH points to $ORIGIN/../lib/inkscape
        # Ensure /usr/lib/inkscape symlinks to /usr/lib64/inkscape on Slackware 64-bit
        mkdir -p "${staging_root}/usr/lib" "${staging_root}/usr/lib64/inkscape"
        rm -rf "${staging_root}/usr/lib/inkscape" 2>/dev/null || true
        ln -sf /usr/lib64/inkscape "${staging_root}/usr/lib/inkscape"
        # 6A-163: no etc/ld.so.conf.d file (system-wide linker path); the RUNPATH above is enough
        rm -f "${staging_root}/etc/ld.so.conf.d/inkscape.conf" 2>/dev/null || true
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

        cat << 'SCX_CONF_EOF' > "${staging_root}/etc/scx_loader.toml"
# /etc/scx_loader.toml - Sched-EXT Loader Configuration for Slackware
default_scheduler = "scx_lavd"

[schedulers.scx_lavd]
description = "Latency-critical and gaming-oriented BPF scheduler"
path = "/usr/bin/scx_lavd"
args = ["--autopilot"]

[schedulers.scx_bpfland]
description = "BPFland gaming scheduler"
path = "/usr/bin/scx_bpfland"

[schedulers.scx_rustland]
description = "Rustland user-space gaming scheduler"
path = "/usr/bin/scx_rustland"
SCX_CONF_EOF

        cat << 'SCX_RC_EOF' > "${staging_root}/etc/rc.d/rc.scx"
#!/bin/sh
# /etc/rc.d/rc.scx - Sched-EXT Gaming Scheduler & Loader Daemon for Slackware

DEFAULT_SCHED="${SCX_SCHED:-scx_lavd}"

scx_check_support() {
    if [ ! -d /sys/kernel/sched_ext ]; then
        echo "Sched-EXT is not supported by current kernel (/sys/kernel/sched_ext missing). Skipping."
        return 1
    fi
    if ! mountpoint -q /sys/kernel/debug 2>/dev/null; then
        mount -t debugfs none /sys/kernel/debug 2>/dev/null || true
    fi
    return 0
}

scx_start() {
    if ! scx_check_support; then
        return 0
    fi
    if command -v "${DEFAULT_SCHED}" >/dev/null 2>&1; then
        echo "Starting Sched-EXT gaming scheduler (${DEFAULT_SCHED} --autopilot)..."
        nohup "${DEFAULT_SCHED}" --autopilot >/var/log/scx.log 2>&1 &
    elif command -v scx_loader >/dev/null 2>&1; then
        echo "Starting Sched-EXT loader daemon (scx_loader)..."
        nohup scx_loader >/var/log/scx_loader.log 2>&1 &
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
    if [ ! -d /sys/kernel/sched_ext ]; then
        echo "Sched-EXT is not supported by running kernel."
        return 0
    fi
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
        chmod 644 "${staging_root}/etc/rc.d/rc.scx"
    fi

    if [ "${pkg_id}" = "easyeffects" ]; then
        log_info "Fetching JackHack96 EasyEffects studio presets & impulse responses..."
        mkdir -p "${staging_root}/etc/easyeffects/output" \
                 "${staging_root}/etc/easyeffects/irs" \
                 "${staging_root}/etc/skel/.config/easyeffects/output" \
                 "${staging_root}/etc/skel/.config/easyeffects/irs"
        
        local presets_tar="${staging_base}/easyeffects-presets.tar.gz"
        curl -fsSL --connect-timeout 15 -m 120 "https://github.com/JackHack96/EasyEffects-Presets/archive/refs/heads/master.tar.gz" -o "${presets_tar}" 2>/dev/null || true  # 6A-129: no endless hang on a dead network
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

    if [ "${pkg_id}" = "openghub" ]; then
        mkdir -p "${staging_root}/lib/udev/rules.d"
        cat << 'OPENGHUB_UDEV_EOF' > "${staging_root}/lib/udev/rules.d/70-openghub.rules"
# OpenGHub — grant desktop user access to Logitech HID++ endpoints
KERNEL=="hidraw*", ATTRS{idVendor}=="046d", MODE="0660", TAG+="uaccess"
KERNEL=="uinput", SUBSYSTEM=="misc", MODE="0660", TAG+="uaccess"
OPENGHUB_UDEV_EOF

        # Ensure cross-desktop icon compatibility (KDE Plasma, XFCE, GNOME)
        mkdir -p "${staging_root}/usr/share/pixmaps" "${staging_root}/usr/share/icons/hicolor/scalable/apps"
        if [ -d "${staging_root}/usr/share/icons" ]; then
            find "${staging_root}/usr/share/icons" -type f \( -name "*.png" -o -name "*.svg" \) | while read -r icon_file; do
                [ -f "${icon_file}" ] || continue
                icon_dir="$(dirname "${icon_file}")"
                icon_base="$(basename "${icon_file}")"
                icon_ext="${icon_base##*.}"
                if [ "${icon_base}" != "openghub.${icon_ext}" ]; then
                    cp -a "${icon_file}" "${icon_dir}/openghub.${icon_ext}" 2>/dev/null || true
                fi
                if [ "${icon_base}" != "OpenGHub.${icon_ext}" ]; then
                    cp -a "${icon_file}" "${icon_dir}/OpenGHub.${icon_ext}" 2>/dev/null || true
                fi
                if [[ "${icon_file}" =~ 128x128|256x256|512x512|scalable ]]; then
                    cp -a "${icon_file}" "${staging_root}/usr/share/pixmaps/openghub.${icon_ext}" 2>/dev/null || true
                    cp -a "${icon_file}" "${staging_root}/usr/share/pixmaps/OpenGHub.${icon_ext}" 2>/dev/null || true
                fi
            done
        fi

        # If pixmap or scalable icon is missing, install the embedded OpenGHub vector icon
        if [ ! -f "${staging_root}/usr/share/pixmaps/openghub.png" ] && [ ! -f "${staging_root}/usr/share/pixmaps/openghub.svg" ]; then
            cat << 'OPENGHUB_SVG_EOF' > "${staging_root}/usr/share/icons/hicolor/scalable/apps/openghub.svg"
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">
  <defs>
    <linearGradient id="ghubGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#00e5ff"/>
      <stop offset="100%" stop-color="#0077ff"/>
    </linearGradient>
  </defs>
  <rect width="256" height="256" rx="56" fill="#12151a"/>
  <path d="M 128 44 C 81.6 44 44 81.6 44 128 C 44 174.4 81.6 212 128 212 C 174.4 212 212 174.4 212 128 L 212 124 L 128 124 L 128 148 L 186.5 148 C 179.5 171.5 156 188 128 188 C 94.9 188 68 161.1 68 128 C 68 94.9 94.9 68 128 68 C 143.5 68 157.6 73.9 168.3 83.7 L 185.5 66.5 C 170.2 52.4 150.1 44 128 44 Z" fill="url(#ghubGrad)"/>
</svg>
OPENGHUB_SVG_EOF
            cp -a "${staging_root}/usr/share/icons/hicolor/scalable/apps/openghub.svg" "${staging_root}/usr/share/icons/hicolor/scalable/apps/OpenGHub.svg" 2>/dev/null || true
            cp -a "${staging_root}/usr/share/icons/hicolor/scalable/apps/openghub.svg" "${staging_root}/usr/share/pixmaps/openghub.svg" 2>/dev/null || true
            cp -a "${staging_root}/usr/share/icons/hicolor/scalable/apps/openghub.svg" "${staging_root}/usr/share/pixmaps/OpenGHub.svg" 2>/dev/null || true
            cp -a "${staging_root}/usr/share/icons/hicolor/scalable/apps/openghub.svg" "${staging_root}/usr/share/pixmaps/openghub.png" 2>/dev/null || true
            cp -a "${staging_root}/usr/share/icons/hicolor/scalable/apps/openghub.svg" "${staging_root}/usr/share/pixmaps/OpenGHub.png" 2>/dev/null || true
        fi

        # Ensure desktop entry exists and is properly formatted
        mkdir -p "${staging_root}/usr/share/applications"
        if [ ! -f "${staging_root}/usr/share/applications/openghub.desktop" ]; then
            cat << 'OPENGHUB_DESKTOP_EOF' > "${staging_root}/usr/share/applications/openghub.desktop"
[Desktop Entry]
Name=OpenGHub
GenericName=Logitech Gaming Software
Comment=Logitech G HUB Native Linux Companion (HID++ 2.0, DPI, profiles, LIGHTSYNC)
Exec=/usr/bin/openghub %U
Icon=openghub
Terminal=false
Type=Application
Categories=Settings;HardwareSettings;Utility;Game;
Keywords=logitech;ghub;mouse;keyboard;headset;rgb;lightsync;dpi;
StartupNotify=true
StartupWMClass=openghub
OPENGHUB_DESKTOP_EOF
        fi

        for df in "${staging_root}/usr/share/applications"/*.desktop; do
            [ -f "${df}" ] || continue
            sed -i 's|^Icon=.*|Icon=openghub|g; s|^Exec=.*|Exec=/usr/bin/openghub %U|g' "${df}" 2>/dev/null || true
            local bdf
            bdf=$(basename "${df}")
            if [ "${bdf}" != "openghub.desktop" ]; then
                ln -sf "${bdf}" "${staging_root}/usr/share/applications/openghub.desktop" 2>/dev/null || true
            fi
        done
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

    if [ "${pkg_id}" = "antigravity" ]; then
        mkdir -p "${staging_root}/usr/bin" \
                 "${staging_root}/usr/share/applications" \
                 "${staging_root}/usr/share/pixmaps" \
                 "${staging_root}/opt/antigravity"

        if [ -d "${staging_root}/opt/Antigravity" ] && [ ! -d "${staging_root}/opt/antigravity" ]; then
            mv "${staging_root}/opt/Antigravity" "${staging_root}/opt/antigravity"
        fi

        rm -f "${staging_root}/usr/bin/antigravity"
        cat << 'ANTIGRAVITY_WRAPPER_EOF' > "${staging_root}/usr/bin/antigravity"
#!/bin/sh
# Google Antigravity 2.0 AI Agent Command Center Launcher for Slackware
export ANTIGRAVITY_PATH="/opt/antigravity"
export JETSKI_LS_PORT="${JETSKI_LS_PORT:-39714}"
export ELECTRON_OZONE_PLATFORM_HINT="${ELECTRON_OZONE_PLATFORM_HINT:-auto}"

FLAGS=""
if [ -n "${WAYLAND_DISPLAY:-}" ]; then
    FLAGS="--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations"
fi

if [ -x /opt/antigravity/antigravity ]; then
    exec /opt/antigravity/antigravity ${FLAGS} "$@"
elif [ -x /opt/Antigravity/antigravity ]; then
    exec /opt/Antigravity/antigravity ${FLAGS} "$@"
else
    echo "Error: Antigravity binary not found in /opt/antigravity/antigravity" >&2
    exit 1
fi
ANTIGRAVITY_WRAPPER_EOF
        chmod 755 "${staging_root}/usr/bin/antigravity"

        rm -f "${staging_root}/usr/bin/agy"
        cat << 'AGY_WRAPPER_EOF' > "${staging_root}/usr/bin/agy"
#!/bin/sh
# Antigravity CLI Launcher
if [ -x /opt/antigravity/resources/app/bin/agy ]; then
    exec /opt/antigravity/resources/app/bin/agy "$@"
else
    exec /usr/bin/antigravity "$@"
fi
AGY_WRAPPER_EOF
        chmod 755 "${staging_root}/usr/bin/agy"

        cat << 'ANTIGRAVITY_DESKTOP_EOF' > "${staging_root}/usr/share/applications/antigravity.desktop"
[Desktop Entry]
Name=Google Antigravity 2.0
GenericName=AI Agent Command Center & IDE
Comment=Advanced Agentic Coding and Multi-Agent Orchestration Platform
Exec=/usr/bin/antigravity %U
Icon=antigravity
Terminal=false
Type=Application
StartupNotify=false
StartupWMClass=Antigravity
Categories=Development;Utility;IDE;
MimeType=x-scheme-handler/antigravity;
ANTIGRAVITY_DESKTOP_EOF

        for sz in 16x16 24x24 32x32 48x48 64x64 128x128 256x256 512x512 scalable; do
            if [ -f "${staging_root}/usr/share/icons/hicolor/${sz}/apps/antigravity.png" ]; then
                mkdir -p "${staging_root}/usr/share/pixmaps"
                cp -a "${staging_root}/usr/share/icons/hicolor/${sz}/apps/antigravity.png" "${staging_root}/usr/share/pixmaps/antigravity.png" 2>/dev/null || true
            fi
        done
        if [ ! -f "${staging_root}/usr/share/pixmaps/antigravity.png" ] && [ -f "${staging_root}/opt/antigravity/resources/app/resources/linux/code.png" ]; then
            cp -a "${staging_root}/opt/antigravity/resources/app/resources/linux/code.png" "${staging_root}/usr/share/pixmaps/antigravity.png" 2>/dev/null || true
        fi
    fi

    if [ "${pkg_id}" = "claude-desktop" ]; then
        mkdir -p "${staging_root}/usr/bin" \
                 "${staging_root}/usr/share/applications" \
                 "${staging_root}/usr/share/pixmaps"

        rm -f "${staging_root}/usr/bin/claude-desktop" "${staging_root}/usr/bin/claude"
        cat << 'CLAUDE_WRAPPER_EOF' > "${staging_root}/usr/bin/claude-desktop"
#!/bin/sh
# Anthropic Claude Desktop Linux Launcher for Slackware
export ELECTRON_OZONE_PLATFORM_HINT="${ELECTRON_OZONE_PLATFORM_HINT:-auto}"

FLAGS=""
if [ -n "${WAYLAND_DISPLAY:-}" ]; then
    FLAGS="--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations"
fi

if [ -f "${HOME}/.config/claude-desktop-flags.conf" ]; then
    USER_FLAGS=$(grep -v '^[[:space:]]*#' "${HOME}/.config/claude-desktop-flags.conf" 2>/dev/null | tr '\n' ' ')
    FLAGS="${FLAGS} ${USER_FLAGS}"
fi

for bin_path in /usr/lib/claude-desktop/claude-desktop /opt/claude-desktop/claude-desktop /usr/share/claude-desktop/claude-desktop /usr/lib64/claude-desktop/claude-desktop; do
    if [ -x "${bin_path}" ]; then
        exec "${bin_path}" ${FLAGS} "$@"
    fi
done

echo "Error: claude-desktop binary not found in /usr/lib/claude-desktop/" >&2
exit 1
CLAUDE_WRAPPER_EOF
        chmod 755 "${staging_root}/usr/bin/claude-desktop"
        ln -sf claude-desktop "${staging_root}/usr/bin/claude"

        for df in "${staging_root}/usr/share/applications"/claude*.desktop "${staging_root}/usr/share/applications"/Claude*.desktop; do
            if [ -f "${df}" ]; then
                sed -i 's|^Exec=.*|Exec=/usr/bin/claude-desktop %U|g; s|^TryExec=.*|TryExec=/usr/bin/claude-desktop|g' "${df}"
            fi
        done

        for sz in 16x16 24x24 32x32 48x48 64x64 128x128 256x256 512x512 scalable; do
            if [ -f "${staging_root}/usr/share/icons/hicolor/${sz}/apps/claude-desktop.png" ]; then
                cp -a "${staging_root}/usr/share/icons/hicolor/${sz}/apps/claude-desktop.png" "${staging_root}/usr/share/pixmaps/claude-desktop.png" 2>/dev/null || true
            elif [ -f "${staging_root}/usr/share/icons/hicolor/${sz}/apps/claude.png" ]; then
                cp -a "${staging_root}/usr/share/icons/hicolor/${sz}/apps/claude.png" "${staging_root}/usr/share/pixmaps/claude-desktop.png" 2>/dev/null || true
            fi
        done
    fi

    if [ "${pkg_id}" = "claude-code" ]; then
        mkdir -p "${staging_root}/usr/bin"
        cat << 'CLAUDE_CODE_WRAPPER_EOF' > "${staging_root}/usr/bin/claude-code"
#!/bin/sh
# Anthropic Claude Code CLI Launcher for Slackware
if [ -x /opt/claude-code/claude-code ]; then
    exec /opt/claude-code/claude-code "$@"
elif [ -x /opt/claude-code/claude ]; then
    exec /opt/claude-code/claude "$@"
else
    echo "Error: claude-code binary not found in /opt/claude-code/" >&2
    exit 1
fi
CLAUDE_CODE_WRAPPER_EOF
        chmod 755 "${staging_root}/usr/bin/claude-code"
        ln -sf claude-code "${staging_root}/usr/bin/claude-cli" 2>/dev/null || true
    fi

    if [ "${pkg_id}" = "gemini-cli" ]; then
        mkdir -p "${staging_root}/usr/bin"
        cat << 'GEMINI_CLI_WRAPPER_EOF' > "${staging_root}/usr/bin/gemini-cli"
#!/bin/sh
# Google Gemini CLI Launcher for Slackware
NODE_BIN="$(which node 2>/dev/null || echo /usr/bin/node)"
if [ ! -x "${NODE_BIN}" ]; then
    echo "Error: Node.js (>=20) is required to run gemini-cli." >&2
    exit 1
fi
if [ -f /opt/gemini-cli/bundle/gemini.js ]; then
    exec "${NODE_BIN}" /opt/gemini-cli/bundle/gemini.js "$@"
else
    echo "Error: gemini-cli bundle not found in /opt/gemini-cli/bundle/gemini.js" >&2
    exit 1
fi
GEMINI_CLI_WRAPPER_EOF
        chmod 755 "${staging_root}/usr/bin/gemini-cli"
        ln -sf gemini-cli "${staging_root}/usr/bin/gemini" 2>/dev/null || true
    fi

    if [ "${pkg_id}" = "opera" ]; then
        mkdir -p "${staging_root}/usr/bin"
        cat << 'OPERA_WRAPPER_EOF' > "${staging_root}/usr/bin/opera"
#!/bin/sh
# Opera Web Browser Launcher for Slackware
FLAGS=""
if [ -n "${WAYLAND_DISPLAY:-}" ]; then
    FLAGS="--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations"
fi
for opera_bin in /usr/lib64/opera/opera /usr/lib/opera/opera /opt/opera/opera; do
    if [ -x "${opera_bin}" ]; then
        exec "${opera_bin}" ${FLAGS} "$@"
    fi
done
exec /usr/lib/opera/opera ${FLAGS} "$@"
OPERA_WRAPPER_EOF
        chmod 755 "${staging_root}/usr/bin/opera"
    fi

    if [ "${pkg_id}" = "gnome-disk-utility" ]; then
        mkdir -p "${staging_root}/usr/share/glib-2.0/schemas"
        # Ensure libhandy is accessible in /usr/lib64 if provided
        if [ -d "${staging_root}/usr/lib" ] && [ ! -d "${staging_root}/usr/lib64" ]; then
            mkdir -p "${staging_root}/usr/lib64"
            cp -a "${staging_root}"/usr/lib/libhandy*.so* "${staging_root}/usr/lib64/" 2>/dev/null || true
        fi
    fi

    if [ "${pkg_id}" = "spacenav" ] || [ "${pkg_id}" = "spacenavd" ]; then
        mkdir -p "${staging_root}/etc/rc.d" "${staging_root}/lib/udev/rules.d" "${staging_root}/usr/bin"
        cat << 'SPACENAV_UDEV_EOF' > "${staging_root}/lib/udev/rules.d/99-spacenav.rules"
# 3Dconnexion SpaceNavigator / SpaceMouse udev rules for Slackware
SUBSYSTEM=="usb", ATTRS{idVendor}=="046d", ATTRS{idProduct}=="c62[0-9|a-f]", MODE="0666", TAG+="uaccess"
SUBSYSTEM=="usb", ATTRS{idVendor}=="256f", MODE="0666", TAG+="uaccess"
KERNEL=="event[0-9]*", ATTRS{idVendor}=="046d", ATTRS{idProduct}=="c62[0-9|a-f]", MODE="0666", TAG+="uaccess"
KERNEL=="event[0-9]*", ATTRS{idVendor}=="256f", MODE="0666", TAG+="uaccess"
SPACENAV_UDEV_EOF

        cat << 'SPACENAV_RC_EOF' > "${staging_root}/etc/rc.d/rc.spacenavd"
#!/bin/sh
# /etc/rc.d/rc.spacenavd - 3Dconnexion SpaceMouse daemon service for Slackware
BIN="/usr/bin/spacenavd"

spacenav_start() {
  if [ -x "$BIN" ]; then
    echo "Starting 3Dconnexion SpaceMouse daemon (spacenavd)..."
    $BIN -d >/var/log/spacenavd.log 2>&1 &
  fi
}
spacenav_stop() {
  echo "Stopping 3Dconnexion SpaceMouse daemon..."
  pkill -x spacenavd 2>/dev/null || true
}
spacenav_status() {
  if pgrep -x spacenavd >/dev/null 2>&1; then
    echo "spacenavd is running (PID: $(pgrep -x spacenavd))."
  else
    echo "spacenavd is NOT running."
  fi
}
case "$1" in
  start) spacenav_start ;;
  stop) spacenav_stop ;;
  restart) spacenav_stop; sleep 1; spacenav_start ;;
  status) spacenav_status ;;
  *) echo "Usage: $0 {start|stop|restart|status}" ;;
esac
SPACENAV_RC_EOF
        chmod 755 "${staging_root}/etc/rc.d/rc.spacenavd"
    fi

    if [ "${pkg_id}" = "volt-gui" ]; then
        mkdir -p "${staging_root}/usr/bin"
        cat << 'VOLT_GUI_WRAPPER_EOF' > "${staging_root}/usr/bin/volt-gui"
#!/bin/bash
# Volt GUI Slackware Launch Wrapper
export VOLT_GUI_DIR="/opt/volt-gui"
PY_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "3.11")
export PYTHONPATH="${VOLT_GUI_DIR}:${VOLT_GUI_DIR}/lib/python${PY_VER}/site-packages:${VOLT_GUI_DIR}/lib:${PYTHONPATH:-}"

if [ -f "${VOLT_GUI_DIR}/volt-gui.py" ]; then
    exec python3 "${VOLT_GUI_DIR}/volt-gui.py" "$@"
elif [ -f "${VOLT_GUI_DIR}/src/volt-gui/volt-gui.py" ]; then
    exec python3 "${VOLT_GUI_DIR}/src/volt-gui/volt-gui.py" "$@"
elif [ -f "/usr/share/volt-gui/volt-gui.py" ]; then
    exec python3 "/usr/share/volt-gui/volt-gui.py" "$@"
elif command -v volt-gui.py >/dev/null 2>&1; then
    exec python3 "$(command -v volt-gui.py)" "$@"
else
    echo "Error: volt-gui script not found in ${VOLT_GUI_DIR}." >&2
    exit 1
fi
VOLT_GUI_WRAPPER_EOF
        chmod 755 "${staging_root}/usr/bin/volt-gui"
    fi

    if [ "${pkg_id}" = "bambu-studio" ]; then
        # 6A-198: the old Arch package shipped 99-bambulab-devices.rules (mode 0666 for every CH340 USB-serial device, so every
        # user could open them). Never shipped here; repair for installed copies: docs/repair/6A-198_remove_bambu_udev_rule.sh.
        rm -f -- "${staging_root}"/etc/udev/rules.d/99-bambulab-devices.rules \
                 "${staging_root}"/lib/udev/rules.d/99-bambulab-devices.rules \
                 "${staging_root}"/usr/lib/udev/rules.d/99-bambulab-devices.rules \
                 "${staging_root}"/usr/lib64/udev/rules.d/99-bambulab-devices.rules 2>/dev/null || true
        mkdir -p "${staging_root}/usr/bin"
        cat << 'BAMBU_WRAPPER_EOF' > "${staging_root}/usr/bin/bambu-studio"
#!/bin/sh
# Bambu Studio Launcher with GPU auto-detection for Slackware
export BAMBU_STUDIO_DIR="/opt/bambu-studio"
export LD_LIBRARY_PATH="${BAMBU_STUDIO_DIR}/lib:${BAMBU_STUDIO_DIR}/bin:${LD_LIBRARY_PATH:-}"
export WEBKIT_EXEC_PATH="${BAMBU_STUDIO_DIR}/lib/webkit2gtk-4.1:/usr/lib64/webkit2gtk-4.1:/usr/lib/webkit2gtk-4.1"
export WEBKIT_INJECTED_BUNDLE_PATH="${BAMBU_STUDIO_DIR}/lib/webkit2gtk-4.1/injected-bundle:/usr/lib64/webkit2gtk-4.1/injected-bundle:/usr/lib/webkit2gtk-4.1/injected-bundle"

# WebKitGTK sandbox and NVIDIA/Wayland DMA-BUF controls
export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1
export WEBKIT_DISABLE_DMABUF_RENDERER=1

# 6A-128: only when a GPU is bound to the proprietary/open nvidia driver (never for nouveau: its OpenGL is Mesa)
BAMBU_NV_BOUND=0
for BAMBU_NV_DEV in /sys/bus/pci/drivers/nvidia/[0-9a-f]*:*; do
    if [ -e "${BAMBU_NV_DEV}" ]; then BAMBU_NV_BOUND=1; break; fi
done
if [ "${BAMBU_NV_BOUND}" = "1" ]; then
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __VK_LAYER_NV_optimus=NVIDIA_only
fi

if [ -z "${GSETTINGS_SCHEMA_DIR:-}" ]; then
    export GSETTINGS_SCHEMA_DIR="/usr/share/glib-2.0/schemas"
fi

for bin_path in "${BAMBU_STUDIO_DIR}/bin/bambu-studio" "${BAMBU_STUDIO_DIR}/AppRun" "/usr/bin/bambu-studio-bin" "${BAMBU_STUDIO_DIR}/bambu-studio"; do
    if [ -x "${bin_path}" ]; then
        exec "${bin_path}" "$@"
    fi
done

echo "Error: Bambu Studio executable not found in ${BAMBU_STUDIO_DIR}" >&2
exit 1
BAMBU_WRAPPER_EOF
        chmod 755 "${staging_root}/usr/bin/bambu-studio"
        ln -sf bambu-studio "${staging_root}/usr/bin/BambuStudio" 2>/dev/null || true
        # 6A-192: the AppImage sits in opt/bambu-studio-<version>; the launcher uses /opt/bambu-studio
        if [ -d "${staging_root}/opt/bambu-studio-${ver}" ]; then
            local bs_app="${staging_root}/opt/bambu-studio-${ver}" bs_icon bs_size
            ln -sfn "bambu-studio-${ver}" "${staging_root}/opt/bambu-studio"
            if [ -f "${bs_app}/BambuStudio.desktop" ]; then
                mkdir -p "${staging_root}/usr/share/applications"
                sed -e 's|^Exec=.*|Exec=bambu-studio %U|' -e 's|^Icon=.*|Icon=bambu-studio|' -e 's|^Name=.*|Name=Bambu Studio|' -e '/^X-AppImage-Version=/d' \
                    "${bs_app}/BambuStudio.desktop" > "${staging_root}/usr/share/applications/bambu-studio.desktop"
                chmod 644 "${staging_root}/usr/share/applications/bambu-studio.desktop"
            fi
            for bs_icon in "${bs_app}"/usr/share/icons/hicolor/*/apps/BambuStudio.png; do
                [ -f "${bs_icon}" ] || continue
                bs_size=$(basename "$(dirname "$(dirname "${bs_icon}")")")
                mkdir -p "${staging_root}/usr/share/icons/hicolor/${bs_size}/apps"
                cp -f "${bs_icon}" "${staging_root}/usr/share/icons/hicolor/${bs_size}/apps/bambu-studio.png"
            done
            if [ -f "${bs_app}/BambuStudio.png" ]; then
                mkdir -p "${staging_root}/usr/share/pixmaps"
                cp -f "${bs_app}/BambuStudio.png" "${staging_root}/usr/share/pixmaps/bambu-studio.png"
            fi
            # the library parts are libraries only: no command line tools, no development files
            rm -f "${staging_root}/usr/bin/avifenc" "${staging_root}/usr/bin/avifdec" "${staging_root}/usr/bin/avifgainmaputil" \
                  "${staging_root}/usr/bin/SvtAv1EncApp" "${staging_root}/usr/bin/rav1e" 2>/dev/null || true
            rm -rf "${staging_root}/usr/lib64/cmake" "${staging_root}/usr/lib64/pkgconfig" "${staging_root}/usr/share/vala" "${staging_root}/usr/share/man" 2>/dev/null || true
        fi
    fi

    if [ "${pkg_id}" = "blender" ]; then
        mkdir -p "${staging_root}/usr/bin"
        # 6A-185: the launcher below must not overwrite the program. Keep the package's own program as usr/bin/blender-bin
        # (the launcher starts that one first); without this the launcher ended up calling itself and the program was lost.
        if [ -L "${staging_root}/usr/bin/blender" ]; then
            rm -f "${staging_root}/usr/bin/blender"
        elif [ -f "${staging_root}/usr/bin/blender" ] && [ ! -e "${staging_root}/usr/bin/blender-bin" ] && [ ! -L "${staging_root}/usr/bin/blender-bin" ]; then
            mv "${staging_root}/usr/bin/blender" "${staging_root}/usr/bin/blender-bin"
        fi
        cat << 'BLENDER_WRAPPER_EOF' > "${staging_root}/usr/bin/blender"
#!/bin/sh
# Blender Launch Wrapper for Slackware
ulimit -n 1048576 2>/dev/null || true

# GPU Acceleration
if lspci 2>/dev/null | grep -i "vga\|3d" | grep -qi "nvidia"; then
    [ -d "/usr/local/cuda" ] && export CUDA_PATH="/usr/local/cuda"
    export LD_LIBRARY_PATH="/usr/lib64:${LD_LIBRARY_PATH:-}"
    export CYCLES_CUDA_EXTRA_CFLAGS="-O3"
    export __GL_SHADER_DISK_CACHE=1
elif lspci 2>/dev/null | grep -i "vga\|3d" | grep -qi "amd\|radeon"; then
    [ -d "/opt/rocm" ] && export ROCM_PATH="/opt/rocm"
    [ -d "/opt/rocm/hip" ] && export HIP_PATH="/opt/rocm/hip"
fi

# Auto-start spacenavd if SpaceMouse device is connected
if [ -c "/dev/hidraw0" ] && lsusb 2>/dev/null | grep -qi "256f:\|046d:c6"; then
    if [ ! -S "/run/spnav.sock" ] && [ ! -S "/var/run/spnav.sock" ]; then
        if [ -x /etc/rc.d/rc.spacenavd ] && ! pgrep -x spacenavd >/dev/null 2>&1; then
            sudo /etc/rc.d/rc.spacenavd start 2>/dev/null || true
        fi
    fi
fi

for bin_path in /usr/bin/blender-bin /usr/bin/blender /opt/blender/blender; do
    if [ -x "${bin_path}" ] && [ "${bin_path}" != "/usr/bin/blender" ]; then
        exec "${bin_path}" "$@"
    fi
done
exec /usr/bin/blender "$@"
BLENDER_WRAPPER_EOF
        chmod 755 "${staging_root}/usr/bin/blender"
    fi

    if [ "${pkg_id}" = "freecad" ]; then
        mkdir -p "${staging_root}/usr/bin"
        # 6A-191: opencascade ships a login-environment script for every user; it has no place in this package
        rm -f "${staging_root}/etc/profile.d/opencascade.sh" "${staging_root}/etc/profile.d/opencascade.csh"
        # never write the launcher through a link of the package
        [ -L "${staging_root}/usr/bin/freecad" ] && rm -f "${staging_root}/usr/bin/freecad"
        cat << 'FREECAD_WRAPPER_EOF' > "${staging_root}/usr/bin/freecad"
#!/bin/sh
# FreeCAD Launch Wrapper for Slackware
ulimit -n 1048576 2>/dev/null || true

if lspci 2>/dev/null | grep -i "vga\|3d" | grep -qi "nvidia"; then
    [ -d "/usr/local/cuda" ] && export CUDA_PATH="/usr/local/cuda"
    export LD_LIBRARY_PATH="/usr/lib64:${LD_LIBRARY_PATH:-}"
    export __GL_SHADER_DISK_CACHE=1
elif lspci 2>/dev/null | grep -i "vga\|3d" | grep -qi "amd\|radeon"; then
    [ -d "/opt/rocm" ] && export ROCM_PATH="/opt/rocm"
fi

if [ -c "/dev/hidraw0" ] && lsusb 2>/dev/null | grep -qi "256f:\|046d:c6"; then
    if [ ! -S "/run/spnav.sock" ] && [ ! -S "/var/run/spnav.sock" ]; then
        if [ -x /etc/rc.d/rc.spacenavd ] && ! pgrep -x spacenavd >/dev/null 2>&1; then
            sudo /etc/rc.d/rc.spacenavd start 2>/dev/null || true
        fi
    fi
fi

for bin_path in /usr/bin/FreeCAD /usr/lib64/freecad/bin/FreeCAD /usr/lib/freecad/bin/FreeCAD /opt/freecad/AppRun /opt/freecad/bin/freecad; do
    if [ -x "${bin_path}" ]; then
        exec "${bin_path}" "$@"
    fi
done
exec FreeCAD "$@"
FREECAD_WRAPPER_EOF
        chmod 755 "${staging_root}/usr/bin/freecad"
        # 6A-186: the package's own FreeCAD link stays; the launcher tries /usr/bin/FreeCAD first, so a link to the launcher
        # would make it call itself. Only when the package has none, link to the program (never to the launcher).
        if [ ! -e "${staging_root}/usr/bin/FreeCAD" ] && [ ! -L "${staging_root}/usr/bin/FreeCAD" ] && [ -f "${staging_root}/usr/lib64/freecad/bin/FreeCAD" ]; then
            ln -s ../lib64/freecad/bin/FreeCAD "${staging_root}/usr/bin/FreeCAD" 2>/dev/null || true
        fi
    fi

    if [ "${pkg_id}" = "plasticity" ]; then
        mkdir -p "${staging_root}/usr/bin"
        cat << 'PLASTICITY_WRAPPER_EOF' > "${staging_root}/usr/bin/plasticity"
#!/bin/sh
# Plasticity 3D CAD Launcher for Slackware
FLAGS=""
if [ -n "${WAYLAND_DISPLAY:-}" ]; then
    FLAGS="--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations"
fi
for bin_path in /opt/plasticity/plasticity /opt/Plasticity/plasticity /usr/lib/plasticity/plasticity; do
    if [ -x "${bin_path}" ]; then
        exec "${bin_path}" ${FLAGS} "$@"
    fi
done
exec /opt/plasticity/plasticity ${FLAGS} "$@"
PLASTICITY_WRAPPER_EOF
        chmod 755 "${staging_root}/usr/bin/plasticity"
        ln -sf plasticity "${staging_root}/usr/bin/Plasticity" 2>/dev/null || true
    fi

    if [ "${pkg_id}" = "storyboarder" ]; then
        mkdir -p "${staging_root}/usr/bin"
        cat << 'STORYBOARDER_WRAPPER_EOF' > "${staging_root}/usr/bin/storyboarder"
#!/bin/sh
# Storyboarder Pre-Vis Launcher for Slackware
FLAGS=""
if [ -n "${WAYLAND_DISPLAY:-}" ]; then
    FLAGS="--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations"
fi
for bin_path in /opt/storyboarder/storyboarder /opt/Storyboarder/storyboarder /usr/lib/storyboarder/storyboarder; do
    if [ -x "${bin_path}" ]; then
        exec "${bin_path}" ${FLAGS} "$@"
    fi
done
exec /opt/storyboarder/storyboarder ${FLAGS} "$@"
STORYBOARDER_WRAPPER_EOF
        chmod 755 "${staging_root}/usr/bin/storyboarder"
        ln -sf storyboarder "${staging_root}/usr/bin/Storyboarder" 2>/dev/null || true
    fi

    if [ "${pkg_id}" = "dvcp-aac" ]; then
        mkdir -p "${staging_root}/opt/resolve/IOPlugins" \
                 "${staging_root}/usr/bin"

        cat << 'RESOLVE_AAC_CHECK_EOF' > "${staging_root}/usr/bin/resolve-aac-status"
#!/bin/sh
# DaVinci Resolve AAC Audio Bridge Status Checker
echo "=== DaVinci Resolve AAC Audio Bridge Status ==="
if [ -d "/opt/resolve/IOPlugins/aac_decoder_probe.dvcp.bundle" ] && [ -d "/opt/resolve/IOPlugins/aac_fdk_plugin.dvcp.bundle" ]; then
    echo "  [OK] AAC Decoder Plugin (Import & Playback) : Active in /opt/resolve/IOPlugins"
    echo "  [OK] AAC Encoder Plugin (Export & Render)   : Active in /opt/resolve/IOPlugins"
    echo "  [OK] Status: DaVinci Resolve Studio is armed with full native AAC support!"
else
    echo "  [!] Warning: One or more AAC plugin bundles are missing from /opt/resolve/IOPlugins."
fi
RESOLVE_AAC_CHECK_EOF
        chmod 755 "${staging_root}/usr/bin/resolve-aac-status"
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
        mkdir -p "${staging_root}/usr/lib64" "${staging_root}/usr/lib"
        for subdir in audacity suil-0 wx; do
            if [ -d "${staging_root}/usr/lib64/${subdir}" ] && [ ! -d "${staging_root}/usr/lib/${subdir}" ]; then
                ln -sf "../lib64/${subdir}" "${staging_root}/usr/lib/${subdir}"
            elif [ -d "${staging_root}/usr/lib/${subdir}" ] && [ ! -d "${staging_root}/usr/lib64/${subdir}" ]; then
                cp -a "${staging_root}/usr/lib/${subdir}" "${staging_root}/usr/lib64/"
                rm -rf "${staging_root}/usr/lib/${subdir}"
                ln -sf "../lib64/${subdir}" "${staging_root}/usr/lib/${subdir}"
            fi
        done

        # 6A-163: the old etc/ld.so.conf.d/audacity.conf put /usr/lib64 and /usr/lib on the linker path of the whole system.
        # Never shipped any more; the wrapper below sets LD_LIBRARY_PATH for Audacity alone.
        rm -f "${staging_root}/etc/ld.so.conf.d/audacity.conf" 2>/dev/null || true

        # Wrap /usr/bin/audacity to ensure LD_LIBRARY_PATH always finds private libraries.
        # 6A-165: only when the program really moved behind the wrapper; without usr/lib64/audacity the program stays as it is
        if [ -f "${staging_root}/usr/bin/audacity" ] && [ -d "${staging_root}/usr/lib64/audacity" ] \
            && mv -f "${staging_root}/usr/bin/audacity" "${staging_root}/usr/lib64/audacity/audacity.bin"; then
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
export XCURSOR_SIZE="${XCURSOR_SIZE:-30}"
export XCURSOR_THEME="${XCURSOR_THEME:-MacTahoe-cursors}"

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

def get_foreground_pid():
    # Detect active window in Hyprland, KDE Plasma Wayland, or X11 / Gamescope
    for cmd in [
        ["hyprctl", "activewindow", "-j"],
        ["kdotool", "getactivewindow", "getwindowpid"],
        ["xdotool", "getactivewindow", "getwindowpid"]
    ]:
        try:
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=0.5)
            if res.returncode == 0 and res.stdout.strip():
                if cmd[0] == "hyprctl":
                    import json
                    w_data = json.loads(res.stdout)
                    w_pid = w_data.get("pid")
                    if w_pid and str(w_pid).isdigit() and int(w_pid) > 0:
                        return str(w_pid)
                elif res.stdout.strip().isdigit():
                    return res.stdout.strip()
        except Exception:
            pass
    return None

def scan_and_boost_games():
    boosted = get_boosted_pids()
    count = 0

    # 1. Boost active Wayland / X11 / Gamescope foreground window
    fg_pid = get_foreground_pid()
    if fg_pid and fg_pid not in boosted:
        try:
            with open(f"/proc/{fg_pid}/comm", "r") as f:
                fg_comm = f.read().strip()
            if fg_comm not in ["plasmashell", "kwin_wayland", "systemsettings", "konsole", "zsh", "bash", "Hyprland", "noctalia", "waybar", "xfwm4", "xfce4-panel", "xfdesktop"]:
                if boost_pid(fg_pid):
                    log(f"Foreground GPU Shield: Boosted active window '{fg_comm}' (PID {fg_pid}) into dmemcg-gaming slice")
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
                        log(f"Boosted gaming process: {comm} (PID {p}) into dmemcg-gaming slice")
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
${pkg_name}: Step 3: PROFIT!!!
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
  for d in /usr/share/icons/MacTahoe* /usr/share/icons/WhiteSur*; do
    if [ -d "$d" ] && [ -f "$d/index.theme" ]; then
      /usr/bin/gtk-update-icon-cache -f -q "$d" 2>/dev/null || true
    fi
  done
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

    slacky_rc_helpers >> "${staging_root}/install/doinst.sh"
    cat << 'DOINST_TAIL_EOF' >> "${staging_root}/install/doinst.sh"
# 6A-6: libelogind compatibility links in the pkgtools "( cd DIR ; rm -rf LINK )" form, so removepkg records them and removes
# them with the last curated package (it only ever deletes symlinks, never a real libsystemd). Never replaces an existing one.
if [ -f lib64/libelogind.so.0 ] && [ ! -e usr/lib64/libsystemd.so.0 ]; then
  mkdir -p usr/lib64
  ( cd usr/lib64 ; rm -rf libsystemd.so.0 )
  ( cd usr/lib64 ; ln -sf /lib64/libelogind.so.0 libsystemd.so.0 )
fi
if [ -f lib/libelogind.so.0 ] && [ ! -e usr/lib/libsystemd.so.0 ]; then
  mkdir -p usr/lib
  ( cd usr/lib ; rm -rf libsystemd.so.0 )
  ( cd usr/lib ; ln -sf /lib/libelogind.so.0 libsystemd.so.0 )
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
  # 6A-170: remove a link inside a plugin folder that has the folder's own name and points at the folder or at the host copy
  # (made by an older run of the loop below: <plugin>/<plugin> -> /usr/share/obs/obs-plugins/<plugin>)
  for obsd in /usr/share/obs/obs-plugins/*/ /opt/obs-studio/share/obs/obs-plugins/*/ /usr/lib64/obs-plugins/*/ /opt/obs-studio/lib/obs-plugins/*/; do
    [ -d "${obsd}" ] || continue
    obsn=$(basename "${obsd}")
    [ -L "${obsd}${obsn}" ] || continue
    obst=$(readlink "${obsd}${obsn}")
    if [ "${obsd}${obsn}" -ef "${obsd%/}" ] || [ "${obst}" = "/usr/share/obs/obs-plugins/${obsn}" ] || [ "${obst}" = "/usr/lib64/obs-plugins/${obsn}" ]; then
      rm -f "${obsd}${obsn}" 2>/dev/null || true
    fi
  done
  if [ -d /usr/lib64/obs-plugins ]; then
    # Clean up stray modular sub-plugins erroneously placed in root plugin directories by earlier builds
    for stray_so in /usr/lib64/obs-plugins/advanced-scene-switcher-*.so /opt/obs-studio/lib/obs-plugins/advanced-scene-switcher-*.so; do
      [ -f "${stray_so}" ] || continue
      rm -f "${stray_so}" 2>/dev/null || true
    done
    for obsitem in /usr/lib64/obs-plugins/*; do
      [ -e "${obsitem}" ] || continue
      obsbname=$(basename "${obsitem}")
      # 6A-170: bundle folder and host folder are the same place, or the link is already right: nothing to do
      [ /opt/obs-studio/lib/obs-plugins -ef /usr/lib64/obs-plugins ] && break
      [ -L "/opt/obs-studio/lib/obs-plugins/${obsbname}" ] && [ "/opt/obs-studio/lib/obs-plugins/${obsbname}" -ef "${obsitem}" ] && continue
      ( cd /opt/obs-studio/lib/obs-plugins && rm -rf "${obsbname}" && ln -sfn "${obsitem}" "${obsbname}" 2>/dev/null || true )
    done
  fi
  if [ -d /usr/share/obs/obs-plugins ]; then
    for obsdir in /usr/share/obs/obs-plugins/*; do
      [ -d "${obsdir}" ] || continue
      obsbname=$(basename "${obsdir}")
      [ /opt/obs-studio/share/obs/obs-plugins -ef /usr/share/obs/obs-plugins ] && break
      [ -L "/opt/obs-studio/share/obs/obs-plugins/${obsbname}" ] && [ "/opt/obs-studio/share/obs/obs-plugins/${obsbname}" -ef "${obsdir}" ] && continue
      ( cd /opt/obs-studio/share/obs/obs-plugins && rm -rf "${obsbname}" && ln -sfn "${obsdir}" "${obsbname}" 2>/dev/null || true )
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

# 6A-6c: daemon start/stop hooks as marker blocks (helpers printed above by slacky_rc_helpers). Exact old unmarked
# blocks are migrated in place; hand-edited ones are left alone.
echo "${SU_RC_DAEMONS}" | while IFS='|' read -r su_dn su_dd; do
  [ -n "${su_dn}" ] && [ -f "/etc/rc.d/rc.${su_dn}" ] || continue
  chmod 755 "/etc/rc.d/rc.${su_dn}" 2>/dev/null || true
  su_rc_migrate /etc/rc.d/rc.local "${su_dn}" start "Start ${su_dd}"
  su_rc_migrate /etc/rc.d/rc.local_shutdown "${su_dn}" stop "Stop ${su_dd}"
  printf 'if [ -x /etc/rc.d/rc.%s ]; then\n  /etc/rc.d/rc.%s start\nfi\n' "${su_dn}" "${su_dn}" | su_rc_add /etc/rc.d/rc.local "${su_dn}"
  printf 'if [ -x /etc/rc.d/rc.%s ]; then\n  /etc/rc.d/rc.%s stop\nfi\n' "${su_dn}" "${su_dn}" | su_rc_add /etc/rc.d/rc.local_shutdown "${su_dn}"
done

# 6A-83: boot-time module loading in rc.modules.local (marked block per module; skipped when the sysadmin already loads it)
echo "${SU_RC_MODULES}" | while IFS='|' read -r su_mn su_ms; do
  [ -n "${su_mn}" ] && [ -e "${su_ms}" ] || continue
  su_mf=/etc/rc.d/rc.modules.local
  if [ ! -e "${su_mf}" ]; then
    printf '#!/bin/sh\n# /etc/rc.d/rc.modules.local - local kernel modules loaded at boot\n' > "${su_mf}" && chmod 755 "${su_mf}"
  fi
  if ! su_mod_listed "${su_mf}" "${su_mn}"; then
    printf '/sbin/modprobe -q %s\n' "${su_mn}" | su_rc_add "${su_mf}" "module-${su_mn}"
  fi
  [ -x "${su_mf}" ] || echo "slacky-update: ${su_mf} is not executable, so ${su_mn} will not load at boot. Fix: chmod +x ${su_mf}" >&2
  # zenpower is loaded by its own step below (k10temp has to let go of the sensor first)
  [ "${su_mn}" = "zenpower" ] || /sbin/modprobe -q "${su_mn}" 2>/dev/null || true
done

if [ -d /etc/easyeffects/output ]; then
  mkdir -p /etc/skel/.config/easyeffects/output /etc/skel/.config/easyeffects/irs 2>/dev/null || true
  cp -n /etc/easyeffects/output/*.json /etc/skel/.config/easyeffects/output/ 2>/dev/null || true
  if [ -d /etc/easyeffects/irs ]; then
    cp -n /etc/easyeffects/irs/* /etc/skel/.config/easyeffects/irs/ 2>/dev/null || true
  fi
  for jf in /etc/skel/.config/easyeffects/output/*.json; do
    [ -f "${jf}" ] || continue
    sed -i "s|<PRESETS_DIRECTORY>|\$HOME/.config/easyeffects|g" "${jf}" 2>/dev/null || true
  done
  target_user="${SUDO_USER:-${USER:-}}"
  if [ -n "${target_user}" ] && [ "${target_user}" != "root" ] && [ -d "/home/${target_user}" ]; then
    u_home="/home/${target_user}"
    mkdir -p "${u_home}/.config/easyeffects/output" "${u_home}/.config/easyeffects/irs" 2>/dev/null || true
    cp -n /etc/easyeffects/output/*.json "${u_home}/.config/easyeffects/output/" 2>/dev/null || true
    if [ -d /etc/easyeffects/irs ]; then
      cp -n /etc/easyeffects/irs/* "${u_home}/.config/easyeffects/irs/" 2>/dev/null || true
    fi
    for jf in "${u_home}/.config/easyeffects/output"/*.json; do
      [ -f "${jf}" ] || continue
      sed -i "s|<PRESETS_DIRECTORY>|${u_home}/.config/easyeffects|g" "${jf}" 2>/dev/null || true
    done
    chown -R "${target_user}:users" "${u_home}/.config/easyeffects" 2>/dev/null || true
  fi
fi
DOINST_TAIL_EOF

    # Conditionally append DKMS & Kernel Module handler ONLY for driver packages
    local has_dkms_driver=0
    if compgen -G "${staging_root}/usr/src/*/dkms.conf" >/dev/null 2>&1 || compgen -G "${staging_root}/var/lib/dkms/*" >/dev/null 2>&1; then
        has_dkms_driver=1
    fi
    case "${pkg_id}" in
        zenpower3|v4l2loopback|rtl8821cu|rtl88x2bu|rtl8812au|broadcom-wl|r8125)
            has_dkms_driver=1
            ;;
    esac

    if [ "${has_dkms_driver}" -eq 1 ]; then
        printf 'SU_DKMS_OWN="%s"\n' "$(slacky_dkms_own_entries "${staging_root}" | cut -d'|' -f1 | tr '\n' ' ')" >> "${staging_root}/install/doinst.sh"
        cat << 'DKMS_DOINST_EOF' >> "${staging_root}/install/doinst.sh"

# DKMS Kernel Driver Auto-registration & Compilation (Drivers Only)
# 6A-166: only the source folders THIS package ships are registered (never another driver's /usr/src/*/dkms.conf)
# 6A-100: while slacky-update runs (its run lock is held) only register the module; the update builds it once per kept
# kernel in its boot-chain step (this file asks for that), instead of building here for every kernel incl. dying ones
SS_DKMS_BUILD=1
if command -v flock >/dev/null 2>&1 && [ -e /run/lock/slacky-update.lock ] && ! flock -n /run/lock/slacky-update.lock true 2>/dev/null; then
  SS_DKMS_BUILD=0
  mkdir -p /var/cache/slacky-update 2>/dev/null || true
  touch /var/cache/slacky-update/dkms-build-pending 2>/dev/null || true
fi
if [ -x /usr/sbin/dkms ] || [ -x /usr/bin/dkms ]; then
  DKMS_BIN=$(command -v dkms 2>/dev/null || echo "/usr/sbin/dkms")
  for su_own in ${SU_DKMS_OWN}; do
    dconf="/usr/src/${su_own}/dkms.conf"
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
      "${DKMS_BIN}" add -m "${mod_name}" -v "${mod_ver}" >/dev/null 2>&1 || true
      [ "${SS_DKMS_BUILD}" = "1" ] || continue
      for kdir in /lib/modules/*; do
        [ -d "${kdir}/build" ] || continue
        kver=$(basename "${kdir}")
        if ! "${DKMS_BIN}" status -m "${mod_name}" -v "${mod_ver}" -k "${kver}" 2>/dev/null | grep -q "installed"; then
          "${DKMS_BIN}" build -m "${mod_name}" -v "${mod_ver}" -k "${kver}" >/dev/null 2>&1 || true
          "${DKMS_BIN}" install -m "${mod_name}" -v "${mod_ver}" -k "${kver}" >/dev/null 2>&1 || true
        fi
      done
    fi
  done
fi
DKMS_DOINST_EOF
    fi

    if [ "${pkg_id}" = "zenpower3" ] || [ -f "${staging_root}/etc/modprobe.d/zenpower.conf" ]; then
        cat << 'ZEN_DOINST_EOF' >> "${staging_root}/install/doinst.sh"
# 6A-167: the sensor driver is swapped only when the zenpower module really exists for the RUNNING kernel (the build can be
# deferred to the update's boot step or fail); if zenpower will not load, k10temp is loaded again
if [ -f /etc/modprobe.d/zenpower.conf ]; then
  su_zk=$(uname -r)
  if [ -n "$(find "/lib/modules/${su_zk}" -name 'zenpower.ko*' 2>/dev/null | head -n1)" ]; then
    /sbin/modprobe -r k10temp >/dev/null 2>&1 || true
    /sbin/modprobe zenpower >/dev/null 2>&1 || /sbin/modprobe k10temp >/dev/null 2>&1 || true
  fi
fi
ZEN_DOINST_EOF
    fi

    if [ "${pkg_id}" = "v4l2loopback" ] || [ -f "${staging_root}/etc/modprobe.d/v4l2loopback.conf" ]; then
        cat << 'V4L2_DOINST_EOF' >> "${staging_root}/install/doinst.sh"
if [ -f /etc/modprobe.d/v4l2loopback.conf ]; then
  /sbin/modprobe v4l2loopback >/dev/null 2>&1 || true
fi
V4L2_DOINST_EOF
    fi

    # 6A-25: the Hyprland suites ship their own session launcher. Arch's /usr/bin/start-hyprland (Hyprland >= 0.53,
    # crash watchdog) starts no D-Bus session bus, so with SDDM nothing in the session had a bus (tray, portals).
    # Packaged here instead of written with sudo after install (the old post-install branch is unreachable).
    if [ "${pkg_id}" = "hyprland-noctalia" ] || [ "${pkg_id}" = "hyprland-core" ]; then
        mkdir -p "${staging_root}/usr/bin" "${staging_root}/usr/share/wayland-sessions"
        cat << 'HYPR_SESSION_EOF' > "${staging_root}/usr/bin/start-hyprland-session"
#!/bin/sh
# Slacky-Update Hyprland session launcher: Wayland environment + a D-Bus session bus when the display manager gave none.
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_TYPE=wayland
export XDG_SESSION_DESKTOP=Hyprland
export MOZ_ENABLE_WAYLAND=1
export QT_QPA_PLATFORM="wayland;xcb"
export GDK_BACKEND="wayland,x11,*"
export CLUTTER_BACKEND=wayland
export SDL_VIDEODRIVER=wayland

if [ -f /etc/hypr/hyprland.env ]; then
    . /etc/hypr/hyprland.env
fi
# 6A-64: the user's own file is read last, so its settings always win
if [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.env" ]; then
    . "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.env"
fi

# 6A-78: multi-GPU machines list their GPUs by PCI slot; turn them into /dev/dri/cardN now (card numbers can change
# between boots) and skip a GPU that is gone. A user-set AQ_DRM_DEVICES always wins.
if [ -n "${SLACKY_DRM_ORDER:-}" ] && [ -z "${AQ_DRM_DEVICES:-}" ]; then
    _aq=""
    for _s in ${SLACKY_DRM_ORDER}; do
        _l="/dev/dri/by-path/pci-${_s}-card"
        [ -e "${_l}" ] || continue
        _n=$(readlink -f "${_l}") || continue
        _aq="${_aq:+${_aq}:}${_n}"
    done
    [ -n "${_aq}" ] && export AQ_DRM_DEVICES="${_aq}"
    unset _aq _s _l _n
fi

if [ -x /usr/bin/start-hyprland ]; then
    set -- /usr/bin/start-hyprland "$@"
else
    set -- Hyprland "$@"
fi

if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && command -v dbus-run-session >/dev/null 2>&1; then
    exec dbus-run-session "$@"
fi
exec "$@"
HYPR_SESSION_EOF
        chmod 755 "${staging_root}/usr/bin/start-hyprland-session"
        cat << 'HYPR_DESKTOP_EOF' > "${staging_root}/usr/share/wayland-sessions/hyprland.desktop"
[Desktop Entry]
Name=Hyprland
Comment=An intelligent dynamic tiling Wayland compositor
Exec=/usr/bin/start-hyprland-session
Type=Application
DesktopNames=Hyprland
Keywords=tiling;wayland;compositor;
HYPR_DESKTOP_EOF
        chmod 644 "${staging_root}/usr/share/wayland-sessions/hyprland.desktop"
    fi
    # 6A-129 (M7): admin-editable config ships as .new; config() installs it only when there is no file yet
    local cfg_new_list=() cfg_rel
    for cfg_rel in ${GAMING_CONFIG_NEW_FILES}; do
        [ -f "${staging_root}/${cfg_rel}" ] || continue
        mv -f "${staging_root}/${cfg_rel}" "${staging_root}/${cfg_rel}.new"
        cfg_new_list+=("${cfg_rel}")
    done
    if [ ${#cfg_new_list[@]} -gt 0 ]; then
        {
            cat << 'CONFIG_NEW_EOF'
config() {
  NEW="$1"
  OLD="$(dirname "$NEW")/$(basename "$NEW" .new)"
  if [ ! -r "$OLD" ]; then
    mv "$NEW" "$OLD"
  elif [ "$(md5sum < "$OLD")" = "$(md5sum < "$NEW")" ]; then
    rm "$NEW"
  fi
}
CONFIG_NEW_EOF
            for cfg_rel in "${cfg_new_list[@]}"; do
                echo "config ${cfg_rel}.new"
            done
        } >> "${staging_root}/install/doinst.sh"
    fi
    chmod 755 "${staging_root}/install/doinst.sh"

    # 6A-6c: remove a daemon's rc.local blocks when its rc script is gone. removepkg runs this after deleting the package's
    # files; during an upgrade (or while another package still ships the script) /etc/rc.d/rc.NAME exists and nothing
    # is touched. The daemon itself is stopped by the updater before removepkg.
    {
        echo '#!/bin/sh'
        slacky_rc_helpers
        cat << 'DOUNINST_EOF'
echo "${SU_RC_DAEMONS}" | while IFS='|' read -r su_dn su_dd; do
  [ -n "${su_dn}" ] || continue
  [ -e "/etc/rc.d/rc.${su_dn}" ] && continue
  su_rc_remove /etc/rc.d/rc.local "${su_dn}"
  su_rc_remove /etc/rc.d/rc.local_shutdown "${su_dn}"
done
# 6A-83: a module block goes only when the package that needs it is gone (not during an upgrade)
echo "${SU_RC_MODULES}" | while IFS='|' read -r su_mn su_ms; do
  [ -n "${su_mn}" ] || continue
  [ -e "${su_ms}" ] && continue
  su_rc_remove /etc/rc.d/rc.modules.local "module-${su_mn}"
done
DOUNINST_EOF
        # 6A-168: a DKMS driver package unregisters its module with DKMS when removepkg has deleted its source folder
        # (removepkg runs this script after the files are gone; an upgrade that keeps the folder changes nothing)
        local dkms_own
        dkms_own=$(slacky_dkms_own_entries "${staging_root}")
        if [ -n "${dkms_own}" ]; then
            printf 'SU_DKMS_OWN="%s"\n' "${dkms_own}"
            cat << 'DKMS_DOUNINST_EOF'
if [ -x /usr/sbin/dkms ] || [ -x /usr/bin/dkms ]; then
  DKMS_BIN=$(command -v dkms 2>/dev/null || echo "/usr/sbin/dkms")
  echo "${SU_DKMS_OWN}" | while IFS='|' read -r su_dn su_mn su_mv; do
    [ -n "${su_dn}" ] || continue
    [ -f "/usr/src/${su_dn}/dkms.conf" ] && continue
    [ -f "/usr/src/${su_mn}-${su_mv}/dkms.conf" ] && continue
    "${DKMS_BIN}" remove -m "${su_mn}" -v "${su_mv}" --all >/dev/null 2>&1 || true
    if [ -L "/usr/src/${su_mn}-${su_mv}" ] && [ ! -e "/usr/src/${su_mn}-${su_mv}" ]; then
      rm -f "/usr/src/${su_mn}-${su_mv}" 2>/dev/null || true
    fi
  done
fi
DKMS_DOUNINST_EOF
        fi
    } > "${staging_root}/install/douninst.sh"
    chmod 755 "${staging_root}/install/douninst.sh"

    # Permissions
    chmod -R u=rwX,go=rX "${staging_root}"
    [ -d "${staging_root}/etc/rc.d" ] && chmod 755 "${staging_root}/etc/rc.d/"* 2>/dev/null || true
    # 6A-129: chmod -R clears setuid; Electron's chrome-sandbox needs 4755 (the archive is packed as root:root)
    local sandbox_bin
    while IFS= read -r -d '' sandbox_bin; do
        chmod 4755 "${sandbox_bin}" 2>/dev/null || true
    done < <(find "${staging_root}" -type f -name chrome-sandbox -print0 2>/dev/null)

    # 6A-194: nothing is ever packed group- or world-writable (the installed underpants-hyprmod had 0666/0777 files; root runs
    # them). chmod above already clears it; this gate makes sure and stops the build if anything is still writable.
    if [ -n "$(find "${staging_root}" ! -type l -perm /022 -print -quit 2>/dev/null)" ]; then
        gaming_build_failed "${pkg_name} has files anyone could change. Package not built."
        return 1
    fi

    # 6A-195: no link or file with a name the package rules refuse
    gaming_drop_odd_names "${staging_root}" || { gaming_build_failed "Name check failed for ${pkg_name}. Package not built."; return 1; }

    # 6A-66: D-Bus activation files from Arch point at /usr/lib/...; on Slackware the program sits in /usr/lib64, so
    # activation silently failed (Hyprland portal, hyprpolkitagent). Rewritten only when the target is really in lib64.
    local dbus_svc dbus_exec
    for dbus_svc in "${staging_root}"/usr/share/dbus-1/services/*.service "${staging_root}"/usr/share/dbus-1/system-services/*.service; do
        [ -f "${dbus_svc}" ] || continue
        dbus_exec=$(sed -n 's/^Exec=\([^ ]*\).*/\1/p' "${dbus_svc}" | head -n1)
        case "${dbus_exec}" in
            /usr/lib/*)
                if [ ! -e "${staging_root}${dbus_exec}" ] && [ -e "${staging_root}/usr/lib64/${dbus_exec#/usr/lib/}" ]; then
                    sed -i "s|^Exec=/usr/lib/|Exec=/usr/lib64/|" "${dbus_svc}"
                fi
                ;;
        esac
    done

    # 2A/2B: Footprint Guard on the final staging tree (enforce mode unless SLACKY_FOOTPRINT_MODE=report)
    if [ -n "${GNOMES_PY:-}" ] && [ -f "${GNOMES_PY}" ]; then
        if ! python3 "${GNOMES_PY}" footprint-guard "${staging_root}" --label "${pkg_name}-${ver}"; then
            if [ "${SLACKY_FOOTPRINT_MODE:-enforce}" != "report" ]; then
                gaming_build_failed "Footprint check failed for ${pkg_name}. Package not built."  # 6A-125
                return 1
            fi
        fi
    elif [ "${SLACKY_FOOTPRINT_MODE:-enforce}" != "report" ]; then
        gaming_build_failed "Footprint check unavailable (gnomes_pacman.py not found). Package not built."
        return 1
    fi

    echo -e "  ${CYAN}•${RESET} Assembling Slackware package: ${pkg_name}-${ver}-x86_64-1_slacky.txz..."
    local txz_out="${staging_base}/${pkg_name}-${ver}-x86_64-1_slacky.txz"
    rm -f "${txz_out}"
    # 6A-125: a failed or truncated archive is never installed
    if ! (
        cd "${staging_root}" || exit 1
        find ./ | LC_COLLATE=C sort | sed '2,$s,^\./,,' | tar --owner=0 --group=0 --numeric-owner --mode='go+rX' --no-recursion -T - -cf - | xz -T0 -1 > "${txz_out}" 2>/dev/null
    ) || ! xz -t "${txz_out}" 2>/dev/null; then
        gaming_build_failed "The ${pkg_name} package could not be created. Nothing was changed."
        return 1
    fi

    # 2C: never install an archive with non-root entries
    if [ -f "${txz_out}" ] && [ -n "$(tar --numeric-owner -tvJf "${txz_out}" 2>/dev/null | awk '$2 != "0/0"' | head -n1)" ]; then
        gaming_build_failed "${pkg_name} package has files not owned by root:root. Not installing."
        return 1
    fi

    # WP-1: a curated package never overwrites a file of an installed gnomes app with another name (the same name is
    # replaced as before: curated wins over its own gnomes build)
    if [ -f "${txz_out}" ] && { [ -n "${GNOMES_PY:-}" ] && [ -f "${GNOMES_PY}" ] || [ "${SLACKY_FOOTPRINT_MODE:-enforce}" != "report" ]; } \
        && ! python3 "${GNOMES_PY:-/nonexistent}" footprint-guard --verify-host-paths "${txz_out}" --mode curated; then
        gaming_build_failed "${pkg_name} was not installed. Nothing was changed."
        return 1
    fi

    if [ -f "${txz_out}" ]; then
        chmod 644 "${txz_out}"
        validate_privileges
        echo -e "  ${CYAN}•${RESET} Installing ${pkg_name} to system..."
        local old_foreign_pkg="" upg_rc=0
        # 6A-129: keep a copy of the admin's config files in case the upgrade removes the old plain file
        local cfg_keep_dir="${staging_base}/cfg-keep"
        mkdir -p "${cfg_keep_dir}"
        for cfg_rel in "${cfg_new_list[@]}"; do
            if [ -f "/${cfg_rel}" ]; then
                cat "/${cfg_rel}" > "${cfg_keep_dir}/${cfg_rel//\//_}" 2>/dev/null \
                    || sudo cat "/${cfg_rel}" > "${cfg_keep_dir}/${cfg_rel//\//_}" 2>/dev/null || true
            fi
        done
        if [ "${pkg_id}" = "antigravity" ]; then
            old_foreign_pkg=$(ls -1d /var/log/packages/antigravity-[0-9]* 2>/dev/null | grep -v 'underpants-' | head -n1 || true)
        fi

        # 6A-240: the boot loader and sbctl rewrite startup files; the safety snapshot is taken BEFORE the package is replaced, and
        # without it the package stays as it is (inside a full update the snapshot already exists)
        if { [ "${pkg_id}" = "limine" ] || [ "${pkg_id}" = "sbctl" ]; } && [ "${DEFER_BOOT_SYNC:-0}" != "1" ] \
            && [ -z "${SLACKY_SNAP_PRE:-}" ] && command -v create_pre_update_snapshot >/dev/null 2>&1 \
            && command -v is_limine_installed >/dev/null 2>&1 && [ "$(is_limine_installed)" = "true" ]; then
            local _pre_snap_rc=0
            create_pre_update_snapshot || _pre_snap_rc=$?
            if [ "${_pre_snap_rc}" -eq 1 ]; then
                gaming_build_failed "A safety snapshot could not be made, so ${pkg_name} was not updated. Nothing was changed."
                return 1
            fi
        fi

        if [ -n "${old_foreign_pkg}" ]; then
            local old_bname
            old_bname=$(basename "${old_foreign_pkg}")
            echo -e "  ${CYAN}•${RESET} Upgrading legacy ${old_bname} directly to ${pkg_name}..."
            sudo "${PKG_UPGRADE_CMD}" --install-new --reinstall "${old_bname}%${txz_out}" || upg_rc=$?
        else
            sudo "${PKG_UPGRADE_CMD}" --install-new --reinstall "${txz_out}" || upg_rc=$?
        fi
        # 6A-4: superseded packages go only after the new one is installed (pkgtools order, no gap)
        # 6A-125: a failed install is a failure (it used to continue and report success)
        if [ "${upg_rc}" -eq 0 ] && [ -e "/var/log/packages/$(basename "${txz_out%.txz}")" ]; then
            cleanup_foreign_gaming_pkgs "${pkg_id}"
            gaming_restore_kept_configs "" "${cfg_keep_dir}" "${cfg_new_list[@]}"
        else
            gaming_build_failed "${pkg_name} was not installed. Older versions were left in place."
            return 1
        fi

        echo -e "  ${CYAN}•${RESET} [1/4] Updating dynamic linker cache (ldconfig)..."
        sudo /sbin/ldconfig 2>/dev/null || true

        echo -e "  ${CYAN}•${RESET} [2/4] Registering desktop application entries & GSettings..."
        if [ -x /usr/bin/update-desktop-database ]; then
            sudo /usr/bin/update-desktop-database /usr/share/applications 2>/dev/null || true
        fi
        if [ -x /usr/bin/glib-compile-schemas ]; then
            sudo /usr/bin/glib-compile-schemas /usr/share/glib-2.0/schemas 2>/dev/null || true
        fi

        echo -e "  ${CYAN}•${RESET} [3/4] Rebuilding GTK/KDE icon theme cache & MIME database..."
        if [ -x /usr/bin/gtk-update-icon-cache ]; then
            sudo /usr/bin/gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
            [ -d /usr/share/icons/breeze ] && sudo /usr/bin/gtk-update-icon-cache -f -t /usr/share/icons/breeze 2>/dev/null || true
            [ -d /usr/share/icons/breeze-dark ] && sudo /usr/bin/gtk-update-icon-cache -f -t /usr/share/icons/breeze-dark 2>/dev/null || true
            for d in /usr/share/icons/MacTahoe* /usr/share/icons/WhiteSur*; do
                [ -d "$d" ] && [ -f "$d/index.theme" ] && sudo /usr/bin/gtk-update-icon-cache -f -q "$d" 2>/dev/null || true
            done
        fi
        if [ -x /usr/bin/update-mime-database ]; then
            sudo /usr/bin/update-mime-database /usr/share/mime 2>/dev/null || true
        fi

        # Conditional hardware device udev trigger
        if [ "${has_udev_rules}" -eq 1 ]; then
            echo -e "  ${CYAN}•${RESET} Reloading hardware device udev rules..."
            if [ -x /sbin/udevadm ]; then
                sudo /sbin/udevadm control --reload-rules 2>/dev/null || true
                sudo /sbin/udevadm trigger 2>/dev/null || true
            fi
        fi

        # 6A-6: the GameMode libelogind compatibility link (usr/lib{,64}/libsystemd.so.0) is created by the package's doinst
        # now, so pkgtools records it and removepkg removes it (was a loose `sudo ln` nobody owned).

        # Start daemons if applicable
        if [ "${pkg_id}" = "lact" ] && [ -x /etc/rc.d/rc.lact ]; then
            # 6A-169: a daemon that already runs (upgrade) is restarted so the new program takes over; never a second copy
            if pgrep -f "/usr/bin/lact daemon" >/dev/null 2>&1; then
                sudo /etc/rc.d/rc.lact restart 2>/dev/null || true
            else
                sudo /etc/rc.d/rc.lact start 2>/dev/null || true
            fi
        elif [ "${pkg_id}" = "ananicy" ] && [ -x /etc/rc.d/rc.ananicy-cpp ]; then
            sudo /etc/rc.d/rc.ananicy-cpp restart 2>/dev/null || true
        elif [ "${pkg_id}" = "scx" ]; then
            # 6A-6: no unowned copy into /etc/dbus-1/system.d; the system bus already reads /usr/share/dbus-1/system.d
            sudo killall -HUP dbus-daemon 2>/dev/null || true
            if [ -x /etc/rc.d/rc.scx ]; then
                sudo /etc/rc.d/rc.scx restart 2>/dev/null || true
            fi
        elif [ "${pkg_id}" = "easyeffects" ]; then
            mkdir -p /etc/skel/.config/easyeffects/db 2>/dev/null || true
            cat << 'EERC_EOF' > /etc/skel/.config/easyeffects/db/easyeffectsrc
[Window]
autostartOnLogin=true
showTrayIcon=true
noWindowAfterStarting=true
EERC_EOF
            if [ -d /etc/easyeffects/output ]; then
                mkdir -p /etc/skel/.config/easyeffects/output /etc/skel/.config/easyeffects/irs 2>/dev/null || true
                cp -n /etc/easyeffects/output/*.json /etc/skel/.config/easyeffects/output/ 2>/dev/null || true
                if [ -d /etc/easyeffects/irs ]; then
                    cp -n /etc/easyeffects/irs/* /etc/skel/.config/easyeffects/irs/ 2>/dev/null || true
                fi
                for jf in /etc/skel/.config/easyeffects/output/*.json; do
                    [ -f "${jf}" ] || continue
                    sed -i "s|<PRESETS_DIRECTORY>|\$HOME/.config/easyeffects|g" "${jf}" 2>/dev/null || true
                done
            fi

            local target_user="${SUDO_USER:-${USER:-}}"
            local target_home=""
            if [ -n "${target_user}" ] && [ "${target_user}" != "root" ]; then
                target_home=$(getent passwd "${target_user}" 2>/dev/null | cut -d: -f6 || echo "/home/${target_user}")
            elif [ -n "${HOME:-}" ] && [ "${HOME}" != "/root" ]; then
                target_home="${HOME}"
            fi

            if [ -n "${target_home}" ] && [ -d "${target_home}" ] && { [ -w "${target_home}" ] || [ "$(id -u)" -eq 0 ]; }; then
                local ee_db="${target_home}/.config/easyeffects/db/easyeffectsrc"
                mkdir -p "$(dirname "${ee_db}")" 2>/dev/null || true
                if [ -f "${ee_db}" ]; then
                    if ! grep -q "showTrayIcon" "${ee_db}"; then
                        sed -i '/\[Window\]/a showTrayIcon=true\nnoWindowAfterStarting=true' "${ee_db}" 2>/dev/null || true
                    fi
                else
                    cat << 'EERC_EOF' > "${ee_db}" 2>/dev/null || true
[Window]
autostartOnLogin=true
showTrayIcon=true
noWindowAfterStarting=true
EERC_EOF
                fi
                if [ -d /etc/easyeffects/output ]; then
                    mkdir -p "${target_home}/.config/easyeffects/output" "${target_home}/.config/easyeffects/irs" 2>/dev/null || true
                    cp -n /etc/easyeffects/output/*.json "${target_home}/.config/easyeffects/output/" 2>/dev/null || true
                    if [ -d /etc/easyeffects/irs ]; then
                        cp -n /etc/easyeffects/irs/* "${target_home}/.config/easyeffects/irs/" 2>/dev/null || true
                    fi
                    for jf in "${target_home}/.config/easyeffects/output"/*.json; do
                        [ -f "${jf}" ] || continue
                        sed -i "s|<PRESETS_DIRECTORY>|${target_home}/.config/easyeffects|g" "${jf}" 2>/dev/null || true
                    done
                fi
                if [ "$(id -u)" -eq 0 ] && [ -n "${target_user}" ] && [ "${target_user}" != "root" ]; then
                    chown -R "${target_user}:users" "${target_home}/.config/easyeffects" 2>/dev/null || true
                fi
            fi
        elif [ "${pkg_id}" = "google-chrome" ] || [ "${pkg_id}" = "microsoft-edge" ] || [ "${pkg_id}" = "brave" ]; then
            probe_gpu_hardware
            local flag_files=()
            case "${pkg_id}" in
                google-chrome)
                    flag_files=("chrome-flags.conf")
                    ;;
                brave)
                    flag_files=("brave-flags.conf")
                    ;;
                microsoft-edge)
                    flag_files=("edge-flags.conf" "microsoft-edge-stable-flags.conf")
                    ;;
            esac

            local flags_content=""
            if [ "${HAS_NVIDIA}" = "true" ]; then
                local gpu_gen="MODERN"
                if command -v detect_nvidia_gpu >/dev/null 2>&1; then
                    gpu_gen=$(detect_nvidia_gpu)
                fi
                if [ "${gpu_gen}" = "MODERN" ]; then
                    log_info "[*] Modern NVIDIA GPU (Turing+) detected: Configuring hardware-accelerated Wayland & VA-API flags for ${pkg_id}..."
                    flags_content="--ozone-platform-hint=auto\n--ozone-platform=wayland\n--enable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL,VaapiOnNvidiaGPUs\n--enable-gpu-rasterization\n--enable-zero-copy\n--ignore-gpu-blocklist\n"
                else
                    log_info "[*] Legacy/Pascal NVIDIA GPU detected: Configuring safe Wayland & GPU rasterization flags for ${pkg_id}..."
                    flags_content="--ozone-platform-hint=auto\n--ozone-platform=wayland\n--enable-gpu-rasterization\n--ignore-gpu-blocklist\n"
                fi
            else
                log_info "[*] AMD/Intel GPU detected: Configuring native Wayland flags for ${pkg_id}..."
                flags_content="--ozone-platform-hint=auto\n--ozone-platform=wayland\n--enable-gpu-rasterization\n--enable-zero-copy\n--ignore-gpu-blocklist\n"
            fi

            mkdir -p /etc/skel/.config 2>/dev/null || true
            # 6A-129 (M7): flags files are created once and never overwritten (the user or admin may have edited them)
            # 6A-179: ONLY /etc/skel/.config. This runs as root, and root never writes into a person's home folder: a link
            # placed there could point the write at a system file. Existing users keep the files they have; new users get
            # the files from /etc/skel. A link in place of a file is skipped, never followed.
            for ff in "${flag_files[@]}"; do
                [ -e "/etc/skel/.config/${ff}" ] && continue
                [ -L "/etc/skel/.config/${ff}" ] && continue
                printf '%b\n' "${flags_content}" > "/etc/skel/.config/${ff}" 2>/dev/null || true
            done
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
            local target_user="${SUDO_USER:-${USER:-}}"
            local target_home=""
            if [ -n "${target_user}" ] && [ "${target_user}" != "root" ]; then
                target_home=$(getent passwd "${target_user}" 2>/dev/null | cut -d: -f6 || echo "/home/${target_user}")
            elif [ -n "${HOME:-}" ] && [ "${HOME}" != "/root" ]; then
                target_home="${HOME}"
            fi

            if [ -n "${target_home}" ] && [ -d "${target_home}" ] && { [ -w "${target_home}" ] || [ "$(id -u)" -eq 0 ]; }; then
                for d_dir in "${target_home}/.config/autostart" "${target_home}/.local/share/applications"; do
                    [ -d "${d_dir}" ] || continue
                    for f in "${d_dir}"/*[oO]pen[rR][gG][bB]*.desktop; do
                        [ -f "${f}" ] || continue
                        sed -i -E 's|Exec=.*[oO]pen[rR][gG][bB].*AppImage|Exec=/usr/bin/openrgb|g; s|Exec=.*OpenRGB-[^ ]*|Exec=/usr/bin/openrgb|g' "${f}" 2>/dev/null || true
                    done
                done
            fi
        elif [ "${pkg_id}" = "goverlay" ] || [ "${pkg_id}" = "mangohud" ] || [ "${pkg_id}" = "hyprland-noctalia" ] || [ "${pkg_id}" = "hyprland-core" ]; then
            log_info "[*] Synchronizing universal multi-path font mesh for MangoHud, GOverlay & Wayland..."
            python3 -c '
import os, glob, shutil

# 1. Mirror /usr/local/share/fonts to /usr/share/fonts for container compatibility (Steam/Proton/Pressure-Vessel)
if os.path.isdir("/usr/local/share/fonts"):
    os.makedirs("/usr/share/fonts", exist_ok=True)
    for root, dirs, files in os.walk("/usr/local/share/fonts"):
        rel = os.path.relpath(root, "/usr/local/share/fonts")
        target_dir = os.path.join("/usr/share/fonts", rel) if rel != "." else "/usr/share/fonts"
        os.makedirs(target_dir, exist_ok=True)
        for f in files:
            src_f = os.path.join(root, f)
            dst_f = os.path.join(target_dir, f)
            try:
                if not os.path.exists(dst_f):
                    try:
                        os.link(src_f, dst_f)
                    except Exception:
                        shutil.copy2(src_f, dst_f)
            except Exception:
                pass

font_roots = ["/usr/share/fonts", "/usr/local/share/fonts"]
subdirs = ["TTF", "OTF", "truetype", "opentype"]

target_homes = []
if os.path.isdir("/etc/skel"):
    target_homes.append("/etc/skel")

sudo_user = os.environ.get("SUDO_USER")
if sudo_user and sudo_user != "root":
    import pwd
    try:
        u_home = pwd.getpwnam(sudo_user).pw_dir
        if os.path.isdir(u_home) and u_home not in target_homes:
            target_homes.append(u_home)
    except Exception:
        pass

env_home = os.environ.get("HOME")
if env_home and os.path.isdir(env_home) and env_home != "/root" and env_home not in target_homes:
    target_homes.append(env_home)

for uhome in target_homes:
    if not os.access(uhome, os.W_OK) and os.geteuid() != 0:
        continue
    target_base = os.path.join(uhome, ".local/share/fonts")
    for s in [""] + subdirs:
        os.makedirs(os.path.join(target_base, s), exist_ok=True)
    
    for r in font_roots:
        if not os.path.isdir(r):
            continue
        for item in os.listdir(r):
            full_p = os.path.join(r, item)
            if not os.path.isdir(full_p):
                continue
            if item in subdirs:
                for sub_item in os.listdir(full_p):
                    sub_full = os.path.join(full_p, sub_item)
                    if not os.path.isdir(sub_full):
                        continue
                    for s in [""] + subdirs:
                        dst = os.path.join(target_base, s, sub_item)
                        try:
                            if os.path.islink(dst) or os.path.exists(dst):
                                os.remove(dst)
                            os.symlink(sub_full, dst)
                        except Exception:
                            pass
            else:
                for s in [""] + subdirs:
                    dst = os.path.join(target_base, s, item)
                    try:
                        if os.path.islink(dst) or os.path.exists(dst):
                            os.remove(dst)
                        os.symlink(full_p, dst)
                    except Exception:
                        pass

    # Universal MangoHud font_file -> font_file_text propagation, local current_font.ttf copy & normalization
    mconf = os.path.join(uhome, ".config/MangoHud/MangoHud.conf")
    mconf_dir = os.path.dirname(mconf)
    if os.path.isfile(mconf):
        try:
            with open(mconf, "r", encoding="utf-8") as f:
                lines = f.readlines()
            has_font_file = False
            font_file_val = ""
            font_size_val = ""
            for l in lines:
                ls = l.strip()
                if ls.startswith("font_file="):
                    has_font_file = True
                    font_file_val = ls.split("=", 1)[1]
                elif ls.startswith("font_size="):
                    font_size_val = ls.split("=", 1)[1]
            if has_font_file and font_file_val:
                cur_font = os.path.join(mconf_dir, "current_font.ttf")
                cur_font_text = os.path.join(mconf_dir, "current_font_text.ttf")
                resolved_font = font_file_val
                if resolved_font.startswith("/usr/local/share/fonts/"):
                    resolved_font = resolved_font.replace("/usr/local/share/fonts/", "/usr/share/fonts/", 1)
                
                # If font_file points to an external file, copy it locally into ~/.config/MangoHud/
                if os.path.isfile(resolved_font) and os.path.abspath(resolved_font) not in [os.path.abspath(cur_font), os.path.abspath(cur_font_text)]:
                    try:
                        if os.path.islink(cur_font) or os.path.exists(cur_font):
                            os.remove(cur_font)
                        shutil.copy2(resolved_font, cur_font)
                    except Exception:
                        pass
                    try:
                        if os.path.islink(cur_font_text) or os.path.exists(cur_font_text):
                            os.remove(cur_font_text)
                        shutil.copy2(resolved_font, cur_font_text)
                    except Exception:
                        pass
                elif not os.path.exists(cur_font):
                    for cand in [resolved_font, "/usr/share/fonts/Apple/SF-Pro-Italic.ttf", "/usr/local/share/fonts/Apple/SF-Pro-Italic.ttf", "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf"]:
                        if os.path.isfile(cand):
                            try:
                                shutil.copy2(cand, cur_font)
                                shutil.copy2(cand, cur_font_text)
                                break
                            except Exception:
                                pass

                new_lines = []
                has_updated_font_file_text = False
                has_updated_font_size_text = False
                has_font_file_text_in_orig = any(x.strip().startswith("font_file_text=") for x in lines)
                has_font_size_text_in_orig = any(x.strip().startswith("font_size_text=") for x in lines)
                for l in lines:
                    ls = l.strip()
                    if ls.startswith("font_file="):
                        new_lines.append(f"font_file={cur_font}\n")
                        if not has_font_file_text_in_orig and not has_updated_font_file_text:
                            new_lines.append(f"font_file_text={cur_font_text}\n")
                            has_updated_font_file_text = True
                    elif ls.startswith("font_file_text="):
                        new_lines.append(f"font_file_text={cur_font_text}\n")
                        has_updated_font_file_text = True
                    elif ls.startswith("font_size="):
                        new_lines.append(l)
                        if font_size_val and not has_font_size_text_in_orig and not has_updated_font_size_text:
                            new_lines.append(f"font_size_text={font_size_val}\n")
                            has_updated_font_size_text = True
                    elif ls.startswith("font_size_text=") and font_size_val:
                        new_lines.append(f"font_size_text={font_size_val}\n")
                        has_updated_font_size_text = True
                    else:
                        new_lines.append(l)
                with open(mconf, "w", encoding="utf-8") as f:
                    f.writelines(new_lines)
        except Exception:
            pass
' 2>/dev/null || true
        elif [ "${pkg_id}" = "limine" ]; then
            if command -v is_limine_installed >/dev/null 2>&1 && [ "$(is_limine_installed)" = "true" ]; then
                if [ "${DEFER_BOOT_SYNC:-0}" = "1" ]; then
                    # 6A-99: inside a full update the boot-chain step enrolls the new Limine once, after kernels and images
                    ss_order_menu
                else
                    log_info "[*] Limine bootloader package updated: syncing EFI payload, configuration & BLAKE2B enrollment..."
                    limine_standalone_boot_sync "boot loader" full || true   # 6A-240
                fi
            fi
        elif [ "${pkg_id}" = "sbctl" ]; then
            if command -v is_limine_installed >/dev/null 2>&1 && [ "$(is_limine_installed)" = "true" ]; then
                if [ "${DEFER_BOOT_SYNC:-0}" = "1" ]; then
                    # 6A-99: the boot-chain step signs a staged Limine EFI with the new sbctl and verifies it
                    ss_order_menu
                else
                    # 6A-101: sign a staged copy and swap it in (was an in-place re-sign of the live boot loader)
                    log_info "[*] sbctl updated: re-signing Limine EFI payload..."
                    limine_standalone_boot_sync "Secure Boot signature" || true   # 6A-240
                fi
            fi
        elif [ "${pkg_id}" = "hyprland-noctalia" ] || [ "${pkg_id}" = "hyprland-core" ]; then
            log_info "[*] Configuring Wayland environment and hardware-adaptive Hyprland session..."
            probe_gpu_hardware
            hypr_gpu_facts
            # 6A-76: on a single NVIDIA GPU the GLX vendor variable is only written while a live check says it is needed
            local hypr_glx_line=true
            if [ "${IS_HYBRID_GPU}" != "true" ] && [ "${HAS_NVIDIA}" = "true" ] && ! hypr_glx_vendor_var_needed; then
                hypr_glx_line=false
            fi

            # 6A-6: no `setcap -r` on Slackware's pipewire/wireplumber any more (alters Slackware-owned files; 6A-26 showed
            # both reach the session bus with their file caps once the session has a bus).

            # 1. Hardware-adaptive GPU environment
            # 6A-64: never (over)written in /etc any more; the generated lines live in a marked block of the user's
            # ~/.config/hypr/hyprland.env (read last by start-hyprland-session), everything outside the block is kept.
            local env_content="# Auto-generated by slacky-update probe_gpu_hardware\n"
            # 6A-82: the GPU that drives the screens decides (was: "two GPU vendors = hybrid", which also hit desktops with
            # the iGPU switched on). A render-only NVIDIA laptop GPU gets NO session-wide NVIDIA variables: they made X11
            # programs on the iGPU screen load NVIDIA's OpenGL and kept the dGPU awake. Programs move to it per program.
            if [ "${HAS_NVIDIA}" = "true" ] && [ "${HYPR_NV_DISPLAY}" != "true" ]; then
                env_content+="# Hybrid laptop: the built-in GPU drives the screen, the NVIDIA card sleeps until a program asks for it.\n"
                env_content+="# Run a game or program on the NVIDIA card with: slacky-prime-run <program>   (Steam: slacky-prime-run %command%)\n"
                env_content+="export ELECTRON_OZONE_PLATFORM_HINT=auto\n"
            elif [ "${HAS_NVIDIA}" = "true" ] && [ "${HYPR_NV_BOUND}" = "true" ]; then
                # Dedicated NVIDIA desktop / single-GPU (6A-128: only with the nvidia driver bound, never nouveau)
                env_content+="export LIBVA_DRIVER_NAME=nvidia\n"
                [ "${hypr_glx_line}" = "true" ] && env_content+="export __GLX_VENDOR_LIBRARY_NAME=nvidia\n"
                env_content+="export NVD_BACKEND=direct\n"
                env_content+="export ELECTRON_OZONE_PLATFORM_HINT=auto\n"
            elif [ "${HAS_NVIDIA}" = "true" ]; then
                env_content+="# The NVIDIA card runs on the open-source nouveau driver, so no NVIDIA variables are set.\n"
                env_content+="export ELECTRON_OZONE_PLATFORM_HINT=auto\n"
            elif [ "${HAS_AMD}" = "true" ] && hypr_display_is_amd; then
                # 6A-128: only when an AMD GPU drives the screens (not an Intel screen with an AMD card beside it)
                env_content+="export LIBVA_DRIVER_NAME=radeonsi\n"
                env_content+="export VDPAU_DRIVER=radeonsi\n"
            fi
            # (Intel: libva picks iHD or, on older chips, i965 by itself; forcing iHD broke video decoding on old Intel)
            # 6A-78: multi-GPU only. PCI slots, not /dev/dri/cardN (card numbers change between boots and by-path names
            # contain colons); start-hyprland-session turns them into AQ_DRM_DEVICES at login and skips missing GPUs.
            if [ -n "${HYPR_DRM_ORDER}" ]; then
                env_content+="SLACKY_DRM_ORDER=\"${HYPR_DRM_ORDER}\"\n"
            fi
            write_user_hypr_env_block "$(printf '%b' "${env_content}")"

            # 6A-6: steps 2 and 3 (sudo-written /usr/bin/start-hyprland and /usr/share/wayland-sessions/hyprland.desktop)
            # removed. The suite package ships start-hyprland-session + hyprland.desktop (6A-25); writing them here would
            # overwrite package-owned files (Arch's start-hyprland binary) behind pkgtools' back.

            # 4. Seed user & skel dotfiles if not present
            local terminal_cand="konsole"
            if command -v konsole >/dev/null 2>&1; then
                terminal_cand="konsole"
            elif command -v xfce4-terminal >/dev/null 2>&1; then
                terminal_cand="xfce4-terminal"
            elif command -v kitty >/dev/null 2>&1; then
                terminal_cand="kitty"
            elif command -v foot >/dev/null 2>&1; then
                terminal_cand="foot"
            elif command -v alacritty >/dev/null 2>&1; then
                terminal_cand="alacritty"
            elif command -v xterm >/dev/null 2>&1; then
                terminal_cand="xterm"
            fi

            local target_dirs=("/etc/skel")
            local target_user="${SUDO_USER:-${USER:-}}"
            local target_home=""
            if [ -n "${target_user}" ] && [ "${target_user}" != "root" ]; then
                target_home=$(getent passwd "${target_user}" 2>/dev/null | cut -d: -f6 || echo "/home/${target_user}")
            elif [ -n "${HOME:-}" ] && [ "${HOME}" != "/root" ]; then
                target_home="${HOME}"
            fi

            if [ -n "${target_home}" ] && [ -d "${target_home}" ] && { [ -w "${target_home}" ] || [ "$(id -u)" -eq 0 ]; }; then
                target_dirs+=("${target_home}")
            fi

            # Auto-detect host keyboard layout (Slackware rc.keymap, vconsole.conf, or LANG)
            local detected_kblayout=""
            if [ -f /etc/rc.d/rc.keymap ]; then
                local raw_kmap
                raw_kmap=$(grep -E '^[[:space:]]*(/usr/bin/)?loadkeys[[:space:]]+' /etc/rc.d/rc.keymap 2>/dev/null | awk '{print $NF}' | sed 's/\.map.*//' || echo "")
                case "${raw_kmap}" in
                    no*)     detected_kblayout="no" ;;
                    de*)     detected_kblayout="de" ;;
                    fr*)     detected_kblayout="fr" ;;
                    es*)     detected_kblayout="es" ;;
                    it*)     detected_kblayout="it" ;;
                    sv*|se*) detected_kblayout="se" ;;
                    da*|dk*) detected_kblayout="da" ;;
                    fi*)     detected_kblayout="fi" ;;
                    uk*)     detected_kblayout="gb" ;;
                    pl*)     detected_kblayout="pl" ;;
                    pt*)     detected_kblayout="pt" ;;
                    us*)     detected_kblayout="us" ;;
                esac
            fi
            if [ -z "${detected_kblayout}" ] && [ -f /etc/vconsole.conf ]; then
                local vckeymap
                vckeymap=$(grep -E '^[[:space:]]*KEYMAP=' /etc/vconsole.conf 2>/dev/null | cut -d'=' -f2 | tr -d '"'\'' ' | sed -E 's/(-latin[0-9]*|-pc|-nordic|-utf8|\.map.*)//g' || echo "")
                [ -n "${vckeymap}" ] && detected_kblayout="${vckeymap}"
            fi
            if [ -z "${detected_kblayout}" ] && [ -n "${LANG:-}" ]; then
                case "${LANG}" in
                    nb_*|nn_*|no_*) detected_kblayout="no" ;;
                    da_*)           detected_kblayout="da" ;;
                    sv_*)           detected_kblayout="se" ;;
                    de_*)           detected_kblayout="de" ;;
                    fr_*)           detected_kblayout="fr" ;;
                    es_*)           detected_kblayout="es" ;;
                    it_*)           detected_kblayout="it" ;;
                    fi_*)           detected_kblayout="fi" ;;
                    pl_*)           detected_kblayout="pl" ;;
                    pt_*)           detected_kblayout="pt" ;;
                esac
            fi

            local final_kblayout="us,no"
            if [ -n "${detected_kblayout}" ]; then
                if [ "${detected_kblayout}" != "us" ]; then
                    final_kblayout="${detected_kblayout},us"
                else
                    final_kblayout="us,no"
                fi
            fi

            for target_dir in "${target_dirs[@]}"; do
                [ -d "${target_dir}" ] || continue
                local hypr_dir="${target_dir}/.config/hypr"
                local noct_dir="${target_dir}/.config/noctalia"
                mkdir -p "${hypr_dir}" "${noct_dir}" 2>/dev/null || sudo mkdir -p "${hypr_dir}" "${noct_dir}" 2>/dev/null || true

                local hypr_conf="${hypr_dir}/hyprland.conf"
                if [ ! -f "${hypr_conf}" ]; then
                    local hypr_body="# --- [ Slacky-Update Curated Hyprland Config ] ---\n"
                    hypr_body+="monitor=,preferred,auto,1\n\n"
                    hypr_body+="# Theming & Environment (KDE Dark Theme & Window Decorations)\n"
                    hypr_body+="env = QT_QPA_PLATFORMTHEME,kde\n"
                    hypr_body+="env = QT_STYLE_OVERRIDE,Breeze\n"
                    hypr_body+="env = GTK_THEME,Breeze-Dark\n"
                    hypr_body+="env = QT_WAYLAND_DISABLE_WINDOWDECORATION,0\n"
                    hypr_body+="env = XDG_CURRENT_DESKTOP,Hyprland\n\n"
                    hypr_body+="\$terminal = ${terminal_cand}\n"
                    hypr_body+="\$fileManager = dolphin || thunar\n"
                    hypr_body+="\$menu = rofi -show drun || fuzzel\n\n"
                    hypr_body+="# Autostart essential Daemons\n"
                    hypr_body+="exec-once = dbus-update-activation-environment --all\n"
                    hypr_body+="exec-once = /usr/lib64/xdg-desktop-portal-hyprland || /usr/libexec/xdg-desktop-portal-hyprland\n"
                    hypr_body+="exec-once = /usr/lib64/hyprpolkitagent/hyprpolkitagent || /usr/libexec/hyprpolkitagent || polkit-gnome-authentication-agent-1\n"
                    hypr_body+="exec-once = pipewire\n"
                    hypr_body+="exec-once = pipewire-pulse\n"
                    hypr_body+="exec-once = wireplumber\n"
                    hypr_body+="exec-once = hypridle\n"
                    hypr_body+="exec-once = hyprpaper\n"
                    if [ "${pkg_id}" = "hyprland-noctalia" ]; then
                        hypr_body+="# Noctalia Mac-like Shell (Top bar, bottom dock, launcher)\n"
                        hypr_body+="exec-once = noctalia\n"
                        hypr_body+="exec-once = QT_QPA_PLATFORM=xcb /usr/bin/slacky-update-tray || /usr/bin/slacky-update-tray\n"
                    fi
                    if command -v easyeffects >/dev/null 2>&1 || [ -x /usr/bin/easyeffects ]; then
                        hypr_body+="# EasyEffects Audio Enhancement Daemon\n"
                        hypr_body+="exec-once = easyeffects --service-mode || easyeffects --gapplication-service\n"
                    fi
                    if command -v openrgb >/dev/null 2>&1 || [ -x /usr/bin/openrgb ]; then
                        hypr_body+="# OpenRGB Lighting Controller\n"
                        hypr_body+="exec-once = openrgb --startminimized\n"
                    fi
                    if command -v syncthing >/dev/null 2>&1 || [ -x /usr/bin/syncthing ]; then
                        hypr_body+="# Syncthing File Synchronization Daemon\n"
                        hypr_body+="exec-once = syncthing --no-browser\n"
                    fi
                    hypr_body+="\n"
                    hypr_body+="# Input & General Settings\n"
                    hypr_body+="input {\n    kb_layout = ${final_kblayout}\n    numlock_by_default = true\n    follow_mouse = 1\n    touchpad {\n        natural_scroll = true\n    }\n}\n\n"
                    hypr_body+="general {\n    gaps_in = 6\n    gaps_out = 12\n    border_size = 2\n    col.active_border = rgba(00b4d8ee) rgba(0e3c61ee) 45deg\n    col.inactive_border = rgba(1c2833aa)\n    layout = dwindle\n}\n\n"
                    hypr_body+="decoration {\n    rounding = 12\n    blur {\n        enabled = true\n        size = 8\n        passes = 3\n        new_optimizations = true\n    }\n}\n\n"
                    hypr_body+="# Real Glass Blur on Noctalia UI\n"
                    hypr_body+="layerrule = blur on, match:namespace noctalia\n"
                    hypr_body+="layerrule = blur on, match:namespace gtk-layer-shell\n\n"
                    hypr_body+="# Snappy, fluid animations (200-250ms)\n"
                    hypr_body+="animations {\n    enabled = yes\n    bezier = snappy, 0.2, 0.8, 0.2, 1.0\n    bezier = linear, 0, 0, 1, 1\n    animation = windows,     1, 2.5, snappy, popin 80%\n    animation = windowsIn,   1, 2.5, snappy, popin 80%\n    animation = windowsOut,  1, 2,   snappy, popin 80%\n    animation = windowsMove, 1, 2.5, snappy\n    animation = fade,        1, 2,   snappy\n    animation = workspaces,  1, 2.5, snappy, slide\n    animation = border,      1, 1.5, linear\n}\n\n"
                    hypr_body+="misc {\n    disable_hyprland_logo = true\n    disable_splash_rendering = true\n    force_default_wallpaper = 0\n    background_color = 0x11111b\n    vrr = 0\n    disable_watchdog_warning = true\n    disable_hyprland_guiutils_check = true\n    disable_xdg_env_checks = true\n}\n\n"
                    hypr_body+="ecosystem {\n    no_update_news = true\n    no_donation_nag = true\n}\n\n"
                    hypr_body+="# Keybindings\n"
                    hypr_body+="bind = SUPER, RETURN, exec, \$terminal\n"
                    hypr_body+="bind = SUPER, U, exec, \$terminal -e /usr/bin/slacky-update\n"
                    if [ "${pkg_id}" = "hyprland-noctalia" ]; then
                        hypr_body+="bind = SUPER, SPACE, exec, noctalia msg panel-toggle launcher || \$menu\n"
                        hypr_body+="bind = SUPER, C, exec, noctalia msg panel-toggle control-center\n"
                        hypr_body+="bind = SUPER, I, exec, noctalia msg settings-toggle\n"
                    else
                        hypr_body+="bind = SUPER, SPACE, exec, \$menu\n"
                    fi
                    hypr_body+="bind = SUPER, Q, killactive,\n"
                    hypr_body+="bind = SUPER, M, exit,\n"
                    hypr_body+="bind = SUPER, E, exec, \$fileManager\n"
                    hypr_body+="bind = SUPER, V, togglefloating,\n"
                    hypr_body+="bind = SUPER, F, fullscreen,\n\n"
                    hypr_body+="# Screenshots & Annotation (Spectacle-like experience)\n"
                    hypr_body+="bind = , PRINT, exec, noctalia msg screenshot-annotate\n"
                    hypr_body+="bind = SUPER SHIFT, S, exec, noctalia msg screenshot-annotate\n\n"
                    hypr_body+="# Color Picker (Eyedropper magnifier with hex clipboard copy)\n"
                    hypr_body+="bind = SUPER SHIFT, C, exec, hyprpicker -a\n"
                    hypr_body+="bind = SUPER, P, exec, hyprpicker -a\n\n"
                    hypr_body+="# Media keys and volume wheel (also functional inside fullscreen games)\n"
                    hypr_body+="bindel = , XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+\n"
                    hypr_body+="bindel = , XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-\n"
                    hypr_body+="bindl  = , XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle\n"
                    hypr_body+="bindl  = , XF86AudioPlay, exec, playerctl play-pause 2>/dev/null || true\n"
                    hypr_body+="bindl  = , XF86AudioNext, exec, playerctl next 2>/dev/null || true\n"
                    hypr_body+="bindl  = , XF86AudioPrev, exec, playerctl previous 2>/dev/null || true\n\n"
                    hypr_body+="# Move and resize windows with mouse and keyboard\n"
                    hypr_body+="bindm = SUPER, mouse:272, movewindow\n"
                    hypr_body+="bindm = SUPER, mouse:273, resizewindow\n"
                    hypr_body+="binde = SUPER CTRL, right, resizeactive, 30 0\n"
                    hypr_body+="binde = SUPER CTRL, left, resizeactive, -30 0\n"
                    hypr_body+="binde = SUPER CTRL, up, resizeactive, 0 -30\n"
                    hypr_body+="# Move window focus / active control (ALT + Arrow keys & Mouse hover)\n"
                    hypr_body+="bind = ALT, left,  movefocus, l\n"
                    hypr_body+="bind = ALT, right, movefocus, r\n"
                    hypr_body+="bind = ALT, up,    movefocus, u\n"
                    hypr_body+="bind = ALT, down,  movefocus, d\n\n"
                    hypr_body+="# Move windows within screen (SUPER + Arrow keys)\n"
                    hypr_body+="bind = SUPER, left,  movewindow, l\n"
                    hypr_body+="bind = SUPER, right, movewindow, r\n"
                    hypr_body+="bind = SUPER, up,    movewindow, u\n"
                    hypr_body+="bind = SUPER, down,  movewindow, d\n\n"
                    hypr_body+="# Move active window across monitors (SUPER + SHIFT + Arrow keys)\n"
                    hypr_body+="bind = SUPER SHIFT, left,  movewindow, mon:l\n"
                    hypr_body+="bind = SUPER SHIFT, right, movewindow, mon:r\n"
                    hypr_body+="bind = SUPER SHIFT, up,    movewindow, mon:u\n"
                    hypr_body+="bind = SUPER SHIFT, down,  movewindow, mon:d\n\n"
                    hypr_body+="# Workspace navigation (SUPER + 1..9)\n"
                    for ws in {1..9}; do
                        hypr_body+="bind = SUPER, ${ws}, workspace, ${ws}\n"
                        hypr_body+="bind = SUPER SHIFT, ${ws}, movetoworkspace, ${ws}\n"
                    done
                    hypr_body+="\n"
                    hypr_body+="# --- [ Universal Game and Launcher Window Rules ] ---\n"
                    hypr_body+="xwayland {\n    force_zero_scaling = true\n}\n\n"
                    hypr_body+="# Game launchers kept in floating mode\n"
                    hypr_body+="windowrule = float on, match:class ^(faugus.*)$\n"
                    hypr_body+="windowrule = float on, match:class ^(battle\\\\.net\\\\.exe)$\n"
                    hypr_body+="windowrule = float on, match:title ^(Battle\\\\.net.*)$\n\n"
                    hypr_body+="# All games (Steam, Proton, Faugus, Wine .exe, Gamescope) automatically get fullscreen and low latency\n"
                    hypr_body+="windowrule = fullscreen on, match:class ^(steam_app_.*)$\n"
                    hypr_body+="windowrule = fullscreen on, match:class ^(gamescope.*)$\n"
                    hypr_body+="windowrule = immediate on, match:class ^(steam_app_.*)$\n\n"
                    # 6A-75: software cursor only for NVIDIA older than the GTX 16xx series; newer cards use Hyprland's default
                    if [ "${HYPR_NV_SW_CURSOR}" = "true" ]; then
                        hypr_body+="# NVIDIA Hardware Cursor Settings\ncursor {\n    no_hardware_cursors = true\n    enable_hyprcursor = false\n}\n"
                    fi
                    echo -e "${hypr_body}" > "${hypr_conf}" 2>/dev/null || echo -e "${hypr_body}" | sudo tee "${hypr_conf}" >/dev/null || true
                fi

                local hypr_lua="${hypr_dir}/hyprland.lua"
                local hypr_lua_example="${hypr_dir}/hyprland.lua.example"
                local hypr_mods="${hypr_dir}/modules"
                mkdir -p "${hypr_mods}" 2>/dev/null || sudo mkdir -p "${hypr_mods}" 2>/dev/null || true

                if [ ! -f "${hypr_lua}" ] || [ ! -f "${hypr_lua_example}" ]; then
                    local hypr_lua_body="-- --- [ Slacky-Update Curated Hyprland Modular Lua Config (0.57+ Ready) ] ---\n\n"
                    hypr_lua_body+="local config_dir = os.getenv(\"HOME\") .. \"/.config/hypr\"\n"
                    hypr_lua_body+="package.path = package.path .. \";\" .. config_dir .. \"/?.lua;\" .. config_dir .. \"/modules/?.lua\"\n\n"
                    hypr_lua_body+="require(\"modules.monitors\")\n"
                    hypr_lua_body+="require(\"modules.env\")\n"
                    hypr_lua_body+="require(\"modules.autostart\")\n"
                    hypr_lua_body+="require(\"modules.general\")\n"
                    hypr_lua_body+="require(\"modules.animations\")\n"
                    hypr_lua_body+="require(\"modules.rules\")\n"
                    hypr_lua_body+="require(\"modules.keybinds\")\n\n"
                    hypr_lua_body+="-- Optional GUI override configuration (HyprMod / Dynamic Settings)\n"
                    hypr_lua_body+="require(\"hyprland-gui\")\n"
                    [ ! -f "${hypr_lua}" ] && echo -e "${hypr_lua_body}" > "${hypr_lua}" 2>/dev/null || true
                    echo -e "${hypr_lua_body}" > "${hypr_lua_example}" 2>/dev/null || echo -e "${hypr_lua_body}" | sudo tee "${hypr_lua_example}" >/dev/null || true

                    local hypr_gui_lua="${hypr_dir}/hyprland-gui.lua"
                    [ ! -f "${hypr_gui_lua}" ] && echo -e "-- --- [ HyprMod Managed Settings ] ---\n" > "${hypr_gui_lua}" 2>/dev/null || true

                    local mod_mon="-- Monitors & Workspaces\nhl.monitor({ output = \"\", mode = \"preferred\", position = \"auto\", scale = 1.0 })\n"
                    [ ! -f "${hypr_mods}/monitors.lua" ] && echo -e "${mod_mon}" > "${hypr_mods}/monitors.lua" 2>/dev/null || true

                    local mod_env="-- Environment Variables\nhl.env(\"QT_QPA_PLATFORM\", \"wayland;xcb\")\nhl.env(\"GDK_BACKEND\", \"wayland,x11,*\")\nhl.env(\"QT_QPA_PLATFORMTHEME\", \"kde\")\nhl.env(\"QT_STYLE_OVERRIDE\", \"Breeze\")\nhl.env(\"GTK_THEME\", \"Breeze-Dark\")\nhl.env(\"QT_WAYLAND_DISABLE_WINDOWDECORATION\", \"0\")\nhl.env(\"XDG_CURRENT_DESKTOP\", \"Hyprland\")\n"
                    if [ "${HAS_NVIDIA}" = "true" ] && [ "${HYPR_NV_DISPLAY}" != "true" ]; then
                        # 6A-82: hybrid laptop, nothing NVIDIA session-wide (slacky-prime-run per program)
                        mod_env+="-- Hybrid laptop: run games on the NVIDIA card with slacky-prime-run (Steam: slacky-prime-run %command%)\nhl.env(\"ELECTRON_OZONE_PLATFORM_HINT\", \"auto\")\n"
                    elif [ "${HAS_NVIDIA}" = "true" ] && [ "${HYPR_NV_BOUND}" = "true" ]; then
                        mod_env+="-- NVIDIA Hardware Acceleration\nhl.env(\"LIBVA_DRIVER_NAME\", \"nvidia\")\n"
                        [ "${hypr_glx_line}" = "true" ] && mod_env+="hl.env(\"__GLX_VENDOR_LIBRARY_NAME\", \"nvidia\")\n"
                        mod_env+="hl.env(\"NVD_BACKEND\", \"direct\")\nhl.env(\"ELECTRON_OZONE_PLATFORM_HINT\", \"auto\")\n"
                    elif [ "${HAS_NVIDIA}" = "true" ]; then
                        # 6A-128: nouveau, no NVIDIA variables
                        mod_env+="-- The NVIDIA card runs on nouveau, so no NVIDIA variables are set\nhl.env(\"ELECTRON_OZONE_PLATFORM_HINT\", \"auto\")\n"
                    elif [ "${HAS_AMD}" = "true" ] && hypr_display_is_amd; then
                        mod_env+="-- AMD Mesa Acceleration\nhl.env(\"LIBVA_DRIVER_NAME\", \"radeonsi\")\nhl.env(\"VDPAU_DRIVER\", \"radeonsi\")\n"
                    elif [ "${HAS_INTEL}" = "true" ]; then
                        mod_env+="-- Intel: libva picks iHD or i965 by itself\n"
                    fi
                    [ ! -f "${hypr_mods}/env.lua" ] && echo -e "${mod_env}" > "${hypr_mods}/env.lua" 2>/dev/null || true

                    local mod_auto="-- Autostart Daemons\nhl.on(\"hyprland.start\", function()\n"
                    mod_auto+="    hl.exec_cmd(\"dbus-update-activation-environment --all\")\n"
                    # 6A-66: the Hyprland portal is started by D-Bus when needed (its activation file is fixed at build)
                    mod_auto+="    hl.exec_cmd(\"/usr/lib64/hyprpolkitagent/hyprpolkitagent || /usr/libexec/hyprpolkitagent || polkit-gnome-authentication-agent-1\")\n"
                    # 6A-66: only when not already running for this user (a second instance fights the first)
                    mod_auto+="    hl.exec_cmd(\"pgrep -u \\\"\$(id -u)\\\" -x pipewire >/dev/null || pipewire\")\n"
                    mod_auto+="    hl.exec_cmd(\"pgrep -u \\\"\$(id -u)\\\" -x pipewire-pulse >/dev/null || pipewire-pulse\")\n"
                    mod_auto+="    hl.exec_cmd(\"pgrep -u \\\"\$(id -u)\\\" -x wireplumber >/dev/null || wireplumber\")\n"
                    mod_auto+="    hl.exec_cmd(\"hypridle\")\n"
                    if [ "${pkg_id}" = "hyprland-noctalia" ]; then
                        mod_auto+="    hl.exec_cmd(\"noctalia\")\n"
                        mod_auto+="    hl.exec_cmd(\"QT_QPA_PLATFORM=xcb /usr/bin/slacky-update-tray\")\n"
                    fi
                    mod_auto+="    hl.exec_cmd(\"canberra-gtk-play -i desktop-login\")\n"
                    mod_auto+="end)\n"
                    [ ! -f "${hypr_mods}/autostart.lua" ] && echo -e "${mod_auto}" > "${hypr_mods}/autostart.lua" 2>/dev/null || true

                    local mod_gen="-- Core Configuration\nhl.config({\n"
                    mod_gen+="    input = {\n        kb_layout = \"${final_kblayout}\",\n        numlock_by_default = true,\n        follow_mouse = 1,\n        touchpad = { natural_scroll = true },\n    },\n"
                    mod_gen+="    general = {\n        gaps_in = 6,\n        gaps_out = 12,\n        border_size = 2,\n        col = {\n            active_border = { colors = {\"rgba(00b4d8ee)\", \"rgba(0e3c61ee)\"}, angle = 45 },\n            inactive_border = \"rgba(1c2833aa)\",\n        },\n        layout = \"dwindle\",\n        allow_tearing = false,\n    },\n"
                    mod_gen+="    decoration = {\n        rounding = 12,\n        active_opacity = 1.0,\n        inactive_opacity = 1.0,\n        blur = { enabled = true, size = 6, passes = 2, new_optimizations = true, xray = false },\n    },\n"
                    mod_gen+="    misc = {\n        disable_hyprland_logo = true,\n        disable_splash_rendering = true,\n        force_default_wallpaper = 0,\n        background_color = 0x11111b,\n        vrr = 0,\n        disable_watchdog_warning = true,\n        disable_hyprland_guiutils_check = true,\n        disable_xdg_env_checks = true,\n    },\n"
                    mod_gen+="    ecosystem = { no_update_news = true, no_donation_nag = true },\n"
                    if [ "${HYPR_NV_SW_CURSOR}" = "true" ]; then
                        mod_gen+="    cursor = { no_hardware_cursors = true, enable_hyprcursor = false },\n"
                    else
                        mod_gen+="    cursor = { enable_hyprcursor = false },\n"
                    fi
                    mod_gen+="    xwayland = { force_zero_scaling = true },\n"
                    mod_gen+="    dwindle = { preserve_split = true },\n"
                    mod_gen+="})\n"
                    [ ! -f "${hypr_mods}/general.lua" ] && echo -e "${mod_gen}" > "${hypr_mods}/general.lua" 2>/dev/null || true

                    local mod_anim="-- Animations & Bezier Curves\n"
                    mod_anim+="hl.curve(\"snappy\", { type = \"bezier\", points = { {0.2, 0.8}, {0.2, 1.0} } })\n"
                    mod_anim+="hl.curve(\"linear\", { type = \"bezier\", points = { {0, 0}, {1, 1} } })\n"
                    mod_anim+="hl.animation({ leaf = \"windows\", enabled = true, speed = 2.5, bezier = \"snappy\", style = \"popin 80%\" })\n"
                    mod_anim+="hl.animation({ leaf = \"windowsIn\", enabled = true, speed = 2.5, bezier = \"snappy\", style = \"popin 80%\" })\n"
                    mod_anim+="hl.animation({ leaf = \"windowsOut\", enabled = true, speed = 2.0, bezier = \"snappy\", style = \"popin 80%\" })\n"
                    mod_anim+="hl.animation({ leaf = \"windowsMove\", enabled = true, speed = 2.5, bezier = \"snappy\" })\n"
                    mod_anim+="hl.animation({ leaf = \"fade\", enabled = true, speed = 2.0, bezier = \"snappy\" })\n"
                    mod_anim+="hl.animation({ leaf = \"workspaces\", enabled = true, speed = 2.5, bezier = \"snappy\", style = \"slide\" })\n"
                    mod_anim+="hl.animation({ leaf = \"border\", enabled = true, speed = 1.5, bezier = \"linear\" })\n"
                    [ ! -f "${hypr_mods}/animations.lua" ] && echo -e "${mod_anim}" > "${hypr_mods}/animations.lua" 2>/dev/null || true

                    local mod_rules="-- Window & Layer Rules\n"
                    mod_rules+="hl.layer_rule({ match = { namespace = \"noctalia\" }, blur = true })\n"
                    mod_rules+="hl.layer_rule({ match = { namespace = \"gtk-layer-shell\" }, blur = true })\n"
                    mod_rules+="hl.window_rule({ name = \"battlenet-floating\", match = { title = \"^(Battle\\\\.net.*)$\" }, float = true })\n"
                    mod_rules+="hl.window_rule({ name = \"faugus-floating\", match = { class = \"^(faugus.*)$\" }, float = true })\n"
                    mod_rules+="hl.window_rule({ name = \"ddcui-floating\", match = { class = \"^(ddcui.*)$\" }, float = true })\n"
                    mod_rules+="hl.window_rule({ name = \"nwg-displays-floating\", match = { class = \"^(nwg-displays.*)$\" }, float = true })\n"
                    mod_rules+="hl.window_rule({ name = \"goverlay-floating\", match = { class = \"^(goverlay.*)$\" }, float = true })\n"
                    mod_rules+="hl.window_rule({ name = \"steam-games-fullscreen\", match = { class = \"^(steam_app_[0-9]+)$\" }, fullscreen = true, immediate = true })\n"
                    mod_rules+="hl.window_rule({ name = \"gamescope-fullscreen\", match = { class = \"^(gamescope.*)$\" }, fullscreen = true })\n"
                    mod_rules+="hl.window_rule({ name = \"wow-gaming-tearing\", match = { class = \"^(.*wow.*|.*worldofwarcraft.*)$\" }, immediate = true })\n"
                    mod_rules+="hl.window_rule({ name = \"wine-games-tearing\", match = { class = \"^(wine|proton)$\" }, immediate = true })\n"
                    [ ! -f "${hypr_mods}/rules.lua" ] && echo -e "${mod_rules}" > "${hypr_mods}/rules.lua" 2>/dev/null || true

                    local mod_keys="-- Keybindings\nlocal terminal = \"${terminal_cand}\"\nlocal fileManager = \"dolphin\"\nlocal mainMod = \"SUPER\"\n\n"
                    mod_keys+="hl.bind(mainMod .. \" + Q\",     hl.dsp.exec_cmd(terminal))\n"
                    mod_keys+="hl.bind(mainMod .. \" + RETURN\", hl.dsp.exec_cmd(terminal))\n"
                    mod_keys+="hl.bind(mainMod .. \" + W\",     hl.dsp.window.close())\n"
                    mod_keys+="hl.bind(mainMod .. \" + SHIFT + K\", hl.dsp.window.close())\n"
                    mod_keys+="hl.bind(mainMod .. \" + U\",     hl.dsp.exec_cmd(terminal .. \" -e /usr/bin/slacky-update\"))\n"
                    mod_keys+="hl.bind(mainMod .. \" + E\",     hl.dsp.exec_cmd(fileManager .. \" || thunar\"))\n"
                    if [ "${pkg_id}" = "hyprland-noctalia" ]; then
                        mod_keys+="hl.bind(mainMod .. \" + SPACE\", hl.dsp.exec_cmd(\"noctalia msg panel-toggle launcher || \" .. terminal))\n"
                        mod_keys+="hl.bind(mainMod .. \" + C\",     hl.dsp.exec_cmd(\"noctalia msg panel-toggle control-center\"))\n"
                        mod_keys+="hl.bind(mainMod .. \" + I\",     hl.dsp.exec_cmd(\"noctalia msg settings-toggle\"))\n"
                    fi
                    mod_keys+="hl.bind(mainMod .. \" + M\",     hl.dsp.exec_cmd(\"command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch exit\"))\n"
                    mod_keys+="hl.bind(mainMod .. \" + V\",     hl.dsp.window.float({ action = \"toggle\" }))\n"
                    mod_keys+="hl.bind(mainMod .. \" + F\",     hl.dsp.window.fullscreen({ action = \"toggle\" }))\n\n"
                    mod_keys+="-- Screenshots & Color Picker\n"
                    mod_keys+="hl.bind(\"Print\",               hl.dsp.exec_cmd(\"noctalia msg screenshot-annotate && canberra-gtk-play -i screen-capture &\"))\n"
                    mod_keys+="hl.bind(mainMod .. \" + SHIFT + S\", hl.dsp.exec_cmd(\"noctalia msg screenshot-annotate && canberra-gtk-play -i screen-capture &\"))\n"
                    mod_keys+="hl.bind(mainMod .. \" + SHIFT + C\", hl.dsp.exec_cmd(\"hyprpicker -a\"))\n"
                    mod_keys+="hl.bind(mainMod .. \" + P\",     hl.dsp.exec_cmd(\"hyprpicker -a\"))\n\n"
                    mod_keys+="-- Media Keys\n"
                    mod_keys+="hl.bind(\"XF86AudioRaiseVolume\", hl.dsp.exec_cmd(\"wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+ && canberra-gtk-play -i audio-volume-change -d 'volume' &\"), { repeating = true })\n"
                    mod_keys+="hl.bind(\"XF86AudioLowerVolume\", hl.dsp.exec_cmd(\"wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- && canberra-gtk-play -i audio-volume-change -d 'volume' &\"),      { repeating = true })\n"
                    mod_keys+="hl.bind(\"XF86AudioMute\",        hl.dsp.exec_cmd(\"wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle && canberra-gtk-play -i audio-volume-change -d 'volume' &\"),     { locked = true })\n"
                    mod_keys+="hl.bind(\"XF86AudioPlay\",        hl.dsp.exec_cmd(\"playerctl play-pause 2>/dev/null || true\"), { locked = true })\n"
                    mod_keys+="hl.bind(\"XF86AudioNext\",        hl.dsp.exec_cmd(\"playerctl next 2>/dev/null || true\"), { locked = true })\n"
                    mod_keys+="hl.bind(\"XF86AudioPrev\",        hl.dsp.exec_cmd(\"playerctl previous 2>/dev/null || true\"), { locked = true })\n\n"
                    mod_keys+="-- Mouse Window Control\n"
                    mod_keys+="hl.bind(mainMod .. \" + mouse:272\", hl.dsp.window.drag(), { mouse = true })\n"
                    mod_keys+="hl.bind(mainMod .. \" + mouse:273\", hl.dsp.window.resize(), { mouse = true })\n\n"
                    mod_keys+="-- Resizing\n"
                    mod_keys+="hl.bind(mainMod .. \" + CTRL + right\", hl.dsp.window.resize({ x = 30, y = 0, relative = true }), { repeating = true })\n"
                    mod_keys+="hl.bind(mainMod .. \" + CTRL + left\",  hl.dsp.window.resize({ x = -30, y = 0, relative = true }), { repeating = true })\n"
                    mod_keys+="hl.bind(mainMod .. \" + CTRL + up\",    hl.dsp.window.resize({ x = 0, y = -30, relative = true }), { repeating = true })\n"
                    mod_keys+="hl.bind(mainMod .. \" + CTRL + down\",  hl.dsp.window.resize({ x = 0, y = 30, relative = true }), { repeating = true })\n\n"
                    mod_keys+="-- Focus & Movement\n"
                    mod_keys+="hl.bind(\"ALT + left\",  hl.dsp.focus({ direction = \"left\" }))\n"
                    mod_keys+="hl.bind(\"ALT + right\", hl.dsp.focus({ direction = \"right\" }))\n"
                    mod_keys+="hl.bind(\"ALT + up\",    hl.dsp.focus({ direction = \"up\" }))\n"
                    mod_keys+="hl.bind(\"ALT + down\",  hl.dsp.focus({ direction = \"down\" }))\n\n"
                    mod_keys+="-- Workspace Navigation\n"
                    mod_keys+="for i = 1, 9 do\n"
                    mod_keys+="    hl.bind(mainMod .. \" + \" .. i, hl.dsp.focus({ workspace = tostring(i) }))\n"
                    mod_keys+="    hl.bind(mainMod .. \" + SHIFT + \" .. i, hl.dsp.window.move({ workspace = tostring(i) }))\n"
                    mod_keys+="end\n"
                    [ ! -f "${hypr_mods}/keybinds.lua" ] && echo -e "${mod_keys}" > "${hypr_mods}/keybinds.lua" 2>/dev/null || true
                fi

                # 6A-79: the screen locks by default (hyprlock after 10 minutes and before sleep); the OLED screen-off after
                # 3 minutes stays. The lock is only set up when hyprlock and a lock-screen config exist, so a missing
                # lock screen can never shut the user out. Existing user files are never touched.
                local hyprlock_conf="${hypr_dir}/hyprlock.conf"
                if [ ! -f "${hyprlock_conf}" ] && [ -f /usr/share/hypr/hyprlock.conf ]; then
                    cp /usr/share/hypr/hyprlock.conf "${hyprlock_conf}" 2>/dev/null || sudo cp /usr/share/hypr/hyprlock.conf "${hyprlock_conf}" 2>/dev/null || true
                fi
                local hypr_can_lock=false
                if command -v hyprlock >/dev/null 2>&1 && [ -f "${hyprlock_conf}" ]; then
                    hypr_can_lock=true
                fi
                local hypridle_conf="${hypr_dir}/hypridle.conf"
                if [ ! -f "${hypridle_conf}" ]; then
                    local idle_body="# --- [ Slacky-Update OLED Protection Hypridle Config ] ---\ngeneral {\n"
                    if [ "${hypr_can_lock}" = "true" ]; then
                        idle_body+="    lock_cmd = pidof hyprlock || hyprlock\n    before_sleep_cmd = loginctl lock-session\n"
                    fi
                    idle_body+="    after_sleep_cmd = hyprctl dispatch 'hl.dsp.dpms({ action = \"on\" })' || hyprctl dispatch dpms on\n    ignore_dbus_inhibit = false\n    ignore_systemd_inhibit = false\n}\n\n"
                    idle_body+="# Turn off OLED & secondary screens completely (DPMS Standby / 0 nits) after 3 minutes (180 sec)\nlistener {\n    timeout = 180\n    on-timeout = hyprctl dispatch 'hl.dsp.dpms({ action = \"off\" })' || hyprctl dispatch dpms off\n    on-resume = hyprctl dispatch 'hl.dsp.dpms({ action = \"on\" })' || hyprctl dispatch dpms on\n}\n"
                    if [ "${hypr_can_lock}" = "true" ]; then
                        idle_body+="\n# Lock the screen after 10 minutes (600 sec). To turn the lock off, delete this block.\nlistener {\n    timeout = 600\n    on-timeout = pidof hyprlock || hyprlock\n}\n"
                    fi
                    echo -e "${idle_body}" > "${hypridle_conf}" 2>/dev/null || echo -e "${idle_body}" | sudo tee "${hypridle_conf}" >/dev/null || true
                fi

                # 6A-80: HDR suggestions from this machine's monitors (user homes only; /etc/skel gets no hardware data)
                if [ "${target_dir}" != "/etc/skel" ]; then
                    write_hypr_hdr_suggestions "${hypr_mods}"
                fi

                if [ "${pkg_id}" = "hyprland-noctalia" ]; then
                    local noct_conf="${noct_dir}/config.toml"
                    if [ ! -f "${noct_conf}" ]; then
                        local term_pinned="${terminal_cand}"
                        if [ "${term_pinned}" = "konsole" ]; then
                            term_pinned="org.kde.konsole"
                        fi
                        local fm_pinned="org.kde.dolphin"
                        if ! command -v dolphin >/dev/null 2>&1; then
                            fm_pinned="thunar"
                        fi
                        local noct_body="[shell.panel]\ntransparency_mode = \"glass\"\n\n"
                        noct_body+="[bar.default]\nenabled = true\nposition = \"top\"\nbackground_opacity = 0.60\n\n"
                        noct_body+="[dock]\nenabled = true\nposition = \"bottom\"\nbackground_opacity = 0.65\nlauncher_position = \"start\"\nlauncher_icon = \"grid-dots\"\nmagnification = true\nmagnification_scale = 1.25\nicon_size = 48\nmargin_edge = 4\nmargin_ends = 8\nradius = 12\npinned = [\"slacky-update\", \"${term_pinned}\", \"${fm_pinned}\", \"firefox\", \"steam\"]\n"
                        echo -e "${noct_body}" > "${noct_conf}" 2>/dev/null || echo -e "${noct_body}" | sudo tee "${noct_conf}" >/dev/null || true
                    fi
                fi

                # Ensure non-root ownership on all configured user dotfiles
                if [ "${target_dir}" != "/etc/skel" ] && [ -n "${target_user}" ] && [ "${target_user}" != "root" ]; then
                    local user_grp
                    user_grp=$(id -gn "${target_user}" 2>/dev/null || echo "users")
                    chown -R "${target_user}:${user_grp}" "${hypr_dir}" "${noct_dir}" 2>/dev/null || sudo chown -R "${target_user}:${user_grp}" "${hypr_dir}" "${noct_dir}" 2>/dev/null || true
                    if [ -d "${target_dir}/.config/easyeffects" ]; then
                        chown -R "${target_user}:${user_grp}" "${target_dir}/.config/easyeffects" 2>/dev/null || sudo chown -R "${target_user}:${user_grp}" "${target_dir}/.config/easyeffects" 2>/dev/null || true
                    fi
                fi
            done
        fi

        echo -e "  ${CYAN}•${RESET} [4/4] Synchronizing system status & background registry..."
        sleep 0.5
        trigger_silent_background_refresh 2>/dev/null || true
        echo -e "${GREEN}${BOLD}${pkg_name} (v${ver}) deployed successfully!${RESET}"
    else
        log_error "Failed to create ${pkg_name} txz package."
        rm -rf "${staging_base}"
        return 1
    fi

    rm -rf "${staging_base}" 2>/dev/null || true
    _gaming_trap_reset
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

    gaming_space_precheck "$(get_user_staging_dir)" || return 1  # 6A-313 (N4): before the batch downloads anything
    local staging_base
    staging_base=$(mktemp -d "$(get_user_staging_dir)/gnome-batch.XXXXXX" 2>/dev/null || mktemp -d /tmp/slacky-gnome-batch.XXXXXX)
    local batch_cache="${staging_base}/downloads"
    mkdir -p "${batch_cache}"
    # 6A-125: Ctrl-C/TERM removes the batch staging and stops; the per-package build restores this trap after itself
    _GAMING_BATCH_STAGING="${staging_base}"
    _gaming_trap_set "rm -rf -- $(printf '%q' "${staging_base}") 2>/dev/null"

    local dl_items=()
    local valid_entries=()
    local failed_pids=()

    while IFS='|' read -r pid ver main_url lib32_url extra_url; do
        [ -n "${pid}" ] || continue
        if [ "${ver}" = "NONE" ] || [ -z "${main_url}" ] || [ "${main_url}" = "NONE" ]; then
            local _why
            _why=$(gaming_pkg_unavailable_reason "${pid}")
            if [ -n "${_why}" ]; then
                log_warn "${pid}: ${_why}"
            else
                log_warn "Skipping unresolved package: ${pid}"
            fi
            failed_pids+=("${pid}")  # 6A-125
            continue
        fi
        valid_entries+=("${pid}|${ver}|${main_url}|${lib32_url}|${extra_url}")

        if [[ "${main_url}" =~ ^https?:// ]]; then
            local mf="${batch_cache}/$(basename "${main_url}")"
            if slacky_signed_repo_url "${main_url}"; then
                dl_items+=("${main_url}|${mf}|${main_url}.sig|${mf}.sig")
            else
                dl_items+=("${main_url}|${mf}")
            fi
        fi

        if [ "${lib32_url}" != "NONE" ] && [ -n "${lib32_url}" ] && [[ "${lib32_url}" =~ ^https?:// ]]; then
            local lf="${batch_cache}/$(basename "${lib32_url}")"
            if slacky_signed_repo_url "${lib32_url}"; then
                dl_items+=("${lib32_url}|${lf}|${lib32_url}.sig|${lf}.sig")
            else
                dl_items+=("${lib32_url}|${lf}")
            fi
        fi

        if [ "${extra_url}" != "NONE" ] && [ -n "${extra_url}" ]; then
            IFS=',' read -ra EXTRA_URLS <<< "${extra_url}"
            for single_extra_url in "${EXTRA_URLS[@]}"; do
                [ -n "${single_extra_url}" ] || continue
                if [[ "${single_extra_url}" =~ ^https?:// ]]; then
                    local ef="${batch_cache}/$(basename "${single_extra_url}")"
                    if slacky_signed_repo_url "${single_extra_url}"; then
                        dl_items+=("${single_extra_url}|${ef}|${single_extra_url}.sig|${ef}.sig")
                    else
                        dl_items+=("${single_extra_url}|${ef}")
                    fi
                fi
            done
        fi
    done <<< "${metadata_raw}"

    local total_pkgs=${#valid_entries[@]}
    if [ "${total_pkgs}" -eq 0 ]; then
        log_warn "No valid packages to install."
        rm -rf "${staging_base}"
        _gaming_trap_reset; _GAMING_BATCH_STAGING=""
        [ ${#failed_pids[@]} -eq 0 ] || return 1
        return 0
    fi

    if [ ${#dl_items[@]} -gt 0 ]; then
        echo ""
        log_info "Starting Unified Parallel Batch Download (${total_pkgs} packages • ${#dl_items[@]} files)..."
        if ! download_parallel_pacman "Underpants Gnomes Batch (${total_pkgs} packages)" "${dl_items[@]}"; then
            log_error "Failed to complete parallel download batch."
            rm -rf "${staging_base}"
            _gaming_trap_reset; _GAMING_BATCH_STAGING=""
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
        echo -e "${CYAN}${BOLD}Transmuting & Deploying: ${pid} (v${ver})${RESET}"
        if transmute_and_deploy_gaming_pkg "${pid}" "${batch_cache}" "${ver}" "${main_url}" "${lib32_url}" "${extra_url}"; then
            success_count=$((success_count + 1))
        else
            failed_pids+=("${pid}")
            log_error "Failed to deploy ${pid}. Continuing with remaining batch..."
        fi
        current_idx=$((current_idx + 1))
    done

    rm -rf "${staging_base}" 2>/dev/null || true
    _gaming_trap_reset
    _GAMING_BATCH_STAGING=""
    echo ""
    # 6A-125: honest result; the caller (full update, --gaming-deploy, Rust) sees a failure
    if [ "${success_count}" -lt "${total_pkgs}" ] || [ ${#failed_pids[@]} -gt 0 ]; then
        log_error "${#failed_pids[@]} of ${#target_pkg_ids[@]} packages failed (${failed_pids[*]:-unknown}); their installed versions were kept."
        return 1
    fi
    log_success "Batch deployment complete! ${success_count}/${total_pkgs} packages successfully installed!"
}

uninstall_cachyos_gaming_pkg() {
    local pkg_id="$1"
    validate_privileges
    local found=0
    for p in /var/log/packages/underpants-${pkg_id}-* /var/log/packages/cachyos-gnome-${pkg_id}-*; do
        [ -f "${p}" ] || continue
        local bname
        bname=$(basename "${p}")
        # 6A-127: exact package name only (name-version-arch-build); "limine" must not match limine-entry-tool,
        # "steam" must not match steam-devices
        case "${bname%-*-*-*}" in
            "underpants-${pkg_id}"|"cachyos-gnome-${pkg_id}") ;;
            *) continue ;;
        esac
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
        elif [ "${pkg_id}" = "spacenav" ] || [ "${pkg_id}" = "spacenavd" ]; then
            if [ -x /etc/rc.d/rc.spacenavd ]; then
                sudo /etc/rc.d/rc.spacenavd stop 2>/dev/null || true
            fi
            pkill -x spacenavd 2>/dev/null || true
        elif [ "${pkg_id}" = "sunshine" ]; then
            pkill -x sunshine 2>/dev/null || true
        fi

        # 6A-289 (M10): rc.local and rc.local_shutdown are not edited from here. removepkg runs the package's douninst.sh,
        # which removes exactly this package's own marked block (su_rc_remove) and leaves every other block alone.
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

# 6A-153: true when the installed package for this curated id was built by gnomes (underpants-<id>-*_gnomes)
gaming_pkg_owned_by_gnomes() {
    local pid="$1" f base
    for f in /var/log/packages/underpants-"${pid}"-*_gnomes; do
        [ -e "${f}" ] || continue
        base="${f##*/}"
        [ "${base%-*-*-*}" = "underpants-${pid}" ] && return 0
    done
    return 1
}

# rec 3 (2026-10-15): the curated build never replaces a program that gnomes installed (underpants-<id> with the _gnomes tag);
# one plain sentence says how to switch. Mirrors the Rust app (PlanFailure::OtherEngine).
gaming_pkg_other_engine_sentence() {
    printf '%s is installed by the other engine, so it was left as it is. To switch, remove that one first.' "$1"
}

sync_all_installed_cachyos_gaming_packages() {
    local outdated_pids=() sync_rc=0
    local fast_results=""

    # 1. Check if status cache already contains detected outdated packages
    fast_results=$(python3 -c "
import os, json
# status-cache split: the NEWEST trusted status.json wins (user cache or /var), not the first one that has a list
best, best_ts = None, -1.0
for p in ['/var/cache/slacky-update/status.json', os.path.expanduser('~/.cache/slacky-update/status.json')]:
    if os.path.exists(p):
        try:
            # 6A-48: root acts on this list; only files owned by root or by this user, never through a symlink
            st = os.lstat(p)
            if os.path.islink(p) or st.st_uid not in (0, os.geteuid()):
                continue
            with open(p, 'r', encoding='utf-8') as f:
                d = json.load(f)
            ts = float(d.get('last_check_ts', st.st_mtime))
            if ts > best_ts:
                best, best_ts = d, ts
        except Exception:
            pass
for line in (best or {}).get('cachyos_gaming_updates_raw', []):
    if line.strip():
        print(line.strip())
" 2>/dev/null || echo "")

    # 2. If status cache did not contain raw updates or was empty, perform fresh audit
    if [ -z "${fast_results}" ]; then
        log_info "Auditing installed Underpants Gnomes Gaming packages for upstream updates..."
        fast_results=$(check_all_installed_gaming_updates_fast 2>/dev/null || echo "")
    fi

    if [ -n "${fast_results}" ]; then
        # 6A-48: only ids of the curated catalog are ever deployed (the list comes from a cache file)
        local known_pids
        known_pids=$(get_gaming_catalog 2>/dev/null | cut -d'|' -f1)
        while IFS='|' read -r pid name cur_ver latest_ver; do
            [[ -z "${pid}" || "${pid}" =~ ^# ]] && continue
            if ! grep -qxF -- "${pid}" <<< "${known_pids}"; then
                log_warn "Skipped an unknown package name in the update list: ${pid}"
                continue
            fi
            # 6A-153: never rebuild an app that gnomes installed (an old status cache may still list it here)
            if gaming_pkg_owned_by_gnomes "${pid}"; then
                log_info "$(gaming_pkg_other_engine_sentence "${name:-${pid}}")"
                continue
            fi
            log_info "Upgrade available for ${name}: v${cur_ver} -> v${latest_ver}"
            outdated_pids+=("${pid}")
        done <<< "${fast_results}"
    fi

    # 6A-296 (F3): a new major version of the boot loader or sbctl is never installed on its own; say so in one sentence
    local _hold_f _hold_pid _hold_name
    for _hold_f in /var/cache/slacky-update/major_hold.txt "${HOME:-/nonexistent}/.cache/slacky-update/major_hold.txt"; do
        [ -f "${_hold_f}" ] || continue
        while IFS='|' read -r _hold_pid _hold_name _; do
            case "${_hold_pid}" in
                limine) log_info "Boot loader: waiting: a new major version of the boot loader needs a manual check." ;;
                sbctl) log_info "Secure Boot tool: waiting: a new major version of the Secure Boot tool needs a manual check." ;;
            esac
        done < "${_hold_f}"
    done

    if [ ${#outdated_pids[@]} -gt 0 ]; then
        log_info "Deploying unified batch upgrade for ${#outdated_pids[@]} packages..."
        deploy_gaming_packages_batch "${outdated_pids[@]}" || sync_rc=$?  # 6A-125: failures reach the caller
    else
        log_info "All installed Underpants Gnomes Gaming packages are up to date."
    fi
    trigger_silent_background_refresh 2>/dev/null || true
    return "${sync_rc}"
}

# --- [ INTERACTIVE TUI GAMING MASTER STATION ] ---
interactive_cachyos_gaming_menu() {
    set_terminal_title "slacky-update: Slacky Curated Software"

    # Category keys and human labels
    local CAT_KEYS=("desktop" "engine" "launcher" "hardware" "streaming" "social" "audio" "creative" "ricing" "tools" "browser" "bootloader")
    local CAT_TITLES=(
        "Wayland Desktops & Shells (Hyprland / Noctalia)"
        "Performance, Gaming HUD & Schedulers"
        "Storefronts & Game Launchers"
        "Hardware Control, Tuning & DKMS Drivers"
        "OBS Studio & Production Plugins"
        "Voice Chat, Streaming & Communications"
        "Studio Audio DSP & Sound Processing"
        "Creative, 3D & Photography Studio"
        "Desktop Aesthetics & Themes"
        "Power Tools & Synchronization"
        "Web Browsers"
        "Secure Boot & UEFI Utilities"
    )

    while true; do
        local tui_py="${APP_DIR:-}/slacky_tui.py"
        [ ! -f "${tui_py}" ] && [ -f "/usr/share/slacky-update/lib/slacky_tui.py" ] && tui_py="/usr/share/slacky-update/lib/slacky_tui.py"
        local use_tui=false
        if [ -f "${tui_py}" ] && command -v python3 >/dev/null 2>&1 && [ -t 0 ]; then
            use_tui=true
        fi

        if [ "${use_tui}" = "false" ]; then
            echo ""
            echo -e " ${BOLD_WHITE}Slacky Curated Software:${RESET} ${DIM_WHITE}Premium verified software tried, tested and optimized${RESET}"
            echo ""
        fi

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
            canon_name = p_name
            for sfx in ("-bin", "-git", "-dkms", "-appimage"):
                if canon_name.endswith(sfx):
                    canon_name = canon_name[:-len(sfx)]
                    break
            if canon_name not in installed or p_ver > installed[canon_name]:
                installed[canon_name] = p_ver

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
    "openghub": ["openghub", "/usr/bin/openghub"],
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
    "dvcp-aac": ["/opt/resolve/IOPlugins/aac_decoder_probe.dvcp.bundle", "/opt/resolve/IOPlugins/aac_fdk_plugin.dvcp.bundle"],
    "syncthing": ["syncthing"],
    "antigravity": ["antigravity", "/usr/bin/antigravity", "/usr/bin/agy", "/opt/antigravity/antigravity", "/opt/Antigravity/antigravity"],
    "claude-desktop": ["claude-desktop", "/usr/bin/claude-desktop", "/usr/bin/claude", "/usr/lib/claude-desktop/claude-desktop", "/opt/claude-desktop/claude-desktop"],
    "claude-code": ["claude-code", "/usr/bin/claude-code", "/opt/claude-code/claude-code", "/opt/claude-code/claude"],
    "gemini-cli": ["gemini-cli", "/usr/bin/gemini-cli", "/usr/bin/gemini", "/opt/gemini-cli/bundle/gemini.js"],
    "google-chrome": ["google-chrome", "google-chrome-stable"],
    "microsoft-edge": ["microsoft-edge", "microsoft-edge-stable"],
    "brave": ["brave", "brave-browser"],
    "zen-browser": ["zen-browser", "zen"],
    "opera": ["opera", "/usr/bin/opera", "/usr/lib64/opera/opera", "/usr/lib/opera/opera"],
    "gnome-disk-utility": ["gnome-disks", "/usr/bin/gnome-disks"],
    "spacenav": ["spacenavd", "spnavcfg", "/usr/bin/spacenavd"],
    "volt-gui": ["volt-gui", "/usr/bin/volt-gui", "/opt/volt-gui/volt-gui", "/opt/volt-gui/volt-gui.py"],
    "bambu-studio": ["bambu-studio", "/usr/bin/bambu-studio", "/opt/bambu-studio/bin/bambu-studio", "/usr/bin/BambuStudio"],
    "blender": ["blender", "/usr/bin/blender", "/opt/blender/blender"],
    "freecad": ["freecad", "FreeCAD", "/usr/bin/freecad", "/usr/bin/FreeCAD", "/usr/lib64/freecad/bin/FreeCAD"],
    "plasticity": ["plasticity", "/usr/bin/plasticity", "/opt/plasticity/plasticity", "/opt/Plasticity/plasticity"],
    "storyboarder": ["storyboarder", "/usr/bin/storyboarder", "/opt/storyboarder/storyboarder", "/opt/Storyboarder/storyboarder"],
    "sbctl": ["sbctl"],
    "mactahoe-icons": ["/usr/share/icons/MacTahoe*", "/usr/share/icons/MacTahoe"],
    "mactahoe-cursors": ["/usr/share/icons/MacTahoe-cursors", "/usr/share/icons/MacTahoe-dark-cursors"],
    "whitesur-icons": ["/usr/share/icons/WhiteSur*", "/usr/share/icons/WhiteSur"],
    "whitesur-cursors": ["/usr/share/icons/WhiteSur-cursors", "/usr/share/icons/WhiteSur-dark-cursors"]
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

            while IFS='|' read -r pkg_id name cat catalog_rest; do
                [[ -z "${pkg_id}" || "${pkg_id}" =~ ^# ]] && continue
                # 6A-250: regex fields may contain "|", so only the tail of the row is checked for the marker
                [[ "${catalog_rest}" == *"|hidden" ]] && continue
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

            if [ "${use_tui}" = "false" ]; then
                # Category Section Header
                echo -e "\n${CYAN}${BOLD}── ${ctitle}${RESET} ${DIM}[${cat_installed}/${cat_total} installed]${RESET} ${CYAN}──${RESET}"
            fi

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
                fi

                if [ "${use_tui}" = "false" ]; then
                    local badge1
                    if [ "${p_ver1}" != "NONE" ]; then
                        local sv1="${p_ver1}"
                        if [ "${sv1}" = "INSTALLED" ]; then
                            sv1="Inst"
                        elif [ ${#sv1} -gt 6 ]; then
                            sv1="${sv1:0:5}…"
                        fi
                        badge1="${GREEN}[v${sv1} OK]${RESET}"
                    else
                        badge1="${RED}[Not Inst]${RESET}"
                    fi

                    local sname1="${p_name1}"
                    if [ ${#sname1} -gt 24 ]; then
                        sname1="${sname1:0:23}…"
                    fi
                    local col1
                    col1=$(printf " ${BOLD}%2d.${RESET} %-24s %b" "${idx1}" "${sname1}" "${badge1}")

                    if [ $((ei + 1)) -lt ${num_entries} ]; then
                        local badge2
                        if [ "${p_ver2}" != "NONE" ]; then
                            local sv2="${p_ver2}"
                            if [ "${sv2}" = "INSTALLED" ]; then
                                sv2="Inst"
                            elif [ ${#sv2} -gt 6 ]; then
                                sv2="${sv2:0:5}…"
                            fi
                            badge2="${GREEN}[v${sv2} OK]${RESET}"
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
                fi
            done
        done

        local user_choice=""
        if [ "${use_tui}" = "true" ]; then
            user_choice=$(python3 "${tui_py}" --mode gnomes)
        else
            echo -e "\n${BOLD}Batch & Automation Actions:${RESET}"
            echo -e "  ${CYAN}${BOLD}O.${RESET}  Install full OBS streaming and creation suite"
            echo -e "  ${CYAN}${BOLD}U.${RESET}  Synchronize & Upgrade All Installed Gaming Packages"
            echo -e "  ${CYAN}${BOLD}D.${RESET}  Uninstall a Component"
            echo ""
            echo -e " ${CYAN}[Up/Down] Navigate   [Enter] Select   [Shift + Drag] Copy Text   [Super + Drag/Click] Move/Resize   [ESC / q] Exit${RESET}"
            echo ""
            read -r -p "Enter your choice here (manual mode) [1-${#item_ids[@]}, O, U, D]: " user_choice
        fi
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
                deploy_gaming_packages_batch "${obs_pids[@]}" || true  # 6A-125: summary already shown; stay in the menu
                echo ""
                read -r -p "Press Enter to continue..."
                ;;
            A)
                echo ""
                log_info "Starting 1-Click Total Gaming Rig Deployment (${#item_ids[@]} packages in unified batch)..."
                validate_privileges
                deploy_gaming_packages_batch "${item_ids[@]}" || true  # 6A-125
                echo ""
                read -r -p "Press Enter to continue..."
                ;;
            U)
                echo ""
                validate_privileges
                sync_all_installed_cachyos_gaming_packages || true  # 6A-125
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
                    local pkg_list_str="${unique_pids[*]}"
                    local confirm_install="y"
                    echo ""
                    read -r -p "Do you want to install ${pkg_list_str} to your system? [Y/n]: " confirm_install || confirm_install="n"
                    confirm_install=$(echo "${confirm_install:-y}" | tr '[:upper:]' '[:lower:]')
                    if [[ ! "${confirm_install}" =~ ^(y|yes|j|ja|s|si)$ ]]; then
                        log_info "Installation cancelled by user."
                        sleep 1
                        continue
                    fi

                    echo ""
                    if [ ${#unique_pids[@]} -eq 1 ]; then
                        log_info "Deploying single package: ${unique_pids[0]}..."
                        transmute_and_deploy_gaming_pkg "${unique_pids[0]}" || log_error "Failed to deploy ${unique_pids[0]}"
                    else
                        log_info "Deploying ${#unique_pids[@]} selected packages in unified batch..."
                        deploy_gaming_packages_batch "${unique_pids[@]}" || true  # 6A-125
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
