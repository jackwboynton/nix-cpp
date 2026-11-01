{
  description = "Nix-native C++ build definitions";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];
      forAllSystems = lib.genAttrs systems;

      exampleNames = [
        "hello"
        "install"
        "arrow"
        "assets"
        "duckdb"
        "external-dependencies"
        "libraries"
        "link_order"
        "objective_c"
      ];

      examples = lib.genAttrs exampleNames (
        name:
        let
          example = import ./examples/${name}/flake.nix;
          outputs = example.outputs {
            inherit nixpkgs;
            nix-cpp = self;
            self = outputs // {
              outPath = ./examples/${name};
            };
          };
        in
        outputs
      );
    in
    {
      lib.mkCpp = pkgs: import ./lib { inherit pkgs; };

      checks = forAllSystems (
        system:
        lib.foldlAttrs (
          checks: name: example:
          checks
          // lib.mapAttrs' (checkName: check: lib.nameValuePair "${name}-${checkName}" check) (
            example.checks.${system} or { }
          )
        ) { } examples
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
