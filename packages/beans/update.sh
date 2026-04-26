#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_FILE="$SCRIPT_DIR/data.json"

OWNER="hmans"
REPO="beans"

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
  nix-build --no-out-link -E "
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
PNPM_DEPS_HASH=$(
  nix-build --no-out-link -E "
    with import <nixpkgs> {};
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
      fetcherVersion = 3;
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
