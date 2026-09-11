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
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
CYAN="\033[1;36m"
RESET="\033[0m"

CACHE_DIR="/var/cache/slacky-update"
LOG_FILE="/var/log/slacky-update.log"

MOK_CERT=""
MOK_CRT=""
MOK_DER=""
MOK_KEY=""

HAS_NVIDIA=false
HAS_AMD=false
HAS_INTEL=false

CURRENT_VERSION="0.11"
RELEASE_CODENAME="Underpants Gnomes hotfix"

CURL_CONNECT_TIMEOUT=15
CURL_MAX_TIME=60

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

set_terminal_title() {
    local title="${1:-slacky-update v${CURRENT_VERSION:-0.10}}"
    if [ -t 1 ] || [ -n "${TERM:-}" ]; then
        printf "\033]0;%s\007\033]2;%s\007\033]30;%s\007" "${title}" "${title}" "${title}" 2>/dev/null || true
    fi
}

get_user_staging_dir() {
    local staging_dir="${HOME:-/tmp}/.cache/slacky-update/staging"
    mkdir -p "${staging_dir}" 2>/dev/null || staging_dir="/tmp/slacky-staging-${UID:-0}"
    mkdir -p "${staging_dir}" 2>/dev/null || true
    echo "${staging_dir}"
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

verify_cachyos_gpg_signature() {
    local payload="$1"
    local sig="$2"

    [ -f "${payload}" ] || return 1
    [ -f "${sig}" ] || return 1

    local keyring
    keyring=$(resolve_cachyos_keyring)

    if [ -z "${keyring}" ] || [ ! -f "${keyring}" ]; then
        log_error "Security Error: Trusted GPG keyring (trusted-keyrings.gpg) not found! Refusing to verify unauthenticated package."
        return 1
    fi

    local gpg_bin
    gpg_bin=$(command -v gpg 2>/dev/null || echo "/usr/bin/gpg")
    if [ ! -x "${gpg_bin}" ]; then
        log_error "Security Error: GPG utility not found. Cannot verify cryptographic signature for $(basename "${payload}")."
        return 1
    fi

    local gpg_tmp
    gpg_tmp=$(mktemp -d /tmp/slacky-gpg-XXXXXX 2>/dev/null || echo "/tmp")

    local verify_res=0
    if "${gpg_bin}" --homedir "${gpg_tmp}" --no-default-keyring --keyring "${keyring}" --verify "${sig}" "${payload}" >/dev/null 2>&1; then
        verify_res=1
    fi

    [ "${gpg_tmp}" != "/tmp" ] && rm -rf "${gpg_tmp}" 2>/dev/null || true

    if [ "${verify_res}" -eq 1 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] GPG cryptographic signature verified for $(basename "${payload}")" >> "${LOG_FILE}" 2>/dev/null || true
        return 0
    else
        log_error "GPG signature verification FAILED for $(basename "${payload}")! Untrusted or corrupt package."
        return 1
    fi
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

verify_microsoft_uefi_authenticode() {
    local efi_file="$1"
    [ -f "${efi_file}" ] || return 1

    local sbverify_bin
    sbverify_bin=$(command -v sbverify 2>/dev/null || echo "/usr/bin/sbverify")
    if [ ! -x "${sbverify_bin}" ]; then
        log_error "Security Error: sbverify utility not found. Cannot verify Authenticode signature on $(basename "${efi_file}")."
        return 1
    fi

    local ca_cert
    ca_cert=$(resolve_microsoft_uefi_ca_cert)
    if [ -z "${ca_cert}" ] || [ ! -f "${ca_cert}" ]; then
        log_error "Security Error: Microsoft UEFI CA certificate (microsoft-uefi-ca-2011.crt) not located. Aborting Authenticode validation."
        return 1
    fi

    if "${sbverify_bin}" --cert "${ca_cert}" "${efi_file}" >/dev/null 2>&1; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] Microsoft 3rd Party UEFI CA signature verified for $(basename "${efi_file}")" >> "${LOG_FILE}" 2>/dev/null || true
        return 0
    else
        log_error "Microsoft UEFI CA Authenticode verification FAILED for $(basename "${efi_file}")!"
        return 1
    fi
}

log_info() {
    local msg="$1"
    echo -e "${CYAN}::${RESET} ${msg}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] ${msg}" >> "${LOG_FILE}" 2>/dev/null || true
}

log_success() {
    local msg="$1"
    echo -e "${GREEN}✓${RESET} ${msg}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] ${msg}" >> "${LOG_FILE}" 2>/dev/null || true
}

log_warn() {
    local msg="$1"
    echo -e "${YELLOW}⚠️${RESET}  ${msg}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] ${msg}" >> "${LOG_FILE}" 2>/dev/null || true
}

log_error() {
    local msg="$1"
    echo -e "${RED}✗${RESET} ${msg}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] ${msg}" >> "${LOG_FILE}" 2>/dev/null || true
}

check_slacky_update_self_update() {
    local current_ver="${1:-${CURRENT_VERSION:-0.10}}"
    local rel_json=""
    # 1. Try Codeberg API first (official mirror)
    rel_json=$(curl -sSL -m 3 -H "User-Agent: slacky-update" "https://codeberg.org/api/v1/repos/TuxOfValhalla/slacky-update/releases/latest" 2>/dev/null || true)
    # 2. Fallback to GitHub API if Codeberg is unavailable or returns invalid payload
    if [ -z "${rel_json}" ] || ! echo "${rel_json}" | grep -q '"tag_name"'; then
        rel_json=$(curl -sSL -m 3 -H "User-Agent: slacky-update" "https://api.github.com/repos/TuxOfValhalla/slacky-update/releases/latest" 2>/dev/null || true)
    fi

    local update_info
    update_info=$(echo "${rel_json}" | python3 -c "
import json, sys, re

def parse_v(v_str):
    return [int(x) for x in re.findall(r'\d+', v_str)]

cur = '${current_ver}'.lstrip('v')
try:
    content = sys.stdin.read().strip()
    if content:
        data = json.loads(content)
        tag = data.get('tag_name', '').lstrip('v')
        if tag and parse_v(tag) > parse_v(cur):
            dl_url = ''
            for asset in data.get('assets', []):
                name = asset.get('name', '')
                if name.endswith(('.txz', '.tgz')):
                    dl_url = asset.get('browser_download_url', '')
                    break
            if not dl_url:
                dl_url = data.get('tarball_url', '')
            print(f'UPDATE|{tag}|{dl_url}')
            sys.exit(0)
except Exception:
    pass
print(f'UP_TO_DATE|{cur}')
" 2>/dev/null || echo "UP_TO_DATE|${current_ver}")

    local status_type rest
    IFS='|' read -r status_type rest <<< "${update_info}"

    if [ "${status_type}" = "UPDATE" ]; then
        local new_tag dl_url
        IFS='|' read -r new_tag dl_url <<< "${rest}"

        echo ""
        echo -e "${YELLOW}${BOLD}⚡ New Slacky-Update Release Available: v${new_tag} (Current: v${current_ver})${RESET}"
        read -r -p "$(_ PROMPT_SELF_UPDATE)" reply_update
        reply_update=${reply_update:-Y}
        if [[ "$reply_update" =~ ^[YyJjSsOo]$ ]]; then
            validate_privileges
            log_info "Downloading Slacky-Update v${new_tag}..."
            local tmp_pkg="/tmp/slacky-update-${new_tag}.txz"
            if [[ "${dl_url}" =~ \.txz$|\.tgz$ ]]; then
                sudo curl -sSL -o "${tmp_pkg}" "${dl_url}"
                if [ -f "${tmp_pkg}" ] && [ -s "${tmp_pkg}" ]; then
                    sudo "${PKG_UPGRADE_CMD}" --reinstall "${tmp_pkg}"
                    sudo rm -f "${tmp_pkg}"
                    log_success "Slacky-Update upgraded to v${new_tag}!"
                    killall slacky-update-tray 2>/dev/null || pkill -f slacky-update-tray || true
                    nohup "$(command -v slacky-update-tray 2>/dev/null || echo "/usr/local/bin/slacky-update-tray")" >/dev/null 2>&1 &
                    exec "$(command -v slacky-update 2>/dev/null || echo "/usr/local/bin/slacky-update")" "$@"
                fi
            fi
        fi
    else
        echo -e "  ${GREEN}✓${RESET} ${BLUE}$(_ APP_UP_TO_DATE tag="v${current_ver}")${RESET}"
    fi
}

trigger_silent_background_refresh() {
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
        nohup "${chk_bin}" >/dev/null 2>&1 &
    fi
}

init_storage() {
    if [ ! -d "${CACHE_DIR}" ]; then
        mkdir -p "${CACHE_DIR}" 2>/dev/null || sudo mkdir -p "${CACHE_DIR}" 2>/dev/null || true
    fi
    # Set 1777 (sticky-bit world-writable like /tmp) so unprivileged check_backend / tray can update status.json
    # while preventing unprivileged users from deleting or modifying root's cached packages.
    chmod 1777 "${CACHE_DIR}" 2>/dev/null || sudo chmod 1777 "${CACHE_DIR}" 2>/dev/null || true

    # Sensitive root payload subdirectories are restricted to 0755
    sudo mkdir -p "${CACHE_DIR}/kernel" "${CACHE_DIR}/nvidia" "${CACHE_DIR}/slacky-slackbuilds" 2>/dev/null || true
    sudo chmod 0755 "${CACHE_DIR}/kernel" "${CACHE_DIR}/nvidia" "${CACHE_DIR}/slacky-slackbuilds" 2>/dev/null || true

    touch "${LOG_FILE}" 2>/dev/null || sudo touch "${LOG_FILE}" 2>/dev/null || true
    chmod 0666 "${LOG_FILE}" 2>/dev/null || sudo chmod 0666 "${LOG_FILE}" 2>/dev/null || true
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
            log_warn "Primary Slackware mirror (${primary_mirror}) timed out or is unreachable. Continuing with standard fallback..."
        fi
    fi

    # Auto-GPG Shield for slackpkgplus if multilib or AlienBOB repositories are present
    if [ -f "/etc/slackpkg/slackpkgplus.conf" ]; then
        if grep -E "REPOPLUS=.*(multilib|alienbob|restricted)" /etc/slackpkg/slackpkgplus.conf >/dev/null 2>&1; then
            if grep -E "^STRICTGPG=on" /etc/slackpkg/slackpkgplus.conf >/dev/null 2>&1; then
                log_info "Auto-GPG Shield: Adjusting STRICTGPG=off in slackpkgplus.conf to prevent third-party signature aborts..."
                sudo sed -i 's/^STRICTGPG=on/STRICTGPG=off/' /etc/slackpkg/slackpkgplus.conf 2>/dev/null || true
            fi
        fi
    fi
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
    echo -e "${CYAN}${BOLD}=== 🎸 POST-UPDATE SUBSYSTEM HEALTH CHECK ===${RESET}"
    echo -e "  ${GREEN}[✓]${RESET} 64-bit Slackware Core : ${GREEN}Up-to-date & healthy${RESET}"
    echo -e "  ${GREEN}[✓]${RESET} Kernel & Video Driver : ${GREEN}${kver} / ${active_driver}${RESET}"
    if [ "${multi_ok}" -eq 1 ]; then
        echo -e "  ${GREEN}[✓]${RESET} 32-bit Multilib Armor : ${GREEN}${multi_status}${RESET}"
    elif [ "${multi_status}" != "Not Configured" ]; then
        echo -e "  ${YELLOW}[!]${RESET} 32-bit Multilib Armor : ${YELLOW}${multi_status}${RESET}"
    else
        echo -e "  ${BLUE}[-]${RESET} 32-bit Multilib Armor : ${multi_status}"
    fi
    echo -e "${CYAN}${BOLD}=============================================${RESET}"
}

download_parallel_pacman() {
    local label="$1"
    shift
    local items=("$@")
    [ ${#items[@]} -gt 0 ] || return 0

    python3 - "${label}" "${items[@]}" << 'PYPACMAN'
import os
import sys
import time
import subprocess
import threading
import concurrent.futures

label = sys.argv[1] if len(sys.argv) > 1 else "Downloading"
raw_items = sys.argv[2:]

if not raw_items:
    sys.exit(0)

# Parse items: url|dest_file[|sig_url|sig_dest]
items = []
for entry in raw_items:
    parts = entry.strip().split('|')
    if len(parts) >= 2:
        url = parts[0].strip()
        dest = parts[1].strip()
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

def format_size(bytes_val):
    mb = bytes_val / (1024 * 1024)
    if mb >= 1024:
        return f"{mb / 1024:.2f} GB"
    return f"{mb:.1f} MB"

def format_eta(seconds):
    if seconds < 0 or seconds > 36000:
        return "--:--"
    m, s = divmod(int(seconds), 60)
    h, m = divmod(m, 60)
    if h > 0:
        return f"{h:02d}:{m:02d}:{s:02d}"
    return f"{m:02d}:{s:02d}"

def render_pacman_bar(pct, width=16, chomp_state=0):
    pct = max(0.0, min(100.0, pct))
    pos = int((pct / 100.0) * width)
    pos = min(width - 1, pos)
    mouth = "C" if (chomp_state % 2 == 0) else "c"
    eaten = "\033[1;32m" + "━" * pos + "\033[0m"
    pacman = f"\033[1;33m{mouth}\033[0m"
    rem = width - pos - 1
    pellets = "".join("o" if (i % 2 == 0) else " " for i in range(rem))
    uneaten = "\033[1;37m" + pellets + "\033[0m"
    if pct >= 100.0:
        return "\033[1;32m[" + "━" * width + "]\033[0m"
    return f"[{eaten}{pacman}{uneaten}]"

size_map = {}
def probe_size(item):
    url, dest, sig_url, sig_dest = item
    try:
        res = subprocess.run(["curl", "-sI", "-L", "-m", "5", url], capture_output=True, text=True)
        if res.returncode == 0:
            for line in res.stdout.splitlines():
                if line.lower().startswith("content-length:"):
                    sz = int(line.split(":", 1)[1].strip())
                    size_map[url] = sz
                    return
    except Exception:
        pass
    size_map[url] = 10 * 1024 * 1024

with concurrent.futures.ThreadPoolExecutor(max_workers=min(len(needed), 16)) as probe_exec:
    list(probe_exec.map(probe_size, needed))

total_bytes_expected = sum(size_map.get(u, 10 * 1024 * 1024) for u, _, _, _ in needed)

is_tty = sys.stdout.isatty()
try:
    term_width = os.get_terminal_size().columns
except Exception:
    term_width = 80

max_display_slots = min(num_workers, total_items, 10)
slot_bar_width = 14 if term_width < 100 else 18
total_bar_width = 18 if term_width < 100 else 24

tot_sz_str = format_size(total_bytes_expected)
print(f"\033[1;36m🚀 Turbo Parallel Pre-fetch: {label} [{total_items} files • {tot_sz_str}]\033[0m")
sys.stdout.flush()

state_lock = threading.Lock()
available_slots = list(range(max_display_slots))
slot_data = {}
completed_bytes = 0
success_count = 0
fail_count = 0
active_part_files = {}
stop_monitor = threading.Event()
start_time = time.time()
rate_history = []
first_render = True
num_lines_rendered = 0

def monitor_thread():
    global first_render, num_lines_rendered
    chomp_step = 0
    last_reported_pct = -1

    while not stop_monitor.is_set():
        time.sleep(0.08)
        chomp_step += 1
        now = time.time()

        with state_lock:
            cur_completed = completed_bytes
            cur_parts = list(active_part_files.keys())
            c_count = success_count + fail_count
            slots_snapshot = []
            for s_id in range(max_display_slots):
                if s_id in slot_data:
                    d = dict(slot_data[s_id])
                    slots_snapshot.append((s_id, d))
                else:
                    slots_snapshot.append((s_id, None))

        part_bytes = 0
        for p in cur_parts:
            try:
                if os.path.exists(p):
                    part_bytes += os.path.getsize(p)
            except Exception:
                pass

        total_dl = cur_completed + part_bytes

        rate_history.append((now, total_dl))
        while rate_history and (now - rate_history[0][0] > 1.5):
            rate_history.pop(0)

        if len(rate_history) >= 2:
            dt = rate_history[-1][0] - rate_history[0][0]
            db = rate_history[-1][1] - rate_history[0][1]
            speed_bps = db / dt if dt > 0.05 else 0.0
        else:
            speed_bps = 0.0

        speed_mb = speed_bps / (1024 * 1024)

        if total_bytes_expected > 0:
            pct = min(100.0, (total_dl / total_bytes_expected) * 100.0)
        else:
            pct = min(100.0, (c_count / total_items) * 100.0)

        rem_bytes = max(0, total_bytes_expected - total_dl)
        eta_sec = (rem_bytes / speed_bps) if speed_bps > 1024 else 0

        if is_tty:
            lines = []
            name_len = 24 if term_width < 100 else 30
            for s_id, s_info in slots_snapshot:
                if s_info:
                    item_num = s_info['item_idx']
                    fn = s_info['filename']
                    if len(fn) > name_len:
                        fn = fn[:name_len-3] + "..."
                    exp_sz = s_info['exp_sz']
                    p_file = s_info['part_file']
                    cur_sz = 0
                    try:
                        if os.path.exists(p_file):
                            cur_sz = os.path.getsize(p_file)
                    except Exception:
                        pass
                    
                    s_pct = min(100.0, (cur_sz / exp_sz * 100.0)) if exp_sz > 0 else 50.0
                    
                    s_hist = s_info.get('history', [])
                    s_hist.append((now, cur_sz))
                    while s_hist and (now - s_hist[0][0] > 1.2):
                        s_hist.pop(0)
                    s_info['history'] = s_hist
                    if len(s_hist) >= 2:
                        s_dt = s_hist[-1][0] - s_hist[0][0]
                        s_db = s_hist[-1][1] - s_hist[0][1]
                        s_spd = (s_db / s_dt) / (1024 * 1024) if s_dt > 0.05 else 0.0
                    else:
                        s_spd = 0.0

                    s_bar = render_pacman_bar(s_pct, width=slot_bar_width, chomp_state=chomp_step + s_id)
                    lines.append(f"  [\033[1;36m{item_num:2d}/{total_items:<2d}\033[0m] \033[1;37m{fn:<{name_len}s}\033[0m {s_bar} \033[1;33m{int(s_pct):3d}%\033[0m • \033[1;32m{s_spd:4.1f} MB/s\033[0m")
                else:
                    if total_items > max_display_slots:
                        lines.append(f"  [\033[1;30m--/{total_items:<2d}\033[0m] \033[1;30m{'(idle / queued)':<{name_len}s}\033[0m \033[1;30m[{' ':>{slot_bar_width}s}]\033[0m \033[1;30m --% •  0.0 MB/s\033[0m")
                    else:
                        lines.append(f"  [\033[1;30m--/{total_items:<2d}\033[0m] \033[1;30m{'(standby)':<{name_len}s}\033[0m \033[1;30m[{' ':>{slot_bar_width}s}]\033[0m \033[1;30m --% •  0.0 MB/s\033[0m")

            if max_display_slots > 1:
                div_len = min(term_width - 4, 76)
                lines.append("  \033[1;30m" + "─" * div_len + "\033[0m")

            tot_bar = render_pacman_bar(pct, width=total_bar_width, chomp_state=chomp_step)
            cur_sz_str = format_size(total_dl)
            eta_str = format_eta(eta_sec)
            lines.append(f"  [\033[1;36m⚡ Total: {c_count:2d}/{total_items:<2d}\033[0m] [\033[1;37m{cur_sz_str:>8s} / {tot_sz_str}\033[0m] {tot_bar} \033[1;33m{int(pct):3d}%\033[0m • \033[1;32m{speed_mb:4.1f} MB/s\033[0m • ETA: \033[1;35m{eta_str}\033[0m")

            out_block = "\n".join(f"\r\033[2K{l}" for l in lines)
            if first_render:
                sys.stdout.write(out_block + "\n")
                first_render = False
                num_lines_rendered = len(lines)
            else:
                sys.stdout.write(f"\033[{num_lines_rendered}A" + out_block + "\n")
            sys.stdout.flush()
        else:
            int_pct = int(pct)
            if int_pct >= last_reported_pct + 25:
                last_reported_pct = (int_pct // 25) * 25
                print(f"  [⚡ {c_count:3d}/{total_items} files] {format_size(total_dl)} / {tot_sz_str} ({int_pct}%) • {speed_mb:.1f} MB/s")
                sys.stdout.flush()

def download_item_wrapper(args):
    idx, item = args
    url, dest, sig_url, sig_dest = item
    dest_dir = os.path.dirname(dest)
    if dest_dir:
        os.makedirs(dest_dir, exist_ok=True)
    part_file = f"{dest}.part"
    part_sig = f"{sig_dest}.part" if sig_dest else ""
    exp_sz = size_map.get(url, 10 * 1024 * 1024)
    fn = os.path.basename(dest)

    slot_id = -1
    while slot_id == -1 and not stop_monitor.is_set():
        with state_lock:
            if available_slots:
                slot_id = available_slots.pop(0)
                slot_data[slot_id] = {
                    'item_idx': idx + 1,
                    'filename': fn,
                    'exp_sz': exp_sz,
                    'part_file': part_file,
                    'history': []
                }
                active_part_files[part_file] = True
        if slot_id == -1:
            time.sleep(0.05)

    global completed_bytes, success_count, fail_count
    try:
        res = subprocess.run(["curl", "-sSL", "-f", "-C", "-", "-m", "180", "-o", part_file, url], capture_output=True)
        if res.returncode == 0 and os.path.exists(part_file) and os.path.getsize(part_file) > 0:
            if sig_url and sig_dest:
                res_sig = subprocess.run(["curl", "-sSL", "-f", "-m", "45", "-o", part_sig, sig_url], capture_output=True)
                if res_sig.returncode == 0 and os.path.exists(part_sig) and os.path.getsize(part_sig) > 0:
                    os.replace(part_sig, sig_dest)
                else:
                    if os.path.exists(part_sig):
                        try: os.remove(part_sig)
                        except Exception: pass
            actual_sz = os.path.getsize(part_file)
            os.replace(part_file, dest)
            with state_lock:
                completed_bytes += actual_sz
                success_count += 1
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
avg_speed_mb = (completed_bytes / (1024 * 1024)) / total_elapsed

if is_tty and num_lines_rendered > 0:
    sys.stdout.write(f"\033[{num_lines_rendered}A")
    for _ in range(num_lines_rendered):
        sys.stdout.write("\r\033[2K\n")
    sys.stdout.write(f"\033[{num_lines_rendered}A")
    sys.stdout.flush()

if fail_count > 0:
    print(f"\033[1;33m⚠️ Turbo Parallel Pre-fetch finished: {success_count}/{total_items} files ({format_size(completed_bytes)}) cached in {int(total_elapsed)}s ({fail_count} failed).\033[0m\n")
    sys.exit(1)
else:
    print(f"\033[1;32m✓ Turbo Parallel Pre-fetch completed: {success_count} files ({format_size(completed_bytes)}) cached in {int(total_elapsed)}s (avg {avg_speed_mb:.1f} MB/s).\033[0m\n")
    sys.exit(0)
PYPACMAN
}
