{ pkgs, targetsLib }:

let
  inherit (pkgs) lib;
  inherit (targetsLib) external;

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
      # A test target is the same as an explicitly declared sibling executable.
      # Libraries link against the library under test; executables cannot be
      # linked, so their tests inherit their dependencies but not their sources.
      testTargets =
        lib.mapAttrsToList
          (_: target: {
            name = "${target.name}-tests";
            value = target // {
              type = "executable";
              name = "${target.name}-tests";
              sources = target.testSources or [ ];
              dependencies = if target.type == "library" then [ target ] else target.dependencies;
              testSources = [ ];
            };
          })
          (
            lib.filterAttrs (
              _: target:
              (target.type == "library" || target.type == "executable") && (target.testSources or [ ]) != [ ]
            ) targets
          );

      testNames = map (testTarget: testTarget.name) testTargets;
      existingNames = (lib.attrNames targets) ++ (map (target: target.name) (lib.attrValues targets));

      expandedTargets =
        if
          lib.length (lib.unique testNames) != lib.length testNames
          || lib.intersectLists testNames existingNames != [ ]
        then
          throw "cpp.project: generated test target names collide with existing targets or each other"
        else
          targets // (lib.listToAttrs testTargets);

      executables = lib.filterAttrs (_: target: target.type == "executable") expandedTargets;

      allTargets = lib.attrValues expandedTargets;

      normalize =
        dependency: if lib.isDerivation dependency then external { package = dependency; } else dependency;

      closure =
        dependency:
        let
          target = normalize dependency;
        in
        [ target ] ++ lib.concatMap closure target.dependencies;

      dependenciesFor = target: lib.tail (closure target);

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
        if target.type == "library" then
          "build/lib/lib${target.name}.a"
        else
          "build/bin/${target.name}${exeSuffix}";

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

      exeSuffix = pkgs.stdenv.hostPlatform.extensions.executable or "";
      projectDrv = pkgs.stdenv.mkDerivation {
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
            install -Dm755 ${outputFor target} "$out/bin/${target.name}${exeSuffix}"
          '') (lib.attrValues executables)}

          runHook postInstall
        '';

        passthru = {
          targets = expandedTargets;
          inherit ninjaFile;

          tests = pkgs.runCommand "test-${name}" { } ''
            ${lib.concatMapStringsSep "\n" (
              testTarget: lib.escapeShellArg "${projectDrv}/bin/${testTarget.name}${exeSuffix}"
            ) testTargets}
            touch "$out"
          '';

          devShell = pkgs.mkShell {
            packages = [
              pkgs.buildPackages.ninja
              pkgs.buildPackages.pkg-config

              (pkgs.buildPackages.writeShellScriptBin "build" ''
                exec ninja -f ${ninjaFile} "$@"
              '')

              # Run a built executable (and pass through any arguments).
              (pkgs.buildPackages.writeShellScriptBin "run" ''
                target="$1"
                shift
                exec "build/bin/$target${exeSuffix}" "$@"
              '')

              # Run the generated test executable for a target.
              (pkgs.buildPackages.writeShellScriptBin "test" ''
                target="$1"
                shift
                exec "build/bin/$target-tests${exeSuffix}" "$@"
              '')
            ]
            ++ externalPackages;
          };
        };
      };
    in
    projectDrv;

in
{
  inherit project;
}
