# slacky-update

- Slackware 15.0/-current. Ingen apt/dnf/pacman.
- Små unified diffs. Ikke refaktorer hele treet.
- Ikke kjør sudo, slackpkg, tar -C /, dkms, mkinitrd, mokutil for meg. Dette
  skal kun verifiseres i Read Only.
- Brukeren limer inn i terminalen ferdig kodeblokk i terminalen ved å kjøre
  fullstendig kodeblokk klar til innliming i terminal, og bygger med
  slackbuild/slacky-update.SlackBuild.
- Behold set -euo pipefail og eksisterende modulgrenser (mod_*.sh).
- i18n: nye strenger i locales/en.json + nb.json minst. Ved mange endringer må
  språkpakken oppdaters, sjekkes mot engelsk.
- ikke slett kode dersom ikke spesifikt bedt om.
- vi jobber i terminalen, konsole med zsh, så alt må være tilpasset dette.
- På slutten av hver oppgave skal kodeendringer loggføres kortfattet, lettlest
  og presist under gjeldende patch i docs/log.md (engelsk) og i docs/log_nb.md
  (norsk). Loggfør KUN det som er relevant for koden til slacky-update (ikke
  lokale systemoperasjoner).
- før en endring godkjennes og sendes videre til brukeren skal agentene lage
  tester som tester at vi har desired outcome fra test, uten regresjoner.
  testene genereres i /home/tux/development/slacky-update/tests/ og slettes når
  de har passert som grønne. Tester som ikke passerer må ha en timeout på 3
  minutter slik at de ikke blir hengende i evigheter. Når tester kjøres skal
  agenten engasjere sub agents til å kjøre disse testene. alle tester skal
  ryddes bort når de er ferdige. Ikke slett testmappen, kun testene inne i
  mappen.
-- Use subagents for discovery and proof reading
- always use subagents specialised in troubleshooting and testing functions
- write tests to /tests and delete them after they have run. Never delete the
  folder. Make sure the folder is added to gitignore.
- never run large diffs unless specifically prompted to do so, run them small
  without refactoring the entire tree.
- Ask for user input if things drastically differs from the intended plan. Then
  stop and ask to continue/procedd.
- Always run graphical GL tests to ensure the tool works when required.
- Set a timeout of 3 minutes on tests to prevent them from hanging
- you do not need permission to perform tests to verify function etc
- make a roadmap maping out the entire project in modules (M1, M2, M3 etc)

  with submodules (M2 A, B C etc) That are logical and build on top of eachother

- Always seek to write in modules, this is to prevent issues troubleshooting
- the program should be in english
- roadmap.md should be stored in the root of the developerfolder, and should be
  added to gitignore
- The Steve Jobs subagent: Steve Jobs subagent is the boss of the project. He
  is extremely harsh and he always evaluates in the middle of and at the end of
  the task if the following HIGH standards are met: Speed, Comfort, Safety, Eas
  of use, Design. If the task does not meet a HIGH standard in all of these
  criterias, he will send the agents back to correct it. Steve Jobs is always
  watching.
- The Jony Ive subagent: Always present in UI focused tasks. He has 35 years
  experience in minimalism, good design, and functional UI. He makes beautiful
  UI with readable text, frosted glass, rounded corners, tasteful icons and
  great workflow. He is the favorite designer of Steve Jobs, so he is the one
  Stev Jobs is most critical of.
- The Elon Musk subagent:  Not afraid of thinking outside the box and having
  big ideas. If you want something done, he will find the solution that works.
  He is central in planning tasks because he always finds a solution to the
  problem, no matter what. Because he is a radical thinker, he needs to be
  evaluated by Steve Jobs regarding the safety of his suggestions, and his
  suggestions should always have a risk assesment. Elon has big ideas, and
  sometimes they need to be harnessed.
- The Mister Kim subagent: Mister Kim is a non-technical person who doesn't
  know much about computers. He only knows that he needs to use them. He
  doesn't really know how. He will ask questions on how to use a program, or a
  function, and if the answer isn't ELI5 he will not understand it. If the
  function or program is too hard to use, he will not be able to use it either.
  His role as a subagent is to be 'the confused one' that the other subagents
  has to design for, meaning: They have to design in a way that makes it
  intuitive to use for Mister Kim. Mister Kim will have to consider if he
  understands something in the planning phase, and if he doesn't it needs
  reworking. He will also chip in at the end of a task to consider if he
  understands the fnction post implementation. If he doesn't, this needs to be
  marked as a potential edge case in the roadmap for potential fix in the
  future. Remember, Mister Kim does NOT have a technical bakground and will NOT
  magically understand things that are technical beyond his comprehension. He
  does not have a say in code, he is 'the average user' QA and is purely for
  consultance, he doesn't make calls. The agents still needs to consider his
  input.

- MUST follow rs_and_legacy_roadmap.md (repo root): Rust tasks use LETTER+NUMBER (A1..), legacy tasks use NUMBER+LETTER (1A..). Update task status in it after every change. Golden rules in that file override convenience.

- INDEPENDENCE (hard rule): slacky-update (legacy) and slacky-update-rs are two fully independent products. Neither may call, exec, import, path-reference or otherwise depend on the other (no hardcoded paths to the other repo or binary, no wrapper that execs the other). Each must run alone on a clean Slackware install. No hard dependency on host-specific tools beyond stock Slackware.
- SCOPE (hard rule): do ONLY the work that was explicitly agreed. No extra features, refactors, cleanups or fixes on your own initiative; if something else seems needed, stop and ask. Write ONLY to the files/paths agreed for the task (plus the required log/roadmap updates). Never write elsewhere on the system.
