#!/usr/bin/env python3
"""Process markdown frontmatter with variant-aware key filtering.

Filters frontmatter keys based on variant prefix:
- Unprefixed keys are kept for all variants
- 'cc:key' is only kept for 'cc' variant (prefix stripped)
- 'cursor:key' is only kept for 'cursor' variant (prefix stripped)
"""

import sys
from pathlib import Path

import yaml

KNOWN_VARIANTS = {"cc", "cursor"}


def parse_frontmatter(content: str) -> tuple[dict | None, str]:
    """Parse YAML frontmatter from markdown content.

    Returns (frontmatter_dict, body) or (None, content) if no frontmatter.
    """
    if not content.startswith("---"):
        return None, content

    # Find the closing ---
    end_idx = content.find("\n---", 3)
    if end_idx == -1:
        return None, content

    frontmatter_str = content[4:end_idx]  # Skip opening ---\n
    body = content[end_idx + 4 :]  # Skip \n---

    # Handle empty frontmatter
    if not frontmatter_str.strip():
        return {}, body

    try:
        frontmatter = yaml.safe_load(frontmatter_str)
        if frontmatter is None:
            frontmatter = {}
        return frontmatter, body
    except yaml.YAMLError:
        # If parsing fails, treat as no frontmatter
        return None, content


def filter_frontmatter(frontmatter: dict, variant: str) -> dict:
    """Filter frontmatter keys based on variant.

    - Unprefixed keys are kept
    - Keys with matching variant prefix have prefix stripped
    - Keys with non-matching variant prefix are removed
    """
    result = {}

    for key, value in frontmatter.items():
        # Check for variant prefix
        if ":" in key:
            prefix, rest = key.split(":", 1)
            if prefix in KNOWN_VARIANTS:
                # Only keep if prefix matches current variant
                if prefix == variant:
                    result[rest] = value
                # Otherwise skip this key
            else:
                # Unknown prefix - keep as-is
                result[key] = value
        else:
            # No prefix - keep for all variants
            result[key] = value

    return result


def serialize_frontmatter(frontmatter: dict) -> str:
    """Serialize frontmatter dict back to YAML string."""
    if not frontmatter:
        return "---\n---"

    yaml_str = yaml.dump(frontmatter, default_flow_style=False, allow_unicode=True)
    return f"---\n{yaml_str}---"


def process_file(content: str, variant: str) -> str:
    """Process markdown file with variant-aware frontmatter filtering."""
    frontmatter, body = parse_frontmatter(content)

    if frontmatter is None:
        return content

    filtered = filter_frontmatter(frontmatter, variant)
    return serialize_frontmatter(filtered) + body


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <variant> <input-file>", file=sys.stderr)
        sys.exit(1)

    variant = sys.argv[1]
    input_path = Path(sys.argv[2])

    if variant not in KNOWN_VARIANTS:
        print(f"Error: Unknown variant '{variant}'. Must be one of: {', '.join(KNOWN_VARIANTS)}", file=sys.stderr)
        sys.exit(1)

    content = input_path.read_text()
    result = process_file(content, variant)
    print(result, end="")


if __name__ == "__main__":
    main()
