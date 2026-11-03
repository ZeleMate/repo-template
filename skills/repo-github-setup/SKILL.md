---
name: repo-github-setup
description: Create the GitHub repo for a repo-template project and apply its hardened settings (squash-only merges, read-only Actions token, SHA pinning required, Dependabot, secret scanning/CodeQL/private vulnerability reporting on public repos, the `main` ruleset requiring ci-ok, immutable releases and the release environment), then walk the user through the manual steps (secrets, Claude/CodeRabbit apps, SonarQube Cloud, trusted publishing, release-please token). Also audits an existing repo's live GitHub settings for drift from that baseline. Use whenever someone wants to push a newly generated repo to GitHub, run bootstrap-github.sh, "finish setup", set up branch protection/rulesets, configure repo secrets for CI, or check whether a repo's GitHub settings are still correct.
---

# GitHub setup and audit

This works on any repo that has a `.copier-answers.yml` from the repo template (created by `repo-new` or `repo-adopt`). The answers decide what is expected: visibility, plan, whether it publishes, which reviewers and services.

Two jobs live here. **Setup** changes things on GitHub, so it always goes dry run → user confirms → real run. **Audit** is read-only and can run any time.

## Setup

### 1. Preconditions

- `gh auth status` must show the account that is `github_owner` (or an admin of that org). If not, ask the user to run `gh auth login`; don't try to authenticate for them.
- Read `.copier-answers.yml` and `docs/SETUP.md` so you can tell the user what is about to happen in terms of *their* answers.
- Make sure the generated files are what the user wants committed. The script makes the initial commit from everything in the folder.

### 2. Dry run

```bash
./scripts/bootstrap-github.sh --dry-run
```

Show the user the plan in plain words: creates `<owner>/<slug>` as public/private and pushes; squash-only merges; read-only Actions token and required SHA pinning; Dependabot alerts and fixes; on public repos secret scanning, push protection, private vulnerability reporting and CodeQL; the `main` ruleset (PR + `ci-ok` required, no force-push) when public or Pro; immutable releases and the `release` environment when publishing.

### 3. Real run, after a clear yes

Creating a repo and pushing code is visible to others and on a public repo it's immediately public. Ask before running:

```bash
./scripts/bootstrap-github.sh
```

The script is idempotent and reports failures instead of stopping, because some endpoints depend on plan or visibility. Read its output and explain each `failed:` line. Known ones: `sha_pinning_required` may not be supported on personal-account repos, and private + Free repos skip the ruleset and environment by design.

### 4. Manual steps

The script ends by printing the manual checklist from `docs/SETUP.md`. Go through it with the user one item at a time, and for each give the exact link or command. Some notes that make these go smoothly:

- **Secrets are typed by the user, not by you.** The generated `.claude/settings.json` denies `gh secret *` to Claude on purpose, so a token never passes through the conversation or the transcript. Give the command and let the user run it in their terminal.
- **Claude review:** no Claude GitHub App is needed; since template v0.2.0 the workflow posts with the job's own `GITHUB_TOKEN`. `claude setup-token` prints the OAuth token, and it usually wraps onto two lines, so a pasted copy can include a line break and fail with an immediate `is_error` result. Have the user copy it, check `pbpaste | tr -d '[:space:]' | wc -c` shows about 108, then store it with `pbpaste | tr -d '[:space:]' | gh secret set CLAUDE_CODE_OAUTH_TOKEN -R <owner>/<slug>` and clear the clipboard. Until the secret exists, the review job passes with a warning.
- **RELEASE_PLEASE_TOKEN:** fine-grained PAT scoped to this one repo with contents + pull requests read/write. Without it release PRs are opened by `GITHUB_TOKEN` and don't trigger CI, so `ci-ok` never reports and they can't merge.
- **SonarQube Cloud:** import the repo, then turn **off** Automatic Analysis (CI analysis and automatic analysis conflict), then `SONAR_TOKEN`.
- **Trusted publishing:** for a brand-new package use the registry's "pending publisher" form, with workflow `release.yml` and (if public or Pro) environment `release`.
- **Agentic apps:** a spend-capped key for `EVAL_ANTHROPIC_API_KEY`, and `docs/THREAT_MODEL.md` §5 plus `docs/agent-policy.md` filled in before the first agent feature ships.
- **Malware alerts** are a UI-only toggle under Settings → Advanced Security.
- `uvx pre-commit install` in the local clone.

### 5. Confirm

Run the audit below. Everything the API can see should be `ok`; whatever is left are the manual items the user hasn't done yet. Then suggest a first PR to see CI go green end to end.

## Audit

```bash
bash <this skill's base directory>/scripts/audit-github.sh <repo-dir> [owner/repo]
```

Read-only. It compares merge settings, Actions permissions, SHA pinning, Dependabot, public-repo security features, the `main` ruleset, release settings and the names of required secrets against what the answers imply, and lists what the API can't show (apps, SonarQube, trusted publishers). `?` means it couldn't read a setting, usually missing admin rights or a plan limit — not drift.

For drift, the usual fix is re-running `./scripts/bootstrap-github.sh` (dry run first), since it is idempotent. Missing secrets go back to the manual steps above. If a setting was changed on purpose, suggest recording that as an ADR in `docs/decisions/` rather than leaving it as silent drift.
