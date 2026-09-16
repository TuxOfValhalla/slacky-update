#!/usr/bin/env bash
# --- [ LIMINE BOOTLOADER & UEFI SECURE BOOT ENGINE ] ---
# Slacky-Update Unified Limine Suite: limine (>=12.x), limine-entry-tool, limine-snapper-sync, sbctl

set -euo pipefail

# --- [ CONSTANTS & ENDPOINTS ] ---
CACHYOS_REPO_BASE="https://mirror.cachyos.org/repo/x86_64/cachyos"
ARCH_EXTRA_REPO_BASE="https://geo.mirror.pkgbuild.com/extra/os/x86_64"

MIN_BOOT_PARTITION_MB=3500

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

    if sudo test -f "${esp_path}/EFI/limine/limine_x64.efi" || \
       sudo test -f "${esp_path}/EFI/limine/BOOTX64.EFI" || \
       sudo test -f "${esp_path}/limine.conf" || \
       sudo test -f "/boot/limine.conf" || \
       [ -f "/etc/default/limine" ]; then
        echo "true"
        return 0
    fi

    echo "false"
    return 1
}

# --- [ ENSURE CLEAN MKINITRD STAGING FOR FAT32 /BOOT ] ---
ensure_mkinitrd_staging_configured() {
    local mkconf="/etc/mkinitrd.conf"

    if [ ! -f "${mkconf}" ]; then
        log_info "Configuring ${mkconf} with SOURCE_TREE=\"/tmp/initrd-tree\" for FAT32 /boot..."
        echo '# Use /tmp for staging to support FAT32/ESP /boot staging' | sudo tee "${mkconf}" >/dev/null
        echo 'SOURCE_TREE="/tmp/initrd-tree"' | sudo tee -a "${mkconf}" >/dev/null
        return 0
    fi

    # Check if SOURCE_TREE is already pointing to /tmp
    if grep -q "^[[:space:]]*SOURCE_TREE=" "${mkconf}" 2>/dev/null; then
        local curr_tree
        curr_tree=$(grep "^[[:space:]]*SOURCE_TREE=" "${mkconf}" | tail -n 1 | cut -d'=' -f2 | tr -d '"'\'' ' || true)
        if [[ ! "${curr_tree}" =~ ^/tmp ]]; then
            log_info "Updating ${mkconf}: changing staging directory from '${curr_tree}' to '/tmp/initrd-tree'..."
            sudo sed -i 's|^[[:space:]]*SOURCE_TREE=.*|SOURCE_TREE="/tmp/initrd-tree"|' "${mkconf}"
        fi
    else
        log_info "Adding SOURCE_TREE=\"/tmp/initrd-tree\" to ${mkconf} for FAT32 /boot support..."
        echo -e "\n# Use /tmp for staging to support FAT32/ESP /boot staging\nSOURCE_TREE=\"/tmp/initrd-tree\"" | sudo tee -a "${mkconf}" >/dev/null
    fi
}

# --- [ RESOLVE PARTITION CAPACITY (MB) ] ---
get_path_size_mb() {
    local target="${1:-}"
    local total_mb=0

    if [ -b "${target}" ]; then
        local bytes
        bytes=$(lsblk -b -n -d -o SIZE "${target}" 2>/dev/null || true)
        if [ -n "${bytes}" ] && [ "${bytes}" -gt 0 ] 2>/dev/null; then
            echo $(( bytes / 1024 / 1024 ))
            return 0
        fi
    fi

    if [ -d "${target}" ]; then
        local size_bytes
        size_bytes=$(findmnt -b -n -o SIZE "${target}" 2>/dev/null || true)
        if [ -n "${size_bytes}" ] && [ "${size_bytes}" -gt 0 ] 2>/dev/null; then
            total_mb=$(( size_bytes / 1024 / 1024 ))
        else
            local size_kb
            size_kb=$(df -k "${target}" 2>/dev/null | awk 'NR==2 {print $2}')
            if [ -n "${size_kb}" ] && [ "${size_kb}" -gt 0 ] 2>/dev/null; then
                total_mb=$(( size_kb / 1024 ))
            fi
        fi
        echo "${total_mb}"
        return 0
    fi

    echo "0"
}

# --- [ SCAN ESP PARTITION CANDIDATES ] ---
list_esp_partition_candidates() {
    local min_bytes=$(( MIN_BOOT_PARTITION_MB * 1024 * 1024 ))
    local output=()

    while IFS= read -r line; do
        [ -z "${line}" ] && continue
        local NAME="" SIZE="" FSTYPE="" TYPE="" MOUNTPOINT=""
        eval "${line}"

        [ "${TYPE}" != "part" ] && continue
        [ "${SIZE:-0}" -lt "${min_bytes}" ] 2>/dev/null && continue

        # Filter out system critical mounts
        if [ "${MOUNTPOINT}" = "/" ] || [ "${MOUNTPOINT}" = "/home" ] || [ "${MOUNTPOINT}" = "/var" ] || [ "${MOUNTPOINT}" = "/usr" ] || [ "${MOUNTPOINT}" = "[SWAP]" ]; then
            continue
        fi

        local dev_path="/dev/${NAME}"
        local size_mb=$(( SIZE / 1024 / 1024 ))
        output+=("${dev_path}|${size_mb}|${FSTYPE:-unformatted}|${MOUNTPOINT:-unmounted}")
    done < <(lsblk -b -P -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT 2>/dev/null || true)

    printf '%s\n' "${output[@]}"
}

# --- [ PROVISION GPT TYPE & FAT32 FILESYSTEM ] ---
provision_esp_partition_type_and_fs() {
    local target_dev="$1"
    validate_privileges

    # 1. Determine disk and partition number
    local parent_disk="" part_num=""
    if [[ "${target_dev}" =~ (/dev/nvme[0-9]+n[0-9]+)p([0-9]+) ]]; then
        parent_disk="${BASH_REMATCH[1]}"
        part_num="${BASH_REMATCH[2]}"
    elif [[ "${target_dev}" =~ (/dev/[a-z]+)([0-9]+) ]]; then
        parent_disk="${BASH_REMATCH[1]}"
        part_num="${BASH_REMATCH[2]}"
    fi

    if [ -n "${parent_disk}" ] && [ -n "${part_num}" ]; then
        log_info "Setting GPT partition type to EFI System Partition (ef00) on ${target_dev}..."
        if command -v sgdisk >/dev/null 2>&1; then
            sudo sgdisk -t "${part_num}:ef00" "${parent_disk}" >/dev/null 2>&1 || true
        elif command -v parted >/dev/null 2>&1; then
            sudo parted -s "${parent_disk}" set "${part_num}" esp on >/dev/null 2>&1 || true
        fi
    fi

    # 2. Check if already FAT32 or needs formatting
    local cur_fs
    cur_fs=$(blkid -s TYPE -o value "${target_dev}" 2>/dev/null || true)
    if [ "${cur_fs}" != "vfat" ]; then
        log_info "Formatting ${target_dev} as FAT32 (ESP_BOOT)..."
        sudo mkfs.vfat -F32 -n "ESP_BOOT" "${target_dev}" >/dev/null
    else
        log_info "${target_dev} is already formatted as FAT32 (vfat)."
    fi
}

# --- [ SCENARIO A: IN-PLACE ESP UPGRADE (/boot/efi -> /boot) ] ---
migrate_existing_esp_to_boot() {
    validate_privileges
    log_info "Initiating Scenario A: Migrating /boot/efi mount point to /boot..."

    local esp_dev esp_uuid
    esp_dev=$(findmnt -n -o SOURCE /boot/efi 2>/dev/null || true)
    esp_uuid=$(findmnt -n -o UUID /boot/efi 2>/dev/null || blkid -s UUID -o value "${esp_dev}" 2>/dev/null || true)

    if [ -z "${esp_dev}" ]; then
        log_error "Could not resolve active device for /boot/efi."
        return 1
    fi

    # Ensure GPT type ef00 (ESP) and bootable flags are 100% active
    provision_esp_partition_type_and_fs "${esp_dev}"

    local ts
    ts=$(date +%Y%m%d_%H%M%S)
    sudo cp -f /etc/fstab "/etc/fstab.bak.${ts}"
    log_info "Created backup: /etc/fstab.bak.${ts}"

    log_info "Copying system boot files (/boot/*) to ESP..."
    sudo find /boot -maxdepth 1 ! -name 'efi' ! -name 'EFI' ! -path '/boot' -exec cp -a {} /boot/efi/ \; 2>/dev/null || true

    log_info "Updating /etc/fstab mountpoint from /boot/efi to /boot..."
    sudo sed -i -E "s|([[:space:]]+)/boot/efi([[:space:]]+vfat)|\1/boot\2|g" /etc/fstab

    ensure_mkinitrd_staging_configured

    log_info "Remounting ESP partition directly on /boot..."
    sudo umount /boot/efi 2>/dev/null || true
    sudo mount /boot 2>/dev/null || sudo mount -t vfat -o defaults,noatime,umask=0077 "${esp_dev}" /boot

    if [ "$(findmnt -n -o FSTYPE /boot 2>/dev/null)" = "vfat" ]; then
        log_success "Scenario A complete: /boot is now actively mounted on ESP (${esp_dev})."
        return 0
    else
        log_error "Failed to verify FAT32 mount at /boot after migration!"
        return 1
    fi
}

# --- [ SCENARIO C: NEW DEDICATED ESP PARTITION ADOPTION ] ---
migrate_to_new_esp_partition() {
    local target_dev="$1"
    validate_privileges
    log_info "Initiating Scenario C: Migrating boot files to new dedicated ESP on ${target_dev}..."

    provision_esp_partition_type_and_fs "${target_dev}"

    local new_uuid
    new_uuid=$(blkid -s UUID -o value "${target_dev}" 2>/dev/null || true)
    if [ -z "${new_uuid}" ]; then
        log_error "Failed to determine UUID for ${target_dev}."
        return 1
    fi

    local tmp_mnt="/mnt/slacky_new_boot_$$"
    sudo mkdir -p "${tmp_mnt}"
    sudo mount -t vfat "${target_dev}" "${tmp_mnt}"

    log_info "Copying kernels, initrds and configs from /boot to new ESP..."
    if [ -d "/boot" ]; then
        sudo find /boot -maxdepth 1 ! -name 'efi' ! -name 'EFI' ! -path '/boot' -exec cp -a {} "${tmp_mnt}/" \; 2>/dev/null || true
    fi

    for efi_cand in /boot/efi/EFI /boot/EFI; do
        if [ -d "${efi_cand}" ]; then
            log_info "Preserving multiboot: Copying existing EFI entries from ${efi_cand} -> ${tmp_mnt}/EFI..."
            sudo mkdir -p "${tmp_mnt}/EFI"
            sudo cp -a "${efi_cand}"/* "${tmp_mnt}/EFI/" 2>/dev/null || true
        fi
    done

    local ts
    ts=$(date +%Y%m%d_%H%M%S)
    sudo cp -f /etc/fstab "/etc/fstab.bak.${ts}"
    log_info "Created backup: /etc/fstab.bak.${ts}"

    sudo sed -i -E "s|^([^#].*[[:space:]]+/boot/efi[[:space:]]+vfat.*)|# [MIGRATED TO DEDICATED /boot BY SLACKY-UPDATE] \1|g" /etc/fstab
    sudo sed -i -E "s|^([^#].*[[:space:]]+/boot[[:space:]]+.*)|# [REPLACED BY SLACKY-UPDATE ESP] \1|g" /etc/fstab

    echo -e "\n# Dedicated ESP for Limine Bootloader & Secure Boot\nUUID=${new_uuid}                             /boot        vfat   defaults,noatime,umask=0077                              0  2" | sudo tee -a /etc/fstab >/dev/null

    ensure_mkinitrd_staging_configured

    sudo umount "${tmp_mnt}" 2>/dev/null || true
    sudo rmdir "${tmp_mnt}" 2>/dev/null || true
    sudo umount /boot/efi 2>/dev/null || true

    log_info "Mounting new ESP at /boot..."
    sudo mount /boot 2>/dev/null || sudo mount -t vfat -o defaults,noatime,umask=0077 "${target_dev}" /boot

    if [ "$(findmnt -n -o FSTYPE /boot 2>/dev/null)" = "vfat" ]; then
        log_success "Scenario C complete: Dedicated ESP (${target_dev}, UUID=${new_uuid}) is now mounted at /boot."
        return 0
    else
        log_error "Failed to verify FAT32 mount at /boot after Scenario C migration!"
        return 1
    fi
}

# --- [ TOPOLOGY GUARD & MIGRATION WIZARD ] ---
validate_or_migrate_boot_topology() {
    validate_privileges

    # Check 1: Is /boot already mounted as FAT32 (vfat)?
    local boot_fs
    boot_fs=$(findmnt -n -o FSTYPE /boot 2>/dev/null || true)

    if [ "${boot_fs}" = "vfat" ]; then
        local boot_size_mb
        boot_size_mb=$(get_path_size_mb "/boot")
        if [ "${boot_size_mb}" -ge "${MIN_BOOT_PARTITION_MB}" ]; then
            # SCENARIO B: Already Best Practice compliant
            ensure_mkinitrd_staging_configured
            log_success "Best Practice Boot Topology confirmed: /boot is FAT32 (${boot_size_mb} MB >= ${MIN_BOOT_PARTITION_MB} MB)."
            return 0
        else
            log_warn "Current /boot is FAT32, but size is insufficient (${boot_size_mb} MB < ${MIN_BOOT_PARTITION_MB} MB)."
        fi
    fi

    # Check 2: Is /boot/efi mounted as FAT32 (vfat)?
    local efi_fs
    efi_fs=$(findmnt -n -o FSTYPE /boot/efi 2>/dev/null || true)
    if [ "${efi_fs}" = "vfat" ]; then
        local efi_size_mb
        efi_size_mb=$(get_path_size_mb "/boot/efi")
        if [ "${efi_size_mb}" -ge "${MIN_BOOT_PARTITION_MB}" ]; then
            # SCENARIO A: Existing /boot/efi is large enough (>= 3.5 GB)
            echo ""
            echo -e "${CYAN}============================================================${RESET}"
            echo -e "${YELLOW}${BOLD}⚡ LIMINE BOOT TOPOLOGY MIGRATION (SCENARIO A) ⚡${RESET}"
            echo -e "${CYAN}============================================================${RESET}"
            echo -e "  • ${BOLD}Current State:${RESET} /boot is on system root (${boot_fs:-posix}), and /boot/efi is ${efi_size_mb} MB FAT32."
            echo -e "  • ${BOLD}Recommendation:${RESET} Migrate /boot/efi directly to /boot for optimal Limine & Snapper sync."
            echo ""
            echo -n "Proceed with automated /boot migration? [Y/n]: "
            local ans
            read -r ans || ans="y"
            if [[ ! "${ans}" =~ ^[Nn] ]]; then
                migrate_existing_esp_to_boot || return 1
                return 0
            else
                log_warn "Migration declined by user. Limine deployment cancelled."
                return 1
            fi
        fi
    fi

    # SCENARIO C: ESP is missing or too small (< 3.5 GB). Offer partition adoption wizard.
    echo ""
    echo -e "${CYAN}============================================================${RESET}"
    echo -e "${YELLOW}${BOLD}⚡ LIMINE DEDICATED ESP ADOPTION WIZARD (SCENARIO C) ⚡${RESET}"
    echo -e "${CYAN}============================================================${RESET}"
    echo -e "${YELLOW}Limine multi-kernel staging with Snapper boot sync requires a dedicated FAT32 ESP of at least ${MIN_BOOT_PARTITION_MB} MB (4 GB) on /boot.${RESET}"
    echo -e "Your current ESP is either too small or /boot is on a non-FAT32 filesystem."
    echo ""
    echo -n "Would you like to scan and select a partition (>= 3.5 GB) to configure as /boot? [Y/n]: "
    local opt_ans
    read -r opt_ans || opt_ans="y"
    if [[ "${opt_ans}" =~ ^[Nn] ]]; then
        log_warn "Limine setup cancelled. Existing bootloader (GRUB/ELILO) remains completely untouched."
        return 1
    fi

    local raw_cands=()
    mapfile -t raw_cands < <(list_esp_partition_candidates)
    if [ ${#raw_cands[@]} -eq 0 ]; then
        echo ""
        log_error "No eligible partitions (>= ${MIN_BOOT_PARTITION_MB} MB) found outside active root/home/swap."
        echo -e "${CYAN}Tip: Use GParted or cfdisk to create or shrink a partition to at least 4 GB, then re-run this tool.${RESET}"
        return 1
    fi

    echo ""
    echo -e "${BOLD}Available Candidate Partitions:${RESET}"
    local idx=1
    local cand_devs=()
    for c in "${raw_cands[@]}"; do
        IFS='|' read -r c_dev c_size c_fs c_mp <<< "${c}"
        cand_devs+=("${c_dev}")
        echo -e "  \033[1;33m${idx}.\033[0m ${c_dev} - ${c_size} MB (${c_fs}, ${c_mp})"
        ((idx++))
    done
    echo -e "  \033[1;33m${idx}.\033[0m Cancel / Abort"
    echo ""
    echo -n "Select partition to configure as /boot [1-${idx}]: "
    local p_choice
    read -r p_choice || p_choice="${idx}"

    if [[ "${p_choice}" =~ ^[0-9]+$ ]] && [ "${p_choice}" -ge 1 ] && [ "${p_choice}" -lt "${idx}" ]; then
        local chosen_dev="${cand_devs[$((p_choice - 1))]}"
        echo ""
        echo -e "${RED}${BOLD}WARNING: You selected ${chosen_dev}.${RESET}"
        echo -e "If this partition contains data, ensure you have backups or that it was created specifically for boot."
        echo -n "Are you SURE you want to configure ${chosen_dev} as /boot? [y/N]: "
        local confirm
        read -r confirm || confirm="n"
        if [[ "${confirm}" =~ ^[Yy] ]]; then
            migrate_to_new_esp_partition "${chosen_dev}" || return 1
            return 0
        else
            log_warn "Operation cancelled by user."
            return 1
        fi
    else
        log_warn "No partition selected. Limine setup cancelled."
        return 1
    fi
}

check_boot_partition_eligibility() {
    validate_or_migrate_boot_topology
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
        if command -v transmute_and_deploy_gaming_pkg >/dev/null 2>&1; then
            transmute_and_deploy_gaming_pkg "${pkg_id}"
        fi
    done

    # Ensure /usr/lib/limine symlink exists for Slackware 64-bit compatibility
    if [ -d "/usr/lib64/limine" ] && [ ! -d "/usr/lib/limine" ] && [ ! -L "/usr/lib/limine" ]; then
        sudo ln -sf /usr/lib64/limine /usr/lib/limine 2>/dev/null || true
    fi

    # Ensure /etc/boot/hooks directories exist for Limine standalone CLI hooks
    sudo mkdir -p /etc/boot/hooks/pre.d /etc/boot/hooks/post.d
    if [ -x "/usr/bin/limine-reset-enroll" ] && [ ! -e "/etc/boot/hooks/pre.d/10-limine-reset-enroll" ]; then
        sudo ln -sf /usr/bin/limine-reset-enroll /etc/boot/hooks/pre.d/10-limine-reset-enroll 2>/dev/null || true
    fi
    cat << 'HOOK_EOF' | sudo tee /etc/boot/hooks/post.d/90-limine-enroll-config >/dev/null
#!/bin/sh
# Hardened Slacky-Update Limine Post-Config Hook: Enroll BLAKE2B hashes and re-sign with sbctl
if [ -x /usr/bin/limine-enroll-config ]; then
    /usr/bin/limine-enroll-config "$@"
fi
if command -v sbctl >/dev/null 2>&1; then
    for cand in /boot/efi/EFI/limine/limine_x64.efi /boot/EFI/limine/limine_x64.efi /efi/EFI/limine/limine_x64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI /boot/EFI/BOOT/BOOTX64.EFI /boot/efi/EFI/Slackware/grubx64.efi /boot/EFI/Slackware/grubx64.efi /boot/efi/EFI/Slackware/shimx64.efi /boot/EFI/Slackware/shimx64.efi; do
        if [ -f "$cand" ]; then
            sbctl sign -s "$cand" >/dev/null 2>&1 || true
        fi
    done
    for kern in /boot/vmlinuz-*; do
        if [ -f "$kern" ] && [ ! -L "$kern" ]; then
            sbctl sign -s "$kern" >/dev/null 2>&1 || true
        fi
    done
fi
HOOK_EOF
    sudo chmod 755 /etc/boot/hooks/post.d/90-limine-enroll-config 2>/dev/null || true

    # Ensure /etc/default/limine exists with clean defaults
    if [ ! -f "/etc/default/limine" ]; then
        sudo mkdir -p /etc/default
        cat << LIMINE_DEFAULT_EOF | sudo tee /etc/default/limine >/dev/null
# /etc/default/limine - Slacky-Update Limine Configuration
ESP_PATH="${esp_path}"
TARGET_OS_NAME="Slackware Linux"
ENABLE_VERIFICATION=yes
ENABLE_ENROLL_LIMINE_CONFIG=yes
FIND_BOOTLOADERS=yes
BOOT_ORDER="*, *fallback, Snapshots"
CONFIG_BACKUP_THRESHOLD=6

# Automatic Background Btrfs Snapper Boot Sync (Opt-In: default disabled)
ENABLE_AUTO_SNAPPER_SYNC=no
SNAPPER_BOOT_POLICY=daily_spread
SNAPPER_BOOT_DEPTH=5
LIMINE_DEFAULT_EOF
        sudo chmod 644 /etc/default/limine
    fi

    sync_host_kernel_cmdline_config "${esp_path}"

    log_success "Unified Limine Suite deployed successfully."
    return 0
}

# --- [ HELPER: DETECT ZRAM STATUS ] ---
is_zram_active() {
    if grep -q "zram" /proc/swaps 2>/dev/null || [ -d "/sys/block/zram0" ] || lsmod 2>/dev/null | grep -q "^zram"; then
        return 0
    fi
    return 1
}

# --- [ HELPER: CPU-SPECIFIC IOMMU / VFIO PARAMETER ] ---
get_iommu_param_for_cpu() {
    if grep -qi "AuthenticAMD" /proc/cpuinfo 2>/dev/null; then
        echo "amd_iommu=on iommu=pt"
    else
        echo "intel_iommu=on iommu=pt"
    fi
}

# --- [ HELPER: SENSIBLE HARDWARE DEFAULTS ] ---
get_default_sensible_cmdline() {
    local defaults="quiet splash loglevel=3 rd.udev.log_priority=3"
    probe_gpu_hardware >/dev/null 2>&1 || true
    if [ "${HAS_NVIDIA}" = "true" ] || lspci 2>/dev/null | grep -Ei 'vga|3d' | grep -qi 'nvidia'; then
        defaults+=" nvidia_drm.modeset=1 nvidia_drm.fbdev=1 nvidia.NVreg_PreserveVideoMemoryAllocations=1"
    fi
    if [ "${HAS_AMD}" = "true" ] || lspci 2>/dev/null | grep -Ei 'vga|3d' | grep -qi 'amd|radeon|ati'; then
        defaults+=" amdgpu.ppfeaturemask=0xffffffff"
    fi
    echo "${defaults}"
}

get_host_kernel_cmdline() {
    local custom_args=""

    # 1. Check /etc/kernel/cmdline (Priority 1: Dedicated Linux/UKI standard file)
    if [ -f "/etc/kernel/cmdline" ]; then
        custom_args=$(cat /etc/kernel/cmdline 2>/dev/null || true)
    fi

    # 2. Check /etc/default/limine (Priority 2)
    if [ -z "$(echo "${custom_args}" | tr -d '[:space:]')" ] && [ -f "/etc/default/limine" ]; then
        custom_args=$(grep -E '^[[:space:]]*KERNEL_CMDLINE\[default\]=' /etc/default/limine 2>/dev/null | tail -n1 | cut -d'=' -f2- | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//" || true)
    fi

    # 3. Check /etc/default/grub (Priority 3)
    if [ -z "$(echo "${custom_args}" | tr -d '[:space:]')" ] && [ -f "/etc/default/grub" ]; then
        local g_def g_lin
        g_def=$(grep -E '^[[:space:]]*GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub 2>/dev/null | tail -n1 | cut -d'=' -f2- | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//" || true)
        g_lin=$(grep -E '^[[:space:]]*GRUB_CMDLINE_LINUX=' /etc/default/grub 2>/dev/null | tail -n1 | cut -d'=' -f2- | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//" || true)
        custom_args="${g_def} ${g_lin}"
    fi

    # 4. If still empty, extract non-transient parameters from /proc/cmdline
    if [ -z "$(echo "${custom_args}" | tr -d '[:space:]')" ] && [ -f "/proc/cmdline" ]; then
        local raw_proc
        raw_proc=$(cat /proc/cmdline 2>/dev/null || true)
        custom_args=$(echo "${raw_proc}" | tr ' ' '\n' | grep -v -E '^(BOOT_IMAGE=.*|initrd=.*|root=.*|rootflags=.*|ro|rw)$' | tr '\n' ' ' || true)
    fi

    # 5. If completely empty, generate sensible defaults based on hardware detection
    if [ -z "$(echo "${custom_args}" | tr -d '[:space:]')" ]; then
        custom_args=$(get_default_sensible_cmdline)
    fi

    # Strip duplicate root, rootflags, ro/rw, and bootloader transients
    local cleaned_args
    cleaned_args=$(echo "${custom_args}" | tr ' ' '\n' | grep -v -E '^(BOOT_IMAGE=.*|initrd=.*|root=.*|rootflags=.*|ro|rw)$' | tr '\n' ' ' || true)

    echo "${cleaned_args}" | tr -s ' ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# --- [ DYNAMIC MULTI-FILESYSTEM & KERNEL CMDLINE SYNCHRONIZER ] ---
sync_host_kernel_cmdline_config() {
    local esp_path="${1:-}"
    if [ -z "${esp_path}" ]; then
        esp_path=$(detect_limine_esp_path)
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

    local host_cmdline
    host_cmdline=$(get_host_kernel_cmdline)

    local standard_cmdline="${root_cmd}${root_extra} rw ${host_cmdline}"
    standard_cmdline=$(echo "${standard_cmdline}" | tr -s ' ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    local recovery_host_cmdline
    recovery_host_cmdline=$(echo "${host_cmdline}" | tr ' ' '\n' | grep -v -E '^(quiet|splash|loglevel=.*|rd\.udev\.log_priority=.*)$' | tr '\n' ' ' || true)
    local recovery_cmdline="${root_cmd}${root_extra} ro single ${recovery_host_cmdline}"
    recovery_cmdline=$(echo "${recovery_cmdline}" | tr -s ' ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    # 1. Sync to /etc/kernel/cmdline for universal Linux / UKI standard
    sudo mkdir -p /etc/kernel
    echo "${standard_cmdline}" | sudo tee /etc/kernel/cmdline >/dev/null
    sudo chmod 644 /etc/kernel/cmdline 2>/dev/null || true

    # 2. Sync to /etc/default/limine (KERNEL_CMDLINE[default] and KERNEL_CMDLINE[fallback])
    if [ -f "/etc/default/limine" ]; then
        sudo python3 -c "
import re

cfg_path = '/etc/default/limine'
with open(cfg_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Ensure KERNEL_CMDLINE[default] is present and updated
if 'KERNEL_CMDLINE[default]' in content:
    content = re.sub(r'^[#\s]*KERNEL_CMDLINE\[default\].*$', '''KERNEL_CMDLINE[default]=\"${standard_cmdline}\"''', content, flags=re.MULTILINE)
else:
    content += '''\nKERNEL_CMDLINE[default]=\"${standard_cmdline}\"\n'''

# Ensure KERNEL_CMDLINE[fallback] is present and updated
if 'KERNEL_CMDLINE[fallback]' in content:
    content = re.sub(r'^[#\s]*KERNEL_CMDLINE\[fallback\].*$', '''KERNEL_CMDLINE[fallback]=\"${recovery_cmdline}\"''', content, flags=re.MULTILINE)
else:
    content += '''KERNEL_CMDLINE[fallback]=\"${recovery_cmdline}\"\n'''

with open(cfg_path, 'w', encoding='utf-8') as f:
    f.write(content)
" 2>/dev/null || true
    fi

    # 3. Sync to /etc/default/grub (GRUB_CMDLINE_LINUX_DEFAULT) if file exists
    if [ -f "/etc/default/grub" ]; then
        sudo python3 -c "
import re

cfg_path = '/etc/default/grub'
with open(cfg_path, 'r', encoding='utf-8') as f:
    content = f.read()

if 'GRUB_CMDLINE_LINUX_DEFAULT' in content:
    content = re.sub(r'^[#\s]*GRUB_CMDLINE_LINUX_DEFAULT=.*$', '''GRUB_CMDLINE_LINUX_DEFAULT=\"${host_cmdline}\"''', content, flags=re.MULTILINE)
    with open(cfg_path, 'w', encoding='utf-8') as f:
        f.write(content)
" 2>/dev/null || true
    fi
}

# --- [ BOOT ASSET HASHING & RESOLUTION HELPER ] ---
compute_file_boot_hash() {
    local target="$1"
    if [ -z "${target}" ] || ! sudo test -f "${target}"; then
        echo ""
        return 0
    fi
    # BLAKE2B (512-bit / 128 hex chars) is verified natively by Limine >= 12.x
    if command -v b2sum >/dev/null 2>&1; then
        sudo b2sum "${target}" 2>/dev/null | awk '{print $1}' || echo ""
    elif command -v xxh128sum >/dev/null 2>&1; then
        sudo xxh128sum "${target}" 2>/dev/null | awk '{print $1}' || echo ""
    else
        sudo sha256sum "${target}" 2>/dev/null | awk '{print $1}' || echo ""
    fi
}

resolve_and_hash_boot_assets() {
    local kver="$1"
    local esp_path="$2"
    local vmlinuz_src=""
    local initrd_src=""

    # Locate vmlinuz
    if sudo test -f "/boot/vmlinuz-${kver}"; then
        vmlinuz_src="/boot/vmlinuz-${kver}"
        if [ "${esp_path}" != "/boot" ]; then
            sudo cp -f "${vmlinuz_src}" "${esp_path}/vmlinuz-${kver}"
            vmlinuz_src="${esp_path}/vmlinuz-${kver}"
        fi
    elif sudo test -f "${esp_path}/vmlinuz-${kver}"; then
        vmlinuz_src="${esp_path}/vmlinuz-${kver}"
    fi

    # Locate initramfs
    for cand_initrd in "/boot/initramfs-${kver}.img" "/boot/initrd-${kver}.gz" "/boot/initrd-${kver}.img" "/boot/initrd.gz" "${esp_path}/initramfs-${kver}.img" "${esp_path}/initrd-${kver}.gz"; do
        if sudo test -f "${cand_initrd}"; then
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

    if [ -z "${vmlinuz_src}" ] || ! sudo test -f "${vmlinuz_src}" || [ -z "${initrd_src}" ] || ! sudo test -f "${initrd_src}"; then
        return 1
    fi

    local v_name i_name k_hash i_hash
    v_name=$(basename "${vmlinuz_src}")
    i_name=$(basename "${initrd_src}")
    k_hash=$(compute_file_boot_hash "${vmlinuz_src}")
    i_hash=$(compute_file_boot_hash "${initrd_src}")

    if [ -n "${k_hash}" ] && [ -n "${i_hash}" ]; then
        echo "${v_name}|${k_hash}|${i_name}|${i_hash}"
        return 0
    fi
    return 1
}

# --- [ SMART HEADER & THEME PRESERVATION HELPER ] ---
get_or_build_limine_header() {
    local esp_path="$1"
    local default_splash_hash="${2:-}"

    local existing_cfg=""
    for cand in "${esp_path}/limine.conf" "/boot/limine.conf"; do
        if sudo test -f "${cand}"; then
            existing_cfg="${cand}"
            break
        fi
    done

    local preserved_header=""
    if [ -n "${existing_cfg}" ]; then
        preserved_header=$(sudo python3 -c "
import os, re, sys, subprocess

cfg_file = '${existing_cfg}'
esp_dir = '${esp_path}'

try:
    with open(cfg_file, 'r', encoding='utf-8') as f:
        content = f.read()
except Exception:
    sys.exit(0)

# Only preserve if user customization theme zone header is present
if 'USER CUSTOMIZATION' not in content:
    sys.exit(0)

# Split before matrix separator or /+Slackware Linux or /Slackware Linux
m = re.search(r'(?:\n[ \t]*#[ \t]*={5,}[^\n]*)?\n[ \t]*#[ \t]*⚡[ \t]*AUTOGENERATED SLACKWARE MATRIX', content)
if m:
    header = content[:m.start()].rstrip()
elif '\n/+Slackware Linux' in content:
    header = content.split('\n/+Slackware Linux')[0].rstrip()
elif '\n/Slackware Linux' in content:
    header = content.split('\n/Slackware Linux')[0].rstrip()
else:
    header = ''

if header and ('timeout:' in header or 'hash_mismatch_panic:' in header or 'interface_branding:' in header):
    def repl_wp(m_match):
        fname = m_match.group(1)
        full_path = os.path.join(esp_dir, fname.lstrip('/'))
        if not os.path.exists(full_path):
            full_path = os.path.join('/boot', fname.lstrip('/'))
        h = ''
        if os.path.exists(full_path):
            try:
                res = subprocess.run(['b2sum', full_path], capture_output=True, text=True)
                if res.returncode == 0:
                    h = res.stdout.strip().split()[0]
            except Exception:
                pass
        if h:
            return f'wallpaper: boot():/{fname}#{h}'
        return m_match.group(0)

    header = re.sub(r'^[ \t]*wallpaper:[ \t]*boot\(\):/([^\s#\n\r]+)(?:#[^\s\n\r]*)?', repl_wp, header, flags=re.MULTILINE)
    print(header)
" 2>/dev/null || true)
    fi

    if [ -n "${preserved_header}" ]; then
        echo "${preserved_header}"
        return 0
    fi

    local splash_line=""
    if [ -n "${default_splash_hash}" ]; then
        splash_line="# wallpaper: boot():/limine-splash.png#${default_splash_hash}\n# wallpaper_style: centered"
    fi

    cat << DEFAULT_HEADER_EOF
# ==============================================================================
# 🎨 USER CUSTOMIZATION & THEME ZONE (Edit freely below this line)
# ==============================================================================
# NOTE: If Secure Boot is active, manual edits to this file require
# running: 'sudo limine-enroll-config' after saving.
# ==============================================================================
timeout: 6
default_entry: 2
remember_last_entry: yes
mouse: no
# Integrity Panic: Set to 'yes' only if strict anti-tampering lockdown is required.
hash_mismatch_panic: no

# --- [ INTERFACE & BRANDING ] ---
interface_branding: Slackware Linux (Most Excellent Edition)
interface_resolution: 1920x1080x32

# --- [ COLOR THEME (Slackware Light Blue & Translucent Box) ] ---
# term_background is TTRRGGBB (TT = Transparency: ff=100% transparent, e0/d0=light glass, 00=opaque)
term_background: e0000000
term_foreground: 55ffff
term_highlight_background: 0055aa
term_highlight_foreground: ffffff
backdrop: 000000

# --- [ GRAPHICAL WALLPAPER (Optional) ] ---
# Uncomment to enable wallpaper. Use 'centered' for badges/icons, 'stretched' for full wallpapers.
$(echo -e "${splash_line}")

# Reference ANSI Palette (Optional override):
# term_palette: 000000;aa0000;00aa00;aa5500;0000aa;aa00aa;00aaaa;aaaaaa;555555;ff5555;55ff55;ffff55;5555ff;ff55ff;55ffff;ffffff
DEFAULT_HEADER_EOF
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

    sync_host_kernel_cmdline_config "${esp_path}"

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

    local host_cmdline
    host_cmdline=$(get_host_kernel_cmdline)

    local standard_cmdline="${root_cmd}${root_extra} rw ${host_cmdline}"
    standard_cmdline=$(echo "${standard_cmdline}" | tr -s ' ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    # Recovery cmdline: ro single, remove quiet, splash, and transient loglevels
    local recovery_host_cmdline
    recovery_host_cmdline=$(echo "${host_cmdline}" | tr ' ' '\n' | grep -v -E '^(quiet|splash|loglevel=.*|rd\.udev\.log_priority=.*)$' | tr '\n' ' ' || true)
    local recovery_cmdline="${root_cmd}${root_extra} ro single ${recovery_host_cmdline}"
    recovery_cmdline=$(echo "${recovery_cmdline}" | tr -s ' ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    # Verify splash wallpaper and compute BLAKE2B hash
    local splash_path=""
    for cand in "${esp_path}/limine-splash.png" "${esp_path}/splash.png" "/usr/share/slacky-update/assets/slackware_icon_HD.png"; do
        if sudo test -f "${cand}"; then
            splash_path="${cand}"
            break
        fi
    done

    local splash_hash=""
    if [ -n "${splash_path}" ] && sudo test -f "${splash_path}"; then
        local target_splash="${esp_path}/limine-splash.png"
        if [ "${splash_path}" != "${target_splash}" ]; then
            sudo cp -f "${splash_path}" "${target_splash}"
        fi
        splash_hash=$(compute_file_boot_hash "${target_splash}")
    fi

    # Prune orphaned kernels and initramfs from ESP if /boot and ESP are separate
    if [ "${esp_path}" != "/boot" ] && sudo test -d "${esp_path}"; then
        for esp_f in "${esp_path}"/vmlinuz-*; do
            sudo test -f "${esp_f}" || continue
            local esp_kver
            esp_kver=$(basename "${esp_f}" | sed 's/^vmlinuz-//')
            if ! sudo test -f "/boot/vmlinuz-${esp_kver}"; then
                log_info "Pruning obsolete kernel from ESP: $(basename "${esp_f}")"
                sudo rm -f "${esp_f}" "${esp_path}/initramfs-${esp_kver}.img"* "${esp_path}/initrd-${esp_kver}.gz"* 2>/dev/null || true
            fi
        done
    fi

    # Resolve early CPU microcode (Intel / AMD) if present on ESP
    local ucode_name="" ucode_hash=""
    for cand_ucode in "${esp_path}/intel-ucode.cpio" "/boot/intel-ucode.cpio" "${esp_path}/amd-ucode.cpio" "/boot/amd-ucode.cpio"; do
        if sudo test -f "${cand_ucode}"; then
            local base_ucode
            base_ucode=$(basename "${cand_ucode}")
            if [ "${esp_path}" != "/boot" ] && sudo test -f "/boot/${base_ucode}"; then
                sudo cp -f "/boot/${base_ucode}" "${esp_path}/${base_ucode}"
            fi
            ucode_name="${base_ucode}"
            ucode_hash=$(compute_file_boot_hash "${esp_path}/${base_ucode}")
            log_info "Identified CPU early microcode asset: ${base_ucode} (BLAKE2B: ${ucode_hash:0:12}...)"
            break
        fi
    done

    # Analyze all kernels using python3 classifier (Primary vs Fallback separation)
    local kernel_class_json
    kernel_class_json=$(sudo python3 -c "
import os, re, json

def get_flavor_and_label(k):
    if '-cachyos-bore-lto' in k or '-cachyos-lto' in k:
        return ('cachyos-bore-lto', 'Linux Cachyos BORE (LTO)', 50)
    elif '-cachyos-bore' in k:
        return ('cachyos-bore', 'Linux Cachyos BORE', 40)
    elif '-cachyos-rc' in k:
        return ('cachyos-rc', 'Linux Cachyos RC', 10)
    elif '-cachyos-lts' in k:
        return ('cachyos-lts', 'Linux Cachyos LTS', 20)
    elif '-cachyos' in k:
        return ('cachyos-standard', 'Linux Cachyos Standard', 30)
    elif 'vmlinuz-generic' in k or 'generic' in k:
        return ('slackware', 'Slackware Linux', -40)
    elif 'vmlinuz-huge' in k or 'huge' in k:
        return ('slackware', 'Slackware Linux (Huge)', -60)
    else:
        return ('slackware', 'Slackware Linux', -40)

def rank(k):
    flv, label, tier = get_flavor_and_label(k)
    nums = [int(x) for x in re.findall(r'\d+', k)]
    return (tier, nums)

search_dirs = list(set(['/boot', '${esp_path}']))
found = set()
for d in search_dirs:
    if os.path.exists(d):
        try:
            for f in os.listdir(d):
                if f.startswith('vmlinuz-') and not os.path.islink(os.path.join(d, f)):
                    found.add(f.replace('vmlinuz-', ''))
        except Exception:
            pass

sorted_kernels = sorted(list(found), key=rank, reverse=True)

flavor_seen = {}
primary = []
fallback = []
slackware_kver = None

for k in sorted_kernels:
    flv, label, tier = get_flavor_and_label(k)
    if flv == 'slackware' and slackware_kver is None:
        slackware_kver = k
    if flv not in flavor_seen:
        flavor_seen[flv] = k
        primary.append({'kver': k, 'label': label})
    else:
        fallback.append({'kver': k, 'label': f'{label} ({k})'})

top_primary = primary[0] if primary else None

print(json.dumps({
    'primary': primary,
    'fallback': fallback,
    'top_primary': top_primary,
    'slackware': slackware_kver
}))
" 2>/dev/null || echo '{"primary":[],"fallback":[],"top_primary":null,"slackware":null}')

    local primary_entries=""
    local top_kver="" top_label=""
    local top_vname="" top_khash="" top_iname="" top_ihash=""
    local slack_kver="" slack_label="Slackware Linux"
    local slack_vname="" slack_khash="" slack_iname="" slack_ihash=""

    slack_kver=$(echo "${kernel_class_json}" | python3 -c "import sys, json; print(json.load(sys.stdin).get('slackware') or '')" 2>/dev/null || true)

    # 1. Primary Entries (Main Menu - Clean title without version numbers)
    while IFS=$'\t' read -r p_kver p_label; do
        [ -n "${p_kver}" ] || continue
        local asset_info
        asset_info=$(resolve_and_hash_boot_assets "${p_kver}" "${esp_path}" || true)
        [ -n "${asset_info}" ] || continue

        local v_name k_hash i_name i_hash
        IFS='|' read -r v_name k_hash i_name i_hash <<< "${asset_info}"

        if [ -z "${top_kver}" ]; then
            top_kver="${p_kver}"
            top_label="${p_label}"
            top_vname="${v_name}"
            top_khash="${k_hash}"
            top_iname="${i_name}"
            top_ihash="${i_hash}"
        fi

        if [ "${p_kver}" = "${slack_kver}" ]; then
            slack_vname="${v_name}"
            slack_khash="${k_hash}"
            slack_iname="${i_name}"
            slack_ihash="${i_hash}"
        fi

        local ucode_line=""
        if [ -n "${ucode_name}" ] && [ -n "${ucode_hash}" ] && [[ "${i_name}" =~ ^initrd.*\.gz$|^initrd.*generic.*|^initrd.*huge.* ]]; then
            ucode_line="  module_path: boot():/${ucode_name}#${ucode_hash}\n"
        fi

        primary_entries+="\n  //${p_label}\n"
        primary_entries+="  ### This kernel entry is auto-generated by slacky-update\n"
        primary_entries+="  comment: Kernel version: ${p_kver}\n"
        primary_entries+="  protocol: linux\n"
        primary_entries+="  path: boot():/${v_name}#${k_hash}\n"
        if [ -n "${ucode_line}" ]; then
            primary_entries+="${ucode_line}"
        fi
        primary_entries+="  module_path: boot():/${i_name}#${i_hash}\n"
        primary_entries+="  cmdline: ${standard_cmdline}\n"
    done < <(echo "${kernel_class_json}" | python3 -c "import sys, json; data=json.load(sys.stdin); [print(f\"{x['kver']}\t{x['label']}\") for x in data.get('primary', [])]" 2>/dev/null || true)

    # 2. Fallback Kernels Submenu (Nested under /+Slackware Linux)
    local fallback_entries=""
    local has_fallback=false
    while IFS=$'\t' read -r f_kver f_label; do
        [ -n "${f_kver}" ] || continue
        local asset_info
        asset_info=$(resolve_and_hash_boot_assets "${f_kver}" "${esp_path}" || true)
        [ -n "${asset_info}" ] || continue

        local v_name k_hash i_name i_hash
        IFS='|' read -r v_name k_hash i_name i_hash <<< "${asset_info}"

        if [ "${has_fallback}" = false ]; then
            fallback_entries+="\n  //Fallback Kernels\n"
            fallback_entries+="  ### Submenu for fallback kernels\n"
            has_fallback=true
        fi

        local f_ucode_line=""
        if [ -n "${ucode_name}" ] && [ -n "${ucode_hash}" ] && [[ "${i_name}" =~ ^initrd.*\.gz$|^initrd.*generic.*|^initrd.*huge.* ]]; then
            f_ucode_line="    module_path: boot():/${ucode_name}#${ucode_hash}\n"
        fi

        fallback_entries+="    ///${f_label}\n"
        fallback_entries+="    comment: Kernel version: ${f_kver}\n"
        fallback_entries+="    protocol: linux\n"
        fallback_entries+="    path: boot():/${v_name}#${k_hash}\n"
        if [ -n "${f_ucode_line}" ]; then
            fallback_entries+="${f_ucode_line}"
        fi
        fallback_entries+="    module_path: boot():/${i_name}#${i_hash}\n"
        fallback_entries+="    cmdline: ${standard_cmdline}\n"
    done < <(echo "${kernel_class_json}" | python3 -c "import sys, json; data=json.load(sys.stdin); [print(f\"{x['kver']}\t{x['label']}\") for x in data.get('fallback', [])]" 2>/dev/null || true)

    # Ensure Slackware kernel assets are resolved if not already captured
    if [ -n "${slack_kver}" ] && [ -z "${slack_vname}" ]; then
        local s_info
        s_info=$(resolve_and_hash_boot_assets "${slack_kver}" "${esp_path}" || true)
        if [ -n "${s_info}" ]; then
            IFS='|' read -r slack_vname slack_khash slack_iname slack_ihash <<< "${s_info}"
        fi
    fi

    # 3. Dedicated Recovery Mode Submenu (Nested under /+Slackware Linux)
    local recovery_entries=""
    if [ -n "${top_kver}" ] && [ -n "${top_vname}" ]; then
        local rec_ucode_line=""
        if [ -n "${ucode_name}" ] && [ -n "${ucode_hash}" ] && [[ "${top_iname}" =~ ^initrd.*\.gz$|^initrd.*generic.*|^initrd.*huge.* ]]; then
            rec_ucode_line="    module_path: boot():/${ucode_name}#${ucode_hash}\n"
        fi

        recovery_entries+="\n  //Recovery Mode\n"
        recovery_entries+="  ### Submenu for single-user recovery mode\n"
        recovery_entries+="    ///${top_label} (Recovery Mode)\n"
        recovery_entries+="    protocol: linux\n"
        recovery_entries+="    path: boot():/${top_vname}#${top_khash}\n"
        if [ -n "${rec_ucode_line}" ]; then
            recovery_entries+="${rec_ucode_line}"
        fi
        recovery_entries+="    module_path: boot():/${top_iname}#${top_ihash}\n"
        recovery_entries+="    cmdline: ${recovery_cmdline}\n"

        if [ -n "${slack_kver}" ] && [ -n "${slack_vname}" ] && [ "${slack_kver}" != "${top_kver}" ]; then
            local slack_rec_ucode_line=""
            if [ -n "${ucode_name}" ] && [ -n "${ucode_hash}" ] && [[ "${slack_iname}" =~ ^initrd.*\.gz$|^initrd.*generic.*|^initrd.*huge.* ]]; then
                slack_rec_ucode_line="    module_path: boot():/${ucode_name}#${ucode_hash}\n"
            fi
            recovery_entries+="    ///Slackware Linux (Recovery Mode)\n"
            recovery_entries+="    protocol: linux\n"
            recovery_entries+="    path: boot():/${slack_vname}#${slack_khash}\n"
            if [ -n "${slack_rec_ucode_line}" ]; then
                recovery_entries+="${slack_rec_ucode_line}"
            fi
            recovery_entries+="    module_path: boot():/${slack_iname}#${slack_ihash}\n"
            recovery_entries+="    cmdline: ${recovery_cmdline}\n"
        fi
    fi

    # 4. Btrfs Snapper Snapshots Submenu (Nested under /+Slackware Linux)
    local snapshot_entries=""
    if [ "${root_fs}" = "btrfs" ]; then
        local snap_dirs=("/.snapshots" "/@snapshots" "/mnt/@snapshots")
        local found_snap_dir=""
        for sd in "${snap_dirs[@]}"; do
            if sudo test -d "${sd}"; then
                found_snap_dir="${sd}"
                break
            fi
        done

        if [ -n "${found_snap_dir}" ]; then
            local snap_list=()
            while IFS= read -r s_id; do
                [ -n "${s_id}" ] && snap_list+=("${s_id}")
            done < <(scan_snapper_boot_candidates "${found_snap_dir}")

            if [ "${#snap_list[@]}" -gt 0 ] && [ -n "${top_kver}" ] && [ -n "${top_vname}" ]; then
                local boot_policy
                boot_policy=$(get_snapper_sync_config "SNAPPER_BOOT_POLICY" "daily_spread")
                snapshot_entries+="\n     //Snapshots\n"
                snapshot_entries+="     ### Auto-generated by slacky-snapper-limine-sync (${boot_policy})\n"
                snapshot_entries+="     comment: ${#snap_list[@]} snapshots (${boot_policy})\n"
                for s_path in "${snap_list[@]}"; do
                    local s_num
                    s_num=$(basename "${s_path}")
                    local s_desc=""
                    local s_date=""
                    if sudo test -f "${s_path}/info.xml"; then
                        s_desc=$(sudo grep -oPm1 "(?<=<description>)[^<]+" "${s_path}/info.xml" 2>/dev/null || true)
                        s_date=$(sudo grep -oPm1 "(?<=<date>)[^<]+" "${s_path}/info.xml" 2>/dev/null || true)
                    fi
                    local s_label="${s_num}"
                    [ -n "${s_desc}" ] && s_label="${s_label} │ ${s_desc}"
                    [ -n "${s_date}" ] && s_label="${s_label} (${s_date%% *})"

                    local s_subvol="@snapshots/${s_num}/snapshot"
                    if [ -n "${root_flags}" ]; then
                        local cur_subvol
                        cur_subvol=$(echo "${root_flags}" | grep -o -E 'subvol=[^ ]+' | cut -d'=' -f2 || true)
                        if [ -n "${cur_subvol}" ] && [ "${cur_subvol}" != "/" ]; then
                            s_subvol="${cur_subvol}/.snapshots/${s_num}/snapshot"
                        fi
                    fi

                    local s_cmdline="${root_cmd} rootflags=subvol=${s_subvol} rw ${host_cmdline}"
                    s_cmdline=$(echo "${s_cmdline}" | tr -s ' ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

                    snapshot_entries+="     ///${s_label}\n"
                    # Primary kernel snapshot entry
                    snapshot_entries+="     ////${top_label}\n"
                    snapshot_entries+="     protocol: linux\n"
                    snapshot_entries+="     path: boot():/${top_vname}#${top_khash}\n"
                    snapshot_entries+="     module_path: boot():/${top_iname}#${top_ihash}\n"
                    snapshot_entries+="     cmdline: ${s_cmdline}\n"

                    # Slackware fallback kernel snapshot entry
                    if [ -n "${slack_kver}" ] && [ -n "${slack_vname}" ] && [ "${slack_kver}" != "${top_kver}" ]; then
                        snapshot_entries+="     ////Slackware Linux\n"
                        snapshot_entries+="     protocol: linux\n"
                        snapshot_entries+="     path: boot():/${slack_vname}#${slack_khash}\n"
                        snapshot_entries+="     module_path: boot():/${slack_iname}#${slack_ihash}\n"
                        snapshot_entries+="     cmdline: ${s_cmdline}\n"
                    fi
                done
            fi
        fi
    fi

    # 5. Foreign & Fallback Bootloaders (Windows, GRUB)
    local foreign_entries=""
    if sudo test -f "${esp_path}/EFI/Microsoft/Boot/bootmgfw.efi"; then
        foreign_entries+="\n/Windows Boot Manager\n"
        foreign_entries+="    protocol: efi_chainload\n"
        foreign_entries+="    image_path: boot():/EFI/Microsoft/Boot/bootmgfw.efi\n"
    fi

    if sudo test -f "${esp_path}/EFI/Slackware/grubx64.efi"; then
        foreign_entries+="\n/GRUB Bootloader (Fallback)\n"
        foreign_entries+="    protocol: efi_chainload\n"
        foreign_entries+="    image_path: boot():/EFI/Slackware/grubx64.efi\n"
    elif sudo test -f "${esp_path}/EFI/Slackware/shimx64.efi"; then
        foreign_entries+="\n/GRUB Bootloader (Secure Boot Shim)\n"
        foreign_entries+="    protocol: efi_chainload\n"
        foreign_entries+="    image_path: boot():/EFI/Slackware/shimx64.efi\n"
    fi

    # 6. Retrieve or build smart theme header (Preserves user customizations & auto-hashes wallpaper)
    local theme_header
    theme_header=$(get_or_build_limine_header "${esp_path}" "${splash_hash}")

    local limine_cfg_file="${esp_path}/limine.conf"
    local limine_cfg_tmp
    limine_cfg_tmp=$(mktemp /tmp/slacky-limine-cfg.XXXXXX)

    cat << LIMINE_HEADER_EOF > "${limine_cfg_tmp}"
${theme_header}

# ==============================================================================
# ⚡ AUTOGENERATED SLACKWARE MATRIX (DO NOT EDIT BELOW THIS LINE)
# ==============================================================================
/+Slackware Linux
### This OS entry is auto-generated by slacky-update
comment: Slackware Linux
comment: machine-id=${machine_id} order-priority=50
$(echo -e "${primary_entries}")
$(echo -e "${fallback_entries}")
$(echo -e "${recovery_entries}")
$(echo -e "${snapshot_entries}")
$(echo -e "${foreign_entries}")
LIMINE_HEADER_EOF

    sudo cp -f "${limine_cfg_tmp}" "${limine_cfg_file}"
    sudo rm -f "${limine_cfg_tmp}" 2>/dev/null || true
    sudo chmod 644 "${limine_cfg_file}" 2>/dev/null || true

    # Also keep a mirror at /boot/limine.conf if /boot != esp_path
    if [ "${esp_path}" != "/boot" ] && [ -d "/boot" ]; then
        sudo cp -f "${limine_cfg_file}" "/boot/limine.conf" 2>/dev/null || true
    fi

    return 0
}

# --- [ CONFIG ENROLLMENT & SBCTL SIGNING ] ---
enroll_limine_config_hash() {
    validate_privileges

    local esp_path
    esp_path=$(detect_limine_esp_path)
    local target_efi="${esp_path}/EFI/limine/limine_x64.efi"
    local cfg_file="${esp_path}/limine.conf"

    if ! sudo test -f "${target_efi}"; then
        log_error "Limine EFI executable not found at ${target_efi}."
        return 1
    fi
    if ! sudo test -f "${cfg_file}"; then
        log_error "Limine configuration not found at ${cfg_file}."
        return 1
    fi

    # Reset target_efi to clean original binary before enrolling to prevent Authenticode digest corruption
    local limine_clean_src=""
    for cand in "/usr/share/limine/BOOTX64.EFI" "/usr/share/limine/x86_64/BOOTX64.EFI" "/usr/lib/limine/BOOTX64.EFI"; do
        if [ -f "${cand}" ]; then
            limine_clean_src="${cand}"
            break
        fi
    done

    if [ -n "${limine_clean_src}" ]; then
        local clean_bak_tmp
        clean_bak_tmp=$(mktemp -d /tmp/limine-bak.XXXXXX)
        cp -f "${limine_clean_src}" "${clean_bak_tmp}/limine_x64.efi"
        sudo cp -f "${limine_clean_src}" "${target_efi}"
        sudo tar --owner=0 --group=0 -cf "${esp_path}/EFI/limine/limine_x64.bak" -C "${clean_bak_tmp}" "limine_x64.efi" 2>/dev/null || true
        rm -rf "${clean_bak_tmp}" 2>/dev/null || true
    elif sudo test -f "${esp_path}/EFI/limine/limine_x64.bak"; then
        sudo tar -xf "${esp_path}/EFI/limine/limine_x64.bak" --directory="${esp_path}/EFI/limine" 2>/dev/null || true
    fi

    local limine_cli
    limine_cli=$(command -v limine 2>/dev/null || echo "/usr/bin/limine")
    if [ -x "${limine_cli}" ]; then
        local cfg_hash
        cfg_hash=$(sudo b2sum "${cfg_file}" 2>/dev/null | awk '{print $1}')
        if [ -n "${cfg_hash}" ]; then
            if ! { sudo "${limine_cli}" enroll-config "${target_efi}" "${cfg_file}" >/dev/null 2>&1 || sudo "${limine_cli}" enroll-config "${target_efi}" "${cfg_hash}" >/dev/null 2>&1 || sudo "${limine_cli}" enroll-config "${target_efi}" < "${cfg_file}" >/dev/null 2>&1; }; then
                log_warn "Notice: limine enroll-config returned non-zero (or already enrolled)."
            fi
            if sudo test -f "${esp_path}/EFI/BOOT/BOOTX64.EFI"; then
                sudo "${limine_cli}" enroll-config "${esp_path}/EFI/BOOT/BOOTX64.EFI" "${cfg_file}" >/dev/null 2>&1 || sudo "${limine_cli}" enroll-config "${esp_path}/EFI/BOOT/BOOTX64.EFI" "${cfg_hash}" >/dev/null 2>&1 || true
            fi
        fi
    fi
    return 0
}

sign_limine_efi_sbctl() {
    validate_privileges
    local esp_path
    esp_path=$(detect_limine_esp_path)
    local target_efi="${esp_path}/EFI/limine/limine_x64.efi"

    local sbctl_bin
    sbctl_bin=$(command -v sbctl 2>/dev/null || echo "/usr/bin/sbctl")
    if [ -x "${sbctl_bin}" ]; then
        if sudo "${sbctl_bin}" status 2>/dev/null | grep -qi "Installed:.*✓\|installed.*true" || sudo test -f "/var/lib/sbctl/files.json"; then
            if ! sudo "${sbctl_bin}" sign -s "${target_efi}" >/dev/null 2>&1; then
                log_warn "sbctl failed to sign ${target_efi}"
            fi
            if sudo test -f "${esp_path}/EFI/BOOT/BOOTX64.EFI"; then
                sudo "${sbctl_bin}" sign -s "${esp_path}/EFI/BOOT/BOOTX64.EFI" >/dev/null 2>&1 || true
            fi
            if sudo test -f "${esp_path}/EFI/Slackware/grubx64.efi"; then
                sudo "${sbctl_bin}" sign -s "${esp_path}/EFI/Slackware/grubx64.efi" >/dev/null 2>&1 || true
            fi
            if sudo test -f "${esp_path}/EFI/Slackware/shimx64.efi"; then
                sudo "${sbctl_bin}" sign -s "${esp_path}/EFI/Slackware/shimx64.efi" >/dev/null 2>&1 || true
            fi
            for kern in /boot/vmlinuz-*; do
                [ -f "${kern}" ] || continue
                [ -L "${kern}" ] && continue
                sudo "${sbctl_bin}" sign -s "${kern}" >/dev/null 2>&1 || true
            done
        fi
    fi

    # Silent sync to disk to prevent FAT32 corruption
    sync -f "${target_efi}" 2>/dev/null || sync 2>/dev/null || true
    backup_limine_self_heal
    return 0
}

enroll_and_sign_limine() {
    enroll_limine_config_hash || return 1
    sign_limine_efi_sbctl || return 1
    return 0
}

# --- [ LIMINE SELF-HEAL BACKUP & RESTORE ] ---
backup_limine_self_heal() {
    local esp_path
    esp_path=$(detect_limine_esp_path)
    sudo test -d "${esp_path}/EFI/limine" || return 0

    local current_user="${SUDO_USER:-${USER:-}}"
    local user_backup_dir="/home/${current_user}/.limine_backup"
    local system_backup_dir="/var/cache/slacky-update/limine_backup"

    if [ -n "${current_user}" ] && [ -d "/home/${current_user}" ]; then
        mkdir -p "${user_backup_dir}" 2>/dev/null || true
        sudo rsync -a --delete "${esp_path}/EFI/limine/" "${user_backup_dir}/" 2>/dev/null || true
        sudo chown -R "${current_user}:" "${user_backup_dir}" 2>/dev/null || true
        if sudo test -f "${esp_path}/limine.conf"; then
            sudo cp -f "${esp_path}/limine.conf" "${user_backup_dir}/" 2>/dev/null || true
            sudo chown "${current_user}:" "${user_backup_dir}/limine.conf" 2>/dev/null || true
        fi
    fi

    validate_privileges
    sudo mkdir -p "${system_backup_dir}" 2>/dev/null || true
    sudo rsync -a --delete "${esp_path}/EFI/limine/" "${system_backup_dir}/" 2>/dev/null || true
    if sudo test -f "${esp_path}/limine.conf"; then
        sudo cp -f "${esp_path}/limine.conf" "${system_backup_dir}/" 2>/dev/null || true
    fi
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
    for cand in "/usr/share/limine/BOOTX64.EFI" "/usr/share/limine/x86_64/BOOTX64.EFI" "/usr/lib/limine/BOOTX64.EFI" "/usr/share/limine/limine_x64.efi"; do
        if [ -f "${cand}" ]; then
            limine_efi_src="${cand}"
            break
        fi
    done
    if [ -z "${limine_efi_src}" ]; then
        limine_efi_src=$(find /usr/share/limine /usr/lib/limine -name "BOOTX64.EFI" -o -name "limine_x64.efi" 2>/dev/null | head -n 1 || true)
    fi

    if [ -z "${limine_efi_src}" ]; then
        log_error "Limine EFI binary (BOOTX64.EFI) not found in system."
        return 1
    fi

    log_info "Deploying Limine EFI binary (${limine_efi_src}) -> ${target_limine_dir}/limine_x64.efi..."
    sudo cp -f "${limine_efi_src}" "${target_limine_dir}/limine_x64.efi"

    local clean_bak_tmp
    clean_bak_tmp=$(mktemp -d /tmp/limine-bak.XXXXXX)
    cp -f "${limine_efi_src}" "${clean_bak_tmp}/limine_x64.efi"
    sudo tar --owner=0 --group=0 -cf "${target_limine_dir}/limine_x64.bak" -C "${clean_bak_tmp}" "limine_x64.efi" 2>/dev/null || true
    rm -rf "${clean_bak_tmp}" 2>/dev/null || true

    # Deploy UEFI standard fallback executable (/EFI/BOOT/BOOTX64.EFI) if missing
    local fallback_dir="${esp_path}/EFI/BOOT"
    local fallback_efi="${fallback_dir}/BOOTX64.EFI"
    if [ ! -f "${fallback_efi}" ]; then
        sudo mkdir -p "${fallback_dir}"
        sudo cp -f "${limine_efi_src}" "${fallback_efi}"
        log_info "Deployed standard UEFI fallback binary -> ${fallback_efi}"
    fi

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
                log_info "Registering UEFI NVRAM Boot Entry: Limine Slackware on ${esp_disk} p${esp_part}..."
                # Check if already present to avoid duplicate entries
                if ! sudo "${efibootmgr_bin}" 2>/dev/null | grep -qi "Limine Slackware"; then
                    sudo "${efibootmgr_bin}" -c -d "${esp_disk}" -p "${esp_part}" -L "Limine Slackware" -l "\\EFI\\limine\\limine_x64.efi" >/dev/null 2>&1 || true
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

# --- [ INTERACTIVE KERNEL CMDLINE & GAMING HUB ] ---
manage_kernel_cmdline_interactive() {
    validate_privileges

    local esp_path
    esp_path=$(detect_limine_esp_path)

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
    local fixed_root="[${root_cmd}${root_extra} rw]"

    local current_custom
    current_custom=$(get_host_kernel_cmdline)

    local iommu_flag
    iommu_flag=$(get_iommu_param_for_cpu)

    local is_amd_cpu=false
    if grep -qi "AuthenticAMD" /proc/cpuinfo 2>/dev/null; then
        is_amd_cpu=true
    fi

    probe_gpu_hardware >/dev/null 2>&1 || true

    while true; do
        # Clean current_custom
        current_custom=$(echo "${current_custom}" | tr -s ' ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

        # Check toggle states
        local has_quiet=false
        if echo " ${current_custom} " | grep -q " quiet "; then has_quiet=true; fi

        local has_nvidia=false
        if echo " ${current_custom} " | grep -q "nvidia_drm.modeset=1"; then has_nvidia=true; fi

        local has_amd_oc=false
        if echo " ${current_custom} " | grep -q "amdgpu.ppfeaturemask="; then has_amd_oc=true; fi

        local has_watchdog=false
        if echo " ${current_custom} " | grep -q " nowatchdog "; then has_watchdog=true; fi

        local has_usb=false
        if echo " ${current_custom} " | grep -q "usbcore.autosuspend=-1"; then has_usb=true; fi

        local has_umip=false
        if echo " ${current_custom} " | grep -q "clearcpuid=umip"; then has_umip=true; fi

        local has_iommu=false
        if echo " ${current_custom} " | grep -E -q '(_iommu=on|iommu=pt)'; then has_iommu=true; fi

        local has_zswap=false
        if echo " ${current_custom} " | grep -q "zswap.enabled=1"; then has_zswap=true; fi

        local zram_active=false
        if is_zram_active; then zram_active=true; fi

        echo ""
        echo -e "${CYAN}================================================================================${RESET}"
        echo -e "${YELLOW}${BOLD}⚙️  KERNEL BOOT PARAMETERS & GAMING HUB${RESET}"
        echo -e "${CYAN}================================================================================${RESET}"
        echo -e "  • ${BOLD}Base Root (Auto):${RESET}   ${GREEN}${fixed_root}${RESET}"
        echo -e "  • ${BOLD}Active Custom:${RESET}     ${CYAN}${current_custom:-"(None - using bare root)"}${RESET}"
        echo ""
        echo -e "  ${BOLD}Toggles (Type number to flip [x] / [ ]):${RESET}"

        if [ "${has_quiet}" = "true" ]; then
            echo -e "  \033[1;32m[x]\033[0m \033[1;33m1.\033[0m Quiet & Splash Boot          [quiet splash loglevel=3 rd.udev.log_priority=3]"
        else
            echo -e "  \033[1;30m[ ]\033[0m \033[1;33m1.\033[0m Quiet & Splash Boot          [quiet splash loglevel=3 rd.udev.log_priority=3]"
        fi

        if [ "${has_nvidia}" = "true" ]; then
            echo -e "  \033[1;32m[x]\033[0m \033[1;33m2.\033[0m NVIDIA GPU Modeset & VRAM    [nvidia_drm.modeset=1 nvidia_drm.fbdev=1 nvidia.NVreg_PreserveVideoMemoryAllocations=1]"
        else
            echo -e "  \033[1;30m[ ]\033[0m \033[1;33m2.\033[0m NVIDIA GPU Modeset & VRAM    [nvidia_drm.modeset=1 nvidia_drm.fbdev=1 nvidia.NVreg_PreserveVideoMemoryAllocations=1]"
        fi

        local amd_note=""
        if [ "${HAS_AMD}" = "true" ] || lspci 2>/dev/null | grep -Ei 'vga|3d' | grep -qi 'amd|radeon|ati'; then
            amd_note=" (AMD GPU detected)"
        fi
        if [ "${has_amd_oc}" = "true" ]; then
            echo -e "  \033[1;32m[x]\033[0m \033[1;33m3.\033[0m AMD GPU Overclocking (LACT)  [amdgpu.ppfeaturemask=0xffffffff]${amd_note}"
        else
            echo -e "  \033[1;30m[ ]\033[0m \033[1;33m3.\033[0m AMD GPU Overclocking (LACT)  [amdgpu.ppfeaturemask=0xffffffff]${amd_note}"
        fi

        if [ "${has_watchdog}" = "true" ]; then
            echo -e "  \033[1;32m[x]\033[0m \033[1;33m4.\033[0m Disable Watchdog             [nowatchdog]"
        else
            echo -e "  \033[1;30m[ ]\033[0m \033[1;33m4.\033[0m Disable Watchdog             [nowatchdog]"
        fi

        if [ "${has_usb}" = "true" ]; then
            echo -e "  \033[1;32m[x]\033[0m \033[1;33m5.\033[0m Disable USB Autosuspend      [usbcore.autosuspend=-1]"
        else
            echo -e "  \033[1;30m[ ]\033[0m \033[1;33m5.\033[0m Disable USB Autosuspend      [usbcore.autosuspend=-1]"
        fi

        if [ "${has_umip}" = "true" ]; then
            echo -e "  \033[1;32m[x]\033[0m \033[1;33m6.\033[0m Hypervisor / VM UMIP Fix     [clearcpuid=umip]"
        else
            echo -e "  \033[1;30m[ ]\033[0m \033[1;33m6.\033[0m Hypervisor / VM UMIP Fix     [clearcpuid=umip]"
        fi

        local cpu_tag="Intel CPU"
        [ "${is_amd_cpu}" = "true" ] && cpu_tag="AMD Ryzen"
        if [ "${has_iommu}" = "true" ]; then
            echo -e "  \033[1;32m[x]\033[0m \033[1;33m7.\033[0m IOMMU / VFIO Passthrough     [${iommu_flag}] (${cpu_tag})"
        else
            echo -e "  \033[1;30m[ ]\033[0m \033[1;33m7.\033[0m IOMMU / VFIO Passthrough     [${iommu_flag}] (${cpu_tag})"
        fi

        if [ "${zram_active}" = "true" ]; then
            echo -e "  \033[1;30m[ ]\033[0m \033[1;33m8.\033[0m ZSWAP Fast RAM Compression   [zswap.enabled=1 ...] ${YELLOW}(⛔ Disabled: ZRAM active)${RESET}"
        else
            if [ "${has_zswap}" = "true" ]; then
                echo -e "  \033[1;32m[x]\033[0m \033[1;33m8.\033[0m ZSWAP Fast RAM Compression   [zswap.enabled=1 zswap.compressor=zstd zswap.max_pool_percent=25]"
            else
                echo -e "  \033[1;30m[ ]\033[0m \033[1;33m8.\033[0m ZSWAP Fast RAM Compression   [zswap.enabled=1 zswap.compressor=zstd zswap.max_pool_percent=25]"
            fi
        fi

        echo ""
        echo -e "  ${BOLD}Actions:${RESET}"
        echo -e "  \033[1;36m[E]\033[0m ✏️  Edit Raw CMDLINE (Inline readline terminal prompt)"
        echo -e "  \033[1;36m[N]\033[0m 📝  Open in Nano / Text Editor"
        echo -e "  \033[1;36m[R]\033[0m 🔄  Reset to Hardware & Sensible Defaults"
        echo -e "  \033[1;32m[S]\033[0m 💾  Save & Enroll (Rebuild limine.conf, BLAKE2B & Sign EFI)"
        echo -e "  \033[1;31m[Q]\033[0m ↩️  Cancel / Return without saving"
        echo ""
        echo -n "Select option [1-8, E, N, R, S, Q]: "
        local act_choice
        read -r act_choice || act_choice="Q"
        act_choice=$(echo "${act_choice}" | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]')

        case "${act_choice}" in
            1)
                current_custom=$(python3 -c "
import sys
cur = sys.argv[1]
quiet_tokens = 'quiet splash loglevel=3 rd.udev.log_priority=3'
tokens = cur.split()
has_q = 'quiet' in tokens
if has_q:
    new_t = [x for x in tokens if x not in quiet_tokens.split() and not x.startswith('loglevel=') and not x.startswith('rd.udev.log_priority=')]
else:
    new_t = tokens + quiet_tokens.split()
print(' '.join(new_t))
" "${current_custom}")
                ;;
            2)
                current_custom=$(python3 -c "
import sys
cur = sys.argv[1]
nv_tokens = 'nvidia_drm.modeset=1 nvidia_drm.fbdev=1 nvidia.NVreg_PreserveVideoMemoryAllocations=1'
tokens = cur.split()
has_nv = 'nvidia_drm.modeset=1' in tokens
if has_nv:
    new_t = [x for x in tokens if x not in nv_tokens.split() and not x.startswith('nvidia')]
else:
    new_t = tokens + nv_tokens.split()
print(' '.join(new_t))
" "${current_custom}")
                ;;
            3)
                current_custom=$(python3 -c "
import sys
cur = sys.argv[1]
tokens = cur.split()
has_oc = any(x.startswith('amdgpu.ppfeaturemask=') for x in tokens)
if has_oc:
    new_t = [x for x in tokens if not x.startswith('amdgpu.ppfeaturemask=')]
else:
    new_t = tokens + ['amdgpu.ppfeaturemask=0xffffffff']
print(' '.join(new_t))
" "${current_custom}")
                ;;
            4)
                current_custom=$(python3 -c "
import sys
cur = sys.argv[1]
tokens = cur.split()
has_w = 'nowatchdog' in tokens
if has_w:
    new_t = [x for x in tokens if x != 'nowatchdog']
else:
    new_t = tokens + ['nowatchdog']
print(' '.join(new_t))
" "${current_custom}")
                ;;
            5)
                current_custom=$(python3 -c "
import sys
cur = sys.argv[1]
tokens = cur.split()
has_u = any(x.startswith('usbcore.autosuspend=') for x in tokens)
if has_u:
    new_t = [x for x in tokens if not x.startswith('usbcore.autosuspend=')]
else:
    new_t = tokens + ['usbcore.autosuspend=-1']
print(' '.join(new_t))
" "${current_custom}")
                ;;
            6)
                current_custom=$(python3 -c "
import sys
cur = sys.argv[1]
tokens = cur.split()
has_umip = 'clearcpuid=umip' in tokens
if has_umip:
    new_t = [x for x in tokens if x != 'clearcpuid=umip']
else:
    new_t = tokens + ['clearcpuid=umip']
print(' '.join(new_t))
" "${current_custom}")
                ;;
            7)
                current_custom=$(python3 -c "
import sys
cur = sys.argv[1]
flag = sys.argv[2]
tokens = cur.split()
has_iommu = any(x in ('intel_iommu=on', 'amd_iommu=on', 'iommu=pt') for x in tokens)
if has_iommu:
    new_t = [x for x in tokens if x not in ('intel_iommu=on', 'amd_iommu=on', 'iommu=pt') and not x.startswith('intel_iommu=') and not x.startswith('amd_iommu=') and not x.startswith('iommu=')]
else:
    new_t = tokens + flag.split()
print(' '.join(new_t))
" "${current_custom}" "${iommu_flag}")
                ;;
            8)
                if [ "${zram_active}" = "true" ]; then
                    echo -e "\n${YELLOW}⚠️  ZRAM is active on this system (/dev/zram*). ZSWAP should remain disabled.${RESET}"
                    sleep 2
                else
                    current_custom=$(python3 -c "
import sys
cur = sys.argv[1]
zs_tokens = 'zswap.enabled=1 zswap.compressor=zstd zswap.max_pool_percent=25'
tokens = cur.split()
has_zs = 'zswap.enabled=1' in tokens
if has_zs:
    new_t = [x for x in tokens if not x.startswith('zswap.')]
else:
    new_t = tokens + zs_tokens.split()
print(' '.join(new_t))
" "${current_custom}")
                fi
                ;;
            E)
                echo ""
                echo -e "${CYAN}Edit custom parameters (Press [Enter] to accept, Backspace to delete):${RESET}"
                local edited_line
                read -e -p "CMDLINE: " -i "${current_custom}" edited_line || edited_line="${current_custom}"
                current_custom="${edited_line}"
                ;;
            N)
                local tmp_cmd_file="/tmp/slacky-cmdline-$$.txt"
                echo "# Enter kernel parameters below. Lines starting with # are ignored." > "${tmp_cmd_file}"
                echo "# Fixed Root parameters (${fixed_root}) are automatically attached." >> "${tmp_cmd_file}"
                echo "${current_custom}" >> "${tmp_cmd_file}"
                local editor_bin="${EDITOR:-nano}"
                if ! command -v "${editor_bin}" >/dev/null 2>&1; then
                    editor_bin=$(command -v nano 2>/dev/null || command -v vi 2>/dev/null || echo "vi")
                fi
                "${editor_bin}" "${tmp_cmd_file}"
                current_custom=$(grep -v '^[[:space:]]*#' "${tmp_cmd_file}" 2>/dev/null | tr '\n' ' ' || true)
                rm -f "${tmp_cmd_file}" 2>/dev/null || true
                ;;
            R)
                current_custom=$(get_default_sensible_cmdline)
                echo -e "\n${GREEN}✓ Reset to Hardware & Sensible Defaults.${RESET}"
                sleep 1
                ;;
            S)
                echo ""
                log_info "Saving kernel boot parameters..."
                current_custom=$(echo "${current_custom}" | tr ' ' '\n' | grep -v -E '^(BOOT_IMAGE=.*|initrd=.*|root=.*|rootflags=.*|ro|rw)$' | tr '\n' ' ' || true)
                current_custom=$(echo "${current_custom}" | tr -s ' ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

                local standard_full="${root_cmd}${root_extra} rw ${current_custom}"
                standard_full=$(echo "${standard_full}" | tr -s ' ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

                sudo mkdir -p /etc/kernel
                echo "${standard_full}" | sudo tee /etc/kernel/cmdline >/dev/null
                sudo chmod 644 /etc/kernel/cmdline 2>/dev/null || true

                sync_host_kernel_cmdline_config "${esp_path}"
                log_info "Regenerating Limine configuration matrix (Zone B)..."
                generate_limine_configuration
                log_info "Enrolling BLAKE2B cryptographic hash & signing EFI binary with sbctl..."
                enroll_and_sign_limine

                log_success "Kernel CMDLINE updated, limine.conf generated, BLAKE2B enrolled & signed!"
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                return 0
                ;;
            Q)
                return 0
                ;;
            *)
                echo -e "\n${YELLOW}$(_ INVALID_SELECTION)${RESET}"
                sleep 1
                ;;
        esac
    done
}

# --- [ BTRFS SNAPPER SYNC CONFIGURATION & SNAPSHOT SCANNER ] ---
get_snapper_sync_config() {
    local key="${1}"
    local default_val="${2:-}"
    local cfg_file="/etc/default/limine"
    if [ -f "${cfg_file}" ]; then
        local val
        val=$(grep -E "^[[:space:]]*${key}=" "${cfg_file}" 2>/dev/null | tail -n1 | cut -d'=' -f2- | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//" | tr -d ' ' || true)
        if [ -n "${val}" ]; then
            echo "${val}"
            return 0
        fi
    fi
    echo "${default_val}"
}

set_snapper_sync_config() {
    local key="${1}"
    local val="${2}"
    local cfg_file="/etc/default/limine"
    
    validate_privileges
    sudo mkdir -p /etc/default
    
    sudo python3 - "${cfg_file}" "${key}" "${val}" << 'PYCFG'
import sys, os

cfg_file = sys.argv[1]
key = sys.argv[2]
val = sys.argv[3]

lines = []
if os.path.exists(cfg_file):
    with open(cfg_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()

found = False
new_lines = []
for line in lines:
    stripped = line.strip()
    if stripped.startswith(f"{key}=") or stripped.startswith(f"export {key}="):
        new_lines.append(f'{key}="{val}"\n')
        found = True
    else:
        new_lines.append(line)

if not found:
    if new_lines and not new_lines[-1].endswith('\n'):
        new_lines[-1] += '\n'
    new_lines.append(f'{key}="{val}"\n')

with open(cfg_file, 'w', encoding='utf-8') as f:
    f.writelines(new_lines)
PYCFG
    sudo chmod 644 "${cfg_file}" 2>/dev/null || true
}

scan_snapper_boot_candidates() {
    local snap_dir="${1:-}"
    if [ -z "${snap_dir}" ]; then
        for sd in "/.snapshots" "/@snapshots" "/mnt/@snapshots"; do
            if sudo test -d "${sd}"; then
                snap_dir="${sd}"
                break
            fi
        done
    fi
    [ -z "${snap_dir}" ] && return 0

    local policy
    policy=$(get_snapper_sync_config "SNAPPER_BOOT_POLICY" "daily_spread")
    local depth
    depth=$(get_snapper_sync_config "SNAPPER_BOOT_DEPTH" "5")

    sudo python3 - "${snap_dir}" "${policy}" "${depth}" << 'PYSNAP'
import os, sys, glob
import xml.etree.ElementTree as ET
from datetime import datetime

snap_dir = sys.argv[1]
policy = sys.argv[2]
try:
    depth = int(sys.argv[3])
except Exception:
    depth = 5

entries = []
for item in glob.glob(os.path.join(snap_dir, "[0-9]*")):
    if not os.path.isdir(item):
        continue
    s_num_str = os.path.basename(item)
    try:
        s_num = int(s_num_str)
    except ValueError:
        continue
    
    # Must contain snapshot subvolume
    snap_subvol = os.path.join(item, "snapshot")
    if not os.path.exists(snap_subvol):
        continue
    
    info_file = os.path.join(item, "info.xml")
    desc = ""
    stype = ""
    sdate = ""
    cleanup = ""
    
    if os.path.exists(info_file):
        try:
            tree = ET.parse(info_file)
            root = tree.getroot()
            desc_el = root.find("description")
            if desc_el is not None and desc_el.text:
                desc = desc_el.text.strip()
            type_el = root.find("type")
            if type_el is not None and type_el.text:
                stype = type_el.text.strip()
            date_el = root.find("date")
            if date_el is not None and date_el.text:
                sdate = date_el.text.strip()
            clean_el = root.find("cleanup")
            if clean_el is not None and clean_el.text:
                cleanup = clean_el.text.strip()
        except Exception:
            pass
            
    if not sdate:
        try:
            mtime = os.path.getmtime(item)
            sdate = datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M:%S")
        except Exception:
            sdate = "1970-01-01 00:00:00"
            
    date_day = sdate.split(" ")[0] if " " in sdate else sdate
    
    entries.append({
        "path": item,
        "num": s_num,
        "desc": desc,
        "type": stype,
        "date": sdate,
        "day": date_day,
        "cleanup": cleanup
    })

# Sort newest snapshot ID first
entries.sort(key=lambda x: x["num"], reverse=True)

selected = []
if policy == "daily_spread":
    seen_days = set()
    for e in entries:
        day = e["day"]
        if day not in seen_days:
            seen_days.add(day)
            selected.append(e)
            if len(selected) >= depth:
                break
elif policy == "important":
    for e in entries:
        is_imp = False
        if e["cleanup"] in ("", "none") or e["type"] in ("pre", "post"):
            is_imp = True
        elif e["desc"] and not e["desc"].lower().startswith("timeline") and not e["desc"].lower().startswith("hourly"):
            is_imp = True
        if is_imp:
            selected.append(e)
            if len(selected) >= depth:
                break
    # If not enough important entries found, fill remaining slots with newest snapshots
    if len(selected) < depth:
        for e in entries:
            if e not in selected:
                selected.append(e)
                if len(selected) >= depth:
                    break
else: # "recent" sequence
    selected = entries[:depth]

# Ensure output is sorted descending by snapshot number
selected.sort(key=lambda x: x["num"], reverse=True)

for e in selected:
    print(e["path"])
PYSNAP
}

sync_snapper_snapshots_to_limine() {
    validate_privileges
    log_info "Synchronizing Btrfs Snapper snapshots into Limine bootloader..."
    generate_limine_configuration
    enroll_and_sign_limine
    log_success "Snapper snapshots successfully synchronized with Limine."
    return 0
}

manage_snapper_sync_interactive() {
    validate_privileges

    while true; do
        clear 2>/dev/null || echo ""
        local auto_sync
        auto_sync=$(get_snapper_sync_config "ENABLE_AUTO_SNAPPER_SYNC" "no")
        local policy
        policy=$(get_snapper_sync_config "SNAPPER_BOOT_POLICY" "daily_spread")
        local depth
        depth=$(get_snapper_sync_config "SNAPPER_BOOT_DEPTH" "5")

        local auto_status="${RED}[DISABLED (Opt-In)]${RESET}"
        if [ "${auto_sync}" = "yes" ] || [ "${auto_sync}" = "true" ] || [ "${auto_sync}" = "1" ]; then
            auto_status="${GREEN}[ACTIVE ✓ (Hourly)]${RESET}"
        fi

        local policy_label="${CYAN}Daily Spread (Past Week)${RESET}"
        if [ "${policy}" = "recent" ]; then
            policy_label="${YELLOW}Recent Sequence (Latest N)${RESET}"
        elif [ "${policy}" = "important" ]; then
            policy_label="${MAGENTA}Important / Manual Only${RESET}"
        fi

        local snap_dirs=("/.snapshots" "/@snapshots" "/mnt/@snapshots")
        local found_snap_dir=""
        for sd in "${snap_dirs[@]}"; do
            if sudo test -d "${sd}"; then
                found_snap_dir="${sd}"
                break
            fi
        done

        local total_snaps="0"
        if [ -n "${found_snap_dir}" ]; then
            total_snaps=$(sudo find "${found_snap_dir}" -maxdepth 1 -mindepth 1 -type d -name "[0-9]*" 2>/dev/null | wc -l || echo "0")
        fi

        echo -e "${CYAN}============================================================${RESET}"
        echo -e "${YELLOW}${BOLD}🌲 BTRFS SNAPPER BOOT SYNCHRONIZATION HUB 🌲${RESET}"
        echo -e "${CYAN}============================================================${RESET}"
        echo -e "  • ${BOLD}Automatic Background Sync:${RESET}  ${auto_status}"
        echo -e "  • ${BOLD}Snapshot Selection Policy:${RESET}  ${policy_label}"
        echo -e "  • ${BOLD}Max Snapshots in Boot Menu:${RESET} ${GREEN}${depth} entries${RESET}"
        echo -e "  • ${BOLD}Snapper Directory:${RESET}          ${found_snap_dir:-None (Non-Btrfs)}"
        echo -e "  • ${BOLD}Total Available Snapshots:${RESET}  ${total_snaps}"
        echo ""
        echo -e "  \033[1;33m1.\033[0m Toggle Automatic Background Sync (Enable / Disable)"
        echo -e "  \033[1;33m2.\033[0m Change Snapshot Selection Policy (Daily Spread / Recent / Important)"
        echo -e "  \033[1;33m3.\033[0m Set Number of Snapshots in Menu (3, 5, 7, 10 entries)"
        echo -e "  \033[1;33m4.\033[0m Synchronize Boot Menu Now (Regenerate limine.conf & enroll BLAKE2B)"
        echo -e "  \033[1;33m5.\033[0m Return to Limine Menu"
        echo ""
        echo -n "Select operation [1-5]: "
        local snap_choice
        read -r snap_choice || snap_choice="5"

        case "${snap_choice}" in
            1)
                echo ""
                if [ "${auto_sync}" = "yes" ] || [ "${auto_sync}" = "true" ] || [ "${auto_sync}" = "1" ]; then
                    set_snapper_sync_config "ENABLE_AUTO_SNAPPER_SYNC" "no"
                    log_warn "$(_ SNAPPER_DISABLED_MSG)"
                else
                    set_snapper_sync_config "ENABLE_AUTO_SNAPPER_SYNC" "yes"
                    log_success "$(_ SNAPPER_ENABLED_MSG)"
                fi
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            2)
                echo ""
                echo -e "Select Snapshot Retention Policy:"
                echo -e "  \033[1;33m1.\033[0m Daily Spread (1 snapshot per distinct day across the past week - Recommended)"
                echo -e "  \033[1;33m2.\033[0m Recent Sequence (The N most recent sequential snapshots)"
                echo -e "  \033[1;33m3.\033[0m Important / Manual Only (Milestones and pre/post upgrade snapshots)"
                echo ""
                echo -n "Enter policy [1-3]: "
                local pol_c
                read -r pol_c || pol_c="1"
                case "${pol_c}" in
                    1) set_snapper_sync_config "SNAPPER_BOOT_POLICY" "daily_spread" ;;
                    2) set_snapper_sync_config "SNAPPER_BOOT_POLICY" "recent" ;;
                    3) set_snapper_sync_config "SNAPPER_BOOT_POLICY" "important" ;;
                    *) log_warn "Invalid selection. Keeping existing policy." ;;
                esac
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            3)
                echo ""
                echo -e "Select Max Number of Snapshots to Include in Bootloader:"
                echo -e "  \033[1;33m1.\033[0m 3 entries"
                echo -e "  \033[1;33m2.\033[0m 5 entries (Default)"
                echo -e "  \033[1;33m3.\033[0m 7 entries (Full 1-week daily spread)"
                echo -e "  \033[1;33m4.\033[0m 10 entries"
                echo ""
                echo -n "Enter depth [1-4]: "
                local dep_c
                read -r dep_c || dep_c="2"
                case "${dep_c}" in
                    1) set_snapper_sync_config "SNAPPER_BOOT_DEPTH" "3" ;;
                    2) set_snapper_sync_config "SNAPPER_BOOT_DEPTH" "5" ;;
                    3) set_snapper_sync_config "SNAPPER_BOOT_DEPTH" "7" ;;
                    4) set_snapper_sync_config "SNAPPER_BOOT_DEPTH" "10" ;;
                    *) log_warn "Invalid selection. Keeping existing depth." ;;
                esac
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            4)
                echo ""
                log_info "Scanning Snapper snapshots and synchronizing Limine configuration..."
                generate_limine_configuration
                enroll_and_sign_limine
                log_success "Snapper snapshots successfully synchronized with BLAKE2B enrollment and Secure Boot signatures."
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
        echo -e "  \033[1;33m3.\033[0m ⚙️  Configure Kernel Boot Parameters (CMDLINE & Gaming Hub)"
        echo -e "  \033[1;33m4.\033[0m 🌲 Btrfs Snapper Snapshot Sync & Boot Hub (Daily Spread & Retention)"
        echo -e "  \033[1;33m5.\033[0m 1-Click Self-Heal: Restore Limine from Backup"
        echo -e "  \033[1;33m6.\033[0m View / Export Field Guide (PDF / Email / Phone QR)"
        echo -e "  \033[1;33m7.\033[0m Return to Main Menu"
        echo ""
        echo -n "Select operation [1-7]: "
        local lim_choice
        read -r lim_choice || lim_choice="7"

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
                manage_kernel_cmdline_interactive
                ;;
            4)
                manage_snapper_sync_interactive
                ;;
            5)
                echo ""
                restore_limine_self_heal
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            6)
                echo ""
                if command -v manage_field_guide_interactive >/dev/null 2>&1; then
                    manage_field_guide_interactive
                else
                    log_warn "Field guide module not available."
                fi
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
