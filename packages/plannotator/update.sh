#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="backnotprop/plannotator"

declare -A PLATFORM_MAP=(
  ["aarch64-darwin"]="darwin-arm64"
  ["x86_64-darwin"]="darwin-x64"
  ["aarch64-linux"]="linux-arm64"
  ["x86_64-linux"]="linux-x64"
)

# Resolve version
if [[ $# -ge 1 ]]; then
  VERSION="$1"
else
  VERSION=$(curl -sf "https://api.github.com/repos/${REPO}/releases/latest" \
    | jq -r '.tag_name | ltrimstr("v")')
  echo "Latest version: ${VERSION}"
fi

# Validate the tag exists as a GitHub release
if ! curl -sfI "https://github.com/${REPO}/releases/tag/v${VERSION}" >/dev/null; then
  echo "Error: Release v${VERSION} not found at github.com/${REPO}" >&2
  exit 1
fi

# Fetch hashes
echo "Fetching hashes for v${VERSION}..."
declare -A HASHES
for nix_platform in "${!PLATFORM_MAP[@]}"; do
  release_platform="${PLATFORM_MAP[$nix_platform]}"
  url="https://github.com/${REPO}/releases/download/v${VERSION}/plannotator-${release_platform}"
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

echo "Updated plannotator to v${VERSION}"
