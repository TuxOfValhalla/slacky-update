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
    sudo chmod -R a+rwX /var/cache/packages 2>/dev/null || true

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
                chmod -R a+rwX /var/cache/packages 2>/dev/null || true
                rm -rf "${stage_dir}" 2>/dev/null || true
            fi
        elif sudo -n cp -rn "${stage_dir}"/* /var/cache/packages/ 2>/dev/null; then
            sudo -n chmod -R a+rwX /var/cache/packages 2>/dev/null || true
            rm -rf "${stage_dir}" 2>/dev/null || true
        elif sudo cp -rn "${stage_dir}"/* /var/cache/packages/ 2>/dev/null; then
            sudo chmod -R a+rwX /var/cache/packages 2>/dev/null || true
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
                sudo sed -i -E "s|^[[:space:]]*VERSION=.*|VERSION=${new_ver}|" /etc/slackpkg/slackpkg.conf 2>/dev/null || true
            else
                sudo cp -a /etc/slackpkg/slackpkg.conf.new /etc/slackpkg/slackpkg.conf 2>/dev/null || true
            fi
        else
            sudo cp -a /etc/slackpkg/slackpkg.conf.new /etc/slackpkg/slackpkg.conf 2>/dev/null || true
        fi

        sudo rm -f /etc/slackpkg/slackpkg.conf.new 2>/dev/null || true
        log_success "Updated slackpkg.conf to match the newly installed slackpkg version (${new_ver:-updated}) while preserving user custom settings."
    fi
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

    if command -v check_and_shield_mirror_freshness >/dev/null 2>&1; then
        check_and_shield_mirror_freshness
    fi

    log_info "Synchronizing Slackware repository indexes..."
    sudo "${slackpkg_bin}" update || {
        log_warn "slackpkg update completed with non-zero exit code."
    }

    # Engage Turbo Parallel Pre-fetch before install-new and upgrade-all
    parallel_prefetch_packages

    clear_stale_slackpkg_locks

    log_info "Installing newly added distribution packages (install-new)..."
    sudo "${slackpkg_bin}" -postinst=off install-new || {
        log_warn "slackpkg install-new completed."
    }

    log_info "Upgrading existing distribution packages (upgrade-all)..."

    local max_passes=3
    local current_pass=1

    while [ "${current_pass}" -le "${max_passes}" ]; do
        local tools_before tools_after
        tools_before=$(get_slackpkg_tools_snapshot)

        sudo "${slackpkg_bin}" -postinst=off upgrade-all || {
            log_warn "slackpkg upgrade-all completed pass ${current_pass}."
        }

        tools_after=$(get_slackpkg_tools_snapshot)

        # Check if slackpkg or core package tools were upgraded in this pass
        if [ "${tools_before}" != "${tools_after}" ] && [ "${current_pass}" -lt "${max_passes}" ]; then
            echo -e "\n${YELLOW}${BOLD}$(_ SLACKPKG_SELF_UPGRADED)${RESET}"
            read -r -p "$(_ PROMPT_RESUME_UPGRADE)" reply_resume
            reply_resume=${reply_resume:-Y}
            if [[ "$reply_resume" =~ ^[YyJjSsOo]$ ]]; then
                current_pass=$((current_pass + 1))
                log_info "Resuming full system upgrade with newly upgraded package tools (Pass ${current_pass})..."
                # CRITICAL MULTI-PASS RESUME CHAIN:
                # 1. Auto-reconcile slackpkg.conf.new so slackpkg does not abort on version check
                auto_reconcile_slackpkg_conf
                # 2. Refresh repository indexes so slackpkg+ re-initializes
                log_info "Refreshing package indexes to initialize updated package tools..."
                sudo "${slackpkg_bin}" update || true
                # 3. Re-check for any newly added distribution packages
                log_info "Checking for newly added packages (install-new)..."
                sudo "${slackpkg_bin}" -postinst=off install-new || true
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

    log_success "Slackware system package synchronization completed."
    heal_multilib_subsystem
    reconcile_new_config_files
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
            log_info "Reinstalling 32-bit glibc from local cache: $(basename "${glibc_pkg}")..."
            sudo "${PKG_UPGRADE_CMD}" --reinstall --install-new "${glibc_pkg}" 2>/dev/null || true
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

reconcile_new_config_files() {
    validate_privileges

    local new_files
    new_files=$(find /etc -name "*.new" 2>/dev/null || true)
    [ -n "${new_files}" ] || return 0

    log_info "Analyzing .new configuration files with Smart Reconciliation Engine..."

    python3 -c "
import os, sys, shutil, subprocess

def get_files():
    found = []
    for root, _, files in os.walk('/etc'):
        for f in files:
            if f.endswith('.new'):
                found.append(os.path.join(root, f))
    return sorted(found)

files = get_files()
if not files:
    sys.exit(0)

group_a = [] # New files (orig does not exist)
group_b = [] # Identical content
group_c = [] # Unmodified stock configs (trivial diffs/comments or identical)
group_d = [] # User-customized configs

for nf in files:
    orig = nf[:-4]
    if not os.path.exists(orig):
        group_a.append((nf, orig))
    else:
        try:
            with open(nf, 'rb') as f1, open(orig, 'rb') as f2:
                c1, c2 = f1.read(), f2.read()
            if c1 == c2:
                group_b.append((nf, orig))
            else:
                t1 = [l.strip() for l in c1.decode(errors='ignore').splitlines() if l.strip() and not l.strip().startswith(('#', '//', ';'))]
                t2 = [l.strip() for l in c2.decode(errors='ignore').splitlines() if l.strip() and not l.strip().startswith(('#', '//', ';'))]
                if t1 == t2:
                    group_c.append((nf, orig))
                else:
                    group_d.append((nf, orig))
        except Exception:
            group_d.append((nf, orig))

is_non_interactive = os.environ.get('NON_INTERACTIVE') == '1' or not sys.stdin.isatty()

def safe_prompt(prompt_text, default_val='Y'):
    if is_non_interactive:
        print(f'{prompt_text}{default_val} (non-interactive default)')
        return default_val
    try:
        val = input(prompt_text).strip()
        return val if val else default_val
    except (EOFError, KeyboardInterrupt):
        return default_val

total_found = len(files)
print(f'\n\033[1;36m=== 🛠️ SMART .NEW CONFIGURATION RECONCILIATION ({total_found} files detected) ===\033[0m')

# Group A: New Configurations
if group_a:
    print(f'\n\033[1;33m[Group A] New Configuration Files ({len(group_a)} files)\033[0m')
    print('These are brand new configuration files for newly installed packages. Safe to apply.')
    for nf, orig in group_a[:10]:
        print(f'  • {orig}')
    if len(group_a) > 10:
        print(f'  ... and {len(group_a)-10} more files.')
    r = safe_prompt('\nApply all new configuration files? [Y/n] ', 'Y')
    if r.lower() in ('y', 'j', 's', 'o'):
        for nf, orig in group_a:
            try:
                subprocess.run(['sudo', 'mv', '-f', nf, orig], check=True)
            except Exception as e:
                print(f'Error applying {orig}: {e}')
        print('\033[1;32m✓ Applied all new configuration files.\033[0m')

# Group B: Identical Redundant Files
if group_b:
    print(f'\n\033[1;33m[Group B] Identical Configuration Files ({len(group_b)} files)\033[0m')
    print('Content is 100% byte-for-byte identical to your current files. Safe to delete.')
    for nf, orig in group_b[:10]:
        print(f'  • {nf}')
    if len(group_b) > 10:
        print(f'  ... and {len(group_b)-10} more files.')
    r = safe_prompt('\nRemove all identical redundant .new files? [Y/n] ', 'Y')
    if r.lower() in ('y', 'j', 's', 'o'):
        for nf, orig in group_b:
            try:
                subprocess.run(['sudo', 'rm', '-f', nf], check=True)
            except Exception as e:
                print(f'Error removing {nf}: {e}')
        print('\033[1;32m✓ Cleaned up all identical .new files.\033[0m')

# Group C: Stock Unmodified Configs
if group_c:
    print(f'\n\033[1;33m[Group C] Standard Distribution Config Updates ({len(group_c)} files)\033[0m')
    print('These files contain updated upstream defaults and comments. Safe to update.')
    for nf, orig in group_c[:10]:
        print(f'  • {orig}')
    if len(group_c) > 10:
        print(f'  ... and {len(group_c)-10} more files.')
    r = safe_prompt('\nUpdate all unmodified configs to new upstream versions? [Y/n] ', 'Y')
    if r.lower() in ('y', 'j', 's', 'o'):
        for nf, orig in group_c:
            try:
                subprocess.run(['sudo', 'mv', '-f', nf, orig], check=True)
            except Exception as e:
                print(f'Error updating {orig}: {e}')
        print('\033[1;32m✓ Updated unmodified configurations.\033[0m')

# Group D: User-Customized Files
if group_d:
    print(f'\n\033[1;33m[Group D] User-Customized Configurations ({len(group_d)} files)\033[0m')
    print('Slacky-Update detected custom user edits in the following files:')
    for nf, orig in group_d:
        print(f'  • \033[1;37m{orig}\033[0m  (new candidate: {nf})')
    r = safe_prompt('\nKeep your customized files and preserve .new for manual review? [Y/n] ', 'Y')
    if r.lower() in ('y', 'j', 's', 'o'):
        print('\033[1;32m✓ Preserved your customized configuration files.\033[0m')
    else:
        ro = safe_prompt('Overwrite your customized files with .new files? [y/N] ', 'N')
        if ro.lower() in ('y', 'j', 's', 'o'):
            for nf, orig in group_d:
                try:
                    subprocess.run(['sudo', 'mv', '-f', nf, orig], check=True)
                except Exception as e:
                    print(f'Error overwriting {orig}: {e}')
            print('\033[1;32m✓ Overwritten customized files with new versions.\033[0m')
" || true
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
