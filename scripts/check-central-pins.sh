#!/usr/bin/env bash
# Check that every call to the central workflow repo in the template pins one SHA and one tag comment.
#   check-central-pins.sh          # exit 1 if the pins disagree or are malformed
#   check-central-pins.sh --sha    # print the pinned SHA
#   check-central-pins.sh --tag    # print the pinned tag
set -euo pipefail
cd "$(dirname "$0")/.."

lines=$(grep -rhoE 'uses: ZeleMate/workflows/\.github/workflows/[a-z-]+\.yml@.*' template/.github/workflows || true)
[[ -n "$lines" ]] || { echo "no central workflow calls found under template/.github/workflows" >&2; exit 1; }

bad=$(grep -vE '@[0-9a-f]{40}  # v[0-9]+\.[0-9]+\.[0-9]+$' <<<"$lines" || true)
if [[ -n "$bad" ]]; then
  echo "central pins must be '@<40-char sha>  # vX.Y.Z':" >&2; echo "$bad" >&2; exit 1
fi
pins=$(sed -E 's/.*@([0-9a-f]{40})  # (v[0-9.]+)$/\1 \2/' <<<"$lines" | sort -u)
if [[ "$(wc -l <<<"$pins")" -ne 1 ]]; then
  echo "central pins disagree:" >&2; echo "$pins" >&2; exit 1
fi
case "${1:-}" in
  --sha) cut -d' ' -f1 <<<"$pins" ;;
  --tag) cut -d' ' -f2 <<<"$pins" ;;
  *) echo "central pins agree: $pins ($(wc -l <<<"$lines" | tr -d ' ') calls)" ;;
esac
