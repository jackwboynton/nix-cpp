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
                includes = [ "inc" ];
              };

              app = cpp.executable {
                name = "app";
                sources = [ "main.cpp" ];
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
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);

    };
}
