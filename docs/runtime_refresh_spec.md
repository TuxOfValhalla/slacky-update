# Underpants runtime monthly refresh: shared behaviour spec (`underpants-runtime-refresh/1`)

Status: DRAFT 1, 2026-10-20. The owner approved the direction and decided D1-D3 on 2026-10-20 (section 17). Written for BOTH apps (CLAUDE.md 13.3):
`slacky-update-rs` (Rust) and `slacky-update` (legacy) implement exactly this and share NO code. The two copies
(`docs/runtime_refresh_spec.md` in each repo) are byte-identical. Detection, shared fixtures and the checks may exist as code (Rust H11-H14, H17); no builder or installer is open. Nothing here may touch the
owner's real install until the gates in section 13 are opened after a drill.

Words: MUST / MUST NOT bind both apps. FACT = read in code or measured read-only on the owner's machine on 2026-10-20,
with file:line. INFERENCE = reasoned, not proven. Rust paths are relative to the Rust repo, legacy paths to the legacy repo.

Scope: how the existing 3.7 GB monolith `/opt/underpants/runtime` (Slackware package `underpants-runtime-all`) avoids
going stale until the runtime bricks of `docs/runtime_spec.md` (H-series, 1.1) replace it. The refresh is a full rebuild of
the same profile from current repository packages, checked against every installed app, and installed through the same
package path as today. It is a stopgap. It never creates bricks, `runtime.next`, `runtime.prev` or `.db`.

## 1. Facts this spec is built on

| # | Fact | Evidence |
|---|---|---|
| F1 | The runtime's own record is `/opt/underpants/runtime/.gnomes/manifest.json`, `root:root`, schema 1, `profile` `all`, `version` `1.1`, `built` `2026-10-13T14:19:32Z`, 518 `packages` (name, version, repo, sha256, provides, files), 15 `host_only`, plus `repo_db_sha256`. There is NO `runtime_manifest.json` on the machine. | machine (read-only); writer `lib/gnomes_pacman.py:3942-3988` (`_write_runtime_manifest`); Rust reader `src/gnomes/manifest.rs:1-60` |
| F2 | The installed package is `underpants-runtime-all-1.1-x86_64-1_gnomes`: 893 MB compressed, 3.4 GB unpacked, 153,945 log lines; the tree is 3.7 GB with 113,790 files and 3,848 `.so*` names directly in `lib/`. No file in `runtime/lib` has a hardlink count above 1 today. | `/var/log/packages/...` header, `du`, `find -links +1` |
| F3 | The legacy builder is `TransmutationFactory.transmute_runtime_profile` (`lib/gnomes_pacman.py:5367-5629`): resolve with `standalone=True` (L5388), `space_precheck` (L5404), parallel download (L5409), `trust_gate` (L5412), unique work dir `mkdtemp(dir=build_dir_base())` (L5416; `build_dir_base` L527 is 0700, on disk, root `/var/cache/slacky-update/gnomes/build`, user `~/.cache/slacky-update/gnomes/build`), merge with clash report (L5478), host-only guard (L5481), relocation and `patch_elf_rpaths` (L5486-5489), headroom refusal (L5494), host-fit check (L5498), manifest (L5520), then `_run_makepkg_with_progress` (L4271) which runs the footprint guard and `tar --owner=0 --group=0 --numeric-owner`. The staging tree is deleted in `finally` (L5628). The package version is the constant `RUNTIME_PKG_VERSION = "1.1"` (L96). | code |
| F4 | Legacy installs it from `bin/gnomes:735-785` (`gnomes runtime install <profile>`): footprint `--verify-archive` and `--verify-host-paths --mode gnomes`, the run lock (`gnomes_pkgtools_lock`, `bin/gnomes:36`), then `sudo upgradepkg --install-new --reinstall`. There is NO snapshot and NO app startability check on this path today. | code |
| F5 | Rust has NO runtime builder: `docs/parity_status.md:125` says runtime install is MISSING; `src/gnomes/` only reads the manifest. The native app builder parts exist and are gated (`GNOMES_NATIVE_BUILD_OPEN=false`, `src/gnomes/build/mod.rs:54`). | code |
| F6 | Rust already detects runtime updates read-only: `detect_updates` (`src/gnomes/manifest.rs:233`) compares every non-host-only manifest member with the synced repo index by exact name; `recommended()` = a usual suspect moved or 20 % moved (L222). Suspects today: `icu openssl ffmpeg python qt6-base qt5-base glibc` (L228; same list `src/core/spidersense/runtime_guard.rs:115`). The hook `observe_runtime` (`runtime_guard.rs:564`) records one recorder line at most once in 24 h and keeps `runtime_drift.json` in Rust's own cache (L325). Nothing is shown, nothing is offered. Legacy has NO runtime update detection at all (no match in `check_backend.sh`, `slacky_sentinel.py`, `mod_packages.sh`). | code |
| F7 | Repo databases live in the sidecar cache `/var/cache/slacky-update/gnomes/db` (legacy `DEFAULT_CACHE_BASE`, `gnomes_pacman.py:35`) or `~/.cache/slacky-update/gnomes/db`; Rust reads them read-only through `existing_cache_dir` (`src/gnomes/engine.rs:170`). Shared by spec (`docs/standalone_inventory.md:39`). | code, machine |
| F8 | Each app keeps its OWN status file: legacy `/var/cache/slacky-update/status.json` (+ user cache, `lib/check_backend.sh:1097-1135`), Rust `/var/cache/slacky-update-rs` or `~/.cache/slacky-update-rs` (`src/core/status_store.rs:1-40`). | code |
| F9 | Both apps share the run lock `/run/lock/slacky-update.lock` (flock; legacy `lib/common.sh:1301-1327`, Rust `src/core/runlock.rs:19`). | code |
| F10 | Both apps take one pre-update snapshot per run after consent (legacy `create_pre_update_snapshot`, `lib/common.sh:1472`, rc 1 = failed, rc 2 = not possible). Rust `SnapshotSentinel::create_install_gate_snapshot` (`src/core/spidersense/snapshots.rs:678`) returns `Created / Skipped / Failed`; the root phase reuses the run's pre-snapshot (`has_pre_snapshot`, L669; `src/core/rootphase.rs:855-862`). | code |
| F11 | Installed app trees: 18 gnomes apps (`/opt/underpants/pkgs/<app>/{bin,lib,share,...}`) and 1 curated runtime-wrapped app, `openrgb` (`/opt/underpants/pkgs/openrgb/usr/bin/openrgb`, package `underpants-openrgb-1.1-x86_64-1_slacky`, launcher `/usr/bin/openrgb`). `/opt/underpants/common` does not exist. | machine |
| F12 | Runtime and app ELF files carry `DT_RUNPATH` (not `DT_RPATH`); e.g. vlc: `$ORIGIN/../lib:$ORIGIN/lib:$ORIGIN:/opt/underpants/common/lib:/opt/underpants/runtime/lib:...` | `readelf -d` |
| F13 | Rust checks: `startable::check` resolves `DT_NEEDED` in the gnomes wrapper order but follows only the app's own libraries (`src/gnomes/build/startable.rs:193-245`); `libver::analyse` checks `DT_VERNEED` against `DT_VERDEF` (`src/packages/curated_build/libver.rs:228`). Both hard-code `/opt/underpants/runtime/lib` (`startable.rs:23-31`, `libver.rs:28`). Legacy `slacky_symver.py` checks `DT_VERNEED` only (`check_elf`, L229) and takes `--runtime DIR` (L195-203); legacy has NO `DT_NEEDED` startability check. | code |
| F14 | `/` and `/home` are subvolumes `@` and `@home` of one Btrfs filesystem (`/dev/nvme1n1p7`); `/opt` is inside `@`. 159 GB free. | `findmnt`, `df` |
| F15 | `glib2`, `mesa`, `vulkan-icd-loader`, `libdrm`, `pipewire`, `libpulse`, `gnutls`, `alsa-lib`, `libva` are NOT in the runtime (host or host-only contract); `qt6-base 6.12.0-2.1`, `qt6-declarative`, `qt5-base`, `gtk3`, `gtk4`, `icu 78.3`, `ffmpeg 2:9.0.2`, `openssl 3.6.5`, `python 3.14.8`, `gstreamer 1.28.8`, `gst-plugins-base-libs`, `harfbuzz`, `freetype2`, `libxml2`, `protobuf`, `abseil-cpp`, `poppler`, `lua` ARE. | manifest |
| F16 | `space_precheck` (`gnomes_pacman.py:630`) checks the build dir (2.2 x unpacked) and `/opt` (1.1 x) SEPARATELY, even when both are on the same filesystem (F14). | code |
| F17 | `docs/runtime_spec.md` section 2 says the `Monolith` state allows NO writer; section 13 item 4 says existing writers refuse in non-brick states once bricks exist. | doc |
| F18 | Curated launchers differ slightly: Rust puts `/opt/underpants/common/lib` after the runtime (`recipes/runtime_wrapper.sh`), legacy does not (`lib/mod_gaming.sh:3885-3900`). With F11 (no `common`) the result is the same. | code |

## 2. Words used

- **Live**: `/opt/underpants/runtime` as installed. **Candidate**: the staged tree `<work>/pkg/opt/underpants/runtime` built this run.
- **Member**: an entry of the live manifest `packages[]` whose name is not in the manifest `host_only[].package` list.
- **Newer**: the repository has the member's exact name at a version that `vercmp` (epoch aware; Rust `gnomes/version.rs is_newer`,
  legacy `is_newer_version`, `gnomes_pacman.py:2451`) says is newer than the manifest version. A pkgrel-only change counts.
- **Gone**: the repository no longer has a member's name. Gone members do not make the runtime due; they are counted and recorded.
- **Age**: section 3.2. **Offerable**: due, eligible (section 4) and not suppressed by the state file (section 7).

## 3. Detection (read-only; check paths and the plan both use it)

### 3.1 Inputs

1. The live manifest (F1). Read with `O_NOFOLLOW`, regular file, at most 16 MB, JSON object, `schema == 1`, `version` vercmp >= `1.1`.
2. The repository index as both apps already load it from the sidecar cache (F7), exact-name lookup in repository priority order (the
   same lookup the resolver and `detect_updates` use). Detection MUST NOT download anything; it uses whatever the cache holds.
3. The clock (UTC). 4. The state file (section 7), read only.

### 3.2 Age source (exact)

`age_days = floor((now_utc - built) / 86400)` where `built` is the manifest field `built`, parsed as `YYYY-MM-DDTHH:MM:SSZ` (UTC).
- `built` missing or not parseable: use the manifest file's mtime; if that fails too, age is UNKNOWN and counts as >= 30.
- `built` more than 24 h in the future (clock wrong): age = 0, one recorder line `RR-CLOCK` per day, never due by age.
- The package database entry date and the directory mtimes are NOT used (a reinstall or a dedup would reset them).

### 3.3 Usual suspects (ABI move = "due now")

A suspect has an **ABI move** when its newer repository version differs from the manifest version in the first `depth` dot-separated
components of the upstream version (epoch stripped, pkgrel ignored). Example: `python` depth 2: `3.14.8 -> 3.14.9` is not a move,
`3.14.9 -> 3.15.0` is.

| Package | depth | Why it is a suspect |
|---|---|---|
| `qt6-base` | 2 | Symbol versions `Qt_6.N`: apps and curated packages built for 6.N+1 are refused or held until the runtime has it (OpenRGB case, `libver.rs:1`) |
| `qt6-declarative` | 2 | QML modules are tied to the Qt minor |
| `qt5-base` | 2 | Same as Qt 6 (5.15 rarely moves; kept for completeness) |
| `gtk4` | 2 | New API per minor; apps built against it need it |
| `gtk3` | 2 | Same (3.24 rarely moves) |
| `icu` | 1 | soname is the major (`libicuuc.so.78`, F15) |
| `ffmpeg` | 1 | libav* sonames follow the major |
| `openssl` | 2 | Symbol versions `OPENSSL_3.N.0` |
| `python` | 2 | `libpython3.N` soname and the `lib/python3.N` module path |
| `gstreamer`, `gst-plugins-base-libs` | 2 | Plugin ABI and registry per `1.N` |
| `harfbuzz` | 1 | New API without symbol versions: a newer app fails with an undefined symbol, which no check sees |
| `libxml2` | 2 | soname changed on a minor (2.14 -> `libxml2.so.16`) |
| `protobuf`, `abseil-cpp` | 1 | soname changes with every release |
| `poppler` | 1 | soname changes almost every release |

Not suspects, on purpose: `glibc` (never in the runtime, `CORE_EXCLUDES`; removed from the old list), `glib2` (host-provided, F15),
`mesa`, `vulkan-icd-loader`, `libglvnd`, `libdrm`, `pipewire`, `alsa-lib`, `gnutls` (host-only by the runtime contract, F15;
Slackware owns them), `freetype2` (stable soname `.so.6`, additive API). The table is data; both apps MUST carry it identically
(Rust replaces `USUAL_SUSPECT_NAMES` and `USUAL_SUSPECTS`; legacy adds the same table).

### 3.4 Decision

| Result | Condition |
|---|---|
| `not_applicable` | not eligible (section 4 E1-E3) |
| `unknown` | no repository index in the cache, or the manifest is unreadable |
| `due_now` | at least one suspect has an ABI move (any age) |
| `due` | age >= 30 days AND at least one member is newer |
| `nominal` | otherwise |

Clarified by the Rust implementation (2026-10-20): E1 includes a valid manifest, so an absent or invalid manifest is `not_applicable`; `unknown` is only a valid monolith with no repository index in the cache. E3 (the gate) does not change detection: with the gate closed the decision, the status key, the notice and the recorder lines all work (section 13). A suspect that is newer but has no ABI move only counts as an ordinary newer member. `suspects` in the status key and fixtures are sorted by package name, each `name old -> new` with the full pacman versions.

`due_now` wins over `due`. The 20 % ratio of `recommended()` is no longer a trigger for the refresh (it stays a recorder detail).
Then section 7 can turn `due`/`due_now` into `deferred` or `remembered_veto` for display and offering.

### 3.5 What a check path may do

The update check (legacy `check_backend.sh`; Rust update check / `PostUpdateCheck`, `src/main.rs:1343-1391`) and the tray MAY ONLY:
1. write the result into the app's OWN status file as key `runtime_refresh` (section 8.2); the key is NOT added to the counted keys
   (`COUNTED_KEYS`, `status_store.rs:36`; legacy `total` in `bin/slacky-update:227`), so package counts stay honest;
2. print one notice line in the check summary when the result is `due` or `due_now` and not suppressed (section 10);
3. show that line in the tray menu (no notification, no sound);
4. write recorder lines (section 11).
A check path MUST NOT build, download packages, call sudo, write `/opt`, or write the state file. Cron, the tray and login never start
a refresh.

## 4. Eligibility (E1, E2, E4 and E6 MUST hold; E3 is the gate; E5 is a warning only, else the refresh is not offered and the plan has no line)

| Code | Rule |
|---|---|
| E1 | Runtime state is the manifest-current monolith: manifest valid (3.1), `profile` names a known profile (`RuntimeManager.PROFILES`, Rust `RUNTIME_PROFILES`, `src/gnomes/tables.rs:349`), a package log `underpants-runtime-<profile>-*` exists |
| E2 | `docs/runtime_spec.md` state is `Monolith` (no `.bricks/layout.json`, no `Mixed`, no `Broken`). Once bricks exist the refresh is retired for good (section 12) |
| E3 | The app's refresh gate is open (section 13) |
| E4 | The run is interactive: a terminal on stdin, not `NON_INTERACTIVE`, not cron, not `--yes`/`--noconfirm`. An explicit answer is required; a refresh is never part of an unattended run |
| E5 | (decided D3, 2026-10-20) Not a condition. The snapshot lifeline is Btrfs root with snapper and a `root` config (the same test as `create_pre_update_snapshot`). Without it the refresh is STILL offered, with the one-sentence warning `RUNTIME_REFRESH_NO_SNAPSHOT_WARN` shown with the plan line and before the question (no snapshot; rollback means reinstalling the previous runtime package by hand). Recorder `RR-NO-SNAPSHOT` |
| E6 | Detection says `due` or `due_now` and the state file does not suppress it (section 7) |

## 5. The run (user phase, then root phase)

### 5.1 Plan and answer (user phase)

- One plan line, exactly `Underpants runtime refresh (monthly)` (i18n `RUNTIME_REFRESH_PLAN_LINE`), listed before the Gnomes apps line
  (legacy plan `bin/slacky-update:549-557`; Rust plan from `transaction.rs`). An offerable refresh counts as an active suite, so the plan
  appears even when it is the only item.
- It is answered with the rest: batch "yes" includes it; in step-by-step mode it gets its own question
  (`RUNTIME_REFRESH_PROMPT`, default Yes like the other suites).
- "No" (or skipped in step mode): record `declined` (section 7), print `RUNTIME_REFRESH_DEFERRED` once, continue the run.
- A run cut off before the refresh step records only `last_offered`; it is neither a yes nor a no.

### 5.2 Disk-space preflight (user phase, before any download)

Let `S` = sum of `ISIZE` and `C` = sum of `CSIZE` of the resolved plan (the same plan the build uses). The build dir is the app's
build base (legacy `build_dir_base`, Rust `~/.cache/slacky-update-rs/gnomes/build`).
- Build peak (downloads not yet cached + staging + package being written): `need_build = 2.2 * S + C_missing`, `C_missing` = CSIZE of
  plan packages not already in the package cache.
- Install peak on `/opt`: `need_opt = 1.1 * S + C` (new extents while the run's snapshot still holds the old tree, plus the archive).
- **Same filesystem** = the mounts holding the two paths have the same `major:minor` in `/proc/self/mountinfo` field 3 (Btrfs
  subvolumes of one filesystem share it; `stat().st_dev` does NOT, so it MUST NOT be used). INFERENCE, to be proven by the fixture
  `space_same_btrfs` and once on the machine read-only.
- Separate filesystems: both needs must fit, each on its own filesystem. Same filesystem: `free >= need_build + 1.1 * S`
  (the staging tree is kept for the root-phase re-check, 5.5, so both peaks overlap). This fixes F16 for the refresh; legacy
  `space_precheck` gets the same-filesystem rule (task 7K).
- On the owner's machine (`S` about 3.4 GB, `C` about 0.9 GB): about 12.4 GB on the shared Btrfs (159 GB free today).
- Not enough: `RUNTIME_REFRESH_NO_SPACE`, nothing downloaded, `last_result = no_space`, offered again next run.
- Exact numbers (so both apps print the same sentence and fixtures agree): factors are integer arithmetic, rounded up (`2.2*S` = `ceil(22*S/10)`, `1.1*S` = `ceil(11*S/10)`); on one filesystem the free value is the smaller of the two paths; `{need}` and `{free}` are GB = 10^9 bytes with one decimal, `need` rounded UP, `free` rounded DOWN; `{path}` is the build dir when only the build dir is short on separate filesystems, otherwise `/opt` (the shared filesystem is reported on `/opt`). If either path has no `mountinfo` line, assume the same filesystem.

### 5.3 Build the candidate (user phase, no root)

The existing proven engine, unchanged in what it produces, run as the user:
1. Load and sync the repo databases the way the app's gnomes engine already does.
2. Resolve the live manifest's `profile` with `standalone=True` (F3). Compute `candidate_basis` (section 7.3). If it equals a remembered
   veto, stop silently (recorder `RR-VETO-REMEMBERED`).
3. Download in parallel, trust gate (PGPSIG, DB SHA-256, CachyOS signed DB; legacy `trust_gate` L3816, Rust `gnomes/trust.rs`).
4. Unique 0700 work dir under the build base. Extract, flatten, merge with the clash report, host-only guard, relocation,
   `patch_elf_rpaths`, headroom refusal, host-fit check, manifest written with a new `built` (F3, same order).
5. Pre-swap startability check (section 6) on the staged candidate, BEFORE packaging. A veto ends the refresh here.
6. Package with the footprint guard and `tar --owner=0 --group=0 --numeric-owner`, name `underpants-runtime-<profile>-1.1-x86_64-1_gnomes.txz`
   (same name and version as today; see 5.7). Verify the archive: every entry `root:root` (footprint `--verify-archive`) and no path
   outside `/opt/underpants/runtime` or owned by another package (`--verify-host-paths --mode gnomes`). Record the archive SHA-256.
7. KEEP the staging tree until the root phase is done (difference to F3, which deletes it in `finally`; the builder gets a keep option).
Wrappers, RPATH strings, `/opt/underpants` paths, `doinst.sh` and the slack-desc stay exactly as today.

### 5.4 Order inside the run

The refresh is installed AFTER the Slackware base step (Sacred Slackware wait) and the kernel/driver steps, and BEFORE gnomes app installs
and curated installs. Reason: the host-fit and startability checks must see the final host libraries, and apps installed later in the same
run must start against the new runtime.

### 5.5 Root phase (as late as possible, one escalation)

1. The run lock is held (both apps hold it for the whole run, F9). Re-check the foreign package tool scan.
2. **Same base**: the live manifest `built` still equals the one detection used; if not (someone refreshed meanwhile) skip silently,
   recorder `RR-SKIP-CHANGED`.
3. **Re-check**: if any host package changed earlier in this run, run section 6 again on the kept staging tree against the now current host.
   A veto here leaves the live runtime untouched.
4. **Running apps** (decided D2, 2026-10-20: WARN and continue, never hold): scan `/proc/<pid>/maps` of every process
   except the updater's own process tree for a mapped path under `/opt/underpants/runtime/` or `/opt/underpants/pkgs/`. If one is found:
   `RUNTIME_REFRESH_RUNNING_WARN` naming the app (the `/opt/underpants/pkgs/<app>` name, else the process name; the first one found, one sentence), recorder `RR-RUNNING-WARN` (app, pid), and the refresh CONTINUES (the app may need a restart). The updater MUST first drop a runtime `LD_LIBRARY_PATH` from its own environment
   (Rust `escalate::scrub_runtime_loader_path`, `src/core/escalate.rs:85`; legacy 6A-316), so it never maps the runtime itself.
5. **Snapshot gate (B8)**: reuse this run's pre-update snapshot when it exists (same transaction id, F10); otherwise
   `create_install_gate_snapshot` / the legacy equivalent. `Failed` = refuse (`RUNTIME_REFRESH_SNAPSHOT_FAILED`), fail closed. `Skipped`
   (no Btrfs/snapper, D3) = continue without a snapshot: the user already saw `RUNTIME_REFRESH_NO_SNAPSHOT_WARN` when answering, recorder
   `RR-NO-SNAPSHOT`, state `snapshot` = 0. `/opt` is inside the root subvolume (F14), so a snapshot, when there is one, IS the rollback.
6. Verify the archive SHA-256 recorded in 5.3 step 6 (Rust: the order book copies staged files root-owned and checks the hash).
7. Exactly one `upgradepkg --install-new --reinstall <archive>` as root (Rust: new order-book step kind `RuntimeRefresh`, booked once).
8. Post-check: the installed manifest `built` equals the candidate's; run section 6 once more on the live tree (read-only). A new failure:
   `RUNTIME_REFRESH_POSTCHECK` with the snapshot number. No automatic rollback (restoring the snapshot is the user's choice and needs a reboot).
   upgradepkg failing: `RUNTIME_REFRESH_INSTALL_FAILED` with the snapshot number.
9. Back in the user process (never as root): write the state file (section 7) and the status key, then delete the work dir (staging + archive)
   on every exit path. The package download cache follows the existing cache rules.

### 5.6 Output

Silent when nominal, work-line style of `docs/output_style.md`: `Building the shared app runtime (518 packages)...OK`,
`Checking that your apps still start (19 apps)...OK`, `Installing the shared app runtime...OK`. No emoji, no banner change, no success
sentence; the final line stays exactly `All updates are completed`. Every problem is ONE plain sentence from section 10, details go to
the recorder/log.

### 5.7 Package name and version (decided in this spec)

The refresh keeps `underpants-runtime-<profile>-1.1-x86_64-1_gnomes` and installs with `--reinstall`, exactly the proven path of F4.
Age lives in the manifest `built`, not in the package name. Rejected alternative: bumping the build number per refresh (more change in
two apps for a cosmetic gain). Layout `2.x` stays reserved for bricks (`runtime_spec.md` section 7).

## 6. Pre-swap startability check

### 6.1 What is checked

- Every installed gnomes app: each directory `/opt/underpants/pkgs/<app>/` that has `bin/` or `lib/` (gnomes layout).
- Every curated runtime-wrapped app: each directory `/opt/underpants/pkgs/<id>/` that has `usr/` (the launcher layout of 6A-327 /
  `libver.rs:283`, F11).
- Every app tree STAGED for install later in this run (gnomes or curated with a runtime launcher), at its staging path.
- **Programs** = ELF64 x86-64 files with a `PT_INTERP` directly in `<app>/bin/` (gnomes) or `<id>/usr/bin/` (curated). An app without an
  ELF program (a script app such as lutris) uses as program the runtime interpreter its wrapper or shebang names under
  `/opt/underpants/runtime/bin/` (mapped to the candidate), if any.

### 6.2 Search order (one model for both apps)

For a `DT_NEEDED` name `N` of an ELF file `O` installed in directory `D`:
1. the wrapper's `LD_LIBRARY_PATH`, which the loader searches first for every object in the process:
   - gnomes: the nested folders the wrapper loop prepends (`lib/*/`, `lib/ghc-*/lib/*`, `lib/lua/*`, runtime `lib/ghc-*/lib/*`), then
     `<app>/lib`, `<app>/lib64`, `/opt/underpants/runtime/lib`, `/opt/underpants/runtime/lib64`, `/opt/underpants/common/lib`,
     `/usr/lib64/libproxy`, `/usr/lib64/pulseaudio`, `/usr/lib64/pipewire-0.3`, `/usr/lib64/samba`, `/usr/lib64`
     (the model of `startable.rs:131-150`);
   - curated launcher: `/opt/underpants/runtime/lib`, `/opt/underpants/runtime/lib64`, `/opt/underpants/common/lib`, the four host
     plugin folders, `/usr/lib64` (F18: an absent `common` changes nothing);
2. `O`'s own `DT_RUNPATH` entries, `$ORIGIN`/`${ORIGIN}` expanded to `D` (F12);
3. the directories of `/etc/ld.so.conf` and its `include` files (stand-in for `ld.so.cache`);
4. `/lib64`, `/usr/lib64`.
A file of the wrong class (not ELF64 x86-64) found in a directory is skipped and the search goes on (loader behaviour). A name containing
`/` is used as a path. **Candidate mapping**: every directory that starts with `/opt/underpants/runtime` is read from the candidate
tree instead (for the live baseline, from the live tree). `DT_RPATH` is treated like `DT_RUNPATH` but searched before step 1 (none exist
today, F12).

### 6.3 The closure and the rules

From each program, follow `DT_NEEDED` transitively through every library found inside the app tree OR inside the runtime (candidate or
live). Libraries found in host directories are leaves (Slackware answers for its own libraries). For every edge:
- **S1 needed**: `N` is found nowhere.
- **S2 version**: for every `DT_VERNEED` entry (soname, version) of a file in the closure, the provider that the same order picks
  defines `DT_VERDEF`s and lacks that version. Weak references (`VER_FLG_WEAK`) are skipped. A provider without version definitions
  is accepted (loader only warns).
- **S3 interpreter minor**: the candidate changes the `python` major.minor (from the manifest/plan versions) and an app tree has a non-empty
  `lib/python3.<old minor>/`; same rule for `lua` and `lib/lua/<old minor>/`. Compiled modules and module paths of that app would break.

**Veto = a NEW failure**: run the same check with the LIVE runtime (baseline) and with the CANDIDATE. A failure is the tuple
`(app, rule, file, soname, version)`. Any tuple present for the candidate and absent for the baseline is a veto. Failures that already exist
live never veto (they are the app's own problem, reported by its own startability note). The first new failure (sorted by app, then file)
names the app in `RUNTIME_REFRESH_VETO`; all new failures go to the recorder (`RR-VETO`, at most 50 entries with a count).

### 6.4 Out of scope (recorded, never a veto)

- `dlopen` plugins and modules that no program links: Qt plugins and QML, GStreamer, GIO modules, gdk-pixbuf and glycin loaders, GTK
  immodules, Python extension modules, `ossl-modules`, `sasl2`, `krb5`, `libproxy`, `webkit2gtk-4.1`. Their `DT_NEEDED` are scanned once in the
  candidate and the count of files with a missing library is recorded as `RR-PLUGINS-UNCHECKED {count}` (only when the count is higher than
  the live baseline).
- Unversioned symbols removed without a soname change (needs symbol tables; gnomes_spec L3, later).
- Data formats: caches, schemas, `runtime/etc`, fonts, icon themes. The GPU stack (host-only by contract).
- Apps that carry private copies of runtime libraries keep them; the refresh does not reach them (runtime_spec Q15).

### 6.5 Cost

Pure in-process ELF reading (headers, dynamic and version sections), nothing executed. Budget: 60 s on the owner's machine for live + candidate;
measured and written to the recorder (`RR-CHECK-TIME`). Legacy's reader should read only the needed sections instead of the whole file
(`slacky_symver.py:49` reads the whole file today).

## 7. The shared state file

### 7.1 Path, ownership, writer

- Path: `${XDG_STATE_HOME}/underpants/runtime_refresh.json` when `XDG_STATE_HOME` is absolute, else `$HOME/.local/state/underpants/runtime_refresh.json`.
  A run whose effective uid is 0 (someone ran the whole update as root) uses `/var/lib/underpants/runtime_refresh.json`. The neutral folder
  name `underpants` belongs to neither app (shared by spec, to be listed in `docs/standalone_inventory.md` section B).
- Owner: the writing user, file 0644, folder 0755. Never written by the root phase (5.5 step 9), so a user's state is never root-owned.
- Writers: ONLY the user process of a full update run that holds the run lock (F9). The two apps never run at the same time, so they cannot
  race; a check path or the tray only reads.
- Write: temp file `.<name>.<pid>.tmp` created with `O_EXCL` in the same folder, fsync, rename. Read: `O_NOFOLLOW`, regular file, owned by the
  effective uid or root, not group/other-writable, at most 64 KB, JSON object with the `spec` string. Anything else is treated as absent
  (offer as if new) plus one recorder line per day `RR-STATE-IGNORED`.

### 7.2 Format

```json
{
  "schema": 1,
  "spec": "underpants-runtime-refresh/1",
  "runtime_built": "2026-10-13T14:19:32Z",
  "last_offered": "2026-11-14T08:00:00Z",
  "declined_at": "",
  "last_result": "none",
  "last_result_at": "",
  "veto": {"candidate_basis": "", "apps_basis": "", "app": "", "rule": "", "detail": ""},
  "snapshot": 0,
  "writer": "slacky-update-rs 80_slacky"
}
```
- `runtime_built`: the live manifest `built` the record refers to. A different live value (anyone rebuilt the runtime) resets `declined_at`,
  `last_result` and `veto`.
- `last_result`: `none | installed | declined | vetoed | build_failed | no_space | snapshot_failed | install_failed | postcheck_failed`.
- `snapshot`: the snapshot number used for the last install attempt (0 = none). `writer`: app name and build, for the log only.
- Unknown fields MUST be kept on rewrite; missing fields take the defaults above.

### 7.3 Suppression rules

- **Weekly re-ask**: `declined_at` within the last 7 days (and `runtime_built` unchanged) suppresses the offer, for `due` AND `due_now`.
  Display state `deferred`.
- **Remembered veto**: `last_result` is `vetoed` and both `candidate_basis` and `apps_basis` equal the current values: suppressed (no download,
  no build), display state `remembered_veto`, one recorder line per day. A new repository version of any member or a changed app set lifts it.
  - `candidate_basis` = lowercase hex SHA-256 of the lines `<name>=<newest repository version>\n`, sorted byte-wise, over all members that
    the repository has (gone members left out). Cheap: it comes from detection, no resolve needed.
  - `apps_basis` = lowercase hex SHA-256 of the sorted lines `<package id>\n` of every installed package log whose name starts with
    `underpants-` and not `underpants-runtime-`.
- `no_space`, `build_failed`, `snapshot_failed`: never suppress; offered again next run.

## 8. Status and record formats

### 8.1 Manifest

Unchanged (schema 1). The refresh writes it through the existing writer with a new `built`. No new fields are required.

### 8.2 Status key (each app's own status file)

```json
"runtime_refresh": {"state": "due", "age_days": 37, "newer": 42, "checked": 503, "gone": 1,
                    "suspects": ["qt6-base 6.12.0-2.1 -> 6.13.0-1.1"], "built": "2026-10-13T14:19:32Z",
                    "checked_at": "2026-11-19T07:00:00Z"}
```
`state`: `nominal | due | due_now | deferred | remembered_veto | unknown | not_applicable`. Advisory only: the full update recomputes the
decision live at plan time and never trusts this key. After an install the run's status reconcile sets `nominal`.

## 9. Both apps, same behaviour

- Same detection table and thresholds (section 3), same eligibility (4), same order and gates (5), same check model (6), same state file (7),
  same texts (10). Neither app calls, execs or path-references the other; they share only this spec, the run lock, the state file, the
  sidecar database cache (F7) and `/opt/underpants`.
- Whichever app runs the refresh, the other sees the new manifest `built` and resets its view; the state file keeps the weekly rule
  common, so the user is asked at most once a week in total, not once per app.
- The existing manual path `gnomes runtime install` (F4) stays, but in legacy it SHOULD get the same startability check and snapshot gate
  (task 7L); it resets the age like a refresh.

## 10. Messages and i18n keys (en and nb; plain English, one sentence, no emoji)

| Key | en | nb |
|---|---|---|
| `RUNTIME_REFRESH_PLAN_LINE` | Underpants runtime refresh (monthly) | Oppfrisking av Underpants-runtime (månedlig) |
| `RUNTIME_REFRESH_PROMPT` | Refresh the shared app runtime now? It downloads about {size} and takes a few minutes. [Y/n] | Vil du friske opp den delte app-runtimen nå? Den laster ned omtrent {size} og tar noen minutter. [J/n] |
| `RUNTIME_REFRESH_NOTICE` | The shared app runtime is {days} days old; the next full update offers to refresh it. | Den delte app-runtimen er {days} dager gammel; neste fulle oppdatering tilbyr å friske den opp. |
| `RUNTIME_REFRESH_NOTICE_NOW` | A core library of the shared app runtime has a new version; the next full update offers to refresh it. | Et kjernebibliotek i den delte app-runtimen har en ny versjon; neste fulle oppdatering tilbyr å friske den opp. |
| `RUNTIME_REFRESH_DEFERRED` | The runtime refresh is offered again in 7 days. | Oppfriskingen av runtimen tilbys igjen om 7 dager. |
| `RUNTIME_REFRESH_WORK_BUILD` | Building the shared app runtime ({count} packages) | Bygger den delte app-runtimen ({count} pakker) |
| `RUNTIME_REFRESH_WORK_CHECK` | Checking that your apps still start ({count} apps) | Sjekker at appene dine fortsatt starter ({count} apper) |
| `RUNTIME_REFRESH_WORK_INSTALL` | Installing the shared app runtime | Installerer den delte app-runtimen |
| `RUNTIME_REFRESH_VETO` | The runtime refresh was skipped because {app} would not start with it; your current runtime stays. | Oppfriskingen av runtimen ble hoppet over fordi {app} ikke ville startet med den; den nåværende runtimen beholdes. |
| `RUNTIME_REFRESH_NO_SPACE` | The runtime refresh needs {need} GB free on {path} but only {free} GB is free, so nothing was changed. | Oppfriskingen av runtimen trenger {need} GB ledig på {path}, men bare {free} GB er ledig, så ingenting ble endret. |
| `RUNTIME_REFRESH_BUILD_FAILED` | The runtime refresh could not be built, so your current runtime stays; the details are in the log. | Oppfriskingen av runtimen kunne ikke bygges, så den nåværende runtimen beholdes; detaljene står i loggen. |
| `RUNTIME_REFRESH_RUNNING_WARN` | {app} is running and may need a restart to use the refreshed runtime. | {app} kjører og må kanskje startes på nytt for å bruke den oppfriskede runtimen. |
| `RUNTIME_REFRESH_SNAPSHOT_FAILED` | The runtime refresh was skipped because no safety snapshot could be made; nothing was changed. | Oppfriskingen av runtimen ble hoppet over fordi det ikke kunne lages et sikkerhetsbilde; ingenting ble endret. |
| `RUNTIME_REFRESH_NO_SNAPSHOT_WARN` | This system has no safety snapshot, so to undo the runtime refresh you would have to reinstall the previous runtime package by hand. | Dette systemet har ikke sikkerhetsbilder, så for å angre oppfriskingen av runtimen må du installere den forrige runtime-pakken på nytt for hånd. |
| `RUNTIME_REFRESH_INSTALL_FAILED` | The runtime refresh did not finish installing; to undo it, roll back to safety snapshot #{number}. | Oppfriskingen av runtimen ble ikke ferdig installert; for å angre, rull tilbake til sikkerhetsbilde #{number}. |
| `RUNTIME_REFRESH_POSTCHECK` | The runtime was refreshed but {app} may not start; to undo it, roll back to safety snapshot #{number}. | Runtimen ble friskt opp, men {app} starter kanskje ikke; for å angre, rull tilbake til sikkerhetsbilde #{number}. |

`RUNTIME_REFRESH_NO_SNAPSHOT_WARN` is shown with the plan line and before the question whenever the refresh is offered on a system without snapshots (D3); it is not part of the check notice.
Both apps add the keys to `locales/en.json` and `locales/nb.json` (legacy: its own locale files). Nothing is printed for `nominal`,
`deferred` (except the one `DEFERRED` line at the moment of the "No"), `remembered_veto`, or a successful install.

## 11. Flight recorder / log events

Rust: `SpiderLogger`, category `Runtime`. Legacy: its log file (`LOG_FILE`) with the prefix `SpiderSense: runtime-refresh`. One line each:

| Code | When |
|---|---|
| `RR-DUE`, `RR-DUE-NOW` | detection result changed to due / due_now (with age, newer count, suspects); at most once per day |
| `RR-OFFERED`, `RR-DECLINED`, `RR-ACCEPTED` | plan time |
| `RR-SPACE` | space preflight failed (need, free, path, same-filesystem yes/no) |
| `RR-BUILD-OK`, `RR-BUILD-FAIL` | after 5.3 (package count, size, time; or the builder's reason) |
| `RR-CHECK-TIME` | check duration, programs and files checked |
| `RR-VETO` | new failures (app, rule S1/S2/S3, file, soname, version), at most 50 plus a count |
| `RR-VETO-REMEMBERED` | an offer suppressed by 7.3 |
| `RR-PLUGINS-UNCHECKED` | 6.4 plugin count above baseline |
| `RR-RUNNING-WARN` | 5.5 step 4 (app, pid) |
| `RR-NO-SNAPSHOT` | 5.5 step 5 / E5: refresh offered or run without a snapshot lifeline |
| `RR-SNAPSHOT-FAIL`, `RR-SNAPSHOT-REUSED`, `RR-SNAPSHOT-MADE` | 5.5 step 5 (number) |
| `RR-INSTALLED`, `RR-INSTALL-FAIL`, `RR-POSTCHECK-FAIL` | 5.5 steps 7-8 (old built, new built, snapshot) |
| `RR-SKIP-CHANGED`, `RR-CLOCK`, `RR-STATE-IGNORED` | 5.5 step 2, 3.2, 7.1 |

## 12. Relation to `docs/runtime_spec.md` and the road to bricks

1. **Amendment needed** (F17): `runtime_spec.md` section 2 must say that in state `Monolith` the ONLY allowed writer is this refresh, which
   replaces the whole monolith through the existing package and never creates `.bricks`, `runtime.next`, `runtime.prev`, `.db` or
   `/opt/underpants/.runtime.lock`. Until that line is added the two specs disagree; the implementing agents add it with the owner's OK.
2. **Retirement**: E2 disables the refresh as soon as `.bricks/layout.json` exists (states `Bricks`, `Mixed`, `Broken`). Brick updates
   (`runtime_spec.md` section 9) then take over; the state file and the `runtime_refresh` status key are no longer written (readers ignore them).
3. **Reuse**: the section 6 check is the per-app half of brick pre-flight P5 (same search order, same candidate mapping); the brick work adds
   the runtime-wide `baseline-unresolved.json` and P6-P11. The suspects table (3.3) feeds the brick ABI keys (`abi` / `built_against`).
4. **Migration build**: the migration (runtime_spec section 12 step 2) builds the same profile from the same repositories; the refresh builder
   is that builder with ownership recording added (runtime_spec Q2). The refresh MAY record per-file ownership into the work dir for
   measurement, but MUST NOT install it.
5. **Freshness before migration**: a refreshed monolith is the best starting point for the migration diff (runtime_spec section 12 step 3): fewer
   version differences between the live tree and the brick build.
6. `docs/gnomes_spec.md` (draft 0.1, 2026-10-13, Option A directly, `runtime.d/<gen>`) is older than the owner's 2026-10-17 decision
   (runtime_spec Q1-Q18, Option C first); this spec follows runtime_spec.

## 13. Gates

- Rust: `RUNTIME_REFRESH_OPEN: bool = false` (beside the other gates; white paper chapter 25 list). Closed = detection, status key, notice and
  recorder work; no plan line, no build, no install.
- Legacy: the same switch as a constant in its runtime code (default off), same meaning.
- Opened by the owner, one app at a time, after a drill on the owner's machine (legacy first, per the "legacy first" rule), with a snapshot.

## 14. Risk table

| Option | Risk | Mitigation / size |
|---|---|---|
| Do nothing | The runtime ages: new app and curated versions built against newer Qt/OpenSSL/harfbuzz are refused or held (`libver` waiting list), more apps bundle private copies (disk, 202 differing copies already, CLAUDE.md 12.1), security fixes in pooled libraries (openssl, libxml2, poppler, ffmpeg) never reach the apps | High over months; grows silently |
| Do nothing | The only update path stays the manual `gnomes runtime install`, which has no snapshot and no startability check (F4) | Medium; user-run |
| Refresh | No snapshot lifeline on this system (D3) | Offered with a warning; rollback is reinstalling the previous runtime package by hand. Residual risk accepted by the owner |
| Refresh | A candidate breaks an app at start-up | Section 6 veto on new S1/S2/S3 failures; live untouched; snapshot rollback |
| Refresh | A plugin-only break (dlopen) passes the check | Out of scope by design; recorded; the snapshot is the rollback; plugin rules come with bricks P7 |
| Refresh | Running apps load a half-new tree (upgradepkg replaces files one by one) | 5.5 step 4: the app is named in one sentence and may need a restart (D2: warn, no hold); the snapshot is the way back. Residual risk accepted by the owner |
| Refresh | Disk fills on the shared Btrfs (old extents held by the snapshot for up to 47 h) | 5.2 same-filesystem sum; 47 h pruner frees it |
| Refresh | 900 MB download and a few minutes of build every month | Only when due; offer, never automatic; remembered veto avoids repeat builds |
| Refresh | Two apps diverge on `/opt/underpants` | One package path, one run lock, one state file, one spec, shared fixtures |
| Refresh | Host library changes in the same run invalidate the check | 5.4 order and 5.5 step 3 re-check |
| Refresh | A same-user change of the staging tree between check and install | Archive SHA-256 pinned at build (5.3 step 6, 5.5 step 6); residual risk accepted (same user) |
| Refresh | Snapshot restore also undoes the other updates of that run | Existing model for every snapshot-gated step; said in the manual |
| Refresh | Hardlinks from `gnomes deduplicate` would let a reinstall change app copies | INFERENCE: tar unlinks before writing, so app copies keep the old inode; none exist today (F2); fixture `dedup_hardlink` proves it |

## 15. Test plan (shared fake-root fixtures)

Location: Rust `tests/golden/runtime_refresh/<case>/` (committed like `tests/golden/runtime_spec/`), legacy `docs/runtime_refresh_fixtures/<case>/`
(byte-identical copy; `tests/` is gitignored there). Each case: `root/` (fake root, tiny fake contents), `input.json` (now, repository index as
`{name: version}`, flags such as interactive, gate, snapshot outcome, host changed), `expected.json`. Both apps MUST reproduce every
`expected.json`. Rust builds the machine-shaped base with a new `testkit::realistic::underpants_runtime(fr)` builder (constants copied from F1,
F2, F11, F12, F14; never read from the machine at test time); the committed fixture is its output. ELF fixtures are tiny synthetic ELF64 files
(Rust `curated_build::elf::fixture`), committed as bytes so legacy reads the same files.

Detection (expected: `state`, `age_days`, `suspects`, `newer`, `gone`):
`fresh_nominal` (age 5, none newer), `old_nominal` (age 40, none newer), `old_due` (age 40, pkgrel-only newer), `young_suspect_patch` (age 5,
python 3.14.8 -> 3.14.9: nominal), `young_suspect_abi` (qt6-base 6.12 -> 6.13: due_now), `epoch` (`1:3.24.52` vs `3.24.60`: not newer),
`host_only_skipped` (mesa newer but host-only), `gone_member`, `built_unparseable` (age unknown, newer -> due), `clock_future`,
`no_manifest` (not_applicable), `bricks_present` (not_applicable), `no_index` (unknown).

State (expected: offerable yes/no, display state): `deferred_3_days`, `deferred_8_days`, `deferred_reset_by_rebuild`, `veto_remembered`,
`veto_lifted_new_version`, `veto_lifted_new_app`, `state_symlink_ignored`, `state_wrong_owner_ignored`, `state_malformed_ignored`,
`unknown_fields_kept`.

Startability (expected: veto yes/no, first app, sorted failure tuples):
`apps_ok`, `needed_removed` (S1), `version_removed` (S2, Qt_6.12), `preexisting_failure_no_veto`, `private_copy_shields`, `curated_launcher`
(openrgb shape), `transitive_runtime` (app -> runtime libA -> missing libB), `host_leaf_not_followed`, `wrong_class_skipped`, `runpath_origin`,
`python_minor_change` (S3), `lua_minor_change` (S3), `weak_version_skipped`, `plugin_only_missing` (no veto, plugin count recorded),
`staged_app_included`, `script_app_uses_runtime_python`.

Space (input: mountinfo lines, free bytes, S, C): `space_separate_ok`, `space_same_btrfs` (subvolumes, sum applies), `space_same_fail`
(expected sentence values).

Flow (fake root, stubbed `upgradepkg`, `snapper`, `/proc`; expected: calls made, files changed, state written):
`not_interactive` (no offer, no state write), `yes_flag` (no offer), `gate_closed` (status key and notice only), `declined` (state
`declined_at`, one `DEFERRED` line), `veto_live_untouched` (hash of the fake live tree unchanged, no sudo), `snapshot_failed` (no upgradepkg),
`no_snapshot_warn` (offered with the warning, install goes on, state `snapshot` 0), `running_warn` (fake `/proc/<pid>/maps` maps runtime; updater's own pid excluded; one warning, install goes on), `skip_changed`,
`install_ok` (exactly one `upgradepkg --install-new --reinstall <archive>`, after the Slackware step and before the gnomes step, state
`installed`, work dir gone), `install_fails` (sentence with snapshot number), `postcheck_fails`, `dedup_hardlink` (a hardlinked app copy keeps
its old bytes after a reinstall in the fake root), `check_path_never_writes` (the check and tray paths never write `/opt`, the state file or
call sudo; Rust also as a guard test next to `install_output_guard.rs`).

i18n: every key of section 10 present in `en` and `nb` of both apps.
Fixture format (as committed by Rust, the reference for legacy): `tests/golden/runtime_refresh/<case>/{input.json,expected.json}` plus `root/`, `candidate/`, `staged/<app>/`, `state/` as the case needs; `input.json` has `kind` = `detection` | `state` | `startability` | `space`; a harness compares every key `expected.json` names. Startability failures are tuples `{app, file, rule, soname, version}` sorted by app, file, rule, soname, version; `file` is relative to the app folder, or `runtime/<path below the runtime>` for a runtime file; S1 has an empty `version`, S3 has soname `python`|`lua` and version `old -> new` (major.minor). The flow cases (plan, build, install) are written with the offer work (H16 / 7N).
Policy: Rust keeps the tests (`src/**/*_tests.rs`); legacy runs a stdlib-only Python test script against the fixtures, 3 minute timeout,
script deleted after green, fixtures kept.

## 16. Task IDs (proposed; `rs_and_legacy_roadmap.md` is NOT edited by this spec)

Free today: Rust `H11`+ (H0-H10 used), legacy `7J`+ (7A-7I used).

| Rust | Legacy | Task |
|---|---|---|
| H11 | 7J | Detection: suspects table, decision of 3.4, status key, check notice, recorder lines; gate closed |
| H12 | 7K | Space preflight with the same-filesystem rule (5.2); legacy also fixes `space_precheck` (F16) |
| H13 | 7L | Startability check of section 6 with candidate mapping (Rust: extend `startable` + `libver` with a runtime root and runtime follow; legacy: add `DT_NEEDED` closure to `slacky_symver.py`); legacy also uses it in `gnomes runtime install` |
| H14 | 7M | State file (section 7) and suppression rules |
| H15 | (exists) | Rust native runtime builder: port `transmute_runtime_profile` (F3) on top of `gnomes/build` (fetch, merge, relocate, elfpatch, symbols, trust, footprint), keep-staging option, gate `RUNTIME_REFRESH_OPEN` |
| H16 | 7N | Plan line, answer, order (5.4), root phase (Rust order-book step `RuntimeRefresh`), running-app warning, snapshot gate, post-check, output |
| H17 | 7O | Shared fixtures of section 15 and the `realistic` builder; runtime_spec section 2 amendment (12.1); standalone_inventory entry for the state file |
| H18 | 7P | Drill on the owner's machine (owner runs it, snapshot first), then the owner opens the gate |

Suggested order: legacy 7J, 7K, 7L, 7M, 7N, 7O, then the 7P drill; Rust H11-H14 and H17 in parallel (no gate needed), H15-H16 after,
H18 last.

## 17. Owner decisions (few)

| ID | Question | Decision (2026-10-20) |
|---|---|---|
| D1 | Rust has no runtime builder (F5). Port it now (H15, large), or let Rust detect and show the notice only until the port is done? | DECIDED: legacy first. Rust only DETECTS and shows the notice (status key, check/tray notice, recorder line) until its native builder (H15) passes a drill. H15 and H16 are not built now. Legacy is the first app that offers |
| D2 | A process maps the runtime (for example claude-desktop, which runs all the time): hold the refresh and name the app, or warn and continue? | DECIDED: warn and continue. One sentence names the app (it may need a restart); the refresh is not held (5.5 step 4) |
| D3 | No Btrfs snapshot possible (no Btrfs, no snapper, or no `root` config): offer anyway with only the package path, or do not offer? | DECIDED: offer anyway WITH a warning (one sentence: no snapshot, rollback means reinstalling the previous package by hand), E5 and 5.5 step 5 |
| D4 | Amendment of `docs/runtime_spec.md` section 2 so that the monolith refresh writer is allowed (12.1) | DECIDED: approved, one line (task H17 / 7O) |
