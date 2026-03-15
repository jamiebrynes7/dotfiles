{ lib, stdenv, fetchurl }:

let
  version = "0.12.0";

  platformMap = {
    "aarch64-darwin" = "darwin-arm64";
    "x86_64-darwin" = "darwin-x64";
    "aarch64-linux" = "linux-arm64";
    "x86_64-linux" = "linux-x64";
  };

  platform = platformMap.${stdenv.hostPlatform.system};
  hashes = builtins.fromJSON (builtins.readFile ./hashes.json);
in
stdenv.mkDerivation {
  pname = "plannotator";
  inherit version;

  src = fetchurl {
    url = "https://github.com/backnotprop/plannotator/releases/download/v${version}/plannotator-${platform}";
    hash = hashes.${stdenv.hostPlatform.system};
  };

  dontUnpack = true;

  installPhase = ''
    install -Dm755 $src $out/bin/plannotator
  '';

  meta = with lib; {
    description = "Interactive annotation and review tool for AI coding agent plans";
    homepage = "https://github.com/backnotprop/plannotator";
    license = with licenses; [ asl20 mit ];
    platforms = builtins.attrNames platformMap;
  };
}
