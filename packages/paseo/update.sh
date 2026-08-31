#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPO="getpaseo/paseo"

# Parse args: optional VERSION positional, optional --force to recompute hashes
# even when the recorded version already matches.
FORCE=0
VERSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f | --force)
      FORCE=1
      shift
      ;;
    -*)
      echo "Error: unknown option: $1" >&2
      exit 1
      ;;
    *)
      VERSION="$1"
      shift
      ;;
  esac
done

# Resolve version
if [[ -z "$VERSION" ]]; then
  VERSION=$(curl -sf "https://api.github.com/repos/${REPO}/releases/latest" \
    | jq -r '.tag_name | ltrimstr("v")')
  echo "Latest version: ${VERSION}"
fi
TAG="v${VERSION}"

# Skip all hash work when the recorded version already matches (unless --force).
CURRENT_VERSION=$(jq -r '.version // empty' "${SCRIPT_DIR}/hashes.json" 2>/dev/null || true)
if [[ "$FORCE" -ne 1 && -n "$CURRENT_VERSION" && "$CURRENT_VERSION" == "$VERSION" ]]; then
  echo "paseo already at ${VERSION}, skipping"
  exit 0
fi

# Validate the tag exists as a GitHub release
if ! curl -sfI "https://github.com/${REPO}/releases/tag/${TAG}" >/dev/null; then
  echo "Error: Release ${TAG} not found at github.com/${REPO}" >&2
  exit 1
fi

# Desktop app: electron-builder's own manifest carries a base64 sha512 per
# asset, which is a valid SRI. Reading it avoids downloading ~150MB nightly.
# Checked before the source/npm work below because it is the step most likely to
# fail on a freshly cut tag, and it costs one request instead of minutes.
DESKTOP_ARTIFACT="Paseo-${VERSION}-arm64.zip"
echo "Reading ${DESKTOP_ARTIFACT} hash from latest-mac.yml..."
MAC_YML=$(curl -sfL "https://github.com/${REPO}/releases/download/${TAG}/latest-mac.yml" || true)
DESKTOP_SHA512=$(awk -v want="url: ${DESKTOP_ARTIFACT}" '
  index($0, want) { found = 1; next }
  found && /sha512:/ { print $2; exit }
' <<<"$MAC_YML")
if [[ -z "$DESKTOP_SHA512" ]]; then
  # Usually transient: upstream tags the release, then CI uploads the artifacts
  # minutes later. But that is indistinguishable here from upstream renaming the
  # artifact or dropping the mac build, so fail rather than exit 0 — a silent
  # skip would pin paseo forever behind a green nightly. The workflow runs every
  # update script before reporting failures, so this does not block the others.
  echo "Error: ${TAG} has no ${DESKTOP_ARTIFACT} in latest-mac.yml." >&2
  echo "       If the release was just cut, its assets may still be uploading;" >&2
  echo "       if this persists, upstream changed its artifact naming." >&2
  exit 1
fi
DESKTOP_HASH="sha512-${DESKTOP_SHA512}"

# Source tarball. fetchFromGitHub is a fetchzip, so --unpack gives the matching
# NAR hash. The unpacked store path feeds the two steps below.
echo "Prefetching source for ${TAG}..."
SRC_JSON=$(nix store prefetch-file --json --unpack \
  "https://github.com/${REPO}/archive/refs/tags/${TAG}.tar.gz")
SRC_HASH=$(jq -r '.hash' <<<"$SRC_JSON")
SRC_PATH=$(jq -r '.storePath' <<<"$SRC_JSON")
if [[ -z "$SRC_HASH" || "$SRC_HASH" == "null" ]]; then
  echo "Error: Failed to prefetch source for ${TAG}" >&2
  exit 1
fi

# Guard: every package-lock.json entry must already carry resolved+integrity, or
# fetchNpmDeps cannot pre-fetch it in the sandbox. Upstream repairs this in CI
# (scripts/fix-lockfile.mjs, committed by nix-update-hash.yml), so tags normally
# arrive complete. We cannot repair it ourselves inside the build: fix-lockfile
# resolves the missing fields via `npm view`, which needs network. This mirrors
# that script's own skip predicate.
INCOMPLETE=$(jq '
  (.packages // {}) as $p
  | [ $p | to_entries[] | select(.value.link == true) | (.value.resolved // .key) ] as $roots
  | [ $p
      | to_entries[]
      | select(.key != "")
      | select(.key | startswith("node_modules/") | not)
      | select(.value.link != true)
      | select((.value.resolved and .value.integrity) | not)
      | select(.value.version != null)
      | select(.key as $k | $roots | index($k) | not)
    ]
  | length
' "${SRC_PATH}/package-lock.json")
if [[ "$INCOMPLETE" -gt 0 ]]; then
  cat >&2 <<MSG
Error: ${TAG} ships a package-lock.json with ${INCOMPLETE} incomplete entries
(missing resolved/integrity). fetchNpmDeps cannot pre-fetch those offline, and
the repair needs network, so it cannot run in the build sandbox.

To fix: run upstream's scripts/fix-lockfile.mjs against the tag, commit the
result as packages/paseo/package-lock.json, and add to default.nix:
  postPatch = "cp \${./package-lock.json} package-lock.json";
MSG
  exit 1
fi

# npm dependency hash, computed against OUR pinned nixpkgs. fetchNpmDeps's hash
# is a function of nixpkgs' prefetch-npm-deps, so upstream's recorded hash (and
# any hash from a different nixpkgs) will not match. --inputs-from resolves
# nixpkgs from this repo's flake.lock.
echo "Prefetching npm dependencies (this takes a few minutes)..."
NPM_DEPS_HASH=$(nix shell --inputs-from "$ROOT_DIR" nixpkgs#prefetch-npm-deps \
  -c prefetch-npm-deps "${SRC_PATH}/package-lock.json")
if [[ -z "$NPM_DEPS_HASH" ]]; then
  echo "Error: prefetch-npm-deps produced no hash" >&2
  exit 1
fi

# Single write, only once every step above succeeded: a partially published
# release leaves hashes.json untouched rather than half-bumped.
jq -n \
  --arg version "$VERSION" \
  --arg tag "$TAG" \
  --arg src_hash "$SRC_HASH" \
  --arg npm_deps_hash "$NPM_DEPS_HASH" \
  --arg desktop_artifact "$DESKTOP_ARTIFACT" \
  --arg desktop_hash "$DESKTOP_HASH" \
  '{
    version: $version,
    tag: $tag,
    src: { hash: $src_hash },
    npmDepsHash: $npm_deps_hash,
    desktop: {
      "aarch64-darwin": { artifact: $desktop_artifact, hash: $desktop_hash }
    }
  }' \
  > "${SCRIPT_DIR}/hashes.json"

echo "Updated paseo to ${TAG}"
