;;; ron-ts-mode.el --- Tree-sitter major mode for RON (Rusty Object Notation) -*- lexical-binding: t; -*-

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

;; Author: Daniel Nagy
;; Version: 0.1.0
;; Keywords: languages, tools
;; Package-Requires: ((emacs "30.1"))
;; URL: https://github.com/nagy/ron-ts-mode

;;; Commentary:

;; `ron-ts-mode' is a major mode for editing RON (Rusty Object Notation)
;; files using tree-sitter.
;;
;; RON is a data format that closely mirrors Rust's type system.
;; See <https://github.com/ron-rs/ron> for the specification.
;;
;; The tree-sitter grammar is at:
;;   <https://github.com/tree-sitter-grammars/tree-sitter-ron>
;;
;; The grammar ships standard query files (highlights.scm, indents.scm,
;; injections.scm, folds.scm, locals.scm), so this mode builds on Emacs
;; 31's `define-treesit-generic-mode' for the basics and supplements
;; with Elisp-level font-lock rules, indentation rules, and Imenu
;; settings.
;;
;; Setup:
;;
;;   (require 'ron-ts-mode)
;;
;; The mode auto-registers for .ron files.  The tree-sitter grammar is
;; installed automatically on first use.

;;; Code:

(require 'treesit)
(require 'treesit-x)

;; ── Customization ──────────────────────────────────────────────────

(defgroup ron nil
  "Support for RON (Rusty Object Notation) files."
  :group 'languages)

(defcustom ron-ts-mode-indent-offset 4
  "Number of spaces for each indentation step."
  :type 'integer
  :safe 'integerp)

;; ── Font-lock supplements ──────────────────────────────────────────

(defvar ron-ts-mode--font-lock-rules
  (treesit-font-lock-rules
   :language 'ron
   :override t
   :feature 'ron-supplement
   '((enum_variant) @font-lock-constant-face
     (struct_name) @font-lock-type-face
     (unit_struct) @font-lock-builtin-face
     (char) @font-lock-constant-face
     (escape_sequence) @font-lock-escape-face
     ;; Punctuation the generic mapping doesn't cover
     ([ "(" ")" ] @font-lock-bracket-face)
     ([ "[" "]" ] @font-lock-bracket-face)
     ([ "{" "}" ] @font-lock-bracket-face)
     ([ "," ":" ] @font-lock-delimiter-face)
     ;; Struct/map field names
     (struct_entry (identifier) @font-lock-property-name-face)
     ;; Map keys are always enum_variant in this grammar
     (map_entry (enum_variant (identifier) @font-lock-property-name-face)))

   :language 'ron
   :override t
   :feature 'ron-keyword
   '((boolean) @font-lock-keyword-face
     (negative) @font-lock-negation-char-face))
  "Supplemental tree-sitter font-lock rules for RON.
Added on top of the grammar's bundled highlights.scm query which
is loaded automatically by `define-treesit-generic-mode'.")

;; ── Indentation ────────────────────────────────────────────────────

(defvar ron-ts-mode--indent-rules
  `((ron
     ((parent-is "source_file") column-0 0)
     ((node-is "}") parent-bol 0)
     ((node-is ")") parent-bol 0)
     ((node-is "]") parent-bol 0)
     ((parent-is "struct") parent-bol ,ron-ts-mode-indent-offset)
     ((parent-is "struct_entry") parent-bol ,ron-ts-mode-indent-offset)
     ((parent-is "map") parent-bol ,ron-ts-mode-indent-offset)
     ((parent-is "array") parent-bol ,ron-ts-mode-indent-offset)
     ((parent-is "tuple") parent-bol ,ron-ts-mode-indent-offset)
     ((and (parent-is "map_entry")
           (not (or (node-is ":") (node-is ","))))
      parent-bol ,ron-ts-mode-indent-offset)
     (no-node parent-bol 0)))
  "Tree-sitter indentation rules for RON.")

;; ── Imenu ──────────────────────────────────────────────────────────

(defvar ron-ts-mode--imenu-settings
  `(("Structs"
     ,(rx bos (or "struct" "map_entry" "struct_entry") eos)
     ron-ts-mode--imenu-name-prev-sibling nil)
    ("Enums"
     ,(rx bos "enum_variant" eos)
     (lambda (node)
       (treesit-node-text
        (treesit-node-prev-sibling node)
        t))
     nil))
  "Imenu settings for RON.")

(declare-function treesit-node-prev-sibling "treesit.c")

(defun ron-ts-mode--imenu-name-prev-sibling (node)
  "Return the text of NODE's previous sibling.
Used by Imenu for struct entries where the field name is the
preceding identifier sibling."
  (when-let* ((prev (treesit-node-prev-sibling node)))
    (treesit-node-text prev t)))

;; ── Mode definition ────────────────────────────────────────────────

;;;###autoload
(define-treesit-generic-mode ron-ts-mode
  "Major mode for editing RON (Rusty Object Notation) files.

RON is a data format that closely mirrors Rust's type system.
See <https://github.com/ron-rs/ron> for the specification.

This mode provides:
  - Tree-sitter syntax highlighting (grammar queries + Elisp rules)
  - Scope-based indentation
  - Imenu structural navigation

\\{ron-ts-mode-map}"
  :lang 'ron
  :source "https://github.com/tree-sitter-grammars/tree-sitter-ron"
  :auto-mode "\\.ron\\'"

  ;; Comments
  (setq-local comment-start "// ")
  (setq-local comment-end "")
  (setq-local comment-use-syntax nil)

  ;; Indentation
  (setq-local indent-tabs-mode nil)
  (setq-local standard-indent ron-ts-mode-indent-offset)
  (setq-local treesit-simple-indent-rules
              ron-ts-mode--indent-rules)

  ;; Font-lock supplements
  (when (treesit-ready-p 'ron t)
    (treesit-add-font-lock-rules ron-ts-mode--font-lock-rules)
    (setq-local treesit-font-lock-feature-list
                (treesit-merge-font-lock-feature-list
                 treesit-font-lock-feature-list
                 '((ron-supplement ron-keyword))))
    (font-lock-flush))

  ;; Imenu
  (setq-local treesit-simple-imenu-settings
              ron-ts-mode--imenu-settings))

;; ── Provide ────────────────────────────────────────────────────────

(provide 'ron-ts-mode)
;;; ron-ts-mode.el ends here
