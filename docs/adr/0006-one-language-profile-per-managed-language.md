---
status: accepted
---

# One language profile per managed language, rendered into each repo for the verifier

Every fact about a managed language that more than one file needs lives in its language profile, one object per language in `includes/languages.json`. The object is keyed by the language's `languages` id and grows out of the newest-known-versions file. Its fields are the display name, the newest known version, the toolchain binary, the lock command, the registry, the release-please type, the Dependabot entry, and the language's checks, each with an optional fixing form. Templates import the profiles from `includes/languages.jinja`, and shell reads the JSON with `jq`. As ADR 0003 does for secrets, the template renders the repo's own languages, with answer conditions already resolved, into `.github/language-profiles.json`. `verify-generated.sh` runs the checks listed there and no longer knows any language itself, and the skills read each language's lock command and registry from the same file. Before this, Go's facts were restated across 41 files. Copies had drifted: AGENTS.md documented `cargo clippy --locked` while the verifier ran it without `--locked`.

## Considered Options

- **A Jinja-only module like `includes/secrets.jinja`.** Rejected: shell already reads the newest known versions with `jq`, and a JSON file keeps one format for both readers. The one answer-dependent fact, Python's type checker, fits a small `if` on the check.
- **The verifier keeps its per-language case arms, and a test checks that they match AGENTS.md.** Rejected for the reason ADR 0003 rejected the same idea for secrets: the verifier ships in the plugin and runs against repos of any template version.
- **The verifier falls back to the old arms for repos without the file.** Rejected: that keeps a second copy with no end date. A repo with managed languages and no file fails "language profiles" and is told to run `copier update`. A baseline repo has nothing to check, so it passes.
- **Separate columns for the folder, the CI job id and the release-please component.** Rejected: all three equal the id today, and a column would only invite drift. The invariant is stated in the profile's header. actionlint and the merge-gate check fail if a job id ever stops matching.
- **Profiles for the per-file formatter in `format.sh`, the pre-commit hooks and `.gitignore` blocks.** Rejected: each is written in one place only, and is shell or config with its own control flow, not a fact that other files restate.

## Consequences

- **AGENTS.md shows one command per line**, each check's fixing form where it has one. It also gains the build step. TypeScript's test line becomes `pnpm run test:coverage`, matching Python's `pytest --cov` and CI. A repo sees this as an AGENTS.md change on its next `copier update`.
- **The verifier runs what CI runs.** That includes clippy with `--locked`, nextest, cargo-deny and the builds, whenever their tools are installed. The template's own CI installs cargo-nextest and cargo-deny, so every Rust check runs there.
- **One computed `lang_dir` map replaces `py_dir`, `ts_dir`, `rs_dir` and `go_dir`.** Computed values aren't saved in `.copier-answers.yml`, so no repo needs a migration. `go_module`'s default reads `multi_lang` and `lang_dir` instead of re-deriving them.
- **One copy-time task runs every language's lock step.** When a toolchain is missing it prints a note instead of failing, which the Rust task already did. A TypeScript repo generated without pnpm therefore gets a note at copy time, and the verifier's frozen install fails later.
- **What stays per-language by necessity:** the questions and their `when`, starter files, `.claude/rules/`, the CI job inputs (each language calls its own central workflow), the publish jobs, pre-commit hooks, `.gitignore` blocks, `format.sh` arms, and the prose in README, `docs/dependencies.md` and `docs/verify.md`.
- **Adding a fifth language** means one profile entry plus the files listed above. It no longer means edits to the verifier, Dependabot, release-please, SETUP.md or AGENTS.md.
