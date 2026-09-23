#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Slacky-Update Unified Pacman ILoveCandy Progress Engine
Author: TuxOfValhalla
License: GPLv3

Provides a canonical, 100% flicker-free multi-line and single-line
Pacman ILoveCandy rendering engine shared between gnomes_pacman.py and common.sh.
"""

import sys
import os
import time
import signal
import atexit
from typing import Optional, List, Tuple

CURSOR_HIDE = "\033[?25l"
CURSOR_SHOW = "\033[?25h"
CLEAR_LINE = "\033[2K"

_cursor_hidden = False

def hide_cursor() -> None:
    """Hide terminal cursor to eliminate flicker during animation."""
    global _cursor_hidden
    if sys.stdout.isatty() and not _cursor_hidden:
        sys.stdout.write(CURSOR_HIDE)
        sys.stdout.flush()
        _cursor_hidden = True

def show_cursor() -> None:
    """Restore terminal cursor."""
    global _cursor_hidden
    if sys.stdout.isatty() and _cursor_hidden:
        sys.stdout.write(CURSOR_SHOW)
        sys.stdout.flush()
        _cursor_hidden = False

# Ensure cursor is always restored on process exit or termination
def _signal_handler(sig, frame):
    show_cursor()
    sys.exit(128 + sig if isinstance(sig, int) else 1)

atexit.register(show_cursor)
try:
    signal.signal(signal.SIGINT, _signal_handler)
    signal.signal(signal.SIGTERM, _signal_handler)
except Exception:
    pass


def format_size(bytes_val: float) -> str:
    """Format bytes into standard human-readable size."""
    if bytes_val < 0:
        return "0.0 MB"
    mb = bytes_val / (1024 * 1024)
    if mb >= 1024:
        return f"{mb / 1024:.2f} GB"
    elif mb >= 1.0:
        return f"{mb:.1f} MB"
    elif bytes_val >= 1024:
        return f"{bytes_val / 1024:.1f} KB"
    return f"{int(bytes_val)} B"


def format_speed(bytes_per_sec: float) -> str:
    """Format download speed into human-readable string."""
    if bytes_per_sec < 0:
        return "  0.0 MB/s"
    mb = bytes_per_sec / (1024 * 1024)
    if mb >= 1.0:
        return f"{mb:4.1f} MB/s"
    elif bytes_per_sec >= 1024:
        return f"{bytes_per_sec / 1024:4.1f} KB/s"
    return f"{int(bytes_per_sec):4d} B/s"


def format_eta(seconds: float) -> str:
    """Format seconds into MM:SS or HH:MM:SS ETA string."""
    if seconds < 0 or seconds > 36000:
        return "--:--"
    m, s = divmod(int(seconds), 60)
    h, m = divmod(m, 60)
    if h > 0:
        return f"{h:02d}:{m:02d}:{s:02d}"
    return f"{m:02d}:{s:02d}"


def render_pacman_bar(
    pct: float,
    width: int = 24,
    chomp_state: int = 0,
    show_pct: bool = False,
    custom_eater: Optional[str] = None
) -> str:
    """
    Render 100% authentic Pacman ILoveCandy progress bar.
    Pellets follow authentic i % 2 == 0 pattern ('o o o o').
    Eater alternates between Slackware Bold Blue 'S' (mouth open) and 's' (mouth closed).
    """
    pct = max(0.0, min(100.0, pct))
    pct_str = f" {int(pct):>3d}%" if show_pct else ""

    if pct >= 100.0:
        return f"[{'-' * width}]{pct_str}"

    pos = int((pct / 100.0) * width)
    pos = min(width - 1, max(0, pos))
    eaten = "-" * pos

    if custom_eater:
        eater = custom_eater
    else:
        mouth_open = (chomp_state % 2 == 0)
        eater = "\033[1;34mS\033[0m" if mouth_open else "\033[1;34ms\033[0m"

    rem_len = max(0, width - pos - 1)
    food_chars = ["o" if (i % 2 == 0) else " " for i in range(rem_len)]
    food = "".join(food_chars)

    return f"[{eaten}{eater}{food}]{pct_str}"
