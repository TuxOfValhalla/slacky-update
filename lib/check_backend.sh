#!/usr/bin/env bash
# --- [ PARALLEL BACKGROUND STATUS WORKER ] ---

set -euo pipefail

STATUS_DIR="/var/cache/slacky-update"
STATUS_FILE="${STATUS_DIR}/status.json"
mkdir -p "${STATUS_DIR}" 2>/dev/null || true
chmod 777 "${STATUS_DIR}" 2>/dev/null || true

TMP_DIR=$(mktemp -d /tmp/slacky-update-check.XXXXXX)
trap 'rm -rf "${TMP_DIR}"' EXIT

touch "${TMP_DIR}/slackware_updates"
touch "${TMP_DIR}/flatpak_updates"
touch "${TMP_DIR}/sbo_updates"
touch "${TMP_DIR}/cachy_updates"
touch "${TMP_DIR}/nvidia_updates"
touch "${TMP_DIR}/slackware_status"
touch "${TMP_DIR}/flatpak_status"
touch "${TMP_DIR}/sbo_status"
touch "${TMP_DIR}/cachy_status"

# --- [ 1. SLACKWARE REPOSITORY INSPECTION (UNPRIVILEGED) ] ---
(
    MIRROR_URL=""
    if [ -f "/etc/slackpkg/mirrors" ]; then
        MIRROR_URL=$(grep -E '^[[:space:]]*(https?|ftp)://' /etc/slackpkg/mirrors 2>/dev/null | sed -e 's/^[[:space:]]*//' | head -n1 || true)
    fi

    CHANGELOG_FETCHED=0
    if [ -n "${MIRROR_URL}" ]; then
        CHANGELOG_URL="${MIRROR_URL%/}/ChangeLog.txt"
        if curl -sSL -m 20 "${CHANGELOG_URL}" -o "${TMP_DIR}/ChangeLog.txt" 2>/dev/null && [ -s "${TMP_DIR}/ChangeLog.txt" ]; then
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
    clean = re.sub(r'\.(t[xg]z|tlz)$', '', filename)
    parts = clean.split('-')
    if len(parts) >= 4:
        base_name = "-".join(parts[:-3])
        version = parts[-3]
        arch = parts[-2]
        build = parts[-1]
        return base_name, version, build, clean
    return clean, "0", "0", clean

installed_map = {}
for p in installed_pkgs:
    bname, ver, bld, full = parse_pkg_details(p)
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
            bname, ver, bld, full = parse_pkg_details(pkg_file)
            
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
        if current["full"] != target["full"]:
            pending_updates.append(target["full_entry"])

for item in sorted(pending_updates):
    print(item)
PYSLACK
        echo "SUCCESS" > "${TMP_DIR}/slackware_status"
    else
        echo "FAILED" > "${TMP_DIR}/slackware_status"
    fi
) &

# --- [ 2. FLATPAK REPOSITORY INSPECTION ] ---
(
    if command -v flatpak >/dev/null 2>&1; then
        if raw_fp=$(timeout 30s flatpak remote-ls --updates --columns=name,branch,ref 2>/dev/null); then
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
        if raw_sbo=$(timeout 30s sbocheck -n -o --nocolor 2>/dev/null); then
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
    source "${APP_DIR}/mod_kernel.sh" 2>/dev/null || true

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
                        local flv_name="linux-cachyos"
                        [ "${flv}" = "bore" ] && flv_name="linux-cachyos-bore"
                        [ "${flv}" = "lto" ] && flv_name="linux-cachyos-bore-lto"
                        CACHY_UPDATES+=("${flv_name}-${latest_flv_ver} (Installed: ${cur_flv_ver})")
                    fi
                fi
            done
            printf "%s\n" "${CACHY_UPDATES[@]:-}" > "${TMP_DIR}/cachy_updates"
            echo "SUCCESS" > "${TMP_DIR}/cachy_status"
        fi
    fi
}
check_cachyos_background &

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
import sys, os, json, time
from datetime import datetime, timezone

tmp_dir = sys.argv[1]
status_file = sys.argv[2]
sb_state = sys.argv[3] if len(sys.argv) > 3 else "disabled"

existing_data = {}
if os.path.exists(status_file):
    try:
        with open(status_file, "r", encoding="utf-8") as f:
            existing_data = json.load(f)
    except Exception:
        existing_data = {}

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
flatpak_updates = get_persisted_list("flatpak_updates", "flatpak_status", "flatpak_updates")
sbo_updates = get_persisted_list("sbo_updates", "sbo_status", "sbo_updates")
cachy_updates = get_persisted_list("cachy_updates", "cachy_status", "cachyos_kernel_updates")
nvidia_updates = read_file_lines("nvidia_updates")
nvidia_mismatch = read_file_content("nvidia_mismatch", "false").lower() == "true"
nvidia_active_ver = read_file_content("nvidia_active_ver", "")

now_dt = datetime.now(timezone.utc)

data = {
    "slackware_updates": slackware_updates,
    "flatpak_updates": flatpak_updates,
    "sbo_updates": sbo_updates,
    "cachyos_kernel_updates": cachy_updates,
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

tmp_file = status_file + ".tmp"
try:
    os.makedirs(os.path.dirname(status_file), exist_ok=True)
    with open(tmp_file, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp_file, status_file)
    os.chmod(status_file, 0o666)
except Exception:
    pass
PYJSON
