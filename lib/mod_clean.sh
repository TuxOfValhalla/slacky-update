#!/usr/bin/env bash
# --- [ SYSTEM CLEANUP & CACHE MAINTENANCE ] ---

set -euo pipefail

purge_old_cachyos_kernels() {
    validate_privileges

    local remove_list
    remove_list=$(get_obsolete_cachyos_kernels 2>/dev/null || true)

    if [ -z "${remove_list}" ]; then
        return 0
    fi

    local removed_any=0
    while IFS= read -r kver; do
        [ -n "${kver}" ] || continue
        # 6A-98: after a commit (SS_KEEP_SET_MENU=1) a kernel the live menu still lists is kept; in the old order
        # (purge, then menu sync) the menu is flagged as stale first, so an interrupted run is repaired
        if ss_live_menu_lists_kernel "${kver}"; then
            if [ "${SS_KEEP_SET_MENU:-0}" = "1" ]; then
                log_warn "Kernel ${kver} was kept for now because the startup menu still lists it."
                continue
            fi
            mark_boot_reseal_pending
        fi
        log_info "Purging obsolete CachyOS kernel: ${kver}..."

        # Remove registered packages in /var/log/packages if present
        # 6A-143: if a removepkg fails, the kernel files are kept (deleting them would orphan the package entry)
        local rm_failed=0
        for pkg in /var/log/packages/*cachyos*${kver}* /var/log/packages/linux-*${kver}*; do
            [ -f "${pkg}" ] || continue
            local p_base
            p_base=$(basename "${pkg}")
            if [[ "${p_base}" =~ ^kernel-headers ]] || [[ "${p_base}" =~ ^kernel-firmware ]]; then
                continue
            fi
            log_info "Removing registered package: ${p_base}..."
            if ! sudo "${PKG_REMOVE_CMD:-removepkg}" "${p_base}" >/dev/null 2>&1; then
                rm_failed=1
            fi
        done
        if [ "${rm_failed}" -eq 1 ]; then
            log_warn "Kernel ${kver} could not be removed cleanly, so its files were kept."
            continue
        fi

        sudo rm -f "/boot/vmlinuz-${kver}" 2>/dev/null || true
        sudo rm -f "/boot/initramfs-${kver}.img" 2>/dev/null || true
        sudo rm -f "/boot/initrd-${kver}.img" 2>/dev/null || true
        sudo rm -f "/boot/initrd-${kver}.gz" 2>/dev/null || true
        sudo rm -rf "/lib/modules/${kver}" 2>/dev/null || true
        sudo rm -rf "/usr/lib/modules/${kver}" 2>/dev/null || true
        sudo rm -rf "/usr/src/linux-headers-${kver}" 2>/dev/null || true

        # Clean DKMS tree (per-module remove + ghost symlink cleanup)
        dkms_purge_kernel "${kver}"

        removed_any=1
        log_success "Removed kernel artifacts for: ${kver}"
    done <<< "${remove_list}"

    local sync_boot="${1:-sync}"
    if [ "${removed_any}" -eq 1 ]; then
        if [ "${sync_boot}" != "--no-sync" ]; then
            log_info "Updating bootloader after kernel purge..."
            if command -v sync_bootloader_configuration >/dev/null 2>&1; then
                sync_bootloader_configuration "$(uname -r)"
            fi
        fi
        log_success "Kernel retention cleanup completed."
    fi
}

# 6A-98: the stock kernels purge_old_slackware_kernels removes, one "version|packages" line each (also used to build
# the startup menu without them before they are deleted)
get_obsolete_slackware_kernels() {
    # 6A-46: only stock kernels that pkgtools knows (kernel-generic/-huge/-modules/-source packages) are pruned, grouped
    # by VERSION (generic-X, huge-X and the module dir X are one kernel). The running kernel and the newest stock
    # kernel(s) always stay. Kernels that are not Slackware packages (self-built, leftovers) are never touched.
    python3 -I -c "
import os, re
db = '/var/lib/pkgtools/packages'
pat = re.compile(r'^kernel-(generic|huge|modules|source)-(.+)-([^-]+)-([^-]+)$')
by_ver = {}
try:
    for n in os.listdir(db):
        m = pat.match(n)
        if m:
            by_ver.setdefault(m.group(2), []).append(n)
except OSError:
    pass
def key(v):
    return [int(x) for x in re.findall(r'\d+', v)]
active = os.uname().release
stock_active = active in by_ver or any(active.endswith('-' + v) or active == v for v in by_ver)
keep_count = 2 if stock_active else 1
vers = sorted(by_ver, key=key, reverse=True)
keep = set(vers[:keep_count])
for v in vers:
    if v == active or active.startswith(v):
        keep.add(v)
for v in vers:
    if v not in keep:
        print(v + '|' + ' '.join(sorted(by_ver[v])))
" 2>/dev/null || true
}

purge_old_slackware_kernels() {
    validate_privileges

    local remove_list
    remove_list=$(get_obsolete_slackware_kernels)

    local removed_any=0
    if [ -n "${remove_list}" ]; then
        while IFS='|' read -r kver kpkgs; do
            [ -n "${kver}" ] && [ -n "${kpkgs}" ] || continue
            [ "${kver}" != "$(uname -r)" ] || continue
            # 6A-98: same rule as for CachyOS kernels above
            if ss_live_menu_lists_kernel "${kver}"; then
                if [ "${SS_KEEP_SET_MENU:-0}" = "1" ]; then
                    log_warn "Kernel ${kver} was kept for now because the startup menu still lists it."
                    continue
                fi
                mark_boot_reseal_pending
            fi
            log_info "Purging obsolete Slackware stock kernel: ${kver}..."
            local p_base rm_failed=0
            for p_base in ${kpkgs}; do
                log_info "Removing registered package: ${p_base}..."
                # 6A-143: keep the kernel files when removepkg fails
                if ! sudo "${PKG_REMOVE_CMD:-removepkg}" "${p_base}" >/dev/null 2>&1; then
                    rm_failed=1
                fi
            done
            if [ "${rm_failed}" -eq 1 ]; then
                log_warn "Kernel ${kver} could not be removed cleanly, so its files were kept."
                continue
            fi

            local fl
            for fl in vmlinuz System.map config; do
                sudo rm -f "/boot/${fl}-${kver}" "/boot/${fl}-generic-${kver}" "/boot/${fl}-huge-${kver}" 2>/dev/null || true
            done
            sudo rm -f "/boot/initramfs-${kver}.img" 2>/dev/null || true
            sudo rm -f "/boot/initramfs-${kver}.img.old" 2>/dev/null || true
            sudo rm -f "/boot/initrd-${kver}.img" 2>/dev/null || true
            sudo rm -f "/boot/initrd-${kver}.gz" 2>/dev/null || true
            sudo rm -rf "/lib/modules/${kver}" 2>/dev/null || true
            sudo rm -rf "/usr/lib/modules/${kver}" 2>/dev/null || true

            dkms_purge_kernel "${kver}"

            removed_any=1
            log_success "Removed obsolete Slackware kernel artifacts for: ${kver}"
        done <<< "${remove_list}"
    fi

    # Clean legacy mkinitrd images (11MB) and broken symlinks in /boot ONLY if Dracut is active AND verified
    local engine
    engine=$(detect_initramfs_engine 2>/dev/null || echo "mkinitrd")
    # 6A-133 (LTS B7): mkinitrd/geninitrd images are only replaced when Limine is the managed boot loader; on LILO/ELILO
    # they are what the machine boots (initrd.gz points at them)
    if [ "${engine}" = "dracut" ] && command -v limine_is_active_loader >/dev/null 2>&1 && limine_is_active_loader; then
        for img in /boot/initrd-*.img /boot/initrd-*.gz; do
            [ -f "${img}" ] && [ ! -L "${img}" ] || continue
            boot_symlink_points_to "${img}" && continue
            local img_kver
            img_kver=$(basename "${img}" | sed -e 's/^initrd-//' -e 's/\.img$//' -e 's/\.gz$//')
            # STRICT CHECK: Only delete mkinitrd image IF a valid, non-empty Dracut initramfs (>5MB) exists for this exact kernel!
            local d_img="/boot/initramfs-${img_kver}.img"
            local d_sz=0
            [ -f "${d_img}" ] && d_sz=$(stat -c%s "${d_img}" 2>/dev/null || echo 0)
            if [ "${d_sz}" -gt 5000000 ]; then
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
            if [ ! -d "/lib/modules/${img_kver}" ] && [ ! -d "/usr/lib/modules/${img_kver}" ]; then
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

    local sync_boot="${1:-sync}"
    if [ "${removed_any}" -eq 1 ]; then
        if [ "${sync_boot}" != "--no-sync" ]; then
            log_info "Updating bootloader after kernel cleanup..."
            if command -v sync_bootloader_configuration >/dev/null 2>&1; then
                sync_bootloader_configuration "$(uname -r)"
            fi
        fi
        log_success "Slackware kernel retention cleanup completed."
    fi
}

# 6A-143: owner uid of a path (the link itself, not its target). Separate so tests can stub it.
_slacky_path_owner_uid() {
    stat -c '%u' -- "$1" 2>/dev/null || echo "-1"
}

# 6A-143: remove our own temp entries only: matching our patterns, owned by root or the invoking user, untouched for
# 6 hours, never a dracut work dir while dracut runs. Usage: _slacky_clean_tmp_entries <root-prefix> <pattern>...
_slacky_clean_tmp_entries() {
    local prefix="$1"; shift
    local me="${SUDO_UID:-$(id -u)}"
    local dracut_busy=0
    if pgrep -x dracut >/dev/null 2>&1; then dracut_busy=1; fi
    local pat entry owner
    for pat in "$@"; do
        for entry in ${prefix}${pat}; do
            [ -e "${entry}" ] || [ -L "${entry}" ] || continue
            case "${entry}" in
                */slacky-update.lock|*/slacky-update-running.lock) continue ;;
                */dracut-*) [ "${dracut_busy}" -eq 0 ] || continue ;;
            esac
            owner=$(_slacky_path_owner_uid "${entry}")
            [ "${owner}" = "0" ] || [ "${owner}" = "${me}" ] || continue
            # Untouched for at least 6 hours (find tests the entry itself, not its contents)
            [ -n "$(find "${entry}" -maxdepth 0 -mmin +360 2>/dev/null)" ] || continue
            sudo rm -rf -- "${entry}" 2>/dev/null || true
        done
    done
}

# 6A-143: delete only cached package files that are OLDER than the installed package of the same name. The installed
# version and anything newer (downloaded, not installed yet) stay. Usage: _slacky_prune_pkg_cache <dir> [pkgdb]
_slacky_prune_pkg_cache() {
    local cdir="$1" pkgdb="${2:-/var/log/packages}"
    [ -d "${cdir}" ] && [ ! -L "${cdir}" ] || return 0
    local f fname full base inst inst_full newest cand
    while IFS= read -r -d '' f; do
        fname=$(basename "${f}")
        full="${fname%.t?z}"
        base="${full%-*-*-*}"
        [ -n "${base}" ] && [ "${base}" != "${full}" ] || continue
        inst=""
        for cand in "${pkgdb}/${base}"-*-*-*; do
            [ -f "${cand}" ] || continue
            [ "$(basename "${cand}" | sed -E 's/-[^-]+-[^-]+-[^-]+$//')" = "${base}" ] || continue
            inst="${cand}"
        done
        [ -n "${inst}" ] || continue
        inst_full=$(basename "${inst}")
        [ "${inst_full}" != "${full}" ] || continue
        newest=$(printf '%s\n%s\n' "${inst_full#"${base}"-}" "${full#"${base}"-}" | sort -V | tail -n 1)
        if [ "${newest}" = "${inst_full#"${base}"-}" ]; then
            sudo rm -f -- "${f}" "${f}.asc" "${f}.md5" 2>/dev/null || true
        fi
    done < <(find "${cdir}" -type f -name '*.t[xgbl]z' -print0 2>/dev/null)
}

clean_package_and_build_caches() {
    validate_privileges

    log_info "Cleaning package caches and temporary build directories..."
    sudo rm -rf /var/cache/slacky-update/kernel/* \
                /var/cache/slacky-update/nvidia/* \
                /var/cache/slacky-update/archives/* \
                /var/cache/slacky-update/rocm/* \
                /var/cache/slacky-update/*.tmp \
                /var/cache/sbopkg/* 2>/dev/null || true
    # 6A-143: the slackpkg cache keeps the installed and not-yet-installed packages; only older copies go
    _slacky_prune_pkg_cache /var/cache/slackpkg

    # 6A-143: only our own temp entries, owned by root or you, untouched for 6 hours
    _slacky_clean_tmp_entries "" \
                "/tmp/slacky-build-*" \
                "/tmp/slacky-rocm-*" \
                "/tmp/slacky-sign-*" \
                "/tmp/slacky-snap-*" \
                "/tmp/slacky-gnome*" \
                "/tmp/slacky-update-check.*" \
                "/tmp/slacky-staging-*" \
                "/tmp/slacky-staging.*" \
                "/tmp/dracut-*" \
                "/tmp/initrd-tree-*" \
                "/var/tmp/slacky-initrd-tree*" \
                "/tmp/initrd-*.gz" \
                "/tmp/SBo/slacky-*" \
                "/tmp/build-slacky*" \
                "/tmp/package-slacky*" \
                "/tmp/transmute-gnomes-*" \
                "/tmp/underpants-*.txz" \
                "/tmp/underpants-*.part" \
                "/tmp/pycache"

    # Clean a stale legacy lock file only when the process it names is gone (6A-143: never a live run lock)
    if [ -f /tmp/slacky-update-running.lock ] && [ ! -L /tmp/slacky-update-running.lock ] \
        && [ "${SLACKY_UPDATE_RUNNING:-0}" != "1" ]; then
        local lock_pid
        lock_pid=$(head -c 32 /tmp/slacky-update-running.lock 2>/dev/null | tr -cd '0-9' || true)
        if [ -z "${lock_pid}" ] || ! kill -0 "${lock_pid}" 2>/dev/null; then
            sudo rm -f /tmp/slacky-update-running.lock 2>/dev/null || true
        fi
    fi

    if command -v gnomes >/dev/null 2>&1; then
        sudo gnomes -Sc >/dev/null 2>&1 || true
    elif [ -f "/usr/share/slacky-update/lib/gnomes_pacman.py" ]; then
        sudo python3 /usr/share/slacky-update/lib/gnomes_pacman.py clean >/dev/null 2>&1 || true
    fi

    log_success "Package caches and temporary build artifacts cleaned."
}

prune_obsolete_kernels_safe() {
    validate_privileges

    log_info "Auditing and pruning obsolete kernels..."
    purge_old_cachyos_kernels "--no-sync"
    purge_old_slackware_kernels "--no-sync"

    log_info "Resealing bootloader and updating BLAKE2B cryptographic hashes..."
    if command -v sync_bootloader_configuration >/dev/null 2>&1; then
        sync_bootloader_configuration "$(uname -r)"
    fi
    log_success "Kernel retention pruning and bootloader resealing completed."
}

clean_unused_flatpaks() {
    if command -v flatpak >/dev/null 2>&1; then
        log_info "Uninstalling unused Flatpak runtimes..."
        flatpak uninstall --unused -y 2>/dev/null || true
        log_success "Unused Flatpak runtimes removed."
    else
        log_info "Flatpak is not installed on this system."
    fi
}

dedup_underpants_storage() {
    validate_privileges
    if command -v gnomes >/dev/null 2>&1; then
        log_info "Running Underpants Gnomes storage deduplication..."
        sudo gnomes dedup
        log_success "Underpants Gnomes storage deduplication completed."
    elif [ -f "${SCRIPT_DIR}/../lib/gnomes_pacman.py" ]; then
        log_info "Running Underpants Gnomes storage deduplication..."
        sudo python3 "${SCRIPT_DIR}/../lib/gnomes_pacman.py" dedup
        log_success "Underpants Gnomes storage deduplication completed."
    else
        log_info "Underpants Gnomes runtime is not installed. Nothing to deduplicate."
    fi
}

clean_system_full_sweep() {
    validate_privileges

    log_info "Executing Full System Sweep (caches, build temps, kernels, flatpaks, dedup)..."
    clean_package_and_build_caches
    prune_obsolete_kernels_safe
    clean_unused_flatpaks
    dedup_underpants_storage
    log_success "Full System Sweep completed successfully. System pristine."
}

# Backward compatibility alias
clean_system_cache_and_orphans() {
    clean_system_full_sweep
}

manage_system_clean_interactive() {
    local tui_py="${SCRIPT_DIR}/../lib/slacky_tui.py"
    if [ ! -f "${tui_py}" ]; then
        tui_py="/usr/share/slacky-update/lib/slacky_tui.py"
    fi

    while true; do
        local choice=""
        if [ -t 0 ] && [ -f "${tui_py}" ]; then
            choice=$(python3 "${tui_py}" --mode clean 2>/dev/tty || echo "6")
        else
            echo ""
            echo "Slacky-Update System Maintenance & Cleanup"
            echo "1. Full System Sweep"
            echo "2. Clean Package & Build Caches Only"
            echo "3. Prune Obsolete Kernels"
            echo "4. Prune Unused Flatpak Runtimes"
            echo "5. Underpants Gnomes Storage Deduplication"
            echo "6. Return to Main Menu"
            read -r -p "Select option [1-6]: " choice || choice="6"
        fi

        case "${choice}" in
            1)
                echo ""
                local confirm="Y"
                read_update_prompt "Execute Full System Sweep? [Y/n] " "Y" confirm
                if [[ "${confirm}" =~ ^[YyJjSsOo]$ ]]; then
                    # 6A-143: never clean while another update holds the run lock
                    if begin_atomic_transaction "full system sweep"; then
                        clean_system_full_sweep
                        end_atomic_transaction
                    else
                        log_warn "Another update is running, so nothing was cleaned."
                    fi
                else
                    log_info "Full System Sweep canceled."
                fi
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            2)
                echo ""
                # 6A-143: never clean while another update holds the run lock
                if begin_atomic_transaction "package & build cache cleanup"; then
                    clean_package_and_build_caches
                    end_atomic_transaction
                else
                    log_warn "Another update is running, so nothing was cleaned."
                fi
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            3)
                echo ""
                local confirm_k="Y"
                read_update_prompt "Prune obsolete kernels (retaining active and newest fallback)? [Y/n] " "Y" confirm_k
                if [[ "${confirm_k}" =~ ^[YyJjSsOo]$ ]]; then
                    # 6A-143: never clean while another update holds the run lock
                    if begin_atomic_transaction "kernel retention pruning"; then
                        prune_obsolete_kernels_safe
                        end_atomic_transaction
                    else
                        log_warn "Another update is running, so nothing was cleaned."
                    fi
                else
                    log_info "Kernel pruning canceled."
                fi
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            4)
                echo ""
                # 6A-143: never clean while another update holds the run lock
                if begin_atomic_transaction "unused flatpak runtime cleanup"; then
                    clean_unused_flatpaks
                    end_atomic_transaction
                else
                    log_warn "Another update is running, so nothing was cleaned."
                fi
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            5)
                echo ""
                # 6A-143: never clean while another update holds the run lock
                if begin_atomic_transaction "gnomes storage deduplication"; then
                    dedup_underpants_storage
                    end_atomic_transaction
                else
                    log_warn "Another update is running, so nothing was cleaned."
                fi
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            6|Q|q|ESC|"")
                log_info "Returning to Main Menu."
                break
                ;;
            *)
                log_warn "Invalid selection: ${choice}"
                sleep 1
                ;;
        esac
    done
}
