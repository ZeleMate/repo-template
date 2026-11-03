---
name: repo-template-update
description: Pull a newer version of the repo-template Copier template into a repo generated from it (copier update), answer any new template questions, resolve the merge conflicts with the repo's own changes, verify, and open a PR. Use whenever a "Repo template update available" issue appears, someone asks to update/sync/upgrade a repo from the template, wants the latest CI/security/workflow pins from the template, or asks what changed in the template since their repo was created.
---

# Update a repo from the template

Copier keeps the template version a repo was generated from in `.copier-answers.yml` (`_commit`) and where it came from (`_src_path`). `copier update` re-renders the old version and the new one with the same answers and applies the difference as a 3-way merge, so local edits survive and only real overlaps conflict.

## 1. Preconditions

- `.copier-answers.yml` exists. If it doesn't, the repo was never generated from the template: use the `repo-adopt` skill instead.
- Clean working tree, on a new branch: `git switch -c chore/template-<new-tag>`. Copier refuses to update a dirty tree, and the branch keeps the update reviewable.
- `_src_path` resolves from this machine. If it's a local path that doesn't exist here, read the `repo-new` skill's `references/template-source.md` (in this plugin's `skills/` folder) and ask the user which remote to point it at.

## 2. See what's coming

```bash
current=$(grep '^_commit:' .copier-answers.yml | awk '{print $2}')
src=$(grep '^_src_path:' .copier-answers.yml | awk '{print $2}' | sed 's|^gh:|https://github.com/|')
git ls-remote --tags --refs "$src" | sed 's|.*refs/tags/||' | sort -V
```

Pick the newest tag unless the user wants a specific one. To summarise the changes, clone the template shallowly into a scratch folder and look at `git log --oneline <current>..<new>` and `git diff <current> <new> -- copier.yml`. The `copier.yml` diff tells you about **new questions**: `copier update --defaults` would silently answer them with defaults, so read each new one's help text and ask the user, then pass the answers with `-d key=value`.

## 3. Update

```bash
uvx copier update --trust --defaults --conflict inline --vcs-ref <new-tag> [-d new_key=value ...]
```

`--defaults` reuses every previous answer (Copier would otherwise re-ask them all); `--trust` allows the template's local tasks; `--conflict inline` writes `<<<<<<<`/`>>>>>>>` markers into files rather than `.rej` side files, which are easier to review.

To change an existing answer (say, the repo went public), pass it with `-d` too; the update then also re-renders everything that answer controls.

## 4. Resolve conflicts

```bash
git status --short; grep -rln '^<<<<<<< ' . --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.venv
```

For each conflict, understand both sides before choosing:

- The template side is usually a pin bump (action SHA, hook rev, scanner checksum) or a hardening change. Keep it, and keep pins as full SHAs with version comments.
- The repo side is usually a deliberate local change (an extra CI job, a project-specific ignore). Keep it too; combine rather than pick one.
- If a local change and a template change contradict each other (for example the template now forbids something the repo relies on), ask the user. If they keep the local way, suggest an ADR in `docs/decisions/` so the next update's reviewer knows it's on purpose.

Lockfiles: don't hand-merge them. Take one side and regenerate with the package manager (`uv lock`, `pnpm install --lockfile-only`, `cargo generate-lockfile`).

## 5. Verify and open a PR

```bash
bash <plugin root>/skills/repo-new/scripts/verify-generated.sh .
```

The plugin root is two levels above this skill's base directory. Fix failures caused by the update. If the template itself is broken, report it upstream (the `repo-template-maintain` skill covers fixing it) rather than patching around it here, or the next update conflicts again.

Commit as `chore: update repo template to <new-tag>`. With the user's go-ahead, push and open a PR whose body has the template changelog summary, any new answers given, and how each conflict was resolved. If a "Repo template update available" issue is open, reference it with `Closes #<n>`.

If the update changed `docs/SETUP.md` or `scripts/bootstrap-github.sh`, mention that the GitHub settings may need re-applying after merge (the `repo-github-setup` skill's audit shows it).
