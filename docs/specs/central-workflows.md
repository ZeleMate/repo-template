# Spec: central workflows

The target layout for [ADR 0001](../adr/0001-centralise-ci-and-security-workflows.md). Generated repos call CI and security from a central workflow repo, and every other workflow stays copied. Terms (template, generated repo, caller workflow, central workflow repo, central release, copied workflow, merge gate) are defined in [CONTEXT.md](../../CONTEXT.md).

This spec comes from the map [Centralise CI and update policy, or keep copying it?](https://github.com/ZeleMate/repo-template/issues/2). Each section names the closed ticket it comes from. The template is changed once, in place. Two generated repos already exist and are covered in section 10.

Out of scope: a settings drift checker for generated repos and Claude Code guard hooks.

**Status (2026-11-11):** built and live. `ZeleMate/workflows` is public and tagged `v1.0.0`. See the build checklist at the end for what the live test did and did not cover.

## 1. The central workflow repo

_From [Can one central workflow repo serve public and private repos?](https://github.com/ZeleMate/repo-template/issues/3) and [Centralise the workflows, and which ones?](https://github.com/ZeleMate/repo-template/issues/7)._

- **Repo:** `ZeleMate/workflows`, **public**, a single repo. A public repo serves public and private callers with no Actions access setting. A private one would serve private callers only, and a repo flipped to public would break.
- **Not `.github`:** that repo's community-health files would become defaults for every repo on the account.
- **Holds no secrets.** Secrets, `GITHUB_TOKEN` and billing all come from the caller repo.
- **Limits to respect:** at most 10 nesting levels and 50 unique reusable workflows per caller file. Caller `env` doesn't reach the called workflow. A called workflow can only lower `GITHUB_TOKEN` permissions, never raise them. A calling job can't set `environment:`.

## 2. Which workflows move, and where they live

_From [Centralise the workflows, and which ones?](https://github.com/ZeleMate/repo-template/issues/7), [How do caller workflows pass settings to central CI?](https://github.com/ZeleMate/repo-template/issues/10) (with its correction) and [Do AI reviewers stall Dependabot automerge?](https://github.com/ZeleMate/repo-template/issues/14)._

One reusable workflow per concern, all under `ZeleMate/workflows/.github/workflows/`, each triggered by `on: workflow_call`:

| Central workflow | Replaces (in `template/.github/workflows/`) |
|---|---|
| `repo-lint.yml` | `ci.yml.jinja` job `repo-lint` (pre-commit) |
| `python.yml` | `ci.yml.jinja` job `python` (version matrix, type check, diff-cover) |
| `typescript.yml` | `ci.yml.jinja` job `typescript` (incl. diff-cover) |
| `rust.yml` | `ci.yml.jinja` job `rust` (incl. `cargo deny`) |
| `security.yml` | `security.yml.jinja` jobs `sast`, `dependencies`, `secrets` |

- **No `sonarqube.yml`.** SonarQube Cloud stays on its GitHub App (Automatic Analysis), which needs no CI job and no secret. Its check is not required. Coverage is not uploaded to SonarQube.
- **Code scanning** in public repos stays CodeQL default setup (enabled by `bootstrap-github.sh`), not a job.

## 3. Caller workflows in the generated repo

_From [Centralise the workflows, and which ones?](https://github.com/ZeleMate/repo-template/issues/7) and [How do caller workflows pass settings to central CI?](https://github.com/ZeleMate/repo-template/issues/10)._

- **`ci.yml`** (still `ci.yml.jinja` in the template): one job per concern the repo uses, each `uses: ZeleMate/workflows/.github/workflows/<concern>.yml@<sha> # vX.Y.Z`, plus any local jobs and the merge gate. Every central call in the file pins the **same** SHA.
- **`security.yml`** becomes a caller too. It keeps the weekly `schedule` and `workflow_dispatch` triggers, and calls the central `security.yml`. `ci.yml` calls the central `security.yml` directly, so it runs on every PR and push and feeds the merge gate.
- **Permissions:** the caller sets `permissions: {}` at the top and grants each calling job only what the central job needs (today `contents: read`). The central workflow can only lower that.

## 4. The interface: typed inputs, named secrets, no secrets on the merge gate

_From [How do caller workflows pass settings to central CI?](https://github.com/ZeleMate/repo-template/issues/10) (with its correction), [Can one central workflow repo serve public and private repos?](https://github.com/ZeleMate/repo-template/issues/3) and [Do AI reviewers stall Dependabot automerge?](https://github.com/ZeleMate/repo-template/issues/14)._

**Inputs.** Typed `workflow_call` inputs. Copier writes the values into the caller with Jinja. No single JSON input, and central workflows never read `.copier-answers.yml`. GitHub rejects missing or unknown inputs when the run starts. That covers the gap that actionlint doesn't type-check inputs across repos.

**Derive what the repo already records.** Where a version is already in a repo file, the central workflow reads that file and takes no input:

| Setting (Copier answer today) | Source after the move |
|---|---|
| `node_version` | `node-version` input that Copier writes. `package.json` `engines` is the fallback when the input is empty (see the correction below) |
| `rust_toolchain` | `rust-toolchain.toml` |
| `python_version` | `python-versions` input: a JSON list of minor versions that Copier writes, so no job computes the matrix |
| `python_type_checker` | `type-checker` input (`pyright` or `mypy`) |
| `py_dir`, `ts_dir`, `rs_dir` | a working-directory input on each language workflow |
| `ts_linter`, `rust_msrv` | no input: CI never reads them |

Changing an input name later costs a central major release (section 7). The names as built:

| Central workflow | Inputs |
|---|---|
| `repo-lint.yml` | `skip-hooks`, `ci-workflow`, `merge-gate-job` (all optional) |
| `python.yml` | `python-versions` (required), `type-checker`, `working-directory` |
| `typescript.yml` | `node-version`, `working-directory` |
| `rust.yml` | `working-directory` |
| `security.yml` | `sast` (boolean, Copier writes `true` for private repos) |

**Correction, Node version.** The earlier plan read the Node version from `package.json` `engines` and took no input. The template writes `engines` as a range (`>=26`), and `setup-node` resolves a range to the newest release that satisfies it, so CI would drift onto a non-LTS major. The caller now passes `node-version`, and `engines` is only the fallback.

**Secrets.**
- Named secrets only (`secrets: NAME: ${{ secrets.NAME }}`). Never `secrets: inherit`, which is unverified for personal accounts.
- **No job that the merge gate depends on may need a secret.** Runs triggered by Dependabot get only Dependabot secrets, so a secret-dependent job would turn the merge gate red on every Dependabot PR and stall automerge. Today no CI or security job needs one. The named-secrets rule applies to any future secret outside the merge gate.

## 5. The merge gate

_From [Centralise the workflows, and which ones?](https://github.com/ZeleMate/repo-template/issues/7) and [How do caller workflows pass settings to central CI?](https://github.com/ZeleMate/repo-template/issues/10)._

- `ci-ok` stays in the caller `ci.yml`, keeps its job name (the ruleset requires it) and stays the single required status check.
- It `needs:` **every** job in the caller: central calls and local jobs alike. It fails if any of them failed or was cancelled, as today.
- A repo whose stack the central repo doesn't support adds a local job and lists it in `ci-ok.needs`. A stack that keeps coming back gets promoted to a template language: a Copier choice, a central workflow, and a pin bump.
- **Central `repo-lint.yml` checks this:** it fails if any job in the caller `ci.yml` is missing from `ci-ok.needs`.

## 6. Pinning and self-checkout

_From [How should caller workflows pin central workflows?](https://github.com/ZeleMate/repo-template/issues/5) and [Can a central workflow check itself out at its pinned SHA?](https://github.com/ZeleMate/repo-template/issues/12)._

**Pin format.** Full commit SHA of a central release tag, with the tag as a same-line comment:

```yaml
uses: ZeleMate/workflows/.github/workflows/python.yml@<40-char sha> # v1.4.0
```

- The central repo cuts semver tags, ideally as immutable releases.
- Dependabot bumps the SHA and the comment together. zizmor's `unpinned-uses` (default `hash-pin`) flags `@v1` or `@main` as High, so a tag or branch ref is not acceptable. GitHub's "require full-length SHA" policy exempts reusable-workflow refs, but every action *inside* a central workflow must still be SHA-pinned.
- Workflow lockfiles (`actions.lock`) don't cover `jobs.<id>.uses`, so the SHA pin is the only lock.

**Self-checkout.** A central workflow that needs its own files (tool lock, config) checks itself out at the SHA it was called at:

```yaml
- uses: actions/checkout@<sha> # vX
  with:
    repository: ${{ job.workflow_repository }}
    ref: ${{ job.workflow_sha }}
    path: .central
    persist-credentials: false
```

- No `id-token: write` and no secret are needed. The repo is public, so the default `GITHUB_TOKEN` can check it out from any caller. Don't use the OIDC `job_workflow_*` claims (every caller would have to grant `id-token: write`) or `github.workflow_sha` (that's the caller's). Don't pass the ref as an input either, because it duplicates the pin and can drift.
- **CI-tools lock moves.** The central repo keeps its own hash-locked `tools/uv.lock` for `semgrep`, `diff-cover`, `pre-commit` and `pyyaml` (for the merge-gate check), and runs them from the self-checkout. The generated repo's `.github/tools` keeps only `copier`, for `template-update.yml`. `diff-cover` is no longer a dev dependency of the Python project.
- **The self-checkout leaves the workspace.** `actions/checkout` can only write under the workspace, so the workflow moves `.central` to `$RUNNER_TEMP/central` straight away. Otherwise Semgrep and OSV-Scanner would scan the central repo's files as if they were the caller's.
- **Verified on the first build (2026-11-11):** a live run confirmed that `job.workflow_sha` equals the `@<sha>` pin. Behaviour in nested reusable workflows is still untested.

## 7. Release coupling: central releases and template releases

_From [How do central workflow releases relate to template releases?](https://github.com/ZeleMate/repo-template/issues/13) and [How should caller workflows pin central workflows?](https://github.com/ZeleMate/repo-template/issues/5)._

**What counts as a major central release:** an input removed or renamed, a new required input or a changed secret, **or** anything that can turn a previously green caller red without a caller edit (a stricter default rule, a raised minimum version, a new check that's on by default).

**Who moves the pin in a generated repo:**
- **Minor and patch releases: Dependabot.** They arrive as PRs and automerge once the merge gate is green (section 8).
- **Majors: only a template release**, applied with `copier update`, together with the caller edits they need. Dependabot ignores majors of `ZeleMate/workflows`.
- **No backports.** Fixes go forward only. A repo on an old major moves forward through the template update that `template-update.yml` already reports.

**Dependabot config** (`dependabot.yml.jinja`, `github-actions` ecosystem):
- A separate `central-workflows` group for `ZeleMate/workflows`, with **no cooldown** and `semver-major` ignored.
- The existing `actions` group excludes `ZeleMate/workflows` and keeps its 7-day cooldown for third-party actions, so a red central bump doesn't block unrelated updates.

**The template's own pin:**
- It moves only when the template needs it (a new major, or a template change that writes an input only a newer minor supports), and always to the newest central release at that moment. Most template releases leave the pin lines alone, so `copier update` merges them cleanly.
- If a pin line conflicts in `copier update`, keep the higher version. Never go backwards.
- Dependabot can't read `.jinja` files, so a new script in `scripts/` turns a central tag into its SHA and rewrites every pin line in `ci.yml.jinja` and `security.yml.jinja`.
- A template check fails if the central pins don't all share one SHA and one tag comment.

**Notifier:** `template-update.yml` doesn't change. It checks only the template version, and majors reach generated repos through template releases.

## 8. The copied Dependabot automerge workflow

_From [Renovate or Dependabot for update policy?](https://github.com/ZeleMate/repo-template/issues/8) and [Do AI reviewers stall Dependabot automerge?](https://github.com/ZeleMate/repo-template/issues/14)._

- **Dependabot stays; no Renovate preset.** `dependabot.yml` keeps its `groups` and `cooldown`. Dependency graph, Dependabot alerts, malware alerts and security updates stay on.
- **New copied workflow** (e.g. `dependabot-automerge.yml`) in each generated repo, not in the central repo, because it holds `contents: write` and `pull-requests: write`. It runs only on Dependabot PRs: `dependabot/fetch-metadata`, then `gh pr merge --auto --squash`. The merge always waits for the merge gate.
- **Rule:** automerge any Dependabot PR whose update type is not major, in every ecosystem (Actions, central workflows, CI-tools lock, app dependencies). A grouped PR counts as its highest update type. Majors stay manual, Actions majors included. Security updates follow the same rule. They skip the cooldown by design, but the merge gate still has to pass.
- **Requires:** auto-merge allowed on the repo, and `ci-ok` as a required check. `bootstrap-github.sh` already sets both.
- **Only where the ruleset exists.** Copier writes the workflow for public repos and for private repos on Pro. A private repo on Free has no ruleset, so nothing would make the merge wait for the merge gate. Those repos merge Dependabot PRs by hand.
- **Reviewers don't stall it.** `claude-review.yml` already skips bot PRs (`user.type != 'Bot'`). Add a comment saying the skip is deliberate. A major update is reviewed by starting `claude-review.yml` by hand with `workflow_dispatch`. `.coderabbit.yaml` already ignores `dependabot[bot]`. `required_review_thread_resolution` stays on for every PR.

## 9. What the template still copies

_From [Centralise the workflows, and which ones?](https://github.com/ZeleMate/repo-template/issues/7), [Does trusted publishing work from a reusable workflow?](https://github.com/ZeleMate/repo-template/issues/4), [Renovate or Dependabot for update policy?](https://github.com/ZeleMate/repo-template/issues/8) and [Can a central workflow check itself out at its pinned SHA?](https://github.com/ZeleMate/repo-template/issues/12)._

| File in the generated repo | Kind | Why it stays |
|---|---|---|
| `ci.yml` | caller workflow + merge gate | Calls central CI. Owns `ci-ok` and any local jobs |
| `security.yml` | caller workflow | Keeps the weekly schedule |
| `release.yml` | copied workflow | PyPI trusted publishing and PEP 740 attestations can't run from a reusable workflow (the PyPI publisher must be the called workflow in the caller repo). npm is unproven from one. A mistake costs most here |
| `claude-review.yml` | copied workflow | Small. Its trust boundary is easier to audit in place. `REVIEW.md` is the real lever |
| `evals.yml` | copied workflow | Tied to the repo's own `evals/run.py` |
| `template-update.yml` | copied workflow | About the repo's own template version |
| `dependabot-automerge.yml` (new, public or Pro only) | copied workflow | Holds write permissions |
| `dependabot.yml` | config | Per-repo update policy, with the new `central-workflows` group |
| `.github/tools/` | CI-tools lock | Now `copier` only |

## 10. Repos generated before the central workflows

_Added 2026-11-10. The spec first assumed no generated repos existed._

Two repos were adopted at template v0.3.0 and updated to v0.4.2: `forge-lab` and `DeepSeek-demo-implementation`. Both kept their own toolchain and rewrote `ci.yml`, so neither uses the template's language jobs:

- **`ci.yml` stays theirs.** The template update that brings the caller workflows will conflict across the whole file. Keep the repo's side. Their stack (Bun, Biome, Lefthook) is one the central repo doesn't support, which section 5 already allows: local jobs, all listed in `ci-ok.needs`.
- **`security.yml` can become a caller.** Both repos call it from `ci.yml` and run it weekly. Replace the local file with the caller, and change the call in `ci.yml` from the local file to the central `security.yml` at the same pin. Each repo keeps its own Gitleaks job or drops it for the central one, but not both.
- **`repo-lint.yml` is optional for them.** Its pre-commit step needs a `.pre-commit-config.yaml`, which both repos replaced with Lefthook. Its merge-gate check is the part worth having. Until the two are split, these repos don't call it.
- **Dependabot:** add the `central-workflows` group and the major-version ignore, as section 7 describes.
- **`.github/tools`** already holds what `template-update.yml` needs. Trimming it to `copier` is safe once nothing else in the repo runs tools from it.

## Build checklist

1. Create public `ZeleMate/workflows` with the five reusable workflows, its own CI and tool lock, and cut `v1.0.0`. **Done:** published and tagged `v1.0.0` at `95244ca`.
2. Rewrite `ci.yml.jinja` and `security.yml.jinja` as caller workflows pinned to that release. **Done**, pinned to `v1.0.0`.
3. Add the `central-workflows` Dependabot group, and exclude `ZeleMate/workflows` from `actions`. **Done.**
4. Add the copied automerge workflow, and the deliberate-skip comment in `claude-review.yml`. **Done.**
5. Trim `.github/tools` to `copier`. **Done.**
6. Add the pin-moving script and the one-SHA template check under `scripts/`. **Done:** `bump-central-pin.sh` and `check-central-pins.sh`; `test-template.sh` runs the check.
7. Generate a test repo, and confirm the merge gate goes green on a normal PR and on a Dependabot PR, and that `job.workflow_sha` matches the pin. **Partly done**, in the private repo `ZeleMate/template-smoke-test` (Python and TypeScript):
   - The merge gate is green on a push and on a normal PR, with changed-line coverage running in both languages.
   - `job.workflow_sha` equals the pin: the self-checkout fetched `95244ca`, the SHA in the caller.
   - **Not covered:** a Dependabot PR and the automerge workflow (the test repo is private on Free, which gets no automerge workflow), and `rust.yml` called from another repo.
