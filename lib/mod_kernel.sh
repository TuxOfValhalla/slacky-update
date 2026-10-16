#!/usr/bin/env bash
# --- [ CACHYOS KERNEL & INITRD ENGINE ] ---

set -euo pipefail

# --- [ ARCHITECTURE DETECTION ] ---
detect_cpu_tier() {
    # 6A-118: SpiderSense answer first (same rules); this copy is the fallback
    if command -v ss_hw_load >/dev/null 2>&1 && ss_hw_load && [ -n "${HW_CPU_TIER:-}" ]; then echo "${HW_CPU_TIER}"; return 0; fi
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
    # 6A-118: SpiderSense answer first (a mouse or headset battery no longer makes a laptop); this copy is the fallback
    if command -v ss_hw_load >/dev/null 2>&1 && ss_hw_load; then [ "${HW_LAPTOP}" = "true" ]; return; fi
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
    for d in ['/var/cache/slacky-update', os.path.expanduser('~/.cache/slacky-update')]:
        try:
            os.makedirs(d, exist_ok=True)
            test_f = os.path.join(d, '.write_test')
            with open(test_f, 'w') as f: f.write('1')
            os.remove(test_f)
            return d
        except Exception:
            continue
    # 6A-17: no fixed /tmp fallback (predictable path, lost on reboot); a private temp dir instead
    return __import__('tempfile').mkdtemp(prefix='slacky-update-cache.')

cache_dir = get_cache_dir()

def fetch_url_cached(url, cdir, ttl=300):
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

check_all_installed_cachyos_flavors_fast() {
    local installed_flavors="${1:-}"
    if [ -z "${installed_flavors}" ]; then
        installed_flavors=$(get_installed_cachyos_flavors 2>/dev/null || echo "")
    fi
    [ -n "${installed_flavors}" ] || return 0

    local tier
    tier=$(detect_cpu_tier)
    local repo_urls=()

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

    python3 - "${tier}" "${installed_flavors}" "${repo_urls[@]}" << 'PYBATCHKERNEL'
import re, sys, os, time, urllib.request, hashlib

tier = sys.argv[1]
flavors = [f.strip() for f in sys.argv[2].split() if f.strip()]
tier_urls = sys.argv[3:]

def get_cache_dir():
    for d in ['/var/cache/slacky-update', os.path.expanduser('~/.cache/slacky-update')]:
        try:
            os.makedirs(d, exist_ok=True)
            test_f = os.path.join(d, '.write_test')
            with open(test_f, 'w') as f: f.write('1')
            os.remove(test_f)
            return d
        except Exception:
            continue
    # 6A-17: no fixed /tmp fallback (predictable path, lost on reboot); a private temp dir instead
    return __import__('tempfile').mkdtemp(prefix='slacky-update-cache.')

cache_dir = get_cache_dir()

def fetch_url_cached(url, cdir, ttl=300):
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

def parse_ver_key(v_str):
    return [int(x) for x in re.findall(r'\d+', v_str)]

for flv in flavors:
    if flv == 'zen':
        r_urls = ['https://geo.mirror.pkgbuild.com/extra/os/x86_64/']
        k_pref, h_pref, nv_pref, r8125_pref = 'linux-zen', 'linux-zen-headers', 'NONE', 'NONE'
    elif flv == 'arch':
        r_urls = ['https://geo.mirror.pkgbuild.com/core/os/x86_64/']
        k_pref, h_pref, nv_pref, r8125_pref = 'linux', 'linux-headers', 'NONE', 'NONE'
    else:
        r_urls = tier_urls
        k_pref = f'linux-cachyos-{flv}' if flv != 'standard' else 'linux-cachyos'
        h_pref = f'{k_pref}-headers'
        nv_pref = f'{k_pref}-nvidia-open'
        r8125_pref = f'{k_pref}-r8125'

    matched = False
    for u in r_urls:
        html = fetch_url_cached(u, cache_dir)
        if not html:
            continue
        k_matches = re.findall(r'href=[\'\"]?(' + re.escape(k_pref) + r'-([0-9]+\.[0-9]+[a-zA-Z0-9\._]*-[0-9]+)[^\'\">]*\.pkg\.tar\.zst)', html)
        h_matches = re.findall(r'href=[\'\"]?(' + re.escape(h_pref) + r'-([0-9]+\.[0-9]+[a-zA-Z0-9\._]*-[0-9]+)[^\'\">]*\.pkg\.tar\.zst)', html)
        nv_matches = re.findall(r'href=[\'\"]?(' + re.escape(nv_pref) + r'-([0-9]+\.[0-9]+[a-zA-Z0-9\._]*-[0-9]+)[^\'\">]*\.pkg\.tar\.zst)', html) if nv_pref != 'NONE' else []
        r8125_matches = re.findall(r'href=[\'\"]?(' + re.escape(r8125_pref) + r'-([0-9]+\.[0-9]+[a-zA-Z0-9\._]*-[0-9]+)[^\'\">]*\.pkg\.tar\.zst)', html) if r8125_pref != 'NONE' else []

        if k_matches and h_matches:
            avail_vers = sorted(list(set(m[1] for m in k_matches)), key=parse_ver_key, reverse=True)
            latest_ver = avail_vers[0]
            k_pkg = next(m[0] for m in k_matches if m[1] == latest_ver)
            h_pkg = next(m[0] for m in h_matches if m[1] == latest_ver)
            nv_url = 'NONE'
            if nv_matches:
                try:
                    nv_pkg = next(m[0] for m in nv_matches if m[1] == latest_ver)
                    nv_url = f'{u}{nv_pkg}'
                except StopIteration:
                    pass
            r8125_url = 'NONE'
            if r8125_matches:
                try:
                    r8125_pkg = next(m[0] for m in r8125_matches if m[1] == latest_ver)
                    r8125_url = f'{u}{r8125_pkg}'
                except StopIteration:
                    pass
            print(f'{flv}|{latest_ver}|{u}{k_pkg}|{u}{h_pkg}|{nv_url}|{r8125_url}')
            matched = True
            break
    if not matched:
        print(f'{flv}|NONE|NONE|NONE|NONE|NONE')
PYBATCHKERNEL
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
        # 6A-130: an unreadable card model (UNKNOWN) is refused too
        if [ "${gpu_arch}" != "MODERN" ]; then
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
    # 6A-98: inside a deferred run the old kernels are removed only after the boot chain has a verified menu without
    # them (done by the owner of the deferral); removing them here left the live menu pointing at deleted files
    if [ "${DEFER_BOOT_SYNC:-0}" != "1" ] && command -v purge_old_cachyos_kernels >/dev/null 2>&1; then
        purge_old_cachyos_kernels
    fi

    # Smart Prompt: Check if system is eligible for pure CachyOS transition
    # 6A-103: never in the middle of a full update (it removes kernels before the menu is rebuilt); asked from the menu
    if [ "${SLACKY_UPDATE_RUNNING:-0}" = "1" ]; then
        { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] SpiderSense: stock kernel removal is offered from the kernel menu, not during a full update" >> "${LOG_FILE}"; } 2>/dev/null || true
    else
        prompt_stock_kernel_removal_if_eligible "${flavor}"
    fi
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

    local was_boot_sync_deferred="${DEFER_BOOT_SYNC:-0}"
    export DEFER_BOOT_SYNC=1
    for flv in "${flavors_to_update[@]}"; do
        deploy_cachyos_kernel_flavor "${flv}"
    done

    log_info "⚡ Running Single-Pass Post-Installation Pipeline (DKMS, Dracut, MOK & Limine)..."
    if command -v dkms >/dev/null 2>&1; then
        build_dkms_modules_for_all_kernels
    fi

    if [ "${HAS_NVIDIA}" = "true" ]; then
        if command -v ensure_cachyos_nvidia_duties >/dev/null 2>&1; then
            # 6A-132: an honest failure must not stop the image and boot-menu steps below
            ensure_cachyos_nvidia_duties || log_warn "The NVIDIA driver could not be confirmed for every kernel; see the log."
        fi
    fi

    # Generate initramfs for updated installed kernels unless deferred to pipeline matrix
    if [ "${was_boot_sync_deferred}" != "1" ]; then
        local target_flavors=()
        if [ ${#flavors_to_update[@]} -gt 0 ]; then
            target_flavors=("${flavors_to_update[@]}")
        else
            read -r -a target_flavors <<< "$(get_installed_cachyos_flavors 2>/dev/null || echo "")"
        fi

        local ss_built=()
        for flv in "${target_flavors[@]}"; do
            [ -n "${flv}" ] || continue
            local kver_full
            kver_full=$(get_installed_cachyos_flavor_version "${flv}" 2>/dev/null || echo "")
            if [ -n "${kver_full}" ] && [ "${kver_full}" != "NONE" ]; then
                # Resolve exact kernel directory under /usr/lib/modules
                local mod_dir=""
                if [ "${flv}" = "standard" ]; then
                    mod_dir=$(find /usr/lib/modules -maxdepth 1 -type d -name "*-cachyos" ! -name "*-bore" ! -name "*-lts" ! -name "*-rc*" ! -name "*-hardened" 2>/dev/null | sort -V | tail -n 1 || true)
                else
                    mod_dir=$(find /usr/lib/modules -maxdepth 1 -type d -name "*${flv}*" 2>/dev/null | sort -V | tail -n 1 || true)
                fi
                if [ -n "${mod_dir}" ] && [ -d "${mod_dir}" ]; then
                    generate_kernel_initramfs "$(basename "${mod_dir}")"
                    ss_built+=("$(basename "${mod_dir}")")
                fi
            fi
        done
        # 6A-97: kernels whose NVIDIA module changed above while DEFER_BOOT_SYNC was set get their one image build here
        local ss_purge_now ok_k
        ss_purge_now=" $(ss_purge_set | tr '\n' ' ') "
        for ok_k in "${SS_INITRD_ORDERS[@]:-}"; do
            [ -n "${ok_k}" ] || continue
            { [ -d "/lib/modules/${ok_k}" ] || [ -d "/usr/lib/modules/${ok_k}" ]; } || continue
            case " ${ss_built[*]:-} " in *" ${ok_k} "*) continue ;; esac
            case "${ss_purge_now}" in *" ${ok_k} "*) continue ;; esac
            generate_kernel_initramfs "${ok_k}"
        done
        SS_INITRD_ORDERS=()
    fi

    if [ "${was_boot_sync_deferred}" = "1" ]; then
        log_info "Bootloader sync & Secure Boot reseal deferred to final post-upgrade hardening matrix."
    else
        unset DEFER_BOOT_SYNC || true
        if command -v enforce_secure_boot_armor >/dev/null 2>&1; then
            enforce_secure_boot_armor
        fi
        # 6A-98: with Limine the menu is built from the kernels that stay, and the old ones are removed only after that
        # menu was enrolled and verified. Without Limine the old order stays (GRUB scans /boot, so remove first).
        if [ "$(is_limine_installed 2>/dev/null || echo false)" = "true" ]; then
            export SS_KEEP_SET_MENU=1
            export SLACKY_LIMINE_SEALED=0
            sync_bootloader_configuration
            if [ "${SLACKY_LIMINE_SEALED:-0}" = "1" ] && command -v purge_old_cachyos_kernels >/dev/null 2>&1; then
                purge_old_cachyos_kernels --no-sync
            fi
            unset SS_KEEP_SET_MENU || true
        else
            if command -v purge_old_cachyos_kernels >/dev/null 2>&1; then
                purge_old_cachyos_kernels --no-sync
            fi
            sync_bootloader_configuration
        fi
    fi

    log_success "CachyOS kernel upgrade completed (Single-Pass Batch)."
}

remove_stock_slackware_kernels() {
    validate_privileges

    # 6A-133 (L2 M1): never while a stock kernel is running, and only after a CachyOS kernel has booted successfully
    # (the running kernel is one); otherwise the running kernel's modules would be gone before anything else was proven.
    local running_k
    running_k=$(uname -r)
    if [[ ! "${running_k}" =~ cachyos ]]; then
        log_error "The stock kernels were kept because this computer is not running a CachyOS kernel; restart into one first."
        return 1
    fi

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
                for icand in [f'/boot/initramfs-{ksuffix}.img', f'/boot/initrd-{ksuffix}.img', f'/boot/initramfs-{ksuffix}']:
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
    local rm_failed=0
    for pkg in "${stock_pkgs[@]}"; do
        local installed
        installed=$(ls "${PKGDB_DIR:-/var/log/packages}"/${pkg}-* 2>/dev/null || true)
        if [ -n "${installed}" ]; then
            for p in ${installed}; do
                local base_p
                base_p=$(basename "${p}")
                # Save log package metadata to backup directory for offline recovery tracking
                sudo cp -f "${p}" "${backup_dir}/${base_p}" 2>/dev/null || true
                log_info "Removing stock Slackware package: ${base_p}..."
                sudo "${PKG_REMOVE_CMD}" "${base_p}" 2>/dev/null || rm_failed=1
            done
        fi
    done

    # 6A-133: no success message and no blacklist entry when removepkg failed
    if [ "${rm_failed}" -eq 1 ]; then
        log_error "Some stock kernel packages could not be removed; the boot menu is refreshed, but nothing was blacklisted."
        sync_bootloader_configuration "$(uname -r)"
        return 1
    fi

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

    log_info "Updating slackpkg repository index..."
    run_slackpkg update || true

    log_info "Installing official Slackware kernel-generic and kernel-modules..."
    run_slackpkg -batch=on -default_answer=y install kernel-generic kernel-modules || true

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
    # 6A-133: not offered until a CachyOS kernel has booted (the removal itself refuses it too)
    [[ "$(uname -r)" =~ cachyos ]] || return 0

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
            remove_stock_slackware_kernels || true
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
        done <<< "${kernels_raw}"

        local exit_idx=$((idx + 1))
        local exit_label
        exit_label="$(_ CACHY_PICKER_EXIT | sed -E 's/^[0-9]+\.\s*//')"

        local tui_script="${REPO_ROOT:-}/lib/slacky_tui.py"
        [ ! -f "${tui_script}" ] && [ -f "${SCRIPT_DIR}/../lib/slacky_tui.py" ] && tui_script="${SCRIPT_DIR}/../lib/slacky_tui.py"
        [ ! -f "${tui_script}" ] && [ -f "/usr/share/slacky-update/lib/slacky_tui.py" ] && tui_script="/usr/share/slacky-update/lib/slacky_tui.py"

        local sel=""
        if [ -t 0 ] && [ -t 1 ] && [ -f "${tui_script}" ] && command -v python3 >/dev/null 2>&1; then
            local items_json
            items_json=$(python3 -c "
import json, sys
raw_lines = sys.argv[1].strip().splitlines()
exit_lbl = sys.argv[2]
items = []
for i, line in enumerate(raw_lines, start=1):
    parts = line.split('|')
    if len(parts) >= 4:
        k_name, k_type, k_sz, k_act = parts[0], parts[1], parts[2], parts[3]
        badge = '[ACTIVE - CANNOT REMOVE]' if k_act == '1' else ('[STOCK]' if k_type == 'stock' else '[CACHY]')
        items.append({
            'id': str(i),
            'label': f'{i}. {k_name} ({k_sz})',
            'badge': badge
        })
exit_idx = len(items) + 1
items.append({
    'id': str(exit_idx),
    'label': f'{exit_idx}. {exit_lbl}'
})
print(json.dumps(items))
" "${kernels_raw}" "${exit_label}" 2>/dev/null || echo "[]")

            if [ -n "${items_json}" ] && [ "${items_json}" != "[]" ]; then
                sel=$(python3 "${tui_script}" --mode kernel-prune --items "${items_json}" || true)
            fi
        fi

        if [ -z "${sel}" ]; then
            echo ""
            echo -e "${CYAN}============================================================${RESET}"
            echo -e "${YELLOW}${BOLD}$(_ KERNEL_REMOVAL_TITLE)${RESET}"
            echo -e "${CYAN}============================================================${RESET}"

            for ((i=1; i<=idx; i++)); do
                local k_name="${k_list[$((i-1))]}"
                local k_sz="${k_sizes[$((i-1))]}"
                local k_act="${k_active[$((i-1))]}"
                local k_type="${k_types[$((i-1))]}"
                local status_badge=""
                if [ "${k_act}" -eq 1 ]; then
                    status_badge="${GREEN}${BOLD}[ACTIVE - CANNOT REMOVE]${RESET}"
                elif [ "${k_type}" = "stock" ]; then
                    status_badge="${BLUE}[STOCK]${RESET}"
                else
                    status_badge="${CYAN}[CACHY]${RESET}"
                fi
                echo -e "  \033[1;33m${i}.\033[0m ${k_name} (${k_sz}) ${status_badge}"
            done

            echo -e "  \033[1;33m${exit_idx}.\033[0m ${exit_label}"
            echo ""
            echo -n "$(_ SELECT_OPERATION_RANGE range="1-${exit_idx}") "
            read -r sel || sel="${exit_idx}"
        fi

        if [ "${sel}" = "${exit_idx}" ] || [ -z "${sel}" ] || [ "${sel}" = "q" ] || [ "${sel}" = "Q" ]; then
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
                remove_stock_slackware_kernels || true
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

        dkms_purge_kernel "${chosen_k}"

        log_success "Kernel ${chosen_k} removed successfully."

        # Check if no CachyOS kernels remain
        local remaining_cachy_now
        remaining_cachy_now=$(get_installed_cachyos_flavors)

        if [ -z "${remaining_cachy_now}" ] && [ "${has_stock_now}" -eq 0 ]; then
            log_warn "No kernels remain! Automatically restoring official Slackware stock kernel..."
            restore_stock_slackware_kernels
            if [ "${HAS_NVIDIA}" = "true" ] && command -v rollback_cachyos_to_slackware_nvidia >/dev/null 2>&1; then
                log_info "Migrating NVIDIA graphics driver to native Slackware standalone driver..."
                rollback_cachyos_to_slackware_nvidia || true
            fi
        elif [ -z "${remaining_cachy_now}" ] && [ "${has_stock_now}" -eq 1 ]; then
            if [ "${HAS_NVIDIA}" = "true" ] && command -v rollback_cachyos_to_slackware_nvidia >/dev/null 2>&1; then
                log_info "No CachyOS kernels remain. Migrating NVIDIA graphics driver to native Slackware standalone driver..."
                rollback_cachyos_to_slackware_nvidia || true
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

        local tui_script="${REPO_ROOT:-}/lib/slacky_tui.py"
        [ ! -f "${tui_script}" ] && [ -f "${SCRIPT_DIR}/../lib/slacky_tui.py" ] && tui_script="${SCRIPT_DIR}/../lib/slacky_tui.py"
        [ ! -f "${tui_script}" ] && [ -f "/usr/share/slacky-update/lib/slacky_tui.py" ] && tui_script="/usr/share/slacky-update/lib/slacky_tui.py"

        local pchoice=""
        if [ -t 0 ] && [ -t 1 ] && [ -f "${tui_script}" ] && command -v python3 >/dev/null 2>&1; then
            local badges_json
            badges_json=$(python3 -c "import json, sys
data = {
    'standard': sys.argv[1],
    'bore': sys.argv[2],
    'lto': sys.argv[3],
    'eevdf': sys.argv[4],
    'bmq': sys.argv[5],
    'deckify': sys.argv[6],
    'rt-bore': sys.argv[7],
    'rc': sys.argv[8],
    'lts': sys.argv[9],
    'zen': sys.argv[10],
    'arch': sys.argv[11]
}
print(json.dumps(data))" "${st_tag}" "${bo_tag}" "${lto_tag}" "${eevdf_tag}" "${bmq_tag}" "${deck_tag}" "${rtbore_tag}" "${rc_tag}" "${lts_tag}" "${zen_tag}" "${arch_tag}" 2>/dev/null || echo "{}")

            pchoice=$(python3 "${tui_script}" --mode kernel-picker --pkg-badges "${badges_json}" || true)
        fi

        if [ -z "${pchoice}" ]; then
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
            read -r pchoice || pchoice="12"
        fi

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
            12|[Qq])
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
    local tui_script="${REPO_ROOT:-}/lib/slacky_tui.py"
    [ ! -f "${tui_script}" ] && [ -f "${SCRIPT_DIR}/../lib/slacky_tui.py" ] && tui_script="${SCRIPT_DIR}/../lib/slacky_tui.py"
    [ ! -f "${tui_script}" ] && [ -f "/usr/share/slacky-update/lib/slacky_tui.py" ] && tui_script="/usr/share/slacky-update/lib/slacky_tui.py"

    while true; do
        local mchoice=""
        if [ -t 0 ] && [ -t 1 ] && [ -f "${tui_script}" ] && command -v python3 >/dev/null 2>&1; then
            mchoice=$(python3 "${tui_script}" --mode kernel-manage || true)
        fi

        if [ -z "${mchoice}" ]; then
            echo ""
            echo -e "${CYAN}============================================================${RESET}"
            echo -e "${YELLOW}${BOLD}$(_ KERNEL_MANAGE_SYSTEM_TITLE)${RESET}"
            echo -e "${CYAN}============================================================${RESET}"
            echo -e "  1. $(_ KERNEL_MANAGE_OPTION_REMOVE | sed -E 's/^[0-9]+\.\s*//')"
            echo -e "  2. $(_ KERNEL_MANAGE_OPTION_RESTORE | sed -E 's/^[0-9]+\.\s*//')"
            echo -e "  3. $(_ MOK_OPTION_RETURN | sed -E 's/^[0-9]+\.\s*//')"
            echo ""
            echo -n "$(_ SELECT_OPERATION_RANGE range="1-3") "
            read -r mchoice || mchoice="3"
        fi

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
            3|[Qq])
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
    local kver_full="${1:-$(uname -r 2>/dev/null || echo "")}"
    validate_privileges
    probe_gpu_hardware

    local required_params=""
    if [ "${HAS_NVIDIA}" = "true" ]; then
        required_params="nvidia_drm.modeset=1 nvidia_drm.fbdev=1 nvidia.NVreg_PreserveVideoMemoryAllocations=1"
    fi

    local root_res
    root_res=$(resolve_boot_root_cmd 2>/dev/null || echo "ERROR")
    if [ "${root_res}" = "ERROR" ] || [ -z "${root_res}" ]; then
        log_error "FATAL: Root filesystem device or UUID resolution failed! Aborting GRUB synchronization."
        return 1
    fi
    local root_cmd root_flags root_fs root_dev root_uuid
    IFS='|' read -r root_cmd root_flags root_fs root_dev root_uuid <<< "${root_res}"

    if [ -z "${root_cmd}" ] || [ "${root_cmd}" = "root=" ]; then
        log_error "FATAL: Empty or invalid root= parameter resolved! Aborting GRUB synchronization."
        return 1
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
            # 6A-8b: a failed enroll/sign is an error, not a warning (the live EFI is left as it was)
            if ! enroll_and_sign_limine; then
                lim_ok=false
                log_error "Limine enrollment or Secure Boot signing failed. Do not reboot; run: sudo slacky-update --sync-boot"
            fi
        fi
        if [ "${lim_ok}" = "true" ] && command -v verify_limine_seal >/dev/null 2>&1; then
            if ! verify_limine_seal; then
                lim_ok=false
                log_error "Limine seal check failed after the reseal. Do not reboot; run: sudo slacky-update --sync-boot"
            fi
        fi
        if [ "${lim_ok}" = "true" ]; then
            export SLACKY_LIMINE_SEALED=1
            local esp_path
            esp_path=$(detect_limine_esp_path 2>/dev/null || echo "/boot")
            log_success "Limine bootloader matrix: BLAKE2B enrolled & Secure Boot signed (${esp_path}/limine.conf)."
        fi
    fi

    # 3./4. ELILO and LILO: 6A-133 (LTS B7, L2 M6, L3 M3) hands-off. The old ELILO sync prompted even under cron, copied
    # onto the ESP with "cp -f || true" (no space check, no verify) and ran an "elilo" binary that does not exist. Now one
    # reminder line; the user runs lilo or eliloconfig, as stock Slackware expects.
    print_boot_loader_reminder
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

# 6A-8g: blocking space check before boot files are written. Kernels and initramfs images go to /boot, whatever
# filesystem that is (the root partition with GRUB, a small /boot partition, or the ESP with Limine). The ESP is only
# checked as well when Limine is in use AND it is a different filesystem, because Limine then gets its own copy.
# Better to stop before anything changes than to leave a cut-short kernel or initramfs (a cut-short file can still get
# a valid hash, and the old file is already gone by then).
largest_boot_initramfs_mb() {
    local b
    b=$(sudo find /boot -maxdepth 1 -type f \( -name 'initramfs-*' -o -name 'initrd*' \) -printf '%s\n' 2>/dev/null | sort -n | tail -n1)
    echo $(( ${b:-0} / 1048576 ))
}

# Margin scales with the system: max(16 MB, a quarter of the largest initramfs) (about 16 MB with small mkinitrd images)
boot_space_margin_mb() {
    local largest="${1:-0}" q
    q=$(( largest / 4 ))
    [ "${q}" -gt 16 ] && echo "${q}" || echo 16
}

# Kernels under /boot that have no initramfs/initrd yet (these need a full new image, the rest are overwritten in place)
count_kernels_without_initramfs() {
    local n=0 v k
    for v in $(sudo find /boot -maxdepth 1 -type f -name 'vmlinuz-*' -printf '%f\n' 2>/dev/null); do
        k="${v#vmlinuz-}"
        if ! sudo test -f "/boot/initramfs-${k}.img" && ! sudo test -f "/boot/initrd-${k}.gz" && ! sudo test -f "/boot/initrd-${k}.img"; then
            n=$((n + 1))
        fi
    done
    echo "${n}"
}

require_boot_space() {
    local need_mb="$1" what="${2:-boot files}" m free_kb free_mb
    local mounts=("/boot")
    if command -v is_limine_installed >/dev/null 2>&1 && [ "$(is_limine_installed 2>/dev/null)" = "true" ] \
        && command -v detect_limine_esp_path >/dev/null 2>&1; then
        local esp
        esp=$(detect_limine_esp_path 2>/dev/null || true)
        if [ -n "${esp}" ] && [ -d "${esp}" ] && [ "$(stat -c %d "${esp}" 2>/dev/null)" != "$(stat -c %d /boot 2>/dev/null)" ]; then
            mounts+=("${esp}")
        fi
    fi
    for m in "${mounts[@]}"; do
        free_kb=$(df -Pk "${m}" 2>/dev/null | awk 'NR==2 {print $4}')
        [ -n "${free_kb}" ] || continue
        free_mb=$(( free_kb / 1024 ))
        if [ "${free_mb}" -lt "${need_mb}" ]; then
            log_error "Not enough free space on ${m} for the ${what}: ${free_mb} MB free, ${need_mb} MB needed. Nothing was changed. Remove an old kernel and try again."
            return 1
        fi
    done
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

    # 6A-98: kernels slated for removal keep existing until after the boot chain; never build modules for them
    local ss_dying=""
    if command -v get_obsolete_cachyos_kernels >/dev/null 2>&1; then
        ss_dying=" $(get_obsolete_cachyos_kernels 2>/dev/null | tr '\n' ' ') "
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
        case "${ss_dying}" in *" ${kver} "*) continue ;; esac
        local has_precompiled_nvidia=false
        if find "/lib/modules/${kver}" "/usr/lib/modules/${kver}" -name "nvidia*.ko*" 2>/dev/null | grep -q "nvidia"; then
            has_precompiled_nvidia=true
        fi

        # Compiler & series detection for target kernel
        local is_clang_kernel=false
        if [ -f "/lib/modules/${kver}/build/.config" ] && grep -q '^CONFIG_CC_IS_CLANG=y' "/lib/modules/${kver}/build/.config" 2>/dev/null; then
            is_clang_kernel=true
        fi
        local is_lts_kernel=false
        if [[ "${kver}" =~ -lts ]]; then
            is_lts_kernel=true
        fi

        for mod_entry in "${dkms_modules[@]}"; do
            [ -n "${mod_entry}" ] || continue
            local m_name m_ver
            IFS='/' read -r m_name m_ver <<< "${mod_entry}"

            # Safety Shield: Never compile NVIDIA DKMS if:
            # 1. Kernel is an RC kernel (RC kernels require precompiled open modules only)
            # 2. Precompiled nvidia modules are already present in kernel tree
            # 3. Kernel already has an nvidia.ko matching m_ver
            # 4. Kernel is marked for retention exclusion / slated for deletion
            if [ "${m_name}" = "nvidia" ]; then
                if [[ "${kver}" =~ -rc ]] || [ "${has_precompiled_nvidia}" = "true" ]; then
                    continue
                fi
                if command -v get_obsolete_cachyos_kernels >/dev/null 2>&1; then
                    local obs_k
                    obs_k=$(get_obsolete_cachyos_kernels 2>/dev/null || true)
                    if [[ " ${obs_k} " =~ [[:space:]]${kver}[[:space:]] ]]; then
                        continue
                    fi
                fi
                local ex_mod
                ex_mod=$(find -L "/lib/modules/${kver}" "/usr/lib/modules/${kver}" -name "nvidia.ko*" 2>/dev/null | head -n 1 || true)
                if [ -n "${ex_mod}" ] && command -v get_nvidia_module_version >/dev/null 2>&1; then
                    local cur_nv_v
                    cur_nv_v=$(get_nvidia_module_version "${ex_mod}")
                    if [ "${cur_nv_v}" = "${m_ver}" ]; then
                        continue
                    fi
                fi
            fi

            # Check if already installed for this kernel
            if dkms status -m "${m_name}" -v "${m_ver}" -k "${kver}" 2>/dev/null | grep -q "installed"; then
                continue
            fi

            # Toolchain & compatibility guard: bcachefs requires GCC + modern in-tree Rust and cannot compile under Clang or on LTS series
            if [ "${m_name}" = "bcachefs" ] && { [ "${is_clang_kernel}" = "true" ] || [ "${is_lts_kernel}" = "true" ]; }; then
                if [ "${is_clang_kernel}" = "true" ]; then
                    log_info "$(_ DKMS_SKIPPED_CLANG mod="${m_name}" kver="${kver}" 2>/dev/null || echo "DKMS module ${m_name} skipped on ${kver} (requires GCC; kernel compiled with Clang)")"
                else
                    log_info "$(_ DKMS_SKIPPED_LTS mod="${m_name}" kver="${kver}" 2>/dev/null || echo "DKMS module ${m_name} skipped on ${kver} (incompatible with LTS kernel series)")"
                fi
                sudo dkms remove -m "${m_name}" -v "${m_ver}" -k "${kver}" --force >/dev/null 2>&1 || true
                continue
            fi

            log_info "Building DKMS module ${m_name} (v${m_ver}) for kernel ${kver}..."
            local build_out
            if ! build_out=$(sudo dkms build -m "${m_name}" -v "${m_ver}" -k "${kver}" 2>&1); then
                if echo "${build_out}" | grep -qE "BUILD_EXCLUSIVE|does not match this kernel"; then
                    log_info "$(_ DKMS_SKIPPED_INCOMPATIBLE mod="${m_name}" kver="${kver}" 2>/dev/null || echo "DKMS module ${m_name} skipped on ${kver} (incompatible with kernel version)")"
                else
                    log_warn "$(_ DKMS_BUILD_WARN mod="${m_name}" kver="${kver}" 2>/dev/null || echo "DKMS build warning for ${m_name} on ${kver}")"
                fi
                sudo dkms remove -m "${m_name}" -v "${m_ver}" -k "${kver}" --force >/dev/null 2>&1 || true
                continue
            fi
            sudo dkms install -m "${m_name}" -v "${m_ver}" -k "${kver}" >/dev/null 2>&1 || {
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
    # 6A-8f: the matching NVIDIA module and r8125 packages are extracted as root into / and then MOK-signed; their
    # .sig was downloaded but never checked. Same fail-closed rule as kernel and headers, before anything is written.
    local extra_pkg
    for extra_pkg in "${nv_file}" "${r8125_file}"; do
        [ -n "${extra_pkg}" ] && [ -f "${extra_pkg}" ] || continue
        if ! verify_cachyos_gpg_signature "${extra_pkg}" "${extra_pkg}.sig"; then
            log_error "GPG signature check failed for $(basename "${extra_pkg}")! Aborting kernel deployment."
            rm -f "${k_file}" "${h_file}" "${k_sig_file}" "${h_sig_file}" "${nv_file}" "${nv_file}.sig" "${r8125_file}" "${r8125_file}.sig" 2>/dev/null || true
            return 1
        fi
    done

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
    check_boot_disk_space 250 || true
    # 6A-8g: kernel image + one initramfs of the current largest size (32 MB if none yet) + scaled margin, before any write
    local vm_pkg_kb need_boot_mb
    vm_pkg_kb=$(tar --zstd -tvf "${k_file}" 2>/dev/null | awk '$NF ~ /(^|\/)vmlinuz(-[^\/]*)?$/ {print int($3/1024); exit}')
    local largest_mb
    largest_mb=$(largest_boot_initramfs_mb)
    [ "${largest_mb}" -gt 0 ] 2>/dev/null || largest_mb=32
    need_boot_mb=$(( ${vm_pkg_kb:-20480} / 1024 + largest_mb + $(boot_space_margin_mb "${largest_mb}") ))
    if ! require_boot_space "${need_boot_mb}" "new kernel"; then
        rm -f "${k_file}" "${h_file}" "${k_sig_file}" "${h_sig_file}" 2>/dev/null || true
        return 1
    fi

    sudo tar --zstd --exclude=.PKGINFO --exclude=.BUILDINFO --exclude=.MTREE --exclude=.INSTALL --exclude=.CHANGELOG -xf "${k_file}" -C /
    sudo tar --zstd --exclude=.PKGINFO --exclude=.BUILDINFO --exclude=.MTREE --exclude=.INSTALL --exclude=.CHANGELOG -xf "${h_file}" -C /

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

    # 6A-8c: boot files change from here on; cron reseals if this run never reaches the reseal
    mark_boot_reseal_pending
    # Copy vmlinuz image dynamically
    local vmlinuz_in_pkg="" vm_src=""
    vmlinuz_in_pkg=$(tar --zstd -tf "${k_file}" 2>/dev/null | grep -E '^boot/vmlinuz-' | head -n 1 | sed 's|^|/|' || true)
    if [ -n "${vmlinuz_in_pkg}" ] && [ -f "${vmlinuz_in_pkg}" ]; then
        vm_src="${vmlinuz_in_pkg}"; sudo cp -f "${vm_src}" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/boot/vmlinuz-linux-cachyos-bore-lto" ] && [ "${flavor}" = "lto" ]; then
        vm_src="/boot/vmlinuz-linux-cachyos-bore-lto"; sudo cp -f "${vm_src}" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/boot/vmlinuz-linux-cachyos-bore" ] && [ "${flavor}" = "bore" ]; then
        vm_src="/boot/vmlinuz-linux-cachyos-bore"; sudo cp -f "${vm_src}" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/boot/vmlinuz-linux-cachyos-eevdf" ] && [ "${flavor}" = "eevdf" ]; then
        vm_src="/boot/vmlinuz-linux-cachyos-eevdf"; sudo cp -f "${vm_src}" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/boot/vmlinuz-linux-cachyos-bmq" ] && [ "${flavor}" = "bmq" ]; then
        vm_src="/boot/vmlinuz-linux-cachyos-bmq"; sudo cp -f "${vm_src}" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/boot/vmlinuz-linux-cachyos-deckify" ] && [ "${flavor}" = "deckify" ]; then
        vm_src="/boot/vmlinuz-linux-cachyos-deckify"; sudo cp -f "${vm_src}" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/boot/vmlinuz-linux-cachyos-rt-bore" ] && [ "${flavor}" = "rt-bore" ]; then
        vm_src="/boot/vmlinuz-linux-cachyos-rt-bore"; sudo cp -f "${vm_src}" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/boot/vmlinuz-linux-cachyos-rc" ] && [ "${flavor}" = "rc" ]; then
        vm_src="/boot/vmlinuz-linux-cachyos-rc"; sudo cp -f "${vm_src}" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/boot/vmlinuz-linux-cachyos-lts" ] && [ "${flavor}" = "lts" ]; then
        vm_src="/boot/vmlinuz-linux-cachyos-lts"; sudo cp -f "${vm_src}" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/boot/vmlinuz-linux-cachyos" ] && [ "${flavor}" = "standard" ]; then
        vm_src="/boot/vmlinuz-linux-cachyos"; sudo cp -f "${vm_src}" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/boot/vmlinuz-linux-zen" ] && [ "${flavor}" = "zen" ]; then
        vm_src="/boot/vmlinuz-linux-zen"; sudo cp -f "${vm_src}" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/boot/vmlinuz-linux" ] && [ "${flavor}" = "arch" ]; then
        vm_src="/boot/vmlinuz-linux"; sudo cp -f "${vm_src}" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/usr/lib/modules/${kver_full}/vmlinuz" ]; then
        vm_src="/usr/lib/modules/${kver_full}/vmlinuz"; sudo cp -f "${vm_src}" "/boot/vmlinuz-${kver_full}"
    elif [ -f "/lib/modules/${kver_full}/vmlinuz" ]; then
        vm_src="/lib/modules/${kver_full}/vmlinuz"; sudo cp -f "${vm_src}" "/boot/vmlinuz-${kver_full}"
    fi

    # 6A-8g: the copied kernel must be byte-identical to its source before it is hashed and sealed
    if [ -n "${vm_src}" ] && ! sudo cmp -s "${vm_src}" "/boot/vmlinuz-${kver_full}"; then
        log_error "The new kernel image on /boot is incomplete (disk full or write error). It was removed; your current kernels are unchanged."
        sudo rm -f "/boot/vmlinuz-${kver_full}" 2>/dev/null || true
        return 1
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
            sudo tar --zstd --exclude=.PKGINFO --exclude=.BUILDINFO --exclude=.MTREE --exclude=.INSTALL --exclude=.CHANGELOG -xf "${r8125_file}" -C /
            log_success "$(_ R8125_DEPLOY_SUCCESS version="${kver_full}" 2>/dev/null || echo "Realtek r8125 module successfully deployed for kernel ${kver_full}.")"
        else
            log_warn "Realtek r8125 package integrity verification failed! Skipping module extraction."
        fi
    fi

    # Fetch and deploy matching CachyOS NVIDIA driver if on supported NVIDIA GPU
    # 6A-131 (B6/F2/F3): only Turing+ cards that run (or chose) the NVIDIA driver; the Pascal 580xx path below is
    # therefore not reached in LTS (it had an HTML scrape, curl without -f and no signature check)
    if [ "${HAS_NVIDIA}" = "true" ] && command -v nvidia_generation_supported >/dev/null 2>&1 && nvidia_generation_supported; then
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
                sudo curl -sSL --connect-timeout 10 --speed-limit 1024 --speed-time 25 -o "${dkms_file}" "${cachy_base}/${dkms_pkg}"
                if ! verify_cachyos_package_integrity "${dkms_file}"; then
                    log_error "DKMS package integrity verification failed! Skipping extraction."
                    sudo rm -f "${dkms_file}" 2>/dev/null || true
                else
                    sudo tar --zstd --exclude=.PKGINFO --exclude=.BUILDINFO --exclude=.MTREE --exclude=.INSTALL --exclude=.CHANGELOG -xf "${dkms_file}" -C /
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
                    curl -sSL --connect-timeout 10 --speed-limit 1024 --speed-time 25 -o "${nv_file}" "${nv_url}" 2>/dev/null || sudo curl -sSL --connect-timeout 10 --speed-limit 1024 --speed-time 25 -o "${nv_file}" "${nv_url}"
                fi
                # 6A-8f: this fallback download had no signature at all
                if [ -f "${nv_file}" ] && [ ! -f "${nv_file}.sig" ]; then
                    curl -sSL --connect-timeout 10 -o "${nv_file}.sig" "${nv_url}.sig" 2>/dev/null || sudo curl -sSL --connect-timeout 10 -o "${nv_file}.sig" "${nv_url}.sig" 2>/dev/null || true
                fi
                if ! verify_cachyos_gpg_signature "${nv_file}" "${nv_file}.sig"; then
                    log_error "NVIDIA driver package GPG signature check failed! Skipping extraction."
                    sudo rm -f "${nv_file}" "${nv_file}.sig" 2>/dev/null || true
                elif ! verify_cachyos_package_integrity "${nv_file}"; then
                    log_error "NVIDIA driver package integrity verification failed! Skipping extraction."
                    sudo rm -f "${nv_file}" 2>/dev/null || true
                else
                    sudo tar --zstd --exclude=.PKGINFO --exclude=.BUILDINFO --exclude=.MTREE --exclude=.INSTALL --exclude=.CHANGELOG -xf "${nv_file}" -C /
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
    # 6A-103: no question in the middle of a full update; the offer is made when kernels are managed from the menu
    if ! command -v dkms >/dev/null 2>&1 && [ "${SLACKY_UPDATE_RUNNING:-0}" = "1" ]; then
        { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] SpiderSense: DKMS is not installed; the offer to install it is made from the kernel menu" >> "${LOG_FILE}"; } 2>/dev/null || true
    elif ! command -v dkms >/dev/null 2>&1; then
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

    if [ "${DEFER_BOOT_SYNC:-0}" != "1" ]; then
        if command -v dkms >/dev/null 2>&1; then
            build_dkms_modules_for_all_kernels
        fi

        if [ "${HAS_NVIDIA}" = "true" ] && command -v nvidia_generation_supported >/dev/null 2>&1 && nvidia_generation_supported; then
            if [ ! -d "/usr/lib/modules/${kver_full}/kernel/drivers/video" ] && [ ! -d "/lib/modules/${kver_full}/kernel/drivers/video" ]; then
                if command -v build_nvidia_modules >/dev/null 2>&1; then
                    build_nvidia_modules "${kver_full}" || true
                fi
            fi

            # Synchronize CachyOS NVIDIA user-space package and any stock Slackware kernels unless deferred
            if command -v ensure_cachyos_nvidia_duties >/dev/null 2>&1; then
                ensure_cachyos_nvidia_duties || log_warn "The NVIDIA driver could not be confirmed for every kernel; see the log."
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

# 6A-119 (SpiderSense): how many initramfs builds may run at once. One dracut build uses a few threads for compression
# and up to about 2 GB of RAM, so the limit is max(1, min(threads/4, RAM GB/2, kernels)): 16 threads + 31 GB -> 4.
# Reads the SpiderSense hardware profile; falls back to nproc and /proc/meminfo.
ss_dracut_jobs() {
    local kernels="$1" threads ram n
    if ss_hw_load; then
        threads="${HW_CPU_THREADS:-1}"; ram="${HW_RAM_GB:-0}"
    else
        threads=$(nproc 2>/dev/null || echo 1)
        ram=$(awk '/^MemTotal:/{print int($2/1048576)}' /proc/meminfo 2>/dev/null || echo 0)
    fi
    [[ "${threads}" =~ ^[0-9]+$ ]] || threads=1
    [[ "${ram}" =~ ^[0-9]+$ ]] || ram=0
    [[ "${kernels}" =~ ^[0-9]+$ ]] || kernels=1
    n=$(( threads / 4 ))
    [ $(( ram / 2 )) -lt "${n}" ] && n=$(( ram / 2 ))
    [ "${kernels}" -lt "${n}" ] && n="${kernels}"
    [ "${n}" -ge 1 ] || n=1
    echo "${n}"
}

# 6A-119: build one initramfs in the foreground. Uses the caller's dracut_bin, dracut_args, is_laptop, HAS_INTEL, HAS_AMD.
ss_dracut_build_one() {
    local skver="$1" tmp_initrd="$2" has_k_nv=false
    if find "/lib/modules/${skver}" "/usr/lib/modules/${skver}" -name "nvidia.ko*" 2>/dev/null | grep -q "nvidia"; then
        has_k_nv=true
    fi
    local k_dracut_args=("${dracut_args[@]}")
    if [ "${has_k_nv}" = "true" ]; then
        if [ "${is_laptop}" -eq 1 ] && [ "${HAS_INTEL}" = "true" ]; then
            k_dracut_args+=(--force-drivers "i915 nvidia nvidia_modeset nvidia_uvm nvidia_drm")
        elif [ "${is_laptop}" -eq 1 ] && [ "${HAS_AMD}" = "true" ]; then
            k_dracut_args+=(--force-drivers "amdgpu nvidia nvidia_modeset nvidia_uvm nvidia_drm")
        else
            k_dracut_args+=(--add-drivers "nvidia nvidia_modeset nvidia_uvm nvidia_drm")
        fi
    fi
    sudo env -i PATH="/usr/local/sbin:/usr/local/bin:/sbin:/usr/sbin:/bin:/usr/bin" "${dracut_bin}" "${k_dracut_args[@]}" "${tmp_initrd}" "${skver}" >/dev/null 2>&1
}

# 6A-119: a quiet line for the log file only (silent on screen).
ss_note() {
    { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SPIDERSENSE] $1" >> "${LOG_FILE}"; } 2>/dev/null || true
}

# 6A-42 (SpiderSense phase 1): move a freshly built image onto /boot safely. Lock + reseal marker BEFORE /boot changes
# (Limine checks a hash of every image: an interrupted run must be repaired by the cron job), copy to <out>.new on the
# same filesystem, sync, then one rename, so the live image is never half-written. The build dir is private (mktemp -d
# as root), never a predictable /tmp name. Returns 1 and keeps the previous image on any failure.
# 6A-133 (LTS B7): boot-loader facts for the initrd rules. Limine is the only loader whose images this tool manages;
# on LILO/ELILO (and Limine not active) the stock Slackware kernels' initrds belong to geninitrd and the user's loader.
slacky_boot_dir() { echo "${SLACKY_BOOT_DIR:-/boot}"; }
limine_is_active_loader() {
    command -v is_limine_installed >/dev/null 2>&1 || return 1
    [ "$(is_limine_installed 2>/dev/null || echo false)" = "true" ]
}
# Prints "lilo" or "elilo" when that loader is configured and Limine is not active; prints nothing otherwise.
hands_off_boot_loader() {
    limine_is_active_loader && return 0
    local etc="${SLACKY_ETC_DIR:-/etc}" b
    b=$(slacky_boot_dir)
    if [ -f "${etc}/lilo.conf" ]; then
        echo "lilo"
    elif sudo test -f "${b}/efi/EFI/Slackware/elilo.conf" 2>/dev/null || sudo test -f "${b}/EFI/Slackware/elilo.conf" 2>/dev/null; then
        echo "elilo"
    fi
    return 0
}
# One plain reminder line for LILO/ELILO machines (the bin/slacky-update boot chain may call this after a kernel change).
print_boot_loader_reminder() {
    case "$(hands_off_boot_loader)" in
        lilo) log_warn "Your computer starts with LILO, which this tool leaves alone; run 'lilo' as root before restarting so it finds the new kernel." ;;
        elilo) log_warn "Your computer starts with ELILO, which this tool leaves alone; run 'eliloconfig' as root before restarting so it copies the new kernel." ;;
    esac
    return 0
}
# A stock Slackware kernel (kernel-generic/huge): not CachyOS, zen or arch.
is_stock_slackware_kver() { [[ ! "$1" =~ (cachyos|-zen|-arch) ]]; }
# True when some symlink directly in /boot resolves to this file (geninitrd: initrd.gz -> initrd-<k>.img).
boot_symlink_points_to() {
    local f="$1" b real l
    b=$(slacky_boot_dir)
    real=$(sudo readlink -f "${f}" 2>/dev/null || echo "${f}")
    while IFS= read -r l; do
        [ -n "${l}" ] || continue
        [ "$(sudo readlink -f "${l}" 2>/dev/null)" = "${real}" ] && return 0
    done < <(sudo find "${b}" -maxdepth 1 -type l 2>/dev/null || true)
    return 1
}

install_initramfs_image() {
    local tmp="$1" out="$2" kv="$3" sz min_sz="${4:-5000000}"
    sz=$(sudo stat -c%s "${tmp}" 2>/dev/null || echo 0)
    if [ "${sz}" -le "${min_sz}" ] 2>/dev/null; then
        sudo rm -f "${tmp}" 2>/dev/null || true
        log_warn "The new startup image for kernel ${kv} did not build correctly (${sz} bytes), so the previous one is kept."
        return 1
    fi
    if [ "$(is_limine_installed 2>/dev/null || echo false)" = "true" ]; then
        acquire_boot_lock || return 1
        mark_boot_reseal_pending
    fi
    if sudo cp -f "${tmp}" "${out}.new" && sudo chmod 600 "${out}.new" && sudo sync && sudo mv -f "${out}.new" "${out}"; then
        sudo rm -f "${tmp}" 2>/dev/null || true
        # 6A-133 (LTS B7): old initrd-<k> files are removed only when Limine is the managed loader, never the image just
        # written, and never a file a /boot symlink points to (geninitrd's initrd-<k>.img behind initrd.gz, used by LILO)
        if limine_is_active_loader; then
            local old b
            b=$(slacky_boot_dir)
            for old in "${b}/initrd-${kv}.img" "${b}/initrd-${kv}.gz" "${b}/initrd-${kv}"; do
                [ "${old}" = "${out}" ] && continue
                sudo test -f "${old}" || continue
                boot_symlink_points_to "${old}" && continue
                sudo rm -f "${old}" 2>/dev/null || true
            done
        fi
        return 0
    fi
    sudo rm -f "${out}.new" "${tmp}" 2>/dev/null || true
    log_warn "The new startup image for kernel ${kv} could not be written to /boot, so the previous one is kept."
    return 1
}

# 6A-245: initramfs input fingerprints. An image is "stale" when the things dracut puts into it changed, not merely when
# vmlinuz has a newer mtime (signing for Secure Boot rewrites vmlinuz after the image was built, so the mtime rule
# rebuilt good images on every run). One record per kernel, written AFTER the whole boot chain (so it holds the signed
# kernel): sha256 of vmlinuz, sha256 of every extra/DKMS/NVIDIA module, a hash of the dracut configuration and the size
# and mtime of the image itself. Firmware is not an input: images keep the firmware they were built with until a real
# rebuild (kernel/module/config change, a SpiderSense order, or --force style commands).
# SS_FP_DIR / SS_FP_BOOT / SS_FP_MODS / SS_FP_ETC exist only so tests can run on a fake root.
ss_fp_dir()  { printf '%s' "${SS_FP_DIR:-/var/lib/slacky-boot/initramfs-inputs}"; }
ss_fp_valid_kver() {
    case "${1:-}" in ""|.*|*/*|*[[:space:]]*) return 1 ;; esac
    return 0
}

# Prints the canonical fingerprint text of one kernel. Returns 1 when the image is missing.
initramfs_inputs_fingerprint() {
    local k="$1" boot="${SS_FP_BOOT:-/boot}" etc="${SS_FP_ETC:-/etc}"
    local mods="${SS_FP_MODS:-/lib/modules /usr/lib/modules}"
    ss_fp_valid_kver "${k}" || return 1
    local vm="${boot}/vmlinuz-${k}" img="${boot}/initramfs-${k}.img" d
    sudo test -f "${img}" || return 1
    echo "slacky-initramfs-inputs v1"
    if sudo test -f "${vm}"; then
        echo "vmlinuz $(sudo sha256sum -- "${vm}" | cut -d' ' -f1)"
    else
        echo "vmlinuz none"
    fi
    for d in ${mods}; do
        [ -d "${d}/${k}" ] || continue
        sudo find "${d}/${k}" \( -path '*/extramodules/*' -o -path '*/updates/*' -o -name 'nvidia*.ko*' \) -type f \
            -exec sha256sum -- {} + 2>/dev/null | LC_ALL=C sort -k2 | sed 's/^\([0-9a-f]*\)  /module \1 /'
    done
    echo "dracut-conf $( { sudo find "${etc}/dracut.conf" "${etc}/dracut.conf.d" -maxdepth 1 -type f \
        -exec sha256sum -- {} + 2>/dev/null | LC_ALL=C sort -k2; } | sha256sum | cut -d' ' -f1)"
    echo "image $(sudo stat -c '%s %Y' -- "${img}")"
}

# 0 = the record matches the current inputs (image is current), 1 = changed (rebuild), 2 = no usable record (mtime fallback)
initramfs_record_check() {
    local k="$1" rec cur old
    ss_fp_valid_kver "${k}" || return 2
    rec="$(ss_fp_dir)/${k}"
    sudo test -L "$(ss_fp_dir)" && return 2
    sudo test -L "${rec}" && return 2
    sudo test -f "${rec}" || return 2
    cur=$(initramfs_inputs_fingerprint "${k}") || return 1
    old=$(sudo cat -- "${rec}" 2>/dev/null) || return 2
    [ -n "${old}" ] || return 2
    [ "${cur}" = "${old}" ] && return 0
    return 1
}

# Writes the record atomically (temp file + rename), root-owned 0644. Refuses links in the path.
initramfs_record_write() {
    local k="$1" dir parent fp tmp rec
    ss_fp_valid_kver "${k}" || return 1
    dir="$(ss_fp_dir)"; parent=$(dirname "${dir}"); rec="${dir}/${k}"
    sudo test -L "${parent}" && return 1
    sudo test -L "${dir}" && return 1
    sudo test -L "${rec}" && return 1
    fp=$(initramfs_inputs_fingerprint "${k}") || return 1
    sudo mkdir -p "${dir}" || return 1
    sudo test -L "${dir}" && return 1
    sudo chmod 0755 "${parent}" "${dir}" 2>/dev/null || true
    tmp=$(sudo mktemp "${dir}/.${k}.XXXXXX") || return 1
    if printf '%s\n' "${fp}" | sudo tee "${tmp}" >/dev/null \
        && sudo chmod 0644 "${tmp}" && sudo chown 0:0 "${tmp}" && sudo mv -T -f -- "${tmp}" "${rec}"; then
        return 0
    fi
    sudo rm -f -- "${tmp}" 2>/dev/null || true
    return 1
}

# 0 = the image of this kernel must be rebuilt, 1 = it is current. Never skips a needed rebuild: no image, a SpiderSense
# order, a changed record, or (only without any record) the old mtime rule.
initramfs_is_stale() {
    local k="$1" has_nv="${2:-false}" nv_mod="${3:-}" boot="${SS_FP_BOOT:-/boot}"
    local img="${boot}/initramfs-${k}.img" fp_rc=0
    sudo test -f "${img}" || return 0
    # 6A-97: the NVIDIA sync ordered this image (an unpacked module keeps the package's old mtime)
    if ss_initrd_ordered "${k}"; then return 0; fi
    initramfs_record_check "${k}" || fp_rc=$?
    if [ "${fp_rc}" -eq 0 ]; then return 1; fi
    if [ "${fp_rc}" -eq 1 ]; then return 0; fi
    # 6A-245: no usable record (first run after the upgrade): the old mtime rule
    if sudo test -f "${boot}/vmlinuz-${k}" && sudo test "${boot}/vmlinuz-${k}" -nt "${img}"; then return 0; fi
    if [ "${has_nv}" = "true" ] && [ -f "${nv_mod}" ] && sudo test "${nv_mod}" -nt "${img}"; then return 0; fi
    return 1
}

# Called once after the whole boot chain: records every kept kernel whose image was built or confirmed in [3/5].
# Kernels that are being removed, or whose image failed, get no record (a stale record could hide a stale image).
record_initramfs_inputs_all() {
    local kdir k dying=""
    case "${SS_INITRD_FAILED-ALL}" in *ALL*) return 0 ;; esac
    command -v ss_purge_set >/dev/null 2>&1 && dying=" $(ss_purge_set 2>/dev/null | tr '\n' ' ') "
    local mroot="${SS_FP_MODS:-/lib/modules}"; mroot="${mroot%% *}"
    for kdir in "${mroot}"/*; do
        [ -d "${kdir}" ] || continue
        k=$(basename "${kdir}")
        [ -f "${kdir}/modules.dep" ] || continue
        case "${dying}" in *" ${k} "*) continue ;; esac
        case " ${SS_INITRD_FAILED:-} " in *" ${k} "*) continue ;; esac
        initramfs_record_write "${k}" || true
    done
    return 0
}

generate_kernel_initramfs() {
    local kver="$1"
    validate_privileges
    [ "${kver}" = "TARGETED_PIPELINE" ] && SS_INITRD_FAILED="ALL"
    probe_gpu_hardware
    # 6A-133 (LTS B7): on LILO/ELILO the stock kernels' initrds stay with geninitrd and the user's loader (hands-off)
    local ss_handsoff
    ss_handsoff=$(hands_off_boot_loader)
    if [ -n "${ss_handsoff}" ] && [ "${kver}" != "ALL" ] && [[ "${kver}" != TARGETED* ]] && is_stock_slackware_kver "${kver}"; then
        print_boot_loader_reminder
        return 0
    fi
    check_boot_disk_space 250 || true
    # 6A-8g: images are copied from /tmp onto /boot. Existing ones are overwritten in place (only growth is needed, covered
    # by the margin); kernels without an image yet need a full one each. Too little space would leave an entry unbootable.
    local cur_initrd_mb missing_initrd
    cur_initrd_mb=$(largest_boot_initramfs_mb)
    [ "${cur_initrd_mb}" -gt 0 ] 2>/dev/null || cur_initrd_mb=32
    missing_initrd=$(count_kernels_without_initramfs)
    require_boot_space $(( missing_initrd * cur_initrd_mb + $(boot_space_margin_mb "${cur_initrd_mb}") )) "initramfs" || return 1

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
        # 6A-42: private root-owned build dir (was /tmp/dracut-<kver>-$$.img, a predictable path written by root)
        local dracut_tmpdir
        dracut_tmpdir=$(sudo mktemp -d /tmp/slacky-dracut.XXXXXX 2>/dev/null) || { log_error "Cannot create a private build folder for the startup image."; return 1; }
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

        # Enforce universal multi-threaded zstd -1 compression for high-speed boot and build
        if command -v zstd >/dev/null 2>&1; then
            dracut_args+=(--compress "zstd -1 -T0")
        fi

        local is_laptop=0
        if command -v is_laptop_chassis >/dev/null 2>&1 && is_laptop_chassis; then
            is_laptop=1
        fi

        if [ "${kver}" = "ALL" ] || [ "${kver}" = "TARGETED" ] || [ "${kver}" = "TARGETED_PIPELINE" ]; then
            local pending_kvers=()
            local pending_nv=()
            local pending_args=()
            # 6A-98: in a keep-set commit the kernels about to be removed get no new image
            local ss_dying=""
            if [ "${SS_KEEP_SET_MENU:-0}" = "1" ] && [ "${kver}" != "ALL" ]; then
                ss_dying=" $(ss_purge_set | tr '\n' ' ') "
            fi

            for kdir in /lib/modules/*; do
                [ -d "${kdir}" ] || continue
                local single_kver
                single_kver=$(basename "${kdir}")
                [ -f "${kdir}/modules.dep" ] || continue
                case "${ss_dying}" in *" ${single_kver} "*) continue ;; esac
                # 6A-133: hands-off for stock kernels on LILO/ELILO
                if [ -n "${ss_handsoff}" ] && is_stock_slackware_kver "${single_kver}"; then continue; fi
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
                        if ! initramfs_is_stale "${single_kver}" "${has_k_nv}" "${k_nv_mod}"; then
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
            local pipeline_failed=()

            if [ "${total_builds}" -eq 0 ]; then
                [ "${kver}" = "TARGETED_PIPELINE" ] && SS_INITRD_FAILED=""
                if [ "${kver}" = "TARGETED_PIPELINE" ]; then
                    printf "  \033[1;36m[3/5]\033[0m \033[1mDracut Initramfs Generation\033[0m  : \033[1;32mAll installed images are up to date\033[0m\n"
                fi
                sudo rm -rf "${dracut_tmpdir}" 2>/dev/null || true
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
                # 6A-119: at most ss_dracut_jobs builds at a time; a failed build is retried once on its own.
                local max_jobs
                max_jobs=$(ss_dracut_jobs "${total_builds}")
                local pids=() tmp_files=() out_files=() t_start=() t_used=()
                local next_job=0 running=0 j

                for ((i=0; i<total_builds; i++)); do
                    tmp_files+=("${dracut_tmpdir}/initramfs-${pending_kvers[i]}.img")
                    out_files+=("/boot/initramfs-${pending_kvers[i]}.img")
                    pids+=("")
                    t_start+=(0)
                    t_used+=(0)
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
                    running=0
                    for ((j=0; j<next_job; j++)); do
                        if [ -n "${pids[j]}" ] && kill -0 "${pids[j]}" 2>/dev/null; then
                            running=$(( running + 1 ))
                        elif [ "${t_used[j]}" -eq 0 ]; then
                            t_used[j]=$(( SECONDS - t_start[j] + 1 ))
                        fi
                    done
                    while [ "${running}" -lt "${max_jobs}" ] && [ "${next_job}" -lt "${total_builds}" ]; do
                        ss_dracut_build_one "${pending_kvers[next_job]}" "${tmp_files[next_job]}" &
                        pids[next_job]="$!"
                        t_start[next_job]="${SECONDS}"
                        next_job=$(( next_job + 1 ))
                        running=$(( running + 1 ))
                    done
                    [ "${running}" -gt 0 ] || break

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
                    local rc=0
                    wait "${pids[i]}" 2>/dev/null || rc=$?
                    if [ "${rc}" -ne 0 ]; then
                        # One quiet serial retry: a parallel failure can be memory pressure, not a broken kernel.
                        ss_note "dracut for ${skver} failed in parallel (exit ${rc}); retrying alone"
                        sudo rm -f "${tmp_initrd}" 2>/dev/null || true
                        local t0="${SECONDS}"
                        rc=0
                        ss_dracut_build_one "${skver}" "${tmp_initrd}" || rc=$?
                        t_used[i]=$(( SECONDS - t0 + 1 ))
                    fi
                    ss_note "dracut ${skver}: exit ${rc}, about ${t_used[i]} s (${max_jobs} at a time)"

                    if install_initramfs_image "${tmp_initrd}" "${initrd_out}" "${skver}"; then
                        pipeline_generated+=("${skver}")
                    else
                        pipeline_failed+=("${skver}")
                    fi
                done
            else
                # Sequential generation with live ticker
                for ((i=0; i<total_builds; i++)); do
                    local single_kver="${pending_kvers[i]}"
                    local initrd_out="/boot/initramfs-${single_kver}.img"
                    local tmp_initrd="${dracut_tmpdir}/initramfs-${single_kver}.img"

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

                    if install_initramfs_image "${tmp_initrd}" "${initrd_out}" "${single_kver}"; then
                        pipeline_generated+=("${single_kver}")
                    else
                        pipeline_failed+=("${single_kver}")
                    fi
                done
            fi

            # Clean orphaned initramfs images
            while IFS= read -r img; do
                [ -n "${img}" ] || continue
                local img_kver
                img_kver=$(basename "${img}" | sed -e 's/^initramfs-//' -e 's/\.img$//')
                if [ ! -d "/lib/modules/${img_kver}" ] && [ ! -d "/usr/lib/modules/${img_kver}" ]; then
                    # 6A-133: never remove a file a /boot symlink points to
                    boot_symlink_points_to "${img}" || sudo rm -f "${img}" 2>/dev/null || true
                fi
            done < <(sudo find /boot -maxdepth 1 -name "initramfs-*.img" 2>/dev/null || true)

            sudo rm -rf "${dracut_tmpdir}" 2>/dev/null || true
            [ "${kver}" = "TARGETED_PIPELINE" ] && SS_INITRD_FAILED=" ${pipeline_failed[*]:-} "
            if [ "${kver}" = "TARGETED_PIPELINE" ]; then
                # 6A-44: a failed image is shown as failed (was always green)
                if [ "${#pipeline_failed[@]}" -gt 0 ]; then
                    local jf
                    jf=$(IFS=', '; echo "${pipeline_failed[*]}")
                    printf "\r  \033[1;36m[3/5]\033[0m \033[1mDracut Initramfs Generation\033[0m  : \033[1;31mFailed for %s (previous image kept)\033[0m\033[K\n" "${jf}"
                elif [ "${#pipeline_generated[@]}" -gt 0 ]; then
                    local joined
                    joined=$(IFS=', '; echo "${pipeline_generated[*]}")
                    printf "\r  \033[1;36m[3/5]\033[0m \033[1mDracut Initramfs Generation\033[0m  : \033[1;32mGenerated %d fresh image(s) (%s)\033[0m\033[K\n" "${#pipeline_generated[@]}" "${joined}"
                else
                    printf "\r  \033[1;36m[3/5]\033[0m \033[1mDracut Initramfs Generation\033[0m  : \033[1;32mAll installed images are up to date\033[0m\033[K\n"
                fi
            fi

            # Only the full-update pipeline (which shows the red [3/5] line and continues) gets a non-zero result; the
            # ~20 other callers run under set -e and must still reach the Limine reseal, so they keep the old 0.
            [ "${#pipeline_failed[@]}" -eq 0 ] || [ "${kver}" != "TARGETED_PIPELINE" ]
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
            local tmp_initrd="${dracut_tmpdir}/initramfs-${kver}.img"

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

            printf "\r\033[K"
            if install_initramfs_image "${tmp_initrd}" "${initrd_out}" "${kver}"; then
                sudo rm -rf "${dracut_tmpdir}" 2>/dev/null || true
                log_success "Dracut initramfs generated: ${initrd_out}"
                return 0
            fi
            sudo rm -rf "${dracut_tmpdir}" 2>/dev/null || true
            # previous image kept and the warning shown; return 0 like before so callers under set -e still reseal
            return 0
        fi
    else
        # Legacy Slackware mkinitrd fallback
        # 6A-133 (M6): TARGETED_PIPELINE (the full-update [3/5] step) was missing here, so no image was built at all
        if [ "${kver}" = "ALL" ] || [ "${kver}" = "TARGETED" ] || [ "${kver}" = "TARGETED_PIPELINE" ]; then
            local mk_failed=0
            local gen_script
            gen_script=$(command -v mkinitrd_command_generator.sh 2>/dev/null || echo "/sbin/mkinitrd_command_generator.sh")
            if [ "${kver}" = "ALL" ] && [ -x "${gen_script}" ] && [ -z "${ss_handsoff}" ]; then
                log_info "Regenerating mkinitrd images using Slackware generator..."
                sudo bash <("${gen_script}") 2>/dev/null || mk_failed=1
            elif [ -d "/lib/modules" ]; then
                for kdir in /lib/modules/*; do
                    [ -d "${kdir}" ] || continue
                    local single_kver
                    single_kver=$(basename "${kdir}")
                    [ -f "${kdir}/modules.dep" ] || continue
                    if [ -n "${ss_handsoff}" ] && is_stock_slackware_kver "${single_kver}"; then continue; fi
                    if [ "${kver}" != "ALL" ]; then
                        local initrd_out="/boot/initrd-${single_kver}.gz"
                        sudo test -f "${initrd_out}" || initrd_out="/boot/initrd-${single_kver}.img"
                        if sudo test -f "${initrd_out}"; then
                            if sudo test -f "/boot/vmlinuz-${single_kver}" && sudo test "${initrd_out}" -nt "/boot/vmlinuz-${single_kver}"; then
                                log_info "Legacy initrd for kernel ${single_kver} is up to date (${initrd_out}). Skipping."
                                continue
                            fi
                        fi
                    fi
                    generate_legacy_mkinitrd "${single_kver}" || mk_failed=1
                done
            fi
            if [ "${mk_failed}" -eq 0 ]; then
                log_success "mkinitrd generation completed for all kernels."
            else
                log_warn "Some startup images could not be built; the previous ones were kept."
            fi
            # same contract as the dracut branch: only the pipeline sees a failure
            [ "${mk_failed}" -eq 0 ] || [ "${kver}" != "TARGETED_PIPELINE" ]
            return
        else
            # previous image kept and the warning shown; 0 like the dracut branch so callers under set -e still reseal
            generate_legacy_mkinitrd "${kver}" || true
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

    local root_res
    root_res=$(resolve_boot_root_cmd 2>/dev/null || echo "ERROR")
    if [ "${root_res}" = "ERROR" ] || [ -z "${root_res}" ]; then
        log_error "FATAL: Root filesystem device or UUID resolution failed! Aborting initrd generation."
        return 1
    fi
    local root_cmd root_flags root_fs root_dev root_uuid
    IFS='|' read -r root_cmd root_flags root_fs root_dev root_uuid <<< "${root_res}"
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
    # 6A-133 (F9): only when this kernel really has an nvidia.ko (the video dir exists on every kernel)
    if [ "${HAS_NVIDIA}" = "true" ] && [ -n "$(find -L "/lib/modules/${kver}" -name 'nvidia.ko*' -print -quit 2>/dev/null)" ]; then
        nvidia_modules=":nvidia:nvidia-modeset:nvidia-uvm:nvidia-drm"
        log_info "NVIDIA hardware identified. Bundling video modules into initrd."
    fi

    local combined_modules="${base_modules}${nvidia_modules}"

    local root_param=""
    if [ -n "${root_uuid}" ]; then
        root_param="UUID=${root_uuid}"
    elif [ -n "${root_dev}" ] && [ "${root_dev}" != "/dev/root" ]; then
        root_param="${root_dev}"
    else
        log_error "FATAL: Missing valid root device or UUID for mkinitrd! Aborting."
        return 1
    fi

    # 6A-133 (M9): private root-owned build dir (was a predictable /tmp name written by root); no fallback without
    # -m/-f/-r (it overwrote a good initrd with one that cannot mount a btrfs root); the result goes through
    # install_initramfs_image (.new + rename, previous image kept on any failure).
    local mk_tmpdir
    mk_tmpdir=$(sudo mktemp -d /tmp/slacky-mkinitrd.XXXXXX 2>/dev/null) || { log_error "Cannot create a private build folder for the startup image."; return 1; }
    local tmp_tree="${mk_tmpdir}/tree"
    local tmp_out="${mk_tmpdir}/initrd-${kver}.gz"

    if ! sudo "${MKINITRD_CMD}" -c -k "${kver}" -s "${tmp_tree}" -m "${combined_modules}" -f "${root_fs}" -r "${root_param}" ${ucode_opt} -o "${tmp_out}"; then
        sudo rm -rf "${mk_tmpdir}" 2>/dev/null || true
        log_warn "The startup image for kernel ${kver} could not be built, so the previous one is kept."
        return 1
    fi
    local mk_rc=0
    if install_initramfs_image "${tmp_out}" "${initrd_out}" "${kver}" 1000000; then
        log_success "Initrd generated: ${initrd_out}"
    else
        mk_rc=1
    fi
    sudo rm -rf "${mk_tmpdir}" 2>/dev/null || true
    return "${mk_rc}"
}

# Backwards compatibility alias
generate_cachy_initrd() {
    generate_kernel_initramfs "$1"
}
