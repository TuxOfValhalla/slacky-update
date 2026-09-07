<div align="center">

# ⚡ SLACKY-UPDATE ⚡
### *The Most Tubular System Update Station, Kernel Time Machine, SBo SlackBuild Hub & Driver Mojo Command Center for Slackware Linux*

[![Slackware -current](https://img.shields.io/badge/Slackware--current-15.0%2B-blue?style=for-the-badge&logo=slackware&logoColor=white)](http://www.slackware.com/)
[![Release](https://img.shields.io/badge/Release-v0.9%20'The%20Fat%20Lady'-purple?style=for-the-badge)](https://github.com/TuxOfValhalla/slacky-update/releases)
[![Mirror: Codeberg](https://img.shields.io/badge/Mirror-Codeberg-2185d0?style=for-the-badge&logo=codeberg&logoColor=white)](https://codeberg.org/TuxOfValhalla/slacky-update)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-green.svg?style=for-the-badge)](LICENSE)
[![Zero-Binary](https://img.shields.io/badge/Architecture-100%25%20Pure%20Source%20(Zero--Binary)-brightgreen?style=for-the-badge)](lib/)
[![Language](https://img.shields.io/badge/Locales-24%20Languages%20(148%20Keys)-yellow?style=for-the-badge)](locales/)
[![Stack](https://img.shields.io/badge/Stack-Bash%20%7C%20Python3%20%7C%20PyQt5-orange?style=for-the-badge)](bin/)

---

### *Party on, Wayne! / Party on, Garth!*
**Slacky-Update** is an all-in-one maintenance station, background system monitor, curated SlackBuild hub, and gaming/creator toolkit engineered specifically for **Slackware Linux (-current / 15.0+)**. 

*Canonical source: [GitHub](https://github.com/TuxOfValhalla/slacky-update) | Official European mirror: [Codeberg](https://codeberg.org/TuxOfValhalla/slacky-update)*

**Release v0.9 'The Fat Lady'** delivers a comprehensive feature set for power users, gamers, and content creators:
* **Turbo Multi-Stream Package Pre-fetcher:** 10 concurrent worker streams delivering warm-cache handoffs to `slackpkg` for 5–10× faster package download phases.
* **Curated SBo SlackBuilds Hub:** 25 pre-configured, tested SlackBuild recipes (including Wonder Unit Storyboarder, Serif Affinity Suite, DaVinci Resolve Studio, Unreal Engine 5, MangoHud, Gamescope, LACT, and OpenRGB) with automated recipe synchronization and Ponce -current routing.
* **Optional System & Gaming Tweaks Module:** Modular kernel and system tuning suite featuring process limits, memory/THP tuning, TCP BBR network congestion control, NTSYNC kernel synchronization, and 27 controller/gamepad udev rules with real-time status badges.
* **CachyOS Time Machine:** High-performance BORE / sched-ext kernel deployment with CPU microarchitecture tier detection (*znver4 / x86_64_v4*), reversible stock kernel removal, and intelligent GRUB priority management.
* **Hardware Graphics & Compute Stations:** NVIDIA branch selector (*Production 595.x, Feature 610.x, Legacy 580.x*) with DKMS and VA-API, plus an AMD ROCm / HIP creator toolkit with DaVinci Resolve FFmpeg/AAC export integration and Rusticl collision prevention.
* **Secure Boot MOK Forcefield:** 1-Click automated UEFI Secure Boot provisioning, Microsoft-signed shim and GRUB deployment, MOK key generation, and smart signature verification.
* **24 Multi-Lingual Locales:** Full internationalization with 100% key parity (148/148 keys) across 24 languages with instant desktop tray switching.

</div>

---

## 📸 Screenshots

| 🖥️ Interactive Terminal Command Center | 🔔 System Tray Monitor & Status Applet |
| :---: | :---: |
| ![Slacky-Update CLI Interface](assets/screenshots/04_interactive-CLI-interface.png) | ![Tray Icon](assets/screenshots/01_systray-applet-icon.png) |

---

## 🎮 Why Slacky-Update? (Engineered for Gamers & Dual-Booters)

### 🕹️ The Ultimate Rig for Linux Gaming
Slackware is legendary for its raw speed and UNIX purity, but modern gaming demands fast-moving graphics stacks and responsive kernel scheduling. Slacky-Update supercharges your gaming battlestation:
* **CachyOS High-Performance Kernels:** Deploy upstream CachyOS kernels featuring the **BORE (Burst-Oriented Response Enhancer)** or `sched-ext` schedulers, `futex2` / `fsync` patches for Proton/Wine, and `-O3` compilation for ultra-low latency and smooth 1% low frametimes.
* **CPU Microarchitecture Optimization:** Auto-detects your exact CPU tier (*znver4 / x86_64_v4 for AMD Zen 4/5 & Intel 12th–15th+ Gen*) to unlock full AVX-512 instruction set performance.
* **Bleeding-Edge GPU Drivers:** Switch seamlessly between NVIDIA driver branches (*Production 595.x, New Feature 610.x, or Legacy 580.x*) with one click for Day-1 game support, DLSS 3/4, and latest Vulkan extensions.
* **Proton & Flatpak Synchronization:** Keeps Flatpak gaming environments (Steam, Heroic, Lutris, MangoHud) locked in perfect sync with your host graphics drivers, eliminating the dreaded OpenGL/Vulkan runtime version mismatch.

### 🪟 Seamless Windows 11 Dual-Booting (Keep Secure Boot ON!)
Windows 11 strictly mandates **UEFI Secure Boot** (and TPM 2.0) for modern security and anti-cheat systems (like Riot Vanguard / Valorant / FACEIT). Traditionally on Slackware, running custom kernels or proprietary NVIDIA drivers with Secure Boot turned on was an exercise in frustration:
* **The Dual-Boot Dilemma:** Every kernel update broke NVIDIA modules, leaving users stranded with black screens unless they went into UEFI BIOS to disable Secure Boot (which broke Windows features).
* **The Slacky-Update Fix:** With the built-in **1-Click Secure Boot Setup & MOK Forcefield**, Microsoft-signed Shim, MokManager, signed GRUB, and your Machine Owner Keys (MOK) are configured automatically.
* **Zero BIOS Toggling:** Keep UEFI Secure Boot permanently **ENABLED** in firmware. Boot back and forth between Windows 11 and Slackware Linux without ever touching BIOS settings or compromising security!

---

## 🧠 Intelligent Hardware Detection (AMD, Intel & NVIDIA)

Slacky-Update features native hardware inspection (`probe_gpu_hardware`) via PCI device querying, making it universally compatible across all GPU vendors while eliminating the historic complexity of proprietary drivers:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      HARDWARE DETECTION & ADAPTATION                        │
├───────────────────┬─────────────────────────────────────────────────────────┤
│ AMD Radeon (RDNA) │ Native in-tree amdgpu KMS driver baked into Dracut.     │
│ & Intel Arc/Iris  │ Mesa Vulkan (RADV / ANV) runtimes synced automatically. │
├───────────────────┼─────────────────────────────────────────────────────────┤
│ NVIDIA GeForce    │ Full automated pipeline: DKMS build -> MOK signing     │
│ (RTX / GTX)       │ -> Dracut driver baking -> Flatpak GL synchronization.  │
├───────────────────┼─────────────────────────────────────────────────────────┤
│ Hybrid / Laptops  │ Dual detection (AMD/Intel iGPU + NVIDIA dGPU) with      │
│ (PRIME Offload)   │ comprehensive KMS driver inclusion for glitch-free DRM. │
└───────────────────┴─────────────────────────────────────────────────────────┘
```

* **AMD & Intel GPUs (Pure Out-of-the-Box Bliss):** For rigs running AMD Radeon (RDNA 1/2/3/4) or Intel Arc / Iris Xe graphics, Slacky-Update detects your open-source Mesa stack, automatically generates optimized Dracut images with the appropriate KMS modules (`amdgpu`, `i915`, `xe`), and manages your system with zero extra configuration.
* **NVIDIA GPUs (A Complete Cake-Walk):** What used to be a fragile multi-step nightmare on Slackware—installing .run files, compiling DKMS, generating MOK keys, signing kernel binaries, signing .ko modules, and configuring Dracut—is completely automated in a single atomic transaction.

---

## 🚀 Key Superpowers & Features

```
=============================================================================
                      ⚡ SLACKY-UPDATE COMMAND MATRIX ⚡
=============================================================================
 [1] Total System Party On!      --> Slackware + Flatpaks + SBo + MOK Armor
 [2] SBo SlackBuild & Gaming Hub --> 25 Curated Packages, Search & Tweaks
 [3] CachyOS Time Machine        --> CPU Tier Detect, Deploy & Manage Kernels
 [4] Nvidia & ROCm Stations      --> Branch Select (580/595/610), ROCm / HIP
 [5] Clean the Garage            --> Dual Kernel Retention & Artifact Purge
 [6] Secure Boot MOK Forcefield  --> 1-Click Setup, Shim Inject & Self-Heal
 [7] Babling                     --> 24 Multi-Lingual Locales (Tray menu)
=============================================================================
```

### 1. 🛡️ Total System Synchronization ("Party On!")
* **Turbo Multi-Stream Package Pre-fetch Engine:** Accelerates downloads with **10 concurrent parallel worker streams** (configurable via `SLACKY_PREFETCH_JOBS`), live terminal progress ticker (`[x/total] ✓ package.txz (size, speed)`), atomic `.part` downloads with resume support (`-C -`), pre-fetching for both `upgrade-all` and `install-new` packages, automatic `.asc` GPG signature pre-fetching, and strict repository path filtering (locking out unwanted `testing/` or `pasture/` trees). Delivers 100% warm-cache handoff to `slackpkg install-new` and `upgrade-all` without duplicate downloads (typically 5–10× faster package download phase).
* **Slackware Core Package Management:** Integrates seamlessly with Slackware's native `slackpkg` (`update`, `install-new`, `upgrade-all`).
* **SBo SlackBuilds Pipeline:** Automatically checks and updates all installed SBo SlackBuilds via `sbotools` (`sboupgrade --all`) in the same unified transaction.
* **Multi-Pass Resume Engine:** If `slackpkg`, `slackpkg+`, `pkgtools`, `glibc-solibs`, or `ca-certificates` self-upgrades and pauses the package transaction, Slacky-Update catches this in-session and prompts to resume immediately with the new toolchain—no crashes, no manual restarts!
* **Smart `.new` Configuration Reconciliation:** Scans `/etc/` after system upgrades and automatically categorizes `.new` files into 4 clear groups (New Configs, Identical Duplicates, Unmodified Defaults, and Custom User Configs) with 4 quick, respectful batch prompts—eliminating 95% of prompt fatigue!
* **Smart Reboot Evaluator:** Intelligently determines if core system packages (`glibc`, `plasma`, `nvidia`, or the active running kernel) were updated via temp-file comparison (`mktemp`), prompting for a reboot only when genuinely necessary, and closing the CLI window cleanly when done.
* **Flatpak Upgrades & NVIDIA GL Sync:** Upgrades all user and system Flatpaks, automatically inspecting and synchronizing required Flatpak NVIDIA GL runtimes (`org.freedesktop.Platform.GL*.nvidia-*`).
* **GitHub Self-Update Engine:** Real-time release verification with clean status line (`✓ Slacky-Update is up to date with GitHub (v0.9)`) and 1-click self-upgrade & reload.
* **Conditional Pipeline:** Intelligently snapshots installed packages and only rebuilds DKMS, Dracut initramfs, and signatures when kernel or driver packages actually change.

### 2. 🧰 Curated SBo SlackBuilds Hub (25 Tested Packages & `sbotools` Integration)
* **Intelligent Version Auto-Tuning:** Detects whether you run Slackware -current (`15.0+`) or stable `15.0`, automatically routing to Ponce's git tree (`current`) or standard SBo (`15.0`), with hardware thread detection (`JOBS=$(nproc)`) so compiling never chokes or fails.
* **1-Click sbotools Bootstrap:** If `sbotools` is missing, Slacky-Update offers automated bootstrap compilation and setup out of the box.
* **Interactive SBo Package Search:** Search thousands of SlackBuilds directly from the terminal (`sbofind`) and install them in real-time.
* **25 Curated Slacky-SlackBuilds Suite:** Pre-configured and tested recipes with auto-recipe cache synchronization directly into `/var/cache/slacky-update/slacky-slackbuilds`:
  * **Graphics & Art:** Wonder Unit Storyboarder (v2.1.0 with standalone `/usr/lib64/storyboarder/` wrapper), Serif Affinity Suite v3 (Photo, Designer, Publisher with automated Wine detection), Blender, FreeCAD, Inkscape, Gamescope, Goverlay, MangoHud.
  * **Gaming Launchers & Emulation:** Faugus Launcher, Heroic Games Launcher, Wine-Staging, Winetricks.
  * **Creation & Multimedia:** DaVinci Resolve Studio (with automated OpenCL/Rusticl conflict handling and plugins).
  * **Development & 3D:** Unreal Engine 5.
  * **Office:** SoftMaker FreeOffice 2024.
  * **System & Hardware Utilities:** Ananicy-CPP, GNOME Disk Utility, Grub-BTRFS, Snapper, LACT (AMD GPU Controller), OpenRGB, SpaceNavd, Spnavcfg, Libhandy, Libspnav.
* **Silent 7-Day Auto-Refresh:** Automatically refreshes the SBo tree snapshot in the background if older than 7 days, keeping build dependencies 100% fresh.

### 3. 🛠️ Optional System & Gaming Tweaks Module
Slacky-Update provides a dedicated, non-destructive tuning module accessible via `slacky-update --tweaks` or via the SlackBuilds & Tweaks menu. Each tweak area provides granular controls, live status inspection badges (`[ACTIVE]` / `[DISABLED]`), and 1-click apply/revert routines:
* **System & Process Limits:** Deploys `/etc/security/limits.d/99-gaming.conf` and tunes `fs.file-max` for 1,048,576 file descriptors and real-time scheduling priority (`rtprio 99`, `memlock unlimited`).
* **Memory & THP Tuning:** Tunes Transparent HugePages to `madvise`, elevates `vm.max_map_count` to `2147483642` (preventing crashes in modern games such as Star Citizen, DayZ, and Unreal Engine titles), sets `vm.swappiness` to `10`, and lowers `vm.vfs_cache_pressure` to `50`.
* **Network TCP BBR Congestion Control:** Configures Google's BBR TCP congestion control algorithm with modern queuing disciplines (`cake` or `fq`) to minimize network latency and packet bufferbloat.
* **NTSYNC Kernel Fast Synchronization:** Configures `/dev/ntsync` udev device access permissions and kernel module loading for high-performance Windows NT kernel synchronization in Wine/Proton.
* **Universal Controller & Gamepad Udev Rules:** Deploys 27 comprehensive udev rules (`/etc/udev/rules.d/70-gamepad-tweaks.rules` and `60-openhmd.rules`) providing plug-and-play user-space permissions for Xbox (360, One, Series X/S), PlayStation (DualShock 3/4, DualSense), Nintendo Switch (Pro Controller, Joy-Cons), Steam Controller, 8BitDo gamepads, Logitech controllers, Flight Sticks / HOTAS systems, and Racing Wheels.

### 4. 🏎️ CachyOS Time Machine (Kernel Engine)
* **Automatic CPU Tier Detection:** Identifies your CPU microarchitecture (*x86_64_v4 / znver4, x86_64_v3, x86_64_v2*) and pulls high-performance, optimized CachyOS Linux kernel binaries and headers directly from upstream Arch/CachyOS package repositories (*Standard, BORE, BORE-LTO, RC, and LTS flavors*).
* **Pure CachyOS Kernel Mode (100% Reversible):** When running CachyOS LTS alongside performance kernels, Slacky-Update offers the option to completely remove stock Slackware kernels (`kernel-generic`, `kernel-huge`, `kernel-modules`) to reclaim disk space while **safely preserving `kernel-headers`** for full build system compatibility. The entire process is 100% reversible with 1-click stock restoration!
* **Smart Bootloader "Top Dog" Priority:** Automatically sets the highest performance installed kernel as default top entry in GRUB, alongside intelligent CMDLINE deduplication and normalization.
* **Dual-Kernel Retention:** Safely keeps the **2 newest CachyOS kernels** plus your active running kernel, preventing `/boot` clutter.
* **Automatic Bootloader Registration:** Links kernels to GRUB (`/boot/grub/grub.cfg`) and Limine bootloader configurations automatically.

### 5. 🎮 Nvidia Mojo Station & AMD ROCm Creator Suite
* **CachyOS Complete NVIDIA Ecosystem:** Full automated packaging and deployment of upstream CachyOS packages: **64-bit Core Driver**, **32-bit Multilib** (`lib32-nvidia-utils`), **NVIDIA Settings** (`nvidia-settings`), **64-bit OpenCL** (`opencl-nvidia`), **32-bit OpenCL** (`lib32-opencl-nvidia`), and **VA-API Hardware Video Acceleration** driver (`libva-nvidia-driver` -> `/usr/lib64/dri/nvidia_drv_video.so` with `/etc/profile.d/nvidia-vaapi.sh`).
* **AMD ROCm / HIP Creator Toolkit:** Complete OpenCL & HIP compute runtimes (`rocm-core`, `rocm-opencl-runtime`, `rocm-hip-runtime`, `hsa-rocr`, `comgr`) with automatic **Mesa OpenCL & Rusticl purge & blacklisting** to prevent DaVinci Resolve crashes on Radeon hardware.
* **DaVinci Resolve Deliver Plugins:** Full integration of **FFmpeg Deliver Tab Encoder plugin** (`FFmpegEncoder.dvpipeline`) and **AAC audio export plugin** directly into DaVinci Resolve Studio for both AMD and NVIDIA rigs.
* **Wayland Memory Preservation:** Automatically deploys power management and video memory allocation preservation scripts to `/var/tmp` for glitch-free suspend/resume under Wayland.
* **Branch Selection:** Choose between **Legacy Mojo** (*580.x* - Pascal / GTX 10-series & older), **Production Mojo** (*595.x* - Modern RTX), and **New Feature Mojo** (*610.x* - Latest RTX series).
* **Hardware Architecture Safeguard:** Intelligently checks GPU capabilities. For legacy hardware like Pascal (GTX 1060/1070/1080), it automatically routes directly to the proprietary 580xx branch via DKMS.
* **DKMS Automated Rebuilds:** Automatically triggers and verifies DKMS compilation across all installed kernels on the system.
* **Instant Rebuild Mode:** Recompile and re-sign NVIDIA drivers for the active kernel in seconds.

### 6. ⚡ "JUST FIX MY DAMN SECURE BOOT!" (1-Click Ironclad Wizard)
* **One-Click Provisioning:** Deploys Microsoft-signed `shimx64.efi`, `mmx64.efi`, and Fedora-signed `grubx64.efi` to `/boot/efi/EFI/Slackware/`, creates dynamic early `grub.cfg` pointers, provisions MOK keypairs, bakes Dracut initramfs across all kernels, signs all binaries, and updates GRUB.
* **Smart Signature Verification:** Inspects module headers (`modinfo -F signer`) prior to extraction, skipping already-signed modules to accelerate update transactions.
* **Collision-Free Isolated Module Signing:** Module signing executes inside dedicated `/tmp/slacky-sign-XXXXXX` workspaces, preventing corrupted `.ko.zst` files, auto-purging uncompressed `.ko` duplicates, and auto-detecting the active MOK signer tool (`kmodsign` or `sign-file`).
* **Silent Self-Heal Guard:** Runs quietly in the background on every update. If an external package or accidental `grub-install` overwrites your signed EFI binaries or configuration, Self-Heal silently restores them!
* **Bundled OpenSSL 1.1 Compatibility:** Packages include bundled `libcrypto.so.1.1` and `libssl.so.1.1` compatibility libraries so `sbsign` and `mokutil` never fail on Slackware -current with OpenSSL 3.x.

### 7. ⚙️ Dracut Multilib Shield & Fail-Safe Initramfs
* **Dracut Multilib Shield (`00-multilib.conf`):** Automatically injects `--libdirs "/lib64 /usr/lib64 /usr/local/lib64"` and deploys `/etc/dracut.conf.d/00-multilib.conf` to block 32-bit multilib library collisions, ensuring pure 64-bit initramfs integrity.
* **Native Dracut Engine:** Explicitly iterates across all installed kernels in `/lib/modules/*` to generate complete, high-performance Dracut initramfs images (`/boot/initramfs-*.img`, 220+ MB) with baked-in GPU and storage drivers.
* **GRUB Preference Protection:** Automatically purges conflicting 11 MB `initrd-*.img` files created by Slackware's stock `mkinitrd` **only after** Dracut has verified successful generation, ensuring GRUB always boots the complete Dracut initramfs!
* **Legacy Fallback:** If Dracut is not installed, seamlessly falls back to standard Slackware `mkinitrd`.

### 8. 🧹 Clean the Garage (System Maintenance)
* **Slackware Stock Kernel Retention:** Keeps the **1 newest Slackware stock kernel** plus the active booted kernel, cleanly purging older versions, old module folders, and outdated initramfs files.
* **Cache Purge & Portability:** Cleans stale build directories in `/var/cache/slacky-update/` and runs `flatpak uninstall --unused`. All paths are 100% portable with zero hardcoded user directories.
* **Bootloader Sync:** Automatically runs `grub-mkconfig` to keep `/boot/grub/grub.cfg` pristine and free of ghost entries.

### 9. 💓 Dynamic System Tray Applet
* **Pulsing Desktop Notifications:** When updates are available, the tray icon pulses dynamically (100% ⇄ 80% size) synchronized with desktop notifications (KNotify/KDE) before settling back smoothly.
* **Discreet Scan Flow:** Manual updates trigger an instant checking icon without popup spam; returning quietly to green when 0 updates are found.
* **Direct Slack-builds Trigger:** Dedicated tray action to launch the interactive SlackBuilds & Tweaks hub in a terminal window.
* **Instant Action Menu:** Check updates on demand, view category breakdowns, launch terminal upgrades, or switch interface language on the fly.

---

## 🌍 Babling (24 Multi-Lingual Locales)

Slacky-Update includes full internationalization across **24 languages** with **100% key parity (148/148 keys)**.

Choose between radical **90's pop-culture theme** (*English* and *Norsk Bokmål*) or **dry, corporate, formal tone** across all languages:

| Language Code | Language Name | Tone / Style |
| :--- | :--- | :--- |
| `ar` | **العربية** | Standard formell (Fusha) |
| `en` | **English** | 90's Radical (Bill & Ted / TMNT) |
| `en-ca` | **English (Canada)** | Standard Canadian |
| `en-boring` | **Boring English** | Corporate / IT Sysadmin Formal |
| `nb` | **Norsk (Bokmål)** | 90-talls fest |
| `nb-boring` | **Kjedelig Norsk** | Tradisjonell formell |
| `nn` | **Norsk (Nynorsk)** | Standard formelt |
| `da` | **Dansk** | Standard formelt |
| `de` | **Deutsch** | Standard formell |
| `es` | **Español** | Estándar formal |
| `fi` | **Suomi** | Virallinen standardi |
| `fr` | **Français** | Standard formel |
| `hi` | **हिन्दी** | मानक औपचारिक |
| `is` | **Íslenska** | Hefðbundið formlegt |
| `it` | **Italiano** | Standard formale |
| `ja` | **日本語** | 標準ビジネス |
| `ko` | **한국어** | 표준 포멀 |
| `nl` | **Nederlands** | Standaard zakelijk |
| `pl` | **Polski** | Standardowy formalny |
| `pt` | **Português** | Padrão formal |
| `ru` | **Русский** | Официально-деловой |
| `se` | **Davvisámegiella** | Standárda formála |
| `sv` | **Svenska** | Standard formellt |
| `zh` | **中文** | 标准正式 |

*Switch languages on the fly through the **System Tray Context Menu** (`Babling` / `Language Selection`) or via CLI: `slacky-update --lang <code`.*

---

## 📦 Installation & Setup

### Building the Slackware Package (.txz)
Slacky-Update is built natively using the official `slacky-update.SlackBuild`:

```bash
# 1. Clone the repository
git clone https://github.com/tuxofvalhalla/slacky-update.git
cd slacky-update

# 2. Build the package
sudo bash slackbuild/slacky-update.SlackBuild

# 3. Install / Upgrade the package (wildcard automatically selects latest build)
sudo upgradepkg --install-new --reinstall slacky-update-*.txz
```

#### ⚡ Quick Install One-Liner
```bash
git clone https://github.com/tuxofvalhalla/slacky-update.git && cd slacky-update && sudo bash slackbuild/slacky-update.SlackBuild && sudo upgradepkg --install-new --reinstall slacky-update-*.txz && slacky-update-tray &
```

> **Autostart:** The background tray monitor is automatically placed in `/etc/xdg/autostart/` and starts seamlessly upon every desktop login (KDE Plasma, XFCE, GNOME, etc.). Running `slacky-update-tray &` starts it immediately in your current active session.

---

## 💻 Usage & Command Line Interface

```bash
# Launch interactive terminal command center
slacky-update

# Open SlackBuilds & Gaming Hub directly
slacky-update --slackbuilds
# or:
slacky-update -s

# Open System & Gaming Tweaks module directly
slacky-update --tweaks
# or:
slacky-update -t

# Run full unattended system update transaction
slacky-update -y
# or:
slacky-update --non-interactive

# Audit pending updates in JSON format
slacky-update --check

# Change system language preference
slacky-update --lang en-boring
slacky-update --lang nb

# List all available language codes
slacky-update --list-langs

# Start or restart the background system tray applet
slacky-update-tray --restart
```

---

## 📜 Project Ancestry & Disclaimers

### 🤖 AI-Assisted Development Notice
This application was developed with the assistance of advanced AI pair-programming agents and was meticulously reviewed, architected, debugged, refactored, and tested on real bare-metal Slackware hardware by the author (**tuxofvalhalla**).

### 🧬 Project Fork & Heritage
**Slacky-Update** is a specialized, direct fork and successor of the author's sister project, **Debian-Update**, completely rewritten and restructured from the ground up to respect Slackware's native packaging philosophy, BSD-style init scripts, and kernel/module layout.

### ⚖️ Trademark & Fair Use Disclaimer
* **Slacky-Update** is an independent open-source project created by and for the Linux enthusiast community.
* This project is **not** officially affiliated with, endorsed by, sponsored by, or maintained by **Patrick Volkerding** or **Slackware Linux, Inc.**
* The name *Slackware* and associated logos are used strictly under **nominative fair use** to identify compatibility with the Slackware operating system distribution.

### 📄 License
This project is licensed under the **GNU General Public License v3.0 (GPL-3.0)**. See the [LICENSE](LICENSE) file for complete details.

---

<div align="center">

*“Be excellent to each other. And... PARTY ON, DUDES!”* 🎸⚡

</div>
