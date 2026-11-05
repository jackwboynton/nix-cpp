{ pkgs }:

{
  expandedTargets,
  executables,
  externalPackages,
  ninjaCommand,
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
      exec ${ninjaCommand} "$@"
    '')

    (pkgs.buildPackages.writeShellScriptBin "run" ''
      target="$1"
      shift
      case "$target" in
      ${runCases}
        *) echo "Unknown executable target: $target" >&2; exit 2 ;;
      esac
      ${ninjaCommand} "$target" && exec "$executable" "$@"
    '')

    (pkgs.buildPackages.writeShellScriptBin "compdb" ''
      ${ninjaCommand} -t compdb compile > compile_commands.json
    '')
  ]
  ++ externalPackages;

  shellHook = ''
    complete -W ${lib.escapeShellArg (lib.concatStringsSep " " (lib.attrNames expandedTargets))} run build
  '';
}
