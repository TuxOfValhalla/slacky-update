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
import tempfile
import stat
import threading
import concurrent.futures
import urllib.request
import urllib.error
import subprocess
import glob
import email.utils
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

# WP-3 (D1, runtime contract): GPU front-ends, audio clients and the TLS trust stack always come from Slackware. A copy in
# the runtime or an app made VA-API, GBM, ALSA, PipeWire and FTPS trust break (wrong driver ABI, 32-bit plugin dirs,
# missing trust store); Slackware ships the same upstream versions. Never resolved from Arch, in every mode.
RUNTIME_HOST_ONLY = {
    "mesa", "libglvnd", "libdrm", "llvm-libs", "vulkan-icd-loader", "libva", "libvdpau", "spirv-tools", "glslang",
    "shaderc", "ocl-icd", "alsa-lib", "libpulse", "pipewire", "libpipewire", "jack2", "pipewire-jack", "p11-kit",
    "gnutls", "ca-certificates-utils", "ca-certificates-mozilla",
}
# File-level guard for anything that still slips in (split names, vendored copies): runtime-relative globs.
RUNTIME_HOST_ONLY_FILES = (
    "lib/libGL.so*", "lib/libEGL.so*", "lib/libGLX*.so*", "lib/libGLdispatch.so*", "lib/libOpenGL.so*", "lib/libGLES*.so*",
    "lib/libgbm.so*", "lib/libdrm*.so*", "lib/libgallium*.so*", "lib/libva.so*", "lib/libva-*.so*", "lib/libvdpau*.so*",
    "lib/libvulkan.so*", "lib/libasound.so*", "lib/libpulse*.so*", "lib/libpipewire-0.3.so*", "lib/libspa-*.so*",
    "lib/libjack*.so*", "lib/libp11-kit.so*", "lib/libgnutls*.so*",
)
# WP-3: the first runtime without GPU/audio/TLS copies (same base name, upgradepkg replaces 1.0)
RUNTIME_PKG_VERSION = "1.1"
RUNTIME_HOST_ONLY_DIRS = (
    "lib/dri", "lib/gbm", "lib/vdpau", "lib/alsa-lib", "lib/spa-0.2", "lib/pipewire-0.3", "lib/pkcs11",
    "share/glvnd", "share/vulkan/icd.d",
)
# Sonames that must then come from the host (64-bit, in ld.so.cache, with every symbol version the runtime asks for)
RUNTIME_HOST_ONLY_SONAME_RE = re.compile(
    r"^lib(GL|EGL|GLX\w*|GLdispatch|OpenGL|GLES\w*|gbm|drm\w*|va|va-\w+|vdpau|vulkan|asound|pulse\w*|pipewire-0\.3|"
    r"jack\w*|p11-kit|gnutls\w*|OpenCL)\.so")

# Virtual Providers: Generic interfaces satisfied by Slackware base or graphics drivers
VIRTUAL_PROVIDES_DEFAULT = {
    # 6A-33: audio plugin packages depend on a virtual "<format>-host"; the app being built (easyeffects, audacity, ...)
    # is that host. Resolving it to the first provider pulled a whole DAW (ardour, 17,500 files) into easyeffects.
    "lv2-host": "app:plugin host (the app itself)",
    "vst-host": "app:plugin host (the app itself)",
    "vst3-host": "app:plugin host (the app itself)",
    "ladspa-host": "app:plugin host (the app itself)",
    "clap-host": "app:plugin host (the app itself)",
    "dssi-host": "app:plugin host (the app itself)",
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
    "f2py", "wheel", "numpy-config", "pybind11-config", "cffi-gen-src",
    "env", "bash", "sh", "zsh", "csh", "tcsh", "fish", "sed", "awk", "gawk", "grep", "egrep", "fgrep",
    "tar", "gzip", "gunzip", "bzip2", "bunzip2", "xz", "unxz", "zstd", "unzstd", "zip", "unzip",
    "find", "xargs", "ls", "cp", "mv", "rm", "mkdir", "rmdir", "chmod", "chown", "cat", "more", "less",
    "make", "gmake", "cmake", "meson", "ninja", "gcc", "g++", "clang", "clang++", "ld", "as", "git",
    "sudo", "su", "login", "passwd", "curl", "wget", "ssh", "scp",
    "systemctl", "init", "shutdown", "reboot", "poweroff", "upgradepkg",
    "installpkg", "removepkg", "slackpkg", "pkgtool", "makepkg", "explodepkg",
    "Xwayland", "xwayland", "Xorg", "X", "startx", "xinit", "xterm", "xauth", "xrdb", "xset", "xrandr",
    "xprop", "xwininfo", "xhost", "setxkbmap", "xmodmap", "xinput",
    "Hyprland", "hyprctl", "hyprpm", "kwin_wayland", "kwin_x11", "sway", "wayfire", "weston", "mutter",
    "startplasma-wayland", "startplasma-x11", "plasma_session", "xfce4-session",
    "dbus-daemon", "dbus-launch", "dbus-send", "dbus-run-session", "elogind", "loginctl", "polkitd", "pkexec",
    "glxinfo", "glxgears", "vulkaninfo", "clinfo", "nvidia-smi", "nvidia-settings", "ldconfig",
    "xdg-open", "xdg-mime", "xdg-email", "xdg-settings", "xdg-desktop-menu", "xdg-desktop-icon",
    "xdg-icon-resource", "xdg-screensaver", "argon2", "fluidsynth", "libfido2", "fido2-assert",
    "fido2-cred", "fido2-token", "cec-client", "wx-config", "wxrc", "qdbus", "qdbusviewer", "qtdiag"
}

# 6A-233: ONE case rule for every audit and write path: Python3, HYPRLAND and xwayland count as protected exactly like
# their canonical spelling (the Rust app does the same in build/protected.rs).
PROTECTED_HOST_LOWER = frozenset(n.lower() for n in PROTECTED_HOST_BINARIES)


def is_protected_host_binary(name: str) -> bool:
    return str(name).lower() in PROTECTED_HOST_LOWER


def localized_sentence(key: str, english: str) -> str:
    """Sentence from locales/<lang>.json through the trust module's loader; English when it is not available."""
    try:
        t = trust_module()
        if t is not None:
            return t.localized(key, english)
    except Exception:
        pass
    return english


def desktop_exec_program_index(parts: List[str]) -> int:
    """6A-11: index of the real program in a .desktop Exec= command, skipping an `env` launcher and
    VAR=value assignments (e.g. `/usr/bin/env GDK_BACKEND=x11 audacity %F` -> index of `audacity`)."""
    i = 0
    if i < len(parts) and os.path.basename(parts[i]) == "env":
        i += 1
        while i < len(parts) and (parts[i].startswith("-") or ("=" in parts[i] and not parts[i].startswith("/"))):
            # options that take a separate argument: -u NAME, -C DIR, -S STRING
            if parts[i] in ("-u", "--unset", "-C", "--chdir", "-S", "--split-string"):
                i += 1
            i += 1
    while i < len(parts) and "=" in parts[i] and not parts[i].startswith("/") and not parts[i].startswith("%"):
        i += 1
    return i if i < len(parts) else -1


# 6A-10: private venv for gnomes Python apps. The app's modules are found through
# APP_ROOT/.venv/pyvenv.cfg (home = runtime python) instead of an exported PYTHONPATH, so programs the
# app starts (games via umu/Proton, other Python versions) never inherit the app's module paths.
RUNTIME_PYTHON = "/opt/underpants/runtime/bin/python3"


_RUNTIME_PY_VERSION_CACHE: Dict[str, Optional[str]] = {}


def runtime_python_version() -> Optional[str]:
    """Full version of the runtime interpreter (e.g. '3.14.7'), or None if it is not available. Cached."""
    if "v" in _RUNTIME_PY_VERSION_CACHE:
        return _RUNTIME_PY_VERSION_CACHE["v"]
    _RUNTIME_PY_VERSION_CACHE["v"] = _runtime_python_version_uncached()
    return _RUNTIME_PY_VERSION_CACHE["v"]


def _runtime_python_version_uncached() -> Optional[str]:
    if not os.path.exists(RUNTIME_PYTHON):
        return None
    try:
        env = {k: v for k, v in os.environ.items() if k not in ("LD_LIBRARY_PATH", "PYTHONPATH", "PYTHONHOME")}
        out = subprocess.run([RUNTIME_PYTHON, "-c", "import sys;print('%d.%d.%d' % sys.version_info[:3])"],
                             capture_output=True, text=True, timeout=20, env=env)
        ver = out.stdout.strip()
        return ver if re.match(r"^\d+\.\d+\.\d+$", ver) else None
    except Exception:
        return None


def venv_site_packages(opt_app_dir: str) -> Optional[str]:
    """6A-10: the app's site-packages dir for the runtime's major.minor, if the app should get a venv."""
    ver = runtime_python_version()
    if not ver:
        return None
    major_minor = ".".join(ver.split(".")[:2])
    sp = os.path.join(opt_app_dir, "lib", f"python{major_minor}", "site-packages")
    return sp if os.path.isdir(sp) else None


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
    # 6A-33: easyeffects 8 needs Linux Studio Plugins for its equalizer, limiter, compressor, delay, ... (optional in Arch)
    "easyeffects": ["lsp-plugins-lv2"],
    "gtk4": ["glycin-loaders"],
}



def secure_cache_modes(base: str) -> None:
    """6A-52: nobody else may write into the gnomes cache (repo DBs carry the package checksums). Dirs: 0755 for the
    system cache, 0700 for a user cache; files in db/ and pkg/: group/other write removed. chmod only, only our own
    files, never chown; errors are ignored (a read-only cache still works)."""
    uid = os.geteuid()
    dir_mode = 0o755 if os.path.abspath(base) == os.path.abspath(DEFAULT_CACHE_BASE) else 0o700
    for d in (base, os.path.join(base, "db"), os.path.join(base, "pkg")):
        try:
            st = os.lstat(d)
        except OSError:
            continue
        if not stat.S_ISDIR(st.st_mode) or st.st_uid != uid:
            continue
        try:
            if stat.S_IMODE(st.st_mode) != dir_mode:
                os.chmod(d, dir_mode)
        except OSError:
            pass
        if d == base:
            continue
        try:
            entries = list(os.scandir(d))
        except OSError:
            continue
        for e in entries:
            try:
                est = e.stat(follow_symlinks=False)
                if stat.S_ISREG(est.st_mode) and est.st_uid == uid and est.st_mode & 0o022:
                    os.chmod(e.path, stat.S_IMODE(est.st_mode) & ~0o022)
            except OSError:
                pass


_SLACK_HOST_PKGS: Optional[Dict[str, str]] = None


def slackware_host_packages() -> Dict[str, str]:
    """6A-151: lower-case name -> version of the installed Slackware packages, our own packages excluded
    (underpants-*/cachyos-* names, _gnomes/_slacky build tags). Read once per run from the package database."""
    global _SLACK_HOST_PKGS
    if _SLACK_HOST_PKGS is None:
        found: Dict[str, str] = {}
        for pkgdb in ("/var/lib/pkgtools/packages", "/var/log/packages"):
            try:
                names = os.listdir(pkgdb)
            except OSError:
                continue
            for entry in names:
                parts = entry.rsplit("-", 3)
                if len(parts) != 4 or "-upgraded-" in entry:
                    continue
                name, ver, _arch, build = parts
                if name.startswith(("underpants-", "cachyos-")) or build.endswith(("_gnomes", "_slacky")):
                    continue
                found[name.lower()] = ver
            break
        _SLACK_HOST_PKGS = found
    return _SLACK_HOST_PKGS


# 6A-151: Arch splits some Slackware packages; only same-project splits with the same version scheme belong here
HOST_PACKAGE_ALIASES = {
    "qemu-system-x86": "qemu",
    "qemu-common": "qemu",
    "qemu-system-x86-firmware": "qemu",
}


def host_package_satisfies(name: str, repo_version: str) -> Optional[str]:
    """6A-151: "name-version" of the installed Slackware package of the same name (or HOST_PACKAGE_ALIASES) when it is
    at least as new as the repo package (epoch and pkgrel ignored), else None. Without the trust module only an exactly equal version counts."""
    pkgs = slackware_host_packages()
    host_name = name.lower() if name.lower() in pkgs else HOST_PACKAGE_ALIASES.get(name.lower(), "")
    host_ver = pkgs.get(host_name)
    if not host_ver:
        return None
    up = str(repo_version or "")
    up = up.split(":", 1)[1] if ":" in up else up
    up = up.rsplit("-", 1)[0] if "-" in up else up
    if not up:
        return None
    trust = trust_module()
    try:
        if trust is not None:
            ok = trust.vercmp(trust.desanitize_slack_version(host_ver), up) >= 0
        else:
            ok = host_ver == up
    except Exception:
        ok = host_ver == up
    return f"{host_name}-{host_ver}" if ok else None


_TRUST_MODULE: Any = False


def trust_module() -> Any:
    """WP-7: lib/gnomes_trust.py, loaded by explicit path from this package's own lib dir (PYTHONSAFEPATH keeps the
    script dir off sys.path). None when it is missing or broken: the old behaviour then stays."""
    global _TRUST_MODULE
    if _TRUST_MODULE is False:
        _TRUST_MODULE = None
        try:
            import importlib.util
            path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gnomes_trust.py")
            spec = importlib.util.spec_from_file_location("gnomes_trust", path)
            if spec and spec.loader:
                mod = importlib.util.module_from_spec(spec)
                sys.modules["gnomes_trust"] = mod
                spec.loader.exec_module(mod)
                _TRUST_MODULE = mod
        except Exception:
            _TRUST_MODULE = None
    return _TRUST_MODULE


_REFRESH_MODULE: Any = False


def refresh_module() -> Any:
    """7J-7N: lib/slacky_runtime_refresh.py (runtime refresh helpers), loaded by explicit path. None when missing or broken."""
    global _REFRESH_MODULE
    if _REFRESH_MODULE is False:
        _REFRESH_MODULE = None
        try:
            import importlib.util
            path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "slacky_runtime_refresh.py")
            spec = importlib.util.spec_from_file_location("slacky_runtime_refresh", path)
            if spec and spec.loader:
                mod = importlib.util.module_from_spec(spec)
                sys.modules["slacky_runtime_refresh"] = mod
                spec.loader.exec_module(mod)
                _REFRESH_MODULE = mod
        except Exception:
            _REFRESH_MODULE = None
    return _REFRESH_MODULE


_SYMVER_MODULE: Any = False


def symver_module() -> Any:
    """6A-327: lib/slacky_symver.py (library symbol-version check), loaded by explicit path. None when missing or broken."""
    global _SYMVER_MODULE
    if _SYMVER_MODULE is False:
        _SYMVER_MODULE = None
        try:
            import importlib.util
            path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "slacky_symver.py")
            spec = importlib.util.spec_from_file_location("slacky_symver", path)
            if spec and spec.loader:
                mod = importlib.util.module_from_spec(spec)
                sys.modules["slacky_symver"] = mod
                spec.loader.exec_module(mod)
                _SYMVER_MODULE = mod
        except Exception:
            _SYMVER_MODULE = None
    return _SYMVER_MODULE


_MIRRORS_MODULE: Any = False


def mirrors_module() -> Any:
    """6A-180: lib/slacky_mirrors.py (ranked mirrors with bounded fall-back), loaded by explicit path like the trust
    module. None when it is missing or broken: the single configured mirror is then used, as before."""
    global _MIRRORS_MODULE
    if _MIRRORS_MODULE is False:
        _MIRRORS_MODULE = None
        try:
            import importlib.util
            path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "slacky_mirrors.py")
            spec = importlib.util.spec_from_file_location("slacky_mirrors", path)
            if spec and spec.loader:
                mod = importlib.util.module_from_spec(spec)
                sys.modules["slacky_mirrors"] = mod
                spec.loader.exec_module(mod)
                _MIRRORS_MODULE = mod
        except Exception:
            _MIRRORS_MODULE = None
    return _MIRRORS_MODULE


_NET_MODULE: Any = False


def net_module() -> Any:
    """6A-244: lib/slacky_net.py (one IPv4 retry when an IPv6 address is unreachable), loaded by explicit path. None when
    it is missing or broken: plain urllib is then used, as before."""
    global _NET_MODULE
    if _NET_MODULE is False:
        _NET_MODULE = None
        try:
            import importlib.util
            path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "slacky_net.py")
            spec = importlib.util.spec_from_file_location("slacky_net", path)
            if spec and spec.loader:
                mod = importlib.util.module_from_spec(spec)
                sys.modules["slacky_net"] = mod
                spec.loader.exec_module(mod)
                _NET_MODULE = mod
        except Exception:
            _NET_MODULE = None
    return _NET_MODULE


def url_open(req: Any, timeout: float) -> Any:
    """urlopen with the 6A-244 IPv4 retry (a host with only IPv6 addresses on a machine without an IPv6 route)."""
    nm = net_module()
    if nm is not None:
        return nm.open_url(req, timeout=timeout)
    return urllib.request.urlopen(req, timeout=timeout)


def trust_log(entries: List[Dict[str, Any]]) -> None:
    """WP-7 log-only rollout: one JSON line per check in <cache>/trust-log.jsonl (kept under about 2 MB). Silent."""
    if not entries:
        return
    base = DEFAULT_CACHE_BASE if os.geteuid() == 0 else USER_CACHE_BASE
    path = os.path.join(base, "trust-log.jsonl")
    try:
        os.makedirs(base, exist_ok=True)
        if os.path.exists(path) and os.path.getsize(path) > 2 * 1024 * 1024:
            os.replace(path, path + ".1")
        stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        with open(path, "a", encoding="utf-8") as fh:
            for e in entries:
                fh.write(json.dumps({"time": stamp, **e}, sort_keys=True) + "\n")
    except OSError:
        pass


def build_dir_base() -> str:
    """D14: build and staging dirs on disk, not on the /tmp tmpfs (a 3-4 GB runtime build can fill it). Root:
    /var/cache/slacky-update/gnomes/build; a user: ~/.cache/slacky-update/gnomes/build. Both 0700."""
    if os.geteuid() == 0:
        base = os.path.join(DEFAULT_CACHE_BASE, "build")
    else:
        base = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "slacky-update", "gnomes", "build")
    os.makedirs(base, mode=0o700, exist_ok=True)
    try:
        if stat.S_IMODE(os.stat(base).st_mode) != 0o700:
            os.chmod(base, 0o700)
    except OSError:
        pass
    return base


def safe_db_filename(name: Any) -> bool:
    """6A-139: True for a plain file name from a repo DB (no path, not empty, not . or ..)."""
    return isinstance(name, str) and bool(name) and name == os.path.basename(name) and \
        name not in (".", "..") and "\x00" not in name and "\\" not in name


class MergeCopyError(Exception):
    """6A-138: a payload file could not be staged; the build stops instead of packaging a half-built tree."""


def _merge_inside(path: str, boundary: str) -> bool:
    real, top = os.path.realpath(path), os.path.realpath(boundary)
    return real == top or real.startswith(top + os.sep)


def _merge_real_dir(d_d: str, boundary: str) -> None:
    """6A-138: make sure d_d is a directory we may write into. A symlinked directory is only followed when it stays
    inside the staging tree (never written through to the host)."""
    if os.path.islink(d_d):
        if os.path.isdir(d_d) and _merge_inside(d_d, boundary):
            return
        raise MergeCopyError(f"Could not stage {d_d}: it is a link that leaves the build tree.")
    try:
        os.makedirs(d_d, exist_ok=True)
    except OSError as e:
        raise MergeCopyError(f"Could not create the folder {d_d}: {e.strerror or e}.")


def _merge_place_link(s_l: str, d_l: str) -> None:
    """6A-138: recreate a symlink as a symlink (files and directories alike). A real directory already in place is kept."""
    try:
        target = os.readlink(s_l)
        if os.path.islink(d_l):
            if os.readlink(d_l) == target:
                return
            os.unlink(d_l)
        elif os.path.isdir(d_l):
            return
        elif os.path.lexists(d_l):
            os.unlink(d_l)
        os.symlink(target, d_l)
    except OSError as e:
        raise MergeCopyError(f"Could not stage the link {d_l}: {e.strerror or e}.")


def _merge_copy_file(s_f: str, d_f: str) -> None:
    """6A-138: copy one regular file; an existing destination link is replaced, never written through."""
    try:
        if os.path.islink(d_f):
            os.unlink(d_f)
        elif os.path.isdir(d_f):
            raise MergeCopyError(f"Could not stage {d_f}: a folder with that name is already there.")
        shutil.copy2(s_f, d_f, follow_symlinks=False)
    except OSError as e:
        raise MergeCopyError(f"Could not stage {d_f}: {e.strerror or e}.")


def merge_tree_safe(src_dir: str, dst_dir: str, boundary: str, note: Optional[Any] = None) -> None:
    """6A-138: merge src_dir into dst_dir. Symlinks (to files or directories) are recreated as links and never
    descended into, destination links are never written through, and any copy error raises MergeCopyError."""
    if os.path.islink(src_dir) or not os.path.isdir(src_dir):
        return
    _merge_real_dir(dst_dir, boundary)
    for root, dirs, files in os.walk(src_dir):
        rel = os.path.relpath(root, src_dir)
        target_dir = os.path.join(dst_dir, rel) if rel != "." else dst_dir
        keep = []
        for d in dirs:
            s_d, d_d = os.path.join(root, d), os.path.join(target_dir, d)
            if os.path.islink(s_d):
                if note:
                    note(d_d, s_d)
                _merge_place_link(s_d, d_d)
            else:
                _merge_real_dir(d_d, boundary)
                keep.append(d)
        dirs[:] = keep
        for f in files:
            s_f, d_f = os.path.join(root, f), os.path.join(target_dir, f)
            if note:
                note(d_f, s_f)
            if os.path.islink(s_f):
                _merge_place_link(s_f, d_f)
            elif os.path.isfile(s_f):
                _merge_copy_file(s_f, d_f)


def space_precheck(installed_bytes: int, build_dir: str, label: str) -> Optional[str]:
    """WP-2: None when there is room, else one plain sentence. The build needs about twice the unpacked size (unpacked
    tree + package being written) and /opt the unpacked size, each with 10 % headroom."""
    if installed_bytes <= 0:
        return None
    # 7K (spec docs/runtime_refresh_spec.md 5.2, F16): the build dir and /opt on ONE filesystem (same major:minor in
    # /proc/self/mountinfo, e.g. two Btrfs subvolumes) share the free space, so both needs are summed there
    rr = refresh_module()
    if rr is not None:
        try:
            res = rr.space_plan(int(installed_bytes), 0, 0, build_dir)
            if not res["ok"]:
                probe = res["path"]
                while not os.path.exists(probe) and probe != "/":
                    probe = os.path.dirname(probe)
                return (f"Not enough free disk space for {label}: {res['need'] / 1e9:.1f} GB needed on {probe}, "
                        f"{res['free'] / 1e9:.1f} GB free. Nothing was changed.")
            return None
        except Exception:
            pass
    for path, need in ((build_dir, 2.2 * installed_bytes), ("/opt", 1.1 * installed_bytes)):
        probe = path
        while not os.path.exists(probe) and probe != "/":
            probe = os.path.dirname(probe)
        try:
            free = shutil.disk_usage(probe).free
        except OSError:
            continue
        if free < need:
            return (f"Not enough free disk space for {label}: {need / 1e9:.1f} GB needed on {probe}, "
                    f"{free / 1e9:.1f} GB free. Nothing was changed.")
    return None


def get_cache_dir() -> str:
    """Resolve writable cache directory for databases and package index."""
    for d in [DEFAULT_CACHE_BASE, USER_CACHE_BASE]:
        try:
            os.makedirs(d, exist_ok=True)
            test_file = os.path.join(d, ".write_test")
            with open(test_file, "w") as f:
                f.write("1")
            os.remove(test_file)
            return d
        except Exception:
            continue
    # 6A-17: no fixed /tmp fallback (predictable path, lost on reboot); a private temp dir instead
    import tempfile
    return tempfile.mkdtemp(prefix="slacky-update-gnomes.")


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
            "url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-znver4/cachyos-znver4.db",
            "base_url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-znver4",
            "priority": 100
        })
        repos.append({
            "name": "cachyos-extra-znver4",
            "url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-extra-znver4/cachyos-extra-znver4.db",
            "base_url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-extra-znver4",
            "priority": 98
        })
        repos.append({
            "name": "cachyos-core-znver4",
            "url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-core-znver4/cachyos-core-znver4.db",
            "base_url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-core-znver4",
            "priority": 96
        })
        repos.append({
            "name": "cachyos-v4",
            "url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-v4/cachyos-v4.db",
            "base_url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-v4",
            "priority": 94
        })
        repos.append({
            "name": "cachyos-extra-v4",
            "url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-extra-v4/cachyos-extra-v4.db",
            "base_url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-extra-v4",
            "priority": 92
        })
        repos.append({
            "name": "cachyos-core-v4",
            "url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-core-v4/cachyos-core-v4.db",
            "base_url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-core-v4",
            "priority": 90
        })
    elif tier == "v4":
        repos.append({
            "name": "cachyos-v4",
            "url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-v4/cachyos-v4.db",
            "base_url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-v4",
            "priority": 100
        })
        repos.append({
            "name": "cachyos-extra-v4",
            "url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-extra-v4/cachyos-extra-v4.db",
            "base_url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-extra-v4",
            "priority": 98
        })
        repos.append({
            "name": "cachyos-core-v4",
            "url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-core-v4/cachyos-core-v4.db",
            "base_url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v4/cachyos-core-v4",
            "priority": 96
        })
    elif tier == "v3":
        repos.append({
            "name": "cachyos-v3",
            "url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v3/cachyos-v3/cachyos-v3.db",
            "base_url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v3/cachyos-v3",
            "priority": 100
        })
        repos.append({
            "name": "cachyos-extra-v3",
            "url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v3/cachyos-extra-v3/cachyos-extra-v3.db",
            "base_url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v3/cachyos-extra-v3",
            "priority": 98
        })
        repos.append({
            "name": "cachyos-core-v3",
            "url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v3/cachyos-core-v3/cachyos-core-v3.db",
            "base_url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64_v3/cachyos-core-v3",
            "priority": 96
        })

    # 2. CachyOS Standard
    repos.append({
        "name": "cachyos",
        "url": f"{DEFAULT_CACHYOS_MIRROR}/x86_64/cachyos/cachyos.db",
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

    _cached_bin_map: Optional[Dict[str, str]] = None

    @classmethod
    def get_host_binary_map(cls) -> Dict[str, str]:
        """Index all host binaries provided by native Slackware packages (/var/log/packages/*)."""
        if cls._cached_bin_map is not None:
            return cls._cached_bin_map

        bin_map: Dict[str, str] = {}
        log_dir = "/var/log/packages"
        if os.path.exists(log_dir):
            try:
                for fname in os.listdir(log_dir):
                    if fname.startswith("underpants-") or fname.startswith("cachyos-gnome-"):
                        continue
                    p_path = os.path.join(log_dir, fname)
                    with open(p_path, "r", encoding="utf-8", errors="ignore") as f:
                        in_flist = False
                        for line in f:
                            sline = line.strip()
                            if sline == "FILE LIST:":
                                in_flist = True
                                continue
                            if in_flist and sline.startswith("usr/bin/"):
                                b_name = sline[8:]
                                if b_name:
                                    bin_map[b_name] = fname
            except Exception:
                pass

        cls._cached_bin_map = bin_map
        return cls._cached_bin_map

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

        # 6A-139: FILENAME is joined into the cache path and the URL; anything but a plain file name is refused
        fn = pkg.get("FILENAME")
        if fn is not None and not safe_db_filename(fn):
            pkg["FILENAME"] = ""
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
        secure_cache_modes(self.cache_dir)
        self.repositories = get_default_repositories()
        self.index: Dict[str, Dict[str, Any]] = {}
        self.provides_index: Dict[str, List[str]] = {}
        self.repo_packages: Dict[str, Dict[str, Dict[str, Any]]] = {}
        self._loaded = False

    def sync_repositories(self, force: bool = False, verbose: bool = True) -> Dict[str, int]:
        """Download and cache all active repository sync databases in parallel with If-Modified-Since."""
        results: Dict[str, int] = {}
        headers_base = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) Slacky-Update/1.0_LTS UnderpantsGnomes"}

        active_repos = [r for r in self.repositories if r["name"] not in BLACKLISTED_REPOS]
        now = time.time()

        def sync_single_repo(repo: Dict[str, Any]) -> Tuple[str, Dict[str, Any]]:
            rname = repo["name"]
            url = repo["url"]
            # 6A-270: CachyOS signs `<repo>.db` (a zstd tar); `<repo>.db.tar.zst` is a separate, unsigned file that was
            # found stale on the mirror. Fetch `.db`, keep the local cache name `<repo>.db.tar.zst` (layout unchanged).
            local_ext = ".db.tar.zst" if (url.endswith(".zst") or url.endswith(".db")) else ".db.tar.gz"
            local_path = os.path.join(self.db_dir, f"{rname}{local_ext}")
            local_meta = local_path + ".meta"

            need_download = force or not os.path.exists(local_path)
            last_modified_hdr: Optional[str] = None
            if not need_download and os.path.exists(local_path):
                mtime = os.path.getmtime(local_path)
                if not force and (now - mtime) < 1800:
                    pass
                else:
                    need_download = True
                    if os.path.exists(local_meta):
                        try:
                            with open(local_meta, "r", encoding="utf-8") as mf:
                                mdata = json.load(mf)
                                last_modified_hdr = mdata.get("last_modified")
                        except Exception:
                            pass
                    if not last_modified_hdr and mtime > 0:
                        last_modified_hdr = email.utils.formatdate(mtime, usegmt=True)

            downloaded = False
            if need_download:
                if verbose:
                    print(f":: Synchronizing database [{rname}] from {url}...")
                req_headers = dict(headers_base)
                if last_modified_hdr and not force:
                    req_headers["If-Modified-Since"] = last_modified_hdr

                # 6A-180: the fastest known mirror of the repo first, the next ones when it fails (bounded). A body that is
                # not a gzip/zstd database counts as a failed mirror. If-Modified-Since and the monotonic check stay as before.
                urls = [url]
                mm = mirrors_module()
                if mm is not None:
                    try:
                        urls = mm.alternatives(url) or [url]
                    except Exception:
                        urls = [url]
                data: Optional[bytes] = None
                resp_last_mod = ""
                not_modified = False
                last_err: Any = None
                data_url = ""
                for cand_url in urls:
                    try:
                        req = urllib.request.Request(cand_url, headers=req_headers)
                        with url_open(req, 10) as resp:
                            body = resp.read()
                            lm = resp.headers.get("Last-Modified") or email.utils.formatdate(now, usegmt=True)
                        if not (body.startswith(b"\x1f\x8b") or body.startswith(b"\x28\xb5\x2f\xfd")):
                            raise ValueError("the server did not send a package database")
                        data, resp_last_mod = body, lm
                        data_url = cand_url
                        if mm is not None:
                            mm.note_success(cand_url)   # 6A-201: mirror health history
                        break
                    except urllib.error.HTTPError as he:
                        if he.code == 304:
                            not_modified = True
                            if mm is not None:
                                mm.note_success(cand_url)
                            break
                        last_err = he
                        if mm is not None and he.code >= 500:
                            mm.note_failure(cand_url)
                    except Exception as e:
                        last_err = e
                        if mm is not None:
                            mm.note_failure(cand_url)
                if data is not None and data_url:
                    # 6A-361 (F2): the downloaded database must pass the signature / parse / monotonic check BEFORE it
                    # replaces the cached one; a blocked database keeps the cached copy (enforce mode only)
                    t = trust_module()
                    if t is not None:
                        try:
                            def _parse_db(b: bytes) -> Dict[str, Dict[str, Any]]:
                                return PacmanDBParser.parse_archive(b, is_zstd=b.startswith(b"\x28\xb5\x2f\xfd"))
                            fam = t.repo_family(rname)
                            chk = t.check_db_before_replace(
                                data, rname, _parse_db, sig=t.fetch_signature(t.sig_url(data_url)),
                                require_sig=(fam == "cachyos"))
                            if not chk.ok:
                                trust_log([dict(chk.as_dict(), check="database", mode=t.trust_mode())])
                            if chk.blocks():
                                last_err = chk.message()
                                data = None
                        except Exception as e:
                            trust_log([{"check": "database", "status": "error", "name": rname, "detail": str(e)[:200]}])
                if not_modified:
                    try:
                        os.utime(local_path, (now, now))
                        if os.path.exists(local_meta):
                            with open(local_meta, "r", encoding="utf-8") as mf:
                                mdata = json.load(mf)
                            mdata["mtime"] = now
                            with open(local_meta, "w", encoding="utf-8") as mf:
                                json.dump(mdata, mf)
                    except Exception:
                        pass
                elif data is not None:
                    try:
                        tmp_path = local_path + f".tmp.{os.getpid()}"
                        with open(tmp_path, "wb") as f:
                            f.write(data)
                        os.replace(tmp_path, local_path)
                        with open(local_meta, "w", encoding="utf-8") as f:
                            json.dump({
                                "url": url,
                                "base_url": repo["base_url"],
                                "mtime": now,
                                "last_modified": resp_last_mod,
                                "size": len(data)
                            }, f)
                        downloaded = True
                    except Exception as e:
                        if verbose:
                            print(f"Warning: Failed to sync [{rname}]: {e}")
                elif verbose:
                    sentence = ""
                    if mm is not None and len(urls) > 1:
                        try:
                            sentence = mm.all_failed_sentence(url)
                        except Exception:
                            sentence = ""
                    print(f"Warning: Failed to sync [{rname}]: {sentence or last_err}")

            pkgs: Dict[str, Any] = {}
            if os.path.exists(local_path):
                if not downloaded and rname in self.repo_packages and self.repo_packages[rname]:
                    pkgs = self.repo_packages[rname]
                else:
                    try:
                        with open(local_path, "rb") as f:
                            raw_data = f.read()
                        is_zstd = local_path.endswith(".zst")
                        pkgs = PacmanDBParser.parse_archive(raw_data, is_zstd=is_zstd)
                    except Exception as e:
                        if verbose:
                            print(f"Warning: Error parsing cached [{rname}]: {e}")
            return (rname, pkgs)

        with concurrent.futures.ThreadPoolExecutor(max_workers=min(len(active_repos), 8)) as executor:
            futures = [executor.submit(sync_single_repo, r) for r in active_repos]
            for fut in concurrent.futures.as_completed(futures):
                try:
                    rname, pkgs = fut.result()
                    if pkgs and not self._db_is_older(rname, pkgs, record=True):
                        self.repo_packages[rname] = pkgs
                        results[rname] = len(pkgs)
                except Exception:
                    pass

        self._build_index()
        return results

    def _db_is_older(self, rname: str, pkgs: Dict[str, Dict[str, Any]], record: bool) -> bool:
        """WP-7 monotonic rule: a repo database older than the last one accepted (a frozen or replayed mirror). Log mode
        only logs it; enforce mode keeps the previous database (True = do not use this one)."""
        trust = trust_module()
        if trust is None:
            return False
        try:
            res = trust.check_db_monotonic(rname, pkgs, trust.default_state_path(), record=record)
        except Exception:
            return False
        mode = trust.trust_mode()
        if res.status != "ok":
            trust_log([dict(res.as_dict(), check="database", mode=mode)])
        if res.status == "older" and mode == "enforce" and rname in self.repo_packages:
            print(f":: {res.message(mode)}")
            return True
        return False

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

    def _is_db_stale(self, max_age_seconds: int = 14400) -> bool:
        """Check if cached database files are older than max_age_seconds."""
        if not self.db_dir or not os.path.isdir(self.db_dir):
            return True
        db_files = [os.path.join(self.db_dir, f) for f in os.listdir(self.db_dir)
                    if (f.endswith(".db.tar.zst") or f.endswith(".db.tar.gz")) and not f.endswith(".meta")]
        if not db_files:
            return True
        now = time.time()
        try:
            oldest = min(os.path.getmtime(fp) for fp in db_files)
            return (now - oldest) > max_age_seconds
        except Exception:
            return True

    def ensure_loaded(self, auto_sync_stale: bool = True, max_age_seconds: int = 14400) -> None:
        """Ensure databases are loaded into memory, syncing if empty or stale."""
        if not self._loaded or not self.index:
            self.load_cached_databases()
            if not self.index or (auto_sync_stale and self._is_db_stale(max_age_seconds)):
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
        # 6A-139: no download for a DB entry whose FILENAME is not a plain file name
        if not filename or not safe_db_filename(filename):
            return []

        candidates: List[str] = []
        if base_url:
            candidates.append(f"{base_url.rstrip('/')}/{filename}")

        # CachyOS repo specific architecture routing
        if "cachyos" in (base_url or "") or repo.startswith("cachyos"):
            # znver4 -> v4 fallback
            if "znver4" in (base_url or ""):
                candidates.append(f"{base_url.replace('-znver4', '-v4').rstrip('/')}/{filename}")
                candidates.append(f"{base_url.replace('/x86_64_v4/', '/x86_64/').replace('-znver4', '').rstrip('/')}/{filename}")
            # v4 -> base x86_64 fallback
            if "v4" in (base_url or "") and "znver4" not in (base_url or ""):
                candidates.append(f"{base_url.replace('/x86_64_v4/', '/x86_64/').replace('-v4', '').rstrip('/')}/{filename}")

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
        return self._with_mirror_hosts(unique_candidates)

    # 6A-244: at most this many payload URLs per package (tier/folder fall-backs and the other ranked hosts together)
    MAX_PAYLOAD_CANDIDATES = 16

    @staticmethod
    def _with_mirror_hosts(candidates: List[str]) -> List[str]:
        """6A-244: the same file on the other ranked hosts of its mirror family (CachyOS, Arch, Chaotic: same path layout,
        only the host part changes), so a host that cannot be reached (for example one with only IPv6 addresses on a
        machine without IPv6) does not stop the download. Order: the first candidate on every ranked host, then the
        existing tier/folder fall-backs as before, then the other hosts for those fall-backs. Bounded. The caller still
        verifies every file (size, SHA256, magic bytes); another host never relaxes a check."""
        mm = mirrors_module()
        if mm is None or not candidates:
            return candidates
        out: List[str] = []
        seen: Set[str] = set()

        def add(u: str) -> None:
            if u and u not in seen and len(out) < GnomesPacmanEngine.MAX_PAYLOAD_CANDIDATES:
                seen.add(u)
                out.append(u)

        def alts(u: str) -> List[str]:
            try:
                return list(mm.alternatives(u) or [u])
            except Exception:
                return [u]

        for u in alts(candidates[0]):
            add(u)
        for u in candidates:
            add(u)
        for u in candidates:
            for a in alts(u):
                add(a)
        return out

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
            # 1.1 WP-3: GPU, audio and TLS-trust libraries always come from Slackware (runtime contract)
            if clean_lower in RUNTIME_HOST_ONLY:
                host_provided[clean_name] = f"host-only (runtime contract) ({clean_name})"
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

            # 6.5 6A-151: an installed Slackware package of the same name, at least as new, provides it (programs and data
            # too, not only .so files: qemu, socat, xdg-utils were bundled again and collided with the base)
            if not standalone and actual_lower not in target_clean_names:
                host_pkg = host_package_satisfies(actual_name, pkg.get("VERSION", ""))
                # never when the host lacks a library soname this package provides (a newer Slackware version with a
                # bumped soname would leave the app without its .so; step 3 bundles those for the same reason)
                so_needed = [p.split("=")[0].strip() for p in pkg.get("PROVIDES", []) if ".so" in p]
                if host_pkg and any(not (so in host_libs or any(h == so or h.startswith(so + ".") or (so.endswith(".so") and h.startswith(so)) for h in host_libs)) for so in so_needed):
                    host_pkg = None
                if host_pkg:
                    host_provided[clean_name] = f"Slackware package ({host_pkg})"
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

    @staticmethod
    def is_quarantined_gnomes_package(name: str) -> bool:
        """Ensure kernels, kernel headers, and dkms modules are never managed by Gnomes."""
        nl = str(name).strip().lower()
        if nl in ("linux", "linux-zen", "linux-lts", "linux-headers", "linux-docs", "linux-api-headers"):
            return True
        if nl.startswith("linux-cachyos") or nl.startswith("linux-headers") or nl.startswith("linux-zen") or nl.startswith("linux-lts"):
            return True
        if nl.endswith("-dkms") or "-dkms-" in nl or nl.startswith("nvidia-open-dkms") or nl.startswith("nvidia-dkms"):
            return True
        return False

    @staticmethod
    def canonical_app_name(name: str) -> str:
        """Strip suffixes like -bin, -git, -appimage, -dkms to group alias packages."""
        n = name.lower().strip()
        for sfx in ["-bin", "-git", "-appimage", "-dkms"]:
            if n.endswith(sfx):
                return n[:-len(sfx)]
        return n

    def list_installed_gnomes_packages(self) -> List[Dict[str, str]]:
        """Inspect /var/log/packages/ for native underpants-* packages."""
        pkgs_by_name: Dict[str, Dict[str, str]] = {}
        log_dir = "/var/log/packages"
        if not os.path.exists(log_dir):
            return []

        try:
            for fname in os.listdir(log_dir):
                if fname.startswith("underpants-") or fname.startswith("cachyos-gnome-"):
                    parts = fname.rsplit("-", 3)
                    if len(parts) == 4:
                        raw_name, ver, arch, build = parts
                        # 6A-59: only packages gnomes built itself (_gnomes) are gnomes-managed; curated _slacky
                        # packages belong to the curated suite and must never be updated/overwritten by gnomes
                        if not build.endswith("_gnomes"):
                            continue
                        app_name = raw_name.replace("underpants-", "").replace("cachyos-gnome-", "")
                        if self.is_quarantined_gnomes_package(app_name):
                            continue
                        canon_name = self.canonical_app_name(app_name)
                        cand = {
                            "package_id": fname,
                            "name": app_name,
                            "canonical_name": canon_name,
                            "version": ver,
                            "arch": arch,
                            "build": build
                        }
                        if canon_name not in pkgs_by_name:
                            pkgs_by_name[canon_name] = cand
                        else:
                            prev = pkgs_by_name[canon_name]
                            if fname.startswith("underpants-") and prev["package_id"].startswith("cachyos-gnome-"):
                                pkgs_by_name[canon_name] = cand
                            elif self.is_newer_version(ver, prev["version"]):
                                pkgs_by_name[canon_name] = cand
                            elif not self.is_newer_version(prev["version"], ver):
                                if app_name.endswith("-bin") and not prev["name"].endswith("-bin"):
                                    pkgs_by_name[canon_name] = cand
        except Exception:
            pass
        return sorted(list(pkgs_by_name.values()), key=lambda x: x["canonical_name"])

    def check_curated_collision(self, pkg_name: str) -> Optional[str]:
        """Check if pkg_name is already installed natively as a curated Slackware package."""
        clean_name = re.split(r"[><=]", pkg_name)[0].strip().lower()
        log_dir = "/var/log/packages"
        if not os.path.exists(log_dir):
            return None

        try:
            for fname in os.listdir(log_dir):
                parts = fname.rsplit("-", 3)
                if len(parts) < 4:
                    continue
                if fname.startswith("underpants-") or fname.startswith("cachyos-gnome-"):
                    # 6A-59: a curated package (any build tag except _gnomes) of the same app counts as a collision
                    app = parts[0].lower()
                    for pre in ("underpants-", "cachyos-gnome-"):
                        if app.startswith(pre):
                            app = app[len(pre):]
                    if app == clean_name and not parts[3].endswith("_gnomes"):
                        return fname
                    continue
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
        installed_list = self.list_installed_gnomes_packages()
        installed_apps = {p["name"].lower() for p in installed_list}
        files_removed = 0
        bytes_freed = 0
        now = time.time()

        def _archive_name_version(fname: str) -> Optional[Tuple[str, str]]:
            """name-pkgver-pkgrel-arch.pkg.tar.<ext> -> (name, "pkgver-pkgrel") (same as Rust cache_clean::split_archive_name)."""
            stem = fname
            for ext in (".zst", ".xz", ".gz"):
                if stem.endswith(ext):
                    stem = stem[:-len(ext)]
                    break
            else:
                return None
            if not stem.endswith(".pkg.tar"):
                return None
            parts = stem[:-len(".pkg.tar")].rsplit("-", 3)
            if len(parts) != 4:
                return None
            return parts[0].lower(), f"{parts[1]}-{parts[2]}"

        def _is_installed_version(name: str, version: str) -> bool:
            # 6A-262: the package database id writes "-" and ":" as "_"; an epoch ("1_2.0_1") is part of the id only
            want = re.sub(r"[-:]", "_", version)
            for ip in installed_list:
                if ip["name"].lower() != name and ip.get("canonical_name", "").lower() != name:
                    continue
                have = ip["version"]
                if have == want:
                    return True
                ep, sep, rest = have.partition("_")
                if sep and ep.isdigit() and rest == want:
                    return True
            return False

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
            # 6A-262: never follow a link: a linked folder is skipped, and only regular files directly in the folder count
            if os.path.islink(cdir) or not os.path.isdir(cdir):
                continue
            try:
                regular: Dict[str, os.stat_result] = {}
                for fname in sorted(os.listdir(cdir)):
                    try:
                        st = os.lstat(os.path.join(cdir, fname))
                    except OSError:
                        continue
                    if stat.S_ISREG(st.st_mode):
                        regular[fname] = st
                gone: Set[str] = set()

                def _remove(fname: str) -> None:
                    nonlocal files_removed, bytes_freed
                    try:
                        os.remove(os.path.join(cdir, fname))
                        files_removed += 1
                        bytes_freed += regular[fname].st_size
                    except OSError:
                        pass

                for fname, st in regular.items():
                    fpath = os.path.join(cdir, fname)
                    if fname.endswith(".sig"):
                        continue
                    if fname.endswith(".part"):
                        # 6A-262: a download may still be running: a fresh .part is kept, even for clean_all
                        if now - st.st_mtime < CLEAN_PART_GRACE:
                            continue
                        _remove(fname)
                        continue
                    if not (fname.endswith(".pkg.tar.zst") or fname.endswith(".pkg.tar.xz")):
                        continue
                    if clean_all or not TransmutationFactory.is_valid_pkg_archive(fpath):
                        should_delete = True
                    else:
                        # 6A-262: only the archive of the INSTALLED name AND version stays (old versions used to stay forever)
                        nv = _archive_name_version(fname)
                        should_delete = not (nv and _is_installed_version(nv[0], nv[1]))
                    if should_delete:
                        gone.add(fname)
                        _remove(fname)
                # WP-7: a cached detached signature goes with its package
                for fname in regular:
                    if fname.endswith(".sig"):
                        arch = fname[:-4]
                        if clean_all or arch in gone or arch not in regular:
                            _remove(fname)
            except Exception:
                pass

        # Also prune generated Slackware .txz packages and temporary build residue in /tmp & /var/cache
        tmp_patterns = [
            "/tmp/underpants-*.txz",
            "/tmp/underpants-*.part",
            # 6A-139: only our own SlackBuild dirs (same patterns as mod_clean.sh), never another build's /tmp/build-*
            "/tmp/build-slacky*",
            "/tmp/package-slacky*",
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
                "/var/cache/slacky-update/archives/*",
                "/var/cache/slacky-update/kernel/*",
                "/var/cache/slacky-update/nvidia/*",
                "/var/cache/slacky-update/rocm/*"
            ])
            # 6A-139: /tmp/SBo and /var/cache/sbopkg belong to sbopkg and are never cleaned here

        # D14: build dirs left behind by an interrupted build (older than 6 hours, so a running build is never touched)
        for bdir in (os.path.join(DEFAULT_CACHE_BASE, "build"), os.path.join(USER_CACHE_BASE, "build")):
            for item in glob.glob(os.path.join(bdir, "*")):
                try:
                    if os.path.isdir(item) and not os.path.islink(item) and time.time() - os.lstat(item).st_mtime > 6 * 3600:
                        sz = sum(os.path.getsize(os.path.join(r, f)) for r, _, fl in os.walk(item) for f in fl if os.path.isfile(os.path.join(r, f)))
                        shutil.rmtree(item, ignore_errors=True)
                        files_removed += 1
                        bytes_freed += sz
                except OSError:
                    pass

        for pat in tmp_patterns:
            for item in glob.glob(pat):
                try:
                    # 6A-139: temp leftovers younger than 6 hours may belong to a running build
                    if (item.startswith("/tmp/") or item.endswith(".tmp")) and \
                            time.time() - os.lstat(item).st_mtime < 6 * 3600:
                        continue
                    if os.path.isfile(item) or os.path.islink(item):
                        sz = os.lstat(item).st_size
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

    @classmethod
    def heal_host_sovereignty(cls, dry_run: bool = False, verbose: bool = True) -> Dict[str, Any]:
        """
        Audit and purge rogue Underpants Gnomes wrappers from /usr/bin/ that conflict with
        native Slackware system packages or protected host utilities.
        6A-154: a wrapper over a file owned by a Slackware package is kept and reported with the
        `slackpkg reinstall` advice (advice only); only wrappers without a stock owner are removed.
        The package records in /var/log/packages are never edited.
        """
        log_dir = "/var/log/packages"
        usr_bin = "/usr/bin"
        if not os.path.exists(usr_bin):
            return {"purged_wrappers": [], "affected_packages": [], "cleaned_logs": 0}

        # 1. Map all host files to their native Slackware packages
        host_pkg_map: Dict[str, str] = {}
        # 6A-137: /usr/bin names listed in our own package records (the owner decides, not the APP_NAME prefix)
        gnomes_owned: Set[str] = set()
        if os.path.exists(log_dir):
            try:
                for fname in os.listdir(log_dir):
                    if fname.startswith("underpants-") or fname.startswith("cachyos-gnome-"):
                        try:
                            with open(os.path.join(log_dir, fname), "r", encoding="utf-8", errors="ignore") as gf:
                                for gl in gf:
                                    gs = gl.strip()
                                    if gs.startswith("usr/bin/") and len(gs) > 8 and "/" not in gs[8:]:
                                        gnomes_owned.add(gs[8:])
                        except OSError:
                            pass
                        continue
                    p_path = os.path.join(log_dir, fname)
                    with open(p_path, "r", encoding="utf-8", errors="ignore") as f:
                        in_flist = False
                        for line in f:
                            sline = line.strip()
                            if sline == "FILE LIST:":
                                in_flist = True
                                continue
                            if in_flist and sline.startswith("usr/bin/"):
                                b_name = sline[8:]
                                if b_name:
                                    host_pkg_map[b_name] = fname
            except Exception:
                pass

        purged_wrappers = []
        affected_pkgs: Set[str] = set()
        heal_errors: List[str] = []
        # 6A-154: stock owners from the Slackware package db (own packages excluded); unreadable db = delete nothing
        kept_stock: List[Tuple[str, str, str, str]] = []
        kept_protected: List[Tuple[str, str, str]] = []     # 6A-232: protected name, no stock owner found: advice only
        stock_owners: Dict[str, str] = {}
        owners_ok = True
        try:
            stock_owners = footprint_load_owners(log_dir)
        except Exception:
            owners_ok = False
            heal_errors.append("The Slackware package database could not be read; no wrapper was removed.")
        # 6A-137: removing a wrapper and scrubbing the package record go together and need root; as a user nothing
        # is changed and the run says so (it used to sudo-remove wrappers while the record scrub failed silently)
        if not dry_run and os.geteuid() != 0:
            dry_run = True
            heal_errors.append("Root is needed to remove rogue wrappers; nothing was changed. Run: sudo gnomes heal")

        # 2. Inspect all files in /usr/bin for rogue wrappers
        try:
            for bname in os.listdir(usr_bin):
                wpath = os.path.join(usr_bin, bname)
                if not os.path.isfile(wpath) or os.path.islink(wpath):
                    continue
                try:
                    with open(wpath, "r", encoding="utf-8", errors="ignore") as wf:
                        header = wf.read(512)
                    if "# --- [ Underpants Gnomes Launcher Wrapper" in header:
                        m = re.search(r'APP_NAME="([^"]+)"', header)
                        app_name = m.group(1) if m else ""
                        canon_app = cls.canonical_app_name(app_name) if app_name else ""
                        b_lower = bname.lower()

                        valid_targets = set()
                        if app_name:
                            valid_targets.add(app_name.lower())
                            valid_targets.add(app_name.lower().replace("-", "").replace("_", ""))
                            if app_name.endswith("-bin"):
                                valid_targets.add(app_name[:-4].lower())
                        if canon_app:
                            valid_targets.add(canon_app.lower())
                            valid_targets.add(canon_app.lower().replace("-", "").replace("_", ""))

                        is_rogue = False
                        by_protected_name = False
                        if is_protected_host_binary(bname):
                            is_rogue = True
                            by_protected_name = True
                        elif bname in host_pkg_map and b_lower not in valid_targets:
                            is_rogue = True
                        # 6A-137: a wrapper listed in its package's own file list is never rogue by name alone
                        elif app_name and bname not in gnomes_owned and not (b_lower in valid_targets or any(b_lower.startswith(t + "-") or b_lower.startswith(t) for t in valid_targets if len(t) >= 4)):
                            is_rogue = True

                        if is_rogue:
                            # 6A-154: a wrapper that shadows a file a Slackware package lists is NEVER deleted (that
                            # would leave the stock file missing); report it and advise `slackpkg reinstall <pkg>`
                            stock_pkg = ""
                            if owners_ok:
                                stock_pkg = stock_owners.get("usr/bin/" + bname, "")
                                if not stock_pkg:
                                    hp = host_pkg_map.get(bname, "")
                                    if hp and not footprint_is_own_package(hp):
                                        stock_pkg = hp
                            if stock_pkg or not owners_ok:
                                stock_pkg = stock_pkg.split(" (")[0]
                                parts = stock_pkg.rsplit("-", 3)
                                pkg_base = parts[0] if len(parts) >= 4 else stock_pkg
                                kept_stock.append((wpath, bname, app_name, pkg_base))
                                continue
                            if by_protected_name:
                                # 6A-232: a protected system name is NEVER deleted on a guess; one sentence, the person decides
                                kept_protected.append((wpath, bname, app_name))
                                continue
                            purged_wrappers.append((wpath, bname, app_name, ""))
                            if not dry_run:
                                try:
                                    os.remove(wpath)
                                except OSError as e:
                                    heal_errors.append(f"Could not remove {wpath}: {e.strerror or e}.")
                except Exception:
                    pass
        except Exception:
            pass

        # 3. 6A-154: the package records in /var/log/packages are never edited here (they belong to pkgtools);
        # "cleaned_logs" stays in the result as 0 for older callers.
        cleaned_logs_count = 0

        if heal_errors and verbose:
            for msg in heal_errors:
                print(f":: {msg}", file=sys.stderr)

        return {
            "purged_wrappers": purged_wrappers,
            "affected_packages": sorted(list(affected_pkgs)),  # 6A-154: always empty now; see kept_stock_owned
            "kept_stock_owned": [{"path": k[0], "name": k[1], "app": k[2], "package": k[3]} for k in kept_stock],
            "kept_protected": [{"path": k[0], "name": k[1], "app": k[2]} for k in kept_protected],
            "cleaned_logs": cleaned_logs_count,
            "errors": heal_errors
        }

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
        # WP-7: pacman's own comparison (epoch, rc/alpha, release) when the trust module is there
        trust = trust_module()
        if trust is not None:
            try:
                return trust.is_newer(trust.desanitize_slack_version(str(upstream_ver)),
                                      trust.desanitize_slack_version(str(installed_ver)))
            except Exception:
                pass
        up_ver, up_rel = cls.parse_pkg_version(upstream_ver)
        inst_ver, inst_rel = cls.parse_pkg_version(installed_ver)

        if up_ver > inst_ver:
            return True
        elif up_ver < inst_ver:
            return False

        if inst_rel and up_rel:
            return up_rel > inst_rel

        return False

    def list_updates(self, allow_sync: bool = True) -> List[Dict[str, Any]]:
        """Check installed Underpants packages against synced repositories for available updates."""
        if allow_sync:
            self.ensure_loaded()
        else:
            # 6A-139: read-only (gnomes -Qu): only the databases already on disk, never a download
            if not self._loaded or not self.index:
                self.load_cached_databases()
            if not self.index:
                return []
        installed = self.list_installed_gnomes_packages()
        updates = []
        held = TransmutationFactory.load_held()
        rb_holds = load_rollback_holds()
        for inst in installed:
            name = inst["name"]
            canon_name = inst.get("canonical_name", name)
            if self.is_quarantined_gnomes_package(name) or self.is_quarantined_gnomes_package(canon_name):
                continue
            cur_ver = inst["version"]
            upstream = self.get_package(name)
            target = name
            if not upstream and canon_name != name:
                # 6A-59: never fall back to a differently named package that a curated package already owns
                # (installed brave-bin must not become underpants-brave = the curated Brave)
                if self.check_curated_collision(canon_name):
                    continue
                upstream = self.get_package(canon_name)
                target = canon_name
            if upstream:
                up_ver = upstream.get("VERSION", "0")
                # P2/L1: a version held for too-new glibc/libstdc++ is not offered again until the host or the package changes
                h = held.get(target) or held.get(name)
                if h and TransmutationFactory.held_is_current(h, up_ver):
                    continue
                # WP-2: the version the user rolled back from is not offered again (a newer one is)
                rb = rb_holds.get(footprint_pkg_base(inst.get("package_id", "")))
                if rb and not self.is_newer_version(up_ver, rb.get("skip_version", "")):
                    continue
                if self.is_newer_version(up_ver, cur_ver):
                    updates.append({
                        # 6A-59: report the package that was actually looked up (was always the canonical name)
                        "name": target,
                        "installed_version": cur_ver,
                        "upstream_version": up_ver,
                        "repo": upstream.get("_REPO", "upstream")
                    })
        return updates



# --- [ TRANSMUTATION FACTORY & PACKAGER ] ---

class TransmutationFactory:
    """Automates extraction, ELF RUNPATH rewriting, launcher wrapper creation, and Slackware .txz packaging."""

    def __init__(self, engine: GnomesPacmanEngine, output_dir: Optional[str] = None):
        self.engine = engine
        # 6A-139: default output in the private 0700 build dir, never a predictable /tmp path
        self.output_dir = output_dir or build_dir_base()
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
                # 6A-139: argv only, no shell (a path can never become a command)
                subprocess.run(["chmod", "-R", "u+w", "--", path], stderr=subprocess.DEVNULL, check=False)
                subprocess.run(["rm", "-rf", "--", path], stderr=subprocess.DEVNULL, check=False)
            except Exception:
                pass

    @staticmethod
    def is_valid_pkg_archive(fpath: str, expected_size: int = 0, expected_sha256: str = "") -> bool:
        """Verify that fpath is a genuine non-corrupted package archive and matches expected SHA256."""
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

            if expected_sha256:
                h = hashlib.sha256()
                with open(fpath, "rb") as f:
                    for chunk in iter(lambda: f.read(131072), b""):
                        h.update(chunk)
                if h.hexdigest().lower() != expected_sha256.lower().strip():
                    return False

            return True
        except Exception:
            return False

    @staticmethod
    def _create_python_venv(opt_app_dir: str, actual_name: str, verbose: bool = True) -> bool:
        """6A-10: APP_ROOT/.venv with pyvenv.cfg (home = runtime) and a .pth for the app's extra module dirs."""
        sp = venv_site_packages(opt_app_dir)
        if not sp:
            return False
        ver = runtime_python_version() or ""
        major_minor = ".".join(ver.split(".")[:2])
        final_root = f"/opt/underpants/pkgs/{actual_name}"
        venv = os.path.join(opt_app_dir, ".venv")
        try:
            os.makedirs(os.path.join(venv, "bin"), exist_ok=True)
            os.makedirs(os.path.join(venv, "lib", f"python{major_minor}"), exist_ok=True)
            with open(os.path.join(venv, "pyvenv.cfg"), "w") as fh:
                fh.write(f"home = {os.path.dirname(RUNTIME_PYTHON)}\n"
                         "include-system-site-packages = true\n"
                         f"version = {ver}\n")
            for name in ("python", "python3", f"python{major_minor}"):
                link = os.path.join(venv, "bin", name)
                if os.path.lexists(link):
                    os.remove(link)
                os.symlink(RUNTIME_PYTHON, link)
            sp_link = os.path.join(venv, "lib", f"python{major_minor}", "site-packages")
            if os.path.lexists(sp_link):
                os.remove(sp_link)
            os.symlink(f"{final_root}/lib/python{major_minor}/site-packages", sp_link)
            # Same extra module dirs the wrapper used to export via PYTHONPATH, minus bundled stdlib copies
            extra: List[str] = []
            for base in ("lib", "share"):
                d = os.path.join(opt_app_dir, base)
                if os.path.isdir(d):
                    for n in sorted(os.listdir(d)):
                        full = os.path.join(d, n)
                        if os.path.isdir(full) and not n.startswith("python") and not n.startswith("."):
                            extra.append(f"{final_root}/{base}/{n}")
            for sub in (f"lib/{actual_name}/lib", f"lib/{actual_name}/Mod"):
                if os.path.isdir(os.path.join(opt_app_dir, sub)):
                    extra.append(f"{final_root}/{sub}")
            if extra:
                with open(os.path.join(sp, "_underpants_app_paths.pth"), "w") as fh:
                    fh.write("\n".join(dict.fromkeys(extra)) + "\n")
            if verbose:
                print(f"  Private Python venv created (runtime {ver}, no exported PYTHONPATH).")
            return True
        except Exception as e:
            if verbose:
                print(f"  ! Could not create the private Python venv: {e}")
            return False

    @staticmethod
    def _relocate_text_and_symlink_paths(opt_app_dir: str, actual_name: str, staging_pkg: str) -> None:
        """
        Universally rewrite hardcoded upstream paths (/usr/lib, /usr/share, prefix=/usr, etc.)
        in staged shell scripts, text configs, python scripts, and symlinks.
        """
        app_prefix = f"/opt/underpants/pkgs/{actual_name}" if not actual_name.startswith("runtime-") else "/opt/underpants/runtime"
        # 6A-9/6A-10: interpreter for rewritten /usr/bin/python3 references, decided once per build
        py_target = None
        if not actual_name.startswith("runtime-") and os.path.exists(RUNTIME_PYTHON):
            py_target = f"{app_prefix}/.venv/bin/python3" if venv_site_packages(opt_app_dir) else RUNTIME_PYTHON
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

                        # 6A-9: Arch scripts expect /usr/bin/python3 to be Python 3.14. On Slackware that path is the
                        # host Python 3.12, which cannot load the 3.14 modules bundled with the app ("SRE module
                        # mismatch"). Point them at the runtime interpreter (3.14). Explicit other versions such as
                        # /usr/bin/python3.12 are left alone; the runtime itself is never rewritten.
                        if py_target:
                            runtime_py = py_target
                            new_content, n_py = re.subn(
                                r'/usr/bin/(?:env\s+)?python(?:3(\.14)?)?(?![\w.\-])',
                                lambda m: runtime_py + (m.group(1) or ""),
                                content,
                            )
                            if n_py > 0:
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
        # 6A-12: the runtime libasound looks for plugins in /usr/lib/alsa-lib (32-bit on Slackware), so ALSA
        # default/pipewire/pulse devices fail. Not for game launchers: their 32-bit children would inherit it.
        if actual_name.lower() in GAME_LAUNCHER_APPS:
            alsa_block = ""
        else:
            alsa_block = (
                "# ALSA plugins (runtime libasound defaults to the 32-bit /usr/lib/alsa-lib on Slackware)\n"
                "if [ -z \"${ALSA_PLUGIN_DIR:-}\" ] && [ -d /usr/lib64/alsa-lib ]; then\n"
                "  export ALSA_PLUGIN_DIR=/usr/lib64/alsa-lib\n"
                "fi\n"
            )
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

# 6A-14: apps with a private Python venv resolve their libraries through the RUNPATH set by patchelf.
# Exporting LD_LIBRARY_PATH would leak the runtime's graphics libs (libGLX, libEGL, libdrm, libXrandr ...)
# into everything the app starts, e.g. the Steam runtime container of a game.
if [ ! -f "${{APP_ROOT}}/.venv/pyvenv.cfg" ]; then
# Dynamic library isolation (Prefer app root, then isolated runtime, then common, then host with private subsystem dirs - 64-bit Multilib clean)
export LD_LIBRARY_PATH="${{APP_ROOT}}/lib:${{APP_ROOT}}/lib64:/opt/underpants/runtime/lib:/opt/underpants/runtime/lib64:/opt/underpants/common/lib:/usr/lib64/libproxy:/usr/lib64/pulseaudio:/usr/lib64/pipewire-0.3:/usr/lib64/samba:${{LD_LIBRARY_PATH:-/usr/lib64}}"

# Deep nested language runtime library search (GHC/Haskell, Lua, app private subdirs)
for _nested_lib in "${{APP_ROOT}}/lib"/ghc-*/lib/* "${{APP_ROOT}}/lib"/ghc-* "${{APP_ROOT}}/lib"/lua/* "${{APP_ROOT}}/lib"/*/ /opt/underpants/runtime/lib/ghc-*/lib/*; do
  if [ -d "${{_nested_lib}}" ]; then
    export LD_LIBRARY_PATH="${{_nested_lib}}:${{LD_LIBRARY_PATH}}"
  fi
done
fi

# XDG data & resources (Preserve host /usr/local/share:/usr/share)
export XDG_DATA_DIRS="${{APP_ROOT}}/share:/opt/underpants/runtime/share:/opt/underpants/common/share:${{XDG_DATA_DIRS:-/usr/local/share:/usr/share}}"

# PipeWire & SPA plugin routing (Ensure audio event loops locate SPA plugins)
export SPA_PLUGIN_DIR="${{APP_ROOT}}/lib/spa-0.2:/opt/underpants/runtime/lib/spa-0.2:/usr/lib64/spa-0.2:${{SPA_PLUGIN_DIR:-/usr/lib64/spa-0.2}}"
export PIPEWIRE_MODULE_DIR="${{APP_ROOT}}/lib/pipewire-0.3:/opt/underpants/runtime/lib/pipewire-0.3:/usr/lib64/pipewire-0.3:${{PIPEWIRE_MODULE_DIR:-/usr/lib64/pipewire-0.3}}"
{alsa_block}
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
# 6A-10: apps with a private venv find their modules via ${{APP_ROOT}}/.venv/pyvenv.cfg; exporting
# PYTHONPATH would leak the app's module dirs into every program it starts (games, other Pythons).
if [ -n "${{_PY_DIRS}}" ] && [ ! -f "${{APP_ROOT}}/.venv/pyvenv.cfg" ]; then
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
  if [ -x "${{APP_ROOT}}/.venv/bin/python3" ]; then
    exec "${{APP_ROOT}}/.venv/bin/python3" "${{TARGET_BIN}}" "$@"
  elif [ -x "${{APP_ROOT}}/bin/python3" ]; then
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
        food = "".join("o" if (j % 2 == 0) else " " for j in range(pos + 1, width))
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

        headers = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) Slacky-Update/1.0_LTS UnderpantsGnomes"}
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
            expected_sha256 = p.get("SHA256SUM", "")
            if os.path.exists(local_path):
                if self.is_valid_pkg_archive(local_path, expected_csize, expected_sha256):
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
                print(f"  All {total_pkgs} package payload(s) ready in local cache.")
            return downloaded_results

        needed_bytes = sum(int(p.get("CSIZE", 15 * 1024 * 1024)) for p in needed_pkgs)
        tot_mb = needed_bytes / (1024 * 1024)
        if verbose:
            print(f"\033[1;36m:: Fetching {len(needed_pkgs)} package payload(s) [{tot_mb:.2f} MB]...\033[0m")
            print("   Step 1: Steal Underpants  ->  Step 2: ? ? ? ?  ->  Step 3: PROFIT!\n")

        num_workers = min(len(needed_pkgs), 10)
        available_slots = list(range(num_workers))
        worker_status: Dict[int, Dict[str, Any]] = {
            i: {
                "active": False,
                "pkg_index": 0,
                "name": "",
                "ver": "",
                "filename": "",
                "cur": 0,
                "total": 0,
                "speed": 0.0,
                "history": [],
                "start_t": 0.0
            }
            for i in range(num_workers)
        }
        pkgs_with_404 = set()
        is_tty = sys.stdout.isatty()
        start_t = time.time()
        bar_width = 28
        term_cols = shutil.get_terminal_size((100, 24)).columns
        name_len = max(20, min(36, term_cols - 58))
        num_dynamic_lines = [0]
        completed_queue: List[Tuple[str, int, float]] = []
        completed_lock = threading.Lock()

        for idx, p in enumerate(pkgs):
            p["_INDEX"] = idx + 1

        def monitor():
            if is_tty:
                sys.stdout.write("\033[?25l")
                sys.stdout.flush()
            while not stop_event.is_set():
                time.sleep(0.12)
                now = time.time()
                chomp_step = int(now / 0.35)

                with completed_lock:
                    new_completed = list(completed_queue)
                    completed_queue.clear()

                with slot_lock:
                    active_slots = [
                        (s_id, dict(s_info))
                        for s_id, s_info in worker_status.items()
                        if s_info.get("active")
                    ]

                with lock:
                    cur_comp = completed_bytes[0]
                    for psize in active_parts.values():
                        cur_comp += psize
                    c_cnt = completed_count[0]

                pct = (cur_comp / total_bytes_expected * 100.0) if total_bytes_expected > 0 else 0.0
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
                    out_buf = []
                    if num_dynamic_lines[0] > 0:
                        out_buf.append(f"\r\033[{num_dynamic_lines[0]}A")

                    # 1. Permanently commit completed lines to terminal
                    for comp_fn, comp_sz, comp_spd in new_completed:
                        comp_disp = comp_fn[:name_len-3] + "..." if len(comp_fn) > name_len else comp_fn
                        comp_sz_str = self._format_size(comp_sz)
                        comp_spd_str = self._format_speed(comp_spd)
                        comp_bar = f"[{'-' * bar_width}] 100%"
                        out_buf.append(f"\r\033[2K{comp_disp:<{name_len}s} {comp_sz_str:>10} {comp_spd_str:>11}  00:00 {comp_bar}\n")

                    # 2. Render active dynamic slots
                    dynamic_lines = []
                    for s_id, s_info in active_slots:
                        fn = s_info.get("filename", "")
                        fn_disp = fn[:name_len-3] + "..." if len(fn) > name_len else fn
                        s_exp = s_info.get("total", 0)
                        s_cur = s_info.get("cur", 0)
                        s_pct = (s_cur / s_exp * 100.0) if s_exp > 0 else 50.0
                        s_spd = s_info.get("speed", 0.0)
                        s_spd_str = self._format_speed(s_spd)
                        s_rem = max(0, s_exp - s_cur)
                        if s_spd > 1024 and s_rem > 0:
                            s_eta_sec = int(s_rem / s_spd)
                            s_eta = f"{s_eta_sec // 60:02d}:{s_eta_sec % 60:02d}"
                        else:
                            s_eta = "00:00" if s_pct >= 99.0 else "--:--"

                        s_sz_str = self._format_size(s_cur if s_cur > s_exp else s_exp)
                        s_bar = self.render_gnome_bar(s_pct, width=bar_width, chomp_state=chomp_step + s_id)
                        dynamic_lines.append(f"{fn_disp:<{name_len}s} {s_sz_str:>10} {s_spd_str:>11} {s_eta:>5} {s_bar}")

                    # 3. Render Total line
                    tot_bar = self.render_gnome_bar(pct, width=bar_width, chomp_state=chomp_step)
                    tot_label = f"Total ({c_cnt}/{total_pkgs})"
                    dynamic_lines.append(f"{tot_label:<{name_len}s} {tot_size_str:>10} {spd_str_tot:>11} {eta_str:>5} {tot_bar}")

                    for d_line in dynamic_lines:
                        out_buf.append(f"\r\033[2K{d_line}\n")

                    out_buf.append("\033[J")
                    sys.stdout.write("".join(out_buf))
                    sys.stdout.flush()
                    num_dynamic_lines[0] = len(dynamic_lines)
                else:
                    tot_label = f"Total ({c_cnt}/{total_pkgs})"
                    tot_bar = self.render_gnome_bar(pct, width=bar_width, chomp_state=chomp_step)
                    line = f"\r{tot_label} {tot_size_str} {spd_str_tot} {eta_str} {tot_bar} "
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
            expected_sha256 = pkg_data.get("SHA256SUM", "")
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
                        "filename": filename,
                        "cur": 0,
                        "total": expected_csize,
                        "speed": 0.0,
                        "history": [(time.time(), 0)],
                        "start_t": time.time()
                    }

            with lock:
                active_parts[part_path] = 0

            download_success = False
            got_404_all = True

            for cand_url in candidates:
                for attempt in range(2):
                    try:
                        if attempt > 0:
                            time.sleep(0.2 * attempt)
                        req = urllib.request.Request(cand_url, headers=headers)
                        with url_open(req, 25) as resp:
                            first_chunk = resp.read(8192)
                            if not first_chunk or first_chunk.startswith(b"<html") or b"<head" in first_chunk.lower():
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
                                # 6A-35: the 25 s socket timeout only covers each single recv, so a mirror that trickles a
                                # few bytes now and then never times out, and read(65536) does not return until 64 KiB
                                # arrived. read1() returns as soon as data is there; a window check abandons this mirror
                                # when less than DL_STALL_MIN_BYTES arrived in DL_STALL_WINDOW seconds (next mirror is tried).
                                stall_mark_t, stall_mark_b = time.time(), dl_cur
                                read_some = getattr(resp, "read1", resp.read)
                                while True:
                                    chunk = read_some(65536)
                                    if not chunk:
                                        break
                                    f.write(chunk)
                                    dl_cur += len(chunk)
                                    now_c = time.time()
                                    if now_c - stall_mark_t >= DL_STALL_WINDOW:
                                        if dl_cur - stall_mark_b < DL_STALL_MIN_BYTES:
                                            raise TimeoutError(f"download stalled: {filename} from {cand_url}")
                                        stall_mark_t, stall_mark_b = now_c, dl_cur
                                    if slot_id is not None:
                                        with slot_lock:
                                            s_info = worker_status[slot_id]
                                            s_info["cur"] = dl_cur
                                            hist = s_info.get("history", [])
                                            hist.append((now_c, dl_cur))
                                            while hist and (now_c - hist[0][0] > 1.2):
                                                hist.pop(0)
                                            s_info["history"] = hist
                                            if len(hist) >= 2:
                                                dt = hist[-1][0] - hist[0][0]
                                                db = hist[-1][1] - hist[0][1]
                                                s_info["speed"] = max(0.0, db / dt) if dt > 0.05 else 0.0
                                    with lock:
                                        active_parts[part_path] = dl_cur

                        if os.path.exists(part_path) and self.is_valid_pkg_archive(part_path, expected_csize, expected_sha256):
                            shutil.move(part_path, local_path)
                            download_success = True
                            got_404_all = False
                            break
                        else:
                            if os.path.exists(part_path):
                                try: os.remove(part_path)
                                except Exception: pass
                    except urllib.error.HTTPError as e:
                        if e.code == 404:
                            pass
                        else:
                            got_404_all = False
                        if os.path.exists(part_path):
                            try: os.remove(part_path)
                            except Exception: pass
                    except Exception:
                        got_404_all = False
                        if os.path.exists(part_path):
                            try: os.remove(part_path)
                            except Exception: pass

                if download_success:
                    break

            if not download_success and got_404_all:
                with lock:
                    pkgs_with_404.add(pkg_data.get("NAME"))

            with lock:
                if part_path in active_parts:
                    del active_parts[part_path]
                if download_success and os.path.exists(local_path):
                    completed_bytes[0] += os.path.getsize(local_path)
                    completed_count[0] += 1

            if download_success and os.path.exists(local_path):
                sz_bytes = os.path.getsize(local_path)
                spd_val = worker_status[slot_id]["speed"] if slot_id is not None else 0.0
                with completed_lock:
                    completed_queue.append((filename, sz_bytes, spd_val))

            if slot_id is not None:
                with slot_lock:
                    worker_status[slot_id]["active"] = False
                    worker_status[slot_id]["name"] = ""
                    worker_status[slot_id]["filename"] = ""
                    worker_status[slot_id]["history"] = []
                    available_slots.append(slot_id)

            if download_success:
                return (pkg_data, local_path)
            return None

        try:
            with concurrent.futures.ThreadPoolExecutor(max_workers=num_workers) as executor:
                future_to_pkg = {executor.submit(fetch_one, p): p for p in needed_pkgs}
                for future in concurrent.futures.as_completed(future_to_pkg):
                    res = future.result()
                    if res:
                        downloaded_results.append(res)
        finally:
            stop_event.set()
            if mon_t:
                mon_t.join(timeout=1.0)
            if is_tty:
                sys.stdout.write("\033[?25h")
                sys.stdout.flush()

        if verbose and is_tty:
            out_buf = []
            if num_dynamic_lines[0] > 0:
                out_buf.append(f"\r\033[{num_dynamic_lines[0]}A")
            with completed_lock:
                final_completed = list(completed_queue)
                completed_queue.clear()
            for comp_fn, comp_sz, comp_spd in final_completed:
                comp_disp = comp_fn[:name_len-3] + "..." if len(comp_fn) > name_len else comp_fn
                comp_sz_str = self._format_size(comp_sz)
                comp_spd_str = self._format_speed(comp_spd)
                comp_bar = f"[{'-' * bar_width}] 100%"
                out_buf.append(f"\r\033[2K{comp_disp:<{name_len}s} {comp_sz_str:>10} {comp_spd_str:>11}  00:00 {comp_bar}\n")

            elapsed = max(0.001, time.time() - start_t)
            avg_speed_bps = completed_bytes[0] / elapsed
            tot_bar = f"[{'-' * bar_width}] 100%"
            tot_sz_str = self._format_size(completed_bytes[0])
            tot_spd_str = self._format_speed(avg_speed_bps)
            tot_label = f"Total ({completed_count[0]}/{total_pkgs})"
            tot_time_str = f"{int(elapsed) // 60:02d}:{int(elapsed) % 60:02d}"
            out_buf.append(f"\r\033[2K{tot_label:<{name_len}s} {tot_sz_str:>10} {tot_spd_str:>11} {tot_time_str:>5} {tot_bar}\n\n")
            out_buf.append("\033[J")
            sys.stdout.write("".join(out_buf))
            sys.stdout.flush()

        # Check for missed packages
        downloaded_names = {r[0].get("NAME") for r in downloaded_results}
        missing_pkgs = [p for p in needed_pkgs if p.get("NAME") not in downloaded_names]


        # Immediate Self-Healing if packages failed due to 404
        if missing_pkgs and pkgs_with_404:
            if verbose:
                print(f"  :: \033[1;33mSelf-Healing:\033[0m Detected {len(pkgs_with_404)} outdated package URL(s) (HTTP 404). Resynchronizing repository databases...")
            try:
                self.engine.sync_repositories(force=True, verbose=False)
            except Exception as e:
                if verbose:
                    print(f"  :: Warning: Auto-sync failed: {e}")

            for p in list(missing_pkgs):
                pname = p.get("NAME")
                if pname in pkgs_with_404:
                    refreshed = self.engine.index.get(pname)
                    if not refreshed:
                        continue
                    candidates = self.engine.get_download_urls_candidates(refreshed)
                    if not candidates:
                        continue
                    recov_ok = False
                    for cand_url in candidates:
                        fn = refreshed.get("FILENAME") or os.path.basename(cand_url)
                        lp = os.path.join(self.cache_pkg_dir, fn)
                        pp = lp + ".part"
                        exp_sz = int(refreshed.get("CSIZE", 0))
                        exp_sha = refreshed.get("SHA256SUM", "")
                        try:
                            req = urllib.request.Request(cand_url, headers=headers)
                            with url_open(req, 25) as resp:
                                first_chunk = resp.read(8192)
                                if not first_chunk or first_chunk.startswith(b"<html") or b"<head" in first_chunk.lower():
                                    continue
                                with open(pp, "wb") as f:
                                    f.write(first_chunk)
                                    copy_response_with_watchdog(resp, f, pp)
                            if os.path.exists(pp) and self.is_valid_pkg_archive(pp, exp_sz, exp_sha):
                                shutil.move(pp, lp)
                                downloaded_results.append((refreshed, lp))
                                recov_ok = True
                                if verbose:
                                    sz_mb = os.path.getsize(lp) / (1024 * 1024)
                                    print(f"  :: Self-healed \033[1m{pname}\033[0m ({refreshed.get('VERSION', '')}) [{sz_mb:.1f} MB]")
                                break
                        except Exception:
                            if os.path.exists(pp):
                                try: os.remove(pp)
                                except Exception: pass
                    if recov_ok:
                        missing_pkgs = [x for x in missing_pkgs if x.get("NAME") != pname]

        # Second Pass: Sequential recovery pass ONLY for non-404 transient dropouts
        transient_missing = [p for p in missing_pkgs if p.get("NAME") not in pkgs_with_404]
        if transient_missing:
            if verbose:
                print(f"  :: Retrying {len(transient_missing)} transiently missed payload(s) in sequential recovery pass...")
            for p in transient_missing:
                candidates = self.engine.get_download_urls_candidates(p)
                if not candidates:
                    continue
                filename = p.get("FILENAME") or os.path.basename(candidates[0])
                local_path = os.path.join(self.cache_pkg_dir, filename)
                part_path = local_path + ".part"
                expected_csize = int(p.get("CSIZE", 0))
                expected_sha256 = p.get("SHA256SUM", "")
                recov_success = False

                for cand_url in candidates:
                    for attempt in range(2):
                        try:
                            if attempt > 0:
                                time.sleep(0.3 * attempt)
                            req = urllib.request.Request(cand_url, headers=headers)
                            with url_open(req, 20) as resp:
                                first_chunk = resp.read(8192)
                                if not first_chunk or first_chunk.startswith(b"<html") or b"<head" in first_chunk.lower():
                                    continue
                                with open(part_path, "wb") as f:
                                    f.write(first_chunk)
                                    copy_response_with_watchdog(resp, f, part_path)
                            if os.path.exists(part_path) and self.is_valid_pkg_archive(part_path, expected_csize, expected_sha256):
                                shutil.move(part_path, local_path)
                                downloaded_results.append((p, local_path))
                                recov_success = True
                                if verbose:
                                    pname = p.get("NAME", "pkg")
                                    sz_mb = os.path.getsize(local_path) / (1024 * 1024)
                                    print(f"  :: Recovered \033[1m{pname}\033[0m [{sz_mb:.1f} MB]")
                                break
                        except Exception:
                            if os.path.exists(part_path):
                                try: os.remove(part_path)
                                except Exception: pass
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

    # --- [ P2/L1 (pacman master plan): glibc / libstdc++ / libgcc symbol headroom ] ---
    # FACT 2026-10-13: Arch binaries already need GLIBC_2.44 and GLIBCXX_3.4.36, exactly what Slackware -current ships.
    # The first Arch build against a newer glibc/gcc would fail at start-up ("version not found"). glibc can never be
    # bundled (it is tied to the host loader), so such a package is held: not packaged, the installed version stays.
    _HOST_SYMBOL_MAX: Optional[Dict[str, Tuple[int, ...]]] = None

    @staticmethod
    def _ver_tuple(v: str) -> Tuple[int, ...]:
        return tuple(int(x) for x in re.findall(r"\d+", v))

    @classmethod
    def host_symbol_max(cls) -> Dict[str, Tuple[int, ...]]:
        """Highest GLIBC_/GLIBCXX_/CXXABI_/GCC_ version the host libraries define (cached per process)."""
        if cls._HOST_SYMBOL_MAX is not None:
            return cls._HOST_SYMBOL_MAX
        res: Dict[str, Tuple[int, ...]] = {}
        try:
            g = os.confstr("CS_GNU_LIBC_VERSION") or ""
            m = re.search(r"([0-9]+\.[0-9]+)", g)
            if m:
                res["GLIBC"] = cls._ver_tuple(m.group(1))
        except (ValueError, OSError):
            pass
        for lib, prefixes in (("libstdc++.so.6", ("GLIBCXX", "CXXABI")), ("libgcc_s.so.1", ("GCC",))):
            path = next((os.path.join(d, lib) for d in ("/usr/lib64", "/lib64") if os.path.exists(os.path.join(d, lib))), "")
            if not path:
                continue
            try:
                out = subprocess.run(["readelf", "-V", "-W", path], capture_output=True, text=True, timeout=20).stdout
            except (OSError, subprocess.SubprocessError):
                continue
            for pre in prefixes:
                vers = [cls._ver_tuple(v) for v in re.findall(rf"\b{pre}_([0-9][0-9.]*)", out)]
                if vers:
                    res[pre] = max(vers)
        cls._HOST_SYMBOL_MAX = res
        return res

    def check_symbol_headroom(self, target_dir: str) -> List[Tuple[str, str]]:
        """Return (file, needed version) pairs that the host cannot satisfy. 64-bit ELF only (32-bit uses multilib)."""
        host = self.host_symbol_max()
        if "GLIBC" not in host or not shutil.which("readelf"):
            return []
        elf64: List[str] = []
        for root, _, files in os.walk(target_dir):
            for f in files:
                fp = os.path.join(root, f)
                try:
                    if os.path.islink(fp) or not os.path.isfile(fp):
                        continue
                    with open(fp, "rb") as fh:
                        head = fh.read(5)
                    if head[:4] == b"\x7fELF" and head[4:5] == b"\x02":
                        elf64.append(fp)
                except OSError:
                    continue
        bad: List[Tuple[str, str]] = []
        need_re = re.compile(r"Name:\s+(GLIBC|GLIBCXX|CXXABI|GCC)_([0-9][0-9.]*)")
        for i in range(0, len(elf64), 200):
            chunk = elf64[i:i + 200]
            try:
                out = subprocess.run(["readelf", "-V", "-W"] + chunk, capture_output=True, text=True, timeout=120).stdout
            except (OSError, subprocess.SubprocessError):
                continue
            cur = chunk[0] if len(chunk) == 1 else ""
            in_needs = False
            for line in out.splitlines():
                if line.startswith("File: "):
                    cur, in_needs = line[6:].strip(), False
                elif line.startswith("Version needs section"):
                    in_needs = True
                elif line.startswith("Version definition section") or line.startswith("Version symbols section"):
                    in_needs = False
                elif in_needs:
                    m = need_re.search(line)
                    if m and m.group(1) in host and self._ver_tuple(m.group(2)) > host[m.group(1)]:
                        bad.append((cur, f"{m.group(1)}_{m.group(2)}"))
        return bad

    @staticmethod
    def extract_pkg_archive(fpath: str, dest: str) -> Optional[str]:
        """WP-7: unpack one Arch package; None on success, else one plain sentence. No shell, both pipe ends checked."""
        name = os.path.basename(fpath)
        try:
            if fpath.endswith(".zst"):
                z = subprocess.Popen(["zstd", "-d", "-c", "--", fpath], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                t = subprocess.run(["tar", "-xf", "-", "-C", dest], stdin=z.stdout, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.PIPE, timeout=1800)
                if z.stdout:
                    z.stdout.close()
                zrc = z.wait(timeout=60)
                ok = zrc == 0 and t.returncode == 0
            else:
                t = subprocess.run(["tar", "-xf", fpath, "-C", dest], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                                   timeout=1800)
                ok = t.returncode == 0
        except (OSError, subprocess.SubprocessError):
            ok = False
        if ok:
            return None
        return f"The download {name} is damaged and could not be unpacked, so nothing was built. Run the update again."

    @staticmethod
    def _report_merge_clashes(clash: List[Tuple[str, str, str]], label: str, verbose: bool) -> None:
        """WP-7: files shipped by two packages with different content (the later package won). Reported, not fatal."""
        if not clash:
            return
        trust_log([{"check": "merge", "label": label, "path": c[0], "first": c[1], "kept": c[2]} for c in clash[:200]])
        if verbose:
            print(f":: {len(clash)} file(s) in {label} came from two packages with different content; the later one was kept.")
            for path, first, kept in clash[:3]:
                print(f"   {os.path.basename(path)}: {first} / {kept}")

    def trust_gate(self, downloaded: List[Tuple[Dict[str, Any], str]], verbose: bool = True) -> bool:
        """WP-7 / 6A-275: check every downloaded package against the repo database checksum and its signature
        (%PGPSIG% or the detached .sig) with the keys of its own family only (Arch keys for Arch repos, CachyOS keys for
        CachyOS repos, Chaotic keys for Chaotic repos). Enforce mode (default): a package that is not verified holds the
        whole build (False) with one plain sentence; a failure caused only by missing or too old keys first gets one key
        refresh and one retry. Log mode (SLACKY_GNOMES_TRUST=log, emergency override): results go to the trust log only."""
        # 6A-139: a DB entry without SHA256 is only checked by size and header; logged for now (owner decision WP-7)
        trust_log([{"check": "sha256", "status": "missing", "name": pd.get("NAME", ""), "repo": pd.get("_REPO", "")}
                   for pd, _ in downloaded if not str(pd.get("SHA256SUM", "") or "").strip()])
        trust = trust_module()
        if trust is None and downloaded and os.environ.get("SLACKY_GNOMES_TRUST", "") != "log":
            # 6A-360: no signature checker = no verified package; fail closed (emergency override: SLACKY_GNOMES_TRUST=log)
            print(":: The signature checker (gnomes_trust.py) is missing or broken, so no downloaded package was used; "
                  "reinstall slacky-update.")
            return False
        if trust is None or not downloaded:
            return True
        mode = trust.trust_mode()
        if mode != "enforce" and verbose:
            print(f":: {trust._t('log_override')}")

        def fetch_sig(pdata: Dict[str, Any], path: str) -> Optional[bytes]:
            # Chaotic-AUR's database carries no %PGPSIG%: use the detached .sig next to the package (cached)
            sig_path = path + ".sig"
            sig: Optional[bytes] = None
            try:
                if os.path.isfile(sig_path):
                    with open(sig_path, "rb") as fh:
                        return fh.read(16384)
                # 6A-244: the signature is the same file on every host of the family; try the first hosts in
                # order so one unreachable host does not make a signed package look unsigned. 6A-275: one more
                # round after a short pause, because a refused package stops the whole build.
                urls = [u for u in self.engine.get_download_urls_candidates(pdata)[:4] if u.startswith("https://")]
                for attempt in range(2):
                    for url in urls:
                        sig = trust.fetch_signature(trust.sig_url(url))
                        if sig:
                            with open(sig_path, "wb") as fh:
                                fh.write(sig)
                            return sig
                    if attempt == 0 and urls:
                        time.sleep(1.5)
            except OSError:
                pass
            return sig

        def one(item: Tuple[Dict[str, Any], str]) -> Any:
            pdata, path = item
            name, repo = pdata.get("NAME", ""), pdata.get("_REPO", "")
            pgpsig = str(pdata.get("PGPSIG", "") or "")
            inp: Dict[str, Any] = {"path": path, "sig": None, "repo": repo, "name": name, "pgpsig": pgpsig}
            bad_sum = trust.check_sha256(path, str(pdata.get("SHA256SUM", "") or ""), name=name, repo=repo)
            if bad_sum is not None:
                return bad_sum, inp
            sig = fetch_sig(pdata, path) if not pgpsig else None
            inp["sig"] = sig
            return trust.verify_package(path, sig, repo, name=name, pgpsig_b64=pgpsig), inp
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
            items = list(ex.map(one, downloaded))
        results = trust.settle_stale(items, mode)
        trust_log([dict(r.as_dict(), check="package", mode=mode) for r in results])
        blocked = [r for r in results if r.blocks(mode)]
        if blocked:
            print(f":: {blocked[0].message(mode)}")
            if len(blocked) > 1:
                print(f"   {len(blocked) - 1} more package(s) could not be verified either.")
            print("   Nothing was built or installed.")
            return False
        return True

    @staticmethod
    def runtime_host_only_guard(opt_runtime_dir: str) -> List[str]:
        """WP-3: remove every GPU/audio/TLS-trust file that slipped into the runtime (runtime contract). Returns the
        removed runtime-relative paths. Never follows symlinks out of the tree."""
        removed: List[str] = []
        root = os.path.abspath(opt_runtime_dir)
        for pat in RUNTIME_HOST_ONLY_FILES:
            for fp in glob.glob(os.path.join(root, pat)):
                if os.path.commonpath([root, os.path.abspath(fp)]) == root and (os.path.islink(fp) or os.path.isfile(fp)):
                    try:
                        os.unlink(fp)
                        removed.append(os.path.relpath(fp, root))
                    except OSError:
                        pass
        for d in RUNTIME_HOST_ONLY_DIRS:
            dp = os.path.join(root, d)
            if os.path.islink(dp):
                os.unlink(dp)
                removed.append(d)
            elif os.path.isdir(dp):
                shutil.rmtree(dp, ignore_errors=True)
                removed.append(d + "/")
        return sorted(removed)

    _HOST_VERDEFS: Dict[str, Set[str]] = {}

    @staticmethod
    def host_soname_map() -> Dict[str, str]:
        """64-bit sonames in the host ld.so.cache -> path."""
        res: Dict[str, str] = {}
        try:
            out = subprocess.run(["/sbin/ldconfig", "-p"], capture_output=True, text=True, timeout=20).stdout
        except (OSError, subprocess.SubprocessError):
            return res
        for line in out.splitlines():
            m = re.match(r"\s*(\S+)\s+\(([^)]*)\)\s+=>\s+(\S+)", line)
            if m and "x86-64" in m.group(2):
                res.setdefault(m.group(1), m.group(3))
        return res

    @classmethod
    def _host_verdefs(cls, path: str) -> Set[str]:
        if path not in cls._HOST_VERDEFS:
            names: Set[str] = set()
            try:
                out = subprocess.run(["readelf", "-V", "-W", path], capture_output=True, text=True, timeout=20).stdout
                in_defs = False
                for line in out.splitlines():
                    if line.startswith("Version definition section"):
                        in_defs = True
                    elif line.startswith("Version needs section") or line.startswith("Version symbols section"):
                        in_defs = False
                    elif in_defs:
                        m = re.search(r"Name:\s+(\S+)", line)
                        if m:
                            names.add(m.group(1))
            except (OSError, subprocess.SubprocessError):
                pass
            cls._HOST_VERDEFS[path] = names
        return cls._HOST_VERDEFS[path]

    def _write_runtime_manifest(self, opt_runtime_dir: str, profile: str, version: str,
                                downloaded: List[Tuple[Dict[str, Any], str]], plan: Dict[str, Any], removed: List[str]) -> None:
        """WP-3: opt/underpants/runtime/.gnomes/manifest.json (schema 1), a package-owned file and the seed of the
        per-package registry (WP-5/WP-6)."""
        def sha256_file(fp: str) -> str:
            h = hashlib.sha256()
            try:
                with open(fp, "rb") as fh:
                    for chunk in iter(lambda: fh.read(1 << 20), b""):
                        h.update(chunk)
                return h.hexdigest()
            except OSError:
                return ""
        repos: Dict[str, str] = {}
        pkgs: List[Dict[str, Any]] = []
        for pdata, fpath in downloaded:
            repo = pdata.get("_REPO", "")
            if repo and repo not in repos:
                db = next((os.path.join(self.engine.db_dir, f) for f in sorted(os.listdir(self.engine.db_dir))
                           if f.startswith(repo + ".db")), "")
                repos[repo] = sha256_file(db) if db else ""
            try:
                with tarfile.open(fpath, "r:*") as tf:
                    count = sum(1 for m in tf if m.isfile() or m.issym())
            except (tarfile.TarError, OSError):
                count = -1
            pkgs.append({"name": pdata.get("NAME", ""), "version": pdata.get("VERSION", ""), "repo": repo,
                         "sha256": pdata.get("SHA256SUM", "") or sha256_file(fpath),
                         "provides": pdata.get("PROVIDES", []), "files": count})
        host_only = []
        hp = plan.get("host_provided", {}) if isinstance(plan, dict) else {}
        pkgdb = FOOTPRINT_PKGDB
        installed = os.listdir(pkgdb) if os.path.isdir(pkgdb) else []
        for name, why in sorted(hp.items()):
            if "runtime contract" not in str(why):
                continue
            host_pkg = next((n for n in installed if footprint_pkg_base(n) == name.lower()), "")
            host_only.append({"package": name, "host_package": host_pkg})
        manifest = {"schema": 1, "profile": profile, "version": version,
                    "built": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                    "repo_db_sha256": repos, "packages": sorted(pkgs, key=lambda x: x["name"]),
                    "host_only": host_only, "host_only_files_removed": removed}
        mdir = os.path.join(opt_runtime_dir, ".gnomes")
        os.makedirs(mdir, exist_ok=True)
        with open(os.path.join(mdir, "manifest.json"), "w", encoding="utf-8") as fh:
            json.dump(manifest, fh, indent=1, sort_keys=True)
            fh.write("\n")

    def host_fit_problems(self, target_dir: str) -> List[str]:
        """WP-3 host-fit check: every host-only soname the tree needs must be a 64-bit library in the host ld.so.cache
        that defines every symbol version asked for. Returns '<soname> <reason>' items (empty = fits)."""
        if not shutil.which("readelf"):
            return ["readelf missing (cannot check)"]
        own = {f for _, _, fs in os.walk(os.path.join(target_dir, "lib")) for f in fs}
        elf64: List[str] = []
        for root, _, files in os.walk(target_dir):
            for f in files:
                fp = os.path.join(root, f)
                try:
                    if os.path.islink(fp) or not os.path.isfile(fp):
                        continue
                    with open(fp, "rb") as fh:
                        head = fh.read(5)
                    if head[:4] == b"\x7fELF" and head[4:5] == b"\x02":
                        elf64.append(fp)
                except OSError:
                    continue
        needed: Dict[str, Set[str]] = {}
        for i in range(0, len(elf64), 200):
            chunk = elf64[i:i + 200]
            try:
                out = subprocess.run(["readelf", "-d", "-V", "-W"] + chunk, capture_output=True, text=True, timeout=180).stdout
            except (OSError, subprocess.SubprocessError):
                return ["readelf failed (cannot check)"]
            in_needs, cur_lib = False, ""
            for line in out.splitlines():
                m = re.search(r"\(NEEDED\)\s+Shared library: \[([^\]]+)\]", line)
                if m:
                    needed.setdefault(m.group(1), set())
                    continue
                if line.startswith("Version needs section"):
                    in_needs = True
                elif line.startswith("File: ") and not in_needs:
                    continue
                elif line.startswith("Version definition section") or line.startswith("Version symbols section") or line.startswith("File: /"):
                    in_needs = False
                elif in_needs:
                    mf = re.search(r"File:\s+(\S+)\s+Cnt:", line)
                    if mf:
                        cur_lib = mf.group(1)
                        continue
                    mn = re.search(r"Name:\s+(\S+)", line)
                    if mn and cur_lib:
                        needed.setdefault(cur_lib, set()).add(mn.group(1))
        host = self.host_soname_map()
        problems: List[str] = []
        for so, vers in sorted(needed.items()):
            if so in own or not RUNTIME_HOST_ONLY_SONAME_RE.match(so):
                continue
            path = host.get(so)
            if not path:
                problems.append(f"{so} is not installed on this Slackware (64-bit)")
                continue
            missing = sorted(v for v in vers if v not in self._host_verdefs(path))
            if missing:
                problems.append(f"{so} on this Slackware lacks {', '.join(missing[:3])}")
        return problems

    @staticmethod
    def held_file_paths() -> List[str]:
        """Held list: root cache when running as root, the user's cache otherwise (both are read)."""
        return [os.path.join(DEFAULT_CACHE_BASE, "held.json"), os.path.join(USER_CACHE_BASE, "held.json")]

    @classmethod
    def host_symbol_stamp(cls) -> str:
        return ";".join(f"{k}={'.'.join(map(str, v))}" for k, v in sorted(cls.host_symbol_max().items()))

    @classmethod
    def held_is_current(cls, h: Dict[str, Any], up_ver: str) -> bool:
        """True while this exact version still waits: same host symbol stamp, and (6A-327) the libraries it lacked unchanged."""
        if not h or h.get("version") != up_ver:
            return False
        stamps = h.get("lib_stamps")
        if stamps:
            sv = symver_module()
            if sv is None:
                return True
            for st in stamps:
                if st.endswith(":none"):
                    if os.path.exists(st[:-5]):
                        return False
                elif sv.stamp_now(st) != st:
                    return False
            return True
        return h.get("host") == cls.host_symbol_stamp()

    @classmethod
    def load_held(cls) -> Dict[str, Dict[str, str]]:
        held: Dict[str, Dict[str, str]] = {}
        for fp in cls.held_file_paths():
            try:
                with open(fp, "r", encoding="utf-8") as fh:
                    for k, v in json.load(fh).items():
                        if isinstance(v, dict):
                            held[k] = v
            except (OSError, ValueError):
                continue
        return held

    HELD_NOW: List[str] = []

    @classmethod
    def record_held(cls, name: str, version: str, need: str, reason: str, stamps: Optional[List[str]] = None) -> None:
        """Remember a held package so it is shown and not rebuilt every run until the host or the package changes."""
        cls.HELD_NOW.append(name)  # 6A-339: this run held it, the CLI reports "waiting" (not a failure)
        fp = cls.held_file_paths()[0 if os.geteuid() == 0 else 1]
        try:
            os.makedirs(os.path.dirname(fp), exist_ok=True)
            data: Dict[str, Any] = {}
            if os.path.exists(fp):
                with open(fp, "r", encoding="utf-8") as fh:
                    data = json.load(fh)
            data[name] = {"version": version, "needs": need, "host": cls.host_symbol_stamp(), "reason": reason,
                          "since": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
            if stamps:
                data[name]["lib_stamps"] = stamps  # 6A-327: waiting until one of these libraries changes
            tmp = fp + ".tmp"
            with open(tmp, "w", encoding="utf-8") as fh:
                json.dump(data, fh, indent=2)
            os.replace(tmp, fp)
        except (OSError, ValueError):
            pass

    def _headroom_refusal(self, target_dir: str, label: str, verbose: bool, name: str = "", version: str = "") -> bool:
        """True (and one plain message) when the build must be held because the host libraries are too old."""
        bad = self.check_symbol_headroom(target_dir)
        if not bad:
            return False
        worst = max((b[1] for b in bad), key=lambda v: self._ver_tuple(v.split("_", 1)[1]))
        fam = worst.split("_", 1)[0]
        have = ".".join(str(x) for x in self.host_symbol_max().get(fam, ()))
        if name:
            self.record_held(name, version, worst, f"needs {worst}, host has {fam} {have}")
        print(f"\n\033[1;33m:: {label} needs a newer system library ({worst}) than this Slackware has ({fam} {have}), "
              f"so it was not installed and your current version stays. It will install once Slackware updates.\033[0m")
        if verbose:
            for f, v in bad[:5]:
                print(f"   {v}  {os.path.relpath(f, target_dir)}")
        return True

    def _symver_refusal(self, target_dir: str, name: str, version: str, verbose: bool) -> bool:
        """6A-327: True (one plain sentence, version put on the waiting list) when a program of the app asks for a library
        version that the library it will load (app, then runtime pool, then host) does not define."""
        sv = symver_module()
        if sv is None:
            return False
        try:
            res = sv.Checker(target_dir, "app").run()
        except Exception:
            return False
        if res["verdict"] != "REFUSE":
            return False
        sentence = sv.refusal_sentence(name, version, res)
        self.record_held(name, version, "symbol-version", sentence, stamps=res["stamps"])
        print(f"\n\033[1;33m:: {sentence}\033[0m")
        if verbose:
            for b in res["bad"][:5]:
                print(f"   {b[2]}  {b[0]}  ({b[1]})")
        return True

    def patch_elf_rpaths(self, target_dir: str, verbose: bool = True) -> int:
        """Rewrite RUNPATH and sanitize absolute DT_NEEDED paths on all ELF binaries using patchelf in parallel."""
        has_patchelf = shutil.which("patchelf") is not None
        if not has_patchelf:
            # 6A-273: one plain line per app (printed even when not verbose); the app is not refused
            print(":: " + localized_sentence("GNOMES_PATCHELF_WARN",
                  "{app}: some program files could not be adjusted (patchelf), so the app may load the wrong libraries; "
                  "it usually still starts because its launcher sets the library path.").replace(
                  "{app}", os.path.basename(os.path.normpath(target_dir))))
            return 0

        # WP-3: no /opt/underpants/common (never existed) and no 32-bit /usr/lib/{pulseaudio,pipewire-0.3} (wrong ELF class)
        rpath_val = "$ORIGIN/../lib:$ORIGIN/lib:$ORIGIN:/opt/underpants/runtime/lib:/usr/lib64/pulseaudio:/usr/lib64/pipewire-0.3:/usr/lib64/samba"

        elf_files = []
        # 6A-18: index every shared object in the tree so each ELF can get $ORIGIN-relative RUNPATH entries for the
        # app dirs that hold its NEEDED libs (e.g. lib/inkscape/libinkscape_base.so, or lib/ libs needed by plugins in
        # lib/<x>/modules). venv apps no longer export LD_LIBRARY_PATH or the nested lib loop (6A-14).
        so_re = re.compile(r"\.so(\.[0-9]+)*$")
        top_lib_dirs = [os.path.join(target_dir, "lib"), os.path.join(target_dir, "lib64")]
        lib_dirs_by_name = {}
        for root, _, files in os.walk(target_dir):
            for fname in files:
                fpath = os.path.join(root, fname)
                if so_re.search(fname):
                    lib_dirs_by_name.setdefault(fname, set()).add(root)
                if self.is_elf_file(fpath):
                    elf_files.append(fpath)

        if not elf_files:
            return 0

        base_rpath = rpath_val.split(":")

        def _private_rpath_entries(fpath: str, needed_list) -> list:
            elf_dir = os.path.dirname(fpath)
            reachable = {os.path.normpath(os.path.join(elf_dir, d)) for d in ("../lib", "lib", ".")}
            extra = []
            for needed in needed_list:
                dirs = lib_dirs_by_name.get(os.path.basename(needed))
                if not dirs:
                    continue
                if any(os.path.normpath(d) in reachable for d in dirs):
                    continue
                # top-level lib dirs first, then nested dirs in a stable order
                for d in sorted(dirs, key=lambda x: (x not in top_lib_dirs, x)):
                    entry = "$ORIGIN/" + os.path.relpath(d, elf_dir)
                    if entry not in extra:
                        extra.append(entry)
            return extra

        def _patch_single_elf(fpath: str):
            # 6A-19: returns True (patched), None (nothing to patch: relocatable object or static binary),
            # False (patchelf failed). Read-only files (e.g. perl XS modules, 0555) get u+w for the patch only.
            orig_mode = None
            try:
                with open(fpath, "rb") as fh:
                    hdr = fh.read(18)
                if len(hdr) < 18 or int.from_bytes(hdr[16:18], "little" if hdr[5] == 1 else "big") not in (2, 3):
                    return None
                st_mode = os.stat(fpath).st_mode
                if not st_mode & stat.S_IWUSR:
                    orig_mode = stat.S_IMODE(st_mode)
                    os.chmod(fpath, orig_mode | stat.S_IWUSR)
                res = subprocess.run(
                    ["patchelf", "--print-needed", fpath],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                    text=True,
                    check=False
                )
                needed_list = []
                if res.returncode == 0 and res.stdout:
                    needed_list = [n.strip() for n in res.stdout.strip().splitlines() if n.strip()]
                # 1. Set RUNPATH (app-private dirs go before the shared runtime pool)
                extra = _private_rpath_entries(fpath, needed_list)
                elf_rpath = ":".join(base_rpath[:3] + extra + base_rpath[3:]) if extra else rpath_val
                set_res = subprocess.run(
                    ["patchelf", "--set-rpath", elf_rpath, fpath],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    check=False
                )
                if set_res.returncode != 0:
                    # no dynamic section (static binary) -> nothing to relocate; otherwise a real failure
                    return None if res.returncode != 0 else False
                # 2. Sanitize any DT_NEEDED containing absolute paths (e.g. /usr/lib/libtlottie.so -> libtlottie.so)
                if needed_list:
                    for needed in needed_list:
                        if "/" in needed:
                            bare_lib = os.path.basename(needed)
                            if bare_lib:
                                subprocess.run(
                                    ["patchelf", "--replace-needed", needed, bare_lib, fpath],
                                    stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL,
                                    check=False
                                )
                return True
            except Exception:
                return False
            finally:
                if orig_mode is not None:
                    try:
                        os.chmod(fpath, orig_mode)
                    except OSError:
                        pass

        max_workers = min(32, (os.cpu_count() or 4) + 4)
        with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
            results = list(executor.map(_patch_single_elf, elf_files))

        failed = [os.path.relpath(f, target_dir) for f, r in zip(elf_files, results) if r is False]
        if failed:
            # 6A-273: ONE plain line per app with the count, no per-file list
            print(":: " + localized_sentence("GNOMES_PATCHELF_WARN",
                  "{app}: some program files could not be adjusted (patchelf), so the app may load the wrong libraries; "
                  "it usually still starts because its launcher sets the library path.").replace(
                  "{app}", os.path.basename(os.path.normpath(target_dir))) + f" ({len(failed)} file(s))")
        return sum(1 for r in results if r)

    @staticmethod
    def _run_makepkg_with_progress(staging_pkg: str, txz_output_path: str, verbose: bool = True) -> bool:
        """Create genuine Slackware .txz package via direct high-speed Slackware tar pipeline."""
        # 2A/2B: Footprint Guard (enforce mode unless SLACKY_FOOTPRINT_MODE=report)
        try:
            footprint_guard(staging_pkg, os.path.basename(txz_output_path).replace(".txz", ""))
        except Exception as fp_err:
            if os.environ.get("SLACKY_FOOTPRINT_MODE", "enforce").strip().lower() != "report":
                print(f":: Footprint check could not run ({fp_err}). Package not built.")
                return False
            print(f":: Footprint check could not run ({fp_err}).")
        # 6A-139: pipefail, so a find/tar error fails the package instead of leaving a short archive; paths as arguments
        cmd = ("set -o pipefail; cd \"$1\" && find ./ | LC_COLLATE=C sort | sed '2,$s,^\\./,,' | "
               "tar --owner=0 --group=0 --numeric-owner --mode='go+rX' --no-recursion -T - -cf - | xz -T0 -1 > \"$2\"")

        p = subprocess.Popen(["bash", "-c", cmd, "slacky-pack", staging_pkg, txz_output_path],
                             stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        is_tty = sys.stdout.isatty() and verbose

        if is_tty:
            start_t = time.time()
            anim_chars = ["underpants · · gnome", "· underpants · gnome", "· · underpants gnome", "· · · gnome profit", "· · underpants gnome", "· underpants · gnome"]
            idx = 0
            while p.poll() is None:
                elapsed = time.time() - start_t
                m = int(elapsed) // 60
                s = int(elapsed) % 60
                time_str = f"{m:02d}:{s:02d}"
                anim = anim_chars[idx % len(anim_chars)]
                sys.stdout.write(f"\033[2K\r   \033[1;36mCompressing Slackware package (xz -T0 -1) [{time_str}] {anim}\033[0m")
                sys.stdout.flush()
                idx += 1
                time.sleep(0.1)
            sys.stdout.write("\033[2K\r")
            sys.stdout.flush()

        stdout, stderr = p.communicate()
        if p.returncode != 0 or not os.path.exists(txz_output_path) or os.path.getsize(txz_output_path) == 0:
            if verbose:
                print(f"Error creating Slackware package: {stderr}")
            try:
                os.remove(txz_output_path)  # 6A-139: no short archive is left for an installer to pick up
            except OSError:
                pass
            return False
        return True

    def transmute_batch(self, target_names: List[str], verbose: bool = True, force: bool = False, noconfirm: bool = False) -> Optional[List[Dict[str, Any]]]:
        """Transmute multiple target packages in a unified dependency resolution and download run."""
        self.engine.ensure_loaded()
        clean_targets = [re.split(r"[><=]", t)[0].strip() for t in target_names if t.strip()]
        if not clean_targets:
            return None

        # 1. Check all targets exist and enforce Host Sovereignty Shield
        valid_targets = []
        for t in clean_targets:
            p = self.engine.get_package(t)
            if not p:
                if verbose:
                    print(f"Error: Target package '{t}' not found in synced repositories.")
                return None
            target_name_resolved = p["NAME"]
            if is_protected_host_binary(target_name_resolved):
                if verbose:
                    print(f"\n\033[1;31mSTOP: Host Sovereignty Shield Activated!\033[0m")
                    print(f"   '{target_name_resolved}' is a protected Slackware core system component.")
                    print(f"   The Host Sovereignty Shield refuses to transmute or overwrite core distribution utilities.")
                    print(f"   Please manage '{target_name_resolved}' natively using Slackware pkgtools or slackpkg.\n")
                return None
            valid_targets.append(target_name_resolved)

        # 2. Curated collision check
        for actual_name in valid_targets:
            collision = self.engine.check_curated_collision(actual_name)
            if collision and not force:
                if verbose:
                    print(f"\n\033[1;33mWarning: '{actual_name}' is already installed as a curated Slackware package ({collision})!\033[0m")
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
        # WP-2: refuse before downloading when the disk cannot hold the build
        no_room = space_precheck(sum(int(p.get("ISIZE", 0) or 0) for p in to_install), build_dir_base(), ", ".join(valid_targets))
        if no_room:
            print(f":: {no_room}")
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
        if not self.trust_gate(downloaded_files, verbose):
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

        # Host Sovereignty Shield: Refuse to transmute core distribution utilities
        if not is_runtime and is_protected_host_binary(actual_name):
            if verbose:
                print(f"\n\033[1;31mSTOP: Host Sovereignty Shield Activated!\033[0m")
                print(f"   '{actual_name}' is a protected Slackware core system component.")
                print(f"   The Host Sovereignty Shield refuses to transmute or overwrite core distribution utilities.")
                print(f"   Please manage '{actual_name}' natively using Slackware pkgtools or slackpkg.\n")
            return None

        # Curated Slackware Package Collision Guard (Skip for internal runtime packages)
        if not is_runtime and not pre_downloaded:
            collision = self.engine.check_curated_collision(actual_name)
            if collision and not force:
                if verbose:
                    print(f"\n\033[1;33mWarning: '{actual_name}' is already installed as a curated Slackware package ({collision})!\033[0m")
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
            if not self.trust_gate(downloaded_files, verbose):
                return None
        else:
            downloaded_files = []
            for p in to_install:
                candidates = self.engine.get_download_urls_candidates(p)
                fname = p.get("FILENAME") or (os.path.basename(candidates[0]) if candidates else f"{p.get('NAME')}.pkg.tar.zst")
                fname = os.path.basename(fname)  # 6A-139: never a path out of the cache dir
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
        # 6A-50: private staging dir (mkdtemp 0700), never a predictable /tmp path
        staging_base = tempfile.mkdtemp(prefix=f"transmute-gnomes-{actual_name}-", dir=build_dir_base())
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
            primary_desktop_binaries: Set[str] = set()

            # WP-7: which package put each staged file there; a different file from a second package is reported
            merge_state: Dict[str, Any] = {"pkg": "", "owner": {}, "clash": []}

            def _note_merge(d_f: str, s_f: str) -> None:
                prev, cur = merge_state["owner"].get(d_f), merge_state["pkg"]
                if prev and prev != cur:
                    try:
                        if os.path.islink(s_f) or os.path.islink(d_f):
                            same = os.path.islink(s_f) and os.path.islink(d_f) and os.readlink(s_f) == os.readlink(d_f)
                        else:
                            import filecmp
                            same = os.path.isfile(d_f) and filecmp.cmp(s_f, d_f, shallow=False)
                    except OSError:
                        same = False
                    if not same:
                        merge_state["clash"].append((d_f, prev, cur))
                merge_state["owner"][d_f] = cur

            def _merge_tree(src_dir: str, dst_dir: str):
                """Recursively merge src_dir into dst_dir without deleting existing non-conflicting files/subdirectories."""
                # 6A-138: links stay links, no write through a destination link, a copy error stops the build
                merge_tree_safe(src_dir, dst_dir, staging_pkg, _note_merge)

            # Extract all archives and recursively merge payloads
            for pdata, fpath in downloaded_files:
                is_primary = (pdata.get("NAME") == actual_name)
                tmp_extract = os.path.join(staging_base, f"extract_{pdata['NAME']}")
                os.makedirs(tmp_extract, exist_ok=True)
                merge_state["pkg"] = pdata.get("NAME", "")
                # WP-7: a broken or truncated archive stops the build (it was silently half-extracted before)
                x_err = self.extract_pkg_archive(fpath, tmp_extract)
                if x_err:
                    print(f":: {x_err}")
                    return None

                # Merge binaries into opt_bin_dir
                for cand_bin in ["usr/bin", "bin", "usr/sbin", "sbin"]:
                    src = os.path.join(tmp_extract, cand_bin)
                    # 6A-138: a linked bin dir (usr/sbin -> bin) is never followed out of the extracted package
                    if os.path.isdir(src) and not os.path.islink(src):
                        for item in os.listdir(src):
                            s = os.path.join(src, item)
                            d = os.path.join(opt_bin_dir, item)
                            if is_primary:
                                primary_binaries.add(item)
                            if os.path.islink(s):
                                _merge_place_link(s, d)
                            elif os.path.isfile(s):
                                _merge_copy_file(s, d)
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
                                            idx = desktop_exec_program_index(parts) if parts else -1
                                            if idx >= 0:
                                                prog = os.path.basename(parts[idx])
                                                if prog:
                                                    primary_desktop_binaries.add(prog)
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
                    app_key = re.sub(r"-(bin|git|appimage)$", "", actual_name.lower())
                    for s_item in os.listdir(opt_share_dir):
                        s_item_path = os.path.join(opt_share_dir, s_item)
                        if not os.path.isdir(s_item_path):
                            continue
                        if s_item in ("applications", "icons", "pixmaps", "locale", "man", "doc", "info", "gtk-doc", "help", "bash-completion", "zsh", "fish"):
                            continue
                        elif s_item in HOST_SHARE_SKIP:
                            # 6A-20: build-only data and host sound-stack config stay in APP_ROOT/share (XDG_DATA_DIRS)
                            continue
                        elif s_item == "dbus-1":
                            # 6A-20: only the app's own session service; bundled portal/dependency services would
                            # replace the desktop-wide ones (claude-desktop/lutris shipped xdg-desktop-portal services)
                            s_services = os.path.join(s_item_path, "services")
                            if os.path.isdir(s_services):
                                for svc in sorted(os.listdir(s_services)):
                                    svc_path = os.path.join(s_services, svc)
                                    if svc.endswith(".service") and app_key in svc.lower() and os.path.isfile(svc_path):
                                        d_svc_dir = os.path.join(staging_pkg, "usr/share/dbus-1/services")
                                        os.makedirs(d_svc_dir, exist_ok=True)
                                        shutil.copy2(svc_path, os.path.join(d_svc_dir, svc))
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

            self._report_merge_clashes(merge_state["clash"], actual_name, verbose)
            # Universal text script and configuration path relocation pass
            self._relocate_text_and_symlink_paths(opt_app_dir, actual_name, staging_pkg)

            # Patch ELF RUNPATH
            if verbose:
                print(":: Relocating ELF RUNPATH with patchelf...")
            patched_count = self.patch_elf_rpaths(opt_app_dir, verbose=verbose)
            if verbose:
                print(f"  Relocated {patched_count} ELF binaries and shared objects.")

            # P2/L1: hold the package when it needs newer glibc/libstdc++/libgcc symbols than the host provides
            if self._headroom_refusal(opt_app_dir, actual_name, verbose, name=actual_name, version=raw_version):
                self.safe_rmtree(staging_base)
                return None
            # 6A-327: any other library version the app asks for (Qt_6.12, ...) must exist where it will be loaded from
            if not is_runtime and self._symver_refusal(opt_app_dir, actual_name, raw_version, verbose):
                self.safe_rmtree(staging_base)
                return None

            # 6A-10: private venv (after patchelf, so patchelf never follows the symlink into the runtime)
            if not is_runtime:
                self._create_python_venv(opt_app_dir, actual_name, verbose=verbose)

            # Remove sandboxed Glycin pixbuf loader and clean loaders.cache
            # 6A-172: the cache must name the INSTALLED folder, never the build/staging folder
            _final_lib = "/opt/underpants/runtime/lib/" if is_runtime else f"/opt/underpants/pkgs/{actual_name}/lib/"
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
                                cleaned_lines.append(line.replace("/usr/lib64/", _final_lib).replace("/usr/lib/", _final_lib))
                            with open(lpath, "w", encoding="utf-8") as lf:
                                lf.writelines(cleaned_lines)
                        except Exception:
                            pass

            # Discover primary package candidates to wrap into /usr/bin/ (strictly scoped to primary application targets)
            canon_name = self.engine.canonical_app_name(actual_name)
            target_names = {actual_name.lower(), canon_name.lower()}
            for suffix in ("-bin", "-appimage", "-desktop", "-git", "-nightly", "-beta", "-qt5", "-qt6", "-gtk3", "-gtk4", "-gui", "-cli"):
                if actual_name.lower().endswith(suffix):
                    target_names.add(actual_name.lower()[:-len(suffix)])
            for t in list(target_names):
                target_names.add(t.replace("-", "").replace("_", ""))

            host_bins = HostLibraryScanner.get_host_binary_map()

            # Filter candidates so only genuine primary application executables are wrapped into /usr/bin
            def _is_clean_app_wrapper(name: str) -> bool:
                if not name or name.startswith(".") or name.startswith("_"):
                    return False
                if any(name.endswith(ext) for ext in [".kiface", ".so", ".a", ".la", ".o", ".pyc", ".pyo", ".h", ".hpp", ".conf", ".ini", ".desktop"]):
                    return False
                low = name.lower()
                if is_protected_host_binary(name):
                    return False
                for ign in ["xdg-", "wx-", "wxrc", "argon", "pkg-config", "pkgconf", "update-", "libtool", "install-", "make", "bison", "flex", "m4", "gcore", "gdb", "test", "demo", "sample", "example"]:
                    if (low.startswith(ign) or low == ign) and low not in target_names:
                        return False
                # Never generate wrapper for existing native host binary unless target explicitly matches
                if name in host_bins and low not in target_names:
                    return False
                return True

            raw_candidates: Set[str] = set()

            # 1. Add binaries from primary package that match target name variants
            for b in primary_binaries:
                b_low = b.lower()
                if b_low in target_names or b_low.startswith(actual_name.lower() + "-") or b_low.startswith(canon_name.lower() + "-"):
                    raw_candidates.add(b)

            # 2. Add binaries explicitly registered in primary desktop entries
            for db in primary_desktop_binaries:
                if db in primary_binaries or os.path.exists(os.path.join(opt_bin_dir, db)):
                    raw_candidates.add(db)

            # 3. Always include actual_name and canon_name as candidates
            raw_candidates.add(actual_name)
            if canon_name:
                raw_candidates.add(canon_name)

            # 4. Fallback: If no candidate matched and primary package has a single binary, use it if safe
            if not any(c in primary_binaries for c in raw_candidates) and len(primary_binaries) == 1:
                single_b = next(iter(primary_binaries))
                if _is_clean_app_wrapper(single_b):
                    raw_candidates.add(single_b)

            candidates_to_wrap = {c for c in raw_candidates if _is_clean_app_wrapper(c)}

            # Ensure all binaries in opt_bin_dir are executable
            if os.path.isdir(opt_bin_dir):
                for b in os.listdir(opt_bin_dir):
                    try:
                        # 6A-173: a link that leaves the app folder is never followed (chmod would hit a host file)
                        if os.path.islink(os.path.join(opt_bin_dir, b)) and not _merge_inside(os.path.join(opt_bin_dir, b), opt_app_dir):
                            continue
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
            try:
                slack_owned = footprint_load_owners()
            except Exception:
                slack_owned = {}
            if not is_runtime:
                for bname in sorted(all_targets):
                    # Never overwrite core host system binaries under any circumstance
                    if is_protected_host_binary(bname):
                        continue
                    # 6A-11: never shadow a program a Slackware package owns (incl. doinst symlinks like
                    # coreutils' /usr/bin/env, which the file-list based host map does not see)
                    if f"usr/bin/{bname}" in slack_owned:
                        if verbose:
                            print(f"  ! Skipping wrapper '{bname}': /usr/bin/{bname} belongs to {slack_owned[f'usr/bin/{bname}']}.")
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
                            # 6A-173: a desktop-file link that leaves the package tree is never rewritten
                            if os.path.islink(df_path) and not _merge_inside(df_path, staging_pkg):
                                continue
                            with open(df_path, "r", encoding="utf-8", errors="ignore") as f:
                                dlines = f.readlines()
                            newlines = []
                            for l in dlines:
                                if l.startswith("Exec="):
                                    parts = l[5:].strip().split()
                                    idx = desktop_exec_program_index(parts) if parts else -1
                                    if idx >= 0:
                                        # 6A-11: keep an `env VAR=...` prefix as is, rewrite only the program
                                        prog = os.path.basename(parts[idx])
                                        prefix = " ".join(parts[:idx])
                                        rest = " ".join(parts[idx + 1:])
                                        cmd = f"{prefix} /usr/bin/{prog} {rest}".strip()
                                        newlines.append(f"Exec={cmd}\n")
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
            # 6A-271 (mirror of Rust GAP-3): the Footprint Guard drops rc scripts of dependency services. Hook only the
            # services whose script is still in the package, and say once how to start each dropped one by hand.
            if created_services:
                try:
                    footprint_guard(staging_pkg, f"underpants-{actual_name}")
                except Exception:
                    pass   # the guard runs again when packing and refuses there if it cannot run
                kept = [sv for sv in created_services if os.path.lexists(os.path.join(staging_pkg, "etc/rc.d", f"rc.{sv}"))]
                for sv in created_services:
                    if sv not in kept:
                        cmd_line = getattr(self, "_service_cmds", {}).get(sv, "")
                        print(f":: {actual_name} has a background service ({sv}) that does not start by itself; "
                              f"to start it by hand, run: {cmd_line}")
                created_services = kept

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
                doinst_content += gnomes_rc_hook_snippet(svc)
            with open(doinst_path, "w", encoding="utf-8") as dif:
                dif.write(doinst_content)
            os.chmod(doinst_path, 0o755)

            # Write install/douninst.sh for safe service and hook teardown on removepkg
            if created_services:
                douninst_path = os.path.join(install_dir, "douninst.sh")
                # 6A-6c: removepkg runs douninst AFTER deleting the package's files. If /etc/rc.d/rc.SVC still exists
                # this is an upgrade (or another package ships it): keep the hook and do not stop the running daemon.
                # Otherwise remove the block safely: both markers required, sh -n before and after, temp file + .slacky-bak.
                # (Before: an unconditional "stop" during upgrades and a sed range that deleted to EOF without the end marker.)
                douninst_lines = [
                    "#!/bin/sh",
                    "# Underpants Gnomes clean teardown of service hooks (spec: docs/rclocal_spec.md)",
                    GNOMES_RC_REMOVE_SH,
                ]
                for svc in created_services:
                    douninst_lines.append(f"if [ ! -e /etc/rc.d/rc.{svc} ]; then")
                    douninst_lines.append(f"  for f in /etc/rc.d/rc.local /etc/rc.d/rc.local_shutdown; do")
                    douninst_lines.append(f"    gnomes_rc_remove \"$f\" '# --- [ gnomes-service: {svc} ] ---' '# --- [ /gnomes-service: {svc} ] ---'")
                    douninst_lines.append(f"  done")
                    douninst_lines.append(f"fi")
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
                print(f"\n\033[1;32mSuccessfully transmuted {actual_name} into genuine Slackware package!\033[0m")
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
        except MergeCopyError as e:
            # 6A-138: a file that could not be staged stops the build; nothing half-built is packaged
            print(f":: {e} The package was not built.")
            return None
        finally:
            self.safe_rmtree(staging_base)

    def _transmute_systemd_services(self, staging_pkg: str, opt_app_dir: str, actual_name: str) -> List[str]:
        """
        Discovers systemd .service files in the transmuted payload and generates genuine
        Slackware BSD init scripts (/etc/rc.d/rc.<service>) with start/stop/restart/status routines.
        """
        created_services = []
        self._service_cmds = {}   # 6A-271: service -> command its rc script starts (for the by-hand hint)
        if not os.path.isdir(opt_app_dir):
            return created_services

        service_files = []
        for root, _, files in os.walk(opt_app_dir):
            # Only system-level daemons belong in /etc/rc.d/. User session services
            # (such as wireplumber, pipewire-pulse, xdg desktop portals) are managed
            # within the user graphical session via XDG autostart or D-Bus activation.
            if "systemd/system" in root and "systemd/user" not in root:
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
                # Never convert user session audio or portals into root /etc/rc.d daemons
                if svc_name in ("wireplumber", "pipewire", "pipewire-pulse") or "portal" in svc_name:
                    continue

                # 6A-173: a unit that is a link out of the app folder is never read
                if not _merge_inside(s_path, opt_app_dir):
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
                self._service_cmds[svc_name] = exec_cmd.strip()
            except Exception:
                pass

        return created_services

    def transmute_runtime_profile(self, profile_name: str, verbose: bool = True, force: bool = False, output_dir: Optional[str] = None,
                                  keep_staging: bool = False, hooks: Optional[Dict[str, Any]] = None) -> Optional[Dict[str, Any]]:
        """
        Transmute a curated runtime profile (core, gui, media, engineering, all) or list of packages
        into a unified /opt/underpants/runtime/ shared runtime environment packaged as a genuine Slackware .txz.

        7N (docs/runtime_refresh_spec.md 5.3): keep_staging leaves the staged tree in place on success (the caller removes it;
        result keys "staging_base" / "staging_runtime"); hooks = {"space": fn(S, C, C_missing) -> None | text,
        "check": fn(staged_runtime_dir) -> None | text}. A hook that answers with text stops the build (nothing is
        packaged, the caller prints the sentence) and the reason is left in self.outcome["kind"] ("no_space" / "vetoed").
        """
        self.outcome: Dict[str, Any] = {"kind": "build_failed"}
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
            print(f"  Runtime Profile Payload Packages ({len(to_install)} files • {total_mb:.2f} MB):")
            for i, p in enumerate(to_install, 1):
                csize_mb = int(p.get("CSIZE", 0)) / (1024 * 1024)
                print(f"    • ({i:>2d}/{len(to_install)}) [{p.get('_REPO')}] {p.get('NAME')} ({p.get('VERSION')}) [{csize_mb:.2f} MB]")
            print()

        s_bytes = sum(int(p.get("ISIZE", 0) or 0) for p in to_install)
        if hooks and hooks.get("space"):
            c_bytes = sum(int(p.get("CSIZE", 0) or 0) for p in to_install)
            c_missing = 0
            for p in to_install:
                fn = p.get("FILENAME") or ""
                if not fn or not os.path.exists(os.path.join(self.cache_pkg_dir, os.path.basename(fn))):
                    c_missing += int(p.get("CSIZE", 0) or 0)
            no_room = hooks["space"](s_bytes, c_bytes, c_missing)
            if no_room:
                self.outcome = {"kind": "no_space"}
                return None
        else:
            no_room = space_precheck(s_bytes, build_dir_base(), f"the {profile_name} runtime")
            if no_room:
                print(f":: {no_room}")
                return None

        downloaded_files = self.download_packages_parallel(to_install, verbose=verbose)
        if len(downloaded_files) < len(to_install):
            return None
        if not self.trust_gate(downloaded_files, verbose):
            return None

        staging_base = tempfile.mkdtemp(prefix=f"transmute-gnomes-runtime-{profile_name}-", dir=build_dir_base())
        staging_pkg = os.path.join(staging_base, "pkg")
        opt_runtime_dir = os.path.join(staging_pkg, "opt", "underpants", "runtime")
        opt_bin_dir = os.path.join(opt_runtime_dir, "bin")
        opt_lib_dir = os.path.join(opt_runtime_dir, "lib")
        opt_share_dir = os.path.join(opt_runtime_dir, "share")
        opt_inc_dir = os.path.join(opt_runtime_dir, "include")
        install_dir = os.path.join(staging_pkg, "install")
        keep_now = {"v": False}

        try:
            os.makedirs(opt_bin_dir, exist_ok=True)
            os.makedirs(opt_lib_dir, exist_ok=True)
            os.makedirs(opt_share_dir, exist_ok=True)
            os.makedirs(opt_inc_dir, exist_ok=True)
            os.makedirs(install_dir, exist_ok=True)

            if verbose:
                print(f":: Extracting and staging runtime payloads into /opt/underpants/runtime/...")

            # WP-7: which package put each staged file there; a different file from a second package is reported
            merge_state: Dict[str, Any] = {"pkg": "", "owner": {}, "clash": []}

            def _note_merge(d_f: str, s_f: str) -> None:
                prev, cur = merge_state["owner"].get(d_f), merge_state["pkg"]
                if prev and prev != cur:
                    try:
                        if os.path.islink(s_f) or os.path.islink(d_f):
                            same = os.path.islink(s_f) and os.path.islink(d_f) and os.readlink(s_f) == os.readlink(d_f)
                        else:
                            import filecmp
                            same = os.path.isfile(d_f) and filecmp.cmp(s_f, d_f, shallow=False)
                    except OSError:
                        same = False
                    if not same:
                        merge_state["clash"].append((d_f, prev, cur))
                merge_state["owner"][d_f] = cur

            def _merge_tree(src_dir: str, dst_dir: str):
                # 6A-138: links stay links, no write through a destination link, a copy error stops the build
                merge_tree_safe(src_dir, dst_dir, staging_pkg, _note_merge)

            for pdata, fpath in downloaded_files:
                tmp_extract = os.path.join(staging_base, f"extract_{pdata['NAME']}")
                os.makedirs(tmp_extract, exist_ok=True)
                merge_state["pkg"] = pdata.get("NAME", "")
                # WP-7: a broken or truncated archive stops the build (it was silently half-extracted before)
                x_err = self.extract_pkg_archive(fpath, tmp_extract)
                if x_err:
                    print(f":: {x_err}")
                    return None

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
                    # 6A-36: the shared runtime never writes /etc on the host. Its packages' defaults (gnutls/config with
                    # ktls=false, an MIT-example krb5.conf, tpm2-tss, sensord, ...) changed Slackware's own programs too.
                    # They are kept for reference under /opt/underpants/runtime/etc; the libraries use built-in defaults.
                    _merge_tree(src_etc, os.path.join(opt_runtime_dir, "etc"))

            self._report_merge_clashes(merge_state["clash"], f"runtime-{profile_name}", verbose)
            # WP-3: runtime contract, no GPU front-end, audio client or TLS trust stack in the runtime
            host_only_removed = self.runtime_host_only_guard(opt_runtime_dir)
            if verbose and host_only_removed:
                print(f":: Left {len(host_only_removed)} graphics/audio/TLS file(s) to Slackware (runtime contract).")

            # Relocate text, symlink, and ELF paths
            self._relocate_text_and_symlink_paths(opt_runtime_dir, f"runtime-{profile_name}", staging_pkg)
            if verbose:
                print(":: Relocating runtime ELF RUNPATH with patchelf...")
            patched_count = self.patch_elf_rpaths(opt_runtime_dir, verbose=verbose)
            if verbose:
                print(f"  Relocated {patched_count} ELF binaries and shared objects.")

            # P2/L1: never ship a runtime that needs newer glibc/libstdc++/libgcc symbols than the host provides
            if self._headroom_refusal(opt_runtime_dir, f"The shared runtime ({profile_name})", verbose, name=f"runtime-{profile_name}"):
                shutil.rmtree(staging_base, ignore_errors=True)
                return None
            # WP-3 host-fit: what the runtime now takes from Slackware must exist there with the needed symbol versions
            unfit = self.host_fit_problems(opt_runtime_dir)
            if unfit:
                print(f"\n\033[1;33m:: The shared runtime ({profile_name}) needs a newer graphics, sound or TLS library than "
                      f"this Slackware has, so it was not built and your current runtime stays.\033[0m")
                for u in unfit[:5]:
                    print(f"   {u}")
                shutil.rmtree(staging_base, ignore_errors=True)
                return None
            self._write_runtime_manifest(opt_runtime_dir, profile_name, RUNTIME_PKG_VERSION, downloaded_files, plan,
                                         host_only_removed)

            # 7L/7N: the startability check of the candidate runs on the staged tree BEFORE anything is packaged
            if hooks and hooks.get("check"):
                veto = hooks["check"](opt_runtime_dir)
                if veto:
                    self.outcome = {"kind": "vetoed"}
                    return None

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
                f"{tag}: {tag} (v{RUNTIME_PKG_VERSION})",
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

            txz_filename = f"underpants-runtime-{profile_name}-{RUNTIME_PKG_VERSION}-x86_64-1_gnomes.txz"
            txz_output_path = os.path.join(self.output_dir, txz_filename)

            if verbose:
                print(f":: Building Slackware package {txz_filename} with makepkg...")

            if not self._run_makepkg_with_progress(staging_pkg, txz_output_path, verbose=verbose):
                return None

            pkg_size_mb = os.path.getsize(txz_output_path) / (1024 * 1024)
            if verbose:
                print(f"\n\033[1;32mPROFIT! Successfully transmuted runtime profile '{profile_name}' into Slackware package!\033[0m")
                print(f"  Package File    : {txz_output_path} [{pkg_size_mb:.2f} MB]")
                print(f"  Installed Root  : /opt/underpants/runtime/")
                print(f"  Install Command : \033[1;36mupgradepkg --install-new {txz_output_path}\033[0m\n")

            keep_now["v"] = bool(keep_staging)
            return {
                "name": f"runtime-{profile_name}",
                "version": RUNTIME_PKG_VERSION,
                "txz_path": txz_output_path,
                "size_bytes": os.path.getsize(txz_output_path),
                "packages": [p["NAME"] for p in to_install],
                "staging_base": staging_base if keep_staging else "",
                "staging_runtime": opt_runtime_dir if keep_staging else "",
            }
        except MergeCopyError as e:
            # 6A-138: a file that could not be staged stops the build; nothing half-built is packaged
            print(f":: {e} The package was not built.")
            return None
        finally:
            if not keep_now["v"]:
                shutil.rmtree(staging_base, ignore_errors=True)

    @staticmethod
    def purge_gnomes_service_hooks(svc_name: str, files: Optional[Tuple[str, ...]] = None, lock_path: str = "/run/lock/slacky-update.lock") -> List[str]:
        """
        Cleanly purges demarcated gnomes-service blocks from /etc/rc.d/rc.local and
        /etc/rc.d/rc.local_shutdown with zero residual syntax errors.

        6A-263: under the shared run lock (skipped when the calling script already holds it), a backup copy
        `<file>.slacky-bak` first, a temp file in the same folder + rename, owner and mode kept, and a link is never
        followed or rewritten. Returns one plain sentence per file that was NOT changed because it was unsafe.
        """
        import fcntl
        problems: List[str] = []
        targets = files if files is not None else ("/etc/rc.d/rc.local", "/etc/rc.d/rc.local_shutdown")
        lock_fd = None
        if os.environ.get("SLACKY_RUN_LOCK_HELD") != "1":
            try:
                lock_fd = os.open(lock_path, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW)
            except OSError:
                lock_fd = None  # no lock file (a normal system without one): the other protections still apply
            if lock_fd is not None:
                deadline = time.time() + 60
                while True:
                    try:
                        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                        break
                    except OSError:
                        if time.time() > deadline:
                            os.close(lock_fd)
                            return ["Another update is running right now, so the startup file was not changed; try again when it has finished."]
                        time.sleep(0.5)
        try:
            pattern = r'(?m)^[ \t]*# --- \[ gnomes-service: ' + re.escape(svc_name) + r' \] ---[\s\S]*?^[ \t]*# --- \[ /gnomes-service: ' + re.escape(svc_name) + r' \] ---\n?'
            for fpath in targets:
                try:
                    if os.path.islink(fpath):
                        problems.append(f"{fpath} is a link, so it was not changed.")
                        continue
                    if not os.path.isfile(fpath):
                        continue
                    st = os.stat(fpath)
                    with open(fpath, "r", encoding="utf-8", errors="strict") as fp:
                        content = fp.read()
                    new_content = re.sub(pattern, "", content)
                    if new_content == content:
                        continue
                    d = os.path.dirname(fpath)
                    tmp = os.path.join(d, f".{os.path.basename(fpath)}.gnomes-tmp.{os.getpid()}")
                    bak = fpath + ".slacky-bak"
                    try:
                        # keep a copy of what is replaced (never through a link)
                        if os.path.islink(bak):
                            problems.append(f"{bak} is a link, so {fpath} was not changed.")
                            continue
                        shutil.copy2(fpath, bak)
                        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
                        with os.fdopen(fd, "w", encoding="utf-8") as fp:
                            fp.write(new_content)
                            fp.flush()
                            os.fsync(fp.fileno())
                        os.chmod(tmp, stat.S_IMODE(st.st_mode))
                        try:
                            os.chown(tmp, st.st_uid, st.st_gid)
                        except PermissionError:
                            if os.geteuid() == 0:
                                raise
                        # a result that no longer parses is refused when the original did parse
                        was_ok = subprocess.run(["sh", "-n", fpath], capture_output=True).returncode == 0
                        now_ok = subprocess.run(["sh", "-n", tmp], capture_output=True).returncode == 0
                        if was_ok and not now_ok:
                            os.remove(tmp)
                            problems.append(f"{fpath} would have a syntax error after the change, so it was not changed.")
                            continue
                        os.replace(tmp, fpath)
                    except Exception:
                        try:
                            os.remove(tmp)
                        except OSError:
                            pass
                        problems.append(f"{fpath} could not be changed safely, so it was left as it was.")
                except Exception:
                    problems.append(f"{fpath} could not be read, so it was not changed.")
        finally:
            if lock_fd is not None:
                os.close(lock_fd)
        return problems


class RuntimeManager:
    """Manages the isolated Underpants Gnomes runtime (/opt/underpants/runtime/) and shared library pool."""

    RUNTIME_DIR = "/opt/underpants/runtime"
    COMMON_DIR = "/opt/underpants/common"
    PKGS_DIR = "/opt/underpants/pkgs"

    PROFILES: Dict[str, List[str]] = {
        "core": ["python", "glib2", "sqlite", "openssl", "curl", "libxml2", "icu", "fmt", "onetbb"],
        # 6A-34: "breeze" + "plasma-integration" give gnomes Qt6 apps the KDE platform theme and Breeze style built for
        # the runtime's Qt; the host plugins are built for Slackware's Qt and fail to load (light Fusion fallback).
        "gui": ["gtk3", "gtk4", "libadwaita", "librsvg", "gdk-pixbuf2", "shared-mime-info", "adwaita-icon-theme", "hicolor-icon-theme", "qt5-base", "qt5-wayland", "qt5-svg", "qt6-base", "qt6-wayland", "qt6-declarative", "qt6-svg", "qt6-webengine", "wxwidgets-gtk3", "libnotify", "webkit2gtk-4.1", "libspnav", "libmanette", "breeze", "plasma-integration"],
        # WP-3: libva, libvdpau, pipewire, alsa-lib and vulkan-icd-loader come from Slackware (RUNTIME_HOST_ONLY)
        "media": ["ffmpeg", "gstreamer", "gst-plugins-base", "gst-plugins-good", "sdl2", "libsamplerate", "libebur128", "taglib", "wavpack", "chromaprint"],
        "graphics": ["openxr", "embree", "hwloc", "onetbb", "libsquish", "libwslay", "miniupnpc", "glm", "freeglut", "glew", "glfw", "openal"],
        "cad": ["opencascade", "vtk", "ngspice", "verdict", "pugixml", "jsoncpp", "poppler", "mpdecimal", "cblas", "lapack", "openblas"],
        "mobile": ["libimobiledevice", "libimobiledevice-glue", "libplist", "libtatsu", "libusbmuxd", "usbmuxd", "libgpod", "sg3_utils"],
        "desktop": ["hyprland", "xdg-desktop-portal-hyprland", "hyprlock", "hypridle", "hyprpaper", "aquamarine", "hyprlang", "hyprcursor", "hyprgraphics", "hyprutils", "hyprpolkitagent", "ddcui", "wlr-randr", "nwg-displays"],
        "hyprland": ["hyprland", "xdg-desktop-portal-hyprland", "hyprlock", "hypridle", "hyprpaper", "aquamarine", "hyprlang", "hyprcursor", "hyprgraphics", "hyprutils", "hyprpolkitagent", "ddcui", "wlr-randr", "nwg-displays"],
        "noctalia": ["noctalia", "hyprland", "xdg-desktop-portal-hyprland", "hyprlock", "hypridle", "hyprpaper", "aquamarine", "hyprlang", "hyprcursor", "hyprgraphics", "hyprutils", "hyprpolkitagent", "ddcui", "wlr-randr", "nwg-displays"],
        "all": [
            "python", "glib2", "sqlite", "openssl", "curl", "libxml2", "icu", "fmt", "onetbb",
            "gtk3", "gtk4", "libadwaita", "librsvg", "gdk-pixbuf2", "shared-mime-info", "adwaita-icon-theme", "hicolor-icon-theme", "qt5-base", "qt5-wayland", "qt5-svg", "qt6-base", "qt6-wayland", "qt6-declarative", "qt6-svg", "qt6-webengine", "wxwidgets-gtk3", "libnotify", "webkit2gtk-4.1", "libspnav", "libmanette", "breeze", "plasma-integration",
            "ffmpeg", "gstreamer", "gst-plugins-base", "gst-plugins-good", "sdl2", "libsamplerate", "libebur128", "taglib", "wavpack", "chromaprint",
            "openxr", "embree", "hwloc", "libsquish", "libwslay", "miniupnpc", "glm", "freeglut", "glew", "glfw", "openal",
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

    def install_profile(self, profile_name: str = "core", verbose: bool = True, output_dir: Optional[str] = None,
                        hooks: Optional[Dict[str, Any]] = None) -> Optional[Dict[str, Any]]:
        """Transmute and generate underpants-runtime-<profile> Slackware package."""
        self.engine.ensure_loaded()
        factory = TransmutationFactory(self.engine, output_dir=output_dir)
        if profile_name == "python":
            return factory.transmute("python", verbose=verbose, force=True, is_runtime=True)
        return factory.transmute_runtime_profile(profile_name, verbose=verbose, output_dir=output_dir, hooks=hooks)

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

        total_scanned = 0
        duplicates_linked = 0
        bytes_saved = 0
        skipped_owner = 0
        runtime_lib = os.path.join(self.RUNTIME_DIR, "lib")

        def _sha256(path: str) -> Optional[str]:
            h = hashlib.sha256()
            try:
                with open(path, "rb") as f:
                    while chunk := f.read(65536):
                        h.update(chunk)
                return h.hexdigest()
            except Exception:
                return None

        # 6A-261 (mirror of Rust src/gnomes/dedup.rs): regular, non-empty files only (links are skipped); candidates are
        # grouped by device and size first and hashed only when another file of that size exists.
        entries: Dict[Tuple[int, int], List[Dict[str, Any]]] = {}
        for sdir in scan_dirs:
            is_runtime = os.path.abspath(sdir) == os.path.abspath(runtime_lib)
            for root, _, files in os.walk(sdir):
                for fname in sorted(files):
                    fpath = os.path.join(root, fname)
                    try:
                        st = os.lstat(fpath)
                    except Exception:
                        continue
                    if not stat.S_ISREG(st.st_mode) or st.st_size == 0:
                        continue
                    total_scanned += 1
                    entries.setdefault((st.st_dev, st.st_size), []).append({
                        "path": fpath, "ino": st.st_ino, "uid": st.st_uid, "gid": st.st_gid,
                        "mode": stat.S_IMODE(st.st_mode), "runtime": is_runtime, "size": st.st_size})

        for (_dev, f_size), group in sorted(entries.items()):
            if len({e["ino"] for e in group}) < 2:
                continue  # one inode: already linked or alone
            by_hash: Dict[str, List[Dict[str, Any]]] = {}
            hashed: Dict[int, Optional[str]] = {}
            for e in group:
                if e["ino"] not in hashed:
                    hashed[e["ino"]] = _sha256(e["path"])
                if hashed[e["ino"]]:
                    by_hash.setdefault(hashed[e["ino"]], []).append(e)
            for same in by_hash.values():
                if len({e["ino"] for e in same}) < 2:
                    continue
                # the runtime copy is the one that is kept; otherwise the first path in scan order
                same.sort(key=lambda e: (not e["runtime"], e["path"]))
                keep = same[0]
                freed: Set[int] = set()
                for e in same[1:]:
                    if e["ino"] == keep["ino"]:
                        continue
                    if e["runtime"]:
                        continue  # a file of the runtime package is never relinked, not even between two runtime files
                    if (e["uid"], e["gid"], e["mode"]) != (keep["uid"], keep["gid"], keep["mode"]):
                        skipped_owner += 1  # a hardlink shares owner, group and mode: never link across a difference
                        continue
                    fpath = e["path"]
                    tmp_link = fpath + f".dedup_tmp_{os.getpid()}"
                    try:
                        os.link(keep["path"], tmp_link)
                        os.replace(tmp_link, fpath)
                        duplicates_linked += 1
                        if e["ino"] not in freed:
                            freed.add(e["ino"])
                            bytes_saved += f_size
                        if verbose:
                            rel_dup = os.path.relpath(fpath, "/opt/underpants")
                            rel_master = os.path.relpath(keep["path"], "/opt/underpants")
                            print(f"  \033[1;32m[link]\033[0m Hardlinked \033[1m{rel_dup}\033[0m -> \033[1;30m{rel_master}\033[0m [{f_size/(1024*1024):.2f} MB]")
                    except Exception:
                        try:
                            os.remove(tmp_link)
                        except OSError:
                            pass

        saved_mb = bytes_saved / (1024 * 1024)
        saved_gb = bytes_saved / (1024 * 1024 * 1024)
        human_str = f"{saved_gb:.2f} GB" if saved_gb >= 1.0 else f"{saved_mb:.2f} MB"

        if verbose:
            print(f"\n:: Deduplication Summary:")
            print(f"  • Files Scanned       : {total_scanned}")
            print(f"  • Duplicates Linked   : {duplicates_linked}")
            if skipped_owner:
                print(f"  • Left out (other owner or mode): {skipped_owner}")
            print(f"  • Disk Space Reclaimed: \033[1;32m{human_str}\033[0m\n")

        return {
            "files_scanned": total_scanned,
            "duplicates_linked": duplicates_linked,
            "bytes_saved": bytes_saved,
            "human_saved": human_str,
            "skipped_owner": skipped_owner
        }


# --- [ FOOTPRINT GUARD (roadmap 2A/2B/2C; mirror of Rust src/packages/footprint.rs, spec docs/footprint_spec.md) ] ---
# Keeps our packages from overwriting files owned by Slackware packages and from shipping global-effect
# files. Default mode is ENFORCE (owner decision 2026-10-11, after report mode would have shipped a
# /usr/bin/env wrapper): offending files are removed from the staging tree before packaging, and the
# package is not built if the check cannot run. SLACKY_FOOTPRINT_MODE=report only lists them.
# 6A-6c: safe removal of a gnomes-service block (literal begin/end marker lines) for package douninst scripts.
GNOMES_RC_REMOVE_SH = r'''gnomes_rc_remove() { # FILE BEGIN END
  g_f=$(readlink -f "$1") || return 0; g_b=$2; g_e=$3
  [ -f "$g_f" ] || return 0
  grep -qxF "$g_b" "$g_f" || return 0
  [ "$(grep -cxF "$g_b" "$g_f")" = "$(grep -cxF "$g_e" "$g_f")" ] || { echo "gnomes: unbalanced markers in $g_f, left unchanged" >&2; return 1; }
  [ -z "$(sh -n "$g_f" 2>&1)" ] || { echo "gnomes: $g_f has a syntax error, left unchanged" >&2; return 1; }
  g_t=$(mktemp "$g_f.gnomes.XXXXXX") || return 1
  cp -p "$g_f" "$g_t" || { rm -f "$g_t"; return 1; }
  awk -v b="$g_b" -v e="$g_e" 'skip { if ($0 == e) skip=0; next } $0 == b { skip=1; next } { print }' "$g_f" >"$g_t"
  if [ -z "$(sh -n "$g_t" 2>&1)" ] && ! grep -qxF "$g_b" "$g_t"; then cp -p "$g_f" "$g_f.slacky-bak" && mv -f "$g_t" "$g_f"
  else rm -f "$g_t"; echo "gnomes: result would be invalid, $g_f unchanged" >&2; return 1; fi
}'''

# 6A-35: download watchdog. A mirror that delivers less than DL_STALL_MIN_BYTES within DL_STALL_WINDOW seconds is
# abandoned for the next one (one easyeffects build hung > 25 min without output on a trickling connection).
DL_STALL_WINDOW = 60
DL_STALL_MIN_BYTES = 32 * 1024


def copy_response_with_watchdog(resp, fobj, label: str = "") -> int:
    """6A-35: copy an HTTP response body to fobj, abandoning a stalled transfer (see DL_STALL_WINDOW)."""
    read_some = getattr(resp, "read1", resp.read)
    total = 0
    mark_t, mark_b = time.time(), 0
    while True:
        chunk = read_some(65536)
        if not chunk:
            return total
        fobj.write(chunk)
        total += len(chunk)
        now = time.time()
        if now - mark_t >= DL_STALL_WINDOW:
            if total - mark_b < DL_STALL_MIN_BYTES:
                raise TimeoutError(f"download stalled: {label}")
            mark_t, mark_b = now, total

# 6A-20: share subdirs never mirrored to the host /usr/share. Build-only data (no app reads it at run time) and
# config that the host sound stack, portal service or OpenXR loader would pick up (never "vulkan": gamescope needs its
# WSI layer there). The app keeps them in APP_ROOT/share via XDG_DATA_DIRS.
HOST_SHARE_SKIP = frozenset({
    "aclocal", "cmake", "pkgconfig", "gir-1.0", "vala", "vala-0.56", "glade", "gettext", "devhelp",
    "kdevappwizard", "qlogging-categories5", "qlogging-categories6", "lv2specgen", "PySide6", "PySide2",
    "xdp-tools", "perl5", "libalpm", "systemd",
    "pipewire", "wireplumber", "alsa-card-profile", "xdg-desktop-portal", "openxr",
})

# 6A-12: apps that start games (often 32-bit Wine/Proton); their wrappers do not set ALSA_PLUGIN_DIR.
GAME_LAUNCHER_APPS = frozenset({
    "faugus-launcher", "lutris", "heroic-games-launcher", "heroic-games-launcher-bin", "bottles", "steam",
    "protonplus", "protonup-qt", "umu-launcher", "gamescope", "minigalaxy", "itch", "itch-setup-bin",
})

FOOTPRINT_PKGDB = "/var/lib/pkgtools/packages"
FOOTPRINT_SCRIPTS = "/var/lib/pkgtools/scripts"
FOOTPRINT_OWN_PREFIXES = ("underpants-", "cachyos-")
FOOTPRINT_VETTED = {
    "etc/cron.hourly/suse.de-snapper",
    "etc/cron.hourly/snapper-cleanup", "etc/cron.hourly/snapper-cleanup.new",
    "etc/cron.hourly/snapper-timeline", "etc/cron.hourly/snapper-timeline.new",
    "etc/profile.d/nvidia-vaapi.sh", "etc/profile.d/nvidia-vaapi.csh",
    "etc/profile.d/rocm.sh", "etc/profile.d/rocm.csh",
    "etc/ld.so.conf.d/rocm.conf",
    # our own app's files
    "etc/cron.hourly/slacky-snapper-limine-sync",
    "etc/cron.weekly/slacky-update-check",
    "etc/profile.d/slacky-hidpi.sh", "etc/profile.d/slacky-hidpi.csh",
}
FOOTPRINT_OWN_DAEMONS = {
    "rc.lact", "rc.scx", "rc.ananicy-cpp", "rc.gamemode", "rc.coolercontrol", "rc.asusd",
    "rc.syncthing", "rc.spacenavd", "rc.dmemcg-booster",
}
_FOOTPRINT_LINK_RE = re.compile(r"\(\s*cd\s+(\S+)\s*;\s*ln\s+-sf\s+(\S+)\s+(\S+)\s*\)")


def gnomes_rc_hook_snippet(svc: str) -> str:
    """Shell text for a package doinst.sh: add the start/stop block of service `svc` to rc.local and rc.local_shutdown.
    6A-291 (M12): the marker is matched as an exact fixed line (grep -qxF), so running it twice leaves ONE block; blocks
    an older version piled up (same marker, several times) are collapsed to the first one."""
    begin = f"# --- [ gnomes-service: {svc} ] ---"
    end = f"# --- [ /gnomes-service: {svc} ] ---"
    dedupe = f"""  if [ "$(grep -cxF -- '{begin}' "$GNOMES_RCF" 2>/dev/null)" -gt 1 ]; then
    GNOMES_RCT="$(mktemp "$GNOMES_RCF.XXXXXX" 2>/dev/null)" && \\
    awk -v b='{begin}' -v e='{end}' '
      $0 == b {{ if (seen) {{ skip = 1; pend = ""; next }} seen = 1 }}
      skip {{ if ($0 == e) skip = 0; next }}
      $0 == "" {{ pend = pend "\\n"; next }}
      {{ if (pend != "") {{ printf "%s", pend; pend = "" }} print }}
    ' "$GNOMES_RCF" > "$GNOMES_RCT" && cat "$GNOMES_RCT" > "$GNOMES_RCF"
    rm -f "$GNOMES_RCT" 2>/dev/null
  fi
"""
    return f"""
# --- [ Boot & Shutdown Service Integration: {svc} ] ---
if [ -f /etc/rc.d/rc.local ]; then
  GNOMES_RCF=/etc/rc.d/rc.local
  if ! grep -qxF -- '{begin}' /etc/rc.d/rc.local 2>/dev/null; then
    cat << 'EOF_RCLOCAL_{svc}' >> /etc/rc.d/rc.local

{begin}
if [ -x /etc/rc.d/rc.{svc} ]; then
  /etc/rc.d/rc.{svc} start
fi
{end}
EOF_RCLOCAL_{svc}
  fi
{dedupe}fi

if [ ! -f /etc/rc.d/rc.local_shutdown ]; then
  touch /etc/rc.d/rc.local_shutdown 2>/dev/null || true
  chmod 755 /etc/rc.d/rc.local_shutdown 2>/dev/null || true
fi

if [ -f /etc/rc.d/rc.local_shutdown ]; then
  GNOMES_RCF=/etc/rc.d/rc.local_shutdown
  if ! grep -qxF -- '{begin}' /etc/rc.d/rc.local_shutdown 2>/dev/null; then
    cat << 'EOF_RCSHUTDOWN_{svc}' >> /etc/rc.d/rc.local_shutdown

{begin}
if [ -x /etc/rc.d/rc.{svc} ]; then
  /etc/rc.d/rc.{svc} stop
fi
{end}
EOF_RCSHUTDOWN_{svc}
  fi
{dedupe}fi
"""


def footprint_is_own_package(name: str) -> bool:
    return name.startswith(FOOTPRINT_OWN_PREFIXES) or name.endswith("_slacky") or name.endswith("_gnomes")


def footprint_load_owners(pkgdb: str = FOOTPRINT_PKGDB, scripts: str = FOOTPRINT_SCRIPTS) -> Dict[str, str]:
    """Relative path -> owning Slackware package (file lists + doinst.sh symlinks). Read-only."""
    owners: Dict[str, str] = {}
    for name in os.listdir(pkgdb):  # raises if the pkgdb is missing: callers fail closed in enforce mode
        if footprint_is_own_package(name):
            continue
        try:
            with open(os.path.join(pkgdb, name), errors="replace") as fh:
                in_list = False
                for line in fh:
                    if in_list:
                        rel = line.strip()
                        if rel and rel != "./" and not rel.endswith("/") and not rel.startswith("install/"):
                            owners.setdefault(rel, name)
                            # 6A-29: Slackware ships config files as X.new (doinst config() installs X); X is theirs too
                            if rel.endswith(".new"):
                                owners.setdefault(rel[:-4], name + " (config file)")
                    elif line.startswith("FILE LIST:"):
                        in_list = True
        except OSError:
            continue
    if os.path.isdir(scripts):
        for name in os.listdir(scripts):
            if footprint_is_own_package(name):
                continue
            try:
                with open(os.path.join(scripts, name), errors="replace") as fh:
                    text = fh.read()
            except OSError:
                continue
            for d, _target, link in _FOOTPRINT_LINK_RE.findall(text):
                owners.setdefault(os.path.normpath(d + "/" + link), name + " (doinst symlink)")
    return owners


def footprint_judge(rel: str, owners: Dict[str, str]) -> Optional[str]:
    """None = keep, otherwise the reason the file must not ship."""
    rel = rel[2:] if rel.startswith("./") else rel
    if rel.startswith("install/"):
        return None
    if rel not in FOOTPRINT_VETTED:
        if rel.startswith("etc/ld.so.conf.d/"):
            return "changes the system-wide linker search path"
        if rel.startswith("etc/cron."):
            return "installs a root cron job"
        if rel.startswith("etc/profile.d/"):
            return "changes the login environment for every user"
        if rel.startswith("etc/rc.d/rc."):
            base = os.path.basename(rel)
            base = base[:-4] if base.endswith(".new") else base
            if base not in FOOTPRINT_OWN_DAEMONS:
                return "service script from a dependency"
    if rel in owners:
        return "owned by Slackware package " + owners[rel]
    return None


def footprint_guard(staging: str, label: str = "", enforce: Optional[bool] = None,
                    owners: Optional[Dict[str, str]] = None, quiet: bool = False) -> Dict[str, Any]:
    """Scans (and in enforce mode cleans) a package staging tree. Only files and symlinks are judged."""
    if enforce is None:
        enforce = os.environ.get("SLACKY_FOOTPRINT_MODE", "enforce").strip().lower() != "report"
    if owners is None:
        owners = footprint_load_owners()
    staging = os.path.abspath(staging)
    drops: List[Tuple[str, str]] = []
    for root, dirs, files in os.walk(staging):
        for name in files + [d for d in dirs if os.path.islink(os.path.join(root, d))]:
            full = os.path.join(root, name)
            rel = os.path.relpath(full, staging)
            reason = footprint_judge(rel, owners)
            if reason:
                drops.append((rel, reason))
    if enforce:
        for rel, _ in drops:
            target = os.path.join(staging, rel)
            if os.path.commonpath([staging, os.path.abspath(target)]) != staging:
                continue  # hard guard: never outside the staging tree
            try:
                os.unlink(target)
            except OSError:
                pass
    details = ""
    if drops:
        cache = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
        out_dir = os.path.join(cache, "slacky-update", "footprint")
        try:
            os.makedirs(out_dir, exist_ok=True)
            details = os.path.join(out_dir, (label or os.path.basename(staging)) + ".txt")
            with open(details, "w") as fh:
                for rel, reason in drops:
                    fh.write(f"{rel}\t{reason}\n")
        except OSError:
            details = ""
        if not quiet:
            mode = "removed" if enforce else "would be removed (report only)"
            where = f" Details: {details}" if details else ""
            print(f":: Footprint check: {len(drops)} file(s) in {label or staging} {mode}.{where}")
    return {"enforce": enforce, "drops": drops, "details": details}


def footprint_archive_non_root(txz: str) -> List[str]:
    """2C: archive entries not owned by root:root (empty list = safe to install)."""
    bad: List[str] = []
    with tarfile.open(txz, "r:*") as tf:
        for m in tf:
            if m.uid != 0 or m.gid != 0:
                bad.append(m.name)
    return bad


def footprint_pkg_base(pkgid: str) -> str:
    """name-version-arch-build -> name (Slackware package id or archive file name)."""
    for ext in (".txz", ".tgz", ".tbz", ".tlz"):
        if pkgid.endswith(ext):
            pkgid = pkgid[: -len(ext)]
    parts = pkgid.split("-")
    return "-".join(parts[:-3]) if len(parts) > 3 else pkgid


def host_path_owners(pkgdb: str = FOOTPRINT_PKGDB, scripts: str = FOOTPRINT_SCRIPTS,
                     keep=None, wanted: Optional[Set[str]] = None) -> Dict[str, List[str]]:
    """WP-1: host path -> every installed package that owns it (file lists, .new config twins, doinst symlinks).
    Unlike footprint_load_owners it includes our own packages; keep(pkgid) -> bool selects which packages count;
    wanted limits the result to those paths (fast path for one archive)."""
    owners: Dict[str, List[str]] = {}

    def add(rel: str, pkg: str) -> None:
        if wanted is not None and rel not in wanted:
            return
        lst = owners.setdefault(rel, [])
        if pkg not in lst:
            lst.append(pkg)

    wanted_b = None
    if wanted is not None:
        wanted_b = set()
        for w in wanted:
            wanted_b.add(w.encode("utf-8", "surrogateescape"))
            wanted_b.add((w + ".new").encode("utf-8", "surrogateescape"))
    for name in os.listdir(pkgdb):  # raises if the pkgdb is missing: the caller refuses (fail closed)
        if keep is not None and not keep(name):
            continue
        try:
            if wanted_b is not None:
                # fast path: one C-level set intersection per package instead of a Python loop over 2M+ lines
                with open(os.path.join(pkgdb, name), "rb") as fh:
                    data = fh.read()
                i = data.find(b"\nFILE LIST:\n")
                if i < 0:
                    continue
                for hit in wanted_b.intersection(data[i + 12:].split(b"\n")):
                    rel = hit.decode("utf-8", "surrogateescape")
                    add(rel, name)
                    if rel.endswith(".new"):
                        add(rel[:-4], name)
                continue
            with open(os.path.join(pkgdb, name), errors="replace") as fh:
                in_list = False
                for line in fh:
                    if in_list:
                        rel = line.strip()
                        if rel and rel != "./" and not rel.endswith("/") and not rel.startswith("install/"):
                            add(rel, name)
                            if rel.endswith(".new"):
                                add(rel[:-4], name)
                    elif line.startswith("FILE LIST:"):
                        in_list = True
        except OSError:
            continue
    if os.path.isdir(scripts):
        for name in os.listdir(scripts):
            if keep is not None and not keep(name):
                continue
            try:
                with open(os.path.join(scripts, name), errors="replace") as fh:
                    text = fh.read()
            except OSError:
                continue
            for d, _target, link in _FOOTPRINT_LINK_RE.findall(text):
                add(os.path.normpath(d + "/" + link), name)
    return owners


VULKAN_IMPLICIT_LAYER_DIR = "usr/share/vulkan/implicit_layer.d/"
# Shared on purpose: licence texts of bundled libraries (several apps ship the same file; removepkg keeps a file
# another package still owns, and the text is never executed or read by programs).
HOST_PATH_SHAREABLE = ("usr/share/licenses/",)


def archive_host_paths(txz: str) -> List[str]:
    """Host paths an archive would create: files and symlinks outside opt/underpants/ and install/, plus the
    symlinks its doinst.sh makes. Directories are shared by design and not listed."""
    paths: List[str] = []
    with tarfile.open(txz, "r:*") as tf:
        for m in tf:
            rel = m.name[2:] if m.name.startswith("./") else m.name
            rel = rel.rstrip("/")
            if not rel or m.isdir():
                continue
            if rel == "install/doinst.sh":
                fh = tf.extractfile(m)
                if fh is not None:
                    text = fh.read().decode("utf-8", "replace")
                    for d, _target, link in _FOOTPRINT_LINK_RE.findall(text):
                        lp = os.path.normpath(d + "/" + link)
                        if not lp.startswith("opt/underpants/"):
                            paths.append(lp)
                continue
            if rel.startswith("install/") or rel.startswith("opt/underpants/"):
                continue
            paths.append(rel)
    return paths


def vulkan_layer_enable_env(txz: str, rel: str) -> str:
    """6A-374: "VAR=value" from the layer JSON's enable_environment inside the package archive, or "" when unknown."""
    try:
        import tarfile, json as _json
        with tarfile.open(txz) as tf:
            for name in (rel, "./" + rel):
                try:
                    member = tf.getmember(name)
                except KeyError:
                    continue
                fh = tf.extractfile(member)
                if fh is None:
                    return ""
                data = _json.loads(fh.read(1 << 20).decode("utf-8", "replace"))
                layer = data.get("layer") or {}
                env = layer.get("enable_environment") or {}
                if isinstance(env, dict) and env:
                    k, v = next(iter(env.items()))
                    return f"{k}={v}"
                return ""
    except Exception:
        return ""
    return ""


def verify_host_paths(txz: str, mode: str = "gnomes", pkgdb: str = FOOTPRINT_PKGDB,
                      scripts: str = FOOTPRINT_SCRIPTS) -> Dict[str, Any]:
    """WP-1 install-time guard. mode "gnomes": no host path may belong to another package (Slackware, curated, other
    gnomes); a curated package with the same name is never replaced by a gnomes build (curated wins).
    mode "curated": no host path may belong to a gnomes package with another name.
    The installed package with the same name (the one being replaced) is always allowed."""
    base = footprint_pkg_base(os.path.basename(txz))
    installed = [n for n in os.listdir(pkgdb) if footprint_pkg_base(n) == base]
    refusals: List[str] = []
    warnings: List[str] = []
    if mode == "gnomes":
        for n in installed:
            if not n.endswith("_gnomes"):
                refusals.append(f"{base} is already installed as {n}, which slacky-update looks after, so gnomes "
                                f"will not replace it. Update it with slacky-update instead.")

        def keep(n: str) -> bool:
            return footprint_pkg_base(n) != base
    else:
        def keep(n: str) -> bool:
            return n.endswith("_gnomes") and footprint_pkg_base(n) != base
    paths = [p for p in archive_host_paths(txz) if not p.startswith(HOST_PATH_SHAREABLE)]
    wanted = set(paths) | {p[:-4] for p in paths if p.endswith(".new")}
    owners = host_path_owners(pkgdb, scripts, keep, wanted)
    clash: Dict[str, List[str]] = {}
    for rel in paths:
        hits = list(owners.get(rel, []))
        if rel.endswith(".new"):
            hits += [o for o in owners.get(rel[:-4], []) if o not in hits]
        for o in hits:
            clash.setdefault(o, []).append(rel)
        if not hits and rel.startswith(VULKAN_IMPLICIT_LAYER_DIR):
            # 6A-374: an implicit layer with "enable_environment" is only loaded when that variable is set
            cond = vulkan_layer_enable_env(txz, rel)
            if cond:
                warnings.append(f"{rel} adds a Vulkan layer that is only active when {cond} is set "
                                f"(the program that needs it sets this itself).")
            else:
                warnings.append(f"{rel} adds a Vulkan layer that every game and Vulkan program will load.")
    for owner, rels in sorted(clash.items()):
        if owner.endswith("_gnomes"):
            fix = f"Remove that app first with: gnomes -R {footprint_pkg_base(owner).replace('underpants-', '', 1)}"
        elif owner.endswith("_slacky") or footprint_is_own_package(owner):
            fix = "That package is looked after by slacky-update."
        else:
            fix = "Files that belong to Slackware are never replaced."
        refusals.append(f"{len(rels)} file(s) already belong to {owner} (for example /{rels[0]}). {fix}")
    return {"package": os.path.basename(txz), "refusals": refusals, "warnings": warnings}


# --- [ WP-2: ROLLBACK FROM SNAPSHOTS ] ---
# Owner decision 2026-10-13: no second copy of every package (about 12 GB on the owner's machine). The previous version
# of an app is rebuilt from the newest Btrfs/snapper snapshot that still has it; /opt, /usr and /var/lib are inside the
# root snapshot, /boot is not, so kernels are refused automatically (their files are missing from the snapshot).
SNAPSHOT_DIR = "/.snapshots"
ROLLBACK_HOLDS = os.path.join(DEFAULT_CACHE_BASE, "rollback-holds.json")


def _snapshot_info(snapdir: str, num: int) -> Dict[str, str]:
    info = {"date": "", "description": ""}
    try:
        with open(os.path.join(snapdir, str(num), "info.xml"), errors="replace") as fh:
            text = fh.read()
        for key in info:
            m = re.search(rf"<{key}>(.*?)</{key}>", text, re.S)
            if m:
                info[key] = m.group(1).strip()
    except OSError:
        pass
    return info


# 6A-262: a .part file younger than this may belong to a running download (kept even by clean --all)
CLEAN_PART_GRACE = 10 * 60
# 6A-262: build folders younger than 30 minutes are never removed; the D14 rule in clean_cache keeps them 6 hours (stricter)


# Boot chain: rolling back only the package would leave the ESP, initramfs or signatures out of step with it. These go
# back with the whole system (the snapshot entries in the Limine menu), never one package at a time.
ROLLBACK_REFUSED = ("limine", "sbctl", "snapper", "kernel", "nvidia", "linux-cachyos", "dkms", "grub", "shim")


def rollback_refusal(base: str) -> Optional[str]:
    # 6A-260: prefixes only (str.replace also cut a "cachyos-" out of the middle, so "linux-cachyos-bore" slipped through)
    short = base
    for pre in ("underpants-", "cachyos-gnome-", "cachyos-"):
        if short.startswith(pre):
            short = short[len(pre):]
    if any(short == r or short.startswith(r + "-") or short.startswith(r) and r in ("kernel", "nvidia", "linux-cachyos")
           for r in ROLLBACK_REFUSED):
        return (f"{base} is part of the boot chain, so it is never rolled back on its own. Boot the snapshot entry "
                f"from the Limine menu instead, or let slacky-update install the next version.")
    return None


def _rollback_aliases(base: str) -> Set[str]:
    """Same app under the names it had before a rename (cachyos-gnome-X became underpants-X)."""
    short = base
    for pre in ("underpants-", "cachyos-gnome-"):
        if short.startswith(pre):
            short = short[len(pre):]
    return {base, "underpants-" + short, "cachyos-gnome-" + short}


def rollback_candidates(base: str, snapdir: str = SNAPSHOT_DIR, pkgdb: str = FOOTPRINT_PKGDB) -> Tuple[Optional[str], List[Dict[str, Any]]]:
    """(installed package id, snapshots holding another version of the same package, newest first). Only the same kind
    of build counts: a curated package never goes back to a gnomes build of the same app, or the other way round."""
    current = next((n for n in sorted(os.listdir(pkgdb)) if footprint_pkg_base(n) == base), None)
    found: List[Dict[str, Any]] = []
    if current is None:
        return current, found
    names = _rollback_aliases(base)
    gnomes_kind = current.endswith("_gnomes")
    try:
        nums = sorted((int(d) for d in os.listdir(snapdir) if d.isdigit()), reverse=True)
    except OSError:
        return current, found
    for num in nums:
        root = os.path.join(snapdir, str(num), "snapshot")
        try:
            ids = [n for n in os.listdir(os.path.join(root, "var/lib/pkgtools/packages"))
                   if footprint_pkg_base(n) in names and n.endswith("_gnomes") == gnomes_kind]
        except OSError:
            continue
        for pid in ids:
            if pid != current:
                found.append({"snapshot": num, "pkgid": pid, "root": root, **_snapshot_info(snapdir, num)})
    return current, found


def build_from_snapshot(cand: Dict[str, Any], out_dir: str, owners: Optional[Dict[str, str]] = None) -> str:
    """Rebuild the package cand["pkgid"] exactly as the snapshot has it installed: its FILE LIST, its doinst/douninst
    scripts and description; everything root:root. Raises ValueError with one plain sentence when that is not possible."""
    pid, root = cand["pkgid"], cand["root"]
    if not footprint_is_own_package(pid):
        raise ValueError(f"{pid} is not a slacky-update or gnomes package; Slackware's own packages are rolled back with slackpkg.")
    with open(os.path.join(root, "var/lib/pkgtools/packages", pid), errors="replace") as fh:
        lines = fh.read().splitlines()
    try:
        fl = lines.index("FILE LIST:")
    except ValueError:
        raise ValueError(f"The snapshot's record of {pid} has no file list.")
    desc: List[str] = []
    if "PACKAGE DESCRIPTION:" in lines:
        desc = [l for l in lines[lines.index("PACKAGE DESCRIPTION:") + 1:fl] if l.strip()]
    # var/lib/pkgtools/... entries (the registered douninst.sh) are recreated by installpkg itself, never shipped
    entries = [e for e in lines[fl + 1:] if e and e != "./" and not e.startswith("install/") and e != "install"
               and not e.startswith("var/lib/pkgtools/")]
    # 6A-292 (M11): the same footprint guard as for a fresh build: a file that now belongs to a Slackware package, or that
    # changes the whole system (linker path, login environment, root cron job, foreign service script), is not put back.
    # The snapshot itself is only read, never changed. Report mode (SLACKY_FOOTPRINT_MODE=report) keeps every file.
    if owners is None:
        owners = footprint_load_owners()  # raises when the package database is missing: the rollback then stops
    if os.environ.get("SLACKY_FOOTPRINT_MODE", "enforce").strip().lower() != "report":
        dropped = [e for e in entries if not e.endswith("/") and footprint_judge(e, owners)]
        if dropped:
            gone = set(dropped)
            entries = [e for e in entries if e not in gone]
            print(f":: Footprint check: {len(dropped)} file(s) of {pid} were not put back because they belong to "
                  f"Slackware or change the whole system (for example /{dropped[0]}).", file=sys.stderr)
    missing = [e for e in entries if not e.endswith("/") and not os.path.lexists(os.path.join(root, e))]
    if missing:
        raise ValueError(f"The snapshot does not hold all files of {pid} ({len(missing)} missing, for example /{missing[0]}).")
    os.makedirs(out_dir, exist_ok=True)
    inst = os.path.join(out_dir, "meta")
    os.makedirs(os.path.join(inst, "install"), exist_ok=True)
    with open(os.path.join(inst, "install", "slack-desc"), "w") as fh:
        fh.write("\n".join(desc) + "\n")
    meta = ["install", "install/slack-desc"]
    for src, name in (("var/lib/pkgtools/scripts", "doinst.sh"), ("var/lib/pkgtools/douninst.sh", "douninst.sh")):
        sp = os.path.join(root, src, pid)
        if os.path.isfile(sp):
            shutil.copyfile(sp, os.path.join(inst, "install", name))
            os.chmod(os.path.join(inst, "install", name), 0o755)
            meta.append("install/" + name)
    listf = os.path.join(out_dir, "files.list")
    with open(listf, "w") as fh:
        fh.write(".\n" + "\n".join(e.rstrip("/") for e in entries) + "\n")
    tar_path = os.path.join(out_dir, pid + ".tar")
    common = ["tar", "--owner=0", "--group=0", "--numeric-owner", "--no-recursion", "--verbatim-files-from"]
    subprocess.run(common + ["-C", root, "-T", listf, "-cf", tar_path], check=True)
    subprocess.run(common + ["-C", inst, "-rf", tar_path] + meta, check=True)
    subprocess.run(["xz", "-T0", "-1", "-f", tar_path], check=True)
    txz = os.path.join(out_dir, pid + ".txz")
    os.replace(tar_path + ".xz", txz)
    return txz


def load_rollback_holds(path: str = ROLLBACK_HOLDS) -> Dict[str, Dict[str, str]]:
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        return {k: v for k, v in data.items() if isinstance(v, dict)}
    except (OSError, ValueError):
        return {}


def record_rollback_hold(base: str, skip_version: str, path: str = ROLLBACK_HOLDS) -> None:
    """The version rolled back from is not offered again; any newer release is (the hold then ends by itself)."""
    data = load_rollback_holds(path)
    data[base] = {"skip_version": skip_version, "since": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)


# --- [ CLI INTERACTION INTERFACE ] ---


# --- [ 7J-7N: SHARED RUNTIME MONTHLY REFRESH (docs/runtime_refresh_spec.md) ] ---

def rr_paths() -> Tuple[str, str]:
    """(live runtime dir, apps dir). SLACKY_RR_ROOT moves both below a fake root, honoured only with SLACKY_SELFTEST=1."""
    pre = os.environ.get("SLACKY_RR_ROOT", "") if os.environ.get("SLACKY_SELFTEST") == "1" else ""
    return pre + RuntimeManager.RUNTIME_DIR, pre + RuntimeManager.PKGS_DIR


def runtime_refresh_status(record: bool = True) -> Dict[str, Any]:
    """7J: read-only detection (spec 3). Uses only the repository databases already in the cache (nothing is downloaded), the
    live manifest and the state file. Returns the status key (spec 8.2) plus offering details. Never raises."""
    rr = refresh_module()
    base: Dict[str, Any] = {"state": "unknown", "age_days": 0, "newer": 0, "checked": 0, "gone": 0, "suspects": [],
                            "built": "", "checked_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                            "offerable": False, "candidate_basis": "", "apps_basis": "", "profile": "", "size_hint": ""}
    if rr is None:
        return base
    try:
        live, _pkgs = rr_paths()
        manifest, mtime, _why = rr.read_manifest(live)
        now = rr.now_ts()
        repo_versions: Dict[str, str] = {}
        idx_file = os.environ.get("SLACKY_RR_INDEX", "") if os.environ.get("SLACKY_SELFTEST") == "1" else ""
        if idx_file:
            with open(idx_file, "r", encoding="utf-8") as fh:
                repo_versions = {str(k): str(v) for k, v in json.load(fh).items()}
        elif manifest is not None:
            def _newest_db(basedir: str) -> Optional[float]:
                d = os.path.join(basedir, "db")
                try:
                    ts = [os.stat(os.path.join(d, n)).st_mtime for n in os.listdir(d) if n.endswith((".db.tar.zst", ".db.tar.gz"))]
                except OSError:
                    return None
                return max(ts) if ts else None
            sys_t, user_t = _newest_db(DEFAULT_CACHE_BASE), _newest_db(USER_CACHE_BASE)
            if sys_t is not None or user_t is not None:
                use = DEFAULT_CACHE_BASE if (sys_t is not None and (user_t is None or sys_t >= user_t)) else USER_CACHE_BASE
                eng = GnomesPacmanEngine(cache_dir=use)
                eng.load_cached_databases()
                repo_versions = {n: str(p.get("VERSION", "")) for n, p in eng.index.items()}
        pre = os.environ.get("SLACKY_RR_ROOT", "") if os.environ.get("SLACKY_SELFTEST") == "1" else ""
        pkgdb = pre + rr.PKGDB
        res = rr.detect(manifest, mtime, repo_versions, GnomesPacmanEngine.is_newer_version, now,
                        set(RuntimeManager.PROFILES.keys()), runtime_dir=live, pkgdb=pkgdb)
        newest = res.pop("newest", {})
        clock_future = bool(res.pop("clock_future", False))
        res["candidate_basis"] = rr.candidate_basis(newest)
        res["apps_basis"] = rr.apps_basis(pkgdb)
        res["profile"] = str(manifest.get("profile", "")) if manifest else ""
        state = res["state"]
        if state in ("due", "due_now"):
            st, why = rr.state_read()
            eff = rr.state_effective(st, res["built"])
            sup = rr.suppression(eff, res["candidate_basis"], res["apps_basis"], now)
            if record:
                if why:
                    rr.rr_log("RR-STATE-IGNORED", why, throttle_daily=True)
                rr.rr_log("RR-DUE-NOW" if state == "due_now" else "RR-DUE",
                          f"age={res['age_days']}d newer={res['newer']} suspects={'; '.join(res['suspects']) or '-'}",
                          throttle_daily=True)
                if sup == "remembered_veto":
                    rr.rr_log("RR-VETO-REMEMBERED", f"app={eff['veto'].get('app', '')}", throttle_daily=True)
            if sup:
                res["state"] = sup
            res["offerable"] = not sup
            res["size_hint"] = rr.size_hint(res["profile"], pkgdb)
        if clock_future and record:
            rr.rr_log("RR-CLOCK", "runtime build time is in the future; age counted as 0", throttle_daily=True)
        return res
    except Exception as e:  # never break the check
        base["error"] = type(e).__name__
        return base


def rr_hooks_for(profile_check: bool, pkgs_dir: str, live_dir: str, outcome: Dict[str, Any], staged: Tuple[str, ...] = (),
                 with_space: bool = True) -> Dict[str, Any]:
    """Build the {space, check} hooks of transmute_runtime_profile. Details are left in `outcome` for the caller."""
    rr, sv = refresh_module(), symver_module()
    hooks: Dict[str, Any] = {}
    if rr is not None and with_space:
        def space_hook(s_bytes: int, c_bytes: int, c_missing: int) -> Optional[str]:
            res = rr.space_plan(s_bytes, c_bytes, c_missing, build_dir_base())
            outcome["space"] = res
            return None if res["ok"] else "no space"
        hooks["space"] = space_hook
    if profile_check:
        def check_hook(staged_runtime: str) -> Optional[str]:
            if sv is None:
                outcome["check_missing"] = True
                return "the startability checker is missing"
            res = sv.run_startcheck(staged_runtime, live_dir, pkgs_dir, staged)
            outcome["check"] = res
            if rr is not None:
                rr.rr_log("RR-CHECK-TIME", f"seconds={res['seconds']} apps={res['apps']} programs={res['programs']} files={res['files']}")
                if res.get("plugins_unchecked"):
                    rr.rr_log("RR-PLUGINS-UNCHECKED", f"count={res['plugins_unchecked']}")
                if res["veto"] and rr is not None:
                    rr.rr_log("RR-VETO", f"count={len(res['new'])} " + "; ".join("|".join(x) for x in res["new"][:50]))
            return f"{res['first_app']} would not start" if res["veto"] else None
        hooks["check"] = check_hook
    return hooks


def runtime_refresh_build(engine: "GnomesPacmanEngine", out_dir: str) -> int:
    """7N user phase (spec 5.3): build the candidate, check it, package it, keep the staging tree. Writes <out_dir>/result.json.
    Exit 0 = a package is ready or the refresh was skipped on purpose; 1 = nothing to install (the reason is in result.json)."""
    rr = refresh_module()
    live, pkgs = rr_paths()
    result: Dict[str, Any] = {"state": "build_failed", "txz": "", "sha256": "", "staging_base": "", "old_built": "", "new_built": "",
                              "app": "", "rule": "", "detail": "", "candidate_basis": "", "apps_basis": "", "packages": 0, "baseline": []}

    def finish(code: int) -> int:
        try:
            os.makedirs(out_dir, mode=0o700, exist_ok=True)
            with open(os.path.join(out_dir, "result.json"), "w", encoding="utf-8") as fh:
                json.dump(result, fh)
        except OSError:
            pass
        return code
    if rr is None:
        result["detail"] = "slacky_runtime_refresh.py is missing"
        return finish(1)
    manifest, _mt, why = rr.read_manifest(live)
    if manifest is None or manifest.get("profile") not in RuntimeManager.PROFILES:
        result["state"], result["detail"] = "skipped", f"runtime manifest not usable ({why})"
        return finish(0)
    profile = str(manifest["profile"])
    result["old_built"] = str(manifest.get("built", ""))
    engine.ensure_loaded()
    # the databases are fresh now: the remembered-veto rule uses the same basis as the plan
    st = runtime_refresh_status(record=False)
    result["candidate_basis"], result["apps_basis"] = st.get("candidate_basis", ""), st.get("apps_basis", "")
    if st.get("state") == "remembered_veto":
        rr.rr_log("RR-VETO-REMEMBERED", "build skipped")
        result["state"] = "skipped"
        result["detail"] = "remembered veto"
        return finish(0)
    factory = TransmutationFactory(engine, output_dir=out_dir)
    outcome: Dict[str, Any] = {}
    hooks = rr_hooks_for(True, pkgs, live, outcome)
    t0 = time.time()
    res = factory.transmute_runtime_profile(profile, verbose=False, output_dir=out_dir, keep_staging=True, hooks=hooks)
    kind = getattr(factory, "outcome", {}).get("kind", "build_failed")
    if res is None:
        if kind == "no_space":
            sp = outcome.get("space", {})
            result.update(state="no_space", detail=json.dumps(sp))
            rr.rr_log("RR-SPACE", f"need={sp.get('need')} free={sp.get('free')} path={sp.get('path')} same_fs={'yes' if sp.get('same_fs') else 'no'}")
        elif kind == "vetoed":
            chk = outcome.get("check", {})
            first = chk.get("new", [[]])[0] if chk.get("new") else []
            result.update(state="vetoed", app=chk.get("first_app", ""), rule=first[1] if len(first) > 1 else "",
                          detail="|".join(first), baseline=chk.get("baseline", []))
        else:
            result.update(state="build_failed", detail="check missing" if outcome.get("check_missing") else "build failed")
            rr.rr_log("RR-BUILD-FAIL", result["detail"])
        return finish(1)
    chk = outcome.get("check", {})
    txz = res["txz_path"]
    h = hashlib.sha256()
    with open(txz, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    nm, _mt2, _w2 = rr.read_manifest(res["staging_runtime"])
    result.update(state="built", txz=txz, sha256=h.hexdigest(), staging_base=res["staging_base"],
                  staging_runtime=res["staging_runtime"], new_built=str(nm.get("built", "")) if nm else "",
                  packages=len(res.get("packages", [])), baseline=chk.get("baseline", []), apps=chk.get("apps", 0))
    rr.rr_log("RR-BUILD-OK", f"packages={result['packages']} size={res['size_bytes']} seconds={int(time.time() - t0)}")
    return finish(0)


def runtime_refresh_check(staging_runtime: str, baseline_file: str = "", postcheck_built: str = "") -> int:
    """7L/7N: run the startability check again (root-phase re-check on the kept staging tree, or the post-check on the live
    tree when postcheck_built is given). JSON on stdout; exit 1 on a veto / a runtime that is not the expected one."""
    sv, rr = symver_module(), refresh_module()
    live, pkgs = rr_paths()
    out: Dict[str, Any] = {"veto": False, "first_app": "", "built_ok": True}
    if sv is None:
        out.update(veto=True, first_app="", error="checker missing")
        print(json.dumps(out))
        return 1
    base = None
    if baseline_file:
        try:
            with open(baseline_file, "r", encoding="utf-8") as fh:
                data = json.load(fh)
            if isinstance(data, dict):
                data = data.get("baseline")
            base = data if isinstance(data, list) else None
        except (OSError, ValueError):
            base = None
    if postcheck_built and rr is not None:
        m, _mt, _w = rr.read_manifest(live)
        out["built_ok"] = bool(m and str(m.get("built", "")) == postcheck_built)
    res = sv.run_startcheck(staging_runtime or live, live, pkgs, (), base)
    out.update(veto=res["veto"], first_app=res["first_app"], new=res["new"][:50], seconds=res["seconds"])
    if rr is not None and res["veto"]:
        rr.rr_log("RR-POSTCHECK-FAIL" if postcheck_built else "RR-VETO",
                  "; ".join("|".join(x) for x in res["new"][:50]))
    print(json.dumps(out))
    return 1 if (res["veto"] or not out["built_ok"]) else 0


def runtime_refresh_clean(path: str) -> int:
    """Remove a kept staging tree. Only a folder named transmute-gnomes-runtime-* directly below the build base is removed."""
    try:
        base = os.path.realpath(build_dir_base())
        real = os.path.realpath(path)
        if os.path.dirname(real) == base and os.path.basename(real).startswith("transmute-gnomes-runtime-") and os.path.isdir(real):
            TransmutationFactory.safe_rmtree(real)
    except OSError:
        pass
    return 0


def main():
    """CLI dispatcher for shell integration and testing."""
    if len(sys.argv) < 2:
        print("Underpants Gnomes Pacman Engine v1.0_LTS ('Dark Star')")
        print("Usage: gnomes_pacman.py [sync|search|info|deps|transmute|runtime|heal|url|check-host|list-repos|list-installed] [args...]")
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
            print(f"\n  Packages to Install ({len(res['to_install'])}):")
            for pkg in res["to_install"]:
                csize = int(pkg.get("CSIZE", 0)) / (1024 * 1024)
                print(f"    • [{pkg.get('_REPO')}] {pkg.get('NAME')} ({pkg.get('VERSION')}) [{csize:.2f} MB]")

            if res["host_provided"]:
                print(f"\n  Host Base System Shielded ({len(res['host_provided'])}):")
                for k, reason in res["host_provided"].items():
                    print(f"    • {k:<24} => {reason}")

            if res["virtual_satisfied"]:
                print(f"\n  Virtual Providers Satisfied ({len(res['virtual_satisfied'])}):")
                for k, target in res["virtual_satisfied"].items():
                    print(f"    • {k:<24} => {target}")

            if res["missing"]:
                print(f"\n  Unresolved / Missing ({len(res['missing'])}):")
                for m in res["missing"]:
                    print(f"    • {m}")

            dl_mb = res["download_size_bytes"] / (1024 * 1024)
            inst_mb = res["installed_size_bytes"] / (1024 * 1024)
            print(f"\n  Total Download Size : {dl_mb:.2f} MB")
            print(f"  Total Installed Size: {inst_mb:.2f} MB\n")

    elif cmd == "transmute":
        targets = []
        out_dir = None  # 6A-139: default is build_dir_base(), not /tmp
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
        # 6A-339: names held on the waiting list in THIS run go to <output-dir>/.waiting so the shell front end can tell
        # "waiting for a newer library" from a failure
        if TransmutationFactory.HELD_NOW:
            try:
                with open(os.path.join(factory.output_dir, ".waiting"), "w", encoding="utf-8") as wfh:
                    wfh.write("\n".join(TransmutationFactory.HELD_NOW) + "\n")
            except OSError:
                pass
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
        elif sub == "refresh-status":
            res = runtime_refresh_status(record="--no-record" not in sys.argv)
            print(json.dumps(res))
        elif sub == "refresh-build":
            out_d = sys.argv[sys.argv.index("--output-dir") + 1] if "--output-dir" in sys.argv else build_dir_base()
            sys.exit(runtime_refresh_build(engine, out_d))
        elif sub == "refresh-check":
            argv = sys.argv
            stg = argv[argv.index("--staging") + 1] if "--staging" in argv else ""
            bfile = argv[argv.index("--baseline") + 1] if "--baseline" in argv else ""
            pb = argv[argv.index("--expect-built") + 1] if "--expect-built" in argv else ""
            sys.exit(runtime_refresh_check(stg, bfile, pb))
        elif sub == "refresh-clean":
            sys.exit(runtime_refresh_clean(sys.argv[3] if len(sys.argv) > 3 else ""))
        elif sub == "install":
            prof_name = "core"
            out_dir = None  # 6A-139: default is build_dir_base(), not /tmp
            # 6A-50: the value after --output-dir is never taken as the profile name
            prof_set = False
            skip_next = False
            for i, a in enumerate(sys.argv[3:], 3):
                if skip_next:
                    skip_next = False
                    continue
                if a == "--output-dir" and i + 1 < len(sys.argv):
                    out_dir = sys.argv[i + 1]
                    skip_next = True
                elif not a.startswith("-") and not prof_set:
                    prof_name = a
                    prof_set = True
            # 7L: the manual install gets the same startability check as the monthly refresh when a runtime is installed
            _live, _pkgs = rr_paths()
            _outcome: Dict[str, Any] = {}
            _hooks = rr_hooks_for(os.path.isdir(os.path.join(_live, "lib")) and symver_module() is not None, _pkgs, _live, _outcome, with_space=False) \
                if prof_name in RuntimeManager.PROFILES else None
            res = mgr.install_profile(profile_name=prof_name, verbose=not as_json, output_dir=out_dir, hooks=_hooks)
            if not res and _outcome.get("check", {}).get("veto"):
                print(f":: The runtime was not installed because {_outcome['check'].get('first_app', 'an app')} would not start "
                      f"with it; your current runtime stays.")
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
        no_sync = "--no-sync" in sys.argv
        if no_sync:
            # 6A-139: read the system cache when it has databases (a user cache is often empty); nothing is downloaded.
            # 6A-241: but only when it is newer than the user's own cache: a stale system cache (root synced days ago)
            # hid updates the user's last sync already knows (same rule as the status files: the newest wins).
            def _newest_db(base):
                d = os.path.join(base, "db")
                try:
                    names = [n for n in os.listdir(d) if n.endswith((".db.tar.zst", ".db.tar.gz"))]
                except OSError:
                    return None
                times = []
                for n in names:
                    try:
                        times.append(os.stat(os.path.join(d, n)).st_mtime)
                    except OSError:
                        pass
                return max(times) if times else None
            sys_t, user_t = _newest_db(DEFAULT_CACHE_BASE), _newest_db(USER_CACHE_BASE)
            if sys_t is not None and (user_t is None or sys_t >= user_t):
                engine = GnomesPacmanEngine(cache_dir=DEFAULT_CACHE_BASE)
        elif "--sync" in sys.argv or "-y" in sys.argv or "-Sy" in sys.argv:
            engine.sync_repositories(force=True, verbose=False)
        as_json = "--json" in sys.argv
        as_count = "--count" in sys.argv
        updates = engine.list_updates(allow_sync=not no_sync)
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

    elif cmd == "rollback":
        # rollback --plan <base> | --build <base> --snapshot N --output-dir DIR | --hold <base> <version>  (root)
        args = sys.argv[2:]
        if "--hold" in args:
            i = args.index("--hold")
            record_rollback_hold(args[i + 1], args[i + 2])
            sys.exit(0)
        base = args[args.index("--plan") + 1] if "--plan" in args else args[args.index("--build") + 1]
        snapdir = args[args.index("--snapshots") + 1] if "--snapshots" in args else SNAPSHOT_DIR
        pkgdb = args[args.index("--pkgdb") + 1] if "--pkgdb" in args else FOOTPRINT_PKGDB
        refusal = rollback_refusal(base)
        if refusal:
            print(f":: {refusal}")
            sys.exit(3)
        current, cands = rollback_candidates(base, snapdir, pkgdb)
        if not current:
            print(f":: {base} is not installed.")
            sys.exit(3)
        if not cands:
            print(f":: No snapshot holds another version of {base}, so there is nothing to go back to.")
            sys.exit(3)
        if "--plan" in args:
            c = cands[0]
            print(f"{current}|{c['pkgid']}|{c['snapshot']}|{c['date']}|{c['description']}")
            sys.exit(0)
        num = int(args[args.index("--snapshot") + 1])
        cand = next((c for c in cands if c["snapshot"] == num), None)
        if cand is None:
            print(f":: Snapshot #{num} does not hold another version of {base}.")
            sys.exit(3)
        try:
            print(build_from_snapshot(cand, args[args.index("--output-dir") + 1]))
        except (ValueError, OSError, subprocess.CalledProcessError) as exc:
            print(f":: Could not rebuild {cand['pkgid']} from snapshot #{num}: {exc}")
            sys.exit(3)
        sys.exit(0)

    elif cmd == "footprint-guard":
        # footprint-guard <staging_dir> [--label NAME] [--enforce]  |  footprint-guard --verify-archive <txz>
        args = sys.argv[2:]
        if "--verify-host-paths" in args:
            # WP-1: footprint-guard --verify-host-paths <txz> [--mode gnomes|curated] [--pkgdb DIR] [--scripts DIR]
            txz = args[args.index("--verify-host-paths") + 1]
            mode = args[args.index("--mode") + 1] if "--mode" in args else "gnomes"
            pkgdb = args[args.index("--pkgdb") + 1] if "--pkgdb" in args else FOOTPRINT_PKGDB
            scripts = args[args.index("--scripts") + 1] if "--scripts" in args else FOOTPRINT_SCRIPTS
            if mode not in ("gnomes", "curated"):
                print(f":: Unknown mode {mode}. Not installing.")
                sys.exit(2)
            try:
                res = verify_host_paths(txz, mode, pkgdb, scripts)
            except (OSError, tarfile.TarError) as exc:
                print(f":: Could not check {os.path.basename(txz)} against the installed packages ({exc}). Not installing.")
                sys.exit(4)  # 6A-135: 3 means "refused", a check that could not run is an error
            for w in res["warnings"]:
                print(f":: Note: {w}")
            if res["refusals"]:
                print(f":: Not installing {res['package']}: it would overwrite files of another package.")
                for r in res["refusals"]:
                    print(f"   {r}")
                sys.exit(3)
            sys.exit(0)
        if "--verify-archive" in args:
            txz = args[args.index("--verify-archive") + 1]
            bad = footprint_archive_non_root(txz)
            if bad:
                print(f":: {os.path.basename(txz)} has {len(bad)} entr(ies) not owned by root:root. Not installing.")
                for b in bad[:5]:
                    print(f"   {b}")
                sys.exit(1)
            sys.exit(0)
        if not args:
            print("Usage: gnomes_pacman.py footprint-guard <staging_dir> [--label NAME] [--enforce]")
            sys.exit(2)
        label = args[args.index("--label") + 1] if "--label" in args else ""
        res = footprint_guard(args[0], label, enforce=True if "--enforce" in args else None)
        sys.exit(0)

    elif cmd == "check-collision":
        # 6A-264: the text stays; the exit code says whether something was found (0) or not (1)
        if len(sys.argv) < 3:
            print("NONE")
            sys.exit(1)
        target = sys.argv[2]
        collision = engine.check_curated_collision(target)
        if collision:
            print(collision)
        else:
            print("NONE")
            sys.exit(1)

    elif cmd == "url":
        if len(sys.argv) < 3:
            sys.exit(1)
        pkg_name = sys.argv[2]
        p = engine.get_package(pkg_name)
        url_found = engine.get_download_url(p) if p else None
        if url_found:
            print(url_found)
        else:
            print("NONE")  # 6A-264: text unchanged, exit 1 when nothing is found
            sys.exit(1)

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

    elif cmd == "held":
        # P2/L1: packages waiting for a newer Slackware glibc/libstdc++ (shown, never rebuilt until something changes)
        held = TransmutationFactory.load_held()
        if "--json" in sys.argv:
            print(json.dumps(held, indent=2))
        elif not held:
            print(":: No packages are waiting for newer system libraries.")
        else:
            print(f":: Waiting for a newer Slackware ({len(held)}):")
            for k, v in sorted(held.items()):
                print(f"  • {k} {v.get('version', '')}: {v.get('reason', '')} (since {v.get('since', '?')})")

    elif cmd == "list-installed":
        as_json = "--json" in sys.argv
        installed = engine.list_installed_gnomes_packages()
        # 6A-265: like pacman -Qs, search words keep only the apps whose name or package id contains every word
        qs_words = [w.lower() for w in sys.argv[2:] if w and not w.startswith("-")]
        if qs_words:
            installed = [i for i in installed
                         if all(w in f"{i['name']} {i.get('canonical_name', '')} {i['package_id']}".lower() for w in qs_words)]
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

    elif cmd in ("heal", "heal-host", "audit-wrappers"):
        dry_run = "--dry-run" in sys.argv or "-n" in sys.argv
        as_json = "--json" in sys.argv
        res = GnomesPacmanEngine.heal_host_sovereignty(dry_run=dry_run, verbose=not as_json)
        if as_json:
            print(json.dumps(res, indent=2))
            # 6A-137: a heal that could not finish is not reported as success
            if res.get("errors"):
                sys.exit(2)
        else:
            purged = res["purged_wrappers"]
            kept = res.get("kept_stock_owned", [])
            if kept:
                # 6A-154: advice only; legacy never reinstalls a Slackware package by itself
                print(":: Launchers kept because they hide a file of a Slackware package (nothing was deleted):")
                for k in kept:
                    print(f"    - \033[1;31m{k['name']}\033[0m ({k['path']})")
                for pk in sorted({k["package"] for k in kept if k["package"]}):
                    print(f"    To restore the original, run: \033[1;36mslackpkg reinstall {pk}\033[0m")
            kept_prot = res.get("kept_protected", [])
            for k in kept_prot:
                print(":: " + localized_sentence("GNOMES_WRAPPER_PROTECTED",
                      "A launcher named {name} sits where a system program belongs. Nothing was changed; check it by hand.").replace("{name}", k["name"]))
            if not purged and not kept and not kept_prot:
                print(":: Host Sovereignty Verification: All /usr/bin/ wrappers are healthy and strictly scoped.")
                print("   Zero rogue wrappers or native package conflicts detected.")
            elif purged:
                print(f":: Host Sovereignty Healer ({'DRY RUN' if dry_run or res.get('errors') else 'EXECUTED'}):")
                print(f"  • Rogue wrappers purged from /usr/bin : {len(purged)}")
                for wpath, bname, app, owner in purged:
                    owner_str = f" [Native owner: {owner}]" if owner else ""
                    print(f"    - \033[1;31m{bname}\033[0m (from {app}){owner_str}")
            if res.get("errors"):
                sys.exit(2)

    elif cmd in ("purge-service", "purge-hooks"):
        if len(sys.argv) < 3:
            print("Error: Specify service name to purge hooks for.")
            sys.exit(1)
        targets = [a for a in sys.argv[2:] if not a.startswith("-")]
        purge_failed = False
        for svc in targets:
            problems = TransmutationFactory.purge_gnomes_service_hooks(svc)
            for pr in problems:
                print(f":: {pr}")
            if problems:
                purge_failed = True
            else:
                print(f":: Purged service hooks for '{svc}' from rc.local and rc.local_shutdown.")
        if purge_failed:
            sys.exit(1)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.stdout.write("\n\033[?25h:: Operation cancelled by user.\n")
        sys.stdout.flush()
        sys.exit(130)
