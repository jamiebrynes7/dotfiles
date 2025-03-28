{
  description = "System configuration for $system";

  inputs = { dotfiles.url = "github:jamiebrynes7/dotfiles"; };

  outputs = { self, dotfiles }: {
    nixosConfigurations.default = dotfiles.lib.mkNixosSystem {
      system = "TODO";
      hostname = "TODO";
      user = "TODO";
      home = ./home.nix;
      modules = [ ./configuration.nix ];
    };
    devShells = dotfiles.lib.mkShells { };
  };
}
