#!/usr/bin/env bash
# Report every pinned third-party version in the template, with the latest upstream release next to it.
#   list-pins.sh [template-root]
# Read-only. Needs gh (authenticated, for the release lookups), curl, jq, uv.
set -uo pipefail

ROOT="$(cd "${1:-.}" && pwd)"
cd "$ROOT" || exit 2
[[ -f copier.yml ]] || { echo "$ROOT has no copier.yml; pass the template root"; exit 2; }

latest() { gh api "repos/$1/releases/latest" --jq .tag_name 2>/dev/null || gh api "repos/$1/tags" --jq '.[0].name' 2>/dev/null || echo "?"; }
row() { # kind, name, current, latest, where
  local flag=""; [[ "${3#v}" != "${4#v}" ]] && [[ "$4" != "?" ]] && [[ "$4" != "-" ]] && flag="  <- update"
  printf '%-8s %-44s %-12s %-12s %s%s\n' "$1" "$2" "$3" "$4" "$5" "$flag"
}
printf '%-8s %-44s %-12s %-12s %s\n' KIND NAME CURRENT LATEST "FILES"

echo "# GitHub Actions (uses: owner/repo@sha  # version)"
grep -rhoE 'uses: [A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40} +# *v?[0-9][^ ]*' template .github 2>/dev/null \
  | sed -E 's/uses: ([^@]+)@[0-9a-f]+ +# *(.*)/\1 \2/' | sort -u \
  | while read -r action ver; do
      repo=$(cut -d/ -f1-2 <<<"$action")
      files=$(grep -rlF "uses: $action@" template .github 2>/dev/null | wc -l | tr -d ' ')
      row action "$action" "$ver" "$(latest "$repo")" "$files file(s)"
    done

echo "# pre-commit hooks (rev: sha  # frozen: version)"
for f in .pre-commit-config.yaml template/.pre-commit-config.yaml.jinja; do
  [[ -f "$f" ]] || continue
  awk '/repo: https:\/\/github.com\//{r=$3} /rev: [0-9a-f]{40} +# frozen:/{print r, $NF}' "$f" \
    | while read -r url ver; do
        repo=${url#https://github.com/}
        row hook "$repo" "$ver" "$(latest "$repo")" "$f"
      done
done

echo "# checksum-verified binaries (VERSION + SHA256 env pairs)"
grep -rhoE '(OSV|GITLEAKS)_VERSION: "[^"]+"' template | sort -u | while read -r line; do
  name=$(cut -d_ -f1 <<<"$line"); ver=$(sed -E 's/.*"([^"]+)"/\1/' <<<"$line")
  case $name in OSV) repo=google/osv-scanner ;; GITLEAKS) repo=gitleaks/gitleaks ;; esac
  row binary "$repo" "v$ver" "$(latest "$repo")" "security.yml (update the SHA256 too)"
done

echo "# tools run by version (uvx tool@version from PyPI, pnpm dlx/npx tool@version from npm)"
grep -rhoE '(uvx|pnpm dlx|npx) [a-z0-9_-]+@[0-9][0-9.]*' template scripts .github 2>/dev/null | sed 's/pnpm dlx/pnpm-dlx/' | sort -u \
  | while read -r runner tool; do
      name=${tool%@*}; ver=${tool#*@}
      if [[ "$runner" = uvx ]]; then new=$(curl -fsS "https://pypi.org/pypi/$name/json" 2>/dev/null | jq -r '.info.version // "?"')
      else new=$(curl -fsS "https://registry.npmjs.org/$name/latest" 2>/dev/null | jq -r '.version // "?"'); fi
      row tool "$name ($runner)" "$ver" "${new:-?}" "$(grep -rlF "$tool" template scripts .github 2>/dev/null | wc -l | tr -d ' ') file(s)"
    done

echo "# toolchain defaults in copier.yml"
uvx --no-build --quiet --from pyyaml python -c '
import yaml
c = yaml.safe_load(open("copier.yml"))
for k in ("python_version", "node_version", "rust_toolchain", "rust_msrv"):
    print(k, c[k]["default"])' | while read -r key val; do row default "$key" "$val" "-" "copier.yml (check upstream support windows)"; done
