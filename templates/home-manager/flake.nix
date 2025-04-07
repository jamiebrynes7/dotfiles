{
  description = "System configuration for $system";

  inputs = { dotfiles.url = "github:jamiebrynes7/dotfiles"; };

  outputs = { self, dotfiles }: {
    homeConfigurations.default = dotfiles.lib.mkHomeManagerSystem {
      system = "TODO";
      user = "TODO";
      directory = "TODO";
      home = ./home.nix;
    };
    devShells = dotfiles.lib.mkShells { };
  };
}
