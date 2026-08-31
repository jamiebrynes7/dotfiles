{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
  release,
}:

let
  platform = release.desktop.${stdenvNoCC.hostPlatform.system};
in
stdenvNoCC.mkDerivation {
  pname = "paseo-desktop";
  version = release.version;

  src = fetchurl {
    url = "https://github.com/getpaseo/paseo/releases/download/${release.tag}/${platform.artifact}";
    hash = platform.hash;
  };

  nativeBuildInputs = [ unzip ];

  # The zip holds Paseo.app at its root, so without this the unpack hook cds
  # into the bundle itself.
  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;

  # Load-bearing. The bundle carries a Developer ID signature and a stapled
  # notarization ticket; fixupPhase's strip rewrites Mach-O headers and
  # invalidates both, which turns "app launches" into "app is damaged".
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/Applications $out/bin
    cp -a Paseo.app $out/Applications/Paseo.app
    test -x $out/Applications/Paseo.app/Contents/MacOS/Paseo
    ln -s $out/Applications/Paseo.app/Contents/MacOS/Paseo $out/bin/paseo-desktop

    runHook postInstall
  '';

  # Contents/Resources/bin/paseo is deliberately left unexposed: that shim
  # re-execs Electron with PASEO_DESKTOP_MANAGED=1, which marks any daemon it
  # starts as the app's to restart and stop. The daemon package owns `paseo`.

  meta = {
    description = "Paseo desktop app (signed upstream macOS build)";
    homepage = "https://github.com/getpaseo/paseo";
    license = lib.licenses.agpl3Plus;
    mainProgram = "paseo-desktop";
    platforms = [ "aarch64-darwin" ];
  };
}
