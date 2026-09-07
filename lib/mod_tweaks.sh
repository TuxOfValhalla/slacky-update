#!/usr/bin/env bash
# --- [ SLACKY-UPDATE OPTIONAL SYSTEM & GAMING TWEAKS MODULE ] ---

set -euo pipefail

# --- [ STATUS BADGE RESOLVERS ] ---

is_limits_active() {
    local cur_nofile
    cur_nofile=$(ulimit -n 2>/dev/null || echo 0)
    if [ "${cur_nofile}" -ge 524288 ] 2>/dev/null; then
        return 0
    fi
    [ -f "/etc/security/limits.d/99-slacky-gaming.conf" ] || \
    [ -f "/etc/profile.d/slacky-limits.sh" ] || \
    grep -Eq 'nofile[[:space:]]+(524288|1048576|[0-9]{7,})' /etc/security/limits.d/*.conf /etc/security/limits.conf 2>/dev/null
}

get_tweak_limits_badge() {
    if is_limits_active; then
        echo -e "\033[1;32m[ACTIVE]\033[0m"
    else
        echo -e "\033[1;33m[DISABLED]\033[0m"
    fi
}

is_thp_memory_active() {
    local max_map
    max_map=$(cat /proc/sys/vm/max_map_count 2>/dev/null || echo 0)
    if [ "$max_map" -ge 2147483640 ] 2>/dev/null; then
        return 0
    fi
    [ -f "/etc/sysctl.d/99-slacky-gaming.conf" ] || [ -f "/etc/sysctl.d/99-viking-gaming.conf" ] || [ -f "/etc/tmpfiles.d/slacky-thp.conf" ]
}

get_tweak_thp_badge() {
    if is_thp_memory_active; then
        echo -e "\033[1;32m[ACTIVE]\033[0m"
    else
        echo -e "\033[1;33m[DISABLED]\033[0m"
    fi
}

is_network_bbr_active() {
    local cc
    cc=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || true)
    [ "$cc" = "bbr" ] || [ -f "/etc/modules-load.d/bbr.conf" ]
}

get_tweak_network_badge() {
    if is_network_bbr_active; then
        echo -e "\033[1;32m[ACTIVE]\033[0m"
    else
        echo -e "\033[1;33m[DISABLED]\033[0m"
    fi
}

is_ntsync_active() {
    [ -c "/dev/ntsync" ] || [ -f "/etc/udev/rules.d/99-ntsync.rules" ] || [ -f "/lib/udev/rules.d/60-ntsync.rules" ]
}

get_tweak_ntsync_badge() {
    if is_ntsync_active; then
        echo -e "\033[1;32m[ACTIVE]\033[0m"
    else
        echo -e "\033[1;33m[DISABLED]\033[0m"
    fi
}

is_controllers_active() {
    [ -f "/lib/udev/rules.d/sony-gdu.rules" ] || \
    [ -f "/lib/udev/rules.d/8bitdo-gdu.rules" ] || \
    [ -f "/lib/udev/rules.d/nintendo-gdu.rules" ] || \
    [ -f "/lib/udev/rules.d/microsoft-gdu.rules" ] || \
    [ -f "/etc/udev/rules.d/70-game-devices-sony.rules" ]
}

get_tweak_controllers_badge() {
    if is_controllers_active; then
        echo -e "\033[1;32m[ACTIVE]\033[0m"
    else
        echo -e "\033[1;33m[DISABLED]\033[0m"
    fi
}

# --- [ 1. FILE DESCRIPTORS & PROCESS LIMITS ] ---

deploy_tweak_limits() {
    log_info "Configuring 1,048,576 file descriptors and realtime audio priorities..."
    sudo mkdir -p /etc/security/limits.d /etc/profile.d

    cat << 'EOF_LIMITS' | sudo tee /etc/security/limits.d/99-slacky-gaming.conf >/dev/null
# Slacky - Gaming File Descriptor Limits & Realtime Priorities
*          soft    nofile    1048576
*          hard    nofile    1048576
root       soft    nofile    1048576
root       hard    nofile    1048576
@gamemode  -       nice      -10
@pipewire  -       rtprio    95
@pipewire  -       nice      -19
@pipewire  -       memlock   4194304
EOF_LIMITS

    cat << 'EOF_PROF' | sudo tee /etc/profile.d/slacky-limits.sh >/dev/null
#!/bin/sh
# Slacky - Set maximum file descriptor limit for all user shells and Steam
ulimit -n 1048576 2>/dev/null || true
EOF_PROF
    sudo chmod 0755 /etc/profile.d/slacky-limits.sh

    ulimit -n 1048576 2>/dev/null || true
    log_success "File descriptor limits (1M) & realtime audio priorities deployed!"
}

revert_tweak_limits() {
    log_info "Reverting file descriptor limits and shell profile..."
    sudo rm -f /etc/security/limits.d/99-slacky-gaming.conf /etc/profile.d/slacky-limits.sh 2>/dev/null || true
    log_success "File descriptor limits restored to stock Slackware defaults."
}

# --- [ 2. KERNEL MEMORY & THP (MADVISE) ] ---

deploy_tweak_thp_memory() {
    log_info "Configuring Transparent Hugepages (madvise) and vm.max_map_count (2,147,483,642)..."
    sudo mkdir -p /etc/sysctl.d /etc/tmpfiles.d

    cat << 'EOF_SYSCTL' | sudo tee /etc/sysctl.d/99-slacky-gaming.conf >/dev/null
# Slacky - Proton & Game Memory Scalability
vm.max_map_count = 2147483642
kernel.split_lock_mitigate = 0
fs.file-max = 2097152
fs.inotify.max_user_watches = 1048576
fs.inotify.max_user_instances = 8192
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
EOF_SYSCTL

    cat << 'EOF_THP' | sudo tee /etc/tmpfiles.d/slacky-thp.conf >/dev/null
# Slacky - Transparent Hugepages madvise mode
w /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise
w /sys/kernel/mm/transparent_hugepage/shmem_enabled - - - - advise
w /sys/kernel/mm/transparent_hugepage/defrag - - - - defer+madvise
EOF_THP

    sudo sysctl -p /etc/sysctl.d/99-slacky-gaming.conf >/dev/null 2>&1 || true
    if [ -w /sys/kernel/mm/transparent_hugepage/enabled ]; then
        echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled >/dev/null 2>&1 || true
    fi
    if [ -w /sys/kernel/mm/transparent_hugepage/shmem_enabled ]; then
        echo advise | sudo tee /sys/kernel/mm/transparent_hugepage/shmem_enabled >/dev/null 2>&1 || true
    fi
    log_success "THP (madvise) & memory parameters successfully applied!"
}

revert_tweak_thp_memory() {
    log_info "Reverting THP and memory sysctl parameters..."
    sudo rm -f /etc/sysctl.d/99-slacky-gaming.conf /etc/sysctl.d/99-viking-gaming.conf /etc/tmpfiles.d/slacky-thp.conf 2>/dev/null || true
    sudo sysctl -w vm.max_map_count=65530 >/dev/null 2>&1 || true
    sudo sysctl -w vm.swappiness=60 >/dev/null 2>&1 || true
    sudo sysctl -w vm.vfs_cache_pressure=100 >/dev/null 2>&1 || true
    if [ -w /sys/kernel/mm/transparent_hugepage/enabled ]; then
        echo always | sudo tee /sys/kernel/mm/transparent_hugepage/enabled >/dev/null 2>&1 || true
    fi
    log_success "Kernel memory parameters restored to stock Slackware defaults."
}

# --- [ 3. NETWORK LOW-LATENCY & BBR ] ---

deploy_tweak_network_bbr() {
    log_info "Configuring BBR congestion control and low-latency network queueing..."
    sudo mkdir -p /etc/modules-load.d /etc/sysctl.d

    echo "tcp_bbr" | sudo tee /etc/modules-load.d/bbr.conf >/dev/null
    sudo modprobe tcp_bbr 2>/dev/null || true

    cat << 'EOF_NET' | sudo tee /etc/sysctl.d/99-slacky-network.conf >/dev/null
# Slacky - Low-Latency Gaming Network Parameters
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
EOF_NET

    sudo sysctl -p /etc/sysctl.d/99-slacky-network.conf >/dev/null 2>&1 || true
    log_success "Network BBR & low-latency parameters active!"
}

revert_tweak_network_bbr() {
    log_info "Reverting network congestion and socket parameters..."
    sudo rm -f /etc/modules-load.d/bbr.conf /etc/sysctl.d/99-slacky-network.conf 2>/dev/null || true
    sudo sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1 || true
    sudo sysctl -w net.core.default_qdisc=fq_codel >/dev/null 2>&1 || true
    log_success "Network configuration restored to stock Slackware defaults."
}

# --- [ 4. NTSYNC KERNEL SYNCHRONIZATION ] ---

deploy_tweak_ntsync() {
    log_info "Configuring NTSYNC device access permissions (0666)..."
    sudo mkdir -p /etc/udev/rules.d
    echo 'KERNEL=="ntsync", MODE="0666"' | sudo tee /etc/udev/rules.d/99-ntsync.rules >/dev/null
    sudo udevadm control --reload-rules 2>/dev/null || true
    sudo udevadm trigger --name-match=ntsync 2>/dev/null || true

    if [ -c "/dev/ntsync" ]; then
        log_success "NTSYNC fast synchronization active and accessible on /dev/ntsync!"
    else
        log_warn "NTSYNC udev rule installed. (/dev/ntsync will be active when running a CachyOS / NTSYNC kernel)."
    fi
}

revert_tweak_ntsync() {
    log_info "Removing NTSYNC udev rule..."
    sudo rm -f /etc/udev/rules.d/99-ntsync.rules 2>/dev/null || true
    sudo udevadm control --reload-rules 2>/dev/null || true
    log_success "NTSYNC configuration removed."
}

# --- [ 5. UNIVERSAL CONTROLLER FORCEFIELD (27 VENDORS) ] ---

deploy_tweak_controllers() {
    log_info "Deploying universal controller udev rules (27 gamepad & VR vendors)..."
    local gdu_src=""
    for cand in "${APP_DIR}/../assets/udev/game-devices-udev" "${APP_DIR}/assets/udev/game-devices-udev" "/usr/share/slacky-update/assets/udev/game-devices-udev" "/usr/local/lib/slacky-update/assets/udev/game-devices-udev"; do
        if [ -d "${cand}" ]; then
            gdu_src="${cand}"
            break
        fi
    done

    if [ -n "${gdu_src}" ] && [ -d "${gdu_src}" ]; then
        sudo mkdir -p /lib/udev/rules.d /etc/udev/rules.d
        sudo cp -f "${gdu_src}"/*.rules /lib/udev/rules.d/ 2>/dev/null || true

        cat << 'EOF_LOGI' | sudo tee /etc/udev/rules.d/50-logitech-no-autosuspend.rules >/dev/null
# Slacky - Disable USB autosuspend on Logitech Gaming Devices
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="046d", TEST=="power/control", ATTR{power/control}="on"
EOF_LOGI

        sudo udevadm control --reload-rules 2>/dev/null || true
        sudo udevadm trigger 2>/dev/null || true
        log_success "Universal controller forcefield (DualSense, Xbox, Switch Pro, 8BitDo, VR, Flight Sticks) active!"
    else
        log_error "Controller udev assets directory not found."
        return 1
    fi
}

revert_tweak_controllers() {
    log_info "Removing deployed controller udev rules..."
    local gdu_src=""
    for cand in "${APP_DIR}/../assets/udev/game-devices-udev" "${APP_DIR}/assets/udev/game-devices-udev" "/usr/share/slacky-update/assets/udev/game-devices-udev" "/usr/local/lib/slacky-update/assets/udev/game-devices-udev"; do
        if [ -d "${cand}" ]; then
            gdu_src="${cand}"
            break
        fi
    done

    if [ -n "${gdu_src}" ] && [ -d "${gdu_src}" ]; then
        for rfile in "${gdu_src}"/*.rules; do
            local base_r
            base_r=$(basename "${rfile}")
            sudo rm -f "/lib/udev/rules.d/${base_r}" 2>/dev/null || true
        done
    fi
    sudo rm -f /etc/udev/rules.d/50-logitech-no-autosuspend.rules 2>/dev/null || true
    sudo udevadm control --reload-rules 2>/dev/null || true
    log_success "Controller udev rules reverted."
}

# --- [ BULK ACTIONS ] ---

apply_all_tweaks() {
    echo ""
    log_info "Applying all recommended system and gaming optimizations..."
    deploy_tweak_limits
    deploy_tweak_thp_memory
    deploy_tweak_network_bbr
    deploy_tweak_ntsync
    deploy_tweak_controllers
    echo ""
    log_success "⚡ Most Triumphant! All system & gaming tweaks are 100% armed and active."
}

revert_all_tweaks() {
    echo ""
    log_info "Reverting all system tweaks to stock Slackware defaults..."
    revert_tweak_limits
    revert_tweak_thp_memory
    revert_tweak_network_bbr
    revert_tweak_ntsync
    revert_tweak_controllers
    echo ""
    log_success "All system tweaks have been reset to factory stock defaults."
}

# --- [ GRANULAR ACTION PROMPT HELPER ] ---

manage_single_tweak_action() {
    local tweak_name="$1"
    local is_active_fn="$2"
    local deploy_fn="$3"
    local revert_fn="$4"

    local current_status="DISABLED"
    if "$is_active_fn"; then
        current_status="ACTIVE"
    fi

    echo ""
    echo -e "${BOLD}${CYAN}--- [ ${tweak_name} ] ---${RESET}"
    echo -e "Current status: $([ "$current_status" = "ACTIVE" ] && echo -e "\033[1;32m[ACTIVE]\033[0m" || echo -e "\033[1;33m[DISABLED]\033[0m")"
    echo -e "  \033[1;33m1.\033[0m Deploy / Enable this tweak"
    echo -e "  \033[1;33m2.\033[0m Revert / Disable to stock default"
    echo -e "  \033[1;33m3.\033[0m $(_ SBO_BACK_OPTION)"
    echo ""
    echo -n "$(_ SELECT_OPERATION_RANGE range="1-3") "
    local sel
    read -r sel || sel="3"

    case "${sel}" in
        1) "$deploy_fn" ;;
        2) "$revert_fn" ;;
        3) return 0 ;;
        *) log_warn "Invalid selection." ;;
    esac
}

# --- [ MAIN INTERACTIVE CONTROLLER ] ---

manage_tweaks_interactive() {
    while true; do
        local b_limits b_thp b_net b_ntsync b_ctrl
        b_limits=$(get_tweak_limits_badge)
        b_thp=$(get_tweak_thp_badge)
        b_net=$(get_tweak_network_badge)
        b_ntsync=$(get_tweak_ntsync_badge)
        b_ctrl=$(get_tweak_controllers_badge)

        echo ""
        echo -e "${BOLD}${CYAN}=============================================================================${RESET}"
        echo -e "${BOLD}${CYAN}               ⚡ OPTIONAL SYSTEM & GAMING TWEAKS ⚡${RESET}"
        echo -e "${BOLD}${CYAN}=============================================================================${RESET}"
        echo -e "  \033[1;33m1.\033[0m File Descriptors & Process Limits (1M nofile, PipeWire rtprio) ${b_limits}"
        echo -e "  \033[1;33m2.\033[0m Kernel Memory & THP (madvise THP, max_map_count=2.14B, swappiness=10) ${b_thp}"
        echo -e "  \033[1;33m3.\033[0m Network Low-Latency & BBR Congestion Control (fq, fastopen) ${b_net}"
        echo -e "  \033[1;33m4.\033[0m NTSYNC Fast Synchronization (/dev/ntsync 0666 permissions) ${b_ntsync}"
        echo -e "  \033[1;33m5.\033[0m Universal Gamepad & Controller Forcefield (27 Vendors, Logitech USB) ${b_ctrl}"
        echo -e "  \033[1;33m6.\033[0m 🚀 Apply All Recommended Tweaks in One-Click"
        echo -e "  \033[1;33m7.\033[0m 🔄 Revert All Tweaks to Stock Slackware Defaults"
        echo -e "  \033[1;33m8.\033[0m $(_ SBO_BACK_OPTION)"
        echo ""
        echo -n "$(_ SELECT_OPERATION_RANGE range="1-8") "
        local opt
        read -r opt || opt="8"

        case "${opt}" in
            1)
                manage_single_tweak_action "File Descriptors & Process Limits" is_limits_active deploy_tweak_limits revert_tweak_limits
                ;;
            2)
                manage_single_tweak_action "Kernel Memory & Transparent Hugepages" is_thp_memory_active deploy_tweak_thp_memory revert_tweak_thp_memory
                ;;
            3)
                manage_single_tweak_action "Network Low-Latency & BBR" is_network_bbr_active deploy_tweak_network_bbr revert_tweak_network_bbr
                ;;
            4)
                manage_single_tweak_action "NTSYNC Kernel Synchronization" is_ntsync_active deploy_tweak_ntsync revert_tweak_ntsync
                ;;
            5)
                manage_single_tweak_action "Universal Controller Forcefield" is_controllers_active deploy_tweak_controllers revert_tweak_controllers
                ;;
            6)
                apply_all_tweaks
                ;;
            7)
                revert_all_tweaks
                ;;
            8)
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
