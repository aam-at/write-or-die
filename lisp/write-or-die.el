;;; write-or-die.el --- Gamified writing sprints -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Alexander Matyasko

;; Author: Alexander Matyasko <alexander.matyasko@gmail.com>
;; Maintainer: Alexander Matyasko <alexander.matyasko@gmail.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "31.1"))
;; Keywords: convenience, writing, productivity
;; URL: https://github.com/aam-at/write-or-die
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;;
;; `write-or-die' is a buffer-local writing-sprint package for breaking through
;; writing and productivity blocks.  It combines tiny next actions, visible
;; momentum, recovery-oriented gamification, optional pace pressure, paragraph
;; focus, and private metric-only session history.
;;
;; Its visual layer is distribution- and theme-native:
;;
;; - no hard-coded foreground/background colors;
;; - faces inherit from standard Emacs semantic faces;
;; - the HUD compresses automatically in narrow windows;
;; - inactive windows are quiet by default;
;; - optional `nerd-icons' integration is used only when both package and font
;;   are available, with Unicode/ASCII fallback;
;; - optional event sounds use bundled, deliberately short WAV cues and fall
;;   back to the Emacs bell when file playback is unavailable;
;; - no Powerline, Doom, or third-party modeline dependency;
;; - the default `global-mode-string' integration works with stock Emacs and
;;   common custom modelines such as doom-modeline.  A traditional minor-mode
;;   lighter remains available as a fallback.
;;
;; Quick start: M-x write-or-die-start
;;
;; C-c w s  start/stop       C-c w g  start profile
;; C-c w p  pause/resume     C-c w r  rescue
;; C-c w t  TODO placeholder C-c w i  implementation plan
;; C-c w f  paragraph focus  C-c w h  stats
;; C-c w d  draft discipline C-c w c  typewriter

;;; Code:

(require 'subr-x)
(require 'thingatpt)

(declare-function nerd-icons-faicon "nerd-icons" (icon &rest args))

(defconst write-or-die--package-directory
  (let ((library-dir (file-name-directory
                      (or load-file-name buffer-file-name default-directory))))
    (cond
     ;; Installed package: write-or-die.el and sounds/ share one directory.
     ((file-directory-p (expand-file-name "sounds" library-dir))
      library-dir)
     ;; Source checkout: lisp/write-or-die.el with sounds/ at repository root.
     ((file-directory-p (expand-file-name "../sounds" library-dir))
      (file-name-directory (directory-file-name library-dir)))
     ;; Keep custom sound-directory usable even if bundled assets are absent.
     (t library-dir)))
  "Root directory of the loaded Write-or-Die package or source checkout.")

(defgroup write-or-die nil
  "Gamified, evidence-informed writing sprints."
  :group 'convenience
  :prefix "write-or-die-")

;;;; Core behavior

(defcustom write-or-die-target-words 250
  "Default net-word target."
  :type 'natnum :group 'write-or-die)

(defcustom write-or-die-target-time (* 20 60)
  "Default sprint duration in seconds."
  :type 'natnum :group 'write-or-die)

(defcustom write-or-die-warning-period 20
  "Seconds without meaningful writing before warning."
  :type 'number :group 'write-or-die)

(defcustom write-or-die-grace-period 45
  "Seconds without meaningful writing before rescue."
  :type 'number :group 'write-or-die)

(defcustom write-or-die-milestone-words 50
  "Net words between small progress acknowledgements; zero disables them."
  :type 'natnum :group 'write-or-die)

(defcustom write-or-die-prompt-for-next-action t
  "Whether a normal start asks for one tiny next writing action."
  :type 'boolean :group 'write-or-die)

(defcustom write-or-die-auto-stop-at-time nil
  "Whether reaching the time target stops the sprint.

Nil means the HUD switches to overtime rather than interrupting flow."
  :type 'boolean :group 'write-or-die)

(defcustom write-or-die-activity-kind 'insertion
  "Which edits restore momentum.

`insertion' counts insertions/replacements but not pure deletion.
`any-edit' counts every modification."
  :type '(choice (const insertion) (const any-edit))
  :group 'write-or-die)

(defcustom write-or-die-consequence 'rescue
  "Consequence after the grace period.

`rollback-session' restores the buffer snapshot from sprint start and stops
the sprint.  It is deliberately opt-in and remains undoable through normal
Emacs undo.

Choices are `rescue', `bell', `delete-word', `rollback-session', and `none'."
  :type '(choice (const rescue) (const bell) (const delete-word)
                 (const rollback-session) (const none))
  :group 'write-or-die)

(defcustom write-or-die-stop-policy 'confirm
  "How an unfinished sprint reacts to an explicit stop request.

`free' stops immediately.  `confirm' asks before abandoning an unfinished
sprint.  `commit' refuses an ordinary stop until the word or time target is
met.  A prefix argument to `write-or-die-stop' always overrides the policy,
so commitment mode can never trap the user."
  :type '(choice (const free) (const confirm) (const commit))
  :group 'write-or-die)

(defcustom write-or-die-draft-discipline 'free
  "Editing discipline during a sprint.

`free' leaves normal Emacs editing untouched.  `forward-only' permits
insertions at or beyond the session frontier but blocks deletion, replacement,
and edits behind that frontier.  This is an opt-in drafting constraint inspired
by forward-only/Hemingway writing modes."
  :type '(choice (const free) (const forward-only))
  :group 'write-or-die)

(defcustom write-or-die-typewriter-on-start nil
  "Whether new sprints keep the current line vertically centered."
  :type 'boolean :group 'write-or-die)

(defcustom write-or-die-rescue-prompts
  '("Write the deliberately rough version. Editing is a later job."
    "State the point in plain language, as if explaining it to a colleague."
    "Write one sentence beginning with: The point is..."
    "Skip the missing detail: insert a TODO placeholder and continue."
    "Write the next fact, claim, example, or transition -- only one."
    "Describe what you are trying to say before trying to say it elegantly."
    "If this paragraph is stuck, write the sentence that should come after it."
    "Turn the paragraph into one bullet point, then expand it."
    "Reduce the scope: what is the smallest useful sentence you can add now?")
  "Prompts cycled by `write-or-die-rescue'."
  :type '(repeat string) :group 'write-or-die)

;;;; Profiles and gamification

(defcustom write-or-die-profiles
  '((gentle :words 200 :time 1500 :warning 30 :grace 75 :consequence rescue
            :stop-policy free :discipline free)
    (standard :words 250 :time 1200 :warning 20 :grace 45 :consequence rescue
              :stop-policy confirm :discipline free)
    (flow :words 300 :time 1200 :warning 15 :grace 35 :consequence rescue
          :stop-policy confirm :discipline free :typewriter t)
    (pressure :words 350 :time 900 :warning 10 :grace 25 :consequence bell
              :stop-policy commit :discipline forward-only)
    (hardcore :words 400 :time 900 :warning 7 :grace 15
              :consequence rollback-session :stop-policy commit
              :discipline forward-only :typewriter t))
  "Named session profiles.

Recognized plist keys: `:words', `:time', `:warning', `:grace',
`:consequence', `:wpm', `:stop-policy', `:discipline', and `:typewriter'."
  :type 'sexp :group 'write-or-die)

(defcustom write-or-die-gamification t
  "Whether launch, flow-chain, rank, and comeback mechanics are enabled."
  :type 'boolean :group 'write-or-die)

(defcustom write-or-die-launch-words 25
  "High-watermark words required for the initial launch quest."
  :type 'natnum :group 'write-or-die)

(defcustom write-or-die-chain-words 25
  "High-watermark words required for each flow-chain step."
  :type 'natnum :group 'write-or-die)

(defcustom write-or-die-recovery-words 20
  "New high-watermark words required for a comeback."
  :type 'natnum :group 'write-or-die)

(defconst write-or-die--ranks
  '((0.00 . "Spark") (0.25 . "Stride") (0.50 . "Flow")
    (0.75 . "Surge") (1.00 . "Breakthrough"))
  "Rank labels keyed by word-target completion fraction.")

(defcustom write-or-die-target-wpm 0
  "Optional WPM target used only for feedback; zero disables it."
  :type 'natnum :group 'write-or-die)

(defcustom write-or-die-wpm-warmup 60
  "Seconds before WPM feedback affects momentum."
  :type 'natnum :group 'write-or-die)

;;;; Focus and history

(defcustom write-or-die-focus-on-start nil
  "Whether paragraph focus starts automatically with a sprint."
  :type 'boolean :group 'write-or-die)

(defcustom write-or-die-record-history t
  "Whether private metric-only history is persisted."
  :type 'boolean :group 'write-or-die)

(defcustom write-or-die-history-file
  (locate-user-emacs-file "write-or-die-history.eld")
  "File used for metric-only history.

Document text and implementation plans are never stored."
  :type 'file :group 'write-or-die)

(defcustom write-or-die-history-limit 500
  "Maximum number of history entries to retain."
  :type 'natnum :group 'write-or-die)

(defcustom write-or-die-show-up-words 25
  "Minimum words for a session to count toward the show-up streak."
  :type 'natnum :group 'write-or-die)

;;;; Adaptive visual design

(defcustom write-or-die-visual-style 'auto
  "HUD density.

`auto' chooses `full', `compact', or `minimal' from window width."
  :type '(choice (const auto) (const full) (const compact) (const minimal))
  :group 'write-or-die)

(defcustom write-or-die-mode-line-location 'global-mode-string
  "Where to publish the HUD.

`minor-mode' uses a traditional minor-mode lighter, which is useful for custom
modelines that intentionally omit `global-mode-string'.  Any other value uses
the standard `global-mode-string' integration point."
  :type '(choice (const global-mode-string) (const minor-mode)
                 (const :tag "Obsolete synonym for global-mode-string" auto))
  :group 'write-or-die)

(defcustom write-or-die-symbol-style 'auto
  "HUD glyph style.

`auto' prefers Nerd Icons when the optional `nerd-icons' package and its font
are available, then restrained Unicode, then ASCII.  `nerd-icons' requests
Nerd Icons explicitly but still falls back safely."
  :type '(choice (const auto) (const nerd-icons) (const unicode) (const ascii))
  :group 'write-or-die)

;;;; Optional sound design

(defcustom write-or-die-sound-backend 'auto
  "Auditory feedback backend.

`auto' tries the bundled WAV cue and falls back to the Emacs bell for important
warning-like events if audio playback is unavailable.  `file' tries only WAV
playback, `bell' uses `ding', and `none' disables all Write-or-Die sounds."
  :type '(choice (const auto) (const file) (const bell) (const none))
  :group 'write-or-die)

(defcustom write-or-die-sound-events
  '(start launch chain milestone warning rescue comeback target pause resume stop)
  "Events allowed to produce auditory feedback."
  :type '(set (const start) (const launch) (const chain) (const milestone)
              (const warning) (const rescue) (const comeback) (const target)
              (const pause) (const resume) (const stop))
  :group 'write-or-die)

(defcustom write-or-die-sound-volume 0.28
  "Volume passed to `play-sound-file', from 0.0 to 1.0."
  :type 'number :group 'write-or-die)

(defcustom write-or-die-sound-min-gap 0.30
  "Minimum seconds between Write-or-Die sound cues.

This coalesces events such as a flow-chain advance and a word milestone that
happen on the same edit."
  :type 'number :group 'write-or-die)

(defcustom write-or-die-sound-directory nil
  "Optional directory containing replacement Write-or-Die WAV files.

Nil uses the package's bundled `sounds' directory.  Files are named after
events, for example `start.wav', `warning.wav', and `comeback.wav'."
  :type '(choice (const :tag "Bundled sounds" nil) directory)
  :group 'write-or-die)

(defcustom write-or-die-progress-bar-width 6
  "Cells used by the full word-progress bar."
  :type 'natnum :group 'write-or-die)

(defcustom write-or-die-visual-full-min-width 110
  "Minimum width for the adaptive full HUD."
  :type 'natnum :group 'write-or-die)

(defcustom write-or-die-visual-compact-min-width 72
  "Minimum width for the adaptive compact HUD."
  :type 'natnum :group 'write-or-die)

(defcustom write-or-die-inactive-window-display 'dim
  "How the HUD appears in inactive windows: `dim', `same', or `hide'."
  :type '(choice (const dim) (const same) (const hide))
  :group 'write-or-die)

(defcustom write-or-die-show-when-stopped nil
  "Whether a quiet indicator remains when no sprint is active."
  :type 'boolean :group 'write-or-die)

(defcustom write-or-die-mode-line-label "WOD"
  "Short HUD label."
  :type 'string :group 'write-or-die)

;; Inheritance only: the current theme owns actual colors, backgrounds, font,
;; weight, contrast, and box styling.
(defface write-or-die-writing-face
  '((t :inherit mode-line-emphasis))
  "Face for healthy momentum." :group 'write-or-die)

(defface write-or-die-warning-face
  '((t :inherit warning))
  "Face for warning state." :group 'write-or-die)

(defface write-or-die-rescue-face
  '((t :inherit error))
  "Face for rescue state." :group 'write-or-die)

(defface write-or-die-paused-face
  '((t :inherit shadow))
  "Face for paused state." :group 'write-or-die)

(defface write-or-die-muted-face
  '((t :inherit shadow))
  "Face for secondary HUD information." :group 'write-or-die)

(defface write-or-die-focus-dim-face
  '((t :inherit shadow))
  "Face used outside the focused paragraph." :group 'write-or-die)

(defvar-keymap write-or-die-mode-map
  :doc "Keymap for `write-or-die-mode'."
  "C-c w s" #'write-or-die
  "C-c w g" #'write-or-die-start-profile
  "C-c w p" #'write-or-die-toggle-pause
  "C-c w r" #'write-or-die-rescue
  "C-c w t" #'write-or-die-insert-placeholder
  "C-c w i" #'write-or-die-plan
  "C-c w f" #'write-or-die-toggle-focus
  "C-c w h" #'write-or-die-stats
  "C-c w d" #'write-or-die-toggle-draft-discipline
  "C-c w c" #'write-or-die-toggle-typewriter)

;;;; Buffer-local state

(defvar-local write-or-die--status 'stopped)
(defvar-local write-or-die--phase 'writing)
(defvar-local write-or-die--timer nil)
(defvar-local write-or-die--start-time nil)
(defvar-local write-or-die--paused-at nil)
(defvar-local write-or-die--paused-seconds 0.0)
(defvar-local write-or-die--last-edit-time nil)
(defvar-local write-or-die--baseline-words 0)
(defvar-local write-or-die--current-words 0)
(defvar-local write-or-die--last-modified-tick nil)
(defvar-local write-or-die--next-milestone nil)
(defvar-local write-or-die--word-goal-announced nil)
(defvar-local write-or-die--warning-announced nil)
(defvar-local write-or-die--intervention-fired nil)
(defvar-local write-or-die--internal-change nil)
(defvar-local write-or-die--rescue-index -1)
(defvar-local write-or-die--next-action "")
(defvar-local write-or-die--obstacle "")
(defvar-local write-or-die--if-then-response "")
(defvar-local write-or-die--profile 'custom)
(defvar-local write-or-die--history-recorded nil)

;; Per-session copies keep profiles from mutating user customization.
(defvar-local write-or-die--session-target-words 250)
(defvar-local write-or-die--session-target-time 1200)
(defvar-local write-or-die--session-warning-period 20)
(defvar-local write-or-die--session-grace-period 45)
(defvar-local write-or-die--session-consequence 'rescue)
(defvar-local write-or-die--session-target-wpm 0)
(defvar-local write-or-die--session-stop-policy 'confirm)
(defvar-local write-or-die--session-discipline 'free)
(defvar-local write-or-die--session-typewriter nil)
(defvar-local write-or-die--baseline-text nil)
(defvar-local write-or-die--baseline-point nil)
(defvar-local write-or-die--baseline-modified-p nil)
(defvar-local write-or-die--draft-frontier nil)
(defvar-local write-or-die--typewriter-enabled nil)

;; Gamification.
(defvar-local write-or-die--high-watermark 0)
(defvar-local write-or-die--launch-announced nil)
(defvar-local write-or-die--current-chain 0)
(defvar-local write-or-die--best-chain 0)
(defvar-local write-or-die--next-chain-at nil)
(defvar-local write-or-die--recovery-target nil)
(defvar-local write-or-die--rescue-count 0)
(defvar-local write-or-die--comeback-count 0)

;; Paragraph focus.
(defvar-local write-or-die--focus-enabled nil)
(defvar-local write-or-die--focus-before nil)
(defvar-local write-or-die--focus-after nil)

;;;; Core helpers

(defun write-or-die--clamp (value low high)
  "Return VALUE constrained to the range LOW to HIGH."
  (max low (min high value)))

(defun write-or-die--cancel-timer ()
  "Cancel and clear the buffer-local sprint timer."
  (when (timerp write-or-die--timer)
    (cancel-timer write-or-die--timer))
  (setq write-or-die--timer nil))

(defun write-or-die--elapsed (&optional now)
  "Return active elapsed seconds, excluding pauses.

NOW defaults to the current time."
  (if (not write-or-die--start-time)
      0.0
    (let* ((now (or now (float-time)))
           (current-pause
            (if (and (eq write-or-die--status 'paused) write-or-die--paused-at)
                (- now write-or-die--paused-at)
              0.0)))
      (max 0.0 (- now write-or-die--start-time
                  write-or-die--paused-seconds current-pause)))))

(defun write-or-die--format-seconds (seconds)
  "Format SECONDS as a minutes:seconds duration string."
  (let* ((seconds (max 0 (truncate seconds)))
         (minutes (/ seconds 60)))
    (format "%d:%02d" minutes (% seconds 60))))

(defun write-or-die--time-label ()
  "Return remaining sprint time, or elapsed overtime past the target."
  (let ((elapsed (write-or-die--elapsed))
        (target write-or-die--session-target-time))
    (cond
     ((<= target 0) (write-or-die--format-seconds elapsed))
     ((<= elapsed target) (write-or-die--format-seconds (- target elapsed)))
     (t (concat "+" (write-or-die--format-seconds (- elapsed target)))))))

(defun write-or-die--net-words ()
  "Return the number of words written since the sprint baseline."
  (- write-or-die--current-words write-or-die--baseline-words))

(defun write-or-die--refresh-word-count ()
  "Recount buffer words when the buffer changed since the last count."
  (let ((tick (buffer-chars-modified-tick)))
    (unless (equal tick write-or-die--last-modified-tick)
      (setq write-or-die--current-words (count-words (point-min) (point-max))
            write-or-die--last-modified-tick tick))))

(defun write-or-die--wpm ()
  "Return words per minute across the active sprint time."
  (let ((elapsed (write-or-die--elapsed)))
    (if (<= elapsed 0) 0.0
      (/ (* 60.0 (max 0 write-or-die--high-watermark)) elapsed))))

(defun write-or-die--wpm-pressure-p ()
  "Return non-nil when pace has fallen below the session WPM target."
  (and (> write-or-die--session-target-wpm 0)
       (>= (write-or-die--elapsed) write-or-die-wpm-warmup)
       (< (write-or-die--wpm) write-or-die--session-target-wpm)))

(defun write-or-die--momentum ()
  "Return 0--100 momentum from inactivity and optional pace feedback."
  (if (not (eq write-or-die--status 'running))
      0
    (let* ((now (float-time))
           (idle (- now (or write-or-die--last-edit-time now)))
           (grace (max 1.0 write-or-die--session-grace-period))
           (idle-score (* 100.0 (- 1.0
                                   (write-or-die--clamp (/ idle grace) 0.0 1.0))))
           (pace-score
            (if (write-or-die--wpm-pressure-p)
                (* 100.0
                   (write-or-die--clamp
                    (/ (write-or-die--wpm)
                       (float write-or-die--session-target-wpm))
                    0.0 1.0))
              100.0)))
      (round (min idle-score pace-score)))))

(defun write-or-die--progress-ratio ()
  "Return word-target completion as a ratio from 0.0 to 1.0."
  (if (<= write-or-die--session-target-words 0)
      0.0
    (write-or-die--clamp
     (/ (float (max 0 write-or-die--high-watermark))
        write-or-die--session-target-words)
     0.0 1.0)))

(defun write-or-die--rank ()
  "Return the rank label matching current word-target progress."
  (let ((ratio (write-or-die--progress-ratio)) (rank ""))
    (dolist (entry write-or-die--ranks rank)
      (when (>= ratio (car entry)) (setq rank (cdr entry))))))

;;;; Adaptive HUD

(defvar write-or-die--nerd-icons-cache 'unknown)
(defvar-local write-or-die--last-sound-time 0.0)

(defun write-or-die--nerd-icons-p ()
  "Return non-nil when optional Nerd Icons appear displayable.

This intentionally works for both GUI and terminal frames: nerd-icons itself
supports both when the corresponding GUI or terminal font is configured."
  (when (eq write-or-die--nerd-icons-cache 'unknown)
    (setq write-or-die--nerd-icons-cache
          (condition-case nil
              (and (require 'nerd-icons nil t)
                   (fboundp 'nerd-icons-faicon)
                   (let* ((sample (nerd-icons-faicon "nf-fa-pencil"))
                          (char (and (stringp sample)
                                     (> (length sample) 0)
                                     (aref sample 0))))
                     (and char (char-displayable-p char))))
            (error nil))))
  (eq write-or-die--nerd-icons-cache t))

(defun write-or-die-refresh-icons ()
  "Re-detect optional Nerd Icons after installing package or font."
  (interactive)
  (setq write-or-die--nerd-icons-cache 'unknown)
  (force-mode-line-update t)
  (message "Write-or-die: Nerd Icons %s."
           (if (write-or-die--nerd-icons-p) "available" "not available")))

(defun write-or-die--nerd-icon (name fallback)
  "Return Font Awesome Nerd Icon NAME, or FALLBACK on any failure."
  (if (not (write-or-die--nerd-icons-p))
      fallback
    (condition-case nil
        (nerd-icons-faicon name)
      (error fallback))))

(defun write-or-die--resolved-symbol-style ()
  "Return the glyph style to use, resolving `auto' against what is displayable."
  (pcase write-or-die-symbol-style
    ('ascii 'ascii)
    ('unicode 'unicode)
    ('nerd-icons (if (write-or-die--nerd-icons-p) 'nerd-icons
                   (if (char-displayable-p ?●) 'unicode 'ascii)))
    (_ (cond
        ((write-or-die--nerd-icons-p) 'nerd-icons)
        ((and (char-displayable-p ?●)
              (char-displayable-p ?○)
              (char-displayable-p ?·)) 'unicode)
        (t 'ascii)))))

(defun write-or-die--unicode-p ()
  "Return non-nil when the resolved HUD style can display Unicode."
  (memq (write-or-die--resolved-symbol-style) '(nerd-icons unicode)))

(defun write-or-die--glyph (unicode ascii)
  "Return UNICODE when the resolved style allows it, otherwise ASCII."
  (if (write-or-die--unicode-p) unicode ascii))

(defconst write-or-die--state-table
  ;; key      nerd icon          unicode ascii  face
  '((paused  "nf-fa-pause"     "Ⅱ" "||" write-or-die-paused-face)
    (warning "nf-fa-warning"   "▲" "!"  write-or-die-warning-face)
    (rescue  "nf-fa-life_ring" "◆" "#"  write-or-die-rescue-face)
    (writing "nf-fa-pencil"    "●" "*"  write-or-die-writing-face)
    (stopped "nf-fa-circle_o"  "○" "o"  write-or-die-muted-face))
  "HUD icon, glyphs, and face per state key.")

(defun write-or-die--state-entry ()
  "Return the `write-or-die--state-table' row for the current state."
  (assq (pcase write-or-die--status
          ('paused 'paused)
          ('running (write-or-die--visual-phase))
          (_ 'stopped))
        write-or-die--state-table))

(defun write-or-die--state-icon ()
  "Return the best available state icon, with non-icon fallbacks."
  (pcase-let ((`(,_ ,icon ,unicode ,ascii ,_) (write-or-die--state-entry)))
    (if (eq (write-or-die--resolved-symbol-style) 'nerd-icons)
        (write-or-die--nerd-icon icon (write-or-die--glyph unicode ascii))
      (write-or-die--glyph unicode ascii))))

(defun write-or-die--objective-icon (kind unicode ascii)
  "Return a Nerd Icon for objective KIND, otherwise UNICODE or ASCII."
  (let ((fallback (write-or-die--glyph unicode ascii)))
    (if (not (eq (write-or-die--resolved-symbol-style) 'nerd-icons))
        fallback
      (write-or-die--nerd-icon
       (pcase kind
         ('recovery "nf-fa-refresh")
         ('launch "nf-fa-rocket")
         ('chain "nf-fa-fire")
         (_ "nf-fa-circle"))
       fallback))))

(defun write-or-die--visual-phase ()
  "Return the phase the HUD should show: `writing', `warning', or `rescue'."
  (cond
   ((eq write-or-die--phase 'rescue) 'rescue)
   ((eq write-or-die--phase 'warning) 'warning)
   ((write-or-die--wpm-pressure-p) 'warning)
   (t 'writing)))

(defun write-or-die--state-face ()
  "Return the HUD face for the current sprint status and phase."
  (nth 4 (write-or-die--state-entry)))

(defun write-or-die--window-width ()
  "Return the body width of the window displaying the current buffer."
  (let ((window (get-buffer-window (current-buffer) t)))
    (if (window-live-p window) (window-body-width window) (frame-width))))

(defun write-or-die--resolved-visual-style ()
  "Return the HUD density, resolving `auto' from the window width."
  (if (not (eq write-or-die-visual-style 'auto))
      write-or-die-visual-style
    (let ((width (write-or-die--window-width)))
      (cond
       ((>= width write-or-die-visual-full-min-width) 'full)
       ((>= width write-or-die-visual-compact-min-width) 'compact)
       (t 'minimal)))))

(defun write-or-die--progress-bar ()
  "Return a theme-native word progress bar."
  (if (or (<= write-or-die-progress-bar-width 0)
          (<= write-or-die--session-target-words 0))
      ""
    (let* ((width write-or-die-progress-bar-width)
           (filled (round (* width (write-or-die--progress-ratio))))
           (empty (- width filled))
           (full-char (if (write-or-die--unicode-p) ?● ?#))
           (empty-char (if (write-or-die--unicode-p) ?· ?-)))
      (concat
       (propertize (make-string filled full-char)
                   'face (write-or-die--state-face))
       (propertize (make-string empty empty-char)
                   'face 'write-or-die-muted-face)))))

(defun write-or-die--objective-label ()
  "Return the active micro-objective in a compact form."
  (when write-or-die-gamification
    (cond
     (write-or-die--recovery-target
      (format "%s%d"
              (write-or-die--objective-icon 'recovery "↻" "R")
              (max 0 (- write-or-die--recovery-target
                        write-or-die--high-watermark))))
     ((and (not write-or-die--launch-announced)
           (> write-or-die-launch-words 0))
      (format "%s%d"
              (write-or-die--objective-icon 'launch "→" ">")
              (max 0 (- write-or-die-launch-words
                        write-or-die--high-watermark))))
     ((> write-or-die--current-chain 0)
      (format "%s%d"
              (write-or-die--objective-icon 'chain "×" "x")
              write-or-die--current-chain)))))

(defun write-or-die--words-label (&optional minimal)
  "Return the HUD word count; MINIMAL omits the session target."
  (let ((words (max 0 (write-or-die--net-words))))
    (if (or minimal (<= write-or-die--session-target-words 0))
        (format "%dw" words)
      (format "%d/%dw" words write-or-die--session-target-words))))

(defun write-or-die--plan-summary ()
  "Return the session plan as one sentence, or an empty string."
  (cond
   ((and (not (string-empty-p write-or-die--obstacle))
         (not (string-empty-p write-or-die--if-then-response)))
    (format "If %s, then %s." write-or-die--obstacle
            write-or-die--if-then-response))
   ((not (string-empty-p write-or-die--next-action))
    (format "Next: %s." write-or-die--next-action))
   (t "")))

(defun write-or-die--mode-line-help ()
  "Return the multi-line tooltip shown when hovering the HUD."
  (let ((objective (write-or-die--objective-label))
        (plan (write-or-die--plan-summary)))
    (string-join
     (delq nil
           (list
            (format "Write or Die — %s"
                    (capitalize (symbol-name write-or-die--status)))
            (when (eq write-or-die--status 'running)
              (format "%d net words · momentum %d · %.1f WPM · rank %s"
                      (max 0 (write-or-die--net-words))
                      (write-or-die--momentum)
                      (write-or-die--wpm)
                      (write-or-die--rank)))
            (when objective (format "Objective: %s" objective))
            (when (memq write-or-die--status '(running paused))
              (format "Discipline: %s · stop: %s%s"
                      (symbol-name write-or-die--session-discipline)
                      (symbol-name write-or-die--session-stop-policy)
                      (if write-or-die--typewriter-enabled " · typewriter" "")))
            (unless (string-empty-p plan) plan)
            "mouse-1 pause/resume · mouse-2 rescue · mouse-3 stop"))
     "\n")))

(defvar write-or-die--mode-line-map)

(defun write-or-die--decorate-hud (string)
  "Return STRING with the HUD tooltip, mouse face, and keymap applied."
  (propertize string
              'help-echo (write-or-die--mode-line-help)
              'mouse-face 'mode-line-highlight
              'keymap write-or-die--mode-line-map))

(defun write-or-die--hud-active ()
  "Return the HUD as displayed in the selected window."
  (let* ((style (write-or-die--resolved-visual-style))
         (state (propertize (write-or-die--state-icon)
                            'face (write-or-die--state-face)))
         (label (propertize write-or-die-mode-line-label
                            'face 'mode-line-emphasis))
         (sep (propertize (write-or-die--glyph "·" "|")
                          'face 'write-or-die-muted-face))
         (words (write-or-die--words-label (eq style 'minimal)))
         (time (write-or-die--time-label))
         (momentum (propertize (format "M%d" (write-or-die--momentum))
                               'face (write-or-die--state-face)))
         (objective (write-or-die--objective-label))
         (bar (write-or-die--progress-bar)))
    (pcase style
      ('minimal
       (format " %s %s %s " state words time))
      (_
       (concat
        " "
        (string-join
         (delq nil (list label state
                         (and (eq style 'full) (not (string-empty-p bar)) bar)
                         words sep momentum
                         (and objective sep) objective sep time))
         " ")
        " ")))))

(defun write-or-die--hud-inactive ()
  "Return the quieter HUD used in unselected windows."
  (pcase write-or-die-inactive-window-display
    ('hide "")
    ('same (write-or-die--hud-active))
    (_ (propertize
        (format " %s %s "
                (write-or-die--state-icon)
                (write-or-die--words-label t))
        'face 'write-or-die-muted-face))))

(defun write-or-die--mode-line ()
  "Return the adaptive Write-or-Die HUD."
  (cond
   ((and (eq write-or-die--status 'stopped)
         (not write-or-die-show-when-stopped))
    "")
   ((not (mode-line-window-selected-p))
    (write-or-die--decorate-hud (write-or-die--hud-inactive)))
   ((eq write-or-die--status 'paused)
    (write-or-die--decorate-hud
     (if (eq (write-or-die--resolved-visual-style) 'minimal)
         (propertize
          (format " %s %s "
                  (write-or-die--state-icon)
                  (write-or-die--words-label t))
          'face 'write-or-die-paused-face)
       (concat
        " " (propertize write-or-die-mode-line-label 'face 'mode-line-emphasis)
        " " (propertize (write-or-die--state-icon)
                        'face 'write-or-die-paused-face)
        " " (write-or-die--words-label t)
        " " (propertize "PAUSED" 'face 'write-or-die-paused-face) " "))))
   (t (write-or-die--decorate-hud (write-or-die--hud-active)))))

(defvar write-or-die--mode-line-map
  (let ((map (make-sparse-keymap)))
    (dolist (button '(mouse-1 mouse-2 mouse-3))
      (define-key map (vector 'mode-line button)
                  #'write-or-die--mode-line-click))
    map))

(defun write-or-die--event-window (event)
  "Return the live window that mouse EVENT occurred in, or nil."
  (let ((window (posn-window (event-start event))))
    (and (windowp window) (window-live-p window) window)))

(defun write-or-die--mode-line-click (event)
  "Act on mouse EVENT in the HUD.
Button 1 toggles pause or starts a sprint, button 2 shows a rescue prompt,
and button 3 stops an active sprint."
  (interactive "e")
  (let ((window (write-or-die--event-window event)))
    (when window
      (with-selected-window window
        (let ((active (memq write-or-die--status '(running paused))))
          (pcase (event-basic-type event)
            ('mouse-1 (if active (write-or-die-toggle-pause) (write-or-die-start)))
            ('mouse-2 (write-or-die-rescue))
            ('mouse-3 (when active (write-or-die-stop)))))))))

(defconst write-or-die--global-mode-line-entry
  '(:eval (write-or-die--mode-line-eval 'global-mode-string)))

(defvar write-or-die-mode)

(defun write-or-die--append-mode-line-entry (value entry)
  "Return mode-line construct VALUE with ENTRY appended once."
  (cond
   ((listp value)
    (if (member entry value) value (append value (list entry))))
   (t (list value entry))))

(defun write-or-die--ensure-global-mode-line-entry ()
  "Install the global HUD integration point once."
  (set-default
   'global-mode-string
   (write-or-die--append-mode-line-entry
    (default-value 'global-mode-string)
    write-or-die--global-mode-line-entry))
  (when (local-variable-p 'global-mode-string)
    (setq-local global-mode-string
                (write-or-die--append-mode-line-entry
                 global-mode-string write-or-die--global-mode-line-entry))))

(defun write-or-die--mode-line-eval (location)
  "Return the HUD when LOCATION is the configured publication point.
Any `write-or-die-mode-line-location' other than `minor-mode' publishes
through `global-mode-string'."
  (when (and write-or-die-mode
             (eq location (if (eq write-or-die-mode-line-location 'minor-mode)
                              'minor-mode
                            'global-mode-string)))
    (write-or-die--mode-line)))

;;;; Rescue and game loop

(defun write-or-die--next-rescue-prompt ()
  "Return the next prompt from `write-or-die-rescue-prompts', cycling."
  (if (null write-or-die-rescue-prompts)
      "Write one imperfect sentence."
    (setq write-or-die--rescue-index
          (% (1+ write-or-die--rescue-index)
             (length write-or-die-rescue-prompts)))
    (nth write-or-die--rescue-index write-or-die-rescue-prompts)))

(defun write-or-die--begin-recovery ()
  "Count a stall intervention and open a comeback quest when appropriate."
  (when (eq write-or-die--status 'running)
    ;; Count the intervention independently of whether decorative game mechanics
    ;; are enabled; history should remain meaningful in a minimalist setup.
    (when (or (not write-or-die-gamification)
              (null write-or-die--recovery-target))
      (incf write-or-die--rescue-count))
    (when (and write-or-die-gamification
               (null write-or-die--recovery-target))
      (setq write-or-die--current-chain 0)
      (when (> write-or-die-recovery-words 0)
        (setq write-or-die--recovery-target
              (+ write-or-die--high-watermark write-or-die-recovery-words))))))

(defun write-or-die--sound-file (event)
  "Return the configured WAV file for EVENT."
  (expand-file-name
   (format "%s.wav" (symbol-name event))
   (or write-or-die-sound-directory
       (expand-file-name "sounds" write-or-die--package-directory))))

(defun write-or-die--play-file-sound (event)
  "Try to play EVENT through a WAV file; return non-nil on success."
  (let ((file (write-or-die--sound-file event)))
    (when (and (file-readable-p file) (fboundp 'play-sound-file))
      (condition-case nil
          (progn
            (play-sound-file file (write-or-die--clamp write-or-die-sound-volume 0.0 1.0))
            t)
        (error nil)))))

(defun write-or-die--sound (event &optional force)
  "Play auditory feedback for EVENT when enabled.

Unless FORCE is non-nil, suppress closely adjacent cues according to
`write-or-die-sound-min-gap'."
  (when (and (memq event write-or-die-sound-events)
             (not (eq write-or-die-sound-backend 'none)))
    (let ((now (float-time)))
      (when (or force
                (>= (- now write-or-die--last-sound-time)
                    (max 0.0 write-or-die-sound-min-gap)))
        (let ((played
               (pcase write-or-die-sound-backend
                 ('bell (ding) t)
                 ('file (write-or-die--play-file-sound event))
                 (_ (write-or-die--play-file-sound event)))))
          (when (and (not played)
                     (eq write-or-die-sound-backend 'auto)
                     (memq event '(warning rescue target comeback)))
            (ding)
            (setq played t))
          (when played
            (setq write-or-die--last-sound-time now)))))))

;;;###autoload
(defun write-or-die-test-sound (&optional event)
  "Play EVENT for testing the current sound configuration."
  (interactive)
  (let ((event (or event
                   (intern
                    (completing-read
                     "Write-or-die sound: "
                     (mapcar #'symbol-name write-or-die-sound-events)
                     nil t nil nil "start")))))
    ;; Test cues should not be swallowed by the normal coalescing window.
    (write-or-die--sound event t)))

;;;###autoload
(defun write-or-die-rescue (&optional suppress-sound)
  "Show an unblock prompt and start a recovery quest when appropriate.

When SUPPRESS-SOUND is non-nil, do not play the rescue cue."
  (interactive)
  (write-or-die--begin-recovery)
  (let* ((prompt (write-or-die--next-rescue-prompt))
         (plan (write-or-die--plan-summary))
         (recovery
          (when write-or-die--recovery-target
            (format " Recovery: %d new words."
                    (max 0 (- write-or-die--recovery-target
                              write-or-die--high-watermark))))))
    (message "Write-or-die: %s%s%s%s"
             prompt
             (if (string-empty-p plan) "" "  ")
             plan
             (or recovery "")))
  (unless suppress-sound (write-or-die--sound 'rescue))
  (force-mode-line-update t))

(defun write-or-die--delete-word-before-point ()
  "Delete the word before point as an internal, undoable change."
  (when (and (not buffer-read-only) (> (point) (point-min)))
    (let ((write-or-die--internal-change t))
      (save-excursion
        (skip-syntax-backward " ")
        (let ((end (point)))
          (condition-case nil
              (progn (backward-word 1) (delete-region (point) end))
            (beginning-of-buffer nil)))))))

(defun write-or-die--rollback-session ()
  "Restore the buffer snapshot captured at sprint start, then stop.

The rollback is performed as one atomic Emacs change, so normal undo can
recover it.  This never restores from disk or touches text from another buffer."
  (unless (stringp write-or-die--baseline-text)
    (user-error "No write-or-die sprint snapshot is available"))
  (let ((write-or-die--internal-change t)
        (inhibit-read-only t)
        (target (or write-or-die--baseline-point 1)))
    (atomic-change-group
      (erase-buffer)
      (insert write-or-die--baseline-text)
      (goto-char (min (point-max) (max (point-min) target))))
    (set-buffer-modified-p write-or-die--baseline-modified-p))
  (write-or-die-stop t t)
  (message "Write-or-die: sprint rolled back. Undo is still available."))

(defun write-or-die--run-consequence ()
  "Run the consequence configured for this session's sustained stall."
  (pcase write-or-die--session-consequence
    ('rescue (write-or-die-rescue))
    ('bell (ding) (write-or-die-rescue t))
    ('delete-word (write-or-die--delete-word-before-point)
                  (write-or-die-rescue))
    ('rollback-session (write-or-die--rollback-session))
    ('none nil)))

(defun write-or-die--update-game-progress ()
  "Update high-watermark plus optional launch/chain/comeback mechanics."
  (let ((net (max 0 (write-or-die--net-words))))
    ;; Pace/history use this even when decorative gamification is disabled.
    (when (> net write-or-die--high-watermark)
      (setq write-or-die--high-watermark net))
    (when write-or-die-gamification
      (let ((old-chain write-or-die--current-chain)
            sound-event
            messages)
        (when (and (not write-or-die--launch-announced)
                   (> write-or-die-launch-words 0)
                   (>= write-or-die--high-watermark write-or-die-launch-words))
          (setq write-or-die--launch-announced t)
          (push "launch complete" messages)
          (setq sound-event 'launch))
        (when (and (> write-or-die-chain-words 0)
                   write-or-die--next-chain-at)
          (while (>= write-or-die--high-watermark write-or-die--next-chain-at)
            (incf write-or-die--current-chain)
            (setq write-or-die--best-chain
                  (max write-or-die--best-chain write-or-die--current-chain))
            (incf write-or-die--next-chain-at write-or-die-chain-words))
          (when (> write-or-die--current-chain old-chain)
            (push (format "flow x%d" write-or-die--current-chain) messages)
            (unless sound-event (setq sound-event 'chain))))
        (when (and write-or-die--recovery-target
                   (>= write-or-die--high-watermark
                       write-or-die--recovery-target))
          (setq write-or-die--recovery-target nil)
          (incf write-or-die--comeback-count)
          (push "COMEBACK" messages)
          (setq sound-event 'comeback))
        (when messages
          (message "Write-or-die: %s."
                   (string-join (nreverse messages) " · "))
          (when sound-event (write-or-die--sound sound-event)))))))

(defun write-or-die--acknowledge-milestones ()
  "Announce word milestones and the word target as they are reached."
  (let ((net (max 0 (write-or-die--net-words))))
    (when (and (> write-or-die-milestone-words 0)
               write-or-die--next-milestone
               (>= net write-or-die--next-milestone))
      (message "Write-or-die: %d net words. Keep the draft rough."
               write-or-die--next-milestone)
      (write-or-die--sound 'milestone)
      (while (<= write-or-die--next-milestone net)
        (incf write-or-die--next-milestone
              write-or-die-milestone-words)))
    (when (and (not write-or-die--word-goal-announced)
               (> write-or-die--session-target-words 0)
               (>= net write-or-die--session-target-words))
      (setq write-or-die--word-goal-announced t)
      (message "Write-or-die: word target reached. Keep going while flow is useful.")
      (write-or-die--sound 'target))))

(defun write-or-die--before-change (beg end)
  "Enforce the session's optional forward-only drafting discipline.

BEG and END bound the change the buffer is about to make."
  (when (and (not write-or-die--internal-change)
             (eq write-or-die--status 'running)
             (eq write-or-die--session-discipline 'forward-only))
    (let ((frontier (and (markerp write-or-die--draft-frontier)
                         (marker-position write-or-die--draft-frontier))))
      (when (> end beg)
        (user-error "Forward-only sprint: deletion/replacement is disabled"))
      (when (and frontier (< beg frontier))
        (user-error "Forward-only sprint: continue from the drafting frontier")))))

(defun write-or-die--after-change (beg end _old-length)
  "Refresh sprint state after the buffer change between BEG and END."
  (unless write-or-die--internal-change
    (when (and (eq write-or-die--status 'running)
               (eq write-or-die--session-discipline 'forward-only)
               (markerp write-or-die--draft-frontier)
               (> end (marker-position write-or-die--draft-frontier)))
      (set-marker write-or-die--draft-frontier end))
    (write-or-die--refresh-word-count)
    (write-or-die--update-game-progress)
    (when (and (eq write-or-die--status 'running)
               (or (eq write-or-die-activity-kind 'any-edit) (> end beg)))
      (setq write-or-die--last-edit-time (float-time)
            write-or-die--phase 'writing
            write-or-die--warning-announced nil
            write-or-die--intervention-fired nil))
    (when write-or-die--focus-enabled
      (write-or-die--update-focus-overlays))
    (force-mode-line-update t)))

;;;; Drafting discipline and typewriter view

(defun write-or-die--typewriter-post-command ()
  "Keep point vertically centered while typewriter view is active."
  (when (and write-or-die--typewriter-enabled
             (eq write-or-die--status 'running)
             (eq (window-buffer (selected-window)) (current-buffer))
             (not (minibufferp)))
    (ignore-errors (recenter))))

(defun write-or-die--set-typewriter (enabled)
  "Set buffer-local typewriter view according to ENABLED."
  (setq write-or-die--typewriter-enabled enabled)
  (if enabled
      (add-hook 'post-command-hook #'write-or-die--typewriter-post-command nil t)
    (remove-hook 'post-command-hook #'write-or-die--typewriter-post-command t)))

;;;###autoload
(defun write-or-die-toggle-typewriter ()
  "Toggle vertically centered typewriter view in the current buffer."
  (interactive)
  (write-or-die--set-typewriter (not write-or-die--typewriter-enabled))
  (message "Write-or-die: typewriter view %s."
           (if write-or-die--typewriter-enabled "on" "off")))

;;;###autoload
(defun write-or-die-toggle-draft-discipline ()
  "Toggle free editing and forward-only drafting for the active sprint."
  (interactive)
  (unless (memq write-or-die--status '(running paused))
    (user-error "No active write-or-die sprint"))
  (setq write-or-die--session-discipline
        (if (eq write-or-die--session-discipline 'forward-only)
            'free 'forward-only))
  (when (eq write-or-die--session-discipline 'forward-only)
    (unless (markerp write-or-die--draft-frontier)
      (setq write-or-die--draft-frontier (copy-marker (point) t)))
    (set-marker write-or-die--draft-frontier (point)))
  (message "Write-or-die: drafting discipline %s."
           (symbol-name write-or-die--session-discipline)))

;;;; Paragraph focus

(defun write-or-die--paragraph-bounds ()
  "Return the bounds of the paragraph at point, or of its line."
  (or (bounds-of-thing-at-point 'paragraph)
      (cons (line-beginning-position) (line-end-position))))

(defun write-or-die--ensure-focus-overlays ()
  "Create the paragraph-focus overlays unless they already exist."
  (unless (overlayp write-or-die--focus-before)
    (setq write-or-die--focus-before
          (make-overlay (point-min) (point-min) nil t nil))
    (overlay-put write-or-die--focus-before 'face 'write-or-die-focus-dim-face)
    (overlay-put write-or-die--focus-before 'write-or-die t))
  (unless (overlayp write-or-die--focus-after)
    (setq write-or-die--focus-after
          (make-overlay (point-max) (point-max) nil nil t))
    (overlay-put write-or-die--focus-after 'face 'write-or-die-focus-dim-face)
    (overlay-put write-or-die--focus-after 'write-or-die t)))

(defun write-or-die--update-focus-overlays ()
  "Dim everything outside the paragraph at point."
  (when write-or-die--focus-enabled
    (write-or-die--ensure-focus-overlays)
    (pcase-let ((`(,start . ,end) (write-or-die--paragraph-bounds)))
      (move-overlay write-or-die--focus-before (point-min) start)
      (move-overlay write-or-die--focus-after end (point-max)))))

(defun write-or-die--disable-focus ()
  "Turn paragraph focus off and delete its overlays."
  (setq write-or-die--focus-enabled nil)
  (remove-hook 'post-command-hook #'write-or-die--update-focus-overlays t)
  (when (overlayp write-or-die--focus-before)
    (delete-overlay write-or-die--focus-before))
  (when (overlayp write-or-die--focus-after)
    (delete-overlay write-or-die--focus-after))
  (setq write-or-die--focus-before nil
        write-or-die--focus-after nil))

;;;###autoload
(defun write-or-die-toggle-focus ()
  "Toggle theme-native paragraph focus."
  (interactive)
  (if write-or-die--focus-enabled
      (progn (write-or-die--disable-focus)
             (message "Write-or-die: paragraph focus off."))
    (setq write-or-die--focus-enabled t)
    (add-hook 'post-command-hook #'write-or-die--update-focus-overlays nil t)
    (write-or-die--update-focus-overlays)
    (message "Write-or-die: paragraph focus on.")))

;;;; Timer and planning

(defun write-or-die--tick (buffer)
  "Advance the sprint clock for BUFFER and react to stalls."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (if (or (not write-or-die-mode)
              (eq write-or-die--status 'stopped))
          (write-or-die--cancel-timer)
        (let ((now (float-time)))
          (write-or-die--refresh-word-count)
          (write-or-die--update-game-progress)
          (write-or-die--acknowledge-milestones)
          (when (eq write-or-die--status 'running)
            (let ((idle (- now (or write-or-die--last-edit-time now))))
              (cond
               ((>= idle write-or-die--session-grace-period)
                (setq write-or-die--phase 'rescue)
                (unless write-or-die--intervention-fired
                  (setq write-or-die--intervention-fired t)
                  (write-or-die--run-consequence)))
               ((>= idle write-or-die--session-warning-period)
                (setq write-or-die--phase 'warning)
                (unless write-or-die--warning-announced
                  (setq write-or-die--warning-announced t)
                  (message "Write-or-die: one imperfect sentence is enough to restart momentum.")
                  (write-or-die--sound 'warning)))
               (t (setq write-or-die--phase 'writing))))
            (when (and write-or-die-auto-stop-at-time
                       (> write-or-die--session-target-time 0)
                       (>= (write-or-die--elapsed now)
                           write-or-die--session-target-time))
              (write-or-die-stop)))
          (force-mode-line-update t))))))

(defun write-or-die-plan ()
  "Set a tiny next action and optional if/then implementation intention."
  (interactive)
  (setq write-or-die--next-action
        (string-trim
         (read-string "Next tiny writing action: " write-or-die--next-action)))
  (setq write-or-die--obstacle
        (string-trim
         (read-string "Likely obstacle (optional): " write-or-die--obstacle)))
  (setq write-or-die--if-then-response
        (if (string-empty-p write-or-die--obstacle)
            ""
          (string-trim
           (read-string "If that happens, I will: "
                        write-or-die--if-then-response))))
  (message "Write-or-die plan: %s" (write-or-die--plan-summary))
  (force-mode-line-update t))

(defun write-or-die--profile-settings (profile)
  "Return the settings plist for PROFILE."
  (cdr (assq profile write-or-die-profiles)))

(defun write-or-die--prepare-session-settings (&optional profile)
  "Copy PROFILE settings, or the user defaults, into session-local variables."
  (let ((settings (write-or-die--profile-settings profile)))
    (setq write-or-die--profile (or profile 'custom)
          write-or-die--session-target-words
          (or (plist-get settings :words) write-or-die-target-words)
          write-or-die--session-target-time
          (or (plist-get settings :time) write-or-die-target-time)
          write-or-die--session-warning-period
          (or (plist-get settings :warning) write-or-die-warning-period)
          write-or-die--session-grace-period
          (or (plist-get settings :grace) write-or-die-grace-period)
          write-or-die--session-consequence
          (or (plist-get settings :consequence) write-or-die-consequence)
          write-or-die--session-target-wpm
          (or (plist-get settings :wpm) write-or-die-target-wpm)
          write-or-die--session-stop-policy
          (or (plist-get settings :stop-policy) write-or-die-stop-policy)
          write-or-die--session-discipline
          (or (plist-get settings :discipline) write-or-die-draft-discipline)
          write-or-die--session-typewriter
          (if (plist-member settings :typewriter)
              (plist-get settings :typewriter)
            write-or-die-typewriter-on-start))))

(defun write-or-die--validate-session-settings ()
  "Signal a `user-error' when the session settings are inconsistent."
  (when (< write-or-die--session-warning-period 0)
    (user-error "Warning period must be non-negative"))
  (when (< write-or-die--session-grace-period
           write-or-die--session-warning-period)
    (user-error "Grace period must be >= warning period"))
  (when (< write-or-die--session-target-time 0)
    (user-error "Target time must be non-negative"))
  (when (and (eq write-or-die--session-stop-policy 'commit)
             (<= write-or-die--session-target-time 0)
             (<= write-or-die--session-target-words 0))
    (user-error "Commit stop policy requires a word or time target")))

(defun write-or-die--start-session (&optional full-plan profile)
  "Start a sprint using PROFILE; FULL-PLAN also asks for an if/then plan."
  (unless write-or-die-mode (write-or-die-mode 1))
  ;; Finish the old sprint before installing the next profile's session-local
  ;; settings, otherwise the old history entry could inherit the new profile.
  (when (memq write-or-die--status '(running paused))
    (write-or-die-stop t))
  (write-or-die--prepare-session-settings profile)
  (write-or-die--validate-session-settings)
  (unless full-plan
    (setq write-or-die--next-action ""
          write-or-die--obstacle ""
          write-or-die--if-then-response ""))
  (cond
   (full-plan (write-or-die-plan))
   (write-or-die-prompt-for-next-action
    (setq write-or-die--next-action
          (string-trim (read-string "Next tiny writing action: ")))))
  (let ((now (float-time))
        (words (count-words (point-min) (point-max))))
    (setq write-or-die--status 'running
          write-or-die--phase 'writing
          write-or-die--start-time now
          write-or-die--paused-at nil
          write-or-die--paused-seconds 0.0
          write-or-die--last-edit-time now
          write-or-die--baseline-words words
          write-or-die--current-words words
          write-or-die--last-modified-tick (buffer-chars-modified-tick)
          write-or-die--next-milestone
          (and (> write-or-die-milestone-words 0)
               write-or-die-milestone-words)
          write-or-die--word-goal-announced nil
          write-or-die--warning-announced nil
          write-or-die--intervention-fired nil
          write-or-die--rescue-index -1
          write-or-die--history-recorded nil
          write-or-die--high-watermark 0
          write-or-die--launch-announced (<= write-or-die-launch-words 0)
          write-or-die--current-chain 0
          write-or-die--best-chain 0
          write-or-die--next-chain-at
          (and (> write-or-die-chain-words 0) write-or-die-chain-words)
          write-or-die--recovery-target nil
          write-or-die--rescue-count 0
          write-or-die--comeback-count 0
          write-or-die--baseline-text
          (when (eq write-or-die--session-consequence 'rollback-session)
            (buffer-substring-no-properties (point-min) (point-max)))
          write-or-die--baseline-point (point)
          write-or-die--baseline-modified-p (buffer-modified-p))
    (when (markerp write-or-die--draft-frontier)
      (set-marker write-or-die--draft-frontier nil))
    (setq write-or-die--draft-frontier
          (copy-marker (point) t))
    (write-or-die--set-typewriter write-or-die--session-typewriter)
    (write-or-die--cancel-timer)
    (setq write-or-die--timer
          (run-with-timer 0 1 #'write-or-die--tick (current-buffer))))
  (when (and write-or-die-focus-on-start
             (not write-or-die--focus-enabled))
    (write-or-die-toggle-focus))
  (message "Write-or-die: %s sprint started — %d words, %s.%s"
           (symbol-name write-or-die--profile)
           write-or-die--session-target-words
           (write-or-die--format-seconds write-or-die--session-target-time)
           (if (string-empty-p write-or-die--next-action)
               "" (format " Next: %s" write-or-die--next-action)))
  (write-or-die--sound 'start t)
  (force-mode-line-update t))

;;;###autoload
(defun write-or-die-start (&optional full-plan)
  "Start a writing sprint; FULL-PLAN asks for an if/then plan."
  (interactive "P")
  (write-or-die--start-session full-plan nil))

;;;###autoload
(defun write-or-die-start-profile (profile &optional full-plan)
  "Start a named PROFILE; FULL-PLAN also asks for an if/then plan."
  (interactive
   (list
    (intern
     (completing-read
      "Write-or-die profile: "
      (mapcar (lambda (entry) (symbol-name (car entry))) write-or-die-profiles)
      nil t nil nil "standard"))
    current-prefix-arg))
  (unless (assq profile write-or-die-profiles)
    (user-error "Unknown write-or-die profile: %s" profile))
  (write-or-die--start-session full-plan profile))

;;;; History and statistics

(defun write-or-die--read-history ()
  "Return saved history entries, or nil when none can be read."
  (if (not (file-readable-p write-or-die-history-file))
      nil
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents write-or-die-history-file)
          (goto-char (point-min))
          (let ((value (read (current-buffer))))
            (and (listp value) value)))
      (error nil))))

(defun write-or-die--write-history (history)
  "Write HISTORY to `write-or-die-history-file', readable only by its owner."
  (let ((dir (file-name-directory write-or-die-history-file)))
    (when dir (make-directory dir t)))
  (condition-case err
      (progn
        (with-temp-file write-or-die-history-file
          (let ((print-length nil) (print-level nil))
            (prin1 history (current-buffer))
            (insert "\n")))
        (set-file-modes write-or-die-history-file #o600))
    (error
     (message "Write-or-die: could not save history: %s"
              (error-message-string err)))))

(defun write-or-die--history-entry (elapsed)
  "Return a metric-only history entry for a sprint lasting ELAPSED seconds."
  (list :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z")
        :date (format-time-string "%Y-%m-%d")
        :profile write-or-die--profile
        :words (max 0 (write-or-die--net-words))
        :elapsed (max 0 (truncate elapsed))
        :wpm (round (write-or-die--wpm))
        :best-chain write-or-die--best-chain
        :rescues write-or-die--rescue-count
        :comebacks write-or-die--comeback-count))

(defun write-or-die--record-session (elapsed)
  "Record a sprint lasting ELAPSED seconds, at most once per sprint."
  (when (and write-or-die-record-history
             (not write-or-die--history-recorded))
    (setq write-or-die--history-recorded t)
    (let* ((history (write-or-die--read-history))
           (updated (cons (write-or-die--history-entry elapsed) history)))
      (when (> write-or-die-history-limit 0)
        (setq updated (take write-or-die-history-limit updated)))
      (write-or-die--write-history updated))))

(defun write-or-die--date-day-number (date)
  "Return the absolute day number for ISO DATE, or nil if unparsable."
  (when (stringp date)
    (ignore-errors (time-to-days (date-to-time date)))))

(defun write-or-die--show-up-streak (history)
  "Return a forgiving writing-day streak from HISTORY.

The streak may end today or yesterday, so one missed day does not reset it."
  (let* ((dates
          (delete-dups
           (delq nil
                 (mapcar
                  (lambda (entry)
                    (when (>= (or (plist-get entry :words) 0)
                              write-or-die-show-up-words)
                      (write-or-die--date-day-number (plist-get entry :date))))
                  history))))
         (days (sort dates #'>))
         (today (time-to-days (current-time))))
    (if (or (null days) (< (car days) (1- today)))
        0
      (let ((count 1)
            (expected (1- (car days))))
        (dolist (day (cdr days) count)
          (when (= day expected)
            (incf count)
            (decf expected)))))))

(defun write-or-die--history-values (history key)
  "Return KEY from each HISTORY entry, defaulting missing values to 0."
  (mapcar (lambda (entry) (or (plist-get entry key) 0)) history))

;;;###autoload
(defun write-or-die-stats ()
  "Show private metric-only writing statistics."
  (interactive)
  (let* ((history (write-or-die--read-history))
         (sessions (length history))
         (words (apply #'+ (write-or-die--history-values history :words)))
         (seconds (apply #'+ (write-or-die--history-values history :elapsed)))
         (best-chain (apply #'max 0 (write-or-die--history-values
                                     history :best-chain)))
         (comebacks (apply #'+ (write-or-die--history-values
                                history :comebacks)))
         (streak (write-or-die--show-up-streak history))
         (buffer (get-buffer-create "*Write-or-Die Stats*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize "Write or Die\n" 'face 'bold))
        (insert (format "\nSessions       %d\n" sessions))
        (insert (format "Lifetime words %d\n" words))
        (insert (format "Writing time   %s\n" (write-or-die--format-seconds seconds)))
        (insert (format "Best flow      x%d\n" best-chain))
        (insert (format "Comebacks      %d\n" comebacks))
        (insert (format "Show-up streak %d day%s\n"
                        streak (if (= streak 1) "" "s")))
        (insert "\nRecent sessions\n\n")
        (dolist (entry (take 10 history))
          (let ((profile (plist-get entry :profile)))
            (insert
             (format "%s  %-9s  %4dw  %6s  %3d WPM  x%d  %d comeback%s\n"
                     (or (plist-get entry :date) "")
                     (if (symbolp profile) (symbol-name profile) (format "%s" profile))
                     (or (plist-get entry :words) 0)
                     (write-or-die--format-seconds (or (plist-get entry :elapsed) 0))
                     (or (plist-get entry :wpm) 0)
                     (or (plist-get entry :best-chain) 0)
                     (or (plist-get entry :comebacks) 0)
                     (if (= (or (plist-get entry :comebacks) 0) 1) "" "s")))))
        (special-mode)))
    (pop-to-buffer buffer)))

;;;; Lifecycle

(defun write-or-die--target-met-p ()
  "Return non-nil when the current sprint has met a time or word target."
  (or (and (> write-or-die--session-target-words 0)
           (>= (max 0 (write-or-die--net-words))
               write-or-die--session-target-words))
      (and (> write-or-die--session-target-time 0)
           (>= (write-or-die--elapsed) write-or-die--session-target-time))))

(defun write-or-die--authorize-stop (force)
  "Return non-nil when an interactive stop is allowed.
FORCE bypasses the current session policy."
  (or force
      (write-or-die--target-met-p)
      (pcase write-or-die--session-stop-policy
        ('free t)
        ('confirm
         (yes-or-no-p "Write-or-die: sprint unfinished.  Stop anyway? "))
        ('commit
         (user-error
          "Commitment active: reach a target, or use C-u M-x write-or-die-stop"))
        (_ t))))

;;;###autoload
(defun write-or-die-stop (&optional silent force)
  "Stop the current sprint.

SILENT suppresses the echo-area summary and bypasses commitment prompts for
internal cleanup.  FORCE, supplied interactively with a prefix argument,
overrides `write-or-die--session-stop-policy'."
  (interactive (list nil current-prefix-arg))
  (let ((was-active (memq write-or-die--status '(running paused))))
    (when (or silent (not was-active) (write-or-die--authorize-stop force))
      (let ((elapsed (write-or-die--elapsed)))
        (write-or-die--refresh-word-count)
        (write-or-die--update-game-progress)
        (let ((net (max 0 (write-or-die--net-words))))
          (when was-active (write-or-die--record-session elapsed))
          (setq write-or-die--status 'stopped
                write-or-die--phase 'writing
                write-or-die--paused-at nil
                write-or-die--recovery-target nil)
          (write-or-die--cancel-timer)
          (when (and was-active (not silent))
            (message
             "Write-or-die: %d words in %s · best flow x%d · %d comeback%s."
             net (write-or-die--format-seconds elapsed)
             write-or-die--best-chain write-or-die--comeback-count
             (if (= write-or-die--comeback-count 1) "" "s"))
            (write-or-die--sound 'stop t)))
        (write-or-die--set-typewriter nil)
        (when (markerp write-or-die--draft-frontier)
          (set-marker write-or-die--draft-frontier nil))
        (setq write-or-die--baseline-text nil)
        (force-mode-line-update t)))))

;;;###autoload
(defun write-or-die ()
  "Start a sprint, or stop it when one is active."
  (interactive)
  (if (memq write-or-die--status '(running paused))
      (write-or-die-stop)
    (write-or-die-start)))

(defun write-or-die-toggle-pause ()
  "Pause or resume the current sprint."
  (interactive)
  (pcase write-or-die--status
    ('running
     (setq write-or-die--status 'paused
           write-or-die--paused-at (float-time)
           write-or-die--phase 'writing)
     (message "Write-or-die: paused. Reading, thinking, and coffee are allowed.")
     (write-or-die--sound 'pause t))
    ('paused
     (let ((now (float-time)))
       (incf write-or-die--paused-seconds
             (- now (or write-or-die--paused-at now)))
       (setq write-or-die--status 'running
             write-or-die--paused-at nil
             write-or-die--last-edit-time now
             write-or-die--warning-announced nil
             write-or-die--intervention-fired nil
             write-or-die--phase 'writing))
     (message "Write-or-die: resumed. One useful sentence at a time.")
     (write-or-die--sound 'resume t))
    (_ (user-error "No active write-or-die sprint")))
  (force-mode-line-update t))

(defun write-or-die-insert-placeholder (text)
  "Insert a TODO placeholder containing TEXT."
  (interactive "sTODO: ")
  (insert (format "[TODO: %s]" (string-trim text))))

(defun write-or-die--cleanup ()
  "Stop the sprint and remove every buffer-local hook and overlay."
  (write-or-die-stop t)
  (write-or-die--disable-focus)
  (write-or-die--set-typewriter nil)
  (when (markerp write-or-die--draft-frontier)
    (set-marker write-or-die--draft-frontier nil))
  (remove-hook 'before-change-functions #'write-or-die--before-change t)
  (remove-hook 'after-change-functions #'write-or-die--after-change t)
  (remove-hook 'kill-buffer-hook #'write-or-die--cleanup t)
  (remove-hook 'change-major-mode-hook #'write-or-die--cleanup t))

;;;###autoload
(define-minor-mode write-or-die-mode
  "Minor mode for gamified writing sprints."
  :init-value nil
  :lighter (:eval (write-or-die--mode-line-eval 'minor-mode))
  :keymap write-or-die-mode-map
  :group 'write-or-die
  (if write-or-die-mode
      (progn
        (write-or-die--ensure-global-mode-line-entry)
        (add-hook 'before-change-functions #'write-or-die--before-change nil t)
        (add-hook 'after-change-functions #'write-or-die--after-change nil t)
        (add-hook 'kill-buffer-hook #'write-or-die--cleanup nil t)
        (add-hook 'change-major-mode-hook #'write-or-die--cleanup nil t))
    (write-or-die--cleanup))
  (force-mode-line-update t))

(provide 'write-or-die)

;;; write-or-die.el ends here
