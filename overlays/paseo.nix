# A nixpkgs overlay fragment (not a buildable package) exposing a patched paseo
# as `pkgs.dotfiles.paseo`. Upstream does not build as tagged, so two patches
# ride along. Both were re-verified against the pinned tag (v0.3.1) and v0.4.0
# in 2026-08, whose `nix/package.nix` files were byte-identical at the time --
# recheck rather than trust that on a bump. Neither patch has landed upstream.
{ inputs }:
final: prev:
let
  paseo =
    (final.callPackage "${inputs.paseo}/nix/package.nix" {
      # Every release tag ships a stale `nix/npm-deps.hash`. Two upstream
      # mechanics combine: `fetchNpmDeps` copies package-lock.json verbatim into
      # its fixed-output result, and the repair workflow that regenerates the
      # hash triggers on push to main -- rewriting `package-lock.json` itself
      # (its commit is "update lockfile signatures and Nix hash"), not just the
      # version strings -- and only lands *after* the release commit is tagged.
      # So a tag always points at the pre-repair state, and the mismatch can be
      # larger than a version bump would suggest (holds for v0.2.5, v0.3.0,
      # v0.3.1).
      #
      # Expect to re-point this at every bump rather than to drop it: take the
      # `got:` hash from the failing build. Overriding is safe either way --
      # package-lock.json's integrity fields pin the fetched contents
      # independently of this hash.
      #
      # One hash, two consumers: `mkPackages` exposes this under both
      # `inputs.nixpkgs` (x86_64-linux) and `inputs.nixpkgs-darwin`
      # (aarch64-darwin), so the value must satisfy both. It does today because
      # both pins resolve `prefetch-npm-deps` to the identical *source* over an
      # identical filtered `src` -- that, not the nixpkgs revision, is the
      # invariant. Verified by build on aarch64-darwin; x86_64-linux is gated by
      # CI (`checks.x86_64-linux.paseo`), and the darwin half only by whoever
      # runs `nix flake check` locally. If the two pins ever diverge, the `got:`
      # hash from *your* platform is not necessarily the right one for both.
      npmDepsHash = "sha256-oXz8hMk+5DlTYK8OndUAjB+RJMDbPqobVGXLFeoH++o=";
    }).overrideAttrs
      (old: {
        # scripts/trace-daemon.mjs walks the JS module graph, so node-pty's
        # prebuilt native binding never makes it into $out and every terminal
        # pane reports "Terminal worker not running". Upstream PR #3250 copies
        # the whole prebuilds/ tree; we copy only the host triple, because the
        # runtime loader keys strictly on prebuilds/<platform>-<arch> (node-pty
        # lib/utils.js) and the full tree is ~24MB of other platforms' binaries
        # -- ~21MB of it win32 debug symbols -- to deliver ~140KB.
        #
        # The guard is the notification: nothing else will tell us when #3250
        # (or a real trace fix) ships, and a plain `cp` would silently nest a
        # redundant prebuilds/ inside upstream's once it does.
        postInstall = (old.postInstall or "") + ''
          ptyDest="$out/lib/paseo/packages/server/node_modules/node-pty"
          if [ -e "$ptyDest/prebuilds" ]; then
            echo "paseo: upstream now ships node-pty prebuilds; drop this patch" >&2
            exit 1
          fi
          triple="$(node -p 'process.platform + "-" + process.arch')"
          mkdir -p "$ptyDest/prebuilds/$triple"
          cp -a "packages/server/node_modules/node-pty/prebuilds/$triple/." \
            "$ptyDest/prebuilds/$triple/"
        '';
      });
in
{
  # Extend (not clobber) the set `dotfilesOverlay` assigns. This overlay must
  # come after it in `defaultOverlays`.
  dotfiles = (prev.dotfiles or { }) // {
    inherit paseo;
  };
}
