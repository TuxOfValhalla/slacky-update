<div align="center">

# ⚡ Slacky-Update
### *Enterprise-Grade System Maintenance, Kernel Lifecycle, Driver Orchestrator & Workstation Suite for Slackware Linux*
#### `v0.12.0` — *"....and all that I can see, is just another Limine tree...."* (Pre-Release / Early Access)

[![Slackware -current](https://img.shields.io/badge/Slackware--current-15.0%2B-blue?style=for-the-badge&logo=slackware&logoColor=white)](http://www.slackware.com/)
[![Release](https://img.shields.io/badge/Release-v0.12.0--pre--release-purple?style=for-the-badge)](https://codeberg.org/TuxOfValhalla/slacky-update/releases)
[![Canonical: Codeberg](https://img.shields.io/badge/Canonical-Codeberg-2185d0?style=for-the-badge&logo=codeberg&logoColor=white)](https://codeberg.org/TuxOfValhalla/slacky-update)
[![Mirror: GitHub](https://img.shields.io/badge/Mirror-GitHub-grey?style=for-the-badge&logo=github&logoColor=white)](https://github.com/TuxOfValhalla/slacky-update)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-green.svg?style=for-the-badge)](LICENSE)
[![Zero-Binary](https://img.shields.io/badge/Architecture-100%25%20Pure%20Source-brightgreen?style=for-the-badge)](lib/)
[![Locales](https://img.shields.io/badge/Locales-24%20Languages%20(182%20Keys)-yellow?style=for-the-badge)](locales/)
[![Documentation: Survival Guide](https://img.shields.io/badge/Manual-Survival%20Guide-teal?style=for-the-badge)](SURVIVAL_GUIDE.md)
[![Documentation: Architecture](https://img.shields.io/badge/Architecture-Technical%20Companion%20Guide-blueviolet?style=for-the-badge)](TECHNICAL_COMPANION_GUIDE.md)

---

**Slacky-Update** is an all-in-one system maintenance station, background monitor, driver orchestrator, and gaming/workstation modernization suite engineered specifically for **Slackware Linux (-current / 15.0+)**. 

*Canonical source: [Codeberg](https://codeberg.org/TuxOfValhalla/slacky-update) | Secondary mirror: [GitHub](https://github.com/TuxOfValhalla/slacky-update) (pending review) | Master Manual: [SURVIVAL_GUIDE.md](SURVIVAL_GUIDE.md) | Technical Architecture: [TECHNICAL_COMPANION_GUIDE.md](TECHNICAL_COMPANION_GUIDE.md) | Disaster Recovery: [docs/TROUBLESHOOTING_GUIDE.md](docs/TROUBLESHOOTING_GUIDE.md)*

> [!CAUTION]
> **PRE-RELEASE / EARLY ACCESS DISCLAIMER — USE AT YOUR OWN RISK**  
> Slacky-Update v0.12 is an active *Pre-Release / Early Access* edition. The software performs low-level system modifications to core components, including Linux kernel deployments, proprietary NVIDIA drivers, Dracut initramfs generation, Btrfs subvolumes, and bootloader topologies (Limine/GRUB).  
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
 [2] CachyOS Kernel Time Machine  --> CPU Tier Detect, Deploy, Manage & Purge
 [3] NVIDIA & ROCm Graphics Hub   --> CachyOS Master, DKMS, OpenCL / HIP
 [4] Underpants Gnomes Suite      --> 36 Native Transmuted Workstation Apps
 [5] System Cleanup & Retention   --> Dual Kernel Retention & Artifact Purge
 [6] Limine & Secure Boot Armor   --> Two-Zone Config, CMDLINE Hub, sbctl Signing
 [7] System Performance Tweaks    --> NVIDIA 615+ VRAM Booster, TCP BBR, NTSYNC
 [8] Master Field Guide & Manual  --> Open Documentation & Mobile Export
 [9] Multi-Lingual Engine (i18n)  --> 24 Locales with 100% Key Parity
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

### 3. 🏎️ CachyOS High-Performance Kernels
* **CPU Microarchitecture Auto-Detection**: Inspects host CPU features and targets optimized builds (*x86_64_v4 / znver4 for Zen 4/5 & Intel 12th–15th+ Gen Core; x86_64_v3; x86_64_v2*).
* **Advanced Schedulers**: Deploys upstream CachyOS kernels with BORE (Burst-Oriented Response Enhancer), BORE-LTO, `sched-ext` (`scx`), and LTS branches.
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

### 6. 🩲 The Underpants Gnomes Workstation Suite (36 Native Packages)
* **Isolated `/opt/<app>` App-Bundles**: Applications with complex runtimes (`obs-studio`, `lutris`, `pear-desktop`, web browsers) reside in self-contained directories with `/usr/bin/` wrappers—never polluting host system Python or library paths.
* **Cryptographic GPG Validation**: Upstream archives (`.pkg.tar.zst`) and signatures (`.sig`) are strictly verified against Arch and CachyOS public keys prior to packaging.
* **Native Slackware SysVinit Daemons**: Generates and manages init scripts in `/etc/rc.d/` (`rc.coolercontrol`, `rc.asusd`, `rc.syncthing`, `rc.lact`, `rc.scx`, `rc.ananicy-cpp`, `rc.gamemode`).

### 7. 🧰 Curated SBo SlackBuilds Hub & `sbotools`
* **Version Auto-Tuning**: Automatically routes build recipes to Ponce's git repository on Slackware `-current` or standard SBo on `15.0`.
* **25 Curated Recipes**: Wonder Unit Storyboarder, Serif Affinity Suite, Blender, FreeCAD, Unreal Engine 5, SoftMaker FreeOffice 2024, LACT, OpenRGB, and SpaceMouse utilities.

### 8. 🌍 Multi-Lingual Engine (24 Locales) & Dynamic Live Tickers
* Full internationalization across 24 languages with 100% key parity (182 keys).
* Standard sober English (`en`), Norwegian (`nb`), and 22 global languages by default with clockwise rotating hourglass (`⏳`/`⌛`).
* **Radical Editions** (`en-radical`, `nb-radical`): 90s pop-culture (*Bill & Ted*, *TMNT*, *Wayne's World*) with high-voltage pulsing lightning bolt (`⚡`/`✨`).

---

## 📦 Installation & Setup

### Method 1: Build from Source via Codeberg (Canonical European Repository)
```bash
# 1. Clone repository from Codeberg
git clone https://codeberg.org/TuxOfValhalla/slacky-update.git
cd slacky-update

# 2. Build the package via SlackBuild
sudo bash slackbuild/slacky-update.SlackBuild

# 3. Install or upgrade the package
sudo upgradepkg --install-new --reinstall /tmp/slacky-update-*-noarch-1_slacky.txz
```

### Method 2: Build from Source via GitHub (Mirror Repository)
```bash
# 1. Clone repository from GitHub
git clone https://github.com/TuxOfValhalla/slacky-update.git
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
curl -sLO https://github.com/TuxOfValhalla/slacky-update/releases/latest/download/slacky-update-0.12.0-noarch-1_slacky.txz

# Install or upgrade
sudo upgradepkg --install-new --reinstall slacky-update-0.12.0-noarch-1_slacky.txz
```

#### Quick 1-Line Installer (Codeberg)
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

* 📘 **[Slacky-Update Survival Guide & System Manual](SURVIVAL_GUIDE.md)** — The complete end-user operational manual, BIOS playbook, and driver guide.
* 🛠️ **[Slacky-Update Technical Companion Guide](TECHNICAL_COMPANION_GUIDE.md)** — Architectural whitepaper detailing all 12 internal engines, sandboxing mechanisms, zero-rootfs compilation model, and Slackware coexistence philosophy.
* 🚨 **[Disaster Recovery & Troubleshooting Guide](docs/TROUBLESHOOTING_GUIDE.md)** — 8-scenario symptom catalog, recovery playbook, and emergency live-USB chroot procedures.
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
