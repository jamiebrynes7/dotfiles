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
in
rustPlatform.buildRustPackage {
  pname = "beans-daemon";
  version = "0.1.0";
  inherit src;
  cargoLock.lockFile = root + "/Cargo.lock";
  cargoBuildFlags = [ "--workspace" ];
  meta = with lib; {
    description = "Background daemon for the beans issue tracker";
    mainProgram = "beansd";
    license = licenses.mit;
  };
}
