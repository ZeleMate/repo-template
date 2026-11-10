#!/usr/bin/env bash
# Move every central workflow pin in the template to a central release tag.
#   bump-central-pin.sh v1.2.0
# Dependabot can't read .jinja files, so this does what it does in generated repos:
# resolves the tag to its commit SHA and rewrites each `uses:` line and its comment.
# Never moves backwards: pass --force to pin an older tag.
set -euo pipefail
cd "$(dirname "$0")/.."

tag="${1:-}"; force="${2:-}"
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: bump-central-pin.sh vX.Y.Z [--force]" >&2; exit 2; }
repo=https://github.com/ZeleMate/workflows.git

# An annotated tag lists the commit as <tag>^{}; a lightweight tag lists it directly.
refs=$(git ls-remote "$repo" "refs/tags/$tag" "refs/tags/$tag^{}")
sha=$(awk '$2 ~ /\^\{\}$/ {print $1}' <<<"$refs")
[[ -n "$sha" ]] || sha=$(awk '{print $1}' <<<"$refs" | head -1)
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "tag $tag not found in $repo" >&2; exit 1; }

current=$(./scripts/check-central-pins.sh --tag)
newest=$(printf '%s\n%s\n' "$current" "$tag" | sort -V | tail -1)
if [[ "$newest" != "$tag" && "$force" != "--force" ]]; then
  echo "refusing to move the pin back from $current to $tag (pass --force)" >&2; exit 1
fi

files=$(grep -rlE 'uses: ZeleMate/workflows/\.github/workflows/' template/.github/workflows)
while IFS= read -r f; do
  sed -E -i.bak "s|(uses: ZeleMate/workflows/\.github/workflows/[a-z-]+\.yml)@[0-9a-f]{40}  # v[0-9.]+$|\1@$sha  # $tag|" "$f"
  rm -f "$f.bak"
done <<<"$files"
./scripts/check-central-pins.sh
