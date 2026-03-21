{ lib, stdenv, fetchurl }:

let
  release = builtins.fromJSON (builtins.readFile ./hashes.json);
  version = release.version;
  platform = release.platforms.${stdenv.hostPlatform.system};
in stdenv.mkDerivation {
  pname = "cship";
  inherit version;

  src = fetchurl {
    url =
      "https://github.com/stephenleo/cship/releases/download/v${version}/cship-${platform.artifact}";
    hash = platform.hash;
  };

  dontUnpack = true;
  dontStrip = true;

  installPhase = ''
    install -Dm755 $src $out/bin/cship
  '';

  meta = with lib; {
    description = "Statusline renderer for Claude Code sessions";
    homepage = "https://cship.dev";
    license = licenses.mit;
    platforms = builtins.attrNames release.platforms;
  };
}
