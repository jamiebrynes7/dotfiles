{
  lib,
  stdenv,
  fetchurl,
}:

let
  release = builtins.fromJSON (builtins.readFile ./hashes.json);
  version = release.version;
  platform = release.platforms.${stdenv.hostPlatform.system};
in
stdenv.mkDerivation {
  pname = "codex";
  inherit version;

  src = fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-${platform.artifact}.tar.gz";
    hash = platform.hash;
  };

  # The tarball contains a single binary named codex-${artifact} at its root,
  # so there is no directory to descend into.
  sourceRoot = ".";

  dontStrip = true;

  installPhase = ''
    install -Dm755 codex-${platform.artifact} $out/bin/codex
  '';

  meta = with lib; {
    description = "OpenAI Codex command-line coding agent";
    homepage = "https://github.com/openai/codex";
    license = licenses.asl20;
    mainProgram = "codex";
    platforms = builtins.attrNames release.platforms;
  };
}
