#!/usr/bin/env bash
# --- [ SHARED RUNTIME MONTHLY REFRESH: shell front end (7N) ] ---
# Spec: docs/runtime_refresh_spec.md ("underpants-runtime-refresh/1"). The Rust app implements the same spec, no shared code.
# Rules in short: offered only in an interactive full update, never automatic (no --yes, no cron, no tray); the candidate is
# built as the user, checked against every installed app, and installed with exactly one `sudo upgradepkg --reinstall`.
# The state file is written here (user process, run lock held), never by the root phase.

RR_OFFER=0
RR_SIZE=""
RR_COUNT=0
RR_CAND_BASIS=""
RR_APPS_BASIS=""
RR_NO_SNAP=0
RR_STAGING=""
# test hook, honoured only with SLACKY_SELFTEST=1: a fake root for the manifest and the package list
RR_ROOT=""
[ "${SLACKY_SELFTEST:-0}" = "1" ] && RR_ROOT="${SLACKY_RR_ROOT:-}"

rr_find() {
    local name="$1" c
    for c in "${APP_DIR:-}/${name}" "/usr/share/slacky-update/lib/${name}" "/usr/local/share/slacky-update/lib/${name}" \
             "/usr/local/lib/slacky-update/${name}"; do
        [ -f "${c}" ] && { printf '%s' "${c}"; return 0; }
    done
    return 1
}

# one JSON value from a file: rr_json FILE KEY  (empty when missing)
rr_json() {
    python3 -I -c '
import json, sys
try:
    v = json.load(open(sys.argv[1]))
    for k in sys.argv[2].split("."):
        v = v.get(k, "") if isinstance(v, dict) else ""
    print("" if v is None else v)
except Exception:
    print("")' "$1" "$2" 2>/dev/null || true
}

rr_log_line() {
    { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] SpiderSense: runtime-refresh $*" >> "${LOG_FILE:-/dev/null}"; } 2>/dev/null || true
}

# True when this system can make a safety snapshot (same test as create_pre_update_snapshot)
rr_has_snapshot_support() {
    [ "$(findmnt -n -o FSTYPE / 2>/dev/null)" = "btrfs" ] || return 1
    command -v snapper >/dev/null 2>&1 || return 1
    [ -f /etc/snapper/configs/root ]
}

rr_state_record() {
    local h
    h=$(rr_find slacky_runtime_refresh.py) || return 0
    python3 -I "${h}" state-record "$@" --writer "slacky-update ${CURRENT_VERSION:-}" >/dev/null 2>&1 || true
}

# Sets RR_OFFER=1 when the refresh is due, not suppressed (weekly re-ask, remembered stop) and this run is interactive (E4).
runtime_refresh_probe() {
    RR_OFFER=0
    [ "${NON_INTERACTIVE:-0}" = "1" ] && return 0
    [ -t 0 ] || return 0
    local py out
    py=$(rr_find gnomes_pacman.py) || return 0
    out=$(timeout 60 python3 "${py}" runtime refresh-status --no-record 2>/dev/null) || return 0
    [ -n "${out}" ] || return 0
    local line
    line=$(printf '%s' "${out}" | python3 -I -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print("\t".join([str(int(bool(d.get("offerable")))), str(d.get("size_hint", "1 GB")), str(d.get("checked", 0)),
                     str(d.get("candidate_basis", "")), str(d.get("apps_basis", ""))]))
except Exception:
    print("0\t\t0\t\t")' 2>/dev/null) || return 0
    local o
    IFS=$'\t' read -r o RR_SIZE RR_COUNT RR_CAND_BASIS RR_APPS_BASIS <<< "${line}"
    [ "${o}" = "1" ] || return 0
    RR_OFFER=1
    rr_has_snapshot_support || RR_NO_SNAP=1
    return 0
}

# Running apps: a warning only (owner decision D2, 2026-10-20). Prints one sentence naming the first one.
runtime_refresh_warn_running() {
    local h out app pid
    h=$(rr_find slacky_runtime_refresh.py) || return 0
    out=$(python3 -I "${h}" running-apps --exclude-pid "$$" 2>/dev/null) || return 0
    app=$(printf '%s' "${out}" | python3 -I -c 'import json,sys
try:
    d = json.load(sys.stdin); print(d[0]["app"] if d else "")
except Exception:
    print("")' 2>/dev/null) || return 0
    [ -n "${app}" ] || return 0
    pid=$(printf '%s' "${out}" | python3 -I -c 'import json,sys
try:
    d = json.load(sys.stdin); print(d[0]["pid"] if d else "")
except Exception:
    print("")' 2>/dev/null) || pid=""
    log_warn "$(_ RUNTIME_REFRESH_RUNNING_WARN app="${app}")"
    rr_log_line "RR-RUNNING-WARN app=${app} pid=${pid}"
}

# Snapshot gate (B8) for a runtime replacement. Reuses this run's pre-update snapshot. Result in RR_SNAP_NUM.
# Return 0 = go on (snapshot reused / made, or none possible: the warning was shown), 1 = a snapshot was needed and failed.
RR_SNAP_NUM=0
runtime_refresh_snapshot_gate() {
    RR_SNAP_NUM=0
    if [ -n "${SLACKY_SNAP_PRE:-}" ]; then
        RR_SNAP_NUM="${SLACKY_SNAP_PRE}"
        rr_log_line "RR-SNAPSHOT-REUSED #${RR_SNAP_NUM}"
        return 0
    fi
    if ! rr_has_snapshot_support; then
        rr_log_line "RR-NO-SNAPSHOT"
        return 0
    fi
    local rc=0
    create_pre_update_snapshot || rc=$?
    if [ "${rc}" -eq 0 ]; then
        RR_SNAP_NUM="${SLACKY_SNAP_PRE:-0}"
        rr_log_line "RR-SNAPSHOT-MADE #${RR_SNAP_NUM}"
        return 0
    fi
    if [ "${rc}" -eq 2 ]; then
        rr_log_line "RR-NO-SNAPSHOT"
        return 0
    fi
    rr_log_line "RR-SNAPSHOT-FAIL"
    return 1
}

rr_pkglist_hash() {
    ls "${RR_ROOT}/var/log/packages" 2>/dev/null | sort | sha256sum | cut -d' ' -f1
}

rr_cleanup() {
    local work="$1" py
    py=$(rr_find gnomes_pacman.py) || py=""
    if [ -n "${RR_STAGING}" ] && [ -n "${py}" ]; then
        python3 "${py}" runtime refresh-clean "${RR_STAGING}" >/dev/null 2>&1 || true
    fi
    RR_STAGING=""
    [ -n "${work}" ] && [ -d "${work}" ] && rm -rf "${work}" 2>/dev/null || true
}

# The user-phase / root-phase work. Return 0 = finished or skipped on purpose, 1 = the install itself failed.
rr_execute_inner() {
    local work="$1" py helper res out_dir
    py=$(rr_find gnomes_pacman.py) || return 0
    helper=$(rr_find slacky_runtime_refresh.py) || return 0
    out_dir="${work}/out"
    res="${out_dir}/result.json"

    printf '%s...' "$(_ RUNTIME_REFRESH_WORK_BUILD count="${RR_COUNT}")"
    local brc=0
    python3 "${py}" runtime refresh-build --output-dir "${out_dir}" > "${work}/build.log" 2>&1 || brc=$?
    local state app rule detail
    state=$(rr_json "${res}" state)
    app=$(rr_json "${res}" app)
    rule=$(rr_json "${res}" rule)
    detail=$(rr_json "${res}" detail)
    RR_STAGING=$(rr_json "${res}" staging_base)
    local cb ab
    cb=$(rr_json "${res}" candidate_basis)
    ab=$(rr_json "${res}" apps_basis)
    case "${state}" in
        skipped)
            echo ""
            return 0 ;;
        no_space)
            echo "failed"
            local need path free
            need=$(python3 -I -c 'import json,sys; print(json.loads(sys.argv[1]).get("need_gb",""))' "${detail}" 2>/dev/null || true)
            free=$(python3 -I -c 'import json,sys; print(json.loads(sys.argv[1]).get("free_gb",""))' "${detail}" 2>/dev/null || true)
            path=$(python3 -I -c 'import json,sys; print(json.loads(sys.argv[1]).get("path",""))' "${detail}" 2>/dev/null || true)
            log_warn "$(_ RUNTIME_REFRESH_NO_SPACE need="${need}" path="${path}" free="${free}")"
            rr_state_record result --result no_space
            return 0 ;;
        vetoed)
            echo "failed"
            log_warn "$(_ RUNTIME_REFRESH_VETO app="${app}")"
            rr_state_record result --result vetoed --candidate-basis "${cb}" --apps-basis "${ab}" --app "${app}" --rule "${rule}" --detail "${detail}"
            return 0 ;;
        built) ;;
        *)
            echo "failed"
            { sed 's/^/    /' "${work}/build.log" | tail -n 40 >> "${LOG_FILE:-/dev/null}"; } 2>/dev/null || true
            log_warn "$(_ RUNTIME_REFRESH_BUILD_FAILED)"
            rr_state_record result --result build_failed
            return 0 ;;
    esac
    echo "OK"
    local apps_n
    apps_n=$(rr_json "${res}" apps)
    printf '%s...OK\n' "$(_ RUNTIME_REFRESH_WORK_CHECK count="${apps_n:-0}")"

    local txz sha old_built new_built stg_rt
    txz=$(rr_json "${res}" txz)
    sha=$(rr_json "${res}" sha256)
    old_built=$(rr_json "${res}" old_built)
    new_built=$(rr_json "${res}" new_built)
    stg_rt=$(rr_json "${res}" staging_runtime)
    local pk_after_build
    pk_after_build=$(rr_pkglist_hash)

    # the archive: root-owned entries only, no path of another package (same guards as `gnomes runtime install`)
    if ! python3 "${py}" footprint-guard --verify-archive "${txz}" >> "${work}/build.log" 2>&1 \
       || ! python3 "${py}" footprint-guard --verify-host-paths "${txz}" --mode gnomes >> "${work}/build.log" 2>&1; then
        { tail -n 20 "${work}/build.log" >> "${LOG_FILE:-/dev/null}"; } 2>/dev/null || true
        log_warn "$(_ RUNTIME_REFRESH_BUILD_FAILED)"
        rr_state_record result --result build_failed
        return 0
    fi
    if [ "$(sha256sum "${txz}" 2>/dev/null | cut -d' ' -f1)" != "${sha}" ]; then
        log_warn "$(_ RUNTIME_REFRESH_BUILD_FAILED)"
        rr_state_record result --result build_failed
        return 0
    fi
    rr_log_line "RR-ACCEPTED"

    # root phase: same base? (nobody refreshed the runtime meanwhile)
    local live_built
    live_built=$(rr_json "${RR_ROOT}/opt/underpants/runtime/.gnomes/manifest.json" built)
    if [ "${live_built}" != "${old_built}" ]; then
        rr_log_line "RR-SKIP-CHANGED"
        return 0
    fi
    # a host package changed after the check: check the kept tree again against the host as it is now
    if [ "$(rr_pkglist_hash)" != "${pk_after_build}" ]; then
        local rc2=0 chk
        chk=$(python3 "${py}" runtime refresh-check --staging "${stg_rt}" --baseline "${res}" 2>/dev/null) || rc2=$?
        if [ "${rc2}" -ne 0 ]; then
            app=$(printf '%s' "${chk}" | python3 -I -c 'import json,sys
try: print(json.load(sys.stdin).get("first_app",""))
except Exception: print("")' 2>/dev/null || true)
            log_warn "$(_ RUNTIME_REFRESH_VETO app="${app:-an app}")"
            rr_state_record result --result vetoed --candidate-basis "${cb}" --apps-basis "${ab}" --app "${app}"
            return 0
        fi
    fi

    runtime_refresh_warn_running

    if ! runtime_refresh_snapshot_gate; then
        log_warn "$(_ RUNTIME_REFRESH_SNAPSHOT_FAILED)"
        rr_state_record result --result snapshot_failed
        return 0
    fi

    printf '%s...' "$(_ RUNTIME_REFRESH_WORK_INSTALL)"
    # the archive is the one that was checked (hash pinned at build time), then exactly one escalation
    if [ "$(sha256sum "${txz}" 2>/dev/null | cut -d' ' -f1)" = "${sha}" ] \
       && sudo upgradepkg --install-new --reinstall "${txz}" >> "${work}/build.log" 2>&1; then
        echo "OK"
    else
        echo "failed"
        { tail -n 30 "${work}/build.log" >> "${LOG_FILE:-/dev/null}"; } 2>/dev/null || true
        rr_log_line "RR-INSTALL-FAIL old=${old_built} snapshot=${RR_SNAP_NUM}"
        log_warn "$(_ RUNTIME_REFRESH_INSTALL_FAILED number="${RR_SNAP_NUM}")"
        rr_state_record result --result install_failed --snapshot "${RR_SNAP_NUM}"
        return 1
    fi

    # post-check on the live tree: the new runtime is the expected one and no app got a NEW failure
    local prc=0 pchk
    pchk=$(python3 "${py}" runtime refresh-check --baseline "${res}" --expect-built "${new_built}" 2>/dev/null) || prc=$?
    if [ "${prc}" -ne 0 ]; then
        app=$(printf '%s' "${pchk}" | python3 -I -c 'import json,sys
try: print(json.load(sys.stdin).get("first_app","") or "an app")
except Exception: print("an app")' 2>/dev/null || echo "an app")
        rr_log_line "RR-POSTCHECK-FAIL app=${app} snapshot=${RR_SNAP_NUM}"
        log_warn "$(_ RUNTIME_REFRESH_POSTCHECK app="${app}" number="${RR_SNAP_NUM}")"
        rr_state_record result --result postcheck_failed --snapshot "${RR_SNAP_NUM}"
        RR_INSTALLED=1
        return 0
    fi
    rr_log_line "RR-INSTALLED old=${old_built} new=${new_built} snapshot=${RR_SNAP_NUM}"
    rr_state_record result --result installed --built "${new_built}" --snapshot "${RR_SNAP_NUM}"
    RR_INSTALLED=1
    return 0
}

RR_INSTALLED=0
# Full-update step. Return 0 = nothing to report, 1 = the install failed (the run is partial).
runtime_refresh_execute() {
    local base work rc=0
    base="${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/slacky-update/gnomes/build"
    mkdir -p -m 0700 "${base}" 2>/dev/null || return 0
    work=$(mktemp -d "${base}/refresh-XXXXXX") || return 0
    chmod 0700 "${work}" 2>/dev/null || true
    RR_INSTALLED=0
    rr_execute_inner "${work}" || rc=$?
    rr_cleanup "${work}"
    return "${rc}"
}
