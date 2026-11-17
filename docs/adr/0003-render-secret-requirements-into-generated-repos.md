---
status: accepted
---

# Render each repo's secret requirements into the repo; the audit reads them and recomputes nothing

The template's secret requirements live in one Jinja data file, `includes/secrets.jinja`, outside the `template/` subdirectory so Copier never renders it. `docs/SETUP.md`, `docs/secrets.md` and `scripts/bootstrap-github.sh` import it. The template also renders the requirements that apply to a repo, with answer conditions already evaluated, into `.github/secret-requirements.json`. The `repo-github-setup` audit reads that file and no longer derives secrets from `.copier-answers.yml`. Before this, the rule for which secret applies and when was written in six places across Jinja, shell and Python, and fix commits #21, #35 and #36 each changed some copies but not others.

## Considered Options

- **The audit keeps its own copy of the rules, and a test checks that the copies agree.** Rejected: the audit lives in the plugin and runs against repos of any template version, so it would have to know every past version's rules. It also can't read `baseline` or `has_governance`, because computed answers aren't saved to the answers file.
- **A computed answer in `copier.yml` holding the list.** Rejected: multi-line setup text and per-entry conditions are awkward there, and `copier.yml` is for questions.
- **The audit falls back to the old logic for repos without the file.** Rejected: that keeps a second copy with no end date. There are only a few generated repos, and the weekly template update check already prompts them to update.

## Consequences

- **Conditions that are only known once the repo exists** (whether `release.yml` is disabled, whether the template repo is private) appear in the file as `waived_if` and `only_if` fields from a small fixed set. The audit implements each kind of check once and doesn't know which secret it applies to.
- **A repo without the file gets `?` for secrets in the audit, not drift**, until it runs `copier update`.
- **The JSON omits the setup instructions**, so editing their text doesn't cause conflicts in `copier update`.
- **Workflows still name their own secrets.** `test-template.sh` fails when the rendered Actions secret requirements differ from the `secrets.X` names in the rendered workflows, for every answer set.
- Adding a secret means adding one entry to `includes/secrets.jinja`, plus the workflow that uses it.
