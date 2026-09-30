# 📝 Slacky-Update Development Log

Dette dokumentet sporer patch-utvikling, arkitekturforbedringer, feilrettinger og endringer på vei mot Slacky-Update LTS.

## 🚀 [v1.0_RC2] — 2026-09-30 ("Dark Star" — Build 26 / noarch-26)

### 🎯 Hovedmål for v1.0_RC2
Kritisk arkitekturstabilisering, flimmerfri terminalstrømming og maskinvare-rettelser oppdaget under felttesting av v1.0_RC1:
1. **Full-Spectrum Stream Normalizer & Scrollback-Bevaring:** Sanntids streaming-normalisering i `run_slackpkg()` som oversetter `\r` og DEC Restore Cursor (`\x1b8`, `\x1b[u`) til ekte linjeskift, stripper samtlige VT100/CSI/DEC/OSC escape-koder, filtrerer ut spinner-linjer (`|/-\`), fjerner `wget`-bakgrunnsomdirigeringsstøy (`Redirecting output to 'wget-log.N'`), og kjører fra midlertidige mapper for å eliminere filforsøpling i `$HOME`.
2. **Isolert App-Bundle Arkitektur:** GUI-apper som krever eksterne/uoffisielle runtimes (som `openghub` med WebKitGTK 4.1, `lutris`, `obs-studio`, `pear-desktop`, `bambu-studio`) pakkes nå som 100 % isolerte App-Bundles i `/opt/<app>/` med egne private biblioteker i `/opt/<app>/lib/`. Dette forhindrer at avinstallasjon (`removepkg`) eller oppgradering av én app sletter eller forstyrrer felles system-runtimes i `/usr/lib64/` eller krasjer andre apper. (OpenGHub er midlertidig skjult fra spillmenyen via `|hidden`-flagget inntil ekstern perifer-atferd er ferdig kartlagt).
3. **Flimmerfri Terminal-Markør & 10-Linjers ILoveCandy:** Full harmonisering av `gnomes_pacman.py` med `lib/common.sh` og `lib/pacman_candy.py`. Opptil 10 parallelle spor gomler synkront med Slackware-blå `S`/`s` og stasjonære pellets. Grønne hakker er fjernet til fordel for ekte Pacman 100%-historikk og låst Total-linje på bunnen.
4. **Maskinvaretilpasset Hyprland Lua-miljø:** Dynamisk GPU-deteksjon (NVIDIA vs AMD vs Intel vs PRIME) i `~/.config/hypr/modules/env.lua` og `/etc/hypr/hyprland.env`, sanert `GBM_BACKEND` og `immediate = true` tearing-regler for spill.
5. **Multilib Version Intersection Engine:** Matematisk versjonssnitt for ledsagerpakker (`gamescope`, `mangohud`, `gamemode`, `obs-vkcapture`, `yabridge`) slik at oppdateringsvarsler kun trigges når 64-bit og 32-bit pakker er synkront tilgjengelige på speil.
6. **Helhetlig Dokumentasjonsgjennomgang & Overhaling:** Utarbeidelse av *The Ultimate Slacky-Update Survival Guide* og *Oh My Hyprland Guide*, opprydding i README.md og sentralisering av historiske release notes i `/home/tux/development/docs/slacky-update_releasenotes/`.
7. **CachyOS Zen 4/5 (znver4) & 404 Self-Healing:** Korrigert CachyOS speil-URL-er for Zen 4/5 mikrostier (`x86_64_v4/cachyos-*-znver4`) og kortsluttet 404-feil direkte til automatisk database-synkronisering ved nye oppstrøms revisjoner.
8. **Dyp Runtime Bibliotek-Oppdager & Typst/Pandoc Kompatibilitet:** Automatisk oppdagelse av dypt nøstede kjørebiblioteker (GHC Haskell, Lua, Python, Qt6) i applikasjonswrappers, og sanering av innholdsfortegnelse-ankre for 100 % feilfri Typst PDF-kompilering.


---

## 🚀 [v1.0_RC1] — 2026-09-25 ("Wonderwall" — Generalprøve & Systemherding)

### 🎯 Hovedmål for v1.0_RC1
Offisiell utgivelse av v1.0 RC1 ("Wonderwall" — Generalprøven før 1.0 LTS).
Full eliminering av maskinvarefeilkonfigurasjoner (NVIDIA vs AMD vs Intel), dedikert hybrid-bærbar/PRIME-differensiering, ikke-blokkerende uprivilegert rettighetshåndtering, robust nettverks- og nedlastningsherding uten kunstige timeouts på store filer, og optimalisert ressursbruk i bakgrunnen.

### 🛠️ Endringer og forbedringer i v1.0_RC1

#### 1. Hybrid GPU & Bærbar Støtte (`lib/common.sh`, `lib/mod_gaming.sh`)
* **Chassis & DMI Deteksjon:** Utvidet `is_laptop_chassis()` og `probe_gpu_hardware()` til å detektere multi-GPU/Optimus-laptoper (`IS_HYBRID_GPU=true`).
* **Wayland Compositor Sikring:** På hybride laptoper settes ikke `GBM_BACKEND=nvidia-drm` globalt i `/etc/hypr/hyprland.env`. Dette forhindrer frys og krasj på integrerte skjermer som drives av Intel/AMD KMS `/dev/dri/card0`, mens spill og tunge apper offloades problemfritt via PRIME (`__NV_PRIME_RENDER_OFFLOAD=1`).
* **Korrekt VA-API Ruting:** På hybrid-systemer rutes `LIBVA_DRIVER_NAME` automatisk til iGPU (`iHD` for Intel, `radeonsi` for AMD) for energieffektiv videoavspilling.

#### 2. Ikke-Blokkerende Uprivilegerte Operasjoner (`lib/common.sh`)
* **Privilegieminimering:** `init_storage()` forsøker ikke lenger å tvinge gjennom interaktive `sudo`-forespørsler ved uprivilegerte kjøringer (f.eks. ved menylesing, statussjekk eller fra bakgrunnsprosesser), men benytter passordløs `sudo -n` eller brukerens lokale cache.

#### 3. Herdet Nettverks- og Nedlastingsarkitektur (`lib/mod_*.sh`, `lib/common.sh`)
* **Ingen Premature Timeouts:** Fjernet harde tidsbegrensninger (som `-m 180` / `-m 120`) på store nedlastinger (NVIDIA-drivere, kjerner, multilib-pakker).
* **Adaptiv Feilhåndtering:** Innført `--connect-timeout 10 --speed-limit 1024 --speed-time 25` slik at nedlastinger tillates å bruke den tiden de trenger så lenge data overføres, samtidig som hengende forbindelser fanges opp og termineres raskt.

#### 5. Feilretting for Underpants Gnomes Batch-oppgraderinger (`lib/mod_gaming.sh`, `lib/check_backend.sh`)
* **Strukturert Oppgraderings-Payload:** Rettet formatmismatch i `check_all_installed_gaming_updates_fast` slik at den leverer strukturerte data (`pid|name|cur_ver|latest_ver`).
* **Sømløs Pakkeoppløsning:** `sync_all_installed_cachyos_gaming_packages` fanger nå opp den faktiske pakke-ID-en (`microsoft-edge`) i stedet for hele den formaterte strengen, slik at enkelt- og batch-oppgraderinger installeres og bygges uten avvisninger.

#### 6. Privilegiesanering & Modent Designdirektiv (Build 2 / noarch-2)
* **Limine Sudo-Fjerning:** Fjernet tidlig `validate_privileges` og `sudo test -f` ved inngang til `manage_limine_interactive()` – statusvisning og lesing forblir 100 % uprivilegert, og `sudo` kreves kun ved faktiske skrivehandlinger.
* **Typografisk Sanering & Rensede menyer:** Fjernet hardkodede prefiks-tall (`0.`, `4.`, `5.`) i NVIDIA-menyen på tvers av 24 språk (`locales/*.json`), renset bort lynikoner og ASCII-pynt til fordel for faste overskrifter i Slackware-blått, og oppdatert referanser til kun å dekke `Slackware -current / 15+ & 16 Alpha`.

#### 7. Autentisk ILoveCandy Pacman-Gomling (Build 4 / noarch-4)
* **Stasjonære Mat-Pellets (`lib/pacman_candy.py`, `lib/gnomes_pacman.py`, `lib/common.sh`):** Fikset relativ indeksfeil i mat-generatoren hvor indeksen restartet på 0 foran snuten til S. Erstatter relativ looping med den globale skjermindeksen `j` i sporet (`range(pos + 1, width)`).
* **Ingen Dytte-Effekt:** Alle `o`-er står nå 100 % stasjonære på faste partallskolonner på skjermen og blir slukt én etter én etter hvert som `S` ruller over dem og etterlater seg `--`.

#### 8. Sanering av ILoveCandy Fargepalett (Build 5 / noarch-5)
* **Krystallren Monokrom Layout (`lib/common.sh`):** Fjernet alle overflødige ANSI-farger (gult, grønt, magenta, cyan) fra fremdriftslinjene.
* **Fokus på S/s Gomleren:** Kun `S` og `s` rendres i fet Slackware-blå (`\033[1;34m`). All annen tekst (prosent, hastighet, filnavn, tellere og ETA) forblir i ren hvit/standard terminalfarge.

#### 9. 100% Autentisk Pacman ILoveCandy Kolonnelayout (Build 6 / noarch-6)
* **Universal Kolonnestruktur (`lib/common.sh`, `lib/pacman_candy.py`, `lib/gnomes_pacman.py`):** Samkjørt kolonneoppsettet i hele systemet til ekte Arch/Pacman-standard: `[Filnavn] [Størrelse] [Hastighet] [ETA] [Fremdriftslinje] [Prosent]`.
* **Perfekt Venstreflanke-Justering:** All numerisk telemetri (KiB/MiB, MiB/s, ETA) er fast plassert til venstre for sporet, slik at fremdriftslinjene starter på samme vertikale kolonne og avsluttes med en høyrejustert prosentindikator.

#### 10. Rullende Pacman Nedlastingsmotor & Transmutasjonsrensking (Build 7 / noarch-7)
* **Rullende Terminal-Rendring (`lib/common.sh`):** Ferdignedlastede filer låses umiddelbart som permanente linjer med `[--------------------] 100%` i terminalhistorikken uten flimring eller ANSI-markørfeil. Aktive tråder oppdateres dynamisk under de ferdige filene, og `Total (x/N)` holdes låst på bunnen.
* **Eksakte Størrelsesberegninger:** Fjernet den kunstige `+ 15 MB` ekspansjonshacket i `lib/common.sh`. Total og filstørrelser beregnes nøyaktig fra faktiske overførte bytes og HTTP Content-Length, med naturlig over-100% telling ved dynamisk kompresjonsavvik.
* **Minimalistisk & Sømløs Transmutasjons-Typografi (`lib/mod_gaming.sh`):** Fjernet tunge ASCII-bokser (`====`) og overflødige tellere (`[1/1]`). Erstattet med ren Slackware Cyan tittel (`🧙 Transmuting & Deploying: ${pkg}`) og strukturerte innrykkede kulepunkter (`  • `) uten repeterende kolon-spam.

#### 11. NVIDIA Arkitektur-Frakobling, Pascal CachyOS-Ruting & Nettleserakselerasjon (Build 8 / noarch-8)
* **Eliminering av .run Split-Brain:** Fjernet usikre og kolliderende 615/580 `.run`-alternativer fra hovedrutene for å forhindre filkollisjoner på `/usr/lib64/libGL.so*` og brutte symlenker.
* **CachyOS Native Suite som 100% Standard:** Turing+ (RTX 20/30/40/50, GTX 16xx) rutes utelukkende til `nvidia-open-dkms` med full 64-bit og 32-bit multilib-pakke, OpenCL, VA-API og settings.
* **Automatisk Pascal-Ruting til CachyOS 580xx:** Pascal (GTX 10-serien, GP100–GP108) detekteres automatisk og rutes til `nvidia-580xx-dkms` med 100 % matchende userspace (`nvidia-580xx-utils`, `lib32-nvidia-580xx-utils`, `opencl-nvidia-580xx`, `lib32-opencl-nvidia-580xx`, `libva-nvidia-driver`), og skjermes strengt mot uforenlig 600+ userspace.
* **Dedikert Frittstående Legacy .run-Undermeny:** Tilbyr offisielle eldre NVIDIA-grener (**595**, **570**, **535**, **470**, **390**) i en isolert undermeny for eldre systemer og spesialtilpassede arbeidsstasjoner.
* **Automatisk .run til CachyOS-Overgang (`transition_legacy_run_to_cachyos`):** Renser automatisk bort uadministrerte `.run`-installasjoner, foreldede symlenker og gjenoppretter rene Mesa GL-tilstander før CachyOS-pakker rulles ut.
* **Maskinvaretilpasset Nettleserakselerasjon (`lib/mod_gaming.sh`):** Moderne GPU-er (Turing+) aktiverer full VA-API NVDEC (`VaapiOnNvidiaGPUs,AcceleratedVideoDecodeLinuxGL`), mens Pascal/Legacy-GPU-er tildeles trygge Wayland- og GPU-rasteriseringsflagg for å forhindre nettleserkrasj.
* **Modulær Hyprland Lua GUI-Hook:** Lagt inn `pcall(dofile, os.getenv("HOME") .. "/.config/hypr/hyprland-gui.lua")` i `hyprland.lua` slik at eksterne GUI-konfigurasjonsverktøy (som HyprMod) kan overstyre innstillinger dynamisk uten å røre de 7 kjerne-modulene.

#### 12. HyprMod First-Class Integrasjon, AUR RPC Oppdateringsmotor & 10-Bit OLED Støtte (Build 9 / noarch-9)
* **HyprMod First-Class Curation (`underpants-hyprmod`):** Integrert BlueManCZs `hyprmod` (v0.4.0) – en visuell innstillings- og regeleditor for Hyprland bygget med GTK4 og Libadwaita. Pakkemotoren bygger og pakker alle 6 rene Python-moduler (`hyprland-config`, `hyprland-monitors`, `hyprland-schema`, `hyprland-socket`, `hyprland-state`, `hyprmod`) samt `.desktop` launcher, SVG-ikoner og AppStream metainfo inn i en frittstående Slackware `.txz`-pakke.
* **Lynrask AUR RPC v5 & GitHub API Oppdateringsmotor (`lib/mod_gaming.sh`):** Implementert dedikert AUR RPC v5 API-oppslag (`https://aur.archlinux.org/rpc/v5/info?arg[]=<pkg>`) og GitHub Release query med lokal caching (TTL 1800s). `slacky-update-tray`, `slacky-update` CLI og `gnomes` sjekker automatisk etter nye versjoner og varsler brukeren umiddelbart ved oppdateringer.
* **Sømløs Modulær Lua & 10-Bit HDR/OLED Støtte:** `hyprland.lua`-malen inkluderer `require("hyprland-gui")` og oppretter automatisk en ren `~/.config/hypr/hyprland-gui.lua`. HyprMod skriver direkte til denne filen, støtter 10-bits farger (`bitdepth = 10` for OLED som ASUS ROG Swift PG32UCDM), tilpassede skjermoppsett og rammer med øyeblikkelig hot-reload uten å berøre kjernekonfigurasjonen.
* **Dedikert CLI-Snarvei:** Lagt til `--hyprmod` i `bin/slacky-update` for direkte installasjon og vedlikehold.

#### 13. Strømlinjeformet Single-Pass Pipeline, Mac Tahoe & WhiteSur Ricing Suite (Build 10 / noarch-10)
* **Retting av Unbound Variable i `sync_bootloader_configuration` (`lib/mod_kernel.sh`):** Sikret funksjonsparametere (`local kver_full="${1:-$(uname -r 2>/dev/null || echo "")}"`) slik at batch-oppgraderinger under `set -euo pipefail` aldri krasjer når funksjonen kalles uten eksplisitt argument.
* **Ekte Atomisk Single-Pass Pipeline (`lib/mod_kernel.sh`, `lib/mod_clean.sh`):** `DEFER_BOOT_SYNC=1` beholdes nå aktiv gjennom hele transaksjonen (kjerneekstrahering, `--no-sync` kjernefjerning og NVIDIA-suite). Dracut, MOK-signering og Limine BLAKE2B-forsegling kjøres nå nøyaktig **én gang samlet** helt til slutt.
* **Renset Typografi & Slutt på Cyan-Firkantene (`lib/common.sh`):** `log_info` er oppgradert fra to fete cyan-kolon (`::`) til et rent og ryddig innrykket kulepunkt (`  • `), som fjerner den massive 4-prikkers firkantstøyen i Konsole og gir en moden terminalopplevelse.
* **Lynrask Multithreaded NVIDIA-Pakkebygging (`lib/mod_nvidia.sh`):** Satt `XZ_OPT="-T0 -1"` under `makepkg`-pakkingen av `cachyos-nvidia-utils`, som utnytter alle CPU-kjerner og reduserer pakke- og komprimeringstiden fra ~60 sekunder til ~1.5 sekunder.
* **Mac Tahoe & WhiteSur Ricing Suite i Underpants Gnomes (`lib/mod_gaming.sh`):**
  * Ny kuratert kategori: `ricing` (Ricing & Desktop Customization).
  * `mactahoe-icons`: 27 macOS Tahoe-vektorvarianter for KDE Plasma, XFCE og GTK.
  * `mactahoe-cursors`: macOS Tahoe-pekere for X11 & Wayland (lyse og mørke varianter).
  * `whitesur-icons`: Klassisk macOS Big Sur / Sonoma stil ikonpakke.
  * `whitesur-cursors`: WhiteSur macOS-pekere med animerte spinnere.
* **Dedikerte CLI-Snarveier:** Lagt til `--mactahoe-icons`, `--mactahoe-cursors`, `--whitesur-icons` og `--whitesur-cursors` i `bin/slacky-update`.
* **SlackBuild Oppgradering:** SlackBuild bumpet til `1.0_RC1-noarch-10_slacky`.

#### 14. Batch-Oppløser for Ricing Themes & TUI Menysynkronisering (Build 11 / noarch-11)
* **Parallell Batch-Oppløser for GitHub/AUR Ricing Pakker (`lib/mod_gaming.sh`):**
  * Registrert `mactahoe-icons`, `mactahoe-cursors`, `whitesur-icons` og `whitesur-cursors` i `resolve_multiple_gaming_upstreams_batch` katalogen og `resolve_single(pid)` oppslaget.
  * Batch-oppløseren returnerer nå live AUR RPC v5 metadata og merker pakkene med `GITHUB_THEME` i stedet for `NONE`, slik at parallelle flervalg i TUI-menyen (f.eks. `50 51`) aldri feilaktig avvises med `⚠ Skipping unresolved package`.
  * Forhåndsnedlastingssløyfen (`deploy_gaming_packages_batch`) gjenkjenner nå `GITHUB_THEME` på lik linje med `BUNDLED` og ruter pakkene direkte til transmutasjons- og byggemotoren.
* **TUI Konsollmenysynkronisering (`interactive_cachyos_gaming_menu`):**
  * Lagt til `"ricing"` i `CAT_KEYS` og `CAT_TITLES` samt filbane-deteksjon i `BINARY_MAP`, slik at **💎 Ricing & Desktop Aesthetics** vises fullstendig i konsollmenyen når den startes fra terminal eller tray-applet.
  * Automatisk generering av `.icon-theme.cache` via `gtk-update-icon-cache` for alle undermapper under `/usr/share/icons/` ved installasjon.
* **Lynrask Multithreaded Pakkebygging for Gaming & Ricing (`lib/mod_gaming.sh`, `lib/mod_rocm.sh`):**
  * Satt `XZ_OPT="-T0 -1"` under `makepkg`-pakkingen i `mod_gaming.sh` og `mod_rocm.sh` på samme måte som i `mod_nvidia.sh`. Dette utnytter alle tilgjengelige CPU-tråder og kutter komprimeringstiden til en brøkdel av et sekund.
* **SlackBuild Oppgradering:** SlackBuild bumpet til `1.0_RC1-noarch-11_slacky`.

#### 15. Direkte Parallell Tar-XZ Pakkemotor & Eliminering av Makepkg Flaskehals (Build 12 / noarch-12)
* **Eliminering av Makepkg Flaskehals (`lib/mod_gaming.sh`, `lib/mod_nvidia.sh`, `lib/mod_rocm.sh`):**
  * Slackwares tradisjonelle `/sbin/makepkg -l y` kjører en enkelttrådet `find . -type l -exec rm -v {} \;` som starter en ny `rm`-prosess for hver eneste symbolske lenke (over 50 000 ganger for store ikontemaer), samt en langsom sjekk av gzip- og ELF-integritet. Dette skapte en 2–3 minutters frys under `Assembling Slackware package...`.
  * Erstattet `/sbin/makepkg`-kallet med den moderne, direkte parallelle rørledningen: `find ./ | LC_COLLATE=C sort | sed '2,$s,^\./,,' | tar --no-recursion -T - -cf - | xz -T0 -1 > "${txz_out}"`.
  * Pakkingen av massive pakker med 100 000+ filer og symlenker (som MacTahoe med 27 temaer) tar nå **under 1 sekund** over alle tilgjengelige CPU-tråder.
* **SlackBuild Oppgradering:** SlackBuild bumpet til `1.0_RC1-noarch-12_slacky`.

#### 16. AUR Git Versjonssymmetri & Fjerning av Falske Oppdateringsvarsler (Build 13 / noarch-13)
* **Symmetrisk AUR RPC Versjonshåndtering (`lib/mod_gaming.sh`):**
  * Fjernet asymmetrisk `.replace("r", "")` i `resolve_cachyos_gaming_upstream_metadata` og `resolve_multiple_gaming_upstreams_batch`.
  * Versjonsstrengen fra AUR RPC v5 bevares nå i sin kanoniske form (`2025.10.16.r1.9669dfee`) under både enkelt- og batch-transmutasjon, nøyaktig slik `check_all_installed_gaming_updates_fast` leser den.
  * Eliminerer falske oppdateringsvarsler og forhindrer at MacTahoe- og WhiteSur-temaene havner i en evig oppdateringsløkke etter vellykket installasjon.
* **SlackBuild Oppgradering:** SlackBuild bumpet til `1.0_RC1-noarch-13_slacky`.

#### 17. Null-Vent Oppgraderingsmotor & Asynkron Bakgrunns-Cache (Build 14 / noarch-14)
* **Gjenbruk av Kjente Utdaterte Pakker (`lib/mod_gaming.sh`, `lib/check_backend.sh`):**
  * `check_backend.sh` lagrer nå strukturerte oppdateringsdata (`cachyos_gaming_updates_raw`) i `status.json`.
  * `sync_all_installed_cachyos_gaming_packages` leser de kjente oppdateringene direkte fra `status.json` i stedet for å tvinge gjennom en ny 25-sekunders online-skanning mot 8 repositories og AUR.
  * Kutter oppstartstiden for underpants-oppgraderinger under Full System Upgrade fra **25 sekunder til 0,0 sekunder**.
* **Lydløs Asynkron Status-Oppfrisking (`bin/slacky-update`):**
  * Fjernet den synkrone 20-sekunders blokkeringen av `slacky-update-check` på slutten av oppgraderingstransaksjoner (`Refreshing package cache...`).
  * Oppfrisking av `status.json` og systemstatusfeltet sendes nå automatisk til en frakoblet bakgrunnsprosess (`trigger_silent_background_refresh &`).
  * Brukeren får terminalprompten tilbake på mikrosekundet idet oppgraderingen er ferdig.
* **SlackBuild Oppgradering:** SlackBuild bumpet til `1.0_RC1-noarch-14_slacky`.

#### 18. NVIDIA egl-gbm Xwayland & KWin DRM Bridge Fix (Build 17 / noarch-17)
* **NVIDIA egl-gbm Integrasjon i CachyOS Driver Suite (`lib/mod_nvidia.sh`):**
  * **Rotårsak Løst:** Løst alvorlig ytelsesfall (10–12 FPS og 100 % CPU software-rendering med `llvmpipe/swrast`) i spill under Xwayland (som World of Warcraft / Battle.net) og oppstartskrasj i KDE Plasma Wayland (KWin) tilbake til SDDM.
  * **Arkitekturfiksen:** Slackware current leverer standardpakken `egl-wayland`, men mangler `egl-gbm`. Da `.run`-driveren ble fjernet til fordel for CachyOS-pakker, manglet GBM external platform (`15_nvidia_gbm.json` og `libnvidia-egl-gbm.so.1`), som førte til at `eglInitialize()` på GBM feilet og Xwayland deaktiverte GLAMOR maskinvareakselerasjon.
  * **Automatisert Pakking:** `build_and_deploy_cachyos_nvidia_userspace` laster nå automatisk ned og GPG-verifiserer `egl-gbm` fra upstream og pakker både 64-bit biblioteket (`/usr/lib64/libnvidia-egl-gbm.so*`) og JSON-plattformfilen (`/usr/share/egl/egl_external_platform.d/15_nvidia_gbm.json`) direkte inn i `cachyos-nvidia-utils`.
  * **64-bit Xorg OutputClass & GLX Symlinker:** Patchet `10-nvidia-drm-outputclass.conf` for 64-bit Slackware `/usr/lib64/` paths og opprettet korrekte symlenker for `libglxserver_nvidia.so`.
  * **Sanering av Minnestruping:** Fjernet Arch-spesifikke strupeprofiler som `limit-vram-usage`.
* **Maskinvaretilpasset Hyprland Lua Miljø (`lib/mod_gaming.sh`):**
  * `modules/env.lua` og `/etc/hypr/hyprland.env` genereres nå dynamisk basert på maskinvare-probering (NVIDIA vs AMD vs Intel vs Hybrid PRIME laptoper).
  * Fjernet foreldet og potensielt forstyrrende `GBM_BACKEND=nvidia-drm`.
  * Lagt til vindus- og tearing-regler i `modules/rules.lua` for Battle.net, World of Warcraft, Wine og Proton.
* **SlackBuild Oppgradering:** SlackBuild bumpet til `1.0_RC1-noarch-17_slacky`.

#### 19. Flimmerfri Terminalmarkør & ANSI Overskrivingssanering (Build 18 / noarch-18)
* **Eliminering av Terminaloverskriving (`lib/common.sh`, `lib/mod_packages.sh`):**
  * **Rotårsak Løst:** Fikset overskriving av terminalmenyen under pakkenedlasting forårsaket av at `\033[NA` (*Cursor Up*) i `download_parallel_pacman` heiste markøren for høyt opp i terminalhistorikken under nettverksfeil eller asymmetriske linjetellinger.
  * **Presis Markøraritmetikk:** Innført obligatorisk `\r` før markøroppheising (`\r\033[NA`), full linjerens med `\033[2K`, og skjermvisking under aktivt spor med `\033[J` (*Erase Display Below*) ved dynamiske linjeendringer og avsluttende buffer-flush.
  * **Sikker Linjeskille mot Slackpkg:** Sikret rene linjeskift og buffer-flushing før `slackpkg` overtar terminalen, slik at `slackpkg` sine `\r`-linjer (`Looking for packages...`) aldri skriver over tidligere menylinjer eller etterlater datostempel-fragmenter.
* **Release Notes for v1.0_RC2:** Opprettet `docs/RELEASE_NOTES_v1.0_RC2.md` som dokumenterer Build 18-forbedringene i detalj.
* **SlackBuild Oppgradering:** SlackBuild bumpet til `1.0_RC1-noarch-18_slacky`.

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
