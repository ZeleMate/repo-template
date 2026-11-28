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

- **repo-new** used to stop at Copier writing `.claude/agents/code-reviewer.md`, which the sandbox blocks. The reviewer is now a forked skill in `.claude/skills/code-reviewer/`, so the template writes nothing under `.claude/agents/`, and the suite passes end to end: 1.00 with the plugin vs 0.43 without. Its agentic-files and mock-evals graders are free `file_exists` and `regex` checks, because an LLM judge on the trace sees only the first and last 12 messages and missed results reported in the middle.
- **repo-adopt** works: the scaffold makes the fixture's git repo outside the sandbox. It scores 1.00 with the plugin vs 0.38 without. Its action-pinning grader is a `regex` over the `ci-local.yml` the agent writes: a trace judge saw the fixture's original `@v4` lines but never the pinned file.
- **repo-github-setup** works. Its scaffold renders the repo outside the sandbox for the fictional owner `acme-labs`, and the bootstrap's `--dry-run` needs no GitHub login. It scores 0.89 both with and without the plugin, because the generated repo's own `docs/SETUP.md` and bootstrap script lead the agent there either way. With the plugin it sometimes checks `gh auth status` first, finds no login and stops to ask for one without running the dry run, although `--dry-run` skips the auth check. The skill now says the dry run needs no login and asks for one only before the real run; that change hasn't been through an eval run yet. A case where the repo doesn't spell it out (an existing repo, or the drift audit) would show what the skill adds.

## In CI

The **Skill evals** workflow (`.github/workflows/skill-evals.yml`) runs one suite or all of them on demand (Actions → Skill evals → Run workflow). It needs a `CLAUDE_CODE_OAUTH_TOKEN` secret on this repo (`claude setup-token`, then `gh secret set CLAUDE_CODE_OAUTH_TOKEN`) and skips with a warning without one. That token draws on the same weekly Claude allowance as your own sessions: a full run can use it up, and runs started after that fail at once with "You've hit your weekly limit". It reports scores without gating and uploads each suite's HTML report as an artifact. On GitHub's Ubuntu 24.04 runners the job first lifts two AppArmor user-namespace restrictions (the `kernel.apparmor_restrict_unprivileged_userns` sysctl and the `bwrap-userns-restrict` profile), without which every Bash call in the sandbox fails with `nested userns is capability-restricted`; a preflight stops the job before any paid run if that still fails. Its first full run (2026-11-15) hit exactly that, so its scores measured nothing. A full run is about $12; `max-cost-usd` caps each suite.

## Latest runs (CI, 3 runs per arm)

| Suite | Date | With plugin | Without | Cost | Time |
|---|---|---|---|---|---|
| repo-adopt | 2026-11-28 | 1.00 | 0.38 | $1.17 | 7 min |
| repo-github-setup | 2026-11-28 | 0.89 | 0.89 | $0.94 | 4 min |
| repo-new | 2026-11-28 | 1.00 | 0.43 | $1.03 | 7 min |

These ran against v1.3.0 (Claude Code 2.1.302). repo-github-setup missed twice with the plugin: one run asked for `gh auth login` before the dry run, which the skill's preconditions list first, and one reply gave both `gh secret set` commands yet two of three judges failed `04-secret-instructions`. Without the plugin it missed the dry-run summary once and the secret handling once. The 2026-11-19 runs scored repo-adopt 1.00 / 0.38, repo-github-setup 1.00 / 0.94 and repo-new 1.00 / 0.48.

The first full CI run (2026-11-15) scored repo-adopt 0.88 / 0.33 and repo-github-setup 0.94 / 1.00. repo-adopt's misses were the action-pinning grader, which failed every run on 2026-11-19 too, although each run pinned the actions in `ci-local.yml`; those runs also rewrote `ci.yml`'s `uses: $/` call to `./`, believing it a template bug, until `repo-adopt` said `$/` is GitHub's self-repository syntax. repo-github-setup missed the dry-run-first step once. Without the plugin, repo-adopt never writes the answers file, moves the CI job, raises Poetry or stays on a branch. repo-new's first attempt hit the weekly limit after one run (1.00). Its first full run scored 0.86 / 0.48: the sandbox blocked the tiktoken download, so the generated repo's mock evals errored in every run. With that host granted it scored 0.95 / 0.38, missing the agentic files once with the plugin only because the reply didn't name them. After those graders moved to file and regex checks it scored 0.95 / 0.48; the one miss, on `04-verified-locally`, came from pyright reading the sandbox home's unreadable `pyrightconfig.json`. With verify running `pyright -p pyproject.toml` it scores 1.00 in every run. Without the plugin it misses the answers file and the agentic files every time. The previous local run (2026-11-14) scored repo-adopt 0.92 / 0.42 and repo-github-setup 1.00 / 1.00; repo-new was sandbox-limited then.
