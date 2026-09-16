# Changelog

Notable changes. Releases follow Keep a Changelog and semantic versioning.

## [0.1.0] - 2026-09-16

First public release. Requires Emacs 31.1 or newer. No third-party runtime dependencies.

### Added
- Buffer-local writing sprints with word and time targets.
- Named profiles: `gentle`, `standard`, `flow`, `pressure`, `hardcore`.
- Launch, flow, and recovery/comeback quests.
- Next-action prompts and if/then obstacle plans.
- Commitment-aware stop policies. `C-u M-x write-or-die-stop` always escapes.
- Forward-only drafting and typewriter centering.
- Paragraph focus and TODO placeholders.
- Theme-native HUD with Unicode and ASCII fallbacks.
- Optional Nerd Icons, detected at runtime.
- Optional WAV cues with bell or silent fallback.
- Opt-in `hardcore` rollback limited to edits made during the sprint.
- Metric-only history and statistics. Document text is never stored.

## Pre-release history

The versions below were private and are not part of the public series.

## [2.3.0] - 2026-09-16

### Added
- Commitment-aware stop policies with a prefix-argument escape hatch.
- Forward-only drafting inspired by Hemingway-style writing modes.
- Theme-native typewriter view with vertical centering.
- Opt-in `hardcore` profile that rolls back current-sprint edits after a sustained stall.
- ERT coverage for commitment, drafting, rollback safety, and the new profile.

### Changed
- `flow` now enables typewriter view.
- `pressure` uses forward-only drafting and a commitment lock without deleting text.
- The default unfinished-stop behavior asks for confirmation instead of silently ending the sprint.

### Safety
- Hardcore rollback keeps the pre-sprint buffer in memory and makes one undoable Emacs change.
- A forced stop (`C-u M-x write-or-die-stop`) always escapes commitment mode.

## [2.2.1] - 2026-09-16

### Changed
- Reorganized the repository for GitHub and future MELPA publication.
- Moved the main library to `lisp/`, and made bundled-asset discovery work from
  both a source checkout and a flat package install.
- Added ERT tests, CI, development commands, publishing notes, and license metadata.

## [2.2.0] - 2026-08-25

### Added
- Optional Nerd Icons with Unicode/ASCII fallback.
- Optional bundled event sounds and sound backend configuration.
- Sound-event coalescing and test command.

## [2.1.0] - 2026-08-25

### Added
- Theme-native adaptive HUD for wide, compact, minimal, and inactive windows.
- Semantic faces with no hard-coded foreground/background colors.
- Modeline integration compatible with stock Emacs and custom modelines.

## [2.0.0] - 2026-08-25

### Added
- Launch quests, flow chains, comeback/recovery quests, ranks, profiles, and history.
- Paragraph focus and insertion-oriented momentum tracking.

## [1.0.0] - 2026-08-25

### Changed
- Refactored the original package around buffer-local state, wall-clock timing,
  supportive rescue prompts, tiny next actions, and explicit pause/resume.
