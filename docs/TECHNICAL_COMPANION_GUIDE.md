# 🛠️ Slacky-Update Technical Companion Guide: Under the Hood & Engine Architecture
### *A Deep-Dive Architectural Whitepaper & Technical Reference for Slackware Linux 15+*
#### `v1.0 LTS` — *"Dark Star"* (Official Long-Term Support Release)

---

> [!IMPORTANT]
> **TARGET DISTRIBUTION REQUIREMENT & VERSION MANDATE**  
> **Slacky-Update is engineered strictly for Slackware 15+ (`slackware-current` / `Slackware 16 alpha`).**  
> It is **NOT** compatible with or supported on legacy **Slackware 15.0 (stable)**. Legacy 15.0 systems feature older core packages, toolchains, and shared libraries (such as older glibc, GCC, Wayland/Mesa, PipeWire, and kernel headers) that cause package and soname conflicts which cannot be safely detected or resolved. Running Slacky-Update on Slackware 15.0 is unsupported. Users on Slackware 15.0 must migrate to `slackware-current` before using this suite.

> [!CAUTION]
> **COMPREHENSIVE TESTING, LIABILITY & USE-AT-YOUR-OWN-RISK DISCLAIMER**  
> * **Hardware Testing & Verification:** Slacky-Update has been extensively verified and field-tested on bare-metal workstations with dry-run/simulated test passes across diverse build environments. However, **this in no way guarantees that it will operate seamlessly or without anomalies on your specific hardware configuration.**
> * **100% User Responsibility:** Slacky-Update executes deep, low-level modifications to foundational system components. **All installation, upgrades, and system modifications are performed 100% at your own discretion and risk.**
> * **No Liability for Data Loss:** The authors, maintainers, and contributors assume **no liability, warranty, or responsibility** for system malfunctions, unbootable states, hardware quirks, or loss of personal data.
> * **Mandatory Backups:** Always maintain current, tested backups of your personal data (`/home`, configuration files, and boot partitions) and keep a bootable Slackware Live-USB accessible before performing upgrades or modifying bootloaders.
> * **Bug Reporting & Support Policy:** If you encounter bugs, regressions, or hardware edge-cases, please report them on [GitHub Issues](https://github.com/TuxOfValhalla/slacky-update/issues) so they can be addressed. Beyond this documentation, no individual customer support, warranties, or service level agreements are offered.

---

## 📑 Table of Contents
1. [Philosophical Manifesto: The Sacred Slackware Base & The Five Pillars](#1-philosophical-manifesto-the-sacred-slackware-base--the-five-pillars)
   - [The Sacred Slackware Base System](#the-sacred-slackware-base-system)
   - [The Five Engineering Pillars](#the-five-engineering-pillars)
   - [The Zero-Rootfs Compilation Rule (Sandboxing)](#the-zero-rootfs-compilation-rule-sandboxing)
   - [Coexistence vs. Replacement](#coexistence-vs-replacement)
2. [Master Architecture Overview](#2-master-architecture-overview)
3. [The Master Internal Engines: Detailed Breakdown](#3-the-master-internal-engines-detailed-breakdown)
   - [Engine 1: Core Orchestration, In-Flight Transaction Armor & Lifecycle Controller](#engine-1-core-orchestration-in-flight-transaction-armor--lifecycle-controller)
   - [Engine 2: Pure Python Standard Library TUI Engine](#engine-2-pure-python-standard-library-tui-engine)
   - [Engine 3: 10-Worker Asynchronous Turbo Pre-Fetcher](#engine-3-10-worker-asynchronous-turbo-pre-fetcher)
   - [Engine 4: Underpants Gnomes Transmutation & Host Sovereignty Engine](#engine-4-underpants-gnomes-transmutation--host-sovereignty-engine)
   - [Engine 5: CachyOS Kernel Lifecycle, Multi-Flavor & CPU Microarchitecture](#engine-5-cachyos-kernel-lifecycle-multi-flavor--cpu-microarchitecture)
   - [Engine 6: NVIDIA Driver & DKMS Pipeline](#engine-6-nvidia-driver--dkms-pipeline)
   - [Engine 7: System Performance, Memory Architecture & 9 Granular Tweaks](#engine-7-system-performance-memory-architecture--9-granular-tweaks)
   - [Engine 8: FastBoot & Turbo Shutdown Acceleration Engine](#engine-8-fastboot--turbo-shutdown-acceleration-engine)
   - [Engine 9: AMD ROCm & HIP Compute Engine](#engine-9-amd-rocm--hip-compute-engine)
   - [Engine 10: Limine Two-Zone & Guided Secure Boot Engine](#engine-10-limine-two-zone--guided-secure-boot-engine)
   - [Engine 11: SBo SlackBuilds & sbotools Integration Engine](#engine-11-sbo-slackbuilds--sbotools-integration-engine)
   - [Engine 12: Real-Time System Tray Telemetry & Notifications](#engine-12-real-time-system-tray-telemetry--notifications)
   - [Engine 13: Internationalization & Fallback Engine (24 Locales)](#engine-13-internationalization--fallback-engine-24-locales)
   - [Engine 14: Documentation & Groff PDF / QR Export Engine](#engine-14-documentation--groff-pdf--qr-export-engine)
   - [Engine 15: Universal HiDPI & Wayland Scaling Engine](#engine-15-universal-hidpi--wayland-scaling-engine)
   - [Engine 16: Fast-Race Chaotic-AUR Probing & Self-Healing 404 Engine](#engine-16-fast-race-chaotic-aur-probing--self-healing-404-engine)
   - [Engine 17: Gaming Overlay TrueType Compatibility Mesh](#engine-17-gaming-overlay-truetype-compatibility-mesh)
4. [Security, Sandboxing & Privilege Model](#4-security-sandboxing--privilege-model)
5. [Data Layout & State Management](#5-data-layout--state-management)
6. [Auditing, Transparency & Debugging](#6-auditing-transparency--debugging)

---

## 1. Philosophical Manifesto: The Sacred Slackware Base & The Five Pillars

> [!NOTE]
> ### 🧩 ELI5 — What is Slackware harmony and why do you care?
> Slackware is legendary for being clean, predictable, and indestructible. Our golden rule is that Slacky-Update must never behave like a reckless modernization script that clobbers system files. We package everything as clean, native Slackware packages (`.txz`), never build software directly on your root filesystem, and always preserve your stock Slackware fallback kernels and bootloaders.

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
│  ├── Host Sovereignty Shield  (/opt/underpants/ with private RPATH)         │
│  ├── Non-Destructive Boot     (Limine + GRUB Coexistence Mode)              │
│  └── Pure Native Packaging    (100% native .txz with slack-desc & doinst)   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 🏛️ The Sacred Slackware Base System
* **Native Tooling is Master**: Slacky-Update does not replace `pkgtools` (`installpkg`, `upgradepkg`, `removepkg`) or `slackpkg`. It acts as an orchestrator and companion around them.
* **No Foreign Package Managers**: No `apt`, `dnf`, or `pacman` binaries are ever installed or executed on the host system.
* **Canonical Logging**: Every package installed by Slacky-Update is registered in `/var/log/packages/` as a first-class citizen with standard `slack-desc` metadata.
* **BSD-Style SysVinit Integration**: All background services deploy standard `/etc/rc.d/rc.<service>` scripts with clean `chmod +x` / `chmod -x` semantics.
* **Preserved Stock Fallbacks**: Official Slackware kernels (`vmlinuz-generic`, `vmlinuz-huge`), stock initrds, and default bootloaders (GRUB, ELILO) are preserved untouched so recovery is always a reboot away.

### 🌟 The Five Engineering Pillars
Every feature, routine, and interface in Slacky-Update is continuously measured against five strict standards:
1. **⚡ Speed:** Multi-core parallel zstd `-1 -T0` dracut decompression (<20ms boot), NVMe direct I/O hardware bypass (`none` scheduler), 10GB persistent shader disk cache, and instant sub-millisecond TUI responsiveness.
2. **🛋️ Comfort:** Automated ChangeLog tracking, background tray telemetry, dynamic terminal adaptation, and native mouse text selection for effortless clipboard sharing with LLMs.
3. **🛡️ Safety:** In-flight signal traps (`trap '' INT QUIT TSTP`) preventing broken states midway, non-destructive boot coexistence (GRUB/ELILO preserved), active kernel armor (`[ACTIVE - CANNOT REMOVE]`), and Btrfs Snapper snapshots.
4. **🎨 UI Design:** Clean Dark Star aesthetics, absolute cursor row positioning (`\033[{row};1H\033[2K`) eliminating staircase defects, dynamic multi-column package status, and intuitive visual hierarchy.
5. **🤝 Ease of Use:** 1-line automated installs, guided Secure Boot setup, universal `(ESC)` navigation across all menus, and clear human-readable confirmation prompts.

### The Zero-Rootfs Compilation Rule (Sandboxing)
> [!IMPORTANT]
> **Slacky-Update NEVER compiles, builds, or mutates packages directly on the host root filesystem (`/`).**

1. **Ephemeral Sandboxes**: Every compilation, archive extraction, and transmutation occurs inside an isolated scratch space: `/tmp/slacky-build-XXXXXX` (in RAM via tmpfs).
2. **Deterministic Staging**: Upstream files are organized into a strict root staging directory (`/tmp/package-name/`), permissions are normalized.
3. **Atomic Package Creation**: `makepkg -l y -c n /tmp/target-package.txz` generates a clean Slackware package archive.
4. **Standard Installation**: The resulting `.txz` is handed over to `upgradepkg --install-new`, guaranteeing complete tracking in `/var/log/packages/`.
5. **Guaranteed Sandbox Destruction**: POSIX signal traps (`trap cleanup INT TERM EXIT`) automatically wipe `/tmp/slacky-build-XXXXXX` even if an operation is aborted midway.

### Coexistence vs. Replacement
Slacky-Update operates strictly on a model of non-destructive coexistence rather than wholesale replacement:
* **Dual Bootloader Coexistence:** Limine is deployed alongside existing bootloaders (GRUB, ELILO) without overwriting NVRAM entries or destroying configuration files.
* **Kernel Preservation:** Official Slackware kernels (`vmlinuz-generic`, `vmlinuz-huge`) and stock initramfs images are permanently retained. High-performance CachyOS kernels live alongside native kernels.
* **Workstation Isolation:** Third-party applications and runtime dependencies reside in `/opt/<app>/` and `/opt/underpants/`, guaranteeing zero conflict with host system libraries in `/lib64` and `/usr/lib64`.

---

## 2. Master Architecture Overview

> [!NOTE]
> ### 🧩 ELI5 — What is the master architecture and why do you care?
> Think of Slacky-Update like a modular high-end stereo rack. Each component (the turbo downloader, the TUI engine, the kernel manager, the graphics orchestrator, the bootloader manager) sits in its own dedicated chassis with its own isolated cables, so tuning your graphics card never interferes with your web browser or audio drivers.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          SLACKY-UPDATE SUBSYSTEMS                           │
├─────────────────────────────────────────────────────────────────────────────┤
│  CLI INTERFACE (bin/slacky-update)       TRAY APPLET (bin/slacky-update-tray)│
│  └── common.sh & check_backend.sh        └── PyQt6 Event Loop & D-Bus / XDG │
├─────────────────────────────────────────────────────────────────────────────┤
│  TUI INTERACTION ENGINE (lib/slacky_tui.py)                                 │
│  ├── Absolute Cursor Addressing          ├── Dynamic Screen Budgeting       │
│  ├── Native Mouse Selection for LLMs     └── Universal (ESC) Navigation     │
├─────────────────────────────────────────────────────────────────────────────┤
│  TRANSACTION & PACKAGE ORCHESTRATION                                        │
│  ├── Parallel Pre-fetcher (10 Streams)  ├── In-Flight Signal Armor (SIGINT) │
│  ├── Multi-Pass Resume Controller       └── .new Config Reconciler          │
├─────────────────────────────────────────────────────────────────────────────┤
│  GRAPHICS, COMPUTE & WORKSTATION SUBSYSTEMS                                 │
│  ├── NVIDIA CachyOS Master & DKMS       ├── AMD ROCm / HIP Creator Toolkit  │
│  ├── 10GB Shader Cache & VRAM Preserver └── Underpants Gnomes App-Bundler   │
├─────────────────────────────────────────────────────────────────────────────┤
│  KERNEL & BOOTLOADER INFRASTRUCTURE                                         │
│  ├── CachyOS Kernel & CPU Tiering       ├── Limine Two-Zone Generator       │
│  ├── Dracut FastBoot (-1 -T0 zstd)      └── Guided MOK Secure Boot Engine   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. The Master Internal Engines: Detailed Breakdown

> [!NOTE]
> ### 🧩 ELI5 — What are the engines and why do you care?
> Under the hood, Slacky-Update runs specialized robotic engines, each laser-focused on one job: one downloads at lightning speed, one renders menus without flicker, one tunes your CPU instructions, one maintains your GPU drivers, and one ensures your PC always boots. Below is the full engineering breakdown of each engine.

---

### Engine 1: Core Orchestration, In-Flight Transaction Armor & Lifecycle Controller
* **Source Files**: `bin/slacky-update`, `lib/common.sh`, `lib/mod_packages.sh`
* **Role**: Coordinates CLI argument parsing, transaction sequencing, `slackpkg` integration, and `.new` configuration file reconciliation.
* **In-Flight Transaction Armor**: During package extraction, kernel generation, or initramfs builds, POSIX traps temporarily ignore interrupt signals (`trap '' INT QUIT TSTP`). This prevents catastrophic half-installed kernel or library states if a user accidentally hits `Ctrl+C`.
* **TTY Input Purging**: Flushes residual unread keypresses (`tcflush`) before and after transactions to prevent phantom keystrokes from spilling into subsequent menus.

---

### Engine 2: Pure Python Standard Library TUI Engine
* **Source File**: `lib/slacky_tui.py`
* **Role**: Renders interactive single-select and multi-select checklist menus with zero third-party dependencies (Python standard library only: `sys`, `termios`, `tty`, `os`, `signal`, `shutil`).
* **Absolute Cursor Addressing**: Employs `\033[{row};1H\033[2K` row-by-row updates instead of relative cursor jumps, completely eliminating terminal "staircase" tearing across resizes.
* **Dynamic Screen Height Budgeting**: Reads terminal rows and columns via `shutil.get_terminal_size()`, reserving exact line allowances for headers, menu items, action docks, and status grids.
* **Native Mouse Text Selection for LLMs**: Avoids capturing mouse reporting events (`\033[?1000h`), leaving the terminal emulator's native drag-to-select and copy-to-clipboard functionality 100% active for instant clipboard sharing with LLM coding agents.
* **Universal (ESC) Navigation**: Explicitly maps the Escape key (`\x1b`) to return to previous menus or exit cleanly.

---

### Engine 3: 10-Worker Asynchronous Turbo Pre-Fetcher
* **Source File**: `lib/mod_packages.sh`
* **Role**: Spawns 10 concurrent `curl` download workers using HTTP range resume (`-C -`) to pre-populate `/var/cache/slacky-update/packages/` before package installation starts.
* **Network Saturation**: Maximizes high-bandwidth connections by saturating gigabit pipes during the pre-fetch phase so `pkgtools` operations run entirely from local NVMe storage.

---

### Engine 4: Underpants Gnomes Transmutation & Host Sovereignty Engine
* **Source Files**: `bin/gnomes`, `lib/gnomes_pacman.py`, `lib/mod_gaming.sh`
* **Role**: In-memory pure Python streaming engine (`lib/gnomes_pacman.py`) that downloads upstream Arch Linux, CachyOS, and Chaotic-AUR package archives (`.pkg.tar.zst`), decompresses them directly in RAM with `zstandard`, and repackages them into authentic namespaced Slackware `.txz` packages (`underpants-*.txz`). Zero foreign package manager binaries (`pacman`, `apt`, `dnf`, `libalpm`) are installed or executed on the host.
* **Host Sovereignty Shielding**: Installs binary runtimes and shared objects into `/opt/underpants/` and `/opt/<app>/`, setting explicit `RPATH`/`RUNPATH` binaries so host system libraries (`/lib64`, `/usr/lib64`, `glibc`, PAM) are 100% shielded and sovereign, never contaminated or overridden.
* **Canonical Registration & Protection**: Every transmuted package is installed via `upgradepkg --install-new` and logs cleanly under `/var/log/packages/underpants-*` for clean removal via standard `removepkg` (or `gnomes -R`). Native Slackware base packages are 100% shielded and never overwritten.

---

### Engine 5: CachyOS Kernel Lifecycle, Multi-Flavor & CPU Microarchitecture
* **Source Files**: `lib/mod_kernel.sh`, `lib/mod_limine.sh`
* **Role**: Inspects host CPU features (x86_64_v4, v3, v2) and deploys optimized CachyOS kernels across 10 scheduler flavors (`standard`, `bore`, `lto`, `eevdf`, `bmq`, `deckify`, `rt-bore`, `rc`, `lts`, `zen`).
* **Active Kernel Armor**: Identifies the currently booted kernel (`uname -r`) and protects it with `[ACTIVE - CANNOT REMOVE]` badges to ensure a user never deletes their live operating kernel.
* **Multi-Kernel DKMS**: Rebuilds third-party kernel modules (NVIDIA, ZFS, OpenRGB, VirtualBox) automatically across all installed kernel versions.

---

### Engine 6: NVIDIA Driver & DKMS Pipeline
* **Source File**: `lib/mod_nvidia.sh`
* **Role**: Deploys pre-compiled modules for CachyOS kernels, DKMS for standard Slackware kernels, purges stale modules, and aligns 32-bit multilib drivers with strict DKMS collision shielding.
* **VRAM Booster & Preserver**: Enforces `nvidia.NVreg_PreserveVideoMemoryAllocations=1` and hooks systemd/SysVinit suspend-resume scripts to preserve VRAM state across sleep cycles.

---

### Engine 7: System Performance, Memory Architecture & 9 Granular Tweaks
* **Source File**: `lib/mod_tweaks.sh`
* **Role**: Provides 9 independently toggleable and fully reversible performance optimizations:
  1. **1 Million File Descriptors**: Eliminates `EMFILE` limits for Wine, Proton, and ESync/FSync.
  2. **THP & Memory Tuning**: Enforces `madvise` with deferred defragmentation (`defer`), sets `max_map_count=2147483642`, and lowers `swappiness=10`.
  3. **TCP BBR Congestion Control**: Replaces Cubic with Google BBR and Fair Queuing (`fq`) for lower network bufferbloat.
  4. **NTSYNC Gaming Synchronization**: Sets udev permissions (`0666`) on `/dev/ntsync` for ultra-low latency Wine threading.
  5. **Gamepad & Controller Forcefield**: Installs universal udev rules for DualSense, Xbox, Switch Pro, and Steam Deck controllers.
  6. **Turbo Boot & Fast Shutdown**: Strips legacy SysVinit delays and applies parallel zstd level 1 dracut initramfs generation.
  7. **NVMe Direct I/O Scheduler (`none`)**: Bypasses CPU-bound software I/O queues for hardware NVMe controllers.
  8. **10GB Shader Disk Cache**: Expands NVIDIA OpenGL/Vulkan shader cache to 10GB (`__GL_SHADER_DISK_CACHE_SIZE=10737418240`), eliminating stutter.
  9. **PipeWire 256 Low-Latency Audio**: Drops audio buffer quantum from 1024 to 256 (5.3ms latency) via `/etc/pipewire/pipewire.conf.d/` drop-in.

---

### Engine 8: FastBoot & Turbo Shutdown Acceleration Engine
* **Source Files**: `lib/mod_tweaks.sh`, `/etc/rc.d/rc.6`
* **Role**: Shaves 10 to 15 seconds off system boot and shutdown:
  - **PCMCIA & Inactive NFS Removal**: Disables legacy PCMCIA probes (5-second sleep) and skips unmounted NFS unmount loops.
  - **NetworkManager Sovereignty**: Prevents redundant `rc.inet1` DHCP timeout blocking when NetworkManager manages interfaces.
  - **tmpfs `/tmp`**: Mounts `/tmp` in RAM for instantaneous ephemeral I/O.
  - **Dracut Multi-Core Compression**: Enforces `zstd -1 -T0` parallel compression, reducing kernel decompression time to under 20ms.

---

### Engine 9: AMD ROCm & HIP Compute Engine
* **Source File**: `lib/mod_rocm.sh`
* **Role**: Deploys full ROCm OpenCL/HIP compute runtimes for DaVinci Resolve Studio and Blender, cleanly isolating compute libraries from conflicting Mesa OpenCL drivers.

---

### Engine 10: Limine Two-Zone & Guided Secure Boot Engine
* **Source Files**: `lib/mod_limine.sh`, `lib/mod_secureboot.sh`
* **Role**: Generates `/boot/limine.conf` preserving Zone A (user custom entries) while atomically recalculating Zone B (kernels, BLAKE2B cryptographic hashes, Snapper snapshots, and Secure Boot signing).
* **Guided MOK Setup**: Provides clear, step-by-step guidance for enrolling custom Machine Owner Keys (`sbctl` / `mokutil`) in UEFI firmware. Once enrolled, all subsequent kernel updates and initramfs builds are signed **100% automatically**.
* **Split-Lock Mitigation Toggle**: Includes a dedicated CMDLINE toggle for `split_lock_mitigate=0` to prevent micro-stutters in heavy gaming workloads.

---

### Engine 11: SBo SlackBuilds & `sbotools` Integration Engine
* **Source File**: `lib/mod_sbo.sh`
* **Role**: Auto-routes recipes to Ponce's git repository on `-current` or standard SBo on `15.0`, enforces `JOBS=$(nproc)`, and provides curated workstation builds.

---

### Engine 12: Real-Time System Tray Telemetry & Notifications
* **Source Files**: `bin/slacky-update-tray`, `lib/slacky-update-tray`, `lib/check_backend.sh`
* **Role**: Lightweight PyQt6 background monitor polling on-demand and on schedule, featuring cascading submenus for Underpants Gnomes (TUI/GUI) and triggering D-Bus desktop notifications.

---

### Engine 13: Internationalization & Fallback Engine (24 Locales)
* **Source Files**: `lib/slacky_update_i18n.py`, `locales/*.json`
* **Role**: High-performance multi-language translation engine providing 100% key parity across 24 global languages (262 keys each) with English fallback and 90s pop-culture Radical Editions.

---

### Engine 14: Documentation & Groff PDF / QR Export Engine
* **Source File**: `lib/mod_docs.sh`
* **Role**: Compiles Markdown documentation into professional Groff/Troff PDFs in `~/Documents/` and starts an ephemeral Wi-Fi QR web server for mobile reading during BIOS setup.

---

### Engine 15: Universal HiDPI & Wayland Scaling Engine
* **Source Files**: `assets/profile.d/slacky-hidpi.sh`, `assets/profile.d/slacky-hidpi.csh`, `desktop/slacky-update.desktop`, `bin/slacky-update`, `lib/slacky-update-tray`
* **Role**: Configures system-wide Qt5, Qt6, and GTK environment defaults for modern high-resolution displays (4K/1440p) under Wayland and X11 sessions (`QT_ENABLE_HIGHDPI_SCALING=1`, `QT_SCALE_FACTOR_ROUNDING_POLICY=PassThrough`, `GDK_BACKEND="wayland,x11,*"`).

---

### Engine 16: Fast-Race Chaotic-AUR Probing & Self-Healing 404 Engine
* **Source Files**: `lib/mod_gaming.sh`, `lib/gnomes_pacman.py`
* **Role**: Parallel, non-blocking latency evaluator and repository integrity recovery engine:
  - **Fast-Race Mirror Benchmarking**: Evaluates global mirrors simultaneously using `concurrent.futures.as_completed` with aggressive 750ms cutoffs and sub-55ms short-circuit instant selection.
  - **Self-Healing 404 Recovery**: Intercepts upstream mirror 404 errors when upstream package versions bump, automatically re-syncs database metadata, and retries in-flight.

---

### Engine 17: Gaming Overlay TrueType Compatibility Mesh
* **Source Files**: `lib/mod_gaming.sh`
* **Role**: Dynamic font indexer, symlinking orchestrator, and parser validation mesh for Vulkan/OpenGL gaming overlays (MangoHud, GOverlay), eliminating font rendering errors in Dear ImGui `stb_truetype` font rasterizers.

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
| `/usr/share/slacky-update/locales/` | 24 JSON language translation files (262 keys each) | Root (0644) |
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
👉 **See [docs/TROUBLESHOOTING_GUIDE.md](TROUBLESHOOTING_GUIDE.md)**  
For disk partitioning and ESP setup:
👉 **See [docs/LIMINE_SECUREBOOT_FIELD_GUIDE.md](LIMINE_SECUREBOOT_FIELD_GUIDE.md)**

---

<div align="center">
<b>Slacky-Update Technical Companion Guide</b><br>
<i>Engineered for Transparency, Purity, and Performance on Slackware Linux</i><br>
<i>Canonical Source: <a href="https://github.com/TuxOfValhalla/slacky-update">GitHub</a> | Secondary Mirror: <a href="https://codeberg.org/TuxOfValhalla/slacky-update">Codeberg</a></i>
</div>
