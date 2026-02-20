# Dotfiles

This repository contains my personal dotfiles and system configurations managed through Nix flakes. It provides a reproducible and declarative approach to managing both NixOS and macOS (Darwin) system configurations.

## Repository Structure

```
.
├── flake.nix          # Main flake configuration
├── darwin/            # Darwin-specific configurations
├── home/              # Home-manager configurations
├── templates/         # Template configurations
│   ├── darwin/        # Template for Darwin systems
│   └── nixos/         # Template for NixOS systems

```

## Getting Started

### Using the Templates

This repository exposes multiple templates that you can use as starting points for your own configurations:

For macOS/Darwin systems:

```bash
nix flake init -t github:jamiebrynes7/dotfiles#system/darwin
```

For NixOS systems:

```bash
nix flake init -t github:jamiebrynes7/dotfiles#system/nixos
```

These commands will create the necessary configuration files in your current directory, which you can then customize for your specific needs.

### Iteration

When iterating on this repository and a child one, its easiest to set the local flake ref to avoid the constant need to push. To do so, update the flake URL:

```diff
-  inputs = { dotfiles.url = "github:jamiebrynes7/dotfiles"; };
+  inputs = { dotfiles.url = "path:${DOTFILES_PATH}"; };
```

And run:

```
nix flake update
```

---

For more information about Nix flakes, see the [official documentation](https://nixos.wiki/wiki/Flakes).
