# Usage: dotfiles-nix-gc <keep> <profile-dir>...
#
# Takes `nix` from the caller's PATH rather than a store path, so it drives
# whichever Nix the machine actually runs — Determinate included.
{ coreutils, writeShellApplication }:
writeShellApplication {
  name = "dotfiles-nix-gc";
  runtimeInputs = [ coreutils ];
  text = ''
    keep=$1
    shift

    shopt -s nullglob
    for dir in "$@"; do
      for profile in "$dir"/*; do
        name=''${profile##*/}
        # A profile links to a sibling `<name>-<N>-link` generation. This skips
        # the generation links themselves, and profiles that point elsewhere
        # (`/nix/var/nix/profiles/default` -> `per-user/root/profile`).
        [[ -L $profile && $(readlink "$profile") =~ ^"$name"-[0-9]+-link$ ]] || continue
        echo "pruning $profile to its last $keep generations"
        nix-env --profile "$profile" --delete-generations "+$keep"
      done
    done

    nix-collect-garbage
    nix store optimise
  '';
}
