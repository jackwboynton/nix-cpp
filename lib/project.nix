{ pkgs, targetsLib }:

let
  inherit (pkgs) lib;
  inherit (targetsLib) external;
  pathString = path: if builtins.isPath path then "${path}" else toString path;

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
        targets
        ;

      toolchain = (import ./toolchain.nix { inherit pkgs; }) {
        optimization = projectArgs.optimization or 2;
        lto = projectArgs.lto or false;
      };

      version = projectArgs.version or "0.1.0";
      cxxFlags = projectArgs.cxxFlags or toolchain.languageDefaults.cxxFlags;
      objcFlags = projectArgs.objcFlags or toolchain.languageDefaults.objcFlags;
      objcxxFlags = projectArgs.objcxxFlags or toolchain.languageDefaults.objcxxFlags;

      graph = (import ./graph.nix { inherit lib external; }) {
        inherit targets targetAliases;
      };

      inherit (graph)
        testTargets
        expandedTargets
        executables
        allTargets
        closure
        publicClosure
        usageFor
        dependenciesFor
        externalPackages
        ;

      ninjaFile = (import ./ninja.nix { inherit pkgs; }) {
        inherit
          toolchain
          expandedTargets
          executables
          allTargets
          closure
          usageFor
          dependenciesFor
          cxxFlags
          objcFlags
          objcxxFlags
          exeSuffix
          ;
      };

      exeSuffix = pkgs.stdenv.hostPlatform.extensions.executable or "";

      projectDrv = toolchain.stdenv.mkDerivation {
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

          # build/bin is the runtime staging directory, including any
          # companion files emitted by the toolchain and copied assets.
          if [ -d build/bin ]; then
            cp -R build/bin/. "$out/bin/"
          fi

          if [ -d build/lib ]; then
            mkdir -p "$out/lib"
            cp -R build/lib/. "$out/lib/"
          fi

          ${lib.concatMapStringsSep "\n" (
            target:
            lib.concatMapStringsSep "\n" (headers: ''
              mkdir -p "$out/include"
              cp -R ${lib.escapeShellArg (pathString headers)}/. "$out/include/"
            '') (target.public.headers or [ ])
          ) allTargets}

          runHook postInstall
        '';

        passthru = {
          targets = expandedTargets;
          inherit ninjaFile;

          # Store paths, not source-tree include paths, form the installed API.
          cppUsage =
            let
              libraries = lib.filter (t: t.type == "library") allTargets;
              exported = lib.concatMap publicClosure libraries;
              exportedExternals = lib.filter (t: t.type == "external") exported;
              linkTargets = lib.concatMap closure libraries;
              orderedLibraries = lib.reverseList (
                lib.unique (lib.reverseList (lib.filter (t: t.type == "library") linkTargets))
              );
            in
            {
              includes = [
                "${projectDrv}/include"
              ]
              ++ lib.concatMap (t: [ "${lib.getDev t.package}/include" ] ++ t.includes) exportedExternals;
              definitions = {
                public = lib.unique (lib.concatMap (t: t.definitions.public) exported);
                private = [ ];
              };
              pkgConfig = lib.unique (lib.concatMap (t: t.pkgConfig or [ ]) exported);
              linkFlags =
                map (t: "${projectDrv}/lib/lib${t.name}.a") orderedLibraries
                ++ lib.concatMap (t: t.linkFlags or [ ]) (lib.filter (t: t.type != "external") linkTargets);
              linkLibraries = lib.concatMap (t: t.linkLibraries or [ ]) (
                lib.filter (t: t.type != "external") linkTargets
              );
              dependencies = map (t: t // { linkOnly = true; }) (
                lib.filter (t: t.type == "external") linkTargets
              );
            };

          tests = pkgs.runCommand "test-${name}" { } ''
            ${lib.concatMapStringsSep "\n" (
              testTarget: lib.escapeShellArg "${projectDrv}/bin/${testTarget.name}${exeSuffix}"
            ) testTargets}
            touch "$out"
          '';

          devShell = (import ./devshell.nix { inherit pkgs; }) {
            inherit
              expandedTargets
              executables
              externalPackages
              ninjaFile
              exeSuffix
              ;
            inherit (toolchain) stdenv;
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
