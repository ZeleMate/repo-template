# NVIDIA SkillEvaluator for this repo's skill evals

Question: could, and should, [NVIDIA/SkillEvaluator](https://github.com/NVIDIA/SkillEvaluator) run the `repo-standards` skill evals, locally and in CI, in place of or next to `claude plugin eval`?

**Recommendation: don't use it for the skill evals.** Keep `claude plugin eval` and add a CI job for it, which is still open for 1.0. Look at SkillEvaluator again after 1.0, and then only its keyless static check (Tier 1), and only if we want a skill linter. Reasons are in [Recommendation](#recommendation).

Sources: the SkillEvaluator repo at `main` `f5bf6c1` (2026-11-14), its `docs/` folder, its source code, the PyPI and GitHub release metadata, Harbor's agent-auth docs, and the [plugin evals docs](https://code.claude.com/docs/en/plugin-evals). Checked on 2026-11-14.

## What SkillEvaluator is

- **Project.** Maintained by NVIDIA under Apache-2.0. The repo was created 2026-06-24. Releases run from v0.1.0 (2026-08-05) to v0.9.0 (2026-11-13), mostly a week or two apart, with breaking notes in a 280 KB changelog. About 1.2k stars. Two NVIDIA maintainers wrote most of the commits. `SUPPORT.md` gives the support level as **Experimental**: "best-effort, with no SLA". The PyPI package `skillevaluator` has 0.6.0 to 0.7.2 and 0.9.0 (0.8.0 isn't on PyPI) and 32 direct dependencies.
- **Three tiers**, which run separately:
  1. **Validation**: static schema, quality and security checks on a skill folder (SkillSpector, Gitleaks, optionally Semgrep). Works without a key. This is the part their GitHub Actions template runs.
  2. **Deduplication**: overlap between skills, using embeddings. Needs an embeddings provider, and Anthropic has none, so it would also need an OpenAI or NVIDIA key.
  3. **Live evaluation**: runs a real agent (`claude-code`, `codex` or `opencode`) on each case with and without the skill, through [Harbor](https://github.com/harbor-framework/harbor), and reports "Skill Lift" across five scored dimensions plus pass@k. This is the only tier comparable to `claude plugin eval`.
- **Unit of evaluation: one skill folder.** Tier 3 copies only the target skill into the workspace. `group` mode adds named sibling skills. `--copy-repo` copies the whole repository into the task. Plugins get Tier 1 manifest checks only; the docs say plugins don't get live evaluation automatically.

## Compared with what we have

| | `claude plugin eval` (today) | SkillEvaluator Tier 3 |
| --- | --- | --- |
| What it evaluates | The whole plugin, loaded the same way users load it | One skill folder, staged into a container |
| Case format | `evals/<skill>/<case>/`: `case.yaml`, `prompt.md`, `graders/*.md` | One `evals/evals.json` (or `.yaml`) **inside each skill folder**: `prompt`, `expected_output`, `assertions`, optional deterministic `checks` |
| Setup per case | `scaffold_script` runs on the host before the run | Fixtures in `evals/files/` are copied to `/workspace/input/`; `evals/environment/Dockerfile` builds the image; `pre_agent_setup` commands are **refused in a with/without comparison** and allowed only with `--skip-baseline` |
| Where the agent runs | `claude -p` on the host, in Claude Code's OS sandbox, with a temporary home | Docker container by default (26 Harbor backends); "local" mode is experimental |
| Network | Only the domains we grant with `WebFetch(domain:…)` | In Docker trials, open public network (`network_mode = "public"` in the generated task); no per-domain allowlist we can set |
| Grading | `llm` rubric (best of three votes), `regex`, `tool_used`, `tool_order`, `file_exists`, `baseline` | An LLM judge against `expected_output` and `assertions`, plus `checks` (`file_exists`, `script_invoked`, `command_succeeded`, `output_matches`, `output_contains`), or a custom `grader.py` |
| Repeats | 3 runs per case by default; case score is the mean | `n_attempts`; reports pass@k |
| CI gating | Exit 1 below `--threshold`, exit 2 on a partial run; JSON `aggregate-result.json` | **Only Tier 1 gates CI.** Tier 3 in CI is advisory, and the docs call all-tier CI "an explicit opt-in and unreleased capability"; `--tier3-required` is deprecated and ignored |
| Cost controls | `--max-cost-usd` (list-price estimate, includes judge calls), `--runs`, `--ablation none` | `--max-cost-usd` with our own price file (agent spend only, not judge spend), `--max-agent-tokens`, `--max-judge-calls`, `--max-cases`, `--skip-baseline` |
| Models | Claude only, `--model` and `--judge-model` | Claude Code, Codex, OpenCode; judge from Anthropic, OpenAI, NVIDIA Build, Bedrock or an OpenAI-compatible gateway |

## Answers

### Can it run our existing cases?

Not without porting. And for two of the three cases the port loses the thing the case tests.

- **Format.** The three suites would become three `evals.json` files, one in each of `skills/repo-new/evals/`, `skills/repo-adopt/evals/` and `skills/repo-github-setup/evals/`. That is inside `skills/`, the opposite of the move we just made for `claude plugin eval`, and the files would then ship in the plugin. The 21 rubric graders map fairly mechanically to `assertions`. A few, such as `.copier-answers.yml` existing, could become `checks`. Our graders are all `focus: trace`, and their judge reads a trajectory of a set size ("evidence budgets"), so long Copier runs may have their middle cut.
- **Scaffolds.** `place-files.sh` can't run per case in a with/without comparison, because `pre_agent_setup` is refused there. `adopt-poetry-library` could move its fixture into `evals/files/`, and a Dockerfile step could do the `git init`. `setup-stops-for-confirmation` builds its repo with Copier from `gh:ZeleMate/repo-template` using the `gh` login. That would have to happen in the Dockerfile at image build time, with no token there, so the owner can't come from `gh api user`.
- **Plugin layout.** `repo-adopt` reads `copier.yml`, `template/` and `README.md` at the plugin root, plus `skills/repo-new/references/` and `skills/repo-new/scripts/verify-generated.sh`. An isolated skill workspace has none of these. `--copy-repo` would provide them, but the without-skill arm then sees the template too, which weakens the baseline. Claude Code's own plugin loading is what we want to test, and SkillEvaluator doesn't load the plugin at all.
- **Toolchain in the container.** The default image is `python:3.12-slim`. Since 0.9.0, Claude Code containers have no Node.js unless the image supplies it. Our cases need git, uv and `gh` (and Node for TypeScript answers), so we would maintain an `evals/environment/Dockerfile` for each skill.

Rough size of the port: three dataset files, three Dockerfiles, rewritten fixtures, and probably a custom grader for the "nothing was pushed" checks. That is a second eval suite to keep in step with the first, not a migration.

### Can it run in GitHub Actions headless? Which secret?

Partly. Docker is available on `ubuntu-latest`, so Tier 3 can run there in principle. But SkillEvaluator's own CI path for Tier 3 is unreleased and advisory, so we would write the workflow ourselves and do our own gating on the JSON report.

The secret has to be an **Anthropic API key** (`ANTHROPIC_API_KEY`), not a Claude subscription token. Harbor's Claude Code adapter does accept `CLAUDE_CODE_OAUTH_TOKEN` for the agent. But SkillEvaluator also needs a judge ("evaluator provider"), and its providers are `anthropic`, `openai`, `nv_build`, `bedrock` and `openai-compatible`, all of which take API keys. With `anthropic`, one key serves both the agent and the judge. A free NVIDIA Build key could be the judge, but in Docker mode that path also sends Claude Code's requests through NVIDIA's bridge to Nemotron, unless we override the model and give Claude Code its own key. Either way it is an API key and API billing.

`claude plugin eval` uses Claude Code's normal sign-in, so the `claude setup-token` token the generated repos already use for the Claude reviewer should work in CI against plan usage. The docs' CI example names `ANTHROPIC_API_KEY`. We haven't tried the OAuth token in a CI job yet.

### Cost and time of one run

Neither tool gives a fixed figure, and SkillEvaluator says it "does not estimate a fixed dollar amount". The trial count is the same for both: cases × runs × 2 arms, plus judge calls. Our cases allow 40 to 80 turns and 20 to 30 minutes each, and a full Copier render and verification is most of that. A SkillEvaluator run adds the container image build (git, uv, gh, Claude Code install) to each task. Its cost ceiling also leaves out judge spend, while `claude plugin eval`'s `--max-cost-usd` includes it. Expect SkillEvaluator to cost the same or more and take longer per run. For our own numbers, read `costUsd` and `durationSeconds` from the `aggregate-result.json` of a `claude plugin eval` run.

### Does it meet our needs?

| Need | SkillEvaluator |
| --- | --- |
| Copier against a remote template | Yes, with uv and git installed in a custom image |
| Network | Yes, but all of it: there is no allowlist like our GitHub/PyPI/npm grants |
| git, uv | Only through our own Dockerfile |
| Authenticated `gh` for one scaffold | Only as `GH_TOKEN` in the agent's environment through `harbor.runtime_env` (not on its blocked-credential list). There's no setup step to use it outside the agent, and Docker egress is open |

### What it has that `claude plugin eval` doesn't

- **Several agents and model providers** (Codex, OpenCode, non-Anthropic judges). Our skills are Claude Code skills with Claude-specific instructions, so this doesn't help us.
- **pass@k and more attempt detail.** `claude plugin eval` already does 3 runs per case and gives a mean and per-run results, which is enough for our three cases.
- **Tier 1 static checks**: skill schema and quality score, SkillSpector security scan, Gitleaks, and a "harness check" of how each agent loads a skill. These are new to us and need no key.
- **Container isolation per trial.** This is a real plus for running untrusted skills. Ours are our own, and Claude Code's sandbox already limits writes and network.

It's missing things we use: real plugin loading, per-domain network grants, host-side scaffolds in a with/without run, a Tier 3 CI gate, and judge cost inside the cost ceiling.

### Security

- **Licence and maintainer.** Apache-2.0, NVIDIA, with a private vulnerability-reporting process in `SECURITY.md`. Licence and maintainer are fine.
- **Maturity.** "Experimental" support and nine minor releases in about three months. Expect breaking changes; 0.9.0 alone removed Node.js from Claude Code containers.
- **What it runs.** The PyPI package and its 32 direct dependencies; Harbor (`harbor==0.25.0`); SkillSpector and Gitleaks release binaries (it says it verifies the pinned versions it downloads); Claude Code 2.1.292, which Harbor installs inside each container; and the Docker base images. Their GitHub template calls a reusable workflow pinned to a commit SHA (`evaluate-skills.yml@ba7779ad…`) and a pinned scanner image. That matches our pin-by-SHA rule, but we would still be running a large third-party dependency tree in a job that holds an Anthropic API key.
- **Credential handling.** This is done carefully. Agent keys come only from the host environment. A skill's `evals/config.yml` can't name or reference `ANTHROPIC_API_KEY` or the base-URL variables. Logs redact GitHub-token patterns. But `GH_TOKEN` isn't protected the same way: passing it in for the `repo-github-setup` case puts it in the agent's environment, with open egress, in both arms. The without-skill arm is the one most likely to run `gh repo create` for real. The same risk applies to our current setup, which also passes `GH_TOKEN` to every run. Whichever tool runs in CI, that case should get a token that can't create repos, or move to a mock.

## Recommendation

**Don't use SkillEvaluator for the skill evals. Put `claude plugin eval` in CI for 1.0.**

1. **It tests a different thing.** SkillEvaluator measures one skill folder in a generic container. Our skills work as a plugin: they share the plugin root and each other's scripts. `claude plugin eval` loads the plugin the way users get it, and that loading is part of what we need to test.
2. **It can't gate CI on agent results.** Tier 3 in CI is advisory and unreleased. We would write our own gating around it, while `claude plugin eval` already exits 1 below `--threshold`.
3. **Porting costs more than it gives back.** Three Dockerfiles, moved fixtures, scaffolds turned into image steps, `evals.json` back inside `skills/`, and open network instead of our domain allowlist. Its extras (multi-agent, other providers) don't apply to Claude Code skills.
4. **Credentials and cost.** It needs API billing even where a subscription token would do, and its cost ceiling leaves out judge spend.
5. **Supply chain.** An "Experimental" tool that changes weekly, with a large dependency tree, would run in a job that holds a model key. We'd be taking on that risk for little benefit.

**Possible later use (not for 1.0):** Tier 1 alone, keyless (`llm: false`), from their SHA-pinned workflow, as an advisory lint on `skills/**`. It needs no secrets, so the risk is small, and the SkillSpector scan and harness check are things we have nothing for. Try it locally first and read what it flags before adding a workflow. For generated repos: their `evals.yml` evaluates the app (Inspect AI), not Claude Code skills, so SkillEvaluator has no place in the template.

**For the open 1.0 item**, the CI job would be a `workflow_dispatch` (and perhaps weekly) job running `scripts/run-evals.sh <skill> --runs 1 --json …` with `--threshold`, `--max-cost-usd`, pinned `--model` and `--judge-model`, and `--no-publish`, on a Linux runner with `bubblewrap` and `socat`. Give the `repo-github-setup` case a token that can't create repos before it runs in CI.

## What was and wasn't run

- I read the SkillEvaluator repo from a shallow clone in a scratch folder outside this repo, and ran none of its code.
- I tried to run `uvx skillevaluator==0.9.0 quality-check` (keyless, no tokens) on a scratch copy of `skills/`, but the session's permission rules blocked it. Nothing above comes from running SkillEvaluator. The Tier 1 trial suggested above is still to do.
- I didn't change any eval, workflow, secret or GitHub setting.
