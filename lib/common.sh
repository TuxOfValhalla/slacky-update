#!/usr/bin/env bash
# --- [ COMMON DEFINITIONS & PATH RESOLUTION ] ---

set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

PKG_UPGRADE_CMD=$(command -v upgradepkg 2>/dev/null || echo "/sbin/upgradepkg")
PKG_REMOVE_CMD=$(command -v removepkg 2>/dev/null || echo "/sbin/removepkg")
PKG_INSTALL_CMD=$(command -v installpkg 2>/dev/null || echo "/sbin/installpkg")
PKG_MAKE_CMD=$(command -v makepkg 2>/dev/null || echo "/sbin/makepkg")
LDCONFIG_CMD=$(command -v ldconfig 2>/dev/null || echo "/sbin/ldconfig")
REBOOT_CMD=$(command -v reboot 2>/dev/null || echo "/sbin/reboot")
DEPMOD_CMD=$(command -v depmod 2>/dev/null || echo "/sbin/depmod")
MKINITRD_CMD=$(command -v mkinitrd 2>/dev/null || echo "/sbin/mkinitrd")
SLACKPKG_CMD=$(command -v slackpkg 2>/dev/null || echo "/usr/sbin/slackpkg")
DRACUT_CMD=$(command -v dracut 2>/dev/null || echo "/usr/bin/dracut")

BOLD="\033[1m"
DIM="\033[2m"
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
MAGENTA="\033[1;35m"
CYAN="\033[1;36m"
WHITE="\033[1;37m"
DARK_GRAY="\033[1;30m"
GRAY="\033[0;37m"
RESET="\033[0m"

CACHE_DIR="/var/cache/slacky-update"
LOG_FILE="/var/log/slacky-update.log"

if [ -z "${I18N_PY:-}" ]; then
    for cand in "${SCRIPT_DIR:-}/../lib/slacky_update_i18n.py" \
                "${APP_DIR:-}/slacky_update_i18n.py" \
                "/usr/share/slacky-update/lib/slacky_update_i18n.py" \
                "/usr/local/lib/slacky-update/slacky_update_i18n.py"; do
        if [ -f "${cand}" ]; then
            I18N_PY="${cand}"
            break
        fi
    done
fi

if ! type _ >/dev/null 2>&1; then
    _() {
        if [ -n "${I18N_PY:-}" ] && [ -f "${I18N_PY}" ]; then
            python3 "${I18N_PY}" "$@"
        else
            echo "$1"
        fi
    }
fi

MOK_CERT=""
MOK_CRT=""
MOK_DER=""
MOK_KEY=""

HAS_NVIDIA=false
HAS_AMD=false
HAS_INTEL=false
IS_LAPTOP=false
IS_HYBRID_GPU=false

CURRENT_VERSION="1.0_RC2"
RELEASE_CODENAME="Dark Star"

CURL_CONNECT_TIMEOUT=10
CURL_SPEED_LIMIT=1024
CURL_SPEED_TIME=25

# 6A-118: SpiderSense hardware facts, probed live once per run (~20 ms incl. python start) and shared as HW_* variables.
# Every hardware question (laptop? NVIDIA? which GPU drives the screen? CPU level?) is answered from here; the old
# per-module probes stay below only as the fallback when the profile cannot run.
ss_hw_load() {
    [ "${SLACKY_HW_LOADED:-0}" = "1" ] && return 0
    local py="${APP_DIR:-/usr/share/slacky-update/lib}/spidersense_hw.py" out line
    [ -f "${py}" ] || py="/usr/share/slacky-update/lib/spidersense_hw.py"
    [ -f "${py}" ] || return 1
    out=$(PYTHONSAFEPATH=1 python3 -I "${py}" get shell 2>/dev/null) || return 1
    while IFS= read -r line; do
        case "${line}" in HW_[A-Z_]*=*) export "${line?}" ;; esac
    done <<< "${out}"
    [ -n "${HW_CHASSIS:-}" ] || return 1
    export SLACKY_HW_LOADED=1
}

is_laptop_chassis() {
    if ss_hw_load; then [ "${HW_LAPTOP}" = "true" ]; return; fi
    local chassis
    chassis=$(cat /sys/class/dmi/id/chassis_type 2>/dev/null || echo "")
    if [[ "${chassis}" =~ ^(8|9|10|14|30|31|32)$ ]]; then
        return 0
    fi
    if [ -d /sys/class/power_supply ]; then
        if ls /sys/class/power_supply/BAT* 1>/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

detect_cpu_tier() {
    if ss_hw_load && [ -n "${HW_CPU_TIER:-}" ]; then echo "${HW_CPU_TIER}"; return 0; fi
    local cpuinfo="/proc/cpuinfo"
    if [ ! -r "${cpuinfo}" ]; then
        echo "generic"
        return 0
    fi
    if grep -q "avx512f" "${cpuinfo}" && \
       grep -q "avx512bw" "${cpuinfo}" && \
       grep -q "avx512cd" "${cpuinfo}" && \
       grep -q "avx512dq" "${cpuinfo}" && \
       grep -q "avx512vl" "${cpuinfo}"; then
        if grep -q "AuthenticAMD" "${cpuinfo}"; then
            echo "znver4"
        else
            echo "v4"
        fi
    elif grep -q "avx2" "${cpuinfo}" && \
         grep -q "fma" "${cpuinfo}" && \
         grep -q "bmi1" "${cpuinfo}" && \
         grep -q "bmi2" "${cpuinfo}"; then
        echo "v3"
    else
        echo "generic"
    fi
}

get_cachyos_repo_url() {
    local tier="${1:-${SLACKY_CPU_TIER:-generic}}"
    case "${tier}" in
        znver4)
            echo "https://mirror.cachyos.org/repo/x86_64_v4/cachyos-znver4/"
            ;;
        v4)
            echo "https://mirror.cachyos.org/repo/x86_64_v4/cachyos-v4/"
            ;;
        v3)
            echo "https://mirror.cachyos.org/repo/x86_64_v3/cachyos-v3/"
            ;;
        *)
            echo "https://mirror.cachyos.org/repo/x86_64/cachyos/"
            ;;
    esac
}

# 6A-355 (env hooks): a CPU tier handed in from the environment is only honoured in the self-tests, or when this CPU
# really supports it (a value above what the CPU can do would download kernels that crash at boot).
slacky_cpu_tier_rank() { case "$1" in generic) echo 0 ;; v3) echo 1 ;; v4) echo 2 ;; znver4) echo 3 ;; *) echo -1 ;; esac; }
_slacky_cpu_tier_detected="$(detect_cpu_tier)"
if [ -n "${SLACKY_CPU_TIER:-}" ] && [ "${SLACKY_SELFTEST:-0}" != "1" ]; then
    _slacky_cpu_tier_want=$(slacky_cpu_tier_rank "${SLACKY_CPU_TIER}")
    if [ "${_slacky_cpu_tier_want}" -lt 0 ] || [ "${_slacky_cpu_tier_want}" -gt "$(slacky_cpu_tier_rank "${_slacky_cpu_tier_detected}")" ]; then
        SLACKY_CPU_TIER="${_slacky_cpu_tier_detected}"
    fi
    unset _slacky_cpu_tier_want
fi
export SLACKY_CPU_TIER="${SLACKY_CPU_TIER:-${_slacky_cpu_tier_detected}}"
unset _slacky_cpu_tier_detected

compare_versions_strictly_greater() {
    local v1="$1"
    local v2="$2"
    python3 -c "
import sys, re

def normalize_v(v):
    s = str(v).strip()
    s = re.sub(r'-cachyos.*$', '', s)
    s = re.sub(r'(\d+\.\d+)\.(rc\d+)', r'\1.0-\2', s)
    s = re.sub(r'(\d+\.\d+)-(rc\d+)', r'\1.0-\2', s)
    if not re.search(r'-\d+$', s):
        s = s + '-1'
    return s

def parse_v(v_str):
    clean = normalize_v(v_str)
    clean = re.sub(r'^[vV]', '', clean).strip()
    tokens = re.split(r'[-._]', clean)
    res = []
    for t in tokens:
        if not t:
            continue
        sub = re.findall(r'(\d+|\D+)', t)
        for s in sub:
            if s.isdigit():
                res.append((1, int(s)))
            else:
                res.append((0, s.lower()))
    return res

try:
    up = parse_v('$v1')
    cur = parse_v('$v2')
    if up > cur:
        sys.exit(0)
except Exception:
    pass
sys.exit(1)
" 2>/dev/null && echo "true" || echo "false"
}

# Cleanly drop every DKMS registration for one kernel so a later reinstall
# does not show a ghost "installed" state. `dkms remove -k <kver> --all` is
# invalid (needs -m/-v), so enumerate `dkms status` and remove per module.
# Overridable for tests: DKMS_BIN, DKMS_ROOT, DKMS_SUDO (empty = no sudo).
dkms_purge_kernel() {
    local kver="${1:-}"
    [ -n "${kver}" ] || return 0
    [ "${kver}" != "source" ] && [ "${kver}" != "build" ] || return 0
    [ "${kver}" != "$(uname -r)" ] || return 0   # never touch the booted kernel

    local dkms_bin="${DKMS_BIN:-$(command -v dkms 2>/dev/null || echo /usr/sbin/dkms)}"
    local root="${DKMS_ROOT:-/var/lib/dkms}"
    local sudo_cmd="${DKMS_SUDO-sudo}"

    if [ -x "${dkms_bin}" ]; then
        local line m v k
        while IFS= read -r line; do
            line="${line%%:*}"
            read -r m v k _ <<< "$(printf '%s' "${line}" | tr '/,' '  ')"
            [ -n "${m}" ] && [ -n "${v}" ] && [ "${k:-}" = "${kver}" ] || continue
            ${sudo_cmd} "${dkms_bin}" remove -m "${m}" -v "${v}" -k "${kver}" --force >/dev/null 2>&1 || true
        done < <("${dkms_bin}" status 2>/dev/null || true)
    fi

    # Leftover ghost entries: per-kernel build dirs and kernel-<kver>-* symlinks
    local p
    for p in "${root}"/*/kernel-"${kver}"-* "${root}"/*/*/"${kver}"; do
        if [ -L "${p}" ]; then
            ${sudo_cmd} rm -f "${p}" 2>/dev/null || true
        elif [ -d "${p}" ]; then
            ${sudo_cmd} rm -rf "${p}" 2>/dev/null || true
        fi
    done
    # Dangling /usr/src/linux-<flavor> links left by removed kernels
    local src_root="${DKMS_SRC_ROOT:-/usr/src}"
    for p in "${src_root}"/linux-*; do
        if [ -L "${p}" ] && [ ! -e "${p}" ]; then
            ${sudo_cmd} rm -f "${p}" 2>/dev/null || true
        fi
    done
    return 0
}

# Automatically purge orphaned DKMS registrations for kernels that no longer
# exist in /lib/modules or /usr/lib/modules (safe garbage collector; never touches uname -r),
# and self-heal dead module version registrations whose source tree has been removed.
dkms_purge_orphaned_ghosts() {
    local root="${DKMS_ROOT:-/var/lib/dkms}"
    local mod_root="${MODULES_ROOT:-/lib/modules}"
    local sudo_cmd="${DKMS_SUDO-sudo}"
    local active_k
    active_k="$(uname -r 2>/dev/null || echo '')"
    [ -d "${root}" ] || return 0

    # 1. Purge registrations for kernels that no longer exist in /lib/modules
    local checked=()
    local p kver
    for p in "${root}"/*/kernel-*-* "${root}"/*/*/*; do
        [ -e "${p}" ] || [ -L "${p}" ] || continue
        kver=""
        if [[ "${p}" =~ kernel-(.+)-[^-]+$ ]]; then
            kver="${BASH_REMATCH[1]}"
        elif [ -d "${p}" ]; then
            kver=$(basename "${p}")
        fi
        [ -n "${kver}" ] || continue
        [ "${kver}" != "source" ] && [ "${kver}" != "build" ] || continue
        [ "${kver}" != "${active_k}" ] || continue
        [[ " ${checked[*]:-} " =~ [[:space:]]${kver}[[:space:]] ]] && continue
        checked+=("${kver}")

        # If kernel modules directory does NOT exist on the filesystem, it is an orphaned ghost!
        if [ ! -d "${mod_root}/${kver}" ] && [ ! -d "/usr/lib/modules/${kver}" ]; then
            dkms_purge_kernel "${kver}"
        fi
    done

    # 2. Self-heal dead module registrations where source tree or dkms.conf is missing
    local mod_dir
    for mod_dir in "${root}"/*; do
        [ -d "${mod_dir}" ] || continue
        local mod_name
        mod_name=$(basename "${mod_dir}")
        local ver_dir
        for ver_dir in "${mod_dir}"/*; do
            [ -d "${ver_dir}" ] || continue
            local v_name
            v_name=$(basename "${ver_dir}")
            [[ "${v_name}" =~ ^kernel- ]] && continue

            # Check if source tree or dkms.conf is missing
            if [ ! -f "${ver_dir}/source/dkms.conf" ] && [ ! -f "${ver_dir}/dkms.conf" ]; then
                ${sudo_cmd} rm -rf "${ver_dir}" 2>/dev/null || true
                for ksym in "${mod_dir}"/kernel-*-*; do
                    if [ -L "${ksym}" ]; then
                        local target
                        target=$(readlink "${ksym}" 2>/dev/null || true)
                        if [[ "${target}" =~ ^${v_name}/ ]]; then
                            ${sudo_cmd} rm -f "${ksym}" 2>/dev/null || true
                        fi
                    fi
                done
            fi
        done
    done
}

# Compute list of custom CachyOS/Arch kernels beyond retention (or older RC kernels)
# that are slated for removal, so DKMS and module sync never waste I/O compiling for them.
get_obsolete_cachyos_kernels() {
    python3 -c "
import os, re
from collections import defaultdict

def get_flavor(k_str):
    if '-cachyos-bore-lto' in k_str or '-cachyos-lto' in k_str:
        return 'lto'
    elif '-cachyos-rt-bore' in k_str or '-cachyos-rt' in k_str:
        return 'rt-bore'
    elif '-cachyos-bore' in k_str:
        return 'bore'
    elif '-cachyos-eevdf' in k_str:
        return 'eevdf'
    elif '-cachyos-bmq' in k_str:
        return 'bmq'
    elif '-cachyos-deckify' in k_str:
        return 'deckify'
    elif '-cachyos-rc' in k_str:
        return 'rc'
    elif '-cachyos-lts' in k_str:
        return 'lts'
    elif '-cachyos' in k_str:
        return 'standard'
    elif '-zen' in k_str or k_str.endswith('-zen'):
        return 'zen'
    elif '-arch' in k_str:
        return 'arch'
    return 'other'

def parse_ver(v_str):
    nums = [int(x) for x in re.findall(r'\d+', v_str)]
    return nums if nums else [0]

def is_custom_k(name):
    return ('cachyos' in name or '-zen' in name or '-arch' in name or name in ('vmlinuz-linux', 'vmlinuz-linux-zen', 'linux', 'linux-zen'))

custom_kernels = set()
if os.path.exists('/boot'):
    try:
        for f in os.listdir('/boot'):
            if is_custom_k(f) and f.startswith('vmlinuz-') and not os.path.islink(os.path.join('/boot', f)):
                custom_kernels.add(f.replace('vmlinuz-', ''))
    except Exception:
        pass

for mdir in ('/lib/modules', '/usr/lib/modules'):
    if os.path.exists(mdir):
        for d in os.listdir(mdir):
            if is_custom_k(d):
                custom_kernels.add(d)

active = os.uname().release
by_flavor = defaultdict(list)
for k in custom_kernels:
    flv = get_flavor(k)
    if flv != 'other':
        by_flavor[flv].append(k)

to_keep = set()
if active in custom_kernels:
    to_keep.add(active)

for flv, klist in by_flavor.items():
    sorted_k = sorted(klist, key=parse_ver, reverse=True)
    if flv == 'rc':
        to_keep.update(sorted_k[:1])
    else:
        to_keep.update(sorted_k[:2])

to_remove = [k for k in custom_kernels if k not in to_keep]
for k in to_remove:
    print(k)
" 2>/dev/null || true
}

# --- [ ROOT FILESYSTEM & DEVICE RESOLUTION ] ---
detect_root_filesystem_details() {
    local root_dev root_fs root_uuid root_flags

    # 1. Device resolution
    root_dev=$(findmnt -n -o SOURCE / 2>/dev/null || true)
    if [ -z "${root_dev}" ]; then
        root_dev=$(awk '$2 == "/" {print $1}' /proc/mounts 2>/dev/null | head -n1 || true)
    fi
    # Strip any Btrfs subvolume brackets like /dev/nvme1n1p7[/@] -> /dev/nvme1n1p7
    root_dev="${root_dev%%\[*}"
    root_dev=${root_dev:-"/dev/root"}

    # 2. Filesystem type resolution
    root_fs=$(findmnt -n -o FSTYPE / 2>/dev/null || true)
    if [ -z "${root_fs}" ]; then
        root_fs=$(awk '$2 == "/" {print $3}' /proc/mounts 2>/dev/null | head -n1 || true)
    fi
    root_fs=${root_fs:-"ext4"}

    # 3. UUID resolution (preferred for reliable boot args)
    root_uuid=$(findmnt -n -o UUID / 2>/dev/null || true)
    if [ -z "${root_uuid}" ] && command -v blkid >/dev/null 2>&1 && [ -b "${root_dev}" ]; then
        root_uuid=$(blkid -s UUID -o value "${root_dev}" 2>/dev/null || true)
    fi

    # 4. Subvolume / mount options resolution (for Btrfs)
    root_flags=""
    if [ "${root_fs}" = "btrfs" ]; then
        local mnt_opts
        mnt_opts=$(findmnt -n -o OPTIONS / 2>/dev/null || awk '$2 == "/" {print $4}' /proc/mounts 2>/dev/null | head -n1 || true)
        local subvol_val subvol_id
        subvol_val=$(echo "${mnt_opts}" | tr ',' '\n' | grep -E '^subvol=' | head -n1 | cut -d'=' -f2 || true)
        subvol_id=$(echo "${mnt_opts}" | tr ',' '\n' | grep -E '^subvolid=' | head -n1 | cut -d'=' -f2 || true)
        if [ -n "${subvol_val}" ] && [ "${subvol_val}" != "/" ] && [ "${subvol_id}" != "5" ]; then
            root_flags="rootflags=subvol=${subvol_val}"
        fi
    fi

    echo "${root_dev}|${root_fs}|${root_uuid}|${root_flags}"
}

# Resolve reliable bootloader root parameter with multi-tier fallbacks and zero-brick assertions
resolve_boot_root_cmd() {
    local root_dev="" root_fs="" root_uuid="" root_flags=""
    if type detect_root_filesystem_details >/dev/null 2>&1; then
        IFS='|' read -r root_dev root_fs root_uuid root_flags <<< "$(detect_root_filesystem_details)"
    fi

    if [ -z "${root_uuid}" ] && [ -z "${root_dev}" ]; then
        root_dev=$(findmnt -n -o SOURCE / 2>/dev/null || awk '$2 == "/" {print $1}' /proc/mounts 2>/dev/null | head -n1 || true)
        root_dev="${root_dev%%\[*}"
        root_uuid=$(findmnt -n -o UUID / 2>/dev/null || true)
        root_fs=$(findmnt -n -o FSTYPE / 2>/dev/null || echo "ext4")
    fi

    local root_cmd=""
    if [ -n "${root_uuid}" ]; then
        root_cmd="root=UUID=${root_uuid}"
    elif [ -n "${root_dev}" ] && [ "${root_dev}" != "/dev/root" ]; then
        root_cmd="root=${root_dev}"
    else
        local proc_root
        proc_root=$(grep -o -E 'root=[^ ]+' /proc/cmdline 2>/dev/null | head -n1 || true)
        if [ -n "${proc_root}" ] && [ "${proc_root}" != "root=" ]; then
            root_cmd="${proc_root}"
        else
            echo "ERROR"
            return 1
        fi
    fi

    echo "${root_cmd}|${root_flags}|${root_fs}|${root_dev}|${root_uuid}"
}

set_terminal_title() {
    local title="${1:-slacky-update v${CURRENT_VERSION:-0.10}}"
    if [ -t 1 ]; then
        printf "\033]0;%s\007\033]2;%s\007\033]30;%s\007" "${title}" "${title}" "${title}" 2>/dev/null || true
    fi
}

get_user_staging_dir() {
    local staging_dir="${HOME:-/tmp}/.cache/slacky-update/staging"
    # 6A-149 (L2 MINOR 5): no predictable /tmp fallback that another user could create first; never an empty path
    # (callers append "/dkms" etc.)
    if ! mkdir -p -m 0700 "${staging_dir}" 2>/dev/null; then
        local private_dir
        private_dir=$(mktemp -d "${TMPDIR:-/tmp}/slacky-staging.XXXXXX" 2>/dev/null) && staging_dir="${private_dir}"
    fi
    echo "${staging_dir}"
}

get_active_locale() {
    python3 -c "
import os, json, locale, pwd

cfg_paths = []
cfg_paths.append(os.path.expanduser('~/.config/slacky-update/config.json'))
sudo_u = os.environ.get('SUDO_USER')
if sudo_u:
    try:
        pw = pwd.getpwnam(sudo_u)
        cfg_paths.append(os.path.join(pw.pw_dir, '.config', 'slacky-update', 'config.json'))
    except Exception:
        pass

for cp in cfg_paths:
    if os.path.exists(cp):
        try:
            with open(cp, 'r', encoding='utf-8') as f:
                c = json.load(f)
                ov = c.get('language_override')
                if ov and ov != 'system':
                    print(ov)
                    exit(0)
        except Exception:
            pass

for ev in ('LC_ALL', 'LC_MESSAGES', 'LANG', 'LANGUAGE'):
    val = os.environ.get(ev)
    if val:
        tag = val.split('.')[0].split(':')[0].replace('_', '-').lower()
        if tag and tag not in ('c', 'posix'):
            print(tag)
            exit(0)

try:
    sys_lang = locale.getdefaultlocale()[0]
    if sys_lang:
        tag = sys_lang.replace('_', '-').lower()
        if tag and tag not in ('c', 'posix'):
            print(tag)
            exit(0)
except Exception:
    pass

print('en')
" 2>/dev/null || echo "en"
}

get_status_json_path() {
    python3 -c "
import os, json, pwd
candidates = []
xdg = os.environ.get('XDG_CACHE_HOME')
candidates.append(os.path.join(xdg, 'slacky-update', 'status.json') if xdg else os.path.expanduser('~/.cache/slacky-update/status.json'))

sudo_u = os.environ.get('SUDO_USER')
if sudo_u:
    try:
        pw = pwd.getpwnam(sudo_u)
        candidates.append(os.path.join(pw.pw_dir, '.cache', 'slacky-update', 'status.json'))
    except Exception:
        pass

candidates.append('/var/cache/slacky-update/status.json')

best_path = ''
best_ts = -1
for c in candidates:
    if os.path.exists(c):
        try:
            with open(c, 'r', encoding='utf-8') as f:
                d = json.load(f)
                ts = float(d.get('last_check_ts', os.path.getmtime(c)))
                if ts > best_ts:
                    best_ts = ts
                    best_path = c
        except Exception:
            pass
print(best_path if best_path else candidates[0])
" 2>/dev/null || echo "${HOME:-/tmp}/.cache/slacky-update/status.json"
}

get_status_key_count() {
    local key="$1"
    python3 -c "
import os, json, sys, pwd
candidates = []
xdg = os.environ.get('XDG_CACHE_HOME')
candidates.append(os.path.join(xdg, 'slacky-update', 'status.json') if xdg else os.path.expanduser('~/.cache/slacky-update/status.json'))

sudo_u = os.environ.get('SUDO_USER')
if sudo_u:
    try:
        pw = pwd.getpwnam(sudo_u)
        candidates.append(os.path.join(pw.pw_dir, '.cache', 'slacky-update', 'status.json'))
    except Exception:
        pass

candidates.append('/var/cache/slacky-update/status.json')

best_data = {}
best_ts = -1
for c in candidates:
    if os.path.exists(c):
        try:
            with open(c, 'r', encoding='utf-8') as f:
                d = json.load(f)
                ts = float(d.get('last_check_ts', os.path.getmtime(c)))
                if ts > best_ts:
                    best_ts = ts
                    best_data = d
        except Exception:
            pass
val = best_data.get(sys.argv[1], [])
if isinstance(val, list):
    print(len(val))
elif isinstance(val, bool):
    print(1 if val else 0)
else:
    print(1 if val else 0)
" "${key}" 2>/dev/null || echo "0"
}

# 6A-346 (1b): did the last check really look at everything? Prints "offline" (no server reached), "failed <names>"
# (parts that could not be checked) or nothing (all checked). The newest status.json wins; unreadable = nothing printed.
slacky_check_state() {
    local sf
    sf=$(get_status_json_path 2>/dev/null || true)
    [ "${SLACKY_SELFTEST:-0}" = "1" ] && [ -n "${SLACKY_STATUS_JSON:-}" ] && sf="${SLACKY_STATUS_JSON}"
    [ -n "${sf}" ] && [ -r "${sf}" ] || return 0
    python3 -I - "${sf}" <<'PYCS' 2>/dev/null || true
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    if not isinstance(d, dict):
        raise ValueError
except Exception:
    sys.exit(0)
if d.get("check_offline") is True:
    print("offline")
else:
    f = d.get("check_failed")
    f = [x for x in f if isinstance(x, str) and x] if isinstance(f, list) else []
    if f:
        print("failed " + " ".join(f))
PYCS
}

resolve_check_bin() {
    if [ -n "${CHECK_BIN:-}" ] && [ -x "${CHECK_BIN}" ]; then
        echo "${CHECK_BIN}"
        return 0
    fi
    for cand in "${SCRIPT_DIR:-}/../lib/check_backend.sh" \
                "${SCRIPT_DIR:-}/check_backend.sh" \
                "${APP_DIR:-}/check_backend.sh" \
                "/usr/share/slacky-update/lib/check_backend.sh" \
                "/usr/local/lib/slacky-update/check_backend.sh"; do
        if [ -x "${cand}" ]; then
            echo "${cand}"
            return 0
        fi
    done
    echo ""
}

run_preflight_check() {
    local force="${1:-0}"
    local chk_bin
    chk_bin=$(resolve_check_bin)

    local should_check=0
    if [ "${force}" -eq 1 ]; then
        should_check=1
    else
        local status_f
        status_f=$(get_status_json_path 2>/dev/null || echo "")
        if [ -z "${status_f}" ] || [ ! -f "${status_f}" ]; then
            should_check=1
        else
            local age
            age=$(python3 -c "
import os, json, time, sys
try:
    with open('${status_f}', 'r', encoding='utf-8') as f:
        d = json.load(f)
        ts = float(d.get('last_check_ts', os.path.getmtime('${status_f}')))
        print(int(time.time() - ts))
except Exception:
    print('999999')
" 2>/dev/null || echo "999999")
            if [ "${age}" -gt 900 ]; then
                should_check=1
            fi
        fi
    fi

    if [ "${should_check}" -eq 1 ] && [ -n "${chk_bin}" ]; then
        if [ "${force}" -eq 1 ] || [ -z "${status_f}" ] || [ ! -f "${status_f}" ]; then
            if [ -t 1 ]; then
                local cur_loc
                cur_loc=$(get_active_locale 2>/dev/null || echo "en")
                local spinner_frames=('-' '\' '|' '/')
                if [[ "${cur_loc}" =~ (en-ca|ca) ]]; then
                    spinner_frames=($'\033[2;31m*\033[0m' $'\033[1;31m*\033[0m' $'\033[1;37m*\033[0m' $'\033[1;31m*\033[0m')
                elif [[ "${cur_loc}" =~ radical ]]; then
                    spinner_frames=($'\033[2;33m*\033[0m' $'\033[1;33m*\033[0m' $'\033[1;37m*\033[0m' $'\033[1;33m+\033[0m')
                fi

                "${chk_bin}" >/dev/null 2>&1 &
                local chk_pid=$!
                local spin_idx=0
                while kill -0 "${chk_pid}" 2>/dev/null; do
                    local spin_char="${spinner_frames[spin_idx % ${#spinner_frames[@]}]}"
                    echo -ne "\r\033[K\033[1;36m$(_ PREFLIGHT_SCOUTING) ${spin_char}\033[0m"
                    spin_idx=$(( spin_idx + 1 ))
                    sleep 0.25
                done
                wait "${chk_pid}" 2>/dev/null || true
                echo -e "\r\033[K\033[1;32m$(_ PREFLIGHT_DONE)\033[0m"
            else
                echo "$(_ PREFLIGHT_SCOUTING)"
                "${chk_bin}" >/dev/null 2>&1 || true
            fi
        else
            nohup "${chk_bin}" </dev/null >/dev/null 2>&1 &
            # 6A-150: remembered so a full update can wait for it before it records what it updated (otherwise this
            # check, started before the update, finished after it and wrote the old list back: the badge stayed)
            SLACKY_BG_CHECK_PID=$!
            disown 2>/dev/null || true
        fi
    fi
}

# 6A-150: let a status check that this run started in the background finish before the run records its results, so
# the check's (older) view never lands on top of them. A check that is still running after 60 s is stopped.
ss_wait_background_check() {
    local pid="${SLACKY_BG_CHECK_PID:-}" waited=0
    [ -n "${pid}" ] || return 0
    while kill -0 "${pid}" 2>/dev/null && [ "${waited}" -lt 120 ]; do
        sleep 0.5
        waited=$(( waited + 1 ))
    done
    if kill -0 "${pid}" 2>/dev/null; then
        pkill -TERM -P "${pid}" 2>/dev/null || true
        kill -TERM "${pid}" 2>/dev/null || true
    fi
    SLACKY_BG_CHECK_PID=""
    return 0
}

reconcile_post_update_status() {
    local slack_done="${1:-0}"
    local cachy_done="${2:-0}"
    local flatpak_done="${3:-0}"
    local sbo_done="${4:-0}"
    local gaming_done="${5:-0}"
    local gnomes_done="${6:-0}"
    local nvidia_done="${7:-0}"
    local rr_done="${8:-0}"

    python3 - "${slack_done}" "${cachy_done}" "${flatpak_done}" "${sbo_done}" "${gaming_done}" "${gnomes_done}" "${nvidia_done}" "${rr_done}" << 'PYRECON'
import sys, os, json, time, pwd

slack_done, cachy_done, flatpak_done, sbo_done, gaming_done, gnomes_done, nvidia_done = sys.argv[1:8]
rr_done = sys.argv[8] if len(sys.argv) > 8 else "0"

candidates = []
xdg = os.environ.get("XDG_CACHE_HOME")
candidates.append(os.path.join(xdg, "slacky-update", "status.json") if xdg else os.path.expanduser("~/.cache/slacky-update/status.json"))

sudo_u = os.environ.get("SUDO_USER")
sudo_path = None
sudo_uid = None
sudo_gid = None
if sudo_u:
    try:
        pw = pwd.getpwnam(sudo_u)
        sudo_path = os.path.join(pw.pw_dir, ".cache", "slacky-update", "status.json")
        sudo_uid = pw.pw_uid
        sudo_gid = pw.pw_gid
        if sudo_path not in candidates:
            candidates.append(sudo_path)
    except Exception:
        pass

candidates.append("/var/cache/slacky-update/status.json")

base_data = None
best_ts = -1
for c in candidates:
    if os.path.exists(c):
        try:
            with open(c, "r", encoding="utf-8") as f:
                d = json.load(f)
                ts = float(d.get("last_check_ts", os.path.getmtime(c)))
                if ts > best_ts:
                    best_ts = ts
                    base_data = d
        except Exception:
            pass

if not base_data:
    base_data = {
        "slackware_updates": [],
        "slackpkgplus_updates": [],
        "slackware_new_packages": [],
        "flatpak_updates": [],
        "sbo_updates": [],
        "cachyos_kernel_updates": [],
        "cachyos_gaming_updates": [],
        "cachyos_gaming_updates_raw": [],
        "gnomes_updates": [],
        "gnomes_updates_raw": [],
        "nvidia_driver_updates": [],
        "reboot_required": False,
        "nvidia_gl_mismatch": False,
        "nvidia_driver_version": "",
        "secure_boot": {"state": "unknown", "warnings": []},
        "last_check": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "last_check_ts": int(time.time())
    }

# Clear updated sections based on completed steps
if slack_done == "1":
    # 6A-345 (1e): in hold mode (no safety snapshot) the stock kernel packages were NOT installed; they stay listed
    def _held_kernel(it):
        if os.environ.get("SLACKY_HOLD_STOCK_KERNEL") != "1" or not isinstance(it, str):
            return False
        return os.path.basename(it.strip()).startswith(("kernel-generic", "kernel-huge", "kernel-modules", "kernel-source"))
    for _k in ("slackware_updates", "slackpkgplus_updates", "slackware_new_packages"):
        _old = base_data.get(_k)
        base_data[_k] = [x for x in _old if _held_kernel(x)] if isinstance(_old, list) else []
if cachy_done == "1":
    base_data["cachyos_kernel_updates"] = []
if flatpak_done == "1":
    base_data["flatpak_updates"] = []
    base_data["nvidia_gl_mismatch"] = False
if sbo_done == "1":
    base_data["sbo_updates"] = []
if gaming_done == "1":
    base_data["cachyos_gaming_updates"] = []
    base_data["cachyos_gaming_updates_raw"] = []
if gnomes_done == "1":
    base_data["gnomes_updates"] = []
    base_data["gnomes_updates_raw"] = []
if nvidia_done == "1":
    base_data["nvidia_driver_updates"] = []
    base_data["nvidia_gl_mismatch"] = False
if rr_done == "1" and isinstance(base_data.get("runtime_refresh"), dict):
    # 7N: the runtime was refreshed in this run (the next check recomputes the real answer)
    base_data["runtime_refresh"].update(state="nominal", age_days=0, newer=0, suspects=[])

base_data["last_check_ts"] = int(time.time())
base_data["last_check"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

def _status_atomic(p, text):
    d = os.path.dirname(p)
    os.makedirs(d, exist_ok=True)
    if os.path.islink(d):
        return
    import tempfile
    fd, tmp = tempfile.mkstemp(prefix=".status.", dir=d)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, 0o644)
        os.replace(tmp, p)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise

def write_status_safely(path, data_obj, uid=None, gid=None):
    """6A-48: never follow a symlink as root. The system cache is written atomically (0644, was 0666); a user's cache
    is written by a child that first drops to that user's uid/gid, so a planted symlink gains nothing."""
    text = json.dumps(data_obj, indent=2)
    try:
        if os.geteuid() == 0 and uid is not None and gid is not None:
            pid = os.fork()
            if pid == 0:
                try:
                    os.setgroups([])
                    os.setgid(gid)
                    os.setuid(uid)
                    _status_atomic(path, text)
                    os._exit(0)
                except BaseException:
                    os._exit(1)
            _, st = os.waitpid(pid, 0)
            return st == 0
        _status_atomic(path, text)
        return True
    except Exception:
        return False

for c in set(candidates):
    u = sudo_uid if (sudo_path and c == sudo_path) else None
    g = sudo_gid if (sudo_path and c == sudo_path) else None
    write_status_safely(c, base_data, u, g)
PYRECON

    for sp in "/var/cache/slacky-update/status.json" "${HOME:-/tmp}/.cache/slacky-update/status.json"; do
        [ -f "${sp}" ] && touch "${sp}" 2>/dev/null || true
    done
}

resolve_cachyos_keyring() {
    local candidates=(
        "/usr/share/slacky-update/keys/trusted-keyrings.gpg"
        "/usr/local/lib/slacky-update/keys/trusted-keyrings.gpg"
        "${SCRIPT_DIR:-.}/../keys/trusted-keyrings.gpg"
        "${APP_DIR:-.}/../keys/trusted-keyrings.gpg"
        "$(dirname "$(readlink -f "$0" 2>/dev/null || echo ".")")/../keys/trusted-keyrings.gpg"
        "/usr/share/slacky-update/keys/cachyos.gpg"
        "/usr/local/lib/slacky-update/keys/cachyos.gpg"
        "${SCRIPT_DIR:-.}/../keys/cachyos.gpg"
        "${APP_DIR:-.}/../keys/cachyos.gpg"
        "$(dirname "$(readlink -f "$0" 2>/dev/null || echo ".")")/../keys/cachyos.gpg"
    )
    for c in "${candidates[@]}"; do
        if [ -f "$c" ] && [ -s "$c" ]; then
            echo "$c"
            return 0
        fi
    done
    echo ""
}

# 6A-276: which key family signs packages from this download address. Decided by the host only (never by a query string
# or path): Arch (archlinux.org, pkgbuild.com), CachyOS (cachyos.org), Chaotic (chaotic.cx). Empty = not a signing repo.
slacky_sig_family() {
    local url="$1" host
    host="${url#*://}"; host="${host%%/*}"; host="${host%%:*}"; host="${host,,}"
    case "${host}" in
        archlinux.org|*.archlinux.org|pkgbuild.com|*.pkgbuild.com) echo "archlinux" ;;
        cachyos.org|*.cachyos.org) echo "cachyos" ;;
        chaotic.cx|*.chaotic.cx) echo "chaotic" ;;
        *) echo "" ;;
    esac
}

# 6A-277: true for a package file from a repo that signs its packages. Such a package without a .sig is refused;
# vendor downloads (other hosts, .deb, AppImage, zip) keep their own checksum or pin rules.
slacky_signed_repo_url() {
    local url="$1"
    [ -n "$(slacky_sig_family "${url}")" ] && [[ "${url%%\?*}" =~ \.pkg\.tar\.(zst|xz)$ ]]
}

slacky_find_trust_helper() {
    local cand
    for cand in "$(dirname "${BASH_SOURCE[0]}")/gnomes_trust.py" "${SCRIPT_DIR:-.}/../lib/gnomes_trust.py" \
                "${APP_DIR:-.}/gnomes_trust.py" "/usr/share/slacky-update/lib/gnomes_trust.py" \
                "/usr/local/lib/slacky-update/gnomes_trust.py"; do
        if [ -f "${cand}" ]; then
            printf '%s\n' "${cand}"
            return 0
        fi
    done
    return 1
}

# 6A-276: one check of a package against the refreshed key store (gnomes_trust.py: gpgv status parsing, revoked lists,
# keys bound to the family). Prints "<status>|<detail>" on stdout; returns 0 only for status good.
_slacky_trust_check() {
    local payload="$1" sig="$2" repo="$3" helper="$4" out status detail
    local keys_root="/opt/underpants/keys"
    [ "${SLACKY_SELFTEST:-0}" = "1" ] && [ -n "${SLACKY_KEYS_ROOT:-}" ] && keys_root="${SLACKY_KEYS_ROOT}"
    out=$(python3 -I "${helper}" verify "${payload}" "${sig}" "${repo}" "${keys_root}" 2>/dev/null | head -n 1) || true
    status=$(printf '%s' "${out}" | sed -n 's/.*"status": "\([a-z]*\)".*/\1/p')
    detail=$(printf '%s' "${out}" | sed -n 's/.*"detail": "\([^"]*\)".*/\1/p')
    printf '%s|%s\n' "${status:-error}" "${detail}"
    [ "${status}" = "good" ]
}

# Usage: verify_cachyos_gpg_signature PAYLOAD SIG SOURCE_URL [SHA256_FROM_REPO_DB]
# SOURCE_URL decides the key family (Arch, CachyOS, Chaotic); only that family's keys count. Revoked and expired keys
# are refused. An unknown or expired key first triggers one signed key refresh, then one retry.
verify_cachyos_gpg_signature() {
    local payload="$1" sig="$2" source="${3:-}" want_sha="${4:-}"
    local name
    name=$(basename "${payload}")

    [ -f "${payload}" ] || return 1
    if [ ! -s "${sig}" ]; then
        log_error "${name} came without its signature file, so it was not used."
        return 1
    fi

    local family repo
    family=$(slacky_sig_family "${source}")
    case "${family}" in
        archlinux) repo="extra" ;;
        cachyos) repo="cachyos" ;;
        chaotic) repo="chaotic" ;;
        *)
            log_error "${name} does not come from a package source whose signing keys are known, so it was not used."
            return 1
            ;;
    esac

    if [ -n "${want_sha}" ]; then
        local have_sha
        have_sha=$(sha256sum "${payload}" 2>/dev/null | cut -d' ' -f1)
        if [ "${have_sha,,}" != "${want_sha,,}" ]; then
            log_error "${name} does not match the checksum listed by its repository, so it was not used."
            return 1
        fi
    fi

    local helper
    if ! helper=$(slacky_find_trust_helper) || ! command -v python3 >/dev/null 2>&1 || ! command -v gpgv >/dev/null 2>&1; then
        log_error "The signature tools are missing (python3, gpgv or gnomes_trust.py), so ${name} could not be checked and was not used."
        return 1
    fi

    if [ ! -d "/opt/underpants/keys/${family}" ] && [ "${SLACKY_SELFTEST:-0}" != "1" ] && [ -z "${_SLACKY_SIG_NOSTORE_NOTE:-}" ]; then
        _SLACKY_SIG_NOSTORE_NOTE=1
        log_info "No refreshed key store yet; using the keys shipped with the program until the next full update."
    fi

    local res status detail
    res=$(_slacky_trust_check "${payload}" "${sig}" "${repo}" "${helper}") && status=good || true
    status="${res%%|*}"; detail="${res#*|}"

    if [ "${status}" != "good" ]; then
        # unknown or expired signing key: the key may simply be newer than our store; refresh once per run, then retry once
        if { [ "${status}" = "nokey" ] && [[ "${detail}" != *"not one of the keys"* ]]; } || [ "${status}" = "expired" ]; then
            if [ -z "${_SLACKY_KEYS_REFRESH_TRIED:-}" ]; then
                _SLACKY_KEYS_REFRESH_TRIED=1
                if command -v slacky_keys_first >/dev/null 2>&1; then
                    log_info "The signing key of ${name} is not known yet; fetching the newest security keys."
                    # 6A-351 (4a): forced, because the daily limit already used up the refresh at the start of the run
                    slacky_keys_first force >/dev/null 2>&1 || true
                fi
            fi
            if [ -n "${_SLACKY_KEYS_REFRESH_TRIED:-}" ]; then
                res=$(_slacky_trust_check "${payload}" "${sig}" "${repo}" "${helper}") && status=good || true
                status="${res%%|*}"; detail="${res#*|}"
            fi
        fi
    fi

    if [ "${status}" = "good" ]; then
        { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] GPG cryptographic signature verified for ${name} (${family})" >> "${LOG_FILE}"; } 2>/dev/null || true
        return 0
    fi

    # 6A-351 (4b/4c): the sentence follows the status, never a word inside the detail text; no sentence promises a fix
    # that a key refresh cannot deliver (a refresh was already tried above for an unknown or expired key)
    case "${status}" in
        nokey)
            if [[ "${detail}" == *"not one of the keys"* ]]; then
                log_error "${name} was signed with a key that does not belong to its package source, so it was not used."
            else
                log_error "The signing key of ${name} is not known, even after the newest security keys were fetched, so it was not used."
            fi ;;
        expired)
            log_error "The signing key of ${name} has run out, even after the newest security keys were fetched, so it was not used." ;;
        bad)
            if [[ "${detail}" == *"revoked"* ]]; then
                log_error "The signing key of ${name} has been withdrawn by its publisher, so the package was not used."
            elif [[ "${detail}" == *"signature itself has expired"* ]]; then
                log_error "The signature of ${name} is damaged or has run out, so it was not used; try the download again later."
            else
                log_error "${name} does not match its signature, so it was not used; the download may be damaged, try again later."
            fi ;;
        unsigned)
            log_error "${name} came without a usable signature, so it was not used." ;;
        *)
            log_error "The signature of ${name} could not be checked (${detail:-unknown reason}), so it was not used." ;;
    esac
    return 1
}

resolve_microsoft_uefi_ca_cert() {
    local candidates=(
        "/usr/share/slacky-update/certs/microsoft-uefi-ca-2011.crt"
        "/usr/local/lib/slacky-update/certs/microsoft-uefi-ca-2011.crt"
        "${SCRIPT_DIR:-.}/../certs/microsoft-uefi-ca-2011.crt"
        "${APP_DIR:-.}/../certs/microsoft-uefi-ca-2011.crt"
        "$(dirname "$(readlink -f "$0" 2>/dev/null || echo ".")")/../certs/microsoft-uefi-ca-2011.crt"
    )
    for c in "${candidates[@]}"; do
        if [ -f "$c" ] && [ -s "$c" ]; then
            echo "$c"
            return 0
        fi
    done
    echo ""
}

# 6A-320 (V2): the Microsoft UEFI CA 2011 certificate expired on 2026-06-27 (sbverify ignores the expiry, so old signatures
# still verify), and newer shim builds are signed by the 2023 CA. Either CA is accepted. The 2023 certificate comes from
# Microsoft (https://www.microsoft.com/pkiops/certs/microsoft%20uefi%20ca%202023.crt) and is pinned by its SHA-256
# fingerprint; a file with another fingerprint is never used.
MS_UEFI_CA_2023_SHA256="F6:12:4E:34:12:5B:EE:3F:E6:D7:9A:57:4E:AA:7B:91:C0:E7:BD:9D:92:9C:1A:32:11:78:EF:D6:11:DA:D9:01"

# Prints the path of every usable Microsoft UEFI CA certificate (2011 first, then 2023), one per line.
resolve_microsoft_uefi_ca_certs() {
    local name dir c fp
    for name in microsoft-uefi-ca-2011.crt microsoft-uefi-ca-2023.crt; do
        for dir in "/usr/share/slacky-update/certs" "/usr/local/lib/slacky-update/certs" \
                   "${SCRIPT_DIR:-.}/../certs" "${APP_DIR:-.}/../certs" \
                   "$(dirname "$(readlink -f "$0" 2>/dev/null || echo ".")")/../certs"; do
            c="${dir}/${name}"
            [ -f "$c" ] && [ -s "$c" ] || continue
            if [ "${name}" = "microsoft-uefi-ca-2023.crt" ]; then
                command -v openssl >/dev/null 2>&1 || continue
                fp=$(env -u LD_LIBRARY_PATH openssl x509 -in "$c" -noout -fingerprint -sha256 2>/dev/null | sed 's/^.*=//') || fp=""
                [ "${fp}" = "${MS_UEFI_CA_2023_SHA256}" ] || continue
            fi
            echo "$c"
            break
        done
    done
}

verify_microsoft_uefi_authenticode() {
    local efi_file="$1"
    [ -f "${efi_file}" ] || return 1

    local sbverify_bin
    sbverify_bin=$(command -v sbverify 2>/dev/null || echo "/usr/bin/sbverify")
    if [ ! -x "${sbverify_bin}" ]; then
        log_error "Security Error: sbverify utility not found. Cannot verify Authenticode signature on $(basename "${efi_file}")."
        return 1
    fi

    local ca_cert ca_list
    ca_list=$(resolve_microsoft_uefi_ca_certs)
    if [ -z "${ca_list}" ]; then
        log_error "Security Error: Microsoft UEFI CA certificate (microsoft-uefi-ca-2011.crt or -2023.crt) not located. Aborting Authenticode validation."
        return 1
    fi

    while IFS= read -r ca_cert; do
        [ -n "${ca_cert}" ] || continue
        if "${sbverify_bin}" --cert "${ca_cert}" "${efi_file}" >/dev/null 2>&1; then
            { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] Microsoft 3rd Party UEFI CA signature verified for $(basename "${efi_file}") ($(basename "${ca_cert}"))" >> "${LOG_FILE}"; } 2>/dev/null || true
            return 0
        fi
    done <<< "${ca_list}"
    log_error "Microsoft UEFI CA Authenticode verification FAILED for $(basename "${efi_file}")!"
    return 1
}

log_info() {
    local msg="$1"
    echo -e "  ${CYAN}•${RESET} ${msg}"
    { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] ${msg}" >> "${LOG_FILE}"; } 2>/dev/null || true
}

log_success() {
    local msg="$1"
    echo -e "${GREEN}OK${RESET} ${msg}"
    { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] ${msg}" >> "${LOG_FILE}"; } 2>/dev/null || true
}

# 6A-345: localised one-line message with an English fallback (the key may be missing in an older locale or without the
# translation helper). Usage: slacky_msg KEY "English text" [value for {0}].
slacky_msg() {
    local key="$1" def="$2" arg="${3:-}" v=""
    if declare -F _ >/dev/null 2>&1; then
        v=$(_ "${key}" 2>/dev/null || true)
    fi
    if [ -z "${v}" ] || [ "${v}" = "${key}" ]; then
        v="${def}"
    fi
    printf '%s' "${v//\{0\}/${arg}}"
}

log_warn() {
    local msg="$1"
    echo -e "${YELLOW}WARN${RESET} ${msg}"
    { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] ${msg}" >> "${LOG_FILE}"; } 2>/dev/null || true
}

log_error() {
    local msg="$1"
    echo -e "${RED}FAIL${RESET} ${msg}"
    { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] ${msg}" >> "${LOG_FILE}"; } 2>/dev/null || true
}

# --- [ ATOMIC TRANSACTION & INPUT PROTECTION ] ---
# Secure prompt input inside update routines:
# Disallows ESC keypresses so accidental ESC cannot skip, cancel, or corrupt updates.
read_update_prompt() {
    local prompt_msg="$1"
    local default_val="${2:-Y}"
    local var_name="$3"
    local user_input=""

    while true; do
        # SS-3 test 4g: a stop request (Ctrl-C/TERM) interrupts read; it must mean "no", never the default "yes"
        read -r -p "${prompt_msg}" user_input || { [ "${SS_ABORT:-0}" -gt 0 ] && user_input="n" || user_input="${default_val}"; }
        user_input="${user_input:-$default_val}"
        if [[ "${user_input}" =~ $'\033' ]] || [[ "${user_input}" =~ $'\x1b' ]] || [[ "${user_input}" == *$'\e'* ]]; then
            echo -e "\n${YELLOW}[!] ESC is disabled during update transactions. Please enter [Y/n] or your choice:${RESET}" >&2
            continue
        fi
        break
    done
    [ "${SS_ABORT:-0}" -gt 0 ] && user_input="n"
    printf -v "${var_name}" "%s" "${user_input}"
}

# 6A-8d: one lock for everything that writes boot files (kernels, initramfs, limine.conf, Limine EFI), shared with the
# hourly snapper/Limine cron job, so a cron reseal can never interleave with an update (conf and enrolled hash must match).
# Held until this process exits; SLACKY_BOOT_LOCK_HELD stops nested calls (and the cron job's own child) from waiting
# on themselves.
SLACKY_BOOT_LOCK="/run/lock/boot-partition.lock"
acquire_boot_lock() {
    [ "${SLACKY_BOOT_LOCK_HELD:-0}" = "1" ] && return 0
    command -v flock >/dev/null 2>&1 || return 0
    if [ ! -e "${SLACKY_BOOT_LOCK}" ]; then
        if [ "$(id -u)" -eq 0 ]; then
            install -m 0644 -o root -g root /dev/null "${SLACKY_BOOT_LOCK}" 2>/dev/null || true
        else
            sudo install -m 0644 -o root -g root /dev/null "${SLACKY_BOOT_LOCK}" 2>/dev/null || true
        fi
    fi
    # 6A-56: brace group so only the open is silenced; a bare "exec 9<f 2>/dev/null" made 2>/dev/null permanent for
    # the whole shell (read -p prompts and every error message vanished after the lock was taken)
    { exec 9<"${SLACKY_BOOT_LOCK}"; } 2>/dev/null || { log_error "Cannot open the boot lock ${SLACKY_BOOT_LOCK}."; return 1; }
    if ! flock -n 9; then
        log_info "Waiting for another boot update to finish..."
        if ! flock -w 300 9; then
            log_error "Another boot update is still running. Try again in a few minutes."
            exec 9<&-
            return 1
        fi
    fi
    export SLACKY_BOOT_LOCK_HELD=1
    # 6A-102: remember that this process opened fd 9, so release_boot_lock may close it (never a lock held by a parent)
    SS_BOOT_LOCK_OURS=1
}

# 6A-102: the full update holds the boot lock only for its boot-chain step and releases it before the post snapshot
release_boot_lock() {
    [ "${SS_BOOT_LOCK_OURS:-0}" = "1" ] || return 0
    exec 9<&-
    SS_BOOT_LOCK_OURS=0
    export SLACKY_BOOT_LOCK_HELD=0
}

# 6A-8c: "boot files changed, Limine not resealed yet". Set before kernels or limine.conf change, cleared after the
# conf + EFI pair was swapped in. The hourly cron job reseals while it exists, so an update killed by a closed terminal,
# SIGKILL or power loss is repaired without the user noticing.
SLACKY_BOOT_PENDING="/var/cache/slacky-update/boot-reseal-pending"
# 6A-152: the shared marker of the SpiderSense spec v0.3 (written by slacky-update-rs); served and cleared here too
SLACKY_BOOT_PENDING_SHARED="/var/lib/slacky-boot/reseal-pending"
mark_boot_reseal_pending() {
    if [ "$(id -u)" -eq 0 ]; then
        touch "${SLACKY_BOOT_PENDING}" 2>/dev/null || true
    else
        sudo touch "${SLACKY_BOOT_PENDING}" 2>/dev/null || true
    fi
}
clear_boot_reseal_pending() {
    if [ "$(id -u)" -eq 0 ]; then
        rm -f "${SLACKY_BOOT_PENDING}" "${SLACKY_BOOT_PENDING_SHARED}" 2>/dev/null || true
    else
        sudo rm -f "${SLACKY_BOOT_PENDING}" "${SLACKY_BOOT_PENDING_SHARED}" 2>/dev/null || true
    fi
}

# 6A-97/6A-98/6A-99 (SpiderSense SS-3, order-book gates): while DEFER_BOOT_SYNC=1 the code in the middle of an update
# records what the boot chain must do instead of writing boot files itself. The owner of the deferral (the full update's
# boot-chain step, or update_cachyos_kernels run on its own) carries the orders out once, in a fixed order. The orders
# live in this shell only; each one also sets the reseal marker, so if the run dies the hourly job repairs the chain.
SS_INITRD_ORDERS=()
SS_MENU_ORDER=0
SS_BOOT_DIRTY=0
ss_mark_if_limine() {
    SS_BOOT_DIRTY=1
    # 6A-147 (verifier MAJOR-1): with /boot unmounted the Limine EFI file is invisible; a configured Limine still gets
    # the marker so the hourly check repairs it once /boot is back (the cron gate re-checks before it serves it)
    if ! ss_boot_ready 2>/dev/null && { [ -f /etc/default/limine ] || [ -f /boot/limine.conf ]; }; then
        mark_boot_reseal_pending
        return 0
    fi
    command -v is_limine_installed >/dev/null 2>&1 || return 0
    [ "$(is_limine_installed 2>/dev/null || echo false)" = "true" ] || return 0
    mark_boot_reseal_pending
}
ss_order_initrd() {
    local k="${1:-}"
    [ -n "${k}" ] || return 0
    ss_initrd_ordered "${k}" || SS_INITRD_ORDERS+=("${k}")
    ss_mark_if_limine
}
ss_initrd_ordered() {
    case " ${SS_INITRD_ORDERS[*]:-} " in *" ${1:-} "*) return 0 ;; esac
    return 1
}
ss_order_menu() {
    SS_MENU_ORDER=1
    ss_mark_if_limine
}

# 6A-98: true when the live Limine menu still lists kernel <kver> (exact name, also generic-<kver> / huge-<kver>)
ss_live_menu_lists_kernel() {
    local k="${1:-}" esp conf n
    [ -n "${k}" ] || return 1
    esp=$(detect_limine_esp_path 2>/dev/null || echo "/boot")
    for conf in "${esp}/limine.conf" "/boot/limine.conf"; do
        sudo test -f "${conf}" 2>/dev/null || continue
        while IFS= read -r n; do
            n="${n#vmlinuz-}"
            if [ "${n}" = "${k}" ] || [ "${n}" = "generic-${k}" ] || [ "${n}" = "huge-${k}" ]; then
                return 0
            fi
        done < <(sudo grep -oE 'vmlinuz-[^#[:space:]]+' "${conf}" 2>/dev/null || true)
    done
    return 1
}

# 6A-98: every kernel the retention rules will remove (CachyOS beyond retention + old Slackware stock kernels), one per line
ss_purge_set() {
    if command -v get_obsolete_cachyos_kernels >/dev/null 2>&1; then
        get_obsolete_cachyos_kernels 2>/dev/null || true
    fi
    if command -v get_obsolete_slackware_kernels >/dev/null 2>&1; then
        get_obsolete_slackware_kernels 2>/dev/null | cut -d'|' -f1 || true
    fi
}

# 6A-102 (SpiderSense SS-3): stop requests during a full update. Ctrl-C keeps being ignored by the update and by every
# package tool it runs (a package must never be cut in half); a tiny relay turns it into a stop request for this shell
# only. TERM is a stop request too. Before the boot-chain step: the remaining suites are skipped and, if boot files
# changed, the chain still runs once so the startup menu matches. During the chain: the request waits until it is done.
# A second request before the chain: stop now; the startup files were not touched, the marker tells the hourly job
# to finish them.
SS_ABORT=0
SS_BOOT_COMMIT=0
SS_ABORT_RELAY=""
ss_abort_signal() {
    SS_ABORT=$(( ${SS_ABORT:-0} + 1 ))
    if [ "${SS_BOOT_COMMIT:-0}" = "1" ]; then
        [ "${SS_ABORT}" -eq 1 ] && log_warn "Stopping as soon as the startup files are finished."
        return 0
    fi
    if [ "${SS_ABORT}" -eq 1 ]; then
        log_warn "Stopping after the current step. Press Ctrl-C again to stop at once."
        return 0
    fi
    ss_disarm_abort_handler
    if [ -f "${SLACKY_BOOT_PENDING}" ]; then
        echo -e "${RED}${BOLD}The update was stopped. Do not restart yet; your computer finishes the startup files within the hour, or run: sudo slacky-update --sync-boot${RESET}"
        exit 30
    fi
    if [ "${SS_BOOT_DIRTY:-0}" = "1" ]; then
        echo -e "${RED}${BOLD}The update was stopped. Do not restart yet; first run: sudo slacky-update --sync-boot${RESET}"
        exit 30
    fi
    echo -e "${YELLOW}The update was stopped. The startup files were not changed, so restarting is safe.${RESET}"
    exit 130
}
ss_arm_abort_handler() {
    SS_ABORT=0
    trap 'ss_abort_signal' TERM
    # the relay closes the lock descriptors (fd 8 run lock, fd 9 boot lock) so it never keeps a lock alive
    if [ -t 0 ] && env --default-signal=INT true >/dev/null 2>&1; then
        env --default-signal=INT bash -c 'trap "kill -TERM $1 2>/dev/null" INT; while kill -0 "$1" 2>/dev/null; do sleep 1; done' \
            ss-abort-relay "$$" </dev/null >/dev/null 2>&1 8<&- 9<&- &
        SS_ABORT_RELAY=$!
    fi
}
ss_disarm_abort_handler() {
    trap - TERM
    if [ -n "${SS_ABORT_RELAY}" ]; then
        kill "${SS_ABORT_RELAY}" 2>/dev/null || true
        SS_ABORT_RELAY=""
    fi
}
ss_continue() {
    [ "${SS_ABORT:-0}" -eq 0 ]
}

# 6A-47 (SpiderSense phase 1, spec 4.5): run lock. flock on a root-owned file in /run/lock (0755 root, so no other user
# can create or pre-claim it); released automatically when the process exits, so a crash or power loss never leaves a
# stale lock. Replaces /tmp/slacky-update-running.lock, which any local user could create to silence the cron reseal.
SLACKY_RUN_LOCK="/run/lock/slacky-update.lock"
acquire_run_lock() {
    [ "${SLACKY_RUN_LOCK_HELD:-0}" = "1" ] && return 0
    command -v flock >/dev/null 2>&1 || return 0
    if [ ! -e "${SLACKY_RUN_LOCK}" ]; then
        if [ "$(id -u)" -eq 0 ]; then
            install -m 0644 -o root -g root /dev/null "${SLACKY_RUN_LOCK}" 2>/dev/null || true
        else
            sudo install -m 0644 -o root -g root /dev/null "${SLACKY_RUN_LOCK}" 2>/dev/null || true
        fi
    fi
    # 6A-90: another package tool (or a hand-run slackpkg) changing the system right now
    local foreign
    foreign=$(pgrep -x -l 'slackpkg|installpkg|upgradepkg|removepkg|sbopkg|sboinstall|sboupgrade' 2>/dev/null | awk '{print $2}' | sort -u | head -n 3 | tr '\n' ' ')
    if [ -n "${foreign}" ]; then
        log_warn "Another package tool (${foreign% }) is changing this system right now. Wait until it has finished, then try again."
        return 1
    fi
    { exec 8<"${SLACKY_RUN_LOCK}"; } 2>/dev/null || return 0
    if ! flock -n 8; then
        log_warn "Another slacky-update is already updating this system. Wait until it has finished, then try again."
        exec 8<&-
        return 1
    fi
    export SLACKY_RUN_LOCK_HELD=1
}

# True (0) when ANOTHER process holds the run lock (cron, kernel hook and the status check stay out of its way).
slacky_update_is_running() {
    [ "${SLACKY_RUN_LOCK_HELD:-0}" = "1" ] && return 1
    [ -e "${SLACKY_RUN_LOCK}" ] || return 1
    command -v flock >/dev/null 2>&1 || return 1
    flock -n "${SLACKY_RUN_LOCK}" true 2>/dev/null && return 1
    return 0
}

# 6A-88 (SS-1): /boot must be mounted read-write when /etc/fstab declares a separate /boot; otherwise kernels, initramfs
# images and the boot menu would be written into the root filesystem behind the real boot partition. No /boot line in
# fstab = /boot lives on the root filesystem and is fine.
ss_boot_ready() {
    local want
    want=$(awk '!/^[[:space:]]*#/ && $2=="/boot" {print $3; exit}' /etc/fstab 2>/dev/null)
    [ -n "${want}" ] || return 0
    local got opts
    got=$(findmnt -n -o FSTYPE --mountpoint /boot 2>/dev/null | head -n1)
    opts=$(findmnt -n -o OPTIONS --mountpoint /boot 2>/dev/null | head -n1)
    [ -n "${got}" ] || return 1
    case ",${opts}," in *,rw,*) ;; *) return 1 ;; esac
    [ "${want}" = "auto" ] || [ "${got}" = "${want}" ] || return 1
    return 0
}

# 6A-89 (SS-1): keep the sudo ticket alive for the whole run (a long update must not stop for the password again)
SLACKY_SUDO_KEEPALIVE_PID=""
start_sudo_keepalive() {
    [ "$(id -u)" -eq 0 ] && return 0
    [ -n "${SLACKY_SUDO_KEEPALIVE_PID}" ] && return 0
    ( trap '' HUP; while sleep 50; do sudo -n -v 2>/dev/null || exit 0; kill -0 "$$" 2>/dev/null || exit 0; done ) &
    SLACKY_SUDO_KEEPALIVE_PID=$!
}
stop_sudo_keepalive() {
    [ -n "${SLACKY_SUDO_KEEPALIVE_PID}" ] && kill "${SLACKY_SUDO_KEEPALIVE_PID}" 2>/dev/null || true
    SLACKY_SUDO_KEEPALIVE_PID=""
}

# 6A-93 (SS-1): interrupted-transaction journal. One root-owned file names the stage that is running; a stage that is
# still "started" at the next run means the last update was cut off (power loss, killed). Detection is read-only.
SLACKY_TX_STATE="/var/lib/slacky-update/tx-state"
ss_tx_mark() {
    local line="$1 $(date +%s)"
    if [ "$(id -u)" -eq 0 ]; then
        mkdir -p -m 0755 "${SLACKY_TX_STATE%/*}" && printf '%s\n' "${line}" > "${SLACKY_TX_STATE}"
    else
        sudo mkdir -p -m 0755 "${SLACKY_TX_STATE%/*}" && printf '%s\n' "${line}" | sudo tee "${SLACKY_TX_STATE}" >/dev/null
    fi
    sync 2>/dev/null || true
}
ss_tx_check_interrupted() {
    [ -f "${SLACKY_TX_STATE}" ] || return 0
    local state stage
    state=$(head -n1 "${SLACKY_TX_STATE}" 2>/dev/null)
    stage=${state%% *}
    case "${stage}" in
        done|"") return 0 ;;
    esac
    log_warn "The last update was interrupted (${stage#started-}). It is finished now; packages that were cut off are checked."
    # an upgradepkg cut off between installing the new and removing the old version leaves two entries of one package
    local dups
    # 6A-147 (L1 M2): also upgradepkg's own leftovers ("-upgraded-<date>"); the message no longer promises a repair
    dups=$( { ls /var/lib/pkgtools/packages 2>/dev/null | grep -v -- '-upgraded-' | sed -E 's/-[^-]+-[^-]+-[^-]+$//' | sort | uniq -d
              ls /var/lib/pkgtools/packages 2>/dev/null | grep -- '-upgraded-' | sed -E 's/-upgraded-.*$//; s/-[^-]+-[^-]+-[^-]+$//'; } \
            | sort -u | head -n 5 | tr '\n' ' ')
    if [ -n "${dups}" ]; then
        log_warn "These packages were cut off half-way and should be reinstalled: ${dups% }"
        export SLACKY_TX_DUPLICATES="${dups}"
    fi
    return 1
}

# 6A-117: SpiderSense hardware profile. Shows changes found at boot or by the hourly check (hw-changed notice) and any
# change since then, in plain sentences, and stores the current profile. Read-only towards the system; ~20 ms.
SLACKY_HW_NOTICE="/var/cache/slacky-update/spidersense/hw-changed"
ss_hw_check() {
    local py="${APP_DIR:-/usr/share/slacky-update/lib}/spidersense_hw.py"
    [ -f "${py}" ] || return 0
    local lines="" line
    if [ -s "${SLACKY_HW_NOTICE}" ]; then
        lines=$(cat "${SLACKY_HW_NOTICE}" 2>/dev/null)
    fi
    local now
    if [ "$(id -u)" -eq 0 ]; then
        now=$(PYTHONSAFEPATH=1 python3 -I "${py}" check --save 2>/dev/null) || true
        rm -f "${SLACKY_HW_NOTICE}" 2>/dev/null || true
    else
        now=$(sudo env PYTHONSAFEPATH=1 python3 -I "${py}" check --save 2>/dev/null) || true
        sudo rm -f "${SLACKY_HW_NOTICE}" 2>/dev/null || true
    fi
    [ -n "${now}" ] && lines="${lines:+${lines}
}${now}"
    [ -n "${lines}" ] || return 0
    printf '%s\n' "${lines}" | awk '!seen[$0]++' | while IFS= read -r line; do
        [ -n "${line}" ] && log_warn "SpiderSense: ${line}"
    done
    { printf '%s\n' "${lines}" | sed "s/^/[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] SpiderSense hardware: /" >> "${LOG_FILE}"; } 2>/dev/null || true
    return 0
}

# 6A-95 (SS-2): remove OUR snapshots before they reach 48 hours (owner rule). The decision is lib/spidersense_snap.py
# (pure, tested); this executor only deletes what it names. Nothing is deleted while a gnomes rollback reads the
# snapshots, while the boot menu still waits for a reseal, or when the clock looks wrong. Pairs go together. A deleted
# snapshot that is still in the Limine menu leaves a reseal order (the commit or the hourly check rebuilds the menu).
SLACKY_ROLLBACK_LOCK="/run/lock/slacky-rollback.lock"
ss_prune_our_snapshots() {
    [ "$(findmnt -n -o FSTYPE / 2>/dev/null)" = "btrfs" ] || return 0
    command -v snapper >/dev/null 2>&1 || return 0
    local py="${APP_DIR:-/usr/share/slacky-update/lib}/spidersense_snap.py"
    [ -f "${py}" ] || return 0
    [ -e "${SLACKY_BOOT_PENDING}" ] && return 0
    [ -e "${SLACKY_BOOT_PENDING_SHARED}" ] && return 0   # 6A-152
    if [ -e "${SLACKY_ROLLBACK_LOCK}" ] && ! flock -n "${SLACKY_ROLLBACK_LOCK}" true 2>/dev/null; then
        return 0
    fi
    local plan
    if [ "$(id -u)" -eq 0 ]; then
        plan=$(PYTHONSAFEPATH=1 python3 -I "${py}" plan 2>/dev/null) || return 0
    else
        plan=$(sudo env PYTHONSAFEPATH=1 python3 -I "${py}" plan 2>/dev/null) || return 0
    fi
    case "${plan}" in ""|HOLD*|ERROR*) return 0 ;; esac
    local n in_menu=0 conf confs=(/boot/limine.conf)
    if declare -F detect_limine_esp_path >/dev/null; then
        conf="$(detect_limine_esp_path 2>/dev/null || true)"
        [ -n "${conf}" ] && [ "${conf%/}/limine.conf" != /boot/limine.conf ] && confs+=("${conf%/}/limine.conf")
    fi
    for n in ${plan}; do
        for conf in "${confs[@]}"; do
            # both layouts mod_limine.sh writes: <root subvol>/.snapshots/N (nested) and /@snapshots/N (own subvolume, 6A-120)
            if sudo grep -qE "(/\.snapshots|@snapshots)/${n}/snapshot" "${conf}" 2>/dev/null; then in_menu=1; fi
        done
    done
    if sudo timeout 300 snapper -c root delete ${plan} >/dev/null 2>&1; then
        { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] SpiderSense: removed our snapshots older than 48 hours: ${plan}" >> "${LOG_FILE}"; } 2>/dev/null || true
        [ "${in_menu}" -eq 1 ] && ss_mark_if_limine
    fi
    return 0
}

# SpiderSense phase 1 (spec 4.4): snapshot lifeline around a full update. snapper pre/post pair (linked by snapper
# itself, "undo this update"), cleanup algorithm "number" so snapper's own NUMBER_LIMIT keeps the count bounded;
# this code never deletes snapshots. Returns 0 = created, 1 = failed, 2 = not a Btrfs root with a snapper root config.
SLACKY_SNAP_PRE=""
create_pre_update_snapshot() {
    SLACKY_SNAP_PRE=""
    [ "$(findmnt -n -o FSTYPE / 2>/dev/null)" = "btrfs" ] || return 2
    command -v snapper >/dev/null 2>&1 || return 2
    if [ ! -f /etc/snapper/configs/root ]; then
        # 6A-309: Btrfs root and snapper, but no snapper config for /: system changes are NOT held (unchanged), but say so once per run
        if [ -z "${SLACKY_SNAP_NOCONF_SAID:-}" ]; then
            export SLACKY_SNAP_NOCONF_SAID=1
            log_warn "No safety snapshot can be made because snapper has no setup for this system; to set it up run: sudo snapper -c root create-config /"
            { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] SpiderSense: safety net missing, snapper has no config for / (fix: snapper -c root create-config /)" >> "${LOG_FILE}"; } 2>/dev/null || true
        fi
        return 2
    fi
    local n
    # 6A-94: tagged as ours, no snapper cleanup algorithm (our 48-hour pruner removes it; the owner's numbered
    # snapshots no longer share snapper's NUMBER_LIMIT with ours)
    # 6A-355: the id ends up in snapper userdata and a file name: only a plain token from the environment is kept
    [[ "${SLACKY_TX_ID:-}" =~ ^[0-9A-Za-z._-]{1,64}$ ]] || SLACKY_TX_ID=""
    SLACKY_TX_ID="${SLACKY_TX_ID:-$(date +%Y%m%d%H%M%S)-$$}"
    n=$(sudo timeout 180 snapper -c root create --type pre \
        --description "slacky-update: before full update" \
        --userdata "slacky=1,slacky-app=legacy,slacky-kind=pre,slacky-tx=${SLACKY_TX_ID}" --print-number 2>/dev/null) || return 1
    n=$(printf '%s' "${n}" | tr -cd '0-9')
    [ -n "${n}" ] || return 1
    SLACKY_SNAP_PRE="${n}"
    { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] SpiderSense: pre-update snapshot #${n}" >> "${LOG_FILE}"; } 2>/dev/null || true
    return 0
}
create_post_update_snapshot() {
    [ -n "${SLACKY_SNAP_PRE}" ] || return 0
    if sudo timeout 180 snapper -c root create --type post --pre-number "${SLACKY_SNAP_PRE}" \
        --description "slacky-update: after full update" \
        --userdata "slacky=1,slacky-app=legacy,slacky-kind=post,slacky-tx=${SLACKY_TX_ID:-}" >/dev/null 2>&1; then
        { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] SpiderSense: post-update snapshot paired with #${SLACKY_SNAP_PRE}" >> "${LOG_FILE}"; } 2>/dev/null || true
    else
        log_warn "The after-update snapshot could not be created; the before-update snapshot #${SLACKY_SNAP_PRE} is still there."
    fi
}

# Atomic update transaction protection:
# Prevents accidental ESC or signal interruption from corrupting or breaking
# in-flight package transactions, kernel builds, or initramfs generations.
begin_atomic_transaction() {
    local tx_name="${1:-package transaction}"
    log_info "Locking execution state for ${tx_name} (abort disabled)..."
    # 6A-89: closing the terminal (SIGHUP) must not kill a half-done package transaction
    trap '' INT QUIT TSTP HUP
    # 6A-47 / 6A-149: no transaction without the run lock (before: "|| true" let --clean prune kernels during an update)
    if ! acquire_run_lock; then
        trap - INT QUIT TSTP HUP
        return 1
    fi
    ss_safe_output_on
}

end_atomic_transaction() {
    trap - INT QUIT TSTP HUP
    ss_safe_output_off
}

# 6A-145 (LTS B1): HUP is ignored, but once the terminal is gone every write to it fails (EIO) and under set -e the
# first failing echo/printf ended the run before the boot chain. During a transaction these two builtins never fail
# the script; what matters also goes to the log file. Children keep the inherited HUP-ignore.
ss_safe_output_on() {
    echo() { builtin echo "$@" 2>/dev/null || true; }
    printf() { builtin printf "$@" 2>/dev/null || true; }
}
ss_safe_output_off() {
    unset -f echo printf 2>/dev/null || true
}


check_slacky_update_self_update() {
    local current_ver="${1:-${CURRENT_VERSION:-0.10}}"
    local rel_json=""
    # 1. Query GitHub API (canonical release source)
    rel_json=$(curl -sSL -m 4 -H "User-Agent: slacky-update" "https://api.github.com/repos/TuxOfValhalla/slacky-update/releases/latest" 2>/dev/null || true)
    # 6A-280 (R6): a failed check must never be reported as "up to date" (the helper below answers CHECK_FAILED|reason)

    local update_info
    update_info=$(echo "${rel_json}" | python3 -c "
import json, sys, re, os

_PRE = {'dev': 0, 'alpha': 1, 'a': 1, 'beta': 2, 'b': 2, 'pre': 3, 'rc': 4}

def parse_v(v_str):
    # 6A-280 (M1): (numbers without trailing zeros, final flag, pre-release rank, pre-release number); a pre-release
    # (1.0_RC2) sorts BEFORE its final release (1.0); 1.0 equals 1.0.0; 1.0.1 and 1.1 are newer than 1.0
    m = re.match(r'^v?(\d+(?:\.\d+)*)(?:[._-]?(dev|alpha|beta|pre|rc|a|b)\.?_?(\d*))?', v_str.strip(), re.I)
    if not m:
        return ((), 0, 0, 0)
    nums = [int(x) for x in m.group(1).split('.')]
    while nums and nums[-1] == 0:
        nums.pop()
    if m.group(2):
        return (tuple(nums), 0, _PRE[m.group(2).lower()], int(m.group(3) or 0))
    return (tuple(nums), 1, 0, 0)

cur = '${current_ver}'.lstrip('v')
try:
    content = sys.stdin.read().strip()
    if not content:
        print('CHECK_FAILED|offline')
        sys.exit(0)
    data = json.loads(content)
    if not isinstance(data, dict) or not data.get('tag_name'):
        msg = str(data.get('message', '')).lower() if isinstance(data, dict) else ''
        print('CHECK_FAILED|' + ('limit' if 'rate limit' in msg else 'answer'))
        sys.exit(0)
    if True:
        tag = data.get('tag_name', '').lstrip('v')
        tag_newer = bool(tag and parse_v(tag) > parse_v(cur))
        
        dl_url = ''
        dl_digest = ''
        asset_newer = False
        asset_display_tag = tag
        pkg_pattern = re.compile(r'slacky-update-([0-9a-zA-Z._]+)-noarch-(\d+)')
        for asset in data.get('assets', []):
            name = asset.get('name', '')
            if name.endswith(('.txz', '.tgz')):
                dl_url = asset.get('browser_download_url', '')
                dl_digest = asset.get('digest') or ''
                m = pkg_pattern.search(name)
                if m:
                    a_ver, a_build = m.group(1), int(m.group(2))
                    if parse_v(a_ver) == parse_v(cur):
                        import glob
                        # 6A-350: only slacky-update-<version>-... (never slacky-update-rs); the highest installed build counts
                        local_best = -1
                        for lp in sorted(glob.glob('/var/log/packages/slacky-update-[0-9]*')):
                            lm = pkg_pattern.search(os.path.basename(lp))
                            if lm and parse_v(lm.group(1)) == parse_v(cur):
                                local_best = max(local_best, int(lm.group(2)))
                        if local_best >= 0:
                            if local_best < a_build:
                                asset_newer = True
                                asset_display_tag = '{}-build{}'.format(tag, a_build)
                if dl_url:
                    break
        if not dl_url:
            dl_url = data.get('tarball_url', '')

        if tag_newer or asset_newer:
            print(f'UPDATE|{asset_display_tag}|{dl_url}|{dl_digest}')
            sys.exit(0)
except Exception:
    print('CHECK_FAILED|answer')
    sys.exit(0)
print(f'UP_TO_DATE|{cur}')
" 2>/dev/null || echo "CHECK_FAILED|answer")

    local status_type rest
    IFS='|' read -r status_type rest <<< "${update_info}"

    if [ "${status_type}" = "UPDATE" ]; then
        local new_tag dl_url dl_digest
        IFS='|' read -r new_tag dl_url dl_digest <<< "${rest}"

        echo ""
        echo -e "${YELLOW}${BOLD}New Slacky-Update release available: v${new_tag} (current: v${current_ver})${RESET}"
        read -r -p "$(_ PROMPT_SELF_UPDATE)" reply_update
        reply_update=${reply_update:-Y}
        if [[ "$reply_update" =~ ^[YyJjSsOo]$ ]]; then
            # 6A-40: download as the user into a private dir, accept only a release asset of this project,
            # verify it against the SHA256 digest GitHub publishes for the asset, check root ownership,
            # and use root only for upgradepkg. No digest = no install (tell the user how to update by hand).
            local rel_prefix="https://github.com/TuxOfValhalla/slacky-update/releases/download/"
            local asset_name="${dl_url##*/}"
            if [[ ! "${new_tag}" =~ ^[0-9A-Za-z._-]+$ ]] || [[ "${dl_url}" != "${rel_prefix}"* ]] \
                || [[ ! "${asset_name}" =~ ^slacky-update-[0-9A-Za-z._]+-noarch-[0-9]+_slacky\.t[gx]z$ ]]; then
                log_warn "The new release could not be checked, so it was not installed. Download it from https://github.com/TuxOfValhalla/slacky-update/releases and install it with upgradepkg."
                return 0
            fi
            local want_sha="${dl_digest#sha256:}"
            if [[ "${dl_digest}" != sha256:* ]] || [[ ! "${want_sha}" =~ ^[0-9a-f]{64}$ ]]; then
                log_warn "The new release has no checksum, so it was not installed. Download it from https://github.com/TuxOfValhalla/slacky-update/releases and install it with upgradepkg."
                return 0
            fi
            log_info "Downloading Slacky-Update v${new_tag}..."
            local su_dir
            su_dir=$(mktemp -d /tmp/slacky-selfupdate-XXXXXX) || return 0
            local tmp_pkg="${su_dir}/${asset_name}"
            if ! curl -fsSL -m 300 -o "${tmp_pkg}" "${dl_url}"; then
                log_warn "Downloading the new release failed. Nothing was changed."
                rm -rf "${su_dir}"
                return 0
            fi
            if [ "$(sha256sum "${tmp_pkg}" | cut -d' ' -f1)" != "${want_sha}" ]; then
                log_error "The downloaded release does not match its checksum. Nothing was changed."
                rm -rf "${su_dir}"
                return 0
            fi
            # list once into a variable: with pipefail, "tar | grep -q" would fail on SIGPIPE for a valid package
            local pkg_list=""
            pkg_list=$(tar --numeric-owner -tvf "${tmp_pkg}" 2>/dev/null) || pkg_list=""
            if [ -z "${pkg_list}" ] || [ -n "$(awk '$2 != "0/0"' <<< "${pkg_list}")" ] \
                || ! grep -q ' usr/bin/slacky-update$' <<< "${pkg_list}"; then
                log_error "The downloaded release is not a valid slacky-update package. Nothing was changed."
                rm -rf "${su_dir}"
                return 0
            fi
            chmod 644 "${tmp_pkg}"
            validate_privileges
            if sudo "${PKG_UPGRADE_CMD}" --reinstall "${tmp_pkg}"; then
                rm -rf "${su_dir}"
                log_success "Slacky-Update upgraded to v${new_tag}!"
                killall slacky-update-tray 2>/dev/null || pkill -f slacky-update-tray || true
                nohup "$(command -v slacky-update-tray 2>/dev/null || echo "/usr/local/bin/slacky-update-tray")" >/dev/null 2>&1 &
                exec "$(command -v slacky-update 2>/dev/null || echo "/usr/local/bin/slacky-update")" "$@"
            else
                log_error "Installing the new release failed. The current version is still installed."
                rm -rf "${su_dir}"
            fi
        fi
    elif [ "${status_type}" = "CHECK_FAILED" ]; then
        local why_key="SELF_UPDATE_WHY_ANSWER"
        [ "${rest}" = "offline" ] && why_key="SELF_UPDATE_WHY_OFFLINE"
        [ "${rest}" = "limit" ] && why_key="SELF_UPDATE_WHY_LIMIT"
        echo -e "  ${YELLOW}$(_ SELF_UPDATE_CHECK_FAILED why="$(_ "${why_key}")")${RESET}"
    else
        echo -e "  ${BLUE}$(_ APP_UP_TO_DATE tag="v${current_ver}")${RESET}"
    fi
}

trigger_silent_background_refresh() {
    [ "${SLACKY_UPDATE_RUNNING:-0}" = "1" ] && return 0
    local chk_bin=""
    for cand in "${APP_DIR:-}/check_backend.sh" \
                "/usr/share/slacky-update/lib/check_backend.sh" \
                "/usr/local/lib/slacky-update/check_backend.sh"; do
        if [ -x "${cand}" ]; then
            chk_bin="${cand}"
            break
        fi
    done
    if [ -n "${chk_bin}" ]; then
        nohup "${chk_bin}" </dev/null >/dev/null 2>&1 &
    fi
}

# 6A-17: the system cache is root-only (root:root 0755) and the log is 0644. Anything written without root goes to the
# user's cache (~/.cache/slacky-update); readers already pick the newest status.json from both. Before, this dir was
# made 1777 and the log 0666, so any local user could plant files that root later read or wrote (mirror list, status).
init_storage() {
    local run=""
    if [ "$(id -u)" -ne 0 ]; then
        sudo -n true 2>/dev/null && run="sudo -n"
    fi
    if [ "$(id -u)" -eq 0 ] || [ -n "${run}" ]; then
        ${run} install -d -m 0755 -o root -g root "${CACHE_DIR}" "${CACHE_DIR}/kernel" "${CACHE_DIR}/nvidia" "${CACHE_DIR}/slacky-slackbuilds" 2>/dev/null || true
        # One-time repair of an old world-writable or user-owned cache (chown/chmod -R never follow symlinks)
        if [ -n "$(${run} find "${CACHE_DIR}" \( ! -user root -o ! -group root -o -perm -0002 \) -print -quit 2>/dev/null)" ]; then
            ${run} chown -R root:root "${CACHE_DIR}" 2>/dev/null || true
            ${run} chmod -R go-w "${CACHE_DIR}" 2>/dev/null || true
        fi
        # 6A-57: only the system log path; LOG_FILE may already point at the user's cache after an earlier call, and
        # `sudo touch/chown root` on it left a root-owned file in the home directory ("Permission denied" on every log line)
        ${run} touch /var/log/slacky-update.log 2>/dev/null || true
        ${run} chown root:root /var/log/slacky-update.log 2>/dev/null || true
        ${run} chmod 0644 /var/log/slacky-update.log 2>/dev/null || true
    fi
    if [ "$(id -u)" -ne 0 ]; then
        local user_cache="${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/slacky-update"
        mkdir -p "${user_cache}" 2>/dev/null || true
        # 6A-57 repair: a log file not owned by this user in our own cache dir is removed (allowed: the dir is ours)
        if [ -L "${user_cache}/slacky-update.log" ] || { [ -e "${user_cache}/slacky-update.log" ] && [ ! -O "${user_cache}/slacky-update.log" ]; }; then
            rm -f "${user_cache}/slacky-update.log" 2>/dev/null || true
        fi
        [ -w "${LOG_FILE}" ] || LOG_FILE="${user_cache}/slacky-update.log"
    fi
}

# 6A-27: called by the --hyprland*/--hyprmod/--mactahoe-*/--whitesur-* shortcuts (added in 1e1e25c) but never defined.
# Creates the cache dir root-owned 0755 when it is missing; an existing dir is left as it is (permissions: 6A-17).
ensure_cache_dir() {
    [ -d "${CACHE_DIR}" ] && return 0
    if [ "$(id -u)" -eq 0 ]; then
        install -d -m 0755 -o root -g root "${CACHE_DIR}"
    else
        sudo install -d -m 0755 -o root -g root "${CACHE_DIR}"
    fi
}

validate_privileges() {
    if [ "$(id -u)" -ne 0 ]; then
        if ! sudo -v 2>/dev/null; then
            log_error "Administrative privileges are required to proceed."
            exit 1
        fi
    fi
    init_storage
}

probe_gpu_hardware() {
    HAS_NVIDIA=false
    HAS_AMD=false
    HAS_INTEL=false
    IS_LAPTOP=false
    IS_HYBRID_GPU=false

    # 6A-118: one SpiderSense answer (sysfs, display classes only, the GPU that drives the screen decides "hybrid": a
    # desktop with its iGPU switched on is no longer called hybrid). lspci below is the fallback only.
    if ss_hw_load; then
        HAS_NVIDIA="${HW_HAS_NVIDIA}"; HAS_AMD="${HW_HAS_AMD}"; HAS_INTEL="${HW_HAS_INTEL}"
        IS_LAPTOP="${HW_LAPTOP}"; IS_HYBRID_GPU="${HW_HYBRID}"
        return 0
    fi

    if is_laptop_chassis; then
        IS_LAPTOP=true
    fi

    local pci_devs
    pci_devs=$(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' || true)

    if echo "${pci_devs}" | grep -qi '\[10de:'; then
        HAS_NVIDIA=true
    fi
    if echo "${pci_devs}" | grep -qi '\[1002:'; then
        HAS_AMD=true
    fi
    if echo "${pci_devs}" | grep -qi '\[8086:'; then
        HAS_INTEL=true
    fi

    # Robust sysfs fallback if lspci is unavailable or unprivileged
    if [ "${HAS_NVIDIA}" = "false" ] && [ "${HAS_AMD}" = "false" ] && [ "${HAS_INTEL}" = "false" ]; then
        if ls -d /sys/bus/pci/devices/* 1>/dev/null 2>&1; then
            for vfile in /sys/bus/pci/devices/*/vendor; do
                [ -f "${vfile}" ] || continue
                # 6A-78: display devices only (class 0x03xxxx); chipsets and network cards of the same vendor are not GPUs
                case "$(cat "${vfile%/vendor}/class" 2>/dev/null)" in 0x03*) ;; *) continue ;; esac
                local v_id
                v_id=$(cat "${vfile}" 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)
                case "${v_id}" in
                    *10de*) HAS_NVIDIA=true ;;
                    *1002*) HAS_AMD=true ;;
                    *8086*) HAS_INTEL=true ;;
                esac
            done
        fi
        if [ -d /proc/driver/nvidia ] || [ -f /sys/module/nvidia/version ]; then
            HAS_NVIDIA=true
        fi
    fi

    # Hybrid GPU calculation:
    # If multiple GPU vendors are detected, or if it is a laptop with NVIDIA dGPU
    local gpu_count=0
    [ "${HAS_NVIDIA}" = "true" ] && ((gpu_count++)) || true
    [ "${HAS_AMD}" = "true" ] && ((gpu_count++)) || true
    [ "${HAS_INTEL}" = "true" ] && ((gpu_count++)) || true

    if [ "${gpu_count}" -ge 2 ]; then
        IS_HYBRID_GPU=true
    elif [ "${IS_LAPTOP}" = "true" ] && [ "${HAS_NVIDIA}" = "true" ]; then
        IS_HYBRID_GPU=true
    fi
}

resolve_mok_keypair() {
    local sbverify_bin
    sbverify_bin=$(command -v sbverify 2>/dev/null || echo "/usr/bin/sbverify")

    MOK_CRT=""
    MOK_DER=""
    MOK_KEY=""

    # 1. Smart Detection: Match active/installed signed kernels in /boot with candidate certs
    local cert_candidates=(
        "/etc/mok/MOK.crt"
        "/etc/mok/mok.crt"
        "/etc/mok/MOK.der"
        "/etc/mok/mok.der"
        "/root/MOK.crt"
        "/root/MOK.der"
        /etc/mok/*.crt
        /etc/mok/*.der
        /etc/ssl/certs/MOK.crt
        /etc/ssl/certs/MOK.der
    )

    if [ -x "${sbverify_bin}" ]; then
        for k in /boot/vmlinuz-*; do
            [ -f "$k" ] && [ ! -L "$k" ] || continue
            for cert in "${cert_candidates[@]}"; do
                [ -f "$cert" ] || continue
                if "${sbverify_bin}" --cert "$cert" "$k" >/dev/null 2>&1; then
                    local dir base
                    dir=$(dirname "$cert")
                    base=$(basename "$cert" | sed 's/\.[^.]*$//')

                    if [[ "$cert" =~ \.crt$ ]]; then
                        MOK_CRT="$cert"
                        [ -f "$dir/$base.der" ] && MOK_DER="$dir/$base.der"
                    elif [[ "$cert" =~ \.der$ ]]; then
                        MOK_DER="$cert"
                        [ -f "$dir/$base.crt" ] && MOK_CRT="$dir/$base.crt"
                    fi

                    for k_cand in "$dir/$base.priv" "$dir/$base.key" "$dir/MOK.priv" "$dir/MOK.key" /etc/mok/MOK.priv /etc/mok/MOK.key /root/MOK.priv /root/MOK.key; do
                        if [ -f "$k_cand" ]; then
                            MOK_KEY="$k_cand"
                            break 2
                        fi
                    done
                fi
            done
        done
    fi

    # 2. Candidate resolution fallback if not resolved via signed kernel
    if [ -z "${MOK_KEY}" ] || { [ -z "${MOK_CRT}" ] && [ -z "${MOK_DER}" ]; }; then
        local pem_crt_candidates=(
            "/etc/mok/MOK.crt"
            "/etc/mok/mok.crt"
            "/root/MOK.crt"
            "/etc/ssl/certs/MOK.crt"
        )

        local der_crt_candidates=(
            "/etc/mok/MOK.der"
            "/etc/mok/mok.der"
            "/root/MOK.der"
            "/etc/ssl/certs/MOK.der"
        )

        local key_candidates=(
            "/etc/mok/MOK.priv"
            "/etc/mok/MOK.key"
            "/etc/mok/mok.key"
            "/root/MOK.priv"
            "/root/MOK.key"
            "/etc/ssl/certs/MOK.key"
        )

        for c in "${pem_crt_candidates[@]}"; do
            if [ -f "$c" ]; then
                MOK_CRT="$c"
                break
            fi
        done

        for d in "${der_crt_candidates[@]}"; do
            if [ -f "$d" ]; then
                MOK_DER="$d"
                break
            fi
        done

        for k in "${key_candidates[@]}"; do
            if [ -f "$k" ]; then
                MOK_KEY="$k"
                break
            fi
        done
    fi

    # Complement CRT / DER pair if only one is present
    if [ -n "${MOK_CRT}" ] && [ -z "${MOK_DER}" ]; then
        local der_match="${MOK_CRT%.*}.der"
        [ -f "${der_match}" ] && MOK_DER="${der_match}"
    elif [ -n "${MOK_DER}" ] && [ -z "${MOK_CRT}" ]; then
        local crt_match="${MOK_DER%.*}.crt"
        [ -f "${crt_match}" ] && MOK_CRT="${crt_match}"
    fi

    MOK_CERT="${MOK_CRT:-${MOK_DER}}"
}

check_and_shield_mirror_freshness() {
    # Check primary Slackware mirror reachability
    local primary_mirror
    primary_mirror=$(grep -v '^#' /etc/slackpkg/mirrors 2>/dev/null | grep -E '^https?://' | head -n 1 || echo "")
    if [ -n "${primary_mirror}" ]; then
        if ! curl -sSLI -m 4 -f -o /dev/null "${primary_mirror}" 2>/dev/null; then
            log_warn "Primary Slackware mirror (${primary_mirror}) timed out or is unreachable. The Slackware update may fail; the other update parts continue."
        fi
    fi

    # 6A-5: slackpkgplus.conf is the user's configuration and is no longer edited here. This used to switch
    # STRICTGPG=on to off silently (packages from one repository could then be signed by any imported key). Repositories
    # such as multilib and alienbob each have their own key; `slackpkg update gpg` imports them, so strict checking works.
}

run_slackpkg() {
    local slackpkg_bin="${SLACKPKG_CMD:-$(command -v slackpkg 2>/dev/null || echo "/usr/sbin/slackpkg")}"
    if [ ! -x "${slackpkg_bin}" ]; then
        log_error "slackpkg binary not found on this system."
        return 1
    fi

    # Terminal anchor: ensure clean newline boundary before starting slackpkg
    if [ -t 1 ] || [ "${TERM:-}" != "dumb" ]; then
        printf "\n"
    else
        echo ""
    fi

    # Run slackpkg from a throw-away temp dir so that wget-log.N files never
    # land in $HOME or whatever the caller's CWD happens to be.
    local _sp_tmpdir
    _sp_tmpdir=$(mktemp -d /tmp/slacky-slackpkg-XXXXXX)

    local rc=0
    # Full-spectrum stream normalizer:
    #   1. Pre-converts DEC/CSI restore-cursor (\x1b8, \x1b[u) to \r so tput rc
    #      is treated as a line-boundary (prevents spinner overwriting scrollback).
    #   2. Strips ALL VT100/ANSI/DEC/OSC escape sequences — not just cursor-up.
    #   3. Filters spinner-only lines (|/-\ and whitespace).
    #   4. Filters intermediate progress percentages; keeps 100% and real output.
    # 6A-89: slackpkg ignores SIGHUP (closed terminal) and the filter below keeps draining its output even when the
    # terminal is gone, so slackpkg never dies on a broken pipe in the middle of upgradepkg.
    (cd "${_sp_tmpdir}" && sudo /bin/sh -c 'trap "" HUP; exec "$@"' sh "${slackpkg_bin}" "$@" 2>&1) | python3 -u -c '
import sys, re

if hasattr(sys.stdin, "reconfigure"):
    sys.stdin.reconfigure(errors="replace")
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(errors="replace")

# Pre-convert restore-cursor sequences to \r (they rewind the cursor like \r does)
# \x1b8 = DEC Restore Cursor (tput rc); \x1b[u = CSI Restore Cursor
restore_cursor_re = re.compile(r"\x1b8|\x1b\[u")

# Full VT100/ANSI/DEC/OSC escape sequence stripper:
#   [0-9@-Z\\-_]        2-char ESC seqs: Fp (0-9 incl. ESC7/8) + Fe (@-Z, \\, [-_)
#   \[[\x20-\x3f]*[\x40-\x7e]   CSI: ESC [ ... params ... final byte
#   \][^\x07\x1b]*(?:\x07|\x1b\\)  OSC: ESC ] ... BEL or ST
ansi_re = re.compile(
    r"\x1b(?:"
    r"[0-9@-Z\\\\-_]"
    r"|\[[\x20-\x3f]*[\x40-\x7e]"
    r"|\][^\x07\x1b]*(?:\x07|\x1b\\\\)"
    r")"
)

# Progress percentage filter (keep 100% and final; drop 1-99%)
prog_re = re.compile(r"(\d{1,2}%|\[\s*={1,10}>\s*\]|\[\s*\])")

# Spinner-only lines: nothing but |, /, -, \ and whitespace
spinner_re = re.compile(r"^[|/\\\\\-\s]*$")

# wget background-mode plumbing noise: "Redirecting output to 'wget-log.N'."
wget_redirect_re = re.compile(r"^Redirecting output to ")

import signal
signal.signal(signal.SIGHUP, signal.SIG_IGN)  # 6A-89: a closed terminal must not stop the drain
_out_dead = False
def out(text):
    global _out_dead
    if _out_dead:
        return
    try:
        sys.stdout.write(text)
        sys.stdout.flush()
    except (OSError, ValueError):
        _out_dead = True

buf = []
while True:
    try:
        chunk = sys.stdin.read(1024)
    except Exception:
        break
    if not chunk:
        break
    # Convert restore-cursor to \r before char-by-char parsing
    chunk = restore_cursor_re.sub("\r", chunk)
    for ch in chunk:
        if ch in ("\r", "\n"):
            line = "".join(buf)
            buf.clear()
            clean = ansi_re.sub("", line).strip()
            if not clean:
                continue
            if spinner_re.match(clean):
                continue
            if wget_redirect_re.match(clean):
                continue
            if ch == "\r" and prog_re.search(clean) and "100%" not in clean:
                continue
            out(clean + "\n")
        else:
            buf.append(ch)

if buf:
    clean = ansi_re.sub("", "".join(buf)).strip()
    if clean and not spinner_re.match(clean):
        out(clean + "\n")
' || rc=$?

    rm -rf "${_sp_tmpdir}"

    # Terminal anchor: flush newline after slackpkg completes
    if [ -t 1 ] || [ "${TERM:-}" != "dumb" ]; then
        printf "\n"
    else
        echo ""
    fi

    return ${rc}
}

run_post_update_smoke_test() {
    local kver active_driver="Mesa / In-Tree"
    kver=$(uname -r)
    if [ "${HAS_NVIDIA}" = "true" ] && command -v nvidia-smi >/dev/null 2>&1; then
        local nv_ver
        nv_ver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n 1 || echo "")
        [ -n "${nv_ver}" ] && active_driver="NVIDIA ${nv_ver}"
    fi

    local multi_status="Not Configured"
    local multi_ok=0
    if ls /var/log/packages/*-compat32* >/dev/null 2>&1 || [ -e "/lib/ld-linux.so.2" ]; then
        if [ -e "/lib/ld-linux.so.2" ] && /lib/ld-linux.so.2 --version >/dev/null 2>&1; then
            local g_ver
            g_ver=$(/lib/ld-linux.so.2 --version 2>/dev/null | head -n 1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1 || echo "2.x")
            multi_status="glibc ${g_ver} (/lib/ld-linux.so.2 active - Steam & Wine ready)"
            multi_ok=1
        else
            multi_status="DEGRADED (/lib/ld-linux.so.2 unresponsive)"
        fi
    fi

    echo ""
    echo -e "${CYAN}${BOLD}=== POST-UPDATE SUBSYSTEM HEALTH CHECK ===${RESET}"
    if [ "${1:-}" = "SKIPPED_MIRROR_ERROR" ] || [ "${SLACK_CORE_STATUS:-}" = "SKIPPED_MIRROR_ERROR" ]; then
        echo -e "  ${YELLOW}[WARN]${RESET} 64-bit Slackware Core : ${YELLOW}Skipped (the Slackware update server did not answer)${RESET}"
    elif [ "${1:-}" = "FAILED" ]; then
        # 6A-347 (1c): "healthy" is only said after a real success (not after errors or a declined update)
        echo -e "  ${RED}[FAIL]${RESET} 64-bit Slackware Core : ${RED}The update did not finish (see the messages above)${RESET}"
    elif [ "${1:-}" = "PENDING" ]; then
        echo -e "  ${YELLOW}[WARN]${RESET} 64-bit Slackware Core : ${YELLOW}Updates are still waiting; they were not installed${RESET}"
    else
        echo -e "  ${GREEN}[ OK ]${RESET} 64-bit Slackware Core : ${GREEN}Up-to-date & healthy${RESET}"
    fi
    echo -e "  ${GREEN}[ OK ]${RESET} Kernel & Video Driver : ${GREEN}${kver} / ${active_driver}${RESET}"
    if [ "${multi_ok}" -eq 1 ]; then
        echo -e "  ${GREEN}[ OK ]${RESET} 32-bit Multilib Armor : ${GREEN}${multi_status}${RESET}"
    elif [ "${multi_status}" != "Not Configured" ]; then
        echo -e "  ${YELLOW}[!]${RESET} 32-bit Multilib Armor : ${YELLOW}${multi_status}${RESET}"
    else
        echo -e "  ${BLUE}[-]${RESET} 32-bit Multilib Armor : ${multi_status}"
    fi
    echo -e "${CYAN}${BOLD}=============================================${RESET}"
}

# 6A-180..182: folder that holds slacky_mirrors.py (the shared mirror lists and fall-back); empty when it is missing,
# and then the single given mirror is used as before.
slacky_mirrors_lib_dir() {
    local d
    for d in "${GNOMES_PY:+$(dirname "${GNOMES_PY}")}" "${APP_DIR:-}" "${SCRIPT_DIR:-}/../lib" "${SCRIPT_DIR:-}" /usr/share/slacky-update/lib /usr/local/lib/slacky-update; do
        [ -n "${d}" ] && [ -f "${d}/slacky_mirrors.py" ] && { printf '%s' "${d}"; return 0; }
    done
    return 0
}

download_parallel_pacman() {
    local label="$1"
    shift
    local items=("$@")
    [ ${#items[@]} -gt 0 ] || return 0

    SLACKY_LIB_DIR="$(slacky_mirrors_lib_dir)" python3 - "${label}" "${items[@]}" << 'PYPACMAN'
import os
import sys
import time
import subprocess
import threading
import concurrent.futures

label = sys.argv[1] if len(sys.argv) > 1 else "Downloading"
raw_items = sys.argv[2:]

# 6A-181: shared mirror fall-back (Chaotic-AUR, Arch, CachyOS); without the module the given url is the only one
_sm = None
try:
    _lib = os.environ.get("SLACKY_LIB_DIR", "")
    if _lib and os.path.isfile(os.path.join(_lib, "slacky_mirrors.py")):
        sys.path.insert(0, _lib)
        import slacky_mirrors as _sm
except Exception:
    _sm = None
failed_sentences = set()

if not raw_items:
    sys.exit(0)

# Parse items: url|dest_file[|sig_url|sig_dest]
items = []
seen_dests = set()
for entry in raw_items:
    parts = entry.strip().split('|')
    if len(parts) >= 2:
        url = parts[0].strip()
        dest = parts[1].strip()
        if dest in seen_dests:
            continue
        seen_dests.add(dest)
        sig_url = parts[2].strip() if len(parts) >= 4 else (f"{url}.sig" if len(parts) == 3 else "")
        sig_dest = parts[3].strip() if len(parts) >= 4 else (f"{dest}.sig" if len(parts) == 3 else "")
        items.append((url, dest, sig_url, sig_dest))

if not items:
    sys.exit(0)

needed = []
for url, dest, sig_url, sig_dest in items:
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        if sig_dest and (not os.path.exists(sig_dest) or os.path.getsize(sig_dest) == 0):
            needed.append((url, dest, sig_url, sig_dest))
        else:
            continue
    else:
        needed.append((url, dest, sig_url, sig_dest))

total_items = len(needed)
if total_items == 0:
    sys.exit(0)

try:
    num_workers = int(os.environ.get('SLACKY_PREFETCH_JOBS', '10'))
    num_workers = max(1, min(num_workers, 32))
except Exception:
    num_workers = 10

def format_size(num_bytes):
    if num_bytes <= 0:
        return "  0.0 B"
    elif num_bytes < 1024:
        return f"{int(num_bytes)} B"
    elif num_bytes < 1024 * 1024:
        return f"{num_bytes / 1024.0:.1f} KiB"
    elif num_bytes < 1024 * 1024 * 1024:
        return f"{num_bytes / (1024.0 * 1024.0):.1f} MiB"
    else:
        return f"{num_bytes / (1024.0 * 1024.0 * 1024.0):.1f} GiB"

def format_speed(bytes_per_sec):
    if bytes_per_sec <= 0:
        return "  0.0 B/s"
    elif bytes_per_sec < 1024 * 1024:
        return f"{bytes_per_sec / 1024.0:.1f} KiB/s"
    else:
        return f"{bytes_per_sec / (1024.0 * 1024.0):.1f} MiB/s"

def format_eta(seconds):
    if seconds < 0 or seconds > 36000:
        return "--:--"
    m, s = divmod(int(seconds), 60)
    h, m = divmod(m, 60)
    if h > 0:
        return f"{h:02d}:{m:02d}:{s:02d}"
    return f"{m:02d}:{s:02d}"

CURSOR_HIDE = "\033[?25l"
CURSOR_SHOW = "\033[?25h"

def hide_cursor():
    if is_tty:
        sys.stdout.write(CURSOR_HIDE)
        sys.stdout.flush()

def show_cursor():
    if is_tty:
        sys.stdout.write(CURSOR_SHOW)
        sys.stdout.flush()

import atexit, signal
atexit.register(show_cursor)
def _sig_handler(sig, frame):
    show_cursor()
    sys.exit(128 + sig if isinstance(sig, int) else 1)
try:
    signal.signal(signal.SIGINT, _sig_handler)
    signal.signal(signal.SIGTERM, _sig_handler)
except Exception:
    pass

def render_pacman_bar(pct, width=28, chomp_state=0):
    pct_val = max(0.0, pct)
    pct_str = f"{int(pct_val):>3d}%"
    if pct_val >= 100.0:
        return f"[{'-' * width}] {pct_str}"
    pos = int((pct_val / 100.0) * width)
    pos = min(width - 1, max(0, pos))
    eaten = "-" * pos
    mouth_open = (chomp_state % 2 == 0)
    eater = "\033[1;34mS\033[0m" if mouth_open else "\033[1;34ms\033[0m"
    food = "".join("o" if (j % 2 == 0) else " " for j in range(pos + 1, width))
    return f"[{eaten}{eater}{food}] {pct_str}"

size_map = {}
def probe_size(item):
    url, dest, sig_url, sig_dest = item
    fn = os.path.basename(dest).lower()

    # 1. Smart HTTP HEAD/GET header probe with curl
    try:
        res = subprocess.run(["curl", "-sIL", "-A", "Mozilla/5.0 (X11; Linux x86_64)", "-m", "3", url], capture_output=True, text=True)
        if res.returncode == 0 and res.stdout:
            for line in reversed(res.stdout.splitlines()):
                line_clean = line.strip().lower()
                if line_clean.startswith("content-length:"):
                    try:
                        sz = int(line.split(":", 1)[1].strip())
                        if sz > 1024:
                            size_map[url] = sz
                            return
                    except Exception:
                        pass
                elif line_clean.startswith("content-range:"):
                    try:
                        sz = int(line.split("/", 1)[1].strip())
                        if sz > 1024:
                            size_map[url] = sz
                            return
                    except Exception:
                        pass
    except Exception:
        pass

    # 2. Smart HTTP Range probe (bytes=0-0) if HEAD didn't yield size
    try:
        res = subprocess.run(["curl", "-sSL", "-r", "0-0", "-D", "-", "-o", "/dev/null", "-A", "Mozilla/5.0 (X11; Linux x86_64)", "-m", "3", url], capture_output=True, text=True)
        if res.returncode == 0 and res.stdout:
            for line in reversed(res.stdout.splitlines()):
                line_clean = line.strip().lower()
                if line_clean.startswith("content-range:"):
                    try:
                        sz = int(line.split("/", 1)[1].strip())
                        if sz > 1024:
                            size_map[url] = sz
                            return
                    except Exception:
                        pass
                elif line_clean.startswith("content-length:"):
                    try:
                        sz = int(line.split(":", 1)[1].strip())
                        if sz > 1024:
                            size_map[url] = sz
                            return
                    except Exception:
                        pass
    except Exception:
        pass

    # 3. Known package heuristics based on filename
    if any(k in fn for k in ["edge", "chrome", "brave", "zen-browser"]):
        size_map[url] = 160 * 1024 * 1024
    elif any(k in fn for k in ["obs-studio", "electron", "pear-desktop", "vesktop", "discord"]):
        size_map[url] = 110 * 1024 * 1024
    elif any(k in fn for k in ["inkscape", "darktable", "audacity", "lutris", "retroarch"]):
        size_map[url] = 70 * 1024 * 1024
    elif any(k in fn for k in ["mangohud", "gamemode", "gamescope", "yabridge", "easyeffects", "scx"]):
        size_map[url] = 25 * 1024 * 1024
    elif any(k in fn for k in ["kernel", "vmlinuz", "modules"]):
        size_map[url] = 120 * 1024 * 1024
    elif any(k in fn for k in ["nvidia"]):
        size_map[url] = 90 * 1024 * 1024
    else:
        size_map[url] = 15 * 1024 * 1024

with concurrent.futures.ThreadPoolExecutor(max_workers=min(len(needed), 32)) as probe_exec:
    list(probe_exec.map(probe_size, needed))

total_bytes_expected = sum(size_map.get(u, 15 * 1024 * 1024) for u, _, _, _ in needed)

is_tty = sys.stdout.isatty() or os.isatty(1) or (os.environ.get("TERM", "") not in ("", "dumb"))
try:
    term_width = os.get_terminal_size().columns
    term_height = os.get_terminal_size().lines
except Exception:
    term_width = 80
    term_height = 24

name_len = 28 if term_width < 100 else 32
bar_width = 18 if term_width < 100 else 24
max_allowed_slots = max(4, min(16, term_height - 6))
max_display_slots = min(num_workers, total_items, max_allowed_slots)

tot_sz_str = format_size(total_bytes_expected)
print(f"\033[1;36mTurbo Parallel Pre-fetch: {label} [{total_items} files • ~{tot_sz_str}]\033[0m")
sys.stdout.flush()

state_lock = threading.Lock()
available_slots = list(range(max_display_slots))
slot_data = {}
completed_queue = []
completed_bytes = 0
success_count = 0
fail_count = 0
active_part_files = {}
stop_monitor = threading.Event()
start_time = time.time()
rate_history = []
num_dynamic_lines = 0

def monitor_thread():
    global num_dynamic_lines, total_bytes_expected
    hide_cursor()
    chomp_step = 0
    last_reported_pct = -1

    while not stop_monitor.is_set():
        time.sleep(0.12)
        now = time.time()
        chomp_step = int(now / 0.35)

        with state_lock:
            cur_completed = completed_bytes
            cur_parts = list(active_part_files.keys())
            c_count = success_count + fail_count
            slots_snapshot = [(s_id, dict(d)) for s_id, d in sorted(slot_data.items())]
            new_completed = list(completed_queue)
            completed_queue.clear()

        part_bytes = 0
        for p in cur_parts:
            try:
                if os.path.exists(p):
                    part_bytes += os.path.getsize(p)
            except Exception:
                pass

        total_dl = cur_completed + part_bytes

        if total_dl > total_bytes_expected:
            total_bytes_expected = total_dl

        rate_history.append((now, total_dl))
        while rate_history and (now - rate_history[0][0] > 1.5):
            rate_history.pop(0)

        if len(rate_history) >= 2:
            dt = rate_history[-1][0] - rate_history[0][0]
            db = rate_history[-1][1] - rate_history[0][1]
            speed_bps = max(0.0, db / dt) if dt > 0.05 else 0.0
        else:
            speed_bps = 0.0

        if total_bytes_expected > 0:
            if c_count < total_items:
                pct = min(99.0, (total_dl / total_bytes_expected) * 100.0)
            else:
                pct = 100.0
        else:
            pct = min(100.0, (c_count / total_items) * 100.0)

        rem_bytes = max(0, total_bytes_expected - total_dl)
        eta_sec = (rem_bytes / speed_bps) if speed_bps > 1024 else 0

        if is_tty:
            out_buf = []
            if num_dynamic_lines > 0:
                out_buf.append(f"\r\033[{num_dynamic_lines}A")

            # 1. Permanently commit completed lines to terminal
            for comp_fn, comp_sz, comp_spd in new_completed:
                comp_fn_disp = comp_fn[:name_len-3] + "..." if len(comp_fn) > name_len else comp_fn
                comp_sz_str = format_size(comp_sz)
                comp_spd_str = format_speed(comp_spd)
                comp_bar = f"[{'-' * bar_width}] 100%"
                out_buf.append(f"\r\033[2K{comp_fn_disp:<{name_len}s} {comp_sz_str:>10} {comp_spd_str:>11}  00:00 {comp_bar}\n")

            # 2. Render active dynamic slots
            dynamic_lines = []
            for s_id, s_info in slots_snapshot:
                fn = s_info['filename']
                fn_disp = fn[:name_len-3] + "..." if len(fn) > name_len else fn
                exp_sz = s_info['exp_sz']
                p_file = s_info['part_file']
                cur_sz = 0
                try:
                    if os.path.exists(p_file):
                        cur_sz = os.path.getsize(p_file)
                except Exception:
                    pass

                s_pct = (cur_sz / exp_sz * 100.0) if exp_sz > 0 else 50.0
                s_hist = s_info.get('history', [])
                s_hist.append((now, cur_sz))
                while s_hist and (now - s_hist[0][0] > 1.2):
                    s_hist.pop(0)
                s_info['history'] = s_hist

                if len(s_hist) >= 2:
                    s_dt = s_hist[-1][0] - s_hist[0][0]
                    s_db = s_hist[-1][1] - s_hist[0][1]
                    s_spd_bps = max(0.0, s_db / s_dt) if s_dt > 0.05 else 0.0
                else:
                    s_spd_bps = 0.0

                s_spd_str = format_speed(s_spd_bps)
                rem_s_bytes = max(0, exp_sz - cur_sz)
                if s_spd_bps > 1024 and rem_s_bytes > 0:
                    s_eta_sec = int(rem_s_bytes / s_spd_bps)
                    s_eta = f"{s_eta_sec // 60:02d}:{s_eta_sec % 60:02d}"
                else:
                    s_eta = "00:00" if s_pct >= 99.0 else "--:--"

                s_sz_str = format_size(cur_sz if cur_sz > exp_sz else exp_sz)
                s_bar = render_pacman_bar(s_pct, width=bar_width, chomp_state=chomp_step + s_id)
                dynamic_lines.append(f"{fn_disp:<{name_len}s} {s_sz_str:>10} {s_spd_str:>11} {s_eta:>5} {s_bar}")

            # 3. Render Total line
            tot_bar = render_pacman_bar(pct, width=bar_width, chomp_state=chomp_step)
            tot_sz_str = format_size(total_bytes_expected)
            tot_spd_str = format_speed(speed_bps)
            tot_eta_str = format_eta(eta_sec)
            tot_label = f"Total ({c_count}/{total_items})"
            dynamic_lines.append(f"{tot_label:<{name_len}s} {tot_sz_str:>10} {tot_spd_str:>11} {tot_eta_str:>5} {tot_bar}")

            for d_line in dynamic_lines:
                out_buf.append(f"\r\033[2K{d_line}\n")

            out_buf.append("\033[J")
            sys.stdout.write("".join(out_buf))
            sys.stdout.flush()
            num_dynamic_lines = len(dynamic_lines)
        else:
            int_pct = int(pct)
            if int_pct >= last_reported_pct + 25:
                last_reported_pct = (int_pct // 25) * 25
                tot_sz_str = format_size(total_bytes_expected)
                tot_spd_str = format_speed(speed_bps)
                tot_eta_str = format_eta(eta_sec)
                print(f"Total ({c_count}/{total_items}) {tot_sz_str:>10} {tot_spd_str:>11} {tot_eta_str:>5} ({int_pct}%)")
                sys.stdout.flush()

def download_item_wrapper(args):
    idx, item = args
    url, dest, sig_url, sig_dest = item
    dest_dir = os.path.dirname(dest)
    if dest_dir:
        os.makedirs(dest_dir, exist_ok=True)
    part_file = f"{dest}.part.{idx}"
    part_sig = f"{sig_dest}.part.{idx}" if sig_dest else ""
    exp_sz = size_map.get(url, 15 * 1024 * 1024)
    fn = os.path.basename(dest)
    item_start_time = time.time()

    slot_id = -1
    while slot_id == -1 and not stop_monitor.is_set():
        with state_lock:
            if available_slots:
                slot_id = available_slots.pop(0)
                slot_data[slot_id] = {
                    'item_idx': idx + 1,
                    'url': url,
                    'filename': fn,
                    'exp_sz': exp_sz,
                    'part_file': part_file,
                    'start_time': item_start_time,
                    'history': []
                }
                active_part_files[part_file] = True
        if slot_id == -1:
            time.sleep(0.05)

    global completed_bytes, success_count, fail_count
    try:
        curl_args = ["curl", "-sSL", "-f", "-w", "%{http_code}", "--connect-timeout", "15", "-m", "1800", "--speed-time", "45", "--speed-limit", "1000"]

        def fetch_part(u):
            """(ok, mirror_trouble). A 4xx (file not on this mirror yet) moves on without blaming the mirror."""
            res = subprocess.run(curl_args + ["-C", "-", "-o", part_file, u], capture_output=True)
            if res.returncode != 0:
                if os.path.exists(part_file):
                    try: os.remove(part_file)
                    except Exception: pass
                res = subprocess.run(curl_args + ["-o", part_file, u], capture_output=True)
            if res.returncode == 0 and os.path.exists(part_file) and os.path.getsize(part_file) > 0:
                # a package from a known repo family must be a zstd file; an error page from a broken mirror is not
                if _sm is not None and u.endswith(".pkg.tar.zst") and _sm.locate(u):
                    with open(part_file, "rb") as pf:
                        if pf.read(4) != b"\x28\xb5\x2f\xfd":
                            try: os.remove(part_file)
                            except Exception: pass
                            return False, True
                return True, False
            code = (res.stdout or b"").decode("ascii", "ignore").strip()[-3:]
            return False, not (res.returncode == 22 and code.startswith("4"))

        # fastest known mirror of the repo first, the next ones when it fails (bounded); only the host changes, the
        # signature check by the caller is the same for every mirror, and a bad signature is never retried elsewhere
        tries = _sm.alternatives(url) if _sm is not None else [url]
        served = None
        for cand in tries:
            ok, trouble = fetch_part(cand)
            if ok:
                served = cand
                if _sm is not None:
                    _sm.note_success(cand)   # 6A-201: clears the failure streak in the mirror health history
                break
            if os.path.exists(part_file):
                try: os.remove(part_file)
                except Exception: pass
            if trouble and _sm is not None:
                _sm.note_failure(cand)
        if served is None and _sm is not None and len(tries) > 1:
            sentence = _sm.all_failed_sentence(url)
            if sentence:
                with state_lock:
                    failed_sentences.add(sentence)
        if served is not None:
            if sig_url and sig_dest and sig_url == url + ".sig":
                sig_url = served + ".sig"  # the signature from the mirror that served the file
            if sig_url and sig_dest:
                curl_sig = ["curl", "-sSL", "-f", "--connect-timeout", "15", "-m", "120", "--speed-time", "45", "--speed-limit", "1000"]
                res_sig = subprocess.run(curl_sig + ["-o", part_sig, sig_url], capture_output=True)
                if res_sig.returncode != 0 and os.path.exists(part_sig):
                    try: os.remove(part_sig)
                    except Exception: pass
                    res_sig = subprocess.run(curl_sig + ["-o", part_sig, sig_url], capture_output=True)
                if res_sig.returncode == 0 and os.path.exists(part_sig) and os.path.getsize(part_sig) > 0:
                    os.replace(part_sig, sig_dest)
                else:
                    if os.path.exists(part_sig):
                        try: os.remove(part_sig)
                        except Exception: pass
            actual_sz = os.path.getsize(part_file)
            os.replace(part_file, dest)
            duration = max(0.05, time.time() - item_start_time)
            avg_item_speed = actual_sz / duration
            with state_lock:
                completed_bytes += actual_sz
                success_count += 1
                completed_queue.append((fn, actual_sz, avg_item_speed))
            return
    except Exception:
        pass
    finally:
        with state_lock:
            active_part_files.pop(part_file, None)
            if slot_id != -1:
                slot_data.pop(slot_id, None)
                if slot_id not in available_slots:
                    available_slots.append(slot_id)
                    available_slots.sort()

    with state_lock:
        fail_count += 1

mon = threading.Thread(target=monitor_thread, daemon=True)
mon.start()

item_args = [(i, needed[i]) for i in range(len(needed))]
with concurrent.futures.ThreadPoolExecutor(max_workers=num_workers) as executor:
    list(executor.map(download_item_wrapper, item_args))

stop_monitor.set()
mon.join(timeout=1.0)

total_elapsed = max(time.time() - start_time, 0.1)
avg_speed_bps = completed_bytes / total_elapsed
avg_speed_mb = (completed_bytes / (1024 * 1024)) / total_elapsed

if is_tty:
    out_buf = []
    if num_dynamic_lines > 0:
        out_buf.append(f"\r\033[{num_dynamic_lines}A")
    with state_lock:
        rem_completed = list(completed_queue)
        completed_queue.clear()
    for comp_fn, comp_sz, comp_spd in rem_completed:
        comp_fn_disp = comp_fn[:name_len-3] + "..." if len(comp_fn) > name_len else comp_fn
        comp_sz_str = format_size(comp_sz)
        comp_spd_str = format_speed(comp_spd)
        comp_bar = f"[{'-' * bar_width}] 100%"
        out_buf.append(f"\r\033[2K{comp_fn_disp:<{name_len}s} {comp_sz_str:>10} {comp_spd_str:>11}  00:00 {comp_bar}\n")

    tot_label = f"Total ({success_count}/{total_items})"
    tot_sz_str = format_size(completed_bytes)
    tot_spd_str = format_speed(avg_speed_bps)
    tot_eta_str = "00:00"
    tot_bar = render_pacman_bar(100.0, width=bar_width, chomp_state=0)
    out_buf.append(f"\r\033[2K{tot_label:<{name_len}s} {tot_sz_str:>10} {tot_spd_str:>11} {tot_eta_str:>5} {tot_bar}\n")
    out_buf.append("\033[J")
    sys.stdout.write("".join(out_buf))
    sys.stdout.flush()
    num_dynamic_lines = 0

show_cursor()

for _sentence in sorted(failed_sentences):
    print(_sentence)
if fail_count > 0:
    print(f"\033[1;33mTurbo Parallel Pre-fetch finished: {success_count}/{total_items} files ({format_size(completed_bytes)}) cached in {int(total_elapsed)}s ({fail_count} failed).\033[0m\n")
    sys.exit(1)
else:
    print(f"\033[1;32mTurbo Parallel Pre-fetch completed: {success_count} files ({format_size(completed_bytes)}) cached in {int(total_elapsed)}s (avg {avg_speed_mb:.1f} MB/s).\033[0m\n")
    sys.exit(0)
PYPACMAN
}
