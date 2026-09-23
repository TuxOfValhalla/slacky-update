# ⚡ Slacky-Update v0.16.0 — "Tubthumping" (LTS Prep & Rock-Solid Milestone)

> *"I get knocked down, but I get up again — You are never gonna keep me down!"* — Chumbawamba (1997)
>
> **Slacky-Update v0.16.0** is the long-term stabilization and polish milestone for **Slackware Linux (-current / 15.0+)**. It introduces a unified, 100% flicker-free Pacman ILoveCandy download engine, bulletproof hardware detection with sysfs fallbacks, hardened DKMS and bootloader integrity guards, and complete 90s cultural flair across 24 languages.

---

## 🌟 Major Highlights of v0.16.0

### 1. 🍒 Unified Flimmerfri Pacman ILoveCandy Engine (`lib/pacman_candy.py`)
* **100% Authentic ILoveCandy Parity:** True `o o o o` pellet spacing (`i % 2 == 0`) with bold Slackware Blue `S`/`s` mouth toggling at a steady ~1.4 toggles/sec (`int(now / 0.35)`).
* **Zero Terminal Flicker & Tear Elimination:** Automatic cursor suppression (`\033[?25l`) during multi-line rendering with robust exit/signal restoration (`\033[?25h`). Single-pass atomic buffer flushes locked at a calm 140 ms refresh rate eliminate screen shearing.
* **Unified Ecosystem Look & Feel:** One canonical engine shared across Slackware base updates, CachyOS kernels, NVIDIA driver stacks, SlackBuilds.org (SBo), Flatpaks, ROCm, and Underpants Gnomes.

### 2. 🛡️ Universal Hardware Probing & Sysfs Fallback
* **Unattended Mode GPU Guarantee:** `probe_gpu_hardware` is now evaluated automatically on initialization, ensuring non-interactive/batch runs (`slacky-update -y`) correctly identify NVIDIA, AMD, and Intel GPUs.
* **Sysfs PCI & DRM Fallback:** Probes `/sys/bus/pci/devices/*/vendor` (`0x10de`, `0x1002`, `0x8086`) and DRM subsystem directly when `lspci` is absent or unprivileged.

### 3. 🔒 Bootloader & Secure Boot BLAKE2B Armor
* **Zero-Fork Hash Engine:** Python `hashlib.blake2b` integration provides sub-millisecond, pure-memory BLAKE2B hashing for kernel and initramfs sealing in `limine.conf`, with automatic fallback to `b2sum`.
* **Isolated DKMS Pipeline:** DKMS execution is strictly restricted to authentic hardware kernel modules, with clean, silenced background compilation.

### 4. 🌐 Resilient Network Timeouts & System Cleanup
* **Fail-Safe Network Lookups:** Configured explicit `--connect-timeout` and max-time parameters across all curl lookups in `mod_sbo.sh`, `mod_nvidia.sh`, and `mod_gaming.sh` to prevent hangs.
* **Expanded Cleanup Routine:** `slacky-update --clean` automatically purges orphaned `.part` files, temporary dracut/initramfs trees, stale locks, and obsolete SBo shell packages.

### 5. 📻 90s Cultural Glød & 24-Language Parity
* **24 Languages Synchronized:** 100% key parity across `locales/*.json` with authentic 90s slang ("Major Bummer", "Excellent", "Cowabunga", "Bodacious", "Tubthumping").

### 6. 🪟 Curated Hyprland Desktop Suite & Noctalia Shell (`hyprland-noctalia` & `hyprland-core`)
* **Mac-like Wayland Elegance:** One-command deployment of Hyprland with Noctalia Shell (top status bar, floating bottom dock, quick launcher, notification center).
* **Hardware-Adaptive Session Wrapper:** Dynamic `/usr/bin/start-hyprland` and `/etc/hypr/hyprland.env` dynamically injecting correct GPU backends (`LIBVA_DRIVER_NAME`, `GBM_BACKEND=nvidia-drm`, `NVD_BACKEND=direct`, `radeonsi`, `iHD`).
* **PipeWire DBus AT_SECURE Protection:** Automatically strips conflicting Linux capabilities (`setcap -r`) from `/usr/bin/wireplumber` and `/usr/bin/pipewire`, completely preventing the kernel from dropping session DBus environment variables (`AT_SECURE=1`).
* **Snappy, Fluid Animations:** Custom 200–250 ms bezier curves (`snappy = 0.2, 0.8, 0.2, 1.0`) replacing sluggish defaults with razor-sharp responsiveness.
* **OLED & Gaming Perfection:** Zero-scaling rules (`force_zero_scaling = true`), low-latency tearing (`immediate on`) for Steam/Proton titles, and OLED burn-in prevention (`vrr = 2`).
* **Automated Systray Daemons:** Built-in autostart and StatusNotifierItem registration for `slacky-update-tray`, `openrgb` (with automatic profile loading), and `easyeffects`.

### 7. 🕹️ Underpants Gnomes Pacman Sidecar CLI (`gnomes`)
* **Full Pacman Command-Line Parity:** Native `gnomes install` / `-S`, `gnomes search` / `-Ss`, `gnomes remove` / `-R`, `gnomes sync` / `-Syu`, `gnomes info` / `-Si`, and `gnomes list` / `-Q`.
* **Sidecar Architecture:** Usable standalone via `/usr/bin/gnomes` or through `slacky-update --gnomes-pacman`.
* **Integrated Candy Progress:** Fully connected to `pacman_candy.py` for continuous, authentic visual feedback.

### 8. 🌐 Automatic NVIDIA & Wayland Hardware Acceleration for Browsers
* **Intelligent GPU Interception:** When installing `google-chrome`, `brave`, or `microsoft-edge` via Underpants Gnomes, hardware detection automatically checks for NVIDIA cards.
* **Turnkey Flags Generation:** Automatically deploys hardware-accelerated Wayland and VA-API flags (`--ozone-platform=wayland`, `VaapiOnNvidiaGPUs`, `--enable-gpu-rasterization`, `--enable-zero-copy`) to user configs and `/etc/skel/.config/`.

---

## 📦 Package Summary
* **Release Target:** Slackware 15.0 & Slackware -current
* **Toolchain Compatibility:** GCC 11–15, LLVM/Clang 15–21, Python 3.9–3.14
* **Build System:** `slackbuild/slacky-update.SlackBuild` (Version 0.16.0, Build 6_slacky)

---

## 🧙 90s Hall of Fame
> *"Be excellent to each other. Party on, dudes!"* — Bill & Ted (1989/1991)  
> *"Cowabunga!"* — Teenage Mutant Ninja Turtles  
> *"I get knocked down, but I get up again!"* — Chumbawamba (1997)  
> *"Schwing! Game on!"* — Wayne's World (1992)


