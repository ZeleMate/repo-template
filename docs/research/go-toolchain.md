# The Go toolchain for lint, vuln scan, coverage and Dependabot

Question ([#62](https://github.com/ZeleMate/repo-template/issues/62), on map [#61](https://github.com/ZeleMate/repo-template/issues/61)): what Go toolchain should a managed language run in CI and locally in late 2026, and how does each tool fit the template's existing security and quality setup?

It feeds two decisions: what the central `go.yml` runs and with which inputs, and what the Go Copier questions and starter files look like.

Sources: go.dev docs and release notes, the Go module proxy, golangci-lint's docs and repo, the `golang.org/x/vuln` source at v1.10.0, the `golang/govulncheck-action` and `actions/setup-go` repos, OSV-Scanner's docs, diff-cover's README and source, `gocover-cobertura`'s source, GitHub's CodeQL and Dependabot docs, the `dependabot-core` source and issue tracker, Semgrep's docs and the live `p/default` ruleset. Checked on 2026-11-21. Claims I could not confirm from a primary source are marked, and listed again at the end.

## Summary

| Concern | Recommendation | Pin it how |
|---|---|---|
| Go versions | Matrix of the two supported releases, **1.26 and 1.27** today, through `actions/setup-go` | Caller passes the list, as with `python-versions` |
| Lint and format | **golangci-lint v2** (v2.15.0), `version: "2"` config, `linters.default: standard`, formatter **gofmt** (not gofumpt) | Checksum-verified release binary, like OSV-Scanner and Gitleaks today |
| Vulnerabilities | **govulncheck** (v1.10.0) at the default symbol level, text output, in `go.yml` | `go.sum`-locked tool in the central repo, or `go run …@v1.10.0` |
| OSV-Scanner | Already scans `go.mod` as the template runs it; does not check the standard library by default | No change needed to cover Go modules |
| Coverage | `go test -coverprofile` → **gocover-cobertura** (v1.5.0) → `diff-cover` at 90%, as for TypeScript | Same as govulncheck |
| Tidiness | `go mod tidy -diff` and `go mod verify` | Built into `go` |
| CodeQL | Default setup handles Go with autobuild; a root `cmd/` + `internal/` layout fits the documented autobuild path | Nothing to pin |
| Semgrep CE | `p/default` already carries 84 Go rules | Already locked in central `tools/uv.lock` |
| Dependabot | `gomod` with the same groups and cooldowns as `cargo`; it will **not** bump the Go version for you | n/a |

## Go versions and `go.mod`

**Supported releases.** "Each major Go release is supported until there are two newer major releases" ([release history](https://go.dev/doc/devel/release)). Go 1.27.0 shipped on 2026-08-19 and Go 1.26.0 on 2026-02-10, so the supported pair today is **1.26 and 1.27** (latest patches go1.27.4 and go1.26.11, both 2026-11-10). Go 1.25.14 was the last 1.25 patch. Go 1.28 is due around February 2027 (an inference from the six-month cadence), and it will drop 1.26.

**The `go` line is the floor.** "The `go` line declares the minimum required Go version for using the module or workspace", and an older toolchain refuses to load the module ([Go toolchains](https://go.dev/doc/toolchain)). It also sets the language version the compiler enforces. This matches the map's "the `go` line in `go.mod` is the floor".

**The `toolchain` line is a suggestion.** It names a preferred toolchain and only matters when the running `go` is older than it. When it equals the `go` line it can be left out, but commands that update the `go` line may write it back ([Go toolchains](https://go.dev/doc/toolchain)).

**`GOTOOLCHAIN`.** The default is `auto` (set in `$GOROOT/go.env`): `go` switches to, and downloads, a newer toolchain when the `go` or `toolchain` line asks for one. `local` never switches and errors out instead ([Go toolchains](https://go.dev/doc/toolchain)).

**What the starter's `go.mod` should say.** Since Go 1.26, `go mod init` with toolchain 1.N writes `go 1.(N-1).0` ([Go 1.26 release notes](https://go.dev/doc/go1.26)). With Go 1.27 installed it writes `go 1.26.0`, which is exactly the floor of the supported pair. So the starter can write `go 1.26.0` (the older supported release, `.0` patch) and no `toolchain` line. The Copier question, if there is one, mirrors `python_version`: the floor minor. Go 1.27 added a default `stdversion` vet check to `go test` that flags standard library symbols newer than the `go` line ([Go 1.27 release notes](https://go.dev/doc/go1.27)), so the floor is enforced by the tests too.

**`actions/setup-go`.** Current release v7.1.0 (2026-11-17); v7.0.0 was 2026-07-16 ([releases](https://github.com/actions/setup-go/releases)). Relevant behaviour:

- `go-version-file: go.mod` uses the `toolchain` line if present, else the `go` line ([README](https://github.com/actions/setup-go)).
- `stable` is the newest release; `oldstable` is the latest patch of the previous minor ([advanced usage](https://github.com/actions/setup-go/blob/main/docs/advanced-usage.md)). A matrix of `['1.26', '1.27']` installs the latest patch of each from the manifest. The aliases would avoid a caller edit at each Go release, but the template already passes an explicit list for Python, and an explicit list stays visible in the caller.
- **It exports `GOTOOLCHAIN=local`** to the rest of the job ([`src/main.ts`, `setGoToolchain`](https://github.com/actions/setup-go/blob/main/src/main.ts)), so a matrix leg really runs the version it says. If a dependency update raises the `go` line above 1.26, the 1.26 leg fails instead of silently downloading 1.27. That is the check we want (see Dependabot below).
- Module caching is on by default and keyed on `go.mod` since v6; set `cache-dependency-path` to `<dir>/go.sum` to key on the lock ([README](https://github.com/actions/setup-go)). For a `working-directory` input, `cache-dependency-path: ${{ inputs.working-directory }}/go.sum`, the same shape `python.yml` uses for `uv.lock`.

**Testing two releases.** The `python.yml` pattern carries over: a `go-versions` JSON-list input, `strategy.matrix.go: ${{ fromJSON(inputs.go-versions) }}`, `fail-fast: false`, and the changed-line coverage step only on the first (floor) entry. Copier writes the list from the floor answer, as it does for `python-versions`.

## Lint and format: golangci-lint v2

**Version.** v2.15.0 (2026-10-16) is the latest on the [module proxy](https://proxy.golang.org/github.com/golangci/golangci-lint/v2/@latest) and the [releases page](https://github.com/golangci/golangci-lint/releases). v2.14.0 was 2026-09-24 and v2.13.0 2026-08-19, so roughly a minor a month. Each release ships a `golangci-lint-<ver>-checksums.txt`, per-archive SBOMs and a release attestation.

**Install and pin.** The docs say "It's highly recommended installing a specific version of golangci-lint", for reproducible CI ([CI installation](https://golangci-lint.run/docs/welcome/install/ci/)). They advise against `go install`, the tools pattern and `go tool`: those "aren't guaranteed to work", and "We don't recommend using `go tool`" ([local installation](https://golangci-lint.run/docs/welcome/install/local/)). So golangci-lint is the one Go tool that should come as a binary. Three options:

1. **A checksum-verified download** of `golangci-lint-2.15.0-linux-amd64.tar.gz`, with `GOLANGCI_LINT_VERSION` and `GOLANGCI_LINT_SHA256` env vars, exactly like the OSV-Scanner and Gitleaks steps in central `security.yml`. This is my recommendation: it matches the existing pattern and the pin-refresh script can treat it the same way.
2. **The official action**, `golangci/golangci-lint-action` (v9.3.0, 2026-06-29, node24; [repo](https://github.com/golangci/golangci-lint-action), [releases](https://github.com/golangci/golangci-lint-action/releases)), SHA-pinned, with `version: v2.15.0`. It needs `actions/setup-go` first, caches `~/.cache/golangci-lint`, validates the config against the version's JSON schema (`verify: true`), and can annotate PRs. Its `install.ts` downloads the release archive with `tc.downloadTool` and I found no checksum check in it ([`src/install.ts`](https://github.com/golangci/golangci-lint-action/blob/main/src/install.ts)). With a minor version (`v2.13`) it resolves the latest patch, so it must be given a full patch version to be pinned.
3. **The install script** (`curl -sSfL https://golangci-lint.run/install.sh | sh -s -- -b … v2.15.0`, from the local install page). It pipes a remote script to `sh`, which the template avoids elsewhere.

**Build-version coupling.** golangci-lint supports Go versions lower than or equal to the Go version it was built with ([FAQ](https://golangci-lint.run/docs/welcome/faq/)); since v1.60.3 it errors out when the project targets a newer Go. So the golangci-lint pin has to move forward at each Go major release, before generated repos raise their floor. Not verified: which Go version v2.15.0 was built with (I did not download the binary).

**Config.** v2 needs `version: "2"`. `linters.default` is `standard` (the default), `all`, `none` or `fast`; `formatters.enable` lists formatters; `linters.exclusions.presets` replaced v1's default exclusions; `run.go` defaults to the `go.mod` version ([configuration file](https://golangci-lint.run/docs/configuration/file/), [migration guide](https://golangci-lint.run/docs/product/migration-guide/)). The `standard` set is errcheck, govet, ineffassign, staticcheck and unused ([quick start](https://golangci-lint.run/docs/welcome/quick-start/)); v2 merged gosimple and stylecheck into staticcheck. A starter `.golangci.yml` could be:

```yaml
version: "2"
linters:
  default: standard
  # Additions are a judgement call for the grilling ticket, e.g. gosec, revive, errorlint.
formatters:
  enable:
    - gofmt
    - goimports
```

`default: all` is a bad default: the CI page warns that it breaks builds when a release adds a linter. Whether to add `gosec` is open: Semgrep and CodeQL already cover security, so it would mostly duplicate them.

**gofmt or gofumpt.** gofmt is the norm. It ships with Go, and golangci-lint's `formatters` default is "standard Go formatting" ([configuration file](https://golangci-lint.run/docs/configuration/file/)). gofumpt (v0.12.0, 2026-09-07, [proxy](https://proxy.golang.org/mvdan.cc/gofumpt/@latest)) is a stricter, backwards-compatible fork of gofmt ([README](https://github.com/mvdan/gofumpt)): gofmt after gofumpt changes nothing, but every contributor's editor needs gofumpt turned on (gopls has a setting) or files will drift. For a speculative template, gofmt plus goimports is the safer default; gofumpt is a one-line change for repos that want it.

**Commands.** `golangci-lint run` runs the linters and also the formatters listed under `formatters` ([CLI reference](https://golangci-lint.run/docs/configuration/cli/)), so one CI step covers both. `golangci-lint fmt` rewrites files, and `golangci-lint fmt --diff` only prints diffs ([CLI reference](https://golangci-lint.run/docs/configuration/cli/)). The default issues exit code is 1. `--new-from-merge-base` limits output to new issues, but the template's other languages lint everything, so there is no reason to use it here.

**Local hooks.** golangci-lint's own pre-commit hooks (`golangci-lint`, `golangci-lint-full`, `golangci-lint-fmt`, `golangci-lint-config-verify`) use `language: golang`, which builds the tool from source ([`.pre-commit-hooks.yaml`](https://github.com/golangci/golangci-lint/blob/main/.pre-commit-hooks.yaml)), the install route its own docs discourage. The template's pattern for TypeScript and Rust is a `repo: local` hook with `language: system` that uses the developer's toolchain, e.g. `gofmt -l -w` (always present with Go) or `golangci-lint fmt` (needs a local golangci-lint). Either way, central `repo-lint.yml` has `skip-hooks` defaulting to `gitleaks,prettier,cargo-fmt`, so a Go hook id has to be added to that default (a central release) or passed by the caller, or `repo-lint` will try to run it without Go installed.

## Vulnerabilities: govulncheck and OSV-Scanner

**govulncheck.** `golang.org/x/vuln` v1.10.0, tagged 2026-11-17 ([proxy](https://proxy.golang.org/golang.org/x/vuln/@latest)).

- Exit codes, from the v1.10.0 source ([`internal/scan/errors.go`](https://go.googlesource.com/vuln/+/refs/tags/v1.10.0/internal/scan/errors.go)): 0 for no findings, **3 for vulnerabilities found**, 2 for usage errors (including no packages matched), 1 for other errors. The docs add that JSON, SARIF and OpenVEX output always exit 0 ([govulncheck docs](https://pkg.go.dev/golang.org/x/vuln/cmd/govulncheck)), so CI must use text output to gate.
- At the default `-scan symbol` level, text mode returns 3 only when a vulnerable **function is called**; at `-scan package` when a vulnerable package is imported; at `-scan module` when a vulnerable module is required ([`internal/scan/text.go`](https://go.googlesource.com/vuln/+/refs/tags/v1.10.0/internal/scan/text.go), [`internal/scan/flags.go`](https://go.googlesource.com/vuln/+/refs/tags/v1.10.0/internal/scan/flags.go)). Reachability comes from static analysis; calls through `reflect` are not seen ([docs](https://pkg.go.dev/golang.org/x/vuln/cmd/govulncheck)).
- It checks the **standard library** too, for the Go version of the `go` command on `PATH` ([docs](https://pkg.go.dev/golang.org/x/vuln/cmd/govulncheck)). In CI that is the matrix leg's version, so running it on the newest leg (the toolchain a release would build with) is enough. Because setup-go installs the latest patch, a stdlib finding there means a fix isn't released yet.
- **The official action is not a fit.** `golang/govulncheck-action` v1.1.0 (2026-07-10) is a composite action that runs its own checkout and setup-go (default `go-version-input: stable`, `check-latest: true`), then `go install golang.org/x/vuln/cmd/govulncheck@latest` ([`action.yml`](https://github.com/golang/govulncheck-action/blob/master/action.yml)). The tool version is unpinned and the Go version floats, which the template's pinning rules don't allow.
- **How to pin.** Two options, both verified by Go's checksum database rather than a hand-kept SHA:
  1. `go run golang.org/x/vuln/cmd/govulncheck@v1.10.0 ./...` in the job.
  2. A small Go module in the central repo (say `tools/go/go.mod`) with `tool golang.org/x/vuln/cmd/govulncheck` and `tool github.com/boumenot/gocover-cobertura` directives, hash-locked in its `go.sum` and run through the self-checkout, the same idea as `tools/uv.lock`. `go get -tool` and `go tool` exist since Go 1.24 ([managing dependencies](https://go.dev/doc/modules/managing-dependencies#tools)). Dependabot `gomod` on the central repo would then move both tools. I did not test running a tool from that module against the caller's module (`go -C … tool govulncheck -C <workdir> ./...`); it should work but needs a check on the first build.

**OSV-Scanner already covers Go modules.** Central `security.yml` runs `osv-scanner scan source --recursive .` (v2.7.0), and OSV-Scanner reads `go.mod` in source scans ([supported lockfiles](https://google.github.io/osv-scanner/supported-languages-and-lockfiles/)). That is why Go is already a Dependabot extra ecosystem with a working scan today. Two differences from govulncheck:

- **No standard library check by default.** "By default, OSV-Scanner does not scan the Go version from `go.mod` files", because the `go` line is a minimum, not the toolchain in use; `ScanGoModVersion = true` turns it on and `GoVersionOverride` sets a version ([configuration](https://google.github.io/osv-scanner/configuration/)). govulncheck in `go.yml` covers the stdlib with the real CI toolchain, so leave OSV-Scanner's default alone.
- **Go call analysis is on by default** and uses the govulncheck library, which needs `go` on `PATH` ([scan source](https://google.github.io/osv-scanner/usage/scan-source)). The `dependencies` job has no setup-go, so it would use whatever Go the runner image has, and with `GOTOOLCHAIN=auto` that `go` may download the toolchain the `go` line asks for. Not verified: what OSV-Scanner does when that fails, and whether uncalled findings fail the scan. GitHub issues on the OSV-Scanner repo report that uncalled findings don't fail it and describe aggregation bugs ([#3162](https://github.com/google/osv-scanner/issues/3162)), and a docs issue says call analysis downloads modules and fills caches ([#3273](https://github.com/google/osv-scanner/issues/3273)). Options for the `go.yml` ticket: leave `security.yml` alone (govulncheck gates on reachable vulns, OSV-Scanner reports the rest), or add `--no-call-analysis=go` so OSV-Scanner flags every vulnerable required module. The second is stricter and could turn a green caller red, which section 7 of the [central workflows spec](../specs/central-workflows.md) counts as a major central release.

## Coverage into diff-cover

diff-cover accepts Cobertura, Clover, JaCoCo XML and LCov ([README](https://github.com/Bachmann1234/diff_cover)); it does not read Go's coverprofile. `typescript.yml` already feeds it Cobertura (`coverage/cobertura-coverage.xml`), so Go should too.

- **Converter: `github.com/boumenot/gocover-cobertura`**, v1.5.0 (2026-05-15, [proxy](https://proxy.golang.org/github.com/boumenot/gocover-cobertura/@latest)). It reads a coverprofile on stdin and writes Cobertura XML on stdout; run it from the module directory, or pass `-path` ([README](https://github.com/boumenot/gocover-cobertura)). Useful flags: `-ignore-gen-files`, `-by-files`, `-strict`. The LCov alternative, `github.com/jandelgado/gcov2lcov`, last released v1.1.1 in October 2024 ([proxy](https://proxy.golang.org/github.com/jandelgado/gcov2lcov/@latest)).
- **Paths line up.** gocover-cobertura writes the module's absolute directory as `<sources><source>` and each file path relative to the module root ([source](https://github.com/boumenot/gocover-cobertura/blob/master/gocover-cobertura.go)). diff-cover joins each `<source>` with the class `filename` when it matches diff paths ([`violations_reporter.py`](https://github.com/Bachmann1234/diff_cover/blob/main/diff_cover/violationsreporters/violations_reporter.py)). With conversion and diff-cover on the same runner this should resolve, including with a `go/` working directory. Not verified end to end.
- **The steps**, on the floor leg of a pull request, as in `python.yml`:

  ```sh
  go test -race -covermode=atomic -coverprofile=coverage.out ./...
  gocover-cobertura -ignore-gen-files < coverage.out > coverage.xml
  diff-cover coverage.xml --compare-branch="origin/${BASE_REF}" --fail-under=90
  ```

  `diff-cover` stays in central `tools/uv.lock`; `gocover-cobertura` is pinned the same way as govulncheck. `-race` needs cgo, which `ubuntu-latest` has; whether to run with `-race` at all is a choice for the `go.yml` ticket.

## Tidiness

- `go mod tidy -diff` (Go 1.23+) changes nothing and "exits with a non-zero code if updates are needed" ([Go 1.23 release notes](https://go.dev/doc/go1.23), [`go mod tidy`](https://go.dev/ref/mod#go-mod-tidy)). This is the whole check; the old `go mod tidy && git diff --exit-code` dance isn't needed.
- `go mod verify` checks that the downloaded modules in the cache haven't changed since download ([`go mod verify`](https://go.dev/ref/mod#go-mod-verify)).
- `go build` and `go test` already act as if `-mod=readonly` were set (since Go 1.16): they error if `go.mod` needs changes ([go.mod reference](https://go.dev/ref/mod)). Together with `tidy -diff` this is the Go equivalent of `uv sync --locked` and `cargo … --locked`.

## Code scanning

**CodeQL.** Go supports `autobuild` and `manual` build modes, not `none`, so default setup uses autobuild ([compiled languages](https://docs.github.com/en/code-security/code-scanning/creating-an-advanced-setup-for-code-scanning/codeql-code-scanning-for-compiled-languages)). Go autobuild tries `make`, `ninja`, `./build`, `./build.sh` (each must be followed by a working `go list ./...`); otherwise it finds `go.mod`, runs `go get` unless vendoring, and extracts all Go code "similar to running `go build ./...`". With default setup it reads `go.mod` to install a compatible Go ([build options](https://docs.github.com/en/code-security/reference/code-scanning/codeql/build-options-for-compiled-languages)).

- A root `go.mod` with `cmd/<name>/main.go` and `internal/` is the plain case for that path, so default setup should need nothing. Don't add a `Makefile` to the starter that fails without extra tools: autobuild would try `make` first.
- Not verified: Go in a `go/` subfolder (multi-language layout). The docs don't cover `go.mod` below the root or `go.work`. Third-party reports say the autobuilder extracts every `go.mod` it finds and can break under an unrelated `go.work` ([example](https://github.com/rios0rios0/pipelines/pull/822)); that's not an official source. Check it on the first multi-language test repo.
- `bootstrap-github.sh` enables default setup with no language list, so Go is picked up by detection.

**Semgrep CE.** Go is generally available in Semgrep ([supported languages](https://docs.semgrep.dev/supported-languages)). Community Edition does single-file, single-function taint analysis; cross-file analysis and Supply Chain are paid ([CE vs Pro](https://docs.semgrep.dev/semgrep-pro-vs-oss)). The `p/default` ruleset that central `security.yml` runs had **84 Go rules** out of 1,074 when I fetched it from `semgrep.dev/c/p/default` (Python 243, TypeScript 150, Rust 4). The source repo has Go rules for the standard library and for gorilla, gorm, grpc, jwt-go, AWS Lambda, otto and templates ([semgrep-rules/go](https://github.com/semgrep/semgrep-rules/tree/develop/go)). So private Go repos get real SAST from the existing `sast` job with no change.

## Dependabot `gomod`

- Supported for version and security updates, private repos and vendoring ([supported ecosystems](https://docs.github.com/en/code-security/dependabot/ecosystems-supported-by-dependabot/supported-ecosystems-and-repositories)). `cooldown` supports `gomod`, including the SemVer-bump days ([options reference](https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference)). Pseudo-versions are always treated as prereleases. So the `cargo` block in `dependabot.yml.jinja` carries over as is: `cooldown.default-days: 7`, `semver-major-days: 14`, a `gomod-minor-patch` group with `update-types: [minor, patch]`, prefix `deps`, `directory` from the Go working directory.
- The `managed_root` map in `dependabot.yml.jinja` (`{'python': 'uv', 'typescript': 'npm', 'rust': 'cargo'}`) needs `'go': 'gomod'`, or a single-language Go repo that also ticks `gomod` in `extra_ecosystems` gets two `gomod` entries for `/`.
- Go's major versions are new module paths (`/v2`), so a v1 → v2 bump is an import-path change, not a version edit. I didn't find Dependabot docs on how it treats that; assume majors are rare and manual.
- **Dependabot does not update the Go version.** It doesn't parse the `toolchain` line as a dependency; it only reads `go version` at runtime ([`file_parser.rb`](https://github.com/dependabot/dependabot-core/blob/main/go_modules/lib/dependabot/go_modules/file_parser.rb)). Bumping the `toolchain` line is an open request ([#13520](https://github.com/dependabot/dependabot-core/issues/13520)), and so is a `.go-version` file ([#15252](https://github.com/dependabot/dependabot-core/issues/15252)). So the floor moves by hand or through a template release, as Python's does.
- **A dependency update can raise the `go` line silently**: `go get` lifts it to the highest `go` line among the requirements. An option to skip such updates is an open request ([#15714](https://github.com/dependabot/dependabot-core/issues/15714)). In a generated repo, the floor leg of the matrix (with setup-go's `GOTOOLCHAIN=local`) then fails, the merge gate goes red, and automerge waits. That's the right outcome, but `AGENTS.md` or `docs/dependencies.md` should say what to do: raise the floor deliberately, or hold the dependency.

## What this means for `go.yml`

A sketch for the grilling ticket, in the shape of `python.yml` and `rust.yml`. Nothing here is decided.

- Inputs: `go-versions` (JSON list, required, Copier writes it), `working-directory` (default `.`).
- Steps per leg: checkout (`fetch-depth: 0`), central self-checkout moved to `$RUNNER_TEMP/central`, `actions/setup-go` with `go-version: ${{ matrix.go }}` and `cache-dependency-path: <dir>/go.sum`, `go mod tidy -diff`, `go mod verify`, checksum-verified golangci-lint, `golangci-lint run`, `go test -race -coverprofile=coverage.out ./...`, then on the floor leg of a PR: gocover-cobertura and diff-cover; on the newest leg: govulncheck.
- Permissions: `contents: read` only; nothing needs a secret, so it can sit under the merge gate.
- New pins for the pin refresh and `list-pins.sh`: `actions/setup-go`, the golangci-lint version and SHA-256, and the govulncheck and gocover-cobertura versions (or the central `tools/go/go.sum`).

## What was and wasn't verified

Verified from primary sources: the release policy and current versions; `go`/`toolchain`/`GOTOOLCHAIN` semantics; setup-go's `go-version-file` order, aliases, caching and `GOTOOLCHAIN=local` export (source); golangci-lint's current version, config format, standard linters, formatters, install advice and pre-commit hooks; the golangci-lint action's install code (no checksum check found); govulncheck's exit codes and scan levels (source); the govulncheck action installing `@latest` (source); OSV-Scanner's `go.mod` support, stdlib default and call-analysis default; diff-cover formats and Cobertura `<source>` handling (source); gocover-cobertura's output paths (source); `go mod tidy -diff`; CodeQL Go build modes and autobuild steps; Semgrep CE scope and `p/default` Go rule count; Dependabot `gomod` support, cooldown, and its lack of Go version updates (source and open issues).

Not verified:

- Which Go version golangci-lint v2.15.0 was built with.
- Running govulncheck and gocover-cobertura through `go tool` from a separate central module against the caller's module.
- The full chain coverprofile → gocover-cobertura → diff-cover on a real PR, especially from a `go/` working directory.
- What OSV-Scanner's Go call analysis does when the runner's Go can't build the module, and whether uncalled findings fail the scan (only GitHub issue reports).
- CodeQL autobuild with `go.mod` in a subfolder or with a `go.work`.
- How Dependabot handles Go major versions (`/v2` module paths).
- Go 1.28's date (inferred from the release cadence).
