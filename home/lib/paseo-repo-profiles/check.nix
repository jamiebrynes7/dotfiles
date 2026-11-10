# Renders a fixture repoProfiles declaration, spread over two modules and merged
# through the option's own type (one skill shared by two repositories, settings for
# one of them from both modules, a settings-only repository and an empty one), and
# checks the generated plugins, settings files and config.json. Validation is checked at eval: a
# rendering whose errors miss a bad declaration fails evaluating this check, which
# turns `nix flake check` red just the same.
#
# Not a package: flake.nix callPackages it into `checks`.
{
  lib,
  pkgs,
  runCommandLocal,
  jq,
}:
let
  profilesLib = import ./. { inherit lib pkgs; };

  dataDir = "/home/test/.local/share/paseo-repo-profiles";

  # One value, listed under each repository that uses it.
  shared = ./fixtures/shared;

  # Declarations from several modules, merged through the option's own type.
  mergeOf =
    modules:
    (lib.evalModules {
      modules = [
        { options.repoProfiles = lib.mkOption { type = profilesLib.profilesType; }; }
      ]
      ++ modules;
    }).config.repoProfiles;

  rendered = profilesLib.render {
    inherit dataDir;
    repoProfiles = mergeOf [
      {
        repoProfiles = {
          "github.com/acme/web" = {
            skills = { inherit shared; };
            settings.autoMode.environment = [
              "$defaults"
              "from the first module"
            ];
          };
          "github.com/acme/api".skills = {
            inherit shared;
            api-only = ./fixtures/api-only;
          };
          "github.com/acme/settings-only".settings.autoMode.allow = [ "allowed" ];
          "github.com/acme/empty" = { };
        };
      }
      {
        repoProfiles."github.com/acme/web".settings = {
          autoMode.environment = [ "from the second module" ];
          model = "opus";
        };
      }
    ];
  };

  # Link path -> plugin name and the skills it must hold, sorted as `ls` lists them.
  expectedPlugins = {
    "acme-web/plugin" = {
      name = "acme-web";
      skills = [ "shared" ];
    };
    "acme-api/plugin" = {
      name = "acme-api";
      skills = [
        "api-only"
        "shared"
      ];
    };
  };

  # Link path -> the settings.json it must hold.
  expectedSettings = {
    "acme-web/settings.json" = {
      autoMode.environment = [
        "$defaults"
        "from the first module"
        "from the second module"
      ];
      model = "opus";
    };
    "acme-settings-only/settings.json" = {
      autoMode.allow = [ "allowed" ];
    };
  };

  # Each field only where declared; the empty profile not at all.
  expectedConfig = {
    version = 1;
    repositories = {
      "github.com/acme/web" = {
        pluginDir = "${dataDir}/acme-web/plugin";
        settings = "${dataDir}/acme-web/settings.json";
      };
      "github.com/acme/api".pluginDir = "${dataDir}/acme-api/plugin";
      "github.com/acme/settings-only".settings = "${dataDir}/acme-settings-only/settings.json";
    };
  };

  errorsOf =
    repoProfiles:
    (profilesLib.render {
      inherit dataDir repoProfiles;
    }).errors;

  # Every listed key must be named by an error containing `kind`.
  rejects =
    kind: keys:
    let
      errors = lib.filter (lib.hasInfix kind) (
        errorsOf (
          lib.genAttrs keys (_: {
            skills.shared = shared;
          })
        )
      );
    in
    lib.all (key: lib.any (lib.hasInfix "\"${key}\"") errors) keys;

  notNormalised = rejects "is not normalised";
  collide = rejects "produce the same profile name";

  conflicting = builtins.tryEval (
    builtins.deepSeq (mergeOf [
      { repoProfiles."github.com/acme/web".skills.shared = ./fixtures/shared; }
      { repoProfiles."github.com/acme/web".skills.shared = ./fixtures/api-only; }
    ]) true
  );
  nonObjectSettings = builtins.tryEval (
    builtins.deepSeq (mergeOf [ { repoProfiles."github.com/acme/web".settings = "x"; } ]) true
  );
  agreeing = mergeOf [
    { repoProfiles."github.com/acme/web".skills.shared = shared; }
    { repoProfiles."github.com/acme/web".skills.shared = shared; }
    { repoProfiles."github.com/acme/web".skills.api-only = ./fixtures/api-only; }
  ];

  evalChecks =
    lib.assertMsg (
      rendered.errors == [ ]
    ) "fixture rendering reported errors: ${toString rendered.errors}"
    &&
      lib.assertMsg (lib.attrNames rendered.links == lib.attrNames (expectedPlugins // expectedSettings))
        "links are ${toString (lib.attrNames rendered.links)}, expected ${
          toString (lib.attrNames (expectedPlugins // expectedSettings))
        }"
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
    ]) "two keys producing the profile name a-b-c were not both named"
    && lib.assertMsg (collide [
      "github.com/Acme/web"
      "github.com/acme/web"
    ]) "two keys differing only in case were not both named"
    && lib.assertMsg (lib.any (lib.hasInfix "skill name \"Bad skill\"") (errorsOf {
      "github.com/acme/web".skills."Bad skill" = shared;
    })) "an invalid skill name was accepted"
    && lib.assertMsg (lib.any
      (lib.hasInfix "repoProfiles.\"github.com/acme/web\".skills.no-skill-md has no SKILL.md")
      (errorsOf {
        "github.com/acme/web".skills.no-skill-md = ./fixtures;
      })
    ) "a source without SKILL.md was accepted"
    && lib.assertMsg (
      errorsOf { "github.com/acme/web".skills.shared = shared; } == [ ]
    ) "a normalised key was rejected"
    && lib.assertMsg (!nonObjectSettings.success) "a settings value that is not an attrset was accepted"
    && lib.assertMsg (
      !conflicting.success
    ) "two modules giving one repository the same skill name with different sources did not conflict"
    && lib.assertMsg (
      lib.attrNames agreeing."github.com/acme/web".skills == [
        "api-only"
        "shared"
      ]
    ) "skills declared for one repository in several modules did not merge";

  checkSettings = link: expected: ''
    [ "$(jq -S . ${rendered.links.${link}})" = "$(jq -S . <<<${lib.escapeShellArg (builtins.toJSON expected)})" ] \
      || fail "${link} is $(cat ${rendered.links.${link}})"
  '';

  checkPlugin = link: expected: ''
    plugin=${rendered.links.${link}}
    [ "$(jq -r .name "$plugin/.claude-plugin/plugin.json")" = ${expected.name} ] \
      || fail "${link}: manifest name is not ${expected.name}"
    [ "$(ls "$plugin/skills" | tr '\n' ' ')" = ${lib.escapeShellArg "${toString expected.skills} "} ] \
      || fail "${link}: skills are $(ls "$plugin/skills" | tr '\n' ' '), expected ${toString expected.skills}"
  '';
in
assert evalChecks;
runCommandLocal "paseo-repo-profiles"
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
    ${lib.concatStrings (lib.mapAttrsToList checkSettings expectedSettings)}

    skill=${rendered.links."acme-api/plugin"}/skills/shared
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
