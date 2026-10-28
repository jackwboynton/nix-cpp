{ pkgs }:

let
  inherit (pkgs) lib;
  projectFor =
    compiler: linkFlags:
    let
      cpp = import ../lib {
        pkgs = pkgs // {
          stdenv = pkgs.stdenv // {
            cc = pkgs.stdenv.cc // {
              isClang = compiler == "clang";
              isGNU = compiler == "gcc";
            };
          };
        };
      };
    in
    cpp.project {
      name = "lto-parallelism";
      src = ../examples/hello;
      cxxFlags = "-std=c++23 -O2 ${if lib.elem "-flto=thin" linkFlags then "-flto=thin" else "-flto"}";
      targets.hello = cpp.executable {
        name = "hello";
        sources = [ "main.cpp" ];
        inherit linkFlags;
      };
    };
  flagsFor = compiler: flags: (projectFor compiler flags).ninjaFile.text;
  jobs = "$\${NIX_BUILD_CORES:-1}";
  nativeCompiler = if pkgs.stdenv.cc.isClang then "clang" else "gcc";
in
assert lib.hasInfix "-flto=${jobs}" (flagsFor "gcc" [ "-flto" ]);
assert lib.hasInfix "-flto-jobs=${jobs}" (flagsFor "clang" [ "-flto=thin" ]);
assert lib.hasInfix "-flto-jobs=${jobs}" (flagsFor "clang" [ "-flto" ]);
assert !(lib.hasInfix jobs (flagsFor "gcc" [ "-flto=2" ]));
assert !(lib.hasInfix jobs (flagsFor "clang" [ "-flto=thin" "-flto-jobs=2" ]));
assert !(lib.hasInfix jobs (flagsFor "clang" [ ]));
assert lib.hasInfix "-flto=${jobs}" (flagsFor "gcc" [ ]);
assert
  !(lib.hasInfix jobs (
    ((projectFor "gcc" [ ]).override { cxxFlags = "-std=c++23 -O2"; }).ninjaFile.text
  ));
assert
  lib.hasInfix "-flto=${jobs}" (
    ((projectFor "gcc" [ ]).override { cxxFlags = "-std=c++23 -O2 -flto=auto"; }).ninjaFile.text
  );
assert
  !(lib.hasInfix jobs (
    ((projectFor "gcc" [ ]).override { cxxFlags = "-std=c++23 -O2 -flto -fno-lto"; }).ninjaFile.text
  ));
assert !(lib.hasInfix jobs (flagsFor "gcc" [ "-flto" "-fno-lto" ]));
assert !(lib.hasInfix jobs (flagsFor "clang" [ "-flto" "-fno-lto" ]));
pkgs.runCommand "test-lto-parallelism" { } ''
  test "$(${projectFor nativeCompiler [ "-flto" ]}/bin/hello)" = "Hello from nix-cpp!"
  ${lib.optionalString pkgs.stdenv.cc.isClang ''
    test "$(${projectFor "clang" [ "-flto=thin" ]}/bin/hello)" = "Hello from nix-cpp!"
  ''}
  ${lib.optionalString pkgs.stdenv.cc.isGNU ''
    test "$(${projectFor "gcc" [ ]}/bin/hello)" = "Hello from nix-cpp!"
  ''}
  touch "$out"
''
