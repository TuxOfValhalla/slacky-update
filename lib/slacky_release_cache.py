#!/usr/bin/env python3
"""Cached vendor release lists that survive unattended checks (6A-325).

GitHub's API allows 60 unauthenticated requests per hour and address, and both programs share that address. One list is
the body file `<cache>` plus a sidecar `<cache>.etag`. The modification time of the body file is "when the server last
confirmed this list". Rules, in this order:
  1. a list confirmed less than LIST_TTL_SECS ago (30 min; 6 h for api.github.com) is used without any request;
  2. while the server said "rate limit" and its reset time has not come (file `ratelimit_<host>` in the cache folder),
     no request is made to that host at all;
  3. otherwise one conditional request (If-None-Match): 304 costs no rate limit and renews the list, 200 replaces it;
  4. when the request fails the last good list is kept for up to STALE_MAX_SECS (3 days); an older or missing list
     means "could not check" (the caller gets None). A bad answer never overwrites the saved list or etag.
The reason of a failure goes ONCE per run and reason to the flight recorder (gnomes_trust.flight_record). The rules are
the same as in the other implementation of this tool (written from the same spec); no code is shared.
Standalone: no dependency on another program; the flight recorder is optional.
"""

import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

GITHUB_API = "https://api.github.com/"
LIST_TTL_SECS = 6 * 3600
OTHER_TTL_SECS = 1800
STALE_MAX_SECS = 3 * 86400
DEFAULT_PAUSE_SECS = 900
MIN_PAUSE_SECS = 60
MAX_PAUSE_SECS = 2 * 3600
CAP = 4 << 20
UA = "Mozilla/5.0 (X11; Linux x86_64)"

_LOGGED = set()
_RECORDER = None
RECORDER_HOOK = None   # tests set a callable(cat, lvl, ev, msg, data); None = gnomes_trust.flight_record when found


def cache_file_for(url, cdir):
    return os.path.join(cdir, "repo_idx_%s.html" % hashlib.sha256(url.encode("utf-8")).hexdigest()[:16])


def host_of(url):
    return url.split("://", 1)[-1].split("/", 1)[0].split("?", 1)[0]


def _safe_host(url):
    return re.sub(r"[^A-Za-z0-9_.-]", "_", host_of(url))


def _pause_path(cdir, url):
    return os.path.join(cdir, "ratelimit_" + _safe_host(url))


def _read_pause(cdir, url, now):
    try:
        with open(_pause_path(cdir, url), "r", encoding="utf-8") as f:
            reset = int(json.loads(f.read()).get("reset", 0))
        return reset if reset > now else 0
    except Exception:
        return 0


def _atomic_write(path, data):
    try:
        tmp = "%s.%d.tmp" % (path, os.getpid())
        with open(tmp, "wb") as f:
            f.write(data)
        os.replace(tmp, path)
        return True
    except Exception:
        return False


def pause_until(headers, now):
    """Epoch second until which no request is made: X-RateLimit-Reset (epoch) or Retry-After (seconds), clamped."""
    def num(k):
        try:
            return int(str(headers.get(k, "")).strip())
        except Exception:
            return None
    reset = num("X-RateLimit-Reset")
    if reset is None or reset <= now:
        ra = num("Retry-After")
        reset = now + ra if ra is not None and ra >= 0 else None
    if reset is None:
        reset = now + DEFAULT_PAUSE_SECS
    return max(now + MIN_PAUSE_SECS, min(now + MAX_PAUSE_SECS, reset))


def is_rate_limit(code, headers):
    """429 always; 403 only with X-RateLimit-Remaining: 0 or a Retry-After header (a plain 403 is not a rate limit)."""
    if code == 429:
        return True
    if code == 403:
        rem = str(headers.get("X-RateLimit-Remaining", "")).strip()
        return rem == "0" or headers.get("Retry-After") is not None
    return False


def describe(kind, detail, now):
    if kind == "rate-limit":
        mins = max(1, -(-(int(detail) - now) // 60))
        return "GitHub's request limit is used up (it frees up in about %d min)" % mins
    if kind == "http":
        return "the server answered HTTP %s" % detail
    if kind == "network":
        return "the server did not answer"
    return "the answer was not a usable release list"


def _record(url, kind, detail, now, stale_used):
    key = (host_of(url), kind)
    if key in _LOGGED:
        return
    _LOGGED.add(key)
    msg = "The release list of %s could not be refreshed: %s%s" % (
        host_of(url), describe(kind, detail, now), "; the saved list (under 3 days old) is used" if stale_used else "")
    data = {"host": host_of(url), "kind": kind}
    try:
        hook = RECORDER_HOOK
        if hook is None:
            global _RECORDER
            if _RECORDER is None:
                import importlib.util
                p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gnomes_trust.py")
                spec = importlib.util.spec_from_file_location("gnomes_trust_rc", p)
                m = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(m)
                _RECORDER = m.flight_record
            hook = _RECORDER
        hook("UPDATE", "WARN", "release_list.refresh_failed", msg[:300], data)
    except Exception:
        pass


def _valid(raw, want):
    try:
        obj = json.loads(raw.decode("utf-8", errors="ignore"))
    except Exception:
        return False
    return isinstance(obj, want)


def fetch_list(url, cdir, ttl=None, want=(list, dict), https_prefix=GITHUB_API, timeout=5):
    """Return (body bytes or None, failure kind or None). The body may be the last good list when failure is not None."""
    now = int(time.time())
    if ttl is None:
        ttl = LIST_TTL_SECS if url.startswith(GITHUB_API) else OTHER_TTL_SECS
    cf = cache_file_for(url, cdir)
    etag_file = cf + ".etag"
    cached, age = None, None
    try:
        if os.path.getsize(cf) <= CAP:
            with open(cf, "rb") as f:
                raw = f.read()
            if _valid(raw, want):
                cached, age = raw, max(0, now - int(os.path.getmtime(cf)))
    except Exception:
        pass
    if cached is not None and age < ttl:
        return cached, None

    def fail(kind, detail=None):
        use = cached if (cached is not None and age <= STALE_MAX_SECS) else None
        _record(url, kind, detail, int(time.time()), use is not None)
        return use, kind

    until = _read_pause(cdir, url, now)
    if until:
        return fail("rate-limit", until)
    headers = {"User-Agent": UA, "Accept": "application/vnd.github+json"} if url.startswith(GITHUB_API) else {"User-Agent": UA}
    etag = None
    if cached is not None:
        try:
            with open(etag_file, "r", encoding="utf-8") as f:
                etag = f.read().strip() or None
        except Exception:
            etag = None
    if etag and "\n" not in etag and "\r" not in etag:
        headers["If-None-Match"] = etag
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            if https_prefix and not resp.geturl().startswith(https_prefix):
                return fail("parse")
            new_etag = resp.headers.get("ETag")
            raw = resp.read(CAP + 1)
    except urllib.error.HTTPError as he:
        hdrs = he.headers if he.headers is not None else {}
        if he.code == 304 and cached is not None:
            try:
                os.utime(cf, (now, now))
            except Exception:
                pass
            return cached, None
        if is_rate_limit(he.code, hdrs):
            until = pause_until(hdrs, now)
            _atomic_write(_pause_path(cdir, url), json.dumps({"reset": until}).encode())
            return fail("rate-limit", until)
        return fail("http", he.code)
    except Exception:
        return fail("network")
    if len(raw) > CAP or not _valid(raw, want):
        return fail("parse")
    if _atomic_write(cf, raw):
        if new_etag and "\n" not in new_etag:
            _atomic_write(etag_file, new_etag.strip().encode())
        else:
            try:
                os.remove(etag_file)
            except OSError:
                pass
    return raw, None


def fetch_text(url, cdir, ttl=None):
    """Text of the list, or "" when there is nothing usable (callers treat "" as "could not check")."""
    body, _ = fetch_list(url, cdir, ttl=ttl)
    return body.decode("utf-8", errors="ignore") if body is not None else ""


def releases(repo, cdir):
    """Release list of owner/repo as a Python list ([] when there is nothing usable)."""
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo or ""):
        return []
    body, _ = fetch_list("%srepos/%s/releases" % (GITHUB_API, repo), cdir, want=(list,))
    try:
        return json.loads(body.decode("utf-8", errors="ignore")) if body is not None else []
    except Exception:
        return []
