#!/usr/bin/env bash
# --- [ LIMINE BOOTLOADER & UEFI SECURE BOOT ENGINE ] ---
# Slacky-Update Unified Limine Suite: limine (>=12.x), limine-entry-tool, limine-snapper-sync, sbctl

set -euo pipefail

if ! type resolve_boot_root_cmd >/dev/null 2>&1; then
    for cand in "${SCRIPT_DIR:-}/common.sh" \
                "$(dirname "${BASH_SOURCE[0]}")/common.sh" \
                "/usr/share/slacky-update/lib/common.sh" \
                "/usr/local/lib/slacky-update/common.sh"; do
        if [ -f "${cand}" ]; then
            source "${cand}"
            break
        fi
    done
fi

# --- [ CONSTANTS & ENDPOINTS ] ---
CACHYOS_REPO_BASE="https://mirror.cachyos.org/repo/x86_64/cachyos"
ARCH_EXTRA_REPO_BASE="https://geo.mirror.pkgbuild.com/extra/os/x86_64"

MIN_BOOT_PARTITION_MB=3500

# --- [ DETECT LIMINE INSTALLATION & ESP PATH ] ---
# 6A-120 (LTS B3): the btrfs subvolume path of the snapshot directory, as rootflags=subvol= needs it. Read from the
# mount table, never guessed: /.snapshots is often its own subvolume (@snapshots, the usual snapper layout) and then
# "<root subvol>/.snapshots/N" is only an empty mount point and the entry cannot boot. Prints e.g. "/@snapshots" or
# "/@/.snapshots"; prints nothing (no snapshot entries) when the directory is on another filesystem than /.
ss_snapshot_subvol_base() {
    local snap_dir="$1" line target fsroot src root_src rel
    line=$(findmnt -n -r -o TARGET,FSROOT,SOURCE --target "${snap_dir}" 2>/dev/null | head -n 1) || return 0
    [ -n "${line}" ] || return 0
    read -r target fsroot src <<< "${line}"
    root_src=$(findmnt -n -r -o SOURCE --target / 2>/dev/null | head -n 1)
    # same filesystem as /: compare the device part of SOURCE ("/dev/x[/@sub]")
    [ -n "${root_src}" ] && [ "${src%%\[*}" = "${root_src%%\[*}" ] || return 0
    rel="${snap_dir#"${target%/}"}"
    fsroot="${fsroot%/}${rel}"
    printf '%s\n' "/${fsroot#/}"
}

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

# 6A-122 (LTS boot-fs M7): Limine is managed only on a UEFI boot with the Limine EFI binary on the ESP. BIOS Limine or a
# leftover /etc/default/limine / limine.conf is left alone (enroll needs EFI/limine/limine_x64.efi; without it every run
# ended in "do not reboot", exit 30).
limine_uefi_booted() {
    [ -d /sys/firmware/efi ]
}
# True when a file exists; uses a cached sudo ticket for root-only ESP mounts (umask 0077), never prompts.
limine_path_exists() {
    [ -f "$1" ] && return 0
    [ "$(id -u)" -eq 0 ] && return 1
    sudo -n test -f "$1" 2>/dev/null
}
is_limine_installed() {
    local esp_path
    esp_path=$(detect_limine_esp_path)

    if limine_uefi_booted; then
        if limine_path_exists "${esp_path}/EFI/limine/limine_x64.efi"; then
            echo "true"
            return 0
        fi
        # 6A-122: as a normal user without a sudo ticket a root-only ESP cannot be read. Keep the old config-based answer
        # then (a false "not installed" would skip the reseal after a kernel change).
        if [ "$(id -u)" -ne 0 ] && { [ ! -r "${esp_path}" ] || [ ! -x "${esp_path}" ]; } && ! sudo -n true 2>/dev/null; then
            if [ -f "/etc/default/limine" ] || [ -f "/boot/limine.conf" ]; then
                echo "true"
                return 0
            fi
        fi
    fi

    echo "false"
    return 1
}
# 6A-122: one plain line, once per run, when Limine files exist that slacky-update does not manage
SLACKY_LIMINE_UNMANAGED_SHOWN="${SLACKY_LIMINE_UNMANAGED_SHOWN:-0}"
limine_unmanaged_notice() {
    [ "${SLACKY_LIMINE_UNMANAGED_SHOWN}" = "1" ] && return 0
    if [ -f "/etc/default/limine" ] || [ -f "/boot/limine.conf" ] || [ -d "/usr/share/limine" ]; then
        SLACKY_LIMINE_UNMANAGED_SHOWN=1
        log_warn "Limine on this computer is not managed by slacky-update (it needs a UEFI start and the Limine EFI file), so its menu was left unchanged."
    fi
    return 0
}
# 6A-123 (LTS boot M11): true when an EFI file is a Limine binary (it carries Limine's config-hash marker)
limine_efi_is_limine() {
    sudo grep -a -q -F '++CONFIG_B2SUM_SIGNATURE++' "$1" 2>/dev/null
}
# 6A-123: the UEFI fallback loader is ours to replace or sign only when it is already Limine (shim, GRUB or another
# system's loader is left alone, logged once)
SLACKY_FALLBACK_EFI_NOTE_SHOWN="${SLACKY_FALLBACK_EFI_NOTE_SHOWN:-0}"
limine_fallback_efi_is_ours() {
    local f="$1"
    sudo test -f "${f}" || return 1
    limine_efi_is_limine "${f}" && return 0
    if [ "${SLACKY_FALLBACK_EFI_NOTE_SHOWN}" != "1" ]; then
        SLACKY_FALLBACK_EFI_NOTE_SHOWN=1
        log_info "The fallback boot file ${f} belongs to another boot loader, so it was left unchanged."
    fi
    return 1
}
# 6A-121 (LTS boot M7): /boot and a separate ESP must be mounted and writable before any boot file is written
limine_boot_paths_ready() {
    local esp_path="${1:-}"
    if command -v ss_boot_ready >/dev/null 2>&1 && ! ss_boot_ready; then
        return 1
    fi
    if [ -n "${esp_path}" ] && [ "${esp_path}" != "/boot" ]; then
        local want opts
        want=$(awk -v m="${esp_path}" '!/^[[:space:]]*#/ && $2==m {print $3; exit}' /etc/fstab 2>/dev/null || true)
        if [ -n "${want}" ]; then
            opts=$(findmnt -n -o OPTIONS --mountpoint "${esp_path}" 2>/dev/null | head -n1 || true)
            [ -n "${opts}" ] || return 1
            case ",${opts}," in *,rw,*) ;; *) return 1 ;; esac
        fi
    fi
    return 0
}
# 6A-121: copy one boot file onto the ESP safely: free-space check, copy to a hidden temp name, compare, then rename.
# An unchanged file is not rewritten. On any failure the old file stays and the function returns 1.
limine_esp_safe_copy() {
    local src="$1" dest="$2"
    local dir="${dest%/*}" base="${dest##*/}"
    local tmp="${dir}/.slacky-${base}.new"
    if sudo test -f "${dest}" && sudo cmp -s "${src}" "${dest}"; then
        return 0
    fi
    local need_kb avail_kb
    need_kb=$(( ( $(sudo stat -c %s "${src}" 2>/dev/null || echo 0) / 1024 ) + 1024 ))
    avail_kb=$(df -Pk "${dir}" 2>/dev/null | awk 'NR==2 {print $4}' || true)
    if [ -z "${avail_kb}" ] || [ "${avail_kb}" -lt "${need_kb}" ] 2>/dev/null; then
        log_error "There is not enough free space on the boot partition for ${base}, so the old file was kept."
        return 1
    fi
    sudo rm -f "${tmp}" 2>/dev/null || true
    if ! sudo cp -f "${src}" "${tmp}"; then
        sudo rm -f "${tmp}" 2>/dev/null || true
        log_error "Copying ${base} to the boot partition failed, so the old file was kept."
        return 1
    fi
    sudo sync -f "${tmp}" 2>/dev/null || sudo sync 2>/dev/null || true
    if ! sudo cmp -s "${src}" "${tmp}" || ! sudo mv -f "${tmp}" "${dest}"; then
        sudo rm -f "${tmp}" 2>/dev/null || true
        log_error "Copying ${base} to the boot partition failed, so the old file was kept."
        return 1
    fi
    return 0
}

# --- [ ENSURE CLEAN MKINITRD STAGING FOR FAT32 /BOOT ] ---
ensure_mkinitrd_staging_configured() {
    local mkconf="/etc/mkinitrd.conf"
    local secure_tree="/var/tmp/slacky-initrd-tree"

    if [ ! -f "${mkconf}" ]; then
        log_info "Configuring ${mkconf} with SOURCE_TREE=\"${secure_tree}\" for FAT32 /boot..."
        echo '# Use /var/tmp for staging to support FAT32/ESP /boot staging' | sudo tee "${mkconf}" >/dev/null
        echo "SOURCE_TREE=\"${secure_tree}\"" | sudo tee -a "${mkconf}" >/dev/null
        return 0
    fi

    # Check if SOURCE_TREE is already pointing to /var/tmp or /tmp
    if grep -q "^[[:space:]]*SOURCE_TREE=" "${mkconf}" 2>/dev/null; then
        local curr_tree
        curr_tree=$(grep "^[[:space:]]*SOURCE_TREE=" "${mkconf}" | tail -n 1 | cut -d'=' -f2 | tr -d '"'\'' ' || true)
        if [[ ! "${curr_tree}" =~ ^/var/tmp ]] && [[ ! "${curr_tree}" =~ ^/tmp ]]; then
            log_info "Updating ${mkconf}: changing staging directory from '${curr_tree}' to '${secure_tree}'..."
            sudo sed -i "s|^[[:space:]]*SOURCE_TREE=.*|SOURCE_TREE=\"${secure_tree}\"|" "${mkconf}"
        elif [ "${curr_tree}" = "/tmp/initrd-tree" ]; then
            log_info "Hardening ${mkconf}: migrating staging directory from '/tmp/initrd-tree' to '${secure_tree}'..."
            sudo sed -i "s|^[[:space:]]*SOURCE_TREE=.*|SOURCE_TREE=\"${secure_tree}\"|" "${mkconf}"
        fi
    else
        log_info "Adding SOURCE_TREE=\"${secure_tree}\" to ${mkconf} for FAT32 /boot support..."
        echo -e "\n# Use /var/tmp for staging to support FAT32/ESP /boot staging\nSOURCE_TREE=\"${secure_tree}\"" | sudo tee -a "${mkconf}" >/dev/null
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

        # 6A-45: never offer a partition that is in use or holds anything but FAT. Mounted partitions, other systems'
        # roots (ext4/btrfs/xfs), Windows (ntfs), encrypted volumes, LVM and swap are never candidates: only an
        # unmounted FAT partition or an empty one (no filesystem at all) can become the new /boot.
        [ -n "${MOUNTPOINT}" ] && continue
        case "${FSTYPE}" in
            ""|vfat) ;;
            *) continue ;;
        esac

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
    if [[ "${target_dev}" =~ (/dev/(nvme[0-9]+n[0-9]+|mmcblk[0-9]+|nbd[0-9]+))p([0-9]+) ]]; then
        parent_disk="${BASH_REMATCH[1]}"
        part_num="${BASH_REMATCH[3]}"
    elif [[ "${target_dev}" =~ (/dev/[a-z]+)([0-9]+) ]]; then
        parent_disk="${BASH_REMATCH[1]}"
        part_num="${BASH_REMATCH[2]}"
    fi

    # 2. Check if already FAT32 or needs formatting
    # 6A-124 (LTS boot M5): the empty-partition check comes first; the partition table is changed only afterwards
    local cur_fs
    cur_fs=$(blkid -s TYPE -o value "${target_dev}" 2>/dev/null || true)
    if [ "${cur_fs}" != "vfat" ]; then
        # 6A-45: only an empty partition (no filesystem signature at all) is ever formatted
        if [ -n "${cur_fs}" ] || [ -n "$(sudo blkid -p -o value -s TYPE "${target_dev}" 2>/dev/null)" ]; then
            log_error "${target_dev} holds a ${cur_fs:-known} filesystem, so it was not formatted. Nothing was changed."
            return 1
        fi
        log_info "Formatting ${target_dev} as FAT32 (ESP_BOOT)..."
        sudo mkfs.vfat -F32 -n "ESP_BOOT" "${target_dev}" >/dev/null || { log_error "Formatting ${target_dev} failed. Nothing else was changed."; return 1; }
    else
        log_info "${target_dev} is already formatted as FAT32 (vfat)."
    fi

    # 3. Mark the partition as an EFI System Partition (GPT disks only; sgdisk would turn an MBR disk into GPT)
    if [ -n "${parent_disk}" ] && [ -n "${part_num}" ]; then
        local pttype parttype
        pttype=$(sudo blkid -p -s PTTYPE -o value "${parent_disk}" 2>/dev/null || lsblk -n -d -o PTTYPE "${parent_disk}" 2>/dev/null || true)
        parttype=$(lsblk -n -d -o PARTTYPE "${target_dev}" 2>/dev/null | tr 'A-Z' 'a-z' || true)
        if [ "${parttype}" = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" ]; then
            :
        elif [ "${pttype}" != "gpt" ]; then
            log_warn "${parent_disk} has no GPT partition table, so the partition type of ${target_dev} was not changed."
        else
            log_info "Setting GPT partition type to EFI System Partition (ef00) on ${target_dev}..."
            local retype_ok=0
            if command -v sgdisk >/dev/null 2>&1; then
                sudo sgdisk -t "${part_num}:ef00" "${parent_disk}" >/dev/null 2>&1 && retype_ok=1
            elif command -v parted >/dev/null 2>&1; then
                sudo parted -s "${parent_disk}" set "${part_num}" esp on >/dev/null 2>&1 && retype_ok=1
            fi
            if [ "${retype_ok}" -ne 1 ]; then
                log_error "${target_dev} could not be marked as an EFI System Partition, so /etc/fstab was not changed."
                return 1
            fi
        fi
    fi
    return 0
}

# 6A-45: every top-level boot file copied to the new ESP must be there with the same content before fstab is touched
verify_boot_copy() {
    local src="$1" dst="$2" f bad=0
    for f in "${src}"/*; do
        [ -e "${f}" ] || continue
        case "${f##*/}" in efi|EFI|lost+found) continue ;; esac
        if [ -f "${f}" ]; then
            sudo cmp -s "${f}" "${dst}/${f##*/}" || { log_error "Copy check failed for ${f##*/}."; bad=1; }
        elif [ -d "${f}" ] && [ ! -L "${f}" ]; then
            sudo diff -rq "${f}" "${dst}/${f##*/}" >/dev/null 2>&1 || { log_error "Copy check failed for ${f##*/}/."; bad=1; }
        fi
    done
    return "${bad}"
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
    # 6A-124: stop when provisioning fails (the result was ignored before)
    provision_esp_partition_type_and_fs "${esp_dev}" || return 1
    # 6A-124: the ESP must still be mounted read-write on /boot/efi before anything is copied onto it
    local efi_opts
    efi_opts=$(findmnt -n -o OPTIONS --mountpoint /boot/efi 2>/dev/null | head -n1 || true)
    case ",${efi_opts}," in
        *,rw,*) ;;
        *) log_error "/boot/efi is not mounted read-write, so nothing was copied and /etc/fstab was not changed."; return 1 ;;
    esac

    local ts
    ts=$(date +%Y%m%d_%H%M%S)
    sudo cp -f /etc/fstab "/etc/fstab.bak.${ts}"
    log_info "Created backup: /etc/fstab.bak.${ts}"

    log_info "Copying system boot files (/boot/*) to ESP..."
    sudo find /boot -maxdepth 1 ! -name 'efi' ! -name 'EFI' ! -path '/boot' -exec cp -a {} /boot/efi/ \; 2>/dev/null || true
    if ! verify_boot_copy /boot /boot/efi; then
        log_error "The boot files did not copy completely to the ESP, so /etc/fstab was not changed. Nothing else was changed."
        return 1
    fi

    log_info "Updating /etc/fstab mountpoint from /boot/efi to /boot..."
    sudo sed -i -E "s|([[:space:]]+)/boot/efi([[:space:]]+vfat)|\1/boot\2|g" /etc/fstab

    ensure_mkinitrd_staging_configured

    log_info "Remounting ESP partition directly on /boot..."
    sudo umount /boot/efi 2>/dev/null || true
    sudo mount /boot 2>/dev/null || sudo mount -t vfat -o defaults,noatime,umask=0077 "${esp_dev}" /boot || true

    if [ "$(findmnt -n -o FSTYPE --mountpoint /boot 2>/dev/null | head -n1)" = "vfat" ]; then
        log_success "Scenario A complete: /boot is now actively mounted on ESP (${esp_dev})."
        return 0
    else
        # 6A-124: a failed mount must not leave the edited fstab behind; restore it and put the ESP back on /boot/efi
        sudo cp -f "/etc/fstab.bak.${ts}" /etc/fstab 2>/dev/null || true
        sudo mount /boot/efi 2>/dev/null || true
        log_error "The boot partition could not be mounted on /boot, so the previous /etc/fstab was restored."
        return 1
    fi
}

# --- [ SCENARIO C: NEW DEDICATED ESP PARTITION ADOPTION ] ---
migrate_to_new_esp_partition() {
    local target_dev="$1"
    validate_privileges
    log_info "Initiating Scenario C: Migrating boot files to new dedicated ESP on ${target_dev}..."

    # 6A-124: stop when provisioning fails (the result was ignored before)
    provision_esp_partition_type_and_fs "${target_dev}" || return 1

    local new_uuid
    new_uuid=$(blkid -s UUID -o value "${target_dev}" 2>/dev/null || true)
    if [ -z "${new_uuid}" ]; then
        log_error "Failed to determine UUID for ${target_dev}."
        return 1
    fi

    local tmp_mnt="/mnt/slacky_new_boot_$$"
    sudo mkdir -p "${tmp_mnt}"
    # 6A-124: an unchecked mount copied the boot files onto the root filesystem and then rewrote fstab. Check the mount
    # and confirm with findmnt that the new partition really is there before copying.
    local mnt_src=""
    if sudo mount -t vfat "${target_dev}" "${tmp_mnt}"; then
        mnt_src=$(findmnt -n -o SOURCE --mountpoint "${tmp_mnt}" 2>/dev/null | head -n1 || true)
    fi
    if [ -z "${mnt_src}" ] || [ "$(readlink -f "${mnt_src}" 2>/dev/null || echo "${mnt_src}")" != "$(readlink -f "${target_dev}" 2>/dev/null || echo "${target_dev}")" ]; then
        log_error "${target_dev} could not be mounted, so nothing was copied and /etc/fstab was not changed."
        [ -n "${mnt_src}" ] && sudo umount "${tmp_mnt}" 2>/dev/null || true
        sudo rmdir "${tmp_mnt}" 2>/dev/null || true
        return 1
    fi

    log_info "Copying kernels, initrds and configs from /boot to new ESP..."
    if [ -d "/boot" ]; then
        sudo find /boot -maxdepth 1 ! -name 'efi' ! -name 'EFI' ! -path '/boot' -exec cp -a {} "${tmp_mnt}/" \; 2>/dev/null || true
    fi
    if ! verify_boot_copy /boot "${tmp_mnt}"; then
        log_error "The boot files did not copy completely to ${target_dev}, so /etc/fstab was not changed."
        sudo umount "${tmp_mnt}" 2>/dev/null || true
        sudo rmdir "${tmp_mnt}" 2>/dev/null || true
        return 1
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
    sudo mount /boot 2>/dev/null || sudo mount -t vfat -o defaults,noatime,umask=0077 "${target_dev}" /boot || true

    if [ "$(findmnt -n -o FSTYPE --mountpoint /boot 2>/dev/null | head -n1)" = "vfat" ]; then
        log_success "Scenario C complete: Dedicated ESP (${target_dev}, UUID=${new_uuid}) is now mounted at /boot."
        return 0
    else
        # 6A-124: restore the previous fstab and mounts instead of leaving a /boot entry that cannot mount
        sudo cp -f "/etc/fstab.bak.${ts}" /etc/fstab 2>/dev/null || true
        sudo mount /boot 2>/dev/null || true
        sudo mount /boot/efi 2>/dev/null || true
        log_error "The new boot partition could not be mounted on /boot, so the previous /etc/fstab was restored."
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
            echo -e "${YELLOW}${BOLD}⚡ $(_ TOPOLOGY_SCENARIO_A_TITLE) ⚡${RESET}"
            echo -e "${CYAN}============================================================${RESET}"
            echo -e "  • ${BOLD}Current State:${RESET} /boot is on system root (${boot_fs:-posix}), and /boot/efi is ${efi_size_mb} MB FAT32."
            echo -e "  • ${BOLD}Recommendation:${RESET} Migrate /boot/efi directly to /boot for optimal Limine & Snapper sync."
            echo ""
            # 6A-124: no answer or closed input means no; the prompt shows [y/N] to match
            local a_prompt
            a_prompt="$(_ TOPOLOGY_SCENARIO_A_PROMPT)"
            echo -n "${a_prompt/\[Y\/n\]/[y/N]}"
            local ans
            read -r ans || ans="n"
            [ -n "${ans}" ] || ans="n"
            if [[ "${ans}" =~ ^[YyJj] ]]; then
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
    echo -e "${YELLOW}${BOLD}⚡ $(_ TOPOLOGY_SCENARIO_C_TITLE) ⚡${RESET}"
    echo -e "${CYAN}============================================================${RESET}"
    echo -e "${YELLOW}Limine multi-kernel staging with Snapper boot sync requires a dedicated FAT32 ESP of at least ${MIN_BOOT_PARTITION_MB} MB (4 GB) on /boot.${RESET}"
    echo -e "Your current ESP is either too small or /boot is on a non-FAT32 filesystem."
    echo ""
    echo -n "$(_ TOPOLOGY_SCENARIO_C_PROMPT)"
    local opt_ans
    # 6A-45: no answer (closed input) means no
    read -r opt_ans || opt_ans="n"
    [ -n "${opt_ans}" ] || opt_ans="n"
    if [[ "${opt_ans}" =~ ^[Nn] ]]; then
        log_warn "Limine setup cancelled. Existing bootloader (GRUB/ELILO) remains completely untouched."
        return 1
    fi

    local raw_cands=()
    mapfile -t raw_cands < <(list_esp_partition_candidates)
    if [ ${#raw_cands[@]} -eq 0 ]; then
        echo ""
        log_error "$(_ TOPOLOGY_NO_CANDIDATES min="${MIN_BOOT_PARTITION_MB}")"
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
    echo -n "$(_ TOPOLOGY_SELECT_PARTITION count="${idx}")"
    local p_choice
    read -r p_choice || p_choice="${idx}"

    if [[ "${p_choice}" =~ ^[0-9]+$ ]] && [ "${p_choice}" -ge 1 ] && [ "${p_choice}" -lt "${idx}" ]; then
        local chosen_dev="${cand_devs[$((p_choice - 1))]}"
        echo ""
        local chosen_fs
        chosen_fs=$(blkid -s TYPE -o value "${chosen_dev}" 2>/dev/null || true)
        local confirm
        if [ "${chosen_fs}" = "vfat" ]; then
            echo -e "${YELLOW}${chosen_dev} is a FAT partition. Its files are kept; the boot files are copied next to them.${RESET}"
            echo -n "Use ${chosen_dev} as /boot? [y/N]: "
            read -r confirm || confirm="n"
        else
            # 6A-45: formatting needs the word ERASE, not just y
            echo -e "${RED}${BOLD}${chosen_dev} will be FORMATTED. Everything on it is erased.${RESET}"
            echo -n "Type ERASE to format ${chosen_dev} and use it as /boot (anything else cancels): "
            read -r confirm || confirm=""
            [ "${confirm}" = "ERASE" ] && confirm="y" || confirm="n"
        fi
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

    log_info "Verifying Unified Limine Suite components..."
    local suite_pkgs=("limine" "limine-entry-tool" "limine-snapper-sync" "sbctl")
    for pkg_id in "${suite_pkgs[@]}"; do
        local cur_ver
        cur_ver=$(get_installed_gaming_pkg_version "${pkg_id}" 2>/dev/null || echo "NONE")
        if [ "${cur_ver}" = "NONE" ] && command -v transmute_and_deploy_gaming_pkg >/dev/null 2>&1; then
            log_info "Deploying missing suite component: ${pkg_id}..."
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
    if [ -x "/usr/bin/limine-enroll-config" ] && [ ! -e "/etc/boot/hooks/post.d/90-limine-enroll-config" ]; then
        sudo ln -sf /usr/bin/limine-enroll-config /etc/boot/hooks/post.d/90-limine-enroll-config 2>/dev/null || true
    fi

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
SNAPPER_BOOT_POLICY=important
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

    local root_res
    root_res=$(resolve_boot_root_cmd 2>/dev/null || echo "ERROR")
    if [ "${root_res}" = "ERROR" ] || [ -z "${root_res}" ]; then
        log_error "FATAL: Root filesystem device or UUID resolution failed! Aborting kernel cmdline synchronization."
        return 1
    fi
    local root_cmd root_flags root_fs root_dev root_uuid
    IFS='|' read -r root_cmd root_flags root_fs root_dev root_uuid <<< "${root_res}"

    if [ -z "${root_cmd}" ] || [ "${root_cmd}" = "root=" ]; then
        log_error "FATAL: Empty or invalid root= parameter resolved! Aborting kernel cmdline synchronization."
        return 1
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

# 6A-121: callers run resolve_and_hash_boot_assets in $( ), so a failed ESP copy is recorded in a file the generator reads
LIMINE_ESP_COPY_FAIL_FILE=""
limine_esp_copy_failed() {
    [ -n "${LIMINE_ESP_COPY_FAIL_FILE}" ] && printf '%s\n' "$1" >> "${LIMINE_ESP_COPY_FAIL_FILE}" 2>/dev/null
    return 0
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
            # 6A-121: temp + compare + rename with a space check (cp -f could leave a truncated kernel that was then sealed)
            if ! limine_esp_safe_copy "${vmlinuz_src}" "${esp_path}/vmlinuz-${kver}"; then
                limine_esp_copy_failed "vmlinuz-${kver}"
                return 1
            fi
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
                if ! limine_esp_safe_copy "${initrd_src}" "${esp_path}/${base_initrd}"; then
                    limine_esp_copy_failed "${base_initrd}"
                    return 1
                fi
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

# 6A-121: kernel versions on a separate ESP whose /boot/vmlinuz-<ver> is gone. Prints nothing when /boot holds no kernel at
# all (an unmounted or empty /boot must never make every ESP kernel look obsolete).
limine_esp_orphan_kernels() {
    local esp_path="$1" esp_f esp_kver
    [ "${esp_path}" != "/boot" ] || return 0
    sudo test -d "${esp_path}" || return 0
    sudo find /boot -maxdepth 1 -type f -name 'vmlinuz-*' 2>/dev/null | grep -q . || return 0
    while IFS= read -r esp_f; do
        [ -n "${esp_f}" ] || continue
        esp_kver="${esp_f##*/vmlinuz-}"
        sudo test -f "/boot/vmlinuz-${esp_kver}" || printf '%s\n' "${esp_kver}"
    done < <(sudo find "${esp_path}" -maxdepth 1 -type f -name 'vmlinuz-*' 2>/dev/null | LC_ALL=C sort)
}
# 6A-121: runs only after the verified commit. Deletes an orphan ESP kernel only when the live limine.conf no longer
# references it.
limine_prune_esp_orphans() {
    local esp_path="$1" k
    limine_boot_paths_ready "${esp_path}" || return 0
    while IFS= read -r k; do
        [ -n "${k}" ] || continue
        if sudo grep -q -F "boot():/vmlinuz-${k}#" "${esp_path}/limine.conf" 2>/dev/null; then
            continue
        fi
        log_info "Pruning obsolete kernel from ESP: vmlinuz-${k}"
        sudo rm -f "${esp_path}/vmlinuz-${k}" "${esp_path}/initramfs-${k}.img"* "${esp_path}/initrd-${k}.gz"* 2>/dev/null || true
    done < <(limine_esp_orphan_kernels "${esp_path}")
    return 0
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
                import hashlib
                hb = hashlib.blake2b()
                with open(full_path, 'rb') as f:
                    while chunk := f.read(65536):
                        hb.update(chunk)
                h = hb.hexdigest().lower()
            except Exception:
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

# --- [ SS-4 ONE MENU WRITER: MENU ORDER + MENU INPUT FINGERPRINT ] ---
# 6A-105/106: snapper's limine-snapper-sync plugin (our curated build) and the kernel post-install hook do not write the
# menu while a slacky-update run holds the run lock, or when the boot lock is busy. They leave this order instead. The
# generator claims it (rename to .taken) under the boot lock; the verified commit in enroll_limine_config_hash clears
# the claim. An order that arrives after the claim keeps its own file and is served by the next holder or the hourly job.
SLACKY_MENU_ORDER="/var/cache/slacky-update/boot-menu-pending"
# 6A-55: fingerprint of what the menu is built from. Shared with cron/slacky-snapper-limine-sync.
SLACKY_MENU_FP_FILE="/var/cache/slacky-update/snapper_limine_fingerprint"
limine_menu_order_claim() {
    if sudo test -f "${SLACKY_MENU_ORDER}"; then
        sudo mv -f "${SLACKY_MENU_ORDER}" "${SLACKY_MENU_ORDER}.taken" 2>/dev/null || true
    fi
    return 0
}
limine_menu_order_done() {
    sudo rm -f "${SLACKY_MENU_ORDER}.taken" 2>/dev/null || true
    return 0
}
# Prints one hash over the inputs that change the menu: snapshot policy + the snapshots it selects, the kernel and
# initramfs files (name, size, time) and /etc/default/limine (command lines). A new timeline snapshot that the policy
# does not select leaves the hash unchanged, so the hourly job does not rewrite and re-sign the boot loader for it.
limine_menu_input_fingerprint() {
    local esp_path snap_dir="" sd root_fs
    esp_path=$(detect_limine_esp_path)
    root_fs=$(findmnt -n -o FSTYPE / 2>/dev/null || true)
    if [ "${root_fs}" = "btrfs" ]; then
        for sd in "/.snapshots" "/@snapshots" "/mnt/@snapshots"; do
            if sudo test -d "${sd}"; then
                snap_dir="${sd}"
                break
            fi
        done
    fi
    {
        echo "fp=1 root_fs=${root_fs} esp=${esp_path}"
        echo "policy=$(get_snapper_sync_config "SNAPPER_BOOT_POLICY" "important") depth=$(get_snapper_sync_config "SNAPPER_BOOT_DEPTH" "5")"
        if [ -n "${snap_dir}" ]; then
            scan_snapper_boot_candidates "${snap_dir}"
        fi
        sudo find /boot "${esp_path}" -maxdepth 1 -type f \( -name 'vmlinuz*' -o -name 'initramfs*' -o -name 'initrd*' \) \
            -printf '%p %s %T@\n' 2>/dev/null | LC_ALL=C sort -u
        sudo cat /etc/default/limine 2>/dev/null || true
    } | b2sum 2>/dev/null | awk '{print $1}'
}
limine_menu_fingerprint_save() {
    local fp
    fp=$(limine_menu_input_fingerprint 2>/dev/null || true)
    [ -n "${fp}" ] || return 0
    printf '%s\n' "${fp}" | sudo tee "${SLACKY_MENU_FP_FILE}" >/dev/null 2>&1 || true
    return 0
}

# --- [ LIMINE CONFIGURATION GENERATOR WITH BLAKE2B HASHING ] ---
generate_limine_configuration() {
    validate_privileges
    # 6A-122: a Limine that slacky-update does not manage (BIOS, or no Limine EFI file) is left alone
    if [ "$(is_limine_installed 2>/dev/null || echo false)" != "true" ]; then
        limine_unmanaged_notice
        return 0
    fi
    # 6A-121 (LTS boot M7): every caller (full run, --sync-boot, --sync-snapper, menus, cron) stops here when /boot or
    # the ESP is not mounted and writable, before anything is written
    if ! limine_boot_paths_ready "$(detect_limine_esp_path)"; then
        log_warn "The boot menu was not changed because the boot partition is not mounted and writable; mount it and try again."
        return 1
    fi
    acquire_boot_lock || return 1
    # SS-4: this generation serves every menu order placed so far (snapshots taken during the run included)
    limine_menu_order_claim
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

    local root_res
    root_res=$(resolve_boot_root_cmd 2>/dev/null || echo "ERROR")
    if [ "${root_res}" = "ERROR" ] || [ -z "${root_res}" ]; then
        log_error "FATAL: Root filesystem device or UUID resolution failed! Aborting Limine configuration."
        return 1
    fi
    local root_cmd root_flags root_fs root_dev root_uuid
    IFS='|' read -r root_cmd root_flags root_fs root_dev root_uuid <<< "${root_res}"

    if [ -z "${root_cmd}" ] || [ "${root_cmd}" = "root=" ]; then
        log_error "FATAL: Empty or invalid root= parameter resolved! Aborting Limine configuration."
        return 1
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

    # 6A-121: ESP kernels whose /boot copy is gone are left out of the new menu here and deleted only after the verified
    # commit (limine_prune_esp_orphans in enroll_limine_config_hash). Deleting them first left the old live menu pointing
    # at missing files whenever the later veto stopped the commit.
    local ss_esp_orphans
    ss_esp_orphans=$(limine_esp_orphan_kernels "${esp_path}" | tr '\n' ' ')

    # Resolve early CPU microcode (Intel / AMD) if present on ESP
    local ucode_name="" ucode_hash=""
    for cand_ucode in "${esp_path}/intel-ucode.cpio" "/boot/intel-ucode.cpio" "${esp_path}/amd-ucode.cpio" "/boot/amd-ucode.cpio"; do
        if sudo test -f "${cand_ucode}"; then
            local base_ucode
            base_ucode=$(basename "${cand_ucode}")
            if [ "${esp_path}" != "/boot" ] && sudo test -f "/boot/${base_ucode}"; then
                # 6A-121: safe copy; a failed copy stops the menu update (the old menu and files stay)
                limine_esp_safe_copy "/boot/${base_ucode}" "${esp_path}/${base_ucode}" || return 1
            fi
            ucode_name="${base_ucode}"
            ucode_hash=$(compute_file_boot_hash "${esp_path}/${base_ucode}")
            log_info "Identified CPU early microcode asset: ${base_ucode} (BLAKE2B: ${ucode_hash:0:12}...)"
            break
        fi
    done

    # 6A-98: keep-set menu. In a commit that removes old kernels afterwards, the menu is built without them, so the live
    # menu never lists a kernel whose files are about to be deleted
    local ss_menu_exclude=""
    if [ "${SS_KEEP_SET_MENU:-0}" = "1" ]; then
        ss_menu_exclude=$(ss_purge_set | tr '\n' ' ')
    fi
    ss_menu_exclude="${ss_menu_exclude} ${ss_esp_orphans}"
    # 6A-121: ESP copies that fail are recorded here; any failure stops the menu update before the live files change
    LIMINE_ESP_COPY_FAIL_FILE=$(mktemp /tmp/slacky-esp-copy.XXXXXX)

    # Analyze all kernels using python3 classifier (Primary vs Fallback separation)
    local kernel_class_json
    kernel_class_json=$(sudo python3 -c "
import os, re, json, sys
excl = set(sys.argv[1].split()) if len(sys.argv) > 1 else set()

def get_flavor_and_label(k):
    if '-cachyos-bore-lto' in k or '-cachyos-lto' in k:
        return ('cachyos-bore-lto', 'Linux Cachyos BORE (LTO)', 50)
    elif '-cachyos-rt-bore' in k or '-cachyos-rt' in k:
        return ('cachyos-rt-bore', 'Linux Cachyos RT (BORE)', 45)
    elif '-cachyos-bore' in k:
        return ('cachyos-bore', 'Linux Cachyos BORE', 40)
    elif '-cachyos-eevdf' in k:
        return ('cachyos-eevdf', 'Linux Cachyos EEVDF', 38)
    elif '-cachyos-bmq' in k:
        return ('cachyos-bmq', 'Linux Cachyos BMQ', 36)
    elif '-zen' in k or k in ('vmlinuz-linux-zen', 'linux-zen'):
        return ('arch-zen', 'Arch Linux Zen', 35)
    elif '-cachyos-deckify' in k:
        return ('cachyos-deckify', 'Linux Cachyos Deckify', 34)
    elif '-cachyos-rc' in k:
        return ('cachyos-rc', 'Linux Cachyos RC', 10)
    elif '-cachyos-lts' in k:
        return ('cachyos-lts', 'Linux Cachyos LTS', 20)
    elif '-cachyos' in k:
        return ('cachyos-standard', 'Linux Cachyos Standard', 30)
    elif '-arch' in k or k in ('vmlinuz-linux', 'linux'):
        return ('arch-standard', 'Arch Linux Standard', 28)
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
found = {k for k in found if k not in excl and not any(k in ('generic-' + v, 'huge-' + v) for v in excl)}

sorted_kernels = sorted(list(found), key=rank, reverse=True)

flavor_seen = {}
primary = []
fallback = []
slackware_kver = None
lts_kver = None

for k in sorted_kernels:
    flv, label, tier = get_flavor_and_label(k)
    if flv == 'slackware' and slackware_kver is None:
        slackware_kver = k
    if flv == 'cachyos-lts' and lts_kver is None:
        lts_kver = k
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
    'slackware': slackware_kver,
    'lts': lts_kver
}))
" "${ss_menu_exclude}" 2>/dev/null || echo '{"primary":[],"fallback":[],"top_primary":null,"slackware":null,"lts":null}')

    local primary_entries=""
    local top_kver="" top_label=""
    local top_vname="" top_khash="" top_iname="" top_ihash=""
    local slack_kver="" slack_label="Slackware Linux"
    local slack_vname="" slack_khash="" slack_iname="" slack_ihash=""
    local lts_kver="" lts_label="Linux Cachyos LTS"
    local lts_vname="" lts_khash="" lts_iname="" lts_ihash=""

    slack_kver=$(echo "${kernel_class_json}" | python3 -c "import sys, json; print(json.load(sys.stdin).get('slackware') or '')" 2>/dev/null || true)
    lts_kver=$(echo "${kernel_class_json}" | python3 -c "import sys, json; print(json.load(sys.stdin).get('lts') or '')" 2>/dev/null || true)

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

    # Ensure Slackware and LTS kernel assets are resolved if not already captured
    if [ -n "${slack_kver}" ] && [ -z "${slack_vname}" ]; then
        local s_info
        s_info=$(resolve_and_hash_boot_assets "${slack_kver}" "${esp_path}" || true)
        if [ -n "${s_info}" ]; then
            IFS='|' read -r slack_vname slack_khash slack_iname slack_ihash <<< "${s_info}"
        fi
    fi
    if [ -n "${lts_kver}" ] && [ -z "${lts_vname}" ]; then
        local l_info
        l_info=$(resolve_and_hash_boot_assets "${lts_kver}" "${esp_path}" || true)
        if [ -n "${l_info}" ]; then
            IFS='|' read -r lts_vname lts_khash lts_iname lts_ihash <<< "${l_info}"
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

        if [ -n "${lts_kver}" ] && [ -n "${lts_vname}" ] && [ "${lts_kver}" != "${top_kver}" ]; then
            local lts_rec_ucode_line=""
            if [ -n "${ucode_name}" ] && [ -n "${ucode_hash}" ] && [[ "${lts_iname}" =~ ^initrd.*\.gz$|^initrd.*generic.*|^initrd.*huge.* ]]; then
                lts_rec_ucode_line="    module_path: boot():/${ucode_name}#${ucode_hash}\n"
            fi
            recovery_entries+="    ///Linux Cachyos LTS (Recovery Mode)\n"
            recovery_entries+="    protocol: linux\n"
            recovery_entries+="    path: boot():/${lts_vname}#${lts_khash}\n"
            if [ -n "${lts_rec_ucode_line}" ]; then
                recovery_entries+="${lts_rec_ucode_line}"
            fi
            recovery_entries+="    module_path: boot():/${lts_iname}#${lts_ihash}\n"
            recovery_entries+="    cmdline: ${recovery_cmdline}\n"
        fi

        if [ -n "${slack_kver}" ] && [ -n "${slack_vname}" ] && [ "${slack_kver}" != "${top_kver}" ] && [ "${slack_kver}" != "${lts_kver}" ]; then
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

        local snap_subvol_base=""
        [ -n "${found_snap_dir}" ] && snap_subvol_base=$(ss_snapshot_subvol_base "${found_snap_dir}")
        if [ -n "${found_snap_dir}" ] && [ -z "${snap_subvol_base}" ]; then
            log_warn "Snapshot boot entries are left out: the snapshot folder could not be matched to the root disk."
            found_snap_dir=""
        fi

        if [ -n "${found_snap_dir}" ]; then
            local snap_list=()
            while IFS= read -r s_id; do
                [ -n "${s_id}" ] && snap_list+=("${s_id}")
            done < <(scan_snapper_boot_candidates "${found_snap_dir}")

            if [ "${#snap_list[@]}" -gt 0 ] && [ -n "${top_kver}" ] && [ -n "${top_vname}" ]; then
                # 6A-96: every kernel this menu knows, newest first (primary, then fallbacks)
                local -a ss_all_kvers=()
                local -A ss_asset_cache=()
                while IFS= read -r c_k; do
                    [ -n "${c_k}" ] && ss_all_kvers+=("${c_k}")
                done < <(echo "${kernel_class_json}" | python3 -c "import sys, json; d=json.load(sys.stdin); seen=[]; [seen.append(x['kver']) for x in d.get('primary', [])+d.get('fallback', []) if x.get('kver') and x['kver'] not in seen]; print('\n'.join(seen))" 2>/dev/null || true)
                local boot_policy
                boot_policy=$(get_snapper_sync_config "SNAPPER_BOOT_POLICY" "important")
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

                    local s_subvol="${snap_subvol_base}/${s_num}/snapshot"

                    local s_cmdline="${root_cmd} rootflags=subvol=${s_subvol} rw ${host_cmdline}"
                    s_cmdline=$(echo "${s_cmdline}" | tr -s ' ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

                    # 6A-96: a snapshot boots only kernels whose modules are inside that snapshot (after a kernel update
                    # the newest kernel has no modules in older snapshots, so its "undo" entry failed exactly when needed).
                    # Up to two matching kernels, newest first; hashes are reused across snapshots.
                    local s_added=0 c_kver c_info c_v c_kh c_i c_ih
                    for c_kver in "${ss_all_kvers[@]}"; do
                        [ "${s_added}" -lt 2 ] || break
                        sudo test -d "${s_path}/snapshot/lib/modules/${c_kver}" || continue
                        c_info="${ss_asset_cache[${c_kver}]:-}"
                        if [ -z "${c_info}" ]; then
                            c_info=$(resolve_and_hash_boot_assets "${c_kver}" "${esp_path}" || true)
                            ss_asset_cache[${c_kver}]="${c_info:--}"
                        fi
                        [ -n "${c_info}" ] && [ "${c_info}" != "-" ] || continue
                        IFS='|' read -r c_v c_kh c_i c_ih <<< "${c_info}"
                        [ "${s_added}" -eq 0 ] && snapshot_entries+="     ///${s_label}\n"
                        snapshot_entries+="     ////Kernel ${c_kver}\n"
                        snapshot_entries+="     protocol: linux\n"
                        snapshot_entries+="     path: boot():/${c_v}#${c_kh}\n"
                        snapshot_entries+="     module_path: boot():/${c_i}#${c_ih}\n"
                        snapshot_entries+="     cmdline: ${s_cmdline}\n"
                        s_added=$((s_added + 1))
                    done
                    if [ "${s_added}" -eq 0 ]; then
                        # no kernel in /boot matches this snapshot: keep the old entry, clearly labelled
                        snapshot_entries+="     ///${s_label} (newer kernel, some drivers may be missing)\n"
                        snapshot_entries+="     ////${top_label}\n"
                        snapshot_entries+="     protocol: linux\n"
                        snapshot_entries+="     path: boot():/${top_vname}#${top_khash}\n"
                        snapshot_entries+="     module_path: boot():/${top_iname}#${top_ihash}\n"
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

    if [ -s "${LIMINE_ESP_COPY_FAIL_FILE}" ]; then
        log_error "Some boot files could not be copied to the boot partition, so the boot menu was not changed."
        rm -f "${LIMINE_ESP_COPY_FAIL_FILE}" 2>/dev/null || true
        LIMINE_ESP_COPY_FAIL_FILE=""
        return 1
    fi
    rm -f "${LIMINE_ESP_COPY_FAIL_FILE}" 2>/dev/null || true
    LIMINE_ESP_COPY_FAIL_FILE=""

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

    # --- [ ZERO-BRICK VETO GUARDRAIL: INTEGRITY SANITY CHECK ] ---
    if grep -E 'cmdline:[[:space:]]*root=([[:space:]]|$)' "${limine_cfg_tmp}" >/dev/null 2>&1; then
        log_error "FATAL: Integrity violation detected in generated Limine config!"
        log_error "Generated configuration contains an empty or invalid 'root=' parameter."
        log_error "Aborting Limine configuration update to protect system bootability."
        rm -f "${limine_cfg_tmp}" 2>/dev/null || true
        return 1
    fi

    if ! grep -q 'cmdline:.*root=' "${limine_cfg_tmp}" 2>/dev/null; then
        log_error "FATAL: Generated Limine configuration contains no valid 'root=' directives! Aborting deployment."
        rm -f "${limine_cfg_tmp}" 2>/dev/null || true
        return 1
    fi

    # Preserve known-good backup before overwriting active configuration
    if sudo test -f "${limine_cfg_file}"; then
        sudo cp -f "${limine_cfg_file}" "${limine_cfg_file}.bak" 2>/dev/null || true
    fi

    # 6A-8d: write next to the target on the ESP, flush, then rename (a crash leaves the old or the new file, never half)
    # 6A-8c: the rename target is limine.conf.next; enroll_and_sign_limine activates it together with the enrolled EFI,
    # so the live limine.conf never differs from the hash inside the live EFI.
    mark_boot_reseal_pending
    local limine_cfg_stage="${limine_cfg_file}.new.$$"
    local stage_ok=1
    { sudo cp -f "${limine_cfg_tmp}" "${limine_cfg_stage}" && sudo chmod 644 "${limine_cfg_stage}"; } || stage_ok=0
    if [ "${stage_ok}" -eq 0 ]; then
        sudo rm -f "${limine_cfg_stage}" "${limine_cfg_tmp}" 2>/dev/null || true
        log_error "Could not stage the new Limine configuration. The current one is unchanged."
        return 1
    fi
    sudo sync -f "${limine_cfg_stage}" 2>/dev/null || sudo sync 2>/dev/null || true
    if ! sudo mv -f "${limine_cfg_stage}" "${limine_cfg_file}.next"; then
        sudo rm -f "${limine_cfg_stage}" "${limine_cfg_tmp}" 2>/dev/null || true
        log_error "Could not prepare the new Limine configuration. The current one is unchanged."
        return 1
    fi
    sudo sync 2>/dev/null || true
    sudo rm -f "${limine_cfg_tmp}" 2>/dev/null || true

    return 0
}

# --- [ CONFIG ENROLLMENT & SBCTL SIGNING ] ---
# 6A-157 (C29, spec 6.1): /var/lib/slacky-boot/limine-committed = one JSON line {v,txid,app,ts,blake2b,sha256} of the exact
# limine.conf bytes that are live after a verified commit. Temp file + rename in the same dir, root:root 0644, never in /boot.
SLACKY_LIMINE_COMMITTED="/var/lib/slacky-boot/limine-committed"
limine_write_committed_record() {
    local conf="$1" dir tmp b2 s256 now txid
    dir="$(dirname "${SLACKY_LIMINE_COMMITTED}")"
    b2=$(sudo b2sum "${conf}" 2>/dev/null | awk '{print $1}')
    s256=$(sudo sha256sum "${conf}" 2>/dev/null | awk '{print $1}')
    case "${b2}" in ''|*[!0-9a-f]*) return 1 ;; esac
    case "${s256}" in ''|*[!0-9a-f]*) return 1 ;; esac
    [ "${#b2}" -eq 128 ] && [ "${#s256}" -eq 64 ] || return 1
    now=$(date +%s)
    txid="${SLACKY_TXID:-legacy-${now}-$$}"
    sudo install -d -m 0755 -o root -g root "${dir}" 2>/dev/null || return 1
    [ ! -L "${dir}" ] || return 1
    tmp="${SLACKY_LIMINE_COMMITTED}.tmp.$$"
    printf '{"v":1,"txid":"%s","app":"slacky-update","ts":%s,"blake2b":"%s","sha256":"%s"}\n' "${txid}" "${now}" "${b2}" "${s256}" \
        | sudo tee "${tmp}" >/dev/null 2>&1 || { sudo rm -f "${tmp}" 2>/dev/null; return 1; }
    if ! { sudo chown root:root "${tmp}" && sudo chmod 0644 "${tmp}" && sudo mv -f "${tmp}" "${SLACKY_LIMINE_COMMITTED}"; } 2>/dev/null; then
        sudo rm -f "${tmp}" 2>/dev/null || true
        return 1
    fi
    return 0
}

enroll_limine_config_hash() {
    validate_privileges

    local esp_path
    esp_path=$(detect_limine_esp_path)
    # 6A-122: never touch a Limine that slacky-update does not manage
    if [ "$(is_limine_installed 2>/dev/null || echo false)" != "true" ]; then
        limine_unmanaged_notice
        return 0
    fi
    # 6A-121: nothing is committed onto an unmounted or read-only boot partition
    if ! limine_boot_paths_ready "${esp_path}"; then
        log_warn "The boot loader was not changed because the boot partition is not mounted and writable; mount it and try again."
        return 1
    fi
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

    # 6A-8a: build the new EFI in a STAGING copy on the ESP. The live EFIs are replaced only after the copy
    # is enrolled and, when sbctl keys exist, signed and verified. Before, both live EFIs were first reset
    # to the clean UNSIGNED binary; a failed enroll only warned and a failed `sbctl sign` was swallowed,
    # which left Limine unsigned (firmware refuses it with Secure Boot on).
    local limine_clean_src=""
    for cand in "/usr/share/limine/BOOTX64.EFI" "/usr/share/limine/x86_64/BOOTX64.EFI" "/usr/lib/limine/BOOTX64.EFI"; do
        if [ -f "${cand}" ]; then
            limine_clean_src="${cand}"
            break
        fi
    done

    local stage_dir="${esp_path}/EFI/limine/.stage-$$"
    sudo rm -rf "${stage_dir}" 2>/dev/null || true
    sudo mkdir -p "${stage_dir}"

    if [ -n "${limine_clean_src}" ]; then
        sudo cp -f "${limine_clean_src}" "${stage_dir}/clean.efi"
        # Keep the clean-binary fallback archive as before
        local clean_bak_tmp
        clean_bak_tmp=$(mktemp -d /tmp/limine-bak.XXXXXX)
        cp -f "${limine_clean_src}" "${clean_bak_tmp}/limine_x64.efi"
        sudo tar --owner=0 --group=0 -cf "${esp_path}/EFI/limine/limine_x64.bak" -C "${clean_bak_tmp}" "limine_x64.efi" 2>/dev/null || true
        rm -rf "${clean_bak_tmp}" 2>/dev/null || true
    elif sudo test -f "${esp_path}/EFI/limine/limine_x64.bak"; then
        sudo tar -xf "${esp_path}/EFI/limine/limine_x64.bak" --directory="${stage_dir}" 2>/dev/null || true
        sudo mv -f "${stage_dir}/limine_x64.efi" "${stage_dir}/clean.efi" 2>/dev/null || true
    fi
    if ! sudo test -f "${stage_dir}/clean.efi"; then
        log_error "Clean Limine EFI binary not found. The boot loader was left unchanged."
        sudo rm -rf "${stage_dir}" 2>/dev/null || true
        return 1
    fi

    local limine_cli
    limine_cli=$(command -v limine 2>/dev/null || echo "/usr/bin/limine")
    # 6A-8c: a freshly generated configuration waits in limine.conf.next and goes live together with this EFI
    local cfg_src="${cfg_file}"
    sudo test -f "${cfg_file}.next" && cfg_src="${cfg_file}.next"
    local cfg_hash
    cfg_hash=$(sudo b2sum "${cfg_src}" 2>/dev/null | awk '{print $1}')
    if [ ! -x "${limine_cli}" ] || [ -z "${cfg_hash}" ]; then
        log_error "limine tool or limine.conf hash unavailable. The boot loader was left unchanged."
        sudo rm -rf "${stage_dir}" 2>/dev/null || true
        return 1
    fi

    local sign_needed=0
    is_sbctl_keys_configured && sign_needed=1
    local sbctl_bin
    sbctl_bin=$(command -v sbctl 2>/dev/null || echo "/usr/bin/sbctl")

    local targets=("${target_efi}")
    # 6A-123 (LTS boot M11): the UEFI fallback is replaced only when it is already Limine (never shim, GRUB or Windows)
    if limine_fallback_efi_is_ours "${esp_path}/EFI/BOOT/BOOTX64.EFI"; then
        targets+=("${esp_path}/EFI/BOOT/BOOTX64.EFI")
    fi

    log_info "Enrolling BLAKE2B configuration digest into Limine EFI bootloader..."
    local idx=0 tgt staged
    for tgt in "${targets[@]}"; do
        staged="${stage_dir}/efi${idx}.efi"
        idx=$((idx + 1))
        sudo cp -f "${stage_dir}/clean.efi" "${staged}"
        if ! sudo "${limine_cli}" enroll-config "${staged}" "${cfg_hash}" >/dev/null 2>&1; then
            log_error "limine enroll-config failed for $(basename "${tgt}"). The boot loader was left unchanged."
            sudo rm -rf "${stage_dir}" "${cfg_file}.next" 2>/dev/null || true
            return 1
        fi
        if [ "${sign_needed}" -eq 1 ]; then
            if ! sudo "${sbctl_bin}" sign "${staged}" >/dev/null 2>&1 || ! limine_efi_signature_ok "${staged}"; then
                log_error "Signing the new Limine EFI failed for $(basename "${tgt}"). The boot loader was left unchanged."
                sudo rm -rf "${stage_dir}" "${cfg_file}.next" 2>/dev/null || true
                return 1
            fi
        fi
    done

    # 6A-8c: commit conf + EFI as one pair. Keep the current (matching) pair as .prev, flush the staged files, then rename
    # them in back to back with hang-up/interrupt/terminate held off, so closing the terminal cannot split the pair.
    # Any failed rename rolls the whole pair back from .prev. Same filesystem, so mv is a rename.
    local old_traps
    old_traps="$(trap -p HUP INT TERM)"
    trap '' HUP INT TERM
    local commit_ok=1 moved=()
    sudo cp -f "${cfg_file}" "${cfg_file}.prev" 2>/dev/null || commit_ok=0
    for tgt in "${targets[@]}"; do
        sudo cp -f "${tgt}" "${tgt}.prev" 2>/dev/null || commit_ok=0
    done
    sudo sync 2>/dev/null || true
    if [ "${commit_ok}" -eq 1 ] && [ "${cfg_src}" != "${cfg_file}" ]; then
        if sudo mv -f "${cfg_src}" "${cfg_file}"; then moved+=("${cfg_file}"); else commit_ok=0; fi
    fi
    idx=0
    for tgt in "${targets[@]}"; do
        staged="${stage_dir}/efi${idx}.efi"
        idx=$((idx + 1))
        [ "${commit_ok}" -eq 1 ] || break
        if sudo mv -f "${staged}" "${tgt}"; then moved+=("${tgt}"); else commit_ok=0; fi
    done
    if [ "${commit_ok}" -ne 1 ]; then
        local m
        for m in "${moved[@]}"; do
            sudo cp -f "${m}.prev" "${m}" 2>/dev/null || true
        done
        sudo sync 2>/dev/null || true
        sudo rm -rf "${stage_dir}" "${cfg_file}.next" 2>/dev/null || true
        trap - HUP INT TERM; eval "${old_traps}"
        log_error "Could not install the new Limine boot files. The previous configuration and boot loader were restored."
        return 1
    fi
    sudo sync 2>/dev/null || true
    trap - HUP INT TERM; eval "${old_traps}"
    sudo rm -rf "${stage_dir}" 2>/dev/null || true
    # 6A-157 (C29): record what was committed BEFORE the reseal marker goes away (shared spec 6.1); a failure only warns
    limine_write_committed_record "${cfg_file}" || log_warn "Could not write the boot menu record; the hourly check cannot compare the menu until the next update."
    clear_boot_reseal_pending
    # SS-4: the claimed menu order is served; record what this menu was built from (6A-55 hourly check)
    limine_menu_order_done
    limine_menu_fingerprint_save
    # 6A-121: obsolete ESP kernels are removed only now, after the new menu is live and no longer lists them
    limine_prune_esp_orphans "${esp_path}"

    # Also keep a mirror at /boot/limine.conf if /boot != esp_path
    if [ "${esp_path}" != "/boot" ] && [ -d "/boot" ]; then
        sudo cp -f "${cfg_file}" "/boot/limine.conf" 2>/dev/null || true
    fi
    return 0
}

# --- [ SBCTL KEYS DETECTION HELPER ] ---
is_sbctl_keys_configured() {
    local sbctl_bin
    sbctl_bin=$(command -v sbctl 2>/dev/null || echo "/usr/bin/sbctl")
    [ -x "${sbctl_bin}" ] || return 1

    if sudo "${sbctl_bin}" status 2>/dev/null | grep -qi "Installed:.*✓\|installed.*true"; then
        return 0
    fi
    for kdir in "/var/lib/sbctl/keys/db" "/usr/share/secureboot/keys/db"; do
        if sudo test -f "${kdir}/db.key" && { sudo test -f "${kdir}/db.pem" || sudo test -f "${kdir}/db.crt"; }; then
            return 0
        fi
    done
    return 1
}

# 6A-8a/6A-8b: true when an EFI file carries a valid signature from the sbctl db key.
# Without sbverify or the db certificate it trusts the sign exit status (returns 0).
limine_efi_signature_ok() {
    local efi="$1" cert=""
    for c in "/var/lib/sbctl/keys/db/db.pem" "/usr/share/secureboot/keys/db/db.pem"; do
        if sudo test -f "${c}"; then cert="${c}"; break; fi
    done
    if [ -z "${cert}" ] || ! command -v sbverify >/dev/null 2>&1; then
        return 0
    fi
    sudo sbverify --cert "${cert}" "${efi}" >/dev/null 2>&1
}

# 6A-8b: silent read-back after a reseal. Returns 0 when every `path#hash` in limine.conf matches its
# file and the live Limine EFI verifies; otherwise prints one plain line and returns 1.
verify_limine_seal() {
    local esp_path
    esp_path=$(detect_limine_esp_path 2>/dev/null || echo "/boot")
    local bad
    bad=$(sudo python3 - "${esp_path}" << 'PYSEAL'
import hashlib, os, re, sys
esp = sys.argv[1]
cfg = os.path.join(esp, "limine.conf")
if not os.path.isfile(cfg):
    print("limine.conf not found"); sys.exit(0)
bad = 0
for line in open(cfg, errors="replace"):
    m = re.match(r"\s*(?:path|kernel_path|module_path|image_path|wallpaper)\s*:\s*boot\(\):/([^#\s]+)#([0-9a-fA-F]{128})\s*$", line)
    if not m:
        continue
    f = os.path.join(esp, m.group(1))
    h = hashlib.blake2b()
    try:
        with open(f, "rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 20), b""):
                h.update(chunk)
    except OSError:
        bad += 1; continue
    if h.hexdigest().lower() != m.group(2).lower():
        bad += 1
if bad:
    print(f"{bad} boot file hash(es) in limine.conf do not match")
PYSEAL
)
    if [ -n "${bad}" ]; then
        log_warn "Limine seal check: ${bad}."
        return 1
    fi
    if is_sbctl_keys_configured && ! limine_efi_signature_ok "${esp_path}/EFI/limine/limine_x64.efi"; then
        log_warn "Limine seal check: the Limine EFI is not validly signed."
        return 1
    fi
    return 0
}

sign_kernel_binaries_sbctl() {
    validate_privileges
    local sbctl_bin
    sbctl_bin=$(command -v sbctl 2>/dev/null || echo "/usr/bin/sbctl")
    if [ ! -x "${sbctl_bin}" ] || ! is_sbctl_keys_configured; then
        log_info "sbctl keys not configured or not installed. Direct UEFI signing skipped."
        return 0
    fi

    # 6A-123 (LTS boot-fs M5): prune only sbctl database entries whose file no longer exists. GRUB, shim, ELILO and UKI
    # entries stay registered (the old whitelist kept only /boot/vmlinuz-* and the Limine EFIs). Written atomically.
    # An unmounted /boot would make every kernel look gone, so nothing is pruned then.
    if sudo test -f "/var/lib/sbctl/files.json" && limine_boot_paths_ready "$(detect_limine_esp_path)"; then
        sudo python3 -c "
import json, os, tempfile

fpath = '/var/lib/sbctl/files.json'
try:
    with open(fpath, 'r', encoding='utf-8') as f:
        data = json.load(f)
    if isinstance(data, dict):
        cleaned = {p: info for p, info in data.items() if os.path.exists(p)}
        if len(cleaned) != len(data):
            fd, tmp = tempfile.mkstemp(dir=os.path.dirname(fpath), prefix='.files.json.')
            with os.fdopen(fd, 'w', encoding='utf-8') as f:
                json.dump(cleaned, f, indent=2)
                f.flush()
                os.fsync(f.fileno())
            os.chmod(tmp, os.stat(fpath).st_mode & 0o777)
            os.replace(tmp, fpath)
except Exception:
    pass
" 2>/dev/null || true
    fi

    local kern_files=()
    local sb_failed=()
    mapfile -t kern_files < <(sudo python3 -c "
import os
if os.path.exists('/boot'):
    for f in sorted(os.listdir('/boot')):
        if f.startswith('vmlinuz-') and not os.path.islink(os.path.join('/boot', f)):
            print(os.path.join('/boot', f))
" 2>/dev/null || true)

    for kern in "${kern_files[@]}"; do
        [ -n "${kern}" ] || continue
        log_info "Signing kernel binary with sbctl: $(basename "${kern}")..."
        sudo "${sbctl_bin}" sign -s "${kern}" >/dev/null 2>&1 || true
        # 6A-44: check the result instead of assuming it (errors were swallowed and reported as signed)
        limine_efi_signature_ok "${kern}" || sb_failed+=("$(basename "${kern}")")
    done

    # 6A-101: no `sbctl sign-all` here. It re-signed the registered live Limine EFIs in place (a FAT write of the only
    # boot loader without staging); the Limine EFI is signed once, as a staged copy, in enroll_limine_config_hash.

    if [ "${#sb_failed[@]}" -gt 0 ]; then
        log_warn "Could not sign ${sb_failed[*]} for Secure Boot."
        return 1
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
    if [ -x "${sbctl_bin}" ] && is_sbctl_keys_configured; then
        if sudo test -f "${target_efi}"; then
            log_info "Signing Limine EFI bootloader with sbctl: ${target_efi}..."
            # -s keeps the file registered in the sbctl database; the copy is usually already signed
            sudo "${sbctl_bin}" sign -s "${target_efi}" >/dev/null 2>&1 || true
            # 6A-8b: report a bad signature instead of swallowing it
            if ! limine_efi_signature_ok "${target_efi}"; then
                log_error "The Limine EFI at ${target_efi} is not validly signed."
                return 1
            fi
        fi
        # 6A-123: sign the fallback only when it is Limine (a shim or GRUB fallback is left alone)
        if limine_fallback_efi_is_ours "${esp_path}/EFI/BOOT/BOOTX64.EFI"; then
            sudo "${sbctl_bin}" sign -s "${esp_path}/EFI/BOOT/BOOTX64.EFI" >/dev/null 2>&1 || true
            if ! limine_efi_signature_ok "${esp_path}/EFI/BOOT/BOOTX64.EFI"; then
                log_error "The fallback EFI at ${esp_path}/EFI/BOOT/BOOTX64.EFI is not validly signed."
                return 1
            fi
        fi
    fi

    # Silent sync to disk to prevent FAT32 corruption
    sync -f "${target_efi}" 2>/dev/null || sync 2>/dev/null || true
    backup_limine_self_heal
    return 0
}

enroll_and_sign_limine() {
    # 6A-122: a Limine that slacky-update does not manage is left alone (no "do not reboot" for it)
    if [ "$(is_limine_installed 2>/dev/null || echo false)" != "true" ]; then
        limine_unmanaged_notice
        return 0
    fi
    # 6A-121: stop before the lock when the boot partition is not mounted and writable
    if ! limine_boot_paths_ready "$(detect_limine_esp_path)"; then
        log_warn "The boot loader was not changed because the boot partition is not mounted and writable; mount it and try again."
        return 1
    fi
    acquire_boot_lock || return 1
    enroll_limine_config_hash || return 1
    if is_sbctl_keys_configured; then
        # 6A-101: the staged EFI was signed and verified before the swap; the live file is only read back here, never
        # re-signed in place (sign_limine_efi_sbctl stays for the interactive menu)
        local esp_v
        esp_v=$(detect_limine_esp_path)
        if ! limine_efi_signature_ok "${esp_v}/EFI/limine/limine_x64.efi"; then
            log_error "The Limine EFI at ${esp_v}/EFI/limine/limine_x64.efi is not validly signed."
            return 1
        fi
        if limine_fallback_efi_is_ours "${esp_v}/EFI/BOOT/BOOTX64.EFI" && ! limine_efi_signature_ok "${esp_v}/EFI/BOOT/BOOTX64.EFI"; then
            log_error "The fallback EFI at ${esp_v}/EFI/BOOT/BOOTX64.EFI is not validly signed."
            return 1
        fi
        backup_limine_self_heal
    else
        log_info "sbctl keys not enrolled. Limine EFI bootloader enrolled without sbctl signature."
    fi
    return 0
}

# --- [ LIMINE SELF-HEAL BACKUP & RESTORE ] ---
backup_limine_self_heal() {
    local esp_path
    esp_path=$(detect_limine_esp_path)
    sudo test -d "${esp_path}/EFI/limine" || return 0

    local current_user="${SUDO_USER:-${USER:-}}"
    local user_home=""
    if [ -n "${current_user}" ]; then
        user_home=$(getent passwd "${current_user}" 2>/dev/null | cut -d: -f6 || true)
        [ -n "${user_home}" ] || user_home=$(eval echo "~${current_user}" 2>/dev/null || true)
    fi
    local user_backup_dir=""
    if [ -n "${user_home}" ] && [ -d "${user_home}" ]; then
        user_backup_dir="${user_home}/.limine_backup"
        mkdir -p "${user_backup_dir}" 2>/dev/null || true
        sudo rsync -a --delete "${esp_path}/EFI/limine/" "${user_backup_dir}/" 2>/dev/null || true
        sudo chown -R "${current_user}:" "${user_backup_dir}" 2>/dev/null || true
        if sudo test -f "${esp_path}/limine.conf"; then
            sudo cp -f "${esp_path}/limine.conf" "${user_backup_dir}/" 2>/dev/null || true
            sudo chown "${current_user}:" "${user_backup_dir}/limine.conf" 2>/dev/null || true
        fi
    fi

    validate_privileges
    local system_backup_dir="/var/cache/slacky-update/limine_backup"
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
    local user_home=""
    if [ -n "${current_user}" ]; then
        user_home=$(getent passwd "${current_user}" 2>/dev/null | cut -d: -f6 || true)
        [ -n "${user_home}" ] || user_home=$(eval echo "~${current_user}" 2>/dev/null || true)
    fi
    local user_backup_dir=""
    [ -n "${user_home}" ] && [ -d "${user_home}" ] && user_backup_dir="${user_home}/.limine_backup"
    local system_backup_dir="/var/cache/slacky-update/limine_backup"

    local src_dir=""
    if [ -d "${system_backup_dir}" ] && [ -f "${system_backup_dir}/limine_x64.efi" ]; then
        src_dir="${system_backup_dir}"
    elif [ -n "${user_backup_dir}" ] && [ -d "${user_backup_dir}" ] && [ -f "${user_backup_dir}/limine_x64.efi" ]; then
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
    # 6A-122: slacky-update manages Limine only on a UEFI start; a BIOS computer keeps its boot loader
    if ! limine_uefi_booted; then
        log_warn "This computer did not start in UEFI mode, so slacky-update cannot install or manage Limine here; nothing was changed."
        return 1
    fi

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
            if [[ "${esp_source}" =~ (/dev/(nvme[0-9]+n[0-9]+|mmcblk[0-9]+|nbd[0-9]+))p([0-9]+) ]]; then
                esp_disk="${BASH_REMATCH[1]}"
                esp_part="${BASH_REMATCH[3]}"
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

    if command -v sign_kernel_binaries_sbctl >/dev/null 2>&1; then
        sign_kernel_binaries_sbctl >/dev/null 2>&1 || true
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

    local root_res
    root_res=$(resolve_boot_root_cmd 2>/dev/null || echo "ERROR")
    if [ "${root_res}" = "ERROR" ] || [ -z "${root_res}" ]; then
        log_error "FATAL: Root filesystem device or UUID resolution failed! Aborting interactive configuration."
        return 1
    fi
    local root_cmd root_flags root_fs root_dev root_uuid
    IFS='|' read -r root_cmd root_flags root_fs root_dev root_uuid <<< "${root_res}"

    if [ -z "${root_cmd}" ] || [ "${root_cmd}" = "root=" ]; then
        log_error "FATAL: Empty or invalid root= parameter resolved! Aborting interactive configuration."
        return 1
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

        local tui_py="${APP_DIR:-}/slacky_tui.py"
        [ ! -f "${tui_py}" ] && [ -f "/usr/share/slacky-update/lib/slacky_tui.py" ] && tui_py="/usr/share/slacky-update/lib/slacky_tui.py"
        [ ! -f "${tui_py}" ] && [ -f "${SCRIPT_DIR:-}/../lib/slacky_tui.py" ] && tui_py="${SCRIPT_DIR:-}/../lib/slacky_tui.py"

        local act_choice=""
        if [ -f "${tui_py}" ] && command -v python3 >/dev/null 2>&1 && [ -t 0 ]; then
            local tui_out
            tui_out=$(python3 "${tui_py}" --mode limine-cmdline --cmdline "${current_custom}")
            tui_out=$(echo "${tui_out}" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            if [[ "${tui_out}" =~ ^SAVE ]]; then
                local sel_indices="${tui_out#SAVE}"
                sel_indices=$(echo "${sel_indices}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
                local new_tokens=()
                for idx in ${sel_indices}; do
                    case "${idx}" in
                        1) new_tokens+=("quiet" "splash" "loglevel=3" "rd.udev.log_priority=3") ;;
                        2) new_tokens+=("nvidia_drm.modeset=1" "nvidia_drm.fbdev=1" "nvidia.NVreg_PreserveVideoMemoryAllocations=1") ;;
                        3) new_tokens+=("amdgpu.ppfeaturemask=0xffffffff") ;;
                        4) new_tokens+=("nowatchdog") ;;
                        5) new_tokens+=("usbcore.autosuspend=-1") ;;
                        6) new_tokens+=("clearcpuid=umip") ;;
                        7) [ -n "${iommu_flag}" ] && new_tokens+=(${iommu_flag}) ;;
                        8) [ "${zram_active}" != "true" ] && new_tokens+=("zswap.enabled=1" "zswap.compressor=zstd" "zswap.max_pool_percent=25") ;;
                        9) new_tokens+=("fsck.mode=skip") ;;
                        10) new_tokens+=("split_lock_mitigate=0" "split_lock_detect=off") ;;
                    esac
                done
                current_custom="${new_tokens[*]:-}"
                act_choice="S"
            elif [ -n "${tui_out}" ]; then
                act_choice=$(echo "${tui_out}" | tr '[:lower:]' '[:upper:]')
            else
                act_choice="Q"
            fi
        else
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

            if [[ " ${current_custom} " =~ [[:space:]]fsck\.mode=skip[[:space:]] ]]; then
                echo -e "  \033[1;32m[x]\033[0m \033[1;33m9.\033[0m Skip Initramfs FSCK          [fsck.mode=skip]"
            else
                echo -e "  \033[1;30m[ ]\033[0m \033[1;33m9.\033[0m Skip Initramfs FSCK          [fsck.mode=skip]"
            fi

            if [[ " ${current_custom} " =~ [[:space:]]split_lock_mitigate=0[[:space:]] ]] || [[ " ${current_custom} " =~ [[:space:]]split_lock_detect=off[[:space:]] ]]; then
                echo -e "  \033[1;32m[x]\033[0m \033[1;33m10.\033[0m Split Lock Protection       [split_lock_mitigate=0 split_lock_detect=off]"
            else
                echo -e "  \033[1;30m[ ]\033[0m \033[1;33m10.\033[0m Split Lock Protection       [split_lock_mitigate=0 split_lock_detect=off]"
            fi

            echo ""
            echo -e "  ${BOLD}Actions:${RESET}"
            echo -e "  \033[1;36m[E]\033[0m ✏️  Edit Raw CMDLINE (Inline readline terminal prompt)"
            echo -e "  \033[1;36m[N]\033[0m 📝  Open in Nano / Text Editor"
            echo -e "  \033[1;36m[R]\033[0m 🔄  Reset to Hardware & Sensible Defaults"
            echo -e "  \033[1;32m[S]\033[0m 💾  Save & Enroll (Rebuild limine.conf, BLAKE2B & Sign EFI)"
            echo -e "  \033[1;31m[Q]\033[0m ↩️  Cancel / Return without saving"
            echo ""
            echo -n "Select option [1-10, E, N, R, S, Q]: "
            read -r act_choice || act_choice="Q"
            act_choice=$(echo "${act_choice}" | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]')
        fi

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
            9)
                current_custom=$(python3 -c "
import sys
cur = sys.argv[1]
tokens = cur.split()
has_fsck = 'fsck.mode=skip' in tokens
if has_fsck:
    new_t = [x for x in tokens if x != 'fsck.mode=skip']
else:
    new_t = tokens + ['fsck.mode=skip']
print(' '.join(new_t))
" "${current_custom}")
                ;;
            10)
                current_custom=$(python3 -c "
import sys
cur = sys.argv[1]
sl_tokens = 'split_lock_mitigate=0 split_lock_detect=off'
tokens = cur.split()
has_sl = any(x in ('split_lock_mitigate=0', 'split_lock_detect=off') for x in tokens)
if has_sl:
    new_t = [x for x in tokens if not x.startswith('split_lock_')]
else:
    new_t = tokens + sl_tokens.split()
print(' '.join(new_t))
" "${current_custom}")
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
    policy=$(get_snapper_sync_config "SNAPPER_BOOT_POLICY" "important")
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
    # 6A-55 (owner 2026-10-13): important snapshots only. Filling up with the newest timeline snapshots made the menu
    # change every hour, so the boot loader was re-hashed and re-signed every hour.
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
        policy=$(get_snapper_sync_config "SNAPPER_BOOT_POLICY" "important")
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
        echo -e "${YELLOW}${BOLD}🌲 $(_ SNAPPER_HUB_TITLE) 🌲${RESET}"
        echo -e "${CYAN}============================================================${RESET}"
        echo -e "  • ${BOLD}$(_ SNAPPER_STATUS_AUTO_SYNC):${RESET}  ${auto_status}"
        echo -e "  • ${BOLD}$(_ SNAPPER_STATUS_POLICY):${RESET}  ${policy_label}"
        echo -e "  • ${BOLD}$(_ SNAPPER_STATUS_DEPTH):${RESET} ${GREEN}${depth} entries${RESET}"
        echo -e "  • ${BOLD}$(_ SNAPPER_STATUS_ROOT):${RESET}          ${found_snap_dir:-None (Non-Btrfs)}"
        echo -e "  • ${BOLD}$(_ SNAPPER_STATUS_TOTAL):${RESET}  ${total_snaps}"
        echo ""
        echo -e "  \033[1;33m$(_ SNAPPER_OPT_TOGGLE_AUTO)\033[0m"
        echo -e "  \033[1;33m$(_ SNAPPER_OPT_CHANGE_POLICY)\033[0m"
        echo -e "  \033[1;33m$(_ SNAPPER_OPT_CHANGE_DEPTH)\033[0m"
        echo -e "  \033[1;33m$(_ SNAPPER_OPT_SYNC_NOW)\033[0m"
        echo -e "  \033[1;33m$(_ SNAPPER_OPT_RETURN)\033[0m"
        echo ""
        echo -n "$(_ SELECT_OPERATION_RANGE range="1-5") "
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
                    1)
                        set_snapper_sync_config "SNAPPER_BOOT_POLICY" "daily_spread"
                        log_info "$(_ SNAPPER_POLICY_SET policy="daily_spread")"
                        ;;
                    2)
                        set_snapper_sync_config "SNAPPER_BOOT_POLICY" "recent"
                        log_info "$(_ SNAPPER_POLICY_SET policy="recent")"
                        ;;
                    3)
                        set_snapper_sync_config "SNAPPER_BOOT_POLICY" "important"
                        log_info "$(_ SNAPPER_POLICY_SET policy="important")"
                        ;;
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
                    1)
                        set_snapper_sync_config "SNAPPER_BOOT_DEPTH" "3"
                        log_info "$(_ SNAPPER_DEPTH_SET depth="3")"
                        ;;
                    2)
                        set_snapper_sync_config "SNAPPER_BOOT_DEPTH" "5"
                        log_info "$(_ SNAPPER_DEPTH_SET depth="5")"
                        ;;
                    3)
                        set_snapper_sync_config "SNAPPER_BOOT_DEPTH" "7"
                        log_info "$(_ SNAPPER_DEPTH_SET depth="7")"
                        ;;
                    4)
                        set_snapper_sync_config "SNAPPER_BOOT_DEPTH" "10"
                        log_info "$(_ SNAPPER_DEPTH_SET depth="10")"
                        ;;
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

# --- [ DYNAMIC KERNEL & LIMINE BLAKE2B HASH VERIFIER ] ---
check_kernel_boot_hashes() {
    validate_privileges
    local esp_path
    esp_path=$(detect_limine_esp_path 2>/dev/null || echo "/boot")

    sudo python3 - "${esp_path}" << 'PYVERIFY'
import os, sys, re, subprocess, shutil

CYAN = '\033[1;36m'
BLUE = '\033[1;34m'
LIGHT_BLUE = '\033[94m'
GREEN = '\033[1;32m'
YELLOW = '\033[1;33m'
RED = '\033[1;31m'
MAGENTA = '\033[1;35m'
BOLD = '\033[1m'
DIM = '\033[2m'
RESET = '\033[0m'

esp_path = sys.argv[1] if len(sys.argv) > 1 else '/boot'
cfg_candidates = [
    os.path.join(esp_path, 'limine.conf'),
    '/boot/limine.conf',
    '/boot/efi/limine.conf',
    '/boot/EFI/limine/limine.conf',
    '/boot/efi/EFI/limine/limine.conf',
    '/boot/limine/limine.conf',
    '/boot/efi/limine/limine.conf',
    '/efi/limine.conf',
    '/efi/EFI/limine/limine.conf',
    '/efi/limine/limine.conf',
    os.path.join(esp_path, 'EFI/limine/limine.conf'),
    os.path.join(esp_path, 'limine/limine.conf')
]

cfg_file = None
for c in cfg_candidates:
    if os.path.exists(c) and os.path.isfile(c):
        cfg_file = c
        break

bar = '=' * 100
div = '-' * 100

print()
print(f'{BOLD}{CYAN}{bar}{RESET}')
print(f'{BOLD}{CYAN}{"⚡ SLACKY-UPDATE DYNAMIC KERNEL & LIMINE HASH VERIFIER ⚡".center(100)}{RESET}')
print(f'{BOLD}{CYAN}{bar}{RESET}')

running_kver = os.uname().release
print(f' {BOLD}Running Kernel:{RESET}   {LIGHT_BLUE}{running_kver}{RESET}')
print(f' {BOLD}Active ESP Path:{RESET}  {BLUE}{esp_path}{RESET}')
if cfg_file:
    print(f' {BOLD}Limine Config:{RESET}    {BLUE}{cfg_file}{RESET}')
else:
    print(f' {BOLD}Limine Config:{RESET}    {RED}NOT FOUND in candidate paths!{RESET}')

sb_status = 'Unknown'
if shutil.which('sbctl'):
    try:
        r = subprocess.run(['sbctl', 'status'], capture_output=True, text=True, timeout=3)
        out_low = r.stdout.lower()
        if 'secure boot: enabled' in out_low or 'secure boot: ✓' in out_low:
            sb_status = f'{GREEN}Enabled (Armed & Enforcing){RESET}'
        elif 'secure boot: disabled' in out_low or 'secure boot: ✗' in out_low:
            sb_status = f'{YELLOW}Disabled (Permissive){RESET}'
        else:
            sb_status = f'{BLUE}Installed{RESET}'
    except Exception:
        pass
print(f' {BOLD}UEFI Secure Boot:{RESET} {sb_status}')
print(f'{BOLD}{CYAN}{div}{RESET}')

if not cfg_file:
    print(f'{RED}✗ Error: Cannot verify hashes because limine.conf could not be found.{RESET}')
    print(f'Run {BOLD}sudo slacky-update --sync-boot{RESET} to generate and register Limine boot configuration.')
    print()
    sys.exit(1)

try:
    with open(cfg_file, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
except Exception as e:
    print(f'{RED}✗ Error reading {cfg_file}: {e}{RESET}')
    sys.exit(1)

primary_kernels = []
fallback_kernels = []
initramfs_entries = {}
splash_entry = None

in_fallback = False
for line in content.splitlines():
    s = line.strip()
    if s.startswith('//Fallback') or (s.startswith('///') and 'fallback' in s.lower()):
        in_fallback = True
    elif s.startswith('//') and not s.startswith('///'):
        if 'fallback' not in s.lower():
            in_fallback = False

    m_wp = re.search(r'^[ \t]*wallpaper:[ \t]*(?:boot\(\):)?/([^\s#\n\r]+)(?:#([a-fA-F0-9]+))?', line)
    if m_wp:
        wp_name = os.path.basename(m_wp.group(1).lstrip('/'))
        wp_hash = (m_wp.group(2) or '').lower().strip()
        splash_entry = (wp_name, wp_hash)
        continue

    m_kern = re.search(r'^[ \t]*(?:path|kernel_path):[ \t]*(?:boot\(\):)?/([^\s#\n\r]+)(?:#([a-fA-F0-9]+))?', line)
    if m_kern:
        k_name = os.path.basename(m_kern.group(1).lstrip('/'))
        k_hash = (m_kern.group(2) or '').lower().strip()
        if k_name.startswith('vmlinuz'):
            if in_fallback or '[fallback]' in line.lower():
                if not any(k[0] == k_name for k in fallback_kernels) and not any(k[0] == k_name for k in primary_kernels):
                    fallback_kernels.append((k_name, k_hash))
            else:
                if not any(k[0] == k_name for k in primary_kernels):
                    primary_kernels.append((k_name, k_hash))
        continue

    m_mod = re.search(r'^[ \t]*module_path:[ \t]*(?:boot\(\):)?/([^\s#\n\r]+)(?:#([a-fA-F0-9]+))?', line)
    if m_mod:
        m_name = os.path.basename(m_mod.group(1).lstrip('/'))
        m_hash = (m_mod.group(2) or '').lower().strip()
        if m_name not in initramfs_entries:
            initramfs_entries[m_name] = m_hash
        continue

scan_dirs = ['/boot']
if esp_path != '/boot' and os.path.exists(esp_path):
    scan_dirs.append(esp_path)

found_files = {}
for sdir in scan_dirs:
    if not os.path.exists(sdir):
        continue
    try:
        for fname in os.listdir(sdir):
            fpath = os.path.join(sdir, fname)
            if os.path.isfile(fpath):
                if fname not in found_files or sdir == esp_path:
                    found_files[fname] = fpath
    except Exception:
        pass

def compute_b2(path):
    if not path or not os.path.exists(path):
        return ''
    try:
        import hashlib
        hb = hashlib.blake2b()
        with open(path, 'rb') as f:
            while chunk := f.read(65536):
                hb.update(chunk)
        return hb.hexdigest().lower()
    except Exception:
        try:
            r = subprocess.run(['b2sum', path], capture_output=True, text=True, timeout=10)
            if r.returncode == 0:
                return r.stdout.strip().split()[0].lower()
        except Exception:
            pass
    return ''

def short_h(h):
    if not h:
        return f'{DIM}None{RESET}'
    if len(h) > 20:
        return f'{h[:10]}...{h[-8:]}'
    return h

active_entry = None
ordered_primaries = []
for k_name, k_hash in primary_kernels:
    if running_kver in k_name and not active_entry:
        active_entry = (k_name, k_hash)
    else:
        ordered_primaries.append((k_name, k_hash))

if not active_entry:
    new_fallbacks = []
    for k_name, k_hash in fallback_kernels:
        if running_kver in k_name and not active_entry:
            active_entry = (k_name, k_hash)
        else:
            new_fallbacks.append((k_name, k_hash))
    fallback_kernels = new_fallbacks

ordered_kernels = []
if active_entry:
    ordered_kernels.append(active_entry)
ordered_kernels.extend(ordered_primaries)
ordered_kernels.extend(fallback_kernels)

print(f' {BOLD}{"COMPONENT / FILE":<34} {"TYPE":<11} {"REGISTERED (LIMINE)":<23} {"ON-DISK (B2SUM)":<23} {"STATUS"}{RESET}')
print(f'{DIM} ' + '-'*98 + f'{RESET}')

all_ok = True
mismatches = 0
total_checked = 0

for k_name, reg_hash in ordered_kernels:
    fpath = found_files.get(k_name)
    actual_hash = compute_b2(fpath) if fpath else ''
    total_checked += 1
    
    is_match = bool(actual_hash and reg_hash and actual_hash == reg_hash)
    if not is_match:
        all_ok = False
        mismatches += 1
    
    raw_name = k_name
    pad = " " * max(0, 34 - len(raw_name))
    disp_name = f"{LIGHT_BLUE}{raw_name}{RESET}{pad}"
    ftype = f'{"Kernel":<11}'
    reg_str = f'{short_h(reg_hash):<23}'
    act_str = f'{short_h(actual_hash):<23}'
    status_str = f'{GREEN}✓ MATCH{RESET}' if is_match else f'{RED}✗ MISMATCH{RESET}'
    print(f' {disp_name} {ftype} {reg_str} {act_str} {status_str}')

init_mismatches = []
init_matches = []
for i_name, reg_hash in initramfs_entries.items():
    fpath = found_files.get(i_name)
    actual_hash = compute_b2(fpath) if fpath else ''
    total_checked += 1
    if actual_hash and reg_hash and actual_hash == reg_hash:
        init_matches.append(i_name)
    else:
        init_mismatches.append((i_name, reg_hash, actual_hash))
        all_ok = False
        mismatches += 1

if not init_mismatches and init_matches:
    raw_name = f"Initramfs Suite ({len(init_matches)} images)"
    pad = " " * max(0, 34 - len(raw_name))
    disp_name = f"{raw_name}{pad}"
    ftype = f'{"Initramfs":<11}'
    val_str = "[BLAKE2B Validated]"
    reg_str = f'{val_str:<23}'
    act_str = f'{val_str:<23}'
    status_str = f'{GREEN}✓ MATCH{RESET}'
    print(f' {disp_name} {ftype} {reg_str} {act_str} {status_str}')
elif init_mismatches:
    for i_name, reg_hash, actual_hash in init_mismatches:
        raw_name = i_name
        pad = " " * max(0, 34 - len(raw_name))
        disp_name = f"{RED}{raw_name}{RESET}{pad}"
        ftype = f'{"Initramfs":<11}'
        reg_str = f'{short_h(reg_hash):<23}'
        act_str = f'{short_h(actual_hash):<23}'
        status_str = f'{RED}✗ MISMATCH{RESET}'
        print(f' {disp_name} {ftype} {reg_str} {act_str} {status_str}')
    if init_matches:
        raw_name = f"Initramfs Suite ({len(init_matches)} images)"
        pad = " " * max(0, 34 - len(raw_name))
        disp_name = f"{raw_name}{pad}"
        ftype = f'{"Initramfs":<11}'
        val_str = "[BLAKE2B Validated]"
        reg_str = f'{val_str:<23}'
        act_str = f'{val_str:<23}'
        status_str = f'{GREEN}✓ MATCH{RESET}'
        print(f' {disp_name} {ftype} {reg_str} {act_str} {status_str}')

if splash_entry:
    wp_name, reg_hash = splash_entry
    fpath = found_files.get(wp_name)
    actual_hash = compute_b2(fpath) if fpath else ''
    total_checked += 1
    is_match = bool(actual_hash and reg_hash and actual_hash == reg_hash)
    if not is_match:
        all_ok = False
        mismatches += 1
    raw_name = wp_name
    pad = " " * max(0, 34 - len(raw_name))
    disp_name = f"{raw_name}{pad}"
    ftype = f'{"Splash":<11}'
    reg_str = f'{short_h(reg_hash):<23}'
    act_str = f'{short_h(actual_hash):<23}'
    status_str = f'{GREEN}✓ MATCH{RESET}' if is_match else f'{RED}✗ MISMATCH{RESET}'
    print(f' {disp_name} {ftype} {reg_str} {act_str} {status_str}')

print(f'{BOLD}{CYAN}{bar}{RESET}')
if all_ok and mismatches == 0 and total_checked > 0:
    print(f' {GREEN}{BOLD}✓ PERFECT INTEGRITY:{RESET} All {total_checked} registered boot assets match their Limine BLAKE2B hashes 1:1.')
    print(f' {DIM}Your bootloader security and kernel sealing are 100% synchronized and stable.{RESET}')
    print(f'{BOLD}{CYAN}{bar}{RESET}')
    print()
    sys.exit(0)
elif mismatches > 0:
    print(f' {RED}{BOLD}✗ INTEGRITY ALERT:{RESET} {mismatches} hash mismatch(es) detected between on-disk files and limine.conf!')
    print(f' {YELLOW}Recommendation:{RESET} Run {BOLD}sudo slacky-update --sync-boot{RESET} to recalculate hashes and reseal.')
    print(f'{BOLD}{CYAN}{bar}{RESET}')
    print()
    sys.exit(1)
else:
    print(f' {YELLOW}{BOLD}⚠️ NOTICE:{RESET} Boot files found, but none are currently registered with hashes in limine.conf.')
    print(f' Run {BOLD}sudo slacky-update --sync-boot{RESET} to enable BLAKE2B boot sealing.')
    print(f'{BOLD}{CYAN}{bar}{RESET}')
    print()
    sys.exit(0)
PYVERIFY
}

# --- [ INTERACTIVE LIMINE MANAGEMENT MENU ] ---
manage_limine_interactive() {
    local tui_py="${APP_DIR:-}/slacky_tui.py"
    [ ! -f "${tui_py}" ] && [ -f "/usr/share/slacky-update/lib/slacky_tui.py" ] && tui_py="/usr/share/slacky-update/lib/slacky_tui.py"
    [ ! -f "${tui_py}" ] && [ -f "${SCRIPT_DIR:-}/../lib/slacky_tui.py" ] && tui_py="${SCRIPT_DIR:-}/../lib/slacky_tui.py"

    while true; do
        local esp_path
        esp_path=$(detect_limine_esp_path)
        local lim_status="[NOT INSTALLED]"
        if [ "$(is_limine_installed)" = "true" ]; then
            lim_status="${GREEN}[INSTALLED & ACTIVE]${RESET}"
        fi

        local lim_choice=""
        if [ -f "${tui_py}" ] && command -v python3 >/dev/null 2>&1 && [ -t 0 ]; then
            lim_choice=$(python3 "${tui_py}" --mode limine-main)
        else
            echo ""
            echo -e "${BLUE}${BOLD}============================================================${RESET}"
            echo -e "${BLUE}${BOLD}LIMINE BOOTLOADER & SECURE BOOT MATRIX${RESET}"
            echo -e "${BLUE}${BOLD}============================================================${RESET}"
            echo -e "  • ${BOLD}Status:${RESET}      ${lim_status}"
            echo -e "  • ${BOLD}ESP Path:${RESET}    ${esp_path}"
            echo ""
            echo -e "  \033[1;33m1.\033[0m Install / Re-deploy Limine Bootloader (Coexistence Mode)"
            echo -e "  \033[1;33m2.\033[0m Regenerate limine.conf & Re-enroll BLAKE2B Checksums"
            echo -e "  \033[1;33m3.\033[0m 🔍 Verify Kernel BLAKE2B Hashes vs Limine Registry"
            echo -e "  \033[1;33m4.\033[0m ⚙️  Configure Kernel Boot Parameters (CMDLINE & Gaming Hub)"
            echo -e "  \033[1;33m5.\033[0m 🌲 $(_ MENU_SNAPPER_HUB)"
            echo -e "  \033[1;33m6.\033[0m 1-Click Self-Heal: Restore Limine from Backup"
            echo -e "  \033[1;33m7.\033[0m View / Export Field Guide (PDF / Email / Phone QR)"
            echo -e "  \033[1;33m8.\033[0m Return to Main Menu"
            echo ""
            echo -n "Select operation [1-8]: "
            read -r lim_choice || lim_choice="8"
        fi

        case "${lim_choice}" in
            1)
                echo ""
                install_limine_bootloader
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            2)
                echo ""
                log_info "Generating /boot/limine.conf & recalculating BLAKE2B checksums..."
                generate_limine_configuration
                log_info "Enrolling BLAKE2B configuration digest & signing bootloader..."
                enroll_and_sign_limine

                local cfg_file=""
                for cand in "${esp_path}/limine.conf" "/boot/limine.conf" "/boot/efi/limine.conf" "${esp_path}/EFI/limine/limine.conf"; do
                    if sudo test -f "${cand}"; then
                        cfg_file="${cand}"
                        break
                    fi
                done
                local k_count=0
                local i_count=0
                if [ -n "${cfg_file}" ] && sudo test -f "${cfg_file}"; then
                    k_count=$(sudo grep -o 'vmlinuz-[^#[:space:]]*' "${cfg_file}" 2>/dev/null | sort -u | wc -l || echo "0")
                    k_count=$(echo "${k_count}" | tr -d '[:space:]')
                    [ -n "${k_count}" ] || k_count=0

                    i_count=$(sudo grep -o -E '(initramfs|initrd)[^#[:space:]]*' "${cfg_file}" 2>/dev/null | sort -u | wc -l || echo "0")
                    i_count=$(echo "${i_count}" | tr -d '[:space:]')
                    [ -n "${i_count}" ] || i_count=0
                fi
                echo ""
                echo -e "${BOLD}${CYAN}========================================================================${RESET}"
                echo -e "${BOLD}${GREEN}✓ LIMINE BOOT MATRIX & BLAKE2B INTEGRITY SEALED:${RESET}"
                echo -e "  • ${BOLD}Registered Kernels :${RESET} ${k_count} kernels mapped (active + fallback entries)"
                echo -e "  • ${BOLD}Initramfs Images   :${RESET} ${i_count} initramfs matched and hash-locked"
                echo -e "  • ${BOLD}Bootloader Binary  :${RESET} Enrolled with BLAKE2B & signed with active MOK/sbctl"
                echo -e "  • ${BOLD}Status             :${RESET} ${GREEN}100% Sealed, Protected & Ready to Boot${RESET}"
                echo -e "${BOLD}${CYAN}========================================================================${RESET}"
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            3)
                echo ""
                check_kernel_boot_hashes
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            4)
                manage_kernel_cmdline_interactive
                ;;
            5)
                manage_snapper_sync_interactive
                ;;
            6)
                echo ""
                restore_limine_self_heal
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            7)
                echo ""
                if command -v manage_field_guide_interactive >/dev/null 2>&1; then
                    manage_field_guide_interactive
                else
                    log_warn "Field guide module not available."
                fi
                ;;
            8)
                return 0
                ;;
            *)
                echo -e "\n${YELLOW}$(_ INVALID_SELECTION)${RESET}"
                sleep 1
                ;;
        esac
    done
}
