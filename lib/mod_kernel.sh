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

check_latest_cachyos_upstream() {
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

    for repo_url in "${repo_urls[@]}"; do
        local result
        result=$(curl -sSL -m 15 "${repo_url}" 2>/dev/null | python3 -c "
import re, sys

html = sys.stdin.read()
if not html:
    print('NONE NONE NONE')
    sys.exit(0)

repo_url = '${repo_url}'

k_matches = re.findall(r'href=[\'\"]?(linux-cachyos-([0-9]+\.[0-9]+\.[0-9]+-[0-9]+)[^\'\">]*\.pkg\.tar\.zst)', html)
h_matches = re.findall(r'href=[\'\"]?(linux-cachyos-headers-([0-9]+\.[0-9]+\.[0-9]+-[0-9]+)[^\'\">]*\.pkg\.tar\.zst)', html)

if not k_matches or not h_matches:
    print('NONE NONE NONE')
    sys.exit(0)

def parse_ver_key(v_str):
    return [int(x) for x in re.findall(r'\d+', v_str)]

available_versions = sorted(list(set(m[1] for m in k_matches)), key=parse_ver_key, reverse=True)
latest_ver = available_versions[0]

k_pkg = next(m[0] for m in k_matches if m[1] == latest_ver)
h_pkg = next(m[0] for m in h_matches if m[1] == latest_ver)

print(f'{latest_ver} {repo_url}{k_pkg} {repo_url}{h_pkg}')
" 2>/dev/null || echo "NONE NONE NONE")

        if [ "${result}" != "NONE NONE NONE" ] && [ -n "${result}" ]; then
            echo "${result}"
            return 0
        fi
    done

    echo "NONE NONE NONE"
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

deploy_cachyos_kernel_packages() {
    local ver="$1"
    local k_url="$2"
    local h_url="$3"
    validate_privileges

    local dest_dir="/var/cache/slacky-update/kernel"
    sudo mkdir -p "${dest_dir}"
    local k_file="${dest_dir}/linux-cachyos-${ver}.pkg.tar.zst"
    local h_file="${dest_dir}/linux-cachyos-headers-${ver}.pkg.tar.zst"

    log_info "Downloading kernel package (${ver})..."
    sudo curl -sSL -o "${k_file}" "${k_url}"
    log_info "Downloading kernel headers package (${ver})..."
    sudo curl -sSL -o "${h_file}" "${h_url}"

    log_info "Extracting kernel package to system root..."
    sudo tar --zstd -xf "${k_file}" -C /

    log_info "Extracting kernel headers package to system root..."
    sudo tar --zstd -xf "${h_file}" -C /

    local kver_full="${ver}-cachyos"

    if [ -d "/usr/lib/modules" ] && [ ! -d "/lib/modules/${kver_full}" ]; then
        if [ -d "/usr/lib/modules/${kver_full}" ]; then
            sudo mkdir -p /lib/modules
            sudo ln -sf "/usr/lib/modules/${kver_full}" "/lib/modules/${kver_full}"
        fi
    fi

    if [ -f "/boot/vmlinuz-linux-cachyos" ]; then
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

    local depmod_bin
    depmod_bin=$(command -v depmod 2>/dev/null || echo "/sbin/depmod")
    sudo "${depmod_bin}" -a "${kver_full}"
    log_success "Kernel deployed: ${kver_full}"

    # 1. Build DKMS out-of-tree modules (NVIDIA) first so they exist in /lib/modules before initramfs & signing
    if command -v build_nvidia_modules >/dev/null 2>&1; then
        build_nvidia_modules "${kver_full}"
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

    local engine
    engine=$(detect_initramfs_engine)
    log_info "Initramfs Engine Selected: ${engine}"

    if [ "${engine}" = "dracut" ]; then
        local dracut_bin
        dracut_bin=$(command -v dracut 2>/dev/null || echo "/usr/bin/dracut")
        local dracut_args=(--force)
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
                    if sudo "${dracut_bin}" "${dracut_args[@]}" "${initrd_out}" "${single_kver}"; then
                        # Clean up legacy mkinitrd files for this kernel ONLY after verified successful Dracut generation
                        if [ -f "${initrd_out}" ] && [ -s "${initrd_out}" ]; then
                            sudo rm -f "/boot/initrd-${single_kver}.img" "/boot/initrd-${single_kver}.gz" "/boot/initrd-${single_kver}" 2>/dev/null || true
                        fi
                    fi
                fi
            done

            # Clean orphaned initramfs images
            for img in /boot/initramfs-*.img; do
                [ -f "${img}" ] || continue
                local img_kver
                img_kver=$(basename "${img}" | sed -e 's/^initramfs-//' -e 's/\.img$//')
                if [ ! -d "/lib/modules/${img_kver}" ]; then
                    log_info "Removing orphaned initramfs image: ${img}"
                    sudo rm -f "${img}" 2>/dev/null || true
                fi
            done

            log_success "Dracut initramfs regeneration completed for all kernels."
            return 0
        else
            local initrd_out="/boot/initramfs-${kver}.img"
            log_info "Generating Dracut initramfs for kernel: ${kver} -> ${initrd_out}..."
            if sudo "${dracut_bin}" "${dracut_args[@]}" "${initrd_out}" "${kver}"; then
                # Clean up legacy mkinitrd files for this kernel ONLY after verified successful Dracut generation
                if [ -f "${initrd_out}" ] && [ -s "${initrd_out}" ]; then
                    sudo rm -f "/boot/initrd-${kver}.img" "/boot/initrd-${kver}.gz" "/boot/initrd-${kver}" 2>/dev/null || true
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
            if [ -x "/sbin/mkinitrd_command_generator.sh" ]; then
                log_info "Regenerating mkinitrd images using Slackware generator..."
                sudo bash <(/sbin/mkinitrd_command_generator.sh) 2>/dev/null || true
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

    if ! sudo /sbin/mkinitrd -c -k "${kver}" -m "${combined_modules}" -f "${root_fs}" -r "${root_param}" ${ucode_opt} -o "${initrd_out}"; then
        log_warn "Standard mkinitrd completed with warnings. Running fallback..."
        sudo /sbin/mkinitrd -c -k "${kver}" -o "${initrd_out}"
    fi

    log_success "Initrd generated: ${initrd_out}"
}

# Backwards compatibility alias
generate_cachy_initrd() {
    generate_kernel_initramfs "$1"
}
