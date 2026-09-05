#!/usr/bin/env bash
# --- [ SYSTEM CLEANUP & CACHE MAINTENANCE ] ---

set -euo pipefail

purge_old_cachyos_kernels() {
    validate_privileges

    log_info "Auditing installed CachyOS kernels for retention policy (keep 2 newest per flavor)..."

    local remove_list
    remove_list=$(python3 -c "
import os, re
from collections import defaultdict

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
    return 'other'

def parse_ver(v_str):
    return [int(x) for x in re.findall(r'\d+', v_str.split('-cachyos')[0])]

cachy_kernels = set()
if os.path.exists('/boot'):
    for f in os.listdir('/boot'):
        if 'cachyos' in f and f.startswith('vmlinuz-') and not os.path.islink(os.path.join('/boot', f)):
            cachy_kernels.add(f.replace('vmlinuz-', ''))

if os.path.exists('/lib/modules'):
    for d in os.listdir('/lib/modules'):
        if 'cachyos' in d:
            cachy_kernels.add(d)

active = os.uname().release
by_flavor = defaultdict(list)
for k in cachy_kernels:
    by_flavor[get_flavor(k)].append(k)

to_keep = set()
if active in cachy_kernels:
    to_keep.add(active)

for flv, klist in by_flavor.items():
    sorted_k = sorted(klist, key=parse_ver, reverse=True)
    to_keep.update(sorted_k[:2])

to_remove = [k for k in cachy_kernels if k not in to_keep]
for k in to_remove:
    print(k)
" 2>/dev/null || true)

    if [ -z "${remove_list}" ]; then
        log_info "No obsolete CachyOS kernels to purge. Retaining installed versions."
        return 0
    fi

    local removed_any=0
    while IFS= read -r kver; do
        [ -n "${kver}" ] || continue
        log_info "Purging obsolete CachyOS kernel: ${kver}..."

        sudo rm -f "/boot/vmlinuz-${kver}" 2>/dev/null || true
        sudo rm -f "/boot/initramfs-${kver}.img" 2>/dev/null || true
        sudo rm -f "/boot/initrd-${kver}.img" 2>/dev/null || true
        sudo rm -f "/boot/initrd-${kver}.gz" 2>/dev/null || true
        sudo rm -rf "/lib/modules/${kver}" 2>/dev/null || true
        sudo rm -rf "/usr/lib/modules/${kver}" 2>/dev/null || true
        sudo rm -rf "/usr/src/linux-headers-${kver}" 2>/dev/null || true

        # Clean DKMS tree if dkms is available
        local dkms_bin
        dkms_bin=$(command -v dkms 2>/dev/null || echo "/usr/sbin/dkms")
        if [ -x "${dkms_bin}" ]; then
            sudo "${dkms_bin}" remove -k "${kver}" --all >/dev/null 2>&1 || true
        fi

        removed_any=1
        log_success "Removed kernel artifacts for: ${kver}"
    done <<< "${remove_list}"

        if [ "${removed_any}" -eq 1 ]; then
        log_info "Updating bootloader after kernel purge..."
        if command -v sync_bootloader_configuration >/dev/null 2>&1; then
            sync_bootloader_configuration "$(uname -r)"
        fi
        log_success "Kernel retention cleanup completed."
    fi
}

purge_old_slackware_kernels() {
    validate_privileges

    log_info "Auditing Slackware stock kernels for retention policy (keep 1 newest)..."

    local remove_list
    remove_list=$(python3 -c "
import os, re

def parse_ver(v_str):
    clean = re.sub(r'^(?:vmlinuz-|linux-|kernel-)?', '', v_str)
    clean = re.sub(r'\.(?:img|gz|old)$', '', clean)
    return [int(x) for x in re.findall(r'\d+', clean)]

slack_kernels = set()
if os.path.exists('/boot'):
    for f in os.listdir('/boot'):
        if f.startswith('vmlinuz-') and 'cachyos' not in f and not os.path.islink(os.path.join('/boot', f)):
            v = f.replace('vmlinuz-', '')
            if v and v != 'generic' and v != 'huge':
                slack_kernels.add(v)

if os.path.exists('/lib/modules'):
    for d in os.listdir('/lib/modules'):
        if 'cachyos' not in d:
            slack_kernels.add(d)

active = os.uname().release
sorted_k = sorted(list(slack_kernels), key=parse_ver, reverse=True)

keep_count = 1
to_keep = set(sorted_k[:keep_count])
if 'cachyos' not in active:
    to_keep.add(active)

to_remove = [k for k in sorted_k if k not in to_keep]
for k in to_remove:
    print(k)
" 2>/dev/null || true)

    local removed_any=0
    if [ -n "${remove_list}" ]; then
        while IFS= read -r kver; do
            [ -n "${kver}" ] || continue
            log_info "Purging obsolete Slackware stock kernel: ${kver}..."

            sudo rm -f "/boot/vmlinuz-${kver}" 2>/dev/null || true
            sudo rm -f "/boot/initramfs-${kver}.img" 2>/dev/null || true
            sudo rm -f "/boot/initramfs-${kver}.img.old" 2>/dev/null || true
            sudo rm -f "/boot/initrd-${kver}.img" 2>/dev/null || true
            sudo rm -f "/boot/initrd-${kver}.gz" 2>/dev/null || true
            sudo rm -rf "/lib/modules/${kver}" 2>/dev/null || true
            sudo rm -rf "/usr/lib/modules/${kver}" 2>/dev/null || true
            sudo rm -rf "/usr/src/linux-${kver}" 2>/dev/null || true

            local dkms_bin
            dkms_bin=$(command -v dkms 2>/dev/null || echo "/usr/sbin/dkms")
            if [ -x "${dkms_bin}" ]; then
                sudo "${dkms_bin}" remove -k "${kver}" --all >/dev/null 2>&1 || true
            fi

            removed_any=1
            log_success "Removed obsolete Slackware kernel artifacts for: ${kver}"
        done <<< "${remove_list}"
    fi

    # Clean legacy mkinitrd images (11MB) and broken symlinks in /boot ONLY if Dracut is active AND verified
    local engine
    engine=$(detect_initramfs_engine 2>/dev/null || echo "mkinitrd")
    if [ "${engine}" = "dracut" ]; then
        for img in /boot/initrd-*.img /boot/initrd-*.gz; do
            [ -f "${img}" ] && [ ! -L "${img}" ] || continue
            local img_kver
            img_kver=$(basename "${img}" | sed -e 's/^initrd-//' -e 's/\.img$//' -e 's/\.gz$//')
            # STRICT CHECK: Only delete mkinitrd image IF a valid, non-empty Dracut initramfs exists for this exact kernel!
            if [ -f "/boot/initramfs-${img_kver}.img" ] && [ -s "/boot/initramfs-${img_kver}.img" ]; then
                log_info "Removing superseded mkinitrd image (replaced by verified Dracut initramfs): ${img}..."
                sudo rm -f "${img}" 2>/dev/null || true
                removed_any=1
            fi
        done

        # Clean orphaned initramfs files (where kernel modules are deleted)
        for img in /boot/initramfs-*.img; do
            [ -f "${img}" ] || continue
            local img_kver
            img_kver=$(basename "${img}" | sed -e 's/^initramfs-//' -e 's/\.img$//')
            if [ ! -d "/lib/modules/${img_kver}" ]; then
                log_info "Removing orphaned initramfs image: ${img}..."
                sudo rm -f "${img}" 2>/dev/null || true
                removed_any=1
            fi
        done

        # Fix/clean broken symlinks in /boot
        for lk in /boot/initrd /boot/initrd-generic.img; do
            if [ -L "${lk}" ] && [ ! -e "${lk}" ]; then
                sudo rm -f "${lk}" 2>/dev/null || true
            fi
        done
    fi

    if [ "${removed_any}" -eq 1 ]; then
        log_info "Updating bootloader after kernel cleanup..."
        if command -v sync_bootloader_configuration >/dev/null 2>&1; then
            sync_bootloader_configuration "$(uname -r)"
        fi
        log_success "Slackware kernel retention cleanup completed."
    fi
}

clean_system_cache_and_orphans() {
    validate_privileges

    log_info "Cleaning package cache and temporary build directories..."
    sudo rm -rf /var/cache/slacky-update/kernel/* 2>/dev/null || true
    sudo rm -f /var/cache/slacky-update/*.tmp 2>/dev/null || true

    if command -v flatpak >/dev/null 2>&1; then
        log_info "Uninstalling unused Flatpak runtimes..."
        flatpak uninstall --unused -y 2>/dev/null || true
    fi

    purge_old_cachyos_kernels
    purge_old_slackware_kernels

    log_success "System cleanup completed."
}
