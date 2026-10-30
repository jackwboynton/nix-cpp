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
      pkgConfig ? [ ],
      linkLibraries ? [ ],
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
        pkgConfig
        linkLibraries
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
      pkgConfig ? [ ],
      linkLibraries ? [ ],
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
        pkgConfig
        linkLibraries
        testSources
        assets
        ;
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
    {
      type = "external";
      inherit
        package
        includes
        linkFlags
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
