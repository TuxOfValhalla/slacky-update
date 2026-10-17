#!/bin/bash
# =============================================================================
#  SLACKY-UPDATE: AMD ROCm / HIP Creator Toolkit Module
#  Manages AMD ROCm OpenCL / HIP Runtimes (Mesa OpenCL is never removed, only hidden from ROCm sessions)
# =============================================================================

set -euo pipefail

# --- [ AMD GPU GUARD ] ---
is_amd_gpu_present() {
    probe_gpu_hardware
    [ "${HAS_AMD}" = "true" ]
}

# --- [ MESA OPENCL / RUSTICL NEXT TO ROCM ] ---
# 6A-2 (mirror of Rust B7): Mesa OpenCL / Rusticl belongs to Slackware's mesa package. Nothing is removed,
# deleted or blacklisted; ROCm sessions hide it through the OCL_ICD_VENDORS filter in /etc/profile.d/rocm.sh.
purge_conflicting_mesa_opencl() {
    local icd found=0
    for icd in /etc/OpenCL/vendors/mesa.icd /etc/OpenCL/vendors/rusticl.icd; do
        [ -e "${icd}" ] && found=1
    done
    if [ "${found}" -eq 0 ]; then
        log_info "$(_ ROCM_MESA_NONE)"
    elif grep -qs 'OCL_ICD_VENDORS' /etc/profile.d/rocm.sh; then
        log_info "$(_ ROCM_MESA_HIDDEN)"
    else
        log_info "$(_ ROCM_MESA_NOT_HIDDEN)"
    fi
}

# --- [ INSTALL CACHYOS / ARCH ROCM SUITE ] ---
install_cachyos_rocm_suite() {
    validate_privileges
    # 6A-143 (ROCm, C-M5/F10): ROCm is for AMD GPUs; SLACKY_ROCM_ALLOW_NON_AMD=1 overrides (e.g. eGPU not yet attached)
    if ! is_amd_gpu_present && [ "${SLACKY_ROCM_ALLOW_NON_AMD:-0}" != "1" ]; then
        log_warn "No AMD graphics card was found, so ROCm was not installed."
        return 1
    fi
    log_info "Preparing AMD ROCm & HIP Creator Suite deployment..."

    # 6A-2: Mesa OpenCL is never removed (Slackware's mesa owns it); rocm.sh below hides it from ROCm sessions.
    # Private 0700 work dir (mktemp) built as the user; root is only used for upgradepkg.
    # 6A-143: staged on disk in a private 0700 dir under the user cache (ROCm is several GB; /tmp may be RAM)
    local work_base="${XDG_CACHE_HOME:-${HOME}/.cache}/slacky-update"
    mkdir -p -m 0700 "${work_base}" 2>/dev/null || true
    local work_dir
    work_dir=$(mktemp -d "${work_base}/rocm-build.XXXXXXXX") || { log_error "Cannot create a private ROCm work directory."; return 1; }
    local staging_root="${work_dir}/stage"
    mkdir -p "${staging_root}/install" "${staging_root}/etc/OpenCL/vendors" "${staging_root}/etc/profile.d" "${staging_root}/etc/ld.so.conf.d"

    local mirror_url="https://mirror.cachyos.org/repo/x86_64/cachyos"
    local arch_mirror_url="https://geo.mirror.pkgbuild.com/extra/os/x86_64"
    local arch_multilib_url="https://geo.mirror.pkgbuild.com/multilib/os/x86_64"

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

    local dl_dir="${work_dir}/dl"
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
            # 6A-143: signature downloaded next to each package (url|dest|sig_url|sig_dest)
            rocm_dl_items+=("${base_url}/${pkg_file}|${dl_dir}/${pkg_file}|${base_url}/${pkg_file}.sig|${dl_dir}/${pkg_file}.sig")
            resolved_pkgs+=("${dl_dir}/${pkg_file}")
        else
            log_warn "Package ${rpkg} not found in primary mirrors; continuing..."
        fi
    done

    # 6A-143: never build a partial suite. The core packages must resolve; every resolved package must download,
    # pass its signature check (when a .sig exists) and extract cleanly, or nothing is installed.
    local core_pkg core_found
    for core_pkg in rocm-core rocm-opencl-runtime; do
        core_found=0
        for r_pkg_file in "${resolved_pkgs[@]}"; do
            [[ "$(basename "${r_pkg_file}")" =~ ^${core_pkg}-[0-9] ]] && core_found=1
        done
        if [ "${core_found}" -eq 0 ]; then
            log_error "The ROCm package ${core_pkg} was not found on the mirrors, so nothing was installed."
            rm -rf "${work_dir}"
            return 1
        fi
    done
    if ! download_parallel_pacman "AMD ROCm / HIP Creator Suite (64-bit & Multilib)" "${rocm_dl_items[@]}"; then
        log_error "Some ROCm parts could not be downloaded, so nothing was installed."
        rm -rf "${work_dir}"
        return 1
    fi
    for r_pkg_file in "${resolved_pkgs[@]}"; do
        if [ ! -s "${r_pkg_file}" ]; then
            log_error "The ROCm part $(basename "${r_pkg_file}") is missing, so nothing was installed."
            rm -rf "${work_dir}"
            return 1
        fi
        if [ -f "${r_pkg_file}.sig" ] && ! verify_cachyos_gpg_signature "${r_pkg_file}" "${r_pkg_file}.sig"; then
            log_error "The ROCm part $(basename "${r_pkg_file}") failed its signature check, so nothing was installed."
            rm -rf "${work_dir}"
            return 1
        fi
        if ! tar --zstd -xf "${r_pkg_file}" -C "${staging_root}/" 2>/dev/null; then
            log_error "The ROCm part $(basename "${r_pkg_file}") could not be unpacked, so nothing was installed."
            rm -rf "${work_dir}"
            return 1
        fi
    done

    # Clean Arch Linux packaging metadata
    rm -f "${staging_root}/.BUILDINFO" "${staging_root}/.INSTALL" "${staging_root}/.MTREE" "${staging_root}/.PKGINFO"

    # Setup OpenCL ICDs (64-bit and 32-bit multilib)
    echo "libamdocl64.so" > "${staging_root}/etc/OpenCL/vendors/amdocl64.icd"
    if [ -f "${staging_root}/usr/lib32/libamdocl32.so" ] || [ -f "${staging_root}/opt/rocm/lib/libamdocl32.so" ] || [ -f "${staging_root}/usr/lib32/libOpenCL.so" ]; then
        echo "libamdocl32.so" > "${staging_root}/etc/OpenCL/vendors/amdocl32.icd"
    fi

    # Setup ldconfig paths for both 64-bit and 32-bit multilib ROCm libraries
    echo -e "/opt/rocm/lib\n/opt/rocm/lib64\n/opt/rocm/lib32\n/usr/lib64/rocm\n/usr/lib/rocm" > "${staging_root}/etc/ld.so.conf.d/rocm.conf"

    # Setup profile scripts
    cat << 'ROCM_SH_EOF' > "${staging_root}/etc/profile.d/rocm.sh"
#!/bin/sh
# AMD ROCm / HIP Creator Environment Configuration
export ROCM_PATH="/opt/rocm"
export HIP_PATH="/opt/rocm"
export ROC_ENABLE_PRE_VEGA=1

if [ -d "/opt/rocm/bin" ] && ! echo "$PATH" | grep -q "/opt/rocm/bin"; then
    export PATH="$PATH:/opt/rocm/bin"
fi

# Hide Mesa Rusticl from OpenCL apps (avoids SIGSEGV in e.g. DaVinci Resolve) without
# touching any Slackware-owned file: build a per-user ICD dir that omits mesa/rusticl.
if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d /etc/OpenCL/vendors ]; then
    _ocl_dir="$XDG_RUNTIME_DIR/slacky-ocl-vendors"
    if mkdir -p "$_ocl_dir" 2>/dev/null; then
        for _icd in /etc/OpenCL/vendors/*.icd; do
            [ -e "$_icd" ] || continue
            case "${_icd##*/}" in mesa.icd|rusticl.icd) continue ;; esac
            ln -sf "$_icd" "$_ocl_dir/${_icd##*/}" 2>/dev/null
        done
        export OCL_ICD_VENDORS="$_ocl_dir"
    fi
    unset _ocl_dir _icd
fi
ROCM_SH_EOF

    cat << 'ROCM_CSH_EOF' > "${staging_root}/etc/profile.d/rocm.csh"
#!/bin/csh
# AMD ROCm / HIP Creator Environment Configuration
setenv ROCM_PATH /opt/rocm
setenv HIP_PATH /opt/rocm
setenv ROC_ENABLE_PRE_VEGA 1

if ( -d /opt/rocm/bin ) then
    setenv PATH "${PATH}:/opt/rocm/bin"
endif
ROCM_CSH_EOF

    chmod 755 "${staging_root}/etc/profile.d/rocm.sh" "${staging_root}/etc/profile.d/rocm.csh"

    # Write Slackware slack-desc
    cat << 'DESC_EOF' > "${staging_root}/install/slack-desc"
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
    cat << 'DOINST_EOF' > "${staging_root}/install/doinst.sh"
if [ -x /sbin/ldconfig ]; then
  /sbin/ldconfig 2>/dev/null || true
fi
DOINST_EOF

    local rocm_ver="7.2.4"
    local rocm_core_file
    rocm_core_file=$(find "${dl_dir}" -name "rocm-core-*.pkg.tar.zst" 2>/dev/null | head -n1 || true)
    if [ -n "${rocm_core_file}" ]; then
        local extracted_ver
        extracted_ver=$(basename "${rocm_core_file}" | sed -E 's/^rocm-core-([0-9]+\.[0-9]+(\.[0-9]+)?).*$/\1/' || true)
        [ -n "${extracted_ver}" ] && rocm_ver="${extracted_ver}"
    fi

    chmod -R u=rwX,go=rX "${staging_root}"

    # 6A-2 (B7 mirror): Footprint Guard before packaging (enforce unless SLACKY_FOOTPRINT_MODE=report)
    if [ -n "${GNOMES_PY:-}" ] && [ -f "${GNOMES_PY}" ]; then
        if ! python3 "${GNOMES_PY}" footprint-guard "${staging_root}" --label "cachyos-rocm-opencl-${rocm_ver}"; then
            if [ "${SLACKY_FOOTPRINT_MODE:-enforce}" != "report" ]; then
                log_error "Footprint check failed for cachyos-rocm-opencl. Package not built."
                rm -rf "${work_dir}"
                return 1
            fi
        fi
    elif [ "${SLACKY_FOOTPRINT_MODE:-enforce}" != "report" ]; then
        log_error "Footprint check unavailable (gnomes_pacman.py not found). Package not built."
        rm -rf "${work_dir}"
        return 1
    fi

    local target_pkg="${work_dir}/cachyos-rocm-opencl-${rocm_ver}-x86_64-1_slacky.txz"
    log_info "Assembling Slackware txz package: ${target_pkg##*/}..."
    (
        cd "${staging_root}"
        # 2C: explicit root ownership in the archive
        find ./ | LC_COLLATE=C sort | sed '2,$s,^\./,,' | tar --owner=0 --group=0 --numeric-owner --mode='go+rX' --no-recursion -T - -cf - | xz -T0 -1 > "${target_pkg}" 2>/dev/null || true
    )

    # 2C: never install an archive with non-root entries
    if [ -f "${target_pkg}" ] && [ -n "$(tar --numeric-owner -tvJf "${target_pkg}" 2>/dev/null | awk '$2 != "0/0"' | head -n1)" ]; then
        log_error "cachyos-rocm-opencl package has files not owned by root:root. Not installing."
        rm -rf "${work_dir}"
        return 1
    fi

    if [ -f "${target_pkg}" ] && [ -s "${target_pkg}" ]; then
        chmod 644 "${target_pkg}"
        log_info "Installing ${target_pkg##*/}..."
        validate_privileges
        if sudo "${PKG_UPGRADE_CMD}" --reinstall --install-new "${target_pkg}"; then
            rm -rf "${work_dir}"
            log_success "$(_ ROCM_INSTALL_SUCCESS)"
        else
            log_error "Installing cachyos-rocm-opencl failed. Nothing else was changed."
            rm -rf "${work_dir}"
            return 1
        fi
    else
        log_warn "Failed to build cachyos-rocm-opencl package. Reverting staging..."
        rm -rf "${work_dir}"
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

    echo -n "• Mesa OpenCL (Rusticl): "
    if [ ! -e /etc/OpenCL/vendors/mesa.icd ] && [ ! -e /etc/OpenCL/vendors/rusticl.icd ]; then
        echo -e "${GREEN}Not present${RESET}"
    elif grep -qs 'OCL_ICD_VENDORS' /etc/profile.d/rocm.sh; then
        echo -e "${GREEN}Hidden from ROCm apps (Slackware files untouched)${RESET}"
    else
        echo -e "${YELLOW}Visible to ROCm apps (install ROCm with option 1 to hide it)${RESET}"
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
        echo -e "  \033[1;33m2.\033[0m $(_ ROCM_OPTION_MESA_STATUS)"
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
