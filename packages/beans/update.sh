#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_FILE="$SCRIPT_DIR/data.json"
FLAKE_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"

OWNER="hmans"
REPO="beans"

# Evaluate against the flake's pinned nixpkgs so the hashes we write match
# what `nix flake check` will recompute. `<nixpkgs>` from NIX_PATH can resolve
# to a different channel and a different `pnpm`, producing a stale
# `pnpmDepsHash`.
echo "Resolving flake nixpkgs..."
NIXPKGS=$(nix eval --raw --impure --expr "(builtins.getFlake \"$FLAKE_ROOT\").inputs.nixpkgs.outPath")

echo "Fetching latest commit from $OWNER/$REPO..."
COMMIT_INFO=$(curl -sf "https://api.github.com/repos/$OWNER/$REPO/commits/main")
REV=$(echo "$COMMIT_INFO" | jq -r '.sha')
DATE=$(echo "$COMMIT_INFO" | jq -r '.commit.committer.date' | cut -d'T' -f1)
SHORT_SHA=$(echo "$REV" | head -c 7)
VERSION="unstable-${DATE}-${SHORT_SHA}"

echo "Latest commit: $REV ($DATE)"
echo "Version: $VERSION"

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
# Must mirror packages/beans/default.nix: pnpm_9 (the lockfile is pnpm 9) and
# the `packages: []` workspace patch (pnpm 9 rejects the upstream
# pnpm-workspace.yaml otherwise). Keep these in sync or the hash will be stale.
PNPM_DEPS_HASH=$(
  nix-build --no-out-link -I "nixpkgs=$NIXPKGS" -E "
    with import <nixpkgs> {};
    pnpm_9.fetchDeps {
      pname = \"beans-frontend\";
      version = \"$VERSION\";
      src = \"\${fetchFromGitHub {
        owner = \"$OWNER\";
        repo = \"$REPO\";
        rev = \"$REV\";
        hash = \"$SRI_HASH\";
      }}/frontend\";
      hash = \"\";
      fetcherVersion = 3;
      postPatch = \"echo 'packages: []' >> pnpm-workspace.yaml\";
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
