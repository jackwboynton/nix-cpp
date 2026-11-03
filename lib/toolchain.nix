{ pkgs }:

{
  optimization ? 2,
  lto ? false,
}:

let
  #inherit (pkgs) lib;
  base = pkgs.stdenv;
  cc = base.cc;

  isClang = cc.isClang or false;
  isGcc = cc.isGNU or false;
  isDarwin = base.hostPlatform.isDarwin;

  optimizationFlag =
    if
      builtins.elem optimization [
        0
        1
        2
        3
        "s"
        "z"
      ]
    then
      "-O${toString optimization}"
    else
      throw "nix-cpp: invalid optimization level";

  ltoFlags =
    if !lto then
      [ ]
    else if isClang then
      [ "-flto=thin" ]
    else if isGcc then
      [ "-flto" ]
    else
      throw "nix-cpp: LTO is unsupported for this compiler";

  selectedCC =
    if lto && isClang && !isDarwin then
      cc.override {
        bintools = cc.cc.llvmPackages.bintools;
      }
    else
      cc;

  stdenv = pkgs.overrideCC base selectedCC;
in
{
  inherit stdenv;

  compileFlags = [ optimizationFlag ] ++ ltoFlags;
  linkFlags = [ optimizationFlag ] ++ ltoFlags;

  # GCC's wrappers load the compiler's LTO plugin when handling archives.
  archiveTool = if lto && isGcc then "gcc-ar" else "ar";
  ranlibTool = if lto && isGcc then "gcc-ranlib" else "ranlib";

  languageDefaults = {
    cxxFlags = "";
    objcFlags = "-fobjc-arc";
    objcxxFlags = "-fobjc-arc";
  };
}
