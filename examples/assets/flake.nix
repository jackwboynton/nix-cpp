{
  description = "nix-cpp assets example";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-cpp.url = "path:../..";
    nix-cpp.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-cpp,
    }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      projects = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          cpp = nix-cpp.lib.mkCpp pkgs;
        in
        cpp.project {
          name = "assets";
          src = ./.;
          cxxFlags = "-std=c++23 -O2";

          targets = {
            app = cpp.executable {
              name = "app";
              sources = [ "main.cpp" ];
              assets = [ "assets" ];
            };
          };
        }
      );
    in
    {
      packages = forAllSystems (system: {
        default = projects.${system};
      });

      devShells = forAllSystems (system: {
        default = projects.${system}.devShell;
      });

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          app = projects.${system};
        in
        {
          runtime = pkgs.runCommand "test-assets" { } ''
            test "$(${app}/bin/app)" = "HELLO"
            touch "$out"
          '';

          tests = app.tests;
        }
      );
    };
}
