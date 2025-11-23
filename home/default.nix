{ home }:
{ pkgs, ... }:
let
  programsDir = builtins.readDir ./programs/.;
  programs = builtins.map (name: ./programs/${name}) (builtins.filter (name:
    let entry = builtins.getAttr name programsDir;
    in (entry == "regular" && builtins.match ".*\\.nix" name != null && name
      != "default.nix") || (entry == "directory"))
    (builtins.attrNames programsDir));
in { imports = [ home ./profiles.nix ] ++ programs; }
