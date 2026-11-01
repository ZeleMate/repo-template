# repo-template

A [Copier](https://copier.readthedocs.io/) template that gives every new repo the same production baseline: CI, security scanning, dependency hygiene, releases, AI review, coding-agent config, and the docs a production codebase needs. It covers Python, TypeScript and Rust, alone or together.

The choices come from the research report *Repo standards for agentic stacks*. Each one is backed by a standard (OpenSSF, NIST SSDF, SLSA, OWASP) or by what major reference projects actually run.

## Quick start

```bash
# 1. Generate (answers drive everything below)
uvx copier copy --trust gh:<you>/repo-template my-project

# 2. Create the GitHub repo and apply settings
cd my-project
./scripts/bootstrap-github.sh --dry-run
./scripts/bootstrap-github.sh

# 3. Do the manual steps it prints (also in docs/SETUP.md)
```

`--trust` is needed because the template runs local post-generation tasks: `uv lock`, `pnpm install --lockfile-only`, `cargo generate-lockfile` and `chmod`. Nothing touches GitHub until you run the bootstrap script.

**Pull template improvements into existing repos:**

```bash
uvx copier update --trust
```

A weekly workflow in each generated repo opens an issue when a new template tag exists.

## Questions you'll be asked

| Question | Effect |
|---|---|
| Languages (Python / TypeScript / Rust) | One language: files at the root. Several: `python/`, `typescript/`, `rust/` folders |
| Visibility (public / private) | Public turns on GitHub's free CodeQL, secret scanning, private vuln reporting and attestations |
| GitHub plan (free / pro) | Pro makes rulesets and environments work on private repos |
| Licence | MIT / Apache-2.0 (with REUSE metadata) or proprietary |
| Agentic app? | Adds the agentic threat model, `docs/agent-policy.md`, Inspect AI evals and the evals workflow |
| Publishes packages? | Adds trusted-publishing jobs (PyPI / npm / crates.io), attestations, immutable releases |
| AI reviewers | Claude Code Action and/or CodeRabbit |
| Quality platform | none / SonarQube Cloud |
| Toolchain details | Python version and type checker (pyright/mypy), Node LTS, ESLint/Oxlint, Rust toolchain and MSRV |

## What you get, and why

| Area | Default | Alternatives you can swap in |
|---|---|---|
| CI | GitHub Actions. Every action is pinned to a commit SHA, `permissions: {}` by default, and a single `ci-ok` required check | — |
| Workflow linting | zizmor + actionlint (pre-commit and CI) | — |
| Static analysis (security) | **Public:** CodeQL default setup + Semgrep CE. **Private:** Semgrep CE in CI | Semgrep AppSec Platform free tier (10 repos, cross-file); Opengrep (LGPL fork) |
| Code quality dashboard | SonarQube Cloud, opt-in. On by default for public repos, where the open-source plan is free and complete | Qlty (free tier); SonarQube Server Community Build (self-hosted) |
| Dependency vulns | OSV-Scanner (checksum-verified binary) + Dependabot alerts; `cargo deny` for Rust | Snyk / Socket free tiers |
| Malicious packages | Dependabot malware alerts (manual toggle) + install cooldowns | Socket GitHub App |
| Secrets | Gitleaks (pre-commit + full-history CI scan); GitHub push protection on public repos | TruffleHog, GitGuardian |
| Dependency updates | Dependabot, grouped weekly, 7-day cooldown (14 for majors) | Renovate (`minimumReleaseAge`) |
| Releases | release-please from Conventional Commit PR titles; SBOM (SPDX) attached | changesets for pnpm monorepos |
| Publishing | OIDC trusted publishing: PyPI (PEP 740 attestations), npm (provenance on public), crates.io | — |
| AI review | Claude Code Action (runs on your Claude subscription) and/or CodeRabbit (free on public repos) | GitHub Copilot code review (enable via ruleset; billed per review); Qodo PR-Agent (MIT, your own API key) |
| Spec conformance | **Custom:** `spec-review` skill + read-only `code-reviewer` subagent + `REVIEW.md` | Nothing on the market does this by default |
| Agent config | `AGENTS.md` (canonical) + `CLAUDE.md` importing it; `.claude/settings.json` deny rules + formatter hook | — |
| Agentic app safety | Threat model keyed to OWASP LLM Top 10 2026 + Agentic Top 10; agent policy; Inspect AI evals (mock on PRs, real model nightly) | promptfoo |
| Python | uv + `uv.lock` (7-day `exclude-newer`), Ruff, pyright/mypy strict, pytest + Hypothesis, coverage | — |
| TypeScript | pnpm (3-day `minimumReleaseAge`, `trustPolicy`), ESLint + typescript-eslint strict / Oxlint, Prettier, Vitest + fast-check | — |
| Rust | pinned `rust-toolchain.toml`, clippy `-D warnings`, nextest, cargo-deny, proptest, `unsafe` forbidden | — |
| Coverage | 80% overall (Badge silver), **90% on changed lines** in PRs (diff-cover) | Codecov |
| Docs | MADR ADRs (incl. the solo-review exception), threat model, SECURITY.md (OpenSSF template), dependency and secrets policy, SLOs, runbooks | — |

### Why some tools are opt-in rather than default

- **SonarQube Cloud on private repos:** the free plan covers 50k LOC, analyses the main branch only, uses a fixed quality gate and leaves out its advanced security analysis. Next to Semgrep it adds maintainability metrics, not security. That's useful, but not required.
- **CodeRabbit on private repos:** paid after a 14-day trial. The Claude Action already reviews on your existing subscription. No independent study ranks one AI reviewer above another, so a second reviewer is a preference.
- **GitHub CodeQL and secret scanning on private repos:** these need a Team org plus Code Security ($30) and Secret Protection ($19) per committer per month. The OSS tools above cover the same ground for free.

## Public vs private at a glance

| | Public (Free) | Private (Free) | Private (Pro) |
|---|---|---|---|
| Ruleset enforcing `ci-ok` | ✓ | ✗ (documented gap) | ✓ |
| CodeQL / secret scanning / PVR | ✓ | ✗, so OSS tools in CI | ✗, so OSS tools in CI |
| Artifact attestations, npm provenance | ✓ | ✗ | ✗ |
| Dependabot alerts + updates | ✓ | ✓ | ✓ |
| Actions minutes | unlimited | ~2,000 Linux min/mo | ~3,000 Linux min/mo |

## Maintaining the template

- Tag releases (`v1.2.0`). `copier update` and the weekly check use tags.
- **Bump pinned versions deliberately.** Action SHAs, hook revs, the gitleaks/OSV-Scanner checksums and Semgrep live in the template files. Dependabot keeps them current in generated repos; update the template itself quarterly.
- **Test changes:** `./scripts/test-template.sh` generates every language combination and runs actionlint, zizmor and the real toolchains on the output.

## Facts to re-check before relying on them

These were not fully verifiable when the template was written:

- Whether Dependabot alerts parse `uv.lock` (OSV-Scanner covers it regardless).
- Malware alerts on private repos.
- Whether the `sha_pinning_required` policy applies to personal-account repos (the bootstrap reports a failure if not).
- When GitHub's workflow lockfile (`actions.lock`) reaches general availability. Adopt it when it does.
