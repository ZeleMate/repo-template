---
description: Diagnostic, not a skill test. Shows what the eval sandbox allows (git, network, .claude/ writes).
max_turns: 5
timeout_seconds: 300
allowed_tools: [Bash]
---

Run exactly this one Bash command and then reply with its full output, nothing else:

echo "PATH=$PATH"; which -a git; git --version; git ls-remote --tags https://github.com/ZeleMate/repo-template 2>&1 | tail -2; for d in .claude .claude/agents .claude/rules .claude/hooks .claude/skills/x x/.claude/agents; do mkdir -p "out/$d" 2>&1 && echo hi > "out/$d/f.md" 2>&1 && echo "write ok: $d" || echo "write FAIL: $d"; done; echo '{}' > out/.claude/settings.json 2>&1 && echo "write ok: settings.json" || echo "write FAIL: settings.json"
