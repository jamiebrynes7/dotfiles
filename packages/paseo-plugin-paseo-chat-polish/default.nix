{
  lib,
  stdenv,
  buildNpmPackage,
  fetchFromGitHub,
  autoPatchelfHook,
}:
# Bumped by hand even though upstream tags releases: plugin server code runs
# unsandboxed as the daemon user, so every update is a reviewed commit rather than a
# nightly auto-update PR.
buildNpmPackage {
  pname = "paseo-plugin-paseo-chat-polish";
  version = "0.7.0";

  src = fetchFromGitHub {
    owner = "lthieu96";
    repo = "paseo-chat-polish";
    rev = "0782cd0c87f621a8211d4731717089767929bb88";
    hash = "sha256-73dkGm6cR17j6OjH0OAyHs6u6JN2g0C67K39v1P6LZ4=";
  };

  npmDepsHash = "sha256-jz+Ee4rghvrkbZV+YoY4bDrz0SfvrUZ+PeF2uH4veOY=";

  # The manifest's `build` step (`npm ci --omit=dev --ignore-scripts`) only runs for
  # git installs, never for a directory source, so it is reproduced here. sharp ships
  # prebuilt per-platform binaries as optional dependencies, so no install script is
  # needed.
  npmFlags = [
    "--omit=dev"
    "--ignore-scripts"
  ];
  dontNpmBuild = true;

  # sharp's prebuilt libvips links against a generic glibc layout.
  nativeBuildInputs = lib.optional stdenv.hostPlatform.isLinux autoPatchelfHook;
  buildInputs = lib.optional stdenv.hostPlatform.isLinux stdenv.cc.cc.lib;

  # Only what package.json's `files` publishes, plus the production node_modules;
  # sharp is loaded at runtime from the plugin's own directory.
  installPhase = ''
    runHook preInstall
    mkdir -p $out/images
    cp -r paseo-plugin.json package.json index.client.tsx index.server.ts client server shared node_modules $out/
    cp images/icon.png $out/images/
    runHook postInstall
  '';
}
