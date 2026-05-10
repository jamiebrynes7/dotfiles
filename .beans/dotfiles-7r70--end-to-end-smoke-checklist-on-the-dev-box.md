---
# dotfiles-7r70
title: End-to-end smoke checklist on the dev box
status: todo
type: task
priority: normal
created_at: 2026-05-03T14:42:39Z
updated_at: 2026-05-10T15:53:09Z
parent: dotfiles-24hc
---

**Files:**
- None modified (this is verification, not implementation).

After F1–F10 are merged, install on the user's actual host config and walk through the following checklist. Report any failure as a follow-up bean.

- [ ] **1. Enable in the host config**

Add to the relevant host's home-manager config (e.g., the user's NixOS host):
```nix
dotfiles.programs.beans-daemon.enable = true;
```

- [ ] **2. Apply the config**

Build and switch:
```bash
home-manager switch --flake .
```
Expected: no errors. `~/.config/beans-daemon/config.toml` exists and points `beans_serve_path` to a Nix store binary.

- [ ] **3. Verify the systemd-user service is running**

```bash
systemctl --user status beans-daemon
```
Expected: `Active: active (running)`.
Logs: `journalctl --user -u beans-daemon -f` should show `beansd starting`, `UDS bound`, `HTTP launcher bound`.

- [ ] **4. Verify the launcher loads**

Open `http://localhost:9000` in a browser.
Expected: empty-state page ("Select a project from the left.").

- [ ] **5. Verify cd-hook registration**

Open a fresh shell, then:
```bash
cd ~/workspace/dotfiles    # this repo has .beans.yml
beansctl ls
```
Expected JSON output lists this project with state `spawning` then `healthy` after a beat.

- [ ] **6. Verify the launcher shows the project**

Refresh `http://localhost:9000`. The dotfiles project appears in the left nav with a `healthy` badge. Clicking it loads the iframe pointing at the per-project port.

- [ ] **7. Verify heartbeat fires**

Watch journal: `journalctl --user -u beans-daemon -f`. Click the project so its iframe is loaded; observe heartbeat-induced bumps (you can use `beansctl ls` repeatedly to watch `last_used` advance).

- [ ] **8. Verify LRU eviction**

Set `lruCap = 2` temporarily, switch, then cd into 3 different beans projects. Expected: oldest is evicted; `journalctl` logs `evicting project`.

- [ ] **9. Verify graceful restart**

```bash
systemctl --user restart beans-daemon
```
Expected: clean restart, registry repopulates as you cd around.

- [ ] **10. Document any issues as follow-up beans**

Any deviation from expected behaviour: open a bug bean against the relevant feature.

- [ ] **11. Mark this bean completed**

Once all checks pass, mark this bean and the parent epic completed.
