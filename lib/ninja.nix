{ pkgs }:

{
  toolchain,
  expandedTargets,
  executables,
  allTargets,
  closure,
  usageFor,
  dependenciesFor,
  cxxFlags,
  objcFlags,
  objcxxFlags,
  exeSuffix,
  pathFor ? (path: if builtins.isPath path then "${path}" else toString path),
  libraryPathFor ? (target: "build/lib/lib${target.name}.a"),
}:

let
  inherit (pkgs) lib;
  pathString = pathFor;

  compileFlags = lib.escapeShellArgs toolchain.compileFlags;
  linkFlags = lib.escapeShellArgs toolchain.linkFlags;
  archiveCommand =
    if toolchain.archiveTool == "gcc-ar" then
      lib.escapeShellArg "${lib.getBin toolchain.stdenv.cc.cc}/bin/${toolchain.stdenv.cc.targetPrefix}gcc-ar"
    else
      "$$AR";

  pkgConfigFor = target: lib.unique (lib.concatMap (dep: dep.pkgConfig or [ ]) (closure target));
  compilePkgConfigFor =
    target: lib.unique (lib.concatMap (dep: dep.pkgConfig or [ ]) (usageFor target));

  pkgConfigFile = mode: target: "build/deps/${target.name}.${mode}.rsp";

  pkgConfigFlags =
    mode: target: lib.optionalString (pkgConfigFor target != [ ]) "@${pkgConfigFile mode target}";

  pkgConfigDependency =
    mode: target: lib.optionalString (pkgConfigFor target != [ ]) " | ${pkgConfigFile mode target}";

  pkgConfigRule =
    target:
    let
      modules = pkgConfigFor target;
      # Package paths in the command invalidate cached flags when dependencies change.
      paths = lib.concatMap (dep: [
        "${lib.getDev dep.package}/lib/pkgconfig"
        "${lib.getDev dep.package}/share/pkgconfig"
      ]) (lib.filter (dep: dep.type == "external") (closure target));
    in
    lib.optionalString (modules != [ ]) ''
      build ${pkgConfigFile "cflags" target} ${pkgConfigFile "libs" target}: pkg_config
        modules = ${lib.escapeShellArgs modules}
        compile_modules = ${lib.escapeShellArgs (compilePkgConfigFor target)}
        pcpath = ${lib.escapeShellArg (lib.concatStringsSep ":" (lib.unique paths))}
        cflags = ${pkgConfigFile "cflags" target}
        libs = ${pkgConfigFile "libs" target}
    '';

  flagsFor =
    target:
    let
      related = usageFor target;

      projectIncludes = lib.unique (
        target.includes
        ++ lib.concatMap (t: if t ? public then t.public.includes else t.includes) (
          lib.filter (t: t.type != "external") (lib.tail related)
        )
      );
      externalIncludes = lib.unique (
        lib.concatMap (t: [ "${lib.getDev t.package}/include" ] ++ t.includes) (
          lib.filter (t: t.type == "external") related
        )
      );

      definitions = lib.unique (
        target.definitions.private ++ lib.concatMap (t: t.definitions.public) related
      );
    in
    lib.concatStringsSep " " (
      (map (inc: "-I${lib.escapeShellArg (pathString inc)}") projectIncludes)
      ++ (map (inc: "-isystem ${lib.escapeShellArg (pathString inc)}") externalIncludes)
      ++ (map (def: "-D${lib.escapeShellArg def}") definitions)
      ++ [ (pkgConfigFlags "cflags" target) ]
    );

  linkFlagsFor =
    target:
    let
      related = closure target;
      extraLibraries = lib.concatMap (dep: dep.linkLibraries or [ ]) related;
      externalFlags = lib.concatMap (dep: dep.linkFlags or [ ]) (
        lib.filter (dep: dep.type == "external") related
      );
    in
    lib.concatStringsSep " " (
      (target.linkFlags or [ ])
      ++ externalFlags
      ++ map (name: "-l${lib.escapeShellArg name}") extraLibraries
      ++ [ (pkgConfigFlags "libs" target) ]
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
          path = pathString source;
          languageFlags =
            if lib.hasSuffix ".mm" path then
              "${cxxFlags} ${objcxxFlags}"
            else if lib.hasSuffix ".m" path then
              objcFlags
            else
              cxxFlags;
        in
        ''
          build build/obj/${target.name}/${toString i}.o: compile ${path}${pkgConfigDependency "cflags" target} || build/obj/${target.name}
            flags = ${compileFlags} ${languageFlags} ${flagsFor target}
        ''
      ) target.sources
    );

  targetRules =
    key: target:
    let
      dependencies = dependenciesFor target;
      libraries = map libraryPathFor (lib.filter (t: t.type == "library") dependencies);
      assets = target.assets or [ ];
      assetStamp = "build/.${target.name}-assets";
      assetPath =
        asset:
        let
          path = pathString asset;
        in
        if lib.hasPrefix "/" path then path else "./${path}";
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
      ${pkgConfigRule target}
      ${compileRules target}
      ${assetRule}

      build ${outputFor target}: ${rule} ${lib.concatStringsSep " " inputs}${
        lib.optionalString (target.type == "executable") (pkgConfigDependency "libs" target)
      }${assetDependency}
      ${lib.optionalString (
        target.type == "executable"
      ) "  ldflags = ${linkFlags} ${linkFlagsFor target}"}
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
        rule pkg_config
          command = export PKG_CONFIG_PATH=$pcpath"$''${PKG_CONFIG_PATH:+:$''${PKG_CONFIG_PATH}}" && mkdir -p $$(dirname $cflags) && { if [ -z "$compile_modules" ]; then :; else "$''${PKG_CONFIG:-pkg-config}" --cflags $compile_modules; fi; } > $cflags.tmp && "$''${PKG_CONFIG:-pkg-config}" --libs $modules > $libs.tmp && mv $cflags.tmp $cflags && mv $libs.tmp $libs
          description = PKG_CONFIG $modules

        rule mkdir
          command = mkdir -p $out
          description = MKDIR $out

        rule compile
          command = $cxx $flags -MMD -MF $out.d -c $in -o $out
          description = CXX $in
          depfile = $out.d
          deps = gcc

        rule archive
          command = mkdir -p $$(dirname $out) && ${archiveCommand} rcs $out $in
          description = AR $out

        rule link
          command = mkdir -p $$(dirname $out) && $cxx $in $ldflags -o $out
          description = LINK $out

        rule copy_assets
          command = mkdir -p $$(dirname $out) build/bin && $copies && touch $out
          description = COPY_ASSETS $out

        build always_assets: phony

        ${lib.concatStringsSep "\n" (lib.mapAttrsToList targetRules expandedTargets)}

        ${lib.concatStringsSep "\n" (lib.map (target: "build build/obj/${target.name}: mkdir") allTargets)}

        default ${
          lib.concatStringsSep " " (map outputFor (lib.filter (t: t.type != "external") allTargets))
        }
      '';
in
{
  inherit ninjaFile;

  # Configure Ninja from the active toolchain for both builds and Ninja tools.
  command = pkgs.buildPackages.writeShellScript "cpp-ninja" ''
    set -eu
    cxx=$(command -v "''${CXX:?CXX must be set}")
    printf 'cxx = %s\ninclude %s\n' "$cxx" ${ninjaFile} > build.ninja
    exec ${pkgs.buildPackages.ninja}/bin/ninja "$@"
  '';
}
