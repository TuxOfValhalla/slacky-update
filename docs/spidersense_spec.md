# Spider-Sense contract (SPEC_VERSION 1, draft 0.3, 2026-10-14)

Shared contract for slacky-update (legacy, bash + python3) and slacky-update-rs (Rust). Both repos carry an identical
copy of this file. It names behaviour, files and formats; it contains no code. Neither app executes the other, with
one exception decided by the owner on 2026-10-13: the Underpants Gnomes pacman sidecar (`gnomes`,
`gnomes_pacman.py`) may be called by the Rust app.

Sources: `docs/spidersense_study/` (studies A, B, C, D and the gap map), `docs/audits/2026-10-13/AUDIT_spidersense.md`,
owner decisions 2026-10-12/13/14 in `claude_workdoc.md`. Status: DRAFT for owner review. Section 3.1 says per event
whether the Rust app sends it today; everything else is the target unless a roadmap task says it is done.

Amendment J1 to 0.3 (2026-10-14, owner decision; the draft number stays 0.3 because a Rust test pins it): the Guardian rule "never touch `.new` prompts" becomes "only with the
user's consent, through the base store and the policy matrix" (1, 3.1 `base.done`, 4 B1, new 13); the base store has its own
format spec, `docs/config_store_spec.md` (13).

Changes in 0.3 (2026-10-14): events mapped to the Rust enum with their dispatch sites (3.1); HOLD verdict shape and the
interim rule "a guard's hold still stops the run until the pipeline handles holds" (3.2); shared marker and order
files moved to the neutral `/var/lib/slacky-boot/` with a read-old/write-new transition (6); logs per app (6, 7);
recorder schema as written by the Rust recorder, level ERROR added (7); exit codes as implemented (9).

## 1. Mission and rules

Spider-Sense is the quiet sentinel of a full system update. It is silent while everything is nominal and acts only
when a cliff edge approaches. Four jobs:

1. **Seer**: before anything changes, compute what will happen and hold back only the dangerous part.
2. **Orderer**: run the update in a fixed dependency order (Slackware base first, boot chain last).
3. **Bookkeeper**: record every action, hold and refusal in one flight recorder.
4. **Guardian**: never touch official Slackware packages, never taint the base, never leave the machine unbootable, never
   force a decision on the user. A waiting `.new` configuration file is touched ONLY with the user's explicit consent (a typed
   yes; no terminal or `-y` means: keep the user's file, leave the `.new`), only through the base store and the policy matrix
   (section 13), and only with an undo (journal plus backup). Without that consent the `.new` file is never read for
   change, moved or removed.

Hard rules:

- R1 Plan, consent, execute. Nothing changes the system before the user accepts the plan once. Checks in the plan
  phase are read-only (they may write caches and the log only).
- R2 Hold, do not abort. A problem holds its own scope and everything that depends on it; independent parts proceed.
- R3 Refuse (VETO) only to protect a root invariant (section 3.4).
- R4 Silent on success. The console shows WARN, HOLD and VETO lines and the final line `All updates are completed`.
- R5 Speed is a quality bar. Every check has a tier and a time budget (section 8). A check that cannot meet its
  budget moves to the background tier or to the Rust app only.
- R6 One sentence per message, plain language, no emoji (section 7).

## 2. Phases of every mutating operation

| Phase | What happens | May change the system |
|---|---|---|
| PLAN | read caches, refresh metadata, build the forecast, run checks, compute holds | no (cache + log only) |
| CONSENT | the user sees one plan with holds and warnings and answers once | no |
| EXECUTE | snapshot, then the stages of section 4 in order | yes |
| FINISH | post snapshot, summary, exit code, restart advice | caches, log, snapshot |

## 3. Events, verdicts, scopes

### 3.1 Events. An event exists only if both apps emit it (checked by section 9).

Spec events and their Rust counterpart (`HookEvent` in `src/core/spidersense/hooks.rs`). The Rust dispatch table
(`DISPATCH_TABLE` in `src/core/spidersense/verify.rs`) is the source of truth for listeners and sites; a unit test
keeps this table and that one equal. "live" = sent today; "planned" = site decided, not wired yet (the self-test
reports it as WAITING and fails).

| id | Rust `HookEvent` | emitted when | verdicts allowed | Rust listeners | Rust dispatch site (status) |
|---|---|---|---|---|---|
| `plan.begin` | PreUpdateCheck | a check or mutating operation starts, before any network access | WARN, HOLD | HardwareTierLockHook, NvidiaIntegrityHook, UnderpantsRuntimeHook, BootSealHook | `src/main.rs` `main`, `--check` flow before the first request (planned, main.rs owner) |
| `plan.horizon` | PostUpdateCheck | after metadata refresh (slackpkg update, repo databases), status cache written | WARN, HOLD | MultilibIntegrityHook, HolyTrinityHorizonHook, UnderpantsRuntimeHook, IntegrityAuditHook | `src/main.rs` `main`, `--check` flow after the status cache; passes the fetched repo listings (planned, main.rs owner) |
| `plan.ready` | PreUpgradeTransaction | forecast assembled, before the consent prompt | WARN, HOLD, VETO (only if a root invariant is already broken) | MultilibIntegrityHook, HardwareTierLockHook, HolyTrinityHorizonHook, ActiveKernelImmunityHook, BtrfsSnapshotLifelineHook (placeholder), RocmOpenClIntegrityHook, NvidiaIntegrityHook, UnderpantsRuntimeHook, FootprintGuardHook, TypeDamageHoldHook, OwnershipAuditHook, BootSealHook | `src/core/transaction.rs` `run_with_options` step 4c (live) |
| `tx.begin` | (none yet) | after consent, before the snapshot | HOLD | - | Rust: not modelled as a hook event yet |
| `stage.pre:<node>` | PreDkmsBuild for `stage.pre:dkms` | before each stage | HOLD, VETO | DkmsTargetHook | `src/core/spidersense/orchestrator.rs` `execute_consolidated_dkms` start (planned, orderer W2-B) |
| `stage.post:<node>` | MultilibAudit for `stage.post:multilib` | after each stage, with its result | WARN, VETO (read-only verification) | MultilibIntegrityHook | `src/core/transaction.rs` `run_with_options`, after the Slackware suite when glibc changed, stage B2 (planned, W1-A) |
| `base.done` | SacredSlackwareWait | Slackware base finished, `.new` files left for the user | PASS or WARN (count of `.new` files waiting; touched only after consent, section 13; the base store may capture their stock text) | SacredSlackwareBaseHook | `src/core/transaction.rs` `run_with_options`, Suite::Slackware arm after `execute_slackware_update` (planned, W1-A) |
| `kernel.deployed` | PostKernelDeploy | kernel, headers or module files landed; carries the deployed releases and `initramfs_built` | HOLD of `kernel:<v>` (kernel triad incomplete), WARN (headers missing) | KernelTriadHook | `src/core/transaction.rs` `execute_hardening_stages` after the initramfs step; later the orderer between D3 and C1 (planned, W1-A) |
| `boot.pre-commit` | ConsolidatedHardening | new menu and boot loader staged as `.next`, not yet live | VETO | ActiveKernelImmunityHook, ParallelDracutHook, RootInvariantHook, Blake2bResealHook (report-only until G7), RocmOpenClIntegrityHook, NvidiaIntegrityHook | `src/core/transaction.rs` `execute_hardening_stages` before the initramfs/menu step (planned, W1-A) |
| `boot.committed` | (none yet) | the menu + boot loader pair is live and verified | WARN | - | Rust: G7 commit |
| `tx.end` | (none yet) | all stages finished or held | sets the exit code | - | Rust: pipeline end |
| `reboot.pre` | PreReboot | before restart advice or a restart prompt | WARN; VETO removes the default-yes only | RootInvariantHook, PreRebootSanityHook | `src/core/transaction.rs` `run_with_options` step 10 before the restart prompt (planned, W1-A) |
| `watch.drift` | InotifyDrift | a watcher sees an outside change (cron, tray, inotify, `--heal`) | WARN, log | RootInvariantHook, Blake2bResealHook, RocmOpenClIntegrityHook, NvidiaIntegrityHook, UnderpantsRuntimeHook | `src/main.rs` `dispatch_spidersense_heal` (live) and `src/core/spidersense/sentinel.rs` `start_watchdog` (live) |
| `watch.weekly` | (none yet) | weekly probes (cron.weekly or timestamp-gated) | WARN, log | - | Rust: weekly framework |

The recorder `ev` field carries the spec id (`HookEvent::spec_id()` in Rust).

Hook rules (both apps): hooks only read and report; repairs are returned as orders and run only after consent. Only
the guards may HOLD or VETO (Rust `VETO_GUARDS`: HardwareTierLockHook, HolyTrinityHorizonHook,
ActiveKernelImmunityHook, RootInvariantHook, PreRebootSanityHook, KernelTriadHook, FootprintGuardHook, TypeDamageHoldHook); a HOLD or VETO from any other check
is shown as a WARN. A check that fails is a WARN, never a VETO. A placeholder check must declare itself (Rust
`SpiderSenseHook::stub`); an event with only placeholder listeners fails the self-test. Hooks never use the network:
upstream listings are fetched by the caller and passed in (Rust `HookContext::horizon`).

### 3.2 Verdicts

| verdict | meaning |
|---|---|
| PASS | nothing to say (silent) |
| WARN(scope, msg) | printed once, the operation proceeds (Rust: `Verdict::Intervention`) |
| HOLD(scope, reason, fix) | the scope and its dependents leave the plan; the previous good state stays; recorded in `held.json`; re-evaluated next run; never a prompt. Rust: `Verdict::Hold(HoldNotice { scope: Vec<String>, reason, fix: Option<String> })`; holds of one dispatch are aggregated (`EventReport::holds()`, `held_scopes()`) |
| VETO(msg) | stops the chain of that scope (never the Slackware base); boot-chain VETO sets the "do not restart" state |
| ERROR | the check itself failed: non-critical check = WARN and continue; critical check = HOLD of its own scope |

Interim rule (owner decision 2026-10-14): until a pipeline removes only the held scope, a guard's HOLD is handled like a
VETO, so the whole run still stops (safe side). Rust exposes this as the pipeline view (`HookOutcome`, where
`Verdict::Hold` maps to `Veto("<reason> <fix>")`); the full verdicts come from `HookRegistry::dispatch_event`.

### 3.3 Scopes and dependency table

Scopes: `suite:slackware`, `suite:cachyos-kernels`, `suite:nvidia`, `suite:curated`, `suite:gnomes`, `suite:sbo`,
`suite:flatpak`, `kernel:<version>`, `driver:nvidia`, `runtime`, `node:<id>`.

| unit | depends on |
|---|---|
| `kernel:<v>` | kernel, headers and modules packages of the same version (the kernel triad) |
| `driver:nvidia` | the kernel triad of every surviving kernel |
| initramfs of `<v>` | `kernel:<v>` and the driver module state for `<v>` |
| boot entry of `<v>` | initramfs of `<v>` |
| boot commit | every surviving boot entry |
| `suite:slackware` | nothing; held only for a split set on a mirror that is still syncing |

If no surviving kernel can get a driver module, all new kernels and the driver are held together.
A hold older than 14 days gives one WARN per week. Holds release themselves when the check passes.

### 3.4 Root invariants (the only VETO reasons)

1. `root=` of the running system is missing or wrong in a generated boot entry.
2. The boot entry for the running kernel would disappear or point to a missing file or a wrong hash.
3. `/boot` or the boot loader partition cannot hold the staged files.
4. A file owned by an official Slackware package would be overwritten.
5. A signature or hash check of a boot-critical download failed.

## 4. The Orderer

### 4.1 Stages

| id | stage | runs |
|---|---|---|
| P0-P3 | locks + fingerprints, horizon, forecast, consent | once |
| S1 | pre-update snapshot (section 4.4) | once |
| B1 | Slackware base: slackpkg update, install-new, upgrade-all, `.new` reconcile (consent + policy matrix, section 13) | once |
| B2 | multilib audit/heal, only if glibc changed | once |
| K1 | CachyOS kernels (kernel + headers) | per kernel version |
| K2 | NVIDIA userspace (utils, DKMS source or prebuilt modules) | once |
| K3 | other suites: curated, gnomes, Flatpak, SBo | once each |
| D1 | DKMS build | per surviving kernel |
| D2 | module signing (optional, off by default, NVIDIA module names only, verified, symlinks skipped) | per kernel |
| D3 | dracut, written to a temp name and renamed | per kernel, parallel |
| D4 | kernel and boot loader signing (sbctl) | per file, skipped when valid |
| C1 | generate `limine.conf.next` with hashes | once |
| C2 | enroll the new menu hash into `<efi>.next` | once |
| C3 | verify the `.next` pair (root invariants, signatures, files, sizes) | once |
| C4 | commit: live to `.prev`, `.next` to live (signals held around the renames) | once |
| C5 | verify live; failure rolls back to `.prev` automatically | once |
| F1 | remove old kernels, only after C5 | once |
| F2-F4 | caches, summary + exit code, restart advice; post snapshot | once |

### 4.2 Order and activation

`S1 -> B1 -> (B2) -> {K1, K2, K3} -> D1 -> D2 -> D3 -> D4 -> C1 -> C2 -> C3 -> C4 -> C5 -> F1 -> F2..F4`

D and C stages are active only if one of these is true: `kernel.deployed` fired; module sources changed; initramfs
inputs changed; the boot file listing differs from the last sealed state; the reseal-pending marker exists.
A run where nothing is active prints nothing. No stage loops over packages.

### 4.3 Resume and interruption

- Each stage writes `tx/<txid>/<node>.done` (input key, result, time) with temp + rename. A rerun skips a stage whose
  input key is unchanged.
- The reseal-pending marker (`/var/lib/slacky-boot/reseal-pending`, section 6) is written before the first rename of C4 and removed after C5. Cron, the tray watcher and
  the next run treat an existing marker as "verify live, else roll back or rerun C1-C5 under the boot lock".
- Kernel and initramfs files are never written in place. Old files stay until F1.

### 4.4 Snapshots (owner decisions 2026-10-12)

- On Btrfs with snapper: S1 takes a pre-update snapshot. If it fails, the kernel, driver and boot-chain scopes are
  held, the Slackware base proceeds, and the user is told once.
- F4 takes a post snapshot linked to the pre snapshot by the transaction id ("undo this update").
- Without Btrfs/snapper: no hold, one INFO line in the log.
- Keep at most 2 Spider-Sense snapshot pairs, 48 hours (configurable later).

### 4.5 Locks (same files in both apps)

| lock | file | rule |
|---|---|---|
| run lock | `/run/lock/slacky-update.lock` | flock + PID text; taken first |
| boot lock | `/run/lock/boot-partition.lock` | flock; taken second; held from the first boot write to exit; `SLACKY_BOOT_LOCK_HELD=1` for children; wait up to 300 s and say what is being waited for; cron never waits |
| rollback lock | `/run/lock/slacky-rollback.lock` | flock; taken by a rollback; an update does not start while it is held |

Locks keep these legacy names in both apps (owner decision O-3, 2026-10-14): the same file is what makes the two apps
exclude each other. No lock files in `/tmp`. Opening a lock must never redirect the process's own stderr (legacy bug
6A-56).

## 5. The Seer

### 5.1 Data sources, cheapest first

status cache; package database (directory mtime + count); Slackware ChangeLog, CHECKSUMS, FILELIST with HEAD /
If-Modified-Since; cached Arch/CachyOS repo databases; local kernel facts (`/lib/modules`, `/boot`, `dkms status`);
boot state from `rootstate.json` (section 6); runtime manifest.

### 5.2 Forecast

`forecast.json`: `schema`, `generated_ts`, `inputs_fingerprint`, `units[]` (id, kind, from, to, sizes, flags),
`derived` (reboot_needed, initramfs_needed, dkms_needed, boot_commit_needed, esp_delta_bytes, boot_free_bytes),
`holds[]`, `warnings[]`, `notes[]` (ChangeLog notes, security fixes).

Valid only while `inputs_fingerprint` matches the cheap fingerprint. Free space is always read live, never cached.
The background tier keeps the forecast fresh; the transaction recomputes inline on a cold cache.

### 5.3 Checks that feed the forecast (initial set)

kernel triad per incoming kernel; NVIDIA module presence per kept kernel; capacity of `/boot`, the boot loader
partition and `/`; mirror still syncing (ChangeLog newer than CHECKSUMS/FILELIST, package missing from FILELIST,
mixed versions in a set); ChangeLog notes (reboot, rebuild, removed, upgrade-first) and security fixes; footprint
(Slackware-owned files, global-effect files, ownership); user hold list; restart advice from libraries still mapped
by running processes (advice only, never restarts anything).

## 6. Files (root-owned 0644 unless noted, written temp + rename)

### 6.1 Shared markers and orders (both apps, owner decision O-3 2026-10-14)

One neutral directory that belongs to neither app: `/var/lib/slacky-boot/` (root:root 0755). Both apps read and write
the same files there, so there is only ever one menu writer and one reseal marker.

| file | content |
|---|---|
| `/var/lib/slacky-boot/reseal-pending` | marker, one JSON line `{txid, app, ts, stage}`; set before the first boot write of C4, removed after C5 |
| `/var/lib/slacky-boot/menu-pending` | order "the startup menu must be regenerated", one JSON line `{txid, app, ts, reason}` |
| `/var/lib/slacky-boot/menu-pending.taken` | claim: the serving process renames `menu-pending` to this name (atomic) before it works; removed when done; a stale claim older than 1 hour is released by the next run |
| `/var/lib/slacky-boot/dkms-build-pending` | order "DKMS modules must be built", one JSON line `{txid, app, ts, kernels: [..]}` |
| `/var/lib/slacky-boot/limine-committed` | C29 record of the last startup menu a trusted tool committed, one JSON line `{v: 1, txid, app, ts, blake2b, sha256}`: `blake2b` = BLAKE2B-512 of the exact `limine.conf` bytes (128 lower case hex, the value Limine enrolls), `sha256` = SHA-256 of the same bytes (64 lower case hex). Written by the app that finished a verified commit (C5), after the purge and BEFORE `reseal-pending` is removed; root:root 0644; never stored in /boot. Legacy writes the same record after its own verified commit (legacy 6A-157). |

Tamper check (C29, both apps, read-only): compare the live `limine.conf` BLAKE2B with the record and with the value enrolled in the Limine EFI
(`++CONFIG_B2SUM_SIGNATURE++`). Outcomes: consistent; pending (round 3b: a `reseal-pending` marker does NOT switch the comparison off; the live menu is always
compared with the record, and only the marker of THIS run, written by this app and carrying this run's txid, turns a difference into "pending"; a marker of an earlier
run, of the other app or at the old path never excuses a difference); no record (silent: cannot judge; this is also what remains when the record of a verified commit
could not be saved after one retry: the stale record is removed and one sentence says so, so the next run never calls our own menu foreign); unknown (unreadable menu or boot file, or an untrusted record: a record not owned by root, a link, world-writable, malformed, wrong version, or SHA-256 not matching its own
BLAKE2B; never reported as tampering, and a normal user who cannot read the boot partition is not interrupted: the recorder gets one entry per change of state, not per run); FOREIGN EDIT (live differs from the record and no marker): HOLD scope `boot:limine`, the boot chain must not commit,
nothing is resealed or re-enrolled; ENROLLED MISMATCH (live differs from the value in the Limine EFI, judged only for the app's own `EFI/limine` file and for the fallback `BOOTX64.EFI` when that is
a Limine file; a foreign loader at the fallback name is left alone): warn that Limine refuses to show this menu. A reseal by a tool that does not write the record
looks foreign: the hold text points to `slacky-update --sync-boot` only when the legacy program is installed, otherwise it says to check the menu. Kernel and driver
work is held at three points (compose time, before the first step at root, and the start of the Limine chain), and before a kernel or NVIDIA package is downloaded
or staged. Re-recording
(`spidersense --accept-boot-menu`) needs an explicit typed yes AND the open switch `BOOT_RECORD_WRITE_OPEN` (closed). CLI `spidersense --check-boot [--json]`:
silent when consistent, exit 52 for foreign/mismatch, 0 otherwise. Recorder category BOOT. Hooks: PreUpdateCheck and PreUpgradeTransaction (a note; the hold is
enforced at the start of the Limine boot chain, so a stray edit never blocks Slackware updates).

Rules: written with temp file + rename in the same directory; opened without following symlinks; a file not owned by
root, or in a directory writable by others, is ignored and reported; readers accept unknown JSON keys.

Transition (legacy uses `/var/cache/slacky-update/boot-reseal-pending` and `/var/cache/slacky-update/boot-menu-pending`
today; INFERENCE: legacy has no DKMS order file yet): both apps READ the old and the new path, and WRITE only the new
path. A marker found at the old path is treated exactly like one at the new path; the app that serves it removes the
old file after success. The old paths are dropped from both apps in a later spec version, after both have shipped the
new paths. Rust names: `verify::shared_paths`.

Rust until G7 (W1-FIX 2026-10-14): Rust never serves a reseal order, so it only READS the old-path marker and never
removes it (legacy serves and clears it). On a Limine machine Rust never starts the boot chain; when boot-relevant
packages changed anyway it writes `reseal-pending` only when a server exists (the legacy hourly check
`/etc/cron.hourly/slacky-snapper-limine-sync`, executable), marks its journal done, and exits 0 with one line; without a
server it writes nothing, says "Run slacky-update --sync-boot before restarting." and exits 30. The Rust snapshot pruner
waits for a marker only while a server exists, ignores a marker older than 7 days (one log line), and treats an
unreadable menu as unknown (a menu order is written) and an unreadable rollback lock as held.

### 6.2 Other state (unchanged from 0.2)

| file | content |
|---|---|
| `/var/cache/slacky-update/spidersense/forecast.json` | section 5.2 |
| `/var/cache/slacky-update/spidersense/held.json` | holds: scope, reason key, text, since, source (seer or user) |
| `/var/cache/slacky-update/spidersense/rootstate.json` | facts only root can read: free space of `/boot` and the boot loader partition, sealed-state fingerprint, menu entry list, boot file hash cache keyed by (path, size, mtime, inode), Secure Boot / lockdown / signature-enforcement flags, marker presence; written by every root phase and the hourly cron |
| `/var/cache/slacky-update/spidersense/boot-sealed.json` | fingerprint of the last good commit (C5 only) |
| `/var/cache/slacky-update/spidersense/weekly.json` | last run per weekly probe |
| `/var/cache/slacky-update/tx/<txid>/<node>.done` | stage records, last 5 transactions kept |
| `/usr/share/slacky-update/spidersense-pins.json` | pinned URLs and versions (Fedora shim/GRUB, usual suspects), read by both apps |

These keep the 0.2 paths (owner decision 2026-10-12). O-3 (2026-10-14) moved only the markers and orders (6.1), kept the
lock names (4.5) and made the logs per app (6.3). OPEN QUESTION for the owner: rule 1 (path independence) argues for
moving these files too, either to `/var/lib/slacky-boot/` (shared: held.json, boot-sealed.json decide boot behaviour)
or to a per-app cache; until decided, the Rust app does not write them.

### 6.3 Flight recorder (per app, owner decision O-3)

| app | system log | user fallback |
|---|---|---|
| legacy | `/var/log/slacky-update/spidersense.log` | legacy's own user cache |
| Rust | `/var/log/slacky-update-rs/spidersense.log` | `~/.cache/slacky-update-rs/spidersense.log` |

Both use the format of section 7, so one viewer can read both. Root never trusts files under a user's `~/.cache`, and a
root step never creates files there (legacy bug 6A-57).

## 7. Flight recorder and messages

One JSON object per line, appended with a single write under 4 KB. Keys on disk (as written by the Rust recorder,
work package W1-H; `?` = optional, left out when empty):

`{"ts":"<UTC ISO8601>","app":"legacy|rs","txid"?:"...","cat":"BOOT","lvl":"WARN","ev":"boot.pre-commit","scope"?:"kernel:7.2.10","msg":"one sentence","d"?:{...}}`

- Levels: INFO, WARN, HOLD, RESCUE, VETO, ERROR. INFO goes to the log only. ERROR = a check or step could not finish.
- Categories: BOOT, KERNEL, INITRAMFS, GPU, CPU, UPDATE, SNAPSHOT, SYSTEM, MIRROR, FOOTPRINT, OWNERSHIP, RUNTIME,
  SUPPLY, CAPACITY, INTEGRITY (C7: package files against the disk; legacy must add the same category). Unknown categories are shown as SYSTEM.
- `ev` is the spec event id of section 3.1 when the line comes from a hook dispatch.
- 16 MB cap, 48 hours; rotation by the writer holding `<log>.lock`, non-blocking.
- Messages: one sentence, about 120 characters, consequence first, everyday words in the console ("startup menu",
  "startup image", "graphics driver", "boot files"), technical names in `d`. No emoji, no blame, at most one command in
  backticks. Strings live in `locales/en.json` and `nb.json` under shared keys so both apps print the same text.
- Words not used in user-visible text (C9; internal identifiers may keep them): Holy Trinity, asymmetric mirror trap,
  Sacred Slackware, Regnskapsforer, Intervention, Veto, neural mesh, Lego, transmute, drift, invariant. The Rust list is
  `verify::JARGON_WORDS`, enforced by a unit test over every hook, watcher and upstream-check message.

Examples:
1. "The new kernel is waiting: its graphics driver is not on the server yet, so your current kernel stays."
2. "Slackware's update server is still copying files, so the kernel set is waiting; everything else updates now."
3. "The startup menu update did not pass its safety check, so nothing was changed; do not restart yet, run `slacky-update --sync-boot`."

## 8. Speed budgets (measured 2026-10-12, study C)

| tier | when | budget | examples |
|---|---|---|---|
| T0 | every invocation | at most 50 ms added | stat + cached verdicts |
| T1 | before the plan prompt | 400 ms warm, 1 s cold, no network | state reads, installed set, capacity, module presence, footprint lookup via index, ChangeLog notes from the local copy |
| T2 | after consent, before changes | 2 s, network capped at 2 s, overlapped with downloads | mirror truth, ABI check of replaced libraries |
| T3 | after changes | 3 s | boot hash compare, sbctl verify, signer of a new kernel, restart advice |
| T4 | background (cron, tray, inotify) | niced, incremental | full ABI graph, full re-hash, index rebuilds, forecast precompute, weekly probes, file integrity sweep |

Never in the foreground: one `ldd` per file, one process per check, network in the plan phase, content hashing of
all installed files. Legacy runs one python3 engine process per phase. Rust-only items: versioned-symbol ABI graph,
uncached parallel re-hash, inotify daemon, parallel mirror racing, upstream risk score.

Measured cost targets: nominal full update with nothing to do about +0.2 s; update with a kernel change about +3 s
in total, about 1 s noticeable.

## 9. Exit codes and self-check

Implemented today (Rust `src/core/exit_codes.rs` and `src/core/transaction.rs`; legacy `bin/slacky-update` 6A-102):

| code | meaning |
|---|---|
| 0 | completed (or nothing to do) |
| 1 | an error stopped the run |
| 30 | the boot chain was not committed, do not restart; also the interim refusal "kernel or driver updates on a Limine machine" before any change (O-1) |
| 31 | refused before any change: no consent (EOF, "no", or no terminal without `-y`) |
| 32 | refused before any change: another update is running (lock busy) |
| 50 | `spidersense --verify` found a mismatch or an event that is not wired yet |
| 130 | stopped by the user |

Reserved for later (not emitted yet): 10 completed with holds (once HOLD removes only its scope), 20 completed with a
warning that needs attention before restart. slackpkg's own codes (0/20/50) are mapped inside the app and never leaked.
Helper scripts print one line `PASS|WARN|HOLD|VETO <scope> <msg_key> [args]`.

Self-check (`slacky-update-rs spidersense --verify`, `slacky-update --spidersense-verify`), plain text, one line per
finding (`OK`, `WAITING`, `NOTE`, `FAIL`) and a summary:

- FAIL: an event has no table row; nothing listens to an event; only placeholders listen to it; a check listens to an
  event that nothing sends; the table and the registered checks disagree; a check listens to no event.
- WAITING: listeners are ready but the planned sender is not wired yet.
- NOTE: a declared placeholder check.
- Exit 0 only with no FAIL and no WAITING, else 50.
- Later additions: stages of section 4.2 exist; lock and marker paths equal sections 4.5/6; a log line round-trips;
  a fake-root dry plan writes nothing outside the caches and the log.

Example (Rust, 2026-10-14):

```
SpiderSense self-test
WAITING  plan.begin (PreUpdateCheck): 3 checks ready, but the update does not send this event yet; planned in main (src/main.rs), main.rs owner (W1-G).
OK       plan.ready (PreUpgradeTransaction): 8 checks, sent from run_with_options (src/core/transaction.rs).
OK       watch.drift (InotifyDrift): 5 checks, sent from dispatch_spidersense_heal (src/main.rs) and start_watchdog (src/core/spidersense/sentinel.rs).
NOTE     BtrfsSnapshotLifelineHook is a placeholder: the update takes its own safety snapshot after you approve the plan, so this check does nothing.
2 of 10 events are wired, 8 waiting, 0 problems.
SpiderSense self-test failed: some safety checks are not connected yet.
```

## 10. Conformance fixtures

Shared test data (files only), run by both apps with the same expected verdict and message key: mirror split sets
(kernel without headers, driver utils without DKMS source),
a kernel deployed without modules or startup image (HOLD `kernel:<v>`), markers at the old and the new path (6.1),
a full `/boot`, the five power-cut points of C4, footprint cases (`docs/footprint_spec.md`), a damaged `rc.local`
(`docs/rclocal_spec.md`), a kernel without driver modules, a failed snapshot.

## 11. Phases of delivery (preliminary plan)

| phase | content |
|---|---|
| 0 | this spec (review, then SPEC_VERSION 1 final) |
| 1 Lifeline | pre-update snapshot (legacy LTS MUST), consent before any change, run lock in `/run/lock`, marker before initramfs writes, cron checks the marker before its opt-in exit, honest status lines, exit code 30 and no default-yes restart after a refused boot chain (legacy 6A-42/43/44/47) |
| 2 Orderer | update re-expressed as the stage list of section 4; DKMS per surviving kernel; purge after commit; resume records; Rust ports G7-a..g before its NVIDIA and kernel suites are switched on |
| 3 Seer | legacy `lib/mod_spidersense.sh` + `lib/spidersense_engine.py`; `rootstate.json`; capacity forecast; footprint index; kernel triad holds; partial hold; mirror checks; ChangeLog notes; restart advice; user hold list |
| 4 Watchdogs | weekly, silent when nominal: Fedora shim/GRUB URLs + SbatLevel, MOK/enforcement warning, `rc.local` integrity, Btrfs health, file integrity sweep, ownership audit, firmware (read-only); package rollback last |

## 12. Owner answers (2026-10-13)

1. Verify on the real ESP whether the boot loader's fallback path survives a power cut between the two renames of C4
   before that becomes a hard requirement: YES (to be checked read-only on the owner's machine in phase 1/2).
2. Keep 2 snapshot pairs, 48 hours: YES.
3. The hourly cron reseals only when boot-relevant input changed (legacy 6A-55): YES.

## 13. Configuration files (`.new`) and the base store (J1, decided 2026-10-14)

Owner decisions (2026-10-14): Spider-Sense MAY resolve `.new` files, never without the user's consent. The store lives in
`/var/lib/slacky-config/` (root 0700, files 0600, outside the package database and outside `/etc`). Undo is BOTH a journal
(one command) AND slackpkg-style `.orig` backups, except inside folders where every file is run or included
(`/etc/cron.*`, `/etc/rc.d/rc*.d`, `/etc/profile.d`, `/etc/sudoers.d`, `/etc/modprobe.d`, `/etc/udev/rules.d`,
`/etc/X11/xorg.conf.d` and the like): there the backup goes only into the store, never next to the file. A pin is the line
`# slacky: keep` (the comment mark of the file type) or an entry in the pins file for formats without comments.

Rules (both apps):

1. Format and capture rules of the store: `docs/config_store_spec.md`. Both apps write the same store; an app that moves a
   live file the store tracks must update the index in the same step, or leave that file alone.
2. Capture is the only thing that runs without a question: right after the Slackware base step the stock text of every
   config file of every package upgraded in this run is copied into the store. It never changes `/etc`.
3. Policy matrix (target; J3 and later; the classifier of J2 only REPORTS the case): O = live file, T = `X.new`, B = base.
   1 O missing: install T. 2 O equals T: drop `.new`. 3 O equals B: replace. 4 T equals B: keep O, drop `.new`.
   5 all differ, clean merge: apply (boot-critical files ask). 6 conflicts: ask. 7 base not exact: preview first.
   8 no base, only comments or blanks differ: replace. 9 no base, anything else: ask (two-way). 10 file unreadable in the
   user phase: decide in the root phase by rules 2-4, else keep. A pinned or user-owned file is always kept.
4. Never listed as actionable: `passwd`, `group`, `shadow`, `gshadow` (slackpkg skips them too; the store never captures them).
5. Recorder: category `Config`, events `config.capture`, `config.status`, later `config.plan`, `config.replace`, `config.keep`,
   `config.merge`, `config.undo`. Hashes and paths only, never file contents.

## 14. Healing (T0, owner decision 2026-10-14)

Design: `docs/spidersense_healing/healing_design.md`. Tasks: Rust T0-T9, legacy 9A-9D. Legacy DETECTS and ADVISES only
(read-only audit, one `slackpkg reinstall ...` command, no root step). Rust plans in this version (T1/T2) and applies in a later one.

### 14.1 Rule H0 (both apps)

A repair may only ADD BACK a missing path or REPLACE a path with STOCK content of the SAME package version. It never deletes a
path unless the same step puts the stock content of that path back, and it never touches a path that has no stock owner. A repair
never edits a user's file, never touches `.new` files, never edits the package database (`/var/log/packages`,
`/var/lib/pkgtools`) with its own code (the only change to it is the rewrite of the entry of the SAME package that Slackware's `upgradepkg --reinstall` makes
as part of its own work), never touches accounts, and never writes the boot chain outside the existing gated steps. A link in the way is
renamed aside (`<path>.slacky-heal-<txid>`), never deleted.

### 14.2 Never-list (a package with any damaged path on it gets class `never`, no repair, no command)

`etc/passwd|shadow|group|gshadow` (and their `-` backups), `etc/sudoers*`, `etc/pam.d`, `etc/security`, `etc/ssh/ssh_host_*`, `root`,
`home`, anything under `$HOME`, `boot` and the ESP (`efi`), `dev`, `etc/limine`, `var/log/packages`, `var/lib/pkgtools`, `var/lib/slacky*`,
`opt/underpants/runtime` (owned by the H-series; heal only reports), `lib/modules`, `lib/firmware`, `usr/lib/firmware`, any `*.new`
(owned by the J-series). Boot-chain repairs only by booking the existing gated `limine_chain` / `dracut_build` steps. A user
config in `/etc` that differs from stock is customisation, not damage; it is never a finding.

### 14.3 Classes

| class | meaning | examples |
|---|---|---|
| repair | put back from the signed stock package, same version, after consent | missing stock file; directory replaced by a link (restored together with every stock package that has files below it); files of OUR package owned by a normal user (`own_owner_restore`) |
| advice | explained with one sentence and, for official packages, the exact command; nothing is changed | installed version differs from the mirror ("the next full update brings the files back"); SBo or third-party package; package only in a tree without a pinned key (`pasture`, `testing`, multilib without key); mirror list missing; link pointing into itself; mount point; collisions and global-effect files (the C2 guard handles them before install); stock package with foreign-owned files (reinstall sets them right) |
| never | left alone, one sentence says why | section 14.2 |

"Same version" is read from slackpkg's local `pkglist` (installed full name must equal the entry of a signed tree: `slackware64`,
`slackware`, `patches`, `extra`) and, when present, the archive must be listed in the local `CHECKSUMS.md5`. No network in the
planner. When the mirror no longer carries the installed version: advice only.

### 14.4 Step kinds (defined here, NOT in the order book yet)

| kind | what | gate |
|---|---|---|
| `stock_reinstall` | exact signed stock package re-installed with `upgradepkg --reinstall` from the private book directory. The book stages the package, its own `.asc` when the signed list names one, and (with the FIRST reinstall step only) the signed `CHECKSUMS.md5` with its `.asc`; the root phase verifies the list and the package signature again with gpgv and the pinned key on its own root-owned copies and compares the package MD5 with the verified list before the install. Verify-after: every damaged path exists with the archive's type; a listed `*.new`, `install/`, `dev/`, `tmp/`, `boot/` or folder entry is not damage (same skip rules as the audit). | `HEAL_STOCK_OPEN = false` |
| `path_type_restore` | link renamed aside, real folder created (mode/owner from the archive listing, default root:root 0755); always listed before the `stock_reinstall` steps below it, which restore the content; refused when the link target lies inside the path or the path is a mount point. When the covering reinstall fails or is skipped (version changed) and the new folder is still empty, the empty folder is moved aside (`<path>.slacky-heal-empty-<txid>`) and the link is put back; a folder that holds files is left as it is | `HEAL_STOCK_OPEN = false` |
| `own_owner_restore` | `chown root:root` of paths listed in OUR package logs only: every component is opened with `openat(O_NOFOLLOW | O_DIRECTORY)` and the file is changed with `fchownat(AT_SYMLINK_NOFOLLOW)`, so a folder owned by a normal user cannot be swapped for a link in between; no content change | `HEAL_OWNER_OPEN = false` |
| `cache_regen` | `ldconfig`, `fc-cache`, desktop/icon/mime/schema caches, only after a heal step | with `HEAL_STOCK_OPEN` |

The validator of a future step refuses: a path in 14.2, a `stock_reinstall` whose file name is not a Slackware package name equal to `version`,
a `path_type_restore` without a covering `stock_reinstall`, an `own_owner_restore` on a package that is not ours, a reinstall whose staged files are not exactly the package,
its own signature and (first step only) the signed list, and a book that mixes heal steps with kernel, driver, DKMS, initramfs, Limine chain or nouveau steps. The
executor reads the gates again before each step (defence in depth).
Rust: `src/core/spidersense/healplan.rs` (`HealPlan::check_h0` checks the same rules on a plan).

### 14.5 Consent and limits

- One consent for a heal book, default NO. `-y`, pipes (no terminal), `NON_INTERACTIVE=1` and cron/tray runs never repair.
- At most ONE heal question per 24 hours (a tray may remind once per day, never more). A "no" uses up the day quietly; a "yes" uses it up only once the root phase
  really started (sudo accepted), so a refused password does not hide the question.
- A finding that returns within 7 days after a verified heal is not offered again: advice "this keeps coming back; something on this
  computer removes it" (state per app in `/var/lib/slacky-update-rs/heal-state.json`).
- Size cap: at most 50 packages (and 2 GB download) per book; above that: advice "restore the latest safety snapshot".
- Refuse (advice only) when the install tools themselves are damaged: `upgradepkg`, `installpkg`, `removepkg`, `explodepkg`, `tar`, `xz`, `gpgv`, `slackpkg`.
- No heal while an update runs, a rollback lock is held, a reseal marker is open, or the mirror is mid-sync (Seer hold).
- Watchers (cron, tray, inotify) only detect and record.

Implemented in T1/T2: classes, same-version check, never-list, tool and size refusal, consent predicate (`may_offer_repair`).
Implemented in T3-T8 (gates closed): download and signature check, flap state (keyed by path, step kind and package NAME, so a new
version does not hide a returning finding; entries older than 30 days are forgotten, at most 5000 are kept), once-per-day stamp, the book
steps, the consent screen and the work lines (14.8), the install-tool check at apply time, the detection in the update flow (14.9).

### 14.8 Consent screen and work lines (T6)

- Every repair is shown as one plain sentence followed by `Repair this? [y/N]`; only `y` or `yes` is a yes, Enter, end of input and anything else is no.
  A folder repair together with the packages that belong below it is ONE question (all or nothing). One summary line
  (`{count} repair(s) will be made, after a safety snapshot.`) appears only when at least one answer was yes. All answers no: nothing more is said.
- During the root phase every heal step is one work line (`docs/output_style.md`): `Reinstalling infozip 6.0-x86_64-9 (restores /usr/bin/unzip)...` with one
  more dot every 1.5 s, ending in `OK` or `FAILED`; on a failure exactly one plain sentence follows on the next line; a step that found nothing to do
  leaves no line. Not a terminal: one finished line `description... OK`. The old line `Repaired: N item(s) ...` is gone (the recorder keeps the count).
- The download after the answers is one work line (`Downloading N signed package(s)`).

### 14.9 Detection in the update flow (T8, no repair)

- After a full update the integrity audit runs once as the normal user (no sudo, no network). Clean: silent. Damage: exactly one sentence, `Some installed
  packages are damaged; run `slacky-update-rs spidersense --heal` to see what can be restored. Nothing was changed.` (legacy names its own flag).
- `TypeDamageHoldHook` (PreUpgradeTransaction, a guard): a package in the update set with a folder replaced by a link is held (`node:<package>`) with one
  sentence; a package with only missing files is not (the upgrade brings them back). With the current pipeline rule a guard's hold stops the update before
  anything changed. The hook receives the base names through `HookContext.metadata["upgrade_names"]`. Legacy mirror: `docs/healing_legacy_9A-9D.md`.

### 14.6 Messages and recorder

One sentence per item, consequence first, no emoji, no jargon (`heal`, `drift`, `invariant` are internal words; UI says "repair", "restore").
Catalog keys `HEAL_*` in `locales/{en,nb}.json` (the one embedded catalog, I18N-1). Recorder events (later steps): `heal.found`, `heal.plan`,
`heal.advice`, `heal.refused`, `heal.consent`, `heal.verified` (RESCUE), `heal.verify_failed` (ERROR), `heal.recurring`; hashes and paths only.

### 14.7 CLI

`slacky-update-rs spidersense --heal [--json]` prints the existing drift report, then the plan (nothing when there is nothing to plan): a summary line,
one sentence per item (repair, advice, never), the exact command (`slackpkg reinstall <names>`) and "Nothing was changed. Applying repairs is not
available yet." (once, and only when a repair was listed; with `--apply` the apply path says it itself) JSON adds `plan` and `plan_command`. A clean drift check prints
nothing, and nothing is claimed for a check that did not run; no colour codes off a terminal or with `NO_COLOR`. Exit 0. Legacy prints the same sentences and the same command.
