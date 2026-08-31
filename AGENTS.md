# slacky-update
- Slackware 15.0/-current. Ingen apt/dnf/pacman.
- Små unified diffs. Ikke refaktorer hele treet.
- Ikke kjør sudo, slackpkg, tar -C /, dkms, mkinitrd, mokutil for meg. Dette skal kun verifiseres i Read Only.
- Brukeren limer inn i terminalen ferdig kodeblokk i terminalen ved å kjøre fullstendig kodeblokk klar til innliming i terminal, og bygger med slackbuild/slacky-update.SlackBuild. 
- Behold set -euo pipefail og eksisterende modulgrenser (mod_*.sh).
- i18n: nye strenger i locales/en.json + nb.json minst. Ved mange endringer må språkpakken oppdaters, sjekkes mot engelsk.
- ikke slett kode dersom ikke spesifikt bedt om.
- vi jobber i terminalen, konsole med zsh, så alt må være tilpasset dette.
