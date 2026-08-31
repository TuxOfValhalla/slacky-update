#!/usr/bin/env bash
# --- [ SLACKWARE & FLATPAK PACKAGE MANAGER ] ---

set -euo pipefail

get_slackpkg_tools_snapshot() {
    python3 -c "
import os
pkgs = os.listdir('/var/log/packages') if os.path.exists('/var/log/packages') else []
core = sorted([p for p in pkgs if p.startswith(('slackpkg-', 'slackpkg+-', 'pkgtools-', 'glibc-solibs-'))])
print(';'.join(core))
" 2>/dev/null || echo ""
}

update_slackware_core() {
    validate_privileges

    local slackpkg_bin
    slackpkg_bin=$(command -v slackpkg 2>/dev/null || echo "/usr/sbin/slackpkg")

    if [ ! -x "${slackpkg_bin}" ]; then
        log_error "slackpkg binary not found on this system."
        return 1
    fi

    log_info "Synchronizing Slackware repository indexes..."
    sudo "${slackpkg_bin}" update || {
        log_warn "slackpkg update completed with non-zero exit code."
    }

    log_info "Installing newly added distribution packages (install-new)..."
    sudo "${slackpkg_bin}" install-new || {
        log_warn "slackpkg install-new completed."
    }

    log_info "Upgrading existing distribution packages (upgrade-all)..."

    local max_passes=3
    local current_pass=1

    while [ "${current_pass}" -le "${max_passes}" ]; do
        local tools_before tools_after
        tools_before=$(get_slackpkg_tools_snapshot)

        sudo "${slackpkg_bin}" upgrade-all || {
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
                continue
            else
                break
            fi
        else
            break
        fi
    done

    log_success "Slackware system package synchronization completed."
    reconcile_new_config_files
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
    r = input('\nApply all new configuration files? [Y/n] ').strip() or 'Y'
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
    r = input('\nRemove all identical redundant .new files? [Y/n] ').strip() or 'Y'
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
    r = input('\nUpdate all unmodified configs to new upstream versions? [Y/n] ').strip() or 'Y'
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
    r = input('\nKeep your customized files and preserve .new for manual review? [Y/n] ').strip() or 'Y'
    if r.lower() in ('y', 'j', 's', 'o'):
        print('\033[1;32m✓ Preserved your customized configuration files.\033[0m')
    else:
        ro = input('Overwrite your customized files with .new files? [y/N] ').strip() or 'N'
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
