# 📖 Slacky-Update Survival Guide & System Manual
### *Slackware Linux 15.0 & -current — Complete Architecture, Deployment & Operational Manual*
#### `v0.12.2` — *"....and all that I can see, is just another Limine tree...."* (Pre-Release / Early Access)

---

> [!CAUTION]
> **PRE-RELEASE / EARLY ACCESS DISCLAIMER & LIABILITY NOTICE — USE AT YOUR OWN RISK**  
> Slacky-Update v0.12 is an active *Pre-Release / Early Access* edition. The software executes deep low-level system modifications, including Linux kernel deployments, proprietary NVIDIA drivers, Dracut initramfs generation, Btrfs subvolumes, and bootloader topologies (Limine/GRUB).  
> **All usage, upgrades, and system configurations are executed strictly at your own discretion and risk.** The developers and maintainers assume no liability or warranty for system malfunction, unbootable states, or data loss.  
> **Pre-requisites:** Always maintain tested, current backups (`/home`, essential configuration files, and boot partitions) and keep a bootable Slackware Live-USB accessible before performing upgrades or modifying bootloader setups.

---

## 📑 Table of Contents
* [🚦 Pre-Flight: Before You Press [1] (Full System Upgrade)](#-pre-flight-before-you-press-1-full-system-upgrade)
1. [1. Introduction & Architecture Philosophy](#1-introduction--architecture-philosophy)
2. [2. Installation & Build Guide](#2-installation--build-guide)
3. [3. System Synchronization Engine](#3-system-synchronization-engine)
4. [4. Limine Bootloader & UEFI Secure Boot](#4-limine-bootloader--uefi-secure-boot)
   - [Two-Zone limine.conf Architecture](#two-zone-limineconf-architecture)
   - [Cryptographic Safe Hashing & Anti-Tamper Security](#cryptographic-safe-hashing--anti-tamper-security)
   - [Interactive Kernel CMDLINE & Gaming Hub](#interactive-kernel-cmdline--gaming-hub)
   - [UEFI Secure Boot Setup with sbctl & MOK](#uefi-secure-boot-setup-with-sbctl--mok)
   - [Windows 11 Dual-Booting Playbook](#windows-11-dual-booting-playbook)
   - [Motherboard UEFI/BIOS Settings Matrix](#motherboard-uefibios-settings-matrix)
   - [Btrfs Snapper Snapshot Rollbacks](#btrfs-snapper-snapshot-rollbacks)
   - [Coexistence Mode & Self-Healing](#coexistence-mode--self-healing)
5. [5. CachyOS High-Performance Kernels](#5-cachyos-high-performance-kernels)
   - [CPU Microarchitecture Auto-Detection](#cpu-microarchitecture-auto-detection)
   - [Kernel Flavors & Schedulers](#kernel-flavors--schedulers)
   - [Retention & Rollback Safeguards](#retention--rollback-safeguards)
6. [6. Graphics Stack & Driver Orchestration](#6-graphics-stack--driver-orchestration)
   - [NVIDIA CachyOS Master Suite & DKMS](#nvidia-cachyos-master-suite--dkms)
   - [Stale Kernel Module Purge & Depmod Shield](#stale-kernel-module-purge--depmod-shield)
   - [Hybrid & Laptop GPU Configuration (PRIME)](#hybrid--laptop-gpu-configuration-prime)
   - [AMD ROCm & HIP Creator Toolkit](#amd-rocm--hip-creator-toolkit)
7. [7. NVIDIA 615+ VRAM Booster & Memory Architecture](#7-nvidia-615-vram-booster--memory-architecture)
   - [Driver Memory Management in 615.x+](#driver-memory-management-in-615x)
   - [VRAM Fragmentation in Direct3D 12 & VKD3D](#vram-fragmentation-in-direct3d-12--vkd3d)
   - [Preserving Video Memory Allocations](#preserving-video-memory-allocations)
   - [Wayland & DRM Direct Modesetting](#wayland--drm-direct-modesetting)
   - [Kernel Memory Mapping & HugePages (madvise + defer)](#kernel-memory-mapping--hugepages-madvise--defer)
8. [8. The Underpants Gnomes Workstation Suite](#8-the-underpants-gnomes-workstation-suite)
   - [Isolated Application Trees in /opt](#isolated-application-trees-in-opt)
   - [Cryptographic GPG Verification](#cryptographic-gpg-verification)
   - [Native Slackware SysVinit Integration](#native-slackware-sysvinit-integration)
   - [Package Manifest](#package-manifest)
9. [9. SBo SlackBuilds Hub & sbotools](#9-sbo-slackbuilds-hub--sbotools)
10. [10. System Performance & Kernel Tweaks](#10-system-performance--kernel-tweaks)
11. [11. Multi-Lingual Engine (24 Locales & 90s Tickers)](#11-multi-lingual-engine-24-locales--90s-tickers)
12. [12. CLI Reference & Troubleshooting](#12-cli-reference--troubleshooting)

---

## 🚦 Pre-Flight: Before You Press [1] (Full System Upgrade)

Before executing your first full system upgrade or modifying kernels and bootloaders, review this 1-page pre-flight checklist:

- [ ] **1. Slackware Branch:** Are you running Slackware 15.0 or -current? (Verify via `cat /etc/slackware-version`).
- [ ] **2. Boot Mode:** Is your machine booted in UEFI or Legacy BIOS? (Verify via `[ -d /sys/firmware/efi ] && echo "UEFI" || echo "BIOS"`).
- [ ] **3. ESP Capacity:** Is `/boot` (or `/boot/efi`) at least 3.5 GB if you plan to use Limine? (Verify via `df -h /boot` or `df -h /boot/efi`). See [docs/LIMINE_SECUREBOOT_FIELD_GUIDE.md](docs/LIMINE_SECUREBOOT_FIELD_GUIDE.md) for partitioning standards.
- [ ] **4. Filesystem:** Are you running Btrfs (with Snapper subvolumes) or standard ext4? (Verify via `findmnt /`).
- [ ] **5. Graphics Card:** Do you have dedicated NVIDIA GeForce, AMD Radeon, or Intel GPU? (Verify via `lspci | grep -iE 'vga|3d'`).
- [ ] **6. Backups:** Have you backed up your personal data (`/home`) and critical system configuration files?
- [ ] **7. Rescue Media:** Do you have a bootable Slackware Live-USB ready in case of power interruption during kernel compilation?
- [ ] **8. Liability Understanding:** Do you understand that deep system upgrades and bootloader migrations are performed at your own risk?

---

## 1. Introduction & Architecture Philosophy

> [!NOTE]
> ### 🧩 ELI5 — What does this module do and why do you care?
> Think of Slacky-Update as an elite Formula 1 pit crew for your PC. It preserves your original, rock-solid Slackware engine, but bolts on a high-flow turbocharger, race-tuned suspension, and modern telemetry—without ever stripping or damaging any factory parts.

**Slacky-Update** is an enterprise-grade, non-destructive system maintenance station, background monitor, driver orchestrator, and high-performance workstation toolkit engineered specifically for **Slackware Linux 15.0 and -current**.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SLACKY-UPDATE ARCHITECTURE                        │
├─────────────────────────────────────────────────────────────────────────────┤
│  [User Layer]      CLI Interface  │  System Tray Applet  │  Multi-Lingual   │
├─────────────────────────────────────────────────────────────────────────────┤
│  [Graphics/Audio]  NVIDIA 615+    │  AMD ROCm / HIP      │  Yabridge / VST  │
├─────────────────────────────────────────────────────────────────────────────┤
│  [Kernel Layer]    CachyOS BORE   │  Sched-EXT (SCX)     │  Stock Slackware │
├─────────────────────────────────────────────────────────────────────────────┤
│  [Init/Storage]    Dracut Initramfs (lib64 Shield) │ Btrfs Snapper Snapshot │
├─────────────────────────────────────────────────────────────────────────────┤
│  [Boot Layer]      Limine (Two-Zone + sbctl)  │  GRUB / ELILO Coexistence   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Core Design Principles
* **Strict Slackware Compliance**: No foreign package managers (`apt`, `dnf`, `pacman`). All transmuted binaries and SlackBuilds conform strictly to Slackware's native packaging standards (`.txz`, `pkgtools`, SysVinit scripts in `/etc/rc.d/`).
* **Non-Destructive Coexistence**: Stock bootloaders (GRUB/ELILO), kernels, and system configuration files are never overwritten destructively. Fallback boot entries remain accessible in firmware NVRAM.
* **Atomic Transactions**: Kernel updates, DKMS compilation, Dracut initramfs generation, and cryptographic Secure Boot signing occur as an atomic chain to guarantee system bootability.
* **Pure Source & Auditable Code**: 100% shell scripts, Python, and native C helpers without opaque pre-compiled binaries in the source tree.

> [!TIP]
> For a deep technical analysis of how our 12 internal engines function, see the **[Slacky-Update Technical Companion Guide](TECHNICAL_COMPANION_GUIDE.md)**. For symptom-based recovery and emergency procedures, see the **[Disaster Recovery & Troubleshooting Guide](docs/TROUBLESHOOTING_GUIDE.md)**.

---

## 2. Installation & Build Guide

> [!NOTE]
> ### 🧩 ELI5 — What does this module do and why do you care?
> Here we build the application from source the pure Slackware way: creating a clean `.txz` package. No shady binary installers or foreign package managers—everything is 100% auditable source code properly tracked in system package logs.

### Building the Slackware Package (`.txz`)
Slacky-Update is built natively using the standard Slackware build methodology:

```bash
# 1. Clone the repository (Codeberg Canonical)
git clone https://codeberg.org/TuxOfValhalla/slacky-update.git
cd slacky-update

# 2. Build the package via SlackBuild
sudo bash slackbuild/slacky-update.SlackBuild

# 3. Install or upgrade the package
sudo upgradepkg --install-new --reinstall /tmp/slacky-update-*-noarch-1_slacky.txz
```

### Starting the Background System Monitor
The system tray monitor starts automatically on desktop login via `/etc/xdg/autostart/slacky-update-tray.desktop`. To launch it immediately in your active session:

```bash
slacky-update-tray &
```

---

## 3. System Synchronization Engine

> [!NOTE]
> ### 🧩 ELI5 — What does this module do and why do you care?
> When you press [1], a 10-track turbo download train takes off. Instead of downloading packages one by one at a crawl, Slacky-Update fetches all updates concurrently, upgrades the core system safely, and sorts out new configuration files (`.new`) without clobbering your customized settings.

The primary synchronization workflow (`slacky-update` option 1 or `slacky-update -y`) coordinates multi-layer upgrades sequentially:

```
[1/7] Multi-Worker Pre-fetch (10 Parallel Streams) ➔ Warm-Cache Handoff
[2/7] Slackware Core Upgrade via slackpkg (Atomic Multi-Pass Resume)
[3/7] CachyOS Kernel Synchronization & CPU Microarchitecture Tiering
[4/7] NVIDIA / ROCm Driver Pipeline (DKMS Build & Flatpak GL Sync)
[5/7] SBo SlackBuilds Pipeline via sbotools
[6/7] Underpants Gnomes Workstation & Gaming Suite Verification
[7/7] Post-Upgrade Matrix Pipeline (5-Step Deterministic Chain)
```

### Deterministic 5-Step Post-Upgrade Pipeline
When package or kernel changes occur, Slacky-Update executes an atomic, sequential 5-step pipeline:
```
  [1/5] CachyOS NVIDIA Module Match     : Active driver modules linked in kernel tree
  [2/5] Module Dependency Tree (depmod) : Symbol references resolved across all modules
  [3/5] Dracut Initramfs Generation     : Live animated ticker + Hardware Guard (>=12 threads, >=16GB RAM)
  [4/5] Limine Config & BLAKE2B Hash    : BLAKE2B enrolled for tamper-proof boot
  [5/5] Secure Boot MOK / sbctl Signing : Unified cryptographic UEFI signature validation
```

### Key Synchronization Features
1. **10-Worker Parallel Pre-fetcher**: Accelerates downloads using 10 concurrent HTTP/FTP worker streams (`SLACKY_PREFETCH_JOBS=10`). Downloads `.txz` packages and `.asc` GPG signatures into a warm cache with resume capability (`-C -`), cutting download phases by 5–10×.
2. **Multi-Pass Resume Engine**: If foundational packages (`slackpkg`, `pkgtools`, `glibc-solibs`, or `ca-certificates`) upgrade mid-transaction, Slacky-Update detects the toolchain replacement and seamlessly resumes the transaction without split-brain failures.
3. **Smart `.new` Configuration Reconciliation**: Scans `/etc/` post-upgrade and categorizes `.new` files into 4 groups (*New Configurations*, *Identical Duplicates*, *Unmodified Defaults*, *Custom User Configurations*) with batch actions, eliminating 95% of upgrade prompt fatigue.
4. **Smart Reboot Evaluator**: Inspects updated package manifests to detect if the active running kernel, glibc, or NVIDIA driver was updated, prompting for a reboot only when strictly necessary.

---

## 4. Limine Bootloader & UEFI Secure Boot

> [!NOTE]
> ### 🧩 ELI5 — What does this module do and why do you care?
> The bootloader is the ignition key that starts your computer before the OS wakes up. Limine is a blazing-fast, modern bootloader that supports Secure Boot and Btrfs snapshots, while ensuring Windows and other operating systems keep booting smoothly side-by-side.

Limine is a modern, lightweight, blazing-fast bootloader that supports advanced UEFI features, graphical themes, safe cryptographic hashing, and Btrfs snapshot rollbacks.

### Two-Zone Configuration Model
Slacky-Update manages `/boot/limine.conf` using a strict Two-Zone architecture:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           LIMINE.CONF ARCHITECTURE                          │
├─────────────────────────────────────────────────────────────────────────────┤
│ ZONE A: USER-CONTROLLED HEADER (Preserved Across All Updates)               │
│ - Timeout, default entry, resolution, graphical wallpaper, theme colors     │
├─────────────────────────────────────────────────────────────────────────────┤
│ ### --- SLACKY-UPDATE DYNAMIC KERNEL ZONE (DO NOT EDIT BELOW) --- ###      │
│ ZONE B: AUTOMATED KERNEL ENTRIES (Generated & Verified Atomically)          │
│ - CachyOS BORE / LTS kernels with exact BLAKE2B hashes                       │
│ - Stock Slackware kernels with Dracut initramfs & microcode modules         │
│ - Btrfs Snapper rollback snapshots (read-only boot entries)                 │
│ - Windows 11 Boot Manager chainload entries                                 │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Safe Hashing & Anti-Tamper Security
Slacky-Update enrolls BLAKE2B cryptographic hashes directly into boot entries:
```ini
/Slackware Linux (CachyOS BORE)
    protocol: linux
    kernel_path: boot():/vmlinuz-linux-cachyos-bore#2c74e8a104...
    module_path: boot():/initramfs-linux-cachyos-bore.img#9bf8a02c...
    cmdline: root=UUID=xxxx-xxxx-xxxx rw quiet splash
```
If an unverified binary modification occurs on disk, Limine detects the hash mismatch and prevents execution of compromised files.

### Interactive Kernel CMDLINE & Gaming Hub (`slacky-update --cmdline`)
* **Root Protection**: Fixed filesystem root parameters (`root=UUID=...`) are automatically protected.
* **Smart Parameter Toggles**: Quick toggles for `quiet splash`, `nvidia_drm.modeset=1`, AMD LACT GPU overclocking (`amdgpu.ppfeaturemask=0xffffffff`), `nowatchdog`, USB autosuspend, IOMMU/VFIO passthrough, and ZSWAP memory compression.

### Windows 11 Dual-Booting & UEFI Secure Boot
With Slacky-Update's `sbctl` and MOK (Machine Owner Keys) integration, you can keep **Secure Boot permanently enabled in BIOS** and boot freely between Windows 11 and Slackware Linux without security warnings.

> [!TIP]
> For a comprehensive A–Z manual partitioning guide, ESP requirements ($\ge 3.5\text{ GB}$), and migration scenarios, see **[docs/LIMINE_SECUREBOOT_FIELD_GUIDE.md](docs/LIMINE_SECUREBOOT_FIELD_GUIDE.md)**.

---

## 5. CachyOS High-Performance Kernels

> [!NOTE]
> ### 🧩 ELI5 — What does this module do and why do you care?
> The Linux kernel is the beating heart of your computer. CachyOS kernels are tuned specifically for gaming and heavy workloads, using BORE schedulers that distribute CPU power instantly to the active game or application you are running, matched to your exact CPU generation.

Slacky-Update provides full lifecycle management for upstream CachyOS high-performance Linux kernels compiled with aggressive `-O3` optimizations, `futex2` fast synchronization, and modern scheduling architectures.

### CPU Microarchitecture Auto-Detection
Slacky-Update inspects your CPU microarchitecture via `/proc/cpuinfo` and `gcc -march=native -Q --help=target`:
* **Tier 4 (`x86_64_v4` / `znver4`)**: AVX-512, AVX-VNNI, BFLOAT16 (AMD Zen 4/5, Intel 12th–15th+ Gen Core).
* **Tier 3 (`x86_64_v3`)**: AVX, AVX2, FMA, BMI1/2 (AMD Zen 1–3, Intel Haswell through 11th Gen Core).
* **Tier 2 (`x86_64_v2`)**: SSE4.2, SSSE3 (Older 64-bit x86 processors).

### Kernel Flavors & Retention Rules
* **BORE & BORE-LTO**: Balances interactive desktop smoothness and high-throughput gaming frame pacing.
* **Sched-EXT (`scx`)**: User-space extensible BPF scheduler framework (`scx_rusty`, `scx_lavd`).
* **LTS**: Rock-solid stability backed by CachyOS optimizations for mission-critical workstations.
* **Retention Safeguards**: Automatically retains the **2 newest standard/BORE kernels** and strictly shields the active booted kernel (`uname -r`).

---

## 6. Graphics Stack & Driver Orchestration

> [!NOTE]
> ### 🧩 ELI5 — What does this module do and why do you care?
> Your graphics card needs the exact right translator (driver) to communicate with the kernel. Slacky-Update makes sure your NVIDIA or AMD drivers automatically match your kernel version, cleans out old module leftovers, and prevents you from landing in a black text screen after an update.

### NVIDIA CachyOS Master Suite & DKMS
* **Precompiled Open Modules**: Official prebuilt modules for CachyOS kernels on Turing (GTX 16xx / RTX 20xx) and newer GPUs with zero compilation time.
* **DKMS Compilation**: Automated module compilation for standard Slackware kernels.
* **Multilib 32-bit**: Synchronizes matching 32-bit OpenGL and Vulkan drivers for Steam and Wine.
* **Stale Module Purge**: Scans and cleans conflicting `nvidia*.ko*` files across all installed kernels and executes `depmod -a`.

### AMD ROCm & HIP Creator Toolkit
For creative professionals using AMD Radeon GPUs in DaVinci Resolve Studio:
* Deploys complete ROCm compute stack with 64-bit and 32-bit OpenCL ICD registration.
* **Mesa Conflict Shield**: Automatically purges and blacklists conflicting `mesa-opencl` packages that cause DaVinci Resolve crashes on Radeon RDNA hardware.

---

## 7. NVIDIA 615+ VRAM Booster & Memory Architecture

> [!NOTE]
> ### 🧩 ELI5 — What does this module do and why do you care?
> Have you experienced games crashing or stuttering because your graphics card memory (VRAM) gets full or fragmented? The VRAM Booster forces the graphics driver and Linux to keep memory tidy and retain game data even when your PC goes to sleep.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      NVIDIA 615+ VRAM PIPELINE OPTIMIZATION                 │
├─────────────────────────────────────────────────────────────────────────────┤
│  [Direct3D 12 / VKD3D-Proton] Heavy Allocation Requests                     │
│         │                                                                   │
│         ▼                                                                   │
│  [Kernel Parameters]  NVreg_PreserveVideoMemoryAllocations=1                │
│                       NVreg_TemporaryFilePath=/var/tmp                      │
│         │                                                                   │
│         ▼                                                                   │
│  [System VM Tuning]   vm.max_map_count = 2147483642                         │
│                       THP: enabled = madvise, defrag = defer                │
│         │                                                                   │
│         ▼                                                                   │
│  [Direct DRM Output]  nvidia_drm.modeset=1  nvidia_drm.fbdev=1              │
│                       Eliminates Wayland composition stutter & frame drops  │
└─────────────────────────────────────────────────────────────────────────────┘
```

Configured automatically via `/etc/modprobe.d/nvidia-power-management.conf` and `/etc/sysctl.d/99-gaming-performance.conf`.

---

## 8. The Underpants Gnomes Workstation Suite

> [!NOTE]
> ### 🧩 ELI5 — What does this module do and why do you care?
> Want Discord, Chrome, OBS Studio, or MangoHud on Slackware without having to compile 50 dependencies by hand? Our Underpants Gnomes fetch prebuilt packages, verify their cryptographic signatures, and package them into self-contained `/opt` folders that never mess up your system libraries.

### Isolated Application Trees in `/opt`
Complex applications with bundled runtimes reside in isolated directories in `/opt/<name>/` with dedicated wrapper scripts in `/usr/bin/`. Host system Python modules and libraries are **never overwritten**.

### Security & Services
* **GPG Validation**: All upstream archives are strictly verified against official GPG signatures before transmutation.
* **Slackware SysVinit**: Services integrate natively with `/etc/rc.d/` (`rc.gamemode`, `rc.coolercontrol`, `rc.lact`, `rc.syncthing`, `rc.scx`, `rc.ananicy-cpp`).

---

## 9. SBo SlackBuilds Hub & `sbotools`

> [!NOTE]
> ### 🧩 ELI5 — What does this module do and why do you care?
> SlackBuilds.org (SBo) is Slackware's official library of build recipes. Slacky-Update connects you automatically to the right repository for your version and lets you build popular software like Blender, FreeOffice, and DaVinci Resolve with a single keypress.

* **Version Auto-Routing**: Routes recipes to Ponce's git tree on `-current` or standard SBo on `15.0`.
* **Hardware Thread Scaling**: Sets `JOBS=$(nproc)` for optimal build speed without locking system responsiveness.
* **Curated Recipes**: Blender, Storyboarder, Affinity Suite, SoftMaker FreeOffice 2024, DaVinci Resolve Studio, LACT, Snapper, and OpenRGB.

---

## 10. System Performance & Kernel Tweaks

> [!NOTE]
> ### 🧩 ELI5 — What does this module do and why do you care?
> Here we tune your system's 'throttle pedal' and network stack. We enable Google BBR for lower ping and smoother downloads, optimize memory buffers for gaming, and give real-time priority to audio so sound and mouse movement never stutter under heavy load.

Accessible via `slacky-update --tweaks`:
1. **1 Million File Descriptors**: Eliminates resource exhaustion in heavily modded games (*Star Citizen*, *Cyberpunk 2077*).
2. **Pro Audio Realtime Scheduling**: Prioritizes PipeWire (`rtprio 95`, `nice -19`) for dropout-free audio production and gaming.
3. **Transparent HugePages (`madvise + defer`)**: Eliminates allocation micro-stutter in modern game engines.
4. **Google TCP BBR**: Minimizes bufferbloat and network latency during online gaming.
5. **NTSYNC & Gamepad Udev Rules**: Prepares fast Windows NT synchronization primitives and includes udev rules for 28 gaming controllers.

---

## 11. Multi-Lingual Engine (24 Locales & 90s Tickers)

> [!NOTE]
> ### 🧩 ELI5 — What does this module do and why do you care?
> Slacky-Update speaks 24 different languages! In addition to standard sober English and Norwegian, we feature 'Radical Editions' packed with 90s pop-culture slang from Ninja Turtles, Wayne's World, and Bill & Ted for authentic retro vibes in your terminal.

* **Full Localization**: 24 languages with 100% key parity (`en`, `nb`, `nn`, `da`, `sv`, `de`, `fr`, `es`, `it`, `pl`, `fi`, `is`, `nl`, `pt`, `ru`, `ja`, `zh`, `ko`, `hi`, `ar`, `se`).
* **Radical Editions (`en-radical`, `nb-radical`)**: 90s pop-culture slang with pulsing lightning bolt animations (`⚡`/`✨`) during kernel builds.
* **Switch Language:**
  ```bash
  slacky-update --lang en
  slacky-update --lang en-radical
  slacky-update --lang nb
  ```

---

## 12. CLI Reference & Troubleshooting

> [!NOTE]
> ### 🧩 ELI5 — What does this module do and why do you care?
> This is your reference desk and command cheat sheet. Here you'll find all CLI shortcuts for automated nightly upgrades, read-only checks, and links to emergency disaster recovery if anything unexpected happens.

### Command Line Flags
| Flag | Description |
| :--- | :--- |
| `slacky-update` | Launch interactive terminal command center |
| `slacky-update -y` (or `--non-interactive`) | Full unattended system upgrade transaction |
| `slacky-update --check` | Read-only scan for pending updates |
| `slacky-update --limine` (or `-l`) | Open Limine Bootloader & Secure Boot Matrix |
| `slacky-update --cmdline` (or `-c`) | Configure Kernel Boot Parameters (CMDLINE Hub) |
| `slacky-update --sync-boot` (or `-b`) | Synchronize initramfs, Limine/GRUB, BLAKE2B hashes & Secure Boot |
| `slacky-update --sync-nvidia` | Synchronize NVIDIA driver suite, DKMS & build initramfs |
| `slacky-update --clean` (or `--purge-kernels`) | Clean package caches, remove obsolete kernels & orphans |
| `slacky-update --restore-limine` | Restore Limine bootloader from verified backup |
| `slacky-update --gaming` (or `-g`) | Open Underpants Gnomes Gaming Suite |
| `slacky-update --slackbuilds` (or `-s`) | Open SlackBuilds & sbotools hub |
| `slacky-update --tweaks` (or `-t`) | Open System Performance & Gaming Tweaks |
| `slacky-update --guide` (or `-d`) | Launch Master Field Guide & Multi-Format Export (PDF/QR) |

### Troubleshooting & Disaster Recovery
For comprehensive step-by-step procedures covering the 8 most critical failure scenarios (black screen, NVRAM reset, hash mismatch, NVIDIA TTY crash, Live-USB chroot):
👉 **Consult [docs/TROUBLESHOOTING_GUIDE.md](docs/TROUBLESHOOTING_GUIDE.md)**

---

<div align="center">
<b>Slacky-Update — Engineered for Slackware Linux</b><br>
<i>Canonical Source: <a href="https://codeberg.org/TuxOfValhalla/slacky-update">Codeberg</a> | Secondary Mirror: <a href="https://github.com/TuxOfValhalla/slacky-update">GitHub</a> (pending review)</i>
</div>
