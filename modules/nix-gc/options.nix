{ lib, ... }:
{
  options.dotfiles.nix.gc = {
    enable =
      lib.mkEnableOption "a weekly job that prunes Nix profiles, collects garbage and optimises the store"
      // {
        default = true;
      };

    keepGenerations = lib.mkOption {
      type = lib.types.ints.positive;
      default = 5;
      description = ''
        Generations to keep per profile. `nix-collect-garbage` can only delete
        by age, so the job prunes each profile with
        `nix-env --delete-generations +N` before collecting.
      '';
    };
  };
}
