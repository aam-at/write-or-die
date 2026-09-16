;;; write-or-die-test.el --- Tests for write-or-die -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; ERT coverage for package helpers and packaging-sensitive behavior.

;;; Code:

(require 'ert)
(require 'write-or-die)

(ert-deftest write-or-die-format-seconds ()
  (should (equal (write-or-die--format-seconds 0) "0:00"))
  (should (equal (write-or-die--format-seconds 65) "1:05"))
  (should (equal (write-or-die--format-seconds 3601) "60:01")))

(ert-deftest write-or-die-clamp ()
  (should (= (write-or-die--clamp 5 0 10) 5))
  (should (= (write-or-die--clamp -2 0 10) 0))
  (should (= (write-or-die--clamp 20 0 10) 10)))

(ert-deftest write-or-die-profile-settings-are-buffer-local ()
  (with-temp-buffer
    (let ((write-or-die-target-words 111)
          (write-or-die-target-time 222)
          (write-or-die-warning-period 9)
          (write-or-die-grace-period 19)
          (write-or-die-consequence 'none)
          (write-or-die-target-wpm 0))
      (write-or-die--prepare-session-settings 'flow)
      (should (eq write-or-die--profile 'flow))
      (should (= write-or-die--session-target-words 300))
      (should (= write-or-die--session-target-time 1200))
      (should (= write-or-die--session-warning-period 15))
      (should (= write-or-die--session-grace-period 35)))))

(ert-deftest write-or-die-progress-ratio-is-clamped ()
  (with-temp-buffer
    (setq write-or-die--session-target-words 100
          write-or-die--high-watermark 25)
    (should (= (write-or-die--progress-ratio) 0.25))
    (setq write-or-die--high-watermark 150)
    (should (= (write-or-die--progress-ratio) 1.0))))

(ert-deftest write-or-die-bundled-sound-path-resolves ()
  (let ((write-or-die-sound-directory nil))
    (should (file-readable-p (write-or-die--sound-file 'start)))
    (should (file-readable-p (write-or-die--sound-file 'warning)))
    (should (file-readable-p (write-or-die--sound-file 'target)))))


(ert-deftest write-or-die-hardcore-profile-is-explicitly-destructive ()
  (with-temp-buffer
    (write-or-die--prepare-session-settings 'hardcore)
    (should (eq write-or-die--session-consequence 'rollback-session))
    (should (eq write-or-die--session-stop-policy 'commit))
    (should (eq write-or-die--session-discipline 'forward-only))
    (should write-or-die--session-typewriter)))

(ert-deftest write-or-die-forward-only-allows-insertion-at-frontier ()
  (with-temp-buffer
    (insert "seed")
    (setq write-or-die--status 'running
          write-or-die--session-discipline 'forward-only
          write-or-die--draft-frontier (copy-marker (point-max) t))
    (goto-char (point-max))
    (should-not (write-or-die--before-change (point) (point)))))

(ert-deftest write-or-die-forward-only-blocks-deletion ()
  (with-temp-buffer
    (insert "seed")
    (setq write-or-die--status 'running
          write-or-die--session-discipline 'forward-only
          write-or-die--draft-frontier (copy-marker (point-max) t))
    (should-error (write-or-die--before-change 1 2) :type 'user-error)))

(ert-deftest write-or-die-commit-policy-has-explicit-override ()
  (with-temp-buffer
    (setq write-or-die--status 'running
          write-or-die--session-stop-policy 'commit
          write-or-die--session-target-words 100
          write-or-die--session-target-time 600
          write-or-die--baseline-words 0
          write-or-die--current-words 0
          write-or-die--start-time (float-time))
    (should-error (write-or-die--authorize-stop nil) :type 'user-error)
    (should (write-or-die--authorize-stop t))))

(ert-deftest write-or-die-rollback-restores-pre-sprint-buffer ()
  (with-temp-buffer
    (let ((write-or-die-record-history nil))
      (insert "before")
      (setq write-or-die--baseline-text "before"
            write-or-die--baseline-point (point-max)
            write-or-die--baseline-modified-p nil
            write-or-die--status 'running
            write-or-die--session-stop-policy 'free
            write-or-die--baseline-words 1
            write-or-die--current-words 2
            write-or-die--start-time (float-time))
      (insert " after")
      (write-or-die--rollback-session)
      (should (equal (buffer-string) "before"))
      (should (eq write-or-die--status 'stopped)))))

(ert-deftest write-or-die-date-day-number-parses-iso-dates ()
  (should (= (write-or-die--date-day-number "2026-09-16")
             (time-to-days (encode-time 0 0 12 16 9 2026))))
  ;; Consecutive days must differ by exactly one, or the streak walk breaks.
  (should (= 1 (- (write-or-die--date-day-number "2026-01-01")
                  (write-or-die--date-day-number "2025-12-31"))))
  (should-not (write-or-die--date-day-number "not-a-date"))
  (should-not (write-or-die--date-day-number nil)))

(ert-deftest write-or-die-history-values-default-missing-keys ()
  (let ((history '((:words 10 :best-chain 3) (:elapsed 60) (:words 5))))
    (should (equal (write-or-die--history-values history :words) '(10 0 5)))
    (should (equal (write-or-die--history-values history :best-chain) '(3 0 0))))
  (should (equal (write-or-die--history-values nil :words) '())))

(defmacro write-or-die-test--with-history (&rest body)
  "Run BODY with `write-or-die-history-file' bound to a temporary file."
  (declare (indent 0))
  `(let* ((file (make-temp-file "write-or-die-test" nil ".eld"))
          (write-or-die-history-file file)
          (write-or-die-record-history t))
     (unwind-protect (progn ,@body)
       (when (file-exists-p file) (delete-file file))
       (when (get-buffer "*Write-or-Die Stats*")
         (kill-buffer "*Write-or-Die Stats*")))))

(defun write-or-die-test--record (words)
  "Record one finished sprint worth WORDS net words."
  (setq write-or-die--history-recorded nil
        write-or-die--baseline-words 0
        write-or-die--current-words words
        write-or-die--high-watermark words
        write-or-die--start-time (float-time))
  (write-or-die--record-session 60))

(ert-deftest write-or-die-history-trim-keeps-newest-entries ()
  (write-or-die-test--with-history
    (let ((write-or-die-history-limit 3))
      (with-temp-buffer
        (dolist (w '(1 2 3 4 5)) (write-or-die-test--record w)))
      ;; Newest first, so the three most recent sprints survive.
      (should (equal (mapcar (lambda (e) (plist-get e :words))
                             (write-or-die--read-history))
                     '(5 4 3))))))

(ert-deftest write-or-die-history-limit-zero-disables-trimming ()
  (write-or-die-test--with-history
    (let ((write-or-die-history-limit 0))
      (with-temp-buffer
        (dolist (w '(1 2 3 4 5)) (write-or-die-test--record w)))
      (should (= (length (write-or-die--read-history)) 5)))))

(ert-deftest write-or-die-history-is-recorded-once-per-sprint ()
  (write-or-die-test--with-history
    (with-temp-buffer
      (write-or-die-test--record 42)
      ;; A second stop of the same sprint must not add an entry.
      (write-or-die--record-session 60))
    (should (= (length (write-or-die--read-history)) 1))))

(ert-deftest write-or-die-stats-handles-empty-history ()
  (write-or-die-test--with-history
    (delete-file file)
    (write-or-die-stats)
    (with-current-buffer "*Write-or-Die Stats*"
      (let ((text (buffer-string)))
        (should (string-match-p "Sessions *0" text))
        (should (string-match-p "Best flow *x0" text))
        (should (string-match-p "Lifetime words *0" text))))))

(ert-deftest write-or-die-stats-aggregates-history ()
  (write-or-die-test--with-history
    (write-or-die--write-history
     (list (list :date "2026-09-16" :profile 'flow :words 300 :elapsed 900
                 :wpm 20 :best-chain 4 :comebacks 1)
           (list :date "2026-09-15" :profile 'standard :words 120 :elapsed 600)))
    (write-or-die-stats)
    (with-current-buffer "*Write-or-Die Stats*"
      (let ((text (buffer-string)))
        (should (string-match-p "Sessions *2" text))
        (should (string-match-p "Lifetime words *420" text))
        ;; Entries missing :best-chain must default to 0, not signal.
        (should (string-match-p "Best flow *x4" text))
        (should (string-match-p "Comebacks *1" text))))))

(ert-deftest write-or-die-show-up-streak-counts-consecutive-days ()
  (let* ((write-or-die-show-up-words 25)
         (today (format-time-string "%Y-%m-%d"))
         (yesterday (format-time-string "%Y-%m-%d" (time-subtract nil 86400))))
    (should (= 2 (write-or-die--show-up-streak
                  (list (list :date today :words 50)
                        (list :date yesterday :words 50)))))
    ;; Below the show-up threshold the day must not count.
    (should (= 0 (write-or-die--show-up-streak
                  (list (list :date today :words 1)))))))

;;; write-or-die-test.el ends here
