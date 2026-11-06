{
  lib,
  stdenv,
  swift,
  swiftpm,
  darwin,
}:
stdenv.mkDerivation {
  pname = "sudo-prompt";
  version = "0.1.0";

  # Tests/ is here even though `swift build` never compiles it: SwiftPM refuses
  # the manifest if a declared target's directory is missing.
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Package.swift
      ./Sources
      ./Tests
    ];
  };

  nativeBuildInputs = [
    swift
    swiftpm
    darwin.sigtool
  ];

  # SwiftPM insists on a writable HOME for its module cache.
  buildPhase = ''
    export HOME=$TMPDIR
    swift build -c release --disable-sandbox
  '';

  # A plain binary, no .app bundle: it is only ever spawned by sudo as SUDO_ASKPASS.
  installPhase = ''
    install -Dm755 .build/release/sudo-prompt $out/bin/sudo-prompt
    codesign --force --sign - $out/bin/sudo-prompt
  '';

  meta = {
    description = "Native macOS password dialog for sudo when there is no terminal";
    # flake.nix filters packages on this, keeping it out of the Linux package set.
    platforms = [ "aarch64-darwin" ];
  };
}
