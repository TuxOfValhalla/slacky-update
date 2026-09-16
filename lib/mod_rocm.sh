#!/bin/bash
# =============================================================================
#  SLACKY-UPDATE: AMD ROCm / HIP Creator Toolkit Module
#  Manages AMD ROCm OpenCL / HIP Runtimes, Mesa OpenCL purges & Blacklisting
# =============================================================================

set -euo pipefail

# --- [ AMD GPU GUARD ] ---
is_amd_gpu_present() {
    probe_gpu_hardware
    [ "${HAS_AMD}" = "true" ]
}

# --- [ PURGE & BLACKLIST CONFLICTING MESA OPENCL / RUSTICL ] ---
purge_conflicting_mesa_opencl() {
    validate_privileges
    log_info "Scanning for conflicting Mesa OpenCL and Rusticl packages..."

    local conflicting_pkgs=("opencl-mesa" "opencl-mesa-compat32" "rusticl" "mesa-rusticl")
    local removed_any=0

    for cpkg in "${conflicting_pkgs[@]}"; do
        for p in /var/log/packages/${cpkg}-*; do
            [ -f "${p}" ] || continue
            local base_p
            base_p=$(basename "${p}")
            log_info "Removing conflicting package: ${base_p}..."
            sudo "${PKG_REMOVE_CMD}" "${base_p}" 2>/dev/null || true
            removed_any=1
        done
    done

    # Remove conflicting OpenCL vendor ICD descriptors
    local conflicting_icds=(
        "/etc/OpenCL/vendors/mesa.icd"
        "/etc/OpenCL/vendors/rusticl.icd"
    )
    for icd in "${conflicting_icds[@]}"; do
        if [ -f "${icd}" ]; then
            log_info "Removing conflicting ICD: ${icd}..."
            sudo rm -f "${icd}"
            removed_any=1
        fi
    done

    # Blacklist in /etc/slackpkg/blacklist to prevent regression during slackpkg upgrade-all
    local blacklist_file="/etc/slackpkg/blacklist"
    if [ -f "${blacklist_file}" ]; then
        if ! grep -q "Slacky-Update AMD ROCm Protection" "${blacklist_file}"; then
            log_info "Adding Mesa OpenCL & Rusticl blacklist entries to ${blacklist_file}..."
            echo -e "\n# [Slacky-Update AMD ROCm Protection]\nopencl-mesa*\nrusticl*\nmesa-rusticl*" | sudo tee -a "${blacklist_file}" >/dev/null
        fi
    fi

    sudo "${LDCONFIG_CMD}" 2>/dev/null || true
    log_success "$(_ ROCM_PURGE_SUCCESS)"
}

# --- [ INSTALL CACHYOS / ARCH ROCM SUITE ] ---
install_cachyos_rocm_suite() {
    validate_privileges
    log_info "Preparing AMD ROCm & HIP Creator Suite deployment..."

    # Ensure conflicting Mesa OpenCL is purged and blacklisted first
    purge_conflicting_mesa_opencl

    local staging_root="/tmp/slacky-rocm-staging"
    sudo rm -rf "${staging_root}"
    sudo mkdir -p "${staging_root}/install"
    sudo mkdir -p "${staging_root}/etc/OpenCL/vendors"
    sudo mkdir -p "${staging_root}/etc/profile.d"
    sudo mkdir -p "${staging_root}/etc/ld.so.conf.d"

    local mirror_url="https://mirror.cachyos.org/repo/x86_64/cachyos"
    local arch_mirror_url="https://geo-mirror.pkgbuild.com/extra/os/x86_64"
    local arch_multilib_url="https://geo-mirror.pkgbuild.com/multilib/os/x86_64"

    log_info "Scanning upstream repository for ROCm & HIP 64-bit and 32-bit multilib packages..."

    local rocm_pkgs=(
        "rocm-core"
        "hsakmt-roct"
        "hsa-rocr"
        "comgr"
        "rocm-opencl-runtime"
        "rocm-hip-runtime"
        "hip-runtime-amd"
        "lib32-rocm-opencl-runtime"
        "lib32-opencl-icd-loader"
    )

    local dl_dir="$(get_user_staging_dir)/rocm-dl"
    rm -rf "${dl_dir}"
    mkdir -p "${dl_dir}"

    local rocm_dl_items=()
    local resolved_pkgs=()

    log_info "Resolving upstream package URLs for AMD ROCm..."
    local m_index
    m_index=$(curl -sSL -m 10 "${mirror_url}/" 2>/dev/null || echo "")
    local arch_index
    arch_index=$(curl -sSL -m 10 "${arch_mirror_url}/" 2>/dev/null || echo "")
    local multilib_index
    multilib_index=$(curl -sSL -m 10 "${arch_multilib_url}/" 2>/dev/null || echo "")

    for rpkg in "${rocm_pkgs[@]}"; do
        local pkg_file
        pkg_file=$(echo "${m_index}" | grep -o -E "${rpkg}-[0-9][^\"'>]+\.pkg\.tar\.zst" | sort -V | tail -n 1 || true)
        local base_url="${mirror_url}"

        if [ -z "${pkg_file}" ]; then
            pkg_file=$(echo "${arch_index}" | grep -o -E "${rpkg}-[0-9][^\"'>]+\.pkg\.tar\.zst" | sort -V | tail -n 1 || true)
            base_url="${arch_mirror_url}"
        fi

        if [ -z "${pkg_file}" ]; then
            pkg_file=$(echo "${multilib_index}" | grep -o -E "${rpkg}-[0-9][^\"'>]+\.pkg\.tar\.zst" | sort -V | tail -n 1 || true)
            base_url="${arch_multilib_url}"
        fi

        if [ -n "${pkg_file}" ]; then
            rocm_dl_items+=("${base_url}/${pkg_file}|${dl_dir}/${pkg_file}")
            resolved_pkgs+=("${dl_dir}/${pkg_file}")
        else
            log_warn "Package ${rpkg} not found in primary mirrors; continuing..."
        fi
    done

    if [ ${#rocm_dl_items[@]} -gt 0 ]; then
        if ! download_parallel_pacman "AMD ROCm / HIP Creator Suite (64-bit & Multilib)" "${rocm_dl_items[@]}"; then
            log_warn "Some ROCm components failed to download."
        fi
        validate_privileges
        for r_pkg_file in "${resolved_pkgs[@]}"; do
            if [ -f "${r_pkg_file}" ] && [ -s "${r_pkg_file}" ]; then
                sudo tar --zstd -xf "${r_pkg_file}" -C "${staging_root}/" 2>/dev/null || true
            fi
        done
    fi

    # Clean Arch Linux packaging metadata
    sudo rm -f "${staging_root}/.BUILDINFO" "${staging_root}/.INSTALL" "${staging_root}/.MTREE" "${staging_root}/.PKGINFO"

    # Setup OpenCL ICDs (64-bit and 32-bit multilib)
    echo "libamdocl64.so" | sudo tee "${staging_root}/etc/OpenCL/vendors/amdocl64.icd" >/dev/null
    if [ -f "${staging_root}/usr/lib32/libamdocl32.so" ] || [ -f "${staging_root}/opt/rocm/lib/libamdocl32.so" ] || [ -f "${staging_root}/usr/lib32/libOpenCL.so" ]; then
        echo "libamdocl32.so" | sudo tee "${staging_root}/etc/OpenCL/vendors/amdocl32.icd" >/dev/null
    fi

    # Setup ldconfig paths for both 64-bit and 32-bit multilib ROCm libraries
    echo -e "/opt/rocm/lib\n/opt/rocm/lib64\n/opt/rocm/lib32\n/usr/lib64/rocm\n/usr/lib/rocm" | sudo tee "${staging_root}/etc/ld.so.conf.d/rocm.conf" >/dev/null

    # Setup profile scripts
    cat << 'ROCM_SH_EOF' | sudo tee "${staging_root}/etc/profile.d/rocm.sh" >/dev/null
#!/bin/sh
# AMD ROCm / HIP Creator Environment Configuration
export ROCM_PATH="/opt/rocm"
export HIP_PATH="/opt/rocm"
export ROC_ENABLE_PRE_VEGA=1

if [ -d "/opt/rocm/bin" ] && ! echo "$PATH" | grep -q "/opt/rocm/bin"; then
    export PATH="$PATH:/opt/rocm/bin"
fi
ROCM_SH_EOF

    cat << 'ROCM_CSH_EOF' | sudo tee "${staging_root}/etc/profile.d/rocm.csh" >/dev/null
#!/bin/csh
# AMD ROCm / HIP Creator Environment Configuration
setenv ROCM_PATH /opt/rocm
setenv HIP_PATH /opt/rocm
setenv ROC_ENABLE_PRE_VEGA 1

if ( -d /opt/rocm/bin ) then
    setenv PATH "${PATH}:/opt/rocm/bin"
endif
ROCM_CSH_EOF

    sudo chmod 755 "${staging_root}/etc/profile.d/rocm.sh" "${staging_root}/etc/profile.d/rocm.csh"

    # Write Slackware slack-desc
    cat << 'DESC_EOF' | sudo tee "${staging_root}/install/slack-desc" >/dev/null
cachyos-rocm-opencl: cachyos-rocm-opencl (AMD ROCm & HIP OpenCL Creator Suite)
cachyos-rocm-opencl:
cachyos-rocm-opencl: High performance AMD ROCm OpenCL and HIP compute runtimes,
cachyos-rocm-opencl: enabling hardware accelerated rendering, compute shaders,
cachyos-rocm-opencl: DaVinci Resolve Studio GPU compute, Blender HIP cycles,
cachyos-rocm-opencl: and Machine Learning workflows on AMD Radeon GPUs.
cachyos-rocm-opencl:
cachyos-rocm-opencl: Packaged directly from CachyOS / Arch upstream for Slackware.
cachyos-rocm-opencl:
cachyos-rocm-opencl: Maintained by slacky-update.
cachyos-rocm-opencl:
DESC_EOF

    # Write doinst.sh
    cat << 'DOINST_EOF' | sudo tee "${staging_root}/install/doinst.sh" >/dev/null
if [ -x /sbin/ldconfig ]; then
  /sbin/ldconfig 2>/dev/null || true
fi
DOINST_EOF

    local target_pkg="/tmp/cachyos-rocm-opencl-7.2.4-x86_64-1_slacky.txz"
    log_info "Assembling Slackware txz package: ${target_pkg}..."
    (
        cd "${staging_root}"
        sudo "${PKG_MAKE_CMD}" -l y -c n "${target_pkg}" >/dev/null 2>&1
    )

    if [ -f "${target_pkg}" ] && [ -s "${target_pkg}" ]; then
        log_info "Installing ${target_pkg}..."
        sudo "${PKG_UPGRADE_CMD}" --reinstall --install-new "${target_pkg}"
        sudo rm -rf "${staging_root}" "${dl_dir}" "${target_pkg}"
        log_success "$(_ ROCM_INSTALL_SUCCESS)"
    else
        log_warn "Failed to build cachyos-rocm-opencl package. Reverting staging..."
        sudo rm -rf "${staging_root}" "${dl_dir}"
        return 1
    fi
}

# --- [ VERIFY AMD COMPUTE & OPENCL STATUS ] ---
verify_amd_compute_status() {
    echo ""
    echo -e "${BOLD}${CYAN}=== 🏎️ AMD ROCm / HIP & OpenCL Status ===${RESET}"

    echo -n "• OpenCL ICD Descriptors: "
    if ls /etc/OpenCL/vendors/*.icd >/dev/null 2>&1; then
        echo -e "${GREEN}$(ls /etc/OpenCL/vendors/*.icd | xargs -n1 basename | tr '\n' ' ')${RESET}"
    else
        echo -e "${YELLOW}None found${RESET}"
    fi

    echo -n "• ROCm Runtime Installation: "
    if [ -d "/opt/rocm" ] || ls /var/log/packages/cachyos-rocm-* >/dev/null 2>&1; then
        echo -e "${GREEN}Active (/opt/rocm)${RESET}"
    else
        echo -e "${YELLOW}Not deployed${RESET}"
    fi

    echo -n "• Mesa OpenCL Conflict Status: "
    if ls /var/log/packages/opencl-mesa* >/dev/null 2>&1 || [ -f "/etc/OpenCL/vendors/mesa.icd" ]; then
        echo -e "${RED}Conflict Present (opencl-mesa detected! Run option 2 to purge)${RESET}"
    else
        echo -e "${GREEN}Clean (No Mesa OpenCL conflicts)${RESET}"
    fi

    if command -v clinfo >/dev/null 2>&1; then
        echo ""
        log_info "Querying clinfo for AMD GPU compute devices..."
        clinfo 2>/dev/null | grep -iE 'Platform Name|Device Name' || true
    fi
    echo -e "${CYAN}===========================================${RESET}"
}

# --- [ INTERACTIVE ROCM CREATOR MENU ] ---
manage_rocm_interactive() {
    while true; do
        echo ""
        echo -e "${BOLD}${CYAN}$(_ ROCM_MENU_TITLE)${RESET}"
        echo -e "  \033[1;33m1.\033[0m $(_ ROCM_OPTION_INSTALL)"
        echo -e "  \033[1;33m2.\033[0m $(_ ROCM_OPTION_PURGE_MESA)"
        echo -e "  \033[1;33m3.\033[0m $(_ ROCM_OPTION_VERIFY)"
        echo -e "  \033[1;33m4.\033[0m $(_ SBO_BACK_OPTION)"
        echo ""
        echo -n "$(_ SELECT_OPERATION_RANGE range="1-4") "
        local sel
        read -r sel || sel="4"

        case "${sel}" in
            1)
                echo ""
                install_cachyos_rocm_suite
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            2)
                echo ""
                purge_conflicting_mesa_opencl
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            3)
                verify_amd_compute_status
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            4)
                return 0
                ;;
            *)
                echo -e "\n${YELLOW}$(_ INVALID_SELECTION)${RESET}"
                sleep 1
                ;;
        esac
    done
}
