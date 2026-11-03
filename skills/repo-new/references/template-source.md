# Where the template comes from

`copier copy` records the template location in `.copier-answers.yml` (`_src_path`) and the version in `_commit`. Every later `copier update`, and the weekly "template update check" workflow in the generated repo, reads them. So choose a source that will still resolve months from now, from the user's machine and from GitHub Actions.

Pick, in this order:

1. **A source the user names.** A fork (`gh:their-org/repo-template`), a GitHub URL, or a local checkout they maintain.
2. **The canonical template:** `gh:ZeleMate/repo-template`.
3. **This plugin's bundled copy**, only if neither of the above is reachable. The plugin root (the folder holding `copier.yml` and `template/`) is two levels above this skill's base directory. Tell the user that `_src_path` will then be a local path, which `copier update` on another machine and the weekly workflow cannot resolve; they should change `_src_path` to the real remote in `.copier-answers.yml` before relying on updates.

Check reachability and find the version before generating:

```bash
git ls-remote --tags --refs https://github.com/ZeleMate/repo-template | sed 's|.*refs/tags/||' | sort -V | tail -1
```

- Pass that tag as `--vcs-ref`. Copier and the update check both track tags, so a tag gives a clean baseline for later 3-way updates. Use `--vcs-ref HEAD` only when the user explicitly wants unreleased changes (for example while testing the template itself).
- If `ls-remote` fails with an auth error, the template repo is private: the user needs read access, and `gh auth setup-git` (or an SSH key) so git can fetch it. The generated repo's weekly check then also needs a `TEMPLATE_READ_TOKEN` secret (fine-grained PAT, contents:read on the template repo).
