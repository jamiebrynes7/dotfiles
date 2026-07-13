{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.dotfiles.programs.adhoc-pf;

  script = pkgs.writeShellScriptBin "adhoc-pf" ''
    set -euo pipefail

    usage() {
      printf 'usage: adhoc-pf <ssh-host> <port>\n' >&2
    }

    if [ "$#" -ne 2 ]; then
      usage
      exit 2
    fi

    host="$1"
    port="$2"

    if [ -z "$host" ]; then
      printf 'invalid host: empty value\n' >&2
      usage
      exit 2
    fi

    if [ -z "$port" ]; then
      printf 'invalid port: empty value\n' >&2
      usage
      exit 2
    fi

    case "$port" in
      *[!0-9]*)
        printf 'invalid port: %s\n' "$port" >&2
        usage
        exit 2
        ;;
    esac

    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
      printf 'invalid port: %s\n' "$port" >&2
      usage
      exit 2
    fi

    printf 'forwarding 127.0.0.1:%s -> %s:127.0.0.1:%s\n' "$port" "$host" "$port" >&2
    printf 'press Ctrl+C to stop\n' >&2

    exec ${pkgs.openssh}/bin/ssh \
      -S none \
      -N \
      -o ControlMaster=no \
      -o ExitOnForwardFailure=yes \
      -L "127.0.0.1:$port:127.0.0.1:$port" \
      "$host"
  '';
in
{
  options.dotfiles.programs.adhoc-pf = {
    enable = mkEnableOption "Enable ad hoc SSH port-forward helper";
  };

  config = mkIf cfg.enable {
    home.packages = [ script ];
  };
}
