#!/usr/bin/env bash
# --- [ COMMON DEFINITIONS & PATH RESOLUTION ] ---

set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

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

log_info() {
    local msg="$1"
    echo -e "${CYAN}[WHOA]${RESET} ${msg}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] ${msg}" >> "${LOG_FILE}" 2>/dev/null || true
}

log_success() {
    local msg="$1"
    echo -e "${GREEN}[COWABUNGA]${RESET} ${msg}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] ${msg}" >> "${LOG_FILE}" 2>/dev/null || true
}

log_warn() {
    local msg="$1"
    echo -e "${YELLOW}[BOGUS]${RESET} ${msg}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] ${msg}" >> "${LOG_FILE}" 2>/dev/null || true
}

log_error() {
    local msg="$1"
    echo -e "${RED}[MAJOR BUMMER]${RESET} ${msg}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] ${msg}" >> "${LOG_FILE}" 2>/dev/null || true
}

check_slacky_update_self_update() {
    local current_ver="${1:-0.6.0}"
    local rel_json
    rel_json=$(curl -sSL -m 2 -H "User-Agent: slacky-update" "https://api.github.com/repos/TuxOfValhalla/slacky-update/releases/latest" 2>/dev/null || true)
    [ -n "${rel_json}" ] || return 0

    local update_info
    update_info=$(python3 -c "
import json, sys, re

def parse_v(v_str):
    return [int(x) for x in re.findall(r'\d+', v_str)]

try:
    data = json.loads('''${rel_json}''')
    tag = data.get('tag_name', '').lstrip('v')
    cur = '${current_ver}'.lstrip('v')
    if tag and parse_v(tag) > parse_v(cur):
        dl_url = ''
        for asset in data.get('assets', []):
            name = asset.get('name', '')
            if name.endswith('.txz') or name.endswith('.tgz'):
                dl_url = asset.get('browser_download_url', '')
                break
        if not dl_url:
            dl_url = data.get('tarball_url', '')
        print(f'{tag}|{dl_url}')
except Exception:
    pass
" 2>/dev/null || true)

    [ -n "${update_info}" ] || return 0

    local new_tag dl_url
    IFS='|' read -r new_tag dl_url <<< "${update_info}"

    echo ""
    echo -e "${YELLOW}${BOLD}⚡ New Slacky-Update Release Available: v${new_tag} (Current: v${current_ver})${RESET}"
    read -r -p "$(_ PROMPT_SELF_UPDATE)" reply_update
    reply_update=${reply_update:-Y}
    if [[ "$reply_update" =~ ^[YyJjSsOo]$ ]]; then
        validate_privileges
        log_info "Downloading Slacky-Update v${new_tag} from GitHub..."
        local tmp_pkg="/tmp/slacky-update-${new_tag}.txz"
        if [[ "${dl_url}" =~ \.txz$|\.tgz$ ]]; then
            sudo curl -sSL -o "${tmp_pkg}" "${dl_url}"
            if [ -f "${tmp_pkg}" ] && [ -s "${tmp_pkg}" ]; then
                sudo /sbin/upgradepkg --reinstall "${tmp_pkg}"
                sudo rm -f "${tmp_pkg}"
                log_success "Slacky-Update upgraded to v${new_tag}!"
                command -v slacky-update-tray >/dev/null 2>&1 && slacky-update-tray --restart 2>/dev/null || true
                exec /usr/local/bin/slacky-update "$@"
            fi
        fi
    fi
}

init_storage() {
    if [ ! -d "${CACHE_DIR}" ]; then
        mkdir -p "${CACHE_DIR}" 2>/dev/null || sudo mkdir -p "${CACHE_DIR}" 2>/dev/null || true
        chmod 777 "${CACHE_DIR}" 2>/dev/null || sudo chmod 777 "${CACHE_DIR}" 2>/dev/null || true
    fi
    touch "${LOG_FILE}" 2>/dev/null || sudo touch "${LOG_FILE}" 2>/dev/null || true
    chmod 666 "${LOG_FILE}" 2>/dev/null || sudo chmod 666 "${LOG_FILE}" 2>/dev/null || true
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
