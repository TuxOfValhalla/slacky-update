# Healing in the legacy app: tasks 9A-9D (spec for the owner, T9)

Status: SPEC ONLY. Nothing in the legacy repo was edited. The owner implements this in `/home/tux/development/slacky-update`
(bash, `lib/*.sh`) and commits there himself. Rust mirror: T0-T8 (`docs/spidersense_spec.md` section 14,
`docs/spidersense_healing/healing_design.md`). The two apps share this document and the message sentences, never code
(golden rule 7: legacy must not call, exec or path-reference the Rust binary).

## 0. What legacy does and does not do

Legacy DETECTS and ADVISES. It never repairs.

| Does | Does not |
|---|---|
| Read the package database (`/var/log/packages`) and compare it with the disk (read only, normal user is enough) | Download, install, reinstall, remove, chown or rename anything on behalf of the heal feature |
| Print plain sentences and ONE command the person can run: `slackpkg reinstall <names>` | Ask for sudo, write a state file, keep a "flap" record, or ask a repair question |
| Hold a package that is about to be upgraded when a folder of it was replaced by a link | Run anything at login, from cron, from the tray or from inotify (those only record) |
| Write findings to its own flight recorder (category INTEGRITY / OWNERSHIP) | Touch `.new` files, `/etc`, boot files, accounts, the package database |

Reason: `slackpkg` does the signature check by itself and is the only writer to the package database. This keeps legacy
simple and safe for 1.0 LTS. If legacy ever applies a repair, it is a later, separate decision: only via
`slackpkg reinstall` behind its own consent (rule H0 of the spec section 14.1 then applies).

Global output rules (owner, `docs/output_style.md`): silent when nothing is wrong, no emoji, no ASCII decoration, one plain
sentence per item, English via the catalog, nothing printed by watchers.

## 9A. Fix the regression 6A-154 (highest priority, do first)

Problem (FACT, owner's machine 2026-10-14): `heal_host_sovereignty` (`lib/gnomes_pacman.py`, around the "Underpants Gnomes
sovereignty" audit) and `cleanup_stale_wrappers` delete a wrapper in `/usr/bin` whose name a Slackware package owns, without
putting the stock file back, and scrub package logs. Result: stock programs such as `xrandr` were lost.

Required behaviour:
1. Rule H0: a delete is allowed only if the SAME step puts the stock content of that path back. Legacy cannot do that, so the
   delete becomes REPORT + PRINT THE COMMAND. A path owned by a Slackware package is never removed.
2. Never edit or scrub `/var/log/packages` or `/var/lib/pkgtools` from legacy code.
3. When a wrapper shadows a stock file, print once (per run, all names together):
   `<pkg> is missing <n> of its files (for example /<path>), so some programs may not start.` then the command line
   (section 9B). Nothing else.
4. Wrappers that are NOT owned by any Slackware package keep their current handling (unchanged).

Done when: the 6A-154 fixture (section 9D) shows no deletion and prints the command.

## 9B. Detect and advise (`spidersense --heal`-equivalent, read only)

Where: the planned standalone legacy Spider-Sense module (`lib/mod_spidersense.sh`, tasks 3A-3J) or, until it exists, the
doctor. Entry point suggestion: `slacky-update --heal-check` (read only; name is the owner's choice, keep it one flag).

### Audit (same findings as the Rust C3 audit)
For every installed package (one pass over `/var/log/packages/*`, `FILE LIST:` section, normal user):
- skip entries: `install/...`, anything ending in `.new`, `dev/...`, `tmp/...`, `boot/...` (the boot partition may be
  unmounted), incoming library swaps (`lib64/incoming/`), and `./` ;
- a listed FILE (no trailing `/`) that does not exist (`[ -e ] || [ -L ]`, one `lstat` each) is MISSING;
- a listed FOLDER (trailing `/`) that exists as a symbolic link (`[ -L ]`) is TYPE DAMAGE (dir replaced by a link).
  Not damage when the package's own install script makes the link on purpose: `var/lib/pkgtools/scripts/<pkg>` contains
  `( cd <dir> ; rm -rf <name> )` plus `ln -sf ... <name>` for that name (also the same for `var/log/packages/<pkg>`'s
  `install/doinst.sh` text when present). `var/log/setup` is such a case.
- octal escapes in file names (`\305\221`) are decoded before the `lstat`.
- Speed target: under 3 s for about 2000 packages (the Rust audit does this with 8 threads; bash may use `xargs -P`).

### Classes (only these three are printed; legacy never repairs)
| class | when | what legacy prints |
|---|---|---|
| advice | official Slackware package (build tag is a plain number, no `_slacky`, `_gnomes`, `_SBo`, `compat32`, no prefix `underpants-` / `cachyos-`) with missing files or type damage | the sentence, and the package goes into the command |
| advice | anything else (SBo, our own, third party, multilib `compat32`) | the sentence for "not an official Slackware package" (no command for it) |
| never | any damaged path in the NEVER list (`etc/passwd`, `shadow`, `group`, `gshadow` and their `-` backups, `etc/sudoers*`, `etc/pam.d`, `etc/security`, `etc/ssh/ssh_host_*`, `root`, `home`, `boot`, `efi`, `dev`, `etc/limine`, `var/log/packages`, `var/lib/pkgtools`, `var/lib/slacky*`, `opt/underpants/runtime`, `lib/modules`, `lib/firmware`, `usr/lib/firmware`, `*.new`) | the "left alone" sentence, NO command for that package |

A config file in `/etc` that differs from stock is customisation, not damage, and is never a finding (legacy does not read file
contents at all).

### Output (silent when clean; exit 0; with damage exit 51 like the Rust `--audit`, if the owner wants an exit code)
Exactly these sentences (keys are the Rust catalog keys; legacy may keep them in its own locale file under the same names):

- missing (`C3_AUDIT_MISSING`): `{pkg} is missing {count} of its files (for example /{example}), so some programs may not start.`
- type damage (`C3_AUDIT_LINKED_FOLDER`): `/{path} should be a normal folder of {pkg} but is a link to {target}, so a reinstall of {pkg} can delete files.`
- not official (`HEAL_ADVICE_THIRD`): `{pkg} is not an official Slackware package; rebuild or reinstall it with the tool you used to install it.`
- never (`HEAL_NEVER`): `{pkg}: /{example} is an account, security, boot or personal file, and a repair never touches those.`
- the command, once, last (`HEAL_COMMAND`): `To restore them yourself: slackpkg reinstall {list}` where `{list}` is the sorted, de-duplicated
  BASE names (no version) of the official packages with a missing file or type damage. Never put a `compat32` package, a package with the
  NEVER class, or a package that is not official in the list.
- install tools damaged (`HEAL_ADVICE_TOOLS`): when `upgradepkg`, `installpkg`, `removepkg`, `explodepkg`, `tar`, `xz`, `gpgv` or `slackpkg`
  is itself missing, print only: `The tools needed to install packages are damaged themselves, so nothing is repaired automatically; restore the safety snapshot or reinstall them from the Slackware installer.`
  and NO command.
- more than 50 packages damaged (`HEAL_ADVICE_MANY`): `{count} packages are damaged, which is too much for an automatic repair; restore the latest safety snapshot instead.` and NO command.
- version note (optional, same as Rust): if `/var/lib/slackpkg/pkglist` shows another version than the installed one for a package, replace its
  line by `HEAL_ADVICE_VERSION`: `The server now has {mirror} instead of {pkg}, so the old version cannot be restored; the next full update brings the files back.`
  and leave it out of the command (a plain `slackpkg reinstall` would otherwise change versions). If `pkglist` is missing: `HEAL_ADVICE_NODATA` once.

Legacy keeps NO state and asks NO question, so there is no 7-day rule and no once-per-day rule in legacy. (If the owner wants the
hint to appear at most once per day when started from a timer, that is the timer's job; the command itself always answers.)

### Flight recorder
Events (category INTEGRITY / OWNERSHIP; paths and counts only, no file contents): `heal.found`, `heal.advice`, `heal.type-hold` (9C).
At most 20 records per run.

## 9C. Pre-upgrade type-damage HOLD, and the post-update sentence (detect only)

### Hold before the upgrade
Point: in the full-update flow, after the plan is known (the list of Slackware/slackpkg packages that WILL be upgraded) and
before anything is installed or the user is asked to confirm.
1. Take the base names (name without `-version-arch-build`, lower case) of the packages in the update set (`slackware_updates` and
   `slackpkgplus_updates` entries such as `a/name-ver-arch-build.txz`).
2. Run the 9B TYPE DAMAGE check for the installed packages with those base names only (cheap).
3. If one or more has a folder replaced by a link: HOLD. Legacy has no per-package hold in `slackpkg upgrade-all`, so it behaves like
   the Rust interim rule: the update stops BEFORE anything changed, with one sentence per held package (first one in full, `N more` for the rest),
   exit code = the same non-zero "stopped by Spider-Sense" code the legacy update already uses for a guard hold. Sentence (`HEAL_TYPE_HOLD`):

   `{pkg} is not upgraded now: the folder /{path} was replaced by a link and the upgrade could lose files. Run \`slacky-update-rs spidersense --heal\` first. Nothing was changed.`

   Legacy must not name the Rust command. In legacy the sentence ends with the legacy advice instead:
   `... could lose files. Run \`slackpkg reinstall {pkg}\` first, then update again. Nothing was changed.` (same words otherwise; key `LEGACY_HEAL_TYPE_HOLD`).
4. A package with only MISSING files (no type change) is NOT held: the upgrade brings the files back.
5. Nothing printed when no package in the set has type damage. Nothing is repaired, nothing is renamed, no sudo.

Why: with a folder replaced by a link, the package's own install script can delete files through the link on upgrade (the 6A-155 mechanism).
Do-nothing risk: the next upgrade of that package turns type damage into data loss.

### After the update
When the update is finished, run the 9B audit once as the normal user. Clean: print nothing (and no "all is well" line). Damage found: print
exactly ONE sentence (key `LEGACY_HEAL_POST_UPDATE_ADVICE`):

`Some installed packages are damaged; run \`slacky-update --heal-check\` to see what can be restored. Nothing was changed.`

(the Rust sentence names `slacky-update-rs spidersense --heal`; legacy names its own flag). Findings go to the recorder. This line is printed
before the final line of the update and never replaces it.

## 9D. Shared fixtures (both apps run the same cases, same verdict and message key)

Files only, fake root (`/tmp/...`, never `/`):
1. 6A-154: stock package `xrandr-1.5.3-x86_64-1` lists `usr/bin/xrandr`; the file is missing. Expect: missing sentence + command `slackpkg reinstall xrandr`; no deletion anywhere; exit 51 when an exit code is used.
2. 6A-155: package `fontconfig-2.18.3-x86_64-2` lists `usr/share/fontconfig/conf.avail/`; on disk that path is a link to `/etc/fonts/conf.avail`. Expect: type damage sentence + command; with fontconfig in the update set: HOLD with the 9C sentence.
3. Intentional link: `var/lib/pkgtools/scripts/foo-1-x86_64-1` contains `( cd usr/share/foo ; rm -rf baz )` and `ln -sf ../bar baz`; `baz` is a link. Expect: nothing.
4. Missing `.new`, `install/`, `dev/`, `tmp/`, `boot/` entries and an incoming library swap. Expect: nothing.
5. SBo package (build `_SBo`) with a missing file. Expect: "not an official Slackware package" sentence, no command line for it.
6. `compat32` package with a missing file. Expect: no command for it.
7. Never-list: a package whose damaged path is `etc/ssh/ssh_host_rsa_key`. Expect: "left alone" sentence, no command.
8. Install tool missing (`sbin/upgradepkg` absent, its package lists it). Expect: only the tools sentence, no command.
9. 51 damaged official packages. Expect: only the "too many" sentence, no command.
10. Clean system. Expect: no output at all, in the check and after an update; and the hold prints nothing for a package that is not damaged or not in the update set.
11. Update set without the damaged package (fixture 2 but update set = `bash`). Expect: no hold.
12. Octal-escaped file names (`F\305\221tan.crt`). Expect: decoded before the check.

Each fixture also asserts: the fake root is byte-identical before and after (detect only), no emoji in the output, every sentence is one line.

## Verification checklist for the owner (legacy)

- [ ] 9A: no code path deletes a wrapper whose name is listed in `/var/log/packages/*`; no write to `/var/log/packages` from legacy.
- [ ] 9B: `--heal-check` is silent on a clean fake root and prints the sentences + the one command on fixtures 1, 2, 5, 6, 7, 8, 9.
- [ ] 9C: hold stops before any install; post-update line appears only with damage.
- [ ] 9D: all twelve fixtures pass; the fake root is unchanged.
- [ ] Legacy contains no reference to `slacky-update-rs` and never executes it; independence rule 1 still holds.
- [ ] Task IDs mirrored in `rs_and_legacy_roadmap.md` (both copies): 9A-9D <-> T0/T1/T2/T8.
