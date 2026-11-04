# Renders a fixture repoSkills declaration (two skills, one shared by two
# repositories) and checks the generated plugins and config.json. The key validation
# is checked at eval: a rendering whose errors miss a bad key fails evaluating this
# check, which turns `nix flake check` red just the same.
#
# Not a package: flake.nix callPackages it into `checks`.
{
  lib,
  pkgs,
  runCommandLocal,
  jq,
}:
let
  repoSkillsLib = import ./. { inherit lib pkgs; };

  dataDir = "/home/test/.local/share/paseo-repo-skills";

  rendered = repoSkillsLib.render {
    inherit dataDir;
    repoSkills = {
      shared = {
        source = ./fixtures/shared;
        repositories = [
          "github.com/acme/web"
          "github.com/acme/api"
        ];
      };
      api-only = {
        source = ./fixtures/api-only;
        repositories = [ "github.com/acme/api" ];
      };
    };
  };

  # Plugin name -> the skills it must hold, sorted as `ls` lists them.
  expectedPlugins = {
    acme-web = [ "shared" ];
    acme-api = [
      "api-only"
      "shared"
    ];
  };

  expectedConfig = {
    version = 1;
    repositories = {
      "github.com/acme/web" = "${dataDir}/acme-web";
      "github.com/acme/api" = "${dataDir}/acme-api";
    };
  };

  errorsFor =
    repositories:
    (repoSkillsLib.render {
      inherit dataDir;
      repoSkills.fixture = {
        source = ./fixtures/shared;
        inherit repositories;
      };
    }).errors;

  # Every listed key must be named by an error containing `kind`.
  rejects =
    kind: repositories:
    let
      errors = lib.filter (lib.hasInfix kind) (errorsFor repositories);
    in
    lib.all (key: lib.any (lib.hasInfix "\"${key}\"") errors) repositories;

  notNormalised = rejects "is not normalised";
  collide = rejects "produce the same plugin name";

  skillErrors =
    repoSkills:
    (repoSkillsLib.render {
      inherit dataDir repoSkills;
    }).errors;

  evalChecks =
    lib.assertMsg (
      rendered.errors == [ ]
    ) "fixture rendering reported errors: ${toString rendered.errors}"
    && lib.assertMsg (
      lib.attrNames rendered.plugins == lib.attrNames expectedPlugins
    ) "plugins are ${toString (lib.attrNames rendered.plugins)}, expected acme-api acme-web"
    && lib.assertMsg (notNormalised [
      "git@github.com:acme/web.git"
    ]) "an SSH clone URL was accepted as a key"
    && lib.assertMsg (notNormalised [
      "https://github.com/acme/web"
    ]) "an HTTPS URL was accepted as a key"
    && lib.assertMsg (notNormalised [ "github.com/acme/web.git" ]) "a key ending in .git was accepted"
    && lib.assertMsg (notNormalised [
      "GitHub.com/acme/web"
    ]) "a key with an uppercase host was accepted"
    && lib.assertMsg (collide [
      "github.com/a-b/c"
      "github.com/a/b-c"
    ]) "two keys producing the plugin name a-b-c were not both named"
    && lib.assertMsg (collide [
      "github.com/Acme/web"
      "github.com/acme/web"
    ]) "two keys differing only in case were not both named"
    && lib.assertMsg (lib.any (lib.hasInfix "skill name \"Bad skill\"") (skillErrors {
      "Bad skill" = {
        source = ./fixtures/shared;
        repositories = [ "github.com/acme/web" ];
      };
    })) "an invalid skill name was accepted"
    && lib.assertMsg (lib.any (lib.hasInfix "repoSkills.no-skill-md.source has no SKILL.md")
      (skillErrors {
        no-skill-md = {
          source = ./fixtures;
          repositories = [ "github.com/acme/web" ];
        };
      })
    ) "a source without SKILL.md was accepted"
    && lib.assertMsg (errorsFor [ "github.com/acme/web" ] == [ ]) "a normalised key was rejected";

  checkPlugin = name: skills: ''
    plugin=${rendered.plugins.${name}}
    [ "$(jq -r .name "$plugin/.claude-plugin/plugin.json")" = ${name} ] \
      || fail "${name}: manifest name is not ${name}"
    [ "$(ls "$plugin/skills" | tr '\n' ' ')" = ${lib.escapeShellArg "${toString skills} "} ] \
      || fail "${name}: skills are $(ls "$plugin/skills" | tr '\n' ' '), expected ${toString skills}"
  '';
in
assert evalChecks;
runCommandLocal "paseo-repo-skills"
  {
    nativeBuildInputs = [ jq ];
    expectedConfig = builtins.toJSON expectedConfig;
    actualConfig = builtins.toJSON rendered.config;
    passAsFile = [
      "expectedConfig"
      "actualConfig"
    ];
  }
  ''
    fail() { echo "FAIL: $1" >&2; exit 1; }

    ${lib.concatStrings (lib.mapAttrsToList checkPlugin expectedPlugins)}

    skill=${rendered.plugins.acme-api}/skills/shared
    [ -f "$skill/notes.md" ] || fail "supporting file notes.md was not copied"
    grep -qx 'allowed-tools: Read' "$skill/SKILL.md" || fail "cc: key was not kept unprefixed"
    grep -qx 'Shared fixture body.' "$skill/SKILL.md" || fail "SKILL.md body was not kept"
    if grep -qE '^(cc:|cursor:|codex:|globs:|model:)' "$skill/SKILL.md"; then
      fail "SKILL.md still carries another variant's keys"
    fi

    [ "$(jq -S . "$expectedConfigPath")" = "$(jq -S . "$actualConfigPath")" ] \
      || fail "config.json is $(cat "$actualConfigPath")"

    touch $out
  ''
