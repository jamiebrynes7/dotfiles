{
  description = "Jamie Brynes's dotfiles";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-24.11-darwin";
    darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-24.11";
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

      mkNixosSystem =
        { system, hostname, user, home, modules ? [ ], overlays ? [ ] }@args:
        let pkgs = nixOsPkgs { inherit overlays system; };
        in inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            {
              nixpkgs.pkgs = pkgs;
              networking.hostName = args.hostname;
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users.${user} = inputs.nixpkgs.lib.modules.importApply ./home {
                  inherit home;
                };
              };
            }
            inputs.home-manager.nixosModules.home-manager
          ] ++ modules;
          specialArgs = { inherit inputs; };
        };

      mkHomeManagerSystem =
        { system, user, directory, home, overlays ? [ ] }@args:
        let pkgs = nixOsPkgs { inherit overlays system; };
        in inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            {
              home = {
                username = user;
                homeDirectory = directory;
              };
            }
            {
              imports = [
                (inputs.nixpkgs.lib.modules.importApply ./home {
                  inherit home;
                })
              ];
            }
          ];
        };

      baseShellPkgs = { pkgs, ... }: {
        packages = with pkgs; [ just nil nixfmt-classic ];
      };

      mkDarwinShell = { modules }:
        let pkgs = nixDarwinPkgs { };
        in inputs.devenv.lib.mkShell {
          inherit pkgs inputs;
          modules = [ baseShellPkgs ] ++ modules;
        };

      mkLinuxShell = { system, modules }:
        let pkgs = nixOsPkgs { inherit system; };
        in inputs.devenv.lib.mkShell {
          inherit pkgs inputs;
          modules = [ baseShellPkgs ] ++ modules;
        };

      mkShells = { modules ? [ ] }: {
        aarch64-darwin.default = mkDarwinShell { inherit modules; };
        x86_64-linux.default = mkLinuxShell {
          inherit modules;
          system = "x86_64-linux";
        };
      };

    in {
      lib = { inherit mkNixosSystem mkDarwin mkHomeManagerSystem mkShells; };
      devShells = mkShells { };
      templates = {
        darwin = {
          path = ./templates/darwin;
          description =
            "A template for a Darwin system managed with nix-darwin";
        };
        nixos = {
          path = ./templates/nixos;
          description = "A template for a NixOS system";
        };
        home-manager = {
          path = ./templates/home-manager;
          description = "A template for a home-manager system";
        };
      };
    };
}
