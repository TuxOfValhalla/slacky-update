# Commit notes for the legacy working tree (prepared by Claude, 2026-10-12)

Installed and verified on the owner's machine as `slacky-update-1.0_RC2-noarch-62_slacky` (snapshot #702; Build 60 was snapshot #698;
Build 59 was snapshot #690).
Details per item: `docs/log.md`, `docs/log_nb.md`, `claude_log.md`.

## Suggested commit message

```
fix: harden boot chain, package footprint, downloads and runtime for 1.0 LTS (Build 60)

Boot chain (Limine + Secure Boot):
- 6A-8a/8b: stage enroll+sign+verify of the Limine EFI, honest [5/5] result
- 6A-8c: limine.conf.next + EFI swapped in as one pair (HUP/INT/TERM held, .prev pair,
  rollback), reseal-pending marker repaired by the hourly cron job
- 6A-8d: one shared boot lock for update, menus and cron; limine.conf via
  temp+sync+rename; cron fingerprint only after a successful reseal
- 6A-8e: no early reseal before initramfs/kernel signing; [5/5] always reseals;
  MOK signature checked with sbverify --cert, verified before replacing the kernel
- 6A-8f: GPG fail-closed for the NVIDIA module and r8125 packages (+ fallback .sig)
- 6A-8g: blocking /boot (+ separate Limine ESP) space check sized from the incoming
  files; kernel copy compared byte for byte before sealing
- 6A-25: Hyprland suites ship start-hyprland-session (D-Bus session bus via
  dbus-run-session) and hyprland.desktop

Footprint Guard / gnomes:
- 2A/2B/2C: Footprint Guard in gnomes and the curated builder, enforce by default,
  root:root archives only
- 6A-9/6A-10/6A-14: runtime python for bundled scripts, private venv instead of
  PYTHONPATH, no LD_LIBRARY_PATH export for venv apps
- 6A-11: never wrap names Slackware owns (/usr/bin/env incident)
- 6A-12: ALSA_PLUGIN_DIR for gnomes apps (not for game launchers)
- 6A-13: Hyprland suites ship libjpeg.so.8 themselves
- 6A-18/6A-19: RUNPATH for app-private lib dirs; read-only ELFs patched, failures reported
- 6A-20: no build files, bundled dbus services, sound-stack or portal config copied to /usr/share
- 6A-29: Slackware config files listed as X.new are recognised as Slackware-owned
- 6A-33: easyeffects ships lsp-plugins-lv2; virtual "<format>-host" deps satisfied by the app (no ardour)
- 6A-34: runtime includes breeze + plasma-integration built for its Qt (gnomes Qt apps follow the KDE theme)
- 6A-35: download watchdog (a mirror below 32 KiB per 60 s is abandoned)
- 6A-36: the shared runtime keeps its etc/ under /opt/underpants/runtime/etc, never the host /etc
- 6A-20 follow-up: "openxr" added to the host share denylist

System safety:
- 6A-0: SlackBuild archives root-owned only
- 6A-7: slackpkg failures are no longer reported as completed
- 6A-17: /var/cache/slacky-update root-only 0755, log 0644, no fixed /tmp fallbacks
- 6A-27: missing ensure_cache_dir defined (Hyprland/theme shortcut flags work again)
- 6A-28: kernel link protection (fs.protected_*) on by default, --protect-links on|off|status
- 6A-6: no loose host writes from curated deploys (libsystemd.so.0 compat link pkgtools-tracked, no scx dbus copy
  into /etc, dead Hyprland post-install branch without sudo tee / setcap on Slackware files)
- 6A-6b: Antigravity download verified against the AUR b2sum (also cached files)
- 6A-6c: rc.local / rc.local_shutdown daemon hooks as marked blocks, safe add/remove (douninst.sh, upgrade-safe),
  gnomes douninst without unguarded stop or sed-to-EOF (spec docs/rclocal_spec.md)
- 6A-6d: NVIDIA .run installer verified against its .sha256sum (.md5sum fallback), curl -f, temp name

Build: BUILD="60_slacky"
```

## Files changed by Claude in this working tree

- `bin/slacky-update`, `bin/gnomes`
- `cron/slacky-snapper-limine-sync`
- `lib/common.sh`, `lib/mod_limine.sh`, `lib/mod_kernel.sh`, `lib/mod_armor.sh`, `lib/mod_gaming.sh`,
  `lib/gnomes_pacman.py`, `lib/mod_tweaks.sh`, `lib/check_backend.sh`, `lib/mod_gnomes_engine.sh`,
  `lib/mod_packages.sh`, `lib/mod_nvidia.sh`, `lib/mod_rocm.sh`
- `slackbuild/slacky-update.SlackBuild` (BUILD 60), `assets/sysctl.d/50-slacky-protect-links.conf` (new)
- `docs/log.md`, `docs/log_nb.md`, `docs/footprint_spec.md`, `docs/rclocal_spec.md` (new), `claude_log.md`
- `rs_and_legacy_roadmap.md` is gitignored (kept identical in both repos)

## Modified files NOT changed by Claude (check before committing)

`git status` also shows changes Claude did not make in this engagement, most likely from the earlier Gemini sessions:
`.gitignore`, `AGENTS.md`, `README.md`, `bin/slacky-update-tray`, `lib/slacky-update-tray`, `lib/mod_clean.sh`,
`lib/mod_docs.sh`, `lib/mod_sbo.sh`, `lib/mod_secureboot.sh`, `lib/slacky_update_i18n.py`, `locales/*.json`,
the guides under `docs/` (other than the logs and `footprint_spec.md`), and the deleted `assets/screenshots/*` and
`assets/slacky-slackbuilds/*` entries. Review them separately; they are not covered by the Build 59/60 tests above.

## Build 61_slacky (installed 2026-10-12): changed since 60_slacky

```
fix: verified multilib and SlackBuild sources, ROCm keeps Mesa, safe curated replacement (Build 61)

- 6A-1: curated SlackBuild installer works again (sb_script was unset); private build workspace,
  MD5-verified sources (cached copies too), no --no-check-certificate, honest result
- 6A-2: ROCm no longer removes or blacklists Slackware's Mesa OpenCL; rocm.sh hides it from ROCm
  apps (OCL_ICD_VENDORS); built as user in a private dir, Footprint Guard + root-owner gate
- 6A-3: AlienBOB multilib fetched over https, pinned keys, signed CHECKSUMS.md5, per-package md5
- 6A-4: curated deploys remove superseded packages only after the new one is installed, by exact
  package name, never official Slackware packages; removal errors reported
- 6A-5: STRICTGPG in slackpkgplus.conf is no longer switched off silently

Build: BUILD="61_slacky"
```
Files: `lib/mod_sbo.sh` (6A-1, 6A-3), `lib/mod_rocm.sh` + `locales/en.json` + `locales/nb.json` (6A-2),
`lib/mod_gaming.sh` (6A-4), `lib/common.sh` (6A-5), `slackbuild/slacky-update.SlackBuild` (BUILD 61), logs.

## Build 62_slacky: changed since 61_slacky

```
fix: verified NVIDIA module signing with an honest [2/5] status (Build 62)

- 6A-8h: every signed NVIDIA module is checked for the MOK signature before it replaces the old
  one; failures keep the original and turn [2/5] red; symlinked modules (CachyOS layout) are
  skipped; only the NVIDIA driver's own modules are touched

Build: BUILD="62_slacky"
```
Files: `lib/mod_armor.sh`, `bin/slacky-update`, `slackbuild/slacky-update.SlackBuild` (BUILD 62), logs.

## Build 63_slacky: changed since 62_slacky

```
fix: LTS security pass and working self-update (Build 63)

- 6A-39: no group/other-writable files in the package (udev rule dir was 0777 and copied as
  root); mode gate in the SlackBuild, doinst repairs older installs
- 6A-40: self-update works again (quoting bug) and verifies the GitHub SHA256 digest,
  downloads as the user, root only for upgradepkg
- 6A-41: gnomes -R/-S match exact package names (gnomes -R obs no longer hits obs-3d-effect)
- 6A-50: gnomes builds in private dirs and installs only the package it built
- 6A-51: PYTHONSAFEPATH=1 for root-run Python helpers
- 6A-37: plain wording for optional NVIDIA module signing
- 6A-6e: DKMS from the official Slackware package via slackpkg
- 6A-38: Fedora shim 16.1-7 + GRUB 2.12-81.fc45, SHA256-pinned, new package layout

Build: BUILD="63_slacky"
```
Files: `slackbuild/slacky-update.SlackBuild`, `lib/common.sh`, `bin/gnomes`, `bin/slacky-update`,
`lib/gnomes_pacman.py`, `lib/check_backend.sh`, `lib/slacky_tui.py`, `lib/mod_armor.sh`, `lib/mod_nvidia.sh`, logs.

## Build 64_slacky: changed since 63_slacky

```
fix: full update prompts and errors visible again (Build 64)

- 6A-56: acquire_boot_lock silenced stderr for the whole run (exec redirection made permanent),
  so the full update looked frozen at the plan prompt; regression from 6A-8d (Build 58)

Build: BUILD="64_slacky"
```
Files: `lib/common.sh`, `slackbuild/slacky-update.SlackBuild` (BUILD 64), logs.
Findings logged, not fixed: 6A-53 (kernel-headers not listed), 6A-54, 6A-55.

## Build 65_slacky: changed since 64_slacky

```
fix: gnomes never manages or overwrites curated packages (Build 65)

- 6A-59: only _gnomes packages are gnomes-managed; curated packages detected as collisions;
  no canonical-name fallback onto a curated package (GOverlay was replaced by a 416 MB gnomes build)

Build: BUILD="65_slacky"
```
Files: `lib/gnomes_pacman.py`, `slackbuild/slacky-update.SlackBuild` (BUILD 65), logs.
Findings logged, not fixed: 6A-57, 6A-58, 6A-60, 6A-61, 6A-62 (runtime not used by gnomes resolver), 6A-63 (env leak).

## Build 66_slacky: changed since 65_slacky

```
feat: SpiderSense phase 1 lifeline (Build 66)

- snapshot pair (snapper pre/post) around every full update, taken after consent; on failure
  kernel and graphics driver updates wait, the Slackware base proceeds
- 6A-47: run lock in /run/lock (flock, auto-released) replaces the /tmp marker file
- 6A-43: the hourly job repairs an interrupted update even with automatic snapshot sync off
- 6A-42: initramfs built in a private dir, marker + boot lock first, renamed into /boot in one step
- 6A-44: honest [1/5]-[4/5] status lines; DKMS and sbctl results checked
- no restart offer and exit code 30 after a failed startup-menu update
- the status check no longer installs Flatpak runtimes by itself
- 6A-61: kernel-headers no longer triggers the boot step and restart advice; 6A-60: cache size shown

Build: BUILD="66_slacky"
```
Files: `bin/slacky-update`, `lib/common.sh`, `lib/mod_kernel.sh`, `lib/mod_nvidia.sh`, `lib/mod_limine.sh`,
`lib/check_backend.sh`, `cron/slacky-snapper-limine-sync`, `assets/hooks/slacky-limine-hook`,
`slackbuild/slacky-update.SlackBuild` (BUILD 66), `docs/spidersense_spec.md` (draft 0.2), logs.

## Build 67_slacky: changed since 66_slacky

```
feat(gnomes): hold apps that need a newer glibc/libstdc++ than Slackware ships (Build 67)

- pacman master plan P2/L1, done early: symbol headroom is zero today (GLIBC_2.44, GLIBCXX_3.4.36)

Build: BUILD="67_slacky"
```
Files: `lib/gnomes_pacman.py`, `slackbuild/slacky-update.SlackBuild` (BUILD 67), logs.

## Build 68_slacky: changed since 67_slacky

```
fix: Hyprland env kept in user space, no root-owned user log, goverlay 1.9.4 recipe (Build 68)

- 6A-64: hyprland.env no longer overwritten in /etc; generated block in ~/.config/hypr/hyprland.env, read last
- 6A-57: root steps never touch the user's cache log; foreign-owned or symlinked user log removed; silent log writes
- 6A-74: curated goverlay installs again (1.9.4 ships the program as usr/lib/goverlay)

Build: BUILD="68_slacky"
```
Files: `lib/mod_gaming.sh`, `lib/common.sh`, `slackbuild/slacky-update.SlackBuild` (BUILD 68), logs.

## Build 69_slacky: changed since 68_slacky

```
feat: Hyprland setup follows the hardware (Build 69)

- 6A-75: no forced software cursor except NVIDIA older than GTX 16xx
- 6A-76: no GLX vendor variable on single NVIDIA when a live glxinfo check proves it is not needed
- 6A-78: multi-GPU AQ_DRM_DEVICES from PCI slots at login; GPU probe fallback counts display devices only
- 6A-79: new hypridle setups lock after 10 min and before sleep (only when hyprlock is set up)
- 6A-80: hdr.lua.suggestions from monitor EDID (never loaded automatically)
- WP-1: gnomes and curated installs refuse to overwrite another package's files (curated wins on the same name)
- 6A-71: gnomes --build-only never installs; curated fallback only after a yes on a terminal
- 6A-52: gnomes cache no longer writable by other users

Build: BUILD="69_slacky"
```
Files: `lib/mod_gaming.sh`, `lib/common.sh`, `lib/gnomes_pacman.py`, `bin/gnomes`, `slackbuild/slacky-update.SlackBuild` (BUILD 69), logs.

## Build 70_slacky: changed since 69_slacky

```
fix: hyprmod from locked, checksummed sources; Hyprland suite clean-up (Build 70)

- 6A-65: hyprmod v0.4.0 tag + 5 PyPI wheels with sha256; mismatch refuses the build; update check shows the lock
- 6A-66: D-Bus activation files pointing at /usr/lib fixed to /usr/lib64 (portal, polkit agent)
- 6A-66: suite drops dead uwsm entry, cmake/pkg-config files, code generators, modules-load.d, empty dirs
- 6A-66: new autostart seeds: no manual portal start, PipeWire only when not running

Build: BUILD="70_slacky"
```
Files: `lib/mod_gaming.sh`, `slackbuild/slacky-update.SlackBuild` (BUILD 70), logs.

## Build 71_slacky: changed since 70_slacky

```
feat: gnomes --rollback from snapshots, builds on disk, space check; boot module loading (Build 71)

- WP-2: gnomes --rollback <app> rebuilds the previous version from the newest snapshot (no stored copies)
- WP-2: boot-chain packages refused; curated/gnomes kinds never mixed; rolled-back version skipped by updates
- D14: gnomes builds on disk instead of the /tmp tmpfs; free-space check before download
- 6A-83: zenpower, v4l2loopback, i2c-dev load at boot via marked rc.modules.local blocks

Build: BUILD="71_slacky"
```
Files: `lib/gnomes_pacman.py`, `bin/gnomes`, `lib/mod_gaming.sh`, `slackbuild/slacky-update.SlackBuild` (BUILD 71), logs.

## Build 72_slacky: changed since 71_slacky

```
feat: runtime without GPU/audio/TLS copies; package signature checks (log-only); pacman vercmp (Build 72)

- WP-3: GPU, audio and TLS-trust libraries always from Slackware; host-fit check; runtime manifest; runtime 1.1
- WP-7: new lib/gnomes_trust.py (vercmp, gpgv signatures with pinned keys, keyring refresh, DB freshness), log-only
- WP-7: damaged downloads stop the build; files shipped twice with different content are reported

Build: BUILD="72_slacky"
```
Files: `lib/gnomes_pacman.py`, `lib/gnomes_trust.py` (new, add to git), `slackbuild/slacky-update.SlackBuild` (BUILD 72), logs.

## Build 73_slacky: changed since 72_slacky

```
feat: Chaotic-AUR signatures via the pinned chain; localized trust messages (Build 73)

- WP-7: Chaotic .sig downloaded and cached; TNE accepted only through the Pedro-signed chaotic-keyring
- WP-7: GNOMES_TRUST_* messages in en/nb; -Sc removes orphan .sig; same-second keyring refresh fixed

Build: BUILD="73_slacky"
```
Files: `lib/gnomes_pacman.py`, `lib/gnomes_trust.py`, `locales/en.json`, `locales/nb.json`, `slackbuild/slacky-update.SlackBuild` (BUILD 73), logs.

## Build 74_slacky: changed since 73_slacky

```
fix: LTS safety - kernel pruner, ESP wizard, status files, compat32 signature, tar metadata, mirror temp file, sbotools (Build 74)

- 6A-46: stock kernel pruner only removes pkgtools-known kernels by version; running/newest/self-built never touched
- 6A-45: ESP wizard offers only unmounted FAT/empty partitions, ERASE to format, copy verified before fstab
- 6A-48: status.json written without following links (uid-dropped child, 0644); only catalog ids deployed
- 6A-84: cached compat32 glibc installed only after gpg verify from a root-held copy
- 6A-85: raw tar -C / extractions exclude Arch metadata (.PKGINFO/.MTREE/...)
- 6A-87: mirror update via private temp file and URL check
- 6A-49: sbotools bootstrap checks MD5SUM, private dirs, correct source name

Build: BUILD="74_slacky"
```
Files: `lib/mod_clean.sh`, `lib/mod_limine.sh`, `lib/common.sh`, `lib/check_backend.sh`, `lib/mod_gaming.sh`, `lib/mod_packages.sh`, `lib/mod_kernel.sh`, `lib/mod_nvidia.sh`, `lib/mod_sbo.sh`, `slackbuild/slacky-update.SlackBuild` (BUILD 74), logs.

## Build 75_slacky: changed since 74_slacky

```
feat: SpiderSense LTS core - boot guard, 48 h snapshots, order book, one menu writer, hardware profile (Build 75)

- SS-1 (6A-88..93): /boot readiness gate (kernel/driver/boot chain and stock-kernel base wait), HUP-proof run and
  slackpkg, sudo keepalive, foreign pkgtool scan, mirror-age and root-space preflight, run journal tx-state
- SS-2 (6A-94..96): tagged snapshots without snapper cleanup, 48 h pruner (lib/spidersense_snap.py), snapshot menu
  entries only offer kernels present in the snapshot
- SS-3 (6A-97..104): dracut once per kept kernel at the end, purge after the verified seal, no sign-all, boot lock
  only for the chain, Ctrl-C/TERM handled at safe points, .new keeps exec bits (6A-103 partial)
- SS-4 (6A-105/106, 6A-55): limine-snapper-sync places menu orders during a run, fail-closed lock; kernel hook marker
  only; cron reseals only when menu inputs change; menu policy "important"
- 6A-117/118: SpiderSense hardware profile (lib/spidersense_hw.py, rc.local boot probe, --hardware)
- 6A-119: parallel dracut throttled by threads/RAM, one serial retry
- 6A-81/82: NVIDIA VA-API env only when NVIDIA drives the display; hybrid Hyprland without global NVIDIA vars;
  new bin/slacky-prime-run
- 6A-53: kernel-headers (arch x86) listed as an update

Build: BUILD="75_slacky"
```
Files: `bin/slacky-update`, `bin/slacky-prime-run` (new, add to git), `lib/common.sh`, `lib/mod_kernel.sh`,
`lib/mod_limine.sh`, `lib/mod_nvidia.sh`, `lib/mod_gaming.sh`, `lib/mod_packages.sh`, `lib/mod_clean.sh`,
`lib/check_backend.sh`, `lib/spidersense_snap.py` (new, add to git), `lib/spidersense_hw.py` (new, add to git),
`cron/slacky-snapper-limine-sync`, `assets/hooks/slacky-limine-hook`, `slackbuild/slacky-update.SlackBuild` (BUILD 75),
`claude_log.md`, `docs/log.md`, `docs/log_nb.md`.

## Build 76_slacky: changed since 75_slacky

```
fix: snapshot boot entries use the real snapshot subvolume (Build 76)

- 6A-120 (LTS B3): rootflags=subvol= for snapshot entries read from the mount table (/@snapshots on an own
  subvolume), entries left out with a warning when the snapshot folder is on another filesystem

Build: BUILD="76_slacky"
```
Files: `lib/mod_limine.sh`, `lib/common.sh` (comment), `slackbuild/slacky-update.SlackBuild` (BUILD 76), logs.

## Build 77_slacky: changed since 76_slacky

```
fix: LTS fix phase 1 - run robustness, boot partition safety, unsupported configs refused, curated failures honest (Build 77)

- 6A-121..124 (L-B): /boot+ESP readiness, safe ESP copies, Limine managed only on UEFI + EFI binary, BOOTX64 ownership,
  files.json prune, ESP migration checks, Secure Boot wizard fail-closed
- 6A-125..129 (L-C): curated builds never install stubs, theme syntax fix, exact-name uninstall, GPU env by bound driver,
  .new configs, chrome-sandbox setuid, no trap interference inside a full update
- 6A-130..134 (L-D): sysfs NVIDIA generation, pre-Turing/nouveau/opt-out refused, proven blacklist, geninitrd/LILO/ELILO
  hands-off, mkinitrd path, stock kernel removal guard, root MOK dir, pipeline SB audit report-only, safe rollback
- 6A-135..139 (L-E): gnomes TTY/--yes, runtime clean confirm, rc ownership, merge symlinks, narrow cache clean, exit codes,
  heal by file list, safe DB names, gnomes -Qu --json
- 6A-140..144 (L-F): mirror cron report-only + --apply rules, NVIDIA offer gate, fastboot safety, clean/ROCm/SBo hardening
- 6A-145..149 (lead): terminal close survives, suite failures honest, kernel change marks at once, Limine-only marker,
  cron repair + backoff, run lock for deploy/clean, heal as root, single mirror writer, SlackBuild private dirs

Build: BUILD="77_slacky"
```
Files: bin/slacky-update, bin/gnomes, cron/slacky-snapper-limine-sync, lib/common.sh, lib/mod_limine.sh,
lib/mod_secureboot.sh, lib/mod_gaming.sh, lib/mod_nvidia.sh, lib/mod_kernel.sh, lib/mod_armor.sh, lib/mod_packages.sh,
lib/mod_clean.sh, lib/mod_tweaks.sh, lib/mod_rocm.sh, lib/mod_sbo.sh, lib/check_backend.sh, lib/rank_mirrors.py,
lib/gnomes_pacman.py, locales/en.json, locales/nb.json, slackbuild/slacky-update.SlackBuild (BUILD 77), logs.
Still untracked and must be added before tagging LTS (review R1): lib/slacky_tui.py, lib/slacky_doctor.py,
lib/gnomes_trust.py, lib/spidersense_hw.py, lib/spidersense_snap.py, bin/slacky-prime-run, assets/sysctl.d. Do NOT add
bin/spidersense.

## Build 81 (6A-153) - suggested commit
```
fix(gaming): list each update once; curated suite only owns _slacky packages (6A-153)

Build: BUILD="81_slacky"
```
Files: lib/mod_gaming.sh, lib/check_backend.sh, slackbuild/slacky-update.SlackBuild, claude_log.md, docs/log.md,
docs/log_nb.md, rs_and_legacy_roadmap.md (gitignored).

## Build 82 (6A-154, 6A-157) - suggested commit
```
fix(gnomes,boot): keep launchers that hide Slackware files; record the Limine menu and report foreign edits (6A-154, 6A-157)

- 6A-154: heal/cleanup never delete a /usr/bin launcher listed by a Slackware package; they print
  "slackpkg reinstall <pkg>" (advice only); no more edits of /var/log/packages
- 6A-157: /var/lib/slacky-boot/limine-committed written after every verified Limine commit (shared
  spec 6.1 format); hourly cron logs one line when the menu differs from the record (never reseals)

Build: BUILD="82_slacky"
```
Files: lib/gnomes_pacman.py, bin/gnomes, lib/mod_packages.sh, lib/mod_limine.sh, cron/slacky-snapper-limine-sync,
slackbuild/slacky-update.SlackBuild, claude_log.md, docs/log.md, docs/log_nb.md, rs_and_legacy_roadmap.md (gitignored).

## Build 83 (8A-8C, 9A-9D) - suggested commit
```
feat(config,heal): config store capture, consent-only .new handling, detect-and-advise for damaged packages (8A-8C, 9A-9D)

- 8A: lib/slacky_config.py captures stock .new text into /var/lib/slacky-config (shared format 1)
- 8B/8C: .new files change only after a typed y and only in exact-base cases; owner/group/mode kept; -y changes nothing;
  bulk "overwrite all customized files" and default-yes groups removed; slackpkg.conf.new never replaces the conf
- 9A-9D: lib/slacky_heal.py + slacky-update --heal-check; hold before an upgrade of a package with a folder replaced by a link
  (exit 30); one sentence after an update when damage exists; read only, no repair

Build: BUILD="83_slacky"
```
Files: lib/slacky_config.py (new), lib/slacky_heal.py (new), lib/mod_packages.sh, bin/slacky-update,
slackbuild/slacky-update.SlackBuild, claude_log.md, docs/log.md, docs/log_nb.md.
