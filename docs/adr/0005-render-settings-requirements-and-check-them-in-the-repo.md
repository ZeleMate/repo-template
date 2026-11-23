---
status: accepted
---

# Render each repo's settings requirements into the repo, and check them there with the code that applies them

The template renders the GitHub settings a repo needs into `.github/settings-requirements.json`, with answer conditions already evaluated, as [ADR 0003](0003-render-secret-requirements-into-generated-repos.md) does for secrets. Each entry is an API endpoint with the body bootstrap writes and, where GitHub's answer differs, what the check expects. `scripts/bootstrap-github.sh` now reads both JSON files at runtime: by default it applies them, `--dry-run` prints the writes, and `--check` reports drift and changes nothing. The `repo-github-setup` audit in the plugin only finds that script and runs `--check`. Before this, bootstrap and `audit-github.sh` each wrote out every setting, template-private detection, the secret waiver kinds and `has_governance`, so fix #53 had to land in both, and the audit had no tests because live GitHub was its only adapter.

## Considered Options

- **The audit stays in the plugin and reads the rendered file (ADR 0003's shape).** Rejected: the waiver kinds, template-private detection and the GitHub reads would still be written twice, once in the repo and once in the plugin, and the plugin would have to read declarations from every past template version.
- **Keep the settings as Jinja data unrolled into bootstrap, and render the JSON only for the audit.** Rejected for the same reason: two interpreters of one declaration.
- **Render SETUP.md's "Automated" list from the same data.** Not done: that list is prose for people and groups several entries into one line. A new setting is one entry in the JSON template plus its checklist line.

## Consequences

- **Drift means "re-running bootstrap would change it".** The check compares exactly what apply writes, so `has_wiki`, the squash commit message and the whole `main` ruleset are now checked, not four parts of it.
- **One comparison, `covers`:** objects by key, recursively; arrays by "every wanted element is covered by some element"; scalars by equality. An HTTP 404 is drift ("missing"); any other failed read, or a key absent from GitHub's answer, is `?`.
- **Bootstrap no longer writes `allowed_actions: all`.** It overwrote the stricter allowlists the audit accepts (#31). The check still requires a `selected` allowlist to allow what the workflows call.
- **The GitHub port is two functions** in the script, `gh_read` and `gh_write`, the only callers of `gh api`. Tests put a fake `gh` on `PATH` that serves recorded API responses (`scripts/test-github-settings.sh`); dry-run is the third adapter for writes.
- **A repo without the file can't be audited** (exit 2: "run copier update"), with no fallback to the old logic, as in ADR 0003.
- **Bootstrap needs jq.** It ships with macOS and GitHub's runners.
- **A fix to the check reaches a repo through `copier update`**, not a plugin update, like any copied file.
