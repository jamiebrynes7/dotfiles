#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_URL="https://sprites-binaries.t3.storage.dev/client"

declare -A PLATFORM_MAP=(
  ["aarch64-darwin"]="darwin-arm64"
  ["x86_64-darwin"]="darwin-amd64"
  ["aarch64-linux"]="linux-arm64"
  ["x86_64-linux"]="linux-amd64"
)

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

# Resolve version. Sprite publishes a stable channel and an rc channel; prefer
# stable, but fall back to rc since there may be no stable release yet.
if [[ -z "$VERSION" ]]; then
  VERSION=$(curl -fsSL "${BASE_URL}/release.txt" 2>/dev/null | tr -d '\r\n' || true)
  if [[ -z "$VERSION" ]]; then
    echo "No release version found, trying rc channel..."
    VERSION=$(curl -fsSL "${BASE_URL}/rc.txt" 2>/dev/null | tr -d '\r\n' || true)
  fi
  if [[ -z "$VERSION" ]]; then
    echo "Error: Failed to fetch version from release or rc channels" >&2
    exit 1
  fi
  echo "Latest version: ${VERSION}"
fi

# Skip all hash work when the recorded version already matches (unless --force).
CURRENT_VERSION=$(jq -r '.version // empty' "${SCRIPT_DIR}/hashes.json" 2>/dev/null || true)
if [[ "$FORCE" -ne 1 && -n "$CURRENT_VERSION" && "$CURRENT_VERSION" == "$VERSION" ]]; then
  echo "sprite already at ${VERSION}, skipping"
  exit 0
fi

# Fetch hashes
echo "Fetching hashes for ${VERSION}..."
declare -A HASHES
for nix_platform in "${!PLATFORM_MAP[@]}"; do
  release_platform="${PLATFORM_MAP[$nix_platform]}"
  url="${BASE_URL}/${VERSION}/sprite-${release_platform}.tar.gz"
  echo "  ${nix_platform}..."
  hash=$(nix store prefetch-file --json "$url" 2>/dev/null | jq -r '.hash')
  if [[ -z "$hash" || "$hash" == "null" ]]; then
    echo "Error: Failed to fetch hash for ${nix_platform}" >&2
    exit 1
  fi
  HASHES[$nix_platform]="$hash"
done

# Write hashes.json (single source of truth for default.nix)
jq -n \
  --arg version "$VERSION" \
  --arg ad_platform "${PLATFORM_MAP[aarch64-darwin]}" \
  --arg ad_hash "${HASHES[aarch64-darwin]}" \
  --arg xd_platform "${PLATFORM_MAP[x86_64-darwin]}" \
  --arg xd_hash "${HASHES[x86_64-darwin]}" \
  --arg al_platform "${PLATFORM_MAP[aarch64-linux]}" \
  --arg al_hash "${HASHES[aarch64-linux]}" \
  --arg xl_platform "${PLATFORM_MAP[x86_64-linux]}" \
  --arg xl_hash "${HASHES[x86_64-linux]}" \
  '{
    version: $version,
    platforms: {
      "aarch64-darwin": { artifact: $ad_platform, hash: $ad_hash },
      "x86_64-darwin": { artifact: $xd_platform, hash: $xd_hash },
      "aarch64-linux": { artifact: $al_platform, hash: $al_hash },
      "x86_64-linux": { artifact: $xl_platform, hash: $xl_hash }
    }
  }' \
  > "${SCRIPT_DIR}/hashes.json"

echo "Updated sprite to ${VERSION}"
