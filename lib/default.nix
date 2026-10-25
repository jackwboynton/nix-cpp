{ pkgs }:

let
  inherit (pkgs) lib;

  library =
    {
      name,
      sources,
      dependencies ? [ ],
      includes ? [ ],
      definitions ? [ ],
    }:
    {
      type = "library";
      inherit
        name
        sources
        dependencies
        includes
        definitions
        ;
    };

  executable =
    {
      name,
      sources,
      dependencies ? [ ],
      includes ? [ ],
      definitions ? [ ],
    }:
    {
      type = "executable";
      inherit
        name
        sources
        dependencies
        includes
        definitions
        ;
    };

  external =
    {
      package,
      includes ? [ ],
      linkLibraries ? [ ],
      dependencies ? [ ],
      definitions ? [ ],
    }:
    {
      type = "external";
      inherit
        package
        includes
        linkLibraries
        dependencies
        definitions
        ;
    };

  project =
    {
      name,
      src,
      cxxFlags,
      targets,
    }:
    let
      executables = lib.filterAttrs (_: target: target.type == "executable") targets;

      allTargets = lib.attrValues targets;

      # Dependencies appear after their dependents, which matters
      # when linking static archives.
      closure = target: [ target ] ++ lib.concatMap closure target.dependencies;

      dependenciesFor = target: lib.unique (lib.tail (closure target));

      flagsFor =
        target:
        let
          related = [ target ] ++ dependenciesFor target;
          includes = lib.unique (lib.concatMap (t: t.includes) related);
          definitions = lib.unique (lib.concatMap (t: t.definitions) related);
        in
        lib.concatStringsSep " " (
          (map (inc: "-I${toString inc}") includes) ++ (map (def: "-D${def}") definitions)
        );

      objectsFor = target: lib.imap0 (i: _: "build/obj/${target.name}/${toString i}.o") target.sources;

      outputFor =
        target:
        if target.type == "library" then "build/lib/lib${target.name}.a" else "build/bin/${target.name}";

      compileRules =
        target:
        lib.concatStringsSep "\n" (
          lib.imap0 (i: source: ''
            build build/obj/${target.name}/${toString i}.o: compile ${toString source}
              flags = ${flagsFor target}
          '') target.sources
        );

      targetRules =
        target:
        let
          dependencies = dependenciesFor target;
          libraries = map outputFor (lib.filter (t: t.type == "library") dependencies);
          inputs = objectsFor target ++ libraries;
          rule = if target.type == "library" then "archive" else "link";
        in
        ''
          ${compileRules target}

          build ${outputFor target}: ${rule} ${lib.concatStringsSep " " inputs}
          build ${target.name}: phony ${outputFor target}
        '';

      ninjaFile = pkgs.writeText "build.ninja" ''
        cxxflags = ${cxxFlags}

        rule compile
          command = mkdir -p $$(dirname $out) && $$CXX $cxxflags $flags -MMD -MF $out.d -c $in -o $out
          depfile = $out.d
          deps = gcc

        rule archive
          command = mkdir -p $$(dirname $out) && $$AR rcs $out $in

        rule link
          command = mkdir -p $$(dirname $out) && $$CXX $in -o $out

        ${lib.concatStringsSep "\n" (map targetRules allTargets)}

        default ${lib.concatStringsSep " " (map outputFor (lib.attrValues executables))}
      '';
    in
    pkgs.stdenv.mkDerivation {
      pname = name;
      version = "0.1.0";

      inherit src;
      strictDeps = true;

      nativeBuildInputs = [ pkgs.ninja ];

      dontConfigure = true;

      buildPhase = ''
        runHook preBuild

        cp ${ninjaFile} build.ninja
        ninja -j "$NIX_BUILD_CORES"

        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall

        mkdir -p "$out/bin"

        ${lib.concatMapStringsSep "\n" (target: ''
          install -Dm755 build/bin/${target.name} "$out/bin/${target.name}"
        '') (lib.attrValues executables)}

        runHook postInstall
      '';

      passthru = {
        inherit targets ninjaFile;

        devShell = pkgs.mkShell {
          packages = [
            pkgs.ninja

            (pkgs.writeShellScriptBin "build" ''
              							exec ninja -f ${ninjaFile} "$@"
              						'')
          ];
        };
      };
    };

in
{
  inherit
    library
    executable
    external
    project
    ;
}
