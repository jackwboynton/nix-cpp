{ lib, external }:

{ targets, targetAliases }:

let
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

      # Compile usage traverses public edges only after the first hop. Static
      # linking still needs the complete dependency graph, including private edges.
      publicClosure =
        dependency:
        let
          target = normalize dependency;
        in
        lib.optional (!(target.linkOnly or false)) target
        ++ lib.concatMap publicClosure (
          if target.linkOnly or false then
            [ ]
          else if target ? public then
            target.public.dependencies
          else
            target.dependencies
        );

      usageFor = target: [ target ] ++ lib.concatMap publicClosure target.dependencies;

      dependenciesFor = target: lib.tail (closure target);

      externalDependencies = lib.filter (dep: dep.type == "external") (lib.concatMap closure allTargets);

      externalPackages = lib.unique (map (dep: dep.package) externalDependencies);

in
{
  inherit
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
}
