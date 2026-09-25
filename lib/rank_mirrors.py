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

ARCH_CANDIDATES = [
    ("Global Geo-DNS (pkgbuild.com)", "https://geo.mirror.pkgbuild.com"),
    ("Worldwide CDN (rackspace.com)", "https://mirror.rackspace.com/archlinux"),
    ("USA (kernel.org)", "https://mirrors.kernel.org/archlinux"),
    ("Sweden (acc.umu.se)", "https://ftp.acc.umu.se/mirror/archlinux"),
    ("Germany (thaller.ws)", "https://archlinux.thaller.ws"),
    ("Denmark (dotsrc.org)", "https://mirrors.dotsrc.org/archlinux"),
    ("Netherlands (osbeck.com)", "https://mirror.osbeck.com/archlinux"),
    ("Germany (f4st.host)", "https://mirror.f4st.host/archlinux")
]

CACHYOS_CANDIDATES = [
    ("Global CDN (mirror.cachyos.org)", "https://mirror.cachyos.org/repo"),
    ("Europe Node (eu.cachyos.org)", "https://eu.cachyos.org/repo"),
    ("USA Node (us.cachyos.org)", "https://us.cachyos.org/repo"),
    ("Asia Node (asia.cachyos.org)", "https://asia.cachyos.org/repo")
]

CHAOTIC_CANDIDATES = [
    ("Global CDN (cdn-mirror.chaotic.cx)", "https://cdn-mirror.chaotic.cx/chaotic-aur"),
    ("Geo Mirror (geo-mirror.chaotic.cx)", "https://geo-mirror.chaotic.cx/chaotic-aur"),
    ("Europe Spain (es-mirror.chaotic.cx)", "https://es-mirror.chaotic.cx/chaotic-aur"),
    ("Europe Germany (de-mirror.chaotic.cx)", "https://de-mirror.chaotic.cx/chaotic-aur"),
    ("USA Florida (us-fl-mirror.chaotic.cx)", "https://us-fl-mirror.chaotic.cx/chaotic-aur")
]


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
    req_headers = {"User-Agent": "Slacky-Update-Mirror-Benchmark/0.17.0"}
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


def update_slackpkg_mirrors_file(chosen_url: str) -> bool:
    """Safely update /etc/slackpkg/mirrors ensuring EXACTLY ONE active mirror."""
    mirrors_file = "/etc/slackpkg/mirrors"
    if not os.path.exists(mirrors_file):
        return False
    if not os.access(mirrors_file, os.W_OK) and os.geteuid() != 0:
        return False

    try:
        with open(mirrors_file, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()

        new_lines = []
        for line in lines:
            sline = line.strip()
            # If line is an active mirror URL, comment it out
            if sline and not sline.startswith("#") and (sline.startswith("http://") or sline.startswith("https://") or sline.startswith("ftp://")):
                new_lines.append(f"# {line.rstrip()}\n")
            else:
                new_lines.append(line)

        # Append chosen single mirror at the end
        clean_url = chosen_url.strip()
        if not clean_url.endswith("/"):
            clean_url += "/"
        new_lines.append(f"\n# Primary mirror selected automatically by Slacky-Update\n{clean_url}\n")

        # Atomic write
        tmp_target = f"{mirrors_file}.tmp.{os.getpid()}"
        with open(tmp_target, "w", encoding="utf-8") as f:
            f.writelines(new_lines)
        os.replace(tmp_target, mirrors_file)
        return True
    except Exception:
        return False


def run_full_benchmark(auto_apply_slackpkg: bool = False) -> Dict[str, Any]:
    """Execute complete parallel benchmark across Slackware, Arch, CachyOS, and Chaotic-AUR."""
    # Detect current Slackware branch
    current_active = ""
    if os.path.exists("/etc/slackpkg/mirrors"):
        try:
            with open("/etc/slackpkg/mirrors", "r") as f:
                for line in f:
                    s = line.strip()
                    if s and not s.startswith("#") and (s.startswith("http://") or s.startswith("https://") or s.startswith("ftp://")):
                        current_active = s
                        break
        except Exception:
            pass

    arch_branch = "slackware64-current"
    if "15.0" in current_active:
        arch_branch = "slackware64-15.0" if "64" in current_active else "slackware-15.0"
    elif "current" in current_active:
        arch_branch = "slackware64-current" if "64" in current_active else "slackware-current"

    # Parallel execution across all ecosystems
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
        f_slack = ex.submit(benchmark_slackware_mirrors, arch_branch)
        f_arch = ex.submit(benchmark_generic_repo_mirrors, ARCH_CANDIDATES, "extra/os/x86_64/extra.db.tar.gz")
        f_cachy = ex.submit(benchmark_generic_repo_mirrors, CACHYOS_CANDIDATES, "cachyos/x86_64/cachyos.db.tar.gz")
        f_chaotic = ex.submit(benchmark_generic_repo_mirrors, CHAOTIC_CANDIDATES, "x86_64/chaotic-aur.db.tar.gz")

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
        "chaotic_ranked": chaotic_ranked
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

    if auto_apply_slackpkg and best_slack:
        update_slackpkg_mirrors_file(best_slack)

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
        run_full_benchmark(auto_apply_slackpkg=True)
        sys.exit(0)

    if "--status" in sys.argv:
        for jf in [RANKED_JSON_USER, RANKED_JSON_SYS]:
            if os.path.exists(jf):
                try:
                    with open(jf, "r") as f:
                        data = json.load(f)
                    print_interactive_summary(data)
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
