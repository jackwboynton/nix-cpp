{
  description = "nix-cpp hello example";

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
          name = "hello";
          src = ./.;
          cxxFlags = "-std=c++23 -O2";

          targets.hello = cpp.executable {
            name = "hello";
            sources = [ "main.cpp" ];
          };
        }
      );

      emscriptenProjects = forAllSystems (
        system:
        let
          nativePkgs = nixpkgs.legacyPackages.${system};
          emPkgs = nativePkgs // {
            stdenv = nativePkgs.emscriptenStdenv;
          };
          cpp = nix-cpp.lib.mkCpp emPkgs;
        in
        (cpp.project {
          name = "hello";
          src = ./.;
          cxxFlags = "-std=c++23 -O2";

          targets.hello = cpp.executable {
            name = "hello";
            sources = [ "main.cpp" ];
          };
        }).overrideAttrs
          (old: {
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ nativePkgs.buildPackages.nodejs ];
            preBuild = (old.preBuild or "") + ''
              export CC="${nativePkgs.emscripten}/bin/emcc"
              export CXX="${nativePkgs.emscripten}/bin/em++"
              export AR="${nativePkgs.emscripten}/bin/emar"

              export EM_CACHE="$TMPDIR/emscripten-cache"
              mkdir -p "$EM_CACHE"
            '';

            checkPhase = "";
          })
      );

      # TODO(jack): only when pkgs.stdenv.hostPlatform.isLinux
      mingwProjects = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux.pkgsCross.mingwW64;
          cpp = nix-cpp.lib.mkCpp pkgs;
        in
        cpp.project {
          name = "hello-mingw";
          src = ./.;
          cxxFlags = "-std=c++23 -O2";

          targets.hello = cpp.executable {
            name = "hello";
            sources = [ "main.cpp" ];
            linkFlags = [
              "-static"
              "-lstdc++exp"
            ];
          };
        }
      );
    in
    {
      packages = forAllSystems (system: {
        default = projects.${system};
        emscripten = emscriptenProjects.${system};
        mingw = mingwProjects.${system};
      });

      devShells = forAllSystems (system: {
        default = projects.${system}.devShell;
        emscripten = emscriptenProjects.${system}.devShell;
        mingw = mingwProjects.${system};
      });

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          app = projects.${system};
          emscriptenApp = emscriptenProjects.${system};
        in
        {
          runtime = pkgs.runCommand "check-hello" { } ''
            test "$(${app}/bin/hello)" = "Hello from nix-cpp!"
            touch "$out"
          '';

          emscripten = pkgs.runCommand "check-hello" { } ''
            test "$(${pkgs.buildPackages.nodejs}/bin/node ${emscriptenApp}/bin/hello)" = "Hello from nix-cpp!"
            touch "$out"
          '';

        }
        // nixpkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          mingw =
            pkgs.runCommand "check-hello-mingw"
              {
                nativeBuildInputs = [ pkgs.wine64 ];
              }
              ''
                # The sandbox's TMPDIR may not be owned by the build user.
                # Wine requires a user-owned prefix (or parent to create it in).
                export HOME="$(mktemp -d "$TMPDIR/wine-home.XXXXXX")"
                export WINEPREFIX="$HOME/prefix"
                mkdir -m 700 "$WINEPREFIX"
                export WINEDEBUG=-all
                export WINEDLLOVERRIDES="mscoree,mshtml="

                # Wine emits Windows line endings; normalize before comparing.
                wine ${mingwProjects.${system}}/bin/hello.exe > hello-output
                test "$(tr -d '\r' < hello-output)" = "Hello from nix-cpp!"
                touch "$out"
              '';
        }
      );
    };
}
