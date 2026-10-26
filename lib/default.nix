{ pkgs }:

let
  targets = import ./targets.nix {
    inherit (pkgs) lib;
  };

  ninja = import ./ninja.nix {
    inherit pkgs;
    targetsLib = targets;
  };
in
targets // ninja
