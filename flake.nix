{
  description = "Tree-sitter major mode for RON (Rusty Object Notation) (Emacs package)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    # nixfmt is the house formatter; treefmt-nix wires it into `nix fmt`.
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
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

          # The package loads tree-sitter grammars at runtime through
          # `treesit-language-source-alist`; nixpkgs ships the ron grammar
          # as an Emacs package, so build with an Emacs that already has
          # it.  This makes `treesit-ready-p 'ron` succeed in the sandbox.
          emacsWithGrammars = pkgs.emacs31.pkgs.withPackages (epkgs: [
            epkgs.treesit-grammars.with-all-grammars
          ]);

          src = lib.cleanSource ./.;

          ron-ts-mode = melpaBuild {
            pname = "ron-ts-mode";
            # Nix rejects versions Nixpkgs cannot parse.  Convention for
            # unreleased packages: <upstream-version>-unstable-<YYYY-MM-DD>,
            # where the date is the last commit touching the source.
            version = "0.1.0-unstable-2026-08-03";

            inherit src;

            # melpaBuild byte-compiles with this Emacs and propagates it,
            # so the installed package finds the grammar in its closure.
            emacs = emacsWithGrammars;

            # Byte-compilation warnings fail the build.  Keep it on: it is
            # the cheapest lint the package will ever get.
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

          # `nix flake check` builds packages.ron-ts-mode, which already
          # byte-compiles everything.  This additionally runs the ERT suite
          # against the *installed* package, so the check exercises the
          # artifact that ships, not the checkout.
          checks.default =
            pkgs.runCommand "ron-ts-mode-ert"
              {
                nativeBuildInputs = [ emacsWithGrammars ];
              }
              ''
                export HOME=$TMPDIR
                emacs --batch \
                  -L ${config.packages.ron-ts-mode}/share/emacs/site-lisp/elpa/ron-ts-mode-* \
                  -l ${src}/ron-ts-mode-tests.el \
                  -f ert-run-tests-batch-and-exit
                touch $out
              '';

          # Interactive hacking: a real Emacs with the grammar available so
          # the mode activates without the network-based grammar install.
          devShells.default = pkgs.mkShell {
            packages = [ emacsWithGrammars ];
          };

          # Only Nix files exist in this repo; the Elisp has no formatter
          # in the house style, so treefmt only runs nixfmt.
          treefmt.programs.nixfmt.enable = true;
        };
    };
}
