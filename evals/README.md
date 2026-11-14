# Skill evals

One suite per skill, in `evals/<skill>/<case>/`, run with `claude plugin eval`. The CLI refuses an eval directory inside `skills/`, which is why they live here.

```bash
./scripts/run-evals.sh repo-adopt                  # 3 runs per case, with and without the plugin
./scripts/run-evals.sh repo-adopt --runs 1 --ablation none   # one quick run
```

`run-evals.sh` grants Bash, Write and Edit, plus network to GitHub, PyPI and npm, which the cases need for Copier and uv.

## What the eval sandbox allows

Each run's Bash commands run in Claude Code's OS sandbox, and a case can't change its rules. `sandbox-probe/` prints them. Run it with `./scripts/run-evals.sh sandbox-probe --runs 1 --ablation none` after a Claude Code or OS update. On macOS (Claude Code 2.1.302):

| | |
|---|---|
| `git` | Only Apple's `/usr/bin/git` stub is visible, and it fails because it can't write its xcrun cache. Homebrew git on `PATH` isn't found. So a skill that needs git inside the run fails |
| Writes under any `.claude/agents/` | Blocked at every depth. Other `.claude/` paths, including `settings.json`, `rules/`, `hooks/` and `skills/`, are allowed |
| Network | Only the domains `run-evals.sh` grants |
| Scaffold scripts | Run as you, **outside** the sandbox: git, uv and network work, but no shell variables reach them (no `GH_TOKEN`), so they can't call an authenticated `gh` |

## Known limits per suite

- **repo-new** can't pass end to end. Copier has to write the template's `.claude/agents/code-reviewer.md`, and the sandbox blocks that, so Copier aborts and removes the output. A score around 0.43 means the skill stopped correctly at that point; it doesn't measure generation. Track it, but don't gate on it.
- **repo-adopt** works: the scaffold makes the fixture's git repo outside the sandbox.
- **repo-github-setup** works. Its scaffold renders the repo outside the sandbox for the fictional owner `acme-labs`, and the bootstrap's `--dry-run` needs no GitHub login. It scores 1.00 with and without the plugin, because the generated repo's own `docs/SETUP.md` and bootstrap script lead the agent there either way. A case where the repo doesn't spell it out (an existing repo, or the drift audit) would show what the skill adds.

## Last full run (2026-11-14, 3 runs per arm)

| Suite | With plugin | Without | Cost |
|---|---|---|---|
| repo-adopt | 0.92 | 0.42 | $5.04 |
| repo-github-setup | 1.00 | 1.00 | $1.98 |
| repo-new | 0.43 (sandbox-limited, see above) | 0.48 | $5.22 |
