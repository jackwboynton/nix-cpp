{ pkgs, cpp }:
let
  source = pkgs.writeTextDir "main.cpp" ''
    #include <vector>
    #include <zlib.h>
    int main() { return zlibVersion() == nullptr; }
  '';
  project = cpp.project {
    name = "iwyu-check";
    src = source;
    targets.app = cpp.executable {
      name = "app";
      sources = [ "main.cpp" ];
      private.dependencies = [ pkgs.zlib ];
      pkgConfig = [ "zlib" ];
    };
  };
in
pkgs.runCommandCC "check-iwyu"
  {
    nativeBuildInputs = project.devShell.nativeBuildInputs;
  }
  ''
    cp ${source}/main.cpp .
    if iwyu > missing.log 2>&1; then
      echo "iwyu unexpectedly succeeded without a compilation database" >&2
      exit 1
    fi
    grep -q 'Run compdb' missing.log

    compdb
    test -s build/deps/app.cflags.rsp
    test ! -e build/obj/app/0.o
    if iwyu main.cpp -- -Xiwyu --error=1 > report.log 2>&1; then
      echo "iwyu failed to report the unused include" >&2
      exit 1
    fi
    cat report.log
    grep -q 'main.cpp should remove these lines:' report.log
    grep -q '^- #include <vector>' report.log
    if grep -q 'error:' report.log; then
      cat report.log >&2
      exit 1
    fi
    cmp main.cpp ${source}/main.cpp
    touch "$out"
  ''
