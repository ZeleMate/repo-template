# repo-template

A Copier template that stamps a production baseline (CI, security scanning, releases, AI review, agent config) into new repos, and keeps those repos current through `copier update`.

## Language

**Template**:
The Copier source in this repo (`copier.yml` plus `template/`), released as semver tags.
_Avoid_: starter, scaffold, boilerplate

**Generated repo**:
A repo stamped from the template, carrying a `.copier-answers.yml` that ties it back to a template version.
_Avoid_: child repo, downstream repo, project

**Managed language**:
A language named in the `languages` answer, for which the template writes and updates the toolchain, CI call and release config.
_Avoid_: supported language, stack

**Language profile**:
The facts the template holds about one managed language that more than one generated file needs: its toolchain, lock step, registry, Dependabot ecosystem and the checks a change must pass. Every file that names the language is written from it, and a generated repo carries the profiles of its own languages.
_Avoid_: language config, toolchain settings, stack definition

**Check**:
One command a change must pass in a managed language, run by CI and by the local verifier, and documented for contributors; it may have a fixing form, which is what contributors run.
_Avoid_: dev command, lint step, CI step

**Version floor**:
The oldest version of a managed language that a generated repo supports, taken from its Copier answer; CI tests every minor from it up to the newest known version.
_Avoid_: minimum version, MSRV

**Newest known version**:
The newest release of a managed language that the current template release knows about; it tops the CI version list and moves only with a template release. Only Python and Go have one: a TypeScript repo tests the one Node LTS major it picked, and a Rust repo builds with its own pinned toolchain.
_Avoid_: latest, current

**Baseline repo**:
A generated repo with no managed language; the template gives it security scanning, Dependabot, the merge gate and agent config, and nothing else.
_Avoid_: baseline-only mode, lite repo, minimal repo

**Local CI workflow**:
The reusable workflow `ci-local.yml` in a generated repo, written once by the template and owned by the repo from then on, holding the CI jobs for anything that isn't a managed language.
_Avoid_: custom CI, local jobs, extension workflow

**Caller workflow**:
A short workflow in a generated repo whose only job is to invoke a central workflow with that repo's inputs.
_Avoid_: thin caller, stub workflow, wrapper

**Central workflow repo**:
A single repo outside the template that hosts reusable workflows which generated repos call by reference.
_Avoid_: `.github` repo (that name is one possible implementation), shared repo

**Central release**:
A semver tag of the central workflow repo; a major release is one that can turn a previously green caller workflow red without an edit to it.
_Avoid_: central version, workflow release

**Copied workflow**:
A workflow the template writes into a generated repo in full, owned and edited there, and refreshed only through `copier update`.
_Avoid_: local workflow, vendored workflow

**Merge gate**:
The single required status check that decides whether a generated repo's change is green; it belongs to the caller workflow, not the central workflow repo.
_Avoid_: ci-ok (that is its job name), required check, status gate

**Secret requirement**:
A credential a generated repo needs, with where it is stored, which workflow or tool uses it, when it applies and how often to rotate it.
_Avoid_: secret list, token manifest, required secrets

**Settings requirement**:
A GitHub setting a generated repo needs, with the value bootstrap writes, the value the check expects, and whether its plan and visibility allow it at all.
_Avoid_: desired state, hardened settings, baseline (that is a repo with no managed language)

**Drift**:
Where a generated repo's live GitHub state misses its settings or secret requirements: a setting that re-running bootstrap would overwrite, or a needed secret that isn't set.
_Avoid_: misconfiguration, deviation
