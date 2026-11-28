# A working git inside the skill eval sandbox

Question ([#86](https://github.com/ZeleMate/repo-template/issues/86), on map [#83](https://github.com/ZeleMate/repo-template/issues/83)): can a skill eval run use a working `git` inside Claude Code's sandbox, on macOS locally and on the CI runner? It decides how a `repo-template-update` case gets a git for `copier update`.

Sources: Claude Code's [plugin evals](https://code.claude.com/docs/en/plugin-evals), [sandboxing](https://code.claude.com/docs/en/sandboxing) and [settings reference](https://code.claude.com/docs/en/settings-reference) pages, the sandbox settings `claude plugin eval` generated for a real run on this machine, Copier's [updating docs](https://copier.readthedocs.io/en/stable/updating/) and [`copier/_vcs.py`](https://github.com/copier-org/copier/blob/master/copier/_vcs.py), the Skill evals workflow's run logs, and a local Seatbelt probe. Checked on 2026-11-28 with Claude Code 2.1.302 on macOS 27.2.1. This file records facts and options. It does not make a decision.

**Spend: $0.** The authenticated probe run did not happen. `run-evals.sh` started from this agent's shell stopped at the first run with `Not logged in · Please run /login` before any model call. The scaffold and the run's settings file were still written, and that is where the main finding comes from. The probe case is ready to run (see [Probe to run next](#probe-to-run-next)).

## Summary

| Question | Answer | Confidence |
|---|---|---|
| Can a suite or `run-evals.sh` configure the eval sandbox (paths, excluded commands, writable dirs)? | **No.** A run loads no user or project settings. The only inputs are `--allow-tools` (tools and `WebFetch(domain:…)` network grants), `EVAL_*` env vars, read-only `context.add_dirs`, and managed settings, which can only tighten | Docs plus generated settings |
| Why does git fail on macOS? | The run's generated sandbox settings block reads of **the git binaries themselves**: `/opt/homebrew/Cellar/git/2.56.1/bin/git` and `/Library/Developer/CommandLineTools/usr/bin/git`. That comes from the run's credential-helper deny list, because `git-credential-store`, `-cache` and `-cache--daemon` are symlinks to `../../bin/git` and the list holds their resolved targets. Apple's `/usr/bin/git` stub then can't find a git it may read | Settings file: fact. Causation: strong, not yet confirmed in a live run |
| Is Homebrew git usable? | Unclear. A read deny alone doesn't stop Seatbelt from exec'ing the binary (local probe), but the README's earlier probe found it "not found". Needs the authenticated probe | Open |
| Does git work on the CI runner? | **Yes, indirectly shown.** CI runs where the agent clones with Copier and branches with git pass (repo-new `02-pinned-to-tag`, repo-adopt `08-on-branch-not-pushed`, 2026-11-28). No direct `git --version` probe has run in CI | Strong but indirect |
| What does `copier update` need git for? | Everything: cloning the template at the old and new tags, checking the project is a clean git repo, and the diff/merge. There is no non-git path. It finds `git` through `PATH` (plumbum `local["git"]`) and has no setting for the binary's path | Docs and source |

The ticket says the runner is Ubuntu 24.04. The 2026-11-28 runs actually ran on the `ubuntu26/20261122.9` image (Ubuntu 26.04), because `ubuntu-latest` has moved. The AppArmor workaround in `skill-evals.yml` still worked there.

## What a suite can configure

**Settings don't load.** Each run "gets a temporary home directory, working directory, and Claude Code configuration". No user settings, hooks, `CLAUDE.md` or project `.claude/` load, "even one a `scaffold_script` wrote" ([plugin evals: how runs are isolated](https://code.claude.com/docs/en/plugin-evals#how-runs-are-isolated)). So `sandbox.excludedCommands`, `sandbox.filesystem.allowWrite` and `allowRead` from the [sandboxing page](https://code.claude.com/docs/en/sandboxing) can't reach a run from the repo or from your user settings. Managed settings still apply, but they only add restrictions.

**What a case can set** (from the [`prompt.md` and `case.yaml` field tables](https://code.claude.com/docs/en/plugin-evals#prompt-md-frontmatter)): `allowed_tools`, `disallowed_tools`, `env` (keys must match `EVAL_[A-Z0-9_]*`), `append_system_prompt`, `context.scaffold_script`, `context.history_file`, and `context.add_dirs` (directories inside the case directory, "granted read-only"). None of these is a sandbox path, a writable directory or an excluded command.

**What the command can set** ([command options](https://code.claude.com/docs/en/plugin-evals#command-options)): `--allow-tools` grants tools and network domains, and `Read(//path/**)` pre-approves Read-tool reads. It doesn't add sandbox paths. Granting Bash in any form puts every command in the OS sandbox: "Writes are confined to the run's workspace, your home directory and Claude Code configuration are unreadable, and network access is limited to domains you grant" ([shell grants need a sandbox](https://code.claude.com/docs/en/plugin-evals#shell-grants-need-a-sandbox)).

**Environment.** The run inherits an allowlist from your shell, including `PATH`, plus `EVAL_*` variables ([`env` field](https://code.claude.com/docs/en/plugin-evals#prompt-md-frontmatter)). A case can't set `PATH` or `DEVELOPER_DIR`, because both fail the `EVAL_*` pattern. The agent can still prefix `PATH` inside its own Bash command. Scaffold scripts get "your shell's `PATH`, `HOME` set to the run's temporary home directory, `TMPDIR`, and a few constants".

**The generated settings, read from a real run.** `--keep-temp` kept `config/settings.json` for the run. It contains:

- `sandbox.enabled: true`, `failIfUnavailable: true`, `allowUnsandboxedCommands: false`. So `dangerouslyDisableSandbox` retries are off, as the sandboxing page describes for that key.
- `filesystem.allowWrite`: only the run's `home/` and `tmp/`.
- `filesystem.denyRead`: `/Users`, your home, `/private/tmp`, `/tmp`, your `$TMPDIR` (`/var/folders/…/T`) and others. `allowRead` re-opens the run's home and tmp, the plugin directory, and the `PATH` entries under your home (`~/.local/bin`, `~/Library/pnpm`).
- `sandbox.credentials.files`, about 60 entries with `mode: deny`, among them:

  ```text
  //opt/homebrew/opt/git/libexec/git-core/git-credential-store
  //opt/homebrew/Cellar/git/2.56.1/bin/git
  //opt/homebrew/opt/git/libexec/git-core/git-credential-cache
  //opt/homebrew/Cellar/git/2.56.1/bin/git
  //Library/Developer/CommandLineTools/usr/libexec/git-core/git-credential-store
  //Library/Developer/CommandLineTools/usr/bin/git
  ...
  ```

  `sandbox.credentials.envVars` denies `GH_TOKEN` and `GITHUB_TOKEN`, among others. That explains why no token reaches the agent, apart from the scaffold.

The settings reference says a `credentials.files` entry with `"mode": "deny"` "blocks reads of the path inside the sandbox, the same read block as `sandbox.filesystem.denyRead`", and that there is "no built-in credential deny list" ([`sandbox.credentials.files`](https://code.claude.com/docs/en/settings-reference#sandbox-credentials-files)). Your `~/.claude/settings.json` has no `sandbox` key, so `claude plugin eval` builds this list itself, and the plugin-evals page doesn't document it. That page only says each run switches off "git hooks, credential helpers, and other programs a repository's git configuration can start" through `GIT_CONFIG_COUNT` ([git is too old](https://code.claude.com/docs/en/plugin-evals#git-is-too-old-for-claude-plugin-eval)).

**Why the git binaries are on that list.** On this machine, Homebrew and the Command Line Tools both ship the credential helpers as symlinks to git:

```text
Cellar/git/2.56.1/libexec/git-core/git-credential-store -> ../../bin/git
Cellar/git/2.56.1/libexec/git-core/git-credential-cache -> ../../bin/git
/Library/Developer/CommandLineTools/usr/libexec/git-core/git-credential-store -> ../../bin/git
```

When the deny list resolves each helper to its real path, it lands on the git binary. That is an inference from the listing above, since the harness's code isn't public. `git-credential-osxkeychain` and `git-credential-netrc` are real files and appear under their own paths.

## macOS: what breaks, and what the probes show

**Apple's stub.** `/usr/bin/git` is a shim that asks `xcode-select` or `xcrun` for the active developer dir (`/Library/Developer/CommandLineTools` here) and execs `usr/bin/git` there. A local Seatbelt probe denied `file-read*` on the two real git binaries, the way the eval's entries do, and the stub then failed:

```text
xcode-select: Failed to locate 'git', requesting installation of command line developer tools.
exit=72
```

So the stub fails under the eval's deny list whether or not xcrun can write its cache. The README's "can't write its xcrun cache" may also be true, because the user cache dir `/var/folders/…/C/` isn't in `allowWrite`, but it isn't the only cause. Setting `DEVELOPER_DIR` won't help, because the target binary is the denied one.

**Homebrew git.** The same local probe exec'd `/opt/homebrew/bin/git --version` successfully under the read deny: Seatbelt's `file-read*` deny didn't stop the exec. A copy of the binary at another path also ran, `init`, `add`, `commit` and `log` worked, but `ls-remote` over HTTPS failed with `remote helper 'https' aborted session`. My hand-written profile isn't the profile Claude Code generates, which also limits writes, network and probably exec. So this doesn't show that Homebrew git works in a real run, and the README's earlier probe said it "isn't found". The PR that added that note ([#34](https://github.com/ZeleMate/repo-template/pull/34)) merged about 40 minutes after this machine's Homebrew git was poured (2026-11-14 13:06 local). So that probe may predate Homebrew git, and `PATH` order or exec rules may also explain it. This is the main open fact.

## Linux CI: does git work?

On Linux the sandbox is bubblewrap. A file deny there masks only the path it names, so a hard-linked or separately installed `/usr/bin/git` isn't affected the way a resolved symlink target is. I didn't check how Ubuntu's `git` package lays out `/usr/lib/git-core`.

The evidence that git runs in the CI sandbox is behavioural. In run [46116907055](https://github.com/ZeleMate/repo-template/actions/runs/46116907055) (2026-11-28, Claude Code 2.1.302):

- repo-new scored 1.00 with the plugin. The skill runs `uvx copier copy … --vcs-ref <tag> gh:ZeleMate/repo-template`, and Copier clones the template with git ([`_vcs.clone`](https://github.com/copier-org/copier/blob/master/copier/_vcs.py)). `02-pinned-to-tag` passed.
- repo-adopt passed `08-on-branch-not-pushed` in every with-plugin run, so the agent ran `git switch -c` inside the sandbox.

Both checks are LLM judges on the trace, not a direct `git --version`. The suite reports are in that run's `skill-evals` artifact, which I didn't download. Running the sandbox probe in CI once (the workflow's `suite` choice would need a `sandbox-probe` entry) would make this direct.

## What `copier update` needs git for

Per Copier's [updating docs](https://copier.readthedocs.io/en/stable/updating/), the template must be "versioned with Git (with tags)" and the destination "versioned with Git", with a clean `git status`. The update regenerates the old version, diffs it against the project, applies the new version, and reapplies the diff, with conflicts written `inline` (the default, merge-style markers) or as `.rej` files. The source ([`copier/_vcs.py`](https://github.com/copier-org/copier/blob/master/copier/_vcs.py)) shows:

- `get_git()` is `local["git"]` from plumbum, which resolves `git` on `PATH`, with fixed author and committer env and `maintenance.auto=false`. No setting or env var names the binary. `COPIER_CACHE_DIR` only moves the mirror cache.
- `clone()` clones remote templates through a cached mirror (current master) and local ones with `git clone --no-checkout`, then `checkout -f <ref>`.
- `is_git_repo_root` and `is_in_git_repo` run `git rev-parse --show-toplevel`.

The repo's `repo-template-update` skill also runs git directly: `git switch -c`, `git ls-remote --tags`, a shallow clone for `git log` and `git diff`, and `git status` and `git checkout HEAD --` for cleanup. So a case for that skill needs git inside the sandbox, not only in the scaffold. The scaffold can prepare git state (a generated project committed at an old tag, or a local template repo with tags), as repo-adopt's `place-files.sh` does, but it can't stand in for the agent's own git calls.

## Options (not a decision)

1. **CI-only case.** Run a `repo-template-update` case only on the Linux runner, where git evidently works, and skip it or mark it expected-to-fail on macOS. Cost: no local iteration. The case's `tags` could carry `ci-only` so `run-evals.sh` can filter it with `--tag`.
2. **Agent-side `PATH` prefix to Homebrew git.** If the authenticated probe shows `/opt/homebrew/bin/git` runs in the sandbox, the skill or prompt can't rely on it (users won't have it), but a suite could `export PATH=/opt/homebrew/bin:$PATH` in `append_system_prompt`. That would test the environment, not the skill. This depends on the open fact above.
3. **Scaffold-provided git binary.** The scaffold runs as you, outside the sandbox. It could copy a git binary into the workspace (`./.tools/git`) under a path the deny list doesn't name, and the case could prepend it to `PATH`. The local probe shows that a copy runs and commits under a read deny, but HTTPS remotes failed. A case could avoid them with a local template repo the scaffold creates. This sidesteps a protection the harness adds on purpose: the copy can run `git credential` builtins (`store`, `cache`) that the deny list means to block, although the run's home is a fresh temp dir with no `~/.git-credentials`. Weigh that before choosing it.
4. **Local template, no network.** Independent of the git question: the scaffold can create a local Copier template with two tags, as the probe does, so the update case needs no GitHub clone. That makes it faster and keeps it off the network grants.
5. **Report the deny-list behaviour upstream.** If the probe confirms the cause, the harness denying the real git binary because helpers symlink to it looks unintended. The docs require git 2.31+ for evals, which implies git is meant to work. Reporting it (`/bug`) could fix macOS for every suite, including repo-new and repo-adopt locally.
6. **Grade without running git in the sandbox.** Move `copier update` into the scaffold and grade only what the agent does after it (conflict resolution, summary). The scaffold runs as you with your `PATH` and full network, but within a 120-second limit, and it gets no other shell variables. This changes what the case tests: the skill's update procedure is no longer exercised.

## Probe to run next

A scratch case, `git-probe`, was written for this research but not committed. It has a scaffold that copies `probe.sh` and builds a two-tag local Copier template, a regex grader that needs no LLM judge, and `max_turns: 4`. It runs: `type -a git`, `/usr/bin/git`, `xcrun --find git`, a write to `getconf DARWIN_USER_CACHE_DIR`, the CLT and Homebrew binaries directly, git `init` and `commit` in the workspace, `ls-remote` and `clone` over HTTPS, `uvx copier copy` at `v1`, `copier update` to `v2`, and a Copier run with Homebrew removed from `PATH`. Expected cost is a few cents per run. To use it, add `evals/git-probe/git-probe/` with those files and run `./scripts/run-evals.sh git-probe --runs 1 --ablation none --keep-temp` from a logged-in shell, then read `probe-out.txt` in the kept workspace. Running it in CI as well would settle the Linux side directly.

## Not confirmed

- That the credential deny entries, rather than `PATH` or exec rules, are what makes git fail in a real macOS run. The settings file shows the entries. No authenticated run has shown the effect.
- Whether Homebrew git runs inside a real eval run.
- A direct `git --version` inside the CI sandbox. The evidence is from graded behaviour.
- How the harness builds its credential deny list. It's undocumented, and inferred here from the symlinks.
