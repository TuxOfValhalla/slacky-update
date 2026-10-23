#!/usr/bin/env python3
"""7J-7N: monthly refresh of the shared Underpants runtime, the pure parts (docs/runtime_refresh_spec.md, "underpants-runtime-refresh/1").

Stdlib only, no network, nothing here installs or builds anything. The Rust app implements the same spec and shares NO code.

  detect()            section 3: age, usual-suspect ABI moves, the decision (nominal / due / due_now / ...)
  state_*()           section 7: the shared state file (weekly re-ask, remembered stopped candidate)
  space_plan()        section 5.2: disk space with the same-filesystem rule (/proc/self/mountinfo field 3)
  running_apps()      section 5.5 step 4: processes that map the runtime or an app below /opt/underpants (warning only, D2)
  rr_log()            section 11: one flight-recorder line "SpiderSense: runtime-refresh RR-..."

CLI (used by the shell front end, JSON on stdout):
  state-show                      effective state (after the rebuilt-runtime reset)
  state-record EVENT [options]    EVENT = offered | declined | result ; the ONLY writer, run by the user process of a full update
  space --installed S --csize C --missing M --build-dir D [--opt /opt]
  running-apps [--exclude-pid PID]
  log CODE MESSAGE
Test hooks are honoured ONLY with SLACKY_SELFTEST=1: SLACKY_RR_ROOT (fake root prefix), SLACKY_RR_NOW (epoch seconds),
SLACKY_RR_STATE (state file), SLACKY_RR_LOG (log file), SLACKY_RR_MOUNTINFO, SLACKY_RR_PROC, SLACKY_RR_FREE (JSON {path: bytes}).
"""
import calendar
import hashlib
import json
import os
import re
import stat as statmod
import sys
import time

SPEC = "underpants-runtime-refresh/1"
RUNTIME_DIR = "/opt/underpants/runtime"
PKGS_DIR = "/opt/underpants/pkgs"
PKGDB = "/var/log/packages"
MIN_AGE_DAYS = 30
REASK_SECONDS = 7 * 86400
MANIFEST_MAX = 16 * 1024 * 1024
STATE_MAX = 64 * 1024

# Spec 3.3: a usual suspect has an "ABI move" when its newer version differs in the first `depth` dot components of the upstream
# version (epoch stripped, pkgrel ignored). The table is data shared with the Rust app by spec; keep both identical.
USUAL_SUSPECTS = {
    "qt6-base": 2, "qt6-declarative": 2, "qt5-base": 2, "gtk4": 2, "gtk3": 2, "icu": 1, "ffmpeg": 1, "openssl": 2,
    "python": 2, "gstreamer": 2, "gst-plugins-base-libs": 2, "harfbuzz": 1, "libxml2": 2, "protobuf": 1,
    "abseil-cpp": 1, "poppler": 1,
}
RESULTS = ("none", "installed", "declined", "vetoed", "build_failed", "no_space", "snapshot_failed",
           "install_failed", "postcheck_failed")


def _test_env(name):
    if os.environ.get("SLACKY_SELFTEST") == "1":
        return os.environ.get(name)
    return None


def _root():
    return _test_env("SLACKY_RR_ROOT") or ""


def now_ts():
    v = _test_env("SLACKY_RR_NOW")
    try:
        return float(v) if v else time.time()
    except ValueError:
        return time.time()


def iso(ts):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(ts))


def parse_iso(s):
    """YYYY-MM-DDTHH:MM:SSZ (UTC) -> epoch seconds, else None."""
    if not isinstance(s, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", s):
        return None
    try:
        return float(calendar.timegm(time.strptime(s, "%Y-%m-%dT%H:%M:%SZ")))
    except ValueError:
        return None


# ----------------------------------------------------------------------------------------------------------------------
# recorder (section 11)
# ----------------------------------------------------------------------------------------------------------------------
def _log_path():
    t = _test_env("SLACKY_RR_LOG")
    if t:
        return t
    if os.geteuid() == 0:
        return "/var/log/slacky-update.log"
    sysfile = "/var/log/slacky-update.log"
    if os.access(sysfile, os.W_OK):
        return sysfile
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return os.path.join(base, "slacky-update", "slacky-update.log")


def rr_log(code, message="", throttle_daily=False):
    """One line in the app's log file. Never raises. With throttle_daily the same code is written at most once per day."""
    try:
        path = _log_path()
        if throttle_daily:
            seen_path = os.path.join(os.path.dirname(path), "runtime_refresh_seen.json")
            seen = {}
            try:
                with open(seen_path, encoding="utf-8") as fh:
                    seen = json.load(fh)
                if not isinstance(seen, dict):
                    seen = {}
            except (OSError, ValueError):
                seen = {}
            today = time.strftime("%Y-%m-%d", time.gmtime(now_ts()))
            if seen.get(code) == today:
                return
            seen[code] = today
            try:
                with open(seen_path, "w", encoding="utf-8") as fh:
                    json.dump(seen, fh)
            except OSError:
                pass
        os.makedirs(os.path.dirname(path), exist_ok=True)
        stamp = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(now_ts()))
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(f"[{stamp}] [INFO] SpiderSense: runtime-refresh {code} {message}".rstrip() + "\n")
    except Exception:
        pass


# ----------------------------------------------------------------------------------------------------------------------
# safe reads
# ----------------------------------------------------------------------------------------------------------------------
def read_json_nofollow(path, max_bytes, owner_check=False, euid=None, owner_uid=None):
    """(object, reason). O_NOFOLLOW, regular file, size cap, JSON object. owner_check: owned by the effective uid or root and
    not group/other-writable (the state file rule)."""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    except OSError as e:
        return None, "missing" if e.errno == 2 else "unreadable"
    try:
        st = os.fstat(fd)
        if not statmod.S_ISREG(st.st_mode):
            return None, "not a regular file"
        if st.st_size > max_bytes:
            return None, "too large"
        if owner_check:
            # euid / owner_uid: fixture hooks (a file cannot be chowned in a test); None = the real values
            me = os.geteuid() if euid is None else euid
            if (st.st_uid if owner_uid is None else owner_uid) not in (me, 0):
                return None, "wrong owner"
            if st.st_mode & 0o022:
                return None, "writable by others"
        data = b""
        while len(data) <= max_bytes:
            chunk = os.read(fd, 65536)
            if not chunk:
                break
            data += chunk
        if len(data) > max_bytes:
            return None, "too large"
    finally:
        os.close(fd)
    try:
        obj = json.loads(data.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return None, "not json"
    if not isinstance(obj, dict):
        return None, "not an object"
    return obj, ""


def version_tuple(v):
    return tuple(int(x) for x in re.findall(r"\d+", str(v))[:4]) or (0,)


def read_manifest(runtime_dir=None):
    """(manifest, mtime, reason). Spec 3.1: schema 1, version >= 1.1."""
    path = os.path.join(runtime_dir or (_root() + RUNTIME_DIR), ".gnomes", "manifest.json")
    m, why = read_json_nofollow(path, MANIFEST_MAX)
    if m is None:
        return None, 0.0, why
    if m.get("schema") != 1 or version_tuple(m.get("version", "0")) < (1, 1) or not isinstance(m.get("packages"), list):
        return None, 0.0, "manifest not usable"
    try:
        mtime = os.stat(path).st_mtime
    except OSError:
        mtime = 0.0
    return m, mtime, ""


# ----------------------------------------------------------------------------------------------------------------------
# detection (section 3)
# ----------------------------------------------------------------------------------------------------------------------
def upstream_components(version, depth):
    """First `depth` dot components of the upstream version: epoch and pkgrel removed."""
    v = str(version or "").strip()
    v = re.sub(r"^\d+:", "", v)
    if "-" in v:
        v = v.rsplit("-", 1)[0]
    return v.split(".")[:depth]


def abi_move(old, new, depth):
    return upstream_components(old, depth) != upstream_components(new, depth)


def age_of(manifest, manifest_mtime, now):
    """(age_days or None when unknown, clock_future). Spec 3.2."""
    built = parse_iso(manifest.get("built"))
    if built is None:
        built = manifest_mtime or None
    if built is None:
        return None, False
    if built - now > 86400:
        return 0, True
    return max(0, int((now - built) // 86400)), False


def members_of(manifest):
    host_only = {h.get("package") for h in manifest.get("host_only", []) if isinstance(h, dict)}
    out = []
    for p in manifest.get("packages", []):
        if isinstance(p, dict) and p.get("name") and p.get("name") not in host_only:
            out.append((str(p["name"]), str(p.get("version", ""))))
    return out


def candidate_basis(newest):
    """SHA-256 of the sorted '<name>=<newest repository version>\\n' lines over members the repository has."""
    lines = sorted(f"{n}={v}\n".encode("utf-8") for n, v in newest.items())
    return hashlib.sha256(b"".join(lines)).hexdigest()


def apps_basis(pkgdb=None):
    """SHA-256 of the sorted '<package id>\\n' lines of every installed underpants-* package except the runtime."""
    d = pkgdb or (_root() + PKGDB)
    try:
        names = sorted(n for n in os.listdir(d) if n.startswith("underpants-") and not n.startswith("underpants-runtime-"))
    except OSError:
        names = []
    return hashlib.sha256(b"".join(f"{n}\n".encode("utf-8") for n in names)).hexdigest()


def size_hint(profile, pkgdb=None):
    """'893 MB' / '1.2 GB' from the compressed size in the installed runtime package's log header, else '1 GB'."""
    d = pkgdb or (_root() + PKGDB)
    try:
        for n in sorted(os.listdir(d)):
            if n.startswith(f"underpants-runtime-{profile}-"):
                with open(os.path.join(d, n), encoding="utf-8", errors="replace") as fh:
                    head = fh.read(600)
                m = re.search(r"COMPRESSED PACKAGE SIZE:\s*([0-9.]+)\s*([KMG])", head)
                if m:
                    mb = float(m.group(1)) * {"K": 1 / 1024, "M": 1, "G": 1024}[m.group(2)]
                    return f"{mb / 1024:.1f} GB" if mb >= 1024 else f"{int(round(mb))} MB"
    except (OSError, ValueError):
        pass
    return "1 GB"


def eligible(manifest, profiles, runtime_dir=None, pkgdb=None):
    """Spec E1/E2: manifest-current monolith with a known profile and a package log; no bricks."""
    if manifest is None or manifest.get("profile") not in profiles:
        return False
    rd = runtime_dir or (_root() + RUNTIME_DIR)
    if os.path.exists(os.path.join(rd, ".bricks", "layout.json")):
        return False
    d = pkgdb or (_root() + PKGDB)
    try:
        return any(n.startswith(f"underpants-runtime-{manifest['profile']}-") for n in os.listdir(d))
    except OSError:
        return False


def detect(manifest, mtime, repo_versions, newer, now, profiles, runtime_dir=None, pkgdb=None):
    """Spec 3.4 without the state file. repo_versions: {name: newest version} or None/{} when no index is cached.
    newer(a, b) is True when a is strictly newer than b. Returns the status key (section 8.2) plus 'newest' (for the basis)."""
    out = {"state": "unknown", "age_days": 0, "newer": 0, "checked": 0, "gone": 0, "suspects": [],
           "built": "", "checked_at": iso(now), "clock_future": False, "newest": {}}
    if manifest is None:
        out["state"] = "not_applicable"      # an absent or invalid manifest is E1 failing (spec 3.4, Rust clarification)
        return out
    out["built"] = str(manifest.get("built", ""))
    if not eligible(manifest, profiles, runtime_dir, pkgdb):
        out["state"] = "not_applicable"
        return out
    age, future = age_of(manifest, mtime, now)
    out["clock_future"] = future
    out["age_days"] = age            # None = unknown (counts as >= 30)
    if not repo_versions:
        return out
    members = members_of(manifest)
    out["checked"] = len(members)
    n_newer = gone = 0
    suspects = []
    newest = {}
    for name, ver in members:
        rv = repo_versions.get(name)
        if not rv:
            gone += 1
            continue
        newest[name] = rv
        if newer(rv, ver):
            n_newer += 1
            depth = USUAL_SUSPECTS.get(name)
            if depth and abi_move(ver, rv, depth):
                suspects.append(f"{name} {ver} -> {rv}")
    out.update(newer=n_newer, gone=gone, suspects=sorted(suspects), newest=newest)
    unknown_age = age is None
    if suspects:
        out["state"] = "due_now"
    elif n_newer > 0 and (unknown_age or (age >= MIN_AGE_DAYS and not future)):
        out["state"] = "due"
    else:
        out["state"] = "nominal"
    return out


# ----------------------------------------------------------------------------------------------------------------------
# state file (section 7)
# ----------------------------------------------------------------------------------------------------------------------
def state_path():
    t = _test_env("SLACKY_RR_STATE")
    if t:
        return t
    if os.geteuid() == 0:
        return "/var/lib/underpants/runtime_refresh.json"
    xdg = os.environ.get("XDG_STATE_HOME", "")
    base = xdg if xdg.startswith("/") else os.path.join(os.path.expanduser("~"), ".local", "state")
    return os.path.join(base, "underpants", "runtime_refresh.json")


STATE_DEFAULTS = {"schema": 1, "spec": SPEC, "runtime_built": "", "last_offered": "", "declined_at": "", "last_result": "none",
                  "last_result_at": "", "veto": {"candidate_basis": "", "apps_basis": "", "app": "", "rule": "", "detail": ""},
                  "snapshot": 0, "writer": ""}


def state_read(path=None, euid=None, owner_uid=None):
    """(state dict with defaults, ignored_reason). A bad file is treated as absent; reason "" = valid or missing."""
    p = path or state_path()
    raw, why = read_json_nofollow(p, STATE_MAX, owner_check=True, euid=euid, owner_uid=owner_uid)
    st = json.loads(json.dumps(STATE_DEFAULTS))
    if raw is None:
        return st, ("" if why == "missing" else why)
    if not isinstance(raw.get("spec"), str) or not raw["spec"].startswith("underpants-runtime-refresh/"):
        return st, "not a refresh state file"
    for k, v in raw.items():
        st[k] = v
    if not isinstance(st.get("veto"), dict):
        st["veto"] = dict(STATE_DEFAULTS["veto"])
    else:
        for k, v in STATE_DEFAULTS["veto"].items():
            st["veto"].setdefault(k, v)
    if st.get("last_result") not in RESULTS:
        st["last_result"] = "none"
    try:
        st["snapshot"] = int(st.get("snapshot", 0) or 0)
    except (TypeError, ValueError):
        st["snapshot"] = 0
    return st, ""


def state_effective(state, live_built):
    """A different live `built` (anyone rebuilt the runtime) resets declined_at, last_result and veto."""
    st = json.loads(json.dumps(state))
    if st.get("runtime_built") != live_built:
        st["runtime_built"] = live_built
        st["declined_at"] = ""
        st["last_result"] = "none"
        st["last_result_at"] = ""
        st["veto"] = dict(STATE_DEFAULTS["veto"])
        st["snapshot"] = 0
    return st


def suppression(state, cand_basis, app_basis, now):
    """'' | 'deferred' | 'remembered_veto' (section 7.3). `state` must already be effective."""
    d = parse_iso(state.get("declined_at"))
    if d is not None and 0 <= now - d < REASK_SECONDS:
        return "deferred"
    v = state.get("veto", {})
    if state.get("last_result") == "vetoed" and v.get("candidate_basis") and v.get("candidate_basis") == cand_basis \
            and v.get("apps_basis") == app_basis:
        return "remembered_veto"
    return ""


def state_write(state, path=None):
    """Atomic write: O_EXCL temp file in the same folder, fsync, rename. File 0644, folder 0755. Returns True on success."""
    p = path or state_path()
    d = os.path.dirname(p)
    try:
        os.makedirs(d, mode=0o755, exist_ok=True)
        if os.path.islink(d):
            return False
        tmp = os.path.join(d, f".{os.path.basename(p)}.{os.getpid()}.tmp")
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                json.dump(state, fh, indent=2, sort_keys=True)
                fh.write("\n")
                fh.flush()
                os.fsync(fh.fileno())
            os.replace(tmp, p)
        except BaseException:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise
        return True
    except OSError:
        return False


# ----------------------------------------------------------------------------------------------------------------------
# disk space (section 5.2, task 7K)
# ----------------------------------------------------------------------------------------------------------------------
def _unescape_mount(s):
    return re.sub(r"\\([0-7]{3})", lambda m: chr(int(m.group(1), 8)), s)


def parse_mountinfo(text):
    """[(mountpoint, 'major:minor')] from /proc/self/mountinfo text."""
    out = []
    for line in text.splitlines():
        f = line.split()
        if len(f) >= 5:
            out.append((_unescape_mount(f[4]), f[2]))
    return out


def mount_dev(path, entries):
    """major:minor of the mount that holds `path` (longest mountpoint prefix)."""
    best, dev = "", ""
    for mp, d in entries:
        if (path == mp or path.startswith(mp.rstrip("/") + "/") or mp == "/") and len(mp) >= len(best):
            best, dev = mp, d
    return dev


def same_filesystem(a, b, mountinfo_text):
    """True when both paths are held by mounts with the same major:minor. Btrfs subvolumes of one filesystem share it, while
    stat().st_dev differs per subvolume and must NOT be used (spec 5.2). A path without a mountinfo line: assume the same."""
    ents = parse_mountinfo(mountinfo_text)
    da, db = mount_dev(os.path.realpath(a), ents), mount_dev(os.path.realpath(b), ents)
    if not da or not db:
        return True
    return da == db


def _free(path):
    t = _test_env("SLACKY_RR_FREE")
    if t:
        try:
            table = json.loads(t)
            best = max((k for k in table if path == k or path.startswith(k.rstrip("/") + "/") or k == "/"), key=len, default=None)
            if best is not None:
                return int(table[best])
        except (ValueError, TypeError):
            pass
    probe = path
    while not os.path.exists(probe) and probe != "/":
        probe = os.path.dirname(probe)
    st = os.statvfs(probe)
    return st.f_bavail * st.f_frsize


def _ceil_mul(n, num, den):
    return -(-int(n) * num // den)


def gb_up(n):
    """Bytes -> GB (10^9) with one decimal, rounded UP, as text."""
    return f"{-(-int(n) // 100000000) / 10:.1f}"


def gb_down(n):
    """Bytes -> GB (10^9) with one decimal, rounded DOWN, as text."""
    return f"{int(n) // 100000000 / 10:.1f}"


def space_decide(installed, csize, missing, free_build, free_opt, same, build_dir="", opt_dir="/opt"):
    """Spec 5.2 with the exact number rules: integer factors rounded up, need_build = 2.2*S + C_missing, need_opt = 1.1*S + C.
    One filesystem: free = min of the two, need = need_build + 1.1*S, reported on /opt."""
    s22, s11 = _ceil_mul(installed, 22, 10), _ceil_mul(installed, 11, 10)
    need_build, need_opt = s22 + int(missing), s11 + int(csize)
    need_same = need_build + s11
    res = {"ok": True, "same_fs": bool(same), "same_filesystem": bool(same), "need_build": need_build, "need_opt": need_opt,
           "need_same": need_same, "need": 0, "free": 0, "path": opt_dir, "short": None}
    if same:
        free = min(free_build, free_opt)
        res.update(need=need_same, free=free, ok=free >= need_same, short=None if free >= need_same else "opt")
    elif free_build < need_build:
        res.update(ok=False, need=need_build, free=free_build, path=build_dir, short="build")
    elif free_opt < need_opt:
        res.update(ok=False, need=need_opt, free=free_opt, path=opt_dir, short="opt")
    else:
        res.update(need=need_build, free=free_build, path=build_dir)
    if not res["ok"]:
        res["need_gb"], res["free_gb"] = gb_up(res["need"]), gb_down(res["free"])
    return res


def space_plan(installed, csize, missing, build_dir, opt_dir="/opt", mountinfo_text=None):
    """space_decide() with the real free space and /proc/self/mountinfo."""
    if mountinfo_text is None:
        mi = _test_env("SLACKY_RR_MOUNTINFO") or "/proc/self/mountinfo"
        try:
            with open(mi, encoding="utf-8") as fh:
                mountinfo_text = fh.read()
        except OSError:
            mountinfo_text = ""
    same = same_filesystem(build_dir, opt_dir, mountinfo_text)
    return space_decide(installed, csize, missing, _free(build_dir), _free(opt_dir), same, build_dir, opt_dir)


# ----------------------------------------------------------------------------------------------------------------------
# running apps (section 5.5 step 4; owner decision D2: warn and continue)
# ----------------------------------------------------------------------------------------------------------------------
def _descendants(proc, root_pid):
    kids = {}
    try:
        names = [n for n in os.listdir(proc) if n.isdigit()]
    except OSError:
        return {root_pid}
    for n in names:
        try:
            with open(f"{proc}/{n}/stat", encoding="utf-8", errors="replace") as fh:
                data = fh.read()
            ppid = int(data[data.rindex(")") + 2:].split()[1])
        except (OSError, ValueError, IndexError):
            continue
        kids.setdefault(ppid, []).append(int(n))
    seen, stack = set(), [root_pid]
    while stack:
        p = stack.pop()
        if p in seen:
            continue
        seen.add(p)
        stack += kids.get(p, [])
    return seen


def running_apps(exclude_pid=None, proc=None):
    """[{'app','pid'}] for every process (except the updater's own tree) that maps a file below /opt/underpants/runtime/ or
    /opt/underpants/pkgs/. The app is the /opt/underpants/pkgs/<app> name, else the process name. Unreadable processes
    (other users) are not seen; this is a warning, not a gate."""
    proc = proc or _test_env("SLACKY_RR_PROC") or "/proc"
    skip = _descendants(proc, exclude_pid) if exclude_pid else set()
    skip.add(os.getpid())
    out = []
    try:
        pids = [int(n) for n in os.listdir(proc) if n.isdigit()]
    except OSError:
        return out
    for pid in sorted(pids):
        if pid in skip:
            continue
        try:
            with open(f"{proc}/{pid}/maps", encoding="utf-8", errors="replace") as fh:
                maps = fh.read()
        except OSError:
            continue
        hit = re.search(r"(/opt/underpants/pkgs/([^/\s]+)/|/opt/underpants/runtime/)", maps)
        if not hit:
            continue
        app = hit.group(2)
        if not app:
            m2 = re.search(r"/opt/underpants/pkgs/([^/\s]+)/", maps)
            app = m2.group(1) if m2 else ""
        if not app:
            try:
                with open(f"{proc}/{pid}/comm", encoding="utf-8", errors="replace") as fh:
                    app = fh.read().strip()
            except OSError:
                app = "an app"
        out.append({"app": app or "an app", "pid": pid})
    return out


# ----------------------------------------------------------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------------------------------------------------------
def _opt(args, name, default=None):
    if name in args:
        i = args.index(name)
        if i + 1 < len(args):
            return args[i + 1]
    return default


def cmd_state_record(args):
    event = args[0] if args else ""
    now = now_ts()
    st, _why = state_read()
    live, _mt, _r = read_manifest()
    built = str(live.get("built", "")) if live else ""
    st = state_effective(st, built)
    st["writer"] = _opt(args, "--writer", st.get("writer", ""))
    if event == "offered":
        st["last_offered"] = iso(now)
    elif event == "declined":
        st["declined_at"] = iso(now)
        st["last_result"] = "declined"
        st["last_result_at"] = iso(now)
    elif event == "result":
        res = _opt(args, "--result", "none")
        if res not in RESULTS:
            return 2
        st["last_result"] = res
        st["last_result_at"] = iso(now)
        try:
            st["snapshot"] = int(_opt(args, "--snapshot", st.get("snapshot", 0)) or 0)
        except ValueError:
            st["snapshot"] = 0
        if res == "installed":
            st["declined_at"] = ""
            st["veto"] = dict(STATE_DEFAULTS["veto"])
            st["runtime_built"] = _opt(args, "--built", built) or built
        elif res == "vetoed":
            st["veto"] = {"candidate_basis": _opt(args, "--candidate-basis", ""), "apps_basis": _opt(args, "--apps-basis", ""),
                          "app": _opt(args, "--app", ""), "rule": _opt(args, "--rule", ""),
                          "detail": _opt(args, "--detail", "")[:300]}
    else:
        return 2
    st["schema"], st["spec"] = 1, SPEC
    ok = state_write(st)
    print(json.dumps({"written": ok, "path": state_path()}))
    return 0 if ok else 1


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    cmd, args = argv[1], argv[2:]
    if cmd == "state-show":
        st, why = state_read()
        live, _mt, _r = read_manifest()
        st = state_effective(st, str(live.get("built", "")) if live else "")
        print(json.dumps({"state": st, "ignored": why}))
        return 0
    if cmd == "state-record":
        return cmd_state_record(args)
    if cmd == "space":
        try:
            res = space_plan(int(_opt(args, "--installed", 0)), int(_opt(args, "--csize", 0)), int(_opt(args, "--missing", 0)),
                             _opt(args, "--build-dir", "/tmp"), _opt(args, "--opt", "/opt"))
        except ValueError:
            return 2
        print(json.dumps(res))
        return 0 if res["ok"] else 1
    if cmd == "running-apps":
        ex = _opt(args, "--exclude-pid")
        print(json.dumps(running_apps(int(ex) if ex and ex.isdigit() else None)))
        return 0
    if cmd == "log" and len(args) >= 1:
        rr_log(args[0], " ".join(args[1:]))
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
