#!/usr/bin/env python3
"""slacky_config.py - config base store (capture) and consent-only .new handling (tasks 8A-8C).

Shared store format: docs/config_store_spec.md (format 1). Run with `python3 -I`, as root for the real system.

  capture --before FILE     after the Slackware base step: store the stock text of the etc/*.new files of every package
                            that is new or changed since FILE (one installed package name per line)
  capture --waiting         before the upgrade: store the stock text of .new files that already wait
  reconcile [--non-interactive]
                            list the waiting .new files; with a typed "y" handle ONLY the exact cases (never edited ->
                            replace, upstream unchanged -> drop the .new, identical -> drop the .new, missing -> add).
                            Without a person at a terminal (-y, no TTY) nothing is changed and one sentence is printed.

Hidden test options: --root DIR (everything below DIR), --owner-uid N (uid that must own the store; 0 on a real system).
Nothing here merges, and nothing overwrites a file the person changed.
"""
import fcntl
import hashlib
import json
import os
import re
import stat
import sys
import time
import uuid
from datetime import datetime

FORMAT = 1
MAX_OBJECT = 2 * 1024 * 1024
MAX_INDEX = 16 * 1024 * 1024
MAX_OBJECTS = 20000
LATE_SLACK = 120
NEVER = ("etc/passwd", "etc/group", "etc/shadow", "etc/gshadow")
WRITER = "slacky-update (legacy)"

ROOT = ""          # prefix for the fake-root tests; "" on a real system
OWNER_UID = 0


def P(p):
    return ROOT + p


def now():
    return datetime.now().astimezone().isoformat()


def sha256_hex(b):
    return hashlib.sha256(b).hexdigest()


def valid_key(k):
    return (k.startswith("etc/") and not k.endswith(".new") and not k.endswith("/") and "\0" not in k
            and all(p not in ("", ".", "..") for p in k.split("/")))


class StoreError(Exception):
    pass


# ---------------------------------------------------------------- store (format 1)
class Store:
    def __init__(self, d, owner):
        self.dir = d
        self.owner = owner

    def _check_dir(self, p):
        st = os.lstat(p)
        if stat.S_ISLNK(st.st_mode):
            raise StoreError("%s is a symbolic link" % p)
        if not stat.S_ISDIR(st.st_mode):
            raise StoreError("%s is not a folder" % p)
        if st.st_uid != self.owner:
            raise StoreError("%s has the wrong owner" % p)
        if st.st_mode & 0o077:
            raise StoreError("%s is open to other users" % p)

    def _check_stat(self, st, p):
        if not stat.S_ISREG(st.st_mode):
            raise StoreError("%s is not a plain file" % p)
        if st.st_uid != self.owner:
            raise StoreError("%s has the wrong owner" % p)
        if st.st_mode & 0o077:
            raise StoreError("%s is open to other users" % p)

    def _make_dir(self, p):
        try:
            os.lstat(p)
        except FileNotFoundError:
            os.mkdir(p, 0o700)
            os.chmod(p, 0o700)
        self._check_dir(p)

    def ensure_layout(self):
        parent = os.path.dirname(self.dir)
        if os.path.islink(parent) or not os.path.isdir(parent):
            raise StoreError("the parent folder is missing or a symbolic link")
        self._make_dir(self.dir)
        self._make_dir(os.path.join(self.dir, "objects"))

    def _read_checked(self, p, cap):
        fd = os.open(p, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
        try:
            st = os.fstat(fd)
            self._check_stat(st, p)
            if st.st_size > cap:
                raise StoreError("%s is too big" % p)
            with os.fdopen(fd, "rb", closefd=False) as f:
                return f.read()
        finally:
            os.close(fd)

    def read_index(self):
        """dict, or None when there is no index yet. Raises StoreError when the store is untrusted or damaged."""
        self._check_dir(self.dir)
        p = os.path.join(self.dir, "index.json")
        try:
            raw = self._read_checked(p, MAX_INDEX)
        except FileNotFoundError:
            return None
        except OSError as e:
            raise StoreError(str(e))
        try:
            idx = json.loads(raw.decode("utf-8"))
        except ValueError:
            raise StoreError("the index is damaged")
        if not isinstance(idx, dict) or not isinstance(idx.get("files"), dict):
            raise StoreError("the index is damaged")
        if int(idx.get("format", 0)) > FORMAT:
            raise StoreError("the index has a newer format")
        return idx

    def read_object(self, sha):
        if not re.fullmatch(r"[0-9a-f]{64}", sha or ""):
            raise StoreError("bad object name")
        try:
            data = self._read_checked(os.path.join(self.dir, "objects", sha), MAX_OBJECT)
        except OSError as e:
            raise StoreError(str(e))
        if sha256_hex(data) != sha:
            raise StoreError("object %s is damaged" % sha)
        return data

    def _atomic_write(self, target, data):
        parent = os.path.dirname(target)
        tmp = os.path.join(parent, ".tmp-%d-%d" % (os.getpid(), time.time_ns()))
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
        try:
            with os.fdopen(fd, "wb") as f:
                f.write(data)
                f.flush()
                os.fsync(f.fileno())
            os.rename(tmp, target)
        except BaseException:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise
        try:
            dfd = os.open(parent, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(dfd)
            finally:
                os.close(dfd)
        except OSError:
            pass

    def put_object(self, data):
        if len(data) > MAX_OBJECT:
            raise StoreError("a config file is over 2 MiB")
        self.ensure_layout()
        sha = sha256_hex(data)
        p = os.path.join(self.dir, "objects", sha)
        if os.path.lexists(p):
            self.read_object(sha)       # re-verified, not rewritten
            return sha
        if len(os.listdir(os.path.join(self.dir, "objects"))) >= MAX_OBJECTS:
            raise StoreError("too many objects")
        self._atomic_write(p, data)
        return sha

    def update_index(self, fn):
        """Read-modify-write the index under an exclusive flock on `lock`. A missing index starts empty."""
        self.ensure_layout()
        lp = os.path.join(self.dir, "lock")
        fd = os.open(lp, os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
        try:
            self._check_stat(os.fstat(fd), lp)
            fcntl.flock(fd, fcntl.LOCK_EX)
            idx = self.read_index()
            if idx is None:
                idx = {"format": FORMAT, "writer": WRITER, "updated_at": now(), "files": {}}
            out = fn(idx)
            idx["format"] = FORMAT
            idx["writer"] = WRITER
            idx["updated_at"] = now()
            idx["files"] = dict(sorted(idx["files"].items()))
            raw = (json.dumps(idx, indent=2, ensure_ascii=False)).encode("utf-8")
            if len(raw) > MAX_INDEX:
                raise StoreError("the index is too big")
            self._atomic_write(os.path.join(self.dir, "index.json"), raw)
            return out
        finally:
            os.close(fd)

    def write_manifest(self, txid, tm, entries):
        d = os.path.join(self.dir, "undo")
        self._make_dir(d)
        d = os.path.join(d, txid)
        self._make_dir(d)
        m = {"format": 1, "txid": txid, "time": tm, "entries": entries}
        self._atomic_write(os.path.join(d, "manifest.json"), json.dumps(m, indent=2, ensure_ascii=False).encode("utf-8"))


def system_store():
    return Store(P("/var/lib/slacky-config"), OWNER_UID)


# ---------------------------------------------------------------- reading files
def read_plain(path):
    """(bytes, stat) of a plain regular file without following a final link; raises OSError/ValueError with a reason."""
    st = os.lstat(path)
    if stat.S_ISLNK(st.st_mode):
        raise ValueError("is a link")
    if not stat.S_ISREG(st.st_mode):
        raise ValueError("is not a plain file")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    try:
        fst = os.fstat(fd)
        if fst.st_size > MAX_OBJECT:
            raise ValueError("is over 2 MiB")
        with os.fdopen(fd, "rb", closefd=False) as f:
            return f.read(), fst
    finally:
        os.close(fd)


def split_pkg(full):
    parts = full.rsplit("-", 3)
    if len(parts) != 4 or not parts[0]:
        return None
    return parts[0], "%s-%s-%s" % (parts[1], parts[2], parts[3])


def pkgdb_names():
    try:
        return {n for n in os.listdir(P("/var/log/packages")) if not n.startswith(".")}
    except OSError:
        return set()


def read_pkgdb():
    """packages that list etc/...new entries: [(full, name, version, installed_mtime, [etc/X.new, ...])]"""
    d = P("/var/log/packages")
    out = []
    try:
        names = sorted(os.listdir(d))
    except OSError:
        return out
    for full in names:
        if full.startswith("."):
            continue
        sp = split_pkg(full)
        if not sp:
            continue
        p = os.path.join(d, full)
        try:
            st = os.stat(p)
            if not stat.S_ISREG(st.st_mode) or st.st_size > 8 * 1024 * 1024:
                continue
            with open(p, "r", encoding="utf-8", errors="replace") as f:
                text = f.read()
        except OSError:
            continue
        in_list = False
        dn = []
        for line in text.splitlines():
            if not in_list:
                in_list = line.startswith("FILE LIST:")
                continue
            l = line.rstrip()
            if l.startswith("./"):
                l = l[2:]
            if l.startswith("etc/") and l.endswith(".new"):
                dn.append(l)
        if dn:
            out.append((full, sp[0], sp[1], st.st_mtime, dn))
    return out


# ---------------------------------------------------------------- 8A capture
def capture(pkgs, only_waiting):
    """Returns (recorded keys, skipped [(key, why)], error or None)."""
    items = []
    skipped = []
    for full, name, ver, installed, dotnew in pkgs:
        for dn in dotnew:
            key = dn[:-4]
            if not valid_key(key) or key in NEVER:
                continue
            newp, livep = P("/" + dn), P("/" + key)
            new_exists = os.path.lexists(newp)
            live_sha = None
            try:
                live_sha = sha256_hex(read_plain(livep)[0])
            except (OSError, ValueError):
                pass
            if new_exists:
                try:
                    data, st = read_plain(newp)
                except (OSError, ValueError) as e:
                    skipped.append((key, str(e)))
                    continue
                items.append(dict(key=key, pkg=name, ver=ver, data=data, st=st, live_sha=live_sha, from_live=False, late=False))
            elif not only_waiting:
                try:
                    data, st = read_plain(livep)
                except (OSError, ValueError) as e:
                    skipped.append((key, str(e)))
                    continue
                late = st.st_mtime > installed + LATE_SLACK
                items.append(dict(key=key, pkg=name, ver=ver, data=data, st=st, live_sha=None, from_live=True, late=late))
    if not items:
        return [], skipped, None
    store = system_store()
    try:
        for it in items:
            store.put_object(it["data"])
        stamp = now()

        def upd(idx):
            files = idx["files"]
            for it in items:
                theirs = sha256_hex(it["data"])
                prev = files.get(it["key"])
                deriv = None
                if it["from_live"]:
                    base, src = (None, None) if it["late"] else (theirs, "capture")
                elif prev and it["live_sha"] is not None and it["live_sha"] == prev.get("theirs"):
                    if prev.get("base") != prev.get("theirs"):
                        deriv = "live equals the earlier stock text"
                    base, src = prev.get("theirs"), "capture"
                elif prev and prev.get("base") is not None:
                    deriv = prev.get("derivation")
                    base, src = prev.get("base"), prev.get("base_source")
                else:
                    base, src = None, None
                st = it["st"]
                ent = dict(prev) if prev else {}
                ent.update({
                    "pkg": it["pkg"], "pkg_version": it["ver"], "theirs": theirs, "base": base, "base_source": src,
                    "mode": "%04o" % (st.st_mode & 0o7777), "uid": st.st_uid, "gid": st.st_gid,
                    "captured_at": stamp, "captured_from": "live" if it["from_live"] else "dotnew", "late": it["late"],
                })
                ent.pop("derivation", None)
                if deriv:
                    ent["derivation"] = deriv
                # field order of format 1
                order = ["pkg", "pkg_version", "theirs", "base", "base_source", "mode", "uid", "gid", "captured_at",
                         "captured_from", "late", "derivation"]
                files[it["key"]] = {**{k: ent[k] for k in order if k in ent}, **{k: v for k, v in ent.items() if k not in order}}

        store.update_index(upd)
    except (StoreError, OSError) as e:
        return [], skipped, str(e)
    return [it["key"] for it in items], skipped, None


# ---------------------------------------------------------------- 8B/8C reconcile
NEVER_AUTO_PREFIX = ("etc/pam.d/", "etc/security/", "etc/ssh/ssh_host_")
NEVER_AUTO_EXACT = ("etc/fstab", "etc/crypttab", "etc/inittab", "etc/mtab", "etc/rc.d/rc.S", "etc/rc.d/rc.M", "etc/lilo.conf")
PIN_RE = re.compile(rb"^\s*(#|;|//|\")\s*slacky:\s*keep\s*$", re.M)


def never_auto(key):
    return (key in NEVER or key.startswith(NEVER_AUTO_PREFIX) or key in NEVER_AUTO_EXACT or key.startswith("etc/sudoers"))


def in_include_dir(key):
    comps = key.split("/")
    return len(comps) > 2 and any(c.endswith(".d") or c.startswith("cron.") for c in comps[1:-1])


def find_waiting():
    out = []
    top = P("/etc")
    for dp, dns, fns in os.walk(top, followlinks=False):
        dns[:] = [d for d in dns if not os.path.islink(os.path.join(dp, d))]
        for f in fns:
            if f.endswith(".new"):
                full = os.path.join(dp, f)
                if os.path.islink(full) or not os.path.isfile(full):
                    continue
                key = full[len(ROOT):].lstrip("/")[:-4]
                if valid_key(key) and key not in NEVER:
                    out.append(key)
    return sorted(out)


def exact_base(idx, store, key):
    """sha of the exact stock base of this file, or None (weak, missing or damaged bases never count)."""
    ent = (idx or {}).get("files", {}).get(key)
    if not ent or not ent.get("base") or ent.get("base_source") != "capture" or ent.get("late"):
        return None
    try:
        store.read_object(ent["base"])
    except StoreError:
        return None
    return ent["base"]


def classify(key, idx, store):
    """-> (action, reason). action: install | replace | drop_same | drop_old | keep"""
    livep, newp = P("/" + key), P("/" + key + ".new")
    if never_auto(key):
        return "keep", "careful"
    try:
        tdata, tst = read_plain(newp)
    except (OSError, ValueError):
        return "keep", "careful"
    if os.path.realpath(os.path.dirname(livep)) != os.path.dirname(livep):
        return "keep", "careful"
    if not os.path.lexists(livep):
        if tst.st_mode & 0o022:
            return "keep", "careful"
        return "install", "missing"
    try:
        odata, ost = read_plain(livep)
    except (OSError, ValueError):
        return "keep", "careful"
    if PIN_RE.search(odata):
        return "keep", "pinned"
    if odata == tdata:
        return "drop_same", "identical"
    base = exact_base(idx, store, key)
    if base is None:
        return "keep", "edited_or_unknown"
    if sha256_hex(odata) == base:
        return "replace", "never_edited"
    if sha256_hex(tdata) == base:
        return "drop_old", "upstream_same"
    return "keep", "edited"


def create_with(path, data, mode, uid, gid):
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    try:
        _write_all(fd, data)
        st = os.fstat(fd)
        if st.st_uid != uid or st.st_gid != gid:
            os.fchown(fd, uid, gid)
        os.fchmod(fd, mode)
        os.fsync(fd)
    finally:
        os.close(fd)


def _write_all(fd, data):
    mv = memoryview(data)
    while mv:
        n = os.write(fd, mv)
        mv = mv[n:]


def apply_items(items, idx, store):
    """items: [(key, action)]. Journal first, then the change per file. Returns (done keys, failed keys)."""
    txid = "%s-%s" % (time.strftime("%Y%m%dT%H%M%S"), uuid.uuid4().hex[:4])
    tm = now()
    entries = []
    done = []
    failed = []
    advances = {}    # key -> (new_base_sha, derivation)
    undo = []        # (target, old bytes, old attrs) for a rollback of replaced files
    unlink_new = []
    for key, action in items:
        livep, newp = P("/" + key), P("/" + key + ".new")
        try:
            # fresh look right before the change (the person may have edited meanwhile)
            if classify(key, idx, store)[0] != action:
                failed.append(key)
                continue
            tdata, tst = read_plain(newp)
            tsha = store.put_object(tdata)
            entry = {"txid": txid, "path": key, "time": tm}
            if action == "install":
                attrs = (tst.st_mode & 0o777, OWNER_UID if ROOT else 0, OWNER_UID if ROOT else 0)
                entry.update(old_sha=None, new_sha=tsha, reason="replace", action="replace")
            elif action == "replace":
                odata, ost = read_plain(livep)
                osha = store.put_object(odata)
                attrs = (ost.st_mode & 0o7777, ost.st_uid, ost.st_gid)
                entry.update(old_sha=osha, new_sha=tsha, reason="replace", action="replace")
            else:
                odata, ost = read_plain(livep)
                osha = store.put_object(odata)
                attrs = (ost.st_mode & 0o7777, ost.st_uid, ost.st_gid)
                entry.update(old_sha=None, new_sha=osha, reason="drop", action="drop")
            entry["attrs"] = {"mode": attrs[0], "uid": attrs[1], "gid": attrs[2]}
            entries.append(entry)
            store.write_manifest(txid, tm, entries)
            if action in ("install", "replace"):
                tmp = os.path.join(os.path.dirname(livep), ".%s.slacky-tmp" % os.path.basename(livep))
                if action == "replace":
                    if not in_include_dir(key) and not os.path.lexists(livep + ".orig"):
                        create_with(livep + ".orig", odata, attrs[0], attrs[1], attrs[2])
                create_with(tmp, tdata, attrs[0], attrs[1], attrs[2])
                with open(tmp, "rb") as f:
                    if f.read() != tdata:
                        os.unlink(tmp)
                        raise OSError("write check failed")
                if action == "install":
                    os.link(tmp, livep)          # never replaces a file that appeared meanwhile
                    os.unlink(tmp)
                else:
                    os.rename(tmp, livep)
                    undo.append((livep, odata, attrs))
                advances[key] = (tsha, "replace")
            elif action == "drop_same":
                advances[key] = (tsha, "identical")
            unlink_new.append(newp)
            done.append(key)
        except (OSError, ValueError, StoreError):
            entries[:] = [e for e in entries if e["path"] != key]
            try:
                store.write_manifest(txid, tm, entries)
            except (OSError, StoreError):
                pass
            failed.append(key)
    # the index moves in the same change set; if it cannot, the files are put back
    if advances:
        def upd(i):
            for k, (sha, d) in advances.items():
                e = i["files"].get(k)
                if e is not None:
                    e["base"], e["base_source"], e["late"], e["derivation"] = sha, "capture", False, d
        try:
            store.update_index(upd)
        except (StoreError, OSError):
            for target, old, attrs in undo:
                try:
                    t2 = os.path.join(os.path.dirname(target), ".%s.slacky-undo" % os.path.basename(target))
                    create_with(t2, old, *attrs)
                    os.rename(t2, target)
                except OSError:
                    pass
            return [], [k for k, _ in items]
    for np in unlink_new:
        try:
            os.unlink(np)
        except OSError:
            pass
    return done, failed


def ask(prompt):
    try:
        sys.stdout.write(prompt)
        sys.stdout.flush()
        return input().strip().lower()
    except (EOFError, KeyboardInterrupt):
        return ""


def waiting_sentence(n):
    if n == 1:
        return "1 configuration file is waiting for you"
    return "%d configuration files are waiting for you" % n


REASON_TEXT = {
    "missing": "Slackware ships a file you do not have yet, so it is added",
    "identical": "the waiting copy is the same as your file, so it is simply removed",
    "never_edited": "you never changed this file, so the new version replaces it",
    "upstream_same": "Slackware did not change this file, so your version stays and the waiting copy is removed",
}


def reconcile(interactive):
    keys = find_waiting()
    if not keys:
        return 0
    if not interactive:
        print(waiting_sentence(len(keys)))      # -y, no terminal, NON_INTERACTIVE: nothing is changed
        return 0
    store = system_store()
    idx = None
    store_ok = True
    try:
        idx = store.read_index()
    except (StoreError, OSError):
        store_ok = False
    plan = [(k,) + classify(k, idx, store) for k in keys]
    todo = [(k, a, r) for k, a, r in plan if a != "keep"]
    kept = [k for k, a, r in plan if a == "keep"]
    if todo and store_ok:
        try:
            store.ensure_layout()
        except (StoreError, OSError):
            store_ok = False
    if todo and not store_ok:
        print("The record of earlier Slackware file versions is missing or unsafe, so no configuration file was changed.")
        print(waiting_sentence(len(keys)))
        return 0
    if todo:
        print("%d configuration file%s can be handled safely:" % (len(todo), "" if len(todo) == 1 else "s"))
        for k, a, r in todo[:20]:
            print("  /%s: %s." % (k, REASON_TEXT[r]))
        if len(todo) > 20:
            print("  ... and %d more." % (len(todo) - 20))
        ans = ask("Do this now? A copy of every replaced file is kept. [y/N] ")
        if ans in ("y", "yes"):
            done, failed = apply_items([(k, a) for k, a, r in todo], idx, store)
            kept += failed
        else:
            kept += [k for k, a, r in todo]
    if kept:
        print("%s; your files are kept as they are and the new versions wait next to them as .new files."
              % waiting_sentence(len(kept)))
    return 0


# ---------------------------------------------------------------- main
def main(argv):
    global ROOT, OWNER_UID
    args = list(argv)
    non_inter = False
    test_inter = False
    before = None
    mode = None
    i = 0
    rest = []
    while i < len(args):
        a = args[i]
        if a == "--root":
            ROOT = args[i + 1].rstrip("/")
            i += 2
            continue
        if a == "--owner-uid":
            OWNER_UID = int(args[i + 1])
            i += 2
            continue
        if a == "--before":
            before = args[i + 1]
            i += 2
            continue
        if a == "--non-interactive":
            non_inter = True
        elif a == "--waiting":
            mode = "waiting"
        elif a == "--test-interactive":
            test_inter = True
        else:
            rest.append(a)
        i += 1
    if not rest:
        print("usage: slacky_config.py capture --before FILE | capture --waiting | reconcile [--non-interactive]")
        return 2
    cmd = rest[0]
    if cmd == "capture":
        pk = read_pkgdb()
        if mode == "waiting":
            rec, skipped, err = capture(pk, True)
        elif before:
            try:
                with open(before) as f:
                    old = {l.strip() for l in f if l.strip()}
            except OSError:
                return 0
            rec, skipped, err = capture([p for p in pk if p[0] not in old], False)
        else:
            return 2
        if err:
            print("The record of earlier Slackware file versions could not be updated; nothing in /etc was changed.")
        return 0
    if cmd == "reconcile":
        interactive = not (non_inter or os.environ.get("NON_INTERACTIVE") == "1" or not sys.stdin.isatty())
        if test_inter and not non_inter:
            interactive = True
        return reconcile(interactive)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
