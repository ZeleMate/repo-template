#!/usr/bin/env bash
# Generates ./invoice-agent from the template (needs network and uv).
set -eu
cat > /tmp/repo-standards-eval-answers.yml <<'YML'
project_name: Invoice Agent
author_name: Ada Lovelace
author_email: ada@example.com
github_owner: acme-labs-eval
languages: [python]
visibility: private
agentic: true
ai_reviewers: [claude]
YML
uvx copier copy --trust --defaults --quiet --data-file /tmp/repo-standards-eval-answers.yml gh:ZeleMate/repo-template invoice-agent
