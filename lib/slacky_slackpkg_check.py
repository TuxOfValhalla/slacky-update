#!/usr/bin/env python3
"""6A-243: user-level view of what `slackpkg update` + `slackpkg upgrade-all` + `slackpkg install-new` would bring.

Standalone (standard library only), no sudo, silent. Run as `python3 -I slacky_slackpkg_check.py all ...` by
check_backend.sh; prints ONE JSON object:

  {"slackpkgplus_updates": ["compat32-tools-3.10-noarch-19alien.tgz", ...],
   "slackpkgplus_unverified": ["repo", ...],     # repos whose list is only a hint (no usable signature check)
   "slackpkgplus_failed": ["repo", ...],         # repos whose signature was BAD: their packages are NOT listed
   "slackware_new_packages": ["l/libgit2-1.9.7-x86_64-1.txz", ...],
   "slackpkgplus_ok": true|false}                # false when no repo list could be read at all (keep the old list)

Why: /var/lib/slackpkg/pkglist is refreshed only by `slackpkg update` as root, so a user-level check saw a stale list and
never showed multilib (compat32) updates. Now the repo lists are fetched here, as the user, into the app's own cache.

slackpkg+ repositories
  * /etc/slackpkg/slackpkgplus.conf: MIRRORPLUS['name']=url, REPOPLUS=( names ); only http(s) addresses.
  * <url>/CHECKSUMS.md5 is fetched with a conditional request (ETag / Last-Modified) into
    <cache>/slackpkgplus/<repo>/ ; <url>/CHECKSUMS.md5.asc is verified with gpgv against the key slackpkg already
    trusts for that repo (/var/lib/slackpkg/gpg/GPG-KEY-<repo>.gpg), in a throw-away GnuPG home.
      verified   -> listed
      bad sig    -> repo dropped (fail closed), named in slackpkgplus_failed
      no sig / no key / no gpgv -> listed as a HINT only, repo named in slackpkgplus_unverified
    The real update is still done and verified by slackpkg itself; this list only tells the user what to expect.
  * Per repo the newest build of each package name; an installed package with a strictly newer one is listed.
    /etc/slackpkg/blacklist is honoured (same matching as slackpkg: the regex is searched in the line
    " repo name version arch build " ; a line `series/` blacklists a Slackware series).
  Limits: PKGS_PRIORITY / TAG_PRIORITY / GREYLIST are not evaluated (a package that slackpkg would take from another
  repo may be listed); dir:// and file:// repositories are not read.

Slackware install-new
  slackpkg install-new reads the ChangeLog for packages ADDED (or split / renamed / moved) and installs the ones that
  are not installed. A user-level check cannot know what the owner skipped on purpose, so only the ChangeLog sections
  NEWER than the installed state are used: the installed state is the newest section (of the last 50) in which every
  entry for an installed, not blacklisted package is already installed. A package added in an older section is not
  listed again (limit); when no section shows the installed state nothing is listed. Packages removed in the window, in testing/pasture/extra/source, and blacklisted ones are skipped.
"""

import concurrent.futures
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

UA = "Mozilla/5.0 (X11; Linux x86_64) Slacky-Update/1.0 slackpkg-check"
MAX_LIST_BYTES = 16 * 1024 * 1024
MAX_SIG_BYTES = 64 * 1024
CONNECT_TIMEOUT = 8
MAX_HEADERS = 50
ASC_RETRY_SECS = 24 * 3600

_PKG_EXT = (".txz", ".tgz", ".tbz", ".tlz")
_DATE_RE = re.compile(r"^[A-Za-z]{3}\s+[A-Za-z]{3}\s+[0-9\s]{2}\s+[0-9:]+\s+[A-Z]+\s+[0-9]{4}")
_ENTRY_RE = re.compile(
    r"^((?:[a-zA-Z0-9_\-+]+/)+[a-zA-Z0-9_\-+.]+-(?:x86_64|x86|i[3-6]86|noarch|arm|fw)-[0-9a-zA-Z_]+\.(?:t[xg]z|tlz|tbz))"
    r":\s+(Added|Upgraded|Rebuilt|Removed|Split|Renamed|Moved|Name change|NAME CHANGE|Switched)", re.I)
_NEW_ACTIONS = {"added", "split", "renamed", "moved", "name change", "switched"}
_SKIP_DIRS = ("testing/", "pasture/", "source/", "extra/")


# ---------------------------------------------------------------------------------------------------
# small helpers shared with the other lib modules (package names, versions)
# ---------------------------------------------------------------------------------------------------

def strip_ext(name):
    for e in _PKG_EXT:
        if name.endswith(e):
            return name[:-len(e)]
    return name


def parse_pkg(filename):
    """(name, version, arch, build, clean) of name-version-arch-build[.ext]; whole string as name when it does not fit."""
    clean = strip_ext(os.path.basename(filename))
    parts = clean.split("-")
    if len(parts) >= 4:
        return "-".join(parts[:-3]), parts[-3], parts[-2], parts[-1], clean
    return clean, "0", "0", "0", clean


def _tokens(s):
    return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", str(s)) if t]


def _lt(a, b):
    """Total-order less-than that never compares int with str."""
    for x, y in zip(a, b):
        if x == y:
            continue
        if isinstance(x, int) and isinstance(y, int):
            return x < y
        if isinstance(x, str) and isinstance(y, str):
            return x < y
        return isinstance(x, int)          # numbers sort before words
    return len(a) < len(b)


def is_strictly_newer(installed_full, upstream_full):
    """Same rule as check_backend.sh: version first, then build."""
    if installed_full == upstream_full:
        return False
    _, iv, _, ib, _ = parse_pkg(installed_full)
    _, uv, _, ub, _ = parse_pkg(upstream_full)
    i_v, u_v = _tokens(iv), _tokens(uv)
    if u_v != i_v:
        return _lt(i_v, u_v)
    return _lt(_tokens(ib), _tokens(ub))


def installed_map(pkgdir):
    out = {}
    try:
        names = os.listdir(pkgdir)
    except OSError:
        return out
    for f in names:
        parts = f.rsplit("-", 3)
        if len(parts) == 4:
            out[parts[0]] = f
    return out


def read_text(path, cap=4 << 20):
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as fh:
            return fh.read(cap)
    except OSError:
        return ""


# ---------------------------------------------------------------------------------------------------
# network (IPv4 retry from slacky_net.py when present)
# ---------------------------------------------------------------------------------------------------

_NET = False


def _urlopen(req, timeout):
    global _NET
    if _NET is False:
        _NET = None
        try:
            import importlib.util
            path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "slacky_net.py")
            spec = importlib.util.spec_from_file_location("slacky_net", path)
            if spec and spec.loader:
                mod = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(mod)
                _NET = mod
        except Exception:
            _NET = None
    if _NET is not None:
        return _NET.open_url(req, timeout=timeout)
    return urllib.request.urlopen(req, timeout=timeout)


def http_get(url, cap, headers=None, timeout=CONNECT_TIMEOUT):
    """(status, body, response headers lower-cased). 304 comes back as (304, b"", headers). Raises on a network error or
    HTTP error other than 304. Only http/https."""
    if not url.lower().startswith(("https://", "http://")):
        raise ValueError("not an http(s) address")
    h = {"User-Agent": UA}
    h.update(headers or {})
    req = urllib.request.Request(url, headers=h)
    try:
        with _urlopen(req, timeout) as resp:
            body = resp.read(cap + 1)
            if len(body) > cap:
                raise ValueError("answer too large")
            return resp.status, body, {k.lower(): v for k, v in resp.headers.items()}
    except urllib.error.HTTPError as e:
        if e.code == 304:
            return 304, b"", {k.lower(): v for k, v in e.headers.items()}
        raise


# ---------------------------------------------------------------------------------------------------
# slackpkg blacklist
# ---------------------------------------------------------------------------------------------------

def load_blacklist(path):
    """(compiled patterns, series set). Same reading as slackpkg: blanks and # lines dropped, each line a regex."""
    pats, series = [], set()
    for line in read_text(path, 1 << 20).splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        m = re.match(r"^([^/\s]+)/$", s)
        if m:
            series.add(m.group(1))
            continue
        try:
            pats.append(re.compile(" " + s + " "))
        except re.error:
            continue
    return pats, series


def is_blacklisted(bl, repo, name, ver, arch, build, series=""):
    pats, sers = bl
    if series and series in sers:
        return True
    line = " %s %s %s %s %s " % (repo, name, ver, arch, build)
    return any(p.search(line) for p in pats)


# ---------------------------------------------------------------------------------------------------
# slackpkg+ repositories
# ---------------------------------------------------------------------------------------------------

def parse_conf(text):
    """({repo: url}, [enabled repos in REPOPLUS order or None], allow32)."""
    urls = {}
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("#"):
            continue
        m = re.match(r"^MIRRORPLUS\[\s*['\"]?([^'\"\]]+?)['\"]?\s*\]\s*=\s*(.+)$", s)
        if m:
            url = m.group(2).strip().strip("'\"").strip()
            if url:
                urls[m.group(1).strip()] = url
    enabled = None
    m = re.search(r"^[ \t]*REPOPLUS=\(\s*([^)]*)\)", text, re.M)
    if m:
        enabled = [r.strip("'\"") for r in m.group(1).split() if not r.startswith("#")]
    allow32 = bool(re.search(r"^[ \t]*ALLOW32BIT=on", text, re.M))
    return urls, enabled, allow32


def _safe(name):
    return re.sub(r"[^A-Za-z0-9._+-]", "_", name)[:80] or "repo"


def _write_atomic(path, data):
    d = os.path.dirname(path)
    os.makedirs(d, mode=0o700, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".w.", dir=d)
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def _read_meta(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            d = json.load(fh)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def verify_signature(sig_path, data_path, keyring):
    """'verified' | 'bad' | 'unverified' using gpgv in a throw-away home. A missing gpgv/key/sig is 'unverified'."""
    gpgv = shutil.which("gpgv")
    if not gpgv or not os.path.isfile(keyring) or not os.path.isfile(sig_path):
        return "unverified"
    home = tempfile.mkdtemp(prefix="slacky-gpgv.")
    try:
        os.chmod(home, 0o700)
        r = subprocess.run([gpgv, "--homedir", home, "--keyring", keyring, "--status-fd", "1", sig_path, data_path],
                           stdin=subprocess.DEVNULL, capture_output=True, timeout=30, text=True)
        out = r.stdout or ""
        if r.returncode == 0 and "GOODSIG" in out:
            return "verified"
        if "BADSIG" in out:
            return "bad"
        return "unverified"
    except (OSError, subprocess.SubprocessError):
        return "unverified"
    finally:
        shutil.rmtree(home, ignore_errors=True)


def fetch_repo(repo, base, cache_root, gpgdir, now=None, getter=None):
    """Fetch (conditional) and verify one repo. Returns (text or None, verdict) with verdict in
    verified / unverified / bad / none (no list at all)."""
    getter = getter or http_get
    now = int(now if now is not None else time.time())
    base = base.rstrip("/") + "/"
    rdir = os.path.join(cache_root, "slackpkgplus", _safe(repo))
    lst, asc, meta_p = (os.path.join(rdir, "CHECKSUMS.md5"), os.path.join(rdir, "CHECKSUMS.md5.asc"),
                        os.path.join(rdir, "meta.json"))
    meta = _read_meta(meta_p)
    if meta.get("url") != base:
        meta = {"url": base}
    hdr = {}
    if os.path.isfile(lst):
        if meta.get("etag"):
            hdr["If-None-Match"] = meta["etag"]
        if meta.get("last_modified"):
            hdr["If-Modified-Since"] = meta["last_modified"]
    changed = False
    try:
        st, body, rh = getter(base + "CHECKSUMS.md5", MAX_LIST_BYTES, hdr)
        if st != 304:
            if not re.search(rb"^[0-9a-f]{32}\s", body, re.M):
                raise ValueError("not a CHECKSUMS.md5")
            _write_atomic(lst, body)
            meta["etag"], meta["last_modified"] = rh.get("etag", ""), rh.get("last-modified", "")
            meta["sha256"] = hashlib.sha256(body).hexdigest()
            meta.pop("verdict", None)
            changed = True
    except Exception:
        if not os.path.isfile(lst):
            return None, "none"
        # offline / error: the cached list still describes the repo (the staleness is the same as slackpkg's own)
    if not os.path.isfile(lst):
        return None, "none"
    if changed or not os.path.isfile(asc):
        if changed or now - int(meta.get("asc_ts", 0) or 0) >= ASC_RETRY_SECS:
            meta["asc_ts"] = now
            try:
                st, sig, _ = getter(base + "CHECKSUMS.md5.asc", MAX_SIG_BYTES, {})
                if st != 304 and b"BEGIN PGP" in sig:
                    _write_atomic(asc, sig)
                else:
                    raise ValueError("no signature")
            except Exception:
                if changed and os.path.isfile(asc):
                    try:
                        os.unlink(asc)           # an old signature must not be paired with a new list
                    except OSError:
                        pass
    verdict = verify_signature(asc, lst, os.path.join(gpgdir, "GPG-KEY-%s.gpg" % repo))
    meta["verdict"] = verdict
    try:
        _write_atomic(meta_p, json.dumps(meta).encode())
    except OSError:
        pass
    return read_text(lst, MAX_LIST_BYTES), verdict


def parse_checksums(text, want64=True, allow32=False):
    """{name: best full name with extension} from the lines of a CHECKSUMS.md5."""
    best = {}
    for line in text.splitlines():
        m = re.match(r"^[0-9a-f]{32}\s+\./?(.+)$", line.strip())
        if not m:
            continue
        rel = m.group(1)
        base = os.path.basename(rel)
        if not base.endswith(_PKG_EXT) or "/source/" in "/" + rel:
            continue
        name, ver, arch, build, clean = parse_pkg(base)
        if clean == name:
            continue
        if want64 and not allow32 and re.match(r"^(x86|i[3-6]86|arm)$", arch):
            continue
        cur = best.get(name)
        if cur is None or is_strictly_newer(strip_ext(cur), clean):
            best[name] = base
    return best


def check_plus(conf_path, pkgdir, cache_root, blacklist_path, gpgdir, getter=None, now=None, want64=None):
    """The slackpkg+ part. Returns a dict with slackpkgplus_updates / _unverified / _failed / _ok."""
    urls, enabled, allow32 = parse_conf(read_text(conf_path))
    repos = [r for r in (enabled if enabled is not None else list(urls)) if r in urls and
             urls[r].lower().startswith(("http://", "https://"))]
    res = {"slackpkgplus_updates": [], "slackpkgplus_unverified": [], "slackpkgplus_failed": [], "slackpkgplus_ok": False}
    if not repos:
        res["slackpkgplus_ok"] = enabled is None or not enabled      # nothing configured is a clean "no updates"
        return res
    if want64 is None:
        want64 = any(f.startswith("aaa_base-") and "-x86_64-" in f for f in _listdir(pkgdir)) or \
            os.uname().machine == "x86_64"
    inst = installed_map(pkgdir)
    bl = load_blacklist(blacklist_path)
    got_one = False
    out = set()

    def one(r):
        return r, fetch_repo(r, urls[r], cache_root, gpgdir, now=now, getter=getter)

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
        results = list(ex.map(one, repos))
    for repo, (text, verdict) in results:
        if text is None:
            continue
        got_one = True
        if verdict == "bad":
            res["slackpkgplus_failed"].append(repo)
            continue
        if verdict != "verified":
            res["slackpkgplus_unverified"].append(repo)
        for name, fn in parse_checksums(text, want64, allow32).items():
            cur = inst.get(name)
            if cur is None:
                continue
            _n, ver, arch, build, clean = parse_pkg(fn)
            if is_blacklisted(bl, repo, name, ver, arch, build):
                continue
            if is_strictly_newer(cur, clean):
                out.add(fn)
    res["slackpkgplus_updates"] = sorted(out)
    res["slackpkgplus_ok"] = got_one
    return res


def _listdir(p):
    try:
        return os.listdir(p)
    except OSError:
        return []


# ---------------------------------------------------------------------------------------------------
# Slackware install-new
# ---------------------------------------------------------------------------------------------------

def parse_sections(text, max_headers=MAX_HEADERS):
    """[[(path, action_lower), ...], ...] newest section first, at most max_headers sections."""
    sections, cur, n = [], None, 0
    for line in text.splitlines():
        if _DATE_RE.match(line):
            n += 1
            if n > max_headers:
                break
            cur = []
            sections.append(cur)
            continue
        m = _ENTRY_RE.match(line)
        if m and cur is not None:
            cur.append((m.group(1), m.group(2).lower()))
    return sections


def check_new(changelog_text, pkgdir, blacklist_path):
    """Packages ADDED in the ChangeLog sections newer than the installed state (see the module text)."""
    inst = installed_map(pkgdir)
    bl = load_blacklist(blacklist_path)
    sections = parse_sections(changelog_text)

    def info(path):
        series = path.split("/", 1)[0]
        n, v, a, b, clean = parse_pkg(os.path.basename(path))
        return series, n, v, a, b, clean

    def relevant(path):
        if path.startswith(_SKIP_DIRS):
            return None
        series, n, v, a, b, clean = info(path)
        if is_blacklisted(bl, "slackware64", n, v, a, b, series):
            return None
        return series, n, v, a, b, clean

    baseline = None
    for idx, sec in enumerate(sections):
        evidence, ok = 0, True
        for path, act in sec:
            r = relevant(path)
            if r is None or act == "removed":
                continue
            cur = inst.get(r[1])
            if cur is None:
                continue
            evidence += 1
            if is_strictly_newer(cur, r[5]):
                ok = False
                break
        if ok and evidence:
            baseline = idx
            break
    if baseline is None:      # no section shows the installed state: no honest "since the installed state"
        return []
    removed, seen, out = set(), set(), []
    for sec in sections[:baseline]:
        for path, act in sec:
            r = relevant(path)
            if r is None:
                continue
            n = r[1]
            if act == "removed":
                removed.add(n)
                continue
            if n in seen or n in removed:
                continue
            seen.add(n)
            if act in _NEW_ACTIONS and n not in inst:
                out.append(path)
    return sorted(set(p for p in out if parse_pkg(os.path.basename(p))[0] not in removed))


# ---------------------------------------------------------------------------------------------------
# command line
# ---------------------------------------------------------------------------------------------------

def _arg(argv, flag, default):
    if flag in argv:
        i = argv.index(flag)
        if i + 1 < len(argv):
            return argv[i + 1]
    return default


def main(argv):
    mode = argv[1] if len(argv) > 1 else "all"
    pkgdir = _arg(argv, "--pkgdir", "/var/log/packages")
    conf = _arg(argv, "--conf", "/etc/slackpkg/slackpkgplus.conf")
    bl = _arg(argv, "--blacklist", "/etc/slackpkg/blacklist")
    gpgdir = _arg(argv, "--gpgdir", "/var/lib/slackpkg/gpg")
    cache = _arg(argv, "--cache", os.path.join(os.environ.get("XDG_CACHE_HOME") or
                                               os.path.join(os.path.expanduser("~"), ".cache"), "slacky-update"))
    changelog = _arg(argv, "--changelog", "")
    out = {}
    if mode in ("all", "plus"):
        out.update(check_plus(conf, pkgdir, cache, bl, gpgdir))
    if mode in ("all", "new") and changelog:
        out["slackware_new_packages"] = check_new(read_text(changelog, 64 << 20), pkgdir, bl)
    json.dump(out, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Exception:
        # never break the check: an empty answer means "keep what you had"
        sys.stdout.write("{}\n")
        sys.exit(0)
