# Config base store (format 1, 2026-10-14)

Shared by slacky-update (legacy) and slacky-update-rs (Rust). Names files, fields and rules; no code. Both apps MUST read
and write exactly this layout (legacy shares only this spec, never code). Part of the Spider-Sense contract
(`docs/spidersense_spec.md`, section 13).

## 1. Purpose

Slackware keeps no copy of the stock text of a config file after an upgrade, so a 3-way comparison has no base. The store
keeps, per config path, the stock text Slackware shipped ("theirs") and the stock text the live file derives from ("base").

## 2. Location, modes, safety

- Directory `/var/lib/slacky-config/`, owner root, mode 0700. Files inside: owner root, mode 0600 (configs may hold secrets).
- Never inside `/etc`, never in a package, never in `/var/log/packages`.
- An app opens the store only when: every path is a real directory or regular file (no symlink anywhere), owner equals
  root (uid 0), no group or other permission bit is set. Otherwise the store is treated as untrusted and not used.
- Writes: temp file in the same folder (`O_EXCL`, `O_NOFOLLOW`, mode 0600), fsync, rename, fsync of the folder.
  Index changes are done under an exclusive `flock` on `lock` (same folder, 0600).
- Size caps: one object <= 2 MiB, index <= 16 MiB, at most 20000 objects. Over a cap: skip that file and say so, never truncate.

## 3. Layout

```
/var/lib/slacky-config/
  lock                 empty file, flock target
  index.json           the index (section 4)
  objects/<sha256>     content, written once, name = lowercase hex sha256 of the bytes (content addressed)
  undo/<txid>/         reserved for the apply step (journal); not written by format-1 capture
```

An object is verified by re-hashing when it is read; a mismatch means the object is corrupt and is ignored.

## 4. index.json

```json
{
  "format": 1,
  "writer": "slacky-update-rs 1.0.0",
  "updated_at": "2026-10-14T12:00:00+00:00",
  "files": {
    "etc/rc.d/rc.M": {
      "pkg": "sysvinit-scripts",
      "pkg_version": "16.0-noarch-7",
      "theirs": "<sha256>",
      "base": "<sha256>",
      "base_source": "capture",
      "mode": "0755",
      "uid": 0,
      "gid": 0,
      "captured_at": "2026-10-14T12:00:00+00:00",
      "captured_from": "dotnew",
      "late": false,
      "derivation": "replace"
    }
  }
}
```

- Key: path relative to `/`, no leading slash, no `..`, without the `.new` suffix, always below `etc/`.
- `theirs`: stock text of the installed package version. `base`: stock text the LIVE file derives from, or `null` when unknown.
  The base moves forward only when the live file is reconciled against a newer stock (replace, merge, drop of an identical copy). The
  apply step moves it in the same change set as the file: `base` becomes the sha256 of the written stock text (the `.new`), for a
  merge too (the person's edits are then the difference between the merged file and that base). If the index update fails, the files
  are put back.
- `base_source`: `capture` (exact), later `snapshot:<n>`, `tool-backup`, `inferred-pristine` (weak: preview only), or `null`.
- `mode`, `uid`, `gid`: of the file the stock text was read from (octal string, numbers).
- `captured_from`: `dotnew` (read from `X.new`) or `live` (read from `X`, see section 5).
- `late`: true when the capture could not be tied to the install moment (the base is then `null`).
- `derivation` (optional, added 2026-10-14, H1): how the base last moved: `replace`, `merge o=<sha12> b=<sha12> t=<sha12>`,
  `identical`, or `live equals the earlier stock text`. Absent for a plain capture. Readers that do not know it ignore it.
- Unknown keys must be preserved when an app rewrites the index. A reader that sees `format` > 1 must not write.

## 5. Capture rules (exact)

For each package in `/var/log/packages` that was installed or upgraded in this run (package db before/after), for each file
list line `etc/X.new` (below `etc/`, plain regular file, not `passwd`, `group`, `shadow`, `gshadow`):

1. `X.new` exists and is a regular file: stock = `X.new`; `captured_from = dotnew`. (The package extraction overwrote it, so it
   is the shipped text of the installed version.) The base stays what the index already had; if the index had no base but the
   previous `theirs` equals the live `X`, the base becomes that previous `theirs` (the file was never edited). The same holds
   when an older base was recorded: if the live `X` equals the previous `theirs` (never edited, or replaced by another tool
   such as slackpkg), the base catches up to that previous `theirs`.
2. `X.new` is absent: Slackware moved it over `X` or dropped an identical copy, so stock = `X`; `captured_from = live`.
   Valid only when `X` is a regular file whose modification time is not later than the package db entry's time plus 120 s
   (otherwise a person may have edited it: `late = true`, `base = null`). If valid: `theirs = base = sha(X)`, `base_source = capture`.
3. Before an upgrade, already waiting `X.new` files are recorded the same way (rule 1) so the old stock text is not lost.
4. A symlink, a non-regular file, an unreadable file or an over-cap file is skipped and counted, never followed.

The pkgdb file name `name-version-arch-build` gives `pkg` and `pkg_version` (`version-arch-build`).

## 6. Compatibility

`format` is the version. Format 1 readers ignore `undo/`. A change that breaks format 1 raises `format` and both apps change in
the same step. Fixtures for both apps: a fake root with a package db entry listing `etc/X.new`, an `X.new` and/or `X`.

## 7. Journal of replaced files (format 1 extension, 2026-10-14)

Every file the config doctor replaces or merges keeps its previous version in the store, so a Doctor screen can offer
"Restore previous config files". Same trust rules as section 2 (folders 0700, files 0600, root, no symlinks).

```
undo/<txid>/manifest.json
```

- `txid`: `[A-Za-z0-9_-]{1,64}`, sorts by time (for example `20261014T120000-a1b2`).
- `manifest.json`: `{ "format": 1, "txid": "...", "time": "<rfc3339>", "entries": [ ... ] }`. A reader ignores a manifest with a
  higher `format`, a damaged one, and entries whose `txid` differs from their folder.
- Entry: `{ "txid", "path", "old_sha", "new_sha", "time", "reason", "action" }`.
  - `path`: as an index key (`etc/...`, no `.new`). `old_sha`: sha256 of the file before the change, or `null` when it did not
    exist (nothing to restore). `new_sha`: sha256 of what was written. Both byte strings live in `objects/<sha>` (written with
    the same rules as section 3, and never pruned while a manifest refers to them).
  - `reason`: stable code (`replace`, `merge`, `drop`, `restore`, ...); `action`: the planner action or `restore`.
  - `attrs` (optional, added 2026-10-14): `{ "mode": <permission bits>, "uid": n, "gid": n }` of the file that was written (for a
    `drop`, of the file that stayed). Lets an install of a file that did not exist before (`old_sha == null`) be undone and a
    restore put the right owner back. A `drop` entry has `old_sha: null` (nothing to restore) and `new_sha` = the unchanged live file.
- A restore backs up the current file first (its sha becomes `old_sha` of the restore entry), so a restore can be undone with
  the same screen. Restoring `passwd`, `group`, `shadow`, `gshadow` is refused.
- Pruning (keep the last N transactions) is not part of format 1 yet.
