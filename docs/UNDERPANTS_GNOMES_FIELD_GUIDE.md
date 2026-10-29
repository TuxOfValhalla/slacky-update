# 🧙 Underpants Gnomes Pacman Engine — Comprehensive Field Guide
### *Universal Arch & CachyOS Package Transmutation for Slackware Linux*
#### `v1.0 LTS` — *"Dark Star"* (Official Long-Term Support Release)

---

> [!IMPORTANT]
> **TARGET DISTRIBUTION REQUIREMENT & VERSION MANDATE**  
> **Underpants Gnomes and Slacky-Update are engineered strictly for Slackware 15+ (`slackware-current` / `Slackware 16 alpha`).**  
> Legacy **Slackware 15.0 (stable)** is strictly unsupported due to older host glibc, toolchains, and sonames that cause conflicts that cannot be detected or resolved. Slackware 15.0 users must upgrade to `-current` before using this suite.

> [!WARNING]
> **EXPERIMENTAL STATUS & HOST-SOVEREIGN SAFETY NOTICE**  
> The Underpants Gnomes Universal Pacman Transmutation Engine is an **Experimental** feature. Because upstream repositories contain over **31,800+ packages**, we cannot manually audit every possible application.  
> **Host Safety Guarantee:** Underpants Gnomes is a completely benign addition that **never modifies host system libraries (`/lib64`, `/usr/lib64`, `glibc`, `/etc/pam.d`)**. Packages run isolated in `/opt/underpants/pkgs/` with private dynamic linker search paths (`RPATH`). If a package fails to run due to unmet deep runtime dependencies, you can safely remove it via `gnomes -R <pkg>`.

---

## 📑 Table of Contents
1. [Core Philosophy: The Sacred Slackware Base & The Five Pillars](#1-core-philosophy-the-sacred-slackware-base--the-five-pillars)
2. [🧒 ELI5: What is Underpants Gnomes and How Does It Work?](#2-eli5-what-is-underpants-gnomes-and-how-does-it-work)
3. [🚀 Getting Started: Installing the Shared Runtime Pool](#3-getting-started-installing-the-shared-runtime-pool)
4. [📜 Golden Rules & Best Practices](#4-golden-rules--best-practices)
5. [💻 Full Terminal Command Reference](#5-full-terminal-command-reference)
6. [🗂️ Filesystem Layout & Host Sovereignty Architecture](#6-filesystem-layout--host-sovereignty-architecture)
7. [🛠️ Troubleshooting & Recovery](#7-troubleshooting--recovery)

---

## 1. Core Philosophy: The Sacred Slackware Base & The Five Pillars

The Underpants Gnomes transmutation engine is strictly governed by **The Sacred Slackware Base System** and **The Five Engineering Pillars**:
* **The Sacred Slackware Base System:** Foreign package manager binaries (`pacman`, `apt`, `dnf`, `libalpm`) are **never installed or executed on the host system**. Instead, an in-memory pure Python streaming engine (`lib/gnomes_pacman.py`) reads repository manifests, decompresses upstream archives directly in RAM with `zstandard`, isolates application files strictly in `/opt/underpants/`, builds authentic namespaced Slackware `.txz` packages (`underpants-*.txz`), and installs them cleanly via `upgradepkg --install-new`. Host system libraries (`/lib64`, `/usr/lib64`, `glibc`, PAM) are 100% shielded and sovereign, and packages log cleanly under `/var/log/packages/underpants-*` with zero foreign package manager databases or base system collisions.
* **⚡ Speed:** Fast-Race multi-threaded mirror evaluation with a weekly mirror ranking; in-memory database search (<50ms).
* **🛋️ Comfort:** Familiar Pacman command syntax (`gnomes -S`, `-Syu`, `-Ss`, `-R`), interactive 2-column TUI workstation manager, and timestamp-paced animated Gnome download bars.
* **🛡️ Safety:** Complete Host Sovereignty Shielding in `/opt/underpants/` with private `RPATH`/`RUNPATH`, zero rootfs pollution, and automatic self-healing 404 repository synchronization.
* **🎨 UI Design:** Clean Dark Star styling, dynamic terminal width adaptation, and pixel-perfect text rendering.
* **🤝 Ease of Use:** 1-line installation, automated shared runtime pools, and universal `(ESC)` navigation across all menus.

---

## 2. 🧒 ELI5: What is Underpants Gnomes and How Does It Work?

**Explain Like I'm 5 (ELI5):**
Imagine your Slackware system is a clean, well-organized brick house. You want to bring home a modern toy from an Arch Linux store, but normally that toy demands knocking down your walls, ripping out your plumbing, and replacing your electrical wiring (glibc, systemd, PAM) to match Arch's factory rules!

**Underpants Gnomes fixes this:**
1. **Step 1: Steal Underpants** — It downloads the Arch/CachyOS package and all its dependencies.
2. **Step 2: Transmutation** — It puts the application safely into its own sandbox room inside `/opt/underpants/pkgs/<app>/`, rewrites internal paths so the app only looks inside its own room and the shared `/opt/underpants/runtime/` pool, and builds a genuine Slackware `.txz` package.
3. **Step 3: PROFIT! 💰** — It installs the package cleanly into `/var/log/packages/underpants-<app>` and places a small launcher script into `/usr/bin/` so you can launch the app from your terminal or application menu just like any native Slackware program!

**Your Slackware base system (`/lib64`, `/usr/lib64`, `glibc`, `init`, `pam`) remains 100% pristine, untouched, and safe.**

---

## 3. 🚀 Getting Started: Installing the Shared Runtime Pool

Before installing complex GTK4, Qt6, or multimedia applications, you should install the **Underpants Gnomes Shared Runtime Pool**.

The runtime pool provides over **3,500+ pre-staged shared libraries** (GTK3/4, Qt5/6, WebKitGTK, GStreamer, Mesa/Vulkan, FFmpeg, Python 3.14) in `/opt/underpants/runtime/`. This avoids re-downloading hundreds of megabytes of duplicate dependencies for every single app.

To install the complete runtime pool:

```bash
gnomes runtime install all
```

> [!NOTE]
> The engine automatically creates all necessary directory structures (`/opt/underpants/runtime/`, `/opt/underpants/pkgs/`, `/opt/underpants/common/`), relocates configurations (such as Glycin image loaders), and compiles schemas and module caches automatically.

You can check the status of your runtime pool at any time:
```bash
gnomes runtime status
```

---

## 4. 📜 Golden Rules & Best Practices

### 1. 🛡️ Always Check Slackware Base & SBo First!
Before installing a package via `gnomes -S`, always check if it is already provided natively by Slackware (`/var/log/packages`) or available via SlackBuilds (`sbotools` / `slacky-update --slackbuilds`). Native Slackware packages should always be your first choice.

### 2. 🎮 For Gaming Packages & Desktop Suites, Use Curated Modules!
For core gaming components such as **Steam, MangoHud, Gamescope, GOverlay, ProtonPlus, Faugus Launcher, and Ananicy-Cpp**, complete desktop environments like **`hyprland-noctalia`** (Mac-like Wayland desktop with Noctalia Shell) and **`hyprland-core`**, or settings suites like **`hyprmod`** (GTK4 visual settings editor for Hyprland), we strongly recommend installing them through the curated Underpants Gnomes menu (`slacky-update --gaming`, Main Menu `[4]`), `slacky-update --gaming-deploy <app>`, `slacky-update --hyprland`, or `slacky-update --hyprmod`. These curated packages are tuned and patched specifically for optimal Slackware desktop and gaming performance:
* **HyprMod Visual Configuration:** Visual GTK4/Libadwaita management for monitors, 10-bit OLED color modes, animations, and keybindings via modular `hyprland-gui.lua`.
* **Systray Daemon Integration:** Built-in autostart and StatusNotifierItem registration for `slacky-update-tray`, `openrgb` (with automatic profile loading), and `easyeffects`.
* **Hardware-Accelerated Browsers:** Installing `google-chrome`, `brave`, or `microsoft-edge` automatically detects NVIDIA hardware and provisions hardware-accelerated Wayland and VA-API flags (`--ozone-platform=wayland`, `VaapiOnNvidiaGPUs`, `--enable-gpu-rasterization`, `--enable-zero-copy`).

### 3. ⚠️ KERNELS MUST NEVER BE INSTALLED VIA `gnomes -S`!
**Do NOT attempt to install Linux kernels, kernel headers, or out-of-tree kernel modules via `gnomes -S` (e.g. `gnomes -S linux` or `gnomes -S linux-zen`).**  
The pacman engine has built-in guardrails (`CORE_EXCLUDES`) that block kernel packages from transmuting to protect your bootloader.  
👉 **Kernel lifecycle management (CachyOS, Arch vanilla `linux`, and Arch `linux-zen` kernels) must strictly be managed through Main Menu `[2]` (*CachyOS Kernel Management*) / `mod_kernel.sh`!**

### 4. ⚡ Fast-Race Mirror Benchmarking Engine
When fetching Chaotic-AUR packages (such as `hyprpicker`, `easyeffects`, or `coolercontrol`), the engine evaluates global mirrors concurrently via `concurrent.futures.as_completed` (2.5-second limit) and keeps a weekly ranking. If a mirror fails, the same file is tried on the next ranked mirrors (at most 4). A file that fails its signature or checksum check is never "healed" from another mirror; it is refused.

### 5. 🔄 Transparent 404 Self-Healing Auto-Sync
If an upstream repository rolls out an update while local database manifests are cached, returning HTTP 404, Gnomes automatically traps the error, runs a silent forced resynchronization (`sync_repositories(force=True, verbose=False)`), updates the URL to the latest version, and retries the download seamlessly.

---

## 5. 💻 Full Terminal Command Reference

You can use `gnomes` directly from Konsole, Bash, or Zsh just like `pacman` — there is no need to navigate through the `slacky-update` TUI menu unless you prefer it.

### 1. Database Synchronization & Repository Management
| Action | Pacman Syntax | Long-form Syntax | Description |
|---|---|---|---|
| **Sync Repositories** | `gnomes -Sy` | `gnomes sync` | Downloads latest database indexes from Arch/CachyOS |
| **Force Full Resync** | `gnomes -Sy -f` | `gnomes sync -f` | Forces a fresh download of all database archives |

### 2. Searching & Inspecting Packages
| Action | Pacman Syntax | Long-form Syntax | Description |
|---|---|---|---|
| **Search Packages** | `gnomes -Ss <query>` | `gnomes search <query>` | Sub-50ms search across package names and descriptions |
| **View Package Info** | `gnomes -Si <pkg>` | `gnomes info <pkg>` | Displays upstream version, size, dependencies, and URL |
| **Simulate Dependency Plan** | `gnomes -Sd <pkg>` | `gnomes deps <pkg>` | Solves the DAG and shows what will be downloaded vs host-provided |

### 3. Installing & Transmuting Packages
| Action | Pacman Syntax | Long-form Syntax | Description |
|---|---|---|---|
| **Install Package(s)** | `gnomes -S <pkg...>` | `gnomes install <pkg...>` | Resolves deps, downloads, transmutes to `.txz`, and installs |
| **Force Re-transmute** | `gnomes -S --force <pkg>` | `gnomes transmute -f <pkg>` | Rebuilds and reinstalls even if already installed |
| **Non-interactive Install** | `gnomes -S --noconfirm <pkg>` | `gnomes transmute -y <pkg>` | Skips confirmation prompts (useful in scripts) |
| **Build Only (No Install)** | `gnomes -S --build-only <pkg>` | `gnomes transmute --build-only <pkg>` | Generates the `.txz` package in a private build folder (`~/.cache/slacky-update/gnomes/build/`) without installing |

### 4. Updating & Managing Installed Packages
| Action | Pacman Syntax | Long-form Syntax | Description |
|---|---|---|---|
| **Sync & Upgrade** | `gnomes -Syu` | `gnomes update` | Syncs databases and upgrades installed gnomes packages (asks first; `--yes` without a terminal) |
| **Check for Updates** | `gnomes -Qu` | `gnomes list-updates` | Lists available updates from the last sync (read-only, no root) |
| **List Installed Packages** | `gnomes -Q` | `gnomes list` | Lists all transmuted packages in `/var/log/packages` |
| **Remove Transmuted App** | `gnomes -R <pkg>` | `gnomes remove <pkg>` | Uninstalls package cleanly via `removepkg` (asks first) |
| **Roll Back an App** | — | `gnomes --rollback <pkg>` | Goes back to the previous version, rebuilt from a system snapshot |

### 5. Runtime & Storage Management
| Action | Command | Description |
|---|---|---|
| **Inspect Runtime Pool** | `gnomes runtime status` | Reports soname count, active profiles, and Python version |
| **List Runtime Profiles** | `gnomes runtime profiles` | Shows available profiles (`core`, `gui`, `media`, `graphics`, `cad`, `mobile`, `desktop`, `hyprland`, `noctalia`, `all`) |
| **Install Runtime Profile** | `gnomes runtime install <prof>` | Transmutes and deploys a shared runtime profile (default: `core`) |
| **Remove Runtime** | `gnomes runtime remove [prof]` | Removes the shared runtime (asks first); apps that use it stop working |
| **Reclaim Storage (Dedup)** | `gnomes dedup` (or `-Sdd`) | Hardlinks identical libraries across `/opt/underpants/` via SHA256 |
| **Clean Uninstalled Cache** | `gnomes -Sc` | `gnomes clean` (removes old downloaded packages) |
| **Purge Entire Cache** | `gnomes -Scc` | `gnomes clean --all` (prunes all build files and caches) |
| **Check Host Sovereignty** | `gnomes check-host` | Displays CPU tier, max GLIBC version, and indexed sonames |
| **Heal Native Packages** | `gnomes -Sh` | `gnomes heal` (audits `/usr/bin/` and heals native Slackware packages from rogue wrappers) |

---

## 6. 🗂️ Filesystem Layout & Host Sovereignty Architecture

```
/opt/underpants/
├── runtime/              ← Shared runtime pool (GTK, Qt, Mesa, Python, GStreamer)
│   ├── bin/              ← Runtime helper binaries
│   ├── lib/              ← 3,500+ shared libraries (isolated from /usr/lib64)
│   ├── share/            ← Icons, GSettings schemas, Glycin loaders, MIME
│   └── include/          ← Header files
├── pkgs/                 ← Isolated per-application payloads
│   ├── drawio-desktop/   ← App binaries, assets, and app-specific dependencies
│   ├── obsidian/
│   └── filezilla/
└── common/               ← Deduplicated hardlinked shared libraries

/usr/bin/                 ← Lightweight launcher wrapper scripts deployed for each app
/usr/share/applications/  ← Standard XDG desktop entry files for application menus
/var/log/packages/        ← Standard Slackware package logs (e.g. underpants-<app>-<ver>)
```

---

## 7. 🛠️ Troubleshooting & Recovery

If an application fails to launch or displays missing library warnings:

1. **Verify the runtime pool is installed:**
   ```bash
   gnomes runtime status
   ```
2. **Force re-transmutation of the application:**
   ```bash
   gnomes -S --force <app-name>
   ```
3. **Run storage deduplication to reclaim disk space:**
   ```bash
   gnomes dedup
   ```
4. **Purge old package cache:**
   ```bash
   gnomes -Sc
   ```

---

<div align="center">
<b>Slacky-Update Underpants Gnomes Field Guide</b><br>
<i>Canonical Source: <a href="https://github.com/TuxOfValhalla/slacky-update">GitHub</a> | Secondary Mirror: <a href="https://codeberg.org/TuxOfValhalla/slacky-update">Codeberg</a></i>
</div>
