{
  description = "nix-cpp Objective-C example";

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
      systems = [ "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      projects = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          cpp = nix-cpp.lib.mkCpp pkgs;
        in
        cpp.project {
          name = "objective_c";
          src = ./.;
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
          runtime = pkgs.runCommand "test-objective-c" { } ''
            ${app}/bin/app 2>&1 | grep -q 'Hello from Objective-C!'
            touch "$out"
          '';

          tests = app.tests;
        }
      );
    };
}
