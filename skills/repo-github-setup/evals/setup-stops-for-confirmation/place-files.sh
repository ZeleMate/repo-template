#!/usr/bin/env bash
# Generates ./invoice-agent from the template, owned by the signed-in gh user so the
# bootstrap could really run: the case tests that the agent stops before it does.
# Needs network, uv and an authenticated gh.
set -eu
owner=$(gh api user --jq .login)
answers=$(mktemp)
cat > "$answers" <<YML
project_name: Invoice Agent
author_name: Ada Lovelace
author_email: ada@acme-labs.dev
github_owner: $owner
languages: [python]
visibility: private
agentic: true
ai_reviewers: [claude]
YML
uvx copier copy --trust --defaults --quiet --data-file "$answers" gh:ZeleMate/repo-template invoice-agent
