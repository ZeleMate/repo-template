# Can one central workflow repo serve public and private repos?

Research for [#3](https://github.com/ZeleMate/repo-template/issues/3) (child of map issue #2). Researched 2026-11-03 against GitHub Docs (`docs.github.com`, github.com "fpt" version, which covers the Free, Pro and Team plans) and the GitHub changelog.

**Setting:** ZeleMate is a personal account (not an org), on Free or Pro. It owns a mix of public and private repos. The question is whether repos generated from this template can all call reusable workflows (`jobs.<id>.uses: ZeleMate/<central>/.github/workflows/x.yml@ref`) from **one** central repo.

## Short answer

- **Public central repo: yes, it serves every caller.** Public repos and private repos can both call a reusable workflow stored in a public repo. No Access setting is needed.
- **Private central repo: private callers only.** With **Settings → Actions → General → Access → "Accessible from repositories owned by 'ZeleMate' user"**, other *private* repos owned by ZeleMate can call it. Public callers can never call it. The docs say "Access is allowed only from private repositories".
- **Free vs Pro: no difference for reachability.** Neither the access rules nor the sharing setting has a plan gate. Plan only matters for what the called workflow can *use*: environment secrets and variables, plus some protection rules, in **private** caller repos (see below).
- So "one central repo for everything" means the central repo must be **public**. The alternative is two central repos (one public for public callers, one private for private callers), or vendoring workflows into each generated repo.

## Access rules (primary source)

[Reusing workflow configurations → Access to reusable workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations#access-to-reusable-workflows). A reusable workflow can be used when any of the following is true:

- Both workflows are in the same repository.
- The called workflow is stored in a public repository. (The extra clause "and your organization allows you to use public reusable workflows" applies to orgs; a personal account has no such policy.)
- The called workflow is stored in a private repository and that repository's settings allow it to be accessed.

The page's visibility table:

| Caller repository | Accessible workflow repositories |
|---|---|
| `private` | `private` and `public` |
| `public` | `public` |

The page also adds two requirements:

- The **caller's** Actions permissions must allow actions and reusable workflows. With the default "Allow all actions and reusable workflows" this is satisfied. If a generated repo restricts to "select actions", the central repo's workflows must be on its allow list. [Managing GitHub Actions settings](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository#allowing-select-actions-and-reusable-workflows-to-run)
- For a private called repo, its **Access** policy must explicitly allow the callers.

## The Access setting for a private repo on a personal account

Source: [Managing GitHub Actions settings → Allowing access to components in a private repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository#allowing-access-to-components-in-a-private-repository) and [Share across private repositories](https://docs.github.com/en/actions/how-tos/reuse-automations/share-across-private-repositories).

- Location: private repo → **Settings → Actions → General → Access** (bottom of the page).
- Options on a user-owned repo:
  - **Not accessible**: this is the default.
  - **Accessible from repositories owned by 'USER NAME' user**: workflows in other repos owned by the same user can use its actions and reusable workflows. Per the docs, "Access is allowed only from private repositories."
- It can also be set via REST: `PUT /repos/{owner}/{repo}/actions/permissions/access` with `access_level` (`none` / `user` / `organization`). [REST: Actions permissions](https://docs.github.com/en/rest/actions/permissions#set-the-level-of-access-for-workflows-outside-of-the-repository)
- History: the [2022-12-14 changelog](https://github.blog/changelog/2022-12-14-github-actions-sharing-actions-and-reusable-workflows-from-private-repositories-is-now-ga/) made this generally available "within the same organization, user account, or enterprise". It names no plan restriction.
- Caveats from the how-to:
  - Outside collaborators on a calling repo can indirectly access the shared private repo, including viewing logs of runs that use it.
  - The runner fetches the shared code with a read-only installation token that expires after one hour.
- **Consequence for the template:** if a generated private repo is later made public, its calls into a private central repo stop working. GitHub says this applies to any nested call: "A workflow that contains nested reusable workflows will fail if any of the nested workflows is inaccessible to the initial caller workflow."

## Limits across the boundary

All from [Reusing workflow configurations](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations) unless noted. The github.com values apply to Free and Pro alike.

### Nesting and count

- Up to **10 levels**: the caller plus up to 9 reusable levels.
- Up to **50 unique reusable workflows** per top-level workflow file, counting nested trees.
- Loops are not allowed. [Reuse workflows → Nesting](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows#nesting-reusable-workflows)
- **Every** workflow in the chain must be accessible to the *top-level caller*. So a public caller → public central → private helper chain fails.

### `env` and `GITHUB_ENV`

- Workflow-level `env` in the caller is **not** propagated to the called workflow, and vice versa. Use `inputs` and `outputs`, or `vars`.
- `GITHUB_ENV` can't pass values into the caller's steps.

### Secrets

- The caller passes secrets explicitly, either by name under `secrets:` or with `secrets: inherit`.
- Secrets reach only the **directly** called workflow. Each nesting level must pass them on again. [Reuse workflows → Nesting](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows#nesting-reusable-workflows)
- `secrets: inherit` passes "all secrets the calling workflow has access to, namely organization, repository, and environment secrets". [Workflow syntax → `jobs.<job_id>.secrets.inherit`](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idsecretsinherit)
- The docs scope `inherit` to "across repositories within the same organization, or across organizations within the same enterprise". **They don't mention personal accounts.** **UNVERIFIED:** whether `secrets: inherit` works from a ZeleMate repo into another ZeleMate repo. It probably does, since the docs describe it as same-owner scoping, but this isn't documented for user accounts. Passing secrets by name is the documented-safe fallback. A one-off test with two throwaway repos would settle it.
- The secret values come from the **caller** repo, not the central repo. The central repo needs no secrets of its own.

### `permissions` (`GITHUB_TOKEN`)

- `permissions` is one of the few keywords allowed on the calling job.
- If the calling job omits it, the called workflow gets the caller repo's default `GITHUB_TOKEN` permissions.
- The called workflow can only **downgrade**, never elevate, what the caller grants. In nested chains each level must be the same or more restrictive.
- The token is the caller repo's token. Hosted runner billing and assignment are also evaluated "using only the caller's context".

### Environments

- The calling job **can't** use `environment:`. Instead, put `environment:` on the job *inside* the reusable workflow. The caller must still pass the secret, either with `inherit` or by name. [Reuse workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows#passing-inputs-and-secrets-to-a-reusable-workflow)
- An environment secret wins over a repo secret of the same name.
- If an environment secret isn't passed, it silently resolves to an empty string. Use `required: true` in `on.workflow_call.secrets` to fail instead.
- **Inferred, not stated verbatim:** the environment is resolved in the caller repo, since the run, token and secrets all belong to the caller. So each generated repo must define the environment itself.
- Plan gates on environments, per [Deployments and environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments). These apply to the **caller** repo, since that's where the environment lives:

| Feature | Public repo (Free & Pro) | Private repo, Free | Private repo, Pro |
|---|---|---|---|
| Environment secrets | yes | **no** | yes |
| Environment variables | yes | **no** (docs name only Pro/Team) | yes |
| Deployment branch/tag rules | yes | **no** (docs name only Pro/Team) | yes |
| Required reviewers, wait timers, admin bypass, custom protection rules | yes | no | **no** |

**UNVERIFIED:** the docs don't say what happens on Free when a reusable workflow job targets an environment in a private caller repo. Possibly the environment is ignored, or possibly the job errors. Either way the secrets won't be there.

## Implications for the template (for #2 / #7)

1. **Simplest design that serves both visibilities:** one **public** central workflow repo. This works on both Free and Pro with zero access configuration. The cost is that the workflow code is public. Secrets stay in each caller.
2. **Private central repo:** it must have Access set to "owned by user". It serves only private generated repos. Public generated repos would need either a public copy or vendored workflows.
3. **Avoid relying on `secrets: inherit`** in generated callers until it's tested on a user account. Pass named secrets instead.
4. **Avoid environment-based secrets in private generated repos** if the account is on Free.

## Sources

- https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations
- https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows
- https://docs.github.com/en/actions/how-tos/reuse-automations/share-across-private-repositories
- https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository
- https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idsecretsinherit
- https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments
- https://docs.github.com/en/rest/actions/permissions
- https://github.blog/changelog/2022-12-14-github-actions-sharing-actions-and-reusable-workflows-from-private-repositories-is-now-ga/
- Docs source checked at `github/docs` `main`: `content/actions/reference/workflows-and-actions/reusing-workflow-configurations.md`, `content/actions/how-tos/reuse-automations/reuse-workflows.md`, `content/actions/reference/workflows-and-actions/workflow-syntax.md`
