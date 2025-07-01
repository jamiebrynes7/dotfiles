{ lib, config, ... }:
with lib;
let cfg = config.dotfiles.programs.git;
in {
  options.dotfiles.programs.git = {
    enable = mkEnableOption "Enable git";
    email = mkOption {
      type = types.str;
      default = "jamiebrynes7@gmail.com";
      description = "Email address for git";
    };
  };

  config.programs.git = mkIf cfg.enable {
    enable = true;

    userName = "Jamie Brynes";
    userEmail = cfg.email;

    aliases = {
      # Create a new branch
      new = "checkout -b";

      # View abbreviated history of the current branch
      lg =
        "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";

      # View current tree format in shortened format.
      s = "status -s";

      # Interactive rebase with the given last commits.
      r = "!r() { git rebase -i HEAD~$1; }; r";

      # Fast-forward branch against a given branch or HEAD.
      ff = "!ff() { git pull --rebase origin \${1:-HEAD}; }; ff";

      # Interactive branch selector
      open = ''
        !open() { git branch "$@" | grep -v "^\*" | fzf --height 20% --reverse --border --info inline | xargs git checkout; }; open'';

      # List contributors and the number of commits.
      contributors = "shortlog --summary --numbered";

      a = "add";
      d = "diff";
      dc = "diff --cached";
      p = "push";
      pf = "push --force";
      c = "commit";

      fomo =
        "!fomo() { git fetch origin master && git rebase $@ origin/master; }; fomo";
    };

    extraConfig = {
      init = { defaultBranch = "master"; };
      pull = { rebase = true; };
      rebase = { autostash = true; };
    };
  };
}
