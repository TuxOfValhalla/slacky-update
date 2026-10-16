#!/usr/bin/env bash
# --- [ SLACKWARE & FLATPAK PACKAGE MANAGER ] ---

set -euo pipefail

get_slackpkg_tools_snapshot() {
    python3 -c "
import os
pkgs = os.listdir('/var/log/packages') if os.path.exists('/var/log/packages') else []
core = sorted([p for p in pkgs if p.startswith(('slackpkg-', 'slackpkg+-', 'pkgtools-', 'glibc-solibs-', 'aaa_glibc-solibs-', 'ca-certificates-'))])
print(';'.join(core))
" 2>/dev/null || echo ""
}

parallel_prefetch_packages() {
    local active_mirror
    active_mirror=$(grep -v '^#' /etc/slackpkg/mirrors 2>/dev/null | grep -E '^https?://' | head -n 1 || echo "")
    [ -n "${active_mirror}" ] || return 0
    [ -f "/var/lib/slackpkg/pkglist" ] || return 0

    sudo mkdir -p /var/cache/packages 2>/dev/null || true

    local candidates=()
    while IFS= read -r line; do
        [ -n "${line}" ] && candidates+=("${line}")
    done < <(python3 - "${active_mirror}" << 'PYPREFETCH'
import os
import sys
import re
import shutil

active_mirror = sys.argv[1].rstrip('/')
try:
    cache_path = '/var/cache/packages' if os.path.exists('/var/cache/packages') else '/var/cache'
    usage = shutil.disk_usage(cache_path)
    free_mb = usage.free // (1024 * 1024)
    if free_mb < 500:
        print(f"\033[1;33m⚠️ Low disk space warning: Only {free_mb} MB free on {cache_path}. Skipping pre-fetch to avoid filling disk.\033[0m", file=sys.stderr)
        sys.exit(0)
except Exception:
    pass

cache_base = '/var/cache/packages'
if not os.path.exists(cache_base) or not os.access(cache_base, os.W_OK):
    stage_base = os.path.expanduser('~/.cache/slacky-update/pkgcache')
    try:
        os.makedirs(stage_base, exist_ok=True)
        if os.access(stage_base, os.W_OK):
            cache_base = stage_base
    except Exception:
        pass

def parse_pkg_details(filename):
    clean = re.sub(r'\.(t[xg]z|tlz|tbz)$', '', filename)
    parts = clean.split('-')
    if len(parts) >= 4:
        base_name = "-".join(parts[:-3])
        version = parts[-3]
        arch = parts[-2]
        build = parts[-1]
        return base_name, version, arch, build, clean
    return clean, "0", "0", "0", clean

def split_numeric(s):
    tokens = re.split(r'(\d+)', str(s))
    res = []
    for t in tokens:
        if not t:
            continue
        if t.isdigit():
            res.append(int(t))
        else:
            res.append(t)
    return res

def is_strictly_newer(installed_full, upstream_full):
    if installed_full == upstream_full:
        return False
    _, i_ver, _, i_bld, _ = parse_pkg_details(installed_full)
    _, u_ver, _, u_bld, _ = parse_pkg_details(upstream_full)
    i_v = split_numeric(i_ver)
    u_v = split_numeric(u_ver)
    if u_v != i_v:
        return u_v > i_v
    i_b = split_numeric(i_bld)
    u_b = split_numeric(u_bld)
    return u_b > i_b

installed = {}
if os.path.exists('/var/log/packages'):
    for f in os.listdir('/var/log/packages'):
        parts = f.rsplit('-', 3)
        if len(parts) == 4:
            installed[parts[0]] = f

# 1. Read recently added packages from ChangeLog.txt so install-new packages are also pre-fetched
added_pkgs = set()
changelog_file = '/var/lib/slackpkg/ChangeLog.txt'
if os.path.exists(changelog_file):
    try:
        with open(changelog_file, 'r', encoding='utf-8', errors='ignore') as cf:
            header_count = 0
            for line in cf:
                if line.startswith(('Mon ', 'Tue ', 'Wed ', 'Thu ', 'Fri ', 'Sat ', 'Sun ')):
                    header_count += 1
                    if header_count > 40:
                        break
                if ':  Added.' in line or ': Added.' in line:
                    entry = line.split(':', 1)[0].strip()
                    if not entry.startswith(('testing/', 'pasture/', 'source/', 'extra/')):
                        pkg_base = os.path.basename(entry)
                        clean_base = pkg_base.rsplit('.', 1)[0]
                        name_parts = clean_base.rsplit('-', 3)
                        if len(name_parts) == 4:
                            added_pkgs.add(name_parts[0])
    except Exception:
        pass

mirror_map = {}
allowed_repos = {'slackware64', 'slackware', 'patches'}
conf_path = '/etc/slackpkg/slackpkgplus.conf'
if os.path.exists(conf_path):
    try:
        with open(conf_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            for line in content.splitlines():
                sline = line.strip()
                if sline.startswith('MIRRORPLUS[') and '=' in sline:
                    repo_key = sline.split('[', 1)[1].split(']', 1)[0].strip('\'"')
                    repo_url = sline.split('=', 1)[1].strip().strip('\'"').rstrip('/')
                    if repo_key and repo_url:
                        mirror_map[repo_key] = repo_url
                        allowed_repos.add(repo_key)
            match = re.search(r'REPOPLUS=\(\s*([^)]+)\s*\)', content, re.DOTALL)
            if match:
                for r in match.group(1).split():
                    allowed_repos.add(r.strip())
    except Exception:
        pass

if os.path.exists('/var/lib/slackpkg/pkglist'):
    with open('/var/lib/slackpkg/pkglist', 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 7:
                ext = parts[-1]
                relpath = parts[-2]
                fullname = parts[-3]
                build = parts[-4]
                arch = parts[-5]
                ver = parts[-6]
                name = parts[-7]
                raw_repo = parts[0] if len(parts) >= 8 else 'slackware64'
                clean_repo = raw_repo.replace('SLACKPKGPLUS_', '')
                
                is_allowed = (clean_repo in allowed_repos or raw_repo in allowed_repos or raw_repo.startswith('slackware') or (raw_repo.startswith('SLACKPKGPLUS_') and not raw_repo.startswith('slackware')))
                if is_allowed:
                    is_upgrade = (name in installed and is_strictly_newer(installed[name], fullname))
                    is_new_add = (name not in installed and name in added_pkgs)
                    if is_upgrade or is_new_add:
                        clean_rel = relpath.lstrip('./')
                        url_rel = clean_rel
                        if url_rel.startswith(f'SLACKPKGPLUS_{clean_repo}/'):
                            url_rel = url_rel[len(f'SLACKPKGPLUS_{clean_repo}/'):]
                        elif url_rel.startswith(f'{clean_repo}/') and clean_repo in mirror_map:
                            url_rel = url_rel[len(f'{clean_repo}/'):]
                        
                        pkg_file = f"{fullname}.{ext}"
                        base_url = mirror_map.get(clean_repo, mirror_map.get(raw_repo, active_mirror))
                        url = f"{base_url}/{url_rel}/{pkg_file}" if url_rel else f"{base_url}/{pkg_file}"
                        asc_url = f"{url}.asc"
                        dest_dir = f"{cache_base}/{clean_rel}" if clean_rel else f"{cache_base}/{clean_repo}"
                        dest_file = f"{dest_dir}/{pkg_file}"
                        asc_dest = f"{dest_file}.asc"
                        
                        std_dest = f"/var/cache/packages/{clean_rel}/{pkg_file}" if clean_rel else f"/var/cache/packages/{clean_repo}/{pkg_file}"
                        std_asc = f"{std_dest}.asc"
                        if os.path.exists(std_dest) and os.path.getsize(std_dest) > 0 and os.path.exists(std_asc) and os.path.getsize(std_asc) > 0:
                            continue
                        if os.path.exists(dest_file) and os.path.getsize(dest_file) > 0 and os.path.exists(asc_dest) and os.path.getsize(asc_dest) > 0:
                            continue
                        print(f"{url}|{dest_file}|{asc_url}|{asc_dest}")
PYPREFETCH
)

    if [ ${#candidates[@]} -gt 0 ]; then
        download_parallel_pacman "Slackware System & Multilib Packages" "${candidates[@]}" || true
    fi

    local stage_dir="${HOME:-/root}/.cache/slacky-update/pkgcache"
    if [ -d "${stage_dir}" ] && [ -n "$(ls -A "${stage_dir}" 2>/dev/null)" ]; then
        if [ "$(id -u)" -eq 0 ]; then
            if cp -rn "${stage_dir}"/* /var/cache/packages/ 2>/dev/null; then
                rm -rf "${stage_dir}" 2>/dev/null || true
            fi
        elif sudo -n cp -rn "${stage_dir}"/* /var/cache/packages/ 2>/dev/null; then
            rm -rf "${stage_dir}" 2>/dev/null || true
        elif sudo cp -rn "${stage_dir}"/* /var/cache/packages/ 2>/dev/null; then
            rm -rf "${stage_dir}" 2>/dev/null || true
        fi
    fi
}

clear_stale_slackpkg_locks() {
    if ls /var/lock/slackpkg.* >/dev/null 2>&1; then
        for lfile in /var/lock/slackpkg.*; do
            [ -f "${lfile}" ] || continue
            local lpid="${lfile##*.}"
            if [ -n "${lpid}" ] && [[ "${lpid}" =~ ^[0-9]+$ ]]; then
                if ! kill -0 "${lpid}" 2>/dev/null; then
                    log_warn "Clearing stale slackpkg lock file from dead process (PID: ${lpid})..."
                    if [ "$(id -u)" -eq 0 ]; then
                        rm -f "${lfile}" 2>/dev/null || true
                    else
                        sudo rm -f "${lfile}" 2>/dev/null || true
                    fi
                fi
            fi
        done
    fi
}

auto_reconcile_slackpkg_conf() {
    if [ -f "/etc/slackpkg/slackpkg.conf.new" ]; then
        log_info "Reconciling slackpkg configuration (/etc/slackpkg/slackpkg.conf.new)..."
        local new_ver
        new_ver=$(grep -E '^[[:space:]]*VERSION=' /etc/slackpkg/slackpkg.conf.new 2>/dev/null | tail -n1 | cut -d= -f2 | tr -d '"'\'' ' || true)

        if [ -f "/etc/slackpkg/slackpkg.conf" ]; then
            sudo cp -a /etc/slackpkg/slackpkg.conf /etc/slackpkg/slackpkg.conf.bak 2>/dev/null || true
            if [ -n "${new_ver}" ] && grep -q '^[[:space:]]*VERSION=' /etc/slackpkg/slackpkg.conf 2>/dev/null; then
                # 8B: only the VERSION line is edited (sed -i keeps owner, group and mode); the rest of the file is the user's
                sudo sed -i -E "s|^[[:space:]]*VERSION=.*|VERSION=${new_ver}|" /etc/slackpkg/slackpkg.conf 2>/dev/null || true
                if grep -qx "VERSION=${new_ver}" /etc/slackpkg/slackpkg.conf 2>/dev/null; then
                    sudo rm -f /etc/slackpkg/slackpkg.conf.new 2>/dev/null || true
                    log_success "Updated slackpkg.conf to match the newly installed slackpkg version (${new_ver}) while preserving user custom settings."
                fi
            else
                # 8B: a missing VERSION line on either side never lets the .new file replace the user's configuration
                log_warn "slackpkg.conf was kept as it is because its version line could not be matched; the new version waits as slackpkg.conf.new."
            fi
        else
            # no configuration yet: nothing of the user's can be lost, so the shipped file becomes the configuration
            sudo cp -a /etc/slackpkg/slackpkg.conf.new /etc/slackpkg/slackpkg.conf 2>/dev/null || true
            sudo rm -f /etc/slackpkg/slackpkg.conf.new 2>/dev/null || true
        fi
    fi
}

check_and_recommend_slackpkg_cacheupdate() {
    [ -f "/etc/slackpkg/slackpkgplus.conf" ] || return 0
    if grep -E "^[[:space:]]*CACHEUPDATE=on" /etc/slackpkg/slackpkgplus.conf >/dev/null 2>&1; then
        return 0
    fi

    # Check 30-day cooldown state
    local state_file="${XDG_CONFIG_HOME:-${HOME:-/root}/.config}/slacky-update/cacheupdate_prompt.state"
    if [ -f "${state_file}" ]; then
        local last_prompt_ts now_ts diff_days
        last_prompt_ts=$(cat "${state_file}" 2>/dev/null || echo "0")
        now_ts=$(date +%s)
        diff_days=$(( (now_ts - last_prompt_ts) / 86400 ))
        if [ "${diff_days}" -lt 30 ]; then
            return 0
        fi
    fi

    if [ -t 0 ] && [ "${NON_INTERACTIVE:-0}" != "1" ]; then
        echo ""
        echo -e "\033[1;36m⚡ Performance Optimization Tip (slackpkg+):\033[0m"
        echo -e "   Enabling \033[1mCACHEUPDATE=on\033[0m in slackpkgplus.conf accelerates 'slackpkg update'"
        echo -e "   by using conditional HTTP caching (wget -N) so unchanged metadata isn't re-downloaded."
        local reply_cache="Y"
        read -r -p "   Enable CACHEUPDATE=on in /etc/slackpkg/slackpkgplus.conf? [Y/n]: " reply_cache || reply_cache="Y"
        reply_cache=${reply_cache:-Y}
        if [[ "${reply_cache}" =~ ^[YyJjSsOo]$ ]]; then
            sudo sed -i 's/^[#[:space:]]*CACHEUPDATE=.*/CACHEUPDATE=on/' /etc/slackpkg/slackpkgplus.conf 2>/dev/null || true
            log_success "CACHEUPDATE=on enabled in /etc/slackpkg/slackpkgplus.conf! Metadata sync will now be significantly faster."
        else
            mkdir -p "$(dirname "${state_file}")" 2>/dev/null || true
            date +%s > "${state_file}" 2>/dev/null || true
            log_info "Keeping CACHEUPDATE=off. We won't prompt you about this again for 30 days."
        fi
    fi
}

# 6A-91 + 6A-92 (SS-1): checks after `slackpkg update`, before anything is installed. Returns 0 to go ahead, 1 to let the
# Slackware base wait this time (one plain sentence printed). Read-only except the accepted ChangeLog date it records.
#  - mirror older than the system: the top date of the mirror's ChangeLog must not be older than the last one accepted
#    here (a stale or rolled-back mirror would otherwise make upgrade-all DOWNGRADE every package, glibc included);
#  - root space: free space on / must cover twice the unpacked size of the packages that would change (old and new
#    coexist during upgradepkg, and the snapshot keeps the old blocks) plus 1 GB.
SLACKY_CHANGELOG_TOP="/var/lib/slacky-update/changelog-top"
ss_base_preflight() {
    local res
    res=$(python3 -I - "${SLACKY_CHANGELOG_TOP}" <<'PYPRE'
import os, sys, time, shutil
from datetime import datetime
state = sys.argv[1]
wd = "/var/lib/slackpkg"
top = 0
try:
    with open(os.path.join(wd, "ChangeLog.txt"), errors="replace") as fh:
        first = fh.readline().strip()
    top = int(datetime.strptime(first.replace("UTC", "+0000"), "%a %b %d %H:%M:%S %z %Y").timestamp())
except (OSError, ValueError):
    top = 0
last = 0
try:
    last = int(open(state).read().split()[0])
except (OSError, ValueError, IndexError):
    last = 0
if top and last and top < last:
    print("OLDER %s %s" % (time.strftime("%Y-%m-%d", time.gmtime(top)), time.strftime("%Y-%m-%d", time.gmtime(last))))
    sys.exit(0)
installed = {}
try:
    for n in os.listdir("/var/lib/pkgtools/packages"):
        parts = n.rsplit("-", 3)
        if len(parts) == 4:
            installed[parts[0]] = n
except OSError:
    pass
changing = set()
try:
    for line in open(os.path.join(wd, "pkglist"), errors="replace"):
        f = line.split()
        if len(f) >= 6 and f[1] in installed and installed[f[1]] != f[5]:
            changing.add(f[5])
except OSError:
    pass
need_kb = 0
cur = None
try:
    for line in open(os.path.join(wd, "PACKAGES.TXT"), errors="replace"):
        if line.startswith("PACKAGE NAME:"):
            cur = line.split(":", 1)[1].strip().rsplit(".", 1)[0]
        elif line.startswith("PACKAGE SIZE (uncompressed):") and cur in changing:
            v = line.split(":", 1)[1].split()
            n = float(v[0]); unit = v[1].upper() if len(v) > 1 else "K"
            need_kb += n * (1024 if unit.startswith("M") else 1)
except (OSError, ValueError):
    pass
# SS-1 follow-up: stock kernels write to /boot; with /boot not mounted they would land on the root fs instead
if os.environ.get("SLACKY_BOOT_UNREADY") == "1":
    boot_pkgs = sorted(p for p in changing if p.startswith(("kernel-generic-", "kernel-huge-")))
    if boot_pkgs:
        print("BOOT " + " ".join(boot_pkgs[:3]))
        sys.exit(0)
need = int(2 * need_kb * 1024 + 1024 ** 3)
free = shutil.disk_usage("/").free
if free < need:
    print("SPACE %.1f %.1f" % (need / 1e9, free / 1e9))
    sys.exit(0)
print("OK %d" % top)
PYPRE
)
    case "${res}" in
        OLDER*)
            set -- ${res}
            log_warn "Your Slackware mirror is older than your system (mirror ${2}, system ${3}), so Slackware updates wait to avoid downgrading. Pick another mirror with: slacky-update --rank-mirrors"
            return 1 ;;
        BOOT*)
            log_warn "Slackware kernel updates need the boot partition (/boot), which is not mounted for writing, so Slackware updates wait; everything else updates now."
            return 1 ;;
        SPACE*)
            set -- ${res}
            log_warn "There is not enough free space on / for the Slackware updates (${2} GB needed, ${3} GB free), so they wait. Free some space and run the update again."
            return 1 ;;
        "OK "*)
            local top="${res#OK }"
            if [ -n "${top}" ] && [ "${top}" != "0" ]; then
                sudo mkdir -p -m 0755 "${SLACKY_CHANGELOG_TOP%/*}" 2>/dev/null || true
                printf '%s\n' "${top}" | sudo tee "${SLACKY_CHANGELOG_TOP}.new" >/dev/null 2>&1 \
                    && sudo mv -f "${SLACKY_CHANGELOG_TOP}.new" "${SLACKY_CHANGELOG_TOP}" 2>/dev/null || true
            fi
            return 0 ;;
    esac
    return 0
}

update_slackware_core() {
    validate_privileges

    local slackpkg_bin
    slackpkg_bin=$(command -v slackpkg 2>/dev/null || echo "/usr/sbin/slackpkg")

    if [ ! -x "${slackpkg_bin}" ]; then
        log_error "slackpkg binary not found on this system."
        return 1
    fi

    clear_stale_slackpkg_locks
    auto_reconcile_slackpkg_conf
    check_and_recommend_slackpkg_cacheupdate

    if command -v check_and_shield_mirror_freshness >/dev/null 2>&1; then
        check_and_shield_mirror_freshness
    fi

    log_info "Synchronizing Slackware repository indexes..."
    if ! run_slackpkg -batch=on -default_answer=y update; then
        log_warn "Official Slackware repository mirror failed to update or is temporarily unavailable (e.g. syncing upstream)."
        log_warn "Skipping Slackware Core upgrade passes to prevent incomplete or failed deployment. Other update suites will proceed."
        heal_multilib_subsystem
        heal_host_sovereignty_subsystem
        reconcile_new_config_files
        return 2
    fi

    # 6A-91/6A-92: a mirror older than the system or too little space on / -> the base waits, everything else proceeds
    if ! ss_base_preflight; then
        heal_multilib_subsystem
        heal_host_sovereignty_subsystem
        reconcile_new_config_files
        return 2
    fi

    # 8A: remember which packages are installed now, and record the stock text of .new files that already wait
    local cfg_before
    cfg_before=$(mktemp /tmp/slacky-pkgs-before.XXXXXX 2>/dev/null || echo "")
    if [ -n "${cfg_before}" ]; then
        ls -1 /var/log/packages > "${cfg_before}" 2>/dev/null || true
        slacky_config_capture waiting
    fi

    # Engage Turbo Parallel Pre-fetch before install-new and upgrade-all
    parallel_prefetch_packages

    clear_stale_slackpkg_locks

    # 6A-7: slackpkg exit status (man slackpkg): 0 ok, 20 nothing to do, 50 slackpkg upgraded itself.
    # Anything else is a failure; the Slackware updates then stay pending instead of being cleared.
    local sp_failed=0
    local sp_rc=0

    log_info "Installing newly added distribution packages (install-new)..."
    run_slackpkg -batch=on -default_answer=y -postinst=off install-new || sp_rc=$?
    case "${sp_rc}" in
        0|20|50) ;;
        *) log_warn "slackpkg install-new failed (exit ${sp_rc})."; sp_failed=1 ;;
    esac

    log_info "Upgrading existing distribution packages (upgrade-all)..."

    local max_passes=3
    local current_pass=1

    while [ "${current_pass}" -le "${max_passes}" ]; do
        local tools_before tools_after
        tools_before=$(get_slackpkg_tools_snapshot)

        sp_rc=0
        run_slackpkg -batch=on -default_answer=y -postinst=off upgrade-all || sp_rc=$?
        case "${sp_rc}" in
            0|20|50) ;;
            *) log_warn "slackpkg upgrade-all failed in pass ${current_pass} (exit ${sp_rc})."; sp_failed=1 ;;
        esac

        tools_after=$(get_slackpkg_tools_snapshot)

        # Check if slackpkg or core package tools were upgraded in this pass
        if [ "${tools_before}" != "${tools_after}" ] && [ "${current_pass}" -lt "${max_passes}" ]; then
            echo -e "\n${YELLOW}${BOLD}$(_ SLACKPKG_SELF_UPGRADED)${RESET}"
            read_update_prompt "$(_ PROMPT_RESUME_UPGRADE)" "Y" reply_resume
            if [[ "$reply_resume" =~ ^[YyJjSsOo]$ ]]; then
                current_pass=$((current_pass + 1))
                echo ""
                log_info "Resuming full system upgrade with newly upgraded package tools (Pass ${current_pass})..."
                # CRITICAL MULTI-PASS RESUME CHAIN:
                # 1. Auto-reconcile slackpkg.conf.new so slackpkg does not abort on version check
                auto_reconcile_slackpkg_conf
                # 2. Refresh repository indexes so slackpkg+ re-initializes
                log_info "Refreshing package indexes to initialize updated package tools..."
                run_slackpkg -batch=on -default_answer=y update || true
                # 3. Re-check for any newly added distribution packages
                log_info "Checking for newly added packages (install-new)..."
                run_slackpkg -batch=on -default_answer=y -postinst=off install-new || true
                # 4. Pre-fetch remaining packages for the next pass
                parallel_prefetch_packages
                continue
            else
                break
            fi
        else
            break
        fi
    done

    # 8A: right after the base step, before anything else looks at /etc: store the stock text of the changed packages
    if [ -n "${cfg_before}" ]; then
        slacky_config_capture "${cfg_before}"
        rm -f "${cfg_before}" 2>/dev/null || true
    fi

    heal_multilib_subsystem
    heal_host_sovereignty_subsystem
    reconcile_new_config_files

    if [ "${sp_failed}" -ne 0 ]; then
        log_warn "Slackware package upgrade finished with errors. The pending updates are kept."
        return 3
    fi
    log_success "Slackware system package synchronization completed."
    return 0
}

heal_multilib_subsystem() {
    validate_privileges

    # Fast path: Check if multilib is present on the system
    local has_multilib=0
    if ls /var/log/packages/*-compat32* >/dev/null 2>&1 || [ -e "/lib/ld-linux.so.2" ] || [ -d "/lib/incoming" ]; then
        has_multilib=1
    elif [ -f "/etc/slackpkg/slackpkgplus.conf" ] && grep -E "REPOPLUS=.*multilib" /etc/slackpkg/slackpkgplus.conf >/dev/null 2>&1; then
        has_multilib=1
    fi

    [ "${has_multilib}" -eq 1 ] || return 0

    # Fast path: Check if /lib/incoming exists or /lib/ld-linux.so.2 is missing/broken
    local needs_healing=0
    if [ -d "/lib/incoming" ] && [ -n "$(ls -A /lib/incoming 2>/dev/null)" ]; then
        needs_healing=1
    elif [ -d "/usr/lib/incoming" ] && [ -n "$(ls -A /usr/lib/incoming 2>/dev/null)" ]; then
        needs_healing=1
    elif [ ! -e "/lib/ld-linux.so.2" ]; then
        needs_healing=1
    elif ! /lib/ld-linux.so.2 --version >/dev/null 2>&1; then
        needs_healing=1
    fi

    # Check libcrypt symlinks
    if [ -f "/lib/libcrypt.so.1.1.0" ] && [ ! -L "/lib/libcrypt.so.1" ]; then
        needs_healing=1
    fi
    if [ -f "/lib/libcrypt.so.2.0.0" ] && [ ! -L "/lib/libcrypt.so.2" ]; then
        needs_healing=1
    fi
    if [ ! -f "/etc/ld.so.conf.d/multilib.conf" ]; then
        needs_healing=1
    fi

    # If everything is 100% healthy, return immediately (< 5ms)
    if [ "${needs_healing}" -eq 0 ]; then
        return 0
    fi

    log_info "32-bit Multilib subsystem irregularity detected. Engaging Multilib Auto-Healer..."

    # Step 1: Drain any stranded /lib/incoming or /usr/lib/incoming files
    if [ -d "/lib/incoming" ] && [ -n "$(ls -A /lib/incoming 2>/dev/null)" ]; then
        log_info "Moving staged 32-bit glibc libraries from /lib/incoming to /lib..."
        sudo mv -f /lib/incoming/* /lib/ 2>/dev/null || true
        sudo rmdir /lib/incoming 2>/dev/null || true
    fi
    if [ -d "/usr/lib/incoming" ] && [ -n "$(ls -A /usr/lib/incoming 2>/dev/null)" ]; then
        log_info "Moving staged 32-bit glibc libraries from /usr/lib/incoming to /usr/lib..."
        sudo mv -f /usr/lib/incoming/* /usr/lib/ 2>/dev/null || true
        sudo rmdir /usr/lib/incoming 2>/dev/null || true
    fi

    # Step 2: If /lib/ld-linux.so.2 is still missing, find or fetch glibc-*-compat32
    if [ ! -e "/lib/ld-linux.so.2" ]; then
        log_warn "/lib/ld-linux.so.2 missing after glibc upgrade. Locating glibc-compat32 package..."
        local glibc_pkg=""
        glibc_pkg=$(find /var/cache/packages -name "glibc-*-compat32*.txz" 2>/dev/null | sort -V | tail -n 1 || echo "")
        if [ -n "${glibc_pkg}" ] && [ -f "${glibc_pkg}" ]; then
            # 6A-84: the cache dir can be writable by other users; install only a root-held copy whose signature
            # verifies against the keys slackpkg uses (root's keyring), never the cache file itself.
            local g_tmp g_ok=0 g_gpg
            g_gpg=$(command -v gpg1 || command -v gpg2 || command -v gpg || echo gpg)
            g_tmp=$(sudo mktemp -d /root/slacky-compat32.XXXXXX 2>/dev/null || echo "")
            if [ -n "${g_tmp}" ] && sudo cp -- "${glibc_pkg}" "${g_tmp}/" 2>/dev/null \
               && sudo cp -- "${glibc_pkg}.asc" "${g_tmp}/" 2>/dev/null \
               && sudo "${g_gpg}" --batch --verify "${g_tmp}/$(basename "${glibc_pkg}").asc" "${g_tmp}/$(basename "${glibc_pkg}")" >/dev/null 2>&1; then
                g_ok=1
            fi
            if [ "${g_ok}" -eq 1 ]; then
                log_info "Reinstalling 32-bit glibc from local cache: $(basename "${glibc_pkg}")..."
                sudo "${PKG_UPGRADE_CMD}" --reinstall --install-new "${g_tmp}/$(basename "${glibc_pkg}")" 2>/dev/null || true
            else
                log_warn "The cached 32-bit glibc package could not be verified, so it was not installed. Run the update again to download it fresh."
            fi
            [ -n "${g_tmp}" ] && sudo rm -rf -- "${g_tmp}" 2>/dev/null || true
            if [ -d "/lib/incoming" ] && [ -n "$(ls -A /lib/incoming 2>/dev/null)" ]; then
                sudo mv -f /lib/incoming/* /lib/ 2>/dev/null || true
                sudo rmdir /lib/incoming 2>/dev/null || true
            fi
        fi
    fi

    # Step 3: Hardened libcrypt symlinks
    if [ -f "/lib/libcrypt.so.1.1.0" ]; then
        sudo ln -sf libcrypt.so.1.1.0 /lib/libcrypt.so.1
    fi
    if [ -f "/lib/libcrypt.so.2.0.0" ]; then
        sudo ln -sf libcrypt.so.2.0.0 /lib/libcrypt.so.2
    fi

    # Step 4: Ensure /etc/ld.so.conf.d/multilib.conf exists
    sudo mkdir -p /etc/ld.so.conf.d
    if [ ! -f "/etc/ld.so.conf.d/multilib.conf" ] || ! grep -q "^/lib$" /etc/ld.so.conf.d/multilib.conf 2>/dev/null; then
        echo -e "/usr/local/lib\n/usr/lib\n/lib" | sudo tee /etc/ld.so.conf.d/multilib.conf >/dev/null 2>&1 || true
    fi

    # Step 5: Regenerate dynamic linker cache
    sudo "${LDCONFIG_CMD}" 2>/dev/null || true

    # Step 6: Active verification test
    if [ -e "/lib/ld-linux.so.2" ] && /lib/ld-linux.so.2 --version >/dev/null 2>&1; then
        local g_ver
        g_ver=$(/lib/ld-linux.so.2 --version 2>/dev/null | head -n 1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1 || echo "ready")
        log_success "32-bit Multilib subsystem successfully auto-healed (glibc ${g_ver}, /lib/ld-linux.so.2 verified)."
    else
        log_warn "Multilib Auto-Healer completed, but /lib/ld-linux.so.2 could not be fully verified."
    fi
}

heal_host_sovereignty_subsystem() {
    validate_privileges

    local gnomes_py=""
    for cand in "${SCRIPT_DIR:-}/gnomes_pacman.py" \
                "${APP_DIR:-}/gnomes_pacman.py" \
                "${SCRIPT_DIR:-}/../lib/gnomes_pacman.py" \
                "/usr/share/slacky-update/lib/gnomes_pacman.py" \
                "/usr/local/lib/slacky-update/gnomes_pacman.py"; do
        if [ -f "${cand}" ]; then
            gnomes_py="${cand}"
            break
        fi
    done
    [ -n "${gnomes_py}" ] || return 0

    log_info "Auditing Host Sovereignty and /usr/bin/ wrapper scoping..."
    local heal_out
    # 6A-137: heal needs root to change anything; a run that could not finish is never reported as clean
    local heal_rc=0
    if [ "$(id -u)" -eq 0 ]; then
        heal_out=$(python3 -I "${gnomes_py}" heal --json 2>/dev/null) || heal_rc=$?
    else
        heal_out=$(sudo python3 -I "${gnomes_py}" heal --json 2>/dev/null) || heal_rc=$?
    fi
    [ -n "${heal_out}" ] || heal_out="{}"
    if [ "${heal_rc}" -ne 0 ] || [ "$(python3 -I -c "import sys, json; print(len(json.loads(sys.argv[1]).get('errors', [])))" "${heal_out}" 2>/dev/null || echo 1)" != "0" ]; then
        log_warn "The check of program launchers in /usr/bin could not finish; nothing was changed there."
        return 0
    fi
    # 6A-154: launchers that hide a Slackware file are kept; the user gets the exact command (advice only)
    local kept_cmds
    kept_cmds=$(python3 -I -c "import sys, json; d = json.loads(sys.argv[1]); print(' '.join(sorted({k['package'] for k in d.get('kept_stock_owned', []) if k.get('package')})))" "${heal_out}" 2>/dev/null || echo "")
    if [ -n "${kept_cmds}" ]; then
        log_warn "A launcher hides an original Slackware file; it was not deleted. To restore the original, run:"
        for kpkg in ${kept_cmds}; do
            log_info "  slackpkg reinstall ${kpkg}"
        done
    fi
    # 6A-232: a launcher on a protected system name without a stock owner is never deleted; one sentence, the person decides
    local prot_names
    prot_names=$(python3 -I -c "import sys, json; d = json.loads(sys.argv[1]); print(' '.join(sorted({k['name'] for k in d.get('kept_protected', []) if k.get('name')})))" "${heal_out}" 2>/dev/null || echo "")
    if [ -n "${prot_names}" ]; then
        local pname
        for pname in ${prot_names}; do
            log_warn "A launcher named ${pname} sits where a system program belongs. Nothing was changed; check it by hand."
        done
    fi
    local purged_count
    purged_count=$(python3 -c "import sys, json; data = json.loads(sys.argv[1]); print(len(data.get('purged_wrappers', [])))" "${heal_out}" 2>/dev/null || echo "0")
    if [ "${purged_count}" -gt 0 ]; then
        log_warn "Purged ${purged_count} rogue wrapper(s) from /usr/bin/ to protect native Slackware binaries."
        local aff_pkgs
        aff_pkgs=$(python3 -c "import sys, json; data = json.loads(sys.argv[1]); print(' '.join(data.get('affected_packages', [])))" "${heal_out}" 2>/dev/null || echo "")
        if [ -n "${aff_pkgs}" ]; then
            log_info "Reinstalling affected native Slackware package(s): ${aff_pkgs}..."
            if command -v slackpkg >/dev/null 2>&1; then
                for apkg in ${aff_pkgs}; do
                    run_slackpkg -batch=on -default_answer=y reinstall "${apkg}" || true
                done
            fi
        fi
        log_success "Host Sovereignty successfully healed."
    else
        :   # 6A-137: silent on success
    fi
}

# 8A-8C: find a lib helper (installed, or next to the source tree)
slacky_find_helper() {
    local name="$1" cand
    for cand in "${SCRIPT_DIR:-}/../lib/${name}" "${APP_DIR:-}/${name}" "${SCRIPT_DIR:-}/${name}" \
                "/usr/share/slacky-update/lib/${name}" "/usr/local/lib/slacky-update/${name}"; do
        if [ -f "${cand}" ]; then
            printf '%s\n' "${cand}"
            return 0
        fi
    done
    return 1
}

# 6A-202 (spec section 0 and 4): signing keys first. Inside an explicit full update, before any package is verified or
# installed, a keyring package that the user phase staged (verified, newer, in the user's own cache) is installed by the
# root phase, which checks the raw bytes again from scratch (gnomes_trust.py install-staged; nothing staged = nothing
# happens, no sudo is asked). One plain sentence per refusal; the update itself continues (the old keys stay in force).
slacky_keys_first() {
    local sentinel trust stage out
    sentinel=$(slacky_find_helper slacky_sentinel.py) || return 0
    trust=$(slacky_find_helper gnomes_trust.py) || return 0
    if [ "$(id -u)" -ne 0 ]; then
        # user phase: stage a newer keyring when the synced database lists one (cheap when nothing is new)
        python3 -I "${sentinel}" keys-check >/dev/null 2>&1 || true
    fi
    stage="${XDG_CACHE_HOME:-${HOME:-/nonexistent}/.cache}/slacky-update/sentinel/keyring_stage"
    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        stage="$(getent passwd "${SUDO_USER}" | cut -d: -f6)/.cache/slacky-update/sentinel/keyring_stage"
    fi
    [ -d "${stage}" ] && [ -n "$(ls -A "${stage}" 2>/dev/null)" ] || return 0
    local owner_uid
    owner_uid=$(stat -c %u "${stage}" 2>/dev/null) || return 0
    out=$(sudo env PYTHONSAFEPATH=1 python3 -I "${trust}" install-staged "${stage}" "${owner_uid}" 2>/dev/null) || true
    if [ -n "${out}" ]; then
        local line
        while IFS= read -r line; do
            [ -n "${line}" ] && log_warn "${line}"
        done <<< "${out}"
    fi
    return 0
}

# 6A-202: the alert sentences that are due (a whole family at risk: fewer than 2 working download servers, no fresh
# server list for a month, a used signing key expiring within 60 days, new keys that could not be confirmed). Each
# condition is shown at most once per 7 days. Silent when nothing is wrong; never asks for sudo.
slacky_sentinel_alerts() {
    local sentinel line
    [ "$(id -u)" -ne 0 ] || return 0
    sentinel=$(slacky_find_helper slacky_sentinel.py) || return 0
    while IFS= read -r line; do
        [ -n "${line}" ] && log_warn "${line}"
    done < <(python3 -I "${sentinel}" alerts 2>/dev/null || true)
    return 0
}

# 8A: the stock text of etc/*.new files goes into /var/lib/slacky-config (format: docs/config_store_spec.md).
# $1 = file with the package names installed before the base step ("waiting" instead: record .new files that already wait).
# Silent on success; never changes /etc.
slacky_config_capture() {
    local helper
    helper=$(slacky_find_helper slacky_config.py) || return 0
    local rc=0
    if [ "$(id -u)" -eq 0 ]; then
        if [ "$1" = "waiting" ]; then python3 -I "${helper}" capture --waiting || rc=$?
        else python3 -I "${helper}" capture --before "$1" || rc=$?; fi
    else
        if [ "$1" = "waiting" ]; then sudo python3 -I "${helper}" capture --waiting || rc=$?
        else sudo python3 -I "${helper}" capture --before "$1" || rc=$?; fi
    fi
    return 0
}

# 8B/8C: .new configuration files. Only with a typed y, only the exact cases (you never edited the file -> replace,
# Slackware did not change it -> drop the waiting copy, identical -> drop it, missing -> add it). Everything else stays as
# it is. With -y, NON_INTERACTIVE or no terminal nothing is changed and one sentence says how many files wait.
# There is no "overwrite all customized files" path any more.
reconcile_new_config_files() {
    validate_privileges
    local helper
    helper=$(slacky_find_helper slacky_config.py) || return 0
    local extra=""
    if [ "${NON_INTERACTIVE:-0}" = "1" ] || [ ! -t 0 ]; then
        extra="--non-interactive"
    fi
    if [ "$(id -u)" -eq 0 ]; then
        python3 -I "${helper}" reconcile ${extra} || true
    else
        sudo python3 -I "${helper}" reconcile ${extra} || true
    fi
}

update_flatpaks() {
    if command -v flatpak >/dev/null 2>&1; then
        log_info "Updating Flatpak runtimes and applications..."
        flatpak update -y || {
            log_warn "Flatpak update completed with warnings."
        }
        log_success "Flatpak updates applied successfully."
    fi
}

rank_slackware_mirrors_interactive() {
    validate_privileges
    log_info "⚡ Probing and benchmarking official worldwide Slackware & Ecosystem mirrors..."

    local rank_py=""
    for cand in "${SCRIPT_DIR:-}/rank_mirrors.py" \
                "${APP_DIR:-}/rank_mirrors.py" \
                "/usr/share/slacky-update/lib/rank_mirrors.py" \
                "/usr/local/share/slacky-update/lib/rank_mirrors.py" \
                "/usr/local/lib/slacky-update/rank_mirrors.py"; do
        if [ -f "${cand}" ]; then
            rank_py="${cand}"
            break
        fi
    done

    if [ -n "${rank_py}" ]; then
        python3 "${rank_py}"
    fi

    local ranked_json=""
    if [ -f "${XDG_CACHE_HOME:-${HOME}/.cache}/slacky-update/ranked_mirrors.json" ]; then
        ranked_json=$(cat "${XDG_CACHE_HOME:-${HOME}/.cache}/slacky-update/ranked_mirrors.json" 2>/dev/null || echo "")
    elif [ -f "/var/cache/slacky-update/ranked_mirrors.json" ]; then
        ranked_json=$(cat "/var/cache/slacky-update/ranked_mirrors.json" 2>/dev/null || echo "")
    fi

    echo -n "Select mirror to set as primary in /etc/slackpkg/mirrors [1-10 or Enter to cancel]: "
    local sel
    read -r sel || sel=""
    if [ -n "${sel}" ] && [[ "${sel}" =~ ^[0-9]+$ ]] && [ "${sel}" -ge 1 ] && [ "${sel}" -le 10 ] && [ -n "${ranked_json}" ]; then
        local chosen_url
        chosen_url=$(python3 -c "import sys, json; data = json.loads(sys.argv[1]); print(data['slackware_ranked'][int(sys.argv[2])-1]['url'])" "${ranked_json}" "${sel}" 2>/dev/null || echo "")
        # 6A-87: only a plain mirror URL, written to a private temp file (was the fixed /tmp/mirrors.tmp, which another
        # local user could plant before root moved it into /etc/slackpkg/mirrors)
        if [[ ! "${chosen_url}" =~ ^(https?|ftp)://[A-Za-z0-9._~:/%+-]+$ ]]; then
            [ -n "${chosen_url}" ] && log_warn "That mirror address looks wrong, so /etc/slackpkg/mirrors was not changed."
            chosen_url=""
        fi
        # 6A-140: one writer for /etc/slackpkg/mirrors (rank_mirrors.py --apply): same release branch, a ChangeLog at
        # least as new as the current mirror, a marked block and a backup; it refuses otherwise and says why
        if [ -n "${chosen_url}" ] && [ -n "${rank_py}" ]; then
            if sudo python3 -I "${rank_py}" --apply "${chosen_url}" --yes; then
                log_info "Your Slackware mirror is now ${chosen_url}."
            else
                log_warn "The mirror was not changed; /etc/slackpkg/mirrors is as it was."
            fi
        fi
    fi
}
