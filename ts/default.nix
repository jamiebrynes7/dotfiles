# A nixpkgs overlay fragment (not a buildable package) holding the build + check
# wiring for the repo-local paseo plugins under ts/. Imported into `flake.nix`'s
# `defaultOverlays`; exports the `buildPaseoPlugin` helper and
# `dotfiles.internal.tsChecks`.
final: prev:
let
  inherit (final) lib;

  paseoVersion = (lib.importJSON ../packages/paseo/hashes.json).version;

  pluginNames = lib.attrNames (
    lib.filterAttrs (name: type: type == "directory" && lib.hasPrefix "paseo-plugin-" name) (
      builtins.readDir ./.
    )
  );

  # Flake source already drops the gitignored node_modules; this covers a `path:`
  # eval of a working tree that has run `npm install`.
  pluginSource =
    src:
    lib.fileset.toSource {
      root = src;
      fileset = lib.fileset.difference src (lib.fileset.maybeMissing (src + "/node_modules"));
    };

  # npm only appears here, never in the shipped plugin, so a type error makes one
  # check red instead of making the plugin unbuildable. importNpmLock fetches each
  # dependency by the lockfile's own integrity hash, so there is no npmDepsHash to
  # re-pin on every lockfile change.
  typecheck =
    name: src:
    final.buildNpmPackage {
      pname = "${name}-typecheck";
      version = "0.0.0";
      src = pluginSource src;
      npmDeps = final.importNpmLock { npmRoot = src; };
      npmConfigHook = final.importNpmLock.npmConfigHook;
      buildPhase = ''
        runHook preBuild
        npm run typecheck
        runHook postBuild
      '';
      installPhase = "touch $out";
    };

  # The SDK is host-supplied at runtime, so a devDependency that drifts from the
  # pinned daemon typechecks against an API the host does not have. The lockfile is
  # checked too: importNpmLock installs from it without `npm ci`'s agreement check,
  # so a package.json bump without `npm install` would typecheck the old SDK.
  # Decided at eval, but failed as a build so one check goes red, not the flake eval.
  sdkVersion =
    name: src:
    let
      sdk = "@getpaseo/plugin";
      manifest = lib.importJSON (src + "/package.json");
      lock = lib.importJSON (src + "/package-lock.json");
      found = {
        "package.json devDependency" = manifest.devDependencies.${sdk} or "(none)";
        "package-lock.json devDependency" = lock.packages."".devDependencies.${sdk} or "(none)";
        "package-lock.json resolved version" = lock.packages."node_modules/${sdk}".version or "(none)";
      };
      wrong = lib.filterAttrs (_: version: version != paseoVersion) found;
    in
    final.runCommandLocal "${name}-sdk-version" { } (
      if wrong == { } then
        "touch $out"
      else
        ''
          ${lib.concatStrings (
            lib.mapAttrsToList (where: version: ''
              echo "ts/${name}: ${sdk} ${where} is ${version}, but packages/paseo pins ${paseoVersion}." >&2
            '') wrong
          )}
          echo "Pin it to exactly ${paseoVersion} in package.json and run npm install." >&2
          exit 1
        ''
    );

  tsChecks = lib.mergeAttrsList (
    map (
      name:
      let
        src = ./. + "/${name}";
      in
      {
        "${name}-typecheck" = typecheck name src;
        "${name}-sdk-version" = sdkVersion name src;
      }
    ) pluginNames
  );
in
{
  # A plain copy: the daemon compiles directory plugins itself (esbuild, write: false)
  # and supplies `@getpaseo/plugin*` at load, so there is nothing to build or install.
  buildPaseoPlugin =
    { pname, src }:
    final.runCommandLocal pname { } ''
      cp -r ${pluginSource src} $out
    '';

  # Extend (not clobber) dotfiles.internal, as crates/ does.
  dotfiles = (prev.dotfiles or { }) // {
    internal = (prev.dotfiles.internal or { }) // {
      inherit tsChecks;
    };
  };
}
