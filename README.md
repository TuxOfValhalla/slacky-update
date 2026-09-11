<div align="center">

# ⚡ SLACKY-UPDATE ⚡
### *The Most Tubular System Update Station, Kernel Time Machine, SBo SlackBuild Hub & Driver Mojo Command Center for Slackware Linux*

[![Slackware -current](https://img.shields.io/badge/Slackware--current-15.0%2B-blue?style=for-the-badge&logo=slackware&logoColor=white)](http://www.slackware.com/)
[![Release](https://img.shields.io/badge/Release-v0.11%20'Underpants%20Gnomes%20hotfix'-purple?style=for-the-badge)](https://github.com/TuxOfValhalla/slacky-update/releases)
[![Mirror: Codeberg](https://img.shields.io/badge/Mirror-Codeberg-2185d0?style=for-the-badge&logo=codeberg&logoColor=white)](https://codeberg.org/TuxOfValhalla/slacky-update)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-green.svg?style=for-the-badge)](LICENSE)
[![Zero-Binary](https://img.shields.io/badge/Architecture-100%25%20Pure%20Source%20(Zero--Binary)-brightgreen?style=for-the-badge)](lib/)
[![Language](https://img.shields.io/badge/Locales-24%20Languages%20(168%20Keys)-yellow?style=for-the-badge)](locales/)
[![Stack](https://img.shields.io/badge/Stack-Bash%20%7C%20Python3%20%7C%20PyQt5-orange?style=for-the-badge)](bin/)

---

### *Party on, Wayne! / Party on, Garth!*
**Slacky-Update** is an all-in-one maintenance station, background system monitor, curated SlackBuild hub, and high-performance gaming/creator workstation suite engineered specifically for **Slackware Linux (-current / 15.0+)**. 

*Canonical source: [GitHub](https://github.com/TuxOfValhalla/slacky-update) | Official European mirror: [Codeberg](https://codeberg.org/TuxOfValhalla/slacky-update)*

**Release v0.11 'Underpants Gnomes hotfix'** (*"Phase 1: Collect Drivers. Phase 2: Purge Stale Modules. Phase 3: Profit!"*) delivers critical graphics and kernel stability enhancements:
* **NVIDIA Stale Kernel Module Purge & Depmod Shield:** Automatically detects and purges conflicting or stale `extramodules/nvidia*.ko.zst` and `kernel/drivers/video/` module copies across all installed kernels, permanently eliminating boot-time TTY fallbacks caused by module version mismatches.
* **CachyOS-Master NVIDIA 615.x Full Suite Multilib Sync:** Synchronizes 64-bit and 32-bit multilib graphics, OpenCL, and VA-API NVDEC with proactive Dracut regeneration across all installed kernels.
* **Intelligent Kernel Retention Policy:** Automatically retains the 2 newest standard/BORE kernels and 1 newest RC kernel, preventing ESP space bloat while preserving rock-solid rollback points.
* **Flatpak GL Runtime & Proton Compatibility:** Restores flatpak NVIDIA GL runtime matching and ensures smooth integration with Steam and Proton.
* **The Underpants Gnomes Suite:** 36 native transmuted gaming, audio, creative, and hardware packages (MangoHud, GameMode, Sched-EXT, Yabridge, DaVinci plugins, Solaar, CoolerControl, LACT, OpenRGB, Syncthing, Browsers) with GPG verification and SysVinit daemons.

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
 [1] Total System Synchronization --> Slackware + Flatpaks + SBo + MOK Armor
 [2] CachyOS Kernel Time Machine  --> CPU Tier Detect, Deploy, Manage & Purge
 [3] NVIDIA & ROCm Graphics Hub   --> Branch Select / CachyOS Master, ROCm/HIP
 [4] Underpants Gnomes Suite      --> 37 Native Transmuted Gaming & App Packages
 [5] System Cleanup & Retention   --> Dual Kernel Retention & Artifact Purge
 [6] Secure Boot MOK Forcefield   --> 1-Click Setup, Shim Inject & Self-Heal
 [7] Babling Multi-Lingual Engine --> 24 Locales with 100% Key Parity (162 Keys)
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
* **Dual Upstream Self-Update Engine:** Real-time release verification from Codeberg (primary) and GitHub (fallback) with clean status line (`✓ Slacky-Update is up to date (v0.10)`) and 1-click self-upgrade & reload.
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

### 4. 🩲 The Underpants Gnomes Master Suite (36 Native Transmuted Packages)
*Phase 1: Collect Upstream Packages. Phase 2: Transmute & Package into Native Slackware `.txz`. Phase 3: Profit!*

The Underpants Gnomes suite provides a curated collection of 36 native, high-performance workstation, audio, creative, hardware, and gaming applications packaged on-the-fly directly from CachyOS and Arch Extra repositories into native Slackware `.txz` packages:

* **Cryptographic Integrity & GPG Verification:** Every downloaded upstream archive (`.pkg.tar.zst`) and auxiliary subpackage is strictly validated against Arch and CachyOS public GPG signatures (`.sig`) before unpacking. Corrupted or unverified packages are rejected immediately.
* **Isolated App-Bundles in `/opt` (Host System Respect):** Applications with complex runtime dependencies (`obs-studio`, `lutris`, `pear-desktop`) are packaged into self-contained directory trees in `/opt/<name>/` with dedicated wrapper launchers in `/usr/bin/`. Host Slackware Python installations, system libraries, and desktop schemas are never polluted or overwritten.
* **Full Multilib 32-Bit & Wine Integration:** Seamless 32-bit multilib runtime deployment for `lib32-gamemode`, `lib32-mangohud`, `obs-vkcapture`, and `yabridge` + `yabridgectl` for Windows VST2/VST3 plugin bridging in Linux DAWs.
* **SysVinit Daemons (`/etc/rc.d/`):** Full integration with Slackware's native init system: generates and manages service scripts for `rc.coolercontrol`, `rc.asusd`, `rc.syncthing`, `rc.lact`, `rc.scx`, `rc.ananicy-cpp`, and `rc.gamemode`, with automatic boot persistence in `/etc/rc.d/rc.local` and `/etc/rc.d/rc.local_shutdown`.
* **Hardware User Group & Multilib Readiness Audits:** Automatically verifies whether your active user account belongs to `input`, `plugdev`, `video`, `audio`, offering 1-click group enrollment via `usermod -aG` so controllers, Solaar, Lian Li, and GPU utilities work without root.
* **Pre-flight Dependency Checks:** Detects kernel support for `sched_ext` before installing `scx`, and verifies Wine availability before deploying `yabridge`, prompting the user with clear options and zero surprise failures.

| Category | Applications Included | Integration & Features |
| :--- | :--- | :--- |
| **🎮 Game Engine & Overlays** | `mangohud`, `gamemode`, `goverlay`, `scx`, `ananicy`, `gamescope` | Multilib 32-bit, Vulkan layer remapping, BPF schedulers, auto-nice daemons. |
| **🎵 Audio & Music Studio** | `yabridge`, `audacity`, `spotify`, `easyeffects`, `pear-desktop` | Windows VST2/3 bridge, 15+ LV2 DSP plugins with JackHack96 presets, YouTube Music. |
| **🎨 Creative & 3D Studio** | `inkscape`, `darktable`, `bambu-studio` | Vector graphics, RAW photo development, 3D printing slicer. |
| **🎛️ Hardware & Cooling** | `coolercontrol`, `solaar`, `lian-li-linux`, `asusctl`, `lact`, `openrgb` | AIO liquid & fan daemons, Logitech Unifying, Lian Li Uni-fan, ASUS ROG, GPU OC. |
| **🛠️ Power Tools & Launchers** | `syncthing`, `parabolic`, `retroarch`, `heroic`, `faugus`, `protonplus`, `steam-devices` | P2P sync daemon, yt-dlp GUI, Libretro emulator with Ozone, 28 gamepad udev rules. |
| **🌐 High-Performance Browsers** | `brave`, `zen-browser`, `vivaldi`, `google-chrome`, `microsoft-edge`, `opera` | Standalone isolated `/opt` installations with clean `/usr/bin` symlinks. |

### 5. 🏎️ CachyOS Time Machine & Kernel Uninstaller
* **Interactive Granular Kernel Removal:** Dedicated interactive tool to select and completely purge specific installed kernels. Removes vmlinuz, initramfs/initrd, `/lib/modules/`, headers, DKMS entries, and GRUB lines.
* **Active Kernel Shield:** Strictly prevents deleting the currently running kernel (`uname -r`).
* **Stock & LTS Fallback Guardrails:** Slackware stock kernels can only be removed if `linux-cachyos-lts` is installed. Removing CachyOS LTS when no other CachyOS kernel exists automatically triggers complete restoration of Slackware stock kernels (`kernel-generic`, `kernel-modules`) and rebuilds graphics drivers.
* **Permanent `kernel-headers` Preservation:** `kernel-headers` are permanently preserved across all operations, ensuring 100% build system compatibility.
* **Automatic CPU Tier Detection:** Identifies your CPU microarchitecture (*x86_64_v4 / znver4, x86_64_v3, x86_64_v2*) and pulls high-performance, optimized CachyOS Linux kernel binaries and headers directly from upstream Arch/CachyOS package repositories (*Standard, BORE, BORE-LTO, RC, and LTS flavors*).
* **Smart Bootloader "Top Dog" Priority:** Automatically sets the highest performance installed kernel as default top entry in GRUB, alongside intelligent CMDLINE deduplication and normalization.

### 6. 🎮 NVIDIA & ROCm Graphics Hub (100% `.run`-Independent)
* **Precompiled CachyOS Modules:** Automatically deploys official prebuilt `linux-cachyos-*-nvidia-open` packages for all CachyOS kernels on Modern GPUs (Turing+), delivering zero compilation overhead.
* **`nvidia-open-dkms` Integration:** Utilizes CachyOS `nvidia-open-dkms` (or `nvidia-580xx-dkms` for Pascal) to compile open modules directly for Slackware stock kernels, completely eliminating 400 MB `.run` file downloads on CachyOS systems.
* **Dynamic Interface Adaptation:** Hides manual `.run` branch options on CachyOS systems to prevent driver mismatch, and automatically restores the full `.run` installer interface when returning to pure Slackware.
* **Automated Rollback Engine:** Fully sanitizes `cachyos-nvidia-utils` and reinstalls the official NVIDIA standalone `.run` driver with DKMS when reverting to pure Slackware.
* **AMD ROCm / HIP Creator Toolkit:** Complete OpenCL & HIP compute runtimes (`rocm-core`, `rocm-opencl-runtime`, `rocm-hip-runtime`, `hsa-rocr`, `comgr`) with automatic **Mesa OpenCL & Rusticl purge & blacklisting** to prevent DaVinci Resolve crashes on Radeon hardware.
* **DaVinci Resolve Deliver Plugins:** Full integration of **FFmpeg Deliver Tab Encoder plugin** (`FFmpegEncoder.dvpipeline`) and **AAC audio export plugin** directly into DaVinci Resolve Studio for both AMD and NVIDIA rigs.

### 7. ⚡ "JUST FIX MY DAMN SECURE BOOT!" (1-Click Ironclad Wizard)
* **One-Click Provisioning:** Deploys Microsoft-signed `shimx64.efi`, `mmx64.efi`, and Fedora-signed `grubx64.efi` to `/boot/efi/EFI/Slackware/`, creates dynamic early `grub.cfg` pointers, provisions MOK keypairs, bakes Dracut initramfs across all kernels, signs all binaries, and updates GRUB.
* **Smart Signature Verification:** Inspects module headers (`modinfo -F signer`) prior to extraction, skipping already-signed modules to accelerate update transactions.
* **Collision-Free Isolated Module Signing:** Module signing executes inside dedicated `/tmp/slacky-sign-XXXXXX` workspaces, preventing corrupted `.ko.zst` files, auto-purging uncompressed `.ko` duplicates, and auto-detecting the active MOK signer tool (`kmodsign` or `sign-file`).
* **Silent Self-Heal Guard:** Runs quietly in the background on every update. If an external package or accidental `grub-install` overwrites your signed EFI binaries or configuration, Self-Heal silently restores them!
* **Bundled OpenSSL 1.1 Compatibility:** Packages include bundled `libcrypto.so.1.1` and `libssl.so.1.1` compatibility libraries so `sbsign` and `mokutil` never fail on Slackware -current with OpenSSL 3.x.

### 8. ⚙️ Dracut & ELILO / Bootloader Integrations
* **Dracut Multilib Shield (`00-multilib.conf`):** Automatically injects `--libdirs "/lib64 /usr/lib64 /usr/local/lib64"` and deploys `/etc/dracut.conf.d/00-multilib.conf` to block 32-bit multilib library collisions, ensuring pure 64-bit initramfs integrity.
* **Native Dracut Engine:** Explicitly iterates across all installed kernels in `/lib/modules/*` to generate complete, high-performance Dracut initramfs images (`/boot/initramfs-*.img`, 220+ MB) with baked-in GPU and storage drivers.
* **ELILO & GRUB Multi-Bootloader Support:** Intelligently adapts to your active bootloader environment, synchronizing `/boot/efi/EFI/Slackware/elilo.conf` on pure ELILO setups, and managing `/boot/grub/grub.cfg` with Top-Dog kernel prioritization on GRUB systems.
* **GRUB Preference Protection:** Automatically purges conflicting 11 MB `initrd-*.img` files created by Slackware's stock `mkinitrd` **only after** Dracut has verified successful generation, ensuring GRUB always boots the complete Dracut initramfs!
* **Legacy Fallback:** If Dracut is not installed, seamlessly falls back to standard Slackware `mkinitrd` with root device UUID and filesystem auto-detection.

### 9. 🧹 Clean the Garage (System Maintenance)
* **Slackware Stock Kernel Retention:** Keeps the **1 newest Slackware stock kernel** plus the active booted kernel, cleanly purging older versions, old module folders, and outdated initramfs files.
* **Cache Purge & Portability:** Cleans stale build directories in `/var/cache/slacky-update/` and runs `flatpak uninstall --unused`. All paths are 100% portable with zero hardcoded user directories.
* **Bootloader Sync:** Automatically runs `grub-mkconfig` to keep `/boot/grub/grub.cfg` pristine and free of ghost entries.

### 10. 💓 Dynamic System Tray Applet
* **Pulsing Desktop Notifications:** When updates are available, the tray icon pulses dynamically (100% ⇄ 80% size) synchronized with desktop notifications (KNotify/KDE) before settling back smoothly.
* **Discreet Scan Flow:** Manual updates trigger an instant checking icon without popup spam; returning quietly to green when 0 updates are found.
* **Direct Slack-builds Trigger:** Dedicated tray action to launch the interactive SlackBuilds & Tweaks hub in a terminal window.
* **Instant Action Menu:** Check updates on demand, view category breakdowns, launch terminal upgrades, or switch interface language on the fly.

---

## 🌍 Babling (24 Multi-Lingual Locales)

Slacky-Update includes full internationalization across **24 languages** with **100% key parity (162/162 keys)**.

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
git clone https://codeberg.org/TuxOfValhalla/slacky-update.git && cd slacky-update && sudo bash slackbuild/slacky-update.SlackBuild && sudo upgradepkg --install-new --reinstall slacky-update-*.txz && slacky-update-tray &
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
