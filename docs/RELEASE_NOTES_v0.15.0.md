# ⚡ Slacky-Update v0.15.0 — "Now This Is Podracing!"
### *Enterprise-Grade System Maintenance, Kernel Lifecycle, Driver Orchestrator & Universal Pacman Transmutation Factory for Slackware Linux*

---

> [!CAUTION]
> **SYSTEM MODIFICATION & RECOVERY DISCLAIMER — USE AT YOUR OWN RISK**  
> Slacky-Update v0.15.0 is an enterprise-grade system orchestrator and workstation modernizer for **Slackware Linux (-current / 15.0+)**. It interacts with low-level kernel infrastructure, proprietary GPU drivers, Dracut initramfs images, Btrfs subvolumes, UEFI bootloader topologies (Limine/GRUB), and standalone sandboxed package engines. Always maintain verified backups of `/home` and boot partitions and keep a Slackware Live-USB accessible.

---

## 🌟 Major Highlights of v0.15.0 — "Now This Is Podracing!"

Release **v0.15.0** delivers two landmark features for Slackware Linux:
1. **Universal Underpants Gnomes Pacman Sidecar Engine & Transmutation Factory (Experimental)**: Instant, host-sovereign access to over **31,800+** software packages from CachyOS and Arch Linux, transmuted dynamically into genuine native Slackware `.txz` packages without polluting host `glibc`, `init`, `pam`, or core system libraries.
2. **Expanded Kernel Ecosystem**: Added support for **Official Arch Linux Vanilla Kernel (`linux`)** and **Arch Zen Kernel (`linux-zen`)** in the kernel manager alongside the full CachyOS kernel suite.

---

## 🏛️ Key Features & Technical Innovations

### 1. 🧙 Universal Pacman Sidecar Engine (`bin/gnomes` & `lib/gnomes_pacman.py`) [Experimental]
* **Zero-Root In-Memory Indexing**: Direct parser for `.db.tar.zst` and `.db.tar.gz` database archives, indexing 31,800+ packages in memory with sub-50ms search and zero host root filesystem dependencies.
* **Microarchitecture Auto-Tiering**: Automatically detects host CPU tier (`znver4`, `v4`, `v3`, generic) and orders mirrors accordingly (`cachyos-znver4`, `cachyos-v4`, `cachyos-v3`, standard `cachyos`, Arch `extra`, `multilib`, `core`).
* **Strict Guardrails**: Blacklists unstable/testing repositories.

### 2. 🩲 10-Worker Parallel Downloader with Gnome Chomping Progress Bar
* **Turbo Parallel Pre-fetch**: 10 concurrent download streams (`download_packages_parallel`) with SHA-256 integrity verification.
* **Animated Progress Ticker**: Signature Gnome Chomping Underpants animation (`[━━━🧙 🩲·🩲·]`) culminating in the triumphant `🧙 💰 PROFIT!` phase indicator.

### 3. 🛡️ Dependency DAG Solver & Host Sovereignty Shield
* **Topological Dependency Graph**: Resolves deep multi-tier dependency trees with cycle detection and leaf-first install ordering.
* **Host Shared Library Scanner**: Scans `/etc/ld.so.cache` (indexing 8,000+ native sonames) to maximize native library reuse.
* **Virtual Provides & Core Exclude Shield**: Satisfies virtual dependencies (`vulkan-driver`, `pipewire`, `wayland`, `sh`, `desktop-file-utils`, `ntsync-module`) from host Slackware while strictly preventing upstream base system packages (`glibc`, `pam`, `shadow`, `sysvinit`, `udev`) from entering the payload.

### 4. ⚡ ELF RUNPATH Relocation, Universal Wrappers & Post-Install Scriptlets
* **Automated Binary Relocation**: Scans ELF headers and rewrites `RUNPATH` to `$ORIGIN/../lib:$ORIGIN/lib:/opt/underpants/common/lib` via `patchelf`.
* **Universal Script Relocator**: Handles shell variables (`${name}`, `$name`) in Electron, Python, and shell wrappers.
* **Unconditional 64-bit GTK Isolation**: Eliminates Multilib `ELFCLASS32` collisions by scoping `GTK_PATH` and auto-generating `immodules.cache` and `loaders.cache`.
* **Automatic Runtime Scriptlets**: Relocates Glycin loader `.conf` files, generates GTK3/Pixbuf caches, compiles GSettings schemas, and updates MIME/icon caches.

### 5. 🐧 Arch Linux Vanilla & Zen Kernel Integration
* **Arch Linux Vanilla Kernel (`linux`)**: Clean upstream stable Linux kernel builds packaged for Slackware with automated Dracut initramfs and Limine/GRUB boot entries.
* **Arch Zen Kernel (`linux-zen`)**: Tuned desktop kernel with low-latency scheduling, ideal for general desktop responsiveness and audio workstation workflows.

### 6. 🎮 CLI & TUI Station Integration
* **`bin/gnomes` CLI Utility**: Full pacman-style command line interface (`-Ss`, `-Si`, `-Sd`, `-S`, `-Sy`, `-Syu`, `-Q`, `-R`, `--check-host`).
* **Dedicated Field Guide**: Full user documentation available in `docs/UNDERPANTS_GNOMES_FIELD_GUIDE.md`.
* **Gaming Menu Integration**: Accessible directly from `slacky-update --gnomes` (Option S) and main menu option `-P` / `--gnomes-pacman`.

---

## 📦 Release Package Details

* **Package File:** `slacky-update-0.15.0-noarch-32_slacky.txz` / `slacky-update.txz`
* **Target OS:** Slackware Linux 15.0 & -current (x86_64)
* **License:** GNU General Public License v3.0 (GPLv3)
* **Canonical Git:** `https://github.com/TuxOfValhalla/slacky-update`
* **Codeberg Mirror:** `https://codeberg.org/TuxOfValhalla/slacky-update`
