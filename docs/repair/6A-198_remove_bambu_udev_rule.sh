#!/bin/bash
# 6A-198 repair (user-run): remove the device rule that older Bambu Studio builds installed.
#
#   99-bambulab-devices.rules   (opened every CH340 USB-serial device on the computer to ALL users, mode 0666; so any user or
#                                program could talk to, for example, a 3D printer controller or any other serial adapter)
#
# Current builds no longer ship this file; this script cleans up what is already installed.
#
# What it does, in this order:
#   1. looks at that file name in the usual udev rule folders; each one found is removed ONLY when
#        - it is a plain file (not a link) that mentions the CH340 vendor id (1a86),
#        - the package database says it belongs to our Bambu Studio package (underpants-bambu-studio-* or
#          cachyos-gnome-bambu-studio-*, build tag _slacky or _gnomes) and to no other package,
#        - it is unchanged: not newer than the package database entry (an edit after the install = left alone);
#   2. takes a Btrfs/Snapper snapshot first (the script stops if that fails; --no-snapshot skips it, at your own risk);
#   3. keeps a copy of the file in a backup folder, removes it, and tells udev to reload its rules.
# Without --yes it only shows what it WOULD do. A serial adapter that is plugged in keeps its old access until it is unplugged
# and plugged in again.
#
# Usage:   sudo ./6A-198_remove_bambu_udev_rule.sh            (show only)
#          sudo ./6A-198_remove_bambu_udev_rule.sh --yes      (do it)
#
# Test hook: SU_REPAIR_ROOT=/some/fake/root runs the same logic below that folder (no snapshot, no udev reload).

set -euo pipefail

APPLY=0
SNAP=1
for a in "$@"; do
    case "$a" in
        --yes) APPLY=1 ;;
        --no-snapshot) SNAP=0 ;;
        -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
        *) echo "Unknown option: $a" >&2; exit 2 ;;
    esac
done

ROOT="${SU_REPAIR_ROOT:-}"
if [ -z "${ROOT}" ] && [ "$(id -u)" != "0" ]; then
    echo "Please run this with sudo." >&2
    exit 1
fi

NAME="99-bambulab-devices.rules"
CANDIDATES=("etc/udev/rules.d/${NAME}" "lib/udev/rules.d/${NAME}" "usr/lib/udev/rules.d/${NAME}" "usr/lib64/udev/rules.d/${NAME}")
PKGDB="${ROOT}/var/lib/pkgtools/packages"
[ -d "${PKGDB}" ] || PKGDB="${ROOT}/var/log/packages"
[ -d "${PKGDB}" ] || { echo "The package database was not found. Nothing was changed." >&2; exit 1; }

is_bambu_pkg() { # full package id
    case "$1" in
        underpants-bambu-studio-*_slacky|underpants-bambu-studio-*_gnomes|cachyos-gnome-bambu-studio-*_gnomes|cachyos-gnome-bambu-studio-*_slacky) return 0 ;;
    esac
    return 1
}

remove=()
for REL in "${CANDIDATES[@]}"; do
    P="${ROOT}/${REL}"
    if [ ! -e "${P}" ] && [ ! -L "${P}" ]; then continue; fi
    if [ -L "${P}" ] || [ ! -f "${P}" ]; then echo "  /${REL}: is not a plain file, left alone."; continue; fi
    if ! grep -qi '1a86' "${P}" 2>/dev/null; then echo "  /${REL}: does not look like the CH340 rule, left alone."; continue; fi
    owners=$(grep -lFx -- "${REL}" "${PKGDB}"/* 2>/dev/null | xargs -r -n1 basename || true)
    if [ -z "${owners}" ]; then echo "  /${REL}: belongs to no package, left alone."; continue; fi
    ok=1
    for o in ${owners}; do
        if ! is_bambu_pkg "${o}"; then ok=0; fi
    done
    if [ "${ok}" != "1" ]; then
        echo "  /${REL}: belongs to a package that is not our Bambu Studio package (${owners//$'\n'/ }), left alone."
        continue
    fi
    for o in ${owners}; do
        if [ "${P}" -nt "${PKGDB}/${o}" ]; then ok=0; fi
    done
    if [ "${ok}" != "1" ]; then echo "  /${REL}: was changed after the install, left alone."; continue; fi
    echo "  /${REL}: ours (${owners//$'\n'/ }) and unchanged, will be removed."
    remove+=("${REL}")
done

if [ "${#remove[@]}" -eq 0 ]; then
    echo "  Nothing to remove."
    exit 0
fi

if [ "${APPLY}" != "1" ]; then
    echo
    echo "This was only a look. Run again with --yes to remove it."
    exit 0
fi

if [ -z "${ROOT}" ] && [ "${SNAP}" = "1" ]; then
    if command -v snapper >/dev/null 2>&1 && [ "$(findmnt -n -o FSTYPE / 2>/dev/null || true)" = "btrfs" ]; then
        snapper -c root create -d "before 6A-198 bambu udev rule removal" || { echo "The snapshot failed. Nothing was changed." >&2; exit 1; }
        echo "Snapshot taken."
    else
        echo "No Btrfs/Snapper snapshot is possible here. Nothing was changed. (Use --no-snapshot to go on without one.)" >&2
        exit 1
    fi
fi

BACKUP="${ROOT}/root/slacky-bambu-udev-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${BACKUP}"
for REL in "${remove[@]}"; do
    d="${BACKUP}/$(echo "${REL}" | tr '/' '_')"
    cp -p -- "${ROOT}/${REL}" "${d}"
    rm -f -- "${ROOT}/${REL}"
    echo "  removed /${REL} (copy in ${d})"
done
if [ -z "${ROOT}" ] && command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload-rules && echo "udev rules reloaded." || echo "Could not reload the udev rules; they are read again at the next start."
fi
echo "Done."
