#!/usr/bin/env python3
"""
slacky_tui.py - Terminal User Interface for Slacky-Update ('Dark Star')
Engineered for Slackware Linux (-current / 15.0+)
Zero external dependencies: uses ONLY Python standard library.

Design Goals:
- 100% "True to the Original" Slackware Slacky-Update CLI design.
- Clean, serious, elegant Slackware system tool aesthetic.
- Zero staircase effect: every frame line uses absolute cursor positioning (\033[{r};1H\033[2K).
- Alternate screen buffer (\033[?1049h) with safe terminal restoration on exit/signals.
- Piped stdout support: renders UI to /dev/tty while printing clean choice to stdout.
- Mode 'main': Exact Slacky-Update main menu with interactive arrow navigation,
  digit jump, and mouse support.
- Mode 'gnomes': Underpants Gnomes Software Suite with categories COLLAPSED by default,
  line-by-line viewport scrolling, pinned header and footer dock, and 2-column grid.
- Mode 'tweaks': Interactive System & Gaming Tweaks checklist menu with badge indicators and batch actions.
- Mode 'sbo-curated': Curated SlackBuilds Hub flat checklist menu with package badges and 1-click build batching.
"""

import sys
import os
import shutil
import signal
import atexit
import termios
import tty
import select
import json
import re
import glob
import time
from collections import defaultdict
import argparse
import unicodedata

# --- [ I18N LOCALIZATION HELPER ] ---
# 6A-51: the callers export PYTHONSAFEPATH=1, which drops the script dir from sys.path; add it explicitly
_TUI_DIR = os.path.dirname(os.path.abspath(__file__))
if _TUI_DIR not in sys.path:
    sys.path.insert(0, _TUI_DIR)
try:
    from slacky_update_i18n import I18nEngine
    _I18N = I18nEngine()
    def _tr(key, default=""):
        val = _I18N.get(key)
        if (not val or val == key) and default:
            return default
        return val or default or key
except Exception:
    def _tr(key, default=""):
        return default or key

# --- [ VERSION & CODENAME ] ---
CURRENT_VERSION = os.environ.get("CURRENT_VERSION", "1.0 LTS")
RELEASE_CODENAME = os.environ.get("RELEASE_CODENAME", "Dark Star")

# --- [ ANSI COLOR & STYLING DEFINITIONS ] ---
RESET = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"
ITALIC = "\033[3m"
UNDERLINE = "\033[4m"
REVERSE = "\033[7m"

BLACK = "\033[30m"
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


# Terminal environment detection
TERM_ENV = os.environ.get("TERM", "")
IS_LINUX_VT = (TERM_ENV == "linux") or (not os.environ.get("DISPLAY") and TERM_ENV.startswith("linux"))

# --- [ STRING DISPLAY WIDTH & ANSI HELPERS ] ---
ANSI_REGEX = re.compile(r'\x1b\[[0-9;?]*[a-zA-Z]')
SGR_MOUSE_RE = re.compile(rb'^\x1b\[<(\d+);(\d+);(\d+)([Mm])')

def strip_ansi(s: str) -> str:
    """Removes all ANSI escape sequences from string."""
    return ANSI_REGEX.sub('', s)

def char_width(c: str) -> int:
    """Returns visual terminal cell width of character (0, 1, or 2 for wide/emoji)."""
    code = ord(c)
    if code in (0xFE0F, 0xFE0E):  # Variation selectors
        return 0
    if code < 32 or (127 <= code < 160):
        return 0
    if 32 <= code <= 126:
        return 1
    # Wide Unicode ranges (emojis, CJK, symbols)
    if ((0x1F300 <= code <= 0x1FAFF) or (0x2600 <= code <= 0x27BF) or
        (0x2300 <= code <= 0x23FF) or (0x2B50 <= code <= 0x2B55) or
        (0x1F1E6 <= code <= 0x1F1FF) or (0x20000 <= code <= 0x2FFFD) or
        (0x3000 <= code <= 0x303F) or (0x4E00 <= code <= 0x9FFF)):
        return 2
    eaw = unicodedata.east_asian_width(c)
    if eaw in ('W', 'F'):
        return 2
    return 1

def str_display_width(s: str) -> int:
    """Returns visual terminal cell width of string ignoring ANSI codes."""
    clean = strip_ansi(s)
    return sum(char_width(c) for c in clean)

def truncate_ansi(s: str, max_w: int, ellipsis: str = "…") -> str:
    """Truncates string to fit in max_w display cells while preserving ANSI tags."""
    if str_display_width(s) <= max_w:
        return s
    el_w = str_display_width(ellipsis)
    target = max(0, max_w - el_w)
    out = []
    curr_w = 0
    i = 0
    n = len(s)
    while i < n:
        if s[i] == '\x1b':
            m = ANSI_REGEX.match(s, i)
            if m:
                out.append(m.group(0))
                i = m.end()
                continue
        w = char_width(s[i])
        if curr_w + w > target:
            break
        curr_w += w
        out.append(s[i])
        i += 1
    out.append(RESET)
    out.append(ellipsis)
    return "".join(out)

def pad_ansi(s: str, target_w: int, align: str = "left") -> str:
    """Pads string to exact target_w visual width with spaces."""
    w = str_display_width(s)
    if w >= target_w:
        return truncate_ansi(s, target_w)
    pad = " " * (target_w - w)
    if align == "right":
        return pad + s
    elif align == "center":
        left = len(pad) // 2
        right = len(pad) - left
        return (" " * left) + s + (" " * right)
    return s + pad

# --- [ CLEAN TERMINAL RECOVERY CONTEXT MANAGER ] ---
_ACTIVE_RAW_TERMINAL = None

def _global_cleanup_terminal():
    global _ACTIVE_RAW_TERMINAL
    if _ACTIVE_RAW_TERMINAL is not None:
        _ACTIVE_RAW_TERMINAL.restore()
        _ACTIVE_RAW_TERMINAL = None

atexit.register(_global_cleanup_terminal)

def _sig_term_handler(signum, frame):
    _global_cleanup_terminal()
    sys.exit(128 + signum)

try:
    signal.signal(signal.SIGINT, _sig_term_handler)
    signal.signal(signal.SIGTERM, _sig_term_handler)
    signal.signal(signal.SIGHUP, _sig_term_handler)
except Exception:
    pass

class SafeRawTerminal:
    """
    Context manager to safely manage raw terminal mode.
    - Uses termios.tcgetattr / tcsetattr(..., termios.TCSADRAIN).
    - Writes UI escapes to /dev/tty when stdout is piped/captured.
    - Guarantees cursor is unhidden and terminal restored on exit or signals.
    """
    def __init__(self, enable_mouse=True):
        self.is_tty = sys.stdin.isatty()
        self.term_out = None
        self.term_in_fd = None
        self.orig_termios = None
        self.enable_mouse = enable_mouse and (not IS_LINUX_VT)
        self.in_raw_mode = False

    def __enter__(self):
        global _ACTIVE_RAW_TERMINAL
        if not self.is_tty:
            return self

        # Determine terminal output stream (support captured stdout in subshells)
        if sys.stdout.isatty():
            self.term_out = sys.stdout
        else:
            try:
                self.term_out = open("/dev/tty", "w", encoding="utf-8", buffering=1)
            except Exception:
                self.term_out = sys.stderr

        self.term_in_fd = sys.stdin.fileno()
        try:
            self.orig_termios = termios.tcgetattr(self.term_in_fd)
            tty.setraw(self.term_in_fd)
            self.in_raw_mode = True
        except Exception:
            self.orig_termios = None
            self.in_raw_mode = False

        _ACTIVE_RAW_TERMINAL = self

        # Enter alternate buffer and hide cursor
        self.write("\033[?1049h\033[?25l")
        if self.enable_mouse:
            # Enable SGR 1006 extended mouse tracking
            self.write("\033[?1000h\033[?1002h\033[?1006h")
        self.flush()
        return self

    def write(self, s: str):
        if self.term_out:
            try:
                self.term_out.write(s)
            except Exception:
                pass

    def flush(self):
        if self.term_out:
            try:
                self.term_out.flush()
            except Exception:
                pass

    def restore(self):
        if self.term_out:
            try:
                if self.enable_mouse:
                    self.write("\033[?1006l\033[?1002l\033[?1000l")
                self.write("\033[?25h\033[0m\033[?1049l\r\n")
                self.flush()
                if self.term_out not in (sys.stdout, sys.stderr):
                    self.term_out.close()
            except Exception:
                pass
            self.term_out = None

        if self.in_raw_mode and self.orig_termios is not None and self.term_in_fd is not None:
            try:
                # Flush pending input queue to prevent leaked mouse release / escape bytes
                try:
                    termios.tcflush(self.term_in_fd, termios.TCIFLUSH)
                except Exception:
                    pass
                termios.tcsetattr(self.term_in_fd, termios.TCSADRAIN, self.orig_termios)
            except Exception:
                pass
            self.in_raw_mode = False
            self.orig_termios = None

    def __exit__(self, exc_type, exc_val, exc_tb):
        global _ACTIVE_RAW_TERMINAL
        self.restore()
        if _ACTIVE_RAW_TERMINAL is self:
            _ACTIVE_RAW_TERMINAL = None

# --- [ KEY & MOUSE INPUT STREAM PARSER ] ---
ESCAPE_KEY_MAP = {
    b'\x1b[A': 'up', b'\x1bOA': 'up',
    b'\x1b[B': 'down', b'\x1bOB': 'down',
    b'\x1b[C': 'right', b'\x1bOC': 'right',
    b'\x1b[D': 'left', b'\x1bOD': 'left',
    b'\x1b[5~': 'page_up',
    b'\x1b[6~': 'page_down',
    b'\x1b[H': 'home', b'\x1b[1~': 'home', b'\x1b[7~': 'home',
    b'\x1b[F': 'end', b'\x1b[4~': 'end', b'\x1b[8~': 'end',
    b'\x1b[2~': 'insert',
    b'\x1b[3~': 'delete',
}

def parse_input_bytes(data: bytes):
    """
    Parses raw bytes from terminal input into structured event tuples:
    - ('key', 'up'|'down'|'left'|'right'|'enter'|'backspace'|'tab'|'escape'|...)
    - ('mouse', button_code, x, y, is_release)
    - ('char', 'a'|'1'|...)
    """
    events = []
    i = 0
    n = len(data)
    while i < n:
        # 1. SGR Mouse sequence: \x1b[<btn;x;yM or m
        if data[i:i+3] == b'\x1b[<':
            m = SGR_MOUSE_RE.match(data[i:])
            if m:
                btn = int(m.group(1))
                x = int(m.group(2))
                y = int(m.group(3))
                is_release = (m.group(4) == b'm')
                events.append(('mouse', btn, x, y, is_release))
                i += m.end()
                continue

        # 2. ANSI escape sequences
        if data[i:i+1] == b'\x1b':
            matched = False
            for seq, keyname in ESCAPE_KEY_MAP.items():
                if data[i:].startswith(seq):
                    events.append(('key', keyname))
                    i += len(seq)
                    matched = True
                    break
            if matched:
                continue

            if i + 1 == n:
                events.append(('key', 'escape'))
                i += 1
                continue
            events.append(('key', 'escape'))
            i += 1
            continue

        # 3. Control keys
        b = data[i:i+1]
        if b in (b'\r', b'\n'):
            events.append(('key', 'enter'))
            i += 1
        elif b in (b'\x7f', b'\x08'):
            events.append(('key', 'backspace'))
            i += 1
        elif b == b'\t':
            events.append(('key', 'tab'))
            i += 1
        elif b == b'\x03':
            events.append(('key', 'ctrl_c'))
            i += 1
        elif b == b'\x04':
            events.append(('key', 'ctrl_d'))
            i += 1
        else:
            # 4. UTF-8 Characters
            char_len = 1
            byte_val = data[i]
            if byte_val >= 0b11110000:
                char_len = 4
            elif byte_val >= 0b11100000:
                char_len = 3
            elif byte_val >= 0b11000000:
                char_len = 2
            chunk = data[i:i+char_len]
            try:
                ch = chunk.decode("utf-8")
                events.append(('char', ch))
            except UnicodeDecodeError:
                pass
            i += char_len

    return events

# --- [ UNDERPANTS GNOMES CATALOG & FAST STATUS DETECTOR ] ---
DEFAULT_CAT_ORDER = [
    "desktop", "engine", "launcher", "hardware", "streaming",
    "social", "audio", "creative", "ricing", "tools", "browser", "bootloader"
]

DEFAULT_CAT_TITLES = {
    "desktop": "Wayland Desktops & Shells (Hyprland / Noctalia)",
    "engine": "Performance, Gaming HUD & Schedulers",
    "launcher": "Storefronts & Game Launchers",
    "hardware": "Hardware Control, Tuning & DKMS Drivers",
    "streaming": "OBS Studio & Production Plugins",
    "social": "Voice Chat, Streaming & Communications",
    "audio": "Studio Audio DSP & Sound Processing",
    "creative": "Creative, 3D & Photography Studio",
    "ricing": "Desktop Aesthetics & Themes",
    "tools": "Power Tools & Synchronization",
    "browser": "Web Browsers",
    "bootloader": "Secure Boot & UEFI Utilities"
}

DEFAULT_CAT_TITLES_ASCII = DEFAULT_CAT_TITLES

def detect_installed_packages():
    """Fast non-modifying detection of installed packages in /var/log/packages and binaries."""
    installed = {}
    pkg_dir = "/var/log/packages"
    if os.path.exists(pkg_dir):
        try:
            for f in os.listdir(pkg_dir):
                parts = f.rsplit('-', 3)
                if len(parts) >= 2:
                    p_name = parts[0]
                    p_ver = parts[1] if len(parts) >= 4 else "INSTALLED"
                    for pref in ("underpants-", "cachyos-gnome-", "cachyos-gnome-gnome-"):
                        if p_name.startswith(pref):
                            p_name = p_name[len(pref):]
                    vm = re.match(r"^(.+?)-([0-9].*)$", p_name)
                    if vm:
                        p_name = vm.group(1)
                        if p_ver.isdigit() or p_ver == "INSTALLED":
                            p_ver = vm.group(2)
                    installed[p_name] = p_ver
                    canon = p_name
                    for sfx in ("-bin", "-git", "-dkms", "-appimage"):
                        if canon.endswith(sfx):
                            canon = canon[:-len(sfx)]
                            break
                    if canon not in installed or p_ver > installed[canon]:
                        installed[canon] = p_ver
        except Exception:
            pass

    # Secondary check for known standalone binaries / paths
    binary_map = {
        "steam": ["steam", "/usr/bin/steam"],
        "mangohud": ["mangohud", "mangoapp"],
        "gamemode": ["gamemoded", "/usr/bin/gamemoded"],
        "goverlay": ["goverlay"],
        "gamescope": ["gamescope"],
        "heroic": ["heroic"],
        "lutris": ["lutris"],
        "faugus": ["faugus-launcher"],
        "protonplus": ["protonplus", "proton-plus"],
        "lact": ["lact"],
        "openrgb": ["openrgb"],
        "solaar": ["solaar"],
        "obs-studio": ["obs"],
        "discord": ["discord", "/opt/discord/Discord"],
        "vesktop": ["vesktop"],
        "sunshine": ["sunshine"],
        "easyeffects": ["easyeffects"],
        "audacity": ["audacity"],
        "spotify": ["spotify"],
        "inkscape": ["inkscape"],
        "darktable": ["darktable"],
        "blender": ["blender", "/usr/bin/blender", "/opt/blender/blender"],
        "freecad": ["freecad", "FreeCAD"],
        "syncthing": ["syncthing"],
        "google-chrome": ["google-chrome", "google-chrome-stable"],
        "brave": ["brave", "brave-browser"],
        "sbctl": ["sbctl"]
    }
    for pid, cands in binary_map.items():
        if pid in installed:
            continue
        for cand in cands:
            if cand.startswith('/'):
                if glob.glob(cand):
                    installed[pid] = "INSTALLED"
                    break
            else:
                if shutil.which(cand):
                    installed[pid] = "INSTALLED"
                    break
    return installed

def load_gnomes_catalog():
    """Extracts catalog entries from lib/mod_gaming.sh or built-in table."""
    catalog = []
    mod_gaming_paths = [
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "mod_gaming.sh"),
        "/usr/share/slacky-update/lib/mod_gaming.sh",
        "/usr/local/lib/slacky-update/lib/mod_gaming.sh"
    ]
    extracted = False
    for path in mod_gaming_paths:
        if os.path.exists(path):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    content = f.read()
                m = re.search(r'get_gaming_catalog\(\)\s*\{\s*cat << \'CATALOG_EOF\'\s*\n(.*?)\nCATALOG_EOF', content, re.DOTALL)
                if m:
                    lines = m.group(1).splitlines()
                    for line in lines:
                        line = line.strip()
                        if not line or line.startswith('#'):
                            continue
                        parts = line.split('|')
                        if len(parts) >= 3:
                            pkg_id = parts[0].strip()
                            name = parts[1].strip()
                            cat = parts[2].strip()
                            hidden = len(parts) >= 8 and parts[7].strip() == "hidden"
                            if not hidden:
                                catalog.append({"id": pkg_id, "name": name, "cat": cat})
                    extracted = True
                    break
            except Exception:
                pass

    if not extracted or not catalog:
        # Fallback catalog essentials
        catalog = [
            {"id": "hyprland", "name": "Hyprland Full Desktop Suite", "cat": "desktop"},
            {"id": "noctalia", "name": "Noctalia Wayland Shell", "cat": "desktop"},
            {"id": "mangohud", "name": "MangoHud (+ 32-bit Multilib & mangoapp)", "cat": "engine"},
            {"id": "gamemode", "name": "Feral GameMode (+ 32-bit Multilib & Governor)", "cat": "engine"},
            {"id": "goverlay", "name": "GOverlay (MangoHud GUI Configurator)", "cat": "engine"},
            {"id": "gamescope", "name": "Gamescope (Micro-Compositor & HDR/Upscaling)", "cat": "engine"},
            {"id": "scx", "name": "Sched-EXT SCX Schedulers & Tools", "cat": "engine"},
            {"id": "steam", "name": "Steam (Valve Gaming Platform & Proton)", "cat": "launcher"},
            {"id": "heroic", "name": "Heroic Games Launcher (Epic, GOG, Amazon)", "cat": "launcher"},
            {"id": "lutris", "name": "Lutris Gaming Platform Manager", "cat": "launcher"},
            {"id": "faugus", "name": "Faugus Launcher (Fast Proton Launcher)", "cat": "launcher"},
            {"id": "protonplus", "name": "ProtonPlus (Wine/GE & Proton Manager)", "cat": "launcher"},
            {"id": "lact", "name": "LACT (AMD/Intel GPU Overclocking & Fans)", "cat": "hardware"},
            {"id": "openrgb", "name": "OpenRGB (Hardware RGB Lighting Control)", "cat": "hardware"},
            {"id": "solaar", "name": "Solaar (Logitech Wireless Device Manager)", "cat": "hardware"},
            {"id": "obs-studio", "name": "OBS Studio (Next-Gen Creator Suite)", "cat": "streaming"},
            {"id": "discord", "name": "Discord Voice & Game Messaging", "cat": "social"},
            {"id": "easyeffects", "name": "EasyEffects (PipeWire Audio DSP Studio)", "cat": "audio"},
            {"id": "blender", "name": "Blender 3D Suite & VFX Studio", "cat": "creative"},
            {"id": "google-chrome", "name": "Google Chrome (Hardware Accelerated)", "cat": "browser"},
            {"id": "sbctl", "name": "sbctl Secure Boot Key Manager", "cat": "bootloader"}
        ]
    return catalog

def get_pending_updates_lines(max_available_lines=None, cols=80, ascii_only=False):
    """Reads /var/cache/slacky-update/status.json to display available updates summary in 2-3 columns with dynamic space budgeting."""
    candidates = []
    xdg_c = os.environ.get("XDG_CACHE_HOME")
    if xdg_c:
        candidates.append(os.path.join(xdg_c, "slacky-update", "status.json"))
    candidates.append(os.path.expanduser("~/.cache/slacky-update/status.json"))
    sudo_u = os.environ.get("SUDO_USER")
    if sudo_u:
        try:
            import pwd
            pw = pwd.getpwnam(sudo_u)
            candidates.append(os.path.join(pw.pw_dir, ".cache", "slacky-update", "status.json"))
        except Exception:
            candidates.append(os.path.expanduser(f"~{sudo_u}/.cache/slacky-update/status.json"))
    candidates.append("/var/cache/slacky-update/status.json")

    # status-cache split: the newest status.json (by last_check_ts) of all candidates is the one shown
    _best, _best_ts = None, -1.0
    for c in candidates:
        if os.path.exists(c):
            try:
                with open(c, "r", encoding="utf-8") as f:
                    _d = json.load(f)
                _ts = float(_d.get("last_check_ts", os.path.getmtime(c)))
                if _ts > _best_ts:
                    _best, _best_ts = _d, _ts
            except Exception:
                pass
    for c in ([None] if _best is not None else []):
        if True:
            try:
                data = _best
                cats = [
                    ("CAT_SLACKWARE", "Slackware", data.get("slackware_updates", [])),
                    ("CAT_SLACKPKGPLUS", "Slackpkg+", data.get("slackpkgplus_updates", [])),
                    ("CAT_FLATPAK", "Flatpak", data.get("flatpak_updates", [])),
                    ("CAT_SBO", "SlackBuilds", data.get("sbo_updates", [])),
                    ("CAT_KERNEL", "CachyOS Kernel", data.get("cachyos_kernel_updates", [])),
                    ("CAT_GAMING", "Gaming", data.get("cachyos_gaming_updates", [])),
                    ("CAT_GNOMES", "Gnomes Software Suite", data.get("gnomes_updates", [])),
                    ("CAT_NVIDIA", "NVIDIA Driver", data.get("nvidia_driver_updates", [])),
                ]
                active_cats = [(ckey, def_lbl, [p for p in pkgs if p]) for ckey, def_lbl, pkgs in cats if pkgs]
                total = sum(len(pkgs) for _, _, pkgs in active_cats)
                gl_mismatch = data.get("nvidia_gl_mismatch", False)
                sb_warnings = data.get("secure_boot", {}).get("warnings", [])

                if total > 0 or gl_mismatch or sb_warnings:
                    lines = [f"{BOLD_CYAN}{_tr('CLI_UPDATES_HEADER', 'Available Updates:')}{RESET}"]
                    if gl_mismatch:
                        lines.append(f"  {BOLD_RED}• {_tr('NVIDIA_SYNC_FAIL', 'NVIDIA GL driver mismatch detected! Reboot or reinstall recommended.')}{RESET}")
                    for w in sb_warnings:
                        lines.append(f"  {BOLD_RED}• Secure Boot Warning: {w}{RESET}")

                    avail_budget = None
                    if max_available_lines is not None:
                        avail_budget = max(1, max_available_lines - len(lines))

                    bullet = "*" if ascii_only else "•"
                    rendered_pkgs = 0
                    truncated = False

                    for cat_idx, (ckey, def_lbl, pkgs) in enumerate(active_cats):
                        if avail_budget is not None and avail_budget <= 1:
                            truncated = True
                            break

                        max_p_len = max((len(p) for p in pkgs), default=20)
                        needed_w = max_p_len + 5
                        if cols >= 120 and (cols - 4) // 3 >= max(26, min(needed_w, 36)):
                            num_cols = 3
                        elif cols >= 70 and (cols - 4) // 2 >= max(26, min(needed_w, 32)):
                            num_cols = 2
                        else:
                            num_cols = 1

                        col_width = (cols - 4) // num_cols
                        num_rows = (len(pkgs) + num_cols - 1) // num_cols

                        cat_rows = []
                        for r in range(num_rows):
                            row_parts = []
                            for col_i in range(num_cols):
                                idx = col_i * num_rows + r
                                if idx < len(pkgs):
                                    item = pkgs[idx]
                                    avail_text = col_width - 4
                                    disp_item = item if len(item) <= avail_text else (item[:avail_text - 1] + "…")
                                    entry = f"  {GREEN}{bullet}{RESET} {disp_item}"
                                    pad = " " * max(0, col_width - (len(disp_item) + 4))
                                    row_parts.append(f"{entry}{pad}")
                            cat_rows.append("".join(row_parts).rstrip())

                        cat_header = f"  {BOLD_YELLOW}{_tr(ckey, def_lbl)} ({len(pkgs)}):{RESET}"

                        if avail_budget is None or (len(cat_rows) + 1 <= avail_budget):
                            lines.append(cat_header)
                            lines.extend(cat_rows)
                            rendered_pkgs += len(pkgs)
                            if avail_budget is not None:
                                avail_budget -= (len(cat_rows) + 1)
                        else:
                            lines.append(cat_header)
                            if avail_budget is not None:
                                avail_budget -= 1

                            max_rows_to_show = max(0, (avail_budget - 1) if avail_budget is not None else len(cat_rows))
                            if max_rows_to_show > 0:
                                lines.extend(cat_rows[:max_rows_to_show])
                                shown_in_rows = 0
                                for r in range(max_rows_to_show):
                                    for col_i in range(num_cols):
                                        if col_i * num_rows + r < len(pkgs):
                                            shown_in_rows += 1
                                rendered_pkgs += shown_in_rows
                            truncated = True
                            break

                    remaining = total - rendered_pkgs
                    if truncated and remaining > 0:
                        more_tmpl = _tr("UPDATES_MORE_SUMMARY", "... and {count} more updates (enlarge window to view all)")
                        more_msg = more_tmpl.replace("{count}", str(remaining))
                        dim_w = globals().get("DIM_WHITE", "\033[2;37m")
                        lines.append(f"  {dim_w}{more_msg}{RESET}")

                    return lines
            except Exception:
                pass

    return [
        f"{BOLD_CYAN}{_tr('CLI_UPDATES_HEADER', 'Available Updates:')}{RESET}",
        f"{BOLD_GREEN}{_tr('NO_PENDING_UPDATES', 'No pending updates found. System is up to date.')}{RESET}"
    ]

def parse_indices_from_text(text: str, max_idx: int) -> set:
    """Parses whitespace/comma-separated numbers and ranges (e.g. '1 3 5', '1-4', '1-3 5') into a set of ints."""
    indices = set()
    clean = re.sub(r'(\d+)\s*-\s*(\d+)', r'\1-\2', text.replace(',', ' '))
    tokens = clean.split()
    for tok in tokens:
        m_range = re.match(r'^(\d+)[-.]+(\d+)$', tok)
        if m_range:
            start_n = int(m_range.group(1))
            end_n = int(m_range.group(2))
            if start_n > end_n:
                start_n, end_n = end_n, start_n
            for n in range(start_n, end_n + 1):
                if 1 <= n <= max_idx:
                    indices.add(n)
            continue
        m_part = re.match(r'^(\d+)[-.]+$', tok)
        if m_part:
            n = int(m_part.group(1))
            if 1 <= n <= max_idx:
                indices.add(n)
            continue
        if tok.isdigit():
            n = int(tok)
            if 1 <= n <= max_idx:
                indices.add(n)
            continue
    return indices

# --- [ SLACKY TUI BASE CLASS ] ---
class SlackyTUI:
    def __init__(self, mode="gnomes", ascii_only=False, enable_mouse=True):
        self.mode = mode
        self.ascii_only = ascii_only or IS_LINUX_VT
        self.enable_mouse = enable_mouse and (not IS_LINUX_VT)
        self.raw_term = SafeRawTerminal(enable_mouse=self.enable_mouse)

        # Dynamic terminal dimensions
        self.cols = 80
        self.rows = 24
        self.input_buffer = ""
        self.resized = True

        # Signal handling for SIGWINCH
        try:
            signal.signal(signal.SIGWINCH, self._on_winch)
        except Exception:
            pass

    def _on_winch(self, signum, frame):
        self.resized = True

    def update_terminal_size(self):
        new_cols = 0
        new_rows = 0

        # 1. Query /dev/tty via active raw_term descriptors (handles subshell pipes stdout gracefully)
        for fd in (
            getattr(getattr(self, 'raw_term', None), 'tty_out', None),
            getattr(getattr(self, 'raw_term', None), 'term_in_fd', None),
        ):
            if fd is not None:
                try:
                    fileno = fd.fileno() if hasattr(fd, 'fileno') else int(fd)
                    sz = os.get_terminal_size(fileno)
                    if sz.columns > 0 and sz.lines > 0:
                        new_cols, new_rows = sz.columns, sz.lines
                        break
                except Exception:
                    pass

        # 2. Try direct /dev/tty access
        if new_cols == 0 or new_rows == 0:
            try:
                with open("/dev/tty", "rb") as tty_fp:
                    sz = os.get_terminal_size(tty_fp.fileno())
                    if sz.columns > 0 and sz.lines > 0:
                        new_cols, new_rows = sz.columns, sz.lines
            except Exception:
                pass

        # 3. Fallback to shutil / environment
        if new_cols == 0 or new_rows == 0:
            sz = shutil.get_terminal_size(fallback=(80, 24))
            new_cols, new_rows = sz.columns, sz.lines

        new_cols = max(40, new_cols)
        new_rows = max(12, new_rows)
        if new_cols != self.cols or new_rows != self.rows:
            self.cols = new_cols
            self.rows = new_rows
            self.resized = True

    def render_frame(self, lines: list, cursor_pos: tuple = None):
        """
        Renders complete frame using strictly absolute cursor positioning per row:
        \033[{row};1H\033[2K{content}
        This eliminates ANY possible staircase effect in raw terminal mode.
        """
        out = ["\033[?25l"]
        if self.resized:
            out.append("\033[2J")
            self.resized = False

        for r in range(1, self.rows + 1):
            idx = r - 1
            content = lines[idx] if idx < len(lines) else ""
            if str_display_width(content) > self.cols:
                content = truncate_ansi(content, self.cols)
            out.append(f"\033[{r};1H\033[2K{content}")

        if cursor_pos:
            crow, ccol = cursor_pos
            out.append(f"\033[{crow};{ccol}H\033[?25h")
        else:
            out.append(f"\033[{self.rows};{self.cols}H")

        self.raw_term.write("".join(out))
        self.raw_term.flush()

def format_exit_label(text: str) -> str:
    """Ensures exit/return menu option labels cleanly end with (ESC) without duplicate tags."""
    cleaned = re.sub(r'^[0-9]+\.\s*', '', text).strip()
    if "(ESC)" not in cleaned and "[ESC]" not in cleaned:
        cleaned = f"{cleaned} (ESC)"
    return cleaned

# --- [ SLACKY-UPDATE MAIN MENU TUI ] ---
class MainMenuTUI(SlackyTUI):
    """
    Main Menu TUI: 100% True to the Original Slacky-Update CLI.
    - Clean Slackware Dark Star branding.
    - Interactive cursor navigation (▶ / bold cyan) and mouse selection.
    """
    def __init__(self, gpu="generic", items=None, ascii_only=False, enable_mouse=True):
        super().__init__(mode="main", ascii_only=ascii_only, enable_mouse=enable_mouse)
        self.gpu = gpu.lower() if gpu else "generic"
        self.items = self.init_items(items)
        self.selected_idx = 0
        self.options_start_row = 1

    def init_items(self, custom_items):
        if custom_items and isinstance(custom_items, list):
            return custom_items

        opts = []
        opts.append({"id": "1", "label": _tr("MENU_FULL_UPDATE", "Full System Upgrade (Slackware, Flatpaks, SBo, Kernel & Secure Boot)")})
        opts.append({"id": "2", "label": _tr("MENU_KERNEL", "CachyOS Kernel Management (Inspect & Install)")})

        if "nvidia" in self.gpu:
            opts.append({"id": "3", "label": _tr("MENU_NVIDIA", "NVIDIA Driver Management (Branch Selection & DKMS)")})
            opts.append({"id": "4", "label": _tr("MENU_GAMING", "Underpants Gnomes Gaming & Software Suite")})
            opts.append({"id": "5", "label": _tr("MENU_CLEAN", "System Maintenance (Clean Package Caches & Old Kernels)")})
            opts.append({"id": "6", "label": _tr("MENU_LIMINE", "Limine Bootloader & Secure Boot Matrix (BLAKE2B Hashing, Snapshots & Self-Heal)")})
            opts.append({"id": "7", "label": _tr("MENU_ARMOR", "UEFI Secure Boot & MOK Armor Command Center")})
            opts.append({"id": "8", "label": _tr("MENU_FIELD_GUIDE", "Master Field Guide & Manual (PDF/QR/Docs)")})
            opts.append({"id": "9", "label": _tr("MENU_EXIT", "Exit Slacky-Update (ESC)")})
        elif "amd" in self.gpu:
            opts.append({"id": "3", "label": _tr("MENU_AMD_ROCM", "AMD ROCm & Compute Stack")})
            opts.append({"id": "4", "label": _tr("MENU_GAMING", "Underpants Gnomes Gaming & Software Suite")})
            opts.append({"id": "5", "label": _tr("MENU_CLEAN", "System Maintenance (Clean Package Caches & Old Kernels)")})
            opts.append({"id": "6", "label": _tr("MENU_LIMINE", "Limine Bootloader & Secure Boot Matrix (BLAKE2B Hashing, Snapshots & Self-Heal)")})
            opts.append({"id": "7", "label": _tr("MENU_ARMOR", "UEFI Secure Boot & MOK Armor Command Center")})
            opts.append({"id": "8", "label": _tr("MENU_FIELD_GUIDE", "Master Field Guide & Manual (PDF/QR/Docs)")})
            opts.append({"id": "9", "label": _tr("MENU_EXIT", "Exit Slacky-Update (ESC)")})
        else:
            # Pure Intel / Generic (8 options)
            opts.append({"id": "3", "label": _tr("MENU_GAMING", "Underpants Gnomes Gaming & Software Suite")})
            opts.append({"id": "4", "label": _tr("MENU_CLEAN", "System Maintenance (Clean Package Caches & Old Kernels)")})
            opts.append({"id": "5", "label": _tr("MENU_LIMINE", "Limine Bootloader & Secure Boot Matrix (BLAKE2B Hashing, Snapshots & Self-Heal)")})
            opts.append({"id": "6", "label": _tr("MENU_ARMOR", "UEFI Secure Boot & MOK Armor Command Center")})
            opts.append({"id": "7", "label": _tr("MENU_FIELD_GUIDE", "Master Field Guide & Manual (PDF/QR/Docs)")})
            opts.append({"id": "8", "label": _tr("MENU_EXIT", "Exit Slacky-Update (ESC)")})

        cleaned_opts = []
        for it in opts:
            raw_lbl = it["label"]
            clean_lbl = re.sub(r'^[0-9]+\.\s*', '', raw_lbl)
            if it["id"] in ("8", "9") and ("exit" in clean_lbl.lower() or "avslutt" in clean_lbl.lower() or it["id"] == str(len(opts))):
                clean_lbl = format_exit_label(clean_lbl)
            cleaned_opts.append({
                "id": it["id"],
                "label": f"{it['id']}. {clean_lbl}"
            })
        return cleaned_opts

    def render_screen(self):
        self.update_terminal_size()
        lines = []

        # 1. Header (Original Slacky-Update CLI)
        lines.append(f"{BOLD_BLUE}Slacky-Update (v{CURRENT_VERSION} '{RELEASE_CODENAME}') [Pre-Release / Early Access]{RESET}")
        lines.append(f"{BLUE}Slackware Core Update & High-Performance Modernization Engine{RESET}")
        check_mark = "*" if self.ascii_only else "✓"
        lines.append(f"  {GREEN}{check_mark} Slacky-Update is up to date (v{CURRENT_VERSION}){RESET}")
        lines.append("")

        # Calculate space available for updates
        # Fixed lines: Header (4) + Blank after updates (1) + Actions header (1) + len(self.items) + Blank before hint (1) + Hint line (1) + Prompt line (1)
        fixed_lines = len(self.items) + 9
        avail_for_updates = max(3, self.rows - fixed_lines)

        # 2. Available Updates status (dynamic columns and row budgeting)
        updates_lines = get_pending_updates_lines(max_available_lines=avail_for_updates, cols=self.cols, ascii_only=self.ascii_only)
        lines.extend(updates_lines)
        lines.append("")

        # 3. Actions Header
        lines.append(f"{BOLD}{_tr('CLI_ACTIONS_HEADER', 'Select an operation:')}{RESET}")

        # Record starting row for options to handle mouse clicks accurately
        self.options_start_row = len(lines) + 1

        # 4. Options
        for i, it in enumerate(self.items):
            is_sel = (i == self.selected_idx)
            lbl = it["label"]
            if is_sel:
                cur = ">" if self.ascii_only else "▶"
                lines.append(f"  {BOLD_CYAN}{cur}{RESET} {BOLD_CYAN}{lbl}{RESET}")
            else:
                if "limine" in lbl.lower():
                    lines.append(f"    {BOLD_CYAN}{lbl}{RESET}")
                elif "field guide" in lbl.lower() or "master field" in lbl.lower():
                    lines.append(f"    {BOLD_GREEN}{lbl}{RESET}")
                else:
                    lines.append(f"    {lbl}")

        # 5. Prompt line & Navigation Hint
        lines.append("")
        default_hint = "[*] Click or [1-{range}] to select | Hold Shift + Drag to copy text | (ESC) Exit" if self.ascii_only else "💡 Click or [1-{range}] to select  •  Hold Shift + Drag to copy text  •  (ESC) Exit"
        hint_text = _tr("TUI_NAV_HINT_COPY", default_hint).replace("{range}", str(len(self.items)))
        lines.append(f"  {DIM_WHITE}{hint_text}{RESET}")
        prompt_prefix = _tr("SELECT_OPERATION_RANGE", "Enter choice [{range}]: ").replace("{range}", f"1-{len(self.items)}")
        prompt_line = f"{prompt_prefix}{self.input_buffer}"
        lines.append(prompt_line)

        prompt_row = len(lines)
        prompt_col = 1 + str_display_width(prompt_line)
        self.render_frame(lines, cursor_pos=(prompt_row, prompt_col))

    def run_interactive(self):
        with self.raw_term:
            need_render = True
            while True:
                if need_render or self.resized:
                    self.render_screen()
                    need_render = False
                    self.resized = False

                r, _, _ = select.select([self.raw_term.term_in_fd], [], [], 0.05)
                if not r:
                    self.update_terminal_size()
                    continue

                try:
                    data = os.read(self.raw_term.term_in_fd, 1024)
                except Exception:
                    break

                if not data:
                    break

                events = parse_input_bytes(data)
                if events:
                    need_render = True

                for ev in events:
                    ev_type = ev[0]
                    if ev_type == 'key':
                        key = ev[1]
                        if key == 'up':
                            self.selected_idx = max(0, self.selected_idx - 1)
                        elif key == 'down':
                            self.selected_idx = min(len(self.items) - 1, self.selected_idx + 1)
                        elif key == 'backspace':
                            if self.input_buffer:
                                self.input_buffer = self.input_buffer[:-1]
                        elif key in ('escape', 'ctrl_c'):
                            return self.items[-1]["id"]  # Exit
                        elif key == 'enter':
                            if self.input_buffer.strip():
                                return self.input_buffer.strip()
                            return self.items[self.selected_idx]["id"]

                    elif ev_type == 'char':
                        ch = ev[1]
                        if ch.upper() == 'Q':
                            return self.items[-1]["id"]
                        if ch.isdigit():
                            d = int(ch)
                            for it_idx, it in enumerate(self.items):
                                if it["id"] == str(d):
                                    self.selected_idx = it_idx
                                    return str(d)
                        self.input_buffer += ch

                    elif ev_type == 'mouse':
                        btn, x, y, release = ev[1], ev[2], ev[3], ev[4]
                        if btn == 0 and not release:
                            opt_idx = y - self.options_start_row
                            if 0 <= opt_idx < len(self.items):
                                return self.items[opt_idx]["id"]

        return self.items[-1]["id"]

# --- [ SIMPLE SELECT TUI (SBO HUBS & MENUS) ] ---
class SimpleSelectTUI(SlackyTUI):
    """
    SimpleSelectTUI: Interactive single-choice menu with arrow navigation,
    instant numeric jumping, and mouse selection.
    Strict per-row absolute positioning (\033[{row};1H\033[2K{content}) - NO STAIRCASE.
    Used for:
    - --mode sbo-main: SlackBuilds & Tweaks Hub
    - --mode sbo-search: SBo Search & Installation Station
    - --mode sbo-recommended: Recommended Gaming SBo Packages
    """
    def __init__(self, mode="sbo-main", title=None, subtitle=None, items=None, badges=None, ascii_only=False, enable_mouse=True):
        super().__init__(mode=mode, ascii_only=ascii_only, enable_mouse=enable_mouse)
        self.title = title
        self.subtitle = subtitle
        self.badges = badges or {}
        self.items = self.init_items(items)
        self.selected_idx = 0
        self.options_start_row = 1

    def init_items(self, custom_items):
        if self.mode == "kernel-manage":
            self.title = self.title or _tr("KERNEL_MANAGE_SYSTEM_TITLE", "Manage System Kernels")
            self.subtitle = self.subtitle or "System Kernel Pruning & Recovery Station"
        elif self.mode == "kernel-prune":
            self.title = self.title or _tr("KERNEL_REMOVAL_TITLE", "Prune / Remove Inactive Installed Kernels")
            self.subtitle = self.subtitle or "Kernel Cleanup Station"

        if custom_items and isinstance(custom_items, list):
            return custom_items

        if self.mode == "sbo-main":
            self.title = self.title or _tr("SBO_MAIN_HUB_TITLE", "SlackBuilds & Third-Party Package Management")
            self.subtitle = self.subtitle or "SlackBuilds & Tweaks Hub"
            return [
                {"id": "1", "label": f"1. {_tr('SBO_MENU_SEARCH_AND_RECOMMENDED', 'Search SBo & Gaming Packages')}"},
                {"id": "2", "label": f"2. {_tr('SBO_MENU_CURATED_SUITE', 'Curated Slacky-SlackBuilds Hub')}"},
                {"id": "3", "label": f"3. {_tr('MENU_OPTIONAL_TWEAKS', 'Optional System & Gaming Tweaks')}"},
                {"id": "4", "label": f"4. {format_exit_label(_tr('CATCH_YOU_FLIP_SIDE', 'Exit / Return'))}"},
            ]
        elif self.mode == "sbo-search":
            self.title = self.title or _tr("SBO_SEARCH_PROMPT_TITLE", "SlackBuilds Search & Installation")
            self.subtitle = self.subtitle or "SlackBuilds.org Query & Deployment Station"
            return [
                {"id": "1", "label": f"1. {_tr('SBO_CUSTOM_SEARCH_OPTION', 'Custom Package Search & Install (sbofind)')}"},
                {"id": "2", "label": f"2. {_tr('SBO_RECOMMENDED_GAMING_OPTION', 'Recommended Gaming Packages')}"},
                {"id": "3", "label": f"3. {format_exit_label(_tr('SBO_BACK_OPTION', 'Return to Previous Menu'))}"},
            ]
        elif self.mode == "sbo-recommended":
            self.title = self.title or _tr("RECOMMENDED_GAMING_TITLE", "Recommended Gaming Packages")
            self.subtitle = self.subtitle or "Curated SBo Gaming Applications"
            return [
                {"id": "1", "label": "1. OBS Studio (multimedia/obs-studio)"},
                {"id": "2", "label": "2. Steam Client (games/steam)"},
                {"id": "3", "label": "3. Discord (network/discord)"},
                {"id": "4", "label": "4. ProtonPlus (games/protonplus)"},
                {"id": "5", "label": f"5. {format_exit_label(_tr('SBO_BACK_OPTION', 'Return to Previous Menu'))}"},
            ]
        elif self.mode == "limine-main":
            self.title = self.title or "Limine Unified UEFI Boot Manager"
            self.subtitle = self.subtitle or "Limine Bootloader & Secure Boot Matrix"
            return [
                {"id": "1", "label": "1. Install / Re-deploy Limine Bootloader (Coexistence Mode)"},
                {"id": "2", "label": "2. Regenerate limine.conf & Re-enroll BLAKE2B Checksums"},
                {
                    "id": "3",
                    "label": "3. 🔍 Verify Kernel BLAKE2B Hashes vs Limine Registry",
                    "ascii_label": "3. [*] Verify Kernel BLAKE2B Hashes vs Limine Registry",
                },
                {
                    "id": "4",
                    "label": "4. ⚙️  Configure Kernel Boot Parameters (CMDLINE & Gaming Hub)",
                    "ascii_label": "4. [*] Configure Kernel Boot Parameters (CMDLINE & Gaming Hub)",
                },
                {
                    "id": "5",
                    "label": "5. 🌲 Snapper Btrfs Snapshot Rollback Engine",
                    "ascii_label": "5. [*] Snapper Btrfs Snapshot Rollback Engine",
                },
                {"id": "6", "label": "6. 1-Click Self-Heal: Restore Limine from Backup"},
                {"id": "7", "label": "7. View / Export Field Guide (PDF / Email / Phone QR)"},
                {"id": "8", "label": f"8. {format_exit_label(_tr('MOK_OPTION_RETURN', 'Return to Main Menu'))}"},
            ]
        elif self.mode == "kernel-main":
            self.title = self.title or "CachyOS Kernel & Hardware Master Suite"
            self.subtitle = self.subtitle or "CachyOS Kernel Management"
            return [
                {"id": "1", "label": "1. Upgrade Installed CachyOS Kernels"},
                {"id": "2", "label": "2. CachyOS Kernel Picker (Explore & Deploy Flavors)"},
                {"id": "3", "label": "3. Manage System Kernels (Inspect & Prune)"},
                {"id": "4", "label": "4. Rebuild Active Kernel Initramfs & NVIDIA Modules"},
                {"id": "5", "label": f"5. {format_exit_label(_tr('MOK_OPTION_RETURN', 'Return to Main Menu'))}"},
            ]
        elif self.mode == "kernel-picker":
            self.title = self.title or "High-Performance CachyOS Kernel Flavor Selector"
            self.subtitle = self.subtitle or "CachyOS Kernel Picker"
            picker_items = [
                ("1", "standard", ["standard", "linux-cachyos", "cachyos"], "1. linux-cachyos (Standard CachyOS optimized kernel)"),
                ("2", "bore", ["bore", "linux-cachyos-bore"], "2. linux-cachyos-bore (BORE scheduler - Burst-Oriented Response Enhancer)"),
                ("3", "lto", ["lto", "bore-lto", "linux-cachyos-bore-lto"], "3. linux-cachyos-bore-lto (BORE + Clang Full LTO)"),
                ("4", "eevdf", ["eevdf", "linux-cachyos-eevdf"], "4. linux-cachyos-eevdf (EEVDF scheduler with gaming patches)"),
                ("5", "bmq", ["bmq", "linux-cachyos-bmq"], "5. linux-cachyos-bmq (Project C BitMap Queue scheduler)"),
                ("6", "deckify", ["deckify", "linux-cachyos-deckify"], "6. linux-cachyos-deckify (Steam Deck & Handheld Gaming)"),
                ("7", "rt-bore", ["rt-bore", "rt", "linux-cachyos-rt-bore"], "7. linux-cachyos-rt-bore (Realtime PREEMPT_RT + BORE)"),
                ("8", "rc", ["rc", "linux-cachyos-rc"], "8. linux-cachyos-rc (Release Candidate Next-Gen Kernel)"),
                ("9", "lts", ["lts", "linux-cachyos-lts"], "9. linux-cachyos-lts (Long Term Support Enterprise Gaming)"),
                ("10", "zen", ["zen", "linux-cachyos-zen", "linux-zen"], "10. linux-zen (Zen gaming tuning)"),
                ("11", "arch", ["arch", "linux"], "11. linux (Arch standard kernel)"),
                ("12", None, [], f"12. {format_exit_label(_tr('CACHY_PICKER_EXIT', 'Return to Previous Menu'))}"),
            ]
            items = []
            for fid, fkey, aliases, flabel in picker_items:
                items.append({
                    "id": fid,
                    "flavor": fkey,
                    "aliases": aliases,
                    "label": flabel,
                })
            return items
        elif self.mode == "kernel-manage":
            self.title = self.title or _tr("KERNEL_MANAGE_SYSTEM_TITLE", "Manage System Kernels")
            self.subtitle = self.subtitle or "System Kernel Pruning & Recovery Station"
            opt1 = re.sub(r'^[0-9]+\.\s*', '', _tr("KERNEL_MANAGE_OPTION_REMOVE", "Prune / Remove Inactive Installed Kernels"))
            opt2 = re.sub(r'^[0-9]+\.\s*', '', _tr("KERNEL_MANAGE_OPTION_RESTORE", "Restore Stock Slackware Huge/Generic Kernel (Emergency Fallback)"))
            opt3 = format_exit_label(_tr("MOK_OPTION_RETURN", "Return to Main Menu"))
            return [
                {"id": "1", "label": f"1. {opt1}"},
                {"id": "2", "label": f"2. {opt2}"},
                {"id": "3", "label": f"3. {opt3}"},
            ]
        elif self.mode == "kernel-prune":
            self.title = self.title or _tr("KERNEL_REMOVAL_TITLE", "Prune / Remove Inactive Installed Kernels")
            self.subtitle = self.subtitle or "Kernel Cleanup Station"
            return []
        elif self.mode == "nvidia-main":
            self.title = self.title or _tr("MENU_NVIDIA_CACHY_TITLE", "CachyOS NVIDIA Master Station")
            self.subtitle = self.subtitle or "NVIDIA Driver & DKMS Management"
            return [
                {"id": "1", "label": f"1. {_tr('NVIDIA_CACHYOS_MASTER_SYNC', '[CachyOS-Master] Full Suite Sync (64-bit, 32-bit Multilib & All Kernels)')}"},
                {"id": "2", "label": f"2. {_tr('NVIDIA_OPTION_REBUILD', 'Rebuild DKMS & sign active modules only')}"},
                {"id": "3", "label": f"3. {_tr('NVIDIA_OPTION_LEGACY_RUN', 'Legacy & Standalone .run Drivers (595, 570, 535, 470, 390)')}"},
                {"id": "4", "label": f"4. {format_exit_label(_tr('NVIDIA_OPTION_RETURN', 'Return to Main Menu'))}"},
            ]
        elif self.mode == "nvidia-legacy":
            self.title = self.title or _tr("MENU_NVIDIA_LEGACY_TITLE", "NVIDIA Legacy .run Drivers")
            self.subtitle = self.subtitle or "Standalone Official NVIDIA Driver Station"
            return [
                {"id": "1", "label": f"1. {_tr('NVIDIA_LEGACY_BRANCH_595', 'NVIDIA 595.x (Latest New Feature / Vulkan Beta)')}"},
                {"id": "2", "label": f"2. {_tr('NVIDIA_LEGACY_BRANCH_570', 'NVIDIA 570.x (Production / Current)')}"},
                {"id": "3", "label": f"3. {_tr('NVIDIA_LEGACY_BRANCH_535', 'NVIDIA 535.x (Long Term Support)')}"},
                {"id": "4", "label": f"4. {_tr('NVIDIA_LEGACY_BRANCH_470', 'NVIDIA 470.x (Legacy Kepler / GTX 600/700)')}"},
                {"id": "5", "label": f"5. {_tr('NVIDIA_LEGACY_BRANCH_390', 'NVIDIA 390.x (Legacy Fermi / GTX 400/500)')}"},
                {"id": "6", "label": f"6. {format_exit_label(_tr('NVIDIA_LEGACY_RETURN', 'Return to Previous Menu'))}"},
            ]
        elif self.mode == "secureboot-main":
            self.title = self.title or "UEFI Secure Boot Control Center (SBCTL & MOK)"
            self.subtitle = self.subtitle or "Cryptographic Signature & Key Armor Station"
            ret_sb = format_exit_label(_tr('MOK_OPTION_RETURN', 'Return to Main Menu'))
            return [
                {
                    "id": "1",
                    "label": "1. 🔍 Audit Secure Boot & Cryptographic Status",
                    "ascii_label": "1. [*] Audit Secure Boot & Cryptographic Status",
                },
                {
                    "id": "2",
                    "label": "2. 🪄 Run 1-Click sbctl Secure Boot Key Enrollment Wizard",
                    "ascii_label": "2. [*] Run 1-Click sbctl Secure Boot Key Enrollment Wizard",
                },
                {
                    "id": "3",
                    "label": "3. 🛡️  Sign All Bootloaders & Linux Kernels with sbctl",
                    "ascii_label": "3. [*] Sign All Bootloaders & Linux Kernels with sbctl",
                },
                {
                    "id": "4",
                    "label": "4. 🔑 Manage Classic MOK (Kernel Module Signatures)",
                    "ascii_label": "4. [*] Manage Classic MOK (Kernel Module Signatures)",
                },
                {
                    "id": "5",
                    "label": f"5. 🚪 {ret_sb}",
                    "ascii_label": f"5. {ret_sb}",
                },
            ]
        elif self.mode == "docs-main":
            self.title = self.title or _tr('DOCS_MENU_TITLE', "Slacky-Update Master Field Guide & Diagnostics")
            self.subtitle = self.subtitle or _tr('DOCS_MENU_SUBTITLE', "System Health Audit, Manuals & Mobile Export")
            ret_docs = format_exit_label(_tr('SBO_BACK_OPTION', 'Return to Previous Menu'))
            return [
                {"id": "1", "label": f"1. 🩺 {_tr('DOCS_OPT_DOCTOR_RUN', 'Run System Health & Diagnostic Audit (Terminal)')}", "ascii_label": f"1. {_tr('DOCS_OPT_DOCTOR_RUN', 'Run System Health & Diagnostic Audit (Terminal)')}"},
                {"id": "2", "label": f"2. 📋 {_tr('DOCS_OPT_DOCTOR_EXPORT', 'Export System Health Report to Markdown (~/slacky-system-health.md)')}", "ascii_label": f"2. {_tr('DOCS_OPT_DOCTOR_EXPORT', 'Export System Health Report to Markdown (~/slacky-system-health.md)')}"},
                {"id": "3", "label": f"3. 📖 {_tr('DOCS_OPT_SURVIVAL', 'Read Master Survival Guide in Terminal')}", "ascii_label": f"3. {_tr('DOCS_OPT_SURVIVAL', 'Read Master Survival Guide in Terminal')}"},
                {"id": "4", "label": f"4. 🛠️  {_tr('DOCS_OPT_COMPANION', 'Read Technical Architecture & Companion Guide in Terminal')}", "ascii_label": f"4. {_tr('DOCS_OPT_COMPANION', 'Read Technical Architecture & Companion Guide in Terminal')}"},
                {"id": "5", "label": f"5. 🚀 {_tr('DOCS_OPT_LIMINE', 'Read Limine & BIOS Playbook in Terminal')}", "ascii_label": f"5. {_tr('DOCS_OPT_LIMINE', 'Read Limine & BIOS Playbook in Terminal')}"},
                {"id": "6", "label": f"6. 🚑 {_tr('DOCS_OPT_TROUBLESHOOT', 'Read Disaster Recovery & Troubleshooting Guide in Terminal')}", "ascii_label": f"6. {_tr('DOCS_OPT_TROUBLESHOOT', 'Read Disaster Recovery & Troubleshooting Guide in Terminal')}"},
                {"id": "7", "label": f"7. 📄 {_tr('DOCS_OPT_PDF', 'Export All Guides to PDF (Save to ~/Documents)')}", "ascii_label": f"7. {_tr('DOCS_OPT_PDF', 'Export All Guides to PDF (Save to ~/Documents)')}"},
                {"id": "8", "label": f"8. ✉️  {_tr('DOCS_OPT_EMAIL', 'Send Survival Guide via Email (Attach PDF in Mail Client)')}", "ascii_label": f"8. {_tr('DOCS_OPT_EMAIL', 'Send Survival Guide via Email (Attach PDF in Mail Client)')}"},
                {"id": "9", "label": f"9. 📱 {_tr('DOCS_OPT_QR', 'Transfer to Phone via Wi-Fi QR Code (Access in BIOS)')}", "ascii_label": f"9. {_tr('DOCS_OPT_QR', 'Transfer to Phone via Wi-Fi QR Code (Access in BIOS)')}"},
                {"id": "10", "label": f"10. 🚪 {ret_docs}", "ascii_label": f"10. {ret_docs}"},
            ]
        return []

    def get_badge(self, it) -> str:
        raw = None
        if "badge" in it and it["badge"]:
            raw = it["badge"]
        elif self.badges:
            flavor = it.get("flavor")
            aliases = it.get("aliases", [])
            if flavor and flavor in self.badges:
                raw = self.badges[flavor]
            else:
                for al in aliases:
                    if al in self.badges:
                        raw = self.badges[al]
                        break
        if not raw:
            return ""

        raw_str = str(raw).strip()
        if '\x1b' in raw_str:
            return raw_str if not self.ascii_only else strip_ansi(raw_str)

        clean = strip_ansi(raw_str).upper()
        if "ACTIVE" in clean or "CANNOT" in clean:
            badge_txt = f"[{clean.strip('[]')}]"
            return f"{BOLD_GREEN}{badge_txt}{RESET}" if not self.ascii_only else badge_txt
        elif "INSTALLED" in clean:
            badge_txt = f"[{clean.strip('[]')}]"
            return f"{BOLD_GREEN}{badge_txt}{RESET}" if not self.ascii_only else badge_txt
        elif "UNSUPPORTED" in clean:
            badge_txt = f"[{clean.strip('[]')}]"
            return f"{BOLD_RED}{badge_txt}{RESET}" if not self.ascii_only else badge_txt
        elif "STOCK" in clean:
            badge_txt = f"[{clean.strip('[]')}]"
            return f"{BOLD_BLUE}{badge_txt}{RESET}" if not self.ascii_only else badge_txt
        elif "CACHY" in clean:
            badge_txt = f"[{clean.strip('[]')}]"
            return f"{BOLD_CYAN}{badge_txt}{RESET}" if not self.ascii_only else badge_txt
        elif "NOT" in clean:
            badge_txt = f"[{clean.strip('[]')}]"
            return f"{BOLD_CYAN}{badge_txt}{RESET}" if not self.ascii_only else badge_txt
        else:
            badge_txt = f"[{clean.strip('[]')}]"
            return f"{BOLD_YELLOW}{badge_txt}{RESET}" if not self.ascii_only else badge_txt

    def render_screen(self):
        self.update_terminal_size()
        lines = []

        # 1. Header (Dark Star styling)
        if self.mode == "limine-main":
            header_top = "Slacky-Update (Limine Bootloader & Secure Boot Matrix)"
            header_sub = self.title or self.subtitle or "Limine Unified UEFI Boot Manager"
        elif self.mode == "kernel-main":
            header_top = "Slacky-Update (CachyOS Kernel Management)"
            header_sub = self.title or self.subtitle or "CachyOS Kernel & Hardware Master Suite"
        elif self.mode == "kernel-picker":
            header_top = "Slacky-Update (CachyOS Kernel Picker)"
            header_sub = self.title or self.subtitle or "High-Performance CachyOS Kernel Flavor Selector"
        elif self.mode == "kernel-manage":
            header_top = "Slacky-Update (Manage System Kernels)"
            header_sub = self.title or self.subtitle or "System Kernel Pruning & Recovery Station"
        elif self.mode == "kernel-prune":
            header_top = "Slacky-Update (Kernel Prune Station)"
            header_sub = self.title or self.subtitle or "Safe Inactive Kernel Removal"
        elif self.mode == "nvidia-main":
            header_top = "Slacky-Update (CachyOS NVIDIA Master Station)"
            header_sub = self.title or self.subtitle or "NVIDIA Driver & DKMS Management"
        elif self.mode == "nvidia-legacy":
            header_top = "Slacky-Update (NVIDIA Legacy .run Drivers)"
            header_sub = self.title or self.subtitle or "Standalone Official NVIDIA Driver Station"
        elif self.mode == "secureboot-main":
            header_top = "Slacky-Update (UEFI Secure Boot Control Center)"
            header_sub = self.title or self.subtitle or "Cryptographic Signature & Key Armor Station"
        elif self.mode == "docs-main":
            header_top = "Slacky-Update (Master Field Guide & Diagnostics)"
            header_sub = self.title or self.subtitle or "System Health Audit, Manuals & Mobile Export"
        else:
            header_top = "Slacky-Update (SlackBuilds & Tweaks)"
            header_sub = self.title or self.subtitle or ""

        lines.append(f"{BOLD_BLUE}{header_top}{RESET}")
        lines.append(f"{BLUE}{header_sub}{RESET}")
        lines.append("")

        # 2. Actions Header
        lines.append(f"{BOLD}{_tr('CLI_ACTIONS_HEADER', 'Select an operation:')}{RESET}")

        # Record starting row for options to handle mouse clicks accurately
        self.options_start_row = len(lines) + 1

        # 3. Options
        items_with_badges = [it for it in self.items if self.get_badge(it)]
        max_lbl_w = max(str_display_width(it.get("ascii_label") if (self.ascii_only and "ascii_label" in it) else it["label"]) for it in items_with_badges) if items_with_badges else 0

        for i, it in enumerate(self.items):
            is_sel = (i == self.selected_idx)
            lbl = it.get("ascii_label") if (self.ascii_only and "ascii_label" in it) else it["label"]
            badge = self.get_badge(it)
            cur = ">" if self.ascii_only else "▶"
            if badge:
                lbl_w = str_display_width(lbl)
                badge_w = str_display_width(badge)
                if max_lbl_w + badge_w + 6 <= self.cols:
                    pad = " " * max(2, max_lbl_w - lbl_w + 2)
                else:
                    pad = " "
                if is_sel:
                    lines.append(f"  {BOLD_CYAN}{cur}{RESET} {BOLD_CYAN}{lbl}{RESET}{pad}{badge}")
                else:
                    lines.append(f"    {lbl}{pad}{badge}")
            else:
                if is_sel:
                    lines.append(f"  {BOLD_CYAN}{cur}{RESET} {BOLD_CYAN}{lbl}{RESET}")
                else:
                    lines.append(f"    {lbl}")

        # 4. Prompt line & Navigation Hint
        lines.append("")
        default_hint = "[*] Click or [1-{range}] to select | Hold Shift + Drag to copy text | (ESC) Exit" if self.ascii_only else "💡 Click or [1-{range}] to select  •  Hold Shift + Drag to copy text  •  (ESC) Exit"
        hint_text = _tr("TUI_NAV_HINT_COPY", default_hint).replace("{range}", str(len(self.items)))
        lines.append(f"  {DIM_WHITE}{hint_text}{RESET}")
        prompt_prefix = _tr("SELECT_OPERATION_RANGE", "Enter choice [{range}]: ").replace("{range}", f"1-{len(self.items)}")
        prompt_line = f"{prompt_prefix}{self.input_buffer}"
        lines.append(prompt_line)

        prompt_row = len(lines)
        prompt_col = 1 + str_display_width(prompt_line)
        self.render_frame(lines, cursor_pos=(prompt_row, prompt_col))

    def run_interactive(self):
        with self.raw_term:
            need_render = True
            while True:
                if need_render or self.resized:
                    self.render_screen()
                    need_render = False
                    self.resized = False

                r, _, _ = select.select([self.raw_term.term_in_fd], [], [], 0.05)
                if not r:
                    self.update_terminal_size()
                    continue

                try:
                    data = os.read(self.raw_term.term_in_fd, 1024)
                except Exception:
                    break

                if not data:
                    break

                events = parse_input_bytes(data)
                if events:
                    need_render = True

                for ev in events:
                    ev_type = ev[0]
                    if ev_type == 'key':
                        key = ev[1]
                        if key == 'up':
                            self.selected_idx = max(0, self.selected_idx - 1)
                        elif key == 'down':
                            self.selected_idx = min(len(self.items) - 1, self.selected_idx + 1)
                        elif key == 'backspace':
                            if self.input_buffer:
                                self.input_buffer = self.input_buffer[:-1]
                        elif key in ('escape', 'ctrl_c'):
                            return self.items[-1]["id"]  # Exit / Return
                        elif key == 'enter':
                            if self.input_buffer.strip():
                                buf = self.input_buffer.strip()
                                for it_idx, it in enumerate(self.items):
                                    if it["id"] == buf:
                                        return buf
                            return self.items[self.selected_idx]["id"]

                    elif ev_type == 'char':
                        ch = ev[1]
                        if ch.upper() == 'Q':
                            return self.items[-1]["id"]
                        if ch.isdigit():
                            has_multidigit = any(len(it["id"]) > 1 for it in self.items)
                            if not has_multidigit:
                                d = int(ch)
                                for it_idx, it in enumerate(self.items):
                                    if it["id"] == str(d):
                                        self.selected_idx = it_idx
                                        return str(d)
                                self.input_buffer = ch
                            else:
                                new_buf = self.input_buffer + ch
                                matching_ids = [it["id"] for it in self.items if it["id"].startswith(new_buf)]
                                exact_match = any(it["id"] == new_buf for it in self.items)
                                if exact_match and len(matching_ids) == 1:
                                    self.input_buffer = new_buf
                                    for it_idx, it in enumerate(self.items):
                                        if it["id"] == new_buf:
                                            self.selected_idx = it_idx
                                            break
                                    return new_buf
                                elif exact_match and len(matching_ids) > 1:
                                    self.input_buffer = new_buf
                                    for it_idx, it in enumerate(self.items):
                                        if it["id"] == new_buf:
                                            self.selected_idx = it_idx
                                            break
                                elif matching_ids:
                                    self.input_buffer = new_buf
                                else:
                                    self.input_buffer = ch
                                    single_matches = [it["id"] for it in self.items if it["id"].startswith(ch)]
                                    if len(single_matches) == 1 and single_matches[0] == ch:
                                        for it_idx, it in enumerate(self.items):
                                            if it["id"] == ch:
                                                self.selected_idx = it_idx
                                                break
                                        return ch

                    elif ev_type == 'mouse':
                        btn, x, y, release = ev[1], ev[2], ev[3], ev[4]
                        if btn == 0 and not release:
                            row_idx = y - self.options_start_row
                            if 0 <= row_idx < len(self.items):
                                return self.items[row_idx]["id"]

        return self.items[-1]["id"] if self.items else "1"

# --- [ SYSTEM STORAGE SCANNER FOR CLEAN TUI ] ---
def scan_system_cleanup_storage():
    """
    Sub-50ms rapid storage scanner for system maintenance.
    Calculates recoverable bytes across package caches, build artifacts,
    inactive kernels, and logs without touching /home.
    """
    start_t = time.time()

    def get_dir_size(path):
        total = 0
        if os.path.exists(path):
            if os.path.isfile(path) and not os.path.islink(path):
                try:
                    return os.path.getsize(path)
                except Exception:
                    return 0
            for root, dirs, files in os.walk(path):
                for f in files:
                    fp = os.path.join(root, f)
                    try:
                        if not os.path.islink(fp):
                            total += os.path.getsize(fp)
                    except Exception:
                        pass
        return total

    def get_glob_size(patterns):
        total = 0
        for pat in patterns:
            for p in glob.glob(pat):
                total += get_dir_size(p)
        return total

    def format_size(bytes_val):
        if bytes_val >= 1024 * 1024 * 1024:
            return f"{bytes_val / (1024**3):.2f} GB"
        elif bytes_val >= 1024 * 1024:
            return f"{bytes_val / (1024**2):.1f} MB"
        elif bytes_val >= 1024:
            return f"{bytes_val / 1024:.1f} KB"
        else:
            return f"{bytes_val} B"

    # 1. Package Caches
    pkg_cache_dirs = [
        "/var/cache/slacky-update", "/var/cache/sbopkg",
        "/var/cache/slackpkg", "/var/cache/gnomes",
        "/opt/underpants/cache"
    ]
    pkg_cache_bytes = sum(get_dir_size(p) for p in pkg_cache_dirs)

    # 2. Ephemeral Build Artifacts
    build_patterns = [
        "/tmp/slacky-build-*", "/tmp/slacky-staging-*", "/tmp/slacky-rocm-*",
        "/tmp/slacky-sign-*", "/tmp/slacky-snap-*", "/tmp/slacky-gnome*",
        "/tmp/dracut-*", "/var/tmp/slacky-initrd-tree*", "/tmp/initrd-tree-*",
        "/tmp/SBo/*", "/tmp/build-*", "/tmp/package-*", "/tmp/transmute-gnomes-*",
        "/tmp/underpants-*.txz", "/tmp/underpants-*.part"
    ]
    build_temp_bytes = get_glob_size(build_patterns)

    # 3. Kernel Artifacts (inactive beyond retention)
    def get_flavor(k_str):
        if "-cachyos-bore-lto" in k_str or "-cachyos-lto" in k_str: return "lto"
        elif "-cachyos-rt-bore" in k_str or "-cachyos-rt" in k_str: return "rt-bore"
        elif "-cachyos-bore" in k_str: return "bore"
        elif "-cachyos-eevdf" in k_str: return "eevdf"
        elif "-cachyos-bmq" in k_str: return "bmq"
        elif "-cachyos-deckify" in k_str: return "deckify"
        elif "-cachyos-rc" in k_str: return "rc"
        elif "-cachyos-lts" in k_str: return "lts"
        elif "-cachyos" in k_str: return "standard"
        elif "-zen" in k_str: return "zen"
        return "other"

    def parse_ver(v_str):
        nums = [int(x) for x in re.findall(r'\d+', v_str)]
        return nums if nums else [0]

    custom_k = set()
    for mdir in ("/lib/modules", "/usr/lib/modules"):
        if os.path.exists(mdir):
            try:
                for d in os.listdir(mdir):
                    if "cachyos" in d or "-zen" in d:
                        custom_k.add(d)
            except Exception:
                pass

    active = os.uname().release
    by_flv = defaultdict(list)
    for k in custom_k:
        by_flv[get_flavor(k)].append(k)

    to_keep = {active}
    for flv, klist in by_flv.items():
        sorted_k = sorted(klist, key=parse_ver, reverse=True)
        limit = 1 if flv == "rc" else 2
        to_keep.update(sorted_k[:limit])

    to_remove_k = [k for k in custom_k if k not in to_keep]
    kernel_reclaim_bytes = 0
    for k in to_remove_k:
        kernel_reclaim_bytes += get_dir_size(f"/lib/modules/{k}")
        kernel_reclaim_bytes += get_dir_size(f"/usr/lib/modules/{k}")
        kernel_reclaim_bytes += get_dir_size(f"/usr/src/linux-headers-{k}")
        for pat in [f"/boot/vmlinuz-{k}", f"/boot/initramfs-{k}.img", f"/boot/initrd-{k}.img"]:
            if os.path.exists(pat):
                try:
                    kernel_reclaim_bytes += os.path.getsize(pat)
                except Exception:
                    pass

    # 4. Logs & Temp checks
    log_patterns = ["/tmp/slacky-update-check.*", "/tmp/wget-log*"]
    log_temp_bytes = get_glob_size(log_patterns)

    caches_total_bytes = pkg_cache_bytes + build_temp_bytes + log_temp_bytes
    total_reclaimable_bytes = caches_total_bytes + kernel_reclaim_bytes

    duration = max(0.01, time.time() - start_t)

    return {
        "duration": duration,
        "pkg_cache_bytes": pkg_cache_bytes,
        "pkg_cache_str": format_size(pkg_cache_bytes),
        "build_temp_bytes": build_temp_bytes,
        "build_temp_str": format_size(build_temp_bytes),
        "kernel_reclaim_bytes": kernel_reclaim_bytes,
        "kernel_reclaim_count": len(to_remove_k),
        "kernel_reclaim_str": format_size(kernel_reclaim_bytes),
        "log_temp_bytes": log_temp_bytes,
        "log_temp_str": format_size(log_temp_bytes),
        "caches_total_bytes": caches_total_bytes,
        "caches_total_str": format_size(caches_total_bytes),
        "total_reclaimable_bytes": total_reclaimable_bytes,
        "total_str": format_size(total_reclaimable_bytes),
        "pkg_cache": {"bytes": pkg_cache_bytes, "formatted": format_size(pkg_cache_bytes)},
        "build_temp": {"bytes": build_temp_bytes, "formatted": format_size(build_temp_bytes)},
        "old_kernels": {"bytes": kernel_reclaim_bytes, "formatted": format_size(kernel_reclaim_bytes)},
        "logs_dumps": {"bytes": log_temp_bytes, "formatted": format_size(log_temp_bytes)},
        "total": {"bytes": total_reclaimable_bytes, "formatted": format_size(total_reclaimable_bytes)},
    }

class CleanMenuItem(dict):
    def __contains__(self, key):
        if super().__contains__(key):
            return True
        if isinstance(key, str):
            return key in self.get("label", "") or key in self.get("id", "")
        return False

# --- [ SYSTEM MAINTENANCE & CLEAN TUI ] ---
class CleanTUI(SimpleSelectTUI):
    """
    CleanTUI: System Maintenance & Storage Analysis TUI.
    - Features a live Storage Breakdown Card.
    - Interactive cursor navigation (▶ / bold cyan) and mouse selection.
    - Strict per-row absolute positioning (\033[{row};1H\033[2K) - ZERO STAIRCASE.
    - Universal ESC exits cleanly to Main Menu.
    """
    def __init__(self, ascii_only=False, enable_mouse=True):
        self.scan_data = scan_system_cleanup_storage()
        super().__init__(mode="clean",
                         title=_tr("CLEAN_MENU_TITLE", "Slacky-Update (System Maintenance & Storage Analysis)"),
                         subtitle=_tr("CLEAN_MENU_SUBTITLE", "High-Performance System Hygenics & Disk Space Recovery"),
                         ascii_only=ascii_only, enable_mouse=enable_mouse)

    def init_items(self, custom_items):
        if custom_items and isinstance(custom_items, list):
            return custom_items

        tot_str = self.scan_data["total_str"]
        caches_str = self.scan_data["caches_total_str"]
        k_str = self.scan_data["kernel_reclaim_str"]
        k_cnt = self.scan_data["kernel_reclaim_count"]
        k_desc = f"{k_str} ({k_cnt} inactive)" if k_cnt > 0 else "0 B (Clean)"

        opt1_lbl = _tr("CLEAN_OPT_SWEEP", "🚀 Full System Sweep (Recommended — Free {tot})").replace("{tot}", tot_str)
        opt2_lbl = _tr("CLEAN_OPT_CACHES", "📦 Clean Package & Build Caches Only (Free {caches})").replace("{caches}", caches_str)
        opt3_lbl = _tr("CLEAN_OPT_KERNELS", "🐧 Prune Obsolete Kernels (Safe Retention Guard: {k_info})").replace("{k_info}", k_desc)
        opt4_lbl = _tr("CLEAN_OPT_FLATPAK", "📦 Prune Unused Flatpak Runtimes")
        opt5_lbl = _tr("CLEAN_OPT_DEDUP", "🧙 Underpants Gnomes Storage Deduplication (gnomes dedup)")
        opt6_lbl = format_exit_label(_tr("MOK_OPTION_RETURN", "Return to Main Menu"))

        return [
            CleanMenuItem({"id": "1", "label": f"1. {opt1_lbl}", "ascii_label": f"1. [*] Full System Sweep (Recommended - Free {tot_str})"}),
            CleanMenuItem({"id": "2", "label": f"2. {opt2_lbl}", "ascii_label": f"2. [*] Clean Package & Build Caches Only (Free {caches_str})"}),
            CleanMenuItem({"id": "3", "label": f"3. {opt3_lbl}", "ascii_label": f"3. [*] Prune Obsolete Kernels (Safe Retention Guard: {k_desc})"}),
            CleanMenuItem({"id": "4", "label": f"4. {opt4_lbl}", "ascii_label": "4. [*] Prune Unused Flatpak Runtimes"}),
            CleanMenuItem({"id": "5", "label": f"5. {opt5_lbl}", "ascii_label": "5. [*] Underpants Gnomes Storage Deduplication (gnomes dedup)"}),
            CleanMenuItem({"id": "6", "label": f"6. {opt6_lbl}"}),
        ]

    def render_screen(self):
        self.update_terminal_size()
        lines = []

        # 1. Header
        header_top = "Slacky-Update (System Maintenance & Storage Analysis)"
        header_sub = "High-Performance System Hygenics & Disk Space Recovery"
        lines.append(f"{BOLD_BLUE}{header_top}{RESET}")
        lines.append(f"{BLUE}{header_sub}{RESET}")
        check_sym = "*" if self.ascii_only else "✓"
        dur = self.scan_data.get("duration", 0.05)
        lines.append(f"  {GREEN}{check_sym} Storage analysis completed in {dur:.2f}s{RESET}")
        lines.append("")

        # 2. Storage Breakdown Card
        w = max(40, min(self.cols - 2, 79))
        tl, tr, bl, br, hz, vt = ("+", "+", "+", "+", "-", "|") if self.ascii_only else ("┌", "┐", "└", "┘", "─", "│")
        ml, mr = ("+", "+") if self.ascii_only else ("├", "┤")

        top_border = f"{CYAN}{tl}{hz * (w - 2)}{tr}{RESET}"
        mid_border = f"{CYAN}{ml}{hz * (w - 2)}{mr}{RESET}"
        bot_border = f"{CYAN}{bl}{hz * (w - 2)}{br}{RESET}"

        def make_card_row(content_str):
            if str_display_width(content_str) > w - 4:
                content_str = truncate_ansi(content_str, w - 4)
            vis_w = str_display_width(content_str)
            pad_len = max(0, w - 2 - vis_w - 2)
            return f"{CYAN}{vt}{RESET} {content_str}{' ' * pad_len} {CYAN}{vt}{RESET}"

        lines.append(top_border)
        lines.append(make_card_row(f"{BOLD}{_tr('CLEAN_CARD_HEADER', 'RECOVERABLE STORAGE BREAKDOWN')}{RESET}"))

        c_pkg = self.scan_data["pkg_cache_str"]
        c_bld = self.scan_data["build_temp_str"]
        k_cnt = self.scan_data["kernel_reclaim_count"]
        c_krn = f"{self.scan_data['kernel_reclaim_str']} ({k_cnt} inactive)" if k_cnt > 0 else "0 B (Clean)"
        c_log = self.scan_data["log_temp_str"]
        c_tot = self.scan_data["total_str"]

        lines.append(make_card_row(f"├── 📦 {_tr('CLEAN_CARD_PKG_CACHES', 'Package Caches (Slackware .txz, SBo, Gnomes):')} {BOLD_WHITE}{c_pkg}{RESET}"))
        lines.append(make_card_row(f"├── 🛠️  {_tr('CLEAN_CARD_BUILD_TEMPS', 'Ephemeral Build Artifacts (/tmp/slacky-build-*):')} {BOLD_WHITE}{c_bld}{RESET}"))
        lines.append(make_card_row(f"├── 🐧 {_tr('CLEAN_CARD_KERNELS', 'Obsolete Kernel Artifacts:')} {BOLD_WHITE}{c_krn}{RESET}"))
        lines.append(make_card_row(f"├── 📦 {_tr('CLEAN_CARD_FLATPAK', 'Unused Flatpak Runtimes & SDKs:')} {DIM_WHITE}(Scanned on Demand){RESET}"))
        lines.append(make_card_row(f"└── 📄 {_tr('CLEAN_CARD_LOGS', 'Stale Logs & Check Dumps:')} {BOLD_WHITE}{c_log}{RESET}"))
        lines.append(mid_border)
        lines.append(make_card_row(f"✨ {BOLD_YELLOW}{_tr('CLEAN_CARD_TOTAL', 'Total Recoverable Disk Space:')} {BOLD_GREEN}{c_tot}{RESET}"))
        lines.append(make_card_row(f"🛡️  {DIM_WHITE}{_tr('CLEAN_CARD_SAFE_ZONE', 'Safe Zone Guarantee: /home and personal files are 100% immune.')}{RESET}"))
        lines.append(bot_border)
        lines.append("")

        # 3. Actions Header
        lines.append(f"{BOLD}{_tr('CLI_ACTIONS_HEADER', 'Select an operation:')}{RESET}")

        # Record starting row for options to handle mouse clicks accurately
        self.options_start_row = len(lines) + 1

        # 4. Options
        for i, it in enumerate(self.items):
            is_sel = (i == self.selected_idx)
            lbl = it.get("ascii_label") if (self.ascii_only and "ascii_label" in it) else it["label"]
            cur = ">" if self.ascii_only else "▶"
            if is_sel:
                lines.append(f"  {BOLD_CYAN}{cur}{RESET} {BOLD_CYAN}{lbl}{RESET}")
            else:
                lines.append(f"    {lbl}")

        # 5. Prompt line & Navigation Hint
        lines.append("")
        default_hint = "[*] Click or [1-{range}] to select | Hold Shift + Drag to copy text | (ESC) Exit" if self.ascii_only else "💡 Click or [1-{range}] to select  •  Hold Shift + Drag to copy text  •  (ESC) Exit"
        hint_text = _tr("TUI_NAV_HINT_COPY", default_hint).replace("{range}", str(len(self.items)))
        lines.append(f"  {DIM_WHITE}{hint_text}{RESET}")
        prompt_prefix = _tr("SELECT_OPERATION_RANGE", "Enter choice [{range}]: ").replace("{range}", f"1-{len(self.items)}")
        prompt_line = f"{prompt_prefix}{self.input_buffer}"
        lines.append(prompt_line)

        prompt_row = len(lines)
        prompt_col = 1 + str_display_width(prompt_line)
        self.render_frame(lines, cursor_pos=(prompt_row, prompt_col))

# --- [ UNDERPANTS GNOMES MASTER SUITE TUI ] ---
class GnomesTUI(SlackyTUI):
    """
    Underpants Gnomes TUI: 100% True to the Original lib/mod_gaming.sh CLI.
    - Header and Footer Dock stay fixed (pinned).
    - Middle category area scrolls line-by-line.
    - Categories start COLLAPSED by default.
    - Exact 2-column grid when expanded.
    """
    def __init__(self, data=None, ascii_only=False, enable_mouse=True):
        super().__init__(mode="gnomes", ascii_only=ascii_only, enable_mouse=enable_mouse)
        self.categories = []
        self.installed_map = detect_installed_packages()
        self.idx_to_item = {}
        self.id_to_item = {}
        self.checked_indices = set()
        self.install_btn_row = 0
        self.install_btn_col_start = 0
        self.install_btn_col_end = 0
        self.init_data(data)

        # Nav state
        self.sel_cat_idx = 0
        self.sel_item_id = None
        self.visible_lines = []
        self.scroll_offset = 0

    def init_data(self, data):
        """Initializes categories and items. CRITICAL: All categories start COLLAPSED by default."""
        self.idx_to_item.clear()
        self.id_to_item.clear()

        if data and isinstance(data, list):
            self.categories = data
            for cat in self.categories:
                cat["expanded"] = False  # Enforce collapsed by default
                for it in cat.get("items", []):
                    if "idx" in it:
                        self.idx_to_item[it["idx"]] = it
                    if "id" in it:
                        self.id_to_item[it["id"]] = it
            return

        raw_catalog = load_gnomes_catalog()
        cat_buckets = {}
        for entry in raw_catalog:
            ckey = entry["cat"]
            if ckey not in cat_buckets:
                cat_buckets[ckey] = []
            cur_ver = self.installed_map.get(entry["id"], None)
            entry["ver"] = cur_ver
            entry["status"] = "INSTALLED" if cur_ver else "NOT_INSTALLED"
            cat_buckets[ckey].append(entry)

        # Build ordered category objects
        idx_counter = 1
        self.categories = []
        titles_map = DEFAULT_CAT_TITLES_ASCII if self.ascii_only else DEFAULT_CAT_TITLES

        for ckey in DEFAULT_CAT_ORDER:
            if ckey not in cat_buckets or not cat_buckets[ckey]:
                continue
            cat_items = cat_buckets[ckey]
            for it in cat_items:
                it["idx"] = idx_counter
                self.idx_to_item[idx_counter] = it
                self.id_to_item[it["id"]] = it
                idx_counter += 1

            inst_count = sum(1 for it in cat_items if it["status"] == "INSTALLED")
            self.categories.append({
                "key": ckey,
                "title": titles_map.get(ckey, f"[{ckey.upper()}]"),
                "items": cat_items,
                "installed_count": inst_count,
                "total_count": len(cat_items),
                "expanded": False  # MUST start COLLAPSED by default
            })

    def get_all_items(self):
        items = []
        for cat in self.categories:
            items.extend(cat["items"])
        return items

    def toggle_item(self, it):
        """Toggles checkbox state for an item and synchronizes input buffer."""
        idx = it["idx"]
        if idx in self.checked_indices:
            self.checked_indices.remove(idx)
        else:
            self.checked_indices.add(idx)
        self.sync_buffer_from_checked()

    def toggle_item_by_id(self, item_id):
        it = self.id_to_item.get(item_id)
        if it:
            self.toggle_item(it)

    def sync_buffer_from_checked(self):
        """Updates input_buffer to reflect currently checked items."""
        if not self.checked_indices:
            self.input_buffer = ""
        else:
            self.input_buffer = " ".join(str(i) for i in sorted(self.checked_indices))

    def sync_checked_from_buffer(self):
        """Updates checked_indices from input_buffer tokens."""
        total_pkgs = len(self.get_all_items())
        self.checked_indices = parse_indices_from_text(self.input_buffer, total_pkgs)

    def get_selected_indices_str(self) -> str:
        """Returns space-separated string of selected package indices e.g. '1 3 5 14'."""
        if not self.checked_indices:
            return ""
        return " ".join(str(i) for i in sorted(self.checked_indices))

    def format_menu_dock_line(self) -> str:
        """Formats 'Packages selected for installation: <pkgs>       [Install]' footer dock line."""
        btn_text = "[Install Now]"
        dim_btn_text = "[Install]"
        lbl_menu = _tr("TUI_PACKAGES_SELECTED", "Packages selected for installation:")
        prefix = f" {BOLD}{lbl_menu}{RESET} "
        prefix_plain = f" {lbl_menu} "

        if self.checked_indices:
            selected_ids = [self.idx_to_item[i]["id"] for i in sorted(self.checked_indices) if i in self.idx_to_item]
            list_str = " ".join(selected_ids)
            btn_styled = f"{BOLD_GREEN}{btn_text}{RESET}"
            btn_w = str_display_width(btn_text)

            avail_w = max(10, self.cols - str_display_width(prefix_plain) - btn_w - 2)
            if str_display_width(list_str) > avail_w:
                list_styled = f"{BOLD_GREEN}{truncate_ansi(list_str, avail_w)}{RESET}"
                content_w = str_display_width(prefix_plain) + avail_w
            else:
                list_styled = f"{BOLD_GREEN}{list_str}{RESET}"
                content_w = str_display_width(prefix_plain) + str_display_width(list_str)

            pad_w = max(1, self.cols - content_w - btn_w - 1)
            self.install_btn_col_start = self.cols - btn_w
            self.install_btn_col_end = self.cols
            return f"{prefix}{list_styled}{' ' * pad_w}{btn_styled} "
        else:
            empty_msg = f"({_tr('TUI_NO_PKGS_SELECTED', 'no packages selected')})"
            list_styled = f"{DIM}{empty_msg}{RESET}"
            content_w = str_display_width(prefix_plain) + str_display_width(empty_msg)

            btn_styled = f"{DIM}{dim_btn_text}{RESET}"
            btn_w = str_display_width(dim_btn_text)

            pad_w = max(1, self.cols - content_w - btn_w - 1)
            self.install_btn_col_start = self.cols - btn_w
            self.install_btn_col_end = self.cols
            return f"{prefix}{list_styled}{' ' * pad_w}{btn_styled} "

    def jump_to_number(self, num: int):
        """Jumps highlight in real-time to the item matching num, expanding its category."""
        for c_idx, cat in enumerate(self.categories):
            for it in cat["items"]:
                if it["idx"] == num:
                    cat["expanded"] = True  # Auto-expand to reveal item
                    self.sel_cat_idx = c_idx
                    self.sel_item_id = it["id"]
                    return True
        return False

    def build_visible_lines(self):
        """Builds flattened visible representation based on category expanded states."""
        self.visible_lines = []
        use_2col = (self.cols >= 80)

        for c_idx, cat in enumerate(self.categories):
            self.visible_lines.append({
                "type": "cat",
                "cat_idx": c_idx,
                "cat": cat
            })

            if not cat["expanded"]:
                continue

            items = cat["items"]
            if use_2col:
                for i in range(0, len(items), 2):
                    row_items = [items[i]]
                    if i + 1 < len(items):
                        row_items.append(items[i + 1])
                    self.visible_lines.append({
                        "type": "item_row",
                        "cat_idx": c_idx,
                        "items": row_items
                    })
            else:
                for it in items:
                    self.visible_lines.append({
                        "type": "item_row",
                        "cat_idx": c_idx,
                        "items": [it]
                    })

    def format_item_col(self, it, is_sel: bool, col_num: int, name_w: int) -> str:
        """Formats a single package column adhering strictly to original CLI badge style."""
        arrow_sym = ">" if self.ascii_only else "▶"
        check_sym = "*" if self.ascii_only else "✓"
        is_checked = (it["idx"] in self.checked_indices)

        # Prefix indentation (col 1 and col 2: 3 cells with cursor arrow)
        if is_sel:
            prefix = f" {BOLD_CYAN}{arrow_sym}{RESET} "
        else:
            prefix = "   "

        # Checkbox formatting
        if is_checked:
            box_str = f"{BOLD_GREEN}[x]{RESET}"
        else:
            box_str = f"{DIM}[ ]{RESET}"

        idx_str = f"{it['idx']:>2}."
        if is_sel:
            idx_formatted = f"{BOLD_CYAN}{idx_str}{RESET}"
        else:
            idx_formatted = f"{BOLD}{idx_str}{RESET}"

        # Badge formatting
        if it.get("status") == "UPDATE_READY":
            badge = f"{BOLD_YELLOW}[UPDATE READY]{RESET}"
        elif it.get("status") == "INSTALLED":
            ver = it.get("ver") or "Inst"
            if ver == "INSTALLED":
                sv = "Inst"
            elif len(ver) > 6:
                sv = ver[:5] + ("*" if self.ascii_only else "…")
            else:
                sv = ver
            badge = f"{GREEN}[v{sv} {check_sym}]{RESET}"
        else:
            badge = f"{RED}[Not Inst]{RESET}"

        raw_name = it["name"]
        trunc_name = truncate_ansi(raw_name, name_w)
        pad = " " * max(0, name_w - str_display_width(trunc_name))

        if is_sel:
            name_display = f"{BOLD_WHITE}{trunc_name}{RESET}{pad}"
        else:
            name_display = f"{trunc_name}{pad}"

        return f"{prefix}{box_str}  {idx_formatted} {name_display} {badge}"

    def render_screen(self):
        self.update_terminal_size()
        self.build_visible_lines()

        total_visible = len(self.visible_lines)
        header_h = 2

        # 1. Clean Corporate Header (No ANSI borders or emojis)
        frame_rows = []
        frame_rows.append(f" {BOLD_WHITE}Slacky Curated Software:{RESET} {DIM_WHITE}Premium verified software tried, tested and optimized{RESET}")
        frame_rows.append("")

        # 2. Unified Footer Blocks & Universal Navigation Line
        total_pkgs = len(self.get_all_items())
        tab_instruction = f"{BOLD_CYAN}[TAB/Click]{RESET} {BOLD_WHITE}{_tr('TUI_TAB_CHECK', 'Check package')}{RESET}"
        enter_instruction = f"{BOLD_CYAN}[Enter]{RESET} {BOLD_WHITE}{_tr('TUI_INSTALL', 'Install')}{RESET}"

        footer_blocks = [
            f" {BOLD}Batch & Automation Actions:{RESET}  {DIM}•{RESET}  {tab_instruction}  {DIM}•{RESET}  {enter_instruction}",
            f"  {BOLD_CYAN}O.{RESET}  Install full OBS streaming and creation suite",
            f"  {BOLD_CYAN}U.{RESET}  Synchronize & Upgrade All Installed Gaming Packages",
            f"  {BOLD_CYAN}D.{RESET}  Uninstall a Component",
            self.format_menu_dock_line(),
            f"Enter your choice here (manual mode) [1-{total_pkgs}, O, U, D]: {self.input_buffer}",
            f"{BOLD_CYAN}[↑/↓]{RESET} Navigate   {BOLD_CYAN}[Enter]{RESET} Select   {BOLD_YELLOW}[Shift + Drag]{RESET} Copy Text   {BOLD_MAGENTA}[Super + Drag/Click]{RESET} Move/Resize   {BOLD_CYAN}[ESC / q]{RESET} Exit"
        ]
        footer_h = len(footer_blocks)

        # 3. Dynamic Height Budgeting: Top-Anchored Push-Down with Viewport Scroll
        required_rows = header_h + total_visible + footer_h
        if required_rows <= self.rows:
            viewport_h = total_visible
            self.scroll_offset = 0
            self.is_viewport_scrolling = False
        else:
            viewport_h = max(2, self.rows - header_h - footer_h)
            self.is_viewport_scrolling = True

            # Target line for active selection
            target_line = 0
            for idx, entry in enumerate(self.visible_lines):
                if entry["type"] == "cat" and entry["cat_idx"] == self.sel_cat_idx and self.sel_item_id is None:
                    target_line = idx
                    break
                elif entry["type"] == "item_row" and entry["cat_idx"] == self.sel_cat_idx:
                    for it in entry["items"]:
                        if it["id"] == self.sel_item_id:
                            target_line = idx
                            break

            max_scroll = max(0, total_visible - viewport_h)
            if target_line < self.scroll_offset:
                self.scroll_offset = target_line
            elif target_line >= self.scroll_offset + viewport_h:
                self.scroll_offset = target_line - viewport_h + 1
            self.scroll_offset = max(0, min(self.scroll_offset, max_scroll))

        # 4. Viewport Rows
        use_2col = (self.cols >= 80)
        if use_2col:
            avail_per_col = self.cols // 2
            name_w = max(14, min(24, avail_per_col - 24))
        else:
            name_w = max(16, self.cols - 25)

        for v_idx in range(viewport_h):
            l_idx = self.scroll_offset + v_idx
            if l_idx >= total_visible:
                frame_rows.append("")
                continue

            entry = self.visible_lines[l_idx]
            if entry["type"] == "cat":
                cat = entry["cat"]
                is_sel = (entry["cat_idx"] == self.sel_cat_idx and self.sel_item_id is None)
                arrow_sym = ">" if self.ascii_only else "▶"
                cur_prefix = f" {BOLD_CYAN}{arrow_sym}{RESET} " if is_sel else "   "

                if self.ascii_only:
                    state_sym = "v" if cat["expanded"] else ">"
                else:
                    state_sym = "▾" if cat["expanded"] else "▸"

                state_color = BOLD_YELLOW if cat["expanded"] else BOLD_CYAN
                cat_title = cat["title"]
                count_str = f"[{cat['installed_count']}/{cat['total_count']} installed]"

                row_str = f"{cur_prefix}{state_color}{state_sym}{RESET} {BOLD_CYAN}── {cat_title}{RESET} {DIM}{count_str}{RESET} {BOLD_CYAN}──{RESET}"
                frame_rows.append(row_str)

            elif entry["type"] == "item_row":
                items = entry["items"]
                it1 = items[0]
                sel1 = (entry["cat_idx"] == self.sel_cat_idx and self.sel_item_id == it1["id"])
                c1 = self.format_item_col(it1, sel1, col_num=1, name_w=name_w)

                if use_2col and len(items) > 1:
                    it2 = items[1]
                    sel2 = (entry["cat_idx"] == self.sel_cat_idx and self.sel_item_id == it2["id"])
                    c2 = self.format_item_col(it2, sel2, col_num=2, name_w=name_w)
                    c1_padded = pad_ansi(c1, self.cols // 2)
                    c2_padded = pad_ansi(c2, self.cols - (self.cols // 2))
                    frame_rows.append(f"{c1_padded}{c2_padded}")
                else:
                    frame_rows.append(c1)

        # 5. Append Footer Blocks & Track Action Rows
        self.action_rows = {}
        self.viewport_height_rendered = viewport_h
        for idx, blk in enumerate(footer_blocks):
            row_num = len(frame_rows) + 1
            if idx == 1:
                self.action_rows["O"] = row_num
            elif idx == 2:
                self.action_rows["U"] = row_num
            elif idx == 3:
                self.action_rows["D"] = row_num
            elif idx == 4:
                self.install_btn_row = row_num
            frame_rows.append(blk)

        prompt_line = footer_blocks[5]
        prompt_row = len(frame_rows) - 1
        prompt_col = 1 + str_display_width(prompt_line)
        self.render_frame(frame_rows, cursor_pos=(prompt_row, prompt_col))

    def move_selection(self, dy: int):
        """Navigates vertically through category headers and items."""
        cat = self.categories[self.sel_cat_idx]
        use_2col = (self.cols >= 80)

        if self.sel_item_id is None:
            # On category header
            if dy > 0:
                if cat["expanded"] and cat["items"]:
                    self.sel_item_id = cat["items"][0]["id"]
                else:
                    self.sel_cat_idx = min(len(self.categories) - 1, self.sel_cat_idx + 1)
            elif dy < 0:
                if self.sel_cat_idx > 0:
                    self.sel_cat_idx -= 1
                    prev_cat = self.categories[self.sel_cat_idx]
                    if prev_cat["expanded"] and prev_cat["items"]:
                        self.sel_item_id = prev_cat["items"][-1]["id"]
                    else:
                        self.sel_item_id = None
        else:
            # Inside category items
            items = cat["items"]
            item_indices = {it["id"]: i for i, it in enumerate(items)}
            curr_i = item_indices.get(self.sel_item_id, 0)
            step_y = 2 if use_2col else 1

            if dy > 0:
                next_i = curr_i + step_y
                if next_i < len(items):
                    self.sel_item_id = items[next_i]["id"]
                elif curr_i % step_y == 0 and curr_i + 1 == len(items) - 1 and step_y == 2:
                    # In odd single last item
                    self.sel_item_id = items[-1]["id"]
                else:
                    # Move to next category header
                    if self.sel_cat_idx + 1 < len(self.categories):
                        self.sel_cat_idx += 1
                        self.sel_item_id = None
            elif dy < 0:
                prev_i = curr_i - step_y
                if prev_i >= 0:
                    self.sel_item_id = items[prev_i]["id"]
                else:
                    # Move to current category header
                    self.sel_item_id = None

    def handle_right_arrow(self):
        """Right Arrow: expands category, or moves between columns in 2-col view."""
        cat = self.categories[self.sel_cat_idx]
        use_2col = (self.cols >= 80)

        if self.sel_item_id is None:
            cat["expanded"] = True
            if cat["items"]:
                self.sel_item_id = cat["items"][0]["id"]
        elif use_2col:
            items = cat["items"]
            item_indices = {it["id"]: i for i, it in enumerate(items)}
            curr_i = item_indices.get(self.sel_item_id, 0)
            if curr_i % 2 == 0 and curr_i + 1 < len(items):
                self.sel_item_id = items[curr_i + 1]["id"]

    def handle_left_arrow(self):
        """
        Left Arrow:
        - If inside a category: collapses that category and returns cursor to header.
        - If on category header: collapses it.
        """
        cat = self.categories[self.sel_cat_idx]
        use_2col = (self.cols >= 80)

        if self.sel_item_id is not None:
            items = cat["items"]
            item_indices = {it["id"]: i for i, it in enumerate(items)}
            curr_i = item_indices.get(self.sel_item_id, 0)
            if use_2col and (curr_i % 2 == 1):
                # If on right column, step left to column 1
                self.sel_item_id = items[curr_i - 1]["id"]
            else:
                # In left column: collapse category and return cursor to header
                self.sel_item_id = None
                cat["expanded"] = False
        else:
            cat["expanded"] = False

    def handle_mouse_click(self, x: int, y: int):
        """Handles mouse clicks across viewport, install button, and footer dock actions."""
        header_h = 2
        viewport_end = header_h + getattr(self, "viewport_height_rendered", len(self.visible_lines))

        # 1. Click inside viewport
        if header_h < y <= viewport_end:
            v_idx = y - header_h - 1
            line_idx = self.scroll_offset + v_idx
            if line_idx < len(self.visible_lines):
                entry = self.visible_lines[line_idx]
                if entry["type"] == "cat":
                    self.sel_cat_idx = entry["cat_idx"]
                    self.sel_item_id = None
                    cat = entry["cat"]
                    cat["expanded"] = not cat["expanded"]
                    return None
                elif entry["type"] == "item_row":
                    self.sel_cat_idx = entry["cat_idx"]
                    items = entry["items"]
                    if len(items) == 1:
                        target_it = items[0]
                    else:
                        if x <= self.cols // 2:
                            target_it = items[0]
                        else:
                            target_it = items[1]
                    self.sel_item_id = target_it["id"]
                    self.toggle_item(target_it)
                    return None

        # 2. Click in footer dock actions or install button
        if hasattr(self, "action_rows"):
            for act, act_row in self.action_rows.items():
                if y == act_row:
                    return act

        if hasattr(self, "install_btn_row") and y == self.install_btn_row and x >= self.install_btn_col_start:
            if self.checked_indices:
                return self.get_selected_indices_str()
            return None

        return None

    def run_interactive(self):
        with self.raw_term:
            need_render = True
            while True:
                if need_render or self.resized:
                    self.render_screen()
                    need_render = False
                    self.resized = False

                r, _, _ = select.select([self.raw_term.term_in_fd], [], [], 0.05)
                if not r:
                    self.update_terminal_size()
                    continue

                try:
                    data = os.read(self.raw_term.term_in_fd, 1024)
                except Exception:
                    break

                if not data:
                    break

                events = parse_input_bytes(data)
                if events:
                    need_render = True

                for ev in events:
                    ev_type = ev[0]
                    if ev_type == 'key':
                        key = ev[1]
                        if key == 'up':
                            self.move_selection(-1)
                        elif key == 'down':
                            self.move_selection(1)
                        elif key == 'left':
                            self.handle_left_arrow()
                        elif key == 'right':
                            self.handle_right_arrow()
                        elif key == 'tab':
                            if self.sel_item_id is not None:
                                self.toggle_item_by_id(self.sel_item_id)
                            else:
                                cat = self.categories[self.sel_cat_idx]
                                cat["expanded"] = not cat["expanded"]
                        elif key == 'page_up':
                            self.scroll_offset = max(0, self.scroll_offset - 8)
                        elif key == 'page_down':
                            self.scroll_offset += 8
                        elif key == 'home':
                            self.sel_cat_idx = 0
                            self.sel_item_id = None
                            self.scroll_offset = 0
                        elif key == 'end':
                            self.sel_cat_idx = len(self.categories) - 1
                            self.sel_item_id = None
                        elif key == 'backspace':
                            if self.input_buffer:
                                self.input_buffer = self.input_buffer[:-1]
                                self.sync_checked_from_buffer()
                                nums = re.findall(r'\d+', self.input_buffer)
                                if nums:
                                    self.jump_to_number(int(nums[-1]))
                        elif key in ('escape', 'ctrl_c'):
                            return "Q"
                        elif key == 'enter':
                            if self.checked_indices:
                                return self.get_selected_indices_str()
                            elif self.input_buffer.strip():
                                return self.input_buffer.strip()
                            else:
                                if self.sel_item_id is not None:
                                    it = self.id_to_item.get(self.sel_item_id)
                                    if it:
                                        return str(it["idx"])
                                else:
                                    cat = self.categories[self.sel_cat_idx]
                                    cat["expanded"] = not cat["expanded"]

                    elif ev_type == 'char':
                        ch = ev[1]
                        # Space toggles category if on header, or checkbox if on item and buffer empty
                        if ch == ' ' and not self.input_buffer and not self.checked_indices:
                            if self.sel_item_id is None:
                                cat = self.categories[self.sel_cat_idx]
                                cat["expanded"] = not cat["expanded"]
                            else:
                                self.toggle_item_by_id(self.sel_item_id)
                            continue

                        # Hotkeys: E (Expand All), C (Collapse All)
                        if not self.input_buffer and not self.checked_indices and ch.upper() == 'E':
                            for cat in self.categories:
                                cat["expanded"] = True
                            continue
                        elif not self.input_buffer and not self.checked_indices and ch.upper() == 'C':
                            for cat in self.categories:
                                cat["expanded"] = False
                            self.sel_item_id = None
                            self.scroll_offset = 0
                            continue

                        # Direct batch action hotkeys when buffer is empty
                        if not self.input_buffer and not self.checked_indices and ch.upper() in ('O', 'U', 'D', 'Q'):
                            return ch.upper()

                        # Append character to input buffer & synchronize checkboxes
                        self.input_buffer += ch
                        self.sync_checked_from_buffer()

                        # Real-time highlight jump when typing numbers
                        nums = re.findall(r'\d+', self.input_buffer)
                        if nums:
                            self.jump_to_number(int(nums[-1]))

                    elif ev_type == 'mouse':
                        btn, x, y, release = ev[1], ev[2], ev[3], ev[4]
                        if btn == 64:  # Wheel Up
                            self.scroll_offset = max(0, self.scroll_offset - 2)
                        elif btn == 65:  # Wheel Down
                            self.scroll_offset += 2
                        elif btn == 0 and not release:
                            res = self.handle_mouse_click(x, y)
                            if res:
                                return res

        return "Q"

# --- [ TWEAKS & CURATED SBO FAST STATUS DETECTORS ] ---
def detect_limits_active() -> bool:
    """Fast non-modifying detection of file descriptors and limits tweaks."""
    try:
        import resource
        soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
        if hard >= 524288 or soft >= 524288:
            return True
    except Exception:
        pass
    for path in ["/etc/security/limits.d/99-slacky-gaming.conf", "/etc/profile.d/slacky-limits.sh"]:
        if os.path.exists(path):
            return True
    try:
        for conf in glob.glob("/etc/security/limits.d/*.conf") + ["/etc/security/limits.conf"]:
            if os.path.exists(conf):
                with open(conf, "r", encoding="utf-8", errors="ignore") as f:
                    content = f.read()
                if re.search(r'nofile\s+(524288|1048576|[0-9]{7,})', content):
                    return True
    except Exception:
        pass
    return False

def detect_thp_active() -> bool:
    """Fast non-modifying detection of kernel memory & THP settings."""
    try:
        if os.path.exists("/proc/sys/vm/max_map_count"):
            with open("/proc/sys/vm/max_map_count", "r", encoding="utf-8") as f:
                val = int(f.read().strip())
                if val >= 2147483640:
                    return True
    except Exception:
        pass
    for path in ["/etc/sysctl.d/99-slacky-gaming.conf", "/etc/sysctl.d/99-viking-gaming.conf", "/etc/tmpfiles.d/slacky-thp.conf"]:
        if os.path.exists(path):
            return True
    return False

def detect_net_bbr_active() -> bool:
    """Fast non-modifying detection of BBR congestion control."""
    try:
        if os.path.exists("/proc/sys/net/ipv4/tcp_congestion_control"):
            with open("/proc/sys/net/ipv4/tcp_congestion_control", "r", encoding="utf-8") as f:
                if f.read().strip() == "bbr":
                    return True
    except Exception:
        pass
    if os.path.exists("/etc/modules-load.d/bbr.conf"):
        return True
    return False

def detect_ntsync_active() -> bool:
    """Fast non-modifying detection of NTSYNC device or udev rules."""
    if os.path.exists("/dev/ntsync"):
        return True
    for path in ["/etc/udev/rules.d/99-ntsync.rules", "/lib/udev/rules.d/60-ntsync.rules"]:
        if os.path.exists(path):
            return True
    return False

def detect_ctrl_active() -> bool:
    """Fast non-modifying detection of gamepad and controller udev rules."""
    for path in [
        "/etc/udev/rules.d/sony-gdu.rules",
        "/etc/udev/rules.d/8bitdo-gdu.rules",
        "/etc/udev/rules.d/nintendo-gdu.rules",
        "/etc/udev/rules.d/microsoft-gdu.rules",
        "/etc/udev/rules.d/50-logitech-no-autosuspend.rules",
        "/lib/udev/rules.d/sony-gdu.rules",
        "/lib/udev/rules.d/8bitdo-gdu.rules",
        "/lib/udev/rules.d/nintendo-gdu.rules",
        "/lib/udev/rules.d/microsoft-gdu.rules",
        "/etc/udev/rules.d/70-game-devices-sony.rules"
    ]:
        if os.path.exists(path):
            return True
    return False

def detect_iosched_active() -> bool:
    """Detects whether direct hardware I/O schedulers are configured."""
    if os.path.exists("/etc/udev/rules.d/60-slacky-ioschedulers.rules") or os.path.exists("/etc/udev/rules.d/60-ioschedulers.rules"):
        return True
    sched_paths = glob.glob("/sys/block/nvme*n1/queue/scheduler")
    for p in sched_paths:
        try:
            with open(p, "r", encoding="utf-8") as f:
                if "[none]" in f.read():
                    return True
        except Exception:
            pass
    return False

def detect_shadercache_active() -> bool:
    """Detects whether 10GB global shader disk cache is active."""
    for env_file in ["/etc/profile.d/slacky-shader-cache.sh", "/etc/profile.d/slacky-gaming-env.sh"]:
        if os.path.exists(env_file):
            try:
                with open(env_file, "r", encoding="utf-8") as f:
                    if "__GL_SHADER_DISK_CACHE_SIZE" in f.read():
                        return True
            except Exception:
                pass
    return False

def detect_pwlatency_active() -> bool:
    """Detects whether PipeWire low-latency configuration is deployed."""
    return os.path.exists("/etc/pipewire/pipewire.conf.d/99-slacky-lowlatency.conf")

def detect_sbo_pkg_installed(pkg_id: str, installed_map: dict) -> bool:
    """Detects whether a curated SlackBuild package or binary is present."""
    if pkg_id in installed_map:
        return True
    sbo_bin_map = {
        "davinci-resolve-studio": ["/opt/resolve/bin/resolve", "resolve"],
        "unreal-engine": ["/opt/unreal-engine", "UE4Editor", "UnrealEditor"],
        "freeoffice2024": ["textmaker24", "planmaker24", "presentations24"],
        "wine-staging": ["wine", "wine64"],
        "winetricks": ["winetricks"],
        "grub-btrfs": ["grub-btrfsd", "/etc/default/grub-btrfs/config"],
        "snapper": ["snapper", "/usr/bin/snapper"]
    }
    candidates = sbo_bin_map.get(pkg_id, [pkg_id])
    for cand in candidates:
        if cand.startswith('/'):
            if os.path.exists(cand):
                return True
        else:
            if shutil.which(cand):
                return True
    return False

def detect_fastboot_active() -> bool:
    """Fast non-modifying detection of fastboot optimizations (PCMCIA, NFS & inet1 disabled, rc.6 patched)."""
    try:
        pcmcia_x = os.access("/etc/rc.d/rc.pcmcia", os.X_OK)
        nfsd_x = os.access("/etc/rc.d/rc.nfsd", os.X_OK)
        inet1_x = os.access("/etc/rc.d/rc.inet1", os.X_OK)
        if pcmcia_x or nfsd_x or inet1_x:
            return False
        if os.path.exists("/etc/rc.d/rc.6"):
            with open("/etc/rc.d/rc.6", "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
            if "/bin/sleep 0.5" in content or "/bin/sleep 0.1" in content:
                return True
    except Exception:
        pass
    return False

# --- [ CHECKLIST MENU TUI (TWEAKS & SBO CURATED HUB) ] ---
class ChecklistMenuTUI(SlackyTUI):
    """
    ChecklistMenuTUI: Interactive checklist menu for Tweaks (--mode tweaks) and
    Curated SlackBuilds (--mode sbo-curated).
    - Strict absolute cursor positioning: \033[{row};1H\033[2K{content} (NO STAIRCASE EFFECT).
    - Mouse Safety: Clicking an item or checkbox ONLY toggles [ ] <-> [x]. NEVER auto-applies!
    - Enter key with checked items OR clicking action button returns space-separated indices string ('1 2 4').
    - Clicking action items (e.g. 6, 7, 8) immediately returns that action ID ('6', '7', '8').
    - Tab key toggles item checkbox [ ] <-> [x].
    - Bidirectional real-time typing sync: typing numbers checks items & updates 'On the menu:'.
    """
    def __init__(self, mode="tweaks", badges=None, items=None, cmdline=None, checked=None, ascii_only=False, enable_mouse=True):
        super().__init__(mode=mode, ascii_only=ascii_only, enable_mouse=enable_mouse)
        self.badges = badges or {}
        self.installed_map = detect_installed_packages() if mode != "limine-cmdline" else {}
        self.items = self.init_items(items)
        self.cursor_idx = 0
        self.checked_indices = set()
        self.items_start_row = 1
        self.action_btn_row = 0
        self.action_btn_col_start = 0
        self.action_btn_col_end = 0

        if checked is not None:
            if checked:
                self.checked_indices = parse_indices_from_text(checked, self.get_max_checklist_idx())
            else:
                self.checked_indices = set()
            self.sync_buffer_from_checked()
        elif cmdline is not None:
            if cmdline:
                self.init_checked_from_cmdline(cmdline)
            else:
                self.checked_indices = set()
                self.sync_buffer_from_checked()
        elif self.mode == "limine-cmdline":
            # Check badges or host cmdline
            has_badge_flag = False
            if self.badges:
                for it in self.items:
                    if it.get("is_action"):
                        continue
                    k = it.get("key")
                    i_str = it.get("id")
                    b_val = self.badges.get(k) or self.badges.get(i_str)
                    if b_val:
                        b_str = str(b_val).upper()
                        if b_str in ("TRUE", "1", "ACTIVE", "YES") or "ACTIVE" in b_str:
                            self.checked_indices.add(int(it["id"]))
                            has_badge_flag = True
            if has_badge_flag:
                self.sync_buffer_from_checked()
            else:
                for p in ["/etc/kernel/cmdline", "/proc/cmdline"]:
                    try:
                        if os.path.exists(p):
                            with open(p, "r", encoding="utf-8") as f:
                                h_cmd = f.read().strip()
                                if h_cmd:
                                    self.init_checked_from_cmdline(h_cmd)
                                    break
                    except Exception:
                        pass

    def init_checked_from_cmdline(self, cmdline: str):
        if not cmdline:
            return
        cmd = f" {cmdline} "
        tokens = cmdline.split()

        # 1. Quiet & Splash Boot
        if " quiet " in cmd or " splash " in cmd or any(x.startswith("loglevel=") or x.startswith("rd.udev.log_priority=") for x in tokens):
            self.checked_indices.add(1)
        # 2. NVIDIA GPU Modeset & VRAM
        if "nvidia_drm.modeset=1" in cmd:
            self.checked_indices.add(2)
        # 3. AMD GPU Overclocking (LACT)
        if "amdgpu.ppfeaturemask=" in cmd:
            self.checked_indices.add(3)
        # 4. Disable Watchdog
        if " nowatchdog " in cmd or "nowatchdog" in tokens:
            self.checked_indices.add(4)
        # 5. Disable USB Autosuspend
        if "usbcore.autosuspend=-1" in cmd or any(x.startswith("usbcore.autosuspend=") for x in tokens):
            self.checked_indices.add(5)
        # 6. Hypervisor / VM UMIP Fix
        if "clearcpuid=umip" in cmd:
            self.checked_indices.add(6)
        # 7. IOMMU / VFIO Passthrough
        if any(x in ("intel_iommu=on", "amd_iommu=on", "iommu=pt") for x in tokens) or "_iommu=on" in cmd or "iommu=pt" in cmd:
            self.checked_indices.add(7)
        # 8. ZSWAP Fast RAM Compression
        if "zswap.enabled=1" in cmd:
            self.checked_indices.add(8)
        # 9. Skip Initramfs FSCK
        if "fsck.mode=skip" in cmd:
            self.checked_indices.add(9)
        # 10. Universal Gaming Split Lock Protection
        if "split_lock_mitigate=0" in cmd or "split_lock_detect=off" in cmd:
            self.checked_indices.add(10)

        self.sync_buffer_from_checked()

    def init_items(self, custom_items=None):
        if custom_items and isinstance(custom_items, list):
            return custom_items

        if self.mode == "tweaks":
            return [
                {
                    "id": "1",
                    "key": "limits",
                    "name": "File Descriptors & Process Limits (1M nofile, PipeWire rtprio)",
                    "short_name": "Limits",
                    "is_action": False,
                },
                {
                    "id": "2",
                    "key": "thp",
                    "name": "Kernel Memory & THP (madvise THP, dirty byte limits, swappiness=10)",
                    "short_name": "Memory/THP",
                    "is_action": False,
                },
                {
                    "id": "3",
                    "key": "net",
                    "name": "Network Low-Latency & BBR Congestion Control (fq, fastopen)",
                    "short_name": "Network/BBR",
                    "is_action": False,
                },
                {
                    "id": "4",
                    "key": "ntsync",
                    "name": "NTSYNC Fast Synchronization (/dev/ntsync 0666 permissions)",
                    "short_name": "NTSYNC",
                    "is_action": False,
                },
                {
                    "id": "5",
                    "key": "ctrl",
                    "name": "Universal Gamepad & Controller Forcefield (27 Vendors, Logitech USB)",
                    "short_name": "Controllers",
                    "is_action": False,
                },
                {
                    "id": "6",
                    "key": "fastboot",
                    "name": "Turbo Boot & Fast Shutdown Delays (Eliminate PCMCIA, NFS & rc.6 delays)",
                    "short_name": "FastBoot/Shutdown",
                    "is_action": False,
                },
                {
                    "id": "7",
                    "key": "iosched",
                    "name": "Storage & NVMe Direct I/O Scheduler (none for NVMe, mq-deadline for SATA)",
                    "short_name": "NVMe-Sched",
                    "is_action": False,
                },
                {
                    "id": "8",
                    "key": "shadercache",
                    "name": "NVIDIA 10GB Global Shader Disk Cache (Permanent Shader Retention)",
                    "short_name": "ShaderCache",
                    "is_action": False,
                },
                {
                    "id": "9",
                    "key": "pwlatency",
                    "name": "PipeWire Low-Latency Audio (256 samples / 5.3ms, zero xruns)",
                    "short_name": "LowLatencyAudio",
                    "is_action": False,
                },
                {
                    "id": "10",
                    "key": "apply_all",
                    "name": "🚀 Apply All Recommended Tweaks in One-Click",
                    "ascii_name": "Apply All Recommended Tweaks in One-Click",
                    "is_action": True,
                },
                {
                    "id": "11",
                    "key": "revert_all",
                    "name": "🔄 Revert All Tweaks to Stock Slackware Defaults",
                    "ascii_name": "Revert All Tweaks to Stock Slackware Defaults",
                    "is_action": True,
                },
                {
                    "id": "12",
                    "key": "return",
                    "name": "🚪 Return to Main Menu (ESC)",
                    "ascii_name": "Return to Main Menu (ESC)",
                    "is_action": True,
                },
            ]
        elif self.mode == "limine-cmdline":
            return [
                {
                    "id": "1",
                    "key": "quiet",
                    "name": "Quiet & Splash Boot [quiet splash loglevel=3 rd.udev.log_priority=3]",
                    "short_name": "Quiet",
                    "token": "quiet splash loglevel=3 rd.udev.log_priority=3",
                    "is_action": False,
                },
                {
                    "id": "2",
                    "key": "nvidia",
                    "name": "NVIDIA GPU Modeset & VRAM [nvidia_drm.modeset=1 nvidia_drm.fbdev=1 nvidia.NVreg_PreserveVideoMemoryAllocations=1]",
                    "short_name": "NVIDIA",
                    "token": "nvidia_drm.modeset=1 nvidia_drm.fbdev=1 nvidia.NVreg_PreserveVideoMemoryAllocations=1",
                    "is_action": False,
                },
                {
                    "id": "3",
                    "key": "amd_oc",
                    "name": "AMD GPU Overclocking (LACT) [amdgpu.ppfeaturemask=0xffffffff]",
                    "short_name": "AMD-OC",
                    "token": "amdgpu.ppfeaturemask=0xffffffff",
                    "is_action": False,
                },
                {
                    "id": "4",
                    "key": "watchdog",
                    "name": "Disable Watchdog [nowatchdog]",
                    "short_name": "Watchdog",
                    "token": "nowatchdog",
                    "is_action": False,
                },
                {
                    "id": "5",
                    "key": "usb",
                    "name": "Disable USB Autosuspend [usbcore.autosuspend=-1]",
                    "short_name": "USB",
                    "token": "usbcore.autosuspend=-1",
                    "is_action": False,
                },
                {
                    "id": "6",
                    "key": "umip",
                    "name": "Hypervisor / VM UMIP Fix [clearcpuid=umip]",
                    "short_name": "UMIP",
                    "token": "clearcpuid=umip",
                    "is_action": False,
                },
                {
                    "id": "7",
                    "key": "iommu",
                    "name": "IOMMU / VFIO Passthrough [amd_iommu=on iommu=pt / intel_iommu=on]",
                    "short_name": "IOMMU",
                    "token": "iommu=pt",
                    "is_action": False,
                },
                {
                    "id": "8",
                    "key": "zswap",
                    "name": "ZSWAP Fast RAM Compression [zswap.enabled=1 zswap.compressor=zstd zswap.max_pool_percent=25]",
                    "short_name": "ZSWAP",
                    "token": "zswap.enabled=1 zswap.compressor=zstd zswap.max_pool_percent=25",
                    "is_action": False,
                },
                {
                    "id": "9",
                    "key": "fsck",
                    "name": "Skip Initramfs FSCK [fsck.mode=skip]",
                    "short_name": "Skip-FSCK",
                    "token": "fsck.mode=skip",
                    "is_action": False,
                },
                {
                    "id": "10",
                    "key": "split_lock",
                    "name": "Universal Split Lock Protection [split_lock_mitigate=0 split_lock_detect=off]",
                    "short_name": "SplitLock",
                    "token": "split_lock_mitigate=0 split_lock_detect=off",
                    "is_action": False,
                },
                {
                    "id": "S",
                    "key": "save",
                    "name": "💾 Save & Enroll (Rebuild limine.conf, BLAKE2B & Sign EFI)",
                    "ascii_name": "Save & Enroll (Rebuild limine.conf, BLAKE2B & Sign EFI)",
                    "is_action": True,
                },
                {
                    "id": "E",
                    "key": "edit",
                    "name": "✏️  Edit Raw CMDLINE (Inline readline terminal prompt)",
                    "ascii_name": "Edit Raw CMDLINE (Inline readline terminal prompt)",
                    "is_action": True,
                },
                {
                    "id": "N",
                    "key": "nano",
                    "name": "📝 Open in Nano / Text Editor",
                    "ascii_name": "Open in Nano / Text Editor",
                    "is_action": True,
                },
                {
                    "id": "R",
                    "key": "reset",
                    "name": "🔄 Reset to Hardware & Sensible Defaults",
                    "ascii_name": "Reset to Hardware & Sensible Defaults",
                    "is_action": True,
                },
                {
                    "id": "Q",
                    "key": "return",
                    "name": "🚪 Cancel / Return without saving (ESC)",
                    "ascii_name": "Cancel / Return without saving (ESC)",
                    "is_action": True,
                },
            ]
        else:
            # Mode "sbo-curated"
            return [
                {
                    "id": "1",
                    "pkg_id": "davinci-resolve-studio",
                    "name": "DaVinci Resolve Studio (multimedia/davinci-resolve-studio)",
                    "short_name": "davinci-resolve-studio",
                    "is_action": False,
                },
                {
                    "id": "2",
                    "pkg_id": "unreal-engine",
                    "name": "Unreal Engine (development/unreal-engine)",
                    "short_name": "unreal-engine",
                    "is_action": False,
                },
                {
                    "id": "3",
                    "pkg_id": "freeoffice2024",
                    "name": "FreeOffice 2024 (office/freeoffice2024)",
                    "short_name": "freeoffice2024",
                    "is_action": False,
                },
                {
                    "id": "4",
                    "pkg_id": "wine-staging",
                    "name": "Wine Staging (system/wine-staging)",
                    "short_name": "wine-staging",
                    "is_action": False,
                },
                {
                    "id": "5",
                    "pkg_id": "winetricks",
                    "name": "Winetricks (system/winetricks)",
                    "short_name": "winetricks",
                    "is_action": False,
                },
                {
                    "id": "6",
                    "pkg_id": "grub-btrfs",
                    "name": "GRUB-Btrfs (system/grub-btrfs)",
                    "short_name": "grub-btrfs",
                    "is_action": False,
                },
                {
                    "id": "7",
                    "pkg_id": "snapper",
                    "name": "Snapper (system/snapper)",
                    "short_name": "snapper",
                    "is_action": False,
                },
                {
                    "id": "8",
                    "key": "return",
                    "name": "🚪 Return to Previous Menu (ESC)",
                    "ascii_name": "Return to Previous Menu (ESC)",
                    "is_action": True,
                },
            ]

    def get_max_checklist_idx(self) -> int:
        if self.mode == "limine-cmdline":
            return 10
        return 9 if self.mode == "tweaks" else 7

    def toggle_item(self, it):
        """Toggles checkbox state for a checklist item and synchronizes input buffer."""
        if it.get("is_action"):
            return
        idx = int(it["id"])
        if idx in self.checked_indices:
            self.checked_indices.remove(idx)
        else:
            self.checked_indices.add(idx)
        self.sync_buffer_from_checked()

    def sync_buffer_from_checked(self):
        """Updates input_buffer to reflect currently checked items."""
        if not self.checked_indices:
            self.input_buffer = ""
        else:
            self.input_buffer = " ".join(str(i) for i in sorted(self.checked_indices))

    def sync_checked_from_buffer(self):
        """Updates checked_indices from input_buffer tokens."""
        max_idx = self.get_max_checklist_idx()
        self.checked_indices = parse_indices_from_text(self.input_buffer, max_idx)

    def get_selected_indices_str(self) -> str:
        """Returns space-separated string of selected indices e.g. '1 2 4'."""
        if not self.checked_indices:
            return ""
        return " ".join(str(i) for i in sorted(self.checked_indices))

    def get_save_return_val(self) -> str:
        indices = self.get_selected_indices_str()
        return f"SAVE {indices}" if indices else "SAVE"

    def get_badge(self, it) -> str:
        if it.get("is_action"):
            return ""

        if self.mode == "limine-cmdline":
            k = it.get("key", "")
            raw = self.badges.get(k) or self.badges.get(it.get("id"))
            if raw:
                raw_str = str(raw).strip()
                if '\x1b' in raw_str:
                    return raw_str if not self.ascii_only else strip_ansi(raw_str)
                clean = strip_ansi(raw_str).upper()
                badge_txt = f"[{clean.strip('[]')}]"
                return f"{BOLD_YELLOW}{badge_txt}{RESET}" if not self.ascii_only else badge_txt
            if k == "zswap":
                if self.badges.get("zram") or self.badges.get("zram_active") or os.path.exists("/dev/zram0"):
                    note = "[⛔ Disabled: ZRAM active]" if not self.ascii_only else "[Disabled: ZRAM active]"
                    return f" {YELLOW}{note}{RESET}" if not self.ascii_only else f" {note}"
            return ""

        if self.mode == "tweaks":
            key = it.get("key", "")
            raw = self.badges.get(key)
            if raw:
                raw_str = str(raw).strip()
                if '\x1b' in raw_str:
                    return raw_str if not self.ascii_only else strip_ansi(raw_str)
                clean = strip_ansi(raw_str).upper()
                if "INACTIVE" in clean or "DISABLED" in clean:
                    badge_txt = "[INACTIVE]" if "INACTIVE" in clean else f"[{clean.strip('[]')}]"
                    return f"{BOLD_YELLOW}{badge_txt}{RESET}" if not self.ascii_only else badge_txt
                elif "ACTIVE" in clean:
                    badge_txt = "[ACTIVE]"
                    return f"{BOLD_GREEN}{badge_txt}{RESET}" if not self.ascii_only else badge_txt
                else:
                    badge_txt = f"[{clean.strip('[]')}]"
                    return f"{BOLD_YELLOW}{badge_txt}{RESET}" if not self.ascii_only else badge_txt

            # Auto-detection
            active = False
            if key == "limits":
                active = detect_limits_active()
            elif key == "thp":
                active = detect_thp_active()
            elif key == "net":
                active = detect_net_bbr_active()
            elif key == "ntsync":
                active = detect_ntsync_active()
            elif key == "ctrl":
                active = detect_ctrl_active()
            elif key == "fastboot":
                active = detect_fastboot_active()
            elif key == "iosched":
                active = detect_iosched_active()
            elif key == "shadercache":
                active = detect_shadercache_active()
            elif key == "pwlatency":
                active = detect_pwlatency_active()

            if active:
                badge_txt = "[ACTIVE]"
                return f"{BOLD_GREEN}{badge_txt}{RESET}" if not self.ascii_only else badge_txt
            else:
                badge_txt = "[INACTIVE]"
                return f"{BOLD_YELLOW}{badge_txt}{RESET}" if not self.ascii_only else badge_txt
        else:
            # Mode "sbo-curated"
            pkg_id = it.get("pkg_id", "")
            raw = self.badges.get(pkg_id)
            if raw:
                raw_str = str(raw).strip()
                if '\x1b' in raw_str:
                    return raw_str if not self.ascii_only else strip_ansi(raw_str)
                clean = strip_ansi(raw_str).upper()
                if "NOT" in clean or "AVAILABLE" in clean:
                    badge_txt = "[AVAILABLE]"
                    return f"{BOLD_YELLOW}{badge_txt}{RESET}" if not self.ascii_only else badge_txt
                elif "INSTALLED" in clean or "ACTIVE" in clean:
                    badge_txt = "[INSTALLED]"
                    return f"{BOLD_GREEN}{badge_txt}{RESET}" if not self.ascii_only else badge_txt
                else:
                    badge_txt = f"[{clean.strip('[]')}]"
                    return f"{BOLD_YELLOW}{badge_txt}{RESET}" if not self.ascii_only else badge_txt

            # Auto-detection
            is_inst = detect_sbo_pkg_installed(pkg_id, self.installed_map)
            if is_inst:
                badge_txt = "[INSTALLED]"
                return f"{BOLD_GREEN}{badge_txt}{RESET}" if not self.ascii_only else badge_txt
            else:
                badge_txt = "[AVAILABLE]"
                return f"{BOLD_YELLOW}{badge_txt}{RESET}" if not self.ascii_only else badge_txt

    def format_menu_dock_line(self) -> str:
        """Formats 'On the menu: <items>       [Action Button]' line."""
        if self.mode == "limine-cmdline":
            btn_text = "[💾 Save & Enroll (Enter)]" if not self.ascii_only else "[Save & Enroll (Enter)]"
            dim_btn_text = btn_text
            empty_msg = "(no parameters selected)"
        elif self.mode == "tweaks":
            btn_text = "[⚡ Apply Selected (Enter)]" if not self.ascii_only else "[Apply Selected (Enter)]"
            dim_btn_text = "[⚡ Apply Selected]" if not self.ascii_only else "[Apply Selected]"
            empty_msg = f"({_tr('TUI_NO_TWEAKS_SELECTED', 'no tweaks selected')})"
        else:
            btn_text = "[🚀 Build & Install (Enter)]" if not self.ascii_only else "[Build & Install (Enter)]"
            dim_btn_text = "[🚀 Build & Install]" if not self.ascii_only else "[Build & Install]"
            empty_msg = f"({_tr('TUI_NO_PKGS_SELECTED', 'no packages selected')})"

        lbl_menu = _tr("TUI_ON_THE_MENU", "On the menu:")
        prefix = f" {BOLD}{lbl_menu}{RESET} "
        prefix_plain = f" {lbl_menu} "

        if self.mode == "limine-cmdline":
            if self.checked_indices:
                selected_shorts = [self.items[i-1]["short_name"] for i in sorted(self.checked_indices) if 1 <= i <= len(self.items)]
                list_str = " ".join(selected_shorts)
                list_styled = f"{BOLD_GREEN}{list_str}{RESET}"
            else:
                list_str = empty_msg
                list_styled = f"{DIM}{list_str}{RESET}"

            btn_styled = f"{BOLD_GREEN}{btn_text}{RESET}"
            btn_w = str_display_width(btn_text)
            avail_w = max(10, self.cols - str_display_width(prefix_plain) - btn_w - 2)
            if str_display_width(list_str) > avail_w:
                list_styled = f"{BOLD_GREEN}{truncate_ansi(list_str, avail_w)}{RESET}" if self.checked_indices else f"{DIM}{truncate_ansi(list_str, avail_w)}{RESET}"
                content_w = str_display_width(prefix_plain) + avail_w
            else:
                content_w = str_display_width(prefix_plain) + str_display_width(list_str)

            pad_w = max(1, self.cols - content_w - btn_w - 1)
            self.action_btn_col_start = self.cols - btn_w
            self.action_btn_col_end = self.cols
            return f"{prefix}{list_styled}{' ' * pad_w}{btn_styled} "

        elif self.checked_indices:
            if self.mode == "tweaks" and len(self.checked_indices) == 6:
                list_str = "All 6 Recommended Tweaks"
            else:
                selected_shorts = [self.items[i-1]["short_name"] for i in sorted(self.checked_indices) if 1 <= i <= len(self.items)]
                list_str = ", ".join(selected_shorts)

            btn_styled = f"{BOLD_GREEN}{btn_text}{RESET}"
            btn_w = str_display_width(btn_text)

            avail_w = max(10, self.cols - str_display_width(prefix_plain) - btn_w - 2)
            if str_display_width(list_str) > avail_w:
                list_styled = f"{BOLD_GREEN}{truncate_ansi(list_str, avail_w)}{RESET}"
                content_w = str_display_width(prefix_plain) + avail_w
            else:
                list_styled = f"{BOLD_GREEN}{list_str}{RESET}"
                content_w = str_display_width(prefix_plain) + str_display_width(list_str)

            pad_w = max(1, self.cols - content_w - btn_w - 1)
            self.action_btn_col_start = self.cols - btn_w
            self.action_btn_col_end = self.cols
            return f"{prefix}{list_styled}{' ' * pad_w}{btn_styled} "
        else:
            list_styled = f"{DIM}{empty_msg}{RESET}"
            content_w = str_display_width(prefix_plain) + str_display_width(empty_msg)

            btn_styled = f"{DIM}{dim_btn_text}{RESET}"
            btn_w = str_display_width(dim_btn_text)

            pad_w = max(1, self.cols - content_w - btn_w - 1)
            self.action_btn_col_start = self.cols - btn_w
            self.action_btn_col_end = self.cols
            return f"{prefix}{list_styled}{' ' * pad_w}{btn_styled} "

    def render_screen(self):
        self.update_terminal_size()
        frame_rows = []

        sep_len = min(self.cols, 77)
        sep_eq = "=" * sep_len
        sep_dash = "-" * sep_len

        # 1. Header
        if self.mode == "limine-cmdline":
            frame_rows.append(f"{BOLD_BLUE}Slacky-Update (Kernel Boot Parameters & Gaming Hub){RESET}")
            frame_rows.append(f"{BLUE}Limine CMDLINE Configuration (Zone B){RESET}")
            frame_rows.append("")
        else:
            frame_rows.append(f"{BOLD_CYAN}{sep_eq}{RESET}")
            if self.mode == "tweaks":
                title = " ⚡ OPTIONAL SYSTEM & GAMING TWEAKS ⚡ " if not self.ascii_only else " OPTIONAL SYSTEM & GAMING TWEAKS "
            else:
                title = " ⚡ SLACKY-SLACKBUILDS CURATED HUB ⚡ " if not self.ascii_only else " SLACKY-SLACKBUILDS CURATED HUB "
            frame_rows.append(f"{BOLD_CYAN}{pad_ansi(title, sep_len, align='center')}{RESET}")
            frame_rows.append(f"{BOLD_CYAN}{sep_eq}{RESET}")

        # 2. Checklist Items
        self.items_start_row = len(frame_rows) + 1

        checklist_items = [it for it in self.items if not it.get("is_action")]
        max_name_w = max(str_display_width(it["name"]) for it in checklist_items) if checklist_items else 40

        for i, it in enumerate(self.items):
            is_cursor = (i == self.cursor_idx)
            arrow_sym = ">" if self.ascii_only else "▶"
            prefix = f" {BOLD_CYAN}{arrow_sym}{RESET} " if is_cursor else "   "

            if it.get("is_action"):
                if self.mode == "limine-cmdline":
                    act_tag = f"[{it['id']}]"
                    idx_styled = f"{BOLD_CYAN}{act_tag}{RESET}" if is_cursor else f"{BOLD_YELLOW}{act_tag}{RESET}"
                    name = it.get("ascii_name") if (self.ascii_only and "ascii_name" in it) else it["name"]
                    name_styled = f"{BOLD_WHITE}{name}{RESET}" if is_cursor else name
                    frame_rows.append(f"{prefix}  {idx_styled} {name_styled}")
                else:
                    idx_str = f"{it['id']:>2}."
                    idx_styled = f"{BOLD_CYAN}{idx_str}{RESET}" if is_cursor else f"{BOLD_YELLOW}{idx_str}{RESET}"
                    name = it.get("ascii_name") if (self.ascii_only and "ascii_name" in it) else it["name"]
                    name_styled = f"{BOLD_WHITE}{name}{RESET}" if is_cursor else name
                    frame_rows.append(f"{prefix}    {idx_styled} {name_styled}")
            else:
                idx = int(it["id"])
                is_checked = (idx in self.checked_indices)
                box_str = f"{BOLD_GREEN}[x]{RESET}" if is_checked else f"{DIM}[ ]{RESET}"
                idx_str = f"{it['id']:>2}."
                idx_styled = f"{BOLD_CYAN}{idx_str}{RESET}" if is_cursor else f"{BOLD_YELLOW}{idx_str}{RESET}"

                name = it["name"]
                badge = self.get_badge(it)

                prefix_w = 11
                badge_w = str_display_width(badge)
                if prefix_w + max_name_w + 2 + badge_w <= self.cols:
                    pad = " " * max(1, max_name_w - str_display_width(name) + 2)
                    name_padded = f"{name}{pad}"
                else:
                    name_padded = f"{name} "

                name_styled = f"{BOLD_WHITE}{name_padded}{RESET}" if is_cursor else name_padded
                frame_rows.append(f"{prefix}{box_str} {idx_styled} {name_styled}{badge}")

        # 3. Padding to pin dock to bottom
        dock_h = 5
        needed_pad = max(0, self.rows - (len(frame_rows) + dock_h))
        for _ in range(needed_pad):
            frame_rows.append("")

        # 4. Bottom Dock
        frame_rows.append(f"{CYAN}{sep_dash}{RESET}")
        bullet = "*" if self.ascii_only else "•"
        if self.mode == "tweaks":
            dock_actions = f" Actions: {bullet} {BOLD_CYAN}[TAB/Click]{RESET} {BOLD_WHITE}Toggle selection{RESET} {bullet} {BOLD_CYAN}[Enter]{RESET} {BOLD_WHITE}Apply Selected{RESET} {bullet} {BOLD_CYAN}[ESC]{RESET} {BOLD_WHITE}Return{RESET}"
        elif self.mode == "limine-cmdline":
            dock_actions = f" Actions: {bullet} {BOLD_CYAN}[1-10/Click]{RESET} {BOLD_WHITE}Toggle flag{RESET} {bullet} {BOLD_CYAN}[S/Enter]{RESET} {BOLD_WHITE}Save & Enroll{RESET} {bullet} {BOLD_CYAN}[ESC]{RESET} {BOLD_WHITE}Return{RESET}"
        else:
            dock_actions = f" Actions: {bullet} {BOLD_CYAN}[TAB/Click]{RESET} {BOLD_WHITE}Check package{RESET} {bullet} {BOLD_CYAN}[Enter]{RESET} {BOLD_WHITE}Build Selected{RESET} {bullet} {BOLD_CYAN}[ESC]{RESET} {BOLD_WHITE}Return{RESET}"
        frame_rows.append(dock_actions)
        frame_rows.append(f"{BOLD_CYAN}{sep_eq}{RESET}")

        # Prompt line
        if self.mode == "tweaks":
            prompt_line = f"Pick your play [1-9, 10, 11, 12]: {self.input_buffer}"
        elif self.mode == "limine-cmdline":
            prompt_line = f"Select option [1-10, S, E, N, R, Q]: {self.input_buffer}"
        else:
            prompt_line = f"Pick your play [1-7, 8]: {self.input_buffer}"
        frame_rows.append(prompt_line)

        # On the menu dock line
        self.action_btn_row = len(frame_rows) + 1
        frame_rows.append(self.format_menu_dock_line())

        prompt_row = len(frame_rows) - 1
        prompt_col = 1 + str_display_width(prompt_line)
        self.render_frame(frame_rows, cursor_pos=(prompt_row, prompt_col))

    def handle_mouse_click(self, x: int, y: int):
        """
        Handles mouse clicks across checklist items and dock action button.
        SAFETY RULE: Clicking an item or checkbox ONLY toggles [ ] <-> [x].
        Clicking action button OR pressing Enter returns selected indices string.
        Clicking action items (e.g. 6, 7, 8, S, E, N, R, Q) immediately returns that action ID.
        """
        # 1. Click on item
        if self.items_start_row <= y < self.items_start_row + len(self.items):
            opt_idx = y - self.items_start_row
            if 0 <= opt_idx < len(self.items):
                target_it = self.items[opt_idx]
                if target_it.get("is_action"):
                    act_id = target_it["id"]
                    if act_id == "S" and self.mode == "limine-cmdline":
                        return self.get_save_return_val()
                    return act_id
                else:
                    self.cursor_idx = opt_idx
                    self.toggle_item(target_it)
                    return None

        # 2. Click on bottom dock action button
        if y == self.action_btn_row and x >= self.action_btn_col_start:
            if self.mode == "limine-cmdline":
                return self.get_save_return_val()
            if self.checked_indices:
                return self.get_selected_indices_str()
            return None

        return None

    def run_interactive(self):
        with self.raw_term:
            need_render = True
            while True:
                if need_render or self.resized:
                    self.render_screen()
                    need_render = False
                    self.resized = False

                r, _, _ = select.select([self.raw_term.term_in_fd], [], [], 0.05)
                if not r:
                    self.update_terminal_size()
                    continue

                try:
                    data = os.read(self.raw_term.term_in_fd, 1024)
                except Exception:
                    break

                if not data:
                    break

                events = parse_input_bytes(data)
                if events:
                    need_render = True

                for ev in events:
                    ev_type = ev[0]
                    if ev_type == 'key':
                        key = ev[1]
                        if key == 'up':
                            self.cursor_idx = max(0, self.cursor_idx - 1)
                        elif key == 'down':
                            self.cursor_idx = min(len(self.items) - 1, self.cursor_idx + 1)
                        elif key == 'home':
                            self.cursor_idx = 0
                        elif key == 'end':
                            self.cursor_idx = len(self.items) - 1
                        elif key == 'tab':
                            target_it = self.items[self.cursor_idx]
                            if not target_it.get("is_action"):
                                self.toggle_item(target_it)
                        elif key == 'backspace':
                            if self.input_buffer:
                                self.input_buffer = self.input_buffer[:-1]
                                self.sync_checked_from_buffer()
                                nums = re.findall(r'\d+', self.input_buffer)
                                if nums:
                                    n = int(nums[-1])
                                    if 1 <= n <= len(self.items):
                                        self.cursor_idx = n - 1
                        elif key in ('escape', 'ctrl_c'):
                            if self.mode == "limine-cmdline":
                                return "Q"
                            elif self.mode == "tweaks":
                                return "12"
                            else:
                                return "8"
                        elif key == 'enter':
                            target_it = self.items[self.cursor_idx]
                            if target_it.get("is_action"):
                                act_id = target_it["id"]
                                if act_id == "S" and self.mode == "limine-cmdline":
                                    return self.get_save_return_val()
                                return act_id

                            if self.mode == "limine-cmdline":
                                return self.get_save_return_val()

                            if self.checked_indices:
                                return self.get_selected_indices_str()
                            elif self.input_buffer.strip():
                                return self.input_buffer.strip()
                            else:
                                self.toggle_item(target_it)

                    elif ev_type == 'char':
                        ch = ev[1]
                        if self.mode == "limine-cmdline":
                            up = ch.upper()
                            if up == 'S':
                                return self.get_save_return_val()
                            elif up == 'E':
                                return "E"
                            elif up == 'N':
                                return "N"
                            elif up == 'R':
                                return "R"
                            elif up == 'Q':
                                return "Q"
                        elif ch.upper() == 'Q':
                            if self.mode == "tweaks":
                                return "12"
                            elif self.mode == "limine-cmdline":
                                return "Q"
                            else:
                                return "8"

                        # Space toggles checkbox if input buffer is empty
                        if ch == ' ' and not self.input_buffer:
                            target_it = self.items[self.cursor_idx]
                            if not target_it.get("is_action"):
                                self.toggle_item(target_it)
                            continue

                        # Typing digits, spaces, commas, dashes into input buffer
                        if ch.isdigit() or ch in " ,-":
                            self.input_buffer += ch
                            self.sync_checked_from_buffer()
                            nums = re.findall(r'\d+', self.input_buffer)
                            if nums:
                                n = int(nums[-1])
                                if 1 <= n <= len(self.items):
                                    self.cursor_idx = n - 1

                    elif ev_type == 'mouse':
                        btn, x, y, release = ev[1], ev[2], ev[3], ev[4]
                        if btn == 0 and not release:
                            res = self.handle_mouse_click(x, y)
                            if res:
                                return res

        if self.mode == "limine-cmdline":
            return "Q"
        elif self.mode == "tweaks":
            return "12"
        else:
            return "8"

# --- [ PIPE / NON-TTY FALLBACK HANDLER ] ---
def run_non_tty_mode(mode: str, gpu: str = "generic"):
    """Graceful fallback for pipe / non-TTY ([ ! -t 0 ])."""
    default_exits = {
        "gnomes": "Q",
        "limine-cmdline": "Q",
        "sbo-main": "4",
        "sbo-search": "3",
        "sbo-recommended": "5",
        "limine-main": "8",
        "kernel-main": "5",
        "kernel-picker": "12",
        "kernel-manage": "3",
        "kernel-prune": "exit",
        "nvidia-main": "4",
        "nvidia-legacy": "6",
        "secureboot-main": "5",
        "docs-main": "10",
        "tweaks": "12",
        "sbo-curated": "8",
        "clean": "6",
        "main": "9",
    }
    fallback = default_exits.get(mode, "9")
    try:
        r, _, _ = select.select([sys.stdin], [], [], 0.0)
        if r:
            line = sys.stdin.readline()
            if not line or not line.strip():
                return fallback
            return line.strip()
        return fallback
    except Exception:
        return fallback

# --- [ CLI ENTRY POINT ] ---
def main():
    parser = argparse.ArgumentParser(description="Slacky-Update CLI Terminal User Interface ('Dark Star')")
    parser.add_argument("--mode", choices=[
        "main", "gnomes", "tweaks", "sbo-curated", "sbo-main", "sbo-search", "sbo-recommended",
        "limine-main", "limine-cmdline", "kernel-main", "kernel-picker",
        "kernel-manage", "kernel-prune",
        "nvidia-main", "nvidia-legacy", "secureboot-main", "docs-main",
        "clean"
    ], default="gnomes", help="UI mode")
    parser.add_argument("--gpu", default="generic", help="GPU variant for main menu (nvidia, amd, intel, generic)")
    parser.add_argument("--data", default=None, help="JSON data string for categories/items")
    parser.add_argument("--data-file", default=None, help="Path to JSON file containing data")
    parser.add_argument("--items", default=None, help="JSON items string for main menu")
    parser.add_argument("--ascii", action="store_true", help="Force ASCII safe borders and symbols")
    parser.add_argument("--no-mouse", action="store_true", help="Disable mouse tracking")
    parser.add_argument("--mouse", action="store_true", help="Enable mouse tracking (default: enabled)")

    # Commandline and checked indices for limine-cmdline
    parser.add_argument("--cmdline", default=None, help="Kernel CMDLINE string for limine-cmdline mode")
    parser.add_argument("--checked", default=None, help="Initial checked indices string")

    # Badges for tweaks & sbo-curated & kernel-picker
    parser.add_argument("--limits-badge", default=None, help="Badge for File Descriptors & Process Limits")
    parser.add_argument("--thp-badge", default=None, help="Badge for Kernel Memory & THP")
    parser.add_argument("--net-badge", default=None, help="Badge for Network Low-Latency & BBR")
    parser.add_argument("--ntsync-badge", default=None, help="Badge for NTSYNC Fast Synchronization")
    parser.add_argument("--ctrl-badge", default=None, help="Badge for Universal Gamepad & Controller Forcefield")
    parser.add_argument("--fastboot-badge", default=None, help="Badge for Turbo Boot & Fast Shutdown Delays")
    parser.add_argument("--iosched-badge", default=None, help="Badge for Storage & NVMe Direct I/O Scheduler")
    parser.add_argument("--shadercache-badge", default=None, help="Badge for NVIDIA 10GB Global Shader Disk Cache")
    parser.add_argument("--pwlatency-badge", default=None, help="Badge for PipeWire Low-Latency Audio")
    parser.add_argument("--badges", default=None, help="JSON dictionary of badges")
    parser.add_argument("--pkg-badges", default=None, help="JSON dictionary of badges for curated SBo packages or kernel flavors")

    args = parser.parse_args()

    # Handle non-TTY fallback ([ ! -t 0 ])
    if not sys.stdin.isatty():
        choice = run_non_tty_mode(args.mode, args.gpu)
        print(choice)
        return 0

    # Auto-detect GPU if generic
    gpu_type = args.gpu
    if gpu_type == "generic":
        if os.path.exists("/proc/driver/nvidia") or shutil.which("nvidia-smi"):
            gpu_type = "nvidia"

    # Custom categories/items data if provided
    custom_data = None
    if args.data:
        try:
            custom_data = json.loads(args.data)
        except Exception:
            pass
    elif args.data_file and os.path.exists(args.data_file):
        try:
            with open(args.data_file, "r", encoding="utf-8") as f:
                custom_data = json.load(f)
        except Exception:
            pass

    custom_items = None
    if args.items:
        try:
            custom_items = json.loads(args.items)
        except Exception:
            pass

    if args.mode == "main":
        use_mouse = not args.no_mouse
        app = MainMenuTUI(gpu=gpu_type, items=custom_items, ascii_only=args.ascii, enable_mouse=use_mouse)
        choice = app.run_interactive()
    elif args.mode == "gnomes":
        app = GnomesTUI(data=custom_data, ascii_only=args.ascii, enable_mouse=not args.no_mouse)
        choice = app.run_interactive()
    elif args.mode == "clean":
        app = CleanTUI(ascii_only=args.ascii, enable_mouse=not args.no_mouse)
        choice = app.run_interactive()
    elif args.mode in ("tweaks", "sbo-curated", "limine-cmdline"):
        badges = {}
        if args.limits_badge:
            badges["limits"] = args.limits_badge
        if args.thp_badge:
            badges["thp"] = args.thp_badge
        if args.net_badge:
            badges["net"] = args.net_badge
        if args.ntsync_badge:
            badges["ntsync"] = args.ntsync_badge
        if args.ctrl_badge:
            badges["ctrl"] = args.ctrl_badge
        if args.fastboot_badge:
            badges["fastboot"] = args.fastboot_badge
        if args.iosched_badge:
            badges["iosched"] = args.iosched_badge
        if args.shadercache_badge:
            badges["shadercache"] = args.shadercache_badge
        if args.pwlatency_badge:
            badges["pwlatency"] = args.pwlatency_badge
        if args.badges:
            try:
                badges.update(json.loads(args.badges))
            except Exception:
                pass
        if args.pkg_badges:
            try:
                badges.update(json.loads(args.pkg_badges))
            except Exception:
                pass

        app = ChecklistMenuTUI(mode=args.mode, badges=badges, items=custom_items, cmdline=args.cmdline, checked=args.checked, ascii_only=args.ascii, enable_mouse=not args.no_mouse)
        choice = app.run_interactive()
    elif args.mode in ("sbo-main", "sbo-search", "sbo-recommended", "limine-main", "kernel-main", "kernel-picker", "kernel-manage", "kernel-prune", "nvidia-main", "nvidia-legacy", "secureboot-main", "docs-main"):
        badges = {}
        if args.badges:
            try:
                badges.update(json.loads(args.badges))
            except Exception:
                pass
        if args.pkg_badges:
            try:
                badges.update(json.loads(args.pkg_badges))
            except Exception:
                pass
        app = SimpleSelectTUI(mode=args.mode, items=custom_items, badges=badges, ascii_only=args.ascii, enable_mouse=not args.no_mouse)
        choice = app.run_interactive()

    # Print clean choice to stdout for caller capture
    print(choice)
    return 0

if __name__ == "__main__":
    sys.exit(main())
