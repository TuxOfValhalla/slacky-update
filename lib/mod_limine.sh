#!/usr/bin/env bash
# --- [ LIMINE BOOTLOADER & UEFI SECURE BOOT ENGINE ] ---
# Slacky-Update Unified Limine Suite: limine (>=12.x), limine-entry-tool, limine-snapper-sync, sbctl

set -euo pipefail

# --- [ CONSTANTS & ENDPOINTS ] ---
CACHYOS_REPO_BASE="https://mirror.cachyos.org/repo/x86_64/cachyos"
ARCH_EXTRA_REPO_BASE="https://geo.mirror.pkgbuild.com/extra/os/x86_64"

MIN_BOOT_PARTITION_MB=4096

# --- [ DETECT LIMINE INSTALLATION & ESP PATH ] ---
detect_limine_esp_path() {
    # Check explicitly defined ESP_PATH from /etc/default/limine or /etc/limine-entry-tool.conf
    for cfg in /etc/default/limine /etc/limine-entry-tool.conf; do
        if [ -f "${cfg}" ]; then
            local custom_esp
            custom_esp=$(grep -E '^[[:space:]]*ESP_PATH=' "${cfg}" 2>/dev/null | tail -n 1 | cut -d'=' -f2 | tr -d '"'\'' ' || true)
            if [ -n "${custom_esp}" ] && [ -d "${custom_esp}" ]; then
                echo "${custom_esp}"
                return 0
            fi
        fi
    done

    # Check mounted FAT32 partitions: /boot, /boot/efi, /efi, /limine
    for candidate in /boot /boot/efi /boot/EFI /efi /limine; do
        if [ -d "${candidate}" ]; then
            local fs_type
            fs_type=$(findmnt -n -o FSTYPE "${candidate}" 2>/dev/null || true)
            if [ "${fs_type}" = "vfat" ]; then
                echo "${candidate}"
                return 0
            fi
        fi
    done

    # Fallback to standard EFI mount
    if [ -d "/boot/efi" ]; then
        echo "/boot/efi"
    elif [ -d "/boot" ]; then
        echo "/boot"
    else
        echo "/boot/efi"
    fi
}

is_limine_installed() {
    local esp_path
    esp_path=$(detect_limine_esp_path)

    if [ -f "${esp_path}/EFI/limine/limine_x64.efi" ] || \
       [ -f "${esp_path}/EFI/limine/BOOTX64.EFI" ] || \
       [ -f "${esp_path}/limine.conf" ] || \
       [ -f "/boot/limine.conf" ] || \
       [ -f "/boot/limine/limine.conf" ] || \
       [ -f "/etc/default/limine" ]; then
        echo "true"
        return 0
    fi

    echo "false"
    return 1
}

# --- [ HARD 4GB PARTITION PRE-FLIGHT GUARD ] ---
check_boot_partition_eligibility() {
    local target_path="${1:-}"
    if [ -z "${target_path}" ]; then
        target_path=$(detect_limine_esp_path)
    fi

    if [ ! -d "${target_path}" ]; then
        log_error "Boot path '${target_path}' does not exist."
        return 1
    fi

    local fs_type
    fs_type=$(findmnt -n -o FSTYPE "${target_path}" 2>/dev/null || true)
    if [ "${fs_type}" != "vfat" ]; then
        log_error "Boot path '${target_path}' is formatted as '${fs_type}', not FAT32 (vfat)!"
        log_error "Limine Secure Boot verification requires a dedicated FAT32 ESP partition."
        return 1
    fi

    # Determine total partition capacity in MB
    local total_mb=0
    local size_bytes
    size_bytes=$(findmnt -b -n -o SIZE "${target_path}" 2>/dev/null || true)
    if [ -n "${size_bytes}" ] && [ "${size_bytes}" -gt 0 ] 2>/dev/null; then
        total_mb=$(( size_bytes / 1024 / 1024 ))
    else
        local size_kb
        size_kb=$(df -k "${target_path}" 2>/dev/null | awk 'NR==2 {print $2}')
        if [ -n "${size_kb}" ] && [ "${size_kb}" -gt 0 ] 2>/dev/null; then
            total_mb=$(( size_kb / 1024 ))
        fi
    fi

    if [ "${total_mb}" -lt "${MIN_BOOT_PARTITION_MB}" ]; then
        echo ""
        log_error "Safety Guardrail: Insufficient boot partition capacity on ${target_path}!"
        echo -e "  • ${BOLD}Current Total Size:${RESET} ${RED}${total_mb} MB${RESET}"
        echo -e "  • ${BOLD}Required Minimum:${RESET}   ${GREEN}${MIN_BOOT_PARTITION_MB} MB (4 GB)${RESET}"
        echo ""
        echo -e "${YELLOW}Limine multi-kernel staging with Secure Boot hashing requires at least 4 GB (4096 MB) on FAT32.${RESET}"
        echo -e "${CYAN}Your existing bootloader (GRUB/ELILO) has been safely preserved and untouched.${RESET}"
        echo ""
        return 1
    fi

    log_success "Boot partition check passed: ${target_path} (${total_mb} MB FAT32 >= ${MIN_BOOT_PARTITION_MB} MB)."
    return 0
}

# --- [ MACHINE ID RESOLUTION ] ---
get_or_create_machine_id() {
    local mid_file="/etc/machine-id"
    if [ ! -s "${mid_file}" ]; then
        validate_privileges
        local new_id
        new_id=$(python3 -c "import uuid; print(uuid.uuid4().hex)" 2>/dev/null || od -x /dev/urandom | head -1 | awk '{print $2$3$4$5$6$7$8$9}' | head -c 32)
        echo "${new_id}" | sudo tee "${mid_file}" >/dev/null
        sudo chmod 444 "${mid_file}"
    fi
    cat "${mid_file}" | tr -d '\n\r '
}

# --- [ UNIFIED LIMINE SUITE PACKAGE MANAGEMENT ] ---
get_limine_suite_catalog() {
    cat << 'CATALOG_EOF'
limine|Limine Bootloader (>= 12.x EFI & Tools)|bootloader|limine-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||cachyos
limine-entry-tool|Limine Entry Tool (Config & Enrollment Generator)|bootloader|limine-entry-tool-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||cachyos
limine-snapper-sync|Limine Snapper Sync (Btrfs Snapshot Integrator)|bootloader|limine-snapper-sync-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||cachyos
sbctl|sbctl (Secure Boot Key Manager & Signer)|bootloader|sbctl-[0-9][a-zA-Z0-9_\.-]*\.pkg\.tar\.zst|||arch-extra,cachyos
CATALOG_EOF
}

install_unified_limine_suite() {
    validate_privileges

    log_info "Verifying boot partition eligibility before deploying Limine suite..."
    local esp_path
    esp_path=$(detect_limine_esp_path)
    if ! check_boot_partition_eligibility "${esp_path}"; then
        return 1
    fi

    log_info "Installing Unified Limine Suite (limine, limine-entry-tool, limine-snapper-sync, sbctl)..."
    local suite_pkgs=("limine" "limine-entry-tool" "limine-snapper-sync" "sbctl")
    for pkg_id in "${suite_pkgs[@]}"; do
        if command -v install_cachyos_gaming_package >/dev/null 2>&1; then
            install_cachyos_gaming_package "${pkg_id}"
        fi
    done

    # Ensure /etc/default/limine exists with clean defaults
    if [ ! -f "/etc/default/limine" ]; then
        sudo mkdir -p /etc/default
        cat << LIMINE_DEFAULT_EOF | sudo tee /etc/default/limine >/dev/null
# /etc/default/limine - Slacky-Update Limine Configuration
ESP_PATH="${esp_path}"
ENABLE_VERIFICATION=yes
ENABLE_ENROLL_LIMINE_CONFIG=yes
FIND_BOOTLOADERS=yes
BOOT_ORDER="*, *fallback, Snapshots"
CONFIG_BACKUP_THRESHOLD=6
LIMINE_DEFAULT_EOF
        sudo chmod 644 /etc/default/limine
    fi

    log_success "Unified Limine Suite deployed successfully."
    return 0
}

# --- [ LIMINE CONFIGURATION GENERATOR WITH BLAKE2B HASHING ] ---
generate_limine_configuration() {
    validate_privileges
    probe_gpu_hardware

    local esp_path
    esp_path=$(detect_limine_esp_path)
    if [ ! -d "${esp_path}" ]; then
        log_error "ESP path '${esp_path}' not found."
        return 1
    fi

    log_info "Scanning system kernels and generating CachyOS-compliant limine.conf..."
    local machine_id
    machine_id=$(get_or_create_machine_id)

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

    local nvidia_params=""
    if [ "${HAS_NVIDIA}" = "true" ]; then
        nvidia_params=" nvidia_drm.modeset=1 nvidia_drm.fbdev=1 nvidia.NVreg_PreserveVideoMemoryAllocations=1"
    fi

    local standard_cmdline="${root_cmd}${root_extra} rw quiet splash${nvidia_params}"
    local fallback_cmdline="${root_cmd}${root_extra} ro single${nvidia_params}"

    # Verify splash wallpaper and compute BLAKE2B hash
    local splash_line=""
    local splash_path=""
    for cand in "${esp_path}/limine-splash.png" "${esp_path}/splash.png" "/usr/share/slacky-update/assets/slackware_icon_HD.png"; do
        if [ -f "${cand}" ]; then
            splash_path="${cand}"
            break
        fi
    done

    if [ -n "${splash_path}" ] && [ -f "${splash_path}" ]; then
        local target_splash="${esp_path}/limine-splash.png"
        if [ "${splash_path}" != "${target_splash}" ]; then
            sudo cp -f "${splash_path}" "${target_splash}"
        fi
        local splash_hash
        splash_hash=$(b2sum "${target_splash}" 2>/dev/null | awk '{print $1}' || echo "")
        if [ -n "${splash_hash}" ]; then
            splash_line="wallpaper: boot():/limine-splash.png#${splash_hash}\nwallpaper_style: stretched\n"
        fi
    fi

    # Build kernel entries dynamically
    local kernel_entries=""
    local kernels=()
    while IFS= read -r k; do
        [ -n "${k}" ] && kernels+=("${k}")
    done < <(python3 -c "
import os, re

def rank(k):
    tier = -50
    if '-cachyos-bore-lto' in k or '-cachyos-lto' in k:
        tier = 50
    elif '-cachyos-bore' in k:
        tier = 40
    elif '-cachyos' in k and '-rc' not in k and '-lts' not in k:
        tier = 30
    elif '-cachyos-lts' in k:
        tier = 20
    elif '-cachyos-rc' in k:
        tier = 10
    elif 'vmlinuz-generic' in k or 'generic' in k:
        tier = -40
    elif 'vmlinuz-huge' in k or 'huge' in k:
        tier = -60
    nums = [int(x) for x in re.findall(r'\d+', k)]
    return (tier, nums)

search_dirs = ['/boot'] if os.path.exists('/boot') and '${esp_path}' != '/boot' else ['${esp_path}']
found = set()
for d in search_dirs:
    if os.path.exists(d):
        for f in os.listdir(d):
            if f.startswith('vmlinuz-') and not os.path.islink(os.path.join(d, f)):
                found.add(f.replace('vmlinuz-', ''))

ranked = sorted(list(found), key=rank, reverse=True)
for r in ranked:
    print(r)
" 2>/dev/null || true)

    if [ ${#kernels[@]} -eq 0 ]; then
        log_warn "No kernels found in /boot or ${esp_path} to configure in Limine."
    fi

    # Prune orphaned kernels and initramfs from ESP if /boot and ESP are separate
    if [ "${esp_path}" != "/boot" ] && [ -d "${esp_path}" ]; then
        for esp_f in "${esp_path}"/vmlinuz-*; do
            [ -f "${esp_f}" ] || continue
            local esp_kver
            esp_kver=$(basename "${esp_f}" | sed 's/^vmlinuz-//')
            if [ ! -f "/boot/vmlinuz-${esp_kver}" ]; then
                log_info "Pruning obsolete kernel from ESP: $(basename "${esp_f}")"
                sudo rm -f "${esp_f}" "${esp_path}/initramfs-${esp_kver}.img"* "${esp_path}/initrd-${esp_kver}.gz"* 2>/dev/null || true
            fi
        done
    fi

    for kver in "${kernels[@]}"; do
        local vmlinuz_src=""
        local initrd_src=""

        # Locate vmlinuz
        if [ -f "/boot/vmlinuz-${kver}" ]; then
            vmlinuz_src="/boot/vmlinuz-${kver}"
            # Mirror to ESP if /boot and ESP are separate
            if [ "${esp_path}" != "/boot" ]; then
                sudo cp -f "${vmlinuz_src}" "${esp_path}/vmlinuz-${kver}"
                vmlinuz_src="${esp_path}/vmlinuz-${kver}"
            fi
        elif [ -f "${esp_path}/vmlinuz-${kver}" ]; then
            vmlinuz_src="${esp_path}/vmlinuz-${kver}"
        fi

        # Locate initramfs
        for cand_initrd in "/boot/initramfs-${kver}.img" "/boot/initrd-${kver}.gz" "${esp_path}/initramfs-${kver}.img" "${esp_path}/initrd-${kver}.gz"; do
            if [ -f "${cand_initrd}" ]; then
                initrd_src="${cand_initrd}"
                if [ "${esp_path}" != "/boot" ] && [[ "${initrd_src}" == /boot/* ]]; then
                    local base_initrd
                    base_initrd=$(basename "${initrd_src}")
                    sudo cp -f "${initrd_src}" "${esp_path}/${base_initrd}"
                    initrd_src="${esp_path}/${base_initrd}"
                fi
                break
            fi
        done

        [ -f "${vmlinuz_src}" ] && [ -f "${initrd_src}" ] || continue

        local vmlinuz_name
        vmlinuz_name=$(basename "${vmlinuz_src}")
        local initrd_name
        initrd_name=$(basename "${initrd_src}")

        # Calculate BLAKE2B hashes
        local k_hash i_hash
        k_hash=$(b2sum "${vmlinuz_src}" 2>/dev/null | awk '{print $1}' || echo "")
        i_hash=$(b2sum "${initrd_src}" 2>/dev/null | awk '{print $1}' || echo "")

        local k_entry_path="boot():/${vmlinuz_name}#${k_hash}"
        local i_entry_path="boot():/${initrd_name}#${i_hash}"

        local display_name="${kver}"
        if [[ "${kver}" =~ cachyos-bore-lto ]]; then
            display_name="CachyOS Linux (BORE + LTO)"
        elif [[ "${kver}" =~ cachyos-bore ]]; then
            display_name="CachyOS Linux (BORE)"
        elif [[ "${kver}" =~ cachyos-lts ]]; then
            display_name="CachyOS Linux (LTS)"
        elif [[ "${kver}" =~ cachyos-rc ]]; then
            display_name="CachyOS Linux (RC)"
        elif [[ "${kver}" =~ cachyos ]]; then
            display_name="CachyOS Linux (Standard)"
        elif [[ "${kver}" =~ generic ]]; then
            display_name="Slackware Linux (Generic)"
        fi

        kernel_entries+="\n    //${display_name} (${kver})\n"
        kernel_entries+="        protocol: linux\n"
        kernel_entries+="        kernel_path: ${k_entry_path}\n"
        kernel_entries+="        module_path: ${i_entry_path}\n"
        kernel_entries+="        cmdline: ${standard_cmdline}\n"

        kernel_entries+="\n    //${display_name} (Recovery Mode)\n"
        kernel_entries+="        protocol: linux\n"
        kernel_entries+="        kernel_path: ${k_entry_path}\n"
        kernel_entries+="        module_path: ${i_entry_path}\n"
        kernel_entries+="        cmdline: ${fallback_cmdline}\n"
    done

    # Foreign & Fallback Bootloaders (Windows, GRUB)
    local foreign_entries=""
    if [ -f "${esp_path}/EFI/Microsoft/Boot/bootmgfw.efi" ]; then
        foreign_entries+="\n/Windows Boot Manager\n"
        foreign_entries+="    protocol: efi_chainload\n"
        foreign_entries+="    image_path: boot():/EFI/Microsoft/Boot/bootmgfw.efi\n"
    fi

    if [ -f "${esp_path}/EFI/Slackware/grubx64.efi" ]; then
        foreign_entries+="\n/GRUB Bootloader (Fallback)\n"
        foreign_entries+="    protocol: efi_chainload\n"
        foreign_entries+="    image_path: boot():/EFI/Slackware/grubx64.efi\n"
    elif [ -f "${esp_path}/EFI/Slackware/shimx64.efi" ]; then
        foreign_entries+="\n/GRUB Bootloader (Secure Boot Shim)\n"
        foreign_entries+="    protocol: efi_chainload\n"
        foreign_entries+="    image_path: boot():/EFI/Slackware/shimx64.efi\n"
    fi

    local limine_cfg_file="${esp_path}/limine.conf"
    local limine_cfg_tmp
    limine_cfg_tmp=$(mktemp /tmp/slacky-limine-cfg.XXXXXX)

    cat << LIMINE_HEADER_EOF > "${limine_cfg_tmp}"
# /boot/limine.conf - Generated by Slacky-Update (Unified Limine Engine)
timeout: 5
default_entry: 1
hash_mismatch_panic: yes
$(echo -e "${splash_line}")
/Slackware Linux
    comment: machine-id=${machine_id}
$(echo -e "${kernel_entries}")
$(echo -e "${foreign_entries}")
LIMINE_HEADER_EOF

    sudo mv -f "${limine_cfg_tmp}" "${limine_cfg_file}"
    sudo chmod 644 "${limine_cfg_file}"

    # Also keep a mirror at /boot/limine.conf if /boot != esp_path
    if [ "${esp_path}" != "/boot" ] && [ -d "/boot" ]; then
        sudo cp -f "${limine_cfg_file}" "/boot/limine.conf"
    fi

    log_success "Limine configuration generated with BLAKE2B hashes at ${limine_cfg_file}."
    return 0
}

# --- [ CONFIG ENROLLMENT & SBCTL SIGNING ] ---
enroll_and_sign_limine() {
    validate_privileges

    local esp_path
    esp_path=$(detect_limine_esp_path)
    local target_efi="${esp_path}/EFI/limine/limine_x64.efi"
    local cfg_file="${esp_path}/limine.conf"

    if [ ! -f "${target_efi}" ]; then
        log_error "Limine EFI executable not found at ${target_efi}."
        return 1
    fi
    if [ ! -f "${cfg_file}" ]; then
        log_error "Limine configuration not found at ${cfg_file}."
        return 1
    fi

    local limine_cli
    limine_cli=$(command -v limine 2>/dev/null || echo "/usr/bin/limine")
    if [ -x "${limine_cli}" ]; then
        log_info "Calculating BLAKE2B hash of limine.conf and enrolling into EFI binary..."
        local cfg_hash
        cfg_hash=$(b2sum "${cfg_file}" 2>/dev/null | awk '{print $1}')
        if [ -n "${cfg_hash}" ]; then
            if sudo "${limine_cli}" enroll-config "${target_efi}" "${cfg_hash}" 2>/dev/null; then
                log_success "Enrolled config hash (${cfg_hash:0:16}...) into ${target_efi}."
            else
                log_warn "Notice: limine enroll-config returned non-zero (or already enrolled)."
            fi
        fi
    fi

    # Sign Limine EFI binary with sbctl if active
    local sbctl_bin
    sbctl_bin=$(command -v sbctl 2>/dev/null || echo "/usr/bin/sbctl")
    if [ -x "${sbctl_bin}" ]; then
        if "${sbctl_bin}" status 2>/dev/null | grep -qi "Installed:.*✓\|installed.*true"; then
            log_info "Signing Limine EFI binary with sbctl..."
            sudo "${sbctl_bin}" sign -s "${target_efi}" 2>/dev/null || true
            if [ -f "${esp_path}/EFI/BOOT/BOOTX64.EFI" ]; then
                sudo "${sbctl_bin}" sign -s "${esp_path}/EFI/BOOT/BOOTX64.EFI" 2>/dev/null || true
            fi
            log_success "Limine EFI binaries cryptographically signed."
        fi
    fi

    # Silent sync to disk to prevent FAT32 corruption
    sync -f "${target_efi}" 2>/dev/null || sync 2>/dev/null || true
    backup_limine_self_heal
    return 0
}

# --- [ LIMINE SELF-HEAL BACKUP & RESTORE ] ---
backup_limine_self_heal() {
    local esp_path
    esp_path=$(detect_limine_esp_path)
    [ -d "${esp_path}/EFI/limine" ] || return 0

    local current_user="${SUDO_USER:-${USER:-}}"
    local user_backup_dir="/home/${current_user}/.limine_backup"
    local system_backup_dir="/var/cache/slacky-update/limine_backup"

    if [ -n "${current_user}" ] && [ -d "/home/${current_user}" ]; then
        mkdir -p "${user_backup_dir}" 2>/dev/null || true
        rsync -a --delete "${esp_path}/EFI/limine/" "${user_backup_dir}/" 2>/dev/null || true
        [ -f "${esp_path}/limine.conf" ] && cp -f "${esp_path}/limine.conf" "${user_backup_dir}/" 2>/dev/null || true
    fi

    validate_privileges
    sudo mkdir -p "${system_backup_dir}" 2>/dev/null || true
    sudo rsync -a --delete "${esp_path}/EFI/limine/" "${system_backup_dir}/" 2>/dev/null || true
    [ -f "${esp_path}/limine.conf" ] && sudo cp -f "${esp_path}/limine.conf" "${system_backup_dir}/" 2>/dev/null || true
}

restore_limine_self_heal() {
    validate_privileges
    local esp_path
    esp_path=$(detect_limine_esp_path)
    local current_user="${SUDO_USER:-${USER:-}}"
    local user_backup_dir="/home/${current_user}/.limine_backup"
    local system_backup_dir="/var/cache/slacky-update/limine_backup"

    local src_dir=""
    if [ -d "${system_backup_dir}" ] && [ -f "${system_backup_dir}/limine_x64.efi" ]; then
        src_dir="${system_backup_dir}"
    elif [ -n "${current_user}" ] && [ -d "${user_backup_dir}" ] && [ -f "${user_backup_dir}/limine_x64.efi" ]; then
        src_dir="${user_backup_dir}"
    fi

    if [ -z "${src_dir}" ]; then
        log_error "No valid Limine Self-Heal backup found."
        return 1
    fi

    log_info "Restoring known-good Limine configuration from ${src_dir}..."
    sudo mkdir -p "${esp_path}/EFI/limine"
    sudo cp -af "${src_dir}/"* "${esp_path}/EFI/limine/" 2>/dev/null || true
    if [ -f "${src_dir}/limine.conf" ]; then
        sudo cp -af "${src_dir}/limine.conf" "${esp_path}/limine.conf"
    fi
    sync -f "${esp_path}/EFI/limine/limine_x64.efi" 2>/dev/null || sync 2>/dev/null || true
    log_success "Limine bootloader and configuration successfully restored from Self-Heal backup."
}

# --- [ INSTALL LIMINE BOOTLOADER (ZERO DESTRUCTION) ] ---
install_limine_bootloader() {
    validate_privileges

    local esp_path
    esp_path=$(detect_limine_esp_path)

    log_info "Running pre-flight check on boot partition (${esp_path})..."
    if ! check_boot_partition_eligibility "${esp_path}"; then
        return 1
    fi

    install_unified_limine_suite || return 1

    local target_limine_dir="${esp_path}/EFI/limine"
    sudo mkdir -p "${target_limine_dir}"

    local limine_efi_src=""
    for cand in "/usr/share/limine/BOOTX64.EFI" "/usr/lib/limine/BOOTX64.EFI" "/usr/share/limine/limine_x64.efi"; do
        if [ -f "${cand}" ]; then
            limine_efi_src="${cand}"
            break
        fi
    done

    if [ -z "${limine_efi_src}" ]; then
        log_error "Limine EFI binary (BOOTX64.EFI) not found in system."
        return 1
    fi

    log_info "Deploying Limine EFI binary (${limine_efi_src}) -> ${target_limine_dir}/limine_x64.efi..."
    sudo cp -f "${limine_efi_src}" "${target_limine_dir}/limine_x64.efi"
    sudo cp -f "${limine_efi_src}" "${target_limine_dir}/limine_x64.bak"

    # Register UEFI NVRAM boot entry with efibootmgr (Zero-Destruction: GRUB is never deleted)
    local efibootmgr_bin
    efibootmgr_bin=$(command -v efibootmgr 2>/dev/null || echo "/usr/sbin/efibootmgr")
    if [ -x "${efibootmgr_bin}" ]; then
        local esp_source
        esp_source=$(findmnt -n -o SOURCE "${esp_path}" 2>/dev/null || true)
        if [ -n "${esp_source}" ]; then
            local esp_disk="" esp_part=""
            if [[ "${esp_source}" =~ (/dev/nvme[0-9]+n[0-9]+)p([0-9]+) ]]; then
                esp_disk="${BASH_REMATCH[1]}"
                esp_part="${BASH_REMATCH[2]}"
            elif [[ "${esp_source}" =~ (/dev/[a-z]+)([0-9]+) ]]; then
                esp_disk="${BASH_REMATCH[1]}"
                esp_part="${BASH_REMATCH[2]}"
            fi

            if [ -n "${esp_disk}" ] && [ -n "${esp_part}" ]; then
                log_info "Registering UEFI NVRAM Boot Entry: Limine Bootloader on ${esp_disk} p${esp_part}..."
                # Check if already present to avoid duplicate entries
                if ! sudo "${efibootmgr_bin}" 2>/dev/null | grep -qi "Limine Bootloader"; then
                    sudo "${efibootmgr_bin}" -c -d "${esp_disk}" -p "${esp_part}" -L "Limine Bootloader" -l "\\EFI\\limine\\limine_x64.efi" >/dev/null 2>&1 || true
                fi
            fi
        fi
    fi

    generate_limine_configuration
    enroll_and_sign_limine

    log_success "Limine Bootloader installed successfully in coexistence mode!"
    echo -e "${CYAN}Note: GRUB and ELILO remain 100% active in UEFI NVRAM and can be chosen anytime via BIOS Boot Menu (F11/F12).${RESET}"
    return 0
}

# --- [ INTERACTIVE LIMINE MANAGEMENT MENU ] ---
manage_limine_interactive() {
    validate_privileges

    while true; do
        local esp_path
        esp_path=$(detect_limine_esp_path)
        local lim_status="[NOT INSTALLED]"
        if [ "$(is_limine_installed)" = "true" ]; then
            lim_status="${GREEN}[INSTALLED & ACTIVE]${RESET}"
        fi

        echo ""
        echo -e "${CYAN}============================================================${RESET}"
        echo -e "${YELLOW}${BOLD}⚡ LIMINE BOOTLOADER & SECURE BOOT MATRIX ⚡${RESET}"
        echo -e "${CYAN}============================================================${RESET}"
        echo -e "  • ${BOLD}Status:${RESET}      ${lim_status}"
        echo -e "  • ${BOLD}ESP Path:${RESET}    ${esp_path}"
        echo ""
        echo -e "  \033[1;33m1.\033[0m Install / Re-deploy Limine Bootloader (Coexistence Mode)"
        echo -e "  \033[1;33m2.\033[0m Regenerate limine.conf & Re-enroll BLAKE2B Checksums"
        echo -e "  \033[1;33m3.\033[0m Synchronize Btrfs Snapper Snapshots into Limine Menu"
        echo -e "  \033[1;33m4.\033[0m 1-Click Self-Heal: Restore Limine from Backup"
        echo -e "  \033[1;33m5.\033[0m Return to Main Menu"
        echo ""
        echo -n "Select operation [1-5]: "
        local lim_choice
        read -r lim_choice || lim_choice="5"

        case "${lim_choice}" in
            1)
                echo ""
                install_limine_bootloader
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            2)
                echo ""
                generate_limine_configuration
                enroll_and_sign_limine
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            3)
                echo ""
                if command -v limine-snapper-sync >/dev/null 2>&1; then
                    log_info "Synchronizing Btrfs Snapper snapshots into Limine..."
                    sudo limine-snapper-sync || true
                    enroll_and_sign_limine
                    log_success "Snapper snapshots synchronized."
                else
                    log_warn "limine-snapper-sync utility not found. Install Unified Limine Suite first."
                fi
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            4)
                echo ""
                restore_limine_self_heal
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            5)
                return 0
                ;;
            *)
                echo -e "\n${YELLOW}$(_ INVALID_SELECTION)${RESET}"
                sleep 1
                ;;
        esac
    done
}
