#!/usr/bin/env python3
"""Mirror and key sentinel for the package repositories (6A-201, 6A-202). Rust mirror: MS3 (signed lists), MS4/MS5/MS6
(Arch status, health, lag), MS7 (sentinel run, alerts), MS8 (keyring staging).

Standalone: no dependency on any other program. Behaviour follows the shared spec docs/mirror_key_spec.md (formats,
thresholds, sentences), written from the same specification as the other implementation of this tool.

What it does, quietly, as the normal user (never sudo, never a prompt, silent when nothing is wrong):
* WEEKLY: fetch the signed mirror-list packages (pacman-mirrorlist, cachyos-mirrorlist, -v3, -v4, chaotic-mirrorlist),
  verify them with the existing signature path (gnomes_trust.verify_package: gpgv against the key store), parse them
  strictly, refuse an older list than the last accepted one, and merge the servers into the candidate lists of
  slacky_mirrors.py. The built-in lists stay the floor. The unsigned Arch status JSON may only rank and retire mirrors
  that are already known, it never adds one. A probe round (at most 8 candidates per family, 1.5 s wall clock) feeds a
  per-mirror health history: 5 failures over 7 days and not listed upstream = retired (one re-probe after 30 days),
  more than 6 hours behind the freshest = demoted.
* ON EVERY UPDATE CHECK: key freshness (see the key functions at the end of this file).

Cache (own user cache only, 0700/0600, own uid, no links, size caps, atomic rename):
  ~/.cache/slacky-update/sentinel/{lists.json,health.json,state.json,arch_status.json,used_signers.json,keyring_stage/}
When the process is root nothing here reads or writes the user cache (root never trusts ~/.cache); root uses
/var/cache/slacky-update/sentinel (root:root 0700) instead. A user-writable
cache cannot raise trust: it only chooses which host is asked first; every byte from a host is still checked by its
caller (signature, checksum).
"""

import concurrent.futures
import gzip
import io
import json
import os
import re
import stat
import sys
import tarfile
import tempfile
import threading
import time
import urllib.error
import urllib.request
from typing import Any, Dict, List, Optional, Set, Tuple

sys.dont_write_bytecode = True

UA = "Slacky-Update-Mirror-Sentinel/1.0"
WEEK = 7 * 86400
DUE_AFTER = 597600                    # 6 days 22 hours, the same threshold as the weekly benchmark
FUTURE_SKEW = 2 * 86400
MAX_CACHE_BYTES = 1 << 20
MAX_LIST_PKG = 512 * 1024
MAX_SIG = 16 * 1024
MAX_INDEX = 4 * 1024 * 1024
MAX_ENTRIES = 1024                    # server lines read from one list (6A-212; Arch ships 424 today)
MAX_LIST_FILE = 128 * 1024            # the list file inside the package (shared spec section 1)
OFFERED_FAMILIES = ("arch",)         # 6A-211: every entry of the signed list is only 'offered' (shipped commented out)
MAX_PROBES = 8
PROBE_BUDGET = 1.5
CONFIRM_TIMEOUT = 4.0
LAG_DEMOTE_SECS = 6 * 3600
RETIRE_FAILS = 5
RETIRE_SPAN = 7 * 86400
REVIVE_AFTER = 30 * 86400
MIN_LIVE = 2
FAIL_WINDOW = 7 * 86400
FAIL_CAP = 32
ARCH_HINT_MAX_AGE = 14 * 86400
MAX_EXTRAS = 24
LIST_STALE_SECS = 30 * 86400
ALERT_REPEAT = 7 * 86400
KEY_EXPIRY_WARN = 60 * 86400
USED_EXPIRY_WARN = 30 * 86400          # 6A-279: a key that really signed packages

ARCH_STATUS_URL = "https://archlinux.org/mirrors/status/json/"

# family -> (label, probe path below the mirror prefix)
FAMILIES: Dict[str, Tuple[str, str]] = {
    "arch": ("Arch Linux", "/extra/os/x86_64/extra.db"),
    "cachyos": ("CachyOS", "/x86_64/cachyos/cachyos.db"),
    "chaotic": ("Chaotic-AUR", "/x86_64/chaotic-aur.db"),
}

# (family, package name, trust repo, member in the package, where the newest version is found)
LISTS: List[Tuple[str, str, str, str, str]] = [
    ("arch", "pacman-mirrorlist", "core", "etc/pacman.d/mirrorlist", "core/os/x86_64/"),
    ("cachyos", "cachyos-mirrorlist", "cachyos", "etc/pacman.d/cachyos-mirrorlist", "x86_64/cachyos/"),
    ("cachyos", "cachyos-v3-mirrorlist", "cachyos", "etc/pacman.d/cachyos-v3-mirrorlist", "x86_64/cachyos/"),
    ("cachyos", "cachyos-v4-mirrorlist", "cachyos", "etc/pacman.d/cachyos-v4-mirrorlist", "x86_64/cachyos/"),
    ("chaotic", "chaotic-mirrorlist", "chaotic", "etc/pacman.d/chaotic-mirrorlist",
     "https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst"),
]
# shape of a Server line per family: the group is the mirror prefix in the shape of slacky_mirrors.py
_SHAPES = {
    "arch": re.compile(r"^(.+)/\$repo/os/\$arch$"),
    "cachyos": re.compile(r"^(.+)/\$arch(?:_v3|_v4)?/\$repo$"),
    "chaotic": re.compile(r"^(.+)/\$repo/\$arch$"),
}
_SERVER_RE = re.compile(r"^(#?)\s*Server\s*=\s*(\S+)\s*$")
_HOST_OK = re.compile(r"^[A-Za-z0-9.-]+$")


# ---------------------------------------------------------------------------------------------------
# cache directory and safe file access
# ---------------------------------------------------------------------------------------------------

SYSTEM_SENTINEL_DIR = "/var/cache/slacky-update/sentinel"


def _is_root() -> bool:
    return os.geteuid() == 0


def sentinel_dir() -> Optional[str]:
    """The sentinel folder: the user's own cache for a normal user, the root-owned system cache for root (6A-278: the
    root cron check and `sudo slacky-update` refresh keys and lists too; root never uses a user cache, and every file it
    reads must be its own). The environment variable SLACKY_MIRROR_CACHE_DIR (tests) is honoured for a normal user only."""
    if _is_root():
        return SYSTEM_SENTINEL_DIR
    env = os.environ.get("SLACKY_MIRROR_CACHE_DIR")
    if env:
        return os.path.join(env, "sentinel")
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return os.path.join(base, "slacky-update", "sentinel")


def read_json(path: str) -> Dict[str, Any]:
    """Our own plain file only: a link, a file of someone else, an oversized or malformed file gives {}."""
    try:
        st = os.lstat(path)
        if not stat.S_ISREG(st.st_mode) or st.st_uid != os.geteuid() or st.st_size > MAX_CACHE_BYTES:
            return {}
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
        with os.fdopen(fd, "r", encoding="utf-8") as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def write_json(path: str, data: Any) -> bool:
    """Folder 0700, temp file 0600 created new without following links, atomic rename. Silent on failure."""
    d = os.path.dirname(path)
    try:
        os.makedirs(d, mode=0o700, exist_ok=True)
        st = os.lstat(d)
        if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.geteuid():
            return False
        if stat.S_IMODE(st.st_mode) != 0o700:
            os.chmod(d, 0o700)
        raw = json.dumps(data, indent=1, sort_keys=True).encode("utf-8")
        tmp = os.path.join(d, f".{os.path.basename(path)}.{os.getpid()}.tmp")
        try:
            os.unlink(tmp)
        except OSError:
            pass
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
        try:
            view = memoryview(raw)
            while view:
                view = view[os.write(fd, view):]
            os.fsync(fd)
        finally:
            os.close(fd)
        os.replace(tmp, path)
        return True
    except OSError:
        return False


_lock = threading.Lock()


def _trust() -> Any:
    """lib/gnomes_trust.py loaded by explicit path (PYTHONSAFEPATH keeps this folder off sys.path)."""
    global _TRUST
    if _TRUST is False:
        _TRUST = None
        try:
            import importlib.util
            path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gnomes_trust.py")
            spec = importlib.util.spec_from_file_location("gnomes_trust", path)
            if spec and spec.loader:
                mod = sys.modules.get("gnomes_trust") or importlib.util.module_from_spec(spec)
                if "gnomes_trust" not in sys.modules:
                    sys.modules["gnomes_trust"] = mod
                    spec.loader.exec_module(mod)
                _TRUST = mod
                _opt_in_ring_cache(mod)
        except Exception:
            _TRUST = None
    return _TRUST


_TRUST: Any = False


def _opt_in_ring_cache(mod: Any) -> None:
    """6A-213: keep the evaluated Arch ring between runs (about 1 s of gpg work). Only in the sentinel's own user cache; the
    sentinel's results are hints or are checked again from scratch by root, so this adds no trust."""
    try:
        d = sentinel_dir()
        if d and hasattr(mod, "RING_CACHE_DIR"):
            mod.RING_CACHE_DIR = os.path.join(d, "arch_ring")
    except Exception:
        pass


def tr(key: str, english: str) -> str:
    """Localised sentence (locales/<lang>.json) through the trust module's loader; English when unavailable."""
    t = _trust()
    try:
        if t is not None:
            return t.localized(key, english)
    except Exception:
        pass
    return english


def display(family: str) -> str:
    return FAMILIES.get(family, (family, ""))[0]


def record(level: str, ev: str, msg: str, data: Optional[Dict[str, Any]] = None, cat: str = "MIRROR") -> None:
    t = _trust()
    if t is not None:
        t.flight_record(cat, level, ev, msg, data)


# ---------------------------------------------------------------------------------------------------
# prefixes and the strict Server-line grammar
# ---------------------------------------------------------------------------------------------------

def clean_prefix(s: str) -> Optional[str]:
    """A mirror prefix a list or an upstream document may name: https://host[/path], no user info, port, query,
    fragment, IP literal, `..` segment or odd character; at most 300 characters. Without a trailing slash."""
    s = (s or "").strip().rstrip("/")
    if not s.startswith("https://") or len(s) > 300:
        return None
    rest = s[len("https://"):]
    if not rest:
        return None
    host, _, path = rest.partition("/")
    if not host or len(host) > 253 or "." not in host or not _HOST_OK.match(host) or host[0] in ".-":
        return None
    parts = host.split(".")
    if all(p.isdigit() and int(p) < 256 for p in parts) or ":" in host:
        return None
    if path and not re.fullmatch(r"[A-Za-z0-9._~/+-]+", path):
        return None
    if path and (any(seg in ("..", ".") for seg in path.split("/")) or "//" in rest):
        return None
    return s


def parse_mirrorlist(text: str, family: str) -> List[Tuple[str, bool]]:
    """Strict parse of a pacman mirror list: [(prefix, active)] where active = the line is not commented out upstream.
    Grammar: `^#?\\s*Server\\s*=\\s*https://<host>/<path>` with only $repo, $arch, $arch_v3, $arch_v4 as placeholders,
    the position of the placeholders fixed per family, no http, IP literals, user info or ports other than 443;
    at most 1024 server lines (more refuses the whole list); anything else is dropped. Duplicates are merged (active wins)."""
    shape = _SHAPES.get(family)
    if shape is None:
        return []
    found: Dict[str, bool] = {}
    n = 0
    for line in text.splitlines():
        m = _SERVER_RE.match(line.strip())
        if not m:
            continue
        n += 1
        if n > MAX_ENTRIES:
            raise ListRefusal("too many server lines")      # the whole list is refused (Rust: TooManyEntries)
        active = m.group(1) != "#"
        url = m.group(2)
        if not url.startswith("https://") or len(url) > 300:
            continue
        host_part = url[len("https://"):].split("/", 1)[0]
        if "@" in host_part:
            continue
        if ":" in host_part:
            host, _, port = host_part.rpartition(":")
            if port != "443" or ":" in host:
                continue
            url = "https://" + host + url[len("https://") + len(host_part):]
        sm = shape.match(url)
        if not sm:
            continue
        base = sm.group(1)
        if "$" in base:
            continue
        if family == "chaotic":
            base = base + "/chaotic-aur"
        prefix = clean_prefix(base)
        if prefix is None:
            continue
        found[prefix] = found.get(prefix, False) or active
    return list(found.items())


# ---------------------------------------------------------------------------------------------------
# health history (pure functions over a dict, an explicit `now`)
# ---------------------------------------------------------------------------------------------------

def new_health() -> Dict[str, Any]:
    return {"version": 1, "families": {}}


def _entry(h: Dict[str, Any], family: str, prefix: str, source: str, now: int) -> Dict[str, Any]:
    fam = h.setdefault("families", {}).setdefault(family, {})
    e = fam.get(prefix)
    if not isinstance(e, dict):
        e = {"source": source, "first_seen": now, "fails": [], "consecutive_fails": 0, "state": "active",
             "upstream": "unknown"}
        fam[prefix] = e
    return e


def get_entry(h: Dict[str, Any], family: str, prefix: str) -> Optional[Dict[str, Any]]:
    e = h.get("families", {}).get(family, {}).get(prefix)
    return e if isinstance(e, dict) else None


def state_of(h: Dict[str, Any], family: str, prefix: str) -> str:
    e = get_entry(h, family, prefix)
    s = e.get("state") if e else None
    return s if s in ("active", "demoted", "retired") else "active"


def _revive(e: Dict[str, Any]) -> None:
    e["state"] = "active"
    e["consecutive_fails"] = 0
    e["streak_start"] = None
    e["retired_ts"] = None
    e["fails"] = []


def register(h: Dict[str, Any], family: str, prefix: str, source: str, now: int) -> bool:
    """Add a mirror from a verified signed list. The Arch status source is refused: it may only annotate."""
    p = clean_prefix(prefix)
    if p is None:
        return False
    if get_entry(h, family, p) is not None:
        return True
    if source == "arch_status":
        return False
    if source == "signed_list":
        n = sum(1 for e in h.get("families", {}).get(family, {}).values()
                if isinstance(e, dict) and e.get("source") == "signed_list")
        if n >= MAX_EXTRAS:
            return False
    _entry(h, family, p, source, now)
    return True


def extras(h: Dict[str, Any], family: str) -> List[str]:
    """Mirrors added by a signed list, in the order they were first seen."""
    fam = h.get("families", {}).get(family, {})
    items = [(e.get("first_seen", 0), p) for p, e in fam.items() if isinstance(e, dict) and e.get("source") == "signed_list"]
    items.sort()
    return [p for _, p in items][:MAX_EXTRAS]


def apply_upstream(h: Dict[str, Any], family: str, prefix: str, up: str, now: int) -> List[Tuple[str, ...]]:
    ev: List[Tuple[str, ...]] = []
    e = _entry(h, family, prefix, "builtin", now)
    was = e.get("upstream")
    e["upstream"] = up
    if up == "active" and was != "active" and e.get("state") == "retired":
        _revive(e)
        ev.append(("revived", family, prefix))
    return ev


def vet_offered(d: str, listed: List[Tuple[str, bool]], known: List[str], now: int) -> List[Tuple[str, bool]]:
    """6A-211 (Rust lists.rs vet_offered): Arch ships every mirror commented out ("offered, choose one"), so the signed
    list is an allow-list. A listed server joins the family only when the (fresh) Arch status document vouches for it,
    best score first, or when it is a built-in host already. The unsigned status document alone never adds a mirror.
    Everything that passes is returned active."""
    doc = read_json(os.path.join(d, "arch_status.json"))
    scores: Dict[str, float] = {}
    try:
        usable = (int(doc.get("last_check", 0)) > 0 and int(doc.get("fetched_ts", 0)) <= now + 3600
                  and now - int(doc.get("fetched_ts", 0)) < ARCH_HINT_MAX_AGE)
    except (TypeError, ValueError):
        usable = False
    if usable and isinstance(doc.get("mirrors"), list):
        for m in doc["mirrors"]:
            if isinstance(m, dict) and isinstance(m.get("url"), str) and isinstance(m.get("score"), (int, float)):
                scores[m["url"].rstrip("/")] = float(m["score"])
    known_set = {k.rstrip("/") for k in known}
    vetted: List[Tuple[float, str]] = []
    builtin: List[str] = []
    for p, _a in listed:
        if p in scores:
            vetted.append((scores[p], p))
        elif p in known_set:
            builtin.append(p)
    vetted.sort(key=lambda x: x[0])
    out: List[Tuple[str, bool]] = [(p, True) for _, p in vetted]
    for p in builtin:
        if not any(x == p for x, _ in out):
            out.append((p, True))
    return out


def reapply_offered(d: str, h: Dict[str, Any], state: Dict[str, Any], now: int) -> List[Tuple[str, ...]]:
    """After the Arch status document changed: vet the stored list again (it is not downloaded again)."""
    ev: List[Tuple[str, ...]] = []
    for spec in LISTS:
        fam, pkgname = spec[0], spec[1]
        if fam not in OFFERED_FAMILIES:
            continue
        ent = state.get("lists", {}).get(pkgname, {})
        listed = [(str(p), bool(a)) for p, a in ent.get("listed", []) if isinstance(p, str)] if isinstance(ent.get("listed"), list) else []
        if not listed or int(ent.get("builddate", 0) or 0) <= 0:
            continue
        ev += apply_list(h, fam, vet_offered(d, listed, builtin_candidates(fam), now), now)
    return ev


def apply_list(h: Dict[str, Any], family: str, servers: List[Tuple[str, bool]], now: int) -> List[Tuple[str, ...]]:
    """A signed list's servers: new active servers join the family (up to 24), known ones get their upstream flag, a
    retired mirror that the list names active is revived."""
    ev: List[Tuple[str, ...]] = []
    for raw, active in servers:
        p = clean_prefix(raw)
        if p is None:
            continue
        if active:
            register(h, family, p, "signed_list", now)
        if get_entry(h, family, p) is not None:
            ev += apply_upstream(h, family, p, "active" if active else "inactive", now)
    return ev


def record_ok(h: Dict[str, Any], family: str, prefix: str, latency_ms: Optional[int], now: int) -> List[Tuple[str, ...]]:
    ev: List[Tuple[str, ...]] = []
    e = _entry(h, family, prefix, "builtin", now)
    e["last_ok"] = now
    e["consecutive_fails"] = 0
    e["streak_start"] = None
    if latency_ms is not None:
        old = e.get("ewma_latency_ms")
        e["ewma_latency_ms"] = latency_ms if old is None else (int(old) * 7 + latency_ms * 3) // 10
    if e.get("state") == "retired":
        _revive(e)
        ev.append(("revived", family, prefix))
    return ev


def record_fail(h: Dict[str, Any], family: str, prefix: str, now: int, total: int) -> List[Tuple[str, ...]]:
    """A download or probe failed. `total` = candidates in the family (retiring never leaves fewer than 2 in play)."""
    fam = h.get("families", {}).get(family, {})
    retired_others = sum(1 for p, x in fam.items() if p != prefix and isinstance(x, dict) and x.get("state") == "retired")
    e = _entry(h, family, prefix, "builtin", now)
    e["last_fail"] = now
    fails = [t for t in e.get("fails", []) if isinstance(t, int) and now - t < FAIL_WINDOW]
    fails.append(now)
    e["fails"] = fails[-FAIL_CAP:]
    e["consecutive_fails"] = int(e.get("consecutive_fails", 0)) + 1
    if not e.get("streak_start"):
        e["streak_start"] = now
    if e.get("state") == "retired":
        e["retired_ts"] = now           # a failed monthly re-probe: wait another month
        return []
    long_enough = now - int(e["streak_start"]) >= RETIRE_SPAN
    live_after = total - (retired_others + 1)
    if e["consecutive_fails"] >= RETIRE_FAILS and long_enough and e.get("upstream") != "active" and live_after >= MIN_LIVE:
        e["state"] = "retired"
        e["retired_ts"] = now
        return [("retired", family, prefix, str(e["consecutive_fails"]))]
    return []


def apply_lag(h: Dict[str, Any], family: str, results: List[Tuple[str, Optional[int], Optional[int]]], now: int) -> List[Tuple[str, ...]]:
    """results: (prefix, stamp, seconds behind the freshest of the round). More than 6 hours behind demotes an active
    mirror, back within 6 hours restores it; None lag leaves the state alone."""
    ev: List[Tuple[str, ...]] = []
    for prefix, stamp, lag in results:
        e = _entry(h, family, prefix, "builtin", now)
        if stamp is not None:
            e["last_stamp"] = stamp
        if lag is None:
            continue
        e["lag_secs"] = lag
        if lag > LAG_DEMOTE_SECS and e.get("state") == "active":
            e["state"] = "demoted"
            ev.append(("lagging", family, prefix, str(lag)))
        elif lag <= LAG_DEMOTE_SECS and e.get("state") == "demoted":
            e["state"] = "active"
            ev.append(("lag_cleared", family, prefix))
    return ev


def reprobe_due(h: Dict[str, Any], family: str, prefix: str, now: int) -> bool:
    e = get_entry(h, family, prefix)
    return bool(e and e.get("state") == "retired" and e.get("retired_ts") and now - int(e["retired_ts"]) >= REVIVE_AFTER)


_RANK = {"active": 0, "demoted": 1, "retired": 2}


def probe_set(h: Dict[str, Any], family: str, candidates: List[str], now: int) -> List[str]:
    """At most MAX_PROBES of `candidates` (the family's order, best known first), chosen by state (active first), then
    our own measured speed, then the Arch score. Retired ones are skipped unless their monthly re-probe is due. A mirror
    never measured is not starved by measured ones: when none is in the selection, the first unmeasured active candidate
    takes the last place."""
    items = []
    for idx, p in enumerate(candidates):
        e = get_entry(h, family, p)
        st = state_of(h, family, p)
        if st == "retired" and not reprobe_due(h, family, p, now):
            continue
        ms = e.get("ewma_latency_ms") if e else None
        sc = e.get("arch_score") if e else None
        items.append({"idx": idx, "p": p, "rank": 3 if st == "retired" else _RANK[st], "measured": ms is not None,
                      "ms": ms if ms is not None else 1 << 62, "score": float(sc) if isinstance(sc, (int, float)) else 1e300})
    items.sort(key=lambda i: (i["rank"], not i["measured"], i["ms"], i["score"], i["idx"]))
    chosen = items[:MAX_PROBES]
    if len(items) > MAX_PROBES and chosen and all(i["measured"] for i in chosen):
        fresh = next((i for i in items[MAX_PROBES:] if not i["measured"] and i["rank"] == 0), None)
        if fresh is not None:
            chosen[-1] = fresh
    chosen.sort(key=lambda i: i["idx"])
    return [i["p"] for i in chosen]


def sort_by_state(h: Dict[str, Any], family: str, order: List[str], keep_last: List[str]) -> List[str]:
    """Stable order by state: active, demoted; the slow last resorts behind every non-retired candidate; retired ones
    behind everything."""
    last = [p for p in order if p in keep_last]
    rest = [p for p in order if p not in keep_last]
    rest.sort(key=lambda p: _RANK[state_of(h, family, p)])
    retired = [p for p in rest if state_of(h, family, p) == "retired"]
    live = [p for p in rest if state_of(h, family, p) != "retired"]
    return live + last + retired


def live_count(h: Dict[str, Any], family: str, total: int) -> int:
    fam = h.get("families", {}).get(family, {})
    return total - sum(1 for e in fam.values() if isinstance(e, dict) and e.get("state") == "retired")


# ---------------------------------------------------------------------------------------------------
# health file access (user phase only)
# ---------------------------------------------------------------------------------------------------

def load_health(d: Optional[str] = None) -> Dict[str, Any]:
    d = d or sentinel_dir()
    if not d:
        return new_health()
    h = read_json(os.path.join(d, "health.json"))
    if not isinstance(h.get("families"), dict):
        return new_health()
    h["version"] = 1
    return h


def with_health(fn, d: Optional[str] = None) -> Any:
    """Load the health history, let `fn(h)` change it, save it, return what fn returned. A root process does nothing."""
    d = d or sentinel_dir()
    if not d:
        return None
    with _lock:
        h = load_health(d)
        r = fn(h)
        write_json(os.path.join(d, "health.json"), h)
        return r


def log_events(events: List[Tuple[str, ...]]) -> None:
    for e in events:
        kind, fam, pre = e[0], e[1], e[2]
        if kind == "retired":
            record("WARN", "mirror.retired", f"{fam}: {pre} retired after {e[3]} failures", {"family": fam, "url": pre, "fails": e[3]})
        elif kind == "revived":
            record("INFO", "mirror.revived", f"{fam}: {pre} is back", {"family": fam, "url": pre})
        elif kind == "lagging":
            record("WARN", "mirror.lagging", f"{fam}: {pre} is {e[3]} s behind", {"family": fam, "url": pre, "lag_secs": e[3]})
        elif kind == "lag_cleared":
            record("INFO", "mirror.lag_cleared", f"{fam}: {pre} caught up", {"family": fam, "url": pre})


# events noted by download code, flushed once (at exit, or at once for a failure) so 100 files are not 100 writes
_PENDING: List[Tuple[str, str, str, float]] = []
_ATEXIT = False


def note(family: str, prefix: str, ok: bool, total: int) -> None:
    """A real download from `prefix` worked or failed (called by slacky_mirrors). Buffered; failures flush at once."""
    global _ATEXIT
    if not sentinel_dir() or clean_prefix(prefix) is None:
        return
    with _lock:
        _PENDING.append((family, prefix, "ok" if ok else "fail", total))
        if not _ATEXIT:
            import atexit
            atexit.register(flush_notes)
            _ATEXIT = True
    if not ok:
        flush_notes()


def flush_notes() -> None:
    with _lock:
        todo = list(_PENDING)
        _PENDING.clear()
    if not todo or not sentinel_dir():
        return
    now = int(time.time())
    events: List[Tuple[str, ...]] = []

    def apply(h: Dict[str, Any]) -> None:
        for fam, pre, kind, total in todo:
            if kind == "ok":
                events.extend(record_ok(h, fam, pre, None, now))
            else:
                events.extend(record_fail(h, fam, pre, now, total))
    with_health(apply)
    log_events(events)


# ---------------------------------------------------------------------------------------------------
# small https client (capped, https only, at most 3 redirects, never to plain http)
# ---------------------------------------------------------------------------------------------------

_ALLOW_HTTP = False      # tests with a local server set this; production never does


class _Redirects(urllib.request.HTTPRedirectHandler):
    max_redirections = 3

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # type: ignore[override]
        if not (newurl.startswith("https://") or (_ALLOW_HTTP and newurl.startswith("http://"))):
            raise urllib.error.HTTPError(newurl, code, "redirect to a plain connection refused", headers, fp)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


_NET: Any = False


def _net() -> Any:
    """6A-244: slacky_net.py loaded by path (IPv4 retry); None when missing or broken."""
    global _NET
    if _NET is False:
        _NET = None
        try:
            import importlib.util
            path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "slacky_net.py")
            spec = importlib.util.spec_from_file_location("slacky_net", path)
            if spec and spec.loader:
                mod = sys.modules.get("slacky_net") or importlib.util.module_from_spec(spec)
                sys.modules["slacky_net"] = mod
                spec.loader.exec_module(mod)
                _NET = mod
        except Exception:
            _NET = None
    return _NET


def http_get(url: str, max_bytes: int, timeout: float, headers: Optional[Dict[str, str]] = None,
             method: str = "GET", truncate: bool = False) -> Tuple[int, bytes, Dict[str, str], str]:
    """(status, body, response headers lower-cased, final url). Raises OSError/URLError on a network problem and
    ValueError when the answer is bigger than max_bytes (unless `truncate`: then only the first max_bytes are read, for
    a server that ignores a Range request) or the url is not https."""
    if not (url.startswith("https://") or (_ALLOW_HTTP and url.startswith("http://"))):
        raise ValueError("not https")
    h = {"User-Agent": UA}
    h.update(headers or {})
    opener = urllib.request.build_opener(_Redirects())
    req = urllib.request.Request(url, headers=h, method=method)
    nm = _net()
    try:
        # 6A-244: one IPv4 retry when an IPv6 address is unreachable (slacky_net.py; plain opener when it is missing)
        with (nm.open_url(req, timeout=timeout, handlers=(_Redirects(),)) if nm is not None else opener.open(req, timeout=timeout)) as resp:
            body = resp.read(max_bytes + 1) if method != "HEAD" else b""
            if len(body) > max_bytes:
                if not truncate:
                    raise ValueError("answer too large")
                body = body[:max_bytes]
            hd = {k.lower(): v for k, v in resp.headers.items()}
            return resp.status, body, hd, resp.geturl()
    except urllib.error.HTTPError as e:
        if e.code == 304:
            return 304, b"", {k.lower(): v for k, v in e.headers.items()}, url
        raise


def _mm() -> Any:
    """slacky_mirrors.py loaded by path; None when missing."""
    global _MM
    if _MM is False:
        _MM = None
        try:
            import importlib.util
            path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "slacky_mirrors.py")
            spec = importlib.util.spec_from_file_location("slacky_mirrors", path)
            if spec and spec.loader:
                mod = sys.modules.get("slacky_mirrors") or importlib.util.module_from_spec(spec)
                if "slacky_mirrors" not in sys.modules:
                    sys.modules["slacky_mirrors"] = mod
                    spec.loader.exec_module(mod)
                _MM = mod
        except Exception:
            _MM = None
    return _MM


_MM: Any = False


def builtin_candidates(family: str) -> List[str]:
    """The built-in list of a family (the floor), as prefixes."""
    m = _mm()
    if m is None:
        return []
    cands, _last = m.builtin_lists()[family]
    return list(cands)


def builtin_last_resort(family: str) -> List[str]:
    m = _mm()
    return list(m.builtin_lists()[family][1]) if m is not None else []


# ---------------------------------------------------------------------------------------------------
# signed mirror lists (6A-201, Rust MS3)
# ---------------------------------------------------------------------------------------------------

_INDEX_RE = r'href="(%s-(\d[A-Za-z0-9._+]*-\d+)-(?:any|x86_64)\.pkg\.tar\.zst)"'


def newest_from_index(html: str, pkgname: str) -> Optional[str]:
    """File name of the newest `<pkgname>-<ver>-<rel>-<arch>.pkg.tar.zst` in a directory listing (pacman version order)."""
    t = _trust()
    best: Optional[Tuple[str, str]] = None
    for m in re.finditer(_INDEX_RE % re.escape(pkgname), html):
        fn, ver = m.group(1), m.group(2)
        if best is None or (t is not None and t.vercmp(ver, best[1]) > 0):
            best = (fn, ver)
    return best[0] if best else None


class ListRefusal(Exception):
    def __init__(self, reason: str):
        super().__init__(reason)
        self.reason = reason


def read_list_package(pkg: bytes, pkgname: str, member: str) -> Tuple[Dict[str, str], str]:
    """(PKGINFO fields, text of the list file) from a mirror-list package. Strict: the right name, one regular file
    of the list, no duplicates, nothing big."""
    t = _trust()
    if t is None:
        raise ListRefusal("trust module missing")
    with tempfile.TemporaryDirectory(prefix="slacky-list-") as tmp:
        os.chmod(tmp, 0o700)
        path = os.path.join(tmp, "list.pkg")
        with open(path, "wb") as f:
            f.write(pkg)
        try:
            if pkg[:4] == b"\x28\xb5\x2f\xfd":
                tf = tarfile.open(fileobj=io.BytesIO(t._unzstd_capped(path)), mode="r:")
            else:
                tf = tarfile.open(path, mode="r:*")
        except Exception as e:
            raise ListRefusal(f"not a readable archive: {e}")
        got: Dict[str, bytes] = {}
        try:
            with tf:
                for m in tf:
                    n = m.name
                    while n.startswith("./"):
                        n = n[2:]
                    if n not in (".PKGINFO", member):
                        continue
                    if not m.isreg() or m.size > MAX_LIST_FILE:
                        raise ListRefusal("a file in the package is not what a list looks like")
                    if n in got:
                        raise ListRefusal("a file appears twice")
                    src = tf.extractfile(m)
                    got[n] = src.read(MAX_LIST_FILE + 1) if src else b""
        except ListRefusal:
            raise
        except Exception as e:
            raise ListRefusal(f"corrupt archive: {e}")
    if len(got.get(member, b"")) > MAX_LIST_FILE:
        raise ListRefusal("a file in the package is not what a list looks like")
    if ".PKGINFO" not in got or member not in got:
        raise ListRefusal("the list or .PKGINFO is missing")
    fields: Dict[str, str] = {}
    for line in got[".PKGINFO"].decode("utf-8", "replace").splitlines():
        k, sep, v = line.partition("=")
        if sep and k.strip() and k.strip() not in fields:
            fields[k.strip()] = v.strip()
    if fields.get("pkgname") != pkgname:
        raise ListRefusal("the package is not the expected list")
    return fields, got[member].decode("utf-8", "replace")


def _load_state(d: str) -> Dict[str, Any]:
    st = read_json(os.path.join(d, "state.json"))
    st.setdefault("lists", {})
    st.setdefault("lists_ok", {})
    st.setdefault("alerts", {})
    st.setdefault("keys", {})
    st.setdefault("first_run", 0)
    st.setdefault("last_run", 0)
    return st


def _save_state(d: str, st: Dict[str, Any]) -> None:
    write_json(os.path.join(d, "state.json"), st)


def fetch_signed_list(spec: Tuple[str, str, str, str, str], now: int, state: Dict[str, Any],
                      bases: Optional[List[str]] = None, timeout: float = 4.0, keys_root: Optional[str] = None,
                      shipped_dir: Optional[str] = None) -> Optional[List[Tuple[str, bool]]]:
    """Fetch, verify and parse one signed list. Returns [(prefix, active)] or None (a refusal is recorded in the
    flight recorder; the built-in list stays in force). Updates state["lists"][pkgname] with the build date."""
    family, pkgname, repo, member, where = spec
    t = _trust()
    if t is None:
        return None
    mm = _mm()

    def refuse(reason: str) -> None:
        record("WARN", "mirror.list.rejected", f"{pkgname}: {reason}", {"family": family, "pkg": pkgname, "reason": reason})

    # 1. where is the newest version and where does it come from
    if where.startswith("https://") or (_ALLOW_HTTP and where.startswith("http")):
        candidates_pkg = [where]
    else:
        index_urls = []
        for b in (bases if bases is not None else builtin_candidates(family)):
            index_urls.append(b.rstrip("/") + "/" + where)
        if bases is None and mm is not None and index_urls:
            index_urls = [u for u in mm.alternatives(index_urls[0])] or index_urls[:1]
        candidates_pkg = []
        fn = None
        for iu in index_urls[:4]:
            try:
                st_, body, _h, _u = http_get(iu, MAX_INDEX, timeout)
                fn = newest_from_index(body.decode("utf-8", "replace"), pkgname)
                if fn:
                    candidates_pkg = [iu.rstrip("/") + "/" + fn]
                    break
            except (OSError, ValueError):
                continue
        if not candidates_pkg:
            refuse("no mirror could list the package")
            return None
    pkg = sig = None
    used = ""
    for u in candidates_pkg:
        try:
            st_, body, _h, _fu = http_get(u, MAX_LIST_PKG, timeout)
            if st_ != 200 or not body:
                continue
            st2, sg, _h2, _fu2 = http_get(u + ".sig", MAX_SIG, timeout)
            if st2 != 200 or not sg:
                continue
            pkg, sig, used = body, sg, u
            break
        except (OSError, ValueError):
            continue
    if pkg is None or sig is None:
        refuse("the package or its signature could not be downloaded")
        return None

    # 2. signature through the existing verifier (the key store, then the shipped keys)
    with tempfile.TemporaryDirectory(prefix="slacky-list-") as tmp:
        os.chmod(tmp, 0o700)
        pp = os.path.join(tmp, "list.pkg")
        with open(pp, "wb") as f:
            f.write(pkg)
        kw: Dict[str, Any] = {}
        if keys_root is not None:
            kw["keys_root"] = keys_root
        if shipped_dir is not None:
            kw["shipped_dir"] = shipped_dir
        res = t.verify_package(pp, sig, repo, name=pkgname, **kw)
    if not res.ok:
        refuse(f"signature check: {res.status} {res.detail}")
        return None

    # 3. strict content, monotonic build date
    try:
        fields, text = read_list_package(pkg, pkgname, member)
        bd = int(fields.get("builddate", ""))
    except (ListRefusal, ValueError) as e:
        refuse(str(e) or "no build date")
        return None
    if bd <= 0 or bd > now + FUTURE_SKEW:
        refuse("the list claims a build date in the future")
        return None
    last = state.get("lists", {}).get(pkgname, {})
    if bd < int(last.get("builddate", 0) or 0):
        refuse("older than the last accepted list")
        return None
    try:
        servers = parse_mirrorlist(text, family)
    except ListRefusal as e:
        refuse(e.reason)
        return None
    state.setdefault("lists", {})[pkgname] = {"builddate": bd, "pkgver": fields.get("pkgver", ""),
                                              "signer": res.key_fpr, "fetched_ts": now, "servers": len(servers)}
    if family in OFFERED_FAMILIES:
        state["lists"][pkgname]["listed"] = [[p, a] for p, a in servers]      # for a later re-vet, no new download
    record("INFO", "mirror.list.ok", f"{pkgname} {fields.get('pkgver', '')}: {len(servers)} servers",
           {"family": family, "pkg": pkgname, "pkgver": fields.get("pkgver", ""), "signer": res.key_fpr,
            "servers": len(servers)})
    return servers


# ---------------------------------------------------------------------------------------------------
# Arch mirror status JSON (rank and retire only, Rust MS4)
# ---------------------------------------------------------------------------------------------------

def _host_of(url: str) -> str:
    rest = url.split("://", 1)[-1]
    return rest.split("/", 1)[0].lower()


def parse_arch_status(raw: bytes, known: List[str]) -> Dict[str, Any]:
    """Parse and filter the document. Raises ValueError("reason"). Filter: https, active, completion 100 %, delay known
    and under an hour, score known; best score first, top 50. `known` = prefixes we already have (their upstream state
    is noted, nothing is ever added)."""
    try:
        v = json.loads(raw.decode("utf-8"))
    except ValueError:
        raise ValueError("malformed")
    if not isinstance(v, dict) or v.get("version") != 3:
        raise ValueError("unknown version")
    try:
        import datetime as _dt
        last_check = int(_dt.datetime.fromisoformat(str(v["last_check"]).replace("Z", "+00:00")).timestamp())
    except (KeyError, ValueError):
        raise ValueError("malformed")
    urls = v.get("urls")
    if not isinstance(urls, list) or len(urls) < 10 or len(urls) > 5000:
        raise ValueError("malformed")
    mirrors: List[Dict[str, Any]] = []
    seen: Dict[str, bool] = {}
    hosts: Dict[str, bool] = {}
    for u in urls:
        if not isinstance(u, dict) or not isinstance(u.get("url"), str):
            continue
        key = u["url"].strip().rstrip("/")
        active = u.get("active") is True
        if active or key not in seen:
            seen[key] = active
        h = _host_of(key)
        hosts[h] = hosts.get(h, False) or active
        comp, delay, score = u.get("completion_pct"), u.get("delay"), u.get("score")
        ok = (u.get("protocol") == "https" and active and isinstance(comp, (int, float)) and comp >= 0.9999
              and isinstance(delay, (int, float)) and 0 <= delay < 3600
              and isinstance(score, (int, float)) and score >= 0 and score == score and score != float("inf"))
        if not ok:
            continue
        p = clean_prefix(u["url"])
        if p is None or any(m["url"] == p for m in mirrors):
            continue
        mirrors.append({"url": p, "score": float(score), "delay": int(delay)})
    if not mirrors:
        raise ValueError("malformed")
    mirrors.sort(key=lambda m: (m["score"], m["url"]))
    mirrors = mirrors[:50]
    watched: Dict[str, str] = {}
    for k in known:
        k = k.rstrip("/")
        act = seen.get(k, False) or hosts.get(_host_of(k), False)
        watched[k] = "active" if act else "inactive"
    return {"version": 3, "last_check": last_check, "mirrors": mirrors, "watched": watched}


def check_monotonic_status(stored: Optional[int], new: int, now: int) -> int:
    """The monotonic rule for `last_check`; returns the new high-water mark or raises ValueError."""
    if new > now + 3600:
        raise ValueError("from the future")
    if now - new > 48 * 3600:
        raise ValueError("too old")
    if stored and stored > 0 and new + 600 < stored:
        raise ValueError("older than the last one")
    return max(stored or 0, new)


def refresh_arch_status(d: str, known: List[str], now: int, url: str = ARCH_STATUS_URL, timeout: float = 4.0) -> str:
    """Fetch the document (ETag, gzip), store it in arch_status.json. Returns 'updated', 'not_modified' or a reason."""
    path = os.path.join(d, "arch_status.json")
    stored = read_json(path)
    hdr = {"Accept-Encoding": "gzip"}
    etag = stored.get("etag")
    if isinstance(etag, str) and etag and len(etag) <= 200 and stored.get("last_check", 0) > 0 \
            and all(0x20 <= ord(c) < 0x7f for c in etag):
        hdr["If-None-Match"] = etag
    try:
        status, body, hd, _u = http_get(url, 1 << 20, timeout, hdr)
    except urllib.error.HTTPError as e:
        return f"http {e.code}"
    except (OSError, ValueError) as e:
        return f"network: {e}"
    if status == 304:
        if stored.get("last_check", 0) > 0:
            stored["fetched_ts"] = now
            write_json(path, stored)
            return "not_modified"
        return "http 304"
    if status != 200:
        return f"http {status}"
    enc = hd.get("content-encoding", "").strip().lower()
    try:
        if body[:2] == b"\x1f\x8b" or enc in ("gzip", "x-gzip"):
            with gzip.GzipFile(fileobj=io.BytesIO(body)) as gz:
                body = gz.read((4 << 20) + 1)
            if len(body) > (4 << 20):
                return "too large"
        elif enc not in ("", "identity"):
            return "bad encoding"
        parsed = parse_arch_status(body, known)
        high = check_monotonic_status(int(stored.get("last_check", 0) or 0) or None, parsed["last_check"], now)
    except (ValueError, OSError, EOFError) as e:
        return str(e) or "malformed"
    et = hd.get("etag")
    doc = {"version": 3, "etag": et if isinstance(et, str) and 0 < len(et) <= 200 and all(0x20 <= ord(c) < 0x7f for c in et) else None,
           "last_check": high, "fetched_ts": now, "mirrors": parsed["mirrors"], "watched": parsed["watched"]}
    write_json(path, doc)
    return "updated"


def apply_arch(h: Dict[str, Any], family: str, known: List[str], doc: Dict[str, Any], now: int) -> List[Tuple[str, ...]]:
    """The Arch JSON as a hint for mirrors that are already known: the score, and 'active upstream' or not. Mirrors
    only in the JSON are ignored. A stale document is ignored."""
    if not (doc.get("last_check", 0) > 0 and doc.get("fetched_ts", 0) <= now + 3600
            and now - int(doc.get("fetched_ts", 0)) < ARCH_HINT_MAX_AGE):
        return []
    ev: List[Tuple[str, ...]] = []
    mirrors = doc.get("mirrors", []) if isinstance(doc.get("mirrors"), list) else []
    watched = doc.get("watched", {}) if isinstance(doc.get("watched"), dict) else {}
    for k in known:
        key = k.rstrip("/")
        score = next((m.get("score") for m in mirrors if isinstance(m, dict) and str(m.get("url", "")).rstrip("/") == key), None)
        up = watched.get(key)
        if up not in ("active", "inactive"):
            if score is None:
                continue
            up = "active"
        e = _entry(h, family, key, "builtin", now)
        e["arch_score"] = score
        ev += apply_upstream(h, family, key, up, now)
    return ev


# ---------------------------------------------------------------------------------------------------
# probes and lag (Rust MS5/MS6): at most 8 per family, 1.5 s wall clock for the whole round
# ---------------------------------------------------------------------------------------------------

def _looks_like_db(b: bytes) -> bool:
    return b.startswith(b"\x28\xb5\x2f\xfd") or b.startswith(b"\x1f\x8b")


def _probe_one(family: str, prefix: str, timeout: float) -> Dict[str, Any]:
    """One mirror: does it serve a repository database (first 256 bytes)? And its freshness stamp."""
    out: Dict[str, Any] = {"prefix": prefix, "ok": False, "ms": None, "stamp": None, "final_host": None, "len": None}
    rel = FAMILIES[family][1]
    t0 = time.time()
    try:
        st, body, hd, fu = http_get(prefix + rel, 256, timeout, {"Range": "bytes=0-255"}, truncate=True)
        if st in (200, 206) and _looks_like_db(body[:4]):
            out["ok"] = True
            out["ms"] = int((time.time() - t0) * 1000)
            out["final_host"] = _host_of(fu)
            m = re.search(r"/(\d+)$", hd.get("content-range", ""))
            out["len"] = int(m.group(1)) if m else None
            out["mtime"] = _http_date(hd.get("last-modified", ""))
    except (OSError, ValueError) as e:
        out["timeout"] = _is_timeout(e)
        return out
    if out["ok"]:
        if family in ("arch", "chaotic"):
            try:
                st, body, _h, _u = http_get(prefix + "/lastupdate", 64, max(0.3, timeout - (time.time() - t0)))
                txt = body.decode("ascii", "ignore").strip()
                if st == 200 and txt.isdigit() and len(txt) <= 12 and int(txt) >= 1_100_000_000:
                    out["stamp"] = int(txt)
            except (OSError, ValueError):
                pass
        else:
            out["stamp"] = out.get("mtime")
    return out


def _is_timeout(e: BaseException) -> bool:
    import socket
    if isinstance(e, (socket.timeout, TimeoutError)):
        return True
    return isinstance(e, urllib.error.URLError) and isinstance(getattr(e, "reason", None), (socket.timeout, TimeoutError))


def _http_date(s: str) -> Optional[int]:
    try:
        import email.utils
        dt = email.utils.parsedate_to_datetime(s.strip())
        v = int(dt.timestamp())
        return v if v >= 1_100_000_000 else None
    except (TypeError, ValueError, IndexError):
        return None


def compute_lag(samples: List[Dict[str, Any]], now: int) -> List[Tuple[str, Optional[int], Optional[int]]]:
    """(prefix, stamp, lag) against the freshest valid stamp of the round. A stamp more than an hour in our future is
    ignored. CachyOS databases of the same size count as identical (mtimes drift by minutes between mirrors)."""
    def valid(t: Optional[int]) -> bool:
        return t is not None and 1_100_000_000 <= t <= now + 3600
    best = max((s for s in samples if valid(s.get("stamp"))), key=lambda s: s["stamp"], default=None)
    out = []
    for s in samples:
        t = s.get("stamp") if valid(s.get("stamp")) else None
        lag = None
        if best is not None and t is not None:
            if s.get("len") is not None and s.get("len") == best.get("len") and s.get("kind") == "db":
                lag = 0
            else:
                lag = max(0, best["stamp"] - t)
        out.append((s["prefix"], t, lag))
    return out


def probe_round(sets: Dict[str, List[str]], budget: float = PROBE_BUDGET) -> Dict[str, List[Dict[str, Any]]]:
    """Probe the given prefixes of every family in parallel within `budget` seconds of wall clock. What did not finish
    is not counted either way."""
    results: Dict[str, List[Dict[str, Any]]] = {f: [] for f in sets}
    jobs = [(f, p) for f, ps in sets.items() for p in ps]
    if not jobs:
        return results
    ex = concurrent.futures.ThreadPoolExecutor(max_workers=min(32, len(jobs)))
    futs = {ex.submit(_probe_one, f, p, budget): (f, p) for f, p in jobs}
    try:
        for fut in concurrent.futures.as_completed(futs, timeout=budget + 0.3):
            f, _p = futs[fut]
            try:
                r = fut.result()
                r["kind"] = "db" if f == "cachyos" else "unix"
                results[f].append(r)
            except Exception:
                pass
    except concurrent.futures.TimeoutError:
        pass
    ex.shutdown(wait=False, cancel_futures=True)
    return results


# ---------------------------------------------------------------------------------------------------
# the weekly run
# ---------------------------------------------------------------------------------------------------

def due(now: Optional[float] = None) -> bool:
    d = sentinel_dir()
    if not d:
        return False
    st = read_json(os.path.join(d, "state.json"))
    last = float(st.get("last_run", 0) or 0)
    now = time.time() if now is None else now
    return last > now + 3600 or now - last >= DUE_AFTER


def family_candidates(h: Dict[str, Any], family: str) -> List[str]:
    """Built-in list (floor) then the signed-list servers, de-duplicated; the slow last resorts are not probed."""
    out: List[str] = []
    for p in builtin_candidates(family) + extras(h, family):
        if p not in out:
            out.append(p)
    return out


def weekly_run(now: Optional[int] = None, force: bool = False, lists: bool = True, status: bool = True,
               probe: bool = True, bases: Optional[Dict[str, List[str]]] = None, keys_root: Optional[str] = None,
               shipped_dir: Optional[str] = None, arch_status_url: str = ARCH_STATUS_URL) -> Dict[str, Any]:
    """Signed lists, Arch status hints, one probe round with lag. Silent; returns a small summary for tests and `status`.
    Does nothing when the weekly schedule says it is not due (unless force). Root writes the system sentinel folder."""
    d = sentinel_dir()
    summary: Dict[str, Any] = {"ran": False}
    if not d:
        return summary
    now = int(time.time()) if now is None else int(now)
    if not force and not due(now):
        return summary
    with _lock:
        state = _load_state(d)
    if not state.get("first_run"):
        state["first_run"] = now
    summary["ran"] = True
    events: List[Tuple[str, ...]] = []
    got_lists: Dict[str, Dict[str, bool]] = {}

    # 1. signed lists
    if lists:
        for spec in LISTS:
            fam = spec[0]
            try:
                servers = fetch_signed_list(spec, now, state, (bases or {}).get(fam), keys_root=keys_root,
                                            shipped_dir=shipped_dir)
            except Exception as e:      # the sentinel must never break the check
                record("WARN", "mirror.list.rejected", f"{spec[1]}: {type(e).__name__}", {"family": fam})
                servers = None
            if servers is not None and fam in OFFERED_FAMILIES:
                servers = vet_offered(d, servers, builtin_candidates(fam), now)
            if servers is not None:
                u = got_lists.setdefault(fam, {})
                for p, a in servers:
                    u[p] = u.get(p, False) or a
                state["lists_ok"][fam] = now
        summary["lists"] = {f: len(v) for f, v in got_lists.items()}

    def apply(h: Dict[str, Any]) -> None:
        for fam, srv in got_lists.items():
            events.extend(apply_list(h, fam, list(srv.items()), now))
    with_health(apply)

    # 2. Arch status JSON: rank and retire only
    if status:
        h0 = load_health(d)
        known = family_candidates(h0, "arch")
        res = refresh_arch_status(d, known, now, arch_status_url)
        summary["arch_status"] = res
        if res in ("updated", "not_modified"):
            record("INFO", "mirror.status.ok", f"arch status {res}", {"result": res})
            doc = read_json(os.path.join(d, "arch_status.json"))
            with_health(lambda h: events.extend(apply_arch(h, "arch", known, doc, now)))
            with_health(lambda h: events.extend(reapply_offered(d, h, state, now)))
        else:
            record("WARN", "mirror.status.rejected", f"arch status: {res}", {"reason": res})

    # 3. one probe round (at most 8 per family, 1.5 s wall clock), then lag
    if probe:
        h1 = load_health(d)
        sets = {f: probe_set(h1, f, family_candidates(h1, f), now) for f in FAMILIES}
        rnd = probe_round(sets)
        any_ok = any(r["ok"] for rs in rnd.values() for r in rs)
        live: Dict[str, int] = {}

        def apply_probe(h: Dict[str, Any]) -> None:
            for fam, rs in rnd.items():
                total = len(family_candidates(h, fam))
                for r in rs:
                    if r["ok"]:
                        events.extend(record_ok(h, fam, r["prefix"], r["ms"], now))
                    elif not r.get("timeout"):      # too slow for the budget is neither a failure nor a success
                        events.extend(record_fail(h, fam, r["prefix"], now, total))
                events.extend(apply_lag(h, fam, compute_lag([r for r in rs if r["ok"]], now), now))
                for r in rs:
                    if r["ok"] and r.get("final_host"):
                        e = get_entry(h, fam, r["prefix"])
                        if e is not None:
                            e["final_host"] = r["final_host"]
        with_health(apply_probe)
        # a family with fewer than 2 answering mirrors gets one slower confirming round before anyone is alarmed
        low = [f for f, rs in rnd.items() if any_ok and sets.get(f) and sum(1 for r in rs if r["ok"]) < MIN_LIVE]
        for f in low:
            hh = load_health(d)
            conf = probe_round({f: probe_set(hh, f, family_candidates(hh, f), now)}, CONFIRM_TIMEOUT)[f]
            live[f] = sum(1 for r in conf if r["ok"])

            def apply_conf(h: Dict[str, Any], f: str = f, conf: List[Dict[str, Any]] = conf) -> None:
                for r in conf:       # failures were counted by the first round; here only a late answer counts
                    if r["ok"]:
                        events.extend(record_ok(h, f, r["prefix"], r["ms"], now))
            with_health(apply_conf)
        for f, rs in rnd.items():
            if f not in live:
                live[f] = sum(1 for r in rs if r["ok"])
        state["live"] = live if any_ok else state.get("live", {})
        state["live_ts"] = now if any_ok else state.get("live_ts", 0)
        summary["live"] = live
        summary["online"] = any_ok
    log_events(events)
    state["last_run"] = now
    _save_state(d, state)
    return summary


# ---------------------------------------------------------------------------------------------------
# key freshness, staging, expiry radar (6A-202, Rust mirror: MS7 / MS8)
# ---------------------------------------------------------------------------------------------------
# Runs on EVERY update check, read-only against the key store and piggybacking on the repository databases that the
# check already synced: a keyring package is downloaded only when a NEWER one is listed than the generation in force.
# A package that passes every rule (gnomes_trust.verify_keyring_package) is staged in the user's cache; it is installed
# only as the FIRST root step of an explicit full update (gnomes_trust.install_staged re-verifies the raw bytes). Never
# sudo, never a prompt here.

# family -> (database name, package name, default package folder, undated alias url or "")
KEYRINGS: Dict[str, Tuple[str, str, str, str]] = {
    "archlinux": ("core", "archlinux-keyring", "https://geo.mirror.pkgbuild.com/core/os/x86_64", ""),
    "cachyos": ("cachyos", "cachyos-keyring", "https://mirror.cachyos.org/repo/x86_64/cachyos", ""),
    "chaotic": ("", "chaotic-keyring", "", "https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst"),
}
USED_KEEP = 90 * 86400
MAX_DB_BYTES = 64 * 1024 * 1024
KEY_PKG_MAX = 24 * 1024 * 1024


def gnomes_db_dirs() -> List[str]:
    """Where the gnomes engine caches its synced databases: the system cache (root-written), then the user's."""
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return ["/var/cache/slacky-update/gnomes/db", os.path.join(base, "slacky-update", "gnomes", "db")]


def _find_db(db_dirs: List[str], repo: str) -> Optional[str]:
    best: Optional[Tuple[float, str]] = None
    for d in db_dirs:
        for ext in (".db.tar.zst", ".db.tar.gz"):
            p = os.path.join(d, repo + ext)
            try:
                st = os.lstat(p)
            except OSError:
                continue
            if not stat.S_ISREG(st.st_mode) or st.st_size > MAX_DB_BYTES or st.st_uid not in (0, os.geteuid()):
                continue
            if best is None or st.st_mtime > best[0]:
                best = (st.st_mtime, p)
    return best[1] if best else None


def listed_keyring(family: str, db_dirs: Optional[List[str]] = None, cache: Optional[Dict[str, Any]] = None
                   ) -> Optional[Tuple[Tuple[int, int], str]]:
    """((version, release), file name) of the keyring package the synced repository database lists, or None (no
    database, or not listed there). Read only; a result is cached by file identity in `cache`."""
    repo, pkgname, _folder, _alias = KEYRINGS[family]
    t = _trust()
    if not repo or t is None:
        return None
    path = _find_db(db_dirs if db_dirs is not None else gnomes_db_dirs(), repo)
    if not path:
        return None
    st = os.stat(path)
    ident = f"{path}|{int(st.st_mtime)}|{st.st_size}"
    if cache is not None and cache.get("ident") == ident and "res" in cache:
        r = cache["res"]
        return (tuple(r[0]), r[1]) if r else None   # type: ignore[return-value]
    res: Optional[Tuple[Tuple[int, int], str]] = None
    try:
        if path.endswith(".zst"):
            tf = tarfile.open(fileobj=io.BytesIO(t._unzstd_capped(path)), mode="r:")
        else:
            tf = tarfile.open(path, mode="r:*")
        with tf:
            for m in tf:
                if not m.name.endswith("/desc") or not m.name.startswith(pkgname + "-") or not m.isreg() or m.size > 65536:
                    continue
                dirn = m.name[: -len("/desc")]
                ver = dirn[len(pkgname) + 1:]
                key = t._parse_pkgver(ver)
                if key is None:
                    continue
                src = tf.extractfile(m)
                desc = src.read(65537).decode("utf-8", "replace") if src else ""
                fields = {}
                cur = ""
                for line in desc.splitlines():
                    if line.startswith("%") and line.endswith("%"):
                        cur = line.strip("%")
                        fields[cur] = []
                    elif cur and line.strip():
                        fields[cur].append(line.strip())
                if fields.get("NAME", [""])[0] != pkgname:
                    continue
                fn = (fields.get("FILENAME") or [""])[0]
                if not re.fullmatch(re.escape(pkgname) + r"-[0-9]+-[0-9]+-(?:any|x86_64)\.pkg\.tar\.zst", fn):
                    continue
                if res is None or key > res[0]:
                    res = (key, fn)
    except Exception:
        res = None
    if cache is not None:
        cache["ident"] = ident
        cache["res"] = [list(res[0]), res[1]] if res else None
    return res


def _stage_dir(d: str) -> str:
    return os.path.join(d, "keyring_stage")


def staged_key(d: str, family: str) -> Optional[Tuple[int, int]]:
    """(version, release) of what is staged for `family`, from its verdict (a hint; the root phase checks again)."""
    t = _trust()
    v = read_json(os.path.join(_stage_dir(d), family, "verdict.json"))
    return t._parse_pkgver(str(v.get("pkgver", ""))) if (t is not None and v) else None


def prune_stage(d: str, keys_root: Optional[str]) -> None:
    """Remove staged keyrings that the key store has caught up with (the full update installed them)."""
    t = _trust()
    if t is None:
        return
    for fam in KEYRINGS:
        sk = staged_key(d, fam)
        if sk is None:
            continue
        gen, _why = t.locate_generation(fam, keys_root or t.KEYS_ROOT)
        gk = gen.pkgver_key() if gen is not None else None
        if gk is not None and gk >= sk:
            fd = os.path.join(_stage_dir(d), fam)
            for fn in ("pkg", "sig", "verdict.json"):
                try:
                    os.unlink(os.path.join(fd, fn))
                except OSError:
                    pass
            try:
                os.rmdir(fd)
            except OSError:
                pass


def download_keyring(family: str, filename: str, timeout: float = 8.0) -> Optional[Tuple[bytes, bytes]]:
    """(package, signature) of a listed keyring package, from the ranked mirrors of its family; None when no mirror
    delivered both. Only bytes: nothing here trusts them."""
    _repo, pkgname, folder, _alias = KEYRINGS[family]
    url = folder.rstrip("/") + "/" + filename
    mm = _mm()
    urls = mm.alternatives(url) if mm is not None else [url]
    for u in urls[:4]:
        try:
            st, pkg, _h, _u = http_get(u, KEY_PKG_MAX, timeout)
            if st != 200 or not pkg:
                continue
            st2, sg, _h2, _u2 = http_get(u + ".sig", MAX_SIG, timeout)
            if st2 == 200 and sg:
                return pkg, sg
        except (OSError, ValueError):
            continue
    return None


def download_alias(family: str, last_modified: str, timeout: float = 6.0) -> Tuple[str, Optional[Tuple[bytes, bytes]], str]:
    """The undated Chaotic alias with If-Modified-Since: ('not_modified'|'ok'|'failed', (pkg, sig), Last-Modified)."""
    alias = KEYRINGS[family][3]
    hdr = {"If-Modified-Since": last_modified} if last_modified else {}
    try:
        st, pkg, hd, _u = http_get(alias, KEY_PKG_MAX, timeout, hdr)
        if st == 304:
            return "not_modified", None, last_modified
        if st != 200 or not pkg:
            return "failed", None, ""
        st2, sg, _h2, _u2 = http_get(alias + ".sig", MAX_SIG, timeout)
        if st2 != 200 or not sg:
            return "failed", None, ""
        return "ok", (pkg, sg), hd.get("last-modified", "")
    except (OSError, ValueError):
        return "failed", None, ""


def key_expiries(ring_path: str) -> Dict[str, int]:
    """fingerprint -> expiry (unix seconds, 0 = never) of every primary key and subkey of a ring file. A subkey's
    expiry is the earlier of its own and its primary key's."""
    t = _trust()
    out: Dict[str, int] = {}
    if t is None or not os.path.isfile(ring_path):
        return out
    try:
        with open(ring_path, "rb") as f:
            data = f.read(MAX_DB_BYTES)
        with t._private_gnupghome() as home:
            imp = t._gpg(home, ["--import"], stdin=data)
            if imp.returncode not in (0, 2):
                return out
            lst = t._gpg(home, ["--with-colons", "--fixed-list-mode", "--list-keys"])
    except Exception:
        return out
    prim_exp = 0
    pending: Optional[Tuple[str, int]] = None
    for line in lst.stdout.decode("utf-8", "replace").splitlines():
        f = line.split(":")
        if f[0] in ("pub", "sub") and len(f) > 6:
            try:
                exp = int(f[6]) if f[6] else 0
            except ValueError:
                exp = 0
            pending = (f[0], exp)
        elif f[0] == "fpr" and pending is not None and len(f) > 9:
            kind, exp = pending
            fpr = f[9].upper()
            if kind == "pub":
                prim_exp = exp
                out[fpr] = exp
            else:
                out[fpr] = min([e for e in (exp, prim_exp) if e > 0], default=0)
            pending = None
    return out


def note_used_signers(used: Dict[str, Dict[str, str]], now: Optional[int] = None) -> None:
    """gnomes_trust reports which keys signed the packages it verified (family -> {primary: signing key}); remembered
    for 90 days in the user's sentinel cache, so the expiry radar looks at keys that are really in use."""
    d = sentinel_dir()
    if not d or not used:
        return
    now = int(time.time()) if now is None else now
    with _lock:
        cur = read_json(os.path.join(d, "used_signers.json"))
        for fam, m in used.items():
            fm = cur.setdefault(fam, {})
            for prim, sgn in m.items():
                fm[prim] = {"signer": sgn, "ts": now}
        for fam in list(cur):
            if not isinstance(cur[fam], dict):
                del cur[fam]
                continue
            cur[fam] = {p: v for p, v in cur[fam].items() if isinstance(v, dict) and now - int(v.get("ts", 0)) < USED_KEEP}
        write_json(os.path.join(d, "used_signers.json"), cur)


def expiry_radar(d: str, family: str, now: int, keys_root: Optional[str] = None, shipped_dir: Optional[str] = None) -> int:
    """Earliest expiry (unix seconds) among the keys the chain rests on (anchors, extra masters, the generation's signer) that
    expire within 60 days, or 0. Silent when a newer keyring is already staged. The generation in force is judged, else the shipped snapshot."""
    t = _trust()
    if t is None:
        return 0
    gen, why = t.locate_generation(family, keys_root or t.KEYS_ROOT)
    if why:
        return 0                        # an unsafe store is not judged (Rust: Located::Unsafe gives nothing)
    sk = staged_key(d, family)
    gk = gen.pkgver_key() if gen is not None else None
    if sk is not None and (gk is None or sk > gk):
        return 0
    pol = t.policy(family)
    # the keys the chain rests on (spec section 7, the same set as the Rust app): the compiled anchors and floor pins,
    # the extra masters accepted through the chain (dynamic anchors) and the key that signed the generation in force
    wanted = {str(a).upper() for a in list(pol.get("anchors", ())) + list(pol.get("floor_pins", ()))}
    if gen is not None:
        wanted |= gen.dynamic_anchors()
        signer = str(gen.meta.get("signed_by", "")).strip().upper()
        if re.fullmatch(r"[0-9A-F]{40}", signer):
            wanted.add(signer)
        ring = gen.pubring
    else:                               # no generation yet: the snapshot shipped with the program is judged
        shipped = shipped_dir if shipped_dir is not None else t.default_shipped_dir()
        floor = os.path.join(shipped, pol["floor_file"])
        if t._file_safety(floor):
            return 0
        ring = floor
    exp = key_expiries(ring)
    soon = 0
    for fpr in wanted:
        e = exp.get(fpr, 0)
        if e > now and e <= now + KEY_EXPIRY_WARN:      # a key that already ran out is not a warning
            soon = e if soon == 0 else min(soon, e)
    return soon


def used_signer_expiry(d: str, family: str, now: int, keys_root: Optional[str] = None,
                       shipped_dir: Optional[str] = None) -> int:
    """6A-279: earliest expiry (unix seconds) within 30 days among the keys that really signed packages for `family`
    in the last 90 days (used_signers.json, written by gnomes_trust), judged against the key generation in force (a
    refreshed generation that extends the key silences it), or 0."""
    t = _trust()
    if t is None:
        return 0
    used = read_json(os.path.join(d, "used_signers.json")).get(family)
    if not isinstance(used, dict) or not used:
        return 0
    gen, why = t.locate_generation(family, keys_root or t.KEYS_ROOT)
    if why:
        return 0
    if gen is not None:
        ring = gen.pubring
    else:
        shipped = shipped_dir if shipped_dir is not None else t.default_shipped_dir()
        ring = os.path.join(shipped, t.policy(family)["floor_file"])
        if t._file_safety(ring):
            return 0
    exp = key_expiries(ring)
    soon = 0
    for prim, v in used.items():
        if not isinstance(v, dict):
            continue
        try:
            if now - int(v.get("ts", 0)) >= USED_KEEP:
                continue
        except (TypeError, ValueError):
            continue
        for fpr in (prim, v.get("signer", "")):
            e = exp.get(str(fpr).upper(), 0)
            if now < e <= now + USED_EXPIRY_WARN:
                soon = e if soon == 0 else min(soon, e)
    return soon


DAY = 86400
NET_RETRY_AFTER_FAIL = 6 * 3600


def _net_allowed(ks: Dict[str, Any], now: int, force: bool) -> bool:
    """6A-278 rate limit: network contact for keys at most once per day per family, again after 6 hours when the last
    try failed. A clock set back counts as allowed."""
    if force:
        return True
    last = int(ks.get("net_ts", 0) or 0)
    if last > now + 3600:
        return True
    return now - last >= (DAY if ks.get("net_ok", True) else NET_RETRY_AFTER_FAIL)


def fetch_db_listing(family: str, tmpdir: str, timeout: float = 8.0) -> bool:
    """Without a gnomes database: download the (small) repository database of the family into `tmpdir` so that
    listed_keyring can read which keyring file is newest. It is only a hint where to look: the package it names is
    verified by the whole keyring chain, a lying database can at most point at an older file, which is refused."""
    repo, _pkg, folder, _alias = KEYRINGS[family]
    if not repo or not folder:
        return False
    url = folder.rstrip("/") + "/" + repo + ".db"
    mm = _mm()
    for u in (mm.alternatives(url) if mm is not None else [url])[:4]:
        try:
            st, body, _h, _u = http_get(u, MAX_DB_BYTES, timeout)
        except (OSError, ValueError):
            continue
        if st != 200 or not body:
            continue
        ext = ".db.tar.zst" if body[:4] == b"\x28\xb5\x2f\xfd" else ".db.tar.gz"
        fd = os.open(os.path.join(tmpdir, repo + ext), os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
        with os.fdopen(fd, "wb") as f:
            f.write(body)
        return True
    return False


def keys_check(now: Optional[int] = None, stage: bool = True, db_dirs: Optional[List[str]] = None,
               keys_root: Optional[str] = None, shipped_dir: Optional[str] = None, force: bool = False
               ) -> Dict[str, Any]:
    """Key freshness for every family: fetch a newer verified keyring, keep the expiry radar and the refusal record in
    state.json. Silent; returns a summary {family: result}. A normal user STAGES the verified keyring in the own cache
    (installed by the first root step of a full update); root INSTALLS it directly as a new key generation (the raw
    bytes are verified again by gnomes_trust.install_keyring). Network contact is rate limited (once a day per family,
    6 hours after a failure) unless `force`; a synced gnomes database is used when present, else the small repository
    database is fetched as a hint (6A-278)."""
    d = sentinel_dir()
    out: Dict[str, Any] = {}
    t = _trust()
    if not d or t is None:
        return out
    now = int(time.time()) if now is None else int(now)
    import fcntl
    os.makedirs(d, mode=0o700, exist_ok=True)
    try:
        lock_fd = os.open(os.path.join(d, "keys-check.lock"), os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    except OSError:
        return out
    try:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return {"busy": True}
        with _lock:
            state = _load_state(d)
        prune_stage(d, keys_root)
        dbcache = state.setdefault("dbcache", {})
        kw: Dict[str, Any] = {}
        if keys_root is not None:
            kw["keys_root"] = keys_root
        if shipped_dir is not None:
            kw["shipped_dir"] = shipped_dir
        for fam in KEYRINGS:
            ks = state["keys"].setdefault(fam, {})
            gen, why = t.locate_generation(fam, keys_root or t.KEYS_ROOT)
            gkey = gen.pkgver_key() if gen is not None else None
            res = "none"
            pkgsig: Optional[Tuple[bytes, bytes]] = None
            ver_label = ""
            if not why:
                if fam == "chaotic":
                    if stage and not _net_allowed(ks, now, force):
                        res = "skipped"
                    elif stage:
                        ks["net_ts"] = now
                        st_, pkgsig, lm = download_alias(fam, ks.get("last_modified", ""))
                        res = "download_failed" if st_ == "failed" else st_
                        ks["net_ok"] = st_ != "failed"
                        if st_ == "ok":
                            ks["last_modified"] = lm
                            ver_label = "alias"
                else:
                    listed = listed_keyring(fam, db_dirs, dbcache.setdefault(fam, {}))
                    if listed is None and stage:
                        # no gnomes database (6A-278): the small repository database is the hint, once a day at most
                        if not _net_allowed(ks, now, force):
                            res = "skipped"
                        else:
                            ks["net_ts"] = now
                            with tempfile.TemporaryDirectory(prefix="slacky-db-") as tmpd:
                                os.chmod(tmpd, 0o700)
                                if fetch_db_listing(fam, tmpd):
                                    ks["net_ok"] = True
                                    listed = listed_keyring(fam, [tmpd], None)
                                    res = "current" if listed is None else "none"
                                else:
                                    ks["net_ok"] = False
                                    res = "download_failed"
                    if listed is not None:
                        lkey, fn = listed
                        newer = gkey is None or lkey > gkey
                        sk = staged_key(d, fam)
                        refused_same = ks.get("refused_file") == fn and now - int(ks.get("refused_ts", 0)) < ALERT_REPEAT
                        if newer and (sk is None or lkey > sk) and not refused_same and stage:
                            got = download_keyring(fam, fn)
                            ks["net_ts"] = now
                            ks["net_ok"] = got is not None
                            if got is None:
                                res = "download_failed"
                            else:
                                pkgsig, ver_label, res = got, fn, "downloaded"
                        else:
                            res = "current" if not newer else "pending"
            if pkgsig is not None:
                try:
                    if _is_root():
                        # root phase (6A-278): verify the raw bytes again and write a new generation, atomically
                        outcome, _gen, _upd = t.install_keyring(fam, pkgsig[0], pkgsig[1], **kw, now=now)
                        r = "installed" if outcome == "written" else "uptodate"
                    else:
                        r = t.stage_keyring(fam, pkgsig[0], pkgsig[1], _stage_dir(d), **kw, now=now)
                    res = r
                    ks.pop("refused", None)
                    ks["ok_ts"] = now
                    if r == "staged":
                        ks["staged_ts"] = now
                except t.Refusal as ref:
                    res = "refused:" + ref.kind
                    ks.update({"refused": ref.kind, "refused_ts": now, "refused_file": ver_label})
                    if ver_label == "alias":
                        ks["last_modified"] = ""       # look at the alias again next time
            if not why:
                ks["expiry"] = expiry_radar(d, fam, now, keys_root, shipped_dir)
                ks["used_expiry"] = used_signer_expiry(d, fam, now, keys_root, shipped_dir)
            out[fam] = res
        state["keys_check_ts"] = now
        _save_state(d, state)
    finally:
        os.close(lock_fd)
    return out


# ---------------------------------------------------------------------------------------------------
# alerts (one sentence, only when a whole family is at risk; each condition at most once per 7 days)
# ---------------------------------------------------------------------------------------------------

def _date(ts: int) -> str:
    return time.strftime("%Y-%m-%d", time.gmtime(ts))


def active_alerts(state: Dict[str, Any], now: int) -> List[Tuple[str, str]]:
    """[(condition key, sentence)] for every condition that holds now (no 7-day rule applied)."""
    out: List[Tuple[str, str]] = []
    t = _trust()
    live = state.get("live") if isinstance(state.get("live"), dict) else {}
    fresh_live = now - int(state.get("live_ts", 0) or 0) < 2 * WEEK
    first = int(state.get("first_run", 0) or 0)
    for fam in ("arch", "cachyos", "chaotic"):
        lab = display(fam)
        if fresh_live and fam in live and live[fam] < MIN_LIVE:
            if live[fam] == 0:
                out.append((f"live0:{fam}", tr("MIRROR_ALL_FAILED", "No download server for {repo} answered. Check your internet connection and try again later.").replace("{repo}", lab)))
            else:
                out.append((f"live1:{fam}", tr("MIRROR_ONE_LIVE", "Only one download server for {repo} works right now; updates still run, but there is no backup.").replace("{repo}", lab)))
        ok_ts = int(state.get("lists_ok", {}).get(fam, 0) or 0)
        base = max(ok_ts, first)
        if first and now - base >= LIST_STALE_SECS:
            out.append((f"list:{fam}", tr("MIRROR_LIST_STALE", "The server list for {repo} could not be refreshed for a month; downloads still work from the known servers.").replace("{repo}", lab)))
    for fam in KEYRINGS:
        ks = state.get("keys", {}).get(fam, {})
        lab = display_name(fam)
        exp = int(ks.get("expiry", 0) or 0)
        if exp:
            out.append((f"keyexp:{fam}", tr("GNOMES_TRUST_KEYS_EXPIRING", "A security key for {repo} runs out on {date}; run a full update before then so the new keys can be installed.").replace("{repo}", lab).replace("{date}", _date(exp))))
        uexp = int(ks.get("used_expiry", 0) or 0)
        if uexp > now and not exp:      # 6A-279: a key that really signed packages; one sentence per family
            out.append((f"usedexp:{fam}", tr("GNOMES_TRUST_KEYS_EXPIRING", "A security key for {repo} runs out on {date}; run a full update before then so the new keys can be installed.").replace("{repo}", lab).replace("{date}", _date(uexp))))
        kind = ks.get("refused")
        if kind and t is not None and now - int(ks.get("refused_ts", 0) or 0) < 2 * WEEK:
            out.append((f"keyref:{fam}:{kind}", t.Refusal(kind, "").sentence(fam)))
    return out


def display_name(family: str) -> str:
    t = _trust()
    return t.display_name(family) if t is not None else family


def due_alerts(now: Optional[int] = None, mark: bool = True) -> List[str]:
    """The alert sentences to show now: each condition at most once per 7 days (recorded in state.json when `mark`)."""
    d = sentinel_dir()
    if not d:
        return []
    now = int(time.time()) if now is None else int(now)
    with _lock:
        state = _load_state(d)
    shown = state.setdefault("alerts", {})
    out: List[str] = []
    for key, sentence in active_alerts(state, now):
        last = int(shown.get(key, 0) or 0)
        if last > now + 3600 or now - last >= ALERT_REPEAT:
            out.append(sentence)
            if mark:
                shown[key] = now
                record("WARN", "mirror.family_at_risk" if key.startswith(("live", "list")) else "key.expiry_soon" if key.startswith(("keyexp", "usedexp")) else "key.rejected",
                       sentence, {"condition": key}, cat="MIRROR" if key.startswith(("live", "list")) else "SUPPLY")
    if mark and out:
        # forget conditions that no longer hold
        active = {k for k, _ in active_alerts(state, now)}
        state["alerts"] = {k: v for k, v in shown.items() if k in active}
        _save_state(d, state)
    return out


# ---------------------------------------------------------------------------------------------------
# stable entry point for other programs (6A-278)
# ---------------------------------------------------------------------------------------------------
# `python3 -I slacky_sentinel.py refresh-keys [--force] [--json]`  (or refresh_keys() from Python)
# Refreshes the signed keyrings in the mode of the caller: a normal user stages, root installs a new key generation.
# Never asks for sudo, silent (--json prints the per-family result), rate limited (once a day per family, 6 hours after
# a failure; --force skips the limit). Exit codes, the first matching line wins:
RK_INSTALLED = 10      # root: a new key generation was written; verify again now
RK_STAGED = 11         # user: a verified newer keyring waits for the next root step; the keys in force are unchanged
RK_REFUSED = 20        # a keyring was downloaded but failed the rules; the keys in force are unchanged
RK_NETWORK = 21        # nothing could be downloaded
RK_BUSY = 23           # another refresh is running
RK_UNAVAILABLE = 24    # the trust module or the cache folder is missing
RK_SKIPPED = 22        # asked less than a day ago; nothing done
# 0 = the keys in force are current (nothing newer exists)


def refresh_exit_code(res: Dict[str, Any]) -> int:
    if not res:
        return RK_UNAVAILABLE
    if res.get("busy"):
        return RK_BUSY
    vals = [str(v) for k, v in res.items() if isinstance(v, str)]
    if "installed" in vals:
        return RK_INSTALLED
    if any(v.startswith("refused") for v in vals):
        return RK_REFUSED
    if "download_failed" in vals:
        return RK_NETWORK
    if "staged" in vals or "pending" in vals:
        return RK_STAGED
    if vals and all(v == "skipped" for v in vals):
        return RK_SKIPPED
    return 0


def refresh_keys(force: bool = False, **kw: Any) -> Tuple[int, Dict[str, Any]]:
    """(exit code, per-family result) of a key refresh in the mode of the caller. Never raises."""
    try:
        res = keys_check(force=force, **kw)
    except Exception:
        return RK_UNAVAILABLE, {}
    return refresh_exit_code(res), res


# ---------------------------------------------------------------------------------------------------
# command line
# ---------------------------------------------------------------------------------------------------

def status_summary() -> Dict[str, Any]:
    """What the sentinel knows, for `status` (read only)."""
    d = sentinel_dir()
    if not d:
        return {}
    st = _load_state(d)
    h = load_health(d)
    fams = {}
    for f in FAMILIES:
        cands = family_candidates(h, f)
        fams[f] = {"candidates": len(cands), "extras": len(extras(h, f)), "retired": sum(1 for p in cands if state_of(h, f, p) == "retired"),
                   "demoted": sum(1 for p in cands if state_of(h, f, p) == "demoted"),
                   "list_ok_ts": st.get("lists_ok", {}).get(f, 0)}
    return {"last_run": st.get("last_run", 0), "families": fams, "lists": st.get("lists", {})}


def main(argv: List[str]) -> int:
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print("usage: slacky_sentinel.py due | weekly [--force] | keys-check [--no-stage] [--force] | refresh-keys [--force] [--json] | alerts | status")
        return 2
    cmd = argv[1]
    try:
        if cmd == "due":
            return 0 if due() else 1
        if cmd == "weekly":
            weekly_run(force="--force" in argv)
            return 0
        if cmd == "keys-check":
            keys_check(stage="--no-stage" not in argv, force="--force" in argv)
            return 0
        if cmd == "refresh-keys":
            code, res = refresh_keys(force="--force" in argv)
            if "--json" in argv:
                print(json.dumps({"code": code, "result": res}, sort_keys=True))
            return code
        if cmd == "alerts":
            for line in due_alerts():
                print(line)
            return 0
        if cmd == "status":
            print(json.dumps(status_summary(), indent=1, sort_keys=True))
            return 0
    except Exception:
        return 0                    # the sentinel is silent and never breaks the caller
    print("unknown command")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
