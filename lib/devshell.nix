{ pkgs }:

{
  expandedTargets,
  executables,
  externalPackages,
  ninjaFile,
  exeSuffix,
  stdenv ? pkgs.stdenv,
}:

let
  inherit (pkgs) lib;

  runCases = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      key: target:
      "  ${lib.escapeShellArg key}) executable=${lib.escapeShellArg "build/bin/${target.name}${exeSuffix}"} ;;"
    ) executables
  );
in
(pkgs.mkShell.override { inherit stdenv; }) {
  packages = [
    pkgs.buildPackages.ninja
    pkgs.buildPackages.pkg-config

    (pkgs.buildPackages.writeShellScriptBin "build" ''
      exec ninja -f ${ninjaFile} "$@"
    '')

    (pkgs.buildPackages.writeShellScriptBin "run" ''
      target="$1"
      shift
      case "$target" in
      ${runCases}
        *) echo "Unknown executable target: $target" >&2; exit 2 ;;
      esac
      ninja -f ${ninjaFile} "$target" && exec "$executable" "$@"
    '')
  ]
  ++ externalPackages;

  shellHook = ''
    complete -W ${lib.escapeShellArg (lib.concatStringsSep " " (lib.attrNames expandedTargets))} run build
  '';
}
