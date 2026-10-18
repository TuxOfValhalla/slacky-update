"""Verified vendor downloads for the curated suite (6A-176).

Claude Desktop (Anthropic's Debian package), Claude Code and Gemini CLI (npm tarballs) used to be downloaded with no
checksum at all and unpacked with an unfiltered ``tarfile.extractall``. This module reads the checksum that the vendor
itself publishes (npm ``dist.integrity`` SHA-512 of the exact version; the SHA-256 in Anthropic's apt ``Packages`` index),
over https and with a size cap, downloads the file with a size cap, checks it, and only then lets the caller unpack it
with a safe member check. Every doubt is an error (fail closed): the caller builds nothing.

6A-192: Bambu Studio comes from the official Bambu Lab GitHub release AppImage (SHA-256 from the release API, unpacked by
``unsquashfs`` and never run); see the GitHub section below.

Used by the PYBUILD blocks in ``mod_gaming.sh``. It never runs anything and never needs root. The Rust app has its own
implementation of the same rules (``vendor_resolve.rs``); the two share only these rules, never code.
"""

import base64
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import tarfile
import urllib.request

NPM_HOST_PREFIX = "https://registry.npmjs.org/"
APT_INDEX_URL = "https://downloads.claude.ai/claude-desktop/apt/stable/dists/stable/main/binary-amd64/Packages"
APT_BASE_URL = "https://downloads.claude.ai/claude-desktop/apt/stable/"
MAX_METADATA_BYTES = 4 << 20
UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"

# the member checks above replace the extraction filter; naming the no-op filter avoids the Python 3.12 deprecation warning
_TRUSTED = {"filter": "fully_trusted"} if hasattr(tarfile, "fully_trusted_filter") else {}

_NET = False


def _urlopen(req, timeout):
    """6A-244: urlopen with one IPv4 retry when an IPv6 address is unreachable (slacky_net.py, loaded by path); plain
    urllib when that file is missing."""
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


_PLAIN_VERSION = re.compile(r"^[0-9]{1,9}(\.[0-9]{1,9}){0,4}$")


class VendorError(Exception):
    """A plain reason; the caller must not build."""


def plain_version(v):
    return bool(_PLAIN_VERSION.match(v or ""))


def _read_capped(url, cap, timeout=60):
    if not url.startswith("https://"):
        raise VendorError("not an https address")
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with _urlopen(req, timeout) as resp:
        if not resp.geturl().startswith("https://"):
            raise VendorError("redirected away from https")
        data = resp.read(cap + 1)
    if len(data) > cap:
        raise VendorError("the answer is too large")
    return data


# ---- npm ----------------------------------------------------------------------------------------------------------------

def parse_npm_record(body, package, version):
    """Version record of an npm package -> (tarball_url, sha512_hex). Raises VendorError on any doubt."""
    import json
    try:
        rec = json.loads(body)
    except ValueError:
        raise VendorError("the registry answer is not JSON")
    if not isinstance(rec, dict) or rec.get("name") != package:
        raise VendorError("the registry answer is for another package")
    if rec.get("version") != version or not plain_version(version):
        raise VendorError("the registry version is not the wanted plain release version")
    dist = rec.get("dist")
    if not isinstance(dist, dict):
        raise VendorError("no dist record")
    tarball = dist.get("tarball")
    if (not isinstance(tarball, str) or not tarball.startswith(NPM_HOST_PREFIX)
            or not tarball.endswith("-" + version + ".tgz")
            or any(c in tarball for c in " \t\r\n?#\\") or ".." in tarball[len(NPM_HOST_PREFIX):]):
        raise VendorError("the tarball address is not on the npm registry")
    integrity = dist.get("integrity")
    if not isinstance(integrity, str):
        raise VendorError("no integrity value")
    b64 = next((t[len("sha512-"):] for t in integrity.split() if t.startswith("sha512-")), None)
    if b64 is None:
        raise VendorError("no SHA-512 integrity value")
    try:
        raw = base64.b64decode(b64, validate=True)
    except ValueError:
        raise VendorError("the SHA-512 integrity value is malformed")
    if len(raw) != 64:
        raise VendorError("the SHA-512 integrity value is malformed")
    return tarball, raw.hex()


def npm_record(package, version):
    """Reads the registry record of exactly `version`; returns (tarball_url, sha512_hex)."""
    if not plain_version(version):
        raise VendorError("not a plain release version")
    try:
        body = _read_capped(NPM_HOST_PREFIX + package + "/" + version, MAX_METADATA_BYTES)
    except VendorError:
        raise
    except Exception:
        raise VendorError("the vendor metadata could not be read")
    return parse_npm_record(body, package, version)


# ---- apt index ------------------------------------------------------------------------------------------------------------

def _safe_deb_filename(f):
    return (f.startswith("pool/") and f.endswith(".deb") and re.match(r"^[A-Za-z0-9._/+~-]+$", f) is not None
            and not any(p in ("", ".", "..") for p in f.split("/")))


def parse_apt_index(text, package, version):
    """Packages index -> (deb_url, sha256_hex, size) of the amd64 entry of exactly `version`."""
    if not plain_version(version):
        raise VendorError("not a plain release version")
    for stanza in text.split("\n\n"):
        fields = {}
        for line in stanza.splitlines():
            if ":" in line and not line.startswith((" ", "\t")):
                k, v = line.split(":", 1)
                fields[k] = v.strip()
        if fields.get("Package") != package or fields.get("Architecture") != "amd64" or fields.get("Version") != version:
            continue
        fn, sha = fields.get("Filename", ""), fields.get("SHA256", "")
        if not _safe_deb_filename(fn) or ("_" + version + "_") not in fn:
            continue
        if len(sha) != 64 or re.match(r"^[0-9a-fA-F]{64}$", sha) is None:
            continue
        size = int(fields["Size"]) if fields.get("Size", "").isdigit() else 0
        return APT_BASE_URL + fn, sha.lower(), size
    raise VendorError("the package index has no usable entry for this version")


def apt_record(package, version):
    try:
        body = _read_capped(APT_INDEX_URL, MAX_METADATA_BYTES)
        text = body.decode("utf-8")
    except VendorError:
        raise
    except Exception:
        raise VendorError("the vendor metadata could not be read")
    return parse_apt_index(text, package, version)


def parse_apt_latest(text, package):
    """6A-310 (V6): newest plain release version of `package` (amd64) in a Packages index; None when there is none.

    Only entries that parse_apt_index would accept count, so the version offered is always one that can be installed."""
    best = None
    for stanza in text.split("\n\n"):
        fields = {}
        for line in stanza.splitlines():
            if ":" in line and not line.startswith((" ", "\t")):
                k, v = line.split(":", 1)
                fields[k] = v.strip()
        ver = fields.get("Version", "")
        if fields.get("Package") != package or fields.get("Architecture") != "amd64" or not plain_version(ver):
            continue
        try:
            parse_apt_index(stanza, package, ver)
        except VendorError:
            continue
        if best is None or _version_key(ver) > _version_key(best):
            best = ver
    return best


def apt_latest_version(package):
    """6A-310 (V6): the newest version in the vendor's own apt index (not a third party's recipe); None when it cannot be read."""
    try:
        return parse_apt_latest(_read_capped(APT_INDEX_URL, MAX_METADATA_BYTES).decode("utf-8"), package)
    except Exception:
        return None


# ---- Antigravity: Google's own update service (6A-311, V5) ---------------------------------------------------------------
#
# Google has no checksum file, but the update service of the app itself answers with the download address and a SHA-256 of
# that file. When the address it names is the one we are about to download, that value is the vendor's own and is used; when
# it names another build (the service can lag behind), nothing is claimed and the caller keeps the third-party value.

ANTIGRAVITY_UPDATE_API = "https://antigravity-auto-updater-974169037036.us-central1.run.app/api/update/linux-x64/stable/latest"
ANTIGRAVITY_URL_PREFIX = "https://storage.googleapis.com/antigravity-public/antigravity-hub/"


def parse_antigravity_update(body):
    """Update-service answer -> (url, sha256_hex) or None on any doubt."""
    import json
    try:
        rec = json.loads(body)
    except ValueError:
        return None
    if not isinstance(rec, dict):
        return None
    url, sha = rec.get("url"), rec.get("sha256hash")
    if (not isinstance(url, str) or not url.startswith(ANTIGRAVITY_URL_PREFIX) or not url.endswith("/linux-x64/Antigravity.tar.gz")
            or any(c in url for c in " \t\r\n?#\\") or ".." in url):
        return None
    if not isinstance(sha, str) or _HEX64.match(sha) is None:
        return None
    return url, sha.lower()


def antigravity_vendor_sha256(url):
    """SHA-256 that Google publishes for exactly `url`; None when the service is unreachable or names another build."""
    try:
        rec = parse_antigravity_update(_read_capped(ANTIGRAVITY_UPDATE_API, MAX_METADATA_BYTES, timeout=15))
    except Exception:
        return None
    if rec is None or rec[0] != url:
        return None
    return rec[1]


# ---- download + check ---------------------------------------------------------------------------------------------------

def file_digest(path, algo):
    h = hashlib.new(algo)
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def download_verified(url, dest, algo, want_hex, max_bytes):
    """Downloads `url` to `dest` (size cap, https only) and keeps it only when its digest equals `want_hex`.

    A file already at `dest` is checked first and reused when it matches; a file that does not match is removed and
    downloaded again once. Raises VendorError when the final file does not match."""
    want_hex = want_hex.lower()
    if os.path.isfile(dest) and not os.path.islink(dest):
        if file_digest(dest, algo) == want_hex:
            return
        os.unlink(dest)
    elif os.path.lexists(dest):
        os.unlink(dest)
    if not url.startswith("https://"):
        raise VendorError("not an https address")
    part = dest + ".part"
    if os.path.lexists(part):
        os.unlink(part)
    h = hashlib.new(algo)
    total = 0
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with _urlopen(req, 120) as resp, open(part, "xb") as out:
            if not resp.geturl().startswith("https://"):
                raise VendorError("redirected away from https")
            while True:
                chunk = resp.read(1 << 16)
                if not chunk:
                    break
                total += len(chunk)
                if total > max_bytes:
                    raise VendorError("the download is larger than allowed")
                h.update(chunk)
                out.write(chunk)
        if total == 0 or h.hexdigest() != want_hex:
            raise VendorError("could not be verified")
        os.replace(part, dest)
    except VendorError:
        if os.path.lexists(part):
            os.unlink(part)
        raise
    except Exception:
        if os.path.lexists(part):
            os.unlink(part)
        raise VendorError("the download failed")


# ---- safe unpacking -----------------------------------------------------------------------------------------------------

def _inside(base, path):
    base = os.path.realpath(base)
    path = os.path.realpath(path)
    return path == base or path.startswith(base + os.sep)


def extract_safe(tf, dest, allow_absolute_links=False):
    """Unpacks an open TarFile below `dest` with a member check (the effect of ``filter='data'``).

    Refused: absolute or ``..`` member names, devices and fifos, links that leave `dest` (absolute link targets only when
    `allow_absolute_links`, as a Debian package may have them; they are never followed while unpacking), members whose
    parent folder is reached through a link. setuid/setgid and group/other write bits are cleared; owners are not set."""
    dest = os.path.abspath(dest)
    os.makedirs(dest, exist_ok=True)
    if not allow_absolute_links and hasattr(tarfile, "data_filter"):
        try:
            tf.extractall(dest, filter="data")
        except tarfile.FilterError as exc:
            raise VendorError("unsafe archive member: " + str(exc))
        return
    members = []
    for m in tf.getmembers():
        name = m.name
        if name.startswith("/") or any(p == ".." for p in name.split("/")):
            raise VendorError("unsafe archive member name: " + name)
        if not (m.isfile() or m.isdir() or m.issym() or m.islnk()):
            raise VendorError("unsafe archive member type: " + name)
        target = os.path.join(dest, name)
        if m.issym():
            if os.path.isabs(m.linkname):
                if not allow_absolute_links:
                    raise VendorError("unsafe archive link: " + name)
            elif not _inside(dest, os.path.join(os.path.dirname(target), m.linkname)):
                raise VendorError("unsafe archive link: " + name)
        if m.islnk() and (m.linkname.startswith("/") or any(p == ".." for p in m.linkname.split("/"))):
            raise VendorError("unsafe archive hard link: " + name)
        m.mode = m.mode & 0o755 if not m.isdir() else (m.mode & 0o755) | 0o700
        m.uid = m.gid = 0
        m.uname = m.gname = ""
        members.append(m)
    for m in members:
        target = os.path.join(dest, m.name)
        parent = os.path.dirname(target)
        os.makedirs(parent, exist_ok=True)
        if not _inside(dest, parent):
            raise VendorError("archive member reached through a link: " + m.name)
        if not m.issym() and os.path.islink(target):
            raise VendorError("archive member written through a link: " + m.name)
        tf.extract(m, dest, set_attrs=True, **_TRUSTED)

# ---- GitHub releases (6A-192) -------------------------------------------------------------------------------------------
#
# Bambu Studio: the AUR / Chaotic name `bambu-studio-bin` is dead (and was a third-party fork). The official source is the
# release AppImage that Bambu Lab publishes on GitHub. The release API lists, for every asset, a `digest` ("sha256:...")
# that GitHub computes at upload; the download is accepted only when its SHA-256 equals it. Prereleases and drafts are never
# taken; the address must be exactly https://github.com/<repo>/releases/download/<tag>/<asset name>. The Rust app reads the
# same fields by the same rules (vendor_resolve.rs `parse_github`); the two share only the rules, never code.

GITHUB_API = "https://api.github.com/repos/%s/releases?per_page=30"
BAMBU_REPO = "bambulab/BambuStudio"
BAMBU_ASSET_RE = r"^BambuStudio_(ubuntu24\.04|ubu24)-v[0-9][0-9.]*-[0-9]+\.AppImage$"
_GH_REPO = re.compile(r"^[A-Za-z0-9._-]{1,100}/[A-Za-z0-9._-]{1,100}$")
_ASSET_NAME = re.compile(r"^[A-Za-z0-9._+-]{1,200}$")
_HEX64 = re.compile(r"^[0-9a-fA-F]{64}$")


def _version_key(v):
    return tuple(int(p) for p in v.split("."))


def parse_github_releases(body, repo, asset_re, want_version=None):
    """Releases list -> (version, url, sha256_hex, size) of the newest non-prerelease with a matching, checked asset."""
    if not _GH_REPO.match(repo or ""):
        raise VendorError("the repository name is not acceptable")
    pattern = re.compile(asset_re)
    try:
        releases = json.loads(body)
    except ValueError:
        raise VendorError("the release list is not JSON")
    if not isinstance(releases, list):
        raise VendorError("the release list is not a list")
    best = None
    for rel in releases:
        if not isinstance(rel, dict) or rel.get("prerelease") is not False or rel.get("draft") is not False:
            continue
        tag = rel.get("tag_name")
        if not isinstance(tag, str) or any(c in tag for c in "/?#"):
            continue
        version = tag[1:] if tag.startswith("v") else tag
        if not plain_version(version) or (want_version is not None and version != want_version):
            continue
        for a in rel.get("assets") or []:
            if not isinstance(a, dict):
                continue
            name = a.get("name")
            if not isinstance(name, str) or not _ASSET_NAME.match(name) or name.startswith(".") or not pattern.search(name):
                continue
            if ("v" + version) not in name or a.get("state") != "uploaded":
                continue
            url = "https://github.com/%s/releases/download/%s/%s" % (repo, tag, name)
            if a.get("browser_download_url") != url:
                continue
            digest = a.get("digest")
            if not isinstance(digest, str) or not digest.startswith("sha256:") or not _HEX64.match(digest[7:]):
                continue
            size = a.get("size")
            if not isinstance(size, int) or isinstance(size, bool) or size <= 0:
                continue
            rec = (version, url, digest[7:].lower(), size)
            if best is None or _version_key(version) > _version_key(best[0]):
                best = rec
            break
    if best is None:
        raise VendorError("no suitable release was found")
    return best


def github_release_record(repo, asset_re, want_version=None):
    try:
        body = _read_capped(GITHUB_API % repo, MAX_METADATA_BYTES)
    except VendorError:
        raise
    except Exception:
        raise VendorError("the vendor metadata could not be read")
    return parse_github_releases(body, repo, asset_re, want_version)


def verify_github_asset(path, repo, asset_re, version):
    """The downloaded file must be the asset of exactly `version`, with the size and SHA-256 the release API names."""
    rec = github_release_record(repo, asset_re, version)
    if os.path.basename(rec[1]) != os.path.basename(path) or os.path.getsize(path) != rec[3]:
        raise VendorError("could not be verified")
    if file_digest(path, "sha256") != rec[2]:
        raise VendorError("could not be verified")
    return rec


# ---- AppImage (type 2) -------------------------------------------------------------------------------------------------
#
# An ELF runtime followed by a SquashFS image. The file is never executed: the image offset is read from the ELF header (end of
# the section header table), the image is listed first (entry count, size, plain paths, only files / folders / links), then
# extracted by `unsquashfs`, and the tree is normalised (plain modes, anything else refused).

MAX_APPIMAGE_ENTRIES = 200000
MAX_APPIMAGE_BYTES = 4 << 30
# NEEDED entries of older Ubuntu builds of the AppImage and what exists here (None = drop the entry)
BAMBU_NEEDED_FIXES = (
    ("libOSMesa.so.8", None),
    ("libwebkit2gtk-4.0.so.37", "libwebkit2gtk-4.1.so.0"),
    ("libjavascriptcoregtk-4.0.so.18", "libjavascriptcoregtk-4.1.so.0"),
    ("libsoup-2.4.so.1", "libsoup-3.0.so.0"),
)


def _clean_env():
    return {k: v for k, v in os.environ.items() if k != "LD_LIBRARY_PATH"}


def appimage_offset(head, size):
    if len(head) < 64 or head[:4] != b"\x7fELF" or head[4] != 2 or head[5] != 1:
        raise VendorError("the file is not a 64-bit AppImage")
    shoff = struct.unpack_from("<Q", head, 0x28)[0]
    shentsize, shnum = struct.unpack_from("<HH", head, 0x3A)
    off = shoff + shentsize * shnum
    if off == 0 or off + 96 > size:
        raise VendorError("the AppImage has no image part")
    return off


def check_squashfs_listing(text, max_entries=MAX_APPIMAGE_ENTRIES, max_bytes=MAX_APPIMAGE_BYTES):
    """`unsquashfs -lls` output -> (entries, bytes); raises VendorError for anything unsafe or too large."""
    entries = total = 0
    for line in text.splitlines():
        if not line.strip():
            continue
        parts = line.split(None, 5)
        if len(parts) < 6:
            raise VendorError("the AppImage listing is damaged")
        kind, path = parts[0][:1], parts[5]
        if kind not in ("-", "d", "l"):
            raise VendorError("the AppImage holds a device, pipe or socket")
        if kind == "l":
            if " -> " not in path:
                raise VendorError("the AppImage listing is damaged")
            path = path.split(" -> ", 1)[0]
        if path == "squashfs-root":
            rel = ""
        elif path.startswith("squashfs-root/"):
            rel = path[len("squashfs-root/"):]
        else:
            raise VendorError("unsafe path in the AppImage")
        if rel and any(c in ("", ".", "..") for c in rel.split("/")):
            raise VendorError("unsafe path in the AppImage")
        if kind == "-":
            if not parts[2].isdigit():
                raise VendorError("the AppImage listing is damaged")
            total += int(parts[2])
        entries += 1
        if entries > max_entries or total > max_bytes:
            raise VendorError("the AppImage is too large")
    if entries == 0:
        raise VendorError("the AppImage is empty")
    return entries, total


def unpack_appimage(path, dest, max_entries=MAX_APPIMAGE_ENTRIES, max_bytes=MAX_APPIMAGE_BYTES):
    """Unpacks a type 2 AppImage into the new (or empty) folder `dest` without running it."""
    if shutil.which("unsquashfs") is None:
        raise VendorError("the unsquashfs tool is not installed")
    size = os.path.getsize(path)
    with open(path, "rb") as fh:
        head = fh.read(64)
        off = appimage_offset(head, size)
        fh.seek(off)
        if fh.read(4) != b"hsqs":
            raise VendorError("the AppImage has no SquashFS image part")
    if os.path.isdir(dest) and os.listdir(dest):
        raise VendorError("the folder for the AppImage is not empty")
    os.makedirs(os.path.dirname(os.path.abspath(dest)), exist_ok=True)
    ls = subprocess.run(["unsquashfs", "-o", str(off), "-lls", path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                        stdin=subprocess.DEVNULL, env=_clean_env())
    if ls.returncode != 0 or len(ls.stdout) > (64 << 20):
        raise VendorError("the AppImage image part could not be read")
    check_squashfs_listing(ls.stdout.decode("utf-8", "replace"), max_entries, max_bytes)
    ex = subprocess.run(["unsquashfs", "-no-xattrs", "-quiet", "-no-progress", "-force", "-o", str(off), "-d", dest, path],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL, env=_clean_env())
    if ex.returncode != 0:
        raise VendorError("the AppImage could not be unpacked")
    for root, dirs, files in os.walk(dest):
        for d in dirs:
            p = os.path.join(root, d)
            if not os.path.islink(p):
                os.chmod(p, 0o755)
        for f in files:
            p = os.path.join(root, f)
            if os.path.islink(p):
                continue
            if not os.path.isfile(p):
                os.unlink(p)
                raise VendorError("the AppImage held a device, pipe or socket")
            os.chmod(p, 0o755 if os.stat(p).st_mode & 0o111 else 0o644)


def fix_needed(directory, fixes=BAMBU_NEEDED_FIXES):
    """Renames or drops the NEEDED entries of older builds (stock `patchelf`); returns the number of files patched."""
    patched = 0
    tool = shutil.which("patchelf")
    for root, _dirs, files in os.walk(directory):
        for f in files:
            p = os.path.join(root, f)
            if os.path.islink(p) or not os.path.isfile(p):
                continue
            with open(p, "rb") as fh:
                if fh.read(4) != b"\x7fELF":
                    continue
            if tool is None:
                # without the tool only a file that really needs a fix is a problem; look with a plain scan of the file text
                with open(p, "rb") as fh:
                    data = fh.read()
                if any(old.encode() in data for old, _ in fixes):
                    raise VendorError("this build of Bambu Studio needs the patchelf tool, which is not installed")
                continue
            out = subprocess.run([tool, "--print-needed", p], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env=_clean_env())
            needed = out.stdout.decode("utf-8", "replace").split()
            todo = [(old, new) for old, new in fixes if old in needed]
            if not todo:
                continue
            cmd = [tool]
            for old, new in todo:
                cmd += ["--remove-needed", old] if new is None else ["--replace-needed", old, new]
            if subprocess.run(cmd + [p], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=_clean_env()).returncode != 0:
                raise VendorError("patchelf failed on " + p)
            patched += 1
    return patched
