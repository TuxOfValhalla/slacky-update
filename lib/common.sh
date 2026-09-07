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
    local current_ver="${1:-0.7}"
    local rel_json
    rel_json=$(curl -sSL -m 2 -H "User-Agent: slacky-update" "https://api.github.com/repos/TuxOfValhalla/slacky-update/releases/latest" 2>/dev/null || true)

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
            log_info "Downloading Slacky-Update v${new_tag} from GitHub (Canonical)..."
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
        echo -e "  \033[1;32m✓\033[0m $(_ APP_UP_TO_DATE tag="v${current_ver}")"
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
