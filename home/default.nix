{ home, inputs }:
{ pkgs, ... }:
let
  programsDir = builtins.readDir ./programs/.;
  programs = builtins.map (name: ./programs/${name}) (
    builtins.filter (
      name:
      let
        entry = builtins.getAttr name programsDir;
      in
      (entry == "regular" && builtins.match ".*\\.nix" name != null && name != "default.nix")
      || (entry == "directory")
    ) (builtins.attrNames programsDir)
  );
in
{
  imports = [
    home
    ./profiles.nix
    # Inert on Linux: mac-app-util's `systems` input is nix-systems/default-darwin,
    # so its `enable` default (does self.packages have this system?) is false there.
    inputs.mac-app-util.homeManagerModules.default
  ]
  ++ programs;
}
