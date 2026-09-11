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
            sudo "${PKG_UPGRADE_CMD}" --reinstall --install-new "${built_pkg}"
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
        log_info "$(_ SBO_SYNCING_INTEL)"
        sudo sbosnap fetch >/dev/null 2>&1 || true
        sudo touch /var/lib/sbotools/repo 2>/dev/null || true
    fi
}

update_sbo_packages() {
    if is_sbotools_installed; then
        echo -e "
${BLUE}${BOLD}$(_ UPGRADING_SBO)${RESET}"
        auto_refresh_sbo_tree_if_stale
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
    sudo "${PKG_UPGRADE_CMD}" --reinstall --install-new ./*.txz 2>/dev/null || true

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
                    sudo rm -f "${steam_txz}"
                    if curl -sSLf "https://bear.alienbase.nl/mirrors/people/alien/slackbuilds/steam/pkg64/current/steam-1.0.0.82-x86_64-1alien.txz" -o "${steam_txz}" 2>/dev/null; then
                        local sz=0
                        [ -f "${steam_txz}" ] && sz=$(stat -c%s "${steam_txz}" 2>/dev/null || echo 0)
                        if [ "${sz}" -gt 1000000 ]; then
                            sudo "${PKG_UPGRADE_CMD}" --reinstall --install-new "${steam_txz}"
                            log_success "Steam installed successfully!"
                            sudo rm -f "${steam_txz}" 2>/dev/null || true
                        else
                            log_warn "Downloaded Steam package is invalid or truncated (${sz} bytes)."
                            sudo rm -f "${steam_txz}" 2>/dev/null || true
                        fi
                    else
                        log_warn "Failed to download AlienBOB Steam package fallback."
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

    # Always ensure cache is synchronized with latest bundled recipe
    local bundled_cand=""
    for cand in "${APP_DIR}/../assets/slacky-slackbuilds/${prg}" "${APP_DIR}/assets/slacky-slackbuilds/${prg}" "/usr/share/slacky-update/assets/slacky-slackbuilds/${prg}" "/usr/local/lib/slacky-update/assets/slacky-slackbuilds/${prg}"; do
        if [ -d "${cand}" ]; then
            bundled_cand="${cand}"
            break
        fi
    done

    if [ -n "${bundled_cand}" ]; then
        sudo mkdir -p "$(dirname "${pkg_path}")"
        sudo rm -rf "${pkg_path}"
        sudo cp -a "${bundled_cand}" "${pkg_path}"
    elif [ ! -d "${pkg_path}" ]; then
        log_error "SlackBuild path ${pkg_path} not found."
        return 1
    fi

    # Create isolated ephemeral build workspace in /tmp
    local build_tmp
    build_tmp=$(mktemp -d /tmp/slacky-build-XXXXXX)
    sudo cp -a "${pkg_path}"/* "${build_tmp}/"

    pushd "${build_tmp}" >/dev/null
    local sb_script
    sb_script=$(ls *.SlackBuild | head -n 1)

    # Special handling for DaVinci Resolve Studio
    if [ "${prg}" = "multimedia/davinci-resolve-studio" ]; then
        local found_zip
        found_zip=$(ls ~/Downloads/DaVinci_Resolve_Studio_*_Linux.zip /tmp/DaVinci_Resolve_Studio_*_Linux.zip "${pkg_path}"/DaVinci_Resolve_Studio_*_Linux.zip 2>/dev/null | head -n 1 || true)
        if [ -n "${found_zip}" ]; then
            cp -f "${found_zip}" "${build_tmp}/"
        else
            echo ""
            echo -e "${YELLOW}${BOLD}$(_ DAVINCI_DOWNLOAD_REQUIRED)${RESET}"
            echo -e "👉 Download link: ${CYAN}https://www.blackmagicdesign.com/products/davinciresolve/studio${RESET}"
            echo -e "Place the DaVinci_Resolve_Studio_<VERSION>_Linux.zip file in ~/Downloads\n"
            read -r -p "$(_ PROMPT_CONTINUE_DAVINCI) " reply_dv
            if [[ ! "$reply_dv" =~ ^[YyJjSsOo]$ ]]; then
                log_warn "DaVinci Resolve installation canceled."
                popd >/dev/null
                sudo rm -rf "${build_tmp}"
                return 0
            fi
            found_zip=$(ls ~/Downloads/DaVinci_Resolve_Studio_*_Linux.zip /tmp/DaVinci_Resolve_Studio_*_Linux.zip 2>/dev/null | head -n 1 || true)
            if [ -n "${found_zip}" ]; then
                cp -f "${found_zip}" "${build_tmp}/"
            fi
        fi
    fi

    # Special handling for FreeOffice 2024
    if [ "${prg}" = "office/freeoffice2024" ]; then
        local found_fo
        found_fo=$(ls ~/Downloads/softmaker-freeoffice-*.tgz /tmp/softmaker-freeoffice-*.tgz "${pkg_path}"/softmaker-freeoffice-*.tgz 2>/dev/null | head -n 1 || true)
        if [ -n "${found_fo}" ]; then
            cp -f "${found_fo}" "${build_tmp}/"
        fi
    fi

    # Generic automated source downloader from .info file
    local info_file
    info_file=$(ls *.info 2>/dev/null | head -n 1 || true)
    if [ -n "${info_file}" ] && [ -f "${info_file}" ]; then
        local dl_urls=""
        if [ "$(uname -m)" = "x86_64" ]; then
            dl_urls=$(grep "^DOWNLOAD_x86_64=" "${info_file}" 2>/dev/null | cut -d'"' -f2 || true)
            [ "${dl_urls}" = "UNSUPPORTED" ] && dl_urls=""
        fi
        if [ -z "${dl_urls}" ]; then
            dl_urls=$(grep "^DOWNLOAD=" "${info_file}" 2>/dev/null | cut -d'"' -f2 || true)
            [ "${dl_urls}" = "UNSUPPORTED" ] && dl_urls=""
        fi

        if [ -n "${dl_urls}" ]; then
            for url in ${dl_urls}; do
                local filename
                filename=$(basename "${url}")
                local found_cache
                found_cache=$(ls "${build_tmp}/${filename}" \
                                 "/var/cache/slacky-update/archives/${filename}" \
                                 "${HOME}/Downloads/${filename}" \
                                 "/tmp/${filename}" 2>/dev/null | head -n 1 || true)
                if [ -n "${found_cache}" ] && [ -f "${found_cache}" ]; then
                    if [ "${found_cache}" != "${build_tmp}/${filename}" ]; then
                        log_info "Using cached source: ${found_cache}"
                        cp -f "${found_cache}" "${build_tmp}/"
                    fi
                else
                    log_info "Downloading source archive: ${url} ..."
                    sudo mkdir -p /var/cache/slacky-update/archives
                    if wget -c --no-check-certificate "${url}" -O "${build_tmp}/${filename}"; then
                        sudo cp -f "${build_tmp}/${filename}" "/var/cache/slacky-update/archives/${filename}" 2>/dev/null || true
                    elif curl -Lo "${build_tmp}/${filename}" "${url}"; then
                        sudo cp -f "${build_tmp}/${filename}" "/var/cache/slacky-update/archives/${filename}" 2>/dev/null || true
                    else
                        log_warn "Download failed for ${url}."
                    fi
                fi
            done
        fi
    fi

    log_info "Building and packaging ${prg} in isolated workspace..."
    chmod +x "${sb_script}"
    sudo env TMP="/tmp/SBo" OUTPUT="/tmp" ./${sb_script}

    local built_pkg
    local prg_base
    prg_base=$(basename "${prg}")
    built_pkg=$(ls -t /tmp/"${prg_base}"-*-*.txz 2>/dev/null | head -n 1 || true)
    if [ -n "${built_pkg}" ] && [ -f "${built_pkg}" ]; then
        sudo "${PKG_UPGRADE_CMD}" --reinstall --install-new "${built_pkg}"
        log_success "${prg_base} installed and active!"
        sudo rm -f "${built_pkg}" 2>/dev/null || true
    fi
    popd >/dev/null
    sudo rm -rf "${build_tmp}" /tmp/SBo/package-* /tmp/SBo/*-build /tmp/SBo/${prg_base}-* 2>/dev/null || true
}

is_pkg_installed() {
    local prg="$1"
    local base_name
    base_name=$(basename "${prg}")
    local matches
    matches=$(ls /var/log/packages/"${base_name}"-[0-9]* /var/log/packages/"${base_name}"_* /var/log/packages/"${base_name}"-[a-zA-Z0-9]* 2>/dev/null || true)
    if [ -n "${matches}" ]; then
        return 0
    fi
    case "${base_name}" in
        affinity|affinity-suite|affinity_suite)
            [ -f "${HOME}/.local/share/applications/Affinity.desktop" ] || \
            [ -f "${HOME}/.local/share/applications/affinity.desktop" ] || \
            [ -f "/usr/share/applications/Affinity.desktop" ] || \
            [ -f "/usr/share/applications/affinity.desktop" ] || \
            [ -f "/usr/share/applications/affinity-designer.desktop" ] || \
            [ -f "/usr/share/applications/affinity-photo.desktop" ] || \
            [ -f "/usr/share/applications/affinity-publisher.desktop" ] || \
            [ -d "${HOME}/.AffinityLinux" ] || \
            [ -d "${HOME}/.config/AffinityOnLinux" ] || \
            [ -f "/usr/bin/affinity" ] || \
            [ -f "/usr/local/bin/affinity" ] || \
            [ -d "/opt/affinity" ]
            ;;
        storyboarder)
            [ -f "/usr/bin/storyboarder" ] || \
            [ -f "/usr/local/bin/storyboarder" ] || \
            [ -d "/usr/lib64/storyboarder" ] || \
            [ -d "/usr/lib/storyboarder" ] || \
            [ -d "/opt/storyboarder" ] || \
            [ -f "/usr/share/applications/storyboarder.desktop" ]
            ;;
        davinci*|davinci-resolve-studio)
            [ -d "/opt/resolve" ] || [ -f "/opt/resolve/bin/resolve" ]
            ;;
        freeoffice*|freeoffice2024)
            [ -d "/usr/lib/softmaker2024" ] || [ -d "/opt/freeoffice2024" ] || [ -f "/usr/bin/freeoffice2024" ]
            ;;
        *)
            command -v "${base_name}" >/dev/null 2>&1
            ;;
    esac
}

get_pkg_badge() {
    local prg="$1"
    if is_pkg_installed "${prg}"; then
        echo -e "\033[1;32m[INSTALLED]\033[0m"
    else
        echo -e "\033[1;33m[AVAILABLE]\033[0m"
    fi
}

menu_category_games() {
    local suite_dir="$1"
    while true; do
        local b_faugus
        b_faugus=$(get_pkg_badge "faugus-launcher")
        echo ""
        echo -e "${BOLD}${CYAN}=============================================================================${RESET}"
        echo -e "${BOLD}${CYAN}                     🎮 Games & Launchers 🎮${RESET}"
        echo -e "${BOLD}${CYAN}=============================================================================${RESET}"
        echo -e "  \033[1;33m1.\033[0m Faugus Launcher ${b_faugus} - Proton Cyber-Runner for Non-Steam Games"
        echo -e "  \033[1;33m2.\033[0m $(_ SBO_BACK_OPTION)"
        echo ""
        echo -n "$(_ SELECT_OPERATION_RANGE range="1-2") "
        local sel
        read -r sel || sel="2"
        case "${sel}" in
            1) install_curated_slackbuild "games/faugus-launcher" "${suite_dir}" ;;
            2) return 0 ;;
            *) log_warn "Invalid selection." ;;
        esac
        echo ""
        read -r -p "$(_ PRESS_ENTER_CONTINUE) " || true
    done
}

menu_category_graphics() {
    local suite_dir="$1"
    while true; do
        local b_affinity b_bambu b_blender b_goverlay b_inkscape b_mangohud b_storyboarder
        b_affinity=$(get_pkg_badge "affinity")
        b_bambu=$(get_pkg_badge "bambu-studio")
        b_blender=$(get_pkg_badge "blender")
        b_goverlay=$(get_pkg_badge "goverlay")
        b_inkscape=$(get_pkg_badge "inkscape")
        b_mangohud=$(get_pkg_badge "mangohud")
        b_storyboarder=$(get_pkg_badge "storyboarder")
        echo ""
        echo -e "${BOLD}${CYAN}=============================================================================${RESET}"
        echo -e "${BOLD}${CYAN}                     🎨 Graphics & Design 🎨${RESET}"
        echo -e "${BOLD}${CYAN}=============================================================================${RESET}"
        echo -e "  \033[1;33m1.\033[0m Affinity Suite (Unified v3) ${b_affinity} - Creative Suite with WineFix & High-DPI"
        echo -e "  \033[1;33m2.\033[0m Bambu Studio ${b_bambu} - High-Speed 3D Slicer for Bambu Lab"
        echo -e "  \033[1;33m3.\033[0m Blender ${b_blender} - 3D Creation & Animation Studio"
        echo -e "  \033[1;33m4.\033[0m GOverlay ${b_goverlay} - Vulkan/OpenGL Overlay Config GUI"
        echo -e "  \033[1;33m5.\033[0m Inkscape ${b_inkscape} - Professional Vector Graphics Editor"
        echo -e "  \033[1;33m6.\033[0m MangoHud ${b_mangohud} - Radical In-Game HUD & Telemetry"
        echo -e "  \033[1;33m7.\033[0m Wonder Unit Storyboarder ${b_storyboarder} - Fast Visual Storytelling & Animatics"
        echo -e "  \033[1;33m8.\033[0m $(_ SBO_BACK_OPTION)"
        echo ""
        echo -n "$(_ SELECT_OPERATION_RANGE range="1-8") "
        local sel
        read -r sel || sel="8"
        case "${sel}" in
            1) install_curated_slackbuild "graphics/affinity" "${suite_dir}" ;;
            2) install_curated_slackbuild "graphics/bambu-studio" "${suite_dir}" ;;
            3) install_curated_slackbuild "graphics/blender" "${suite_dir}" ;;
            4) install_curated_slackbuild "graphics/goverlay" "${suite_dir}" ;;
            5) install_curated_slackbuild "graphics/inkscape" "${suite_dir}" ;;
            6) install_curated_slackbuild "graphics/mangohud" "${suite_dir}" ;;
            7) install_curated_slackbuild "graphics/storyboarder" "${suite_dir}" ;;
            8) return 0 ;;
            *) log_warn "Invalid selection." ;;
        esac
        echo ""
        read -r -p "$(_ PRESS_ENTER_CONTINUE) " || true
    done
}

menu_category_multimedia() {
    local suite_dir="$1"
    while true; do
        local b_davinci
        b_davinci=$(get_pkg_badge "davinci-resolve-studio")
        echo ""
        echo -e "${BOLD}${CYAN}=============================================================================${RESET}"
        echo -e "${BOLD}${CYAN}                    🎬 Multimedia & Video 🎬${RESET}"
        echo -e "${BOLD}${CYAN}=============================================================================${RESET}"
        echo -e "  \033[1;33m1.\033[0m DaVinci Resolve Studio ${b_davinci} - Hollywood Post-Production Suite"
        echo -e "  \033[1;33m2.\033[0m $(_ SBO_BACK_OPTION)"
        echo ""
        echo -n "$(_ SELECT_OPERATION_RANGE range="1-2") "
        local sel
        read -r sel || sel="2"
        case "${sel}" in
            1) install_curated_slackbuild "multimedia/davinci-resolve-studio" "${suite_dir}" ;;
            2) return 0 ;;
            *) log_warn "Invalid selection." ;;
        esac
        echo ""
        read -r -p "$(_ PRESS_ENTER_CONTINUE) " || true
    done
}

menu_category_development() {
    local suite_dir="$1"
    while true; do
        local b_unreal
        b_unreal=$(get_pkg_badge "unreal-engine")
        echo ""
        echo -e "${BOLD}${CYAN}=============================================================================${RESET}"
        echo -e "${BOLD}${CYAN}                  🛠️ Development & Engines 🛠️${RESET}"
        echo -e "${BOLD}${CYAN}=============================================================================${RESET}"
        echo -e "  \033[1;33m1.\033[0m Unreal Engine 5 ${b_unreal} - Next-Gen Real-Time 3D Game Engine"
        echo -e "  \033[1;33m2.\033[0m $(_ SBO_BACK_OPTION)"
        echo ""
        echo -n "$(_ SELECT_OPERATION_RANGE range="1-2") "
        local sel
        read -r sel || sel="2"
        case "${sel}" in
            1) install_curated_slackbuild "development/unreal-engine" "${suite_dir}" ;;
            2) return 0 ;;
            *) log_warn "Invalid selection." ;;
        esac
        echo ""
        read -r -p "$(_ PRESS_ENTER_CONTINUE) " || true
    done
}

menu_category_system() {
    local suite_dir="$1"
    while true; do
        local b_ananicy b_gdu b_grub_btrfs b_lact b_openrgb b_snapper b_winetricks
        b_lact=$(get_pkg_badge "lact")
        b_snapper=$(get_pkg_badge "snapper")
        b_grub_btrfs=$(get_pkg_badge "grub-btrfs")
        b_ananicy=$(get_pkg_badge "ananicy-cpp")
        b_gdu=$(get_pkg_badge "gnome-disk-utility")
        b_openrgb=$(get_pkg_badge "openrgb")
        b_winetricks=$(get_pkg_badge "winetricks")
        echo ""
        echo -e "${BOLD}${CYAN}=============================================================================${RESET}"
        echo -e "${BOLD}${CYAN}                   ⚙️ System, Wine & Tuning ⚙️${RESET}"
        echo -e "${BOLD}${CYAN}=============================================================================${RESET}"
        echo -e "  \033[1;33m1.\033[0m LACT ${b_lact} - GPU Control & Overclocking for Radeon & Nvidia"
        echo -e "  \033[1;33m2.\033[0m Snapper ${b_snapper} - Btrfs Snapshot Manager"
        echo -e "  \033[1;33m3.\033[0m GRUB-Btrfs ${b_grub_btrfs} - Bootable Btrfs Snapshots in GRUB"
        echo -e "  \033[1;33m4.\033[0m Ananicy-cpp ${b_ananicy} - Auto-Nice Turbo Boost for Games & Apps"
        echo -e "  \033[1;33m5.\033[0m GNOME Disk Utility ${b_gdu} - Storage, Partitions & SMART Management"
        echo -e "  \033[1;33m6.\033[0m OpenRGB ${b_openrgb} - Open-Source RGB Lighting Control"
        echo -e "  \033[1;33m7.\033[0m Winetricks ${b_winetricks} - Easy Wine Prefix Config & DLL Helper"
        echo -e "  \033[1;33m8.\033[0m $(_ SBO_BACK_OPTION)"
        echo ""
        echo -n "$(_ SELECT_OPERATION_RANGE range="1-8") "
        local sel
        read -r sel || sel="8"
        case "${sel}" in
            1) install_curated_slackbuild "system/lact" "${suite_dir}" ;;
            2) install_curated_slackbuild "system/snapper" "${suite_dir}" ;;
            3) install_curated_slackbuild "system/grub-btrfs" "${suite_dir}" ;;
            4) install_curated_slackbuild "system/ananicy-cpp" "${suite_dir}" ;;
            5) install_curated_slackbuild "system/gnome-disk-utility" "${suite_dir}" ;;
            6) install_curated_slackbuild "system/openrgb" "${suite_dir}" ;;
            7) install_curated_slackbuild "system/winetricks" "${suite_dir}" ;;
            8) return 0 ;;
            *) log_warn "Invalid selection." ;;
        esac
        echo ""
        read -r -p "$(_ PRESS_ENTER_CONTINUE) " || true
    done
}

menu_category_office() {
    local suite_dir="$1"
    while true; do
        local b_fo
        b_fo=$(get_pkg_badge "freeoffice2024")
        echo ""
        echo -e "${BOLD}${CYAN}=============================================================================${RESET}"
        echo -e "${BOLD}${CYAN}                  🏢 Office & Productivity 🏢${RESET}"
        echo -e "${BOLD}${CYAN}=============================================================================${RESET}"
        echo -e "  \033[1;33m1.\033[0m FreeOffice 2024 ${b_fo} - Microsoft Office Compatible Suite"
        echo -e "  \033[1;33m2.\033[0m $(_ SBO_BACK_OPTION)"
        echo ""
        echo -n "$(_ SELECT_OPERATION_RANGE range="1-2") "
        local sel
        read -r sel || sel="2"
        case "${sel}" in
            1) install_curated_slackbuild "office/freeoffice2024" "${suite_dir}" ;;
            2) return 0 ;;
            *) log_warn "Invalid selection." ;;
        esac
        echo ""
        read -r -p "$(_ PRESS_ENTER_CONTINUE) " || true
    done
}

menu_category_libraries() {
    local suite_dir="$1"
    while true; do
        local b_handy
        b_handy=$(get_pkg_badge "libhandy")
        echo ""
        echo -e "${BOLD}${CYAN}=============================================================================${RESET}"
        echo -e "${BOLD}${CYAN}                   📚 Libraries & Drivers 📚${RESET}"
        echo -e "${BOLD}${CYAN}=============================================================================${RESET}"
        echo -e "  \033[1;33m1.\033[0m LibHandy ${b_handy} - GTK Adaptive UI Library"
        echo -e "  \033[1;33m2.\033[0m $(_ SBO_BACK_OPTION)"
        echo ""
        echo -n "$(_ SELECT_OPERATION_RANGE range="1-2") "
        local sel
        read -r sel || sel="2"
        case "${sel}" in
            1) install_curated_slackbuild "libraries/libhandy" "${suite_dir}" ;;
            2) return 0 ;;
            *) log_warn "Invalid selection." ;;
        esac
        echo ""
        read -r -p "$(_ PRESS_ENTER_CONTINUE) " || true
    done
}

manage_curated_suite_interactive() {
    local suite_dir="${SLACKY_SLACKBUILDS_DIR:-/var/cache/slacky-update/slacky-slackbuilds}"
    local bundled_assets=""
    for cand in "${APP_DIR}/../assets/slacky-slackbuilds" "${APP_DIR}/assets/slacky-slackbuilds" "/usr/share/slacky-update/assets/slacky-slackbuilds" "/usr/local/lib/slacky-update/assets/slacky-slackbuilds"; do
        if [ -d "${cand}" ]; then
            bundled_assets="${cand}"
            break
        fi
    done

    if [ -n "${bundled_assets}" ] && [ -d "${bundled_assets}" ]; then
        sudo mkdir -p "${suite_dir}"
        sudo cp -a "${bundled_assets}"/* "${suite_dir}/" 2>/dev/null || true
    fi

    while true; do
        echo ""
        echo -e "${BOLD}${CYAN}=============================================================================${RESET}"
        echo -e "${BOLD}${CYAN}                  ⚡ SLACKY-SLACKBUILDS CURATED HUB ⚡${RESET}"
        echo -e "${BOLD}${CYAN}=============================================================================${RESET}"
        echo -e "  \033[1;33m1.\033[0m 🎮 Games & Launchers (Faugus)"
        echo -e "  \033[1;33m2.\033[0m 🎨 Graphics & Design (Bambu Studio, Blender, MangoHud, GOverlay, Inkscape, Storyboarder)"
        echo -e "  \033[1;33m3.\033[0m 🎬 Multimedia & Video (DaVinci Resolve Studio)"
        echo -e "  \033[1;33m4.\033[0m ⚙️ System, Wine & Tuning (LACT, Snapper, GRUB-Btrfs, Ananicy-cpp, GNOME Disk Utility, OpenRGB, Winetricks)"
        echo -e "  \033[1;33m5.\033[0m 🏢 Office & Productivity (FreeOffice 2024)"
        echo -e "  \033[1;33m6.\033[0m 📚 Libraries & Drivers (LibHandy)"
        echo -e "  \033[1;33m7.\033[0m $(_ SBO_BACK_OPTION)"
        echo ""
        echo -n "$(_ SELECT_OPERATION_RANGE range="1-7") "
        local cat_sel
        read -r cat_sel || cat_sel="7"

        case "${cat_sel}" in
            1) menu_category_games "${suite_dir}" ;;
            2) menu_category_graphics "${suite_dir}" ;;
            3) menu_category_multimedia "${suite_dir}" ;;
            4) menu_category_system "${suite_dir}" ;;
            5) menu_category_office "${suite_dir}" ;;
            6) menu_category_libraries "${suite_dir}" ;;
            7) return 0 ;;
            *) log_warn "Invalid selection." ;;
        esac
    done
}

manage_slackbuilds_interactive() {
    if ! is_sbotools_installed; then
        setup_sbotools_interactive
    fi
    auto_refresh_sbo_tree_if_stale

    while true; do
        echo ""
        echo -e "${BOLD}Slacky-Update (SlackBuilds & Tweaks)${RESET}"
        echo -e "${BOLD}$(_ SBO_MAIN_HUB_TITLE)${RESET}"
        echo -e "  \033[1;33m1.\033[0m $(_ SBO_MENU_SEARCH_AND_RECOMMENDED)"
        echo -e "  \033[1;33m2.\033[0m $(_ SBO_MENU_CURATED_SUITE)"
        echo -e "  \033[1;33m3.\033[0m $(_ MENU_OPTIONAL_TWEAKS)"
        echo -e "  \033[1;33m4.\033[0m $(_ CATCH_YOU_FLIP_SIDE)"
        echo ""
        echo -n "$(_ SELECT_OPERATION_RANGE range="1-4") "
        local opt
        read -r opt || opt="4"

        case "${opt}" in
            1)
                search_sbo_interactive
                ;;
            2)
                manage_curated_suite_interactive
                ;;
            3)
                manage_tweaks_interactive
                ;;
            4)
                return 0
                ;;
            *)
                log_warn "Invalid selection."
                ;;
        esac
    done
}
