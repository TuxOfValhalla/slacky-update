#!/bin/bash
# 6A-175 repair (user-run): remove the root cron job that older slacky-update builds installed for Microsoft Edge.
#
#   /etc/cron.daily/microsoft-edge   (a link to Microsoft's apt repository helper, written for Debian/Ubuntu systems;
#                                     on Slackware it runs as root every day and does nothing useful)
#
# Current builds no longer ship this file; this script cleans up what is already installed.
#
# What it does, in this order:
#   1. looks at that ONE path; it is removed ONLY when
#        - it is a link to /opt/microsoft/msedge/cron/microsoft-edge (or a plain file with the same name that is the
#          Edge helper: it mentions the apt sources of packages.microsoft.com),
#        - the package database says it belongs to our Edge package (underpants-microsoft-edge-*, build tag _slacky or
#          _gnomes) and to no other package;
#   2. takes a Btrfs/Snapper snapshot first (the script stops if that fails; --no-snapshot skips it, at your own risk);
#   3. keeps a note of the link (target) in a backup folder, removes the path, and nothing else.
# Without --yes it only shows what it WOULD do.
#
# Usage:   sudo ./6A-175_remove_edge_apt_cron.sh            (show only)
#          sudo ./6A-175_remove_edge_apt_cron.sh --yes      (do it)
#
# Test hook: SU_REPAIR_ROOT=/some/fake/root runs the same logic below that folder (no snapshot).

set -euo pipefail

APPLY=0
SNAP=1
for a in "$@"; do
    case "$a" in
        --yes) APPLY=1 ;;
        --no-snapshot) SNAP=0 ;;
        -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
        *) echo "Unknown option: $a" >&2; exit 2 ;;
    esac
done

ROOT="${SU_REPAIR_ROOT:-}"
if [ -z "${ROOT}" ] && [ "$(id -u)" != "0" ]; then
    echo "Please run this with sudo." >&2
    exit 1
fi

REL="etc/cron.daily/microsoft-edge"
PATH_ON_DISK="${ROOT}/${REL}"
PKGDB="${ROOT}/var/lib/pkgtools/packages"
[ -d "${PKGDB}" ] || PKGDB="${ROOT}/var/log/packages"
[ -d "${PKGDB}" ] || { echo "The package database was not found. Nothing was changed." >&2; exit 1; }

is_edge_pkg() { # full package id
    case "$1" in
        underpants-microsoft-edge-*_slacky|underpants-microsoft-edge-*_gnomes) return 0 ;;
    esac
    return 1
}

if [ ! -e "${PATH_ON_DISK}" ] && [ ! -L "${PATH_ON_DISK}" ]; then
    echo "  /${REL}: not present, nothing to do."
    exit 0
fi

if [ -L "${PATH_ON_DISK}" ]; then
    target=$(readlink "${PATH_ON_DISK}")
    if [ "${target}" != "/opt/microsoft/msedge/cron/microsoft-edge" ]; then
        echo "  /${REL}: a link to ${target}, which is not the Edge helper, left alone."
        exit 0
    fi
elif [ -f "${PATH_ON_DISK}" ]; then
    if ! grep -q 'packages\.microsoft\.com' "${PATH_ON_DISK}" 2>/dev/null; then
        echo "  /${REL}: a plain file that is not the Edge helper, left alone."
        exit 0
    fi
    target="(plain file)"
else
    echo "  /${REL}: is not a file or link, left alone."
    exit 0
fi

owners=$(grep -lFx -- "${REL}" "${PKGDB}"/* 2>/dev/null | xargs -r -n1 basename || true)
if [ -z "${owners}" ]; then
    echo "  /${REL}: belongs to no package, left alone."
    exit 0
fi
for o in ${owners}; do
    if ! is_edge_pkg "${o}"; then
        echo "  /${REL}: belongs to a package that is not our Edge package (${owners//$'\n'/ }), left alone."
        exit 0
    fi
done
echo "  /${REL}: ours (${owners//$'\n'/ }), will be removed."

if [ "${APPLY}" != "1" ]; then
    echo
    echo "This was only a look. Run again with --yes to remove it."
    exit 0
fi

if [ -z "${ROOT}" ] && [ "${SNAP}" = "1" ]; then
    if command -v snapper >/dev/null 2>&1 && [ "$(findmnt -n -o FSTYPE / 2>/dev/null || true)" = "btrfs" ]; then
        snapper -c root create -d "before 6A-175 Edge apt cron cleanup" || { echo "The snapshot failed. Nothing was changed." >&2; exit 1; }
        echo "Snapshot taken."
    else
        echo "No Btrfs/Snapper snapshot is possible here. Nothing was changed. (Use --no-snapshot to go on without one.)" >&2
        exit 1
    fi
fi

BACKUP="${ROOT}/root/slacky-edge-cron-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${BACKUP}"
if [ -L "${PATH_ON_DISK}" ]; then
    printf '%s -> %s\n' "/${REL}" "${target}" > "${BACKUP}/microsoft-edge.link"
else
    cp -p -- "${PATH_ON_DISK}" "${BACKUP}/microsoft-edge"
fi
rm -f -- "${PATH_ON_DISK}"
echo "  removed /${REL} (note in ${BACKUP})"
echo "Done."
