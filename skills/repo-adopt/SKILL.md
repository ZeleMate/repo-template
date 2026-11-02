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

- Languages and layout: where `pyproject.toml`, `package.json`, `Cargo.toml` are. The template puts a single language at the root and several under `python/`, `typescript/`, `rust/`. If the repo's layout differs, don't move code to fit; you will map paths instead (step 4).
- Package managers and tools in use: Poetry/pip vs uv, npm/yarn vs pnpm, mypy vs pyright, ESLint vs Oxlint, Jest vs Vitest.
- Existing CI (`.github/workflows/`), pre-commit config, Dependabot/Renovate, release tooling, `AGENTS.md`/`CLAUDE.md`/`.claude/`, licence, SECURITY.md, docs.
- GitHub facts: `gh repo view --json visibility,owner,name`.

## 2. Agree the answers and the scope

Draft the answers from the survey (visibility, owner and slug come from GitHub; author from git config). Then talk through, with the user, every place where the template's choice differs from what the repo does today. For each, the options are adopt the template's tool (migrate), or keep theirs and adapt the template file. Recommend, don't decide:

- A tool swap that's mostly config (mypy → pyright, adding Ruff, npm → pnpm) is usually worth it.
- A swap that touches lots of code or habits (Poetry → uv with many extras, Jest → Vitest with heavy mocks) can be its own follow-up PR; keep their tool and wire it into the template's CI job for now.
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
| Exists and is pure config (`.pre-commit-config.yaml`, `.gitignore`, `dependabot.yml`, linter configs) | Merge: template content as the base, plus the repo's extra entries. |
| Exists and is the project's own (`README.md`, `pyproject.toml`/`package.json`/`Cargo.toml`, source, tests, `LICENSE`, `CHANGELOG.md`) | Keep theirs; port only the template's tool settings into it (e.g. the `[tool.ruff]`, `[tool.pyright]`, coverage and `exclude-newer` sections; the package.json scripts CI calls: `format:check`, `lint`, `typecheck`, `test:coverage`, `build`). |
| The template's placeholder code (`src/<pkg>/__init__.py`, `src/index.ts`, `src/lib.rs`, `tests/test_smoke.py`, `test/index.test.ts`) | Skip. |
| Existing CI workflows | Replace with the template's `ci.yml`, `security.yml`, `release.yml`, then re-add any job the template lacks and add it to `ci-ok`'s `needs`. Keep every action pinned to a full SHA with a version comment. |

If the layout differs from the template's (say Python under `backend/`), fix paths in the copied files: `working-directory`, `cache-dependency-glob`, coverage paths in `ci.yml`, the `uv run --project` / `pnpm --dir` paths in `.claude/hooks/format.sh`, and `paths` in `release-please-config.json`.

Add the dev dependencies the template's CI calls with the package manager, never by editing lockfiles (`uv add --dev ruff pyright pytest pytest-cov hypothesis diff-cover`, `pnpm add -D ...` as listed in the rendered `package.json`). Respect the cooldowns the template sets.

## 5. Write the answers file

Copy `<scratch>/rendered/.copier-answers.yml` to the repo root unchanged. Its `_commit` is the tag you rendered from, which is what makes later `copier update` runs a 3-way merge against that version instead of a fresh copy. Don't edit it by hand, except `_src_path` if it points at a local path (see `template-source.md`).

## 6. Verify and open a PR

```bash
bash <plugin root>/skills/repo-new/scripts/verify-generated.sh .
```

Fix what fails. Failures now are usually real issues in the existing code that the stricter checks catch (type errors, lint, low coverage). Fix the trivial ones; for big batches, ask whether to fix now or relax a specific rule with a comment and a follow-up issue, rather than disabling a check wholesale.

Commit as `chore: adopt repo template <tag>` and, with the user's go-ahead, push and open a PR whose body lists the merge decisions from step 4 and the follow-ups. After merge, the `repo-github-setup` skill applies the GitHub settings (the bootstrap script detects that the repo already exists) and its audit shows what's missing.
