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

    sudo python3 - "${active_mirror}" << 'PYPREFETCH'
import os
import sys
import shutil
import time
import subprocess
import threading
import concurrent.futures

active_mirror = sys.argv[1].rstrip('/')
try:
    cache_path = '/var/cache/packages' if os.path.exists('/var/cache/packages') else '/var/cache'
    usage = shutil.disk_usage(cache_path)
    free_mb = usage.free // (1024 * 1024)
    if free_mb < 500:
        print(f"\033[1;33m⚠️ Low disk space warning: Only {free_mb} MB free on {cache_path}. Skipping pre-fetch to avoid filling disk.\033[0m")
        sys.exit(0)
except Exception:
    pass

installed = {}
if os.path.exists('/var/log/packages'):
    for f in os.listdir('/var/log/packages'):
        parts = f.rsplit('-', 3)
        if len(parts) == 4:
            installed[parts[0]] = f

# Read recently added packages from ChangeLog.txt so install-new packages are also pre-fetched
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
if os.path.exists('/etc/slackpkg/slackpkgplus.conf'):
    with open('/etc/slackpkg/slackpkgplus.conf', 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            sline = line.strip()
            if sline.startswith('REPOPLUS=('):
                inside = sline.split('(', 1)[1].split(')', 1)[0]
                for r in inside.split():
                    allowed_repos.add(r.strip())
            elif sline.startswith('MIRRORPLUS[') and '=' in sline:
                repo_key = sline.split('[', 1)[1].split(']', 1)[0].strip('\'"')
                repo_url = sline.split('=', 1)[1].strip().strip('\'"').rstrip('/')
                if repo_key and repo_url:
                    mirror_map[repo_key] = repo_url

candidates = []
if os.path.exists('/var/lib/slackpkg/pkglist'):
    with open('/var/lib/slackpkg/pkglist', 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 8:
                repo, name, ver, arch, build, fullname, relpath, ext = parts[0], parts[1], parts[2], parts[3], parts[4], parts[5], parts[6], parts[7]
                if repo in allowed_repos:
                    # Candidates: either upgrade of an installed package OR newly added package for install-new
                    is_upgrade = (name in installed and installed[name] != fullname)
                    is_new_add = (name not in installed and name in added_pkgs)
                    if is_upgrade or is_new_add:
                        clean_rel = relpath.lstrip('./')
                        pkg_file = f"{fullname}.{ext}"
                        base_url = mirror_map.get(repo, active_mirror)
                        url = f"{base_url}/{clean_rel}/{pkg_file}" if clean_rel else f"{base_url}/{pkg_file}"
                        asc_url = f"{url}.asc"
                        dest_dir = f"/var/cache/packages/{clean_rel}" if clean_rel else f"/var/cache/packages/{repo}"
                        dest_file = f"{dest_dir}/{pkg_file}"
                        asc_dest = f"{dest_file}.asc"
                        if os.path.exists(dest_file) and os.path.getsize(dest_file) > 0 and os.path.exists(asc_dest) and os.path.getsize(asc_dest) > 0:
                            continue
                        candidates.append((clean_rel or repo, pkg_file, url, asc_url, dest_dir, dest_file, asc_dest))

total = len(candidates)
if total == 0:
    sys.exit(0)

try:
    num_workers = int(os.environ.get('SLACKY_PREFETCH_JOBS', '10'))
    num_workers = max(1, min(num_workers, 32))
except Exception:
    num_workers = 10

print(f"\033[1;36m🚀 Turbo Parallel Pre-fetch: Downloading {total} packages ({num_workers} parallel streams)...\033[0m")
sys.stdout.flush()

counter = 0
success_count = 0
fail_count = 0
counter_lock = threading.Lock()

def download_item(item):
    global counter, success_count, fail_count
    clean_rel, pkg_file, url, asc_url, dest_dir, dest_file, asc_dest = item
    os.makedirs(dest_dir, exist_ok=True)
    part_file = f"{dest_file}.part"
    part_asc = f"{asc_dest}.part"
    t0 = time.time()

    # Download payload using curl with resume support (-C -)
    res = subprocess.run(["curl", "-sSL", "-f", "-C", "-", "-m", "120", "-o", part_file, url], capture_output=True)
    if res.returncode == 0 and os.path.exists(part_file) and os.path.getsize(part_file) > 0:
        # Download asc signature
        res_asc = subprocess.run(["curl", "-sSL", "-f", "-m", "30", "-o", part_asc, asc_url], capture_output=True)
        if res_asc.returncode == 0 and os.path.exists(part_asc) and os.path.getsize(part_asc) > 0:
            # Atomic rename into final destinations
            os.replace(part_file, dest_file)
            os.replace(part_asc, asc_dest)
            dt = max(time.time() - t0, 0.001)
            sz = os.path.getsize(dest_file)
            sz_mb = sz / (1024 * 1024)
            spd_mb = sz_mb / dt
            if sz_mb >= 1.0:
                sz_str = f"{sz_mb:.1f} MB"
            else:
                sz_str = f"{sz / 1024:.0f} KB"
            spd_str = f"{spd_mb:.1f} MB/s"
            with counter_lock:
                counter += 1
                success_count += 1
                c = counter
            print(f"  [\033[1;32m{c:4d}/{total}\033[0m] \033[1;34m✓\033[0m {clean_rel}/{pkg_file} (\033[1;37m{sz_str}\033[0m, \033[1;36m{spd_str}\033[0m)")
            sys.stdout.flush()
            return
        else:
            if os.path.exists(part_asc):
                try: os.remove(part_asc)
                except Exception: pass
            if os.path.exists(part_file):
                try: os.remove(part_file)
                except Exception: pass

    with counter_lock:
        counter += 1
        fail_count += 1

with concurrent.futures.ThreadPoolExecutor(max_workers=num_workers) as executor:
    list(executor.map(download_item, candidates))

if fail_count > 0:
    print(f"\033[1;33m⚠️ Turbo Parallel Pre-fetch finished: {success_count}/{total} packages cached ({fail_count} failed, slackpkg will fallback to direct download).\033[0m\n")
else:
    print(f"\033[1;32m✓ Turbo Parallel Pre-fetch completed: {success_count} packages cached to /var/cache/packages.\033[0m\n")
sys.stdout.flush()
PYPREFETCH
}

update_slackware_core() {
    validate_privileges

    local slackpkg_bin
    slackpkg_bin=$(command -v slackpkg 2>/dev/null || echo "/usr/sbin/slackpkg")

    if [ ! -x "${slackpkg_bin}" ]; then
        log_error "slackpkg binary not found on this system."
        return 1
    fi

    if command -v check_and_shield_mirror_freshness >/dev/null 2>&1; then
        check_and_shield_mirror_freshness
    fi

    log_info "Synchronizing Slackware repository indexes..."
    sudo "${slackpkg_bin}" update || {
        log_warn "slackpkg update completed with non-zero exit code."
    }

    # Engage Turbo Parallel Pre-fetch before install-new and upgrade-all
    parallel_prefetch_packages

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
                # 1. Refresh repository indexes so slackpkg+ re-initializes
                log_info "Refreshing package indexes to initialize updated package tools..."
                sudo "${slackpkg_bin}" update || true
                # 2. Re-check for any newly added distribution packages
                log_info "Checking for newly added packages (install-new)..."
                sudo "${slackpkg_bin}" -postinst=off install-new || true
                # 3. Pre-fetch remaining packages for the next pass
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
