{ pkgs, targetsLib }:

let
  inherit (pkgs) lib;
  inherit (targetsLib) external;

  targetAliasesFor =
    targets:
    let
      names = map (target: target.name) (lib.attrValues targets);
    in
    if lib.length (lib.unique names) != lib.length names then
      throw "cpp.project: target names must be unique"
    else
      lib.listToAttrs (
        lib.mapAttrsToList (key: target: {
          name = target.name;
          value = key;
        }) targets
      );

  project = projectArgs: buildProject projectArgs (targetAliasesFor projectArgs.targets);

  buildProject =
    projectArgs: targetAliases:
    let
      inherit (projectArgs)
        name
        src
        cxxFlags
        targets
        ;
      version = projectArgs.version or "0.1.0";
      objcFlags = projectArgs.objcFlags or "-O2 -fobjc-arc";
      objcxxFlags = projectArgs.objcxxFlags or "-fobjc-arc";
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
        dependency:
        if lib.isDerivation dependency then
          external { package = dependency; }
        else if (dependency.type or "") == "external" then
          dependency
        else if lib.hasAttr (dependency.name or "") targetAliases then
          let
            key = targetAliases.${dependency.name};
          in
          if lib.hasAttr key expandedTargets then
            expandedTargets.${key}
          else
            throw "cpp.project: dependency '${dependency.name}' refers to a removed target"
        else
          dependency;

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

          projectIncludes = lib.unique (
            lib.concatMap (t: t.includes) (lib.filter (t: t.type != "external") related)
          );
          externalIncludes = lib.unique (
            lib.concatMap (t: t.includes) (lib.filter (t: t.type == "external") related)
          );

          definitions = lib.unique (
            target.definitions.private ++ lib.concatMap (t: t.definitions.public) related
          );
        in
        lib.concatStringsSep " " (
          (map (inc: "-I${toString inc}") projectIncludes)
          ++ (map (inc: "-isystem ${toString inc}") externalIncludes)
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
        key: target:
        let
          dependencies = dependenciesFor target;
          libraries = map outputFor (lib.filter (t: t.type == "library") dependencies);
          assets = target.assets or [ ];
          assetStamp = "build/bin/.${target.name}-assets";
          assetPath = asset: if lib.hasPrefix "/" asset then asset else "./${asset}";
          assetCopies = lib.concatStringsSep " && " (
            map (
              asset:
              "rm -rf ${
                lib.escapeShellArg ("build/bin/" + builtins.baseNameOf asset)
              } && cp -R ${lib.escapeShellArg (assetPath asset)} build/bin"
            ) assets
          );

          inputs = objectsFor target ++ (if target.type == "executable" then libraries else [ ]);
          assetDependency = if target.type == "executable" && assets != [ ] then " || ${assetStamp}" else "";
          assetRule =
            if target.type != "executable" || assets == [ ] then
              ""
            else
              ''
                build ${assetStamp}: copy_assets | always_assets
                  copies = ${assetCopies}
              '';

          rule = if target.type == "library" then "archive" else "link";
        in
        ''
          ${compileRules target}
          ${assetRule}

          build ${outputFor target}: ${rule} ${lib.concatStringsSep " " inputs}${assetDependency}
            ldflags = ${linkFlagsFor target}
          build ${key}: phony ${outputFor target}
        '';

      assetNameConflict = lib.any (
        target:
        lib.any (
          asset:
          lib.elem (builtins.baseNameOf asset) (
            map (exe: "${exe.name}${exeSuffix}") (lib.attrValues executables)
          )
        ) (target.assets or [ ])
      ) (lib.attrValues executables);

      ninjaFile =
        if assetNameConflict then
          throw "cpp.project: asset directory names cannot match executable filenames"
        else
          pkgs.writeText "build.ninja" ''
            rule compile
              command = mkdir -p $$(dirname $out) && $$CXX $flags -MMD -MF $out.d -c $in -o $out
              description = CXX $in
              depfile = $out.d
              deps = gcc

            rule archive
              command = mkdir -p $$(dirname $out) && $$AR rcs $out $in
              description = AR $out

            rule link
              command = mkdir -p $$(dirname $out) && $$CXX $in $ldflags -o $out
              description = LINK $out

            rule copy_assets
              command = mkdir -p $$(dirname $out) && $copies && touch $out
              description = COPY_ASSETS $out

            build always_assets: phony

            ${lib.concatStringsSep "\n" (lib.mapAttrsToList targetRules expandedTargets)}

            default ${lib.concatStringsSep " " (map outputFor (lib.attrValues executables))}
          '';

      exeSuffix = pkgs.stdenv.hostPlatform.extensions.executable or "";
      runCases = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          key: target:
          "  ${lib.escapeShellArg key}) executable=${lib.escapeShellArg "build/bin/${target.name}${exeSuffix}"} ;;"
        ) executables
      );
      projectDrv = pkgs.stdenv.mkDerivation {
        pname = name;

        inherit src version;
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

          ${lib.concatMapStrings (
            target:
            lib.concatMapStrings (asset: ''
              cp -R ${lib.escapeShellArg "build/bin/${builtins.baseNameOf asset}"} "$out/bin/"
            '') (target.assets or [ ])
          ) (lib.attrValues executables)}

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

              # Build the target if needed, then run it (and pass through any arguments).
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
          };
        };
      };
    in
    projectDrv
    // {
      override =
        changes:
        let
          patch = if builtins.isFunction changes then changes projectArgs else changes;
          nextArgs = lib.recursiveUpdate projectArgs patch;
          nextAliases = targetAliasesFor nextArgs.targets;
          aliasConflicts = lib.filter (
            alias: lib.hasAttr alias targetAliases && targetAliases.${alias} != nextAliases.${alias}
          ) (lib.attrNames nextAliases);
          aliases =
            if aliasConflicts != [ ] then
              throw "cpp.project: target names cannot be reused after an override"
            else
              targetAliases // nextAliases;
        in
        buildProject nextArgs aliases;
    };

in
{
  inherit project;
}
