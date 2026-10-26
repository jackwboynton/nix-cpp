{ pkgs }:

let
  inherit (pkgs) lib;

  library =
    {
      name,
      sources,
      dependencies ? [ ],
      includes ? [ ],
      definitions ? {
        public = [ ];
        private = [ ];
      },
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
      definitions ? {
        public = [ ];
        private = [ ];
      },
      linkFlags ? [ ],
    }:
    {
      type = "executable";
      inherit
        name
        sources
        dependencies
        includes
        definitions
        linkFlags
        ;
    };

  external =
    {
      package,
      includes ? [ ],
      linkLibraries ? [ ],
      dependencies ? [ ],
      definitions ? {
        public = [ ];
        private = [ ];
      },
      pkgConfig ? [ (lib.getName package) ],
    }:
    {
      type = "external";
      inherit
        package
        includes
        linkLibraries
        dependencies
        definitions
        pkgConfig
        ;
    };

  project =
    {
      name,
      src,
      cxxFlags,
      objcFlags ? "-O2 -fobjc-arc",
      objcxxFlags ? "-fobjc-arc",
      targets,
    }:
    let
      executables = lib.filterAttrs (_: target: target.type == "executable") targets;

      allTargets = lib.attrValues targets;

      normalize =
        dependency: if lib.isDerivation dependency then external { package = dependency; } else dependency;

      closure =
        dependency:
        let
          target = normalize dependency;
        in
        [ target ] ++ lib.concatMap closure target.dependencies;

      dependenciesFor = target: lib.unique (lib.tail (closure target));

      externalDependencies = lib.filter (dep: dep.type == "external") (lib.concatMap closure allTargets);

      externalPackages = lib.unique (map (dep: dep.package) externalDependencies);

      pkgConfigFor =
        target:
        lib.unique (
          lib.concatMap (dep: if dep.type == "external" then dep.pkgConfig else [ ]) (closure target)
        );

      pkgConfigFlags =
        mode: target:
        let
          modules = pkgConfigFor target;
        in
        if modules == [ ] then
          ""
        else
          "$$(\"$\${PKG_CONFIG:-pkg-config}\" --${mode} ${lib.escapeShellArgs modules})";

      flagsFor =
        target:
        let
          related = closure target;

          includes = lib.unique (lib.concatMap (t: t.includes) related);

          definitions = lib.unique (
            target.definitions.private ++ lib.concatMap (t: t.definitions.public) related
          );
        in
        lib.concatStringsSep " " (
          (map (inc: "-I${toString inc}") includes)
          ++ (map (def: "-D${lib.escapeShellArg def}") definitions)
          ++ [ (pkgConfigFlags "cflags" target) ]
        );

      linkFlagsFor =
        target:
        let
          extraLibraries = lib.concatMap (dep: if dep.type == "external" then dep.linkLibraries else [ ]) (
            closure target
          );
        in
        lib.concatStringsSep " " (
          (target.linkFlags or [ ]) ++ extraLibraries ++ [ (pkgConfigFlags "libs" target) ]
        );

      objectsFor = target: lib.imap0 (i: _: "build/obj/${target.name}/${toString i}.o") target.sources;

      outputFor =
        target:
        if target.type == "library" then "build/lib/lib${target.name}.a" else "build/bin/${target.name}";

      compileRules =
        target:
        lib.concatStringsSep "\n" (
          lib.imap0 (
            i: source:
            let
              path = toString source;

              languageFlags =
                if lib.hasSuffix ".mm" path then
                  "${cxxFlags} ${objcxxFlags}"
                else if lib.hasSuffix ".m" path then
                  objcFlags
                else
                  cxxFlags;
            in
            ''
              build build/obj/${target.name}/${toString i}.o: compile ${path}
                flags = ${languageFlags} ${flagsFor target}
            ''
          ) target.sources
        );

      targetRules =
        target:
        let
          dependencies = dependenciesFor target;
          libraries = map outputFor (lib.filter (t: t.type == "library") dependencies);

          inputs = objectsFor target ++ (if target.type == "executable" then libraries else [ ]);

          rule = if target.type == "library" then "archive" else "link";
        in
        ''
          ${compileRules target}

          build ${outputFor target}: ${rule} ${lib.concatStringsSep " " inputs}
            ldflags = ${linkFlagsFor target}
          build ${target.name}: phony ${outputFor target}
        '';

      ninjaFile = pkgs.writeText "build.ninja" ''
        rule compile
          command = mkdir -p $$(dirname $out) && $$CXX $flags -MMD -MF $out.d -c $in -o $out
          depfile = $out.d
          deps = gcc

        rule archive
          command = mkdir -p $$(dirname $out) && $$AR rcs $out $in

        rule link
          command = mkdir -p $$(dirname $out) && $$CXX $in $ldflags -o $out

        ${lib.concatStringsSep "\n" (map targetRules allTargets)}

        default ${lib.concatStringsSep " " (map outputFor (lib.attrValues executables))}
      '';
    in
    pkgs.stdenv.mkDerivation {
      pname = name;
      version = "0.1.0";

      inherit src;
      strictDeps = true;

      nativeBuildInputs = [
        pkgs.buildPackages.ninja
        pkgs.buildPackages.pkg-config
      ];

      buildInputs = externalPackages;

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
            pkgs.buildPackages.ninja
            pkgs.buildPackages.pkg-config

            (pkgs.buildPackages.writeShellScriptBin "build" ''
              							exec ninja -f ${ninjaFile} "$@"
              						'')
          ]
          ++ externalPackages;
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
