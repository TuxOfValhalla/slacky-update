#!/usr/bin/env bash
# --- [ SLACKY-UPDATE SBO & SLACKBUILDS MODULE ] ---

set -euo pipefail

is_sbotools_installed() {
    command -v sboinstall >/dev/null 2>&1 && command -v sbocheck >/dev/null 2>&1
}

setup_sbotools_interactive() {
    echo -e "
$(_ SBO_SETUP_HEADER)"
    
    local slack_ver="15.0"
    local is_current=false
    if grep -q -E "(\+|current)" /etc/slackware-version 2>/dev/null; then
        is_current=true
        slack_ver="current"
    fi

    log_info "Detected Slackware version: ${slack_ver}"

    if ! is_sbotools_installed; then
        echo ""
        read -r -p "$(_ PROMPT_SETUP_SBOTOOLS) " reply_sbo
        reply_sbo=${reply_sbo:-Y}
        if [[ ! "$reply_sbo" =~ ^[YyJjSsOo]$ ]]; then
            log_warn "$(_ SBO_SETUP_SKIPPED)"
            return 0
        fi

        log_info "Bootstrapping sbotools from SlackBuilds.org..."
        local sbo_tmp="/tmp/sbotools-bootstrap"
        rm -rf "${sbo_tmp}"
        mkdir -p "${sbo_tmp}"
        pushd "${sbo_tmp}" >/dev/null

        local sbotools_tar="sbotools-3.6.tar.gz"
        local sbotools_sb="sbotools.tar.gz"
        
        # Download sbotools SlackBuild
        if [ "${is_current}" = "true" ]; then
            curl -sSL "https://raw.githubusercontent.com/Ponce/slackbuilds/current/system/sbotools/sbotools.SlackBuild" -o sbotools.SlackBuild
            curl -sSL "https://raw.githubusercontent.com/Ponce/slackbuilds/current/system/sbotools/sbotools.info" -o sbotools.info
            curl -sSL "https://raw.githubusercontent.com/Ponce/slackbuilds/current/system/sbotools/slack-desc" -o slack-desc
        else
            curl -sSL "https://slackbuilds.org/slackbuilds/15.0/system/sbotools.tar.gz" -o "${sbotools_sb}"
            tar -zxf "${sbotools_sb}"
            cd sbotools
        fi

        # Source download URL from info
        local dl_url
        dl_url=$(grep "^DOWNLOAD=" sbotools.info 2>/dev/null | cut -d'"' -f2 || true)
        dl_url=${dl_url:-https://github.com/duganchen/sbotools/archive/v3.6/sbotools-3.6.tar.gz}
        curl -sSL "${dl_url}" -o "${sbotools_tar}" || true

        chmod +x sbotools.SlackBuild
        sudo ./sbotools.SlackBuild
        local built_pkg
        built_pkg=$(ls -t /tmp/sbotools-*-noarch-*.txz 2>/dev/null | head -n 1 || true)
        if [ -n "${built_pkg}" ] && [ -f "${built_pkg}" ]; then
            sudo /sbin/upgradepkg --install-new "${built_pkg}"
            log_success "sbotools installed successfully!"
        else
            log_error "Failed to build sbotools package."
            popd >/dev/null
            rm -rf "${sbo_tmp}"
            return 1
        fi
        popd >/dev/null
        rm -rf "${sbo_tmp}"
    fi

    # Configure repository in /etc/sbotools/sbotools.conf
    local num_jobs
    num_jobs=$(nproc 2>/dev/null || echo 4)
    sudo mkdir -p /etc/sbotools
    if [ "${is_current}" = "true" ]; then
        log_info "Configuring sbotools for Slackware -current with Ponce git repository..."
        echo "REPO_URL=https://github.com/Ponce/slackbuilds.git" | sudo tee /etc/sbotools/sbotools.conf >/dev/null
        echo "REPO_BRANCH=current" | sudo tee -a /etc/sbotools/sbotools.conf >/dev/null
        echo "NOCLEAN=FALSE" | sudo tee -a /etc/sbotools/sbotools.conf >/dev/null
        echo "JOBS=${num_jobs}" | sudo tee -a /etc/sbotools/sbotools.conf >/dev/null
    else
        log_info "Configuring sbotools for Slackware 15.0..."
        echo "REPO_URL=https://github.com/pfeiffer/slackbuilds.git" | sudo tee /etc/sbotools/sbotools.conf >/dev/null
        echo "REPO_BRANCH=15.0" | sudo tee -a /etc/sbotools/sbotools.conf >/dev/null
        echo "NOCLEAN=FALSE" | sudo tee -a /etc/sbotools/sbotools.conf >/dev/null
        echo "JOBS=${num_jobs}" | sudo tee -a /etc/sbotools/sbotools.conf >/dev/null
    fi

    log_info "Fetching initial SBo tree snapshot (sbosnap fetch)..."
    sudo sbosnap fetch >/dev/null 2>&1 || log_warn "sbosnap fetch finished with warnings."
    log_success "sbotools is ready for action!"
}

auto_refresh_sbo_tree_if_stale() {
    [ -d "/var/lib/sbotools/repo" ] || return 0
    
    local repo_mtime now_ts diff_days
    repo_mtime=$(stat -c %Y /var/lib/sbotools/repo 2>/dev/null || echo 0)
    now_ts=$(date +%s)
    diff_days=$(( (now_ts - repo_mtime) / 86400 ))

    if [ "${diff_days}" -ge 7 ]; then
        echo -e "${CYAN}[WHOA] $(_ SBO_SYNCING_INTEL)${RESET}"
        sudo sbosnap fetch >/dev/null 2>&1 || true
        touch /var/lib/sbotools/repo 2>/dev/null || true
    fi
}

update_sbo_packages() {
    if is_sbotools_installed; then
        echo -e "
${BLUE}${BOLD}$(_ UPGRADING_SBO)${RESET}"
        sudo sboupgrade --all || {
            log_warn "sbotools upgrade completed with non-fatal warnings."
        }
        log_success "SlackBuilds upgrade routine complete."
    fi
}

check_steam_multilib_status() {
    local multilib_pkgs
    multilib_pkgs=$(ls /var/log/packages/glibc-*-compat32* 2>/dev/null || true)
    if [ -n "${multilib_pkgs}" ]; then
        echo "true"
    else
        echo "false"
    fi
}

setup_multilib_interactive() {
    echo -e "
${BOLD}${CYAN}$(_ MULTILIB_SETUP_HEADER)${RESET}"
    log_warn "$(_ STEAM_MULTILIB_REQUIRED)"
    
    local reply_multi
    read -r -p "$(_ PROMPT_SETUP_MULTILIB) " reply_multi
    reply_multi=${reply_multi:-Y}
    if [[ ! "$reply_multi" =~ ^[YyJjSsOo]$ ]]; then
        log_warn "Multilib setup aborted by user."
        return 1
    fi

    local slack_ver="15.0"
    if grep -q -E "(\+|current)" /etc/slackware-version 2>/dev/null; then
        slack_ver="current"
    fi

    log_info "Fetching AlienBOB multilib packages for Slackware ${slack_ver}..."
    local multi_tmp="/tmp/slacky-multilib-setup"
    rm -rf "${multi_tmp}"
    mkdir -p "${multi_tmp}"
    pushd "${multi_tmp}" >/dev/null

    local multi_url="http://bear.alienbase.nl/mirrors/people/alien/multilib/${slack_ver}"
    lftp -c "open ${multi_url}; mirror -c -e -n -v --include-glob='*.txz' ." 2>/dev/null || {
        log_info "Falling back to HTTP package sync..."
        curl -sSL "${multi_url}/" | grep -o 'href="[^"]*\.txz"' | cut -d'"' -f2 | while read -r pkg_file; do
            [ -n "${pkg_file}" ] && curl -sSL -O "${multi_url}/${pkg_file}"
        done
    }

    log_info "Upgrading to multilib core packages..."
    sudo /sbin/upgradepkg --reinstall --install-new ./*.txz 2>/dev/null || true

    popd >/dev/null
    rm -rf "${multi_tmp}"
    log_success "Multilib environment successfully installed and activated!"
    return 0
}

manage_recommended_gaming_interactive() {
    while true; do
        echo ""
        echo -e "${BOLD}${CYAN}$(_ RECOMMENDED_GAMING_TITLE)${RESET}"
        echo -e "  \033[1;33m1.\033[0m OBS Studio (multimedia/obs-studio)"
        echo -e "  \033[1;33m2.\033[0m Steam Client (games/steam)"
        echo -e "  \033[1;33m3.\033[0m Discord (network/discord)"
        echo -e "  \033[1;33m4.\033[0m ProtonPlus (games/protonplus)"
        echo -e "  \033[1;33m5.\033[0m $(_ SBO_BACK_OPTION)"
        echo ""
        echo -n "$(_ SELECT_OPERATION_RANGE range="1-5") "
        local sel
        read -r sel || sel="5"

        case "${sel}" in
            1)
                sudo sboinstall obs-studio
                ;;
            2)
                local has_multi
                has_multi=$(check_steam_multilib_status)
                if [ "${has_multi}" != "true" ]; then
                    if ! setup_multilib_interactive; then
                        continue
                    fi
                fi
                sudo sboinstall steam || {
                    log_info "Downloading AlienBOB's native Steam package..."
                    local steam_txz="/tmp/steam-latest.txz"
                    curl -sSL "http://bear.alienbase.nl/mirrors/people/alien/slackbuilds/steam/pkg64/current/steam-1.0.0.82-x86_64-1alien.txz" -o "${steam_txz}" 2>/dev/null || true
                    if [ -f "${steam_txz}" ]; then
                        sudo /sbin/upgradepkg --install-new "${steam_txz}"
                        log_success "Steam installed successfully!"
                    fi
                }
                ;;
            3)
                sudo sboinstall discord
                ;;
            4)
                sudo sboinstall protonplus
                ;;
            5)
                return 0
                ;;
            *)
                log_warn "Invalid selection."
                ;;
        esac
        echo ""
        read -r -p "$(_ PRESS_ENTER_CONTINUE) " || true
    done
}

search_sbo_interactive() {
    while true; do
        echo ""
        echo -e "${BOLD}${CYAN}$(_ SBO_SEARCH_PROMPT_TITLE)${RESET}"
        echo -e "  \033[1;33m1.\033[0m $(_ SBO_CUSTOM_SEARCH_OPTION)"
        echo -e "  \033[1;33m2.\033[0m $(_ SBO_RECOMMENDED_GAMING_OPTION)"
        echo -e "  \033[1;33m3.\033[0m $(_ SBO_BACK_OPTION)"
        echo ""
        echo -n "$(_ SELECT_OPERATION_RANGE range="1-3") "
        local sel
        read -r sel || sel="3"

        case "${sel}" in
            1)
                echo ""
                echo -n "$(_ ENTER_SEARCH_QUERY): "
                local q
                read -r q || q=""
                if [ -n "${q}" ]; then
                    sbofind "${q}" || true
                    echo ""
                    echo -n "$(_ ENTER_PACKAGE_TO_INSTALL): "
                    local target
                    read -r target || target=""
                    if [ -n "${target}" ]; then
                        sudo sboinstall "${target}"
                    fi
                fi
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE) " || true
                ;;
            2)
                manage_recommended_gaming_interactive
                ;;
            3)
                return 0
                ;;
            *)
                log_warn "Invalid selection."
                ;;
        esac
    done
}

install_curated_slackbuild() {
    local prg="$1"
    local suite_dir="$2"
    local pkg_path="${suite_dir}/${prg}"

    if [ ! -d "${pkg_path}" ]; then
        log_error "SlackBuild path ${pkg_path} not found."
        return 1
    fi

    pushd "${pkg_path}" >/dev/null
    local sb_script
    sb_script=$(ls *.SlackBuild | head -n 1)

    # Special handling for DaVinci Resolve Studio
    if [ "${prg}" = "multimedia/davinci-resolve-studio" ]; then
        local found_zip
        found_zip=$(ls "${pkg_path}"/DaVinci_Resolve_Studio_*_Linux.zip ~/Downloads/DaVinci_Resolve_Studio_*_Linux.zip /tmp/DaVinci_Resolve_Studio_*_Linux.zip 2>/dev/null | head -n 1 || true)
        if [ -z "${found_zip}" ]; then
            echo ""
            echo -e "${YELLOW}${BOLD}$(_ DAVINCI_DOWNLOAD_REQUIRED)${RESET}"
            echo -e "👉 Download link: ${CYAN}https://www.blackmagicdesign.com/products/davinciresolve/studio${RESET}"
            echo -e "Place the DaVinci_Resolve_Studio_<VERSION>_Linux.zip file in ~/Downloads
"
            read -r -p "$(_ PROMPT_CONTINUE_DAVINCI) " reply_dv
            if [[ ! "$reply_dv" =~ ^[YyJjSsOo]$ ]]; then
                log_warn "DaVinci Resolve installation canceled."
                popd >/dev/null
                return 0
            fi
        fi
    fi

    # Special handling for FreeOffice 2024
    if [ "${prg}" = "office/freeoffice2024" ]; then
        local found_fo
        found_fo=$(ls "${pkg_path}"/softmaker-freeoffice-*.tgz ~/Downloads/softmaker-freeoffice-*.tgz /tmp/softmaker-freeoffice-*.tgz 2>/dev/null | head -n 1 || true)
        if [ -z "${found_fo}" ]; then
            log_info "Fetching FreeOffice 2024 tarball from SoftMaker..."
            curl -sSL "https://www.softmaker.net/down/softmaker-freeoffice-2024-1234-amd64.tgz" -o "softmaker-freeoffice-2024-1234-amd64.tgz"
        fi
    fi

    log_info "Building and packaging ${prg}..."
    chmod +x "${sb_script}"
    sudo ./${sb_script}

    local built_pkg
    local prg_base
    prg_base=$(basename "${prg}")
    built_pkg=$(ls -t /tmp/"${prg_base}"-*-*.txz 2>/dev/null | head -n 1 || true)
    if [ -n "${built_pkg}" ] && [ -f "${built_pkg}" ]; then
        sudo /sbin/upgradepkg --install-new "${built_pkg}"
        log_success "${prg_base} installed and active!"
    fi
    popd >/dev/null
}

manage_curated_suite_interactive() {
    local suite_dir="${SLACKY_SLACKBUILDS_DIR:-/var/cache/slacky-update/slacky-slackbuilds}"
    if [ ! -d "${suite_dir}" ]; then
        log_info "Fetching curated Slacky-SlackBuilds repository..."
        sudo mkdir -p "$(dirname "${suite_dir}")"
        sudo git clone https://github.com/TuxOfValhalla/slacky-slackbuilds.git "${suite_dir}" 2>/dev/null || true
    else
        (cd "${suite_dir}" && sudo git pull 2>/dev/null || true)
    fi

    while true; do
        echo ""
        echo -e "${BOLD}${CYAN}$(_ CURATED_SUITE_TITLE)${RESET}"
        
        # Helper to check if package is installed
        get_status_badge() {
            local pattern="$1"
            if ls /var/log/packages/"${pattern}"-* >/dev/null 2>&1; then
                echo -e "[1;32m[INSTALLED][0m"
            else
                echo -e "[1;33m[AVAILABLE][0m"
            fi
        }

        echo -e "  [1;33m1.[0m LACT $(get_status_badge "lact") - GPU Overclocking Mojo for Radeon & Nvidia"
        echo -e "  [1;33m2.[0m Heroic Games Launcher $(get_status_badge "heroic-games-launcher") - Epic & GOG Cyber-Deck"
        echo -e "  [1;33m3.[0m GOverlay + MangoHud $(get_status_badge "goverlay") - Radical In-Game HUD & Telemetry"
        echo -e "  [1;33m4.[0m Faugus Launcher $(get_status_badge "faugus-launcher") - Proton Cyber-Runner for Non-Steam Games"
        echo -e "  [1;33m5.[0m Ananicy-cpp $(get_status_badge "ananicy-cpp") - Auto-Nice Turbo Boost for Games & Apps"
        echo -e "  [1;33m6.[0m Snapper + GRUB-Btrfs $(get_status_badge "snapper") - Instant Btrfs Time Warp & Snapshot Booting"
        echo -e "  [1;33m7.[0m FreeOffice 2024 $(get_status_badge "freeoffice2024") - Microsoft-compatible Office Suite"
        echo -e "  [1;33m8.[0m DaVinci Resolve Studio $(get_status_badge "davinci-resolve-studio") - Hollywood-grade Video Studio & Color Engine"
        echo -e "  [1;33m9.[0m $(_ SBO_BACK_OPTION)"
        echo ""
        echo -n "$(_ SELECT_OPERATION_RANGE range="1-9") "
        local sel
        read -r sel || sel="9"

        case "${sel}" in
            1) install_curated_slackbuild "system/lact" "${suite_dir}" ;;
            2) install_curated_slackbuild "games/heroic-games-launcher" "${suite_dir}" ;;
            3)
                install_curated_slackbuild "graphics/mangohud" "${suite_dir}"
                install_curated_slackbuild "graphics/goverlay" "${suite_dir}"
                ;;
            4) install_curated_slackbuild "games/faugus-launcher" "${suite_dir}" ;;
            5) install_curated_slackbuild "system/ananicy-cpp" "${suite_dir}" ;;
            6)
                install_curated_slackbuild "system/snapper" "${suite_dir}"
                install_curated_slackbuild "system/grub-btrfs" "${suite_dir}"
                ;;
            7) install_curated_slackbuild "office/freeoffice2024" "${suite_dir}" ;;
            8) install_curated_slackbuild "multimedia/davinci-resolve-studio" "${suite_dir}" ;;
            9) return 0 ;;
            *) log_warn "Invalid selection." ;;
        esac
        echo ""
        read -r -p "$(_ PRESS_ENTER_CONTINUE) " || true
    done
}

manage_slackbuilds_interactive() {
    if ! is_sbotools_installed; then
        setup_sbotools_interactive
    fi
    auto_refresh_sbo_tree_if_stale

    while true; do
        echo ""
        echo -e "${BOLD}Slacky-Update (SlackBuilds & Packages)${RESET}"
        echo -e "${BOLD}$(_ SBO_MAIN_HUB_TITLE)${RESET}"
        echo -e "  \033[1;33m1.\033[0m $(_ SBO_MENU_SEARCH_AND_RECOMMENDED)"
        echo -e "  \033[1;33m2.\033[0m $(_ SBO_MENU_CURATED_SUITE)"
        echo -e "  \033[1;33m3.\033[0m $(_ CATCH_YOU_FLIP_SIDE)"
        echo ""
        echo -n "$(_ SELECT_OPERATION_RANGE range="1-3") "
        local opt
        read -r opt || opt="3"

        case "${opt}" in
            1)
                search_sbo_interactive
                ;;
            2)
                manage_curated_suite_interactive
                ;;
            3)
                return 0
                ;;
            *)
                log_warn "Invalid selection."
                ;;
        esac
    done
}
