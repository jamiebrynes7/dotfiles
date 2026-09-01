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

  # node-pty names its prebuilt-addon directory with node's own `process.platform`
  # and `process.arch` spellings, which are not nixpkgs' spellings.
  nodePlatform = if stdenv.hostPlatform.isDarwin then "darwin" else "linux";
  nodeArch = if stdenv.hostPlatform.isAarch64 then "arm64" else "x64";
in
daemon.overrideAttrs (old: {
  # Ship node-pty's native addon, which upstream's build drops on the floor.
  #
  # Upstream computes the daemon's runtime closure with @vercel/nft, and because
  # nft cannot trace node-pty's runtime-computed `require`, its trace script
  # (scripts/trace-daemon.mjs) copies the addon via an explicit glob rooted at
  # `node_modules/node-pty/prebuilds/<plat>-<arch>`. npm does not hoist node-pty
  # to the workspace root, though -- it resolves under packages/server -- so that
  # glob matches nothing and $out ships no pty.node at all.
  #
  # The failure is quiet and easy to misread: the addon is only required by the
  # forked terminal worker, so the daemon starts, serves the UI and runs agents
  # normally while the worker dies on require. Every terminal then fails with
  # "Terminal worker is not running", which reads like a runtime/permissions
  # problem rather than a missing file.
  #
  # Copy it from where npm actually put it. The prebuilt binary is the right
  # artifact to ship despite upstream's `npm rebuild node-pty`: node-pty's
  # install script is `node scripts/prebuild.js || node-gyp rebuild`, and
  # prebuild.js exits 0 as soon as it sees the prebuilds directory the npm
  # tarball already ships, so node-gyp never runs and build/Release is never
  # created. Copy the whole platform directory rather than pty.node alone --
  # darwin also needs the spawn-helper binary that sits beside it, which
  # unixTerminal.js resolves relative to the addon it loaded.
  #
  # autoPatchelfHook, already wired up upstream with libuv in buildInputs, fixes
  # the prebuilt binary's interpreter and rpath during fixupPhase. It never had
  # anything to do here before, since the file it exists for never reached $out.
  postInstall = (old.postInstall or "") + ''
    ptyDir=packages/server/node_modules/node-pty
    prebuild="$ptyDir/prebuilds/${nodePlatform}-${nodeArch}"

    # Fail loudly rather than shipping another daemon whose terminals are broken:
    # this path is upstream's to change, and the symptom is far from the cause.
    if [ ! -f "$prebuild/pty.node" ]; then
      echo "paseo: no node-pty addon at $prebuild/pty.node" >&2
      echo "paseo: node-pty's layout changed upstream; terminals would silently break." >&2
      exit 1
    fi

    mkdir -p "$out/lib/paseo/$ptyDir/prebuilds"
    cp -a "$prebuild" "$out/lib/paseo/$prebuild"
  '';

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
