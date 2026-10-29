<div align="center">

# Slacky-Update
### *System upgrades, CachyOS kernels, NVIDIA drivers, Limine & Secure Boot and curated software for Slackware Linux*
#### `v1.0 LTS` — *"Dark Star"* (Long-Term Support Release)

[![Slackware 15.0 / -current](https://img.shields.io/badge/Slackware-15.0%20%2F%20--current-blue?style=for-the-badge&logo=slackware&logoColor=white)](http://www.slackware.com/)
[![Release](https://img.shields.io/badge/Release-v1.0%20LTS-purple?style=for-the-badge)](https://github.com/TuxOfValhalla/slacky-update/releases)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-green.svg?style=for-the-badge)](LICENSE)
[![Locales: 24](https://img.shields.io/badge/Languages-24-yellow?style=for-the-badge)](locales/)
[![Manual: Survival Guide](https://img.shields.io/badge/Manual-Survival%20Guide-teal?style=for-the-badge)](docs/THE_ULTIMATE_SLACKY_UPDATE_SURVIVAL_GUIDE.md)

</div>

---

## About

Slacky-Update is a terminal tool that keeps a Slackware Linux system up to date from one menu. It handles Slackware packages, Flatpaks, SlackBuilds (SBo), CachyOS kernels, NVIDIA drivers, the Limine boot menu with Secure Boot signatures, and a curated set of software. It shows a plan of what is pending and asks before it changes the system. It runs the existing Slackware tools rather than replacing them.

---

## Screenshots

![Main menu](assets/screenshots/slacky-update-main.png)

*Main menu: pending updates grouped by source, with the nine operations.*

![Full system upgrade](assets/screenshots/slacky-update-upgrade.png)

*Full system upgrade: packages are downloaded in parallel after one confirmation.*

![CachyOS kernel picker](assets/screenshots/slacky-update-kernel-picker.png)

*CachyOS kernel picker: available kernel flavors with the installed ones marked.*

![Health audit](assets/screenshots/slacky-update-doctor.png)

*Health audit (`slacky-update --doctor`): a read-only check of boot, kernel, drivers and base system.*

![Curated software](assets/screenshots/slacky-update-software.png)

*Curated software: tested applications in twelve categories.*

---

## Features

### Main menu

| # | Operation | Description |
| :-: | :--- | :--- |
| 1 | **Full System Upgrade** | Slackware, Flatpaks, SBo, kernel and Secure Boot in one run |
| 2 | **CachyOS Kernel Management** | Upgrade installed CachyOS kernels, pick a flavor (BORE, EEVDF, BMQ, RT, LTS, RC, Zen and others), prune old kernels, rebuild the initramfs |
| 3 | **NVIDIA Driver Management** | CachyOS NVIDIA suite (64-bit and 32-bit multilib, all kernels), DKMS rebuild and signing, legacy `.run` branches (595, 570, 535, 470, 390) |
| 4 | **CachyOS Gaming Software** | The curated software catalog |
| 5 | **System Maintenance** | Shows how much space can be freed, then cleans caches, old kernels and unused Flatpak runtimes. `/home` is not touched |
| 6 | **Limine Bootloader & Secure Boot Matrix** | Limine installation beside GRUB/ELILO, BLAKE2B hash enrollment and checks, kernel command line, Snapper rollback, self-heal from backup |
| 7 | **Secure Boot MOK Configuration** | Secure Boot audit, sbctl key-enrollment wizard, signing of bootloaders and kernels, classic MOK for kernel modules |
| 8 | **Master Field Guide & Diagnostics** | Health audit and report, guides in the terminal, PDF export, email and Wi-Fi QR transfer to a phone |
| 9 | **Exit** | Leaves the program |

On AMD systems, line 3 is **AMD ROCm** instead of the NVIDIA suite. `ESC` works as "back" in every menu.

Operations can also be started from the command line. Run `slacky-update --help` for the full list, for example `slacky-update --check` (read-only status), `--doctor` (health audit) or `-y` (unattended full upgrade).

### Curated software

Menu 4 opens **Slacky Curated Software**, with tested applications in twelve categories, such as Hyprland desktops, gaming HUDs, game launchers, hardware tuning, OBS Studio with plugins, voice chat, creative tools and Secure Boot utilities. Select items with `TAB` or the mouse, then press `Enter`.

### Underpants Gnomes

Applications that Slackware does not ship are built by the **Underpants Gnomes** engine. It takes Arch Linux and CachyOS packages and turns them into native Slackware `.txz` packages, installed under `/opt/underpants/`. The host never has `pacman` installed or run. The engine is also a command: see `gnomes --help` for search, install, dependency and rollback options.

### Safety

* **Confirmation first.** Larger operations show a plain summary and wait for a yes.
* **Protected steps.** `Ctrl+C`, closing the terminal and similar signals are held back until the current package or kernel step has finished. A power cut can still interrupt a step.
* **Integrity checks.** Kernels, initramfs images and `limine.conf` are verified with BLAKE2B hashes and Secure Boot signatures. A last known good Limine setup is kept as a self-heal backup.
* **Snapshots.** With Snapper, an earlier state can be restored from the boot menu on Btrfs systems.
* **Existing bootloaders stay.** GRUB and ELILO are left alone and remain available as a fallback.
* **SpiderSense.** A read-only watcher (`spidersense status`) reports damaged packages, mirror problems and hardware changes. Repairs are left to Slacky-Update.
* **Tray applet.** `slacky-update-tray` shows when updates are waiting on KDE Plasma, XFCE and Hyprland.

---

## Installation

> Slacky-Update changes kernels, drivers and boot files. Read [Use at your own risk](#license-and-disclaimer) before installing.

**Requirements:** Slackware 15.0 or Slackware -current, `x86_64`, `git`, internet access and `sudo`.

Slacky-Update is built as a native Slackware package. The build writes it to `../slacky-updates_releases/`, next to the repository.

**Step by step:**
```bash
# 1. Get the source
git clone https://github.com/TuxOfValhalla/slacky-update.git
cd slacky-update

# 2. Build the Slackware package
bash slackbuild/slacky-update.SlackBuild

# 3. Install or upgrade it
sudo upgradepkg --reinstall --install-new "$(ls -t ../slacky-updates_releases/slacky-update-[0-9]*.txz | head -n 1)"

# 4. Start it
slacky-update
```

**Shortcut (build, install and start in one line):**

*From GitHub:*
```bash
git clone https://github.com/TuxOfValhalla/slacky-update.git && cd slacky-update && bash slackbuild/slacky-update.SlackBuild && sudo upgradepkg --reinstall --install-new "$(ls -t ../slacky-updates_releases/slacky-update-[0-9]*.txz | head -n 1)" && slacky-update
```

*From Codeberg:*
```bash
git clone https://codeberg.org/TuxOfValhalla/slacky-update.git && cd slacky-update && bash slackbuild/slacky-update.SlackBuild && sudo upgradepkg --reinstall --install-new "$(ls -t ../slacky-updates_releases/slacky-update-[0-9]*.txz | head -n 1)" && slacky-update
```

Menu lines can be chosen with the mouse, with the arrow keys and `Enter`, or by typing the number. To copy text from the terminal, hold `Shift` while you drag with the mouse.

---

## Languages

Slacky-Update ships with 24 languages. It selects one from `$LANG` or `$LC_MESSAGES`. Use `slacky-update --lang <code>` to change it, and `slacky-update --list-langs` to list them.

English (`en`, default), Norsk bokmål (`nb`), Norsk nynorsk (`nn`), Deutsch (`de`), Français (`fr`), Español (`es`), Italiano (`it`), Português (`pt`), Nederlands (`nl`), Dansk (`da`), Svenska (`sv`), Suomi (`fi`), Íslenska (`is`), Polski (`pl`), Русский (`ru`), 简体中文 (`zh`), 日本語 (`ja`), 한국어 (`ko`), हिन्दी (`hi`), العربية (`ar`), English Canada (`en-ca`), Davvisámegiella (`se`), Radical English (`en-radical`), Radical Norwegian (`nb-radical`).

English and Norwegian Bokmål are maintained by the author. The other translations are machine-assisted. Corrections from native speakers are welcome.

---

## Documentation

The guides are installed to `/usr/share/slacky-update/docs/`. They can be read from menu 8 or exported to PDF there.

* [The Ultimate Slacky-Update Survival Guide](docs/THE_ULTIMATE_SLACKY_UPDATE_SURVIVAL_GUIDE.md): operator manual and quick reference.
* [Slacky-Update Field Guide](docs/SLACKY_UPDATE_FIELD_GUIDE.md): everyday use, menu by menu.
* [Limine & Secure Boot Field Guide](docs/LIMINE_SECUREBOOT_FIELD_GUIDE.md): Limine, BLAKE2B, MOK and sbctl keys, and snapshot recovery.
* [Underpants Gnomes Field Guide](docs/UNDERPANTS_GNOMES_FIELD_GUIDE.md): the curated software and the `gnomes` command.
* [Troubleshooting Guide](docs/TROUBLESHOOTING_GUIDE.md): what to do when something goes wrong.
* [Technical Companion Guide](docs/TECHNICAL_COMPANION_GUIDE.md): architecture, modules and safety mechanisms.
* [Oh My Hyprland Guide](docs/OH_MY_HYPRLAND_GUIDE.md): the Hyprland desktop suite.

---

## License and disclaimer

### License

Slacky-Update is released under the GNU General Public License version 3 (GPLv3). See [LICENSE](LICENSE).

### Use at your own risk

Slacky-Update changes core parts of the system: kernels, graphics drivers, initramfs images and the UEFI boot setup. It includes safety checks, signal guards and rollback paths. All installations and system changes are nevertheless made at your own risk. The authors and contributors give no warranty and accept no liability for data loss, hardware problems or a system that does not start. Back up personal data before major upgrades.

### AI pair programming

Slacky-Update was developed with AI pair-programming tools, in collaboration with a human Linux systems architect who planned, reviewed and tested every change.

### Trademarks and non-affiliation

Slacky-Update is an independent community open-source project. It is not an official Slackware product and is not endorsed, sponsored, affiliated with or maintained by Patrick Volkerding or the Slackware project. The name "Slackware" is used under nominative fair use, only to identify the operating system this tool is made for.
