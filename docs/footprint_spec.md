# Footprint Guard specification (shared by slacky-update and slacky-update-rs)

Both apps implement these rules independently (legacy: `lib/gnomes_pacman.py` `footprint_*`; Rust:
`src/packages/footprint.rs`). They share this document, never code. A change here must be made in both
implementations in the same step, with a parity test (same verdict for every file of every installed own package).

## Purpose
Packages we build must never overwrite, shadow or alter a file owned by an official Slackware package, and must
not ship files with a global effect on the system unless vetted.

## Own packages
A package in `/var/lib/pkgtools/packages` is ours if its name starts with `underpants-` or `cachyos-`, or ends with
`_slacky` or `_gnomes`. Everything else is a Slackware (or SBo/third-party) package.

## Ownership map
Relative path -> owning package, built read-only from:
1. Every non-own package's `FILE LIST:` (skip blank lines, `./`, entries ending in `/`, `install/*`). A listed `X.new`
   also makes `X` owned (Slackware's doinst installs the config file as `X`).
2. Every non-own package's install script in `/var/lib/pkgtools/scripts`: lines `( cd DIR ; ln -sf TARGET LINK )`
   own the path `normpath(DIR/LINK)`.
First owner wins.

## Verdict per staged file (files and symlinks only; directories are never judged)
In this order:
1. `install/*` -> keep.
2. Unless the path is in VETTED:
   - `etc/ld.so.conf.d/*` -> drop ("changes the system-wide linker search path")
   - `etc/cron.*` -> drop ("installs a root cron job")
   - `etc/profile.d/*` -> drop ("changes the login environment for every user")
   - `etc/rc.d/rc.*` whose basename (without a trailing `.new`) is not in OWN_DAEMONS -> drop
     ("service script from a dependency")
3. Path present in the ownership map -> drop ("owned by Slackware package <name>").
4. Otherwise keep.

## VETTED
etc/cron.hourly/suse.de-snapper, etc/cron.hourly/snapper-cleanup(.new), etc/cron.hourly/snapper-timeline(.new),
etc/profile.d/nvidia-vaapi.{sh,csh}, etc/profile.d/rocm.{sh,csh}, etc/ld.so.conf.d/rocm.conf,
etc/cron.hourly/slacky-snapper-limine-sync, etc/cron.weekly/slacky-update-check, etc/profile.d/slacky-hidpi.{sh,csh}

## OWN_DAEMONS
rc.lact, rc.scx, rc.ananicy-cpp, rc.gamemode, rc.coolercontrol, rc.asusd, rc.syncthing, rc.spacenavd, rc.dmemcg-booster

## Modes
- enforce (DEFAULT since 2026-10-11, owner decision after report mode would have shipped a `/usr/bin/env` wrapper):
  offending files are removed from the staging tree only (never outside it); one line
  `:: Footprint check: N file(s) in <pkg> removed. Details: <file>`; silent when nothing is removed. If the ownership
  map cannot be built, the package is not built (fail closed).
- report (`SLACKY_FOOTPRINT_MODE=report`): nothing is removed; the same line says "would be removed (report only)".

## Archive gate (before any install)
Every entry of the package archive must be owned `0/0` (root:root); otherwise the package is not installed.
