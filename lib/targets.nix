{ lib }:

let
  # testSources expands to a sibling executable in project.
  library =
    {
      name,
      sources,
      dependencies ? [ ],
      includes ? [ ],
      definitions ? {
        public = [ ];
        private = [ ];
      },
      linkFlags ? [ ],
      testSources ? [ ],
    }:
    {
      type = "library";
      inherit
        name
        sources
        dependencies
        includes
        definitions
        linkFlags
        testSources
        ;
    };

  executable =
    {
      name,
      sources,
      dependencies ? [ ],
      includes ? [ ],
      definitions ? {
        public = [ ];
        private = [ ];
      },
      linkFlags ? [ ],
      testSources ? [ ],
      assets ? [ ],
    }:
    {
      type = "executable";
      inherit
        name
        sources
        dependencies
        includes
        definitions
        linkFlags
        testSources
        assets
        ;
    };

  external =
    {
      package,
      includes ? [ ],
      linkLibraries ? [ ],
      dependencies ? [ ],
      definitions ? {
        public = [ ];
        private = [ ];
      },
      pkgConfig ? [ (lib.getName package) ],
    }:
    {
      type = "external";
      inherit
        package
        includes
        linkLibraries
        dependencies
        definitions
        pkgConfig
        ;
    };
in
{
  inherit library executable external;
}
