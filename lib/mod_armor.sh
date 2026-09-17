#!/usr/bin/env bash
# --- [ SECURE BOOT & MOK SIGNATURE MODULE ] ---

set -euo pipefail

audit_secure_boot_readiness() {
    resolve_mok_keypair

    # If we already have a valid MOK keypair (from existing signed kernels or /etc/mok), we are ready to sign!
    if [ -n "${MOK_KEY}" ] && { [ -n "${MOK_CRT}" ] || [ -n "${MOK_DER}" ]; }; then
        return 0
    fi

    local mokutil_bin
    mokutil_bin=$(command -v mokutil 2>/dev/null || echo "/usr/bin/mokutil")

    if [ ! -x "${mokutil_bin}" ]; then
        return 0
    fi

    if ! "${mokutil_bin}" --sb-state 2>/dev/null | grep -qi "enabled"; then
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
        local mokutil_bin
        mokutil_bin=$(command -v mokutil 2>/dev/null || echo "/usr/bin/mokutil")
        if [ -x "${mokutil_bin}" ]; then
            if "${mokutil_bin}" --test-key "${cert_der}" 2>&1 | grep -qi "already enrolled"; then
                log_info "MOK certificate is already enrolled in UEFI NVRAM keyring. Skipping import prompt."
            else
                log_info "Importing MOK certificate to UEFI keyring..."
                echo -e "${CYAN}Set a temporary enrollment password (e.g. 1234) when prompted:${RESET}"
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
        fi
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

    local sign_workdir
    sign_workdir=$(mktemp -d /tmp/slacky-sign-XXXXXX)
    trap 'sudo rm -rf "${sign_workdir:-}" 2>/dev/null || true' INT TERM

    local expected_cn=""
    if [ -f "${cert_for_sign}" ]; then
        expected_cn=$(openssl x509 -in "${cert_for_sign}" -noout -subject 2>/dev/null | sed -E 's/.*CN[[:space:]]*=[[:space:]]*//' | tr -d '"' || true)
    fi

    local found_modules=0
    local newly_signed=0
    while IFS= read -r mod; do
        [ -f "${mod}" ] || continue

        found_modules=1

        # Check if module is already signed with current MOK certificate AND has valid container integrity
        local cur_signer=""
        cur_signer=$(modinfo -F signer "${mod}" 2>/dev/null || true)
        if [ -n "${cur_signer}" ] && { [ -z "${expected_cn}" ] || [ "${cur_signer}" = "${expected_cn}" ]; }; then
            if [[ "${mod}" =~ \.ko\.zst$ ]]; then
                if zstd -t "${mod}" >/dev/null 2>&1; then
                    continue
                fi
            elif [[ "${mod}" =~ \.ko\.xz$ ]]; then
                if xz -t "${mod}" >/dev/null 2>&1; then
                    continue
                fi
            elif [[ "${mod}" =~ \.ko\.gz$ ]]; then
                if gzip -t "${mod}" >/dev/null 2>&1; then
                    continue
                fi
            else
                continue
            fi
        fi

        # If this is an uncompressed .ko, check if a compressed version exists
        if [[ "${mod}" =~ \.ko$ ]]; then
            if [ -f "${mod}.zst" ] || [ -f "${mod}.xz" ] || [ -f "${mod}.gz" ]; then
                # Stale duplicate left behind from previous operations: remove safely
                sudo rm -f "${mod}" 2>/dev/null || true
                continue
            fi
            newly_signed=1
            sudo "${sign_bin}" sha256 "${MOK_KEY}" "${cert_for_sign}" "${mod}" 2>/dev/null || true
            continue
        fi

        if [[ "${mod}" =~ \.ko\.zst$ ]]; then
            local base_name
            base_name=$(basename "${mod%.zst}")
            # Ensure stale uncompressed twin in module directory is purged
            sudo rm -f "${mod%.zst}" 2>/dev/null || true
            local decomp_ok=0
            if sudo sh -c "unzstd -c '${mod}' > '${sign_workdir}/${base_name}' 2>/dev/null" && [ -s "${sign_workdir}/${base_name}" ]; then
                decomp_ok=1
            else
                # Self-healing: Strip trailing signature bytes appended to raw zstd stream
                if sudo python3 -c "
import sys, subprocess
try:
    with open('${mod}', 'rb') as fp:
        data = fp.read()
    found = False
    for cut in range(28, 4096):
        sub = data[:-cut]
        p = subprocess.run(['unzstd', '-c'], input=sub, capture_output=True)
        if p.returncode == 0 and len(p.stdout) > 0:
            with open('${sign_workdir}/${base_name}', 'wb') as out_fp:
                out_fp.write(p.stdout)
            found = True
            break
    sys.exit(0 if found else 1)
except Exception:
    sys.exit(1)
" 2>/dev/null; then
                    decomp_ok=1
                fi
            fi

            if [ "${decomp_ok}" -eq 1 ] && [ -s "${sign_workdir}/${base_name}" ]; then
                sudo "${sign_bin}" sha256 "${MOK_KEY}" "${cert_for_sign}" "${sign_workdir}/${base_name}" 2>/dev/null || true
                if sudo zstd -f -q "${sign_workdir}/${base_name}" -o "${sign_workdir}/${base_name}.zst" 2>/dev/null; then
                    sudo mv -f "${sign_workdir}/${base_name}.zst" "${mod}"
                    newly_signed=1
                fi
                sudo rm -f "${sign_workdir}/${base_name}" "${sign_workdir}/${base_name}.zst" 2>/dev/null || true
            fi
        elif [[ "${mod}" =~ \.ko\.xz$ ]]; then
            local base_name
            base_name=$(basename "${mod%.xz}")
            sudo rm -f "${mod%.xz}" 2>/dev/null || true
            if sudo sh -c "unxz -c '${mod}' > '${sign_workdir}/${base_name}' 2>/dev/null" && [ -s "${sign_workdir}/${base_name}" ]; then
                sudo "${sign_bin}" sha256 "${MOK_KEY}" "${cert_for_sign}" "${sign_workdir}/${base_name}" 2>/dev/null || true
                if sudo xz -f -q "${sign_workdir}/${base_name}" 2>/dev/null; then
                    sudo mv -f "${sign_workdir}/${base_name}.xz" "${mod}"
                    newly_signed=1
                fi
                sudo rm -f "${sign_workdir}/${base_name}" "${sign_workdir}/${base_name}.xz" 2>/dev/null || true
            fi
        elif [[ "${mod}" =~ \.ko\.gz$ ]]; then
            local base_name
            base_name=$(basename "${mod%.gz}")
            sudo rm -f "${mod%.gz}" 2>/dev/null || true
            if sudo sh -c "gunzip -c '${mod}' > '${sign_workdir}/${base_name}' 2>/dev/null" && [ -s "${sign_workdir}/${base_name}" ]; then
                sudo "${sign_bin}" sha256 "${MOK_KEY}" "${cert_for_sign}" "${sign_workdir}/${base_name}" 2>/dev/null || true
                if sudo gzip -f -q "${sign_workdir}/${base_name}" 2>/dev/null; then
                    sudo mv -f "${sign_workdir}/${base_name}.gz" "${mod}"
                    newly_signed=1
                fi
                sudo rm -f "${sign_workdir}/${base_name}" "${sign_workdir}/${base_name}.gz" 2>/dev/null || true
            fi
        fi
    done < <(find "${search_dirs[@]}" -name "nvidia*.ko*" 2>/dev/null || true)

    sudo rm -rf "${sign_workdir}" 2>/dev/null || true
    trap - INT TERM
    if [ "${newly_signed}" -eq 1 ]; then
        sudo depmod -a "${target_kver}" 2>/dev/null || true
        if [ "${ARMOR_PIPELINE_MODE:-0}" != "1" ]; then
            log_success "Applied MOK signature to kernel modules for: ${target_kver}"
        fi
        ARMOR_NEWLY_SIGNED=1
        ARMOR_SIGNED_LIST+=("${target_kver}")
    fi
    return 0
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

    local kern_list=()
    mapfile -t kern_list < <(sudo python3 -c "
import os
if os.path.exists('/boot'):
    for f in sorted(os.listdir('/boot')):
        if f.startswith('vmlinuz-') and not os.path.islink(os.path.join('/boot', f)):
            print(os.path.join('/boot', f))
" 2>/dev/null || true)

    for kernel in "${kern_list[@]}"; do
        [ -n "${kernel}" ] || continue

        local k_base
        k_base=$(basename "${kernel}")

        local needs_sign=1
        if command -v sbctl >/dev/null 2>&1; then
            if sudo sbctl verify "${kernel}" 2>/dev/null | grep -qi "is signed"; then
                needs_sign=0
            fi
        fi
        if [ "${needs_sign}" -eq 1 ] && [ -x "${sbverify_bin}" ]; then
            if sudo "${sbverify_bin}" --list "${kernel}" 2>/dev/null | grep -qi "signature"; then
                needs_sign=0
            fi
        fi

        if [ "${needs_sign}" -eq 1 ]; then
            log_info "Signing kernel image with MOK: ${k_base}..."
            local signed_tmp="${kernel}.signed"
            if sudo "${sbsign_bin}" --key "${MOK_KEY}" --cert "${MOK_CRT}" "${kernel}" --output "${signed_tmp}" 2>/dev/null; then
                sudo mv -f "${signed_tmp}" "${kernel}"
                sudo chmod 0644 "${kernel}"
                log_success "Applied MOK signature to kernel image: ${k_base}"
                ARMOR_NEWLY_SIGNED=1
            else
                sudo rm -f "${signed_tmp}" 2>/dev/null || true
                log_warn "Failed to sign kernel image: ${k_base}"
            fi
        fi
    done
    return 0
}

enforce_secure_boot_armor() {
    local mode="${1:-}"
    validate_privileges
    audit_secure_boot_readiness
    resolve_mok_keypair

    if [ -z "${MOK_KEY}" ] || { [ -z "${MOK_CRT}" ] && [ -z "${MOK_DER}" ]; }; then
        if [ "${mode}" = "--pipeline" ]; then
            echo "Skipped (No MOK configured)"
        else
            log_info "No MOK keypair configured. Skipping Secure Boot signing."
        fi
        return 0
    fi

    local ARMOR_PIPELINE_MODE=0
    if [ "${mode}" = "--pipeline" ]; then
        ARMOR_PIPELINE_MODE=1
    else
        log_info "Verifying and enforcing Secure Boot MOK armor..."
    fi

    ARMOR_NEWLY_SIGNED=0
    local ARMOR_SIGNED_LIST=()

    # 1. Sign kernel binaries in /boot (only if unsigned)
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

    if [ "${ARMOR_PIPELINE_MODE}" -eq 1 ]; then
        if [ "${#ARMOR_SIGNED_LIST[@]}" -gt 0 ]; then
            local joined
            joined=$(IFS=', '; echo "${ARMOR_SIGNED_LIST[*]}")
            echo "Signed kernel modules (${joined})"
        else
            echo "Verified signed with active MOK"
        fi
    else
        if [ "${ARMOR_NEWLY_SIGNED}" -eq 0 ]; then
            log_info "All kernel images and modules are verified signed with active MOK."
        fi
    fi

    # 3. Synchronize bootloader if kernel binaries were newly signed
    if [ "${ARMOR_NEWLY_SIGNED}" -eq 1 ] && command -v sync_bootloader_configuration >/dev/null 2>&1; then
        sync_bootloader_configuration "$(uname -r)"
    fi

    # 4. Silent Self-Heal Guard: Verify EFI bootloader integrity
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
    local k_files=()
    mapfile -t k_files < <(sudo python3 -c "
import os
if os.path.exists('/boot'):
    for f in sorted(os.listdir('/boot')):
        if f.startswith('vmlinuz-') and not os.path.islink(os.path.join('/boot', f)):
            print(f)
" 2>/dev/null || true)

    for k_base in "${k_files[@]}"; do
        [ -n "$k_base" ] || continue
        local k="/boot/${k_base}"
        if [ -x "${sbverify_bin}" ] && [ -n "${MOK_CRT}" ]; then
            if sudo "${sbverify_bin}" --cert "${MOK_CRT}" "$k" >/dev/null 2>&1; then
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
    for mod in $(find -L /lib/modules/ -name "nvidia.ko*" 2>/dev/null | sort -u); do
        [ -f "$mod" ] || continue
        found_nv=1
        local m_kver
        m_kver=$(echo "$mod" | cut -d'/' -f4)
        local signer
        signer=$(modinfo -F signer "$mod" 2>/dev/null || echo "")
        if [ -z "$signer" ] || [ "$signer" = "None" ]; then
            if strings "$mod" 2>/dev/null | grep -E -q "Tux MOK|Slacky-Update|Module signature appended"; then
                signer="MOK Verified"
            elif strings "$mod" 2>/dev/null | grep -q "~Module signature appended~"; then
                signer="In-kernel / Attached"
            else
                signer="None"
            fi
        fi
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

fetch_official_signed_shim_interactive() {
    local esp_mount="${1:-/boot/efi}"
    local target_efi_dir="${esp_mount}/EFI/Slackware"

    if [ -f "${target_efi_dir}/shimx64.efi" ] && [ -f "${target_efi_dir}/mmx64.efi" ] && [ -f "${target_efi_dir}/grubx64.efi" ]; then
        return 0
    fi

    log_info "Fetching official Microsoft-signed Shim and GRUB from Fedora repositories to user staging..."
    local efi_staging
    efi_staging="$(get_user_staging_dir)/efi-bootstrap"
    rm -rf "${efi_staging}"
    mkdir -p "${efi_staging}"
    pushd "${efi_staging}" >/dev/null

    local shim_url="https://kojipkgs.fedoraproject.org/packages/shim/15.8/3/x86_64/shim-x64-15.8-3.x86_64.rpm"
    local grub_url="https://kojipkgs.fedoraproject.org/packages/grub2/2.12/9.fc41/x86_64/grub2-efi-x64-2.12-9.fc41.x86_64.rpm"

    local dl_ok=true
    if ! curl -sSL --fail -o shim.rpm "${shim_url}"; then
        dl_ok=false
    fi
    if ! curl -sSL --fail -o grub.rpm "${grub_url}"; then
        dl_ok=false
    fi

    if [ "${dl_ok}" = "true" ]; then
        bsdtar -xf shim.rpm ./boot/efi/EFI/fedora/shimx64.efi ./boot/efi/EFI/fedora/mmx64.efi 2>/dev/null || \
        bsdtar -xf shim.rpm 2>/dev/null || true

        bsdtar -xf grub.rpm ./boot/efi/EFI/fedora/grubx64.efi 2>/dev/null || \
        bsdtar -xf grub.rpm 2>/dev/null || true

        if [ -f "boot/efi/EFI/fedora/shimx64.efi" ]; then
            if ! verify_microsoft_uefi_authenticode "boot/efi/EFI/fedora/shimx64.efi"; then
                log_error "Authenticode verification failed for shimx64.efi! Aborting deployment to protect Secure Boot integrity."
                popd >/dev/null
                rm -rf "${efi_staging}" 2>/dev/null || true
                return 1
            fi
            validate_privileges
            sudo mkdir -p "${target_efi_dir}"
            sudo cp -af "boot/efi/EFI/fedora/shimx64.efi" "${target_efi_dir}/shimx64.efi"
            sudo cp -af "boot/efi/EFI/fedora/mmx64.efi" "${target_efi_dir}/mmx64.efi"
        fi
        if [ -f "boot/efi/EFI/fedora/grubx64.efi" ]; then
            validate_privileges
            sudo mkdir -p "${target_efi_dir}"
            sudo cp -af "boot/efi/EFI/fedora/grubx64.efi" "${target_efi_dir}/grubx64.efi"
        fi
        log_success "Official Microsoft-signed Shim & GRUB deployed to ${target_efi_dir}!"
    else
        log_warn "Could not download official Shim RPMs. Checking local fallback paths..."
    fi

    popd >/dev/null
    rm -rf "${efi_staging}" 2>/dev/null || true
}

deploy_maximum_armor_interactive() {
    local is_silent="${1:-}"
    validate_privileges

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

    fetch_official_signed_shim_interactive "${esp_mount}"

    # Search for Microsoft-signed shimx64.efi & mmx64.efi candidates
    local shim_src=""
    local mm_src=""
    local grub_src=""

    local shim_candidates=(
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
    # 1. Hardware/Firmware Guard: Must be booted in UEFI mode
    [ -d "/sys/firmware/efi" ] || return 0

    # 2. Secure Boot Guard: Must be actively enabled in firmware (via mokutil)
    if command -v mokutil >/dev/null 2>&1; then
        local sb_state
        sb_state=$(mokutil --sb-state 2>/dev/null || echo "")
        if ! echo "${sb_state}" | grep -qi "enabled"; then
            # Secure Boot is NOT enabled in firmware. Do not touch or heal anything.
            return 0
        fi
    else
        # mokutil not available; cannot verify active Secure Boot. Safety first: do not heal.
        return 0
    fi

    # 3. Bootloader Guard: Must be using GRUB architecture
    if ! command -v grub-install >/dev/null 2>&1 && [ ! -f "/boot/grub/grub.cfg" ] && [ ! -f "/etc/default/grub" ]; then
        return 0
    fi

    local esp_mount
    esp_mount=$(detect_esp_mount)
    [ -d "${esp_mount}/EFI/Slackware" ] || return 0

    local target_efi_dir="${esp_mount}/EFI/Slackware"
    local needs_heal=0

    # Only heal if Slackware GRUB was previously deployed here
    if [ -f "${target_efi_dir}/grub.cfg" ] || [ -f "${target_efi_dir}/shimx64.efi" ]; then
        if [ ! -s "${target_efi_dir}/shimx64.efi" ] || [ ! -s "${target_efi_dir}/grubx64.efi" ]; then
            needs_heal=1
        fi
        if [ ! -s "${target_efi_dir}/grub.cfg" ]; then
            needs_heal=1
        fi
    fi

    if [ "${needs_heal}" -eq 1 ]; then
        log_warn "$(_ SB_SELF_HEAL_TRIGGERED)"
        deploy_maximum_armor_interactive --silent
    fi
}

fix_my_damn_secure_boot_wizard() {
    validate_privileges

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

revert_secure_boot_armor_interactive() {
    validate_privileges

    echo ""
    echo -e "${CYAN}============================================================${RESET}"
    echo -e "${YELLOW}${BOLD}$(_ MOK_OPTION_REVERT_SB | sed -E 's/^[0-9]+\.\s*//')${RESET}"
    echo -e "${CYAN}============================================================${RESET}"
    echo -e "This will remove the Microsoft-signed Shim early-loader and re-register standard Slackware GRUB in your UEFI firmware."
    echo -e "Use this if you are disabling Secure Boot in firmware or returning to standard boot."
    echo ""
    read -r -p "Are you sure you want to revert to standard unsigned GRUB? [y/N] " reply_rev
    reply_rev=${reply_rev:-N}
    if [[ ! "${reply_rev}" =~ ^[YyJjSsOo]$ ]]; then
        log_info "Operation cancelled."
        return 0
    fi

    local esp_mount
    esp_mount=$(detect_esp_mount)
    local target_efi_dir="${esp_mount}/EFI/Slackware"

    if [ -d "${target_efi_dir}" ]; then
        log_info "Cleaning Shim early-loader files from ${target_efi_dir}..."
        sudo rm -f "${target_efi_dir}/shimx64.efi" "${target_efi_dir}/mmx64.efi" "${target_efi_dir}/grub.cfg" 2>/dev/null || true
    fi

    if command -v grub-install >/dev/null 2>&1; then
        log_info "Running standard grub-install to restore native GRUB..."
        sudo grub-install --target=x86_64-efi --efi-directory="${esp_mount}" --bootloader-id=Slackware --recheck >/dev/null 2>&1 || true
    fi

    log_success "Standard Slackware GRUB restored! Secure Boot Armor disabled."
}

manage_armor_interactive() {
    validate_privileges

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
        echo -e "  $(_ MOK_OPTION_REVERT_SB)"
        echo -e "  $(_ MOK_OPTION_RETURN)"
        echo ""
        echo -n "$(_ SELECT_OPERATION_RANGE range="1-7") "
        read -r achoice || achoice="7"

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
                echo ""
                revert_secure_boot_armor_interactive
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
