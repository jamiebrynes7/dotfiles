{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.dotfiles.programs.spark;
  ghqEnabled = config.dotfiles.programs.ghq.enable;

  dirPrompt = if ghqEnabled then ''
    printf "  Directory [\e[2mjamiebrynes7/\e[0m]: "
    read -r dir_suffix
    if [ -z "$dir_suffix" ]; then
      printf "\e[31mError:\e[0m no directory specified.\n"
      exit 1
    fi
    dir="jamiebrynes7/$dir_suffix"
  '' else ''
    printf "  Directory: "
    read -r dir
    if [ -z "$dir" ]; then
      printf "\e[31mError:\e[0m no directory specified.\n"
      exit 1
    fi
  '';

  dirSummary = if ghqEnabled
    then ''printf "  Directory : \e[1m$GHQ_ROOT/$dir\e[0m\n"''
    else ''printf "  Directory : \e[1m$dir\e[0m\n"'';

  dirInit = if ghqEnabled then ''
    ghq create "$dir"
    actual_dir="$(ghq list --full-path | grep -F "$dir" | head -1)"
    if [ -z "$actual_dir" ]; then
      printf "\e[31mError:\e[0m could not determine directory created by ghq\n"
      exit 1
    fi
  '' else ''
    mkdir -p "$dir"
    git -C "$dir" init
    actual_dir="$dir"
  '';

  script = pkgs.writeShellScriptBin "spark" ''
    set -euo pipefail

    printf "\e[2mFetching available templates...\e[0m\n" >&2

    template=$(
      nix flake show github:jamiebrynes7/dotfiles --impure --json 2>/dev/null \
        | jq -r '.templates | to_entries[] | "\(.key)\t\(.value.description)"' \
        | fzf --prompt="> " \
              --header="Select a template" \
              --delimiter=$'\t' \
              --with-nth=1 \
              --preview='printf "  {2}"' \
              --preview-window=up:2:wrap \
        | cut -d$'\t' -f1
    )

    if [ -z "$template" ]; then
      printf "\e[2mNo template selected.\e[0m\n"
      exit 1
    fi

    printf "\n\e[1mConfigure project\e[0m\n"
    printf "  Template  : \e[1m$template\e[0m\n"
    ${dirPrompt}

    printf "\n\e[1mSummary\e[0m\n"
    printf "  Template  : \e[1m$template\e[0m\n"
    ${dirSummary}

    printf "\nConfirm? [y/N] "
    read -r confirm
    case "$confirm" in
      y|Y) ;;
      *) printf "\e[2mAborted.\e[0m\n"; exit 0 ;;
    esac

    printf "\n"
    ${dirInit}

    (cd "''${actual_dir}" && nix flake init -t "github:jamiebrynes7/dotfiles#$template")

    printf "\e[32mDone!\e[0m\n"
  '';
in {
  options.dotfiles.programs.spark = {
    enable = mkEnableOption "Enable spark script";
  };

  config = mkIf cfg.enable {
    home.packages = [ script ];
  };
}
