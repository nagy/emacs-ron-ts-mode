{
  description = "Tree-sitter major mode for RON (Rusty Object Notation) (Emacs package)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      flake-parts,
      nixpkgs,
      treefmt-nix,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      # Emacs packages are pure Elisp: no ELF binaries, so evaluate on
      # every Linux arch (the grammar is built per-arch by nixpkgs).
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      imports = [ treefmt-nix.flakeModule ];

      perSystem =
        {
          system,
          pkgs,
          lib,
          config,
          ...
        }:
        let
          inherit (pkgs.emacsPackages) melpaBuild;

          # Nix sets `lastModifiedDate` for git checkouts, so the version
          # tracks commits.  melpaBuild wants `<version>-unstable-YYYY-MM-DD`.
          stamp = self.lastModifiedDate or "19700101000000";
          date =
            "${builtins.substring 0 4 stamp}-"
            + "${builtins.substring 4 2 stamp}-"
            + builtins.substring 6 2 stamp;

          # Grammar in the Emacs closure, so `treesit-ready-p 'ron` succeeds
          # offline.  `with-all-grammars` would link ~477 parsers (~1.3 GiB).
          emacsWithGrammars = pkgs.emacs31.pkgs.withPackages (epkgs: [
            (epkgs.treesit-grammars.with-grammars (grammars: [ grammars.tree-sitter-ron ]))
          ]);

          src = self; # Nix filters `.git` and untracked paths.

          ron-ts-mode = melpaBuild {
            pname = "ron-ts-mode";
            inherit src;
            version = "0-unstable-${date}";

            # melpaBuild propagates this Emacs, so the grammar ships too.
            emacs = emacsWithGrammars;

            turnCompilationWarningToError = true;

            meta = {
              description = "Tree-sitter major mode for RON (Rusty Object Notation)";
              longDescription = ''
                ron-ts-mode provides syntax highlighting, indentation, and
                Imenu navigation for RON (Rusty Object Notation) files using
                tree-sitter.

                Built on Emacs 31's `define-treesit-generic-mode', it supplies
                Elisp-level font-lock rules (a transcription of the grammar's
                bundled highlights.scm plus deliberate deviations), simple
                indent rules, and Imenu settings.  Comment support, parser
                creation, and `auto-mode-alist` registration come from the
                generic mode.
              '';
              license = lib.licenses.agpl3Plus;
              homepage = "https://github.com/nagy/ron-ts-mode";
              maintainers = with lib.maintainers; [ nagy ];
              platforms = lib.platforms.linux;
            };
          };
        in
        {
          packages.ron-ts-mode = ron-ts-mode;
          packages.default = config.packages.ron-ts-mode;

          # Runs the ERT suite against the *installed* package, not the
          # checkout.  The package build already byte-compiles.
          checks.default =
            pkgs.runCommand "ron-ts-mode-ert"
              {
                nativeBuildInputs = [
                  emacsWithGrammars
                  pkgs.writableTmpDirAsHomeHook
                ];
              }
              ''
                emacs --batch \
                  -L ${config.packages.ron-ts-mode}/share/emacs/site-lisp/elpa/ron-ts-mode-* \
                  -l ${src}/ron-ts-mode-tests.el \
                  -f ert-run-tests-batch-and-exit
                touch $out
              '';

          # No network-based grammar install needed.
          devShells.default = pkgs.mkShell {
            packages = [ emacsWithGrammars ];
          };

          # The Elisp has no house-style formatter.
          treefmt.programs.nixfmt.enable = true;
        };
    };
}
