{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
}:

let
  release = builtins.fromJSON (builtins.readFile ./hashes.json);
  version = release.version;
  platform = release.platforms.${stdenv.hostPlatform.system};

  # Anthropic publishes the native binaries to a fixed GCS bucket rather than a
  # GitHub release, so the bucket id is part of the URL.
  gcsBase = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases";
in
stdenv.mkDerivation {
  pname = "claude-code";
  inherit version;

  src = fetchurl {
    url = "${gcsBase}/${version}/${platform.artifact}/claude";
    hash = platform.hash;
  };

  # The artifact is a bare executable, not an archive.
  dontUnpack = true;
  dontBuild = true;
  # Without this the Linux binary strips down to just Bun's runtime.
  dontStrip = true;

  nativeBuildInputs = [ makeWrapper ] ++ lib.optionals stdenv.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.isLinux [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall

    install -Dm755 $src $out/libexec/claude

    # `$HOME` is deliberately left unexpanded — the CLI expands
    # CLAUDE_EXECUTABLE_PATH itself. DISABLE_AUTOUPDATER stops it trying to
    # overwrite itself in the read-only store.
    makeWrapper $out/libexec/claude $out/bin/claude \
      --set CLAUDE_EXECUTABLE_PATH '$HOME/.local/bin/claude' \
      --set DISABLE_AUTOUPDATER 1

    runHook postInstall
  '';

  meta = with lib; {
    description = "Claude Code - AI-powered command line interface";
    homepage = "https://code.claude.com";
    license = licenses.unfree;
    mainProgram = "claude";
    platforms = builtins.attrNames release.platforms;
  };
}
