# It's My Party, And I'll Cry If I Want To...
### ⚡ Slacky-Update v0.13.0 — "Birthday Clown Demolition" (Release Edition)

---

> [!CAUTION]
> **SYSTEM MODIFICATION & RECOVERY DISCLAIMER — USE AT YOUR OWN RISK**  
> Slacky-Update v0.13.0 is a comprehensive system orchestrator and workstation modernizer for **Slackware Linux (-current / 15.0+)**. It interacts with low-level kernel infrastructure, proprietary GPU drivers, Dracut initramfs images, Btrfs subvolumes, and UEFI bootloader topologies (Limine/GRUB). Always maintain verified backups of `/home` and boot partitions and keep a Slackware Live-USB accessible.

---

## 🌟 Major Highlights of Patch v0.13.0

### 🔍 1. Dynamic Kernel & Limine BLAKE2B Hash Verifier (`hash-check`)
* **Instant Sealing Audit (`slacky-update --hash-check` / `-H`):** Dynamically scans all installed kernels (`/boot/vmlinuz-*`) and initramfs images (`/boot/initramfs-*.img`, `initrd*`) and calculates live `b2sum` cryptographic hashes.
* **1:1 Limine Registry Comparison:** Compares on-disk checksums against the registered entries inside `limine.conf`, verifying bootloader anti-tamper integrity with formatted color-coded output (`✓ MATCH`, `✗ MISMATCH`, `⚠️ UNTRACKED`).
* **Active Kernel Highlighting:** Clearly highlights the currently running kernel (`★`) and displays UEFI Secure Boot enforcement state.
* **Terminal Alias Integration:** Out-of-the-box support for the `hash-check` alias in Zsh / Bash.

---

### 🕹️ 2. The 34-Package Underpants Gnomes Gaming & Hardware Suite
All 34 workstation, creative, audio, and gaming packages have been verified and whitelisted:
* **Web Browsers:** Added and whitelisted **Brave** and **Zen Browser**.
* **Streaming & Remote Play:** Whitelisted **Sunshine** (Self-Hosted Game Stream Host) with automatic `/lib/udev/rules.d/60-sunshine.rules` controller permissions and `input` hardware group auditing (free of `setcap` to preserve unprivileged D-Bus / Wayland screen capture).
* **Communication & Streaming:** Whitelisted **Vesktop** (Discord Client with Vencord & Wayland Screen sharing) and **OBS Studio VKCapture** (bridged into isolated `/opt/obs-studio` runtime with 64-bit and 32-bit Vulkan layer discovery).
* **Creative & RAW Photography:** Whitelisted **Darktable** with complete modern multimedia codec suite (`libavif`, `libheif`, `libde265`, `libyuv`, `rav1e`, `svt-av1`, `openh264`, `pugixml`, `colord-gtk`, `osm-gps-map`, `gmic`, `flickcurl`), RUNPATH dynamic bridging, and Lua 5.4 support.
* **Music & Audio Production:** Whitelisted **Spotify Launcher** (with Sequoia PGP verification, `libayatana-appindicator`, `ayatana-ido`, and `libcurl-gnutls` integration) and **Yabridge (+ yabridgectl)** (Windows VST2/VST3/CLAP bridge for Linux DAWs with automated discovery library reflection).
* **Hardware & Fan Management:** Whitelisted **Solaar** (Logitech Unifying/Lightspeed manager with pure-Python modules and udev rules) and **CoolerControl (+ coolercontrold)** (v5.0 standalone Rust/Qt6 WebEngine suite with `/etc/rc.d/rc.coolercontrol` daemon management).
* **Emulation & Micro-Compositing:** Whitelisted **RetroArch** (multi-system emulator with Ozone/XMB shaders, FFmpeg 7, Qt6, SDL2, PipeWire) and **Gamescope** (Valve Gamescope Micro-Compositor with 64-bit and 32-bit multilib).

---

### 🌐 3. Curated SBo Hub & Dedicated Opera SlackBuild
* **Opera Web Browser SlackBuild (`assets/slacky-slackbuilds/network/opera/`):** Added curated SlackBuild recipe for Opera with auto-download fallback from `deb.opera.com`, 64-bit Slackware layout, SUID `4755` sandbox preservation, bulletproof launcher wrapper scripts (`/usr/bin/opera`), and desktop/icon database self-healing.
* **SlackBuilds Dry-Run & Formatting:** All 28 SlackBuilds verified with `bash -n` and adjusted to strict 11-line `slack-desc` formatting.
* **Curated SBo Hub Menus:** 7 active categories (Games, Graphics, Multimedia, System, Office, Network, Libraries) with `unreal-engine` dormant for future patch testing.

---

### 🚨 4. Holistic Disaster Recovery & Troubleshooting Guide with ELI5
* **11 Comprehensive Failure Scenarios:** Expanded [`docs/TROUBLESHOOTING_GUIDE.md`](TROUBLESHOOTING_GUIDE.md) to cover NVRAM resets, Secure Boot / hash mismatches, NVIDIA TTY fallbacks, disappearing Windows boot entries, Dracut OOM, Btrfs read-only snapshot rollbacks, BIOS Setup Mode, Live-USB chroot rescues, missing app icons / broken symlinks, multilib gaming crashes, and PipeWire audio resets.
* **🧩 ELI5 (Explain Like I'm 5) Sections:** Every scenario features a relatable, plain-English analogy with copy-paste terminal fixes.

---

### 🛠️ 5. Zero-Hardcoded Paths, Autonomous Healing & UI Polish
* **Dynamic CLI Multi-Column View:** Full package visibility without artificial truncation (`... and 20 additional packages`) across 2-to-3 terminal columns.
* **Scrollable Tray Menu:** Added Qt6 vertical scrollbar support in `slacky-update-tray` for large update batches.
* **Autonomous `slackpkg.conf.new` Reconcile:** Multi-pass distribution upgrades seamlessly transition when `slackpkg` self-upgrades.
* **Path Hardening:** Removed all personal development paths (`/home/tux/...`) across all scripts, tools, and documentation.
* **100% i18n Parity:** Synchronized all 24 language dictionaries (`locales/*.json`) to 206 keys matching `en.json` and `nb.json`.
* **Canonical Repository:** [GitHub](https://github.com/TuxOfValhalla/slacky-update) confirmed as canonical primary source with [Codeberg](https://codeberg.org/TuxOfValhalla/slacky-update) as secondary mirror.

---

## 📦 Package Details

* **Filename:** `slacky-update-0.13.0-noarch-1_slacky.txz`
* **Architecture:** `noarch` (Slackware Linux 15.0 & -current)
* **License:** `GPLv3`
* **Canonical Repository:** `https://github.com/TuxOfValhalla/slacky-update`
* **Secondary Mirror:** `https://codeberg.org/TuxOfValhalla/slacky-update`
