# Home-manager configuration for the `home-eval` flake check: the default `base`
# profile plus the AI-assistant modules, so CI evaluates their assertions and
# everything they produce. Never activated on a real machine.
{
  home.stateVersion = "26.05";

  dotfiles.programs = {
    claude-code.enable = true;
    codex.enable = true;
    cursor.enable = true;
    git.emailByRemote."git@github.com:jamiebrynes7/**" = "jamiebrynes7@gmail.com";
    beans = {
      enable = true;
      enableClaudeCodeIntegration = true;
    };
    plannotator = {
      claude-code.enable = true;
      codex.enable = true;
    };
  };
}
