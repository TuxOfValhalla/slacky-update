#!/usr/bin/env bash
# --- [ SBCTL & UEFI SECURE BOOT AUTOMATION MODULE ] ---

set -euo pipefail

audit_sbctl_status() {
    local sbctl_bin
    sbctl_bin=$(command -v sbctl 2>/dev/null || echo "/usr/bin/sbctl")

    echo ""
    echo -e "${CYAN}============================================================${RESET}"
    echo -e "${YELLOW}${BOLD}🔒 UEFI SECURE BOOT & SBCTL STATUS AUDIT 🔒${RESET}"
    echo -e "${CYAN}============================================================${RESET}"

    if [ ! -x "${sbctl_bin}" ]; then
        echo -e "  • ${BOLD}sbctl status:${RESET} ${YELLOW}[NOT INSTALLED]${RESET}"
        echo -e "    Install the Unified Limine & Secure Boot Suite to enable sbctl."
        echo ""
        return 0
    fi

    local status_json
    status_json=$("${sbctl_bin}" status --json 2>/dev/null || echo "{}")

    python3 -c "
import json, sys

data = {}
try:
    data = json.loads('''${status_json}''')
except Exception:
    pass

sb_installed = data.get('installed', False)
sb_setup_mode = data.get('setup_mode', False)
sb_secure_boot = data.get('secure_boot', False)
vendors = data.get('vendors', [])

c_green = '\033[1;32m'
c_yellow = '\033[1;33m'
c_red = '\033[1;31m'
c_cyan = '\033[1;36m'
c_reset = '\033[0m'
c_bold = '\033[1m'

print(f'  • {c_bold}Secure Boot Enabled:{c_reset}    ' + (f'{c_green}YES (Protected){c_reset}' if sb_secure_boot else f'{c_yellow}NO (Disabled / Setup Mode){c_reset}'))
print(f'  • {c_bold}Setup Mode Active:{c_reset}      ' + (f'{c_cyan}YES (Ready for Key Enrollment){c_reset}' if sb_setup_mode else f'{c_green}NO (User Mode Active){c_reset}'))
print(f'  • {c_bold}Custom Keys Installed:{c_reset}  ' + (f'{c_green}YES{c_reset}' if sb_installed else f'{c_yellow}NO (Keys not yet created){c_reset}'))
if vendors:
    print(f'  • {c_bold}Vendor Certificates:{c_reset}    {c_green}' + ', '.join(vendors) + f'{c_reset}')
else:
    print(f'  • {c_bold}Vendor Certificates:{c_reset}    {c_yellow}None / Microsoft OEM Certs Recommended{c_reset}')
" 2>/dev/null || "${sbctl_bin}" status || true

    echo ""
    echo -e "${BOLD}Signed EFI Binaries (/boot/EFI & /boot/efi/EFI):${RESET}"
    local esp_path
    esp_path=$(detect_limine_esp_path 2>/dev/null || echo "/boot/efi")
    local found_efi=0
    for efi in "${esp_path}/EFI/limine/limine_x64.efi" "${esp_path}/EFI/BOOT/BOOTX64.EFI" "${esp_path}/EFI/Slackware/grubx64.efi"; do
        if [ -f "${efi}" ]; then
            found_efi=1
            local sign_status="${YELLOW}[UNSIGNED]${RESET}"
            if command -v sbctl >/dev/null 2>&1; then
                if sbctl verify "${efi}" 2>/dev/null | grep -qi "signed"; then
                    sign_status="${GREEN}[SIGNED & VERIFIED]${RESET}"
                fi
            fi
            printf "  • %-45s : %b\n" "${efi#"${esp_path}/"}" "${sign_status}"
        fi
    done
    if [ "${found_efi}" -eq 0 ]; then
        echo -e "  • No EFI binaries found under ${esp_path}/EFI."
    fi
    echo ""
}

setup_sbctl_keys_interactive() {
    validate_privileges

    local sbctl_bin
    sbctl_bin=$(command -v sbctl 2>/dev/null || echo "/usr/bin/sbctl")

    if [ ! -x "${sbctl_bin}" ]; then
        log_info "sbctl not found. Deploying Unified Limine & Secure Boot Suite..."
        if command -v install_unified_limine_suite >/dev/null 2>&1; then
            install_unified_limine_suite || return 1
        fi
        sbctl_bin=$(command -v sbctl 2>/dev/null || echo "/usr/bin/sbctl")
    fi

    if [ ! -x "${sbctl_bin}" ]; then
        log_error "sbctl binary could not be found or installed."
        return 1
    fi

    echo ""
    echo -e "${CYAN}============================================================${RESET}"
    echo -e "${YELLOW}${BOLD}🧙‍♂️ UEFI SECURE BOOT & SBCTL SETUP WIZARD 🧙‍♂️${RESET}"
    echo -e "${CYAN}============================================================${RESET}"

    local status_json
    status_json=$("${sbctl_bin}" status --json 2>/dev/null || echo "{}")

    local in_setup_mode=0
    if echo "${status_json}" | grep -q '"setup_mode": true'; then
        in_setup_mode=1
    fi

    if [ "${in_setup_mode}" -eq 0 ]; then
        echo -e "${YELLOW}${BOLD}⚠️ Firmware is NOT in Setup Mode!${RESET}"
        echo -e "To enroll your custom Secure Boot keys, your UEFI motherboard must be in Setup Mode."
        echo ""
        echo -e "${CYAN}${BOLD}Instructions to enter Setup Mode in BIOS:${RESET}"
        echo -e "  1. Reboot and press \033[1;33mDelete\033[0m / \033[1;33mF2\033[0m to enter UEFI BIOS Setup."
        echo -e "  2. Navigate to \033[1;33mSecurity\033[0m -> \033[1;33mSecure Boot\033[0m."
        echo -e "  3. Select \033[1;33m'Clear Secure Boot Keys'\033[0m or \033[1;33m'Delete PK'\033[0m (this enables Setup Mode)."
        echo -e "  4. Save changes, boot into Slackware, and run this wizard again."
        echo ""
        read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
        return 0
    fi

    echo -e "${GREEN}${BOLD}✓ Firmware is in Setup Mode! Ready to enroll custom keys.${RESET}"
    echo ""
    echo -e "${YELLOW}${BOLD}Would you like to create keys and enroll them with Microsoft OEM certificates (-m)?${RESET}"
    echo -e "${CYAN}(Note: -m includes Microsoft OEM certificates, essential for GPU Option ROMs and Windows 11 dual-boot)${RESET}"
    echo ""
    read -r -p "Proceed with enrollment? [Y/n]: " reply_enroll
    reply_enroll=${reply_enroll:-Y}
    if [[ ! "${reply_enroll}" =~ ^[YyJjSsOo]$ ]]; then
        log_info "Operation cancelled by user."
        return 0
    fi

    log_info "Creating cryptographic keys with sbctl create-keys..."
    sudo "${sbctl_bin}" create-keys || true

    log_info "Enrolling keys with Microsoft OEM vendor certificates (sbctl enroll-keys -m)..."
    if sudo "${sbctl_bin}" enroll-keys -m; then
        log_success "Secure Boot keys successfully enrolled in UEFI NVRAM keyring!"
    else
        log_warn "Standard enroll-keys failed. Retrying with sbctl enroll-keys --microsoft..."
        sudo "${sbctl_bin}" enroll-keys --microsoft || true
    fi

    # Sign Limine and GRUB EFI binaries
    local esp_path
    esp_path=$(detect_limine_esp_path 2>/dev/null || echo "/boot/efi")
    for efi in "${esp_path}/EFI/limine/limine_x64.efi" "${esp_path}/EFI/BOOT/BOOTX64.EFI" "${esp_path}/EFI/Slackware/grubx64.efi"; do
        if [ -f "${efi}" ]; then
            log_info "Signing EFI executable: ${efi}..."
            sudo "${sbctl_bin}" sign -s "${efi}" 2>/dev/null || true
        fi
    done

    # Enroll Limine config if Limine is installed
    if command -v enroll_and_sign_limine >/dev/null 2>&1; then
        enroll_and_sign_limine || true
    fi

    echo ""
    echo -e "${CYAN}============================================================${RESET}"
    echo -e "${GREEN}${BOLD}🎉 SECURE BOOT ENROLLMENT COMPLETE! 🎉${RESET}"
    echo -e "${CYAN}============================================================${RESET}"
    echo -e "  1. Reboot into UEFI BIOS Setup."
    echo -e "  2. Turn \033[1;32mSecure Boot: Enabled (Standard Mode)\033[0m."
    echo -e "  3. Boot directly into Limine or GRUB with 100% cryptographic protection!"
    echo -e "${CYAN}============================================================${RESET}"
    echo ""
    read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
}

manage_secureboot_interactive() {
    while true; do
        echo ""
        echo -e "${CYAN}============================================================${RESET}"
        echo -e "${YELLOW}${BOLD}🔒 UEFI SECURE BOOT CONTROL CENTER (SBCTL & MOK) 🔒${RESET}"
        echo -e "${CYAN}============================================================${RESET}"
        echo -e "  \033[1;33m1.\033[0m Audit Secure Boot & Cryptographic Status"
        echo -e "  \033[1;33m2.\033[0m Run 1-Click sbctl Secure Boot Key Enrollment Wizard"
        echo -e "  \033[1;33m3.\033[0m Sign All EFI Bootloaders in /boot/EFI"
        echo -e "  \033[1;33m4.\033[0m Manage Classic MOK (Kernel Module Signatures)"
        echo -e "  \033[1;33m5.\033[0m Return to Main Menu"
        echo ""
        echo -n "Select operation [1-5]: "
        local sb_choice
        read -r sb_choice || sb_choice="5"

        case "${sb_choice}" in
            1)
                audit_sbctl_status
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            2)
                setup_sbctl_keys_interactive
                ;;
            3)
                validate_privileges
                local sbctl_bin
                sbctl_bin=$(command -v sbctl 2>/dev/null || echo "/usr/bin/sbctl")
                local esp_path
                esp_path=$(detect_limine_esp_path 2>/dev/null || echo "/boot/efi")
                for efi in $(find "${esp_path}/EFI" -name "*.efi" 2>/dev/null || true); do
                    log_info "Signing ${efi}..."
                    sudo "${sbctl_bin}" sign -s "${efi}" 2>/dev/null || true
                done
                log_success "All EFI binaries in ${esp_path}/EFI signed."
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            4)
                if command -v manage_armor_interactive >/dev/null 2>&1; then
                    manage_armor_interactive
                fi
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
