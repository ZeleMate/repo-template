# What a PreToolUse hook can see and block, and where permission rules fall short

Question ([#96](https://github.com/ZeleMate/repo-template/issues/96), on map [#85](https://github.com/ZeleMate/repo-template/issues/85)): what can a Claude Code `PreToolUse` hook see and block, how does it combine with permission rules and settings scopes, and which commands slip past the deny/ask rules in `template/.claude/settings.json.jinja`?

**Short answer.** A `PreToolUse` hook gets the raw tool input as JSON on stdin (for Bash, the full `command` string, unparsed). It blocks with exit 2 or `permissionDecision: "deny"`, forces a prompt with `"ask"`, and can never loosen a deny or ask rule. Permission rules already split compound commands and see past env prefixes and a fixed set of wrappers, so `cd x && npm publish` and `FOO=1 npm publish` are caught. They match command text after the program name, though, so `bash -c '…'`, `/usr/bin/git …`, `git -C . push …`, flags placed after the subcommand's arguments, `git push origin +main`, and `gh api --method DELETE …` all get past the template's deny rules; several get past the `git push *` ask rule too. The docs themselves say a Bash deny/ask rule "isn't a security boundary around the program" and point to hooks or the sandbox for that.

Sources: Claude Code docs at code.claude.com, read 2026-11-28: [Hooks reference](https://code.claude.com/docs/en/hooks), [Configure permissions](https://code.claude.com/docs/en/permissions), [Permission modes](https://code.claude.com/docs/en/permission-modes), [Settings files and precedence](https://code.claude.com/docs/en/settings). Git's [`git push` manual](https://git-scm.com/docs/git-push) for refspecs. Local Claude Code is 2.1.302. A local `claude -p` probe of the rule-matching cases was attempted but couldn't authenticate, so nothing below is locally verified; "unverified" marks claims that rest on reading the docs alone.

## What the template has today

From `template/.claude/settings.json.jinja` and `template/.claude/hooks/format.sh.jinja`:

- **deny:** `Read` of `.env`, `.env.*` (root and `**/`), `**/*.pem`, `**/*.key`; `Bash(npm publish *)`, `Bash(pnpm publish *)`, `Bash(uv publish *)`, `Bash(cargo publish *)`, `Bash(git push --force *)`, `Bash(git push -f *)`, `Bash(gh release create *)`, `Bash(gh release upload *)`, `Bash(gh secret *)`, `Bash(gh api -X DELETE *)`; plus five SonarQube MCP write tools when `quality_platform == 'sonarqube-cloud'`.
- **ask:** `Bash(git push *)`, `Bash(gh pr merge *)`.
- **hooks:** one `PostToolUse` hook on `Edit|Write`, `"$CLAUDE_PROJECT_DIR"/.claude/hooks/format.sh`, timeout 60. It reads `.tool_input.file_path` with `jq` and always exits 0. If `jq` is missing it exits 0 and does nothing.

## What a PreToolUse hook sees

- **Input arrives on stdin as JSON** for command hooks ([Hooks, input](https://code.claude.com/docs/en/hooks)). Common fields: `session_id`, `transcript_path`, `cwd`, `permission_mode` (`default`, `plan`, `acceptEdits`, `auto`, `dontAsk`, `bypassPermissions`), `hook_event_name`. `PreToolUse` adds `tool_name`, `tool_input` and `tool_use_id`.
- **Bash `tool_input`:** `command`, `description`, `timeout`, `run_in_background`. The doc's example is `{"command": "npm test", "description": "Run test suite", "timeout": 120000, "run_in_background": false}`. The hook gets the raw command string; Claude Code's subcommand splitting and wrapper stripping are not passed to it, so a hook that wants them has to parse the string itself.
- **Edit `tool_input`:** `file_path`, `old_string`, `new_string`, `replace_all` (boolean, default `false`). **Write:** `file_path`, `content`. For `Write`, `Edit` and `Read`, "`tool_input.file_path` is always absolute" (backslashes on Windows).
- **`cwd`** follows Claude into a worktree; **`${CLAUDE_PROJECT_DIR}`** "stays put: it still points at the project root where the session started" ([Hooks](https://code.claude.com/docs/en/hooks)).

## How a hook blocks or asks

From [Hooks, exit codes and PreToolUse decision control](https://code.claude.com/docs/en/hooks):

- **Exit 0:** Claude Code applies any JSON on stdout. With no decision, the call goes "through the normal permission flow". "The hook can deny the call, but staying silent doesn't approve it."
- **Exit 2:** blocks the tool call; stderr is the reason Claude sees. It "routes the same way as `"deny"`", and the call "stays blocked even if you return `"allow"`".
- **Any other exit code, a hook that fails to start, or invalid JSON:** non-blocking error, the action goes ahead. The docs warn: "If your hook is meant to enforce a policy, use `exit 2`."
- **Timeout:** "On `PreToolUse`, a timed-out command, http, or mcp_tool hook doesn't block the tool call… don't count on a stalled hook to act as a gate." Default timeout for `command` hooks is 600 s.
- **JSON decision** in `hookSpecificOutput` with `hookEventName: "PreToolUse"`:
  - `permissionDecision`: `"allow"` skips the prompt (with exceptions below), `"deny"` prevents the call, `"ask"` prompts the user, `"defer"` ends the turn for later resumption and needs `-p`.
  - `permissionDecisionReason`: shown to the user for `ask`, to Claude for `deny`, only logged for `allow`/`defer`.
  - `updatedInput`: replaces the whole input object; pair with `allow` or `ask`.
  - `additionalContext`: text added to Claude's context next to the tool result.
  - Top-level `decision`/`reason` (`approve`/`block`) are deprecated for this event and map to `allow`/`deny`.
  - `continue: false` "doesn't block a `PreToolUse` tool call"; return `permissionDecision: "deny"` for that.
- **Several hooks disagreeing:** "precedence is `deny` > `defer` > `ask` > `allow`". Matching hooks run in parallel, and an identical handler defined in several settings files runs once.

## Matchers and the `if` field

From [Hooks, matcher patterns](https://code.claude.com/docs/en/hooks):

- `"*"`, `""` or omitted matches every tool. A value of only letters, digits, `_`, `-`, spaces, `,` and `|` is an exact name or a list (`Edit|Write`, `Edit, Write`). Anything else is an unanchored JavaScript regex, so `Edit.*` also matches `NotebookEdit`; use `^Edit$` for an exact match. MCP tools are `mcp__<server>__<tool>`, and a whole server needs `mcp__memory__.*`.
- A handler can carry `"if": "Bash(git *)"`, one permission rule matched against tool name and arguments. For Bash it "checks each subcommand", so `Bash(git *)` matches `npm test && git push`. The docs also call `if` "best-effort" and say: "use the permission system rather than a hook to enforce a hard allow or deny." A guard that must not miss a command should run on `matcher: "Bash"` without `if` and inspect the command itself.

## How hooks combine with permission rules, modes and settings

- **Rule order:** deny, then ask, then allow; first match wins, and specificity doesn't change it ([Permissions, manage permissions](https://code.claude.com/docs/en/permissions#manage-permissions)).
- **A hook can tighten, never loosen.** "PreToolUse hook decisions don't bypass permission rules… a matching deny rule blocks the call, and a matching ask rule still prompts even when the hook returned `"allow"` or `"ask"`" ([Permissions, precedence among rules, hooks, and mods](https://code.claude.com/docs/en/permissions#precedence-among-rules-hooks-and-mods)). In the other direction, "A hook that exits with code 2 stops the tool call before permission rules are evaluated, so the block applies even when an allow rule would otherwise let the call proceed." The documented pattern is `"Bash"` in allow plus a `PreToolUse` hook that rejects specific commands.
- **Things a hook `allow` can't approve:** MCP tools marked `requiresUserInteraction`, network-path reads, connector tools the org set to `ask`, and recognized `rm`/`rmdir` critical-path removals ([Permissions](https://code.claude.com/docs/en/permissions#precedence-among-rules-hooks-and-mods); [Permission modes, actions no mode auto-approves](https://code.claude.com/docs/en/permission-modes)). In plan mode a hook `allow` has no effect on a call that isn't read-only.
- **Mods** (plugins handling `tool.check`) answer after `PreToolUse` hooks. Without managed settings, a `managed-mcp.json` or a Team/Enterprise login, "the mod can approve a call that a `PreToolUse` hook blocked, and some calls that a deny rule refuses." With one of those, the built-in guard keeps hook blocks and deny rules in force ([Permissions](https://code.claude.com/docs/en/permissions#precedence-among-rules-hooks-and-mods)).
- **Modes:**
  - `bypassPermissions`: "Deny rules block in every mode, including `bypassPermissions`"; explicit ask rules still prompt; allow rules have no effect; protected-path writes (`.git`, `.claude`, …) are allowed ([Permission modes](https://code.claude.com/docs/en/permission-modes)). The docs don't say in so many words whether `PreToolUse` hooks run and their `deny` holds in this mode. **Unverified**, though the hook input's `permission_mode` field lists `bypassPermissions` as a value a hook can receive.
  - `auto`: deny/ask rules resolve immediately; "Ask rules that match on a command's content, such as `Bash(git push *)`, fall back to a permission prompt"; broad allow rules such as `Bash(*)` are dropped while in auto mode ([Permission modes](https://code.claude.com/docs/en/permission-modes)). An ask rule's subcommand match holds "even in auto mode" ([Permissions, compound commands](https://code.claude.com/docs/en/permissions#compound-commands)).
  - `dontAsk`: calls that would prompt, including explicit ask-rule matches, are denied.
- **Settings scopes:** precedence is managed > command line (`--settings`) > `.claude/settings.local.json` > `.claude/settings.json` > `~/.claude/settings.json`, but list keys such as `permissions.allow` merge across files rather than override ([Settings, lists merge](https://code.claude.com/docs/en/settings#lists-merge-instead-of-overriding)). "If a tool is denied at any level, no other level can allow it", and a user-level deny blocks a project-level allow ([Permissions, settings precedence](https://code.claude.com/docs/en/permissions#settings-precedence)). Hooks come from user, project, local, managed, plugin `hooks/hooks.json`, and skill/subagent frontmatter ([Hooks](https://code.claude.com/docs/en/hooks)); the reference describes deduplication of identical handlers, which implies hooks from all files run together.
- **Turning hooks off:** `allowManagedHooksOnly` (managed) blocks user, project, local and plugin hooks. `disableAllHooks` follows normal precedence, so "a `"disableAllHooks": false` in a project's `.claude/settings.json` overrides a `true` in your user settings", and no non-managed file can disable managed hooks ([Hooks](https://code.claude.com/docs/en/hooks)). A user can also just edit or delete the committed hook, or override it in `.claude/settings.local.json` (inferred from the merge rules; the docs don't describe disabling one specific project hook from the local file, **unverified**).
- **Edits take effect live:** the settings file watcher reloads `permissions` and `hooks` mid-session ([Settings, when edits take effect](https://code.claude.com/docs/en/settings#when-edits-take-effect)).

## Do project hooks need trust first?

- **Interactive:** "Claude Code holds back hooks from every settings file, including your own `~/.claude/settings.json`, until you accept the workspace trust dialog for the folder, or for a parent directory whose trust extends to it" ([Hooks, security](https://code.claude.com/docs/en/hooks)). So a generated repo's guard hook does not run until the folder is trusted.
- **`claude -p` and the SDK:** no dialog; the folder counts as trusted, "so hooks committed in a repository's `.claude/settings.json` run in a folder you've never trusted" ([Hooks](https://code.claude.com/docs/en/hooks); table in [Permissions, what runs before you trust a folder](https://code.claude.com/docs/en/permissions#what-runs-before-you-trust-a-folder)). `--bare`, `--setting-sources user` or `--settings '{"disableAllHooks": true}'` skip them.
- **Deny and ask rules don't wait for trust:** "`deny` and `ask` rules aren't affected, since they only restrict"; only `permissions.allow` and `additionalDirectories` wait ([Permissions, project allow rules and workspace trust](https://code.claude.com/docs/en/permissions#project-allow-rules-and-workspace-trust)). Before trust is accepted, the template's deny/ask rules apply and a guard hook does not.
- **Cloud sessions in a project's threads** apply none of a repo's `.claude/settings.json` permission rules or hooks ([Settings, cloud sessions](https://code.claude.com/docs/en/settings#settings-in-cloud-sessions)).

## How Bash deny/ask rules match

From [Permissions, Bash](https://code.claude.com/docs/en/permissions#bash) and [wildcard patterns](https://code.claude.com/docs/en/permissions#wildcard-patterns):

- **Text match.** "Bash rules match the whole command text, with `*` standing in for any text." Everything before the first `*` must match as written. A trailing ` *` also matches the bare command (`Bash(git push *)` matches `git push`); the space is part of the rule (`Bash(ls *)` doesn't match `lsof`).
- **Compound commands are split.** Separators `&&`, `||`, `;`, `|`, `|&`, `&` and newlines. "Deny and ask rules apply when any subcommand matches them, including a command nested inside a subshell, a command substitution, or a control-flow body such as a `for` loop." Example: an ask rule `Bash(git clean *)` prompts for `cd /tmp && git clean -f` and `echo "$(git clean -f)"`.
- **Env prefixes:** "A deny or ask rule matches past any leading assignment, so `Bash(rm *)` in deny still matches `FOO=bar rm -rf tmp/`." (Allow rules only see past known-safe variables.)
- **Wrappers stripped:** `timeout`, `time`, `nice`, `nohup`, `stdbuf`, `command`, `builtin`, zsh `noglob`, and bare `xargs` (not `xargs -n1 …`). Not stripped: `direnv exec`, `devbox run`, `mise exec`, `npx`, `docker exec`, and by implication `env`, `sudo` and `exec` (not on the list; **unverified**).
- **What a rule doesn't match** (the docs' own table): `Bash(rm *)` doesn't stop `/bin/rm -rf build/` or `bash -c 'rm -rf build/'`; `Bash(curl *)` doesn't stop `/usr/bin/curl …` or `sh -c 'curl …'`; `Bash(git push *)` doesn't stop `git -C . push origin main` or `git -c push.default=current push origin main`. "A deny or ask rule covers the invocation Claude usually produces and isn't a security boundary around the program." For that, the docs point to the sandbox or "a PreToolUse hook".
- **Parameter rules can't match `command`.** `Bash(command:rm *)` is ignored with a startup warning because it "would be bypassable by a compound command" ([Permissions, match by input parameter](https://code.claude.com/docs/en/permissions#match-by-input-parameter)).
- **Read deny vs Bash:** `Read` deny rules also cover redirect targets and recognized file commands such as `cat`, `head`, `tail`, `sed` and `tee`, but "don't apply to a command that reads files without naming them, such as `grep -r pattern .`" or to scripts that open files themselves ([Permissions, Read and Edit](https://code.claude.com/docs/en/permissions#read-and-edit)).

## Which commands slip past the template's rules

Read from the matching rules above, not run. Every row is **unverified locally**. "Default mode" means Manual mode prompts anyway because the command isn't read-only; in `auto`, `bypassPermissions` or with a broad allow rule, a row marked "slips" would run unless something else stops it.

| Command | deny hit? | ask hit? | Why |
| :- | :- | :- | :- |
| `cd x && npm publish` | yes | – | Compound commands are split; deny applies to any subcommand. |
| `NPM_TOKEN=x npm publish` | yes | – | Deny matches past any leading assignment. |
| `timeout 60 cargo publish` | yes | – | `timeout` is a stripped wrapper. |
| `echo "$(npm publish)"`, `(npm publish)` | yes | – | Docs say subshells and command substitutions are checked. |
| `bash -c 'npm publish'`, `sh -c '…'` | no | no | Docs' table: `bash -c` isn't matched. Only the outer `bash` is checked. |
| `env npm publish`, `sudo npm publish` | no (unverified) | no | `env`/`sudo` aren't in the stripped-wrapper list. |
| `npx pnpm publish`, `pnpm -r publish`, `npm --workspace a publish`, `pnpm --filter a publish` | no | no | Text before the first `*` must match; an option or runner before `publish` breaks the prefix. |
| `git push --force origin main` | yes | – | Matches `git push --force *`. |
| `git push origin main --force`, `git push origin main -f` | no | yes | Flag after the refspec; only the ask rule matches. |
| `git push --force-with-lease`, `git push --force-if-includes` | no | yes | No space after `--force`, so the deny prefix doesn't match. |
| `git push origin +main` | no | yes | `+` on a refspec forces a non-fast-forward update ([git-push, `<refspec>`](https://git-scm.com/docs/git-push)); no deny rule looks at refspecs. |
| `git push origin :main`, `git push --delete origin main` | no | yes | Deletes the remote branch; only the ask rule matches. |
| `git push --mirror`, `git push --all --force` | no / yes | yes | `--mirror` force-updates and deletes remote refs; not in deny. |
| `git -C . push --force`, `git -c k=v push -f`, `/usr/bin/git push -f` | no | no | Docs' table: these forms get past `Bash(git push *)`. |
| `gh api -X DELETE repos/o/r` | yes | – | Matches `gh api -X DELETE *`. |
| `gh api --method DELETE repos/o/r` | no | no | Long option spelling isn't covered. |
| `gh api repos/o/r -X DELETE`, `gh api -XDELETE …`, `gh api -X delete …` | no | no | Option after the path, no space, or lower case; none match the prefix (case sensitivity of matching is **unverified**). |
| `gh api -X PUT repos/o/r/actions/secrets/NAME`, `gh api -X POST repos/o/r/releases` | no | no | Same effect as the denied `gh secret` / `gh release create`, through the REST API. |
| `gh secret set X`, `gh secret list` | yes | – | `gh secret *` denies every subcommand, read-only ones included. |
| `gh pr merge 5 --admin`, `gh -R o/r pr merge 5` | – | yes / no | Global `-R` before `pr` breaks the ask prefix. |
| `cat .env` | yes | – | Recognized file command, checked against `Read` deny. |
| `grep -r TOKEN .`, `python -c "print(open('.env').read())"`, `source .env` | no | no | Docs: unnamed reads and subprocess reads aren't covered (`source` **unverified**). |

What still stops some of these: Manual mode prompts for any non-read-only command; on GitHub, `main`'s ruleset, the merge gate and push protection reject force pushes and branch deletion on `main` server-side ([#85](https://github.com/ZeleMate/repo-template/issues/85) notes); package registries need credentials the agent may not have.

## Facts that bear on writing a guard hook

- The hook receives the raw `command`; splitting on `&&`/`;`/`|`, unwrapping `bash -c '…'`, stripping env prefixes and `git -C`/`-c`/`gh -R` globals, and spotting `+refspec` or `--method DELETE` is the hook's own job.
- Fail-open by default: a crash (exit 1), a missing `jq`, invalid JSON or a timeout lets the call through. `format.sh`'s `command -v jq … || exit 0` pattern is fail-open; a guard that should fail closed needs `exit 2` on those paths.
- A hook `deny` or exit 2 wins over every allow rule and every other hook's `allow`, but a non-org mod can override it in sessions without managed settings or an org login.
- Hooks don't run until the folder is trusted in an interactive session, while deny/ask rules apply immediately. Under `-p`, both apply.
- The docs offer the OS sandbox as the enforcement that "doesn't depend on the command text"; the map puts sandbox settings out of scope.

## Open (not settled by the docs)

- Whether `PreToolUse` hooks run and their `deny` holds in `bypassPermissions` mode. Not stated explicitly.
- Whether Bash rule matching is case-sensitive, and whether `env`, `sudo`, `exec` and `eval` are seen through.
- How a rule treats quoting inside the command (e.g. `git push origin '+main'`).
- A local `claude -p --permission-mode dontAsk` probe with harmless `echo`/`printf` deny/ask rules would settle the table; the attempt here failed on authentication. The probe script is easy to rebuild: `--setting-sources '' --settings '{"permissions":{"allow":["Bash"],"deny":["Bash(echo guardtest *)"]}}'` and read `.permission_denials` from `--output-format json`.
