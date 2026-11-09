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
      exampleSource = nixpkgs.lib.cleanSourceWith {
        src = ./.;
        filter = path: _: builtins.baseNameOf path != "build";
      };

      projects = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          cpp = nix-cpp.lib.mkCpp pkgs;
        in
        cpp.project {
          name = "modules";
          src = exampleSource;
          cxxFlags = "-std=c++23 -Wall -Wextra -Werror";

          targets = rec {
            stdLibrary = cpp.library {
              name = "std-library";
              sources = [ ];
              module = {
                name = "std";
                source =
                  if pkgs.stdenv.cc.isGNU or false then
                    "${pkgs.stdenv.cc.cc}/include/c++/${pkgs.stdenv.cc.version}/bits/std.cc"
                  else
                    "${
                      pkgs."llvmPackages_${nixpkgs.lib.versions.major pkgs.stdenv.cc.libcxx.version}".libcxx
                    }/share/libc++/v1/std.cppm";
              };
              testSources = [ "std-main.cpp" ];
            };

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
            src = exampleSource;
            cxxFlags = "-std=c++23";
            targets = {
              app = cpp.executable {
                name = "app";
                sources = [ "main.cpp" ];
                private.dependencies = [ modules ];
              };
              stdApp = cpp.executable {
                name = "std-app";
                sources = [ "std-main.cpp" ];
                private.dependencies = [ modules ];
              };
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
            ${modules}/bin/std-library-tests
            touch "$out"
          '';
          installed-consumer =
            pkgs.runCommandCC "check-installed-modules"
              {
                nativeBuildInputs = consumer.devShell.nativeBuildInputs;
              }
              ''
                ${consumer}/bin/app
                ${consumer}/bin/std-app
                cp ${./main.cpp} main.cpp
                cp ${./std-main.cpp} std-main.cpp
                export CXX=${pkgs.stdenv.cc}/bin/c++
                compdb
                build -j4 app stdApp
                build/bin/app
                build/bin/std-app
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
                cp ${./std-main.cpp} std-main.cpp
                export CXX=${pkgs.stdenv.cc}/bin/c++
                compdb
                jq -e 'map(.file | split("/") | last) | unique | sort == (["base.cppm", "main.cpp", "std-main.cpp", "${
                  if pkgs.stdenv.cc.isGNU or false then "std.cc" else "std.cppm"
                }", "theme.cppm", "traits.cppm", "ui.cppm"] | sort)' compile_commands.json
                build -j4 app views-tests std-library-tests
                build/bin/app
                build/bin/views-tests
                build/bin/std-library-tests
                touch "$out"
              '';
        }
      );
    };
}
