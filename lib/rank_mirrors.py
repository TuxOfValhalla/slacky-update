#!/usr/bin/env python3
"""
Underpants Gnomes & Slacky-Update Multi-Ecosystem Mirror Benchmarking Engine.
Evaluates Slackware, Arch Linux, CachyOS, and Chaotic-AUR mirrors in parallel.
Ensures zero boot delays, low-priority background execution, and atomic updates.
"""

import sys
import os
import time
import re
import json
import urllib.request
import urllib.error
import concurrent.futures
from typing import Dict, List, Any, Optional, Tuple

THRESHOLD_SECONDS = 597600  # 6 days and 22 hours (6*86400 + 22*3600)
BOOT_GRACE_PERIOD_SECONDS = 120  # 2 minutes after boot before background run

CACHE_DIR_USER = os.path.expanduser("~/.cache/slacky-update")
CACHE_DIR_SYS = "/var/cache/slacky-update"

TIMESTAMP_FILE_USER = os.path.join(CACHE_DIR_USER, "last_mirror_benchmark.timestamp")
TIMESTAMP_FILE_SYS = os.path.join(CACHE_DIR_SYS, "last_mirror_benchmark.timestamp")

RANKED_JSON_USER = os.path.join(CACHE_DIR_USER, "ranked_mirrors.json")
RANKED_JSON_SYS = os.path.join(CACHE_DIR_SYS, "ranked_mirrors.json")

# --- [ CANDIDATE MIRROR REGISTRIES ] ---

SLACKWARE_CANDIDATES = [
    # Europe
    ("Netherlands (slackware.nl)", "https://slackware.nl/slackware/"),
    ("Denmark (dotsrc.org)", "https://mirrors.dotsrc.org/slackware/"),
    ("Sweden (lysator.liu.se)", "https://ftp.lysator.liu.se/pub/slackware/"),
    ("Sweden (acc.umu.se)", "https://ftp.acc.umu.se/mirror/slackware/"),
    ("Germany (gwdg.de)", "https://ftp.gwdg.de/pub/linux/slackware/"),
    ("United Kingdom (slackware.uk)", "https://slackware.uk/slackware/"),
    ("Ireland (heanet.ie)", "https://ftp.heanet.ie/mirrors/ftp.slackware.com/pub/slackware/"),
    # Americas
    ("USA (kernel.org)", "https://mirrors.kernel.org/slackware/"),
    ("USA (osuosl.org)", "https://ftp.osuosl.org/pub/slackware/"),
    ("USA (math.princeton.edu)", "https://mirror.math.princeton.edu/pub/slackware/"),
    ("USA (clarkson.edu)", "https://mirror.clarkson.edu/slackware/"),
    ("USA (mirrors.tds.net)", "https://slackware.mirrors.tds.net/pub/slackware/"),
    ("Brazil (c3sl.ufpr.br)", "https://slackware.c3sl.ufpr.br/"),
    ("Ecuador (cedia.org.ec)", "https://mirror.cedia.org.ec/slackware/"),
    # Asia & Pacific
    ("Japan (riken.jp)", "https://ftp.riken.jp/Linux/slackware/"),
    ("Japan (iij.ad.jp)", "https://ftp.iij.ad.jp/pub/linux/slackware/"),
    ("China (tsinghua.edu.cn)", "https://mirrors.tuna.tsinghua.edu.cn/slackware/"),
    ("Australia (aarnet.edu.au)", "https://mirror.aarnet.edu.au/pub/slackware/")
]

# 6A-183: one list per family in slacky_mirrors.py (the same lists as the Rust app): eu/asia.cachyos.org are gone (no DNS
# record, checked 2026-10-15), cdn77.cachyos.org was added, Chaotic has the eleven regional mirrors and the cdn-mirror only
# as a never-probed last resort.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from slacky_mirrors import ARCH_CANDIDATES, CACHYOS_CANDIDATES, CHAOTIC_CANDIDATES  # noqa: E402


def get_system_uptime() -> float:
    """Read system uptime in seconds from /proc/uptime."""
    try:
        with open("/proc/uptime", "r") as f:
            return float(f.read().split()[0])
    except Exception:
        return 9999.0


def is_maintenance_due() -> bool:
    """Check if 6 days and 22 hours have passed since last benchmark and boot grace period is satisfied."""
    uptime = get_system_uptime()
    if uptime < BOOT_GRACE_PERIOD_SECONDS:
        return False

    latest_ts = 0.0
    for ts_file in [TIMESTAMP_FILE_USER, TIMESTAMP_FILE_SYS]:
        if os.path.exists(ts_file):
            try:
                with open(ts_file, "r") as f:
                    val = float(f.read().strip())
                    if val > latest_ts:
                        latest_ts = val
            except Exception:
                pass

    if latest_ts == 0.0:
        return True

    now = time.time()
    return (now - latest_ts) >= THRESHOLD_SECONDS


def probe_single_endpoint(url: str, headers: Optional[Dict[str, str]] = None, timeout: float = 3.5) -> Tuple[bool, int, str]:
    """Test HTTP endpoint latency and return (success, latency_ms, content_snippet)."""
    t0 = time.time()
    req_headers = {"User-Agent": "Slacky-Update-Mirror-Benchmark/1.0_RC2"}
    if headers:
        req_headers.update(headers)
    req = urllib.request.Request(url, headers=req_headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read(2048)
            lat = int((time.time() - t0) * 1000)
            text = raw.decode("utf-8", errors="ignore")
            return True, lat, text
    except Exception:
        return False, 9999, ""


def benchmark_slackware_mirrors(arch_branch: str = "slackware64-current") -> List[Dict[str, Any]]:
    """Benchmark Slackware mirrors for latency and ChangeLog freshness."""
    results = []

    def _worker(item):
        region, base_url = item
        full_url = f"{base_url.rstrip('/')}/{arch_branch}/"
        cl_url = f"{full_url}ChangeLog.txt"
        ok, lat, content = probe_single_endpoint(cl_url, headers={"Range": "bytes=0-1024"}, timeout=3.5)
        top_date = "Unknown"
        if ok and content:
            m = re.search(r'^[A-Za-z]{3}\s+[A-Za-z]{3}\s+[0-9\s]{2}\s+[0-9:]+\s+[A-Z]+\s+[0-9]{4}', content, re.MULTILINE)
            if m:
                top_date = m.group(0)
        return {
            "region": region,
            "url": full_url,
            "latency_ms": lat,
            "date": top_date,
            "ok": ok
        }

    with concurrent.futures.ThreadPoolExecutor(max_workers=18) as ex:
        results = list(ex.map(_worker, SLACKWARE_CANDIDATES))

    valid = [r for r in results if r["ok"]]
    valid.sort(key=lambda x: x["latency_ms"])
    return valid


def benchmark_generic_repo_mirrors(candidates: List[Tuple[str, str]], check_rel_path: str) -> List[Dict[str, Any]]:
    """Benchmark a list of package repository mirrors for latency."""
    def _worker(item):
        region, base_url = item
        target_url = f"{base_url.rstrip('/')}/{check_rel_path.lstrip('/')}"
        ok, lat, _ = probe_single_endpoint(target_url, headers={"Range": "bytes=0-512"}, timeout=3.5)
        return {
            "region": region,
            "url": base_url.rstrip('/'),
            "latency_ms": lat,
            "ok": ok
        }

    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as ex:
        results = list(ex.map(_worker, candidates))

    valid = [r for r in results if r["ok"]]
    valid.sort(key=lambda x: x["latency_ms"])
    return valid


# 6A-140: mirror writes are explicit only. The weekly --auto run ranks and records a recommendation; it never edits
# /etc/slackpkg/mirrors. --apply URL (interactive, after the user said yes) replaces our marked block, keeps a backup,
# refuses when there is no active mirror, when the branch would change, or when the chosen mirror is older.
MIRRORS_FILE = "/etc/slackpkg/mirrors"
BLOCK_BEGIN = "# BEGIN slacky-update primary mirror"
BLOCK_END = "# END slacky-update primary mirror"
LEGACY_HEADERS = ("# Primary mirror selected automatically by Slacky-Update",
                  "# Primary Slackware mirror set by Slacky-Update")
_URL_RE = re.compile(r'^(https?|ftp)://')
_BRANCH_RE = re.compile(r'(slackware(?:64)?-(?:current|[0-9]+\.[0-9]+))/?$')
_DATE_RE = re.compile(r'^[A-Za-z]{3}\s+[A-Za-z]{3}\s+[0-9\s]{2}\s+[0-9:]+\s+[A-Z]+\s+[0-9]{4}', re.MULTILINE)


def read_active_mirror(mirrors_file: str = MIRRORS_FILE) -> str:
    """Return the first active (uncommented) mirror URL, or an empty string."""
    try:
        with open(mirrors_file, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                s = line.strip()
                if s and not s.startswith("#") and _URL_RE.match(s):
                    return s
    except Exception:
        pass
    return ""


def mirror_branch(url: str) -> str:
    """Return the release branch directory of a mirror URL (e.g. slackware64-current), or an empty string."""
    m = _BRANCH_RE.search((url or "").strip())
    return m.group(1) if m else ""


def parse_changelog_date(text: str) -> Optional[float]:
    """Parse the top ChangeLog date ("Mon Oct 13 20:11:05 UTC 2026") into epoch seconds (UTC assumed)."""
    if not text:
        return None
    m = _DATE_RE.search(text)
    raw = m.group(0) if m else text.strip()
    parts = raw.split()
    if len(parts) != 6:
        return None
    try:
        import calendar
        st = time.strptime(" ".join(parts[:4] + parts[5:]), "%a %b %d %H:%M:%S %Y")
        return float(calendar.timegm(st))
    except Exception:
        return None


def fetch_changelog_date(mirror_url: str) -> Optional[float]:
    """Fetch the top ChangeLog date of a mirror branch URL."""
    ok, _, content = probe_single_endpoint(f"{mirror_url.rstrip('/')}/ChangeLog.txt",
                                           headers={"Range": "bytes=0-1024"}, timeout=5.0)
    return parse_changelog_date(content) if ok else None


def render_mirrors_text(old_text: str, chosen_url: str) -> str:
    """Return the new mirrors file text: our old blocks removed, other active lines commented, one marked block."""
    clean_url = chosen_url.strip()
    if not clean_url.endswith("/"):
        clean_url += "/"
    lines = old_text.splitlines(keepends=True)
    # Only a BEGIN followed by its own END forms a block; a lone marker line is dropped, never used as a range
    drop = set()
    i = 0
    while i < len(lines):
        if lines[i].strip() == BLOCK_BEGIN:
            j = i + 1
            while j < len(lines) and lines[j].strip() not in (BLOCK_BEGIN, BLOCK_END):
                j += 1
            if j < len(lines) and lines[j].strip() == BLOCK_END:
                drop.update(range(i, j + 1))
                i = j + 1
                continue
        if lines[i].strip() in (BLOCK_BEGIN, BLOCK_END):
            drop.add(i)
        i += 1
    out: List[str] = []
    skip_next_url = False
    for idx, line in enumerate(lines):
        s = line.strip()
        if idx in drop:
            continue
        if s in LEGACY_HEADERS:
            # Blocks appended by older builds: drop the header and the URL line that follows it
            skip_next_url = True
            continue
        if skip_next_url:
            skip_next_url = False
            if _URL_RE.match(s.lstrip("#").strip()):
                continue
        if s and not s.startswith("#") and _URL_RE.match(s):
            out.append(f"# {line.rstrip()}\n")
        else:
            out.append(line)
    while out and out[-1].strip() == "":
        out.pop()
    if out and not out[-1].endswith("\n"):
        out[-1] += "\n"
    out.append(f"\n{BLOCK_BEGIN}\n{clean_url}\n{BLOCK_END}\n")
    return "".join(out)


def _t(key: str, english: str) -> str:
    """Plain sentence in the user's language (locales/<lang>.json) through the sentinel's loader; English when it is not there."""
    try:
        import slacky_mirrors as _sm
        sn = _sm._sentinel()
        if sn is not None:
            return sn.tr(key, english)
    except Exception:
        pass
    return english


def check_mirror_change(current_url: str, chosen_url: str,
                        current_date: Optional[float], chosen_date: Optional[float]) -> Tuple[bool, str]:
    """Decide whether switching to chosen_url is safe. Returns (ok, plain-English reason)."""
    if not current_url:
        return False, _t("G13_MIRROR_NONE", "No Slackware download server is chosen, so the server list was left alone.")
    if not _URL_RE.match(chosen_url or ""):
        return False, _t("G13_MIRROR_BAD_URL", "That download server address looks wrong, so the server list was left alone.")
    cur_b, new_b = mirror_branch(current_url), mirror_branch(chosen_url)
    if not cur_b or cur_b != new_b:
        return False, _t("G13_MIRROR_OTHER_RELEASE", "That download server is for a different Slackware version, so the server list was left alone.")
    if chosen_url.rstrip("/") == current_url.rstrip("/"):
        return False, _t("G13_MIRROR_ACTIVE", "That download server is already the one you use.")
    if current_date is None or chosen_date is None:
        return False, _t("G13_MIRROR_NO_DATE", "The dates of the download servers could not be read, so the server list was left alone.")
    if chosen_date < current_date:
        return False, _t("G13_MIRROR_BEHIND", "That download server is behind your current one, so the server list was left alone.")
    return True, ""


def update_slackpkg_mirrors_file(chosen_url: str, mirrors_file: str = MIRRORS_FILE,
                                 current_date: Optional[float] = None,
                                 chosen_date: Optional[float] = None) -> Tuple[bool, str]:
    """Explicit, user-confirmed mirror switch with a backup. Never called from --auto."""
    if not os.path.isfile(mirrors_file) or os.path.islink(mirrors_file):
        return False, _t("G13_MIRROR_FILE", "The server list file was not found or is a link, so nothing was changed.")
    current = read_active_mirror(mirrors_file)
    if current and current_date is None:
        current_date = fetch_changelog_date(current)
    if chosen_date is None and _URL_RE.match(chosen_url or ""):
        chosen_date = fetch_changelog_date(chosen_url)
    ok, reason = check_mirror_change(current, chosen_url, current_date, chosen_date)
    if not ok:
        return False, reason
    try:
        with open(mirrors_file, "r", encoding="utf-8", errors="ignore") as f:
            old_text = f.read()
        new_text = render_mirrors_text(old_text, chosen_url)
        st = os.stat(mirrors_file)
        backup = f"{mirrors_file}.slacky-update.bak"
        tmp_b = f"{backup}.tmp.{os.getpid()}"
        with open(tmp_b, "w", encoding="utf-8") as f:
            f.write(old_text)
        os.chmod(tmp_b, st.st_mode & 0o777)
        os.replace(tmp_b, backup)
        tmp_target = f"{mirrors_file}.tmp.{os.getpid()}"
        with open(tmp_target, "w", encoding="utf-8") as f:
            f.write(new_text)
        os.chmod(tmp_target, st.st_mode & 0o777)
        try:
            os.chown(tmp_target, st.st_uid, st.st_gid)
        except OSError:
            pass
        os.replace(tmp_target, mirrors_file)
        return True, _t("G13_MIRROR_DONE", "Your Slackware download server is now {url}; the old list was saved next to it.").replace("{url}", chosen_url.strip())
    except Exception:
        return False, _t("G13_MIRROR_WRITE", "The server list could not be written, so it was left as it was.")


def build_recommendation(current_url: str, ranked: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Pick the fastest mirror on the same branch that is not older than the current one (report only)."""
    rec: Dict[str, Any] = {"url": "", "current": current_url, "reason": ""}
    if not current_url:
        rec["reason"] = "No active Slackware mirror is set."
        return rec
    cur_date = None
    for r in ranked:
        if r["url"].rstrip("/") == current_url.rstrip("/"):
            cur_date = parse_changelog_date(r.get("date", ""))
    if cur_date is None:
        cur_date = fetch_changelog_date(current_url)
    for r in ranked:
        if r["url"].rstrip("/") == current_url.rstrip("/"):
            rec["reason"] = "Your current mirror is already the fastest up-to-date mirror."
            return rec
        ok, _ = check_mirror_change(current_url, r["url"], cur_date, parse_changelog_date(r.get("date", "")))
        if ok:
            rec["url"] = r["url"]
            rec["latency_ms"] = r.get("latency_ms")
            rec["reason"] = "A faster mirror with the same or newer updates was found; change it with slacky-update -M."
            return rec
    rec["reason"] = "No faster up-to-date mirror was found."
    return rec


def _candidates(family: str, builtin: List[Tuple[str, str]]) -> List[Tuple[str, str]]:
    try:
        from slacky_mirrors import benchmark_candidates
        return benchmark_candidates(family) or builtin
    except Exception:
        return builtin


def run_full_benchmark(auto_apply_slackpkg: bool = False) -> Dict[str, Any]:
    """Execute complete parallel benchmark across Slackware, Arch, CachyOS, and Chaotic-AUR."""
    # Detect current Slackware branch (6A-140: from the active mirror path; default -current only for ranking)
    current_active = read_active_mirror()
    arch_branch = mirror_branch(current_active) or "slackware64-current"

    # Parallel execution across all ecosystems
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
        f_slack = ex.submit(benchmark_slackware_mirrors, arch_branch)
        # 6A-201: the candidates are the built-in list plus the signed-list servers, at most 8 per family, retired mirrors
        # skipped; and the CachyOS / Chaotic probe paths are the real ones (the old paths answered 404, so those two
        # rankings were always empty)
        f_arch = ex.submit(benchmark_generic_repo_mirrors, _candidates("arch", ARCH_CANDIDATES), "extra/os/x86_64/extra.db")
        f_cachy = ex.submit(benchmark_generic_repo_mirrors, _candidates("cachyos", CACHYOS_CANDIDATES), "x86_64/cachyos/cachyos.db")
        f_chaotic = ex.submit(benchmark_generic_repo_mirrors, _candidates("chaotic", CHAOTIC_CANDIDATES), "x86_64/chaotic-aur.db")

        slack_ranked = f_slack.result()
        arch_ranked = f_arch.result()
        cachy_ranked = f_cachy.result()
        chaotic_ranked = f_chaotic.result()

    best_slack = slack_ranked[0]["url"] if slack_ranked else ""
    best_arch = arch_ranked[0]["url"] if arch_ranked else "https://geo.mirror.pkgbuild.com"
    best_cachy = cachy_ranked[0]["url"] if cachy_ranked else "https://mirror.cachyos.org/repo"
    best_chaotic = chaotic_ranked[0]["url"] if chaotic_ranked else "https://cdn-mirror.chaotic.cx/chaotic-aur"

    now_ts = time.time()
    payload = {
        "last_benchmark_ts": now_ts,
        "last_benchmark_date": time.strftime("%Y-%m-%d %H:%M:%S UTC", time.gmtime(now_ts)),
        "branch": arch_branch,
        "slackware_primary": best_slack,
        "arch_primary": best_arch,
        "cachyos_primary": best_cachy,
        "chaotic_primary": best_chaotic,
        "slackware_ranked": slack_ranked,
        "arch_ranked": arch_ranked,
        "cachyos_ranked": cachy_ranked,
        "chaotic_ranked": chaotic_ranked,
        # 6A-140: report only; the user applies it with slacky-update -M
        "slackware_recommendation": build_recommendation(current_active, slack_ranked)
    }

    # Save to user cache and system cache
    for cdir, jfile, tfile in [(CACHE_DIR_USER, RANKED_JSON_USER, TIMESTAMP_FILE_USER),
                               (CACHE_DIR_SYS, RANKED_JSON_SYS, TIMESTAMP_FILE_SYS)]:
        try:
            os.makedirs(cdir, exist_ok=True)
            tmp_j = f"{jfile}.tmp.{os.getpid()}"
            with open(tmp_j, "w", encoding="utf-8") as f:
                json.dump(payload, f, indent=2)
            os.replace(tmp_j, jfile)

            with open(tfile, "w", encoding="utf-8") as f:
                f.write(str(now_ts))
        except Exception:
            pass

    # 6A-140: auto_apply_slackpkg is ignored on purpose. A background run never edits /etc/slackpkg/mirrors.
    _ = auto_apply_slackpkg

    return payload


def print_interactive_summary(payload: Dict[str, Any]):
    """Format and display colorized benchmark tables for terminal."""
    BOLD = "\033[1m"
    CYAN = "\033[1;36m"
    GREEN = "\033[1;32m"
    YELLOW = "\033[1;33m"
    RED = "\033[1;31m"
    BLUE = "\033[34m"
    RESET = "\033[0m"

    print(f"\n{BOLD}{CYAN}=== SLACKWARE LINUX OFFICIAL MIRRORS (Ranked by Latency) ==={RESET}")
    print(f"{BLUE}{'─'*86}{RESET}")
    print(f"{BOLD}{'#':<3} {'Region / Mirror Host':<36} {'Latency':<14} {'ChangeLog Timestamp':<32}{RESET}")
    print(f"{BLUE}{'─'*86}{RESET}")

    current = ""
    if os.path.exists("/etc/slackpkg/mirrors"):
        try:
            with open("/etc/slackpkg/mirrors", "r") as f:
                for line in f:
                    s = line.strip()
                    if s and not s.startswith("#") and (s.startswith("http://") or s.startswith("https://") or s.startswith("ftp://")):
                        current = s.rstrip('/')
                        break
        except Exception:
            pass

    for idx, m in enumerate(payload.get("slackware_ranked", [])[:10], 1):
        lat = m["latency_ms"]
        lat_c = GREEN if lat < 60 else (YELLOW if lat < 150 else RED)
        lat_str = f"{lat_c}{lat} ms{RESET}"
        is_curr = m["url"].rstrip('/') == current
        curr_badge = f" {GREEN}[ACTIVE]{RESET}" if is_curr else ""
        date_str = m["date"][:27] + "..." if len(m["date"]) > 30 else m["date"]
        print(f"{BOLD}{idx:<3}{RESET} {m['region']:<36} {lat_str:<23} {date_str:<32}{curr_badge}")

    print(f"\n{BOLD}{CYAN}=== ECOSYSTEM REPOSITORIES (Arch Linux, CachyOS & Chaotic-AUR) ==={RESET}")
    print(f"{BLUE}{'─'*86}{RESET}")
    print(f"{BOLD}Arch Linux Top Mirror   :{RESET} {GREEN}{payload.get('arch_primary')}{RESET}")
    print(f"{BOLD}CachyOS Top Mirror      :{RESET} {GREEN}{payload.get('cachyos_primary')}{RESET}")
    print(f"{BOLD}Chaotic-AUR Top Mirror  :{RESET} {GREEN}{payload.get('chaotic_primary')}{RESET}")
    print(f"{BLUE}{'─'*86}{RESET}\n")


def main():
    if "--check-due" in sys.argv:
        if is_maintenance_due():
            sys.exit(0)
        sys.exit(1)

    if "--auto" in sys.argv:
        if not is_maintenance_due() and "--force" not in sys.argv:
            sys.exit(0)
        # 6A-140: rank and record a recommendation only
        run_full_benchmark(auto_apply_slackpkg=False)
        sys.exit(0)

    if "--apply" in sys.argv:
        # 6A-140: explicit switch after an interactive yes: rank_mirrors.py --apply URL --yes
        idx = sys.argv.index("--apply")
        chosen = sys.argv[idx + 1] if len(sys.argv) > idx + 1 else ""
        if "--yes" not in sys.argv or not sys.stdin.isatty():
            print("The mirror list is only changed after you confirm it in a terminal.")
            sys.exit(2)
        ok, msg = update_slackpkg_mirrors_file(chosen)
        print(msg)
        sys.exit(0 if ok else 1)

    if "--status" in sys.argv:
        for jf in [RANKED_JSON_USER, RANKED_JSON_SYS]:
            if os.path.exists(jf):
                try:
                    with open(jf, "r") as f:
                        data = json.load(f)
                    print_interactive_summary(data)
                    rec = data.get("slackware_recommendation") or {}
                    if rec.get("reason"):
                        print(rec["reason"] + (f" ({rec['url']})" if rec.get("url") else ""))
                    sys.exit(0)
                except Exception:
                    pass
        print("No benchmark cache found. Run with --rank to measure mirrors.")
        sys.exit(0)

    # Default / Interactive
    print("\033[1;36m:: Measuring HTTP/SSL latency and ChangeLog freshness across all ecosystems in parallel...\033[0m")
    res = run_full_benchmark(auto_apply_slackpkg=False)
    print_interactive_summary(res)


if __name__ == "__main__":
    main()
