# Trusted publishing from a reusable workflow

Research for [#4](https://github.com/ZeleMate/repo-template/issues/4) (child of map issue #2). Researched 2026-11-03.

**Question:** if a generated repo's publish job moves into a reusable workflow in a central workflow repo (`central-org/workflows/.github/workflows/publish.yml@v1`, called with `uses:`), do OIDC trusted publishing to PyPI, npm and crates.io, npm provenance, PyPI PEP 740 attestations and GitHub artifact attestations still work? Which workflow identity does each one verify?

## Short answer

| Target | Identity it checks | Cross-repo reusable workflow |
|---|---|---|
| PyPI trusted publishing | **Called** workflow (`job_workflow_ref`), which must also live in the caller repo at the caller's ref | **Does not work** |
| PyPI PEP 740 attestations (PyPA action) | Needs trusted publishing to work | **Does not work** (follows from PyPI) |
| npm trusted publishing | **Caller** workflow filename | **Works, with caveats** |
| npm provenance | Source repo must match `package.json` `repository` | **Probably works** (not verified for reusable workflows) |
| crates.io trusted publishing | **Caller** workflow (`workflow_ref`) | **Works** (from source code; not stated in the docs) |
| GitHub artifact attestations | Signer = **called** workflow; source repo = caller | **Works**, and this is a supported pattern |

What this means for the template: keep the **PyPI upload step in the generated repo's own workflow**. A central reusable workflow can build the dists and upload them as an artifact. The caller then downloads them and runs `pypa/gh-action-pypi-publish` itself. npm, crates.io and GitHub attestations can live in the central workflow.

## Background: the two workflow claims in GitHub's OIDC token

When a job runs inside a called (reusable) workflow, the OIDC token carries:

- Standard claims about the **calling** workflow: `repository`, `ref`, `workflow`, `workflow_ref`, and `sub`. The example `sub` is the caller's `repo:octo-org/octo-repo:environment:prod`.
- An extra `job_workflow_ref` claim naming the **called** workflow, e.g. `central-org/workflows/.github/workflows/publish.yml@refs/tags/v1`.

Source: [GitHub Docs, Using OpenID Connect with reusable workflows](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-with-reusable-workflows).

Each registry checks one of these two claims, and that choice decides the answer. A registry that checks `workflow_ref` sees the caller. A registry that checks `job_workflow_ref` sees the central workflow.

## PyPI: trusted publishing does not work

- **Docs:** reusable workflows "cannot currently be used as the workflow in a Trusted Publisher". The limitation is tracked in [pypi/warehouse#11096](https://github.com/pypi/warehouse/issues/11096). Source: [PyPI Docs, Troubleshooting](https://docs.pypi.org/trusted-publishers/troubleshooting/).
- **Code:** in [`warehouse/oidc/models/github.py`](https://github.com/pypi/warehouse/blob/main/warehouse/oidc/models/github.py), the publisher lookup takes the workflow filename from `job_workflow_ref` (the called workflow). `_check_job_workflow_ref` then requires the claim to equal `{repository}/.github/workflows/{workflow_filename}@{ref or sha}`. Here `repository` is the publisher's (caller's) repo, and `ref`/`sha` are the caller's. `workflow_ref` is in `__unchecked_claims__`. A workflow in a *different* repo, or at a different ref such as `@v1`, can never match.
  - Side note, derived from the code and not documented: a reusable workflow in the **same** repo, called as `./.github/workflows/x.yml`, passes the check if the publisher is registered with the *called* file's name.
- **Status:** #11096 is still open (last updated 2026-05-02). A Warehouse maintainer said support is "Unlikely" without funded or volunteer work. Another maintainer called the build-in-reusable, publish-in-caller split "kinda the only recommended way right now". That split is the approach documented by [OpenAstronomy](https://github-actions-workflows.openastronomy.org/en/latest/trusted_publishing.html).
- **PyPA action:** "Trusted publishing cannot be used from within a reusable workflow at this time". This case is listed as "explicitly unsupported". Source: [pypa/gh-action-pypi-publish README](https://github.com/pypa/gh-action-pypi-publish).

**Setup needed:** register the trusted publisher on PyPI with the generated repo and the caller workflow filename (plus an environment if used). Run the `pypa/gh-action-pypi-publish` step in that caller workflow, not in the central one.

## PyPI PEP 740 attestations: do not work (inside the reusable workflow)

The PyPA action says generating and uploading attestations "is currently limited to Trusted Publishing flows" and "currently requires authentication with a trusted publisher". Source: [pypa/gh-action-pypi-publish README](https://github.com/pypa/gh-action-pypi-publish). Because trusted publishing fails from a cross-repo reusable workflow, attestations do too. If the upload stays in the caller, attestations work as normal.

**Not verified:** whether PyPI would accept a PEP 740 attestation signed by a central reusable workflow while the upload itself runs in the caller. The action signs inside the publish step, so the template would not run into this case.

## npm trusted publishing: works, with caveats

- **Docs:** for workflows that use `workflow_call`, "validation checks the calling workflow's name instead of the workflow that actually contains the publish command". Also, "The `id-token: write` permission must also be given to both parent and child workflows." Source: [npm Docs, Trusted publishing](https://docs.npmjs.com/trusted-publishers) (troubleshooting section).
- **Caveat: one workflow file per package.** npm's trusted publisher config names a single workflow file. If several caller workflows (e.g. `release.yml` and `manual-release.yml`) call the same reusable publish workflow, only the registered caller works. [npm/documentation#1755](https://github.com/npm/documentation/issues/1755) asks for multiple publishers or `job_workflow_ref`-based matching. It is open, with no npm maintainer answer.
- **Caveat: security model.** npm does not check the called workflow. Anyone who can edit the registered caller workflow in the generated repo can publish, whatever central workflow it calls (or none).

**Setup needed:** register the generated repo and the **caller** workflow filename (and environment, if any) on npmjs.com. Grant `id-token: write` in the caller and in the reusable workflow. Use a single caller workflow file for releases.

## npm provenance: probably works (partly verified)

- **Docs:** provenance needs `id-token: write` and a public `repository` in `package.json` that "matches (case-sensitive) where you are publishing with provenance from". Source: [npm Docs, Generating provenance statements](https://docs.npmjs.com/generating-provenance-statements). Provenance is generated automatically for trusted publishing only from a public repository and for a public package. Source: [npm Docs, Trusted publishing](https://docs.npmjs.com/trusted-publishers).
- The source repository in the signing certificate comes from the standard (caller) claims. So `repository.url` should point at the generated repo, not the central repo.
- **Not verified:** the npm docs do not say how the registry treats provenance signed by a cross-repo reusable workflow. I found no first-party statement either way. Run one real publish before relying on it.

## crates.io trusted publishing: works

- **Code:** in [`crates/crates_io_trustpub/src/github/claims.rs`](https://github.com/rust-lang/crates.io/blob/main/crates/crates_io_trustpub/src/github/claims.rs), the GitHub claims crates.io decodes are `repository_owner_id`, `repository`, `workflow_ref`, `environment`, `event_name`, `run_id` and `sha`. `job_workflow_ref` is not among them. `workflow_filename()` is taken from `workflow_ref`, which is the **caller's** top-level workflow, via [`workflows.rs`](https://github.com/rust-lang/crates.io/blob/main/crates/crates_io_trustpub/src/github/workflows.rs). A publish step inside a central reusable workflow therefore matches against the caller's repo and workflow filename.
- **Not verified:** the [crates.io trusted publishing docs](https://crates.io/docs/trusted-publishing) render client-side and I could not read them, so I did not confirm any explicit docs statement. This conclusion comes from the source code on `main` as of 2026-11-03.
- **Caveats:** these are the same as npm's. One caller workflow file per publisher config, and the called workflow is not pinned by the registry.

**Setup needed:** on crates.io, register the generated repo owner/repo, the **caller** workflow filename and an optional environment. Grant `id-token: write` in both workflows.

## GitHub artifact attestations: work (supported pattern)

- **Docs:** GitHub documents reusable workflows as a way to reach a higher security level. The reusable workflow "must also generate artifact attestations". The caller and the reusable workflow both need `attestations: write`, `contents: read` and `id-token: write` (plus `packages: write` for images). Source: [GitHub Docs, Increasing artifact security with reusable workflows](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/increase-security-rating).
- **Identity:** the signer is the **called** workflow (`job_workflow_ref`, the Build Signer URI). The source repo is the caller. To verify, use `gh attestation verify --owner <org>` (or `--repo <caller>`). Add `--signer-repo <central-org>/<central-repo>` or `--signer-workflow <central-org>/<central-repo>/.github/workflows/publish.yml` to require the central workflow.

## Unverified items

1. crates.io: docs page not read. The conclusion comes from source code only.
2. npm provenance: how it behaves with a cross-repo reusable workflow is not documented. Repo-matching uses the caller repo, by inference.
3. PyPI: whether a PEP 740 attestation signed in a reusable workflow would be accepted with an upload from the caller. The template will not need this case.
4. None of these were tested with a real publish run.
