{
  description = "System configuration for $system";

  inputs = { dotfiles.url = "git+ssh://git@github.com/jamiebrynes7/dotfiles"; };

  outputs = { self, dotfiles }: {
    darwinConfigurations.default = dotfiles.lib.mkDarwin {
      hostname = "TODO";
      user = "TODO";
      home = ./home.nix;
      modules = [ ./configuration.nix ];
    };
    devShells = dotfiles.lib.mkShells { };
  };
}
