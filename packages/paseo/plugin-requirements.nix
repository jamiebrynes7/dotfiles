# The daemon enforces a plugin's `requirements.paseo` only at load, so a paseo bump
# that a plugin no longer admits would surface as `failed` in `paseo plugin ls` on a
# host. As a flake check this moves that failure onto the auto-update PR, whose diff
# says nothing about plugins.
#
# It mirrors upstream's assertPluginCompatibility (protocol/src/plugin-requirements.ts):
# a missing range means "<0.8.0", an empty one is rejected (npm's semver alone would
# read it as "*"), and a prerelease also passes when its stable core does. The real
# semver comes from the npm bundled in nodejs, so it moves with the nixpkgs pin.
#
# Not a package: flake.nix callPackages it into `checks`. Package discovery only picks
# up directories under packages/, so this file is never exposed as one.
{
  lib,
  runCommandLocal,
  nodejs,
  dotfiles,
}:
let
  paseoVersion = (lib.importJSON ./hashes.json).version;
  plugins = lib.filterAttrs (name: _: lib.hasPrefix "paseo-plugin-" name) dotfiles;
in
runCommandLocal "paseo-plugin-requirements"
  {
    nativeBuildInputs = [ nodejs ];
    NODE_PATH = "${nodejs}/lib/node_modules/npm/node_modules";
  }
  ''
    node - ${lib.escapeShellArg paseoVersion} ${lib.escapeShellArgs (lib.attrValues plugins)} <<'EOF'
    const fs = require("node:fs");
    const semver = require("semver");
    const [version, ...dirs] = process.argv.slice(2);
    const parsed = semver.parse(version);
    const core = `''${parsed.major}.''${parsed.minor}.''${parsed.patch}`;
    let failed = false;
    for (const dir of dirs) {
      const manifest = JSON.parse(fs.readFileSync(`''${dir}/paseo-plugin.json`, "utf8"));
      const range = manifest.requirements?.paseo ?? "<0.8.0";
      const ok =
        range.trim() !== "" &&
        semver.validRange(range) !== null &&
        (semver.satisfies(parsed, range) || semver.satisfies(core, range));
      console.log(`''${ok ? "ok  " : "FAIL"} ''${manifest.id}: requires paseo ''${range}, pinned ''${version}`);
      failed ||= !ok;
    }
    process.exit(failed ? 1 : 0);
    EOF
    touch $out
  ''
