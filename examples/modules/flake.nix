{
  description = "nix-cpp modules example";

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
          name = "modules";
          src = ./.;
          cxxFlags = "-std=c++23";

          targets = rec {
            views = cpp.library {
              name = "views";
              sources = [ ];
              module = { name = "example.ui"; source = "ui.cppm"; };
            };

            app = cpp.executable {
              name = "app";
              sources = [ "main.cpp" ];
              private.dependencies = [ views ];
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
          modules = projects.${system};
        in
        {
          runtime = pkgs.runCommand "check-modules" { } ''
            ${modules}/bin/app
            touch "$out"
          '';
          dev-build = pkgs.runCommandCC "check-modules-dev-build" {
            nativeBuildInputs = modules.devShell.nativeBuildInputs ++ [ pkgs.jq ];
          } ''
            cp ${./ui.cppm} ui.cppm
            cp ${./main.cpp} main.cpp
            export CXX=${pkgs.stdenv.cc}/bin/c++
            compdb
            jq -e 'map(.file) | sort == ["main.cpp", "ui.cppm"]' compile_commands.json
            build app
            build/bin/app
            touch "$out"
          '';
        }
      );
    };
}
