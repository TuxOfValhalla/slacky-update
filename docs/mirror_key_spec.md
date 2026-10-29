# Mirror and key sentinel: shared spec (MS1)

Shared by `slacky-update-rs` and the legacy `slacky-update`. Only formats, thresholds and sentences are shared, never code.
Status: key rules (section 3, 4) implemented in Rust (MS2,
`src/packages/key_store.rs`); mirror rules (section 1, 2, 5) are the spec for MS3-MS7. Legacy: key rules in
`lib/gnomes_trust.py`, mirror rules and alerts in `lib/slacky_sentinel.py`.

## 0. Cadences (owner decision 2026-10-15)
| What | When |
|---|---|
| Mirror ranking and signed mirror-list fetch (all families) | WEEKLY. Plus the failure-driven fallback: a failing mirror sinks to the end of its list and may be re-probed after 10 minutes. |
| Keyring freshness | On EVERY update check. It piggybacks on the repo databases already synced; a keyring package is downloaded only when a newer one is listed than the generation in force. |
| Alerts (section 6) | Evaluated by those same runs (weekly mirror run, per-check keyring run). Each condition is shown at most once per 7 days. |
| Installing a keyring | Never on its own. Only as the first root step of an explicit full update or `--sync-keys`; no sudo prompt anywhere else. |

## 1. Signed mirror lists
Source per family: `pacman-mirrorlist` (Arch, packager-signed), `cachyos-mirrorlist`, `cachyos-v3-mirrorlist`,
`cachyos-v4-mirrorlist` (pinned CachyOS key), `chaotic-mirrorlist` (pinned Chaotic key). Verify with the family verifier
before parsing; never older than the last accepted build date (same rule as keyrings, 2 day future skew).
Line grammar (anything else is dropped): `^#?\s*Server\s*=\s*https://<host>/<path>` with only `$repo`, `$arch`,
`$arch_v3`, `$arch_v4` placeholders; no `http://`, IP literals, userinfo, ports other than 443; at most 1024 entries (Arch ships 424 today) in a list file of at most 128 KiB.
Arch status JSON (TLS only, not signed) may rank and add candidates that pass a probe; it is never a trust input.
Slackware: recommend only, never write `/etc/slackpkg/mirrors`.

## 2. Thresholds
| Name | Value |
|---|---|
| Lag: demote a mirror behind the freshest stamp of the round | more than 6 h |
| Retire: consecutive failures, across at least | 5 failures over 7 days AND not listed in the newest signed list (revive after 30 days for one probe, or when listed again) |
| Alert: live mirrors in a family after a full round | fewer than 2 |
| Alert: no fresh verified signed list | 30 days |
| Alert: a used key expires within | 60 days, and no newer keyring is staged |
| Probe budget | at most 8 candidates per family per run; 1.5 s total wall clock |
| Slackware mirror behind | more than 2 days |

## 3. Key store on disk (shared, written only by root)
`/opt/underpants/keys/<family>/` with `<family>` one of `archlinux`, `cachyos`, `chaotic`:
- `gen.<YYYYMMDDHHMMSS>[-n]/` containing `pubring.gpg` (binary, accepted keys only, export-minimal), `revoked`,
  `trusted` (accepted primary fingerprints, one per line), `meta.json`; all 0644, folders 0755, owner root.
- `current` -> newest generation, `previous` -> the one before; both relative symlinks to a sibling `gen.*`, replaced by
  rename (atomic). Only `current` and `previous` are kept.
- `meta.json` (legacy keys unchanged): `family, keyring_pkg, signed_by, anchors (compiled pins), accepted, revoked,
  vouched, built, mode (bootstrap|refresh)`; added by Rust, optional for readers: `pkgver` (`20260909-1`),
  `builddate` (unix seconds from `.PKGINFO`), `dynamic_anchors` (Arch), `via` (continuity|master_path), `writer`.
  A generation without `pkgver` takes its version from the `keyring_pkg` file name.
- Readers use `current` when valid, else the newest valid `gen.*`; a generation that is unsafe (link, wrong owner,
  group/world writable) fails closed. The snapshot shipped in the app's package is the floor (used when there is no
  generation, and also tried when the generation does not know a signer); the generation's revoked list applies to both.
- Writers MUST apply the monotonic rule below, so one app cannot roll the other back, and take an exclusive `flock`
  on the family folder while checking and writing.

## 4. Keyring package rules (both apps)
A keyring package is `<pkgname>-<pkgver>-<rel>-any.pkg.tar.zst` plus its REQUIRED detached `.sig`; it holds
`.PKGINFO` and `usr/share/pacman/keyrings/{<f>.gpg,<f>-trusted,<f>-revoked}`. Refuse (change nothing) unless:
1. `.sig` present; package name equals the family's; build date not more than 2 days in the future.
2. Monotonic: `(pkgver, rel)` and build date never older than the generation in force; equal version = nothing to do.
3. Every compiled anchor is in `-trusted`, in the ring, not on `-revoked`, not revoked inside the ring.
4. The new `-revoked` list contains every key of the current one (it may only grow; missing list counts as empty).
5. Continuity (Path A): the signature verifies against the ring in force now (generation, else the shipped snapshot).
   If that fails (signer expired or unknown), Path B: the signature verifies against the NEW ring restricted to keys
   accepted under the compiled anchors (Arch: at least 3 certifications by anchors, pacman's rule; CachyOS/Chaotic:
   the pinned key). With no ring at all the same Path B is the bootstrap.
6. CachyOS/Chaotic: the signer's primary key must be a compiled anchor; keys listed in `-trusted`, present in the ring
   and not revoked are then accepted ("vouched"). Arch: a key listed in `-trusted`, not revoked, not expired, with at
   least 3 certifications by anchors in force becomes a dynamic anchor; accepted packagers are then evaluated with
   compiled pins plus dynamic anchors. Compiled pins are the floor and never removed.
Every anchor change is one flight-recorder record (category Supply, `key.anchor_set_changed`); installs, stagings and
refusals are `key.installed`, `key.staged`, `key.rejected`.
User phase may verify and stage (`~/.cache/.../sentinel/keyring_stage/<family>/{pkg,sig,verdict.json}`); the root phase
re-verifies the raw bytes from scratch and never trusts the staged verdict.

## 5. User cache (per app, not shared)
Rust: `~/.cache/slacky-update-rs/sentinel/` (`lists.json`, `health.json`, `state.json`, `keyring_stage/`), 0700/0600,
own uid, no symlinks, size caps, atomic rename. Legacy keeps its own folder with the same file meanings.

## 6. Sentences (English; Norwegian in `locales/nb.json`; one sentence, shown only when a family is at risk)
- Fewer than 2 live mirrors: "Only one download server for {repo} works right now; updates still run, but there is no backup."
- None live: "No download server for {repo} answered. Check your internet connection and try again later."
- No fresh list for 30 days: "The server list for {repo} could not be refreshed for a month; downloads still work from the known servers."
- Key expiring: "A security key for {repo} runs out on {date}; run a full update before then so the new keys can be installed."
- Chain broken (implemented, `KEYS_REFUSED_CHAIN`): "The new security keys for {repo} could not be confirmed, so they were not used; packages from {repo} are held back until this is fixed."
- Older keys (`KEYS_REFUSED_OLDER`): "The security keys offered for {repo} are older than the ones already installed, so they were not used."
- Other failed checks (`KEYS_REFUSED_CHECKS`): "The security keys for {repo} did not pass the safety checks, so nothing was changed; details are in the Spider-Sense log."
- Slackware mirror behind: "Your Slackware download server is {n} days behind; a faster, up-to-date server is available."

## 7. Install flow (MS8, Rust)
User phase (full update, `--sync-keys`): download package and `.sig`, verify, keep only a newer one in the user cache (`keyring_stage/<family>/`).
Root phase: the very first step of the order book (`keyring_install`, one per family, no gate, independent of every other step) re-verifies the raw
bytes from scratch and writes the generation; a refusal changes nothing and does not fail the run. One password prompt for the whole update; none for keys alone
(except `--sync-keys`, which the person ran on purpose). Expiry radar: nearest future expiry of the anchors, extra masters and the generation signer,
recorded as `key.nearest_expiry`; the section 6 sentence is shown at most once per 7 days per family.
