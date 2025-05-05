{ config, lib, pkgs, ... }:

# This module is used to configure VSCode and VSCode-like applications (Cursor, etc.) with support for defining the
# configuration for a remote server instance as well.
# Inspired by: https://github.com/jcszymansk/vscodes
# This is opinionated in that it assumes single profile.
let
  inherit (lib) mkIf mkOption types;
  cfg = config.programs.vscode-likes;

  jsonFormat = pkgs.formats.json { };

  dataDirLookup = {
    "vscode-server-linux" =
      "${config.home.homeDirectory}/.vscode-server/data/Machine";
    "cursor-server-linux" =
      "${config.home.homeDirectory}/.cursor-server/data/Machine";
    "vscode-darwin" =
      "${config.home.homeDirectory}/Library/Application Support/Code/User";
    "cursor-darwin" =
      "${config.home.homeDirectory}/Library/Application Support/TODO";
  };

  dataDir = cfg:
    let
      platform =
        if pkgs.stdenv.hostPlatform.isDarwin then "darwin" else "linux";
      remoteSuffix = if cfg.remote then "-server" else "";

      key = "${cfg.kind}${remoteSuffix}-${platform}";
    in dataDirLookup.${key} or (throw "Unsupported combination: ${key}");

  settingsFilePath = cfg: "${dataDir cfg}/settings.json";

  instanceType = types.submodule ({ name, config, ... }: {
    options = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to enable this instance";
      };

      kind = mkOption {
        type = types.enum [ "vscode" "cursor" ];
        description = ''
          Determines the kind of instance this is.
        '';
      };

      remote = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Determines whether this instance is a remote installation
          i.e. - code-server or cursor-server over SSH.
        '';
      };

      userSettings = mkOption {
        type = jsonFormat.type;
        default = { };
      };
    };
  });

  mergedUserSettings = cfg:
    cfg.userSettings // (lib.optionalAttrs cfg.remote {
      "security.allowedUNCHosts" = [ "wsl.localhost" ];
    });

  mkFiles = cfg:
    let userSettings = mergedUserSettings cfg;
    in lib.mkMerge [
      (mkIf (userSettings != { }) {
        "${settingsFilePath cfg}".source =
          jsonFormat.generate "vscode-user-settings" userSettings;
      })
    ];

  # TODO: Keybindings and extensions
  # Keybindings are complicated by the fact that remote servers don't have support for defining keybindings.
  # Instead, we could have an extension that defines contributes our keybindings and ensure we don't have any
  # conflicting keybindings in the user's settings.
  # https://github.com/Microsoft/vscode/issues/4504

in {
  options.programs.vscode-likes = mkOption {
    type = types.attrsOf instanceType;
    default = { };
  };

  config = {
    home.file =
      lib.mkMerge (lib.flatten (lib.map mkFiles (lib.attrValues cfg)));
  };
}
