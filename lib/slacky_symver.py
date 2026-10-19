#!/usr/bin/env python3
"""6A-327: symbol-version headroom guard (pure Python, no readelf needed).

A program built against a newer library (for example OpenRGB asking for Qt_6.12 while Slackware has Qt 6.11) dies at start-up
with "version `Qt_6.12' not found". This module reads, for every 64-bit ELF of a staging tree, the versions it needs
(DT_VERNEED) and compares them with the versions the library that will really be loaded defines (DT_VERDEF).

Library search order (the order the real loader and the launcher wrapper use):
  mode "curated": files of the package itself, then the host; when the host cannot satisfy it, the Underpants runtime is tried
                  (verdict RUNTIME = install with a launcher wrapper that puts the runtime first), else REFUSE.
  mode "app":     files of the app itself, then the Underpants runtime pool, then the host (gnomes launcher order).
Environment overrides for tests: SLACKY_SYMVER_HOST_DIRS (colon list, replaces ldconfig), SLACKY_SYMVER_RUNTIME,
SLACKY_SYMVER_CACHE (hold-file directory).

CLI:  slacky_symver.py check TREE --mode curated|app [--runtime DIR]
        prints HOST | RUNTIME | REFUSE | SKIP on the first line; RUNTIME is followed by one tree-relative path per ELF that must
        be wrapped; REFUSE is followed by the missing-version facts "<file>|<soname>|<version>|<lib path>|<where>" per line.
      slacky_symver.py hold PID VERSION SONAME LIBVERSION [STAMPS...]   remember a refused version
      slacky_symver.py held PID VERSION     exit 0 when that version is still waiting (the libraries are unchanged)
"""
import json
import os
import struct
import subprocess
import sys
import time

RUNTIME_DEFAULT = "/opt/underpants/runtime"
EXTRA_DIRS = ["/usr/lib64/libproxy", "/usr/lib64/pulseaudio", "/usr/lib64/pipewire-0.3", "/usr/lib64/samba"]
HOST_FALLBACK = ["/lib64", "/usr/lib64"]
WRAPPABLE = ("usr/bin", "usr/sbin", "bin", "sbin", "usr/local/bin")

DT_NEEDED, DT_STRTAB, DT_VERDEF, DT_VERDEFNUM, DT_VERNEED, DT_VERNEEDNUM = 1, 5, 0x6ffffffc, 0x6ffffffd, 0x6ffffffe, 0x6fffffff
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
        try:
            with open(path, "rb") as fh:
                self.data = fh.read()
        except OSError:
            return
        d = self.data
        if len(d) < 64 or d[:4] != b"\x7fELF" or d[4] != 2 or d[5] != 1:
            return
        try:
            self._parse()
        except (struct.error, IndexError, ValueError):
            self.ok = False

    def _parse(self):
        d = self.data
        self.etype = struct.unpack_from("<H", d, 16)[0]
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
        for o in range(dyn[0], dyn[0] + dyn[1], 16):
            tag, val = struct.unpack_from("<qQ", d, o)
            if tag == 0:
                break
            if tag == DT_NEEDED:
                needed_offs.append(val)
            else:
                tags[tag] = val
        if DT_STRTAB not in tags:
            return
        strtab = off(tags[DT_STRTAB])

        def s(o):
            e = d.index(b"\0", strtab + o)
            return d[strtab + o:e].decode("utf-8", "replace")

        self.needed = [s(v) for v in needed_offs]
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
    env = os.environ.get("SLACKY_SYMVER_HOST_DIRS")
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
        self.runtime = runtime or os.environ.get("SLACKY_SYMVER_RUNTIME") or RUNTIME_DEFAULT
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
    env = os.environ.get("SLACKY_SYMVER_CACHE")
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
