#!/usr/bin/env python3
"""
gnomes_trust.py - trust and version correctness for Underpants Gnomes (WP-7, D9).

Standalone module, Python 3.12 stdlib only. External binaries: stock `gpgv` (hot path) and `gpg`
(keyring build only, in a private throwaway GNUPGHOME; never ~/.gnupg, never a gpg-agent).

What it provides:
  vercmp(a, b)                 faithful port of libalpm alpm_pkg_vercmp (epoch:version-release, rpmvercmp)
  verify_package(...)          detached signature check of a downloaded package (%PGPSIG% or .sig)
  build_keyring(...)           bootstrap / refresh of a per-family keyring from its keyring package,
                               checked against PINNED trust anchors, swapped atomically
  check_db_monotonic(...)      refuse a repo DB whose newest BUILDDATE is older than the last accepted one
  TrustResult.blocks(mode)     "enforce" (default: an unverified package is refused) vs "log" (emergency override)
  settle_stale(...)            6A-275: a package that fails only because the keys are too old gets ONE key refresh
                               and ONE retry before it is refused
  `python3 gnomes_trust.py selftest`

Trust model (documented simplification of pacman, see master plan s2.3):
  Arch: a packager key is accepted when it carries valid certifications from at least 3 of the 5 pinned
  master keys (same rule as pacman's "3 marginal = valid"), is not in archlinux-revoked, and the
  pins are all present in archlinux-trusted. CachyOS / Chaotic-AUR: only the pinned keys themselves
  (they sign with one project key), minus the revoked list.
"""

import base64
import binascii
import contextlib
import datetime
import errno
import fcntl
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request
from dataclasses import dataclass, field
from typing import Any, Dict, Iterator, List, Optional, Set, Tuple

# --- [ CONFIGURATION ] ---

KEYS_ROOT = "/opt/underpants/keys"
STATE_PATH_ROOT = "/var/cache/slacky-update/gnomes/trust_state.json"
MODE_ENV = "SLACKY_GNOMES_TRUST"   # "enforce" (default, 6A-275) or "log" (emergency override: checks only logged)
MODES = ("log", "enforce")
DEFAULT_MODE = "enforce"
STATUSES = ("good", "bad", "nokey", "unsigned", "error", "expired")
MAX_SIG_BYTES = 16384              # a detached package signature is a few hundred bytes
FUTURE_SKEW_SECONDS = 2 * 86400    # BUILDDATE further in the future than this is ignored (poisoning guard)
GPG_TIMEOUT = 60
GPGV_TIMEOUT = 30
WEAK_HASH_ALGOS = {"1", "2", "3"}  # MD5, SHA1, RIPEMD160 (RFC 4880 hash ids)

# Pinned trust anchors. Every pin was checked on 2026-10-13 against TWO independent sources:
# the project's published page or docs, AND the `<family>-trusted` file inside the current keyring
# package downloaded from the official mirror (FACT, see the WP-7 report).
TRUST_PINS: Dict[str, Dict[str, Any]] = {
    "archlinux": {
        "anchors": {
            "D8AFDDA07A5B6EDFA7D8CCDAD6D055F927843F1C": "Arch master key (Levente Polyak)",
            "2AC0A42EFB0B5CBC7A0402ED4DC95B6D7BE9892E": "Arch master key (David Runge)",
            "69E6471E3AE065297529832E6BA0F5A2037F4F41": "Arch master key (Johannes Loethberg)",
            "3572FA2A1B067F22C58AF155F8B821B42A6FDCD7": "Arch master key (Leonidas Spyropoulos)",
            "99B6618472A3B3B814185BAED7D3D823B88BDB9B": "Arch master key (Christian Heusel)",
        },
        "min_certs": 3,
        "keyring_pkg": "archlinux-keyring",
        "files": ("archlinux.gpg", "archlinux-trusted", "archlinux-revoked"),
        "sources": [
            "https://archlinux.org/master-keys/ (fetched 2026-10-13)",
            "archlinux-keyring-20260909-1 usr/share/pacman/keyrings/archlinux-trusted (core, geo.mirror.pkgbuild.com, 2026-10-13)",
        ],
        "verified": "2026-10-13",
    },
    "cachyos": {
        "anchors": {
            "882DCFE48E2051D48E2562ABF3B607488DB35A47": "CachyOS <admin@cachyos.org>",
        },
        "min_certs": 0,
        # 6A-200: keys listed in cachyos-trusted are vouched for when a pinned key signed the keyring package
        "vouch": True,
        "floor_pins": ("882DCFE48E2051D48E2562ABF3B607488DB35A47",),
        "keyring_pkg": "cachyos-keyring",
        "files": ("cachyos.gpg", "cachyos-trusted", "cachyos-revoked"),
        "sources": [
            "https://discuss.cachyos.org/t/pacman-signature-is-invalid/3239/22 (full fingerprint, fetched 2026-10-13)",
            "CachyOS install docs: pacman-key --recv-keys F3B607488DB35A47 (key id suffix matches)",
            "cachyos-keyring-20240331-1 usr/share/pacman/keyrings/cachyos-trusted (mirror.cachyos.org, 2026-10-13)",
        ],
        "verified": "2026-10-13",
    },
    "chaotic": {
        "anchors": {
            "EF925EA60F33D0CB85C44AD13056513887B78AEB": "Chaotic-AUR primary key (Pedro Henrique Lara Campos)",
        },
        "min_certs": 0,
        "floor_pins": ("EF925EA60F33D0CB85C44AD13056513887B78AEB",),
        "keyring_pkg": "chaotic-keyring",
        "files": ("chaotic.gpg", "chaotic-trusted", "chaotic-revoked"),
        "sources": [
            "https://aur.chaotic.cx/ docs and https://github.com/chaotic-aur: pacman-key --recv-key 3056513887B78AEB (key id suffix matches)",
            "keyserver.ubuntu.com 0x3056513887B78AEB -> EF925EA60F33D0CB85C44AD13056513887B78AEB (2026-10-13)",
            "chaotic-keyring-20251028-1 usr/share/pacman/keyrings/chaotic-trusted (cdn-mirror.chaotic.cx, 2026-10-13)",
        ],
        # Owner decision 2026-10-13: keys listed in chaotic-trusted (e.g. TNE <tne@garudalinux.org>,
        # 67BF8CA6DA181643C9723B4ED6C9442437365605, which signs today's Chaotic packages) are accepted through the chain
        # pinned anchor -> signed keyring package -> its -trusted list, like pacman-key --populate. The keyring package
        # must be signed by a PINNED anchor itself (bootstrap and every refresh), never only by a vouched key.
        "vouch": True,
        "verified": "2026-10-13",
    },
}

MESSAGES = {
    "good": "The package {name} is signed by a trusted key.",
    "bad": "The package {name} failed its signature check and may have been changed by someone else.",
    "expired": "The package {name} is signed with a security key that has run out, so it cannot be trusted until the keys are renewed; a full update (slacky-update) fetches the new keys.",
    "nokey_refreshed": "The package {name} is signed with a key that is not in your security keys yet, even after a key refresh was tried; a full update (slacky-update) renews the keys, then try again.",
    "sha_bad": "The downloaded file for {name} does not match the checksum in the package list, so it may be damaged or changed.",
    "nokey": "The package {name} is signed by a publisher we do not trust, so we cannot prove who made it.",
    "unsigned": "The package {name} has no signature, so we cannot prove who made it.",
    "error": "The signature check for {name} could not run, so its origin is unknown.",
    "db_older": "The package list from {name} is older than the one we already have, so it was not used.",
    "db_ok": "The package list from {name} is up to date.",
    "keyring_ok": "The {name} security keys were checked and updated.",
    "keyring_bad": "The {name} security keys did not match the keys we expect, so they were not updated.",
    "keys_refused_chain": "The new security keys for {repo} could not be confirmed as genuine, so they were not used.",
    "keys_refused_older": "The security keys offered for {repo} are older than the ones you already have, so they were not used.",
    "keys_refused_checks": "The security keys for {repo} did not pass the safety checks, so nothing was changed; the details are in the Spider-Sense log.",
    "keys_no_tools": "The security keys for {repo} could not be checked because the checking program (gpg) is not installed, so nothing was changed.",
    "keys_expiring": "A security key for {repo} runs out on {date}; run a full update before then so the new keys can be installed.",
    "held_suffix": " It was held back.",
    "held_family": " Packages from {repo} that need the new keys are held back until this is fixed.",
    "log_override": "Signature checks are set to log only (SLACKY_GNOMES_TRUST=log), so packages that fail them are still installed.",
    "log_suffix": " This is only logged for now.",
}


_I18N: Any = False


def _load_i18n() -> Any:
    """The program's own i18n engine, loaded by path (PYTHONSAFEPATH keeps this dir off sys.path); None when unavailable."""
    global _I18N
    if _I18N is False:
        _I18N = None
        try:
            import importlib.util
            path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "slacky_update_i18n.py")
            spec = importlib.util.spec_from_file_location("slacky_update_i18n", path)
            if spec and spec.loader:
                mod = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(mod)
                _I18N = mod.i18n
        except Exception:
            _I18N = None
    return _I18N


def localized(lk: str, default: str) -> str:
    """Sentence for the locale key `lk` (any module of the program may use this loader); `default` when unavailable."""
    i18n = _load_i18n()
    if i18n is not None:
        try:
            text = i18n.translations.get(lk) or i18n.fallback_translations.get(lk)
            if text:
                return text
        except Exception:
            pass
    return default


def _t(key: str) -> str:
    """Localised message (locales/<lang>.json key GNOMES_TRUST_<KEY>); English MESSAGES when unavailable."""
    return localized("GNOMES_TRUST_" + key.upper(), MESSAGES[key])


# --- [ RESULT TYPE AND MODE ] ---

@dataclass
class TrustResult:
    """Outcome of one trust check. `status` is one of STATUSES (or "ok"/"older" for DB checks)."""
    status: str
    key_fpr: str = ""
    detail: str = ""
    name: str = ""
    repo: str = ""
    family: str = ""
    extra: Dict[str, Any] = field(default_factory=dict)

    @property
    def ok(self) -> bool:
        return self.status in ("good", "ok")

    def blocks(self, mode: Optional[str] = None) -> bool:
        """True when this result must stop the install in the given mode. "log" never blocks."""
        return trust_mode(mode) == "enforce" and not self.ok

    def message(self, mode: Optional[str] = None) -> str:
        """One plain English sentence for a non-technical user (no emoji)."""
        if self.extra.get("kind") == "keyring":
            kind = self.extra.get("refusal")
            if kind:
                return Refusal(kind, self.detail).sentence(self.family or self.name)
            return _t("keyring_ok" if self.ok else "keyring_bad").format(name=self.name or "package")
        key = {"older": "db_older", "ok": "db_ok"}.get(self.status, self.status)
        if self.status == "nokey" and self.extra.get("refreshed"):
            key = "nokey_refreshed"
        if self.extra.get("sha_mismatch"):
            key = "sha_bad"
        text = _t(key if key in MESSAGES else "error").format(name=self.name or self.repo or "this package")
        if not self.ok and key in ("bad", "nokey", "nokey_refreshed", "unsigned", "error", "expired", "sha_bad"):
            text += _t("held_suffix") if trust_mode(mode) == "enforce" else _t("log_suffix")
        return text

    def as_dict(self) -> Dict[str, Any]:
        return {"status": self.status, "key_fpr": self.key_fpr, "detail": self.detail, "name": self.name,
                "repo": self.repo, "family": self.family, **({"extra": self.extra} if self.extra else {})}


def trust_mode(mode: Optional[str] = None) -> str:
    """Effective mode: explicit argument, else $SLACKY_GNOMES_TRUST, else "enforce" (6A-275). Only the exact word
    "log" switches the checks to logging (emergency override); anything unknown fails closed to "enforce"."""
    m = (mode or os.environ.get(MODE_ENV, "") or DEFAULT_MODE).strip().lower()
    return m if m in MODES else DEFAULT_MODE


def repo_family(repo: str) -> Optional[str]:
    """Map a gnomes repo name to its keyring family."""
    r = (repo or "").strip().lower()
    if r.startswith("cachyos"):
        return "cachyos"
    if r.startswith("chaotic"):
        return "chaotic"
    if r in ("core", "extra", "multilib") or r.endswith("-testing") or r in ("core-testing", "extra-testing", "multilib-testing"):
        return "archlinux"
    return None


# --- [ VERSION COMPARISON: port of libalpm version.c ] ---

def _alnum(c: str) -> bool:
    return c != "" and c.isascii() and c.isalnum()


def _alpha(c: str) -> bool:
    return c != "" and c.isascii() and c.isalpha()


def _digit(c: str) -> bool:
    return c != "" and c in "0123456789"


def _rpmvercmp(a: str, b: str) -> int:
    """Port of libalpm rpmvercmp() (lib/libalpm/version.c): segment-wise compare of one version part."""
    if a == b:
        return 0
    la, lb = len(a), len(b)
    at = lambda s, k: s[k] if k < len(s) else ""  # noqa: E731  (C string with NUL terminator)
    i = j = 0
    p1 = p2 = 0
    while i < la and j < lb:
        while i < la and not _alnum(a[i]):
            i += 1
        while j < lb and not _alnum(b[j]):
            j += 1
        if not (i < la and j < lb):
            break
        if (i - p1) != (j - p2):
            return -1 if (i - p1) < (j - p2) else 1
        p1, p2 = i, j
        if _digit(a[p1]):
            while _digit(at(a, p1)):
                p1 += 1
            while _digit(at(b, p2)):
                p2 += 1
            isnum = True
        else:
            while _alpha(at(a, p1)):
                p1 += 1
            while _alpha(at(b, p2)):
                p2 += 1
            isnum = False
        seg1, seg2 = a[i:p1], b[j:p2]
        if not seg1:
            return -1  # cannot happen, kept from libalpm
        if not seg2:
            return 1 if isnum else -1
        if isnum:
            seg1 = seg1.lstrip("0")
            seg2 = seg2.lstrip("0")
            if len(seg1) > len(seg2):
                return 1
            if len(seg2) > len(seg1):
                return -1
        if seg1 != seg2:
            return -1 if seg1 < seg2 else 1
        i, j = p1, p2
    if i >= la and j >= lb:
        return 0
    # the final showdown: a remaining alpha string never beats an empty string
    if (i >= la and not _alpha(at(b, j))) or _alpha(at(a, i)):
        return -1
    return 1


def parse_evr(evr: str) -> Tuple[str, str, Optional[str]]:
    """Split "epoch:version-release" like libalpm parseEVR(). Missing epoch -> "0", missing release -> None."""
    s = evr
    k = 0
    while k < len(s) and s[k].isdigit():
        k += 1
    if k < len(s) and s[k] == ":":
        epoch = s[:k] or "0"
        rest = s[k + 1:]
    else:
        epoch, rest = "0", s
    dash = rest.rfind("-")
    if dash >= 0:
        return epoch, rest[:dash], rest[dash + 1:]
    return epoch, rest, None


def vercmp(a: str, b: str) -> int:
    """alpm_pkg_vercmp(): -1 if a < b, 0 if equal, 1 if a > b. Release is compared only when both have one."""
    if a is None and b is None:
        return 0
    if a is None:
        return -1
    if b is None:
        return 1
    a, b = str(a), str(b)
    if a == b:
        return 0
    e1, v1, r1 = parse_evr(a)
    e2, v2, r2 = parse_evr(b)
    ret = _rpmvercmp(e1, e2)
    if ret == 0:
        ret = _rpmvercmp(v1, v2)
        if ret == 0 and r1 is not None and r2 is not None:
            ret = _rpmvercmp(r1, r2)
    return ret


def is_newer(candidate: str, installed: str) -> bool:
    """True only if `candidate` is strictly newer than `installed` (pacman semantics)."""
    return vercmp(candidate, installed) > 0


_REL_RE = re.compile(r"^[0-9]+(\.[0-9]+)?$")


def desanitize_slack_version(v: str) -> str:
    """Best-effort inverse of the txz name sanitising ("1:3.7.9-1.1" -> "1_3.7.9_1.1").
    INFERENCE: Arch pkgver may itself contain "_", so this is ambiguous; prefer the exact version stored by
    the engine (WP-7 says: keep the full version in the manifest/lock). Rules: the last "_" + digits[.digits]
    is the release; a leading all-digit segment followed by "_" and another "_" later is the epoch."""
    s = str(v).strip()
    parts = s.split("_")
    if len(parts) >= 2 and _REL_RE.match(parts[-1]):
        rel = parts[-1]
        head = parts[:-1]
        if len(head) >= 2 and head[0].isdigit():
            return f"{head[0]}:{'_'.join(head[1:])}-{rel}"
        return f"{'_'.join(head)}-{rel}"
    return s


# --- [ OPENPGP HELPERS (no gpg needed) ] ---

def dearmor(data: bytes) -> bytes:
    """Convert one or more ASCII-armored OpenPGP blocks to binary. Binary input is returned unchanged."""
    if b"-----BEGIN PGP" not in data:
        return data
    out = bytearray()
    for block in re.findall(rb"-----BEGIN PGP [A-Z ]+-----\r?\n(.*?)-----END PGP [A-Z ]+-----", data, re.S):
        lines = block.replace(b"\r", b"").split(b"\n")
        # skip armor headers (up to the first empty line) if present
        if b"" in lines and any(b":" in ln for ln in lines[:lines.index(b"")]):
            lines = lines[lines.index(b"") + 1:]
        body = b"".join(ln for ln in lines if ln and not ln.startswith(b"="))
        out += base64.b64decode(body)
    return bytes(out)


def decode_pgpsig(b64: str) -> Optional[bytes]:
    """Decode the base64 %PGPSIG% field of a pacman desc entry. None if empty or malformed."""
    if not b64:
        return None
    try:
        raw = base64.b64decode("".join(str(b64).split()), validate=True)
    except (binascii.Error, ValueError):
        return None
    return raw if 0 < len(raw) <= MAX_SIG_BYTES else None


def _read_subpackets(buf: bytes) -> Iterator[Tuple[int, bytes]]:
    i = 0
    while i < len(buf):
        o = buf[i]
        if o < 192:
            ln, i = o, i + 1
        elif o < 255:
            ln, i = ((o - 192) << 8) + buf[i + 1] + 192, i + 2
        else:
            ln, i = int.from_bytes(buf[i + 1:i + 5], "big"), i + 5
        if ln == 0 or i + ln > len(buf):
            return
        yield buf[i] & 0x7F, buf[i + 1:i + ln]
        i += ln


def sig_issuer(sig: bytes) -> str:
    """Issuer of a detached v4/v5 signature: fingerprint if present (subpacket 33), else 16-hex key id. "" if unknown.
    Diagnostics only; the trust decision is always made by gpgv."""
    try:
        sig = dearmor(sig)
        tag = sig[0]
        if not tag & 0x80:
            return ""
        if tag & 0x40:  # new format
            o = sig[1]
            if o < 192:
                off = 2
            elif o < 224:
                off = 3
            else:
                off = 6
        else:
            off = 1 + {0: 1, 1: 2, 2: 4}.get(tag & 3, 0)
        body = sig[off:]
        ver = body[0]
        if ver not in (4, 5, 6):
            return body[7:15].hex().upper() if ver == 3 else ""
        hl = 2 if ver == 4 else 4
        hlen = int.from_bytes(body[4:4 + hl], "big")
        hashed = body[4 + hl:4 + hl + hlen]
        rest = body[4 + hl + hlen:]
        ulen = int.from_bytes(rest[:hl], "big")
        unhashed = rest[hl:hl + ulen]
        keyid = ""
        for area in (hashed, unhashed):
            for typ, data in _read_subpackets(area):
                if typ == 33 and len(data) >= 21:
                    return data[1:].hex().upper()
                if typ == 16 and len(data) == 8:
                    keyid = data.hex().upper()
        return keyid
    except (IndexError, ValueError):
        return ""


# --- [ GPG PLUMBING ] ---

def _clean_env() -> Dict[str, str]:
    """Host environment without the foreign LD_LIBRARY_PATH (CLAUDE.md s3 trap) and without GNUPGHOME."""
    env = dict(os.environ)
    env.pop("LD_LIBRARY_PATH", None)
    env.pop("GNUPGHOME", None)
    env["LC_ALL"] = "C"
    return env


@contextlib.contextmanager
def _private_gnupghome() -> Iterator[str]:
    """Throwaway 0700 GNUPGHOME. An empty common.conf stops gpg from switching the new home to keyboxd;
    every gpg call uses --no-autostart so no agent or dirmngr is started."""
    home = tempfile.mkdtemp(prefix="gnomes-gpg-")
    try:
        os.chmod(home, 0o700)
        open(os.path.join(home, "common.conf"), "w").close()
        yield home
    finally:
        try:
            subprocess.run(["gpgconf", "--homedir", home, "--kill", "all"], env=_clean_env(),
                           capture_output=True, timeout=10, check=False)
        except (OSError, subprocess.SubprocessError):
            pass
        shutil.rmtree(home, ignore_errors=True)


def _gpg(home: str, args: List[str], stdin: Optional[bytes] = None) -> subprocess.CompletedProcess:
    cmd = ["gpg", "--homedir", home, "--batch", "--no-tty", "--no-autostart", "--no-auto-key-retrieve",
           "--no-auto-check-trustdb", "--quiet"] + args
    return subprocess.run(cmd, input=stdin, env=_clean_env(), capture_output=True, timeout=GPG_TIMEOUT, check=False)


def _parse_status(text: str) -> Dict[str, List[List[str]]]:
    st: Dict[str, List[List[str]]] = {}
    for line in text.splitlines():
        if line.startswith("[GNUPG:] "):
            parts = line[9:].split()
            if parts:
                st.setdefault(parts[0], []).append(parts[1:])
    return st


def read_revoked(path: str) -> Set[str]:
    """Read a pacman-style revoked list (one fingerprint per line)."""
    out: Set[str] = set()
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                t = line.strip().split(":")[0].upper()
                if re.fullmatch(r"[0-9A-F]{40}|[0-9A-F]{64}", t):
                    out.add(t)
    except OSError:
        pass
    return out


# --- [ PACKAGE SIGNATURE VERIFICATION (hot path, gpgv only) ] ---

def verify_detached(path: str, sig: bytes, keyring: str, revoked: Optional[Set[str]] = None,
                    name: str = "", repo: str = "", family: str = "",
                    allowed: Optional[Set[str]] = None) -> TrustResult:
    """Verify `path` against detached signature bytes with stock gpgv and one binary keyring. `allowed` (6A-200): only
    these primary fingerprints count even if the file holds more keys (the shipped snapshot of a pinned family)."""
    base = dict(name=name or os.path.basename(path), repo=repo, family=family or "")
    if not sig:
        return TrustResult("unsigned", detail="no signature available", **base)
    if len(sig) > MAX_SIG_BYTES:
        return TrustResult("bad", detail="signature is unreasonably large", **base)
    if not os.path.isfile(path):
        return TrustResult("error", detail="package file missing", **base)
    if not os.path.isfile(keyring):
        return TrustResult("nokey", key_fpr=sig_issuer(sig), detail=f"keyring not installed: {keyring}", **base)
    sig = dearmor(sig)
    with tempfile.TemporaryDirectory(prefix="gnomes-gpgv-") as tmp:
        os.chmod(tmp, 0o700)
        sig_path = os.path.join(tmp, "pkg.sig")
        with open(sig_path, "wb") as f:
            f.write(sig)
        try:
            cp = subprocess.run(["gpgv", "--homedir", tmp, "--keyring", os.path.abspath(keyring),
                                 "--status-fd", "1", sig_path, path],
                                env=_clean_env(), capture_output=True, timeout=GPGV_TIMEOUT, check=False)
        except FileNotFoundError:
            return TrustResult("error", detail="gpgv is not installed", **base)
        except subprocess.TimeoutExpired:
            return TrustResult("error", detail="gpgv timed out", **base)
    st = _parse_status(cp.stdout.decode("utf-8", "replace"))
    issuer = sig_issuer(sig)
    if "BADSIG" in st:
        return TrustResult("bad", key_fpr=issuer, detail="signature does not match the file", **base)
    if "REVKEYSIG" in st:
        return TrustResult("bad", key_fpr=issuer, detail="signing key is revoked", **base)
    if "EXPSIG" in st:
        return TrustResult("bad", key_fpr=issuer, detail="the signature itself has expired", **base)
    if "EXPKEYSIG" in st:
        # 6A-275: the key has run out (a renewed keyring may extend it, so callers may refresh once). Whether it had
        # already run out when the package was signed is recorded for the log; the verdict is the same either way.
        ex: Dict[str, Any] = {}
        try:
            ex["key_expired_at"] = int(st["KEYEXPIRED"][0][0])
            ex["sig_time"] = int(st["VALIDSIG"][0][2])
            ex["expired_when_signed"] = ex["sig_time"] >= ex["key_expired_at"]
        except (KeyError, IndexError, ValueError):
            pass
        vs = st.get("VALIDSIG", [])
        if revoked and vs and ({vs[0][0].upper(), (vs[0][9] if len(vs[0]) > 9 else vs[0][0]).upper()} & revoked):
            return TrustResult("bad", key_fpr=issuer, detail="signing key is on the revoked list", **base)
        return TrustResult("expired", key_fpr=issuer, detail="signing key has expired", extra=ex, **base)
    if "ERRSIG" in st:
        rc = st["ERRSIG"][0][5] if len(st["ERRSIG"][0]) > 5 else ""
        if rc == "9" or "NO_PUBKEY" in st:
            return TrustResult("nokey", key_fpr=issuer, detail="signing key not in the trusted keyring", **base)
        return TrustResult("error", key_fpr=issuer, detail=f"gpgv could not check the signature (rc {rc})", **base)
    valid = st.get("VALIDSIG", [])
    if cp.returncode != 0 or len(valid) != 1 or len(st.get("GOODSIG", [])) != 1 or len(st.get("NEWSIG", [None])) > 1:
        return TrustResult("bad", key_fpr=issuer, detail=f"unexpected gpgv result (rc {cp.returncode}, {len(valid)} valid)", **base)
    v = valid[0]
    signer = v[0].upper()
    primary = v[9].upper() if len(v) > 9 else signer
    hash_algo = v[7] if len(v) > 7 else ""
    if revoked and (signer in revoked or primary in revoked):
        return TrustResult("bad", key_fpr=primary, detail="signing key is on the revoked list", **base)
    if allowed is not None and primary not in {a.upper() for a in allowed}:
        return TrustResult("nokey", key_fpr=primary, detail="signing key is not one of the keys this keyring is trusted for", **base)
    if hash_algo in WEAK_HASH_ALGOS:
        return TrustResult("bad", key_fpr=primary, detail=f"weak signature hash algorithm {hash_algo}", **base)
    return TrustResult("good", key_fpr=primary, detail=f"signed by {primary}", extra={"signer": signer}, **base)


def verify_package(pkg_path: str, sig_bytes: Optional[bytes], repo: str, keys_root: str = KEYS_ROOT,
                   name: str = "", pgpsig_b64: str = "", shipped_dir: Optional[str] = None) -> TrustResult:
    """Verify a downloaded package. Signature source: `sig_bytes` (downloaded .sig) or the base64 %PGPSIG%.
    Rings (6A-200, spec section 3): the generation in force (`current` when valid, else the newest valid gen.*), then
    the snapshot shipped with the program as the floor; the generation's revoked list applies to both. A store that is
    unsafe to read gives "nokey" (fail closed).
    Never raises; never blocks by itself (the caller applies `result.blocks(mode)`)."""
    try:
        family = repo_family(repo)
        if sig_bytes is None and pgpsig_b64:
            sig_bytes = decode_pgpsig(pgpsig_b64)
            if sig_bytes is None:
                return TrustResult("bad", detail="malformed %PGPSIG% field", name=name or os.path.basename(pkg_path),
                                   repo=repo, family=family or "")
        if family is None:
            return TrustResult("nokey", key_fpr=sig_issuer(sig_bytes or b""), detail=f"no keyring family for repo {repo}",
                               name=name or os.path.basename(pkg_path), repo=repo)
        if not sig_bytes:
            return TrustResult("unsigned", detail="no signature available", name=name or os.path.basename(pkg_path),
                               repo=repo, family=family)
        rings, why = reader_rings(family, keys_root, shipped_dir)
        if not rings:
            return TrustResult("nokey", key_fpr=sig_issuer(sig_bytes), detail=why or "no keyring installed",
                               name=name or os.path.basename(pkg_path), repo=repo, family=family)
        res = check_rings(rings, pkg_path, sig_bytes, name=name, repo=repo, family=family)
        if res.ok:
            _note_used_signer(family, res)
        return res
    except Exception as e:  # trust code must never crash the engine
        return TrustResult("error", detail=f"{type(e).__name__}: {e}", name=name or os.path.basename(pkg_path), repo=repo)


_USED: Dict[str, Dict[str, str]] = {}
_USED_HOOKED = False


def _note_used_signer(family: str, res: "TrustResult") -> None:
    """Remember which keys signed the packages that verified (6A-202 expiry radar). Kept in memory and handed to the
    sentinel once at exit, which stores it in the user's own cache (nothing for root)."""
    global _USED_HOOKED
    signer = str(res.extra.get("signer", "")).upper()
    if not family or not res.key_fpr or not signer:
        return
    _USED.setdefault(family, {})[res.key_fpr.upper()] = signer
    if not _USED_HOOKED:
        import atexit
        atexit.register(_flush_used_signers)
        _USED_HOOKED = True


def _flush_used_signers() -> None:
    if not _USED or os.geteuid() == 0:
        return
    try:
        import importlib.util
        mod = sys.modules.get("slacky_sentinel")
        if mod is None:
            path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "slacky_sentinel.py")
            spec = importlib.util.spec_from_file_location("slacky_sentinel", path)
            if not spec or not spec.loader:
                return
            mod = importlib.util.module_from_spec(spec)
            sys.modules["slacky_sentinel"] = mod
            spec.loader.exec_module(mod)
        mod.note_used_signers({f: dict(m) for f, m in _USED.items()})
    except Exception:
        pass


_NET: Any = False


def _urlopen(req: Any, timeout: float) -> Any:
    """6A-244: urlopen with one IPv4 retry when an IPv6 address is unreachable (slacky_net.py, loaded by path)."""
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
    if _NET is not None:
        return _NET.open_url(req, timeout=timeout)
    return urllib.request.urlopen(req, timeout=timeout)


def sig_url(pkg_url: str) -> str:
    """Detached signature URL used by Arch, CachyOS and Chaotic mirrors."""
    return pkg_url + ".sig"


def fetch_signature(url: str, timeout: int = 15) -> Optional[bytes]:
    """Download a detached .sig (bounded size). None on any failure (caller reports "unsigned")."""
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Slacky-Update UnderpantsGnomes"})
        with _urlopen(req, timeout) as resp:
            data = resp.read(MAX_SIG_BYTES + 1)
        return data if 0 < len(data) <= MAX_SIG_BYTES else None
    except Exception:
        return None


# --- [ KEYRING STORE: READERS ] ---
# 6A-200 (Rust mirror: MS2): the key store /opt/underpants/keys/<family>/ is shared with the Rust app. Format and rules
# are in docs/mirror_key_spec.md (sections 3 and 4); only the format is shared, never code.

GEN_FILES = ("pubring.gpg", "revoked", "trusted", "meta.json")
MAX_PKG_BYTES = 24 * 1024 * 1024
MAX_UNPACKED = 256 * 1024 * 1024
MAX_ENTRY = 32 * 1024 * 1024
MAX_LIST_BYTES = 2 * 1024 * 1024
PKG_KEYRING_DIR = "usr/share/pacman/keyrings/"
WRITER = "slacky-update"
LOCK_WAIT_STEPS = 200              # 200 x 50 ms = 10 s
_GEN_RE = re.compile(r"^gen\.(\d{14})(?:-(\d+))?$")
_FPR_RE = re.compile(r"[0-9A-F]{40}|[0-9A-F]{64}")

DISPLAY_NAMES = {"archlinux": "Arch Linux", "cachyos": "CachyOS", "chaotic": "Chaotic-AUR"}


def display_name(family: str) -> str:
    return DISPLAY_NAMES.get(family, family)


class Refusal(Exception):
    """A keyring package that failed a rule. `kind` is machine readable, `detail` goes to the flight recorder."""
    NO_SIGNATURE = "no_signature"
    MALFORMED = "malformed"
    OLDER = "older"
    REVOKED_STRIPPED = "revoked_list_stripped"
    ANCHOR_MISSING = "anchor_missing"
    ANCHOR_REVOKED = "anchor_revoked"
    CHAIN_BROKEN = "chain_broken"
    SIGNER_NOT_PINNED = "signer_not_pinned"
    NO_TOOLS = "no_tools"
    STORE = "store"

    def __init__(self, kind: str, detail: str = ""):
        super().__init__(f"{kind}: {detail}")
        self.kind = kind
        self.detail = detail

    def sentence(self, family: str, mode: Optional[str] = None) -> str:
        """One plain sentence for the user (6A-275: the "held back" part is only said in enforce mode, where it is true)."""
        extra = ""
        if self.kind in (self.CHAIN_BROKEN, self.SIGNER_NOT_PINNED):
            key = "keys_refused_chain"
            if trust_mode(mode) == "enforce":
                extra = _t("held_family")
        elif self.kind == self.OLDER:
            key = "keys_refused_older"
        elif self.kind == self.NO_TOOLS:
            key = "keys_no_tools"
        else:
            key = "keys_refused_checks"
        return (_t(key) + extra).replace("{repo}", display_name(family))

    def status(self) -> str:
        return {self.NO_SIGNATURE: "unsigned", self.OLDER: "older", self.NO_TOOLS: "error",
                self.STORE: "error"}.get(self.kind, "bad")


@dataclass
class Generation:
    dir: str
    pubring: str
    revoked: Set[str]
    trusted: Set[str]
    meta: Dict[str, Any]

    def pkgver_key(self) -> Optional[Tuple[int, int]]:
        """(version, release) as numbers from meta pkgver, or (older generations) from the keyring_pkg file name."""
        k = _parse_pkgver(str(self.meta.get("pkgver", "")))
        if k:
            return k
        parts = str(self.meta.get("keyring_pkg", "")).split("-")
        for a, b in zip(parts, parts[1:]):
            if a.isascii() and a.isdigit() and b.isascii() and b.isdigit():
                return int(a), int(b)
        return None

    def builddate(self) -> int:
        try:
            return max(0, int(self.meta.get("builddate", 0) or 0))
        except (TypeError, ValueError):
            return 0

    def dynamic_anchors(self) -> Set[str]:
        d = self.meta.get("dynamic_anchors", [])
        return {str(k).upper() for k in d} if isinstance(d, list) else set()


class _Unsafe(Exception):
    pass


class _Invalid(Exception):
    pass


def _parse_pkgver(s: str) -> Optional[Tuple[int, int]]:
    v, sep, r = s.strip().partition("-")
    if sep and v.isascii() and v.isdigit() and r.isascii() and r.isdigit():
        return int(v), int(r)
    return None


def _parse_fprs(text: str) -> Set[str]:
    out: Set[str] = set()
    for line in text.splitlines():
        t = line.strip().split(":")[0].upper()
        if _FPR_RE.fullmatch(t):
            out.add(t)
    return out


def _dir_safety(p: str) -> Optional[str]:
    """None when `p` is a real folder owned by root (or by us) that nobody else can write to."""
    try:
        st = os.lstat(p)
    except OSError:
        return f"key folder missing: {p}"
    if not stat.S_ISDIR(st.st_mode):
        return f"key folder is not a real folder: {p}"
    if st.st_uid not in (0, os.geteuid()):
        return f"key folder is not owned by root: {p}"
    if st.st_mode & 0o022:
        return f"key folder is writable by other users: {p}"
    return None


def _file_safety(p: str) -> Optional[str]:
    try:
        st = os.lstat(p)
    except OSError:
        return f"key file missing: {p}"
    if not stat.S_ISREG(st.st_mode):
        return f"key file is not a regular file: {p}"
    if st.st_uid not in (0, os.geteuid()):
        return f"key file is not owned by root: {p}"
    if st.st_mode & 0o022:
        return f"key file is writable by other users: {p}"
    return None


def _read_small(p: str, cap: int) -> bytes:
    why = _file_safety(p)
    if why:
        raise _Unsafe(why)
    try:
        fd = os.open(p, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    except OSError as e:
        raise _Unsafe(f"{p}: {e}")
    with os.fdopen(fd, "rb") as f:
        data = f.read(cap + 1)
    if len(data) > cap:
        raise _Unsafe(f"{p} is unreasonably large")
    return data


def _load_generation(fam_dir: str, name: str) -> Generation:
    d = os.path.join(fam_dir, name)
    if not os.path.lexists(d):
        raise _Invalid()              # a dangling `current`
    why = _dir_safety(d)
    if why:
        raise _Unsafe(why)
    ring = os.path.join(d, "pubring.gpg")
    if not os.path.lexists(ring):
        raise _Invalid()
    why = _file_safety(ring)
    if why:
        raise _Unsafe(why)

    def optional(fn: str) -> Optional[bytes]:
        p = os.path.join(d, fn)
        return _read_small(p, MAX_LIST_BYTES) if os.path.lexists(p) else None

    rv, tr, mt = optional("revoked"), optional("trusted"), optional("meta.json")
    meta: Dict[str, Any] = {}
    if mt is not None:
        try:
            meta = json.loads(mt.decode("utf-8"))
        except ValueError:
            raise _Invalid()
        if not isinstance(meta, dict):
            raise _Invalid()
    return Generation(d, ring, _parse_fprs(rv.decode("utf-8", "replace")) if rv else set(),
                      _parse_fprs(tr.decode("utf-8", "replace")) if tr else set(), meta)


def _gen_sort_key(n: str) -> Tuple[str, int]:
    m = _GEN_RE.match(n)
    return (m.group(1), int(m.group(2) or 1)) if m else ("", 0)


def locate_generation(family: str, keys_root: str = KEYS_ROOT) -> Tuple[Optional[Generation], str]:
    """The generation in force: `current` when valid, else the newest valid gen.*. Returns (generation, "") ,
    (None, "") when there is none, or (None, reason) when the store is unsafe to read (callers fail closed)."""
    fam_dir = os.path.join(keys_root, family)
    if not os.path.lexists(fam_dir):
        return None, ""
    why = _dir_safety(fam_dir)
    if why:
        return None, why
    cur = os.path.join(fam_dir, "current")
    if os.path.lexists(cur):
        name: Optional[str] = "current"
        if os.path.islink(cur):
            try:
                t = os.readlink(cur)
            except OSError:
                t = ""
            name = t if _GEN_RE.match(t) else None
        if name:
            try:
                return _load_generation(fam_dir, name), ""
            except _Unsafe as e:
                return None, str(e)
            except _Invalid:
                pass
    try:
        names = sorted((n for n in os.listdir(fam_dir) if _GEN_RE.match(n)), key=_gen_sort_key, reverse=True)
    except OSError:
        names = []
    for n in names:
        try:
            return _load_generation(fam_dir, n), ""
        except (_Unsafe, _Invalid):
            continue
    return None, ""


def keyring_dir(family: str, keys_root: str = KEYS_ROOT) -> str:
    """The `current` link of a family (kept for callers that only need the path)."""
    return os.path.join(keys_root, family, "current")


def default_shipped_dir() -> str:
    """The keys shipped with this program (the floor): <program dir>/keys, i.e. /usr/share/slacky-update/keys."""
    return os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "keys")


def policy(family: str) -> Dict[str, Any]:
    pins = TRUST_PINS[family]
    anchors = sorted(a.upper() for a in pins["anchors"])
    return {"family": family, "pkgname": pins["keyring_pkg"], "files": pins["files"], "anchors": anchors,
            "min_certs": int(pins["min_certs"]), "vouch": bool(pins.get("vouch")),
            "floor_pins": sorted(a.upper() for a in pins.get("floor_pins", ())), "floor_file": pins["files"][0]}


# --- [ KEYRING STORE: SIGNATURE CHECKS AGAINST SEVERAL RINGS ] ---

_SEVERITY = {"good": 5, "bad": 4, "expired": 3, "nokey": 2, "unsigned": 1, "error": 1}


def check_rings(rings: List[Dict[str, Any]], path: str, sig: bytes, name: str = "", repo: str = "",
                family: str = "") -> TrustResult:
    """Good when any ring accepts the signature. The union of the revoked lists applies to every ring (a revocation
    in the generation also stops a key of the shipped snapshot). Ring: {"path", "revoked", "allowed" or None}."""
    revoked_all: Set[str] = set()
    for r in rings:
        revoked_all |= set(r.get("revoked") or ())
    best: Optional[TrustResult] = None
    for r in rings:
        rp = r["path"]() if callable(r["path"]) else r["path"]    # the Arch floor ring is built only when needed
        if not rp:
            continue
        res = verify_detached(path, sig, rp, revoked_all, name=name, repo=repo, family=family,
                              allowed=r.get("allowed"))
        if res.ok:
            return res
        if best is None or _SEVERITY.get(res.status, 0) > _SEVERITY.get(best.status, 0):
            best = res
    return best or TrustResult("nokey", detail="no keyring installed", name=name or os.path.basename(path),
                               repo=repo, family=family)


_FLOOR_CACHE: Dict[Tuple[Any, ...], Tuple[str, Set[str]]] = {}
_FLOOR_DIRS: List[str] = []
# 6A-213 (Rust: once per process): the sentinel (user cache, background) may set this folder so the evaluated Arch ring
# (about 1 s of gpg work) survives between runs. Default None = no disk cache. Never used by root, never for the
# package gate of a full update: only a program that treats the result as a hint (mirror lists) or re-verifies later
# (staged keyrings are checked again from scratch by root) opts in.
RING_CACHE_DIR: Optional[str] = None
RING_CACHE_KEEP = 4


def _ring_cache_key(data: bytes, pol: Dict[str, Any]) -> str:
    anchors = json.dumps(sorted(a.upper() for a in pol["anchors"])) + "|" + str(pol["min_certs"])
    return hashlib.sha256(data).hexdigest()[:40] + "-" + hashlib.sha256(anchors.encode()).hexdigest()[:16]


def _ring_cache_dir() -> Optional[str]:
    d = RING_CACHE_DIR
    if not d or os.geteuid() == 0:
        return None
    try:
        os.makedirs(d, mode=0o700, exist_ok=True)
        st = os.lstat(d)
        if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.geteuid() or st.st_mode & 0o077:
            return None
    except OSError:
        return None
    return d


def _ring_cache_get(d: str, key: str) -> Optional[str]:
    path = os.path.join(d, key + ".gpg")
    try:
        st = os.lstat(path)
        if not stat.S_ISREG(st.st_mode) or st.st_uid != os.geteuid() or st.st_mode & 0o077 or not 0 < st.st_size <= MAX_PKG_BYTES:
            return None
        with open(path, "rb") as f:
            blob = f.read(MAX_PKG_BYTES + 1)
        with open(path + ".sha256", "r", encoding="ascii") as f:
            want = f.read(80).strip()
    except OSError:
        return None
    return path if hashlib.sha256(blob).hexdigest() == want else None


def _ring_cache_put(d: str, key: str, blob: bytes) -> Optional[str]:
    path = os.path.join(d, key + ".gpg")
    try:
        for target, data in ((path, blob), (path + ".sha256", (hashlib.sha256(blob).hexdigest() + "\n").encode())):
            tmp = f"{target}.{os.getpid()}.tmp"
            fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
            with os.fdopen(fd, "wb") as f:
                f.write(data)
            os.replace(tmp, target)
        old = sorted((n for n in os.listdir(d) if n.endswith(".gpg") and n != key + ".gpg"),
                     key=lambda n: os.lstat(os.path.join(d, n)).st_mtime, reverse=True)
        for n in old[RING_CACHE_KEEP - 1:]:
            for x in (n, n + ".sha256"):
                try:
                    os.unlink(os.path.join(d, x))
                except OSError:
                    pass
    except OSError:
        return None
    return path


def _cleanup_floor_dirs() -> None:
    for d in _FLOOR_DIRS:
        shutil.rmtree(d, ignore_errors=True)


def _arch_floor_ring(shipped_dir: str) -> Optional[Tuple[str, Set[str]]]:
    """The shipped Arch ring evaluated under the compiled master pins (3 certifications): the accepted keys only, as a
    ring file that lives until the process ends. Cached per process; None when there is no usable snapshot."""
    raw = os.path.join(shipped_dir, "archlinux.gpg")
    if _file_safety(raw):
        return None
    st = os.stat(raw)
    key = (raw, st.st_size, int(st.st_mtime))
    if key in _FLOOR_CACHE:
        return _FLOOR_CACHE[key]
    pol = policy("archlinux")
    cache = _ring_cache_dir()
    ckey = ""
    try:
        with open(raw, "rb") as f:
            data = f.read(MAX_PKG_BYTES)
        if cache:
            ckey = _ring_cache_key(data, pol)
            hit = _ring_cache_get(cache, ckey)
            if hit:
                _FLOOR_CACHE[key] = (hit, set())
                return _FLOOR_CACHE[key]
        with _private_gnupghome() as home:
            ins = _inspect_ring(home, data)
            acc, _ = evaluate_accepted(ins["colons"], pol["anchors"], set(), pol["min_certs"])
            if not acc:
                return None
            exp = _gpg(home, ["--export", "--export-options", "export-minimal"] + sorted(acc))
        if exp.returncode != 0 or not exp.stdout:
            return None
    except (OSError, RuntimeError, subprocess.SubprocessError, Refusal):
        return None
    if cache and ckey:
        stored = _ring_cache_put(cache, ckey, exp.stdout)
        if stored:
            _FLOOR_CACHE[key] = (stored, set())
            return _FLOOR_CACHE[key]
    hold = tempfile.mkdtemp(prefix="slacky-archring-")
    if not _FLOOR_DIRS:
        import atexit
        atexit.register(_cleanup_floor_dirs)
    _FLOOR_DIRS.append(hold)
    os.chmod(hold, 0o700)
    ring = os.path.join(hold, "pubring.gpg")
    with open(ring, "wb") as f:
        f.write(exp.stdout)
    _FLOOR_CACHE[key] = (ring, set())
    return _FLOOR_CACHE[key]


def reader_rings(family: str, keys_root: str = KEYS_ROOT, shipped_dir: Optional[str] = None,
                 with_floor: bool = True) -> Tuple[List[Dict[str, Any]], str]:
    """Rings to verify a package of `family`: the generation in force first, the shipped snapshot as the floor.
    Returns (rings, reason); an unsafe store gives no rings and a reason (fail closed)."""
    pol = policy(family)
    shipped = shipped_dir if shipped_dir is not None else default_shipped_dir()
    rings: List[Dict[str, Any]] = []
    gen_revoked: Set[str] = set()
    gen, why = locate_generation(family, keys_root)
    if why:
        return [], why
    if gen is not None:
        allowed = None if pol["min_certs"] > 0 else (set(pol["anchors"]) | gen.trusted)
        gen_revoked = set(gen.revoked)
        rings.append({"path": gen.pubring, "revoked": gen.revoked, "allowed": allowed})
    if with_floor:
        if pol["min_certs"] > 0:
            rings.append({"path": lambda: (_arch_floor_ring(shipped) or (None,))[0], "revoked": gen_revoked, "allowed": None})
        else:
            floor = os.path.join(shipped, pol["floor_file"])
            if not _file_safety(floor):
                rings.append({"path": floor, "revoked": gen_revoked, "allowed": set(pol["floor_pins"])})
    return rings, ("" if rings else "no keyring installed")


# --- [ KEYRING PACKAGE ] ---

def _unzstd_capped(path: str) -> bytes:
    """Decompress a .zst file with the stock `zstd`, at most MAX_UNPACKED bytes out (a bomb is refused)."""
    try:
        p = subprocess.Popen(["zstd", "-d", "-c", "-q", "--", path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                             env=_clean_env())
    except FileNotFoundError:
        raise Refusal(Refusal.NO_TOOLS, "zstd is not installed")
    assert p.stdout is not None
    data = p.stdout.read(MAX_UNPACKED + 1)
    if len(data) > MAX_UNPACKED:
        p.kill()
    p.stdout.close()
    rc = p.wait()
    if len(data) > MAX_UNPACKED:
        raise Refusal(Refusal.MALFORMED, "the keyring package unpacks to an unreasonable size")
    if rc != 0:
        raise Refusal(Refusal.MALFORMED, "zstd could not unpack the keyring package")
    return data


def _norm_member(name: str) -> str:
    while name.startswith("./"):
        name = name[2:]
    return name


def _read_package(pol: Dict[str, Any], pkg_file: str) -> Dict[str, Any]:
    """Read .PKGINFO and the three key files from a keyring package. Refuses anything that is not what such a
    package looks like."""
    bad = lambda m: Refusal(Refusal.MALFORMED, m)  # noqa: E731
    import io
    with open(pkg_file, "rb") as fh:
        head = fh.read(4)
    try:
        if head == b"\x28\xb5\x2f\xfd":
            tf = tarfile.open(fileobj=io.BytesIO(_unzstd_capped(pkg_file)), mode="r:")
        else:
            tf = tarfile.open(pkg_file, mode="r:*")
    except (tarfile.TarError, OSError, EOFError):
        raise bad("not a readable archive")
    ring_f, trusted_f, revoked_f = pol["files"]
    wanted = {PKG_KEYRING_DIR + f: f for f in (ring_f, trusted_f, revoked_f)}
    found: Dict[str, bytes] = {}
    try:
        with tf:
            for m in tf:
                n = _norm_member(m.name)
                if n != ".PKGINFO" and n not in wanted:
                    continue
                if not m.isreg():
                    raise bad("a key file is not a regular file")
                if m.size > MAX_ENTRY:
                    raise bad("a key file is unreasonably large")
                if n in found:
                    raise bad("a key file appears twice")
                src = tf.extractfile(m)
                if src is None:
                    raise bad("unreadable key file")
                found[n] = src.read(MAX_ENTRY + 1)
    except (tarfile.TarError, OSError, EOFError):
        raise bad("corrupt archive")
    info = found.get(".PKGINFO")
    if info is None:
        raise bad("no .PKGINFO")
    fields: Dict[str, str] = {}
    for line in info.decode("utf-8", "replace").splitlines():
        k, sep, v = line.partition("=")
        if sep and k.strip() and k.strip() not in fields:
            fields[k.strip()] = v.strip()
    if fields.get("pkgname") != pol["pkgname"]:
        raise bad("the package is not the expected keyring")
    pkgver = fields.get("pkgver", "")
    key = _parse_pkgver(pkgver)
    if key is None:
        raise bad("unreadable pkgver")
    try:
        builddate = int(fields.get("builddate", ""))
    except ValueError:
        raise bad("no build date")
    if builddate < 0:
        raise bad("no build date")
    if PKG_KEYRING_DIR + ring_f not in found or PKG_KEYRING_DIR + trusted_f not in found:
        raise bad("the ring or the trusted list is missing")
    rv = found.get(PKG_KEYRING_DIR + revoked_f)
    return {"pkgver": pkgver, "pkgver_key": key, "builddate": builddate,
            "ring": found[PKG_KEYRING_DIR + ring_f],
            "trusted": found[PKG_KEYRING_DIR + trusted_f].decode("utf-8", "replace"),
            "revoked": rv.decode("utf-8", "replace") if rv is not None else None}


# --- [ KEYRING PACKAGE: GPG INSPECTION ] ---

def _inspect_ring(home: str, ring: bytes) -> Dict[str, Any]:
    if not shutil.which("gpg") or not shutil.which("gpgv"):
        raise Refusal(Refusal.NO_TOOLS, "gpg or gpgv is not installed")
    try:
        data = dearmor(ring) if ring.startswith(b"-----BEGIN PGP") else ring
    except Exception:
        raise Refusal(Refusal.MALFORMED, "the ring is not valid OpenPGP armor")
    imp = _gpg(home, ["--import", "--import-options", "import-local-sigs"], stdin=data)
    if imp.returncode not in (0, 2):     # 2 = some keys had problems; the keys that did import are usable
        raise Refusal(Refusal.MALFORMED, "gpg could not import the ring")
    lst = _gpg(home, ["--with-colons", "--fixed-list-mode", "--check-sigs"])
    if lst.returncode != 0 and not lst.stdout:
        raise Refusal(Refusal.MALFORMED, "gpg could not list the ring")
    colons = lst.stdout.decode("utf-8", "replace")
    present: Set[str] = set()
    validity: Dict[str, str] = {}
    pending: Optional[str] = None
    for line in colons.splitlines():
        f = line.split(":")
        if f[0] == "pub":
            pending = f[1] if len(f) > 1 else ""
        elif f[0] == "fpr" and pending is not None and len(f) > 9:
            fp = f[9].upper()
            present.add(fp)
            validity[fp] = pending
            pending = None
    return {"colons": colons, "present": present, "validity": validity}


def _export(home: str, fprs: Set[str]) -> bytes:
    if not fprs:
        raise Refusal(Refusal.MALFORMED, "no accepted keys to export")
    exp = _gpg(home, ["--export", "--export-options", "export-minimal"] + sorted(fprs))
    if exp.returncode != 0 or not exp.stdout:
        raise Refusal(Refusal.MALFORMED, "gpg could not export the accepted keys")
    return exp.stdout


def evaluate_accepted(colons: str, anchors: Any, revoked: Set[str], min_certs: int) -> Tuple[Set[str], Dict[str, int]]:
    """Accepted primary fingerprints: the anchors themselves, plus (min_certs > 0) keys with at least `min_certs`
    valid certifications by anchors that no anchor revoked. Revoked keys never count. Returns (accepted, counts)."""
    anchors = {a.upper() for a in anchors}
    by_kid = {a[-16:]: a for a in anchors}
    certs: Dict[str, Set[str]] = {}
    revcerts: Dict[str, Set[str]] = {}
    key_valid: Dict[str, str] = {}
    cur: Optional[str] = None
    expect_fpr = False
    in_sub = False
    pending = ""
    for line in colons.splitlines():
        f = line.split(":")
        rec = f[0]
        if rec == "pub":
            cur, expect_fpr, in_sub = None, True, False
            pending = f[1] if len(f) > 1 else ""
            continue
        if rec == "sub":
            in_sub = True
            continue
        if rec == "fpr" and expect_fpr:
            cur = (f[9] if len(f) > 9 else "").upper()
            key_valid[cur] = pending
            certs.setdefault(cur, set())
            revcerts.setdefault(cur, set())
            expect_fpr = False
            continue
        if cur is None or in_sub or rec not in ("sig", "rev") or len(f) < 5 or f[1] != "!":
            continue
        kid = f[4].upper()
        cls = f[10][:2].lower() if len(f) > 10 else ""
        issuer = f[12].upper() if len(f) > 12 and f[12] else by_kid.get(kid, "")
        if issuer not in anchors:
            continue
        if rec == "sig" and cls in ("10", "11", "12", "13"):
            certs[cur].add(issuer)
        elif rec == "rev" and cls == "30":
            revcerts[cur].add(issuer)
    accepted: Set[str] = set()
    counts: Dict[str, int] = {}
    for fpr, signers in certs.items():
        if fpr in revoked or key_valid.get(fpr) == "r":
            continue
        n = len(signers - revcerts.get(fpr, set()))
        counts[fpr] = n
        if fpr in anchors or (min_certs > 0 and n >= min_certs):
            accepted.add(fpr)
    return accepted, counts


# --- [ KEYRING PACKAGE: THE RULES (read-only; user and root share this) ] ---

@dataclass
class KeyringUpdate:
    """A keyring package that passed every rule. Everything the root phase writes is in here."""
    family: str
    pkgver: str
    pkgver_key: Tuple[int, int]
    builddate: int
    package_name: str
    signer: str
    via: str                       # "continuity" or "master_path"
    bootstrap: bool
    pubring: bytes
    revoked: Set[str]
    trusted: Set[str]
    anchors: List[str]
    dynamic_anchors: Set[str]
    vouched: Set[str]
    added: Set[str] = field(default_factory=set)
    removed: Set[str] = field(default_factory=set)


def _current_ring(pol: Dict[str, Any], cur: Optional[Generation], shipped: str) -> Optional[Dict[str, Any]]:
    """The ring in force NOW for continuity: the generation, else the shipped snapshot (the floor)."""
    if cur is not None:
        return {"path": cur.pubring, "revoked": cur.revoked, "allowed": None}
    if pol["min_certs"] > 0:
        fl = _arch_floor_ring(shipped)
        return {"path": fl[0], "revoked": fl[1], "allowed": None} if fl else None
    floor = os.path.join(shipped, pol["floor_file"])
    if _file_safety(floor):
        return None
    return {"path": floor, "revoked": set(), "allowed": set(pol["floor_pins"])}


def verify_keyring_package(family: str, pkg: bytes, sig: bytes, keys_root: str = KEYS_ROOT,
                           now: Optional[float] = None, shipped_dir: Optional[str] = None
                           ) -> Tuple[str, Optional[KeyringUpdate]]:
    """Check a keyring package against the store and the compiled anchors. Reads the store, writes nothing.
    Returns ("uptodate", None) or ("update", KeyringUpdate); raises Refusal when any rule fails.

    Rules (spec section 4): 1 the .sig is required, the package is the family's, the build date is not in the future;
    2 monotonic: (pkgver, rel) and build date never older than the generation in force, equal = nothing to do;
    3 every compiled anchor is in -trusted, in the ring, not revoked, not revoked inside the ring; 4 the -revoked list
    may only grow; 5 continuity (the signature verifies against the ring in force) or else the master path (the signer
    is accepted under the compiled anchors in the NEW ring); 6 pinned families: the signer is a compiled anchor, keys in
    -trusted are then vouched; Arch: keys in -trusted with >= 3 anchor certifications become dynamic anchors."""
    if family not in TRUST_PINS:
        raise Refusal(Refusal.MALFORMED, f"unknown family {family}")
    pol = policy(family)
    shipped = shipped_dir if shipped_dir is not None else default_shipped_dir()
    now_ts = int(now if now is not None else time.time())
    if not sig or len(sig) > MAX_SIG_BYTES:
        raise Refusal(Refusal.NO_SIGNATURE, "the keyring package has no usable signature")
    if not pkg or len(pkg) > MAX_PKG_BYTES:
        raise Refusal(Refusal.MALFORMED, "the keyring package has an unreasonable size")
    sig = dearmor(sig)
    pins = set(pol["anchors"])
    with tempfile.TemporaryDirectory(prefix="gnomes-keyring-") as work:
        os.chmod(work, 0o700)
        pkg_path = os.path.join(work, "keyring.pkg")
        sig_path = os.path.join(work, "keyring.sig")
        with open(pkg_path, "wb") as f:
            f.write(pkg)
        with open(sig_path, "wb") as f:
            f.write(sig)
        kp = _read_package(pol, pkg_path)
        if kp["builddate"] > now_ts + FUTURE_SKEW_SECONDS:
            raise Refusal(Refusal.MALFORMED, "the keyring package claims a build date in the future")
        cur, why = locate_generation(family, keys_root)
        if why:
            raise Refusal(Refusal.STORE, why)

        # rule 2: monotonic
        if cur is not None:
            cp = cur.pkgver_key()
            if cp is not None:
                if kp["pkgver_key"] < cp:
                    raise Refusal(Refusal.OLDER, f"package {kp['pkgver']} is older than {cur.meta.get('pkgver', cp)}")
                if kp["pkgver_key"] == cp:
                    return "uptodate", None
            if cur.builddate() > 0 and kp["builddate"] < cur.builddate():
                raise Refusal(Refusal.OLDER, "the build date is older than the one in force")

        # rules 3 and 4: lists
        trusted_list = _parse_fprs(kp["trusted"])
        revoked_new = _parse_fprs(kp["revoked"] or "")
        cur_revoked = set(cur.revoked) if cur is not None else set()
        lost = sorted(cur_revoked - revoked_new)
        if lost:
            raise Refusal(Refusal.REVOKED_STRIPPED, f"the new revoked list no longer names {lost[0]}")
        miss = sorted(pins - trusted_list)
        if miss:
            raise Refusal(Refusal.ANCHOR_MISSING, f"pinned key {miss[0]} is not in the trusted list")
        dead = sorted(pins & revoked_new)
        if dead:
            raise Refusal(Refusal.ANCHOR_REVOKED, f"pinned key {dead[0]} is on the revoked list")

        with _private_gnupghome() as home:
            ins = _inspect_ring(home, kp["ring"])
            absent = sorted(pins - ins["present"])
            if absent:
                raise Refusal(Refusal.ANCHOR_MISSING, f"pinned key {absent[0]} is not in the ring")
            cur_dyn = cur.dynamic_anchors() if cur is not None else set()
            # pass 1: accepted under the anchors in force NOW (compiled pins + dynamic ones)
            acc1, counts1 = evaluate_accepted(ins["colons"], pins | cur_dyn, revoked_new, pol["min_certs"])
            gone = sorted(pins - acc1)
            if gone:
                raise Refusal(Refusal.ANCHOR_REVOKED, f"pinned key {gone[0]} is revoked inside the ring")

            dynamic: Set[str] = set()
            vouched: Set[str] = set()

            def usable_master(k: str) -> bool:
                return k in ins["present"] and k not in revoked_new and ins["validity"].get(k, "") not in ("r", "e", "i", "d")

            if pol["min_certs"] > 0:
                for k in sorted(trusted_list - pins):
                    if usable_master(k) and (k in cur_dyn or counts1.get(k, 0) >= pol["min_certs"]):
                        dynamic.add(k)
            elif pol["vouch"]:
                for k in sorted(trusted_list - pins):
                    if k in ins["present"] and k not in revoked_new and ins["validity"].get(k, "") != "r":
                        vouched.add(k)
            if pol["min_certs"] > 0:
                final, _ = evaluate_accepted(ins["colons"], pins | dynamic, revoked_new, pol["min_certs"])
            else:
                final = set(acc1) | vouched

            # rule 5: Path A (continuity), then Path B (the signer is accepted under the compiled anchors in the new ring)
            tried: List[str] = []
            verdict: Optional[TrustResult] = None
            via = ""
            ring = _current_ring(pol, cur, shipped)
            if ring is not None:
                v = check_rings([ring], pkg_path, sig, name=pol["pkgname"], family=family)
                if v.ok:
                    verdict, via = v, "continuity"
                else:
                    tried.append(f"current ring: {v.status} {v.detail}")
            if verdict is None:
                base = _export(home, acc1)
                base_path = os.path.join(work, "base.gpg")
                with open(base_path, "wb") as f:
                    f.write(base)
                v = check_rings([{"path": base_path, "revoked": revoked_new,
                                  "allowed": pins if pol["min_certs"] == 0 else None}],
                                pkg_path, sig, name=pol["pkgname"], family=family)
                if v.ok:
                    verdict, via = v, "master_path"
                else:
                    tried.append(f"new ring under the pinned anchors: {v.status} {v.detail}")
            if verdict is None:
                raise Refusal(Refusal.CHAIN_BROKEN, "; ".join(tried))
            signer = verdict.key_fpr.upper()
            if signer in revoked_new:
                raise Refusal(Refusal.CHAIN_BROKEN, "the package is signed by a key its own revoked list names")
            # rule 6 (pinned families): a pinned key must have signed it
            if pol["min_certs"] == 0 and signer not in pins:
                raise Refusal(Refusal.SIGNER_NOT_PINNED, f"signed by {signer}, which is not a pinned key")
            export = _export(home, final)

    old_extra = (cur.dynamic_anchors() | {str(k).upper() for k in cur.meta.get("vouched", []) or []}) if cur is not None else set()
    new_extra = dynamic | vouched
    return "update", KeyringUpdate(
        family=family, pkgver=kp["pkgver"], pkgver_key=kp["pkgver_key"], builddate=kp["builddate"],
        package_name=f"{pol['pkgname']}-{kp['pkgver']}-any.pkg.tar.zst", signer=signer, via=via,
        bootstrap=cur is None, pubring=export, revoked=revoked_new, trusted=set(final), anchors=list(pol["anchors"]),
        dynamic_anchors=dynamic, vouched=vouched, added=new_extra - old_extra, removed=old_extra - new_extra)


# --- [ FLIGHT RECORDER (category SUPPLY / MIRROR; spec section 7 format) ] ---

RECORDER_PATH: Optional[str] = None     # tests set this; None = the app's own location
RECORDER_MAX = 16 * 1024 * 1024


def _recorder_path() -> Optional[str]:
    if RECORDER_PATH:
        return RECORDER_PATH
    if os.geteuid() == 0:
        return "/var/log/slacky-update/spidersense.log"
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return os.path.join(base, "slacky-update", "spidersense.log")


def flight_record(cat: str, lvl: str, ev: str, msg: str, data: Optional[Dict[str, Any]] = None) -> None:
    """One JSON line, silent, never raises. Root writes the system log only (never a file under a home folder)."""
    p = _recorder_path()
    if not p:
        return
    try:
        d = os.path.dirname(p)
        os.makedirs(d, mode=0o755, exist_ok=True)
        try:
            if os.path.getsize(p) > RECORDER_MAX:
                os.replace(p, p + ".1")
        except OSError:
            pass
        rec: Dict[str, Any] = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "app": "legacy", "cat": cat,
                               "lvl": lvl, "ev": ev, "msg": msg}
        if data:
            rec["d"] = data
        line = (json.dumps(rec, sort_keys=True) + "\n").encode("utf-8")
        if len(line) > 3900:
            rec.pop("d", None)
            rec["msg"] = str(rec["msg"])[:300]
            line = (json.dumps(rec, sort_keys=True) + "\n").encode("utf-8")
        fd = os.open(p, os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC, 0o644)
        try:
            os.write(fd, line)
        finally:
            os.close(fd)
    except Exception:
        pass


def _record_update(u: KeyringUpdate, ev: str) -> None:
    flight_record("SUPPLY", "INFO", ev, f"{u.family} keyring {u.pkgver} ({u.via})",
                  {"family": u.family, "pkgver": u.pkgver, "signer": u.signer, "via": u.via, "accepted": len(u.trusted)})
    if u.added or u.removed:
        flight_record("SUPPLY", "WARN", "key.anchor_set_changed",
                      f"{u.family} anchor set changed: +{len(u.added)} -{len(u.removed)}",
                      {"family": u.family, "added": sorted(u.added), "removed": sorted(u.removed), "pkgver": u.pkgver})


def record_refusal(family: str, r: Refusal) -> None:
    flight_record("SUPPLY", "VETO", "key.rejected", f"{family} keyring refused: {r.kind}",
                  {"family": family, "reason": r.kind, "detail": r.detail})


# --- [ KEYRING STORE: WRITER (root phase) ] ---

def _check_owned_dir(fd: int, name: str) -> None:
    st = os.fstat(fd)
    if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.geteuid() or st.st_mode & 0o022:
        raise Refusal(Refusal.STORE, f"{name} is not a real folder owned by the root phase")


def _dir_at(parent_fd: int, name: str, create: bool) -> int:
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
    try:
        fd = os.open(name, flags, dir_fd=parent_fd)
    except FileNotFoundError:
        if not create:
            raise Refusal(Refusal.STORE, f"{name}: missing")
        try:
            os.mkdir(name, 0o755, dir_fd=parent_fd)
            fd = os.open(name, flags, dir_fd=parent_fd)
            os.fchmod(fd, 0o755)
        except OSError as e:
            raise Refusal(Refusal.STORE, f"{name}: {e}")
    except OSError as e:
        raise Refusal(Refusal.STORE, f"{name}: {e}")
    try:
        _check_owned_dir(fd, name)
    except Refusal:
        os.close(fd)
        raise
    return fd


def _create_file_at(dir_fd: int, name: str, data: bytes) -> None:
    try:
        fd = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o644, dir_fd=dir_fd)
    except OSError as e:
        raise Refusal(Refusal.STORE, f"create {name}: {e}")
    try:
        _write_all(fd, data)
        os.fchmod(fd, 0o644)
        os.fsync(fd)
    except OSError as e:
        raise Refusal(Refusal.STORE, f"write {name}: {e}")
    finally:
        os.close(fd)


def _write_all(fd: int, data: bytes) -> None:
    view = memoryview(data)
    while view:
        n = os.write(fd, view)
        view = view[n:]


def _remove_gen_at(fam_fd: int, name: str) -> None:
    try:
        d = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=fam_fd)
    except OSError:
        return
    try:
        for f in GEN_FILES:
            try:
                os.unlink(f, dir_fd=d)
            except OSError:
                pass
    finally:
        os.close(d)
    try:
        os.rmdir(name, dir_fd=fam_fd)    # only a folder that held nothing but our files goes away
    except OSError:
        pass


def _swap_link(fam_fd: int, link_name: str, target: str) -> None:
    tmp = f".{link_name}.{os.getpid()}"
    try:
        os.unlink(tmp, dir_fd=fam_fd)
    except OSError:
        pass
    try:
        os.symlink(target, tmp, dir_fd=fam_fd)
        os.rename(tmp, link_name, src_dir_fd=fam_fd, dst_dir_fd=fam_fd)
    except OSError as e:
        raise Refusal(Refusal.STORE, f"swap {link_name}: {e}")


def _meta_for(u: KeyringUpdate, stamp: str) -> Dict[str, Any]:
    return {"family": u.family, "keyring_pkg": u.package_name, "signed_by": u.signer, "anchors": sorted(u.anchors),
            "accepted": len(u.trusted), "revoked": len(u.revoked), "vouched": sorted(u.vouched), "built": stamp,
            "mode": "bootstrap" if u.bootstrap else "refresh", "pkgver": u.pkgver, "builddate": u.builddate,
            "dynamic_anchors": sorted(u.dynamic_anchors), "via": u.via, "writer": WRITER}


def _write_generation(fam_fd: int, u: KeyringUpdate, now: float) -> str:
    stamp = time.strftime("%Y%m%d%H%M%S", time.gmtime(now))

    def exists(n: str) -> bool:
        try:
            os.stat(n, dir_fd=fam_fd, follow_symlinks=False)
            return True
        except OSError:
            return False

    name, n = f"gen.{stamp}", 1
    while exists(name):
        n += 1
        name = f"gen.{stamp}-{n}"
    tmp = f"{name}.tmp.{os.getpid()}"
    _remove_gen_at(fam_fd, tmp)
    try:
        os.mkdir(tmp, 0o755, dir_fd=fam_fd)
    except OSError as e:
        raise Refusal(Refusal.STORE, f"create {tmp}: {e}")
    d = -1
    try:
        d = _dir_at(fam_fd, tmp, False)
        os.fchmod(d, 0o755)
        lst = lambda s: "".join(k + "\n" for k in sorted(s)).encode()  # noqa: E731
        _create_file_at(d, "pubring.gpg", u.pubring)
        _create_file_at(d, "revoked", lst(u.revoked))
        _create_file_at(d, "trusted", lst(u.trusted))
        _create_file_at(d, "meta.json", json.dumps(_meta_for(u, stamp), indent=1, sort_keys=True).encode())
        os.fsync(d)
        os.rename(tmp, name, src_dir_fd=fam_fd, dst_dir_fd=fam_fd)
    except (Refusal, OSError) as e:
        if d >= 0:
            os.close(d)
            d = -1
        _remove_gen_at(fam_fd, tmp)
        raise e if isinstance(e, Refusal) else Refusal(Refusal.STORE, f"publish {name}: {e}")
    finally:
        if d >= 0:
            os.close(d)
    try:
        old_target = os.readlink("current", dir_fd=fam_fd)
    except OSError:
        old_target = None
    if old_target is not None and not _GEN_RE.match(old_target):
        old_target = None
    _swap_link(fam_fd, "current", name)
    if old_target:
        _swap_link(fam_fd, "previous", old_target)
    os.fsync(fam_fd)
    # keep `current` and `previous` only (the shared format); never touch anything that is not a plain generation
    keep = {name} | ({old_target} if old_target else set())
    for g in os.listdir(fam_fd):
        if _GEN_RE.match(g) and g not in keep:
            _remove_gen_at(fam_fd, g)
    return name


def _lock_family(fam_fd: int) -> None:
    """Exclusive lock on the family folder, held until the descriptor is closed; waits up to 10 seconds."""
    for _ in range(LOCK_WAIT_STEPS):
        try:
            fcntl.flock(fam_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return
        except OSError as e:
            if e.errno not in (errno.EAGAIN, errno.EACCES):
                raise Refusal(Refusal.STORE, f"lock: {e}")
            time.sleep(0.05)
    raise Refusal(Refusal.STORE, "another key update is running")


def install_keyring(family: str, pkg: bytes, sig: bytes, keys_root: str = KEYS_ROOT, now: Optional[float] = None,
                    shipped_dir: Optional[str] = None) -> Tuple[str, Optional[str], Optional[KeyringUpdate]]:
    """Root phase: verify the raw bytes again from scratch against the store and write a new generation, under an
    exclusive lock on the family folder (two writers cannot both pass the monotonic check). Nothing here calls sudo;
    the caller is already root. Returns ("uptodate", None, None) or ("written", generation name, update).
    Raises Refusal (also recorded) with nothing changed."""
    root_fd = fam_fd = -1
    try:
        try:
            os.makedirs(os.path.dirname(keys_root.rstrip("/")) or "/", mode=0o755, exist_ok=True)
            if not os.path.lexists(keys_root):
                os.mkdir(keys_root, 0o755)
                os.chmod(keys_root, 0o755)
            root_fd = os.open(keys_root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
        except OSError as e:
            raise Refusal(Refusal.STORE, f"{keys_root}: {e}")
        _check_owned_dir(root_fd, keys_root)
        fam_fd = _dir_at(root_fd, family, True)
        _lock_family(fam_fd)
        outcome, upd = verify_keyring_package(family, pkg, sig, keys_root, now, shipped_dir)
        if outcome == "uptodate" or upd is None:
            return "uptodate", None, None
        gen = _write_generation(fam_fd, upd, now if now is not None else time.time())
        _record_update(upd, "key.installed")
        return "written", gen, upd
    except Refusal as r:
        record_refusal(family, r)
        raise
    finally:
        for fd in (fam_fd, root_fd):
            if fd >= 0:
                try:
                    os.close(fd)
                except OSError:
                    pass


def build_keyring(family: str, pkg_path: str, sig_path: str, keys_root: str = KEYS_ROOT,
                  bootstrap: bool = False, now: Optional[float] = None,
                  shipped_dir: Optional[str] = None) -> TrustResult:
    """Keyring refresh from a downloaded `<family>-keyring` package (see verify_keyring_package for the rules). Never
    raises; the result carries extra["kind"] = "keyring". `bootstrap` is accepted for old callers: with no ring at all
    the master path is the bootstrap, so it is no longer needed."""
    base = dict(name=family, family=family)
    try:
        with open(pkg_path, "rb") as f:
            pkg = f.read(MAX_PKG_BYTES + 1)
        try:
            with open(sig_path, "rb") as f:
                sig = f.read(MAX_SIG_BYTES + 1)
        except OSError:
            sig = b""
        outcome, gen, upd = install_keyring(family, pkg, sig, keys_root, now, shipped_dir)
        if outcome == "uptodate":
            res = TrustResult("good", detail="the keys in force are already this version", **base)
            res.extra["uptodate"] = True
        else:
            assert upd is not None
            res = TrustResult("good", key_fpr=upd.signer, detail=f"{len(upd.trusted)} keys accepted, {len(upd.revoked)} revoked",
                              extra={"generation": os.path.join(keys_root, family, str(gen)), "anchors": sorted(upd.anchors),
                                     "via": upd.via}, **base)
    except Refusal as r:
        res = TrustResult(r.status(), detail=f"{r.kind}: {r.detail}", extra={"refusal": r.kind}, **base)
    except Exception as e:
        res = TrustResult("error", detail=f"{type(e).__name__}: {e}", **base)
    res.extra["kind"] = "keyring"
    return res


# --- [ KEYRING STAGING (user phase) ] ---

def _write_private(p: str, data: bytes) -> None:
    d = os.path.dirname(p)
    fd, tmp = tempfile.mkstemp(prefix=".stage.", dir=d)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, 0o600)
        os.replace(tmp, p)
    except BaseException:
        with contextlib.suppress(OSError):
            os.unlink(tmp)
        raise


def stage_keyring(family: str, pkg: bytes, sig: bytes, stage_dir: str, keys_root: str = KEYS_ROOT,
                  now: Optional[float] = None, shipped_dir: Optional[str] = None) -> str:
    """User phase: verify a downloaded keyring package and, when it passes and is newer, keep it in
    <stage_dir>/<family>/{pkg,sig,verdict.json} (0700 / 0600, the user's own cache). The staged bytes are only an
    optimisation: the root phase checks them again from scratch. Returns "staged" or "uptodate"; raises Refusal."""
    try:
        outcome, upd = verify_keyring_package(family, pkg, sig, keys_root, now, shipped_dir)
    except Refusal as r:
        record_refusal(family, r)
        raise
    if outcome == "uptodate" or upd is None:
        return "uptodate"
    d = os.path.join(stage_dir, family)
    try:
        os.makedirs(d, mode=0o700, exist_ok=True)
        os.chmod(d, 0o700)
        verdict = {"family": family, "pkgver": upd.pkgver, "builddate": upd.builddate, "signer": upd.signer,
                   "via": upd.via, "sha256": hashlib.sha256(pkg).hexdigest(), "staged_ts": int(now or time.time())}
        _write_private(os.path.join(d, "pkg"), pkg)
        _write_private(os.path.join(d, "sig"), sig)
        _write_private(os.path.join(d, "verdict.json"), json.dumps(verdict, indent=1, sort_keys=True).encode())
    except OSError as e:
        raise Refusal(Refusal.STORE, str(e))
    _record_update(upd, "key.staged")
    return "staged"


def read_staged(stage_dir: str, family: str, owner_uid: int) -> Tuple[bytes, bytes]:
    """Read a staged package and signature without following links; the files must be regular and owned by
    `owner_uid` (the user who staged them). Returns raw bytes only; the caller hands them to install_keyring."""
    d = os.path.join(stage_dir, family)

    def read(name: str, cap: int) -> bytes:
        try:
            fd = os.open(os.path.join(d, name), os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
        except OSError as e:
            raise Refusal(Refusal.STORE, f"staged {name}: {e}")
        with os.fdopen(fd, "rb") as f:
            st = os.fstat(f.fileno())
            if not stat.S_ISREG(st.st_mode) or st.st_uid != owner_uid:
                raise Refusal(Refusal.STORE, f"staged {name} is not a regular file of the staging user")
            data = f.read(cap + 1)
        if len(data) > cap:
            raise Refusal(Refusal.STORE, f"staged {name} is unreasonably large")
        return data

    return read("pkg", MAX_PKG_BYTES), read("sig", MAX_SIG_BYTES)


def install_staged(stage_dir: str, owner_uid: int, families: Optional[List[str]] = None, keys_root: str = KEYS_ROOT,
                   now: Optional[float] = None, shipped_dir: Optional[str] = None) -> List[Dict[str, Any]]:
    """Root phase of a full update (the FIRST step, before any package is verified or installed): install what the user
    phase staged. Every family is re-verified from the raw bytes; nothing staged = nothing to do. Returns one dict
    per staged family: {"family", "outcome": written|uptodate|refused, "sentence"?}."""
    out: List[Dict[str, Any]] = []
    for fam in (families or list(TRUST_PINS)):
        if not os.path.lexists(os.path.join(stage_dir, fam)):
            continue
        try:
            pkg, sig = read_staged(stage_dir, fam, owner_uid)
            outcome, gen, upd = install_keyring(fam, pkg, sig, keys_root, now, shipped_dir)
            out.append({"family": fam, "outcome": "written" if outcome == "written" else "uptodate",
                        "generation": gen})
        except Refusal as r:
            record_refusal(fam, r)
            out.append({"family": fam, "outcome": "refused", "kind": r.kind, "sentence": r.sentence(fam)})
    return out


# --- [ ENFORCE: CHECKSUM, KEY REFRESH AND ONE RETRY (6A-275) ] ---

REFRESH_HOOK: Optional[Any] = None     # tests: callable(family) replaces the real key refresh
_REFRESHED: Set[str] = set()           # families whose keys were already refreshed in this process (once is enough)
REFRESHABLE = ("nokey", "expired")     # failures that a newer keyring can fix; bad, unsigned and error cannot be


def check_sha256(path: str, expected: str, name: str = "", repo: str = "") -> Optional[TrustResult]:
    """The repo database %SHA256SUM% against the file about to be unpacked. None when it matches or the entry has no
    checksum (that case is only logged by the caller); a "bad" result when it does not (or the file cannot be read)."""
    want = str(expected or "").strip().lower()
    if not want:
        return None
    h = hashlib.sha256()
    try:
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(131072), b""):
                h.update(chunk)
    except OSError:
        pass
    else:
        if h.hexdigest() == want:
            return None
    return TrustResult("bad", detail="the file does not match the checksum in the repository database",
                       name=name or os.path.basename(path), repo=repo, family=repo_family(repo) or "",
                       extra={"sha_mismatch": True})


def default_stage_dir() -> Optional[str]:
    """Where the key refresh stages a verified newer keyring (the sentinel's folder in the user's own cache); None for
    root, which never reads a user cache."""
    if os.geteuid() == 0:
        return None
    env = os.environ.get("SLACKY_MIRROR_CACHE_DIR")
    base = os.path.join(env, "sentinel") if env else os.path.join(
        os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "slacky-update", "sentinel")
    return os.path.join(base, "keyring_stage")


def refresh_family_keys(family: str) -> bool:
    """Ask the existing signed keyring refresh (slacky_sentinel.keys_check: downloads a listed newer keyring and stages
    it after every rule passed) to run, at most once per family and process. True when it was run now."""
    if family in _REFRESHED:
        return False
    _REFRESHED.add(family)
    hook = REFRESH_HOOK
    try:
        if hook is not None:
            hook(family)
        else:
            import importlib.util
            mod = sys.modules.get("slacky_sentinel")
            if mod is None:
                path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "slacky_sentinel.py")
                spec = importlib.util.spec_from_file_location("slacky_sentinel", path)
                if not spec or not spec.loader:
                    return False
                mod = importlib.util.module_from_spec(spec)
                sys.modules["slacky_sentinel"] = mod
                spec.loader.exec_module(mod)
            mod.keys_check()
    except Exception as e:
        flight_record("SUPPLY", "WARN", "trust.refresh_failed", f"{family} key refresh did not run", {"error": str(e)[:200]})
        return True
    flight_record("SUPPLY", "INFO", "trust.refresh", f"{family} keys refreshed before a retry", {"family": family})
    return True


def settle_stale(items: List[Tuple[TrustResult, Dict[str, Any]]], mode: Optional[str] = None,
                 keys_root: str = KEYS_ROOT, shipped_dir: Optional[str] = None,
                 stage_dir: Optional[str] = None) -> List[TrustResult]:
    """Enforce mode only. Every result that failed because the keys are missing or too old ("nokey", "expired") gets ONE
    key refresh per family and ONE retry, checked against the keyring staged by the refresh (all keyring rules re-run
    on its raw bytes) as well as the keys in force. What still fails is marked extra["refreshed"] so the sentence says
    so. Input: [(result, {"path", "sig", "repo", "name", "pgpsig"})]. Returns the final results in the same order."""
    out = [r for r, _ in items]
    if trust_mode(mode) != "enforce":
        return out
    stale = [i for i, (r, _) in enumerate(items) if r.status in REFRESHABLE and r.family and not r.ok]
    if not stale:
        return out
    stage = stage_dir if stage_dir is not None else default_stage_dir()
    for fam in sorted({items[i][0].family for i in stale}):
        refresh_family_keys(fam)
        idx = [i for i in stale if items[i][0].family == fam]
        with tempfile.TemporaryDirectory(prefix="gnomes-retry-") as work:
            os.chmod(work, 0o700)
            extra_ring: Optional[Dict[str, Any]] = None
            if stage:
                try:
                    pkg, sig = read_staged(stage, fam, os.geteuid())
                    outcome, upd = verify_keyring_package(fam, pkg, sig, keys_root, None, shipped_dir)
                    if outcome == "update" and upd is not None:
                        rp = os.path.join(work, "staged.gpg")
                        with open(rp, "wb") as f:
                            f.write(upd.pubring)
                        pol = policy(fam)
                        extra_ring = {"path": rp, "revoked": set(upd.revoked),
                                      "allowed": None if pol["min_certs"] > 0 else (set(pol["anchors"]) | set(upd.trusted))}
                except (Refusal, OSError, ValueError):
                    extra_ring = None
            for i in idx:
                old, inp = items[i]
                rings, _why = reader_rings(fam, keys_root, shipped_dir)
                if extra_ring is not None:
                    rings = [extra_ring] + rings
                sig_b = inp.get("sig")
                if sig_b is None and inp.get("pgpsig"):
                    sig_b = decode_pgpsig(inp["pgpsig"])
                res = old
                if sig_b and rings:
                    try:
                        res = check_rings(rings, inp["path"], sig_b, name=inp.get("name", ""), repo=inp.get("repo", ""),
                                          family=fam)
                    except Exception:
                        res = old
                if res.ok:
                    _note_used_signer(fam, res)
                    flight_record("SUPPLY", "INFO", "trust.retry_ok", f"{inp.get('name', '')} verified after a key refresh",
                                  {"family": fam})
                else:
                    res.extra["refreshed"] = True
                    flight_record("SUPPLY", "VETO", "trust.refused",
                                  f"{inp.get('name', '')} refused: {res.status} after a key refresh",
                                  {"family": fam, "status": res.status, "detail": res.detail})
                out[i] = res
    return out


# --- [ MONOTONIC DATABASE RULE ] ---

def newest_builddate(packages: Dict[str, Dict[str, Any]], now: Optional[float] = None) -> Tuple[int, int]:
    """(newest plausible BUILDDATE, count of entries ignored as too far in the future)."""
    limit = int((now or time.time()) + FUTURE_SKEW_SECONDS)
    newest, skewed = 0, 0
    for p in packages.values():
        try:
            bd = int(str(p.get("BUILDDATE", "0")).strip() or 0)
        except ValueError:
            continue
        if bd > limit:
            skewed += 1
            continue
        newest = max(newest, bd)
    return newest, skewed


def _load_state(path: str) -> Dict[str, Any]:
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def _save_state(path: str, data: Dict[str, Any]) -> None:
    d = os.path.dirname(path) or "."
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".trust_state.", dir=d)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=1, sort_keys=True)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, 0o644)
        os.replace(tmp, path)
    except BaseException:
        with contextlib.suppress(OSError):
            os.unlink(tmp)
        raise


def check_db_monotonic(repo: str, packages: Dict[str, Dict[str, Any]], state_path: str,
                       record: bool = True, now: Optional[float] = None) -> TrustResult:
    """Refuse a repo DB whose newest BUILDDATE is older than the last accepted one (freeze/rollback guard).
    Equal or newer is accepted and (when `record`) stored. An empty DB is "error", never recorded."""
    newest, skewed = newest_builddate(packages, now)
    base = dict(name=repo, repo=repo, family=repo_family(repo) or "")
    if newest <= 0:
        return TrustResult("error", detail="database has no build dates", **base)
    state = _load_state(state_path)
    repos = state.setdefault("repos", {})
    last = int(repos.get(repo, {}).get("newest_builddate", 0) or 0)
    extra = {"newest": newest, "last_accepted": last, "skewed": skewed}
    if newest < last:
        return TrustResult("older", detail=f"newest build {newest} < last accepted {last}", extra=extra, **base)
    if record and newest > last:
        repos[repo] = {"newest_builddate": newest, "accepted_at": int(now or time.time())}
        state["version"] = 1
        _save_state(state_path, state)
    return TrustResult("ok", detail=f"newest build {newest}", extra=extra, **base)


def default_state_path() -> str:
    """Root uses the system cache; a user run uses its own cache (root never trusts ~/.cache)."""
    if os.geteuid() == 0:
        return STATE_PATH_ROOT
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return os.path.join(base, "slacky-update", "gnomes", "trust_state.json")


# --- [ SELF-TEST ] ---

# pacman test/util/vercmptest.sh (pacman master, fetched 2026-10-13 from gitlab.archlinux.org); each case also runs mirrored.
VERCMP_VECTORS: List[Tuple[str, str, int]] = [
    ("1.5.0", "1.5.0", 0), ("1.5.1", "1.5.0", 1),
    ("1.5.1", "1.5", 1),
    ("1.5.0-1", "1.5.0-1", 0), ("1.5.0-1", "1.5.0-2", -1), ("1.5.0-1", "1.5.1-1", -1), ("1.5.0-2", "1.5.1-1", -1),
    ("1.5-1", "1.5.1-1", -1), ("1.5-2", "1.5.1-1", -1), ("1.5-2", "1.5.1-2", -1),
    ("1.5", "1.5-1", 0), ("1.5-1", "1.5", 0), ("1.1-1", "1.1", 0), ("1.0-1", "1.1", -1), ("1.1-1", "1.0", 1),
    ("1.5b-1", "1.5-1", -1), ("1.5b", "1.5", -1), ("1.5b-1", "1.5", -1), ("1.5b", "1.5.1", -1),
    ("1.0a", "1.0alpha", -1), ("1.0alpha", "1.0b", -1), ("1.0b", "1.0beta", -1), ("1.0beta", "1.0rc", -1), ("1.0rc", "1.0", -1),
    ("1.5.a", "1.5", 1), ("1.5.b", "1.5.a", 1), ("1.5.1", "1.5.b", 1),
    ("1.5.b-1", "1.5.b", 0), ("1.5-1", "1.5.b", -1),
    ("2.0", "2_0", 0), ("2.0_a", "2_0.a", 0), ("2.0a", "2.0.a", -1), ("2___a", "2_a", 1),
    ("0:1.0", "0:1.0", 0), ("0:1.0", "0:1.1", -1), ("1:1.0", "0:1.0", 1), ("1:1.0", "0:1.1", 1), ("1:1.0", "2:1.1", -1),
    ("1:1.0", "0:1.0-1", 1), ("1:1.0-1", "0:1.1-1", 1),
    ("0:1.0", "1.0", 0), ("0:1.0", "1.1", -1), ("0:1.1", "1.0", 1), ("1:1.0", "1.0", 1), ("1:1.0", "1.1", 1), ("1:1.1", "1.1", 1),
]


def _selftest_vercmp() -> Tuple[int, List[str]]:
    fails: List[str] = []
    n = 0
    for a, b, exp in VERCMP_VECTORS:
        for x, y, e in ((a, b, exp), (b, a, -exp)):
            n += 1
            got = vercmp(x, y)
            if got != e:
                fails.append(f"vercmp {x} {y}: expected {e}, got {got}")
    return n, fails


def _selftest_signatures() -> Tuple[int, List[str]]:
    """Throwaway key in a private GNUPGHOME: good, bad (flipped byte), unknown key, unsigned, revoked list, PGPSIG."""
    fails: List[str] = []
    n = 0
    if not shutil.which("gpg") or not shutil.which("gpgv"):
        return 0, ["gpg/gpgv not found"]
    with tempfile.TemporaryDirectory(prefix="gnomes-trust-selftest-") as work, \
            _private_gnupghome() as home_a, _private_gnupghome() as home_b:
        os.chmod(work, 0o700)
        for home, uid in ((home_a, "Gnomes Selftest A <a@selftest.invalid>"), (home_b, "Gnomes Selftest B <b@selftest.invalid>")):
            cp = subprocess.run(["gpg", "--homedir", home, "--batch", "--no-tty", "--quiet", "--passphrase", "",
                                 "--pinentry-mode", "loopback", "--quick-gen-key", uid, "ed25519", "sign", "1d"],
                                env=_clean_env(), capture_output=True, timeout=GPG_TIMEOUT, check=False)
            if cp.returncode != 0:
                return 0, [f"cannot create test key: {cp.stderr.decode(errors='replace').strip()[:200]}"]
        pkg = os.path.join(work, "fixture.pkg.tar.zst")
        with open(pkg, "wb") as f:
            f.write(b"\x28\xb5\x2f\xfd" + os.urandom(4096))
        cp = subprocess.run(["gpg", "--homedir", home_a, "--batch", "--no-tty", "--quiet", "--pinentry-mode", "loopback",
                             "--passphrase", "", "--detach-sign", "-o", pkg + ".sig", pkg],
                            env=_clean_env(), capture_output=True, timeout=GPG_TIMEOUT, check=False)
        if cp.returncode != 0:
            return 0, ["cannot sign fixture"]
        with open(pkg + ".sig", "rb") as f:
            sig = f.read()
        ring_a = os.path.join(work, "ring_a.gpg")
        ring_b = os.path.join(work, "ring_b.gpg")
        for home, ring in ((home_a, ring_a), (home_b, ring_b)):
            ex = _gpg(home, ["--export"])
            with open(ring, "wb") as f:
                f.write(ex.stdout)
        fpr_a = [ln.split(":")[9] for ln in _gpg(home_a, ["--with-colons", "--list-keys"]).stdout.decode().splitlines()
                 if ln.startswith("fpr:")][0].upper()
        flipped = os.path.join(work, "flipped.pkg.tar.zst")
        with open(pkg, "rb") as f:
            data = bytearray(f.read())
        data[2048] ^= 0x01
        with open(flipped, "wb") as f:
            f.write(bytes(data))

        def expect(label: str, res: TrustResult, status: str) -> None:
            nonlocal n
            n += 1
            if res.status != status:
                fails.append(f"{label}: expected {status}, got {res.status} ({res.detail})")

        expect("good", verify_detached(pkg, sig, ring_a), "good")
        expect("good fpr", TrustResult("good" if verify_detached(pkg, sig, ring_a).key_fpr == fpr_a else "bad"), "good")
        expect("flipped byte", verify_detached(flipped, sig, ring_a), "bad")
        expect("unknown key", verify_detached(pkg, sig, ring_b), "nokey")
        expect("unsigned", verify_detached(pkg, b"", ring_a), "unsigned")
        expect("revoked list", verify_detached(pkg, sig, ring_a, revoked={fpr_a}), "bad")
        expect("armored sig", verify_detached(pkg, b"-----BEGIN PGP SIGNATURE-----\n\n" + base64.encodebytes(sig)
                                              + b"-----END PGP SIGNATURE-----\n", ring_a), "good")
        expect("garbage sig", verify_detached(pkg, b"\x89\x01\x02garbage", ring_a), "bad")
        expect("issuer parse", TrustResult("good" if sig_issuer(sig) == fpr_a else "bad", detail=sig_issuer(sig)), "good")
        # %PGPSIG% path through verify_package with a fake keys root
        keys = os.path.join(work, "keys")
        gen = os.path.join(keys, "archlinux", "gen.20260101000000")
        os.makedirs(gen)
        shutil.copyfile(ring_a, os.path.join(gen, "pubring.gpg"))
        open(os.path.join(gen, "revoked"), "w").close()
        os.symlink("gen.20260101000000", os.path.join(keys, "archlinux", "current"))
        none_shipped = os.path.join(work, "no-shipped-keys")
        b64 = base64.b64encode(sig).decode()
        expect("PGPSIG good", verify_package(pkg, None, "extra", keys_root=keys, pgpsig_b64=b64, shipped_dir=none_shipped), "good")
        expect("PGPSIG malformed", verify_package(pkg, None, "extra", keys_root=keys, pgpsig_b64="@@not base64@@", shipped_dir=none_shipped), "bad")
        expect("no keyring for family", verify_package(pkg, sig, "cachyos", keys_root=keys, shipped_dir=none_shipped), "nokey")
        expect("unknown repo", verify_package(pkg, sig, "someones-repo", keys_root=keys, shipped_dir=none_shipped), "nokey")
        # mode switch
        r = verify_detached(flipped, sig, ring_a)
        expect("log never blocks", TrustResult("good" if not r.blocks("log") else "bad"), "good")
        expect("enforce blocks", TrustResult("good" if r.blocks("enforce") else "bad"), "good")
        # monotonic DB rule
        st = os.path.join(work, "state.json")
        now = 1_800_000_000.0
        db_new = {"a": {"BUILDDATE": "1700000100"}, "b": {"BUILDDATE": "1700000200"}}
        db_old = {"a": {"BUILDDATE": "1700000100"}}
        db_future = {"a": {"BUILDDATE": str(int(now) + 10 * 86400)}, "b": {"BUILDDATE": "1700000300"}}
        expect("db first", check_db_monotonic("extra", db_new, st, now=now), "ok")
        expect("db same", check_db_monotonic("extra", db_new, st, now=now), "ok")
        expect("db older", check_db_monotonic("extra", db_old, st, now=now), "older")
        expect("db other repo", check_db_monotonic("core", db_old, st, now=now), "ok")
        res = check_db_monotonic("extra", db_future, st, now=now)
        expect("db future ignored", TrustResult("ok" if res.ok and res.extra.get("newest") == 1700000300 else "bad"), "ok")
        expect("db empty", check_db_monotonic("extra", {}, st, now=now), "error")
    return n, fails


def selftest() -> int:
    """Run the vercmp vectors and the signature fixtures. Exit code 0 when everything passes."""
    total = 0
    failed: List[str] = []
    n, f = _selftest_vercmp()
    print(f"vercmp: {n - len(f)}/{n} passed")
    total += n
    failed += f
    n, f = _selftest_signatures()
    print(f"signatures and database: {n - len(f)}/{n} passed")
    total += n
    failed += f
    for line in failed:
        print("FAIL " + line)
    print("selftest passed" if not failed and total else "selftest failed")
    return 0 if not failed and total else 1


# --- [ CLI ] ---

def main(argv: List[str]) -> int:
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print("usage: gnomes_trust.py selftest | vercmp A B | verify PKG SIG REPO [KEYS_ROOT] | "
              "keyring FAMILY PKG SIG [KEYS_ROOT] | keyring-check FAMILY PKG SIG [KEYS_ROOT] | "
              "install-staged STAGE_DIR OWNER_UID [KEYS_ROOT] | pins")
        return 2
    cmd = argv[1]
    if cmd == "selftest":
        return selftest()
    if cmd == "vercmp" and len(argv) == 4:
        print(vercmp(argv[2], argv[3]))
        return 0
    if cmd == "verify" and len(argv) in (5, 6):
        with open(argv[3], "rb") as f:
            sig = f.read(MAX_SIG_BYTES + 1)
        res = verify_package(argv[2], sig, argv[4], keys_root=argv[5] if len(argv) == 6 else KEYS_ROOT)
        print(json.dumps(res.as_dict()))
        print(res.message())
        return 0 if res.ok else 1
    if cmd == "keyring" and len(argv) >= 5:
        rest = [a for a in argv[5:] if a != "--bootstrap"]
        res = build_keyring(argv[2], argv[3], argv[4], keys_root=rest[0] if rest else KEYS_ROOT,
                            bootstrap="--bootstrap" in argv)
        print(json.dumps(res.as_dict()))
        if not res.ok:
            print(res.message())
        return 0 if res.ok else 1
    if cmd == "keyring-check" and len(argv) in (5, 6):
        # read-only: the rules of a keyring package against the store (what the user phase does before staging)
        try:
            with open(argv[3], "rb") as f:
                pkg = f.read(MAX_PKG_BYTES + 1)
            with open(argv[4], "rb") as f:
                sig = f.read(MAX_SIG_BYTES + 1)
            outcome, upd = verify_keyring_package(argv[2], pkg, sig, keys_root=argv[5] if len(argv) == 6 else KEYS_ROOT)
            print(json.dumps({"outcome": outcome, **({"pkgver": upd.pkgver, "builddate": upd.builddate, "via": upd.via,
                                                      "signer": upd.signer} if upd else {})}))
            return 0
        except Refusal as r:
            print(json.dumps({"outcome": "refused", "kind": r.kind, "detail": r.detail}))
            print(r.sentence(argv[2]))
            return 1
        except OSError as e:
            print(json.dumps({"outcome": "refused", "kind": "store", "detail": str(e)}))
            return 1
    if cmd == "install-staged" and len(argv) in (4, 5):
        # root phase of a full update: STAGE_DIR OWNER_UID [KEYS_ROOT]; one sentence per refused family on stdout
        if os.geteuid() != 0:
            print("Installing security keys needs administrator rights, so nothing was changed.")
            return 2
        try:
            owner = int(argv[3])
        except ValueError:
            return 2
        results = install_staged(argv[2], owner, keys_root=argv[4] if len(argv) == 5 else KEYS_ROOT)
        for r in results:
            if r["outcome"] == "refused":
                print(r["sentence"])
        return 1 if any(r["outcome"] == "refused" for r in results) else 0
    if cmd == "pins":
        for fam, p in TRUST_PINS.items():
            for fpr, label in p["anchors"].items():
                print(f"{fam}\t{fpr}\t{label}")
        return 0
    print("unknown command")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
