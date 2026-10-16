#!/usr/bin/env python3
"""slacky_heal.py - detect and advise (tasks 9B-9C). Read only: never repairs, never asks for sudo, writes no state.

  check                    audit all installed packages; silent when clean; exit 51 when damage was found
  hold NAME [NAME ...]     type-damage check for these base names only (the upgrade set); prints the hold sentence and
                           exits 30 when a package has a folder replaced by a link, else silent, exit 0
  post                     the one sentence after an update when damage exists (silent when clean)

Hidden test option: --root DIR (everything below DIR).
Spec: docs/healing_legacy_9A-9D.md. Legacy DETECTS and ADVISES; the person runs `slackpkg reinstall <names>` himself.
"""
import os
import re
import sys
from concurrent.futures import ThreadPoolExecutor

ROOT = ""
SKIP_PREFIX = ("install/", "dev/", "tmp/", "boot/", "lib64/incoming/", "lib/incoming/")
NEVER_EXACT = ("etc/passwd", "etc/shadow", "etc/group", "etc/gshadow", "etc/passwd-", "etc/shadow-", "etc/group-",
               "etc/gshadow-", "etc/security", "etc/pam.d", "root", "home", "boot", "efi", "dev", "etc/limine",
               "var/log/packages", "var/lib/pkgtools", "opt/underpants/runtime", "lib/modules", "lib/firmware",
               "usr/lib/firmware")
NEVER_PREFIX = ("etc/sudoers", "etc/ssh/ssh_host_", "var/lib/slacky")
TOOLS = ("upgradepkg", "installpkg", "removepkg", "explodepkg", "tar", "xz", "gpgv", "slackpkg")
TOOL_DIRS = ("bin/", "sbin/", "usr/bin/", "usr/sbin/")
S_TOOLS = ("The tools needed to install packages are damaged themselves, so nothing is repaired automatically; "
           "restore the safety snapshot or reinstall them from the Slackware installer.")
OCT = re.compile(rb"\\([0-7]{3})")


def P(p):
    return ROOT + p


def decode(name):
    """octal escapes (\\305\\221) in file names -> real bytes, as a str that keeps undecodable bytes"""
    b = OCT.sub(lambda m: bytes([int(m.group(1), 8) & 0xFF]), name.encode("utf-8", "surrogateescape"))
    return b.decode("utf-8", "surrogateescape")


def is_never(path):
    p = path.rstrip("/")
    if p.endswith(".new"):
        return True
    for n in NEVER_EXACT:
        if p == n or p.startswith(n + "/"):
            return True
    return p.startswith(NEVER_PREFIX)


def split_full(full):
    parts = full.rsplit("-", 3)
    if len(parts) != 4 or not parts[0]:
        return None
    return parts


def is_official(full):
    sp = split_full(full)
    if not sp:
        return False
    name, build = sp[0], sp[3]
    if "compat32" in full or name.startswith(("underpants-", "cachyos-")):
        return False
    return build.isdigit()


def intended_links(full):
    """(dir, name) pairs the package's own install script replaces by a link on purpose"""
    out = set()
    for rel in ("var/lib/pkgtools/scripts/", "var/log/scripts/"):
        try:
            with open(P("/" + rel + full), "r", encoding="utf-8", errors="replace") as f:
                text = f.read()
        except OSError:
            continue
        for m in re.finditer(r"\(\s*cd\s+(\S+)\s*;\s*rm\s+-rf\s+(\S+)\s*\)", text):
            d, n = m.group(1), m.group(2)
            d = d[2:] if d.startswith("./") else d
            d = d.lstrip("/")
            if re.search(r"\bln\s+-[a-z]*s[a-z]*\s+\S+\s+%s\b" % re.escape(n), text):
                out.add(d.rstrip("/") + "/" + n)
    return out


def audit_one(full):
    """-> (missing [paths], linked [(path, target)]) for one package"""
    missing, linked = [], []
    try:
        with open(P("/var/log/packages/" + full), "r", encoding="utf-8", errors="surrogateescape") as f:
            lines = f.read().splitlines()
    except OSError:
        return missing, linked
    try:
        i = lines.index("FILE LIST:") + 1
    except ValueError:
        return missing, linked
    intended = None
    for raw in lines[i:]:
        e = raw.strip()
        if not e or e == "./":
            continue
        if e.startswith("./"):
            e = e[2:]
        e = decode(e)
        if e.endswith(".new") or e.startswith(SKIP_PREFIX):
            continue
        path = P("/" + e.rstrip("/"))
        try:
            if e.endswith("/"):
                if os.path.islink(path):
                    if intended is None:
                        intended = intended_links(full)
                    if e.rstrip("/") in intended:
                        continue
                    linked.append((e.rstrip("/"), os.readlink(path)))
            else:
                os.lstat(path)
        except FileNotFoundError:
            if not e.endswith("/"):
                missing.append(e)
        except OSError:
            pass
    return missing, linked


def audit(only_names=None):
    """-> {full: (missing, linked)} for damaged packages only"""
    try:
        names = [n for n in os.listdir(P("/var/log/packages")) if not n.startswith(".")]
    except OSError:
        return {}
    if only_names is not None:
        names = [n for n in names if (split_full(n) or ("",))[0].lower() in only_names]
    names.sort()
    res = {}
    with ThreadPoolExecutor(max_workers=8) as ex:
        for full, (mi, li) in zip(names, ex.map(audit_one, names)):
            if mi or li:
                res[full] = (mi, li)
    candidates = {p for (_, li) in res.values() for (p, _) in li}
    if candidates:
        designed = designed_links(candidates)
        for full in list(res):
            mi, li = res[full]
            li = [(p, t) for (p, t) in li if p not in designed and not own_bridge(full, t)]
            if mi or li:
                res[full] = (mi, li)
            else:
                del res[full]
    return res


# pkgtools moved these to /var/lib/pkgtools and leaves links behind (its doinst loop, not a literal ln line)
PKGTOOLS_LINKS = ("var/log/setup", "var/log/packages", "var/log/scripts")


def own_bridge(full, target):
    """our own package links a folder to a host folder that the same package ships (the OBS bundle bridge)"""
    if not full.startswith(("underpants-", "cachyos-")) or not target.startswith("/"):
        return False
    want = target.strip("/") + "/"
    try:
        with open(P("/var/log/packages/" + full), "r", encoding="utf-8", errors="surrogateescape") as f:
            return any(raw.rstrip("\n") == want for raw in f)
    except OSError:
        return False


LN_LINE = re.compile(r"\(\s*cd\s+(\S+)\s*;\s*ln\s+-[a-z]*s[a-z]*\s+\S+\s+(\S+)\s*\)")


def designed_links(candidates):
    """6A-174: folder paths that are links ON PURPOSE because ANOTHER package makes them: its install script runs
    `( cd D ; ln -sf T N )` for that path (aaa_base: var/run, usr/share/doc, usr/share/man), or its file list has the
    path as a plain entry, not a folder (breeze-icons' 16@2x links that easyeffects lists as folders)."""
    found = {p for p in candidates if p in PKGTOOLS_LINKS}
    for rel in ("/var/lib/pkgtools/scripts", "/var/log/scripts"):
        try:
            entries = os.listdir(P(rel))
        except OSError:
            continue
        for n in entries:
            try:
                with open(P(rel + "/" + n), "r", encoding="utf-8", errors="replace") as f:
                    text = f.read()
            except OSError:
                continue
            if " ln " not in text:
                continue
            for m in LN_LINE.finditer(text):
                d = m.group(1)
                d = (d[2:] if d.startswith("./") else d).strip("/")
                path = (d + "/" + m.group(2)) if d else m.group(2)
                if path in candidates:
                    found.add(path)
        break
    rest = candidates - found
    if rest:
        try:
            names = os.listdir(P("/var/log/packages"))
        except OSError:
            names = []
        for n in names:
            try:
                with open(P("/var/log/packages/" + n), "r", encoding="utf-8", errors="surrogateescape") as f:
                    for raw in f:
                        e = raw.rstrip("\n")
                        if e.startswith("./"):
                            e = e[2:]
                        if e in rest:
                            found.add(e)
            except OSError:
                continue
    return found


def pkglist_versions():
    """{base name: set of full names on the server}, or None when the list is missing"""
    p = P("/var/lib/slackpkg/pkglist")
    try:
        with open(p, "r", encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        return None
    out = {}
    for l in lines:
        t = l.split()
        if len(t) >= 5:
            out.setdefault(t[1], set()).add("%s-%s-%s-%s" % (t[1], t[2], t[3], t[4]))
    return out


def report(res):
    """prints the sentences; returns the exit code"""
    if not res:
        return 0
    # install tools damaged: only that sentence
    for full, (mi, li) in res.items():
        for m in mi:
            if m.startswith(TOOL_DIRS) and os.path.basename(m) in TOOLS:
                print(S_TOOLS)
                return 51
    if len(res) > 50:
        print("%d packages are damaged, which is too much for an automatic repair; restore the latest safety snapshot instead." % len(res))
        return 51
    server = pkglist_versions()
    cmd = set()
    lines = []
    nodata = False
    for full in sorted(res):
        mi, li = res[full]
        sp = split_full(full)
        base = sp[0] if sp else full
        example = (mi or [p for p, _ in li])[0]
        damaged = list(mi) + [p for p, _ in li]
        if any(is_never(d) for d in damaged):
            lines.append("%s: /%s is an account, security, boot or personal file, and a repair never touches those." % (base, next(d for d in damaged if is_never(d))))
            continue
        if not is_official(full):
            lines.append("%s is not an official Slackware package; rebuild or reinstall it with the tool you used to install it." % base)
            continue
        if mi:
            lines.append("%s is missing %d of its files (for example /%s), so some programs may not start." % (base, len(mi), mi[0]))
        for path, target in li:
            lines.append("/%s should be a normal folder of %s but is a link to %s, so a reinstall of %s can delete files." % (path, base, target, base))
        if server is None:
            nodata = True
        elif base in server and full not in server[base]:
            mirror = sorted(server[base])[0]
            lines = [l for l in lines if not l.startswith(base + " is missing") and ("of %s but is a link" % base) not in l]
            lines.append("The server now has %s instead of %s, so the old version cannot be restored; the next full update brings the files back." % (mirror, full))
            continue
        cmd.add(base)
    for l in lines:
        print(l)
    if nodata:
        print("The list of packages on the Slackware server is not available here (run slackpkg update), so nothing can be restored automatically.")
    if cmd:
        print("To restore them yourself: slackpkg reinstall " + " ".join(sorted(cmd)))
    return 51


def status_names():
    """base names of the Slackware / slackpkg+ updates the last check found (status.json, normal user is enough)"""
    import json
    cands = []
    xdg = os.environ.get("XDG_CACHE_HOME")
    cands.append(os.path.join(xdg, "slacky-update", "status.json") if xdg else os.path.expanduser("~/.cache/slacky-update/status.json"))
    cands.append("/var/cache/slacky-update/status.json")
    best, best_ts = {}, -1.0
    for c in cands:
        try:
            with open(c, "r", encoding="utf-8") as f:
                d = json.load(f)
            ts = float(d.get("last_check_ts", os.path.getmtime(c)))
        except (OSError, ValueError, TypeError):
            continue
        if ts > best_ts:
            best, best_ts = d, ts
    names = set()
    for key in ("slackware_updates", "slackpkgplus_updates"):
        for ent in best.get(key, []) or []:
            if not isinstance(ent, str) or not ent.strip():
                continue
            tok = ent.split()[0].rsplit("/", 1)[-1]
            tok = re.sub(r"\.(t[xgb]z|tlz)$", "", tok)
            sp = split_full(tok)
            if sp:
                names.add(sp[0].lower())
    return names


def hold(names):
    if names == ["--from-status"]:
        names = sorted(status_names())
        if not names:
            return 0
    res = audit({n.lower() for n in names})
    held = []
    for full, (mi, li) in sorted(res.items()):
        if li:
            held.append((split_full(full)[0] if split_full(full) else full, li[0][0]))
    if not held:
        return 0
    pkg, path = held[0]
    s = ("%s is not upgraded now: the folder /%s was replaced by a link and the upgrade could lose files. "
         "Run `slackpkg reinstall %s` first, then update again. Nothing was changed." % (pkg, path, pkg))
    if len(held) > 1:
        s += " %d more held for the same reason." % (len(held) - 1)
    print(s)
    return 30


def post():
    if audit():
        print("Some installed packages are damaged; run `slacky-update --heal-check` to see what can be restored. Nothing was changed.")
    return 0


def main(argv):
    global ROOT
    a = list(argv)
    if "--root" in a:
        i = a.index("--root")
        ROOT = a[i + 1].rstrip("/")
        del a[i:i + 2]
    if not a:
        print("usage: slacky_heal.py check | hold NAME... | post")
        return 2
    if a[0] == "check":
        return report(audit())
    if a[0] == "hold":
        return hold(a[1:])
    if a[0] == "post":
        return post()
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
