{
  pkgs ? import <nixpkgs> { },
  lib ? pkgs.lib,
  emacs31 ? pkgs.emacs31,
  emacsPackages ? emacs31.pkgs,
  melpaBuild ? emacsPackages.melpaBuild,
}:

let
  emacsWithGrammars = emacs31.pkgs.withPackages (epkgs: [
    epkgs.treesit-grammars.with-all-grammars
  ]);
in
melpaBuild (finalAttrs: {
  pname = "ron-ts-mode";
  version = "0.1.0";
  src = lib.cleanSource ./.;

  emacs = emacsWithGrammars;

  turnCompilationWarningToError = true;

  checkPhase = ''
    runHook preCheck
    ${emacsWithGrammars}/bin/emacs --batch -L . \
      -l ron-ts-mode-tests.el \
      -f ert-run-tests-batch-and-exit
    runHook postCheck
  '';

  doCheck = true;

  meta = {
    description = "Tree-sitter major mode for RON (Rusty Object Notation)";
    longDescription = ''
      ron-ts-mode provides syntax highlighting, indentation, and Imenu
      navigation for RON files using tree-sitter.

      Built on Emacs 31's define-treesit-generic-mode, it loads the
      grammar's bundled query files and supplements them with Elisp-level
      font-lock and indentation rules.
    '';
    license = lib.licenses.agpl3Plus;
    homepage = "https://github.com/nagy/ron-ts-mode";
    maintainers = with lib.maintainers; [ nagy ];
    platforms = lib.platforms.unix;
  };
})
