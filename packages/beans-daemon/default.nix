{ lib, rustPlatform }:

let
  root = ../..;
  src = lib.fileset.toSource {
    inherit root;
    fileset = lib.fileset.unions [
      (root + "/Cargo.toml")
      (root + "/Cargo.lock")
      (root + "/crates")
    ];
  };
in rustPlatform.buildRustPackage {
  pname = "beans-daemon";
  version = "0.1.0";
  inherit src;
  cargoLock.lockFile = root + "/Cargo.lock";
  # Builds all workspace members: `beansd` (daemon binary, mainProgram) and
  # `beansctl` (control CLI used by the chpwd hook and direct invocation).
  # Both binaries are installed to $out/bin.
  cargoBuildFlags = [ "--workspace" ];
  meta = with lib; {
    description =
      "Background daemon (beansd) and control CLI (beansctl) for the beans issue tracker";
    mainProgram = "beansd";
    license = licenses.mit;
  };
}
