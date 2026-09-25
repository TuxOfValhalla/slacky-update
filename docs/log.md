# 📝 Slacky-Update Development Log

Dette dokumentet sporer patch-utvikling, arkitekturforbedringer, feilrettinger og endringer på vei mot Slacky-Update LTS.

---

## 🚀 [v0.17.0] — 2026-09-25 ("I AM THE LAW!" — Security Hardening, Modular Lua & Display Suite Milestone)

### 🎯 Hovedmål for v0.17.0
Offisiell utgivelse av v0.17.0 ("I AM THE LAW!"). Innføre ren modulær Lua-arkitektur for Hyprland 0.55+ / 0.57+, 3-minutters OLED DPMS-skjermsparing via native Lua IPC, full skjermstyringssuite (`ddcui`, `nwg-displays`, `wlr-randr`), ny force-kill snarvei (`SUPER + SHIFT + K`), feilfri Wayland HiDPI-skalering for terminaler fra systemstatusfeltet, universell Cgroups v2-støtte på tvers av KDE Plasma og Hyprland, og ikke-destruktive oppdateringsrutiner.

### 🛠️ Endringer og forbedringer i v0.17.0

#### 1. Modulær Hyprland Lua-Arkitektur (`~/.config/hypr/modules/*.lua`, `lib/mod_gaming.sh`)
* **Modulær Dekomponering:** Erstattet monolittisk `hyprland.lua` med en ren 7-modulers struktur:
  * `modules/monitors.lua`: Skjermoppløsninger, oppfriskningsrater (240Hz/120Hz), skalering og workspace-ruting.
  * `modules/env.lua`: Qt/GTK High-DPI, Wayland-overstyringer, Breeze-Dark og maskinvareakselerasjon.
  * `modules/autostart.lua`: Portaler, Polkit, PipeWire/WirePlumber, Hypridle, Noctalia og Slacky-Update tray.
  * `modules/general.lua`: Norsk tastaturoppsett (`no,us`), NumLock, Slackware cyan/blå rammer og `force_zero_scaling`.
  * `modules/animations.lua`: 240Hz snappy bezier-kurver (200–250ms).
  * `modules/rules.lua`: Ekte glass-blur, flyteregler for Battle.net/Faugus/DDCui/NWG, og lavlatens for spill.
  * `modules/keybinds.lua`: Komplett snarveisett inkludert ny hurtiglukk/kill (`SUPER + SHIFT + K`).
* **Kryssdistribusjons-kompatibilitet:** Standard `hl.*` og `hl.dsp.*` C-bindings med portabel `package.path`.

#### 2. Skjermstyrings- og Maskinvaresuite (`lib/mod_gaming.sh`)
* **Integrerte Skjermverktøy:** Utvidet både `hyprland-noctalia` og `hyprland-core` med `ddcui` (DDC/CI hardware GUI for lysstyrke/HDR/kontrast), `nwg-displays`, `wlr-randr` og `python-i3ipc`.
* **Flytende Vindusregler:** Automatiske flyteregler for `ddcui` og `nwg-displays` integrert i `rules.lua`.

#### 3. OLED Protection & Hypridle Lua IPC (`~/.config/hypr/hypridle.conf`, `lib/mod_gaming.sh`)
* **3-Minutters Standby:** Konfigurert 180s timeout som kaller `hl.dsp.dpms({ action = "off" })` direkte, eliminerer flimring og beskytter OLED-paneler mot innbrenning.

#### 4. Fiks for HiDPI og Wayland-Skalering fra Systemstatusfeltet (`lib/slacky-update-tray`)
* **Wayland Overstyring:** Sikret at `launch_in_terminal` overstyrer `QT_QPA_PLATFORM="wayland;xcb"` når terminalvinduer åpnes, slik at Konsole alltid starter i native Wayland med skarp 1.5x skalering på 4K-skjermer.

#### 5. Force-Kill Hurtigtast (`SUPER + SHIFT + K`)
* **Umiddelbar Vindu-terminering:** Lagt inn snarvei for rask lukking/kill av aktive vinduer på tvers av live og kuraterte oppsett.

#### 6. Universell Cgroups v2 & VRAM-beskyttelse (`lib/mod_gaming.sh`)
* **Multi-DE Støtte:** Cgroups v2 (+memory +io) og slice-håndtering via `dmemcg-booster` og `ananicy-cpp` bekreftet og herdet for både KDE Plasma og Hyprland.

---

## 🚀 [v0.16.1] — 2026-09-24 ("I AM THE LAW!" — Security Hardening, Mirror Benchmark & Desktop Suite)

### 🎯 Hovedmål for v0.16.1
Utvikling og herding mot v0.17.0 ("I AM THE LAW!"). Innføre global parallell speil-benchmark med interaktiv rangering, maskinvare-differensierte nettleserflagg uten Vulkan-krasj, advarselsfrie Hyprland-oppstartsscript med full XDG-miljøsynkronisering, dynamisk MangoHud/GOverlay-fontspeiling og VRAM-booster beskyttelse for XFCE, KDE og Hyprland.

### 🛠️ Endringer og forbedringer

#### 1. Global Multitrådet Speil-Benchmark (`lib/mod_packages.sh`, `bin/slacky-update`)
* **Parallell Latens & Ferskhet:** Pinger og parser ChangeLog-toppen på tvers av globale Tier-1 speil (Europa, Amerika, Asia/Stillehavet) i parallell via Python multithreading.
* **Interaktiv Valgmeny:** Viser fargekodet tabell med responstid i millisekunder, ChangeLog-tidsstempel og aktivt speil. Lar brukeren oppdatere `/etc/slackpkg/mirrors` med ett tastetrykk.
* **CLI-flagg:** Tilgjengelig via `slacky-update --rank-mirrors`, `--mirrors` eller `-M`.

#### 2. Maskinvare-Differensierte Nettleserflagg (`lib/mod_gaming.sh`)
* **GPU-differensiering:** NVIDIA-oppsett får automatisk VA-API NVDEC (`VaapiOnNvidiaGPUs`) og Wayland-flagg, mens AMD og Intel får rene native Wayland-flagg (`--ozone-platform=wayland`, `--enable-zero-copy`).
* **Vulkan-fjerning:** Eksperimentell `--use-vulkan` er fjernet fullstendig for alle nettlesere (Chrome, Brave, Edge) for å eliminere renderer-frys og GPU-prosesskrasj.

#### 3. Hyprland & Noctalia Suite Hardening (`lib/mod_gaming.sh`)
* **XDG-miljøsynkronisering:** Sikret `XDG_CURRENT_DESKTOP=Hyprland` i `/usr/bin/start-hyprland`, `hyprland.conf` og `hyprland.lua.example`.
* **Advarselsfri oppstart:** Undertrykker falske advarsler og nyhetsmas via `disable_xdg_env_checks = true`, `disable_hyprland_guiutils_check = true`, og `ecosystem { no_update_news = true, no_donation_nag = true }`.
* **Slank Noctalia Dock Seed:** Raffinert standardoppsett (`icon_size = 48`, `magnification_scale = 1.25`, `margin_edge = 4`, `margin_ends = 8`, `radius = 12`).

#### 4. Dynamisk MangoHud & GOverlay Fontspeiling (`lib/mod_gaming.sh`)
* **Automatisk symlinking:** Alle skrifttyper fra `/usr/share/fonts/` og `/usr/local/share/fonts/` speiles automatisk inn i `~/.local/share/fonts/` og `/etc/skel/.local/share/fonts/`.
* **GOverlay-kompatibilitet:** Løser GOverlays absolutte stioppslag, slik at egendefinerte fonter lastes direkte i MangoHud uten bitmap-fallback.

#### 5. Multi-DE VRAM Booster Skjerming (`lib/mod_gaming.sh`)
* **Skjerming av XFCE:** Lagt til `xfwm4`, `xfce4-panel` og `xfdesktop` i dmemcg-booster filteret sammen med KDE Plasma og Hyprland for å unngå VRAM-eviction av skrivebordskomponenter under tung spilling.

#### 6. Underpants Gnomes Pacman Sidecar Engine v0.16.1 (`bin/gnomes`, `lib/gnomes_pacman.py`)
* **Versjonssynkronisering:** Oppdatert User-Agent og headers til `v0.16.1` ("I AM THE LAW!").
* **24 Språkpakker:** 100 % nøkkelkonsistens på tvers av alle `locales/*.json`.

#### 7. Multi-Ecosystem Ukentlig Speil- og Vedlikeholdsmotor (`lib/rank_mirrors.py`, `lib/check_backend.sh`)
* **Skuddsikker 6d 22h Tidsgrense:** Kjører automatisk kun når mer enn 6 dager og 22 timer (597 600 s) er passert siden forrige måling.
* **Oppstartsfred (Grace Period):** Sjekker `/proc/uptime` og avventer oppstart i 120 sekunder slik at skrivebordsinnlogging aldri forsinkes.
* **Lav-prioritet Bakgrunnsutførelse:** Kjøres frakoblet med `nice -n 19 ionice -c 3` og måler i parallell Slackware, Arch Linux (`geo.mirror.pkgbuild.com`), CachyOS og Chaotic-AUR.
* **Strenge Slackware-regler for speil:** Sikrer at oppdatering av `/etc/slackpkg/mirrors` kun etterlater **nøyaktig ett** aktivt speil uten kollisjoner.
* **Pakkebygg:** Oppdatert til `0.16.1-noarch-9_slacky` med Limine Suite Catalog Unification, Dynamic HiDPI Scaling, Fast-Race Chaotic-AUR Engine, Hypridle 3-min OLED DPMS Protection, og full dokumentasjonssynkronisering mot v0.17.0 ("I AM THE LAW!").

#### 8. Selvhelbredende 404 Auto-Sync for Underpants Gnomes (`lib/gnomes_pacman.py`)
* **Automatisk 404-Gjenoppretting:** Dersom oppstrøms-speil (Arch/CachyOS) ruller ut nye pakkeversjoner innenfor databasens 3-timers TTL slik at eldre tarballs returnerer 404 Not Found, fanger Gnomes feilen automatisk.
* **Stille Bakgrunns-Sync:** Kjører en stille, tvungen resynkronisering av databasene (`sync_repositories(force=True, verbose=False)`), oppdaterer pakkenavn/URL til nyeste oppstrømsversjon, og laster ned på nytt i samme kjøring.
* **Null Brukerintervensjon:** Eliminerer behovet for manuell `gnomes sync` etter oppstrøms oppdateringer.

#### 9. Universell Multi-Path Font Mesh for MangoHud & GOverlay (`lib/mod_gaming.sh`)
* **Hierarkisk Kompatibilitets-bro:** Genererer automatiske undermapper (`~/.local/share/fonts/TTF`, `OTF`, `truetype`, `opentype`) som krysslenker samtlige system- og brukerfonter.
* **100 % Feilfrie Spill-Overlays:** Garanterer at uansett hvilken banestruktur GOverlay skriver til `MangoHud.conf` (f.eks. `.../fonts/TTF/Apple/...`), finner Vulkan-overlayet i Wine/Proton/Faugus filen direkte og rendrer den valgte fonten i stedet for å falle tilbake til standard bitmap-font.

#### 10. Limine Suite Katalog-Harmonisering & Transparent Oppdatering (`lib/mod_gaming.sh`, `lib/mod_limine.sh`)
* **Katalog-Harmonisering:** `limine`, `limine-entry-tool` og `limine-snapper-sync` er integrert i hovedkatalogen slik at `check_backend.sh` sjekker og viser oppdateringer i tabellen på forhånd.
* **Fjerning av Tvungen Bundle-installasjon:** `install_unified_limine_suite` rører ikke allerede installerte pakker under oppstarts-sync.

#### 11. Dynamisk & Universell HiDPI / Wayland Skalering (`assets/profile.d/`, `bin/slacky-update`, `desktop/`)
* **Automatisk Qt- og GTK-skalering:** Etablert `/etc/profile.d/slacky-hidpi.sh` (og `.csh`) som setter `QT_ENABLE_HIGHDPI_SCALING=1`, `QT_AUTO_SCREEN_SCALE_FACTOR=1` og `QT_SCALE_FACTOR_ROUNDING_POLICY=PassThrough`.
* **Full Skrivebordskompatibilitet:** Universell støtte på tvers av **Hyprland** (`wp-fractional-scale-v1`), **KDE Plasma** (Wayland & X11), **XFCE** og **GNOME**.
* **Krystallklare Kontekstmenyer på 4K:** Retter mikroskopiske fonter og høyreklikkmenyer i Konsole og andre Qt-verktøy på 4K-skjermer og flerskjermsoppsett.

#### 12. Fast-Race Speilmotor for Chaotic-AUR (`lib/mod_gaming.sh`)
* **Instant-Win Racing:** Avbryter tregere noder umiddelbart når et europeisk lav-latens speil (< 55 ms) svarer via `concurrent.futures.as_completed`.
* **Lav Timeout (750 ms):** Døde eller hengende speil forkastes proaktivt før de sinker oppdateringssjekken.

#### 13. Hypridle 3-Minutters DPMS Skjermbeskyttelse & Løkkefiks (`~/.config/hypr/hypridle.conf`, `lib/mod_gaming.sh`)
* **Fjerning av Egen-Nullstillende Løkke:** Fjernet `hyprctl keyword decoration:dim_inactive true` som utløste IPC konfigurasjons-reload og resatte Wayland `ext-idle-notify-v1` tidsuret hvert 120. sekund.
* **Ren 3-Minutters Standby (DPMS):** Slår av skjermene fullstendig etter 180 sekunder (`hyprctl dispatch dpms off`) og vekker dem umiddelbart ved brukeraktivitet (`hyprctl dispatch dpms on`) for 100 % OLED-beskyttelse og strømsparing.

#### 14. Dokumentasjons-Harmonisering & Whitepaper-Fullføring (`docs/`, `README.md`)
* **100 % Versjonsparitet:** Alle manualer og field guides i `/docs` oppdatert til `v0.17.0` ("I AM THE LAW!").
* **Teknisk Whitepaper:** Utvidet `TECHNICAL_COMPANION_GUIDE.md` med fullstendige spesifikasjoner for Motorene 13, 14 og 15.
* **Nedlastings-Badge:** Integrert sanntids unike nedlastings-tellere fra GitHub Releases i `README.md`.

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

#### 9. Atomisk Single-Pass Multi-Kernel Pipeline (`lib/mod_kernel.sh`)
* **Problem:** Ved installasjon av flere CachyOS-kjernevarianter i samme kjøring (f.eks. `linux-cachyos-bore`, `linux-cachyos-lto`, `linux-cachyos-rc`) kjørte hver pakke full DKMS-kompilering, initramfs-generering, MOK-signering og Limine bootloader-synk i serie, noe som tok unødvendig lang tid.
* **Løsning:** Innført `DEFER_BOOT_SYNC=1` under kjerne-løkker, etterfulgt av en samlet atomisk fullføring av DKMS, Dracut, Secure Boot-signering og Limine BLAKE2B-forsegling.

#### 10. Sanitering av Curated Hyprland Konfigurasjon (`lib/mod_gaming.sh`)
* **Problem:** Hyprland Lua API (`hl.config()`) avviste `.conf`-spesifikke deprecation-nøkler i `misc`-tabellen med feilmeldingen `unknown config key misc.disable_xdg_env_warning`.
* **Løsning:** Sanert `hyprland.lua`- og `hyprland.conf`-malene slik at `hyprland.lua` utelukkende inneholder gyldige Lua API-tabellnøkler (`disable_hyprland_logo`, `disable_splash_rendering`, `force_default_wallpaper`, `background_color`, `vrr`), mens `.conf`-malen bruker de offisielle parser-direktivene.

#### 11. SlackBuild Oppgradering
* Bygget oppgradert til `0.16.0-noarch-7_slacky` i `slackbuild/slacky-update.SlackBuild`.

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
