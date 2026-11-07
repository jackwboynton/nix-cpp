{ pkgs }:

{
  expandedTargets,
  executables,
  externalPackages,
  ninjaCommand,
  compdbDependencies,
  exeSuffix,
  stdenv ? pkgs.stdenv,
}:

let
  inherit (pkgs) lib;

  iwyu = pkgs.pkgsBuildBuild.include-what-you-use.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      # Nix's C++ header flags use -cxx-isystem, which IWYU's wrapper ignores.
      substituteInPlace $out/bin/include-what-you-use \
        --replace-fail '-isystem)' '-isystem|-cxx-isystem)'
    '';
  });

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
      set -e
      ${lib.optionalString (compdbDependencies != [ ]) ''
        ${ninjaCommand} ${lib.escapeShellArgs compdbDependencies}
      ''}
      ${ninjaCommand} -t compdb compile compile_module > compile_commands.json
    '')

    (pkgs.buildPackages.writeShellScriptBin "iwyu" ''
      if [ ! -f compile_commands.json ]; then
        echo "No compile_commands.json found. Run compdb in the project directory first." >&2
        exit 1
      fi
      exec ${iwyu}/bin/iwyu_tool.py -p . "$@"
    '')
  ]
  ++ externalPackages;

  shellHook = ''
    complete -W ${lib.escapeShellArg (lib.concatStringsSep " " (lib.attrNames expandedTargets))} run build
  '';
}
