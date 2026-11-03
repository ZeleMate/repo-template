# repo-template

A Copier template that stamps a production baseline (CI, security scanning, releases, AI review, agent config) into new repos, and keeps those repos current through `copier update`.

## Language

**Template**:
The Copier source in this repo (`copier.yml` plus `template/`), released as semver tags.
_Avoid_: starter, scaffold, boilerplate

**Generated repo**:
A repo stamped from the template, carrying a `.copier-answers.yml` that ties it back to a template version.
_Avoid_: child repo, downstream repo, project

**Caller workflow**:
A short workflow in a generated repo whose only job is to invoke a central workflow with that repo's inputs.
_Avoid_: thin caller, stub workflow, wrapper

**Central workflow repo**:
A single repo outside the template that hosts reusable workflows (and shared policy such as an update preset) which generated repos call by reference.
_Avoid_: `.github` repo (that name is one possible implementation), shared repo

**Copied workflow**:
A workflow the template writes into a generated repo in full, owned and edited there, and refreshed only through `copier update`.
_Avoid_: local workflow, vendored workflow

**Merge gate**:
The single required status check that decides whether a generated repo's change is green; it belongs to the caller workflow, not the central workflow repo.
_Avoid_: ci-ok (that is its job name), required check, status gate
