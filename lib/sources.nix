{ lib }:

{ src, usageFor }:
let
  root = if builtins.isPath src then src else /. + builtins.unsafeDiscardStringContext (toString src);
  rootString = toString root;
  pathString = path: if builtins.isPath path then "${path}" else toString path;

  relativePath = path:
    let
      value = pathString path;
    in
    if value == rootString then
      "."
    else if lib.hasPrefix "${rootString}/" value then
      builtins.unsafeDiscardStringContext (lib.removePrefix "${rootString}/" value)
    else if !(lib.hasPrefix "/" value) then
      value
    else
      null;

  pathFor = path:
    let relative = relativePath path;
    in if relative == null then pathString path else relative;

  internalPaths = paths:
    map (path: root + "/${path}") (
      lib.filter (path: path != null) (map relativePath paths)
    );

  headerFiles = path: lib.fileset.fileFilter (
    file: lib.any file.hasExt [ "h" "hh" "hpp" "hxx" "inc" "inl" "ipp" "tpp" "def" "cuh" ]
      || !(lib.hasInfix "." file.name)
  ) path;

  sourceFor = target:
    let
      related = lib.filter (t: t.type != "external") (usageFor target);
      sources = internalPaths target.sources;
      includes = target.includes ++ lib.concatMap (t: t.public.includes) (lib.tail related);
      headers = (target.private.headers or [ ])
        ++ lib.concatMap (t: t.public.headers or [ ]) related;
      testHeaders = internalPaths ((target.testOf or { }).sources or [ ]);
      adjacent = lib.unique (map builtins.dirOf (sources ++ testHeaders));
      assets = internalPaths (target.assets or [ ]);
    in
    lib.fileset.toSource {
      inherit root;
      fileset = lib.fileset.unions (
        sources
        ++ internalPaths headers
        ++ map headerFiles (internalPaths includes ++ adjacent)
        ++ assets
      );
    };
in
{
  inherit pathFor sourceFor;
}
