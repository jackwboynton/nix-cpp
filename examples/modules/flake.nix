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
            base = cpp.library {
              name = "base";
              sources = [ ];
              module = {
                name = "example.base";
                source = "base.cppm";
              };
            };

            views = cpp.library {
              name = "views";
              sources = [ ];
              modules = [
                {
                  name = "example.theme";
                  source = "theme.cppm";
                }
                {
                  name = "example.traits";
                  source = "traits.cppm";
                }
                {
                  name = "example.ui";
                  source = "ui.cppm";
                }
              ];
              public.dependencies = [ base ];
              testSources = [ "main.cpp" ];
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
          cpp = nix-cpp.lib.mkCpp pkgs;
          consumer = cpp.project {
            name = "modules-consumer";
            src = ./.;
            cxxFlags = "-std=c++23";
            targets.app = cpp.executable {
              name = "app";
              sources = [ "main.cpp" ];
              private.dependencies = [ modules ];
            };
          };
          rejects = args: !(builtins.tryEval (builtins.deepSeq (cpp.library args) true)).success;
          unit = {
            name = "example.ui";
            source = "ui.cppm";
          };
        in
        {
          runtime = pkgs.runCommand "check-modules" { } ''
            ${modules}/bin/app
            ${modules}/bin/views-tests
            touch "$out"
          '';
          installed-consumer = pkgs.runCommandCC "check-installed-modules" {
            nativeBuildInputs = consumer.devShell.nativeBuildInputs;
          } ''
            ${consumer}/bin/app
            cp ${./main.cpp} main.cpp
            export CXX=${pkgs.stdenv.cc}/bin/c++
            compdb
            build -j4 app
            build/bin/app
            touch "$out"
          '';
          validation =
            assert rejects {
              name = "invalid";
              sources = [ ];
              modules = [
                unit
                unit
              ];
            };
            assert rejects {
              name = "invalid";
              sources = [ ];
              module = unit;
              modules = [ unit ];
            };
            assert rejects {
              name = "invalid";
              sources = [ "ui.cppm" ];
              modules = [ unit ];
            };
            assert rejects {
              name = "invalid";
              sources = [ ];
              modules = [
                {
                  name = "bad-name";
                  source = "ui.cppm";
                }
              ];
            };
            assert
              !(builtins.tryEval (
                builtins.deepSeq (cpp.executable {
                  name = "invalid";
                  sources = [ ];
                  modules = [ unit ];
                }) true
              )).success;
            pkgs.runCommand "check-module-validation" { } ''touch "$out"'';
          dev-build =
            pkgs.runCommandCC "check-modules-dev-build"
              {
                nativeBuildInputs = modules.devShell.nativeBuildInputs ++ [ pkgs.jq ];
              }
              ''
                cp ${./base.cppm} base.cppm
                cp ${./theme.cppm} theme.cppm
                cp ${./traits.cppm} traits.cppm
                cp ${./ui.cppm} ui.cppm
                cp ${./main.cpp} main.cpp
                export CXX=${pkgs.stdenv.cc}/bin/c++
                compdb
                jq -e 'map(.file) | unique | sort == ["base.cppm", "main.cpp", "theme.cppm", "traits.cppm", "ui.cppm"]' compile_commands.json
                build -j4 app views-tests
                build/bin/app
                build/bin/views-tests
                touch "$out"
              '';
        }
      );
    };
}
