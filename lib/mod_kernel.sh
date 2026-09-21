#!/usr/bin/env bash
# --- [ CACHYOS KERNEL & INITRD ENGINE ] ---

set -euo pipefail

# --- [ ARCHITECTURE DETECTION ] ---
detect_cpu_tier() {
    local cpuinfo="/proc/cpuinfo"
    if grep -q "avx512f" "${cpuinfo}" && \
       grep -q "avx512bw" "${cpuinfo}" && \
       grep -q "avx512cd" "${cpuinfo}" && \
       grep -q "avx512dq" "${cpuinfo}" && \
       grep -q "avx512vl" "${cpuinfo}"; then
        if grep -q "AuthenticAMD" "${cpuinfo}"; then
            echo "znver4"
        else
            echo "v4"
        fi
    elif grep -q "avx2" "${cpuinfo}" && \
         grep -q "fma" "${cpuinfo}" && \
         grep -q "bmi1" "${cpuinfo}" && \
         grep -q "bmi2" "${cpuinfo}"; then
        echo "v3"
    else
        echo "generic"
    fi
}

is_laptop_chassis() {
    [ -d "/sys/class/power_supply" ] && ls /sys/class/power_supply/BAT* >/dev/null 2>&1 && return 0
    local chassis
    chassis=$(cat /sys/class/dmi/id/chassis_type 2>/dev/null || echo "")
    if [[ "${chassis}" =~ ^(8|9|10|14|30|31|32)$ ]]; then
        return 0
    fi
    return 1
}

has_realtek_2_5gbe_hardware() {
    if [ -d "/sys/bus/pci/devices" ]; then
        for dev in /sys/bus/pci/devices/*; do
            [ -f "${dev}/vendor" ] && [ -f "${dev}/device" ] || continue
            local vendor devid
            vendor=$(cat "${dev}/vendor" 2>/dev/null || echo "")
            devid=$(cat "${dev}/device" 2>/dev/null || echo "")
            if [ "${vendor,,}" = "0x10ec" ]; then
                case "${devid,,}" in
                    "0x8125"|"0x3000")
                        return 0
                        ;;
                esac
            fi
        done
    fi
    if command -v lspci >/dev/null 2>&1; then
        if lspci -n 2>/dev/null | grep -qiE "10ec:(8125|3000)"; then
            return 0
        fi
        if lspci 2>/dev/null | grep -qiE "RTL8125|Realtek.*2\.5G|Killer.*E3100"; then
            return 0
        fi
    fi
    return 1
}

is_r8125_enabled() {
    if [ -f "/etc/slacky-update/r8125.enabled" ] || [ -f "/var/cache/slacky-update/r8125.enabled" ]; then
        return 0
    fi
    if ls /var/log/packages/*r8125* >/dev/null 2>&1; then
        return 0
    fi
    if find /lib/modules /usr/lib/modules -name "r8125.ko*" 2>/dev/null | grep -q "r8125"; then
        return 0
    fi
    return 1
}

is_r8125_wanted() {
    local kver="${1:-}"
    if ! has_realtek_2_5gbe_hardware; then
        return 1
    fi
    if [ -f "/etc/slacky-update/r8125.disabled" ]; then
        return 1
    fi
    if is_r8125_enabled; then
        return 0
    fi

    # First-time interactive prompt
    if [ -t 0 ] || [ -n "${PS1:-}" ] || [ "${INTERACTIVE:-0}" = "1" ]; then
        echo ""
        log_info "$(_ HARDWARE_REALTEK_2_5GBE_DETECTED 2>/dev/null || echo "⚡ Realtek 2.5GbE Ethernet NIC detected (RTL8125).")"
        echo -n "$(_ PROMPT_INSTALL_R8125_MODULE version="${kver:-latest}" 2>/dev/null || echo "Would you like to auto-install the high-performance CachyOS r8125 module? [Y/n]: ")"
        local reply_r8125
        read -r reply_r8125 || reply_r8125="Y"
        reply_r8125=${reply_r8125:-Y}
        if [[ "${reply_r8125}" =~ ^[YyJjSsOo]$ ]]; then
            sudo mkdir -p /etc/slacky-update /var/cache/slacky-update 2>/dev/null || true
            sudo touch /etc/slacky-update/r8125.enabled 2>/dev/null || touch /var/cache/slacky-update/r8125.enabled 2>/dev/null || true
            log_success "Realtek r8125 module auto-sync enabled for CachyOS kernels."
            return 0
        else
            sudo mkdir -p /etc/slacky-update /var/cache/slacky-update 2>/dev/null || true
            sudo touch /etc/slacky-update/r8125.disabled 2>/dev/null || true
            return 1
        fi
    fi
    return 1
}

get_cachyos_repo_url() {
    local tier="$1"
    case "${tier}" in
        znver4)
            echo "https://mirror.cachyos.org/repo/x86_64_v4/cachyos-znver4/"
            ;;
        v4)
            echo "https://mirror.cachyos.org/repo/x86_64_v4/cachyos-v4/"
            ;;
        v3)
            echo "https://mirror.cachyos.org/repo/x86_64_v3/cachyos-v3/"
            ;;
        *)
            echo "https://mirror.cachyos.org/repo/x86_64/cachyos/"
            ;;
    esac
}

is_cachyos_kernel_installed() {
    if uname -r | grep -qiE "cachyos|zen|arch"; then
        echo "true"
        return 0
    fi
    if find /lib/modules /boot -maxdepth 2 \( -name "*cachyos*" -o -name "*zen*" -o -name "*arch*" -o -name "vmlinuz-linux*" \) 2>/dev/null | grep -qE "cachyos|zen|arch|vmlinuz-linux"; then
        echo "true"
        return 0
    fi
    echo "false"
}

get_installed_cachyos_flavors() {
    python3 -c "
import os, re

def get_flavor(k_str):
    if '-cachyos-bore-lto' in k_str or '-cachyos-lto' in k_str:
        return 'lto'
    elif '-cachyos-rt-bore' in k_str or '-cachyos-rt' in k_str:
        return 'rt-bore'
    elif '-cachyos-bore' in k_str:
        return 'bore'
    elif '-cachyos-eevdf' in k_str:
        return 'eevdf'
    elif '-cachyos-bmq' in k_str:
        return 'bmq'
    elif '-cachyos-deckify' in k_str:
        return 'deckify'
    elif '-cachyos-rc' in k_str:
        return 'rc'
    elif '-cachyos-lts' in k_str:
        return 'lts'
    elif '-cachyos' in k_str:
        return 'standard'
    elif '-zen' in k_str or k_str in ('vmlinuz-linux-zen', 'linux-zen'):
        return 'zen'
    elif '-arch' in k_str or k_str in ('vmlinuz-linux', 'linux'):
        return 'arch'
    return None

def is_custom_k(name):
    return ('cachyos' in name or '-zen' in name or '-arch' in name or name in ('vmlinuz-linux', 'vmlinuz-linux-zen', 'linux', 'linux-zen'))

flavors = set()

if os.path.exists('/lib/modules'):
    try:
        for d in os.listdir('/lib/modules'):
            if is_custom_k(d):
                flv = get_flavor(d)
                if flv: flavors.add(flv)
    except Exception:
        pass

if os.path.exists('/boot'):
    try:
        for f in os.listdir('/boot'):
            if is_custom_k(f) and f.startswith('vmlinuz-') and not os.path.islink(os.path.join('/boot', f)):
                flv = get_flavor(f)
                if flv: flavors.add(flv)
    except Exception:
        pass

if os.path.exists('/var/log/packages'):
    try:
        for p in os.listdir('/var/log/packages'):
            if 'linux-cachyos' in p or p.startswith('linux-zen-') or p.startswith('linux-'):
                flv = get_flavor(p)
                if flv: flavors.add(flv)
    except Exception:
        pass

uname_r = os.uname().release
if is_custom_k(uname_r):
    flv = get_flavor(uname_r)
    if flv: flavors.add(flv)

print(' '.join(sorted(list(flavors))))
" 2>/dev/null || echo ""
}

get_installed_cachyos_flavor_version() {
    local flavor="$1"
    python3 -c "
import os, re

def get_flavor(k_str):
    if '-cachyos-bore-lto' in k_str or '-cachyos-lto' in k_str:
        return 'lto'
    elif '-cachyos-rt-bore' in k_str or '-cachyos-rt' in k_str:
        return 'rt-bore'
    elif '-cachyos-bore' in k_str:
        return 'bore'
    elif '-cachyos-eevdf' in k_str:
        return 'eevdf'
    elif '-cachyos-bmq' in k_str:
        return 'bmq'
    elif '-cachyos-deckify' in k_str:
        return 'deckify'
    elif '-cachyos-rc' in k_str:
        return 'rc'
    elif '-cachyos-lts' in k_str:
        return 'lts'
    elif '-cachyos' in k_str:
        return 'standard'
    elif '-zen' in k_str or k_str in ('vmlinuz-linux-zen', 'linux-zen'):
        return 'zen'
    elif '-arch' in k_str or k_str in ('vmlinuz-linux', 'linux'):
        return 'arch'
    return None

def parse_ver(v_str):
    nums = [int(x) for x in re.findall(r'\d+', v_str)]
    return nums if nums else [0]

def clean_ver(v_str):
    c = v_str.replace('vmlinuz-', '')
    c = re.sub(r'-(cachyos|zen|arch).*$', '', c)
    return c

cachy_vers = set()
target_flv = '$flavor'

if os.path.exists('/lib/modules'):
    try:
        for d in os.listdir('/lib/modules'):
            if get_flavor(d) == target_flv:
                v = clean_ver(d)
                if v: cachy_vers.add(v)
    except Exception:
        pass

if os.path.exists('/boot'):
    try:
        for f in os.listdir('/boot'):
            if f.startswith('vmlinuz-') and not os.path.islink(os.path.join('/boot', f)):
                if get_flavor(f) == target_flv:
                    v = clean_ver(f)
                    if v: cachy_vers.add(v)
    except Exception:
        pass

uname_r = os.uname().release
if get_flavor(uname_r) == target_flv:
    cachy_vers.add(clean_ver(uname_r))

if cachy_vers:
    sorted_vers = sorted(list(cachy_vers), key=parse_ver, reverse=True)
    print(sorted_vers[0])
else:
    print('NONE')
" 2>/dev/null || echo "NONE"
}

get_newest_installed_cachyos_version() {
    python3 -c "
import os, re

def parse_ver(v_str):
    nums = [int(x) for x in re.findall(r'\d+', v_str)]
    return nums if nums else [0]

def clean_ver(v_str):
    c = v_str.replace('vmlinuz-', '')
    c = re.sub(r'-(cachyos|zen|arch).*$', '', c)
    return c

def is_custom_k(name):
    return ('cachyos' in name or '-zen' in name or '-arch' in name or name in ('vmlinuz-linux', 'vmlinuz-linux-zen', 'linux', 'linux-zen'))

cachy_vers = set()

if os.path.exists('/lib/modules'):
    try:
        for d in os.listdir('/lib/modules'):
            if is_custom_k(d):
                v = clean_ver(d)
                if v:
                    cachy_vers.add(v)
    except Exception:
        pass

if os.path.exists('/boot'):
    try:
        for f in os.listdir('/boot'):
            if is_custom_k(f) and f.startswith('vmlinuz-') and not os.path.islink(os.path.join('/boot', f)):
                v = clean_ver(f)
                if v:
                    cachy_vers.add(v)
    except Exception:
        pass

uname_r = os.uname().release
if is_custom_k(uname_r):
    cachy_vers.add(clean_ver(uname_r))

if cachy_vers:
    sorted_vers = sorted(list(cachy_vers), key=parse_ver, reverse=True)
    print(sorted_vers[0])
else:
    print('NONE')
" 2>/dev/null || echo "NONE"
}


check_cachyos_upstream_flavor() {
    local flavor="${1:-standard}"
    local tier
    tier=$(detect_cpu_tier)
    local repo_urls=()

    if [ "${flavor}" = "zen" ]; then
        repo_urls=("https://geo.mirror.pkgbuild.com/extra/os/x86_64/")
    elif [ "${flavor}" = "arch" ]; then
        repo_urls=("https://geo.mirror.pkgbuild.com/core/os/x86_64/")
    else
        case "${tier}" in
            znver4)
                repo_urls=("https://mirror.cachyos.org/repo/x86_64_v4/cachyos-znver4/" "https://mirror.cachyos.org/repo/x86_64_v4/cachyos-v4/")
                ;;
            v4)
                repo_urls=("https://mirror.cachyos.org/repo/x86_64_v4/cachyos-v4/")
                ;;
            v3)
                repo_urls=("https://mirror.cachyos.org/repo/x86_64_v3/cachyos-v3/" "https://mirror.cachyos.org/repo/x86_64/cachyos/")
                ;;
            *)
                repo_urls=("https://mirror.cachyos.org/repo/x86_64/cachyos/")
                ;;
        esac
    fi

    local k_prefix="linux-cachyos"
    local h_prefix="linux-cachyos-headers"
    if [ "${flavor}" = "bore" ]; then
        k_prefix="linux-cachyos-bore"
        h_prefix="linux-cachyos-bore-headers"
    elif [ "${flavor}" = "lto" ]; then
        k_prefix="linux-cachyos-bore-lto"
        h_prefix="linux-cachyos-bore-lto-headers"
    elif [ "${flavor}" = "eevdf" ]; then
        k_prefix="linux-cachyos-eevdf"
        h_prefix="linux-cachyos-eevdf-headers"
    elif [ "${flavor}" = "bmq" ]; then
        k_prefix="linux-cachyos-bmq"
        h_prefix="linux-cachyos-bmq-headers"
    elif [ "${flavor}" = "deckify" ]; then
        k_prefix="linux-cachyos-deckify"
        h_prefix="linux-cachyos-deckify-headers"
    elif [ "${flavor}" = "rt-bore" ]; then
        k_prefix="linux-cachyos-rt-bore"
        h_prefix="linux-cachyos-rt-bore-headers"
    elif [ "${flavor}" = "rc" ]; then
        k_prefix="linux-cachyos-rc"
        h_prefix="linux-cachyos-rc-headers"
    elif [ "${flavor}" = "lts" ]; then
        k_prefix="linux-cachyos-lts"
        h_prefix="linux-cachyos-lts-headers"
    elif [ "${flavor}" = "zen" ]; then
        k_prefix="linux-zen"
        h_prefix="linux-zen-headers"
    elif [ "${flavor}" = "arch" ]; then
        k_prefix="linux"
        h_prefix="linux-headers"
    fi

    for repo_url in "${repo_urls[@]}"; do
        local result
        result=$(python3 - "${repo_url}" "${k_prefix}" "${h_prefix}" << 'PYKERNELFETCH'
import re, sys, os, time, urllib.request, hashlib

repo_url = sys.argv[1]
k_pref = sys.argv[2]
h_pref = sys.argv[3]
nv_pref = k_pref + '-nvidia-open'
r8125_pref = k_pref + '-r8125'

def get_cache_dir():
    for d in ['/var/cache/slacky-update', os.path.expanduser('~/.cache/slacky-update'), '/tmp/slacky-update-cache']:
        try:
            os.makedirs(d, exist_ok=True)
            test_f = os.path.join(d, '.write_test')
            with open(test_f, 'w') as f: f.write('1')
            os.remove(test_f)
            return d
        except Exception:
            continue
    return '/tmp'

cache_dir = get_cache_dir()

def fetch_url_cached(url, cdir, ttl=1800):
    url_hash = hashlib.sha256(url.encode('utf-8')).hexdigest()[:16]
    cache_file = os.path.join(cdir, f'repo_idx_{url_hash}.html')
    now = time.time()
    if os.path.exists(cache_file):
        try:
            mtime = os.path.getmtime(cache_file)
            if (now - mtime) < ttl:
                with open(cache_file, 'r', encoding='utf-8', errors='ignore') as f:
                    return f.read()
        except Exception:
            pass
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64)'})
        with urllib.request.urlopen(req, timeout=5) as resp:
            content = resp.read().decode('utf-8', errors='ignore')
            try:
                with open(cache_file, 'w', encoding='utf-8', errors='ignore') as f:
                    f.write(content)
            except Exception:
                pass
            return content
    except Exception:
        return ''

html = fetch_url_cached(repo_url, cache_dir)
if not html:
    print('NONE NONE NONE NONE NONE')
    sys.exit(0)

k_matches = re.findall(r'href=[\'\"]?(' + re.escape(k_pref) + r'-([0-9]+\.[0-9]+[a-zA-Z0-9\._]*-[0-9]+)[^\'\">]*\.pkg\.tar\.zst)', html)
h_matches = re.findall(r'href=[\'\"]?(' + re.escape(h_pref) + r'-([0-9]+\.[0-9]+[a-zA-Z0-9\._]*-[0-9]+)[^\'\">]*\.pkg\.tar\.zst)', html)
nv_matches = re.findall(r'href=[\'\"]?(' + re.escape(nv_pref) + r'-([0-9]+\.[0-9]+[a-zA-Z0-9\._]*-[0-9]+)[^\'\">]*\.pkg\.tar\.zst)', html)
r8125_matches = re.findall(r'href=[\'\"]?(' + re.escape(r8125_pref) + r'-([0-9]+\.[0-9]+[a-zA-Z0-9\._]*-[0-9]+)[^\'\">]*\.pkg\.tar\.zst)', html)

if not k_matches or not h_matches:
    print('NONE NONE NONE NONE NONE')
    sys.exit(0)

def parse_ver_key(v_str):
    return [int(x) for x in re.findall(r'\d+', v_str)]

available_versions = sorted(list(set(m[1] for m in k_matches)), key=parse_ver_key, reverse=True)
latest_ver = available_versions[0]

k_pkg = next(m[0] for m in k_matches if m[1] == latest_ver)
h_pkg = next(m[0] for m in h_matches if m[1] == latest_ver)

nv_url = 'NONE'
if nv_matches:
    try:
        nv_pkg = next(m[0] for m in nv_matches if m[1] == latest_ver)
        nv_url = f'{repo_url}{nv_pkg}'
    except StopIteration:
        pass

r8125_url = 'NONE'
if r8125_matches:
    try:
        r8125_pkg = next(m[0] for m in r8125_matches if m[1] == latest_ver)
        r8125_url = f'{repo_url}{r8125_pkg}'
    except StopIteration:
        pass

print(f'{latest_ver} {repo_url}{k_pkg} {repo_url}{h_pkg} {nv_url} {r8125_url}')
PYKERNELFETCH
)

        if [ "${result}" != "NONE NONE NONE NONE NONE" ] && [ -n "${result}" ]; then
            echo "${result}"
            return 0
        fi
    done

    echo "NONE NONE NONE NONE NONE"
}

check_latest_cachyos_upstream() {
    check_cachyos_upstream_flavor "standard"
}

deploy_cachyos_kernel_flavor() {
    local flavor="$1"
    validate_privileges
    probe_gpu_hardware

    log_info "Fetching latest ${flavor} CachyOS kernel metadata from upstream..."
    local latest_ver k_url h_url nv_url r8125_url
    read -r latest_ver k_url h_url nv_url r8125_url <<< "$(check_cachyos_upstream_flavor "${flavor}" || echo "NONE NONE NONE NONE NONE")"

    if [ "${latest_ver}" = "NONE" ] || [ -z "${k_url}" ]; then
        log_error "Could not resolve CachyOS ${flavor} kernel from mirrors."
        return 1
    fi

    if [ "${flavor}" = "rc" ] && [ "${HAS_NVIDIA}" = "true" ]; then
        local gpu_arch="MODERN"
        if command -v detect_nvidia_gpu >/dev/null 2>&1; then
            gpu_arch=$(detect_nvidia_gpu)
        fi
        if [ "${gpu_arch}" = "PASCAL" ] || [ "${gpu_arch}" = "LEGACY" ]; then
            log_error "Safety Guardrail: CachyOS Release Candidate (RC) kernels require minimum RTX 20-series (Turing) with precompiled open drivers and do not support Pascal or DKMS."
            return 1
        fi
        if [ "${nv_url}" = "NONE" ] || [ -z "${nv_url}" ]; then
            log_error "Safety Guardrail: Matching precompiled NVIDIA Open module for CachyOS RC (${latest_ver}) is not published on mirrors. Aborting deployment to prevent graphical crash."
            return 1
        fi
    fi

    local target_r8125="NONE"
    if [ "${r8125_url}" != "NONE" ] && [ -n "${r8125_url}" ]; then
        if is_r8125_wanted "${latest_ver}"; then
            target_r8125="${r8125_url}"
        fi
    fi

    log_info "Deploying CachyOS ${flavor} kernel (v${latest_ver})..."
    deploy_cachyos_kernel_packages "${latest_ver}" "${k_url}" "${h_url}" "${flavor}" "${nv_url}" "${target_r8125}"
    if command -v purge_old_cachyos_kernels >/dev/null 2>&1; then
        purge_old_cachyos_kernels
    fi

    # Smart Prompt: Check if system is eligible for pure CachyOS transition
    prompt_stock_kernel_removal_if_eligible "${flavor}"
}

update_cachyos_kernels() {
    validate_privileges
    local installed_flavors
    installed_flavors=$(get_installed_cachyos_flavors 2>/dev/null || echo "")
    if [ -z "${installed_flavors}" ]; then
        log_info "No CachyOS kernels currently installed."
        return 0
    fi

    log_info "Scanning for upstream updates across installed CachyOS flavors..."
    local flavors_to_update=()

    for flv in ${installed_flavors}; do
        local cur_ver latest_ver k_url h_url nv_url r8125_url
        cur_ver=$(get_installed_cachyos_flavor_version "${flv}" 2>/dev/null || echo "NONE")
        read -r latest_ver k_url h_url nv_url r8125_url <<< "$(check_cachyos_upstream_flavor "${flv}" || echo "NONE NONE NONE NONE NONE")"
        if [ "${latest_ver}" != "NONE" ] && [ -n "${latest_ver}" ] && [ "${cur_ver}" != "NONE" ]; then
            if [ "$(compare_versions_strictly_greater "${latest_ver}" "${cur_ver}")" = "true" ]; then
                echo -e "\n${GREEN}${BOLD}Upgrade available for ${flv}: v${cur_ver} -> v${latest_ver}${RESET}"
                flavors_to_update+=("${flv}")
            else
                log_info "Flavor '${flv}' (v${cur_ver}) is up to date with upstream."
            fi
        fi
    done

    if [ ${#flavors_to_update[@]} -eq 0 ]; then
        log_info "All installed CachyOS kernels are already up to date."
        return 0
    fi

    # Pre-fetch all kernel, headers, nvidia and r8125 module packages for all target flavors in a single parallel batch
    local staging_dir
    staging_dir=$(get_user_staging_dir)
    mkdir -p "${staging_dir}"

    local dl_items=()
    for flv in "${flavors_to_update[@]}"; do
        local latest_ver k_url h_url nv_url r8125_url
        read -r latest_ver k_url h_url nv_url r8125_url <<< "$(check_cachyos_upstream_flavor "${flv}" || echo "NONE NONE NONE NONE NONE")"
        if [ "${k_url}" != "NONE" ] && [ -n "${k_url}" ]; then
            local kf="${staging_dir}/$(basename "${k_url}")"
            dl_items+=("${k_url}|${kf}|${k_url}.sig|${kf}.sig")
        fi
        if [ "${h_url}" != "NONE" ] && [ -n "${h_url}" ]; then
            local hf="${staging_dir}/$(basename "${h_url}")"
            dl_items+=("${h_url}|${hf}|${h_url}.sig|${hf}.sig")
        fi
        if [ "${nv_url}" != "NONE" ] && [ -n "${nv_url}" ]; then
            local nvf="${staging_dir}/$(basename "${nv_url}")"
            dl_items+=("${nv_url}|${nvf}|${nv_url}.sig|${nvf}.sig")
        fi
        if [ "${r8125_url}" != "NONE" ] && [ -n "${r8125_url}" ]; then
            if is_r8125_wanted "${latest_ver}"; then
                local rf="${staging_dir}/$(basename "${r8125_url}")"
                dl_items+=("${r8125_url}|${rf}|${r8125_url}.sig|${rf}.sig")
            fi
        fi
    done

    if [ ${#dl_items[@]} -gt 0 ]; then
        echo ""
        log_info "⚡ Starting Unified Parallel Batch Download (${#flavors_to_update[@]} kernel flavors • ${#dl_items[@]} files)..."
        download_parallel_pacman "CachyOS Kernel Suite (${#flavors_to_update[@]} flavors)" "${dl_items[@]}" || true
    fi

    for flv in "${flavors_to_update[@]}"; do
        deploy_cachyos_kernel_flavor "${flv}"
    done

    log_success "CachyOS kernel upgrade completed."
}

remove_stock_slackware_kernels() {
    validate_privileges

    # HARD BOOT-VALIDATION GUARDRAIL:
    # Ensure at least one verified, bootable CachyOS vmlinuz (>5MB) and matching initramfs/initrd (>5MB) exist before removing stock kernels
    local validation_res
    validation_res=$(sudo python3 -c "
import os

found_kernel = ''
valid = False
try:
    for fname in os.listdir('/boot'):
        if 'cachyos' in fname and fname.startswith('vmlinuz-') and not os.path.islink(os.path.join('/boot', fname)):
            kpath = os.path.join('/boot', fname)
            if os.path.getsize(kpath) > 5000000:
                ksuffix = fname.replace('vmlinuz-', '')
                for icand in [f'/boot/initramfs-{ksuffix}.img', f'/boot/initrd-{ksuffix}.img', f'/boot/initramfs-{ksuffix}', f'/boot/initrd.gz']:
                    if os.path.exists(icand) and os.path.getsize(icand) > 5000000:
                        valid = True
                        found_kernel = fname
                        break
                if valid:
                    break
except Exception:
    pass

print(f'{1 if valid else 0}|{found_kernel}')
" 2>/dev/null || echo "0|")

    local valid_cachy_boot=0
    local found_cachy_kernel=""
    IFS='|' read -r valid_cachy_boot found_cachy_kernel <<< "${validation_res}"

    if [ "${valid_cachy_boot:-0}" -ne 1 ]; then
        log_error "Safety Guardrail: No verified, bootable CachyOS kernel + initramfs (>5MB) found in /boot!"
        log_error "Stock Slackware kernels must be retained to prevent an unbootable system."
        return 1
    fi

    log_info "Boot validation passed (Verified bootable kernel: ${found_cachy_kernel})."
    log_info "Transitioning system to Pure CachyOS Mode..."

    local backup_dir="/var/cache/slacky-update/backup/kernel"
    sudo mkdir -p "${backup_dir}"

    local stock_pkgs=("kernel-generic" "kernel-huge" "kernel-modules" "kernel-source")
    for pkg in "${stock_pkgs[@]}"; do
        local installed
        installed=$(ls /var/log/packages/${pkg}-* 2>/dev/null || true)
        if [ -n "${installed}" ]; then
            for p in ${installed}; do
                local base_p
                base_p=$(basename "${p}")
                # Save log package metadata to backup directory for offline recovery tracking
                sudo cp -f "${p}" "${backup_dir}/${base_p}" 2>/dev/null || true
                log_info "Removing stock Slackware package: ${base_p}..."
                sudo "${PKG_REMOVE_CMD}" "${base_p}" 2>/dev/null || true
            done
        fi
    done

    # Add to blacklist if not already present
    local blacklist_file="/etc/slackpkg/blacklist"
    if [ -f "${blacklist_file}" ]; then
        if ! grep -q "Slacky-Update Pure CachyOS Mode" "${blacklist_file}"; then
            echo -e "\n# [Slacky-Update Pure CachyOS Mode]\nkernel-generic*\nkernel-huge*\nkernel-modules*\nkernel-source*" | sudo tee -a "${blacklist_file}" >/dev/null
            log_info "Stock kernels blacklisted in ${blacklist_file} (kernel-headers preserved)."
        fi
    fi

    log_success "System is now running on Pure CachyOS kernels!"
    sync_bootloader_configuration "$(uname -r)"
}

restore_stock_slackware_kernels() {
    validate_privileges

    echo ""
    echo -e "${CYAN}============================================================${RESET}"
    echo -e "${YELLOW}${BOLD}$(_ CACHY_PICKER_RESTORE_STOCK | sed -E 's/^[0-9]+\.\s*//')${RESET}"
    echo -e "${CYAN}============================================================${RESET}"
    echo -e "${YELLOW}${BOLD}$(_ PROMPT_CONFIRM_RESTORE_STOCK)${RESET}"
    read -r confirm_restore
    confirm_restore=${confirm_restore:-N}
    if [[ ! "${confirm_restore}" =~ ^[YyJjSsOo]$ ]]; then
        log_info "Operation cancelled by user."
        return 0
    fi

    log_info "Restoring stock Slackware kernel infrastructure..."
    local blacklist_file="/etc/slackpkg/blacklist"
    if [ -f "${blacklist_file}" ]; then
        sudo sed -i '/kernel-generic\*/d; /kernel-huge\*/d; /kernel-modules\*/d; /kernel-source\*/d; /\[Slacky-Update Pure CachyOS Mode\]/d' "${blacklist_file}" 2>/dev/null || true
        log_info "Un-blacklisted stock kernels in ${blacklist_file}."
    fi

    local slackpkg_bin
    slackpkg_bin=$(command -v slackpkg 2>/dev/null || echo "/usr/sbin/slackpkg")
    if [ -x "${slackpkg_bin}" ]; then
        log_info "Updating slackpkg repository index..."
        sudo "${slackpkg_bin}" update || true

        log_info "Installing official Slackware kernel-generic and kernel-modules..."
        sudo "${slackpkg_bin}" -batch=on -default_answer=y install kernel-generic kernel-modules || true
    fi

    local stock_kver=""
    for mod_d in /lib/modules/*; do
        [ -d "${mod_d}" ] || continue
        local bname
        bname=$(basename "${mod_d}")
        if [[ ! "${bname}" =~ cachyos ]]; then
            stock_kver="${bname}"
        fi
    done

    if [ -n "${stock_kver}" ]; then
        log_info "Regenerating initrd for stock kernel: ${stock_kver}..."
        generate_kernel_initramfs "${stock_kver}"
        sync_bootloader_configuration "${stock_kver}"
    else
        sync_bootloader_configuration "$(uname -r)"
    fi

    log_success "Official Slackware stock kernels successfully restored and integrated!"
}

prompt_stock_kernel_removal_if_eligible() {
    local just_deployed_flavor="$1"
    validate_privileges

    local has_stock=0
    if ls /var/log/packages/kernel-generic-* /var/log/packages/kernel-modules-* 2>/dev/null | grep -q 'kernel-'; then
        has_stock=1
    fi
    [ "${has_stock}" -eq 1 ] || return 0

    local installed_flavors
    installed_flavors=$(get_installed_cachyos_flavors)

    local has_lts=0
    local has_perf=0
    for flv in ${installed_flavors}; do
        [ "${flv}" = "lts" ] && has_lts=1
        [[ "${flv}" =~ ^(bore|lto|standard|rc)$ ]] && has_perf=1
    done

    # Guardrail: Must have BOTH LTS and a Performance/RC kernel to offer stock removal
    if [ "${has_lts}" -eq 1 ] && [ "${has_perf}" -eq 1 ]; then
        echo ""
        local reply_remove="N"
        if [ "${just_deployed_flavor}" = "lts" ]; then
            echo -e "${YELLOW}${BOLD}$(_ PROMPT_REMOVE_STOCK_MULTIPLE)${RESET}"
            read -r reply_remove
        else
            echo -e "${YELLOW}${BOLD}$(_ PROMPT_REMOVE_STOCK_DUAL)${RESET}"
            read -r reply_remove
        fi
        reply_remove=${reply_remove:-N}
        if [[ "${reply_remove}" =~ ^[YyJjSsOo]$ ]]; then
            remove_stock_slackware_kernels
        fi
    fi
}

manage_kernel_removal_interactive() {
    validate_privileges

    while true; do
        local kernels_raw
        kernels_raw=$(sudo python3 -c "
import os

def get_dir_size(path):
    if not os.path.exists(path):
        return 0
    if os.path.isfile(path) and not os.path.islink(path):
        return os.path.getsize(path)
    total = 0
    for root, dirs, files in os.walk(path):
        for f in files:
            fp = os.path.join(root, f)
            if not os.path.islink(fp) and os.path.exists(fp):
                try:
                    total += os.path.getsize(fp)
                except Exception:
                    pass
    return total

def format_sz(bytes_sz):
    mb = bytes_sz / (1024 * 1024)
    return f'{mb:.0f} MB' if mb >= 1 else f'{bytes_sz / 1024:.0f} KB'

active = os.uname().release
kernels = {}

if os.path.exists('/boot'):
    try:
        for f in os.listdir('/boot'):
            if f.startswith('vmlinuz-') and not os.path.islink(os.path.join('/boot', f)):
                k = f.replace('vmlinuz-', '')
                if k and k not in ('generic', 'huge'):
                    kernels[k] = {'type': 'cachyos' if 'cachyos' in k else 'stock'}
    except Exception:
        pass

for mdir in ('/lib/modules', '/usr/lib/modules'):
    if os.path.exists(mdir):
        for d in os.listdir(mdir):
            if os.path.isdir(os.path.join(mdir, d)) and not os.path.islink(os.path.join(mdir, d)):
                if d not in kernels:
                    kernels[d] = {'type': 'cachyos' if 'cachyos' in d else 'stock'}

for k, data in sorted(kernels.items()):
    sz = 0
    sz += get_dir_size(f'/boot/vmlinuz-{k}')
    sz += get_dir_size(f'/boot/initramfs-{k}.img')
    sz += get_dir_size(f'/boot/initrd-{k}.img')
    sz += get_dir_size(f'/lib/modules/{k}')
    sz += get_dir_size(f'/usr/lib/modules/{k}')
    sz += get_dir_size(f'/usr/src/linux-headers-{k}')
    
    k_type = data['type']
    is_active = (k == active)
    print(f'{k}|{k_type}|{format_sz(sz)}|{1 if is_active else 0}')
" 2>/dev/null || true)

        if [ -z "${kernels_raw}" ]; then
            log_info "No installed kernels detected."
            return 0
        fi

        local k_list=()
        local k_types=()
        local k_sizes=()
        local k_active=()
        local idx=0

        echo ""
        echo -e "${CYAN}============================================================${RESET}"
        echo -e "${YELLOW}${BOLD}$(_ KERNEL_REMOVAL_TITLE)${RESET}"
        echo -e "${CYAN}============================================================${RESET}"

        while IFS='|' read -r k_name k_type k_sz k_act; do
            [ -n "${k_name}" ] || continue
            idx=$((idx + 1))
            k_list+=("${k_name}")
            k_types+=("${k_type}")
            k_sizes+=("${k_sz}")
            k_active+=("${k_act}")

            local status_badge=""
            if [ "${k_act}" -eq 1 ]; then
                status_badge="${GREEN}${BOLD}[ACTIVE - CANNOT REMOVE]${RESET}"
            elif [ "${k_type}" = "stock" ]; then
                status_badge="${BLUE}[STOCK]${RESET}"
            else
                status_badge="${CYAN}[CACHY]${RESET}"
            fi

            echo -e "  \033[1;33m${idx}.\033[0m ${k_name} (${k_sizes[$((idx-1))]}) ${status_badge}"
        done <<< "${kernels_raw}"

        local exit_idx=$((idx + 1))
        echo -e "  \033[1;33m${exit_idx}.\033[0m $(_ CACHY_PICKER_EXIT | sed -E 's/^[0-9]+\.\s*//')"
        echo ""
        echo -n "$(_ SELECT_OPERATION_RANGE range="1-${exit_idx}") "
        local sel
        read -r sel || sel="${exit_idx}"

        if [ "${sel}" = "${exit_idx}" ] || [ -z "${sel}" ]; then
            return 0
        fi

        if ! [[ "${sel}" =~ ^[0-9]+$ ]] || [ "${sel}" -lt 1 ] || [ "${sel}" -gt "${idx}" ]; then
            log_warn "Invalid selection."
            continue
        fi

        local chosen_k="${k_list[$((sel-1))]}"
        local chosen_type="${k_types[$((sel-1))]}"
        local chosen_is_active="${k_active[$((sel-1))]}"

        if [ "${chosen_is_active}" -eq 1 ]; then
            echo ""
            log_error "Safety Guardrail: Cannot remove the active booted kernel (${chosen_k})!"
            echo -e "${YELLOW}Please reboot your system into another kernel before removing this version.${RESET}"
            echo ""
            read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
            continue
        fi

        if [ "${chosen_type}" = "stock" ]; then
            # Stock Slackware kernel guardrail: CachyOS LTS must be installed on the system!
            local has_cachy_lts=0
            if get_installed_cachyos_flavors | grep -qw "lts"; then
                has_cachy_lts=1
            fi

            if [ "${has_cachy_lts}" -eq 0 ]; then
                echo ""
                log_error "Safety Guardrail: Slackware stock kernels cannot be removed unless CachyOS LTS is installed as a fallback!"
                echo -e "${YELLOW}Install 'linux-cachyos-lts' first before removing official stock Slackware kernels.${RESET}"
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                continue
            fi

            echo ""
            echo -e "${YELLOW}${BOLD}Are you sure you want to remove Slackware stock kernel packages?${RESET}"
            echo -e "${CYAN}(Note: kernel-headers will be safely preserved for build compatibility)${RESET}"
            read -r -p "Confirm removal [y/N]: " conf_stock
            conf_stock=${conf_stock:-N}
            if [[ "${conf_stock}" =~ ^[YyJjSsOo]$ ]]; then
                remove_stock_slackware_kernels
            fi
            echo ""
            read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
            continue
        fi

        # CachyOS kernel removal
        local has_stock_now=0
        if ls /var/log/packages/kernel-generic-* /var/log/packages/kernel-modules-* 2>/dev/null | grep -q 'kernel-'; then
            has_stock_now=1
        fi

        local cur_cachy_flavors
        cur_cachy_flavors=$(get_installed_cachyos_flavors)
        local cachy_count
        cachy_count=$(echo "${cur_cachy_flavors}" | wc -w)

        if [ "${has_stock_now}" -eq 0 ] && [ "${cachy_count}" -le 1 ]; then
            echo ""
            log_warn "Notice: ${chosen_k} is the ONLY remaining fallback kernel on the system!"
            echo -e "${YELLOW}Removing this kernel will leave the system without a bootable fallback.${RESET}"
            read -r -p "Would you like to restore official Slackware stock kernels first? [Y/n]: " conf_restore_first
            conf_restore_first=${conf_restore_first:-Y}
            if [[ "${conf_restore_first}" =~ ^[YyJjSsOo]$ ]]; then
                restore_stock_slackware_kernels
                has_stock_now=1
            else
                echo -e "${RED}Proceeding without fallback kernel protection.${RESET}"
            fi
        fi

        echo ""
        echo -e "${YELLOW}${BOLD}Are you sure you want to completely remove kernel ${chosen_k}?${RESET}"
        read -r -p "Confirm removal [y/N]: " conf_k
        conf_k=${conf_k:-N}
        if [[ ! "${conf_k}" =~ ^[YyJjSsOo]$ ]]; then
            continue
        fi

        log_info "Purging kernel artifacts for: ${chosen_k}..."
        sudo rm -f "/boot/vmlinuz-${chosen_k}" 2>/dev/null || true
        sudo rm -f "/boot/initramfs-${chosen_k}.img"* 2>/dev/null || true
        sudo rm -f "/boot/initrd-${chosen_k}.img"* 2>/dev/null || true
        sudo rm -f "/boot/initrd-${chosen_k}.gz"* 2>/dev/null || true
        sudo rm -rf "/lib/modules/${chosen_k}" 2>/dev/null || true
        sudo rm -rf "/usr/lib/modules/${chosen_k}" 2>/dev/null || true
        sudo rm -rf "/usr/src/linux-headers-${chosen_k}" 2>/dev/null || true

        local dkms_bin
        dkms_bin=$(command -v dkms 2>/dev/null || echo "/usr/sbin/dkms")
        if [ -x "${dkms_bin}" ]; then
            sudo "${dkms_bin}" remove -k "${chosen_k}" --all >/dev/null 2>&1 || true
        fi

        log_success "Kernel ${chosen_k} removed successfully."

        # Check if no CachyOS kernels remain
        local remaining_cachy_now
        remaining_cachy_now=$(get_installed_cachyos_flavors)

        if [ -z "${remaining_cachy_now}" ] && [ "${has_stock_now}" -eq 0 ]; then
            log_warn "No kernels remain! Automatically restoring official Slackware stock kernel..."
            restore_stock_slackware_kernels
            if [ "${HAS_NVIDIA}" = "true" ] && command -v rollback_cachyos_to_slackware_nvidia >/dev/null 2>&1; then
                log_info "Migrating NVIDIA graphics driver to native Slackware standalone driver..."
                rollback_cachyos_to_slackware_nvidia
            fi
        elif [ -z "${remaining_cachy_now}" ] && [ "${has_stock_now}" -eq 1 ]; then
            if [ "${HAS_NVIDIA}" = "true" ] && command -v rollback_cachyos_to_slackware_nvidia >/dev/null 2>&1; then
                log_info "No CachyOS kernels remain. Migrating NVIDIA graphics driver to native Slackware standalone driver..."
                rollback_cachyos_to_slackware_nvidia
            fi
        fi

        sync_bootloader_configuration "$(uname -r)"
        echo ""
        read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
    done
}

cachyos_kernel_picker_interactive() {
    while true; do
        local st_ver bo_ver lto_ver eevdf_ver bmq_ver deck_ver rtbore_ver rc_ver lts_ver zen_ver arch_ver
        st_ver=$(get_installed_cachyos_flavor_version "standard")
        bo_ver=$(get_installed_cachyos_flavor_version "bore")
        lto_ver=$(get_installed_cachyos_flavor_version "lto")
        eevdf_ver=$(get_installed_cachyos_flavor_version "eevdf")
        bmq_ver=$(get_installed_cachyos_flavor_version "bmq")
        deck_ver=$(get_installed_cachyos_flavor_version "deckify")
        rtbore_ver=$(get_installed_cachyos_flavor_version "rt-bore")
        rc_ver=$(get_installed_cachyos_flavor_version "rc")
        lts_ver=$(get_installed_cachyos_flavor_version "lts")
        zen_ver=$(get_installed_cachyos_flavor_version "zen")
        arch_ver=$(get_installed_cachyos_flavor_version "arch")

        probe_gpu_hardware
        local gpu_arch="MODERN"
        if command -v detect_nvidia_gpu >/dev/null 2>&1; then
            gpu_arch=$(detect_nvidia_gpu)
        fi

        local not_inst="\033[0;36m[NOT INSTALLED]\033[0m"
        local st_tag="${not_inst}"
        local bo_tag="${not_inst}"
        local lto_tag="${not_inst}"
        local eevdf_tag="${not_inst}"
        local bmq_tag="${not_inst}"
        local deck_tag="${not_inst}"
        local rtbore_tag="${not_inst}"
        local rc_tag="${not_inst}"
        local lts_tag="${not_inst}"
        local zen_tag="${not_inst}"
        local arch_tag="${not_inst}"

        [ "${st_ver}" != "NONE" ] && st_tag="\033[1;32m[INSTALLED: ${st_ver}]\033[0m"
        [ "${bo_ver}" != "NONE" ] && bo_tag="\033[1;32m[INSTALLED: ${bo_ver}]\033[0m"
        [ "${lto_ver}" != "NONE" ] && lto_tag="\033[1;32m[INSTALLED: ${lto_ver}]\033[0m"
        [ "${eevdf_ver}" != "NONE" ] && eevdf_tag="\033[1;32m[INSTALLED: ${eevdf_ver}]\033[0m"
        [ "${bmq_ver}" != "NONE" ] && bmq_tag="\033[1;32m[INSTALLED: ${bmq_ver}]\033[0m"
        [ "${deck_ver}" != "NONE" ] && deck_tag="\033[1;32m[INSTALLED: ${deck_ver}]\033[0m"
        [ "${rtbore_ver}" != "NONE" ] && rtbore_tag="\033[1;32m[INSTALLED: ${rtbore_ver}]\033[0m"
        [ "${rc_ver}" != "NONE" ] && rc_tag="\033[1;32m[INSTALLED: ${rc_ver}]\033[0m"
        [ "${lts_ver}" != "NONE" ] && lts_tag="\033[1;32m[INSTALLED: ${lts_ver}]\033[0m"
        [ "${zen_ver}" != "NONE" ] && zen_tag="\033[1;32m[INSTALLED: ${zen_ver}]\033[0m"
        [ "${arch_ver}" != "NONE" ] && arch_tag="\033[1;32m[INSTALLED: ${arch_ver}]\033[0m"
        if [ "${HAS_NVIDIA}" = "true" ] && { [ "${gpu_arch}" = "PASCAL" ] || [ "${gpu_arch}" = "LEGACY" ]; }; then
            rc_tag="\033[1;31m[UNSUPPORTED ON PASCAL/LEGACY GPU]\033[0m"
        fi

        echo ""
        echo -e "${CYAN}============================================================${RESET}"
        echo -e "${YELLOW}${BOLD}$(_ CACHY_PICKER_TITLE)${RESET}"
        echo -e "${CYAN}============================================================${RESET}"
        echo -e "  1. \033[1;34mlinux-cachyos\033[0m ${st_tag}"
        echo -e "     $(_ CACHY_FLAVOR_STANDARD)"
        echo -e "  2. \033[1;34mlinux-cachyos-bore\033[0m ${bo_tag}"
        echo -e "     $(_ CACHY_FLAVOR_BORE)"
        echo -e "  3. \033[1;34mlinux-cachyos-bore-lto\033[0m ${lto_tag}"
        echo -e "     $(_ CACHY_FLAVOR_LTO)"
        echo -e "  4. \033[1;34mlinux-cachyos-eevdf\033[0m ${eevdf_tag}"
        echo -e "     $(_ CACHY_FLAVOR_EEVDF)"
        echo -e "  5. \033[1;34mlinux-cachyos-bmq\033[0m ${bmq_tag}"
        echo -e "     $(_ CACHY_FLAVOR_BMQ)"
        echo -e "  6. \033[1;34mlinux-cachyos-deckify\033[0m ${deck_tag}"
        echo -e "     $(_ CACHY_FLAVOR_DECKIFY)"
        echo -e "  7. \033[1;34mlinux-cachyos-rt-bore\033[0m ${rtbore_tag}"
        echo -e "     $(_ CACHY_FLAVOR_RT_BORE)"
        echo -e "  8. \033[1;34mlinux-cachyos-rc\033[0m ${rc_tag}"
        echo -e "     $(_ CACHY_FLAVOR_RC)"
        echo -e "  9. \033[1;34mlinux-cachyos-lts\033[0m ${lts_tag}"
        echo -e "     $(_ CACHY_FLAVOR_LTS)"
        echo -e " 10. \033[1;34mlinux-zen\033[0m ${zen_tag}"
        echo -e "     $(_ CACHY_FLAVOR_ZEN)"
        echo -e " 11. \033[1;34mlinux\033[0m ${arch_tag}"
        echo -e "     $(_ CACHY_FLAVOR_ARCH)"
        echo -e " 12. $(_ CACHY_PICKER_EXIT | sed -E 's/^[0-9]+\.\s*//')"
        echo ""
        echo -n "$(_ SELECT_OPERATION_RANGE range="1-12") "
        local pchoice
        read -r pchoice || pchoice="12"

        case "${pchoice}" in
            1)
                echo ""
                deploy_cachyos_kernel_flavor "standard"
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            2)
                echo ""
                deploy_cachyos_kernel_flavor "bore"
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            3)
                echo ""
                deploy_cachyos_kernel_flavor "lto"
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            4)
                echo ""
                deploy_cachyos_kernel_flavor "eevdf"
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            5)
                echo ""
                deploy_cachyos_kernel_flavor "bmq"
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            6)
                echo ""
                deploy_cachyos_kernel_flavor "deckify"
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            7)
                echo ""
                deploy_cachyos_kernel_flavor "rt-bore"
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            8)
                echo ""
                if [ "${HAS_NVIDIA}" = "true" ] && { [ "${gpu_arch}" = "PASCAL" ] || [ "${gpu_arch}" = "LEGACY" ]; }; then
                    log_error "Safety Guardrail: CachyOS Release Candidate (RC) kernels require minimum RTX 20-series (Turing) with precompiled open drivers and do not support Pascal or DKMS."
                else
                    deploy_cachyos_kernel_flavor "rc"
                fi
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            9)
                echo ""
                deploy_cachyos_kernel_flavor "lts"
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            10)
                echo ""
                deploy_cachyos_kernel_flavor "zen"
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            11)
                echo ""
                deploy_cachyos_kernel_flavor "arch"
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            12)
                return 0
                ;;
            *)
                echo -e "\n${YELLOW}$(_ INVALID_SELECTION)${RESET}"
                sleep 1
                ;;
        esac
    done
}

manage_system_kernels_interactive() {
    while true; do
        echo ""
        echo -e "${CYAN}============================================================${RESET}"
        echo -e "${YELLOW}${BOLD}$(_ KERNEL_MANAGE_SYSTEM_TITLE)${RESET}"
        echo -e "${CYAN}============================================================${RESET}"
        echo -e "  1. $(_ KERNEL_MANAGE_OPTION_REMOVE | sed -E 's/^[0-9]+\.\s*//')"
        echo -e "  2. $(_ KERNEL_MANAGE_OPTION_RESTORE | sed -E 's/^[0-9]+\.\s*//')"
        echo -e "  3. $(_ MOK_OPTION_RETURN | sed -E 's/^[0-9]+\.\s*//')"
        echo ""
        echo -n "$(_ SELECT_OPERATION_RANGE range="1-3") "
        local mchoice
        read -r mchoice || mchoice="3"

        case "${mchoice}" in
            1)
                echo ""
                manage_kernel_removal_interactive
                ;;
            2)
                echo ""
                restore_stock_slackware_kernels
                echo ""
                read -r -p "$(_ PRESS_ENTER_CONTINUE)" || true
                ;;
            3)
                return 0
                ;;
            *)
                echo -e "\n${YELLOW}$(_ INVALID_SELECTION)${RESET}"
                sleep 1
                ;;
        esac
    done
}

# --- [ ROOT FILESYSTEM & DEVICE RESOLUTION ] ---
detect_root_filesystem_details() {
    local root_dev root_fs root_uuid root_flags root_subvol

    # 1. Device resolution
    root_dev=$(findmnt -n -o SOURCE / 2>/dev/null || true)
    if [ -z "${root_dev}" ]; then
        root_dev=$(awk '$2 == "/" {print $1}' /proc/mounts 2>/dev/null | head -n1 || true)
    fi
    root_dev=${root_dev:-"/dev/root"}

    # 2. Filesystem type resolution
    root_fs=$(findmnt -n -o FSTYPE / 2>/dev/null || true)
    if [ -z "${root_fs}" ]; then
        root_fs=$(awk '$2 == "/" {print $3}' /proc/mounts 2>/dev/null | head -n1 || true)
    fi
    root_fs=${root_fs:-"ext4"}

    # 3. UUID resolution (preferred for reliable boot args)
    root_uuid=$(findmnt -n -o UUID / 2>/dev/null || true)
    if [ -z "${root_uuid}" ] && command -v blkid >/dev/null 2>&1 && [ -b "${root_dev}" ]; then
        root_uuid=$(blkid -s UUID -o value "${root_dev}" 2>/dev/null || true)
    fi

    # 4. Subvolume / mount options resolution (for Btrfs)
    root_flags=""
    if [ "${root_fs}" = "btrfs" ]; then
        local mnt_opts
        mnt_opts=$(findmnt -n -o OPTIONS / 2>/dev/null || awk '$2 == "/" {print $4}' /proc/mounts 2>/dev/null | head -n1 || true)
        local subvol_val subvol_id
        subvol_val=$(echo "${mnt_opts}" | tr ',' '\n' | grep -E '^subvol=' | head -n1 | cut -d'=' -f2 || true)
        subvol_id=$(echo "${mnt_opts}" | tr ',' '\n' | grep -E '^subvolid=' | head -n1 | cut -d'=' -f2 || true)
        if [ -n "${subvol_val}" ] && [ "${subvol_val}" != "/" ] && [ "${subvol_id}" != "5" ]; then
            root_flags="rootflags=subvol=${subvol_val}"
        fi
    fi

    echo "${root_dev}|${root_fs}|${root_uuid}|${root_flags}"
}

ensure_grub_smart_kernel_sorting() {
    local grub_script="/etc/grub.d/10_linux"
    [ -f "${grub_script}" ] || return 0

    if grep -q "Smart CachyOS Prioritized Sort" "${grub_script}" 2>/dev/null; then
        return 0
    fi

    sudo python3 - << 'PYGRUB_SORT'
import os, sys

script = '/etc/grub.d/10_linux'
if not os.path.exists(script):
    sys.exit(0)

try:
    with open(script, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    new_lines = []
    modified = False
    for line in lines:
        if 'reverse_sorted_list=' in line and 'version_sort -r' in line:
            modified = True
            snippet = """# Smart CachyOS Prioritized Sort (slacky-update)
if command -v python3 >/dev/null 2>&1; then
  reverse_sorted_list=$(echo "$list" | tr ' ' '\\n' | python3 -c "
import sys, os, re

def rank(k):
    b = os.path.basename(k)
    tier = -50
    if '-cachyos-bore-lto' in b or '-cachyos-lto' in b:
        tier = 50
    elif '-cachyos-rt-bore' in b or '-cachyos-rt' in b:
        tier = 45
    elif '-cachyos-bore' in b:
        tier = 40
    elif '-cachyos-eevdf' in b:
        tier = 38
    elif '-cachyos-bmq' in b:
        tier = 36
    elif '-zen' in b or b.endswith('-zen') or b == 'vmlinuz-linux-zen':
        tier = 35
    elif '-cachyos-deckify' in b:
        tier = 34
    elif '-cachyos' in b and '-rc' not in b and '-lts' not in b and '-bore' not in b and '-rt' not in b and '-eevdf' not in b and '-bmq' not in b and '-deckify' not in b:
        tier = 30
    elif '-arch' in b or b == 'vmlinuz-linux':
        tier = 28
    elif '-cachyos-lts' in b:
        tier = 20
    elif '-cachyos-rc' in b:
        tier = 10
    elif 'vmlinuz-generic' in b or 'generic' in b:
        tier = -40
    elif 'vmlinuz-huge' in b or 'huge' in b:
        tier = -60
    nums = [int(x) for x in re.findall(r'\\d+', b)]
    return (tier, nums)

lines = [l.strip() for l in sys.stdin if l.strip()]
ranked = sorted(lines, key=rank, reverse=True)
print(' '.join(ranked))
" 2>/dev/null || true)
fi
if [ -z "${reverse_sorted_list}" ]; then
""" + line + "fi\n"
            new_lines.append(snippet)
        else:
            new_lines.append(line)

    if modified:
        if not os.path.exists(script + '.orig'):
            try:
                with open(script + '.orig', 'w', encoding='utf-8') as f_orig:
                    f_orig.writelines(lines)
            except Exception:
                pass
        with open(script, 'w', encoding='utf-8') as f_out:
            f_out.writelines(new_lines)
except Exception:
    pass
PYGRUB_SORT
}

set_grub_smart_default_priority() {
    local top_dog
    top_dog=$(sudo python3 -c "
import os, re

def rank_kernel(k):
    tier = -2
    if '-cachyos-bore-lto' in k or '-cachyos-lto' in k:
        tier = 50
    elif '-cachyos-rt-bore' in k or '-cachyos-rt' in k:
        tier = 45
    elif '-cachyos-bore' in k:
        tier = 40
    elif '-cachyos-eevdf' in k:
        tier = 38
    elif '-cachyos-bmq' in k:
        tier = 36
    elif '-zen' in k or k.endswith('-zen') or k == 'vmlinuz-linux-zen':
        tier = 35
    elif '-cachyos-deckify' in k:
        tier = 34
    elif '-cachyos-lts' in k:
        tier = 20
    elif '-cachyos-rc' in k:
        tier = 10
    elif '-cachyos' in k and '-rc' not in k and '-lts' not in k and '-bore' not in k and '-rt' not in k and '-eevdf' not in k and '-bmq' not in k and '-deckify' not in k:
        tier = 30
    elif '-arch' in k or k == 'vmlinuz-linux':
        tier = 28
    elif 'vmlinuz-generic' in k:
        tier = 0
    elif 'vmlinuz-huge' in k:
        tier = -1
    nums = [int(x) for x in re.findall(r'\d+', k)]
    return (tier, nums)

try:
    kernels = [f for f in os.listdir('/boot') if f.startswith('vmlinuz-') and not os.path.islink(os.path.join('/boot', f))]
    ranked = sorted(kernels, key=rank_kernel, reverse=True)
    if ranked:
        print('/boot/' + ranked[0])
except Exception:
    pass
" 2>/dev/null || echo "")

    if [ -n "${top_dog}" ]; then
        local grub_default_file="/etc/default/grub"
        if [ -f "${grub_default_file}" ]; then
            if grep -q "^GRUB_TOP_LEVEL=" "${grub_default_file}"; then
                sudo sed -i "s|^GRUB_TOP_LEVEL=.*|GRUB_TOP_LEVEL=\"${top_dog}\"|" "${grub_default_file}"
            else
                echo "GRUB_TOP_LEVEL=\"${top_dog}\"" | sudo tee -a "${grub_default_file}" >/dev/null
            fi
        fi
    fi
}

sync_grub_configuration() {
    validate_privileges
    local grub_mkconfig_bin
    grub_mkconfig_bin=$(command -v grub-mkconfig 2>/dev/null || command -v grub2-mkconfig 2>/dev/null || echo "/usr/sbin/grub-mkconfig")
    [ -x "${grub_mkconfig_bin}" ] || return 0

    ensure_grub_smart_kernel_sorting
    set_grub_smart_default_priority

    local grub_target=""
    if [ -f "/boot/grub/grub.cfg" ] || [ -d "/boot/grub" ]; then
        grub_target="/boot/grub/grub.cfg"
    elif [ -f "/boot/grub2/grub.cfg" ] || [ -d "/boot/grub2" ]; then
        grub_target="/boot/grub2/grub.cfg"
    fi

    if [ -n "${grub_target}" ]; then
        local grub_tmp="${grub_target}.tmp-$$"
        if sudo "${grub_mkconfig_bin}" -o "${grub_tmp}" >/dev/null 2>&1; then
            local gsz
            gsz=$(stat -c%s "${grub_tmp}" 2>/dev/null || stat -f%z "${grub_tmp}" 2>/dev/null || echo 0)
            if [ "${gsz}" -gt 500 ]; then
                sudo mv -f "${grub_tmp}" "${grub_target}"
                sudo chmod 600 "${grub_target}" 2>/dev/null || true
                return 0
            else
                log_warn "Generated GRUB config is unexpectedly small (${gsz} bytes). Preserving existing ${grub_target}."
                sudo rm -f "${grub_tmp}" 2>/dev/null || true
            fi
        else
            sudo rm -f "${grub_tmp}" 2>/dev/null || true
            log_warn "Failed to execute grub-mkconfig to generate ${grub_target}."
        fi
    fi
    return 1
}

# --- [ BOOTLOADER SYNCHRONIZATION & CMDLINE INJECTION ] ---
sync_bootloader_configuration() {
    local kver_full="$1"
    validate_privileges
    probe_gpu_hardware

    local required_params=""
    if [ "${HAS_NVIDIA}" = "true" ]; then
        required_params="nvidia_drm.modeset=1 nvidia_drm.fbdev=1 nvidia.NVreg_PreserveVideoMemoryAllocations=1"
    fi

    local root_dev root_fs root_uuid root_flags
    IFS='|' read -r root_dev root_fs root_uuid root_flags <<< "$(detect_root_filesystem_details)"

    local root_cmd="root=${root_dev}"
    if [ -n "${root_uuid}" ]; then
        root_cmd="root=UUID=${root_uuid}"
    fi

    local root_extra=""
    if [ -n "${root_flags}" ]; then
        root_extra=" ${root_flags}"
    fi

    # 1. GRUB Configuration (CRITICAL: Never execute grub-install, preserve signed Shim)
    local grub_default_file="/etc/default/grub"
    if [ -f "${grub_default_file}" ]; then
        python3 - << PYGRUB
import os, re

cfg_path = "${grub_default_file}"
try:
    with open(cfg_path, "r", encoding="utf-8") as f:
        content = f.read()

    m = re.search(r'^(GRUB_CMDLINE_LINUX_DEFAULT=\")([^\"]*)(\")', content, re.MULTILINE)
    if m:
        prefix, cmdline, suffix = m.group(1), m.group(2), m.group(3)
        tokens = cmdline.strip().split()
        seen = set()
        result = []
        for t in tokens:
            norm = t
            if norm.startswith("nvidia-drm."):
                norm = "nvidia_drm." + norm[len("nvidia-drm."):]
            elif norm.startswith("nvidia-modeset."):
                norm = "nvidia_modeset." + norm[len("nvidia-modeset."):]
            elif norm.startswith("nvidia-uvm."):
                norm = "nvidia_uvm." + norm[len("nvidia-uvm."):]
            if norm not in seen:
                seen.add(norm)
                result.append(norm)

        has_nv = "${HAS_NVIDIA}".lower() == "true"
        if has_nv:
            for req in ["nvidia_drm.modeset=1", "nvidia_drm.fbdev=1", "nvidia.NVreg_PreserveVideoMemoryAllocations=1"]:
                if req not in seen:
                    seen.add(req)
                    result.append(req)

        new_cmdline = " ".join(result)
        if new_cmdline != cmdline:
            new_content = content[:m.start()] + prefix + new_cmdline + suffix + content[m.end():]
            with open(cfg_path, "w", encoding="utf-8") as f:
                f.write(new_content)
except Exception:
    pass
PYGRUB
    fi

    # 0. Pre-sign kernel binaries with sbctl strictly BEFORE calculating BLAKE2B hashes or generating configs
    if command -v sign_kernel_binaries_sbctl >/dev/null 2>&1; then
        sign_kernel_binaries_sbctl >/dev/null 2>&1 || true
    fi

    if sync_grub_configuration; then
        local g_target="/boot/grub/grub.cfg"
        [ -f "/boot/grub2/grub.cfg" ] && g_target="/boot/grub2/grub.cfg"
        log_success "GRUB fallback configuration synchronized (${g_target})."
    fi

    # 2. Limine Bootloader Configuration (if installed)
    if command -v is_limine_installed >/dev/null 2>&1 && [ "$(is_limine_installed)" = "true" ]; then
        local lim_ok=true
        if command -v generate_limine_configuration >/dev/null 2>&1; then
            if ! generate_limine_configuration; then
                lim_ok=false
                log_error "Limine configuration generator encountered an error."
            fi
        fi
        if [ "${lim_ok}" = "true" ] && command -v enroll_and_sign_limine >/dev/null 2>&1; then
            if ! enroll_and_sign_limine; then
                log_warn "Limine enrollment or Secure Boot signing completed with warnings."
            fi
        fi
        if [ "${lim_ok}" = "true" ]; then
            local esp_path
            esp_path=$(detect_limine_esp_path 2>/dev/null || echo "/boot")
            log_success "Limine bootloader matrix: BLAKE2B enrolled & Secure Boot signed (${esp_path}/limine.conf)."
        fi
    fi

    # 3. ELILO Bootloader Configuration (Standard Slackware UEFI)
    local elilo_cfg="/boot/efi/EFI/Slackware/elilo.conf"
    if [ -f "${elilo_cfg}" ] && [ ! -f "/boot/grub/grub.cfg" ] && [ ! -f "/boot/grub2/grub.cfg" ]; then
        log_info "ELILO bootloader detected at ${elilo_cfg}."
        echo -n "Would you like to sync ELILO with kernel ${kver_full}? [Y/n]: "
        read -r reply_elilo
        reply_elilo=${reply_elilo:-Y}
        if [[ "${reply_elilo}" =~ ^[YyJjSsOo]$ ]]; then
            validate_privileges
            log_info "Deploying ${kver_full} kernel and initrd to /boot/efi/EFI/Slackware/..."
            sudo cp -f "/boot/vmlinuz-${kver_full}" /boot/efi/EFI/Slackware/vmlinuz 2>/dev/null || true
            sudo cp -f "/boot/${initrd_target:-initramfs-${kver_full}.img}" /boot/efi/EFI/Slackware/initrd.gz 2>/dev/null || true
            local elilo_bin
            elilo_bin=$(command -v elilo 2>/dev/null || echo "/sbin/elilo")
            if [ -x "${elilo_bin}" ]; then
                sudo "${elilo_bin}" 2>/dev/null || true
            fi
            log_success "ELILO updated successfully with ${kver_full}."
        fi
    fi
}

verify_cachyos_package_integrity() {
    local archive="$1"
    [ -f "${archive}" ] || return 1
    if ! zstd -t "${archive}" >/dev/null 2>&1; then
        log_error "Archive $(basename "${archive}") failed zstd CRC integrity verification!"
        return 1
    fi
    if ! tar --zstd -tf "${archive}" >/dev/null 2>&1; then
        log_error "Archive $(basename "${archive}") failed tar structure verification!"
        return 1
    fi
    return 0
}

check_boot_disk_space() {
    local min_free_mb="${1:-250}"
    local target_mount="/boot"
    if [ ! -d "/boot" ] && [ -d "/boot/efi" ]; then
        target_mount="/boot/efi"
    fi

    local df_output
    df_output=$(df -k "${target_mount}" 2>/dev/null | awk 'NR==2 {print $2" "$4" "$5}')
    if [ -n "${df_output}" ]; then
        local total_kb free_kb use_pct_raw
        read -r total_kb free_kb use_pct_raw <<< "${df_output}"
        local free_mb=$(( free_kb / 1024 ))
        local use_pct
        use_pct=$(echo "${use_pct_raw}" | tr -d '%')

        if [ -n "${use_pct}" ] && [ "${use_pct}" -ge 75 ] 2>/dev/null; then
            log_warn "Capacity Warning: ${target_mount} partition is ${use_pct}% full (${free_mb} MB free)."
        fi

        if [ "${free_mb}" -lt "${min_free_mb}" ]; then
            log_warn "Low disk space on ${target_mount}: ${free_mb} MB free (recommended: at least ${min_free_mb} MB)."
            return 1
        fi
    fi
    return 0
}

# --- [ MULTI-KERNEL DKMS ENGINE & ANTI-RACE-CONDITION SHIELD ] ---
build_dkms_modules_for_all_kernels() {
    local target_mod="${1:-all}"
    local target_ver="${2:-}"

    if ! command -v dkms >/dev/null 2>&1; then
        return 0
    fi

    local depmod_bin
    depmod_bin=$(command -v depmod 2>/dev/null || echo "/sbin/depmod")

    # Discover all kernel versions with valid headers/build directory
    local target_kernels=()
    local all_kdirs
    all_kdirs=$(find /lib/modules /usr/lib/modules -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort -u || true)
    for kpath in ${all_kdirs}; do
        local kver
        kver=$(basename "${kpath}")
        # Check if build directory / Makefile exists
        if [ -d "${kpath}/build" ] || [ -f "${kpath}/build/Makefile" ] || [ -d "/usr/src/linux-headers-${kver}" ]; then
            local already=0
            for ek in "${target_kernels[@]:-}"; do
                [ "${ek}" = "${kver}" ] && already=1 && break
            done
            [ "${already}" -eq 0 ] && target_kernels+=("${kver}")
        fi
    done

    if [ "${#target_kernels[@]}" -eq 0 ]; then
        return 0
    fi

    # Retrieve registered DKMS modules
    local dkms_modules=()
    if [ "${target_mod}" != "all" ] && [ -n "${target_ver}" ]; then
        dkms_modules+=("${target_mod}/${target_ver}")
    else
        while IFS= read -r line; do
            [ -n "${line}" ] || continue
            dkms_modules+=("${line}")
        done <<< "$(dkms status 2>/dev/null | awk -F'[,/]' '{print $1"/"$2}' | tr -d ' ' | sort -u)"
    fi

    if [ "${#dkms_modules[@]}" -eq 0 ]; then
        return 0
    fi

    log_info "⚡ DKMS Multi-Kernel Engine: Auditing modules across ${#target_kernels[@]} kernel trees..."

    for kver in "${target_kernels[@]}"; do
        local has_precompiled_nvidia=false
        if find "/lib/modules/${kver}" "/usr/lib/modules/${kver}" -name "nvidia*.ko*" 2>/dev/null | grep -q "nvidia"; then
            has_precompiled_nvidia=true
        fi

        for mod_entry in "${dkms_modules[@]}"; do
            [ -n "${mod_entry}" ] || continue
            local m_name m_ver
            IFS='/' read -r m_name m_ver <<< "${mod_entry}"

            # Safety Shield: Never compile NVIDIA DKMS if precompiled nvidia modules are present in kernel tree
            if [ "${m_name}" = "nvidia" ] && [ "${has_precompiled_nvidia}" = "true" ]; then
                continue
            fi

            # Check if already installed for this kernel
            if dkms status -m "${m_name}" -v "${m_ver}" -k "${kver}" 2>/dev/null | grep -q "installed"; then
                continue
            fi

            log_info "Building DKMS module ${m_name} (v${m_ver}) for kernel ${kver}..."
            sudo dkms build -m "${m_name}" -v "${m_ver}" -k "${kver}" 2>/dev/null || {
                log_warn "DKMS build warning for ${m_name} on ${kver}"
                continue
            }
            sudo dkms install -m "${m_name}" -v "${m_ver}" -k "${kver}" 2>/dev/null || {
                log_warn "DKMS install warning for ${m_name} on ${kver}"
            }
        done

        # Re-index module tree
        sudo "${depmod_bin}" -a "${kver}" 2>/dev/null || true
    done

    log_success "DKMS Multi-Kernel synchronization complete across all installed kernels."
}

deploy_cachyos_kernel_packages() {
    local ver="$1"
    local k_url="$2"
    local h_url="$3"
    local flavor="${4:-standard}"
    local nv_url="${5:-NONE}"
    local r8125_url="${6:-NONE}"
    probe_gpu_hardware

    local staging_dir
    staging_dir=$(get_user_staging_dir)
    mkdir -p "${staging_dir}"

    local k_filename h_filename
    k_filename=$(basename "${k_url}")
    h_filename=$(basename "${h_url}")

    local k_file="${staging_dir}/${k_filename}"
    local h_file="${staging_dir}/${h_filename}"
    local k_sig_file="${staging_dir}/${k_filename}.sig"
    local h_sig_file="${staging_dir}/${h_filename}.sig"

    local dl_items=()
    dl_items+=("${k_url}|${k_file}|${k_url}.sig|${k_sig_file}")
    dl_items+=("${h_url}|${h_file}|${h_url}.sig|${h_sig_file}")

    local nv_filename="" nv_file=""
    if [ "${nv_url}" != "NONE" ] && [ -n "${nv_url}" ]; then
        nv_filename=$(basename "${nv_url}")
        nv_file="${staging_dir}/${nv_filename}"
        dl_items+=("${nv_url}|${nv_file}|${nv_url}.sig|${nv_file}.sig")
    fi

    local r8125_filename="" r8125_file=""
    if [ "${r8125_url}" != "NONE" ] && [ -n "${r8125_url}" ]; then
        r8125_filename=$(basename "${r8125_url}")
        r8125_file="${staging_dir}/${r8125_filename}"
        dl_items+=("${r8125_url}|${r8125_file}|${r8125_url}.sig|${r8125_file}.sig")
    fi

    if ! download_parallel_pacman "CachyOS Kernel (${flavor})" "${dl_items[@]}"; then
        log_error "Failed to download CachyOS kernel packages."
        rm -f "${k_file}" "${h_file}" "${k_sig_file}" "${h_sig_file}" "${nv_file}" "${nv_file}.sig" "${r8125_file}" "${r8125_file}.sig" 2>/dev/null || true
        return 1
    fi

    if ! verify_cachyos_gpg_signature "${k_file}" "${k_sig_file}"; then
        log_error "Kernel package GPG signature check failed! Aborting."
        rm -f "${k_file}" "${h_file}" "${k_sig_file}" "${h_sig_file}" 2>/dev/null || true
        return 1
    fi
    if ! verify_cachyos_gpg_signature "${h_file}" "${h_sig_file}"; then
        log_error "Kernel headers package GPG signature check failed! Aborting."
        rm -f "${k_file}" "${h_file}" "${k_sig_file}" "${h_sig_file}" 2>/dev/null || true
        return 1
    fi

    if ! verify_cachyos_package_integrity "${k_file}" || ! verify_cachyos_package_integrity "${h_file}"; then
        log_error "Kernel package integrity verification failed! Aborting deployment to prevent system corruption."
        rm -f "${k_file}" "${h_file}" 2>/dev/null || true
        return 1
    fi

    # Resolve exact kernel release string directly from the verified package
    local kver_full=""
    kver_full=$(tar --zstd -tf "${k_file}" 2>/dev/null | grep -E '^usr/lib/modules/[^/]+/$' | head -n 1 | sed -E 's|^usr/lib/modules/([^/]+)/$|\1|' || true)
    if [ -z "${kver_full}" ]; then
        kver_full=$(tar --zstd -tf "${k_file}" 2>/dev/null | grep -E '^usr/lib/modules/[^/]+/modules\.order' | head -n 1 | sed -E 's|^usr/lib/modules/([^/]+)/.*|\1|' || true)
    fi

    # Root transaction phase
    validate_privileges
    if ! check_boot_disk_space 250; then
        log_warn "Proceeding with caution, but /boot partition is running very low on disk space."
    fi

    sudo tar --zstd -xf "${k_file}" -C /
    sudo tar --zstd -xf "${h_file}" -C /

    if [ -z "${kver_full}" ]; then
        local ver_clean
        ver_clean=$(echo "${ver}" | sed -E 's/-[0-9]+$//')
        if [ "${flavor}" = "bore" ]; then
            kver_full="${ver_clean}-cachyos-bore"
        elif [ "${flavor}" = "lto" ]; then
            kver_full="${ver_clean}-cachyos-bore-lto"
            if [ ! -d "/usr/lib/modules/${kver_full}" ] && [ -d "/usr/lib/modules/${ver_clean}-cachyos-lto" ]; then
                kver_full="${ver_clean}-cachyos-lto"
            fi
        elif [ "${flavor}" = "eevdf" ]; then
            kver_full="${ver_clean}-cachyos-eevdf"
        elif [ "${flavor}" = "bmq" ]; then
            kver_full="${ver_clean}-cachyos-bmq"
        elif [ "${flavor}" = "deckify" ]; then
            kver_full="${ver_clean}-cachyos-deckify"
        elif [ "${flavor}" = "rt-bore" ]; then
            kver_full="${ver_clean}-cachyos-rt-bore"
        elif [ "${flavor}" = "rc" ]; then
            kver_full="${ver_clean}-cachyos-rc"
        elif [ "${flavor}" = "lts" ]; then
            kver_full="${ver_clean}-cachyos-lts"
        elif [ "${flavor}" = "zen" ]; then
            kver_full="${ver_clean}-zen"
        elif [ "${flavor}" = "arch" ]; then
            kver_full="${ver_clean}-arch"
        else
            kver_full="${ver_clean}-cachyos"
        fi
    fi

    # Verify matching directory in /usr/lib/modules if slight naming variation
    if [ ! -d "/usr/lib/modules/${kver_full}" ]; then
        local matched_dir
        matched_dir=$(find /usr/lib/modules -maxdepth 1 -type d -name "*${flavor}*" 2>/dev/null | sort -V | tail -n 1 || true)
        if [ -n "${matched_dir}" ] && [ -d "${matched_dir}" ]; then
            kver_full=$(basename "${matched_dir}")
        fi
    fi

    if [ -d "/usr/lib/modules/${kver_full}" ] && [ ! -d "/lib/modules/${kver_full}" ]; then
        sudo mkdir -p /lib/modules
        sudo ln -sf "/usr/lib/modules/${kver_full}" "/lib/modules/${kver_full}"
    fi

    # Resolve headers directory dynamically
    local headers_dir=""
    headers_dir=$(tar --zstd -tf "${h_file}" 2>/dev/null | grep -E '^usr/src/linux-headers-[^/]+/$' | head -n 1 | sed -E 's|^usr/src/([^/]+)/$|/usr/src/\1|' || true)
    if [ -z "${headers_dir}" ] || [ ! -d "${headers_dir}" ]; then
        if [ -d "/usr/src/linux-headers-${kver_full}" ]; then
            headers_dir="/usr/src/linux-headers-${kver_full}"
        elif [ -d "/usr/lib/modules/${kver_full}/build" ]; then
            headers_dir="/usr/lib/modules/${kver_full}/build"
        else
            headers_dir=$(find /usr/src -maxdepth 1 -type d -name "linux-headers-*${flavor}*" 2>/dev/null | sort -V | tail -n 1 || true)
        fi
    fi

    # Copy vmlinuz image dynamically
    local vmlinuz_in_pkg=""
    vmlinuz_in_pkg=$(tar --zstd -tf "${k_file}" 2>/dev/null | grep -E '^boot/vmlinuz-' | head -n 1 | sed 's|^|/|' || true)
    if [ -n "${vmlinuz_in_pkg}" ] && [ -f "${vmlinuz_in_pkg}" ]; then
        sudo cp -f "${vmlinuz_in_pkg}" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/boot/vmlinuz-linux-cachyos-bore-lto" ] && [ "${flavor}" = "lto" ]; then
        sudo cp -f "/boot/vmlinuz-linux-cachyos-bore-lto" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/boot/vmlinuz-linux-cachyos-bore" ] && [ "${flavor}" = "bore" ]; then
        sudo cp -f "/boot/vmlinuz-linux-cachyos-bore" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/boot/vmlinuz-linux-cachyos-eevdf" ] && [ "${flavor}" = "eevdf" ]; then
        sudo cp -f "/boot/vmlinuz-linux-cachyos-eevdf" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/boot/vmlinuz-linux-cachyos-bmq" ] && [ "${flavor}" = "bmq" ]; then
        sudo cp -f "/boot/vmlinuz-linux-cachyos-bmq" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/boot/vmlinuz-linux-cachyos-deckify" ] && [ "${flavor}" = "deckify" ]; then
        sudo cp -f "/boot/vmlinuz-linux-cachyos-deckify" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/boot/vmlinuz-linux-cachyos-rt-bore" ] && [ "${flavor}" = "rt-bore" ]; then
        sudo cp -f "/boot/vmlinuz-linux-cachyos-rt-bore" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/boot/vmlinuz-linux-cachyos-rc" ] && [ "${flavor}" = "rc" ]; then
        sudo cp -f "/boot/vmlinuz-linux-cachyos-rc" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/boot/vmlinuz-linux-cachyos-lts" ] && [ "${flavor}" = "lts" ]; then
        sudo cp -f "/boot/vmlinuz-linux-cachyos-lts" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/boot/vmlinuz-linux-cachyos" ] && [ "${flavor}" = "standard" ]; then
        sudo cp -f "/boot/vmlinuz-linux-cachyos" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/boot/vmlinuz-linux-zen" ] && [ "${flavor}" = "zen" ]; then
        sudo cp -f "/boot/vmlinuz-linux-zen" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/boot/vmlinuz-linux" ] && [ "${flavor}" = "arch" ]; then
        sudo cp -f "/boot/vmlinuz-linux" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/usr/lib/modules/${kver_full}/vmlinuz" ]; then
        sudo cp -f "/usr/lib/modules/${kver_full}/vmlinuz" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/lib/modules/${kver_full}/vmlinuz" ]; then
        sudo cp -f "/lib/modules/${kver_full}/vmlinuz" "/boot/vmlinuz-${kver_full}"
    fi

    if [ -n "${headers_dir}" ] && [ -d "${headers_dir}" ]; then
        sudo ln -sf "${headers_dir}" "/lib/modules/${kver_full}/build"
        sudo ln -sf "${headers_dir}" "/lib/modules/${kver_full}/source"
    elif [ -d "/usr/lib/modules/${kver_full}/build" ]; then
        sudo ln -sf "/usr/lib/modules/${kver_full}/build" "/lib/modules/${kver_full}/build" 2>/dev/null || true
        sudo ln -sf "/usr/lib/modules/${kver_full}/build" "/lib/modules/${kver_full}/source"
    fi

    # Deploy Realtek 2.5GbE (r8125) module if supplied
    if [ -n "${r8125_file}" ] && [ -f "${r8125_file}" ]; then
        if verify_cachyos_package_integrity "${r8125_file}"; then
            log_info "Deploying matching Realtek 2.5GbE (r8125) module for ${kver_full}..."
            sudo tar --zstd -xf "${r8125_file}" -C /
            log_success "$(_ R8125_DEPLOY_SUCCESS version="${kver_full}" 2>/dev/null || echo "Realtek r8125 module successfully deployed for kernel ${kver_full}.")"
        else
            log_warn "Realtek r8125 package integrity verification failed! Skipping module extraction."
        fi
    fi

    # Fetch and deploy matching CachyOS NVIDIA driver if on supported NVIDIA GPU
    if [ "${HAS_NVIDIA}" = "true" ]; then
        local gpu_arch="MODERN"
        if command -v detect_nvidia_gpu >/dev/null 2>&1; then
            gpu_arch=$(detect_nvidia_gpu)
        fi

        if [ "${gpu_arch}" = "LEGACY" ]; then
            log_warn "NVIDIA GPU is older than Pascal (pre-GTX 10-series). CachyOS kernels do not support legacy proprietary drivers."
        elif [ "${gpu_arch}" = "PASCAL" ]; then
            log_info "Pascal GPU architecture detected (GTX 10-series):"
            log_info "NVIDIA Open modules are unsupported on pre-Turing hardware."
            log_info "Fetching matching nvidia-580xx-dkms from CachyOS repository..."
            local cachy_base="https://mirror.cachyos.org/repo/x86_64/cachyos"
            local dkms_pkg
            dkms_pkg=$(curl -sSL -m 10 "${cachy_base}/" 2>/dev/null | grep -o -E 'nvidia-580xx-dkms-[0-9a-zA-Z_\.-]*\.pkg\.tar\.zst' | head -n 1 || echo "")
            if [ -n "${dkms_pkg}" ]; then
                local dkms_file="${staging_dir}/${dkms_pkg}"
                log_info "Downloading ${dkms_pkg}..."
                sudo curl -sSL -o "${dkms_file}" "${cachy_base}/${dkms_pkg}"
                if ! verify_cachyos_package_integrity "${dkms_file}"; then
                    log_error "DKMS package integrity verification failed! Skipping extraction."
                    sudo rm -f "${dkms_file}" 2>/dev/null || true
                else
                    sudo tar --zstd -xf "${dkms_file}" -C /
                    if command -v dkms >/dev/null 2>&1; then
                        local dkms_ver
                        dkms_ver=$(dkms status 2>/dev/null | grep -E '^nvidia/' | awk -F'[,/]' '{print $2}' | tr -d ' ' | head -n 1 || echo "580.178.04")
                        log_info "Building nvidia ${dkms_ver} for kernel ${kver_full} via DKMS..."
                        sudo dkms build -m nvidia -v "${dkms_ver}" -k "${kver_full}" 2>/dev/null || true
                        sudo dkms install -m nvidia -v "${dkms_ver}" -k "${kver_full}" 2>/dev/null || true
                    fi
                fi
            else
                log_warn "Could not resolve nvidia-580xx-dkms package from CachyOS repository."
            fi
        elif [ "${gpu_arch}" = "MODERN" ]; then
            if [ "${nv_url}" != "NONE" ] && [ -n "${nv_url}" ]; then
                local nv_filename
                nv_filename=$(basename "${nv_url}")
                local nv_file="${staging_dir}/${nv_filename}"
                if [ ! -f "${nv_file}" ]; then
                    log_info "Modern NVIDIA GPU detected. Downloading prebuilt matching CachyOS NVIDIA Open driver (${nv_filename})..."
                    curl -sSL -o "${nv_file}" "${nv_url}" 2>/dev/null || sudo curl -sSL -o "${nv_file}" "${nv_url}"
                fi
                if ! verify_cachyos_package_integrity "${nv_file}"; then
                    log_error "NVIDIA driver package integrity verification failed! Skipping extraction."
                    sudo rm -f "${nv_file}" 2>/dev/null || true
                else
                    sudo tar --zstd -xf "${nv_file}" -C /
                    local act_nv_ver=""
                    if command -v detect_cachyos_nvidia_upstream_version >/dev/null 2>&1; then
                        act_nv_ver=$(detect_cachyos_nvidia_upstream_version)
                    elif ls /var/log/packages/cachyos-nvidia-utils-* 1>/dev/null 2>&1; then
                        act_nv_ver=$(basename "$(ls /var/log/packages/cachyos-nvidia-utils-* 2>/dev/null | head -n 1)" | sed -E 's/cachyos-nvidia-utils-([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/' || echo "")
                    fi
                    if [ -n "${act_nv_ver}" ]; then
                        if command -v prune_stale_nvidia_modules_for_kernel >/dev/null 2>&1; then
                            prune_stale_nvidia_modules_for_kernel "${kver_full}" "${act_nv_ver}"
                        elif command -v register_precompiled_nvidia_in_dkms >/dev/null 2>&1; then
                            register_precompiled_nvidia_in_dkms "${kver_full}" "${act_nv_ver}"
                        fi
                    fi
                fi
            elif command -v dkms >/dev/null 2>&1; then
                if [[ "${kver_full}" =~ -rc ]]; then
                    log_warn "Notice: CachyOS RC kernel (${kver_full}) requires precompiled open module; skipping DKMS fallback."
                else
                    log_info "No precompiled NVIDIA package matching v${ver} on mirrors. Engaging DKMS Bridge for ${kver_full}..."
                    local cachy_nv_ver="595.44.02"
                    if command -v detect_cachyos_nvidia_upstream_version >/dev/null 2>&1; then
                        cachy_nv_ver=$(detect_cachyos_nvidia_upstream_version)
                    elif ls /var/log/packages/cachyos-nvidia-utils-* 1>/dev/null 2>&1; then
                        cachy_nv_ver=$(basename "$(ls /var/log/packages/cachyos-nvidia-utils-* 2>/dev/null | head -n 1)" | sed -E 's/cachyos-nvidia-utils-([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/' || echo "595.44.02")
                    fi
                    if command -v ensure_cachyos_nvidia_dkms_source_unpacked >/dev/null 2>&1; then
                        ensure_cachyos_nvidia_dkms_source_unpacked "${cachy_nv_ver}" "MODERN" >/dev/null 2>&1 || true
                    fi
                    log_info "Building nvidia-open ${cachy_nv_ver} for kernel ${kver_full} via DKMS..."
                    sudo dkms build -m nvidia -v "${cachy_nv_ver}" -k "${kver_full}" 2>/dev/null || log_warn "DKMS build warning for ${kver_full}"
                    sudo dkms install -m nvidia -v "${cachy_nv_ver}" -k "${kver_full}" 2>/dev/null || log_warn "DKMS install warning for ${kver_full}"
                    if command -v prune_stale_nvidia_modules_for_kernel >/dev/null 2>&1; then
                        prune_stale_nvidia_modules_for_kernel "${kver_full}" "${cachy_nv_ver}"
                    fi
                fi
            else
                log_warn "Notice: No precompiled NVIDIA package or DKMS toolchain available for ${kver_full}."
            fi
        fi
    fi

    local depmod_bin
    depmod_bin=$(command -v depmod 2>/dev/null || echo "/sbin/depmod")
    sudo "${depmod_bin}" -a "${kver_full}"
    log_success "Kernel & headers deployed: ${kver_full}"

    # 1. Build DKMS out-of-tree modules (v4l2loopback, broadcom-wl, VirtualBox, NVIDIA, etc.)
    if ! command -v dkms >/dev/null 2>&1; then
        log_info "DKMS is not installed. DKMS automates module rebuilding for v4l2loopback, broadcom-wl, VirtualBox, and out-of-tree drivers across kernel updates."
        if command -v sboinstall >/dev/null 2>&1 || [ -d /var/lib/sbopkg ]; then
            echo -n "Would you like to install DKMS from SlackBuilds now? [y/N]: "
            read -r reply_dkms
            if [[ "${reply_dkms}" =~ ^[YyJjSsOo]$ ]]; then
                log_info "Installing DKMS from SlackBuilds..."
                if command -v sboinstall >/dev/null 2>&1; then
                    sudo sboinstall -r -j$(nproc) dkms 2>/dev/null || true
                fi
                if command -v dkms >/dev/null 2>&1; then
                    log_success "DKMS installed successfully!"
                fi
            fi
        fi
    fi

    if command -v dkms >/dev/null 2>&1; then
        build_dkms_modules_for_all_kernels
    fi

    if [ "${HAS_NVIDIA}" = "true" ]; then
        if [ ! -d "/usr/lib/modules/${kver_full}/kernel/drivers/video" ] && [ ! -d "/lib/modules/${kver_full}/kernel/drivers/video" ]; then
            if command -v build_nvidia_modules >/dev/null 2>&1; then
                build_nvidia_modules "${kver_full}"
            fi
        fi

        # Synchronize CachyOS NVIDIA user-space package and any stock Slackware kernels unless deferred
        if [ "${DEFER_BOOT_SYNC:-0}" != "1" ]; then
            if command -v ensure_cachyos_nvidia_duties >/dev/null 2>&1; then
                ensure_cachyos_nvidia_duties
            fi
        fi
    fi

    # 2. Generate initramfs image (Dracut) and sync bootloader unless deferred
    if [ "${DEFER_BOOT_SYNC:-0}" != "1" ]; then
        generate_kernel_initramfs "${kver_full}"
        if command -v enforce_secure_boot_armor >/dev/null 2>&1; then
            enforce_secure_boot_armor
        fi
        sync_bootloader_configuration "${kver_full}"
    fi
}

# --- [ HYBRID INITRAMFS ENGINE ROUTER ] ---
detect_initramfs_engine() {
    if command -v dracut >/dev/null 2>&1; then
        if [ -d "/etc/dracut.conf.d" ] || [ -f "/etc/dracut.conf" ] || ls /boot/initramfs-*.img >/dev/null 2>&1; then
            echo "dracut"
            return 0
        fi
    fi
    echo "mkinitrd"
}

can_run_parallel_dracut() {
    local n_cpu
    n_cpu=$(nproc 2>/dev/null || echo 1)
    [ "${n_cpu}" -ge 12 ] || return 1

    local mem_kb
    mem_kb=$(grep -E '^MemTotal:' /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
    [ "${mem_kb}" -ge 15500000 ] || return 1

    return 0
}

generate_kernel_initramfs() {
    local kver="$1"
    validate_privileges
    probe_gpu_hardware
    if ! check_boot_disk_space 250; then
        log_warn "Proceeding with caution, but /boot partition is running very low on disk space."
    fi

    local engine
    engine=$(detect_initramfs_engine)
    if [ "${engine}" = "mkinitrd" ] && [[ "${kver}" =~ cachyos ]]; then
        log_info "Dracut is recommended for CachyOS kernels to dynamically bundle storage, NVMe and GPU modules."
        if command -v sboinstall >/dev/null 2>&1 || [ -d /var/lib/sbopkg ]; then
            echo -n "Would you like to build and install Dracut via SBo before generating initramfs? [y/N]: "
            read -r reply_dracut
            if [[ "${reply_dracut}" =~ ^[YyJjSsOo]$ ]]; then
                log_info "Installing Dracut from SlackBuilds..."
                if command -v sboinstall >/dev/null 2>&1; then
                    sudo sboinstall -r -j$(nproc) dracut 2>/dev/null || true
                fi
                if command -v dracut >/dev/null 2>&1; then
                    engine="dracut"
                    log_success "Dracut installed! Switching initramfs engine to Dracut."
                fi
            fi
        fi
    fi

    if [ "${engine}" = "dracut" ]; then
        local dracut_bin
        dracut_bin=$(command -v dracut 2>/dev/null || echo "/usr/bin/dracut")
        local dracut_args=(--force)
        if [ "$(uname -m)" = "x86_64" ] && [ -d "/usr/lib64" ]; then
            dracut_args+=(--libdirs "/lib64 /usr/lib64 /usr/local/lib64")
            if [ -d "/etc/dracut.conf.d" ] && [ ! -f "/etc/dracut.conf.d/00-multilib.conf" ]; then
                echo 'libdirs=" /lib64 /usr/lib64 /usr/local/lib64 "' | sudo tee /etc/dracut.conf.d/00-multilib.conf >/dev/null 2>&1 || true
            fi
        fi
        local root_fs
        root_fs=$(findmnt -n -o FSTYPE / 2>/dev/null || awk '$2 == "/" {print $3}' /proc/mounts 2>/dev/null | head -n1 || echo "ext4")
        if [ "${root_fs}" = "xfs" ]; then
            dracut_args+=(--add "xfs" --add-drivers "xfs crc32c")
        elif [ "${root_fs}" = "btrfs" ]; then
            dracut_args+=(--add "btrfs" --add-drivers "btrfs zstd crc32c")
        fi

        local is_laptop=0
        if command -v is_laptop_chassis >/dev/null 2>&1 && is_laptop_chassis; then
            is_laptop=1
        fi

        if [ "${kver}" = "ALL" ] || [ "${kver}" = "TARGETED" ] || [ "${kver}" = "TARGETED_PIPELINE" ]; then
            local pending_kvers=()
            local pending_nv=()
            local pending_args=()

            for kdir in /lib/modules/*; do
                [ -d "${kdir}" ] || continue
                local single_kver
                single_kver=$(basename "${kdir}")
                [ -f "${kdir}/modules.dep" ] || continue
                if sudo test -f "/boot/vmlinuz-${single_kver}" || sudo test -f "/boot/vmlinuz-generic" || [ -d "/lib/modules/${single_kver}/kernel" ]; then
                    local initrd_out="/boot/initramfs-${single_kver}.img"
                    local has_k_nv=false
                    local k_nv_mod=""
                    k_nv_mod=$(find "/lib/modules/${single_kver}" "/usr/lib/modules/${single_kver}" -name "nvidia.ko*" 2>/dev/null | head -n 1 || true)
                    if [ -n "${k_nv_mod}" ]; then
                        has_k_nv=true
                    fi

                    # In TARGETED mode, check if existing initramfs is already up to date
                    if { [ "${kver}" = "TARGETED" ] || [ "${kver}" = "TARGETED_PIPELINE" ]; } && sudo test -f "${initrd_out}"; then
                        local is_up_to_date=true
                        if sudo test -f "/boot/vmlinuz-${single_kver}" && sudo test "/boot/vmlinuz-${single_kver}" -nt "${initrd_out}"; then
                            is_up_to_date=false
                        fi
                        if [ "${has_k_nv}" = "true" ] && [ -f "${k_nv_mod}" ] && sudo test "${k_nv_mod}" -nt "${initrd_out}"; then
                            is_up_to_date=false
                        fi
                        if [ "${is_up_to_date}" = "true" ]; then
                            continue
                        fi
                    fi

                    local k_dracut_args=("${dracut_args[@]}")
                    if [ "${has_k_nv}" = "true" ]; then
                        if [ "${is_laptop}" -eq 1 ]; then
                            if [ "${HAS_INTEL}" = "true" ]; then
                                k_dracut_args+=(--force-drivers "i915 nvidia nvidia_modeset nvidia_uvm nvidia_drm")
                            elif [ "${HAS_AMD}" = "true" ]; then
                                k_dracut_args+=(--force-drivers "amdgpu nvidia nvidia_modeset nvidia_uvm nvidia_drm")
                            else
                                k_dracut_args+=(--add-drivers "nvidia nvidia_modeset nvidia_uvm nvidia_drm")
                            fi
                        else
                            k_dracut_args+=(--add-drivers "nvidia nvidia_modeset nvidia_uvm nvidia_drm")
                        fi
                    fi

                    pending_kvers+=("${single_kver}")
                fi
            done

            local total_builds="${#pending_kvers[@]}"
            local pipeline_generated=()

            if [ "${total_builds}" -eq 0 ]; then
                if [ "${kver}" = "TARGETED_PIPELINE" ]; then
                    printf "  \033[1;36m[3/5]\033[0m \033[1mDracut Initramfs Generation\033[0m  : \033[1;32mAll installed images are up to date\033[0m\n"
                fi
                return 0
            fi

            local cur_loc
            cur_loc=$(get_active_locale 2>/dev/null || echo "en")
            local spinner_frames=()
            if [[ "${cur_loc}" =~ (en-ca|ca) ]]; then
                spinner_frames=($'\033[2;31m🍁\033[0m' $'\033[1;31m🍁\033[0m' $'\033[1;37m🍁\033[0m' $'\033[1;31m🍁\033[0m')
            elif [[ "${cur_loc}" =~ radical ]]; then
                spinner_frames=($'\033[2;33m⚡\033[0m' $'\033[1;33m⚡\033[0m' $'\033[1;37m⚡\033[0m' $'\033[1;33m✨\033[0m')
            else
                spinner_frames=('⏳' '⌛')
            fi

            if can_run_parallel_dracut && [ "${total_builds}" -gt 1 ]; then
                local pids=()
                local tmp_files=()
                local out_files=()

                for ((i=0; i<total_builds; i++)); do
                    local skver="${pending_kvers[i]}"
                    local initrd_out="/boot/initramfs-${skver}.img"
                    local tmp_initrd="/tmp/dracut-${skver}-$$.img"
                    sudo rm -f "${tmp_initrd}" 2>/dev/null || true

                    local has_k_nv=false
                    if find "/lib/modules/${skver}" "/usr/lib/modules/${skver}" -name "nvidia.ko*" 2>/dev/null | grep -q "nvidia"; then
                        has_k_nv=true
                    fi

                    local k_dracut_args=("${dracut_args[@]}")
                    if [ "${has_k_nv}" = "true" ]; then
                        if [ "${is_laptop}" -eq 1 ]; then
                            if [ "${HAS_INTEL}" = "true" ]; then
                                k_dracut_args+=(--force-drivers "i915 nvidia nvidia_modeset nvidia_uvm nvidia_drm")
                            elif [ "${HAS_AMD}" = "true" ]; then
                                k_dracut_args+=(--force-drivers "amdgpu nvidia nvidia_modeset nvidia_uvm nvidia_drm")
                            else
                                k_dracut_args+=(--add-drivers "nvidia nvidia_modeset nvidia_uvm nvidia_drm")
                            fi
                        else
                            k_dracut_args+=(--add-drivers "nvidia nvidia_modeset nvidia_uvm nvidia_drm")
                        fi
                    fi

                    sudo env -i PATH="/usr/local/sbin:/usr/local/bin:/sbin:/usr/sbin:/bin:/usr/bin" "${dracut_bin}" "${k_dracut_args[@]}" "${tmp_initrd}" "${skver}" >/dev/null 2>&1 &
                    pids+=("$!")
                    tmp_files+=("${tmp_initrd}")
                    out_files+=("${initrd_out}")
                done

                local spin_idx=0
                local dot_count=0
                local max_dots=8
                local joined_names
                if [ "${total_builds}" -gt 2 ]; then
                    joined_names="${total_builds} kernels (${pending_kvers[0]}, ...)"
                else
                    joined_names=$(IFS=', '; echo "${pending_kvers[*]}")
                fi

                while true; do
                    local any_running=false
                    for pid in "${pids[@]}"; do
                        if kill -0 "${pid}" 2>/dev/null; then
                            any_running=true
                            break
                        fi
                    done
                    [ "${any_running}" = "true" ] || break

                    local spin_char="${spinner_frames[spin_idx % ${#spinner_frames[@]}]}"
                    local dots=""
                    for ((d=0; d<dot_count; d++)); do
                        dots+=" ."
                    done

                    if [ "${kver}" = "TARGETED_PIPELINE" ]; then
                        printf "\r  \033[1;36m[3/5]\033[0m \033[1mDracut Initramfs Generation\033[0m  : %s Building in parallel (%s)%s\033[K" \
                            "${spin_char}" "${joined_names}" "${dots}"
                    else
                        printf "\r:: Generating Dracut initramfs in parallel (%s) %s%s\033[K" \
                            "${joined_names}" "${spin_char}" "${dots}"
                    fi

                    spin_idx=$(( spin_idx + 1 ))
                    dot_count=$(( (dot_count + 1) % (max_dots + 1) ))
                    sleep 0.35
                done

                for ((i=0; i<total_builds; i++)); do
                    local skver="${pending_kvers[i]}"
                    local tmp_initrd="${tmp_files[i]}"
                    local initrd_out="${out_files[i]}"
                    local pid="${pids[i]}"
                    wait "${pid}" 2>/dev/null || true

                    local img_sz=0
                    if [ -f "${tmp_initrd}" ]; then
                        img_sz=$(stat -c%s "${tmp_initrd}" 2>/dev/null || echo 0)
                    fi
                    if [ "${img_sz}" -gt 5000000 ]; then
                        sudo mv -f "${tmp_initrd}" "${initrd_out}"
                        sudo chmod 600 "${initrd_out}" 2>/dev/null || true
                        sudo rm -f "/boot/initrd-${skver}.img" "/boot/initrd-${skver}.gz" "/boot/initrd-${skver}" 2>/dev/null || true
                        pipeline_generated+=("${skver}")
                    else
                        log_warn "Generated Dracut image ${initrd_out} is unexpectedly small (${img_sz} bytes)."
                        sudo rm -f "${tmp_initrd}" 2>/dev/null || true
                    fi
                done
            else
                # Sequential generation with live ticker
                for ((i=0; i<total_builds; i++)); do
                    local single_kver="${pending_kvers[i]}"
                    local initrd_out="/boot/initramfs-${single_kver}.img"
                    local tmp_initrd="/tmp/dracut-${single_kver}-$$.img"
                    sudo rm -f "${tmp_initrd}" 2>/dev/null || true

                    local has_k_nv=false
                    if find "/lib/modules/${single_kver}" "/usr/lib/modules/${single_kver}" -name "nvidia.ko*" 2>/dev/null | grep -q "nvidia"; then
                        has_k_nv=true
                    fi

                    local k_dracut_args=("${dracut_args[@]}")
                    if [ "${has_k_nv}" = "true" ]; then
                        if [ "${is_laptop}" -eq 1 ]; then
                            if [ "${HAS_INTEL}" = "true" ]; then
                                k_dracut_args+=(--force-drivers "i915 nvidia nvidia_modeset nvidia_uvm nvidia_drm")
                            elif [ "${HAS_AMD}" = "true" ]; then
                                k_dracut_args+=(--force-drivers "amdgpu nvidia nvidia_modeset nvidia_uvm nvidia_drm")
                            else
                                k_dracut_args+=(--add-drivers "nvidia nvidia_modeset nvidia_uvm nvidia_drm")
                            fi
                        else
                            k_dracut_args+=(--add-drivers "nvidia nvidia_modeset nvidia_uvm nvidia_drm")
                        fi
                    fi

                    sudo env -i PATH="/usr/local/sbin:/usr/local/bin:/sbin:/usr/sbin:/bin:/usr/bin" "${dracut_bin}" "${k_dracut_args[@]}" "${tmp_initrd}" "${single_kver}" >/dev/null 2>&1 &
                    local dracut_pid=$!

                    local spin_idx=0
                    local dot_count=0
                    local max_dots=8

                    while kill -0 "${dracut_pid}" 2>/dev/null; do
                        local spin_char="${spinner_frames[spin_idx % ${#spinner_frames[@]}]}"
                        local dots=""
                        for ((d=0; d<dot_count; d++)); do
                            dots+=" ."
                        done

                        if [ "${kver}" = "TARGETED_PIPELINE" ]; then
                            printf "\r  \033[1;36m[3/5]\033[0m \033[1mDracut Initramfs Generation\033[0m  : %s Building [%d/%d] (%s)%s\033[K" \
                                "${spin_char}" "$(( i + 1 ))" "${total_builds}" "${single_kver}" "${dots}"
                        else
                            printf "\r:: Generating Dracut initramfs [%d/%d] (%s) %s%s\033[K" \
                                "$(( i + 1 ))" "${total_builds}" "${single_kver}" "${spin_char}" "${dots}"
                        fi

                        spin_idx=$(( spin_idx + 1 ))
                        dot_count=$(( (dot_count + 1) % (max_dots + 1) ))
                        sleep 0.35
                    done
                    wait "${dracut_pid}" 2>/dev/null || true

                    local img_sz=0
                    if [ -f "${tmp_initrd}" ]; then
                        img_sz=$(stat -c%s "${tmp_initrd}" 2>/dev/null || echo 0)
                    fi
                    if [ "${img_sz}" -gt 5000000 ]; then
                        sudo mv -f "${tmp_initrd}" "${initrd_out}"
                        sudo chmod 600 "${initrd_out}" 2>/dev/null || true
                        sudo rm -f "/boot/initrd-${single_kver}.img" "/boot/initrd-${single_kver}.gz" "/boot/initrd-${single_kver}" 2>/dev/null || true
                        pipeline_generated+=("${single_kver}")
                    else
                        log_warn "Generated Dracut image ${initrd_out} is unexpectedly small (${img_sz} bytes)."
                        sudo rm -f "${tmp_initrd}" 2>/dev/null || true
                    fi
                done
            fi

            # Clean orphaned initramfs images
            while IFS= read -r img; do
                [ -n "${img}" ] || continue
                local img_kver
                img_kver=$(basename "${img}" | sed -e 's/^initramfs-//' -e 's/\.img$//')
                if [ ! -d "/lib/modules/${img_kver}" ] && [ ! -d "/usr/lib/modules/${img_kver}" ]; then
                    sudo rm -f "${img}" 2>/dev/null || true
                fi
            done < <(sudo find /boot -maxdepth 1 -name "initramfs-*.img" 2>/dev/null || true)

            if [ "${kver}" = "TARGETED_PIPELINE" ]; then
                if [ "${#pipeline_generated[@]}" -gt 0 ]; then
                    local joined
                    joined=$(IFS=', '; echo "${pipeline_generated[*]}")
                    printf "\r  \033[1;36m[3/5]\033[0m \033[1mDracut Initramfs Generation\033[0m  : \033[1;32mGenerated %d fresh image(s) (%s)\033[0m\033[K\n" "${#pipeline_generated[@]}" "${joined}"
                else
                    printf "\r  \033[1;36m[3/5]\033[0m \033[1mDracut Initramfs Generation\033[0m  : \033[1;32mAll installed images are up to date\033[0m\033[K\n"
                fi
            fi

            return 0
        else
            local cur_loc
            cur_loc=$(get_active_locale 2>/dev/null || echo "en")
            local spinner_frames=()
            if [[ "${cur_loc}" =~ (en-ca|ca) ]]; then
                spinner_frames=($'\033[2;31m🍁\033[0m' $'\033[1;31m🍁\033[0m' $'\033[1;37m🍁\033[0m' $'\033[1;31m🍁\033[0m')
            elif [[ "${cur_loc}" =~ radical ]]; then
                spinner_frames=($'\033[2;33m⚡\033[0m' $'\033[1;33m⚡\033[0m' $'\033[1;37m⚡\033[0m' $'\033[1;33m✨\033[0m')
            else
                spinner_frames=('⏳' '⌛')
            fi

            local k_dracut_args=("${dracut_args[@]}")
            local has_k_nv=false
            if find "/lib/modules/${kver}" "/usr/lib/modules/${kver}" -name "nvidia.ko*" 2>/dev/null | grep -q "nvidia"; then
                has_k_nv=true
            fi
            if [ "${has_k_nv}" = "true" ]; then
                if [ "${is_laptop}" -eq 1 ]; then
                    if [ "${HAS_INTEL}" = "true" ]; then
                        k_dracut_args+=(--force-drivers "i915 nvidia nvidia_modeset nvidia_uvm nvidia_drm")
                    elif [ "${HAS_AMD}" = "true" ]; then
                        k_dracut_args+=(--force-drivers "amdgpu nvidia nvidia_modeset nvidia_uvm nvidia_drm")
                    else
                        k_dracut_args+=(--add-drivers "nvidia nvidia_modeset nvidia_uvm nvidia_drm")
                    fi
                else
                    k_dracut_args+=(--add-drivers "nvidia nvidia_modeset nvidia_uvm nvidia_drm")
                fi
            fi

            local initrd_out="/boot/initramfs-${kver}.img"
            local tmp_initrd="/tmp/dracut-${kver}-$$.img"
            sudo rm -f "${tmp_initrd}" 2>/dev/null || true

            sudo env -i PATH="/usr/local/sbin:/usr/local/bin:/sbin:/usr/sbin:/bin:/usr/bin" "${dracut_bin}" "${k_dracut_args[@]}" "${tmp_initrd}" "${kver}" >/dev/null 2>&1 &
            local dracut_pid=$!
            local spin_idx=0
            local dot_count=0
            local max_dots=8

            while kill -0 "${dracut_pid}" 2>/dev/null; do
                local spin_char="${spinner_frames[spin_idx % ${#spinner_frames[@]}]}"
                local dots=""
                for ((d=0; d<dot_count; d++)); do
                    dots+=" ."
                done

                printf "\r:: Generating Dracut initramfs (%s) %s%s\033[K" \
                    "${kver}" "${spin_char}" "${dots}"

                spin_idx=$(( spin_idx + 1 ))
                dot_count=$(( (dot_count + 1) % (max_dots + 1) ))
                sleep 0.35
            done
            wait "${dracut_pid}" 2>/dev/null || true

            local img_sz=0
            if [ -f "${tmp_initrd}" ]; then
                img_sz=$(stat -c%s "${tmp_initrd}" 2>/dev/null || echo 0)
            fi
            if [ "${img_sz}" -gt 5000000 ]; then
                sudo mv -f "${tmp_initrd}" "${initrd_out}"
                sudo chmod 600 "${initrd_out}" 2>/dev/null || true
                sudo rm -f "/boot/initrd-${kver}.img" "/boot/initrd-${kver}.gz" "/boot/initrd-${kver}" 2>/dev/null || true
                printf "\r\033[K"
                log_success "Dracut initramfs generated: ${initrd_out} (${img_sz} bytes)"
                return 0
            else
                sudo rm -f "${tmp_initrd}" 2>/dev/null || true
                printf "\r\033[K"
                log_warn "Generated Dracut image ${initrd_out} is unexpectedly small (${img_sz} bytes). Preserving existing initrd backup."
                return 0
            fi
        fi
    else
        # Legacy Slackware mkinitrd fallback
        if [ "${kver}" = "ALL" ] || [ "${kver}" = "TARGETED" ]; then
            local gen_script
            gen_script=$(command -v mkinitrd_command_generator.sh 2>/dev/null || echo "/sbin/mkinitrd_command_generator.sh")
            if [ "${kver}" = "ALL" ] && [ -x "${gen_script}" ]; then
                log_info "Regenerating mkinitrd images using Slackware generator..."
                sudo bash <("${gen_script}") 2>/dev/null || true
            elif [ -d "/lib/modules" ]; then
                for kdir in /lib/modules/*; do
                    [ -d "${kdir}" ] || continue
                    local single_kver
                    single_kver=$(basename "${kdir}")
                    if [ "${kver}" = "TARGETED" ]; then
                        local initrd_out="/boot/initrd-${single_kver}.gz"
                        sudo test -f "${initrd_out}" || initrd_out="/boot/initrd-${single_kver}.img"
                        if sudo test -f "${initrd_out}"; then
                            if sudo test -f "/boot/vmlinuz-${single_kver}" && sudo test "${initrd_out}" -nt "/boot/vmlinuz-${single_kver}"; then
                                log_info "Legacy initrd for kernel ${single_kver} is up to date (${initrd_out}). Skipping."
                                continue
                            fi
                        fi
                    fi
                    generate_legacy_mkinitrd "${single_kver}"
                done
            fi
            log_success "mkinitrd generation completed for all kernels."
            return 0
        else
            generate_legacy_mkinitrd "${kver}"
        fi
    fi
}

generate_legacy_mkinitrd() {
    local kver="$1"
    local initrd_out="/boot/initrd-${kver}.gz"
    validate_privileges
    probe_gpu_hardware

    if command -v ensure_mkinitrd_staging_configured >/dev/null 2>&1; then
        if [ "$(findmnt -n -o FSTYPE /boot 2>/dev/null || true)" = "vfat" ]; then
            ensure_mkinitrd_staging_configured
        fi
    fi

    log_info "Generating legacy mkinitrd for kernel: ${kver}..."

    local ucode_opt=""
    if [ -f "/boot/intel-ucode.cpio" ]; then
        ucode_opt="-u /boot/intel-ucode.cpio"
    elif [ -f "/boot/amd-ucode.cpio" ]; then
        ucode_opt="-u /boot/amd-ucode.cpio"
    fi

    local root_dev root_fs root_uuid root_flags
    IFS='|' read -r root_dev root_fs root_uuid root_flags <<< "$(detect_root_filesystem_details)"
    log_info "Detected root device: ${root_dev} (${root_fs})"

    local base_modules="${root_fs}:nvme:xhci-pci:ahci:sd_mod"
    if [ "${root_fs}" = "btrfs" ]; then
        base_modules="btrfs:zstd:crc32c:nvme:xhci-pci"
    elif [ "${root_fs}" = "ext4" ]; then
        base_modules="ext4:crc32c:nvme:xhci-pci:ahci:sd_mod"
    elif [ "${root_fs}" = "xfs" ]; then
        base_modules="xfs:crc32c:nvme:xhci-pci:ahci:sd_mod"
    elif [ "${root_fs}" = "f2fs" ]; then
        base_modules="f2fs:crc32:nvme:xhci-pci:ahci:sd_mod"
    fi

    local nvidia_modules=""
    if [ "${HAS_NVIDIA}" = "true" ] || [ -d "/lib/modules/${kver}/kernel/drivers/video" ]; then
        nvidia_modules=":nvidia:nvidia-modeset:nvidia-uvm:nvidia-drm"
        log_info "NVIDIA hardware identified. Bundling video modules into initrd."
    fi

    local combined_modules="${base_modules}${nvidia_modules}"

    local root_param="${root_dev}"
    if [ -n "${root_uuid}" ]; then
        root_param="UUID=${root_uuid}"
    fi

    local tmp_tree="/tmp/initrd-tree-${kver}-$$"
    local tmp_out="/tmp/initrd-${kver}-$$.gz"
    sudo rm -rf "${tmp_tree}" "${tmp_out}" 2>/dev/null || true

    if ! sudo "${MKINITRD_CMD}" -c -k "${kver}" -s "${tmp_tree}" -m "${combined_modules}" -f "${root_fs}" -r "${root_param}" ${ucode_opt} -o "${tmp_out}"; then
        log_warn "Standard mkinitrd completed with warnings. Running fallback..."
        sudo "${MKINITRD_CMD}" -c -k "${kver}" -s "${tmp_tree}" -o "${tmp_out}" 2>/dev/null || true
    fi

    if [ -f "${tmp_out}" ] && [ -s "${tmp_out}" ]; then
        sudo mv -f "${tmp_out}" "${initrd_out}"
        sudo chmod 600 "${initrd_out}" 2>/dev/null || true
        log_success "Initrd generated: ${initrd_out}"
    fi
    sudo rm -rf "${tmp_tree}" "${tmp_out}" 2>/dev/null || true
}

# Backwards compatibility alias
generate_cachy_initrd() {
    generate_kernel_initramfs "$1"
}
