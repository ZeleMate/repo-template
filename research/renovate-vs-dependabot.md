# What would a shared Renovate preset give us over Dependabot?

Research for [#6](https://github.com/ZeleMate/repo-template/issues/6) (child of #2). Sources were checked on 2026-11-03 against the Renovate docs (`renovatebot/renovate` `main`), the Mend-hosted docs, and GitHub Docs and Changelog.

## Short answer

A central Renovate preset buys **one place to change policy** and a few features Dependabot lacks: built-in automerge, a Dependency Dashboard, and finer-grained rules. Grouping and cooldown are **not** the differentiator any more, because Dependabot has both and the template already uses them. On GitHub's side we keep **Dependabot alerts and malware alerts**, because they work independently of which bot opens version-update PRs. The Mend Renovate App is **free for public and private repos**, but on the free tier it runs every 4 hours with 1 concurrent job. Also, a **private preset repo cannot be extended from a public repo**, so the shared preset should be public.

Since the template is a Copier template, `copier update` already pushes `dependabot.yml` changes to generated repos. That shrinks the "central policy" advantage to "no PR per repo for a policy change".

## Comparison

| Concern | Dependabot (`dependabot.yml`, current template) | Renovate (central preset + Mend app) |
|---|---|---|
| Sharing config | No inheritance mechanism in `dependabot.yml`. Each repo carries its own file. With Copier, changes spread via `copier update` PRs. | `"extends": ["github>ZeleMate/renovate-config"]` reads `default.json` from the preset repo's default branch. A change there applies on the next run in every repo. Can pin a tag (`#1.2.3`). [1] |
| Grouping | `groups` with `patterns` and `update-types`, plus `multi-ecosystem-groups`. `group-by` applies to version updates only. [5] | `packageRules` plus `groupName`, and built-in `group:monorepos` / `group:recommended` (part of `config:recommended`). [3] |
| Cooldown | `cooldown.default-days` and `semver-{major,minor,patch}-days`. **A default 3-day cooldown applies even if unset.** Cooldown does not apply to security updates. [5] | `minimumReleaseAge`, per version, enforced through a `renovate/stability-days` status check. It needs a registry-provided release timestamp. Since Renovate 42, a missing timestamp counts as "not yet passed". `security:minimumReleaseAge{Npm,Pypi,Crate}` presets exist (3 days). `config:best-practices` only includes the npm one. [2][4][6] |
| Automerge | No config option. You need a workflow using `dependabot/fetch-metadata` plus `gh pr merge --auto`, and repo auto-merge plus required status checks. [7] | `automerge` with `automergeType` `pr` / `branch` and `matchUpdateTypes`. With `minimumReleaseAge`, it opens the PR immediately and automerges only after the age passes. `platformAutomerge` is on by default. **Warning from the docs:** without a required status check, GitHub may automerge PRs whose tests fail. [3] |
| Security fix PRs | Dependabot security updates, separate from `dependabot.yml` version updates. [8] | `vulnerabilityAlerts` reads **GitHub's Dependabot alerts** (dependency graph and Dependabot alerts must be on, and the app needs `read` on "Dependabot alerts"). These PRs skip schedules and limits. Optionally `osvVulnerabilityAlerts` (OSV, direct deps only; npm, pypi, crate and others are covered). [3] |
| Malware | Dependabot malware alerts: Composer, Go, Maven, npm, NuGet, pip, RubyGems, Rust. They only fire on GitHub-reviewed advisories. OpenSSF malicious-packages feed ingested since 2026-07. [9][10] | Malicious-package detection is marked "experimental" under `osvVulnerabilityAlerts`. [3] Not a replacement. |
| Overview | Dependabot tab / PR list | Dependency Dashboard issue (in `config:recommended`), which shows pending and age-gated updates. [3][6] |

## What we would lose or must keep from GitHub

- **Keep on:** the dependency graph, Dependabot alerts, malware alerts and (optionally) Dependabot security updates. These are repo settings, not part of `dependabot.yml`. GitHub says there is "no interaction" between `dependabot.yml` settings and security alerts. [8] Renovate's `vulnerabilityAlerts` actually **depends on** Dependabot alerts being enabled. [3]
- **Drop:** `dependabot.yml` version updates, to avoid duplicate PRs from two bots. If Dependabot security updates stay on as well, both bots may raise a fix PR for the same CVE. Pick one: Renovate `vulnerabilityAlerts` *or* Dependabot security updates. *(Duplicate behaviour is inferred from the docs, not tested.)*
- **Lose:** nothing significant on alerting. We would lose GitHub-native PR authorship (`dependabot[bot]`), and with it workflows keyed on that actor. The template has no such workflow today.

## Running the Mend Renovate App

- **Cost:** Community Cloud is **free**, "available for all across an unlimited number of public and private repositories". [11]
- **Free-tier limits** (Community): 1 concurrent job per org/account, active repos scheduled **every 4 hours**, 1 vCPU / 3 GB / 15 GB, 30-minute timeout. Repos that are onboarded but have no merged Renovate PR ("inactive") run **daily**. [11][12] A webhook (for example, ticking a Dashboard checkbox) also triggers a job. [11]
- Free users **cannot use arbitrary `postUpgradeTasks`** commands. [13]
- **Private presets:** install the app on the preset repo too, and reference it with `local>` / `github>`. **Extending a private preset from a public repo does not work**, because public repos get a token scoped to that repo only. The docs recommend splitting presets into public and private ones, or making the preset public if it holds no secrets. [14] For this setup, use a **public** `renovate-config` repo.
- **Org-level default:** on onboarding, Renovate looks for `<owner>/renovate-config` (`default.json`) or `<owner>/.github` (`renovate-config.json`) and suggests it as the sole preset. [1] Naming the repo `renovate-config` makes onboarding PRs pick it up automatically.
- **Unverified:** the exact GitHub App permission list Mend requests, and whether the free tier still has all of the above limits. The docs table was the only source, with no pricing page beyond "contact sales" for Enterprise.

## Implications for the template (input for #8)

1. Cooldown and grouping parity already exist in `dependabot.yml`. A switch should be justified by **automerge without a workflow**, the **dashboard**, and **one-place policy** rather than by those two features.
2. If we switch, generated repos get a tiny `renovate.json` (`extends: ["github>ZeleMate/renovate-config"]`). The public preset holds `config:best-practices`, `minimumReleaseAge: "7 days"` (plus a longer value for `major` via `packageRules`), grouping, and automerge for minor/patch, gated on CI as a required status check. GitHub alerts and malware alerts stay on.
3. `config:best-practices` pins GitHub Actions to digests (`helpers:pinGitHubActionDigests`). GitHub malware alerts for Actions only cover actions pinned **by semver tag, not SHA**. [9] That is a small trade-off to note.

## Sources

1. Renovate, Shareable Config Presets: https://docs.renovatebot.com/config-presets/
2. Renovate, Minimum Release Age: https://docs.renovatebot.com/key-concepts/minimum-release-age/
3. Renovate, Configuration Options (`minimumReleaseAge`, `automerge`, `automergeType`, `platformAutomerge`, `vulnerabilityAlerts`, `osvVulnerabilityAlerts`): https://docs.renovatebot.com/configuration-options/
4. Renovate source, `security` presets: https://github.com/renovatebot/renovate/blob/main/lib/config/presets/internal/security.preset.ts
5. GitHub Docs, Dependabot options reference (`cooldown`, `groups`): https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference
6. Renovate source, `config:recommended` / `config:best-practices`: https://github.com/renovatebot/renovate/blob/main/lib/config/presets/internal/config.preset.ts
7. GitHub Docs, Automating Dependabot with GitHub Actions: https://docs.github.com/en/code-security/dependabot/working-with-dependabot/automating-dependabot-with-github-actions
8. GitHub Docs, About Dependabot security updates: https://docs.github.com/en/code-security/dependabot/dependabot-security-updates/about-dependabot-security-updates
9. GitHub Docs, Dependabot malware alerts: https://docs.github.com/en/code-security/concepts/supply-chain-security/malware-alerts
10. GitHub Changelog, 2026-07-28, Dependabot alerts on malicious packages across more ecosystems: https://github.blog/changelog/2026-07-28-dependabot-alerts-on-malicious-packages-across-more-ecosystems
11. Renovate, Mend-hosted Apps overview: https://docs.renovatebot.com/mend-hosted/overview/
12. Renovate, Mend-hosted job scheduling: https://docs.renovatebot.com/mend-hosted/job-scheduling/
13. Renovate, Mend-hosted FAQ: https://docs.renovatebot.com/mend-hosted/faq/
14. Renovate, Private packages (private presets, public repos): https://docs.renovatebot.com/getting-started/private-packages/
