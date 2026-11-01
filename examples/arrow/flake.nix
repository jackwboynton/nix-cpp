{
  description = "nix-cpp arrow example";

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
          llvm = pkgs.llvmPackages;

          clang =
            if pkgs.stdenv.hostPlatform.isDarwin then
              llvm.clang
            else
              llvm.clang.override {
                bintools = llvm.bintools;
              };

          ltoStdenv = pkgs.stdenvAdapters.withCFlags [
            "-flto=thin"
          ] (pkgs.overrideCC pkgs.stdenv clang);

          ltoPkgs = pkgs // {
            stdenv = ltoStdenv;
            mkShell = pkgs.mkShell.override { stdenv = ltoStdenv; };
          };

          cpp = nix-cpp.lib.mkCpp ltoPkgs;
        in
        cpp.project {
          name = "arrow";
          src = ./.;
          cxxFlags = "-std=c++23 -O2";

          targets = {
            app = cpp.executable {
              name = "app";
              sources = [ "main.cpp" ];

              private.dependencies = [ pkgs.arrow-cpp ];
              pkgConfig = [ "arrow" ];
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
          runtime = pkgs.runCommand "test-arrow" { } ''
            test "$(${app}/bin/app)" = "Arrow array length: 3"
            touch "$out"
          '';
          tests = app.tests;
        }
      );
    };
}
