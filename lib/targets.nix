{ lib }:

let
  scope = value: {
    includes = value.includes or [ ];
    definitions = value.definitions or [ ];
    dependencies = value.dependencies or [ ];
    headers = value.headers or [ ];
  };

  target =
    type:
    args@{
      name,
      sources,
      module ? null,
      modules ? [ ],
      public ? { },
      private ? { },
      linkFlags ? [ ],
      pkgConfig ? [ ],
      linkLibraries ? [ ],
      testSources ? [ ],
      assets ? [ ],
    }:
    let
      public = scope (args.public or { });
      private = scope (args.private or { });
      headers = value: if builtins.isList value then value else [ value ];
      declaredModules =
        if module != null && modules != [ ] then
          throw "cpp.project: use either module or modules, not both"
        else
          lib.optional (module != null) module ++ modules;
      checkedModules = map (
        m:
        if type != "library" then
          throw "cpp.project: only libraries can export modules"
        else if builtins.match "[a-zA-Z_][a-zA-Z0-9_]*([.][a-zA-Z_][a-zA-Z0-9_]*)*" m.name == null then
          throw "cpp.project: invalid module name '${m.name}'"
        else if builtins.elem m.source sources then
          throw "cpp.project: module.source is already in sources"
        else
          m
      ) declaredModules;
      moduleNames = map (m: m.name) checkedModules;
    in
    {
      inherit type;
      modules =
        if lib.length moduleNames != lib.length (lib.unique moduleNames) then
          throw "cpp.project: module names must be unique within a target"
        else
          checkedModules;
      inherit (args) name sources;
      public = public // {
        includes = public.includes ++ headers public.headers;
        headers = headers public.headers;
      };
      private = private // {
        includes = private.includes ++ headers private.headers;
        headers = headers private.headers;
      };
      dependencies = public.dependencies ++ private.dependencies;
      includes = public.includes ++ private.includes ++ headers public.headers ++ headers private.headers;
      definitions = {
        public = public.definitions;
        private = private.definitions;
      };
      linkFlags = args.linkFlags or [ ];
      pkgConfig = args.pkgConfig or [ ];
      linkLibraries = args.linkLibraries or [ ];
      testSources = args.testSources or [ ];
    }
    // lib.optionalAttrs (type == "executable") {
      assets = args.assets or [ ];
    };

  external =
    {
      package,
      includes ? [ ],
      linkLibraries ? [ ],
      linkFlags ? [ ],
      dependencies ? [ ],
      definitions ? {
        public = [ ];
        private = [ ];
      },
      pkgConfig ? [ ],
    }:
    let
      usage = package.cppUsage or { };
    in
    {
      type = "external";
      inherit package;
      moduleFiles = usage.moduleFiles or [ ];
      includes = (usage.includes or [ ]) ++ includes;
      linkFlags = (usage.linkFlags or [ ]) ++ linkFlags;
      linkLibraries = (usage.linkLibraries or [ ]) ++ linkLibraries;
      dependencies = (usage.dependencies or [ ]) ++ dependencies;
      definitions = {
        public = (usage.definitions.public or [ ]) ++ (definitions.public or [ ]);
        private = definitions.private or [ ];
      };
      pkgConfig = (usage.pkgConfig or [ ]) ++ pkgConfig;
    };
in
{
  library = target "library";
  executable = target "executable";
  inherit external;
}
