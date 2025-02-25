{
  description = "System configuration for $system";

  inputs = { dotfiles.url = "git+ssh://git@github.com/jamiebrynes7/dotfiles"; };

  outputs = { self, dotfiles }: {
    darwinConfigurations.default = dotfiles.lib.mkDarwin {
      hostname = "TODO";
      user = "TODO";
      home = ./sys/home.nix;
      modules = [ ./sys/configuration.nix ];
    };
    devShells = dotfiles.lib.mkShells { };
  };
}
