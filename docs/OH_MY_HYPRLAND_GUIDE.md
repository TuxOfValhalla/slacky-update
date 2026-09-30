# 🖥️ Oh My Hyprland Guide
### *Curated & DIY Wayland Desktop Environments for Slackware Linux*
#### `v1.0_RC2` — *"Dark Star"* (Stability & Hardware Release Candidate)

---

> [!IMPORTANT]
> **TARGET DISTRIBUTION REQUIREMENT**  
> **Hyprland suites in Slacky-Update are engineered strictly for Slackware 15+ (`slackware-current` / `Slackware 16 alpha`).**  
> Legacy Slackware 15.0 is unsupported due to older Wayland, Mesa, Seatd, and PipeWire shared libraries.

> [!NOTE]
> **OVERVIEW & DESIGN PHILOSOPHY**  
> Slacky-Update provides a modern, high-performance Wayland compositor experience on Slackware Linux without compromising system stability. Whether you prefer a turnkey, beautifully polished Mac-like desktop environment powered by Noctalia Shell, or an unopinionated DIY compositor to craft your own custom bar and shell, this guide provides complete architectural, configuration, and troubleshooting documentation.

---

## 📑 Table of Contents
1. [The Two Flavors: Curated vs DIY](#the-two-flavors-curated-vs-diy)
2. [Non-Intrusive Updates & Fallback Recovery](#non-intrusive-updates--fallback-recovery)
3. [Modular Lua Architecture (`hyprland.lua`)](#modular-lua-architecture-hyprlandlua)
4. [GUI Configuration with HyprMod & nwg-displays](#gui-configuration-with-hyprmod--nwg-displays)
5. [Manual Configuration Guide](#manual-configuration-guide)
6. [Troubleshooting Common Hyprland Issues](#troubleshooting-common-hyprland-issues)
7. [Complete Keybindings Reference Table](#complete-keybindings-reference-table)


---

## 1. The Two Flavors: Curated vs DIY {#the-two-flavors-curated-vs-diy}

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
│  Config Architecture        │ Modular Lua (`modules/*.lua`)│ Stock / Custom  │
│  Visual Settings Editor     │ HyprMod (GTK4/Libadwaita)   │ Manual editing  │
│  Display Management         │ nwg-displays + ddcui        │ wlr-randr / CLI │
│  Hardware Color Modes       │ Auto (8-bit default, optional 10-bit) │ User-configured │
│  Audio / Screen Sharing     │ Automated PipeWire Shield   │ User-configured │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Flavor 1: `hyprland-noctalia` (Curated Mac-like Desktop Suite)
* **Command:** `slacky-update --hyprland-noctalia` (or `slacky-update --hyprland`)
* **What's Included:**
  * **Compositor & Graphics:** `hyprland`, `aquamarine`, `hyprlang`, `hyprcursor`, `hyprgraphics`, `hyprutils`, `hyprwire`, `hyprtoolkit`.
  * **Noctalia Shell Suite:** Modern topbar, floating dock, spotlight application launcher, control center with brightness/volume sliders, and StatusNotifierItem system tray integration.
  * **Desktop Portals & Authentication:** `xdg-desktop-portal-hyprland`, `hyprpolkitagent`, `sdbus-cpp`.
  * **Locking & Power Management:** `hyprlock` (screen locker with PAM integration), `hypridle` (3-minute OLED burn-in standby and DPMS sleep), `hyprpaper` (wallpaper daemon).
  * **Color & Display Utilities:** `hyprpicker` (Wayland eyedropper & magnifier), `ddcui` (DDC/CI hardware monitor control), `nwg-displays` (graphical multi-monitor layout), `wlr-randr`.
  * **Visual Configuration:** `hyprmod` (native GTK4/Libadwaita visual settings and rules editor).

### Flavor 2: `hyprland-core` (DIY Minimalist Compositor)
* **Command:** `slacky-update --hyprland-core`
* **What's Included:**
  * Clean, unopinionated Hyprland compositor with core Wayland portals (`xdg-desktop-portal-hyprland`), `hyprlock`, `hypridle`, and display CLI tools.
  * No shell, no dock, no pre-defined theme.
  * Ideal for power users who want to build custom environments using Waybar, Eww, Rofi-Wayland, SwayNC, or custom Hyprland configs from scratch.

---

## 2. Non-Intrusive Updates & Fallback Recovery {#non-intrusive-updates--fallback-recovery}

### Zero Configuration Overwrite Guarantee
When you update Hyprland via Slacky-Update, the engine guarantees that **your personal customizations in `~/.config/hypr/` will NEVER be overwritten or deleted**.

* If upstream defaults change, new templates are deposited alongside your files as non-invasive `.example` files (e.g., `hyprland.lua.example` or `modules/keybinds.lua.example`).
* Your active `~/.config/hypr/modules/*.lua` and custom `hyprland-gui.lua` files remain 100% untouched.

### Curated Hyprland Fallback & Reinstall
If you ever experiment with configuration files, break your Lua scripts, or corrupt your desktop setup, you can restore the factory curated environment at any time without losing personal user data:

```bash
# 1. Move your broken configuration aside (slacky-update preserves existing files by default)
mv ~/.config/hypr ~/.config/hypr.broken.backup

# 2. Re-apply the curated default configuration, hardware probes, and desktop suite
slacky-update --hyprland
```

Because Slacky-Update protects existing user files with `[ ! -f ]` guards, moving the damaged directory aside allows the installer to provision a clean factory modular Lua layout, re-probe host GPU acceleration (NVIDIA vs AMD vs Intel vs PRIME), reset PipeWire capabilities, and recreate all desktop rules.

---

## 3. Modular Lua Architecture (`hyprland.lua`) {#modular-lua-architecture-hyprlandlua}

### Why Lua Instead of Static `.conf` Files?
Traditional Hyprland setups use a single, monolithic 1,500-line `hyprland.conf` file. Slacky-Update adopts a **modular Lua architecture**:

1. **Procedural Logic & Hardware Branching:** Lua scripts can query host hardware (e.g., detecting if an NVIDIA GPU, OLED display, or laptop battery is present) and dynamically configure settings at startup.
2. **Clean Separation of Concerns:** Keybindings, window rules, monitor layouts, and startup daemons live in dedicated, readable files.
3. **Safe GUI Overrides:** The HyprMod visual settings editor writes directly to `modules/hyprland-gui.lua`, cleanly overriding defaults without corrupting your hand-crafted scripts.

### Directory Structure & Module Breakdown

```
~/.config/hypr/
├── hyprland.lua            # 🚀 Master Entry Point (loads all modules)
├── hyprland.env            # 🌐 Global environment variable overrides
└── modules/
    ├── env.lua             # 🎮 Hardware GPU detection & renderer flags
    ├── monitors.lua        # 🖥️ Monitor resolutions, refresh rates & scaling
    ├── keybinds.lua        # ⌨️ Keyboard shortcuts & application launchers
    ├── rules.lua           # 🪟 Window rules, floating dialogs & tearing
    ├── autostart.lua       # 🚀 Background daemons (Noctalia, Polkit, Systray)
    ├── decorations.lua     # ✨ Window borders, rounded corners & shadows
    ├── animations.lua      # 🏎️ 200–250ms smooth bezier animation curves
    └── hyprland-gui.lua    # 🎛️ Auto-generated overrides from HyprMod GUI
```

#### Module Descriptions
* **`modules/env.lua`:** Dynamically sets GPU environment variables based on probed hardware:
  * **NVIDIA:** `LIBVA_DRIVER_NAME=nvidia`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`, `NVD_BACKEND=direct`, `ELECTRON_OZONE_PLATFORM_HINT=auto`.
  * **AMD:** `LIBVA_DRIVER_NAME=radeonsi`, `VDPAU_DRIVER=radeonsi`.
  * **Intel:** `LIBVA_DRIVER_NAME=iHD`.
  * **Hybrid Laptops (PRIME):** Configures non-intrusive render offload routing without locking the compositor to discrete GPU memory.
* **`modules/monitors.lua`:** Configures display outputs, color depth (auto by default, optional 10-bit for HDR/OLED), refresh rates, and position matrices.
* **`modules/rules.lua`:** Manages window behavior (forcing Steam dialogs to float, Picture-in-Picture pin) and provisions `immediate = true` tearing rules for low-latency gaming under Wine/Proton.
* **`modules/autostart.lua`:** Spawns Noctalia Shell, `hyprpolkitagent`, `hypridle`, `slacky-update-tray`, and `easyeffects`.

---

## 4. GUI Configuration with HyprMod & nwg-displays {#gui-configuration-with-hyprmod--nwg-displays}

### HyprMod: GTK4 & Libadwaita Visual Editor
**HyprMod** (`underpants-hyprmod`) provides a native graphical settings interface for Hyprland:

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
> All changes made in HyprMod are saved atomically to `~/.config/hypr/modules/hyprland-gui.lua`. If you ever want to reset visual settings, simply delete `hyprland-gui.lua` and Hyprland will instantly reload default module settings.

### nwg-displays: Graphical Multi-Monitor Management
For complex multi-monitor setups (e.g., triple monitors with mixed DPI, vertical side monitors, or TV mirrors):

```bash
# Launch multi-monitor layout tool
nwg-displays
```

Drag and arrange your displays visually, click **Apply**, and your layout will be saved permanently.

---

## 5. Manual Configuration Guide {#manual-configuration-guide}

If you prefer editing files directly in your favorite text editor (`nano`, `vim`, `kate`):

### How to Edit Keybindings
Open `~/.config/hypr/modules/keybinds.lua`:
```lua
-- Add a custom shortcut to launch Spotify
bind = {
    {"SUPER", "S", "exec", "spotify"},
    {"SUPER SHIFT", "F", "exec", "firefox"},
}
```

### How to Add a Low-Latency Gaming Rule
Open `~/.config/hypr/modules/rules.lua`:
```lua
-- Enable immediate scanout (tearing) for low input latency
windowrulev2 = {
    {"immediate, class:^(cs2)$"},
    {"immediate, class:^(steam_app_.*)$"},
}
```

### How to Change Wallpapers
Edit `~/.config/hypr/hyprpaper.conf`:
```ini
preload = /usr/share/wallpapers/my_wallpaper.png
wallpaper = ,/usr/share/wallpapers/my_wallpaper.png
```

---

## 6. Troubleshooting Common Hyprland Issues {#troubleshooting-common-hyprland-issues}

### 1. NVIDIA Black Screen or Frozen Cursor on Boot
* **Cause:** NVIDIA DRM modesetting is not enabled in kernel boot arguments, or `GBM_BACKEND` is misconfigured.
* **Fix:**
  1. Open `slacky-update --cmdline` and verify that Toggle `[2]` (**NVIDIA GPU Modeset & VRAM**) is enabled (`[x]`).
  2. Verify that `/etc/hypr/hyprland.env` contains `LIBVA_DRIVER_NAME=nvidia` and `__GLX_VENDOR_LIBRARY_NAME=nvidia`.
  3. Ensure `GBM_BACKEND=nvidia-drm` is **purged** (it is deprecated in modern Hyprland).

### 2. PipeWire Audio or Screen Sharing Fails under Wayland
* **Cause:** Linux file capabilities on `pipewire` binaries cause `AT_SECURE` security restrictions that break session DBus communication.
* **Fix:** Slacky-Update automatically strips these capabilities. Run:
  ```bash
  sudo setcap -r /usr/bin/pipewire 2>/dev/null || true
  sudo setcap -r /usr/bin/wireplumber 2>/dev/null || true
  ```

### 3. Screen Goes to Sleep Too Fast (OLED 3-Minute Standby)
* **Cause:** By default, `hypridle` activates DPMS monitor standby after 3 minutes of inactivity to protect OLED displays from burn-in.
* **Fix:** Edit `~/.config/hypr/hypridle.conf` and adjust the `timeout` values (e.g., from `180` to `600` for 10 minutes).

---

## 7. Complete Keybindings Reference Table {#complete-keybindings-reference-table}


The `hyprland-noctalia` curated suite comes pre-configured with intuitive keyboard shortcuts:

### 🚀 Applications & System Launchers

| Keybinding | Action | Description |
|---|---|---|
| `SUPER + Return` | Open Terminal | Launches default terminal (Konsole / Foot) |
| `SUPER + Space` | Spotlight Launcher | Opens Noctalia search & app launcher |
| `SUPER + E` | File Manager | Opens Dolphin / Thunar file manager |
| `SUPER + B` | Web Browser | Launches default web browser (Firefox / Chrome) |
| `SUPER + P` | Color Picker | Activates Hyprpicker eyedropper with hex clipboard copy |
| `SUPER + L` | Lock Screen | Immediately locks workstation via `hyprlock` |
| `SUPER + Shift + K` | Force Kill Window | Interactively terminates stubborn or frozen windows |

### 🪟 Window & Layout Management

| Keybinding | Action | Description |
|---|---|---|
| `SUPER + Q` | Close Window | Closes currently focused window |
| `SUPER + V` | Toggle Floating | Toggles focused window between tiling and floating mode |
| `SUPER + F` | Fullscreen | Toggles true fullscreen mode |
| `SUPER + M` | Monocle / Maximize | Expands focused window to fill tile workspace |
| `SUPER + Left / Right` | Focus Window | Moves focus to left/right adjacent window |
| `SUPER + Up / Down` | Focus Window | Moves focus to upper/lower window |
| `SUPER + Shift + Arrows` | Move Window | Swaps position of focused window in tile tree |

### 🧭 Workspaces & Navigation

| Keybinding | Action | Description |
|---|---|---|
| `SUPER + 1 ... 9` | Switch Workspace | Switches directly to workspace 1 through 9 |
| `SUPER + Shift + 1 ... 9` | Move to Workspace | Moves active window to specified workspace |
| `SUPER + Tab` | Next Workspace | Cycles forward through active workspaces |
| `SUPER + Shift + Tab` | Previous Workspace | Cycles backward through active workspaces |

### 🔊 Multimedia, Volume & Brightness

| Keybinding | Action | Description |
|---|---|---|
| `XF86AudioRaiseVolume` | Volume Up (+5%) | Increases system audio volume |
| `XF86AudioLowerVolume` | Volume Down (-5%) | Decreases system audio volume |
| `XF86AudioMute` | Mute Audio | Toggles audio output mute state |
| `XF86MonBrightnessUp` | Brightness Up | Increases display backlight brightness |
| `XF86MonBrightnessDown` | Brightness Down | Decreases display backlight brightness |
| `Print` | Screenshot Region | Captures selected screen area to clipboard |
| `Shift + Print` | Full Screenshot | Captures entire multi-monitor desktop |

---

## 📜 Summary
The Slacky-Update Hyprland suite brings desktop ergonomics, tear-free gaming, and aesthetic elegance to Slackware Linux while keeping the underlying operating system clean and sovereign. Enjoy your desktop!
