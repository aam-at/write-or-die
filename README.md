# write-or-die.el

[![CI](https://github.com/aam-at/write-or-die/actions/workflows/ci.yml/badge.svg)](https://github.com/aam-at/write-or-die/actions/workflows/ci.yml)

Gamified writing sprints for **Emacs 31.1+**.

`write-or-die` helps when you know what to write but cannot start. Set a word
target and a clock; the mode line tracks both. After a long stall, the package
shows a prompt to get you moving.

Typical flow:

```text
next action → launch quest → flow → stall → rescue → comeback
```

History stores metrics only. Destructive options are opt-in.

## Highlights

- Buffer-local writing sprints
- Named profiles: `gentle`, `standard`, `flow`, `pressure`, `hardcore`
- Live word count, overtime, and optional WPM pressure
- 25-word launch quest, flow chains, and recovery/comeback quests
- Next-action prompts and if/then obstacle plans
- TODO placeholders for missing details
- Paragraph focus and typewriter centering
- Metric-only history and statistics
- Adaptive HUD for wide, split, narrow, and inactive windows
- Theme-native faces with no hard-coded foreground/background colors
- Stock Emacs and custom modelines such as doom-modeline
- Optional Nerd Icons with Unicode/ASCII fallback
- Optional bundled WAV feedback with bell/silent fallback
- Commitment-aware stopping: confirm unfinished exits or lock until a target is met
- Optional forward-only drafting to avoid editing loops
- Opt-in hardcore rollback limited to current-sprint edits
- Optional one-word destructive consequence for classic "Write or Die" pressure

## Repository layout

```text
write-or-die/
├── lisp/
│   └── write-or-die.el       # package library and metadata
├── sounds/                   # optional bundled WAV cues
├── test/
│   └── write-or-die-test.el  # ERT tests
├── docs/
│   ├── INSPIRATIONS.md       # reviewed writing-app mechanics and adaptations
│   └── PUBLISHING.md         # GitHub/MELPA release notes
├── .github/workflows/ci.yml  # Emacs CI
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE
├── Makefile
└── README.md
```

This layout matches MELPA's convention of keeping libraries at the repository
root or under `lisp/`, with tests under `test/`. A MELPA recipe must list
`sounds` because the default package file set omits it.

## Installation from a Git checkout

Clone the repository, add `lisp/` to `load-path`, then load the package:

```sh
git clone https://github.com/aam-at/write-or-die.git
```

```elisp
(add-to-list 'load-path "/path/to/write-or-die/lisp")
(require 'write-or-die)
```

With `use-package`:

```elisp
(use-package write-or-die
  :load-path "/path/to/write-or-die/lisp"
  :commands (write-or-die-start
             write-or-die-start-profile
             write-or-die-stats))
```

The package automatically finds `sounds/` both in this source layout and in a
flattened ELPA/MELPA installation.

### Emacs 31.1 `user-lisp/` tree

Place the repository under your Emacs 31.1 `user-lisp/` tree and put its `lisp/`
directory on `load-path`.

### Doom Emacs

MELPA has no recipe yet, so use a local checkout. If Doom installs the package
from GitHub, point it at `lisp/*.el` and keep `sounds/` as package data.

## Quick start

```text
M-x write-or-die-start
```

For a named profile:

```text
M-x write-or-die-start-profile
```

With a prefix argument, the start command also asks for an implementation
intention:

```text
C-u M-x write-or-die-start
```

## Keybindings

Active while `write-or-die-mode` is enabled:

| Key | Command | Purpose |
| --- | --- | --- |
| `C-c w s` | `write-or-die` | Start / stop |
| `C-c w g` | `write-or-die-start-profile` | Start with a profile |
| `C-c w p` | `write-or-die-toggle-pause` | Pause / resume |
| `C-c w r` | `write-or-die-rescue` | Rescue prompt + recovery quest |
| `C-c w t` | `write-or-die-insert-placeholder` | Insert a TODO placeholder |
| `C-c w i` | `write-or-die-plan` | Next action + if/then plan |
| `C-c w f` | `write-or-die-toggle-focus` | Paragraph focus |
| `C-c w h` | `write-or-die-stats` | Session statistics |
| `C-c w d` | `write-or-die-toggle-draft-discipline` | Free or forward-only drafting |
| `C-c w c` | `write-or-die-toggle-typewriter` | Toggle typewriter centering |

## Profiles and commitment

A profile sets the time and word targets, stop policy, drafting mode, and stall
consequence:

| Profile | Style | Early stop | Drafting | Stall consequence |
| --- | --- | --- | --- | --- |
| `gentle` | low pressure | free | normal | rescue |
| `standard` | balanced | confirm | normal | rescue |
| `flow` | immersive | confirm | normal + typewriter | rescue |
| `pressure` | high commitment | target-locked | forward-only | bell + rescue |
| `hardcore` | deliberate danger | target-locked | forward-only + typewriter | rollback current sprint |

`pressure` and `hardcore` block ordinary stops until you reach the word or time
target. `C-u M-x write-or-die-stop` overrides the policy and always stops.

Forward-only discipline blocks deletion, replacement, and edits behind the
drafting frontier. It does not rebind Emacs movement keys globally. Toggle it
with `C-c w d`.

### Hardcore rollback safety

The `hardcore` profile is opt-in. At sprint start it stores an in-memory buffer
snapshot. When the grace period expires, it restores the snapshot and stops.
Only current-sprint edits are at risk. The rollback is one ordinary Emacs
change group, so normal undo can recover it.

## Adaptive visual design

The defaults work with stock Emacs and custom modelines:

```elisp
(setq write-or-die-visual-style 'auto
      write-or-die-mode-line-location 'global-mode-string
      write-or-die-symbol-style 'auto
      write-or-die-inactive-window-display 'dim)
```

`auto` compresses the HUD based on window width. Faces inherit from semantic
Emacs faces (`mode-line-emphasis`, `warning`, `error`, `shadow`) instead of
fixed colors, so the theme controls them. This works with Modus, Doom, Ef,
Solarized, and terminal palettes.

The mode-line indicator is also readable without color. Unicode/ASCII state
shapes distinguish running, warning, rescue, paused, and stopped states.

## Nerd Icons

`nerd-icons` is optional. With `write-or-die-symbol-style` set to `auto`, the
package checks for the package and a displayable Nerd Font glyph, then falls
back to Unicode or ASCII.

To retry detection after installing fonts or `nerd-icons`:

```text
M-x write-or-die-refresh-icons
```

To force a style:

```elisp
(setq write-or-die-symbol-style 'nerd-icons) ; or 'unicode / 'ascii
```

## Sounds

The bundled cues are short WAV files for these events:

```text
start launch chain milestone warning rescue comeback target pause resume stop
```

The `auto` backend tries WAV playback, then uses the Emacs bell for warnings,
rescues, targets, and comebacks:

```elisp
(setq write-or-die-sound-backend 'auto
      write-or-die-sound-volume 0.28)
```

Disable sound entirely:

```elisp
(setq write-or-die-sound-backend 'none)
```

Choose which events make sound:

```elisp
(setq write-or-die-sound-events
      '(start warning rescue comeback target stop))
```

Audition a cue with:

```text
M-x write-or-die-test-sound
```

Set `write-or-die-sound-directory` to use your own compatible WAV files.

## Suggested configuration

```elisp
(use-package write-or-die
  :load-path "/path/to/write-or-die/lisp"
  :commands (write-or-die-start
             write-or-die-start-profile
             write-or-die-stats)
  :custom
  (write-or-die-gamification t)
  (write-or-die-launch-words 25)
  (write-or-die-chain-words 25)
  (write-or-die-recovery-words 20)
  (write-or-die-activity-kind 'insertion)
  (write-or-die-auto-stop-at-time nil)
  (write-or-die-consequence 'rescue)
  (write-or-die-stop-policy 'confirm)
  (write-or-die-draft-discipline 'free)
  (write-or-die-visual-style 'auto)
  (write-or-die-symbol-style 'auto)
  (write-or-die-sound-backend 'auto))
```

## Development

Requires Emacs 31.1+.

```bash
make ci        # compile, test, checkdoc
```

If installed, also run:

```bash
make package-lint
```

GitHub Actions runs these checks on Emacs 31.1 and the development snapshot.
Checkdoc runs on 31.1 only because its rules change between releases. See
[`CONTRIBUTING.md`](CONTRIBUTING.md) and the reviewed writing tools in
[`docs/INSPIRATIONS.md`](docs/INSPIRATIONS.md).

## Publishing

The repository layout keeps `lisp/` and `sounds/` where a MELPA recipe expects
them. See [`docs/PUBLISHING.md`](docs/PUBLISHING.md) for the recipe and release
checklist.

Do not commit `write-or-die-pkg.el`. MELPA generates it from the headers in
the main library.

## License

GPL-3.0-or-later. See [`LICENSE`](LICENSE).
