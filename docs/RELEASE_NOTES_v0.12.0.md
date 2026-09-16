# ⚡ Slacky-Update v0.12.0 — Release Notes
### *"....and all that I can see, is just another Limine tree...."* (Pre-Release / Early Access)

---

> [!CAUTION]
> **PRE-RELEASE / EARLY ACCESS DISCLAIMER — USE AT YOUR OWN RISK**  
> Slacky-Update v0.12.0 is an active *Pre-Release / Early Access* edition. The software performs low-level system modifications to core infrastructure, including Linux kernel deployments, proprietary NVIDIA drivers, Dracut initramfs generation, Btrfs subvolumes, and bootloader topologies (Limine/GRUB).  
> **All usage is strictly at your own discretion and risk.** Always verify that you maintain current, tested backups (`/home`, essential configuration files, and boot partitions) and keep a bootable Slackware Live-USB accessible.

---

## 🌟 What's New in v0.12.0

### 🥾 1. Complete Limine Bootloader & Secure Boot Armor
* **Two-Zone Configuration Model**: Protects custom themes, wallpapers, and timeouts in Zone A while atomically generating verified kernel entries in Zone B.
* **Safe Cryptographic Hashing**: Enrolls BLAKE2B cryptographic hashes directly into boot entries (`boot():/vmlinuz-...#<hash>`) to prevent execution of tampered or corrupted files.
* **Automated & Manual ESP Topology Migration**:
  - Full support for $\ge 3.5\text{ GB}$ FAT32 ESP partitions mounted directly at `/boot`.
  - Supports Scenario A (in-place `/boot/efi` $\rightarrow$ `/boot` promotion), Scenario B (in-place verified $\ge 3.5\text{ GB}$ `/boot`), and Scenario C (dedicated ESP adoption with multiboot EFI preservation).
* **UEFI Fallback Binary**: Automatically installs and signs `/EFI/BOOT/BOOTX64.EFI` to guarantee bootability even if motherboard NVRAM is reset following BIOS updates.
* **Early CPU Microcode Multi-Module Support**: Automatically detects and injects `intel-ucode.cpio` / `amd-ucode.cpio` as separate hashed modules before `initrd` for legacy Slackware stock kernels.
* **Btrfs Snapper Snapshot Booting**: Boot directly into read-only Btrfs snapshots with zero disk overhead (reusing base kernel hashes).
* **UEFI Secure Boot Orchestration**: Full integration with `sbctl` and Machine Owner Keys (MOK), enabling permanent Secure Boot operation alongside Windows 11.

---

### 🏎️ 2. NVIDIA Driver & CachyOS-Master Logic Hardening
* **CachyOS-Master vs. DKMS**: Uses official pre-compiled CachyOS open kernel modules for CachyOS kernels on Turing and newer GPUs, with automated DKMS fallback for custom and stock kernels.
* **Stale Module Purge & Depmod Shield**: Automatically scans and purges conflicting, obsolete `nvidia*.ko*` module remnants across all installed kernel versions, permanently eliminating boot-time TTY fallbacks caused by version mismatches.
* **Hybrid Laptop Graphics (PRIME)**: Automatically detects mobile chassis forms and forces integrated GPU KMS drivers (`i915`, `xe`, `amdgpu`) to load before `nvidia` in Dracut, preventing early-boot black screens and ensuring smooth PRIME offloading (`prime-run`).

---

### 🧠 3. CachyOS-RC Kernel Retention Fixes
* **Strict Single RC Retention**: Fixed kernel retention logic to keep strictly the **single newest RC kernel** on the system (0 retention of older RC builds), preventing ESP space exhaustion.
* **Dual Stable Retention**: Preserves the 2 newest standard/BORE kernels and strictly shields the active running kernel (`uname -r`).
* **Stock Kernel Fallback Guard**: Automatically protects and restores stock Slackware generic kernels (`kernel-generic`, `kernel-modules`) as bootable fallbacks.

---

### ⚡ 4. 10-Stream Parallel Downloads on Everything
* **Core Slackware Acceleration**: 10 concurrent HTTP/FTP worker streams (`SLACKY_PREFETCH_JOBS=10`) with HTTP range resume (`-C -`), cutting download phases by 5–10×.
* **Parallel Workstation & Gaming Downloads**: Multi-threaded metadata resolution and concurrent downloads for Underpants Gnomes application bundles.

---

### 📚 5. Complete Documentation & Technical Whitepapers (100% English)
* **Master Survival Guide & System Manual** ([`SURVIVAL_GUIDE.md`](SURVIVAL_GUIDE.md)): Complete end-user operational manual featuring a 1-page "Before you press 1" Pre-Flight checklist and ELI5 ("Explain Like I'm 5") conceptual ingresses at the start of all 12 chapters.
* **Technical Companion Guide** ([`TECHNICAL_COMPANION_GUIDE.md`](TECHNICAL_COMPANION_GUIDE.md)): Architectural whitepaper detailing the 12 internal engines, sandboxing mechanisms, and zero-rootfs compilation philosophy.
* **Disaster Recovery & Troubleshooting Guide** ([`docs/TROUBLESHOOTING_GUIDE.md`](docs/TROUBLESHOOTING_GUIDE.md)): Symptom-based field catalog covering the 8 most critical failure scenarios, diagnosis commands, and a universal 5-step Live-USB chroot recovery procedure.
* **Limine & Secure Boot Field Guide** ([`docs/LIMINE_SECUREBOOT_FIELD_GUIDE.md`](docs/LIMINE_SECUREBOOT_FIELD_GUIDE.md)): A–Z manual partitioning playbook and motherboard BIOS configuration matrix.

---

### 🐛 6. Additional Bugfixes & Enhancements
* **`mkinitrd.conf` Staging Fix**: Forced `SOURCE_TREE="/tmp/initrd-tree"` across all modules and scenarios to permanently eliminate FAT32 symlink/mknod warnings during `slackpkg` upgrades.
* **Menu Whitelist Filtering**: Interactive menus in Underpants Gnomes (22 packages) and SlackBuilds Hub (18 packages) now present only 100% tested and verified suites, while all transmutation definitions remain intact in code for future activation.
* **Multi-Lingual Engine**: 24 fully localized languages with 100% key parity (182 keys), featuring rotating hourglass (`⏳`) and Radical 90s pulsing lightning bolt (`⚡`) animations.
* **Dual Installation Support**: Clear, side-by-side build and installation instructions for both **Codeberg** (Canonical) and **GitHub** (Mirror).

---

## 📦 Package Verification

* **Filename:** `slacky-update-0.12.0-noarch-1_slacky.txz`
* **Architecture:** `noarch` (Slackware Linux 15.0 & -current)
* **License:** `GPLv3`
* **Canonical Repository:** `https://codeberg.org/TuxOfValhalla/slacky-update`
* **Secondary Mirror:** `https://github.com/TuxOfValhalla/slacky-update`
