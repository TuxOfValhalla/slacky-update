#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Underpants Gnomes Universal Pacman Database & Mirror Engine (Slacky-Update)
Engineered for Slackware Linux (-current / 15.0+)

Provides standalone, in-memory parsing of Pacman sync databases (.db.tar.zst / .db.tar.gz),
sub-50ms query indexing, multi-repo mirror management, recursive Dependency DAG Solving
with Host Sovereignty Shielding, and automated Transmutation of upstream packages into
genuine Slackware .txz packages without requiring pacman or libalpm on the host system.
"""

import os
import sys
import json
import time
import re
import hashlib
import io
import tarfile
import shutil
import stat
import threading
import concurrent.futures
import urllib.request
import urllib.error
import subprocess
import glob
from typing import Dict, List, Optional, Any, Tuple, Set

# --- [ DEFAULT PATHS & CONSTANTS ] ---

DEFAULT_CACHE_BASE = "/var/cache/slacky-update/gnomes"
USER_CACHE_BASE = os.path.expanduser("~/.cache/slacky-update/gnomes")

DEFAULT_ARCH_MIRROR = "https://geo.mirror.pkgbuild.com"
DEFAULT_CACHYOS_MIRROR = "https://mirror.cachyos.org/repo"
DEFAULT_CHAOTIC_MIRROR = "https://cdn-mirror.chaotic.cx/chaotic-aur"

# Load fastest benchmarked mirrors if available
for _ranked_path in [os.path.expanduser("~/.cache/slacky-update/ranked_mirrors.json"),
                     "/var/cache/slacky-update/ranked_mirrors.json"]:
    if os.path.exists(_ranked_path):
        try:
            with open(_ranked_path, "r", encoding="utf-8") as _rf:
                _mdata = json.load(_rf)
                if _mdata.get("arch_primary"):
                    DEFAULT_ARCH_MIRROR = _mdata["arch_primary"]
                if _mdata.get("cachyos_primary"):
                    DEFAULT_CACHYOS_MIRROR = _mdata["cachyos_primary"]
                if _mdata.get("chaotic_primary"):
                    DEFAULT_CHAOTIC_MIRROR = _mdata["chaotic_primary"]
                break
        except Exception:
            pass

# Safety Guardrail: Strictly STABLE. Testing repos are permanently blacklisted.
BLACKLISTED_REPOS = {
    "core-testing", "extra-testing", "multilib-testing",
    "cachyos-testing", "cachyos-testing-v3", "cachyos-testing-v4", "testing"
}

# Core Host Packages: Protected base system packages that must NEVER overwrite Slackware root
CORE_EXCLUDES = {
    "glibc", "glibc-locales", "gcc-libs", "linux", "linux-headers",
    "systemd", "systemd-libs", "systemd-sysvcompat", "libsystemd", "libsystemd0", "libsystemd.so",
    "sysvinit", "sysvinit-tools", "pam", "shadow", "util-linux", "util-linux-libs",
    "coreutils", "bash", "filesystem", "pkgtools", "slackpkg", "eudev", "udev",
    "libudev", "libudev0", "libudev1", "libudev.so", "elogind", "libelogind", "libelogind.so",
    "polkit", "dbus", "kbd", "kmod", "iproute2", "net-tools", "procps-ng",
    "ca-certificates", "ca-certificates-utils", "iana-etc", "tzdata",
    "perl", "libgcc", "libstdc++", "binutils", "gcc", "make", "gmake", "patch", "diffutils", "findutils",
    "libtool", "libltdl", "m4", "autoconf", "automake", "bison", "flex", "texinfo",
    "pkgconf", "pkg-config", "pkgconfig", "groff", "man-db", "which", "gettext", "gettext-runtime",
    "cmake", "meson", "ninja", "readline", "libreadline", "xz", "liblzma", "zstd", "libzstd"
}

# Virtual Providers: Generic interfaces satisfied by Slackware base or graphics drivers
VIRTUAL_PROVIDES_DEFAULT = {
    "libgl": "host:libGL.so.1",
    "libgl.so": "host:libGL.so.1",
    "libegl": "host:libEGL.so.1",
    "libegl.so": "host:libEGL.so.1",
    "libgles": "host:libGLESv2.so.2",
    "opengl-driver": "host:graphics-driver",
    "vulkan-driver": "host:vulkan-icd",
    "vulkan-icd-loader": "host:libvulkan.so.1",
    "sh": "host:/bin/sh",
    "bash": "host:/bin/bash",
    "awk": "host:/usr/bin/gawk",
    "sed": "host:/usr/bin/sed",
    "tar": "host:/usr/bin/tar",
    "coreutils": "host:/usr/bin/coreutils",
    "desktop-file-utils": "host:/usr/bin/update-desktop-database",
    "hicolor-icon-theme": "host:/usr/share/icons/hicolor",
    "shared-mime-info": "host:/usr/bin/update-mime-database",
    "glib2": "host:/usr/lib64/libglib-2.0.so.0",
    "libdbus": "host:/usr/lib64/libdbus-1.so.3",
    "dbus": "host:/usr/bin/dbus-daemon",
    "libsystemd": "host:libelogind.so.0",
    "libsystemd.so": "host:libelogind.so.0",
    "systemd-libs": "host:libelogind.so.0",
    "libudev": "host:libudev.so.1",
    "libudev.so": "host:libudev.so.1",
    "pipewire": "host:pipewire-system",
    "pulse-audio": "host:pulseaudio-system",
    "pulseaudio": "host:pulseaudio-system",
    "jack": "host:pipewire-jack",
    "jack2": "host:pipewire-jack",
    "libjack.so": "host:libjack.so.0",
    "x-display-server": "host:xorg-server",
    "wayland": "host:libwayland-client.so.0",
    "wayland-protocols": "host:wayland-protocols",
    "libwayland-client": "host:libwayland-client.so.0",
    "libwayland-client.so": "host:libwayland-client.so.0",
    "libwayland-server": "host:libwayland-server.so.0",
    "libwayland-server.so": "host:libwayland-server.so.0",
    "libwayland-cursor": "host:libwayland-cursor.so.0",
    "libwayland-egl": "host:libwayland-egl.so.1",
    "libxkbcommon": "host:libxkbcommon.so.0",
    "libxkbcommon.so": "host:libxkbcommon.so.0",
    "libseat": "host:libseat.so.1",
    "libseat.so": "host:libseat.so.1",
    "seatd": "host:seatd",
    "polkit": "host:polkit-1",
    "libpolkit-gobject-1.so": "host:libpolkit-gobject-1.so.0",
    "java-runtime": "host:openjdk",
    "java-environment": "host:openjdk-jdk",
    "ntsync-module": "host:kernel-ntsync-module",
    "virtualbox-guest-modules": "host:virtualbox-guest-modules",
    "virtualbox-host-modules": "host:virtualbox-host-modules",
    "rfkill": "host:util-linux",
    "fuse": "host:fuse3",
    "fuse2": "host:fuse",
    "libfuse.so": "host:libfuse.so.2",
    "libfuse3.so": "host:libfuse3.so.3",
    "libltdl": "host:/usr/lib64/libltdl.so.7",
    "libltdl.so": "host:/usr/lib64/libltdl.so.7",
    "libltdl.so.7": "host:/usr/lib64/libltdl.so.7",
    "libtool": "host:/usr/bin/libtool",
    "pkgconfig": "host:/usr/bin/pkg-config",
    "pkg-config": "host:/usr/bin/pkg-config",
    "pkgconf": "host:/usr/bin/pkgconf",
    "m4": "host:/usr/bin/m4",
    "autoconf": "host:/usr/bin/autoconf",
    "automake": "host:/usr/bin/automake",
    "bison": "host:/usr/bin/bison",
    "flex": "host:/usr/bin/flex",
    "gettext": "host:/usr/bin/gettext",
    "which": "host:/usr/bin/which",
    "readline": "host:/lib64/libreadline.so.8",
    "libreadline": "host:/lib64/libreadline.so.8",
    "libreadline.so": "host:/lib64/libreadline.so.8",
    "libreadline.so.8": "host:/lib64/libreadline.so.8",
    "xz": "host:/usr/bin/xz",
    "liblzma": "host:/lib64/liblzma.so.5",
    "liblzma.so": "host:/lib64/liblzma.so.5",
    "liblzma.so.5": "host:/lib64/liblzma.so.5",
    "zstd": "host:/usr/bin/zstd",
    "libzstd": "host:/lib64/libzstd.so.1",
    "libzstd.so": "host:/lib64/libzstd.so.1",
    "libzstd.so.1": "host:/lib64/libzstd.so.1"
}

PROTECTED_HOST_BINARIES = {
    "python", "python3", "python2", "python3.11", "python3.12", "python3.14",
    "python-config", "python3-config", "python3.12-config", "python3.14-config",
    "pip", "pip3", "idle", "idle3", "idle3.14", "pydoc", "pydoc3", "pydoc3.14",
    "bash", "sh", "zsh", "csh", "tcsh", "fish", "sed", "awk", "gawk", "grep", "egrep", "fgrep",
    "tar", "gzip", "gunzip", "bzip2", "bunzip2", "xz", "unxz", "zstd", "unzstd", "zip", "unzip",
    "find", "xargs", "ls", "cp", "mv", "rm", "mkdir", "rmdir", "chmod", "chown", "cat", "more", "less",
    "make", "gcc", "g++", "clang", "clang++", "ld", "as", "git", "sudo", "su", "login", "passwd",
    "curl", "wget", "ssh", "scp", "systemctl", "init", "shutdown", "reboot", "poweroff", "upgradepkg",
    "installpkg", "removepkg", "slackpkg", "pkgtool", "makepkg", "explodepkg", "wheel"
}

# Modular Application Plugins: Companion plugins automatically required for headless/modular apps
MODULAR_APP_PLUGINS: Dict[str, List[str]] = {
    "zathura": ["zathura-pdf-poppler"],
    "openscad": ["qt5-wayland", "qt5-svg", "qt5-multimedia"],
    "qt5-base": ["qt5-wayland", "qt5-svg"],
    "qt6-base": ["qt6-wayland", "qt6-svg", "qt6-declarative"],
    "libreoffice-fresh": ["gtk3", "librsvg", "gdk-pixbuf2"],
    "libreoffice-still": ["gtk3", "librsvg", "gdk-pixbuf2"],
    "glycin": ["glycin-loaders"],
    "libglycin": ["glycin-loaders"],
    "filezilla": ["glycin-loaders", "librsvg"],
    "gtk4": ["glycin-loaders"],
}



def get_cache_dir() -> str:
    """Resolve writable cache directory for databases and package index."""
    for d in [DEFAULT_CACHE_BASE, USER_CACHE_BASE, "/tmp/slacky-update-gnomes"]:
        try:
            os.makedirs(d, exist_ok=True)
            test_file = os.path.join(d, ".write_test")
            with open(test_file, "w") as f:
                f.write("1")
            os.remove(test_file)
            return d
        except Exception:
            continue
    return "/tmp"


def detect_cpu_tier() -> str:
    """Detect CPU microarchitecture tier (znver4, v4, v3, generic)."""
    cpuinfo = "/proc/cpuinfo"
    if not os.path.exists(cpuinfo):
        return "generic"
    try:
        with open(cpuinfo, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
        if all(flag in content for flag in ["avx512f", "avx512bw", "avx512cd", "avx512dq", "avx512vl"]):
            if "AuthenticAMD" in content:
                return "znver4"
            return "v4"
        elif all(flag in content for flag in ["avx2", "fma", "bmi1", "bmi2"]):
            return "v3"
    except Exception:
        pass
    return "generic"


# --- [ REPOSITORY MATRIX ] ---

def get_default_repositories(cpu_tier: Optional[str] = None) -> List[Dict[str, Any]]:
    """Return priority-ordered list of repositories based on CPU tier."""
    tier = cpu_tier or detect_cpu_tier()
    repos: List[Dict[str, Any]] = []

    # 1. CachyOS Tier-Optimized Repositories
    if tier == "znver4":
        repos.append({
            "name": "cachyos-znver4",
            "url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_znver4/cachyos-znver4/cachyos-znver4.db.tar.zst",
            "base_url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_znver4/cachyos-znver4",
            "priority": 100
        })
        repos.append({
            "name": "cachyos-extra-znver4",
            "url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_znver4/cachyos-extra-znver4/cachyos-extra-znver4.db.tar.zst",
            "base_url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_znver4/cachyos-extra-znver4",
            "priority": 98
        })
        repos.append({
            "name": "cachyos-core-znver4",
            "url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_znver4/cachyos-core-znver4/cachyos-core-znver4.db.tar.zst",
            "base_url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_znver4/cachyos-core-znver4",
            "priority": 96
        })
        repos.append({
            "name": "cachyos-v4",
            "url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-v4/cachyos-v4.db.tar.zst",
            "base_url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-v4",
            "priority": 94
        })
        repos.append({
            "name": "cachyos-extra-v4",
            "url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-extra-v4/cachyos-extra-v4.db.tar.zst",
            "base_url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-extra-v4",
            "priority": 92
        })
        repos.append({
            "name": "cachyos-core-v4",
            "url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-core-v4/cachyos-core-v4.db.tar.zst",
            "base_url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-core-v4",
            "priority": 90
        })
    elif tier == "v4":
        repos.append({
            "name": "cachyos-v4",
            "url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-v4/cachyos-v4.db.tar.zst",
            "base_url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-v4",
            "priority": 100
        })
        repos.append({
            "name": "cachyos-extra-v4",
            "url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-extra-v4/cachyos-extra-v4.db.tar.zst",
            "base_url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-extra-v4",
            "priority": 98
        })
        repos.append({
            "name": "cachyos-core-v4",
            "url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-core-v4/cachyos-core-v4.db.tar.zst",
            "base_url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-core-v4",
            "priority": 96
        })
    elif tier == "v3":
        repos.append({
            "name": "cachyos-v3",
            "url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v3/cachyos-v3/cachyos-v3.db.tar.zst",
            "base_url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v3/cachyos-v3",
            "priority": 100
        })
        repos.append({
            "name": "cachyos-extra-v3",
            "url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v3/cachyos-extra-v3/cachyos-extra-v3.db.tar.zst",
            "base_url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v3/cachyos-extra-v3",
            "priority": 98
        })
        repos.append({
            "name": "cachyos-core-v3",
            "url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v3/cachyos-core-v3/cachyos-core-v3.db.tar.zst",
            "base_url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v3/cachyos-core-v3",
            "priority": 96
        })

    # 2. CachyOS Standard
    repos.append({
        "name": "cachyos",
        "url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64/cachyos/cachyos.db.tar.zst",
        "base_url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64/cachyos",
        "priority": 85
    })

    # 3. Arch Linux Extra (Largest official repository)
    repos.append({
        "name": "extra",
        "url": f"{DEFAULT_ARCH_MIRROR}/extra/os/x86_64/extra.db.tar.gz",
        "base_url": f"{DEFAULT_ARCH_MIRROR}/extra/os/x86_64",
        "priority": 70
    })

    # 4. Arch Linux Multilib (32-bit gaming / wine compatibility)
    repos.append({
        "name": "multilib",
        "url": f"{DEFAULT_ARCH_MIRROR}/multilib/os/x86_64/multilib.db.tar.gz",
        "base_url": f"{DEFAULT_ARCH_MIRROR}/multilib/os/x86_64",
        "priority": 60
    })

    # 5. Arch Linux Core (System dependencies)
    repos.append({
        "name": "core",
        "url": f"{DEFAULT_ARCH_MIRROR}/core/os/x86_64/core.db.tar.gz",
        "base_url": f"{DEFAULT_ARCH_MIRROR}/core/os/x86_64",
        "priority": 50
    })

    return repos


# --- [ HOST SHARED LIBRARY & GLIBC SCANNER ] ---

class HostLibraryScanner:
    """Scans host shared libraries and glibc version to enforce host sovereignty."""

    _cached_libs: Optional[Set[str]] = None
    _cached_glibc_ver: Optional[Tuple[int, int]] = None

    @classmethod
    def get_host_libraries(cls) -> Set[str]:
        """Scan ldconfig cache and filesystem to index all native sonames."""
        if cls._cached_libs is not None:
            return cls._cached_libs

        libs: Set[str] = set()

        # 1. Try reading ldconfig -p
        try:
            p = subprocess.Popen(["/sbin/ldconfig", "-p"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            stdout, _ = p.communicate(timeout=3)
            for line in stdout.splitlines():
                if "=>" in line:
                    parts = line.strip().split("=>")
                    soname = parts[0].split("(")[0].strip()
                    if soname:
                        libs.add(soname)
        except Exception:
            pass

        # 2. Filesystem scan fallback
        lib_dirs = ["/lib64", "/usr/lib64", "/usr/local/lib64", "/lib", "/usr/lib", "/usr/local/lib"]
        for d in lib_dirs:
            if os.path.isdir(d):
                try:
                    for fname in os.listdir(d):
                        if ".so" in fname:
                            libs.add(fname)
                            # Add clean soname (e.g., libz.so.1 from libz.so.1.3.1)
                            m = re.match(r"^(lib[a-zA-Z0-9_\-\+\.]+\.so(?:\.[0-9]+)*)", fname)
                            if m:
                                libs.add(m.group(1))
                except Exception:
                    pass

        cls._cached_libs = libs
        return cls._cached_libs

    @classmethod
    def get_host_glibc_version(cls) -> Tuple[int, int]:
        """Determine maximum supported GLIBC version (e.g. (2, 38) or (2, 40))."""
        if cls._cached_glibc_ver is not None:
            return cls._cached_glibc_ver

        max_ver = (2, 17)
        for libc_path in ["/lib64/libc.so.6", "/usr/lib64/libc.so.6", "/lib/libc.so.6", "/usr/lib/libc.so.6"]:
            if os.path.exists(libc_path):
                try:
                    with open(libc_path, "rb") as f:
                        data = f.read(1024 * 1024)
                    matches = re.findall(rb"GLIBC_2\.([0-9]+)", data)
                    for m in matches:
                        minor = int(m.decode("ascii"))
                        if (2, minor) > max_ver:
                            max_ver = (2, minor)
                    break
                except Exception:
                    pass

        cls._cached_glibc_ver = max_ver
        return cls._cached_glibc_ver

    _cached_frameworks: Optional[Dict[str, str]] = None

    @classmethod
    def get_host_frameworks(cls) -> Dict[str, str]:
        """Detect verified system frameworks and libraries provided natively by host Slackware."""
        if cls._cached_frameworks is not None:
            return cls._cached_frameworks

        frameworks: Dict[str, str] = {}
        libs = cls.get_host_libraries()

        def has_lib(pattern: str) -> bool:
            return any(pattern in s for s in libs)

        # 1. Desktop GUI, GTK & System Fonts
        if has_lib("libgtk-4.so"):
            frameworks["gtk4"] = "host:libgtk-4.so"
        if has_lib("libgtk-3.so"):
            frameworks["gtk3"] = "host:libgtk-3.so"
        if has_lib("libglib-2.0.so"):
            frameworks["glib2"] = "host:libglib-2.0.so"
        if has_lib("libgirepository-1.0.so") or has_lib("libgirepository-2.0.so"):
            frameworks["gobject-introspection-runtime"] = "host:libgirepository"
            frameworks["libgirepository"] = "host:libgirepository"
        if has_lib("libadwaita-1.so"):
            frameworks["libadwaita"] = "host:libadwaita"
        if has_lib("libgraphene-1.0.so"):
            frameworks["graphene"] = "host:libgraphene"
        if has_lib("libappstream.so"):
            frameworks["appstream"] = "host:libappstream"
        if has_lib("libcairo.so"):
            frameworks["cairo"] = "host:libcairo"
        if has_lib("libpango-1.0.so"):
            frameworks["pango"] = "host:libpango"
        if has_lib("libgdk_pixbuf-2.0.so"):
            frameworks["gdk-pixbuf2"] = "host:libgdk_pixbuf"
        if has_lib("libharfbuzz.so"):
            frameworks["harfbuzz"] = "host:libharfbuzz"
        if has_lib("libfreetype.so"):
            frameworks["freetype2"] = "host:libfreetype"
        if has_lib("libfontconfig.so"):
            frameworks["fontconfig"] = "host:libfontconfig"
        if has_lib("libatspi.so"):
            frameworks["at-spi2-core"] = "host:libatspi"
        if has_lib("libdconf.so") or shutil.which("dconf"):
            frameworks["dconf"] = "host:dconf"
        if os.path.exists("/usr/share/glib-2.0/schemas"):
            frameworks["gsettings-desktop-schemas"] = "host:gsettings-schemas"
            frameworks["gsettings-system-schemas"] = "host:gsettings-schemas"
        if os.path.exists("/usr/share/icons/Adwaita") or os.path.exists("/usr/share/icons/hicolor"):
            frameworks["adwaita-icon-theme"] = "host:adwaita-icon-theme"
            frameworks["adwaita-icon-theme-legacy"] = "host:adwaita-icon-theme"
            frameworks["adwaita-cursors"] = "host:adwaita-cursors"
            frameworks["adwaita-fonts"] = "host:adwaita-fonts"
            frameworks["hicolor-icon-theme"] = "host:hicolor-icon-theme"
        if has_lib("librsvg-2.so"):
            frameworks["librsvg"] = "host:librsvg"
        if has_lib("libfribidi.so"):
            frameworks["fribidi"] = "host:fribidi"
        if has_lib("libgraphite2.so"):
            frameworks["graphite"] = "host:graphite"
        if has_lib("libpixman-1.so"):
            frameworks["pixman"] = "host:pixman"
        if has_lib("libepoxy.so"):
            frameworks["libepoxy"] = "host:libepoxy"
        if has_lib("libjson-glib-1.0.so"):
            frameworks["json-glib"] = "host:json-glib"
        if has_lib("libsoup-3.0.so"):
            frameworks["libsoup3"] = "host:libsoup3"
        if has_lib("libsoup-2.4.so"):
            frameworks["libsoup"] = "host:libsoup"
        if shutil.which("icoextract"):
            frameworks["icoextract"] = "host:icoextract"
        if has_lib("libltdl.so"):
            frameworks["libltdl"] = "host:libltdl"
            frameworks["libtool"] = "host:libtool"

        # 3. Graphics, 3D, Mesa & LLVM
        if has_lib("libGLX_mesa.so") or has_lib("libgbm.so") or has_lib("libEGL_mesa.so"):
            frameworks["mesa"] = "host:mesa-driver"
        if has_lib("libdrm.so"):
            frameworks["libdrm"] = "host:libdrm"
        if has_lib("libGLdispatch.so"):
            frameworks["libglvnd"] = "host:libglvnd"
        if has_lib("libvulkan.so"):
            frameworks["vulkan-icd-loader"] = "host:libvulkan"
        if shutil.which("glxinfo") or os.path.exists("/usr/bin/glxinfo"):
            frameworks["mesa-utils"] = "host:glxinfo"
            frameworks["mesa-demos"] = "host:glxinfo"
        if shutil.which("vulkaninfo") or os.path.exists("/usr/bin/vulkaninfo"):
            frameworks["vulkan-tools"] = "host:vulkaninfo"
        if has_lib("libva.so"):
            frameworks["libva"] = "host:libva"
        if has_lib("libvdpau.so"):
            frameworks["libvdpau"] = "host:libvdpau"
        if has_lib("libLLVM"):
            frameworks["llvm-libs"] = "host:llvm-libs"

        # 4. Multimedia & Codecs
        if has_lib("libgstreamer-1.0.so"):
            frameworks["gstreamer"] = "host:gstreamer"
        if has_lib("libgstvideo-1.0.so"):
            frameworks["gst-plugins-base-libs"] = "host:gst-plugins-base-libs"
        if has_lib("libgstcodecparsers-1.0.so"):
            frameworks["gst-plugins-bad-libs"] = "host:gst-plugins-bad-libs"
        if has_lib("libavcodec.so") or has_lib("libavformat.so"):
            frameworks["ffmpeg"] = "host:ffmpeg"
        if has_lib("libpng16.so") or has_lib("libpng.so"):
            frameworks["libpng"] = "host:libpng"
        if has_lib("libjpeg.so"):
            frameworks["libjpeg-turbo"] = "host:libjpeg-turbo"
        if has_lib("libtiff.so"):
            frameworks["libtiff"] = "host:libtiff"
        if has_lib("libwebp.so"):
            frameworks["libwebp"] = "host:libwebp"
        if has_lib("libaom.so"):
            frameworks["aom"] = "host:aom"
        if has_lib("libdav1d.so"):
            frameworks["dav1d"] = "host:dav1d"
        if has_lib("libFLAC.so"):
            frameworks["flac"] = "host:flac"
        if has_lib("libopus.so"):
            frameworks["opus"] = "host:opus"
        if has_lib("libvorbis.so"):
            frameworks["libvorbis"] = "host:libvorbis"
        if has_lib("libasound.so"):
            frameworks["alsa-lib"] = "host:alsa-lib"
        if has_lib("libpipewire-0.3.so"):
            frameworks["libpipewire"] = "host:libpipewire"
            frameworks["pipewire"] = "host:pipewire"
        if has_lib("libpulse.so"):
            frameworks["pulseaudio"] = "host:pulseaudio"
            frameworks["libpulse"] = "host:libpulse"

        # 5. Core Libraries & Tools
        if has_lib("libsqlite3.so"):
            frameworks["sqlite"] = "host:sqlite"
            frameworks["sqlite3"] = "host:sqlite3"
        if has_lib("libcurl.so"):
            frameworks["curl"] = "host:curl"
        if has_lib("libssl.so") or has_lib("libcrypto.so"):
            frameworks["openssl"] = "host:openssl"
        if has_lib("libz.so"):
            frameworks["zlib"] = "host:zlib"
        if has_lib("libbz2.so"):
            frameworks["bzip2"] = "host:bzip2"
        if has_lib("liblzma.so"):
            frameworks["xz"] = "host:xz"
        if has_lib("libzstd.so"):
            frameworks["zstd"] = "host:zstd"
        if has_lib("libreadline.so"):
            frameworks["readline"] = "host:libreadline"
        if has_lib("libncurses.so") or has_lib("libncursesw.so"):
            frameworks["ncurses"] = "host:libncurses"
        if has_lib("libexpat.so"):
            frameworks["expat"] = "host:libexpat"
        if has_lib("libgdbm.so"):
            frameworks["gdbm"] = "host:libgdbm"
        if has_lib("libffi.so"):
            frameworks["libffi"] = "host:libffi"
        if has_lib("libsasl2.so"):
            frameworks["libsasl"] = "host:libsasl2"
            frameworks["cyrus-sasl"] = "host:libsasl2"
        if has_lib("libuv.so"):
            frameworks["libuv"] = "host:libuv"
        if has_lib("libtasn1.so"):
            frameworks["libtasn1"] = "host:libtasn1"
        if has_lib("libp11-kit.so"):
            frameworks["p11-kit"] = "host:libp11-kit"
        if has_lib("libgnutls.so"):
            frameworks["gnutls"] = "host:gnutls"
        if has_lib("libgcrypt.so"):
            frameworks["libgcrypt"] = "host:libgcrypt"
        if has_lib("libgpg-error.so"):
            frameworks["libgpg-error"] = "host:libgpg-error"
        if has_lib("libbrotlidec.so"):
            frameworks["brotli"] = "host:brotli"
        if has_lib("libgif.so"):
            frameworks["giflib"] = "host:giflib"
        if has_lib("libopenjp2.so"):
            frameworks["openjpeg2"] = "host:openjpeg2"
        if has_lib("libwoff2dec.so"):
            frameworks["woff2"] = "host:woff2"
        if has_lib("libelf.so"):
            frameworks["libelf"] = "host:libelf"
            frameworks["elfutils"] = "host:elfutils"
        if has_lib("libpcre2-8.so"):
            frameworks["pcre2"] = "host:pcre2"
        if has_lib("libpcre.so"):
            frameworks["pcre"] = "host:pcre"
        if has_lib("libkeyutils.so"):
            frameworks["keyutils"] = "host:keyutils"
        if has_lib("libkrb5.so"):
            frameworks["krb5"] = "host:krb5"
        if has_lib("libssh2.so"):
            frameworks["libssh2"] = "host:libssh2"
        if has_lib("libpsl.so"):
            frameworks["libpsl"] = "host:libpsl"
        if has_lib("libidn2.so"):
            frameworks["libidn2"] = "host:libidn2"
        if has_lib("libunistring.so"):
            frameworks["libunistring"] = "host:libunistring"
        if has_lib("libgmp.so"):
            frameworks["gmp"] = "host:gmp"
        if has_lib("libmpfr.so"):
            frameworks["mpfr"] = "host:mpfr"
        if shutil.which("perl") or os.path.exists("/usr/bin/perl"):
            frameworks["perl"] = "host:perl"
        if has_lib("libgcc_s.so"):
            frameworks["libgcc"] = "host:libgcc_s.so"
        if has_lib("libstdc++.so"):
            frameworks["libstdc++"] = "host:libstdc++.so"
        if has_lib("libicuuc.so"):
            frameworks["icu"] = "host:icu"
        if has_lib("libxml2.so"):
            frameworks["libxml2"] = "host:libxml2"
        if has_lib("libxslt.so"):
            frameworks["libxslt"] = "host:libxslt"
        if has_lib("libarchive.so"):
            frameworks["libarchive"] = "host:libarchive"
        if has_lib("libjson-c.so"):
            frameworks["json-c"] = "host:json-c"
        if has_lib("libfuse3.so"):
            frameworks["fuse3"] = "host:fuse3"
        if has_lib("libfuse.so"):
            frameworks["fuse2"] = "host:fuse2"
        if has_lib("libusb-1.0.so"):
            frameworks["libusb"] = "host:libusb"
        if has_lib("libevdev.so"):
            frameworks["libevdev"] = "host:libevdev"
        if has_lib("libhidapi-hidraw.so") or has_lib("libhidapi-libusb.so"):
            frameworks["hidapi"] = "host:hidapi"
        if has_lib("libseccomp.so"):
            frameworks["libseccomp"] = "host:libseccomp"
        if has_lib("libcap.so"):
            frameworks["libcap"] = "host:libcap"
        if has_lib("liburing.so"):
            frameworks["liburing"] = "host:liburing"
        if has_lib("libunwind.so"):
            frameworks["libunwind"] = "host:libunwind"
        if shutil.which("bwrap") or os.path.exists("/usr/bin/bwrap"):
            frameworks["bubblewrap"] = "host:bubblewrap"

        # 6. X11 & Wayland
        for x_pkg in ["libx11", "libxext", "libxfixes", "libxi", "libxrandr", "libxcursor",
                      "libxrender", "libxcomposite", "libxdamage", "libxinerama", "libxtst",
                      "libxshmfence", "libxxf86vm", "libxau", "libxdmcp", "libxcb", "xcb-proto",
                      "xorgproto", "xorg-xprop", "default-cursors", "xkeyboard-config"]:
            frameworks[x_pkg] = f"host:{x_pkg}"
        if has_lib("libwayland-client.so"):
            frameworks["wayland"] = "host:wayland"
        if has_lib("libxkbcommon.so"):
            frameworks["libxkbcommon"] = "host:libxkbcommon"
        if has_lib("libxkbcommon-x11.so"):
            frameworks["libxkbcommon-x11"] = "host:libxkbcommon-x11"

        # 7. Qt Frameworks
        if has_lib("libQt6Core.so"):
            frameworks["qt6-base"] = "host:qt6-base"
        if has_lib("libQt5Core.so"):
            frameworks["qt5-base"] = "host:qt5-base"

        # 8. SDL Frameworks
        if has_lib("libSDL2-2.0.so") or has_lib("libSDL2.so"):
            frameworks["sdl2"] = "host:sdl2"
        if has_lib("libSDL3.so"):
            frameworks["sdl3"] = "host:sdl3"

        # 9. Extended Base & Desktop System Libraries (Slackware Native Shield)
        if has_lib("libmng.so"):
            frameworks["libmng"] = "host:libmng"
        if has_lib("libpopt.so"):
            frameworks["popt"] = "host:popt"
        if has_lib("libhunspell"):
            frameworks["hunspell"] = "host:hunspell"
        if has_lib("libhyphen.so"):
            frameworks["hyphen"] = "host:hyphen"
        if has_lib("libmtp.so"):
            frameworks["libmtp"] = "host:libmtp"
        if has_lib("libwmf"):
            frameworks["libwmf"] = "host:libwmf"
        if has_lib("liblcms2.so"):
            frameworks["lcms2"] = "host:lcms2"
        if has_lib("libidn.so"):
            frameworks["libidn"] = "host:libidn"
        if has_lib("libminizip.so"):
            frameworks["minizip"] = "host:minizip"
        if has_lib("libpoppler.so"):
            frameworks["poppler"] = "host:poppler"
        if has_lib("libchm.so"):
            frameworks["chmlib"] = "host:chmlib"
        if has_lib("libuchardet.so"):
            frameworks["uchardet"] = "host:uchardet"
        if has_lib("libsnappy.so"):
            frameworks["snappy"] = "host:snappy"
        if has_lib("liblua.so"):
            frameworks["lua"] = "host:lua"
            frameworks["lua54"] = "host:lua"
        if has_lib("libespeak-ng.so"):
            frameworks["espeak-ng"] = "host:espeak-ng"
        if has_lib("libnspr4.so"):
            frameworks["nspr"] = "host:nspr"
        if has_lib("libnss3.so") or has_lib("libnss_"):
            frameworks["nss"] = "host:nss"
        if has_lib("libassuan.so"):
            frameworks["libassuan"] = "host:libassuan"
        if has_lib("libksba.so"):
            frameworks["libksba"] = "host:libksba"
        if has_lib("libldap.so"):
            frameworks["libldap"] = "host:libldap"
        if has_lib("libnpth.so"):
            frameworks["npth"] = "host:npth"
        if has_lib("libgpgme.so"):
            frameworks["gpgme"] = "host:gpgme"
            frameworks["gpgmepp"] = "host:gpgmepp"
        if has_lib("libopenh264.so"):
            frameworks["openh264"] = "host:openh264"
        if has_lib("libxxhash.so"):
            frameworks["xxhash"] = "host:xxhash"
        if has_lib("libjasper.so"):
            frameworks["jasper"] = "host:jasper"
        if has_lib("libacl.so"):
            frameworks["acl"] = "host:acl"
        if has_lib("libcryptsetup.so"):
            frameworks["cryptsetup"] = "host:cryptsetup"
        if has_lib("libparted.so"):
            frameworks["parted"] = "host:parted"
        if has_lib("libgudev-1.0.so"):
            frameworks["libgudev"] = "host:libgudev"
        if has_lib("libudisks2.so"):
            frameworks["udisks2"] = "host:udisks2"

        # 10. Comprehensive Slackware System & Multimedia Libraries (Shared Native Shield)
        mappings = [
            ("bluez", "libbluetooth.so"),
            ("bluez-libs", "libbluetooth.so"),
            ("boost", "libboost_"),
            ("boost-libs", "libboost_"),
            ("cups", "libcups.so"),
            ("libcups", "libcups.so"),
            ("mariadb", "libmariadb.so"),
            ("mariadb-libs", "libmariadb.so"),
            ("samba", "libsmbclient.so"),
            ("smbclient", "libsmbclient.so"),
            ("libwbclient", "libwbclient.so"),
            ("libbluray", "libbluray.so"),
            ("libcdio", "libcdio.so"),
            ("libcdio-paranoia", "libcdio_paranoia.so"),
            ("lzo", "liblzo2.so"),
            ("lzo2", "liblzo2.so"),
            ("lz4", "liblz4.so"),
            ("libtirpc", "libtirpc.so"),
            ("libnsl", "libnsl.so"),
            ("libxcrypt", "libcrypt.so"),
            ("talloc", "libtalloc.so"),
            ("tdb", "libtdb.so"),
            ("ldb", "libldb.so"),
            ("tevent", "libtevent.so"),
            ("jansson", "libjansson.so"),
            ("lmdb", "liblmdb.so"),
            ("libdaemon", "libdaemon.so"),
            ("avahi", "libavahi-client.so"),
            ("taglib", "libtag.so"),
            ("libwacom", "libwacom.so"),
            ("mtdev", "libmtdev.so"),
            ("libinput", "libinput.so"),
            ("glu", "libGLU.so"),
            ("glew", "libGLEW.so"),
            ("tcl", "libtcl"),
            ("tk", "libtk"),
            ("libevent", "libevent"),
            ("libyaml", "libyaml.so"),
            ("libxft", "libXft.so"),
            ("libxss", "libXss.so"),
            ("libpciaccess", "libpciaccess.so"),
            ("libcap-ng", "libcap-ng.so"),
            ("libdisplay-info", "libdisplay-info.so"),
            ("libavif", "libavif.so"),
            ("svt-av1", "libSvtAv1Enc.so"),
            ("rav1e", "librav1e.so"),
            ("libass", "libass.so"),
            ("libmicrohttpd", "libmicrohttpd.so"),
            ("libusb-compat", "libusb-0.1.so"),
            ("libftdi", "libftdi1.so"),
            ("binutils", "libbfd.so"),
            ("cifs-utils", "libwbclient.so"),
            ("openmpi", "libmpi.so"),
            ("hwloc", "libhwloc.so"),
            ("jsoncpp", "libjsoncpp.so"),
            ("numactl", "libnuma.so")
        ]
        for pkg_name, soname_pat in mappings:
            if has_lib(soname_pat) or (pkg_name == "boost-libs" and has_lib("libboost_")):
                frameworks[pkg_name] = f"host:{pkg_name}"

        cls._cached_frameworks = frameworks
        return cls._cached_frameworks


# --- [ IN-MEMORY PACMAN DATABASE PARSER ] ---

class PacmanDBParser:
    """Parses raw Pacman sync archive buffers into structured package dictionaries."""

    LIST_KEYS = {"DEPENDS", "OPTDEPENDS", "PROVIDES", "CONFLICTS", "REPLACES", "MAKEDEPENDS", "CHECKDEPENDS"}

    @classmethod
    def parse_desc_content(cls, content: str) -> Dict[str, Any]:
        """Parse the key-value block in a single 'desc' file."""
        pkg: Dict[str, Any] = {}
        cur_key = None
        cur_lines: List[str] = []

        for line in content.splitlines():
            line = line.strip()
            if line.startswith("%") and line.endswith("%"):
                if cur_key:
                    if cur_key in cls.LIST_KEYS:
                        pkg[cur_key] = cur_lines
                    else:
                        pkg[cur_key] = cur_lines[0] if cur_lines else ""
                cur_key = line[1:-1]
                cur_lines = []
            elif line:
                cur_lines.append(line)

        if cur_key:
            if cur_key in cls.LIST_KEYS:
                pkg[cur_key] = cur_lines
            else:
                pkg[cur_key] = cur_lines[0] if cur_lines else ""

        return pkg

    @classmethod
    def parse_archive(cls, data: bytes, is_zstd: bool = False) -> Dict[str, Dict[str, Any]]:
        """Parse full sync database tar archive from memory buffer."""
        packages: Dict[str, Dict[str, Any]] = {}
        if is_zstd:
            p = subprocess.Popen(["zstd", "-d", "-c"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            unz_data, err = p.communicate(input=data)
            if p.returncode != 0:
                raise RuntimeError(f"zstd decompression failed: {err.decode('utf-8', errors='ignore')}")
            tf = tarfile.open(fileobj=io.BytesIO(unz_data))
        else:
            tf = tarfile.open(fileobj=io.BytesIO(data), mode="r:*")

        try:
            for member in tf.getmembers():
                if member.name.endswith("/desc"):
                    f = tf.extractfile(member)
                    if f:
                        content = f.read().decode("utf-8", errors="ignore")
                        pkg = cls.parse_desc_content(content)
                        if "NAME" in pkg:
                            packages[pkg["NAME"]] = pkg
        finally:
            tf.close()

        return packages


# --- [ DATABASE ENGINE & DEPENDENCY RESOLVER ] ---

class GnomesPacmanEngine:
    """High-performance repository synchronizer, indexer, search engine, and DAG solver."""

    def __init__(self, cache_dir: Optional[str] = None):
        self.cache_dir = cache_dir or get_cache_dir()
        self.db_dir = os.path.join(self.cache_dir, "db")
        os.makedirs(self.db_dir, exist_ok=True)
        self.repositories = get_default_repositories()
        self.index: Dict[str, Dict[str, Any]] = {}
        self.provides_index: Dict[str, List[str]] = {}
        self.repo_packages: Dict[str, Dict[str, Dict[str, Any]]] = {}
        self._loaded = False

    def sync_repositories(self, force: bool = False, verbose: bool = True) -> Dict[str, int]:
        """Download and cache all active repository sync databases."""
        results: Dict[str, int] = {}
        headers = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) Slacky-Update/0.17.0 UnderpantsGnomes"}

        for repo in self.repositories:
            rname = repo["name"]
            url = repo["url"]
            if rname in BLACKLISTED_REPOS:
                continue

            local_ext = ".db.tar.zst" if url.endswith(".zst") else ".db.tar.gz"
            local_path = os.path.join(self.db_dir, f"{rname}{local_ext}")
            local_meta = local_path + ".meta"

            now = time.time()
            need_download = force or not os.path.exists(local_path)

            if not need_download and os.path.exists(local_path):
                mtime = os.path.getmtime(local_path)
                if (now - mtime) > 10800: # 3 hours TTL
                    need_download = True

            if need_download:
                if verbose:
                    print(f":: Synchronizing database [{rname}] from {url}...")
                try:
                    req = urllib.request.Request(url, headers=headers)
                    with urllib.request.urlopen(req, timeout=15) as resp:
                        data = resp.read()
                        with open(local_path, "wb") as f:
                            f.write(data)
                        with open(local_meta, "w", encoding="utf-8") as f:
                            json.dump({"url": url, "base_url": repo["base_url"], "mtime": now, "size": len(data)}, f)
                except Exception as e:
                    if verbose:
                        print(f"Warning: Failed to sync [{rname}]: {e}")
                    if not os.path.exists(local_path):
                        continue

            # Parse and count packages
            if os.path.exists(local_path):
                try:
                    with open(local_path, "rb") as f:
                        raw_data = f.read()
                    is_zstd = local_path.endswith(".zst")
                    pkgs = PacmanDBParser.parse_archive(raw_data, is_zstd=is_zstd)
                    self.repo_packages[rname] = pkgs
                    results[rname] = len(pkgs)
                except Exception as e:
                    if verbose:
                        print(f"Warning: Error parsing cached [{rname}]: {e}")

        self._build_index()
        return results

    def load_cached_databases(self) -> None:
        """Load and index all locally cached databases without downloading."""
        for repo in self.repositories:
            rname = repo["name"]
            for ext in [".db.tar.zst", ".db.tar.gz"]:
                lpath = os.path.join(self.db_dir, f"{rname}{ext}")
                if os.path.exists(lpath):
                    try:
                        with open(lpath, "rb") as f:
                            raw_data = f.read()
                        is_zstd = lpath.endswith(".zst")
                        pkgs = PacmanDBParser.parse_archive(raw_data, is_zstd=is_zstd)
                        self.repo_packages[rname] = pkgs
                        break
                    except Exception:
                        pass
        self._build_index()

    def _build_index(self) -> None:
        """Construct unified search, package, and provides index."""
        self.index.clear()
        self.provides_index.clear()

        # Process in reverse repository priority so higher priority repos overwrite lower ones
        sorted_repos = sorted(self.repositories, key=lambda r: r.get("priority", 0))

        for repo in sorted_repos:
            rname = repo["name"]
            pkgs = self.repo_packages.get(rname, {})
            for pname, pdata in pkgs.items():
                pdata_copy = dict(pdata)
                pdata_copy["_REPO"] = rname
                pdata_copy["_BASE_URL"] = repo.get("base_url", "")
                self.index[pname] = pdata_copy

                # Index provides
                raw_provides = pdata.get("PROVIDES", [])
                for prov in raw_provides:
                    clean_prov = re.split(r"[><=]", prov)[0].strip()
                    if clean_prov not in self.provides_index:
                        self.provides_index[clean_prov] = []
                    if pname not in self.provides_index[clean_prov]:
                        self.provides_index[clean_prov].append(pname)

        self._loaded = True

    def ensure_loaded(self) -> None:
        """Ensure databases are loaded into memory, syncing if empty."""
        if not self._loaded or not self.index:
            self.load_cached_databases()
            if not self.index:
                self.sync_repositories(verbose=False)

    def search(self, query: str, repo: Optional[str] = None, limit: int = 50) -> List[Dict[str, Any]]:
        """
        Fast search across package names, descriptions, and provides.
        Returns ranked list of matching package entries.
        """
        self.ensure_loaded()
        q = query.lower().strip()
        terms = [t for t in q.split() if t]
        if not terms:
            return []

        scored_results: List[Tuple[int, Dict[str, Any]]] = []

        target_items = []
        if repo and repo in self.repo_packages:
            for pname, pdata in self.repo_packages[repo].items():
                pcopy = dict(pdata)
                pcopy["_REPO"] = repo
                target_items.append((pname, pcopy))
        else:
            target_items = list(self.index.items())

        for pname, pdata in target_items:
            name_lower = pname.lower()
            desc_lower = str(pdata.get("DESC", "")).lower()
            provides = [str(x).lower() for x in pdata.get("PROVIDES", [])]

            score = 0
            # Exact match
            if name_lower == q:
                score += 1000
            elif name_lower.startswith(q):
                score += 500
            elif q in name_lower:
                score += 200

            # Multi-term scoring
            all_match = True
            for term in terms:
                term_hit = False
                if term in name_lower:
                    score += 50
                    term_hit = True
                if term in desc_lower:
                    score += 20
                    term_hit = True
                if any(term in prov for prov in provides):
                    score += 30
                    term_hit = True
                if not term_hit:
                    all_match = False

            if all_match and score > 0:
                scored_results.append((score, pdata))

        scored_results.sort(key=lambda x: x[0], reverse=True)
        return [item[1] for item in scored_results[:limit]]

    def get_package(self, pkg_name: str, repo: Optional[str] = None) -> Optional[Dict[str, Any]]:
        """Retrieve exact package definition by name or provider."""
        self.ensure_loaded()
        clean_name = re.split(r"[><=]", pkg_name)[0].strip()

        if repo and repo in self.repo_packages:
            pdata = self.repo_packages[repo].get(clean_name)
            if pdata:
                pcopy = dict(pdata)
                pcopy["_REPO"] = repo
                return pcopy

        # Exact match in unified index
        if clean_name in self.index:
            return self.index[clean_name]

        # Check provides index (filter out excluded providers)
        if clean_name in self.provides_index and self.provides_index[clean_name]:
            for provider_name in self.provides_index[clean_name]:
                p_lower = provider_name.lower()
                if provider_name not in CORE_EXCLUDES and p_lower not in CORE_EXCLUDES and not p_lower.startswith("linux") and not p_lower.startswith("systemd"):
                    return self.index.get(provider_name)

        # Fallback suffix aliases (e.g. ungoogled-chromium -> ungoogled-chromium-bin)
        for suffix in ["-bin", "-git", "-appimage"]:
            cand = f"{clean_name}{suffix}"
            if cand in self.index:
                return self.index[cand]

        return None

    def get_download_urls_candidates(self, pkg: Dict[str, Any]) -> List[str]:
        """Construct candidate HTTP download URLs in priority order including architecture and mirror fallbacks."""
        filename = pkg.get("FILENAME")
        base_url = pkg.get("_BASE_URL")
        repo = pkg.get("_REPO", "")
        if not filename:
            return []

        candidates: List[str] = []
        if base_url:
            candidates.append(f"{base_url.rstrip('/')}/{filename}")

        # CachyOS repo specific architecture routing
        if "cachyos" in (base_url or "") or repo.startswith("cachyos"):
            # znver4 -> v4 fallback
            if "znver4" in (base_url or "") and "_v4" in filename:
                candidates.append(f"{base_url.replace('x86_64_znver4', 'x86_64_v4').replace('-znver4', '-v4').rstrip('/')}/{filename}")
            # znver4 -> base x86_64 fallback
            if "znver4" in (base_url or ""):
                candidates.append(f"{base_url.replace('x86_64_znver4', 'x86_64').replace('-znver4', '').rstrip('/')}/{filename}")
            # v4 -> base x86_64 fallback
            if "v4" in (base_url or "") and "znver4" not in (base_url or ""):
                candidates.append(f"{base_url.replace('x86_64_v4', 'x86_64').replace('-v4', '').rstrip('/')}/{filename}")

            # CachyOS clean package fallbacks
            clean_fn = re.sub(r'-([0-9]+)\.[0-9]+-x86_64(_v[0-9]+|_znver[0-9]+|)', r'-\1-x86_64', filename)
            clean_fn = re.sub(r'-x86_64_v[0-9]+', r'-x86_64', clean_fn)
            clean_fn = re.sub(r'-x86_64_znver[0-9]+', r'-x86_64', clean_fn)
            candidates.append(f"{DEFAULT_CACHYOS_MIRROR}/x86_64/cachyos/{filename}")
            candidates.append(f"{DEFAULT_CACHYOS_MIRROR}/x86_64/cachyos-extra/{filename}")
            candidates.append(f"{DEFAULT_CACHYOS_MIRROR}/x86_64/cachyos-core/{filename}")
            if clean_fn != filename:
                candidates.append(f"{DEFAULT_CACHYOS_MIRROR}/x86_64/cachyos/{clean_fn}")
                candidates.append(f"{DEFAULT_CACHYOS_MIRROR}/x86_64/cachyos-extra/{clean_fn}")
                candidates.append(f"{DEFAULT_CACHYOS_MIRROR}/x86_64/cachyos-core/{clean_fn}")

        # Arch Linux Official Mirrors (Extra / Core / Multilib)
        clean_arch_fn = re.sub(r'-([0-9]+)\.[0-9]+-x86_64(_v[0-9]+|_znver[0-9]+|)', r'-\1-x86_64', filename)
        clean_arch_fn = re.sub(r'-x86_64_v[0-9]+', r'-x86_64', clean_arch_fn)
        clean_arch_fn = re.sub(r'-x86_64_znver[0-9]+', r'-x86_64', clean_arch_fn)
        for cand_name in [clean_arch_fn, filename]:
            candidates.append(f"{DEFAULT_ARCH_MIRROR}/extra/os/x86_64/{cand_name}")
            candidates.append(f"{DEFAULT_ARCH_MIRROR}/core/os/x86_64/{cand_name}")
            candidates.append(f"{DEFAULT_ARCH_MIRROR}/multilib/os/x86_64/{cand_name}")

        # Remove duplicates while preserving order
        unique_candidates: List[str] = []
        seen: Set[str] = set()
        for c in candidates:
            if c and c not in seen:
                seen.add(c)
                unique_candidates.append(c)
        return unique_candidates

    def get_download_url(self, pkg: Dict[str, Any]) -> Optional[str]:
        """Construct direct HTTP download URL for package archive."""
        cands = self.get_download_urls_candidates(pkg)
        return cands[0] if cands else None

    def resolve_dependencies(self, targets: List[str], max_depth: int = 15, standalone: bool = False) -> Dict[str, Any]:
        """
        Solve multi-tier recursive dependency DAG for requested packages,
        enforcing Host Sovereignty Excludes, Virtual Provides, and Native Host Frameworks.
        """
        self.ensure_loaded()
        host_libs = HostLibraryScanner.get_host_libraries()
        host_glibc = HostLibraryScanner.get_host_glibc_version()
        host_frameworks = {} if standalone else HostLibraryScanner.get_host_frameworks()
        runtime_libs = {} if standalone else RuntimeManager.get_runtime_libraries()
        target_clean_names: Set[str] = set()
        for t in targets:
            c = re.split(r"[><=]", t)[0].strip().lower()
            target_clean_names.add(c)
            p = self.get_package(c)
            if p and p.get("NAME"):
                target_clean_names.add(p["NAME"].lower())

        resolved_pkgs: Dict[str, Dict[str, Any]] = {}
        dep_graph: Dict[str, List[str]] = {} # parent -> [children]
        host_provided: Dict[str, str] = {}
        virtual_satisfied: Dict[str, str] = {}
        missing_deps: List[str] = []

        visited: Set[str] = set()
        queue: List[Tuple[str, int, Optional[str]]] = [(t, 0, None) for t in targets]

        while queue:
            raw_req, depth, parent = queue.pop(0)
            clean_name = re.split(r"[><=]", raw_req)[0].strip()

            if not clean_name:
                continue

            clean_lower = clean_name.lower()

            # 1. Check Core Host Exclude Shield
            if clean_name in CORE_EXCLUDES or clean_lower in CORE_EXCLUDES or clean_lower.startswith("linux") or clean_lower.startswith("systemd"):
                host_provided[clean_name] = f"Host Base System / Core Exclude Protected ({clean_name})"
                continue

            # 1.5 Shield against 32-bit (multilib) packages when resolving 64-bit target graph
            is_32bit_request = any(t.lower().startswith("lib32-") for t in targets)
            if not is_32bit_request and clean_lower.startswith("lib32-"):
                host_provided[clean_name] = f"32-bit Multilib Excluded for 64-bit target ({clean_name})"
                continue

            # 2. Check Virtual Providers (case-insensitive)
            if clean_lower in VIRTUAL_PROVIDES_DEFAULT:
                virtual_satisfied[clean_name] = VIRTUAL_PROVIDES_DEFAULT[clean_lower]
                continue

            # 3. Check Native Host System Frameworks (Slackware-First Hybrid Model)
            if not standalone and (clean_name in host_frameworks or clean_lower in host_frameworks) and clean_lower not in target_clean_names:
                fw_source = host_frameworks.get(clean_name, host_frameworks.get(clean_lower))
                host_provided[clean_name] = f"Host System Framework ({fw_source})"
                continue

            # 4. Check if raw_req is a shared library soname provided by host
            if clean_name.endswith(".so") or ".so." in clean_name:
                if clean_name in host_libs:
                    host_provided[clean_name] = f"Host Shared Library ({clean_name})"
                    continue

            # 5. Check if already processed
            if clean_name in visited:
                if parent and clean_name in resolved_pkgs:
                    dep_graph.setdefault(parent, []).append(clean_name)
                continue

            visited.add(clean_name)

            # 6. Lookup package in repo index
            pkg = self.get_package(clean_name)

            if not pkg:
                missing_deps.append(clean_name)
                continue

            actual_name = pkg["NAME"]
            actual_lower = actual_name.lower()

            if actual_name in CORE_EXCLUDES or actual_lower in CORE_EXCLUDES or actual_lower.startswith("linux") or actual_lower.startswith("systemd"):
                host_provided[clean_name] = f"Host Base System ({actual_name} excluded)"
                continue

            if not standalone and (actual_name in host_frameworks or actual_lower in host_frameworks) and actual_lower not in target_clean_names:
                pkg_provides = pkg.get("PROVIDES", [])
                so_provides = [p.split("=")[0].strip() for p in pkg_provides if ".so" in p]
                if so_provides:
                    missing_host_so = [so for so in so_provides if not (so in host_libs or any(h == so or h.startswith(so + ".") or (so.endswith(".so") and h.startswith(so)) for h in host_libs))]
                    if missing_host_so:
                        # Host lacks specific ABI sonames; stage the package to avoid missing libraries
                        pass
                    else:
                        fw_source = host_frameworks.get(actual_name, host_frameworks.get(actual_lower))
                        host_provided[clean_name] = f"Host System Framework ({fw_source})"
                        continue
                else:
                    fw_source = host_frameworks.get(actual_name, host_frameworks.get(actual_lower))
                    host_provided[clean_name] = f"Host System Framework ({fw_source})"
                    continue

            # 7. Check Underpants Shared Runtime Pool (/opt/underpants/runtime/ & /opt/underpants/common/)
            if not standalone and actual_lower not in target_clean_names:
                pkg_provides = pkg.get("PROVIDES", [])
                so_provides = [p.split("=")[0].strip() for p in pkg_provides if ".so" in p]
                if so_provides and all(any(h == so or h.startswith(so + ".") or (so.endswith(".so") and h.startswith(so)) for h in runtime_libs) for so in so_provides):
                    host_provided[clean_name] = f"Underpants Shared Runtime ({actual_name})"
                    continue

            resolved_pkgs[actual_name] = pkg

            if parent:
                dep_graph.setdefault(parent, []).append(actual_name)

            # Auto-enqueue modular companion plugins (e.g. zathura -> zathura-pdf-poppler, qt5-base -> qt5-wayland)
            if actual_lower in MODULAR_APP_PLUGINS:
                for plugin_pkg in MODULAR_APP_PLUGINS[actual_lower]:
                    if plugin_pkg not in visited and plugin_pkg not in [q[0] for q in queue]:
                        queue.append((plugin_pkg, depth + 1, actual_name))

            # 6. Recurse dependencies if within depth limit
            if depth < max_depth:
                depends = pkg.get("DEPENDS", [])
                for dep in depends:
                    queue.append((dep, depth + 1, actual_name))

        # --- [ TOPOLOGICAL SORT (DAG) ] ---
        # Deepest leaf dependencies installed first
        install_order: List[str] = []
        perm_marks: Set[str] = set()
        temp_marks: Set[str] = set()

        def visit(node: str) -> None:
            if node in perm_marks:
                return
            if node in temp_marks:
                # Cycle detected: break loop safely
                return
            temp_marks.add(node)
            for child in dep_graph.get(node, []):
                visit(child)
            temp_marks.remove(node)
            perm_marks.add(node)
            install_order.append(node)

        for target in targets:
            clean_t = re.split(r"[><=]", target)[0].strip()
            if clean_t in resolved_pkgs:
                visit(clean_t)
        for p in resolved_pkgs:
            if p not in perm_marks:
                visit(p)

        to_install_pkgs = [resolved_pkgs[p] for p in install_order if p in resolved_pkgs]

        total_download = sum(int(p.get("CSIZE", 0)) for p in to_install_pkgs)
        total_installed = sum(int(p.get("ISIZE", 0)) for p in to_install_pkgs)

        return {
            "targets": targets,
            "to_install": to_install_pkgs,
            "to_install_names": [p["NAME"] for p in to_install_pkgs],
            "host_provided": host_provided,
            "virtual_satisfied": virtual_satisfied,
            "missing": list(set(missing_deps)),
            "download_size_bytes": total_download,
            "installed_size_bytes": total_installed,
            "host_glibc_supported": f"{host_glibc[0]}.{host_glibc[1]}"
        }

    def list_installed_gnomes_packages(self) -> List[Dict[str, str]]:
        """Inspect /var/log/packages/ for native underpants-* packages."""
        installed = []
        log_dir = "/var/log/packages"
        if not os.path.exists(log_dir):
            return installed

        try:
            for fname in os.listdir(log_dir):
                if fname.startswith("underpants-") or fname.startswith("cachyos-gnome-"):
                    parts = fname.rsplit("-", 3)
                    if len(parts) == 4:
                        raw_name, ver, arch, build = parts
                        app_name = raw_name.replace("underpants-", "").replace("cachyos-gnome-", "")
                        installed.append({
                            "package_id": fname,
                            "name": app_name,
                            "version": ver,
                            "arch": arch,
                            "build": build
                        })
        except Exception:
            pass
        return sorted(installed, key=lambda x: x["name"])

    def check_curated_collision(self, pkg_name: str) -> Optional[str]:
        """Check if pkg_name is already installed natively as a curated Slackware package."""
        clean_name = re.split(r"[><=]", pkg_name)[0].strip().lower()
        log_dir = "/var/log/packages"
        if not os.path.exists(log_dir):
            return None

        try:
            for fname in os.listdir(log_dir):
                if fname.startswith("underpants-") or fname.startswith("cachyos-gnome-"):
                    continue
                parts = fname.rsplit("-", 3)
                if len(parts) >= 4:
                    native_name = parts[0].lower()
                    if native_name == clean_name:
                        return fname
        except Exception:
            pass
        return None

    def clean_cache(self, clean_all: bool = False) -> Tuple[int, int]:
        """
        Prune package tarballs from all local download cache directories.
        If clean_all is True, removes all .pkg.tar.zst / .pkg.tar.xz / .part files.
        If clean_all is False, removes uninstalled or corrupt files.
        Returns (files_removed, bytes_freed).
        """
        installed_apps = {p["name"].lower() for p in self.list_installed_gnomes_packages()}
        files_removed = 0
        bytes_freed = 0

        candidate_dirs = {
            os.path.join(self.cache_dir, "pkg"),
            os.path.join(DEFAULT_CACHE_BASE, "pkg"),
            os.path.join(USER_CACHE_BASE, "pkg"),
            "/var/cache/gnomes/pkg",
            "/var/cache/slacky-update/gnomes/pkg",
            os.path.expanduser("~/.cache/gnomes/pkg"),
            os.path.expanduser("~/.cache/slacky-update/gnomes/pkg"),
            "/tmp/slacky-update-gnomes/pkg"
        }

        for cdir in candidate_dirs:
            if not os.path.isdir(cdir):
                continue
            try:
                for fname in os.listdir(cdir):
                    fpath = os.path.join(cdir, fname)
                    if not os.path.isfile(fpath):
                        continue
                    if not (fname.endswith(".pkg.tar.zst") or fname.endswith(".pkg.tar.xz") or fname.endswith(".part")):
                        continue

                    should_delete = False
                    if clean_all or fname.endswith(".part"):
                        should_delete = True
                    else:
                        if not TransmutationFactory.is_valid_pkg_archive(fpath):
                            should_delete = True
                        else:
                            m = re.match(r"^([a-zA-Z0-9_\.\+-]+?)-[0-9]+[a-zA-Z0-9_\.:-]*-[0-9]+", fname)
                            pkg_name = m.group(1).lower() if m else ""
                            if pkg_name not in installed_apps:
                                should_delete = True

                    if should_delete:
                        try:
                            sz = os.path.getsize(fpath)
                            os.remove(fpath)
                            files_removed += 1
                            bytes_freed += sz
                        except Exception:
                            pass
            except Exception:
                pass

        # Also prune generated Slackware .txz packages and temporary build residue in /tmp & /var/cache
        tmp_patterns = [
            "/tmp/underpants-*.txz",
            "/tmp/underpants-*.part",
            "/tmp/build-*",
            "/tmp/package-*",
            "/tmp/transmute-gnomes-*",
            "/tmp/slacky-build-*",
            "/tmp/slacky-rocm-*",
            "/tmp/slacky-sign-*",
            "/tmp/pycache",
            "/var/cache/slacky-update/*.tmp"
        ]
        if clean_all:
            tmp_patterns.extend([
                "/tmp/slacky-update-*.txz",
                "/tmp/SBo/*",
                "/var/cache/slacky-update/archives/*",
                "/var/cache/slacky-update/kernel/*",
                "/var/cache/slacky-update/nvidia/*",
                "/var/cache/slacky-update/rocm/*",
                "/var/cache/sbopkg/*"
            ])

        for pat in tmp_patterns:
            for item in glob.glob(pat):
                try:
                    if os.path.isfile(item) or os.path.islink(item):
                        sz = os.path.getsize(item)
                        os.remove(item)
                        files_removed += 1
                        bytes_freed += sz
                    elif os.path.isdir(item):
                        sz = sum(os.path.getsize(os.path.join(r, f)) for r, _, fl in os.walk(item) for f in fl if os.path.isfile(os.path.join(r, f)))
                        shutil.rmtree(item, ignore_errors=True)
                        files_removed += 1
                        bytes_freed += sz
                except Exception:
                    pass

        # Prune orphaned /opt/underpants/pkgs/<app> directories if not registered in /var/log/packages
        if os.path.isdir("/opt/underpants/pkgs"):
            try:
                for entry in os.listdir("/opt/underpants/pkgs"):
                    app_dir = os.path.join("/opt/underpants/pkgs", entry)
                    if not os.path.isdir(app_dir):
                        continue
                    if entry.lower() not in installed_apps:
                        matches = glob.glob(f"/var/log/packages/underpants-{entry}-*") + glob.glob(f"/var/log/packages/underpants-{entry.lower()}-*")
                        if not matches:
                            sz = sum(os.path.getsize(os.path.join(r, f)) for r, _, fl in os.walk(app_dir) for f in fl if os.path.isfile(os.path.join(r, f)))
                            shutil.rmtree(app_dir, ignore_errors=True)
                            files_removed += 1
                            bytes_freed += sz
            except Exception:
                pass

        return files_removed, bytes_freed

    @staticmethod
    def parse_pkg_version(v_str: str) -> Tuple[List[Tuple[int, int, str]], List[Tuple[int, int, str]]]:
        """
        Parse version string into tokenized (version_tuple, release_tuple).
        Strips epochs and normalizes alphanumeric segments.
        """
        s = str(v_str).strip()
        s = re.sub(r"^[0-9]+[:_]", "", s)
        if "-" in s:
            ver_part, rel_part = s.rsplit("-", 1)
        elif "_" in s:
            ver_part, rel_part = s.rsplit("_", 1)
        else:
            ver_part, rel_part = s, ""

        def tokenize(v: str) -> List[Tuple[int, int, str]]:
            parts = re.split(r"([0-9]+)", v)
            res = []
            for p in parts:
                if not p or p in "._-+~":
                    continue
                if p.isdigit():
                    res.append((0, int(p), ""))
                else:
                    res.append((1, 0, p.lower()))
            return res

        return tokenize(ver_part), tokenize(rel_part)

    @classmethod
    def is_newer_version(cls, upstream_ver: str, installed_ver: str) -> bool:
        """
        Compare upstream package version against installed version.
        Returns True only if upstream is strictly newer.
        """
        up_ver, up_rel = cls.parse_pkg_version(upstream_ver)
        inst_ver, inst_rel = cls.parse_pkg_version(installed_ver)

        if up_ver > inst_ver:
            return True
        elif up_ver < inst_ver:
            return False

        if inst_rel and up_rel:
            return up_rel > inst_rel

        return False

    def list_updates(self) -> List[Dict[str, Any]]:
        """Check installed Underpants packages against synced repositories for available updates."""
        self.ensure_loaded()
        installed = self.list_installed_gnomes_packages()
        updates = []
        for inst in installed:
            name = inst["name"]
            cur_ver = inst["version"]
            upstream = self.get_package(name)
            if upstream:
                up_ver = upstream.get("VERSION", "0")
                if self.is_newer_version(up_ver, cur_ver):
                    updates.append({
                        "name": name,
                        "installed_version": cur_ver,
                        "upstream_version": up_ver,
                        "repo": upstream.get("_REPO", "upstream")
                    })
        return updates



# --- [ TRANSMUTATION FACTORY & PACKAGER ] ---

class TransmutationFactory:
    """Automates extraction, ELF RUNPATH rewriting, launcher wrapper creation, and Slackware .txz packaging."""

    def __init__(self, engine: GnomesPacmanEngine, output_dir: str = "/tmp"):
        self.engine = engine
        self.output_dir = output_dir
        self.cache_pkg_dir = os.path.join(self.engine.cache_dir, "pkg")
        os.makedirs(self.cache_pkg_dir, exist_ok=True)
        os.makedirs(self.output_dir, exist_ok=True)

    @staticmethod
    def safe_rmtree(path: str) -> None:
        """Safely remove directory tree handling permission quirks and symlinks."""
        if not os.path.exists(path) and not os.path.islink(path):
            return
        def _onerror(func, p, exc_info):
            try:
                os.chmod(p, stat.S_IWRITE | stat.S_IWUSR | stat.S_IRUSR | stat.S_IXUSR)
                func(p)
            except Exception:
                pass
        try:
            shutil.rmtree(path, onerror=_onerror)
        except Exception:
            try:
                subprocess.run(f"chmod -R u+w '{path}' 2>/dev/null; rm -rf '{path}' 2>/dev/null", shell=True, check=False)
            except Exception:
                pass

    @staticmethod
    def is_valid_pkg_archive(fpath: str, expected_size: int = 0) -> bool:
        """Verify that fpath is a genuine non-corrupted package archive and not an HTML error page."""
        if not os.path.isfile(fpath):
            return False
        sz = os.path.getsize(fpath)
        if sz < 128:
            return False
        try:
            with open(fpath, "rb") as f:
                header = f.read(32)
            if header.startswith(b"<html") or header.startswith(b"<!DOCTYPE") or header.startswith(b"<!doctype") or b"<html" in header.lower() or b"<head" in header.lower():
                return False
            if (".zst" in fpath or fpath.endswith(".zst")) and not header.startswith(b"\x28\xb5\x2f\xfd"):
                return False
            if (".xz" in fpath or fpath.endswith(".xz")) and not header.startswith(b"\xfd7zXZ\x00"):
                return False
            if (".gz" in fpath or fpath.endswith(".gz")) and not header.startswith(b"\x1f\x8b"):
                return False
            return True
        except Exception:
            return False

    @staticmethod
    def _relocate_text_and_symlink_paths(opt_app_dir: str, actual_name: str, staging_pkg: str) -> None:
        """
        Universally rewrite hardcoded upstream paths (/usr/lib, /usr/share, prefix=/usr, etc.)
        in staged shell scripts, text configs, python scripts, and symlinks.
        """
        app_prefix = f"/opt/underpants/pkgs/{actual_name}" if not actual_name.startswith("runtime-") else "/opt/underpants/runtime"
        scan_dirs = [opt_app_dir, staging_pkg]
        seen_paths = set()

        for sdir in scan_dirs:
            if not os.path.isdir(sdir):
                continue
            for root, dirs, files in os.walk(sdir):
                for fname in files:
                    fpath = os.path.join(root, fname)
                    real_fpath = os.path.realpath(fpath) if not os.path.islink(fpath) else fpath
                    if real_fpath in seen_paths:
                        continue
                    seen_paths.add(real_fpath)

                    # Fix symlinks pointing to absolute /usr/ paths
                    if os.path.islink(fpath):
                        try:
                            link_target = os.readlink(fpath)
                            if link_target.startswith("/usr/"):
                                if link_target.startswith(f"/usr/lib/{actual_name}"):
                                    new_target = link_target.replace(f"/usr/lib/{actual_name}", f"{app_prefix}/lib/{actual_name}", 1)
                                elif link_target.startswith(f"/usr/share/{actual_name}"):
                                    new_target = link_target.replace(f"/usr/share/{actual_name}", f"{app_prefix}/share/{actual_name}", 1)
                                elif link_target.startswith("/usr/lib64/"):
                                    new_target = link_target.replace("/usr/lib64/", f"{app_prefix}/lib64/", 1)
                                elif link_target.startswith("/usr/lib/"):
                                    new_target = link_target.replace("/usr/lib/", f"{app_prefix}/lib/", 1)
                                elif link_target.startswith("/usr/share/"):
                                    new_target = link_target.replace("/usr/share/", f"{app_prefix}/share/", 1)
                                elif link_target.startswith("/usr/bin/"):
                                    new_target = link_target.replace("/usr/bin/", f"{app_prefix}/bin/", 1)
                                else:
                                    new_target = link_target.replace("/usr", app_prefix, 1)
                                os.remove(fpath)
                                os.symlink(new_target, fpath)
                        except Exception:
                            pass
                        continue

                    # Skip non-regular files or files > 20MB
                    try:
                        if not os.path.isfile(fpath) or os.path.getsize(fpath) > 20 * 1024 * 1024:
                            continue
                    except Exception:
                        continue

                    # Check if file is text/script (avoid binary/ELF/zip/images)
                    try:
                        with open(fpath, "rb") as f:
                            chunk = f.read(512)
                        if not chunk or b"\x00" in chunk:
                            continue
                    except Exception:
                        continue

                    # Read and perform universal path relocation
                    try:
                        with open(fpath, "r", encoding="utf-8", errors="ignore") as f:
                            content = f.read()

                        modified = False

                        # Rewrite app-specific directories: /usr/lib/<app> -> /opt/underpants/pkgs/<app>/lib/<app>
                        if f"/usr/lib/{actual_name}" in content:
                            content = content.replace(f"/usr/lib/{actual_name}", f"{app_prefix}/lib/{actual_name}")
                            modified = True
                        if f"/usr/lib64/{actual_name}" in content:
                            content = content.replace(f"/usr/lib64/{actual_name}", f"{app_prefix}/lib64/{actual_name}")
                            modified = True
                        if f"/usr/share/{actual_name}" in content:
                            content = content.replace(f"/usr/share/{actual_name}", f"{app_prefix}/share/{actual_name}")
                            modified = True

                        # Rewrite shell script helper / dependency references (e.g. /usr/lib/electron42 -> /opt/underpants/pkgs/.../lib/electron42)
                        m_elec = re.search(r'^name=([a-zA-Z0-9_\.\-]+)', content, re.MULTILINE)
                        if m_elec:
                            dep_var = m_elec.group(1)
                            new_content, n_ev = re.subn(
                                r'exec\s+/usr/lib(?:64)?/\$\{?name\}?/electron',
                                rf'exec {app_prefix}/lib/{dep_var}/electron',
                                content
                            )
                            if n_ev > 0:
                                content = new_content
                                modified = True

                        new_content, n_el = re.subn(r'/usr/lib(?:64)?/(electron[0-9]*)', rf'{app_prefix}/lib/\1', content)
                        if n_el > 0:
                            content = new_content
                            modified = True

                        new_content, n_lib64 = re.subn(r'/usr/lib64/(?=[\$a-zA-Z0-9_-])', f'{app_prefix}/lib/', content)
                        if n_lib64 > 0:
                            content = new_content
                            modified = True

                        new_content, n_lib = re.subn(r'/usr/lib/(?=[\$a-zA-Z0-9_-])', f'{app_prefix}/lib/', content)
                        if n_lib > 0:
                            content = new_content
                            modified = True

                        new_content, n_ebin = re.subn(r'/usr/bin/(electron[0-9]*)', rf'{app_prefix}/bin/\1', content)
                        if n_ebin > 0:
                            content = new_content
                            modified = True

                        # Rewrite standard Autotools/CMake/Script variable assignments (prefix, exec_prefix, LIBDIR, datarootdir, sysconfdir)
                        new_content, n1 = re.subn(r'^((?:prefix|exec_prefix|PREFIX|EXEC_PREFIX)\s*=\s*)(["\']?)/usr\2(?=$|\s|;)', rf'\g<1>\g<2>{app_prefix}\g<2>', content, flags=re.MULTILINE)
                        if n1 > 0:
                            content = new_content
                            modified = True

                        new_content, n2 = re.subn(r'^((?:LIBDIR|libdir)\s*=\s*)(["\']?)/usr/lib(?:64)?\2(?=$|\s|;)', rf'\g<1>\g<2>{app_prefix}/lib\g<2>', content, flags=re.MULTILINE)
                        if n2 > 0:
                            content = new_content
                            modified = True

                        new_content, n3 = re.subn(r'^((?:datarootdir|DATADIR|datadir)\s*=\s*)(["\']?)/usr/share\2(?=$|\s|;)', rf'\g<1>\g<2>{app_prefix}/share\g<2>', content, flags=re.MULTILINE)
                        if n3 > 0:
                            content = new_content
                            modified = True

                        new_content, n4 = re.subn(r'^((?:sysconfdir|SYSCONFDIR)\s*=\s*)(["\']?)/etc\2(?=$|\s|;)', rf'\g<1>\g<2>{app_prefix}/etc\g<2>', content, flags=re.MULTILINE)
                        if n4 > 0:
                            content = new_content
                            modified = True

                        # Rewrite Exec= and loader directives (e.g. Exec=/usr/lib/glycin-loaders/2+/glycin-svg)
                        new_content, n5 = re.subn(r'(Exec\s*=\s*)/usr/lib(?:64)?/', rf'\g<1>{app_prefix}/lib/', content)
                        if n5 > 0:
                            content = new_content
                            modified = True

                        if modified:
                            with open(fpath, "w", encoding="utf-8", errors="ignore") as f:
                                f.write(content)
                    except Exception:
                        pass

    @staticmethod
    def _generate_launcher_wrapper(bname: str, actual_name: str) -> str:
        """
        Generate a robust, universal Slackware host launcher wrapper script for a binary or application.
        """
        upper_app = actual_name.replace("-", "_").replace(".", "_").upper()
        return f"""#!/bin/sh
# --- [ Underpants Gnomes Launcher Wrapper for {bname} ] ---
# Slackware Linux Host Sovereignty & Isolated Runtime Wrapper

APP_NAME="{actual_name}"
APP_ROOT="/opt/underpants/pkgs/{actual_name}"

# High-DPI Display Auto-Scaling (4K / 150% / 200% Fractional Scaling)
export QT_AUTO_SCREEN_SCALE_FACTOR=1
export QT_ENABLE_HIGHDPI_SCALE_FACTOR=1
export QT_ENABLE_HIGHDPI_SCALING=1
export QT_SCALE_FACTOR_ROUNDING_POLICY="${{QT_SCALE_FACTOR_ROUNDING_POLICY:-PassThrough}}"

# Realtime & memory lock limits (DAWs / Audio engines / Ardour / Jack)
ulimit -l unlimited 2>/dev/null || ulimit -l 1048576 2>/dev/null || true

# Dynamic library isolation (Prefer app root, then isolated runtime, then common, then host with private subsystem dirs - 64-bit Multilib clean)
export LD_LIBRARY_PATH="${{APP_ROOT}}/lib:${{APP_ROOT}}/lib64:/opt/underpants/runtime/lib:/opt/underpants/runtime/lib64:/opt/underpants/common/lib:/usr/lib64/libproxy:/usr/lib64/pulseaudio:/usr/lib64/pipewire-0.3:/usr/lib64/samba:${{LD_LIBRARY_PATH:-/usr/lib64}}"

# XDG data & resources (Preserve host /usr/local/share:/usr/share)
export XDG_DATA_DIRS="${{APP_ROOT}}/share:/opt/underpants/runtime/share:/opt/underpants/common/share:${{XDG_DATA_DIRS:-/usr/local/share:/usr/share}}"

# PipeWire & SPA plugin routing (Ensure audio event loops locate SPA plugins)
export SPA_PLUGIN_DIR="${{APP_ROOT}}/lib/spa-0.2:/opt/underpants/runtime/lib/spa-0.2:/usr/lib64/spa-0.2:${{SPA_PLUGIN_DIR:-/usr/lib64/spa-0.2}}"
export PIPEWIRE_MODULE_DIR="${{APP_ROOT}}/lib/pipewire-0.3:/opt/underpants/runtime/lib/pipewire-0.3:/usr/lib64/pipewire-0.3:${{PIPEWIRE_MODULE_DIR:-/usr/lib64/pipewire-0.3}}"

# GObject Introspection Typelib Path (Crucial for GTK/WebKit/GI apps)
export GI_TYPELIB_PATH="${{APP_ROOT}}/lib/girepository-1.0:${{APP_ROOT}}/lib64/girepository-1.0:${{APP_ROOT}}/share/gir-1.0:/opt/underpants/runtime/lib/girepository-1.0:/opt/underpants/common/lib/girepository-1.0:${{GI_TYPELIB_PATH:-/usr/lib64/girepository-1.0}}"

# GSettings Schemas (GLib/GTK4/Libadwaita)
if [ -d "${{APP_ROOT}}/share/glib-2.0/schemas" ]; then
  export GSETTINGS_SCHEMA_DIR="${{APP_ROOT}}/share/glib-2.0/schemas:${{GSETTINGS_SCHEMA_DIR:-/usr/share/glib-2.0/schemas}}"
fi

# GIO Modules (TLS/Networking - 64-bit strict)
if [ -d "${{APP_ROOT}}/lib/gio/modules" ] || [ -d "${{APP_ROOT}}/lib64/gio/modules" ]; then
  export GIO_MODULE_DIR="${{APP_ROOT}}/lib/gio/modules:${{APP_ROOT}}/lib64/gio/modules:${{GIO_MODULE_DIR:-/usr/lib64/gio/modules}}"
fi

# GTK Input Method Safety (Preserve default simple context unless explicitly specified)
if [ -n "${{GTK_IM_MODULE:-}}" ] && [ "${{GTK_IM_MODULE}}" = "ibus" ]; then
  export GTK_IM_MODULE=""
fi
if [ -n "${{QT_IM_MODULE:-}}" ] && [ "${{QT_IM_MODULE}}" = "ibus" ]; then
  export QT_IM_MODULE=""
fi

# GTK 64-bit Input Modules & Path Wiring (Scoped strictly to isolated environment to prevent GTK2/3 ABI collisions and 32-bit Multilib ELFCLASS warnings)
export GTK_PATH="${{APP_ROOT}}/lib/gtk-3.0:${{APP_ROOT}}/lib/gtk-2.0:/opt/underpants/runtime/lib/gtk-3.0:/opt/underpants/runtime/lib/gtk-2.0:${{GTK_PATH:-/usr/lib64/gtk-3.0}}"
if [ -f "${{APP_ROOT}}/lib/gtk-3.0/3.0.0/immodules.cache" ]; then
  export GTK_IM_MODULE_FILE="${{APP_ROOT}}/lib/gtk-3.0/3.0.0/immodules.cache"
elif [ -f "/opt/underpants/runtime/lib/gtk-3.0/3.0.0/immodules.cache" ]; then
  export GTK_IM_MODULE_FILE="/opt/underpants/runtime/lib/gtk-3.0/3.0.0/immodules.cache"
fi

# GdkPixbuf 64-bit Image & SVG Loaders Cache (Prefer host native Slackware librsvg, then clean isolated loaders)
if [ -f "/usr/lib64/gdk-pixbuf-2.0/2.10.0/loaders.cache" ]; then
  export GDK_PIXBUF_MODULE_FILE="/usr/lib64/gdk-pixbuf-2.0/2.10.0/loaders.cache"
elif [ -f "${{APP_ROOT}}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache" ]; then
  export GDK_PIXBUF_MODULE_FILE="${{APP_ROOT}}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"
elif [ -f "/opt/underpants/runtime/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache" ]; then
  export GDK_PIXBUF_MODULE_FILE="/opt/underpants/runtime/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"
fi
if [ -d "/usr/lib64/gdk-pixbuf-2.0/2.10.0/loaders" ]; then
  export GDK_PIXBUF_MODULEDIR="/usr/lib64/gdk-pixbuf-2.0/2.10.0/loaders"
elif [ -d "${{APP_ROOT}}/lib/gdk-pixbuf-2.0/2.10.0/loaders" ]; then
  export GDK_PIXBUF_MODULEDIR="${{APP_ROOT}}/lib/gdk-pixbuf-2.0/2.10.0/loaders"
elif [ -d "/opt/underpants/runtime/lib/gdk-pixbuf-2.0/2.10.0/loaders" ]; then
  export GDK_PIXBUF_MODULEDIR="/opt/underpants/runtime/lib/gdk-pixbuf-2.0/2.10.0/loaders"
fi

# Universal Glycin & Bubblewrap Sandbox Shield (Route loaders and run directly without bwrap)
if [ -d "${{APP_ROOT}}/share/glycin-loaders" ]; then
  export GLYCIN_DATA_DIR="${{APP_ROOT}}/share"
elif [ -d "/opt/underpants/runtime/share/glycin-loaders" ]; then
  export GLYCIN_DATA_DIR="/opt/underpants/runtime/share"
fi
export GLYCIN_LOADERS_DIR="${{APP_ROOT}}/lib/glycin-loaders/2+:/opt/underpants/runtime/lib/glycin-loaders/2+:/usr/lib64/glycin-loaders/2+"
export GLYCIN_DISABLE_SANDBOX="1"
export LIBGLYCIN_DISABLE_SANDBOX="1"
export GLYCIN_NO_SANDBOX="1"

# GStreamer Plugins
if [ -d "${{APP_ROOT}}/lib/gstreamer-1.0" ] || [ -d "${{APP_ROOT}}/lib64/gstreamer-1.0" ]; then
  export GST_PLUGIN_SYSTEM_PATH_1_0="${{APP_ROOT}}/lib/gstreamer-1.0:${{APP_ROOT}}/lib64/gstreamer-1.0:${{GST_PLUGIN_SYSTEM_PATH_1_0:-/usr/lib64/gstreamer-1.0}}"
fi

# Intelligent Qt Wayland / XCB platform fallback guard
if [ -n "${{WAYLAND_DISPLAY:-}}" ]; then
  if [ ! -f "${{APP_ROOT}}/lib/qt/plugins/platforms/libqwayland-egl.so" ] && \\
     [ ! -f "${{APP_ROOT}}/lib/qt6/plugins/platforms/libqwayland-egl.so" ] && \\
     [ ! -f "${{APP_ROOT}}/lib/qt/plugins/platforms/libqwayland-generic.so" ] && \\
     [ ! -f "${{APP_ROOT}}/lib/qt6/plugins/platforms/libqwayland-generic.so" ] && \\
     [ ! -f "/opt/underpants/runtime/lib/qt/plugins/platforms/libqwayland-egl.so" ] && \\
     [ ! -f "/opt/underpants/runtime/lib/qt6/plugins/platforms/libqwayland-egl.so" ] && \\
     [ ! -f "/usr/lib64/qt5/plugins/platforms/libqwayland-egl.so" ] && \\
     [ ! -f "/usr/lib64/qt6/plugins/platforms/libqwayland-egl.so" ]; then
    export QT_QPA_PLATFORM="xcb"
  else
    export QT_QPA_PLATFORM="${{QT_QPA_PLATFORM:-wayland;xcb}}"
  fi
fi

# Qt6 & Qt5 Plugins & Imports
_QT_PLUGINS=""
for _qp in "${{APP_ROOT}}/lib/qt6/plugins" "${{APP_ROOT}}/lib64/qt6/plugins" \\
           "${{APP_ROOT}}/lib/qt/plugins" "${{APP_ROOT}}/lib64/qt/plugins" \\
           "${{APP_ROOT}}/lib/plugins" \\
           /opt/underpants/runtime/lib/qt6/plugins /opt/underpants/runtime/lib/qt/plugins \\
           /usr/lib64/qt6/plugins /usr/lib64/qt5/plugins; do
  if [ -d "${{_qp}}" ]; then
    _QT_PLUGINS="${{_QT_PLUGINS:+${{_QT_PLUGINS}}:}}${{_qp}}"
  fi
done
if [ -n "${{_QT_PLUGINS}}" ]; then
  export QT_PLUGIN_PATH="${{_QT_PLUGINS}}${{QT_PLUGIN_PATH:+:${{QT_PLUGIN_PATH}}}}"
fi
if [ -d "${{APP_ROOT}}/lib/qt6/qml" ] || [ -d "${{APP_ROOT}}/lib64/qt6/qml" ]; then
  export QML2_IMPORT_PATH="${{APP_ROOT}}/lib/qt6/qml:${{APP_ROOT}}/lib64/qt6/qml:${{QML2_IMPORT_PATH:-}}"
fi

# Audio, DSP & Image processing plugin paths
if [ -d "${{APP_ROOT}}/lib/ladspa" ] || [ -d "/opt/underpants/runtime/lib/ladspa" ]; then
  export LADSPA_PATH="${{APP_ROOT}}/lib/ladspa:/opt/underpants/runtime/lib/ladspa:${{LADSPA_PATH:-/usr/lib64/ladspa}}"
fi
if [ -d "${{APP_ROOT}}/lib/lv2" ] || [ -d "/opt/underpants/runtime/lib/lv2" ]; then
  export LV2_PATH="${{APP_ROOT}}/lib/lv2:/opt/underpants/runtime/lib/lv2:${{LV2_PATH:-/usr/lib64/lv2}}"
fi
if [ -d "${{APP_ROOT}}/lib/gegl-0.4" ] || [ -d "${{APP_ROOT}}/lib/gegl-0.3" ]; then
  export GEGL_PATH="${{APP_ROOT}}/lib/gegl-0.4:${{APP_ROOT}}/lib/gegl-0.3:${{GEGL_PATH:-}}"
fi
if [ -d "${{APP_ROOT}}/lib/babl-0.1" ]; then
  export BABL_PATH="${{APP_ROOT}}/lib/babl-0.1:${{BABL_PATH:-}}"
fi
if [ -d "${{APP_ROOT}}/lib/frei0r-1" ]; then
  export FREI0R_PATH="${{APP_ROOT}}/lib/frei0r-1:${{FREI0R_PATH:-/usr/lib64/frei0r-1}}"
fi

# Mesa OpenGL / DRI / GBM 64-bit Drivers (Conditioned for non-NVIDIA systems)
if [ ! -c /dev/nvidia0 ] && [ ! -f /usr/lib64/libGLX_nvidia.so.0 ]; then
  export GBM_BACKENDS_PATH="/usr/lib64/gbm:${{APP_ROOT}}/lib/gbm:/opt/underpants/runtime/lib/gbm:${{GBM_BACKENDS_PATH:-}}"
  export GBM_DRIVERS_PATH="/usr/lib64/gbm:${{APP_ROOT}}/lib/gbm:/opt/underpants/runtime/lib/gbm:${{GBM_DRIVERS_PATH:-}}"
  export LIBGL_DRIVERS_PATH="/usr/lib64/dri:${{APP_ROOT}}/lib/dri:/opt/underpants/runtime/lib/dri:${{LIBGL_DRIVERS_PATH:-}}"
  export DRI_DRIVER_PATH="/usr/lib64/dri:${{APP_ROOT}}/lib/dri:/opt/underpants/runtime/lib/dri:${{DRI_DRIVER_PATH:-}}"
else
  export __EGL_VENDOR_LIBRARY_DIRS="/usr/share/glvnd/egl_vendor.d:${{APP_ROOT}}/share/glvnd/egl_vendor.d:/opt/underpants/runtime/share/glvnd/egl_vendor.d:${{__EGL_VENDOR_LIBRARY_DIRS:-}}"
  export QT_XCB_GL_INTEGRATION="${{QT_XCB_GL_INTEGRATION:-xcb_glx}}"
fi

# Electron and deep helper binary directories
for _edir in "${{APP_ROOT}}/lib"/electron* "${{APP_ROOT}}/lib/{actual_name}"/electron*; do
  if [ -d "${{_edir}}" ]; then
    export PATH="${{_edir}}:${{PATH}}"
    export LD_LIBRARY_PATH="${{_edir}}:${{LD_LIBRARY_PATH}}"
  fi
done

# Office & Document Suite UI Engine (Intelligent Desktop Environment Auto-Detection)
if [ "{actual_name}" = "libreoffice-fresh" ] || [ "{actual_name}" = "libreoffice-still" ] || [ "{actual_name}" = "libreoffice" ] || [ "{bname}" = "libreoffice" ] || [ "{bname}" = "soffice" ]; then
  if [ -z "${{SAL_USE_VCLPLUGIN:-}}" ]; then
    if [ "${{XDG_CURRENT_DESKTOP:-}}" = "KDE" ] || [ -n "${{KDE_FULL_SESSION:-}}" ]; then
      if [ -f "${{APP_ROOT}}/lib/libreoffice/program/libvclplug_kf5lo.so" ] || [ -f "${{APP_ROOT}}/lib/libreoffice/program/libvclplug_qt5lo.so" ]; then
        export SAL_USE_VCLPLUGIN="kf5"
      elif [ -f "${{APP_ROOT}}/lib/libreoffice/program/libvclplug_kf6lo.so" ] || [ -f "${{APP_ROOT}}/lib/libreoffice/program/libvclplug_qt6lo.so" ]; then
        export SAL_USE_VCLPLUGIN="kf6"
      elif [ -f "${{APP_ROOT}}/lib/libreoffice/program/libvclplug_gtk3lo.so" ]; then
        export SAL_USE_VCLPLUGIN="gtk3"
      else
        export SAL_USE_VCLPLUGIN="gen"
      fi
    else
      export SAL_USE_VCLPLUGIN="gtk3"
    fi
  fi
fi

# Vulkan Layers
if [ -d "${{APP_ROOT}}/share/vulkan/explicit_layer.d" ]; then
  export VK_LAYER_PATH="${{APP_ROOT}}/share/vulkan/explicit_layer.d:${{APP_ROOT}}/share/vulkan/implicit_layer.d:${{VK_LAYER_PATH:-}}"
fi

# Universal Python Module & Private Library Auto-Discovery
_PY_DIRS=""
for _d in "${{APP_ROOT}}"/lib/python*/site-packages \\
          "${{APP_ROOT}}"/lib64/python*/site-packages \\
          "${{APP_ROOT}}"/lib/* \\
          "${{APP_ROOT}}"/lib/{actual_name}/lib \\
          "${{APP_ROOT}}"/lib/{actual_name}/Mod \\
          "${{APP_ROOT}}"/share/* \\
          /opt/underpants/runtime/lib/python*/site-packages \\
          /opt/underpants/runtime/lib64/python*/site-packages; do
  if [ -d "${{_d}}" ]; then
    _PY_DIRS="${{_PY_DIRS:+${{_PY_DIRS}}:}}${{_d}}"
  fi
done
if [ -n "${{_PY_DIRS}}" ]; then
  export PYTHONPATH="${{_PY_DIRS}}${{PYTHONPATH:+:${{PYTHONPATH}}}}"
fi

# Universal Application Resource & Environment Auto-Wiring
if [ -d "${{APP_ROOT}}/lib/{actual_name}" ]; then
  export {upper_app}_PYTHON_PATH="${{APP_ROOT}}/lib/{actual_name}"
fi
if [ -d "${{APP_ROOT}}/share/{actual_name}" ]; then
  export {upper_app}_RESOURCES_PATH="${{APP_ROOT}}/share/{actual_name}"
  export {upper_app}_DATA_DIR="${{APP_ROOT}}/share/{actual_name}"
fi
if [ -d "${{APP_ROOT}}/lib/{actual_name}/{actual_name}/plugins" ]; then
  export {upper_app}_EXTENSIONS_PATH="${{APP_ROOT}}/lib/{actual_name}/{actual_name}/plugins"
  export {upper_app}_PLUGINS_PATH="${{APP_ROOT}}/lib/{actual_name}/{actual_name}/plugins"
elif [ -d "${{APP_ROOT}}/lib/{actual_name}/plugins" ]; then
  export {upper_app}_EXTENSIONS_PATH="${{APP_ROOT}}/lib/{actual_name}/plugins"
  export {upper_app}_PLUGINS_PATH="${{APP_ROOT}}/lib/{actual_name}/plugins"
fi

# Binary search path
export PATH="${{APP_ROOT}}/bin:${{APP_ROOT}}/lib/{actual_name}/bin:/opt/underpants/runtime/bin:${{PATH}}"

# Smart Target Binary Universal Resolver
TARGET_BIN=""

# 1. Exact match in ${{APP_ROOT}}/bin/${{bname}}
if [ -x "${{APP_ROOT}}/bin/{bname}" ] && [ ! -d "${{APP_ROOT}}/bin/{bname}" ]; then
  TARGET_BIN="${{APP_ROOT}}/bin/{bname}"

# 2. Exact match in ${{APP_ROOT}}/lib/ (deep apps like chromium, electron, etc.)
elif [ -x "${{APP_ROOT}}/lib/chromium/{bname}" ] && [ ! -d "${{APP_ROOT}}/lib/chromium/{bname}" ]; then
  TARGET_BIN="${{APP_ROOT}}/lib/chromium/{bname}"
elif [ -x "${{APP_ROOT}}/lib/{actual_name}/{bname}" ] && [ ! -d "${{APP_ROOT}}/lib/{actual_name}/{bname}" ]; then
  TARGET_BIN="${{APP_ROOT}}/lib/{actual_name}/{bname}"
elif [ -x "${{APP_ROOT}}/lib/{actual_name}/{actual_name}" ] && [ ! -d "${{APP_ROOT}}/lib/{actual_name}/{actual_name}" ]; then
  TARGET_BIN="${{APP_ROOT}}/lib/{actual_name}/{actual_name}"
fi

# 3. Versioned executable prefix match in ${{APP_ROOT}}/bin (e.g. ardour -> ardour8 / ardour9, octave -> octave-cli)
if [ -z "${{TARGET_BIN}}" ]; then
  for _v_cand in "${{APP_ROOT}}/bin/{bname}"[0-9]* "${{APP_ROOT}}/bin/{bname}-"[0-9]* "${{APP_ROOT}}/bin/{actual_name}"[0-9]* "${{APP_ROOT}}/bin/{actual_name}-"[0-9]*; do
    if [ -x "${{_v_cand}}" ] && [ ! -d "${{_v_cand}}" ]; then
      TARGET_BIN="${{_v_cand}}"
      break
    fi
  done
fi

# 4. Suffix-stripped name match (e.g. drawio-desktop -> drawio, telegram-desktop -> telegram)
if [ -z "${{TARGET_BIN}}" ]; then
  _stripped="{bname}"
  _stripped="$(echo "${{_stripped}}" | sed -E 's/-(desktop|bin|app|gui|qt5|qt6|gtk3|gtk4|gtk|cli|plus|pro)//g')"
  if [ -n "${{_stripped}}" ] && [ -x "${{APP_ROOT}}/bin/${{_stripped}}" ] && [ ! -d "${{APP_ROOT}}/bin/${{_stripped}}" ]; then
    TARGET_BIN="${{APP_ROOT}}/bin/${{_stripped}}"
  fi
fi

# 5. Application Desktop Entry Parsing (Check Exec= in share/applications/*.desktop)
if [ -z "${{TARGET_BIN}}" ]; then
  for _df in "${{APP_ROOT}}/share/applications"/*.desktop /usr/share/applications/"{actual_name}"*.desktop /usr/share/applications/"{bname}"*.desktop; do
    if [ -f "${{_df}}" ]; then
      _exec_cmd="$(grep -E '^Exec=' "${{_df}}" 2>/dev/null | head -n1 | sed -E 's/^Exec=([^ %]+).*/\\1/')"
      if [ -n "${{_exec_cmd}}" ]; then
        _exec_base="$(basename "${{_exec_cmd}}")"
        if [ -x "${{APP_ROOT}}/bin/${{_exec_base}}" ] && [ ! -d "${{APP_ROOT}}/bin/${{_exec_base}}" ]; then
          TARGET_BIN="${{APP_ROOT}}/bin/${{_exec_base}}"
          break
        elif [ -x "${{APP_ROOT}}/lib/{actual_name}/${{_exec_base}}" ] && [ ! -d "${{APP_ROOT}}/lib/{actual_name}/${{_exec_base}}" ]; then
          TARGET_BIN="${{APP_ROOT}}/lib/{actual_name}/${{_exec_base}}"
          break
        fi
      fi
    fi
  done
fi

# 6. Case-insensitive scan in ${{APP_ROOT}}/bin and ${{APP_ROOT}}/lib/{actual_name}/bin
if [ -z "${{TARGET_BIN}}" ]; then
  _target_lower="$(echo "{bname}" | tr '[:upper:]' '[:lower:]')"
  _pkg_lower="$(echo "{actual_name}" | tr '[:upper:]' '[:lower:]')"
  for _cand in "${{APP_ROOT}}/bin"/* "${{APP_ROOT}}/lib/{actual_name}/bin"/* "${{APP_ROOT}}/lib/{actual_name}"/*; do
    if [ -f "${{_cand}}" ] || [ -L "${{_cand}}" ]; then
      if [ -x "${{_cand}}" ] && [ ! -d "${{_cand}}" ]; then
        _cbase="$(basename "${{_cand}}")"
        _clower="$(echo "${{_cbase}}" | tr '[:upper:]' '[:lower:]')"
        if [ "${{_clower}}" = "${{_target_lower}}" ] || [ "${{_clower}}" = "${{_pkg_lower}}" ]; then
          TARGET_BIN="${{_cand}}"
          break
        fi
      fi
    fi
  done
fi

# 7. Single primary executable fallback if only 1 executable exists in ${{APP_ROOT}}/bin
if [ -z "${{TARGET_BIN}}" ]; then
  _bin_count=0
  _first_bin=""
  for _cand in "${{APP_ROOT}}/bin"/*; do
    if [ -x "${{_cand}}" ] && [ ! -d "${{_cand}}" ]; then
      _bin_count=$((_bin_count + 1))
      if [ -z "${{_first_bin}}" ]; then
        _first_bin="${{_cand}}"
      fi
    fi
  done
  if [ ${{_bin_count}} -eq 1 ] && [ -n "${{_first_bin}}" ]; then
    TARGET_BIN="${{_first_bin}}"
  fi
fi

# 8. Absolute fallback
if [ -z "${{TARGET_BIN}}" ]; then
  TARGET_BIN="${{APP_ROOT}}/bin/{bname}"
fi

# Smart Shebang & Hybrid Runtime Selector
if [ -f "${{TARGET_BIN}}" ] && head -n1 "${{TARGET_BIN}}" 2>/dev/null | grep -qE '^#!.*python'; then
  if [ -x "${{APP_ROOT}}/bin/python3" ]; then
    exec "${{APP_ROOT}}/bin/python3" "${{TARGET_BIN}}" "$@"
  elif [ -x "/opt/underpants/runtime/bin/python3" ]; then
    exec "/opt/underpants/runtime/bin/python3" "${{TARGET_BIN}}" "$@"
  elif command -v python3 >/dev/null 2>&1; then
    exec python3 "${{TARGET_BIN}}" "$@"
  fi
fi

# Universal Modular Plugin Injection (e.g. Zathura --plugins-dir)
if [ "{actual_name}" = "zathura" ] && [ -d "${{APP_ROOT}}/lib/zathura" ]; then
  case "$*" in
    *--plugins-dir*|*-p\\ *) ;;
    *) set -- --plugins-dir="${{APP_ROOT}}/lib/zathura" "$@" ;;
  esac
fi

exec "${{TARGET_BIN}}" "$@"
"""

    @staticmethod
    def _format_size(num_bytes: float) -> str:
        """Format bytes to exact Pacman style string (e.g. 1954.9 KiB, 27.2 MiB, 1.2 GiB)."""
        if num_bytes < 1024:
            return f"{num_bytes:.1f} B"
        elif num_bytes < 1024 * 1024:
            return f"{num_bytes / 1024.0:.1f} KiB"
        elif num_bytes < 1024 * 1024 * 1024:
            return f"{num_bytes / (1024.0 * 1024.0):.1f} MiB"
        else:
            return f"{num_bytes / (1024.0 * 1024.0 * 1024.0):.1f} GiB"

    @staticmethod
    def _format_speed(bytes_per_sec: float) -> str:
        """Format bytes/sec to Pacman style speed (e.g. 768.0 KiB/s, 2.19 MiB/s)."""
        if bytes_per_sec <= 0:
            return "  0.0 B/s"
        elif bytes_per_sec < 1024 * 1024:
            return f"{bytes_per_sec / 1024.0:.1f} KiB/s"
        else:
            return f"{bytes_per_sec / (1024.0 * 1024.0):.2f} MiB/s"

    @classmethod
    @classmethod
    def render_gnome_bar(cls, pct: float, width: int = 28, chomp_state: int = 0) -> str:
        """Pacman S/s progress bar eating small 'o' pellets (ILoveCandy style)."""
        pct = max(0.0, min(100.0, pct))
        pct_str = f"{int(pct):>3d}%"
        if pct >= 100.0:
            return f"[{'-' * width}] 100%"
        pos = int((pct / 100.0) * width)
        pos = min(width - 1, max(0, pos))
        eaten = "-" * pos
        # Animated S/s mouth toggling ~1.4 toggles/sec (Slackware Bold Blue S/s)
        mouth_open = (chomp_state % 2 == 0)
        eater = "\033[1;34mS\033[0m" if mouth_open else "\033[1;34ms\033[0m"
        rem_len = max(0, width - pos - 1)
        food_chars = ["o" if (i % 2 == 0) else " " for i in range(rem_len)]
        food = "".join(food_chars)
        return f"[{eaten}{eater}{food}] {pct_str}"

    @classmethod
    def render_gnome_mini_bar(cls, pct: float, width: int = 28) -> str:
        return cls.render_gnome_bar(pct, width=width)

    def download_packages_parallel(self, pkgs: List[Dict[str, Any]], verbose: bool = True) -> List[Tuple[Dict[str, Any], str]]:
        """Download multiple packages using parallel worker threads with in-place ILoveCandy progress (Pacman style)."""
        if not pkgs:
            return []

        total_pkgs = len(pkgs)
        total_bytes_expected = sum(int(p.get("CSIZE", 15 * 1024 * 1024)) for p in pkgs)
        downloaded_results: List[Tuple[Dict[str, Any], str]] = []

        headers = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) Slacky-Update/0.17.0 UnderpantsGnomes"}
        lock = threading.Lock()
        slot_lock = threading.Lock()
        print_lock = threading.Lock()
        completed_bytes = [0]
        completed_count = [0]
        active_parts: Dict[str, int] = {}
        stop_event = threading.Event()

        needed_pkgs: List[Dict[str, Any]] = []
        for p in pkgs:
            url = self.engine.get_download_url(p)
            if not url:
                continue
            filename = p.get("FILENAME") or os.path.basename(url)
            local_path = os.path.join(self.cache_pkg_dir, filename)
            expected_csize = int(p.get("CSIZE", 0))
            if os.path.exists(local_path):
                if self.is_valid_pkg_archive(local_path, expected_csize):
                    downloaded_results.append((p, local_path))
                    completed_bytes[0] += os.path.getsize(local_path)
                    completed_count[0] += 1
                else:
                    try:
                        os.remove(local_path)
                    except Exception:
                        pass
                    needed_pkgs.append(p)
            else:
                needed_pkgs.append(p)

        if not needed_pkgs:
            if verbose:
                print(f"  ✓ All {total_pkgs} package payload(s) ready in local cache.")
            return downloaded_results

        needed_bytes = sum(int(p.get("CSIZE", 15 * 1024 * 1024)) for p in needed_pkgs)
        tot_mb = needed_bytes / (1024 * 1024)
        if verbose:
            print(f"\033[1;36m:: Fetching {len(needed_pkgs)} package payload(s) [{tot_mb:.2f} MB]...\033[0m")
            print("   🩲 Step 1: Steal Underpants  ➔  Step 2: ? ? ? ?  ➔  🧙 💰 Step 3: PROFIT!\n")

        num_workers = min(len(needed_pkgs), 10)
        available_slots = list(range(num_workers))
        worker_status: Dict[int, Dict[str, Any]] = {
            i: {
                "active": False,
                "pkg_index": 0,
                "name": "",
                "ver": "",
                "repo": "",
                "cur": 0,
                "total": 0,
                "speed": 0.0,
                "start_t": 0.0
            }
            for i in range(num_workers)
        }
        is_tty = sys.stdout.isatty()
        lines_printed = [0]
        start_t = time.time()
        bar_width = 28

        for idx, p in enumerate(pkgs):
            p["_INDEX"] = idx + 1

        def monitor():
            first_draw = True
            if is_tty:
                sys.stdout.write("\033[?25l")
                sys.stdout.flush()
            while not stop_event.is_set():
                time.sleep(0.14)
                now = time.time()
                chomp_step = int(now / 0.35)

                with lock:
                    cur_comp = completed_bytes[0]
                    for psize in active_parts.values():
                        cur_comp += psize
                    c_cnt = completed_count[0]

                pct = (cur_comp / total_bytes_expected * 100.0) if total_bytes_expected > 0 else 0.0
                bar = self.render_gnome_bar(pct, width=bar_width, chomp_state=chomp_step)
                elapsed = max(0.001, now - start_t)
                speed_bps = cur_comp / elapsed
                spd_str_tot = self._format_speed(speed_bps)
                rem_bytes = max(0, total_bytes_expected - cur_comp)
                if speed_bps > 1024 and rem_bytes > 0:
                    eta_sec = int(rem_bytes / speed_bps)
                    eta_str = f"{eta_sec // 60:02d}:{eta_sec % 60:02d}"
                elif cur_comp >= total_bytes_expected or pct >= 100.0:
                    eta_str = "00:00"
                else:
                    eta_str = "--:--"

                tot_size_str = self._format_size(total_bytes_expected)

                if is_tty:
                    with slot_lock:
                        slots_snapshot = [dict(worker_status[i]) for i in range(num_workers)]

                    with print_lock:
                        if not first_draw and lines_printed[0] > 0:
                            sys.stdout.write(f"\033[{lines_printed[0]}A")

                        output_lines = []
                        for sid, sinfo in enumerate(slots_snapshot):
                            if sinfo["active"] and sinfo["name"]:
                                w_cur = sinfo["cur"]
                                w_tot = sinfo["total"]
                                w_pct = (w_cur / w_tot * 100.0) if w_tot > 0 else 0.0
                                w_spd = sinfo.get("speed", 0.0)
                                w_spd_str = self._format_speed(w_spd * 1024 * 1024)
                                rem_w_bytes = max(0, w_tot - w_cur)
                                if w_spd > 0.001 and rem_w_bytes > 0:
                                    w_eta_sec = int((rem_w_bytes / (1024 * 1024)) / w_spd)
                                    w_eta = f"{w_eta_sec // 60:02d}:{w_eta_sec % 60:02d}"
                                else:
                                    w_eta = "00:00" if w_pct >= 100 else "--:--"

                                w_bar = self.render_gnome_bar(w_pct, width=bar_width, chomp_state=chomp_step + sid)
                                pname = sinfo["name"]
                                pver = sinfo.get("ver", "")
                                full_n = f"{pname}-{pver}" if pver else pname
                                disp_n = (full_n[:30] + "...") if len(full_n) > 32 else full_n
                                w_sz_str = self._format_size(w_tot if w_tot > 0 else w_cur)
                                output_lines.append(f"{disp_n:<32} {w_sz_str:>10} {w_spd_str:>11} {w_eta:>5} {w_bar}")

                        # Total summary line matching Pacman style
                        tot_label = f"Total ({c_cnt}/{total_pkgs})"
                        output_lines.append(f"{tot_label:<32} {tot_size_str:>10} {spd_str_tot:>11} {eta_str:>5} {bar}")

                        out_block = "".join(f"\033[2K\r{l}\n" for l in output_lines)
                        sys.stdout.write(out_block)
                        sys.stdout.flush()
                        lines_printed[0] = len(output_lines)
                        first_draw = False
                else:
                    line = f"\rTotal: {bar} [{tot_size_str}] ({c_cnt}/{total_pkgs} pkgs) [{spd_str_tot} | ETA: {eta_str}] "
                    sys.stdout.write(line)
                    sys.stdout.flush()

        mon_t = None
        if verbose:
            mon_t = threading.Thread(target=monitor, daemon=True)
            mon_t.start()

        def fetch_one(pkg_data: Dict[str, Any]) -> Optional[Tuple[Dict[str, Any], str]]:
            candidates = self.engine.get_download_urls_candidates(pkg_data)
            if not candidates:
                return None

            filename = pkg_data.get("FILENAME") or os.path.basename(candidates[0])
            local_path = os.path.join(self.cache_pkg_dir, filename)
            part_path = local_path + ".part"
            expected_csize = int(pkg_data.get("CSIZE", 0))
            p_idx = pkg_data.get("_INDEX", 1)

            slot_id = None
            with slot_lock:
                if available_slots:
                    slot_id = available_slots.pop(0)
                    worker_status[slot_id] = {
                        "active": True,
                        "pkg_index": p_idx,
                        "name": pkg_data.get("NAME", "pkg"),
                        "ver": pkg_data.get("VERSION", ""),
                        "repo": pkg_data.get("_REPO", "upstream"),
                        "cur": 0,
                        "total": expected_csize,
                        "speed": 0.0,
                        "start_t": time.time()
                    }

            with lock:
                active_parts[part_path] = 0

            download_success = False
            for cand_url in candidates:
                for attempt in range(3):
                    try:
                        if attempt > 0:
                            time.sleep(0.3 * attempt)
                        req = urllib.request.Request(cand_url, headers=headers)
                        with urllib.request.urlopen(req, timeout=35) as resp:
                            first_chunk = resp.read(8192)
                            if not first_chunk:
                                continue
                            if first_chunk.startswith(b"<html") or first_chunk.startswith(b"<!DOCTYPE") or first_chunk.startswith(b"<!doctype") or b"<html" in first_chunk.lower() or b"<head" in first_chunk.lower():
                                continue
                            if filename.endswith(".zst") and not first_chunk.startswith(b"\x28\xb5\x2f\xfd"):
                                continue
                            if filename.endswith(".xz") and not first_chunk.startswith(b"\xfd7zXZ\x00"):
                                continue
                            if filename.endswith(".gz") and not first_chunk.startswith(b"\x1f\x8b"):
                                continue

                            with open(part_path, "wb") as f:
                                f.write(first_chunk)
                                dl_cur = len(first_chunk)
                                w_start = time.time()
                                while True:
                                    chunk = resp.read(65536)
                                    if not chunk:
                                        break
                                    f.write(chunk)
                                    dl_cur += len(chunk)
                                    w_elapsed = max(0.001, time.time() - w_start)
                                    if slot_id is not None:
                                        with slot_lock:
                                            worker_status[slot_id]["cur"] = dl_cur
                                            worker_status[slot_id]["speed"] = (dl_cur / (1024 * 1024)) / w_elapsed
                                    with lock:
                                        active_parts[part_path] = dl_cur

                        if os.path.exists(part_path) and self.is_valid_pkg_archive(part_path, expected_csize):
                            shutil.move(part_path, local_path)
                            download_success = True
                            break
                        else:
                            if os.path.exists(part_path):
                                try:
                                    os.remove(part_path)
                                except Exception:
                                    pass
                    except Exception:
                        if os.path.exists(part_path):
                            try:
                                os.remove(part_path)
                            except Exception:
                                pass
                        continue
                if download_success:
                    break

            with lock:
                if part_path in active_parts:
                    del active_parts[part_path]
                if download_success and os.path.exists(local_path):
                    completed_bytes[0] += os.path.getsize(local_path)
                    completed_count[0] += 1

            if download_success and os.path.exists(local_path):
                sz_bytes = os.path.getsize(local_path)
                sz_str = self._format_size(sz_bytes)
                spd_str = self._format_speed(worker_status[slot_id]["speed"] * 1024 * 1024) if slot_id is not None else "  -- B/s"
                pname = pkg_data.get("NAME", "pkg")
                pver = pkg_data.get("VERSION", "")
                full_name = f"{pname}-{pver}" if pver else pname
                disp_name = (full_name[:30] + "...") if len(full_name) > 32 else full_name

            if slot_id is not None:
                with slot_lock:
                    worker_status[slot_id]["active"] = False
                    worker_status[slot_id]["name"] = ""
                    available_slots.append(slot_id)

            if download_success:
                return (pkg_data, local_path)
            return None

        with concurrent.futures.ThreadPoolExecutor(max_workers=num_workers) as executor:
            future_to_pkg = {executor.submit(fetch_one, p): p for p in needed_pkgs}
            for future in concurrent.futures.as_completed(future_to_pkg):
                res = future.result()
                if res:
                    downloaded_results.append(res)

        stop_event.set()
        if mon_t:
            mon_t.join(timeout=1.0)
            if verbose and is_tty:
                sys.stdout.write("\033[?25h")
                with print_lock:
                    if lines_printed[0] > 0:
                        sys.stdout.write(f"\033[{lines_printed[0]}A")
                        for _ in range(lines_printed[0]):
                            sys.stdout.write("\033[2K\r\n")
                        sys.stdout.write(f"\033[{lines_printed[0]}A")
                    elapsed = max(0.001, time.time() - start_t)
                    avg_speed_bps = total_bytes_expected / elapsed
                    tot_bar = f"[{'-' * bar_width}] 100%"
                    tot_sz_str = self._format_size(total_bytes_expected)
                    tot_spd_str = self._format_speed(avg_speed_bps)
                    tot_label = f"Total ({total_pkgs}/{total_pkgs})"
                    tot_time_str = f"{int(elapsed) // 60:02d}:{int(elapsed) % 60:02d}"
                    sys.stdout.write(f"\033[2K\r{tot_label:<32} {tot_sz_str:>10} {tot_spd_str:>11} {tot_time_str:>5} {tot_bar}\n\n")
                    sys.stdout.flush()

        # Second Pass: Sequential recovery pass for any transiently missed packages
        downloaded_names = {r[0].get("NAME") for r in downloaded_results}
        missing_pkgs = [p for p in needed_pkgs if p.get("NAME") not in downloaded_names]
        if missing_pkgs:
            if verbose:
                print(f"  :: Retrying {len(missing_pkgs)} missed payload(s) in sequential recovery pass...")
            for p in missing_pkgs:
                candidates = self.engine.get_download_urls_candidates(p)
                if not candidates:
                    continue
                filename = p.get("FILENAME") or os.path.basename(candidates[0])
                local_path = os.path.join(self.cache_pkg_dir, filename)
                part_path = local_path + ".part"
                expected_csize = int(p.get("CSIZE", 0))
                recov_success = False

                for cand_url in candidates:
                    for attempt in range(3):
                        try:
                            if attempt > 0:
                                time.sleep(0.5 * attempt)
                            req = urllib.request.Request(cand_url, headers=headers)
                            with urllib.request.urlopen(req, timeout=45) as resp:
                                first_chunk = resp.read(8192)
                                if not first_chunk or first_chunk.startswith(b"<html") or first_chunk.startswith(b"<!DOCTYPE") or first_chunk.startswith(b"<!doctype") or b"<html" in first_chunk.lower() or b"<head" in first_chunk.lower():
                                    continue
                                if filename.endswith(".zst") and not first_chunk.startswith(b"\x28\xb5\x2f\xfd"):
                                    continue
                                if filename.endswith(".xz") and not first_chunk.startswith(b"\xfd7zXZ\x00"):
                                    continue
                                if filename.endswith(".gz") and not first_chunk.startswith(b"\x1f\x8b"):
                                    continue

                                with open(part_path, "wb") as f:
                                    f.write(first_chunk)
                                    while True:
                                        chunk = resp.read(65536)
                                        if not chunk:
                                            break
                                        f.write(chunk)
                            if os.path.exists(part_path) and self.is_valid_pkg_archive(part_path, expected_csize):
                                shutil.move(part_path, local_path)
                                downloaded_results.append((p, local_path))
                                recov_success = True
                                if verbose:
                                    pname = p.get("NAME", "pkg")
                                    sz_mb = os.path.getsize(local_path) / (1024 * 1024)
                                    print(f"  \033[1;32m✓\033[0m Recovered \033[1m{pname}\033[0m [{sz_mb:.1f} MB]")
                                break
                            else:
                                if os.path.exists(part_path):
                                    try:
                                        os.remove(part_path)
                                    except Exception:
                                        pass
                        except Exception:
                            if os.path.exists(part_path):
                                try:
                                    os.remove(part_path)
                                except Exception:
                                    pass
                    if recov_success:
                        break

        # Check for still-missing packages after recovery pass
        final_downloaded_names = {r[0].get("NAME") for r in downloaded_results}
        missing_final = [p for p in needed_pkgs if p.get("NAME") not in final_downloaded_names]

        # Third Pass: Self-Healing 404 Auto-Sync pass
        if missing_final:
            if verbose:
                print(f"  :: \033[1;33m⚡ Self-Healing:\033[0m Re-synchronizing repository index for {len(missing_final)} out-of-date payload(s)...")
            try:
                self.engine.sync_repositories(force=True, verbose=False)
            except Exception as e:
                if verbose:
                    print(f"  :: Warning: Auto-sync failed: {e}")

            for p in missing_final:
                pname = p.get("NAME")
                # Lookup refreshed package data from updated index
                refreshed_pkg = self.engine.index.get(pname)
                if not refreshed_pkg:
                    continue

                candidates = self.engine.get_download_urls_candidates(refreshed_pkg)
                if not candidates:
                    continue

                filename = refreshed_pkg.get("FILENAME") or os.path.basename(candidates[0])
                local_path = os.path.join(self.cache_pkg_dir, filename)
                part_path = local_path + ".part"
                expected_csize = int(refreshed_pkg.get("CSIZE", 0))
                recov_success = False

                for cand_url in candidates:
                    for attempt in range(2):
                        try:
                            if attempt > 0:
                                time.sleep(0.5 * attempt)
                            req = urllib.request.Request(cand_url, headers=headers)
                            with urllib.request.urlopen(req, timeout=45) as resp:
                                first_chunk = resp.read(8192)
                                if not first_chunk or first_chunk.startswith(b"<html") or first_chunk.startswith(b"<!DOCTYPE") or first_chunk.startswith(b"<!doctype") or b"<html" in first_chunk.lower() or b"<head" in first_chunk.lower():
                                    continue
                                if filename.endswith(".zst") and not first_chunk.startswith(b"\x28\xb5\x2f\xfd"):
                                    continue
                                if filename.endswith(".xz") and not first_chunk.startswith(b"\xfd7zXZ\x00"):
                                    continue
                                if filename.endswith(".gz") and not first_chunk.startswith(b"\x1f\x8b"):
                                    continue

                                with open(part_path, "wb") as f:
                                    f.write(first_chunk)
                                    while True:
                                        chunk = resp.read(65536)
                                        if not chunk:
                                            break
                                        f.write(chunk)
                            if os.path.exists(part_path) and self.is_valid_pkg_archive(part_path, expected_csize):
                                shutil.move(part_path, local_path)
                                downloaded_results.append((refreshed_pkg, local_path))
                                recov_success = True
                                if verbose:
                                    sz_mb = os.path.getsize(local_path) / (1024 * 1024)
                                    print(f"  \033[1;32m✓\033[0m Self-healed & downloaded \033[1m{pname}\033[0m ({refreshed_pkg.get('VERSION', '')}) [{sz_mb:.1f} MB]")
                                break
                            else:
                                if os.path.exists(part_path):
                                    try:
                                        os.remove(part_path)
                                    except Exception:
                                        pass
                        except Exception:
                            if os.path.exists(part_path):
                                try:
                                    os.remove(part_path)
                                except Exception:
                                    pass
                    if recov_success:
                        break

        # Final check after all recovery and self-healing passes
        final_downloaded_names = {r[0].get("NAME") for r in downloaded_results}
        missing_final_names = [p.get("NAME") for p in pkgs if p.get("NAME") not in final_downloaded_names]
        if missing_final_names:
            if verbose:
                print(f"\n\033[1;31mThe following packages could not be downloaded:\033[0m {', '.join(missing_final_names)}\n")

        return downloaded_results

    def is_elf_file(self, path: str) -> bool:
        """Check if path is a genuine ELF executable or shared object."""
        if not os.path.isfile(path) or os.path.islink(path):
            return False
        try:
            with open(path, "rb") as f:
                header = f.read(4)
                return header == b"\x7fELF"
        except Exception:
            return False

    def patch_elf_rpaths(self, target_dir: str, verbose: bool = True) -> int:
        """Rewrite RUNPATH and sanitize absolute DT_NEEDED paths on all ELF binaries using patchelf."""
        patched = 0
        has_patchelf = shutil.which("patchelf") is not None
        if not has_patchelf:
            if verbose:
                print("  ⚠️  patchelf binary not found in PATH; skipping RUNPATH relocation.")
            return 0

        rpath_val = "$ORIGIN/../lib:$ORIGIN/lib:$ORIGIN:/opt/underpants/common/lib:/opt/underpants/runtime/lib:/usr/lib64/pulseaudio:/usr/lib/pulseaudio:/usr/lib64/pipewire-0.3:/usr/lib/pipewire-0.3:/usr/lib64/samba"

        for root, _, files in os.walk(target_dir):
            for fname in files:
                fpath = os.path.join(root, fname)
                if self.is_elf_file(fpath):
                    try:
                        # 1. Set RUNPATH
                        subprocess.run(
                            ["patchelf", "--set-rpath", rpath_val, fpath],
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL,
                            check=False
                        )
                        # 2. Sanitize any DT_NEEDED containing absolute paths (e.g. /usr/lib/libtlottie.so -> libtlottie.so)
                        res = subprocess.run(
                            ["patchelf", "--print-needed", fpath],
                            stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL,
                            text=True,
                            check=False
                        )
                        if res.returncode == 0 and res.stdout:
                            for needed in res.stdout.strip().splitlines():
                                needed = needed.strip()
                                if "/" in needed:
                                    bare_lib = os.path.basename(needed)
                                    if bare_lib:
                                        subprocess.run(
                                            ["patchelf", "--replace-needed", needed, bare_lib, fpath],
                                            stdout=subprocess.DEVNULL,
                                            stderr=subprocess.DEVNULL,
                                            check=False
                                        )
                        patched += 1
                    except Exception:
                        pass
        return patched

    @staticmethod
    def _run_makepkg_with_progress(staging_pkg: str, txz_output_path: str, verbose: bool = True) -> bool:
        """Create genuine Slackware .txz package via direct high-speed Slackware tar pipeline."""
        cmd = f"cd '{staging_pkg}' && find ./ | LC_COLLATE=C sort | sed '2,$s,^\\./,,' | tar --no-recursion -T - -cf - | xz -T0 -1 > '{txz_output_path}'"

        p = subprocess.Popen(cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        is_tty = sys.stdout.isatty() and verbose

        if is_tty:
            start_t = time.time()
            anim_chars = ["🩲 · · 🧙", "· 🩲 · 🧙", "· · 🩲 🧙", "· · · 🧙 💰", "· · 🩲 🧙", "· 🩲 · 🧙"]
            idx = 0
            while p.poll() is None:
                elapsed = time.time() - start_t
                m = int(elapsed) // 60
                s = int(elapsed) % 60
                time_str = f"{m:02d}:{s:02d}"
                anim = anim_chars[idx % len(anim_chars)]
                sys.stdout.write(f"\033[2K\r   \033[1;36m🧙 Compressing Slackware package (xz -T0 -1) [{time_str}] {anim}\033[0m")
                sys.stdout.flush()
                idx += 1
                time.sleep(0.1)
            sys.stdout.write("\033[2K\r")
            sys.stdout.flush()

        stdout, stderr = p.communicate()
        if p.returncode != 0 or not os.path.exists(txz_output_path) or os.path.getsize(txz_output_path) == 0:
            if verbose:
                print(f"Error creating Slackware package: {stderr}")
            return False
        return True

    def transmute_batch(self, target_names: List[str], verbose: bool = True, force: bool = False, noconfirm: bool = False) -> Optional[List[Dict[str, Any]]]:
        """Transmute multiple target packages in a unified dependency resolution and download run."""
        self.engine.ensure_loaded()
        clean_targets = [re.split(r"[><=]", t)[0].strip() for t in target_names if t.strip()]
        if not clean_targets:
            return None

        # 1. Check all targets exist
        valid_targets = []
        for t in clean_targets:
            p = self.engine.get_package(t)
            if not p:
                if verbose:
                    print(f"Error: Target package '{t}' not found in synced repositories.")
                return None
            valid_targets.append(p["NAME"])

        # 2. Curated collision check
        for actual_name in valid_targets:
            collision = self.engine.check_curated_collision(actual_name)
            if collision and not force:
                if verbose:
                    print(f"\n\033[1;33m⚠️  Warning: '{actual_name}' is already installed as a curated Slackware package ({collision})!\033[0m")
                if sys.stdin.isatty():
                    try:
                        ans = input(f"   Do you want to override '{actual_name}' with the Underpants Gnomes version? [y/N]: ").strip().lower()
                        if ans not in ("y", "yes", "j", "ja"):
                            return None
                    except (KeyboardInterrupt, EOFError):
                        return None
                else:
                    return None

        if verbose:
            print(f":: Resolving unified dependency plan for {', '.join(valid_targets)}...")
        plan = self.engine.resolve_dependencies(valid_targets)
        to_install = plan["to_install"]
        if not to_install:
            if verbose:
                print("Error: No packages resolved.")
            return None

        if verbose:
            total_dl_bytes = sum(int(p.get("CSIZE", 0)) for p in to_install)
            total_inst_bytes = sum(int(p.get("ISIZE", 0)) for p in to_install)
            dl_mb = total_dl_bytes / (1024 * 1024)
            inst_mb = total_inst_bytes / (1024 * 1024)

            print(f"\n\033[1;36m:: Packages ({len(to_install)}):\033[0m")
            if len(to_install) <= 100:
                cols = 2
                for i in range(0, len(to_install), cols):
                    row_items = []
                    for j in range(cols):
                        if i + j < len(to_install):
                            p = to_install[i + j]
                            p_idx = i + j + 1
                            p_name = p["NAME"]
                            p_ver = p.get("VERSION", "")
                            p_csize = int(p.get("CSIZE", 0)) / (1024 * 1024)
                            label = f"({p_idx:>2d}/{len(to_install)}) {p_name}-{p_ver}"
                            row_items.append(f"  \033[1;36m•\033[0m \033[1m{label:<38}\033[0m \033[1;30m[{p_csize:>5.1f} MB]\033[0m")
                    print("".join(row_items))
            else:
                pkg_labels = [f"{p['NAME']}-{p.get('VERSION', '')}" for p in to_install]
                line_buf = "   "
                for label in pkg_labels:
                    if len(line_buf) + len(label) + 2 > 88:
                        print(line_buf)
                        line_buf = "   " + label + "  "
                    else:
                        line_buf += label + "  "
                if line_buf.strip():
                    print(line_buf)

            print(f"\n  Total Download Size : \033[1;32m{dl_mb:.2f} MB\033[0m")
            print(f"  Total Installed Size: \033[1;32m{inst_mb:.2f} MB\033[0m\n")

            if not noconfirm:
                targets_disp = ", ".join(valid_targets)
                if sys.stdin.isatty():
                    try:
                        ans = input(f":: Proceed with download and installation of {targets_disp}? [Y/n] ").strip().lower()
                        if ans and ans not in ("y", "yes", "j", "ja"):
                            print(f"\n:: Operation cancelled by user. Slackware host sovereignty preserved.\n")
                            return None
                    except (KeyboardInterrupt, EOFError):
                        print("\n:: Operation cancelled by user.\n")
                        return None
                else:
                    try:
                        line = sys.stdin.readline()
                        if line:
                            ans = line.strip().lower()
                            if ans and ans not in ("y", "yes", "j", "ja"):
                                return None
                    except Exception:
                        pass

        # 3. Download all payloads across the entire graph in ONE pass
        downloaded_files = self.download_packages_parallel(to_install, verbose=verbose)
        if len(downloaded_files) < len(to_install):
            if verbose:
                print(f"Error: Only {len(downloaded_files)}/{len(to_install)} packages were downloaded successfully.")
            return None

        # 4. For each target in valid_targets, stage and package it individually
        results = []
        for target in valid_targets:
            res = self.transmute(target, verbose=verbose, force=force, noconfirm=True, pre_downloaded=True)
            if res:
                results.append(res)

        return results if len(results) == len(valid_targets) else None

    def transmute(self, target_name: Any, verbose: bool = True, force: bool = False, is_runtime: bool = False, noconfirm: bool = False, pre_downloaded: bool = False) -> Optional[Any]:
        """Execute full transmutation pipeline into genuine Slackware .txz package."""
        if isinstance(target_name, (list, tuple)):
            if len(target_name) == 1:
                target_name = target_name[0]
            elif len(target_name) > 1:
                return self.transmute_batch(list(target_name), verbose=verbose, force=force, noconfirm=noconfirm)

        self.engine.ensure_loaded()
        clean_target = re.split(r"[><=]", target_name)[0].strip()
        pkg = self.engine.get_package(clean_target)
        if not pkg:
            if verbose:
                print(f"Error: Target package '{target_name}' not found in synced repositories.")
            return None

        actual_name = pkg["NAME"]
        raw_version = pkg.get("VERSION", "1.0")
        clean_version = raw_version.replace(":", "_").replace("-", "_")
        desc = pkg.get("DESC", "Transmuted by Underpants Gnomes for Slackware Linux")

        # Curated Slackware Package Collision Guard (Skip for internal runtime packages)
        if not is_runtime and not pre_downloaded:
            collision = self.engine.check_curated_collision(actual_name)
            if collision and not force:
                if verbose:
                    print(f"\n\033[1;33m⚠️  Warning: '{actual_name}' is already installed as a curated Slackware package ({collision})!\033[0m")
                    print(f"   Transmuting it will place the Underpants Gnomes binary in /usr/bin/{actual_name}.")
                if sys.stdin.isatty():
                    try:
                        ans = input(f"   Do you want to override '{actual_name}' with the Underpants Gnomes version? [y/N]: ").strip().lower()
                        if ans not in ("y", "yes", "j", "ja"):
                            if verbose:
                                print(f"   Aborted transmutation of '{actual_name}'. Native Slackware package preserved.\n")
                            return None
                    except (KeyboardInterrupt, EOFError):
                        return None
                else:
                    if verbose:
                        print(f"   Non-interactive mode without --force: Skipping transmutation of '{actual_name}' to protect native package.\n")
                    return None

        if verbose and not pre_downloaded:
            print(f":: Resolving dependency plan for {actual_name}...")
        plan = self.engine.resolve_dependencies([actual_name])
        to_install = plan["to_install"]

        if not to_install:
            if verbose:
                print(f"Error: No packages resolved for '{actual_name}'.")
            return None

        if verbose and not pre_downloaded:
            total_dl_bytes = sum(int(p.get("CSIZE", 0)) for p in to_install)
            total_inst_bytes = sum(int(p.get("ISIZE", 0)) for p in to_install)
            dl_mb = total_dl_bytes / (1024 * 1024)
            inst_mb = total_inst_bytes / (1024 * 1024)

            print(f"\n\033[1;36m:: Packages ({len(to_install)}):\033[0m")
            if len(to_install) <= 100:
                cols = 2
                for i in range(0, len(to_install), cols):
                    row_items = []
                    for j in range(cols):
                        if i + j < len(to_install):
                            p = to_install[i + j]
                            p_idx = i + j + 1
                            p_name = p["NAME"]
                            p_ver = p.get("VERSION", "")
                            p_csize = int(p.get("CSIZE", 0)) / (1024 * 1024)
                            label = f"({p_idx:>2d}/{len(to_install)}) {p_name}-{p_ver}"
                            row_items.append(f"  \033[1;36m•\033[0m \033[1m{label:<38}\033[0m \033[1;30m[{p_csize:>5.1f} MB]\033[0m")
                    print("".join(row_items))
            else:
                pkg_labels = [f"{p['NAME']}-{p.get('VERSION', '')}" for p in to_install]
                line_buf = "   "
                for label in pkg_labels:
                    if len(line_buf) + len(label) + 2 > 88:
                        print(line_buf)
                        line_buf = "   " + label + "  "
                    else:
                        line_buf += label + "  "
                if line_buf.strip():
                    print(line_buf)

            print(f"\n  Total Download Size : \033[1;32m{dl_mb:.2f} MB\033[0m")
            print(f"  Total Installed Size: \033[1;32m{inst_mb:.2f} MB\033[0m\n")

            if not noconfirm and not is_runtime:
                if sys.stdin.isatty():
                    try:
                        ans = input(f":: Proceed with download and installation of {actual_name}? [Y/n] ").strip().lower()
                        if ans and ans not in ("y", "yes", "j", "ja"):
                            print(f"\n:: Operation cancelled by user. Slackware host sovereignty preserved.\n")
                            return None
                    except (KeyboardInterrupt, EOFError):
                        print("\n:: Operation cancelled by user.\n")
                        return None
                else:
                    try:
                        line = sys.stdin.readline()
                        if line:
                            ans = line.strip().lower()
                            if ans and ans not in ("y", "yes", "j", "ja"):
                                print(f"\n:: Operation cancelled by user. Slackware host sovereignty preserved.\n")
                                return None
                    except Exception:
                        pass

        # Download all required packages in parallel with animated Gnome progress
        if not pre_downloaded:
            downloaded_files = self.download_packages_parallel(to_install, verbose=verbose)
            if len(downloaded_files) < len(to_install):
                if verbose:
                    print(f"Error: Only {len(downloaded_files)}/{len(to_install)} packages were downloaded successfully.")
                return None
        else:
            downloaded_files = []
            for p in to_install:
                candidates = self.engine.get_download_urls_candidates(p)
                fname = p.get("FILENAME") or (os.path.basename(candidates[0]) if candidates else f"{p.get('NAME')}.pkg.tar.zst")
                lpath = os.path.join(self.cache_pkg_dir, fname)
                if os.path.exists(lpath):
                    downloaded_files.append((p, lpath))
                else:
                    found = False
                    for c in candidates:
                        cp = os.path.join(self.cache_pkg_dir, os.path.basename(c))
                        if os.path.exists(cp):
                            downloaded_files.append((p, cp))
                            found = True
                            break
                    if not found:
                        res_dl = self.engine.download_package(p, self.cache_pkg_dir)
                        if res_dl and os.path.exists(res_dl):
                            downloaded_files.append((p, res_dl))

        # Setup staging directory
        staging_base = f"/tmp/transmute-gnomes-{actual_name}-{os.getpid()}"
        staging_pkg = os.path.join(staging_base, "pkg")
        if is_runtime:
            opt_app_dir = os.path.join(staging_pkg, "opt", "underpants", "runtime")
        else:
            opt_app_dir = os.path.join(staging_pkg, "opt", "underpants", "pkgs", actual_name)
        opt_bin_dir = os.path.join(opt_app_dir, "bin")
        opt_lib_dir = os.path.join(opt_app_dir, "lib")
        opt_share_dir = os.path.join(opt_app_dir, "share")
        usr_bin_dir = os.path.join(staging_pkg, "usr", "bin")
        usr_apps_dir = os.path.join(staging_pkg, "usr", "share", "applications")
        usr_icons_dir = os.path.join(staging_pkg, "usr", "share", "icons")
        usr_pixmaps_dir = os.path.join(staging_pkg, "usr", "share", "pixmaps")
        install_dir = os.path.join(staging_pkg, "install")

        try:
            os.makedirs(opt_bin_dir, exist_ok=True)
            os.makedirs(opt_lib_dir, exist_ok=True)
            os.makedirs(opt_share_dir, exist_ok=True)
            os.makedirs(usr_bin_dir, exist_ok=True)
            os.makedirs(usr_apps_dir, exist_ok=True)
            os.makedirs(usr_icons_dir, exist_ok=True)
            os.makedirs(usr_pixmaps_dir, exist_ok=True)
            os.makedirs(install_dir, exist_ok=True)

            if verbose:
                target_desc = f"/opt/underpants/runtime/" if is_runtime else f"/opt/underpants/pkgs/{actual_name}/"
                print(f":: Extracting and staging payloads into {target_desc}...")

            # Track binaries and desktop entries belonging to the primary target package
            primary_binaries: Set[str] = {actual_name}
            primary_desktop_files: Set[str] = set()

            def _merge_tree(src_dir: str, dst_dir: str):
                """Recursively merge src_dir into dst_dir without deleting existing non-conflicting files/subdirectories."""
                if not os.path.isdir(src_dir):
                    return
                os.makedirs(dst_dir, exist_ok=True)
                for root, dirs, files in os.walk(src_dir):
                    rel = os.path.relpath(root, src_dir)
                    target_dir = os.path.join(dst_dir, rel) if rel != "." else dst_dir
                    os.makedirs(target_dir, exist_ok=True)
                    for d in dirs:
                        os.makedirs(os.path.join(target_dir, d), exist_ok=True)
                    for f in files:
                        s_f = os.path.join(root, f)
                        d_f = os.path.join(target_dir, f)
                        if os.path.islink(s_f):
                            target = os.readlink(s_f)
                            if os.path.islink(d_f) or os.path.exists(d_f):
                                try:
                                    os.remove(d_f)
                                except Exception:
                                    pass
                            try:
                                os.symlink(target, d_f)
                            except Exception:
                                pass
                        elif os.path.isfile(s_f):
                            try:
                                shutil.copy2(s_f, d_f)
                            except Exception:
                                pass

            # Extract all archives and recursively merge payloads
            for pdata, fpath in downloaded_files:
                is_primary = (pdata.get("NAME") == actual_name)
                tmp_extract = os.path.join(staging_base, f"extract_{pdata['NAME']}")
                os.makedirs(tmp_extract, exist_ok=True)
                if fpath.endswith(".zst"):
                    subprocess.run(f"zstd -d -c '{fpath}' | tar -xf - -C '{tmp_extract}' 2>/dev/null", shell=True, check=False)
                else:
                    subprocess.run(f"tar -xf '{fpath}' -C '{tmp_extract}' 2>/dev/null", shell=True, check=False)

                # Merge binaries into opt_bin_dir
                for cand_bin in ["usr/bin", "bin", "usr/sbin", "sbin"]:
                    src = os.path.join(tmp_extract, cand_bin)
                    if os.path.isdir(src):
                        for item in os.listdir(src):
                            s = os.path.join(src, item)
                            d = os.path.join(opt_bin_dir, item)
                            if is_primary:
                                primary_binaries.add(item)
                            if os.path.islink(s):
                                target = os.readlink(s)
                                if os.path.islink(d) or os.path.exists(d):
                                    try:
                                        os.remove(d)
                                    except Exception:
                                        pass
                                try:
                                    os.symlink(target, d)
                                except Exception:
                                    pass
                            elif os.path.isfile(s):
                                try:
                                    shutil.copy2(s, d)
                                except Exception:
                                    pass
                            elif os.path.isdir(s):
                                _merge_tree(s, d)

                # Merge libraries into opt_lib_dir
                for cand_lib in ["usr/lib", "usr/lib64", "lib", "lib64"]:
                    src = os.path.join(tmp_extract, cand_lib)
                    if os.path.isdir(src):
                        _merge_tree(src, opt_lib_dir)

                # Merge share into opt_share_dir and record primary desktop entries
                for cand_share in ["usr/share", "share"]:
                    src = os.path.join(tmp_extract, cand_share)
                    if os.path.isdir(src):
                        if is_primary:
                            s_apps = os.path.join(src, "applications")
                            if os.path.isdir(s_apps):
                                for df in os.listdir(s_apps):
                                    if df.endswith(".desktop"):
                                        primary_desktop_files.add(df)
                        _merge_tree(src, opt_share_dir)

                # Merge include into opt_app_dir/include
                for cand_inc in ["usr/include", "include"]:
                    src = os.path.join(tmp_extract, cand_inc)
                    if os.path.isdir(src):
                        _merge_tree(src, os.path.join(opt_app_dir, "include"))

                # Merge configuration into staging_pkg/etc
                src_etc = os.path.join(tmp_extract, "etc")
                if os.path.isdir(src_etc):
                    _merge_tree(src_etc, os.path.join(staging_pkg, "etc"))

            # Copy desktop entries and icons into global package structure (only for non-runtime apps)
            if not is_runtime:
                share_apps = os.path.join(opt_share_dir, "applications")
                if os.path.isdir(share_apps):
                    for df in os.listdir(share_apps):
                        if df.endswith(".desktop"):
                            if primary_desktop_files and df not in primary_desktop_files:
                                continue
                            src_df = os.path.join(share_apps, df)
                            dst_df = os.path.join(usr_apps_dir, df)
                            try:
                                if os.path.islink(src_df):
                                    target = os.readlink(src_df)
                                    if os.path.islink(dst_df) or os.path.exists(dst_df):
                                        os.remove(dst_df)
                                    if os.path.exists(dst_df):
                                        os.remove(dst_df)
                                    os.symlink(target, dst_df)
                                elif os.path.isfile(src_df):
                                    shutil.copy2(src_df, dst_df)
                            except Exception:
                                pass

                # Scan desktop files to register primary application binaries
                if os.path.isdir(usr_apps_dir):
                    for df in os.listdir(usr_apps_dir):
                        df_path = os.path.join(usr_apps_dir, df)
                        if os.path.isfile(df_path):
                            try:
                                with open(df_path, "r", encoding="utf-8", errors="ignore") as f:
                                    for line in f:
                                        if line.startswith("Exec="):
                                            parts = line[5:].strip().split()
                                            if parts:
                                                prog = os.path.basename(parts[0])
                                                if prog:
                                                    primary_binaries.add(prog)
                            except Exception:
                                pass

                share_icons = os.path.join(opt_share_dir, "icons")
                if os.path.isdir(share_icons):
                    for root, _, files in os.walk(share_icons):
                        rel = os.path.relpath(root, share_icons)
                        dest_root = os.path.join(usr_icons_dir, rel)
                        os.makedirs(dest_root, exist_ok=True)
                        for f in files:
                            s_f = os.path.join(root, f)
                            d_f = os.path.join(dest_root, f)
                            try:
                                if os.path.islink(s_f):
                                    target = os.readlink(s_f)
                                    if os.path.islink(d_f) or os.path.exists(d_f):
                                        os.remove(d_f)
                                    os.symlink(target, d_f)
                                elif os.path.isfile(s_f):
                                    shutil.copy2(s_f, d_f)
                            except Exception:
                                pass

                share_pixmaps = os.path.join(opt_share_dir, "pixmaps")
                if os.path.isdir(share_pixmaps):
                    for pm in os.listdir(share_pixmaps):
                        s_pm = os.path.join(share_pixmaps, pm)
                        d_pm = os.path.join(usr_pixmaps_dir, pm)
                        try:
                            if os.path.islink(s_pm):
                                target = os.readlink(s_pm)
                                if os.path.islink(d_pm) or os.path.exists(d_pm):
                                        os.remove(d_pm)
                                os.symlink(target, d_pm)
                            elif os.path.isdir(s_pm):
                                if os.path.exists(d_pm):
                                    shutil.rmtree(d_pm, ignore_errors=True)
                                shutil.copytree(s_pm, d_pm, symlinks=True)
                            elif os.path.isfile(s_pm):
                                shutil.copy2(s_pm, d_pm)
                        except Exception:
                            pass

                # Stage GSettings schemas, metainfo, mime, and app-specific private share directories into usr/share
                if os.path.isdir(opt_share_dir):
                    for s_item in os.listdir(opt_share_dir):
                        s_item_path = os.path.join(opt_share_dir, s_item)
                        if not os.path.isdir(s_item_path):
                            continue
                        if s_item in ("applications", "icons", "pixmaps", "locale", "man", "doc", "info", "gtk-doc", "help", "bash-completion", "zsh", "fish"):
                            continue
                        elif s_item == "glib-2.0":
                            s_schemas = os.path.join(s_item_path, "schemas")
                            if os.path.isdir(s_schemas):
                                _merge_tree(s_schemas, os.path.join(staging_pkg, "usr/share/glib-2.0/schemas"))
                        elif s_item in ("metainfo", "appdata"):
                            _merge_tree(s_item_path, os.path.join(staging_pkg, "usr/share/metainfo"))
                        elif s_item == "mime":
                            s_mime_pkgs = os.path.join(s_item_path, "packages")
                            if os.path.isdir(s_mime_pkgs):
                                _merge_tree(s_mime_pkgs, os.path.join(staging_pkg, "usr/share/mime/packages"))
                        else:
                            # App-specific data assets (e.g. missioncenter, fastfetch, goverlay, mangohud, etc.)
                            _merge_tree(s_item_path, os.path.join(staging_pkg, "usr/share", s_item))

            # Universal text script and configuration path relocation pass
            self._relocate_text_and_symlink_paths(opt_app_dir, actual_name, staging_pkg)

            # Patch ELF RUNPATH
            if verbose:
                print(":: Relocating ELF RUNPATH with patchelf...")
            patched_count = self.patch_elf_rpaths(opt_app_dir, verbose=verbose)
            if verbose:
                print(f"  ✓ Relocated {patched_count} ELF binaries and shared objects.")

            # Remove sandboxed Glycin pixbuf loader and clean loaders.cache
            for root, _, files in os.walk(opt_app_dir):
                for f in files:
                    if f == "libpixbufloader-glycin.so":
                        try:
                            os.remove(os.path.join(root, f))
                        except Exception:
                            pass
                    elif f == "loaders.cache":
                        lpath = os.path.join(root, f)
                        try:
                            with open(lpath, "r", encoding="utf-8", errors="ignore") as lf:
                                llines = lf.readlines()
                            cleaned_lines = []
                            skip_entry = False
                            for line in llines:
                                if "libpixbufloader-glycin" in line:
                                    skip_entry = True
                                    continue
                                if skip_entry:
                                    if line.startswith('"') and "libpixbufloader-" in line:
                                        skip_entry = False
                                    elif line.strip() == "":
                                        skip_entry = False
                                        continue
                                    else:
                                        continue
                                cleaned_lines.append(line.replace("/usr/lib64/", f"{opt_app_dir}/lib/").replace("/usr/lib/", f"{opt_app_dir}/lib/"))
                            with open(lpath, "w", encoding="utf-8") as lf:
                                lf.writelines(cleaned_lines)
                        except Exception:
                            pass

            # Discover primary package candidates to wrap into /usr/bin/ (strictly scoped to primary application targets)
            raw_candidates: Set[str] = set(primary_binaries)
            raw_candidates.add(actual_name)
            raw_candidates.add(actual_name.replace("-", "").replace("_", ""))
            if actual_name.endswith("-bin"):
                raw_candidates.add(actual_name[:-4])
                raw_candidates.add(actual_name[:-4].replace("-", "").replace("_", ""))
            if actual_name.endswith("-appimage"):
                raw_candidates.add(actual_name[:-9])
            if actual_name.endswith("-desktop"):
                raw_candidates.add(actual_name[:-8])
                raw_candidates.add(actual_name[:-8].replace("-", "").replace("_", ""))

            # Filter candidates so only genuine primary application executables are wrapped into /usr/bin
            def _is_clean_app_wrapper(name: str) -> bool:
                if not name or name.startswith(".") or name.startswith("_"):
                    return False
                if any(name.endswith(ext) for ext in [".kiface", ".so", ".a", ".la", ".o", ".pyc", ".pyo", ".h", ".hpp", ".conf", ".ini"]):
                    return False
                low = name.lower()
                for ign in ["xdg-", "wx-", "wxrc", "argon", "pkg-config", "pkgconf", "update-", "libtool", "install-", "make", "bison", "flex", "m4", "gcore", "gdb", "test", "demo", "sample", "example"]:
                    if (low.startswith(ign) or low == ign) and low != actual_name.lower():
                        return False
                return True

            candidates_to_wrap = {c for c in raw_candidates if _is_clean_app_wrapper(c)}

            # Ensure all binaries in opt_bin_dir are executable
            if os.path.isdir(opt_bin_dir):
                for b in os.listdir(opt_bin_dir):
                    try:
                        os.chmod(os.path.join(opt_bin_dir, b), 0o755)
                    except Exception:
                        pass

            # Also generate case aliases (e.g. FreeCAD -> freecad) for primary targets
            all_targets = set()
            for b in list(candidates_to_wrap):
                if b and _is_clean_app_wrapper(b):
                    all_targets.add(b)
                    all_targets.add(b.lower())

            # Create global runner wrapper scripts in /usr/bin/ ONLY for primary application targets
            created_binaries = []
            if not is_runtime:
                for bname in sorted(all_targets):
                    # Never overwrite core host system binaries unless the target package is explicitly that binary
                    if bname in PROTECTED_HOST_BINARIES and bname != actual_name:
                        continue
                    # Skip internal modules, shared plugins, and non-executable extensions
                    if bname.startswith("_") or bname.startswith("."):
                        continue
                    if any(bname.endswith(ext) for ext in [".kiface", ".so", ".a", ".la", ".o", ".pyc", ".pyo", ".h", ".hpp"]):
                        continue
                    # Skip uppercase aliases that weren't in original candidates_to_wrap
                    if bname.isupper() and len(bname) > 3 and bname not in candidates_to_wrap:
                        continue
                    wrapper_path = os.path.join(usr_bin_dir, bname)
                    if not os.path.exists(wrapper_path):
                        wrapper_content = self._generate_launcher_wrapper(bname, actual_name)
                        with open(wrapper_path, "w", encoding="utf-8") as wf:
                            wf.write(wrapper_content)
                        os.chmod(wrapper_path, 0o755)
                        created_binaries.append(bname)


            # Update .desktop files to use global wrapper
            if os.path.isdir(usr_apps_dir):
                for df in os.listdir(usr_apps_dir):
                    df_path = os.path.join(usr_apps_dir, df)
                    if os.path.isfile(df_path):
                        try:
                            with open(df_path, "r", encoding="utf-8", errors="ignore") as f:
                                dlines = f.readlines()
                            newlines = []
                            for l in dlines:
                                if l.startswith("Exec="):
                                    parts = l[5:].strip().split()
                                    if parts:
                                        prog = os.path.basename(parts[0])
                                        rest = " ".join(parts[1:])
                                        newlines.append(f"Exec=/usr/bin/{prog} {rest}\n".rstrip() + "\n")
                                    else:
                                        newlines.append(l)
                                elif l.startswith("TryExec="):
                                    prog = os.path.basename(l[8:].strip())
                                    newlines.append(f"TryExec=/usr/bin/{prog}\n")
                                else:
                                    newlines.append(l)
                            with open(df_path, "w", encoding="utf-8") as f:
                                f.writelines(newlines)
                        except Exception:
                            pass

            # Transmute systemd services into Slackware BSD /etc/rc.d/rc.<service> scripts
            created_services = self._transmute_systemd_services(staging_pkg, opt_app_dir, actual_name) if not is_runtime else []

            # Write install/slack-desc
            slack_desc_path = os.path.join(install_dir, "slack-desc")
            if is_runtime:
                tag = f"underpants-runtime-{actual_name}"
                desc_text = f"Isolated runtime environment ({actual_name})"
                inst_root = "/opt/underpants/runtime/"
            else:
                tag = f"underpants-{actual_name}"
                desc_text = desc[:60]
                inst_root = f"/opt/underpants/pkgs/{actual_name}/"

            desc_lines = [
                f"# HOW TO EDIT THIS FILE:",
                f"# The \"handy ruler\" below makes it easier to edit a package description.",
                f"# Line up the first '|' above the ':' following the base package name, and",
                f"# the '|' on the right side marks the last column you can put a character in.",
                f"# You must make exactly 11 lines for the formatting to be correct.  It's also",
                f"# customary to leave one space after the ':'.",
                f"",
                f"       |-----handy-ruler------------------------------------------------------|",
                f"{tag}: {tag} (v{raw_version})",
                f"{tag}:",
                f"{tag}: Transmuted by Underpants Gnomes Pacman Engine for Slackware Linux.",
                f"{tag}: Upstream package: {actual_name} [{pkg.get('_REPO', 'upstream')}]",
                f"{tag}: {desc_text[:60]}",
                f"{tag}:",
                f"{tag}: Isolated payload staged in {inst_root}",
                f"{tag}: Host Sovereignty Protected: Zero modifications to core system libs.",
                f"{tag}: Run directly via /usr/bin/ or system desktop application menu.",
                f"{tag}:",
                f"{tag}: Underpants Gnomes Factory (slacky-update)",
            ]
            with open(slack_desc_path, "w", encoding="utf-8") as sdf:
                sdf.write("\n".join(desc_lines) + "\n")

            # Write install/doinst.sh
            doinst_path = os.path.join(install_dir, "doinst.sh")
            doinst_content = """if [ -x /sbin/ldconfig ]; then
  /sbin/ldconfig 2>/dev/null || true
fi
if [ -x /usr/bin/update-desktop-database ]; then
  /usr/bin/update-desktop-database /usr/share/applications 2>/dev/null || true
fi
if [ -x /usr/bin/gtk-update-icon-cache ]; then
  /usr/bin/gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
fi
if [ -x /usr/bin/update-mime-database ]; then
  /usr/bin/update-mime-database /usr/share/mime 2>/dev/null || true
fi
if [ -x /usr/bin/glib-compile-schemas ]; then
  /usr/bin/glib-compile-schemas /usr/share/glib-2.0/schemas 2>/dev/null || true
fi
"""
            # Append cleanly-demarcated boot & shutdown hooks for all transmuted services
            for svc in created_services:
                doinst_content += f"""
# --- [ Boot & Shutdown Service Integration: {svc} ] ---
if [ -f /etc/rc.d/rc.local ]; then
  if ! grep -q "# --- [ gnomes-service: {svc} ] ---" /etc/rc.d/rc.local 2>/dev/null; then
    cat << 'EOF_RCLOCAL_{svc}' >> /etc/rc.d/rc.local

# --- [ gnomes-service: {svc} ] ---
if [ -x /etc/rc.d/rc.{svc} ]; then
  /etc/rc.d/rc.{svc} start
fi
# --- [ /gnomes-service: {svc} ] ---
EOF_RCLOCAL_{svc}
  fi
fi

if [ ! -f /etc/rc.d/rc.local_shutdown ]; then
  touch /etc/rc.d/rc.local_shutdown 2>/dev/null || true
  chmod 755 /etc/rc.d/rc.local_shutdown 2>/dev/null || true
fi

if [ -f /etc/rc.d/rc.local_shutdown ]; then
  if ! grep -q "# --- [ gnomes-service: {svc} ] ---" /etc/rc.d/rc.local_shutdown 2>/dev/null; then
    cat << 'EOF_RCSHUTDOWN_{svc}' >> /etc/rc.d/rc.local_shutdown

# --- [ gnomes-service: {svc} ] ---
if [ -x /etc/rc.d/rc.{svc} ]; then
  /etc/rc.d/rc.{svc} stop
fi
# --- [ /gnomes-service: {svc} ] ---
EOF_RCSHUTDOWN_{svc}
  fi
fi
"""
            with open(doinst_path, "w", encoding="utf-8") as dif:
                dif.write(doinst_content)
            os.chmod(doinst_path, 0o755)

            # Write install/douninst.sh for safe service and hook teardown on removepkg
            if created_services:
                douninst_path = os.path.join(install_dir, "douninst.sh")
                douninst_lines = [
                    "#!/bin/sh",
                    "# Underpants Gnomes clean teardown of service hooks and daemons",
                ]
                for svc in created_services:
                    douninst_lines.append(f"if [ -x /etc/rc.d/rc.{svc} ]; then")
                    douninst_lines.append(f"  /etc/rc.d/rc.{svc} stop 2>/dev/null || true")
                    douninst_lines.append(f"fi")
                    douninst_lines.append(f"for f in /etc/rc.d/rc.local /etc/rc.d/rc.local_shutdown; do")
                    douninst_lines.append(f"  if [ -f \"$f\" ]; then")
                    douninst_lines.append(f"    sed -i '/# --- \\[ gnomes-service: {svc} \\] ---/,/# --- \\[ \\/gnomes-service: {svc} \\] ---/d' \"$f\" 2>/dev/null || true")
                    douninst_lines.append(f"  fi")
                    douninst_lines.append(f"done")
                with open(douninst_path, "w", encoding="utf-8") as duf:
                    duf.write("\n".join(douninst_lines) + "\n")
                os.chmod(douninst_path, 0o755)

            # Build Slackware package using makepkg
            if is_runtime:
                txz_filename = f"underpants-runtime-{actual_name}-{clean_version}-x86_64-1_gnomes.txz"
            else:
                txz_filename = f"underpants-{actual_name}-{clean_version}-x86_64-1_gnomes.txz"
            txz_output_path = os.path.join(self.output_dir, txz_filename)

            if verbose:
                print(f":: Building Slackware package {txz_filename} with makepkg...")

            if not self._run_makepkg_with_progress(staging_pkg, txz_output_path, verbose=verbose):
                return None

            pkg_size_mb = os.path.getsize(txz_output_path) / (1024 * 1024)
            if verbose:
                print(f"\n\033[1;32m✓ Successfully transmuted {actual_name} into genuine Slackware package!\033[0m")
                print(f"  Package File    : {txz_output_path} [{pkg_size_mb:.2f} MB]")
                print(f"  Installed Root  : {inst_root}")
                print(f"  Binaries Linked : {', '.join(created_binaries) if created_binaries else ('None (Isolated Runtime)' if is_runtime else 'None')}")
                print(f"  Install Command : \033[1;36mupgradepkg --install-new {txz_output_path}\033[0m\n")

            return {
                "name": actual_name,
                "version": clean_version,
                "txz_path": txz_output_path,
                "size_bytes": os.path.getsize(txz_output_path),
                "binaries": created_binaries,
                "services": created_services
            }
        finally:
            self.safe_rmtree(staging_base)

    def _transmute_systemd_services(self, staging_pkg: str, opt_app_dir: str, actual_name: str) -> List[str]:
        """
        Discovers systemd .service files in the transmuted payload and generates genuine
        Slackware BSD init scripts (/etc/rc.d/rc.<service>) with start/stop/restart/status routines.
        """
        created_services = []
        if not os.path.isdir(opt_app_dir):
            return created_services

        service_files = []
        for root, _, files in os.walk(opt_app_dir):
            if "systemd/system" in root or "systemd/user" in root:
                for f in files:
                    if f.endswith(".service") and "@" not in f:
                        service_files.append(os.path.join(root, f))

        if not service_files:
            return created_services

        rc_dir = os.path.join(staging_pkg, "etc/rc.d")
        os.makedirs(rc_dir, exist_ok=True)

        for s_path in service_files:
            try:
                svc_name = os.path.basename(s_path).replace(".service", "")
                if svc_name.endswith("-wait-online") or svc_name.endswith("-shutdown") or "@" in svc_name:
                    continue

                with open(s_path, "r", encoding="utf-8", errors="ignore") as f:
                    content = f.read()

                service_type = ""
                exec_start = ""
                exec_stop = ""
                user = ""
                group = ""
                env_vars = []
                env_files = []
                pid_file = f"/var/run/{svc_name}.pid"

                for line in content.splitlines():
                    line = line.strip()
                    if not line or line.startswith("#") or line.startswith(";"):
                        continue
                    if line.startswith("Type="):
                        service_type = line[len("Type="):].strip().lower()
                    elif line.startswith("ExecStart="):
                        exec_start = line[len("ExecStart="):].strip()
                    elif line.startswith("ExecStop="):
                        exec_stop = line[len("ExecStop="):].strip()
                    elif line.startswith("User="):
                        user = line[len("User="):].strip()
                    elif line.startswith("Group="):
                        group = line[len("Group="):].strip()
                    elif line.startswith("PIDFile="):
                        pid_file = line[len("PIDFile="):].strip()
                    elif line.startswith("Environment="):
                        env_val = line[len("Environment="):].strip().strip('"').strip("'")
                        env_vars.append(env_val)
                    elif line.startswith("EnvironmentFile="):
                        ef = line[len("EnvironmentFile="):].strip().lstrip("-").strip('"').strip("'")
                        env_files.append(ef)

                if not exec_start or service_type == "oneshot":
                    continue

                if exec_start.startswith("-"):
                    exec_start = exec_start[1:].strip()

                parts = exec_start.split()
                if parts:
                    bin_base = os.path.basename(parts[0])
                    exec_cmd = f"/usr/bin/{bin_base} " + " ".join(parts[1:])
                else:
                    exec_cmd = f"/usr/bin/{svc_name}"

                env_exports = "\n".join([f"export {e}" for e in env_vars])
                if env_exports:
                    env_exports = "\n# Environment variables\n" + env_exports + "\n"

                env_file_loads = [
                    f'if [ -f "/etc/default/{svc_name}" ]; then',
                    f'  . "/etc/default/{svc_name}"',
                    f'elif [ -f "/etc/conf.d/{svc_name}" ]; then',
                    f'  . "/etc/conf.d/{svc_name}"',
                    f'fi'
                ]
                for ef in env_files:
                    env_file_loads.extend([
                        f'if [ -f "{ef}" ]; then',
                        f'  . "{ef}"',
                        f'fi'
                    ])
                env_file_section = "\n".join(env_file_loads)

                rc_script_path = os.path.join(rc_dir, f"rc.{svc_name}")
                rc_script_content = f"""#!/bin/sh
# /etc/rc.d/rc.{svc_name}
# Start/stop/restart {svc_name} daemon (Transmuted for Slackware by Underpants Gnomes)
# PKG_NAME: {actual_name}

# Configuration & Environment
{env_file_section}
{env_exports}
PORT="${{PORT:-41641}}"
FLAGS="${{FLAGS:-}}"
OPTIONS="${{OPTIONS:-}}"

NAME="{svc_name}"
PROG="{exec_cmd.strip()}"
PIDFILE="{pid_file}"
USER="{user}"

{svc_name}_start() {{
  if [ -f "$PIDFILE" ] && kill -0 $(cat "$PIDFILE") 2>/dev/null; then
    echo "$NAME is already running (PID $(cat "$PIDFILE"))."
    return 0
  fi
  mkdir -p "$(dirname "$PIDFILE")" /var/run/{svc_name} /var/lib/{svc_name} 2>/dev/null || true
  [ -z "$PORT" ] && PORT="41641"
  echo "Starting $NAME daemon: $PROG"
  if [ -n "$USER" ] && [ "$USER" != "root" ] && id -u "$USER" >/dev/null 2>&1; then
    su -s /bin/sh "$USER" -c "eval $PROG" >/dev/null 2>&1 &
    echo $! > "$PIDFILE"
  else
    eval "$PROG" >/dev/null 2>&1 &
    echo $! > "$PIDFILE"
  fi
}}

{svc_name}_stop() {{
  echo "Stopping $NAME daemon..."
  if [ -f "$PIDFILE" ]; then
    PID=$(cat "$PIDFILE")
    if kill -0 "$PID" 2>/dev/null; then
      kill -TERM "$PID" 2>/dev/null || true
      sleep 1
      if kill -0 "$PID" 2>/dev/null; then
        kill -9 "$PID" 2>/dev/null || true
      fi
    fi
    rm -f "$PIDFILE"
  else
    killall -TERM "$NAME" 2>/dev/null || true
  fi
}}

{svc_name}_restart() {{
  {svc_name}_stop
  sleep 1
  {svc_name}_start
}}

{svc_name}_status() {{
  if [ -f "$PIDFILE" ] && kill -0 $(cat "$PIDFILE") 2>/dev/null; then
    echo "$NAME is running (PID $(cat "$PIDFILE"))."
  else
    echo "$NAME is stopped."
  fi
}}

case "$1" in
  'start')
    {svc_name}_start
    ;;
  'stop')
    {svc_name}_stop
    ;;
  'restart')
    {svc_name}_restart
    ;;
  'status')
    {svc_name}_status
    ;;
  *)
    echo "Usage: $0 {{start|stop|restart|status}}"
    exit 1
    ;;
esac
"""
                with open(rc_script_path, "w", encoding="utf-8") as rcf:
                    rcf.write(rc_script_content)
                os.chmod(rc_script_path, 0o755)
                created_services.append(svc_name)
            except Exception:
                pass

        return created_services

    def transmute_runtime_profile(self, profile_name: str, verbose: bool = True, force: bool = False, output_dir: Optional[str] = None) -> Optional[Dict[str, Any]]:
        """
        Transmute a curated runtime profile (core, gui, media, engineering, all) or list of packages
        into a unified /opt/underpants/runtime/ shared runtime environment packaged as a genuine Slackware .txz.
        """
        self.engine.ensure_loaded()
        if output_dir:
            self.output_dir = output_dir

        if profile_name in RuntimeManager.PROFILES:
            target_pkgs = RuntimeManager.PROFILES[profile_name]
        else:
            target_pkgs = [p.strip() for p in profile_name.split(",") if p.strip()]

        if not target_pkgs:
            if verbose:
                print(f"Error: Unknown or empty runtime profile '{profile_name}'. Available: {', '.join(RuntimeManager.PROFILES.keys())}")
            return None

        if verbose:
            print(f"\033[1;36m:: Resolving runtime profile '{profile_name}' ({len(target_pkgs)} seed packages)...\033[0m")

        plan = self.engine.resolve_dependencies(target_pkgs, standalone=True)
        to_install = plan["to_install"]
        if not to_install:
            if verbose:
                print(f"Error: Could not resolve any packages for runtime profile '{profile_name}'.")
            return None

        if verbose:
            total_mb = plan["download_size_bytes"] / (1024 * 1024)
            print(f"  📦 Runtime Profile Payload Packages ({len(to_install)} files • {total_mb:.2f} MB):")
            for i, p in enumerate(to_install, 1):
                csize_mb = int(p.get("CSIZE", 0)) / (1024 * 1024)
                print(f"    • ({i:>2d}/{len(to_install)}) [{p.get('_REPO')}] {p.get('NAME')} ({p.get('VERSION')}) [{csize_mb:.2f} MB]")
            print()

        downloaded_files = self.download_packages_parallel(to_install, verbose=verbose)
        if len(downloaded_files) < len(to_install):
            return None

        staging_base = f"/tmp/transmute-gnomes-runtime-{profile_name}-{os.getpid()}"
        staging_pkg = os.path.join(staging_base, "pkg")
        opt_runtime_dir = os.path.join(staging_pkg, "opt", "underpants", "runtime")
        opt_bin_dir = os.path.join(opt_runtime_dir, "bin")
        opt_lib_dir = os.path.join(opt_runtime_dir, "lib")
        opt_share_dir = os.path.join(opt_runtime_dir, "share")
        opt_inc_dir = os.path.join(opt_runtime_dir, "include")
        install_dir = os.path.join(staging_pkg, "install")

        try:
            os.makedirs(opt_bin_dir, exist_ok=True)
            os.makedirs(opt_lib_dir, exist_ok=True)
            os.makedirs(opt_share_dir, exist_ok=True)
            os.makedirs(opt_inc_dir, exist_ok=True)
            os.makedirs(install_dir, exist_ok=True)

            if verbose:
                print(f":: Extracting and staging runtime payloads into /opt/underpants/runtime/...")

            def _merge_tree(src_dir: str, dst_dir: str):
                if not os.path.isdir(src_dir):
                    return
                os.makedirs(dst_dir, exist_ok=True)
                for root, dirs, files in os.walk(src_dir):
                    rel = os.path.relpath(root, src_dir)
                    target_dir = os.path.join(dst_dir, rel) if rel != "." else dst_dir
                    os.makedirs(target_dir, exist_ok=True)
                    for d in dirs:
                        os.makedirs(os.path.join(target_dir, d), exist_ok=True)
                    for f in files:
                        s_f = os.path.join(root, f)
                        d_f = os.path.join(target_dir, f)
                        if os.path.islink(s_f):
                            target = os.readlink(s_f)
                            if os.path.islink(d_f) or os.path.exists(d_f):
                                try:
                                    os.remove(d_f)
                                except Exception:
                                    pass
                            try:
                                os.symlink(target, d_f)
                            except Exception:
                                pass
                        elif os.path.isfile(s_f):
                            try:
                                shutil.copy2(s_f, d_f)
                            except Exception:
                                pass

            for pdata, fpath in downloaded_files:
                tmp_extract = os.path.join(staging_base, f"extract_{pdata['NAME']}")
                os.makedirs(tmp_extract, exist_ok=True)
                if fpath.endswith(".zst"):
                    subprocess.run(f"zstd -d -c '{fpath}' | tar -xf - -C '{tmp_extract}' 2>/dev/null", shell=True, check=False)
                else:
                    subprocess.run(f"tar -xf '{fpath}' -C '{tmp_extract}' 2>/dev/null", shell=True, check=False)

                for cand_bin in ["usr/bin", "bin", "usr/sbin", "sbin"]:
                    src = os.path.join(tmp_extract, cand_bin)
                    if os.path.isdir(src):
                        _merge_tree(src, opt_bin_dir)

                for cand_lib in ["usr/lib", "usr/lib64", "lib", "lib64"]:
                    src = os.path.join(tmp_extract, cand_lib)
                    if os.path.isdir(src):
                        _merge_tree(src, opt_lib_dir)

                for cand_share in ["usr/share", "share"]:
                    src = os.path.join(tmp_extract, cand_share)
                    if os.path.isdir(src):
                        _merge_tree(src, opt_share_dir)

                for cand_inc in ["usr/include", "include"]:
                    src = os.path.join(tmp_extract, cand_inc)
                    if os.path.isdir(src):
                        _merge_tree(src, opt_inc_dir)

                src_etc = os.path.join(tmp_extract, "etc")
                if os.path.isdir(src_etc):
                    _merge_tree(src_etc, os.path.join(staging_pkg, "etc"))

            # Relocate text, symlink, and ELF paths
            self._relocate_text_and_symlink_paths(opt_runtime_dir, f"runtime-{profile_name}", staging_pkg)
            if verbose:
                print(":: Relocating runtime ELF RUNPATH with patchelf...")
            patched_count = self.patch_elf_rpaths(opt_runtime_dir, verbose=verbose)
            if verbose:
                print(f"  ✓ Relocated {patched_count} ELF binaries and shared objects.")

            # Slackware package metadata
            tag = f"underpants-runtime-{profile_name}"
            slack_desc_path = os.path.join(install_dir, "slack-desc")
            desc_lines = [
                f"# HOW TO EDIT THIS FILE:",
                f"# The \"handy ruler\" below makes it easier to edit a package description.",
                f"# Line up the first '|' above the ':' following the base package name, and",
                f"# the '|' on the right side marks the last column you can put a character in.",
                f"# You must make exactly 11 lines for the formatting to be correct.  It's also",
                f"# customary to leave one space after the ':'.",
                f"",
                f"       |-----handy-ruler------------------------------------------------------|",
                f"{tag}: {tag} (v1.0)",
                f"{tag}:",
                f"{tag}: Underpants Gnomes Shared Isolated Runtime Pool ({profile_name})",
                f"{tag}: Curated shared libraries staged into /opt/underpants/runtime/",
                f"{tag}: Eliminates duplicate dependency downloads for all Underpants apps.",
                f"{tag}:",
                f"{tag}: Staged in /opt/underpants/runtime/",
                f"{tag}: Host Sovereignty Protected: Zero modifications to core system libs.",
                f"{tag}: Managed by Underpants Gnomes Engine (slacky-update)",
                f"{tag}:",
                f"{tag}: Underpants Gnomes Factory (slacky-update)",
            ]
            with open(slack_desc_path, "w", encoding="utf-8") as sdf:
                sdf.write("\n".join(desc_lines) + "\n")

            doinst_path = os.path.join(install_dir, "doinst.sh")
            doinst_content = """if [ -x /sbin/ldconfig ]; then
  /sbin/ldconfig 2>/dev/null || true
fi
if [ -x /usr/bin/update-desktop-database ]; then
  /usr/bin/update-desktop-database /usr/share/applications 2>/dev/null || true
fi
if [ -x /usr/bin/glib-compile-schemas ]; then
  /usr/bin/glib-compile-schemas /opt/underpants/runtime/share/glib-2.0/schemas 2>/dev/null || true
fi

# Relocate Glycin loader config files to point to runtime binaries
for _gcf in /opt/underpants/runtime/share/glycin-loaders/2+/conf.d/*.conf /opt/underpants/runtime/share/glycin-loaders/*/conf.d/*.conf; do
  if [ -f "${_gcf}" ]; then
    sed -i 's|Exec=/usr/lib/glycin-loaders/|Exec=/opt/underpants/runtime/lib/glycin-loaders/|g; s|Exec=/usr/lib64/glycin-loaders/|Exec=/opt/underpants/runtime/lib/glycin-loaders/|g' "${_gcf}" 2>/dev/null || true
  fi
done

# Generate GTK3 64-bit runtime immodules cache
if [ -d /opt/underpants/runtime/lib/gtk-3.0/3.0.0/immodules ]; then
  if [ -x /usr/bin/gtk-query-immodules-3.0-64 ]; then
    /usr/bin/gtk-query-immodules-3.0-64 /opt/underpants/runtime/lib/gtk-3.0/3.0.0/immodules/*.so > /opt/underpants/runtime/lib/gtk-3.0/3.0.0/immodules.cache 2>/dev/null || true
  elif [ -x /usr/bin/gtk-query-immodules-3.0 ]; then
    /usr/bin/gtk-query-immodules-3.0 /opt/underpants/runtime/lib/gtk-3.0/3.0.0/immodules/*.so > /opt/underpants/runtime/lib/gtk-3.0/3.0.0/immodules.cache 2>/dev/null || true
  fi
fi

# Generate GdkPixbuf 64-bit runtime loaders cache
if [ -d /opt/underpants/runtime/lib/gdk-pixbuf-2.0/2.10.0/loaders ]; then
  if [ -x /usr/bin/gdk-pixbuf-query-loaders-64 ]; then
    GDK_PIXBUF_MODULEDIR=/opt/underpants/runtime/lib/gdk-pixbuf-2.0/2.10.0/loaders /usr/bin/gdk-pixbuf-query-loaders-64 /opt/underpants/runtime/lib/gdk-pixbuf-2.0/2.10.0/loaders/*.so > /opt/underpants/runtime/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache 2>/dev/null || true
  elif [ -x /usr/bin/gdk-pixbuf-query-loaders ]; then
    GDK_PIXBUF_MODULEDIR=/opt/underpants/runtime/lib/gdk-pixbuf-2.0/2.10.0/loaders /usr/bin/gdk-pixbuf-query-loaders /opt/underpants/runtime/lib/gdk-pixbuf-2.0/2.10.0/loaders/*.so > /opt/underpants/runtime/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache 2>/dev/null || true
  fi
fi

# Update runtime MIME database and icon caches
if [ -x /usr/bin/update-mime-database ] && [ -d /opt/underpants/runtime/share/mime ]; then
  /usr/bin/update-mime-database /opt/underpants/runtime/share/mime 2>/dev/null || true
fi
if [ -x /usr/bin/gtk-update-icon-cache ] && [ -d /opt/underpants/runtime/share/icons/hicolor ]; then
  /usr/bin/gtk-update-icon-cache -f -t /opt/underpants/runtime/share/icons/hicolor 2>/dev/null || true
fi
if [ -x /usr/bin/gtk4-update-icon-cache ] && [ -d /opt/underpants/runtime/share/icons/hicolor ]; then
  /usr/bin/gtk4-update-icon-cache -f -t /opt/underpants/runtime/share/icons/hicolor 2>/dev/null || true
fi
"""
            with open(doinst_path, "w", encoding="utf-8") as dif:
                dif.write(doinst_content)
            os.chmod(doinst_path, 0o755)

            txz_filename = f"underpants-runtime-{profile_name}-1.0-x86_64-1_gnomes.txz"
            txz_output_path = os.path.join(self.output_dir, txz_filename)

            if verbose:
                print(f":: Building Slackware package {txz_filename} with makepkg...")

            if not self._run_makepkg_with_progress(staging_pkg, txz_output_path, verbose=verbose):
                return None

            pkg_size_mb = os.path.getsize(txz_output_path) / (1024 * 1024)
            if verbose:
                print(f"\n\033[1;32m🎉 Bodacious! Successfully transmuted runtime profile '{profile_name}' into Slackware package!\033[0m")
                print(f"  Package File    : {txz_output_path} [{pkg_size_mb:.2f} MB]")
                print(f"  Installed Root  : /opt/underpants/runtime/")
                print(f"  Install Command : \033[1;36mupgradepkg --install-new {txz_output_path}\033[0m\n")

            return {
                "name": f"runtime-{profile_name}",
                "version": "1.0",
                "txz_path": txz_output_path,
                "size_bytes": os.path.getsize(txz_output_path),
                "packages": [p["NAME"] for p in to_install]
            }
        finally:
            shutil.rmtree(staging_base, ignore_errors=True)

    @staticmethod
    def purge_gnomes_service_hooks(svc_name: str) -> None:
        """
        Cleanly purges demarcated gnomes-service blocks from /etc/rc.d/rc.local and
        /etc/rc.d/rc.local_shutdown with zero residual syntax errors.
        """
        for fpath in ("/etc/rc.d/rc.local", "/etc/rc.d/rc.local_shutdown"):
            if os.path.exists(fpath):
                try:
                    with open(fpath, "r", encoding="utf-8", errors="ignore") as fp:
                        content = fp.read()
                    pattern = r'(?m)^[ \t]*# --- \[ gnomes-service: ' + re.escape(svc_name) + r' \] ---[\s\S]*?^[ \t]*# --- \[ /gnomes-service: ' + re.escape(svc_name) + r' \] ---\n?'
                    new_content = re.sub(pattern, "", content)
                    if new_content != content:
                        with open(fpath, "w", encoding="utf-8") as fp:
                            fp.write(new_content)
                except Exception:
                    pass


class RuntimeManager:
    """Manages the isolated Underpants Gnomes runtime (/opt/underpants/runtime/) and shared library pool."""

    RUNTIME_DIR = "/opt/underpants/runtime"
    COMMON_DIR = "/opt/underpants/common"
    PKGS_DIR = "/opt/underpants/pkgs"

    PROFILES: Dict[str, List[str]] = {
        "core": ["python", "glib2", "sqlite", "openssl", "curl", "libxml2", "icu", "fmt", "onetbb"],
        "gui": ["gtk3", "gtk4", "libadwaita", "librsvg", "gdk-pixbuf2", "shared-mime-info", "adwaita-icon-theme", "hicolor-icon-theme", "qt5-base", "qt5-wayland", "qt5-svg", "qt6-base", "qt6-wayland", "qt6-declarative", "qt6-svg", "qt6-webengine", "wxwidgets-gtk3", "libnotify", "webkit2gtk-4.1", "libspnav", "libmanette"],
        "media": ["ffmpeg", "libva", "libvdpau", "pipewire", "alsa-lib", "gstreamer", "gst-plugins-base", "gst-plugins-good", "sdl2", "libsamplerate", "libebur128", "taglib", "wavpack", "chromaprint"],
        "graphics": ["vulkan-icd-loader", "openxr", "embree", "hwloc", "onetbb", "libsquish", "libwslay", "miniupnpc", "glm", "freeglut", "glew", "glfw", "openal"],
        "cad": ["opencascade", "vtk", "ngspice", "verdict", "pugixml", "jsoncpp", "poppler", "mpdecimal", "cblas", "lapack", "openblas"],
        "mobile": ["libimobiledevice", "libimobiledevice-glue", "libplist", "libtatsu", "libusbmuxd", "usbmuxd", "libgpod", "sg3_utils"],
        "desktop": ["hyprland", "xdg-desktop-portal-hyprland", "hyprlock", "hypridle", "hyprpaper", "aquamarine", "hyprlang", "hyprcursor", "hyprgraphics", "hyprutils", "hyprpolkitagent", "ddcui", "wlr-randr", "nwg-displays"],
        "hyprland": ["hyprland", "xdg-desktop-portal-hyprland", "hyprlock", "hypridle", "hyprpaper", "aquamarine", "hyprlang", "hyprcursor", "hyprgraphics", "hyprutils", "hyprpolkitagent", "ddcui", "wlr-randr", "nwg-displays"],
        "noctalia": ["noctalia", "hyprland", "xdg-desktop-portal-hyprland", "hyprlock", "hypridle", "hyprpaper", "aquamarine", "hyprlang", "hyprcursor", "hyprgraphics", "hyprutils", "hyprpolkitagent", "ddcui", "wlr-randr", "nwg-displays"],
        "all": [
            "python", "glib2", "sqlite", "openssl", "curl", "libxml2", "icu", "fmt", "onetbb",
            "gtk3", "gtk4", "libadwaita", "librsvg", "gdk-pixbuf2", "shared-mime-info", "adwaita-icon-theme", "hicolor-icon-theme", "qt5-base", "qt5-wayland", "qt5-svg", "qt6-base", "qt6-wayland", "qt6-declarative", "qt6-svg", "qt6-webengine", "wxwidgets-gtk3", "libnotify", "webkit2gtk-4.1", "libspnav", "libmanette",
            "ffmpeg", "libva", "libvdpau", "pipewire", "alsa-lib", "gstreamer", "gst-plugins-base", "gst-plugins-good", "sdl2", "libsamplerate", "libebur128", "taglib", "wavpack", "chromaprint",
            "vulkan-icd-loader", "openxr", "embree", "hwloc", "libsquish", "libwslay", "miniupnpc", "glm", "freeglut", "glew", "glfw", "openal",
            "opencascade", "vtk", "ngspice", "verdict", "pugixml", "jsoncpp", "poppler", "mpdecimal", "cblas", "lapack", "openblas",
            "libimobiledevice", "libimobiledevice-glue", "libplist", "libtatsu", "libusbmuxd", "usbmuxd", "libgpod", "sg3_utils"
        ]
    }

    def __init__(self, engine: GnomesPacmanEngine):
        self.engine = engine

    @staticmethod
    def get_runtime_libraries() -> Set[str]:
        """Scan /opt/underpants/runtime/lib and /opt/underpants/common/lib for available sonames."""
        libs: Set[str] = set()
        for lib_dir in ("/opt/underpants/runtime/lib", "/opt/underpants/runtime/lib64", "/opt/underpants/common/lib", "/opt/underpants/common/lib64"):
            if os.path.exists(lib_dir):
                for root, _, files in os.walk(lib_dir):
                    for f in files:
                        if ".so" in f:
                            libs.add(f)
        return libs

    def get_status(self) -> Dict[str, Any]:
        """Inspect status of isolated runtime and shared library pools."""
        py_bin = os.path.join(self.RUNTIME_DIR, "bin", "python3")
        is_python_installed = os.path.isfile(py_bin) and os.access(py_bin, os.X_OK)
        py_version_str = "N/A"
        if is_python_installed:
            try:
                res = subprocess.run([py_bin, "--version"], capture_output=True, text=True, timeout=3)
                py_version_str = res.stdout.strip() or res.stderr.strip()
            except Exception:
                py_version_str = "installed"

        installed_profiles = []
        for pfile in sorted(glob.glob("/var/log/packages/underpants-runtime-*")):
            installed_profiles.append(os.path.basename(pfile))

        runtime_libs = self.get_runtime_libraries()

        common_lib_count = 0
        common_lib_dir = os.path.join(self.COMMON_DIR, "lib")
        if os.path.isdir(common_lib_dir):
            common_lib_count = sum(len(files) for _, _, files in os.walk(common_lib_dir))

        installed_apps = []
        if os.path.isdir(self.PKGS_DIR):
            installed_apps = [d for d in sorted(os.listdir(self.PKGS_DIR)) if os.path.isdir(os.path.join(self.PKGS_DIR, d))]

        return {
            "runtime_dir": self.RUNTIME_DIR,
            "common_dir": self.COMMON_DIR,
            "installed_profiles": installed_profiles,
            "python_bin": py_bin if is_python_installed else None,
            "python_version": py_version_str,
            "runtime_libraries_count": len(runtime_libs),
            "common_files_count": common_lib_count,
            "installed_apps": installed_apps,
            "available_profiles": list(self.PROFILES.keys())
        }

    def install_profile(self, profile_name: str = "core", verbose: bool = True, output_dir: str = "/tmp") -> Optional[Dict[str, Any]]:
        """Transmute and generate underpants-runtime-<profile> Slackware package."""
        self.engine.ensure_loaded()
        factory = TransmutationFactory(self.engine, output_dir=output_dir)
        if profile_name == "python":
            return factory.transmute("python", verbose=verbose, force=True, is_runtime=True)
        return factory.transmute_runtime_profile(profile_name, verbose=verbose, output_dir=output_dir)

    def deduplicate_storage(self, verbose: bool = True) -> Dict[str, Any]:
        """
        Scan all installed packages in /opt/underpants/pkgs/ and /opt/underpants/runtime/,
        identify identical files (same size and SHA256 checksum), and hardlink duplicate
        files across directories to reclaim disk space without breaking runtime isolation.
        """
        if verbose:
            print("\033[1;36m:: Underpants Gnomes Storage Deduplication Engine\033[0m")
            print("   Scanning /opt/underpants/ for identical library payloads...\n")

        scan_dirs = []
        if os.path.isdir(self.PKGS_DIR):
            for p in os.listdir(self.PKGS_DIR):
                p_lib = os.path.join(self.PKGS_DIR, p, "lib")
                if os.path.isdir(p_lib):
                    scan_dirs.append(p_lib)
        if os.path.isdir(os.path.join(self.RUNTIME_DIR, "lib")):
            scan_dirs.append(os.path.join(self.RUNTIME_DIR, "lib"))

        if not scan_dirs:
            if verbose:
                print(":: No installed Underpants package library directories found to deduplicate.")
            return {"files_scanned": 0, "duplicates_linked": 0, "bytes_saved": 0, "human_saved": "0 MB"}

        file_hash_map: Dict[Tuple[int, str], str] = {}
        inode_map: Dict[int, str] = {}

        total_scanned = 0
        duplicates_linked = 0
        bytes_saved = 0

        def _sha256(path: str) -> Optional[str]:
            h = hashlib.sha256()
            try:
                with open(path, "rb") as f:
                    while chunk := f.read(65536):
                        h.update(chunk)
                return h.hexdigest()
            except Exception:
                return None

        for sdir in scan_dirs:
            for root, _, files in os.walk(sdir):
                for fname in files:
                    fpath = os.path.join(root, fname)
                    if os.path.islink(fpath):
                        continue
                    try:
                        st = os.stat(fpath)
                    except Exception:
                        continue

                    if not stat.S_ISREG(st.st_mode) or st.st_size == 0:
                        continue

                    total_scanned += 1

                    if st.st_ino in inode_map:
                        continue

                    f_size = st.st_size
                    f_hash = _sha256(fpath)
                    if not f_hash:
                        continue

                    key = (f_size, f_hash)
                    if key in file_hash_map:
                        master_file = file_hash_map[key]
                        tmp_link = fpath + f".dedup_tmp_{os.getpid()}"
                        try:
                            os.link(master_file, tmp_link)
                            os.replace(tmp_link, fpath)
                            duplicates_linked += 1
                            bytes_saved += f_size
                            inode_map[st.st_ino] = master_file
                            if verbose:
                                rel_dup = os.path.relpath(fpath, "/opt/underpants")
                                rel_master = os.path.relpath(master_file, "/opt/underpants")
                                print(f"  \033[1;32m🔗\033[0m Hardlinked \033[1m{rel_dup}\033[0m ➔ \033[1;30m{rel_master}\033[0m [{f_size/(1024*1024):.2f} MB]")
                        except Exception:
                            if os.path.exists(tmp_link):
                                try:
                                    os.remove(tmp_link)
                                except Exception:
                                    pass
                    else:
                        file_hash_map[key] = fpath
                        inode_map[st.st_ino] = fpath

        saved_mb = bytes_saved / (1024 * 1024)
        saved_gb = bytes_saved / (1024 * 1024 * 1024)
        human_str = f"{saved_gb:.2f} GB" if saved_gb >= 1.0 else f"{saved_mb:.2f} MB"

        if verbose:
            print(f"\n:: Deduplication Summary:")
            print(f"  • Files Scanned       : {total_scanned}")
            print(f"  • Duplicates Linked   : {duplicates_linked}")
            print(f"  • Disk Space Reclaimed: \033[1;32m{human_str}\033[0m\n")

        return {
            "files_scanned": total_scanned,
            "duplicates_linked": duplicates_linked,
            "bytes_saved": bytes_saved,
            "human_saved": human_str
        }


# --- [ CLI INTERACTION INTERFACE ] ---

def main():
    """CLI dispatcher for shell integration and testing."""
    if len(sys.argv) < 2:
        print("Underpants Gnomes Pacman Engine v0.17.0 ('I AM THE LAW!')")
        print("Usage: gnomes_pacman.py [sync|search|info|deps|transmute|runtime|url|check-host|list-repos|list-installed] [args...]")
        sys.exit(0)

    cmd = sys.argv[1]
    engine = GnomesPacmanEngine()

    if cmd == "sync":
        force = "--force" in sys.argv or "-f" in sys.argv
        res = engine.sync_repositories(force=force, verbose=True)
        print("\n:: Synchronization Complete:")
        total = 0
        for rname, count in res.items():
            print(f"  • {rname:<20}: {count:>6} packages")
            total += count
        print(f"  -------------------------------------")
        print(f"  Total Indexed       : {total:>6} packages\n")

    elif cmd == "search":
        if len(sys.argv) < 3:
            print("Error: Specify search term.")
            sys.exit(1)
        query = " ".join([a for a in sys.argv[2:] if not a.startswith("--")])
        as_json = "--json" in sys.argv
        results = engine.search(query)
        if as_json:
            print(json.dumps(results, indent=2))
        else:
            print(f":: Search results for '{query}' ({len(results)} matches):\n")
            for p in results:
                repo = p.get("_REPO", "unknown")
                name = p.get("NAME", "")
                ver = p.get("VERSION", "")
                desc = p.get("DESC", "")
                csize = int(p.get("CSIZE", 0)) / (1024 * 1024)
                print(f"  \033[1;32m{repo}/{name}\033[0m \033[1m{ver}\033[0m [{csize:.1f} MB]")
                print(f"    {desc}")
            print("")

    elif cmd == "info":
        if len(sys.argv) < 3:
            print("Error: Specify package name.")
            sys.exit(1)
        pkg_name = sys.argv[2]
        as_json = "--json" in sys.argv
        p = engine.get_package(pkg_name)
        if not p:
            print(f"Error: Package '{pkg_name}' not found in synced repositories.")
            sys.exit(1)
        if as_json:
            print(json.dumps(p, indent=2))
        else:
            print(f":: Package Information: {p.get('NAME')}")
            print(f"  Repository   : {p.get('_REPO')}")
            print(f"  Version      : {p.get('VERSION')}")
            print(f"  Description  : {p.get('DESC')}")
            print(f"  URL          : {p.get('URL', 'N/A')}")
            print(f"  License      : {p.get('LICENSE', 'N/A')}")
            print(f"  Architecture : {p.get('ARCH', 'x86_64')}")
            print(f"  Dependencies : {', '.join(p.get('DEPENDS', [])) or 'None'}")
            print(f"  Optional Deps: {', '.join(p.get('OPTDEPENDS', [])) or 'None'}")
            print(f"  Provides     : {', '.join(p.get('PROVIDES', [])) or 'None'}")
            print(f"  Download URL : {engine.get_download_url(p)}")

    elif cmd == "deps":
        if len(sys.argv) < 3:
            print("Error: Specify package name(s).")
            sys.exit(1)
        targets = [a for a in sys.argv[2:] if not a.startswith("--")]
        as_json = "--json" in sys.argv
        res = engine.resolve_dependencies(targets)
        if as_json:
            print(json.dumps(res, indent=2))
        else:
            print(f":: Dependency Resolution Plan for: {', '.join(targets)}")
            print(f"  Host Glibc Capable  : GLIBC <= {res['host_glibc_supported']}")
            print(f"\n  📦 Packages to Install ({len(res['to_install'])}):")
            for pkg in res["to_install"]:
                csize = int(pkg.get("CSIZE", 0)) / (1024 * 1024)
                print(f"    • [{pkg.get('_REPO')}] {pkg.get('NAME')} ({pkg.get('VERSION')}) [{csize:.2f} MB]")

            if res["host_provided"]:
                print(f"\n  🛡️  Host Base System Shielded ({len(res['host_provided'])}):")
                for k, reason in res["host_provided"].items():
                    print(f"    • {k:<24} => {reason}")

            if res["virtual_satisfied"]:
                print(f"\n  ✨ Virtual Providers Satisfied ({len(res['virtual_satisfied'])}):")
                for k, target in res["virtual_satisfied"].items():
                    print(f"    • {k:<24} => {target}")

            if res["missing"]:
                print(f"\n  ⚠️  Unresolved / Missing ({len(res['missing'])}):")
                for m in res["missing"]:
                    print(f"    • {m}")

            dl_mb = res["download_size_bytes"] / (1024 * 1024)
            inst_mb = res["installed_size_bytes"] / (1024 * 1024)
            print(f"\n  Total Download Size : {dl_mb:.2f} MB")
            print(f"  Total Installed Size: {inst_mb:.2f} MB\n")

    elif cmd == "transmute":
        targets = []
        out_dir = "/tmp"
        as_json = "--json" in sys.argv
        force = "--force" in sys.argv or "-f" in sys.argv
        noconfirm = "--noconfirm" in sys.argv or "-y" in sys.argv or "--yes" in sys.argv
        
        i = 2
        while i < len(sys.argv):
            arg = sys.argv[i]
            if arg == "--output-dir" and i + 1 < len(sys.argv):
                out_dir = sys.argv[i + 1]
                i += 2
            elif arg in ("--json", "--force", "-f", "--noconfirm", "-y", "--yes", "--build-only", "--no-install"):
                i += 1
            elif not arg.startswith("-"):
                targets.append(arg)
                i += 1
            else:
                i += 1

        if not targets:
            print("Error: Specify package name(s) to transmute.")
            sys.exit(1)

        factory = TransmutationFactory(engine, output_dir=out_dir)
        if len(targets) == 1:
            res = factory.transmute(targets[0], verbose=not as_json, force=force, noconfirm=noconfirm)
        else:
            res = factory.transmute(targets, verbose=not as_json, force=force, noconfirm=noconfirm)
        if as_json:
            print(json.dumps(res, indent=2))
        elif not res:
            sys.exit(1)

    elif cmd == "runtime":
        mgr = RuntimeManager(engine)
        sub = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith("-") else "status"
        as_json = "--json" in sys.argv
        if sub in ("status", "info"):
            stat = mgr.get_status()
            if as_json:
                print(json.dumps(stat, indent=2))
            else:
                print(":: Underpants Gnomes Shared Isolated Runtime Pool Status:")
                print(f"  • Runtime Location : {stat['runtime_dir']}")
                print(f"  • Common Pool      : {stat['common_dir']}")
                if stat['python_bin']:
                    print(f"  • Python Binary    : \033[1;32m{stat['python_bin']} ({stat['python_version']})\033[0m")
                else:
                    print(f"  • Python Binary    : \033[1;33mUsing native host Python\033[0m")
                print(f"  • Runtime Sonames  : \033[1;36m{stat['runtime_libraries_count']}\033[0m sonames available in pool")
                print(f"  • Deduplicated Libs: \033[1;36m{stat['common_files_count']}\033[0m shared libraries in common")
                print(f"  • Installed Apps   : {len(stat.get('installed_apps', []))} packages in /opt/underpants/pkgs/")
                if stat['installed_profiles']:
                    print(f"  • Active Profiles  : {', '.join(stat['installed_profiles'])}")
                else:
                    print(f"  • Active Profiles  : None installed (Install with: 'gnomes runtime install <profile>')")
                print(f"  • Available Profiles: {', '.join(stat['available_profiles'])}")
        elif sub in ("profiles", "list-profiles"):
            as_json = "--json" in sys.argv
            if as_json:
                print(json.dumps(RuntimeManager.PROFILES, indent=2))
            else:
                print(":: Available Underpants Gnomes Runtime Profiles:\n")
                for prof, pkgs in RuntimeManager.PROFILES.items():
                    print(f"  • \033[1;36m{prof:<12}\033[0m : {', '.join(pkgs)}")
                print("\nInstall a profile with: gnomes runtime install <profile>")
        elif sub == "install":
            prof_name = "core"
            out_dir = "/tmp"
            for i, a in enumerate(sys.argv[3:], 3):
                if not a.startswith("-") and prof_name == "core":
                    prof_name = a
                elif a == "--output-dir" and i + 1 < len(sys.argv):
                    out_dir = sys.argv[i + 1]
            res = mgr.install_profile(profile_name=prof_name, verbose=not as_json, output_dir=out_dir)
            if as_json:
                print(json.dumps(res, indent=2))
            elif not res:
                sys.exit(1)

    elif cmd in ("deduplicate", "dedup"):
        mgr = RuntimeManager(engine)
        as_json = "--json" in sys.argv
        res = mgr.deduplicate_storage(verbose=not as_json)
        if as_json:
            print(json.dumps(res, indent=2))

    elif cmd in ("clean", "clean-cache"):
        clean_all = "--all" in sys.argv or "-a" in sys.argv or "-Scc" in sys.argv
        as_json = "--json" in sys.argv
        files_rem, bytes_freed = engine.clean_cache(clean_all=clean_all)
        freed_mb = bytes_freed / (1024 * 1024)
        freed_gb = bytes_freed / (1024 * 1024 * 1024)
        human_str = f"{freed_gb:.2f} GB" if freed_gb >= 1.0 else f"{freed_mb:.1f} MB"
        data = {
            "files_removed": files_rem,
            "bytes_freed": bytes_freed,
            "human_freed": human_str,
            "mode": "all" if clean_all else "uninstalled"
        }
        if as_json:
            print(json.dumps(data, indent=2))
        else:
            print(f":: Underpants Gnomes Cache Cleaning ({'ALL Packages' if clean_all else 'Uninstalled Packages'}):")
            print(f"  • Files removed : {files_rem}")
            print(f"  • Space freed   : \033[1;32m{human_str}\033[0m")

    elif cmd == "list-updates":
        as_json = "--json" in sys.argv
        as_count = "--count" in sys.argv
        updates = engine.list_updates()
        if as_count:
            print(len(updates))
        elif as_json:
            print(json.dumps(updates, indent=2))
        else:
            if not updates:
                print(":: All Underpants Gnomes packages are up to date.")
            else:
                print(f":: Underpants Gnomes Package Updates Available ({len(updates)}):\n")
                for u in updates:
                    print(f"  • \033[1;36m{u['name']:<20}\033[0m : {u['installed_version']} -> \033[1;32m{u['upstream_version']}\033[0m [{u['repo']}]")
                print("")

    elif cmd == "check-collision":
        if len(sys.argv) < 3:
            print("NONE")
            sys.exit(0)
        target = sys.argv[2]
        collision = engine.check_curated_collision(target)
        if collision:
            print(collision)
        else:
            print("NONE")

    elif cmd == "url":
        if len(sys.argv) < 3:
            sys.exit(1)
        pkg_name = sys.argv[2]
        p = engine.get_package(pkg_name)
        if p:
            print(engine.get_download_url(p) or "NONE")
        else:
            print("NONE")

    elif cmd == "check-host":
        as_json = "--json" in sys.argv
        libs = sorted(list(HostLibraryScanner.get_host_libraries()))
        glibc = HostLibraryScanner.get_host_glibc_version()
        tier = detect_cpu_tier()
        data = {
            "cpu_tier": tier,
            "glibc_version": f"{glibc[0]}.{glibc[1]}",
            "total_host_libraries": len(libs),
            "sample_libraries": libs[:25]
        }
        if as_json:
            print(json.dumps(data, indent=2))
        else:
            print(":: Host Sovereignty & Hardware Architecture:")
            print(f"  CPU Microarchitecture Tier : {tier.upper()}")
            print(f"  Host Glibc Symbol Support  : GLIBC <= {glibc[0]}.{glibc[1]}")
            print(f"  Host Shared Libraries      : {len(libs)} sonames indexed in host cache")

    elif cmd == "list-installed":
        as_json = "--json" in sys.argv
        installed = engine.list_installed_gnomes_packages()
        if as_json:
            print(json.dumps(installed, indent=2))
        else:
            print(f":: Installed Underpants Gnomes Packages ({len(installed)}):\n")
            for inst in installed:
                print(f"  • {inst['name']:<24} (v{inst['version']}) [{inst['package_id']}]")
            print("")

    elif cmd == "list-repos":
        engine.ensure_loaded()
        print(":: Configured Repositories:")
        for r in engine.repositories:
            rname = r["name"]
            count = len(engine.repo_packages.get(rname, {}))
            print(f"  • {rname:<20} (Priority: {r.get('priority', 0):>3}) : {count} packages")

    elif cmd in ("purge-service", "purge-hooks"):
        if len(sys.argv) < 3:
            print("Error: Specify service name to purge hooks for.")
            sys.exit(1)
        targets = [a for a in sys.argv[2:] if not a.startswith("-")]
        for svc in targets:
            TransmutationFactory.purge_gnomes_service_hooks(svc)
            print(f":: Purged service hooks for '{svc}' from rc.local and rc.local_shutdown.")


if __name__ == "__main__":
    main()
