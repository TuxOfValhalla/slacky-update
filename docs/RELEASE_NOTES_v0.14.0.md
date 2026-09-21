# Coco Jambo - 'Put Me Up, Put Me Down, Put My Feet Back On The Ground'
### ⚡ Slacky-Update v0.14.0 — "Coco Jambo" (Release Edition)

---

> [!CAUTION]
> **SYSTEM MODIFICATION & RECOVERY DISCLAIMER — USE AT YOUR OWN RISK**  
> Slacky-Update v0.14.0 is a comprehensive system orchestrator and workstation modernizer for **Slackware Linux (-current / 15.0+)**. It interacts with low-level kernel infrastructure, proprietary GPU drivers, Dracut initramfs images, Btrfs subvolumes, and UEFI bootloader topologies (Limine/GRUB). Always maintain verified backups of `/home` and boot partitions and keep a Slackware Live-USB accessible.

---

## 🌟 Major Highlights of Patch v0.14.0

### 🚀 1. Expanded CachyOS High-Performance Kernel Fleet
Slacky-Update now supports 9 specialized CachyOS kernel flavors across all CPU optimization tiers (`v4` AVX-512, `v3` AVX2, and standard x86-64):
* **`linux-cachyos-eevdf`:** Earliest Eligible Virtual Deadline First — upstream standard scheduler refined with CachyOS responsiveness and low-latency throughput tuning.
* **`linux-cachyos-bmq`:** BitMap Queue scheduler engineered specifically for ultra-low desktop latency and silky smooth interactivity under heavy system load.
* **`linux-cachyos-deckify`:** Handheld and power/frame-pacing scheduler profile crafted for Valve Steam Deck and portable rigs.
* **`linux-cachyos-rt-bore`:** Real-Time `PREEMPT_RT` combined with BORE (Burst-Oriented Response Enhancer) for deterministic DAW audio production and live streaming.
* **Full Ecosystem Parity:** All 9 kernel flavors are integrated into `lib/mod_kernel.sh`, `lib/mod_limine.sh` boot menus, `lib/mod_clean.sh` retention policies, and `lib/mod_nvidia.sh` compatibility checks.

---

### 🛡️ 2. Universal Multi-Kernel DKMS Engine & NVIDIA Safety Shield
* **Dynamic Multi-Kernel Driver Generation (`build_dkms_modules_for_all_kernels`):** Iterates across all installed kernels in `/usr/lib/modules/*/build` and automatically compiles and installs active DKMS out-of-tree hardware drivers.
* **NVIDIA DKMS Safety Shield:** Automatically inspects kernel extramodules for precompiled `nvidia.ko` / `nvidia-open` drivers. If precompiled NVIDIA modules exist, DKMS NVIDIA builds are strictly skipped to prevent module collisions and driver corruption.

---

### 📡 3. Out-of-Tree DKMS Hardware & Telemetry Suite
Integrated automated packaging, configuration, and DKMS module compilation for crucial hardware:
* **Smart Realtek 2.5GbE (`r8125`) Hardware Detection:** Automatically detects RTL8125 / Killer E3100X PCI NIC hardware (`10ec:8125` / `10ec:3000`) via sysfs and lspci. Automatically downloads and deploys matching precompiled CachyOS `r8125` driver packages directly from official mirrors for all installed CachyOS kernels.
* **`zenpower3-dkms`:** AMD Ryzen (Zen / Zen 2 / Zen 3 / Zen 4 / Zen 5) voltage, current, and CCD core telemetry driver for MangoHud (with automatic `/etc/modprobe.d/zenpower.conf` `k10temp` blacklisting).
* **`v4l2loopback-dkms`:** Video4Linux2 virtual loopback device driver enabling OBS Studio Virtual Camera (`/etc/modprobe.d/v4l2loopback.conf` with `exclusive_caps=1`, `video_nr=10`).
* **Realtek Wi-Fi Fleet:** `rtl8821cu-dkms-git`, `rtl88x2bu-dkms-git`, and `rtl8812au-dkms-git` for high-gain USB Wi-Fi dongles.
* **Broadcom Wireless:** `broadcom-wl-dkms` for Broadcom BCM43xx 802.11a/b/g/n wireless adapters.

---

### 🎬 4. OBS Studio Creator & Streaming Power-Pack
Added 9 vetted industry-standard creator and streamer plugins, complete with automated dual-mode bridging into native Slackware (`/usr/lib64/obs-plugins/`, `/usr/share/obs/obs-plugins/`) and isolated `/opt/obs-studio`:
1. **`obs-studio`:** Isolated bleeding-edge OBS Studio application.
2. **`obs-vkcapture`:** Vulkan / OpenGL game capture layer with 32-bit multilib support.
3. **`obs-move-transition`:** Smooth source and scene animations.
4. **`obs-source-record`:** Isolated track/ISO recording for clean creator edits.
5. **`obs-pipewire-audio-capture`:** Per-application audio routing and direct stream separation.
6. **`obs-advanced-scene-switcher`:** Advanced automated scene triggering and scripting engine.
7. **`obs-multi-rtmp`:** Multi-destination live streaming (Twitch, YouTube, Kick).
8. **`obs-composite-blur`:** High-performance GPU box/motion/Gaussian blur filter.
9. **`obs-teleport`:** Ultra-low latency LAN/NDI video streaming across workstation networks.

---

### 🎨 5. Pure Plasticity 3D CAD SlackBuild Recipe
* **Curated SlackBuild (`assets/slacky-slackbuilds/graphics/plasticity/`):** Transmutes official upstream Plasticity 3D CAD `.deb` packages into pure Slackware `.txz` archives.
* **Workstation Integration:** Provides desktop application entries, hicolor icons, and mime type associations. Added to `lib/mod_sbo.sh` graphics catalog.

---

### 📂 6. Collapsible Category Menus in TUI (`slacky-update -g`)
* **Interactive Category Folding:** Toggle categories open or closed (`C1` through `C9`).
* **Expand All / Collapse All:** Quick fold toggles (`E` for Expand All, `C` for Collapse All).
* **1-Click OBS Creator Suite (`O`):** Batch installs all 9 OBS plugins and streaming tools in a single parallel download transaction.
* **1-Click Total Gaming Rig (`A`):** Batch installs the entire curated workstation and gaming suite.

---

### 🧙 💰 7. Underpants Gnomes Rebranding & High-Performance Console Station
* **Unified Console Station (`slacky-update --gnomes`):**
  * **2-Column Grid Layout:** Replaced deep category nesting with a clean, compact 2-by-2 column grid displaying all 51 gaming apps, tools, and drivers.
  * **Compact Version Badges:** Streamlined status badges with concise version tags (`[v1.8.2 ✓]` / `[Not Inst]`) for immediate verification of cutting-edge software.
  * **🧙 Alternating Gnome Animation:** Timestamp-paced (~350ms) animated Gnome transmutation (`🧙` <-> `🧙‍♂️`) collecting underpants (`🩲`) along the parallel download track.
  * **Steal Underpants Flow:** Action flow `🩲 Steal Underpants!`, animated transmutation `Step 2: ? ? ? ?`, and grand finish `🧙 💰 STEP 3: PROFIT!!! 🎉`.
* **Sub-10ms Fast Status Resolution & Probe Engine:**
  * Implemented instant single-pass package status scanning using standard Slackware package naming rules.
  * Automatic binary, DKMS, and udev probing fallback for locally compiled or custom unmanaged tools (such as LACT, OpenRGB, MangoHud, etc.).
* **Seamless Launch Pathways:**
  1. **Direct CLI:** `slacky-update --gnomes` or `slacky-update -g`.
  2. **System Tray Applet:** Direct right-click action `🧙 Underpants Gnomes 📦` launching instantly in Konsole/terminal.
  3. **Main Station Menu:** `slacky-update` option `G` (Underpants Gnomes Transmutation Station).
* **Valve Steam Platform Integration (`underpants-steam`):**
  * Added Valve Steam directly into the Underpants Gnomes suite (51 total components).
  * Automatically bundles official controller & gamepad udev hardware rules (`60-steam-input.rules`) with instant `udevadm` reload.
  * Performs pre-flight 32-bit multilib verification to ensure seamless proton and native compatibility.
* **Package Rebranding:** Transitioned package naming prefix to `underpants-${pkg_id}` with full backward compatibility for existing `cachyos-gnome-*` installations.
* **Authentic 90s Slang:** Injected authentic 90s slang (*Cowabunga*, *Major Bummer*, *Excellent*, *Bodacious*, *Step 3: PROFIT!*) throughout the installer and slack-desc manifests.

---

## 📦 Package Details

* **Filename:** `slacky-update-0.14.0-noarch-1_slacky.txz`
* **Architecture:** `noarch` (Slackware Linux 15.0 & -current)
* **License:** `GPLv3`
* **Canonical Repository:** `https://github.com/TuxOfValhalla/slacky-update`
* **Secondary Mirror:** `https://codeberg.org/TuxOfValhalla/slacky-update`
