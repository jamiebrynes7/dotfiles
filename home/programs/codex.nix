{ config, lib, pkgs, ... }:
with lib;
let cfg = config.dotfiles.programs.codex;
in {
  options.dotfiles.programs.codex = { enable = mkEnableOption "Enable codex"; };

  # The codex binary is unbundled: it shells out to an ambient `rg` and, on
  # Linux only, `bubblewrap` for sandboxing. Ensure those are on PATH where
  # this is enabled (the base profile already provides ripgrep).
  config = mkIf cfg.enable { home.packages = [ pkgs.dotfiles.codex ]; };
}
