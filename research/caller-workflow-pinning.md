# How should caller workflows pin central workflows?

Research for [#5](https://github.com/ZeleMate/repo-template/issues/5) (child of map [#2](https://github.com/ZeleMate/repo-template/issues/2)).
Researched 2026-11-03 against current docs and the `main` branches of zizmor (latest release v1.32.0), actionlint (v1.7.12), dependabot-core and Renovate.

## Answer

Pin the caller's `uses:` to the **full commit SHA of a release tag in the central repo, with the tag as a same-line comment**:

```yaml
jobs:
  ci:
    uses: ZeleMate/workflows/.github/workflows/ci.yml@0123456789abcdef0123456789abcdef01234567 # v1.4.0
```

That is the only form that is GitHub's own recommendation, passes zizmor's default `unpinned-uses` policy unchanged, keeps `impostor-commit` / `ref-version-mismatch` meaningful, and gets clean, tag-to-tag Dependabot and Renovate PRs. It also means the central repo must cut **tags (ideally immutable releases)**; branch-only refs make every bot update a "latest commit on default branch" bump.

Two things nothing does for you: the GitHub workflow **lockfile does not cover reusable-workflow calls**, and **actionlint cannot type-check inputs/secrets of a remote reusable workflow**. And for a **private** central repo on a personal account, Dependabot's access to it is the one piece not confirmed by docs (see Open questions).

## Findings

### GitHub itself

- **Syntax and ref types.** `{owner}/{repo}/.github/workflows/{filename}@{ref}`; `{ref}` may be a commit SHA, a release tag or a branch; a tag wins over a same-named branch. "Using the commit SHA is the safest option for stability and security." ([Reuse workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows))
- **Same guidance as actions.** The secure-use reference says the principles for third-party actions "also apply to using third-party workflows": pin to a full-length SHA, and use tags only if you trust the creator, since tags can be moved or deleted. ([Secure use reference](https://docs.github.com/en/actions/reference/security/secure-use))
- **"Require actions to be pinned to a full-length commit SHA" policy does not cover reusable workflows.** The repo/org Actions settings page says "Reusable workflows can still be referenced by tag." The actions *inside* the called workflow still must be SHA-pinned, because the policy applies to every action that runs. ([Managing GitHub Actions settings for a repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository); policy announcement: [changelog 2025-08-15](https://github.blog/changelog/2025-08-15-github-actions-policy-now-supports-blocking-and-sha-pinning-actions/)). So the policy is no reason to pin callers; our own security posture is.
- **Workflow lockfiles (`.github/workflows/actions.lock`, `gh actions-lock`, public preview) do not pin reusable-workflow calls.** The concept page says the lockfile "doesn't pin calls to reusable workflows (`jobs.<job_id>.uses`)"; reference them by full SHA instead. A reusable workflow's own action dependencies are covered by the lockfile of the repo where it is defined, i.e. the central repo. ([Workflow dependency lockfiles](https://docs.github.com/en/actions/concepts/security/workflow-dependency-lockfiles); zizmor source references the tracking issue [github/gh-actions-lock#179](https://github.com/github/gh-actions-lock/issues/179)). Availability is contested: the [changelog](https://github.blog/changelog/2026-10-14-github-actions-workflow-lockfiles-in-public-preview/) mentions Enterprise Cloud; not verified whether personal accounts get it.
- **Private central repo on a personal account.** In the central repo's Settings > Actions > General > Access, choose "Accessible from repositories owned by '<user>' user". Access is allowed only from private repositories, so **public callers cannot use a private central repo**. (Same settings page as above.)
- **Immutable releases** lock a release's tag to its commit: it "cannot be changed, and cannot be deleted while the release exists." That makes the `# vX.Y.Z` comment trustworthy and reduces the tag-move risk, but does not change the recommendation. The docs do not say whether personal-account repos are eligible. ([Immutable releases](https://docs.github.com/en/code-security/supply-chain-security/understanding-your-software-supply-chain/immutable-releases))

### Dependabot

- **Detects and bumps reusable-workflow refs, SHA-pinned ones included.** Docs: Dependabot keeps "reusable workflows used inside workflows" up to date, ignores local (`./`) references, and updates the version comment "when the comment is on the same line". If a pinned commit "is not associated with any tag", Dependabot updates to the latest commit, "which might differ from the latest release". ([Keeping actions up to date](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/keeping-your-actions-up-to-date-with-dependabot), [Supported ecosystems](https://docs.github.com/en/code-security/dependabot/ecosystems-supported-by-dependabot/supported-ecosystems-and-repositories))
- **Source confirms it.** `dependabot-core/github_actions/lib/dependabot/github_actions/file_parser.rb` special-cases paths matching `/.github/workflows/*.yml` and names the dependency `owner/repo/.github/workflows/file.yml`, so each central workflow is its own dependency (relevant for `groups`, `ignore` and cooldown patterns). Older history: [dependabot-core#4327](https://github.com/dependabot/dependabot-core/issues/4327) (support request, closed), [#12489](https://github.com/dependabot/dependabot-core/issues/12489) (newer-version detection, closed as not reproducible).
- **Private repos.** Docs say "Dependabot supports both public and private repositories for GitHub Actions", with a `git` registry (`url: https://github.com`, `username: x-access-token`, `password: ${{ secrets.<PAT> }}`) as the documented auth path ([Configuring access to private registries](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/configuring-access-to-private-registries-for-dependabot); example in [dependabot-core#13166](https://github.com/dependabot/dependabot-core/issues/13166)). The no-token "grant Dependabot access to private repositories" switch is an **organization** security setting ([org security settings](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-security-and-analysis-settings-for-your-organization)); there is no documented personal-account equivalent. **Unverified:** whether Dependabot in a personal-account private repo can read a sibling private repo without that `git` registry + PAT.
- **Our current config interacts.** The template's `dependabot.yml` sets `cooldown.default-days: 7` for `github-actions`. That delays central-workflow bumps a week too. Cooldown has `exclude` (wildcards allowed), so `exclude: ["ZeleMate/workflows/*"]` (or whatever the repo is named) would let our own releases through immediately. ([Dependabot options reference](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/dependabot-options-reference))

### Renovate (for comparison)

- Job-level `uses: owner/repo/.github/workflows/<file>.yml@<ref>` is extracted with `depType: workflow` (vs `action`), so it can get separate `packageRules`. Source: `lib/modules/manager/github-actions/extract.ts` (`reusableWorkflowPathRe`). ([github-actions manager docs](https://docs.renovatebot.com/modules/manager/github-actions/))
- SHA pins are updated "according to the GitHub tag you specified" in the comment; **a bare SHA with no version comment is disabled by default**; branch refs get digest-only updates. `helpers:pinGitHubActionDigests` converts tag refs to SHA+comment.
- Private repos: self-hosted Renovate uses its GitHub token / `hostRules`; the Mend app uses its installation and App-settings secrets. ([Private packages](https://docs.renovatebot.com/getting-started/private-packages/)). Not verified end to end for a private reusable workflow.

### zizmor

- **`unpinned-uses` audits reusable-workflow calls.** `crates/zizmor/src/audit/unpinned_uses.rs` implements `audit_reusable_job`, which runs the same policy check as for steps. Default policy is blanket `hash-pin` (first-party `actions/*` too since v1.20.0), so `@v1` or `@main` on a central workflow is a High finding out of the box. ([Audits: unpinned-uses](https://docs.zizmor.sh/audits/#unpinned-uses))
- **Relaxing for our own repo is possible but not recommended.** Policies are pattern-based (`owner/*`, `owner/repo/*`, exact `owner/repo/path`), e.g. `ZeleMate/workflows/*: ref-pin`. Unlike steps, a lockfile cannot silence the finding for reusable jobs (source comment: "GitHub's lockfile does not support reusable workflows yet").
- **Other audits that understand reusable-workflow `uses:`** (they have `audit_reusable_job` or handle `Job::ReusableWorkflowCallJob`): `impostor-commit` (its module doc: "Audits reusable workflows and pinned actions for 'impostor' commits"), `ref-version-mismatch` (SHA vs `# vX` comment), `stale-action-refs` (pedantic: SHA not pointing at a tag), `archived-uses`, `typosquat-uses`, `secrets-inherit` (flags `secrets: inherit`; callers should pass secrets explicitly), `self-repository`. `known-vulnerable-actions` only looks at steps.
- **Online audits and a private central repo.** `impostor-commit`, `ref-version-mismatch` and `stale-action-refs` call the GitHub API. **Unverified:** how they behave when the token (CI's `GITHUB_TOKEN`, or none in pre-commit) cannot read the private central repo. Test before relying on them.

### actionlint

- Only checks the *shape*: a remote call must match `owner/repo/path/to/workflow.yml@ref` (`rule_workflow_call.go`, `isWorkflowCallUsesRepoFormat`). It does not care whether the ref is a SHA, tag or branch.
- Input/secret existence and type checks run **only for local** (`./`) reusable workflows: "Note that this check only works with local reusable workflow (it starts with `./`)." ([actionlint checks](https://github.com/rhysd/actionlint/blob/main/docs/checks.md#check-inputs-and-secrets-in-workflow-call)). So a caller passing a wrong input to a central workflow is caught only at run time.

## Ref choice at a glance

| Ref form | GitHub guidance | SHA-pin policy | zizmor default | Dependabot | Renovate |
| --- | --- | --- | --- | --- | --- |
| `@<sha> # v1.4.0` (tag's commit) | recommended | passes | passes | bumps to new tag SHA + comment | bumps per tag comment |
| `@<sha>` (untagged commit) | ok | passes | passes (`stale-action-refs` pedantic) | bumps to latest default-branch commit | disabled unless comment added |
| `@v1` / `@v1.4.0` tag | "only if you trust the creator" | passes (reusable workflows exempt) | **High** `unpinned-uses` | bumps tag | bumps tag |
| `@main` branch | discouraged | passes | **High** `unpinned-uses` | no meaningful update | digest pinning only |

## Open questions / not verified

1. Dependabot reading a **private** central repo from a **personal-account** private repo without a `git` registry + PAT. Test with one caller; fall back to a fine-grained PAT (read-only contents on the central repo) stored as a Dependabot secret.
2. zizmor online audits against a private central repo with the default token.
3. Whether workflow lockfiles and immutable releases are available on personal-account repos.
4. Public callers cannot use a private central repo at all, so a template that may generate public repos needs a public central repo (or a per-visibility fallback).
