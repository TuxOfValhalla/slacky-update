#!/usr/bin/env python3
"""SpiderSense hardware profile (6A-117): what is inside this machine, read in milliseconds from sysfs/procfs.

One probe, one cached file (/var/cache/slacky-update/spidersense/hwprofile.json), one fingerprint. Run at boot, at the
start of every update and hourly; when the hardware or the boot setup changed since the last time, it says so in one
plain sentence per change. It only reads and reports: it never changes drivers, settings or files outside its cache.
"""
import hashlib
import json
import os
import sys
import time
from typing import Any, Dict, List, Optional

SYS = os.environ.get("SLACKY_SYSFS_ROOT", "")  # tests point this at a fake tree
STATE = os.environ.get("SLACKY_HWPROFILE", "/var/cache/slacky-update/spidersense/hwprofile.json")
VENDORS = {"0x10de": "NVIDIA", "0x1002": "AMD", "0x8086": "Intel", "0x1af4": "virtio", "0x15ad": "VMware",
           "0x1234": "QEMU", "0x80ee": "VirtualBox"}


def _read(path: str, default: str = "") -> str:
    try:
        with open(SYS + path, errors="replace") as fh:
            return fh.read().strip()
    except OSError:
        return default


def _ls(path: str) -> List[str]:
    try:
        return sorted(os.listdir(SYS + path))
    except OSError:
        return []


def probe_gpus() -> List[Dict[str, Any]]:
    gpus = []
    for slot in _ls("/sys/bus/pci/devices"):
        base = f"/sys/bus/pci/devices/{slot}"
        cls = _read(base + "/class")
        if not cls.startswith(("0x0300", "0x0302", "0x0380")):
            continue
        drv = ""
        try:
            drv = os.path.basename(os.readlink(SYS + base + "/driver"))
        except OSError:
            pass
        outputs = 0
        for card in _ls(base + "/drm"):
            if not card.startswith("card"):
                continue
            for conn in _ls(base + f"/drm/{card}"):
                if conn.startswith(card + "-") and _read(base + f"/drm/{card}/{conn}/status") == "connected":
                    outputs += 1
        gpus.append({"slot": slot, "vendor": _read(base + "/vendor"), "device": _read(base + "/device"),
                     "class": cls[:6], "driver": drv, "boot_vga": _read(base + "/boot_vga", "0") == "1",
                     "outputs_connected": outputs})
    return gpus


def display_gpu(gpus: List[Dict[str, Any]]) -> Optional[str]:
    for g in gpus:
        if g["boot_vga"]:
            return g["slot"]
    lit = [g for g in gpus if g["outputs_connected"]]
    return lit[0]["slot"] if lit else (gpus[0]["slot"] if gpus else None)


def probe_cpu() -> Dict[str, str]:
    info = _read("/proc/cpuinfo")
    vendor = model = ""
    flags: List[str] = []
    for line in info.splitlines():
        k, _, v = line.partition(":")
        k = k.strip()
        if k == "vendor_id" and not vendor:
            vendor = v.strip()
        elif k == "model name" and not model:
            model = v.strip()
        elif k == "flags" and not flags:
            flags = v.split()
    fs = set(flags)
    if {"avx512f", "avx512bw", "avx512cd", "avx512dq", "avx512vl"} <= fs:
        tier = "znver4" if vendor == "AuthenticAMD" else "v4"
    elif {"avx2", "fma", "bmi1", "bmi2"} <= fs:
        tier = "v3"
    else:
        tier = "generic"
    return {"vendor": vendor, "model": model, "tier": tier}


def probe_chassis() -> str:
    if _read("/sys/class/dmi/id/sys_vendor") in ("QEMU", "innotek GmbH", "VMware, Inc.") or \
            "hypervisor" in _read("/proc/cpuinfo").split("flags", 1)[-1].split("\n", 1)[0]:
        return "virtual machine"
    if _read("/sys/class/dmi/id/chassis_type") in ("8", "9", "10", "14", "30", "31", "32"):
        return "laptop"
    for ps in _ls("/sys/class/power_supply"):
        # a mouse or headset battery reports scope=Device; only a system battery means a laptop
        if _read(f"/sys/class/power_supply/{ps}/type") == "Battery" and \
                _read(f"/sys/class/power_supply/{ps}/scope", "System") != "Device":
            return "laptop"
    return "desktop"


def _mounts() -> Dict[str, str]:
    out: Dict[str, str] = {}
    for line in _read("/proc/self/mountinfo").splitlines():
        parts = line.split(" - ")
        if len(parts) != 2:
            continue
        left, right = parts[0].split(), parts[1].split()
        if len(left) > 4 and right:
            out[left[4]] = right[0]
    return out


def probe_boot() -> Dict[str, Any]:
    m = _mounts()
    fstab_boot = any(l.split()[1:2] == ["/boot"] for l in _read("/etc/fstab").splitlines()
                     if l.strip() and not l.lstrip().startswith("#"))
    pkgs = _ls("/var/lib/pkgtools/packages")

    def has_pkg(prefixes):
        return any(p.startswith(prefixes) for p in pkgs)
    if os.path.exists(SYS + "/boot/limine.conf") or has_pkg(("underpants-limine-1", "underpants-limine-2",
                                                               "cachyos-gnome-limine-", "limine-")):
        loader = "Limine"
    elif os.path.exists(SYS + "/boot/grub/grub.cfg") or has_pkg(("grub-",)):
        loader = "GRUB"
    elif has_pkg(("elilo-",)):
        loader = "ELILO"
    else:
        loader = "unknown"
    sb = None
    for f in _ls("/sys/firmware/efi/efivars"):
        if f.startswith("SecureBoot-"):
            try:
                with open(SYS + "/sys/firmware/efi/efivars/" + f, "rb") as fh:
                    data = fh.read()
                sb = bool(data[-1]) if data else None
            except OSError:
                sb = None
    return {"root_fs": m.get("/", "unknown"), "boot_separate": fstab_boot,
            "boot_fs": m.get("/boot", m.get("/", "unknown")), "uefi": os.path.isdir(SYS + "/sys/firmware/efi"),
            "secure_boot": sb, "bootloader": loader,
            "snapper": os.path.exists(SYS + "/etc/snapper/configs/root")}


def probe() -> Dict[str, Any]:
    gpus = probe_gpus()
    nv = None
    ver = _read("/proc/driver/nvidia/version")
    if ver:
        nv = {"driver": "open" if "Open Kernel Module" in ver else "proprietary",
              "version": next((w for w in ver.split() if w.count(".") >= 1 and w[0].isdigit()), "")}
    prof = {"schema": 1, "taken": int(time.time()), "gpus": gpus, "display_gpu": display_gpu(gpus), "nvidia": nv,
            "cpu": probe_cpu(), "chassis": probe_chassis(), "boot": probe_boot()}
    prof["fingerprint"] = fingerprint(prof)
    return prof


def fingerprint(p: Dict[str, Any]) -> str:
    """Stable parts only: monitors plugged in/out, versions and the time do not count."""
    stable = {"gpus": [{k: g[k] for k in ("slot", "vendor", "device", "class", "driver", "boot_vga")} for g in p["gpus"]],
              "display_gpu": p["display_gpu"], "nvidia": (p.get("nvidia") or {}).get("driver"),
              "cpu": p["cpu"], "chassis": p["chassis"], "boot": p["boot"]}
    return hashlib.sha256(json.dumps(stable, sort_keys=True).encode()).hexdigest()[:16]


def _gpu_name(g: Dict[str, Any]) -> str:
    return f"{VENDORS.get(g['vendor'], g['vendor'])} {g['device']}"


def changes(old: Dict[str, Any], new: Dict[str, Any]) -> List[str]:
    """One plain sentence per change (for a non-technical user)."""
    out: List[str] = []
    og = {g["slot"]: g for g in old.get("gpus", [])}
    ng = {g["slot"]: g for g in new.get("gpus", [])}
    added = [ng[s] for s in ng if s not in og or (og[s]["vendor"], og[s]["device"]) != (ng[s]["vendor"], ng[s]["device"])]
    removed = [og[s] for s in og if s not in ng or (og[s]["vendor"], og[s]["device"]) != (ng[s]["vendor"], ng[s]["device"])]
    if added or removed:
        was = ", ".join(_gpu_name(g) for g in removed) or "none"
        now = ", ".join(_gpu_name(g) for g in added) or "none"
        out.append(f"The graphics hardware changed (removed: {was}; added: {now}). Run the update once so the drivers "
                   f"and graphics settings match it.")
    elif old.get("display_gpu") != new.get("display_gpu"):
        out.append("A different graphics card now drives the screen. Run the update once so the graphics settings "
                   "match it.")
    for s in ng:
        if s in og and og[s].get("driver") != ng[s].get("driver") and (og[s]["vendor"], og[s]["device"]) == \
                (ng[s]["vendor"], ng[s]["device"]):
            out.append(f"The {_gpu_name(ng[s])} graphics card now uses the '{ng[s].get('driver') or 'no'}' driver "
                       f"(was '{og[s].get('driver') or 'none'}').")
    od, nd = (old.get("nvidia") or {}).get("driver"), (new.get("nvidia") or {}).get("driver")
    if od != nd and od and nd:
        out.append(f"The NVIDIA driver changed from the {od} to the {nd} kernel module.")
    if old.get("cpu", {}).get("model") != new.get("cpu", {}).get("model"):
        out.append(f"The processor changed (now {new['cpu'].get('model') or 'unknown'}); packages optimised for it "
                   f"are chosen on the next update.")
    if old.get("chassis") != new.get("chassis"):
        out.append(f"This machine now looks like a {new.get('chassis')} (was a {old.get('chassis')}).")
    ob, nb = old.get("boot", {}), new.get("boot", {})
    labels = {"root_fs": "root file system", "boot_fs": "boot partition file system", "bootloader": "boot loader",
              "snapper": "snapshot setup (snapper)", "secure_boot": "Secure Boot setting", "uefi": "firmware mode"}
    words = {"snapper": {True: "set up", False: "not set up"}, "secure_boot": {True: "on", False: "off", None: "unknown"},
             "uefi": {True: "UEFI", False: "BIOS"}}

    def say(k: str, v: Any) -> str:
        return words.get(k, {}).get(v, str(v)) if isinstance(v, (bool, type(None))) else str(v)
    for k, label in labels.items():
        if ob.get(k) != nb.get(k):
            out.append(f"The {label} changed from {say(k, ob.get(k))} to {say(k, nb.get(k))}.")
    return out


def load(path: str = STATE) -> Optional[Dict[str, Any]]:
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def save(prof: Dict[str, Any], path: str = STATE) -> None:
    d = os.path.dirname(path)
    os.makedirs(d, mode=0o755, exist_ok=True)
    old = load(path)
    if old is not None:
        with open(path + ".prev.tmp", "w", encoding="utf-8") as fh:
            json.dump(old, fh, indent=1, sort_keys=True)
        os.replace(path + ".prev.tmp", path + ".prev")
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(prof, fh, indent=1, sort_keys=True)
        fh.write("\n")
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)


def summary(p: Dict[str, Any]) -> List[str]:
    lines = []
    for g in p["gpus"]:
        role = "drives the screen" if g["slot"] == p["display_gpu"] else "extra card"
        lines.append(f"Graphics : {_gpu_name(g)} ({g['driver'] or 'no driver'}, {role}, "
                     f"{g['outputs_connected']} screen(s))")
    if p.get("nvidia"):
        lines.append(f"NVIDIA   : {p['nvidia']['driver']} kernel module {p['nvidia']['version']}")
    c = p["cpu"]
    lines.append(f"Processor: {c['model']} (package level {c['tier']})")
    lines.append(f"Machine  : {p['chassis']}")
    b = p["boot"]
    lines.append(f"Boot     : {b['bootloader']}, {'UEFI' if b['uefi'] else 'BIOS'}, Secure Boot "
                 f"{'on' if b['secure_boot'] else 'off' if b['secure_boot'] is False else 'unknown'}")
    lines.append(f"Disks    : / on {b['root_fs']}, /boot on {b['boot_fs']}{' (own partition)' if b['boot_separate'] else ''}, "
                 f"snapshots {'snapper' if b['snapper'] else 'not set up'}")
    return lines


def facts(p: Dict[str, Any]) -> Dict[str, str]:
    """6A-118: the answers every part of the app asks for, from ONE live probe (no lspci, no copies of the logic)."""
    gpus = p["gpus"]
    vend = {g["vendor"] for g in gpus}
    disp = next((g for g in gpus if g["slot"] == p["display_gpu"]), None)
    has_nv = "0x10de" in vend
    nv_display = bool(disp and disp["vendor"] == "0x10de")
    # hybrid = a render-only NVIDIA card next to the GPU that drives the screen, or two GPUs in a laptop
    hybrid = (has_nv and not nv_display and len(gpus) >= 2) or (p["chassis"] == "laptop" and len(gpus) >= 2)
    b = p["boot"]
    return {
        "chassis": p["chassis"], "laptop": str(p["chassis"] == "laptop").lower(),
        "has-nvidia": str(has_nv).lower(), "has-amd": str("0x1002" in vend).lower(),
        "has-intel": str("0x8086" in vend).lower(), "gpu-count": str(len(gpus)),
        "display-gpu-vendor": VENDORS.get(disp["vendor"], disp["vendor"]) if disp else "none",
        "nvidia-display": str(nv_display).lower(), "hybrid": str(hybrid).lower(),
        "nvidia-driver": (p.get("nvidia") or {}).get("driver") or "none",
        "cpu-tier": p["cpu"]["tier"], "cpu-threads": str(os.cpu_count() or 1),
        "ram-gb": str(_ram_gb()), "bootloader": b["bootloader"], "root-fs": b["root_fs"],
        "boot-fs": b["boot_fs"], "snapper": str(b["snapper"]).lower(),
        "secure-boot": {True: "on", False: "off", None: "unknown"}[b["secure_boot"]],
    }


def _ram_gb() -> int:
    for line in _read("/proc/meminfo").splitlines():
        if line.startswith("MemTotal:"):
            try:
                return int(int(line.split()[1]) / 1024 / 1024)
            except (ValueError, IndexError):
                return 0
    return 0


def main(argv: List[str]) -> int:
    cmd = argv[0] if argv else "show"
    t0 = time.time()
    prof = probe()
    if cmd == "get":
        # get <key> -> one value; get shell -> HW_<KEY>=value lines (values are [a-z0-9._-] only, safe for eval)
        f = facts(prof)
        if len(argv) > 1 and argv[1] != "shell":
            print(f.get(argv[1], ""))
            return 0 if argv[1] in f else 2
        import re
        for k, v in sorted(f.items()):
            print(f"HW_{k.upper().replace('-', '_')}={re.sub(r'[^A-Za-z0-9._-]', '_', v)}")
        return 0
    if cmd == "probe":
        print(json.dumps(prof, indent=1, sort_keys=True))
        return 0
    if cmd == "show":
        print("\n".join(summary(prof)))
        return 0
    if cmd in ("check", "boot"):
        # check: print one sentence per change, exit 1 when something changed; --save (root) stores the new profile
        old = load()
        ch = changes(old, prof) if old and old.get("fingerprint") != prof["fingerprint"] else []
        for line in ch:
            print(line)
        if ("--save" in argv or cmd == "boot") and os.geteuid() == 0 and (old is None or old.get("fingerprint") != prof["fingerprint"]
                                                                             or "--refresh" in argv):
            try:
                save(prof)
                if ch:
                    with open(os.path.join(os.path.dirname(STATE), "hw-changed"), "w", encoding="utf-8") as fh:
                        fh.write("\n".join(ch) + "\n")
            except OSError:
                pass
        if os.environ.get("SLACKY_HW_TIMING"):
            print(f"probe took {1000 * (time.time() - t0):.1f} ms", file=sys.stderr)
        return 1 if ch else 0
    print("usage: spidersense_hw.py show | probe | check [--save] | boot")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
