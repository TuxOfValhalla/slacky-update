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
    [ -f "/etc/udev/rules.d/sony-gdu.rules" ] || \
    [ -f "/etc/udev/rules.d/8bitdo-gdu.rules" ] || \
    [ -f "/etc/udev/rules.d/50-logitech-no-autosuspend.rules" ] || \
    [ -f "/lib/udev/rules.d/sony-gdu.rules" ] || \
    [ -f "/etc/udev/rules.d/70-game-devices-sony.rules" ]
}

get_tweak_controllers_badge() {
    if is_controllers_active; then
        echo -e "\033[1;32m[ACTIVE]\033[0m"
    else
        echo -e "\033[1;33m[DISABLED]\033[0m"
    fi
}

# 6A-142: an NFS server is "configured" when /etc/exports has at least one non-comment line
_slacky_nfs_exports_configured() {
    [ -f /etc/exports ] && grep -q -E '^[[:space:]]*[^#[:space:]]' /etc/exports 2>/dev/null
}

# 6A-142: rc.6 edits. Old builds cut the waits to 0.5 s / 0.1 s; now the waits never go below 2 s and the
# "sleep 3" sync wait is left alone. The dhcpcd wait ("sleep 2" without /bin) is never touched.
_slacky_rc6_fwd_old() { sed -e 's|/bin/sleep 5|/bin/sleep 0.5|g' -e 's|/bin/sleep 3|/bin/sleep 0.1|g'; }
_slacky_rc6_fwd_new() { sed -e 's|/bin/sleep 5|/bin/sleep 2|g'; }

# Prints: nobackup | stock (rc.6 equals the backup) | old (our old 0.5 s edit) | new (our 2 s edit) | foreign
_slacky_rc6_state() {
    local rc6="/etc/rc.d/rc.6" orig="/etc/rc.d/rc.6.slacky_orig"
    if [ ! -f "${orig}" ]; then echo "nobackup"; return 0; fi
    if [ ! -f "${rc6}" ]; then echo "foreign"; return 0; fi
    if cmp -s "${rc6}" "${orig}"; then echo "stock"; return 0; fi
    if _slacky_rc6_fwd_new < "${orig}" | cmp -s - "${rc6}"; then echo "new"; return 0; fi
    if _slacky_rc6_fwd_old < "${orig}" | cmp -s - "${rc6}"; then echo "old"; return 0; fi
    echo "foreign"
}

is_fastboot_active() {
    [ ! -x "/etc/rc.d/rc.pcmcia" ] && \
    { [ ! -x "/etc/rc.d/rc.nfsd" ] || _slacky_nfs_exports_configured; } && \
    [ ! -x "/etc/rc.d/rc.inet1" ] && \
    [ -f "/etc/rc.d/rc.6" ] && \
    [ "$(_slacky_rc6_state)" = "new" ]
}

get_tweak_fastboot_badge() {
    if is_fastboot_active; then
        echo -e "\033[1;32m[ACTIVE]\033[0m"
    else
        echo -e "\033[1;33m[DISABLED]\033[0m"
    fi
}

is_iosched_active() {
    if [ -f "/etc/udev/rules.d/60-slacky-ioschedulers.rules" ] || [ -f "/etc/udev/rules.d/60-ioschedulers.rules" ]; then
        return 0
    fi
    for p in /sys/block/nvme*n1/queue/scheduler; do
        if [ -f "$p" ] && grep -q "\[none\]" "$p" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

get_tweak_iosched_badge() {
    if is_iosched_active; then
        echo -e "\033[1;32m[ACTIVE]\033[0m"
    else
        echo -e "\033[1;33m[DISABLED]\033[0m"
    fi
}

is_shadercache_active() {
    for f in "/etc/profile.d/slacky-shader-cache.sh" "/etc/profile.d/slacky-gaming-env.sh"; do
        if [ -f "$f" ] && grep -q "__GL_SHADER_DISK_CACHE_SIZE" "$f" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

get_tweak_shadercache_badge() {
    if is_shadercache_active; then
        echo -e "\033[1;32m[ACTIVE]\033[0m"
    else
        echo -e "\033[1;33m[DISABLED]\033[0m"
    fi
}

is_pwlatency_active() {
    [ -f "/etc/pipewire/pipewire.conf.d/99-slacky-lowlatency.conf" ] || \
    [ -f "/etc/pipewire/pipewire-pulse.conf.d/99-slacky-lowlatency.conf" ]
}

get_tweak_pwlatency_badge() {
    if is_pwlatency_active; then
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

# --- [ 2. KERNEL MEMORY & THP (MADVISE + DEFER) ] ---

deploy_tweak_thp_memory() {
    log_info "Configuring Transparent Hugepages (madvise + defer) and memory scalability..."
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
vm.dirty_background_bytes = 134217728
vm.dirty_bytes = 268435456
EOF_SYSCTL

    cat << 'EOF_THP' | sudo tee /etc/tmpfiles.d/slacky-thp.conf >/dev/null
# Slacky - Transparent Hugepages (madvise + defer meta)
w /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise
w /sys/kernel/mm/transparent_hugepage/shmem_enabled - - - - advise
w /sys/kernel/mm/transparent_hugepage/defrag - - - - defer
w /sys/kernel/mm/transparent_hugepage/khugepaged/defrag - - - - 1
EOF_THP

    sudo sysctl -p /etc/sysctl.d/99-slacky-gaming.conf >/dev/null 2>&1 || true
    if [ -w /sys/kernel/mm/transparent_hugepage/enabled ]; then
        echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled >/dev/null 2>&1 || true
    fi
    if [ -w /sys/kernel/mm/transparent_hugepage/defrag ]; then
        echo defer | sudo tee /sys/kernel/mm/transparent_hugepage/defrag >/dev/null 2>&1 || true
    fi
    if [ -w /sys/kernel/mm/transparent_hugepage/shmem_enabled ]; then
        echo advise | sudo tee /sys/kernel/mm/transparent_hugepage/shmem_enabled >/dev/null 2>&1 || true
    fi
    if [ -w /sys/kernel/mm/transparent_hugepage/khugepaged/defrag ]; then
        echo 1 | sudo tee /sys/kernel/mm/transparent_hugepage/khugepaged/defrag >/dev/null 2>&1 || true
    fi
    log_success "THP (madvise + defer) & dirty byte memory limits successfully applied!"
}

revert_tweak_thp_memory() {
    log_info "Reverting THP and memory sysctl parameters..."
    sudo rm -f /etc/sysctl.d/99-slacky-gaming.conf /etc/sysctl.d/99-viking-gaming.conf /etc/tmpfiles.d/slacky-thp.conf 2>/dev/null || true
    sudo sysctl -w vm.max_map_count=65530 >/dev/null 2>&1 || true
    sudo sysctl -w vm.swappiness=60 >/dev/null 2>&1 || true
    sudo sysctl -w vm.vfs_cache_pressure=100 >/dev/null 2>&1 || true
    sudo sysctl -w vm.dirty_ratio=20 >/dev/null 2>&1 || true
    sudo sysctl -w vm.dirty_background_ratio=10 >/dev/null 2>&1 || true
    if [ -w /sys/kernel/mm/transparent_hugepage/enabled ]; then
        echo always | sudo tee /sys/kernel/mm/transparent_hugepage/enabled >/dev/null 2>&1 || true
    fi
    if [ -w /sys/kernel/mm/transparent_hugepage/defrag ]; then
        echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/defrag >/dev/null 2>&1 || true
    fi
    log_success "Kernel memory parameters restored to stock Slackware defaults."
}

# --- [ 3. NETWORK LOW-LATENCY & BBR ] ---

deploy_tweak_network_bbr() {
    log_info "Configuring BBR congestion control and low-latency network queueing..."
    sudo mkdir -p /etc/modules-load.d /etc/sysctl.d

    echo "tcp_bbr" | sudo tee /etc/modules-load.d/bbr.conf >/dev/null
    sudo modprobe tcp_bbr 2>/dev/null || true

    # Ensure Slackware SysVinit loads the module across reboots
    if [ ! -f /etc/rc.d/rc.modules.local ]; then
        echo -e "#!/bin/sh\n# /etc/rc.d/rc.modules.local - Local module initialization script" | sudo tee /etc/rc.d/rc.modules.local >/dev/null
    fi
    if ! grep -q 'modprobe tcp_bbr' /etc/rc.d/rc.modules.local 2>/dev/null; then
        echo -e "\n# Slacky - Low-Latency TCP BBR Congestion Control\n/sbin/modprobe tcp_bbr" | sudo tee -a /etc/rc.d/rc.modules.local >/dev/null
    fi
    sudo chmod +x /etc/rc.d/rc.modules.local 2>/dev/null || true

    cat << 'EOF_NET' | sudo tee /etc/sysctl.d/99-slacky-network.conf >/dev/null
# Slacky - Low-Latency Gaming Network Parameters
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
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
    if [ -f /etc/rc.d/rc.modules.local ]; then
        sudo sed -i '/# Slacky - Low-Latency TCP BBR/d' /etc/rc.d/rc.modules.local 2>/dev/null || true
        sudo sed -i '/\/sbin\/modprobe tcp_bbr/d' /etc/rc.d/rc.modules.local 2>/dev/null || true
    fi
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
        sudo mkdir -p /etc/udev/rules.d
        sudo cp -f "${gdu_src}"/*.rules /etc/udev/rules.d/ 2>/dev/null || true

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
            local base_r rdir
            base_r=$(basename "${rfile}")
            for rdir in etc/udev/rules.d lib/udev/rules.d; do
                [ -e "/${rdir}/${base_r}" ] || continue
                # 6A-142: never delete a rules file that an installed package owns
                if grep -l -x -F "${rdir}/${base_r}" /var/log/packages/* >/dev/null 2>&1; then
                    log_info "Kept /${rdir}/${base_r} because an installed package owns it."
                    continue
                fi
                sudo rm -f "/${rdir}/${base_r}" 2>/dev/null || true
            done
        done
    fi
    sudo rm -f /etc/udev/rules.d/50-logitech-no-autosuspend.rules 2>/dev/null || true
    sudo udevadm control --reload-rules 2>/dev/null || true
    log_success "Controller udev rules reverted."
}

# --- [ 6. TURBO BOOT & FAST SHUTDOWN DELAYS ] ---

deploy_tweak_fastboot() {
    log_info "Configuring Turbo Boot & Fast Shutdown optimizations (Phase 1 & 2)..."

    # 1. Disable obsolete PCMCIA (saves 5s on boot, 5s on shutdown)
    if [ -f /etc/rc.d/rc.pcmcia ] && [ -x /etc/rc.d/rc.pcmcia ]; then
        log_info "Disabling legacy 16-bit PCMCIA service (/etc/rc.d/rc.pcmcia)..."
        sudo touch /etc/rc.d/.slacky_pcmcia_was_exec 2>/dev/null || true
        sudo chmod -x /etc/rc.d/rc.pcmcia
    fi

    # 2. Disable NFSD only when no NFS export is configured (saves 10s boot-freeze)
    # 6A-142: was unconditional; an NFS server with entries in /etc/exports keeps running
    if [ -f /etc/rc.d/rc.nfsd ] && [ -x /etc/rc.d/rc.nfsd ] && _slacky_nfs_exports_configured; then
        log_info "The NFS server stays on because /etc/exports shares folders."
    elif [ -f /etc/rc.d/rc.nfsd ] && [ -x /etc/rc.d/rc.nfsd ]; then
        log_info "Disabling unneeded NFS server daemon (/etc/rc.d/rc.nfsd)..."
        sudo touch /etc/rc.d/.slacky_nfsd_was_exec 2>/dev/null || true
        sudo chmod -x /etc/rc.d/rc.nfsd
    fi

    # 3. NetworkManager sovereignty: Disable rc.inet1 to eliminate duplicate probing & unplugged DHCP hang
    if [ -f /etc/rc.d/rc.networkmanager ] && [ -x /etc/rc.d/rc.networkmanager ]; then
        if [ -f /etc/rc.d/rc.inet1 ] && [ -x /etc/rc.d/rc.inet1 ]; then
            log_info "Optimizing network startup: handing full control to NetworkManager (disabling rc.inet1)..."
            sudo touch /etc/rc.d/.slacky_inet1_was_exec 2>/dev/null || true
            sudo chmod -x /etc/rc.d/rc.inet1
        fi
    fi

    # 4. Clean misplaced user-session daemons from root rc.local and rc.local_shutdown
    local session_svcs=("wireplumber" "pipewire-pulse" "xdg-desktop-portal" "xdg-document-portal" "xdg-permission-store" "org.freedesktop.impl.portal.desktop.cosmic")
    for svc in "${session_svcs[@]}"; do
        if [ -f "/etc/rc.d/rc.${svc}" ]; then
            sudo chmod -x "/etc/rc.d/rc.${svc}" 2>/dev/null || true
        fi
        for rcf in /etc/rc.d/rc.local /etc/rc.d/rc.local_shutdown; do
            # 6A-142: delete the block only when BOTH markers exist (a missing end marker would delete to end of file)
            if [ -f "$rcf" ] && grep -q "# --- \[ gnomes-service: ${svc} \] ---" "$rcf" 2>/dev/null \
                && grep -q "# --- \[ /gnomes-service: ${svc} \] ---" "$rcf" 2>/dev/null; then
                sudo sed -i "/# --- \\[ gnomes-service: ${svc} \\] ---/,/# --- \\[ \\/gnomes-service: ${svc} \\] ---/d" "$rcf" 2>/dev/null || true
            fi
        done
    done

    # 5. Accelerate rc.6 shutdown (saves ~6s on reboot/shutdown)
    # 6A-142: waits never below 2 s (programs get time to save their data); the disk sync wait is not touched
    if [ -f /etc/rc.d/rc.6 ]; then
        local rc6_state
        rc6_state=$(_slacky_rc6_state)
        case "${rc6_state}" in
            nobackup)
                log_info "Backing up stock /etc/rc.d/rc.6 to /etc/rc.d/rc.6.slacky_orig..."
                sudo cp -a /etc/rc.d/rc.6 /etc/rc.d/rc.6.slacky_orig
                rc6_state="stock"
                ;;
            old)
                # Undo the too-short waits of older builds before applying the safe values
                log_info "Restoring safe shutdown waits from the old fast-shutdown setting..."
                sudo cp -a /etc/rc.d/rc.6.slacky_orig /etc/rc.d/rc.6
                rc6_state="stock"
                ;;
        esac
        if [ "${rc6_state}" = "stock" ]; then
            log_info "Shortening the shutdown waits from 5 to 2 seconds..."
            sudo sed -i 's|/bin/sleep 5|/bin/sleep 2|g' /etc/rc.d/rc.6
        elif [ "${rc6_state}" = "foreign" ]; then
            log_warn "Your shutdown script was changed by a Slackware update, so the shutdown speed-up was skipped."
        fi
    fi

    # 6. Mount /tmp in RAM (tmpfs) to eliminate rc.S disk cleanup pause & SSD wear
    if [ -f /etc/fstab ] && ! grep -E -q '^[[:space:]]*tmpfs[[:space:]]+/tmp[[:space:]]+tmpfs' /etc/fstab; then
        log_info "Configuring /tmp on tmpfs in RAM (/etc/fstab)..."
        echo "tmpfs                                      /tmp         tmpfs  defaults,rw,nosuid,nodev,relatime,size=50%,mode=1777     0  0" | sudo tee -a /etc/fstab >/dev/null
        # 6A-142: never mount over the live /tmp (running programs keep sockets and files there)
        log_info "/tmp will be kept in memory after the next reboot."
    fi

    # 7. Configure universal Dracut multi-threaded zstd -1 compression for all kernel flavors
    if [ -d /etc/dracut.conf.d ]; then
        log_info "Configuring universal high-speed initramfs compression (/etc/dracut.conf.d/99-fast-boot-compression.conf)..."
        cat << 'EOF_DRACUT' | sudo tee /etc/dracut.conf.d/99-fast-boot-compression.conf >/dev/null
# Generated by slacky-update Turbo Boot
compress="zstd -1 -T0"
EOF_DRACUT
    fi

    log_success "Turbo Boot & Fast Shutdown active."
}

revert_tweak_fastboot() {
    log_info "Reverting Turbo Boot & Fast Shutdown to stock Slackware defaults..."
    if [ -f /etc/rc.d/.slacky_pcmcia_was_exec ]; then
        if [ -f /etc/rc.d/rc.pcmcia ]; then
            sudo chmod +x /etc/rc.d/rc.pcmcia
        fi
        sudo rm -f /etc/rc.d/.slacky_pcmcia_was_exec 2>/dev/null || true
    fi
    if [ -f /etc/rc.d/.slacky_nfsd_was_exec ]; then
        if [ -f /etc/rc.d/rc.nfsd ]; then
            sudo chmod +x /etc/rc.d/rc.nfsd
        fi
        sudo rm -f /etc/rc.d/.slacky_nfsd_was_exec 2>/dev/null || true
    fi
    if [ -f /etc/rc.d/.slacky_inet1_was_exec ]; then
        if [ -f /etc/rc.d/rc.inet1 ]; then
            sudo chmod +x /etc/rc.d/rc.inet1
        fi
        sudo rm -f /etc/rc.d/.slacky_inet1_was_exec 2>/dev/null || true
    fi
    if [ -f /etc/rc.d/rc.6.slacky_orig ]; then
        # 6A-142: only restore the backup when rc.6 still holds our edit; never copy an old backup over a newer
        # rc.6 from a Slackware update
        case "$(_slacky_rc6_state)" in
            new|old|stock)
                sudo cp -a /etc/rc.d/rc.6.slacky_orig /etc/rc.d/rc.6
                sudo rm -f /etc/rc.d/rc.6.slacky_orig
                ;;
            *)
                log_warn "Your shutdown script is newer than the saved copy, so it was left as it is (old copy: /etc/rc.d/rc.6.slacky_orig)."
                ;;
        esac
    fi
    if [ -f /etc/fstab ] && grep -E -q '^[[:space:]]*tmpfs[[:space:]]+/tmp[[:space:]]+tmpfs' /etc/fstab; then
        log_info "Removing /tmp tmpfs mount from /etc/fstab..."
        sudo sed -i -E '/^[[:space:]]*tmpfs[[:space:]]+\/tmp[[:space:]]+tmpfs/d' /etc/fstab
    fi
    if [ -f /etc/dracut.conf.d/99-fast-boot-compression.conf ]; then
        log_info "Removing Dracut fast compression override..."
        sudo rm -f /etc/dracut.conf.d/99-fast-boot-compression.conf
    fi
    log_success "Boot and shutdown scripts restored to stock Slackware defaults."
}

# --- [ 7. STORAGE & NVME DIRECT I/O SCHEDULERS ] ---

deploy_tweak_ioschedulers() {
    log_info "Configuring direct hardware I/O schedulers (none for NVMe, mq-deadline for SATA SSD, bfq for HDD)..."
    sudo mkdir -p /etc/udev/rules.d

    cat << 'EOF_IOSCHED' | sudo tee /etc/udev/rules.d/60-slacky-ioschedulers.rules >/dev/null
# Slacky - Optimal Hardware I/O Schedulers
# High-speed NVMe PCIe Gen 4/5: direct bypass (none) to eliminate scheduler locking overhead
ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/scheduler}="none"

# SATA SSDs and eMMC: multi-queue deadline scheduler
ACTION=="add|change", KERNEL=="sd[a-z]|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"

# Mechanical Rotational HDDs: Budget Fair Queueing (BFQ) for desktop responsiveness
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
EOF_IOSCHED

    sudo udevadm control --reload-rules 2>/dev/null || true
    sudo udevadm trigger --subsystem-match=block 2>/dev/null || true

    for sch in /sys/block/nvme*n1/queue/scheduler; do
        if [ -w "$sch" ]; then
            echo "none" | sudo tee "$sch" >/dev/null 2>&1 || true
        fi
    done

    log_success "Direct hardware I/O schedulers active!"
}

revert_tweak_ioschedulers() {
    log_info "Reverting I/O scheduler rules to stock defaults..."
    sudo rm -f /etc/udev/rules.d/60-slacky-ioschedulers.rules /etc/udev/rules.d/60-ioschedulers.rules 2>/dev/null || true
    sudo udevadm control --reload-rules 2>/dev/null || true
    log_success "I/O schedulers restored to stock defaults."
}

# --- [ 8. NVIDIA & MESA 10GB SHADER DISK CACHE ] ---

deploy_tweak_nvidia_shader_cache() {
    log_info "Configuring 10GB global shader disk cache for NVIDIA and Mesa/RADV..."
    sudo mkdir -p /etc/profile.d

    cat << 'EOF_SHADER' | sudo tee /etc/profile.d/slacky-shader-cache.sh >/dev/null
#!/bin/sh
# Slacky - High-Performance 10GB Shader Cache for NVIDIA and Mesa/RADV
# Prevents pipeline compilation stutter and eliminates shader re-compilation
export __GL_SHADER_DISK_CACHE_SIZE=10737418240
export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1
export MESA_SHADER_CACHE_MAX_SIZE=10G
EOF_SHADER

    sudo chmod 0755 /etc/profile.d/slacky-shader-cache.sh
    export __GL_SHADER_DISK_CACHE_SIZE=10737418240
    export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1
    export MESA_SHADER_CACHE_MAX_SIZE=10G
    log_success "10GB shader disk cache environment variables configured (/etc/profile.d/slacky-shader-cache.sh)!"
}

revert_tweak_nvidia_shader_cache() {
    log_info "Reverting global shader cache configuration..."
    sudo rm -f /etc/profile.d/slacky-shader-cache.sh 2>/dev/null || true
    unset __GL_SHADER_DISK_CACHE_SIZE 2>/dev/null || true
    unset __GL_SHADER_DISK_CACHE_SKIP_CLEANUP 2>/dev/null || true
    unset MESA_SHADER_CACHE_MAX_SIZE 2>/dev/null || true
    log_success "Shader disk cache settings restored to stock driver defaults."
}

# --- [ 9. PIPEWIRE LOW-LATENCY AUDIO ] ---

deploy_tweak_pipewire_latency() {
    log_info "Configuring PipeWire low-latency drop-in profiles (256 quantum / 5.33ms) & RT95 limits..."
    sudo mkdir -p /etc/pipewire/pipewire.conf.d /etc/pipewire/pipewire-pulse.conf.d /etc/security/limits.d

    cat << 'EOF_PW' | sudo tee /etc/pipewire/pipewire.conf.d/99-slacky-lowlatency.conf >/dev/null
# Slacky - Low-Latency Pro-Audio & Gaming Quantum Drop-in
context.properties = {
    default.clock.rate = 48000
    default.clock.quantum = 256
    default.clock.min-quantum = 64
    default.clock.max-quantum = 1024
}
EOF_PW

    cat << 'EOF_PWP' | sudo tee /etc/pipewire/pipewire-pulse.conf.d/99-slacky-lowlatency.conf >/dev/null
# Slacky - Low-Latency PipeWire-Pulse Drop-in
pulse.properties = {
    pulse.min.req = 256/48000
    pulse.default.req = 256/48000
    pulse.max.req = 1024/48000
    pulse.min.quantum = 64/48000
}
EOF_PWP

    cat << 'EOF_AUDIO' | sudo tee /etc/security/limits.d/99-slacky-audio.conf >/dev/null
# Slacky - Realtime Audio Priorities for PipeWire and Pro-Audio Users
@audio - rtprio 95
@audio - memlock 4194304
@audio - nice -19
EOF_AUDIO

    log_success "PipeWire low-latency drop-ins active (256 samples / 5.33ms, RT95 priority)!"
}

revert_tweak_pipewire_latency() {
    log_info "Reverting PipeWire low-latency drop-in configurations..."
    sudo rm -f /etc/pipewire/pipewire.conf.d/99-slacky-lowlatency.conf \
               /etc/pipewire/pipewire-pulse.conf.d/99-slacky-lowlatency.conf \
               /etc/security/limits.d/99-slacky-audio.conf 2>/dev/null || true
    log_success "PipeWire audio configuration restored to stock Slackware defaults."
}

# --- [ BULK ACTIONS ] ---

# --- [ BASE HARDENING: LINK PROTECTION (6A-28) ] ---
# Not part of apply/revert-all: this is base safety, on by default (shipped by the package), not a gaming tweak.
PROTECT_LINKS_CONF="/etc/sysctl.d/50-slacky-protect-links.conf"

is_protect_links_active() {
    [ "$(cat /proc/sys/fs/protected_symlinks 2>/dev/null)" = "1" ] && [ "$(cat /proc/sys/fs/protected_hardlinks 2>/dev/null)" = "1" ]
}

_write_protect_links_conf() {
    local v="$1" r="$2" note="$3"
    sudo mkdir -p /etc/sysctl.d
    printf '%s\n' "# Slacky-Update base hardening (6A-28): ${note}" \
        "# Change with: slacky-update --protect-links on|off   (this file is kept on upgrades)" \
        "fs.protected_symlinks = ${v}" "fs.protected_hardlinks = ${v}" "fs.protected_regular = ${r}" "fs.protected_fifos = ${v}" \
        | sudo tee "${PROTECT_LINKS_CONF}" >/dev/null
    sudo chmod 0644 "${PROTECT_LINKS_CONF}"
    sudo sysctl -q -p "${PROTECT_LINKS_CONF}" >/dev/null 2>&1 || true
}

deploy_protect_links() {
    _write_protect_links_conf 1 2 "link protection on (the safe default)."
    is_protect_links_active && log_success "Link protection is on." || log_warn "Link protection could not be switched on."
}

revert_protect_links() {
    _write_protect_links_conf 0 0 "link protection turned OFF by the user."
    is_protect_links_active && log_warn "Link protection is still on." || log_warn "Link protection is off. Other users can trick programs through links in shared folders."
}

apply_all_tweaks() {
    echo ""
    log_info "Applying all recommended system and gaming optimizations..."
    deploy_tweak_limits
    deploy_tweak_thp_memory
    deploy_tweak_network_bbr
    deploy_tweak_ntsync
    deploy_tweak_controllers
    deploy_tweak_fastboot
    deploy_tweak_ioschedulers
    deploy_tweak_nvidia_shader_cache
    deploy_tweak_pipewire_latency
    echo ""
    log_success "Most Triumphant! All system & gaming tweaks are 100% armed and active."
}

revert_all_tweaks() {
    echo ""
    log_info "Reverting all system tweaks to stock Slackware defaults..."
    revert_tweak_limits
    revert_tweak_thp_memory
    revert_tweak_network_bbr
    revert_tweak_ntsync
    revert_tweak_controllers
    revert_tweak_fastboot
    revert_tweak_ioschedulers
    revert_tweak_nvidia_shader_cache
    revert_tweak_pipewire_latency
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
    local tui_py="${APP_DIR:-}/slacky_tui.py"
    [ ! -f "${tui_py}" ] && [ -f "/usr/share/slacky-update/lib/slacky_tui.py" ] && tui_py="/usr/share/slacky-update/lib/slacky_tui.py"

    while true; do
        local b_limits b_thp b_net b_ntsync b_ctrl b_fastboot b_iosched b_shadercache b_pwlatency
        b_limits=$(get_tweak_limits_badge)
        b_thp=$(get_tweak_thp_badge)
        b_net=$(get_tweak_network_badge)
        b_ntsync=$(get_tweak_ntsync_badge)
        b_ctrl=$(get_tweak_controllers_badge)
        b_fastboot=$(get_tweak_fastboot_badge)
        b_iosched=$(get_tweak_iosched_badge)
        b_shadercache=$(get_tweak_shadercache_badge)
        b_pwlatency=$(get_tweak_pwlatency_badge)

        local opt=""
        if [ -f "${tui_py}" ] && command -v python3 >/dev/null 2>&1 && [ -t 0 ]; then
            opt=$(python3 "${tui_py}" --mode tweaks \
                --limits-badge "${b_limits}" \
                --thp-badge "${b_thp}" \
                --net-badge "${b_net}" \
                --ntsync-badge "${b_ntsync}" \
                --ctrl-badge "${b_ctrl}" \
                --fastboot-badge "${b_fastboot}" \
                --iosched-badge "${b_iosched}" \
                --shadercache-badge "${b_shadercache}" \
                --pwlatency-badge "${b_pwlatency}")
        else
            echo ""
            echo -e "${BOLD}${CYAN}=============================================================================${RESET}"
            echo -e "${BOLD}${CYAN}               OPTIONAL SYSTEM & GAMING TWEAKS${RESET}"
            echo -e "${BOLD}${CYAN}=============================================================================${RESET}"
            echo -e "  \033[1;33m1.\033[0m File Descriptors & Process Limits (1M nofile, PipeWire rtprio) ${b_limits}"
            echo -e "  \033[1;33m2.\033[0m Kernel Memory & THP (madvise THP, dirty byte limits, swappiness=10) ${b_thp}"
            echo -e "  \033[1;33m3.\033[0m Network Low-Latency & BBR Congestion Control (fq, fastopen) ${b_net}"
            echo -e "  \033[1;33m4.\033[0m NTSYNC Fast Synchronization (/dev/ntsync 0666 permissions) ${b_ntsync}"
            echo -e "  \033[1;33m5.\033[0m Universal Gamepad & Controller Forcefield (27 Vendors, Logitech USB) ${b_ctrl}"
            echo -e "  \033[1;33m6.\033[0m Turbo Boot & Fast Shutdown Delays (Eliminate PCMCIA, NFS & rc.6 delays) ${b_fastboot}"
            echo -e "  \033[1;33m7.\033[0m Storage & NVMe Direct I/O Scheduler (none for NVMe, mq-deadline for SATA) ${b_iosched}"
            echo -e "  \033[1;33m8.\033[0m NVIDIA 10GB Global Shader Disk Cache (Permanent Shader Retention) ${b_shadercache}"
            echo -e "  \033[1;33m9.\033[0m PipeWire Low-Latency Audio (256 samples / 5.3ms, zero xruns) ${b_pwlatency}"
            echo -e "  \033[1;33m10.\033[0m Apply All Recommended Tweaks in One-Click"
            echo -e "  \033[1;33m11.\033[0m Revert All Tweaks to Stock Slackware Defaults"
            echo -e "  \033[1;33m12.\033[0m $(_ SBO_BACK_OPTION)"
            echo ""
            echo -n "$(_ SELECT_OPERATION_RANGE range="1-12") "
            read -r opt || opt="12"
        fi

        opt=$(echo "${opt}" | xargs)

        if [ -z "${opt}" ] || [ "${opt}" = "12" ] || [ "${opt}" = "Q" ] || [ "${opt}" = "q" ]; then
            return 0
        fi

        if [ "${opt}" = "10" ]; then
            apply_all_tweaks
            echo ""
            read -r -p "$(_ PRESS_ENTER_CONTINUE) " || true
            continue
        elif [ "${opt}" = "11" ]; then
            revert_all_tweaks
            echo ""
            read -r -p "$(_ PRESS_ENTER_CONTINUE) " || true
            continue
        fi

        if [[ "${opt}" =~ ^[1-9]$ ]]; then
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
                    manage_single_tweak_action "Turbo Boot & Fast Shutdown Delays" is_fastboot_active deploy_tweak_fastboot revert_tweak_fastboot
                    ;;
                7)
                    manage_single_tweak_action "Storage & NVMe Direct I/O Scheduler" is_iosched_active deploy_tweak_ioschedulers revert_tweak_ioschedulers
                    ;;
                8)
                    manage_single_tweak_action "NVIDIA 10GB Shader Disk Cache" is_shadercache_active deploy_tweak_nvidia_shader_cache revert_tweak_nvidia_shader_cache
                    ;;
                9)
                    manage_single_tweak_action "PipeWire Low-Latency Audio" is_pwlatency_active deploy_tweak_pipewire_latency revert_tweak_pipewire_latency
                    ;;
            esac
            echo ""
            read -r -p "$(_ PRESS_ENTER_CONTINUE) " || true
            continue
        fi

        # Multi-selection batch apply (e.g. "1 3" or "1 2 4 6 7 8")
        local valid_sel=()
        local tweak_labels=()
        for tok in ${opt}; do
            if [[ "${tok}" =~ ^[1-9]$ ]]; then
                valid_sel+=("${tok}")
                case "${tok}" in
                    1) tweak_labels+=("limits") ;;
                    2) tweak_labels+=("thp/memory") ;;
                    3) tweak_labels+=("network/bbr") ;;
                    4) tweak_labels+=("ntsync") ;;
                    5) tweak_labels+=("controllers") ;;
                    6) tweak_labels+=("fastboot/shutdown") ;;
                    7) tweak_labels+=("nvme-sched") ;;
                    8) tweak_labels+=("shadercache") ;;
                    9) tweak_labels+=("pwlatency") ;;
                esac
            fi
        done

        if [ ${#valid_sel[@]} -gt 0 ]; then
            echo ""
            echo -e "${BOLD}${CYAN}Tweaks selected for deployment:${RESET} ${tweak_labels[*]}"
            local confirm=""
            read -r -p "Do you want to apply the selected tweaks (${tweak_labels[*]}) to your system? [Y/n]: " confirm
            confirm=${confirm:-Y}
            if [[ "$confirm" =~ ^[YyJjSsOo]$ ]]; then
                echo ""
                for s in "${valid_sel[@]}"; do
                    case "${s}" in
                        1) deploy_tweak_limits ;;
                        2) deploy_tweak_thp_memory ;;
                        3) deploy_tweak_network_bbr ;;
                        4) deploy_tweak_ntsync ;;
                        5) deploy_tweak_controllers ;;
                        6) deploy_tweak_fastboot ;;
                        7) deploy_tweak_ioschedulers ;;
                        8) deploy_tweak_nvidia_shader_cache ;;
                        9) deploy_tweak_pipewire_latency ;;
                    esac
                done
                log_success "Selected tweaks successfully applied!"
            else
                log_warn "Application canceled by user."
            fi
            echo ""
            read -r -p "$(_ PRESS_ENTER_CONTINUE) " || true
        else
            log_warn "Invalid selection: ${opt}"
            echo ""
            read -r -p "$(_ PRESS_ENTER_CONTINUE) " || true
        fi
    done
}
