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
    in
    {
      inherit type;
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
