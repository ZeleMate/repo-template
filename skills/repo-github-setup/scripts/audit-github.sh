#!/usr/bin/env bash
# Read-only audit: compare a generated repo's live GitHub settings and secrets with its requirements.
#   audit-github.sh [repo-dir] [owner/repo]
# The check lives in the repo, as `scripts/bootstrap-github.sh --check`, next to the code that applies
# the same requirements (the template's ADR 0005), so a repo is always checked against its own
# template version. This only finds it. owner/repo defaults to the repo bootstrap creates.
# Changes nothing. Exits 1 if anything has drifted, 0 if not, 2 if the repo can't be audited.
# Needs: gh (authenticated), jq.
set -uo pipefail

REPO_DIR="$(cd "${1:-.}" && pwd)" || exit 2
[[ -f "$REPO_DIR/.copier-answers.yml" ]] || { echo "No .copier-answers.yml in $REPO_DIR"; exit 2; }
if [[ ! -f "$REPO_DIR/.github/settings-requirements.json" || ! -f "$REPO_DIR/scripts/bootstrap-github.sh" ]]; then
  echo "$REPO_DIR has no .github/settings-requirements.json or scripts/bootstrap-github.sh:"
  echo "it was rendered by a template older than the one that checks settings in the repo."
  echo "Run copier update (the repo-template-update skill), then audit again."
  exit 2
fi
exec bash "$REPO_DIR/scripts/bootstrap-github.sh" --check ${2:+"$2"}
