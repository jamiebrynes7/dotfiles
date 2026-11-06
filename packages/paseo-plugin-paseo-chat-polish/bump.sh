#!/usr/bin/env bash
# Re-pin paseo-chat-polish to an upstream commit (default: the tip of its default
# branch) and recompute both hashes.
#
# Run by hand only. Deliberately not named update.sh: auto-update.yml runs every
# packages/*/update.sh nightly, and plugin server code runs unsandboxed as the
# daemon user, so each bump should be a reviewed commit.
#
# Usage: bump.sh [REV]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DEFAULT_NIX="${SCRIPT_DIR}/default.nix"
REPO="lthieu96/paseo-chat-polish"

REV="${1:-}"
if [[ -z "$REV" ]]; then
  REV=$(curl -sf "https://api.github.com/repos/${REPO}" | jq -r '.default_branch')
fi
SHA=$(curl -sf "https://api.github.com/repos/${REPO}/commits/${REV}" | jq -r '.sha // empty')
if [[ -z "$SHA" ]]; then
  echo "Error: could not resolve ${REV} in github.com/${REPO}" >&2
  exit 1
fi

CURRENT_SHA=$(sed -n 's/^ *rev = "\([0-9a-f]*\)";/\1/p' "$DEFAULT_NIX")
if [[ "$CURRENT_SHA" == "$SHA" ]]; then
  echo "paseo-chat-polish already at ${SHA}, skipping"
  exit 0
fi

# fetchFromGitHub is a fetchzip of this tarball, so --unpack gives the same NAR hash.
echo "Prefetching ${SHA}..."
SRC_JSON=$(nix store prefetch-file --json --unpack \
  "https://github.com/${REPO}/archive/${SHA}.tar.gz")
SRC_HASH=$(jq -r '.hash' <<<"$SRC_JSON")
SRC_PATH=$(jq -r '.storePath' <<<"$SRC_JSON")

VERSION=$(jq -r '.version' "${SRC_PATH}/package.json")

# Computed against this repo's pinned nixpkgs, which is what buildNpmPackage checks.
echo "Prefetching npm dependencies..."
NPM_DEPS_HASH=$(nix shell --inputs-from "$ROOT_DIR" nixpkgs#prefetch-npm-deps \
  -c prefetch-npm-deps "${SRC_PATH}/package-lock.json")
if [[ -z "$NPM_DEPS_HASH" ]]; then
  echo "Error: prefetch-npm-deps produced no hash" >&2
  exit 1
fi

sed -i.bak \
  -e "s|^\( *version = \)\"[^\"]*\";|\1\"${VERSION}\";|" \
  -e "s|^\( *rev = \)\"[^\"]*\";|\1\"${SHA}\";|" \
  -e "s|^\( *hash = \)\"[^\"]*\";|\1\"${SRC_HASH}\";|" \
  -e "s|^\( *npmDepsHash = \)\"[^\"]*\";|\1\"${NPM_DEPS_HASH}\";|" \
  "$DEFAULT_NIX"
rm -f "${DEFAULT_NIX}.bak"

echo "Updated paseo-chat-polish to ${VERSION} (${SHA})"
echo
echo "Review before committing:"
echo "  https://github.com/${REPO}/compare/${CURRENT_SHA}...${SHA}"
echo "  package.json files (installPhase copies a fixed list):"
jq -r '.files[] | "    " + .' "${SRC_PATH}/package.json"
echo "  paseo requirement: $(jq -r '.requirements.paseo' "${SRC_PATH}/paseo-plugin.json")"
