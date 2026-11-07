{ pkgs, lib }:

{
  toolchain,
  usageFor,
  dependencyModulePath
}:

rec {

  hasModule = target: (target.module or null) != null;
  localModulePath = target: "build/modules/${target.module.name}.${toolchain.moduleExtension}";
  # Each module interface is built in its owning target. An ordinary source
  # can also import its own target's interface.
  moduleInputs = target: includeOwn:
    let
      dependencies = lib.unique (lib.tail (usageFor target));
      entries = lib.concatMap (dep:
        if hasModule dep then [ { inherit (dep.module) name; path = dependencyModulePath dep; } ]
        else dep.moduleFiles or [ ]
      ) dependencies ++ lib.optional (includeOwn && hasModule target) {
        inherit (target.module) name;
        path = localModulePath target;
      };
      unique = lib.unique entries;
      names = map (entry: entry.name) unique;
    in
    if lib.length names != lib.length (lib.unique names) then
      throw "cpp.project: conflicting module providers for '${target.name}'"
    else unique;

  moduleFlags = entries:
    if entries == [ ] then ""
    else if toolchain.stdenv.cc.isGNU or false then
      let
        mapper = pkgs.writeText "module-mapper" (lib.concatMapStrings (m: "${m.name} ${m.path}\n") entries);
        enable = if lib.versionAtLeast toolchain.stdenv.cc.version "16" then "-fmodules" else "-fmodules-ts";
      in "${enable} -fmodule-mapper=${mapper} -Mno-modules"
    else lib.escapeShellArgs (map (m: "-fmodule-file=${m.name}=${m.path}") entries);

  moduleObject = target: "build/obj/${target.name}/interface.o";
}
