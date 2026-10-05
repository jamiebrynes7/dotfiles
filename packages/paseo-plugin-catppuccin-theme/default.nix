{ runCommand, fetchFromGitHub }:
let
  # No tags or releases upstream — paseo.cafe itself links a bare commit. Bumped by
  # hand, deliberately: plugin server code runs unsandboxed as the daemon user, so
  # every update is a reviewed commit rather than a nightly auto-update PR.
  src = fetchFromGitHub {
    owner = "sleeyax";
    repo = "paseo-plugins";
    rev = "c9063ded14eb3fb7843bae78c26d9b7c6662a0be";
    hash = "sha256-LzoVIYbm6U807T2DTXQOa23FsgBGYt7h9EixNgnKuR0=";
  };
in
# Copy the plugin subdirectory out rather than pointing config.json at
# "${src}/plugins/catppuccin-theme": the monorepo carries other plugins and tooling
# that have no business in the runtime closure.
runCommand "paseo-plugin-catppuccin-theme" { } ''
  cp -r ${src}/plugins/catppuccin-theme $out
''
