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

The script is idempotent and reports failures instead of stopping, because some endpoints depend on plan or visibility. Read its output and explain each `failed:` line. Known ones: private + Free repos skip the ruleset and environment by design.

### 4. Manual steps

The script ends by printing the manual checklist from `docs/SETUP.md`. Go through it with the user one item at a time, and for each give the exact link or command. Some notes that make these go smoothly:

- **Secrets are typed by the user, not by you.** The generated `.claude/settings.json` denies `gh secret *` to Claude on purpose, so a token never passes through the conversation or the transcript. Give the command and let the user run it in their terminal.
- **Which secrets, and how to create each:** the repo's `.github/secret-requirements.json` lists them, and `docs/SETUP.md` has the step for each one. Don't work them out from the answers yourself. A repo that won't release can run `gh workflow disable release.yml` instead of creating `RELEASE_PLEASE_TOKEN`; the audit then doesn't ask for it.
- **SonarQube Cloud:** install its GitHub App and import the repo. Leave Automatic Analysis on; it needs no CI job or `SONAR_TOKEN`.
- **Trusted publishing**, on each registry the repo's `.github/language-profiles.json` names (`registry` per language; `null` means none, as for Go, whose binaries go on the GitHub release with the workflow's own token): for a brand-new package use the registry's "pending publisher" form, with workflow `release.yml` and (if public or Pro) environment `release`.
- **Agentic apps:** `docs/THREAT_MODEL.md` §5 plus `docs/agent-policy.md` filled in before the first agent feature ships.
- **Malware alerts** are a UI-only toggle under Settings → Advanced Security.
- `uvx pre-commit install` in the local clone.

### 5. Confirm

Run the audit below. Everything the API can see should be `ok`; whatever is left are the manual items the user hasn't done yet. Then suggest a first PR to see CI go green end to end.

## Audit

```bash
bash <this skill's base directory>/scripts/audit-github.sh <repo-dir> [owner/repo]
```

Read-only. It compares merge settings, Actions permissions, SHA pinning, Dependabot, public-repo security features, the `main` ruleset, release settings against what the answers imply, and the names of secrets against the repo's `.github/secret-requirements.json` (a repo generated before that file existed gets `?` for secrets until `copier update`), and lists what the API can't show (apps, SonarQube, trusted publishers). `?` means it couldn't read a setting, usually missing admin rights or a plan limit — not drift.

For drift, the usual fix is re-running `./scripts/bootstrap-github.sh` (dry run first), since it is idempotent. Missing secrets go back to the manual steps above. If a setting was changed on purpose, suggest recording that as an ADR in `docs/decisions/` rather than leaving it as silent drift.
