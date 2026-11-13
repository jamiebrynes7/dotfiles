#!/usr/bin/env bash
# Runs a throwaway paseo daemon loading the named repo-local plugins, for trying a
# plugin by hand before it reaches a host. It is isolated from the real daemon: its
# own PASEO_HOME (wiped on start) and its own port. Add it in the Paseo app as a host
# at 127.0.0.1:<port>, no password. Ctrl-C stops it.
#
#   ts/paseo-demo.sh beans [direnv ...]
#
# Each plugin is built from the flake (pkgs.dotfiles.paseo-plugin-<id>), the store path
# a host would load, so `git add` working-tree edits first, and re-run to pick up a
# rebuild. A plugin with a `demo/seed.sh` gets it run once the daemon is listening,
# with PASEO_HOME pointing at the demo, to create and register demo workspaces.
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "usage: $0 <plugin-id>... (e.g. beans)" >&2
  exit 2
fi

TS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${TS_DIR}/.." && pwd)"
export PASEO_HOME="${PASEO_DEMO_HOME:-/tmp/paseo-demo-home}"
PORT="${PASEO_DEMO_PORT:-6868}"
SYSTEM="$(nix eval --raw --impure --expr builtins.currentSystem)"

plugins="{}"
for id in "$@"; do
  if [[ ! -d "${TS_DIR}/paseo-plugin-${id}" ]]; then
    echo "no repo-local plugin ts/paseo-plugin-${id}" >&2
    exit 2
  fi
  path="$(nix build --no-link --print-out-paths "${ROOT_DIR}#packages.${SYSTEM}.paseo-plugin-${id}")"
  plugins="$(jq --arg id "$id" --arg path "$path" \
    '. + { ($id): { source: "directory", path: $path, enabled: true } }' <<<"$plugins")"
done

rm -rf "$PASEO_HOME"
mkdir -p "$PASEO_HOME"
# The two creation defaults the paseo module also supplies (home/programs/paseo.nix),
# and the MCP injection that carries plugin agent tools to agents. Unlike the module,
# this leaves Paseo's built-in tools enabled: they can only reach this throwaway daemon.
jq -n --argjson plugins "$plugins" '{
  app: { baseUrl: "https://app.paseo.sh" },
  daemon: { cors: { allowedOrigins: ["https://app.paseo.sh"] }, mcp: { injectIntoAgents: true } },
  pluginsEnabled: true,
  plugins: $plugins
}' >"${PASEO_HOME}/config.json"

PASEO_LISTEN="127.0.0.1:${PORT}" paseo-server >"${PASEO_HOME}/server.log" 2>&1 &
server=$!
# `wait` returns on a trapped signal, so a SIGINT or SIGTERM aimed at this script
# alone (not just a terminal Ctrl-C to the group) still reaches the EXIT cleanup.
trap 'paseo daemon stop >/dev/null 2>&1 || kill "$server" 2>/dev/null; wait "$server" 2>/dev/null' EXIT
trap 'exit 130' INT TERM

for _ in $(seq 1 60); do
  paseo plugin ls >/dev/null 2>&1 && break
  kill -0 "$server" 2>/dev/null || { cat "${PASEO_HOME}/server.log" >&2; exit 1; }
  sleep 0.5
done

for id in "$@"; do
  seed="${TS_DIR}/paseo-plugin-${id}/demo/seed.sh"
  if [[ -x "$seed" ]]; then
    echo "seeding ${id}…"
    "$seed"
  fi
done

paseo plugin ls
echo
echo "paseo demo daemon on 127.0.0.1:${PORT} (home ${PASEO_HOME}, log server.log)."
echo "Add it as a host in the Paseo app; Ctrl-C to stop."
wait "$server"
