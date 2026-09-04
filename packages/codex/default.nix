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

  # Codex resolves its code-mode host by looking for `codex-code-mode-host` next to
  # its own executable, so the helper has to land in the same bin/ as codex or every
  # code-mode tool call (running a shell command, editing a file) fails. Upstream ships
  # it as a separate release artifact: openai/codex#31831.
  srcs = [
    (fetchurl {
      url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-${platform.artifact}.tar.gz";
      hash = platform.hash;
    })
    (fetchurl {
      url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-code-mode-host-${platform.artifact}.tar.gz";
      hash = platform.codeModeHostHash;
    })
  ];

  # Each tarball contains a single binary named after the artifact at its root, so
  # there is no directory to descend into and both unpack side by side.
  sourceRoot = ".";

  dontStrip = true;

  installPhase = ''
    install -Dm755 codex-${platform.artifact} $out/bin/codex
    install -Dm755 codex-code-mode-host-${platform.artifact} $out/bin/codex-code-mode-host
  '';

  meta = with lib; {
    description = "OpenAI Codex command-line coding agent";
    homepage = "https://github.com/openai/codex";
    license = licenses.asl20;
    mainProgram = "codex";
    platforms = builtins.attrNames release.platforms;
  };
}
