{
  description = "nix-cpp libraries example";

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
          name = "libraries";
          src = ./.;
          cxxFlags = "-std=c++23";
          optimization = 3;
          lto = true;

          targets = rec {
            math = cpp.library {
              name = "math";
              sources = [ "math.cpp" ];
              testSources = [ "math_tests.cpp" ];
              public.includes = [ "inc" ];
              public.definitions = [ "MATH_PUBLIC=42" ];
              private.definitions = [ "MATH_PRIVATE=1234" ];
            };

            app = cpp.executable {
              name = "app";
              sources = [ "main.cpp" ];
              testSources = [ "app_tests.cpp" ];
              private.dependencies = [ math ];
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
          libraries = projects.${system};
        in
        {
          runtime = pkgs.runCommand "check-libraries" { } ''
            test "$(${libraries}/bin/app)" = "add(20, 22) = 42"
            touch "$out"
          '';
          tests = libraries.tests;
        }
      );
    };
}
