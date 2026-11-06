{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.programs.sudo-prompt;

  # Shadows /usr/bin/sudo via the per-user profile, which precedes /usr/bin on
  # PATH. With a terminal it is a pure pass-through. Without one (agents,
  # launchd jobs) it asks through sudo-prompt's dialog instead of failing, and
  # `-k` makes every such call prompt: a cached credential would otherwise let
  # later calls run unseen.
  sudo = pkgs.writeShellScriptBin "sudo" ''
    if { : </dev/tty; } 2>/dev/null; then exec /usr/bin/sudo "$@"; fi
    # The dialog can't read root-owned sudo's exact argv itself; it trusts this
    # only if it matches what ps reports for the real sudo process.
    SUDO_PROMPT_ARGV=$(printf '%s\0' /usr/bin/sudo -A -k "$@" | /usr/bin/base64 | /usr/bin/tr -d '\n') \
      SUDO_ASKPASS=${pkgs.dotfiles.sudo-prompt}/bin/sudo-prompt \
      exec /usr/bin/sudo -A -k "$@"
  '';
in
{
  # Deliberately in no profile: it shadows sudo, so a host opts in by hand.
  options.dotfiles.programs.sudo-prompt = {
    enable = lib.mkEnableOption "a native macOS password dialog for sudo calls made without a terminal";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isDarwin;
        message = "dotfiles.programs.sudo-prompt is macOS-only.";
      }
    ];
    home.packages = [ sudo ];
  };
}
