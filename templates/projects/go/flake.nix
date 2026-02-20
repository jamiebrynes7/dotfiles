{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    systems.url = "github:nix-systems/default";
    devenv.url = "github:cachix/devenv";
  };

  outputs = { self, nixpkgs, devenv, systems, ... }@inputs:
    let forEachSystem = nixpkgs.lib.genAttrs (import systems);
    in {
      devShells = forEachSystem (system:
        let
          overlays = [ ];
          pkgs = import nixpkgs { inherit system overlays; };
        in {
          default = devenv.lib.mkShell {
            inherit inputs pkgs;
            modules = [{
              packages = with pkgs; [
                go
                gopls
                gotools
                golangci-lint

                nil
                nixfmt-classic
              ];
            }];
          };
        });
    };
}
