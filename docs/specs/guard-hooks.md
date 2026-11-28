# Spec: guard hooks

Generated repos get **guards**: more permission rules, plus one `PreToolUse` hook, `.claude/hooks/guard.sh`. Together they stop or ask before agent actions that today's rules in `.claude/settings.json` miss when the action is phrased a little differently. This spec covers the template side (`template/.claude/`, `copier.yml`, `AGENTS.md`), the `repo-adopt` skill and `verify-generated.sh`, and the tests in `test-template.sh`.

Terms (generated repo, baseline repo, merge gate, guard) are defined in [CONTEXT.md](../../CONTEXT.md).

This spec comes from the map [Generated repos guard risky agent actions with hooks](https://github.com/ZeleMate/repo-template/issues/85). Each section names the closed tickets it comes from. The research behind it is [claude-code-guard-hooks.md](../research/claude-code-guard-hooks.md), and the local probe results are on [Do the guard rules and a PreToolUse hook behave as the docs say?](https://github.com/ZeleMate/repo-template/issues/98).

No ADR: no decision here is hard to reverse. The guards are copied files that a template release can change, and a repo can remove any of them.

Out of scope:
- Guard hooks for this template repo itself.
- Claude Code's OS sandbox settings in generated repos.

**Status (2026-11-28):** specified, not built.

## 1. What the guards are for

_From [Which agent actions should a generated repo's guard hooks block or ask about?](https://github.com/ZeleMate/repo-template/issues/97)._

**Guardrails against honest mistakes, not a security boundary.** An agent that means well rephrases its way around a rule. For example, after `pnpm publish` is denied it tries `pnpm -r publish`, or it force-pushes with `+main` without knowing that's a force push. The guards catch the usual phrasings and say why they stopped the command.

They aren't a boundary, for these reasons:
- A hook lets the command through when it crashes, times out or gets invalid JSON.
- It doesn't run until the folder is trusted in an interactive session.
- Without managed settings, an installed mod can override its deny.
- A determined agent can write a script that does the same thing.

The boundary stays on GitHub and with the registries: the `main` ruleset, the merge gate, push protection, and registry credentials the agent doesn't have. `AGENTS.md` says so (section 5).

**Guarded:**
1. Rewordings of what today's rules already deny or ask about. Each rewording gets the strictness of the rule it rewords, and every force-push form is denied.
2. Hand edits to lockfiles: deny.
3. Hand edits to `.copier-answers.yml`: ask.

**Not guarded, and why** (also in `AGENTS.md`):

| Action | Why not |
|---|---|
| `git commit --no-verify` / `-n` / `SKIP=…` | The central `repo-lint` job runs the same pre-commit hooks in CI, and the merge gate fails. |
| Edits under `.github/workflows/` | Normal work (`ci-local.yml`), so a guard would interrupt too often. |
| Deleting or emptying tests | Can't be detected reliably. |
| Reading `.env` through Bash without naming it, or through an interpreter (`grep -r`, `python -c "open('.env')"`, `source .env`) | Telling a read apart from setup (`cp .env.example .env`) means parsing each tool's arguments. The `Read` deny rules already cover `cat`, `head`, `tail`, `sed` and redirects. |

## 2. Permission rules

_From [Which agent actions should a generated repo's guard hooks block or ask about?](https://github.com/ZeleMate/repo-template/issues/97), [Do the guard rules and a PreToolUse hook behave as the docs say?](https://github.com/ZeleMate/repo-template/issues/98) and [Do baseline repos get the guards, and how does repo-adopt bring them in?](https://github.com/ZeleMate/repo-template/issues/100)._

Changes to `template/.claude/settings.json.jinja`. Every answer set gets them, baseline repos included, except where a row says otherwise.

**`deny`, new:**

| Rule | Catches | Note |
|---|---|---|
| `Bash(git push *--force*)` | `--force` anywhere, `--force-with-lease`, `--force-if-includes` | Replaces `Bash(git push --force *)`, which it covers |
| `Bash(git push * -f)` | `-f` after the refspec | `Bash(git push -f *)` stays for `-f` first |
| `Bash(git push * +*)` | `+main`, a forced refspec | Quoted `'+main'` gets past it; the hook catches that |
| `Bash(gh api --method DELETE *)` | the long option spelling | |
| `Bash(gh api * -X DELETE*)` | the method after the path | `Bash(gh api -X DELETE *)` stays |
| `Bash(gh api * --method DELETE*)` | the long spelling after the path | _Added while writing this spec_, for symmetry with the row above |
| `Bash(gh api *actions/secrets*)` | the REST equivalent of `gh secret`, reads included, like `gh secret *` | |
| `Bash(npm * publish)`, `Bash(npm * publish *)` | an option before `publish` (`npm --workspace a publish`) | _Changed while writing:_ the ticket wrote `npm * publish*`, which also matches `npm run publish-docs`. Two rules ending on a word boundary avoid that |
| `Bash(pnpm * publish)`, `Bash(pnpm * publish *)` | `pnpm -r publish`, `pnpm --filter a publish` | As above |
| `Bash(uv * publish)`, `Bash(uv * publish *)`, `Bash(cargo * publish)`, `Bash(cargo * publish *)` | `uv --directory x publish`, `cargo +nightly publish` | _Added while writing_: same reasoning as npm and pnpm |
| `Edit(**/uv.lock)` | hand edits to every `uv.lock`, including `.github/tools/uv.lock` | **Always**: every repo has `.github/tools/uv.lock`. Covers Write, new files and the root lockfile (probe) |
| `Edit(**/pnpm-lock.yaml)` | | Only with `'typescript' in languages` |
| `Edit(**/Cargo.lock)` | | Only with `'rust' in languages` |
| `Edit(**/go.sum)` | | Only with `'go' in languages` |

Render the lockfile rules from the managed languages rather than as four `if`s, so adding a language through `copier update` adds its rule. A repo's own lockfiles that the template doesn't manage (`poetry.lock`, `bun.lock`) get no rule; the repo can add one.

**`ask`, new:** `Edit(./.copier-answers.yml)`. Not deny, because `repo-adopt` legitimately fixes `_src_path`. Copier writes the file through Bash, so `copier update` never hits this rule.

**`hooks`, new:** a `PreToolUse` entry next to the existing `PostToolUse` one.

```json
"PreToolUse": [
  {
    "matcher": "Bash",
    "hooks": [
      { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/guard.sh", "timeout": 10 }
    ]
  }
]
```

There's no `if` filter, because the docs call it best-effort.

**What the probe confirmed** (Claude Code 2.1.302, 2026-11-28):
- Patterns with `*` in the middle match as written.
- Matching is case-sensitive.
- `env` and `sudo` (with flags) in front of a command are seen through.
- `eval`, `bash -c` and quoted words aren't seen through.
- An `Edit(**/…)` deny also stops Write.

## 3. The guard hook

_From [How is the guard hook written, and how does test-template.sh test it?](https://github.com/ZeleMate/repo-template/issues/99), with facts from [Do the guard rules and a PreToolUse hook behave as the docs say?](https://github.com/ZeleMate/repo-template/issues/98)._

**File:** `template/.claude/hooks/guard.sh`, written in bash + `jq` like `format.sh`. It's a plain file, not `.jinja`, because it depends on no answer. The `chmod +x` task in `copier.yml` gains it:

```yaml
- command: chmod +x scripts/bootstrap-github.sh .claude/hooks/format.sh .claude/hooks/guard.sh
```

**Input:** the hook JSON on stdin. It reads only `.tool_input.command`.

**Where the patterns come from:** `"$CLAUDE_PROJECT_DIR"/.claude/settings.json`, read when the hook runs:

```bash
jq -r --arg k deny '.permissions[$k][]? | select(startswith("Bash(")) | ltrimstr("Bash(") | rtrimstr(")")'
```

It reads the same for `ask`. Each pattern is matched with bash's `[[ $cmd == $pattern ]]`, with `$pattern` unquoted so bash treats it as a pattern. The script must run under bash (`#!/usr/bin/env bash`), because zsh would compare the text literally. Claude Code rules use only `*`, which bash patterns treat the same way. Claude Code's trailing ` *` also matches the bare command (`Bash(git push *)` matches `git push`), so a pattern that ends in ` *` is tried a second time without that ending. Using one source means the hook and the rules can't drift apart, and rules a repo adds are covered too. Only the project's `settings.json` is read, not `settings.local.json` or the user's settings.

**Normalization.** Claude Code's rules have already judged the command as written, so the hook re-checks only the **parts that normalizing changed**. For each part, it never runs or expands anything, and `$(…)` stays as text:
1. **Split** on `&&`, `||`, `;`, `|`, `&` and newlines.
2. **Split each part into words** with `xargs printf '%s\n'`, which handles single quotes, double quotes and backslashes without running anything. If `xargs` gives up (unbalanced quotes), skip that part.
3. **Unwrap** `bash -c`, `sh -c` and `zsh -c` (take the quoted string) and `eval …`, one level deep. Normalize the result again from step 1.
4. **Strip** leading `VAR=value`, `env` and its assignments, `sudo` and its flags, and Claude Code's wrapper list: `timeout <d>`, `time`, `nice [-n N]`, `nohup`, `stdbuf <opts>`, `command`, `builtin`, `noglob`, and bare `xargs`.
5. **Program path to its name:** `/usr/bin/git` becomes `git`.
6. **Drop global options.**
   - git: `-C <dir>`, `-c <k=v>`, `--git-dir[=]<d>`, `--work-tree[=]<d>`, `--no-pager`.
   - gh: `-R <x>`, `--repo[=]<x>`.
7. **Upper-case the HTTP method** after `-X` or `--method`, and split `-X<method>` or `--method=<method>` into two words first, so `-Xdelete` becomes `-X DELETE`.

Words are joined back with single spaces and without quotes, so `git -C . push origin '+main'` becomes `git push origin +main`.

**A check of its own, applied to every part:** `gh api` with a method of `POST`, `PATCH`, `PUT` or `DELETE` (after step 7) and a word containing `/releases` is denied. It does the same as the denied `gh release create` and `gh release upload`. Release reads pass.

**What it returns:**
- **Deny:** exit 2. Stderr gets one line, which Claude sees: `guard: "<normalized>" (from "<original part>") matches deny rule Bash(<pattern>)`, or `… is a gh api write to releases`.
- **Ask:** exit 0, with this on stdout: `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"guard: … matches ask rule Bash(<pattern>)"}}`.
- **No match:** exit 0 with no output, so the normal permission flow carries on.
- **Parts that match differently:** deny wins over ask, the same order Claude Code uses.

**Failure:** it lets the command through silently (exit 0). That covers a missing `jq`, an unreadable or invalid `settings.json`, `xargs` giving up, and a timeout (Claude Code doesn't block on a hook timeout either). Claude Code's own rules still apply.

**Known gaps** (`AGENTS.md` lists the short form):
- heredocs, nested quoting, aliases and functions, and anything else that needs real shell parsing;
- a second level of `bash -c` inside `bash -c`;
- `gh api` writes with no `-X`, which become POST implicitly once `-f` or `-F` fields are passed;
- everything in section 1's "not guarded" table.

## 4. Baseline repos, `repo-adopt` and `copier update`

_From [Do baseline repos get the guards, and how does repo-adopt bring them in?](https://github.com/ZeleMate/repo-template/issues/100)._

**Baseline repos** (`languages: []`) get everything in sections 2 and 3 except the language-specific lockfile rules. The existing `npm`, `pnpm`, `uv` and `cargo` publish denies already render there and do no harm where those tools aren't used. Other stacks' commands (`bun publish`) are the repo's own call.

**`repo-adopt`** (`skills/repo-adopt/SKILL.md`):
- **Merge table:** `.claude/settings.json` belongs to the "Exists and is pure config" row. The template's file is the base, and the repo's own `allow`, `deny`, `ask` and `hooks` entries are added. The repo's own `PreToolUse` hooks stay next to `guard.sh`: they run in parallel and deny wins.
- **Step 4:** a line saying that where the repo allows something a template deny covers, the deny wins (deny beats allow). List each case in the PR body instead of removing the template's rule.
- `guard.sh` is a new file under the "Doesn't exist in the repo" row. Copy it with its executable bit; `verify-generated.sh` checks it (section 6).
- The path-fixing step needs nothing new, because `guard.sh` contains no paths.

**`copier update`:**
- `settings.json` gets Copier's normal 3-way merge, and `repo-template-update` resolves conflicts with the repo's own rule edits as usual.
- Because the hook reads the rules when it runs, the repo's edits apply to it with no extra step.
- The `chmod +x` task runs on every update, so `guard.sh` stays executable.

**Switching a guard off:**
- **One guard:** remove its rule from `.claude/settings.json`.
- **The hook:** remove its `PreToolUse` entry there.

Both are local changes that later updates keep. Deleting `guard.sh` isn't the documented way (see [Not verified](#not-verified)).

## 5. Generated docs

_From [Which agent actions should a generated repo's guard hooks block or ask about?](https://github.com/ZeleMate/repo-template/issues/97) and [Do baseline repos get the guards, and how does repo-adopt bring them in?](https://github.com/ZeleMate/repo-template/issues/100)._

`AGENTS.md` is rendered for every repo. Baseline repos have no README, so this text goes in `AGENTS.md` rather than in the README. Under **Security rules**, add:

> - `.claude/settings.json` and `.claude/hooks/guard.sh` stop or ask before publishing, force pushes, secret and release changes through `gh`, hand edits to lockfiles, and edits to `.copier-answers.yml`, including the usual rewordings (`bash -c`, `git -C`, `+main`, `--method DELETE`). They are guardrails for honest mistakes, not a security boundary: when a guard stops you, don't look for another way to do the same thing; say what you wanted to do and ask. The guard hook needs `jq` and lets the command through without it. Not guarded: `--no-verify` (CI runs the same hooks), workflow edits, test deletion, and reading `.env` through a script. To switch a guard off, remove its rule, or the hook's `PreToolUse` entry, from `.claude/settings.json`.

The existing "Never edit lockfiles by hand" line under Dependencies stays as it is. The deny now enforces it.

No change to `REVIEW.md`, `docs/THREAT_MODEL.md`, `SETUP.md` or the README.

## 6. Tests

_From [How is the guard hook written, and how does test-template.sh test it?](https://github.com/ZeleMate/repo-template/issues/99)._

**`verify-generated.sh`:** one new check, "guard hook executable" (`test -x .claude/hooks/guard.sh`). `repo-adopt` and `repo-template-update` then get it for free.

**`test-template.sh`:** a table test in the style of the `go-major-version` rows. It runs against the rendered `guard.sh` in two answer sets, `py` and `base-priv`, so it uses real rendered rules. Each row feeds `{"tool_input":{"command":"<cmd>"}}` on stdin with `CLAUDE_PROJECT_DIR` set to the answer set's directory. It expects exit 2 for **deny**, exit 0 plus `"permissionDecision":"ask"` for **ask**, and exit 0 with empty stdout for **pass**.

| Command | Expect | Why |
|---|---|---|
| `git push origin '+main'` | deny | quoting (probe miss) |
| `git push origin "+main"` | deny | quoting (probe miss) |
| `git -C . push -f` | deny | git global option |
| `git -c push.default=current push --force` | deny | git global option |
| `/usr/bin/git push -f origin main` | deny | absolute path |
| `bash -c 'npm publish'` | deny | unwrap (probe miss) |
| `sh -c "cd x && pnpm publish"` | deny | unwrap and split |
| `eval npm publish` | deny | `eval` (probe miss) |
| `gh api -X delete repos/o/r` | deny | method case (probe miss) |
| `gh api repos/o/r --method delete` | deny | method case, after the path |
| `gh api -X POST repos/o/r/releases` | deny | the script's own releases check |
| `gh api --method PATCH repos/o/r/releases/1` | deny | as above |
| `gh -R o/r pr merge 5` | ask | gh global option before an ask rule |
| `git -C . push origin main` | ask | git global option before an ask rule |
| `git -C . status` | pass | normal worktree use |
| `git push origin main` | pass | unchanged; Claude Code's ask rule handles it |
| `gh api repos/o/r/releases` | pass | a read |
| `bash -c 'echo hi'` | pass | unwrapped, nothing matches |
| `cp .env.example .env` | pass | setup, not guarded |
| `npm run publish-docs` | pass | not `publish` (section 2) |
| `git push origin 'unbalanced` | pass | `xargs` gives up, so it fails open |
| `git -C . push -f`, with `jq` removed from `PATH` | pass | fails open |

Plus one check per answer set that the rendered `settings.json` contains every rule in section 2 that applies to it, and that a baseline repo has `Edit(**/uv.lock)` but not `Edit(**/pnpm-lock.yaml)`. No Claude Code call is needed, so the test is free and runs in the template's CI as it is.

## Not verified

| Fact | From | Checked by |
|---|---|---|
| Claude Code matches the word-boundary rules `Bash(npm * publish)` and `Bash(npm * publish *)` the way bash does: it denies `npm --workspace a publish` and lets `npm run publish-docs` through. The probe tested only `* publish*` | section 2 | a `claude -p` run like the probe's, step 3 |
| BSD `xargs` (macOS) and GNU `xargs` (Linux) split the table's commands identically | section 3 | `test-template.sh`, locally (macOS) and in CI (Linux), step 3 |
| The hook adds no noticeable delay to Bash calls | section 3 | the live check, step 4 |
| A real interactive session shows the hook's ask prompt and deny reason as described | sections 2 and 3 | the live check, step 4 |
| `copier update` recreates a `guard.sh` that a repo deleted | section 4 | left open; the docs point at `settings.json` instead |

Already checked, by the probe on [Do the guard rules and a PreToolUse hook behave as the docs say?](https://github.com/ZeleMate/repo-template/issues/98):
- The rule patterns, case sensitivity, prefixes and quoting.
- A hook's exit-2 deny holds in `default`, `acceptEdits`, `dontAsk`, `auto` and `bypassPermissions`.
- `Edit(**/uv.lock)` also stops Write.

## Build checklist

1. **Template.** Make the changes in sections 2, 3 and 5: `settings.json.jinja`, the new `guard.sh`, the `chmod` task in `copier.yml`, and `AGENTS.md.jinja`.
2. **Plugin.**
   - Add the `repo-adopt` lines in section 4.
   - Add the `verify-generated.sh` check and the `test-template.sh` rows in section 6.
   - In the `repo-template-update` skill, add one line: after an update, a conflict in `.claude/settings.json` keeps the repo's own rules.
3. **Test.** Run `test-template.sh` locally. Every answer set passes, and so do the table rows in `py` and `base-priv`. Push, and the template's CI runs the same rows on Linux.
4. **Live check.** Generate a repo from the branch, then in an interactive Claude Code session there (folder trusted), ask the agent to run three commands without executing anything harmful:
   - `git -C . push origin '+main'` against a remote that doesn't exist: expect a deny with the guard's reason.
   - `gh -R o/r pr merge 1`: expect an ask prompt that shows the reason.
   - an edit to `.github/tools/uv.lock`: expect a deny.

   Note any delay.
5. **Release.** A minor template and plugin release. Generated repos get the guards through `copier update`.
