{ pkgs }:

let
  targets = import ./targets.nix {
    inherit (pkgs) lib;
  };

  project = import ./project.nix {
    inherit pkgs;
    targetsLib = targets;
  };
in
targets // project
