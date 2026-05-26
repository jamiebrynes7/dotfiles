{ config, lib, pkgs, ... }:
let cfg = config.dotfiles.programs.beans-daemon;
in {
  options.dotfiles.programs.beans-daemon = {
    enable = lib.mkEnableOption "Enable the beans daemon";
    launcherPort = lib.mkOption {
      type = lib.types.port;
      default = 9000;
      description = "TCP port for the unified web launcher.";
    };
    lruCap = lib.mkOption {
      type = lib.types.ints.positive;
      default = 8;
      description = "Maximum number of beans-serve children warm at once.";
    };
    heartbeatSecs = lib.mkOption {
      type = lib.types.ints.positive;
      default = 15;
      description = "Browser heartbeat interval in seconds.";
    };
    enableZshIntegration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description =
        "Install the zsh chpwd hook that pings the daemon on each cd.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.dotfiles.beans-daemon ];

    xdg.configFile."beans-daemon/config.toml".text = ''
      launcher_port    = ${toString cfg.launcherPort}
      lru_cap          = ${toString cfg.lruCap}
      heartbeat_secs   = ${toString cfg.heartbeatSecs}
      log_level        = "info"
      beans_serve_path = "${pkgs.dotfiles.beans}/bin/beans-serve"
    '';

    launchd.agents.beans-daemon = lib.mkIf pkgs.stdenv.isDarwin {
      enable = true;
      config = {
        ProgramArguments = [ "${pkgs.dotfiles.beans-daemon}/bin/beansd" ];
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath =
          "${config.home.homeDirectory}/Library/Logs/beans-daemon.log";
        StandardErrorPath =
          "${config.home.homeDirectory}/Library/Logs/beans-daemon.log";
      };
    };

    systemd.user.services.beans-daemon = lib.mkIf pkgs.stdenv.isLinux {
      Unit = {
        Description = "Beans daemon — multiplexes beans-serve across projects";
        After = [ "default.target" ];
      };
      Service = {
        ExecStart = "${pkgs.dotfiles.beans-daemon}/bin/beansd";
        Restart = "always";
        RestartSec = 2;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
