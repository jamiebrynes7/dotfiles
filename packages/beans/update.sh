#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_FILE="$SCRIPT_DIR/data.json"
FLAKE_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"

OWNER="hmans"
REPO="beans"

# Parse args: --force recomputes hashes even when the recorded version already
# matches the latest main commit.
FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f | --force)
      FORCE=1
      shift
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

echo "Fetching latest commit from $OWNER/$REPO..."
COMMIT_INFO=$(curl -sf "https://api.github.com/repos/$OWNER/$REPO/commits/main")
REV=$(echo "$COMMIT_INFO" | jq -r '.sha')
DATE=$(echo "$COMMIT_INFO" | jq -r '.commit.committer.date' | cut -d'T' -f1)
SHORT_SHA=$(echo "$REV" | head -c 7)
VERSION="unstable-${DATE}-${SHORT_SHA}"

echo "Latest commit: $REV ($DATE)"
echo "Version: $VERSION"

# Skip all hash work when the recorded version already matches (unless --force).
# The version embeds the commit SHA, so this equality also means "main has not
# moved since the last update".
CURRENT_VERSION=$(jq -r '.version // empty' "$DATA_FILE" 2>/dev/null || true)
if [[ "$FORCE" -ne 1 && -n "$CURRENT_VERSION" && "$CURRENT_VERSION" == "$VERSION" ]]; then
  echo "beans already at ${VERSION}, skipping"
  exit 0
fi

# Evaluate against the flake's pinned nixpkgs so the hashes we write match
# what `nix flake check` will recompute. `<nixpkgs>` from NIX_PATH can resolve
# to a different channel and a different `pnpm`, producing a stale
# `pnpmDepsHash`.
echo "Resolving flake nixpkgs..."
NIXPKGS=$(nix eval --raw --impure --expr "(builtins.getFlake \"$FLAKE_ROOT\").inputs.nixpkgs.outPath")

echo "Prefetching source..."
HASH=$(nix-prefetch-url --unpack "https://github.com/$OWNER/$REPO/archive/$REV.tar.gz" 2>/dev/null)
SRI_HASH=$(nix hash to-sri --type sha256 "$HASH")

echo "Source hash: $SRI_HASH"

echo "Computing vendor hash..."
VENDOR_HASH=$(
  nix-build --no-out-link -I "nixpkgs=$NIXPKGS" -E "
    with import <nixpkgs> {};
    buildGoModule {
      pname = \"beans\";
      version = \"$VERSION\";
      src = fetchFromGitHub {
        owner = \"$OWNER\";
        repo = \"$REPO\";
        rev = \"$REV\";
        hash = \"$SRI_HASH\";
      };
      vendorHash = \"\";
    }
  " 2>&1 | grep -oP 'got:\s+\K\S+' || true
)

if [[ -z "$VENDOR_HASH" ]]; then
  echo "failed to compute vendor hash" >&2
  exit 1
fi

echo "Vendor hash: $VENDOR_HASH"

echo "Computing pnpm deps hash..."
# Must mirror packages/beans/default.nix: a pnpm_11 patched to 11.5.2 with
# trackUnmanagedFds disabled (works around the aarch64-darwin fetch SIGKILL,
# nixpkgs#525627), wired through the top-level fetchPnpmDeps with that pnpm
# passed explicitly (pnpm.fetchDeps ignores overrideAttrs), fetcherVersion 4.
# Keep this in sync with default.nix or the hash will be stale.
PNPM_DEPS_HASH=$(
  nix-build --no-out-link -I "nixpkgs=$NIXPKGS" -E "
    with import <nixpkgs> {};
    let
      pnpm = pnpm_11.overrideAttrs (_: {
        version = \"11.5.2\";
        src = fetchurl {
          url = \"https://registry.npmjs.org/pnpm/-/pnpm-11.5.2.tgz\";
          hash = \"sha256-dJ3FT709zenkFLquMsF3yoR3DT/NaciBbVea3D5qLJk=\";
        };
        postPatch = ''
          substituteInPlace dist/pnpm.mjs \
            --replace-fail \
              'resourceLimits: this._workerResourceLimits' \
              'resourceLimits: this._workerResourceLimits, trackUnmanagedFds: false'
        '';
      });
    in
    fetchPnpmDeps {
      pname = \"beans-frontend\";
      version = \"$VERSION\";
      src = \"\${fetchFromGitHub {
        owner = \"$OWNER\";
        repo = \"$REPO\";
        rev = \"$REV\";
        hash = \"$SRI_HASH\";
      }}/frontend\";
      hash = \"\";
      fetcherVersion = 4;
      inherit pnpm;
    }
  " 2>&1 | grep -oP 'got:\s+\K\S+' || true
)

if [[ -z "$PNPM_DEPS_HASH" ]]; then
  echo "failed to compute pnpm deps hash" >&2
  exit 1
fi

echo "pnpm deps hash: $PNPM_DEPS_HASH"

echo "Writing $DATA_FILE..."
jq -n \
  --arg rev "$REV" \
  --arg hash "$SRI_HASH" \
  --arg vendorHash "$VENDOR_HASH" \
  --arg pnpmDepsHash "$PNPM_DEPS_HASH" \
  --arg version "$VERSION" \
  '{rev: $rev, hash: $hash, vendorHash: $vendorHash, pnpmDepsHash: $pnpmDepsHash, version: $version}' > "$DATA_FILE"

echo "Done! Updated to $VERSION"
