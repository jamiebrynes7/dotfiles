{
  lib,
  stdenv,
  callPackage,
  fetchFromGitHub,
}:

let
  release = builtins.fromJSON (builtins.readFile ./hashes.json);

  src = fetchFromGitHub {
    owner = "getpaseo";
    repo = "paseo";
    rev = release.tag;
    hash = release.src.hash;
  };

  # IFD: importing a file out of `src` builds that fetch during *evaluation*, so
  # any config touching paseo needs network on a cold machine, and `nix flake
  # show`/`check` are no longer offline-pure. This is the only package here that
  # does it. Accepted deliberately — the FOD is small and deterministic, and
  # calling upstream's own package.nix is what keeps us from forking their source
  # filter and build phases. If it ever needs to go, the escape is to vendor a
  # copy of nix/package.nix into this directory and have update.sh refresh it.
  # Revisit before adding a second IFD package.
  #
  # npmDepsHash is an explicit argument upstream added for downstream flakes on a
  # different nixpkgs. The hash recorded at a release tag is reliably stale (the
  # workflow that repairs it lands on main *after* the tag), and ours has to be
  # computed against our own nixpkgs anyway, so update.sh owns it.
  daemon = callPackage "${src}/nix/package.nix" { inherit (release) npmDepsHash; };
in
daemon.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    # The signed upstream release bundle, not a local electron-builder run, and
    # deliberately not derived from `daemon` — a host that only wants the app
    # pays the eval-time source fetch and the release zip, never the npm build.
    #
    # Hung off passthru rather than living in its own packages/ directory so this
    # darwin-only artifact never enters flake.nix's package or check sets on
    # x86_64-linux. The throw is lazy: it fires only if something forces it.
    desktop =
      if stdenv.hostPlatform.system == "aarch64-darwin" then
        callPackage ./desktop.nix { inherit release; }
      else
        throw "pkgs.dotfiles.paseo.desktop is only available on aarch64-darwin";
  };
})
