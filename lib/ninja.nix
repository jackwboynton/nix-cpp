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
  dependencyModulePath ? (_dep: module: "build/modules/${module.name}.${toolchain.moduleExtension}"),
}:

let
  inherit (pkgs) lib;
  pathString = pathFor;

  compileFlags = lib.escapeShellArgs toolchain.compileFlags;
  linkFlags = lib.escapeShellArgs toolchain.linkFlags;
  archiveCommand =
    if toolchain.archiveTool == "gcc-ar" then
      lib.escapeShellArg "${lib.getBin toolchain.stdenv.cc.cc}/bin/${toolchain.stdenv.cc.targetPrefix}gcc-ar"
    else if toolchain.archiveTool == "llvm-ar" then
      lib.escapeShellArg "${lib.getBin toolchain.stdenv.cc.cc.llvmPackages.llvm}/bin/llvm-ar"
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

  compileDeps =
    target: entries:
    let
      paths =
        lib.unique (
          lib.concatMap (
            m: [ m.path ] ++ lib.optional (toolchain.stdenv.cc.isGNU or false) (modules.localModulePath m)
          ) entries
        )
        ++ lib.optional (pkgConfigFor target != [ ]) (pkgConfigFile "cflags" target);
    in
    lib.optionalString (paths != [ ]) " | ${lib.concatStringsSep " " paths}";

  modules = (import ./modules.nix { inherit pkgs lib; }) {
    inherit toolchain usageFor dependencyModulePath;
  };

  # GCC records relative paths to sibling BMIs; restore those paths for installed dependencies.
  stagedModules =
    if toolchain.stdenv.cc.isGNU or false then
      lib.unique (
        lib.concatMap (
          target: lib.filter (m: m.path != modules.localModulePath m) (modules.moduleInputs target [ ])
        ) allTargets
      )
    else
      [ ];

  moduleRules =
    target:
    lib.concatStringsSep "\n" (
      lib.imap0 (
        i: module:
        let
          imports = modules.moduleInputs target (lib.take i target.modules);
          bmi = modules.localModulePath module;
          isGcc = toolchain.stdenv.cc.isGNU or false;
          mappings =
            imports
            ++ lib.optional isGcc {
              inherit (module) name;
              path = bmi;
            };
        in
        ''
          build ${modules.moduleObject target i} | ${bmi}: compile_module ${pathString module.source}${compileDeps target imports}
            interface_flags = ${
              if isGcc then "-x c++" else "-x c++-module -fmodules-embed-all-files -fmodule-output=${bmi}"
            }
            flags = ${compileFlags} ${cxxFlags} ${flagsFor target} ${modules.moduleFlags mappings}${
              lib.optionalString (
                !isGcc
                && lib.elem module.name [
                  "std"
                  "std.compat"
                ]
              ) " -Wno-reserved-module-identifier"
            }
        ''
      ) (target.modules or [ ])
    );

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
          imports =
            if lib.hasSuffix ".m" path then [ ] else modules.moduleInputs target (target.modules or [ ]);
          languageFlags =
            if lib.hasSuffix ".mm" path then
              "${cxxFlags} ${objcxxFlags}"
            else if lib.hasSuffix ".m" path then
              objcFlags
            else
              cxxFlags;
        in
        ''
          build build/obj/${target.name}/${toString i}.o: compile ${path}${compileDeps target imports}
            flags = ${compileFlags} ${languageFlags} ${flagsFor target} ${modules.moduleFlags imports}
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

      inputs =
        objectsFor target
        ++ lib.imap0 (i: _: modules.moduleObject target i) (target.modules or [ ])
        ++ (if target.type == "executable" then libraries else [ ]);
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
      ${moduleRules target}
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

        rule compile
          command = $cxx $flags -MMD -MF $out.d -c $in -o $out
          description = CXX $in
          depfile = $out.d
          deps = gcc

        rule compile_module
          command = $cxx $flags $interface_flags -MMD -MF $out.d -c $in -o $out
          description = CXX_MODULE $in
          depfile = $out.d
          deps = gcc

        rule stage_module
          command = mkdir -p $$(dirname $out) && ln -sfn "$in" "$out"
          description = MODULE_PATH $out

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

        ${lib.concatMapStrings (m: ''
          build ${modules.localModulePath m}: stage_module ${m.path}
        '') stagedModules}

        ${lib.concatStringsSep "\n" (lib.mapAttrsToList targetRules expandedTargets)}


        default ${
          lib.concatStringsSep " " (map outputFor (lib.filter (t: t.type != "external") allTargets))
        }
      '';
in
{
  inherit ninjaFile;
  compdbDependencies =
    map (pkgConfigFile "cflags") (lib.filter (target: pkgConfigFor target != [ ]) allTargets)
    ++ lib.concatMap (target: map modules.localModulePath (target.modules or [ ])) allTargets
    ++ map modules.localModulePath stagedModules;

  # Configure Ninja from the active toolchain for both builds and Ninja tools.
  command = pkgs.buildPackages.writeShellScript "cpp-ninja" ''
    set -eu
    cxx=$(command -v "''${CXX:?CXX must be set}")
    printf 'cxx = %s\ninclude %s\n' "$cxx" ${ninjaFile} > build.ninja
    exec ${pkgs.buildPackages.ninja}/bin/ninja "$@"
  '';
}
