{
  description = "Jamie Brynes's dotfiles";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-25.11-darwin";
    darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Overlays
    alacritty-themes = {
      url = "github:alexghr/alacritty-theme.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Tools
    claude-code = {
      url = "github:jamiebrynes7/claude-code-native-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sprites-cli = {
      url = "github:jamiebrynes7/sprite-cli-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      defaultOverlays = [
        inputs.alacritty-themes.overlays.default
        inputs.claude-code.overlays.default
        inputs.sprites-cli.overlays.default
      ];

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

      baseShellPkgs = pkgs: with pkgs; [ just nil nixfmt-classic ];

      mkShells = { extraPackages ? [ ] }: {
        aarch64-darwin.default =
          let pkgs = nixDarwinPkgs { };
          in pkgs.mkShell { packages = baseShellPkgs pkgs ++ extraPackages; };
        x86_64-linux.default =
          let pkgs = nixOsPkgs { system = "x86_64-linux"; };
          in pkgs.mkShell { packages = baseShellPkgs pkgs ++ extraPackages; };
      };

      discoverPackages = dir:
        let entries = builtins.readDir dir;
        in builtins.listToAttrs (builtins.map (name: {
          inherit name;
          value = dir + "/${name}";
        }) (builtins.filter (name: entries.${name} == "directory")
          (builtins.attrNames entries)));

      packagePaths = discoverPackages ./packages;

      mkPackages = pkgs:
        builtins.mapAttrs (_: path: pkgs.callPackage path { }) packagePaths;

    in {
      lib = { inherit mkNixosSystem mkDarwin mkHomeManagerSystem mkShells; };
      devShells = mkShells { };
      packages = {
        aarch64-darwin = mkPackages (nixDarwinPkgs { });
        x86_64-linux = mkPackages (nixOsPkgs { system = "x86_64-linux"; });
      };
      templates = {
        "system/darwin" = {
          path = ./templates/systems/darwin;
          description =
            "A template for a Darwin system managed with nix-darwin";
        };
        "system/nixos" = {
          path = ./templates/systems/nixos;
          description = "A template for a NixOS system";
        };
        "system/home-manager" = {
          path = ./templates/systems/home-manager;
          description = "A template for a home-manager system";
        };
        "project/go" = {
          path = ./templates/projects/go;
          description = "A template for a Go project";
        };
        "project/typescript" = {
          path = ./templates/projects/typescript;
          description = "A template for a TypeScript project";
        };
      };
    };
}
