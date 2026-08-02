{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  zlib,
  libgcc,
}:

let
  release = builtins.fromJSON (builtins.readFile ./hashes.json);
  version = release.version;
  platform = release.platforms.${stdenv.hostPlatform.system};

  baseUrl = "https://sprites-binaries.t3.storage.dev/client";
in
stdenv.mkDerivation {
  pname = "sprite";
  inherit version;

  src = fetchurl {
    url = "${baseUrl}/${version}/sprite-${platform.artifact}.tar.gz";
    hash = platform.hash;
  };

  # The tarball holds a single `sprite` binary at its root.
  sourceRoot = ".";

  dontBuild = true;
  dontConfigure = true;

  nativeBuildInputs = lib.optionals stdenv.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.isLinux [
    zlib
    libgcc.lib
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 sprite $out/bin/sprite
    runHook postInstall
  '';

  meta = with lib; {
    description = "Sprite CLI";
    homepage = "https://sprites.dev";
    mainProgram = "sprite";
    platforms = builtins.attrNames release.platforms;
  };
}
