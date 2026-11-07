{ pkgs, lib }:

{
  toolchain,
  usageFor,
  dependencyModulePath,
}:

rec {

  moduleFile = module: "${module.name}.${toolchain.moduleExtension}";
  localModulePath = module: "build/modules/${moduleFile module}";
  # Interfaces receive earlier units; ordinary sources receive all owning units.
  moduleInputs =
    target: ownModules:
    let
      dependencies = lib.unique (lib.tail (usageFor target));
      entries =
        lib.concatMap (
          dep:
          if (dep.modules or [ ]) != [ ] then
            map (module: {
              inherit (module) name;
              path = dependencyModulePath dep module;
            }) dep.modules
          else
            dep.moduleFiles or [ ]
        ) dependencies
        ++ map (module: {
          inherit (module) name;
          path = localModulePath module;
        }) ownModules;
      unique = lib.unique entries;
      names = map (entry: entry.name) unique;
    in
    if lib.length names != lib.length (lib.unique names) then
      throw "cpp.project: conflicting module providers for '${target.name}'"
    else
      unique;

  moduleFlags =
    entries:
    if entries == [ ] then
      ""
    else if toolchain.stdenv.cc.isGNU or false then
      let
        mapper = pkgs.writeText "module-mapper" (lib.concatMapStrings (m: "${m.name} ${m.path}\n") entries);
        enable =
          if lib.versionAtLeast toolchain.stdenv.cc.version "16" then "-fmodules" else "-fmodules-ts";
      in
      "${enable} -fmodule-mapper=${mapper} -Mno-modules"
    else
      lib.escapeShellArgs (map (m: "-fmodule-file=${m.name}=${m.path}") entries);

  moduleObject = target: i: "build/obj/${target.name}/interface-${toString i}.o";
}
