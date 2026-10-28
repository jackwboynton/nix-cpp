{ pkgs }:

let
  cpp = import ../lib { inherit pkgs; };
  project = cpp.project {
    name = "test-phase";
    src = pkgs.writeTextDir "test.cpp" ''
      #include <fstream>
      int main() {
        std::ofstream marker("test-ran");
        marker << "ran";
        return marker.good() ? 0 : 1;
      }
    '';
    cxxFlags = "-std=c++23 -O2";
    targets.example = cpp.library {
      name = "example";
      sources = [ ];
      testSources = [ "test.cpp" ];
    };
  };
in
assert project.doCheck;
assert !((project.override { targets.example.testSources = [ ]; }).doCheck);
project.overrideAttrs {
  preCheck = ''
    test ! -e test-ran
    touch pre-check-ran
  '';
  postCheck = ''
    test -e pre-check-ran
    test "$(<test-ran)" = ran
    touch post-check-ran
  '';
  preInstall = ''
    test -e post-check-ran
  '';
}
