# Shared tools for AI assistant file management.
{ pkgs }:
{
  # Variant-aware frontmatter filtering for markdown files.
  # Usage in a derivation: "${processFrontmatter}/bin/process-frontmatter <variant> <input-file>"
  processFrontmatter = pkgs.callPackage ./process-frontmatter { };
}
