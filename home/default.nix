{ home }:
{ pkgs, ... }:
let
  programs = builtins.map (f: ./programs/${f}) (builtins.filter
    (f: builtins.match ".*\\.nix" f != null && f != "default.nix")
    (builtins.attrNames (builtins.readDir ./programs/.)));
in { imports = [ home ./profiles.nix ./modules/vscodes.nix ] ++ programs; }
