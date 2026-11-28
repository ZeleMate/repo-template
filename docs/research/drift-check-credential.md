# Which credential can read everything `bootstrap-github.sh --check` reads

Question ([#94](https://github.com/ZeleMate/repo-template/issues/94), on map [#84](https://github.com/ZeleMate/repo-template/issues/84)): which credential lets a scheduled workflow in a generated repo read everything `scripts/bootstrap-github.sh --check` reads? For each endpoint: the permission a fine-grained PAT needs, the permission a GitHub App installation token needs, and whether the default `GITHUB_TOKEN` can read it. Plus free-plan private-repo differences, and each credential's lifetime and rotation. Facts only, no decision.

**Short answer.** The default `GITHUB_TOKEN` can't run the whole check. Seven of the endpoints need the repository **Administration** permission and one needs **Secrets**, and neither is in the list of permissions a workflow can grant `GITHUB_TOKEN`. A fine-grained PAT and a GitHub App installation token use the same permission names for every endpoint here. The read-only set is Metadata, Administration, Actions and Secrets, all `read`. The GitHub docs name two more conditions, and each could leave a field the check compares unread, which the check reports as `?`:

- The merge settings on `GET /repos/{repo}` need Contents **read and write**.
- `bypass_actors` on a ruleset is returned only to a caller with write access to that ruleset.

Neither condition has been checked live for token types. A private template repo also has to be inside the token's reach.

Sources: GitHub's REST docs (API version 2022-11-28), [Permissions required for fine-grained personal access tokens](https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens), [Permissions required for GitHub Apps](https://docs.github.com/en/rest/authentication/permissions-required-for-github-apps), the per-endpoint reference pages linked below, and the Actions, PAT and GitHub App docs linked in each section. Checked 2026-11-28 against the template at plugin 1.3.1.

## What the check reads

`--check` reads only through `gh_read`, which calls `gh api` with GET. The endpoints come from the rendered `.github/settings-requirements.json` (template: `template/.github/settings-requirements.json.jinja`) and `.github/secret-requirements.json` (from `includes/secrets.jinja`), plus fixed reads in `template/scripts/bootstrap-github.sh.jinja`. The recorded responses in `tests/github-settings/recorded/compliant/` cover the same set.

| # | Endpoint (GET) | Read when | What the check compares |
|---|---|---|---|
| 1 | `repos/{repo}` | always | exists; `visibility`; `allow_squash_merge`, `allow_merge_commit`, `allow_rebase_merge`, `delete_branch_on_merge`, `allow_auto_merge`, `has_wiki`, `squash_merge_commit_title`, `squash_merge_commit_message`; public only: `security_and_analysis.secret_scanning(_push_protection).status` |
| 2 | `repos/{repo}/actions/permissions/workflow` | always | `default_workflow_permissions`, `can_approve_pull_request_reviews` |
| 3 | `repos/{repo}/actions/permissions` | always | `enabled`, `sha_pinning_required`, `allowed_actions` (the `when` gate for #4) |
| 4 | `repos/{repo}/actions/permissions/selected-actions` | `allowed_actions == "selected"` | `patterns_allowed` |
| 5 | `repos/{repo}/vulnerability-alerts` | always | 204 = on, 404 = off (drift) |
| 6 | `repos/{repo}/automated-security-fixes` | always | `enabled` |
| 7 | `repos/{repo}/private-vulnerability-reporting` | public | `enabled` |
| 8 | `repos/{repo}/code-scanning/default-setup` | public | `state`, `query_suite` |
| 9 | `repos/{repo}/actions/permissions/fork-pr-contributor-approval` | public | `approval_policy` |
| 10 | `repos/{repo}/rulesets`, then `rulesets/{id}` | `has_governance` | the whole `.github/rulesets/main.json`, including `bypass_actors: []` |
| 11 | `repos/{repo}/immutable-releases` | `publishes` | `enabled` |
| 12 | `repos/{repo}/environments/release` | `publishes` and `has_governance` | `deployment_branch_policy` |
| 13 | `repos/{repo}/environments/release/deployment-branch-policies`, then `/{id}` | `publishes` and `has_governance` | an item named `main`, type `branch` |
| 14 | `repos/{repo}/actions/secrets?per_page=100` | a secret requirement with `store: actions` exists (always: `TEMPLATE_READ_TOKEN`) | secret names only |
| 15 | `repos/{repo}/actions/workflows/release.yml` | `RELEASE_PLEASE_TOKEN` is listed (repos with `languages`) and `release.yml` is in the repo | `state == "disabled_manually"` (the waiver) |
| 16 | `repos/{TPL}`: the **template** repo from `_src_path` | `TEMPLATE_READ_TOKEN` has `only_if: template_private` (always) | `private` |

How the script handles failed reads: an HTTP 404 is `missing`, which counts as drift. Any other failure, or a key that's absent from GitHub's answer, is `?`. So a token that can read an endpoint but gets a body without some field produces `?`, not a false drift. The exception is #5, where off means 404 (see "Open points").

## Permission per endpoint

The PAT and App columns are the "Repository permissions" tables on the two permissions pages above. Every row there is `read`, with no "additional permissions" mark, and each is listed for both PAT and IAT (installation access token). The `GITHUB_TOKEN` column compares that permission with the scopes a workflow can grant ([Workflow syntax: `permissions`](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#permissions)): `actions`, `artifact-metadata`, `attestations`, `checks`, `code-quality`, `contents`, `copilot-requests`, `deployments`, `id-token`, `issues`, `discussions`, `packages`, `pages`, `pull-requests`, `security-events`, `statuses`, `vulnerability-alerts`. That list has no `administration` and no `secrets` scope. `GITHUB_TOKEN` "is a GitHub App installation access token" for the GitHub Actions app ([GITHUB_TOKEN](https://docs.github.com/en/actions/concepts/security/github_token)), so the GitHub App table applies to it as well, limited to those scopes.

| # | Endpoint | Fine-grained PAT | App installation token | Default `GITHUB_TOKEN` |
|---|---|---|---|---|
| 1 | [Get a repository](https://docs.github.com/en/rest/repos/repos#get-a-repository) | Metadata: read | Metadata: read | Yes for the base object. See the field notes below. |
| 2 | [Get default workflow permissions](https://docs.github.com/en/rest/actions/permissions#get-default-workflow-permissions-for-a-repository) | Administration: read | Administration: read | **No** (no `administration` scope) |
| 3 | [Get GitHub Actions permissions](https://docs.github.com/en/rest/actions/permissions#get-github-actions-permissions-for-a-repository) | Administration: read | Administration: read | **No** |
| 4 | [Get allowed actions](https://docs.github.com/en/rest/actions/permissions#get-allowed-actions-and-reusable-workflows-for-a-repository) | Administration: read | Administration: read | **No** |
| 5 | [Check if vulnerability alerts are enabled](https://docs.github.com/en/rest/repos/repos#check-if-vulnerability-alerts-are-enabled-for-a-repository) | Administration: read | Administration: read | **No**. The `vulnerability-alerts: read` scope maps to the "Dependabot alerts" permission (listing alerts), not to this endpoint. |
| 6 | [Check if Dependabot security updates are enabled](https://docs.github.com/en/rest/repos/repos#check-if-dependabot-security-updates-are-enabled-for-a-repository) | Administration: read | Administration: read | **No** |
| 7 | [Check if private vulnerability reporting is enabled](https://docs.github.com/en/rest/repos/repos#check-if-private-vulnerability-reporting-is-enabled-for-a-repository) | Metadata: read | Metadata: read | Yes |
| 8 | [Get code scanning default setup](https://docs.github.com/en/rest/code-scanning/code-scanning#get-a-code-scanning-default-setup-configuration) | Administration: read | Administration: read | **No** (`security-events` covers alerts, not this endpoint) |
| 9 | [Get fork PR contributor approval](https://docs.github.com/en/rest/actions/permissions#get-fork-pr-contributor-approval-permissions-for-a-repository) | Administration: read | Administration: read | **No** |
| 10 | [Get all rulesets](https://docs.github.com/en/rest/repos/rules#get-all-repository-rulesets) / [Get a ruleset](https://docs.github.com/en/rest/repos/rules#get-a-repository-ruleset) | Metadata: read | Metadata: read | Yes, but without `bypass_actors` (below) |
| 11 | [Check if immutable releases are enabled](https://docs.github.com/en/rest/repos/repos#check-if-immutable-releases-are-enabled-for-a-repository) | Administration: read | Administration: read | **No** |
| 12 | [Get an environment](https://docs.github.com/en/rest/deployments/environments#get-an-environment) | Actions: read | Actions: read | Yes, with `actions: read` |
| 13 | [List](https://docs.github.com/en/rest/deployments/branch-policies#list-deployment-branch-policies) / [Get a deployment branch policy](https://docs.github.com/en/rest/deployments/branch-policies#get-a-deployment-branch-policy) | Actions: read | Actions: read | Yes, with `actions: read` |
| 14 | [List repository secrets](https://docs.github.com/en/rest/actions/secrets#list-repository-secrets) | Secrets: read | Secrets: read | **No** (no `secrets` scope) |
| 15 | [Get a workflow](https://docs.github.com/en/rest/actions/workflows#get-a-workflow) | Actions: read | Actions: read | Yes, with `actions: read` |
| 16 | Get a repository, on the template repo | Metadata: read, and the template repo must be in the token's repository selection | Metadata: read, and the app must be installed on the template repo | Only if the template repo is public: "The token's permissions are limited to the repository that contains your workflow" ([GITHUB_TOKEN](https://docs.github.com/en/actions/concepts/security/github_token)) |

The endpoint pages add these conditions:

- **#1, merge settings.** "To view merge-related settings, you must have the `contents:read` and `contents:write` permissions" ([Get a repository](https://docs.github.com/en/rest/repos/repos#get-a-repository)). The check compares eight merge-related fields. A read-only token would leave them out of the answer, and the check would show `?` for each one. `GITHUB_TOKEN` can be given `contents: write` in the job's `permissions` block. The docs don't say which of the eight fields count as "merge-related".
- **#1, `security_and_analysis`.** "you must have admin permissions for the repository or be an owner or security manager for the organization" ([Get a repository](https://docs.github.com/en/rest/repos/repos#get-a-repository)). This applies to public repos only, where the check compares secret scanning and push protection. The docs don't name the token permission that counts as "admin" here. `GITHUB_TOKEN` can't have admin.
- **#2 to #9, #11.** The pages for #5, #6 and #11 say: "The authenticated user must have admin read access to the repository". For #2 to #4 and #9, classic PATs "need the `repo` scope".
- **#4.** It works only when the repo's `allowed_actions` is `selected`. The check reads it only then, gated on #3, so a credential that can't read #3 never reaches #4.
- **#10, `bypass_actors`.** "the `bypass_actors` property is only returned if the user making the API request has write access to the ruleset" ([Get a ruleset](https://docs.github.com/en/rest/repos/rules#get-a-repository-ruleset)). Writing a ruleset is Administration: write on both permissions pages. `main.json` has `"bypass_actors": []`. A caller without write access would get no such key, and the check would show `?` for it.
- **#12, #13, #15.** "Anyone with read access to the repository can use this endpoint".
- **#14.** "Authenticated users must have collaborator access to a repository to create, update, or read secrets". Only names are returned, never values.

### What each credential needs in total

- **Fine-grained PAT or GitHub App, read-only:** Metadata: read (granted automatically), Administration: read, Actions: read, Secrets: read. Repository access must cover the generated repo, plus the template repo when that is private.
- **To also read the merge settings (#1):** Contents: read **and write**, per the note above.
- **To also read `bypass_actors` (#10):** write access to the ruleset, which means Administration: write.
- **Default `GITHUB_TOKEN`, with `actions: read` and optionally `contents: write`:** can read #1 (base fields; merge fields only with `contents: write`), #7, #10 (without `bypass_actors`), #12, #13, #15, and #16 when the template is public. It can't read #2 to #6, #8, #9, #11 or #14 in any configuration.

## Private repos on the free plan

The rendered requirements already leave out what a free private repo can't have. Those entries become `unavailable`, and the check shows `?` for them without reading anything:

- When `is_public` is false: no secret scanning, push protection, private vulnerability reporting or CodeQL entries (#7, #8, #9 and the `security_and_analysis` part of #1). They're replaced by one `unavailable` line.
- When `has_governance` is false (private repos on the free plan): no ruleset (#10) and no `release` environment (#12, #13). The requirements file says "rulesets on private repos need GitHub Pro" and "environments on private repos need GitHub Pro".

That leaves #1 to #6, #11 (if `publishes`), #14, #15 and #16 for a free private repo. Of those, `GITHUB_TOKEN` can read only #1 (partly), #15, and #16 when the template is public. The Administration and Secrets endpoints have no plan condition in the docs above, and they need the same credential on every plan.

Plan and visibility affect the credential and the schedule in these ways:

- **Template repo (#16).** When the template repo is private, the token has to reach a second repo. A fine-grained PAT "is limited to access resources owned by a single user or organization" ([Managing your personal access tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)). If the template and the generated repo have different owners, one fine-grained PAT can't cover both. A GitHub App would need an installation on each owner. If the check can't read the template repo, it reports `?` for `TEMPLATE_READ_TOKEN`, not drift.
- **Scheduled workflows.** "In a public repository, scheduled workflows are automatically disabled when no repository activity has occurred in 60 days", and they "only run on the default branch" ([Events that trigger workflows: schedule](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)). The weekly template update check is subject to the same rule.
- **Organizations** can block fine-grained or classic PATs from org resources, and can require approval for fine-grained PATs ([Setting a PAT policy for your organization](https://docs.github.com/en/organizations/managing-programmatic-access-to-your-organization/setting-a-personal-access-token-policy-for-your-organization)). Personal-account repos have no such policy.

## Lifetime and rotation

| Credential | Lifetime | Rotation and other limits | Stored in the repo as |
|---|---|---|---|
| Default `GITHUB_TOKEN` | Created per job; "expires when the job finishes or after its effective maximum lifetime" (6 h on GitHub-hosted runners, refreshable up to 24 h on self-hosted runners) ([GITHUB_TOKEN](https://docs.github.com/en/actions/concepts/security/github_token)) | None. 1,000 requests/hour per repository ([Rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)) | nothing (not a secret requirement) |
| Fine-grained PAT | Set at creation. The `expires_in` parameter takes 1 to 366 days or `none`, with a default of 30. "Infinite lifetimes are allowed but may be blocked by a maximum lifetime policy" set by an org or enterprise. GitHub "automatically removes personal access tokens that haven't been used in a year" ([Managing your personal access tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)) | Manual: create a new token and `gh secret set` it again. It's tied to the user and "will become inactive if the user loses access to the resource". Limit of 50 fine-grained PATs per user. 5,000 requests/hour (the user's limit, shared) | one Actions secret |
| GitHub App installation token | "The installation access token will expire after 1 hour" ([Generating an installation access token](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-an-installation-access-token-for-a-github-app)). A workflow mints one per run with `actions/create-github-app-token` ([GitHub App in a workflow](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/making-authenticated-api-requests-with-a-github-app-in-a-github-actions-workflow)) | The long-lived credential is the app's private key: "Private keys do not expire and instead need to be manually revoked". An app can have up to 25 keys, so a key can be rotated without downtime ([Managing private keys](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/managing-private-keys-for-github-apps)). Not tied to a user. 5,000 requests/hour minimum per installation | a private-key secret plus a client-ID variable, and the app must be registered and installed |

Precedent in the template (`includes/secrets.jinja`): both existing Actions-secret PATs are fine-grained with rotation "≤ 1 year". `RELEASE_PLEASE_TOKEN` has contents and pull requests read/write on this repo. `TEMPLATE_READ_TOKEN` has contents:read on the template repo. A new credential for the check would be a new entry there and in `SETUP.md` (ADR 0003).

## Open points not settled by the docs

- **Not verified live** for any token type: whether a read-only fine-grained PAT or App token gets the eight merge fields of #1, and whether it gets `security_and_analysis`. The docs describe these in role terms ("admin permissions", "`contents:read` and `contents:write`"), not in token-permission terms. A recorded response from a scoped token would settle it.
- **#5's 404.** GitHub answers 404 when vulnerability alerts are off. Whether a token without Administration gets 403 or 404 here isn't documented. If it gets 404, the check would report false drift ("missing") instead of `?`.
- The `X-Accepted-GitHub-Permissions` response header names the permission an endpoint needs ([Troubleshooting the REST API](https://docs.github.com/en/rest/using-the-rest-api/troubleshooting-the-rest-api#resource-not-accessible)). It was absent from the successful reads made with the maintainer's own `gh` login on 2026-11-28, which were read-only GETs against this repo. A real scoped token would confirm the rows above.
