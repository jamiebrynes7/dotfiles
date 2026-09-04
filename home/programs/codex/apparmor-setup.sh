# shellcheck shell=bash
#
# Installs the nix-bwrap AppArmor profile so bubblewrap can create user namespaces,
# which Codex's default sandbox backend requires. See nix-bwrap.apparmor for why the
# Nix store path needs a profile of its own.
#
# Deliberately imperative and run by hand: it writes root-owned state under /etc, and
# home-manager activation runs unprivileged with no tty on the NixOS systemd path, so
# escalating from there would either hang or need a root-provisioned sudoers rule.

PROFILE_SRC="@profile@"
PROBE="@probe@"
PROFILE_DEST=/etc/apparmor.d/nix-bwrap

dry_run=0
case "${1:-}" in
  --dry-run) dry_run=1 ;;
  "") ;;
  *)
    echo "usage: codex-apparmor-setup [--dry-run]" >&2
    exit 2
    ;;
esac

if [ "$(uname -s)" != Linux ]; then
  echo "codex-apparmor-setup: Linux only; macOS sandboxes Codex with Seatbelt." >&2
  exit 1
fi

if [ -e /etc/NIXOS ] || [ -e /run/current-system/nixos-version ]; then
  # The profile is printed from PROFILE_SRC rather than repeated inline, so this guidance
  # cannot drift from the real thing.
  cat >&2 <<'EOF'
codex-apparmor-setup: this host is NixOS, where /etc is generated — an imperative write to
/etc/apparmor.d does not belong here and would not survive. Declare it instead:

  security.apparmor.enable = true;   # NixOS does not enable AppArmor by default
  security.apparmor.policies."nix-bwrap".profile = ''...'';

Build the policy from the profile below, dropping its `include` lines: NixOS has no
/etc/apparmor.d for <tunables/global> or <local/nix-bwrap> to resolve against.

EOF
  cat "$PROFILE_SRC" >&2
  exit 1
fi

if ! command -v apparmor_parser >/dev/null; then
  echo "codex-apparmor-setup: apparmor_parser not found, so AppArmor is not installed here." >&2
  echo "codex-apparmor-setup: bwrap's failure has another cause; a profile would not fix it." >&2
  exit 1
fi

if [ ! -d /sys/kernel/security/apparmor ]; then
  echo "codex-apparmor-setup: AppArmor is not active on this kernel (/sys/kernel/security/apparmor is missing)." >&2
  echo "codex-apparmor-setup: bwrap's failure has another cause; a profile would not fix it." >&2
  exit 1
fi

# Validate before asking for root, so a malformed profile fails cheaply.
if ! apparmor_parser -Q "$PROFILE_SRC"; then
  echo "codex-apparmor-setup: the profile did not parse on this host; refusing to install it." >&2
  exit 1
fi

# --dry-run reports the plan unconditionally, including on a host that needs no changes:
# previewing is most useful precisely when you do not yet know which case you are in.
if [ "$dry_run" = 1 ]; then
  if "$PROBE" >/dev/null 2>&1; then
    echo "codex-apparmor-setup: bwrap can already create a user namespace, so a real run would change nothing."
    echo
  fi
  echo "codex-apparmor-setup: would install this profile at $PROFILE_DEST:"
  echo
  cat "$PROFILE_SRC"
  echo
  echo "codex-apparmor-setup: would then run:"
  echo "  sudo install -m 0644 $PROFILE_SRC $PROFILE_DEST"
  echo "  sudo apparmor_parser -r -W $PROFILE_DEST"
  exit 0
fi

# Probe before escalating: if bwrap already works there is nothing to do, and this is
# what makes the command safe to re-run.
if "$PROBE" >/dev/null 2>&1; then
  echo "codex-apparmor-setup: bwrap can already create a user namespace; nothing to do."
  exit 0
fi

if ! command -v sudo >/dev/null; then
  echo "codex-apparmor-setup: sudo not found, and installing the profile needs root." >&2
  echo "codex-apparmor-setup: install $PROFILE_DEST as root manually, or set dotfiles.programs.codex.useLegacyLandlock = true." >&2
  exit 1
fi

if [ -e "$PROFILE_DEST" ] && cmp -s "$PROFILE_SRC" "$PROFILE_DEST"; then
  echo "codex-apparmor-setup: $PROFILE_DEST is already current; reloading it."
else
  echo "codex-apparmor-setup: installing $PROFILE_DEST (requires sudo)."
  if ! sudo install -m 0644 "$PROFILE_SRC" "$PROFILE_DEST"; then
    echo "codex-apparmor-setup: could not write $PROFILE_DEST — sudo failed or was declined." >&2
    exit 1
  fi
fi

echo "codex-apparmor-setup: reloading the profile (requires sudo)."
if ! sudo apparmor_parser -r -W "$PROFILE_DEST"; then
  echo "codex-apparmor-setup: apparmor_parser rejected $PROFILE_DEST, or sudo failed." >&2
  echo "codex-apparmor-setup: the profile is installed but not loaded; its error is above." >&2
  exit 1
fi

# Re-probe with stderr left alone: if it still fails, bwrap's own error is the most
# useful thing to show. This is the same probe the codex wrapper gates on, so passing
# here means codex will start.
if "$PROBE" >/dev/null; then
  echo "codex-apparmor-setup: bwrap can now create a user namespace. Codex will start."
else
  echo >&2
  echo "codex-apparmor-setup: bwrap still cannot create a user namespace; its error is above." >&2
  echo "codex-apparmor-setup: confirm the profile loaded with 'aa-status | grep nix-bwrap'." >&2
  echo "codex-apparmor-setup: otherwise set dotfiles.programs.codex.useLegacyLandlock = true to use Codex's Landlock backend." >&2
  exit 1
fi
