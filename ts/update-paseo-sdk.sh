#!/usr/bin/env bash
# Re-pins @getpaseo/plugin in every repo-local paseo plugin to VERSION and refreshes
# its lockfile, keeping ts/default.nix's `<dir>-sdk-version` check green across a
# paseo bump. packages/paseo/update.sh calls this before writing hashes.json.
#
# Every plugin is resolved in a staging copy first and only then copied back, so a
# failure (a version npm does not have, or a resolution error) leaves every plugin
# as it was.
set -euo pipefail
shopt -s nullglob

VERSION="${1:?usage: update-paseo-sdk.sh VERSION}"
TS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${TS_DIR}/.." && pwd)"
SDK="@getpaseo/plugin"

# The flake's own nodejs, resolved once: npm's version shapes the lockfile.
NODEJS="$(nix build --no-link --print-out-paths --inputs-from "$ROOT_DIR" nixpkgs#nodejs)"
npm() {
  "${NODEJS}/bin/npm" "$@"
}

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

plugins=("$TS_DIR"/paseo-plugin-*/)
for dir in "${plugins[@]}"; do
  name="$(basename "$dir")"
  echo "Re-pinning ${SDK} to ${VERSION} in ts/${name}..."
  mkdir "${STAGING}/${name}"
  cp "${dir}package.json" "${dir}package-lock.json" "${STAGING}/${name}/"
  (
    cd "${STAGING}/${name}"
    npm pkg set "devDependencies.${SDK}=${VERSION}"
    # Explicit registry: a mirror in ~/.npmrc would otherwise land in `resolved`,
    # which CI's importNpmLock then has to fetch.
    npm install --package-lock-only --ignore-scripts --no-audit --no-fund \
      --registry=https://registry.npmjs.org/
  )
done

# Copy back only what changed, so a no-op re-pin leaves the tree clean.
for dir in "${plugins[@]}"; do
  name="$(basename "$dir")"
  for file in package.json package-lock.json; do
    cmp -s "${STAGING}/${name}/${file}" "${dir}${file}" || cp "${STAGING}/${name}/${file}" "${dir}${file}"
  done
done
