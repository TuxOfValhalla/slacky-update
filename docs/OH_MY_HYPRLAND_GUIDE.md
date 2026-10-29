# 🖥️ Oh My Hyprland Guide
### *Curated & DIY Wayland Desktop Environments for Slackware Linux*
#### `v1.0 LTS` — *"Dark Star"* (Official Long-Term Support Release)

---

> [!IMPORTANT]
> **TARGET DISTRIBUTION REQUIREMENT & VERSION MANDATE**  
> **Hyprland suites in Slacky-Update are engineered strictly for Slackware 15+ (`slackware-current` / `Slackware 16 alpha`).**  
> Legacy Slackware 15.0 is unsupported due to older Wayland, Mesa, Seatd, and PipeWire shared libraries.

> [!NOTE]
> **OVERVIEW & DESIGN PHILOSOPHY**  
> Slacky-Update provides a modern, high-performance Wayland compositor experience on Slackware Linux without compromising system stability. Whether you prefer a turnkey, beautifully polished Mac-like desktop environment powered by Noctalia Shell, or an unopinionated DIY compositor to craft your own custom bar and shell, this guide provides complete architectural, configuration, and troubleshooting documentation.

---

## 📑 Table of Contents
1. [Core Philosophy: The Sacred Slackware Base & The Five Pillars](#1-core-philosophy-the-sacred-slackware-base--the-five-pillars)
2. [🧒 ELI5: What is Hyprland and Wayland?](#2-eli5-what-is-hyprland-and-wayland)
3. [The Two Flavors: Curated vs DIY](#3-the-two-flavors-curated-vs-diy)
4. [Non-Intrusive Updates & Fallback Recovery](#4-non-intrusive-updates--fallback-recovery)
5. [Modular Lua Architecture (`hyprland.lua`)](#5-modular-lua-architecture-hyprlandlua)
6. [GUI Configuration with HyprMod & nwg-displays](#6-gui-configuration-with-hyprmod--nwg-displays)
7. [Manual Configuration Guide](#7-manual-configuration-guide)
8. [Troubleshooting Common Hyprland Issues](#8-troubleshooting-common-hyprland-issues)
9. [Complete Keybindings Reference Table](#9-complete-keybindings-reference-table)

---

## 1. Core Philosophy: The Sacred Slackware Base & The Five Pillars

The Hyprland desktop integration within Slacky-Update is strictly anchored in **The Sacred Slackware Base System** and **The Five Engineering Pillars**:
* **The Sacred Slackware Base System:** Official Slackware desktop environments (KDE Plasma, XFCE) and native system libraries remain **100% untouched and functional**. Hyprland packages are deployed cleanly through isolated packages in `/opt/underpants/` and native Slackware `.txz` packages registered in `/var/log/packages/`.
* **⚡ Speed:** Hardware-accelerated direct scanout with `immediate = true` tearing support for gaming; blazing 200ms bezier animations.
* **🛋️ Comfort:** Complete out-of-the-box Mac-like desktop with floating dock, spotlight launcher, volume/brightness overlays, and status notifier tray integration.
* **🛡️ Safety:** Slackware's own PipeWire and WirePlumber files are never altered; non-destructive user configuration model where updates never overwrite `~/.config/hypr/`.
* **🎨 UI Design:** Frosted glass aesthetics, rounded window corners, tasteful icon sets, and smooth fluid animations.
* **🤝 Ease of Use:** 1-Click GUI configuration through HyprMod (`hyprmod`), visual multi-monitor management via `nwg-displays`, and universal `(ESC)` navigation across all menus.

---

## 2. 🧒 ELI5: What is Hyprland and Wayland?

> [!NOTE]
> ### 🧩 ELI5 (Explain Like I'm 5)
> Think of your computer screen like a theater stage. For 30 years, Linux used an old stage director named **X11** who shouted through megaphones, had trouble synchronizing lighting, and sometimes let actors walk through walls (screen tearing).  
> **Wayland** is the modern stage director who coordinates everything smoothly with laser timing so there is zero screen flicker or lag.  
> **Hyprland** is the state-of-the-art stage manager who arranges your windows automatically like neat puzzle pieces, adds elegant animations, and keeps gaming framerates high!

---

## 3. The Two Flavors: Curated vs DIY

Slacky-Update offers two distinct Hyprland deployment choices:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           HYPRLAND FLAVOR COMPARISON                        │
├─────────────────────────────────────────────────────────────────────────────┤
│  Feature / Component        │ hyprland-noctalia (Curated) │ hyprland-core   │
├─────────────────────────────┼─────────────────────────────┼─────────────────┤
│  Target Audience            │ Turnkey Mac-like Desktop    │ DIY Power Users │
│  Desktop Shell              │ Noctalia Shell (Bar + Dock) │ None (Bring OW) │
│  Spotlight Launcher         │ Built-in Noctalia Launcher  │ None (Rofi/Wofi)│
│  Control Center / Systray   │ Integrated Quick Toggles    │ None            │
│  Config Architecture        │ Modular Lua (`modules/*.lua`)│ Same Lua layout │
│  Visual Settings Editor     │ HyprMod (`--hyprmod`, extra)│ HyprMod (extra) │
│  Display Management         │ nwg-displays + ddcui        │ Same            │
│  Hardware Color Modes       │ Auto + HDR suggestions      │ Auto + HDR sugg.│
│  Audio / Screen Sharing     │ PipeWire autostart (once)   │ Same            │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Flavor 1: `hyprland-noctalia` (Curated Mac-like Desktop Suite)
* **Command:** `slacky-update --hyprland-noctalia` (or `slacky-update --hyprland`)
* **What's Included:**
  * **Compositor & Graphics:** `hyprland`, `aquamarine`, `hyprlang`, `hyprcursor`, `hyprgraphics`, `hyprutils`, `hyprwire`, `hyprtoolkit`, `hyprland-guiutils`.
  * **Noctalia Shell Suite:** Modern topbar, floating dock, spotlight application launcher, control center with brightness/volume sliders, and StatusNotifierItem system tray integration.
  * **Desktop Portals & Authentication:** `xdg-desktop-portal-hyprland`, `hyprpolkitagent`, `sdbus-cpp`.
  * **Locking & Power Management:** `hyprlock` (screen locker with PAM integration), `hypridle` (3-minute OLED burn-in standby and DPMS sleep), `hyprpaper` (wallpaper daemon).
  * **Color & Display Utilities:** `hyprpicker` (Wayland eyedropper & magnifier), `ddcui` (DDC/CI hardware monitor control), `nwg-displays` (graphical multi-monitor layout), `wlr-randr`.
  * **Visual Configuration (separate install):** `hyprmod` (native GTK4/Libadwaita visual settings and rules editor) is not part of the suite; install it with `slacky-update --hyprmod`.

### Flavor 2: `hyprland-core` (DIY Minimalist Compositor)
* **Command:** `slacky-update --hyprland-core`
* **What's Included:**
  * Clean, unopinionated Hyprland compositor with core Wayland portals (`xdg-desktop-portal-hyprland`), `hyprlock`, `hypridle`, `hyprpaper`, `hyprpicker`, `hyprpolkitagent` and the display tools (`nwg-displays`, `ddcui`, `wlr-randr`).
  * No shell, no dock (no Noctalia). It gets the same modular Lua starter files, without the Noctalia entries.
  * Ideal for power users who want to build custom environments using Waybar, Eww, Rofi-Wayland, SwayNC, or custom Hyprland configs from scratch.

---

## 4. Non-Intrusive Updates & Fallback Recovery

### Zero Configuration Overwrite Guarantee
When you update Hyprland via Slacky-Update, the engine guarantees that **your personal customizations in `~/.config/hypr/` will NEVER be overwritten or deleted**.

* The curated entry point is also kept as `hyprland.lua.example` (written when it or `hyprland.lua` is missing); every other file is only created when missing, never replaced.
* Your active `~/.config/hypr/modules/*.lua` and custom `hyprland-gui.lua` files remain 100% untouched.

### Curated Hyprland Fallback & Reinstall
If you ever experiment with configuration files, break your Lua scripts, or corrupt your desktop setup, you can restore the factory curated environment at any time without losing personal user data:

```bash
# 1. Move your broken configuration aside (slacky-update preserves existing files by default)
mv ~/.config/hypr ~/.config/hypr.broken.backup

# 2. Re-apply the curated default configuration, hardware probes, and desktop suite
slacky-update --hyprland
```

Because Slacky-Update protects existing user files with `[ ! -f ]` guards, moving the damaged directory aside allows the installer to provision a clean factory modular Lua layout, re-probe host GPU acceleration (NVIDIA vs AMD vs Intel vs PRIME), and recreate all desktop rules.

---

## 5. Modular Lua Architecture (`hyprland.lua`)

### Why Lua Instead of Static `.conf` Files?
Traditional Hyprland setups use a single, monolithic 1,500-line `hyprland.conf` file. Slacky-Update adopts a **modular Lua architecture**:

1. **Procedural Logic & Hardware Branching:** Lua scripts can query host hardware (e.g., detecting if an NVIDIA GPU, OLED display, or laptop battery is present) and dynamically configure settings at startup.
2. **Clean Separation of Concerns:** Keybindings, window rules, monitor layouts, and startup daemons live in dedicated, readable files.
3. **Safe GUI Overrides:** HyprMod settings live in `~/.config/hypr/hyprland-gui.lua` (loaded last by `hyprland.lua`), cleanly overriding defaults without corrupting your hand-crafted scripts.

### Directory Structure & Module Breakdown

```
~/.config/hypr/
├── hyprland.lua            # 🚀 Master Entry Point (loads all modules)
├── hyprland.lua.example    # 📄 Fresh copy of the curated entry point
├── hyprland-gui.lua        # 🎛️ HyprMod managed settings (loaded last)
├── hyprland.conf           # 📜 Classic (non-Lua) curated config, written when missing
├── hyprland.env            # 🌐 Environment variables (slacky-update keeps its lines in a marked block)
├── hypridle.conf           # 💤 Screen-off after 3 min, lock after 10 min
├── hyprlock.conf           # 🔒 Lock screen (copied when Hyprlock ships one)
└── modules/
    ├── env.lua             # 🎮 Hardware GPU detection & renderer flags
    ├── monitors.lua        # 🖥️ Monitor resolutions, refresh rates & scaling
    ├── general.lua         # ✨ Input, gaps, borders, rounded corners, blur, cursor & XWayland
    ├── keybinds.lua        # ⌨️ Keyboard shortcuts & application launchers
    ├── rules.lua           # 🪟 Window rules, floating dialogs & tearing
    ├── autostart.lua       # 🚀 Background daemons (Noctalia, Polkit, PipeWire, tray)
    ├── animations.lua      # 🏎️ 200–250ms smooth bezier animation curves
    └── hdr.lua.suggestions # 🌈 HDR lines for your HDR-capable monitors (copy into monitors.lua)
```

#### Module Descriptions
* **`modules/env.lua`:** Dynamically sets GPU environment variables based on probed hardware:
  * **NVIDIA:** `LIBVA_DRIVER_NAME=nvidia`, `__GLX_VENDOR_LIBRARY_NAME=nvidia` (only when a live check says it is needed), `NVD_BACKEND=direct`, `ELECTRON_OZONE_PLATFORM_HINT=auto`. A card on `nouveau` gets no NVIDIA variables.
  * **AMD:** `LIBVA_DRIVER_NAME=radeonsi`, `VDPAU_DRIVER=radeonsi`.
  * **Intel:** No variable is set; libva picks `iHD` or `i965` by itself.
  * **Hybrid Laptops (PRIME):** No NVIDIA variables session-wide; the built-in GPU drives the screen and a program runs on the NVIDIA card with `slacky-prime-run <program>` (Steam: `slacky-prime-run %command%`).
* **`modules/monitors.lua`:** Configures display outputs (preferred mode, auto position, scale 1.0 by default), refresh rates and positions. HDR / 10-bit lines for your monitors are suggested in `modules/hdr.lua.suggestions`.
* **`modules/rules.lua`:** Manages window behavior (Battle.net, Faugus, ddcui, nwg-displays and GOverlay float; Steam games and Gamescope open fullscreen) and provisions `immediate = true` tearing rules for low-latency gaming (Steam games, Wine/Proton, World of Warcraft).
* **`modules/autostart.lua`:** Spawns `hyprpolkitagent`, PipeWire / `pipewire-pulse` / WirePlumber (only when not already running), `hypridle`, and in the curated suite Noctalia Shell and `slacky-update-tray`.

---

## 6. GUI Configuration with HyprMod & nwg-displays

### HyprMod: GTK4 & Libadwaita Visual Editor
**HyprMod** (`underpants-hyprmod`, installed separately with `sudo slacky-update --hyprmod`) provides a native graphical settings interface for Hyprland:

```bash
# Launch HyprMod from terminal or spotlight launcher
hyprmod
```

#### What You Can Configure in HyprMod:
* **Monitors & Colors:** Set resolution, refresh rate (e.g., 144Hz / 240Hz), display scaling, and optional 10-bit OLED color depth toggle.
* **Animations:** Choose between *Snappy* (150ms), *Smooth* (220ms), and *Cinematic* (300ms) bezier curves with live previews.
* **Borders & Styling:** Adjust corner border radius, active border gradient colors, and drop shadow opacity.
* **Window Rules:** Easily add application rules (e.g., force Discord to open on Workspace 4, or force Steam to float).

> [!TIP]
> HyprMod settings belong in `~/.config/hypr/hyprland-gui.lua`. If you ever want to reset visual settings, empty that file (keep the file itself: `hyprland.lua` loads it) and Hyprland reloads the default module settings.

### nwg-displays: Graphical Multi-Monitor Management
For complex multi-monitor setups (e.g., triple monitors with mixed DPI, vertical side monitors, or TV mirrors):

```bash
# Launch multi-monitor layout tool
nwg-displays
```

Drag and arrange your displays visually, click **Apply**, and your layout will be saved permanently.

---

## 7. Manual Configuration Guide

If you prefer editing files directly in your favorite text editor (`nano`, `vim`, `kate`):

### How to Edit Keybindings
Open `~/.config/hypr/modules/keybinds.lua`:
```lua
-- Add a custom shortcut to launch Spotify
hl.bind(mainMod .. " + S",         hl.dsp.exec_cmd("spotify"))
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.exec_cmd("firefox"))
```

### How to Add a Low-Latency Gaming Rule
Open `~/.config/hypr/modules/rules.lua`:
```lua
-- Enable immediate scanout (tearing) for low input latency
hl.window_rule({ name = "cs2-tearing", match = { class = "^(cs2)$" }, immediate = true })
```

### How to Change Wallpapers
Edit `~/.config/hypr/hyprpaper.conf`:
```ini
preload = /usr/share/wallpapers/my_wallpaper.png
wallpaper = ,/usr/share/wallpapers/my_wallpaper.png
```

---

## 8. Troubleshooting Common Hyprland Issues

### 1. NVIDIA Black Screen or Frozen Cursor on Boot
* **Cause:** NVIDIA DRM modesetting is not enabled in kernel boot arguments, or `GBM_BACKEND` is misconfigured.
* **Fix:**
  1. Open `slacky-update --cmdline` and verify that Toggle `[2]` (**NVIDIA GPU Modeset & VRAM**) is enabled (`[x]`).
  2. Verify that `~/.config/hypr/hyprland.env` (or `~/.config/hypr/modules/env.lua`) contains `LIBVA_DRIVER_NAME=nvidia` (and `__GLX_VENDOR_LIBRARY_NAME=nvidia` when your card needs it). On a hybrid laptop these are deliberately absent.
  3. Ensure `GBM_BACKEND=nvidia-drm` is **purged** (it is deprecated in modern Hyprland).

### 2. PipeWire Audio or Screen Sharing Fails under Wayland
* **Cause:** A second PipeWire or WirePlumber instance fights the first, or the session bus environment was not passed on.
* **Fix:** Slacky-Update no longer removes the file capabilities of Slackware's `pipewire` / `wireplumber` (they reach the session bus with them). The curated `autostart.lua` runs `dbus-update-activation-environment --all` and starts each audio daemon only when it is not already running. Check that each runs once:
  ```bash
  pgrep -a pipewire
  pgrep -a wireplumber
  ```

### 3. Screen Goes to Sleep Too Fast (OLED 3-Minute Standby)
* **Cause:** By default, `hypridle` activates DPMS monitor standby after 3 minutes of inactivity to protect OLED displays from burn-in (and, when Hyprlock is set up, locks the screen after 10 minutes).
* **Fix:** Edit `~/.config/hypr/hypridle.conf` and adjust the `timeout` values (e.g., from `180` to `600` for 10 minutes).

---

## 9. Complete Keybindings Reference Table

The `hyprland-noctalia` curated suite comes pre-configured with intuitive keyboard shortcuts:

### 🚀 Applications & System Launchers

| Keybinding | Action | Description |
|---|---|---|
| `SUPER + Return` | Open Terminal | Launches default terminal (Konsole / Xfce Terminal / Kitty / Foot / Alacritty) |
| `SUPER + Q` | Open Terminal | Same as `SUPER + Return` |
| `SUPER + Space` | Spotlight Launcher | Opens Noctalia search & app launcher |
| `SUPER + C` | Control Center | Opens the Noctalia control center |
| `SUPER + I` | Shell Settings | Opens the Noctalia settings |
| `SUPER + E` | File Manager | Opens Dolphin / Thunar file manager |
| `SUPER + U` | Slacky-Update | Opens Slacky-Update in a terminal |
| `SUPER + P` / `SUPER + Shift + C` | Color Picker | Activates Hyprpicker eyedropper with hex clipboard copy |

### 🪟 Window & Layout Management

| Keybinding | Action | Description |
|---|---|---|
| `SUPER + W` / `SUPER + Shift + K` | Close Window | Closes currently focused window |
| `SUPER + V` | Toggle Floating | Toggles focused window between tiling and floating mode |
| `SUPER + F` | Fullscreen | Toggles true fullscreen mode |
| `SUPER + M` | Exit Hyprland | Ends the session (`hyprshutdown` when installed) |
| `ALT + Arrows` | Focus Window | Moves focus to the adjacent window |
| `SUPER + Ctrl + Arrows` | Resize Window | Resizes the focused window in 30 px steps |
| `SUPER + Left / Right Mouse Drag` | Move / Resize | Drags or resizes a window with the mouse |

### 🧭 Workspaces & Navigation

| Keybinding | Action | Description |
|---|---|---|
| `SUPER + 1 ... 9` | Switch Workspace | Switches directly to workspace 1 through 9 |
| `SUPER + Shift + 1 ... 9` | Move to Workspace | Moves active window to specified workspace |

### 🔊 Multimedia, Volume & Screenshots

| Keybinding | Action | Description |
|---|---|---|
| `XF86AudioRaiseVolume` | Volume Up (+5%) | Increases system audio volume (up to 150%) |
| `XF86AudioLowerVolume` | Volume Down (-5%) | Decreases system audio volume |
| `XF86AudioMute` | Mute Audio | Toggles audio output mute state |
| `XF86AudioPlay / Next / Prev` | Media Control | Play/pause, next and previous track (`playerctl`) |
| `Print` / `SUPER + Shift + S` | Screenshot | Noctalia screenshot with annotation |

---

<div align="center">
<b>Slacky-Update Oh My Hyprland Guide</b><br>
<i>Canonical Source: <a href="https://github.com/TuxOfValhalla/slacky-update">GitHub</a> | Secondary Mirror: <a href="https://codeberg.org/TuxOfValhalla/slacky-update">Codeberg</a></i>
</div>
