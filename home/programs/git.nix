{ lib, config, ... }:
with lib;
let
  cfg = config.dotfiles.programs.git;
in
{
  options.dotfiles.programs.git = {
    enable = mkEnableOption "Enable git";
    email = mkOption {
      type = types.str;
      default = "jamiebrynes7@gmail.com";
      description = "Email address for git";
    };
    emailByRemote = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = {
        "git@github.com:jamiebrynes7/**" = "jamiebrynes7@gmail.com";
      };
      description = ''
        Email to use instead of `email` in repositories with a remote whose URL
        matches the key, a git `hasconfig:remote.*.url:` glob. Write one key per URL
        form you clone with: an SSH glob does not match the HTTPS URL.
      '';
    };
  };

  config.programs.git = mkIf cfg.enable {
    enable = true;

    ignores = [ ".DS_Store" ];

    includes = mapAttrsToList (glob: email: {
      condition = "hasconfig:remote.*.url:${glob}";
      contents.user.email = email;
    }) cfg.emailByRemote;

    settings = {
      user = {
        name = "Jamie Brynes";
        email = cfg.email;
      };

      alias = {
        # Create a new branch
        new = "checkout -b";

        # View abbreviated history of the current branch
        lg = "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";

        # View current tree format in shortened format.
        s = "status -s";

        # Interactive rebase with the given last commits.
        r = "!r() { git rebase -i HEAD~$1; }; r";

        # Fast-forward branch against a given branch or HEAD.
        ff = "!ff() { git pull --rebase origin \${1:-HEAD}; }; ff";

        # Interactive branch selector
        open = ''!open() { git branch "$@" | grep -v "^[*+]" | sed 's/^ *//' | fzf --height 20% --reverse --border --info inline | xargs git checkout; }; open'';

        # List contributors and the number of commits.
        contributors = "shortlog --summary --numbered";

        a = "add";
        d = "diff";
        dc = "diff --cached";
        p = "push";
        pf = "push --force";
        c = "commit";

        fomo = "!fomo() { branch=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@') && git fetch origin $branch && git rebase $@ origin/$branch; }; fomo";
      };

      init = {
        defaultBranch = "master";
      };
      pull = {
        rebase = true;
      };
      rebase = {
        autostash = true;
      };
    };
  };
}
