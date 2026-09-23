<div align="center">

# ⚡ Slacky-Update
### *Enterprise-Grade System Maintenance, Kernel Lifecycle, Driver Orchestrator & Workstation Suite for Slackware Linux*
#### `v0.15.0` — *"Now This Is Podracing!"* (Release Edition)

[![Slackware -current](https://img.shields.io/badge/Slackware--current-15.0%2B-blue?style=for-the-badge&logo=slackware&logoColor=white)](http://www.slackware.com/)
[![Release](https://img.shields.io/badge/Release-v0.15.0-purple?style=for-the-badge)](https://github.com/TuxOfValhalla/slacky-update/releases)
[![Canonical: GitHub](https://img.shields.io/badge/Canonical-GitHub-black?style=for-the-badge&logo=github&logoColor=white)](https://github.com/TuxOfValhalla/slacky-update)
[![Mirror: Codeberg](https://img.shields.io/badge/Mirror-Codeberg-2185d0?style=for-the-badge&logo=codeberg&logoColor=white)](https://codeberg.org/TuxOfValhalla/slacky-update)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-green.svg?style=for-the-badge)](LICENSE)
[![Zero-Binary](https://img.shields.io/badge/Architecture-100%25%20Pure%20Source-brightgreen?style=for-the-badge)](lib/)
[![Locales](https://img.shields.io/badge/Locales-24%20Languages-yellow?style=for-the-badge)](locales/)
[![Documentation: Field Guide](https://img.shields.io/badge/Manual-Field%20Guide-teal?style=for-the-badge)](docs/SLACKY_UPDATE_FIELD_GUIDE.md)
[![Documentation: Underpants Gnomes](https://img.shields.io/badge/Manual-Underpants%20Gnomes-purple?style=for-the-badge)](docs/UNDERPANTS_GNOMES_FIELD_GUIDE.md)
[![Documentation: Architecture](https://img.shields.io/badge/Architecture-Technical%20Companion%20Guide-blueviolet?style=for-the-badge)](docs/TECHNICAL_COMPANION_GUIDE.md)

---

**Slacky-Update** is an all-in-one system maintenance station, background monitor, driver orchestrator, and gaming/workstation modernization suite engineered specifically for **Slackware Linux (-current / 15.0+)**. 

*Canonical source: [GitHub](https://github.com/TuxOfValhalla/slacky-update) | Secondary mirror: [Codeberg](https://codeberg.org/TuxOfValhalla/slacky-update) | Master Manual: [docs/SLACKY_UPDATE_FIELD_GUIDE.md](docs/SLACKY_UPDATE_FIELD_GUIDE.md) | Gnomes Guide: [docs/UNDERPANTS_GNOMES_FIELD_GUIDE.md](docs/UNDERPANTS_GNOMES_FIELD_GUIDE.md) | Technical Architecture: [docs/TECHNICAL_COMPANION_GUIDE.md](docs/TECHNICAL_COMPANION_GUIDE.md) | Disaster Recovery: [docs/TROUBLESHOOTING_GUIDE.md](docs/TROUBLESHOOTING_GUIDE.md)*

> [!CAUTION]
> **SYSTEM MODIFICATION & RECOVERY DISCLAIMER — USE AT YOUR OWN RISK**  
> Slacky-Update v0.15.0 is a comprehensive system orchestrator and workstation modernization suite. The software performs low-level system modifications to core components, including Linux kernel deployments, proprietary NVIDIA drivers, Dracut initramfs generation, Btrfs subvolumes, and bootloader topologies (Limine/GRUB).  
> **All usage and modifications are strictly at your own risk.** The authors and contributors assume no liability or warranty for system anomalies, unbootable states, or data loss.  
> **Pre-requisites:** Always ensure you maintain current, tested backups (`/home`, essential configuration files, and boot partitions) and keep a bootable Slackware Live-USB accessible before executing upgrades or altering bootloader topologies.

</div>

---

## 📸 Screenshots

| 🖥️ Interactive Terminal Command Center | 🔔 System Tray Monitor & Applet |
| :---: | :---: |
| ![Slacky-Update CLI Interface](assets/screenshots/04_interactive-CLI-interface.png) | ![Tray Icon](assets/screenshots/01_systray-applet-icon.png) |

---

## 🏛️ System Architecture

Slacky-Update is designed around a non-destructive, modular layered architecture that strictly adheres to Slackware's native packaging and system initialization standards:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SLACKY-UPDATE ARCHITECTURE                        │
├─────────────────────────────────────────────────────────────────────────────┤
│  [User Layer]      CLI Interface (Bash)  │  System Tray Applet (PyQt5)      │
├─────────────────────────────────────────────────────────────────────────────┤
│  [Graphics/Audio]  NVIDIA 615+ Suite     │  AMD ROCm / HIP  │  Yabridge     │
├─────────────────────────────────────────────────────────────────────────────┤
│  [Kernel Layer]    CachyOS BORE / LTS    │  Sched-EXT (SCX) │  Slackware    │
├─────────────────────────────────────────────────────────────────────────────┤
│  [Init/Storage]    Dracut (lib64 Shield) │  Btrfs Snapper Snapshots         │
├─────────────────────────────────────────────────────────────────────────────┤
│  [Boot Layer]      Limine (Two-Zone + sbctl)  │  GRUB / ELILO Coexistence   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 🚀 Key Features & Capabilities

```
=============================================================================
                      ⚡ SLACKY-UPDATE CONTROL CENTER ⚡
=============================================================================
 [1] Total System Synchronization --> Slackware + Flatpaks + SBo + Kernels
 [2] CachyOS Kernel Time Machine  --> 9 Kernel Schedulers, Deploy & Purge
 [3] NVIDIA & ROCm Graphics Hub   --> CachyOS Master, DKMS, OpenCL / HIP
 [4] Underpants Gnomes Suite      --> 51 Native Workstation Apps, Plugins & Drivers
 [5] System Cleanup & Retention   --> Dual Kernel Retention & Artifact Purge
 [6] Limine & Secure Boot Armor   --> Two-Zone Config, CMDLINE Hub, sbctl Signing
 [7] System Performance Tweaks    --> NVIDIA 615+ VRAM Booster, TCP BBR, NTSYNC
 [8] Master Field Guide & Manual  --> Open Documentation & Mobile Export
 [9] Multi-Lingual Engine (i18n)  --> 24 Locales with 100% Key Parity (213 keys)
=============================================================================
```

### 1. 🛡️ Total System Synchronization
* **10-Worker Parallel Pre-fetch Engine**: Accelerates downloads using 10 concurrent worker streams (`SLACKY_PREFETCH_JOBS=10`). Downloads `.txz` packages and `.asc` GPG signatures into a warm cache with resume support (`-C -`), cutting download phases by 5–10×.
* **Slackware Core Integration**: Seamless integration with native `slackpkg` (`update`, `install-new`, `upgrade-all`).
* **Multi-Pass Resume Engine**: If foundational packages (`slackpkg`, `pkgtools`, `glibc-solibs`, `ca-certificates`) upgrade mid-transaction, Slacky-Update detects the toolchain replacement and resumes cleanly without split-brain errors.
* **Smart `.new` Configuration Reconciliation**: Scans `/etc/` post-upgrade and categorizes `.new` files into 4 distinct groups (New Configurations, Identical Duplicates, Unmodified Defaults, Custom User Configurations) with batch resolution prompts.
* **Smart Reboot Evaluator**: Inspects updated package manifests to detect if the active running kernel, glibc, or NVIDIA driver was updated, prompting for a reboot only when strictly necessary.

### 2. 🥾 Limine Bootloader & UEFI Secure Boot
* **Two-Zone `limine.conf` Architecture**: Automatically preserves user theme and visual settings in Zone A while recalculating and atomically generating kernel entries in Zone B.
* **Kernel CMDLINE & Gaming Hub**: Interactive toggle editor for kernel boot arguments (NVIDIA modesetting, AMD LACT overclocking `amdgpu.ppfeaturemask=0xffffffff`, USB autosuspend, watchdog, IOMMU/VFIO passthrough, and hypervisor UMIP workarounds).
* **Cryptographic Safe Hashing**: Automatically calculates and enrolls BLAKE2B cryptographic hashes directly into boot entries for tamper resistance.
* **Seamless Windows 11 Dual-Booting**: Keep UEFI Secure Boot permanently **ENABLED** in motherboard BIOS. Slacky-Update automates `sbctl` key management, signing kernels, initramfs images, and out-of-tree modules.
* **Btrfs Snapper Snapshot Rollbacks**: Automatically creates boot entries for the 5 newest read-only Btrfs snapshots, reusing base kernel hashes with 0 extra disk overhead.
* **Coexistence Mode**: Safely maintains dual bootloader configurations (Limine and GRUB/ELILO) with background self-healing hooks.

### 3. 🏎️ CachyOS, Arch Linux & Zen High-Performance Kernels
* **CPU Microarchitecture Auto-Detection**: Inspects host CPU features and targets optimized builds (*x86_64_v4 / znver4 for Zen 4/5 & Intel 12th–15th+ Gen Core; x86_64_v3; x86_64_v2*).
* **Advanced Schedulers**: Deploys upstream CachyOS kernels across 9 specialized flavors: `standard` (`linux-cachyos`), `bore` (Burst-Oriented Response Enhancer), `lto` (`bore-lto` Clang LTO optimized), `eevdf` (Earliest Eligible Virtual Deadline First), `bmq` (Project C BitMap Queue), `deckify` (Steam Deck & handheld gaming profile), `rt-bore` (PREEMPT_RT Real-Time low-latency), `rc` (Release Candidate), and `lts` (Long-Term Support fallback).
* **Arch Linux Official Vanilla & Zen Kernels**: Full automated support for Arch Linux's upstream stable vanilla kernel (`linux`) and low-latency tuned desktop kernel (`linux-zen`).
* **Smart Realtek 2.5GbE (`r8125`) Hardware Integration**: Automatically detects RTL8125 / Killer E3100X PCI NICs (`10ec:8125` / `10ec:3000`) and seamlessly deploys matching precompiled CachyOS `r8125` kernel module packages directly from official mirrors with zero friction.
* **Universal Multi-Kernel DKMS Engine**: Builds out-of-tree hardware drivers (`zenpower3`, `v4l2loopback`, Wi-Fi/Ethernet) across all installed kernels with strict NVIDIA DKMS safety shielding.
* **Granular Retention Safeguards**: Automatically retains the 2 newest standard/BORE kernels and 1 newest RC kernel, while strictly protecting the active running kernel and preserving stock fallback kernels.

### 4. 🎮 NVIDIA & ROCm Graphics Hub
* **CachyOS Master Precompiled Modules**: Deploys official prebuilt open modules for CachyOS kernels on Turing and newer GPUs with zero compilation overhead.
* **Stale Module Purge & Depmod Shield**: Scans and purges conflicting or stale `nvidia*.ko*` module copies across all installed kernels, permanently eliminating boot-time TTY fallbacks caused by version mismatches.
* **Hybrid & Laptop Support**: Detects mobile chassis types and forces Intel/AMD in-tree KMS drivers to load before NVIDIA in Dracut, ensuring flawless PRIME render offloading.
* **AMD ROCm / HIP Creator Toolkit**: Full compute runtime deployment for DaVinci Resolve Studio with automatic Mesa OpenCL and Rusticl conflict resolution.

### 5. ⚡ NVIDIA 615+ VRAM Booster & Memory Architecture
* **Video Memory Allocation Retention**: Deploys `NVreg_PreserveVideoMemoryAllocations=1` and `NVreg_TemporaryFilePath=/var/tmp` to eliminate VRAM fragmentation, power-state data drops, and Out-of-Memory crashes under Direct3D 12 (VKD3D-Proton).
* **Direct DRM Modesetting**: Configures `nvidia_drm.modeset=1` and `nvidia_drm.fbdev=1` for tear-free, low-latency Wayland and X11 composition.
* **Virtual Memory Tuning**: Configures `vm.max_map_count=2147483642`, Transparent HugePages to `madvise`, `vm.swappiness=10`, and `vm.vfs_cache_pressure=50`.
* **KDE Plasma Dynamic VRAM Leak Guard & Memory Compaction**: Dedicated protection against KWin Wayland compositor and GPU memory leakage via Underpants Gnomes:
  * **`underpants-kwin-dynamic-vram-fix`** (KWin Wayland Dynamic VRAM Leak Guard & Buffer Manager): Actively monitors and manages unevicted compositor video memory buffers on KDE Plasma Wayland sessions, preventing runaway VRAM leakage and releasing stale surface allocations.
  * **`underpants-vram-booster`** (Dynamic VRAM Booster & Memory Compaction Daemon): Actively monitors GPU utilization and system buffer caches, triggering proactive memory defragmentation before Out-of-Memory (OOM) limits are reached—dramatically stabilizing 1% low FPS, eliminating micro-stutters, and boosting Direct3D 12 (VKD3D-Proton) / heavy creative workstation performance.

### 6. 🩲 Underpants Gnomes Universal Pacman Sidecar & Transmutation Factory *(Experimental)*
* **Universal Pacman Engine (`gnomes -S <pkg>` / `slacky-update -P`)**: Transmutes over 31,800+ upstream Arch Linux, CachyOS (`znver4`, `v4`, `v3`, standard), and Multilib packages into 100% native Slackware `.txz` packages without polluting host `glibc`, `init`, `pam`, or system libraries.
* **Underpants Gnomes Field Guide**: Detailed user guide and command manual available in [docs/UNDERPANTS_GNOMES_FIELD_GUIDE.md](docs/UNDERPANTS_GNOMES_FIELD_GUIDE.md).
* **10-Worker Parallel Downloader**: Turbo parallel download stream with the iconic animated Gnome Chomping Underpants progress ticker (`[━━━🧙 🩲·🩲·]`) concluding with `🧙 💰 PROFIT!`.
* **Host Sovereignty Shield & Dynamic DAG Solver**: Scans `/etc/ld.so.cache` (8,000+ native sonames) and satisfies virtual provides (`vulkan-driver`, `pipewire`, `wayland`, `sh`, `desktop-file-utils`) directly from host Slackware while strictly protecting core base packages (`glibc`, `pam`, `shadow`, `sysvinit`, `udev`).
* **ELF RUNPATH Relocation & Universal Wrappers**: Automatically rewrites ELF dynamic header `RUNPATH` to `$ORIGIN/../lib:$ORIGIN/lib:/opt/underpants/common/lib` via `patchelf`, eliminating missing library symbol errors, with dynamic support for Electron and Python variable wrappers.
* **Automatic Runtime Scriptlets**: Relocates Glycin loader `.conf` files, generates GTK3/Pixbuf 64-bit caches, compiles GSettings schemas, and updates MIME/icon caches.
* **Valve Steam & Storefront Fleet**: Native Valve Steam client (`underpants-steam`) with bundled controller udev rules (`60-steam-input.rules`), automatic multilib 32-bit validation, Heroic Games Launcher, Lutris, Faugus Launcher, and ProtonPlus.
* **OBS Creator & Streamer Power-Pack**: 9 vetted streaming components (`obs-studio`, `obs-vkcapture`, `obs-move-transition`, `obs-source-record`, `obs-pipewire-audio-capture`, `obs-advanced-scene-switcher`, `obs-multi-rtmp`, `obs-composite-blur`, `obs-teleport`).
* **Curated Hyprland Desktop Suite (`slacky-update --hyprland` / `gnomes -S hyprland-noctalia`)**: Complete turnkey Wayland desktop environment powered by Noctalia Shell (dock, topbar, launcher, control center) with automatic GPU environment wrappers, PipeWire AT_SECURE fix (`setcap -r`), 200ms snappy animations, OLED VRR support, and automatic OpenRGB + EasyEffects systray integration.
* **Turnkey Browser GPU Acceleration**: Dynamic NVIDIA detection when installing `google-chrome`, `brave`, or `microsoft-edge`, automatically provisioning hardware-accelerated Wayland and VA-API flags (`--ozone-platform=wayland`, `VaapiOnNvidiaGPUs`, `--enable-gpu-rasterization`, `--enable-zero-copy`).
* **Out-of-Tree DKMS Drivers**: `zenpower3`, `v4l2loopback`, `rtl8821cu`, `rtl88x2bu`, `rtl8812au`, `broadcom-wl`, `r8125`.
* **Native Slackware SysVinit Daemons**: Generates and manages init scripts in `/etc/rc.d/` (`rc.coolercontrol`, `rc.asusd`, `rc.syncthing`, `rc.lact`, `rc.scx`, `rc.ananicy-cpp`, `rc.gamemode`).

### 7. 🧰 Curated SBo SlackBuilds Hub & `sbotools`
* **Version Auto-Tuning**: Automatically routes build recipes to Ponce's git repository on Slackware `-current` or standard SBo on `15.0`.
* **26 Curated Recipes**: Plasticity 3D CAD, Wonder Unit Storyboarder, Serif Affinity Suite, Blender, FreeCAD, Unreal Engine 5, SoftMaker FreeOffice 2024, Opera, LACT, OpenRGB, and SpaceMouse utilities.

### 8. 🌍 Multi-Lingual Engine (24 Locales) & Dynamic Live Tickers
* Full internationalization across 24 languages with 100% key parity (213 keys each).
* Standard sober English (`en`), Norwegian (`nb`), and 22 global languages by default with clockwise rotating hourglass (`⏳`/`⌛`).
* **Radical Editions** (`en-radical`, `nb-radical`): 90s pop-culture (*Bill & Ted*, *TMNT*, *Wayne's World*) with high-voltage pulsing lightning bolt (`⚡`/`✨`).

---

## 📦 Installation & Setup

### Method 1: Build from Source via GitHub (Canonical Repository)
```bash
# 1. Clone repository from GitHub
git clone https://github.com/TuxOfValhalla/slacky-update.git
cd slacky-update

# 2. Build the package via SlackBuild
sudo bash slackbuild/slacky-update.SlackBuild

# 3. Install or upgrade the package
sudo upgradepkg --install-new --reinstall /tmp/slacky-update-*-noarch-1_slacky.txz
```

### Method 2: Build from Source via Codeberg (European Mirror)
```bash
# 1. Clone repository from Codeberg
git clone https://codeberg.org/TuxOfValhalla/slacky-update.git
cd slacky-update

# 2. Build the package via SlackBuild
sudo bash slackbuild/slacky-update.SlackBuild

# 3. Install or upgrade the package
sudo upgradepkg --install-new --reinstall /tmp/slacky-update-*-noarch-1_slacky.txz
```

### Method 3: Direct Package Download (GitHub Releases)
You can also download and install the pre-built Slackware `.txz` package directly from GitHub Releases:
```bash
# Download latest release package
curl -sLO https://github.com/TuxOfValhalla/slacky-update/releases/latest/download/slacky-update-0.14.0-noarch-1_slacky.txz

# Install or upgrade
sudo upgradepkg --install-new --reinstall slacky-update-0.14.0-noarch-1_slacky.txz
```

#### Quick 1-Line Installer (GitHub)
```bash
git clone https://github.com/TuxOfValhalla/slacky-update.git && cd slacky-update && sudo bash slackbuild/slacky-update.SlackBuild && sudo upgradepkg --install-new --reinstall /tmp/slacky-update-*-noarch-1_slacky.txz && slacky-update-tray &
```

#### Quick 1-Line Installer (Codeberg Mirror)
```bash
git clone https://codeberg.org/TuxOfValhalla/slacky-update.git && cd slacky-update && sudo bash slackbuild/slacky-update.SlackBuild && sudo upgradepkg --install-new --reinstall /tmp/slacky-update-*-noarch-1_slacky.txz && slacky-update-tray &
```

---

## 💻 Usage & CLI Reference

```bash
# Launch interactive terminal command center
slacky-update

# Run full unattended system update transaction
slacky-update -y
# or:
slacky-update --non-interactive

# Perform read-only audit of pending updates
slacky-update --check

# Open Limine Bootloader & Secure Boot Matrix
slacky-update --limine
# or:
slacky-update -l

# Open Kernel CMDLINE & Gaming Parameter Hub
slacky-update --cmdline
# or:
slacky-update -c

# Synchronize initramfs, Limine/GRUB, enroll BLAKE2B hashes & sign
slacky-update --sync-boot
# or:
slacky-update -b

# Dynamically verify on-disk kernel & initramfs BLAKE2B hashes against Limine
slacky-update --hash-check
# or:
slacky-update -H
# or alias:
hash-check

# Synchronize NVIDIA driver suite and compile/match kernel modules
slacky-update --sync-nvidia

# Clean package caches, remove obsolete kernels & orphans
slacky-update --clean

# Open Underpants Gnomes Gaming Suite
slacky-update --gaming
# or:
slacky-update -g

# Open Curated SBo SlackBuilds Hub
slacky-update --slackbuilds
# or:
slacky-update -s

# Open System Performance & Gaming Tweaks
slacky-update --tweaks
# or:
slacky-update -t

# Launch Master Field Guide & Multi-Format Export
slacky-update --guide

# Set default interface language
slacky-update --lang en
slacky-update --lang en-radical
slacky-update --lang nb

# List all available language codes
slacky-update --list-langs

# Start or restart background system tray applet
slacky-update-tray --restart
```

---

## 📖 Complete Documentation & System Manuals
 
For complete user manuals, disaster recovery procedures, UEFI BIOS configuration walkthroughs, kernel scheduling deep dives, and under-the-hood engine architecture specifications, please consult our open documentation:

* 📘 **[Slacky-Update Survival Guide & System Manual](docs/SLACKY_UPDATE_FIELD_GUIDE.md)** — The complete end-user operational manual, BIOS playbook, and driver guide.
* 🛠️ **[Slacky-Update Technical Companion Guide](docs/TECHNICAL_COMPANION_GUIDE.md)** — Architectural whitepaper detailing all 12 internal engines, sandboxing mechanisms, zero-rootfs compilation model, and Slackware coexistence philosophy.
* 🚨 **[Disaster Recovery & Troubleshooting Guide](docs/TROUBLESHOOTING_GUIDE.md)** — 11-scenario symptom catalog, recovery playbook, ELI5 guides, and emergency live-USB chroot procedures.
* 🥾 **[Limine & Secure Boot Field Guide](docs/LIMINE_SECUREBOOT_FIELD_GUIDE.md)** — ESP topology migration, A–Z manual partition guide, and `sbctl` setup.

---

## 📜 Project Ancestry & Disclaimers

### AI-Assisted Development Notice
This application was developed with the assistance of advanced AI pair-programming agents and was meticulously reviewed, architected, debugged, refactored, and tested on real bare-metal Slackware hardware by the author (**tuxofvalhalla**).

### Project Fork & Heritage
**Slacky-Update** is a specialized, direct fork and successor of the author's sister project, **Debian-Update**, completely rewritten and restructured from the ground up to respect Slackware's native packaging philosophy, BSD-style init scripts, and kernel/module layout.

### Trademark & Fair Use Disclaimer
* **Slacky-Update** is an independent open-source project created by and for the Linux enthusiast community.
* This project is **not** officially affiliated with, endorsed by, sponsored by, or maintained by **Patrick Volkerding** or **Slackware Linux, Inc.**
* The name *Slackware* and associated logos are used strictly under **nominative fair use** to identify compatibility with the Slackware operating system distribution.

### License
This project is licensed under the **GNU General Public License v3.0 (GPL-3.0)**. See the [LICENSE](LICENSE) file for complete details.
