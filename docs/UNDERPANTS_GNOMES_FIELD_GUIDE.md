# 🧙 Underpants Gnomes Pacman Engine — Comprehensive Field Guide
### *Universal Arch & CachyOS Package Transmutation for Slackware Linux*

---

> [!WARNING]
> **EXPERIMENTAL FEATURE / UNDERPANTS LABS PREVIEW**  
> The Underpants Gnomes Universal Pacman Transmutation Engine is an **experimental, bleeding-edge capability** introduced in `slacky-update` v0.15.0. It provides direct, host-sovereign access to over **31,800+** software packages from Arch Linux and CachyOS repositories without modifying or compromising your Slackware base system.

---

## 🧒 ELI5: What is Underpants Gnomes and How Does It Work?

**Explain Like I'm 5 (ELI5):**
Imagine your Slackware system is a clean, well-organized house. You want to run a fancy toy from Arch Linux, but normally that toy requires changing the walls, doors, and plumbing (glibc, systemd, core libraries) of your whole house!

**Underpants Gnomes fixes this:**
1. **Step 1: Steal Underpants** — It downloads the Arch/CachyOS package and all its dependencies.
2. **Step 2: Transmutation** — It puts the application safely into its own sandbox room inside `/opt/underpants/pkgs/<app>/`, rewrites all internal paths so the app only looks inside its own room and the shared `/opt/underpants/runtime/` pool, and builds a genuine native Slackware `.txz` package.
3. **Step 3: PROFIT! 💰** — It places a small launcher script into `/usr/bin/` so you can launch the app from your terminal or application menu just like any native Slackware program!

**Your Slackware base system (`/lib64`, `/usr/lib64`, `glibc`, `init`, `pam`) remains 100% pristine, untouched, and safe.**

---

## 🚀 Getting Started: Step 1 is Installing the Runtime Pool

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

## 📜 Golden Rules & Best Practices

### 1. 🛡️ Always Check Slackware Base & SBo First!
Before installing a package via `gnomes -S`, always check if it is already provided natively by Slackware (`/var/log/packages`) or available via SlackBuilds (`sbopkg` / `slacky-update --sbo`). Native Slackware packages should always be your first choice.

### 2. 🎮 For Gaming Packages, Use Curated Modules!
For core gaming components such as **Steam, MangoHud, Gamescope, GOverlay, ProtonPlus, Faugus Launcher, and Ananicy-Cpp**, we strongly recommend installing them through `slacky-update --party-on` or the curated Underpants Gnomes gaming menu. These curated packages are tuned and patched specifically for optimal Slackware desktop and gaming performance.

### 3. ⚠️ KERNELS MUST NEVER BE INSTALLED VIA `gnomes -S`!
**Do NOT attempt to install Linux kernels, kernel headers, or out-of-tree kernel modules via `gnomes -S` (e.g. `gnomes -S linux` or `gnomes -S linux-zen`).**  
The pacman engine has built-in guardrails (`CORE_EXCLUDES`) that block kernel packages from transmuting to protect your bootloader.  
👉 **Kernel lifecycle management (CachyOS, Arch vanilla `linux`, and Arch `linux-zen` kernels) must strictly be managed through `slacky-update --kernel` / `mod_kernel.sh`!**

---

## 💻 Full Terminal Command Reference

You can use `gnomes` directly from Konsole, Bash, or Zsh just like `pacman` — there is no need to navigate through the `slacky-update` TUI menu unless you prefer it.

### 1. Database Synchronization & Repository Management
| Action | Pacman Syntax | Long-form Syntax | Description |
|---|---|---|---|
| **Sync Repositories** | `gnomes -Sy` | `gnomes sync` | Downloads latest database indexes from Arch/CachyOS |
| **Force Full Resync** | `gnomes -Syy` | `gnomes sync -f` | Forces a fresh download of all database archives |
| **List Active Mirrors** | — | `gnomes list-repos` | Lists active repository matrix and priority ordering |

### 2. Searching & Inspecting Packages
| Action | Pacman Syntax | Long-form Syntax | Description |
|---|---|---|---|
| **Search Packages** | `gnomes -Ss <query>` | `gnomes search <query>` | Sub-50ms search across package names and descriptions |
| **View Package Info** | `gnomes -Si <pkg>` | `gnomes info <pkg>` | Displays upstream version, size, dependencies, and URL |
| **Simulate Dependency Plan** | `gnomes -Sp <pkg>` | `gnomes deps <pkg>` | Solves the DAG and shows what will be downloaded vs host-provided |

### 3. Installing & Transmuting Packages
| Action | Pacman Syntax | Long-form Syntax | Description |
|---|---|---|---|
| **Install Package(s)** | `gnomes -S <pkg...>` | `gnomes transmute <pkg...>` | Resolves deps, downloads, transmutes to `.txz`, and installs |
| **Force Re-transmute** | `gnomes -S --force <pkg>` | `gnomes transmute -f <pkg>` | Rebuilds and reinstalls even if already installed |
| **Non-interactive Install** | `gnomes -S --noconfirm <pkg>` | `gnomes transmute -y <pkg>` | Skips confirmation prompts (useful in scripts) |
| **Build Only (No Install)** | `gnomes -S --build-only <pkg>` | `gnomes transmute --build-only <pkg>` | Generates the `.txz` package in `/tmp` without installing |

### 4. Updating & Managing Installed Packages
| Action | Pacman Syntax | Long-form Syntax | Description |
|---|---|---|---|
| **Check for Updates** | `gnomes -Syu` | `gnomes list-updates` | Checks installed gnomes packages against upstream repos |
| **List Installed Packages** | `gnomes -Q` | `gnomes list-installed` | Lists all transmuted packages in `/var/log/packages` |
| **Remove Transmuted App** | `gnomes -R <pkg>` | `removepkg underpants-<pkg>` | Uninstalls package cleanly from Slackware package database |

### 5. Runtime & Storage Management
| Action | Command | Description |
|---|---|---|
| **Inspect Runtime Pool** | `gnomes runtime status` | Reports soname count, active profiles, and Python version |
| **List Runtime Profiles** | `gnomes runtime profiles` | Shows available profiles (`core`, `gui`, `media`, `graphics`, `all`) |
| **Install Runtime Profile** | `gnomes runtime install <prof>` | Transmutes and deploys a shared runtime profile |
| **Reclaim Storage (Dedup)** | `gnomes dedup` | Hardlinks identical libraries across `/opt/underpants/` via SHA256 |
| **Clean Uninstalled Cache** | `gnomes -Sc` | `gnomes clean-cache` (removes old downloaded packages) |
| **Purge Entire Cache** | `gnomes -Scc` | `gnomes clean-cache --all` (prunes all build files and caches) |
| **Check Host Sovereignty** | `gnomes check-host` | Displays CPU tier, max GLIBC version, and indexed sonames |

---

## 🗂️ Filesystem Layout

```
/opt/underpants/
├── runtime/              ← Shared runtime pool (GTK, Qt, Mesa, Python, GStreamer)
│   ├── bin/              ← Runtime helper binaries
│   ├── lib/              ← 3,500+ shared libraries
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

## 🛠️ Troubleshooting

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
