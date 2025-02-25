{
  description = "System configuration for $system";

  inputs = { dotfiles.url = "git+ssh://git@github.com/jamiebrynes7/dotfiles"; };

  outputs = { self, dotfiles }: {
    nixosConfigurations.default = dotfiles.lib.mkNixosSystem {
      system = "TODO";
      hostname = "TODO";
      user = "TODO";
      home = ./sys/home.nix;
      modules = [ ./sys/configuration.nix ];
    };
    devShells = dotfiles.lib.mkShells { };
  };
}
