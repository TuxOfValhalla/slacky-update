#!/usr/bin/env python3
"""6A-327: symbol-version headroom guard (pure Python, no readelf needed).

A program built against a newer library (for example OpenRGB asking for Qt_6.12 while Slackware has Qt 6.11) dies at start-up
with "version `Qt_6.12' not found". This module reads, for every 64-bit ELF of a staging tree, the versions it needs
(DT_VERNEED) and compares them with the versions the library that will really be loaded defines (DT_VERDEF).

Library search order (the order the real loader and the launcher wrapper use):
  mode "curated": files of the package itself, then the host; when the host cannot satisfy it, the Underpants runtime is tried
                  (verdict RUNTIME = install with a launcher wrapper that puts the runtime first), else REFUSE.
  mode "app":     files of the app itself, then the Underpants runtime pool, then the host (gnomes launcher order).
Environment overrides for tests, honoured ONLY when SLACKY_SELFTEST=1 (normal runs ignore them): SLACKY_SYMVER_HOST_DIRS
(colon list, replaces ldconfig), SLACKY_SYMVER_RUNTIME, SLACKY_SYMVER_CACHE (hold-file directory).

CLI:  slacky_symver.py check TREE --mode curated|app [--runtime DIR]
        prints HOST | RUNTIME | REFUSE | SKIP on the first line; RUNTIME is followed by one tree-relative path per ELF that must
        be wrapped; REFUSE is followed by the missing-version facts "<file>|<soname>|<version>|<lib path>|<where>" per line.
      slacky_symver.py startcheck --candidate DIR [--live DIR] [--pkgs DIR] [--staged DIR]... [--baseline FILE]
        7L: JSON result; exit 1 = a refresh of the runtime would stop an app that starts today (new failures only)
      slacky_symver.py hold PID VERSION SONAME LIBVERSION [STAMPS...]   remember a refused version
      slacky_symver.py held PID VERSION     exit 0 when that version is still waiting (the libraries are unchanged)
"""
import json
import mmap
import os
import struct
import subprocess
import sys
import time

RUNTIME_DEFAULT = "/opt/underpants/runtime"


def _test_env(name):
    """6A-338: test hooks are read only under SLACKY_SELFTEST=1."""
    if os.environ.get("SLACKY_SELFTEST") == "1":
        return os.environ.get(name)
    return None
EXTRA_DIRS = ["/usr/lib64/libproxy", "/usr/lib64/pulseaudio", "/usr/lib64/pipewire-0.3", "/usr/lib64/samba"]
HOST_FALLBACK = ["/lib64", "/usr/lib64"]
WRAPPABLE = ("usr/bin", "usr/sbin", "bin", "sbin", "usr/local/bin")

DT_NEEDED, DT_STRTAB, DT_VERDEF, DT_VERDEFNUM, DT_VERNEED, DT_VERNEEDNUM = 1, 5, 0x6ffffffc, 0x6ffffffd, 0x6ffffffe, 0x6fffffff
DT_RPATH, DT_RUNPATH = 15, 29
EM_X86_64 = 62
VER_FLG_BASE, VER_FLG_WEAK = 1, 2


class Elf:
    """Minimal reader for 64-bit little-endian ELF files: DT_NEEDED, version needs, version definitions."""

    def __init__(self, path):
        self.path = path
        self.ok = False
        self.needed = []
        self.needs = {}   # soname -> set(version)
        self.defs = set()
        self.has_defs = False
        self.etype = 0
        self.machine = 0
        self.has_interp = False      # 7L: PT_INTERP present = a program, not a library
        self.runpath = []            # 7L: DT_RUNPATH entries (raw, $ORIGIN not expanded)
        self.rpath = []              # 7L: DT_RPATH entries
        # mapped, not read: only the pages the dynamic section, string and version tables live in are touched
        try:
            with open(path, "rb") as fh:
                self.data = mmap.mmap(fh.fileno(), 0, access=mmap.ACCESS_READ)
        except (OSError, ValueError):
            return
        d = self.data
        try:
            if len(d) < 64 or d[:4] != b"\x7fELF" or d[4] != 2 or d[5] != 1:
                return
            try:
                self._parse()
            except (struct.error, IndexError, ValueError):
                self.ok = False
        finally:
            self.data = None
            d.close()

    def _parse(self):
        d = self.data
        self.etype = struct.unpack_from("<H", d, 16)[0]
        self.machine = struct.unpack_from("<H", d, 18)[0]
        phoff, = struct.unpack_from("<Q", d, 32)
        phentsize, phnum = struct.unpack_from("<HH", d, 54)
        loads, dyn = [], None
        for i in range(phnum):
            o = phoff + i * phentsize
            p_type, _fl, p_off, p_vaddr, _pa, p_filesz, _ms, _al = struct.unpack_from("<IIQQQQQQ", d, o)
            if p_type == 1:
                loads.append((p_vaddr, p_off, p_filesz))
            elif p_type == 2:
                dyn = (p_off, p_filesz)
            elif p_type == 3:
                self.has_interp = True
        self.ok = True
        if not dyn:
            return

        def off(vaddr):
            for va, fo, fs in loads:
                if va <= vaddr < va + fs:
                    return fo + (vaddr - va)
            raise ValueError("unmapped")

        tags = {}
        needed_offs = []
        path_offs = []
        for o in range(dyn[0], dyn[0] + dyn[1], 16):
            tag, val = struct.unpack_from("<qQ", d, o)
            if tag == 0:
                break
            if tag == DT_NEEDED:
                needed_offs.append(val)
            else:
                tags[tag] = val
                if tag in (DT_RPATH, DT_RUNPATH):
                    path_offs.append((tag, val))
        if DT_STRTAB not in tags:
            return
        strtab = off(tags[DT_STRTAB])

        def s(o):
            e = d.find(b"\0", strtab + o)
            if e < 0:
                raise ValueError("unterminated string")
            return d[strtab + o:e].decode("utf-8", "replace")

        self.needed = [s(v) for v in needed_offs]
        for tag, val in path_offs:
            ents = [x for x in s(val).split(":") if x]
            if tag == DT_RUNPATH:
                self.runpath = ents
            else:
                self.rpath = ents
        if DT_VERNEED in tags and DT_VERNEEDNUM in tags:
            o = off(tags[DT_VERNEED])
            for _ in range(tags[DT_VERNEEDNUM]):
                _ver, cnt, fileoff, auxoff, nxt = struct.unpack_from("<HHIII", d, o)
                lib = s(fileoff)
                a = o + auxoff
                for _j in range(cnt):
                    _h, flags, _other, name, anext = struct.unpack_from("<IHHII", d, a)
                    if not flags & VER_FLG_WEAK:
                        self.needs.setdefault(lib, set()).add(s(name))
                    if not anext:
                        break
                    a += anext
                if not nxt:
                    break
                o += nxt
        if DT_VERDEF in tags and DT_VERDEFNUM in tags:
            o = off(tags[DT_VERDEF])
            for _ in range(tags[DT_VERDEFNUM]):
                _ver, flags, _ndx, cnt, _hash, auxoff, nxt = struct.unpack_from("<HHHHIII", d, o)
                if cnt:
                    name, _an = struct.unpack_from("<II", d, o + auxoff)
                    self.defs.add(s(name))
                    self.has_defs = True
                if not nxt:
                    break
                o += nxt


def is_elf64(path):
    try:
        if os.path.islink(path) or not os.path.isfile(path):
            return False
        with open(path, "rb") as fh:
            h = fh.read(6)
        return h[:4] == b"\x7fELF" and h[4:5] == b"\x02"
    except OSError:
        return False


def host_map():
    """soname -> path of the 64-bit host libraries."""
    res = {}
    env = _test_env("SLACKY_SYMVER_HOST_DIRS")
    dirs = env.split(":") if env is not None else None
    if dirs is None:
        try:
            out = subprocess.run(["/sbin/ldconfig", "-p"], capture_output=True, text=True, timeout=20).stdout
            for line in out.splitlines():
                parts = line.strip().split(" => ")
                if len(parts) == 2 and "x86-64" in parts[0]:
                    res.setdefault(parts[0].split(" ", 1)[0], parts[1])
        except (OSError, subprocess.SubprocessError):
            pass
        dirs = HOST_FALLBACK
    for d in dirs:
        try:
            for f in os.listdir(d):
                res.setdefault(f, os.path.join(d, f))
        except OSError:
            continue
    return res


def dir_map(dirs):
    res = {}
    for d in dirs:
        try:
            for f in os.listdir(d):
                res.setdefault(f, os.path.join(d, f))
        except OSError:
            continue
    return res


def tree_map(tree):
    res = {}
    for root, _dirs, files in os.walk(tree):
        for f in files:
            res.setdefault(f, os.path.join(root, f))
    return res


def stamp(path):
    try:
        st = os.stat(path)
        return f"{os.path.realpath(path)}:{st.st_size}:{st.st_mtime_ns}"
    except OSError:
        return f"{path}:none"


class Checker:
    def __init__(self, tree, mode="curated", runtime=None):
        self.tree = os.path.abspath(tree)
        self.mode = mode
        self.runtime = runtime or _test_env("SLACKY_SYMVER_RUNTIME") or RUNTIME_DEFAULT
        self.own = tree_map(self.tree)
        self.host = host_map()
        self.rt_dirs = [os.path.join(self.runtime, "lib"), os.path.join(self.runtime, "lib64")]
        self.rt = dir_map(self.rt_dirs)
        self.runtime_present = any(os.path.isdir(d) for d in self.rt_dirs)
        self._defs = {}

    def defs_of(self, path):
        if path not in self._defs:
            e = Elf(path)
            self._defs[path] = e if e.ok else None
        return self._defs[path]

    def _missing(self, soname, vers, path):
        """Versions of `vers` that the library at `path` does not define (a library without any version info is accepted,
        the loader only warns then)."""
        e = self.defs_of(path)
        if e is None or not e.has_defs:
            return []
        return sorted(v for v in vers if v not in e.defs)

    def elf_files(self):
        out = []
        for root, _d, files in os.walk(self.tree):
            for f in files:
                p = os.path.join(root, f)
                if is_elf64(p):
                    out.append(p)
        return sorted(out)

    def check_elf(self, elf, order):
        """Returns list of (soname, version, libpath, where) that fail for this search order, [] when it fits."""
        bad = []
        for soname, vers in sorted(elf.needs.items()):
            path, where = None, ""
            for label, m in order:
                if soname in m:
                    path, where = m[soname], label
                    break
            if not path:
                continue  # library not found anywhere: not a version problem (other checks cover a missing library)
            for v in self._missing(soname, vers, path):
                bad.append((soname, v, path, where))
        return bad

    def run(self):
        order_host = [("package", self.own), ("host", self.host)]
        order_rt = [("package", self.own), ("runtime", self.rt), ("host", self.host)]
        order_app = order_rt
        res = {"verdict": "HOST", "wrap": [], "bad": [], "stamps": []}
        files = self.elf_files()
        if self.mode == "app":
            for p in files:
                e = self.defs_of(p)
                if e is None:
                    continue
                for soname, v, lp, where in self.check_elf(e, order_app):
                    res["bad"].append((os.path.relpath(p, self.tree), soname, v, lp, where))
            if res["bad"]:
                res["verdict"] = "REFUSE"
            return self._stamps(res)
        failing = []
        for p in files:
            e = self.defs_of(p)
            if e is None:
                continue
            host_bad = self.check_elf(e, order_host)
            if host_bad:
                failing.append((p, e, host_bad))
        if not failing:
            return res
        res["verdict"] = "RUNTIME"
        for p, e, host_bad in failing:
            rel = os.path.relpath(p, self.tree)
            rt_bad = self.check_elf(e, order_rt) if self.runtime_present else host_bad
            if rt_bad or not self.runtime_present:
                for soname, v, lp, where in (rt_bad or host_bad):
                    res["bad"].append((rel, soname, v, lp, where))
                res["verdict"] = "REFUSE"
            elif not any(rel.startswith(w + "/") and rel.count("/") == w.count("/") + 1 for w in WRAPPABLE) \
                    or e.etype not in (2, 3) or not os.access(p, os.X_OK) or ".so" in os.path.basename(rel):
                # fixed by the runtime, but the file is not a program the launcher wrapper can start
                for soname, v, lp, where in host_bad:
                    res["bad"].append((rel, soname, v, lp, "host"))
                res["verdict"] = "REFUSE"
            else:
                res["wrap"].append(rel)
        if res["verdict"] == "REFUSE":
            res["wrap"] = []
        return self._stamps(res)

    def _stamps(self, res):
        seen = set()
        for _f, soname, _v, lp, _w in res["bad"]:
            seen.add(stamp(lp))
            for d in self.rt_dirs:
                seen.add(stamp(os.path.join(d, soname)))
            if soname in self.host:
                seen.add(stamp(self.host[soname]))
        res["stamps"] = sorted(seen)
        return res


def pretty_lib(soname, ver):
    return f"{soname} ({ver})"


def refusal_sentence(app, version, res, runtime_present=True):
    """One plain sentence; names the highest missing version of the first library."""
    def vkey(v):
        import re
        return tuple(int(x) for x in re.findall(r"\d+", v)) or (0,)
    worst = max(res["bad"], key=lambda b: vkey(b[2]))
    lib = f"{worst[1]} ({worst[2]})"
    label = f"{app} {version}".strip()
    if not runtime_present:
        return (f"{label} needs a newer {lib} than this system has and the shared runtime is not installed, "
                f"so it was not updated; the installed version stays.")
    return f"{label} needs a newer {lib} than this system has, so it was not updated; the installed version stays."


# --- hold file (waiting list) -------------------------------------------------------------------------------------------
def hold_paths():
    env = _test_env("SLACKY_SYMVER_CACHE")
    if env:
        return [os.path.join(env, "lib_hold.json")]
    return [os.path.join("/var/cache/slacky-update", "lib_hold.json"),
            os.path.join(os.path.expanduser("~/.cache/slacky-update"), "lib_hold.json")]


def load_holds():
    holds = {}
    for fp in hold_paths():
        try:
            with open(fp, encoding="utf-8") as fh:
                for k, v in json.load(fh).items():
                    if isinstance(v, dict):
                        holds[k] = v
        except (OSError, ValueError):
            continue
    return holds


def record_hold(pid, version, res, sentence):
    paths = hold_paths()
    fp = paths[0] if os.geteuid() == 0 or len(paths) == 1 else paths[1]
    try:
        os.makedirs(os.path.dirname(fp), exist_ok=True)
        data = {}
        try:
            with open(fp, encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, ValueError):
            data = {}
        data[pid] = {"version": version, "stamps": res["stamps"], "reason": sentence,
                     "since": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
        tmp = fp + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2)
        os.replace(tmp, fp)
    except OSError:
        pass


def clear_hold(pid):
    for fp in hold_paths():
        try:
            with open(fp, encoding="utf-8") as fh:
                data = json.load(fh)
            if pid in data:
                del data[pid]
                with open(fp + ".tmp", "w", encoding="utf-8") as fh:
                    json.dump(data, fh, indent=2)
                os.replace(fp + ".tmp", fp)
        except (OSError, ValueError):
            continue


def stamp_now(s):
    """Re-evaluate a stored stamp ('<realpath>:<size>:<mtime>' or '<path>:none')."""
    return stamp(s.rsplit(":", 2)[0])


def is_held(pid, version, holds=None):
    """True while that exact version is waiting and none of the libraries involved has changed."""
    h = (holds if holds is not None else load_holds()).get(pid)
    if not h or h.get("version") != version:
        return False
    for s in h.get("stamps", []):
        if s.endswith(":none"):
            if os.path.exists(s[:-5]):
                return False
        elif stamp_now(s) != s:
            return False
    return True


# --- 7L: startability of the installed apps against a CANDIDATE runtime (docs/runtime_refresh_spec.md section 6) -----------
# A refresh of the shared runtime must not stop an app that starts today. For every installed app (and every app staged in
# this run) the closure of its programs' DT_NEEDED is followed through the app's own libraries and the runtime (candidate or
# live), in the order the launcher wrapper and the loader use. Rules: S1 a needed library is found nowhere, S2 a needed symbol
# version (DT_VERNEED) is not defined by the library that gets picked, S3 the Python / Lua minor of the runtime moved while the
# app carries modules for the old minor. A refresh is vetoed only for NEW failures (present with the candidate, absent with
# the live runtime). Libraries found in host directories are leaves. Nothing is executed; only ELF headers are read.
LIVE_RUNTIME = "/opt/underpants/runtime"
LIVE_COMMON = "/opt/underpants/common"
HOST_PLUGIN_DIRS = ["/usr/lib64/libproxy", "/usr/lib64/pulseaudio", "/usr/lib64/pipewire-0.3", "/usr/lib64/samba"]
PLUGIN_MARKERS = ("qt6/plugins", "qt5/plugins", "qt/plugins", "gstreamer-1.0", "gio/modules", "gdk-pixbuf-2.0", "gtk-3.0",
                  "gtk-4.0", "ossl-modules", "sasl2", "krb5", "libproxy", "webkit2gtk-4.1", "lib-dynload", "/qml/")


def _host_root():
    """Test hook (SLACKY_SELFTEST=1 only): fixed host folders such as /usr/lib64 are read below this folder."""
    return _test_env("SLACKY_SYMVER_HOST_ROOT") or ""


class Startability:
    """Library-resolution model with one runtime folder standing in for /opt/underpants/runtime."""

    def __init__(self, runtime_root, host=None):
        self.rt = os.path.abspath(runtime_root)
        self.host = host if host is not None else host_map()
        self._elf = {}
        self._dirs = {}
        self._glob = {}
        self.followed = {}

    # -- path helpers
    def mp(self, p):
        """Map a path that names the live runtime to this model's runtime folder; host folders honour the test root."""
        if p == LIVE_RUNTIME or p.startswith(LIVE_RUNTIME + "/"):
            return self.rt + p[len(LIVE_RUNTIME):]
        if p.startswith("/usr/") or p.startswith("/lib"):
            return _host_root() + p
        return p

    def listing(self, d):
        if d not in self._dirs:
            try:
                self._dirs[d] = set(os.listdir(d))
            except OSError:
                self._dirs[d] = set()
        return self._dirs[d]

    def elf(self, path):
        """Parsed 64-bit x86-64 ELF at `path`, else None (a file of the wrong class is skipped by the loader)."""
        if path not in self._elf:
            e = Elf(path) if os.path.isfile(path) else None
            self._elf[path] = e if (e is not None and e.ok and e.machine == EM_X86_64) else None
        return self._elf[path]

    def subdirs(self, base, sub):
        """Existing directories base/<glob sub>, sorted (the wrapper's nested-folder loop)."""
        import fnmatch
        key = (base, sub)
        if key not in self._glob:
            out = []

            def walk(cur, rest):
                if not rest:
                    if os.path.isdir(cur):
                        out.append(cur)
                    return
                head, tail = rest[0], rest[1:]
                try:
                    names = sorted(os.listdir(cur))
                except OSError:
                    return
                for n in names:
                    if fnmatch.fnmatchcase(n, head):
                        walk(os.path.join(cur, n), tail)
            walk(base, sub.split("/"))
            self._glob[key] = out
        return self._glob[key]

    # -- the wrapper's LD_LIBRARY_PATH
    def wrapper_dirs(self, kind, app_root):
        tail = [self.mp(LIVE_RUNTIME + "/lib"), self.mp(LIVE_RUNTIME + "/lib64"), LIVE_COMMON + "/lib"] \
            + [self.mp(d) for d in HOST_PLUGIN_DIRS] + [self.mp("/usr/lib64")]
        if kind != "gnomes":
            return tail
        lib = os.path.join(app_root, "lib")
        nested = []
        for base, sub in ((lib, "ghc-*/lib/*"), (lib, "ghc-*"), (lib, "lua/*"), (lib, "*"),
                          (self.mp(LIVE_RUNTIME + "/lib"), "ghc-*/lib/*")):
            nested += self.subdirs(base, sub)
        # the wrapper PREPENDS in loop order, so the last folder found is searched first
        return list(reversed(nested)) + [lib, os.path.join(app_root, "lib64")] + tail

    # -- one lookup
    def lookup(self, name, obj_path, e, ld_dirs):
        if "/" in name:
            p = self.mp(name) if name.startswith("/") else os.path.join(os.path.dirname(obj_path), name)
            return p if self.elf(p) else None
        origin = os.path.dirname(obj_path)

        def expand(entries):
            return [self.mp(x.replace("${ORIGIN}", origin).replace("$ORIGIN", origin)) for x in entries]
        order = []
        if e is not None and e.rpath and not e.runpath:
            order += expand(e.rpath)
        order += ld_dirs
        if e is not None:
            order += expand(e.runpath)
        for d in order:
            if name in self.listing(d):
                p = os.path.join(d, name)
                if self.elf(p):
                    return p
        hp = self.host.get(name)
        if hp and self.elf(hp):
            return hp
        for d in ("/lib64", "/usr/lib64"):
            d = _host_root() + d
            if name in self.listing(d):
                p = os.path.join(d, name)
                if self.elf(p):
                    return p
        return None

    @staticmethod
    def inside(p, root):
        return p == root or p.startswith(root.rstrip("/") + "/")

    # -- one app
    def programs(self, kind, app_root):
        """ELF programs directly in the app's bin folder; for a script app the runtime interpreter its first line names."""
        bindir = os.path.join(app_root, "bin" if kind == "gnomes" else "usr/bin")
        try:
            names = sorted(os.listdir(bindir))
        except OSError:
            return []
        out, scripts = [], []
        for n in names:
            p = os.path.join(bindir, n)
            e = self.elf(p)
            if e is not None and e.has_interp:
                out.append(p)
            elif e is None and os.path.isfile(p):
                scripts.append(p)
        if out:
            return out
        for p in scripts:
            try:
                with open(p, "rb") as fh:
                    first = fh.readline(200).decode("utf-8", "replace").strip()
            except OSError:
                continue
            if not first.startswith("#!"):
                continue
            parts = first[2:].split()
            if not parts:
                continue
            if os.path.basename(parts[0]) == "env" and len(parts) > 1:
                cand = self.mp(LIVE_RUNTIME + "/bin/" + parts[1])
            else:
                cand = self.mp(parts[0])
            if self.inside(cand, self.rt):
                real = os.path.realpath(cand)
                e = self.elf(real)
                if e is not None and e.has_interp and real not in out:
                    out.append(real)
        return out

    def check_app(self, app, kind, app_root):
        """(set of failure tuples (app, rule, file, soname, version), programs, files followed) for one app tree."""
        fails = set()
        progs = self.programs(kind, app_root)
        if not progs:
            return fails, 0, 0
        ld_dirs = self.wrapper_dirs(kind, app_root)
        seen = set()
        stack = list(progs)

        def fid(p):
            if self.inside(p, app_root):
                return os.path.relpath(p, app_root)
            if self.inside(p, self.rt):
                return "runtime/" + os.path.relpath(p, self.rt)
            return p
        while stack:
            f = stack.pop()
            if f in seen:
                continue
            seen.add(f)
            e = self.elf(f)
            if e is None:
                continue
            for n in e.needed:
                p = self.lookup(n, f, e, ld_dirs)
                if p is None:
                    fails.add((app, "S1", fid(f), n, ""))
                    continue
                if self.inside(p, app_root) or self.inside(p, self.rt):
                    stack.append(p)
            for soname, vers in e.needs.items():
                p = self.lookup(soname, f, e, ld_dirs)
                if not p:
                    continue
                pe = self.elf(p)
                if pe is None or not pe.has_defs:
                    continue
                for v in vers:
                    if v not in pe.defs:
                        fails.add((app, "S2", fid(f), soname, v))
        self.followed.setdefault(app, set()).update(seen)
        return fails, len(progs), len(seen)

    def app_plugins_missing(self, app, kind, app_root):
        """Library files of an app that no program links (dlopen plugins) with a needed library found nowhere."""
        n = 0
        ld_dirs = self.wrapper_dirs(kind, app_root)
        done = self.followed.get(app, set())
        for root, _d, files in os.walk(app_root):
            for f in files:
                if ".so" not in f:
                    continue
                p = os.path.join(root, f)
                if p in done:
                    continue
                e = self.elf(p)
                if e is not None and any(self.lookup(x, p, e, ld_dirs) is None for x in e.needed):
                    n += 1
        return n

    def plugins_missing(self):
        """Count of plugin / module files of the runtime with a needed library found nowhere (recorded, never a veto)."""
        n = 0
        ld = [self.mp(LIVE_RUNTIME + "/lib"), self.mp(LIVE_RUNTIME + "/lib64")]
        base = os.path.join(self.rt, "lib")
        for root, _d, files in os.walk(base):
            rel = "/" + os.path.relpath(root, base) + "/"
            if not any(m in rel for m in PLUGIN_MARKERS):
                continue
            for f in files:
                if ".so" not in f:
                    continue
                p = os.path.join(root, f)
                e = self.elf(p)
                if e is None:
                    continue
                if any(self.lookup(x, p, e, ld) is None for x in e.needed):
                    n += 1
        return n


def app_trees(pkgs_dir, staged=()):
    """[(app, kind, root)]: gnomes layout (bin/ or lib/) or curated launcher layout (usr/); plus staged trees."""
    found = []

    def classify(d):
        if os.path.isdir(os.path.join(d, "bin")) or os.path.isdir(os.path.join(d, "lib")):
            return "gnomes"
        if os.path.isdir(os.path.join(d, "usr")):
            return "curated"
        return None
    try:
        names = sorted(os.listdir(pkgs_dir))
    except OSError:
        names = []
    for n in names:
        d = os.path.join(pkgs_dir, n)
        if os.path.isdir(d) and not os.path.islink(d):
            k = classify(d)
            if k:
                found.append((n, k, d))
    for d in staged:
        d = os.path.abspath(d)
        k = classify(d)
        if k and not any(x[2] == d for x in found):
            found.append((os.path.basename(d.rstrip("/")), k, d))
    return found


def _manifest_pkg_minor(root, name):
    """'3.14' for python 3.14.8-1.1 from <root>/.gnomes/manifest.json, else ''."""
    try:
        with open(os.path.join(root, ".gnomes", "manifest.json"), encoding="utf-8") as fh:
            m = json.load(fh)
        for p in m.get("packages", []):
            if p.get("name") == name:
                v = str(p.get("version", "")).split(":")[-1].split("-")[0]
                bits = v.split(".")
                return ".".join(bits[:2]) if len(bits) >= 2 else ""
    except (OSError, ValueError, AttributeError):
        pass
    return ""


def s3_failures(trees, live_root, cand_root):
    """S3: the interpreter minor of the runtime moved and an app carries modules for the old one."""
    out = set()
    for name in ("python", "lua"):
        old, new = _manifest_pkg_minor(live_root, name), _manifest_pkg_minor(cand_root, name)
        if not old or not new or old == new:
            continue
        for app, _kind, root in trees:
            if name == "python":
                cands = [os.path.join(root, lib, "python" + old) for lib in ("lib", "lib64", "usr/lib", "usr/lib64")]
            else:
                cands = [os.path.join(root, lib, "lua", old) for lib in ("lib", "usr/lib", "usr/lib64")]
            for c in cands:
                try:
                    if os.path.isdir(c) and os.listdir(c):
                        out.add((app, "S3", os.path.relpath(c, root), name, f"{old} -> {new}"))
                except OSError:
                    pass
    return out


def run_startcheck(candidate, live=None, pkgs=None, staged=(), baseline=None, host=None):
    """Failures with the candidate runtime that the live runtime (or the given baseline list) does not have."""
    t0 = time.time()
    live = live or RUNTIME_DEFAULT
    pkgs = pkgs or "/opt/underpants/pkgs"
    trees = app_trees(pkgs, staged)
    hm = host if host is not None else host_map()
    cand = Startability(candidate, hm)
    cfail, progs, files, cplug = set(), 0, 0, 0
    for app, kind, root in trees:
        f, p, n = cand.check_app(app, kind, root)
        cfail |= f
        progs += p
        files += n
        cplug += cand.app_plugins_missing(app, kind, root)
    if baseline is None:
        base = Startability(live, hm)
        bfail, plug_base = set(), 0
        for app, kind, root in trees:
            f, _p, _n = base.check_app(app, kind, root)
            bfail |= f
            plug_base += base.app_plugins_missing(app, kind, root)
        plug_base += base.plugins_missing() if os.path.isdir(live) else 0
        cfail |= s3_failures(trees, live, candidate)
    else:
        bfail = {tuple(x) for x in baseline}
        plug_base = None
    new = sorted(x for x in cfail if x not in bfail)
    plug = cplug + cand.plugins_missing()
    return {"veto": bool(new), "new": [list(x) for x in new], "first_app": new[0][0] if new else "",
            "apps": len(trees), "programs": progs, "files": files,
            "baseline": sorted(list(x) for x in bfail), "candidate_failures": len(cfail),
            "plugins_unchecked": (plug if plug_base is None else max(0, plug - plug_base)),
            "seconds": round(time.time() - t0, 2)}


def main(argv):
    if len(argv) >= 3 and argv[1] == "check":
        mode = "curated"
        runtime = None
        args = argv[2:]
        tree = args[0]
        for i, a in enumerate(args):
            if a == "--mode" and i + 1 < len(args):
                mode = args[i + 1]
            if a == "--runtime" and i + 1 < len(args):
                runtime = args[i + 1]
        c = Checker(tree, mode, runtime)
        res = c.run()
        print(res["verdict"])
        if res["verdict"] == "RUNTIME":
            for w in res["wrap"]:
                print(w)
        elif res["verdict"] == "REFUSE":
            for b in res["bad"][:50]:
                print("|".join(b))
            print("STAMPS|" + "|".join(res["stamps"]))
            print("RUNTIME_PRESENT|" + ("1" if c.runtime_present else "0"))
        return 0
    if len(argv) >= 3 and argv[1] == "startcheck":
        # startcheck --candidate DIR [--live DIR] [--pkgs DIR] [--staged DIR]... [--baseline FILE]   (JSON on stdout)
        args = argv[2:]
        opt = {"--candidate": None, "--live": None, "--pkgs": None, "--baseline": None}
        staged = []
        for i, a in enumerate(args):
            if a in opt and i + 1 < len(args):
                opt[a] = args[i + 1]
            elif a == "--staged" and i + 1 < len(args):
                staged.append(args[i + 1])
        if not opt["--candidate"]:
            return 2
        base = None
        if opt["--baseline"]:
            try:
                with open(opt["--baseline"], encoding="utf-8") as fh:
                    base = json.load(fh)
                if not isinstance(base, list):
                    base = None
            except (OSError, ValueError):
                base = None
        res = run_startcheck(opt["--candidate"], opt["--live"], opt["--pkgs"], staged, base)
        print(json.dumps(res))
        return 1 if res["veto"] else 0
    if len(argv) >= 4 and argv[1] == "sentence":
        # sentence APP VERSION < facts on stdin (the REFUSE lines)
        bad, stamps, rtp = [], [], True
        for line in sys.stdin.read().splitlines():
            if line.startswith("STAMPS|"):
                stamps = [x for x in line.split("|")[1:] if x]
            elif line.startswith("RUNTIME_PRESENT|"):
                rtp = line.endswith("|1")
            elif line.count("|") == 4:
                bad.append(tuple(line.split("|")))
        if not bad:
            return 1
        print(refusal_sentence(argv[2], argv[3], {"bad": bad}, rtp))
        return 0
    if len(argv) >= 4 and argv[1] == "hold":
        # hold PID VERSION < facts on stdin
        bad, stamps = [], []
        for line in sys.stdin.read().splitlines():
            if line.startswith("STAMPS|"):
                stamps = [x for x in line.split("|")[1:] if x]
            elif line.count("|") == 4:
                bad.append(tuple(line.split("|")))
        if bad:
            record_hold(argv[2], argv[3], {"bad": bad, "stamps": stamps}, refusal_sentence(argv[2], argv[3], {"bad": bad}))
        return 0
    if len(argv) >= 4 and argv[1] == "held":
        return 0 if is_held(argv[2], argv[3]) else 1
    if len(argv) >= 3 and argv[1] == "clear":
        clear_hold(argv[2])
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
