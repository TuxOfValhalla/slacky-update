#!/usr/bin/env bash
# --- [ CACHYOS KERNEL & INITRD ENGINE ] ---

set -euo pipefail

# --- [ ARCHITECTURE DETECTION ] ---
detect_cpu_tier() {
    local cpuinfo="/proc/cpuinfo"
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
    local tier="$1"
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

is_cachyos_kernel_installed() {
    if uname -r | grep -qi "cachyos"; then
        echo "true"
        return 0
    fi
    if find /lib/modules /boot -maxdepth 2 -name "*cachyos*" 2>/dev/null | grep -q "cachyos"; then
        echo "true"
        return 0
    fi
    echo "false"
}

get_installed_cachyos_flavors() {
    python3 -c "
import os, re

def get_flavor(k_str):
    if '-cachyos-bore-lto' in k_str or '-cachyos-lto' in k_str:
        return 'lto'
    elif '-cachyos-bore' in k_str:
        return 'bore'
    elif '-cachyos-rc' in k_str:
        return 'rc'
    elif '-cachyos-lts' in k_str:
        return 'lts'
    elif '-cachyos' in k_str:
        return 'standard'
    return None

flavors = set()
if os.path.exists('/boot'):
    for f in os.listdir('/boot'):
        if 'cachyos' in f and f.startswith('vmlinuz-') and not os.path.islink(os.path.join('/boot', f)):
            flv = get_flavor(f)
            if flv: flavors.add(flv)

if os.path.exists('/lib/modules'):
    for d in os.listdir('/lib/modules'):
        if 'cachyos' in d:
            flv = get_flavor(d)
            if flv: flavors.add(flv)

print(' '.join(sorted(list(flavors))))
" 2>/dev/null || echo ""
}

get_installed_cachyos_flavor_version() {
    local flavor="$1"
    python3 -c "
import os, re

def get_flavor(k_str):
    if '-cachyos-bore-lto' in k_str or '-cachyos-lto' in k_str:
        return 'lto'
    elif '-cachyos-bore' in k_str:
        return 'bore'
    elif '-cachyos-rc' in k_str:
        return 'rc'
    elif '-cachyos-lts' in k_str:
        return 'lts'
    elif '-cachyos' in k_str:
        return 'standard'
    return None

def parse_ver(v_str):
    return [int(x) for x in re.findall(r'\d+', v_str.split('-cachyos')[0])]

cachy_vers = set()
target_flv = '$flavor'

if os.path.exists('/boot'):
    for f in os.listdir('/boot'):
        if 'cachyos' in f and f.startswith('vmlinuz-') and not os.path.islink(os.path.join('/boot', f)):
            if get_flavor(f) == target_flv:
                v = f.replace('vmlinuz-', '').split('-cachyos')[0]
                if v: cachy_vers.add(v)

if os.path.exists('/lib/modules'):
    for d in os.listdir('/lib/modules'):
        if 'cachyos' in d and get_flavor(d) == target_flv:
            v = d.split('-cachyos')[0]
            if v: cachy_vers.add(v)

if cachy_vers:
    sorted_vers = sorted(list(cachy_vers), key=parse_ver, reverse=True)
    print(sorted_vers[0])
else:
    print('NONE')
" 2>/dev/null || echo "NONE"
}

get_newest_installed_cachyos_version() {
    python3 -c "
import os, re

def parse_ver(v_str):
    return [int(x) for x in re.findall(r'\d+', v_str.split('-cachyos')[0])]

cachy_vers = set()

if os.path.exists('/boot'):
    for f in os.listdir('/boot'):
        if 'cachyos' in f and f.startswith('vmlinuz-') and not os.path.islink(os.path.join('/boot', f)):
            v = f.replace('vmlinuz-', '').split('-cachyos')[0]
            if v:
                cachy_vers.add(v)

if os.path.exists('/lib/modules'):
    for d in os.listdir('/lib/modules'):
        if 'cachyos' in d:
            v = d.split('-cachyos')[0]
            if v:
                cachy_vers.add(v)

uname_r = os.uname().release
if 'cachyos' in uname_r:
    cachy_vers.add(uname_r.split('-cachyos')[0])

if cachy_vers:
    sorted_vers = sorted(list(cachy_vers), key=parse_ver, reverse=True)
    print(sorted_vers[0])
else:
    print('NONE')
" 2>/dev/null || echo "NONE"
}

compare_versions_strictly_greater() {
    local target="$1"
    local reference="$2"

    python3 -c "
import sys, re

def parse_ver(v_str):
    return [int(x) for x in re.findall(r'\d+', v_str.split('-cachyos')[0])]

try:
    target_parts = parse_ver('$target')
    ref_parts = parse_ver('$reference')
    if target_parts > ref_parts:
        sys.exit(0)
except Exception:
    pass
sys.exit(1)
" && echo "true" || echo "false"
}

check_cachyos_upstream_flavor() {
    local flavor="${1:-standard}"
    local tier
    tier=$(detect_cpu_tier)
    local repo_urls=()
    case "${tier}" in
        znver4)
            repo_urls=("https://mirror.cachyos.org/repo/x86_64_v4/cachyos-znver4/" "https://mirror.cachyos.org/repo/x86_64_v4/cachyos-v4/")
            ;;
        v4)
            repo_urls=("https://mirror.cachyos.org/repo/x86_64_v4/cachyos-v4/")
            ;;
        v3)
            repo_urls=("https://mirror.cachyos.org/repo/x86_64_v3/cachyos-v3/" "https://mirror.cachyos.org/repo/x86_64/cachyos/")
            ;;
        *)
            repo_urls=("https://mirror.cachyos.org/repo/x86_64/cachyos/")
            ;;
    esac

    local k_prefix="linux-cachyos"
    local h_prefix="linux-cachyos-headers"
    if [ "${flavor}" = "bore" ]; then
        k_prefix="linux-cachyos-bore"
        h_prefix="linux-cachyos-bore-headers"
    elif [ "${flavor}" = "lto" ]; then
        k_prefix="linux-cachyos-bore-lto"
        h_prefix="linux-cachyos-bore-lto-headers"
    elif [ "${flavor}" = "rc" ]; then
        k_prefix="linux-cachyos-rc"
        h_prefix="linux-cachyos-rc-headers"
    elif [ "${flavor}" = "lts" ]; then
        k_prefix="linux-cachyos-lts"
        h_prefix="linux-cachyos-lts-headers"
    fi

    for repo_url in "${repo_urls[@]}"; do
        local result
        result=$(curl -sSL -m 15 "${repo_url}" 2>/dev/null | python3 -c "
import re, sys

html = sys.stdin.read()
if not html:
    print('NONE NONE NONE NONE')
    sys.exit(0)

repo_url = '${repo_url}'
k_pref = '${k_prefix}'
h_pref = '${h_prefix}'
nv_pref = k_pref + '-nvidia-open'

k_matches = re.findall(r'href=[\'\"]?(' + re.escape(k_pref) + r'-([0-9]+\.[0-9]+[a-zA-Z0-9\._]*-[0-9]+)[^\'\">]*\.pkg\.tar\.zst)', html)
h_matches = re.findall(r'href=[\'\"]?(' + re.escape(h_pref) + r'-([0-9]+\.[0-9]+[a-zA-Z0-9\._]*-[0-9]+)[^\'\">]*\.pkg\.tar\.zst)', html)
nv_matches = re.findall(r'href=[\'\"]?(' + re.escape(nv_pref) + r'-([0-9]+\.[0-9]+[a-zA-Z0-9\._]*-[0-9]+)[^\'\">]*\.pkg\.tar\.zst)', html)

if not k_matches or not h_matches:
    print('NONE NONE NONE NONE')
    sys.exit(0)

def parse_ver_key(v_str):
    return [int(x) for x in re.findall(r'\d+', v_str)]

available_versions = sorted(list(set(m[1] for m in k_matches)), key=parse_ver_key, reverse=True)
latest_ver = available_versions[0]

k_pkg = next(m[0] for m in k_matches if m[1] == latest_ver)
h_pkg = next(m[0] for m in h_matches if m[1] == latest_ver)

nv_url = 'NONE'
if nv_matches:
    try:
        nv_pkg = next(m[0] for m in nv_matches if m[1] == latest_ver)
        nv_url = f'{repo_url}{nv_pkg}'
    except StopIteration:
        pass

print(f'{latest_ver} {repo_url}{k_pkg} {repo_url}{h_pkg} {nv_url}')
" 2>/dev/null || echo "NONE NONE NONE NONE")

        if [ "${result}" != "NONE NONE NONE NONE" ] && [ -n "${result}" ]; then
            echo "${result}"
            return 0
        fi
    done

    echo "NONE NONE NONE NONE"
}

check_latest_cachyos_upstream() {
    check_cachyos_upstream_flavor "standard"
}

deploy_cachyos_kernel_flavor() {
    local flavor="$1"
    validate_privileges
    probe_gpu_hardware

    log_info "Fetching latest ${flavor} CachyOS kernel metadata from upstream..."
    local latest_ver k_url h_url nv_url
    read -r latest_ver k_url h_url nv_url <<< "$(check_cachyos_upstream_flavor "${flavor}" || echo "NONE NONE NONE NONE")"

    if [ "${latest_ver}" = "NONE" ] || [ -z "${k_url}" ]; then
        log_error "Could not resolve CachyOS ${flavor} kernel from mirrors."
        return 1
    fi

    log_info "Deploying CachyOS ${flavor} kernel (v${latest_ver})..."
    deploy_cachyos_kernel_packages "${latest_ver}" "${k_url}" "${h_url}" "${flavor}" "${nv_url}"
    if command -v purge_old_cachyos_kernels >/dev/null 2>&1; then
        purge_old_cachyos_kernels
    fi

    # Smart Prompt: Check if system is eligible for pure CachyOS transition
    prompt_stock_kernel_removal_if_eligible "${flavor}"
}

update_cachyos_kernels() {
    validate_privileges
    local installed_flavors
    installed_flavors=$(get_installed_cachyos_flavors 2>/dev/null || echo "")
    if [ -z "${installed_flavors}" ]; then
        log_info "No CachyOS kernels currently installed."
        return 0
    fi

    log_info "Scanning for upstream updates across installed CachyOS flavors..."
    local updated_any=0
    for flv in ${installed_flavors}; do
        local cur_ver latest_ver k_url h_url nv_url
        cur_ver=$(get_installed_cachyos_flavor_version "${flv}" 2>/dev/null || echo "NONE")
        read -r latest_ver k_url h_url nv_url <<< "$(check_cachyos_upstream_flavor "${flv}" || echo "NONE NONE NONE NONE")"
        if [ "${latest_ver}" != "NONE" ] && [ -n "${latest_ver}" ] && [ "${cur_ver}" != "NONE" ]; then
            if [ "$(compare_versions_strictly_greater "${latest_ver}" "${cur_ver}")" = "true" ]; then
                echo -e "\n${GREEN}${BOLD}Upgrade available for ${flv}: v${cur_ver} -> v${latest_ver}${RESET}"
                deploy_cachyos_kernel_flavor "${flv}"
                updated_any=1
            else
                log_info "Flavor '${flv}' (v${cur_ver}) is up to date with upstream."
            fi
        fi
    done

    if [ "${updated_any}" -eq 1 ]; then
        log_success "CachyOS kernel upgrade completed."
    else
        log_info "All installed CachyOS kernels are already up to date."
    fi
}

remove_stock_slackware_kernels() {
    validate_privileges

    # HARD BOOT-VALIDATION GUARDRAIL:
    # Ensure at least one verified, bootable CachyOS vmlinuz (>5MB) and matching initramfs/initrd (>5MB) exist before removing stock kernels
    local valid_cachy_boot=0
    local found_cachy_kernel=""
    for vk in /boot/vmlinuz-*cachyos*; do
        [ -f "${vk}" ] && [ ! -L "${vk}" ] || continue
        local ksz
        ksz=$(stat -c%s "${vk}" 2>/dev/null || stat -f%z "${vk}" 2>/dev/null || echo 0)
        if [ "${ksz}" -gt 5000000 ]; then
            local ksuffix
            ksuffix=$(basename "${vk}" | sed 's/^vmlinuz-//')
            for initrd_cand in "/boot/initramfs-${ksuffix}.img" "/boot/initrd-${ksuffix}.img" "/boot/initramfs-${ksuffix}" "/boot/initrd.gz"; do
                if [ -f "${initrd_cand}" ]; then
                    local isz
                    isz=$(stat -c%s "${initrd_cand}" 2>/dev/null || stat -f%z "${initrd_cand}" 2>/dev/null || echo 0)
                    if [ "${isz}" -gt 5000000 ]; then
                        valid_cachy_boot=1
                        found_cachy_kernel="$(basename "${vk}")"
                        break 2
                    fi
                fi
            done
        fi
    done

    if [ "${valid_cachy_boot}" -eq 0 ]; then
        log_error "Safety Guardrail: No verified, bootable CachyOS kernel + initramfs (>5MB) found in /boot!"
        log_error "Stock Slackware kernels must be retained to prevent an unbootable system."
        return 1
    fi

    log_info "Boot validation passed (Verified bootable kernel: ${found_cachy_kernel})."
    log_info "Transitioning system to Pure CachyOS Mode..."

    local stock_pkgs=("kernel-generic" "kernel-huge" "kernel-modules" "kernel-source")
    for pkg in "${stock_pkgs[@]}"; do
        local installed
        installed=$(ls /var/log/packages/${pkg}-* 2>/dev/null || true)
        if [ -n "${installed}" ]; then
            for p in ${installed}; do
                local base_p
                base_p=$(basename "${p}")
                log_info "Removing stock Slackware package: ${base_p}..."
                sudo "${PKG_REMOVE_CMD}" "${base_p}" 2>/dev/null || true
            done
        fi
    done

    # Add to blacklist if not already present
    local blacklist_file="/etc/slackpkg/blacklist"
    if [ -f "${blacklist_file}" ]; then
        if ! grep -q "Slacky-Update Pure CachyOS Mode" "${blacklist_file}"; then
            echo -e "\n# [Slacky-Update Pure CachyOS Mode]\nkernel-generic*\nkernel-huge*\nkernel-modules*\nkernel-source*" | sudo tee -a "${blacklist_file}" >/dev/null
            log_info "Stock kernels blacklisted in ${blacklist_file} (kernel-headers preserved)."
        fi
    fi

    log_success "System is now running on Pure CachyOS kernels!"
    sync_bootloader_configuration "$(uname -r)"
}

restore_stock_slackware_kernels() {
    validate_privileges

    echo ""
    echo -e "${CYAN}============================================================${RESET}"
    echo -e "${YELLOW}${BOLD}$(_ CACHY_PICKER_RESTORE_STOCK | sed -E 's/^[0-9]+\.\s*//')${RESET}"
    echo -e "${CYAN}============================================================${RESET}"
    echo -e "${YELLOW}${BOLD}$(_ PROMPT_CONFIRM_RESTORE_STOCK)${RESET}"
    read -r confirm_restore
    confirm_restore=${confirm_restore:-N}
    if [[ ! "${confirm_restore}" =~ ^[YyJjSsOo]$ ]]; then
        log_info "Operation cancelled by user."
        return 0
    fi

    log_info "Restoring stock Slackware kernel infrastructure..."
    local blacklist_file="/etc/slackpkg/blacklist"
    if [ -f "${blacklist_file}" ]; then
        sudo sed -i '/kernel-generic\*/d; /kernel-huge\*/d; /kernel-modules\*/d; /kernel-source\*/d; /\[Slacky-Update Pure CachyOS Mode\]/d' "${blacklist_file}" 2>/dev/null || true
        log_info "Un-blacklisted stock kernels in ${blacklist_file}."
    fi

    local slackpkg_bin
    slackpkg_bin=$(command -v slackpkg 2>/dev/null || echo "/usr/sbin/slackpkg")
    if [ -x "${slackpkg_bin}" ]; then
        log_info "Updating slackpkg repository index..."
        sudo "${slackpkg_bin}" update || true

        log_info "Installing official Slackware kernel-generic and kernel-modules..."
        sudo "${slackpkg_bin}" -batch=on -default_answer=y install kernel-generic kernel-modules || true
    fi

    local stock_kver=""
    for mod_d in /lib/modules/*; do
        [ -d "${mod_d}" ] || continue
        local bname
        bname=$(basename "${mod_d}")
        if [[ ! "${bname}" =~ cachyos ]]; then
            stock_kver="${bname}"
        fi
    done

    if [ -n "${stock_kver}" ]; then
        log_info "Regenerating initrd for stock kernel: ${stock_kver}..."
        generate_kernel_initramfs "${stock_kver}"
        sync_bootloader_configuration "${stock_kver}"
    else
        sync_bootloader_configuration "$(uname -r)"
    fi

    log_success "Official Slackware stock kernels successfully restored and integrated!"
}

prompt_stock_kernel_removal_if_eligible() {
    local just_deployed_flavor="$1"
    validate_privileges

    local has_stock=0
    if ls /var/log/packages/kernel-generic-* /var/log/packages/kernel-modules-* 2>/dev/null | grep -q 'kernel-'; then
        has_stock=1
    fi
    [ "${has_stock}" -eq 1 ] || return 0

    local installed_flavors
    installed_flavors=$(get_installed_cachyos_flavors)

    local has_lts=0
    local has_perf=0
    for flv in ${installed_flavors}; do
        [ "${flv}" = "lts" ] && has_lts=1
        [[ "${flv}" =~ ^(bore|lto|standard|rc)$ ]] && has_perf=1
    done

    # Guardrail: Must have BOTH LTS and a Performance/RC kernel to offer stock removal
    if [ "${has_lts}" -eq 1 ] && [ "${has_perf}" -eq 1 ]; then
        echo ""
        local reply_remove="N"
        if [ "${just_deployed_flavor}" = "lts" ]; then
            echo -e "${YELLOW}${BOLD}$(_ PROMPT_REMOVE_STOCK_MULTIPLE)${RESET}"
            read -r reply_remove
        else
            echo -e "${YELLOW}${BOLD}$(_ PROMPT_REMOVE_STOCK_DUAL)${RESET}"
            read -r reply_remove
        fi
        reply_remove=${reply_remove:-N}
        if [[ "${reply_remove}" =~ ^[YyJjSsOo]$ ]]; then
            remove_stock_slackware_kernels
        fi
    fi
}

cachyos_kernel_picker_interactive() {
    while true; do
        local st_ver bo_ver lto_ver rc_ver lts_ver
        st_ver=$(get_installed_cachyos_flavor_version "standard")
        bo_ver=$(get_installed_cachyos_flavor_version "bore")
        lto_ver=$(get_installed_cachyos_flavor_version "lto")
        rc_ver=$(get_installed_cachyos_flavor_version "rc")
        lts_ver=$(get_installed_cachyos_flavor_version "lts")

        local st_tag="[NOT INSTALLED]"
        local bo_tag="[NOT INSTALLED]"
        local lto_tag="[NOT INSTALLED]"
        local rc_tag="[NOT INSTALLED]"
        local lts_tag="[NOT INSTALLED]"
        [ "${st_ver}" != "NONE" ] && st_tag="[INSTALLED: ${st_ver}]"
        [ "${bo_ver}" != "NONE" ] && bo_tag="[INSTALLED: ${bo_ver}]"
        [ "${lto_ver}" != "NONE" ] && lto_tag="[INSTALLED: ${lto_ver}]"
        [ "${rc_ver}" != "NONE" ] && rc_tag="[INSTALLED: ${rc_ver}]"
        [ "${lts_ver}" != "NONE" ] && lts_tag="[INSTALLED: ${lts_ver}]"

        echo ""
        echo -e "${CYAN}============================================================${RESET}"
        echo -e "${YELLOW}${BOLD}$(_ CACHY_PICKER_TITLE)${RESET}"
        echo -e "${CYAN}============================================================${RESET}"
        echo -e "  1. \033[1;32mlinux-cachyos\033[0m ${st_tag}"
        echo -e "     $(_ CACHY_FLAVOR_STANDARD)"
        echo -e "  2. \033[1;32mlinux-cachyos-bore\033[0m ${bo_tag}"
        echo -e "     $(_ CACHY_FLAVOR_BORE)"
        echo -e "  3. \033[1;32mlinux-cachyos-bore-lto\033[0m ${lto_tag}"
        echo -e "     $(_ CACHY_FLAVOR_LTO)"
        echo -e "  4. \033[1;32mlinux-cachyos-rc\033[0m ${rc_tag}"
        echo -e "     $(_ CACHY_FLAVOR_RC)"
        echo -e "  5. \033[1;32mlinux-cachyos-lts\033[0m ${lts_tag}"
        echo -e "     $(_ CACHY_FLAVOR_LTS)"
        echo -e "  $(_ CACHY_PICKER_RESTORE_STOCK)"
        echo -e "  $(_ CACHY_PICKER_EXIT)"
        echo ""
        echo -n "$(_ SELECT_OPERATION_RANGE range="1-7") "
        read -r pchoice || pchoice="7"

        case "${pchoice}" in
            1)
                echo ""
                deploy_cachyos_kernel_flavor "standard"
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            2)
                echo ""
                deploy_cachyos_kernel_flavor "bore"
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            3)
                echo ""
                deploy_cachyos_kernel_flavor "lto"
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            4)
                echo ""
                deploy_cachyos_kernel_flavor "rc"
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            5)
                echo ""
                deploy_cachyos_kernel_flavor "lts"
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            6)
                echo ""
                restore_stock_slackware_kernels
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            7)
                return 0
                ;;
            *)
                echo -e "\n${YELLOW}$(_ INVALID_SELECTION)${RESET}"
                sleep 1
                ;;
        esac
    done
}

# --- [ ROOT FILESYSTEM & DEVICE RESOLUTION ] ---
detect_root_filesystem_details() {
    local root_dev root_fs root_uuid root_flags root_subvol

    # 1. Device resolution
    root_dev=$(findmnt -n -o SOURCE / 2>/dev/null || true)
    if [ -z "${root_dev}" ]; then
        root_dev=$(awk '$2 == "/" {print $1}' /proc/mounts 2>/dev/null | head -n1 || true)
    fi
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
        root_subvol=$(echo "${mnt_opts}" | tr ',' '\n' | grep -E '^subvol=' | head -n1 || true)
        if [ -n "${root_subvol}" ]; then
            root_flags="rootflags=${root_subvol}"
        fi
    fi

    echo "${root_dev}|${root_fs}|${root_uuid}|${root_flags}"
}

set_grub_smart_default_priority() {
    local top_dog
    top_dog=$(python3 -c "
import os, re

def rank_kernel(k):
    tier = -2
    if '-cachyos-bore-lto' in k or '-cachyos-lto' in k:
        tier = 4
    elif '-cachyos-bore' in k:
        tier = 5
    elif '-cachyos-rc' in k:
        tier = 3
    elif '-cachyos-lts' in k:
        tier = 1
    elif '-cachyos' in k:
        tier = 2
    elif 'vmlinuz-generic' in k:
        tier = 0
    elif 'vmlinuz-huge' in k:
        tier = -1
    nums = [int(x) for x in re.findall(r'\d+', k)]
    return (tier, nums)

kernels = [f for f in os.listdir('/boot') if f.startswith('vmlinuz') and not os.path.islink(os.path.join('/boot', f))]
ranked = sorted(kernels, key=rank_kernel, reverse=True)
if ranked:
    print('/boot/' + ranked[0])
" 2>/dev/null || echo "")

    if [ -n "${top_dog}" ] && [ -f "${top_dog}" ]; then
        log_info "Smart Boot Priority: Setting Top Dog default in GRUB (${top_dog})..."
        echo -e "  \033[1;36m• Primary Boot Kernel (Top Dog):\033[0m \033[1;32m$(basename "${top_dog}")\033[0m"
        local grub_default_file="/etc/default/grub"
        if [ -f "${grub_default_file}" ]; then
            if grep -q "^GRUB_TOP_LEVEL=" "${grub_default_file}"; then
                sudo sed -i "s|^GRUB_TOP_LEVEL=.*|GRUB_TOP_LEVEL=\"${top_dog}\"|" "${grub_default_file}"
            else
                echo "GRUB_TOP_LEVEL=\"${top_dog}\"" | sudo tee -a "${grub_default_file}" >/dev/null
            fi
        fi
    fi
}

# --- [ BOOTLOADER SYNCHRONIZATION & CMDLINE INJECTION ] ---
sync_bootloader_configuration() {
    local kver_full="$1"
    validate_privileges
    probe_gpu_hardware

    local required_params=""
    if [ "${HAS_NVIDIA}" = "true" ]; then
        required_params="nvidia_drm.modeset=1 nvidia_drm.fbdev=1 nvidia.NVreg_PreserveVideoMemoryAllocations=1"
    fi

    local root_dev root_fs root_uuid root_flags
    IFS='|' read -r root_dev root_fs root_uuid root_flags <<< "$(detect_root_filesystem_details)"

    local root_cmd="root=${root_dev}"
    if [ -n "${root_uuid}" ]; then
        root_cmd="root=UUID=${root_uuid}"
    fi

    local root_extra=""
    if [ -n "${root_flags}" ]; then
        root_extra=" ${root_flags}"
    fi

    # 1. GRUB Configuration (CRITICAL: Never execute grub-install, preserve signed Shim)
    local grub_mkconfig_bin
    grub_mkconfig_bin=$(command -v grub-mkconfig 2>/dev/null || command -v grub2-mkconfig 2>/dev/null || echo "/usr/sbin/grub-mkconfig")
    if [ -x "${grub_mkconfig_bin}" ]; then
        local grub_default_file="/etc/default/grub"
        if [ -f "${grub_default_file}" ]; then
            python3 - << PYGRUB
import os, re

cfg_path = "${grub_default_file}"
try:
    with open(cfg_path, "r", encoding="utf-8") as f:
        content = f.read()

    m = re.search(r'^(GRUB_CMDLINE_LINUX_DEFAULT=\")([^\"]*)(\")', content, re.MULTILINE)
    if m:
        prefix, cmdline, suffix = m.group(1), m.group(2), m.group(3)
        tokens = cmdline.strip().split()
        seen = set()
        result = []
        for t in tokens:
            norm = t
            if norm.startswith("nvidia-drm."):
                norm = "nvidia_drm." + norm[len("nvidia-drm."):]
            elif norm.startswith("nvidia-modeset."):
                norm = "nvidia_modeset." + norm[len("nvidia-modeset."):]
            elif norm.startswith("nvidia-uvm."):
                norm = "nvidia_uvm." + norm[len("nvidia-uvm."):]
            if norm not in seen:
                seen.add(norm)
                result.append(norm)

        has_nv = "${HAS_NVIDIA}".lower() == "true"
        if has_nv:
            for req in ["nvidia_drm.modeset=1", "nvidia_drm.fbdev=1", "nvidia.NVreg_PreserveVideoMemoryAllocations=1"]:
                if req not in seen:
                    seen.add(req)
                    result.append(req)

        new_cmdline = " ".join(result)
        if new_cmdline != cmdline:
            new_content = content[:m.start()] + prefix + new_cmdline + suffix + content[m.end():]
            with open(cfg_path, "w", encoding="utf-8") as f:
                f.write(new_content)
except Exception:
    pass
PYGRUB
        fi
        set_grub_smart_default_priority
        if [ -f "/boot/grub/grub.cfg" ]; then
            log_info "Synchronizing GRUB bootloader configuration (/boot/grub/grub.cfg)..."
            sudo "${grub_mkconfig_bin}" -o /boot/grub/grub.cfg >/dev/null 2>&1 || true
        elif [ -f "/boot/grub2/grub.cfg" ]; then
            log_info "Synchronizing GRUB bootloader configuration (/boot/grub2/grub.cfg)..."
            sudo "${grub_mkconfig_bin}" -o /boot/grub2/grub.cfg >/dev/null 2>&1 || true
        fi
    fi

    # 2. Limine Bootloader Configuration
    local initrd_target="initrd-${kver_full}.gz"
    if [ -f "/boot/initramfs-${kver_full}.img" ]; then
        initrd_target="initramfs-${kver_full}.img"
    fi

    for limine_cfg in /boot/limine.conf /boot/limine/limine.conf /boot/efi/limine.conf; do
        if [ -f "${limine_cfg}" ]; then
            log_info "Synchronizing Limine bootloader configuration (${limine_cfg})..."
            if ! grep -q "vmlinuz-${kver_full}" "${limine_cfg}"; then
                python3 - << PYLIM
import os

cfg_path = "${limine_cfg}"
kver = "${kver_full}"
initrd_name = "${initrd_target}"
root_cmd = "${root_cmd}${root_extra}"
params = "${required_params}".strip()
full_cmd = f"{root_cmd} rw quiet splash {params}".strip()

entry = f"""
/CachyOS Linux ({kver})
    protocol: linux
    kernel_path: boot():/boot/vmlinuz-{kver}
    initrd_path: boot():/boot/{initrd_name}
    cmdline: {full_cmd}
"""

try:
    with open(cfg_path, "r", encoding="utf-8") as f:
        content = f.read()
    if f"vmlinuz-{kver}" not in content:
        with open(cfg_path, "a", encoding="utf-8") as f:
            f.write(entry)
except Exception:
    pass
PYLIM
            fi
        fi
    done

    log_success "Bootloader synchronization completed."
}

verify_cachyos_package_integrity() {
    local archive="$1"
    [ -f "${archive}" ] || return 1
    if ! zstd -t "${archive}" >/dev/null 2>&1; then
        log_error "Archive $(basename "${archive}") failed zstd CRC integrity verification!"
        return 1
    fi
    if ! tar --zstd -tf "${archive}" >/dev/null 2>&1; then
        log_error "Archive $(basename "${archive}") failed tar structure verification!"
        return 1
    fi
    return 0
}

check_boot_disk_space() {
    local min_free_mb="${1:-250}"
    local free_kb
    free_kb=$(df -k /boot 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -n "${free_kb}" ]; then
        local free_mb=$(( free_kb / 1024 ))
        if [ "${free_mb}" -lt "${min_free_mb}" ]; then
            log_warn "Low disk space on /boot: ${free_mb} MB free (recommended: at least ${min_free_mb} MB)."
            return 1
        fi
    fi
    return 0
}

deploy_cachyos_kernel_packages() {
    local ver="$1"
    local k_url="$2"
    local h_url="$3"
    local flavor="${4:-standard}"
    local nv_url="${5:-NONE}"
    validate_privileges
    probe_gpu_hardware
    if ! check_boot_disk_space 250; then
        log_warn "Proceeding with caution, but /boot partition is running very low on disk space."
    fi

    local dest_dir="/var/cache/slacky-update/kernel"
    sudo mkdir -p "${dest_dir}"

    local k_filename h_filename
    k_filename=$(basename "${k_url}")
    h_filename=$(basename "${h_url}")

    local k_file="${dest_dir}/${k_filename}"
    local h_file="${dest_dir}/${h_filename}"

    log_info "Downloading kernel package (${k_filename})..."
    sudo curl -sSL -o "${k_file}" "${k_url}"
    log_info "Downloading kernel headers package (${h_filename})..."
    sudo curl -sSL -o "${h_file}" "${h_url}"

    log_info "Verifying archive integrity for kernel and headers packages..."
    if ! verify_cachyos_package_integrity "${k_file}" || ! verify_cachyos_package_integrity "${h_file}"; then
        log_error "Kernel package integrity verification failed! Aborting deployment to prevent system corruption."
        sudo rm -f "${k_file}" "${h_file}" 2>/dev/null || true
        return 1
    fi

    log_info "Extracting kernel package to system root..."
    sudo tar --zstd -xf "${k_file}" -C /

    log_info "Extracting kernel headers package to system root..."
    sudo tar --zstd -xf "${h_file}" -C /

    local kver_full=""
    if [ "${flavor}" = "bore" ]; then
        kver_full="${ver}-cachyos-bore"
    elif [ "${flavor}" = "lto" ]; then
        kver_full="${ver}-cachyos-bore-lto"
        if [ ! -d "/usr/lib/modules/${kver_full}" ] && [ -d "/usr/lib/modules/${ver}-cachyos-lto" ]; then
            kver_full="${ver}-cachyos-lto"
        fi
    elif [ "${flavor}" = "rc" ]; then
        kver_full="${ver}-cachyos-rc"
    elif [ "${flavor}" = "lts" ]; then
        kver_full="${ver}-cachyos-lts"
    else
        kver_full="${ver}-cachyos"
    fi

    if [ -d "/usr/lib/modules/${kver_full}" ] && [ ! -d "/lib/modules/${kver_full}" ]; then
        sudo mkdir -p /lib/modules
        sudo ln -sf "/usr/lib/modules/${kver_full}" "/lib/modules/${kver_full}"
    fi

    if [ -f "/boot/vmlinuz-linux-cachyos-bore-lto" ] && [ "${flavor}" = "lto" ]; then
        sudo cp -f "/boot/vmlinuz-linux-cachyos-bore-lto" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/boot/vmlinuz-linux-cachyos-bore" ] && [ "${flavor}" = "bore" ]; then
        sudo cp -f "/boot/vmlinuz-linux-cachyos-bore" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/boot/vmlinuz-linux-cachyos-rc" ] && [ "${flavor}" = "rc" ]; then
        sudo cp -f "/boot/vmlinuz-linux-cachyos-rc" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/boot/vmlinuz-linux-cachyos-lts" ] && [ "${flavor}" = "lts" ]; then
        sudo cp -f "/boot/vmlinuz-linux-cachyos-lts" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/boot/vmlinuz-linux-cachyos" ] && [ "${flavor}" = "standard" ]; then
        sudo cp -f "/boot/vmlinuz-linux-cachyos" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/usr/lib/modules/${kver_full}/vmlinuz" ]; then
        sudo cp -f "/usr/lib/modules/${kver_full}/vmlinuz" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/lib/modules/${kver_full}/vmlinuz" ]; then
        sudo cp -f "/lib/modules/${kver_full}/vmlinuz" "/boot/vmlinuz-${kver_full}"
    fi

    if [ -d "/usr/src/linux-headers-${kver_full}" ]; then
        sudo ln -sf "/usr/src/linux-headers-${kver_full}" "/lib/modules/${kver_full}/build"
        sudo ln -sf "/usr/src/linux-headers-${kver_full}" "/lib/modules/${kver_full}/source"
    elif [ -d "/usr/lib/modules/${kver_full}/build" ]; then
        sudo ln -sf "/usr/lib/modules/${kver_full}/build" "/lib/modules/${kver_full}/source"
    fi

    # Fetch and deploy matching CachyOS NVIDIA driver if on supported NVIDIA GPU
    if [ "${HAS_NVIDIA}" = "true" ]; then
        local gpu_arch="MODERN"
        if command -v detect_nvidia_gpu >/dev/null 2>&1; then
            gpu_arch=$(detect_nvidia_gpu)
        fi

        if [ "${gpu_arch}" = "LEGACY" ]; then
            log_warn "NVIDIA GPU is older than Pascal (pre-GTX 10-series). CachyOS kernels do not support legacy proprietary drivers."
        elif [ "${gpu_arch}" = "PASCAL" ]; then
            log_info "Pascal GPU architecture detected (GTX 10-series):"
            log_info "NVIDIA Open modules are unsupported on pre-Turing hardware."
            log_info "Fetching matching nvidia-580xx-dkms from CachyOS repository..."
            local cachy_base="https://mirror.cachyos.org/repo/x86_64/cachyos"
            local dkms_pkg
            dkms_pkg=$(curl -sSL -m 10 "${cachy_base}/" 2>/dev/null | grep -o -E 'nvidia-580xx-dkms-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst' | head -n 1 || echo "")
            if [ -n "${dkms_pkg}" ]; then
                local dkms_file="${dest_dir}/${dkms_pkg}"
                log_info "Downloading ${dkms_pkg}..."
                sudo curl -sSL -o "${dkms_file}" "${cachy_base}/${dkms_pkg}"
                if ! verify_cachyos_package_integrity "${dkms_file}"; then
                    log_error "DKMS package integrity verification failed! Skipping extraction."
                    sudo rm -f "${dkms_file}" 2>/dev/null || true
                else
                    sudo tar --zstd -xf "${dkms_file}" -C /
                    if command -v dkms >/dev/null 2>&1; then
                        local dkms_ver
                        dkms_ver=$(dkms status 2>/dev/null | grep -E '^nvidia/' | awk -F'[,/]' '{print $2}' | tr -d ' ' | head -n 1 || echo "580.178.04")
                        log_info "Building nvidia ${dkms_ver} for kernel ${kver_full} via DKMS..."
                        sudo dkms build -m nvidia -v "${dkms_ver}" -k "${kver_full}" 2>/dev/null || true
                        sudo dkms install -m nvidia -v "${dkms_ver}" -k "${kver_full}" 2>/dev/null || true
                    fi
                fi
            else
                log_warn "Could not resolve nvidia-580xx-dkms package from CachyOS repository."
            fi
        elif [ "${gpu_arch}" = "MODERN" ]; then
            if [ "${nv_url}" != "NONE" ] && [ -n "${nv_url}" ]; then
                local nv_filename
                nv_filename=$(basename "${nv_url}")
                local nv_file="${dest_dir}/${nv_filename}"
                log_info "Modern NVIDIA GPU detected (Turing 20-series+). Downloading prebuilt matching CachyOS NVIDIA Open driver (${nv_filename})..."
                sudo curl -sSL -o "${nv_file}" "${nv_url}"
                if ! verify_cachyos_package_integrity "${nv_file}"; then
                    log_error "NVIDIA driver package integrity verification failed! Skipping extraction."
                    sudo rm -f "${nv_file}" 2>/dev/null || true
                else
                    log_info "Extracting NVIDIA driver package to system root..."
                    sudo tar --zstd -xf "${nv_file}" -C /
                fi
            fi
        fi
    fi

    local depmod_bin
    depmod_bin=$(command -v depmod 2>/dev/null || echo "/sbin/depmod")
    sudo "${depmod_bin}" -a "${kver_full}"
    log_success "Kernel deployed: ${kver_full}"

    # 1. Build DKMS out-of-tree modules (NVIDIA) only if on NVIDIA GPU and modules not yet in tree
    if [ "${HAS_NVIDIA}" = "true" ]; then
        if [ ! -d "/usr/lib/modules/${kver_full}/kernel/drivers/video" ] && [ ! -d "/lib/modules/${kver_full}/kernel/drivers/video" ]; then
            if command -v build_nvidia_modules >/dev/null 2>&1; then
                build_nvidia_modules "${kver_full}"
            fi
        else
            log_info "Matching CachyOS NVIDIA driver modules active in kernel tree."
        fi

        # Synchronize CachyOS NVIDIA user-space package and any stock Slackware kernels
        if command -v ensure_cachyos_nvidia_duties >/dev/null 2>&1; then
            ensure_cachyos_nvidia_duties
        fi
    fi

    # 2. Generate initramfs image (Dracut / mkinitrd)
    generate_kernel_initramfs "${kver_full}"

    # 3. Enforce Secure Boot MOK signing for new kernel image and modules
    if command -v enforce_secure_boot_armor >/dev/null 2>&1; then
        enforce_secure_boot_armor
    fi

    # 4. Synchronize bootloader (GRUB / Limine)
    sync_bootloader_configuration "${kver_full}"
}

# --- [ HYBRID INITRAMFS ENGINE ROUTER ] ---
detect_initramfs_engine() {
    if command -v dracut >/dev/null 2>&1; then
        if [ -d "/etc/dracut.conf.d" ] || [ -f "/etc/dracut.conf" ] || ls /boot/initramfs-*.img >/dev/null 2>&1; then
            echo "dracut"
            return 0
        fi
    fi
    echo "mkinitrd"
}

generate_kernel_initramfs() {
    local kver="$1"
    validate_privileges
    probe_gpu_hardware
    if ! check_boot_disk_space 250; then
        log_warn "Proceeding with caution, but /boot partition is running very low on disk space."
    fi

    local engine
    engine=$(detect_initramfs_engine)
    log_info "Initramfs Engine Selected: ${engine}"

    if [ "${engine}" = "dracut" ]; then
        local dracut_bin
        dracut_bin=$(command -v dracut 2>/dev/null || echo "/usr/bin/dracut")
        local dracut_args=(--force)
        if [ "$(uname -m)" = "x86_64" ] && [ -d "/usr/lib64" ]; then
            dracut_args+=(--libdirs "/lib64 /usr/lib64 /usr/local/lib64")
            if [ -d "/etc/dracut.conf.d" ] && [ ! -f "/etc/dracut.conf.d/00-multilib.conf" ]; then
                echo 'libdirs=" /lib64 /usr/lib64 /usr/local/lib64 "' | sudo tee /etc/dracut.conf.d/00-multilib.conf >/dev/null 2>&1 || true
            fi
        fi
        if [ "${HAS_NVIDIA}" = "true" ]; then
            dracut_args+=(--add-drivers "nvidia nvidia_modeset nvidia_uvm nvidia_drm")
        fi

        if [ "${kver}" = "ALL" ]; then
            log_info "Regenerating Dracut initramfs images for all installed kernels..."
            for kdir in /lib/modules/*; do
                [ -d "${kdir}" ] || continue
                local single_kver
                single_kver=$(basename "${kdir}")
                if [ -f "/boot/vmlinuz-${single_kver}" ] || [ -f "/boot/vmlinuz-generic" ] || [ -d "/lib/modules/${single_kver}/kernel" ]; then
                    local initrd_out="/boot/initramfs-${single_kver}.img"
                    log_info "Generating Dracut initramfs for kernel: ${single_kver} -> ${initrd_out}..."
                    if sudo env -i PATH="/usr/local/sbin:/usr/local/bin:/sbin:/usr/sbin:/bin:/usr/bin" "${dracut_bin}" "${dracut_args[@]}" "${initrd_out}" "${single_kver}"; then
                        # Clean up legacy mkinitrd files for this kernel ONLY after verified successful Dracut generation (>5MB)
                        local img_sz=0
                        if [ -f "${initrd_out}" ]; then
                            img_sz=$(stat -c%s "${initrd_out}" 2>/dev/null || echo 0)
                        fi
                        if [ "${img_sz}" -gt 5000000 ]; then
                            sudo rm -f "/boot/initrd-${single_kver}.img" "/boot/initrd-${single_kver}.gz" "/boot/initrd-${single_kver}" 2>/dev/null || true
                        else
                            log_warn "Generated Dracut image ${initrd_out} is unexpectedly small (${img_sz} bytes). Preserving existing initrd backup."
                        fi
                    fi
                fi
            done

            # Clean orphaned initramfs images
            for img in /boot/initramfs-*.img; do
                [ -f "${img}" ] || continue
                local img_kver
                img_kver=$(basename "${img}" | sed -e 's/^initramfs-//' -e 's/\.img$//')
                if [ ! -d "/lib/modules/${img_kver}" ] && [ ! -d "/usr/lib/modules/${img_kver}" ]; then
                    log_info "Removing orphaned initramfs image: ${img}"
                    sudo rm -f "${img}" 2>/dev/null || true
                fi
            done

            log_success "Dracut initramfs regeneration completed for all kernels."
            return 0
        else
            local initrd_out="/boot/initramfs-${kver}.img"
            log_info "Generating Dracut initramfs for kernel: ${kver} -> ${initrd_out}..."
            if sudo env -i PATH="/usr/local/sbin:/usr/local/bin:/sbin:/usr/sbin:/bin:/usr/bin" "${dracut_bin}" "${dracut_args[@]}" "${initrd_out}" "${kver}"; then
                # Clean up legacy mkinitrd files for this kernel ONLY after verified successful Dracut generation (>5MB)
                local img_sz=0
                if [ -f "${initrd_out}" ]; then
                    img_sz=$(stat -c%s "${initrd_out}" 2>/dev/null || echo 0)
                fi
                if [ "${img_sz}" -gt 5000000 ]; then
                    sudo rm -f "/boot/initrd-${kver}.img" "/boot/initrd-${kver}.gz" "/boot/initrd-${kver}" 2>/dev/null || true
                else
                    log_warn "Generated Dracut image ${initrd_out} is unexpectedly small (${img_sz} bytes). Preserving existing initrd backup."
                fi
                log_success "Dracut initramfs generated: ${initrd_out}"
                return 0
            else
                log_error "Dracut initramfs generation failed for kernel: ${kver}"
                return 1
            fi
        fi
    else
        # Legacy Slackware mkinitrd fallback
        if [ "${kver}" = "ALL" ]; then
            local gen_script
            gen_script=$(command -v mkinitrd_command_generator.sh 2>/dev/null || echo "/sbin/mkinitrd_command_generator.sh")
            if [ -x "${gen_script}" ]; then
                log_info "Regenerating mkinitrd images using Slackware generator..."
                sudo bash <("${gen_script}") 2>/dev/null || true
            elif [ -d "/lib/modules" ]; then
                for kdir in /lib/modules/*; do
                    [ -d "${kdir}" ] || continue
                    local single_kver
                    single_kver=$(basename "${kdir}")
                    generate_legacy_mkinitrd "${single_kver}"
                done
            fi
            log_success "mkinitrd generation completed for all kernels."
            return 0
        else
            generate_legacy_mkinitrd "${kver}"
        fi
    fi
}

generate_legacy_mkinitrd() {
    local kver="$1"
    local initrd_out="/boot/initrd-${kver}.gz"
    validate_privileges
    probe_gpu_hardware

    log_info "Generating legacy mkinitrd for kernel: ${kver}..."

    local ucode_opt=""
    if [ -f "/boot/intel-ucode.cpio" ]; then
        ucode_opt="-u /boot/intel-ucode.cpio"
    elif [ -f "/boot/amd-ucode.cpio" ]; then
        ucode_opt="-u /boot/amd-ucode.cpio"
    fi

    local root_dev root_fs root_uuid root_flags
    IFS='|' read -r root_dev root_fs root_uuid root_flags <<< "$(detect_root_filesystem_details)"
    log_info "Detected root device: ${root_dev} (${root_fs})"

    local base_modules="${root_fs}:nvme:xhci-pci:ahci:sd_mod"
    if [ "${root_fs}" = "btrfs" ]; then
        base_modules="btrfs:zstd:crc32c:nvme:xhci-pci"
    elif [ "${root_fs}" = "ext4" ]; then
        base_modules="ext4:crc32c:nvme:xhci-pci:ahci:sd_mod"
    elif [ "${root_fs}" = "xfs" ]; then
        base_modules="xfs:crc32c:nvme:xhci-pci:ahci:sd_mod"
    elif [ "${root_fs}" = "f2fs" ]; then
        base_modules="f2fs:crc32:nvme:xhci-pci:ahci:sd_mod"
    fi

    local nvidia_modules=""
    if [ "${HAS_NVIDIA}" = "true" ] || [ -d "/lib/modules/${kver}/kernel/drivers/video" ]; then
        nvidia_modules=":nvidia:nvidia-modeset:nvidia-uvm:nvidia-drm"
        log_info "NVIDIA hardware identified. Bundling video modules into initrd."
    fi

    local combined_modules="${base_modules}${nvidia_modules}"

    local root_param="${root_dev}"
    if [ -n "${root_uuid}" ]; then
        root_param="UUID=${root_uuid}"
    fi

    if ! sudo "${MKINITRD_CMD}" -c -k "${kver}" -m "${combined_modules}" -f "${root_fs}" -r "${root_param}" ${ucode_opt} -o "${initrd_out}"; then
        log_warn "Standard mkinitrd completed with warnings. Running fallback..."
        sudo "${MKINITRD_CMD}" -c -k "${kver}" -o "${initrd_out}"
    fi

    log_success "Initrd generated: ${initrd_out}"
}

# Backwards compatibility alias
generate_cachy_initrd() {
    generate_kernel_initramfs "$1"
}
