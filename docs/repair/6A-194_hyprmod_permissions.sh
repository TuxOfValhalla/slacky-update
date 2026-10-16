#!/bin/bash
# 6A-194 repair (user-run): remove group/world write permission from the installed HyprMod package.
#
# An older build of underpants-hyprmod put files on the system that ANY user could change (modes 0666 / 0777), for example
# /usr/bin/hyprmod and the Python modules below site-packages/hypr*. Those files are run by you, so a change by another user or
# program would run with your rights. New builds never pack such modes. This script cleans up what is already installed.
#
# What it does, in this order:
#   1. reads the package database entry of underpants-hyprmod-* (our package: build tag _slacky or _gnomes) and looks at ONLY the
#      paths listed there;
#   2. of those, selects the entries that are owned by root and are currently writable by group or others (links are never touched);
#   3. takes a Btrfs/Snapper snapshot first (the script stops if that fails; --no-snapshot skips it, at your own risk);
#   4. runs "chmod go-w" on exactly those entries and writes a list of the old modes to a backup folder.
# Nothing else is changed: no ownership, no owner permissions, no file outside the package list.
# Without --yes it only shows what it WOULD do.
#
# Usage:   sudo ./6A-194_hyprmod_permissions.sh            (show only)
#          sudo ./6A-194_hyprmod_permissions.sh --yes      (do it)
#
# Test hook: SU_REPAIR_ROOT=/some/fake/root runs the same logic below that folder (no snapshot, no root needed).

set -euo pipefail

APPLY=0
SNAP=1
for a in "$@"; do
    case "$a" in
        --yes) APPLY=1 ;;
        --no-snapshot) SNAP=0 ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "Unknown option: $a" >&2; exit 2 ;;
    esac
done

ROOT="${SU_REPAIR_ROOT:-}"
if [ -z "${ROOT}" ] && [ "$(id -u)" != "0" ]; then
    echo "Please run this with sudo." >&2
    exit 1
fi

PKGDB="${ROOT}/var/lib/pkgtools/packages"
[ -d "${PKGDB}" ] || PKGDB="${ROOT}/var/log/packages"
[ -d "${PKGDB}" ] || { echo "The package database was not found. Nothing was changed." >&2; exit 1; }

# test hook only: with SU_REPAIR_ROOT set, the owner to look for may be changed (a fake root is not owned by root)
WANT_UID=0
[ -n "${ROOT}" ] && WANT_UID="${SU_REPAIR_UID:-0}"

shopt -s nullglob
pkgs=()
for f in "${PKGDB}"/underpants-hyprmod-*_slacky "${PKGDB}"/underpants-hyprmod-*_gnomes; do
    pkgs+=("${f}")
done
if [ "${#pkgs[@]}" -eq 0 ]; then
    echo "  underpants-hyprmod is not installed, nothing to do."
    exit 0
fi

todo=()      # "oldmode<TAB>path"
for pk in "${pkgs[@]}"; do
    in_list=0
    while IFS= read -r line; do
        if [ "${in_list}" = "0" ]; then
            [ "${line}" = "FILE LIST:" ] && in_list=1
            continue
        fi
        rel="${line#./}"
        rel="${rel%/}"
        [ -n "${rel}" ] || continue
        case "${rel}" in install|install/*|/*|*..*) continue ;; esac
        full="${ROOT}/${rel}"
        [ -L "${full}" ] && continue
        [ -e "${full}" ] || continue
        info=$(stat -c '%u %a' -- "${full}" 2>/dev/null) || continue
        uid="${info%% *}"; mode="${info##* }"
        [ "${uid}" = "${WANT_UID}" ] || continue
        if (( (8#${mode}) & 8#022 )); then
            todo+=("${mode}"$'\t'"${full}")
        fi
    done < "${pk}"
done

if [ "${#todo[@]}" -eq 0 ]; then
    echo "  No root-owned HyprMod file is writable by group or others. Nothing to do."
    exit 0
fi

echo "  ${#todo[@]} entr(ies) of $(printf '%s ' "${pkgs[@]##*/}")are writable by group or others:"
n=0
for t in "${todo[@]}"; do
    n=$((n + 1))
    if [ "${n}" -le 15 ]; then echo "    ${t%%$'\t'*}  ${t#*$'\t'}"; fi
done
[ "${n}" -gt 15 ] && echo "    ... and $((n - 15)) more"

if [ "${APPLY}" != "1" ]; then
    echo
    echo "This was only a look. Run again with --yes to remove group/world write from these entries."
    exit 0
fi

if [ -z "${ROOT}" ] && [ "${SNAP}" = "1" ]; then
    if command -v snapper >/dev/null 2>&1 && [ "$(findmnt -n -o FSTYPE / 2>/dev/null || true)" = "btrfs" ]; then
        snapper -c root create -d "before 6A-194 hyprmod permission repair" || { echo "The snapshot failed. Nothing was changed." >&2; exit 1; }
        echo "Snapshot taken."
    else
        echo "No Btrfs/Snapper snapshot is possible here. Nothing was changed. (Use --no-snapshot to go on without one.)" >&2
        exit 1
    fi
fi

BACKUP="${ROOT}/root/slacky-hyprmod-modes-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${BACKUP}"
: > "${BACKUP}/old-modes.txt"
for t in "${todo[@]}"; do
    printf '%s\t%s\n' "${t%%$'\t'*}" "${t#*$'\t'}" >> "${BACKUP}/old-modes.txt"
    chmod go-w -- "${t#*$'\t'}"
done
echo "  changed ${#todo[@]} entr(ies) (old modes in ${BACKUP}/old-modes.txt)"
echo "Done."
