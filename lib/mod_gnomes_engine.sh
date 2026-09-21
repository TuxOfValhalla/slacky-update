#!/usr/bin/env bash
# --- [ SLACKY-UPDATE UNDERPANTS GNOMES ENGINE BRIDGE MODULE ] ---
# Engineered for Slackware Linux (-current / 15.0+)
# Provides shell integration for standalone Pacman repository synchronization,
# in-memory metadata queries, and Dependency DAG resolution.

set -euo pipefail

GNOMES_CACHE_DIR="/var/cache/slacky-update/gnomes"
GNOMES_USER_CACHE="${HOME:-/root}/.cache/slacky-update/gnomes"

GNOMES_PY=""
if [ -f "${APP_DIR:-}/gnomes_pacman.py" ]; then
    GNOMES_PY="${APP_DIR:-}/gnomes_pacman.py"
elif [ -f "${SCRIPT_DIR:-}/../lib/gnomes_pacman.py" ]; then
    GNOMES_PY="${SCRIPT_DIR:-}/../lib/gnomes_pacman.py"
elif [ -f "/usr/share/slacky-update/lib/gnomes_pacman.py" ]; then
    GNOMES_PY="/usr/share/slacky-update/lib/gnomes_pacman.py"
elif [ -f "/usr/local/lib/slacky-update/gnomes_pacman.py" ]; then
    GNOMES_PY="/usr/local/lib/slacky-update/gnomes_pacman.py"
fi

gnomes_init() {
    if ! command -v python3 >/dev/null 2>&1; then
        echo -e "${RED}Error: python3 is required for Underpants Gnomes Pacman Engine.${RESET}"
        return 1
    fi

    if [ -z "${GNOMES_PY}" ] || [ ! -f "${GNOMES_PY}" ]; then
        echo -e "${RED}Error: gnomes_pacman.py backend script not found.${RESET}"
        return 1
    fi

    # Ensure writable cache directory
    if [ -w "/var/cache" ] 2>/dev/null; then
        mkdir -p "${GNOMES_CACHE_DIR}/db" "${GNOMES_CACHE_DIR}/pkg" 2>/dev/null || true
    else
        mkdir -p "${GNOMES_USER_CACHE}/db" "${GNOMES_USER_CACHE}/pkg" 2>/dev/null || true
    fi
}

gnomes_ensure_db() {
    gnomes_init || return 1
    local has_db=false

    for cdir in "${GNOMES_CACHE_DIR}/db" "${GNOMES_USER_CACHE}/db" "/tmp/slacky-update-gnomes/db"; do
        if [ -d "${cdir}" ] && ls "${cdir}"/*.db.tar.* >/dev/null 2>&1; then
            has_db=true
            break
        fi
    done

    if [ "${has_db}" = false ]; then
        echo -e "${CYAN}:: Underpants Gnomes repository database cache is empty.${RESET}"
        echo -e "${CYAN}:: Initializing sync from upstream mirrors...${RESET}"
        gnomes_sync_db
    fi
}

gnomes_sync_db() {
    gnomes_init || return 1
    local force_flag=""
    if [ "${1:-}" = "--force" ] || [ "${1:-}" = "-f" ]; then
        force_flag="--force"
    fi

    echo -e "${BOLD}${CYAN}:: [Underpants Gnomes] Synchronizing Pacman Repositories...${RESET}"
    if python3 "${GNOMES_PY}" sync ${force_flag}; then
        echo -e "${GREEN}✓ Pacman sync databases updated successfully.${RESET}"
        return 0
    else
        echo -e "${RED}✗ Failed to synchronize one or more Pacman databases.${RESET}"
        return 1
    fi
}

gnomes_search_pkg() {
    gnomes_init || return 1
    gnomes_ensure_db
    python3 "${GNOMES_PY}" search "$@"
}

gnomes_get_pkg_info() {
    gnomes_init || return 1
    gnomes_ensure_db
    python3 "${GNOMES_PY}" info "$@"
}

gnomes_resolve_deps() {
    gnomes_init || return 1
    gnomes_ensure_db
    python3 "${GNOMES_PY}" deps "$@"
}

gnomes_get_download_url() {
    gnomes_init || return 1
    gnomes_ensure_db
    python3 "${GNOMES_PY}" url "$@"
}

gnomes_check_host() {
    gnomes_init || return 1
    python3 "${GNOMES_PY}" check-host "$@"
}

gnomes_list_installed() {
    gnomes_init || return 1
    python3 "${GNOMES_PY}" list-installed "$@"
}

gnomes_transmute_pkg() {
    gnomes_init || return 1
    gnomes_ensure_db
    python3 "${GNOMES_PY}" transmute "$@"
}

gnomes_interactive_station() {
    gnomes_init || return 1
    gnomes_ensure_db

    while true; do
        echo ""
        echo -e "${BLUE}${BOLD}================================================================================${RESET}"
        echo -e " ${BOLD}${MAGENTA}🧙 UNDERPANTS GNOMES PACMAN FACTORY & TRANSMUTATION MATRIX (SLACKWARE)${RESET}"
        echo -e "${BLUE}================================================================================${RESET}"
        echo -e "  ${CYAN}Step 1: Steal Underpants  ➔  Step 2: Relocate ELF & DAG  ➔  ${GREEN}${BOLD}Step 3: 💰 PROFIT!${RESET}"
        echo ""
        echo -e "  ${BOLD}1.${RESET} 🔍 Search Upstream Repositories (CachyOS / Arch / Multilib)"
        echo -e "  ${BOLD}2.${RESET} 📦 Inspect Package Details & Upstream Metadata (-Si)"
        echo -e "  ${BOLD}3.${RESET} 🧬 Resolve Dependency Graph & Host Sovereignty Shield (-Sd)"
        echo -e "  ${BOLD}4.${RESET} ⚡ Transmute & Install Upstream Package (-S)"
        echo -e "  ${BOLD}5.${RESET} 🔄 Synchronize Pacman Sync Databases (-Sy)"
        echo -e "  ${BOLD}6.${RESET} 📋 List Transmuted Packages in /var/log/packages/ (-Q)"
        echo -e "  ${BOLD}7.${RESET} 🛡️ Verify Host System Sovereignty & glibc Compatibility"
        echo -e "  ${BOLD}Q.${RESET} 🚪 Catch You on the Flip Side (Return)"
        echo ""
        read -r -p "Enter choice [1-7, Q]: " g_choice
        g_choice=$(echo "${g_choice}" | tr '[:lower:]' '[:upper:]' | xargs)

        case "${g_choice}" in
            1)
                echo ""
                read -r -p "Enter package search term: " s_term
                s_term=$(echo "${s_term}" | xargs)
                if [ -n "${s_term}" ]; then
                    echo ""
                    gnomes_search_pkg "${s_term}"
                fi
                echo ""
                read -r -p "Press Enter to continue..."
                ;;
            2)
                echo ""
                read -r -p "Enter package name to inspect: " p_info
                p_info=$(echo "${p_info}" | xargs)
                if [ -n "${p_info}" ]; then
                    echo ""
                    gnomes_get_pkg_info "${p_info}"
                fi
                echo ""
                read -r -p "Press Enter to continue..."
                ;;
            3)
                echo ""
                read -r -p "Enter package name(s) for dependency resolution: " p_deps
                p_deps=$(echo "${p_deps}" | xargs)
                if [ -n "${p_deps}" ]; then
                    echo ""
                    # shellcheck disable=SC2086
                    gnomes_resolve_deps ${p_deps}
                fi
                echo ""
                read -r -p "Press Enter to continue..."
                ;;
            4)
                echo ""
                read -r -p "Enter package name(s) to transmute: " p_trans
                p_trans=$(echo "${p_trans}" | xargs)
                if [ -n "${p_trans}" ]; then
                    echo ""
                    # shellcheck disable=SC2086
                    gnomes_transmute_pkg ${p_trans}
                fi
                echo ""
                read -r -p "Press Enter to continue..."
                ;;
            5)
                echo ""
                gnomes_sync_db --force
                echo ""
                read -r -p "Press Enter to continue..."
                ;;
            6)
                echo ""
                gnomes_list_installed
                echo ""
                read -r -p "Press Enter to continue..."
                ;;
            7)
                echo ""
                gnomes_check_host
                echo ""
                read -r -p "Press Enter to continue..."
                ;;
            Q|"")
                break
                ;;
            *)
                echo -e "${RED}Invalid choice: ${g_choice}${RESET}"
                ;;
        esac
    done
}
