{
  description = "Jamie Brynes's dotfiles";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-24.11-darwin";
    darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Overlays
    alacritty-themes = {
      url = "github:alexghr/alacritty-theme.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Tools
    devenv.url = "github:cachix/devenv";
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      defaultOverlays = [ inputs.alacritty-themes.overlays.default ];

      nixOsPkgs = { overlays ? [ ], system }:
        import inputs.nixpkgs {
          inherit system;
          overlays = overlays ++ defaultOverlays;
          config.allowUnfree = true;
        };

      nixDarwinPkgs = { overlays ? [ ] }:
        import inputs.nixpkgs-darwin {
          system = "aarch64-darwin";
          overlays = overlays ++ defaultOverlays;
          config.allowUnfree = true;
        };

      mkDarwin = { hostname, user, home, modules ? [ ], overlays ? [ ] }@args:
        let pkgs = nixDarwinPkgs { inherit overlays; };
        in inputs.darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          modules = [
            {
              nixpkgs.pkgs = pkgs;
              users.users."${args.user}".home = "/Users/${args.user}";
              networking.hostName = args.hostname;
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users.${user} = inputs.nixpkgs.lib.modules.importApply ./home {
                  inherit home;
                };
              };
            }
            ./darwin
            inputs.home-manager.darwinModules.home-manager
          ] ++ modules;
        };

      mkDarwinShell = { }:
        let pkgs = nixDarwinPkgs { };
        in inputs.devenv.lib.mkShell {
          inherit pkgs inputs;
          modules =
            [ ({ pkgs, config, ... }: { packages = with pkgs; [ just ]; }) ];
        };

      mkShells = { }: { aarch64-darwin.default = mkDarwinShell { }; };

    in { lib = { inherit mkDarwin mkShells; }; };
}
