{
  description = "nix-cpp install example";

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
        cpp.project rec {
          name = "install";
          src = ./.;
          cxxFlags = "-std=c++23 -O2";

          targets.lib = cpp.library {
            name = "lib";
            public = {
              headers = ./include;
              definitions = [ "INSTALL_API_VERSION=1" ];
            };
            private = {
              includes = [ "src" ];
              definitions = [ "INSTALL_IMPLEMENTATION" ];
            };
            sources = [ "src/lib.cpp" ];
          };

          targets.entrypoint = cpp.executable {
            name = "app";
            sources = [ "src/main.cpp" ];
            private.dependencies = [ targets.lib ];
          };
        }
      );

      # test how an external consumer would depend on projects.$system or the app target,
      # and build their own entrypoint.
      external = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          cpp = nix-cpp.lib.mkCpp pkgs;
        in
        cpp.project {
          name = "install";
          src = ./.;
          cxxFlags = "-std=c++23 -O2";

          targets.entrypoint = cpp.executable {
            name = "app";
            sources = [ "src/consumer.cpp" ];
            private.dependencies = [ projects.${system} ];
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
        external = external.${system}.devShell;
      });

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          app = projects.${system};
          externalApp = external.${system};
        in
        {
          runtime = pkgs.runCommand "check-install" { } ''
            test -f ${app}/include/lib/lib.hpp
            test -f ${app}/lib/liblib.a
            test ! -e ${app}/include/private.hpp
            test "$(${app}/bin/app)" = "lib: 42"
            touch "$out"
          '';

          externalConsumer = pkgs.runCommand "check-install-external-consumer" { } ''
            test "$(${externalApp}/bin/app)" = "external lib: 42"
            touch "$out"
          '';

        }
      );
    };
}
