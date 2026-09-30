# 📘 The Ultimate Slacky-Update Survival Guide
### *Enterprise-Grade System Maintenance, Kernel Lifecycle, Driver Orchestrator & Workstation Suite for Slackware Linux*
#### `v1.0_RC2` — *"Dark Star"* (Stability & Hardware Release Candidate)

---

> [!IMPORTANT]
> **TARGET DISTRIBUTION REQUIREMENT & VERSION MANDATE**  
> **Slacky-Update is engineered strictly for Slackware 15+ (`slackware-current` / `Slackware 16 alpha`).**  
> It is **NOT** compatible with or supported on legacy **Slackware 15.0 (stable)**. Legacy 15.0 systems feature older core packages, toolchains, and shared libraries (such as older glibc, GCC, Wayland/Mesa, PipeWire, and kernel headers) that cause package and soname conflicts which cannot be safely detected or resolved. Running Slacky-Update on Slackware 15.0 is unsupported. Users on Slackware 15.0 must migrate to `slackware-current` before using this suite.

> [!CAUTION]
> **COMPREHENSIVE TESTING, LIABILITY & USE-AT-YOUR-OWN-RISK DISCLAIMER**  
> * **Hardware Testing & Verification:** Slacky-Update has been extensively verified and field-tested on the author's bare-metal workstations, and dry-run/simulated test passes have been executed across diverse build environments. However, **this in no way guarantees that it will operate seamlessly or without anomalies on your specific hardware configuration.**
> * **100% User Responsibility:** Slacky-Update executes deep, low-level modifications to foundational system components, including Linux kernel deployments, proprietary graphics stacks, initramfs generation, Btrfs subvolumes, and UEFI bootloader topologies. **All installation, upgrades, and system modifications are performed 100% at your own discretion and risk.**
> * **No Liability for Data Loss:** The authors, maintainers, and contributors assume **no liability, warranty, or responsibility** for system malfunctions, unbootable states, hardware quirks, or loss of personal data.
> * **Mandatory Backups:** Always maintain current, tested backups of your personal data (`/home`, essential configuration files, and boot partitions) and keep a bootable Slackware Live-USB accessible before performing upgrades or modifying bootloaders.
> * **Bug Reporting & Support Policy:** If you encounter bugs, regressions, or hardware edge-cases, please report them on [GitHub Issues](https://github.com/TuxOfValhalla/slacky-update/issues) so they can be addressed. Beyond the comprehensive documentation provided in `docs/`, no individual customer support, warranties, or service level agreements are offered.

---

## 📑 Table of Contents
1. [Core Philosophy: The Sacred Slackware Base](#core-philosophy-the-sacred-slackware-base)
2. [System Synchronization & Package Engine](#system-synchronization--package-engine)
3. [CachyOS Kernels (And all the flavors)](#cachyos-kernels-and-all-the-flavors)
4. [Graphics Stack & NVIDIA Driver Orchestration](#graphics-stack--nvidia-driver-orchestration)
5. [Limine Bootloader & UEFI Secure Boot Matrix](#limine-bootloader--uefi-secure-boot-matrix)
6. [System Performance & Gaming Tweaks](#system-performance--gaming-tweaks)
7. [Curated SBo SlackBuilds Hub & sbotools](#curated-sbo-slackbuilds-hub--sbotools)
8. [Curated Workstation & Gaming Suite](#curated-workstation--gaming-suite)
9. [Underpants Gnomes Sidecar Engine (Experimental)](#underpants-gnomes-sidecar-engine-experimental)
10. [Hyprland Desktop Suite Overview](#hyprland-desktop-suite-overview)
11. [Multi-Lingual Engine (24 Locales)](#multi-lingual-engine-24-locales)


---

## 1. Core Philosophy: The Sacred Slackware Base {#core-philosophy-the-sacred-slackware-base}

Slacky-Update was engineered around one immutable principle: **The Slackware Base System is Sacred.**

Unlike other package managers or modernization scripts that overwrite `/usr/lib64`, replace `glibc`, alter `/etc/pam.d/`, or inject alien daemons into system directories, Slacky-Update operates strictly within native Slackware boundaries:
* **Native Packaging Standard:** All deployed software is packaged into genuine Slackware `.txz` archives with standard `slack-desc` manifests, tracked in `/var/log/packages/`, and fully removable via `removepkg`.
* **Zero Rootfs Pollution:** Workstation applications and runtime libraries are isolated in `/opt/<app>/` and `/opt/underpants/` with private dynamic linker search paths (`RPATH` / `LD_LIBRARY_PATH`).
* **SysVinit Sovereignty:** Daemons and hardware services generate standard BSD-style init scripts in `/etc/rc.d/` (`rc.coolercontrol`, `rc.asusd`, `rc.lact`, `rc.ananicy-cpp`, `rc.scx`, `rc.gamemode`) adhering to Slackware convention.
* **Pure Source Transparency:** Slacky-Update contains zero precompiled binary blobs; every module is transparent Bash and Python 3.

> [!NOTE]
> ### 🧒 ELI5 (Explain Like I'm 5)
> Imagine your computer is a clean, sturdy brick house built by Slackware. Other update tools knock down walls and change your electrical wiring to fit new appliances. Slacky-Update brings in modern appliances inside custom furniture: you get all the new power, but the bricks, wiring, and foundation of your house remain 100% original and untouched!

---

## 2. System Synchronization & Package Engine {#system-synchronization--package-engine}

* **Engine:** `lib/mod_packages.sh`, `lib/common.sh`
* **Trigger:** Menu Option `[1]` (*Full System Upgrade*), CLI: `slacky-update`, `slacky-update -y`

### How the Engine Works
The System Synchronization Engine manages Slackware core updates in a single, resilient pipeline:
1. **Parallel Pre-fetch:** Spawns 10 concurrent download streams (`SLACKY_PREFETCH_JOBS=10`) using Python and `curl` to pre-cache all needed `.txz` packages and `.asc` GPG signatures into `/var/cache/slacky-update/packages/` before package operations begin.
2. **Slackpkg Integration & Stream Normalization:** Invokes `slackpkg update`, `slackpkg install-new`, and `slackpkg upgrade-all` through a real-time VT100/CSI/DEC stream normalizer. The normalizer converts `\r` and DEC Restore Cursor (`\x1b8`, `\x1b[u`) to `\n`, strips terminal cursor jumps, silences `wget` background redirect logs, and executes from temporary sandbox directories to prevent `wget-log.*` pollution in `$HOME`.
3. **Multi-Pass Resume:** If core system packages (`slackpkg`, `pkgtools`, `glibc-solibs`, `ca-certificates`) upgrade mid-transaction, the engine pauses, reloads the newly installed toolchain, and automatically completes remaining packages in up to 3 passes.
4. **Smart `.new` File Reconciliation:** Scans `/etc/` post-upgrade and categorizes `.new` files into 4 groups (New Configurations, Identical Duplicates, Unmodified Defaults, Custom User Configurations) with batch resolution.
5. **Smart Reboot Evaluator:** Inspects package manifests to determine if the running kernel, glibc, or NVIDIA driver was updated, prompting for a reboot only when strictly necessary.

> [!NOTE]
> ### 🧒 ELI5
> Instead of downloading one package at a time like an old dial-up modem, Slacky-Update sends 10 delivery vans at once to grab all your updates in seconds. It also makes sure the screen doesn't flicker or overwrite old text, and asks what to do with new config files so you never lose your personal settings.

### 🔍 Troubleshooting: Package Engine
* **Symptom:** `slackpkg update` fails with `CHECKSUMS.md5.asc download FAILS`.
  * *Cause:* Upstream Slackware mirror is temporarily syncing or offline.
  * *Fix:* Switch mirror in `/etc/slackpkg/mirrors` to an active mirror (e.g., `https://mirrors.ircam.fr/slackware/slackware64-current/`) or retry in 5 minutes.
* **Symptom:** Terminal screen shows duplicate or skipped text during updates.
  * *Cause:* Running an older version of Slacky-Update without the VT100 stream normalizer.
  * *Fix:* Update Slacky-Update to the latest version (`cd slackbuild && ./slacky-update.SlackBuild && sudo upgradepkg --install-new --reinstall /tmp/slacky-update-*.txz`).

---

## 3. CachyOS Kernels (And all the flavors) {#cachyos-kernels-and-all-the-flavors}

* **Engine:** `lib/mod_kernel.sh`
* **Trigger:** Menu Option `[2]` (*CachyOS Kernel Management*), CLI: `slacky-update --kernel`, `slacky-update -k`

### How the Engine Works
The Kernel Engine provides automated microarchitecture targeting, scheduling selection, DKMS building, and retention safeguards:
1. **Microarchitecture Auto-Detection:** Inspects `/proc/cpuinfo` flags (`avx512f`, `avx2`, `bmi2`) to target optimal instruction sets:
   * `x86_64_v4` / `znver4`: AMD Zen 4/5, Intel 12th–15th+ Gen Core.
   * `x86_64_v3`: Intel Haswell+ / AMD Excavator+.
   * `x86_64_v2`: Legacy 64-bit CPUs (Nehalem / Bulldozer).
2. **Kernel Flavors & Schedulers:**
   * `bore` (`linux-cachyos-bore`): Burst-Oriented Response Enhancer — optimal desktop and gaming latency.
   * `standard` (`linux-cachyos`): Default high-performance CachyOS kernel with BCFS/EEVDF tuning.
   * `lto` (`linux-cachyos-bore-lto`): Clang Link-Time Optimized build for peak instruction throughput.
   * `eevdf` (`linux-cachyos-eevdf`): Upstream Earliest Eligible Virtual Deadline First scheduling.
   * `bmq` (`linux-cachyos-bmq`): Project C BitMap Queue scheduler.
   * `rt-bore` (`linux-cachyos-rt-bore`): Real-Time PREEMPT_RT kernel for professional low-latency DAW audio.
   * `rc` (`linux-cachyos-rc`): Release Candidate mainline branch for bleeding-edge hardware testing.
   * `lts` (`linux-cachyos-lts`): Long-Term Support kernel for mission-critical stability.
   * `linux` / `linux-zen`: Arch Linux official vanilla and desktop-tuned Zen kernels.

> [!WARNING]
> ### 🛑 DECKIFY KERNEL RESTRICTION NOTICE
> The `deckify` kernel flavor (`linux-cachyos-deckify`) is **strictly engineered for handheld gaming consoles (Valve Steam Deck LCD/OLED, ROG Ally, Legion Go)** with specialized TDP, ACPI, audio, and controller driver patches.  
> **DO NOT install or use the `deckify` kernel on standard desktop PCs or laptops.** Doing so can cause incorrect thermal governor behavior, display power regressions, or non-functional audio devices.

3. **Multi-Kernel DKMS Driver Pipeline:** Automatically builds out-of-tree hardware modules (`nvidia-open-dkms`, `zenpower3`, `v4l2loopback`, `r8125`, Wi-Fi drivers) across all installed kernels.
4. **Dracut & Secure Boot Signing:** Generates lightweight Dracut initramfs images (`/boot/initramfs-<version>.img`) with 64-bit library shielding, and automatically signs kernels and initramfs with `sbctl` when UEFI Secure Boot is active.
5. **Retention Safeguards:** Automatically preserves the **2 newest standard/BORE kernels**, the **1 newest RC kernel**, and **strictly protects the active running kernel** plus stock fallback kernels.

> [!NOTE]
> ### 🧒 ELI5
> The kernel is the brain of your operating system. Slacky-Update lets you choose specialized brains tuned for super-fast gaming, music recording, or maximum stability. It automatically compiles drivers for all your hardware and keeps your old working kernel safe so you can always roll back if needed.

### 🔍 Troubleshooting: Kernel Engine
* **Symptom:** System boots into black screen or fallback TTY after kernel upgrade.
  * *Cause:* Graphics module was not compiled for the newly booted kernel version.
  * *Fix:* In Limine bootloader menu, select your previous working kernel, boot into desktop, and run `slacky-update --sync-nvidia` (or `slacky-update --sync-boot`).
* **Symptom:** `/boot` partition is full.
  * *Cause:* Too many old kernels or initramfs images accumulated.
  * *Fix:* Run `slacky-update --clean` (Option `[5]`) to purge obsolete kernel images and maintain the dual-kernel retention standard.

---

## 4. Graphics Stack & NVIDIA Driver Orchestration {#graphics-stack--nvidia-driver-orchestration}

* **Engine:** `lib/mod_nvidia.sh`, `lib/mod_rocm.sh`
* **Trigger:** Menu Option `[3]` (*NVIDIA & ROCm Graphics Hub*), CLI: `slacky-update --sync-nvidia`

### How the Engine Works
Slacky-Update orchestrates both kernel-space driver modules and user-space graphics stacks:

#### A. Kernel-Space NVIDIA Modules
* **CachyOS Kernels:** Deploys official pre-compiled binary open modules (`linux-cachyos-nvidia-open`, `cachyos-nvidia-open-modules`) matching the exact kernel version and microarchitecture.
* **Slackware & Arch Kernels:** Deploys `nvidia-open-dkms` (or `nvidia-580xx-dkms` for legacy Pascal architecture), building modules dynamically against the kernel headers.
* **Custom / Legacy `.run` Fallback:** The official NVIDIA `.run` installer is fully supported for users who require custom, beta, or specific legacy driver branches not covered by distribution packages.

#### B. User-Space Graphics Stack & Wayland Bridge
* **`cachyos-nvidia-utils` & `egl-gbm`:** Automatically packages 64-bit userspace libraries (`/usr/lib64/libnvidia-*.so`, `libcuda.so`, `libEGL_nvidia.so`), Xorg OutputClass configuration (`10-nvidia-drm-outputclass.conf`), and GLX symlinks.
* **`libnvidia-egl-gbm` & `15_nvidia_gbm.json`:** Deploys the GBM EGL external platform bridge directly into `/usr/lib64/` and `/usr/share/egl/egl_external_platform.d/`, ensuring flawless hardware acceleration for Xwayland games (*World of Warcraft*, *Battle.net*) and preventing KWin/Hyprland compositor crashes.
* **VRAM Booster & Memory Persistence:** Deploys `nvidia_drm.modeset=1`, `nvidia_drm.fbdev=1`, `NVreg_PreserveVideoMemoryAllocations=1`, and `NVreg_TemporaryFilePath=/var/tmp` to eliminate VRAM fragmentation and crash loops under Direct3D 12 (VKD3D-Proton).

#### C. AMD ROCm & HIP Creator Toolkit
* Deploys complete ROCm compute runtimes (`hip-runtime-amd`, `rocm-core`, `rocm-opencl-runtime`) for DaVinci Resolve Studio and Blender with automated Mesa Rusticl conflict resolution.

> [!NOTE]
> ### 🧒 ELI5
> Your graphics card needs two parts to work: a driver that talks to the hardware (kernel) and a translator that lets games speak to the driver (userspace). Slacky-Update installs matching versions of both automatically, prevents video memory crashes, and bridges modern Wayland desktops to your NVIDIA or AMD card.

### 🔍 Troubleshooting: Graphics Stack
* **Symptom:** Xwayland games run at 10–12 FPS with 100% CPU usage on `llvmpipe`.
  * *Cause:* Missing `libnvidia-egl-gbm.so` or `15_nvidia_gbm.json`.
  * *Fix:* Run `slacky-update --sync-nvidia` to deploy the unified `cachyos-nvidia-utils` suite with the integrated `egl-gbm` bridge.
* **Symptom:** Games crash with VRAM allocation errors after resuming from suspend.
  * *Cause:* Power management video memory preservation is disabled.
  * *Fix:* Enable NVIDIA VRAM preservation in `slacky-update --cmdline` (Option `[2]` in CMDLINE Hub).

---

## 5. Limine Bootloader & UEFI Secure Boot Matrix {#limine-bootloader--uefi-secure-boot-matrix}

* **Engine:** `lib/mod_limine.sh`, `lib/mod_secureboot.sh`
* **Trigger:** Menu Option `[6]` (*Limine & Secure Boot Armor*), CLI: `slacky-update --limine`, `slacky-update --cmdline`

### How the Engine Works
1. **Two-Zone `limine.conf` Architecture:**
   * **Zone A (User Styling):** Preserves custom background wallpaper, timeouts, color palettes, and graphical resolutions untouched.
   * **Zone B (Kernel Registry):** Atomically regenerates boot entries for all detected kernels (CachyOS, Arch, Slackware huge/generic) and calculates cryptographic hashes.
2. **Cryptographic BLAKE2B Anti-Tamper Sealing:** Pure-memory Python `hashlib.blake2b` engine computes cryptographic checksums for all kernel and initramfs binaries, embedding them into `limine.conf` (`kernel_hash:` and `module_hash:`). Any unauthorized modification to boot files is trapped before execution.
3. **Interactive Kernel CMDLINE Hub:** Instant interactive toggles for:
   * Quiet & Splash Boot (`quiet splash loglevel=3`)
   * NVIDIA Modeset & VRAM (`nvidia_drm.modeset=1 nvidia_drm.fbdev=1 NVreg_PreserveVideoMemoryAllocations=1`)
   * AMD GPU Overclocking (`amdgpu.ppfeaturemask=0xffffffff`)
   * Disable Watchdog (`nowatchdog`)
   * Disable USB Autosuspend (`usbcore.autosuspend=-1`)
   * ZSWAP RAM Compression (`zswap.enabled=1 zswap.compressor=zstd zswap.max_pool_percent=25`)
4. **UEFI Secure Boot & `sbctl` Integration:** Keeps UEFI Secure Boot permanently **ENABLED** in motherboard BIOS. Automates custom PK/KEK/db key enrollment and signs all kernel images, initramfs archives, and EFI binaries.
5. **Btrfs Snapper Snapshot Boot Integration:** Scans Btrfs root snapshots and automatically generates boot entries for the 5 newest snapshots, enabling 1-click rollback directly from the bootloader menu.

> [!NOTE]
> ### 🧒 ELI5
> Limine is the menu you see when you turn on your computer. Slacky-Update keeps this menu beautiful, locks it with cryptographic security seals so no virus can tamper with your startup files, lets you dual-boot Windows 11 with Secure Boot enabled, and lets you boot into backup snapshots if an update ever goes wrong.

### 🔍 Troubleshooting: Bootloader Matrix
* **Symptom:** Limine reports `Hash mismatch for kernel binary`.
  * *Cause:* Kernel binary was updated or modified outside of Slacky-Update without updating `limine.conf`.
  * *Fix:* Boot into system via fallback entry or live-USB and run `slacky-update --sync-boot` (or `hash-check`) to re-enroll BLAKE2B hashes.
* **Symptom:** Windows 11 fails to boot due to Secure Boot violation after dual-boot setup.
  * *Cause:* Microsoft certificates were not included during Secure Boot key generation.
  * *Fix:* In `slacky-update --limine`, re-enroll keys with Microsoft certificates enabled (`sbctl enroll-keys -m`).

---

## 6. System Performance & Gaming Tweaks {#system-performance--gaming-tweaks}

* **Engine:** `lib/mod_tweaks.sh`, `lib/mod_armor.sh`
* **Trigger:** Menu Option `[7]` (*System Performance Tweaks*), CLI: `slacky-update --tweaks`

### How the Engine Works
Deploys proven kernel, memory, network, and hardware tweaks in `/etc/sysctl.d/`, `/etc/security/limits.d/`, and `/etc/udev/rules.d/`:
* **Virtual Memory Tuning:** Sets `vm.max_map_count=2147483642` (required for modern Unreal Engine 5 and Direct3D 12 titles via VKD3D-Proton), `vm.swappiness=10`, `vm.vfs_cache_pressure=50`, and Transparent HugePages (`transparent_hugepage=madvise`).
* **TCP BBR Congestion Control:** Activates Google BBR congestion control (`net.ipv4.tcp_congestion_control=bbr`) and FQ queue discipline (`net.core.default_qdisc=fq`) for minimum download bufferbloat.
* **NTSYNC Primitives:** Provisions `/dev/ntsync` compatibility for fast in-kernel Windows NT synchronization primitives in Wine/Proton.
* **Universal Controller Forcefield:** Deploys udev hardware rules for DualSense, Xbox Wireless, Nintendo Switch Pro, 8BitDo, VR headsets, and flight sticks, disabling USB autosuspend on gaming peripherals (`ATTR{power/control}="on"`).

> [!NOTE]
> ### 🧒 ELI5
> These tweaks remove hidden speed limits in your operating system. They give games access to more memory maps, stop your internet from lagging during big downloads, and ensure your game controllers never go to sleep in the middle of a match!

---

## 7. Curated SBo SlackBuilds Hub & sbotools {#curated-sbo-slackbuilds-hub--sbotools}

* **Engine:** `lib/mod_sbo.sh`
* **Trigger:** CLI: `slacky-update --slackbuilds`, `slacky-update -s`

### How the Engine Works
* **Automatic Branch Routing:** On Slackware `-current`, build recipes are automatically routed to Ponce's Git repository; on Slackware `15.0`, recipes route to standard SlackBuilds.org.
* **26 Curated Build Recipes:** Pre-configured builds for Blender, FreeCAD, Unreal Engine 5, Plasticity 3D, Storyboarder, Serif Affinity Suite, SoftMaker FreeOffice, Opera, LACT, OpenRGB, and 3Dconnexion SpaceMouse.

---

## 8. Curated Workstation & Gaming Suite {#curated-workstation--gaming-suite}


* **Engine:** `lib/mod_gaming.sh`
* **Trigger:** Menu Option `[4]` (*CachyOS Gaming Software*), CLI: `slacky-update --gaming`, `slacky-update -g`

### How the Engine Works
1. **Isolated App-Bundles in `/opt/<app>/`:** Complex applications requiring specialized runtimes (`obs-studio`, `lutris`, `pear-desktop`, `bambu-studio`, `openghub`) are packaged into private application directories in `/opt/`. Their private libraries never touch `/usr/lib64/`, ensuring that running `removepkg` on one app will never break or remove shared system libraries for another.
2. **Multilib Version Intersection Engine:** For multi-architecture software (`gamescope`, `mangohud`, `gamemode`, `obs-vkcapture`, `yabridge`), update checks compute a strict version intersection between 64-bit and 32-bit package sets. An update notification is triggered **only when both 64-bit and 32-bit companion packages are available in the exact same version on upstream mirrors**, permanently eliminating multilib mismatch errors.
3. **Hardware Acceleration Wrappers:** Generates desktop wrappers (`/usr/bin/<app>`) with environment variable shielding (`WEBKIT_DISABLE_DMABUF_RENDERER=1`, `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1`) for reliable Wayland and NVIDIA execution.

---

## 9. Underpants Gnomes Sidecar Engine (Experimental) {#underpants-gnomes-sidecar-engine-experimental}

* **Engine:** `lib/mod_gnomes_engine.sh`, `lib/gnomes_pacman.py`, `/usr/bin/gnomes`
* **Trigger:** CLI: `gnomes`, `slacky-update --gnomes`

> [!WARNING]
> ### ⚠️ EXPERIMENTAL STATUS & SAFETY ARCHITECTURE
> The Underpants Gnomes Pacman Sidecar CLI (`gnomes`) is classified as **Experimental**.  
> Because the upstream Arch Linux and CachyOS repositories contain over **31,800+ packages**, it is impossible to manually audit and test every single package permutation.  
> **Why Underpants Gnomes is Benign and Safe for your Host System:**
> * All transmuted packages are installed strictly into `/opt/underpants/pkgs/<package>/` and link against the shared runtime pool in `/opt/underpants/runtime/`.
> * Gnomes **never** writes to, replaces, or modifies core system directories (`/lib64`, `/usr/lib64`, `glibc`, `pam`, `/sbin`).
> * **The only risk is that an individual transmuted package may fail to launch due to missing deep dependencies.** If an application fails to run, it can be safely removed with `gnomes -R <package>` without affecting your Slackware system. Please report broken packages on GitHub!

### Mandatory First-Time Setup: Complete Runtime Pool
Before installing standalone software via `gnomes -S`, you **must** install the complete runtime pool:

```bash
# Install the complete Underpants Gnomes shared runtime pool (~3,500+ shared libraries)
gnomes runtime install all

# Verify runtime pool status
gnomes runtime status
```

### Full Gnomes CLI Reference Table

| Command | Action | Description |
|---|---|---|
| `gnomes -S <pkg>` | Install Package | Transmutes and installs upstream package into `/opt/underpants/pkgs/` |
| `gnomes -Ss <query>` | Search Repositories | Searches Arch Linux and CachyOS mirrors for package names/descriptions |
| `gnomes -R <pkg>` | Remove Package | Uninstalls Gnomes package and removes desktop launcher |
| `gnomes -Syu` | Synchronize & Update | Updates package databases and upgrades all installed Gnomes packages |
| `gnomes -Si <pkg>` | Package Information | Displays upstream package metadata, size, version, and dependencies |
| `gnomes -Q` | Query Installed | Lists all installed Underpants Gnomes packages and versions |
| `gnomes runtime install all` | Install Runtimes | Deploys complete GTK4, Qt6, Python 3.14, and multimedia runtime libraries |
| `gnomes runtime status` | Runtime Audit | Verifies integrity and disk footprint of `/opt/underpants/runtime/` |

> [!NOTE]
> ### 🧒 ELI5
> Underpants Gnomes is like a magic translator. It lets you download software made for other Linux systems (Arch/CachyOS) and runs them in a private sandbox room inside `/opt/underpants/`. It never touches your Slackware system files, so your computer stays completely safe!

---

## 10. Hyprland Desktop Suite Overview {#hyprland-desktop-suite-overview}

* **Engine:** `lib/mod_gaming.sh`
* **Trigger:** CLI: `slacky-update --hyprland`, `slacky-update --hyprland-noctalia`, `slacky-update --hyprland-core`

Slacky-Update provides two distinct Hyprland desktop options:
1. **`hyprland-noctalia` (Curated Mac-like Wayland Suite):** Turnkey desktop featuring Noctalia Shell (topbar, dock, spotlight launcher, control center), modular Lua architecture (`~/.config/hypr/hyprland.lua`), PipeWire AT_SECURE protection, and HyprMod GTK4 visual settings editor.
2. **`hyprland-core` (DIY Minimalist Compositor):** Clean, unopinionated compositor for power users who want to build their own custom waybar, rofi, and swaylock environment.

👉 **For the complete, in-depth manual on Lua configurations, HyprMod GUI management, keybindings, and multi-monitor setups, consult the dedicated [Oh My Hyprland Guide](OH_MY_HYPRLAND_GUIDE.md).**

---

## 11. Multi-Lingual Engine (24 Locales) {#multi-lingual-engine-24-locales}


* **Engine:** `lib/slacky_update_i18n.py`, `locales/*.json`
* **Trigger:** CLI: `slacky-update --lang <code>`, `slacky-update --list-langs`

Slacky-Update features 100% internationalization parity across **24 global languages** (244 keys each):
* **Standard Locales:** English (`en`), Norwegian Bokmål (`nb`), Norwegian Nynorsk (`nn`), Danish (`da`), Swedish (`sv`), Finnish (`fi`), Icelandic (`is`), Sami (`se`), German (`de`), French (`fr`), Spanish (`es`), Italian (`it`), Portuguese (`pt`), Dutch (`nl`), Polish (`pl`), Russian (`ru`), Arabic (`ar`), Hindi (`hi`), Chinese (`zh`), Japanese (`ja`), Korean (`ko`), Canadian English (`en-ca`).
* **Radical 90s Pop-Culture Editions:** `en-radical` and `nb-radical` featuring authentic 90s slang (*Bill & Ted*, *TMNT*, *Wayne's World*, *Austin Powers*) and pulsing lightning bolt indicators (`⚡`/`✨`).

```bash
# Switch to Norwegian Bokmål
slacky-update --lang nb

# Switch to 90s Radical English
slacky-update --lang en-radical

# Reset to system default language
slacky-update --lang system
```

---

## 📜 Project Ancestry & License

* **Author:** tuxofvalhalla
* **Heritage:** Direct successor to Debian-Update, re-architected for Slackware Linux.
* **License:** GNU General Public License v3.0 (GPL-3.0). See [LICENSE](../LICENSE) for complete details.
