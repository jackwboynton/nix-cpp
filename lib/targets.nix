{ lib }:

let
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
