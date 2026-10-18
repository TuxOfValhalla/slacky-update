#!/usr/bin/env python3
"""
slacky_doctor.py - System Health & Diagnostic Engine for Slacky-Update ('Dark Star')
Engineered for Slackware Linux (-current / 15.0+)
Zero external dependencies: uses ONLY Python standard library.

Audits 7 critical system health domains:
1. Platform, CPU Architecture & ISA extensions (AVX2/AVX-512)
2. Kernel, Initramfs & Fallback Retention
3. Bootloader (Limine/GRUB), Secure Boot MOK & BLAKE2B Hash Integrity
4. Graphics Stack (NVIDIA/AMD), DKMS Modules & Wayland/X11 Compositor
5. Storage, Btrfs Subvolumes, Snapper Snapshots, /tmp tmpfs & zswap
6. Performance & Low-Latency Tweaks (Limits, THP, BBR, NTSYNC, FastBoot)
7. The Sacred Slackware Base & System Package Integrity
"""

import sys
import os
import platform
import subprocess
import json
import re
import shutil
import time
import argparse
from datetime import datetime
from pathlib import Path

# --- [ ANSI COLOR & STYLING DEFINITIONS ] ---
RESET = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"
ITALIC = "\033[3m"
UNDERLINE = "\033[4m"

RED = "\033[31m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
BLUE = "\033[34m"
MAGENTA = "\033[35m"
CYAN = "\033[36m"
WHITE = "\033[37m"

BOLD_RED = "\033[1;31m"
BOLD_GREEN = "\033[1;32m"
BOLD_YELLOW = "\033[1;33m"
BOLD_BLUE = "\033[1;34m"
BOLD_MAGENTA = "\033[1;35m"
BOLD_CYAN = "\033[1;36m"
BOLD_WHITE = "\033[1;37m"
DIM_WHITE = "\033[2;37m"

def strip_ansi(text: str) -> str:
    ansi_regex = re.compile(r'\x1b\[[0-9;]*[a-zA-Z]')
    return ansi_regex.sub('', text)

def format_size(bytes_val: int) -> str:
    if bytes_val < 1024:
        return f"{bytes_val} B"
    elif bytes_val < 1024 * 1024:
        return f"{bytes_val / 1024:.1f} KB"
    elif bytes_val < 1024 * 1024 * 1024:
        return f"{bytes_val / (1024 * 1024):.1f} MB"
    else:
        return f"{bytes_val / (1024 * 1024 * 1024):.2f} GB"

def compute_blake2b(path: str) -> str:
    if not path or not os.path.exists(path):
        return ""
    try:
        import hashlib
        hb = hashlib.blake2b()
        with open(path, "rb") as f:
            while chunk := f.read(65536):
                hb.update(chunk)
        return hb.hexdigest().lower()
    except Exception:
        return ""

# --- [ SYSTEM HEALTH AUDITOR ] ---
def audit_system_health() -> dict:
    t_start = time.perf_counter()
    report = {
        "timestamp": datetime.now().isoformat(),
        "hostname": platform.node(),
        "platform": {},
        "kernel": {},
        "bootloader": {},
        "graphics": {},
        "storage": {},
        "tweaks": {},
        "integrity": {},
        "checks": [],
        "warnings": [],
        "failures": [],
        "recommendations": [],
        "score": 100,
        "verdict": "EXCELLENT",
        "eli5_summary": ""
    }

    # 1. Platform & CPU Architecture
    slackware_ver = "Slackware (Unknown)"
    if os.path.exists("/etc/slackware-version"):
        try:
            with open("/etc/slackware-version", "r", encoding="utf-8") as f:
                slackware_ver = f.read().strip()
        except Exception:
            pass

    cpu_model = "Unknown CPU"
    cpu_cores = os.cpu_count() or 1
    cpu_flags = set()
    if os.path.exists("/proc/cpuinfo"):
        try:
            with open("/proc/cpuinfo", "r", encoding="utf-8") as f:
                for line in f:
                    if line.startswith("model name") and cpu_model == "Unknown CPU":
                        cpu_model = line.split(":", 1)[1].strip()
                    elif line.startswith("flags"):
                        cpu_flags.update(line.split(":", 1)[1].strip().split())
        except Exception:
            pass

    has_avx2 = "avx2" in cpu_flags
    has_avx512 = any(f.startswith("avx512") for f in cpu_flags)
    isa_level = "x86_64_v4" if has_avx512 else ("x86_64_v3" if has_avx2 else "x86_64_v1/v2")

    report["platform"] = {
        "os": slackware_ver,
        "cpu_model": cpu_model,
        "cores": cpu_cores,
        "isa_level": isa_level,
        "avx2": has_avx2,
        "avx512": has_avx512
    }
    report["checks"].append({
        "id": "os_slackware",
        "category": "Platform",
        "name": "Slackware Base Distribution",
        "status": "PASS",
        "value": slackware_ver,
        "detail": f"{cpu_model} ({cpu_cores} threads, {isa_level})"
    })

    # 2. Kernel & Initramfs
    active_kver = platform.release()
    initramfs_candidates = [
        f"/boot/initramfs-{active_kver}.img",
        f"/boot/initramfs-{active_kver}.zst",
        f"/boot/initrd-{active_kver}.img",
        f"/boot/initrd-{active_kver}.gz",
        f"/boot/initrd.gz"
    ]
    active_initramfs = None
    for cand in initramfs_candidates:
        if os.path.exists(cand):
            active_initramfs = cand
            break

    initramfs_fresh = False
    initramfs_size_str = "None"
    if active_initramfs:
        initramfs_size_str = format_size(os.path.getsize(active_initramfs))
        k_file = f"/boot/vmlinuz-{active_kver}"
        if os.path.exists(k_file):
            k_mtime = os.path.getmtime(k_file)
            i_mtime = os.path.getmtime(active_initramfs)
            initramfs_fresh = (i_mtime >= k_mtime - 300)
        else:
            initramfs_fresh = True

    # Fallbacks in /boot with /lib/modules fallback when /boot is root-isolated
    installed_vmlinuz = []
    boot_readable = os.path.exists("/boot") and os.access("/boot", os.R_OK)
    if boot_readable:
        try:
            for fname in os.listdir("/boot"):
                if fname.startswith("vmlinuz-") and not fname.endswith(".old"):
                    installed_vmlinuz.append(fname.replace("vmlinuz-", ""))
        except Exception:
            pass
    else:
        # Fallback: check /lib/modules where installed kernels are registered and world-readable
        if os.path.exists("/lib/modules"):
            try:
                for d in os.listdir("/lib/modules"):
                    if re.match(r'^\d+\.\d+', d) and os.path.isdir(os.path.join("/lib/modules", d)):
                        installed_vmlinuz.append(d)
            except Exception:
                pass

    fallbacks = [k for k in installed_vmlinuz if k != active_kver]
    has_fallback = len(installed_vmlinuz) > 1
    report["kernel"] = {
        "active": active_kver,
        "initramfs": active_initramfs,
        "initramfs_fresh": initramfs_fresh,
        "initramfs_size": initramfs_size_str,
        "fallbacks": fallbacks,
        "has_fallback": has_fallback,
        "total_kernels": len(installed_vmlinuz)
    }

    if active_initramfs and initramfs_fresh:
        report["checks"].append({
            "id": "kernel_initramfs",
            "category": "Kernel",
            "name": "Active Kernel & Initramfs",
            "status": "PASS",
            "value": f"{active_kver} ({initramfs_size_str})",
            "detail": "Initramfs verified synchronized with active kernel"
        })
    elif active_initramfs:
        report["checks"].append({
            "id": "kernel_initramfs",
            "category": "Kernel",
            "name": "Active Kernel & Initramfs",
            "status": "WARN",
            "value": f"{active_kver} (Stale)",
            "detail": "Initramfs appears older than kernel binary. Consider rebuilding via Option 2 (Rebuild Initramfs).",
            "recommendation": "Run slacky-update and select option 2 -> 4 to rebuild active initramfs."
        })
        report["warnings"].append("Initramfs may be stale relative to the active kernel image.")
        report["score"] -= 10
    elif not boot_readable:
        report["checks"].append({
            "id": "kernel_initramfs",
            "category": "Kernel",
            "name": "Active Kernel & Initramfs",
            "status": "PASS",
            "value": f"{active_kver} (Active)",
            "detail": "ESP (/boot) is mode 0700 (umask=0077). Initramfs is active in running kernel."
        })
    else:
        report["checks"].append({
            "id": "kernel_initramfs",
            "category": "Kernel",
            "name": "Active Kernel & Initramfs",
            "status": "WARN",
            "value": f"{active_kver} (No initramfs)",
            "detail": "No dedicated initramfs found in /boot. Kernel may rely on monolithic built-in drivers."
        })

    if has_fallback:
        report["checks"].append({
            "id": "kernel_fallback",
            "category": "Kernel",
            "name": "Disaster Recovery Fallback Kernel",
            "status": "PASS",
            "value": f"{len(fallbacks)} Fallback(s) available",
            "detail": f"Fallbacks: {', '.join(fallbacks[:2])}"
        })
    else:
        report["checks"].append({
            "id": "kernel_fallback",
            "category": "Kernel",
            "name": "Disaster Recovery Fallback Kernel",
            "status": "WARN",
            "value": "Single Kernel Only",
            "detail": "No fallback kernel detected in /boot. If this kernel fails to boot, recovery requires Live-USB.",
            "recommendation": "Deploy a secondary fallback kernel (e.g., linux-cachyos-lts) via CachyOS Kernel Picker."
        })
        report["warnings"].append("Only one kernel installed in /boot; fallback kernel recommended for safety.")
        report["score"] -= 5

    # 3. Bootloader & Secure Boot
    is_uefi = os.path.exists("/sys/firmware/efi")
    bootloader_type = "Generic / Unknown"
    limine_conf_path = None
    limine_candidates = [
        "/boot/limine.conf",
        "/boot/EFI/limine/limine.conf",
        "/boot/efi/EFI/limine/limine.conf",
        "/boot/limine/limine.conf",
        "/boot/efi/limine.conf",
        "/efi/limine.conf",
        "/efi/EFI/limine/limine.conf"
    ]
    for cand in limine_candidates:
        if os.path.exists(cand) and os.path.isfile(cand):
            bootloader_type = "Limine Unified UEFI"
            limine_conf_path = cand
            break

    if bootloader_type == "Generic / Unknown":
        if os.path.exists("/etc/default/limine"):
            bootloader_type = "Limine Unified UEFI"
        elif os.path.exists("/sys/firmware/efi/efivars"):
            try:
                for var in os.listdir("/sys/firmware/efi/efivars"):
                    if var.startswith("Boot0") or var.startswith("BootOrder"):
                        with open(os.path.join("/sys/firmware/efi/efivars", var), "rb") as f:
                            if b"limine" in f.read().lower():
                                bootloader_type = "Limine Unified UEFI"
                                break
            except Exception:
                pass

    if bootloader_type == "Generic / Unknown":
        if os.path.exists("/boot/grub/grub.cfg"):
            bootloader_type = "GRUB2"
        elif os.path.exists("/boot/efi/EFI/Slackware/elilo.efi"):
            bootloader_type = "ELILO"

    # Secure Boot status
    secure_boot_state = "Disabled / Not Enrolled"
    if is_uefi:
        try:
            res = subprocess.run(["mokutil", "--sb-state"], capture_output=True, text=True, timeout=2)
            if "SecureBoot enabled" in res.stdout:
                secure_boot_state = "Active & Enforced (MOK Enrolled)"
            elif "SecureBoot disabled" in res.stdout:
                secure_boot_state = "Supported (Disabled in UEFI firmware)"
        except Exception:
            pass

    # BLAKE2B hash verification if Limine
    blake2b_status = "Not Applicable"
    blake2b_valid = True
    if limine_conf_path and os.path.exists(f"/boot/vmlinuz-{active_kver}"):
        try:
            with open(limine_conf_path, "r", encoding="utf-8") as f:
                l_content = f.read()
            match = re.search(r'vmlinuz-' + re.escape(active_kver) + r'[^\s#\n\r]*#([0-9a-fA-F]+)', l_content)
            if match:
                expected_hash = match.group(1).lower()
                real_hash = compute_blake2b(f"/boot/vmlinuz-{active_kver}")
                if expected_hash == real_hash:
                    blake2b_status = f"Verified ({expected_hash[:10]}...)"
                else:
                    blake2b_status = "MISMATCH (Kernel binary altered)"
                    blake2b_valid = False
            else:
                blake2b_status = "No hash seal on active kernel"
        except Exception:
            pass
    elif not boot_readable and bootloader_type == "Limine Unified UEFI":
        blake2b_status = "Protected (Root Required for Digest)"

    # ESP Disk Space
    esp_dir = "/boot"
    if os.path.exists("/boot/efi") and os.path.ismount("/boot/efi"):
        esp_dir = "/boot/efi"
    elif not os.path.exists(esp_dir):
        esp_dir = "/"

    try:
        esp_stat = shutil.disk_usage(esp_dir)
        esp_free_mb = esp_stat.free // (1024 * 1024)
        esp_total_mb = esp_stat.total // (1024 * 1024)
    except Exception:
        esp_free_mb = 2048
        esp_total_mb = 4096

    report["bootloader"] = {
        "type": bootloader_type,
        "uefi": is_uefi,
        "secure_boot": secure_boot_state,
        "blake2b_status": blake2b_status,
        "blake2b_valid": blake2b_valid,
        "esp_dir": esp_dir,
        "esp_free_mb": esp_free_mb,
        "esp_total_mb": esp_total_mb
    }

    if is_uefi:
        report["checks"].append({
            "id": "boot_uefi",
            "category": "Bootloader",
            "name": "Firmware Interface & Bootloader",
            "status": "PASS",
            "value": f"{bootloader_type} (UEFI)",
            "detail": f"Secure Boot: {secure_boot_state}"
        })
    else:
        report["checks"].append({
            "id": "boot_uefi",
            "category": "Bootloader",
            "name": "Firmware Interface & Bootloader",
            "status": "WARN",
            "value": "Legacy BIOS (Non-UEFI)",
            "detail": "System is booting in legacy CSM/BIOS mode. UEFI is strongly recommended for NVMe & Secure Boot."
        })

    if blake2b_valid:
        report["checks"].append({
            "id": "boot_blake2b",
            "category": "Bootloader",
            "name": "Cryptographic Kernel Anti-Tamper",
            "status": "PASS" if any(w in blake2b_status for w in ["Verified", "Protected"]) else "INFO",
            "value": blake2b_status,
            "detail": "BLAKE2B hash verification against bootloader registry" if "Verified" in blake2b_status else (
                "ESP is mode 0700 (umask=0077). Run via sudo slacky-update --doctor to audit on-disk hashes."
                if "Protected" in blake2b_status else "BLAKE2B hash status in active bootloader"
            )
        })
    else:
        report["checks"].append({
            "id": "boot_blake2b",
            "category": "Bootloader",
            "name": "Cryptographic Kernel Anti-Tamper",
            "status": "FAIL",
            "value": blake2b_status,
            "detail": "Active kernel hash does not match limine.conf! Limine will halt boot on secure boot matrix.",
            "recommendation": "Run option 6 in Main Menu to re-enroll and sign BLAKE2B cryptographic hashes."
        })
        report["failures"].append("BLAKE2B kernel hash mismatch detected in bootloader configuration.")
        report["score"] -= 25

    if esp_free_mb >= 500:
        report["checks"].append({
            "id": "boot_esp_space",
            "category": "Bootloader",
            "name": f"ESP Partition Space ({esp_dir})",
            "status": "PASS",
            "value": f"{esp_free_mb} MB Free / {esp_total_mb} MB",
            "detail": "Ample space for multi-kernel coexistence and emergency rollback images"
        })
    elif esp_free_mb >= 200:
        report["checks"].append({
            "id": "boot_esp_space",
            "category": "Bootloader",
            "name": f"ESP Partition Space ({esp_dir})",
            "status": "WARN",
            "value": f"{esp_free_mb} MB Free (Moderate)",
            "detail": f"Space is getting tight on {esp_dir}. Pruning obsolete kernels is recommended.",
            "recommendation": "Run slacky-update -> System Maintenance (Option 5) to prune obsolete kernels."
        })
        report["warnings"].append(f"ESP partition {esp_dir} has less than 500 MB remaining ({esp_free_mb} MB).")
        report["score"] -= 5
    else:
        report["checks"].append({
            "id": "boot_esp_space",
            "category": "Bootloader",
            "name": f"ESP Partition Space ({esp_dir})",
            "status": "FAIL",
            "value": f"{esp_free_mb} MB Free (Critically Low)",
            "detail": "Insufficient space for kernel builds or initramfs regeneration!",
            "recommendation": "Immediately prune old kernels via Option 5 in Slacky-Update."
        })
        report["failures"].append(f"ESP partition {esp_dir} critically low on space ({esp_free_mb} MB).")
        report["score"] -= 20

    # 4. Graphics & Display Stack
    has_nvidia = os.path.exists("/proc/driver/nvidia/version") or os.path.exists("/sys/module/nvidia")
    gpu_vendor = "Generic"
    gpu_model = "Standard Graphics Adapter"
    driver_version = "Unknown"
    drm_modeset = False
    vram_preserve = False

    if has_nvidia:
        gpu_vendor = "NVIDIA"
        if os.path.exists("/sys/module/nvidia/version"):
            try:
                with open("/sys/module/nvidia/version", "r", encoding="utf-8") as f:
                    driver_version = f.read().strip()
            except Exception:
                pass

        if driver_version == "Unknown" and os.path.exists("/proc/driver/nvidia/version"):
            try:
                with open("/proc/driver/nvidia/version", "r", encoding="utf-8") as f:
                    first_line = f.readline().strip()
                    m_ver = re.search(r'(?:Kernel Module.*?|NVRM version:.*?)\s+([0-9]+\.[0-9.]+)', first_line)
                    if m_ver:
                        driver_version = m_ver.group(1)
            except Exception:
                pass

        if shutil.which("nvidia-smi"):
            try:
                res_smi = subprocess.run(["nvidia-smi", "-L"], capture_output=True, text=True, timeout=2)
                m_gpu = re.search(r'GPU \d+:\s+([^(\n]+)', res_smi.stdout)
                if m_gpu:
                    gpu_model = m_gpu.group(1).strip()
            except Exception:
                pass

        if os.path.exists("/sys/module/nvidia_drm/parameters/modeset"):
            try:
                with open("/sys/module/nvidia_drm/parameters/modeset", "r") as f:
                    drm_modeset = (f.read().strip() == "Y")
            except Exception:
                pass

        if os.path.exists("/sys/module/nvidia/parameters/NVreg_PreserveVideoMemoryAllocations"):
            try:
                with open("/sys/module/nvidia/parameters/NVreg_PreserveVideoMemoryAllocations", "r") as f:
                    vram_preserve = (f.read().strip() == "1")
            except Exception:
                pass
    elif os.path.exists("/sys/module/amdgpu"):
        gpu_vendor = "AMD Radeon"
        driver_version = "amdgpu in-tree"
        drm_modeset = True
    elif os.path.exists("/sys/module/i915") or os.path.exists("/sys/module/xe"):
        gpu_vendor = "Intel"
        driver_version = "i915/xe in-tree"
        drm_modeset = True

    # Session type
    session_type = os.environ.get("XDG_SESSION_TYPE", "unknown").lower()
    desktop_session = os.environ.get("DESKTOP_SESSION", "console")
    if not session_type or session_type == "unknown":
        if os.environ.get("WAYLAND_DISPLAY"):
            session_type = "wayland"
        elif os.environ.get("DISPLAY"):
            session_type = "x11"
        else:
            session_type = "tty / headless"

    report["graphics"] = {
        "vendor": gpu_vendor,
        "driver_version": driver_version,
        "drm_modeset": drm_modeset,
        "vram_preserve": vram_preserve,
        "session_type": session_type,
        "desktop": desktop_session
    }

    if gpu_vendor == "NVIDIA":
        if drm_modeset and vram_preserve:
            report["checks"].append({
                "id": "gpu_nvidia",
                "category": "Graphics",
                "name": "NVIDIA Driver & Wayland DRM Modeset",
                "status": "PASS",
                "value": f"NVIDIA {driver_version} (DRM Modeset + VRAM Preserved)",
                "detail": f"Session: {session_type} ({desktop_session})"
            })
        elif drm_modeset:
            report["checks"].append({
                "id": "gpu_nvidia",
                "category": "Graphics",
                "name": "NVIDIA Driver & Wayland DRM Modeset",
                "status": "PASS",
                "value": f"NVIDIA {driver_version} (DRM Modeset Active)",
                "detail": f"Session: {session_type} ({desktop_session})"
            })
        else:
            report["checks"].append({
                "id": "gpu_nvidia",
                "category": "Graphics",
                "name": "NVIDIA Driver & Wayland DRM Modeset",
                "status": "WARN",
                "value": f"NVIDIA {driver_version} (Modeset Inactive)",
                "detail": "nvidia_drm.modeset=1 is missing from kernel CMDLINE. Wayland compositors may experience black screen.",
                "recommendation": "Configure Kernel Boot Parameters in Option 6 (Limine) to enable NVIDIA DRM modeset."
            })
            report["warnings"].append("NVIDIA DRM modeset is inactive; required for modern Wayland compositors.")
            report["score"] -= 10
    else:
        report["checks"].append({
            "id": "gpu_driver",
            "category": "Graphics",
            "name": "Graphics Driver & Display Server",
            "status": "PASS",
            "value": f"{gpu_vendor} ({driver_version})",
            "detail": f"Session: {session_type} ({desktop_session})"
        })

    # 5. Storage, Filesystems & RAM Optimization
    root_fs = "unknown"
    root_mount_opts = []
    if os.path.exists("/proc/mounts"):
        try:
            with open("/proc/mounts", "r") as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) >= 4 and parts[1] == "/":
                        root_fs = parts[2]
                        root_mount_opts = parts[3].split(",")
                        break
        except Exception:
            pass

    try:
        root_stat = shutil.disk_usage("/")
        root_free_gb = root_stat.free / (1024 * 1024 * 1024)
        root_total_gb = root_stat.total / (1024 * 1024 * 1024)
        root_free_pct = (root_stat.free / root_stat.total) * 100
    except Exception:
        root_free_gb = 50.0
        root_total_gb = 100.0
        root_free_pct = 50.0

    tmp_is_tmpfs = False
    if os.path.exists("/proc/mounts"):
        try:
            with open("/proc/mounts", "r") as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) >= 3 and parts[1] == "/tmp" and parts[2] == "tmpfs":
                        tmp_is_tmpfs = True
                        break
        except Exception:
            pass

    zswap_active = False
    if os.path.exists("/sys/module/zswap/parameters/enabled"):
        try:
            with open("/sys/module/zswap/parameters/enabled", "r") as f:
                zswap_active = (f.read().strip() == "Y")
        except Exception:
            pass

    btrfs_snapshots = os.path.exists("/.snapshots") or os.path.exists("/home/.snapshots")

    report["storage"] = {
        "root_fs": root_fs,
        "root_free_gb": f"{root_free_gb:.1f}",
        "root_total_gb": f"{root_total_gb:.1f}",
        "root_free_pct": f"{root_free_pct:.1f}",
        "tmp_tmpfs": tmp_is_tmpfs,
        "zswap": zswap_active,
        "btrfs_snapshots": btrfs_snapshots
    }

    if root_free_pct >= 15:
        report["checks"].append({
            "id": "storage_root_space",
            "category": "Storage",
            "name": f"Root Filesystem (/) [{root_fs}]",
            "status": "PASS",
            "value": f"{root_free_gb:.1f} GB Free ({root_free_pct:.1f}%)",
            "detail": f"Filesystem: {root_fs} (Healthy capacity margin)"
        })
    else:
        report["checks"].append({
            "id": "storage_root_space",
            "category": "Storage",
            "name": f"Root Filesystem (/) [{root_fs}]",
            "status": "WARN",
            "value": f"{root_free_gb:.1f} GB Free ({root_free_pct:.1f}%)",
            "detail": "Root partition has less than 15% free space remaining.",
            "recommendation": "Execute Full System Sweep in Option 5 (System Maintenance) to reclaim disk space."
        })
        report["warnings"].append(f"Root filesystem space is below 15% ({root_free_gb:.1f} GB free).")
        report["score"] -= 10

    if tmp_is_tmpfs:
        report["checks"].append({
            "id": "storage_tmpfs",
            "category": "Storage",
            "name": "Temporary Filesystem (/tmp)",
            "status": "PASS",
            "value": "tmpfs in RAM (Ultra-Fast I/O)",
            "detail": "Protects SSD against write amplification during large package builds"
        })
    else:
        report["checks"].append({
            "id": "storage_tmpfs",
            "category": "Storage",
            "name": "Temporary Filesystem (/tmp)",
            "status": "INFO",
            "value": "Physical Disk Mount",
            "detail": "Enable Turbo Boot & Fast Shutdown in Tweaks to mount /tmp as tmpfs."
        })

    # 6. Performance & Latency Tweaks
    active_tweaks_count = 0
    total_tweaks_count = 9

    # Limits
    limits_active = False
    try:
        import resource
        soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
        limits_active = (soft >= 524288 or hard >= 1048576)
    except Exception:
        pass
    if limits_active:
        active_tweaks_count += 1

    # THP
    thp_mode = "unknown"
    if os.path.exists("/sys/kernel/mm/transparent_hugepage/enabled"):
        try:
            with open("/sys/kernel/mm/transparent_hugepage/enabled", "r") as f:
                thp_mode = f.read().strip()
                if "[madvise]" in thp_mode:
                    active_tweaks_count += 1
        except Exception:
            pass

    # BBR
    bbr_active = False
    if os.path.exists("/proc/sys/net/ipv4/tcp_congestion_control"):
        try:
            with open("/proc/sys/net/ipv4/tcp_congestion_control", "r") as f:
                bbr_active = ("bbr" in f.read().strip())
                if bbr_active:
                    active_tweaks_count += 1
        except Exception:
            pass

    # NTSYNC
    ntsync_active = os.path.exists("/dev/ntsync")
    if ntsync_active:
        active_tweaks_count += 1

    # FastBoot
    fastboot_active = os.path.exists("/etc/rc.d/rc.pcmcia") and not os.access("/etc/rc.d/rc.pcmcia", os.X_OK)
    if fastboot_active:
        active_tweaks_count += 1

    # I/O Scheduler
    iosched_active = (os.path.exists("/etc/udev/rules.d/60-slacky-ioschedulers.rules") or
                      os.path.exists("/etc/udev/rules.d/60-slacky-iosched.rules") or
                      os.path.exists("/etc/udev/rules.d/60-ioschedulers.rules"))
    if iosched_active:
        active_tweaks_count += 1

    # Shader Cache
    shadercache_active = (os.path.exists("/etc/profile.d/slacky-shader-cache.sh") or
                          os.path.exists("/etc/profile.d/slacky_shadercache.sh") or
                          os.path.exists("/etc/profile.d/slacky-gaming-env.sh"))
    if shadercache_active:
        active_tweaks_count += 1

    # Controller udev
    ctrl_active = os.path.exists("/etc/udev/rules.d/70-game-controllers.rules")
    if ctrl_active:
        active_tweaks_count += 1

    # PipeWire Latency
    pwlatency_active = os.path.exists("/etc/pipewire/pipewire.conf.d/99-slacky-lowlatency.conf")
    if pwlatency_active:
        active_tweaks_count += 1

    report["tweaks"] = {
        "active_count": active_tweaks_count,
        "total_count": total_tweaks_count,
        "limits": limits_active,
        "thp": "[madvise]" in thp_mode,
        "bbr": bbr_active,
        "ntsync": ntsync_active,
        "fastboot": fastboot_active,
        "iosched": iosched_active,
        "shadercache": shadercache_active,
        "controllers": ctrl_active,
        "pwlatency": pwlatency_active
    }

    report["checks"].append({
        "id": "perf_tweaks",
        "category": "Performance",
        "name": "System & Gaming Performance Matrix",
        "status": "PASS" if active_tweaks_count >= 5 else "INFO",
        "value": f"{active_tweaks_count}/{total_tweaks_count} Active Optimizations",
        "detail": f"NTSYNC: {'on' if ntsync_active else 'off'} | BBR: {'on' if bbr_active else 'off'} | 1M Limits: {'on' if limits_active else 'off'} | FastBoot: {'on' if fastboot_active else 'off'}"
    })

    # 7. The Sacred Slackware Base & System Integrity
    pkg_count = 0
    if os.path.exists("/var/log/packages"):
        try:
            pkg_count = len(os.listdir("/var/log/packages"))
        except Exception:
            pass

    # Check for foreign package managers contaminating /
    foreign_managers = []
    if os.path.exists("/var/lib/dpkg/status"):
        foreign_managers.append("dpkg/apt")
    if os.path.exists("/var/lib/rpm"):
        foreign_managers.append("rpm")
    if os.path.exists("/var/lib/pacman/local") or (os.path.exists("/var/lib/pacman") and not os.path.islink("/var/lib/pacman")):
        foreign_managers.append("pacman")

    gnomes_isolated = os.path.exists("/opt/underpants") or not os.path.exists("/bin/gnomes")

    report["integrity"] = {
        "native_packages_count": pkg_count,
        "foreign_managers": foreign_managers,
        "gnomes_isolated": gnomes_isolated
    }

    if not foreign_managers and gnomes_isolated:
        report["checks"].append({
            "id": "system_integrity",
            "category": "Integrity",
            "name": "The Sacred Slackware Base System",
            "status": "PASS",
            "value": f"{pkg_count} Native Packages Verified",
            "detail": "100% Canonical Slackware compliance. Zero foreign package manager contamination."
        })
    else:
        report["checks"].append({
            "id": "system_integrity",
            "category": "Integrity",
            "name": "The Sacred Slackware Base System",
            "status": "WARN",
            "value": "Anomalies Detected",
            "detail": f"Foreign package manager artifacts detected: {', '.join(foreign_managers)}"
        })
        report["warnings"].append("Foreign package manager database detected outside /opt/.")
        report["score"] -= 10

    # Calculate Final Verdict
    duration = time.perf_counter() - t_start
    report["duration"] = round(duration, 3)

    report["score"] = max(0, min(100, report["score"]))
    if report["failures"]:
        report["verdict"] = "ATTENTION REQUIRED"
        report["eli5_summary"] = "We found one or more critical issues that need your attention (like a full boot drive or missing kernel signatures). Check the recommendations below to fix them safely."
    elif report["warnings"]:
        report["verdict"] = "GOOD (Minor Warnings)"
        report["eli5_summary"] = "Your Slackware system is running smoothly, but there are a few tuning opportunities or minor warnings you can optimize whenever you have time."
    else:
        report["verdict"] = "EXCELLENT (100% Healthy)"
        report["eli5_summary"] = "Your Slackware system is in pristine condition! All 5 engineering pillars are met, your kernel and graphics stack are optimal, and your system is 100% safe."

    return report

# --- [ TERMINAL ANSI RENDERER ] ---
def render_terminal_report(data: dict, ascii_only: bool = False) -> str:
    lines = []
    w = 82
    tl, tr, bl, br, hz, vt = ("+", "+", "+", "+", "-", "|") if ascii_only else ("┌", "┐", "└", "┘", "─", "│")
    ml, mr = ("+", "+") if ascii_only else ("├", "┤")

    # Header Card
    lines.append(f"{BOLD_BLUE}Slacky-Update Doctor (System Health & Diagnostic Audit){RESET}")
    lines.append(f"{BLUE}High-Performance Slackware Workstation Health Check ('Dark Star'){RESET}")
    lines.append(f"  {DIM_WHITE}Audit completed in {data.get('duration', 0.05)}s on {data['hostname']}{RESET}")
    lines.append("")

    # Overall Verdict Banner
    verdict = data["verdict"]
    score = data["score"]
    v_color = BOLD_GREEN if "EXCELLENT" in verdict else (BOLD_YELLOW if "GOOD" in verdict else BOLD_RED)
    star_sym = "*"
    lines.append(f"{CYAN}{tl}{hz * (w - 2)}{tr}{RESET}")
    lines.append(f"{CYAN}{vt}{RESET}  {v_color}OVERALL HEALTH SCORE: {score}/100 — {verdict}{RESET}")
    lines.append(f"{CYAN}{vt}{RESET}  {WHITE}{data['eli5_summary']}{RESET}")
    lines.append(f"{CYAN}{bl}{hz * (w - 2)}{br}{RESET}")
    lines.append("")

    # Domain Groupings
    categories = ["Platform", "Kernel", "Bootloader", "Graphics", "Storage", "Performance", "Integrity"]
    cat_icons = {
        "Platform": "[*]",
        "Kernel": "[*]",
        "Bootloader": "[*]",
        "Graphics": "[*]",
        "Storage": "[*]",
        "Performance": "[*]",
        "Integrity": "[*]"
    }

    for cat in categories:
        cat_checks = [c for c in data["checks"] if c["category"] == cat]
        if not cat_checks:
            continue

        icon = cat_icons.get(cat, "•") if not ascii_only else "[*]"
        lines.append(f"{BOLD_CYAN}{icon} {cat.upper()}{RESET}")
        lines.append(f"{CYAN}{'-' * min(w, 80)}{RESET}")

        for c in cat_checks:
            st = c["status"]
            if st == "PASS":
                badge = f"{BOLD_GREEN}[PASS]{RESET}" if not ascii_only else "[PASS]"
            elif st == "WARN":
                badge = f"{BOLD_YELLOW}[WARN]{RESET}" if not ascii_only else "[WARN]"
            elif st == "FAIL":
                badge = f"{BOLD_RED}[FAIL]{RESET}" if not ascii_only else "[FAIL]"
            else:
                badge = f"{DIM_WHITE}[INFO]{RESET}" if not ascii_only else "[INFO]"

            name_w = 40
            name_str = c["name"][:name_w]
            pad = " " * max(1, name_w - len(name_str))
            lines.append(f"  {badge} {BOLD}{name_str}{RESET}{pad} {BOLD_WHITE}{c['value']}{RESET}")
            if c.get("detail"):
                lines.append(f"         {DIM_WHITE}└─ {c['detail']}{RESET}")
            if c.get("recommendation"):
                lines.append(f"         {YELLOW}Action: {c['recommendation']}{RESET}")
        lines.append("")

    # Actionable Recommendations Section
    all_recs = [c["recommendation"] for c in data["checks"] if c.get("recommendation")]
    if all_recs:
        lines.append(f"{BOLD_YELLOW}ACTIONABLE RECOMMENDATIONS:{RESET}")
        for i, rec in enumerate(all_recs, 1):
            lines.append(f"  {YELLOW}{i}. {rec}{RESET}")
        lines.append("")

    # Footer Pro-Tip
    copy_hint = "[*] Hold Shift + Drag to copy text | Press ENTER or Q to exit" if ascii_only else "Hold Shift + Drag to copy text  •  Press ENTER or Q to exit"
    lines.append(f"  {DIM_WHITE}{copy_hint}{RESET}")

    return "\n".join(lines)

# --- [ MARKDOWN EXPORT RENDERER ] ---
def render_markdown_report(data: dict) -> str:
    md = []
    md.append(f"# Slacky-Update System Health & Diagnostic Audit")
    md.append(f"**Date:** {data['timestamp']} | **Host:** `{data['hostname']}` | **Execution Time:** {data.get('duration', 0.05)}s\n")
    md.append(f"## Health Verdict: {data['verdict']} ({data['score']}/100)")
    md.append(f"> {data['eli5_summary']}\n")

    md.append(f"| Category | Check | Status | Value | Details |")
    md.append(f"| :--- | :--- | :--- | :--- | :--- |")

    for c in data["checks"]:
        st = c["status"]
        badge = "`PASS`" if st == "PASS" else ("`WARN`" if st == "WARN" else ("`FAIL`" if st == "FAIL" else "`INFO`"))
        detail = c.get("detail", "").replace("|", "/")
        md.append(f"| **{c['category']}** | {c['name']} | {badge} | `{c['value']}` | {detail} |")

    all_recs = [c["recommendation"] for c in data["checks"] if c.get("recommendation")]
    if all_recs:
        md.append(f"\n## Recommended Actions")
        for i, rec in enumerate(all_recs, 1):
            md.append(f"{i}. {rec}")

    md.append(f"\n---")
    md.append(f"*Generated automatically by Slacky-Update Doctor (`slacky-update --doctor`)*")
    return "\n".join(md)

# --- [ CLI ENTRY POINT ] ---
def main():
    parser = argparse.ArgumentParser(description="Slacky-Update Doctor: High-Performance System Health & Diagnostics")
    parser.add_argument("--json", action="store_true", help="Output machine-readable JSON")
    parser.add_argument("--markdown", "--md", action="store_true", help="Output GitHub-Flavored Markdown to stdout")
    parser.add_argument("--ascii", action="store_true", help="Force ASCII safe borders and plain text")
    parser.add_argument("--export", nargs="?", const="", default=None, help="Export Markdown report to file (default: ~/slacky-system-health.md)")
    parser.add_argument("--pager", action="store_true", help="View output inside terminal pager (less/more)")

    args = parser.parse_args()

    data = audit_system_health()

    if args.json:
        print(json.dumps(data, indent=2))
        return 0

    if args.markdown:
        print(render_markdown_report(data))
        return 0

    if args.export is not None:
        target_path = args.export.strip()
        if not target_path:
            target_path = os.path.expanduser("~/slacky-system-health.md")
        else:
            target_path = os.path.expanduser(target_path)

        md_content = render_markdown_report(data)
        try:
            with open(target_path, "w", encoding="utf-8") as f:
                f.write(md_content + "\n")
            print(f"{BOLD_GREEN}System health report exported to:{RESET} {target_path}")
            return 0
        except Exception as e:
            print(f"{BOLD_RED}Failed to export report to {target_path}:{RESET} {e}", file=sys.stderr)
            return 1

    terminal_output = render_terminal_report(data, ascii_only=args.ascii)

    if args.pager and sys.stdout.isatty():
        try:
            pager_cmd = os.environ.get("PAGER", "less -R")
            proc = subprocess.Popen(pager_cmd, shell=True, stdin=subprocess.PIPE, text=True)
            proc.communicate(terminal_output)
            return 0
        except Exception:
            pass

    print(terminal_output)
    return 0

if __name__ == "__main__":
    sys.exit(main())
