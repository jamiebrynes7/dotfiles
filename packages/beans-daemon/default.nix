{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "beans-daemon";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  cargoLock = { lockFile = ./Cargo.lock; };

  meta = with lib; {
    description = "Background daemon for the beans issue tracker";
    mainProgram = "beansd";
    license = licenses.mit;
  };
}
