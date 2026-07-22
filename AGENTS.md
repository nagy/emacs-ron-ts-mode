# ron-ts-mode — Architecture

Tree-sitter major mode for RON (Rusty Object Notation) files. Built on
Emacs 31's `define-treesit-generic-mode`.

## Core design: generic mode + supplements

`define-treesit-generic-mode` provides the base — it:

1. Creates the `ron` parser
2. Loads the grammar's bundled `highlights.scm` query
3. Sets up font-lock from the grammar's capture→face mapping
4. Optionally auto-installs the grammar

The supplemental layers in this package:

- **Font-lock rules** (`ron-ts-mode--font-lock-rules`): a `defvar` with
  `treesit-font-lock-rules`, stored as a top-level variable (not inside the
  mode body) so batch byte-compilation works. Added at mode activation via
  `treesit-add-font-lock-rules`.

  Two features:
  - `ron-supplement`: captures the generic mapping doesn't handle
    (`enum_variant`→constant, `struct_name`→type, `unit_struct`→builtin,
    brackets, delimiters, struct/map field name properties).
  - `ron-keyword`: `boolean`→keyword-face, `negative`→negation-char.

- **Indentation** (`ron-ts-mode--indent-rules`): `treesit-simple-indent-rules`
  for struct body, map body, array, tuple, map entries. Closing delimiters
  align to their opener's column.

- **Imenu** (`ron-ts-mode--imenu-settings`): Structs and enum variants.

## Grammar notes

Upstream: <https://github.com/tree-sitter-grammars/tree-sitter-ron>
Bundled queries: `highlights.scm`, `indents.scm`, `injections.scm`,
`folds.scm`, `locals.scm`.

Key structural detail: map keys are wrapped in `enum_variant` → `identifier`
(inline table entries use bare `identifier`, but those don't appear
top-level in RON). Our font-lock queries need to account for both patterns
but the grammar only produces `enum_variant`-wrapped keys.

## Activation

- `define-treesit-generic-mode` takes care of `auto-mode-alist`,
  `treesit-language-source-alist`, parser creation, and base font-lock.
- The mode body sets up comments, indentation, supplemental font-lock (via
  `treesit-add-font-lock-rules` + `font-lock-flush`), and Imenu.
- Font-lock is guarded by `(treesit-ready-p 'ron t)` to be safe in
  `emacs -Q` where the grammar might not be installed.

## Testing

`ron-ts-mode-tests.el` follows the same pattern as `toml-ts-cargo-mode`:

- Helper macro `ron-ts-mode-test--with-ron-buffer` for temp buffer setup
- `skip-unless (treesit-ready-p 'ron)` on every test
- Tests cover: mode activation, parser creation, font-lock faces on struct
  names/booleans/strings/enum variants, indentation at single and nested
  levels, custom indent offset, comments, Imenu settings

Run with:

    emacs --batch -L . -l ron-ts-mode-tests.el -f ert-run-tests-batch-and-exit

Or via the Nix `checkPhase`.

## Font-lock face assertions

Face assertion tests check `get-text-property` at known positions. Some face
results come back as lists when multiple rules apply; the tests handle both
the singleton and list cases.
