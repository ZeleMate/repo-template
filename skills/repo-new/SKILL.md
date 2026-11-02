---
name: repo-new
description: Create a new repository with a production baseline from the repo-template Copier template — SHA-pinned GitHub Actions CI with a single ci-ok check, Semgrep/OSV-Scanner/Gitleaks/CodeQL, Dependabot with cooldowns, release-please releases, optional trusted publishing, Claude/CodeRabbit AI review, AGENTS.md + Claude Code config, threat model, ADRs and (for LLM apps) agent policy and evals. Python, TypeScript and Rust, alone or together. Use this whenever someone wants to start, scaffold, bootstrap or init a new project/repo/service/library/package/agent app "properly", "production-ready", "with CI and security set up", or "from our template", even if they don't mention Copier or the template by name.
---

# New repo from the template

You turn a short conversation into a generated, locally verified repository. Creating the GitHub repo and applying its settings is a separate step (the `repo-github-setup` skill), because it is outward-facing and the user should look at the generated files first.

The plugin root (two levels above this skill's base directory) is the template itself: `copier.yml` holds the questions, `template/` the files, `README.md` the reasoning behind every default. Read `README.md` once if the user asks *why* something is set up the way it is.

## 1. Check prerequisites

```bash
for t in git uv gh pnpm node cargo; do printf '%-6s ' $t; command -v $t >/dev/null && echo ok || echo missing; done
```

`uv` is required (Copier runs through `uvx` and the post-generation tasks call `uv lock`). `pnpm` and `node` are required only for TypeScript, `cargo` only for Rust (generation still works without it; the lockfile is made later). `gh` is needed in the next skill, not here. Tell the user what's missing and how to install it rather than working around it.

## 2. Gather the answers

Read `copier.yml` for the exact keys and `references/choosing-answers.md` for what each answer changes. Copier's own prompts are interactive and you cannot answer a TTY, so collect the answers in chat and write them to a file.

- Fill in what you can infer: author from `git config user.name`/`user.email`, `github_owner` from `gh api user --jq .login`, languages from what the user described.
- Ask about what you cannot infer, all at once rather than one question per message. The ones that usually need asking are `visibility`, `github_plan` (only if private), `agentic` and `publishes`. Explain the consequence of each in a few words; the reference file has them.
- Toolchain versions and linters: keep the defaults unless the user has a preference.
- Before generating, show the final answers as a compact table and point out any combination from the "worth warning about" list.

Write the answers to a YAML file **outside** the destination (the scratchpad or a temp dir), since Copier refuses to write into a non-empty folder without `--overwrite` and the file does not belong in the repo.

## 3. Generate

Resolve the template source and version as described in `references/template-source.md` (normally the latest tag of `gh:ZeleMate/repo-template`). Then:

```bash
uvx copier copy --trust --defaults --data-file <answers.yml> --vcs-ref <tag> <source> <destination>
```

- `--trust` is needed because the template runs local post-generation tasks: `chmod`, `uv lock`, `pnpm install --lockfile-only`, `cargo generate-lockfile`. None of them touch GitHub. Mention this when you run it.
- `--defaults` fills computed values and anything the user left to the default; without it Copier would wait on a prompt.
- The destination must not exist or must be empty. If it is an existing project, stop and use the `repo-adopt` skill instead; copying over it would clobber their files.

## 4. Verify locally

```bash
bash <this skill's base directory>/scripts/verify-generated.sh <destination>
```

It reads `.copier-answers.yml` and runs what CI runs: actionlint and zizmor (if installed), JSON validity, pre-commit, a check for unrendered `[[ ]]`/`[% %]` tags, then per language uv/ruff/pyright-or-mypy/pytest, pnpm/prettier/lint/typecheck/vitest/build, cargo fmt/clippy/test. Before `git init`, pre-commit is skipped; that's expected.

A failure here is a template bug or a missing tool, not something to patch in the generated repo by hand. Report the failing check with its output; if it's a template bug, say so and suggest fixing it in the template (the `repo-template-maintain` skill) so every future repo gets the fix.

## 5. Hand over

Tell the user, briefly:

- where the repo is and which answers shaped it (a short table);
- what they got, grouped (CI, security scanning, releases, AI review, agent config, docs), naming the files worth opening first: `AGENTS.md`, `docs/SETUP.md`, `docs/THREAT_MODEL.md`, and for agentic apps `docs/agent-policy.md`;
- the next step: creating the GitHub repo and applying settings with the `repo-github-setup` skill, which runs the bootstrap script with a dry run first.

Don't create the GitHub repo, push, or set secrets in this skill. Those are visible to others and the user should choose when.
