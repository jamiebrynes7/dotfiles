# A nixpkgs overlay fragment (not a buildable package) holding the Rust build +
# check wiring for the workspace. Imported into `flake.nix`'s `defaultOverlays`;
# exports the `buildLocalRustBin` helper and `dotfiles.internal.{rustToolchain,rustChecks}`.
{ inputs }:
final: prev:
let
  # rust-overlay applied to `prev` so `rust-bin.*` doesn't leak into consumer
  # pkgs and to avoid `final` recursion.
  rustyPkgs = prev.appendOverlays [ inputs.rust-overlay.overlays.default ];

  # Bare `default` profile (rustc, cargo, clippy, rustfmt) used to build packages.
  # The `rust-src` extension lays down a `lib/rustlib/src/rust/library` tree in the
  # toolchain store path; compiled binaries embed those source paths
  # (panic/debuginfo metadata), so Nix's scanner records the whole toolchain as a
  # runtime dep. Excluding `rust-src` here removes the only such reference, keeping
  # it out of the package's runtime closure.
  buildToolchain = rustyPkgs.rust-bin.stable.latest.default;
  # devShell toolchain: build toolchain plus dev-only extensions.
  rustToolchain = buildToolchain.override {
    extensions = [
      "rust-src"
      "rust-analyzer"
    ];
  };

  # crane, pinned to the bare `buildToolchain` (not the fat devShell `rustToolchain`)
  # so dev-only extensions stay out of the package closure. `rustfmt` and `clippy`
  # are in the `default` profile, so the fmt/clippy checks work without extra
  # components.
  craneLib = (inputs.crane.mkLib final).overrideToolchain buildToolchain;

  # Args shared by the package build, its dependency-only artifact cache, and the
  # clippy/test checks — so cargo deps compile once and every derivation reuses the
  # same `cargoArtifacts`.
  commonArgs = {
    # The root Cargo.toml is a virtual workspace manifest (`[workspace]`, no
    # `[package].name`), so crane can't infer a crate name for the deps cache /
    # checks and warns while substituting a placeholder. Naming the shared args
    # explicitly silences that. `buildLocalRustBin` overrides pname/version with
    # the shipped package's own values, so this only labels the deps/check derivations.
    pname = "dotfiles-rs-workspace";
    version = "0.1.0";
    # Full workspace tree, not `cleanCargoSource`: `beansd` embeds non-Rust assets
    # (askama `.html` templates compiled by the derive macro, plus `.css`/`.js`
    # static files) that the cargo-only filter would strip. `buildDepsOnly` keys
    # its cache off Cargo.{toml,lock} only, so including assets here doesn't churn
    # the artifact cache.
    src = final.lib.fileset.toSource {
      root = ../.;
      fileset = final.lib.fileset.unions [
        ../Cargo.toml
        ../Cargo.lock
        ../crates
      ];
    };
    strictDeps = true;
    cargoExtraArgs = "--locked --workspace";
    buildInputs = final.lib.optionals final.stdenv.isDarwin [ final.libiconv ];
  };
  cargoArtifacts = craneLib.buildDepsOnly commonArgs;

  # Workspace-wide Rust lint/test gates surfaced as flake checks. Named `rust-*`
  # (not `beans-daemon-*`) because `--workspace` means they cover every crate, not
  # just the shipped package.
  rustChecks = {
    rust-fmt = craneLib.cargoFmt { inherit (commonArgs) src pname version; };
    rust-clippy = craneLib.cargoClippy (
      commonArgs
      // {
        inherit cargoArtifacts;
        cargoClippyExtraArgs = "--all-targets -- -D warnings";
      }
    );
    rust-test = craneLib.cargoNextest (commonArgs // { inherit cargoArtifacts; });
  };
in
{
  # Build the named local workspace bins as one package. The package build is
  # scoped to those bins (`--bin <name>` each); fmt/clippy/test stay `--workspace`
  # via commonArgs, and cargoArtifacts (built `--workspace`) is a valid superset.
  # Caller provides pname/version (these crates are never released, so version is
  # a cosmetic default).
  buildLocalRustBin =
    {
      pname,
      bins,
      version ? "0.1.0",
      meta ? { },
      ...
    }@args:
    craneLib.buildPackage (
      commonArgs
      # Forward only EXTRA crane args; pname/version/meta/bins are handled
      # explicitly below so the `version` default actually takes effect (a
      # defaulted arg is not present in `args`).
      // (removeAttrs args [
        "pname"
        "bins"
        "version"
        "meta"
      ])
      // {
        inherit pname version cargoArtifacts;
        cargoExtraArgs = "--locked " + final.lib.concatMapStringsSep " " (b: "--bin ${b}") bins;
        doCheck = false;
        meta = {
          mainProgram = final.lib.head bins;
          license = final.lib.licenses.mit;
        }
        // meta;
      }
    );

  # Extend (not clobber) dotfiles.internal with the Rust output plumbing the
  # devShell + checks read.
  dotfiles = (prev.dotfiles or { }) // {
    internal = (prev.dotfiles.internal or { }) // {
      inherit rustToolchain rustChecks;
    };
  };
}
