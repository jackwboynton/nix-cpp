{
  description = "Nix-native C++ build definitions";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      examplesFor =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          cpp = self.lib.mkCpp pkgs;
        in
        {
          hello = cpp.project {
            name = "hello";
            src = ./examples/hello;
            cxxFlags = "-std=c++23 -O2";

            targets = {
              hello = cpp.executable {
                name = "hello";
                sources = [ "main.cpp" ];
              };
            };
          };

          libraries = cpp.project {
            name = "libraries";
            src = ./examples/libraries;
            cxxFlags = "-std=c++23 -O2";

            targets = rec {
              math = cpp.library {
                name = "math";
                sources = [ "math.cpp" ];
                testSources = [ "math_tests.cpp" ];
                includes = [ "inc" ];

                definitions = {
                  public = [ "MATH_PUBLIC=42" ];
                  private = [ "MATH_PRIVATE=1234" ];
                };
              };

              app = cpp.executable {
                name = "app";
                sources = [ "main.cpp" ];
                testSources = [ "app_tests.cpp" ];
                dependencies = [ math ];
              };
            };
          };

          external-dependencies = cpp.project {
            name = "external-dependencies";
            src = ./examples/external-dependencies;
            cxxFlags = "-std=c++23 -O2";

            targets = {
              app = cpp.executable {
                name = "app";
                sources = [ "main.cpp" ];
                dependencies = [ pkgs.fmt ];
              };
            };
          };

          arrow = cpp.project {
            name = "arrow";
            src = ./examples/arrow;
            cxxFlags = "-std=c++23 -O2";

            targets = {
              app = cpp.executable {
                name = "app";
                sources = [ "main.cpp" ];

                dependencies = [
                  (cpp.external {
                    package = pkgs.arrow-cpp;
                    pkgConfig = [ "arrow" ];
                  })
                ];
              };
            };
          };

          duckdb = cpp.project {
            name = "duckdb";
            src = ./examples/duckdb;
            cxxFlags = "-std=c++20 -O2"; # duckdb doesnt support c++23

            targets = {
              app = cpp.executable {
                name = "app";
                sources = [ "main.cpp" ];
                dependencies = [
                  (cpp.external {
                    package = pkgs.duckdb;
                    pkgConfig = [ ];
                    linkLibraries = [ "-lduckdb" ];
                  })
                ];
              };
            };
          };

          link_order = cpp.project {
            name = "link_order";
            src = ./examples/link_order;
            cxxFlags = "-std=c++23 -O2";
            targets = rec {
              core = cpp.library {
                name = "core";
                sources = [ "core.cpp" ];
              };
              plugin = cpp.library {
                name = "plugin";
                sources = [ "plugin.cpp" ];
                dependencies = [ core ];
              };
              app = cpp.executable {
                name = "app";
                sources = [ "main.cpp" ];
                dependencies = [
                  core
                  plugin
                ];
              };
            };
          };

          hello-emscripten =
            let
              emPkgs = pkgs // {
                stdenv = pkgs.emscriptenStdenv;
              };

              emCpp = self.lib.mkCpp emPkgs;
            in
            (emCpp.project {
              name = "hello-emscripten";
              src = ./examples/hello;
              cxxFlags = "-std=c++23 -O2";

              targets = {
                hello = emCpp.executable {
                  name = "hello";
                  sources = [ "main.cpp" ];
                };
              };
            }).overrideAttrs
              (old: {
                nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
                  pkgs.buildPackages.nodejs
                ];

                preBuild = (old.preBuild or "") + ''
                  			export CC="${pkgs.emscripten}/bin/emcc"
                  			export CXX="${pkgs.emscripten}/bin/em++"
                  			export AR="${pkgs.emscripten}/bin/emar"

                  			export EM_CACHE="$TMPDIR/emscripten-cache"
                  			mkdir -p "$EM_CACHE"
                  		'';

                checkPhase = ''
                        runHook preCheck

                  			ls -lah build/bin
                  			file build/bin/*
                  			echo "CXX=$CXX"

                  			test "$(node build/bin/hello)" = "Hello from nix-cpp!"

                        runHook postCheck
                '';
              });

        }
        // nixpkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
          objective_c = cpp.project {
            name = "objective_c";
            src = ./examples/objective_c;
            cxxFlags = "-std=c++23 -O2";
            objcFlags = "-O2 -fobjc-arc";
            objcxxFlags = "-fobjc-arc";
            targets = {
              app = cpp.executable {
                name = "app";
                sources = [ "main.m" ];
                linkFlags = [
                  "-framework Foundation"
                ];
              };
            };
          };

        }
        // nixpkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {

          hello-mingw =
            let
              pkgs = nixpkgs.legacyPackages.x86_64-linux.pkgsCross.mingwW64;
              cpp = self.lib.mkCpp pkgs;
            in
            cpp.project {
              name = "hello-mingw";
              src = ./examples/hello;
              cxxFlags = "-std=c++23 -O2";

              targets = {
                hello = cpp.executable {
                  name = "hello";
                  sources = [ "main.cpp" ];

                  linkFlags = nixpkgs.lib.optionals pkgs.stdenv.hostPlatform.isMinGW [
                    "-lstdc++exp"
                  ];
                };
              };
            };
        };
    in
    {
      lib.mkCpp = pkgs: import ./lib { inherit pkgs; };

      packages = forAllSystems examplesFor;

      devShells = forAllSystems (
        system: nixpkgs.lib.mapAttrs (_: project: project.devShell) (examplesFor system)
      );

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          examples = examplesFor system;
        in
        {
          hello =
            pkgs.runCommand "test-hello"
              {
                nativeBuildInputs = [ examples.hello ];
              }
              ''
                test "$(hello)" = "Hello from nix-cpp!"
                touch "$out"
              '';

          libraries =
            pkgs.runCommand "test-libraries"
              {
                nativeBuildInputs = [ examples.libraries ];
              }
              ''
                test "$(app)" = "add(20, 22) = 42"
                touch "$out"
              '';

          libraries-tests = examples.libraries.tests;

          external-dependencies =
            pkgs.runCommand "test-external-dependencies"
              {
                nativeBuildInputs = [ examples.external-dependencies ];
              }
              ''
                test "$(app)" = "Hello from fmt!"
                touch "$out"
              '';

          arrow =
            pkgs.runCommand "test-arrow"
              {
                nativeBuildInputs = [ examples.arrow ];
              }
              ''
                test "$(app)" = "Arrow array length: 3"
                touch "$out"
              '';

          duckdb =
            pkgs.runCommand "test-duckdb"
              {
                nativeBuildInputs = [ examples.duckdb ];
              }
              ''
                test "$(app)" = "42"
                touch "$out"
              '';

          link_order =
            pkgs.runCommand "test-link-order"
              {
                nativeBuildInputs = [ examples.link_order ];
              }
              ''
                test "$(app)" = "42"
                touch "$out"
              '';

        }
        // nixpkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {

          objective_c =
            pkgs.runCommand "test-objective-c"
              {
                nativeBuildInputs = [ examples.objective_c ];
              }
              ''
                app 2>&1 | grep -q 'Hello from Objective-C!'
                touch "$out"
              '';

        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);

    };
}
