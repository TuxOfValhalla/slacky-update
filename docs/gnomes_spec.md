# Underpants Gnomes contract: "pacman for /opt" (GNOMES_SPEC_VERSION 1, draft 0.1, 2026-10-13)

Shared contract for the Underpants Gnomes pacman sidecar (`bin/gnomes`, `lib/gnomes_pacman.py`, later
`libexec/gnomes-apply`) and its two callers, slacky-update (legacy) and slacky-update-rs (Rust). Identical copy in both
repos. It names behaviour, files and formats; it contains no code.

Status: DRAFT for owner review (phase P0 of the master plan, `docs/pacman_study/opus_pacman_masterplan.md`). Sections
marked PROVISIONAL (resolver 6, wrapper 8, runtime lifecycle 9) will be revised with the results of the three
compatibility studies started 2026-10-13. Nothing here is implemented until a roadmap task says so.

## 1. Decisions this spec is built on (owner, 2026-10-13)

1. The sidecar is exempt from the rule that the two apps never call each other. It is the ONLY code that writes under
   `/opt/underpants`. Legacy and Rust call it; Rust may read its index and registry read-only.
2. Runtime model: Option A directly (registry + runtime generations). The earlier "family bricks first" plan (H3/7B) is
   dropped; families remain as logical sets in the registry.
3. Registry location: `/opt/underpants/var/lib/gnomes` (never `/var/log/packages` for runtime content).
4. Trust model: pinned keyrings (Arch, CachyOS, Chaotic), verified with stock `gpgv`. Simpler than pacman's master-key
   web of trust; documented as such.
5. The runtime becomes GPU-free: GL/EGL/GLX/GBM/DRM/Mesa/Vulkan loader/LLVM-for-Mesa come from the host only.
6. System class stays outside gnomes: kernel, NVIDIA, limine, sbctl, limine-entry-tool, limine-snapper-sync, snapper,
   grub-btrfs. Never in `gnomes -Syu`; updated only inside the boot chain with snapshot and reseal.
7. openghub is dropped; hyprmod is kept (its sources must be pinned).
8. Curated (`_slacky`) packages are never managed or overwritten by gnomes (6A-59) until a package's migration step
   explicitly hands it over.

## 2. Layout (root:root, directories 0755, files 0644 unless noted)

```
/opt/underpants/
  pkgs/<app>/                    app trees, installed as Slackware packages (role unchanged)
  runtime -> runtime.d/<gen>     symlink after migration (today: a real directory)
  runtime.d/<gen>/               immutable generations: lib/ bin/ share/ etc/ include/ + .gen.json
  var/lib/gnomes/
    db/runtime/<gen>/<pkg>-<ver>/{desc,files,elf}
    db/apps/<app>/{lock.json,files,elf}
    host.idx                     host soname + symbol inventory
    tx/<txid>/{plan.json,<step>.done,journal}
    state.json                   current generation, previous generations, held sets, last DB timestamps
  keys/{archlinux,cachyos,chaotic}/{pubring.gpg,revoked}
  libexec/{gnomes-apply, shim/<name>}
/usr/share/slacky-update/gnomes/policy/<id>.toml   shipped policies (read-only)
/var/cache/slacky-update/gnomes/{db/,index.sqlite,pkgs/,built/,held.json}   root cache
~/.cache/slacky-update/gnomes/                     user cache (search, user builds, user held.json); root never trusts it
/usr/bin/<app>                                     wrapper (a file of the app's package)
```

Root never reads decisions from a user cache. Cache directories are never group/other-writable (6A-52).

## 3. Package identity and versions

- Unit: one Arch package (name, epoch:pkgver-pkgrel, repo, arch). The full version is stored in the registry and in the
  app lock; the Slackware package filename only carries a sanitised copy.
- Version comparison: a faithful port of pacman's `vercmp` (epoch first, then pkgver segment rules, then pkgrel).
  Acceptance: 100 % of pacman's own test vectors.
- Repository order: CachyOS tier repos (znver4 / v4 / v3 by CPU), then Arch core/extra/multilib; testing repos never.
- A DB whose newest build date is older than the last accepted one is refused (replay protection). Downgrades only by
  an explicit user command.

## 4. Metadata index (speed)

- `sync` keeps the repo DB files and also writes `index.sqlite` (tables: pkg, depend, provide, conflict, replace,
  optdepend, file) keyed by the sha256 of each DB file. Plan-time code queries only what it needs.
- Arch `.files` databases are imported for pre-download file conflict checks.
- Budget: planning one app at most 400 ms warm, 1 s cold (today 1.37 s).
- The Rust app may read `index.sqlite` read-only.

## 5. Signatures and sources

- Packages: `%PGPSIG%` from the DB or the `.sig` file, verified with `gpgv` against the pinned keyring of its repo.
- Keyrings: shipped fingerprints; refreshed only from the official keyring package, verified with the current keyring,
  swapped atomically, revocations honoured.
- Rollout: first log-only (flight recorder category SUPPLY), then enforce: an unsigned or badly signed package and its
  dependents are HELD with one sentence.
- Non-repo sources (policy `source`): must be pinned (tag or commit, never a branch) and carry a sha256 or b2sum.

## 5a. Held packages (implemented early, legacy Build 67)

- A package is held when its ELF files need newer GLIBC / GLIBCXX / CXXABI / GCC symbol versions than the host defines
  (check after patchelf, before packaging). Nothing is installed; the installed version stays; one sentence explains it.
- Held entries: `held.json` (root cache when root, else user cache): name, version, needed symbol, host stamp, reason,
  since. `list-updates` does not offer a held version again while the host stamp is unchanged; a new upstream version
  or new host libraries release it. `gnomes_pacman.py held [--json]` lists them.
- Later holds (signatures, bounds, conflicts, families) use the same file and the same rules.

## 6. Resolver v2 (PROVISIONAL)

For each dependency D of target P, keeping version bounds and resolving providers:

1. Hard host list: glibc family, libstdc++/gcc-libs, udev/elogind, dbus, pam, nss, polkit, wayland, xkbcommon, audio
   servers, the whole GPU userspace. Symbol headroom check (5a).
2. Host: every soname D provides that P needs exists on the host with matching ELF class and the required symbol
   versions, and the host package version satisfies the bound.
3. Runtime by manifest: the current generation has D (or a provider) at a version satisfying the bound, and for
   move-together families the family version matches the one P was built against.
4. Runtime by soname: the pool has the library and the needed symbols (fallback for packages without metadata).
5. Bundle into the app (recorded in the app lock). If two or more apps would bundle the same D at the same version, the
   plan proposes moving it into the runtime instead.
6. Unsatisfiable bound or conflict: HOLD P with one sentence. `replaces` drives renames.
7. After building: closure and symbol checks (section 10, L1-L4); a failing dependency flips to bundle once, else HOLD.
8. 32-bit only when a policy says so, resolved against host multilib only, never in the runtime.
9. "Provided by the host" for programs means owned by an official Slackware package, not found on PATH (6A-15).

Move-together families: Qt6 + KF6 + PyQt/PySide; Qt5; GStreamer; ICU; Python + C extensions; boost;
protobuf + abseil + grpc; ffmpeg; GTK/glib caches; the Hyprland family (hyprland, hyprutils, hyprlang, hyprcursor,
hyprgraphics, aquamarine). Mesa/libdrm/LLVM are host-only.

## 7. Transactions

Follows `docs/spidersense_spec.md` phases and events (plan, consent, execute, finish).

1. PLAN (user, read-only): resolve, file lists from the index, conflict check against Slackware owners and against
   other gnomes packages, disk space, holds.
2. CONSENT: one plan, answered once.
3. FETCH + VERIFY (user, parallel): download, signature check.
4. BUILD (user, private 0700 temp dir): extraction errors are fatal, `.MTREE` verified, merge collisions inside an app
   reported, patchelf failures reported, wrapper generated, policy applied, Footprint Guard enforced, archive root-owned
   with the mode gate. Output: `.txz`, `lock.json`, registry fragment, all hashed into `plan.json`.
5. PRE-FLIGHT (user): section 10 checks against the current generation (apps) or the candidate (runtime).
6. SNAPSHOT GATE: required for host-path classes and runtime switches; fail-closed when Btrfs + snapper exist.
7. APPLY (root, one prompt, `gnomes-apply <txid>`): re-verify hashes and archive owner/mode; take
   `/run/lock/underpants-gnomes.lock` (and respect the slacky-update run lock); `upgradepkg --install-new --reinstall`
   per package with `UNDERPANTS_TX=<txid>`; remove exact-name predecessors only after the successor is installed;
   runtime switch; hooks once (section 11); commit the registry with temp + rename; journal records.
8. POST-VERIFY: wrapper present and executable, hooks succeeded, registry consistent, quick closure check of touched apps.
9. FINISH: keep the previous `.txz` of each replaced app (2 versions) for `gnomes --rollback <app>`; silent on success.

Every step writes `<step>.done`; a rerun resumes or rolls back. Exit codes and helper output lines follow
`docs/spidersense_spec.md` section 9.

## 8. Wrapper v2 (PROVISIONAL)

Generated from a per-app manifest written at build time:

- Fixed `APP_ROOT`; `exec` of the target recorded in the manifest (no search at every launch).
- No `LD_LIBRARY_PATH` (RUNPATH covers patched ELFs). A per-app escape hatch only when the build-time closure check
  proves it is needed; never with host directories; always removed by the shims.
- No `QT_PLUGIN_PATH`; `qt.conf` next to the binary only for apps with a private Qt.
- PATH: shim directory first, then the host PATH, then `APP_ROOT/bin` last and only when the app runs its own helpers by
  name. Never `/opt/underpants/runtime/bin`.
- Toolkit variables only when the app links that toolkit and the directory exists; `XDG_DATA_DIRS` host first;
  `GST_REGISTRY_1_0` per app.
- Before changing a variable the wrapper saves the original; shims (`xdg-open`, `xdg-email`, `xdg-mime`, `gio`,
  `kde-open`, `kioclient`, `gtk-launch`, browser helpers) restore the originals and run the host tool by absolute path.
- Game launchers export nothing that games inherit. No GPU driver paths into the runtime.

## 9. Runtime generations and lifecycle (PROVISIONAL)

- The runtime is a set of Arch packages recorded in the registry. A transaction is a closed set: the changed package,
  every member of its family, and every pool package whose libraries need a changed soname.
- Candidate: `runtime.d/<new>` built as a hardlink clone; inside the candidate files are only replaced (unlink, new
  file, rename), never edited in place (patchelf and cache generation run on fresh files before linking in).
  `gnomes -Sdd` (hardlink dedup) is disabled or made generation-aware before generations go live.
- Old sonames stay until no pool package and no app lock needs them.
- Pre-flight over the candidate and every installed app (section 10), caches generated inside the candidate, snapshot
  gate, then one atomic symlink switch; rollback is the same switch back. Two previous generations are kept; a
  generation is deleted only when no running process maps it.
- Cadence: metadata daily; a candidate is built only when a pool package changed; applied only inside a full update or
  `gnomes -Syu`; a family bump waits until every consumer's rebuild is in the same repo sync.

## 10. Pre-flight levels

| level | check | verdict |
|---|---|---|
| L1 | GLIBC/GLIBCXX/CXXABI/GCC symbol versions vs host (implemented, Build 67) | HOLD |
| L2 | needed-library closure with the real search order, diff against a baseline | HOLD on new "not found" |
| L3 | undefined symbols and symbol versions against the chosen providers | HOLD |
| L4 | plugin directories match their toolkit version (Qt, GStreamer, pixbuf, GTK, GIO, SPA, Python) | HOLD the set |
| L5 | registry consistency: one owner per path, every needed soname provided, bounds and conflicts satisfied, families coherent | HOLD the set |
| L6 | headless start (`--version`/`--help` with a timeout) in the candidate environment (runtime updates) | WARN first, later HOLD |

Costs follow `docs/spidersense_spec.md` section 8: incremental checks in the transaction, full scans in the background.

## 11. Hooks (closed table, run once per transaction; Arch install scripts are never run)

desktop database; mime database; icon caches per touched theme; glib schemas; fontconfig cache; udev reload (policy
allowlist only); D-Bus system config reload (policy only); polkit (read on demand); sysusers translated to
groupadd/useradd (never deleted on removal); tmpfiles translated into the generated rc script; systemd units converted to
rc.d with rc.local marker blocks (`docs/rclocal_spec.md`, unit names sanitised); modprobe.d and modules-load (policy);
DKMS handed to SpiderSense (once per surviving kernel); suid/capabilities only from a shipped policy, applied in the tar
entry; ldconfig only when a host library directory is touched; boot chain never inside gnomes. `backup=` files ship as
`X.new` with Slackware's `config()`. Unknown install-script functions are logged and shown as a warning in the plan.

## 12. Policies (separate document `docs/gnomes_policy_spec.md`, to be written)

TOML per package, shipped read-only. Unknown keys are errors. A policy can only narrow what the Footprint Guard allows,
plus explicit allowlist keys for host paths that are not Slackware-owned. suid/capabilities only in shipped policies.
Sources must be verified and pinned. Post hooks from a closed list. Classes: app, plugin, host-layout, daemon, driver,
theme, and the system exception (section 1.6).

## 13. Messages

One sentence, consequence first, everyday words, no emoji; strings in `locales/en.json` and `nb.json` under shared keys.
Examples:
- "vlc needs a newer system library (GLIBC_2.45) than this Slackware has (GLIBC 2.44), so it was not installed and your
  current version stays."
- "This package is not signed by a trusted key, so it was not installed; your current version stays."
- "Steam is a curated package, so gnomes leaves it alone; it is updated by the curated suite."

## 14. Open items

- Results of the three compatibility studies (ABI/linking, environment, runtime lifecycle) and the Fable review will
  revise sections 6, 8 and 9.
- `docs/gnomes_policy_spec.md` (P0 part 2) and the Hyprland suite plan.
- Still open with the owner: suid sandbox for browsers, brave vs brave-bin, the theme packs, an optional bwrap tier.
