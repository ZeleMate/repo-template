---
status: accepted
---

# Centralise CI and security workflows; keep the rest copied

Generated repos call CI and security as reusable workflows from a public central workflow repo, `ZeleMate/workflows`, pinned to the full SHA of a central release tag (tag as a same-line comment). Every other workflow stays a copied workflow. CI and security churn most (toolchain, linter and scanner bumps) and are the likeliest to conflict in `copier update`; centralising them turns those fixes into one-line pin bumps that Dependabot or Renovate opens automatically. The repo is public because a private one can't serve public callers, and it isn't named `.github` because that repo's community-health defaults would apply to every repo on the account.

## Considered Options

- **Keep everything copied.** One versioned thing, no public repo, but every CI fix means a hand-run `copier update` per repo.
- **Centralise everything that can move.** Rejected for the workflows below.

## Consequences

- **Release stays copied.** PyPI trusted publishing can't run from a reusable workflow, and npm's is untested from one. Splitting a release between two repos is the hardest thing to debug, and it is the workflow where a mistake costs most.
- **Claude review, evals and the template-update check stay copied.** They are small, tied to the repo's own files (`REVIEW.md`, `evals/run.py`, its template version), or easier to audit in place.
- **The merge gate stays in the caller workflow.** It waits on the central CI call plus any local jobs, so a repo with a stack the central repo doesn't support can add its own job without a second required check. A stack that recurs is promoted to a template language.
- **Two release trains.** The template and the central repo version separately, and actionlint can't type-check inputs to central workflows, so a wrong input fails only at run time.
