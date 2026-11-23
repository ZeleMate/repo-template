---
name: repo-adopt
description: Bring an existing repository up to the repo-template production baseline — SHA-pinned CI with a ci-ok gate, Semgrep/OSV-Scanner/Gitleaks, Dependabot cooldowns, release-please, AI review, AGENTS.md/CLAUDE.md and .claude config, threat model, ADRs, SECURITY.md — by rendering the Copier template next to the repo and merging it in file by file, keeping the project's own code and deliberate choices, and leaving a .copier-answers.yml so future template updates apply. Use whenever someone wants to retrofit, harden, standardise or "productionise" an existing repo, add our CI/security/release setup to a project that already has code, migrate a repo onto the template, or asks why an old repo doesn't get template updates.
---

# Adopt the template in an existing repo

Copying the template straight over an existing project would overwrite their README, their CI, their `pyproject.toml`. So render it into a scratch folder, compare, and merge deliberately. The end state is the project's code unchanged, the template's baseline around it, and a `.copier-answers.yml` that lets `copier update` (the `repo-template-update` skill) keep it current from then on.

The plugin root (two levels above this skill's base directory) holds `copier.yml`, `template/` and `README.md`. The `repo-new` skill's `references/` folder (a sibling of this skill) has `choosing-answers.md` and `template-source.md`; read both.

## 1. Survey the repo

Work on a fresh branch (`git switch -c chore/adopt-repo-template`); the repo must have a clean working tree so the merge is reviewable as one diff.

Collect what the answers depend on, and what will collide:

- Languages and layout: where `pyproject.toml`, `package.json`, `Cargo.toml`, `go.mod` are. The template puts a single language at the root and several under `python/`, `typescript/`, `rust/`, `go/`. If the repo's layout differs, don't move code to fit; you will map paths instead (step 4).
- Package managers and tools in use: Poetry/pip vs uv, npm/yarn vs pnpm, mypy vs pyright, ESLint vs Oxlint, Jest vs Vitest.
- Existing CI (`.github/workflows/`), pre-commit config, Dependabot/Renovate, release tooling, `AGENTS.md`/`CLAUDE.md`/`.claude/`, licence, SECURITY.md, docs.
- GitHub facts: `gh repo view --json visibility,owner,name`.

### Secrets already in history

Before anything else lands, scan the full history, because the template's CI runs Gitleaks on every commit of every branch and would start red:

```bash
gitleaks git --redact --no-banner .
```

Stop on any finding and go through each with the user:

- **A real secret:** the owner rotates it first. Only then add its fingerprint (the `Fingerprint:` line Gitleaks prints) to `.gitleaksignore` with a comment giving the rotation date. Never add a fingerprint for a secret that is still valid.
- **A false positive:** add the fingerprint with a comment saying why it isn't a secret.

Don't rewrite history. In a public repo the value is already exposed, so only rotation removes the risk. CI then starts green and still fails on a new secret.

## 2. Agree the answers and the scope

Draft the answers from the survey (visibility, owner and slug come from GitHub; author from git config). Set `repo_name` to the repo's exact GitHub name when it has capitals, dots or underscores the slug can't hold (`LegalQA_v2`), and `python_max_version` when the repo's `requires-python` has an upper bound or a dependency doesn't support the newest Python yet. For Go, `go_module` is the existing `module` line of `go.mod`, copied exactly (any difference breaks every import), and `go_version` is its `go` line's `1.N`. Then talk through, with the user, every place where the template's choice differs from what the repo does today. For each, the options are adopt the template's tool (migrate), or keep theirs and adapt the template file. Recommend, don't decide:

- A tool swap that's mostly config (mypy → pyright, adding Ruff, npm → pnpm) is usually worth it.
- A swap that touches lots of code or habits (Poetry → uv with many extras, Jest → Vitest with heavy mocks) can be its own follow-up PR; keep their tool and wire it into the template's CI job for now.
- **A repo that keeps its whole stack becomes a baseline repo.** If the repo doesn't use uv, Ruff and strict typing for Python, or pnpm, ESLint and Vitest for TypeScript, and the user doesn't want to migrate, answer `languages: []` and name its package ecosystems in `extra_ecosystems`. The template then writes no toolchain, release or ops files, and the repo's own CI jobs move into `.github/workflows/ci-local.yml` (step 4). This is the usual answer for an existing repo; the full template fits a repo already on the template's toolchain.
- Never silently drop an existing CI job or check. If the template has no equivalent, keep it in their workflow and make it a dependency of `ci-ok`.

## 3. Render to a scratch folder

Resolve the template source and tag as in `template-source.md`, write the answers file, then:

```bash
uvx copier copy --trust --defaults --data-file <answers.yml> --vcs-ref <tag> <source> <scratch>/rendered
```

The post-generation tasks create fresh lockfiles in the scratch copy. Those are for an empty project; don't copy them over the repo's real lockfiles.

## 4. Merge file by file

Walk the rendered tree (`find <scratch>/rendered -type f -not -path '*/.venv/*' -not -path '*/node_modules/*'`) and, for each file, take one of three actions. Track the decisions in a short list; it goes into the PR description.

| File kind | Default action |
|---|---|
| Doesn't exist in the repo (most of `.github/`, `docs/`, `.claude/`, `AGENTS.md`, `REVIEW.md`, `SECURITY.md`, `scripts/bootstrap-github.sh`, `.editorconfig`) | Copy it in. |
| Exists and is pure config (`.pre-commit-config.yaml`, `.gitignore`, `dependabot.yml`, linter configs) | Merge: template content as the base, plus the repo's extra entries. In `.gitignore`, keep the template's closing `!` block (release-please files, `.github/tools/.python-version`) last, below the repo's entries, or a broad rule like `.python-version` or `/*.json` hides them. Before committing, run `git status --ignored` and check that no rendered file is ignored. |
| Exists and is the project's own (`README.md`, `pyproject.toml`/`package.json`/`Cargo.toml`, source, tests, `LICENSE`, `CHANGELOG.md`) | Keep theirs; port only the template's tool settings into it (e.g. the `[tool.ruff]`, `[tool.pyright]`, coverage and `exclude-newer` sections; the package.json scripts CI calls: `format:check`, `lint`, `typecheck`, `test:coverage`, `build`). |
| The template's placeholder code (`src/<pkg>/__init__.py`, `src/index.ts`, `src/lib.rs`, `tests/test_smoke.py`, `test/index.test.ts`, `cmd/<slug>/`, `internal/greeting/`) | Skip. |
| `.github/workflows/ci-local.yml` | The repo owns this file; the template never updates it. Move the repo's existing CI jobs into it as jobs of a reusable workflow (`on: workflow_call`), replacing the no-op job. Keep every action pinned to a full SHA, give each job its own `permissions`, and make sure no job needs a secret (Dependabot PRs get none). Delete the old workflow those jobs came from, so they don't run twice. `ci.yml` calls it as `uses: $/.github/workflows/ci-local.yml`: `$/` is GitHub's self-repository syntax, which zizmor's `self-repository` audit requires. Don't change it to `./`. |
| Existing CI workflows | Replace with the template's `ci.yml`, `security.yml`, `release.yml`, then re-add any job the template lacks and add it to `ci-ok`'s `needs`. Keep every action pinned to a full SHA with a version comment. The template's `ci.yml` only calls reusable workflows in `ZeleMate/workflows`; if the repo keeps a toolchain those don't support (Bun, Poetry, Jest), drop that language's call, keep the repo's own job in `ci.yml`, and still call `security.yml` and `repo-lint.yml`. |

### Go

- **`.golangci.yml`** is merged like other config. If theirs is v1, run `golangci-lint migrate` first, then combine their linters and settings with the template's. Keep the template's `gofmt` and `goimports` formatters: the `golangci-lint-fmt` hook and CI's format check depend on them.
- **A `Makefile`** is kept. Tell the user that CodeQL's Go autobuild runs `make` first in public repos, so they should check the first CodeQL run.
- **GoReleaser:** move to the template's `publish-go` job by default. Keep GoReleaser only for what `publish-go` lacks (archives, Homebrew taps, Docker images, signing): then answer `publishes: false` and let their workflow run from the tag. That works only in a single-language repo with root `v` tags, because GoReleaser's open-source edition can't release from `go/vX.Y.Z` tags.
- **Release history:** set the Go entry in `.release-please-manifest.json` to the latest released version, not `0.1.0`. Otherwise a `/v3` module would next be tagged `v0.2.0`, which Go rejects, and `go-major-version` doesn't check majors 0 and 1. The tag prefix must match the module's folder: when Go stays at the root in a multi-language repo, set `"include-component-in-tag": false` on the Go package. Existing tags stay as they are.

If the layout differs from the template's (say Python under `backend/`), fix paths in the copied files: the `working-directory` inputs in `ci.yml`, the `uv run --project` / `pnpm --dir` paths in `.claude/hooks/format.sh`, `paths` in `release-please-config.json`, and each language's `dir` in `.github/language-profiles.json` (where verify runs its checks).

Add the dev dependencies the template's CI calls with the package manager, never by editing lockfiles (`uv add --dev ruff pyright pytest pytest-cov hypothesis`, `pnpm add -D ...` as listed in the rendered `package.json`). Respect the cooldowns the template sets.

## 5. Write the answers file

Copy `<scratch>/rendered/.copier-answers.yml` to the repo root unchanged. Its `_commit` is the tag you rendered from, which is what makes later `copier update` runs a 3-way merge against that version instead of a fresh copy. Don't edit it by hand, except `_src_path` if it points at a local path (see `template-source.md`).

## 6. Verify and open a PR

```bash
bash <plugin root>/skills/repo-new/scripts/verify-generated.sh .
```

Fix what fails. Failures now are usually real issues in the existing code that the stricter checks catch (type errors, lint, low coverage). Fix the trivial ones; for big batches, ask whether to fix now or relax a specific rule with a comment and a follow-up issue, rather than disabling a check wholesale.

If the repo restricts GitHub Actions to an allowlist, check it allows `ZeleMate/*`, `astral-sh/setup-uv@*` and `dependabot/fetch-metadata@*` before pushing; otherwise `ci.yml` fails at startup with no job logs. Ask before changing it.

Commit as `chore: adopt repo template <tag>` and, with the user's go-ahead, push and open a PR whose body lists the merge decisions from step 4 and the follow-ups. After merge, the `repo-github-setup` skill applies the GitHub settings (the bootstrap script detects that the repo already exists) and its audit shows what's missing.
