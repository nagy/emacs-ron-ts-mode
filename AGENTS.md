# ron-ts-mode — Architecture

Tree-sitter major mode for RON (Rusty Object Notation) files. Built on
Emacs 31's `define-treesit-generic-mode`.

## Core design: generic mode + supplements

`define-treesit-generic-mode` provides the base — it:

1. Creates the `ron` parser
2. Adds `ron` to `treesit-language-source-alist` with `:copy-queries t`
3. Optionally auto-installs the grammar

Note: it only loads the grammar's bundled `highlights.scm` from
`~/.emacs.d/tree-sitter/queries/ron/` — in this repo's build that file does
not exist, so the generic mode contributes **no** base font-lock settings. The
font-lock base therefore lives in this package (see below).

The supplemental layers in this package:

- **Font-lock rules** (`ron-ts-mode--font-lock-rules`): a `defvar` with
  `treesit-font-lock-rules`, stored as a top-level variable (not inside the
  mode body) so batch byte-compilation works. Added at mode activation via
  `treesit-add-font-lock-rules`.

  Three features:
  - `highlights`: the grammar's bundled `highlights.scm` transcribed as a
    real feature (capture names converted to their `treesit-x` face
    counterparts). Provides enum variants→constant, struct names→type,
    unit structs→builtin, strings, numbers, floats, chars, escapes,
    comments, brackets, delimiters, operator (`-`), and `ERROR`→warning.
  - `ron-keyword`: deliberate deviation from upstream — `boolean`→keyword
    (upstream maps it to constant), `negative`→negation-char. Applied with
    `:override t` so it wins over `highlights`.
  - `ron-field`: struct field names (`struct_entry` bare `identifier` child)
    and map keys (`map_entry` `enum_variant`-wrapped identifier) →
    property-name-face.

- **Indentation** (`ron-ts-mode--indent-rules`): `treesit-simple-indent-rules`
  for struct body, map body, array, tuple, map entries. Closing delimiters
  align to their opener's column.

- **Imenu** (`ron-ts-mode--imenu-settings`): Structs and enum variants.

## Grammar notes

Upstream: <https://github.com/tree-sitter-grammars/tree-sitter-ron>
Bundled queries: `highlights.scm`, `indents.scm`, `injections.scm`,
`folds.scm`, `locals.scm`.

Key structural detail (verified against the parser):
- `struct_entry` children: bare `identifier` (the field name), then the value
  (`tuple`, `boolean`, `string`, ...).
- `map_entry` keys are `enum_variant`-wrapped identifiers (`SomeVariant: 3`)
  or strings; **bare** identifiers in maps (`b: -2`) are parse `ERROR` nodes.

So the two font-lock patterns are asymmetric: structs use
`(struct_entry (identifier) @cap)`, maps use
`(map_entry (enum_variant (identifier) @cap))`.

## Activation

- `define-treesit-generic-mode` takes care of `auto-mode-alist`,
  `treesit-language-source-alist`, and parser creation.
- The mode body sets up comments, indentation, font-lock (via
  `treesit-add-font-lock-rules` + `font-lock-flush`), and Imenu.
- Font-lock is guarded by `(treesit-ready-p 'ron t)` to be safe in
  `emacs -Q` where the grammar might not be installed.
- `treesit-font-lock-feature-list` is merged to
  `((highlights ron-keyword ron-field))`.

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

## Open recommendations (audited 2026-08, Emacs 31.0.91 + tree-sitter-ron 0.2.0)

Remaining items from the original audit (items 1, 3, 4, 6 — the bundled
highlights transcription, dead font-lock patterns, the boolean→keyword
deviation, and Imenu — are fixed; see commit history and the test suite).
All 20 tests currently pass.

### 1. `:source` is currently a no-op in this build

The generic mode appends `(ron . ("URL" :copy-queries t))` to
`treesit-language-source-alist`, but with `:copy-queries` unset the queries
never land where `treesit-generic-mode-font-lock-query` looks. Combined with
the fact that the font-lock base is now provided by the `highlights` feature
in `ron-ts-mode--font-lock-rules`, the mode's "grammar ships queries, so we
get them for free" assumption doesn't hold.

### 2. Mode-activation ordering: font-lock is added after `treesit-major-mode-setup`

Body runs after `(treesit-generic-mode-setup lang)` (which only sets up
`treesit-font-lock-settings` from the never-loaded query), and
`treesit-add-font-lock-rules` + `font-lock-flush` in the body run **before**
`treesit-major-mode-setup`. This works today but is fragile: if the bundled
query is ever loaded through the generic mode's path,
`treesit-major-mode-setup` will build `font-lock-keywords` from
`treesit-font-lock-feature-list` at that point, and the
`treesit-merge-font-lock-feature-list` reordering in the body may not be what
you want. Re-verify after any change to how `highlights.scm` is loaded.

### 3. `map_entry` only matches `enum_variant`-wrapped keys — inline table keys are a syntax error

Verified: in `{ "a": 1, b: -2 }`, the grammar emits
`map_entry ("a" : 1)` and `ERROR (b: -2)`. Quoted keys parse; bare
identifiers in inline maps are errors. `b` correctly renders as
`font-lock-warning-face` (the `ERROR` → warning rule in `highlights`). This
is not a bug in the mode — it's what the grammar does. Documented in code.

### 4. Tests: indent-offset coverage is via `let`, not real use

Face-assertion, Imenu-name, negative-number, and engine-driven indent tests
are in place (20/20 of the suite covers font-lock faces, Imenu names, node
structure, indentation, comments).

The remaining gap: `ron-ts-mode-custom-indent-offset` binds
`ron-ts-mode-indent-offset` via `let` rather than `setq-local` on a real
file. Consider `ert-with-temp-file` + `setq-local` to be closer to real use.

### 5. Misc

- `ron-ts-mode--font-lock-rules` uses `:override t` only on `ron-keyword`
  and `ron-field` (the deliberate deviations), not on `highlights` — this
  matches the recommendation.
- `(require 'treesit-x)` is correct (the macro lives there) — keep it.
- The `:auto-mode "\\.ron\\'"` registration works and is tested implicitly.
- `Package-Requires: ((emacs "31"))` — matches where
  `define-treesit-generic-mode` (treesit-x.el) landed. DONE.
- License is AGPL-3+ while the code mirrors upstream tree-sitter-ron's MIT —
  decide if that matters for redistribution.

### Priority order

1. Indentation: wrapped-value and engine-driven indent tests DONE
   (`ron-ts-mode-indent-wrapped-value`, `-map-wrapped-value`,
   `-engine-unindented`, `-engine-unindented-map`); the long-multiline case
   is covered by the engine tests.
2. `negative` sign coloring RESOLVED (was item 2) — kept negation-char,
   locked in by `ron-ts-mode-font-lock-negative-number`.
3. `:source`/`:copy-queries` Nix wiring (item 1) — build-level, slow to
   iterate; lower priority now that `highlights` is embedded.
4. Re-verify mode-activation ordering (item 2) if `highlights.scm` loading
   ever changes.
