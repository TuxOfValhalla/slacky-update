# Underpants runtime bricks: shared file-format spec (`underpants-runtime-bricks/1`)

Status: DRAFT 2, 2026-10-17 (owner decisions of 2026-10-17 applied, section 14). Written for BOTH apps (CLAUDE.md 13.3): `slacky-update-rs` (Rust) and `slacky-update` (legacy)
implement exactly this and share NO code. Same shape as `docs/footprint_spec.md`; a copy must sit in the legacy repo as
`docs/runtime_spec.md` (owner commits there). Evidence: `docs/runtime_bricks_measurement.md`.

Scope of this draft: file formats, ownership rules, pre-flight, swap, detection. Nothing here is implemented as a writer or an
installer, and NOTHING may touch the owner's real install until the owner decides (section 12, CLAUDE.md 13.3).
Every point that came from an owner decision is marked **[Q#]** and collected, with date and reason, in section 14 (all 18 questions are decided).

Words: MUST/MUST NOT are binding for both apps. FACT = measured. DECIDED = owner decision of 2026-10-17 (section 14).

## 1. Goals and non-goals

Goals: update the shared runtime by family (brick) instead of as one 3 GB monolith; know which package owns every file; refuse
a dangerous update BEFORE it lands (Spider-Sense "seer"); make rollback one rename; keep every wrapper, RPATH and path
exactly as it is (section 11). Option C (bricks) is the first step; the formats are chosen so Option A (per-package registry,
candidate pool, pre-flight, atomic swap) is a refinement, not a rewrite.

Non-goals: changing wrappers, RPATH or `LD_LIBRARY_PATH` (CLAUDE.md 11); touching app trees `/opt/underpants/pkgs/<app>`; per-app private
libraries (**[Q15]**); signature verification of repository packages (**[Q16]**, separate task); writing `/var/log/packages` from our own tools.

## 2. States and how the monolith is detected (read-only)

`runtime_state(root)` classifies `<root>/opt/underpants/runtime`. Both apps MUST return the same state for the same fake root.

| State | Condition | Writers allowed |
|---|---|---|
| `Absent` | no `lib/` entries, no `.gnomes/manifest.json`, no `.bricks/layout.json`, no `underpants-runtime-*` package log | create |
| `Monolith` | NO `.bricks/layout.json`, AND (`.gnomes/manifest.json` exists OR `var/log/packages/underpants-runtime-*` exists OR `lib/` has files) | **none**; read and report only |
| `Bricks` | `.bricks/layout.json` valid, every listed brick manifest present and valid, cross-brick checks (section 5.4) pass | update through the swap (section 9) |
| `Broken` | `.bricks/layout.json` present but invalid, a listed brick manifest missing or invalid, or a fatal validator finding (V1-V5, V8, V9, section 5.4, for example a collision or a host-only leak) | none; report the first reason in one plain sentence |
| `Mixed` | `.bricks/layout.json` present AND a package log `underpants-runtime-all-*` still exists | none; "migration half done" |

The existing monolith (`.gnomes/manifest.json`, schema 1, profile `all`, layout 1.1, FACT: 518 packages, installed package
`underpants-runtime-all-1.1-x86_64-1_gnomes`) is `Monolith`. It is left completely alone: no writer, no `runtime.next`, no
convert prompt (the existing `LEGO_MODEL_ENABLED=false` gate stays off) until a user-run migration (section 12).
The ONLY writer allowed in state `Monolith` is the monthly refresh of `docs/runtime_refresh_spec.md` (owner 2026-10-20): it replaces the whole
monolith through the existing package path and never creates `.bricks`, `runtime.next`, `runtime.prev`, `.db` or `/opt/underpants/.runtime.lock`. Every other code path that
could write under the runtime MUST first call the state check and refuse when the state is not `Absent` or `Bricks`.

## 3. Layout on disk

```
/opt/underpants/runtime/            LIVE tree, root:root, flat, UNCHANGED shape: bin lib include share etc
/opt/underpants/runtime/.gnomes/manifest.json   schema 1 aggregate manifest (kept, see Q12)
/opt/underpants/runtime/.bricks/layout.json     NEW: the brick list and generation
/opt/underpants/runtime/.bricks/<brick>.json    NEW: one manifest per brick (section 5)
/opt/underpants/runtime/.bricks/baseline-unresolved.json   NEW: NEEDED baseline (section 8)
/opt/underpants/runtime.next/       candidate tree (exists only during an update)
/opt/underpants/runtime.prev/       previous tree (one generation, kept for rollback, Q17)
/opt/underpants/.runtime.lock       flock file (one writer at a time)
```

Bricks are a LOGICAL partition of the one flat tree: every file keeps its path (`runtime/lib/libQt6Core.so.6`), so
nothing that resolves paths (wrapper, RPATH, desktop files, scripts) changes. The partition lives in the manifests, not in directories.
A brick is never a separate directory under `runtime/` (the old idea `runtime/<brick>/` in CLAUDE.md 6.2 would change every
`LD_LIBRARY_PATH` entry and is NOT used). Directories starting with `.` under the runtime root (`.bricks`, `.db`, `.gnomes`) are
metadata; no brick file may live there.

## 4. The brick set (DECIDED 2026-10-17, section 14; measurement doc section 3)

| Brick | Meaning | Order (lower = earlier) |
|---|---|---|
| `core` | compression, crypto, text, base C/C++ libraries (**[Q3]**: coarse) | 0 |
| `x11` | libX*, xcb, xorg tools | 1 |
| `data` | fonts, icon/cursor/sound themes, translations, keymaps (no ELF) | 1 |
| `python` | the Python interpreter and stdlib | 2 |
| `ffmpeg` | libav*, video/audio codecs and filters (**[Q8]**) | 2 |
| `graphics` | GL/Vulkan HELPERS only (glew, glfw, glm, epoxy, openxr, input libs); NEVER drivers or loaders | 2 |
| `gstreamer` | GStreamer, plugins, orc, nice, gupnp (**[Q4]**) | 3 |
| `gtk` | GTK 3/4, libadwaita, pango, cairo, webkit, glycin, wx, portals-gtk (**[Q4]**) | 3 |
| `qt5` | Qt 5 | 3 |
| `qt6` | Qt 6 | 3 |
| `cad` | OpenCASCADE, VTK, poppler, BLAS/LAPACK, imaging libraries (**[Q5]**) | 3 |
| `mobile` | libimobiledevice family | 3 |
| `desktop-services` | only what remains after **[Q18]**: `xdg-desktop-portal`, `xdg-dbus-proxy`, `xdg-utils`, `bubblewrap`. If a build finds it empty, the brick is dropped (never an empty manifest) | 3 |
| `kde` | KDE Frameworks 6, Plasma pieces; needs `qt6` (**[Q7]**) | 4 |

Rules:
1. Brick names match `^[a-z][a-z0-9-]{0,31}$`. The set is data, listed in `layout.json`; a new brick needs no code change.
2. **Host-only (hard rule).** The brick table MUST NOT contain any package named in `RUNTIME_HOST_ONLY` / the manifest's `host_only`
   (`mesa libglvnd libdrm vulkan-icd-loader shaderc glslang spirv-tools libva libvdpau alsa-lib pipewire libpipewire libpulse
   pipewire-jack jack2 ocl-icd gnutls p11-kit llvm-libs ca-certificates-*`), and from **[Q18]** also the system daemons and disk tools
   `udisks2 upower mdadm cryptsetup parted device-mapper lm_sensors libbytesize volume_key accountsservice iio-sensor-proxy libblockdev`
   and every package whose name starts with `libblockdev-` (see "Host-only lists" below). No file matching `RUNTIME_HOST_ONLY_FILES` or under
   `RUNTIME_HOST_ONLY_DIRS` (`src/gnomes/tables.rs`; legacy has the same lists in `gnomes_pacman.py`). The old `LEGO_BRICKS`
   table violates this (measurement doc section 6). The new table is generated from the manifest and checked by the validator (P3).
   Reason for Q18: system services and disk tools do not belong in an app runtime; Slackware ships its own.
3. The package to brick assignment is carried BY the brick manifests (each lists its packages); there is no second table at run time. At build time
   both apps use the same written name rules (**[Q6]**). An Arch package that matches no rule is a build error, never silently `core` (**[Q3]**).
4. `requires` should point to a brick of lower Order (the table above is guidance); an edge to an equal or higher Order is only valid as part of an update set (section 7). The validator enforces only V6 (no cycles outside an update set).
5. **No developer or documentation content (DECIDED Q9).** The runtime does not ship headers, cmake files, pkgconfig files, man pages or docs. The builder
   drops them while flattening, and the validator (V9) refuses any manifest that lists one. Excluded prefixes (whole path components, relative to the runtime root):

   | Prefix | What |
   |---|---|
   | `include` | C/C++ headers |
   | `lib/cmake`, `share/cmake` | CMake package files |
   | `lib/pkgconfig`, `share/pkgconfig` | pkg-config files |
   | `share/aclocal` | autoconf macros |
   | `share/man` | man pages |
   | `share/doc`, `share/info`, `share/gtk-doc`, `share/devhelp` | documentation |

   **Kept on purpose:** `share/locale` (apps use translations), `share/icons`, `share/mime`, themes, and everything else not listed. Static libraries
   (`*.a`) and libtool files (`*.la`) are not covered by this decision and are not checked by V9. Table `RUNTIME_EXCLUDED_DIRS` in `src/gnomes/tables.rs`;
   legacy carries the same list (section 13). Measured effect: the `devel`/`docs` share of the monolith (715 MB, about 20 percent) is not rebuilt into bricks.

   **Host-only lists** (V4, one source of truth in `src/gnomes/tables.rs`, mirrored byte for byte in legacy): package names `RUNTIME_HOST_ONLY`, package
   prefix `libblockdev-`, file globs `RUNTIME_HOST_ONLY_FILES` (from Q18 also `lib/libudisks2*.so*`, `lib/libupower-glib*.so*`, `lib/libblockdev*.so*`,
   `lib/libbd_*.so*`, `lib/libbytesize*.so*`, `lib/libcryptsetup*.so*`, `lib/libparted*.so*`, `lib/libdevmapper*.so*`, `lib/libsensors*.so*`, and
   `bin/{mdadm,udisksctl,udisksd,upower,upowerd,cryptsetup,parted}`) and directories `RUNTIME_HOST_ONLY_DIRS` (from Q18 also `lib/udisks2`, `lib/libblockdev`, `share/udisks2`).

## 5. Manifest formats (JSON, UTF-8, one document each)

### 5.1 `.bricks/layout.json`

```json
{
  "schema": 1,
  "spec": "underpants-runtime-bricks/1",
  "profile": "all",
  "generation": 7,
  "built": "2026-10-17T10:00:00Z",
  "bricks": ["core", "x11", "data", "qt6", "kde"],
  "host_only": ["mesa", "libdrm", "vulkan-icd-loader"]
}
```
`schema` MUST be 1. `spec` MUST equal the string above. `generation` is an integer, +1 for every swap. `bricks` has no duplicates.
`host_only` copies the package names that this runtime leaves to Slackware (from the manifest `host_only`).

### 5.2 `.bricks/<brick>.json`

```json
{
  "schema": 1,
  "spec": "underpants-runtime-bricks/1",
  "brick": "qt6",
  "revision": 3,
  "built": "2026-10-17T10:00:00Z",
  "content_id": "<sha256 hex, section 5.3>",
  "update_set": "",
  "requires": ["core", "x11"],
  "abi": {"qt6": "6.12"},
  "built_against": {},
  "packages": [
    {
      "name": "qt6-base",
      "version": "6.12.0-1.1",
      "repo": "cachyos-extra-znver4",
      "archive_sha256": "<64 hex or empty>",
      "files": [
        {"path": "lib/libQt6Core.so.6.12.0", "type": "file", "sha256": "<64 hex>", "size": 7340032, "mode": "0755"},
        {"path": "lib/libQt6Core.so.6", "type": "symlink", "target": "libQt6Core.so.6.12.0"}
      ]
    }
  ]
}
```

Fields:
- `brick` equals the file name without `.json` and is listed in `layout.json`.
- `revision`: integer >= 1, +1 whenever the brick content changes.
- `update_set`: empty, or an id (`^[a-z][a-z0-9-]{0,31}$`). Bricks sharing a non-empty id MUST be swapped together (section 7).
- `requires`: bricks this brick links against (derived from the pre-flight NEEDED scan at build time).
- `abi` (provides) and `built_against` (consumes): small maps `key -> "major.minor"`. A brick that ships plugins or libraries for a
  family records the family key it was built for. Example: `qt6` has `abi {"qt6":"6.12"}`; `kde` has `built_against {"qt6":"6.12"}`.
  Defined keys: `qt6`, `qt5`, `gst` (gstreamer `0.<minor>`), `python` (`3.14`), `icu` (major), `ffmpeg` (libavcodec major), `gtk3`, `gtk4`. New keys need no code change.
- `packages[].name/version`: the Arch/CachyOS package name and `version-pkgrel` exactly as in the repository database (epoch kept: `1:0.9rc5-1.2`).
  `repo` is the repository that supplied it. `archive_sha256` is the repository's SHA256SUM of the archive, or empty when unknown.
- `files[]`: every non-directory path the package contributes AFTER flattening into the runtime tree. Directories are implied and never listed.
  - `path`: relative to the runtime root, `/`-separated, no leading `/`, no empty, `.` or `..` component, no NUL/newline/backslash/tab, UTF-8, first component one of
    `bin lib include share etc` (`include` stays syntactically legal only so that V9 can name the problem; no file may actually be listed there), never under a dot-directory,
    and not under an excluded dev/doc prefix (section 4 rule 5, V9).
  - `type`: `file` or `symlink` (nothing else: no device, fifo, hardlink record; hardlinks from dedup are plain files).
  - `file`: `sha256` (64 lowercase hex), `size` (bytes), `mode` (4 octal digits). Owner is always `root:root` (not recorded; verified at install, P4).
    The mode MUST NOT have the setuid, setgid or world-write bit (P4).
  - `symlink`: `target`, relative. It MUST NOT be absolute and MUST NOT leave the runtime root when resolved lexically (**[Q13]**: absolute targets are refused in v1).
  - `path` is unique inside the document.

### 5.3 `content_id` (both apps compute it the same way)

Collect every file entry of every package of the brick, sort the entries by `path` (byte-wise), and build the text, one line per entry, `\n` terminated:

```
F<TAB><path><TAB><mode><TAB><sha256>
L<TAB><path><TAB>-<TAB><target>
```
`content_id` = lowercase hex SHA-256 of that text. It does not depend on package names, order of packages, `built`, or `revision`: the same bytes in the
same places always give the same id. It is the integrity anchor checked at install, at audit and before a swap.

### 5.4 Cross-document rules (the validator, both apps)

| Code | Rule |
|---|---|
| V1 | `layout.json` and every `<brick>.json` parse; `schema` is 1; `spec` matches; brick names valid and unique; each listed brick has a file and each brick file is listed |
| V2 | field syntax of section 5.2 (paths, hashes, modes, types) |
| V3 | **Disjoint ownership**: a path appears in exactly one package of exactly one brick. Two owners, in one brick or in two, is a collision and an error |
| V4 | **Host-only**: no package in `host_only`/`RUNTIME_HOST_ONLY` (case-insensitive, includes the Q18 system daemons and disk tools) or with a host-only prefix (`libblockdev-`), no path matching `RUNTIME_HOST_ONLY_FILES` or under `RUNTIME_HOST_ONLY_DIRS` |
| V5 | `content_id` equals the recomputed value |
| V6 | `requires` entries exist and are not the brick itself; no cycle unless every brick of the cycle shares one non-empty `update_set` |
| V7 | every `built_against[k]` is matched by exactly one brick with `abi[k]` equal to it (a mismatch means "rebuilt for another ABI", see P8) |
| V8 | no path under `.bricks`, `.db`, `.gnomes`; no path equals a metadata file |
| V9 | **No dev/doc content** (Q9): no path equal to or below an excluded prefix of section 4 rule 5 (`include`, `lib/cmake`, `lib/pkgconfig`, `share/pkgconfig`, `share/cmake`, `share/aclocal`, `share/man`, `share/doc`, `share/info`, `share/gtk-doc`, `share/devhelp`). `share/locale` is allowed |

Severity: V1, V2, V3, V4, V5, V8, V9 make the layout `Broken` when found in an INSTALLED layout, and are vetoes for a candidate (nothing is touched). V6, V7 and the mode bits of P4 are vetoes at update time and warnings in the state of an installed layout (state stays `Bricks`, findings are reported). The mode check (setuid, setgid, world-write) uses the code `P4` even when found by the validator.

## 6. Registry and the road to Option A

Option C keeps the authoritative record in the brick manifests. Option A (per-package registry) is a mechanical split of the same data:

| Option C (this spec) | Option A (later) `.db/<name>-<version>/` |
|---|---|
| `packages[]` entry | one directory `<name>-<version>` (version with `:` replaced by `_`) |
| `name`, `version`, `repo`, `archive_sha256`, brick | `desc`, pacman-style blocks: `%NAME%`, `%VERSION%`, `%REPO%`, `%BRICK%`, `%ARCHIVE_SHA256%`, `%PROVIDES%` |
| `files[].path` | `files`: `%FILES%` then one path per line (pacman local db shape), sorted |
| `files[].sha256`, `size`, `mode`, `target` | `hashes`: `sha256sum` format (`<sha256>  <path>`); symlinks as `link:<target>  <path>` |

The mapping is 1:1 and lossless. A tool that holds the Option C manifests can emit the Option A `.db` and the reverse. Until the owner chooses
Option A for updates, `.db` MUST NOT be written by anyone. The registry is NEVER written to `/var/log/packages` by our tools, and the
runtime records are the only source of file ownership inside the runtime; the Slackware package database is not consulted for them (DECIDED **[Q1]**: bricks live outside the pkgdb).

Exact ownership cannot be reconstructed afterwards on this machine (measurement doc section 1): the builder MUST record `path`, `sha256`, `mode`, owning package and
version WHILE it extracts each archive (it already has the archive open). DECIDED **[Q2]**: build-time recording is the only way; nobody downloads the roughly 900 MB
`*.files` databases for a retrofit. Ownership of the existing monolith is therefore recorded at the next runtime build (the migration build, section 12).

## 7. Naming, versioning, update sets

- Brick revision: integer (`revision`). A brick is "changed" when its `content_id` changes. The layout `generation` counts swaps.
- Archive form of a brick (DECIDED **[Q1]**: NOT a Slackware package, never registered in `/var/log/packages`): the updater fetches or builds a brick as an archive
  `underpants-runtime-<brick>-2.<revision>-x86_64.tar.zst` (the `2.` prefix marks layout 2; the old monolith is layout 1.1, `underpants-runtime-all-1.1-...`), extracts it as root
  into `runtime.next` (section 9), and records it only in the brick manifests. The archive carries `opt/underpants/runtime/.bricks/<brick>.json` and nothing outside
  `/opt/underpants/runtime` (rule 4 of CLAUDE.md section 2). Built with `tar --owner=0 --group=0 --numeric-owner`. Neither `installpkg` nor `upgradepkg` is used for bricks.
- **Update set**: bricks with the same non-empty `update_set` are prepared, pre-flighted and swapped as one unit. Decided sets: `gtk`+`gstreamer` as update set `gtk-media` (**[Q4]**); candidate:
  `qt6`+`kde` when Qt changes minor. An update that changes `abi[k]` of a brick MUST include (or already have rebuilt) every brick whose `built_against[k]` names it.
- Version comparison of package versions uses the existing `vercmp` (epoch aware) in both apps; do not invent a second one.

## 8. Pre-flight ("seer"): everything that is checked BEFORE anything changes

The pre-flight runs against the CANDIDATE tree `runtime.next`, never against live. It is read-only. Any veto stops the update; the plain sentence for
the user is one line, the detail goes to the Spider-Sense log (category `runtime`).

| Code | Check |
|---|---|
| P1 | candidate manifests pass V1, V2, V5 and the files on disk match their `sha256`/`size`/`mode`/`target` (every file of every changed brick) |
| P2 | V3 (disjoint ownership) over the whole candidate |
| P3 | V4 (host-only) and V9 (no dev/doc content) over the whole candidate |
| P4 | ownership and permissions in the candidate: every entry `root:root`, no setuid/setgid, no world-writable, no symlink leaving the root |
| P5 | **NEEDED closure.** For every ELF file in the candidate runtime AND in every app tree `/opt/underpants/pkgs/*/{bin,lib}`: read `NEEDED` (`readelf -d`), resolve it in the order the wrappers use: app `lib`, candidate runtime `lib`, `/opt/underpants/common/lib`, then the host (`/usr/lib64 /lib64 /usr/lib /lib`). Veto on any NEW unresolved entry compared with `.bricks/baseline-unresolved.json`. FACT: the monolith has a baseline of about 40 optional unresolved sonames (`libmpi`, `libviskores_*`, `libnetcdf`, `libpyside6`...) that are NOT bundled on purpose |
| P6 | **Soname removal.** A soname present in live and absent in the candidate that some ELF file (pool or app) still needs is a veto. Old sonames stay until no consumer needs them (the update set keeps the old file, as an extra path owned by the old package, until the next generation) |
| P7 | **Plugin directories** (NEEDED scanning cannot see `dlopen`): each directory below must belong to the brick that owns its host library, and every `.so` inside must pass P5. Directories: `lib/qt6/plugins`, `lib/qt6/qml`, `lib/qt/plugins`, `lib/qt/qml`, `lib/gstreamer-1.0`, `lib/gtk-3.0`, `lib/gtk-4.0`, `lib/gio/modules`, `lib/gdk-pixbuf-2.0`, `lib/girepository-1.0`, `lib/glycin-loaders`, `lib/libproxy`, `lib/sasl2`, `lib/krb5`, `lib/ossl-modules`, `lib/engines-3`, `lib/webkit2gtk-4.1`, `lib/python3.*`. A brick may add files below a plugin directory only in a named subdirectory it owns exclusively (KDE does so under `lib/qt6/plugins/kf6`, `plasma`, `kwin`, ...); the owning brick is recorded by V3 |
| P8 | **ABI keys.** If the candidate changes `abi[k]` (for example Qt 6.12 to 6.13), every brick with `built_against[k]` must be in the same update set and must itself be rebuilt (its `built_against[k]` equals the new key). Otherwise veto |
| P9 | disk space for the candidate (hardlink clone is cheap; only changed files count) plus 10 percent, on the same Btrfs |
| P10 | no process other than the updater has the runtime tree as a loader path in `/proc/<pid>/maps` for a brick in the update set; if one has, hold the update and say which app to close (**[Q10]**) |
| P11 | the Btrfs snapshot gate (section 10) succeeded |

The `baseline-unresolved.json` file: `{"schema":1,"generation":7,"unresolved":["libmpi.so.40", "..."]}`, written after every successful swap from the
final P5 result, so the next update compares against what was true after the last good swap.

## 9. Atomic swap and rollback (Option A mechanics, used from the first brick update)

1. Take `/opt/underpants/.runtime.lock` (flock, non-blocking; a second updater stops with one plain sentence).
2. Build `runtime.next` as a hardlink clone of `runtime` (`cp -al` semantics, same filesystem). Files of the changed bricks are REPLACED by
   remove-then-create (a new inode); NEVER write into a file in place, because hardlinks would change the live tree too.
3. Remove only the old files of the changed packages, add the new ones. Refuse on any path owned by another brick (V3).
4. Update the brick manifests, `layout.json` (`generation` + 1), the aggregate `.gnomes/manifest.json` (**[Q12]**) and `baseline-unresolved.json` inside `runtime.next`.
5. Run the pre-flight (section 8) on `runtime.next`. Any veto: delete `runtime.next`, nothing else has changed. Done.
6. Snapshot gate (section 10), as root and as late as possible.
7. Swap: `renameat2(runtime, runtime.next, RENAME_EXCHANGE)` (one atomic call: there is no instant without a `runtime`). Now `runtime.next` holds the
   OLD tree. Remove the previous `runtime.prev`, then rename `runtime.next` to `runtime.prev`.
8. Run the P5 scan once more on the live tree (read-only) as a post-check. If it shows a NEW unresolved entry: roll back (step 9) and say so.
9. **Rollback** (also user-triggerable): `renameat2(runtime, runtime.prev, RENAME_EXCHANGE)`. One call, the old tree is live again. The generation goes back by the manifests the old tree carries.

Running programs keep their already opened files (old inodes live on); programs that start or `dlopen` after the swap see the new tree. That is why P10 exists (**[Q10]**).
Crash safety: if the process dies before step 7 the live tree is untouched and `runtime.next` is garbage to delete; if it dies between the exchange and step 8 both
trees exist and `Bricks` state is valid; a leftover `runtime.next` or `.prev` is reported, never auto-deleted without the lock.

## 10. Snapshot gate

Before step 7, `SnapshotSentinel::create_install_gate_snapshot` (B8) MUST succeed: Btrfs plus snapper present means fail closed (no snapshot, no swap).
Where there is no Btrfs/snapper, the update continues with the `runtime.prev` rollback as the only lifeline and says so in the log. The legacy app does the same
with its own implementation of the same behaviour. Snapshot retention follows the existing 2-snapshot, 48 h rule.

## 11. Wrappers, RPATH and app packages stay unchanged

Nothing in this spec changes: the `/usr/bin/<app>` wrapper, `LD_LIBRARY_PATH` order (app, runtime, common, host), RPATH strings written by `patch_elf_rpaths`, `APP_ROOT`,
desktop files, icons, or the app packages `underpants-<app>-*_gnomes` under `/opt/underpants/pkgs/<app>`. All runtime files keep the path `/opt/underpants/runtime/<bin|lib|include|share|etc>/...`.
The only new things under the runtime root are dot-directories (`.bricks`). The pre-flight uses the wrapper's own search order as its model; if the wrapper contract ever
changes, section 8 P5 changes with it.

## 12. Migration of the existing monolith (user-run; NOT implemented, NOT started)

Preconditions (CLAUDE.md 13.3): Rust and legacy both implement this spec and pass the shared fixtures; the Step 2 repair of the tainted base is done; the owner has decided **[Q1] [Q2] [Q3] [Q11]** (section 14; the migration timing is the owner's and comes after parity and the Step 2 repair); a snapshot exists.
Outline for the owner to run, one tool, as root only for the last step:
1. State is `Monolith`. Take a Btrfs snapshot.
2. Build every brick from the same repository packages (same versions as the manifest) into `runtime.next` while RECORDING ownership (section 6, Q2: no `*.files` download). The monolith is not touched.
3. Diff: the candidate file set MUST equal the live file set (same paths, same bytes), except (a) metadata dot-directories, (b) files removed on purpose by the owner decisions Q9 (dev/doc content) and Q18 (host-only system daemons and disk tools), which the report lists one by one. Any other difference stops the migration.
4. Pre-flight section 8, with the monolith as the baseline (P5 baseline taken from live).
5. Swap (section 9). `runtime.prev` now holds the monolith tree.
6. Retire the monolith package record (Q1: bricks live outside the pkgdb, so the old `underpants-runtime-all` log entry must go). A Slackware `removepkg` WOULD delete the files it lists, which by then are the swapped-out tree or, worse, shared paths; so this is a dedicated, snapshotted step that removes only the log entry and verifies that no file of the live tree is touched. Its exact mechanism is designed and tested in a fake root before the owner runs it.
7. State becomes `Bricks`; the convert prompt stays hidden until then and is removed afterwards.
Rollback at any point before step 6: exchange back. After step 6: restore the snapshot.

## 13. What the legacy app needs (listed, not implemented here)

Same spec, same fixtures (Rust: `tests/golden/runtime_spec/`; legacy: `docs/runtime_spec_fixtures/`, because `tests/` is gitignored there; byte-identical copy; an otherwise empty `root/` such as in `absent` carries a `.keep` file), no shared code. Legacy tasks (mirrors of the Rust H-series, IDs 7A.. by the owner):
1. `runtime_state()` returning the five states of section 2 for a fake root (Python, `json` + `hashlib` only).
2. Reader and validator for `layout.json` and `<brick>.json` with the rules V1-V9 and the `content_id` computation of section 5.3.
3. The same host-only lists used by V4, extended with the Q18 names, the `libblockdev-` prefix, files and directories (section 4 rule 5; `gnomes_pacman.py` today lacks the Q18 entries), and the Q9 excluded-prefix list used by V9; refuse a brick containing them.
4. Make the existing writers (`RuntimeManager`, `transmute_runtime_profile`, `deduplicate_storage`) refuse in state `Monolith`/`Broken`/`Mixed` once bricks exist; until then no behaviour change.
5. Later: builder that records ownership while extracting, the pre-flight P1-P11, the swap, with the shared fixture results as the acceptance test.
6. The same plain sentences for the user (one line per veto, Mister Kim wording) from a shared message list.

## 14. Decided (owner, 2026-10-17)

All 18 questions are decided. "Agent default accepted by owner 2026-10-17" means the default of draft 1 became binding unchanged.

| ID | Decision | Date | Reason |
|---|---|---|---|
| Q1 | Bricks live OUTSIDE the Slackware package database: own manifests plus registry, atomic swap and rollback (sections 6, 7, 9, 12) | 2026-10-17 | Owner rule: the runtime never writes `/var/log/packages` |
| Q2 | NO 900 MB `*.files` download for file ownership; ownership is recorded at the next runtime build (build-time recording, sections 6, 12) | 2026-10-17 | Not worth the download; the builder has every archive open anyway |
| Q3 | `core` stays one coarse brick for the pilot, split later. Agent default accepted by owner 2026-10-17 | 2026-10-17 | Fewest moving parts for the first brick update |
| Q4 | `gtk` and `gstreamer` form ONE update set `gtk-media`. Agent default accepted by owner 2026-10-17 | 2026-10-17 | They need each other; moving them together is safer than splitting a true cycle |
| Q5 | VTK Python bindings (`lib/python3.14/vtk*.so`) belong to `cad`. Agent default accepted by owner 2026-10-17 | 2026-10-17 | They follow VTK, not the interpreter |
| Q6 | Package-to-brick name rules live in a spec appendix plus fixtures check (generated into both sources). Agent default accepted by owner 2026-10-17 | 2026-10-17 | Prevents drift between the two apps |
| Q7 | KDE is its own brick `kde` on top of `qt6`. Agent default accepted by owner 2026-10-17 | 2026-10-17 | Large, optional, follows Qt minor versions |
| Q8 | Audio codecs (opus, vorbis, flac, ...) stay inside `ffmpeg`. Agent default accepted by owner 2026-10-17 | 2026-10-17 | They move together with libav* |
| Q9 | Do NOT ship headers, cmake, pkgconfig, man pages and docs; KEEP locale files. Exact prefixes in section 4 rule 5, validator rule V9, fixtures `dev_docs_leak` and `locale_kept` | 2026-10-17 | Apps do not compile against the pool; about 715 MB saved; apps use translations |
| Q10 | A swap is held while apps from the runtime run, and the app is named. Agent default accepted by owner 2026-10-17 | 2026-10-17 | A running app must never see a half-new tree |
| Q11 | The owner runs the migration, after parity and the Step 2 repair. Agent default accepted by owner 2026-10-17 | 2026-10-17 | No migration before the base is clean |
| Q12 | Keep the aggregate `.gnomes/manifest.json`, derived at every swap. Agent default accepted by owner 2026-10-17 | 2026-10-17 | Existing readers keep working |
| Q13 | Absolute symlink targets inside the runtime are refused in v1 (re-check at the first real build). Agent default accepted by owner 2026-10-17 | 2026-10-17 | Keeps the tree relocatable and lexically checkable |
| Q14 | Names as written: `underpants-runtime-<brick>-2.<revision>-x86_64...` and the `.bricks` directory. Agent default accepted by owner 2026-10-17 (the archive suffix follows Q1, section 7) | 2026-10-17 | Clear separation from layout 1.1 |
| Q15 | Apps with private copies of runtime libraries are out of scope. Agent default accepted by owner 2026-10-17 | 2026-10-17 | A pool update cannot reach them; they follow their own app updates |
| Q16 | PGPSIG / database signature verification is a separate task with its own ID. Agent default accepted by owner 2026-10-17 | 2026-10-17 | Independent of the brick format |
| Q17 | `runtime.prev` lives for one generation (deleted at the next swap). Agent default accepted by owner 2026-10-17 | 2026-10-17 | One rename of rollback is enough; disk use stays small |
| Q18 | udisks2, upower, mdadm, cryptsetup, parted, libblockdev (and every `libblockdev-*`) and similar system daemons and disk tools are REMOVED from the runtime and become host-only (V4, section 4 rule 2 and "Host-only lists"). `desktop-services` keeps only `xdg-desktop-portal`, `xdg-dbus-proxy`, `xdg-utils`, `bubblewrap` | 2026-10-17 | System services and disk tools do not belong in an app runtime; Slackware ships its own |

Q18 scope note (agent, for the owner to confirm at the first real build): "similar" was read as `device-mapper`, `libbytesize`, `volume_key`, `lm_sensors`, `accountsservice`, `iio-sensor-proxy` (same family: disk or hardware daemons and their helper libraries). If an app turns out to need one of their libraries, the P5 pre-flight reports it as an unresolved NEEDED and the host copy (Slackware) is used.

## 15. Shared fixtures and the Rust reference reader

`tests/golden/runtime_spec/<case>/{root/,expected.json}` are fake roots (committed, tiny, fake file contents). `expected.json` holds
`{"state": ..., "codes": [sorted unique finding codes], "writers_allowed": bool}`. The legacy repo gets a byte-identical copy and MUST reproduce
every `expected.json` from its own implementation. Cases: `bricks_ok` (with real files on disk), `absent`, `monolith`, `mixed`, `broken_missing_brick` (V1, V6, V7),
`collision` (V3), `host_only_leak` (V4), `bad_content_id` (V5), `bad_path` (V2), `abi_mismatch` (V7, state stays `Bricks`), `cycle` (V6, state stays `Bricks`),
`update_set_cycle_ok` (no finding), `setuid_mode` (P4, state stays `Bricks`), and since draft 2: `dev_docs_leak` (V9, Broken: include, cmake, pkgconfig, man, doc, info, gtk-doc),
`locale_kept` (no finding: `share/locale` is allowed), `host_only_disk_tools` (V4, Broken: udisks2, libblockdev-part by prefix, mdadm, cryptsetup), `desktop_services_small_ok`
(no finding: a `desktop-services` brick with only xdg-desktop-portal and bubblewrap). The `content_id` values in the fixtures were produced by an independent Python
implementation of section 5.3 and are reproduced by the Rust reader (`src/gnomes/bricks.rs`, read only: parser, validator V1-V9, state, `verify_files` P1; no writer,
no installer). The `.gnomes/manifest.json` of the existing monolith is deliberately not a brick document: the reader reports `Monolith` for it.
