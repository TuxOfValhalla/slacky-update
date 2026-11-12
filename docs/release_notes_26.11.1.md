# Slacky-Update v26.11.1 "Touch of Grey"

A hotfix on top of v1.0 LTS "Dark Star". Install it if you use the Hyprland desktop from our curated catalog (`hyprland-noctalia` or `hyprland-core`) and keep Slackware -current up to date. From this release on, version numbers are year.month.release, so you can see how old your version is.

## Why this release

On 12 November 2026 Slackware -current moved `libjxl` from 0.12 to 0.13. Every Hyprland program of our curated suites (Hyprland, hyprlock, hyprpaper, the Noctalia shell, libhyprgraphics) uses the system's `libjxl.so.0.12`, which is gone after that update.

What you may notice:
- The desktop you are logged in to keeps working, because it still has the old library in memory.
- New commands to the shell fail. For example, a keyboard shortcut that opens the Noctalia launcher (`noctalia msg ...`) does nothing.
- The screen lock (`hyprlock`) cannot start.
- **After you log out or restart, Hyprland cannot start, so you have no desktop.**

Check whether you are affected:

```
ldd /usr/bin/Hyprland | grep "not found"
```

Any output means you are affected.

## What this release does

- Both Hyprland suites now bring the Arch build of `libjxl` 0.12 along. The Footprint Guard leaves out every file Slackware owns, so only the versioned 0.12 libraries are added, next to Slackware's 0.13. No Slackware file is touched.
- The update check now finds an installed Hyprland suite whose programs or libraries are missing a library. It lists it as `... needs a repair`, and the next full update rebuilds and reinstalls the same version. You do not have to do anything by hand.

Nothing else changed compared with v1.0 LTS.

## How to install

If you are on the Hyprland desktop: do not log out or restart before step 3.

1. Install the package. It upgrades v1.0 LTS in place:
   ```
   sudo upgradepkg --install-new --reinstall slacky-update-26.11.1-noarch-106_slacky.txz
   ```
2. Run a full update:
   ```
   slacky-update
   ```
   The plan lists `Hyprland Mac-like Desktop Suite 0.57.2 needs a repair` (or the core suite). Answer yes.
3. Check that nothing is missing any more:
   ```
   ldd /usr/bin/Hyprland /usr/bin/hyprlock /usr/bin/noctalia | grep "not found"
   ```
   No output means you are fixed, and it is safe to log out and restart.

If you are already logged out and Hyprland does not start, log in on a text console (Ctrl+Alt+F2) and do the same three steps there.

## Verified

- On the author's machine (Slackware -current, 12 November 2026), the same fix was installed in Norse SlackyUpdate (Rust) and the repaired suite started with no missing libraries.
- The new repair check was tested on that machine (nothing to repair) and on a simulated broken install (the repair was found).
- The legacy build of the repaired suite itself has not been run on that machine, because it had already been repaired with the Rust app.

Product of Norse Software. Author: Tux of Valhalla.
