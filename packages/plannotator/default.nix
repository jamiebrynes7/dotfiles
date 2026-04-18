{ lib, stdenv, fetchurl, makeWrapper, autoPatchelfHook }:

let
  release = builtins.fromJSON (builtins.readFile ./hashes.json);
  version = release.version;
  platform = release.platforms.${stdenv.hostPlatform.system};
in stdenv.mkDerivation {
  pname = "plannotator";
  inherit version;

  src = fetchurl {
    url =
      "https://github.com/backnotprop/plannotator/releases/download/v${version}/plannotator-${platform.artifact}";
    hash = platform.hash;
  };

  nativeBuildInputs = [ makeWrapper ]
    ++ lib.optionals stdenv.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.isLinux [ stdenv.cc.cc.lib ];

  dontUnpack = true;
  dontStrip = true;

  installPhase = ''
    install -Dm755 $src $out/bin/plannotator
  '';

  postInstall = ''
    wrapProgram $out/bin/plannotator \
      --set PLANNOTATOR_SHARE disabled
  '';

  meta = with lib; {
    description =
      "Interactive annotation and review tool for AI coding agent plans";
    homepage = "https://github.com/backnotprop/plannotator";
    license = with licenses; [ asl20 mit ];
    platforms = builtins.attrNames release.platforms;
  };
}
