---
name: repo-template-maintain
description: Maintain the repo-template Copier template itself — bump pinned GitHub Action SHAs, pre-commit hook revs, checksum-verified scanner binaries and tool versions; add or change template questions and files using its [[ ]] / [% %] delimiters; run scripts/test-template.sh across every language combination; and cut a semver tag so generated repos get the change via copier update. Use whenever someone works inside the template repo (copier.yml, template/, test-template.sh), wants to fork it as their own org's template, add a language/tool/workflow/question to it, do the quarterly pin refresh, fix a bug found in a generated repo at the source, or release a new template version.
---

# Maintain the template

Generated repos only improve when the template does, and they only see a change once it's tagged. This skill keeps changes to the template safe: rendered correctly for every answer combination, pinned, tested, and released.

Work in the template repo (the folder with `copier.yml`, `template/`, `scripts/test-template.sh`). If the user is working from this plugin's installed copy, that's read-only cache: have them clone the template repo (or their fork) and work there.

## How the template is put together

- `copier.yml`: questions, computed values (`multi_lang`, `py_dir`/`ts_dir`/`rs_dir`, `is_public`, `has_governance`, `is_oss`), and the post-generation `_tasks`.
- Delimiters are `[[ var ]]`, `[% block %]`, `[# comment #]`, chosen so GitHub Actions' `${{ }}` needs no escaping. Never use `{{ }}` for template logic.
- Only files ending in `.jinja` are rendered; the suffix is stripped. A file containing template tags but without `.jinja` is copied verbatim and ships unrendered tags (the test script catches this).
- Conditional files and folders use the tag in the *name*: `[% if agentic %]evals[% endif %]`. An empty rendered name means the file is skipped.
- `trim_blocks` and `lstrip_blocks` are on, so a `[% if %]` on its own line leaves no blank line. Use `[%+ ... %]` or `+%]` where you need to keep the whitespace (see `docs/SETUP.md.jinja`).
- `template/docs/SETUP.md.jinja` is the manual checklist and `template/scripts/bootstrap-github.sh.jinja` is the automated part. When you add anything that needs a secret, an app or a GitHub setting, update both — and the `repo-github-setup` skill's `scripts/audit-github.sh` in this plugin if the setting can be read from the API.

## Changing things

**Adding a question:** add it to `copier.yml` with `help`, a sensible `default` (often derived from `visibility`), and `when` if it only applies to some languages. Existing repos get it on their next `copier update` with the default unless they pass `-d`, so pick a default that keeps today's behaviour. Document it in the README "Questions" table and in `skills/repo-new/references/choosing-answers.md`.

**Adding a workflow job:** `permissions: {}` at the workflow level, the narrowest per-job permissions, `persist-credentials: false` on checkout, a `timeout-minutes`, every action pinned to a full SHA with a `# vX.Y.Z` comment, no `pull_request_target`, no `${{ }}` of untrusted input inside `run:` (pass it through `env:`). If the job should block merges, add it to `ci-ok`'s `needs`. zizmor and actionlint enforce most of this.

**Bumping pins** (quarterly, or when a security fix lands):

```bash
bash <this skill's base directory>/scripts/list-pins.sh <template root>
```

It lists every pinned action, hook, scanner binary, `uvx`/`pnpm dlx` tool version and toolchain default, with the latest upstream release and an `<- update` marker. For each one you bump:

- Actions: resolve the tag to its commit, `gh api repos/<owner>/<repo>/commits/<tag> --jq .sha` (this dereferences annotated tags; the tag object SHA is not what `uses:` needs). Replace every occurrence and the version comment. Read the release notes for breaking input changes.
- pre-commit hooks: same SHA lookup; keep the `# frozen: vX` comment format. Update both the root `.pre-commit-config.yaml` and `template/.pre-commit-config.yaml.jinja` where the hook appears in both.
- Gitleaks / OSV-Scanner (in `ZeleMate/workflows`, `security.yml`): update `*_VERSION` and `*_SHA256` together, taking the hash from the release's published checksums file for the exact asset the workflow downloads — never from hashing a download yourself without comparing.
- Eval harness (`template/[% if agentic %]evals[% endif %]/run.py`): its dependencies are hash-locked in `run.py.lock` next to it, which neither `list-pins.sh` nor Dependabot tracks. Re-lock it each pin refresh with `uv lock --script run.py --upgrade` (it keeps a 7-day cooldown), bump the `inspect-ai` pin there if needed, and let `test-template.sh` run the mock evals against the new lock. An unlocked script once broke when a transitive dependency shipped an incompatible major version.
- Central workflows (`ZeleMate/workflows`): the CI and security jobs, their action pins, the Gitleaks and OSV-Scanner checksums and the pre-commit/diff-cover/Semgrep lock live in that repo, not here. Change them there, cut a central release, then run `./scripts/bump-central-pin.sh vX.Y.Z` here. Move the template's pin only for a central major, or when the template writes an input that only a newer central release accepts; Dependabot carries generated repos through the rest. A central major needs a template release with the caller edits, because Dependabot ignores majors of `ZeleMate/workflows`.
- Respect the same cooldown the template imposes on generated repos: don't adopt a release younger than about 7 days unless it's a security fix.

## Test

```bash
./scripts/test-template.sh <outdir>
```

It generates five answer sets (each language alone, all three together, public/private, agentic or not, publishing or not, both linters and type checkers) from `HEAD`, then runs actionlint, zizmor, pre-commit, a check for unrendered tags, and the real toolchains on each output. It needs uv, pnpm and node; cargo, actionlint and zizmor are optional and skipped when missing — say which were skipped when reporting, because a skipped Rust run proves nothing about Rust.

If you added a question or a conditional file, make sure at least one answer set in `test-template.sh` exercises each branch, and add one if not.

## Release

Generated repos track tags: `copier update` and the weekly "template update check" workflow both look for a newer tag.

1. Commit with Conventional Commits (`feat:` new capability, `fix:` bug in generated output, `chore:` pins). A change that needs action in generated repos beyond `copier update` (a new secret, a renamed question) is breaking: `feat!:` and a note in the tag message.
2. With the user's go-ahead, tag semver from the latest tag: `git tag -a vX.Y.Z -m "<summary>"` and push the tag. Bump the plugin's `.claude-plugin/plugin.json` version in the same release when skills changed.
3. Tell the user that generated repos will see an "update available" issue within a week, and that the `repo-template-update` skill handles the update in each one.

## Forking for another org

Someone adopting this for their own org should fork it, then: change the canonical source in `skills/repo-new/references/template-source.md` and the marketplace/plugin manifests in `.claude-plugin/`, revisit defaults in `copier.yml` (owner, visibility, reviewers), and tag a first release. Generated repos record the fork as `_src_path`, so updates come from the fork from then on.
