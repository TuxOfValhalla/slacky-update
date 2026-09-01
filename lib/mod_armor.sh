#!/usr/bin/env bash
# --- [ SECURE BOOT & MOK SIGNATURE MODULE ] ---

set -euo pipefail

setup_compat_library_env() {
    local compat_dirs=(
        "/usr/share/slacky-update/lib/compat"
        "${APP_DIR}/../assets/compat"
    )
    for c in "${compat_dirs[@]}"; do
        if [ -d "$c" ] && [ -f "$c/libcrypto.so.1.1" ]; then
            if ! echo "${LD_LIBRARY_PATH:-}" | grep -q "$c"; then
                export LD_LIBRARY_PATH="${c}:${LD_LIBRARY_PATH:-}"
            fi
            break
        fi
    done
}

audit_secure_boot_readiness() {
    setup_compat_library_env
    local mokutil_bin
    mokutil_bin=$(command -v mokutil 2>/dev/null || echo "/usr/bin/mokutil")

    if [ ! -x "${mokutil_bin}" ]; then
        return 0
    fi

    if ! "${mokutil_bin}" --sb-state 2>/dev/null | grep -qi "enabled"; then
        return 0
    fi

    resolve_mok_keypair

    # If we already have a valid MOK keypair (from existing signed kernels or /etc/mok), we are ready to sign!
    if [ -n "${MOK_KEY}" ] && { [ -n "${MOK_CRT}" ] || [ -n "${MOK_DER}" ]; }; then
        return 0
    fi

    local is_enrolled=0
    if "${mokutil_bin}" --list-enrolled 2>/dev/null | grep -Ei -q "Certificate|Issuer|Subject"; then
        is_enrolled=1
    fi

    if [ -z "${MOK_CERT}" ] || [ -z "${MOK_KEY}" ] || [ "${is_enrolled}" -eq 0 ]; then
        echo -e "\n${YELLOW}${BOLD}$(_ SB_ACTIVE_NO_MOK)${RESET}"
        read -r -p "$(_ PROMPT_CREATE_MOK)" reply_mok
        reply_mok=${reply_mok:-Y}
        if [[ "$reply_mok" =~ ^[YyJjSsOo]$ ]]; then
            provision_mok_keypair
        fi
    fi
}

provision_mok_keypair() {
    validate_privileges
    local mok_dir="/etc/mok"
    sudo mkdir -p "${mok_dir}"

    local priv_key="${mok_dir}/MOK.key"
    local cert_crt="${mok_dir}/MOK.crt"
    local cert_der="${mok_dir}/MOK.der"

    if [ ! -f "${priv_key}" ] || [ ! -f "${cert_crt}" ]; then
        log_info "Generating local MOK cryptographic keypair..."
        sudo openssl req -new -x509 -newkey rsa:2048 -keyout "${priv_key}" -out "${cert_crt}" -nodes -days 3650 -subj "/CN=Slacky-Update Module Signing Key/" 2>/dev/null
        sudo openssl x509 -outform DER -in "${cert_crt}" -out "${cert_der}" 2>/dev/null
        sudo chmod 600 "${priv_key}"
        sudo chmod 644 "${cert_crt}" "${cert_der}"
    fi

    if [ -f "${cert_der}" ]; then
        log_info "Importing MOK certificate to UEFI keyring..."
        echo -e "${CYAN}Set a temporary enrollment password (e.g. 1234) when prompted:${RESET}"
        local mokutil_bin
        mokutil_bin=$(command -v mokutil 2>/dev/null || echo "/usr/bin/mokutil")
        sudo "${mokutil_bin}" --import "${cert_der}" || true

        echo ""
        echo -e "${CYAN}============================================================${RESET}"
        echo -e "${YELLOW}${BOLD}$(_ MOK_ENROLL_HEADER)${RESET}"
        echo -e "  $(_ MOK_ENROLL_STEP1)"
        echo -e "  $(_ MOK_ENROLL_STEP2)"
        echo -e "  $(_ MOK_ENROLL_STEP3)"
        echo -e "  $(_ MOK_ENROLL_STEP4)"
        echo -e "${CYAN}============================================================${RESET}"
        echo ""
    fi

    resolve_mok_keypair
}

sign_modules_for_kernel() {
    local target_kver="$1"
    resolve_mok_keypair
    local cert_for_sign="${MOK_CRT:-${MOK_DER}}"

    if [ -z "${cert_for_sign}" ] || [ -z "${MOK_KEY}" ]; then
        return 0
    fi

    local sign_bin=""
    local candidates=(
        "/lib/modules/${target_kver}/build/scripts/sign-file"
        "/usr/src/linux-headers-${target_kver}/scripts/sign-file"
        "/usr/src/linux-${target_kver}/scripts/sign-file"
        /usr/lib/modules/*/build/scripts/sign-file
        /lib/modules/*/build/scripts/sign-file
        "/usr/bin/kmodsign"
    )

    for c in "${candidates[@]}"; do
        if [ -x "$c" ]; then
            sign_bin="$c"
            break
        fi
    done

    if [ -z "${sign_bin}" ]; then
        return 0
    fi

    local search_dirs=()
    [ -d "/lib/modules/${target_kver}" ] && search_dirs+=("/lib/modules/${target_kver}")
    [ -d "/usr/lib/modules/${target_kver}" ] && search_dirs+=("/usr/lib/modules/${target_kver}")
    [ ${#search_dirs[@]} -gt 0 ] || return 0

    local found_modules=0
    while IFS= read -r mod; do
        [ -f "${mod}" ] || continue
        found_modules=1
        if [[ "${mod}" =~ \.ko\.zst$ ]]; then
            local raw_mod="${mod%.zst}"
            if sudo unzstd -f -q "${mod}" -o "${raw_mod}" 2>/dev/null; then
                sudo "${sign_bin}" sha256 "${MOK_KEY}" "${cert_for_sign}" "${raw_mod}" 2>/dev/null || true
                sudo zstd -f -q --rm "${raw_mod}" -o "${mod}" 2>/dev/null || true
            fi
        elif [[ "${mod}" =~ \.ko\.xz$ ]]; then
            local raw_mod="${mod%.xz}"
            if sudo unxz -f -q -c "${mod}" > "${raw_mod}" 2>/dev/null; then
                sudo "${sign_bin}" sha256 "${MOK_KEY}" "${cert_for_sign}" "${raw_mod}" 2>/dev/null || true
                sudo xz -f -q "${raw_mod}" 2>/dev/null || true
            fi
        elif [[ "${mod}" =~ \.ko\.gz$ ]]; then
            local raw_mod="${mod%.gz}"
            if sudo gunzip -f -q -c "${mod}" > "${raw_mod}" 2>/dev/null; then
                sudo "${sign_bin}" sha256 "${MOK_KEY}" "${cert_for_sign}" "${raw_mod}" 2>/dev/null || true
                sudo gzip -f -q "${raw_mod}" 2>/dev/null || true
            fi
        elif [[ "${mod}" =~ \.ko$ ]]; then
            sudo "${sign_bin}" sha256 "${MOK_KEY}" "${cert_for_sign}" "${mod}" 2>/dev/null || true
        fi
    done < <(find "${search_dirs[@]}" -name "nvidia*.ko*" 2>/dev/null || true)

    if [ "${found_modules}" -eq 1 ]; then
        log_success "Applied MOK signature to kernel modules for: ${target_kver}"
    fi
}

sign_kernel_images() {
    validate_privileges
    resolve_mok_keypair

    if [ -z "${MOK_CRT}" ] || [ -z "${MOK_KEY}" ]; then
        log_info "No MOK PEM certificate/key pair configured. Skipping kernel image signing."
        return 0
    fi

    local sbsign_bin
    sbsign_bin=$(command -v sbsign 2>/dev/null || echo "/usr/bin/sbsign")
    local sbverify_bin
    sbverify_bin=$(command -v sbverify 2>/dev/null || echo "/usr/bin/sbverify")

    if [ ! -x "${sbsign_bin}" ]; then
        log_warn "sbsign utility (sbsigntools) not found. Skipping kernel image signing."
        return 0
    fi

    log_info "Verifying and signing kernel images in /boot..."

    for kernel in /boot/vmlinuz-*; do
        [ -f "${kernel}" ] || continue
        [ -L "${kernel}" ] && continue

        local k_base
        k_base=$(basename "${kernel}")

        local needs_sign=1
        if [ -x "${sbverify_bin}" ]; then
            if "${sbverify_bin}" --cert "${MOK_CRT}" "${kernel}" >/dev/null 2>&1; then
                needs_sign=0
                log_info "Kernel ${k_base} is already signed with active MOK."
            fi
        fi

        if [ "${needs_sign}" -eq 1 ]; then
            log_info "Signing kernel image: ${k_base}..."
            local signed_tmp="${kernel}.signed"
            if sudo "${sbsign_bin}" --key "${MOK_KEY}" --cert "${MOK_CRT}" "${kernel}" --output "${signed_tmp}" 2>/dev/null; then
                sudo mv -f "${signed_tmp}" "${kernel}"
                sudo chmod 0644 "${kernel}"
                log_success "Applied MOK signature to kernel image: ${k_base}"
            else
                sudo rm -f "${signed_tmp}" 2>/dev/null || true
                log_warn "Failed to sign kernel image: ${k_base}"
            fi
        fi
    done
}

enforce_secure_boot_armor() {
    validate_privileges
    audit_secure_boot_readiness
    resolve_mok_keypair

    if [ -z "${MOK_KEY}" ] || { [ -z "${MOK_CRT}" ] && [ -z "${MOK_DER}" ]; }; then
        log_info "No MOK keypair configured. Skipping Secure Boot signing."
        return 0
    fi

    log_info "MOK keypair located (${MOK_CRT:-${MOK_DER}}). Enforcing Secure Boot armor..."

    # 1. Sign kernel binaries in /boot
    sign_kernel_images

    # 2. Sign kernel modules in /lib/modules
    if [ -d "/lib/modules" ]; then
        for kdir in /lib/modules/*; do
            [ -d "${kdir}" ] || continue
            local kver
            kver=$(basename "${kdir}")
            sign_modules_for_kernel "${kver}"
        done
    fi

    # 3. Silent Self-Heal Guard: Verify EFI bootloader integrity
    self_heal_secure_boot_guard
}

verify_secure_boot_status_interactive() {
    log_info "Scanning UEFI Secure Boot status and key armor..."
    local mokutil_bin
    mokutil_bin=$(command -v mokutil 2>/dev/null || echo "/usr/bin/mokutil")
    local sbverify_bin
    sbverify_bin=$(command -v sbverify 2>/dev/null || echo "/usr/bin/sbverify")

    if [ -x "${mokutil_bin}" ]; then
        local sb_status
        sb_status=$("${mokutil_bin}" --sb-state 2>/dev/null || echo "Unknown")
        echo -e "  • ${BOLD}UEFI Secure Boot State:${RESET} ${CYAN}${sb_status}${RESET}"
    fi

    resolve_mok_keypair
    if [ -n "${MOK_CRT}" ] && [ -n "${MOK_KEY}" ]; then
        echo -e "  • ${BOLD}Active MOK Keypair:${RESET} ${GREEN}${MOK_CRT}${RESET} / ${GREEN}${MOK_KEY}${RESET}"
    elif [ -n "${MOK_DER}" ] && [ -n "${MOK_KEY}" ]; then
        echo -e "  • ${BOLD}Active MOK Keypair:${RESET} ${GREEN}${MOK_DER}${RESET} / ${GREEN}${MOK_KEY}${RESET}"
    else
        echo -e "  • ${BOLD}Active MOK Keypair:${RESET} ${YELLOW}None configured in /etc/mok/${RESET}"
    fi

    echo -e "\n${BOLD}Kernel Signature Audit (/boot):${RESET}"
    for k in /boot/vmlinuz-*; do
        [ -f "$k" ] || continue
        [ -L "$k" ] && continue
        local k_base
        k_base=$(basename "$k")
        if [ -x "${sbverify_bin}" ] && [ -n "${MOK_CRT}" ]; then
            if "${sbverify_bin}" --cert "${MOK_CRT}" "$k" >/dev/null 2>&1; then
                printf "  • %-35s : ${GREEN}[SIGNED & VERIFIED]${RESET}\n" "${k_base}"
            else
                printf "  • %-35s : ${YELLOW}[UNSIGNED / FOREIGN KEY]${RESET}\n" "${k_base}"
            fi
        else
            printf "  • %-35s : [UNCHECKED]\n" "${k_base}"
        fi
    done

    echo -e "\n${BOLD}NVIDIA Kernel Module Audit (/lib/modules):${RESET}"
    local found_nv=0
    for mod in $(find /lib/modules/ -name "nvidia.ko*" 2>/dev/null | sort -u); do
        [ -f "$mod" ] || continue
        found_nv=1
        local m_kver
        m_kver=$(echo "$mod" | cut -d'/' -f4)
        local signer
        signer=$(modinfo -F signer "$mod" 2>/dev/null || echo "None")
        if [ -n "$signer" ] && [ "$signer" != "None" ]; then
            printf "  • %-35s : ${GREEN}[SIGNED by: %s]${RESET}\n" "${m_kver}" "${signer}"
        else
            printf "  • %-35s : ${YELLOW}[UNSIGNED]${RESET}\n" "${m_kver}"
        fi
    done
    if [ "$found_nv" -eq 0 ]; then
        echo -e "  • No NVIDIA kernel modules found."
    fi
    echo ""
}

detect_esp_mount() {
    local detected
    detected=$(findmnt -n -o TARGET -t vfat 2>/dev/null | grep -E '^/(boot/efi|boot/EFI|efi|boot)$' | head -n1 || true)
    if [ -n "${detected}" ] && [ -d "${detected}" ]; then
        echo "${detected}"
        return 0
    fi

    for candidate in /boot/efi /boot/EFI /efi /boot; do
        if mountpoint -q "${candidate}" 2>/dev/null || [ -d "${candidate}/EFI" ]; then
            echo "${candidate}"
            return 0
        fi
    done

    echo "/boot/efi"
}

get_bootloader_uuid_and_prefix() {
    local boot_uuid=""
    local boot_prefix="/boot/grub"

    if mountpoint -q "/boot" 2>/dev/null; then
        boot_uuid=$(findmnt -n -o UUID /boot 2>/dev/null || true)
        boot_prefix="/grub"
    fi

    if [ -z "${boot_uuid}" ]; then
        boot_uuid=$(findmnt -n -o UUID / 2>/dev/null || blkid -s UUID -o value "$(findmnt -n -o SOURCE / 2>/dev/null)" 2>/dev/null || true)
        boot_prefix="/boot/grub"
    fi

    echo "${boot_uuid} ${boot_prefix}"
}

deploy_maximum_armor_interactive() {
    local is_silent="${1:-}"
    validate_privileges
    setup_compat_library_env

    if [ "${is_silent}" != "--silent" ]; then
        echo -e "\n${CYAN}${BOLD}$(_ MOK_OPTION_DEPLOY_SHIM)${RESET}"
        echo -n "$(_ DEPLOY_SHIM_CONFIRM)"
        read -r reply_deploy
        reply_deploy=${reply_deploy:-Y}
        if [[ ! "$reply_deploy" =~ ^[YyJjSsOo]$ ]]; then
            log_info "Operation cancelled."
            return 0
        fi
    fi

    log_info "Locating EFI System Partition (ESP)..."
    local esp_mount
    esp_mount=$(detect_esp_mount)

    if [ ! -d "${esp_mount}" ]; then
        log_warn "EFI System Partition not detected. Aborting."
        return 1
    fi

    local target_efi_dir="${esp_mount}/EFI/Slackware"
    sudo mkdir -p "${target_efi_dir}"

    # Search for Microsoft-signed shimx64.efi & mmx64.efi candidates
    local shim_src=""
    local mm_src=""
    local grub_src=""

    local shim_candidates=(
        "${APP_DIR}/../assets/efi/shimx64.efi"
        "/usr/share/slacky-update/efi/shimx64.efi"
        "${esp_mount}/EFI/Slackware/shimx64.efi"
        "${esp_mount}/EFI/fedora/shimx64.efi"
        "${esp_mount}/EFI/debian/shimx64.efi"
        "${esp_mount}/EFI/ubuntu/shimx64.efi"
        "${esp_mount}/EFI/BOOT/BOOTX64.EFI"
        "/usr/share/shim-signed/shimx64.efi"
    )
    for s in "${shim_candidates[@]}"; do
        if [ -f "$s" ]; then
            shim_src="$s"
            break
        fi
    done

    local mm_candidates=(
        "${APP_DIR}/../assets/efi/mmx64.efi"
        "/usr/share/slacky-update/efi/mmx64.efi"
        "${esp_mount}/EFI/Slackware/mmx64.efi"
        "${esp_mount}/EFI/fedora/mmx64.efi"
        "${esp_mount}/EFI/debian/mmx64.efi"
        "${esp_mount}/EFI/ubuntu/mmx64.efi"
    )
    for m in "${mm_candidates[@]}"; do
        if [ -f "$m" ]; then
            mm_src="$m"
            break
        fi
    done

    local grub_candidates=(
        "${APP_DIR}/../assets/efi/grubx64.efi"
        "/usr/share/slacky-update/efi/grubx64.efi"
        "${esp_mount}/EFI/Slackware/grubx64.efi"
        "/boot/grub/x86_64-efi/core.efi"
        "/boot/grub/x86_64-efi/grub.efi"
        "${esp_mount}/EFI/fedora/grubx64.efi"
        "${esp_mount}/EFI/debian/grubx64.efi"
    )
    for g in "${grub_candidates[@]}"; do
        if [ -f "$g" ]; then
            grub_src="$g"
            break
        fi
    done

    if [ -n "${shim_src}" ] && [ "${shim_src}" != "${target_efi_dir}/shimx64.efi" ]; then
        log_info "Deploying Microsoft-signed Shim (${shim_src}) -> ${target_efi_dir}/shimx64.efi..."
        sudo cp -af "${shim_src}" "${target_efi_dir}/shimx64.efi"
    fi

    if [ -n "${mm_src}" ] && [ "${mm_src}" != "${target_efi_dir}/mmx64.efi" ]; then
        log_info "Deploying MokManager (${mm_src}) -> ${target_efi_dir}/mmx64.efi..."
        sudo cp -af "${mm_src}" "${target_efi_dir}/mmx64.efi"
    fi

    if [ -n "${grub_src}" ] && [ "${grub_src}" != "${target_efi_dir}/grubx64.efi" ]; then
        log_info "Deploying GRUB binary (${grub_src}) -> ${target_efi_dir}/grubx64.efi..."
        sudo cp -af "${grub_src}" "${target_efi_dir}/grubx64.efi"
    fi

    # Create early grub.cfg redirector with Slackware root/boot UUID & prefix
    local root_uuid boot_prefix
    read -r root_uuid boot_prefix <<< "$(get_bootloader_uuid_and_prefix)"

    if [ -n "${root_uuid}" ]; then
        log_info "Configuring early GRUB loader for Slackware (UUID=${root_uuid}, prefix=${boot_prefix})..."
        cat << GCFG_EOF | sudo tee "${target_efi_dir}/grub.cfg" >/dev/null
search --no-floppy --fs-uuid --set=root ${root_uuid}
set prefix=(\$root)${boot_prefix}
configfile \$prefix/grub.cfg
GCFG_EOF
        sudo chmod 644 "${target_efi_dir}/grub.cfg"
    fi

    # Register UEFI boot entry with efibootmgr
    local efibootmgr_bin
    efibootmgr_bin=$(command -v efibootmgr 2>/dev/null || echo "/usr/sbin/efibootmgr")
    if [ -x "${efibootmgr_bin}" ]; then
        local esp_source
        esp_source=$(findmnt -n -o SOURCE "${esp_mount}" 2>/dev/null || true)
        if [ -n "${esp_source}" ]; then
            local esp_disk=""
            local esp_part=""
            if [[ "${esp_source}" =~ (/dev/nvme[0-9]+n[0-9]+)p([0-9]+) ]]; then
                esp_disk="${BASH_REMATCH[1]}"
                esp_part="${BASH_REMATCH[2]}"
            elif [[ "${esp_source}" =~ (/dev/[a-z]+)([0-9]+) ]]; then
                esp_disk="${BASH_REMATCH[1]}"
                esp_part="${BASH_REMATCH[2]}"
            fi

            if [ -n "${esp_disk}" ] && [ -n "${esp_part}" ]; then
                log_info "Registering UEFI Boot Entry: Slackware (Secure Boot) on ${esp_disk} partition ${esp_part}..."
                sudo "${efibootmgr_bin}" -c -d "${esp_disk}" -p "${esp_part}" -L "Slackware (Secure Boot)" -l "\\EFI\\Slackware\\shimx64.efi" >/dev/null 2>&1 || true
            fi
        fi
    fi

    # Ensure MOK keypair exists and sign everything
    resolve_mok_keypair
    if [ -z "${MOK_KEY}" ] || { [ -z "${MOK_CRT}" ] && [ -z "${MOK_DER}" ]; }; then
        provision_mok_keypair
    fi

    enforce_secure_boot_armor
    if [ "${is_silent}" != "--silent" ]; then
        log_success "$(_ DEPLOY_SHIM_SUCCESS)"
    fi
}

self_heal_secure_boot_guard() {
    # Guard runs 100% silent unless corruption or missing files are detected
    local esp_mount
    esp_mount=$(detect_esp_mount)
    [ -d "${esp_mount}/EFI/Slackware" ] || return 0

    local target_efi_dir="${esp_mount}/EFI/Slackware"
    local needs_heal=0

    if [ ! -s "${target_efi_dir}/shimx64.efi" ] || [ ! -s "${target_efi_dir}/grubx64.efi" ]; then
        needs_heal=1
    fi

    if [ ! -s "${target_efi_dir}/grub.cfg" ]; then
        needs_heal=1
    fi

    if [ "${needs_heal}" -eq 1 ]; then
        log_warn "$(_ SB_SELF_HEAL_TRIGGERED)"
        deploy_maximum_armor_interactive --silent
    fi
}

fix_my_damn_secure_boot_wizard() {
    validate_privileges
    setup_compat_library_env

    echo ""
    echo -e "${CYAN}============================================================${RESET}"
    echo -e "${YELLOW}${BOLD}$(_ MOK_OPTION_FIX_MY_SB)${RESET}"
    echo -e "${CYAN}============================================================${RESET}"
    echo -e "$(_ SB_FIX_WIZARD_DESC)"
    echo ""
    echo -n "$(_ PROMPT_CONFIRM_FIX_SB)"
    read -r reply_fix
    reply_fix=${reply_fix:-Y}
    if [[ ! "$reply_fix" =~ ^[YyJjSsOo]$ ]]; then
        log_info "Operation cancelled."
        return 0
    fi

    echo ""
    log_info "Running Pre-Flight Tool & Cryptographic Audit..."
    local missing_tools=()

    command -v openssl >/dev/null 2>&1 || missing_tools+=("openssl (Slackware core: a/openssl)")
    command -v efibootmgr >/dev/null 2>&1 || missing_tools+=("efibootmgr (Slackware core: ap/efibootmgr)")
    command -v mokutil >/dev/null 2>&1 || missing_tools+=("mokutil (Alien Bob / SBo: mokutil)")
    command -v sbsign >/dev/null 2>&1 || missing_tools+=("sbsigntools (Alien Bob / SBo: sbsigntools)")

    if [ "${#missing_tools[@]}" -gt 0 ]; then
        log_warn "Missing required packages for automated Secure Boot setup:"
        for t in "${missing_tools[@]}"; do
            echo -e "  • ${YELLOW}${t}${RESET}"
        done
        echo ""
        echo "Please install missing packages before running 1-Click Secure Boot Setup."
        return 1
    fi

    log_success "Pre-flight audit passed! All cryptographic & bootloader tools detected."

    # Phase 1: Deploy Microsoft-signed Shim & signed GRUB
    log_info "Phase 1: Deploying Microsoft-signed Shim, MokManager and GRUB to /boot/efi/EFI/Slackware..."
    deploy_maximum_armor_interactive --silent

    # Phase 2: Rebuild DKMS NVIDIA modules (if present)
    if [ "${HAS_NVIDIA}" = "true" ] && command -v build_nvidia_modules >/dev/null 2>&1; then
        log_info "Phase 2: Building NVIDIA DKMS kernel modules..."
        for kdir in /lib/modules/*; do
            [ -d "${kdir}" ] || continue
            local kver
            kver=$(basename "${kdir}")
            build_nvidia_modules "${kver}"
        done
    fi

    # Phase 3: Generate high-performance Dracut initramfs for all kernels and purge old 11MB initrd
    log_info "Phase 3: Generating Dracut initramfs images for all installed kernels..."
    generate_kernel_initramfs "ALL"

    # Phase 4: Sign all kernels and modules
    log_info "Phase 4: Enforcing cryptographic MOK signatures on all kernels and modules..."
    enforce_secure_boot_armor

    # Phase 5: Synchronize GRUB bootloader menu
    log_info "Phase 5: Synchronizing GRUB menu configuration..."
    sync_bootloader_configuration "$(uname -r)"

    echo ""
    log_success "$(_ SB_FIX_WIZARD_SUCCESS)"
    echo ""
    echo -e "${CYAN}============================================================${RESET}"
    echo -e "${YELLOW}${BOLD}$(_ MOK_ENROLL_HEADER)${RESET}"
    echo -e "  $(_ MOK_ENROLL_STEP1)"
    echo -e "  $(_ MOK_ENROLL_STEP2)"
    echo -e "  $(_ MOK_ENROLL_STEP3)"
    echo -e "  $(_ MOK_ENROLL_STEP4)"
    echo -e "${CYAN}============================================================${RESET}"
    echo ""
}

manage_armor_interactive() {
    validate_privileges
    setup_compat_library_env

    while true; do
        echo ""
        echo -e "${CYAN}============================================================${RESET}"
        echo -e "${YELLOW}${BOLD}$(_ MOK_MENU_TITLE)${RESET}"
        echo -e "${CYAN}============================================================${RESET}"
        echo -e "  $(_ MOK_OPTION_VERIFY)"
        echo -e "  $(_ MOK_OPTION_FIX_MY_SB)"
        echo -e "  $(_ MOK_OPTION_DEPLOY_SHIM)"
        echo -e "  $(_ MOK_OPTION_CREATE_MOK)"
        echo -e "  $(_ MOK_OPTION_SIGN_ALL)"
        echo -e "  $(_ MOK_OPTION_RETURN)"
        echo ""
        echo -n "$(_ SELECT_OPERATION_RANGE range="1-6") "
        read -r achoice || achoice="6"

        case "${achoice}" in
            1)
                echo ""
                verify_secure_boot_status_interactive
                ;;
            2)
                echo ""
                fix_my_damn_secure_boot_wizard
                ;;
            3)
                echo ""
                deploy_maximum_armor_interactive
                ;;
            4)
                echo ""
                provision_mok_keypair
                ;;
            5)
                echo ""
                enforce_secure_boot_armor
                ;;
            6)
                return 0
                ;;
            *)
                echo -e "\n${YELLOW}$(_ INVALID_SELECTION)${RESET}"
                sleep 1
                ;;
        esac
    done
}
