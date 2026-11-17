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
| Network | Only the domains `run-evals.sh` grants: GitHub, PyPI, npm, the tiktoken file a generated repo's mock evals fetch (`openaipublic.blob.core.windows.net`) and Semgrep's rules (`semgrep.dev`) |
| Scaffold scripts | Run as you, **outside** the sandbox: git, uv and network work, but no shell variables reach them (no `GH_TOKEN`), so they can't call an authenticated `gh` |

## Known limits per suite

- **repo-new** used to stop at Copier writing `.claude/agents/code-reviewer.md`, which the sandbox blocks. The reviewer is now a forked skill in `.claude/skills/code-reviewer/`, so the template writes nothing under `.claude/agents/`, and the suite passes end to end: 0.95 with the plugin vs 0.48 without. Its agentic-files and mock-evals graders are free `file_exists` and `regex` checks, because an LLM judge on the trace sees only the first and last 12 messages and missed results reported in the middle.
- **repo-adopt** works: the scaffold makes the fixture's git repo outside the sandbox.
- **repo-github-setup** works. Its scaffold renders the repo outside the sandbox for the fictional owner `acme-labs`, and the bootstrap's `--dry-run` needs no GitHub login. It scores 1.00 with and without the plugin, because the generated repo's own `docs/SETUP.md` and bootstrap script lead the agent there either way. A case where the repo doesn't spell it out (an existing repo, or the drift audit) would show what the skill adds.

## In CI

The **Skill evals** workflow (`.github/workflows/skill-evals.yml`) runs one suite or all of them on demand (Actions → Skill evals → Run workflow). It needs a `CLAUDE_CODE_OAUTH_TOKEN` secret on this repo (`claude setup-token`, then `gh secret set CLAUDE_CODE_OAUTH_TOKEN`) and skips with a warning without one. That token draws on the same weekly Claude allowance as your own sessions: a full run can use it up, and runs started after that fail at once with "You've hit your weekly limit". It reports scores without gating and uploads each suite's HTML report as an artifact. On GitHub's Ubuntu 24.04 runners the job first lifts two AppArmor user-namespace restrictions (the `kernel.apparmor_restrict_unprivileged_userns` sysctl and the `bwrap-userns-restrict` profile), without which every Bash call in the sandbox fails with `nested userns is capability-restricted`; a preflight stops the job before any paid run if that still fails. Its first full run (2026-11-15) hit exactly that, so its scores measured nothing. A full run is about $12; `max-cost-usd` caps each suite.

## Last full run (CI, 2026-11-15, 3 runs per arm, 28 minutes)

| Suite | With plugin | Without | Cost |
|---|---|---|---|
| repo-adopt | 0.88 | 0.33 | $1.12 |
| repo-github-setup | 0.94 | 1.00 | $0.85 |
| repo-new (rerun 2026-11-17, 7 minutes) | 0.95 | 0.48 | $1.10 |

repo-adopt's misses with the plugin: action pinning (2 of 3 runs) and one README judgement. repo-github-setup missed the dry-run-first step once. repo-new's first attempt hit the weekly limit after one run (1.00). Its first full run scored 0.86 / 0.48: the sandbox blocked the tiktoken download, so the generated repo's mock evals errored in every run. With that host granted it scored 0.95 / 0.38, missing the agentic files once with the plugin only because the reply didn't name them. After those graders moved to file and regex checks, the only miss with the plugin was one 2–1 judge split on `04-verified-locally`. Without the plugin it misses the answers file and the agentic files every time. The previous local run (2026-11-14) scored repo-adopt 0.92 / 0.42 and repo-github-setup 1.00 / 1.00; repo-new was sandbox-limited then.
