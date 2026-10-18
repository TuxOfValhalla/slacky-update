#!/usr/bin/env python3
"""SpiderSense snapshot pruner (6A-95, SS-2): decides which of OUR snapshots must go so none lives past 48 hours.

Owner rule (2026-10-13): snapshots made by our scripts are never kept longer than 48 hours; the owner's own snapshots
(timeline, manual, "Claude: ...") are never touched. Pure decision here; the shell executor deletes, under the locks.

Ours = userdata slacky=1 (6A-94 tags), or the descriptions older versions wrote ("slacky-update: ...",
"gnomes: before rollback of ..."). A pre/post pair is always deleted together. Never deleted: the snapshot the system
booted from, the default subvolume, and nothing at all when the clock looks wrong.
"""
import json
import os
import subprocess
import sys
import time
from datetime import datetime
from typing import Any, Dict, List, Optional, Set, Tuple

MAX_AGE_HOURS = 47  # pruned hourly: nothing of ours reaches 48 hours
OUR_DESC_PREFIXES = ("slacky-update: ", "gnomes: before rollback of ")
CLOCK_FLOOR = 1767225600  # 2026-01-01 UTC: a clock before this is wrong
# 6A-305: time limits for snapper calls (a hung snapper must fail closed with one sentence, never hang the update)
SNAPPER_CREATE_TIMEOUT = 180
SNAPPER_LIST_TIMEOUT = 60
SNAPPER_DELETE_TIMEOUT = 300
SNAPPER_BIN = os.environ.get("SLACKY_SNAPPER_BIN", "snapper")


def _truthy(v: Any) -> bool:
    return v is True or str(v).strip().lower() in ("yes", "true", "1", "+", "x")


def is_important(s: Dict[str, Any]) -> bool:
    """snapper convention (also limine-snapper-sync): userdata important=yes means keep."""
    ud = s.get("userdata") or {}
    return isinstance(ud, dict) and str(ud.get("important", "")).strip().lower() == "yes"


def is_ours(s: Dict[str, Any]) -> bool:
    ud = s.get("userdata") or {}
    if isinstance(ud, dict) and str(ud.get("slacky", "")) == "1":
        return True
    return str(s.get("description") or "").startswith(OUR_DESC_PREFIXES)


def snap_epoch(s: Dict[str, Any]) -> Optional[float]:
    """snapper prints local time without a zone ("2026-10-13 17:47:04")."""
    d = str(s.get("date") or "").strip()
    if not d:
        return None
    try:
        return time.mktime(datetime.strptime(d, "%Y-%m-%d %H:%M:%S").timetuple())
    except ValueError:
        return None


def decide(snaps: List[Dict[str, Any]], now: float, protected: Set[int],
           max_age_hours: float = MAX_AGE_HOURS) -> Tuple[List[int], str]:
    """(numbers to delete, reason when nothing may be deleted). `protected` = booted/default/current numbers."""
    dated = [e for e in (snap_epoch(s) for s in snaps if s.get("number")) if e]
    if now < CLOCK_FLOOR or (dated and now + 300 < max(dated)):
        return [], "clock"
    by_num = {int(s["number"]): s for s in snaps if s.get("number")}
    # 6A-305: snapper's own default/active flags protect a snapshot exactly like the booted one
    protected = set(protected) | {n for n, s in by_num.items() if _truthy(s.get("default")) or _truthy(s.get("active"))}
    groups: Dict[int, Set[int]] = {}
    for n, s in by_num.items():
        pre = s.get("pre-number")
        root = int(pre) if s.get("type") == "post" and pre else n
        groups.setdefault(root, set()).add(n)
    limit = max_age_hours * 3600
    out: List[int] = []
    for root, members in sorted(groups.items()):
        ss = [by_num[m] for m in members if m in by_num]
        if not ss or not all(is_ours(s) for s in ss):
            continue
        if members & protected:
            continue
        if any(is_important(s) for s in ss):  # 6A-305: important=yes is never deleted
            continue
        ages = [now - e for e in (snap_epoch(s) for s in ss) if e]
        if ages and max(ages) > limit:  # the OLDEST member decides: nothing of ours may pass 48 hours
            out.extend(sorted(members))
    return out, ""


def _snapper_list() -> List[Dict[str, Any]]:
    out = subprocess.run([SNAPPER_BIN, "--jsonout", "-c", "root", "list", "--columns",
                          "number,type,pre-number,date,cleanup,description,userdata,default,active"],
                         capture_output=True, text=True, timeout=SNAPPER_LIST_TIMEOUT, check=True).stdout
    return json.loads(out).get("root", [])


def _protected() -> Set[int]:
    """The snapshot the system booted from and the default subvolume are never deleted."""
    nums: Set[int] = set()
    try:
        fsroot = subprocess.run(["findmnt", "-n", "-o", "FSROOT", "/"], capture_output=True, text=True,
                                timeout=10).stdout.strip()
        if "/.snapshots/" in fsroot:
            nums.add(int(fsroot.split("/.snapshots/")[1].split("/")[0]))
    except (OSError, subprocess.SubprocessError, ValueError, IndexError):
        pass
    try:
        dflt = subprocess.run(["btrfs", "subvolume", "get-default", "/"], capture_output=True, text=True,
                              timeout=10).stdout
        if ".snapshots/" in dflt:
            nums.add(int(dflt.split(".snapshots/")[1].split("/")[0]))
    except (OSError, subprocess.SubprocessError, ValueError, IndexError):
        pass
    return nums


def main(argv: List[str]) -> int:
    # plan [--input FILE] [--now EPOCH] [--protect N,N] [--max-age-hours H]  -> prints numbers to delete (one line)
    if not argv or argv[0] != "plan":
        print("usage: spidersense_snap.py plan [--input FILE] [--now EPOCH] [--protect N,..] [--max-age-hours H]")
        return 2
    args = argv[1:]

    def opt(name: str) -> Optional[str]:
        return args[args.index(name) + 1] if name in args and args.index(name) + 1 < len(args) else None
    try:
        if opt("--input"):
            with open(opt("--input"), encoding="utf-8") as fh:
                data = json.load(fh)
            snaps = data.get("root", data) if isinstance(data, dict) else data
        else:
            snaps = _snapper_list()
    except subprocess.TimeoutExpired:
        print("ERROR snapper did not answer in time, so no snapshot was deleted")
        return 3
    except (OSError, ValueError, subprocess.SubprocessError):
        print("ERROR cannot list snapshots")
        return 3
    now = float(opt("--now") or time.time())
    protected = _protected() if opt("--input") is None else set()
    if opt("--protect"):
        protected |= {int(x) for x in opt("--protect").split(",") if x.strip().isdigit()}
    nums, why = decide(snaps, now, protected, float(opt("--max-age-hours") or MAX_AGE_HOURS))
    if why:
        print("HOLD " + why)
        return 0
    print(" ".join(str(n) for n in nums))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
