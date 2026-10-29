# Claude patch-note log (slacky-update, legacy)

### 2026-10-20 Build 96_slacky - 6A-360..366 / 7J-7O - cross-file fixes and the monthly runtime refresh
- 6A-360: when `gnomes_trust.py` is missing or broken, the build now stops with one sentence and uses no downloaded package (before it silently skipped verification); `SLACKY_GNOMES_TRUST=log` keeps the old behaviour.
- 6A-361 (F2): a downloaded repository database replaces the cached one only after `check_db_before_replace` (detached signature, required for CachyOS; parses; not older than the last accepted). A blocked database keeps the cached copy and says why; log mode never blocks. `load_cached_databases` is NOT checked (an in-memory comparison needs a previous database; not trivial, left open).
- 6A-362: `spacenav` without any upstream answer is written to `SLACKY_GAMING_MANUAL_FILE` (the "check by hand" list) instead of counting as a failed check.
- 6A-363: the TUI update list no longer says "up to date" after an offline or partly failed check; a bad `last_check_ts` or non-object status file is ignored.
- 6A-364: Limine committed-record transaction id must match `^[0-9A-Za-z._-]{1,64}$` (else the generated one); the NVIDIA footprint mode is `enforce` unless `SLACKY_SELFTEST=1`; the mirror cache override `SLACKY_MIRROR_CACHE_DIR` is ignored for root.
- 6A-365 (F1): listings with a `./` prefix are accepted in the kernel and NVIDIA version lookups (as in the curated lookup). `slacky-update --nvidia` menu option 2: a failed module build now gives one plain sentence and skips the later steps.
- 7J: `gnomes_pacman.py runtime refresh-status [--no-record]` (read-only, cached databases only): age from the manifest `built`, shared usual-suspect table (16 entries), states nominal / due / due_now / deferred / remembered_veto / unknown / not_applicable. `check_backend.sh` stores it as status key `runtime_refresh` (not counted); `--check` and the tray show one calm line; recorder lines `RR-*` go to the log file.
- 7K: `space_precheck` and the refresh use the same-filesystem rule from `/proc/self/mountinfo` (integer factors rounded up, free = the smaller of the two, shown on `/opt`).
- 7L: `slacky_symver.py startcheck` follows DT_NEEDED and DT_VERNEED of every app through the app, the candidate runtime and the host (S1 missing library, S2 missing symbol version, S3 python/lua minor moved); only NEW failures against the live runtime veto; plugins are counted, never vetoed. `gnomes runtime install` uses the same check, the snapshot gate and names running apps.
- 7M: state file `$XDG_STATE_HOME/underpants/runtime_refresh.json` (written only by the user process of a full update, atomically, unknown fields kept); weekly re-ask after "No"; a stopped candidate is remembered until a member version or the app set changes.
- 7N: interactive full update only (never headless, `-y`, cron or tray): plan line "Underpants runtime refresh (monthly)" after the Slackware base and kernel, before the apps; candidate built as the user in a 0700 work dir with the footprint guard, checked, archive hash pinned, snapshot reused or made (no snapshot support: warning, continue), running apps named (warning, continue), one `sudo upgradepkg --reinstall`, post-check. Shipped OPEN but offer-only.
- 7O: the shared fixtures are copied byte-identical to `docs/runtime_refresh_fixtures/`; `docs/runtime_refresh_spec.md` and `docs/runtime_spec.md` are the Rust repo's copies.
- Files touched: `lib/gnomes_pacman.py`, `lib/slacky_runtime_refresh.py` (new), `lib/slacky_symver.py`, `lib/mod_runtime_refresh.sh` (new), `lib/check_backend.sh`, `lib/common.sh`, `lib/mod_gaming.sh`, `lib/mod_limine.sh`, `lib/mod_nvidia.sh`, `lib/mod_kernel.sh`, `lib/slacky_tui.py`, `lib/slacky_mirrors.py`, `lib/slacky-update-tray`, `bin/slacky-update`, `bin/gnomes`, `locales/en.json`, `locales/nb.json`, `slackbuild/slacky-update.SlackBuild` (installs the new module), `docs/runtime_refresh_spec.md`, `docs/runtime_spec.md`, `docs/runtime_refresh_fixtures/`.
- Verification: `bash -n`, `py_compile`, `gnomes_trust.py selftest` (92 + 30 checks); fixture harness 46 of 46 (detection, state, startability, space); fake-root flow test with a stub engine and stub sudo (install_ok has exactly one upgradepkg, veto/no_space/build_failed/snapshot_failed/postcheck/install_fails/skip_changed, no_snapshot continues with snapshot 0, work and staging folders removed, headless and `-y` never offered); `--check` notice lines; trust gate and database check with a patched downloader; TUI and regex checks. Tests deleted after green.
- NOT verified: a real build and install of the runtime (needs network, sudo and about 12 GB), the real `check_backend.sh` writing the status key end to end, the tray menu line in Qt, the spacenav manual list and the NVIDIA/Limine shell edits beyond `bash -n`, `load_cached_databases` monotonic check (not applied). The owner drill (7P) is still to do.
- Rust mirror: Rust has detection, fixtures and checks only (H11-H14, H17); the builder and the offer come later (decision D1).

### 2026-10-16 Build 89 (pending, not bumped) - 6A-250 / 6A-251 / 6A-260..6A-265 - catalog parsing, safe Limine restore, gnomes cleanup rules
- 6A-250: the gaming catalog is read correctly again. OpenGHub (and Microsoft Edge) have `|` inside a pattern, which shifted the fields, so the `hidden` marker was never seen and OpenGHub was listed. Rows are now split only outside brackets; a row with the wrong number of fields stops the export with one sentence; new `gaming_catalog_selfcheck` fails loudly (used in tests). The bash menu loop and the scan table read the marker from the end of the row.
- 6A-251: `--restore-limine` / menu 6 now takes the shared boot lock, checks the saved pair first (the saved boot loader must be a Limine file whose enrolled BLAKE2B equals the saved limine.conf, every `#hash` boot file in that menu must match the real file, signature when keys exist) and refuses with one plain sentence if not. A safety copy of what it replaces goes to `/var/cache/slacky-update/limine_replaced/<time>` (newest 3 kept); files are staged then renamed back to back; the live pair is checked again and rolled back on a mismatch; errors are no longer swallowed. The committed-menu record and the /boot mirror are updated.
- 6A-260: `rollback_refusal` strips prefixes only, so `linux-cachyos-*` is refused (the old replace cut `cachyos-` out of the middle).
- 6A-261: `deduplicate_storage` links only pairs with the same owner, group and mode (and content), never touches a runtime file (the runtime copy is kept) and hashes only files with a same-size partner. Summary shows how many were left out.
- 6A-262: `clean_cache` keeps only the archive of the INSTALLED name and version (old versions go), skips `.part` files younger than 10 minutes (also with --all), never follows links, only regular files directly in the folder; signatures go with their archive in the same run. Build folders keep the stricter 6 hour rule.
- 6A-263: `purge_gnomes_service_hooks` takes the shared run lock (unless the caller holds it), writes `<file>.slacky-bak`, writes a temp file and renames it, keeps owner and mode, refuses a link, and refuses a result that no longer passes `sh -n`; the command exits 1 and says why.
- 6A-264: `check-collision` and `url` still print `NONE` but exit 1 when nothing is found.
- 6A-265: `gnomes -Qs word` / `-Q word` filters by the words (name or package id, all words, case-insensitive).
- Files touched: `lib/mod_gaming.sh`, `lib/mod_limine.sh`, `lib/gnomes_pacman.py`, `claude_log.md`, `docs/log.md`, `docs/log_nb.md`.
- Verification: `bash -n`, `python3 -I -m py_compile`; offline tests in a temp dir: all 77 catalog rows parse (70 visible, openghub hidden), Limine pair check (good pair, changed kernel, wrong enrolled hash, not a Limine file) and the full restore in a fake root incl. refusal and safety copy, 37 checks for 6A-260..265 (dedup with modes, clean with versions/epoch/.part/links/directories behind a guard that blocks anything outside the temp dir, purge with backup/mode/link/held lock, exit codes, -Qs). Not verified: a real restore on the Btrfs/ESP machine, a real `gnomes -Qs`, `gnomes -Sc` against the real caches.
- Rust mirror: 6A-262 and 6A-265 mirrored in `gnomes-native` (Rust log, same date); 6A-260/261/263/264 were already correct in Rust; 6A-250/251 have no Rust counterpart (Rust has no `|` catalog; `BootCommit::recover` already checks the pair).

### 2026-10-16 Build 76_slacky (next build: 77) - 6A-242 - OBS plugin updates are found on GitHub
- Installed obs-multi-rtmp 0.7.4.0 now shows the update to 0.7.4.4: the update check asks the same GitHub release source the install uses for obs-move-transition, obs-source-record, obs-advanced-scene-switcher, obs-multi-rtmp, obs-composite-blur and obs-teleport (before, it only looked in the Arch/CachyOS repos, which no longer carry them). If GitHub cannot be reached, no update is listed.
- Technical: new helpers `gh_releases_cached` / `github_obs_version` in `PYFASTCHECK` (https to api.github.com only, 5 s timeout, 4 MiB cap, cache 30 min in the same file the resolver uses, so 12 API calls per hour at most). Newest non-prerelease, non-draft release with an asset matching the deploy `asset_pattern`; version taken like the deploy (group 1, else tag). The six deploy table entries (both tables) now also skip prereleases so install and scan agree.
- Files touched: `lib/mod_gaming.sh`, `claude_log.md`, `docs/log.md`, `docs/log_nb.md`.
- Verification: `bash -n`; offline tests with patched urlopen (newest prerelease and draft skipped, no matching asset, API down, redirect away, non-list answer, oversize, cache hit, stale cache, bad repo name) all green; one read-only real call per repo: move-transition 3.2.1, source-record 0.4.8, advanced-scene-switcher 1.36.1, multi-rtmp 0.7.4.4, composite-blur 1.5.2, teleport 0.7.7. Not verified: a full `slacky-update --check` on the installed system.
- Rust mirror: Rust reads pinned releases (obs_pins.rs); no change.

### 2026-10-10 Build 72_slacky - G1 (prep) - Roadmap reference fix
- No program behaviour changed. `rs_and_legacy_roadmap.md` header now says it is referenced from `CLAUDE.md`
  in the Rust repo and `AGENTS.md` in this repo (the Rust `AGENTS.md` was removed by the owner). Copy kept
  identical to the Rust repo's.
- Files touched: `rs_and_legacy_roadmap.md` (gitignored), new `claude_log.md`.
- Nothing to commit except `claude_log.md` if you want to track it.

### 2026-10-10 Build 72_slacky - G1 / 6A - Legacy findings recorded (no code changed)
- No program behaviour changed. The Rust parity audit found legacy issues, recorded as 6A-1..6A-6 in
  `rs_and_legacy_roadmap.md`: broken `install_curated_slackbuild` (`mod_sbo.sh:344/432`), mesa removal in `mod_rocm.sh`,
  unverified AlienBOB http install (`mod_sbo.sh:162`), broad removepkg globs (`mod_gaming.sh:2988-3008`),
  silent `STRICTGPG=off` (`common.sh:1266`), host-taint writes in `mod_gaming.sh`.
- Files touched: `rs_and_legacy_roadmap.md` (gitignored), `claude_log.md`.

### 2026-10-10 Build 72_slacky - 6A-0 (finding) - Own package built with tux ownership
- No program behaviour changed. `slackbuild/slacky-update.SlackBuild:171` runs makepkg as tux without an owner
  override, so the legacy package has the same system-directory taint as the Rust one (G5-0). Recorded in the roadmap.
- Roadmap golden rule 6 now allows Claude to use sudo after asking the owner.

### 2026-10-10 Build 55_slacky (next build: 56) - 6A-0 / G5-0 - Root-owned package archive + ownership gate
- Installing slacky-update no longer changes ownership of `/`, `/etc`, `/usr`, `/usr/bin`, `/var` to the build user.
- `makepkg` runs with `TAR_OPTIONS="--owner=0 --group=0 --numeric-owner"`; fail-closed gate deletes the package and
  exits 1 if any entry is not `0/0`.
- Files touched: `slackbuild/slacky-update.SlackBuild` (only the makepkg block), `docs/log.md`, `docs/log_nb.md`.
- Verification: same real-makepkg test as the Rust side; `bash -n`. Not verified: a full legacy build.
- To commit (owner): the makepkg/gate hunk in `slackbuild/slacky-update.SlackBuild`. NOTE: that file and many others
  already had large uncommitted changes before this (BUILD 7 -> 55, paths /usr/local -> /usr/share, deleted assets);
  review those separately.

### 2026-10-11 Build 55_slacky - 6A-7 (mirror of G5-11) - slackpkg failures are no longer reported as completed
- User-visible: if `slackpkg install-new` or `upgrade-all` fails, the full update says so and keeps the Slackware updates
  pending (before: "slackpkg ... completed" and the updates were cleared).
- Technical: `update_slackware_core` checks the slackpkg exit status (0, 20, 50 = ok per `man slackpkg`), runs the usual
  healing steps, then returns 3 on failure; `bin/slacky-update` already treats only 0/2 as done, so 3 keeps them pending.
- Files: `lib/mod_packages.sh` (only the install-new/upgrade-all/return hunks), `docs/log.md`, `docs/log_nb.md`.
- Verification: bash harness sourcing the real `lib/mod_packages.sh` with stubbed helpers: 20/0 and 0/50 -> RC=0 with
  success; 0/1 and 1/0 -> RC=3, no success line, failure named. `bash -n` ok. Not run against real slackpkg.
- To commit (owner): the three hunks above in `lib/mod_packages.sh` (that file also had older uncommitted changes).

### 2026-10-11 Build 55_slacky - 6A-8a / 6A-8b - Limine reseal can no longer leave an unsigned boot loader; honest [5/5]
- User-visible: if enrolling or signing the Limine EFI fails, the working boot loader is kept and the update says
  "FAILED - do not reboot; run: sudo slacky-update --sync-boot" instead of a green "BLAKE2B enrolled & EFI signed".
  After a successful reseal, a silent check confirms every `path#hash` in limine.conf matches its file and the EFI
  signature verifies.
- Technical: `enroll_limine_config_hash` builds the new EFI(s) in `EFI/limine/.stage-<pid>` from the clean
  `/usr/share/limine/BOOTX64.EFI`, enrolls with the real b2sum (the wrong `<conf path>` first attempt is gone), signs with
  sbctl and verifies (`sbverify --cert db.pem`, new helper `limine_efi_signature_ok`), then swaps them in with `mv` (same
  filesystem). Any failure returns 1 and leaves both live EFIs untouched (before: live EFIs were reset to the unsigned
  binary first and `sbctl sign ... || true` hid failures). `sign_limine_efi_sbctl` returns 1 on an invalid signature.
  New `verify_limine_seal` (b2sum read-back + EFI signature). `bin/slacky-update` [5/5] and
  `sync_bootloader_configuration` (`mod_kernel.sh`) use the real results; a failed enroll/sign is an error.
- Files: `lib/mod_limine.sh`, `lib/mod_kernel.sh`, `bin/slacky-update` (only these hunks), `docs/log.md`, `docs/log_nb.md`.
- Verification: fake-ESP harness sourcing the real `lib/mod_limine.sh` with fake `limine`/`sbctl` (checked that the fakes
  were used): success swaps both EFIs enrolled with the correct b2sum and signed; enroll failure, sign failure and
  "sign exit 0 but no valid signature" all return 1 with both live EFIs byte-identical and no staging dir left; seal check
  passes on matching hashes and fails on one mismatch; [5/5] source check. Tests deleted after green.
  Not verified: real sbctl/sbverify on the machine's ESP (needs root; first real run is the next legacy update or
  `--sync-snapper`).
- Known limits: 6A-8c (abort window), 6A-8d (non-atomic limine.conf write, cron lock hole) still open.
- To commit (owner): the hunks above (these files also carry older uncommitted changes).

### 2026-10-11 Build 55_slacky - 2A / 2B / 2C (P3a, report mode; mirror of B1-B3) - Footprint Guard in the packagers
- User-visible: when a gnomes app, the runtime or a curated gaming package is built, one line reports files that
  would collide with Slackware or have a global effect, e.g. `:: Footprint check: 92 file(s) in <pkg> would be removed
  (report only). Details: ~/.cache/slacky-update/footprint/<pkg>.txt`. Nothing is removed yet (report mode). Packages
  with non-root files are refused before install.
- Technical: `lib/gnomes_pacman.py` new `footprint_*` functions + `footprint-guard` subcommand (`<staging> [--label]
  [--enforce]`, `--verify-archive <txz>`); called in `_run_makepkg_with_progress` (all gnomes apps + runtime) and in
  `lib/mod_gaming.sh` before the tar. Mode via `SLACKY_FOOTPRINT_MODE=report|enforce` (default report; enforce fails
  closed). 2C archive gate in `bin/gnomes` (both upgradepkg sites) and `mod_gaming.sh` (before install).
  `lib/mod_nvidia.sh` (cachyos-nvidia-utils) and `lib/mod_rocm.sh` now tar with `--owner=0 --group=0 --numeric-owner`.
  Rules: `docs/footprint_spec.md` (identical in both repos).
- Files: `lib/gnomes_pacman.py`, `lib/mod_gaming.sh`, `lib/mod_nvidia.sh`, `lib/mod_rocm.sh`, `bin/gnomes`,
  `docs/footprint_spec.md` (new), `docs/log.md`, `docs/log_nb.md`.
- Verification: 14 tests (real pkgdb read-only, temp staging): collision, doinst-symlink collision, vetted own cron,
  junk cron/rc.d, own daemons, install/ and /opt kept, report mode removes nothing, enforce removes only offenders and
  never directories, archive gate root ok / tux refused. Parity with the Rust guard on 646,201 installed files
  (identical 40,384 drops). Dry run earlier: 17 of 69 installed packages would lose files; 9 libraries used by
  audacity/inkscape have the same name/version as the Slackware copy. Tests deleted.
  Not verified: a real package build through the hooks (first real build will show the report line).
- Next: owner reviews reports from real builds, then enforce; P3b (/opt for inkscape, audacity, ...) is a separate decision.
- To commit (owner): the hunks above (files also carry older uncommitted changes).

### 2026-10-11 Build 55_slacky - 6A-9 - Gnomes apps run their Python scripts on the runtime Python (3.14)
- User-visible: gnomes apps whose launcher scripts call `/usr/bin/python3` (Arch: Python 3.14) no longer start the
  Slackware host Python 3.12 and crash with "SRE module mismatch"; they use `/opt/underpants/runtime/bin/python3`.
  Found with the faugus-launcher pilot (P3b).
- Technical: `_relocate_text_and_symlink_paths` (`lib/gnomes_pacman.py`) rewrites `/usr/bin/python`, `/usr/bin/python3`,
  `/usr/bin/python3.14` and `/usr/bin/env python3` in staged text files to the runtime interpreter when it exists.
  Explicit other versions (`/usr/bin/python3.12`), `python3-*` tools and the runtime build itself are left alone.
- Files: `lib/gnomes_pacman.py` (one hunk).
- Verification: regex unit check (6 cases); rebuilt faugus-launcher (build only): launcher now execs the runtime
  python, no `/usr/bin/python3` left; import test of faugus (runner, shortcut, tray_only), PIL, psutil, vdf, gi from the
  extracted package with the wrapper's environment passed. Installed with owner approval (snapshot #652).
  Not verified yet: owner launching faugus + a game.
- To commit (owner): the hunk in `lib/gnomes_pacman.py`.

### 2026-10-11 Build 55_slacky - 6A-11 (CRITICAL) - Gnomes never creates a wrapper that shadows a Slackware program
- User-visible: building audacity with gnomes produced a wrapper named `/usr/bin/env` (it would have replaced
  coreutils' `env`, used by almost every `#!/usr/bin/env` script). Found by the new Footprint Guard report during the P3b
  audacity pilot, before anything was installed. Fixed; the rebuilt package ships only `/usr/bin/audacity`.
- Cause: `.desktop` `Exec=/usr/bin/env GDK_BACKEND=x11 UBUNTU_MENUPROXY=0 audacity %F` was parsed as program `env`, and
  the host-binary map (file lists only) does not see coreutils' doinst symlink `/usr/bin/env`.
- Technical (`lib/gnomes_pacman.py`): new `desktop_exec_program_index()` skips an `env` launcher (incl. `-u NAME`,
  `-C DIR`, `-S STR`) and `VAR=value` tokens, used when registering desktop binaries and when rewriting `Exec=` (the
  `env VAR=...` prefix is kept, only the program becomes `/usr/bin/<prog>`); wrapper creation skips any name whose
  `usr/bin/<name>` a Slackware package owns according to `footprint_load_owners()` (file lists + doinst symlinks);
  `env` added to PROTECTED_HOST_BINARIES.
- Verification: parser checks (audacity Exec, `env -u FOO bar`, `env -i A=1 prog`, plain); audacity rebuilt: no
  `usr/bin/env`, Exec rewritten correctly, archive all 0/0, Footprint Guard silent, 140 ELFs resolve, no bundled Python
  stdlib. Installed next to the curated audacity with owner approval (snapshot #656); `/usr/bin/env` unchanged.
- To commit (owner): the hunks above in `lib/gnomes_pacman.py`.

### 2026-10-11 Build 55_slacky - 6A-13 / 2A / 2B - Hyprland suites bring their own libjpeg.so.8; Footprint Guard enforces by default
- User-visible: the next build of `hyprland-noctalia` or `hyprland-core` ships `libjpeg.so.8` itself (Arch JPEG-8, needed by
  libhyprgraphics). Before, it only worked on this machine because the curated audacity package happened to install it;
  on a clean Slackware it would be missing. Packages are now cleaned automatically: files owned by Slackware and
  unvetted global files are removed from every package we build (one line per package when something is removed).
- Technical: `lib/mod_gaming.sh` catalog: `libjpeg-turbo-*.pkg.tar.zst` added to the extras of both Hyprland entries; the
  guard (enforce) strips the 20 Slackware-owned parts (cjpeg/djpeg/..., headers, pc/cmake, libturbojpeg, `libjpeg.so`) and
  keeps `libjpeg.so.8*`. Footprint mode default changed report -> enforce in `lib/gnomes_pacman.py` and `lib/mod_gaming.sh`
  (`SLACKY_FOOTPRINT_MODE=report` to only list). `docs/footprint_spec.md` updated (identical in both repos).
- Verification: simulation with the real Arch libjpeg-turbo 3.2.0-2 (sha256 verified) mapped like mod_gaming extras + guard
  enforce: 20 removed (all Slackware-owned), kept libjpeg.so.8 + .8.3.2 + docs/man, no collisions; CLI test: default
  enforce removes, report keeps. `bash -n` / python syntax ok. No Hyprland build was run (mod_gaming has no build-only mode
  and installs immediately); takes effect at the next Hyprland update.
- Known limits / risks: on the next runtime rebuild the guard drops the runtime's `etc/profile.d` files (debuginfod,
  freetype2, gpm, opencascade, vapoursynth) and its Slackware-owned `/etc` files (fonts.conf, avahi, krb5 ...); apps
  that relied on those env files may need wrapper env later. After the next Hyprland build, the curated audacity can be
  removed (then 2b: reinstall libjpeg-turbo, libid3tag; rebuild portaudio, twolame from SBo).
- To commit (owner): the hunks above (`lib/mod_gaming.sh`, `lib/gnomes_pacman.py`, `docs/footprint_spec.md`).

### 2026-10-11 Build 55_slacky - 6A-13 (fix + verified) - Hyprland suite now really ships libjpeg.so.8
- The first rebuild did not fetch libjpeg-turbo: extras are resolved from the two Python catalogs in `lib/mod_gaming.sh`
  (single resolve ~L1398, batch ~L2104); the bash catalog line is display-only. Added the libjpeg-turbo pattern to
  `hyprland-noctalia` and `hyprland-core` in both Python catalogs (anchored so `lib32-libjpeg-turbo` does not match).
- Verified on the machine (owner ran the rebuild, snapshot #658): 28 files fetched incl. libjpeg-turbo-3.2.0-2; Footprint
  Guard (enforce) removed 26 Slackware-owned files (cjpeg/djpeg/..., libjpeg.so, libturbojpeg*, pc/cmake, lua.pc, libical
  dev symlinks/pc/cmake/vapi); the installed `underpants-hyprland-noctalia` now owns `usr/lib64/libjpeg.so.8` and
  `libjpeg.so.8.3.2` (root:root); `libhyprgraphics` resolves libjpeg.so.8. First rebuild (snapshot #657) also installed fine.
- Files: `lib/mod_gaming.sh` (4 catalog lines).
- Next: 2K (remove curated audacity; libjpeg.so.8 stays, owned by the Hyprland suite), then 2b.

### 2026-10-11 Build 55_slacky - 2K - Curated audacity replaced by the gnomes build (system change, no code change)
- The curated `cachyos-gnome-audacity-3.7.9-x86_64-1_slacky` was removed (owner ran it, snapshot #659). Audacity now runs
  from `/opt/underpants/pkgs/audacity` (gnomes, runtime libs); `/etc/ld.so.conf.d/audacity.conf` is gone; 312 curated-only
  files removed, 151 shared files kept. `libjpeg.so.8` stays (owned by the Hyprland suite since 6A-13); `libhyprgraphics`
  has no unresolved libraries. Pre-check: no other installed program needed a library owned only by the curated package.
- Audacity audio: use the JACK host (PipeWire); the ALSA host in gnomes apps waits for 6A-12.
- Still to do (2b): reinstall Slackware `libjpeg-turbo` and `libid3tag` (also restores `/usr/lib64/libjpeg.so -> .62`) and
  rebuild SBo `portaudio` and `twolame`, whose files were overwritten by the curated package.

### 2026-10-11 Build 55_slacky - 2b (part 1: audacity set) - Slackware/SBo files restored (system repair, no code change)
- Owner ran `slackpkg reinstall libjpeg-turbo libid3tag` (also reinstalled libjpeg-turbo-compat32; `.new` files kept with K)
  and `sboupgrade -f portaudio twolame`. Verified: `/usr/lib64/libjpeg.so -> libjpeg.so.62` again (was `.8`);
  libid3tag/cjpeg carry the Slackware build date (2026-09-02); portaudio and twolame rebuilt from SBo (files dated
  2026-10-11 22:30, root:root, 0 missing files). `libjpeg.so.8` still present (owned by the Hyprland suite).
- Remaining 2b: the other Slackware packages whose files were overwritten by curated/gnomes packages (inkscape set:
  poppler, librevenge, libvisio, libwpg, xpdf; runtime-all set: fontconfig, avahi, krb5, e2fsprogs, libtirpc; others from
  the P3 dry run). Each set only after the curated package that overwrote it is rebuilt/removed with the guard on.

### 2026-10-11 Build 55_slacky - 6A-10 - Gnomes Python apps get a private venv instead of an exported PYTHONPATH
- User-visible: programs started from a gnomes Python app (games via umu/Proton, other Python versions) no longer inherit
  the app's module paths. Found with the faugus pilot: Proton's Python inside steamrt4 crashed on the app's bundled 3.14
  stdlib (`sys.flags.context_aware_warnings`). Lutris uses the same pattern and is fixed when rebuilt.
- Technical (`lib/gnomes_pacman.py`): new `runtime_python_version()`, `venv_site_packages()`, `_create_python_venv()`.
  When the app has `lib/python<runtime major.minor>/site-packages`, the build adds `APP_ROOT/.venv/` (pyvenv.cfg with
  `home = /opt/underpants/runtime/bin`, `include-system-site-packages = true`; `bin/python{,3,3.14}` -> runtime python;
  `lib/python3.14/site-packages` -> the app's site-packages) and a `_underpants_app_paths.pth` with the extra module dirs
  the wrapper used to export (lib/* and share/* dirs except bundled `python*` stdlib copies, lib/<app>/{lib,Mod}). Created
  after patchelf so patchelf never follows the symlink into the runtime. 6A-9 now rewrites `/usr/bin/python3` to
  `APP_ROOT/.venv/bin/python3` for such apps. Wrapper: no `PYTHONPATH` export when `.venv/pyvenv.cfg` exists; the shebang
  selector prefers `.venv/bin/python3`. Apps without a matching site-packages keep the old behaviour.
- Verification: faugus-launcher rebuilt (build only): `.venv` present (symlinks, pyvenv.cfg), launcher execs the venv
  python, wrapper does not export PYTHONPATH; mechanism test in a temp copy: faugus/runner/shortcut/tray_only/PIL/psutil/
  vdf/gi import without PYTHONPATH, stdlib comes from the runtime, a child shell sees PYTHONPATH unset and host Python
  3.12 runs. Not yet verified: a real game launch through the gnomes faugus (needs install).
- Known limit: the wrapper still exports LD_LIBRARY_PATH (runtime libs) to child programs (K17); pressure-vessel resets
  it inside the Steam runtime, but host tools started by the app see it.
- To commit (owner): the hunks in `lib/gnomes_pacman.py`.

### 2026-10-11 Build 55_slacky - 6A-14 - Gnomes Python venv apps no longer export LD_LIBRARY_PATH
- User-visible: programs started from a gnomes Python app with a private venv (games via umu/Proton) get the host
  graphics stack instead of the runtime's. Seen with the faugus pilot: pressure-vessel warned
  `"opt/underpants/runtime/share/libdrm" is unlikely to appear in "/run/host"`, i.e. it captured the runtime's libdrm
  (the runtime also ships Arch libGLX/libEGL/libgbm/libX11/libXrandr).
- Technical (`lib/gnomes_pacman.py` wrapper template): the LD_LIBRARY_PATH export and the nested-lib loop are skipped when
  `${APP_ROOT}/.venv/pyvenv.cfg` exists; such apps resolve libraries via the RUNPATH patchelf sets. Also fixed a 6A-10 slowdown:
  the venv decision ran once per relocated text file (one runtime-python subprocess per file; faugus build hit a 10 min
  timeout); now decided once per build and the runtime version is cached (faugus build 3.3 s).
- Verification: faugus venv python imports faugus (runner, shortcut, tray_only), PIL, psutil, vdf, gi + Gtk 4 with
  LD_LIBRARY_PATH unset; rebuilt package wrapper passes `sh -n` and contains the guard. Not yet verified: game launch.
- To commit (owner): the hunks in `lib/gnomes_pacman.py`.

### 2026-10-11 Build 55_slacky - 6A-18 - Gnomes apps find libraries in their own subfolders without LD_LIBRARY_PATH
- User-visible: gnomes inkscape (venv app) can start on its own libraries; before, its binary only found
  `libinkscape_base.so` through the curated package's `/etc/ld.so.conf.d/inkscape.conf` (mixing two builds) and would not
  start at all after the curated package is removed.
- Technical (`lib/gnomes_pacman.py` `patch_elf_rpaths`): index all `*.so*` names in the tree; per ELF, NEEDED libs that are
  in the app but not reachable via `$ORIGIN/../lib:$ORIGIN/lib:$ORIGIN` get `$ORIGIN/<relpath>` entries inserted before
  `/opt/underpants/common/lib` (top-level lib dirs first). Additive only; base RUNPATH unchanged for all other ELFs.
- Verification: fake-root test with real gcc-built ELFs (nested lib, plugin needing lib/, python ext, plain bin, moved
  tree; all run/resolve without LD_LIBRARY_PATH) green and deleted. Rebuilt inkscape: 295 ELF, with LD_LIBRARY_PATH unset
  libinkscape_base resolves inside the app; only `libheif.so.1` missing (GraphicsMagick heif coder).
- Known limits: patchelf still fails silently on read-only ELFs (0555, e.g. perl `Magick.so` keeps RUNPATH /usr/lib) ->
  6A-19. Same function also patches the runtime on its next rebuild (additive).
- To commit (owner): the `patch_elf_rpaths` hunk in `lib/gnomes_pacman.py`.

### 2026-10-11 Build 55_slacky - 6A-19 - Gnomes patches read-only libraries and reports patch failures
- User-visible: read-only ELF files in gnomes packages now get the Underpants library path (before: e.g. perl
  Graphics::Magick `Magick.so` 0555 kept RUNPATH /usr/lib); a failed patch prints one line instead of being swallowed.
- Technical (`lib/gnomes_pacman.py` `patch_elf_rpaths`): ELF type check (only ET_EXEC/ET_DYN), temporary u+w with mode
  restored in `finally`, `--set-rpath` exit code checked (no dynamic section = skipped, otherwise failure), failures listed
  relative to the tree. Return value (patched count) unchanged; the build is not stopped by a failure.
- Verification: fake-root test (0555 XS module patched + mode 555 restored + resolves; .o and static binary skipped without
  report; simulated patchelf failure reported once; silent on success) green and deleted.
- To commit (owner): the `patch_elf_rpaths` hunks in `lib/gnomes_pacman.py` (together with 6A-18).

### 2026-10-11 Build 55_slacky - 6A-20 / 6A-12 - Gnomes host share denylist + own-dbus-service filter; ALSA plugin dir
- User-visible: new gnomes builds no longer put build files, sound-stack config, portal config or bundled dbus services
  into /usr/share (claude-desktop/lutris had replaced the desktop-wide xdg-desktop-portal services, Exec pointing into
  /opt/underpants/pkgs/claude-desktop). ALSA devices work in gnomes apps; game launchers excluded.
- Technical (`lib/gnomes_pacman.py`): module constants `HOST_SHARE_SKIP` and `GAME_LAUNCHER_APPS`; share mirror skips
  HOST_SHARE_SKIP, `dbus-1` copies only `services/*.service` whose name contains the app name (suffix -bin/-git/-appimage
  stripped); wrapper template gets an `alsa_block` (`[ -z "${ALSA_PLUGIN_DIR:-}" ]` guard) unless the app is a launcher.
- Verification: wrapper test (sh -n for audacity/faugus/lutris, block present/absent, user value kept, no other diff)
  green and deleted. Build-only: flameshot keeps its own dbus service, drops qlogging-categories6, wrapper has the ALSA
  block; lutris drops 63 dbus-1 files, pkgconfig and the cosmic portal config, wrapper has no ALSA block. Not installed.
- Follow-ups: existing installs keep the old files until rebuilt (claude-desktop, lutris, easyeffects, audacity, ...);
  then `slackpkg reinstall xdg-desktop-portal` (2b) restores the Slackware portal services. Option C (allowlist) pending.
  Rust: no native gnomes builder yet; the D-series port must carry HOST_SHARE_SKIP, the dbus filter and the ALSA rule.
- To commit (owner): the 6A-12/6A-20 hunks in `lib/gnomes_pacman.py`.

### 2026-10-12 Build 55_slacky - 6A-21 - Rebuilt gnomes apps without host share junk (5 of 8 installed)
- User-visible: audacity, filezilla, lutris, nwg-displays, vlc (3.0.23 -> 3.0.24) reinstalled from new builds (snapshot
  #669): no build files, portal/dbus services or sound-stack config in /usr/share any more; lutris' COSMIC portal service gone.
- NOT installed: easyeffects and flameshot (new Arch builds need Qt_6.12, the runtime has older Qt6Core; and venv apps
  cannot find libpxbackend because the runtime libproxy.so.1 relied on LD_LIBRARY_PATH) -> 6A-23/6A-24. claude-desktop
  2.31226.1 built and clean, to be installed by the owner after closing Claude (scratchpad p6a21_claude_desktop.sh).
- Verification: per package: archive 0/0, 0 host files owned by Slackware, ldd with the wrapper's semantics (venv: no
  LD_LIBRARY_PATH) 0 missing for the 5 installed + claude-desktop.
- Follow-up: 2b reinstall of the Slackware packages these apps overwrote earlier (xdg-desktop-portal still has the
  claude-desktop portal Exec until reinstalled).

### 2026-10-12 Build 55_slacky - 6A-25 - Hyprland session gets a D-Bus session bus again
- User-visible: after the 6A-13 suite rebuild the SDDM Hyprland session had no session bus (noctalia "dbus disabled",
  no tray icons). The suites now package `/usr/bin/start-hyprland-session` (env + hyprland.env + `dbus-run-session`
  around Arch's `start-hyprland` watchdog when no bus) and a `hyprland.desktop` pointing to it.
- Root cause (FACT): Hyprland 0.56 ships `/usr/bin/start-hyprland` (binary), which replaced our 2026-09-23 wrapper
  script; the post-install branch that wrote it (`mod_gaming.sh` ~L6982) is dead since commit 96b304b (2026-09-25):
  the font-mesh `elif` at ~L6810 already matches hyprland-noctalia/core. That dead branch also holds the pipewire
  `setcap -r` workaround and `/etc/hypr/hyprland.env` generation (left untouched; 6A-26).
- Verification: fake-root test (hook writes launcher 755 + desktop 644 only for the two suites; launcher: no bus ->
  `dbus-run-session start-hyprland`, bus present -> direct, env file sourced, fallbacks to Hyprland / no
  dbus-run-session) green and deleted. Not yet verified on the machine (needs suite rebuild + re-login).
- To commit (owner): the 6A-25 hunk in `lib/mod_gaming.sh`.

### 2026-10-12 Build 55_slacky - 6A-25 verified / 6A-27 - Session bus confirmed; missing ensure_cache_dir added
- 6A-25 VERIFIED on the machine after `--gaming-deploy hyprland-noctalia` + re-login: Hyprland has
  DBUS_SESSION_BUS_ADDRESS (dbus-run-session via start-hyprland-session), noctalia has it, the bus lists
  org.kde.StatusNotifierWatcher, org.freedesktop.Notifications and org.freedesktop.portal.Desktop; the portal runs from
  /usr/libexec (Slackware, 6A-21/2b confirmed).
- 6A-27 (`lib/common.sh`): `ensure_cache_dir` was called by 7 shortcut flags since commit 1e1e25c but never defined
  ("command not found" on `--hyprland-noctalia`). Defined: create CACHE_DIR root:root 0755 only when missing.
  Test (existing dir untouched, missing dir -> sudo install -d -m 0755 -o root -g root) green and deleted.
- To commit (owner): the 6A-27 hunk in `lib/common.sh`.

### 2026-10-12 Build 56_slacky - 6A-17 / 6A-28 - Root-only cache and log; link protection on by default
- User-visible: /var/cache/slacky-update root:root 0755, /var/log/slacky-update.log 0644; user-mode checks keep
  working via ~/.cache/slacky-update (persistent). New `slacky-update --protect-links on|off|status`; protection on by default.
- Technical: `init_storage` (common.sh) no longer sets 1777/0666; as root or with cached sudo (-n) it creates the dirs
  root 0755 and repairs a non-root/world-writable cache once (`find ... -print -quit`, chown/chmod -R, no symlink
  following); non-root log falls back to the user cache. doinst does the same repair at install. get_cache_dir
  (mod_kernel x2, mod_gaming x3, gnomes) and check_backend: no fixed /tmp fallback, private mkdtemp instead;
  mod_gnomes_engine and a mod_gaming status reader drop /tmp paths. 6A-28: package ships
  etc/sysctl.d/50-slacky-protect-links.conf.new, doinst `config()` + `sysctl -q -p`; mod_tweaks
  is_/deploy_/revert_protect_links (revert writes 0-values so upgrades keep the choice), not in apply/revert-all.
- Verification: fake-root tests (unshare -r): cache/log repair, symlink targets untouched (666/777 kept), second run
  no-op, non-root log fallback, mkdtemp fallbacks; doinst fresh/identical/user-changed config cases; tweak on/off files.
  All green and deleted. Package 56_slacky built (588 entries, all 0/0).
- Known limits: tweak menu entry not added (TUI hard-codes 9 items; E-series). Rust uses /var/cache/slacky-update-rs
  (1777, root-owned) and still reads the legacy cache path (rule-1) -> Rust tasks.
- To commit (owner): common.sh, mod_kernel.sh, mod_gaming.sh, gnomes_pacman.py, check_backend.sh, mod_gnomes_engine.sh,
  mod_tweaks.sh, bin/slacky-update, slackbuild/slacky-update.SlackBuild (BUILD 56), assets/sysctl.d/.

### 2026-10-12 Build 56_slacky - 6A-29 / B10 - Footprint Guard: X.new in a Slackware file list owns X
- User-visible: gnomes builds stop shipping Arch versions of Slackware config files (openssl.cnf, mke2fs.conf, netconfig,
  fuse.conf, avahi-daemon.conf, libva.conf, ldap.conf, sensors3.conf, pulse client.conf, ...).
- Technical: `footprint_load_owners` adds `X` (reason "config file") for every `X.new`; Rust `FootprintGuard::load`
  mirrored as B10 (Rust repo). Found after the runtime rebuild: slackpkg left openssl.cnf.new / mke2fs.conf.new /
  client.conf.new because the live files were Arch versions owned by underpants-runtime-all.
- Verification: legacy fake-pkgdb test and Rust integration test (cargo test) green and deleted. Read-only scan: 16 such
  files in installed packages (runtime 11, claude-desktop 5), owners: avahi e2fsprogs fuse3 gtk+3 libnl3 libtirpc libva
  libvdpau lm_sensors ndctl openldap openssl pulseaudio.
- Follow-up: rebuild runtime + claude-desktop, upgradepkg (pkgtools then deletes those files, since Slackware lists only
  X.new), immediately `slackpkg reinstall` the owners so config() recreates the Slackware versions.
- To commit (owner): the 6A-29 hunk in `lib/gnomes_pacman.py`.

### 2026-10-12 Build 56_slacky - 6A-8e - Always reseal in [5/5]; real MOK signature check
- Root cause (FACT): `enforce_secure_boot_armor` called `sync_bootloader_configuration` mid-pipeline (not guarded by
  DEFER_BOOT_SYNC) -> SLACKY_LIMINE_SEALED=1 -> [3/5] dracut and [4/5] sbctl signing changed boot files -> [5/5]
  skipped generate+enroll -> stale hash on the new entry (FAILED shown since 6A-8b, entry panics under SB).
- Fix: armor sync only when DEFER_BOOT_SYNC != 1; [5/5] always generate + enroll + verify; kernel "signed" check is
  `sbverify --cert $MOK_CRT` (was `--list | grep -i signature`, which matched "No signature table present"); signed temp
  verified before `mv`.
- Verification: stub test (fake /boot: unsigned / MOK-signed / foreign / bad-signature kernels; deferred vs standalone
  sync; no SEALED skip left) green and deleted. Not exercised on real hardware.
- Known limits: module signing still swallows errors (`|| true`, NVIDIA refused = no X, not a brick) -> follow-up;
  sbctl-signed kernels still count as signed (correct for Limine+sbctl, wrong for a shim/MOK-only chain).
- To commit (owner): lib/mod_armor.sh, bin/slacky-update.

### 2026-10-12 Build 56_slacky - 6A-8f - GPG check for the NVIDIA module and r8125 packages
- Technical: after the kernel/headers GPG checks, a loop verifies `${nv_file}` and `${r8125_file}` against their .sig
  (verify_cachyos_gpg_signature, fail-closed, cleanup, return 1 before any write). MODERN-GPU fallback curl now also
  fetches `${nv_url}.sig`; extraction only after GPG + integrity pass.
- Verification: snippet tests (both signed, bad sig, missing sig, no extras; fallback signed / unsigned) green, deleted.
  FACT: mirror.cachyos.org x86_64_v4/cachyos-v4 serves .sig (HTTP 200) for linux-cachyos-bore-nvidia-open and -r8125
  7.2.9-2, so normal updates are not blocked. Not checked: other mirrors; the .run installer and DKMS bootstrap
  tarballs (mod_nvidia.sh) still have no checksum (lower priority).
- To commit (owner): lib/mod_kernel.sh.

### 2026-10-12 Build 56_slacky - 6A-31 - .sig availability matrix across all CPU-tier repos (read-only)
- Every repo the tier detection can select was checked for kernel, headers, nvidia(-open), r8125 and NVIDIA suite
  packages: cachyos-znver4 64/64, cachyos-v4 115/115, cachyos-v3 114/114, cachyos (x86_64) 76/76, Arch core 4/4,
  Arch extra 15/15 have a .sig (HTTP 200). Fail-closed GPG (6A-8f) therefore does not block normal updates on any tier.
- Limit: primary mirrors only (mirror.cachyos.org, geo.mirror.pkgbuild.com), which the kernel/NVIDIA code hard-codes.

### 2026-10-12 Build 56_slacky - 6A-8d - Shared boot lock, atomic limine.conf write, cron fingerprint on success
- Technical: `acquire_boot_lock` (common.sh): flock on /run/lock/boot-partition.lock via fd 9 (creates it root 0644 if
  missing), waits up to 300 s with a plain-language message, exports SLACKY_BOOT_LOCK_HELD (nested calls and the cron
  job's child skip). Taken at the start of the full update (bin, after DEFER_BOOT_SYNC), in
  generate_limine_configuration and enroll_and_sign_limine. limine.conf: stage `${file}.new.$$` on the ESP, chmod,
  sync, `mv -f`, sync; old file untouched on any failure. Cron: PID-checked /tmp running-lock, exports
  SLACKY_BOOT_LOCK_HELD after flock, fingerprint written only when the sync succeeded.
- Verification: test (free lock, wait for holder, nested guard, two contenders without interleave, staging success /
  cp failure / mv failure, stale vs live PID, cron export + gated fingerprint) green and deleted.
- Known limits: kernel deploys started outside the full update (menus, kernel picker) write /boot before the lock is
  taken in generate; EFI restore/clean-unsigned writers not locked; staged EFI is still synced after the rename and
  re-signed in place (6A-8c will swap conf+EFI as a pair).
- To commit (owner): lib/common.sh, lib/mod_limine.sh, bin/slacky-update, cron/slacky-snapper-limine-sync.

### 2026-10-12 Build 57_slacky - 6A-8d / 6A-8e / 6A-8f / 6A-29 - Installed and checked on the machine
- 57_slacky built (588 entries, all 0/0) and installed by the owner (snapshot #688).
- Real `sudo slacky-update --sync-boot` on the Secure Boot machine: initramfs for 9 kernels regenerated, BLAKE2B
  enrolled, Limine EFI signed with sbctl, final line green; no error, no lock wait. This exercises the shared boot lock,
  the staged limine.conf write and the reseal path.

### 2026-10-12 Build 57_slacky+ (not yet packaged) - 6A-8c - Pair commit of limine.conf + EFI, .prev pair, reseal marker
- Technical: generate_limine_configuration stages `${cfg}.new.$$` and renames it to `${cfg}.next` (marks pending);
  enroll_limine_config_hash hashes `.next` when present, enrolls/signs/verifies staged EFIs (6A-8a), then commits:
  traps for HUP/INT/TERM saved and ignored, live conf + EFIs copied to `.prev`, sync, `mv .next -> limine.conf`, `mv`
  each EFI, sync, traps restored (`eval` of `trap -p`), marker cleared; any failed rename restores moved files from
  `.prev`. Failures before the commit drop `.next` (live pair untouched). /boot mirror copy moved to the commit.
  mark_boot_reseal_pending also before the kernel copy to /boot. Cron drops its fingerprint while the marker exists.
- Verification: fake-ESP test (normal commit; enroll-config failure; second EFI rename failure -> full rollback; trap
  restored; generate targets .next only; cron marker) green and deleted. Diff: tests/6A-8c.diff in the Rust repo (temp).
- Known limits: sign_limine_efi_sbctl still re-signs the live EFI in place after the commit (registration in the sbctl
  db); two renames cannot be one atomic step (microsecond window); marker lingers harmlessly on GRUB-only systems.
- To commit (owner): lib/common.sh, lib/mod_limine.sh, lib/mod_kernel.sh, cron/slacky-snapper-limine-sync.

### 2026-10-12 Build 58_slacky - 6A-8c - Installed and checked on the machine
- 58_slacky (588 entries, 0/0) installed by the owner (snapshot #689). Real `sudo slacky-update --sync-boot` on the
  Secure Boot machine: enroll + sign + seal check green, no error; the reseal-pending marker was set and cleared
  (absent afterwards), i.e. the limine.conf.next + EFI pair commit ran end to end and verify_limine_seal accepted it.

### 2026-10-12 Build 58_slacky+ (not yet packaged) - 6A-8g - Blocking /boot + ESP space preflight, kernel copy check
- Technical: `largest_boot_initramfs_mb` and `require_boot_space <MB> <what>` (df -Pk on /boot and the Limine ESP when
  it is a different filesystem; plain-language refusal). Kernel deploy: need = vmlinuz size from the package listing
  + largest initramfs + 64 MB, checked before `tar -x` (refusal cleans the downloads, returns 1).
  generate_kernel_initramfs: need = max(largest initramfs, 64) + 64 MB, returns 1 on refusal. vmlinuz copy chain
  (14 branches) records `vm_src`; `cmp -s` source vs /boot copy, incomplete copy removed + return 1. The advisory
  check_boot_disk_space still prints its 75 % warning.
- Verification: test (largest initramfs, enough / too little space + message, identical / truncated copy, size parser on
  a real zstd package, both checks blocking) green and deleted.
- To commit (owner): lib/mod_kernel.sh.

### 2026-10-12 Build 59_slacky - 6A-8g refinement - Space check aware of boot loader and disk layout (owner question)
- Only the filesystem holding /boot is checked (root fs with GRUB, a small /boot partition, or the ESP); the Limine ESP
  is added only when is_limine_installed and it is a different filesystem (detect_limine_esp_path returns /boot/efi on
  GRUB systems, which must not block). Need: kernel = vmlinuz + largest image (32 MB if none) + margin; initramfs =
  (kernels without an image) x largest + margin; margin = max(16 MB, largest/4).
- Verification: layout test (GRUB small /boot + tiny ESP ignored, GRUB /boot too small refused, Limine separate ESP
  checked, Limine /boot == ESP single check, formulas, old fixed +64 rules gone) green and deleted.

### 2026-10-12 Build 59_slacky - 6A-8g - Installed and checked on the machine
- 59_slacky (588 entries, 0/0) installed by the owner (snapshot #690). Real `sudo slacky-update --sync-boot`: initramfs
  for all kernels regenerated through the new space check (no refusal at 31 % ESP use), enroll + sign + seal check
  green, reseal marker cleared. All 6A-8a..g items are now in the installed legacy package.

### 2026-10-12 Build 59_slacky+ (gnomes only) - 6A-23/24 / 6A-33 - easyeffects + flameshot on the new runtime; LSP plugins
- 6A-23/24: easyeffects and flameshot rebuilt against runtime Qt 6.12 and installed (Qt_6.12 / libpxbackend gaps gone,
  owner tested both). Remaining unresolved libs are optional plugins only (sonnet voikko/hspell, assimp, PySide6 bindings).
- 6A-33: MODULAR_APP_PLUGINS["easyeffects"] = ["lsp-plugins-lv2"]; VIRTUAL_PROVIDES_DEFAULT adds lv2/vst/vst3/ladspa/
  clap/dssi "-host" as satisfied by the app (first build pulled ardour-9.8: 17,527 media files). Final package: 63 deps,
  96.5 MB, 199 LSP plugins, 58 host files, 0 Slackware-owned; installed by the owner (snapshot), starts without errors.
- Note: one build attempt hung > 25 min with no output (python stdout buffered; INFERENCE: stalled download). Builds now
  run with `python3 -u`; a download stall watchdog is a follow-up for the gnomes downloader.
- To commit (owner): the 6A-33 hunks in `lib/gnomes_pacman.py`.

### 2026-10-12 Build 59_slacky+ (gnomes only) - 6A-20 follow-up - "openxr" added to HOST_SHARE_SKIP
- easyeffects (dependency openxr) registered three OpenXR validation/api_dump layers host-wide in
  /usr/share/openxr/1/api_layers/explicit.d; now kept in the app. "vulkan" deliberately not skipped: gamescope's
  VkLayer_FROG_gamescope_wsi implicit layer must stay visible to games. Takes effect on the next easyeffects rebuild.

### 2026-10-12 Build 59_slacky+ (gnomes only) - 6A-34 / 6A-36 - KDE theme plugins in the runtime; runtime /etc stays in /opt
- 6A-34: "breeze" + "plasma-integration" added to runtime profiles gui and all. Cause (FACT): owner's Hyprland env sets
  QT_QPA_PLATFORMTHEME=kde and QT_STYLE_OVERRIDE=Breeze; host KDEPlasmaPlatformTheme6.so / breeze6.so are built for
  Slackware Qt 6.11.2, runtime Qt is 6.12 -> light Fusion fallback. Runtime grows 350 -> 539 packages (968 MB txz).
- 6A-36: transmute_runtime_profile merges package etc/ into /opt/underpants/runtime/etc instead of the host /etc. The
  installed runtime owned 21 host /etc files (gnutls/config ktls=false, MIT-example krb5.conf, tpm2-tss, sensord,
  sndiod, healthd, ts.conf, avahi-autoipd.action, debuginfod urls); the new build adds 0 (74 kept under /opt).
- Verification: pre-flight against the 22 installed gnomes apps: 0 new problems; both KDE plugins resolve fully from
  the candidate runtime (no host Qt). Install pending (owner, Claude Desktop closed; backup of the old /etc files).
- To commit (owner): the 6A-34 / 6A-36 hunks in `lib/gnomes_pacman.py`.

### 2026-10-12 Build 59_slacky+ (gnomes only) - 6A-34 / 6A-36 - Installed and checked on the machine
- Runtime installed by the owner (snapshot #695, backup of the old /etc files in /var/cache/slacky-update/backup/6A-36):
  0 runtime-owned /etc files left; /etc/gnutls/config and /etc/krb5.conf gone (stock Slackware behaviour).
- Restarted easyeffects maps /opt/underpants/runtime/lib/qt6/plugins/platformthemes/KDEPlasmaPlatformTheme6.so and
  .../styles/breeze6.so (before: host breeze6.so built for Qt 6.11). Colours now follow ~/.config/kdeglobals, which
  holds the owner's "Noctalia" scheme (navy BackgroundNormal 3,15,52) - a user theme choice, not a packaging issue.

### 2026-10-12 Build 59_slacky+ (not yet packaged) - 6A-6 (items 1-3) - No loose host writes from mod_gaming.sh
- Shared curated doinst tail: libsystemd.so.0 -> libelogind links as `( cd usr/lib64 ; rm -rf libsystemd.so.0 )` +
  `( cd usr/lib64 ; ln -sf ... )` inside the existing "[ ! -e ]" guard (removepkg's extract_links parses exactly that
  form; it only deletes symlinks). gamemode post-deploy `sudo ln` removed. scx post-deploy copy of org.scx.Loader.conf
  into /etc/dbus-1/system.d removed (HUP kept). Dead hyprland branch: setcap -r and steps 2/3 (sudo tee start-hyprland,
  hyprland.desktop) removed; hyprland.env generation and skel seeding left as they were.
- Verification: fake-root test (links created, idempotent, real libsystemd untouched, removepkg regex finds both links,
  no loose writes left, 6A-25 launcher intact) green and deleted.
- Existing machine state: /usr/lib64/libsystemd.so.0 becomes tracked on the next curated package rebuild; the old
  /etc/dbus-1/system.d/org.scx.Loader.conf copy stays until removed by the owner (identical duplicate, harmless).
- Not done (documented): Antigravity download without checksum (6A-6b), /usr/local/share/fonts mirror into
  /usr/share/fonts (untracked), rc.local daemon lines without uninstall cleanup, ld.so.conf.d (already blocked by the guard).
- To commit (owner): lib/mod_gaming.sh.

### 2026-10-12 Build 59_slacky+ (not yet packaged) - 6A-6b / 6A-6d - Antigravity b2sum, NVIDIA .run sha256sum
- 6A-6b (mod_gaming.sh PYBUILD_ANTIGRAVITY): b2sums_x86_64 parsed from the cloned AUR PKGBUILD; hashlib.blake2b
  (= b2sum) on the cached file (mismatch -> re-download) and after download (mismatch -> delete + RuntimeError); no hash
  -> RuntimeError, nothing installed. FACT: the AUR b2sum matches the real 2.22.0 tarball (180,243,767 bytes).
- 6A-6d (mod_nvidia.sh install_nvidia_run_driver): curl -f to `${target}.part.$$`, `.sha256sum` (fallback `.md5sum`)
  from the same directory, compare, then mv + chmod; no checksum / mismatch / failed download -> error, return 1,
  nothing run.
- Verification: stub tests (good / tampered / no hash / bad cache for Antigravity; sha256 / tampered / md5 fallback /
  no checksum / 404 for NVIDIA) green and deleted.
- Not done: DKMS web bootstrap (6A-6e, URL is 404 today), claude-desktop apt signature chain, npm integrity.
- To commit (owner): lib/mod_gaming.sh, lib/mod_nvidia.sh.

### 2026-10-12 Build 59_slacky+ (gnomes only) - 6A-35 - Download stall watchdog
- Technical: DL_STALL_WINDOW = 60 s, DL_STALL_MIN_BYTES = 32 KiB; main parallel loop uses resp.read1 (returns as soon as
  data arrives) and raises TimeoutError when a window brings too little (caught by the existing per-attempt handler ->
  next attempt / mirror); new helper copy_response_with_watchdog used by both recovery downloaders.
- Verification: local HTTP server test (10 MB fast body completes; 100 B / 0.5 s trickle abandoned in < 6 s with the
  window patched to 2 s / 4 KiB; no plain resp.read(65536) loops left) green and deleted.
- To commit (owner): the 6A-35 hunks in lib/gnomes_pacman.py.

### 2026-10-12 Build 60_slacky - 6A-6c - rc.local marker blocks with safe add/remove (curated + gnomes)
- mod_gaming.sh: slacky_rc_helpers() prints su_rc_* helpers (docs/rclocal_spec.md, vars prefixed su_) into every curated
  doinst.sh (before the shared tail) and a new install/douninst.sh. The 7 daemon blocks (28 RC_EOF heredocs) are replaced
  by one loop over SU_RC_DAEMONS: su_rc_migrate (exact old 4-line block -> marked) then su_rc_add for start/stop.
  douninst removes a daemon's blocks only when /etc/rc.d/rc.NAME no longer exists (upgrade-safe).
- gnomes_pacman.py: douninst uses GNOMES_RC_REMOVE_SH gnomes_rc_remove (both markers required, sh -n before/after, temp
  file + .slacky-bak) inside "[ ! -e /etc/rc.d/rc.SVC ]"; the unguarded "rc.SVC stop" is gone.
- Verification: fake-root test (user if/elif/else kept byte-identical, exact old lact block migrated, hand-edited ananicy
  left alone, scx added, idempotent, upgrade keeps blocks, removal drops only scx, sh -n clean, broken file unchanged,
  gnomes block removed / missing end marker refused) green and deleted.
- To commit (owner): lib/mod_gaming.sh, lib/gnomes_pacman.py, docs/rclocal_spec.md.

### 2026-10-12 Build 60_slacky - 6A-6/6b/6c/6d, 6A-35 - Installed and checked on the machine
- 60_slacky (589 entries, 0/0) installed by the owner (snapshot #698). The five inert gnomes-service blocks (ibacm, iwpmd,
  rdma-ndd, cxl-monitor, ndctl-monitor; rc scripts gone since the 6A-30 claude-desktop rebuild) were removed from
  rc.local and rc.local_shutdown with the new gnomes_rc_remove: both files pass sh -n, 0 gnomes blocks left, rc.local
  147 -> 122 lines and a diff against snapshot #698 shows only those 25 block lines removed; .slacky-bak written.

### 2026-10-12 Build 60_slacky+ (not yet packaged) - 6A-5 - No silent STRICTGPG=off in slackpkgplus.conf
- check_and_shield_mirror_freshness (common.sh) no longer runs `sudo sed -i s/^STRICTGPG=on/STRICTGPG=off/` on
  /etc/slackpkg/slackpkgplus.conf. CHECKGPG stays on in slackpkg.conf; STRICTGPG binds each repository to its own key.
  The owner's file has STRICTGPG=off (mtime 2026-10-02, INFERENCE: set by this code). Rust only reads the file.
  Remaining write to that file (CACHEUPDATE=on, mod_packages.sh:272) is interactive and consent-based.
- Verification: bash -n; grep shows no other non-interactive writes to slackpkgplus.conf.
- To commit (owner): lib/common.sh.

### 2026-10-12 Build 60_slacky+ (not yet packaged) - 6A-3 - Verified AlienBOB multilib fetch
- setup_multilib_interactive (mod_sbo.sh): https, mktemp -d, new alien_fetch_verified(): key imported into a private
  GNUPGHOME, every primary fingerprint must be in ALIEN_GPG_FPRS (F2CE1B92...A75CBDA0 = 2003 DSA key that signs
  multilib/current, FACT verified against the real CHECKSUMS.md5.asc; 2AD107EA...769EE011 = 2016 RSA key), signed
  CHECKSUMS.md5 verified, listed packages (top level + slackware64-compat32, no "..") downloaded with curl -f and md5
  checked against the signed list; upgradepkg exit code reported. Steam fallback (dead fixed 1alien URL, no signature)
  replaced by a pointer to slackpkg+.
- Verification: local signed repo test (good / unpinned key / tampered list / tampered package / path traversal) and a
  real-server test (pinned key accepted, signature valid, 281 packages selected) green and deleted.
- Note: the multilib key is DSA-1024 (2003); that is AlienBOB's choice, slackpkg+ uses the same key.
- To commit (owner): lib/mod_sbo.sh.

### 2026-10-12 Build 60_slacky+ (not yet packaged) - 6A-4 - Curated deploy removes superseded packages safely
- A curated deploy no longer removes the app (or Limine/sbctl tooling) before installing the new build. Superseded
  packages are removed after a successful install; the new underpants-<id> is left to upgradepkg (same base name,
  also when the installed one is a _gnomes build); exact base-name match (name-version-arch-build stripped) instead of
  /var/log/packages globs; official Slackware packages (untagged build) are never removed; removepkg failures are
  reported. Lutris /usr/share leftovers removed only when no package lists them. basename fork replaced by expansion.
- Files touched: lib/mod_gaming.sh (cleanup_foreign_gaming_pkgs + its call site in the curated installer).
- Verification: fake-root test (15 cases: self kept, SBo/foreign removed, gnomes brave-bin kept, official package kept,
  r-versions, deb-style chrome names, antigravity early return, removepkg failure, lutris tracked vs stray) green and
  deleted. Read-only dry run against the real package db: only cachyos-gnome-* predecessors, SBo gamemode and SBo
  steam-devices would be replaced; no Slackware package and no _gnomes app hit. ~70 ms per deploy.
- Known limits: switching hyprland-core <-> hyprland-noctalia does not remove the other underpants-hyprland-* suite
  (pre-existing gap, not changed). Note: an installed _gnomes underpants-<id> (e.g. gnomes Steam) is replaced by the
  curated build of the same name, as before; that is upgradepkg behaviour.
- To commit (owner): lib/mod_gaming.sh.

### 2026-10-12 Build 61_slacky - 6A-2 (mirror of Rust B7) - ROCm keeps Slackware's Mesa OpenCL
- purge_conflicting_mesa_opencl no longer removepkgs, deletes /etc/OpenCL/vendors/{mesa,rusticl}.icd (FACT: rusticl.icd
  is owned by Slackware mesa-26.2.4) or appends to /etc/slackpkg/blacklist; it only reports status (new strings
  ROCM_OPTION_MESA_STATUS / ROCM_MESA_HIDDEN / ROCM_MESA_NOT_HIDDEN / ROCM_MESA_NONE in en + nb, others fall back to en;
  old ROCM_PURGE_* keys left unused). rocm.sh gets the Rust B7 OCL_ICD_VENDORS per-user filter (mesa/rusticl omitted).
  install_cachyos_rocm_suite: mktemp 0700 work dir instead of /tmp/slacky-rocm-staging + /tmp/<pkg>.txz, built as the
  user, Footprint Guard (enforce), 2C owner gate, sudo only for upgradepkg with checked exit code; status view updated.
- Files touched: lib/mod_rocm.sh, locales/en.json, locales/nb.json.
- Verification: fake-download test (16 cases: sudo only once for upgradepkg, archive 0/0, rocm.sh with filter, no mesa
  files, host ICDs untouched, work dir removed on success and failure, no false success, filter hides only
  mesa/rusticl, status function mutates nothing) green and deleted. NOT verified on AMD hardware (owner has none).
- Known limits: no pre-install Btrfs snapshot gate in legacy (Rust has B8); rocm.csh has no filter (same as Rust).
- To commit (owner): lib/mod_rocm.sh, locales/en.json, locales/nb.json.

### 2026-10-12 Build 61_slacky - 6A-1 - Curated SlackBuild installer works again, sources verified
- install_curated_slackbuild: sb_script is now <name>.SlackBuild (was unset -> set -u abort, so every curated
  SlackBuild install failed); recipe copied as the user into the mktemp workspace; TMP/OUTPUT inside the workspace
  (no fixed /tmp/SBo, /tmp output or root rm of /tmp globs); .info read as shell in a subshell (multi-line DOWNLOAD,
  e.g. wine-staging); MANUAL/UNSUPPORTED/UNTESTED skipped in both arch branches; every source with an MD5SUM is
  verified (cached ~/Downloads and /tmp copies included), mismatch aborts that package; no --no-check-certificate;
  build, package presence and upgradepkg exit codes checked; callers report failed packages instead of "completed".
- Files touched: lib/mod_sbo.sh.
- Verification: fake recipe test (21 cases: multi-line URLs + md5 pairs, private out dir, md5 mismatch, tampered cached
  copy, no-md5 warning, MANUAL, build failure, missing script, upgradepkg failure, workspace cleanup) green and deleted.
  All 7 bundled recipes parse (freeoffice/grub-btrfs/snapper/winetricks have md5; wine-staging 2 URLs, no md5).
  NOT verified: a real build of any recipe.
- Known limits: unreal-engine DOWNLOAD is a web page URL (pre-existing); FreeOffice md5 not checked against the real
  135 MB file (URL answers 200), a stale md5 would now stop the install with a clear message.
- To commit (owner): lib/mod_sbo.sh.

### 2026-10-12 Build 61_slacky - 6A-1..6A-5 - Installed on the owner's machine
- slacky-update-1.0_RC2-noarch-61_slacky installed by the owner (snapshot taken first by the install script).
- Verified read-only: package registered, installed lib/mod_sbo.sh, mod_rocm.sh, mod_gaming.sh carry the 6A-1/6A-2/6A-4
  code, /usr/share/slacky-update/lib and /usr/bin/slacky-update root:root, all installed shell files pass bash -n,
  `--protect-links status` runs, /etc/OpenCL/vendors and /etc/slackpkg/blacklist unchanged.

### 2026-10-12 Build 62_slacky - 6A-8h (mirror G7-g) - Verified NVIDIA module signing, honest [2/5]
- sign_modules_for_kernel: new _armor_sign_file/_armor_signed_by_us (sign-file exit code + modinfo signer == MOK CN);
  compressed modules are verified on the recompressed temp copy before mv; any failure (sign, wrong signer, unpack,
  recompress, mv) keeps the original, records the kernel in ARMOR_SIGN_FAILED and warns on stderr (log file too).
  enforce_secure_boot_armor: pipeline prints "Signing FAILED for <kvers> (...)", bin/slacky-update shows it red;
  interactive mode log_error. Symlinks skipped; find limited to nvidia, nvidia-drm/-modeset/-uvm/-peermem.
- Findings (FACT, read-only): the 20 kernel/drivers/video/nvidia*.ko.zst are symlinks to extramodules/; zstd refuses
  symlinks, so the old skip check failed for each link every run and the repair path (~4000 unzstd attempts per link)
  failed silently. My first reading ("signature outside the zstd stream") was wrong and is corrected here. In-tree
  nvidia-wmi-ec-backlight carries "Tux MOK" (re-signed by the old glob; kernel build key elsewhere). Running nvidia,
  nvidia_drm, nvidia_modeset, nvidia_uvm show taint OE (E = kernel did not verify the signature; sig_enforce=N).
  /etc/dkms/framework.conf.d/mok.conf names sign_tool=/etc/mok/viking-sign-module, which does not exist.
- Files touched: lib/mod_armor.sh, bin/slacky-update, slackbuild/slacky-update.SlackBuild (BUILD 62).
- Verification: fake module tree test (21 cases: zst/xz/gz/.ko success, sign-file failure, wrong signer, corrupt zst,
  originals byte-identical on failure, no depmod on failure, red pipeline text, symlink kept, in-tree module untouched,
  no false alarm on second run) green and deleted. Dry run against the real tree: 50 modules SKIP, 0 would change.
- Open: why the kernel does not accept the MOK signature (key trust: dmesg / .platform keyring, needs sudo read-only).
- To commit (owner): lib/mod_armor.sh, bin/slacky-update, slackbuild/slacky-update.SlackBuild.

### 2026-10-12 Build 62_slacky - 6A-8h - Installed; MOK key trust finding
- Owner installed 62_slacky (snapshot #702). Installed mod_armor.sh / bin/slacky-update carry 6A-8h, bash -n clean.
- Read-only key check (sudo, owner ran): .machine keyring empty, "Tux MOK" not loaded, dmesg "nvidia: module
  verification failed: signature and/or required key missing - tainting kernel". MOK keys reach the kernel only via
  shim's MokListRT; this machine boots Limine signed with sbctl db keys (no shim), and UEFI db (.platform) keys are not
  trusted for modules. So MOK module signing protects nothing here; modules load because MODULE_SIG_FORCE is unset.
  Recorded as proposal 6A-37 (honest status / shim / leave). Nothing changed on the system.

### 2026-10-12 Build 63_slacky (not yet built) - 6A-37 - Honest MOK module signing text
- Owner decision 2026-10-12: Secure Boot is for painless dual boot (kernel-level anti-cheat), not maximum security; no
  extra criteria beyond MOK/sbctl, module signatures are not required. [2/5] texts: "Signed NVIDIA modules for <k> with
  your MOK (optional, not needed to boot)", "NVIDIA modules already signed with your MOK (optional, ...)", failure
  "Could not sign NVIDIA modules for <k> (optional, ...)" in yellow (was red "Signing FAILED ... will not load");
  per-module warnings and interactive message reworded the same way; bin default status "Skipped".
- Files touched: lib/mod_armor.sh, bin/slacky-update.
- Verification: stub test (5 cases: three pipeline texts, interactive warn, yellow colour) green and deleted.

### 2026-10-12 Build 63_slacky (not yet built) - 6A-6e - DKMS from official Slackware packages
- ensure_dkms_installed_interactive: SBo 15.0 tarball (404 today, fixed /tmp/slacky-dkms-build, no -f, no checksum,
  sudo bash SlackBuild, ls -t /tmp/dkms-*) replaced by run_slackpkg update + install dkms (FACT: dkms-3.4.4 is in
  slackware64/d of -current, GPG-verified by slackpkg); success only when dkms exists, else hint + return 1.
  build_nvidia_modules tip now says "slackpkg install dkms". FACT: the function has no caller today (left in place).
- Files touched: lib/mod_nvidia.sh.
- Verification: stub test (6 cases: slackpkg calls, success only with dkms, failure rc 1 + hint, no false success,
  decline runs nothing) green and deleted.

### 2026-10-12 Build 63_slacky (not yet built) - 6A-38 - Current Fedora shim/GRUB, pinned, new layout
- fetch_official_signed_shim_interactive: shim-x64 15.8-3 -> 16.1-7 (F45 stable 2026-03-31, SBAT shim,4) and
  grub2-efi-x64 2.12-9.fc41 -> 2.12-81.fc45 (F45 stable 2026-10-05, SBAT grub,5); RPM SHA256 pinned (taken from one
  https download from kojipkgs, owner-approved); FACT: shimx64.efi carries two Authenticode signatures, Microsoft
  Corporation UEFI CA 2011 and Microsoft UEFI CA 2023, verifies OK against the bundled 2011 cert (expires 2026-06-27);
  grubx64.efi signed by Fedora CA 20250530 and Fedora CA 20200709; mmx64.efi by Fedora kernel-signer.
  FACT: new RPMs place files under usr/lib/efi/<pkg>/<ver>/EFI/fedora (old code looked for boot/efi/EFI/fedora and
  would have deployed nothing while printing success); files now located with find, all three required, mktemp
  staging, success only after deploy. Existing ESP installs: early return unchanged (not upgraded).
- Files touched: lib/mod_armor.sh.
- Verification: test with the real RPMs as fixtures (12 cases: deploy of the exact 16.1-7 / 2.12-81 binaries, real
  sbverify against the 2011 cert, tampered RPM rejected with nothing deployed, download failure fallback, staging
  cleanup, early return) green and deleted; downloads deleted. NOT verified: a real shim boot.
- Follow-ups: upgrade path for existing shim installs (boot-chain change, owner decision); after June 2026 the bundled
  2011 cert is expired as a CA but sbverify still validates the chain; consider bundling UEFI CA 2023 too; SpiderSense:
  watch SbatLevel vs installed shim/GRUB.

### 2026-10-12 Build 63_slacky - 6A-39 / 6A-40 / 6A-41 / 6A-50 / 6A-51 - LTS security fixes
- 6A-39 (S1 BLOCKER, verified on the machine): source assets/udev, assets/profile.d (0777) -> installed udev dirs
  drwxrwxrwx; mod_tweaks.sh:328 copies *.rules from there as root. SlackBuild: `find PKG_DIR ! -type l -perm /022
  -exec chmod go-w`, mode gate after the owner gate (refuses g/o-writable non-symlink entries), doinst repairs
  usr/share/slacky-update + usr/local/lib/slacky-update on existing installs.
- 6A-40 (S2): FACT pre-existing (in HEAD): the self-update check never worked: `f"{tag}-build{a_build}"` inside a
  bash double-quoted python3 -c lost its quotes -> SyntaxError hidden by `2>/dev/null || echo UP_TO_DATE`; `os` was
  not imported. Fixed (format + import os). New flow: tag ^[0-9A-Za-z._-]+$, URL must start with
  https://github.com/TuxOfValhalla/slacky-update/releases/download/, asset name slacky-update-*-noarch-N_slacky.t?z,
  SHA256 from the GitHub API asset "digest" field (FACT: present on the live release), download as user with curl -f
  into mktemp, sha256 compare, archive listed once (pipefail-safe) for 0/0 owners + usr/bin/slacky-update, sudo only
  for upgradepkg with checked exit code; no digest -> no install + manual link. Scanner over all double-quoted
  python3 -c blocks found no other quote breakage (validated on the old common.sh).
- 6A-41 (P1): bin/gnomes installed_pkg_by_base() exact base-name lookup for -R (underpants-/cachyos-gnome-/native);
  -S predecessor purge only exact variant names with _gnomes tag, never the new base, visible + failure reported;
  bin/slacky-update gnomes fallback cachyos-gnome purge exact.
- 6A-50 (P3): bin/gnomes passes a private mktemp --output-dir to transmute and runtime install, built_txz_for()
  takes only the exact-base package from it (single-target fallback for renamed packages), dir removed unless
  --build-only; gnomes_pacman.py staging via tempfile.mkdtemp; runtime-install argument parser no longer takes the
  --output-dir value as the profile name (bug that would have hit "runtime install core").
- 6A-51 (S6): export PYTHONSAFEPATH=1 in bin/slacky-update, bin/gnomes, lib/check_backend.sh; slacky_tui.py inserts
  its own dir into sys.path (it imported slacky_update_i18n from the script dir).
- Files touched: slackbuild/slacky-update.SlackBuild (BUILD 63), lib/common.sh, bin/gnomes, bin/slacky-update,
  lib/gnomes_pacman.py, lib/check_backend.sh, lib/slacky_tui.py.
- Verification: gnomes/args/TUI test (20 cases incl. real pkg db read-only, `gnomes -R obs` never lists
  obs-3d-effect, planted json.py ignored, TUI loads i18n with PYTHONSAFEPATH) green; self-update test (21 cases with
  the real 63 package as fixture, wrong/missing digest, foreign URL, bad tag, non-package archive, upgradepkg
  failure, real GitHub API read-only: up to date, no false update) green; 63 package: 0 non-root, 0 g/o-writable
  entries, udev dirs 0755. Two of my own bugs were caught by the tests and fixed (prefix glob "obs-[0-9]*" matched
  "obs-3d-effect"; tar|grep -q SIGPIPE under pipefail rejected a valid package).

### 2026-10-13 Build 64_slacky - 6A-56 - Full update prompts and errors visible again (regression from 6A-8d)
- Owner's full update "hung" after the plan. FACT: /proc/<pid>/fd showed fd 2 -> /dev/null and the process sleeping on
  a tty read. Cause (my 6A-8d code, Build 58): `exec 9<"${SLACKY_BOOT_LOCK}" 2>/dev/null` - an exec without a command
  makes every redirection permanent, so stderr was gone for the rest of the update (read -p prompts and all stderr
  error messages invisible). Fix: `{ exec 9<"${SLACKY_BOOT_LOCK}"; } 2>/dev/null`. Only occurrence (grep over legacy,
  installed copy, cron, hook).
- The initial "Waiting for another boot update to finish" was genuine: the hourly cron (Slackware runs cron.hourly at
  xx:47) started its Limine reseal at 06:47:03, the same minute the update started. The owner aborted at the invisible
  prompt; nothing had been installed; lock released cleanly.
- Files touched: lib/common.sh, slackbuild/slacky-update.SlackBuild (BUILD 64).
- Verification: pseudo-tty test (script -qec): fixed version shows stderr + prompt and reads the answer; the installed
  63 version reproduces the bug; lock exclusive; open failure returns 1 with our message and no raw bash error.
- Findings recorded, not fixed: 6A-53 kernel-headers (arch "x86") never listed as an update in either app (install
  unaffected, slackpkg upgrade-all); 6A-54 wait message does not say it waits for the hourly boot check; 6A-55 cron
  re-enrolls BLAKE2B + re-signs the Limine EFI every hour (13:47 ... 06:47), likely because hourly snapper snapshots
  change the menu: hourly EFI write window; Rust G5-14 goverlay counted twice (curated + gnomes) in the Rust status.

### 2026-10-13 Build 65_slacky - 6A-59 - Curated packages are never managed or overwritten by gnomes
- FACT (owner's full update on 64): curated underpants-goverlay-1.9.3_slacky (41 MB installed) was replaced by
  underpants-goverlay-1.9.4_1.1_gnomes (416 MB). Cause: list_installed_gnomes_packages() took every
  underpants-*/cachyos-gnome-* package regardless of build tag (60 packages instead of the 25 _gnomes ones), and
  check_curated_collision() skipped all underpants-*/cachyos-gnome-* names, so curated packages were never seen as curated.
- Fix: only _gnomes packages are gnomes-managed (list-updates, gnomes -Syu, gnomes -Q, cache clean);
  check_curated_collision() reports underpants-/cachyos-gnome- packages without the _gnomes tag as curated (explicit
  gnomes -S of a curated app now prompts, refuses when not interactive); list_updates() reports the package it actually
  looked up and never falls back to a canonical name that a curated package owns (installed brave-bin would have been
  updated as "brave" = underpants-brave, the curated Brave). Rust currently calls the legacy gnomes tools (D-series),
  so this also protects the Rust app.
- Files touched: lib/gnomes_pacman.py, slackbuild/slacky-update.SlackBuild (BUILD 65).
- Verification: test against the real package database (22 cases: only _gnomes listed, 9 curated packages incl. limine
  tools/sbctl/steam/hyprland not managed, gnomes apps still managed, collision detection for curated/gnomes/native,
  list_updates offers no curated package and reports brave-bin under its own name; the installed 64 code listed 60)
  green and deleted.
- Follow-up for the owner: GOverlay is still the gnomes build (works); `sudo slacky-update --gaming-deploy goverlay`
  restores the curated one (frees about 375 MB).

### 2026-10-13 Build 66_slacky - SpiderSense phase 1 lifeline (6A-42, 6A-43, 6A-44, 6A-47, 6A-60, 6A-61)
- Snapshot lifeline (spec 4.4): create_pre_update_snapshot / create_post_update_snapshot in common.sh; snapper
  --type pre/post pair, cleanup algorithm "number", userdata slacky-update=pre/post; taken after consent, before the first
  change; failure (rc 1) holds the CachyOS kernel and NVIDIA suites (ss_hold_boot), base proceeds, one plain sentence;
  non-Btrfs (rc 2) silent. The code never deletes snapshots: the count is bounded by snapper's own NUMBER_LIMIT
  (owner's config: 6), not by custom deletion (deviation from "2 pairs, 48 h" to confirm with the owner).
- 6A-47 run lock: acquire_run_lock / slacky_update_is_running (flock on root-owned /run/lock/slacky-update.lock, released
  on exit); used by the full update, begin_atomic_transaction, check_backend.sh, the kernel hook and the cron job; the
  /tmp/slacky-update-running.lock file is no longer created or honoured.
- 6A-43 cron: repair block first (marker -> run lock free -> boot lock -> `slacky-update --sync-boot`, NON_INTERACTIVE),
  independent of ENABLE_AUTO_SNAPPER_SYNC.
- 6A-42 initramfs: install_initramfs_image() (size check, Limine: boot lock + reseal marker first, cp to <out>.new, sync,
  rename); dracut builds into a root mktemp -d dir (was /tmp/dracut-<kver>-$$.img). [3/5] shows failures in red; only
  the pipeline gets a non-zero result, the ~20 other callers keep 0 so they still reach the Limine reseal under set -e.
- 6A-44 honest status: [1/5] real result of ensure_cachyos_nvidia_duties/build_nvidia_modules (no hard-coded 615.71.09),
  build_nvidia_modules returns 1 when no nvidia.ko exists after dkms; [4/5] sign_kernel_binaries_sbctl verifies each
  kernel with sbverify against the sbctl db cert and returns 1 on failure; skipped when sbctl keys are not configured.
- Failed [5/5]: SLACKY_BOOT_CHAIN_FAILED -> no restart offer, "do not restart yet", exit 30.
- Consent: check_backend.sh no longer starts a background `flatpak install` of the NVIDIA GL runtime (the full update's
  Flatpak step already handles the mismatch).
- 6A-61: get_kernel_driver_snapshot ignores kernel-headers/kernel-source (FACT: kernel-headers 7.2.9 -> 7.2.10 had
  triggered the boot matrix and the forced restart advice on 2026-10-13). 6A-60: cache prompt substitutes {0} in bash.
- Files touched: bin/slacky-update, lib/common.sh, lib/mod_kernel.sh, lib/mod_nvidia.sh, lib/mod_limine.sh,
  lib/check_backend.sh, cron/slacky-snapper-limine-sync, assets/hooks/slacky-limine-hook, SlackBuild (BUILD 66).
- Verification: fake-root suite (19 cases: run lock exclusive + released on exit + seen by watchers; cron repair with
  opt-in off, deferred while an update runs, nothing without marker; initramfs tiny/good/copy-failure with lock and
  marker order; snapshot pre/post pairing, failure, non-Btrfs, never deletes; exit 30; kernel-headers exclusion;
  {0} substitution) green and deleted. NOT verified on the machine yet: a real full update with snapshot and a real
  cron repair.

### 2026-10-13 Build 67_slacky - pacman master plan P2/L1 (early) - glibc/libstdc++/libgcc headroom hold
- FACT (study 5): max needed GLIBC_2.44 and GLIBCXX_3.4.36 = host (zero headroom). New TransmutationFactory
  host_symbol_max() (glibc via confstr, GLIBCXX/CXXABI from libstdc++.so.6, GCC from libgcc_s.so.1 via readelf -V) and
  check_symbol_headroom() (64-bit ELF only, readelf -V -W in chunks of 200, "Version needs" entries only); called after
  patch_elf_rpaths in transmute (app) and the runtime build; any need above the host = build stops before packaging,
  staging removed, installed version stays, one plain sentence (HOLD semantics of the master plan).
- Files touched: lib/gnomes_pacman.py, SlackBuild (BUILD 67).
- Verification: real host detected (GLIBC 2.44, GLIBCXX 3.4.36, CXXABI 1.3.17, GCC 14.0.0); 0 false alarms over all 23
  installed gnomes apps (1.6 s) and the runtime (6.7 s); simulated older host flags vlc (GLIBC_2.43) and prints the
  message; test deleted.
- Addition (same build, not installed yet): held list. A held package is recorded in held.json (root cache when root,
  else ~/.cache/slacky-update/gnomes) with version, needed symbol, host stamp and time; list_updates() skips that version
  while the host stamp is unchanged (no repeated download/build), offers it again when the upstream version or the host
  libraries change; `gnomes_pacman.py held [--json]` lists what is waiting. Test (6 cases, temp HOME) green and deleted.

### 2026-10-13 Build 68_slacky - 6A-57, 6A-64 (WP-12a), 6A-74 - Hyprland env in user space, log ownership, goverlay recipe
- 6A-64 (owner decision: hyprland.env in user space, never overwritten by the system): configurator no longer writes
  /etc/hypr/hyprland.env (was `sudo tee` on every deploy, mod_gaming.sh:7076); new write_user_hypr_env_block() writes the
  generated lines between "# >>> slacky-update: hardware environment ... >>>" / "# <<< ... <<<" in the user's
  ~/.config/hypr/hyprland.env, as the user (sudo -u when root), keeps every line outside the block (also text glued to
  the end marker); start-hyprland-session template sources /etc/hypr/hyprland.env first and the user file last. The
  owner's /etc file (AQ_DRM_DEVICES, GBM_BACKEND) is left untouched. Hardware detection itself is redesigned by the
  running Hyprland study (SpiderSense hardware profile).
- 6A-57: init_storage's root branch touched/chowned the LOG_FILE variable, which after an earlier call pointed at
  ~/.cache/slacky-update/slacky-update.log -> root-owned file in the home dir (FACT: created 06:57 when sudo was cached).
  Root branch now only touches /var/log/slacky-update.log; the user branch removes a user-cache log that is a symlink or
  not owned by the user; all log writes are brace-grouped so an unwritable log is silent.
- 6A-74: curated goverlay recipe ran mkdir usr/lib64/goverlay before moving the ELF file of that name (goverlay 1.9.4
  ships the program as usr/lib/goverlay) -> "File exists", deploy stopped (owner's run 2026-10-13). ELF moved aside first.
- WP-0 repair run by the owner (snapshot #732): stale cachyos-gnome-mangohud removed, gamescope rebuilt through the guard
  (72 Slackware files dropped), 4 duplicate gnomes apps + brave-bin removed, encodings/luajit/luajit-lgi/xorg-server-
  xwayland/ddcutil reinstalled from Slackware; line-based re-check: 0 gnomes packages share Slackware files (the two
  "STILL SHARED" lines of the script were a whitespace-splitting false positive in my check).
- Files touched: lib/mod_gaming.sh, lib/common.sh, SlackBuild (BUILD 68).
- Verification: env block (3 runs, user lines before/after/glued kept, no duplicate block, user-owned, launcher order),
  goverlay recipe for 3 layouts, silent unwritable log, log repair (symlink to existing/dangling target removed, own log
  kept) - all green, tests deleted.

### 2026-10-13 Build 69_slacky - 6A-75, 6A-76, 6A-78, 6A-79, 6A-80 - Hyprland setup follows the hardware (owner decisions 1-5 + cursor rule)
- New Hyprland setups no longer force a software cursor (only NVIDIA older than Turing, device id < 0x1e00, or an NVIDIA card
  whose id cannot be read); no GLX vendor variable on single NVIDIA when glxinfo under Xwayland proves it is not needed
  (kept when the check cannot run); multi-GPU: PCI slots in the user env block (SLACKY_DRM_ORDER), resolved to AQ_DRM_DEVICES by
  start-hyprland-session at login, missing GPUs skipped, a user-set AQ_DRM_DEVICES wins, single GPU gets nothing; hypridle seed
  locks after 10 min and before sleep (only when hyprlock + hyprlock.conf exist; upstream hyprlock.conf copied if missing);
  hdr.lua.suggestions generated from EDID (connected PQ monitors, name + VRR range, no serials, never loaded).
- probe_gpu_hardware sysfs fallback counts display-class PCI devices only (was: any Intel/AMD device).
- Files touched: lib/mod_gaming.sh (hypr_gpu_facts, hypr_glx_vendor_var_needed, write_hypr_hdr_suggestions, configurator,
  launcher), lib/common.sh, SlackBuild (BUILD 69).
- Machine (owner's): user files changed with .bak-20261013 copies (env.lua GLX line commented, hypridle.conf lock added,
  hyprlock.conf from upstream, hdr.lua.suggestions). install69.sh: snapshot, upgradepkg, removes unowned
  /etc/profile.d/vaapi.sh/.csh, comments AQ_DRM_DEVICES/__GLX_VENDOR_LIBRARY_NAME/GBM_BACKEND in /etc/hypr/hyprland.env
  (backups in /root/slacky-backup-20261013-hypr).
- Verification: 12 fake-sysfs GPU layouts (single new/old NVIDIA, 1660 boundary, Volta, unknown id, hybrid laptop with and
  without dGPU output, desktop iGPU on, two GPUs, compute accelerator, two NVIDIA), launcher snippet (sh/dash/posix,
  missing slot, user override), live GLX check on this machine (NVIDIA with and without the variable, also env -i), EDID
  on the real monitors + non-HDR + garbage, whole configurator in a fake home (real, no display, old NVIDIA, hybrid,
  hyprlock missing, existing files kept). All green, tests deleted. NOT verified: real multi-GPU/hybrid hardware,
  hyprlock unlock (owner to test by hand), HDR keys on the owner's monitors.
- Follow-ups (not done): hybrid branch still exports global GLX/NVD (Opus/Sonnet: never global on hybrid; needs owner
  decision + slacky-prime-run); nvidia-vaapi.sh in cachyos-nvidia-utils (lspci per shell, misses 0302, csh differs,
  MOZ_DISABLE_RDD_SANDBOX=1 global); suite launcher reaches the machine only with the next hyprland suite deploy.

### 2026-10-13 Build 69_slacky - WP-1, 6A-71, 6A-52 (D15) - install-time host-path guard both ways
- gnomes refuses to install a package whose host paths (files, symlinks, doinst symlinks, .new twins; outside
  opt/underpants and install/) belong to any other package; the same-name `_gnomes` predecessor is allowed; a same-name
  non-gnomes (curated) package is never replaced (curated wins). Curated installs refuse paths owned by a `_gnomes`
  package with another name. usr/share/licenses/ is shareable (found on the real db: 7 apps share bundled licence texts).
  Unowned Vulkan implicit layer = note only (D15). Exit 3, one sentence per owner with the fix; fail closed on a missing
  pkgdb or broken archive.
- 6A-71: --build-only never installs; the curated fallback asks on a tty, never runs sudo silently.
- 6A-52: secure_cache_modes on every engine start (dirs 0700 user / 0755 system, files in db/ and pkg/ lose go-w, own
  files only, chmod only, symlinks not followed).
- Files touched: lib/gnomes_pacman.py (footprint_pkg_base, host_path_owners, archive_host_paths, verify_host_paths,
  CLI footprint-guard --verify-host-paths, secure_cache_modes), bin/gnomes, lib/mod_gaming.sh.
- Verification: 19 fixture cases (Slackware/curated/gnomes owners, predecessor, same-name curated, Vulkan layer, .new both
  ways, doinst symlinks both ways, symlink entry, opt/underpants, curated mode 4 cases, fail-closed x3); real pkgdb: all 64
  installed own packages rebuilt from their file lists -> 0 false refusals, true positives (Xwayland, hyprpicker) refused;
  0.22 s per check incl. Python start (plan target <= 0.3 s; owner index cache not needed); 6A-52 modes; 6A-71 with
  stubbed sudo (build-only, no tty, tty+no, tty build-only): no sudo. Tests deleted.
- Not done: owner-map cache (not needed at 0.22 s); locale strings for the Python messages (gnomes has no i18n layer yet);
  Rust footprint mirror (B11, Rust phase).

### 2026-10-13 Build 70_slacky - 6A-65, 6A-66 (WP-12a) - hyprmod source lock, Hyprland suite clean-up
- 6A-65: HYPRMOD_LOCK in the build recipe: GitHub tag v0.4.0 tarball (sha256 fd3672..., identical to the AUR PKGBUILD) +
  hyprland-config 0.9.17 / monitors 0.9.0 / schema 0.7.1 / socket 0.12.2 / state 0.4.7 as PyPI wheels with sha256 (same
  versions as installed). Streamed sha256, mismatch = exit 1, nothing staged, function returns 1. tarfile filter='data'.
  Both version checks (fast scan + resolver) report the lock, no AUR RPC for hyprmod. FACT: the installed "0.4.0" was
  built from main (needs hyprland-config>=0.9.17, tag needs >=0.9.10); upstream v0.5.0 exists (2026-10-07). Owner's
  install is not downgraded automatically (same version label).
- 6A-66: suite staging drops hyprland-uwsm.desktop unless uwsm exists, usr/lib64/cmake + pkgconfig + share/pkgconfig
  (no headers ship), hyprwire-scanner, sdbus-c++-xml2cpp, md2html(+man), modules-load.d (not read on Slackware), empty
  dirs. Generic: D-Bus .service Exec=/usr/lib/X rewritten to /usr/lib64/X only when X is in lib64 and not lib (FACT on the
  machine: portal and hyprpolkitagent activation files pointed at missing /usr/lib paths). Seed autostart: no portal exec
  (D-Bus activation), pipewire/pipewire-pulse/wireplumber guarded with pgrep -u uid -x.
- Files touched: lib/mod_gaming.sh, SlackBuild (BUILD 70).
- Verification: hyprmod lock: real build in a temp root with network (6 dist-infos identical to the installed set,
  desktop/metainfo/launcher present), tampered wheel and tampered source refused with nothing staged, no main-branch URL, no
  AUR RPC. 6A-66: fake staging from the real suite file list (uwsm, dev files, tools, modules-load, udev dir gone; 10 key
  binaries and 66 libs kept; both D-Bus files fixed; real /usr/lib and non-lib Exec untouched); seed autostart parses
  with luac5.5 and the pgrep guard works both ways. Tests deleted.
- Not done: hyprlock linking libjpeg.so.8 and .62 (needs a look); owner machine keeps the broken D-Bus files until the
  next suite deploy (portal and polkit agent are started by his autostart.lua, so nothing is broken today).
- New finding 6A-83: /etc/modules-load.d is not read on Slackware (no reader in /etc/rc.d); curated zenpower and
  v4l2loopback write their autoload there, so those modules would not load at boot.

### 2026-10-13 Build 71_slacky - WP-2 (D14), 6A-83 - snapshot rollback, build dirs on disk, space check, module loading
- WP-2 (owner decision 2026-10-13: rollback from snapshots, no second package copy; ~11.8 GB saved per copy on his
  machine): gnomes --rollback <app> [--yes]: plan = newest snapper snapshot holding another version of the same app
  (same kind: _gnomes vs curated; follows cachyos-gnome-X -> underpants-X renames); boot chain refused (limine, sbctl,
  snapper, kernel*, nvidia*, linux-cachyos*, dkms, grub, shim); snapshot of the current state first (fail closed);
  rebuild = snapshot FILE LIST (minus install/ and var/lib/pkgtools/) + snapshot doinst/douninst + slack-desc, tar
  --owner=0, xz -T0 -1, refused when any listed file is missing in the snapshot (/boot never is, so kernels fail
  naturally); verify-archive + verify-host-paths; upgradepkg --reinstall old%new; hold file
  /var/cache/slacky-update/gnomes/rollback-holds.json makes gnomes list_updates and the curated fast scan skip the
  version rolled back from (a newer one is offered).
- D14: transmute/runtime staging and bin/gnomes output dirs moved from /tmp (16 GB tmpfs) to the user cache (or
  /var/cache/... as root), 0700; -Sc removes build dirs older than 6 h. Space precheck before download: build fs >=
  2.2 x ISIZE, /opt >= 1.1 x ISIZE, else one sentence and nothing changed.
- 6A-83: SU_RC_MODULES (zenpower, v4l2loopback, i2c-dev for ddcui) -> marked block per module in
  /etc/rc.d/rc.modules.local via the 6A-6c helpers (syntax-checked, .slacky-bak); skipped when the module is already
  loaded there by the sysadmin (comments ignored, exact name); file created 0755 if missing; warning when not
  executable (mode left alone); douninst removes the block only when the package is gone. modules-load.d writes removed.
- Files touched: lib/gnomes_pacman.py, bin/gnomes, lib/mod_gaming.sh, SlackBuild (BUILD 71).
- Verification: rollback engine 19 cases in fake snapshots (choice, info, build, root:root, scripts, content, modes,
  installpkg ROOT= accepts it with identical FILE LIST and content, missing file, Slackware package, not installed, no
  snapshots, kind + rename, boot chain, holds); real snapshots read-only (goverlay plan 1.9.4 -> 1.9.3 from #721, Limine
  refused); end-to-end gnomes --rollback goverlay --yes with stubbed sudo/snapper/upgradepkg on a copy (real build from
  snapshot #721, both guards pass, upgradepkg old%new called, work dir removed). Space precheck/build dir 6 cases.
  6A-83 15 cases in a fake /etc. All tests deleted.
- Not done: no repack-on-update store (replaced by the snapshot decision); machines without snapper get no rollback yet
  (decision said: 1 stored package with a size cap there; follow-up); Rust scanner must honour rollback-holds.json.

### 2026-10-13 Build 72_slacky - WP-3 (D1, D14), WP-7 (D9, log-only) - runtime contract, trust module, vercmp
- WP-3: RUNTIME_HOST_ONLY (mesa, libglvnd, libdrm, llvm-libs, vulkan-icd-loader, libva, libvdpau, spirv-tools, glslang,
  shaderc, ocl-icd, alsa-lib, libpulse, pipewire, libpipewire, jack2, pipewire-jack, p11-kit, gnutls, ca-certificates-*)
  resolved as host in every mode; profiles media/graphics/all without libva/libvdpau/pipewire/alsa-lib/vulkan-icd-loader;
  file guard (globs + dirs) after merge; host-fit check (every host-only NEEDED soname 64-bit in ld.so.cache with every
  symbol version, else HOLD); RUNPATH without /opt/underpants/common (never existed) and 32-bit /usr/lib/{pulseaudio,
  pipewire-0.3}; manifest .gnomes/manifest.json schema 1; runtime version 1.1.
- WP-7: lib/gnomes_trust.py by an Opus subagent (reviewed): pacman vercmp port (92/92 upstream vectors), gpgv verify of
  %PGPSIG%/.sig with pinned anchors (Arch 5 masters, CachyOS 882DCFE4...8DB35A47, Chaotic EF925EA6...87B78AEB; verified
  2026-10-13 against project pages + keyring packages), keyring bootstrap/refresh (3-of-5 master certification for Arch,
  atomic current/previous symlink under /opt/underpants/keys/<family>/), monotonic DB BUILDDATE rule. Wired: loaded by
  explicit path (PYTHONSAFEPATH); is_newer_version uses vercmp (fallback old code); trust_gate after every
  download_packages_parallel (log: trust-log.jsonl, enforce: hold); sync checks DB monotonic; extraction without shell,
  both pipe ends checked, failure = one sentence + no build; merge collision report. SlackBuild ships gnomes_trust.py.
- Files touched: lib/gnomes_pacman.py, lib/gnomes_trust.py (new), slackbuild/slacky-update.SlackBuild (BUILD 72, file list).
- Verification: WP-3 units 12/12 (host-fit with real gcc-built ELFs incl. a stub needing ALSA_9.9 and a missing
  libgnutls.so.99, guard, profiles, resolver fixture). Real runtime-all 1.1 built as user (518 packages, 892 MB vs 969 MB
  for 1.0, 76 s), mounted over /opt/underpants/runtime with bwrap: V3 ld.so --list on 1,419 app ELFs + 4,158 runtime ELFs:
  0 not found (same as today) and 0 graphics/sound/TLS libs taken from the runtime (today: vlc 56, easyeffects 59,
  audacity 40, filezilla 8, gamescope 6, lutris 3); VA-API device init with the runtime ffmpeg on NVIDIA (encode not
  offered by nvidia-vaapi-driver, expected), ALSA playback via host libasound rc 0, filezilla takes host gnutls/p11-kit;
  L3: host GPU/TLS libs pull only libX11/libXext/expat/gmp from the runtime, all the same version as Slackware (nettle 4.0
  vs 3.10 differ by soname); V4 --version identical old vs new for vlc, filezilla, flameshot, gamescope, satty, lutris,
  easyeffects. WP-7: selftest 92/92 + 21/21; integration 22 cases; real list-updates; real wlr-randr build (trust log
  shows the pinned CachyOS key, keyring not installed yet); runtime rebuilt with all checks: identical file list, 0 merge
  clashes, 519 packages logged. Package: 0 non-root, 0 g/o-writable, gnomes_trust.py loads from the package path.
- Not done: keyring bootstrap (owner-run, root), .sig download for Chaotic (its DB has no %PGPSIG%), enforce switch,
  locale keys for the trust messages, .MTREE verify, stored exact Arch version per app (desanitize is a heuristic),
  host_package names in the manifest for glslang/shaderc/vulkan/libpulse (Slackware names differ). Runtime 1.1 install is
  owner-run (install_runtime11.sh, sha256-pinned to the tested package).

### 2026-10-13 (no build) - WP-3 verified on the machine, WP-7 keyring bootstrap prepared
- Runtime 1.1 installed by the owner. Post-install (FACT): pkg underpants-runtime-all-1.1, manifest 518 packages, 0
  graphics/audio/TLS copies, all root-owned, nothing world-writable; V3 on the real tree for 12 apps (incl. inkscape,
  claude-desktop, discord, btop) + 4,157 runtime ELFs: 0 not found, 0 host-only libs from the runtime; VA-API init via
  host libva, ALSA rc 0, 6 apps launch clean. Test harness deleted.
- WP-7: keyring packages downloaded twice (subagent + Claude, identical sha256); dry bootstrap as user: Arch 84 accepted
  / 38 revoked, CachyOS 1, Chaotic 1 (3 revoked); census of the 523 cached real packages (matched by sha256): 523 good;
  a real package with one flipped byte -> bad. Owner decision: Chaotic TNE key not trusted. bootstrap_keyrings.sh
  (sha256-pinned inputs, snapshot, fails closed per keyring, root:root, world-readable) is owner-run. Still log-only.
- Note: CachyOS ships identical file names in several CPU-tier repos with different builds; any check must pair a file
  with its DB entry by sha256 or by the entry it was downloaded for (the engine does the latter).

### 2026-10-13 Build 73_slacky - WP-7 - Chaotic .sig, TNE via the pinned chain (owner decision), localized messages
- trust_gate (now an instance method) downloads and caches <pkg>.sig when the DB has no %PGPSIG% (Chaotic), https
  only; -Sc removes orphan .sig. GNOMES_TRUST_* keys in locales/en.json + nb.json, read through slacky_update_i18n by
  path (English fallback).
- Owner decision 2026-10-13: Chaotic keys listed in chaotic-trusted (TNE 67BF8CA6...37365605, which signs today's
  Chaotic packages, FACT) are accepted when the keyring package is signed by the pinned Pedro anchor; the anchor
  requirement holds on bootstrap AND every refresh, revoked keys (list or in-keyring) never accepted; meta.json lists them.
- Fix (subagent code): two keyring refreshes in the same second clashed on gen.<stamp> (Directory not empty); now -N.
- Files touched: lib/gnomes_pacman.py, lib/gnomes_trust.py, locales/en.json, locales/nb.json, SlackBuild (BUILD 73).
- Verification: real Chaotic mirror: 4 packages + .sig good via TNE against a dry keyring (Pedro-signed keyring, TNE
  vouched), flipped byte bad; installed keyrings: Arch/CachyOS good in enforce mode. Fixtures (throwaway ed25519 keys):
  anchor-signed + vouched accepted, unlisted key out, refresh signed by the vouched key refused and nothing changed,
  bootstrap signed by the vouched key refused, vouched key on the revoked list out, revoked anchor refused (7/7);
  triple refresh in one second ok; selftest 92/92 + 21/21; nb/en messages render.

### 2026-10-13 Build 74_slacky - 6A-45, 6A-46, 6A-48, 6A-49, 6A-84, 6A-85, 6A-87 - LTS safety fixes
- 6A-46: purge_old_slackware_kernels prunes only pkgdb-known stock kernels (kernel-generic/huge/modules/source), grouped by
  version (generic-X, huge-X, X = one kernel), keeps running + newest 1 (2 when running stock), removes via removepkg +
  versioned /boot files; unmanaged kernels (self-built, leftovers like /lib/modules/6.18.52 here) never touched.
- 6A-45: ESP candidates only unmounted vfat or empty (no fs); provision refuses any partition with a signature
  (blkid + blkid -p); ERASE needed to format; verify_boot_copy (cmp/diff -r) before fstab edits in both scenarios;
  EOF/empty answer = no.
- 6A-48: write_status_safely: system cache atomic 0644 (was 0666), user cache written by a forked child after
  setgroups/setgid/setuid to that user; gaming fast-results reader skips symlinked/foreign-owned status files and the
  batch deploy accepts only catalog ids.
- 6A-84 (found by Opus C, verified): compat32 glibc from /var/cache/packages (world-writable, FACT) installed as root
  without signature -> now copied into a root mktemp dir, gpg --verify with root's keyring (slackpkg's), else not installed.
- 6A-85 (found by Opus B, verified: /.PKGINFO /.BUILDINFO /.MTREE in / since 2026-10-08): 8 raw tar -C / extractions
  exclude Arch metadata. Registering these files with pkgtools is part of the SpiderSense plan.
- 6A-87 (found while fixing 6A-84): fastest-mirror update wrote /tmp/mirrors.tmp (fixed path) then sudo mv into
  /etc/slackpkg/mirrors -> private mktemp + URL regex + install -m 0644 -o root.
- 6A-49: sbotools bootstrap: mktemp work dir, private OUTPUT, https + MD5SUM from .info must match, source saved under
  its real name (was always sbotools-3.6.tar.gz while .info now says 4.4.2).
- Machine (owner-run fix_perms.sh): /var/cache/packages root:root, no group/other write; /var/log/slacky-update root
  0755 (reserved for the flight recorder), stale tux status.json moved; /.PKGINFO etc. moved to /root backup.
- Files touched: lib/mod_clean.sh, lib/mod_limine.sh, lib/common.sh, lib/check_backend.sh, lib/mod_gaming.sh,
  lib/mod_packages.sh, lib/mod_kernel.sh, lib/mod_nvidia.sh, lib/mod_sbo.sh, SlackBuild (BUILD 74).
- Verification: 6A-46 8 cases (fake pkgdb, stubbed sudo); 6A-45 9 cases (fake lsblk of a 6-OS disk, stubbed blkid/mkfs,
  real cmp/diff); 6A-48 6 writer cases + symlinked reader + catalog check; 6A-84 good/bad signature with stubs; 6A-85
  exclusion checked on a real zstd tar; 6A-87 URL regex 4 cases; 6A-49 real .info + tarball md5 match. Tests deleted.
- Not done / Rust: Rust multilib.rs has the same compat32 and /tmp/slacky-multilib.conf issues (Opus C) -> carry-over.

### 2026-10-13 Build 75_slacky - SS-1..SS-4 (6A-88..6A-106) / 6A-53, 55, 81, 82, 96, 117, 118, 119 - SpiderSense LTS core
- SS-1 (guardian basics): when /boot is not mounted read-write as fstab says (`ss_boot_ready`), kernel and driver
  suites and the boot chain wait (reseal marker set, one plain warning) and everything else updates; the Slackware base
  also waits if a stock kernel-generic/kernel-huge would change (it writes to /boot; found while merging). A closed terminal no longer
  kills a running update: `begin_atomic_transaction` ignores HUP and `run_slackpkg` runs slackpkg under `trap "" HUP`
  with a filter that keeps draining when the terminal is gone. sudo stays alive for the whole run (keepalive). A run
  journal `/var/lib/slacky-update/tx-state` (started-packages / started-boot-chain / done) lets the next run see an
  interrupted one (also duplicate pkgdb bases) and repair the boot chain. A foreign slackpkg/installpkg/upgradepkg/
  removepkg/sbopkg/sboinstall/sboupgrade blocks the run lock. Base preflight (6A-91/92, `mod_packages.sh`): the base
  waits when the mirror ChangeLog is older than the last one seen, or when / has less than 2x the unpacked size + 1 GB.
- SS-2 (48 h rule): our snapshots carry userdata `slacky=1,slacky-app=legacy,slacky-kind,slacky-tx` and no snapper
  cleanup algorithm. New `lib/spidersense_snap.py` decides which of ours are older than 47 h (pre/post pairs together,
  the oldest member decides); owner snapshots, the booted snapshot, the default subvolume and anything under a wrong
  clock are never touched. `ss_prune_our_snapshots` deletes at run start and hourly from the cron job, never while a
  reseal or rollback is pending, and marks a reseal if a deleted snapshot was in the menu.
- SS-3 (order book, Opus agent, hand-merged): dracut once per surviving kernel at the end, purge only after a verified
  seal, no `sbctl sign-all`, no in-place re-sign of a live EFI, boot lock only for the boot chain, Ctrl-C/TERM handled
  (stop before the chain, wait during it). 6A-97..6A-104 (6A-103 partial: prompts skipped during a run, not moved).
- SS-4 (one menu writer, Opus agent): the curated limine-snapper-sync gets a plugin guard and a fail-closed lock at build
  time; during a run it only leaves an order (`boot-menu-pending`, claimed as `.taken`) that the run or the hourly job
  serves. The hourly fingerprint now covers the menu inputs.
- 6A-53 (Sonnet agent): kernel-headers (arch x86) is listed as an update (`check_backend.sh`; Rust `changelog.rs` too).
- 6A-55: the default snapshot menu policy is "important"; no fill-up with timeline snapshots.
- 6A-96: snapshot menu entries list only kernels whose modules exist inside that snapshot (max 2, newest first), else
  the old entry with "(newer kernel, some drivers may be missing)".
- 6A-81: `/usr/libexec/cachyos-nvidia-vaapi-env` sets LIBVA/NVD only when NVIDIA drives the display or PRIME is asked
  for, and MOZ_DISABLE_RDD_SANDBOX only when Firefox has hardware decoding switched on. 3.4 ms per login shell.
- 6A-82: Hyprland on hybrid laptops (NVIDIA not the display GPU) gets no session-wide NVIDIA variables and a hint to use
  the new `slacky-prime-run <program>`; Intel is no longer forced to iHD (libva picks iHD/i965 itself).
- 6A-117: new `lib/spidersense_hw.py`: sysfs/procfs hardware profile (GPUs and display GPU, CPU tier/threads, RAM,
  chassis via system battery or DMI, boot fs, bootloader, UEFI/Secure Boot, snapper) in about 1.3 ms, saved at boot by
  an rc.local block and checked at run start ("SpiderSense: ..." notice on change). `slacky-update --hardware` shows it.
- 6A-118: `is_laptop_chassis`, `detect_cpu_tier`, `probe_gpu_hardware` read the profile first (old code kept as fallback).
- 6A-119: parallel dracut runs at most max(1, min(threads/4, RAM GB/2, kernels)) builds at a time (4 here, was all at
  once); a failed build is retried once alone; per-kernel time goes to the log file only.
- Files touched: bin/slacky-update, bin/slacky-prime-run (new), lib/common.sh, lib/mod_kernel.sh, lib/mod_limine.sh,
  lib/mod_nvidia.sh, lib/mod_gaming.sh, lib/mod_packages.sh, lib/mod_clean.sh, lib/check_backend.sh,
  lib/spidersense_snap.py (new), lib/spidersense_hw.py (new), cron/slacky-snapper-limine-sync,
  assets/hooks/slacky-limine-hook, slackbuild/slacky-update.SlackBuild (BUILD 75, new files, rc.local block, douninst).
- Integrated test of the merged tree (Opus agent, fake root, 11 scenarios): all PASS after three fixes made from it:
  (4g) Ctrl-C/TERM at a [Y/n] prompt was taken as "Y" -> `read_update_prompt` answers "n" once a stop is requested;
  the prune step's menu check also matches the `@snapshots/N` layout and the ESP limine.conf; doinst/douninst use
  ROOT-relative paths (etc/rc.d/rc.local), as pkgtools run them from $ROOT/. Re-tested: prompt 5 cases, rc.local
  add/keep/remove in a temp root, grep pattern 3 cases.
- Verification: unit tests per ID in fake roots with stubs (SS-3: 15 scenarios; SS-4: claim/serve/fail-closed; SS-2:
  pruner fixtures; 6A-117: 12 probe/change cases + real host; 6A-119: formula 6 cases, max concurrency 4 of 6, transient
  and permanent failure); bash -n / py_compile clean on the merged tree. Integrated test of the merged tree: see below.
  Not verified: real sudo HUP behaviour, real dracut in parallel, GRUB-only machines, hybrid laptops (no hardware).
- Known limits: SS-3 W2/W3 window stays until SS-6; 6A-103 partial; two snapshot-entry generators remain (ours and
  lss); bambu-studio wrapper still forces NVIDIA offload. Curated underpants-limine-snapper-sync (SS-4) and
  cachyos-nvidia-utils (6A-81) take effect at their next redeploy. One reseal is expected after install (fingerprint
  format changed).

### 2026-10-13 Build 76_slacky - 6A-120 (LTS B3) - Snapshot boot entries point at the real snapshot subvolume
- Booting a snapshot from the Limine menu works again on the usual snapper layout. The entries used
  `rootflags=subvol=<root subvol>/.snapshots/N/snapshot`; when /.snapshots is its own subvolume (@snapshots, as on the
  owner's machine, FACT from findmnt and the live limine.conf: entries 755-761 all said `/@/.snapshots/N`) that path is an
  empty mount point and the root mount failed. New `ss_snapshot_subvol_base` reads the path from the mount table
  (findmnt TARGET/FSROOT/SOURCE) and leaves snapshot entries out, with one warning, when the snapshot folder is on
  another filesystem than /. The old fallback `@snapshots/N` for a top-level root is gone (it was wrong for a nested
  .snapshots).
- Files touched: lib/mod_limine.sh (helper + snapshot entry block), lib/common.sh (comment), SlackBuild (BUILD 76).
- Verification: real host gives /@snapshots (and /@home for /home, nothing for vfat /boot); stubbed findmnt: own
  subvolume, nested in @, nested in top-level, /mnt/@snapshots, other filesystem, findmnt failure: 6/6. Prune menu check
  (common.sh:1298) already matches both forms. Package audit: 0 non-root, 0 group/other-writable.
- Not verified yet: a real boot from a snapshot. Open question (INFERENCE): entries pass `rw` while snapper snapshots
  are read-only; the owner's boot test decides whether a read-only boot or an overlay is needed.

### 2026-10-13 Build 77_slacky - LTS fix phase 1 (6A-121..6A-149) - review blockers B1, B2, B4-B7 and the major bundles
- Why: the LTS review (Rust repo docs/release_review/2026-10-13/L4_lts_verdict.md) found 7 blockers; B3 was Build 76.
- Run robustness (lead, 6A-145..149): a closed terminal no longer ends the run (echo/printf cannot fail it during the
  transaction); a failing suite (kernel, NVIDIA, curated, gnomes, SBo, Flatpak) only warns, stays pending and is named
  at the end instead of "completed successfully"; a kernel change in the Slackware base marks the boot repair at once;
  the repair marker is only for Limine (also when /boot is unmounted and Limine is configured); the hourly job repairs
  a cut-off run (journal not "done"), stops after 3 failed tries for 24 h; --gaming-deploy/--gaming-uninstall/--clean
  take the run lock; heal runs as root and never reports "clean" when it could not finish; one mirror writer
  (rank_mirrors.py --apply); kernels are not purged under an unmanaged Limine menu; SlackBuild: private mktemp build
  dirs, no /tmp copy or fallback, no chmod of cron/hook on upgrade, cache staged 0755; staging dir never predictable.
- Limine/ESP/Secure Boot (L-B, 6A-121..124): /boot and a separate ESP must be mounted rw before any write; ESP copies
  .new + cmp + rename with a space check; ESP orphan prune only after the verified commit; Limine counts as managed only
  on UEFI with EFI/limine/limine_x64.efi (BIOS Limine or leftover config: one notice, no exit 30); BOOTX64.EFI replaced
  only if it is Limine; sbctl files.json keeps foreign entries; ESP migration checks every step, EOF = no; the Secure
  Boot wizard stops on failure and says "enable Secure Boot" only after the seal check.
- Curated suite (L-C, 6A-125..129): a failed build never installs a stub or reports success (payload check, xz -t,
  upgradepkg rc + pkgdb), batch returns non-zero with the failed ids; theme builder syntax error fixed; uninstall by
  exact name; NVIDIA session variables only for the bound nvidia driver, radeonsi only for an AMD display, outputs win
  over boot_vga; scx_loader.toml/ananicy.conf as .new; browser flag files never overwritten; chrome-sandbox setuid kept;
  inside a full update curated builds never touch the run's INT/TERM handling (verifier BLOCKER-1).
- NVIDIA/kernel (L-D, 6A-130..134): GPU generation from the sysfs device id (Pascal was never detected); pre-Turing,
  nouveau and /etc/slacky-update/nvidia.disabled are left alone everywhere; nouveau blacklisted only after the NVIDIA
  driver is proven for every kept kernel; geninitrd images and /boot symlink targets are never deleted unless Limine is
  managed; LILO/ELILO hands-off with a reminder line; mkinitrd path fixed (TARGETED_PIPELINE, no fallback, private dir,
  atomic install); stock kernels are removed only while a CachyOS kernel runs; MOK signing dir root-owned; Secure Boot
  audit never prompts in the pipeline; NVIDIA rollback verifies the download first; packaging errors fail.
- Gnomes (L-E, 6A-135..139): no install without a terminal or --yes (exit 4); `runtime clean|remove` confirms; -R only
  touches its own rc scripts; merge keeps symlinks and never writes through them; cache cleanup only our dirs, 6 h; exit
  codes 0/1/3/4; heal by package file list, atomic pkgdb scrub; safe DB file names; new read-only `gnomes -Qu --json`.
- Cron/mirrors/tweaks/clean/ROCm/SBo (L-F, 6A-140..144): the weekly job only recommends a mirror; pre-Turing NVIDIA is
  never offered an update; fastboot: no live tmpfs over /tmp, rc.6 wait 2 s, no stale restore, NFS kept when exported;
  clean only our own old temp entries, kernel files kept when removepkg fails, package cache pruned by version; ROCm
  AMD-only, all-or-nothing with signatures; SBo no /tmp sources, MD5 required, sbotools pinned; check lock not in /tmp.
- Verification: author tests (L-B 50, L-C 48, L-D 89, L-E 45, L-F 72, lead bundle A 12) plus an independent
  verifier (fake roots, stubs, owner path traced; second pass after its BLOCKER-1/MAJOR-1..3 were fixed: see below).
- Known issues (documented for LTS): shared curated doinst uses absolute ln -sf (libcurl-gnutls alias, obs plugins);
  rc.<daemon> overwritten on upgrade; NVIDIA retired_by_slacky pkgdb move for stock/SBo NVIDIA packages; gnomes
  signatures log-only; ROCm accepts a missing .sig; sbotools pins need bumping on upstream change; emoji/E-series.

### 2026-10-14 Build 78_slacky - 6A-150 - Pending-updates badge cleared after a full update again
- After yesterday's full update that installed 5 Flatpak Mesa updates, the tray badge kept showing them. Cause (FACT):
  when status.json is older than 15 minutes the full update starts the status check in the background and goes on;
  that check read `flatpak remote-ls` before the Flatpak step, finished ~27 s later and wrote its old list over the
  file AFTER the run had crossed the updated suites off (reconcile_post_update_status). Now the run waits for its own
  background check (max 60 s, then stops it) before it records what it updated.
- Files: lib/common.sh (SLACKY_BG_CHECK_PID, ss_wait_background_check), bin/slacky-update (call before reconcile),
  SlackBuild (BUILD 78).
- Verification: fake background check that rewrites the old list 2 s later: without the wait the 5 Mesa entries come
  back, with it the list stays empty and the check's other results are kept. Real check measured at 27 s on this host.
- Also today (no code): Battle.net desktop icon pointed at a removed /opt/underpants/pkgs/faugus-launcher path (written
  by Faugus from an old PATH); fixed in the user's desktop file. Antigravity colours live in ~/.gemini/config/config.json
  (customThemeSeedsDark), not in the package; a user script was provided.
- Carry into Rust: a status refresh started by the run must finish (or be stopped) before the run records its results.

### 2026-10-14 Build 79_slacky - 6A-151 - Gnomes uses installed Slackware packages instead of bundling them again
- claude-desktop 2.37337 pulled 23 packages (qemu, xdg-desktop-portal, socat, ... ) although 13 of them were installed
  Slackware packages, several at the exact same version; the resolver only recognised host .so files, not installed
  programs/data. Footprint Guard kept the base safe (92 colliding files dropped), but the app was oversized and its
  bundled qemu lost its data files.
- Now an installed Slackware package of the same name (or a listed Arch split: qemu-system-x86, qemu-common,
  qemu-system-x86-firmware -> qemu) that is at least as new (pacman vercmp, epoch/pkgrel ignored) provides the
  dependency; never our own packages (underpants-/cachyos-, _gnomes/_slacky), never when the host lacks a .so the
  package provides, never for runtime builds (standalone).
- Plans on this machine: claude-desktop 23 -> 3, lutris 63 -> 33, easyeffects 62 -> 31, inkscape 58 -> 25,
  gamescope 22 -> 9, audacity 22 -> 17, filezilla 9 -> 5, vlc 49 -> 45, flameshot 3 -> 2; one-package apps unchanged.
- Older claude-desktop builds (8 versions, before the guard) had shipped Slackware-owned files of qemu (77),
  xdg-desktop-portal (61), vde2 (5), ndctl (2): those Slackware packages are reinstalled once (owner script).
- Files: lib/gnomes_pacman.py (slackware_host_packages, HOST_PACKAGE_ALIASES, host_package_satisfies, resolver step 6.5),
  SlackBuild (BUILD 79).
- Verification: real `deps` plans before/after for every installed gnomes app (read-only); py_compile. Not verified:
  a rebuilt claude-desktop's Cowork VM with Slackware's qemu.
- Rust: gnomes is an optional add-on, no Rust change.

### 2026-10-14 Build 80_slacky - 6A-152 - Legacy serves the shared SpiderSense reseal marker (spec v0.3)
- slacky-update-rs writes its boot-menu reseal order to /var/lib/slacky-boot/reseal-pending (shared spec path); legacy
  1.0 only read /var/cache/slacky-update/boot-reseal-pending, so a Rust order was never served. The hourly job now folds
  the shared marker into its own (Limine) or removes it (no managed Limine); a verified commit clears both; the snapshot
  pruner waits for either.
- Files: lib/common.sh (SLACKY_BOOT_PENDING_SHARED, clear_boot_reseal_pending, ss_prune_our_snapshots),
  cron/slacky-snapper-limine-sync, SlackBuild (BUILD 80).
- Verification: cron in a fake root with a stub slacky-update: shared marker served with --sync-boot and cleared on
  Limine; removed without a call on a non-Limine machine. bash -n.

### 2026-10-14 Build 81_slacky - 6A-153 - Each update is listed once; curated suite never rebuilds a Gnomes app
- User-visible: Discord was listed twice (curated + gnomes) in both apps. Apps installed with gnomes (audacity, discord,
  easyeffects, gamescope, inkscape, lutris) are now only gnomes updates; SBo gamemode/gnome-disk-utility/steam-devices are no
  longer claimed by the curated suite.
- Cause: the curated fast scan matched any package named underpants-<id> regardless of build tag; the check_backend dedupe
  compared the first word of the display line ("Official" vs "discord") and never filtered the raw list that deploy reads.
- Fix: lib/mod_gaming.sh fast scan counts only _slacky packages; new gaming_pkg_owned_by_gnomes() and the deploy loop skips
  gnomes-owned ids (stale cache safety); lib/check_backend.sh dedupes by curated id on both display and raw lists.
- Files: lib/mod_gaming.sh, lib/check_backend.sh, slackbuild/slacky-update.SlackBuild (BUILD 81), logs, roadmap.
- Verification: bash -n; helper on the real package db (6 gnomes ids true, mangohud/brave/steam-devices/prefixes false);
  dedupe block executed on the Discord case (gaming display+raw drop discord, keep mangohud); scan filter on the real db
  detects 36 curated _slacky ids and none of the gnomes/SBo ones. Not run: a full legacy check (needs network + root cache).
- Rust mirror: none needed in source (gaming.rs scan_installed only _slacky/_gnomes, status_store dedup_overlaps by id);
  the installed Rust Build 75 predates that and shows the duplicate until the next Rust install.

### 2026-10-14 Build 82_slacky - 6A-154 - Gnomes heal/cleanup never deletes a launcher that hides a Slackware file
- User-visible: `gnomes heal` and the cleanup in `bin/gnomes` kept removing marker launchers in /usr/bin even when they had
  replaced a stock file (xrandr, unzip, ...), so the original stayed gone. Now a launcher whose path is listed by a
  non-own (non _gnomes/_slacky/underpants-/cachyos-) package in the pkgdb is kept and reported with the exact
  `slackpkg reinstall <pkg>` command (advice only). Unowned launchers are deleted as before. Unreadable pkgdb = nothing deleted.
- The package-log scrubbing in heal is removed; /var/log/packages is never edited. `heal --json` has a new `kept_stock_owned`
  list, `affected_packages` is always empty (the automatic slackpkg reinstall loop in mod_packages.sh can no longer trigger),
  `cleaned_logs` stays 0.
- Files: lib/gnomes_pacman.py (heal_host_sovereignty, heal CLI output), bin/gnomes (stock_owner_of_usr_bin,
  remove_wrapper_unless_stock, cleanup_stale_wrappers), lib/mod_packages.sh (heal_host_sovereignty_subsystem), SlackBuild (BUILD 82).
- Verification: py_compile, bash -n; fake pkgdb + fake /usr/bin: stock-owned wrapper kept and advice shown, unowned wrapper
  deleted, an underpants-* record unchanged byte for byte; bash helpers tested in a fake pkgdb. Not run: on the real system.
- Rust mirror: SpiderSense C2/C3 (already there).

### 2026-10-14 Build 82_slacky - 6A-157 - Limine committed record and read-only tamper report (spec 6.1, C29)
- After each verified Limine commit (enroll_limine_config_hash, so also --sync-boot, --sync-snapper and the hourly cron
  repair) legacy writes /var/lib/slacky-boot/limine-committed: one JSON line {"v":1,"txid","app":"slacky-update","ts",
  "blake2b","sha256"} of the live limine.conf, temp + mv, root:root 0644, written before the reseal marker is cleared.
  A failed write only warns. Same format as the Rust side.
- The hourly cron job compares the live limine.conf with the record and, when they differ and no reseal marker exists (and
  no update is running), logs one plain line in /var/log/slacky-update.log (once per distinct state). Missing, untrusted
  (not root-owned, link, group/world-writable) or malformed record = silent. It never reseals a foreign edit.
- Files: lib/mod_limine.sh (limine_write_committed_record), cron/slacky-snapper-limine-sync (limine_tamper_report), SlackBuild (BUILD 82).
- Verification: bash -n; fake root: record written with correct BLAKE2B-512/SHA-256 (checked against python hashlib), mode 0644,
  no temp left; report silent when consistent, one line on a foreign edit (no repeat), silent with a marker or a
  world-writable record. Not run: a real seal on the ESP (needs root/sbctl), and root:root ownership (chown stubbed in the test).

### 2026-10-14 Build 83_slacky - 8A / 8B / 8C - Config store capture, consent-only .new handling, bulk overwrite removed
- User-visible: `.new` configuration files are changed only after you type `y`, and only when it is provably safe (you never edited the
  file, Slackware did not change it, identical copy, or the file is missing). Owner, group and mode of your file are kept; a `.orig`
  copy and a journal entry are kept. With `-y`, `NON_INTERACTIVE` or no terminal nothing is changed and one sentence says
  "N configuration files are waiting for you". The "overwrite all customized files" choice and the default-yes groups A-C are gone.
  `slackpkg.conf.new` no longer replaces `slackpkg.conf` when a VERSION line is missing.
- Technical: new `lib/slacky_config.py` (run with `python3 -I`): `capture` writes `/var/lib/slacky-config/` in the shared format 1
  (objects/<sha256>, index.json, lock, undo/<txid>/manifest.json; root 0700/0600, atomic writes, flock on the index, no links, never
  passwd/group/shadow/gshadow, 2 MiB / 20000 caps, mtime rule 120 s). `reconcile` classifies by exact base from the store.
  Backups of files inside `*.d`/`cron.*` folders go only into the store.
- Files: lib/slacky_config.py (new), lib/mod_packages.sh (capture hooks in `update_slackware_core`, `reconcile_new_config_files`,
  `auto_reconcile_slackpkg_conf`), slackbuild/slacky-update.SlackBuild (installs the helper, BUILD 83).
- Verification: fake roots in the scratchpad (deleted after green): store layout/modes/field order, symlinked and group-readable
  store refused, late rule, base catch-up; `-y` and no-TTY leave /etc byte-identical; answers other than y change nothing; mode 0755 and
  a supplementary group kept on replace, `.orig` beside the file, none inside profile.d; journal and index base moved; pinned,
  edited, no-base, symlinked and boot-critical files kept; bulk overwrite strings gone; slackpkg.conf cases. `bash -n`, `py_compile`.
  Not verified: a run as real root (chown to another uid; tests used the test user), the real update flow, the Rust app reading this
  store (byte-compat was checked against the spec and the Rust writer's field order only).
- Known limits: the in-file pin `# slacky: keep` is honoured; the pins file of the Rust app is not read (rule 1). Boot-critical
  files (pam.d, fstab, inittab, rc.S, rc.M, sudoers, ...) are never handled here.

### 2026-10-14 Build 83_slacky - 9A / 9B / 9C / 9D - Detect and advise damaged packages (no repair)
- User-visible: `slacky-update --heal-check` prints which installed packages miss files or have a folder replaced by a link and the one
  command `slackpkg reinstall <names>`; silent when clean (exit 51 with damage). A full update stops before any change when a package of
  the update set has a folder replaced by a link (one sentence, exit 30). After an update one sentence appears only when damage exists.
- Technical: new `lib/slacky_heal.py` (read only, normal user, no sudo, no state). 9A (6A-154) was fixed in Build 82: re-verified by reading
  `heal_host_sovereignty` / `remove_wrapper_unless_stock` and by a fake-root run of the bash helper (wrapper kept, advice printed, package
  db untouched).
- Files: lib/slacky_heal.py (new), bin/slacky-update (`--heal-check`, hold before the plan, post-update sentence, help line),
  slackbuild/slacky-update.SlackBuild.
- Verification: fixtures 1-12 of docs/healing_legacy_9A-9D.md in fake roots (sentences, command, never/third-party/compat32 rules, tools,
  more than 50, intentional link, skip rules, octal names, version note, clean = silent, root byte-identical); 2000 packages x 100 files
  audit in 0.4 s. Not verified on the real system or in a real full update (the hold exit path in `run_full_update` was read, not run).

### 2026-10-14 Build 84_slacky - 6A-163..6A-170 (mirrors the Rust curated-engine fixes) - Curated package fixes: linker files, DKMS, LACT, OBS, driver names
- User-visible: audacity, darktable and inkscape no longer put `/usr/lib64` and `/usr/lib` (or their own folders) on the linker path of the whole system, and audacity keeps its program when it has no private folder (163, 165). Files that a Slackware package owns were already dropped by the Footprint Guard before packaging (164, re-checked). A DKMS driver's install script registers only the driver folders of its own package (166). The `k10temp` -> `zenpower` swap happens only when the zenpower module exists for the running kernel, and `k10temp` is loaded again if `zenpower` will not load (167). Driver packages now unregister their module from DKMS when they are removed (168). After an install LACT is started only if no daemon runs; a running one is restarted (169). The OBS bundle step no longer leaves a link that points at itself, and cleans one that an older build left (170). Catalog: `rtl8821cu` now reads `rtl8821cu-morrownr-dkms-git`, `r8125` is looked up in chaotic-aur, and `rtl88x2bu` / `rtl8812au` (no package in any repo we read) are hidden and say so in one sentence.
- Technical: `lib/mod_gaming.sh` only. New helpers `slacky_dkms_own_entries` and `gaming_pkg_unavailable_reason`; `SU_DKMS_OWN` list written into the generated `doinst.sh`; a DKMS part appended to the generated `douninst.sh` (runs only when the source folder, and any other folder shipping the same module and version, is gone; an upgrade keeps everything); the `lact` branch of the post-install daemon start; catalog rows, the two repo-regex tables, the `aur_pkg_names` rows and the supersede patterns for the renamed drivers. `slackbuild/slacky-update.SlackBuild`: BUILD 84_slacky. New user-run repair script `docs/repair/6A-163_remove_global_ld_conf.sh` for the files already installed (dry run by default, `--yes` to apply, Btrfs snapshot first, removes only `audacity.conf`/`darktable.conf`/`inkscape.conf` in `/etc/ld.so.conf.d` that belong to our packages only and still have our exact text, backs them up, runs `ldconfig`).
- Verification: `bash -n` on `lib/mod_gaming.sh`; the changed snippets extracted from the real file and run with `sh` against fake roots in a temp folder (own-folder DKMS registration, uninstall and upgrade cases, zenpower with and without a built module and the fallback, OBS link cases incl. the old damage, audacity staging with and without the private folder, the Footprint Guard against a fake package db, catalog rows); the repair script run in `SU_REPAIR_ROOT` fake roots (dry run, apply, foreign owner, hand-edited file). All green. NOT verified: a real package build and install, a real `removepkg` run of the new `douninst.sh` (read in `/sbin/removepkg` only), shellcheck (not installed), the repair script on the real system (the owner runs it).
- Known limits: `rtl88x2bu` / `rtl8812au` stay hidden until a package appears; the check used the cached repo indexes of 2026-10-12. Files to commit: `lib/mod_gaming.sh`, `slackbuild/slacky-update.SlackBuild`, `docs/repair/6A-163_remove_global_ld_conf.sh`, `docs/log.md`, `docs/log_nb.md`, `claude_log.md`. Rust mirror: same IDs in the Rust repo `claude_log.md`.

### 2026-10-15 Build 85_slacky - 6A-174 - heal-check no longer calls Slackware's own folder links damage
- User-visible: `--heal-check` (and the line after an update) reported 68 damaged packages on the owner's machine and advised restoring a snapshot. 63 of them were false: folders that are links on purpose. It now reports only real damage (5 packages here: bcachefs-tools-compat32 stale DKMS source list, cachyos-gnome-scx D-Bus file, libnfs SBo programs, mactahoe cursors, rpm temp file).
- Technical: `lib/slacky_heal.py`: a folder->link is intended when ANY package's install script makes exactly that link (`aaa_base`: `var/run`, `usr/share/doc`, `usr/share/man`), when another package lists the path as a plain entry (breeze-icons `16@2x` links that easyeffects lists as folders), for the pkgtools migration links `var/log/{setup,packages,scripts}`, and for our own packages when the link points at a host folder the same package ships (OBS bundle bridge). The extra scan only runs when a link was found. `slackbuild/slacky-update.SlackBuild`: BUILD 85_slacky.
- Verification: real system read-only (68 -> 5, the 5 are real); fake root with each rule plus one real damaged link that is still reported. Rust mirror: `spidersense --audit` already gave the same 5 on this machine (global script scan, own packages not link-checked); no Rust change.
- Files to commit: `lib/slacky_heal.py`, `slackbuild/slacky-update.SlackBuild`, `docs/log.md`, `docs/log_nb.md`, `claude_log.md`.

### 2026-10-15 Build 85_slacky (uncommitted) - 6A-171 / 6A-172 / 6A-173 / status-cache split - OBS plugin library, Glycin cache path, links out of the package, newest status file
- User-visible: (171) curated OBS plugins built by the old engine (advanced-scene-switcher, move-transition, multi-rtmp) now get their main `.so` in `/usr/lib64/obs-plugins`, so OBS can load them. (172) apps with Glycin get a pixbuf loader cache that names the installed folder, not the build folder. (173) a package can no longer make the builder change permissions on, rewrite, or read host files through a link that points out of the package. Status split: the NVIDIA mismatch hint, the curated-update fast path and the TUI "Available Updates" box now use the newest status file (user cache or /var), like the tray and the CLI already did.
- Technical: `lib/mod_gaming.sh`: the OBS bridge skip test now looks at the folder names of the path inside the package and does not count `obs-plugins` itself as a `*-plugins` subfolder (Rust rule). `lib/gnomes_pacman.py`: `loaders.cache` rewrite uses `/opt/underpants/pkgs/<app>/lib/` (`/opt/underpants/runtime/lib/` for the runtime) instead of the staging path; `os.chmod` on `bin/*`, the `.desktop` `Exec=` rewrite and systemd unit reads skip a link whose real path leaves the app/staging tree (`_merge_inside`). `bin/slacky-update` (nvidia_gl_mismatch read via `get_status_key_count`), `lib/mod_gaming.sh` (`cachyos_gaming_updates_raw`), `lib/slacky_tui.py` (pending-updates box): pick the newest valid `last_check_ts` instead of /var first or first existing file. Why the files diverged: `check_backend.sh` runs as the user (owner rule: no random sudo prompts), so it writes `~/.cache/slacky-update/status.json`; `/var/cache/slacky-update/status.json` is only refreshed by a root run (cron, sudo update) and has been stale since 2026-10-13. Rule for both apps: writers write where they may write (user cache; /var only as root), readers take the newest valid file.
- Files touched: `lib/mod_gaming.sh`, `lib/gnomes_pacman.py`, `lib/slacky_tui.py`, `bin/slacky-update`, `claude_log.md`, `docs/log.md`, `docs/log_nb.md`. (Please commit these; not committed here.)
- Verification: `bash -n` on `bin/slacky-update` and `lib/mod_gaming.sh`, `py_compile` on `lib/gnomes_pacman.py` and `lib/slacky_tui.py`; fake-HOME test of `get_status_key_count` and the extracted `mod_gaming.sh` snippet (newer user file wins over /var); OBS skip condition checked on sample paths (loose `obs-plugins/x.so` kept, `x-plugins/y.so` skipped); `_merge_inside` checked with an absolute link out of the tree (false) and a relative link inside (true). NOT verified: a real transmute or a real OBS plugin build (needs network and root), the TUI box on screen.
- Known limits: the cron mail/notify script reads /var after its own root check, so it is consistent; the tray already took the newest file. Rust mirror: 6A-171/172/173 were already correct in Rust.

### 2026-10-15 Build 86_slacky - 6A-175 / 6A-176 / 6A-177 / 6A-178 / 6A-179 / rec 3 - vendor downloads checked, Edge cron job, flags in /etc/skel, Opera hidden, gnomes builds left alone (mirror: Rust 6A-175..179)
- User-visible: Claude Desktop, Claude Code and Gemini CLI builds now stop with "could not be verified" unless the file matches the checksum the vendor publishes (npm SHA-512 of that exact version, Anthropic's apt index SHA-256). Edge no longer gets Microsoft's apt helper as a root cron job. Chrome/Brave/Edge flag files go to `/etc/skel/.config` only (never into a home folder as root, never through a link). The Opera row is hidden with one sentence. A program installed by gnomes (`underpants-<id>` `_gnomes`) is never replaced by the curated build: one sentence says to remove the gnomes one first.
- Technical: new `lib/slacky_vendor_fetch.py` (npm record and apt index parsing, capped https reads, capped verified download, `filter='data'` or an equivalent member check; absolute links only for the .deb and never written through); `lib/mod_gaming.sh`: the three PYBUILD blocks use it (fourth argument = folder of the helper, empty = stop), `_slacky_vendor_fetch_dir`, Edge cron path dropped in the staging step, flag loop mirrors the Rust snippet (`printf '%b\n'`, `-e`/`-L` skip, home block removed), `opera|...|hidden` plus the reason text, `gaming_pkg_other_engine_sentence` in the sync loop and as a gate in `_transmute_and_deploy_gaming_pkg_impl`. `slackbuild/slacky-update.SlackBuild`: installs the helper, BUILD 86_slacky. New `docs/repair/6A-175_remove_edge_apt_cron.sh` (user-run, dry run by default, snapshot first).
- Files touched: `lib/slacky_vendor_fetch.py` (new), `lib/mod_gaming.sh`, `slackbuild/slacky-update.SlackBuild`, `docs/repair/6A-175_remove_edge_apt_cron.sh` (new), `docs/log.md`, `docs/log_nb.md`, `claude_log.md`. (Please commit these; not committed here.)
- Verification: `bash -n`, `python3 -I -m py_compile` (cache folder removed); offline tests with `urlopen` patched: npm and apt parsing with 14 hostile variants, download good / changed / cached / too large / http, extraction refusing traversal, absolute names, outside links, devices, writes through links, and the real heredoc text of the three PYBUILD blocks run end to end (good file builds, changed file stops, traversal tarball refused, missing helper stops); repair script in fake roots (ours, foreign owner, other target, absent, not root); the flag loop against a fake `/etc/skel` with a planted link and an edited file; the gnomes gate functions against a fake package folder; the footprint guard against a fake database (libhandy / libdvdread / SBo files all dropped).
- Known limits: nothing was run against the real npm registry or Anthropic's server from this tree (the Rust side read both live: the apt index entry for 2.37337.1 equals the SHA-256 the Rust app had pinned by hand). Trust is "https to the vendor host" (the apt `InRelease` PGP signature is not checked). 6A-177: no code change was needed, the installed copy on the owner's machine predates the guard (repair = reinstall the Slackware `libhandy` / `libdvdread`, Step 2). The user must run the 6A-175 repair script himself.

### 2026-10-15 Build 86_slacky - 6A-180 / 6A-181 / 6A-182 / 6A-183 - mirror fall-back, daily Chaotic ranking, one shared helper, current CachyOS mirrors (Rust mirror: already done, 104ddd3)
- User-visible: when the first download server of a package repository is down or sends an error page, the update now tries the next fastest server (at most 4) instead of giving up; a file that fails its signature check is never replaced by a file from another server (the build still stops). When every server failed you get one plain sentence: "No download server for <repo> answered. Check your internet connection and try again later." The Chaotic-AUR server choice is refreshed once per day (or 10 minutes after a server failed). The server benchmark no longer lists the two CachyOS hosts that do not exist any more and knows cdn77.
- Technical: new `lib/slacky_mirrors.py` (the one source of the Arch, CachyOS and Chaotic mirror lists, `alternatives()`, the Chaotic cache `chaotic_fastest_mirror.json` with the old keys plus `ranked`, `probed_ts`, `needs_refresh`; stale on a new calendar day or 10 minutes after a failure, a failed mirror sinks behind the other candidates, cdn-mirror is a never-probed last resort, own regular file only). 6A-180 `lib/gnomes_pacman.py` `sync_repositories`: ranked mirrors in order, a body that is not gzip/zstd is rejected, If-Modified-Since, 304 and the monotonic check unchanged. 6A-181 `lib/common.sh` `download_parallel_pacman`: ranked fall-back per file, 4xx does not sink a mirror, a `.pkg.tar.zst` from a known family must start with the zstd magic, the `.sig` comes from the mirror that served the file, 404/signature problems stay fail-closed in the caller. 6A-182 `lib/mod_gaming.sh`: the three copies of `get_chaotic_fastest_mirror` are one short shim over the helper (the old "up to 7 days unless Thursday" rule is gone). 6A-183 `lib/rank_mirrors.py`: lists imported from the helper (eu/asia.cachyos.org removed: no DNS record, `curl` exit 6, checked 2026-10-15; cdn77.cachyos.org added and answered 206; Chaotic has the 11 regional mirrors, cdn-mirror last).
- Files touched: `lib/slacky_mirrors.py` (new), `lib/gnomes_pacman.py`, `lib/common.sh`, `lib/mod_gaming.sh`, `lib/rank_mirrors.py`, `slackbuild/slacky-update.SlackBuild` (installs the new file; BUILD unchanged), `claude_log.md`, `docs/log.md`, `docs/log_nb.md`. (Please commit these; not committed here.)
- Verification: `bash -n` on `lib/common.sh`, `lib/mod_gaming.sh`, the SlackBuild; `python3 -I -m py_compile` on the changed Python and on the heredoc scripts extracted from `common.sh`/`mod_gaming.sh` (cache folders removed); offline tests in a temp dir with local HTTP servers and a fake HOME: first mirror down -> second used, html body rejected, 304 kept, all down -> one sentence, unknown host unchanged, 404 not sunk, 500/connect error sunk, a valid-looking file is not re-asked from another mirror, the daily/10-minute rule, cache-file keys, symlinked cache ignored, 4-attempt bound; one real read-only probe of the Chaotic mirrors into a temp cache (0.33 s).
- Known limits: not run through the real `slacky-update` flow or against a real failing mirror. The repository listing pages that the resolver reads (`fetch_url_cached`) still use one Chaotic mirror per run (it is only the download that falls back). Arch/CachyOS failures are not remembered between runs (their order comes from `ranked_mirrors.json`, which only the benchmark writes). A new run starts with the new file `slacky_mirrors.py`; without it everything behaves as before (single mirror, geo mirror for Chaotic).

### 2026-10-15 Build 86_slacky (no bump) - 6A-185 / 6A-186 / 6A-187 / 6A-188 / 6A-189 / 6A-190 / 6A-191 - curated round 5 fixes (mirror of the Rust D-series round 5)
- User-visible: Blender and FreeCAD packages start again (the launcher no longer replaces the program or calls itself); a rebuilt Steam controller rules package no longer removes the SlackBuilds.org `steam-devices` package; the DaVinci Resolve AAC plugins are no longer refused as "empty"; yabridge can be resolved again (no 32-bit part is required); Volt GUI, Plasticity and Storyboarder are not offered any more (AUR only, no signed source), each with one plain sentence; FreeCAD no longer ships a login script for OpenCASCADE.
- Technical (`lib/mod_gaming.sh`): blender block moves a regular `usr/bin/blender` to `usr/bin/blender-bin` before the launcher is written (a link is removed, never written through); freecad block drops `etc/profile.d/opencascade.{sh,csh}`, never writes through a link, keeps the package's own `usr/bin/FreeCAD` link (only if absent and `usr/lib64/freecad/bin/FreeCAD` exists, links to that); `cleanup_foreign_gaming_pkgs` steam-devices pattern is only `game-devices-udev-[0-9]*`; payload check for dvcp-aac accepts any file under `opt/resolve/IOPlugins`; the yabridge lib32 pattern is `None` in both resolver tables; catalog rows volt-gui, plasticity, storyboarder carry `|hidden` and `gaming_pkg_unavailable_reason` gives their sentences (comment: AUR only, a source may be added later). 6A-191 for bambu-studio and the 60-steam-input.rules file rest on the existing footprint guard (drops files owned by non-own packages); verified in a fake package database. New user-run repair `docs/repair/6A-191_remove_opencascade_profile.sh` (dry run by default, `--yes`, snapper snapshot first, removes only `/etc/profile.d/opencascade.sh` when only `underpants-freecad-*` owns it and it is not newer than the package record).
- Files touched: `lib/mod_gaming.sh`, `docs/repair/6A-191_remove_opencascade_profile.sh` (new), `claude_log.md`, `docs/log.md`, `docs/log_nb.md`. (Please commit these; not committed here.)
- Verification: `bash -n lib/mod_gaming.sh` and the repair script; the blender and freecad blocks run in fake staging trees in a temp dir (regular file, link, own link, no own link, profile scripts); the repair script run with `SU_REPAIR_ROOT` fake roots (dry run, apply, edited file, shared owner, SBo owner); `footprint_guard` run on a fake pkgdb (webkit2gtk/libsoup3, the Valve rule and `opencascade.sh` dropped). Not verified: a full curated build, `cleanup_foreign_gaming_pkgs` against a real package database, the real catalog flow in the TUI.
- Known limits: on the owner's machine `opencascade.sh` is no longer present and the old record lists it under `underpants-runtime-all`, so the repair script would leave it alone there by design (it only acts on files owned by our FreeCAD package alone). Opera, bambu-studio and spacenav rows unchanged.

### 2026-10-15 Build 86_slacky (no bump) - 6A-192 - Bambu Studio from the official Bambu Lab GitHub release AppImage (mirror of Rust D-series round 6)
- User-visible: Bambu Studio can be built again. It used to look for the dead name `bambu-studio-bin` (a third-party fork no repository carries), so the update or install never produced a package. Now the official AppImage from Bambu Lab's GitHub release page is downloaded, checked against the SHA-256 the release API names, and only then unpacked; a download that does not match stops with "could not be verified" and nothing is changed. Prereleases are never taken.
- Technical: `lib/slacky_vendor_fetch.py` gets `parse_github_releases` / `github_release_record` / `verify_github_asset` (newest non-prerelease, uploaded asset named like the Ubuntu 24.04 AppImage, address exactly `https://github.com/<repo>/releases/download/<tag>/<name>`, `digest` sha256, size), `check_squashfs_listing` / `unpack_appimage` (ELF section table end = image offset, `unsquashfs -lls` check of entries, size and plain paths, extraction with `-no-xattrs`, plain modes, the file is never run) and `fix_needed` (the four `patchelf` name fixes of older builds). `lib/mod_gaming.sh`: catalog row and both embedded resolver catalogs use the AppImage name and the library parts (webkit2gtk-4.1, libsoup3, libavif, libyuv, rav1e, svt-av1); `github_and_direct_pkgs` gets `bambu-studio` with `skip_prerelease` (both resolver copies); the early-return block that looked for `bambu-studio-bin` in Chaotic and the AUR RPC is gone, as are the two `aur_pkg_names` entries; the update check reads the GitHub list; `cleanup_foreign_gaming_pkgs` removes an older `bambu-studio-[0-9]*`; the standard download branch verifies the AppImage and unpacks it into `opt/bambu-studio-<ver>`; the bambu block adds the `opt/bambu-studio` link, the desktop entry and icons from the AppImage and drops the command line tools and development files of the library parts.
- Files touched: `lib/slacky_vendor_fetch.py`, `lib/mod_gaming.sh`, `claude_log.md`, `docs/log.md`, `docs/log_nb.md`. (Please commit these; not committed here.)
- Verification: `bash -n lib/mod_gaming.sh`; `python3 -I -m py_compile lib/slacky_vendor_fetch.py` (cache folder removed); offline test script (66 checks, `urlopen` patched, temp HOME): the real release list of 2026-10-15 (prereleases 02.08.03.66 / 02.08.04.57 skipped, 02.08.02.61 chosen, digest and size as published), 13 hostile release variants (no digest, other algorithm, not hex, no size, not uploaded, http, other repository / host, path in the name, name pattern, prerelease, draft, odd tag), a changed or renamed download refused, the real 230 MB AppImage accepted against the API digest, listing checks (traversal, absolute names, devices, link without target, entry and size limits), a squashfs built with `mksquashfs` unpacked (setuid dropped, links kept, non-empty folder refused), the four `patchelf` fixes on a real program, all five heredoc scripts compile, `PYRESOLVE` and `PYBATCHRESOLVE` return the AppImage address and the six library parts and never the dead name, and the bambu block of the build run in a fake staging tree with the real unpacked AppImage (link, desktop entry, three icon sizes, pixmap, tools and dev files removed).
- Known limits: not run through the real `slacky-update` build and install flow (no root, nothing installed). An older installed `bambu-studio-<ver>` package is removed by the cleanup only after a verified install. Opera and spacenavd / spnavcfg: no change here (later owner decision).

### 2026-10-15 Build 86_slacky (no bump) - 6A-200 - keyring chain of trust: never older, revocations only grow, shared key store (Rust mirror: MS2)
- User-visible: nothing yet (the keyring install is wired in 6A-202). The signing-key code that will refresh the Arch, CachyOS and Chaotic keys now follows the shared rules: a keyring package without a signature, older than the keys in force, missing a revocation, or not provably signed by the keys we trust is refused with one sentence and nothing is changed. Package checks (`verify_package`) now also use the newest valid key generation and the keys shipped with the program as a floor.
- Technical: `lib/gnomes_trust.py` `_build_keyring` replaced by `verify_keyring_package` (read-only rules), `install_keyring` (root: flock on the family folder, re-verify, write `gen.<stamp>`, swap `current`/`previous` by rename, keep two), `stage_keyring`/`install_staged` (user stage, root re-verify), `check_rings` (several rings, union of revoked lists, `allowed` pins for the shipped snapshot), `locate_generation`. `meta.json` gains `pkgver`, `builddate`, `dynamic_anchors`, `via`, `writer` (optional for readers; older generations take the version from `keyring_pkg`). CachyOS now vouches keys from `cachyos-trusted` like Chaotic (spec section 4 rule 6). `locales/en.json`, `nb.json`: `GNOMES_TRUST_KEYS_*` sentences.
- Files touched: `lib/gnomes_trust.py`, `locales/en.json`, `locales/nb.json`, `docs/log.md`, `docs/log_nb.md`, `claude_log.md`. (Please commit these; not committed here.)
- Verification: `python3 -I -m py_compile`; `gnomes_trust.py selftest` (113 checks, fake keys root); a 67-check offline suite with throwaway gpg keys in a temp store (bootstrap via master path, continuity, older/equal/future/older-release, stripped and missing revoked list, anchor missing/revoked, flipped byte, unknown signer, 1-certification signer, dynamic anchors, vouching, vouched key cannot sign, shipped floor, union of revoked lists, group-writable folder fails closed, bad `current` link, lock held, store root a link, generation in the older format, staged tamper/link/wrong owner, recorder events). Not verified: the real store, a real upstream keyring package, behaviour as root (only own-uid ownership checked).
- Known limits: the shipped Arch snapshot is evaluated with `gpg --check-sigs` (about 1 s) the first time a floor is needed in a process. Rust-side finding: `locales/nb.json` `KEYS_REFUSED_CHECKS` says "beståtte" (should be "bestod").

### 2026-10-15 Build 86_slacky - 6A-193 - Theme packages come from pinned, checked archives
- MacTahoe and WhiteSur icon and cursor themes are no longer built from a `git clone` of a moving branch. Each comes from one pinned commit archive with a SHA-256 check (MacTahoe 839848b9, WhiteSur icons 73d8040d, WhiteSur cursors e190baf6; same pins as the Rust engine); the project's `install.sh` runs only on the verified archive (refused if it mentions git clone, curl, wget or sudo). The update check offers the pinned versions only (2026.09.10.r0.839848b9, 2026.09.10, 2025.04.05.r0.e190baf6).
- Files: `lib/mod_gaming.sh` (`PYBUILD_THEME`, version output of the theme ids, scanner). Rust mirror: already correct (commit 2519e1e).
- Verification: `bash -n`; the build script run offline against fixture archives (good, wrong checksum, hostile `install.sh`) and against the real pinned MacTahoe archive from an earlier download (27 variants, exit 0). Not verified: a live download from GitHub, an installed result.
- Follow-up: raising a pin is a code change (like `HYPRMOD_LOCK`).

### 2026-10-15 Build 86_slacky - 6A-194 - HyprMod permissions: build gate and user-run repair
- New packages are refused if any file would be group- or world-writable (the existing `chmod -R u=rwX,go=rX` already clears it; the gate fails closed). New repair script `docs/repair/6A-194_hyprmod_permissions.sh` (dry run by default, `--yes`, snapper snapshot first) runs `chmod go-w` only on root-owned, currently group/world-writable entries listed in the `underpants-hyprmod` package log, saves the old modes. Rust mirror: already correct (commit 2519e1e); the Rust side needs the same repair for the installed package (same script).
- Files: `lib/mod_gaming.sh` (gate after the permission step), `docs/repair/6A-194_hyprmod_permissions.sh`.
- Verification: `bash -n`; the script in a fake root (dry run, apply, links and unlisted files untouched, second run no-op). Not verified: a real run with snapper on the machine.

### 2026-10-15 Build 86_slacky - 6A-195 - No links or files with odd names in packages
- Links whose path or target has characters outside letters, digits and `. _ + @ % , = : - /` (for example the upstream typo link `...Application.svg}`) and files with `{ } $ ` backslash ; | & < > "` or control characters in the name are left out of curated packages, with one line ("Left out N link(s) or file(s) with unusual names."). Same rule as the Rust packer for links (Rust refuses the whole package; legacy drops and goes on).
- Files: `lib/mod_gaming.sh` (`gaming_drop_odd_names`, called before the footprint guard). Rust mirror: already correct (commit 2519e1e).
- Verification: `bash -n`; fake tree (good link, `}` link, link with a space in its target, `}` file, file with spaces and brackets kept, `install/` untouched); the real MacTahoe tree (18 typo links dropped). Known limit: any other package whose links use unusual characters now loses those links.

### 2026-10-15 Build 86_slacky - 6A-196 - Hyprland suites and hyprpicker no longer overwrite each other
- Policy (coordinator recommendation, owner confirmation pending): hyprland-noctalia, hyprland-core and hyprpicker are mutually exclusive. Installing a suite replaces the other suite and a separate hyprpicker (the old patterns never matched the installed `underpants-` names); hyprpicker alone is skipped with "Hyprpicker is already part of the installed <suite> desktop, so it is not installed on its own." when a suite is installed. All of it sits in `GAMING_HYPR_SUITES`, `gaming_hypr_exclusive_patterns` and `gaming_hypr_exclusive_skip` so it is easy to change.
- Files: `lib/mod_gaming.sh`. Rust mirror: none made; the Rust guard already refuses differing bytes (commit 2519e1e); Rust could add the `underpants-` base names to `HYPRLAND_SUPERSEDES` if the owner confirms.
- Verification: `bash -n`; the three helper functions with a fake package folder. Not verified: a real upgrade between the two suites.

### 2026-10-15 Build 86_slacky - 6A-197 - Hyprland suites keep Slackware-owned files out
- No new code needed: the footprint guard that every curated build runs (`gnomes_pacman.py footprint-guard`, enforce mode) already drops files Slackware packages own. Checked with a fake package database (libjpeg-turbo tools and libraries, libical C++/glib libraries and vapi): 9 of 11 staged files dropped, the suite's own files kept. Rust mirror: already correct (commit 2519e1e).
- Files: none. Not verified: against the real package database (a build with the real database would list the 14 files).

### 2026-10-15 Build 86_slacky - 6A-198 - Bambu CH340 udev rule never shipped, user-run removal
- `99-bambulab-devices.rules` (mode 0666 for every CH340 USB-serial device) is removed from the bambu-studio staging tree if any part brings it. New repair script `docs/repair/6A-198_remove_bambu_udev_rule.sh` (dry run by default, `--yes`, snapper snapshot first) removes it only when it is a plain file mentioning 1a86, owned only by our bambu package and not changed after the install, then runs `udevadm control --reload-rules`.
- Files: `lib/mod_gaming.sh`, `docs/repair/6A-198_remove_bambu_udev_rule.sh`. Rust mirror: not carried over by design (6A-192).
- Verification: `bash -n`; the script in a fake root (foreign-owned copy left alone, ours removed with backup, modified copy left alone). Not verified: a real run, the udev reload.

### 2026-10-15 Build 86_slacky (no bump) - 6A-201 - weekly signed mirror lists, mirror health history, Arch status hints (Rust mirror: MS3 / MS4 / MS5 / MS6)
- User-visible: nothing to see. Once a week, quietly and without sudo, the program reads the signed server lists of Arch, CachyOS and Chaotic-AUR, adds new download servers to its candidates, and remembers which servers fail or lag so a dead or stale server is asked last. The built-in server lists remain as the fallback. The Chaotic server ranking is now weekly instead of daily. The CachyOS and Chaotic rankings of `rank_mirrors.py` work again (they probed paths that answer 404).
- Technical: new `lib/slacky_sentinel.py` (strict list grammar, signed-list fetch through `gnomes_trust.verify_package`, monotonic build date, Arch JSON with ETag/gzip/monotonic `last_check`, health history with retire/revive/demote, probe round of at most 8 per family in 1.5 s, lag, own-uid 0700/0600 cache, no cache use as root, flight-recorder events `mirror.list.ok|rejected`, `mirror.status.ok|rejected`, `mirror.retired|revived|lagging|lag_cleared`). `lib/slacky_mirrors.py`: `builtin_lists` (floor) + merged `_family_lists`, state-ordered `alternatives`, `note_success`/`note_failure` for all families, `benchmark_candidates`, weekly `is_stale`. `lib/check_backend.sh` starts `weekly` next to the benchmark (user only). `lib/common.sh` and `lib/gnomes_pacman.py` report download results.
- Files touched: `lib/slacky_sentinel.py` (new), `lib/slacky_mirrors.py`, `lib/rank_mirrors.py`, `lib/common.sh`, `lib/gnomes_pacman.py`, `lib/check_backend.sh`, `lib/gnomes_trust.py`, `slackbuild/slacky-update.SlackBuild` (installs the new file; BUILD unchanged), `docs/log.md`, `docs/log_nb.md`, `claude_log.md`. (Please commit these; not committed here.)
- Verification: `bash -n` on the changed scripts and the SlackBuild, `python3 -I -m py_compile` on the changed Python (no `__pycache__` left); 111 offline checks with local HTTP servers, throwaway gpg keys and a temp key store (see docs/log.md). Not verified: the real upstream lists, the real Arch JSON, a real failing mirror, the SlackBuild install.
- Known limits: CachyOS mirrors are one family in legacy (the three tier lists are merged). Slackware mirror lag is not part of this step. Rust-side findings for the coordinator: `src/packages/mirror_rank.rs` `CACHY_MIRRORS` still lists `eu.`/`asia.cachyos.org` (no DNS record) and `CHAOTIC_MIRRORS_LEGACY` has the dead `bg-` (404), `es-` and `us-ut-` (503) hosts as of 2026-10-15 (they only waste probe slots; the built-in floor could drop them).

### 2026-10-15 Build 86_slacky (no bump) - 6A-202 - key freshness on every check, expiry notice, signing keys installed first in a full update (Rust mirror: MS7 / MS8)
- User-visible: `slacky-update --check` can now say, in one plain sentence and at most once a week per condition: only one download server works for a repo, none works, the server list could not be refreshed for a month, a signing key will expire within 60 days (run a full update), or new signing keys could not be confirmed. A full update installs a newer, already-verified signing keyring first, before any package; nothing is asked and no sudo is used when nothing is waiting.
- Technical: `lib/slacky_sentinel.py` `keys_check` (database listing, undated Chaotic alias with `If-Modified-Since`, download, `gnomes_trust.stage_keyring`, refusal record, prune), `expiry_radar` (key expiry from the generation's ring, keys used in the last 90 days), `due_alerts` (7-day rule in state.json), CLI `keys-check`, `alerts`. `lib/gnomes_trust.py`: signer noting in `verify_package`, CLI `install-staged` (root only) and `keyring-check`. `lib/mod_packages.sh`: `slacky_keys_first`, `slacky_sentinel_alerts`; `bin/slacky-update`: call before `started-packages` in `run_full_update`, alerts after `--check`; `lib/check_backend.sh`: detached `keys-check` at the end of each check (user only). `lib/slacky_mirrors.py`: localized all-failed sentence.
- Files touched: `lib/slacky_sentinel.py`, `lib/gnomes_trust.py`, `lib/slacky_mirrors.py`, `lib/mod_packages.sh`, `lib/check_backend.sh`, `bin/slacky-update`, `locales/en.json`, `locales/nb.json`, `docs/log.md`, `docs/log_nb.md`, `claude_log.md`. (Please commit these; not committed here.)
- Verification: `bash -n` on all changed scripts, `python3 -I -m py_compile` on the changed Python (no `__pycache__` left from this work), `gnomes_trust.py selftest` (113), the three offline suites (67 + 111 + 41 checks) in temp dirs with local HTTP servers, throwaway gpg keys, fake HOME and fake key store. Not verified: a real full update with sudo (the root-ownership checks of the key store ran as the test user), real databases, the tray and the TUI (they do not show the sentences yet; `--check` does).
- Known limits: the expiry radar judges only keys in a key-store generation (not the shipped floor) and needs packages to have been verified since this change; CachyOS lag uses the database size and date only; Slackware mirror lag and the "Slackware server is N days behind" sentence are not implemented here. Rust-side findings for the coordinator: (1) `locales/nb.json` `KEYS_REFUSED_CHECKS` typo "beståtte" (should be "bestod"); (2) the expiry radar / alert texts of Rust MS7 should use the same condition keys and once-per-7-days rule; (3) the Rust `KeyringManager::sync_with` has no database-first freshness check yet (it downloads from the index each time).

### 2026-10-15 Build 86_slacky (no bump) - 6A-210 / 6A-211 / 6A-212 / 6A-213 - mirror and signed-list fixes found by the Rust work (Rust: 6A-212 mirrored in `mirror_sentinel/lists.rs`)
- User-visible: three Chaotic servers that no longer exist (`bg-`, `es-`, `us-ut-`) are gone from the built-in list, so fewer wasted tries. A signed Arch list can now be up to 1024 server lines (Arch ships 424 today). The Arch server list only adds a server that the Arch status page also vouches for (or that is built in), as in the Rust app.
- Technical: `lib/slacky_mirrors.py` (210). `lib/slacky_sentinel.py`: `vet_offered` and `reapply_offered` (211: Arch ships every line commented out, so the list is an allow-list; vouched hosts best score first, then built-in hosts, a stale status page vouches for nobody; the stored list is vetted again when the status page changes, no new download), `MAX_ENTRIES` 1024 and a 128 KiB list-file cap, more than 1024 lines now refuses the whole list (212, also in `docs/mirror_key_spec.md`, copied identical from the Rust repo). `lib/gnomes_trust.py` `RING_CACHE_DIR`: the evaluated Arch ring (about 1.0 s of gpg work) is kept in the sentinel's own user cache keyed by the sha256 of the ring file and of the compiled pins, with a checksum sidecar, only when the sentinel opts in and never for root (213). The check already starts the sentinel detached in the background.
- Files touched: `lib/slacky_mirrors.py`, `lib/slacky_sentinel.py`, `lib/gnomes_trust.py`, `docs/mirror_key_spec.md`, `docs/log.md`, `docs/log_nb.md`, `claude_log.md`. (Please commit; nothing was committed here.)
- Verification: `bash -n`, py_compile through `ast.parse` (no `__pycache__`), an offline test in a temp dir with a fake HOME: 800/1024 lines accepted, 1025 refused, allow-list cases (no status page, vouched, stale, stranger), reapply from the stored list, dead hosts gone, ring cache first build 1.03 s then 0.003 s, a tampered cache file is rebuilt. NOT verified: a real weekly run against the Arch servers and a real signed `pacman-mirrorlist`.
- Known limits: the ring cache protects nothing the user could not already change in their own cache, so it is used only where the result is a hint or is checked again by root (mirror lists, staged keyrings); the package gate of a full update still builds the ring in memory.

### 2026-10-15 Build 86_slacky (no bump) - 6A-220 / 6A-221 - key flow aligned with Rust MS8, plain wording for keys and mirrors
- User-visible: the key sentences now say "security keys", "runs out on", "confirmed as genuine", "the checking program (gpg)", and the mirror switch sentences say "download server" / "server list", the same words as the Rust app (en and nb). The expiry notice no longer fires for a key that already ran out, and it also looks at the keys shipped with the program when no key generation is installed yet.
- Technical: `lib/gnomes_trust.py` `MESSAGES`/`Refusal.sentence`, `lib/slacky_sentinel.py` default text, `lib/rank_mirrors.py` (`_t`, keys `G13_MIRROR_*` read through the sentinel's loader), `locales/en.json`, `locales/nb.json`. `expiry_radar` now judges the same key set as the Rust spec section 7 (compiled anchors and floor pins, extra masters of the generation, the generation's signer) and only a FUTURE expiry within 60 days. Checked equal to Rust and left alone: download only when the database lists a newer version, a refused version is skipped for 7 days, 60-day warning, once per 7 days per family.
- Files touched: `lib/gnomes_trust.py`, `lib/slacky_sentinel.py`, `lib/rank_mirrors.py`, `locales/en.json`, `locales/nb.json`, `claude_log.md`, `docs/log.md`, `docs/log_nb.md`.
- Verification: same offline test (radar returns 0 or a future time, year 2100 gives 0, sentence text), json loads for both locales. NOT verified: the sentence in the 22 other languages (they keep their own older wording until translated), a real expiring key.
- Known limits: the other 22 locale files still carry the old `GNOMES_TRUST_*` wording.

### 2026-10-15 Build 86_slacky (no bump) - 6A-230 / 6A-231 / 6A-232 / 6A-233 - launcher cleanup no longer guesses (Rust: 233 fixed in `build/protected.rs`)
- User-visible: `gnomes` cleanup no longer recreates `/usr/bin/python`, `python3` or `python3-config` (they belong to the Slackware python package), no longer mistakes `underpants-foo-bar` for `underpants-foo`, and never deletes a launcher that sits on a protected system name: it says so in one sentence and leaves the decision to the person. `Python3`, `HYPRLAND` and `xwayland` count as protected like their normal spelling everywhere.
- Technical: `bin/gnomes` `pkg_name_installed` (cut the last three dash fields, compare the rest), `gnomes_app_package_installed` (same variants as the Rust app: `-bin`, `-git`, canonical name, `cachyos-gnome-`), `advise_protected_wrapper`; three `ln -sf` blocks removed. `lib/gnomes_pacman.py` `is_protected_host_binary` (one lower-case rule used by the audit and all four write paths), `heal_host_sovereignty` gains `kept_protected` and no longer `os.remove`s a protected-name launcher with no stock owner; `lib/mod_packages.sh` prints the sentence; locale key `GNOMES_WRAPPER_PROTECTED` (en, nb).
- Files touched: `bin/gnomes`, `lib/gnomes_pacman.py`, `lib/mod_packages.sh`, `locales/en.json`, `locales/nb.json`, `claude_log.md`, `docs/log.md`, `docs/log_nb.md`.
- Verification: `bash -n`, py_compile, a fake package folder for the name matching (foo vs foo-bar, -bin variant, cachyos-gnome-), no `ln -sf` left in `cleanup_stale_wrappers`, `heal_host_sovereignty(dry_run=True)` read-only run as a user. NOT verified: a real root cleanup on the machine.
- Known limits: the orphan-folder prune in `gnomes_pacman.py` (`/opt/underpants/pkgs/<app>`) still uses a prefix match on purpose: a false match there only keeps a folder. The second loop of `cleanup_stale_wrappers` has no protected-name list in bash; it relies on the stock-owner check.

### 2026-10-16 Build 87_slacky (pending) - 6A-241 - gnomes -Qu read a stale system cache
- User-visible: `gnomes -Qu` (and so the Rust app, which asks it) showed no gnomes updates although the legacy check found claude-desktop 2.42304.0-1.
- Cause: `list-updates --no-sync` always preferred `/var/cache/slacky-update/gnomes/db` when it held any database, even when the user's own cache was days newer (system cache from 2026-10-13, user cache 2026-10-16).
- Fix: `lib/gnomes_pacman.py`: the system cache is used only when its newest database is at least as new as the user's (the same "newest wins" rule as the status files).
- Verification: from the working tree, `list-updates --no-sync --json` now lists claude-desktop; ast parse clean. Rust mirror: the Rust pipeline asks `gnomes -Qu`, so it is fixed by this; the native engine is not used by the pipeline yet.

### 2026-10-16 Build 87_slacky (pending) - 6A-245 - no more pointless initramfs rebuilds (Rust mirror: not affected, booked steps, no mtime rule)
- User-visible: the full update no longer rebuilds startup images whose content is already correct (~2 minutes saved per run). Before, Secure Boot signing made `vmlinuz` newer than the image, so the next run rebuilt it for nothing.
- Technical: `lib/mod_kernel.sh` new `initramfs_inputs_fingerprint`, `initramfs_record_check/write`, `initramfs_is_stale`, `record_initramfs_inputs_all`. One record per kernel in `/var/lib/slacky-boot/initramfs-inputs/<kver>` (root 0644, temp+rename, refused through links): sha256 of vmlinuz, of every extramodules/updates/nvidia module, hash of /etc/dracut.conf(.d), size+mtime of the image. `bin/slacky-update` writes the records right after step [4/5] (signed kernel), never for a kernel whose image failed or that is being removed. Rebuild when: no image, SpiderSense order, record differs (kernel, any module, dracut config, replaced image). Only with no record at all the old mtime rule is used, then the record is written. kernel-headers was already not counted (6A-61); kernel-firmware still reaches the hardening stage but decides nothing to rebuild: images keep their old firmware until a real rebuild (note for the owner).
- Files touched: `lib/mod_kernel.sh`, `bin/slacky-update`, `claude_log.md`, `docs/log.md`, `docs/log_nb.md`.
- Verification: `bash -n`; offline fake root (stub sudo, real sha256sum): record written; re-signed vmlinuz only -> current; changed module / kernel / dracut conf / replaced or missing image -> stale; several kernels with a new driver on two of them -> exactly those two; new kernel without image -> stale; SpiderSense order -> stale; failed/ALL set -> no record; links in record path or dir refused. Hashing cost: 25 MB (20 MB kernel + modules) about 0.05 s per kernel. NOT verified: a real full update on the machine.
- Known limits: the mkinitrd (non-dracut) path keeps its own rule; a failed signing records the unsigned kernel, causing one extra rebuild after the retry.

### 2026-10-16 Build 87_slacky (pending) - 6A-244 - a mirror with only IPv6 addresses no longer stops gnomes downloads on a machine without IPv6 (Rust mirror: 6A-244)
- User-visible: `gnomes -S virtiofsd` (CachyOS extra) failed when `mirror.cachyos.org` answered with IPv6 addresses only and the machine has no IPv6 route ("Network is unreachable"). Now the payload is also tried on the other ranked hosts of its family (cdn77.cachyos.org, us.cachyos.org; Arch and Chaotic the same), and an unreachable IPv6 address is retried over IPv4 first. Silent.
- Technical: new `lib/slacky_net.py` (`open_url`: on ENETUNREACH / EHOSTUNREACH / EADDRNOTAVAIL retry once with an IPv4-only opener, resolve with AF_INET; no A record = the original error at once; the host is remembered for the process). Used by `gnomes_pacman.py` (`url_open`: db sync, both payload passes, recovery), `gnomes_trust.py` (signature fetch), `slacky_sentinel.py` (`http_get`), `slacky_vendor_fetch.py`, and the new check module. `gnomes_pacman.py` `get_download_urls_candidates` now ends in `_with_mirror_hosts`: first candidate on every ranked host (`slacky_mirrors.alternatives`), then the existing tier/folder fall-backs unchanged, then the other hosts for those; at most 16 URLs. The chaotic `.sig` fetch tries the first four candidates in order. Every check (size, SHA256, magic bytes, signature) is unchanged and runs on whatever host answered. `curl` calls were checked: none forces IPv6 (curl does happy eyeballs itself).
- Files touched: `lib/slacky_net.py` (new), `lib/gnomes_pacman.py`, `lib/gnomes_trust.py`, `lib/slacky_sentinel.py`, `lib/slacky_vendor_fetch.py`, `slackbuild/slacky-update.SlackBuild` (install lines).
- Verification: offline tests (deleted after green, fake HOME, local HTTP server, patched `create_connection` / `getaddrinfo`): IPv6-only host served over IPv4, second call goes straight to IPv4, no-A-record host fails at once and is remembered, HTTP 404 is passed on, candidates include cdn77/us/rackspace and keep all old fall-backs (max 16, unknown host unchanged). `ast` parse clean. NOT verified: a real AAAA-only host and a full `gnomes -S` build (needs the owner's machine and sudo).
- Known limits: `rank_mirrors.py` and the Chaotic probe in `slacky_mirrors.py` still use plain urllib (a failed probe just ranks the host last); the SBo ChangeLog fetch inside `check_backend.sh` is unchanged (GitHub has IPv4).

### 2026-10-16 Build 87_slacky (pending) - 6A-243 - the check lists multilib (slackpkg+) updates and slackpkg install-new packages (Rust mirror: 6A-243)
- User-visible: `slacky-update --check` and the tray now show multilib / compat32 updates and packages newly ADDED to Slackware (for example `libgit2`) that the check never listed before, because both came from slackpkg's `pkglist`, which only a root `slackpkg update` refreshes. New category "New Slackware Packages"; they count in the totals and in the number of Slackware packages of the update flow. Silent when nothing is pending, no sudo.
- Technical: new `lib/slacky_slackpkg_check.py`, called by `lib/check_backend.sh` (`plus` and `new`). slackpkg+ repos from `slackpkgplus.conf`; `CHECKSUMS.md5` conditional (ETag / Last-Modified) into `~/.cache/slacky-update/slackpkgplus/<repo>/`; `CHECKSUMS.md5.asc` verified with `gpgv` against `/var/lib/slackpkg/gpg/GPG-KEY-<repo>.gpg` in a throw-away GnuPG home: verified -> listed, BAD -> repo dropped, no signature/key/gpgv -> listed as a hint, repo in the new status key `slackpkgplus_unverified`. `/etc/slackpkg/blacklist` honoured like slackpkg. install-new: ChangeLog sections newer than the installed state (newest of the last 50 whose entries for installed, not blacklisted packages are all installed), Added/Split/Renamed/Moved/Name change/Switched, not installed, not removed, not testing/pasture/extra/source -> new status key `slackware_new_packages` (recomputed each check, never carried forward). Consumers updated: `bin/slacky-update` (list, total, slack package count), tray (total, list), TUI category, `common.sh` (reconcile clears it), `slacky_heal.py`; locale key `CAT_SLACKWARE_NEW` (en, nb).
- Files touched: `lib/slacky_slackpkg_check.py` (new), `lib/check_backend.sh`, `bin/slacky-update`, `lib/slacky-update-tray`, `lib/slacky_tui.py`, `lib/common.sh`, `lib/slacky_heal.py`, `locales/en.json`, `locales/nb.json`, `slackbuild/slacky-update.SlackBuild`.
- Verification: `bash -n`, `ast` parse. Offline tests (deleted after green): install-new window and rules, blacklist, comparison, conditional 304 + cached list, hint without signature, throwaway gpg key verified and BAD. One real run of `check_backend.sh` in a private fake HOME against the real repos: 0 multilib, 0 install-new, 0 unverified (both repos verified; nothing pending). Real repos with a fixture of yesterday's installed set (attr-compat32 and compat32-tools older, no libgit2): found `attr-compat32-2.6.0-x86_64-2compat32.txz`, `compat32-tools-3.10-noarch-19alien.tgz` and `l/libgit2-1.9.7-x86_64-1.txz`.
- Known limits: PKGS_PRIORITY / TAG_PRIORITY / GREYLIST not evaluated; `dir://` / `file://` repos not read; a package added in a section older than the installed state is not listed again; with no ChangeLog section showing the installed state nothing is listed; the `slackpkgplus_updates` list still merges the previous run's not-installed entries (existing rule).

### 2026-10-16 Build 87_slacky (pending) - 6A-246 - no emoji in gnomes and curated deploy output (Rust mirror: 6A-246)
- User-visible: the gnomes command line (`bin/gnomes`), the transmutation engine (`lib/gnomes_pacman.py`) and the curated deploy (`lib/mod_gaming.sh`) no longer print emoji or decorative pictographs. The humour stays in words: `Step 1: Steal Underpants  ->  Step 2: ? ? ? ?  ->  Step 3: PROFIT!`, `PROFIT! ...`, the compress animation is `underpants . . gnome`, warnings start with `Warning:` / `STOP:`, check marks are gone (`[OK]` in the AAC bridge status), the hardlink line says `[link]`. Colours are unchanged.
- Technical: text-only replacements in output strings; no logic, message meaning or exit code changed. The slack-desc line of curated packages is now `Step 3: PROFIT!!!`. The key-hint line in the curated menu says `[Up/Down]`.
- Files touched: `bin/gnomes`, `lib/gnomes_pacman.py`, `lib/mod_gaming.sh`.
- Verification: `bash -n bin/gnomes lib/mod_gaming.sh`, `compile()` of `lib/gnomes_pacman.py` clean (no `__pycache__` created); a code point scan (U+1F000-1FFFF, U+2600-27BF, U+2B00-2BFF, U+2190-21FF, U+FE0F, U+200D, check marks) finds 0 lines in the three files. Not run against the real system.
- Known limits: other legacy files (`lib/common.sh`, TUI, doctor) were not part of this task; the colour palette is untouched by design.

### 2026-10-16 Build 90_slacky (pending) - 6A-266 - Chaotic-AUR epoch packages were missed by the curated check
- User-visible: a newer curated program on Chaotic-AUR whose package name carries an epoch (Brave `brave-bin-1:1.97.59-1`) is now offered as an update, like the Rust app already does.
- Technical: epoch groups in the catalog and source patterns accept `%3A` or `:`; every `href=` pattern accepts an optional `./` prefix (Chaotic's index writes `href="./name..."`). Optional groups only; the captured file name is unchanged.
- Files touched: `lib/mod_gaming.sh`.
- Verification: `bash -n`; the new patterns run against the cached Chaotic and CachyOS indexes find Brave 1.97.59 (Chaotic), 1.97.57 (CachyOS) and Edge 155.0.4283.60. Not run end to end on the real system.
- Known limits: 438 pattern lines got the optional `./`; only Chaotic-sourced entries are affected in practice.

### 2026-10-17 Build 90_slacky (pending) - 6A-267 - restart advice only when something in use changed (bin/slacky-update)
- User-visible: after updating a kernel that is not the running one (zen while bore runs) plus ordinary packages, the update no longer says "System reboot recommended" without a reason. The advice now needs a concrete reason: the running kernel's flavor got a newer version, its `/lib/modules` folder is gone, a Slackware kernel package of the running release was replaced or removed, or NVIDIA, glibc (not zoneinfo), Mesa or the desktop changed. Rust mirror: G5-21.
- Technical: the boot chain flag `kernel_or_driver_changed` still runs the boot chain but no longer forces the advice (`force_flag` is ignored). The decision moved from an inline heredoc into `slacky_reboot_reasons` (testable; `SLACKY_RUNNING_RELEASE` overrides `uname -r`). `get_full_pkg_snapshot_file` appends `MOD:<release>` lines for `/lib/modules`. Rules: `docs/reboot_rules.md`.
- Files touched: `bin/slacky-update`, `docs/reboot_rules.md`, `claude_log.md`, `docs/log.md`, `docs/log_nb.md`. No BUILD bump (collects for Build 90). No new locale keys (`REBOOT_RECOMMENDED_DESC` is now unreachable but kept).
- Verification: `bash -n`; a temporary script ran the function against fake snapshot files (16 cases: owner's zen case, new flavor, older version, rc, boot tooling, zoneinfo, bore updated, modules gone, Slackware kernel replaced/removed/other version/headers, nvidia, glibc, mesa, desktop); all passed and the script was deleted. NOT verified: a real full update.
- Known limits: a plain first run after upgrading to this build has no MOD lines in the before snapshot only if the snapshot was made by an older process (cannot happen within one run).

### 2026-10-17 Build 90_slacky (pending) - 6A-268 - the file check no longer flags scratch folders and says what it found (lib/slacky_heal.py)
- User-visible: the file check no longer reports packages as damaged because of scratch paths they list (for example `var/lib/rpm/tmp/Packages`). For a package that is not an official Slackware one, the message now says how many files are missing and gives one example: `<pkg> is missing N of its files (for example /path); it is not an official Slackware package, so rebuild or reinstall it with the tool you used to install it.` Rust mirror: the Rust app already skipped `/tmp/` paths; its wording was aligned in Rust commit 5e969f1.
- Technical: `audit_one` skips entries containing `/tmp/`; `report` builds the non-official sentence with the damaged count and example.
- Files touched: `lib/slacky_heal.py`, `claude_log.md`, `docs/log.md`, `docs/log_nb.md`.
- Verification: `compile()` clean. Not run against the real system.
- Known limits: any package path that legitimately contains `/tmp/` is no longer checked (same as Rust).

### 2026-10-17 Build 90_slacky (pending) - 6A-269 - packages built under a strict umask no longer carry private folder modes
- User-visible: a package built while the builder's umask is 077 (or similar) used to carry `usr/` and `usr/bin/` as 0700 and files as 0600/0700, and `installpkg` would apply that to the host's `/usr` and `/usr/bin` (normal users could no longer run programs). Every package we build now has world-readable modes (folders 0755, files 0644 or 0755) whatever the umask. Rust mirror: commit a3b099c `normalize_modes`.
- Technical: the archive step of every builder now passes `--mode='go+rX'` to `tar`: group and others gain read, and execute only on folders and on files the owner can already execute. Setuid/setgid/sticky bits and existing permissions are kept (nothing is removed), symlinks are untouched. Chosen over a `os.umask(0o022)` or a chmod pass on the staging tree because the fix then lives in the one place that decides what is installed (the archive), does not depend on how the files got into staging, and never changes files in the staging tree (which may hardlink to cached runtime files); a umask would not repair modes that tar had already masked during extraction.
- Files touched: `lib/gnomes_pacman.py` (`_run_makepkg_with_progress`, used by app transmute and the runtime builder), `lib/mod_gaming.sh` (curated packager), `lib/mod_rocm.sh`, `lib/mod_nvidia.sh`.
- Verification: a temporary script built a tree under `umask 077` (0700 folders, a 0600 file, a 0700 and a 4700 program, a 1700 folder, a symlink) and packed it with the exact pipeline; modes in the archive were 0755, 0644, 0755, 4755 (setuid kept), 1755 (sticky kept), symlink unchanged; the script was deleted. `bash -n` on the three shell files, `compile()` of the Python file. Not run against the real system.
- Known limits: a file that was deliberately private (0600) in an upstream package becomes world-readable; nothing we ship installs secrets, and the previous behaviour (host folders at 0700) was worse. The tar step of `rollback` (re-packing installed files) copies real modes and is unchanged.

### 2026-10-17 Build 90_slacky (pending) - 6A-270 - CachyOS package lists are fetched as the signed `.db` file
- User-visible: the CachyOS package lists no longer lag behind the mirror (the unsigned `<repo>.db.tar.zst` was found hours older than the signed `<repo>.db`, with older versions such as davinci-resolve 21.1.0 instead of 21.1.1). Rust mirror: commit 859ad1f.
- Technical: the 13 CachyOS repo URLs in `get_default_repositories` end in `.db`; `sync_repositories` still stores them as `<repo>.db.tar.zst` so the cache layout, the parser and the other readers are unchanged. Arch (`.db.tar.gz`) is untouched. No other legacy code fetches CachyOS databases.
- Files touched: `lib/gnomes_pacman.py`.
- Verification: read-only fetch of `cachyos-extra-znver4.db` into a temp dir (zstd magic, 7418 packages parsed by `PacmanDBParser.parse_archive`); `gpgv` with `keys/cachyos.gpg` and the mirror's `.db.sig` reported Good signature from CachyOS. Temp dir removed. The download itself was not run through `sync_repositories`.
- Known limits: no signature gate is added (none existed); Arch and Chaotic publish no `.db.sig`.

### 2026-10-17 Build 90_slacky (pending) - 6A-271 - no boot hook for a service script the Footprint Guard dropped
- User-visible: when the guard removes the start script of a dependency's background service, the package no longer adds a line to `rc.local` that calls a script that does not exist. For each dropped service one sentence is printed: `<app> has a background service (<svc>) that does not start by itself; to start it by hand, run: <command>`. Rust mirror: commit 1dda156 (GAP-3).
- Technical: `transmute` runs `footprint_guard` right after `_transmute_systemd_services` (the pack-time run then finds nothing more), keeps only services whose `etc/rc.d/rc.<svc>` still exists for `doinst.sh` and `douninst.sh`; the command comes from the unit's ExecStart (recorded in `_service_cmds`). Locale key `GNOMES_SERVICE_NOT_SET_UP` added to en/nb (the Python prints English like its other messages).
- Files touched: `lib/gnomes_pacman.py`, `locales/en.json`, `locales/nb.json`.
- Verification: temp staging tree with two fake units: service conversion recorded both commands, the guard dropped both scripts, `etc/rc.d` ended empty. The inline keep/skip step in `transmute` was not exercised end to end (needs a full app build); `compile()` and JSON load clean.
- Known limits: the guard message also appears at this earlier point; services the guard keeps (own daemons) are hooked as before.

### 2026-10-17 Build 90_slacky (pending) - 6A-272 / 6A-273 - restart question defaults to no; one patchelf warning per app
- User-visible: the restart question reads `[y/N] (Enter = no)` in all languages, so an accidental Enter never closes work. When patchelf is missing or fails, one plain line names the app and says it usually still starts (the launcher sets the library path); nothing is refused.
- Files touched: `bin/slacky-update`, `lib/gnomes_pacman.py`, `locales/*.json`, `docs/log.md`, `docs/log_nb.md`.
- Verification: bash -n, python -I compile, JSON load of all locales, fake-patchelf test (deleted). Not run in a full update.
- Known limits: Rust mirror of 6A-272 pending Build 80; Rust refuses on patchelf failure (intended difference).

### 2026-10-17 Build 90_slacky (pending) - 6A-274 - standalone `spidersense` command
- User-visible: `spidersense` (status, heal-check, hardware, snapshots, prune-plan, log*) works on legacy code alone; it no longer execs the Rust binary. Mentioned in `slacky-update --help`; installed as `/usr/bin/spidersense` by the SlackBuild unless another package owns the path.
- Files: `bin/spidersense` (untracked, new), `bin/slacky-update`, `slackbuild/slacky-update.SlackBuild`, `docs/log.md`, `docs/log_nb.md`, `claude_log.md`.
- Verification: `bash -n`; each subcommand run with fake HOME/XDG_CACHE_HOME/SLACKY_SYSFS_ROOT/--root; grep shows no Rust path or name. Not verified: SlackBuild install branch (not built).
- Limits: no live `--watch`; snapshot deletion stays with the hourly job. Rust mirror: none needed.

### 2026-10-17 Build 90_slacky (pending) - 6A-276 / 6A-277 - package signatures: refreshed keys, one family per source, missing .sig always refuses
- User-visible: kernel, NVIDIA, gaming and ROCm packages are now checked against the refreshed key store (`/opt/underpants/keys/<family>/current`, shipped ring only as floor), only with keys of the family the download address belongs to (Arch, CachyOS, Chaotic); revoked and expired keys are refused. An unknown or expired key first triggers one key refresh (`slacky_keys_first`) and one retry, then a true sentence ("the next key refresh fixes this") replaces "corrupt package". ROCm now refuses a part without `.sig`. The Pascal 580xx DKMS archive in `mod_kernel.sh` is signature-checked before it is unpacked as root, and tar's exit code is checked (M9).
- Technical: `verify_cachyos_gpg_signature PAYLOAD SIG SOURCE_URL [SHA256]` calls `gnomes_trust.py verify` (gpgv status parsing); new `slacky_sig_family`, `slacky_signed_repo_url` (host-based, replaces the url regexes in `mod_gaming.sh`).
- Files: `lib/common.sh`, `lib/mod_kernel.sh`, `lib/mod_nvidia.sh`, `lib/mod_gaming.sh`, `lib/mod_rocm.sh`, `docs/log.md`, `docs/log_nb.md`, `claude_log.md`.
- Verification: temp GNUPGHOME and fake key store: good (CachyOS, Arch), wrong family, tampered, revoked, expired, unknown key (refresh once, then refusal; refresh that installs the key then passes), missing sig, unknown host, sha mismatch: 14/14. `bash -n` on all files. Not verified: real downloads on the machine; the optional repo-db SHA256 argument is supported but no caller has the value yet.
- Limits: `SLACKY_KEYS_ROOT` is honoured only with `SLACKY_SELFTEST=1`. Rust mirror: Rust already verifies with the key store; no change needed.

### 2026-10-17 Build 90_slacky - 6A-275 (Rust mirror: gnomes trust default) - gnomes signature checks now enforce by default
- User-visible: Underpants Gnomes (`gnomes -S`, updates) now refuse a package whose signature is bad, missing, from a revoked or run-out key, from the wrong repository family, or whose download does not match the checksum in the package list; the build stops with one plain sentence and "Nothing was built or installed." Before, these checks only wrote to a log. If the keys are only too old (new publisher key, key run out), the program first refreshes the signed keyring once and retries once, and only then refuses with a sentence that names the fix ("a full update (slacky-update) renews the keys"). The old claim "held back" is now said only when it is true.
- Emergency override: `SLACKY_GNOMES_TRUST=log` (documented in `gnomes --help`) installs anyway, only logs, and prints one line saying so.
- Technical: `trust_mode()` defaults to enforce (unknown values fail closed to enforce). New status "expired" (run-out signing key; detail records whether it had already run out when signed); `check_sha256` (repo-db %SHA256SUM% cross-check, as in the Rust app); `settle_stale` + `refresh_family_keys` (calls the existing `slacky_sentinel.keys_check` once per family and process, then retries against the keys in force plus the staged keyring, whose raw bytes go through all keyring rules again; `REFRESH_HOOK` for tests); `Refusal.sentence(family, mode)`; `.sig` fetch gets one extra round for a transient network failure.
- Files: `lib/gnomes_trust.py`, `lib/gnomes_pacman.py` (`trust_gate`), `bin/gnomes` (help text), `locales/en.json`, `locales/nb.json` (new keys GNOMES_TRUST_EXPIRED, _NOKEY_REFRESHED, _SHA_BAD, _HELD_FAMILY, _LOG_OVERRIDE; _KEYS_REFUSED_CHAIN reworded).
- Verification: temp dirs, temp GNUPGHOME, generated keys, fake key store: good (Arch, CachyOS), tampered, revoked list, real revocation certificate, run-out key, wrong family both ways, unsigned, missing keyring (refresh once, then refusal), refresh that installs the key (retry passes), bad/unsigned never trigger a refresh, log mode neither refreshes nor blocks, checksum mismatch, `trust_gate` with a good app (passes silently), bad, unsigned, checksum mismatch and log override; module selftest 113/113. 36/36 checks green; test file deleted. NOT verified: the real network refresh (`keys_check` downloads) and a full real `gnomes -S` install (build-only path was not run; only the gate in front of it).
- Limits/follow-ups: a key that only expired AFTER the package was signed is still refused until the keyring renews its expiry (same as pacman and the Rust app). The refresh needs a normal user (it stages in the user's cache); as root the retry just runs against the keys in force. Rust mirror: `src/gnomes/trust.rs` keeps "held back" wording in `keys_refused_chain`; align it (enforce-only) and the new sentences.

### 2026-10-17 Build 90_slacky - 6A-278 / 6A-279 / 6A-280 / 6A-281 - keys refresh in every mode, used-key expiry warning, honest self-update, honest exit code
- User-visible: (278) Security keys are now refreshed by the user check, by `sudo slacky-update` and by the root cron check, with or without Underpants Gnomes; at most once a day (6 hours after a failure). A normal user stages a verified keyring, root installs it at once as a new key generation. The signed mirror-list refresh also runs as root now. (279) One plain sentence (once per 7 days, in `slacky-update --check`) when a key that really signed packages in the last 90 days runs out within 30 days and no refreshed key generation extends it; it is logged as `key.expiry_soon`. (280) The self-update check says "Could not check for a new version (why)" when GitHub cannot be reached, answers with an error or a limit; no more false "up to date". 1.0_RC2 is now older than 1.0, 1.0 equals 1.0.0, 1.0.1 and 1.1 are newer. No emoji banner, no "Pre-Release / Early Access" wording. (281) After a failed or waiting step (also Slackware core return codes 1, 2, 3) the "completed successfully" line is not printed and the exit code is 20 (documented in `--help` and the spec).
- Technical: `slacky_sentinel.sentinel_dir()` returns `/var/cache/slacky-update/sentinel` for root (root-owned files only). New stable entry point `python3 -I lib/slacky_sentinel.py refresh-keys [--force] [--json]` / `refresh_keys()`; exit codes 0 current, 10 installed (root), 11 staged (user), 20 refused, 21 network, 22 skipped (rate limit), 23 busy, 24 unavailable. Without a gnomes database the small repository database is fetched as a hint only (the package is still fully verified). `used_signer_expiry()` reads `used_signers.json`.
- Files: `lib/slacky_sentinel.py`, `lib/check_backend.sh`, `lib/mod_packages.sh`, `lib/common.sh` (self-update only), `bin/slacky-update`, `lib/slacky_tui.py` (banner), `locales/en.json`, `locales/nb.json` (SELF_UPDATE_*), `docs/spidersense_spec.md` (exit 20), logs.
- Verification: fake trust module, fake HTTP, temp dirs: 22 key checks green (user stage, root install, rate limit, force, 6-hour retry, refusal, current, used-key radar, alert once per 7 days, silent after extension); self-update with stubbed curl: 9 version pairs, offline, rate limit, HTML answer; `prompt_reboot_or_close` exit codes 0/20. `bash -n`, py compile. NOT verified: real network refresh, real root install into /opt/underpants/keys, the cron job run as root.
- Limits: the tray status does not show the key sentence yet (check output only). A key that already expired is not warned about by the used-key radar.

### 2026-10-17 Build 90_slacky - 6A-282 / 6A-283 (6A-159) / 6A-284 (6A-160) / 6A-285 (6A-161) / 6A-286 (6A-240) - boot menu and backup hardening
- User-visible: a CachyOS kernel whose own startup image is missing or too old is left out of the boot menu (one sentence) instead of getting a wrong image; the boot loader backup lives only in a root-owned folder and restore refuses an unsafe source; snapshot entries only offer kernels the snapshot really contains; purged kernels leave the Secure Boot list.
- Files: `lib/mod_limine.sh` only (new helpers `limine_snapshot_has_modules`, `limine_backup_source_trusted`, `sbctl_forget_missing_files`, `limine_standalone_boot_sync`).
- Verification: 13 fake-root checks green (initrd choice and age, trust check, snapshot symlink, sbctl remove-file), tests deleted. NOT verified: real ESP, real restore as root, real sbctl.
- Limits: `limine_standalone_boot_sync` is not yet called from `lib/mod_gaming.sh` (~7928-7944, owned by another agent). The old `~/.limine_backup` is left in place but never used.

### 2026-10-17 Build 90_slacky - 6A-291 / 6A-292 / 6A-293 / 6A-294 (M12, M11, M4, S3) - gnomes: one rc.local block, guarded rollback, run lock, visible errors
- gnomes no longer piles up boot-hook blocks (exact-line match, old duplicates collapsed to one); a rollback no longer puts back Slackware-owned or system-wide files; gnomes install/remove/rollback wait for (or refuse beside) a running update; rollback errors are shown again.
- Files: `lib/gnomes_pacman.py` (`gnomes_rc_hook_snippet`, `build_from_snapshot`), `bin/gnomes` (`gnomes_pkgtools_lock`, rollback lock open).
- Verification: 13 fake-root/temp-dir checks green (hook twice and with 3 old duplicates, repack drops global + Slackware-owned files and leaves the snapshot alone, lock free/inherited/held-by-other waits 15 s and refuses, stderr kept); tests deleted. NOT verified: real install, rollback, snapper.
- Follow-up: the Rust app mirrors M4 by spec; carry M11/M12 into the Rust workdoc.

### 2026-10-17 Build 90_slacky - 6A-287 / 6A-288 / 6A-289 / 6A-290 (Rust mirror: robustness audit M8, S4, M10, S2) - NVIDIA package database untouched, NVIDIA footprint guard, safe curated uninstall, isolated root Python
- User-visible: (287) If an older NVIDIA driver package (SBo `nvidia-driver`, `nvidia-kernel`, `nvidia-utils`, `x11-nvidia-driver`) is installed, the NVIDIA update stops before building with one sentence naming the `sudo removepkg` command; our code no longer moves anything in `/var/log/packages` or `/var/log/scripts`. (288) The NVIDIA userspace package now goes through the Footprint Guard like every other package (staging tree, root-owned archive, no overwrite of another package's files). (289) Uninstalling a curated package no longer rewrites `rc.local` from Python (it could delete the begin marker of a block and make every later rc.local change refuse); the package's own `douninst.sh` removes exactly its marked block. (290) Root Python calls (`sudo python3 -c` and `-`) now run with `-I`, so a file in the current directory cannot be imported as root.
- Files: `lib/mod_nvidia.sh` (new `nvidia_legacy_pkg_check`, guard before packing, archive checks before the root step), `lib/mod_gaming.sh` (Python rc.local block removed), `lib/mod_limine.sh` (10 tokens), `lib/mod_kernel.sh` (4), `lib/mod_armor.sh` (3), `lib/mod_secureboot.sh` (1).
- Verification: fake roots/temp dirs, 14 checks green (scratch rc.local with three blocks: only the target block removed, other markers and bodies kept, balanced, idempotent; fake package database with SBo and clean cases, database unchanged, no false hit on `nvidia-driver-extra` or `cachyos-nvidia-utils`; footprint guard on a fake NVIDIA staging tree keeps the vetted `nvidia-vaapi.sh`, drops unvetted profile.d / ld.so.conf.d files and Slackware-owned files); `bash -n` on all touched files. NOT verified: a real NVIDIA build/install, real `removepkg` with the douninst.sh run.
- Limits: no new vetted paths were needed; if a future NVIDIA payload ships an unvetted global file, the guard drops it (see `FOOTPRINT_VETTED`). Not changed (script-path calls, other owners): `sudo python3 <script>` in `lib/mod_docs.sh` (2), `bin/slacky-update` (3, doctor), `bin/gnomes` (2, purge-service), `lib/mod_clean.sh` (2). All run self-contained scripts; add `-I` there as well. Rust mirror: check the Rust NVIDIA path never moves package records.

### 2026-10-17 Build 90_slacky - 6A-302..305 (F0b, F0c, GRUB, snapshot mirror) - exact NVIDIA module match, fail-closed Secure Boot check, no more edits to Slackware's grub files, safer snapshot pruning
- 6A-302 (F0b): the precompiled NVIDIA module package must now match the kernel release exactly (7.2.1 no longer matches a 7.2.10 module). After install, success is reported only when an `nvidia.ko*` exists for that kernel and `modinfo -k` shows the expected version (also for the DKMS bridge). Otherwise one sentence is printed, no initramfs is ordered, and the kernel goes on a hold list (`/var/lib/slacky-boot/nvidia-hold`); the Limine menu leaves held kernels out while their module is still missing (never the last kernel), and a later good run clears the hold.
- 6A-303 (F0c): `limine_efi_signature_ok` now fails (one sentence, nothing written) when sbctl keys are set up or firmware Secure Boot is on but the certificate or `sbverify` is missing. Without Secure Boot the old behaviour stays.
- 6A-304 (GRUB): legacy no longer rewrites `/etc/grub.d/10_linux` (file of the Slackware `grub` package) and no longer writes `GRUB_TOP_LEVEL` into `/etc/default/grub`. The first-entry choice is written to our own drop-in `/etc/default/grub.d/09-slacky.cfg`, only when the installed `grub-mkconfig` reads `default/grub.d/*.cfg` (this machine's does); otherwise nothing is written. Full kernel list sorting inside GRUB is removed (the 10_linux patch was the only way); the top entry is still chosen. Release note: a user whose 10_linux was patched earlier gets the original back with `slackpkg reinstall grub` (not run by us); a stale `GRUB_TOP_LEVEL` line in `/etc/default/grub` is overridden by the drop-in, and `/etc/default/grub` (a Slackware `.new` config) is not touched.
- 6A-305 (snapshots): `lib/spidersense_snap.py` keeps `important=yes` snapshots, reads snapper's `default`/`active` columns and protects them, and has named time limits (list 60 s; create 180 s and delete 300 s defined as constants) with a one-sentence fail-closed answer when snapper does not respond.
- Files touched: `lib/mod_nvidia.sh`, `lib/mod_limine.sh`, `lib/mod_kernel.sh` (only the three GRUB functions), `lib/spidersense_snap.py`.
- Verification: fake-root/stub tests (module landed/wrong version/missing, hold set/clear/active, anchored match, Secure Boot with and without cert, GRUB files untouched and drop-in written/skipped, snapshot plan with important/default/active, list timeout) all green, test file deleted; `bash -n`, `python3 -I` compile. NOT verified: a real NVIDIA install, a real GRUB machine, real snapper.
- Follow-up (not my files): the snapper `create` calls (`lib/common.sh` ~1453, 1464, `bin/gnomes` ~542) and `delete` (`lib/common.sh` ~1433) still have no `timeout`; wrap with `timeout 180` / `timeout 300`. Rust mirror: same anchored match plus landed check, fail-closed verifier check.

- 6A-305 (coordinator addition): the snapper create (pre/post/single) and delete calls in `lib/common.sh` and `bin/gnomes` now run under `timeout 180` / `timeout 300` (after sudo, so the password prompt is not cut short); a hung snapper fails closed like a failed snapshot. `bash -n` clean.

### 2026-10-17 Build 90_slacky - 6A-295 / 6A-296 / 6A-297 (V1, F3, 6A-240 call sites) - GitHub checksums, boot loader major hold, snapshot before Limine/sbctl update
- 6A-295 (V1): the six OBS plugins, OpenGHub and dvcp-aac are now checked against the SHA-256 and size that the GitHub release API names for the exact asset; on any doubt (no digest, other size, API unreachable, rate limit) the file is refused with one sentence and nothing is installed. dvcp-aac uses the verified downloader (no more reuse of any cached file over 100 KB) and the safe extractor instead of a bare `extractall`; a zip with an absolute or `..` member name is refused before unpacking. obs-composite-blur (now `x86_64-linux-gnu.deb`) and obs-teleport (now `Teleport-<ver>-Linux-x86_64.zip`) find their renamed assets again, so they move from 1.5.2 / 0.7.7 to 1.6.0 / 0.8.0.
- 6A-296 (F3): limine and sbctl are held at the installed major version in the update scan, the resolver and the batch resolver (including the Arch fall-back). A newer major is not installed and the update step says "waiting: a new major version of the boot loader (Secure Boot tool) needs a manual check". Nothing is held when the package is not installed.
- 6A-297 (6A-240 call sites): after a stand-alone Limine or sbctl update the boot files are rebuilt with `limine_standalone_boot_sync` (no more silent `|| true` steps). The safety snapshot is taken BEFORE the package is replaced; if it cannot be made the package stays as it is.
- Files touched: `lib/mod_gaming.sh` (new `gaming_verify_github_asset`, the dvcp-aac block, the three asset tables, the three embedded scan/resolver scripts, the limine/sbctl branches, the update step).
- Verification: real read-only GitHub API in a temp dir: good file accepted, one byte added refused, same-size random file refused, unlisted asset refused, non-GitHub address refused; dvcp-aac block run in a temp staging dir (installs both bundles, a tampered cache is re-downloaded and re-checked); the new asset regexes tested against the live release lists of all 7 repos; hold logic tested with fake installed and candidate version lists (12.x kept, 13.x held, unparsable held, not installed = no hold, sbctl 0.x/1.0); `bash -n` and compile of every embedded Python script. Tests deleted. NOT verified: a full real build of an OBS plugin, a real Limine/sbctl update, snapper.
- Known limits: the resolver still falls back to an older stable release when the newest has no matching asset (no "no matching asset" line yet); the "waiting" sentence is shown by the curated update step only, `check_backend.sh` (not touched) could show it from `major_hold.txt` in the cache folder. GitHub allows 60 unauthenticated API calls per hour; each GitHub-sourced build uses one.

### 2026-10-17 Build 90_slacky - 6A-298 / 6A-299 / 6A-300 (N0 N0b N0c N1 F1 V4, F0, M7) - honest check, release-safe multilib, kernel hold on snapshot failure
- User-visible: `--check` says "Could not check: <parts>." or one offline sentence instead of "up to date" whenever a part failed; a 404 or captive-portal page is no longer read as "no updates". Multilib/SlackBuilds setup reads the real Slackware release: 16.0 uses only the 16.0 tree, an unknown release is refused with one sentence, and a package older than the installed one (glibc/gcc downgrade) stops the setup. If the safety snapshot fails, the Slackware kernel packages wait too; the rest of the update continues. The whole check stops after 240 s.
- Technical: `status.json` gets optional keys `check_failed` (ids slackware, slackpkgplus, flatpak, sbo, cachyos_kernel, cachyos_gaming, gnomes, nvidia), `check_offline`, `check_timed_out`, `last_ok_check_ts` (old keys unchanged). Workers write `NA` when a suite does not apply. Kernel hold = marked block in `/etc/slackpkg/blacklist` for the duration of the Slackware steps only.
- Files touched: `lib/check_backend.sh`, `lib/mod_sbo.sh`, `lib/mod_packages.sh`, `bin/slacky-update`, `lib/common.sh` (2 wording lines).
- Verification: 52 checks in temp dirs (local fake mirror valid/404/HTML/hung, offline probe, fake version files, fake package dirs, fake blacklist with stubbed slackpkg); `bash -n` clean. NOT verified: real offline run, real 16.0, real root edit of the blacklist.
- Follow-ups (other files): fallback versions in `mod_gaming.sh` (V4), gaming helper exit code, tray kill after N minutes, `cron/slacky-update-check` time limit, i18n keys `CHECK_OFFLINE` / `CHECK_COULD_NOT`. Rust mirror: Rust IDs not assigned here.

### 2026-10-17 Build 90_slacky - 6A-306 - Kernel hold without touching slackpkg config; hooks only in self-test; honest gaming check
- User-visible: when the safety snapshot fails, the Slackware kernel waits (one sentence) while other Slackware packages update; `/etc/slackpkg/blacklist` is no longer edited, and a leftover 6A-300 block is removed once. Gaming checks no longer show invented version numbers; unreachable sources read as "could not check".
- Technical: explicit `slackpkg install/upgrade <names>` from status.json lists minus kernel-generic/huge/modules/source; test env hooks gated by `SLACKY_SELFTEST=1`; `CHECK_OFFLINE`/`CHECK_COULD_NOT` locale keys (en, nb); gaming scan exit 3 (partial) / 1 (none checked), resolvers return NONE instead of fallback versions.
- Files touched: `lib/mod_packages.sh`, `lib/check_backend.sh`, `lib/mod_sbo.sh`, `lib/mod_gaming.sh`, `locales/en.json`, `locales/nb.json`, logs.
- Verification: 46 checks in temp dirs with stubbed slackpkg and a dead proxy (green, test deleted). NOT verified: real root cleanup, real offline machine.
- Follow-ups: the scan only covers lists from the ChangeLog window (50 entries); in kernel-hold mode older pending packages wait for the next normal run.

### 2026-10-17 Build 90_slacky - 6A-307 - no emoji in program output; final line "All updates are completed" (Rust mirror: E-series)
- User-visible: no emoji or decorative pictographs in any output, TUI menu, doctor report, locale text or spinner (plain words and ASCII instead; humour kept in words). A successful full update now ends with exactly `All updates are completed`; on partial failure the line is still NOT printed and exit 20 stays. The old success sentence is no longer printed.
- Technical: text-only edits. Spinners use `- \ | /` / `*`; check marks became on/off, OK/WARN/FAIL or were dropped; `➔` became `->`, `[↑/↓]` became `[Up/Down]`. In `prompt_reboot_or_close` the final line is printed on every success path (non-interactive, reboot offer yes/no, plain close).
- Files touched: `bin/slacky-update`, `lib/common.sh`, `mod_docs.sh`, `mod_gnomes_engine.sh`, `mod_kernel.sh`, `mod_limine.sh`, `mod_nvidia.sh`, `mod_packages.sh`, `mod_rocm.sh`, `mod_sbo.sh`, `mod_secureboot.sh`, `mod_tweaks.sh`, `slacky_doctor.py`, `slacky_tui.py`, `slacky_update_i18n.py`, all `locales/*.json` (values only).
- Verification: code point scan over bin/ lib/ locales/ (0 hits except the exceptions below), `bash -n` on all shell files, compile of all Python files, all locale JSON parse. NOT verified: a live full update run.
- Exceptions left on purpose: `mod_limine.sh:1068,1696` (shared limine.conf marker), `:1121` (generated limine.conf comment, mirrored in Rust), `:1942,3325,3327` (match sbctl output, input not output), stale backup `lib/mod_limine.sh.orig`. The TUI cursor `▶` (U+25B6) is not in the scanned set and stays.

### 2026-10-18 Build 90_slacky - 6A-308 - ChangeLog fetch retry, mirror fallback, recorded reason; tray network wait and one re-check (Rust mirror: commit 7f0c7df)
- User-visible: the check right after login no longer misses Slackware updates just because the network was not up yet. A failed ChangeLog request is retried after 3 s, then the next mirrors of the same branch are asked; the tray waits silently (max 60 s) for the network before the login check and re-checks once after 3 minutes when a check was incomplete.
- Technical: `slacky_cl_curl` (one delayed retry, none on 4xx), mirror list built from `/etc/slackpkg/mirrors` (same branch only), one flight recorder entry per failed run via `gnomes_trust.flight_record`; tray pure functions `network_wait_decision`, `next_check_after`, `status_is_incomplete`, async `QHostInfo` lookup.
- Files touched: `lib/check_backend.sh`, `lib/slacky-update-tray`, `docs/log.md`, `docs/log_nb.md`.
- Verification: temp-dir tests with a local HTTP server (503 then OK, dead first mirror, other-branch mirror untouched, all dead = one entry, 404 = no retry) and tray scheduling tests, all green and deleted; `bash -n`, Python compile. NOT verified: a real login with a late network, the Qt wait on a live desktop.
- Follow-ups: the Python tray is not changed in the Rust tray; the inner range requests after a successful head request have no retry of their own.

### 2026-10-18 Build 90 (pending) - 6A-309 - TUI cursor is ">" only; stale backup removed; missing snapper config is said once
- User-visible: the TUI cursor and the expand/collapse marks are plain ASCII (`>` and `v`) in every terminal. On a Btrfs root with snapper installed but no snapper config for `/`, each run says once, in one sentence, that no safety snapshot can be made and how to set it up (`sudo snapper -c root create-config /`); system changes are still not held (behaviour unchanged) and the flight recorder gets a SpiderSense warning line.
- Technical: `lib/slacky_tui.py` (all cursor `▶` and the category marks `▾`/`▸` replaced, ascii branch kept as the only form), `lib/common.sh` `create_pre_update_snapshot` (still returns 2; guarded by exported `SLACKY_SNAP_NOCONF_SAID`). `lib/mod_limine.sh.orig` deleted (untracked, referenced only by a log sentence).
- Verification: stub test (btrfs + snapper stubs, config path redirected): one sentence, one log line, rc=2 on both calls; `bash -n`, `py_compile` clean. Test files deleted.
- Kept on purpose: box-drawing table borders in `slacky_tui.py`/`slacky_doctor.py` (ascii fallback exists), tree marks in the clean card, `rank_mirrors.py` rules, `⚡`/`│`/`✓`/`✗` in `mod_limine.sh` (file markers and input matching, owned by another agent), `──` in `mod_gaming.sh:9161` (L1's file).

### 2026-10-18 Build 90 (pending) - 6A-310..6A-314 (mirror of Rust LTS V3/V5/V6/N4/F5) - Antigravity, Claude Desktop, NVIDIA branch, disk space
- User-visible: Antigravity is verified against the SHA-256 that Google's own update service publishes for the build (the AUR maintainer's BLAKE2b is used only when Google names another build) and a mismatch or an unsafe archive stops with one sentence instead of a Python traceback; its git clone and download have timeouts. Claude Desktop's version now comes from Anthropic's own apt index (the file is already checked against that index), so the check no longer says "could not be verified" when AUR runs ahead. The NVIDIA update is offered only if it can be installed: "production" follows the installed driver's branch (latest.txt only when no driver is loaded), so an update is no longer offered forever; branch 390 says plainly it is not supported (no checksum); the dead 535 fallback (404) and the stale CachyOS 580xx fallback are gone. A curated build or batch checks free space first (build folder and /opt) and refuses with one sentence naming the space.
- Technical: 6A-310 `slacky_vendor_fetch.py` `parse_apt_latest`/`apt_latest_version`, used by both resolvers in `mod_gaming.sh` (no AUR fallback). 6A-311 `antigravity_vendor_sha256`/`parse_antigravity_update` + PYBUILD_ANTIGRAVITY (`vf.extract_safe`, `timeout=`, `curl --connect-timeout/--speed-limit/-m`, GIT_HTTP_LOW_SPEED_*). 6A-312 `mod_nvidia.sh` `nvidia_installed_major`, `nvidia_production_branch`, `nvidia_production_offer_version`, `get_nvidia_download_url` (production/feature resolve through the rule; any 3-digit branch resolved from the index, empty when unknown), 390 gate in `install_nvidia_run_driver`, callers handle an empty URL; `lib/check_backend.sh` (one block, modern-GPU branch) offers `nvidia_production_offer_version` instead of latest.txt. 6A-313 `gaming_space_precheck` (3072 MB build, 1536 MB /opt; summed when on one filesystem). 6A-314 no bare `extractall` left (Antigravity was the last; dvcp-aac already used `extract_safe`).
- Verification (scratch tests in temp dirs, deleted): apt latest/Antigravity parsers incl. bad input and network failure; Antigravity block run with fake git/curl: Google checksum match installs, wrong checksum deletes the file and refuses, no checksum refuses, absolute-symlink archive refuses; NVIDIA rule with stubbed curl (installed 595 stays 595.104.02, no driver follows latest.txt 615, junk latest falls to 595, unknown branch gives no offer, 535 fallback, 390 refused before any probe); space check ok and refuse, nothing created. `bash -n`, `python3 -I` compile. Real network read-only: Google's update service answers today with 2.0.6 (older than AUR 2.24.0), so today the AUR value is used for 2.24.0.
- Known limits: Google's service lags, so the vendor checksum applies only when it names the same build; the trust anchor for newer builds remains the AUR maintainer (write in the release notes). `check_backend.sh` was touched for V3 (not in the stated ownership list). No real install of Antigravity/Claude Desktop/NVIDIA was run.

### 2026-10-18 Build 90_slacky - 6A-315..6A-320 (LTS F4, N0c, N0d, N3, N5, S8/S9/S10, V2) - tray survives Qt changes, no hung checks, clean loader environment, live mirrors only, config files that stay disabled, no root network check, Microsoft UEFI CA 2023
- 6A-315 (F4 + N0c): the tray tries PyQt6 first and falls back to PyQt5. With neither it prints one line to stderr (the launcher keeps it in `~/.cache/slacky-update/tray.log`, size-capped), shows no notification and exits normally, so the autostart does not loop. A check that runs longer than 6 minutes is killed with all its child processes (the check starts in its own process group) and the tray says "Could not check"; the normal single re-check follows. Files: `lib/slacky-update-tray`, `bin/slacky-update-tray`.
- 6A-316 (N0d): `LD_LIBRARY_PATH`, `LD_PRELOAD`, `LD_AUDIT` and `LD_BIND_NOW` are cleared at the entry points `bin/slacky-update`, `bin/gnomes`, `bin/spidersense`, `bin/slacky-update-tray`, the tray itself, `lib/check_backend.sh` and the weekly cron job, so a wrapped desktop session cannot make host tools load foreign libraries.
- 6A-317 (N3): the SBo source fall-backs now have time limits (`wget --timeout=30 --tries=3`; `curl --connect-timeout 15 -m 1800 --speed-limit 1000 --speed-time 45`). The Antigravity and dvcp-aac sites named in the audit were already fixed by 6A-310..314; no other download call without a limit remains in `common.sh`, `bin/`, `lib/*.sh` or `lib/*.py` (urllib calls all pass `timeout=`). Files: `lib/mod_sbo.sh`.
- 6A-318 (N5): dead built-in mirrors removed, measured read-only on 2026-10-18: Chaotic de-1, nl-1, fr-1 and ca (404 for `chaotic-aur.db`), Arch `mirror.f4st.host` (no answer), Slackware acc.umu.se, heanet.ie, iij.ad.jp, lysator.liu.se (404 for `ChangeLog.txt`) and tds.net, c3sl.ufpr.br (no answer). The signed, weekly refreshed mirror lists stay the primary source. Files: `lib/slacky_mirrors.py`, `lib/rank_mirrors.py`.
- 6A-319 (S8, S9, S10): cron jobs (hourly and weekly), `/etc/profile.d/slacky-hidpi.*`, the tray autostart and the kernel hook are shipped as `.new` (mode 0644) and installed by a `config_job` helper in doinst: absent = installed; same = `.new` dropped; an untouched older shipped version (md5 list of every earlier version) = updated and keeps its mode, so a job switched off with `chmod -x` stays off; changed by the admin = kept, `.new` left. Because older packages shipped these as plain files and `upgradepkg` removes such a file after doinst, a small detached helper restores the kept file for up to two minutes if that happens (release note: this transitional upgrade is the one risk; check `ls /etc/cron.weekly` after the first upgrade). Docs now come from an explicit list in the SlackBuild (12 files; `log.md`, `log_nb.md`, `runtime_spec.md`, `healing_legacy_9A-9D.md`, `gnomes_spec.md`, `spidersense_spec.md` are no longer shipped; a missing listed file stops the build). The weekly cron no longer runs the network check as root: root only runs the sentinel's `refresh-keys` (120 s limit); the update check runs as the logged-in desktop user via `runuser` with `timeout 360`, a clean environment, no sudo and no prompt, and the notification is sent as that user; without a logged-in user nothing is checked. Files: `slackbuild/slacky-update.SlackBuild`, `cron/slacky-update-check`.
- 6A-320 (V2): `certs/microsoft-uefi-ca-2023.crt` added (downloaded from Microsoft's PKI repository, SHA-256 F6:12:4E:34:12:5B:EE:3F:E6:D7:9A:57:4E:AA:7B:91:C0:E7:BD:9D:92:9C:1A:32:11:78:EF:D6:11:DA:D9:01, subject "Microsoft UEFI CA 2023", valid to 2038-06-13). `verify_microsoft_uefi_authenticode` accepts either CA; the 2023 file is used only when its fingerprint matches the pinned value. The pinned Fedora shim 16.1-7 verifies against both CAs. SBAT levels of the pinned files and the "Shim/MOK path is frozen" note are in `docs/LIMINE_SECUREBOOT_FIELD_GUIDE.md`. No installed boot file was changed. Files: `lib/common.sh`, `certs/microsoft-uefi-ca-2023.crt`, `docs/LIMINE_SECUREBOOT_FIELD_GUIDE.md`.
- Verification (temp dirs only, scratch tests deleted): `bash -n` on all `bin/`, `lib/*.sh`, `cron/`, SlackBuild; `python3 -I` compile of the tray and both mirror files; the tray module loaded under Qt 6 and Qt 5 (offscreen) with a fake 5-minute check that was killed after the shortened limit (tooltip "Could not check", no stray process), and with both Qt versions blocked (one line, exit 0); cron script run as a normal user with stub check, sentinel and notify-send (check ran with `LD_LIBRARY_PATH` cleared, notification sent only with pending updates); `config_job` run in a fake root (fresh, same, known-old, disabled stays disabled, admin edit kept, restore after removal, no leftovers); the SlackBuild run with `OUTPUT_DIR` in a temp dir: the `.new` files and the 12 docs are in the package, `doinst.sh` passes `sh -n`; shim and GRUB RPMs downloaded to a temp dir (hashes match the pins) to check the CA and read the SBAT sections.
- Not verified: the root branch of the cron job (`runuser`) and the real `upgradepkg` transition (needs root and an installed older package); the tray on a real desktop session.
- Known limits: when a shipped config file changes in a later build, add the md5 of the replaced version to the list in the SlackBuild, otherwise the admin gets a `.new` to merge. The Microsoft RSA Devices Root CA 2021 chain was not validated (no root file shipped); trust rests on the fingerprint pin.

### 2026-10-18 Build 92 (pending) - 6A-321 (mirror of Rust initramfs inputs) - --sync-boot rebuilds only changed kernels
- A full boot sync no longer rebuilds every startup image: only kernels whose recorded inputs changed (vmlinuz, extra/DKMS/NVIDIA modules, dracut config) or that have no record or no image are rebuilt. `sudo slacky-update --sync-boot --all` rebuilds every image. The repair wizard in the Secure Boot menu still rebuilds all (explicit repair).
- Technical: `generate_kernel_initramfs "ALL"` now calls `initramfs_is_stale ... strict` per kernel (strict = a missing or unreadable record means rebuild, no file-time guess; SpiderSense orders still win). `SS_INITRD_FORCE_ALL=1` skips the check. ALL runs now set `SS_INITRD_FAILED`, and `--sync-boot` and the NVIDIA menu call `record_initramfs_inputs_all` after the boot chain, so the next run finds records (format unchanged, `docs/initramfs_inputs_spec.md` in the Rust repo; `record_initramfs_inputs_all` clears `SS_INITRD_FAILED` afterwards). Help text updated.
- Files: `lib/mod_kernel.sh`, `lib/mod_armor.sh`, `bin/slacky-update`.
- Verification: fake root in a temp dir with a stubbed sudo: no records = both kernels rebuild; after writing records = both skip; an `nvidia.ko.zst` appearing under one kernel = only that kernel rebuilds; record header/lines as in the spec. The dracut loop itself (hard-coded /boot, /lib/modules, real dracut) was NOT run end to end; syntax checked with `bash -n`.
- Known limits: the NVIDIA userspace-driver path (`mod_nvidia.sh`) also goes through "ALL" and now skips unchanged kernels (module hashes cover DKMS/precompiled modules, userspace files are not in an image). The first run after this build rebuilds every kernel once (no records exist after a plain pipeline run only when none were written).

### 2026-10-18 Build 93 (pending) - 6A-322..324 (mirror of the whole-catalog comparison) - easyeffects, spotify, v4l2loopback updates are listed again
- `easyeffects`, `spotify` and `v4l2loopback` now show their updates in the check (found with the same versions as the Rust app: easyeffects 8.3.0, spotify 0.6.6, v4l2loopback 0.15.4). `spacenav` is reported as "could not check" instead of silently "up to date".
- 6A-322: the easyeffects catalog row had `(?:2|1)` in its extras pattern; the row parser splits on `|`, so the row was cut wrongly and a bogus 32-bit pattern was required. Written as `[12]` (same match). Checked every other row with a parser simulation: no other row is affected.
- 6A-323: the Arch JSON lookup used the catalog id. Now `ARCH_API_NAMES` maps spotify -> spotify-launcher and v4l2loopback -> v4l2loopback-dkms, and `ARCH_API_ARCH` maps v4l2loopback -> `any` (DKMS packages are arch=any in the Arch API; with x86_64 it still answers 404). Applied in the update check and both resolvers.
- 6A-324: spacenavd is in no Arch, CachyOS or Chaotic list (Arch search API: not found). Rust reads a signed Debian index for it (owner decision 2026-10-15); legacy has no Debian reader, so an empty answer is now taken out of the "looked" set and the check ends with exit 3 (6A-298/306 "could not check").
- Files: `lib/mod_gaming.sh`.
- Verification: `bash -n`; the three Python blocks compile; the update-check block run from a temp HOME with a fake package list (old versions) against the live Arch API: first live (cache filled in the temp dir), then offline (proxy to a dead port, cache only): same result both times, exit 3 for spacenav; temp dir deleted.
- Known limits: spacenav still lists no update in legacy (a Debian reader would be a new feature). The deploy-time resolver for spacenav still uses mirror lists only.

### 2026-10-18 Build 93_slacky (next build: 94) - 6A-325 - GitHub release lists are cached with ETag and survive the rate limit (mirror of Rust ee882e8)
- User-visible: a missed OBS plugin update (the Rust app lost obs-composite-blur 1.6.0 to a failed GitHub request) can no longer happen silently. The eight GitHub lists (six OBS plugins, Bambu Studio, dvcp-aac) are asked for at most every 6 hours, with a conditional request (an unchanged list costs no rate limit). When GitHub says the limit is used up, no further API call is made until it frees up; the last good list is used for up to 3 days, after that the app is reported as "could not check" (6A-298). The reason is written once per run to the flight recorder.
- Technical: new `lib/slacky_release_cache.py` (`<cache>.etag` sidecar, If-None-Match, 304 renews the file time, 6 h TTL for api.github.com / 30 min elsewhere, `ratelimit_<host>` with the reset time clamped 60 s .. 2 h from X-RateLimit-Reset or Retry-After, 429 or 403 with Remaining 0 / Retry-After = rate limit, plain 403 is not, bad answer never overwrites list or etag, stale limit 3 days, `release_list.refresh_failed` via `gnomes_trust.flight_record`). `gh_releases_cached` and all three copies of `fetch_url_cached` in `mod_gaming.sh` delegate to it for api.github.com URLs (so Bambu, dvcp-aac and the resolvers use it too); the old code stays as fallback when the module is missing. SlackBuild installs the new file.
- Files touched: `lib/slacky_release_cache.py` (new), `lib/mod_gaming.sh`, `slackbuild/slacky-update.SlackBuild`, `claude_log.md`, `docs/log.md`, `docs/log_nb.md`.
- Verification: `bash -n`, py_compile, the three Python heredocs compile; scratch tests against a local HTTP server (200+ETag, TTL hit, 304 with If-None-Match, 403 rate limit with reset and pause, far reset clamped, 429 Retry-After, plain 403, malformed JSON, 3 day limit, dead server, one log per reason) all green, tests deleted. Not verified: a full `--check` against real GitHub.
- Rust mirror: ee882e8 (`release_cache.rs`).

### 2026-10-18 Build 94_slacky - 6A-326 - DKMS multi-kernel audit no longer fooled by decoy nvidia* modules (mirror of the Rust decoy fix)
- User-visible: every Arch/CachyOS/Zen kernel ships `nvidia-wmi-ec-backlight.ko.zst`, which made every kernel count as "has a precompiled NVIDIA driver", so the DKMS audit/rebuild across kernels was skipped (an old module could stay after a driver update). Now only the driver itself (`nvidia.ko`, `.zst/.xz/.gz`) counts.
- Technical: `lib/mod_kernel.sh` (`has_precompiled_nvidia`, ~L1956) uses an exact regex with `build/` pruned, `-print -quit`. `lib/mod_nvidia.sh` DKMS registration (~L1235) collects only the driver's own modules (nvidia, -drm, -modeset, -uvm, -peermem), build/ pruned. Other sites already used `nvidia.ko*` (exact driver) or an exact regex (`mod_armor.sh`, `mod_nvidia.sh` copy filter); no Python/bin site matches modules loosely.
- Files touched: `lib/mod_kernel.sh`, `lib/mod_nvidia.sh`, `claude_log.md`, `docs/log.md`, `docs/log_nb.md`.
- Verification: `bash -n`; fake module trees (decoy only, decoy + video/nvidia.ko.zst, decoy + extramodules/nvidia.ko.zst with a build/build loop, nvidia.ko only under build/) gave NONE / found / found / NONE; temp dir deleted. Real /usr/lib/modules read-only: decoy present in all kernels.
- Known limits: several `find -L` sites in `mod_nvidia.sh` still walk `build/` (slow, correct result).

### 2026-10-19 Build 94_slacky (next build: 95) - 6A-327 - library version check before install (OpenRGB / Qt_6.12), host then runtime
- User-visible: a package that needs a newer library than the system has (OpenRGB 1.1 asks for Qt_6.12, Slackware has 6.11) is no longer installed broken. If the Underpants runtime has the newer library, the curated program is installed with a launcher that starts it with the runtime first (programs move to /opt/underpants/pkgs/<id>/, same layout as the Rust app; udev rules and other host files stay put). If neither the host nor the runtime fits (or the runtime is not installed), nothing is installed, the installed version stays and one sentence says so: "<app> <ver> needs a newer <lib> (<version>) than this system has, so it was not updated; the installed version stays." The version then waits and is not offered again until one of the libraries involved changes.
- Technical: new `lib/slacky_symver.py` (pure Python ELF reader: DT_VERNEED and DT_VERDEF, no readelf needed). Curated: `gaming_symver_gate` / `gaming_symver_wrap` in `lib/mod_gaming.sh` run before the footprint guard (order: package files, host, then runtime); waiting list `lib_hold.json` read by the update check (`lib_waiting`). Gnomes: `_symver_refusal` after the glibc check in `transmute` (order: app, runtime pool, host, like the launcher), `record_held(..., stamps=)`, `held_is_current`. SlackBuild installs the new file.
- Files touched: `lib/slacky_symver.py` (new), `lib/mod_gaming.sh`, `lib/gnomes_pacman.py`, `slackbuild/slacky-update.SlackBuild`, `claude_log.md`, `docs/log.md`, `docs/log_nb.md`.
- Layout (coordinator decision, same in both apps): the moved real program goes to `/opt/underpants/pkgs/<id>/<original relative path>` (e.g. `/opt/underpants/pkgs/openrgb/usr/bin/openrgb`), root:root; `/usr/bin/<app>` is the launcher. No `/opt/<id>-rt` was ever installed, so no migration. The footprint guard needed no change (it already ignores `opt/underpants/` in `archive_host_paths`; staging judge has no opt rule). Verified with synthetic ELFs: host lib old, runtime lib new, the wrapped program starts from the new path (unwrapped fails with version V2 not found).
- Verification: `bash -n`, py_compile; scratch tests (deleted) with real gcc-built libraries carrying version tables (Foo_6.11 host vs Foo_6.12 runtime): host old + runtime new = RUNTIME and the wrapped program really starts; no runtime / old runtime = refused with the sentence; satisfied or bundled library = passes; library outside bin dirs that needs the runtime = refused; app order; waiting list released when a library file changes; gate function end to end with stubs. Not tested on the real OpenRGB package or a real install.
- Known limits: 64-bit ELF only (32-bit multilib files are not checked); a library not found anywhere is not a version problem and is ignored; a library without version info is accepted (the loader only warns); symlinks to a wrapped program follow the wrapper; the wrapper puts the runtime libraries first for that program and its children, like the gnomes launchers.

### 2026-10-20 Build 96_slacky - 6A-328 / 6A-329 / 6A-331 / 6A-332 / 6A-333 / 6A-334 - Boot menu no longer drops good kernels; honest NVIDIA sync; safer root extracts
- 6A-328 (M2 / 6A-282 regression): a kernel is left out of the Limine menu only when this run's image build failed for it or its fingerprint record says the image is stale (and no build judged this run). Depmod, DKMS and Secure Boot signing changing file times no longer remove kernels. The running kernel is never left out; if every kernel would be left out, all are kept and one sentence goes to the log. Stock names `generic-`/`huge-` accepted for `/boot/initrd.gz`. `SS_MENU_INITRD_FAILED` keeps the failed list past `record_initramfs_inputs_all`.
- 6A-329 (6A-321): the initramfs fingerprint now includes `/etc/modprobe.d`, so NVIDIA option or nouveau blacklist changes rebuild the image (one rebuild of every image on the first run after the update).
- 6A-331 (S6): `build_nvidia_modules ALL` returns 1 and names the kernels when a driver build failed or the module is missing.
- 6A-332 (6A-304): `sync_bootloader_configuration` writes the NVIDIA kernel parameters to `/etc/default/grub.d/08-slacky-cmdline.cfg` when grub-mkconfig reads drop-ins and leaves `/etc/default/grub` alone; otherwise the old edit stays.
- 6A-333: test path hooks (SS_FP_*, SLACKY_BOOT_DIR, SLACKY_ETC_DIR, NVIDIA_HOLD_FILE, NVIDIA_MODROOT, LIMINE_MODULES_ROOT, SLACKY_SB_EFIVAR, DKMS_ROOT, DKMS_SUDO, MODULES_ROOT, PKGDB_DIR, GRUB_DROPIN_DIR, GRUB_MKCONFIG_SCRIPT) are honoured only with SLACKY_SELFTEST=1.
- 6A-334 (S5): every `sudo tar -C /` in kernel and NVIDIA deploy is checked; failure gives one sentence and stops (r8125 is optional: error, not installed, no success line).
- Files touched: `lib/mod_limine.sh`, `lib/mod_kernel.sh`, `lib/mod_nvidia.sh`, `claude_log.md`, `docs/log.md`, `docs/log_nb.md`.
- Verification: `bash -n` all lib/mod_*.sh; fake-root scratch tests (deleted): mtime bump keeps kernel, running kernel kept, failed-initrd kernel left out, empty set keeps all plus log line, stale record left out, build-judged run ignores record, generic-/stock initrd names, modprobe.d changes the fingerprint, hooks unset without SLACKY_SELFTEST. Not tested: real dracut/DKMS/GRUB, grub drop-in on a real system, S6 end to end.
- Follow-up: `bin/slacky-update` ~832 prints "Synchronized for every kernel" on rc 0 only, so it is now honest. --sync-boot flow could call `record_initramfs_inputs_all` before `sync_bootloader_configuration`; not needed now.

### 2026-10-20 Build 96_slacky - 6A-335..344 - Gnomes/curated/packaging audit fixes
- 6A-335 (S8): upgrade no longer leaves executable `<job>.slacky-keep.*` copies in cron/profile.d/autostart/kernel hook dirs (root jobs ran twice). Old copies are removed on upgrade, the spare copy now lives in `/var/cache/slacky-update`, and the helper ignores HUP/INT. `slackbuild/slacky-update.SlackBuild` (BUILD 96).
- 6A-336: the OpenRGB udev rule is no longer world-writable (MODE 0666 on all USB/hidraw/i2c). The upstream rules of the package are used when present, otherwise `TAG+="uaccess"` scoped to common RGB vendor IDs. An already installed OpenRGB keeps the old rule at `/lib/udev/rules.d/60-openrgb.rules` until it is rebuilt. `lib/mod_gaming.sh`.
- 6A-337: `gnomes -R` hands the run-lock marker to `purge-service` through sudo only when it holds the lock (no 60 s wait, rc.local block removed); `sudo python3` calls use `-I`. `grep -qF` for the wrapper marker (the `[` made grep fail silently); rollback lock file is created once. `bin/gnomes`, `lib/mod_clean.sh`.
- 6A-338: `SLACKY_SYMVER_*` and `SLACKY_GNOMES_BUILD_ROOT` only with `SLACKY_SELFTEST=1`; the ELF reader maps the file instead of reading all of it; docstring corrected. `lib/slacky_symver.py`, `bin/gnomes`.
- 6A-339: a symbol-version / glibc hold in `gnomes -S` counts as "waiting" (exit 0, sentence printed, no curated-fallback prompt, no failure in a full update), like curated. The build writes `<output-dir>/.waiting`. `lib/gnomes_pacman.py`, `bin/gnomes`.
- 6A-340 (V6): the update scan for Claude Desktop uses Anthropic's apt index, the same source as the install. `lib/mod_gaming.sh`.
- 6A-341 (F3): the Limine/sbctl major-version hold now sees `underpants-limine-*` and `cachyos-gnome-sbctl-*`. `lib/mod_gaming.sh`.
- 6A-342: the zip path-safety check no longer loses its match to SIGPIPE under pipefail on long listings. `lib/mod_gaming.sh`.
- 6A-343: the TUI catalog reader splits rows outside regex groups, so hidden rows (OpenGHub) stay hidden. `lib/slacky_tui.py`.
- 6A-344 (S12): kernel purge removes only packages of exactly that kernel (no more `7.2.10-1-cachyos` matching the `-bore` packages). `lib/mod_clean.sh`.
- Verification: fake-root scratch tests (deleted): keep-file removal and helper surviving HUP, sudo env hand-over, waiting match, installed-package regex on real pkgdb names, zip bypass reproduced and fixed, catalog field counts, kernel glob cases; `bash -n` and `py_compile` on all touched files. Not tested: real upgradepkg doinst, real udev, full `gnomes -S` build with a hold.

### 2026-10-20 Build 96_slacky - 6A-345..359 - Honest endings, trust messages, env hooks, tray and docs
- 6A-345 (1a/1e): kernel and graphics-driver updates that wait for a snapshot or for /boot are no longer silently dropped: the run ends with exit 20, no "All updates are completed", and one sentence says what waits and why. The held Slackware kernel packages stay listed after the run (reconcile keeps them); a failed module build in the "Synchronized for every kernel" step also ends the run with exit 20. New `slacky_msg` helper (localised text with English fallback), `slacky_stock_kernel_pending`. Files: `bin/slacky-update`, `lib/common.sh`, `lib/mod_packages.sh`.
- 6A-346 (1b): a run whose check was offline or incomplete (`check_offline`, `check_failed` in status.json) says so in one sentence and ends with exit 20 (no success line, nothing claimed as up to date). `slacky_check_state` in `lib/common.sh`.
- 6A-347 (1c): the post-update health line says "Up-to-date & healthy" only after a real success; failed (rc 1/3) and declined/waiting updates show [FAIL] / [WARN].
- 6A-348 (1d): an interactive run that ends with exit 20 asks "Press ENTER" once (the EXIT trap no longer asks again).
- 6A-349: `SLACKY_RUN_PARTIAL` from the caller's environment is cleared at the start of a full update.
- 6A-350: the self-update check looks at `/var/log/packages/slacky-update-[0-9]*` (no longer matches slacky-update-rs) and compares the highest installed build of the running version.
- 6A-351 (4a-4c): the retry after an unknown/expired key forces ONE key refresh per run (`slacky_keys_first force` -> `refresh-keys --force`); final sentences follow the status, not words in the detail text: wrong-source key ("does not belong to its package source", also detected in `gnomes_trust.verify_package` when another family's keyring accepts the signature), expired signature (EXPSIG: damaged/expired, no refresh promise), expired/unknown key (says a refresh was tried). New messages `wrong_source`, `sig_expired`. Files: `lib/common.sh`, `lib/mod_packages.sh`, `lib/gnomes_trust.py`.
- 6A-352 (4e/R4): root verify runs record the signers in the system sentinel folder (only when the sentinel module belongs to root and is not group/world-writable). `lib/gnomes_trust.py`.
- 6A-353 (4f): `slacky_sentinel.py` main() returns exit 25 and writes `last_error` to state.json (shown by `status`) instead of a silent exit 0 on an unexpected error.
- 6A-354 (F2): `gnomes_trust.verify_db_sig(path, sig, family)` and `check_db_before_replace(data, repo, parse, ...)` (signature, parse, monotonic date, before the cached DB is replaced) with selftest cases (30 now). The call site in `gnomes_pacman.py` still has to be wired (diff handed over).
- 6A-355: env hooks gated: `SLACKY_SLACKBUILDS_DIR` (self-test only), `SLACKY_FOOTPRINT_MODE=report` in `mod_rocm.sh` (self-test only), `SLACKY_TX_ID` (plain token only), `SLACKY_CPU_TIER` (only when the CPU supports it, or self-test). `SLACKY_GNOMES_TRUST=log` stays.
- 6A-356: SBo ChangeLog cache is checked after a 304 (a bad cached file is removed and the check reports "could not check"); a CachyOS NVIDIA page without an nvidia-utils package sets `NVIDIA_LOOKUP_FAILED`. `lib/check_backend.sh`.
- 6A-357: an installed item that cannot be looked up by design (spacenav) is reported through `SLACKY_GAMING_MANUAL_FILE` -> `manual_items` in status.json and shown once as "Not checked automatically, please check by hand"; it is not a failed check any more (needs the one-line change in `mod_gaming.sh`, handed over). `lib/check_backend.sh`, `bin/slacky-update`.
- 6A-358: tray: "Could not check"/offline replaces "System is up to date" when the last check was incomplete (tooltip and menu); the timeout note survives the 30 s poll; `load_status` ignores non-object JSON, bad timestamps and non-list values. `lib/slacky-update-tray`.
- 6A-359: unknown option prints one sentence plus the help and exits 2 (no menu); help lists -M/--rank-mirrors, -P, --protect-links, --gaming-deploy/--gaming-uninstall, --hyprmod and the icon/cursor flags; README: install lines use `../slacky-updates_releases`, locale claim corrected (English and Norwegian complete, 22 partial), zstd tool instead of "native zstandard". `bin/slacky-update`, `README.md`.
- Files touched: `bin/slacky-update`, `lib/common.sh`, `lib/check_backend.sh`, `lib/mod_packages.sh`, `lib/mod_sbo.sh`, `lib/mod_rocm.sh`, `lib/slacky-update-tray`, `lib/gnomes_trust.py`, `lib/slacky_sentinel.py`, `README.md`, `locales/en.json`, `locales/nb.json`, `claude_log.md`, `docs/log.md`, `docs/log_nb.md`.
- Verification: `bash -n`, py_compile, gnomes_trust.py selftest (XDG_CACHE_HOME redirected) 122/122; scratch tests (deleted) with a stubbed `run_full_update` and a fake HOME/status.json: hold by snapshot (cachyos, nvidia, stock kernel), /boot unready, offline, partial check, slackware rc 1/2/3 and a clean run (final line and exit codes); reconcile in hold mode; interactive double prompt through a pty; tray load_status/incomplete_note with broken files; self-update glob with a fake release; trust message mapping (all status/detail pairs) and forced refresh; wrong-family detection with real throwaway gpg keys; sentinel exit 25; SBo 304 with bad and good cache; manual item shown once; CPU tier and tx id gates; unknown option exit 2. Not tested: root-mode signer recording, a real run, the tray in a desktop session.
- Known limits: the `mod_gaming.sh` change for spacenav, the `gnomes_pacman.py` trust_gate fail-closed change and the F2 call site, the TUI offline line, `SLACKY_TXID` in `mod_limine.sh`, `SLACKY_FOOTPRINT_MODE` in `mod_nvidia.sh` and `SLACKY_MIRROR_CACHE_DIR` in `slacky_mirrors.py` are in files owned by others and are handed over as diffs.

### 2026-10-20 Build 96_slacky - 6A-367 / 6A-368 (mirror of Rust Build 89) - failed Underpants installs are never reported as done
- Full update, gnomes fallback path (no `gnomes` binary): a missing package or a failed `upgradepkg` now leaves the app pending (`ss_failed gnomes`, exit 20, no final line) instead of `|| true`; the old cachyos-gnome package is only removed after a successful install. Uses sudo when not root.
- `gnomes runtime install`: a failed `upgradepkg` now says "The shared runtime package could not be installed, so the previous runtime stays." and exits 1 instead of printing PROFIT.
- Files: bin/slacky-update, bin/gnomes.
- Verification: bash -n. Not run on the machine.
- Mirrors Rust Build 89 (gnomes-only runs built but never installed the apps and crossed them off).

### 2026-10-20 Build 97_slacky - 6A-369 - a stale startup-image record never removes a kernel from the boot menu
- Regression seen on the owner's machine with Build 96: the hourly Limine sync left 9 of 11 kernels out of limine.conf ("The startup image for kernel ... is not current, so that kernel was left out of the boot menu."). Cause: 6A-328 also excluded kernels whose initramfs input record was stale, and the 6A-329 record format change (new `modprobe-conf` line) made every record stale. The running kernel and the one rebuilt kernel stayed, so the machine still booted.
- Fix: only a kernel whose image build failed in this run is left out. A stale record only means "rebuild next time".
- Files: lib/mod_limine.sh. BUILD 97 (96 was installed before the later Build 96 work: 6A-360..368, 7J-7O runtime refresh; all of it ships in 97).
- Verification: bash -n. Owner restores the menu with `sudo slacky-update --sync-boot --all`.
- Rust: has no record-based menu exclusion (checked 2026-10-20), nothing to mirror.

### 2026-10-21 Build 97_slacky - 6A-370 - honest Game Priority Booster (curated vram-booster)
- The curated item `vram-booster` is now called "Game Priority Booster (CPU/IO)": "Raises the CPU and disk priority of the game in focus." Id unchanged.
- Wrapper `/usr/bin/dmemcg-booster`: no longer writes PIDs into a fake tmpfs "cgroup"; never boosts itself, shells, terminals, compositors or panels; generic interpreters (python, perl, node ...) only with a game marker in the command line (steamapps, Proton, wine, gamescope, lutris, heroic, faugus, retroarch); real dmem.low (half of VRAM) only on AMD/Intel when a dmem cgroup is available; ASCII log, one line per boosted pid.
- Why: research 2026-10-21 showed the old wrapper never used the dmem controller and boosted unrelated python3 processes; NVIDIA 615 ignores dmem.low (osCgroupCanEvict passes ignore_low=true).
- Files: lib/mod_gaming.sh (catalog row, wrapper and rc heredocs). Mirrors Rust Build 91 (docs/vram_booster.md there).
- Verification: bash -n; extracted wrapper parses (Python ast); installed on the owner's machine 2026-10-21, daemon runs, log clean.

### 2026-10-23 Build 98_slacky - 6A-371 - an unreadable package index is "could not check", never a silent "up to date"
- Seen 2026-10-23: Brave 1.98.60 was on Chaotic-AUR but the legacy check said nothing; the Rust app listed it. The Chaotic index (about 2 MB, behind a redirect) did not finish within the 5 s limit, and the scan silently used yesterday's saved copy (1.97.59) without marking anything as "could not check".
- Fix (check scan, lib/mod_gaming.sh): the index time limit is 20 s (all four copies of fetch_url_cached); in the check scan a source that could not be read is recorded, a saved copy is used only when younger than 3 days, and every item with an unread source counts as "could not check" (exit 3, the list is kept, no "up to date").
- Verification: bash -n, Python ast of the scan; real read-only scan on the owner's machine now lists brave 1.97.59 -> 1.98.60 (rc 0).
- Not a feature change: the LTS test week continues (owner 2026-10-23, day 2/7).

### 2026-10-23 Build 99_slacky - 6A-372 - initramfs rebuilt for an NVIDIA module only when the module content changed
- Seen 2026-10-23: the full update rebuilt the initramfs of the running bore kernel although its NVIDIA modules were unchanged (same sha256 in every snapshot since 2026-10-14). During the DKMS step the modules' time stamp changed (DKMS reinstalls through the extramodules symlinks of the DKMS bridge), and the stale test in mod_nvidia.sh only compared nvidia.ko's mtime with the image.
- Fix: new nvidia_initrd_needs_rebuild uses the 6A-321 input record (it holds the module sha256): record current = keep, changed = rebuild; only without a usable record the old time test is used.
- Files: lib/mod_nvidia.sh.
- Verification: bash -n; stub tests for record current/changed/missing and no record function. Not run on the machine yet.
- Rust: uses content fingerprints, not affected. Small change, LTS test week continues (owner 2026-10-23, day 2/7).

### 2026-10-25 Build 100_slacky - 6A-373 - catalog patterns match only the package itself (no false OBS update)
- Seen 2026-10-25: legacy offered "OBS Studio 32.2.2 -> 33.0.0"; the Rust app did not. arch-extra has obs-studio 32.2.2 (installed); the check pattern `obs-studio-[0-9a-zA-Z_.-]*` also matched the different CachyOS package `obs-studio-browser-33.0.0`.
- Fix: the catalog patterns of obs-studio, google-chrome (could match google-chrome-beta/-unstable) and opera, and the opera install resolver, require the version to start with a digit, like the other rows. The obs-studio and google-chrome install resolvers already did.
- Files: lib/mod_gaming.sh.
- Verification: bash -n; real read-only gaming scan now lists antigravity, faugus, limine, obs-composite-blur (same 4 as the Rust app), no OBS.
- Rust: matches exact package names from the repo databases, not affected. Small catalog fix; LTS test week continues.

### 2026-10-25 Build 101_slacky - 6A-374 - plan prompt asks again on a stray answer; honest initramfs and Vulkan layer messages
- Seen 2026-10-25: stray keys ("7916", typed after a failed password) at "Apply all pending updates ... [Y/n/c(ustom)]" switched the run to step-by-step questions. Now only Y, n or c are answers; anything else asks again ("Please answer Y, n or c.").
- Seen 2026-10-25: 9 kernels rebuilt "older than its updated NVIDIA module" although every input in their records (vmlinuz, module sha256, modprobe, dracut) was unchanged before and after the run, and the records all pass the check afterwards. Cause not yet proven (INFERENCE: the DKMS bridge briefly changes the module set the fingerprint reads). Now the log gets one diff per kernel when its record does not match, so the next kernel update shows the exact line; the screen message says "The startup image for kernel X no longer matches its driver modules or settings, so it is rebuilt."
- Gamescope note: an implicit Vulkan layer whose JSON has enable_environment is reported as "only active when ENABLE_GAMESCOPE_WSI=1 is set", not "every game ... will load".
- Files: bin/slacky-update, lib/mod_nvidia.sh, lib/gnomes_pacman.py.
- Verification: bash -n, py_compile; prompt loop with stray input; vulkan_layer_enable_env on a package built from the real gamescope layer JSON.
- Small change; LTS test week continues.

### 2026-10-29 Build 102_slacky - 6A-375 - the update check reads every source and never answers silently from an old Arch lookup
- Seen 2026-10-29: OBS Studio 33.0.0 was in Arch extra (the Rust app listed it), legacy said nothing. archlinux.org's JSON API failed (SSL EOF) and the saved answer (32.2.2) was used without marking the item as could-not-check (6A-371 only covered repo listings). Also found: the scan read only the first 10 of a randomly ordered set of sources (`list(needed_repos)[:10]`), so random sources were skipped per run.
- Fix (check scan, lib/mod_gaming.sh): all needed sources are read (sorted, no cap); when the Arch API could not be asked, the Arch mirror listing (geo.mirror.pkgbuild.com, same pattern) gives the version; if that also fails the item counts as could-not-check.
- Verification: bash -n, Python ast; real read-only scan twice while archlinux.org was failing: obs-studio 32.2.2 -> 33.0.0 listed both times, next to faugus, google-chrome, hyprland-noctalia, obs-advanced-scene-switcher.
- Rust: reads the repo databases (arch-extra.db), not the Arch API; the same audit is running there. Small check fix; LTS test week continues.
