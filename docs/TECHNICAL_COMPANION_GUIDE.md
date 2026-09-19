# 🛠️ Slacky-Update Technical Companion Guide: Under the Hood & Engine Architecture
### *A Deep-Dive Architectural Whitepaper & Technical Reference for Slackware Linux 15.0 & -current*
#### `v0.13.0` — *"It's My Party, And I'll Cry If I Want To..."* (Release Edition)

---

> [!CAUTION]
> **PRE-RELEASE / EARLY ACCESS DISCLAIMER & LIABILITY NOTICE — USE AT YOUR OWN RISK**  
> Slacky-Update v0.12 is an active *Pre-Release / Early Access* edition. The software executes low-level system modifications, including Linux kernel deployments, proprietary NVIDIA drivers, Dracut initramfs generation, Btrfs subvolumes, and bootloader topologies (Limine/GRUB).  
> **All usage, upgrades, and system configurations are executed strictly at your own discretion and risk.** The developers and maintainers assume no liability or warranty for system malfunction, unbootable states, or data loss.  
> **Pre-requisites:** Always maintain tested, current backups (`/home`, essential configuration files, and boot partitions) and keep a bootable Slackware Live-USB accessible before performing upgrades or modifying bootloader setups.

---

## 📑 Table of Contents
1. [1. Philosophical Manifesto: Harmony with Slackware](#1-philosophical-manifesto-harmony-with-slackware)
   - [100% Respect for Slackware Core](#100-respect-for-slackware-core)
   - [The Zero-Rootfs Compilation Rule (Sandboxing)](#the-zero-rootfs-compilation-rule-sandboxing)
   - [Coexistence vs. Replacement](#coexistence-vs-replacement)
   - [Zero-Binary Policy & Transparent Source](#zero-binary-policy--transparent-source)
2. [2. Master Architecture Overview](#2-master-architecture-overview)
3. [3. The 12 Internal Engines: Detailed Breakdown](#3-the-12-internal-engines-detailed-breakdown)
   - [Engine 1: Core Orchestration & Lifecycle Controller](#engine-1-core-orchestration--lifecycle-controller)
   - [Engine 2: 10-Worker Asynchronous Turbo Pre-Fetcher](#engine-2-10-worker-asynchronous-turbo-pre-fetcher)
   - [Engine 3: Sandboxed Transmutation & App-Bundle Engine](#engine-3-sandboxed-transmutation--app-bundle-engine)
   - [Engine 4: CachyOS Kernel Lifecycle & CPU Microarchitecture](#engine-4-cachyos-kernel-lifecycle--cpu-microarchitecture)
   - [Engine 5: NVIDIA Driver & DKMS Pipeline](#engine-5-nvidia-driver--dkms-pipeline)
   - [Engine 6: System Performance, Memory Architecture & 1M Resource Limits](#engine-6-system-performance-memory-architecture--1m-resource-limits)
   - [Engine 7: AMD ROCm & HIP Compute Engine](#engine-7-amd-rocm--hip-compute-engine)
   - [Engine 8: Limine Two-Zone & Cryptographic Armor Engine](#engine-8-limine-two-zone--cryptographic-armor-engine)
   - [Engine 9: SBo SlackBuilds & sbotools Integration Engine](#engine-9-sbo-slackbuilds--sbotools-integration-engine)
   - [Engine 10: Real-Time System Tray Telemetry & Notifications](#engine-10-real-time-system-tray-telemetry--notifications)
   - [Engine 11: Internationalization & Fallback Engine (i18n)](#engine-11-internationalization--fallback-engine-i18n)
   - [Engine 12: Documentation & Groff PDF / QR Export Engine](#engine-12-documentation--groff-pdf--qr-export-engine)
4. [4. Security, Sandboxing & Privilege Model](#4-security-sandboxing--privilege-model)
5. [5. Data Layout & State Management](#5-data-layout--state-management)
6. [6. Auditing, Transparency & Debugging](#6-auditing-transparency--debugging)

---

## 1. Philosophical Manifesto: Harmony with Slackware

> [!NOTE]
> ### 🧩 ELI5 — What is Slackware harmony and why do you care?
> Slackware is legendary for being clean, predictable, and indestructible. Our golden rule is that Slacky-Update must never behave like a reckless package manager that clobbers system files. We package everything as clean, native Slackware packages (`.txz`), never build software directly on your root filesystem, and always preserve your stock Slackware fallback kernels and bootloaders.

Slacky-Update was engineered with a strict guiding principle: **augment Slackware without ever violating its unix philosophy, package management integrity, or system initialization purity.**

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       SLACKWARE & SLACKY-UPDATE HARMONY                     │
├─────────────────────────────────────────────────────────────────────────────┤
│  SLACKWARE CORE LINUX (Canonical System of Record)                          │
│  ├── /var/log/packages/        (Native pkgtools database)                   │
│  ├── /etc/slackpkg/            (Official distribution mirrors)              │
│  ├── /etc/rc.d/                (BSD-style SysVinit scripts)                 │
│  └── /boot/vmlinuz-generic     (Official Slackware fallback kernels)        │
│                               ▲                                             │
│                               │ Strict Respect & Clean Boundaries           │
│                               ▼                                             │
│  SLACKY-UPDATE COMPANION LAYER (Zero-Destruction Augmentation)              │
│  ├── Isolated Builds          (Sandboxed in /tmp/slacky-build-XXXXXX)      │
│  ├── Isolated Workstation Apps (Contained in /opt/<app>/)                   │
│  ├── Non-Destructive Boot     (Limine + GRUB Coexistence Mode)              │
│  └── Pure Native Packaging    (100% native .txz with slack-desc & doinst)   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 100% Respect for Slackware Core
* **Native Tooling is Master**: Slacky-Update does not replace `pkgtools` (`installpkg`, `upgradepkg`, `removepkg`) or `slackpkg`. It acts as an orchestrator and companion around them.
* **No Foreign Package Managers**: No `apt`, `dnf`, or `pacman` binaries are ever installed or executed on the host system.
* **Canonical Logging**: Every package installed by Slacky-Update is registered in `/var/log/packages/` as a first-class citizen with standard `slack-desc` metadata.
* **BSD-Style SysVinit Integration**: All background services deploy standard `/etc/rc.d/rc.<service>` scripts with clean `chmod +x` / `chmod -x` semantics.

### The Zero-Rootfs Compilation Rule (Sandboxing)
> [!IMPORTANT]
> **Slacky-Update NEVER compiles, builds, or mutates packages directly on the host root filesystem (`/`).**

1. **Ephemeral Sandboxes**: Every compilation, archive extraction, and transmutation occurs inside an isolated scratch space: `/tmp/slacky-build-XXXXXX` (in RAM via tmpfs).
2. **Deterministic Staging**: Upstream files are organized into a strict root staging directory (`/tmp/package-name/`), permissions are normalized.
3. **Atomic Package Creation**: `makepkg -l y -c n /tmp/target-package.txz` generates a clean Slackware package archive.
4. **Standard Installation**: The resulting `.txz` is handed over to `upgradepkg --install-new`, guaranteeing complete tracking in `/var/log/packages/`.
5. **Guaranteed Sandbox Destruction**: POSIX signal traps (`trap cleanup INT TERM EXIT`) automatically wipe `/tmp/slacky-build-XXXXXX` even if an operation is aborted midway.

---

## 2. Master Architecture Overview

> [!NOTE]
> ### 🧩 ELI5 — What is the master architecture and why do you care?
> Think of Slacky-Update like a modular high-end stereo rack. Each component (the turbo downloader, the kernel manager, the graphics orchestrator, the bootloader manager) sits in its own dedicated chassis with its own isolated cables, so tuning your graphics card never interferes with your web browser or audio drivers.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          SLACKY-UPDATE SUBSYSTEMS                           │
├─────────────────────────────────────────────────────────────────────────────┤
│  CLI INTERFACE (bin/slacky-update)       TRAY APPLET (bin/slacky-update-tray)│
│  └── common.sh & check_backend.sh        └── PyQt5 Event Loop & D-Bus / XDG │
├─────────────────────────────────────────────────────────────────────────────┤
│  TRANSACTION & PACKAGE ORCHESTRATION                                        │
│  ├── Parallel Pre-fetcher (10 Streams)  ├── .new Config Reconciler          │
│  ├── Multi-Pass Resume Controller       └── AlienBOB Multilib Health Guard  │
├─────────────────────────────────────────────────────────────────────────────┤
│  GRAPHICS, COMPUTE & WORKSTATION SUBSYSTEMS                                 │
│  ├── NVIDIA CachyOS Master & DKMS       ├── AMD ROCm / HIP Creator Toolkit  │
│  ├── VRAM Booster (615+ Preserver)      └── Underpants Gnomes App-Bundler   │
├─────────────────────────────────────────────────────────────────────────────┤
│  KERNEL & BOOTLOADER INFRASTRUCTURE                                         │
│  ├── CachyOS Kernel & CPU Tiering       ├── Limine Two-Zone Generator       │
│  ├── Dracut Hardware Guard (lib64)      └── sbctl / MOK Secure Boot Armor   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. The 12 Internal Engines: Detailed Breakdown

> [!NOTE]
> ### 🧩 ELI5 — What are the 12 engines and why do you care?
> Under the hood, Slacky-Update runs 12 specialized robotic engines, each laser-focused on one job: one downloads at lightning speed, one tunes your CPU instructions, one maintains your GPU drivers, and one ensures your PC always boots. Below is the full engineering breakdown of each engine.

---

### Engine 1: Core Orchestration & Lifecycle Controller
* **Source Files**: `bin/slacky-update`, `lib/common.sh`, `lib/mod_packages.sh`
* **Role**: Coordinates CLI argument parsing, transaction sequencing, `slackpkg` integration, and `.new` configuration file reconciliation.

---

### Engine 2: 10-Worker Asynchronous Turbo Pre-Fetcher
* **Source File**: `lib/mod_packages.sh`
* **Role**: Spawns 10 concurrent `curl` download workers using HTTP range resume (`-C -`) to pre-populate `/var/cache/packages/` before package installation starts.

---

### Engine 3: Sandboxed Transmutation & App-Bundle Engine
* **Source File**: `lib/mod_gaming.sh`
* **Role**: Transmutes upstream `.pkg.tar.zst` packages into native `.txz` archives with GPG signature validation and `/opt/<app>/` directory isolation.

---

### Engine 4: CachyOS Kernel Lifecycle & CPU Microarchitecture
* **Source File**: `lib/mod_kernel.sh`
* **Role**: Inspects host CPU features (x86_64_v4, v3, v2) and deploys optimized BORE/LTS kernels with a deterministic 2-kernel retention policy.

---

### Engine 5: NVIDIA Driver & DKMS Pipeline
* **Source File**: `lib/mod_nvidia.sh`
* **Role**: Deploys pre-compiled modules for CachyOS kernels, DKMS for standard Slackware kernels, purges stale modules, and aligns 32-bit multilib drivers.

---

### Engine 6: System Performance, Memory Architecture & 1M Resource Limits
* **Source File**: `lib/mod_tweaks.sh`
* **Role**: Applies 1 million file descriptor limits, PipeWire realtime priority (`rtprio 95`), Transparent HugePages (`madvise + defer`), and TCP BBR.

---

### Engine 7: AMD ROCm & HIP Compute Engine
* **Source File**: `lib/mod_rocm.sh`
* **Role**: Deploys full ROCm OpenCL/HIP compute runtimes for DaVinci Resolve Studio and purges conflicting Mesa OpenCL libraries.

---

### Engine 8: Limine Two-Zone & Cryptographic Armor Engine
* **Source Files**: `lib/mod_limine.sh`, `lib/mod_secureboot.sh`
* **Role**: Generates `/boot/limine.conf` preserving Zone A (user settings) while atomically recalculating Zone B (kernels, BLAKE2B hashes, Snapper snapshots, and `sbctl` signing).

---

### Engine 9: SBo SlackBuilds & `sbotools` Integration Engine
* **Source File**: `lib/mod_sbo.sh`
* **Role**: Auto-routes recipes to Ponce's git repository on `-current` or standard SBo on `15.0`, enforces `JOBS=$(nproc)`, and provides 25 curated recipes.

---

### Engine 10: Real-Time System Tray Telemetry & Notifications
* **Source Files**: `bin/slacky-update-tray`, `lib/check_backend.sh`
* **Role**: Lightweight PyQt5 background monitor (~18 MB RAM) polling weekly or on-demand, triggering D-Bus desktop notifications.

---

### Engine 11: Internationalization & Fallback Engine (i18n)
* **Source Files**: `lib/slacky_update_i18n.py`, `locales/*.json`
* **Role**: Zero-dependency Python localization across 24 languages with 100% key parity, fallbacks, and 90s Radical editions.

---

### Engine 12: Documentation & Groff PDF / QR Export Engine
* **Source File**: `lib/mod_docs.sh`
* **Role**: Compiles Markdown documentation into professional Groff/Troff PDFs in `~/Documents/` and starts an ephemeral Wi-Fi QR web server for mobile reading during BIOS setup.

---

## 4. Security, Sandboxing & Privilege Model

> [!NOTE]
> ### 🧩 ELI5 — What is the privilege model and why do you care?
> Security means never giving administrative power to programs that don't need it. The background monitor and update checks run as a regular user with zero privileges. Only when kernels, drivers, or bootloaders are being modified does the tool request elevated root permissions via sudo.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      SLACKY-UPDATE PRIVILEGE HIERARCHY                      │
├─────────────────────────────────────────────────────────────────────────────┤
│  USER SPACE (Standard UID - No Root Required)                               │
│  ├── slacky-update-tray   (Desktop Applet, D-Bus, GUI)                      │
│  ├── slacky-update --check (Read-only status inspection)                     │
│  └── ~/.config/slacky-update/config.json (User settings & language)         │
├─────────────────────────────────────────────────────────────────────────────┤
│  SANDBOX WORKSPACE (Ephemeral /tmp/slacky-build-XXXXXX, mode 0700)          │
│  ├── GPG signature validation with gpgv                                     │
│  ├── Archive unpacking and /opt staging                                     │
│  └── makepkg assembly of .txz package                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│  ROOT PRIVILEGE (Elevated via sudo for atomic transaction only)             │
│  ├── slackpkg upgrade-all & installpkg / upgradepkg                         │
│  ├── dracut initramfs generation & sbctl / MOK signing                      │
│  └── Atomic limine.conf / grub.cfg replacement                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 5. Data Layout & State Management

> [!NOTE]
> ### 🧩 ELI5 — What is the data layout and why do you care?
> This is the filesystem map showing where Slacky-Update keeps its data. Everything is organized according to standard Linux file hierarchy standards, so you always know where configuration files, keys, and backups are stored.

| Path | Purpose | Ownership / Permissions |
| :--- | :--- | :--- |
| `~/.config/slacky-update/config.json` | User settings, language override | User (0644) |
| `/var/cache/slacky-update/` | Download cache, SlackBuild recipes, update status | Root (0755) |
| `/var/cache/slacky-update/backup/` | Offline backup of stock kernels and drivers | Root (0700) |
| `/usr/share/slacky-update/keys/` | Machine Owner Keys (MOK) and vendor GPG keys | Root (0644) |
| `/usr/share/slacky-update/locales/` | 24 JSON language translation files | Root (0644) |
| `/usr/share/slacky-update/docs/` | System manuals, Survival Guide, Companion Guide | Root (0644) |
| `/etc/boot/hooks/post.d/` | Post-kernel installation hooks (Limine hash enrollment) | Root (0755) |

---

## 6. Auditing, Transparency & Debugging

> [!NOTE]
> ### 🧩 ELI5 — What is auditing and why do you care?
> Nothing in Slacky-Update is a mysterious black box. If you ever want to see exactly what the application is doing, you can read the shell scripts directly or run the diagnostic inspection commands listed below.

### Key Diagnostic Commands
```bash
# Execute a read-only update status check
slacky-update --check

# Test bash script syntax across all modules
for f in /usr/local/lib/slacky-update/*.sh; do bash -n "$f"; done

# Inspect active language translations
python3 /usr/share/slacky-update/lib/slacky_update_i18n.py CLI_TITLE

# Verify active NVIDIA VRAM Booster parameter status
cat /sys/module/nvidia/parameters/PreserveVideoMemoryAllocations

# Verify Limine configuration and enrolled BLAKE2B hashes
cat /boot/limine.conf

# Verify Secure Boot signing state
sbctl status
```

For disaster recovery procedures:
👉 **See [docs/TROUBLESHOOTING_GUIDE.md](docs/TROUBLESHOOTING_GUIDE.md)**  
For disk partitioning and ESP setup:
👉 **See [docs/LIMINE_SECUREBOOT_FIELD_GUIDE.md](docs/LIMINE_SECUREBOOT_FIELD_GUIDE.md)**

---

<div align="center">
<b>Slacky-Update Technical Companion Guide</b><br>
<i>Engineered for Transparency, Purity, and Performance on Slackware Linux</i><br>
<i>Canonical Source: <a href="https://github.com/TuxOfValhalla/slacky-update">GitHub</a> | Secondary Mirror: <a href="https://codeberg.org/TuxOfValhalla/slacky-update">Codeberg</a></i>
</div>
