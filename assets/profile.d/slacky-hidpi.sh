#!/bin/sh
# /etc/profile.d/slacky-hidpi.sh
# Universal & Dynamic HiDPI & Wayland scaling for Slackware
# Supports Hyprland, KDE Plasma (Wayland & X11), XFCE, and GNOME

# Wayland Compositor Auto-Routing (Hyprland, KDE Wayland, Sway, GNOME Wayland)
if [ "${XDG_SESSION_TYPE:-}" = "wayland" ] || [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    if [ -z "${QT_QPA_PLATFORM+x}" ]; then
        export QT_QPA_PLATFORM="wayland;xcb"
    fi
    if [ -z "${GDK_BACKEND+x}" ]; then
        export GDK_BACKEND="wayland,x11,*"
    fi
    if [ -z "${CLUTTER_BACKEND+x}" ]; then
        export CLUTTER_BACKEND="wayland"
    fi
    if [ -z "${SDL_VIDEODRIVER+x}" ]; then
        export SDL_VIDEODRIVER="wayland,x11"
    fi
    unset QT_AUTO_SCREEN_SCALE_FACTOR QT_ENABLE_HIGHDPI_SCALING 2>/dev/null || true
else
    # X11 HiDPI scaling
    if [ -z "${QT_AUTO_SCREEN_SCALE_FACTOR+x}" ]; then
        export QT_AUTO_SCREEN_SCALE_FACTOR=1
    fi
    if [ -z "${QT_ENABLE_HIGHDPI_SCALING+x}" ]; then
        export QT_ENABLE_HIGHDPI_SCALING=1
    fi
    if [ -z "${QT_SCALE_FACTOR_ROUNDING_POLICY+x}" ]; then
        export QT_SCALE_FACTOR_ROUNDING_POLICY=PassThrough
    fi
fi
