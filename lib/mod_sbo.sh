#!/usr/bin/env bash
# --- [ SLACKY-UPDATE SBO & SLACKBUILDS MODULE ] ---

set -euo pipefail

# 6A-299 (F0): read the real Slackware release. Prints "<N.N> stable" for a release (15.0, 16.0), "<N.N> current" for a
# -current tree (15.0+, 16.0+) and "unknown" when the file is missing or says something else. It never guesses 15.0.
# SLACKY_SLACKWARE_VERSION_FILE lets the self-tests (SLACKY_SELFTEST=1 only) point at a fake file.
slackware_release_info() {
    local vf="/etc/slackware-version" line=""
    [ "${SLACKY_SELFTEST:-0}" = "1" ] && vf="${SLACKY_SLACKWARE_VERSION_FILE:-${vf}}"
    [ -r "${vf}" ] && line=$(head -n 1 "${vf}" 2>/dev/null | tr -d '\r' || true)
    if [[ "${line}" =~ ^Slackware[[:space:]]+([0-9]+\.[0-9]+)(\+?)[[:space:]]*$ ]]; then
        if [ -n "${BASH_REMATCH[2]}" ]; then
            echo "${BASH_REMATCH[1]} current"
        else
            echo "${BASH_REMATCH[1]} stable"
        fi
    else
        echo "unknown"
    fi
}

# 6A-299 (F0): which AlienBOB multilib tree matches this system. Prints the tree name ("15.0", "16.0" or "current") and
# returns 0; prints nothing and returns 1 when the release is unknown. A release only ever maps to ITS OWN tree: 16.0
# never falls back to 15.0 (that would put an older glibc and gcc on the system).
slackware_multilib_tree() {
    local info ver chan
    info=$(slackware_release_info)
    [ "${info}" != "unknown" ] || return 1
    ver="${info%% *}"; chan="${info##* }"
    if [ "${chan}" = "current" ]; then
        echo "current"
    else
        echo "${ver}"
    fi
}

# 6A-299 (F0): never downgrade. DIR holds the verified multilib packages; any package whose version is OLDER than the
# installed package of the same name stops the whole setup before upgradepkg runs. SLACKY_PKGLOG_DIR is for the self-tests (SLACKY_SELFTEST=1 only).
multilib_refuse_downgrade() {
    local dir="$1" logdir="/var/log/packages" f base name ver inst inst_ver
    [ "${SLACKY_SELFTEST:-0}" = "1" ] && logdir="${SLACKY_PKGLOG_DIR:-${logdir}}"
    while IFS= read -r f; do
        [ -n "${f}" ] || continue
        base=$(basename "${f}"); base="${base%.*}"
        [[ "${base}" =~ ^(.+)-([^-]+)-([^-]+)-([^-]+)$ ]] || continue
        name="${BASH_REMATCH[1]}"; ver="${BASH_REMATCH[2]}"
        for inst in "${logdir}"/"${name}"-*; do
            [ -e "${inst}" ] || continue
            [[ "$(basename "${inst}")" =~ ^(.+)-([^-]+)-([^-]+)-([^-]+)$ ]] || continue
            [ "${BASH_REMATCH[1]}" = "${name}" ] || continue
            inst_ver="${BASH_REMATCH[2]}"
            if [ "${inst_ver}" != "${ver}" ] && [ "$(printf '%s\n%s\n' "${inst_ver}" "${ver}" | sort -V | tail -n 1)" = "${inst_ver}" ]; then
                log_error "The multilib packages are older than what is installed (${name} ${ver} instead of ${inst_ver}), so nothing was installed."
                return 1
            fi
        done
    done < <(find "${dir}" -name '*.t?z' 2>/dev/null)
    return 0
}

is_sbotools_installed() {
    command -v sboinstall >/dev/null 2>&1 && command -v sbocheck >/dev/null 2>&1
}

setup_sbotools_interactive() {
    echo -e "
$(_ SBO_SETUP_HEADER)"
    
    # 6A-299 (F0): the real release decides; only 15.0 and -current have a known SlackBuilds setup here
    local slack_ver="" rel_info is_current=false
    rel_info=$(slackware_release_info)
    case "${rel_info}" in
        *" current") is_current=true; slack_ver="current" ;;
        "15.0 stable") slack_ver="15.0" ;;
        *)
            log_warn "SlackBuilds setup was not started: this Slackware version (${rel_info}) has no matching SlackBuilds setup here. Nothing was changed."
            return 0
            ;;
    esac

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
        # 6A-49: private work and output dirs (was the fixed /tmp/sbotools-bootstrap and "newest /tmp/sbotools-*.txz")
        local sbo_tmp sbo_out
        sbo_tmp=$(mktemp -d "${TMPDIR:-/tmp}/sbotools-bootstrap.XXXXXX") || return 1
        sbo_out="${sbo_tmp}/out"
        mkdir -p "${sbo_out}"
        pushd "${sbo_tmp}" >/dev/null

        local sbotools_tar="sbotools-3.6.tar.gz"
        local sbotools_sb="sbotools.tar.gz"
        
        # Download sbotools SlackBuild
        # 6A-144: curl -f (an HTTP error page is never saved as a script) and every recipe file root runs or packages
        # is checked against a pinned sha256 (sbotools 4.4.2, identical on Ponce current and SBo 15.0, 2026-10-13).
        # A newer upstream recipe is refused until the pins are updated.
        local fetch_ok=1
        if [ "${is_current}" = "true" ]; then
            local sbo_f
            for sbo_f in sbotools.SlackBuild sbotools.info slack-desc doinst.sh; do
                curl -fsSL --connect-timeout 8 -m 20 "https://raw.githubusercontent.com/Ponce/slackbuilds/current/system/sbotools/${sbo_f}" -o "${sbo_f}" || fetch_ok=0
            done
        else
            if curl -fsSL --connect-timeout 8 -m 30 "https://slackbuilds.org/slackbuilds/15.0/system/sbotools.tar.gz" -o "${sbotools_sb}" \
                && tar -zxf "${sbotools_sb}" && [ -d sbotools ]; then
                cd sbotools
            else
                fetch_ok=0
            fi
        fi
        local pin_line pin_bad=0
        for pin_line in \
            "3a6d888067b707d8d33c179edf7df6930021d422ac9813cd8eda2e7d9ae9db2e sbotools.SlackBuild" \
            "f3f6af7eb0942c55009bf7500ad31143dbc920515d1e327974c3beb04d36c955 sbotools.info" \
            "50aa975d3e0e71e4a832fec2f66d7d69fa0ea8e08b121ff1ea74358095d55869 slack-desc" \
            "773cd312476edb493437d94e110fd9c5ad48615dd75f9510fcd9b658d9508827 doinst.sh"; do
            [ "$(sha256sum "${pin_line#* }" 2>/dev/null | awk '{print $1}')" = "${pin_line%% *}" ] || pin_bad=1
        done
        if [ "${fetch_ok}" -ne 1 ] || [ "${pin_bad}" -ne 0 ]; then
            log_error "The sbotools recipe could not be downloaded or does not match the known version, so it was not built. Nothing was installed."
            popd >/dev/null
            rm -rf "${sbo_tmp}"
            return 1
        fi

        # Source download URL from info
        local dl_url
        dl_url=$(grep "^DOWNLOAD=" sbotools.info 2>/dev/null | cut -d'"' -f2 || true)
        dl_url=${dl_url:-https://github.com/duganchen/sbotools/archive/v3.6/sbotools-3.6.tar.gz}
        # the SlackBuild looks for the source under its own file name (was always sbotools-3.6.tar.gz)
        sbotools_tar=$(basename "${dl_url}")
        curl -fsSL --connect-timeout 10 --speed-limit 1024 --speed-time 25 "${dl_url}" -o "${sbotools_tar}" || true

        # 6A-49: the source must match the checksum published in the SlackBuild's .info file
        local want_md5 have_md5
        want_md5=$(grep '^MD5SUM=' sbotools.info 2>/dev/null | cut -d'"' -f2 | awk '{print $1}')
        have_md5=$(md5sum "${sbotools_tar}" 2>/dev/null | awk '{print $1}')
        if [[ ! "${dl_url}" =~ ^https:// ]] || [ -z "${want_md5}" ] || [ "${want_md5}" != "${have_md5}" ]; then
            log_error "The sbotools download does not match its published checksum, so it was not built. Nothing was installed."
            popd >/dev/null
            rm -rf "${sbo_tmp}"
            return 1
        fi

        chmod +x sbotools.SlackBuild
        sudo env OUTPUT="${sbo_out}" TMP="${sbo_tmp}/build" ./sbotools.SlackBuild
        local built_pkg
        built_pkg=$(ls -t "${sbo_out}"/sbotools-*-noarch-*.txz 2>/dev/null | head -n 1 || true)
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
    
    local sync_file="/var/cache/slacky-update/sbo_last_sync"
    local now_ts last_sync diff_hours
    now_ts=$(date +%s)
    last_sync=0
    if [ -f "${sync_file}" ]; then
        last_sync=$(cat "${sync_file}" 2>/dev/null || echo 0)
    fi
    if [ "${last_sync}" -eq 0 ]; then
        last_sync=$(stat -c %Y /var/lib/sbotools/repo 2>/dev/null || echo 0)
    fi
    diff_hours=$(( (now_ts - last_sync) / 3600 ))

    if [ "${diff_hours}" -ge 24 ]; then
        log_info "$(_ SBO_SYNCING_INTEL)"
        sudo sbosnap fetch >/dev/null 2>&1 || true
        sudo mkdir -p /var/cache/slacky-update 2>/dev/null || true
        echo "${now_ts}" | sudo tee "${sync_file}" >/dev/null 2>&1 || true
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

    # 6A-299 (F0): decide the multilib tree BEFORE asking anything. Unknown release: refuse, change nothing.
    local slack_ver=""
    if ! slack_ver=$(slackware_multilib_tree); then
        log_error "Multilib was not set up: this Slackware version is not recognised, so no matching multilib packages are known. Nothing was changed."
        return 1
    fi
    log_warn "$(_ STEAM_MULTILIB_REQUIRED)"
    
    local reply_multi
    read -r -p "$(_ PROMPT_SETUP_MULTILIB) " reply_multi
    reply_multi=${reply_multi:-Y}
    if [[ ! "$reply_multi" =~ ^[YyJjSsOo]$ ]]; then
        log_warn "Multilib setup aborted by user."
        return 1
    fi

    log_info "Fetching AlienBOB multilib packages for Slackware ${slack_ver}..."
    # 6A-3: packages that replace glibc/gcc and add the compat32 tree are now verified before install. Before: plain
    # http, no signature check, a fixed /tmp directory, a curl fallback that downloaded nothing, and "|| true" that
    # reported success anyway. Now: https, AlienBOB's key pinned by fingerprint, the signed CHECKSUMS.md5 verified,
    # every package checked against it, and upgradepkg only when everything matches.
    local multi_url="https://bear.alienbase.nl/mirrors/people/alien/multilib/${slack_ver}"
    local multi_tmp
    multi_tmp=$(mktemp -d /tmp/slacky-multilib.XXXXXX) || { log_error "Could not create a temporary directory."; return 1; }
    if ! alien_fetch_verified "${multi_url}" "${multi_tmp}"; then
        rm -rf "${multi_tmp}"
        log_error "Multilib packages could not be verified, so nothing was installed."
        return 1
    fi

    # 6A-299 (F0): a tree that does not exist (404 above) already stopped here; a tree that carries older glibc/gcc than
    # the installed ones stops here too
    if ! multilib_refuse_downgrade "${multi_tmp}/pkgs"; then
        rm -rf "${multi_tmp}"
        return 1
    fi

    log_info "Upgrading to multilib core packages..."
    local multi_rc=0
    ( cd "${multi_tmp}/pkgs" && find . -name '*.t?z' -print0 | xargs -0 sudo "${PKG_UPGRADE_CMD}" --reinstall --install-new ) || multi_rc=$?
    rm -rf "${multi_tmp}"
    if [ "${multi_rc}" -ne 0 ]; then
        log_error "Installing the multilib packages failed (exit ${multi_rc}). Check the messages above."
        return 1
    fi
    log_success "Multilib environment successfully installed and activated!"
    return 0
}

# 6A-3: AlienBOB (Eric Hameleers) signing keys, pinned. The multilib tree is signed with his 2003 DSA key (F2CE...BDA0,
# verified 2026-10-12 against multilib/current/CHECKSUMS.md5.asc); his 2016 RSA key (2AD1...E011) signs newer trees.
ALIEN_GPG_FPRS="F2CE1B92EE1F2C0CE97E581E5E56AAAFA75CBDA0 2AD107EAF45132C8A991F4F9883EC63B769EE011"

# alien_fetch_verified BASE_URL WORKDIR: import AlienBOB's key into a private keyring, require the pinned fingerprint,
# verify the signed CHECKSUMS.md5, then download every listed multilib package (top level + slackware64-compat32) over
# https into WORKDIR/pkgs and check each md5 against the signed list. Returns non-zero on any failure.
alien_fetch_verified() {
    local base="$1" work="$2" gh fpr f list n=0 rel sum got
    command -v gpg >/dev/null 2>&1 || { log_error "gpg is missing, so the packages cannot be verified."; return 1; }
    gh="${work}/gnupg"; mkdir -p -m 0700 "${gh}" "${work}/pkgs"
    curl -fsSL --connect-timeout 10 -o "${work}/GPG-KEY" "${base}/GPG-KEY" || { log_error "Could not download the AlienBOB signing key."; return 1; }
    gpg --homedir "${gh}" --batch --quiet --import "${work}/GPG-KEY" 2>/dev/null || { log_error "Could not read the AlienBOB signing key."; return 1; }
    # every imported primary key must be one of the pinned ones (a key file with any other key is refused)
    fpr=$(gpg --homedir "${gh}" --batch --with-colons --fingerprint 2>/dev/null | awk -F: '/^pub:/ {p=1; next} p && /^fpr:/ {print $10; p=0}')
    [ -n "${fpr}" ] || { log_error "The AlienBOB signing key could not be read."; return 1; }
    for f in ${fpr}; do
        case " ${ALIEN_GPG_FPRS} " in
            *" ${f} "*) ;;
            *) log_error "The AlienBOB signing key does not have the expected fingerprint. Nothing was downloaded."; return 1 ;;
        esac
    done
    curl -fsSL --connect-timeout 10 -o "${work}/CHECKSUMS.md5" "${base}/CHECKSUMS.md5" \
        && curl -fsSL --connect-timeout 10 -o "${work}/CHECKSUMS.md5.asc" "${base}/CHECKSUMS.md5.asc" \
        || { log_error "Could not download the multilib checksum list."; return 1; }
    gpg --homedir "${gh}" --batch --quiet --verify "${work}/CHECKSUMS.md5.asc" "${work}/CHECKSUMS.md5" 2>/dev/null \
        || { log_error "The multilib checksum list has no valid AlienBOB signature."; return 1; }
    list=$(awk '$2 ~ /\.t[gx]z$/ { p=$2; sub(/^\.\//, "", p); if (p !~ /\// || p ~ /^slackware64-compat32\//) print $1 " " p }' "${work}/CHECKSUMS.md5")
    [ -n "${list}" ] || { log_error "The multilib checksum list contains no packages."; return 1; }
    while read -r sum rel; do
        [ -n "${rel}" ] || continue
        case "${rel}" in *..*|/*) log_error "Unexpected path in checksum list: ${rel}"; return 1 ;; esac
        mkdir -p "${work}/pkgs/$(dirname "${rel}")"
        curl -fsSL --connect-timeout 10 --speed-limit 1024 --speed-time 25 -o "${work}/pkgs/${rel}" "${base}/${rel}" \
            || { log_error "Download failed: ${rel}"; return 1; }
        got=$(md5sum "${work}/pkgs/${rel}" | awk '{print $1}')
        [ "${got}" = "${sum}" ] || { log_error "Checksum mismatch: ${rel}"; return 1; }
        n=$((n + 1))
    done <<EOF_ALIEN_LIST
${list}
EOF_ALIEN_LIST
    log_info "Verified ${n} multilib packages against AlienBOB's signed checksum list."
    return 0
}

manage_recommended_gaming_interactive() {
    local tui_py="${APP_DIR:-}/slacky_tui.py"
    [ ! -f "${tui_py}" ] && [ -f "/usr/share/slacky-update/lib/slacky_tui.py" ] && tui_py="/usr/share/slacky-update/lib/slacky_tui.py"

    while true; do
        local sel=""
        if [ -f "${tui_py}" ] && command -v python3 >/dev/null 2>&1 && [ -t 0 ]; then
            sel=$(python3 "${tui_py}" --mode sbo-recommended)
        else
            echo ""
            echo -e "${BOLD}${CYAN}=============================================================================${RESET}"
            echo -e "${BOLD}${CYAN}              $(_ RECOMMENDED_GAMING_TITLE)${RESET}"
            echo -e "${BOLD}${CYAN}=============================================================================${RESET}"
            echo -e "  \033[1;33m1.\033[0m OBS Studio (multimedia/obs-studio)"
            echo -e "  \033[1;33m2.\033[0m Steam Client (games/steam)"
            echo -e "  \033[1;33m3.\033[0m Discord (network/discord)"
            echo -e "  \033[1;33m4.\033[0m ProtonPlus (games/protonplus)"
            echo -e "  \033[1;33m5.\033[0m $(_ SBO_BACK_OPTION)"
            echo ""
            echo -n "$(_ SELECT_OPERATION_RANGE range="1-5") "
            read -r sel || sel="5"
        fi

        sel=$(echo "${sel}" | xargs)

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
                # 6A-3: the old fallback fetched a fixed, now missing (404) AlienBOB Steam package without a signature check.
                sudo sboinstall steam || log_warn "Steam could not be built from SlackBuilds.org. Install it from AlienBOB's repository with slackpkg+ (multilib), which checks the signature."
                ;;
            3)
                sudo sboinstall discord
                ;;
            4)
                sudo sboinstall protonplus
                ;;
            5|Q|q|"")
                return 0
                ;;
            *)
                log_warn "Invalid selection: ${sel}"
                ;;
        esac
        echo ""
        read -r -p "$(_ PRESS_ENTER_CONTINUE) " || true
    done
}

search_sbo_interactive() {
    local tui_py="${APP_DIR:-}/slacky_tui.py"
    [ ! -f "${tui_py}" ] && [ -f "/usr/share/slacky-update/lib/slacky_tui.py" ] && tui_py="/usr/share/slacky-update/lib/slacky_tui.py"

    while true; do
        local sel=""
        if [ -f "${tui_py}" ] && command -v python3 >/dev/null 2>&1 && [ -t 0 ]; then
            sel=$(python3 "${tui_py}" --mode sbo-search)
        else
            echo ""
            echo -e "${BOLD}${CYAN}=============================================================================${RESET}"
            echo -e "${BOLD}${CYAN}              $(_ SBO_SEARCH_PROMPT_TITLE)${RESET}"
            echo -e "${BOLD}${CYAN}=============================================================================${RESET}"
            echo -e "  \033[1;33m1.\033[0m $(_ SBO_CUSTOM_SEARCH_OPTION)"
            echo -e "  \033[1;33m2.\033[0m $(_ SBO_RECOMMENDED_GAMING_OPTION)"
            echo -e "  \033[1;33m3.\033[0m $(_ SBO_BACK_OPTION)"
            echo ""
            echo -n "$(_ SELECT_OPERATION_RANGE range="1-3") "
            read -r sel || sel="3"
        fi

        sel=$(echo "${sel}" | xargs)

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
            3|Q|q|"")
                return 0
                ;;
            *)
                log_warn "Invalid selection: ${sel}"
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

    # 6A-1: the recipe script is <name>.SlackBuild (was never assigned -> set -u abort)
    local prg_base
    prg_base=$(basename "${prg}")
    local sb_script="${prg_base}.SlackBuild"
    if [ ! -f "${pkg_path}/${sb_script}" ]; then
        log_error "SlackBuild script ${sb_script} not found in ${pkg_path}."
        return 1
    fi

    # Create isolated ephemeral build workspace (mktemp 0700, user-owned copy of the recipe)
    local build_tmp
    build_tmp=$(mktemp -d /tmp/slacky-build-XXXXXX)
    cp -a "${pkg_path}"/. "${build_tmp}/"

    pushd "${build_tmp}" >/dev/null
    local target_user="${SUDO_USER:-${USER:-$(id -un)}}"
    local target_home
    target_home=$(getent passwd "${target_user}" 2>/dev/null | cut -d: -f6)
    [ -n "${target_home}" ] && [ -d "${target_home}" ] || target_home="${HOME:-/tmp}"
    local user_dl="${target_home}/Downloads"

    # Special handling for DaVinci Resolve Studio
    if [ "${prg}" = "multimedia/davinci-resolve-studio" ]; then
        local found_zip
        # 6A-144: never pick sources from world-writable /tmp (another user could plant them; the build runs as root)
        found_zip=$(ls "${user_dl}"/DaVinci_Resolve_Studio_*_Linux.zip ~/Downloads/DaVinci_Resolve_Studio_*_Linux.zip "${pkg_path}"/DaVinci_Resolve_Studio_*_Linux.zip 2>/dev/null | head -n 1 || true)
        if [ -n "${found_zip}" ]; then
            cp -f "${found_zip}" "${build_tmp}/"
        else
            echo ""
            echo -e "${YELLOW}${BOLD}$(_ DAVINCI_DOWNLOAD_REQUIRED)${RESET}"
            echo -e "Download link: ${CYAN}https://www.blackmagicdesign.com/products/davinciresolve/studio${RESET}"
            echo -e "Place the DaVinci_Resolve_Studio_<VERSION>_Linux.zip file in ~/Downloads\n"
            read -r -p "$(_ PROMPT_CONTINUE_DAVINCI) " reply_dv
            if [[ ! "$reply_dv" =~ ^[YyJjSsOo]$ ]]; then
                log_warn "DaVinci Resolve installation canceled."
                popd >/dev/null
                sudo rm -rf "${build_tmp}"
                return 0
            fi
            found_zip=$(ls "${user_dl}"/DaVinci_Resolve_Studio_*_Linux.zip ~/Downloads/DaVinci_Resolve_Studio_*_Linux.zip 2>/dev/null | head -n 1 || true)
            if [ -n "${found_zip}" ]; then
                cp -f "${found_zip}" "${build_tmp}/"
            fi
        fi
    fi

    # Special handling for FreeOffice 2024
    if [ "${prg}" = "office/freeoffice2024" ]; then
        local found_fo
        found_fo=$(ls "${user_dl}"/softmaker-freeoffice-*.tgz ~/Downloads/softmaker-freeoffice-*.tgz "${pkg_path}"/softmaker-freeoffice-*.tgz 2>/dev/null | head -n 1 || true)  # 6A-144: no /tmp
        if [ -n "${found_fo}" ]; then
            cp -f "${found_fo}" "${build_tmp}/"
        fi
    fi

    # Generic automated source downloader from .info file
    # 6A-1: the bundled .info is read as shell (SBo format, multi-line DOWNLOAD works) and every source with a
    # listed MD5SUM is verified, cached copies included.
    local info_file="${prg_base}.info"
    if [ -f "${info_file}" ]; then
        local dl_urls="" dl_md5s=""
        if [ "$(uname -m)" = "x86_64" ]; then
            dl_urls=$( ( . "./${info_file}" >/dev/null 2>&1; echo "${DOWNLOAD_x86_64:-}" ) )
            dl_md5s=$( ( . "./${info_file}" >/dev/null 2>&1; echo "${MD5SUM_x86_64:-}" ) )
            case "${dl_urls}" in UNSUPPORTED|UNTESTED|MANUAL) dl_urls="" ;; esac
        fi
        if [ -z "${dl_urls// /}" ]; then
            dl_urls=$( ( . "./${info_file}" >/dev/null 2>&1; echo "${DOWNLOAD:-}" ) )
            dl_md5s=$( ( . "./${info_file}" >/dev/null 2>&1; echo "${MD5SUM:-}" ) )
            case "${dl_urls}" in UNSUPPORTED|UNTESTED|MANUAL) dl_urls="" ;; esac
        fi
        local -a md5_list=()
        read -r -a md5_list <<< "${dl_md5s}" || true
        local url_idx=0

        if [ -n "${dl_urls// /}" ]; then
            for url in ${dl_urls}; do
                local want_md5="${md5_list[url_idx]:-}"
                url_idx=$((url_idx + 1))
                local filename
                filename=$(basename "${url}")
                local found_cache
                found_cache=$(ls "${build_tmp}/${filename}" \
                                 "/var/cache/slacky-update/archives/${filename}" \
                                 "${user_dl}/${filename}" \
                                 "${HOME}/Downloads/${filename}" 2>/dev/null | head -n 1 || true)  # 6A-144: no /tmp
                if [ -n "${found_cache}" ] && [ -f "${found_cache}" ]; then
                    if [ "${found_cache}" != "${build_tmp}/${filename}" ]; then
                        log_info "Using cached source: ${found_cache}"
                        cp -f "${found_cache}" "${build_tmp}/"
                    fi
                else
                    log_info "Downloading source archive: ${url} ..."
                    sudo mkdir -p /var/cache/slacky-update/archives 2>/dev/null || true
                    if download_parallel_pacman "SBo: ${filename}" "${url}|${build_tmp}/${filename}"; then
                        sudo cp -f "${build_tmp}/${filename}" "/var/cache/slacky-update/archives/${filename}" 2>/dev/null || true
                    elif wget -c --timeout=30 --tries=3 "${url}" -O "${build_tmp}/${filename}"; then   # 6A-317 (N3): a stalled server cannot hang the build
                        sudo cp -f "${build_tmp}/${filename}" "/var/cache/slacky-update/archives/${filename}" 2>/dev/null || true
                    elif curl -fL --connect-timeout 15 -m 1800 --speed-limit 1000 --speed-time 45 -o "${build_tmp}/${filename}" "${url}"; then
                        sudo cp -f "${build_tmp}/${filename}" "/var/cache/slacky-update/archives/${filename}" 2>/dev/null || true
                    else
                        log_warn "Download failed for ${url}."
                    fi
                fi
                if [ -n "${want_md5}" ] && [ -f "${build_tmp}/${filename}" ]; then
                    local got_md5
                    got_md5=$(md5sum "${build_tmp}/${filename}" | cut -d' ' -f1)
                    if [ "${got_md5}" != "${want_md5}" ]; then
                        log_error "${filename} does not match its checksum. ${prg_base} was not built."
                        popd >/dev/null
                        sudo rm -rf "${build_tmp}" 2>/dev/null || true
                        return 1
                    fi
                else
                    # 6A-144: an unverifiable or missing source is refused (the build runs as root)
                    if [ -f "${build_tmp}/${filename}" ]; then
                        log_error "${filename} has no checksum in the recipe, so ${prg_base} was not built."
                    else
                        log_error "${filename} could not be downloaded, so ${prg_base} was not built."
                    fi
                    popd >/dev/null
                    sudo rm -rf "${build_tmp}" 2>/dev/null || true
                    return 1
                fi
            done
        fi
    fi

    # 6A-1: build output and work files stay inside the private workspace (no fixed /tmp paths as root)
    log_info "Building and packaging ${prg} in isolated workspace..."
    chmod +x "${sb_script}"
    mkdir -p "${build_tmp}/out" "${build_tmp}/SBo"
    if ! sudo env TMP="${build_tmp}/SBo" OUTPUT="${build_tmp}/out" "./${sb_script}"; then
        log_error "Building ${prg_base} failed. Nothing was installed."
        popd >/dev/null
        sudo rm -rf "${build_tmp}" 2>/dev/null || true
        return 1
    fi

    local built_pkg
    built_pkg=$(ls -t "${build_tmp}/out/${prg_base}"-*-*.t?z 2>/dev/null | head -n 1 || true)
    local rc=0
    if [ -z "${built_pkg}" ] || [ ! -f "${built_pkg}" ]; then
        log_error "${prg_base} built no package. Nothing was installed."
        rc=1
    elif sudo "${PKG_UPGRADE_CMD}" --reinstall --install-new "${built_pkg}"; then
        log_success "${prg_base} installed and active!"
    else
        log_error "Installing ${prg_base} failed."
        rc=1
    fi
    popd >/dev/null
    sudo rm -rf "${build_tmp}" 2>/dev/null || true
    return "${rc}"
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
        grub-btrfs)
            [ -f "/etc/default/grub-btrfs/config" ] || [ -f "/etc/grub.d/41_snapshots-btrfs" ] || command -v grub-btrfs >/dev/null 2>&1
            ;;
        davinci*|davinci-resolve-studio)
            [ -d "/opt/resolve" ] || [ -f "/opt/resolve/bin/resolve" ]
            ;;
        unreal*|unreal-engine)
            [ -d "/opt/unreal-engine" ] || [ -f "/usr/bin/unreal-engine" ] || [ -f "/usr/bin/UnrealEditor" ]
            ;;
        freeoffice*|freeoffice2024)
            [ -d "/usr/lib/softmaker2024" ] || [ -d "/opt/freeoffice2024" ] || [ -f "/usr/bin/freeoffice2024" ]
            ;;
        wine-staging)
            command -v wine >/dev/null 2>&1
            ;;
        winetricks)
            command -v winetricks >/dev/null 2>&1
            ;;
        snapper)
            command -v snapper >/dev/null 2>&1
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

is_curated_sbo_whitelisted() {
    local prg="$1"
    # Whitelist of tested & verified standalone SlackBuilds
    case "${prg}" in
        davinci-resolve-studio|\
        unreal-engine|\
        freeoffice2024|\
        snapper|grub-btrfs|wine-staging|winetricks)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

render_curated_category_menu() {
    local cat_title="$1"
    local suite_dir="$2"
    shift 2
    local entries=("$@")

    while true; do
        local items_name=()
        local items_path=()
        local items_desc=()

        for ((i=0; i<${#entries[@]}; i+=3)); do
            local prg="${entries[i]}"
            local path="${entries[i+1]}"
            local desc="${entries[i+2]}"

            if ! is_curated_sbo_whitelisted "${prg}"; then
                continue
            fi

            local b_badge
            b_badge=$(get_pkg_badge "${prg}")
            items_name+=("${path##*/} ${b_badge}")
            items_path+=("${path}")
            items_desc+=("${desc}")
        done

        echo ""
        echo -e "${BOLD}${CYAN}=============================================================================${RESET}"
        echo -e "${BOLD}${CYAN}                     ${cat_title}${RESET}"
        echo -e "${BOLD}${CYAN}=============================================================================${RESET}"

        local idx=1
        if [ ${#items_name[@]} -eq 0 ]; then
            echo -e "  \033[1;30m(No verified packages currently available in this category)\033[0m"
        else
            for ((j=0; j<${#items_name[@]}; j++)); do
                echo -e "  \033[1;33m${idx}.\033[0m ${items_name[j]} - ${items_desc[j]}"
                idx=$((idx + 1))
            done
        fi

        echo -e "  \033[1;33m${idx}.\033[0m $(_ SBO_BACK_OPTION)"
        echo ""
        echo -n "$(_ SELECT_OPERATION_RANGE range="1-${idx}") "
        local sel
        read -r sel || sel="${idx}"

        if [ "${sel}" -eq "${idx}" ]; then
            return 0
        elif [ "${sel}" -ge 1 ] && [ "${sel}" -lt "${idx}" ]; then
            local sel_idx=$((sel - 1))
            install_curated_slackbuild "${items_path[sel_idx]}" "${suite_dir}" || true
        else
            log_warn "Invalid selection."
        fi
        echo ""
        read -r -p "$(_ PRESS_ENTER_CONTINUE) " || true
    done
}

menu_category_multimedia() {
    local suite_dir="$1"
    render_curated_category_menu "Multimedia & Video" "${suite_dir}" \
        "davinci-resolve-studio" "multimedia/davinci-resolve-studio" "Hollywood Post-Production Suite"
}

menu_category_development() {
    local suite_dir="$1"
    render_curated_category_menu "Development & Engines" "${suite_dir}" \
        "unreal-engine" "development/unreal-engine" "Next-Gen Real-Time 3D Game Engine"
}

menu_category_office() {
    local suite_dir="$1"
    render_curated_category_menu "Office & Productivity" "${suite_dir}" \
        "freeoffice2024" "office/freeoffice2024" "Microsoft Office Compatible Suite"
}

menu_category_system() {
    local suite_dir="$1"
    render_curated_category_menu "System, Wine & Storage" "${suite_dir}" \
        "wine-staging" "system/wine-staging" "Bleeding-Edge Windows Compatibility" \
        "winetricks" "system/winetricks" "Easy Wine Prefix Config & DLL Helper" \
        "grub-btrfs" "system/grub-btrfs" "Bootable Btrfs Snapshots in GRUB" \
        "snapper" "system/snapper" "Btrfs Snapshot Manager"
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

    local tui_py="${APP_DIR:-}/slacky_tui.py"
    [ ! -f "${tui_py}" ] && [ -f "/usr/share/slacky-update/lib/slacky_tui.py" ] && tui_py="/usr/share/slacky-update/lib/slacky_tui.py"

    local curated_paths=(
        "multimedia/davinci-resolve-studio"
        "development/unreal-engine"
        "office/freeoffice2024"
        "system/wine-staging"
        "system/winetricks"
        "system/grub-btrfs"
        "system/snapper"
    )
    local curated_names=(
        "DaVinci Resolve Studio (multimedia/davinci-resolve-studio)"
        "Unreal Engine (development/unreal-engine)"
        "FreeOffice 2024 (office/freeoffice2024)"
        "Wine Staging (system/wine-staging)"
        "Winetricks (system/winetricks)"
        "GRUB-Btrfs (system/grub-btrfs)"
        "Snapper (system/snapper)"
    )

    while true; do
        local user_choice=""
        if [ -f "${tui_py}" ] && command -v python3 >/dev/null 2>&1 && [ -t 0 ]; then
            user_choice=$(python3 "${tui_py}" --mode sbo-curated)
        else
            echo ""
            echo -e "${BOLD}${CYAN}=============================================================================${RESET}"
            echo -e "${BOLD}${CYAN}                  SLACKY-SLACKBUILDS CURATED HUB${RESET}"
            echo -e "${BOLD}${CYAN}=============================================================================${RESET}"
            for ((idx=0; idx<${#curated_paths[@]}; idx++)); do
                local b_badge
                b_badge=$(get_pkg_badge "${curated_paths[idx]}")
                echo -e "  \033[1;33m$((idx+1)).\033[0m ${curated_names[idx]} ${b_badge}"
            done
            echo -e "  \033[1;33m8.\033[0m $(_ SBO_BACK_OPTION)"
            echo ""
            echo -e "  ${YELLOW}Note: 3D apps (Blender, Bambu Studio, FreeCAD, Plasticity), browsers,${RESET}"
            echo -e "  ${YELLOW}   and gaming engines are now in Underpants Gnomes for instant deployment!${RESET}"
            echo ""
            echo -n "$(_ SELECT_OPERATION_RANGE range="1-8") "
            read -r user_choice || user_choice="8"
        fi

        user_choice=$(echo "${user_choice}" | xargs)

        if [ -z "${user_choice}" ] || [ "${user_choice}" = "8" ] || [ "${user_choice}" = "Q" ] || [ "${user_choice}" = "q" ]; then
            return 0
        fi

        local valid_sel=()
        local selected_paths=()
        local selected_names=()
        for tok in ${user_choice}; do
            if [[ "${tok}" =~ ^[1-7]$ ]]; then
                local s_idx=$((tok - 1))
                valid_sel+=("${tok}")
                selected_paths+=("${curated_paths[s_idx]}")
                selected_names+=("$(basename "${curated_paths[s_idx]}")")
            fi
        done

        if [ ${#valid_sel[@]} -gt 0 ]; then
            echo ""
            echo -e "${BOLD}${CYAN}Selected SlackBuild(s) to build & install:${RESET} ${selected_names[*]}"
            local confirm=""
            read -r -p "Do you want to build and install the selected SlackBuild(s) (${selected_names[*]})? [Y/n]: " confirm
            confirm=${confirm:-Y}
            if [[ "$confirm" =~ ^[YyJjSsOo]$ ]]; then
                local failed_names=()
                for p in "${selected_paths[@]}"; do
                    install_curated_slackbuild "${p}" "${suite_dir}" || failed_names+=("$(basename "${p}")")
                done
                if [ ${#failed_names[@]} -eq 0 ]; then
                    log_success "Curated SlackBuild operation completed!"
                else
                    log_warn "Not installed: ${failed_names[*]}"
                fi
            else
                log_warn "Installation canceled by user."
            fi
            echo ""
            read -r -p "$(_ PRESS_ENTER_CONTINUE) " || true
        else
            log_warn "Invalid selection: ${user_choice}"
            echo ""
            read -r -p "$(_ PRESS_ENTER_CONTINUE) " || true
        fi
    done
}

manage_slackbuilds_interactive() {
    if ! is_sbotools_installed; then
        setup_sbotools_interactive
    fi
    auto_refresh_sbo_tree_if_stale

    local tui_py="${APP_DIR:-}/slacky_tui.py"
    [ ! -f "${tui_py}" ] && [ -f "/usr/share/slacky-update/lib/slacky_tui.py" ] && tui_py="/usr/share/slacky-update/lib/slacky_tui.py"

    while true; do
        local opt=""
        if [ -f "${tui_py}" ] && command -v python3 >/dev/null 2>&1 && [ -t 0 ]; then
            opt=$(python3 "${tui_py}" --mode sbo-main)
        else
            echo ""
            echo -e "${BOLD}Slacky-Update (SlackBuilds & Tweaks)${RESET}"
            echo -e "${BOLD}$(_ SBO_MAIN_HUB_TITLE)${RESET}"
            echo -e "  \033[1;33m1.\033[0m $(_ SBO_MENU_SEARCH_AND_RECOMMENDED)"
            echo -e "  \033[1;33m2.\033[0m $(_ SBO_MENU_CURATED_SUITE)"
            echo -e "  \033[1;33m3.\033[0m $(_ MENU_OPTIONAL_TWEAKS)"
            echo -e "  \033[1;33m4.\033[0m $(_ CATCH_YOU_FLIP_SIDE)"
            echo ""
            echo -n "$(_ SELECT_OPERATION_RANGE range="1-4") "
            read -r opt || opt="4"
        fi

        opt=$(echo "${opt}" | xargs)

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
            4|Q|q|"")
                return 0
                ;;
            *)
                log_warn "Invalid selection: ${opt}"
                ;;
        esac
    done
}
