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

- **repo-new** used to stop at Copier writing `.claude/agents/code-reviewer.md`, which the sandbox blocks. The reviewer is now a forked skill in `.claude/skills/code-reviewer/`, so the template writes nothing under `.claude/agents/` and the suite can run end to end; the 2026-11-14 score below predates that.
- **repo-adopt** works: the scaffold makes the fixture's git repo outside the sandbox.
- **repo-github-setup** works. Its scaffold renders the repo outside the sandbox for the fictional owner `acme-labs`, and the bootstrap's `--dry-run` needs no GitHub login. It scores 1.00 with and without the plugin, because the generated repo's own `docs/SETUP.md` and bootstrap script lead the agent there either way. A case where the repo doesn't spell it out (an existing repo, or the drift audit) would show what the skill adds.

## In CI

The **Skill evals** workflow (`.github/workflows/skill-evals.yml`) runs one suite or all of them on demand (Actions → Skill evals → Run workflow). It needs a `CLAUDE_CODE_OAUTH_TOKEN` secret on this repo (`claude setup-token`, then `gh secret set CLAUDE_CODE_OAUTH_TOKEN`) and skips with a warning without one. It reports scores without gating and uploads each suite's HTML report as an artifact. On GitHub's Ubuntu 24.04 runners the job first lifts two AppArmor user-namespace restrictions (the `kernel.apparmor_restrict_unprivileged_userns` sysctl and the `bwrap-userns-restrict` profile), without which every Bash call in the sandbox fails with `nested userns is capability-restricted`; a preflight stops the job before any paid run if that still fails. Its first full run (2026-11-15) hit exactly that, so its scores measured nothing. A full run is about $12; `max-cost-usd` caps each suite.

## Last full run (2026-11-14, 3 runs per arm)

| Suite | With plugin | Without | Cost |
|---|---|---|---|
| repo-adopt | 0.92 | 0.42 | $5.04 |
| repo-github-setup | 1.00 | 1.00 | $1.98 |
| repo-new | 0.43 (sandbox-limited, see above) | 0.48 | $5.22 |
