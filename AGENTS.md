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

## General recommendations (audited 2026-08, Emacs 31.0.91 + tree-sitter-ron 0.2.0)

These were verified by running the mode and the grammar in this repo's own
Nix environment. All 11 tests currently pass.

### 1. ~~The bundled `highlights.scm` is never loaded~~ DONE

**Fixed:** the bundled query is now transcribed as the `highlights` feature in
`ron-ts-mode--font-lock-rules` (see "Core design" above), so numbers,
strings, enum variants, escapes, punctuation, and comments all get faces
without relying on the generic mode's `~/.emacs.d` lookup. The old
`ron-supplement` feature is gone.

### 2. `:source` is currently a no-op in this build

The generic mode appends `(ron . ("URL" :copy-queries t))` to
`treesit-language-source-alist`, but with `:copy-queries` unset the queries
never land where `treesit-generic-mode-font-lock-query` looks. Combined with
(1), the mode's "grammar ships queries, so we get them for free" assumption
doesn't hold.

### 3. ~~The font-lock `ron-supplement` rules contain dead/broken patterns~~ DONE

**Fixed:** `ron-supplement` was replaced by `highlights` (transcribed bundled
query) + `ron-field`. Correction to the original audit: the claim that
`(struct_entry (identifier))` matches nothing was **wrong** — struct entries
use a bare `identifier` child, so the pattern works. The actual asymmetry is:
structs use bare `identifier`, maps use `enum_variant`-wrapped identifiers.
`enum_variant` is no longer shadowed (it's constant from `highlights`, and
`ron-keyword` only re-maps `boolean`, not `enum_variant`).

### 4. ~~`ron-keyword` (boolean → keyword) fights the grammar's own `@boolean` mapping~~ DONE

**Fixed:** the deviation is now documented in a comment right above
`ron-keyword`. `boolean` → keyword-face with `:override t` is intentional;
`enum_variant` is no longer affected (it's covered by `highlights` and not
re-mapped).

### 5. `negative` font-lock rule only colors the minus sign

Still open. `(negative) @font-lock-negation-char-face` colors only the `-` in
`-2`; the digits are a separate `integer` node. Now that `highlights` maps
`integer` → number-face, the digits after `-` are colored number but the `-`
itself is negation-char. Decide if that's acceptable.

### 6. Imenu is effectively broken

`ron-ts-mode--imenu-name-prev-sibling` reads the **previous sibling**, but in
this grammar the name is the *previous sibling's previous sibling* (or the
field's `struct_name`):
- `struct_entry "window_size: ..."` → prev sibling is `"("` → Imenu entry
  is `"("`.
- `enum_variant "A"` → prev sibling is `"("`; `"B"` → `","` — the
  `ron-ts-mode--imenu-name-prev-sibling` lambda returns these punctuation
  strings as names.
- The `Structs` regex `(or "struct" "map_entry" "struct_entry")` also
  matches every `struct` node (every RON value is a `struct`), so Imenu would
  be full of `(`, `,`, and giant struct texts.

The tests only assert `treesit-simple-imenu-settings` is non-nil — they never
exercise the name functions, so this is untested behavior.

**Recommendation:** name function should be: for a `struct`/`struct_entry`/`map_entry`
node, take the first named child (or `struct_name`); for `enum_variant` inside
a tuple, take the `struct_name` of the enclosing struct. Add a test that
actually runs `imenu--make-index-alist` (or calls the name function directly)
on a small buffer and checks the returned names are the field/enum names.

### 7. Mode-activation ordering: font-lock is added after `treesit-major-mode-setup`

Body runs after `(treesit-generic-mode-setup lang)` (which only sets up
`treesit-font-lock-settings` from the never-loaded query), and
`treesit-add-font-lock-rules` + `font-lock-flush` in the body run **before**
`treesit-major-mode-setup`. This works today but is fragile: if the bundled
query is loaded (per (1)), `treesit-major-mode-setup` will build
`font-lock-keywords` from `treesit-font-lock-feature-list` at that point, and
the `treesit-merge-font-lock-feature-list` reordering in the body may not be
what you want. Re-verify after fixing (1).

### 8. Indentation works but is overly rigid and duplicates the grammar's `indents.scm`

The grammar ships `indents.scm` (array/map/tuple/struct + branch delimiters).
The mode's `ron-ts-mode--indent-rules` hard-codes `parent-bol` + offset 4 for
all containers; `ron-ts-mode-indent-offset` is respected, but the rules don't
handle multiline expressions well (e.g. a long `struct_entry` value spanning
lines, or `map_entry` with value on the next line). The `map_entry` rule is a
heuristic that excludes `:`/`,` but doesn't cover `value` on a new line.

**Recommendation:** consider loading the grammar's `indents.scm` via
`treesit-simple-indent-rules` from the bundled query (or vendor it), and keep
the Elisp rules only as a fallback. At minimum add a test with a wrapped
struct field value.

### 9. `map_entry` only matches `enum_variant`-wrapped keys — inline table keys are a syntax error

Verified: in `{ "a": 1, b: -2 }`, the grammar emits
`map_entry ("a" : 1)` and `ERROR (b: -2)`. Quoted keys parse; bare
identifiers in inline maps are errors. `b` now correctly renders as
`font-lock-warning-face` (the `ERROR` → warning rule in `highlights`). This
is not a bug in the mode — it's what the grammar does. Documented in code.

### 10. Tests don't cover the real failure modes

The test suite only checks: mode activates, parser exists, rules compile,
specific node types exist, indentation on simple cases, comment syntax,
imenu settings installed. It never checks:
- that numbers/strings actually get a face (**now fixed** — they do, via
  `highlights`; add an assertion test to lock it in)
- that enum variants render as constant (now constant from `highlights` —
  add an assertion test)
- that Imenu names are correct (they're punctuation, see (6))
- `ron-ts-mode-indent-offset` changes (covered, but only via `let` binding —
  consider `ert-with-temp-file` + `setq-local` to be closer to real use)

**Recommendation:** add face-assertion tests for number/string/enum faces
(they now pass — lock them in), and Imenu-name tests. See
`ron-ts-mode-tests.el` for the current `get-text-property` pattern.

### 11. Misc

- `ron-ts-mode--font-lock-rules` now uses `:override t` only on
  `ron-keyword` and `ron-field` (the deliberate deviations), not on
  `highlights` — this matches the recommendation.
- `(require 'treesit-x)` is correct (the macro lives there) — keep it.
- The `:auto-mode "\\.ron\\'"` registration works and is tested implicitly.
- `Package-Requires: ((emacs "30.1"))` vs. `define-treesit-generic-mode`
  landing in 31 — double-check the floor; the macro used here is Emacs 31.
- License is AGPL-3+ while the code mirrors upstream tree-sitter-ron's MIT —
  decide if that matters for redistribution.

### Priority order

1. ~~Vendor/load the bundled `highlights.scm`~~ DONE (as the `highlights`
   feature in `ron-ts-mode--font-lock-rules`)
2. Fix Imenu name extraction (punctuation names) — next up
3. ~~Trim dead font-lock patterns~~ DONE (folded into the rewrite)
4. Add face-assertion tests for numbers/strings/enum faces + Imenu names
