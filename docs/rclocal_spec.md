# rc.local block spec (shared by slacky-update and slacky-update-rs; spec only, never shared code)

Source: Claude subagent design + temp-dir tests, 2026-10-12. Status: implemented in legacy (6A-6c): the helpers are printed into
each curated package's doinst.sh / douninst.sh by `slacky_rc_helpers` in `lib/mod_gaming.sh`; gnomes service packages keep
their own marker format with the upgrade guard (`lib/gnomes_pacman.py`). Section 1 describes the state before that change.

# rc.local / rc.local_shutdown block recipe (read-only design, tested in mktemp dir)

Code:  `lib/mod_gaming.sh` (`slacky_rc_helpers`: su_rc_add / su_rc_remove / su_rc_migrate + helpers; POSIX sh). The
       design-time copy (rclocal_funcs.sh) and its test script (rclocal_test.sh) were temporary and are not kept.

## 1. Current state
FACT mod_gaming.sh doinst (L6320-6470), per daemon, appended with `cat << 'RC_EOF' >>`, guarded by `grep -q "rc.NAME" file`:
    <blank>
    # Start Ananicy C++ auto-nice daemon:          (shutdown: "# Stop ...:")
    if [ -x /etc/rc.d/rc.ananicy-cpp ]; then
      /etc/rc.d/rc.ananicy-cpp start               (shutdown: stop)
    fi
  Descriptions: "Ananicy C++ auto-nice daemon", "LACT GPU control daemon", "Sched-EXT gaming scheduler",
  "CoolerControl daemon", "ASUS control daemon", "Syncthing service", "dmemcg-booster VRAM daemon".
  Each block is a self-contained 3-line if/fi, no else/elif. No marker, no removal. mod_gaming.sh ships NO
  install/douninst.sh (grep "douninst" there: no hits). Only gnomes ships one.
FACT gnomes doinst (gnomes_pacman.py L3978-4007) appends
    # --- [ gnomes-service: SVC ] ---  /  if [ -x /etc/rc.d/rc.SVC ]; then ... fi  /  # --- [ /gnomes-service: SVC ] ---
  also self-contained. douninst (L4015-4033) = `rc.SVC stop` + `sed -i '/begin/,/end/d' rc.local rc.local_shutdown`.
  purge_gnomes_service_hooks (L4500-4516): python re.sub non-greedy begin..end, plain open(...,"w").
FACT owner's machine (read-only; both files pass `sh -n`, root:root 755):
  rc.local (147 lines): lines 1-52 are hand-written/unmarked (postboot, THP, nscd, LACT, scx, CoolerControl,
  Ananicy, Syncthing, dmemcg-booster), then ~65 blank lines, then 5 gnomes-service blocks (ibacm, iwpmd, rdma-ndd,
  cxl-monitor, ndctl-monitor), file ends with newline. rc.local_shutdown (133 lines): 7 unmarked stop blocks
  ("# Stop LACT daemon cleanly", no trailing colon), blank run, same 5 gnomes blocks with "stop".
  The unmarked blocks do NOT match mod_gaming's exact text (different comments, 4-space indent) and the Ananicy start
  block has an `elif [ -x /usr/bin/ananicy-cpp ]; then ... fi` chain: this one is user/hand-edited. Removing it by
  grep/line range would cut an if/elif/fi in the middle. The gnomes and mod_gaming blocks themselves are self-contained.
  There is no mod_gaming-format block on this machine, so migration has nothing to convert here (tested on fixture).
  The ~65/~70 blank lines are residue of earlier line-deletions (INFERENCE).

## Judgement of the gnomes "zero residual syntax errors" approach
FACT (code) / INFERENCE (not executed on real pkgtools):
 a) douninst sed range: if the END marker is missing, sed deletes from BEGIN to EOF (loses user lines below). No
    balance check, no `sh -n`, no backup, `|| true` hides errors. Claim is not backed by any validation.
 b) python purge: non-atomic truncate-write (power loss = empty rc.local), errors swallowed by `except: pass`, no
    syntax check. Regex is safe against a missing END (no match) but not validated either.
 c) UPGRADE BUG (see 3): douninst runs after the new doinst, so every upgrade of a gnomes service package deletes the
    block the new doinst just skipped re-adding. Services then silently stop starting at boot.
 d) Dedupe by `grep -q` of the full marker is fine; marker text with `[` `]` is fine but exotic. Verdict: format
    (marker pair, self-contained block) is good and kept in spirit; the removal code must be replaced.

## 3. pkgtools facts (read from /sbin/removepkg, /sbin/upgradepkg, /sbin/installpkg on this machine)
FACT installpkg L788-791: if package has install/douninst.sh it is copied to /var/lib/pkgtools/douninst.sh/<fullpkgname>
  and listed in the package log. (Currently only 3 files there; only underpants-claude-desktop is ours.)
FACT removepkg L384-389: uninstall script copied to $TMP unless --skip-douninst; L426-436 files are deleted first
  (files also owned by another installed package are kept, `keep_files`); L459-464 the script is run with
  `( cd $ROOT/ ; sh $TMP/$PKGNAME )` AFTER the files are gone and the package log has been moved away. Plain `sh`,
  cwd = /, no arguments, no environment hint about upgrade.
FACT upgradepkg L343-356, L448-455: old logs renamed `*-upgraded-TIMESTAMP`, NEW package installed first (its doinst
  runs), THEN `removepkg <old>-upgraded-TS`, which runs the OLD package's douninst (looked up via the stripped name).
  With `--reinstall` of the same version the stripped name equals the new package's name, so the same script runs.
Consequence: douninst cannot tell upgrade from removal by arguments. Reliable discriminator (FACT order, INFERENCE it
  holds for every case): in a real removal the daemon script /etc/rc.d/rc.NAME was just deleted by removepkg; in an
  upgrade the new package owns it, so it still exists (keep_files). Rule: remove the block only if
  /etc/rc.d/rc.NAME does NOT exist. Also correct for the owner's manual `rm`. Fallback: removepkg --skip-douninst
  leaves blocks (harmless: guarded by `[ -x ]`, so a dangling block is a no-op, never an error).
  Safety property worth stating: even if a removal is missed, the `if [ -x ... ]` guard makes the leftover inert.

## 2. Recipe (implemented in `lib/mod_gaming.sh`, `slacky_rc_helpers`)
Marker pair, column 0, one name per block:
    # >>> slacky-update:NAME >>>
    <self-contained shell: complete if/fi, no unclosed quote/heredoc>
    # <<< slacky-update:NAME <<<
Add (su_rc_add FILE NAME < body), all steps must pass or the file stays untouched (rc 1, message on stderr):
  1. file exists; markers across the whole file balanced (strict begin/end pairs, same name, no nesting);
  2. `sh -n FILE` clean with EMPTY stderr (bash only warns on an unterminated here-doc but exits 0, so stderr counts);
  3. already has block NAME -> no-op (idempotent). Unmarked non-comment line containing rc.NAME -> leave alone and log
     (keeps the old grep guard, so the owner's hand-written blocks are never duplicated);
  4. refuse CRLF files (appending LF lines would mix endings) and files whose last real command is `exit`
     (an appended block would be unreachable);
  5. body itself passes `sh -n`; append at END only: add a newline if missing, one blank line, then the block;
  6. temp file in same dir (`mktemp FILE.slacky.XXXXXX`), `cp -p` first (mode/owner/times), write content into it,
     re-check markers + `sh -n` on the result, `cp -p FILE FILE.slacky-bak` (rolling backup), `mv -f` (atomic rename).
     Symlinked FILE is resolved with readlink -f.
Appending after a file that passed `sh -n` cannot land inside the user's open if/case, because such a file would not
  parse (checked: unclosed `if` and unterminated heredoc fixtures are refused).
Remove (su_rc_remove FILE NAME): no block -> no-op without touching the file or backup. Else same pre-checks (markers
  balanced, `sh -n` ok), awk drops every NAME block (duplicates too; CRLF-tolerant marker match) plus ONE blank line
  directly before the begin marker (the one add emitted), temp + post-check (balanced, `sh -n`, block gone), backup, mv.
  Orphan marker or syntax error anywhere in the file = refuse, log, leave unchanged (never `sed A,B d` to EOF).
Migrate (su_rc_migrate FILE NAME start|stop "DESC"): matches only the exact 4 mod_gaming lines (comment, if, call, fi;
  CR-tolerant) and replaces them IN PLACE with the marked block (start order preserved). No exact match = no change
  (owner's hand-edited blocks untouched, tested against a copy of the real rc.local). Run it from the new doinst for
  every daemon before su_rc_add; the add-step's "unmarked rc.NAME present" rule then prevents duplicates.
Known limits: (a) if a user keeps a blank line right before our begin marker it is removed with the block (whitespace
  only); (b) a non-newline-terminated last user line gains a newline on first add; (c) no flock: two pkgtools runs at
  the same moment could race (installpkg already serialises doinst with INSTLOCKDIR in most paths; INFERENCE);
  (d) a user-written `exit` in the MIDDLE at top level makes later blocks unreachable, undetectable by syntax.

## 3b. Where to run it
- doinst.sh: replace the cat>> blocks by su_rc_migrate + su_rc_add for rc.local (start) and rc.local_shutdown (stop).
  The functions must be pasted into doinst.sh and douninst.sh (package-local, no dependence on the Rust or legacy tool).
- install/douninst.sh (must be shipped; pkgtools copies it, plain sh, cwd /). Skeleton per daemon:
    #!/bin/sh
    for n in lact scx ...; do
      [ -e /etc/rc.d/rc.$n ] && continue        # upgrade: new package still owns the script, keep the block
      [ -x /etc/rc.d/rc.$n ] && /etc/rc.d/rc.$n stop 2>/dev/null   # (unreachable after removal; stop belongs to prerm)
      su_rc_remove /etc/rc.d/rc.local $n; su_rc_remove /etc/rc.d/rc.local_shutdown $n
    done
  Stopping the daemon: the script is already deleted when douninst runs, so a stop here is impossible. Stop must be
  done by the updater before removepkg (or accept: daemon runs until reboot). INFERENCE: gnomes douninst's stop call
  is dead code for the same reason.
- Rust/legacy `remove` command: call the same logic when removing a package outside pkgtools hooks (purge-service
  equivalent) - Rust implementation should port awk logic 1:1 and keep the same marker spec in docs/runtime_spec style
  shared-format file (format spec only, no shared code).
- Existing gnomes blocks keep the old marker format; support both forms in remove for gnomes packages (their old
  douninst stays in the pkg db until they are rebuilt) and fix their douninst with the upgrade guard + balanced removal.

## 4. Test results (rclocal_test.sh, run with sh from env -u LD_LIBRARY_PATH; FACT, executed)
- F1 user if/elif/else/fi + case file: add, add again (1 block), second block, user block inserted between ours,
  remove each: `sh -n` ok after every step; outside the blocks identical to input (diff showed only the test-inserted
  user block). F1b pure add+remove: byte-identical to the original (cmp).
- F2 CRLF user file: add refused, file byte-identical. F3 no trailing newline: add/remove ok, `sh -n` ok (file gains
  its final \n). F4 duplicate blocks: remove deletes both, `sh -n` ok.
- F5 stray begin / stray end / nested begin: add and remove refuse, file byte-identical.
- F6 syntax-broken file, unterminated here-doc, trailing `exit`: all refused unchanged.
- F7 copy of the owner's real rc.local: add lact -> left alone (hand-written block present), unchanged.
- F8 mode 750 preserved, .slacky-bak created. F9 exact legacy block migrated in place, `sh -n` ok, remove ok.
  F10 owner's elif-variant Ananicy block: migrate leaves the file untouched.
- Not tested: real pkgtools run (needs root/sudo), concurrent runs, SELinux/ACL (none on Slackware).

## Reference implementation (POSIX sh, from the design test)

```sh
# --- slacky rc.local block helpers (POSIX sh) ---------------------------------
# Return 0 = ok/no-op/changed, 1 = refused (file left byte-identical).
su_rc_log() { echo "slacky-update: rc.local: $*" >&2; }

# Syntax check; any stderr output (e.g. unterminated here-doc warning) counts as failure.
su_rc_syntax_ok() { [ -z "$(sh -n "$1" 2>&1)" ]; }

# All markers (any name) must be strictly begin/end pairs, never nested.
su_rc_markers_ok() {
  awk '
    { l=$0; sub(/\r$/,"",l) }
    l ~ /^# >>> slacky-update:[A-Za-z0-9._+-]+ >>>$/ {
      n=l; sub(/^# >>> slacky-update:/,"",n); sub(/ >>>$/,"",n)
      if (open != "") bad=1; open=n; next }
    l ~ /^# <<< slacky-update:[A-Za-z0-9._+-]+ <<<$/ {
      n=l; sub(/^# <<< slacky-update:/,"",n); sub(/ <<<$/,"",n)
      if (open == "" || open != n) bad=1; open=""; next }
    /slacky-update:[A-Za-z0-9._+-]+ (>>>|<<<)/ { odd=1 }
    END { exit (bad || open != "") }' "$1"
}

su_rc_has_block() { awk -v b="# >>> slacky-update:$2 >>>" '{ l=$0; sub(/\r$/,"",l) } l==b { f=1 } END { exit !f }' "$1"; }

# Commit tmp over file atomically, keeping a rolling backup.
su_rc__commit() { # file tmp
  cp -p "$1" "$1.slacky-bak" && mv -f "$2" "$1"
}

# su_rc_add FILE NAME < body   (body = complete, self-contained shell commands)
su_rc_add() {
  f=$(readlink -f "$1") || return 1; name=$2
  body=$(cat)
  [ -f "$f" ] || { su_rc_log "$f missing, skipped"; return 1; }
  su_rc_markers_ok "$f" || { su_rc_log "unbalanced markers in $f, refused"; return 1; }
  su_rc_syntax_ok "$f"  || { su_rc_log "$f has a syntax error already, refused"; return 1; }
  su_rc_has_block "$f" "$name" && return 0
  if tr -d '\n' <"$f" | grep -q "$(printf '\r')"; then su_rc_log "$f has CRLF line endings, refused"; return 1; fi
  if grep -v '^[[:space:]]*#' "$f" | grep -q "rc\.$name"; then
    su_rc_log "$f already starts/stops $name by hand, left alone"; return 0
  fi
  printf '%s\n' "$body" | { t=$(mktemp) && cat >"$t" && su_rc_syntax_ok "$t"; rc=$?; rm -f "$t"; exit $rc; } \
    || { su_rc_log "block body for $name is not valid shell, refused"; return 1; }
  # a trailing top-level "exit" would make an appended block unreachable
  if tr -d '\r' <"$f" | grep -v '^[[:space:]]*\(#.*\)\{0,1\}$' | tail -n 1 | grep -q '^[[:space:]]*exit\([[:space:]]\|$\)'; then
    su_rc_log "$f ends with exit, refused"; return 1; fi
  tmp=$(mktemp "$f.slacky.XXXXXX") || return 1
  cp -p "$f" "$tmp" || { rm -f "$tmp"; return 1; }
  { cat "$f"
    [ -n "$(tail -c 1 "$f")" ] && printf '\n'
    printf '\n# >>> slacky-update:%s >>>\n%s\n# <<< slacky-update:%s <<<\n' "$name" "$body" "$name"
  } >"$tmp"
  if su_rc_markers_ok "$tmp" && su_rc_syntax_ok "$tmp"; then su_rc__commit "$f" "$tmp"
  else rm -f "$tmp"; su_rc_log "result would be invalid, $f unchanged"; return 1; fi
}

# su_rc_remove FILE NAME   (removes every block of NAME + one blank line we added before it)
su_rc_remove() {
  f=$(readlink -f "$1") || return 1; name=$2
  [ -f "$f" ] || return 0
  su_rc_has_block "$f" "$name" || return 0
  su_rc_markers_ok "$f" || { su_rc_log "unbalanced markers in $f, refused"; return 1; }
  su_rc_syntax_ok "$f"  || { su_rc_log "$f has a syntax error already, refused"; return 1; }
  tmp=$(mktemp "$f.slacky.XXXXXX") || return 1
  cp -p "$f" "$tmp" || { rm -f "$tmp"; return 1; }
  awk -v b="# >>> slacky-update:$name >>>" -v e="# <<< slacky-update:$name <<<" '
    { l=$0; sub(/\r$/,"",l) }
    skip { if (l == e) skip=0; next }
    l == b { hold=0; skip=1; next }
    { if (hold) print held; hold=0
      if (l == "") { held=$0; hold=1; next }
      print }
    END { if (hold) print held }' "$f" >"$tmp"
  if su_rc_markers_ok "$tmp" && su_rc_syntax_ok "$tmp" && ! su_rc_has_block "$tmp" "$name"; then
    su_rc__commit "$f" "$tmp"
  else rm -f "$tmp"; su_rc_log "result would be invalid, $f unchanged"; return 1; fi
}

# su_rc_migrate FILE NAME VERB DESC   - replace the exact old 4-line unmarked block with a marked one
su_rc_migrate() {
  f=$(readlink -f "$1") || return 1; name=$2; verb=$3; desc=$4
  [ -f "$f" ] || return 0
  su_rc_markers_ok "$f" && su_rc_syntax_ok "$f" || { su_rc_log "$f not clean, migration refused"; return 1; }
  su_rc_has_block "$f" "$name" && return 0
  tmp=$(mktemp "$f.slacky.XXXXXX") || return 1
  cp -p "$f" "$tmp"
  awk -v c="# $(printf %s "$verb" | sed 's/^./\U&/') $desc:" -v n="$name" -v v="$verb" '
    { L[NR]=$0; sub(/\r$/,"",L[NR]); R[NR]=$0 }
    END { i=1
      while (i<=NR) {
        if (L[i]==c && L[i+1]=="if [ -x /etc/rc.d/rc." n " ]; then" && L[i+2]=="  /etc/rc.d/rc." n " " v \
            && L[i+3]=="fi") { found=1; i+=4
          print "# >>> slacky-update:" n " >>>"; print "if [ -x /etc/rc.d/rc." n " ]; then"
          print "  /etc/rc.d/rc." n " " v; print "fi"; print "# <<< slacky-update:" n " <<<"; continue }
        print R[i]; i++ }
      exit found?0:3 }' "$f" >"$tmp"
  rc=$?
  if [ $rc -ne 0 ]; then rm -f "$tmp"; return 0; fi   # nothing exact found: leave alone
  if su_rc_markers_ok "$tmp" && su_rc_syntax_ok "$tmp"; then su_rc__commit "$f" "$tmp"
  else rm -f "$tmp"; su_rc_log "migration result invalid, $f unchanged"; return 1; fi
}
```
