---
name: repo-template-maintain
description: Maintain the repo-template Copier template itself — bump pinned GitHub Action SHAs, pre-commit hook revs, checksum-verified scanner binaries and tool versions; add or change template questions and files using its [[ ]] / [% %] delimiters; run scripts/test-template.sh across every language combination; and cut a semver tag so generated repos get the change via copier update. Use whenever someone works inside the template repo (copier.yml, template/, test-template.sh), wants to fork it as their own org's template, add a language/tool/workflow/question to it, do the quarterly pin refresh, fix a bug found in a generated repo at the source, or release a new template version.
---

# Maintain the template

Generated repos only improve when the template does, and they only see a change once it's tagged. This skill keeps changes to the template safe: rendered correctly for every answer combination, pinned, tested, and released.

Work in the template repo (the folder with `copier.yml`, `template/`, `scripts/test-template.sh`). If the user is working from this plugin's installed copy, that's read-only cache: have them clone the template repo (or their fork) and work there.

## How the template is put together

- `copier.yml`: questions, computed values (`multi_lang`, `lang_dir`, `baseline`, `is_public`, `has_governance`, `is_oss`), and the post-generation `_tasks`. `lang_dir` maps each managed language to its folder (`lang_dir.python` is `python` or `.`); computed values aren't saved in `.copier-answers.yml`, so renaming one needs no migration.
- `includes/languages.json`: the language profiles, one object per managed language (display name, newest known version, toolchain, lock command, registry, release-please type, Dependabot entry, and the checks AGENTS.md documents). Templates import them from `includes/languages.jinja`, whose header lists the fields; shell reads the JSON with `jq`. Each generated repo gets its own slice as `.github/language-profiles.json`, which `verify-generated.sh` runs (ADR 0006). Change a dev command, registry or ecosystem there and nowhere else.
- Delimiters are `[[ var ]]`, `[% block %]`, `[# comment #]`, chosen so GitHub Actions' `${{ }}` needs no escaping. Never use `{{ }}` for template logic.
- Only files ending in `.jinja` are rendered; the suffix is stripped. A file containing template tags but without `.jinja` is copied verbatim and ships unrendered tags (the test script catches this).
- Conditional files and folders use the tag in the *name*: `[% if agentic %]evals[% endif %]`. An empty rendered name means the file is skipped.
- `trim_blocks` and `lstrip_blocks` are on, so a `[% if %]` on its own line leaves no blank line. Use `[%+ ... %]` or `+%]` where you need to keep the whitespace (see `docs/SETUP.md.jinja`).
- `template/docs/SETUP.md.jinja` is the manual checklist. A GitHub setting is one entry in `template/.github/settings-requirements.json.jinja` (its header lists the fields), plus its line in SETUP.md: `template/scripts/bootstrap-github.sh.jinja` reads the rendered JSON to apply it, and to check it with `--check`, which the `repo-github-setup` audit runs (ADR 0005). Don't write a setting into the bootstrap script or the audit. A secret is one entry in `includes/secrets.jinja` and nothing else; SETUP.md, secrets.md and `.github/secret-requirements.json`, which bootstrap reads, are rendered from it (ADR 0003). `scripts/test-github-settings.sh` runs bootstrap's apply, dry run and check against recorded GitHub API responses in `tests/github-settings/`; a new kind of entry or a new API answer needs a test there.

## Changing things

**Adding a question:** add it to `copier.yml` with `help`, a sensible `default` (often derived from `visibility`), and `when` if it only applies to some languages. Existing repos get it on their next `copier update` with the default unless they pass `-d`, so pick a default that keeps today's behaviour. Document it in the README "Questions" table and in `skills/repo-new/references/choosing-answers.md`.

**Adding a managed language:** start with its profile, one object in `includes/languages.json`. Its key is the language's id, which is also its `languages` choice, its folder in a multi-language repo, its CI job id and its release-please component, so pick one that works as all four. The profile gives it its AGENTS.md commands, its verify checks, its Dependabot entry, its lock step at copy, its release-please type and its registry in SETUP.md. What stays per-language by necessity: its questions in `copier.yml` (with `when: "[[ '<id>' in languages ]]"`), the starter files under `template/[% if '<id>' in languages %][[ lang_dir.<id> ]][% endif %]/`, its `.claude/rules/` file, its job in `ci.yml.jinja` (a central workflow with its own inputs), its publish job in `release.yml.jinja`, its pre-commit hooks, `.gitignore` block and `format.sh` arm, and the prose in README, `docs/dependencies.md` and `docs/verify.md`. Then add an answer set to `test-template.sh`.

**Adding a workflow job:** `permissions: {}` at the workflow level, the narrowest per-job permissions, `persist-credentials: false` on checkout, a `timeout-minutes`, every action pinned to a full SHA with a `# vX.Y.Z` comment, no `pull_request_target`, no `${{ }}` of untrusted input inside `run:` (pass it through `env:`). If the job should block merges, add it to `ci-ok`'s `needs`. zizmor and actionlint enforce most of this.

**Bumping pins** (quarterly, or when a security fix lands):

```bash
bash <this skill's base directory>/scripts/list-pins.sh <template root>
```

It lists every pinned action, hook, scanner binary, `uvx`/`pnpm dlx` tool version and toolchain default, with the latest upstream release and an `<- update` marker. For each one you bump:

- Actions: resolve the tag to its commit, `gh api repos/<owner>/<repo>/commits/<tag> --jq .sha` (this dereferences annotated tags; the tag object SHA is not what `uses:` needs). Replace every occurrence and the version comment. Read the release notes for breaking input changes.
- pre-commit hooks: same SHA lookup; keep the `# frozen: vX` comment format. Update both the root `.pre-commit-config.yaml` and `template/.pre-commit-config.yaml.jinja` where the hook appears in both.
- Gitleaks / OSV-Scanner (in `ZeleMate/workflows`, `security.yml`): update `*_VERSION` and `*_SHA256` together, taking the hash from the release's published checksums file for the exact asset the workflow downloads — never from hashing a download yourself without comparing.
- Copier: generated repos run it from `.github/tools` (`template-update.yml`, and `copier update` in the `repo-template-update` skill), locked in their own `uv.lock`, which Dependabot moves. What the template controls is the floor, `copier>=X` in `template/.github/tools/pyproject.toml.jinja`: raise it to the newest release that's past the cooldown, so new repos' locks and the oldest version Dependabot can leave behind stay current. Raise `_min_copier_version` in `copier.yml` only when the template starts using a newer Copier feature, and never above that floor, or repos on the floor can't update.
- Eval harness (`template/[% if agentic %]evals[% endif %]/run.py`): its dependencies are hash-locked in `run.py.lock` next to it, which neither `list-pins.sh` nor Dependabot tracks. Re-lock it each pin refresh with `uv lock --script run.py --upgrade` (it keeps a 7-day cooldown), bump the `inspect-ai` pin there if needed, and let `test-template.sh` run the mock evals against the new lock. An unlocked script once broke when a transitive dependency shipped an incompatible major version.
- Central workflows (`ZeleMate/workflows`): the CI and security jobs, their action pins, the Gitleaks and OSV-Scanner checksums and the pre-commit/diff-cover/Semgrep lock live in that repo, not here. Change them there, cut a central release, then run `./scripts/bump-central-pin.sh vX.Y.Z` here. Move the template's pin only for a central major, or when the template writes an input that only a newer central release accepts; Dependabot carries generated repos through the rest. A central major needs a template release with the caller edits, because Dependabot ignores majors of `ZeleMate/workflows`.
- Central Go pins (in `ZeleMate/workflows`): golangci-lint's `GOLANGCI_LINT_VERSION` and `GOLANGCI_LINT_SHA256` in `go.yml`, like Gitleaks and OSV-Scanner, and govulncheck and gocover-cobertura in `tools/go/go.mod`, which Dependabot keeps current there. The template's own CI installs the same golangci-lint (`list-pins.sh` shows it as a `binary` row): keep the two equal.
- Newest known versions (Python and Go): one edit each, the `newest` value in `includes/languages.json`, e.g. `"go": {"newest": "1.28"}`. That moves the top of the generated CI version list, the Go that builds release binaries, the template's own CI Go and the `test-template.sh` expectations; `list-pins.sh` shows both as `default` rows. Nothing else restates them, so don't add a copy: Jinja imports them from `includes/languages.jinja`, and shell reads the JSON with `jq`.
- **At each Go release, in this order:** first move the central golangci-lint pin to a build made with the new Go (its release notes say which Go built it) and cut a central release; only then raise Go's `newest`. The other way round turns every Go repo's CI red, because golangci-lint can't lint code for a Go newer than it was built with.
- Respect the same cooldown the template imposes on generated repos: don't adopt a release younger than about 7 days unless it's a security fix.

## Test

```bash
./scripts/test-template.sh <outdir>
```

It generates eleven answer sets from `HEAD` (each language alone, Go public and private, all four together, baseline repos, public/private, agentic or not, publishing or not, both linters and type checkers, a capitalised repo name) and runs `skills/repo-new/scripts/verify-generated.sh` on each: the same checker the skills run on a real repo (actionlint, zizmor, pre-commit, the merge gate, Semgrep, osv-scanner, unrendered tags and the real toolchains). On top of that it asserts things about the template itself, and that verify fails on a deliberately broken repo. A check of a generated repo belongs in verify-generated.sh; only a check of the template belongs in test-template.sh. It needs uv, pnpm and node; cargo, go, golangci-lint, actionlint, zizmor and osv-scanner are optional and skipped when missing — say which were skipped when reporting, because a skipped Rust or Go run proves nothing about that language.

If you added a question or a conditional file, make sure at least one answer set in `test-template.sh` exercises each branch, and add one if not.

## Release

Generated repos track tags: `copier update` and the weekly "template update check" workflow both look for a newer tag.

1. Commit with Conventional Commits (`feat:` new capability, `fix:` bug in generated output, `chore:` pins). A change that needs action in generated repos beyond `copier update` (a new secret, a renamed question) is breaking: `feat!:` and a note in the tag message.
2. With the user's go-ahead, tag semver from the latest tag: `git tag -a vX.Y.Z -m "<summary>"` and push the tag. Bump the plugin's `.claude-plugin/plugin.json` version in the same release when skills changed.
3. Tell the user that generated repos will see an "update available" issue within a week, and that the `repo-template-update` skill handles the update in each one.

## Forking for another org

Someone adopting this for their own org should fork it, then: change the canonical source in `skills/repo-new/references/template-source.md` and the marketplace/plugin manifests in `.claude-plugin/`, revisit defaults in `copier.yml` (owner, visibility, reviewers), and tag a first release. Generated repos record the fork as `_src_path`, so updates come from the fork from then on.
