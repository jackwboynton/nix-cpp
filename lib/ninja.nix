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
}:

let
  inherit (pkgs) lib;
  pathString = path: if builtins.isPath path then "${path}" else toString path;

  compileFlags = lib.escapeShellArgs toolchain.compileFlags;
  linkFlags = lib.escapeShellArgs toolchain.linkFlags;
  archiveCommand =
    if toolchain.archiveTool == "gcc-ar" then
      lib.escapeShellArg
        "${toolchain.stdenv.cc}/bin/${toolchain.stdenv.cc.targetPrefix}gcc-ar"
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
          build build/obj/${target.name}/${toString i}.o: compile ${path}${pkgConfigDependency "cflags" target}
            flags = ${compileFlags} ${languageFlags} ${flagsFor target}
        ''
      ) target.sources
    );

    targetRules =
    key: target:
    let
      dependencies = dependenciesFor target;
      libraries = map outputFor (lib.filter (t: t.type == "library") dependencies);
      assets = target.assets or [ ];
      assetStamp = "build/.${target.name}-assets";
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
      ${pkgConfigRule target}
      ${compileRules target}
      ${assetRule}

      build ${outputFor target}: ${rule} ${lib.concatStringsSep " " inputs}${
        lib.optionalString (target.type == "executable") (pkgConfigDependency "libs" target)
      }${assetDependency}
        ldflags = ${linkFlags} ${linkFlagsFor target}
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

        rule compile
          command = mkdir -p $$(dirname $out) && $$CXX $flags -MMD -MF $out.d -c $in -o $out
          description = CXX $in
          depfile = $out.d
          deps = gcc

        rule archive
          command = mkdir -p $$(dirname $out) && ${archiveCommand} rcs $out $in
          description = AR $out

        rule link
          command = mkdir -p $$(dirname $out) && $$CXX $in $ldflags -o $out
          description = LINK $out

        rule copy_assets
          command = mkdir -p $$(dirname $out) build/bin && $copies && touch $out
          description = COPY_ASSETS $out

        build always_assets: phony

        ${lib.concatStringsSep "\n" (lib.mapAttrsToList targetRules expandedTargets)}

        default ${
          lib.concatStringsSep " " (map outputFor (lib.filter (t: t.type != "external") allTargets))
        }
      '';
in
  ninjaFile
