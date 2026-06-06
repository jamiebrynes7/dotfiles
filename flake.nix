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
    # crane is nixpkgs-agnostic (no `nixpkgs` input to follow); it reads pkgs
    # from `crane.mkLib pkgs` at call sites.
    crane.url = "github:ipetkov/crane";

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
          # Bare `default` profile (rustc, cargo, clippy, rustfmt) used to build
          # packages. The `rust-src` extension lays down a `lib/rustlib/src/rust/library`
          # tree in the toolchain store path; compiled binaries embed those source
          # paths (panic/debuginfo metadata), so Nix's scanner records the whole
          # toolchain as a runtime dep. Excluding `rust-src` here removes the only
          # such reference, keeping it out of the package's runtime closure.
          buildToolchain = rustyPkgs.rust-bin.stable.latest.default;
          # devShell toolchain: build toolchain plus dev-only extensions.
          rustToolchain = buildToolchain.override {
            extensions = [
              "rust-src"
              "rust-analyzer"
            ];
          };

          # crane, pinned to the bare `buildToolchain` (not the fat devShell
          # `rustToolchain`) so dev-only extensions stay out of the package
          # closure. `rustfmt` and `clippy` are in the `default` profile, so the
          # fmt/clippy checks work without extra components.
          craneLib = (inputs.crane.mkLib final).overrideToolchain buildToolchain;
          # Args shared by the package build, its dependency-only artifact cache,
          # and the clippy/test checks — so cargo deps compile once and every
          # derivation reuses the same `cargoArtifacts`.
          commonArgs = {
            # Full workspace tree, not `cleanCargoSource`: `beansd` embeds
            # non-Rust assets (askama `.html` templates compiled by the derive
            # macro, plus `.css`/`.js` static files) that the cargo-only filter
            # would strip. `buildDepsOnly` keys its cache off Cargo.{toml,lock}
            # only, so including assets here doesn't churn the artifact cache.
            src = final.lib.fileset.toSource {
              root = ./.;
              fileset = final.lib.fileset.unions [
                ./Cargo.toml
                ./Cargo.lock
                ./crates
              ];
            };
            strictDeps = true;
            cargoExtraArgs = "--locked --workspace";
            buildInputs = final.lib.optionals final.stdenv.isDarwin [ final.libiconv ];
          };
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;

          packageArgs = {
            beans-daemon = { inherit craneLib commonArgs cargoArtifacts; };
          };
          packages = builtins.mapAttrs (
            name: path: final.callPackage path (packageArgs.${name} or { })
          ) packagePaths;

          # Workspace-wide Rust lint/test gates surfaced as flake checks. Named
          # `rust-*` (not `beans-daemon-*`) because `--workspace` means they
          # cover every crate, not just the shipped package. Wired into
          # `checks.<system>` below so `nix flake check` runs fmt → clippy → test
          # alongside the package build, sharing `cargoArtifacts`.
          rustChecks = {
            rust-fmt = craneLib.cargoFmt { inherit (commonArgs) src; };
            rust-clippy = craneLib.cargoClippy (
              commonArgs
              // {
                inherit cargoArtifacts;
                cargoClippyExtraArgs = "--all-targets -- -D warnings";
              }
            );
            rust-test = craneLib.cargoNextest (commonArgs // { inherit cargoArtifacts; });
          };
        in
        {
          dotfiles = packages // {
            internal = { inherit rustToolchain rustChecks; };
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
      checks = {
        aarch64-darwin = self.packages.aarch64-darwin // (nixDarwinPkgs { }).dotfiles.internal.rustChecks;
        x86_64-linux =
          self.packages.x86_64-linux // (nixOsPkgs { system = "x86_64-linux"; }).dotfiles.internal.rustChecks;
      };
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
