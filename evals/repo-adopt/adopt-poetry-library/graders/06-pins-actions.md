---
type: regex
target: { source: file, path: acme-utils/.github/workflows/ci-local.yml }
# At least one action pinned to a 40-character SHA, and no `uses:` of an action at anything else
# (local `./` calls are ignored). An LLM judge on the trace only saw the fixture's original
# `@v4` lines, not the ci-local.yml the agent wrote mid-session.
pattern: '^(?![\s\S]*uses:\s*["'']?[^.\s$''"][^\s@''"]*@(?![0-9a-f]{40}\b))[\s\S]*uses:\s*\S+@[0-9a-f]{40}\b'
weight: 1
---
