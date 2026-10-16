#!/usr/bin/env python3
"""Shared mirror lists and mirror fall-back for the package repositories (6A-180..183).

Standalone: no dependency on any other program. Behaviour matches the rules of the other implementation of this
tool (ranked mirrors, bounded fall-back, daily ranking, failed mirrors sink), written from the same specification.

* Families: Arch Linux, Chaotic-AUR, CachyOS. One candidate list per family (the single source of these lists; the
  benchmark script rank_mirrors.py imports them).
* alternatives(url): the same file on the next ranked mirrors of the family, at most MAX_ATTEMPTS. Only the host part
  changes, never the file: the caller still checks every file exactly as before (signature, checksum, magic bytes).
  A bad file is never "healed" by asking another mirror; the caller fails closed.
* Chaotic-AUR keeps a weekly ranking in <cache>/chaotic_fastest_mirror.json (6A-201, spec section 0): refreshed when
  the last round is a week old, or 10 minutes after a mirror failed (or when nothing answered). A failing mirror moves
  behind the others. The slow cdn-mirror is a last resort and is never probed.
* 6A-201: the candidate lists are the built-in lists (the floor, never shorter) plus the servers of the newest SIGNED
  mirror lists, fetched weekly by slacky_sentinel.py. That helper also keeps a per-mirror health history: a mirror
  that failed for good is retired (moved behind the others), one that lags far behind is demoted. Downloads report
  their result here (note_failure / note_success). Without the helper or its cache everything behaves as before.
* Arch and CachyOS orders come from ranked_mirrors.json (written by rank_mirrors.py) when present.
* Silent. When every mirror failed, all_failed_sentence() gives one plain sentence.
"""

import concurrent.futures
import datetime
import json
import os
import stat
import sys
import tempfile
import threading
import time
import urllib.request

MAX_ATTEMPTS = 4
PROBE_LIMIT_S = 2.5
EARLY_STOP = 3
RETRY_AFTER_FAILURE_SECS = 600

# (label, base url); a label is only used by the benchmark report
ARCH_CANDIDATES = [
    ("Global Geo-DNS (pkgbuild.com)", "https://geo.mirror.pkgbuild.com"),
    ("Worldwide CDN (rackspace.com)", "https://mirror.rackspace.com/archlinux"),
    ("USA (kernel.org)", "https://mirrors.kernel.org/archlinux"),
    ("Sweden (acc.umu.se)", "https://ftp.acc.umu.se/mirror/archlinux"),
    ("Germany (thaller.ws)", "https://archlinux.thaller.ws"),
    ("Denmark (dotsrc.org)", "https://mirrors.dotsrc.org/archlinux"),
    ("Netherlands (osbeck.com)", "https://mirror.osbeck.com/archlinux"),
    ("Germany (f4st.host)", "https://mirror.f4st.host/archlinux"),
]

# 6A-183: eu.cachyos.org and asia.cachyos.org do not resolve in DNS any more (checked 2026-10-15), cdn77 answers.
CACHYOS_CANDIDATES = [
    ("Global CDN (mirror.cachyos.org)", "https://mirror.cachyos.org/repo"),
    ("CDN77 (cdn77.cachyos.org)", "https://cdn77.cachyos.org/repo"),
    ("USA Node (us.cachyos.org)", "https://us.cachyos.org/repo"),
]

CHAOTIC_CANDIDATES = [
    ("Geo Mirror (geo-mirror.chaotic.cx)", "https://geo-mirror.chaotic.cx/chaotic-aur"),
    ("Germany 1 (de-1-mirror.chaotic.cx)", "https://de-1-mirror.chaotic.cx/chaotic-aur"),
    ("Germany 2 (de-2-mirror.chaotic.cx)", "https://de-2-mirror.chaotic.cx/chaotic-aur"),
    ("Netherlands (nl-1-mirror.chaotic.cx)", "https://nl-1-mirror.chaotic.cx/chaotic-aur"),
    ("France (fr-1-mirror.chaotic.cx)", "https://fr-1-mirror.chaotic.cx/chaotic-aur"),
    ("Germany 4 (de-4-mirror.chaotic.cx)", "https://de-4-mirror.chaotic.cx/chaotic-aur"),
    ("Canada (ca-mirror.chaotic.cx)", "https://ca-mirror.chaotic.cx/chaotic-aur"),
    ("USA Michigan (us-mi-mirror.chaotic.cx)", "https://us-mi-mirror.chaotic.cx/chaotic-aur"),
]
# slow, used after the ranked ones, never probed
CHAOTIC_LAST_RESORT = [("Global CDN (cdn-mirror.chaotic.cx)", "https://cdn-mirror.chaotic.cx/chaotic-aur")]

_LABEL = {"arch": "Arch Linux", "chaotic": "Chaotic-AUR", "cachyos": "CachyOS"}
_RANKED_KEY = {"arch": "arch_ranked", "cachyos": "cachyos_ranked", "chaotic": "chaotic_ranked"}
_CHAOTIC_PROBE_REL = "/x86_64/chaotic-aur.db"
_CHAOTIC_FILE = "chaotic_fastest_mirror.json"

_lock = threading.Lock()
_noted = set()


def builtin_lists():
    """The built-in lists (the floor): {family: (candidates, last resorts)}."""
    return {
        "arch": ([u for _, u in ARCH_CANDIDATES], []),
        "cachyos": ([u for _, u in CACHYOS_CANDIDATES], []),
        "chaotic": ([u for _, u in CHAOTIC_CANDIDATES], [u for _, u in CHAOTIC_LAST_RESORT]),
    }


_SENTINEL = False
_HEALTH_CACHE = {}


def _sentinel():
    """lib/slacky_sentinel.py loaded by explicit path (PYTHONSAFEPATH keeps this folder off sys.path); None when it is
    missing or broken: the built-in lists then stay the only source."""
    global _SENTINEL
    if _SENTINEL is False:
        _SENTINEL = None
        try:
            import importlib.util
            path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "slacky_sentinel.py")
            spec = importlib.util.spec_from_file_location("slacky_sentinel", path)
            if spec and spec.loader:
                mod = sys.modules.get("slacky_sentinel") or importlib.util.module_from_spec(spec)
                if "slacky_sentinel" not in sys.modules:
                    sys.modules["slacky_sentinel"] = mod
                    spec.loader.exec_module(mod)
                _SENTINEL = mod
        except Exception:
            _SENTINEL = None
    return _SENTINEL


def _health():
    """(sentinel module, health history) from the user's sentinel cache, re-read only when the file changed. (None, {})
    for root or when there is no sentinel."""
    s = _sentinel()
    if s is None:
        return None, {}
    try:
        d = s.sentinel_dir()
        if not d:
            return None, {}
        path = os.path.join(d, "health.json")
        try:
            st = os.stat(path)
            key = (path, st.st_mtime_ns, st.st_size)
        except OSError:
            return s, {}
        hit = _HEALTH_CACHE.get("h")
        if hit and hit[0] == key:
            return s, hit[1]
        h = s.load_health(d)
        _HEALTH_CACHE["h"] = (key, h)
        return s, h
    except Exception:
        return None, {}


def _family_lists():
    """{family: (candidates, last resorts)}: the built-in lists plus the servers of the newest signed lists."""
    base = builtin_lists()
    s, h = _health()
    if s is None or not h:
        return base
    out = {}
    for fam, (cands, last) in base.items():
        try:
            ex = [p for p in s.extras(h, fam) if p not in cands and p not in last]
        except Exception:
            ex = []
        out[fam] = (cands + ex, last)
    return out


def locate(url):
    """(family, mirror base, rest of the url starting with '/') or None for a host that is not a known mirror."""
    best = None
    for fam, (cands, last) in _family_lists().items():
        for b in cands + last:
            if url.startswith(b) and url[len(b):].startswith("/"):
                if best is None or len(b) > len(best[1]):
                    best = (fam, b, url[len(b):])
    return best


def benchmark_candidates(family):
    """[(label, url)] for the benchmark: the built-in list plus the signed-list servers, at most 8 chosen by the health
    history (retired mirrors skipped). Falls back to the built-in tuples."""
    builtin = {"arch": ARCH_CANDIDATES, "cachyos": CACHYOS_CANDIDATES, "chaotic": CHAOTIC_CANDIDATES}[family]
    sn, hh = _health()
    if sn is None:
        return list(builtin)
    try:
        cands = _family_lists()[family][0]
        chosen = sn.probe_set(hh, family, cands, int(time.time()))
        names = dict((u, lab) for lab, u in builtin)
        return [(names.get(u) or u.split("//", 1)[-1].split("/", 1)[0], u) for u in chosen]
    except Exception:
        return list(builtin)


def label_for(url):
    loc = locate(url)
    return _LABEL[loc[0]] if loc else ""


def all_failed_sentence(url):
    """One plain sentence for 'every mirror of this repo failed', empty for an unknown host."""
    lab = label_for(url)
    if not lab:
        return ""
    english = "No download server for {repo} answered. Check your internet connection and try again later."
    sn = _sentinel()
    if sn is not None:
        try:
            return sn.tr("MIRROR_ALL_FAILED", english).replace("{repo}", lab)
        except Exception:
            pass
    return english.replace("{repo}", lab)


# ---------------------------------------------------------------------------------------------------
# cache directory and safe file access
# ---------------------------------------------------------------------------------------------------

def default_cache_dir():
    """SLACKY_MIRROR_CACHE_DIR (tests), else the system cache when writable, else the user cache."""
    env = os.environ.get("SLACKY_MIRROR_CACHE_DIR")
    if env:
        return env
    for d in ("/var/cache/slacky-update", os.path.expanduser("~/.cache/slacky-update")):
        try:
            os.makedirs(d, exist_ok=True)
            if os.access(d, os.W_OK):
                return d
        except OSError:
            continue
    return os.path.expanduser("~/.cache/slacky-update")


def _read_json(path):
    """Our own plain file only: a symlink, a file of someone else or an oversized file is ignored."""
    try:
        st = os.lstat(path)
        if not stat.S_ISREG(st.st_mode) or st.st_uid != os.geteuid() or st.st_size > (1 << 20):
            return None
        with open(path, "r", encoding="utf-8") as f:
            d = json.load(f)
        return d if isinstance(d, dict) else None
    except Exception:
        return None


def _write_json(path, data):
    d = os.path.dirname(path)
    try:
        os.makedirs(d, mode=0o755, exist_ok=True)
        fd, tmp = tempfile.mkstemp(prefix=".chaotic_mirror.", dir=d)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump(data, f)
            os.chmod(tmp, 0o644)
            os.replace(tmp, path)
        except Exception:
            try:
                os.unlink(tmp)
            except OSError:
                pass
    except Exception:
        pass


# ---------------------------------------------------------------------------------------------------
# Chaotic-AUR daily ranking
# ---------------------------------------------------------------------------------------------------

RANK_PERIOD_SECS = 7 * 86400


def is_stale(entry, today, now):
    """True when the cached Chaotic ranking is due for a new probe round: the last round is a week old (or from the
    future), or 10 minutes after a mirror failed. Pure, for tests. `today` is kept for the callers' signature."""
    if not entry or not isinstance(entry.get("ranked"), list) or not entry["ranked"]:
        return True
    try:
        probed = float(entry.get("probed_ts", 0))
    except (TypeError, ValueError):
        return True
    if probed > now + 3600 or (now - probed) >= RANK_PERIOD_SECS:
        return True
    return bool(entry.get("needs_refresh")) and (now - probed) >= RETRY_AFTER_FAILURE_SECS


def _looks_like_db(b):
    return b.startswith(b"\x28\xb5\x2f\xfd") or b.startswith(b"\x1f\x8b")


def _probe_one(base, limit):
    t0 = time.time()
    try:
        req = urllib.request.Request(base + _CHAOTIC_PROBE_REL,
                                     headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64)", "Range": "bytes=0-255"})
        with urllib.request.urlopen(req, timeout=limit) as resp:
            head = resp.read(256)
        if _looks_like_db(head):
            return base, int((time.time() - t0) * 1000)
    except Exception:
        pass
    return base, None


def _probe_chaotic(limit=PROBE_LIMIT_S):
    """Probe every candidate in parallel; the full order (answered by speed, the rest, the last resort) and
    whether anything answered. Stops as soon as EARLY_STOP mirrors answered."""
    cands = list(_family_lists()["chaotic"][0])
    to_probe = cands
    sn, hh = _health()
    if sn is not None:
        try:
            to_probe = sn.probe_set(hh, "chaotic", cands, int(time.time()))      # at most 8, retired ones skipped
        except Exception:
            to_probe = cands[:8]
    else:
        to_probe = cands[:8]
    good, failed = [], set()
    ex = concurrent.futures.ThreadPoolExecutor(max_workers=max(1, len(to_probe)))
    futs = [ex.submit(_probe_one, b, limit) for b in to_probe]
    try:
        for fut in concurrent.futures.as_completed(futs, timeout=limit):
            base, ms = fut.result()
            if ms is None:
                failed.add(base)
            else:
                good.append((ms, base))
                if len(good) >= EARLY_STOP:
                    break
    except Exception:
        pass
    ex.shutdown(wait=False, cancel_futures=True)
    good.sort()
    have = {b for _, b in good}
    out = [{"url": b, "latency_ms": ms} for ms, b in good]
    out += [{"url": b, "latency_ms": None} for b in cands if b not in have and b not in failed]
    out += [{"url": b, "latency_ms": None} for b in cands if b in failed]
    out += [{"url": u, "latency_ms": None} for _, u in CHAOTIC_LAST_RESORT]
    if sn is not None:      # retired mirrors go behind the others, demoted ones behind the active ones
        try:
            urls = sn.sort_by_state(hh, "chaotic", [r["url"] for r in out], [u for _, u in CHAOTIC_LAST_RESORT])
            by = {r["url"]: r for r in out}
            out = [by[u] for u in urls]
        except Exception:
            pass
    return out, bool(good)


def _today():
    return datetime.datetime.now().strftime("%Y-%m-%d")


def chaotic_order(cdir=None):
    """The Chaotic mirror bases in ranked order from the cache; only known mirrors, missing ones appended."""
    cdir = cdir or default_cache_dir()
    cands, last = _family_lists()["chaotic"]
    known = cands + last
    out = []
    e = _read_json(os.path.join(cdir, _CHAOTIC_FILE))
    if e and isinstance(e.get("ranked"), list):
        for r in e["ranked"]:
            u = r.get("url") if isinstance(r, dict) else None
            if u in known and u not in out:
                out.append(u)
    for b in known:
        if b not in out:
            out.append(b)
    # the last resort stays last whatever the cache says
    return [b for b in out if b not in last] + [b for b in out if b in last]


def chaotic_refresh_if_due(cdir=None, probe=None):
    """Probe when the cached ranking is from an earlier day (or due after a failure). Cheap otherwise.
    `probe` replaces the network probe in tests."""
    cdir = cdir or default_cache_dir()
    path = os.path.join(cdir, _CHAOTIC_FILE)
    now = time.time()
    with _lock:
        if not is_stale(_read_json(path), _today(), now):
            return
        ranked, answered = (probe or _probe_chaotic)()
        best = next((r["url"] for r in ranked if r.get("latency_ms") is not None), ranked[0]["url"] if ranked else "")
        _write_json(path, {
            "mirror": best + "/x86_64/",
            "timestamp": now,
            "date": _today(),
            "latency_ms": next((r["latency_ms"] for r in ranked if r["url"] == best), None),
            "probed_ts": now,
            "needs_refresh": not answered,
            "ranked": ranked,
        })
        _noted.clear()


def chaotic_fastest(cdir=None):
    """The Chaotic-AUR mirror to read repository listings from, as '<base>/x86_64/' (the old function's format)."""
    cdir = cdir or default_cache_dir()
    try:
        chaotic_refresh_if_due(cdir)
        order = chaotic_order(cdir)
    except Exception:
        order = [u for _, u in CHAOTIC_CANDIDATES]
    for b in order:
        return b + "/x86_64/"
    return "https://geo-mirror.chaotic.cx/chaotic-aur/x86_64/"


def note_success(url):
    """A download from this mirror worked: it clears the failure streak of its health history (buffered, written
    once at exit). Silent; nothing for root or without the sentinel helper."""
    loc = locate(url)
    sn = _sentinel()
    if not loc or sn is None:
        return
    try:
        sn.note(loc[0], loc[1], True, len(_family_lists()[loc[0]][0]))
    except Exception:
        pass


def note_failure(url, cdir=None):
    """A mirror failed (connect error, timeout, 5xx, a body that is not a package): the health history counts it, and
    a Chaotic mirror also moves behind the other candidates (before the last resort) with a new probe in 10 minutes."""
    loc = locate(url)
    if not loc:
        return
    sn = _sentinel()
    if sn is not None:
        try:
            sn.note(loc[0], loc[1], False, len(_family_lists()[loc[0]][0]))
        except Exception:
            pass
    if loc[0] != "chaotic":
        return
    base = loc[1]
    cdir = cdir or default_cache_dir()
    path = os.path.join(cdir, _CHAOTIC_FILE)
    with _lock:
        if base in _noted:
            return
        _noted.add(base)
        cands, last = _family_lists()["chaotic"]
        order = [b for b in chaotic_order(cdir) if b != base]
        at = max([i for i, b in enumerate(order) if b in cands], default=-1) + 1
        order.insert(at, base)
        old = _read_json(path) or {}
        lat = {r.get("url"): r.get("latency_ms") for r in old.get("ranked", []) if isinstance(r, dict)}
        now = time.time()
        old.update({
            "mirror": order[0] + "/x86_64/",
            "timestamp": old.get("timestamp", now),
            "date": old.get("date") or _today(),
            "probed_ts": now,
            "needs_refresh": True,
            "ranked": [{"url": b, "latency_ms": lat.get(b)} for b in order],
        })
        _write_json(path, old)


# ---------------------------------------------------------------------------------------------------
# alternatives
# ---------------------------------------------------------------------------------------------------

def _ranked_json_order(fam):
    """Arch / CachyOS order from ranked_mirrors.json (rank_mirrors.py), valid mirrors fastest first."""
    out = []
    env = os.environ.get("SLACKY_MIRROR_CACHE_DIR")
    paths = [os.path.join(env, "ranked_mirrors.json")] if env else [
        os.path.expanduser("~/.cache/slacky-update/ranked_mirrors.json"), "/var/cache/slacky-update/ranked_mirrors.json"]
    for p in paths:
        d = _read_json(p)
        if d:
            for r in d.get(_RANKED_KEY[fam], []):
                u = r.get("url") if isinstance(r, dict) else None
                if isinstance(u, str):
                    out.append(u.rstrip("/"))
            break
    return out


def alternatives(url, cdir=None):
    """The urls to try for `url`, no network: the original alone for an unknown host, else the same file on the
    ranked mirrors of its family, at most MAX_ATTEMPTS."""
    loc = locate(url)
    if not loc:
        return [url]
    fam, base, rest = loc
    cands, last = _family_lists()[fam]
    known = cands + last
    if fam == "chaotic":
        cdir = cdir or default_cache_dir()
        if os.path.exists(os.path.join(cdir, _CHAOTIC_FILE)):
            order = chaotic_order(cdir)
        else:
            order = [base] + [b for b in known if b != base]
    else:
        order = [b for b in _ranked_json_order(fam) if b in known]
        order += [b for b in [base] + known if b not in order]
    seen, uniq = set(), []
    for b in order:
        if b not in seen:
            seen.add(b)
            uniq.append(b)
    sn, hh = _health()
    if sn is not None and hh:
        try:      # active first, demoted behind them, retired last (6A-201); nothing is dropped
            uniq = sn.sort_by_state(hh, fam, uniq, last)
        except Exception:
            pass
    return [b + rest for b in uniq][:MAX_ATTEMPTS]
