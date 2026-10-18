#!/usr/bin/env bash
# --- [ NVIDIA DRIVER & DKMS ENGINE ] ---

set -euo pipefail

# --- [ HARDWARE DETECTION & DKMS CHECK ] ---
# 6A-130 (N1): NVIDIA generation from the PCI device ID. The old lspci regex matched three hex digits, so a four-digit ID
# such as 10de:1b80 (GTX 1080) was never seen as Pascal and fell through to MODERN. sysfs is read first (no lspci text
# parsing); SLACKY_SYSFS_ROOT lets tests use a fake tree. Turing and newer (0x1e00 and up) = MODERN; Pascal and Volta
# (0x15f0-0x15ff GP100, 0x1b00-0x1dff) = PASCAL; anything older = LEGACY; no readable ID = UNKNOWN.
_nvidia_gen_for_devid() {
    local id="${1#0x}"
    [[ "${id}" =~ ^[0-9a-fA-F]{4}$ ]] || { echo "UNKNOWN"; return 0; }
    id=$(( 16#${id} ))
    if [ "${id}" -ge $(( 16#1e00 )) ]; then
        echo "MODERN"
    elif [ "${id}" -ge $(( 16#1b00 )) ] || { [ "${id}" -ge $(( 16#15f0 )) ] && [ "${id}" -le $(( 16#15ff )) ]; }; then
        echo "PASCAL"
    else
        echo "LEGACY"
    fi
}

# Prints "<device-id> <bound-driver>" for every NVIDIA display device (driver "-" when none is bound).
_nvidia_pci_devices() {
    local sys="${SLACKY_SYSFS_ROOT:-}/sys/bus/pci/devices" d cls ven dev drv found=0
    for d in "${sys}"/*; do
        [ -r "${d}/class" ] || continue
        read -r cls < "${d}/class" 2>/dev/null || continue
        case "${cls}" in 0x03*) ;; *) continue ;; esac
        read -r ven < "${d}/vendor" 2>/dev/null || continue
        [ "${ven}" = "0x10de" ] || continue
        read -r dev < "${d}/device" 2>/dev/null || continue
        drv="-"
        [ -L "${d}/driver" ] && drv=$(basename "$(readlink "${d}/driver")")
        echo "${dev#0x} ${drv}"
        found=1
    done
    [ "${found}" -eq 1 ] && return 0
    # Fallback: lspci text (four hex digits), "Kernel driver in use" for the bound driver
    lspci -nnk 2>/dev/null | awk '
        /^[0-9a-f]/ { if (id != "") print id, drv; id = ""; drv = "-"
                      if ($0 ~ /(VGA|3D|Display)/ && match($0, /\[10de:[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]\]/))
                          id = tolower(substr($0, RSTART + 6, 4)) }
        /Kernel driver in use:/ { drv = $NF }
        END { if (id != "") print id, drv }' || true
}

detect_nvidia_gpu() {
    probe_gpu_hardware
    if [ "${HAS_NVIDIA}" = "false" ]; then
        echo "NONE"
        return 0
    fi
    # Several NVIDIA cards share one kernel driver, so the oldest card decides.
    local id drv g worst="" devs
    devs=$(_nvidia_pci_devices)
    while read -r id drv; do
        [ -n "${id}" ] || continue
        g=$(_nvidia_gen_for_devid "${id}")
        case "${g}" in
            LEGACY) worst="LEGACY" ;;
            PASCAL) [ "${worst}" = "LEGACY" ] || worst="PASCAL" ;;
            MODERN) [ -n "${worst}" ] || worst="MODERN" ;;
        esac
    done <<< "${devs}"
    echo "${worst:-UNKNOWN}"
}

# 6A-130: the one gate every NVIDIA entry point uses. Returns 0 when this tool may manage the NVIDIA driver; otherwise
# prints one plain line (once per shell) and returns 1. Rules (owner decision 2026-10-13, LTS scope):
#   - /etc/slacky-update/nvidia.disabled switches NVIDIA management off everywhere (6A-132);
#   - only Turing or newer cards are managed (Pascal, Volta, Maxwell, Kepler are left alone) (6A-131);
#   - a card running nouveau is never switched to NVIDIA unless the user chose it (INTERACTIVE_NVIDIA=1) (6A-132);
#   - with no driver bound, only a machine that already has an NVIDIA driver installed is managed.
NVIDIA_OPTOUT_FILE="${NVIDIA_OPTOUT_FILE:-/etc/slacky-update/nvidia.disabled}"
nvidia_generation_supported() {
    local why=""
    if [ -e "${NVIDIA_OPTOUT_FILE}" ]; then
        why="NVIDIA driver management is switched off by ${NVIDIA_OPTOUT_FILE}, so the graphics driver was left as it is."
    else
        local gen
        gen=$(detect_nvidia_gpu)
        case "${gen}" in
            NONE) return 1 ;;
            MODERN) ;;
            UNKNOWN) why="The NVIDIA card model could not be read, so the graphics driver was left as it is." ;;
            *) why="Your NVIDIA card is older than the cards this tool manages, so the graphics driver was left as it is." ;;
        esac
        if [ -z "${why}" ] && [ "${INTERACTIVE_NVIDIA:-0}" != "1" ]; then
            local devs bound
            devs=$(_nvidia_pci_devices)
            bound=$(echo "${devs}" | awk '{print $2}')
            if ! echo "${bound}" | grep -qx 'nvidia'; then
                if echo "${bound}" | grep -qx 'nouveau'; then
                    why="Your NVIDIA card runs the nouveau driver, so it was left as it is; run 'slacky-update --nvidia' if you want the NVIDIA driver."
                elif ! nvidia_driver_present; then
                    why="No NVIDIA driver is installed, so none was added; run 'slacky-update --nvidia' if you want one."
                fi
            fi
        fi
    fi
    [ -z "${why}" ] && return 0
    if [ "${NVIDIA_GATE_SHOWN:-}" != "${why}" ]; then
        log_warn "${why}"
        NVIDIA_GATE_SHOWN="${why}"
    fi
    return 1
}

# True when some NVIDIA driver is already on the machine (our package, a loaded module, a .run install, or nvidia.ko).
nvidia_driver_present() {
    [ -f "${SLACKY_SYSFS_ROOT:-}/sys/module/nvidia/version" ] && return 0
    compgen -G "${PKGDB_DIR:-/var/log/packages}/cachyos-nvidia*utils-*" >/dev/null 2>&1 && return 0
    [ -x /usr/bin/nvidia-uninstall ] && return 0
    local m
    for m in "${MODULES_ROOT:-/lib/modules}"/*; do
        [ -n "$(find -L "${m}" -name 'nvidia.ko*' -print -quit 2>/dev/null)" ] && return 0
    done
    return 1
}

ensure_dkms_installed_interactive() {
    probe_gpu_hardware
    [ "${HAS_NVIDIA}" = "true" ] || return 0

    if command -v dkms >/dev/null 2>&1; then
        return 0
    fi

    echo ""
    log_warn "DKMS utility is not installed on this system."
    echo "DKMS is required to automatically rebuild NVIDIA drivers across kernel updates."
    # 6A-6e: DKMS is an official Slackware -current package (slackware64/d). The old SBo 15.0 bootstrap
    # (fixed /tmp dir, no checksum, URL now 404) is replaced by slackpkg, which verifies Slackware's GPG signature.
    read -r -p "Would you like Slacky-Update to install DKMS from the official Slackware packages? [Y/n] " reply_dkms
    reply_dkms=${reply_dkms:-Y}
    if [[ "$reply_dkms" =~ ^[YyJjSsOo]$ ]]; then
        validate_privileges
        log_info "Installing DKMS from the official Slackware packages..."
        run_slackpkg -batch=on -default_answer=y update || true
        run_slackpkg -batch=on -default_answer=y install dkms || true
        if command -v dkms >/dev/null 2>&1 || [ -x /usr/sbin/dkms ]; then
            log_success "DKMS installed successfully!"
        else
            log_warn "DKMS could not be installed. Install it with: slackpkg install dkms"
            return 1
        fi
    fi
}

# --- [ SYSTEM CONFIGURATION INTEGRATION ] ---
# 6A-132 (F4): nouveau may only be switched off once its replacement is proven: an NVIDIA userspace is installed and every
# kept kernel has an nvidia.ko (of the expected version when one is given). Stock kernels without a build tree are the
# rescue rail and are not expected to carry one; kernels about to be removed are ignored.
nvidia_replacement_proven() {
    local want_ver="${1:-}" mroot="${MODULES_ROOT:-/lib/modules}" kdir kver mod v dying=""
    if ! compgen -G "${PKGDB_DIR:-/var/log/packages}/cachyos-nvidia*utils-*" >/dev/null 2>&1 && [ ! -x "${NVIDIA_SMI_BIN:-/usr/bin/nvidia-smi}" ]; then
        return 1
    fi
    if command -v ss_purge_set >/dev/null 2>&1; then
        dying=" $(ss_purge_set 2>/dev/null | tr '\n' ' ') "
    fi
    for kdir in "${mroot}"/*; do
        [ -d "${kdir}" ] || continue
        kver=$(basename "${kdir}")
        [ -f "${kdir}/modules.dep" ] || continue
        case "${dying}" in *" ${kver} "*) continue ;; esac
        if [[ ! "${kver}" =~ (cachyos|-zen|-arch) ]] && [ ! -d "${kdir}/build" ] && [ ! -d "/usr/src/linux-${kver}" ]; then
            continue
        fi
        mod=$(find -L "${kdir}" -name 'nvidia.ko*' 2>/dev/null | head -n 1 || true)
        [ -n "${mod}" ] || return 1
        if [ -n "${want_ver}" ]; then
            v=$(get_nvidia_module_version "${mod}")
            [ "${v}" = "${want_ver}" ] || return 1
        fi
    done
    return 0
}

configure_nvidia_modprobe() {
    local want_ver="${1:-}"
    local conf_file="/etc/modprobe.d/nvidia.conf"
    # 6A-131/6A-132: never blacklist nouveau for an unmanaged card, or before the NVIDIA driver is proven for every kernel
    nvidia_generation_supported || return 0
    if ! nvidia_replacement_proven "${want_ver}"; then
        if ! grep -qs '^blacklist nouveau' "${conf_file}"; then
            log_warn "The open-source nouveau driver was kept because the NVIDIA driver is not ready for every kernel yet."
        fi
        return 1
    fi
    validate_privileges

    log_info "Configuring NVIDIA modprobe parameters..."
    sudo mkdir -p /etc/modprobe.d

    cat << 'CONF_EOF' | sudo tee "${conf_file}" >/dev/null
# Generated by slacky-update
blacklist nouveau
options nouveau modeset=0

# Power Management and Video Memory Allocation
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia NVreg_TemporaryFilePath=/var/tmp
CONF_EOF

    log_success "NVIDIA modprobe settings written to: ${conf_file}"
}

# --- [ UPSTREAM VERSION RESOLUTION ] ---
resolve_nvidia_branch_version() {
    local prefix="$1"
    local default_ver="$2"

    curl -sSL -m 8 "https://download.nvidia.com/XFree86/Linux-x86_64/" 2>/dev/null | python3 -c "
import sys, re

html = sys.stdin.read()
if not html:
    print('$default_ver')
    sys.exit(0)

prefix = '$prefix'
matches = re.findall(r'href=[\'\"]?(' + re.escape(prefix) + r'\.[0-9]+(?:\.[0-9]+)?)/?[\'\"]?', html)
if not matches:
    print('$default_ver')
    sys.exit(0)

def parse_v(v):
    return [int(x) for x in v.split('.') if x.isdigit()]

sorted_matches = sorted(list(set(matches)), key=parse_v, reverse=True)
print(sorted_matches[0])
" 2>/dev/null || echo "${default_ver}"
}

# 6A-312 (V3): major number (three digits) of the NVIDIA driver in use; empty when none is loaded.
nvidia_installed_major() {
    local v="${NVIDIA_ACTIVE_VER:-}" m=""
    [ -n "${v}" ] || v=$(tr -d '[:space:]' < /sys/module/nvidia/version 2>/dev/null || true)
    [ -n "${v}" ] || v=$(grep -m1 -o -E '[0-9]{3}\.[0-9]+(\.[0-9]+)?' /proc/driver/nvidia/version 2>/dev/null || true)
    m="${v%%.*}"
    [[ "${m}" =~ ^[0-9]{3}$ ]] && printf '%s' "${m}"
    return 0
}

# 6A-312 (V3): the one rule behind "production": stay on the branch of the driver that is installed (it is only updated inside
# its own branch); with no driver loaded, take the branch NVIDIA's latest.txt names; with neither, 595. The branch the user
# picks in the menu (470, 535, 570, 595) is never changed by this.
nvidia_production_branch() {
    local m latest
    m=$(nvidia_installed_major)
    if [ -n "${m}" ] && [ "${m}" -ge 470 ]; then printf '%s' "${m}"; return 0; fi
    latest=$(curl -fsSL --connect-timeout 5 -m 8 "https://download.nvidia.com/XFree86/Linux-x86_64/latest.txt" 2>/dev/null | awk '{print $1}' | head -n 1 || true)
    if [[ "${latest}" =~ ^([0-9]{3})\.[0-9]+(\.[0-9]+)?$ ]]; then printf '%s' "${BASH_REMATCH[1]}"; return 0; fi
    printf '595'
}

# 6A-312 (V3): the version number "production" would install, so an update is offered only when it can really be installed.
# Empty when the lookup fails (then nothing is offered).
nvidia_production_offer_version() {
    local url
    url=$(get_nvidia_download_url "production")
    [ -n "${url}" ] || return 0
    basename "${url}" | sed -E 's/^NVIDIA-Linux-x86_64-([0-9]+\.[0-9]+(\.[0-9]+)?)\.run$/\1/' | grep -E '^[0-9]+\.[0-9]+(\.[0-9]+)?$' || true
}

get_nvidia_download_url() {
    local branch="$1"
    local ver=""

    case "${branch}" in
        production|feature)
            branch=$(nvidia_production_branch)
            ;;
    esac

    case "${branch}" in
        390)
            ver="390.157"
            echo "https://download.nvidia.com/XFree86/Linux-x86_64/${ver}/NVIDIA-Linux-x86_64-${ver}.run"
            ;;
        470)
            ver=$(resolve_nvidia_branch_version "470" "470.256.02")
            echo "https://download.nvidia.com/XFree86/Linux-x86_64/${ver}/NVIDIA-Linux-x86_64-${ver}.run"
            ;;
        535)
            ver=$(resolve_nvidia_branch_version "535" "535.309.01")  # 6A-312: the old fallback 535.241.11 returns 404
            echo "https://download.nvidia.com/XFree86/Linux-x86_64/${ver}/NVIDIA-Linux-x86_64-${ver}.run"
            ;;
        570|legacy)
            ver=$(resolve_nvidia_branch_version "570" "570.124.04")
            echo "https://download.nvidia.com/XFree86/Linux-x86_64/${ver}/NVIDIA-Linux-x86_64-${ver}.run"
            ;;
        595)
            ver=$(resolve_nvidia_branch_version "595" "595.58.03")
            echo "https://download.nvidia.com/XFree86/Linux-x86_64/${ver}/NVIDIA-Linux-x86_64-${ver}.run"
            ;;
        [0-9][0-9][0-9])
            # 6A-312: a newer or other branch has no built-in fallback; if the index cannot be read nothing is returned
            ver=$(resolve_nvidia_branch_version "${branch}" "")
            [ -n "${ver}" ] && echo "https://download.nvidia.com/XFree86/Linux-x86_64/${ver}/NVIDIA-Linux-x86_64-${ver}.run"
            ;;
        *)
            ver=$(resolve_nvidia_branch_version "595" "595.58.03")
            echo "https://download.nvidia.com/XFree86/Linux-x86_64/${ver}/NVIDIA-Linux-x86_64-${ver}.run"
            ;;
    esac
}

manage_legacy_nvidia_run_interactive() {
    local tui_py="${REPO_ROOT:-}/lib/slacky_tui.py"
    [ ! -f "${tui_py}" ] && [ -f "${SCRIPT_DIR}/../lib/slacky_tui.py" ] && tui_py="${SCRIPT_DIR}/../lib/slacky_tui.py"
    [ ! -f "${tui_py}" ] && [ -f "/usr/share/slacky-update/lib/slacky_tui.py" ] && tui_py="/usr/share/slacky-update/lib/slacky_tui.py"

    while true; do
        local leg_choice=""
        if [ -f "${tui_py}" ] && command -v python3 >/dev/null 2>&1 && [ -t 0 ]; then
            leg_choice=$(python3 "${tui_py}" --mode nvidia-legacy || true)
        else
            echo ""
            echo -e "${BLUE}${BOLD}============================================================${RESET}"
            echo -e "${BLUE}${BOLD}$(_ MENU_NVIDIA_LEGACY_TITLE)${RESET}"
            echo -e "${BLUE}${BOLD}============================================================${RESET}"
            echo -e "  \033[1;33m1.\033[0m $(_ NVIDIA_LEGACY_BRANCH_595)"
            echo -e "  \033[1;33m2.\033[0m $(_ NVIDIA_LEGACY_BRANCH_570)"
            echo -e "  \033[1;33m3.\033[0m $(_ NVIDIA_LEGACY_BRANCH_535)"
            echo -e "  \033[1;33m4.\033[0m $(_ NVIDIA_LEGACY_BRANCH_470)"
            echo -e "  \033[1;33m5.\033[0m $(_ NVIDIA_LEGACY_BRANCH_390)"
            echo -e "  \033[1;33m6.\033[0m $(_ NVIDIA_LEGACY_RETURN)"
            echo ""
            echo -n "$(_ SELECT_OPERATION_RANGE range="1-6") "
            read -r leg_choice || leg_choice="6"
        fi

        case "${leg_choice}" in
            1)
                validate_privileges
                INTERACTIVE_NVIDIA=1 install_nvidia_run_driver "595" || true
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            2)
                validate_privileges
                INTERACTIVE_NVIDIA=1 install_nvidia_run_driver "570" || true
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            3)
                validate_privileges
                INTERACTIVE_NVIDIA=1 install_nvidia_run_driver "535" || true
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            4)
                validate_privileges
                INTERACTIVE_NVIDIA=1 install_nvidia_run_driver "470" || true
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            5)
                validate_privileges
                INTERACTIVE_NVIDIA=1 install_nvidia_run_driver "390" || true
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            6|[Qq])
                return 0
                ;;
            *)
                log_warn "Invalid selection."
                ;;
        esac
    done
}

transition_legacy_run_to_cachyos() {
    local has_unmanaged_run=0
    if [ -f "/var/log/nvidia-installer.log" ] || [ -x "/usr/bin/nvidia-uninstall" ]; then
        has_unmanaged_run=1
    elif command -v nvidia-smi >/dev/null 2>&1; then
        if ! compgen -G "/var/log/packages/*nvidia*" >/dev/null 2>&1; then
            has_unmanaged_run=1
        fi
    fi

    [ "${has_unmanaged_run}" -eq 1 ] || return 0
    # 6A-131: a .run driver on a card this tool does not manage is never removed
    nvidia_generation_supported || return 0

    log_info "Detected legacy unmanaged NVIDIA (.run) installation on system."
    log_info "Executing clean transition: removing untracked .run artifacts and preparing clean system libraries..."
    validate_privileges

    if [ -x "/usr/bin/nvidia-uninstall" ]; then
        sudo /usr/bin/nvidia-uninstall --silent 2>/dev/null || true
    fi

    sudo rm -f /var/log/nvidia-installer.log 2>/dev/null || true
    sudo find /usr/lib64 /usr/lib -xtype l -name "*nvidia*" -delete 2>/dev/null || true
    sudo find /usr/lib64 /usr/lib -xtype l -name "*cuda*" -delete 2>/dev/null || true
    sudo find /usr/lib64 /usr/lib -xtype l -name "*nvcuvid*" -delete 2>/dev/null || true
    sudo /sbin/ldconfig 2>/dev/null || true
    log_success "Clean transition complete. System libraries prepared for CachyOS native suite."
}

# 6A-134 (L2 M8): download + checksum check of a .run installer, split out so the rollback can fetch and verify it
# BEFORE anything is removed. Returns 1 and leaves nothing behind on any failure.
nvidia_fetch_verified_run() {
    local url="$1" target_file="$2" branch="${3:-}"
    local filename dest_dir
    filename=$(basename "${target_file}")
    dest_dir=$(dirname "${target_file}")
    sudo mkdir -p "${dest_dir}" "/var/cache/slacky-update/backup/nvidia"
    log_info "Downloading NVIDIA driver installer (${branch} branch: ${filename})..."
    # 6A-6d: the installer runs as root, so it must be the exact file NVIDIA published. Before, curl had no -f (an error
    # page was saved, made executable and run) and nothing was checked. Download to a temporary name, compare with the
    # .sha256sum NVIDIA publishes next to it (.md5sum for old branches), and only then put it in place.
    local run_tmp="${target_file}.part.$$" sum_expected="" sum_tool="" sum_actual=""
    sudo rm -f "${run_tmp}" 2>/dev/null || true
    if ! sudo curl -fsSL --connect-timeout 10 --speed-limit 1024 --speed-time 25 -o "${run_tmp}" "${url}"; then
        sudo rm -f "${run_tmp}" 2>/dev/null || true
        log_error "The NVIDIA driver installer could not be downloaded. Nothing was changed."
        return 1
    fi
    sum_expected=$(curl -fsSL --connect-timeout 10 "${url}.sha256sum" 2>/dev/null | awk '{print tolower($1)}' | grep -E '^[0-9a-f]{64}$' || true)
    [ -n "${sum_expected}" ] && sum_tool="sha256sum"
    if [ -z "${sum_expected}" ]; then
        sum_expected=$(curl -fsSL --connect-timeout 10 "${url}.md5sum" 2>/dev/null | awk '{print tolower($1)}' | grep -E '^[0-9a-f]{32}$' || true)
        [ -n "${sum_expected}" ] && sum_tool="md5sum"
    fi
    if [ -z "${sum_tool}" ]; then
        sudo rm -f "${run_tmp}" 2>/dev/null || true
        log_error "NVIDIA publishes no checksum for ${filename}, so it cannot be verified. The installer was not run."
        return 1
    fi
    sum_actual=$(sudo "${sum_tool}" "${run_tmp}" 2>/dev/null | awk '{print $1}')
    if [ "${sum_actual}" != "${sum_expected}" ]; then
        sudo rm -f "${run_tmp}" 2>/dev/null || true
        log_error "The NVIDIA driver installer does not match its published checksum (damaged or tampered). It was deleted and not run."
        return 1
    fi
    sudo mv -f "${run_tmp}" "${target_file}"
    sudo chmod +x "${target_file}"
    sudo cp -f "${target_file}" "/var/cache/slacky-update/backup/nvidia/${filename}" 2>/dev/null || true

    return 0
}

# --- [ DRIVER INSTALLATION ] ---
install_nvidia_run_driver() {
    local branch="$1"
    # 6A-312 (V3): NVIDIA publishes no checksum for branch 390, and the installer runs as root, so it is not supported
    if [ "${branch}" = "390" ]; then
        log_error "NVIDIA driver branch 390 is not supported here, because NVIDIA publishes no checksum to verify it. Nothing was changed."
        return 1
    fi
    # 6A-131 (B6/F1): pre-Turing, nouveau (unless chosen), unreadable model or opt-out: nothing is installed or replaced
    probe_gpu_hardware
    nvidia_generation_supported || return 0
    validate_privileges

    local prefetched="${2:-}"
    local url filename
    if [ -n "${prefetched}" ]; then
        filename=$(basename "${prefetched}")
        url=""
    else
        url=$(get_nvidia_download_url "${branch}")
        if [ -z "${url}" ]; then
            log_error "No NVIDIA installer for the ${branch} branch could be found right now. Nothing was changed."
            return 1
        fi
        filename=$(basename "${url}")
    fi
    local dest_dir="/var/cache/slacky-update/nvidia"
    local target_file="${dest_dir}/${filename}"

    if [ "$(has_cachyos_kernels_installed 2>/dev/null || echo false)" = "true" ]; then
        local cachy_nv_ver
        cachy_nv_ver=$(detect_cachyos_nvidia_upstream_version)
        local req_ver
        req_ver=$(basename "${filename}" | sed -E 's/NVIDIA-Linux-x86_64-([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/')
        if [ -n "${cachy_nv_ver}" ] && [ -n "${req_ver}" ]; then
            local is_newer
            is_newer=$(python3 -c "
import sys, re
def p(v): return [int(x) for x in re.sub(r'[^0-9.]', '', v).split('.') if x.isdigit()]
sys.exit(0 if p('$req_ver') > p('$cachy_nv_ver') else 1)
" && echo "true" || echo "false")
            if [ "${is_newer}" = "true" ]; then
                log_warn "WARNING: You have CachyOS kernels installed."
                log_warn "The requested NVIDIA driver (${req_ver}) is newer than CachyOS upstream (${cachy_nv_ver})."
                log_warn "Installing standalone user-space will cause an API mismatch crash on CachyOS kernels!"
                echo ""
                read -r -p "Would you like to cancel and run safe CachyOS-Master synchronization instead? [Y/n] " cancel_choice
                cancel_choice=${cancel_choice:-Y}
                if [[ "$cancel_choice" =~ ^[YyJjSsOo]$ ]]; then
                    log_info "Redirecting to CachyOS-Master synchronization..."
                    ensure_cachyos_nvidia_duties || return 1
                    return 0
                fi
            fi
        fi
    fi

    # 6A-134: a caller that already downloaded and verified the installer (rollback) passes it as the second argument
    if [ -n "${prefetched}" ] && sudo test -x "${prefetched}"; then
        target_file="${prefetched}"
    else
        nvidia_fetch_verified_run "${url}" "${target_file}" "${branch}" || return 1
    fi

    log_info "Executing NVIDIA driver installer with DKMS..."
    if sudo "${target_file}" --silent --dkms 2>/dev/null || sudo "${target_file}" -s --dkms; then
        log_success "NVIDIA driver installation completed successfully."
    else
        # 6A-132 (F4): nouveau is no longer blacklisted before this point, so a failed install leaves a working screen
        log_error "The NVIDIA driver installer failed, so nouveau was kept; see /var/log/nvidia-installer.log."
        return 1
    fi

    local nv_rc=0
    build_nvidia_modules "ALL" || nv_rc=1
    # 6A-132: blacklist nouveau only now that the driver exists for every kept kernel
    configure_nvidia_modprobe || true
    enforce_secure_boot_armor
    register_flatpak_gl_sync "${req_ver:-}"
    return "${nv_rc}"
}

# --- [ MULTI-KERNEL MODULE COMPILATION ] ---
build_nvidia_modules() {
    local target_kver="$1"
    # 6A-132: the opt-out file is honoured here too (a registered DKMS driver of any generation is otherwise rebuilt)
    if [ -e "${NVIDIA_OPTOUT_FILE}" ]; then
        nvidia_generation_supported || true
        return 0
    fi
    validate_privileges

    local dkms_bin
    dkms_bin=$(command -v dkms 2>/dev/null || echo "/usr/sbin/dkms")
    if [ ! -x "${dkms_bin}" ]; then
        log_info "DKMS utility not detected on system."
        if [ "${HAS_NVIDIA}" = "true" ]; then
            log_warn "Tip: Installing DKMS (slackpkg install dkms) enables automated NVIDIA rebuilds on kernel updates."
        fi
        return 0
    fi

    local dkms_status
    dkms_status=$("${dkms_bin}" status 2>/dev/null || true)
    if ! echo "${dkms_status}" | grep -qi "nvidia"; then
        log_info "No registered NVIDIA DKMS module found."
        return 0
    fi

    local target_ver
    target_ver=$(detect_cachyos_nvidia_upstream_version 2>/dev/null || echo "")
    if [ -z "${target_ver}" ] && [ -f "/sys/module/nvidia/version" ]; then
        target_ver=$(cat /sys/module/nvidia/version 2>/dev/null | tr -d '[:space:]' || echo "")
    fi

    if [ "${target_kver}" = "ALL" ]; then
        log_info "Rebuilding NVIDIA DKMS modules for installed Slackware kernels..."
        if [ -d "/lib/modules" ]; then
            for kdir in /lib/modules/*; do
                [ -d "${kdir}" ] || continue
                local kver
                kver=$(basename "${kdir}")
                [ -f "${kdir}/modules.dep" ] || [ -d "${kdir}/kernel" ] || [ -d "${kdir}/extramodules" ] || continue

                local existing_mod
                existing_mod=$(find -L "${kdir}" -name "nvidia.ko*" 2>/dev/null | head -n 1 || true)
                if [ -n "${existing_mod}" ] && [ -n "${target_ver}" ]; then
                    local cur_v
                    cur_v=$(get_nvidia_module_version "${existing_mod}")
                    if [ "${cur_v}" = "${target_ver}" ]; then
                        log_info "Kernel ${kver} already has matching NVIDIA module (v${cur_v}). Ensuring DKMS registration."
                        register_precompiled_nvidia_in_dkms "${kver}" "${target_ver}"
                        continue
                    fi
                fi

                if [[ "${kver}" =~ -rc ]]; then
                    log_warn "Skipping DKMS build for CachyOS RC kernel (${kver}); RC kernels require precompiled open modules."
                    continue
                fi

                log_info "Building NVIDIA DKMS modules for kernel: ${kver}..."
                sudo "${dkms_bin}" autoinstall -k "${kver}" >/dev/null 2>&1 || log_warn "DKMS build warning for kernel: ${kver}"
            done
        fi
    else
        local existing_mod
        existing_mod=$(find -L "/lib/modules/${target_kver}" "/usr/lib/modules/${target_kver}" -name "nvidia.ko*" 2>/dev/null | head -n 1 || true)
        if [ -n "${existing_mod}" ] && [ -n "${target_ver}" ]; then
            local cur_v
            cur_v=$(get_nvidia_module_version "${existing_mod}")
            if [ "${cur_v}" = "${target_ver}" ]; then
                log_info "Kernel ${target_kver} already has matching NVIDIA module (v${cur_v}). Ensuring DKMS registration."
                register_precompiled_nvidia_in_dkms "${target_kver}" "${target_ver}"
                return 0
            fi
        fi

        if [[ "${target_kver}" =~ -rc ]]; then
            log_warn "Skipping DKMS build for CachyOS RC kernel (${target_kver}); RC kernels require precompiled open modules."
            return 0
        fi

        log_info "Building NVIDIA DKMS modules for kernel: ${target_kver}..."
        # 6A-44: success only when the module really exists afterwards (a failed build was reported as completed)
        local built_ok=1
        sudo "${dkms_bin}" autoinstall -k "${target_kver}" >/dev/null 2>&1 || built_ok=0
        if [ -z "$(find -L "/lib/modules/${target_kver}" "/usr/lib/modules/${target_kver}" -name 'nvidia.ko*' 2>/dev/null | head -n 1)" ]; then
            built_ok=0
        fi
        if [ "${built_ok}" -eq 0 ]; then
            log_warn "The graphics driver could not be built for kernel ${target_kver}, so the screen may stay black on that kernel."
            return 1
        fi
    fi

    log_success "NVIDIA module compilation phase completed."
}

# --- [ FLATPAK GL SYNCHRONIZATION ] ---
register_flatpak_gl_sync() {
    local target_ver="${1:-}"
    if ! command -v flatpak >/dev/null 2>&1; then
        return 0
    fi

    if [ -z "${target_ver}" ]; then
        if [ -f "/sys/module/nvidia/version" ]; then
            target_ver=$(cat /sys/module/nvidia/version 2>/dev/null || true)
        elif command -v nvidia-smi >/dev/null 2>&1; then
            target_ver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n 1 || true)
        elif command -v detect_cachyos_nvidia_upstream_version >/dev/null 2>&1; then
            target_ver=$(detect_cachyos_nvidia_upstream_version 2>/dev/null || true)
        fi
    fi

    # Targeted Verification & Synchronization: Check if runtime is needed and missing
    if [ -n "${target_ver}" ]; then
        local ver_clean
        ver_clean=$(echo "${target_ver}" | sed -E 's/^[^0-9]*([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/')
        if [ -n "${ver_clean}" ]; then
            local ver_dash
            ver_dash=$(echo "${ver_clean}" | tr '.' '-')

            local installed_runtimes
            installed_runtimes=$(flatpak list --runtime --columns=application 2>/dev/null || true)

            local has_32bit_flatpaks="false"
            if echo "${installed_runtimes}" | grep -q "org.freedesktop.Platform.GL32"; then
                has_32bit_flatpaks="true"
            fi

            local pkgs_to_install=()
            if ! echo "${installed_runtimes}" | grep -qE "^org\.freedesktop\.Platform\.GL\.nvidia-${ver_dash}$"; then
                pkgs_to_install+=("org.freedesktop.Platform.GL.nvidia-${ver_dash}")
            fi
            if [ "${has_32bit_flatpaks}" = "true" ]; then
                if ! echo "${installed_runtimes}" | grep -qE "^org\.freedesktop\.Platform\.GL32\.nvidia-${ver_dash}$"; then
                    pkgs_to_install+=("org.freedesktop.Platform.GL32.nvidia-${ver_dash}")
                fi
            fi

            if [ "${#pkgs_to_install[@]}" -gt 0 ]; then
                log_info "Pre-fetching Flatpak NVIDIA GL runtimes for driver ${ver_clean} (nvidia-${ver_dash})..."
                log_info "Downloading Flatpak runtimes in advance: ${pkgs_to_install[*]}"
                flatpak install -y --non-interactive flathub "${pkgs_to_install[@]}" 2>/dev/null || \
                flatpak install -y --non-interactive --system flathub "${pkgs_to_install[@]}" 2>/dev/null || {
                    log_warn "Flatpak runtime pre-fetch from Flathub deferred (runtime may not be published yet; will auto-heal after reboot)."
                }
            else
                log_info "Matching Flatpak NVIDIA GL runtime (nvidia-${ver_dash}) is already installed and verified."
            fi
        fi
    fi
}

# --- [ CACHYOS-MASTER NVIDIA DUALITY & SYNCHRONIZATION ] ---

has_cachyos_kernels_installed() {
    if ls /boot/vmlinuz*cachyos* 1>/dev/null 2>&1 || ls -d /lib/modules/*cachyos* 1>/dev/null 2>&1; then
        echo "true"
    else
        echo "false"
    fi
}
get_cachyos_nvidia_repo_url() {
    local tier="${SLACKY_CPU_TIER:-generic}"
    if [ "${tier}" = "generic" ] && command -v detect_cpu_tier >/dev/null 2>&1; then
        tier=$(detect_cpu_tier)
    fi
    if command -v get_cachyos_repo_url >/dev/null 2>&1; then
        get_cachyos_repo_url "${tier}"
    else
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
    fi
}

detect_cachyos_nvidia_upstream_version() {
    local gpu_arch="MODERN"
    if command -v detect_nvidia_gpu >/dev/null 2>&1; then
        gpu_arch=$(detect_nvidia_gpu)
    fi

    local cachy_repo
    cachy_repo=$(get_cachyos_nvidia_repo_url)
    local ver=""
    if [ "${gpu_arch}" = "PASCAL" ]; then
        ver=$(curl -sSL -m 10 "${cachy_repo}" 2>/dev/null | grep -o -E 'nvidia-580xx-utils-[0-9]+\.[0-9]+(\.[0-9]+)?' | sed 's/nvidia-580xx-utils-//' | sort -V | tail -n 1 || echo "")
        # 6A-312 (V3): no stale made-up version when the lookup fails (it vanishes once CachyOS prunes it); empty = unknown
    else
        ver=$(curl -sSL -m 10 "${cachy_repo}" 2>/dev/null | grep -o -E 'nvidia-utils-[0-9]+\.[0-9]+(\.[0-9]+)?' | sed 's/nvidia-utils-//' | sort -V | tail -n 1 || echo "")
    fi
    echo "${ver}"
}

# 6A-287 (M8): older NVIDIA driver packages (SBo or other) that own the same files. We never move or edit their package
# database records; the user removes them with removepkg and runs the update again. Read-only; PKGDB_DIR is for tests.
nvidia_legacy_pkg_check() {
    local ppath pbname found=()
    for ppath in "${PKGDB_DIR:-/var/log/packages}"/{nvidia-driver,nvidia-kernel,nvidia-utils,x11-nvidia-driver}-[0-9]*; do
        [ -f "${ppath}" ] || continue
        pbname=$(basename "${ppath}")
        case "${pbname%-*-*-*}" in
            nvidia-driver|nvidia-kernel|nvidia-utils|x11-nvidia-driver) found+=("${pbname}") ;;
        esac
    done
    [ "${#found[@]}" -eq 0 ] && return 0
    log_error "An older NVIDIA driver package is installed (${found[*]}). Remove it with: sudo removepkg ${found[*]} and run the update again. Nothing was installed."
    return 1
}

build_and_deploy_cachyos_nvidia_userspace() {
    nvidia_legacy_pkg_check || return 1
    local target_ver="$1"
    local gpu_arch="MODERN"
    if command -v detect_nvidia_gpu >/dev/null 2>&1; then
        gpu_arch=$(detect_nvidia_gpu)
    fi

    local cachy_repo
    cachy_repo=$(get_cachyos_nvidia_repo_url)
    local html
    html=$(curl -sSL -m 15 "${cachy_repo}" 2>/dev/null || echo "")
    if [ -z "${html}" ]; then
        log_warn "Could not connect to CachyOS mirror to fetch NVIDIA user-space packages."
        return 1
    fi

    local pkg_utils pkg_lib32 pkg_settings pkg_opencl pkg_lib32_opencl
    if [ "${gpu_arch}" = "PASCAL" ]; then
        pkg_utils=$(echo "${html}" | grep -o -E 'href="nvidia-580xx-utils-'${target_ver}'-[^"]*\.pkg\.tar\.zst"' | head -n 1 | cut -d'"' -f2 || echo "")
        pkg_lib32=$(echo "${html}" | grep -o -E 'href="lib32-nvidia-580xx-utils-'${target_ver}'-[^"]*\.pkg\.tar\.zst"' | head -n 1 | cut -d'"' -f2 || echo "")
        pkg_settings=$(echo "${html}" | grep -o -E 'href="nvidia-settings-[^"]*\.pkg\.tar\.zst"' | head -n 1 | cut -d'"' -f2 || echo "")
        pkg_opencl=$(echo "${html}" | grep -o -E 'href="opencl-nvidia-580xx-'${target_ver}'-[^"]*\.pkg\.tar\.zst"' | head -n 1 | cut -d'"' -f2 || echo "")
        pkg_lib32_opencl=$(echo "${html}" | grep -o -E 'href="lib32-opencl-nvidia-580xx-'${target_ver}'-[^"]*\.pkg\.tar\.zst"' | head -n 1 | cut -d'"' -f2 || echo "")
    else
        pkg_utils=$(echo "${html}" | grep -o -E 'href="nvidia-utils-'${target_ver}'-[^"]*\.pkg\.tar\.zst"' | head -n 1 | cut -d'"' -f2 || echo "")
        pkg_lib32=$(echo "${html}" | grep -o -E 'href="lib32-nvidia-utils-'${target_ver}'-[^"]*\.pkg\.tar\.zst"' | head -n 1 | cut -d'"' -f2 || echo "")
        pkg_settings=$(echo "${html}" | grep -o -E 'href="nvidia-settings-[^"]*\.pkg\.tar\.zst"' | head -n 1 | cut -d'"' -f2 || echo "")
        pkg_opencl=$(echo "${html}" | grep -o -E 'href="opencl-nvidia-'${target_ver}'-[^"]*\.pkg\.tar\.zst"' | head -n 1 | cut -d'"' -f2 || echo "")
        pkg_lib32_opencl=$(echo "${html}" | grep -o -E 'href="lib32-opencl-nvidia-'${target_ver}'-[^"]*\.pkg\.tar\.zst"' | head -n 1 | cut -d'"' -f2 || echo "")
    fi

    # Resolve libva-nvidia-driver (CachyOS mirror or Arch Linux official extra repository)
    local pkg_libva=""
    local libva_url=""
    pkg_libva=$(echo "${html}" | grep -o -E 'href="libva-nvidia-driver-[^"]*\.pkg\.tar\.zst"' | head -n 1 | cut -d'"' -f2 || echo "")
    if [ -n "${pkg_libva}" ]; then
        libva_url="${cachy_repo}/${pkg_libva}"
    else
        local arch_extra_repo="https://geo.mirror.pkgbuild.com/extra/os/x86_64"
        local arch_html
        arch_html=$(curl -sSL -m 15 "${arch_extra_repo}/" 2>/dev/null || echo "")
        pkg_libva=$(echo "${arch_html}" | grep -o -E 'href="libva-nvidia-driver-[0-9][^"]*\.pkg\.tar\.zst"' | head -n 1 | cut -d'"' -f2 || echo "")
        if [ -n "${pkg_libva}" ]; then
            libva_url="${arch_extra_repo}/${pkg_libva}"
        fi
    fi

    # Resolve egl-gbm (NVIDIA GBM external platform bridge for Xwayland GLAMOR & KWin)
    local pkg_egl_gbm=""
    local egl_gbm_url=""
    pkg_egl_gbm=$(echo "${html}" | grep -o -E 'href="egl-gbm-[^"]*\.pkg\.tar\.zst"' | head -n 1 | cut -d'"' -f2 || echo "")
    if [ -n "${pkg_egl_gbm}" ]; then
        egl_gbm_url="${cachy_repo}/${pkg_egl_gbm}"
    else
        local arch_extra_repo="https://geo.mirror.pkgbuild.com/extra/os/x86_64"
        local arch_html
        arch_html=$(curl -sSL -m 15 "${arch_extra_repo}/" 2>/dev/null || echo "")
        pkg_egl_gbm=$(echo "${arch_html}" | grep -o -E 'href="egl-gbm-[0-9][^"]*\.pkg\.tar\.zst"' | head -n 1 | cut -d'"' -f2 || echo "")
        if [ -n "${pkg_egl_gbm}" ]; then
            egl_gbm_url="${arch_extra_repo}/${pkg_egl_gbm}"
        fi
    fi

    if [ -z "${pkg_utils}" ]; then
        log_warn "Could not resolve matching nvidia user-space (${target_ver}) from CachyOS repository."
        return 1
    fi

    local staging_base
    staging_base=$(mktemp -d "$(get_user_staging_dir)/cachy-nv-${target_ver}.XXXXXX" 2>/dev/null || mktemp -d /tmp/slacky-cachy-nv.XXXXXX)
    local cache_dir="${staging_base}/downloads"
    local staging_root="${staging_base}/pkg"
    local tmp_extract="${staging_base}/extract"
    trap 'rm -rf "${staging_base:-}" 2>/dev/null || true' INT TERM

    mkdir -p "${cache_dir}" \
             "${staging_root}" \
             "${tmp_extract}/utils" \
             "${tmp_extract}/lib32" \
             "${tmp_extract}/settings" \
             "${tmp_extract}/opencl" \
             "${tmp_extract}/lib32_opencl" \
             "${tmp_extract}/libva" \
             "${tmp_extract}/egl_gbm"

    log_info "Downloading CachyOS NVIDIA Complete Suite components (${target_ver}) to user staging..."
    local download_list=("${pkg_utils}")
    [ -n "${pkg_lib32}" ] && download_list+=("${pkg_lib32}")
    [ -n "${pkg_settings}" ] && download_list+=("${pkg_settings}")
    [ -n "${pkg_opencl}" ] && download_list+=("${pkg_opencl}")
    [ -n "${pkg_lib32_opencl}" ] && download_list+=("${pkg_lib32_opencl}")

    local dl_items=()
    for pkg_item in "${download_list[@]}"; do
        dl_items+=("${cachy_repo}/${pkg_item}|${cache_dir}/${pkg_item}|${cachy_repo}/${pkg_item}.sig|${cache_dir}/${pkg_item}.sig")
    done
    if [ -n "${pkg_libva}" ] && [ -n "${libva_url}" ]; then
        dl_items+=("${libva_url}|${cache_dir}/${pkg_libva}|${libva_url}.sig|${cache_dir}/${pkg_libva}.sig")
    fi
    if [ -n "${pkg_egl_gbm}" ] && [ -n "${egl_gbm_url}" ]; then
        dl_items+=("${egl_gbm_url}|${cache_dir}/${pkg_egl_gbm}|${egl_gbm_url}.sig|${cache_dir}/${pkg_egl_gbm}.sig")
    fi

    if ! download_parallel_pacman "CachyOS NVIDIA Driver Suite (${target_ver})" "${dl_items[@]}"; then
        log_error "Failed to download NVIDIA suite components."
        rm -rf "${staging_base}"
        trap - INT TERM
        return 1
    fi

    for pkg_item in "${download_list[@]}"; do
        if ! verify_cachyos_gpg_signature "${cache_dir}/${pkg_item}" "${cache_dir}/${pkg_item}.sig" "${cachy_repo}/${pkg_item}"; then
            log_error "GPG verification failed for ${pkg_item}! Aborting user-space staging build."
            rm -rf "${staging_base}"
            trap - INT TERM
            return 1
        fi
    done

    if [ -n "${pkg_libva}" ] && [ -n "${libva_url}" ]; then
        if ! verify_cachyos_gpg_signature "${cache_dir}/${pkg_libva}" "${cache_dir}/${pkg_libva}.sig" "${libva_url}"; then
            log_error "GPG verification failed for ${pkg_libva}! Aborting."
            rm -rf "${staging_base}"
            trap - INT TERM
            return 1
        fi
    fi

    if [ -n "${pkg_egl_gbm}" ] && [ -n "${egl_gbm_url}" ]; then
        if ! verify_cachyos_gpg_signature "${cache_dir}/${pkg_egl_gbm}" "${cache_dir}/${pkg_egl_gbm}.sig" "${egl_gbm_url}"; then
            log_error "GPG verification failed for ${pkg_egl_gbm}! Aborting."
            rm -rf "${staging_base}"
            trap - INT TERM
            return 1
        fi
    fi

    log_info "Unpacking and mapping Complete Suite in user staging..."
    # 6A-134 (B-M8): the core package must unpack, or nothing is built
    if ! tar --zstd -xf "${cache_dir}/${pkg_utils}" -C "${tmp_extract}/utils" 2>/dev/null; then
        log_error "The NVIDIA userspace package ${pkg_utils} could not be unpacked, so nothing was installed."
        rm -rf "${staging_base}"
        trap - INT TERM
        return 1
    fi
    [ -n "${pkg_lib32}" ] && [ -f "${cache_dir}/${pkg_lib32}" ] && tar --zstd -xf "${cache_dir}/${pkg_lib32}" -C "${tmp_extract}/lib32" 2>/dev/null || true
    [ -n "${pkg_settings}" ] && [ -f "${cache_dir}/${pkg_settings}" ] && tar --zstd -xf "${cache_dir}/${pkg_settings}" -C "${tmp_extract}/settings" 2>/dev/null || true
    [ -n "${pkg_opencl}" ] && [ -f "${cache_dir}/${pkg_opencl}" ] && tar --zstd -xf "${cache_dir}/${pkg_opencl}" -C "${tmp_extract}/opencl" 2>/dev/null || true
    [ -n "${pkg_lib32_opencl}" ] && [ -f "${cache_dir}/${pkg_lib32_opencl}" ] && tar --zstd -xf "${cache_dir}/${pkg_lib32_opencl}" -C "${tmp_extract}/lib32_opencl" 2>/dev/null || true
    [ -n "${pkg_libva}" ] && [ -f "${cache_dir}/${pkg_libva}" ] && tar --zstd -xf "${cache_dir}/${pkg_libva}" -C "${tmp_extract}/libva" 2>/dev/null || true
    [ -n "${pkg_egl_gbm}" ] && [ -f "${cache_dir}/${pkg_egl_gbm}" ] && tar --zstd -xf "${cache_dir}/${pkg_egl_gbm}" -C "${tmp_extract}/egl_gbm" 2>/dev/null || true

    # Prepare Slackware structure:
    # 64-bit -> /usr/lib64
    # 32-bit -> /usr/lib
    mkdir -p "${staging_root}/usr/bin" \
             "${staging_root}/usr/lib64/dri" \
             "${staging_root}/usr/lib" \
             "${staging_root}/usr/share" \
             "${staging_root}/etc/OpenCL/vendors" \
             "${staging_root}/etc/profile.d" \
             "${staging_root}/lib/firmware/nvidia/${target_ver}" \
             "${staging_root}/install"

    # 1. Map nvidia-utils (64-bit Core)
    if [ -d "${tmp_extract}/utils/usr/bin" ]; then
        cp -a "${tmp_extract}/utils/usr/bin/." "${staging_root}/usr/bin/"
    fi
    if [ -d "${tmp_extract}/utils/usr/share" ]; then
        cp -a "${tmp_extract}/utils/usr/share/." "${staging_root}/usr/share/"
    fi
    if [ -d "${tmp_extract}/utils/etc" ]; then
        cp -a "${tmp_extract}/utils/etc/." "${staging_root}/etc/"
    fi
    if [ -d "${tmp_extract}/utils/usr/lib/firmware/nvidia" ]; then
        cp -a "${tmp_extract}/utils/usr/lib/firmware/nvidia/." "${staging_root}/lib/firmware/nvidia/"
    fi
    if [ -d "${tmp_extract}/utils/usr/lib" ]; then
        (
            cd "${tmp_extract}/utils/usr/lib"
            find . -maxdepth 1 ! -name "." ! -name "environment.d" ! -name "firmware" -exec cp -a {} "${staging_root}/usr/lib64/" \;
        )
    fi

    # 2. Map lib32-nvidia-utils (32-bit multilib Core) -> Slackware /usr/lib
    if [ -d "${tmp_extract}/lib32/usr/lib32" ]; then
        (
            cd "${tmp_extract}/lib32/usr/lib32"
            find . -maxdepth 1 ! -name "." -exec cp -a {} "${staging_root}/usr/lib/" \;
        )
    fi

    # 3. Map nvidia-settings
    if [ -d "${tmp_extract}/settings/usr/bin" ]; then
        cp -a "${tmp_extract}/settings/usr/bin/." "${staging_root}/usr/bin/"
    fi
    if [ -d "${tmp_extract}/settings/usr/share" ]; then
        cp -a "${tmp_extract}/settings/usr/share/." "${staging_root}/usr/share/"
    fi
    if [ -d "${tmp_extract}/settings/usr/lib" ]; then
        cp -a "${tmp_extract}/settings/usr/lib/." "${staging_root}/usr/lib64/"
    fi

    # 4. Map opencl-nvidia (64-bit OpenCL)
    if [ -d "${tmp_extract}/opencl/etc/OpenCL" ]; then
        cp -a "${tmp_extract}/opencl/etc/OpenCL/." "${staging_root}/etc/OpenCL/"
    fi
    if [ -d "${tmp_extract}/opencl/usr/lib" ]; then
        (
            cd "${tmp_extract}/opencl/usr/lib"
            find . -maxdepth 1 ! -name "." -exec cp -a {} "${staging_root}/usr/lib64/" \;
        )
    fi

    # 5. Map lib32-opencl-nvidia (32-bit OpenCL multilib) -> Slackware /usr/lib
    if [ -d "${tmp_extract}/lib32_opencl/usr/lib32" ]; then
        (
            cd "${tmp_extract}/lib32_opencl/usr/lib32"
            find . -maxdepth 1 ! -name "." -exec cp -a {} "${staging_root}/usr/lib/" \;
        )
    fi

    # 6. Map libva-nvidia-driver (VA-API NVDEC driver) -> /usr/lib64/dri/
    if [ -d "${tmp_extract}/libva/usr/lib/dri" ]; then
        cp -a "${tmp_extract}/libva/usr/lib/dri/." "${staging_root}/usr/lib64/dri/"
    fi

    # 7. Map egl-gbm (NVIDIA GBM external platform bridge for Xwayland GLAMOR & KWin)
    if [ -d "${tmp_extract}/egl_gbm/usr/lib" ]; then
        cp -a "${tmp_extract}/egl_gbm/usr/lib/libnvidia-egl-gbm"* "${staging_root}/usr/lib64/" 2>/dev/null || true
    fi
    if [ -d "${tmp_extract}/egl_gbm/usr/share/egl/egl_external_platform.d" ]; then
        mkdir -p "${staging_root}/usr/share/egl/egl_external_platform.d"
        cp -a "${tmp_extract}/egl_gbm/usr/share/egl/egl_external_platform.d/." "${staging_root}/usr/share/egl/egl_external_platform.d/"
    fi

    # 8. Patch Arch paths to Slackware 64-bit in Xorg OutputClass
    if [ -f "${staging_root}/usr/share/X11/xorg.conf.d/10-nvidia-drm-outputclass.conf" ]; then
        sed -i 's|/usr/lib/|/usr/lib64/|g' "${staging_root}/usr/share/X11/xorg.conf.d/10-nvidia-drm-outputclass.conf"
    fi

    # 8. Ensure Xorg extensions symlinks for GLX Server
    mkdir -p "${staging_root}/usr/lib64/xorg/modules/extensions"
    (
        cd "${staging_root}/usr/lib64/xorg/modules/extensions"
        ln -sf /usr/lib64/nvidia/xorg/libglxserver_nvidia.so.${target_ver} libglxserver_nvidia.so 2>/dev/null || true
        ln -sf /usr/lib64/nvidia/xorg/libglxserver_nvidia.so.${target_ver} libglxserver_nvidia.so.1 2>/dev/null || true
    )

    # 9. Remove Arch-specific throttling application profiles
    rm -f "${staging_root}/etc/nvidia/nvidia-application-profiles-rc.d/limit-vram-usage" 2>/dev/null || true

    # 10. Hardware video acceleration profile configuration
    # 6A-81: one helper decides for sh and csh alike (they disagreed before). NVIDIA VA-API variables only when the NVIDIA
    # card drives the display (boot_vga, read from sysfs: no lspci per login shell, and laptop dGPUs exposed as a
    # "3D controller" 0302 are seen), or when PRIME offload is asked for. Firefox's media sandbox is switched off only for
    # a user who turned on hardware video decoding in Firefox (it needs that for NVIDIA); everyone else keeps it.
    mkdir -p "${staging_root}/usr/libexec"
    cat << 'VA_ENV_EOF' > "${staging_root}/usr/libexec/cachyos-nvidia-vaapi-env"
#!/bin/sh
# Prints the NVIDIA VA-API environment for this machine as sh (default) or csh (argument "csh"). Read-only, fast.
fmt="${1:-sh}"
sys="${SLACKY_SYSFS_ROOT:-}/sys"
nv_display=0
for c in "${sys}"/bus/pci/devices/*/class; do
    cls=""; ven=""; boot=""
    read -r cls < "${c}" 2>/dev/null || continue
    case "${cls}" in 0x0300*|0x0302*|0x0380*) ;; *) continue ;; esac
    d="${c%/class}"
    read -r ven < "${d}/vendor" 2>/dev/null || continue
    [ "${ven}" = "0x10de" ] || continue
    read -r boot < "${d}/boot_vga" 2>/dev/null || boot=0
    [ "${boot}" = "1" ] && nv_display=1
done
want=0
[ "${nv_display}" = "1" ] && want=1
{ [ "${__NV_PRIME_RENDER_OFFLOAD:-0}" = "1" ] || [ "${DRI_PRIME:-0}" = "1" ]; } && want=1
[ "${want}" = "1" ] || exit 0
moz=0
for pf in "${HOME:-/nonexistent}"/.mozilla/firefox/*/prefs.js; do
    [ -r "${pf}" ] || continue
    if grep -qE 'user_pref\("media\.(hardware-video-decoding\.force-enabled|ffmpeg\.vaapi\.enabled)", true\)' "${pf}" 2>/dev/null; then
        moz=1; break
    fi
done
if [ "${fmt}" = "csh" ]; then
    echo "setenv LIBVA_DRIVER_NAME nvidia;"
    echo "setenv NVD_BACKEND direct;"
    [ "${moz}" = "1" ] && echo "setenv MOZ_DISABLE_RDD_SANDBOX 1;"
else
    echo "export LIBVA_DRIVER_NAME=nvidia"
    echo "export NVD_BACKEND=direct"
    [ "${moz}" = "1" ] && echo "export MOZ_DISABLE_RDD_SANDBOX=1"
fi
exit 0
VA_ENV_EOF
    chmod 755 "${staging_root}/usr/libexec/cachyos-nvidia-vaapi-env"

    cat << 'VA_SH_EOF' > "${staging_root}/etc/profile.d/nvidia-vaapi.sh"
#!/bin/sh
# NVIDIA VA-API hardware video acceleration (decided by /usr/libexec/cachyos-nvidia-vaapi-env, 6A-81)
if [ -x /usr/libexec/cachyos-nvidia-vaapi-env ]; then
    eval "$(/usr/libexec/cachyos-nvidia-vaapi-env sh)"
fi
VA_SH_EOF

    cat << 'VA_CSH_EOF' > "${staging_root}/etc/profile.d/nvidia-vaapi.csh"
#!/bin/csh
# NVIDIA VA-API hardware video acceleration (decided by /usr/libexec/cachyos-nvidia-vaapi-env, 6A-81)
if ( -x /usr/libexec/cachyos-nvidia-vaapi-env ) then
    eval `/usr/libexec/cachyos-nvidia-vaapi-env csh`
endif
VA_CSH_EOF

    chmod 755 "${staging_root}/etc/profile.d/nvidia-vaapi.sh" "${staging_root}/etc/profile.d/nvidia-vaapi.csh"

    # Clean Arch metadata
    rm -f "${staging_root}/.BUILDINFO" "${staging_root}/.INSTALL" "${staging_root}/.MTREE" "${staging_root}/.PKGINFO"

    # Write Slackware slack-desc
    cat << 'DESC_EOF' > "${staging_root}/install/slack-desc"
cachyos-nvidia-utils: cachyos-nvidia-utils (CachyOS NVIDIA Complete User-Space Suite)
cachyos-nvidia-utils:
cachyos-nvidia-utils: Official NVIDIA graphics libraries (OpenGL, Vulkan, CUDA,
cachyos-nvidia-utils: OpenCL, VA-API NVDEC driver, nvidia-smi, nvidia-settings)
cachyos-nvidia-utils: and 32-bit multilib runtimes (GL, Vulkan, CUDA, OpenCL),
cachyos-nvidia-utils: packaged directly from CachyOS repository for Slackware.
cachyos-nvidia-utils:
cachyos-nvidia-utils: Provides 100% synchronized user-space for CachyOS and
cachyos-nvidia-utils: Slackware kernels to prevent API mismatch.
cachyos-nvidia-utils:
cachyos-nvidia-utils: Maintained by slacky-update.
cachyos-nvidia-utils:
DESC_EOF

    # Write doinst.sh
    cat << 'DOINST_EOF' > "${staging_root}/install/doinst.sh"
mkdir -p /usr/lib64/xorg/modules/extensions
( cd /usr/lib64/xorg/modules/extensions ; rm -f libglxserver_nvidia.so libglxserver_nvidia.so.1 )
( cd /usr/lib64/xorg/modules/extensions ; ln -sf /usr/lib64/nvidia/xorg/libglxserver_nvidia.so libglxserver_nvidia.so )
( cd /usr/lib64/xorg/modules/extensions ; ln -sf /usr/lib64/nvidia/xorg/libglxserver_nvidia.so libglxserver_nvidia.so.1 )
if [ -x /sbin/ldconfig ]; then
  /sbin/ldconfig 2>/dev/null || true
fi
if [ -x /usr/bin/update-desktop-database ]; then
  /usr/bin/update-desktop-database /usr/share/applications 2>/dev/null || true
fi
if [ -x /usr/bin/gtk-update-icon-cache ]; then
  /usr/bin/gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
fi
DOINST_EOF
    chmod 755 "${staging_root}/install/doinst.sh"

    # Enforce standard permissions before packaging
    chmod -R u=rwX,go=rX "${staging_root}"

    # 6A-288 (S4): Footprint Guard on the final staging tree, as in the other packagers (enforce unless
    # SLACKY_FOOTPRINT_MODE=report). The NVIDIA files that must reach the host (profile.d VA-API) are on the guard's vetted list.
    if [ -n "${GNOMES_PY:-}" ] && [ -f "${GNOMES_PY}" ]; then
        if ! python3 "${GNOMES_PY}" footprint-guard "${staging_root}" --label "cachyos-nvidia-utils-${target_ver}"; then
            if [ "${SLACKY_FOOTPRINT_MODE:-enforce}" != "report" ]; then
                log_error "Footprint check failed for the NVIDIA userspace package. Package not built."
                rm -rf "${staging_base}"
                trap - INT TERM
                return 1
            fi
        fi
    elif [ "${SLACKY_FOOTPRINT_MODE:-enforce}" != "report" ]; then
        log_error "Footprint check unavailable (gnomes_pacman.py not found). Package not built."
        rm -rf "${staging_base}"
        trap - INT TERM
        return 1
    fi

    log_info "Assembling Slackware txz package: cachyos-nvidia-utils-${target_ver}..."
    local txz_out="${staging_base}/cachyos-nvidia-utils-${target_ver}-x86_64-1_slacky.txz"
    rm -f "${txz_out}"
    # 6A-134 (B-M8): a tar or xz failure fails the build (it was "|| true", and "[ -f ]" after the redirect was always
    # true, so a broken archive went to upgradepkg)
    local pack_ok=1
    (
        cd "${staging_root}"
        # 2C: root-owned archive (was built with the build user's ownership)
        find ./ | LC_COLLATE=C sort | sed '2,$s,^\./,,' | tar --owner=0 --group=0 --numeric-owner --mode='go+rX' --no-recursion -T - -cf - | xz -T0 -1 > "${txz_out}" 2>/dev/null
    ) || pack_ok=0
    if [ "${pack_ok}" -eq 1 ] && { [ ! -s "${txz_out}" ] || ! xz -t "${txz_out}" 2>/dev/null; }; then
        pack_ok=0
    fi

    # 6A-288 (S4): the finished archive must be root-owned and must not overwrite files of another package
    if [ "${pack_ok}" -eq 1 ] && [ "${SLACKY_FOOTPRINT_MODE:-enforce}" != "report" ]; then
        if [ -z "${GNOMES_PY:-}" ] || [ ! -f "${GNOMES_PY}" ] \
            || ! python3 "${GNOMES_PY}" footprint-guard --verify-archive "${txz_out}" \
            || ! python3 "${GNOMES_PY}" footprint-guard --verify-host-paths "${txz_out}" --mode curated; then
            log_error "The NVIDIA userspace package failed the footprint check, so nothing was installed."
            rm -rf "${staging_base}" 2>/dev/null || true
            trap - INT TERM
            return 1
        fi
    fi

    local deploy_rc=0
    if [ "${pack_ok}" -eq 1 ]; then
        chmod 644 "${txz_out}"

        # Root stage: Validate privileges and install
        validate_privileges

        # 6A-287 (M8): the package database is never edited. An older NVIDIA package (for example from SBo) is re-checked
        # right before the install; it must be removed by the user with removepkg.
        if ! nvidia_legacy_pkg_check; then
            rm -rf "${staging_base}" 2>/dev/null || true
            trap - INT TERM
            return 1
        fi

        log_info "Installing cachyos-nvidia-utils package to system..."
        if sudo "${PKG_UPGRADE_CMD}" --install-new --reinstall "${txz_out}"; then
            log_success "CachyOS NVIDIA Complete Suite package deployed: ${target_ver}"
        else
            log_error "The NVIDIA userspace package ${target_ver} could not be installed."
            deploy_rc=1
        fi
    else
        log_error "The NVIDIA userspace package ${target_ver} could not be built, so nothing was installed."
        deploy_rc=1
    fi

    rm -rf "${staging_base}" 2>/dev/null || true
    trap - INT TERM
    return "${deploy_rc}"
}

get_nvidia_module_version() {
    local mod="$1"
    [ -f "${mod}" ] || { echo "Unknown"; return 0; }
    local ver=""
    ver=$(modinfo -F version "${mod}" 2>/dev/null || true)
    if [ -z "${ver}" ] || [ "${ver}" = "Unknown" ]; then
        if [[ "${mod}" =~ \.ko\.zst$ ]]; then
            ver=$(unzstd -c "${mod}" 2>/dev/null | strings | grep -E '^version=[0-9]+\.[0-9]+' | cut -d'=' -f2 | head -n 1 || true)
        elif [[ "${mod}" =~ \.ko\.xz$ ]]; then
            ver=$(unxz -c "${mod}" 2>/dev/null | strings | grep -E '^version=[0-9]+\.[0-9]+' | cut -d'=' -f2 | head -n 1 || true)
        elif [[ "${mod}" =~ \.ko\.gz$ ]]; then
            ver=$(gunzip -c "${mod}" 2>/dev/null | strings | grep -E '^version=[0-9]+\.[0-9]+' | cut -d'=' -f2 | head -n 1 || true)
        else
            ver=$(strings "${mod}" 2>/dev/null | grep -E '^version=[0-9]+\.[0-9]+' | cut -d'=' -f2 | head -n 1 || true)
        fi
    fi
    echo "${ver:-Unknown}"
}

register_precompiled_nvidia_in_dkms() {
    local kver="$1"
    local target_ver="$2"
    local arch="${3:-x86_64}"

    [ -n "${kver}" ] || return 0
    [ -n "${target_ver}" ] || return 0

    local dkms_root="${DKMS_ROOT:-/var/lib/dkms}"
    local mod_base="${dkms_root}/nvidia"
    local ver_tree="${mod_base}/${target_ver}/${kver}/${arch}"
    local module_dir="${ver_tree}/module"
    local active_symlink="${mod_base}/kernel-${kver}-${arch}"
    local sudo_cmd="${DKMS_SUDO-sudo}"

    # Find precompiled nvidia modules installed on disk for this kernel
    local found_mods=()
    local p
    local mod_paths=()
    if [ -n "${MODULES_ROOT:-}" ]; then
        mod_paths+=("${MODULES_ROOT}/${kver}")
    fi
    mod_paths+=("/lib/modules/${kver}" "/usr/lib/modules/${kver}")
    for p in "${mod_paths[@]}"; do
        if [ -d "${p}" ]; then
            while IFS= read -r f; do
                [ -n "${f}" ] && found_mods+=("${f}")
            done < <(find "${p}" -name "nvidia*.ko*" 2>/dev/null || true)
        fi
    done

    if [ ${#found_mods[@]} -eq 0 ]; then
        log_info "No on-disk NVIDIA modules found for ${kver}; skipping DKMS registration."
        return 0
    fi

    # Create DKMS module and log directories
    ${sudo_cmd} mkdir -p "${module_dir}" "${ver_tree}/log" 2>/dev/null || true

    # Copy module binaries into DKMS module directory so DKMS is_module_built succeeds
    local mod_file
    for mod_file in "${found_mods[@]}"; do
        local bname
        bname=$(basename "${mod_file}")
        if [[ "${bname}" =~ ^nvidia(-modeset|-drm|-uvm|-peermem)?\.ko(\.zst|\.xz|\.gz)?$ ]]; then
            ${sudo_cmd} cp -af "${mod_file}" "${module_dir}/${bname}" 2>/dev/null || true
        fi
    done

    # Ensure DKMS canonical DEST_MODULE_LOCATION (/kernel/drivers/video) is symlinked to extramodules
    for p in "${mod_paths[@]}"; do
        if [ -d "${p}/extramodules" ]; then
            ${sudo_cmd} mkdir -p "${p}/kernel/drivers/video" 2>/dev/null || true
            for mod in "${p}/extramodules"/nvidia*.ko*; do
                if [ -f "${mod}" ]; then
                    local bname
                    bname=$(basename "${mod}")
                    ${sudo_cmd} ln -sf "${mod}" "${p}/kernel/drivers/video/${bname}" 2>/dev/null || true
                fi
            done
        fi
    done

    # Create dummy make.log so DKMS status sees clean build logs
    if [ ! -f "${ver_tree}/log/make.log" ]; then
        echo "Precompiled CachyOS NVIDIA module registration (v${target_ver}) for kernel ${kver}" | ${sudo_cmd} tee "${ver_tree}/log/make.log" >/dev/null 2>&1 || true
    fi

    # Create active kernel symlink: /var/lib/dkms/nvidia/kernel-<kver>-<arch> -> <ver>/<kver>/<arch>
    ${sudo_cmd} rm -f "${active_symlink}" 2>/dev/null || true
    ${sudo_cmd} ln -s "${target_ver}/${kver}/${arch}" "${active_symlink}" 2>/dev/null || true

    # Ensure source directory symlink /var/lib/dkms/nvidia/<ver>/source -> /usr/src/nvidia-<ver>
    if [ -d "/usr/src/nvidia-${target_ver}" ] && [ ! -e "${mod_base}/${target_ver}/source" ]; then
        ${sudo_cmd} ln -s "/usr/src/nvidia-${target_ver}" "${mod_base}/${target_ver}/source" 2>/dev/null || true
    fi

    log_success "Registered precompiled NVIDIA v${target_ver} modules in DKMS for kernel ${kver}."
    return 0
}

# 6A-302 (F0b): true only when kernel <kver> has an nvidia module file AND modinfo reports exactly <expected> for it.
# depmod is refreshed first so "modinfo -k" sees the new files. Prints nothing.
nvidia_module_landed() {
    local kver="${1:-}" expected="${2:-}" mod got
    [ -n "${kver}" ] && [ -n "${expected}" ] || return 1
    mod=$(find -L "${NVIDIA_MODROOT:-/lib/modules}/${kver}" -name "nvidia.ko*" 2>/dev/null | head -n 1 || true)
    [ -n "${mod}" ] || return 1
    sudo "${DEPMOD_CMD:-depmod}" -a "${kver}" >/dev/null 2>&1 || true
    got=$(modinfo -k "${kver}" -F version nvidia 2>/dev/null | head -n 1 || true)
    [ -n "${got}" ] || got=$(get_nvidia_module_version "${mod}")
    [ "${got}" = "${expected}" ]
}

# 6A-302 (F0b): kernels whose NVIDIA module failed to arrive are listed here; the boot menu leaves them out while the
# module is still missing (see nvidia_hold_active), so they cannot become the default. A later good run clears the entry.
NVIDIA_HOLD_FILE="${NVIDIA_HOLD_FILE:-/var/lib/slacky-boot/nvidia-hold}"
nvidia_hold_set() {
    local kver="${1:-}"
    [ -n "${kver}" ] || return 0
    grep -qxF "${kver}" "${NVIDIA_HOLD_FILE}" 2>/dev/null && return 0
    sudo mkdir -p "$(dirname "${NVIDIA_HOLD_FILE}")" 2>/dev/null || true
    echo "${kver}" | sudo tee -a "${NVIDIA_HOLD_FILE}" >/dev/null 2>&1 || true
}
nvidia_hold_clear() {
    local kver="${1:-}"
    [ -n "${kver}" ] && [ -f "${NVIDIA_HOLD_FILE}" ] || return 0
    grep -qxF "${kver}" "${NVIDIA_HOLD_FILE}" 2>/dev/null || return 0
    local keep
    keep=$(grep -vxF "${kver}" "${NVIDIA_HOLD_FILE}" 2>/dev/null || true)
    printf '%s\n' "${keep}" | sudo tee "${NVIDIA_HOLD_FILE}" >/dev/null 2>&1 || true
}
# Held kernels that STILL have no nvidia module, one per line (a repaired kernel is released automatically).
nvidia_hold_active() {
    local k
    [ -f "${NVIDIA_HOLD_FILE}" ] || return 0
    while IFS= read -r k; do
        [ -n "${k}" ] || continue
        [ -n "$(find -L "${NVIDIA_MODROOT:-/lib/modules}/${k}" -name 'nvidia.ko*' 2>/dev/null | head -n 1)" ] && continue
        echo "${k}"
    done < "${NVIDIA_HOLD_FILE}"
}

prune_stale_nvidia_modules_for_kernel() {
    local target_kver="$1"
    local target_ver="$2"
    [ -n "${target_kver}" ] || return 0
    [ -n "${target_ver}" ] || return 0

    local pruned_any=0
    local dirs_to_check=()
    [ -d "/lib/modules/${target_kver}" ] && dirs_to_check+=("/lib/modules/${target_kver}")
    [ -d "/usr/lib/modules/${target_kver}" ] && dirs_to_check+=("/usr/lib/modules/${target_kver}")

    # Remove conflicting duplicate modules silently ONLY when target module is confirmed present
    for d in "${dirs_to_check[@]}"; do
        [ -d "${d}" ] || continue
        local all_mods=()
        mapfile -t all_mods < <(find "${d}" -name "nvidia.ko*" 2>/dev/null || true)
        [ "${#all_mods[@]}" -gt 1 ] || continue

        local has_target=0
        for m in "${all_mods[@]}"; do
            local mv
            mv=$(get_nvidia_module_version "${m}")
            if [ "${mv}" = "${target_ver}" ]; then
                has_target=1
                break
            fi
        done

        if [ "${has_target}" -eq 1 ]; then
            for m in "${all_mods[@]}"; do
                local mv
                mv=$(get_nvidia_module_version "${m}")
                if [ "${mv}" != "${target_ver}" ]; then
                    local mdir
                    mdir=$(dirname "${m}")
                    sudo rm -f "${mdir}"/nvidia*.ko* 2>/dev/null || true
                    pruned_any=1
                fi
            done
        fi
    done

    if [ "${pruned_any}" -eq 1 ]; then
        sudo "${DEPMOD_CMD:-depmod}" -a "${target_kver}" 2>/dev/null || true
    fi
}

sync_stock_kernel_nvidia_module() {
    local stock_kver="$1"
    local cachy_nv_ver="$2"

    [ -n "${stock_kver}" ] || return 0
    [ -n "${cachy_nv_ver}" ] || return 0
    # 6A-131: no nvidia-open or 580xx DKMS source for a card this tool does not manage
    nvidia_generation_supported || return 0

    # Check if stock kernel already has matching nvidia.ko module version
    local existing_mod
    existing_mod=$(find "/lib/modules/${stock_kver}" "/usr/lib/modules/${stock_kver}" -name "nvidia.ko*" 2>/dev/null | head -n 1 || true)
    if [ -n "${existing_mod}" ]; then
        local cur_mod_ver
        cur_mod_ver=$(get_nvidia_module_version "${existing_mod}")
        if [ "${cur_mod_ver}" = "${cachy_nv_ver}" ]; then
            return 0
        fi
    fi

    local gpu_arch="MODERN"
    if command -v detect_nvidia_gpu >/dev/null 2>&1; then
        gpu_arch=$(detect_nvidia_gpu)
    fi

    local cachy_repo
    cachy_repo=$(get_cachyos_nvidia_repo_url | sed 's|/*$||')
    local staging_dir
    staging_dir="$(get_user_staging_dir)/dkms"
    mkdir -p "${staging_dir}"

    local dkms_pkg=""
    local dkms_name="nvidia"
    local dkms_ver="${cachy_nv_ver}"

    if [ "${gpu_arch}" = "PASCAL" ]; then
        # Pascal GTX 10-series uses nvidia-580xx-dkms
        local phtml
        phtml=$(curl -sSL --connect-timeout 15 -m 30 "${cachy_repo}/" 2>/dev/null || echo "")
        dkms_pkg=$(echo "${phtml}" | grep -o -E 'nvidia-580xx-dkms-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst' | head -n 1 || echo "")
        dkms_name="nvidia"
        dkms_ver=$(echo "${dkms_pkg}" | grep -o -E '580\.[0-9]+(\.[0-9]+)?' | head -n 1 || echo "580.178.04")
    else
        # Modern Turing+ RTX series uses nvidia-open-dkms
        local mhtml
        mhtml=$(curl -sSL --connect-timeout 15 -m 30 "${cachy_repo}/" 2>/dev/null || echo "")
        dkms_pkg=$(echo "${mhtml}" | grep -o -E 'nvidia-open-dkms-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst' | head -n 1 || echo "")
        dkms_name="nvidia"
    fi

    if [ -n "${dkms_pkg}" ]; then
        local dkms_archive="${staging_dir}/${dkms_pkg}"
        local dkms_items=("${cachy_repo}/${dkms_pkg}|${dkms_archive}|${cachy_repo}/${dkms_pkg}.sig|${dkms_archive}.sig")
        if ! download_parallel_pacman "CachyOS NVIDIA DKMS (${dkms_pkg})" "${dkms_items[@]}"; then
            log_error "Failed to download DKMS source package: ${dkms_pkg}"
            rm -rf "${staging_dir}"
            return 1
        fi

        if ! verify_cachyos_gpg_signature "${dkms_archive}" "${dkms_archive}.sig" "${cachy_repo}/${dkms_pkg}"; then
            log_error "GPG signature verification failed for ${dkms_pkg}! Aborting."
            rm -rf "${staging_dir}"
            return 1
        fi

        if [ -f "${dkms_archive}" ] && [ -s "${dkms_archive}" ]; then
            validate_privileges
            # Unpack /usr/src/nvidia-* to system
            sudo tar --zstd --exclude=.PKGINFO --exclude=.BUILDINFO --exclude=.MTREE --exclude=.INSTALL --exclude=.CHANGELOG -xf "${dkms_archive}" -C / 2>/dev/null || true

            # Self-heal dead DKMS module registrations prior to build/install
            if command -v dkms_purge_orphaned_ghosts >/dev/null 2>&1; then
                dkms_purge_orphaned_ghosts >/dev/null 2>&1 || true
            fi

            local dkms_bin
            dkms_bin=$(command -v dkms 2>/dev/null || echo "/usr/sbin/dkms")
            if [ -x "${dkms_bin}" ]; then
                log_info "Compiling NVIDIA DKMS module for kernel ${stock_kver}..."
                if ! sudo "${dkms_bin}" build -m "${dkms_name}" -v "${dkms_ver}" -k "${stock_kver}" 2>&1; then
                    log_error "DKMS build failed for kernel: ${stock_kver}"
                    return 1
                fi
                if ! sudo "${dkms_bin}" install -m "${dkms_name}" -v "${dkms_ver}" -k "${stock_kver}" --force 2>&1; then
                    log_error "DKMS install failed for kernel: ${stock_kver}"
                    return 1
                fi
                prune_stale_nvidia_modules_for_kernel "${stock_kver}" "${cachy_nv_ver}"
                log_success "NVIDIA kernel module built for kernel: ${stock_kver}"
            fi
        fi
    fi

    validate_privileges
    sudo "${DEPMOD_CMD}" -a "${stock_kver}" 2>/dev/null || true
    # 6A-97: inside a deferred run the boot-chain step builds this image once (it was built twice per kernel)
    if [ "${DEFER_BOOT_SYNC:-0}" = "1" ]; then
        ss_order_initrd "${stock_kver}"
    elif command -v generate_kernel_initramfs >/dev/null 2>&1; then
        generate_kernel_initramfs "${stock_kver}"
    fi
}

rollback_cachyos_to_slackware_nvidia() {
    [ "${HAS_NVIDIA}" = "true" ] || return 0
    # 6A-131: never install a .run driver for a card this tool does not manage
    nvidia_generation_supported || return 0
    validate_privileges

    log_info "Initiating rollback from CachyOS NVIDIA Suite to official Slackware standalone driver..."

    # 6A-134 (L2 M8): fetch and verify the replacement FIRST; the CachyOS userspace is removed only after that, so a
    # failed download leaves the current driver in place (it used to remove it first and then print success).
    local target_branch="595" url run_file
    url=$(get_nvidia_download_url "${target_branch}")
    if [ -z "${url}" ]; then
        log_error "The NVIDIA driver could not be looked up, so the current graphics driver was kept."
        return 1
    fi
    run_file="/var/cache/slacky-update/nvidia/$(basename "${url}")"
    if ! nvidia_fetch_verified_run "${url}" "${run_file}" "${target_branch}"; then
        log_error "The NVIDIA driver could not be downloaded and verified, so the current graphics driver was kept."
        return 1
    fi

    local pkg pbase rm_failed=0
    for pkg in "${PKGDB_DIR:-/var/log/packages}"/cachyos-nvidia*utils-*; do
        [ -f "${pkg}" ] || continue
        pbase=$(basename "${pkg}")
        log_info "Removing CachyOS package: ${pbase}..."
        sudo "${PKG_REMOVE_CMD}" "${pbase}" 2>/dev/null || rm_failed=1
    done
    if [ "${rm_failed}" -eq 1 ]; then
        log_error "The CachyOS NVIDIA package could not be removed, so the NVIDIA driver was not replaced."
        return 1
    fi

    log_info "Installing official NVIDIA .run driver (${target_branch} branch) with DKMS..."
    if ! INTERACTIVE_NVIDIA=1 install_nvidia_run_driver "${target_branch}" "${run_file}"; then
        log_error "The NVIDIA driver installer failed after the CachyOS package was removed; run 'slacky-update --nvidia' before restarting."
        return 1
    fi
    log_success "Rollback to official Slackware NVIDIA driver completed!"
}

sync_all_stock_kernels_nvidia() {
    local cachy_nv_ver="$1"
    [ -n "${cachy_nv_ver}" ] || return 0

    local excluded_kernels=()
    if command -v get_obsolete_cachyos_kernels >/dev/null 2>&1; then
        mapfile -t excluded_kernels < <(get_obsolete_cachyos_kernels 2>/dev/null || true)
    fi

    if [ -d "/lib/modules" ]; then
        for kdir in /lib/modules/*; do
            [ -d "${kdir}" ] || continue
            local kver
            kver=$(basename "${kdir}")
            # Skip CachyOS kernels as they receive cachyos-*-nvidia-open
            [[ "${kver}" =~ cachyos ]] && continue
            if [[ " ${excluded_kernels[*]:-} " =~ [[:space:]]${kver}[[:space:]] ]]; then
                continue
            fi
            if [ -d "${kdir}/build" ] || [ -d "/usr/src/linux-${kver}" ]; then
                sync_stock_kernel_nvidia_module "${kver}" "${cachy_nv_ver}" || log_warn "DKMS synchronization warning for ${kver}"
            fi
        done
    fi
}

ensure_cachyos_nvidia_dkms_source_unpacked() {
    local cachy_nv_ver="$1"
    local gpu_arch="${2:-MODERN}"
    local cachy_repo
    cachy_repo=$(get_cachyos_nvidia_repo_url | sed 's|/*$||')
    local staging_dir
    staging_dir="$(get_user_staging_dir)/dkms"
    mkdir -p "${staging_dir}"

    local dkms_pkg=""
    local dkms_name="nvidia"
    local dkms_ver="${cachy_nv_ver}"

    if [ "${gpu_arch}" = "PASCAL" ]; then
        local phtml
        phtml=$(curl -sSL --connect-timeout 15 -m 30 "${cachy_repo}/" 2>/dev/null || echo "")
        dkms_pkg=$(echo "${phtml}" | grep -o -E 'nvidia-580xx-dkms-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst' | head -n 1 || echo "")
        dkms_name="nvidia"
        dkms_ver=$(echo "${dkms_pkg}" | grep -o -E '580\.[0-9]+(\.[0-9]+)?' | head -n 1 || echo "580.178.04")
    else
        local mhtml
        mhtml=$(curl -sSL --connect-timeout 15 -m 30 "${cachy_repo}/" 2>/dev/null || echo "")
        dkms_pkg=$(echo "${mhtml}" | grep -o -E 'nvidia-open-dkms-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst' | head -n 1 || echo "")
        dkms_name="nvidia"
    fi

    if [ -n "${dkms_pkg}" ]; then
        local dkms_archive="${staging_dir}/${dkms_pkg}"
        local dkms_items=("${cachy_repo}/${dkms_pkg}|${dkms_archive}|${cachy_repo}/${dkms_pkg}.sig|${dkms_archive}.sig")
        if download_parallel_pacman "CachyOS NVIDIA DKMS (${dkms_pkg})" "${dkms_items[@]}" 2>/dev/null; then
            if verify_cachyos_gpg_signature "${dkms_archive}" "${dkms_archive}.sig" "${cachy_repo}/${dkms_pkg}" 2>/dev/null; then
                validate_privileges
                sudo tar --zstd --exclude=.PKGINFO --exclude=.BUILDINFO --exclude=.MTREE --exclude=.INSTALL --exclude=.CHANGELOG -xf "${dkms_archive}" -C / 2>/dev/null || true
                if command -v dkms_purge_orphaned_ghosts >/dev/null 2>&1; then
                    dkms_purge_orphaned_ghosts >/dev/null 2>&1 || true
                fi
            fi
        fi
    fi
    echo "${dkms_name}|${dkms_ver}"
}

sync_all_cachyos_kernels_nvidia() {
    local cachy_nv_ver="$1"
    [ -n "${cachy_nv_ver}" ] || return 0

    local gpu_arch="MODERN"
    if command -v detect_nvidia_gpu >/dev/null 2>&1; then
        gpu_arch=$(detect_nvidia_gpu)
    fi
    [ "${gpu_arch}" = "LEGACY" ] && return 0
    # 6A-131: Pascal and Volta are refused as well (open modules need Turing; the 580xx path is not part of LTS)
    nvidia_generation_supported || return 0

    local cachy_repo
    cachy_repo=$(get_cachyos_nvidia_repo_url | sed 's|/*$||')
    local html
    html=$(curl -sSL -m 15 "${cachy_repo}/" 2>/dev/null || echo "")
    [ -n "${html}" ] || return 0

    local excluded_kernels=()
    if command -v get_obsolete_cachyos_kernels >/dev/null 2>&1; then
        mapfile -t excluded_kernels < <(get_obsolete_cachyos_kernels 2>/dev/null || true)
    fi

    local search_dirs=()
    [ -d "/usr/lib/modules" ] && search_dirs+=("/usr/lib/modules")
    [ -d "/lib/modules" ] && search_dirs+=("/lib/modules")

    local processed_kvers=()
    for mod_parent in "${search_dirs[@]}"; do
        for kdir in "${mod_parent}"/*; do
            [ -d "${kdir}" ] || continue
            local kver
            kver=$(basename "${kdir}")
            [[ "${kver}" =~ cachyos ]] || continue

            # Skip kernels marked for retention exclusion / slated for deletion
            if [[ " ${excluded_kernels[*]:-} " =~ [[:space:]]${kver}[[:space:]] ]]; then
                continue
            fi

            # Prevent processing the same kernel version twice
            if [[ " ${processed_kvers[*]:-} " =~ [[:space:]]${kver}[[:space:]] ]]; then
                continue
            fi
            processed_kvers+=("${kver}")

            local existing_mod
            existing_mod=$(find -L "${kdir}" -name "nvidia.ko*" 2>/dev/null | head -n 1 || true)
            local cur_mod_ver="None"
            [ -n "${existing_mod}" ] && cur_mod_ver=$(get_nvidia_module_version "${existing_mod}")

            if [ "${cur_mod_ver}" != "${cachy_nv_ver}" ]; then
                log_info "Synchronizing CachyOS kernel ${kver} NVIDIA module (${cur_mod_ver} -> ${cachy_nv_ver})..."
                if [ "${gpu_arch}" = "MODERN" ]; then
                    local pref="linux-cachyos"
                    if [[ "${kver}" =~ -bore-lto ]]; then
                        pref="linux-cachyos-bore-lto"
                    elif [[ "${kver}" =~ -rt-bore ]]; then
                        pref="linux-cachyos-rt-bore"
                    elif [[ "${kver}" =~ -bore ]]; then
                        pref="linux-cachyos-bore"
                    elif [[ "${kver}" =~ -eevdf ]]; then
                        pref="linux-cachyos-eevdf"
                    elif [[ "${kver}" =~ -bmq ]]; then
                        pref="linux-cachyos-bmq"
                    elif [[ "${kver}" =~ -deckify ]]; then
                        pref="linux-cachyos-deckify"
                    elif [[ "${kver}" =~ -rc ]]; then
                        pref="linux-cachyos-rc"
                    elif [[ "${kver}" =~ -lts ]]; then
                        pref="linux-cachyos-lts"
                    fi

                    # 1. Primary Fast-Path: Precompiled CachyOS binary module
                    local pkg_pattern="${pref}-nvidia-open-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst"
                    local matched_pkg=""
                    local candidate_pkgs
                    candidate_pkgs=$(echo "${html}" | grep -o -E "${pkg_pattern}" || echo "")
                    local kver_clean
                    kver_clean=$(echo "${kver}" | sed -E 's/-cachyos.*$//')
                    for c_pkg in ${candidate_pkgs}; do
                        if [[ "${kver}" =~ -rc ]] && [[ "${c_pkg}" =~ -rc ]]; then
                            local k_rc p_rc
                            k_rc=$(echo "${kver}" | grep -o -E 'rc[0-9]+' || echo "")
                            p_rc=$(echo "${c_pkg}" | grep -o -E 'rc[0-9]+' || echo "")
                            # 6A-302 (F0b): exact release, anchored on both sides; 7.2.1 must never match a 7.2.10 module
                            if [ -n "${k_rc}" ] && [ "${k_rc}" = "${p_rc}" ] && [[ "${c_pkg}" == "${pref}-nvidia-open-${kver_clean}-"* ]]; then
                                matched_pkg="${c_pkg}"
                                break
                            fi
                        elif [[ "${c_pkg}" == "${pref}-nvidia-open-${kver_clean}-"* ]]; then
                            matched_pkg="${c_pkg}"
                            break
                        fi
                    done

                    local deployed_precompiled=0
                    if [ -n "${matched_pkg}" ]; then
                        local staging_dir
                        staging_dir="$(get_user_staging_dir)/cachy-nv-modules"
                        mkdir -p "${staging_dir}"
                        local nv_file="${staging_dir}/${matched_pkg}"
                        local nv_items=("${cachy_repo}/${matched_pkg}|${nv_file}|${cachy_repo}/${matched_pkg}.sig|${nv_file}.sig")
                        if download_parallel_pacman "CachyOS NVIDIA Module (${kver})" "${nv_items[@]}" && verify_cachyos_gpg_signature "${nv_file}" "${nv_file}.sig" "${cachy_repo}/${matched_pkg}"; then
                            validate_privileges
                            log_info "Deploying precompiled NVIDIA open driver to kernel ${kver}..."
                            sudo tar --zstd --exclude=.PKGINFO --exclude=.BUILDINFO --exclude=.MTREE --exclude=.INSTALL --exclude=.CHANGELOG -xf "${nv_file}" -C /
                            prune_stale_nvidia_modules_for_kernel "${kver}" "${cachy_nv_ver}"
                            register_precompiled_nvidia_in_dkms "${kver}" "${cachy_nv_ver}"
                            # 6A-302 (F0b): success only when the module really landed for this kernel with the expected version
                            if nvidia_module_landed "${kver}" "${cachy_nv_ver}"; then
                                nvidia_hold_clear "${kver}"
                                # 6A-97: deferred run -> one image build per kernel in the boot-chain step
                                if [ "${DEFER_BOOT_SYNC:-0}" = "1" ]; then
                                    ss_order_initrd "${kver}"
                                elif command -v generate_kernel_initramfs >/dev/null 2>&1; then
                                    generate_kernel_initramfs "${kver}"
                                fi
                                deployed_precompiled=1
                            else
                                nvidia_hold_set "${kver}"
                                log_error "The NVIDIA driver did not arrive for kernel ${kver}, so that kernel will not become the default until it is fixed."
                            fi
                        fi
                    fi

                    # 2. Secondary Hybrid Fallback: DKMS Bridge for older/intermediate CachyOS kernels (non-RC only)
                    if [ "${deployed_precompiled}" -eq 0 ]; then
                        if [[ "${kver}" =~ -rc ]]; then
                            log_warn "Notice: CachyOS RC kernel (${kver}) requires precompiled open module; skipping DKMS fallback."
                        elif command -v dkms >/dev/null 2>&1 && ([ -d "/lib/modules/${kver}/build" ] || [ -d "/usr/src/linux-headers-${kver}" ]); then
                            log_info "No precompiled module matching ${kver} found on mirrors. Engaging DKMS Bridge..."
                            ensure_cachyos_nvidia_dkms_source_unpacked "${cachy_nv_ver}" "MODERN" >/dev/null 2>&1 || true
                            validate_privileges
                            log_info "Building nvidia-open ${cachy_nv_ver} for CachyOS kernel ${kver} via DKMS..."
                            if sudo dkms build -m nvidia -v "${cachy_nv_ver}" -k "${kver}" 2>/dev/null; then
                                sudo dkms install -m nvidia -v "${cachy_nv_ver}" -k "${kver}" 2>/dev/null || log_warn "DKMS install warning for ${kver}"
                                prune_stale_nvidia_modules_for_kernel "${kver}" "${cachy_nv_ver}"
                                # 6A-302 (F0b): the same proof as for the precompiled module
                                if nvidia_module_landed "${kver}" "${cachy_nv_ver}"; then
                                    nvidia_hold_clear "${kver}"
                                    # 6A-97: deferred run -> one image build per kernel in the boot-chain step
                                    if [ "${DEFER_BOOT_SYNC:-0}" = "1" ]; then
                                        ss_order_initrd "${kver}"
                                    elif command -v generate_kernel_initramfs >/dev/null 2>&1; then
                                        generate_kernel_initramfs "${kver}"
                                    fi
                                else
                                    nvidia_hold_set "${kver}"
                                    log_error "The NVIDIA driver did not arrive for kernel ${kver}, so that kernel will not become the default until it is fixed."
                                fi
                            else
                                log_warn "DKMS build was unsuccessful for kernel: ${kver} (skipping install)"
                            fi
                        else
                            log_warn "Could not resolve precompiled module or DKMS toolchain for CachyOS kernel ${kver}."
                        fi
                    fi
                elif [ "${gpu_arch}" = "PASCAL" ]; then
                    if command -v dkms >/dev/null 2>&1; then
                        validate_privileges
                        ensure_cachyos_nvidia_dkms_source_unpacked "${cachy_nv_ver}" "PASCAL" >/dev/null 2>&1 || true
                        local dkms_ver
                        dkms_ver=$(dkms status 2>/dev/null | grep -E '^nvidia/' | awk -F'[,/]' '{print $2}' | tr -d ' ' | head -n 1 || echo "580.178.04")
                        log_info "Building nvidia ${dkms_ver} for CachyOS kernel ${kver} via DKMS..."
                        sudo dkms build -m nvidia -v "${dkms_ver}" -k "${kver}" 2>/dev/null || true
                        sudo dkms install -m nvidia -v "${dkms_ver}" -k "${kver}" 2>/dev/null || true
                        prune_stale_nvidia_modules_for_kernel "${kver}" "${cachy_nv_ver}"
                        # 6A-97: deferred run -> one image build per kernel in the boot-chain step
                        if [ "${DEFER_BOOT_SYNC:-0}" = "1" ]; then
                            ss_order_initrd "${kver}"
                        elif command -v generate_kernel_initramfs >/dev/null 2>&1; then
                            generate_kernel_initramfs "${kver}"
                        fi
                    fi
                fi
            else
                # Module is already matching; ensure no duplicate stale modules linger in extramodules/ or drivers/video
                prune_stale_nvidia_modules_for_kernel "${kver}" "${cachy_nv_ver}"
                register_precompiled_nvidia_in_dkms "${kver}" "${cachy_nv_ver}"
            fi
        done
    done
}

ensure_cachyos_nvidia_duties() {
    probe_gpu_hardware
    [ "${HAS_NVIDIA}" = "true" ] || return 0
    # 6A-131/6A-132 (B6, F2, F3): pre-Turing, nouveau (unless chosen with --nvidia or the menu), opt-out: left alone
    nvidia_generation_supported || return 0

    local has_cachy
    has_cachy=$(has_cachyos_kernels_installed)
    if [ "${has_cachy}" != "true" ] && [ "${INTERACTIVE_NVIDIA:-0}" != "1" ]; then
        return 0
    fi

    # Clean legacy unmanaged .run installations if present
    transition_legacy_run_to_cachyos

    # Clean up obsolete kernels (including older RC kernels where only the latest is kept)
    # 6A-98: inside a deferred run the purge waits until the boot chain has a menu without these kernels
    if [ "${DEFER_BOOT_SYNC:-0}" != "1" ] && command -v purge_old_cachyos_kernels >/dev/null 2>&1; then
        purge_old_cachyos_kernels --no-sync
    fi

    # Clean up orphaned ghost DKMS entries
    if command -v dkms_purge_orphaned_ghosts >/dev/null 2>&1; then
        dkms_purge_orphaned_ghosts >/dev/null 2>&1 || true
    fi

    local cachy_nv_ver
    cachy_nv_ver=$(detect_cachyos_nvidia_upstream_version)
    if [ -z "${cachy_nv_ver}" ]; then
        log_warn "Unable to detect CachyOS NVIDIA upstream version."
        return 0
    fi

    local excluded_kernels=()
    if command -v get_obsolete_cachyos_kernels >/dev/null 2>&1; then
        mapfile -t excluded_kernels < <(get_obsolete_cachyos_kernels 2>/dev/null || true)
    fi

    local pending_rebuilds=0
    if [ -d "/lib/modules" ]; then
        for kdir in /lib/modules/*; do
            [ -d "${kdir}" ] || continue
            local kver
            kver=$(basename "${kdir}")
            [ -f "${kdir}/modules.dep" ] || [ -d "${kdir}/kernel" ] || [ -d "${kdir}/extramodules" ] || continue

            # Skip kernels marked for retention exclusion / slated for deletion
            if [[ " ${excluded_kernels[*]:-} " =~ [[:space:]]${kver}[[:space:]] ]]; then
                continue
            fi

            # Stock Slackware kernel without build tree: immutable rescue rail
            if [[ ! "${kver}" =~ cachyos ]] && [[ ! "${kver}" =~ -zen ]] && [[ ! "${kver}" =~ -arch ]]; then
                if [ ! -d "${kdir}/build" ] && [ ! -d "/usr/src/linux-${kver}" ]; then
                    local stale_stock_mod
                    stale_stock_mod=$(find -L "${kdir}" -name "nvidia.ko*" 2>/dev/null | head -n 1 || true)
                    if [ -n "${stale_stock_mod}" ]; then
                        local cur_stale_ver
                        cur_stale_ver=$(get_nvidia_module_version "${stale_stock_mod}")
                        if [ "${cur_stale_ver}" != "${cachy_nv_ver}" ]; then
                            validate_privileges
                            sudo mv -f "${stale_stock_mod}" "${kdir}/nvidia.ko.disabled" 2>/dev/null || true
                            sudo "${DEPMOD_CMD:-depmod}" -a "${kver}" 2>/dev/null || true
                        fi
                    fi
                    continue
                fi
            fi

            local k_mod
            k_mod=$(find -L "${kdir}" -name "nvidia.ko*" 2>/dev/null | head -n 1 || true)
            if [ -n "${k_mod}" ]; then
                local k_ver
                k_ver=$(get_nvidia_module_version "${k_mod}")
                if [ "${k_ver}" != "${cachy_nv_ver}" ]; then
                    pending_rebuilds=$((pending_rebuilds + 1))
                fi
            else
                pending_rebuilds=$((pending_rebuilds + 1))
            fi
        done
    fi

    # 1. Synchronize installed CachyOS and stock kernels FIRST if pending rebuilds exist
    if [ "${pending_rebuilds}" -gt 0 ]; then
        log_info "Synchronizing NVIDIA ${cachy_nv_ver} kernel modules across active kernels..."
        sync_all_cachyos_kernels_nvidia "${cachy_nv_ver}"
        sync_all_stock_kernels_nvidia "${cachy_nv_ver}"
    else
        # Reconcile DKMS state for all matching kernels so boot-time dkms_autoinstaller skips compilation
        local check_kdirs=()
        [ -d "/lib/modules" ] && check_kdirs+=("/lib/modules"/*)
        [ -d "/usr/lib/modules" ] && check_kdirs+=("/usr/lib/modules"/*)
        local reconciled_kvers=()
        for kdir in "${check_kdirs[@]}"; do
            [ -d "${kdir}" ] || continue
            local kver
            kver=$(basename "${kdir}")
            [[ " ${reconciled_kvers[*]:-} " =~ [[:space:]]${kver}[[:space:]] ]] && continue
            reconciled_kvers+=("${kver}")
            local k_mod
            k_mod=$(find -L "${kdir}" -name "nvidia.ko*" 2>/dev/null | head -n 1 || true)
            if [ -n "${k_mod}" ]; then
                local k_ver
                k_ver=$(get_nvidia_module_version "${k_mod}")
                if [ "${k_ver}" = "${cachy_nv_ver}" ]; then
                    register_precompiled_nvidia_in_dkms "${kver}" "${cachy_nv_ver}" >/dev/null 2>&1 || true
                fi
            fi
        done
    fi

    # 2. Verify or deploy CachyOS user-space package SECOND (split-brain proof)
    local installed_pkg
    installed_pkg=$(ls /var/log/packages/cachyos-nvidia*utils-* 2>/dev/null | head -n 1 || true)
    local need_userspace="false"
    if [ -z "${installed_pkg}" ]; then
        need_userspace="true"
    else
        local cur_pkg_ver
        cur_pkg_ver=$(basename "${installed_pkg}" | sed -E 's/.*utils-([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/')
        if [ "${cur_pkg_ver}" != "${cachy_nv_ver}" ]; then
            need_userspace="true"
        elif [ ! -f "/etc/OpenCL/vendors/nvidia.icd" ] || [ ! -f "/usr/lib64/dri/nvidia_drv_video.so" ]; then
            log_info "Detected legacy CachyOS userspace missing OpenCL or VA-API driver. Migrating to Complete Suite..."
            need_userspace="true"
        fi
    fi

    # 6A-132 (F4): the userspace result is checked (a failed build was followed by the blacklist and "up to date")
    local userspace_ok=1
    if [ "${need_userspace}" = "true" ]; then
        build_and_deploy_cachyos_nvidia_userspace "${cachy_nv_ver}" || userspace_ok=0
    fi
    local modules_ok=1
    nvidia_replacement_proven "${cachy_nv_ver}" || modules_ok=0

    # Check if any installed kernel is missing its initramfs image OR has a stale initramfs older than its nvidia.ko
    local engine
    engine=$(detect_initramfs_engine 2>/dev/null || echo "mkinitrd")
    local missing_kvers=()
    if [ -d "/lib/modules" ]; then
        for kdir in /lib/modules/*; do
            [ -d "${kdir}" ] || continue
            local kver
            kver=$(basename "${kdir}")
            [ -f "${kdir}/modules.dep" ] || continue
            if ! sudo test -f "/boot/vmlinuz-${kver}" && ! sudo test -f "/boot/vmlinuz-generic" && ! sudo test -f "/boot/vmlinuz" && ! sudo ls /boot/vmlinuz*"${kver}"* >/dev/null 2>&1; then
                continue
            fi

            local k_mod
            k_mod=$(find -L "${kdir}" -name "nvidia.ko*" 2>/dev/null | head -n 1 || true)

            if [ "${engine}" = "dracut" ]; then
                local img="/boot/initramfs-${kver}.img"
                if ! sudo test -f "${img}"; then
                    missing_kvers+=("${kver}")
                elif [ -n "${k_mod}" ] && [ -f "${k_mod}" ] && sudo test "${k_mod}" -nt "${img}"; then
                    log_info "Detected initramfs for kernel ${kver} is older than its updated NVIDIA module. Rebuilding..."
                    missing_kvers+=("${kver}")
                fi
            else
                local img="/boot/initrd-${kver}.gz"
                sudo test -f "${img}" || img="/boot/initrd-${kver}.img"
                sudo test -f "${img}" || img="/boot/initrd.gz"
                if ! sudo test -f "${img}"; then
                    missing_kvers+=("${kver}")
                elif [ -n "${k_mod}" ] && [ -f "${k_mod}" ] && sudo test "${k_mod}" -nt "${img}"; then
                    log_info "Detected initrd for kernel ${kver} is older than its updated NVIDIA module. Rebuilding..."
                    missing_kvers+=("${kver}")
                fi
            fi
        done
    fi

    # 3. Secure Boot, Initramfs & Bootloader synchronization (Targeted or Full, unless deferred)
    if [ "${DEFER_BOOT_SYNC:-0}" != "1" ]; then
        if [ "${need_userspace}" = "true" ]; then
            configure_nvidia_modprobe "${cachy_nv_ver}" || true
            log_info "Regenerating ${engine} initramfs images for all installed kernels with updated NVIDIA driver (${cachy_nv_ver})..."
            if command -v generate_kernel_initramfs >/dev/null 2>&1; then
                generate_kernel_initramfs "ALL"
            fi
        elif [ "${#missing_kvers[@]}" -gt 0 ]; then
            configure_nvidia_modprobe "${cachy_nv_ver}" || true
            for mk in "${missing_kvers[@]}"; do
                log_info "Generating missing ${engine} initramfs for kernel: ${mk}..."
                if command -v generate_kernel_initramfs >/dev/null 2>&1; then
                    generate_kernel_initramfs "${mk}"
                fi
            done
        fi

        if [ "${pending_rebuilds}" -gt 0 ] || [ "${need_userspace}" = "true" ] || [ "${#missing_kvers[@]}" -gt 0 ]; then
            if command -v purge_old_slackware_kernels >/dev/null 2>&1; then
                purge_old_slackware_kernels --no-sync
            fi
            if command -v purge_old_cachyos_kernels >/dev/null 2>&1; then
                purge_old_cachyos_kernels --no-sync
            fi

            if command -v enforce_secure_boot_armor >/dev/null 2>&1; then
                enforce_secure_boot_armor
            fi

            log_info "Synchronizing bootloader configurations (GRUB / Limine)..."
            if command -v sync_bootloader_configuration >/dev/null 2>&1; then
                sync_bootloader_configuration "$(uname -r)"
            fi

            register_flatpak_gl_sync "${cachy_nv_ver}"
            if [ "${userspace_ok}" -eq 1 ] && [ "${modules_ok}" -eq 1 ]; then
                log_success "CachyOS-Master NVIDIA Full Suite synchronization completed!"
            fi
        elif [ "${modules_ok}" -eq 1 ]; then
            log_success "All CachyOS and stock kernel NVIDIA modules (v${cachy_nv_ver}) are matched and up to date."
        fi
    else
        # 6A-97: the owner of the deferral builds these images once (missing, or older than their NVIDIA module)
        local mk_o
        for mk_o in "${missing_kvers[@]:-}"; do
            [ -n "${mk_o}" ] && ss_order_initrd "${mk_o}"
        done
        if [ "${userspace_ok}" -eq 1 ] && [ "${modules_ok}" -eq 1 ]; then
            log_success "All CachyOS and stock kernel NVIDIA modules (v${cachy_nv_ver}) are matched and up to date (boot sync deferred)."
        fi
    fi
    # 6A-132: honest result for the caller ([1/5] status line)
    if [ "${userspace_ok}" -ne 1 ]; then
        log_error "The NVIDIA userspace ${cachy_nv_ver} could not be installed; the previous driver files are kept."
        return 1
    fi
    if [ "${modules_ok}" -ne 1 ]; then
        log_warn "The NVIDIA driver ${cachy_nv_ver} is not ready for every kernel yet, so the screen may stay black on some of them."
        return 1
    fi
    return 0
}

