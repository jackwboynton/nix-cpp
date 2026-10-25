# nix-cpp

Declarative C++ builds using Nix and Ninja, with Nix as the single source of truth for library and executable dependencies. Nixpkgs supplies dependencies and toolchains, while Ninja handles parallel and incremental compilation.

> [!WARNING]
> **Experimental
>
> nix-cpp is under active development. The public API is unstable and may change without notice. Not recommended for production use. 

## Example

```nix
let
  cpp = nix-cpp.lib.mkCpp pkgs;

  project = cpp.project {
    name = "example";
    src = ./.;
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
        dependencies = [ math pkgs.fmt ];
      };
    };
  };
in
{
  packages.${system}.default = project;
  devShells.${system}.default = project.devShell;
}
```

## Design principles

1. **One source of truth.** Build targets and dependencies are declared exclusively in Nix.
2. **Nixpkgs provides dependencies.** No separate package manager or dependency resolution system.
3. **Ninja is an execution detail.** Generated build files are not maintained manually.
4. **One build graph.** Hermetic builds and local development share the same target definitions.
5. **Minimal abstraction.** Prefer straightforward Nix expressions over another build configuration language.

## Status

Early development.

Currently supports C++ executables, static libraries, and internal dependency propagation.

External dependency adapters, broader platform support, and more advanced build features are inprogress.
