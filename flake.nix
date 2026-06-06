{
  description = "Jamie Brynes's dotfiles";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-26.05-darwin";
    darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Overlays
    alacritty-themes = {
      url = "github:alexghr/alacritty-theme.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
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

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      discoverPackages =
        dir:
        let
          entries = builtins.readDir dir;
        in
        builtins.listToAttrs (
          builtins.map (name: {
            inherit name;
            value = dir + "/${name}";
          }) (builtins.filter (name: entries.${name} == "directory") (builtins.attrNames entries))
        );

      packagePaths = discoverPackages ./packages;

      # rust-overlay is applied to `prev` here so `rust-bin.*` doesn't leak
      # into consumer pkgs via `defaultOverlays`.
      dotfilesOverlay =
        final: prev:
        let
          rustyPkgs = prev.appendOverlays [ inputs.rust-overlay.overlays.default ];
          rustToolchain = rustyPkgs.rust-bin.stable.latest.default.override {
            extensions = [
              "rust-src"
              "rust-analyzer"
            ];
          };
          rustPlatform = final.makeRustPlatform {
            cargo = rustToolchain;
            rustc = rustToolchain;
          };
          packageArgs = {
            beans-daemon = { inherit rustPlatform; };
          };
          packages = builtins.mapAttrs (
            name: path: final.callPackage path (packageArgs.${name} or { })
          ) packagePaths;
        in
        {
          dotfiles = packages // {
            internal = { inherit rustToolchain; };
          };
        };

      defaultOverlays = [
        inputs.alacritty-themes.overlays.default
        inputs.claude-code.overlays.default
        inputs.sprites-cli.overlays.default
        dotfilesOverlay
      ];

      nixOsPkgs =
        {
          overlays ? [ ],
          system,
        }:
        import inputs.nixpkgs {
          inherit system;
          overlays = overlays ++ defaultOverlays;
          config.allowUnfree = true;
        };

      nixDarwinPkgs =
        {
          overlays ? [ ],
        }:
        import inputs.nixpkgs-darwin {
          system = "aarch64-darwin";
          overlays = overlays ++ defaultOverlays;
          config.allowUnfree = true;
        };

      mkDarwin =
        {
          hostname,
          user,
          home,
          modules ? [ ],
          overlays ? [ ],
        }@args:
        let
          pkgs = nixDarwinPkgs { inherit overlays; };
        in
        inputs.darwin.lib.darwinSystem {
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
          ]
          ++ modules;
        };

      mkNixosSystem =
        {
          system,
          hostname,
          user,
          home,
          modules ? [ ],
          overlays ? [ ],
        }@args:
        let
          pkgs = nixOsPkgs { inherit overlays system; };
        in
        inputs.nixpkgs.lib.nixosSystem {
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
          ]
          ++ modules;
          specialArgs = { inherit inputs; };
        };

      mkHomeManagerSystem =
        {
          system,
          user,
          directory,
          home,
          overlays ? [ ],
        }@args:
        let
          pkgs = nixOsPkgs { inherit overlays system; };
        in
        inputs.home-manager.lib.homeManagerConfiguration {
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

      baseShellPkgs =
        pkgs: with pkgs; [
          just
          nil
          nixfmt
        ];

      mkShells =
        {
          extraPackages ? (_: [ ]),
          extraEnv ? (_: { }),
        }:
        let
          mkOne =
            pkgs:
            pkgs.mkShell (
              {
                packages = baseShellPkgs pkgs ++ extraPackages pkgs;
              }
              // extraEnv pkgs
            );
        in
        {
          aarch64-darwin.default = mkOne (nixDarwinPkgs { });
          x86_64-linux.default = mkOne (nixOsPkgs {
            system = "x86_64-linux";
          });
        };

      mkPackages = pkgs: builtins.removeAttrs pkgs.dotfiles [ "internal" ];

    in
    {
      lib = {
        inherit
          mkNixosSystem
          mkDarwin
          mkHomeManagerSystem
          mkShells
          ;
      };
      devShells = mkShells {
        extraPackages = pkgs: [ pkgs.dotfiles.internal.rustToolchain ];
        extraEnv = pkgs: {
          RUST_SRC_PATH = "${pkgs.dotfiles.internal.rustToolchain}/lib/rustlib/src/rust/library";
          shellHook = ''
            git config core.hooksPath .githooks
          '';
        };
      };
      packages = {
        aarch64-darwin = mkPackages (nixDarwinPkgs { });
        x86_64-linux = mkPackages (nixOsPkgs {
          system = "x86_64-linux";
        });
      };
      checks = self.packages;
      templates = {
        "system/darwin" = {
          path = ./templates/systems/darwin;
          description = "A template for a Darwin system managed with nix-darwin";
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
