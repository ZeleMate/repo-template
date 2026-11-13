#!/usr/bin/env bash
# Run a skill's eval suite with the grants its cases need.
#   ./scripts/run-evals.sh <skill> [extra `claude plugin eval` flags, e.g. --runs 1]
# Suites live in evals/<skill>/: the CLI refuses an eval dir inside skills/.
#
# The cases run Copier against gh:ZeleMate/repo-template, so each run's sandbox needs
# GitHub, PyPI and npm. On macOS it also needs a git that isn't Apple's /usr/bin/git shim,
# which can't write its xcrun cache inside the sandbox (`brew install git`).
# repo-github-setup's scaffold calls `gh api user`, so GH_TOKEN is passed from gh's login.
set -euo pipefail

skill=${1:?usage: run-evals.sh <skill> [flags]}; shift
root="$(cd "$(dirname "$0")/.." && pwd)"
[[ -d "$root/evals/$skill" ]] || { echo "no suite at evals/$skill" >&2; exit 1; }

grants=(Bash Write Edit)
for d in github.com api.github.com codeload.github.com objects.githubusercontent.com \
         release-assets.githubusercontent.com raw.githubusercontent.com \
         pypi.org files.pythonhosted.org registry.npmjs.org; do
  grants+=("WebFetch(domain:$d)")
done

cd "$root"
GH_TOKEN=${GH_TOKEN:-$(gh auth token)} exec claude plugin eval . --eval-dir "evals/$skill" \
  --trust-plugin --scaffold --allow-tools "${grants[@]}" "$@"
