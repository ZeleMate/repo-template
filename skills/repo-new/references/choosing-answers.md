# Choosing the template answers

The questions themselves (names, types, choices, defaults, validators) live in `copier.yml` at the plugin root. Read it for the exact keys; this file says how to help someone pick, and what each answer turns on, so you can explain the consequence instead of just asking the question.

## Contents

- Identity
- Shape (languages, visibility, plan, licence, agentic, publishes)
- Third-party services (AI reviewers, quality platform)
- Toolchains
- Combinations worth warning about
- Example answers file

## Identity

| Key | Notes |
|---|---|
| `project_name` | Human name. Required. |
| `project_slug` | Repo and package name; lowercase letters, digits, dashes. Defaults from the name. It is also the GitHub repo name the bootstrap creates. |
| `package_name` | Python import name (Python only). Defaults to the slug with underscores. |
| `description` | One line; goes in README, AGENTS.md, package metadata and the GitHub repo description. |
| `author_name`, `author_email` | Package metadata. For private repos the email is also the vulnerability-report address in SECURITY.md, so it should be one the maintainer reads. Take them from `git config user.name` / `user.email` and confirm. |
| `github_owner` | User or org that will own the repo. `gh api user --jq .login` gives the signed-in user. |

## Shape

**`languages`** (multiselect: `python`, `typescript`, `rust`). One language puts its files at the repo root; several put each in its own folder (`python/`, `typescript/`, `rust/`) with one shared CI, pre-commit and docs set. Infer from what the user says they are building; ask only when it is unclear.

**`visibility`** (`public` / `private`). The biggest lever, because it decides which GitHub security features are free:

- public: CodeQL default setup, secret scanning with push protection, private vulnerability reporting, artifact attestations and npm provenance all switch on. CodeRabbit and SonarQube Cloud are free.
- private: those GitHub features need a paid org add-on, so Semgrep CE, OSV-Scanner and Gitleaks in CI cover the same ground.

**`github_plan`** (`free` / `pro`). Matters only for private repos: rulesets (the thing that makes `ci-ok` required on `main`) and environments only work on private repos with Pro. On private + free the bootstrap skips the ruleset and the threat model records the gap. Say this out loud when someone picks private + free, because "CI is required to pass" silently stops being true.

**`license`** (`MIT`, `Apache-2.0`, `Proprietary`). Defaults to MIT for public, Proprietary for private. An open licence also adds `LICENSES/` and `REUSE.toml`.

**`agentic`** (bool, default true). Yes if the app calls an LLM or runs agents. Adds the OWASP LLM / Agentic Top 10 sections to the threat model, `docs/agent-policy.md`, an Inspect AI `evals/` suite and the evals workflow (mock model on PRs, real model nightly, which needs a spend-capped API key). Say no for plain libraries and services, otherwise they carry a nightly job that needs a secret.

**`publishes`** (bool, default false). Yes only if packages go to PyPI / npm / crates.io. Adds OIDC trusted-publishing jobs, attestations, immutable releases and `docs/verify.md`. Releases (release-please, changelog, SBOM) happen either way.

## Third-party services

**`ai_reviewers`** (multiselect: `claude`, `coderabbit`). `claude` adds a workflow using the Claude Code GitHub Action on the user's Claude subscription (needs a `CLAUDE_CODE_OAUTH_TOKEN` secret). `coderabbit` adds `.coderabbit.yaml`; free on public repos, paid after a trial on private ones. Default: both for public, Claude only for private.

**`quality_platform`** (`none` / `sonarqube-cloud`). SonarQube Cloud adds maintainability metrics, not security. Free and complete for public repos; on private repos the free plan is capped at 50k LOC and main-branch only. Default: on for public, off for private. `sonar_organization` defaults to the lowercased owner.

## Toolchains

Only asked for the chosen languages. Defaults are sensible; change them only on request.

| Key | Default | Notes |
|---|---|---|
| `python_version` | 3.13 | Minimum supported |
| `python_type_checker` | pyright | or mypy; both strict |
| `node_version` | 26 | 24 or 26 (LTS majors) |
| `ts_linter` | eslint | or oxlint (faster, fewer rules) |
| `rust_toolchain` | 1.99.0 | pinned in `rust-toolchain.toml` |
| `rust_msrv` | 1.97 | `rust-version` in Cargo.toml |

## Combinations worth warning about

- private + free: no enforced `ci-ok`, no `release` environment. Suggest Pro or public if the user expects branch protection.
- private + `coderabbit`: paid after 14 days.
- private + `sonarqube-cloud`: limited free plan.
- `publishes` on a private repo: no attestations or npm provenance; trusted publishing still works.
- `agentic` = true: someone has to fill in `docs/THREAT_MODEL.md` §5 and `docs/agent-policy.md` before the first agent feature ships.

## Example answers file

Pass this with `--data-file`. Lists are YAML lists. Leave out any key you want defaulted.

```yaml
project_name: Invoice Agent
project_slug: invoice-agent
description: Extracts line items from supplier invoices
author_name: Ada Lovelace
author_email: ada@example.com
github_owner: ada
languages: [python, typescript]
visibility: private
github_plan: pro
license: Proprietary
agentic: true
publishes: false
ai_reviewers: [claude]
quality_platform: none
python_type_checker: pyright
ts_linter: eslint
```
