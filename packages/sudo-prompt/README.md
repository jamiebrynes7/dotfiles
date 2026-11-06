# sudo-prompt

A native macOS password dialog for `sudo` when there is no terminal, so agents
and other background processes can escalate with your explicit approval instead
of failing with "a terminal is required".

`home/programs/sudo-prompt.nix` (`dotfiles.programs.sudo-prompt.enable`) installs
a `sudo` wrapper ahead of `/usr/bin/sudo` on `PATH`:

- **With a terminal** it execs `/usr/bin/sudo "$@"` untouched.
- **Without one** it runs `/usr/bin/sudo -A -k "$@"` with this binary as
  `SUDO_ASKPASS`. The dialog shows the command, who asked and the working
  directory. Cancel makes sudo fail as if no password were given.

## Design notes

- **The command shown is verified, not claimed.** An unprivileged process can't
  read the argv of root-owned `sudo` (`KERN_PROCARGS2` returns EINVAL); only the
  setuid `/bin/ps` can, and only space-joined. So the wrapper passes the exact
  argv in `SUDO_PROMPT_ARGV`, and the dialog uses it only if it joins to exactly
  what `ps` reports for its parent `sudo`. Otherwise (e.g. `/usr/bin/sudo -A`
  called directly) it shows `ps`'s raw line with a warning.
- **`-k` on every terminal-less call.** It ignores and doesn't refresh the
  credential cache, so one approval can't silently authorize the next command.
- **`sh -c` scripts are split one step per line** at top-level `&&` `||` `;` `|`,
  so a long chain can't bury a step mid-line. Nothing is truncated; long
  commands scroll.
- **The panel stays up until answered** — on every Space, above other windows,
  and not hidden when focus moves elsewhere (`hidesOnDeactivate = false`).

## Test

```bash
swift test
```

With the system Apple toolchain; nixpkgs' Darwin Swift has no XCTest. Only the
pure `SudoPromptCore` target is covered.

To see the dialog without risk, use `sh -n` (parse only, runs nothing):

```bash
SUDO_ASKPASS=$PWD/.build/debug/sudo-prompt /usr/bin/sudo -A -k /bin/sh -nc 'echo hi && id'
```

(Called this way there is no `SUDO_PROMPT_ARGV`, so expect the warning.)
