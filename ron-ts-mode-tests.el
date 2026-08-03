;;; ron-ts-mode-tests.el --- Tests for ron-ts-mode -*- lexical-binding: t -*-

;; Copyright (C) 2026  Daniel Nagy

;; This file is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU Affero General Public License for more details.

;; You should have received a copy of the GNU Affero General Public
;; License along with this file.  If not, see
;; <https://www.gnu.org/licenses/>.

;; To run:
;;
;;   emacs --batch -L . -l ron-ts-mode-tests.el -f ert-run-tests-batch-and-exit

(require 'ron-ts-mode)
(require 'ert)

;;; Helpers

(defmacro ron-ts-mode-test--with-ron-buffer (content &rest body)
  "Create a temporary `ron-ts-mode' buffer with CONTENT and run BODY."
  (declare (indent 1))
  `(let ((buf (generate-new-buffer " *ron-ts-mode-test*")))
     (with-current-buffer buf
       (ron-ts-mode)
       (insert ,content)
       (goto-char (point-min)))
     (unwind-protect
         (with-current-buffer buf ,@body)
       (kill-buffer buf))))

;;; Mode activation

(ert-deftest ron-ts-mode-activates ()
  "Mode activates for .ron files."
  (skip-unless (treesit-ready-p 'ron))
  (ron-ts-mode-test--with-ron-buffer ""
    (should (eq major-mode 'ron-ts-mode))))

(ert-deftest ron-ts-mode-parser-created ()
  "Tree-sitter parser is created on activation."
  (skip-unless (treesit-ready-p 'ron))
  (ron-ts-mode-test--with-ron-buffer "// comment\n"
    (should (treesit-parser-list))))

;;; Font-lock: face assertions

(defun ron-ts-mode-test--face-at (word)
  "Return the face text-property at WORD's position in current buffer.
Handles both singleton faces and lists (multiple rules applied)."
  (save-excursion
    (goto-char (point-min))
    (when (search-forward word nil t)
      (let ((f (get-text-property (match-beginning 0) 'face)))
        (if (listp f) f (list f))))))

(ert-deftest ron-ts-mode-font-lock-numbers-and-strings ()
  "Numbers and strings get faces from the transcribed highlights feature."
  (skip-unless (treesit-ready-p 'ron))
  (ron-ts-mode-test--with-ron-buffer
      "Position(\n    x: 1920,\n    title: \"Hi\",\n)\n"
    (font-lock-ensure)
    (should (member 'font-lock-number-face (ron-ts-mode-test--face-at "1920")))
    (should (member 'font-lock-string-face (ron-ts-mode-test--face-at "Hi")))))

(ert-deftest ron-ts-mode-font-lock-struct-faces ()
  "Struct names, field names, booleans get faces."
  (skip-unless (treesit-ready-p 'ron))
  (ron-ts-mode-test--with-ron-buffer
      "Position(\n    fullscreen: true,\n)\n"
    (font-lock-ensure)
    (should (member 'font-lock-type-face (ron-ts-mode-test--face-at "Position")))
    (should (member 'font-lock-property-name-face (ron-ts-mode-test--face-at "fullscreen")))
    (should (member 'font-lock-keyword-face (ron-ts-mode-test--face-at "true")))))

(ert-deftest ron-ts-mode-font-lock-enum-variant-constant ()
  "Bare enum variants render as constant (not keyword)."
  (skip-unless (treesit-ready-p 'ron))
  (ron-ts-mode-test--with-ron-buffer "Dark\n"
    (font-lock-ensure)
    (should (member 'font-lock-constant-face (ron-ts-mode-test--face-at "Dark")))))

;;; Font-lock: verify rules compile and don't error

(ert-deftest ron-ts-mode-font-lock-rules-compile ()
  "Supplemental font-lock rules compile without error."
  (skip-unless (treesit-ready-p 'ron))
  (should ron-ts-mode--font-lock-rules))

(ert-deftest ron-ts-mode-font-lock-supplement-predicates ()
  "Check that known node types exist in a parsed RON buffer."
  (skip-unless (treesit-ready-p 'ron))
  (ron-ts-mode-test--with-ron-buffer
      "Config(\n    window_size: (1920, 1080),\n    fullscreen: false,\n)\n"
    (let ((root (treesit-buffer-root-node 'ron)))
      ;; Should have struct_name "Config"
      (should (treesit-node-descendant-for-range
               root (point-min) (point-max) "struct_name"))
      ;; Should have booleans
      (should (treesit-node-descendant-for-range
               root (point-min) (point-max) "boolean"))
      ;; Should have integers
      (should (treesit-node-descendant-for-range
               root (point-min) (point-max) "integer"))
      ;; Should have struct entries
      (should (treesit-node-descendant-for-range
               root (point-min) (point-max) "struct_entry")))))

;;; Indentation

(ert-deftest ron-ts-mode-indent-struct-body ()
  "Struct fields indent by ron-ts-mode-indent-offset."
  (skip-unless (treesit-ready-p 'ron))
  (ron-ts-mode-test--with-ron-buffer "Position(\n    x: 1.0,\n    y: 2.0,\n)\n"
    (let ((ron-ts-mode-indent-offset 4))
      (goto-char (point-min))
      (forward-line 1)
      (should (= (current-indentation) 4))
      (forward-line 1)
      (should (= (current-indentation) 4)))))

(ert-deftest ron-ts-mode-indent-nested ()
  "Nested structs indent correctly."
  (skip-unless (treesit-ready-p 'ron))
  (ron-ts-mode-test--with-ron-buffer
      "Config(\n    font: Font(\n        family: \"Mono\",\n    ),\n)\n"
    (let ((ron-ts-mode-indent-offset 4))
      (goto-char (point-min))
      (forward-line 1) ;; "    font: Font("
      (should (= (current-indentation) 4))
      (forward-line 1) ;; "        family: \"Mono\","
      (should (= (current-indentation) 8)))))

(ert-deftest ron-ts-mode-indent-map ()
  "Map bodies indent correctly."
  (skip-unless (treesit-ready-p 'ron))
  (ron-ts-mode-test--with-ron-buffer
      "{\n    key: \"value\",\n    flag: true,\n}\n"
    (let ((ron-ts-mode-indent-offset 4))
      (goto-char (point-min))
      (forward-line 1)
      (should (= (current-indentation) 4)))))

(ert-deftest ron-ts-mode-custom-indent-offset ()
  "Custom indent offset is respected."
  (skip-unless (treesit-ready-p 'ron))
  (ron-ts-mode-test--with-ron-buffer "Position(\n  x: 1.0,\n)\n"
    (let ((ron-ts-mode-indent-offset 2))
      (goto-char (point-min))
      (forward-line 1)
      (should (= (current-indentation) 2)))))

;;; Comments

(ert-deftest ron-ts-mode-comment-syntax ()
  "Comment syntax is set correctly."
  (skip-unless (treesit-ready-p 'ron))
  (ron-ts-mode-test--with-ron-buffer ""
    (should (equal comment-start "// "))
    (should (equal comment-end ""))))

;;; Imenu

(ert-deftest ron-ts-mode-imenu-installed ()
  "Imenu settings are installed."
  (skip-unless (treesit-ready-p 'ron))
  (ron-ts-mode-test--with-ron-buffer "Position(x: 1.0)\n"
    (should (consp treesit-simple-imenu-settings))
    (should (>= (length treesit-simple-imenu-settings) 2))))

(defun ron-ts-mode-test--flatten-imenu (entries)
  "Flatten Imenu ENTRIES into a list of names.
Nested entries are (NAME MARKER CHILDREN...) or (NAME . MARKER)."
  (cl-loop for e in entries
           append (cons (car e)
                        (when (consp (cdr e))
                          (ron-ts-mode-test--flatten-imenu (cddr e))))))

(ert-deftest ron-ts-mode-imenu-names ()
  "Imenu returns struct/enum names, not punctuation."
  (skip-unless (treesit-ready-p 'ron))
  (ron-ts-mode-test--with-ron-buffer
      "Config(\n    window_size: (1920, 1080),\n    fullscreen: false,\n)\n\nShape(\n    Rectangle(\n        width: 10,\n    ),\n)\n\nDark\n"
    (let* ((idx (treesit-simple-imenu))
           (structs (cdr (assoc "Structs" idx)))
           (enums (cdr (assoc "Enums" idx))))
      ;; Struct names, no punctuation
      (should (equal (sort (ron-ts-mode-test--flatten-imenu structs) #'string-lessp)
                     '("Config" "Rectangle" "Shape")))
      ;; Enum names
      (should (equal (sort (ron-ts-mode-test--flatten-imenu enums) #'string-lessp)
                     '("Dark")))
      ;; No punctuation anywhere
      (should-not (cl-some (lambda (e) (string-match-p "[(),]" e))
                           (ron-ts-mode-test--flatten-imenu (append structs enums)))))))

;;; Enum variant handling

(ert-deftest ron-ts-mode-parses-enum-variant ()
  "Enum variants are parsed correctly."
  (skip-unless (treesit-ready-p 'ron))
  (ron-ts-mode-test--with-ron-buffer "Dark\n"
    (let ((root (treesit-buffer-root-node 'ron)))
      (should (treesit-node-descendant-for-range
               root (point-min) (point-max) "enum_variant")))))

(provide 'ron-ts-mode-tests)
;;; ron-ts-mode-tests.el ends here
