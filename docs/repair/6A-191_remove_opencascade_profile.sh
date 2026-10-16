#!/bin/bash
# 6A-191 repair (user-run): remove the login-environment script that older FreeCAD builds installed.
#
#   /etc/profile.d/opencascade.sh   (shipped by the opencascade part of the FreeCAD package; every user's shell reads it at
#                                    login, so a program package changes the environment of the whole system)
#
# Current builds no longer ship this file; this script cleans up what is already installed.
#
# What it does, in this order:
#   1. looks at that ONE path; it is removed ONLY when
#        - it is a plain file (not a link) that mentions OpenCASCADE,
#        - the package database says it belongs to our FreeCAD package (underpants-freecad-*, build tag _slacky or _gnomes)
#          and to no other package (if another package lists it too, for example the shared runtime, it is left alone),
#        - it is unchanged: not newer than the package database entry of that package (an edit after the install = left alone);
#   2. takes a Btrfs/Snapper snapshot first (the script stops if that fails; --no-snapshot skips it, at your own risk);
#   3. keeps a copy of the file in a backup folder, removes the path, and nothing else.
# Without --yes it only shows what it WOULD do. Open shells keep the old environment until they are closed.
#
# Usage:   sudo ./6A-191_remove_opencascade_profile.sh            (show only)
#          sudo ./6A-191_remove_opencascade_profile.sh --yes      (do it)
#
# Test hook: SU_REPAIR_ROOT=/some/fake/root runs the same logic below that folder (no snapshot).

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

REL="etc/profile.d/opencascade.sh"
PATH_ON_DISK="${ROOT}/${REL}"
PKGDB="${ROOT}/var/lib/pkgtools/packages"
[ -d "${PKGDB}" ] || PKGDB="${ROOT}/var/log/packages"
[ -d "${PKGDB}" ] || { echo "The package database was not found. Nothing was changed." >&2; exit 1; }

is_freecad_pkg() { # full package id
    case "$1" in
        underpants-freecad-*_slacky|underpants-freecad-*_gnomes) return 0 ;;
    esac
    return 1
}

if [ ! -e "${PATH_ON_DISK}" ] && [ ! -L "${PATH_ON_DISK}" ]; then
    echo "  /${REL}: not present, nothing to do."
    exit 0
fi
if [ -L "${PATH_ON_DISK}" ] || [ ! -f "${PATH_ON_DISK}" ]; then
    echo "  /${REL}: is not a plain file, left alone."
    exit 0
fi
if ! grep -qi 'opencascade' "${PATH_ON_DISK}" 2>/dev/null; then
    echo "  /${REL}: does not look like the OpenCASCADE script, left alone."
    exit 0
fi

owners=$(grep -lFx -- "${REL}" "${PKGDB}"/* 2>/dev/null | xargs -r -n1 basename || true)
if [ -z "${owners}" ]; then
    echo "  /${REL}: belongs to no package, left alone."
    exit 0
fi
for o in ${owners}; do
    if ! is_freecad_pkg "${o}"; then
        echo "  /${REL}: belongs to a package that is not our FreeCAD package (${owners//$'\n'/ }), left alone."
        exit 0
    fi
done
for o in ${owners}; do
    if [ "${PATH_ON_DISK}" -nt "${PKGDB}/${o}" ]; then
        echo "  /${REL}: was changed after the install of ${o}, left alone."
        exit 0
    fi
done
echo "  /${REL}: ours (${owners//$'\n'/ }) and unchanged, will be removed."

if [ "${APPLY}" != "1" ]; then
    echo
    echo "This was only a look. Run again with --yes to remove it."
    exit 0
fi

if [ -z "${ROOT}" ] && [ "${SNAP}" = "1" ]; then
    if command -v snapper >/dev/null 2>&1 && [ "$(findmnt -n -o FSTYPE / 2>/dev/null || true)" = "btrfs" ]; then
        snapper -c root create -d "before 6A-191 opencascade profile cleanup" || { echo "The snapshot failed. Nothing was changed." >&2; exit 1; }
        echo "Snapshot taken."
    else
        echo "No Btrfs/Snapper snapshot is possible here. Nothing was changed. (Use --no-snapshot to go on without one.)" >&2
        exit 1
    fi
fi

BACKUP="${ROOT}/root/slacky-opencascade-profile-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${BACKUP}"
cp -p -- "${PATH_ON_DISK}" "${BACKUP}/opencascade.sh"
rm -f -- "${PATH_ON_DISK}"
echo "  removed /${REL} (copy in ${BACKUP})"
echo "Done."
