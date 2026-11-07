# Can a central reusable workflow check itself out at its pinned SHA?

Research for [ZeleMate/repo-template#12](https://github.com/ZeleMate/repo-template/issues/12). Researched 2026-11-07, using primary sources only: GitHub Docs (the `github/docs` source on `main`), the GitHub Changelog, and the `actions/checkout` and `actions/toolkit` source.

**Setup in question:** a public repo, `ZeleMate/workflows`, hosts reusable workflows. Generated repos (public and private, all owned by the personal account ZeleMate) call them with
`uses: ZeleMate/workflows/.github/workflows/<name>.yml@<sha>  # vX.Y.Z`.
The called workflow should `actions/checkout` its own repo at that SHA, then run tools (semgrep, diff-cover, pre-commit) from a hash-locked `uv.lock` kept in the central repo.

## 1. OIDC claims `job_workflow_ref` / `job_workflow_sha`

- The OIDC token reference defines the two claims. `job_workflow_ref`: "For jobs using a reusable workflow, the ref path to the reusable workflow." `job_workflow_sha`: "For jobs using a reusable workflow, the commit SHA for the reusable workflow file." ([OIDC reference](https://docs.github.com/en/actions/reference/security/oidc), claims table)
- Inside a called workflow, the token's standard claims (`workflow`, `ref`, `workflow_ref`, ...) describe the **caller**. `job_workflow_ref` describes the **called** workflow. The example token shows `"job_workflow_ref": "octo-org/octo-automation/.github/workflows/oidc.yml@refs/heads/main"`. ([OIDC with reusable workflows](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-with-reusable-workflows)) The same page shows a SHA-pinned ref used in a trust filter, `job_workflow_ref:octo-org/octo-automation/.github/workflows/deployment.yml@10040c56...`. So with a SHA pin, the part after `@` is the SHA as written.
- **Permission needed.** "Without `id-token: write`, the OIDC JWT ID token cannot be requested." The setting "only enables fetching and setting the OIDC token; it does not grant write access to other resources." ([OIDC reference](https://docs.github.com/en/actions/reference/security/oidc), "Workflow permissions for the requesting the OIDC token") The toolkit's `getIDToken` throws if `ACTIONS_ID_TOKEN_REQUEST_TOKEN` or `ACTIONS_ID_TOKEN_REQUEST_URL` is missing; the runner only sets these when the permission is granted. ([actions/toolkit `packages/core/src/oidc-utils.ts`](https://github.com/actions/toolkit/blob/main/packages/core/src/oidc-utils.ts))
- **Who grants it.** A called workflow can only keep or reduce the `GITHUB_TOKEN` permissions the caller passes, never raise them. If the calling job sets no `permissions`, the called workflow gets the default permissions. ([Reusing workflow configurations](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations)) The default token permissions do not include `id-token: write`, so every caller would have to grant it. For reusable workflows owned by the same user or org, "the OIDC token generated in the reusable workflow is accessible from the caller's context". ([OIDC reference](https://docs.github.com/en/actions/reference/security/oidc), "Reusable workflows")
- **Security implication.** `id-token: write` lets any step in that job mint a signed JWT that asserts the caller repo's identity, with an audience the step chooses. Write access to GitHub resources does not come with it. The risk is that any cloud or Vault trust policy keyed on those claims would accept the token. With no OIDC trust anywhere this risk is small, but it is still an extra capability given to third-party tool code (semgrep, pre-commit hooks) running in the job, used only to read back a string. This is no longer needed (see section 2).

## 2. Expression contexts

- **`github.*` is the caller's.** The reference says it directly: "When a reusable workflow is triggered by a caller workflow, the `github` context is always associated with the caller workflow." ([Reusing workflow configurations](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations), "Behavior of reusable workflows") So `github.workflow_ref` ("The ref path to the workflow") and `github.workflow_sha` ("The commit SHA for the workflow file") hold the **caller's** values. This **confirms** the reports in pinpredict/.github PRs #21 and #22. No `github.job_workflow_sha` context property is documented.
- **The newer `job.workflow_*` properties are the called workflow's.** The [contexts reference](https://docs.github.com/en/actions/reference/workflows-and-actions/contexts#job-context) defines:
  - `job.workflow_ref`: "The full ref of the workflow file that defines the current job." For jobs in a reusable workflow, "this refers to the reusable workflow file."
  - `job.workflow_sha`: "The commit SHA of the workflow file that defines the current job."
  - `job.workflow_repository`: "The `owner/repo` of the repository containing the workflow file that defines the current job."
  - `job.workflow_file_path`: the file path relative to the repo root.
  - None of these are available on GitHub Enterprise Server. That does not matter for github.com.
- The same page contains an official example of exactly this pattern. It "uses `job.workflow_repository` and `job.workflow_sha` to check out its own source code, rather than the caller's repository":

  ```yaml
  - uses: actions/checkout@v6
    with:
      repository: ${{ job.workflow_repository }}
      ref: ${{ job.workflow_sha }}
  ```
- Announced in the [GitHub Changelog, 2026-09-03 ("GitHub Actions: Early September 2026 updates")](https://github.blog/changelog/2026-09-03-github-actions-early-september-2026-updates/): "Reusable workflows can now determine their own source identity at runtime with four new job context properties". It notes that they "reflect the workflow that defines the current job" and differ from `github.workflow_*` only in reusable workflows. The docs commit adding them is `94ac73455f` in `github/docs` ("add job workflow identity context properties (ADR 10024)").
- No permissions are needed. These are plain expression contexts, and the docs mention no token or `id-token` requirement for them.

## 3. Checking out the public central repo from a private caller with `GITHUB_TOKEN`

- `actions/checkout` takes `repository` (default `${{ github.repository }}`), `ref` ("The branch, tag or SHA to checkout"), and `token` (default `${{ github.token }}`). ([actions/checkout `action.yml`](https://github.com/actions/checkout/blob/main/action.yml)) A full SHA as `ref` is fetched directly (`src/ref-helper.ts`, "SHA only" branch).
- `GITHUB_TOKEN` is an installation token whose "permissions are limited to the repository that contains your workflow". ([GITHUB_TOKEN concepts](https://docs.github.com/en/actions/concepts/security/github_token)) The checkout README says a different repo needs your own PAT only when it is private: "`${{ github.token }}` is scoped to the current repository, so if you want to checkout a different repository that is private you will need to provide your own PAT". Its "Checkout multiple repos" examples check out `my-org/my-tools` with no token. They add the warning: "If your secondary repository is private or internal you will need to add the option noted in Checkout multiple repos (private)". ([actions/checkout README](https://github.com/actions/checkout/blob/main/README.md))
- So for a **public** `ZeleMate/workflows`, the default token works from both private and public callers, and no extra secret is needed. The token sent is the caller's. Public content is readable anyway, so it is just a credential that is not needed. Setting `persist-credentials: false` on this checkout is reasonable, so the caller's token is not left in `.git/config` of a tree whose tools will execute.
- Calling the workflow: a private caller may use workflows in `private` and `public` repos, and a public caller only in `public` ones. ([Reusing workflow configurations](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations), "Access to reusable workflows") The caller's Actions permissions must allow the reusable workflow. With a public central repo, no "Access" setting on the central repo is required. That setting is needed only for private or internal called repos.

## 4. Alternative: pass the ref as an input

- Pattern: `on: workflow_call: inputs: ref:` in the central workflow, and the caller sets `with: ref: <same sha>`. ([Reuse workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows), inputs)
- Drawbacks:
  - The pin is duplicated in two places that can drift. Dependabot or Renovate bump the `uses:` SHA but not the `with:` value, so the workflow at SHA *A* silently runs tools from lock *B*.
  - A caller can pass any ref, so the invariant "workflow and its tool lock come from one commit" is not enforced.
  - It is more boilerplate in every generated repo.
- Other options: the OIDC route (section 1) needs `id-token: write` in every caller. Hard-coding a version in the central workflow is self-referential and cannot carry its own SHA. `job.workflow_sha` makes all of them unnecessary.

## Caveats and things not verified

- Nothing was run. In particular, I did not empirically check that `job.workflow_sha` equals the caller's pinned SHA when called as `@<sha>`. The docs define it as the commit SHA of the workflow file that defines the job, which for a SHA pin should be that SHA.
- Not verified: the behavior of `job.workflow_*` in **nested** reusable workflows. Per the definition it should be the innermost workflow defining the job.
- Not verified: whether `job.*` is accepted in every key (for example `jobs.<id>.if`, `runs-on`). The official example uses it in a step's `with:`, which is where it is needed.
- Not checked against the pinpredict PR runs themselves. Only the docs statement that `github.*` belongs to the caller was checked.
- The feature is new (2026-09-03) and not available on GHES. It should be re-checked against the docs if behavior looks off.

## Answer

**Yes.** Since the 2026-09-03 changelog, a called reusable workflow can read its own identity from the `job` context: `job.workflow_repository`, `job.workflow_sha` and `job.workflow_ref` describe the reusable workflow file, not the caller. The docs show the exact self-checkout pattern: `actions/checkout` with `repository: ${{ job.workflow_repository }}` and `ref: ${{ job.workflow_sha }}`. `github.workflow_ref` / `github.workflow_sha` are the caller's ("the `github` context is always associated with the caller workflow"), which confirms the pinpredict #21/#22 reports.

Conditions:
- No `id-token: write` is needed. The OIDC `job_workflow_ref`/`job_workflow_sha` claims also carry this, but need `id-token: write` granted by every caller, so avoid that route.
- No extra secret is needed: because `ZeleMate/workflows` is public, the default `GITHUB_TOKEN` (`contents: read`) can check it out from private and public callers. Use `persist-credentials: false`.
- Not available on GHES (irrelevant here).

Passing the ref as an input works but duplicates the pin and can drift.

Not verified: no live run confirming `job.workflow_sha` equals the `@<sha>` pin; nested-workflow behavior; use of `job.*` outside step inputs.
