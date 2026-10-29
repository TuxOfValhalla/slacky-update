# Slacky-Update v1.0 LTS "Dark Star"

The first long-term support release. Since 1.0 RC2 (30 September 2026), the work has gone into making Slacky-Update safe to leave running on a real Slackware -current machine. It went through Builds 55 to 105, with more than 370 fixes. The final test was done on real hardware with Secure Boot on: a CachyOS kernel was installed and then removed. Only the new kernel got a startup image, and every boot file matched its Limine hash both times.

## Highlights

### The Slackware base stays untouched
- The **Footprint Guard** is on by default. No package we build may overwrite, shadow or change a file owned by a Slackware package. It also cannot drop files with a system-wide effect (`ld.so.conf.d`, `profile.d`, `cron.*`) onto the host.
- Packages are always built `root:root`. Underpants Gnomes never creates a launcher that hides a Slackware program.
- `.new` configuration files are only handled with your consent, and each one now comes with a short explanation. Damaged packages are detected and explained, never "repaired" behind your back.

### A boot chain you can trust
- One shared boot lock. `limine.conf` and the Limine EFI file are written atomically as a pair, with a backup pair kept. Limine is resealed at the end of every run, in the right Secure Boot order.
- Free space on `/boot` and the ESP is checked before anything is copied. The real MOK signature is checked, and the Secure Boot check fails closed.
- A startup image (initramfs) is rebuilt only when its inputs actually changed: no more rebuilding every kernel after an NVIDIA update. A stale record never removes a working kernel from the boot menu.
- Btrfs/Snapper snapshot entries point at the real snapshot. If the snapshot fails, the kernel update is held back.

### Signatures and sources
- Gnomes packages are checked against family-bound Arch, CachyOS and Chaotic-AUR signing keys, and this is enforced by default. CachyOS package lists come as the signed `.db` file.
- Keyrings never go back to an older version. Mirror lists are signed and refreshed weekly, and mirror health is recorded.
- Vendor downloads are checked: NVIDIA `.run` files and the NVIDIA module and r8125 packages (GPG), Antigravity, GitHub release digests, and pinned theme archives.

### Honest output
- No emoji. The run ends with exactly `All updates are completed`.
- A failed step is never reported as done. If a source cannot be read, you see "could not check", never a silent "up to date".
- Restart advice appears only when something in use changed, and the question defaults to No.

### Update checks and software
- The check also lists multilib (slackpkg+) updates and new Slackware packages, Chaotic-AUR epoch versions and OBS plugins. Catalog names match the package itself only.
- GitHub release lists are cached (ETag), so the rate limit no longer causes trouble. When archlinux.org fails, the check falls back to the Arch mirror.
- Underpants Gnomes:
  - uses installed Slackware libraries instead of bundling them again;
  - gives Python apps a private venv;
  - checks library symbol versions before installing;
  - has a download stall watchdog, IPv4 fallback, a guarded rollback and a run lock.
- Monthly runtime refresh (offer only): it tells you when the shared Underpants runtime is due and checks the affected apps before it is replaced.
- Curated packages are never rebuilt by Gnomes. Superseded packages are removed safely. A package that waits for a newer system library is reported as waiting, not as installed.

### SpiderSense
- A standalone `spidersense` command and a snapshot lifeline before risky steps. A mirror and key sentinel, and pruning that never deletes the booted or default snapshot.

### Look and feel
- New README and screenshots. All 24 languages are complete (364 strings each). Plan prompts ask again on a stray answer, and the kernel picker shows coloured badges again.

## Upgrade
From an installed RC build, open **Slacky-Update** and accept the self-update. You can also build it from the source:

```bash
git clone https://github.com/TuxOfValhalla/slacky-update.git && cd slacky-update && bash slackbuild/slacky-update.SlackBuild
sudo upgradepkg --reinstall --install-new "$(ls -t ../slacky-updates_releases/slacky-update-[0-9]*.txz | head -n 1)"
```

## Known limits (planned for 1.0.1)
- When a new kernel is installed from the kernel menu, its startup image is built twice and Limine is sealed three times. The end result is correct; it only takes about 25 seconds longer.
- A kernel installed from the menu gets its initramfs input record at the next boot sync. Records of removed kernels are left behind (harmless).
- A leftover module folder with no kernel image (for example `/lib/modules/6.18.52`) is treated as a kernel by the boot sync.
- Kernel menu actions are logged to `~/.cache/slacky-update/slacky-update.log`, not to `/var/log/slacky-update.log`.
