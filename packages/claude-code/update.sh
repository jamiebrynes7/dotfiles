#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GCS_BASE="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"

declare -A PLATFORM_MAP=(
  ["aarch64-darwin"]="darwin-arm64"
  ["x86_64-darwin"]="darwin-x64"
  ["aarch64-linux"]="linux-arm64"
  ["x86_64-linux"]="linux-x64"
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

# Resolve version
if [[ -z "$VERSION" ]]; then
  VERSION=$(curl -fsSL "${GCS_BASE}/latest" | tr -d '\r\n')
  echo "Latest version: ${VERSION}"
fi

# Skip all hash work when the recorded version already matches (unless --force).
CURRENT_VERSION=$(jq -r '.version // empty' "${SCRIPT_DIR}/hashes.json" 2>/dev/null || true)
if [[ "$FORCE" -ne 1 && -n "$CURRENT_VERSION" && "$CURRENT_VERSION" == "$VERSION" ]]; then
  echo "claude-code already at ${VERSION}, skipping"
  exit 0
fi

# The release manifest carries a hex checksum per platform, so no download is
# needed — convert them to SRI rather than prefetching each binary.
echo "Fetching manifest for ${VERSION}..."
MANIFEST=$(curl -fsSL "${GCS_BASE}/${VERSION}/manifest.json")

declare -A HASHES
for nix_platform in "${!PLATFORM_MAP[@]}"; do
  release_platform="${PLATFORM_MAP[$nix_platform]}"
  echo "  ${nix_platform}..."
  checksum=$(jq -r --arg p "$release_platform" '.platforms[$p].checksum // empty' <<<"$MANIFEST")
  if [[ -z "$checksum" ]]; then
    echo "Error: No checksum for ${release_platform} in manifest" >&2
    exit 1
  fi
  HASHES[$nix_platform]=$(nix hash convert --hash-algo sha256 --to sri "$checksum")
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

echo "Updated claude-code to ${VERSION}"
