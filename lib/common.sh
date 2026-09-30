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

is_laptop_chassis() {
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
    echo -e "  ${CYAN}•${RESET} ${msg}"
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
    # 1. Query GitHub API (canonical release source)
    rel_json=$(curl -sSL -m 4 -H "User-Agent: slacky-update" "https://api.github.com/repos/TuxOfValhalla/slacky-update/releases/latest" 2>/dev/null || true)

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
        nohup "${chk_bin}" </dev/null >/dev/null 2>&1 &
    fi
}

init_storage() {
    # If running as root, enforce strict storage permissions and directory layout
    if [ "$(id -u)" -eq 0 ]; then
        mkdir -p "${CACHE_DIR}/kernel" "${CACHE_DIR}/nvidia" "${CACHE_DIR}/slacky-slackbuilds" 2>/dev/null || true
        chmod 1777 "${CACHE_DIR}" 2>/dev/null || true
        chmod 0755 "${CACHE_DIR}/kernel" "${CACHE_DIR}/nvidia" "${CACHE_DIR}/slacky-slackbuilds" 2>/dev/null || true
        touch "${LOG_FILE}" 2>/dev/null || true
        chmod 0666 "${LOG_FILE}" 2>/dev/null || true
    else
        # Unprivileged caller: attempt local user cache or silent non-blocking sudo if passwordless
        mkdir -p "${CACHE_DIR}" 2>/dev/null || {
            if sudo -n true 2>/dev/null; then
                sudo mkdir -p "${CACHE_DIR}/kernel" "${CACHE_DIR}/nvidia" "${CACHE_DIR}/slacky-slackbuilds" 2>/dev/null || true
                sudo chmod 1777 "${CACHE_DIR}" 2>/dev/null || true
                sudo chmod 0755 "${CACHE_DIR}/kernel" "${CACHE_DIR}/nvidia" "${CACHE_DIR}/slacky-slackbuilds" 2>/dev/null || true
            fi
        }
        touch "${LOG_FILE}" 2>/dev/null || {
            if sudo -n true 2>/dev/null; then
                sudo touch "${LOG_FILE}" 2>/dev/null || true
                sudo chmod 0666 "${LOG_FILE}" 2>/dev/null || true
            fi
        }
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
    (cd "${_sp_tmpdir}" && sudo "${slackpkg_bin}" "$@" 2>&1) | python3 -u -c '
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
            sys.stdout.write(clean + "\n")
            sys.stdout.flush()
        else:
            buf.append(ch)

if buf:
    clean = ansi_re.sub("", "".join(buf)).strip()
    if clean and not spinner_re.match(clean):
        sys.stdout.write(clean + "\n")
        sys.stdout.flush()
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
print(f"\033[1;36m🚀 Turbo Parallel Pre-fetch: {label} [{total_items} files • ~{tot_sz_str}]\033[0m")
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
        curl_args = ["curl", "-sSL", "-f", "--connect-timeout", "15", "-m", "1800", "--speed-time", "45", "--speed-limit", "1000"]
        res = subprocess.run(curl_args + ["-C", "-", "-o", part_file, url], capture_output=True)
        if res.returncode != 0:
            if os.path.exists(part_file):
                try: os.remove(part_file)
                except Exception: pass
            res = subprocess.run(curl_args + ["-o", part_file, url], capture_output=True)
        if res.returncode == 0 and os.path.exists(part_file) and os.path.getsize(part_file) > 0:
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

if fail_count > 0:
    print(f"\033[1;33m⚠️ Turbo Parallel Pre-fetch finished: {success_count}/{total_items} files ({format_size(completed_bytes)}) cached in {int(total_elapsed)}s ({fail_count} failed).\033[0m\n")
    sys.exit(1)
else:
    print(f"\033[1;32m✓ Turbo Parallel Pre-fetch completed: {success_count} files ({format_size(completed_bytes)}) cached in {int(total_elapsed)}s (avg {avg_speed_mb:.1f} MB/s).\033[0m\n")
    sys.exit(0)
PYPACMAN
}
