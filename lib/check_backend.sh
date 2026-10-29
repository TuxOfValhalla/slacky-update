#!/usr/bin/env bash
# --- [ PARALLEL BACKGROUND STATUS WORKER ] ---

set -euo pipefail
# 6A-51: python3 -c / python3 - run as root must never import modules from the current directory
export PYTHONSAFEPATH=1
# 6A-316 (N0d): a wrapped desktop session (LD_LIBRARY_PATH from a runtime) must not make host tools load foreign libraries
unset LD_LIBRARY_PATH LD_PRELOAD LD_AUDIT LD_BIND_NOW

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
for cand in "${SCRIPT_DIR}/common.sh" \
            "/usr/share/slacky-update/lib/common.sh" \
            "/usr/local/share/slacky-update/lib/common.sh" \
            "/usr/local/lib/slacky-update/common.sh"; do
    if [ -f "${cand}" ]; then
        # shellcheck source=/dev/null
        source "${cand}"
        break
    fi
done

# --- [ MUTEX & CONCURRENCY GUARD ] ---
# Defer immediately if an interactive slacky-update session is running
# 6A-47: a running update holds the flock run lock in /run/lock (a /tmp file could be created by any user)
if [ -e "/run/lock/slacky-update.lock" ] && command -v flock >/dev/null 2>&1 \
    && ! flock -n "/run/lock/slacky-update.lock" true 2>/dev/null; then
    exit 0
fi

# 6A-144: no predictable /tmp lock. Root uses /run/lock (root-only on Slackware), a user its XDG_RUNTIME_DIR, else a
# private cache dir. The PID check below still guards against a stale file.
LOCK_DIR=""
if [ "${EUID:-$(id -u)}" -eq 0 ] && [ -d "/run/lock" ] && [ -w "/run/lock" ] && [ ! -L "/run/lock" ]; then
    LOCK_DIR="/run/lock"
elif [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "${XDG_RUNTIME_DIR}" ] && [ -w "${XDG_RUNTIME_DIR}" ] && [ -O "${XDG_RUNTIME_DIR}" ]; then
    LOCK_DIR="${XDG_RUNTIME_DIR}"
else
    LOCK_DIR="${XDG_CACHE_HOME:-${HOME:-/root}/.cache}/slacky-update"
    mkdir -p -m 0700 "${LOCK_DIR}" 2>/dev/null || true
fi
CHECK_LOCK="${LOCK_DIR}/slacky-update-check-${UID:-$(id -u)}.lock"
if [ -f "${CHECK_LOCK}" ]; then
    cpid=$(cat "${CHECK_LOCK}" 2>/dev/null || echo "")
    if [ -n "${cpid}" ] && [[ "${cpid}" =~ ^[0-9]+$ ]] && kill -0 "${cpid}" 2>/dev/null; then
        if [ -r "/proc/${cpid}/cmdline" ] && grep -q -a "slacky-update" "/proc/${cpid}/cmdline" 2>/dev/null; then
            exit 0
        fi
    fi
fi
echo "$$" > "${CHECK_LOCK}" 2>/dev/null || true

USER_CACHE_DIR="${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/slacky-update"
mkdir -p "${USER_CACHE_DIR}" 2>/dev/null || true
STATUS_FILE="${USER_CACHE_DIR}/status.json"

TMP_DIR=$(mktemp -d /tmp/slacky-update-check.XXXXXX)
trap 'rm -rf "${TMP_DIR}" "${CHECK_LOCK}" 2>/dev/null || true' EXIT

# 6A-243: the user-level slackpkg / slackpkg+ list reader (fetches the repo lists itself; slackpkg's own pkglist is only
# refreshed by `slackpkg update` as root). Looked up like the other helper scripts; empty when missing.
SLACKPKG_CHECK_SCRIPT=""
for cand in "${SCRIPT_DIR:-}/slacky_slackpkg_check.py" \
            "${APP_DIR:-}/slacky_slackpkg_check.py" \
            "/usr/share/slacky-update/lib/slacky_slackpkg_check.py" \
            "/usr/local/share/slacky-update/lib/slacky_slackpkg_check.py" \
            "/usr/local/lib/slacky-update/slacky_slackpkg_check.py"; do
    if [ -f "${cand}" ]; then
        SLACKPKG_CHECK_SCRIPT="${cand}"
        break
    fi
done

touch "${TMP_DIR}/slackware_updates"
touch "${TMP_DIR}/slackpkgplus_updates"
touch "${TMP_DIR}/slackpkgplus_unverified"
touch "${TMP_DIR}/slackware_new_packages"
touch "${TMP_DIR}/slackware_new_status"
touch "${TMP_DIR}/flatpak_updates"
touch "${TMP_DIR}/sbo_updates"
touch "${TMP_DIR}/cachy_updates"
touch "${TMP_DIR}/gaming_updates"
touch "${TMP_DIR}/gnomes_updates"
touch "${TMP_DIR}/nvidia_updates"
touch "${TMP_DIR}/slackware_status"
touch "${TMP_DIR}/slackpkgplus_status"
touch "${TMP_DIR}/flatpak_status"
touch "${TMP_DIR}/sbo_status"
touch "${TMP_DIR}/cachy_status"
touch "${TMP_DIR}/gnomes_status"
touch "${TMP_DIR}/nvidia_status"
# 6A-298 (N0/F1): suites whose answer is only partly known ("cachyos_kernel", "cachyos_gaming") are listed here, one id
# per line; a suite whose status file is not SUCCESS/NA is "could not check" as well (see the status writer below).
touch "${TMP_DIR}/check_failed_parts"

# Paths below are only overridden by the self-tests (6A-306: honoured only with SLACKY_SELFTEST=1; in normal use the
# environment cannot change them).
if [ "${SLACKY_SELFTEST:-0}" = "1" ]; then
    SLACKY_SLACKPKG_MIRRORS="${SLACKY_SLACKPKG_MIRRORS:-/etc/slackpkg/mirrors}"
    SLACKY_LOCAL_CHANGELOG="${SLACKY_LOCAL_CHANGELOG:-/var/lib/slackpkg/ChangeLog.txt}"
else
    SLACKY_SLACKPKG_MIRRORS="/etc/slackpkg/mirrors"
    SLACKY_LOCAL_CHANGELOG="/var/lib/slackpkg/ChangeLog.txt"
    unset SLACKY_PROBE_URLS SLACKY_CHECK_SKIP_BACKGROUND
fi

# 6A-298 (N1): one reachability probe up front. Any HTTP answer counts as "online" (even a 404); only "cannot resolve",
# "cannot connect" and "timed out" count as offline. Offline: no network phase runs and the old lists are kept.
slacky_probe_network() {
    local urls=() u rc
    if [ -f "${SLACKY_SLACKPKG_MIRRORS}" ]; then
        while IFS= read -r u; do [ -n "${u}" ] && urls+=("${u}"); done < <(grep -E '^[[:space:]]*(https?)://' "${SLACKY_SLACKPKG_MIRRORS}" 2>/dev/null | sed -e 's/^[[:space:]]*//' | head -n 2 || true)
    fi
    urls+=("https://github.com")
    [ -n "${SLACKY_PROBE_URLS:-}" ] && read -r -a urls <<< "${SLACKY_PROBE_URLS}"   # self-tests only
    for u in "${urls[@]}"; do
        rc=0
        curl -s -I -m 5 -o /dev/null "${u}" 2>/dev/null || rc=$?
        case "${rc}" in
            5|6|7|28) ;;
            *) return 0 ;;
        esac
    done
    return 1
}
SLACKY_OFFLINE=0
if ! slacky_probe_network; then
    SLACKY_OFFLINE=1
fi
echo "${SLACKY_OFFLINE}" > "${TMP_DIR}/offline"
# --- [ 0. OPPORTUNISTIC LOW-PRIORITY WEEKLY MAINTENANCE (6d 22h) ] ---
(
    [ "${SLACKY_CHECK_SKIP_BACKGROUND:-0}" = "1" ] && exit 0   # self-tests only
    RANK_SCRIPT=""
    for cand in "${SCRIPT_DIR:-}/rank_mirrors.py" \
                "${APP_DIR:-}/rank_mirrors.py" \
                "/usr/share/slacky-update/lib/rank_mirrors.py" \
                "/usr/local/share/slacky-update/lib/rank_mirrors.py" \
                "/usr/local/lib/slacky-update/rank_mirrors.py"; do
        if [ -f "${cand}" ]; then
            RANK_SCRIPT="${cand}"
            break
        fi
    done

    if [ -n "${RANK_SCRIPT}" ]; then
        # 6A-140: --auto only ranks and records a recommendation; it never edits /etc/slackpkg/mirrors
        if python3 -I "${RANK_SCRIPT}" --check-due 2>/dev/null; then
            nohup nice -n 19 ionice -c 3 python3 -I "${RANK_SCRIPT}" --auto </dev/null >/dev/null 2>&1 &
        fi
    fi

    # 6A-201 (spec section 0): the weekly sentinel run (signed mirror lists, Arch status hints, one short probe round,
    # lag). It runs as the current user (the root cron job too, 6A-278), never asks for sudo, and is silent; it writes only
    # that user's own sentinel cache (root: /var/cache/slacky-update/sentinel).
    SENTINEL_SCRIPT=""
    for cand in "${SCRIPT_DIR:-}/slacky_sentinel.py" \
                "${APP_DIR:-}/slacky_sentinel.py" \
                "/usr/share/slacky-update/lib/slacky_sentinel.py" \
                "/usr/local/share/slacky-update/lib/slacky_sentinel.py" \
                "/usr/local/lib/slacky-update/slacky_sentinel.py"; do
        if [ -f "${cand}" ]; then
            SENTINEL_SCRIPT="${cand}"
            break
        fi
    done
    if [ -n "${SENTINEL_SCRIPT}" ]; then
        if python3 -I "${SENTINEL_SCRIPT}" due 2>/dev/null; then
            nohup nice -n 19 ionice -c 3 python3 -I "${SENTINEL_SCRIPT}" weekly </dev/null >/dev/null 2>&1 &
        fi
    fi
) </dev/null >/dev/null 2>&1 &

# --- [ 1. SLACKWARE REPOSITORY INSPECTION (UNPRIVILEGED) ] ---
(
    [ "${SLACKY_OFFLINE}" -eq 1 ] && exit 0
    # 6A-308: the mirrors to ask, in /etc/slackpkg/mirrors order: the first line, then (only when the first fetch fails) the
    # other lines of the SAME branch (a ChangeLog of another branch must never answer). Duplicates dropped.
    MIRRORS=()
    if [ -f "${SLACKY_SLACKPKG_MIRRORS}" ]; then
        _branch_re='(slackware(64)?-(current|[0-9]+\.[0-9]+))/?$'
        _first_branch=""
        while IFS= read -r _m; do
            [ -n "${_m}" ] || continue
            _m="${_m%/}"
            if [ "${#MIRRORS[@]}" -eq 0 ]; then
                [[ "${_m}" =~ ${_branch_re} ]] && _first_branch="${BASH_REMATCH[1]}"
                MIRRORS+=("${_m}")
                continue
            fi
            [ -n "${_first_branch}" ] || continue
            [[ "${_m}" =~ ${_branch_re} ]] && [ "${BASH_REMATCH[1]}" = "${_first_branch}" ] || continue
            _dup=0
            for _e in "${MIRRORS[@]}"; do [ "${_e}" = "${_m}" ] && _dup=1; done
            [ "${_dup}" -eq 1 ] || MIRRORS+=("${_m}")
        done < <(grep -E '^[[:space:]]*(https?|ftp)://' "${SLACKY_SLACKPKG_MIRRORS}" 2>/dev/null | sed -e 's/^[[:space:]]*//' || true)
    fi

    CHANGELOG_FETCHED=0
    # 6A-298 (N0): curl -f, and a downloaded page only counts when it really is a Slackware ChangeLog (a dated entry
    # header and no HTML). A 404 page or a captive-portal page used to parse as "no updates".
    CL_DATE_RE='^[A-Za-z]{3}[[:space:]]+[A-Za-z]{3}[[:space:]]+[0-9[:space:]]{2}[[:space:]]+[0-9:]+[[:space:]]+[A-Z]+[[:space:]]+[0-9]{4}'
    slacky_changelog_valid() {
        [ -s "$1" ] || return 1
        grep -qiE '<(!doctype|html|head|body)' "$1" 2>/dev/null && return 1
        grep -qE "${CL_DATE_RE}" "$1" 2>/dev/null
    }
    # 6A-308: one ChangeLog request with ONE delayed retry (3 s; the network may still be coming up right after login).
    # No retry on an HTTP 4xx answer (the server said no). SLACKY_FAIL_REASON gets a short plain reason for the recorder.
    SLACKY_RETRY_DELAY=3
    [ "${SLACKY_SELFTEST:-0}" = "1" ] && SLACKY_RETRY_DELAY="${SLACKY_RETRY_DELAY_TEST:-3}"
    SLACKY_FAIL_REASON=""
    slacky_cl_curl() {   # usage: slacky_cl_curl <max-seconds> <url> <out> [curl range args...]
        local mt="$1" url="$2" out="$3" attempt rc code
        shift 3
        for attempt in 1 2; do
            rc=0
            code=$(curl -fsSL -m "${mt}" "$@" -o "${out}" -w '%{http_code}' "${url}" 2>/dev/null) || rc=$?
            if [ "${rc}" -eq 0 ]; then
                if slacky_changelog_valid "${out}"; then return 0; fi
                SLACKY_FAIL_REASON="not a ChangeLog"
                return 1
            fi
            case "${rc}" in
                6)  SLACKY_FAIL_REASON="DNS lookup failed" ;;
                7)  SLACKY_FAIL_REASON="connection refused" ;;
                28) SLACKY_FAIL_REASON="timed out" ;;
                22) SLACKY_FAIL_REASON="HTTP ${code:-error}" ;;
                35|51|58|59|60|77|83) SLACKY_FAIL_REASON="secure connection failed" ;;
                *)  SLACKY_FAIL_REASON="download failed" ;;
            esac
            # a 4xx answer is final; so is the second attempt
            case "${code}" in 4[0-9][0-9]) return 1 ;; esac
            [ "${attempt}" -eq 1 ] && sleep "${SLACKY_RETRY_DELAY}"
        done
        return 1
    }
    slacky_try_mirror() {
        local MIRROR_URL="$1" CHANGELOG_URL UPSTREAM_TOP_DATE LOCAL_TOP_DATE
        CHANGELOG_URL="${MIRROR_URL%/}/ChangeLog.txt"
        # Super-fast check: fetch top 16KB header from upstream
        if slacky_cl_curl 8 "${CHANGELOG_URL}" "${TMP_DIR}/ChangeLog_head.txt" -r 0-16384; then
            UPSTREAM_TOP_DATE=$(grep -E "${CL_DATE_RE}" "${TMP_DIR}/ChangeLog_head.txt" 2>/dev/null | head -n1 || true)
            LOCAL_TOP_DATE=""
            if [ -f "${SLACKY_LOCAL_CHANGELOG}" ]; then
                LOCAL_TOP_DATE=$(grep -E "${CL_DATE_RE}" "${SLACKY_LOCAL_CHANGELOG}" 2>/dev/null | head -n1 || true)
            fi

            if [ -n "${UPSTREAM_TOP_DATE}" ] && [ "${UPSTREAM_TOP_DATE}" = "${LOCAL_TOP_DATE}" ] && [ -f "${SLACKY_LOCAL_CHANGELOG}" ]; then
                cp -f "${SLACKY_LOCAL_CHANGELOG}" "${TMP_DIR}/ChangeLog.txt" 2>/dev/null || true
                slacky_changelog_valid "${TMP_DIR}/ChangeLog.txt" && return 0
            else
                if curl -fsSL -m 6 -r 0-262144 "${CHANGELOG_URL}" -o "${TMP_DIR}/ChangeLog.txt" 2>/dev/null && slacky_changelog_valid "${TMP_DIR}/ChangeLog.txt"; then
                    return 0
                elif curl -fsSL -m 8 "${CHANGELOG_URL}" -o "${TMP_DIR}/ChangeLog.txt" 2>/dev/null && slacky_changelog_valid "${TMP_DIR}/ChangeLog.txt"; then
                    return 0
                else
                    cp -f "${TMP_DIR}/ChangeLog_head.txt" "${TMP_DIR}/ChangeLog.txt" 2>/dev/null || true
                    slacky_changelog_valid "${TMP_DIR}/ChangeLog.txt" && return 0
                fi
            fi
            SLACKY_FAIL_REASON="download failed"
            return 1
        fi
        # the head request failed (after its retry): one more try for the bigger piece, same retry rule
        slacky_cl_curl 8 "${CHANGELOG_URL}" "${TMP_DIR}/ChangeLog.txt" -r 0-262144
    }
    rm -f "${TMP_DIR}/changelog_failures"
    for _m in "${MIRRORS[@]}"; do
        if slacky_try_mirror "${_m}"; then
            CHANGELOG_FETCHED=1
            break
        fi
        _h="${_m#*://}"; _h="${_h%%/*}"
        printf '%s\t%s\n' "${_h}" "${SLACKY_FAIL_REASON:-download failed}" >> "${TMP_DIR}/changelog_failures"
    done
    # 6A-308: when no mirror answered, ONE entry in the flight recorder (host and plain reason per mirror). Silent otherwise.
    if [ "${CHANGELOG_FETCHED}" -eq 0 ] && [ -s "${TMP_DIR}/changelog_failures" ]; then
        _trust=""
        for cand in "${SCRIPT_DIR:-}/gnomes_trust.py" "${APP_DIR:-}/gnomes_trust.py" \
                    "/usr/share/slacky-update/lib/gnomes_trust.py" "/usr/local/share/slacky-update/lib/gnomes_trust.py" \
                    "/usr/local/lib/slacky-update/gnomes_trust.py"; do
            if [ -f "${cand}" ]; then _trust="${cand}"; break; fi
        done
        if [ -n "${_trust}" ]; then
            python3 -I - "${_trust}" "${TMP_DIR}/changelog_failures" << 'PYREC' 2>/dev/null || true
import importlib.util, sys
spec = importlib.util.spec_from_file_location("gnomes_trust_rec", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
rows = []
for line in open(sys.argv[2], encoding="utf-8", errors="replace"):
    h, _, r = line.rstrip("\n").partition("\t")
    if h:
        rows.append({"mirror": h[:100], "reason": r[:60]})
msg = "The Slackware ChangeLog could not be fetched (" + "; ".join(x["mirror"] + ": " + x["reason"] for x in rows[:4]) + ")"
m.flight_record("UPDATE", "WARN", "changelog.fetch_failed", msg[:300], {"mirrors": rows[:6]})
PYREC
        fi
    fi

    if [ "${CHANGELOG_FETCHED}" -eq 1 ] && [ -s "${TMP_DIR}/ChangeLog.txt" ]; then
        python3 - "${TMP_DIR}/ChangeLog.txt" > "${TMP_DIR}/slackware_updates" << 'PYSLACK'
import os, sys, re

changelog_path = sys.argv[1]
pkg_log_dir = "/var/log/packages"

installed_pkgs = set(os.listdir(pkg_log_dir)) if os.path.exists(pkg_log_dir) else set()

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

installed_map = {}
for p in installed_pkgs:
    bname, ver, arch, bld, full = parse_pkg_details(p)
    installed_map[bname] = {"version": ver, "build": bld, "full": full}

latest_changelog_pkgs = {}
date_pattern = re.compile(r'^[A-Za-z]{3}\s+[A-Za-z]{3}\s+[0-9\s]{2}\s+[0-9:]+\s+[A-Z]+\s+[0-9]{4}')
entry_pattern = re.compile(r'^((?:[a-zA-Z0-9_\-+]+/)+[a-zA-Z0-9_\-+.]+-(?:x86_64|x86|i[3-6]86|noarch|arm)-[0-9a-zA-Z_]+\.(?:t[xg]z|tlz)):\s+(Added|Upgraded|Rebuilt)')

if os.path.exists(changelog_path):
    with open(changelog_path, "r", encoding="utf-8", errors="ignore") as f:
        lines = f.readlines()

    header_count = 0
    max_headers = 50

    for line in lines:
        if date_pattern.match(line):
            header_count += 1
            if header_count > max_headers:
                break

        match = entry_pattern.match(line)
        if match:
            full_entry = match.group(1)
            # Filter out non-standard / masked distribution directories (testing, pasture, source, extra)
            if full_entry.startswith(("testing/", "pasture/", "source/", "extra/")):
                continue
            pkg_file = os.path.basename(full_entry)
            bname, ver, arch, bld, full = parse_pkg_details(pkg_file)
            
            if bname not in latest_changelog_pkgs:
                latest_changelog_pkgs[bname] = {
                    "full_entry": full_entry,
                    "version": ver,
                    "build": bld,
                    "full": full
                }

pending_updates = []
for bname, target in latest_changelog_pkgs.items():
    if bname in installed_map:
        current = installed_map[bname]
        if is_strictly_newer(current["full"], target["full"]):
            pending_updates.append(target["full_entry"])

for item in sorted(pending_updates):
    print(item)
PYSLACK
        echo "SUCCESS" > "${TMP_DIR}/slackware_status"
        # 6A-243: packages ADDED in the ChangeLog since the installed state (what `slackpkg install-new` would offer)
        if [ -n "${SLACKPKG_CHECK_SCRIPT}" ] \
            && python3 -I "${SLACKPKG_CHECK_SCRIPT}" new --changelog "${TMP_DIR}/ChangeLog.txt" > "${TMP_DIR}/slackware_new.json" 2>/dev/null \
            && python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); l=d["slackware_new_packages"]; assert isinstance(l,list); print("\n".join(str(x) for x in l))' "${TMP_DIR}/slackware_new.json" > "${TMP_DIR}/slackware_new_packages" 2>/dev/null; then
            echo "SUCCESS" > "${TMP_DIR}/slackware_new_status"
        else
            : > "${TMP_DIR}/slackware_new_packages"
        fi
    else
        echo "FAILED" > "${TMP_DIR}/slackware_status"
    fi
) & PID_SLACK=$!

# --- [ 1.5. SLACKPKGPLUS & MULTILIB REPOSITORY INSPECTION (UNPRIVILEGED) ] ---
# 6A-243: the repo lists (CHECKSUMS.md5, signature checked against the keys slackpkg already trusts) are fetched here, as
# the user, into the app's own cache; /var/lib/slackpkg/pkglist is no longer read (it is stale until a root `slackpkg update`).
(
    [ "${SLACKY_OFFLINE}" -eq 1 ] && exit 0
    if [ -n "${SLACKPKG_CHECK_SCRIPT}" ] \
        && python3 -I "${SLACKPKG_CHECK_SCRIPT}" plus --cache "${USER_CACHE_DIR}" > "${TMP_DIR}/slackpkgplus.json" 2>/dev/null \
        && python3 -I - "${TMP_DIR}" << 'PYPLUS'
import json, sys, os
t = sys.argv[1]
d = json.load(open(os.path.join(t, "slackpkgplus.json")))
if not d.get("slackpkgplus_ok"):
    sys.exit(1)
with open(os.path.join(t, "slackpkgplus_updates"), "w") as f:
    f.write("".join(str(x) + "\n" for x in d.get("slackpkgplus_updates", [])))
with open(os.path.join(t, "slackpkgplus_unverified"), "w") as f:
    f.write("".join(str(x) + "\n" for x in d.get("slackpkgplus_unverified", [])))
PYPLUS
    then
        echo "SUCCESS" > "${TMP_DIR}/slackpkgplus_status"
    else
        echo "FAILED" > "${TMP_DIR}/slackpkgplus_status"
    fi
) & PID_PLUS=$!

# --- [ 2. FLATPAK REPOSITORY INSPECTION ] ---
(
    [ "${SLACKY_OFFLINE}" -eq 1 ] && exit 0
    if ! command -v flatpak >/dev/null 2>&1; then
        echo "NA" > "${TMP_DIR}/flatpak_status"
    else
        if raw_fp=$(timeout 6s flatpak remote-ls --updates --columns=name,branch,ref 2>/dev/null); then
            echo "${raw_fp}" | awk -F'\t' '{if ($1 != "") print $1 " [" $2 "]"; else if ($3 != "") print $3}' > "${TMP_DIR}/flatpak_updates"
            echo "SUCCESS" > "${TMP_DIR}/flatpak_status"
        else
            echo "FAILED" > "${TMP_DIR}/flatpak_status"
        fi
    fi
) & PID_FLATPAK=$!

# --- [ 2.5. SBOTOOLS & SLACKBUILDS REPOSITORY INSPECTION ] ---
(
    [ "${SLACKY_OFFLINE}" -eq 1 ] && exit 0
    python3 - "${TMP_DIR}" << 'PYSBOCHECK'
import os, sys, re, glob, time, urllib.request, subprocess, shutil

tmp_dir = sys.argv[1]
out_file = os.path.join(tmp_dir, "sbo_updates")
status_file = os.path.join(tmp_dir, "sbo_status")

# 1. Discover installed SBo packages (suppressing any superseded by Underpants packages)
underpants_pkgs = set()
for p in glob.glob('/var/log/packages/underpants-*') + glob.glob('/var/log/packages/cachyos-gnome-*'):
    fn = os.path.basename(p)
    m = re.match(r'^(?:underpants|cachyos-gnome)-(.*?)-[0-9a-zA-Z._+]+-[^-]+-[^-]+$', fn)
    if m:
        underpants_pkgs.add(m.group(1).lower())

installed = {}
for p in glob.glob('/var/log/packages/*_SBo*') + glob.glob('/var/log/packages/*_sbo*'):
    fn = os.path.basename(p)
    m = re.match(r'^(.*?)-([0-9a-zA-Z._+]+)-[^-]+-[^-]+$', fn)
    if m:
        pname = m.group(1)
        if pname.lower() in underpants_pkgs:
            continue
        installed[pname] = m.group(2)

if not installed:
    with open(out_file, "w") as f: pass
    with open(status_file, "w") as f: f.write("SUCCESS\n")
    sys.exit(0)

# 2. Determine target branch from sbotools conf or /etc/slackware-version
branch = "current"
if os.path.exists("/etc/sbotools/sbotools.conf"):
    try:
        with open("/etc/sbotools/sbotools.conf", "r", encoding="utf-8") as f:
            for line in f:
                if line.strip().startswith("REPO_BRANCH="):
                    val = line.strip().split("=", 1)[1].strip()
                    if val in ("15.0", "current", "14.2"):
                        branch = val
    except Exception:
        pass
elif os.path.exists("/etc/slackware-version"):
    try:
        with open("/etc/slackware-version", "r", encoding="utf-8") as f:
            content = f.read().lower()
            # 6A-299 (F0): "Slackware 15.0+" is -current; a plain "15.0" is the stable tree; anything else is not guessed
            mver = re.match(r'^\s*slackware\s+(\d+\.\d+)(\+?)\s*$', content.splitlines()[0] if content.strip() else "")
            if mver and not mver.group(2) and mver.group(1) == "15.0":
                branch = "15.0"
            elif mver and not mver.group(2):
                branch = mver.group(1)
    except Exception:
        pass

# 3. Setup ChangeLog caching
cache_dir = os.path.expanduser("~/.cache/slacky-update")
try:
    os.makedirs(cache_dir, exist_ok=True)
except Exception:
    # 6A-17: private temp dir instead of the fixed, shared /tmp/slacky-update-cache
    import tempfile
    cache_dir = tempfile.mkdtemp(prefix="slacky-update-cache.")

cl_file = os.path.join(cache_dir, f"sbo_ChangeLog_{branch}.txt")
changelog_urls = [
    f"https://raw.githubusercontent.com/Ponce/slackbuilds/{branch}/ChangeLog.txt",
    "https://slackbuilds.org/ChangeLog.txt"
] if branch == "current" else [
    "https://slackbuilds.org/ChangeLog.txt",
    "https://raw.githubusercontent.com/pfeiffer/slackbuilds/15.0/ChangeLog.txt"
]

def looks_like_sbo_changelog(data):
    # 6A-298 (N0): a 200 page that is not a SlackBuilds ChangeLog (captive portal, error page) must not replace the cache
    try:
        text = data.decode("utf-8", errors="ignore")
    except Exception:
        return False
    if re.search(r'<(!doctype|html|head|body)', text[:4096], re.I):
        return False
    return re.search(r'^[a-zA-Z0-9_+.-]+/[a-zA-Z0-9_+.-]+:\s+(?:Updated|Added)\b', text, re.M) is not None

fetched = False
for cl_url in changelog_urls:
    try:
        req = urllib.request.Request(cl_url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) Slacky-Update/1.0_LTS"})
        if os.path.exists(cl_file) and os.path.getsize(cl_file) > 0:
            mtime = os.path.getmtime(cl_file)
            req.add_header("If-Modified-Since", time.strftime("%a, %d %b %Y %H:%M:%S GMT", time.gmtime(mtime)))
        with urllib.request.urlopen(req, timeout=4) as resp:
            content = resp.read()
            if not looks_like_sbo_changelog(content):
                continue
            tmp_cl = cl_file + ".part"
            with open(tmp_cl, "wb") as f:
                f.write(content)
            os.replace(tmp_cl, cl_file)
        fetched = True
        break
    except urllib.error.HTTPError as e:
        if e.code == 304 and os.path.exists(cl_file) and os.path.getsize(cl_file) > 0: # Not modified, cache is fresh
            # 6A-356: "not modified" does not make an old bad cache good: the stored file must still look like a ChangeLog
            try:
                with open(cl_file, "rb") as _cf:
                    _cached_ok = looks_like_sbo_changelog(_cf.read(8 * 1024 * 1024))
            except Exception:
                _cached_ok = False
            if _cached_ok:
                fetched = True
                break
            try:
                os.unlink(cl_file)
            except OSError:
                pass
    except Exception:
        continue

# 4. Parse ChangeLog.txt if available
upstream = {}
if os.path.exists(cl_file):
    try:
        with open(cl_file, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                m = re.match(r'^[a-zA-Z0-9_+.-]+/([a-zA-Z0-9_+.-]+):\s+(?:Updated|Added)\s+for\s+version\s+([0-9a-zA-Z_.:+~-]+)', line)
                if m:
                    pname = m.group(1)
                    pver = m.group(2)
                    if pname not in upstream:
                        upstream[pname] = pver
    except Exception:
        pass

def ver_tuple(v):
    parts = re.findall(r'[0-9]+|[a-zA-Z]+', v)
    res = []
    for p in parts:
        if p.isdigit():
            res.append((0, int(p)))
        else:
            res.append((1, p))
    return res

updates_dict = {}
for pname, inst_ver in installed.items():
    if pname in upstream:
        up_ver = upstream[pname]
        if inst_ver != up_ver and ver_tuple(up_ver) > ver_tuple(inst_ver):
            updates_dict[pname] = f"{pname} ({inst_ver} -> {up_ver})"

# 5. Local sbocheck fallback/merge if available
if shutil.which("sbocheck"):
    try:
        raw_sbo = subprocess.run(["sbocheck", "-n", "-o", "--nocolor"], capture_output=True, text=True, timeout=5).stdout
        for line in raw_sbo.splitlines():
            if "needs updating" in line.lower():
                parts = line.split()
                if len(parts) >= 6:
                    pname = parts[0]
                    cur_v = parts[1]
                    new_v = parts[5].lstrip("(")
                    updates_dict[pname] = f"{pname} ({cur_v} -> {new_v})"
    except Exception:
        pass

with open(out_file, "w", encoding="utf-8") as f:
    for u in sorted(updates_dict.values()):
        f.write(f"{u}\n")

# 6A-298 (N0): "SUCCESS" only after a real answer (or a 304 on a cache that holds a real ChangeLog)
with open(status_file, "w", encoding="utf-8") as f:
    f.write("SUCCESS\n" if fetched else "FAILED\n")
PYSBOCHECK
) & PID_SBO=$!

# --- [ 3. CACHYOS KERNEL UPSTREAM CHECK ] ---
check_cachyos_background() {
    [ "${SLACKY_OFFLINE}" -eq 1 ] && return 0
    CACHY_UPDATES=()
    local cachy_partial=0
    ACTIVE_KVER=$(uname -r)
    
    LIB_DIR="$(dirname "$(readlink -f "$0")")"
    if [ -f "${LIB_DIR}/mod_kernel.sh" ]; then
        APP_DIR="${LIB_DIR}"
    elif [ -d "/usr/share/slacky-update" ] && [ -f "/usr/share/slacky-update/mod_kernel.sh" ]; then
        APP_DIR="/usr/share/slacky-update"
    elif [ -d "/usr/local/share/slacky-update" ] && [ -f "/usr/local/share/slacky-update/mod_kernel.sh" ]; then
        APP_DIR="/usr/local/share/slacky-update"
    elif [ -d "/usr/local/lib/slacky-update" ] && [ -f "/usr/local/lib/slacky-update/mod_kernel.sh" ]; then
        APP_DIR="/usr/local/lib/slacky-update"
    elif [ -d "/usr/lib64/slacky-update" ] && [ -f "/usr/lib64/slacky-update/mod_kernel.sh" ]; then
        APP_DIR="/usr/lib64/slacky-update"
    elif [ -d "/usr/lib/slacky-update" ] && [ -f "/usr/lib/slacky-update/mod_kernel.sh" ]; then
        APP_DIR="/usr/lib/slacky-update"
    else
        APP_DIR="${LIB_DIR}"
    fi
    # shellcheck source=/dev/null
    [ -f "${APP_DIR}/common.sh" ] && source "${APP_DIR}/common.sh" 2>/dev/null || true
    # shellcheck source=/dev/null
    [ -f "${APP_DIR}/mod_kernel.sh" ] && source "${APP_DIR}/mod_kernel.sh" 2>/dev/null || true

    if command -v get_installed_cachyos_flavors >/dev/null 2>&1; then
        local installed_flavors
        installed_flavors=$(get_installed_cachyos_flavors 2>/dev/null || echo "")

        if [ -n "${installed_flavors}" ]; then
            local raw_batch=""
            if command -v check_all_installed_cachyos_flavors_fast >/dev/null 2>&1; then
                raw_batch=$(check_all_installed_cachyos_flavors_fast "${installed_flavors}" 2>/dev/null || echo "")
            fi

            if [ -n "${raw_batch}" ]; then
                local answered_flavors=" "
                while IFS='|' read -r flv latest_flv_ver k_url h_url nv_url r8125_url; do
                    [ -n "${flv}" ] || continue
                    # 6A-298 (F1): NONE means the lookup failed or found nothing; that is "could not check", not "no update"
                    if [ "${latest_flv_ver}" = "NONE" ] || [ -z "${latest_flv_ver}" ]; then
                        cachy_partial=1
                        continue
                    fi
                    answered_flavors+="${flv} "
                    local cur_flv_ver
                    cur_flv_ver=$(get_installed_cachyos_flavor_version "${flv}" 2>/dev/null || echo "NONE")
                    if [ "${cur_flv_ver}" != "NONE" ] && [ -n "${cur_flv_ver}" ]; then
                        local is_flv_newer
                        is_flv_newer=$(compare_versions_strictly_greater "${latest_flv_ver}" "${cur_flv_ver}" 2>/dev/null || echo "false")
                        if [ "${is_flv_newer}" = "true" ]; then
                            local nv_ready=1
                            if [ "${HAS_NVIDIA:-false}" = "true" ]; then
                                local gpu_arch="MODERN"
                                if command -v detect_nvidia_gpu >/dev/null 2>&1; then
                                    gpu_arch=$(detect_nvidia_gpu)
                                fi
                                if [ "${gpu_arch}" = "MODERN" ]; then
                                    if [ "${nv_url}" = "NONE" ] && ! command -v dkms >/dev/null 2>&1; then
                                        nv_ready=0
                                    fi
                                fi
                            fi

                            if [ "${nv_ready}" -eq 1 ]; then
                                local flv_name="linux-cachyos"
                                [ "${flv}" = "bore" ] && flv_name="linux-cachyos-bore"
                                [ "${flv}" = "lto" ] && flv_name="linux-cachyos-bore-lto"
                                [ "${flv}" = "eevdf" ] && flv_name="linux-cachyos-eevdf"
                                [ "${flv}" = "bmq" ] && flv_name="linux-cachyos-bmq"
                                [ "${flv}" = "deckify" ] && flv_name="linux-cachyos-deckify"
                                [ "${flv}" = "rt-bore" ] && flv_name="linux-cachyos-rt-bore"
                                [ "${flv}" = "rc" ] && flv_name="linux-cachyos-rc"
                                [ "${flv}" = "lts" ] && flv_name="linux-cachyos-lts"
                                [ "${flv}" = "zen" ] && flv_name="linux-zen"
                                [ "${flv}" = "arch" ] && flv_name="linux"
                                CACHY_UPDATES+=("${flv_name}-${latest_flv_ver} (Installed: ${cur_flv_ver})")
                            fi
                        fi
                    fi
                done <<< "${raw_batch}"
                local want_flv
                for want_flv in ${installed_flavors}; do
                    case "${answered_flavors}" in *" ${want_flv} "*) ;; *) cachy_partial=1 ;; esac
                done
            else
                for flv in ${installed_flavors}; do
                    local cur_flv_ver latest_flv_ver k_url h_url nv_url r8125_url
                    cur_flv_ver=$(get_installed_cachyos_flavor_version "${flv}" 2>/dev/null || echo "NONE")
                    read -r latest_flv_ver k_url h_url nv_url r8125_url <<< "$(check_cachyos_upstream_flavor "${flv}" || echo "NONE NONE NONE NONE NONE")"
                    if [ "${latest_flv_ver}" = "NONE" ] || [ -z "${latest_flv_ver}" ]; then
                        cachy_partial=1
                    fi

                    if [ "${latest_flv_ver}" != "NONE" ] && [ -n "${latest_flv_ver}" ] && [ "${cur_flv_ver}" != "NONE" ]; then
                        local is_flv_newer
                        is_flv_newer=$(compare_versions_strictly_greater "${latest_flv_ver}" "${cur_flv_ver}" 2>/dev/null || echo "false")
                        if [ "${is_flv_newer}" = "true" ]; then
                            local nv_ready=1
                            if [ "${HAS_NVIDIA:-false}" = "true" ]; then
                                local gpu_arch="MODERN"
                                if command -v detect_nvidia_gpu >/dev/null 2>&1; then
                                    gpu_arch=$(detect_nvidia_gpu)
                                fi
                                if [ "${gpu_arch}" = "MODERN" ]; then
                                    if [ "${nv_url}" = "NONE" ] && ! command -v dkms >/dev/null 2>&1; then
                                        nv_ready=0
                                    fi
                                fi
                            fi

                            if [ "${nv_ready}" -eq 1 ]; then
                                local flv_name="linux-cachyos"
                                [ "${flv}" = "bore" ] && flv_name="linux-cachyos-bore"
                                [ "${flv}" = "lto" ] && flv_name="linux-cachyos-bore-lto"
                                [ "${flv}" = "eevdf" ] && flv_name="linux-cachyos-eevdf"
                                [ "${flv}" = "bmq" ] && flv_name="linux-cachyos-bmq"
                                [ "${flv}" = "deckify" ] && flv_name="linux-cachyos-deckify"
                                [ "${flv}" = "rt-bore" ] && flv_name="linux-cachyos-rt-bore"
                                [ "${flv}" = "rc" ] && flv_name="linux-cachyos-rc"
                                [ "${flv}" = "lts" ] && flv_name="linux-cachyos-lts"
                                [ "${flv}" = "zen" ] && flv_name="linux-zen"
                                [ "${flv}" = "arch" ] && flv_name="linux"
                                CACHY_UPDATES+=("${flv_name}-${latest_flv_ver} (Installed: ${cur_flv_ver})")
                            fi
                        fi
                    fi
                done
            fi
            printf "%s\n" "${CACHY_UPDATES[@]:-}" > "${TMP_DIR}/cachy_updates"
            echo "SUCCESS" > "${TMP_DIR}/cachy_status"
            [ "${cachy_partial}" -eq 0 ] || echo "cachyos_kernel" >> "${TMP_DIR}/check_failed_parts"
        else
            echo "NA" > "${TMP_DIR}/cachy_status"
        fi
    else
        # mod_kernel.sh could not be loaded: nothing was looked at
        echo "FAILED" > "${TMP_DIR}/cachy_status"
    fi
}
check_cachyos_background & PID_CACHY=$!

# --- [ 3.5. CACHYOS GAMING SUITE UPDATE CHECK ] ---
check_cachyos_gaming_background() {
    [ "${SLACKY_OFFLINE}" -eq 1 ] && return 0
    local GAMING_UPDATES=()
    local LIB_DIR
    LIB_DIR="$(dirname "$(readlink -f "$0")")"
    if [ -f "${LIB_DIR}/mod_gaming.sh" ]; then
        source "${LIB_DIR}/mod_gaming.sh" 2>/dev/null || true
    elif [ -f "/usr/share/slacky-update/lib/mod_gaming.sh" ]; then
        source "/usr/share/slacky-update/lib/mod_gaming.sh" 2>/dev/null || true
    fi

    if command -v check_all_installed_gaming_updates_fast >/dev/null 2>&1; then
        local raw_g_updates g_rc=0
        # 6A-298 (F1): a lookup that crashed is "could not check", not "no gaming updates"
        # 6A-357: items that cannot be looked up by design (spacenav) are reported through this file ("manual"), not as a
        # failed check; the checker writes one id per line when it supports it
        export SLACKY_GAMING_MANUAL_FILE="${TMP_DIR}/gaming_manual"
        : > "${SLACKY_GAMING_MANUAL_FILE}"
        raw_g_updates=$(check_all_installed_gaming_updates_fast 2>/dev/null) || g_rc=$?
        # 6A-306 (V4): exit 3 = some items could not be checked (the rest of the answer is valid); any other failure = nothing
        if [ "${g_rc}" -eq 3 ]; then
            echo "cachyos_gaming" >> "${TMP_DIR}/check_failed_parts"
        elif [ "${g_rc}" -ne 0 ]; then
            echo "FAILED" > "${TMP_DIR}/gaming_status"
            return 0
        fi
        if [ -n "${raw_g_updates}" ]; then
            while IFS='|' read -r pid name cur_ver latest_ver; do
                [ -n "${pid}" ] || continue
                GAMING_UPDATES+=("${name} ${latest_ver} (Installed: ${cur_ver})")
            done <<< "${raw_g_updates}"
        fi
        printf "%s\n" "${GAMING_UPDATES[@]:-}" > "${TMP_DIR}/gaming_updates"
        echo "${raw_g_updates}" > "${TMP_DIR}/gaming_updates_raw"
        echo "SUCCESS" > "${TMP_DIR}/gaming_status"
    elif command -v get_gaming_catalog >/dev/null 2>&1; then
        local gaming_partial=0
        while IFS='|' read -r pkg_id name cat main_pat l32_pat ext_pat repos; do
            [ -n "${pkg_id}" ] || continue
            local cur_ver
            cur_ver=$(get_installed_gaming_pkg_version "${pkg_id}" 2>/dev/null || echo "NONE")
            [ "${cur_ver}" != "NONE" ] || continue

            local latest_ver main_u l32_u ext_u
            read -r latest_ver main_u l32_u ext_u <<< "$(resolve_cachyos_gaming_upstream_metadata "${pkg_id}" 2>/dev/null || echo "NONE NONE NONE NONE")"
            if [ "${latest_ver}" = "NONE" ] || [ -z "${latest_ver}" ]; then
                gaming_partial=1
            fi
            if [ "${latest_ver}" != "NONE" ] && [ -n "${latest_ver}" ]; then
                local is_newer
                is_newer=$(compare_versions_strictly_greater "${latest_ver}" "${cur_ver}" 2>/dev/null || echo "false")
                if [ "${is_newer}" = "true" ]; then
                    GAMING_UPDATES+=("${name} ${latest_ver} (Installed: ${cur_ver})")
                fi
            fi
        done <<< "$(get_gaming_catalog 2>/dev/null || echo "")"
        printf "%s\n" "${GAMING_UPDATES[@]:-}" > "${TMP_DIR}/gaming_updates"
        echo "SUCCESS" > "${TMP_DIR}/gaming_status"
        [ "${gaming_partial}" -eq 0 ] || echo "cachyos_gaming" >> "${TMP_DIR}/check_failed_parts"
    else
        echo "SUCCESS" > "${TMP_DIR}/gaming_status"
    fi
}
check_cachyos_gaming_background & PID_GAMING=$!

# --- [ 3.5. UNDERPANTS GNOMES PACMAN ENGINE INSPECTION ] ---
check_underpants_gnomes_background() {
    [ "${SLACKY_OFFLINE}" -eq 1 ] && return 0
    local gnomes_py=""
    for gcand in "${SCRIPT_DIR:-}/gnomes_pacman.py" \
                 "${APP_DIR:-}/gnomes_pacman.py" \
                 "/usr/share/slacky-update/lib/gnomes_pacman.py" \
                 "/usr/local/share/slacky-update/lib/gnomes_pacman.py" \
                 "/usr/local/lib/slacky-update/gnomes_pacman.py"; do
        if [ -f "${gcand}" ]; then
            gnomes_py="${gcand}"
            break
        fi
    done

    local force_sync="false"
    if [[ "${*:-}" =~ --sync|-y|-Sy ]]; then
        force_sync="true"
    fi

    if [ -n "${gnomes_py}" ] && command -v python3 >/dev/null 2>&1; then
        python3 - "${gnomes_py}" "${TMP_DIR}" "${force_sync}" << 'PYGNOMES'
import sys, os, json, subprocess

gpy = sys.argv[1]
tmp_d = sys.argv[2]
force_sync = (sys.argv[3] == "true") if len(sys.argv) > 3 else False

try:
    cmd = [sys.executable, gpy, "list-updates", "--json"]
    if force_sync:
        cmd.append("--sync")
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=10)
    if res.returncode == 0 and res.stdout.strip():
        updates = json.loads(res.stdout)
        lines = []
        raw_lines = []
        for u in updates:
            n = u.get("name", "")
            iv = u.get("installed_version", "")
            uv = u.get("upstream_version", "")
            r = u.get("repo", "")
            if n and uv:
                lines.append(f"{n} {uv} (Installed: {iv}) [{r}]")
                raw_lines.append(f"{n}|{uv}|{iv}|{r}")
        with open(os.path.join(tmp_d, "gnomes_updates"), "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + ("\n" if lines else ""))
        with open(os.path.join(tmp_d, "gnomes_updates_raw"), "w", encoding="utf-8") as f:
            f.write("\n".join(raw_lines) + ("\n" if raw_lines else ""))
        with open(os.path.join(tmp_d, "gnomes_status"), "w", encoding="utf-8") as f:
            f.write("SUCCESS\n")
    else:
        # 6A-298 (N0): a helper that failed or answered nothing is "could not check" (a clean answer is a JSON list)
        with open(os.path.join(tmp_d, "gnomes_status"), "w", encoding="utf-8") as f:
            f.write("FAILED\n")
except Exception:
    with open(os.path.join(tmp_d, "gnomes_status"), "w", encoding="utf-8") as f:
        f.write("FAILED\n")
PYGNOMES
    else
        echo "SUCCESS" > "${TMP_DIR}/gnomes_status"
    fi
}
check_underpants_gnomes_background "$@" & PID_GNOMES=$!

# --- [ 3.6. SHARED RUNTIME REFRESH DUE? (7J, docs/runtime_refresh_spec.md section 3) ] ---
# Read only: the cached repository databases, the runtime manifest and the state file; no network, no sudo, no build, no
# write to /opt. The answer goes into the status key "runtime_refresh" (not counted as an update).
check_runtime_refresh_background() {
    local rr_py="" rcand
    for rcand in "${SCRIPT_DIR:-}/gnomes_pacman.py" \
                 "${APP_DIR:-}/gnomes_pacman.py" \
                 "/usr/share/slacky-update/lib/gnomes_pacman.py" \
                 "/usr/local/share/slacky-update/lib/gnomes_pacman.py" \
                 "/usr/local/lib/slacky-update/gnomes_pacman.py"; do
        if [ -f "${rcand}" ]; then
            rr_py="${rcand}"
            break
        fi
    done
    [ -n "${rr_py}" ] && command -v python3 >/dev/null 2>&1 || return 0
    local rr_out
    rr_out=$(timeout 45 python3 "${rr_py}" runtime refresh-status 2>/dev/null) || return 0
    [ -n "${rr_out}" ] && printf '%s\n' "${rr_out}" > "${TMP_DIR}/runtime_refresh" || true
}
check_runtime_refresh_background & PID_RR=$!

# 6A-141: self-contained NVIDIA generation check (this worker runs standalone, so it cannot rely on mod_nvidia.sh).
# Prints "modern" when every NVIDIA display device is Turing or newer (PCI device ID >= 0x1e00), "legacy" when any is
# older (Pascal/Volta 0x15xx-0x1dxx, Maxwell and below), "none" when no NVIDIA display device is visible.
slacky_check_nvidia_gpu_class() {
    local pci_root="${1:-/sys/bus/pci/devices}"
    local dev vendor class device found="none"
    for dev in "${pci_root}"/*; do
        [ -r "${dev}/vendor" ] && [ -r "${dev}/class" ] && [ -r "${dev}/device" ] || continue
        vendor=$(tr -d '[:space:]' < "${dev}/vendor" 2>/dev/null || true)
        [ "${vendor}" = "0x10de" ] || continue
        class=$(tr -d '[:space:]' < "${dev}/class" 2>/dev/null || true)
        [[ "${class}" == 0x03* ]] || continue
        device=$(tr -d '[:space:]' < "${dev}/device" 2>/dev/null || true)
        [[ "${device}" =~ ^0x[0-9a-fA-F]{4}$ ]] || continue
        if (( 16#${device#0x} >= 16#1e00 )); then
            if [ "${found}" = "none" ]; then found="modern"; fi
        else
            found="legacy"
        fi
    done
    echo "${found}"
}

# --- [ 4. NVIDIA HARDWARE & DRIVER CHECK ] ---
(
    [ "${SLACKY_OFFLINE}" -eq 1 ] && exit 0
    NVIDIA_UPDATES=()
    NVIDIA_ACTIVE_VER=""
    NVIDIA_MISMATCH="false"
    NVIDIA_LOOKUP_FAILED=0

    if [ -f "/sys/module/nvidia/version" ]; then
        NVIDIA_ACTIVE_VER=$(cat /sys/module/nvidia/version 2>/dev/null | tr -d '[:space:]' || true)
    elif [ -f "/proc/driver/nvidia/version" ]; then
        NVIDIA_ACTIVE_VER=$(head -n 1 /proc/driver/nvidia/version | awk '{print $8}' 2>/dev/null || true)
    fi

    # 6A-141: pre-Turing NVIDIA is refused in 1.0, so no driver update is offered for it
    NVIDIA_GPU_CLASS=$(slacky_check_nvidia_gpu_class)
    if [ -n "${NVIDIA_ACTIVE_VER}" ]; then
        HAS_CACHY_LOCAL="false"
        if ls /boot/vmlinuz*cachyos* 1>/dev/null 2>&1 || ls -d /lib/modules/*cachyos* 1>/dev/null 2>&1; then
            HAS_CACHY_LOCAL="true"
        fi

        if [ "${HAS_CACHY_LOCAL}" = "true" ]; then
            cachy_nv_repo=$(get_cachyos_repo_url "${SLACKY_CPU_TIER:-generic}")
            if ! command -v get_cachyos_nvidia_repo_url >/dev/null 2>&1; then
                for mod_cand in "${APP_DIR:-}/mod_nvidia.sh" "${SCRIPT_DIR:-}/mod_nvidia.sh" "/usr/share/slacky-update/lib/mod_nvidia.sh"; do
                    if [ -f "${mod_cand}" ]; then
                        # shellcheck source=/dev/null
                        source "${mod_cand}" 2>/dev/null || true
                        break
                    fi
                done
            fi
            if command -v get_cachyos_nvidia_repo_url >/dev/null 2>&1; then
                cachy_nv_repo=$(get_cachyos_nvidia_repo_url)
            fi
            cachy_nv_html=$(curl -fsSL -m 10 "${cachy_nv_repo}" 2>/dev/null || echo "")
            [ -n "${cachy_nv_html}" ] || NVIDIA_LOOKUP_FAILED=1
            LATEST_NVIDIA=$(echo "${cachy_nv_html}" | grep -o -E 'nvidia-utils-[0-9]+\.[0-9]+(\.[0-9]+)?' | sed 's/nvidia-utils-//' | sort -V | tail -n 1 || true)
            # 6A-356: a page that came back but names no nvidia-utils package is a failed lookup (error page, wrong folder)
            [ -n "${LATEST_NVIDIA}" ] || NVIDIA_LOOKUP_FAILED=1
            # Atomic Triad Preflight Gate ("Spider-Sense"):
            # Ensure target LATEST_NVIDIA exists simultaneously across userspace, DKMS, and precompiled modules
            if [ -n "${LATEST_NVIDIA}" ]; then
                has_dkms_triad="false"
                has_mod_triad="false"
                if echo "${cachy_nv_html}" | grep -q -E "nvidia-(open-)?dkms.*${LATEST_NVIDIA}"; then
                    has_dkms_triad="true"
                fi
                if echo "${cachy_nv_html}" | grep -q -E "linux-cachyos.*-nvidia-open"; then
                    has_mod_triad="true"
                fi
                if [ "${has_dkms_triad}" != "true" ] || [ "${has_mod_triad}" != "true" ]; then
                    LATEST_NVIDIA=""
                fi
            fi
        elif [ "${NVIDIA_GPU_CLASS}" = "modern" ]; then
            # 6A-141: the newest .run branch supports Turing and newer
            # 6A-312 (V3): offer exactly what "production" would install (the installed driver's own branch), not latest.txt,
            # which can name a newer major that the install would never take (an update offered forever)
            if ! command -v nvidia_production_offer_version >/dev/null 2>&1; then
                for mod_cand in "${APP_DIR:-}/mod_nvidia.sh" "${SCRIPT_DIR:-}/mod_nvidia.sh" "/usr/share/slacky-update/lib/mod_nvidia.sh"; do
                    if [ -f "${mod_cand}" ]; then
                        # shellcheck source=/dev/null
                        source "${mod_cand}" 2>/dev/null || true
                        break
                    fi
                done
            fi
            LATEST_NVIDIA=""
            if command -v nvidia_production_offer_version >/dev/null 2>&1; then
                LATEST_NVIDIA=$(NVIDIA_ACTIVE_VER="${NVIDIA_ACTIVE_VER}" nvidia_production_offer_version || true)
            fi
            # 6A-298 (V4): an answer that is not a version number (error page, empty) is "unknown", not a version
            [[ "${LATEST_NVIDIA}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || { LATEST_NVIDIA=""; NVIDIA_LOOKUP_FAILED=1; }
        else
            # 6A-141: GPU generation unknown: only offer a newer release inside the installed major branch
            nv_major="${NVIDIA_ACTIVE_VER%%.*}"
            LATEST_NVIDIA=""
            if [[ "${nv_major}" =~ ^[0-9]+$ ]]; then
                nv_index=$(curl -fsSL -m 8 "https://download.nvidia.com/XFree86/Linux-x86_64/" 2>/dev/null || true)
                [ -n "${nv_index}" ] || NVIDIA_LOOKUP_FAILED=1
                LATEST_NVIDIA=$(echo "${nv_index}" \
                    | grep -o -E "href=['\"]${nv_major}\.[0-9]+(\.[0-9]+)?/" | grep -o -E "${nv_major}\.[0-9]+(\.[0-9]+)?" \
                    | sort -V | tail -n 1 || true)
            fi
        fi

        # 6A-141: no driver offer at all for a pre-Turing card (the Flatpak GL check below still runs)
        if [ "${NVIDIA_GPU_CLASS}" = "legacy" ]; then LATEST_NVIDIA=""; fi
        if [ -n "${LATEST_NVIDIA}" ]; then
            IS_NEWER=$(python3 -I -c "
import sys, re
def p(v): return [int(x) for x in re.sub(r'[^0-9.]', '', v).split('.') if x.isdigit()]
sys.exit(0 if p(sys.argv[1]) > p(sys.argv[2]) else 1)
" "${LATEST_NVIDIA}" "${NVIDIA_ACTIVE_VER}" && echo "true" || echo "false")

            if [ "${IS_NEWER}" = "true" ]; then
                if [ "${HAS_CACHY_LOCAL}" = "true" ]; then
                    NVIDIA_UPDATES+=("CachyOS NVIDIA Complete Suite ${LATEST_NVIDIA} (64-bit, 32-bit Multilib, OpenCL & VA-API) [CachyOS Master Update]")
                else
                    NVIDIA_UPDATES+=("nvidia-driver-${LATEST_NVIDIA} (Installed: ${NVIDIA_ACTIVE_VER})")
                fi
            elif [ "${HAS_CACHY_LOCAL}" = "true" ]; then
                # Version matches, but user is on untracked .run user-space or missing OpenCL / VA-API
                if ! ls /var/log/packages/cachyos-nvidia-utils-* 1>/dev/null 2>&1; then
                    NVIDIA_UPDATES+=("CachyOS NVIDIA Complete Suite ${LATEST_NVIDIA} (64-bit, 32-bit Multilib, OpenCL & VA-API) [CachyOS Master Migration]")
                elif [ ! -f "/etc/OpenCL/vendors/nvidia.icd" ] || [ ! -f "/usr/lib64/dri/nvidia_drv_video.so" ]; then
                    NVIDIA_UPDATES+=("CachyOS NVIDIA Complete Suite ${LATEST_NVIDIA} (OpenCL & VA-API Hardware Acceleration) [Complete Suite Upgrade]")
                fi
            fi
        fi

        if command -v flatpak >/dev/null 2>&1; then
            MATCH_FOUND=$(python3 -c "
import subprocess, sys

active_ver = '${NVIDIA_ACTIVE_VER}'.strip()
ver_dash = active_ver.replace('.', '-')

try:
    out = subprocess.check_output(['flatpak', 'list', '--runtime'], text=True, stderr=subprocess.DEVNULL)
    for line in out.splitlines():
        if 'GL.nvidia' in line or 'nvidia' in line.lower():
            if active_ver in line or ver_dash in line:
                sys.exit(0)
except Exception:
    pass

sys.exit(1)
" && echo "true" || echo "false")

            if [ "${MATCH_FOUND}" != "true" ]; then
                NVIDIA_MISMATCH="true"
                # SpiderSense phase 1 (consent before any change): the status check only reports the mismatch; the
                # full update installs the matching Flatpak GL runtime in its Flatpak step (register_flatpak_gl_sync).
            fi
        fi
    fi

    printf "%s\n" "${NVIDIA_UPDATES[@]:-}" > "${TMP_DIR}/nvidia_updates"
    # 6A-298 (F1): no NVIDIA module loaded = nothing to check (NA); a failed version lookup = could not check
    if [ -z "${NVIDIA_ACTIVE_VER}" ]; then
        echo "NA" > "${TMP_DIR}/nvidia_status"
    elif [ "${NVIDIA_LOOKUP_FAILED}" -eq 1 ]; then
        echo "FAILED" > "${TMP_DIR}/nvidia_status"
    else
        echo "SUCCESS" > "${TMP_DIR}/nvidia_status"
    fi
    echo "${NVIDIA_MISMATCH}" > "${TMP_DIR}/nvidia_mismatch"
    echo "${NVIDIA_ACTIVE_VER}" > "${TMP_DIR}/nvidia_active_ver"
) & PID_NVIDIA=$!

# 6A-298 (N0c): a time limit on the whole network phase, so one hung mirror can never hold the check (and with it the
# tray and every later check, which wait for the lock) for ever. When it fires, the parts still running are stopped and
# count as "could not check" (their status file stays empty); everything that already answered is kept.
slacky_descendants() {
    local c
    for c in $(pgrep -P "$1" 2>/dev/null || true); do
        slacky_descendants "${c}"
        echo "${c}"
    done
}
SLACKY_CHECK_TIMEOUT="${SLACKY_CHECK_TIMEOUT:-240}"
(
    sleep "${SLACKY_CHECK_TIMEOUT}"
    echo 1 > "${TMP_DIR}/timed_out"
    for jp in ${PID_SLACK:-} ${PID_PLUS:-} ${PID_FLATPAK:-} ${PID_SBO:-} ${PID_CACHY:-} ${PID_GAMING:-} ${PID_GNOMES:-} ${PID_NVIDIA:-}; do
        for d in $(slacky_descendants "${jp}"); do kill -TERM "${d}" 2>/dev/null || true; done
        kill -TERM "${jp}" 2>/dev/null || true
    done
) >/dev/null 2>&1 &
PID_WATCHDOG=$!

wait "${PID_SLACK:-}" "${PID_PLUS:-}" "${PID_FLATPAK:-}" "${PID_SBO:-}" "${PID_CACHY:-}" "${PID_GAMING:-}" "${PID_GNOMES:-}" "${PID_NVIDIA:-}" "${PID_RR:-}" 2>/dev/null || true
pkill -TERM -P "${PID_WATCHDOG}" 2>/dev/null || true
kill -TERM "${PID_WATCHDOG}" 2>/dev/null || true
wait "${PID_WATCHDOG}" 2>/dev/null || true

# --- [ 5. SECURE BOOT STATUS ] ---
SB_STATE="disabled"
if command -v mokutil >/dev/null 2>&1; then
    if mokutil --sb-state 2>/dev/null | grep -qi "enabled"; then
        SB_STATE="enabled"
    fi
fi

# --- [ 6. CACHE SERIALIZATION & ATOMIC PERSISTENCE ] ---
python3 - "${TMP_DIR}" "${STATUS_FILE}" "${SB_STATE}" << 'PYJSON'
import sys, os, json, time, pwd, re
from datetime import datetime, timezone

tmp_dir = sys.argv[1]
status_file = sys.argv[2]
sb_state = sys.argv[3] if len(sys.argv) > 3 else "disabled"

# Identify candidate cache files
candidates = [status_file]
user_cache = os.path.expanduser("~/.cache/slacky-update/status.json")
if user_cache not in candidates:
    candidates.append(user_cache)

sudo_u = os.environ.get("SUDO_USER")
sudo_uid, sudo_gid, sudo_cache = None, None, None
if sudo_u and os.getuid() == 0:
    try:
        pw = pwd.getpwnam(sudo_u)
        sudo_uid, sudo_gid = pw.pw_uid, pw.pw_gid
        sudo_cache = os.path.join(pw.pw_dir, ".cache", "slacky-update", "status.json")
        if sudo_cache not in candidates:
            candidates.append(sudo_cache)
    except Exception:
        pass

if "/var/cache/slacky-update/status.json" not in candidates:
    candidates.append("/var/cache/slacky-update/status.json")

existing_data = {}
newest_ts = -1
for c in candidates:
    if os.path.exists(c):
        try:
            with open(c, "r", encoding="utf-8") as f:
                c_data = json.load(f)
                c_ts = float(c_data.get("last_check_ts", os.path.getmtime(c)))
                if c_ts > newest_ts:
                    newest_ts = c_ts
                    existing_data = c_data
        except Exception:
            pass

def read_file_lines(filename):
    filepath = os.path.join(tmp_dir, filename)
    if os.path.exists(filepath):
        try:
            with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
                return [line.strip() for line in f if line.strip()]
        except Exception:
            pass
    return []

def get_status(status_name):
    path = os.path.join(tmp_dir, status_name)
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return f.read().strip()
        except Exception:
            pass
    return "FAILED"

def get_persisted_list(filename, status_name, json_key):
    # "NA" = this suite does not apply here (no Flatpak, no CachyOS kernel, no NVIDIA module): its list is simply empty
    if get_status(status_name) in ("SUCCESS", "NA"):
        return read_file_lines(filename)
    return existing_data.get(json_key, [])

def read_file_content(filename, default=""):
    filepath = os.path.join(tmp_dir, filename)
    if os.path.exists(filepath):
        try:
            with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
                return f.read().strip()
        except Exception:
            pass
    return default

def merge_with_existing_uninstalled(new_list, existing_list):
    installed = set(os.listdir("/var/log/packages")) if os.path.exists("/var/log/packages") else set()
    result = list(new_list)
    seen_bases = set()
    for item in result:
        clean = os.path.basename(item)
        for ext in (".txz", ".tgz", ".tlz", ".tbz"):
            if clean.endswith(ext):
                clean = clean[:-len(ext)]
                break
        parts = clean.rsplit("-", 3)
        bname = parts[0] if len(parts) == 4 else clean
        seen_bases.add(bname)

    for item in existing_list:
        clean = os.path.basename(item)
        for ext in (".txz", ".tgz", ".tlz", ".tbz"):
            if clean.endswith(ext):
                clean = clean[:-len(ext)]
                break
        parts = clean.rsplit("-", 3)
        bname = parts[0] if len(parts) == 4 else clean
        if bname not in seen_bases:
            if clean not in installed:
                result.append(item)
                seen_bases.add(bname)
    return sorted(result)

def parse_pkg_details_local(filename):
    clean = re.sub(r'\.(t[xg]z|tlz|tbz)$', '', filename)
    parts = clean.split('-')
    if len(parts) >= 4:
        return "-".join(parts[:-3]), parts[-3], parts[-2], parts[-1], clean
    return clean, "0", "0", "0", clean

def split_numeric_local(s):
    tokens = re.split(r'(\d+)', str(s))
    res = []
    for t in tokens:
        if not t: continue
        if t.isdigit(): res.append(int(t))
        else: res.append(t)
    return res

def is_strictly_newer_local(inst_full, up_full):
    if inst_full == up_full: return False
    _, i_ver, _, i_bld, _ = parse_pkg_details_local(inst_full)
    _, u_ver, _, u_bld, _ = parse_pkg_details_local(up_full)
    i_v = split_numeric_local(i_ver)
    u_v = split_numeric_local(u_ver)
    if u_v != i_v: return u_v > i_v
    i_b = split_numeric_local(i_bld)
    u_b = split_numeric_local(u_bld)
    return u_b > i_b

def filter_uninstalled_slack_pkgs(pkg_list):
    installed_map = {}
    if os.path.exists("/var/log/packages"):
        for f in os.listdir("/var/log/packages"):
            parts = f.rsplit("-", 3)
            if len(parts) == 4:
                installed_map[parts[0]] = f
    
    filtered = []
    for item in pkg_list:
        clean = os.path.basename(item)
        bname, _, _, _, _ = parse_pkg_details_local(clean)
        if bname in installed_map:
            # If target package is strictly newer than installed, it is STILL uninstalled!
            if is_strictly_newer_local(installed_map[bname], clean):
                filtered.append(item)
        else:
            # Not installed at all -> keep
            filtered.append(item)
    return filtered

slackware_updates = get_persisted_list("slackware_updates", "slackware_status", "slackware_updates")
slackpkgplus_updates = get_persisted_list("slackpkgplus_updates", "slackpkgplus_status", "slackpkgplus_updates")
if get_status("slackware_status") == "SUCCESS":
    slackware_updates = merge_with_existing_uninstalled(slackware_updates, existing_data.get("slackware_updates", []))
if get_status("slackpkgplus_status") == "SUCCESS":
    slackpkgplus_updates = merge_with_existing_uninstalled(slackpkgplus_updates, existing_data.get("slackpkgplus_updates", []))

slackware_updates = filter_uninstalled_slack_pkgs(slackware_updates)
slackpkgplus_updates = filter_uninstalled_slack_pkgs(slackpkgplus_updates)
# 6A-243: install-new candidates are recomputed on every successful check (never carried forward: a package the owner
# skipped must not be listed for ever); on a failed run the old list stays, minus what got installed meanwhile
if get_status("slackware_new_status") == "SUCCESS":
    slackware_new_packages = read_file_lines("slackware_new_packages")
else:
    _inst_names = set()
    if os.path.exists("/var/log/packages"):
        for _f in os.listdir("/var/log/packages"):
            _p = _f.rsplit("-", 3)
            if len(_p) == 4:
                _inst_names.add(_p[0])
    slackware_new_packages = [x for x in existing_data.get("slackware_new_packages", [])
                              if parse_pkg_details_local(os.path.basename(x))[0] not in _inst_names]
slackpkgplus_unverified = read_file_lines("slackpkgplus_unverified") if get_status("slackpkgplus_status") == "SUCCESS" else existing_data.get("slackpkgplus_unverified", [])
flatpak_updates = get_persisted_list("flatpak_updates", "flatpak_status", "flatpak_updates")
sbo_updates = get_persisted_list("sbo_updates", "sbo_status", "sbo_updates")
cachy_updates = get_persisted_list("cachy_updates", "cachy_status", "cachyos_kernel_updates")
gaming_updates = get_persisted_list("gaming_updates", "gaming_status", "cachyos_gaming_updates")
gaming_updates_raw = get_persisted_list("gaming_updates_raw", "gaming_status", "cachyos_gaming_updates_raw")
gnomes_updates = get_persisted_list("gnomes_updates", "gnomes_status", "gnomes_updates")
gnomes_updates_raw = get_persisted_list("gnomes_updates_raw", "gnomes_status", "gnomes_updates_raw")

# Prevent duplicates between gnomes_updates and cachyos_gaming_updates
gnome_names = {u.split()[0].lower() for u in gnomes_updates if u.strip()}
# 6A-153: match on the curated id from the raw list (the display line starts with the long name, e.g.
# "Official Discord Linux Client"), and drop it from the raw list too, which is the list a deploy reads
dup_display = {r.split("|")[1].strip() for r in gaming_updates_raw
               if r.count("|") >= 3 and r.split("|")[0].strip().lower() in gnome_names}
gaming_updates_raw = [r for r in gaming_updates_raw if r.split("|")[0].strip().lower() not in gnome_names]
gaming_updates = [g for g in gaming_updates if g.strip() and g.split()[0].lower() not in gnome_names
                  and not any(n and g.startswith(n + " ") for n in dup_display)]

# 6A-298 (F1): the NVIDIA part keeps its last answer when it could not look (offline, timeout, lookup failed)
if get_status("nvidia_status") in ("SUCCESS", "NA"):
    nvidia_updates = read_file_lines("nvidia_updates")
else:
    nvidia_updates = existing_data.get("nvidia_driver_updates", [])
if get_status("nvidia_status"):
    nvidia_mismatch = read_file_content("nvidia_mismatch", "false").lower() == "true"
    nvidia_active_ver = read_file_content("nvidia_active_ver", "")
else:
    nvidia_mismatch = bool(existing_data.get("nvidia_gl_mismatch", False))
    nvidia_active_ver = existing_data.get("nvidia_driver_version", "")

# 6A-298 (N0/F1/N1): which parts could NOT be checked this time. A part counts as checked only when its worker wrote
# SUCCESS (or NA = not applicable); an empty or FAILED status, or a part that found only some of its answers, is listed.
check_offline = read_file_content("offline", "0") == "1"
check_timed_out = read_file_content("timed_out", "0") == "1"
check_failed = []
for _name, _st in (("slackware", "slackware_status"), ("slackpkgplus", "slackpkgplus_status"),
                   ("flatpak", "flatpak_status"), ("sbo", "sbo_status"), ("cachyos_kernel", "cachy_status"),
                   ("cachyos_gaming", "gaming_status"), ("gnomes", "gnomes_status"), ("nvidia", "nvidia_status")):
    if get_status(_st) not in ("SUCCESS", "NA"):
        check_failed.append(_name)
for _part in read_file_lines("check_failed_parts"):
    if _part not in check_failed:
        check_failed.append(_part)

# 6A-357: installed items that have no upstream list by design (shown once as "manual", never as a failed check)
manual_items = []
for _m in read_file_lines("gaming_manual"):
    if re.fullmatch(r'[A-Za-z0-9_.+-]{1,64}', _m) and _m not in manual_items:
        manual_items.append(_m)

# 7J: the runtime-refresh answer (spec 8.2). Only the documented fields are kept; a missing or broken answer keeps the last one.
runtime_refresh = existing_data.get("runtime_refresh")
try:
    _rr_raw = json.loads(read_file_content("runtime_refresh", "") or "null")
    if isinstance(_rr_raw, dict) and not _rr_raw.get("error") and _rr_raw.get("state") in (
            "nominal", "due", "due_now", "deferred", "remembered_veto", "unknown", "not_applicable"):
        runtime_refresh = {k: _rr_raw.get(k) for k in ("state", "age_days", "newer", "checked", "gone", "suspects", "built", "checked_at")}
except (ValueError, TypeError):
    pass

now_dt = datetime.now(timezone.utc)

data = {
    "slackware_updates": slackware_updates,
    "slackpkgplus_updates": slackpkgplus_updates,
    "slackpkgplus_unverified": slackpkgplus_unverified,
    "slackware_new_packages": slackware_new_packages,
    "flatpak_updates": flatpak_updates,
    "sbo_updates": sbo_updates,
    "cachyos_kernel_updates": cachy_updates,
    "cachyos_gaming_updates": gaming_updates,
    "cachyos_gaming_updates_raw": gaming_updates_raw,
    "gnomes_updates": gnomes_updates,
    "gnomes_updates_raw": gnomes_updates_raw,
    "nvidia_driver_updates": nvidia_updates,
    "reboot_required": False,
    "nvidia_gl_mismatch": nvidia_mismatch,
    "nvidia_driver_version": nvidia_active_ver,
    "secure_boot": {
        "state": sb_state,
        "warnings": []
    },
    # 6A-298: optional keys (the tray and the Rust reader ignore what they do not know). check_failed lists the parts
    # that could not be checked this time (ids: slackware, slackpkgplus, flatpak, sbo, cachyos_kernel, cachyos_gaming,
    # gnomes, nvidia); check_offline is true when no server could be reached at all; last_ok_check_ts is the last run
    # that checked everything.
    "check_failed": check_failed,
    "check_offline": check_offline,
    "check_timed_out": check_timed_out,
    "manual_items": manual_items,
    "runtime_refresh": runtime_refresh,
    "last_ok_check_ts": int(time.time()) if not check_failed else int(existing_data.get("last_ok_check_ts", 0) or 0),
    "last_check": now_dt.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "last_check_ts": int(time.time())
}

def _status_atomic(p, text):
    d = os.path.dirname(p)
    os.makedirs(d, exist_ok=True)
    if os.path.islink(d):
        return
    import tempfile
    fd, tmp = tempfile.mkstemp(prefix=".status.", dir=d)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, 0o644)
        os.replace(tmp, p)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise

def write_status_safely(path, data_obj, uid=None, gid=None):
    """6A-48: never follow a symlink as root. The system cache is written atomically (0644, was 0666); a user's cache
    is written by a child that first drops to that user's uid/gid, so a planted symlink gains nothing."""
    text = json.dumps(data_obj, indent=2)
    try:
        if os.geteuid() == 0 and uid is not None and gid is not None:
            pid = os.fork()
            if pid == 0:
                try:
                    os.setgroups([])
                    os.setgid(gid)
                    os.setuid(uid)
                    _status_atomic(path, text)
                    os._exit(0)
                except BaseException:
                    os._exit(1)
            _, st = os.waitpid(pid, 0)
            return st == 0
        _status_atomic(path, text)
        return True
    except Exception:
        return False

def save_json_safely(target_path, uid=None, gid=None):
    return write_status_safely(target_path, data, uid, gid)

# 1. Always write to current user status_file
save_json_safely(status_file)

# 2. If root under sudo, write to SUDO_USER cache with user ownership
if sudo_cache and sudo_uid is not None and sudo_gid is not None:
    save_json_safely(sudo_cache, sudo_uid, sudo_gid)

# 3. Attempt to update system cache
try:
    save_json_safely("/var/cache/slacky-update/status.json")
except Exception:
    pass
PYJSON

for sp in "/var/cache/slacky-update/status.json" "${USER_CACHE_DIR}/status.json"; do
    [ -f "${sp}" ] && touch "${sp}" 2>/dev/null || true
done


# 6A-202 (spec section 0): key freshness on EVERY check, after the repository databases were synced above. Read only against
# the key store; a keyring package is downloaded only when the database lists a newer one than the keys in force, and a
# package that passes every rule is only STAGED in the user's own cache (it is installed as the first root step of an
# explicit full update; root, e.g. the cron job, installs it at once as a new key generation, 6A-278). Rate limited to once
# a day, works without gnomes. Never sudo, silent, detached so it never delays the check.
{
    for cand in "${SCRIPT_DIR:-}/slacky_sentinel.py" \
                "${APP_DIR:-}/slacky_sentinel.py" \
                "/usr/share/slacky-update/lib/slacky_sentinel.py" \
                "/usr/local/share/slacky-update/lib/slacky_sentinel.py" \
                "/usr/local/lib/slacky-update/slacky_sentinel.py"; do
        [ "${SLACKY_CHECK_SKIP_BACKGROUND:-0}" = "1" ] && break   # self-tests only
        if [ -f "${cand}" ]; then
            nohup nice -n 19 ionice -c 3 python3 -I "${cand}" refresh-keys </dev/null >/dev/null 2>&1 &
            break
        fi
    done
}
