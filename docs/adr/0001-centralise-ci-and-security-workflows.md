---
status: accepted
---

# Centralise CI and security workflows; keep the rest copied

Generated repos call CI and security as reusable workflows from a public central workflow repo, `ZeleMate/workflows`, pinned to the full SHA of a central release tag (tag as a same-line comment). Every other workflow stays a copied workflow, and update policy stays per-repo Dependabot. CI and security churn most (toolchain, linter and scanner bumps) and are the likeliest to conflict in `copier update`. Centralising them turns those fixes into one-line pin bumps that Dependabot opens and automerges. The repo is public because a private one can't serve public callers. It isn't named `.github`, because that repo's community-health defaults would apply to every repo on the account.

The layout to build is in [docs/specs/central-workflows.md](../specs/central-workflows.md).

## Considered Options

- **Keep everything copied.** One versioned thing and no public repo, but every CI fix means a hand-run `copier update` in each repo.
- **Centralise everything that can move.** Rejected for the workflows listed under Consequences.
- **A shared Renovate preset for update policy.** It gives one place to change policy, built-in automerge and a dashboard. Dependabot already has grouping and cooldown, policy changes are rare enough to travel through `copier update`, and a short copied workflow gives Dependabot automerge. Renovate would add a second bot and a public preset repo for little gain. This part is cheap to reverse.

## Consequences

- **Release stays copied.** PyPI trusted publishing can't run from a reusable workflow, and npm's is untested from one. A release split across two repos is the hardest thing to debug, and it is the workflow where a mistake costs most.
- **Claude review, evals and the template-update check stay copied.** They are small, tied to the repo's own files (`REVIEW.md`, `evals/run.py`, its template version), or easier to audit in place.
- **Dependabot automerge is a copied workflow.** It holds write permissions, so its trust boundary stays where it can be read. It merges non-major updates only after the merge gate is green.
- **The merge gate stays in the caller workflow.** It waits on the central CI calls plus any local jobs, so a repo with a stack the central repo doesn't support can add its own job without a second required check. A stack that recurs gets promoted to a template language.
- **No merge-gate job may need a secret.** Runs triggered by Dependabot get no Actions secrets, so a secret-dependent job would block every automerge. SonarQube Cloud stays on its GitHub App for this reason.
- **Two release trains.** The template and the central repo are versioned separately. Dependabot moves callers through non-major central releases, and majors arrive only through a template release. actionlint can't type-check inputs to central workflows, so a wrong input fails when the run starts, not at lint time.
