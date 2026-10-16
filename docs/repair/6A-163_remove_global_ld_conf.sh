#!/bin/bash
# 6A-163 repair (user-run): remove the global linker files that older slacky-update builds installed.
#
#   /etc/ld.so.conf.d/audacity.conf   (added /usr/lib64 and /usr/lib to the linker path of the WHOLE system)
#   /etc/ld.so.conf.d/darktable.conf
#   /etc/ld.so.conf.d/inkscape.conf
#
# Current builds no longer ship these files; this script cleans up what is already installed.
#
# What it does, in this order:
#   1. looks at each file; it is removed ONLY when
#        - it is a plain file (not a link),
#        - the package database says it belongs to one of OUR packages (underpants-*, cachyos-*, *_slacky, *_gnomes)
#          and to no other package,
#        - and its text is exactly what our old builds wrote (a file you edited by hand is left alone);
#   2. takes a Btrfs/Snapper snapshot first (the script stops if that fails; --no-snapshot skips it, at your own risk);
#   3. copies each file to a backup folder, removes it, and runs ldconfig once.
# Nothing else is touched. Without --yes it only shows what it WOULD do.
#
# Usage:   sudo ./6A-163_remove_global_ld_conf.sh            (show only)
#          sudo ./6A-163_remove_global_ld_conf.sh --yes      (do it)
#
# Test hook: SU_REPAIR_ROOT=/some/fake/root runs the same logic below that folder (no snapshot, no ldconfig).

set -euo pipefail

APPLY=0
SNAP=1
for a in "$@"; do
    case "$a" in
        --yes) APPLY=1 ;;
        --no-snapshot) SNAP=0 ;;
        -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
        *) echo "Unknown option: $a" >&2; exit 2 ;;
    esac
done

ROOT="${SU_REPAIR_ROOT:-}"
if [ -z "${ROOT}" ] && [ "$(id -u)" != "0" ]; then
    echo "Please run this with sudo." >&2
    exit 1
fi

CONF_DIR="${ROOT}/etc/ld.so.conf.d"
PKGDB="${ROOT}/var/lib/pkgtools/packages"
[ -d "${PKGDB}" ] || PKGDB="${ROOT}/var/log/packages"
[ -d "${PKGDB}" ] || { echo "The package database was not found. Nothing was changed." >&2; exit 1; }

expected_text() {
    case "$1" in
        audacity.conf) printf '/usr/lib64/audacity\n/usr/lib/audacity\n/usr/lib64\n/usr/lib\n' ;;
        darktable.conf) printf '/usr/lib64/darktable\n' ;;
        inkscape.conf) printf '/usr/lib64/inkscape\n' ;;
    esac
}

is_ours() { # package base name or full id
    case "$1" in
        underpants-*|cachyos-*|*_slacky|*_gnomes) return 0 ;;
    esac
    return 1
}

todo=()
for f in audacity.conf darktable.conf inkscape.conf; do
    path="${CONF_DIR}/${f}"
    if [ ! -e "${path}" ] && [ ! -L "${path}" ]; then
        echo "  ${f}: not present, nothing to do."
        continue
    fi
    if [ -L "${path}" ] || [ ! -f "${path}" ]; then
        echo "  ${f}: is not a plain file, left alone."
        continue
    fi
    owners=$(grep -lFx "etc/ld.so.conf.d/${f}" "${PKGDB}"/* 2>/dev/null | xargs -r -n1 basename || true)
    if [ -z "${owners}" ]; then
        echo "  ${f}: belongs to no package, left alone."
        continue
    fi
    foreign=0
    for o in ${owners}; do
        is_ours "${o}" || foreign=1
    done
    if [ "${foreign}" = "1" ]; then
        echo "  ${f}: belongs to a package that is not ours (${owners//$'\n'/ }), left alone."
        continue
    fi
    if [ "$(cat "${path}")" != "$(expected_text "${f}")" ]; then
        echo "  ${f}: the text was changed by hand, left alone."
        continue
    fi
    echo "  ${f}: ours (${owners//$'\n'/ }), will be removed."
    todo+=("${f}")
done

if [ "${#todo[@]}" -eq 0 ]; then
    echo "Nothing to remove."
    exit 0
fi
if [ "${APPLY}" != "1" ]; then
    echo
    echo "This was only a look. Run again with --yes to remove the ${#todo[@]} file(s) above."
    exit 0
fi

if [ -z "${ROOT}" ] && [ "${SNAP}" = "1" ]; then
    if command -v snapper >/dev/null 2>&1 && [ "$(findmnt -n -o FSTYPE / 2>/dev/null || true)" = "btrfs" ]; then
        snapper -c root create -d "before 6A-163 ld.so.conf.d cleanup" || { echo "The snapshot failed. Nothing was changed." >&2; exit 1; }
        echo "Snapshot taken."
    else
        echo "No Btrfs/Snapper snapshot is possible here. Nothing was changed. (Use --no-snapshot to go on without one.)" >&2
        exit 1
    fi
fi

BACKUP="${ROOT}/root/slacky-ld-conf-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${BACKUP}"
for f in "${todo[@]}"; do
    cp -p "${CONF_DIR}/${f}" "${BACKUP}/${f}"
    rm -f "${CONF_DIR}/${f}"
    echo "  removed ${f} (copy in ${BACKUP})"
done
if [ -z "${ROOT}" ]; then
    /sbin/ldconfig
fi
echo "Done."
