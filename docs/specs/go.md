# Spec: Go as a managed language

Go becomes the fourth managed language, next to Python, TypeScript and Rust, as decided in [ADR 0004](../adr/0004-add-go-as-a-managed-language-ahead-of-demand.md). This spec covers three parts:
- the template side;
- the central `go.yml` in `ZeleMate/workflows` and the central release it ships in;
- the `repo-standards` plugin's skills and tests.

Terms (managed language, caller workflow, central workflow repo, central release, merge gate, local CI workflow, version floor, newest known version) are defined in [CONTEXT.md](../../CONTEXT.md). How central and template releases relate is in [the central workflows spec](central-workflows.md).

This spec comes from the map [Add Go as a managed language](https://github.com/ZeleMate/repo-template/issues/61). Each section names the closed tickets it comes from. The two research write-ups behind it are [go-toolchain.md](../research/go-toolchain.md) and [go-releases.md](../research/go-releases.md).

Out of scope:
- Java/Kotlin and C# as managed languages.
- Switching the Python release job from `actions/attest-build-provenance` to `actions/attest`.
- Starter evals that drive the app itself instead of calling the model directly.
- Adding a language to an existing single-language repo with `copier update`.

**Status (2026-11-21):** specified, not built. The facts nobody could check by reading are listed under [Not verified](#not-verified), and the build checklist says where each one gets checked.

## 1. Copier questions and the starter

_From [What do the Go Copier questions and starter files look like?](https://github.com/ZeleMate/repo-template/issues/65) (amended by [What does publishes mean for a Go repo?](https://github.com/ZeleMate/repo-template/issues/66)) and [What is the current Go toolchain for lint, vuln scan, coverage and Dependabot?](https://github.com/ZeleMate/repo-template/issues/62)._

**Questions** (each `when: "[[ 'go' in languages ]]"`; `languages` gains the choice `Go: go`):

| Key | Kind | Default | Rule |
|---|---|---|---|
| `go_version` | asked | `1.26` (the oldest supported release) | The version floor. A free string validated as `1.N`, not a choices list: when a later template release moves the choices, an old answer would stop `copier update`. No max cap like `python_max_version`, because Go's compatibility promise means newer Go builds older code. |
| `go_module` | asked | `github.com/[[ github_owner ]]/[[ repo_name ]]`, plus `/go` when `go_dir` is `go` | The module path, asked like Python's `package_name` so that vanity paths and other hosts work. Case is kept as on GitHub. Light validator: no whitespace, and a first path element containing a dot. The `/go` suffix isn't enforced, since a vanity path can map onto the subfolder. It also accepts a `/vN` suffix (section 4). |
| `go_dir` | computed (`when: false`) | `go` in a multi-language repo, else `.` | Matches `py_dir`, `ts_dir`, `rs_dir`. |

The `publishes` help text becomes "Will you publish releases (packages to PyPI / npm / crates.io, Go binaries on GitHub releases)?". The template README's Questions table and languages row gain Go.

**The CI version list.** Every minor from `go_version` up to the newest known version, lowest first (today `["1.26", "1.27"]`). The newest known version is a literal in `ci.yml.jinja`, like Python's `14`. The floor moves only with `copier update -d go_version=1.N`, which rewrites `go.mod`'s `go` line and the list together. Editing `go.mod` alone makes the floor leg fail, because setup-go sets `GOTOOLCHAIN=local`. Dependabot never moves the floor.

**Starter files**, in `go_dir`:
- `go.mod`:
  - `module [[ go_module ]]` and `go 1.26.0` (from `go_version`);
  - no `toolchain` line and no dependencies, so no `go.sum`.
- `cmd/[[ project_slug ]]/main.go`:
  - a thin shim that calls `greeting.Greet` and prints the result;
  - `var version = "dev"` and a `--version` flag, which release builds stamp with `-ldflags -X main.version=<version>`.

  The binary name is `project_slug`. The starter is always a binary; a library repo deletes `cmd/`.
- `internal/greeting/greeting.go`: `Greet(name string) string`. The package name is a fixed `greeting`, since Go package names can't take a slug's dashes.
- `internal/greeting/greeting_test.go`: a table-driven test plus a native fuzz test, `FuzzGreet`. Plain `go test` runs only its seeds.
- `.golangci.yml`:
  - `version: "2"` and `linters.default: standard` (errcheck, govet, ineffassign, staticcheck, unused);
  - plus `gosec` (with G104 excluded, which duplicates errcheck) and `errorlint`;
  - formatters `gofmt` and `goimports`.

  gosec is on because agent code shells out, reads paths and calls HTTP.
- **No `Makefile`:** CodeQL's Go autobuild tries `make` first.
- **No `go.work`:** the template has one Go module, and go.dev advises against committing it.
- **No post-generation task:** with no dependencies there's nothing to tidy or lock, so generating needs no Go install. A starter that gains a dependency later adds a guarded task then.

**Other template files:**
- `.gitignore`: a Go block when Go is managed, with `coverage.out`, `*.test`, and `/[[ project_slug ]]` anchored in `go_dir` (the binary `go build` leaves there). No `dist/`: binaries are built only in CI.
- `dependabot.yml.jinja`: `'go': 'gomod'` in the `managed_root` map, and a `gomod` block copied from the `cargo` one (cooldown 7/14 days, a minor-patch group).

## 2. Local hooks and the Claude format hook

_From [What are the Go local hooks, and which ids does repo-lint skip?](https://github.com/ZeleMate/repo-template/issues/70) and [How does a Go repo release v2 and later?](https://github.com/ZeleMate/repo-template/issues/67)._

**`.pre-commit-config.yaml`**: two hooks in the `local` block, whose `[% if %]` guard gains `'go' in languages`.

| Id | Entry | Matching | Runs in `repo-lint` |
|---|---|---|---|
| `golangci-lint-fmt` | `golangci-lint fmt --config [[ go_dir ]]/.golangci.yml`, `language: system` | `types: [go]`, plus `files: ^[[ go_dir ]]/` in a multi-language repo; filenames passed, so only staged files are formatted | No, skipped (needs the Go toolchain) |
| `go-major-version` | `sh scripts/go-major-version.sh`, `language: system`, `pass_filenames: false` | `files: ^(\.release-please-manifest\.json\|[[ go_dir ]]/go\.mod)$` | Yes |

- **Formatting only, like `prettier` and `cargo-fmt`.** `golangci-lint fmt` reads the files without loading packages, so it's fast. Rejected: `golangci-lint run` as a hook (it type-checks whole packages, and the TypeScript and Rust hooks don't lint either), and a `go mod tidy -diff` hook (it can need the network, and no other language checks its lockfile in a hook). CI gates both.
- **`scripts/go-major-version.sh.jinja`**, rendered only when Go is managed, next to `bootstrap-github.sh`. Copier bakes in the Go package's manifest key (`go` or `.`) and its `go.mod` path. It uses only `sh` and `grep`, and is called through `sh` so it doesn't depend on the executable bit. The rule:
  - A version of 0 or 1 is never checked (Go has no `/v0` or `/v1` paths).
  - A major of 2 or higher fails unless the `module` line ends in `/vN` with N ≥ major.
  - The lenient `≥` lets the preparation PR of a major bump pass: the module already says `/v2` while the manifest still says `1.x`, and the same for v2 → v3.

**`repo-lint.yml`'s `skip-hooks` default** in central `v1.1.0` becomes `gitleaks,prettier,cargo-fmt,golangci-lint-fmt`. The `golangci-lint` id reserved in [What does the central go.yml run, with which inputs, in which central release?](https://github.com/ZeleMate/repo-template/issues/64) became `golangci-lint-fmt`. Repos without Go skip an id they don't have, which does nothing.

**Claude format hook** (`.claude/hooks/format.sh.jinja`), branch `*.go)`:
- When `golangci-lint` is on PATH: `golangci-lint fmt --config "$root/[[ go_dir ]]/.golangci.yml" "$file"`.
- Otherwise: `gofmt -w "$file"`. gofmt is one of the configured formatters, so the fallback never conflicts with it; it just doesn't group imports.
- Output is silenced and the hook always exits 0, as for the other languages.

## 3. The central `go.yml` and central release `v1.1.0`

_From [What does the central go.yml run, with which inputs, in which central release?](https://github.com/ZeleMate/repo-template/issues/64) and [What is the current Go toolchain for lint, vuln scan, coverage and Dependabot?](https://github.com/ZeleMate/repo-template/issues/62)._

**Inputs** (renaming or removing one later costs a central major):

| Input | Required | Meaning |
|---|---|---|
| `go-versions` | yes | A JSON list of Go versions, lowest first, written by Copier (section 1), e.g. `'["1.26", "1.27"]'` |
| `working-directory` | no (default `.`) | The folder holding `go.mod` |

Nothing else: no switch for `-race` or coverage. A repo that can't run `-race` (no cgo) runs its own job in `ci-local.yml`. The list isn't derived from `go.mod` plus setup-go's `stable` alias, because a new Go release would then turn green repos red with no edit: golangci-lint can't lint for a Go newer than it was built with.

**One matrix job**, mirroring `python.yml`. It has one leg per entry in `go-versions`, uses `contents: read`, and runs `actions/setup-go` (which sets `GOTOOLCHAIN=local`). Each leg runs:
1. the format check and lint, with golangci-lint and the repo's own `.golangci.yml`;
2. `go vet ./...`;
3. `go mod tidy -diff` and `go mod verify`;
4. `go build ./...`;
5. `go test -race -covermode=atomic -coverprofile=coverage.out ./...`.

Some steps run on one leg only:
- **Floor leg** (the first entry), on PRs only: `coverage.out` → gocover-cobertura → `diff-cover --fail-under=90`, as Python and TypeScript do. No packages are left out, `cmd/` included. If `go.mod`'s `go` line is above the floor, this leg fails on its own, so there's no separate consistency check.
- **Newest leg** (the last entry): govulncheck, with text output. It fails only on vulnerable code that's actually called, and it checks the standard library of the Go running it.
- **No `gosec` step.** It overlaps Semgrep and CodeQL, and stays a linter in the repo's `.golangci.yml`.

**Tool pins:**

| Tool | Version (2026-11-21) | Pinned as |
|---|---|---|
| golangci-lint | v2.15.0 | a release binary, version + SHA-256 in env, like OSV-Scanner and Gitleaks. Not `go install` or `go tool` (the project advises against them), and not the official action (it does no checksum check) |
| govulncheck | v1.10.0 | a `tool` directive in a central `tools/go/go.mod`, locked in `go.sum`. Not `golang/govulncheck-action`, which installs `@latest` and floats Go |
| gocover-cobertura | v1.5.0 | the same `tools/go` module |
| `actions/setup-go` | v7.1.0 | SHA, like every action |

Dependabot on `ZeleMate/workflows` keeps `tools/go` current. The workflow builds those tools from its self-checkout into `$RUNNER_TEMP/bin`, then runs them in the caller's folder. `go run …@vX` is rejected because Dependabot can't see its version. golangci-lint's pin must move at each Go release, before the template's newest known version moves (section 8).

**Caller side.** `ci.yml.jinja` gains a `go` job calling `go.yml` at the central pin, with `go-versions` and `working-directory: [[ go_dir ]]`. The job is listed in `ci-ok`'s `needs`.

**`security.yml` doesn't change:**
- OSV-Scanner already scans `go.mod` and skips the standard library, which govulncheck covers. Its Go call analysis stays on by default; turning it off would be stricter, so a central major, and govulncheck is the gate.
- Semgrep `p/default` has 84 Go rules.
- CodeQL default setup uses autobuild for Go, and the root `cmd/` + `internal/` layout is its documented simple case.

**Release.** Every central change is additive (`go.yml`, `tools/go`, the larger skip default), so by section 7 of the central workflows spec it is the minor release **`v1.1.0`**. The template moves its central pin to `v1.1.0` in the same template release that adds Go, since it writes a workflow only `v1.1.0` has. Repos without Go get `v1.1.0` through Dependabot, and nothing changes for them.

## 4. Releases: tags, `publishes`, and v2 and later

_From [How do Go modules version and release from a subdirectory?](https://github.com/ZeleMate/repo-template/issues/63), [What does publishes mean for a Go repo?](https://github.com/ZeleMate/repo-template/issues/66) and [How does a Go repo release v2 and later?](https://github.com/ZeleMate/repo-template/issues/67)._

**Tags.** Go requires a module in a subfolder to be tagged with the folder as a prefix and a slash.

| Layout | Module path | Tag | release-please package |
|---|---|---|---|
| Single language (root) | `github.com/<owner>/<repo>` | `vX.Y.Z` | path `.`, as today |
| Multi-language (`go/`) | `github.com/<owner>/<repo>/go` | `go/vX.Y.Z` | `component: go` and its own `"tag-separator": "/"` |

- The separator is set on the Go package only, so the other languages' tags don't change. The template's current multi-language form, `go-vX.Y.Z`, isn't a Go version tag. `googleapis/google-cloud-go` uses the same scheme.
- The release type is `go`. It writes only `CHANGELOG.md` and never touches `go.mod`.
- **The tag is the release.** There's no registry, token or OIDC step. proxy.golang.org fetches a version the first time someone asks for it, and pkg.go.dev reads from the proxy. The proxy never removes a version, so the fix for a bad release is `retract` plus a new version. Drafts don't matter, since `force-tag-creation` creates the tag.
- **Private repos:** consumers set `GOPRIVATE` and need git credentials.

**Versioning:**
- `"bump-minor-pre-major": true` on the Go package only. In 0.x a breaking change bumps the minor, matching Go's "v0 promises nothing". It isn't set for Python, TypeScript or Rust: it would quietly change how existing repos version on their next `copier update`.
- Leaving v0 is deliberate: a commit with a `Release-As: 1.0.0` footer.

**`publishes`:**
- `false`: tag only. A public module is installable from the tag with `go install`.
- `true`: binaries on the GitHub release, plus provenance attestations and a proxy warm in public repos. Agent projects in Go (MCP servers, CLIs) mostly ship as downloads.
- No new Copier question.

**The `publish-go` job** in `release.yml`:
- **When:** `needs: release-please`, and it runs when the Go package released. `environment: release` where `has_governance`, like the other publish jobs.
- **Permissions:** `contents: write`, to upload to the draft. In public repos also `id-token: write` and `attestations: write`.
- **Build:** six targets (linux, darwin, windows × amd64, arm64), in one job that loops over them. Pure Go cross-compiles quickly, so there's no matrix. Flags: `CGO_ENABLED=0`, `-trimpath`, `-ldflags "-s -w -X main.version=<version>"`. The version is the tag without its `go/` prefix. It's stamped explicitly, because research couldn't confirm Go stamps the right version from a prefixed tag.
- **Assets:** raw binaries named `<slug>_<os>_<arch>[.exe]`, plus one `SHA256SUMS`. No archives: `LICENSE` is in the repo and in the module zip.
- **Steps:**
  1. Build the six binaries and write `SHA256SUMS`.
  2. Attest with `actions/attest`, in public repos only, like the PyPI job. `actions/attest-build-provenance` v4 is now a wrapper around it, and its README points new code to `actions/attest`.
  3. `gh release upload` into the draft release.
  4. Public repos only: warm the proxy with `GOPROXY=https://proxy.golang.org go list -m <module>@<version>`. Never in private repos: the proxy can't fetch them, and the request would leak the module path.
- **No GoReleaser.** Its open-source edition can't release from prefixed tags: the monorepo feature is Pro-only, and OSS fails to parse `go/vX.Y.Z` as semver. It would only fit single-language repos.
- **`sbom` waits for it:** `needs: [release-please, publish-go]`, running unless `publish-go` failed. That keeps the draft-then-publish safeguard, so a failed Go build leaves the release as a draft. The extra `needs` is rendered only when Go is managed and `publishes` is set. The repo-wide SPDX SBOM covers the Go module; there's no SBOM per binary.

**v2 and later.** A breaking change at ≥1.0.0 makes release-please propose 2.0.0 and tag `go/v2.0.0` (or `v2.0.0`) while `go.mod` has no `/v2`. Go rejects that, and no release-please setting guards it. Instead:
- The `go-major-version` hook (section 2) fails the merge gate on the bot's release PR before the tag exists.
- The procedure, in the generated `CONTRIBUTING.md` (section 5):
  1. `copier update --trust --defaults -d go_module=<path>/v2` rewrites `go.mod`'s `module` line, and later updates keep the new path.
  2. Rewrite the internal imports to the `/v2` path.
  3. Merge with a breaking-change commit. release-please proposes 2.0.0 and the hook passes.
- `go.mod` stays where it is (`go/` or the root), not in a `v2/` subfolder: both work for Go, and staying put keeps `go_dir`, CI and the release paths unchanged.
- Binary-only repos and libraries are the same here: `go install <module>/cmd/<slug>@v2.0.0` needs the `/v2` path too.
- Rejected: docs only (a bad tag, release and binaries are messy to undo), and `always-bump-minor` versioning (no patch releases).

## 5. Generated docs and agent rules

_From [What do the generated docs and agent rules say for Go?](https://github.com/ZeleMate/repo-template/issues/71), [What does publishes mean for a Go repo?](https://github.com/ZeleMate/repo-template/issues/66) and [What does a Go repo with agentic get for evals?](https://github.com/ZeleMate/repo-template/issues/69)._

**`AGENTS.md`:**
- A `### Go` block, with `` (`go/`) `` in multi-language repos:
  ```bash
  cd go   # multi-language only
  golangci-lint fmt && golangci-lint run
  go vet ./... && go mod tidy -diff
  go test -race ./...
  ```
  govulncheck stays CI-only: running it locally needs a pinned install, and it checks against CI's Go.
- In the Dependencies section, `go get` joins the package-manager list.
- A new bullet: a dependency that raises `go.mod`'s `go` line fails CI's floor leg, and the floor moves only with `copier update -d go_version=1.N`.

**`.claude/rules/go.md`** (`paths: ["**/*.go"]`):
- Return errors and wrap them with `%w`; compare with `errors.Is`/`errors.As`. No `panic` outside `main`.
- `context.Context` is the first parameter of anything that does I/O, and is never stored in a struct.
- Every goroutine has a way to stop (a context or a closed channel).
- Use `os/exec` with an argument list, never `sh -c` with input built from strings (gosec G204).
- New code goes under `internal/`; `cmd/<slug>/main.go` stays a thin shim.
- Tests are table-driven with `t.Run`, use fuzz tests for parsers, and must pass under `-race`.
- Fix lint findings rather than adding `//nolint`; any `//nolint:<linter>` needs a reason comment.

**`README.md`:**
- The Toolchains line gains "Go `[[ go_version ]]`+ with golangci-lint v2". Its loop's bare `[% else %]` (which now means Rust) becomes explicit `rust` and `go` branches.
- When Python isn't in `languages`, the line adds "plus uv (hooks[, evals when `agentic`])". `uvx pre-commit install` already needs uv in every repo, so this covers Rust and TypeScript repos too.
- No install line, for any language.

**`CONTRIBUTING.md`:** a section "Releasing a new major version", rendered only when Go is managed. It has v0 → v1 (`Release-As: 1.0.0`) and the v2 steps from section 4. golangci-lint has no local version pin: CI pins it, and gofmt and goimports output barely changes between versions.

**`docs/dependencies.md`:**
- The lockfiles line gains "`go.sum` (`go mod verify`, `go mod tidy -diff` in CI)".
- The scanning line gains "govulncheck on the newest Go version (flags only vulnerable code that's called)".
- A new bullet, **Go version floor:** `go.mod`'s `go` line is the floor CI's first leg tests. A dependency that needs a newer Go raises it and fails that leg; Dependabot never raises it. Move it deliberately with `copier update -d go_version=1.N`.
- No Go cooldown line: Go has no client-side cooldown, so only Dependabot's applies.

**`docs/SETUP.md`:**
- `go` is dropped from both registry lines (account security and trusted publishing).
- The trusted-publishing step renders only when a language with a registry is left, so a Go-only repo skips it.
- No Go manual step: the existing "Immutable releases" checkbox covers Go.

**`docs/secrets.md` and `.github/secret-requirements.json`:**
- `publish-go` uses only `GITHUB_TOKEN`, so `includes/secrets.jinja` gets no new entry.
- When Go is managed and `publishes` is on, `secrets.md` adds after the OIDC sentence: "Go binaries are uploaded with the workflow's own `GITHUB_TOKEN`."

**`docs/verify.md`:** a Go section with three commands:
- `sha256sum -c SHA256SUMS`;
- the existing `gh attestation verify <file> --repo …` line, in public repos;
- `go install <module>/cmd/<slug>@<version>`.

**Unchanged:** `REVIEW.md`, `docs/THREAT_MODEL.md` and `docs/agent-policy.md` stay language-neutral. Races and unhandled errors are already on the rubric, and errcheck catches ignored `error` values.

**Agent permissions** (`.claude/settings.json`): `Bash(gh release upload *)` joins the deny list, for every repo, next to `gh release create`. A Go release is a tag (`git push` already asks) plus uploaded binaries.

## 6. Evals

_From [What does a Go repo with agentic get for evals?](https://github.com/ZeleMate/repo-template/issues/69)._

Nothing changes for Go. The starter eval doesn't drive the app in any language: `tasks.py` sends prompts straight to the model with Inspect's `generate()`. So a Go repo with `agentic: true` gets the same Python `evals/` (Inspect AI, run with uv, hash-locked) and the same `evals.yml` as Rust and TypeScript repos do today. It needs no Go step and no binary build.
- Rejected: a Go-native eval harness (none is as mature as Inspect, and it would split the eval setup by language), and no evals for Go.
- `agentic` stays `true` by default, whatever the language.

## 7. The `repo-standards` skills

_From [What does each skill and its eval cases need for Go?](https://github.com/ZeleMate/repo-template/issues/72)._

**`repo-new`:**
- Its description says "Python, TypeScript, Rust and Go".
- The prerequisite check gains `go` as optional, like `cargo`. Generating needs no Go, and verify skips Go without it.
- The step 4 summary lists the Go checks (section 8).
- `references/choosing-answers.md`:
  - `languages` gets `go` (folder `go/`). Pick it for a binary-shaped app: an agent CLI, MCP server or service.
  - The Toolchains table gets `go_version` and `go_module`. Vanity paths are allowed, but the template doesn't serve the `go-import` meta tag; the user hosts that.
  - The `publishes` text gains "Go: binaries on the GitHub release, no registry".
  - A new warning: a private Go module needs `GOPRIVATE` and git auth for `go install`, and gets no attestations or proxy warm.

**`repo-adopt`:**
- **Survey:** look for `go.mod` next to the other manifests.
- **Answers:** `go_module` is the existing `module` line, copied exactly (any difference breaks every import). `go_version` is the `go` line's `1.N`.
- **Layout** is kept; the placeholder list gains `cmd/<slug>/` and `internal/greeting/`.
- **`.golangci.yml`** is merged like other config. Run `golangci-lint migrate` first if it's v1, then combine theirs with the template's linters and formatters. Keep the template's gofmt and goimports, because the hook and CI's format check depend on them.
- **A Makefile** is kept. Tell the user that CodeQL's Go autobuild runs `make` first in public repos, so they should check the first CodeQL run.
- **GoReleaser:** move to the template's `publish-go` by default. Keep GoReleaser only for features `publish-go` lacks (archives, Homebrew taps, Docker images, signing). Then answer `publishes: false` and let their workflow run from the tag. This works only for a single-language repo with root `v` tags.
- **Release history:**
  - Set the Go entry in `.release-please-manifest.json` to the latest released version, not `0.1.0`. Otherwise a `/v3` module would next be tagged `v0.2.0`, which Go rejects, and `go-major-version` doesn't check majors 0 and 1.
  - The tag prefix must match the module's folder. When Go stays at the root in a multi-language repo, set `include-component-in-tag: false` on the Go package.
  - Existing tags stay as they are.

**`repo-github-setup`:** wording only. Nothing changes in the bootstrap or the settings audit.
- The SKILL's trusted-publishing bullet applies only to languages with a registry.
- `scripts/audit-github.sh` prints "trusted publisher registered on each registry" only when such a language is managed.

**`repo-template-update`:**
- A short Go section:
  - Raise the floor with `-d go_version=1.N`, then run `go mod tidy`.
  - Never edit `go.mod`'s `go` line alone.
  - For v2 and later, follow the generated `CONTRIBUTING.md`.
- The lockfile line gains `go mod tidy` (for `go.sum`).

**`repo-template-maintain`:**
- `go_dir` joins the computed-values list.
- `scripts/list-pins.sh` gains a `default` row for the newest known Go and for the newest known Python, both literals in `ci.yml.jinja`. Python's goes unreported today.
- It also gains a `binary` row for the golangci-lint copy in the template's own CI (section 8).
- The central Go pins (golangci-lint, `tools/go`) are noted like Gitleaks and OSV-Scanner. `actions/setup-go` and `actions/attest` are already picked up by the existing `uses:` scan.
- **The order at each Go release:**
  1. Move the central golangci-lint pin to a build made with the new Go, and cut a central release.
  2. Only then raise the template's newest known Go.

  The other way round turns CI red.

**Skill eval cases:** none new. A Go case would mostly test the template, which `test-template.sh` covers. The eval sandbox grants no Go module proxy and doesn't guarantee a Go toolchain, and Rust never got a case. If one is added later, a `repo-adopt` case with GoReleaser and a Makefile would show the most.

Every skill change bumps `.claude-plugin/plugin.json`'s version in the template release.

## 8. Tests

_From [What do test-template.sh and verify-generated.sh check for Go?](https://github.com/ZeleMate/repo-template/issues/73)._

**`scripts/test-template.sh` answer sets:**

| Set | Answers | Template assertions |
|---|---|---|
| `go` | `languages=[go]`, public, `publishes=true`, `agentic=false` | `go-versions: '["1.26", "1.27"]'`; `module github.com/example/demo-app` at the root; root `vX.Y.Z` tags and `bump-minor-pre-major` on the Go package; `sbom` needs `publish-go`; attestation and proxy-warm steps present |
| `go-priv` | `languages=[go]`, private, `agentic=true`, `go_version=1.27` | `go-versions: '["1.27"]'`; no attestation or proxy-warm steps; the mock evals pass next to Go (through verify) |
| `multi` (existing) | gains `go`: `python, typescript, rust, go` | `go_module` ends in `/go`; the Go package has `component: go` and `tag-separator: "/"`; `bump-minor-pre-major` on the Go package only; `sbom` needs both publish jobs |

Also in `test-template.sh`:
- `go` and `go-priv` join the secret-requirements loop.
- A table test of `go-major-version.sh` on a copy of the `go` set:

  | Manifest | Module | Expected |
  |---|---|---|
  | `2.0.0` | no suffix | fail |
  | `2.0.0` | `/v2` | pass |
  | `1.4.0` | `/v2` | pass |
  | `3.0.0` | `/v2` | fail |
- `pre-commit run golangci-lint-fmt --all-files` on the `go` set. Verify and `repo-lint` both skip that hook, so this is the only place its entry is tested.

**No `copier update` case.** None exists for any language today; the only Copier-update check is a `recopy` confirming `ci-local.yml` survives. Adding a language to an existing single-language repo would mean moving files into folders, which Copier can't do for any language, so it's out of scope.

**`skills/repo-new/scripts/verify-generated.sh`:**
- A `go)` case in `dir_for go`, skipped with "go not installed" when `go` is missing, as with cargo. It runs with `GOTOOLCHAIN=local`, so a Go older than the floor fails with Go's own "requires go >= …" message instead of downloading a toolchain:
  - `go mod tidy -diff`
  - `go vet ./...`
  - `go build ./...`
  - `go test -race ./...`
- golangci-lint (`fmt --diff`, then `run`) runs only when installed, like actionlint.
- No govulncheck: it needs network access to `vuln.go.dev`, and CI gates it.
- The pre-commit `SKIP` list is read from the `skip-hooks` default in `$central/.github/workflows/repo-lint.yml`, the central clone verify already makes, instead of the hard-coded `gitleaks,prettier,cargo-fmt`. Without this, verify fails on every Go repo, and the two lists could drift apart again.
- The header's "Needs:" line gains Go and golangci-lint, both optional.

**The template's own CI** (`.github/workflows/ci.yml`, job `test-template`):
- `actions/setup-go` with the newest known Go (1.27), which builds every answer set, the 1.26-floor ones included.
- golangci-lint as a checksum-verified binary at the central version, copied the way OSV-Scanner is already.

Without these, every Go check would be skipped in CI, and the starter `.golangci.yml` would never be tested before a release.

## Not verified

Everything below was read from docs and source but never run. Each item says where it gets checked in the build checklist.

| Fact | From | Checked by |
|---|---|---|
| `golangci-lint fmt` accepts file arguments together with `--config` from the repo root, and honours the config's `formatters` | [What are the Go local hooks, and which ids does repo-lint skip?](https://github.com/ZeleMate/repo-template/issues/70) | `test-template.sh` (step 4) |
| Which Go version built golangci-lint v2.15.0, so it lints Go 1.27 code | [What is the current Go toolchain for lint, vuln scan, coverage and Dependabot?](https://github.com/ZeleMate/repo-template/issues/62) | `test-template.sh` (step 4) |
| Building govulncheck and gocover-cobertura from the central `tools/go` module and running them against the caller's module | [What does the central go.yml run, with which inputs, in which central release?](https://github.com/ZeleMate/repo-template/issues/64) | live check (step 5) |
| setup-go's cache step with no `go.sum` (fallback: point the cache at `go.mod`) | [What does the central go.yml run, with which inputs, in which central release?](https://github.com/ZeleMate/repo-template/issues/64) | live check (step 5) |
| The coverage chain end to end (`go test -coverprofile` → gocover-cobertura → diff-cover), run from `go/` | [What is the current Go toolchain for lint, vuln scan, coverage and Dependabot?](https://github.com/ZeleMate/repo-template/issues/62) | live check (step 5) |
| CodeQL autobuild with `go.mod` in `go/` | [What is the current Go toolchain for lint, vuln scan, coverage and Dependabot?](https://github.com/ZeleMate/repo-template/issues/62) | live check (step 5) |
| OSV-Scanner's Go call analysis when the runner's Go can't build the module | [What is the current Go toolchain for lint, vuln scan, coverage and Dependabot?](https://github.com/ZeleMate/repo-template/issues/62) | live check (step 5), if it comes up; otherwise left open |
| release-please-action v5.0.0's bundled code has `tag-separator` (release-please 17.6.0) and produces `go/vX.Y.Z` | [How do Go modules version and release from a subdirectory?](https://github.com/ZeleMate/repo-template/issues/63) | live check (step 5) |
| `gh release upload` with a slash in the tag | [How do Go modules version and release from a subdirectory?](https://github.com/ZeleMate/repo-template/issues/63), [What does publishes mean for a Go repo?](https://github.com/ZeleMate/repo-template/issues/66) | live check (step 5) |
| The proxy warm right after release-please creates the draft's tag | [What does publishes mean for a Go repo?](https://github.com/ZeleMate/repo-template/issues/66) | live check (step 5) |
| Dependabot's handling of a module's `/v2` major | [What is the current Go toolchain for lint, vuln scan, coverage and Dependabot?](https://github.com/ZeleMate/repo-template/issues/62) | left open: the live check doesn't reach v2 |

## Build checklist

1. **Central, unreleased.** In `ZeleMate/workflows`:
   - add `go.yml` (section 3);
   - add the `tools/go` module and its Dependabot entry;
   - add `golangci-lint-fmt` to `repo-lint.yml`'s `skip-hooks` default.

   Merge, but don't tag yet.
2. **Template.** Make every change in sections 1, 2, 4 and 5:
   - `copier.yml`;
   - `template/`, including `ci.yml.jinja`'s `go` job and `release.yml.jinja`'s `publish-go`;
   - the template README.

   Leave the central pin alone for now.
3. **Plugin.** Make the skill changes in section 7, and the `verify-generated.sh`, `test-template.sh` and template CI changes in section 8.
4. **Test locally.** Run `test-template.sh` with `CENTRAL_DIR=<clone at the step 1 commit>`, with Go 1.27 and golangci-lint installed. Every answer set passes, and none of the Go checks is skipped.
5. **Live check**, on a throwaway repo, before any release. The agent building this runs it with the user, and the user approves creating the repo and pushing.
   1. Generate a **public** multi-language (Python + Go) repo from the template branch, with `publishes: true`. Public, because attestations and the proxy warm only run there.
   2. Point its `ci.yml` at the step 1 central commit SHA. The template pins the central repo by SHA, so `v1.1.0` doesn't need to exist yet.
   3. Open a PR that touches Go code. It checks setup-go's cache with no `go.sum`, the coverage chain and diff-cover from `go/`, the central tools build, and CodeQL autobuild with `go/`.
   4. Merge a `feat:`, then the release PR. Check:
      - the `go/v0.2.0` tag;
      - `gh release upload` with a slash in the tag;
      - `SHA256SUMS` and `gh attestation verify`;
      - the proxy warm;
      - `go install <module>/go/cmd/<slug>@v0.2.0`.
   5. Fix what fails, in the central repo or the template, and repeat.
   6. Record the results in this spec's Not verified table, then archive the repo (don't delete it).
6. **Central release.** Tag `ZeleMate/workflows` `v1.1.0`, then run `./scripts/bump-central-pin.sh v1.1.0` here.
7. **Template release.** A `feat:` minor, with the plugin version bumped, since skills changed. Generated repos without Go see only three changes: the central pin moving to `v1.1.0`, the `gh release upload` deny rule, and, without Python, the README's uv line. Update this spec's status line.
