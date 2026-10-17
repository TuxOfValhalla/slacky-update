# Restart advice: rules (Rust G5-21 / legacy 6A-267)

The same rules in both apps. The boot chain (DKMS, dracut, MOK, Limine, BLAKE2B enroll, sbctl reseal) runs on its own
triggers and is NOT decided here. The restart advice only asks: did something that is in use right now change?

| Row | What changed during the run | Advice | Sentence shown (one concrete reason) |
|---|---|---|---|
| a1 | The running kernel's flavor got a newer version (running `7.2.10-1-cachyos-bore`, new `/lib/modules/7.2.11-1-cachyos-bore`) | yes | The running kernel (cachyos-bore) was updated to 7.2.11-1-cachyos-bore |
| a2 | `/lib/modules/<running release>` existed before the run and is gone after it | yes | The modules of the running kernel (<release>) were removed |
| b | A Slackware kernel package (generic, huge, modules; not headers, source, firmware, docs) whose version equals the running release was replaced or removed | yes | The running kernel package was replaced or removed (<package>) |
| c1 | NVIDIA driver or userspace package changed | yes | NVIDIA graphics driver suite updated (<package>) |
| c2 | glibc (not `glibc-zoneinfo`) | yes | Core C library updated (<package>) |
| c3 | Mesa | yes | Mesa graphics / Vulkan driver updated (<package>) |
| c4 | Display server or desktop (plasma, kwin, sddm, wayland) | yes | Display server / Desktop environment updated (<package>) |
| n1 | A new kernel was added | no | silent |
| n2 | Another flavor was updated (running bore, zen 7.2.9 to 7.2.10) | no | silent |
| n3 | An older version of the running flavor appeared, or a release candidate of another flavor | no | silent |
| n4 | initramfs rebuilt for other kernels | no | silent |
| n5 | Limine reseal, BLAKE2B enroll, MOK signing of other kernels, DKMS for other kernels | no | silent |

Rules of the decision:

- Flavor = the part after the package release in the release string (`7.2.9-zen1-1-zen` is `zen`, `7.3.0-rc6-2-cachyos-rc`
  is `cachyos-rc`, a plain `6.18.52` has none). Newer = higher version, then final before release candidate, then higher
  package release. Only module directories that did not exist before the run count as an update.
- The decision needs the package list and the `/lib/modules` listing from before and after the run.
- Advice without a reason is a bug: a run that set the "boot chain ran" flag but has no row above gives no advice.
- Rust: `RebootAdvisor::evaluate_reboot` (`src/core/reboot.rs`). Legacy: `slacky_reboot_reasons` (`bin/slacky-update`);
  the snapshot files carry the module directories as `MOD:<release>` lines.
