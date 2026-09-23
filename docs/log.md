# 📝 Slacky-Update Development Log

Dette dokumentet sporer patch-utvikling, arkitekturforbedringer, feilrettinger og endringer på vei mot Slacky-Update LTS.

---

## 🚀 [v0.16.0] — 2026-09-23 ("Tubthumping" — LTS Prep & Flimmerfri Pacman ILoveCandy Engine)

### 🎯 Hovedmål for v0.16.0
Oppnå 100 % konsistens og fjellstø stabilitet for LTS. Eliminere terminalflimmer og skjermriving ved multi-linje nedlasting, innføre en felles flimmerfri Pacman ILoveCandy-motor for alle moduler, herde maskinvaregjenkjenning (GPU/DKMS/Bootloader) inkludert non-interactive batch-modus (`-y`), sikre alle nettverksoppslag med eksplisitte tidsavbrudd, og fullføre opprydding av midlertidige filer.

### 🛠️ Endringer og forbedringer

#### 1. Kuratert Hyprland Desktop Suite via Underpants Gnomes (`lib/mod_gaming.sh`, `lib/gnomes_pacman.py`, `bin/slacky-update`)
* **Hensikt:** Gi Slackware-brukere en moderne, ferdigkonfigurert og maskinvare-tilpasset Wayland/Hyprland-opplevelse transmutert direkte fra CachyOS til genuine `.txz`-pakker.
* **Valg 1 (`hyprland-noctalia`):** Fullverdig Mac-like skrivebordsopplevelse drevet av **Noctalia Shell** (topplinje, bunndock, spotlight-launcher, notifikasjoner og kontrollsenter).
* **Valg 2 (`hyprland-core`):** Ren minimalistisk Hyprland-kompositor for power-users som bygger egne dotfiles.
* **Biblioteks-bundling & Host Sovereignty Shield:**
  * Bunder automatisk nødvendige delte biblioteker (`hyprwire`, `hyprtoolkit`, `sdbus-cpp`, `tomlplusplus`, `muparser`, `re2`, `md4c`, `liblua.so.5.5`, `libical.so.4.0`) slik at samtlige verktøy i suiten starter 100 % feilfritt.
  * Beskytter Slackware base-systemet: fjerner binærkollisjoner (`/usr/bin/lua`), uversjonerte generiske utviklingssymlenker og headers som tilhører vertssystemets egne pakker.
* **Hardware- og sesjonsintegrasjon:**
  * Autogenererer `/etc/hypr/hyprland.env` med optimale GPU-driverflagg (NVIDIA direct backend & hardware cursor bypass, AMD radeonsi, Intel iHD).
  * Oppretter SDDM-oppføring `/usr/share/wayland-sessions/hyprland.desktop` og sesjons-wrapper `/usr/bin/start-hyprland` (D-Bus + elogind).
  * Etablerer standardkonfigurasjon med global hurtigtast `SUPER + U` for å starte `slacky-update`, autostart av portaler, og Slacky pinned i docken.
  * Lagt til CLI-snarveier `--hyprland` / `--hyprland-noctalia` og `--hyprland-core`.

#### 2. Felles flimmerfri Pacman ILoveCandy-motor (`lib/pacman_candy.py`)
* **Problem:** `gnomes_pacman.py` og `common.sh` hadde separate renderers med ulik animasjonshastighet og pellet-mønster (`i % 3 == 1` vs `i % 2 == 0`). Tråder som slettet og skrev ferdiglinjer underveis i `gnomes_pacman.py` forårsaket synlig flimmer og hoppende tekst i terminalen.
* **Løsning:** 
  * Opprettet kanonisk fellesmodul `lib/pacman_candy.py` som deles 100 % likt av `gnomes_pacman.py` og `common.sh`.
  * Ekte Pacman ILoveCandy-paritet: `i % 2 == 0` pellets (`o o o o`), rolig munntoggling (~1.4 toggles/sek) med asynkron faseforskyvning per worker.
  * Flimmer-eliminering: Terminalcursor skjules under rendering (`\033[?25l`) og gjenopprettes automatisk (`\033[?25h`) ved avslutning/signal. Oppdateringsfrekvensen er låst til 140 ms, og all rendering gjøres via en atomisk buffer.

#### 2. Universal GPU-deteksjon og Sysfs Fallback (`lib/common.sh` & `bin/slacky-update`)
* **Problem:** I unattended/batch-modus (`slacky-update -y`) ble ikke `probe_gpu_hardware` kalt før `run_full_update`, slik at `HAS_NVIDIA` forble `false` og førte til at nødvendige NVIDIA-oppgraderinger ble hoppet over.
* **Løsning:**
  * Lagt inn global oppstartskjøring av `probe_gpu_hardware` i `bin/slacky-update`.
  * Utvidet `probe_gpu_hardware` med en robust sysfs-fallback via `/sys/bus/pci/devices/*/vendor` og `/sys/class/drm` som fungerer selv om `lspci` mangler.

#### 3. Innebygd BLAKE2B Hash-motor for Limine (`lib/mod_limine.sh`)
* **Problem:** Hash-sjekk mot `limine.conf` var avhengig av ekstern `b2sum`-binærfil via subprosesser.
* **Løsning:**
  * Integrert direkte Python `hashlib.blake2b` beregning med fallback til `b2sum`. Dette er raskere, mer pålitelig og uavhengig av eksterne verktøy.

#### 4. Aktivitetsovervåking av nedlastinger & systemopprydding (`lib/common.sh`, `lib/mod_clean.sh`)
* **Problem:** En hard 300-sekunders grense (`-m 300`) i `download_parallel_pacman` kunne avbryte store pakker (f.eks. CUDA, Unreal Engine eller store kjerner) ved treg internettforbindelse selv om data aktivt ble overført.
* **Løsning:**
  * Erstattet rigid 300s timeout med aktivitetsovervåking: `--connect-timeout 15 -m 1800 --speed-time 45 --speed-limit 1000`. Pakker kan nå laste ned uavbrutt så lenge linjen overfører data, mens frosne forbindelser fanges opp og prøves på nytt etter 45 sekunder under 1 KB/s.
  * Satt eksplisitte `--connect-timeout` og `-m` grenser på alle eksterne metadata `curl`-kall.
  * Utvidet `clean_system_cache_and_orphans` til å rydde opp gamle snapshot-filer, låsfiler, dracut-midlertidige filer og skallpakker.

#### 5. i18n & 90-talls glød
* Full 100 % synkronisering over samtlige 24 språkpakkefiler i `locales/` med 90-talls referanser ("Tubthumping", "Bodacious", "Major Bummer", "Cowabunga", "Excellent").

#### 6. PipeWire AT_SECURE Fix & Hyprland / Noctalia Desktop Suite (`lib/mod_gaming.sh`)
* **Problem:** PipeWire og WirePlumber feilet under Wayland-oppstart med DBus-feil fordi Linux capabilities (`setcap`) førte til at kjernen kjørte prosessene med `AT_SECURE=1`, som strippet miljøvariabler som `DBUS_SESSION_BUS_ADDRESS`.
* **Løsning:**
  * Lagt inn automatisk fjerning av motstridende capabilities (`setcap -r /usr/bin/wireplumber` og `setcap -r /usr/bin/pipewire`) under sesjonsoppsett.
  * Autogenerering av standardkonfigurasjon for Hyprland med universell skjermdeteksjon (`monitor = , preferred, auto, 1`), raske og responsive animasjoner (200–250 ms), OLED-innbrenningsvern (`vrr = 2`), samt egne spillregler (`immediate on`, `xwayland { force_zero_scaling = true }`).
  * Integrert Slacky-Update tray-ikon (`slacky-update-tray`) som standard i Noctalia statuslinje.

#### 7. Automatisk Systray-integrasjon for OpenRGB og EasyEffects (`lib/mod_gaming.sh`)
* **OpenRGB:** Starter minimert i systrayen (`--startminimized`) med fallback til standardprofil eller dedikert brukerprofil (`--profile slackware1`).
* **EasyEffects:** Automatisk generering og oppdatering av `~/.config/easyeffects/db/easyeffectsrc` og `/etc/skel` med `showTrayIcon=true` og `noWindowAfterStarting=true`, slik at EasyEffects alltid dukker opp med interaktivt StatusNotifierItem i systrayen ved innlogging.

#### 8. Automatisk NVIDIA & Wayland maskinvareakselerasjon for nettlesere (`lib/mod_gaming.sh`)
* **Hensikt:** Sikre best mulig ytelse og null tearing for brukere som installerer Google Chrome, Brave eller Microsoft Edge på maskiner med NVIDIA-skjermkort.
* **Løsning:**
  * Under installasjon via Underpants Gnomes kalles `probe_gpu_hardware`.
  * Dersom NVIDIA detekteres, skrives de optimale flaggene automatisk inn i brukerens hjemmemappe og `/etc/skel/.config/` (`chrome-flags.conf`, `brave-flags.conf`, `edge-flags.conf`, `microsoft-edge-stable-flags.conf`):
    `--ozone-platform-hint=auto`
    `--ozone-platform=wayland`
    `--enable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL,VaapiOnNvidiaGPUs`
    `--enable-gpu-rasterization`
    `--enable-zero-copy`
    `--ignore-gpu-blocklist`

#### 9. SlackBuild Oppgradering
* Bygget oppgradert til `0.16.0-noarch-6_slacky` i `slackbuild/slacky-update.SlackBuild`.

---

## 🚀 [v0.15.1] — 2026-09-23 (Patch Staging)

### 🎯 Hovedmål for denne patchen
Rette opp unødvendige DKMS-kjøringer for rene brukerprogrammer, dempe støy fra DKMS-kompilering, sikre lynrask og pålitelig pakkeoppdagelse for Arch Extra-speil (spesielt Discord), og rydde opp i gamle SBo-wrapperpakker.

### 🛠️ Endringer og forbedringer

#### 1. DKMS Guard i Underpants Gnomes (`lib/mod_gaming.sh`)
* **Problem:** Under transmutering av enhver pakke (Discord, Google Chrome, Steam, osv.) ble det lagt til en felles DKMS-blokk i `doinst.sh`. Dette førte til at Slackwares `installpkg` tvang en full DKMS-gjennomgang over samtlige installerte kjerner ved installasjon av vanlige brukerprogrammer.
* **Løsning:** 
  * `doinst.sh`-genereringen sjekker nå eksplisitt om pakken faktisk leverer kernel-drivere (`/usr/src/*/dkms.conf`, `zenpower3`, `v4l2loopback`, `rtl8821cu`, `rtl88x2bu`, `rtl8812au`, `broadcom-wl`, `r8125`).
  * For rene brukerprogrammer (Discord, Chrome, OBS, Spotify, osv.) utelates DKMS-blokken fullstendig.
  * For faktiske driverpakker sjekkes `dkms status` før bygging, og output omdirigeres (`>/dev/null 2>&1`) for å eliminere støy i terminalen.

#### 2. Muffling og ren statusrapportering for DKMS (`lib/mod_kernel.sh` & `lib/mod_nvidia.sh`)
* **Problem:** `dkms build` og `dkms install` sender standard bygge- og signeringslogger til `stdout`. Slackware fanger ikke opp dette, noe som førte til massive tekst-dumps og irrelevante feilmeldinger (f.eks. på ukompatible RC-kjerner).
* **Løsning:**
  * Omdirigert stdout og stderr (`>/dev/null 2>&1`) under `build_dkms_modules_for_all_kernels` og `build_nvidia_modules`.
  * Slacky-Update viser nå kun ryddige og konsise statuslinjer for moduler som faktisk kompileres eller oppdateres.

#### 3. Lynrask Arch Linux JSON API-integrasjon (`lib/mod_gaming.sh`)
* **Problem:** Ved oppstart forsøkte bakgrunnssjekken (`check_all_installed_gaming_updates_fast`) å laste ned den fullstendige HTML-indeksen for Arch Extra på 4,43 MB med 5 sekunders timeout. Hvis nettverket var opptatt, feilet sjekken og Discord ble ikke vist i tilgjengelige oppdateringer ved oppstart.
* **Løsning:**
  * Integrert direkte oppslag mot Arch Linux offisielle JSON API (`https://archlinux.org/packages/<repo>/x86_64/<pkg>/json/`) som henter nøyaktig versjon på 50 ms (~1 KB payload).
  * Økt fallback HTML-timeout til 10 sekunder for feiltoleranse.

#### 4. Utvidet pakkeopprydding for SBo-wrappers (`lib/mod_gaming.sh`)
* **Problem:** Gamle SBo-skallpakker som `google-chrome-the-latest` eller `google-chrome-stable_current` ble liggende igjen når native `underpants-google-chrome` ble installert.
* **Løsning:**
  * Utvidet mønstersøket i `cleanup_foreign_gaming_pkgs` til å fange opp og avinstallere `google-chrome-the-latest-*`, `google-chrome-stable_*`, `discord-canary-*`, `discord-ptb-*` osv.

#### 5. Versjonsbump til `0.15.1`
* Oppdatert versjonskonstanter i `bin/slacky-update`, `lib/common.sh`, `bin/gnomes`, `lib/gnomes_pacman.py` og `slackbuild/slacky-update.SlackBuild`.

---
