---
# dotfiles-t4ve
title: Move a daemon-written config.json aside before linking
status: todo
type: task
priority: normal
created_at: 2026-09-21T17:29:14Z
updated_at: 2026-09-21T17:30:08Z
parent: dotfiles-eii4
---

**Files:**
- Modify: `home/programs/paseo.nix:292-306` — add `home.activation.paseoConfigBackup` inside the `lib.mkIf cfg.enable` block, next to the existing `paseoDataDirMode` entry

Home-manager refuses to link over an existing regular file ("existing file in the way") unless `home.backupFileExtension` is set repo-wide. Rather than depend on that, move the file aside from the module. Two cases need it: the first switch on a host whose `config.json` the daemon wrote, and the desktop app's unpatched bundled daemon overwriting the symlink later.

- [ ] **Step 1: Add the activation entry**

```nix
      # Before the write boundary so home.file can link over the path. Never deletes:
      # this is the migration path for a host adopting a managed config, and the
      # recovery path for the desktop app's unpatched bundled daemon.
      home.activation.paseoConfigBackup = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
        paseoConfig=${lib.escapeShellArg "${cfg.dataDir}/config.json"}
        paseoOldConfigTarget=""
        if [ -L "$paseoConfig" ]; then
          paseoOldConfigTarget="$(readlink "$paseoConfig")"
        elif [ -e "$paseoConfig" ]; then
          paseoBackup="$paseoConfig.daemon-$(date +%Y%m%d%H%M%S)"
          warnEcho "paseo: daemon-written config.json moved aside to $paseoBackup"
          run mv "$paseoConfig" "$paseoBackup"
        fi
      '';
```

`paseoOldConfigTarget` is read by the restart task's entry. Home-manager concatenates DAG entries into a single bash script, so the variable survives across entries; `run` and `warnEcho` are home-manager's own activation helpers, and `run` is what makes `--dry-run` honest.

- [ ] **Step 2: Format**

Run: `nixfmt home/programs/paseo.nix`

- [ ] **Step 3: Exercise the script against a real directory**

```bash
tmp=$(mktemp -d)
mkdir -p "$tmp/.paseo"
echo '{"daemon":{}}' > "$tmp/.paseo/config.json"
script=$(nix eval --impure --raw --expr "
  let
    flake = builtins.getFlake (toString ./.);
    hm = flake.lib.mkHomeManagerSystem {
      system = builtins.currentSystem;
      user = \"test\";
      directory = \"$tmp\";
      home = { ... }: {
        home.stateVersion = \"25.05\";
        dotfiles.profiles.base = false;
        dotfiles.programs.paseo.enable = true;
      };
    };
  in hm.config.home.activation.paseoConfigBackup.data
")
run() { "$@"; }
warnEcho() { echo "$@"; }
eval "$script"
ls "$tmp/.paseo"
```

Expected: the warning prints and `ls` shows a single `config.json.daemon-<timestamp>` and no `config.json`.

- [ ] **Step 4: Re-run to confirm it is a no-op when there is nothing to move**

```bash
eval "$script"
ls "$tmp/.paseo"
```

Expected: no warning, no new backup file — the `elif [ -e ]` branch does not fire. Then `rm -rf "$tmp"`.

- [ ] **Step 5: Commit**

```bash
git add home/programs/paseo.nix
git commit -m "home/programs/paseo: move a daemon-written config.json aside" -m "Bean: dotfiles-t4ve"
```
