#!/usr/bin/env bash
# --- [ PARALLEL BACKGROUND STATUS WORKER ] ---

set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
if [ -f "${SCRIPT_DIR}/common.sh" ]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/common.sh"
elif [ -f "/usr/share/slacky-update/lib/common.sh" ]; then
    # shellcheck source=/dev/null
    source "/usr/share/slacky-update/lib/common.sh"
fi

USER_CACHE_DIR="${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/slacky-update"
mkdir -p "${USER_CACHE_DIR}" 2>/dev/null || true
STATUS_FILE="${USER_CACHE_DIR}/status.json"

TMP_DIR=$(mktemp -d /tmp/slacky-update-check.XXXXXX)
trap 'rm -rf "${TMP_DIR}"' EXIT

touch "${TMP_DIR}/slackware_updates"
touch "${TMP_DIR}/slackpkgplus_updates"
touch "${TMP_DIR}/flatpak_updates"
touch "${TMP_DIR}/sbo_updates"
touch "${TMP_DIR}/cachy_updates"
touch "${TMP_DIR}/gaming_updates"
touch "${TMP_DIR}/nvidia_updates"
touch "${TMP_DIR}/slackware_status"
touch "${TMP_DIR}/slackpkgplus_status"
touch "${TMP_DIR}/flatpak_status"
touch "${TMP_DIR}/sbo_status"
touch "${TMP_DIR}/cachy_status"
touch "${TMP_DIR}/gaming_status"

# --- [ 1. SLACKWARE REPOSITORY INSPECTION (UNPRIVILEGED) ] ---
(
    MIRROR_URL=""
    if [ -f "/etc/slackpkg/mirrors" ]; then
        MIRROR_URL=$(grep -E '^[[:space:]]*(https?|ftp)://' /etc/slackpkg/mirrors 2>/dev/null | sed -e 's/^[[:space:]]*//' | head -n1 || true)
    fi

    CHANGELOG_FETCHED=0
    if [ -n "${MIRROR_URL}" ]; then
        CHANGELOG_URL="${MIRROR_URL%/}/ChangeLog.txt"
        # Super-fast check: fetch top 16KB header from upstream
        if curl -sSL -m 8 -r 0-16384 "${CHANGELOG_URL}" -o "${TMP_DIR}/ChangeLog_head.txt" 2>/dev/null && [ -s "${TMP_DIR}/ChangeLog_head.txt" ]; then
            UPSTREAM_TOP_DATE=$(grep -E '^[A-Za-z]{3}\s+[A-Za-z]{3}\s+[0-9\s]{2}\s+[0-9:]+\s+[A-Z]+\s+[0-9]{4}' "${TMP_DIR}/ChangeLog_head.txt" 2>/dev/null | head -n1 || true)
            LOCAL_TOP_DATE=""
            if [ -f "/var/lib/slackpkg/ChangeLog.txt" ]; then
                LOCAL_TOP_DATE=$(grep -E '^[A-Za-z]{3}\s+[A-Za-z]{3}\s+[0-9\s]{2}\s+[0-9:]+\s+[A-Z]+\s+[0-9]{4}' "/var/lib/slackpkg/ChangeLog.txt" 2>/dev/null | head -n1 || true)
            fi

            if [ -n "${UPSTREAM_TOP_DATE}" ] && [ "${UPSTREAM_TOP_DATE}" = "${LOCAL_TOP_DATE}" ] && [ -f "/var/lib/slackpkg/ChangeLog.txt" ]; then
                cp -f "/var/lib/slackpkg/ChangeLog.txt" "${TMP_DIR}/ChangeLog.txt" 2>/dev/null || true
                [ -s "${TMP_DIR}/ChangeLog.txt" ] && CHANGELOG_FETCHED=1
            else
                if curl -sSL -m 20 "${CHANGELOG_URL}" -o "${TMP_DIR}/ChangeLog.txt" 2>/dev/null && [ -s "${TMP_DIR}/ChangeLog.txt" ]; then
                    CHANGELOG_FETCHED=1
                else
                    cp -f "${TMP_DIR}/ChangeLog_head.txt" "${TMP_DIR}/ChangeLog.txt" 2>/dev/null || true
                    [ -s "${TMP_DIR}/ChangeLog.txt" ] && CHANGELOG_FETCHED=1
                fi
            fi
        elif curl -sSL -m 20 "${CHANGELOG_URL}" -o "${TMP_DIR}/ChangeLog.txt" 2>/dev/null && [ -s "${TMP_DIR}/ChangeLog.txt" ]; then
            CHANGELOG_FETCHED=1
        fi
    fi

    if [ "${CHANGELOG_FETCHED}" -eq 0 ] && [ -f "/var/lib/slackpkg/ChangeLog.txt" ]; then
        cp -f "/var/lib/slackpkg/ChangeLog.txt" "${TMP_DIR}/ChangeLog.txt" 2>/dev/null || true
        [ -s "${TMP_DIR}/ChangeLog.txt" ] && CHANGELOG_FETCHED=1
    fi

    if [ "${CHANGELOG_FETCHED}" -eq 1 ] && [ -s "${TMP_DIR}/ChangeLog.txt" ]; then
        python3 - "${TMP_DIR}/ChangeLog.txt" > "${TMP_DIR}/slackware_updates" << 'PYSLACK'
import os, sys, re

changelog_path = sys.argv[1]
pkg_log_dir = "/var/log/packages"

installed_pkgs = set(os.listdir(pkg_log_dir)) if os.path.exists(pkg_log_dir) else set()

def parse_pkg_details(filename):
    clean = re.sub(r'\.(t[xg]z|tlz|tbz)$', '', filename)
    parts = clean.split('-')
    if len(parts) >= 4:
        base_name = "-".join(parts[:-3])
        version = parts[-3]
        arch = parts[-2]
        build = parts[-1]
        return base_name, version, arch, build, clean
    return clean, "0", "0", "0", clean

def split_numeric(s):
    tokens = re.split(r'(\d+)', str(s))
    res = []
    for t in tokens:
        if not t:
            continue
        if t.isdigit():
            res.append(int(t))
        else:
            res.append(t)
    return res

def is_strictly_newer(installed_full, upstream_full):
    if installed_full == upstream_full:
        return False
    _, i_ver, _, i_bld, _ = parse_pkg_details(installed_full)
    _, u_ver, _, u_bld, _ = parse_pkg_details(upstream_full)
    i_v = split_numeric(i_ver)
    u_v = split_numeric(u_ver)
    if u_v != i_v:
        return u_v > i_v
    i_b = split_numeric(i_bld)
    u_b = split_numeric(u_bld)
    return u_b > i_b

installed_map = {}
for p in installed_pkgs:
    bname, ver, arch, bld, full = parse_pkg_details(p)
    installed_map[bname] = {"version": ver, "build": bld, "full": full}

latest_changelog_pkgs = {}
date_pattern = re.compile(r'^[A-Za-z]{3}\s+[A-Za-z]{3}\s+[0-9\s]{2}\s+[0-9:]+\s+[A-Z]+\s+[0-9]{4}')
entry_pattern = re.compile(r'^((?:[a-zA-Z0-9_\-+]+/)+[a-zA-Z0-9_\-+.]+-(?:x86_64|i[3-6]86|noarch|arm)-[0-9a-zA-Z_]+\.(?:t[xg]z|tlz)):\s+(Added|Upgraded|Rebuilt)')

if os.path.exists(changelog_path):
    with open(changelog_path, "r", encoding="utf-8", errors="ignore") as f:
        lines = f.readlines()

    header_count = 0
    max_headers = 50

    for line in lines:
        if date_pattern.match(line):
            header_count += 1
            if header_count > max_headers:
                break

        match = entry_pattern.match(line)
        if match:
            full_entry = match.group(1)
            # Filter out non-standard / masked distribution directories (testing, pasture, source, extra)
            if full_entry.startswith(("testing/", "pasture/", "source/", "extra/")):
                continue
            pkg_file = os.path.basename(full_entry)
            bname, ver, arch, bld, full = parse_pkg_details(pkg_file)
            
            if bname not in latest_changelog_pkgs:
                latest_changelog_pkgs[bname] = {
                    "full_entry": full_entry,
                    "version": ver,
                    "build": bld,
                    "full": full
                }

pending_updates = []
for bname, target in latest_changelog_pkgs.items():
    if bname in installed_map:
        current = installed_map[bname]
        if is_strictly_newer(current["full"], target["full"]):
            pending_updates.append(target["full_entry"])

for item in sorted(pending_updates):
    print(item)
PYSLACK
        echo "SUCCESS" > "${TMP_DIR}/slackware_status"
    else
        echo "FAILED" > "${TMP_DIR}/slackware_status"
    fi
) &

# --- [ 1.5. SLACKPKGPLUS & MULTILIB REPOSITORY INSPECTION (UNPRIVILEGED) ] ---
(
    python3 > "${TMP_DIR}/slackpkgplus_updates" << 'PYPLUS'
import os, sys, re

pkg_log_dir = "/var/log/packages"
installed = {}
if os.path.exists(pkg_log_dir):
    for f in os.listdir(pkg_log_dir):
        parts = f.rsplit('-', 3)
        if len(parts) == 4:
            installed[parts[0]] = f

def parse_pkg_details(filename):
    clean = re.sub(r'\.(t[xg]z|tlz|tbz)$', '', filename)
    parts = clean.split('-')
    if len(parts) >= 4:
        base_name = "-".join(parts[:-3])
        version = parts[-3]
        arch = parts[-2]
        build = parts[-1]
        return base_name, version, arch, build, clean
    return clean, "0", "0", "0", clean

def split_numeric(s):
    tokens = re.split(r'(\d+)', str(s))
    res = []
    for t in tokens:
        if not t:
            continue
        if t.isdigit():
            res.append(int(t))
        else:
            res.append(t)
    return res

def is_strictly_newer(installed_full, upstream_full):
    if installed_full == upstream_full:
        return False
    _, i_ver, _, i_bld, _ = parse_pkg_details(installed_full)
    _, u_ver, _, u_bld, _ = parse_pkg_details(upstream_full)
    i_v = split_numeric(i_ver)
    u_v = split_numeric(u_ver)
    if u_v != i_v:
        return u_v > i_v
    i_b = split_numeric(i_bld)
    u_b = split_numeric(u_bld)
    return u_b > i_b

allowed_repos = set()
mirror_map = {}
conf_path = "/etc/slackpkg/slackpkgplus.conf"
if os.path.exists(conf_path):
    try:
        with open(conf_path, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
            for line in content.splitlines():
                sline = line.strip()
                if sline.startswith("MIRRORPLUS[") and "=" in sline:
                    repo_key = sline.split("[", 1)[1].split("]", 1)[0].strip("'\"")
                    repo_url = sline.split("=", 1)[1].strip().strip("'\"").rstrip("/")
                    if repo_key and repo_url:
                        mirror_map[repo_key] = repo_url
                        allowed_repos.add(repo_key)
            match = re.search(r'REPOPLUS=\(\s*([^)]+)\s*\)', content, re.DOTALL)
            if match:
                for r in match.group(1).split():
                    allowed_repos.add(r.strip())
    except Exception:
        pass

updates = []
pkglist_path = "/var/lib/slackpkg/pkglist"
if os.path.exists(pkglist_path):
    try:
        with open(pkglist_path, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) >= 7:
                    ext = parts[-1]
                    relpath = parts[-2]
                    fullname = parts[-3]
                    name = parts[-7]
                    raw_repo = parts[0] if len(parts) >= 8 else ""
                    clean_repo = raw_repo.replace("SLACKPKGPLUS_", "")
                    if clean_repo in allowed_repos or raw_repo in allowed_repos or (raw_repo.startswith("SLACKPKGPLUS_") and not raw_repo.startswith("slackware")):
                        if name in installed and is_strictly_newer(installed[name], fullname):
                            updates.append(f"{fullname}.{ext}")
    except Exception:
        pass

for u in sorted(updates):
    print(u)
PYPLUS
    echo "SUCCESS" > "${TMP_DIR}/slackpkgplus_status"
) &

# --- [ 2. FLATPAK REPOSITORY INSPECTION ] ---
(
    if command -v flatpak >/dev/null 2>&1; then
        if raw_fp=$(timeout 10s flatpak remote-ls --updates --columns=name,branch,ref 2>/dev/null); then
            echo "${raw_fp}" | awk -F'\t' '{if ($1 != "") print $1 " [" $2 "]"; else if ($3 != "") print $3}' > "${TMP_DIR}/flatpak_updates"
            echo "SUCCESS" > "${TMP_DIR}/flatpak_status"
        else
            echo "FAILED" > "${TMP_DIR}/flatpak_status"
        fi
    fi
) &

# --- [ 2.5. SBOTOOLS REPOSITORY INSPECTION ] ---
(
    if command -v sbocheck >/dev/null 2>&1; then
        # Auto-fetch fresh SBo tree if snapshot is >= 7 days old
        if [ -d "/var/lib/sbotools/repo" ]; then
            repo_mtime=$(stat -c %Y /var/lib/sbotools/repo 2>/dev/null || echo 0)
            now_ts=$(date +%s)
            diff_days=$(( (now_ts - repo_mtime) / 86400 ))
            if [ "${diff_days}" -ge 7 ]; then
                if [ "$(id -u)" -eq 0 ]; then
                    timeout 60s sbosnap fetch >/dev/null 2>&1 || true
                    touch /var/lib/sbotools/repo 2>/dev/null || true
                elif sudo -n true 2>/dev/null; then
                    sudo -n timeout 60s sbosnap fetch >/dev/null 2>&1 || true
                    sudo -n touch /var/lib/sbotools/repo 2>/dev/null || true
                fi
            fi
        fi

        if raw_sbo=$(timeout 20s sbocheck -n -o --nocolor 2>/dev/null); then
            echo "${raw_sbo}" | (grep -i "needs updating" || true) | awk '{print $1 " (" $2 " -> " substr($6, 2) ")"}' > "${TMP_DIR}/sbo_updates"
            echo "SUCCESS" > "${TMP_DIR}/sbo_status"
        else
            echo "FAILED" > "${TMP_DIR}/sbo_status"
        fi
    else
        echo "SUCCESS" > "${TMP_DIR}/sbo_status"
    fi
) &

# --- [ 3. CACHYOS KERNEL UPSTREAM CHECK ] ---
check_cachyos_background() {
    CACHY_UPDATES=()
    ACTIVE_KVER=$(uname -r)
    
    LIB_DIR="$(dirname "$(readlink -f "$0")")"
    if [ -f "${LIB_DIR}/mod_kernel.sh" ]; then
        APP_DIR="${LIB_DIR}"
    elif [ -d "/usr/share/slacky-update" ] && [ -f "/usr/share/slacky-update/mod_kernel.sh" ]; then
        APP_DIR="/usr/share/slacky-update"
    elif [ -d "/usr/local/share/slacky-update" ] && [ -f "/usr/local/share/slacky-update/mod_kernel.sh" ]; then
        APP_DIR="/usr/local/share/slacky-update"
    elif [ -d "/usr/local/lib/slacky-update" ] && [ -f "/usr/local/lib/slacky-update/mod_kernel.sh" ]; then
        APP_DIR="/usr/local/lib/slacky-update"
    elif [ -d "/usr/lib64/slacky-update" ] && [ -f "/usr/lib64/slacky-update/mod_kernel.sh" ]; then
        APP_DIR="/usr/lib64/slacky-update"
    elif [ -d "/usr/lib/slacky-update" ] && [ -f "/usr/lib/slacky-update/mod_kernel.sh" ]; then
        APP_DIR="/usr/lib/slacky-update"
    else
        APP_DIR="${LIB_DIR}"
    fi
    # shellcheck source=/dev/null
    [ -f "${APP_DIR}/common.sh" ] && source "${APP_DIR}/common.sh" 2>/dev/null || true
    # shellcheck source=/dev/null
    [ -f "${APP_DIR}/mod_kernel.sh" ] && source "${APP_DIR}/mod_kernel.sh" 2>/dev/null || true

    if command -v get_installed_cachyos_flavors >/dev/null 2>&1; then
        local installed_flavors
        installed_flavors=$(get_installed_cachyos_flavors 2>/dev/null || echo "")

        if [ -n "${installed_flavors}" ]; then
            for flv in ${installed_flavors}; do
                local cur_flv_ver latest_flv_ver k_url h_url nv_url
                cur_flv_ver=$(get_installed_cachyos_flavor_version "${flv}" 2>/dev/null || echo "NONE")
                read -r latest_flv_ver k_url h_url nv_url <<< "$(check_cachyos_upstream_flavor "${flv}" || echo "NONE NONE NONE NONE")"

                if [ "${latest_flv_ver}" != "NONE" ] && [ -n "${latest_flv_ver}" ] && [ "${cur_flv_ver}" != "NONE" ]; then
                    local is_flv_newer
                    is_flv_newer=$(compare_versions_strictly_greater "${latest_flv_ver}" "${cur_flv_ver}" 2>/dev/null || echo "false")
                    if [ "${is_flv_newer}" = "true" ]; then
                        # On modern NVIDIA systems, verify either precompiled module or DKMS toolchain is available
                        local nv_ready=1
                        if [ "${HAS_NVIDIA:-false}" = "true" ]; then
                            local gpu_arch="MODERN"
                            if command -v detect_nvidia_gpu >/dev/null 2>&1; then
                                gpu_arch=$(detect_nvidia_gpu)
                            fi
                            if [ "${gpu_arch}" = "MODERN" ]; then
                                if [ "${nv_url}" = "NONE" ] && ! command -v dkms >/dev/null 2>&1; then
                                    nv_ready=0
                                fi
                            fi
                        fi

                        if [ "${nv_ready}" -eq 1 ]; then
                            local flv_name="linux-cachyos"
                            [ "${flv}" = "bore" ] && flv_name="linux-cachyos-bore"
                            [ "${flv}" = "lto" ] && flv_name="linux-cachyos-bore-lto"
                            [ "${flv}" = "rc" ] && flv_name="linux-cachyos-rc"
                            [ "${flv}" = "lts" ] && flv_name="linux-cachyos-lts"
                            CACHY_UPDATES+=("${flv_name}-${latest_flv_ver} (Installed: ${cur_flv_ver})")
                        fi
                    fi
                fi
            done
            printf "%s\n" "${CACHY_UPDATES[@]:-}" > "${TMP_DIR}/cachy_updates"
            echo "SUCCESS" > "${TMP_DIR}/cachy_status"
        fi
    fi
}
check_cachyos_background &

# --- [ 3.5. CACHYOS GAMING SUITE UPDATE CHECK ] ---
check_cachyos_gaming_background() {
    local GAMING_UPDATES=()
    local LIB_DIR
    LIB_DIR="$(dirname "$(readlink -f "$0")")"
    if [ -f "${LIB_DIR}/mod_gaming.sh" ]; then
        source "${LIB_DIR}/mod_gaming.sh" 2>/dev/null || true
    elif [ -f "/usr/share/slacky-update/lib/mod_gaming.sh" ]; then
        source "/usr/share/slacky-update/lib/mod_gaming.sh" 2>/dev/null || true
    fi

    if command -v check_all_installed_gaming_updates_fast >/dev/null 2>&1; then
        check_all_installed_gaming_updates_fast > "${TMP_DIR}/gaming_updates" 2>/dev/null || true
        echo "SUCCESS" > "${TMP_DIR}/gaming_status"
    elif command -v get_gaming_catalog >/dev/null 2>&1; then
        while IFS='|' read -r pkg_id name cat main_pat l32_pat ext_pat repos; do
            [ -n "${pkg_id}" ] || continue
            local cur_ver
            cur_ver=$(get_installed_gaming_pkg_version "${pkg_id}" 2>/dev/null || echo "NONE")
            [ "${cur_ver}" != "NONE" ] || continue

            local latest_ver main_u l32_u ext_u
            read -r latest_ver main_u l32_u ext_u <<< "$(resolve_cachyos_gaming_upstream_metadata "${pkg_id}" 2>/dev/null || echo "NONE NONE NONE NONE")"
            if [ "${latest_ver}" != "NONE" ] && [ -n "${latest_ver}" ]; then
                local is_newer
                is_newer=$(compare_versions_strictly_greater "${latest_ver}" "${cur_ver}" 2>/dev/null || echo "false")
                if [ "${is_newer}" = "true" ]; then
                    GAMING_UPDATES+=("${name} ${latest_ver} (Installed: ${cur_ver})")
                fi
            fi
        done <<< "$(get_gaming_catalog 2>/dev/null || echo "")"
        printf "%s\n" "${GAMING_UPDATES[@]:-}" > "${TMP_DIR}/gaming_updates"
        echo "SUCCESS" > "${TMP_DIR}/gaming_status"
    else
        echo "SUCCESS" > "${TMP_DIR}/gaming_status"
    fi
}
check_cachyos_gaming_background &

# --- [ 4. NVIDIA HARDWARE & DRIVER CHECK ] ---
(
    NVIDIA_UPDATES=()
    NVIDIA_ACTIVE_VER=""
    NVIDIA_MISMATCH="false"

    if [ -f "/sys/module/nvidia/version" ]; then
        NVIDIA_ACTIVE_VER=$(cat /sys/module/nvidia/version 2>/dev/null | tr -d '[:space:]' || true)
    elif [ -f "/proc/driver/nvidia/version" ]; then
        NVIDIA_ACTIVE_VER=$(head -n 1 /proc/driver/nvidia/version | awk '{print $8}' 2>/dev/null || true)
    fi

    if [ -n "${NVIDIA_ACTIVE_VER}" ]; then
        HAS_CACHY_LOCAL="false"
        if ls /boot/vmlinuz*cachyos* 1>/dev/null 2>&1 || ls -d /lib/modules/*cachyos* 1>/dev/null 2>&1; then
            HAS_CACHY_LOCAL="true"
        fi

        if [ "${HAS_CACHY_LOCAL}" = "true" ]; then
            LATEST_NVIDIA=$(curl -sSL -m 10 "https://mirror.cachyos.org/repo/x86_64/cachyos/" 2>/dev/null | grep -o -E 'nvidia-utils-[0-9]+\.[0-9]+(\.[0-9]+)?' | sed 's/nvidia-utils-//' | sort -V | tail -n 1 || true)
        else
            LATEST_NVIDIA=$(curl -sSL -m 8 "https://download.nvidia.com/XFree86/Linux-x86_64/latest.txt" 2>/dev/null | awk '{print $1}' || true)
        fi

        if [ -n "${LATEST_NVIDIA}" ]; then
            IS_NEWER=$(python3 -c "
import sys, re
def p(v): return [int(x) for x in re.sub(r'[^0-9.]', '', v).split('.') if x.isdigit()]
sys.exit(0 if p('$LATEST_NVIDIA') > p('$NVIDIA_ACTIVE_VER') else 1)
" && echo "true" || echo "false")

            if [ "${IS_NEWER}" = "true" ]; then
                if [ "${HAS_CACHY_LOCAL}" = "true" ]; then
                    NVIDIA_UPDATES+=("CachyOS NVIDIA Complete Suite ${LATEST_NVIDIA} (64-bit, 32-bit Multilib, OpenCL & VA-API) [CachyOS Master Update]")
                else
                    NVIDIA_UPDATES+=("nvidia-driver-${LATEST_NVIDIA} (Installed: ${NVIDIA_ACTIVE_VER})")
                fi
            elif [ "${HAS_CACHY_LOCAL}" = "true" ]; then
                # Version matches, but user is on untracked .run user-space or missing OpenCL / VA-API
                if ! ls /var/log/packages/cachyos-nvidia-utils-* 1>/dev/null 2>&1; then
                    NVIDIA_UPDATES+=("CachyOS NVIDIA Complete Suite ${LATEST_NVIDIA} (64-bit, 32-bit Multilib, OpenCL & VA-API) [CachyOS Master Migration]")
                elif [ ! -f "/etc/OpenCL/vendors/nvidia.icd" ] || [ ! -f "/usr/lib64/dri/nvidia_drv_video.so" ]; then
                    NVIDIA_UPDATES+=("CachyOS NVIDIA Complete Suite ${LATEST_NVIDIA} (OpenCL & VA-API Hardware Acceleration) [Complete Suite Upgrade]")
                fi
            fi
        fi

        if command -v flatpak >/dev/null 2>&1; then
            MATCH_FOUND=$(python3 -c "
import subprocess, sys

active_ver = '${NVIDIA_ACTIVE_VER}'.strip()
ver_dash = active_ver.replace('.', '-')

try:
    out = subprocess.check_output(['flatpak', 'list', '--runtime'], text=True, stderr=subprocess.DEVNULL)
    for line in out.splitlines():
        if 'GL.nvidia' in line or 'nvidia' in line.lower():
            if active_ver in line or ver_dash in line:
                sys.exit(0)
except Exception:
    pass

sys.exit(1)
" && echo "true" || echo "false")

            if [ "${MATCH_FOUND}" != "true" ]; then
                NVIDIA_MISMATCH="true"
                # Non-blocking background auto-heal for active loaded kernel
                (
                    ver_clean=$(echo "${NVIDIA_ACTIVE_VER}" | tr -d '[:space:]')
                    ver_dash=$(echo "${ver_clean}" | tr '.' '-')
                    flatpak install -y --non-interactive flathub \
                        "runtime/org.freedesktop.Platform.GL.nvidia-${ver_dash}" \
                        "runtime/org.freedesktop.Platform.GL32.nvidia-${ver_dash}" >/dev/null 2>&1 || \
                    flatpak update -y --non-interactive >/dev/null 2>&1 || true
                ) &
            fi
        fi
    fi

    printf "%s\n" "${NVIDIA_UPDATES[@]:-}" > "${TMP_DIR}/nvidia_updates"
    echo "${NVIDIA_MISMATCH}" > "${TMP_DIR}/nvidia_mismatch"
    echo "${NVIDIA_ACTIVE_VER}" > "${TMP_DIR}/nvidia_active_ver"
) &

wait

# --- [ 5. SECURE BOOT STATUS ] ---
SB_STATE="disabled"
if command -v mokutil >/dev/null 2>&1; then
    if mokutil --sb-state 2>/dev/null | grep -qi "enabled"; then
        SB_STATE="enabled"
    fi
fi

# --- [ 6. CACHE SERIALIZATION & ATOMIC PERSISTENCE ] ---
python3 - "${TMP_DIR}" "${STATUS_FILE}" "${SB_STATE}" << 'PYJSON'
import sys, os, json, time, pwd
from datetime import datetime, timezone

tmp_dir = sys.argv[1]
status_file = sys.argv[2]
sb_state = sys.argv[3] if len(sys.argv) > 3 else "disabled"

# Identify candidate cache files
candidates = [status_file]
user_cache = os.path.expanduser("~/.cache/slacky-update/status.json")
if user_cache not in candidates:
    candidates.append(user_cache)

sudo_u = os.environ.get("SUDO_USER")
sudo_uid, sudo_gid, sudo_cache = None, None, None
if sudo_u and os.getuid() == 0:
    try:
        pw = pwd.getpwnam(sudo_u)
        sudo_uid, sudo_gid = pw.pw_uid, pw.pw_gid
        sudo_cache = os.path.join(pw.pw_dir, ".cache", "slacky-update", "status.json")
        if sudo_cache not in candidates:
            candidates.append(sudo_cache)
    except Exception:
        pass

if "/var/cache/slacky-update/status.json" not in candidates:
    candidates.append("/var/cache/slacky-update/status.json")

existing_data = {}
newest_ts = -1
for c in candidates:
    if os.path.exists(c):
        try:
            with open(c, "r", encoding="utf-8") as f:
                c_data = json.load(f)
                c_ts = float(c_data.get("last_check_ts", os.path.getmtime(c)))
                if c_ts > newest_ts:
                    newest_ts = c_ts
                    existing_data = c_data
        except Exception:
            pass

def read_file_lines(filename):
    filepath = os.path.join(tmp_dir, filename)
    if os.path.exists(filepath):
        try:
            with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
                return [line.strip() for line in f if line.strip()]
        except Exception:
            pass
    return []

def get_status(status_name):
    path = os.path.join(tmp_dir, status_name)
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return f.read().strip()
        except Exception:
            pass
    return "FAILED"

def get_persisted_list(filename, status_name, json_key):
    if get_status(status_name) == "SUCCESS":
        return read_file_lines(filename)
    return existing_data.get(json_key, [])

def read_file_content(filename, default=""):
    filepath = os.path.join(tmp_dir, filename)
    if os.path.exists(filepath):
        try:
            with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
                return f.read().strip()
        except Exception:
            pass
    return default

slackware_updates = get_persisted_list("slackware_updates", "slackware_status", "slackware_updates")
slackpkgplus_updates = get_persisted_list("slackpkgplus_updates", "slackpkgplus_status", "slackpkgplus_updates")
flatpak_updates = get_persisted_list("flatpak_updates", "flatpak_status", "flatpak_updates")
sbo_updates = get_persisted_list("sbo_updates", "sbo_status", "sbo_updates")
cachy_updates = get_persisted_list("cachy_updates", "cachy_status", "cachyos_kernel_updates")
gaming_updates = get_persisted_list("gaming_updates", "gaming_status", "cachyos_gaming_updates")
nvidia_updates = read_file_lines("nvidia_updates")
nvidia_mismatch = read_file_content("nvidia_mismatch", "false").lower() == "true"
nvidia_active_ver = read_file_content("nvidia_active_ver", "")

now_dt = datetime.now(timezone.utc)

data = {
    "slackware_updates": slackware_updates,
    "slackpkgplus_updates": slackpkgplus_updates,
    "flatpak_updates": flatpak_updates,
    "sbo_updates": sbo_updates,
    "cachyos_kernel_updates": cachy_updates,
    "cachyos_gaming_updates": gaming_updates,
    "nvidia_driver_updates": nvidia_updates,
    "reboot_required": False,
    "nvidia_gl_mismatch": nvidia_mismatch,
    "nvidia_driver_version": nvidia_active_ver,
    "secure_boot": {
        "state": sb_state,
        "warnings": []
    },
    "last_check": now_dt.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "last_check_ts": int(time.time())
}

def save_json_safely(target_path, uid=None, gid=None):
    try:
        os.makedirs(os.path.dirname(target_path), exist_ok=True)
        tmp = target_path + ".tmp"
        written = False
        try:
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
            if uid is not None and gid is not None:
                try:
                    os.chown(tmp, uid, gid)
                except Exception:
                    pass
            os.replace(tmp, target_path)
            if uid is not None and gid is not None:
                try:
                    os.chown(target_path, uid, gid)
                except Exception:
                    pass
            written = True
        except Exception:
            if os.path.exists(tmp):
                try:
                    os.unlink(tmp)
                except Exception:
                    pass
        
        if not written:
            with open(target_path, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
            if uid is not None and gid is not None:
                try:
                    os.chown(target_path, uid, gid)
                except Exception:
                    pass
        return True
    except Exception:
        return False

# 1. Always write to current user status_file
save_json_safely(status_file)

# 2. If root under sudo, write to SUDO_USER cache with user ownership
if sudo_cache and sudo_uid is not None and sudo_gid is not None:
    save_json_safely(sudo_cache, sudo_uid, sudo_gid)

# 3. If root, also update system cache
if os.getuid() == 0:
    save_json_safely("/var/cache/slacky-update/status.json")
PYJSON
