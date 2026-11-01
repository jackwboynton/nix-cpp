{
  description = "nix-cpp duckdb example";

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
          name = "duckdb";
          src = ./.;
          cxxFlags = "-std=c++20 -O2"; # duckdb doesnt support c++23

          targets = {
            app = cpp.executable {
              name = "app";
              sources = [ "main.cpp" ];
              private.dependencies = [ pkgs.duckdb ];
              linkLibraries = [ "duckdb" ];
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
          runtime = pkgs.runCommand "test-duckdb" { } ''
            test "$(${app}/bin/app)" = "42"
            touch "$out"
          '';
          tests = app.tests;
        }
      );
    };
}
