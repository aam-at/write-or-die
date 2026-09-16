EMACS ?= emacs
ELISP := lisp/write-or-die.el
TESTS := test/write-or-die-test.el

.PHONY: all ci compile test checkdoc package-lint clean

all: compile test

ci: compile test checkdoc

compile: clean
	$(EMACS) -Q --batch -L lisp \
	  --eval "(setq byte-compile-error-on-warn t)" \
	  -f batch-byte-compile $(ELISP)

test:
	$(EMACS) -Q --batch -L lisp -L test \
	  -l $(TESTS) -f ert-run-tests-batch-and-exit

checkdoc:
	$(EMACS) -Q --batch $(ELISP) \
	  --eval "(progn (require 'checkdoc) (checkdoc-current-buffer t) \
	    (let ((b (get-buffer \"*Style Warnings*\"))) \
	      (when (and b (with-current-buffer b (goto-char (point-min)) \
	                     (re-search-forward \"\\\\.el:[0-9]+:\" nil t))) \
	        (with-current-buffer b (princ (buffer-string))) \
	        (kill-emacs 1))))"

# Requires package-lint to be installed in the selected Emacs environment.
package-lint:
	$(EMACS) -Q --batch \
	  --eval "(progn (require 'package) (package-initialize))" \
	  -f package-lint-batch-and-exit $(ELISP)

clean:
	rm -f lisp/*.elc test/*.elc
