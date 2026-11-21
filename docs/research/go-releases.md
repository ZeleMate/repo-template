# How Go modules version and release from a subdirectory

Question ([#63](https://github.com/ZeleMate/repo-template/issues/63), on map [#61](https://github.com/ZeleMate/repo-template/issues/61)): how does a Go module version, tag and release at the repo root and from a subdirectory, and what does that mean for release-please, binaries and attestations in this template?

**Short answer.** A Go module in `go/` must be tagged `go/vX.Y.Z`. release-please can make exactly that tag with `"component": "go"` and `"tag-separator": "/"`, which is how `googleapis/google-cloud-go` already tags its nested modules. "Publishing" a Go module means pushing that tag: there is no registry account, token or OIDC step, and the module proxy fetches the version when someone asks for it. GoReleaser's open-source edition can't release from a prefixed tag (the monorepo feature is Pro-only), so the plain path, `go build` for each target plus `actions/attest` plus `gh release upload` into the draft release, is the one that works for both layouts. Don't commit `go.work`.

Sources: the Go modules reference (go.dev/ref/mod), go.dev module docs, proxy.golang.org and pkg.go.dev/about, release-please source at v17.11.2 (latest, 2026-08-24) and the release-please-action v5.0.0 lockfile, GoReleaser docs and source at v2.20.3 (latest, 2026-11-20), the `actions/attest` and `actions/attest-build-provenance` READMEs (both v4.2.2), the GitHub REST docs for releases, and `cli/cli` source. Checked on 2026-11-21.

## How the template releases today

From `template/.github/workflows/[% if languages %]release.yml[% endif %].jinja`, `template/[% if languages %]release-please-config.json[% endif %].jinja` and the manifest:

- One release-please run on push to `main`, with a package per language. In a single-language repo the package path is `.`; with several languages each sits in its own folder (`python/`, `typescript/`, `rust/`) and gets `"component": "<language>"`.
- `include-component-in-tag` is `true` only for multi-language repos, so tags are `v1.2.3` (single) or `python-v1.2.3` (multi, default `-` separator).
- `draft: true` and `force-tag-creation: true`: the tag exists as soon as release-please runs, and the release stays a draft until the `sbom` job uploads `sbom.spdx.json` and publishes it. Immutable releases can't take assets once published.
- `publish-*` jobs run only when `publishes` is true, use OIDC trusted publishing, and add `actions/attest-build-provenance` only when `is_public` (attestations need a public repo or GitHub Enterprise Cloud).

## Go's tag rules

- **Module path = repo path + subdirectory.** "A module path consists of a repository root path, a directory within the repository (usually empty), and a major version suffix (only for major version 2 or higher)." ([ref/mod, Module paths](https://go.dev/ref/mod#module-paths))
  - Single language at the root: `module github.com/<owner>/<repo>`.
  - Multi-language in `go/`: `module github.com/<owner>/<repo>/go`. The starter binary installs as `go install github.com/<owner>/<repo>/go/cmd/<name>@latest`.
- **Subdirectory tags carry the directory as a prefix.** "each tag name must be prefixed with the module subdirectory, followed by a slash". The `gopls` module's `v0.4.0` "must have the tag named `gopls/v0.4.0`". ([ref/mod, Mapping versions to commits](https://go.dev/ref/mod#vcs-version); the same rule with `module1/v1.2.3` is in [Managing module source](https://go.dev/doc/modules/managing-source).) So `go/` means tags `go/vX.Y.Z`. `go-vX.Y.Z`, the template's current multi-language form, is not a Go version tag and the `go` command would ignore it.
- **Major versions v2+ change the module path.** "Starting with major version 2, module paths must have a major version suffix like `/v2`"; the tag's major must match the suffix ([ref/mod, Major version suffixes](https://go.dev/ref/mod#major-version-suffixes)). Because the template's `go.mod` exists, a `v2.0.0` tag on a module without `/v2` is just invalid; the `+incompatible` escape applies only to modules with no `go.mod` at the repo root. The v2 step is a code change (edit `go.mod`, rewrite internal imports), per [Module release and versioning workflow](https://go.dev/doc/modules/release-workflow). The `go.mod` may stay in `go/` or move to `go/v2/`; both work ([ref/mod](https://go.dev/ref/mod#vcs-version)). Tags would be `go/v2.0.0` in either case.
- **Tags are permanent.** "Once a tag is created, it should not be deleted or changed to a different revision", or clients get a checksum security error ([ref/mod](https://go.dev/ref/mod#vcs-version), [Publishing a module](https://go.dev/doc/modules/publishing)). The fix for a bad release is a `retract` directive in `go.mod` plus a new version ([ref/mod, retract](https://go.dev/ref/mod#go-mod-file-retract)).
- **A package can't be named `go`.** `go` is a Go keyword, so code directly in `go/` would need another package name. Not a problem for the starter (`cmd/<name>` and `internal/` only), but worth a line in the starter docs.
- **LICENSE.** When `go` zips a module from a subdirectory with no `LICENSE` of its own, it copies the repository root's `LICENSE` ("files named `LICENSE` specifically") ([ref/mod, Module zip files](https://go.dev/ref/mod#zip-files)). The template's root `LICENSE` covers `go/` for pkg.go.dev's license check; `LICENSES/` (REUSE) alone would not.
- **Nested modules are excluded.** A module zip leaves out any subdirectory with its own `go.mod` ([ref/mod](https://go.dev/ref/mod#zip-files)).

## What happens after a tag is pushed

- **Nothing, until someone asks.** proxy.golang.org doesn't watch tags; a new version is fetched on the first `go get module@version`, and "should be available within one minute" ([proxy.golang.org](https://proxy.golang.org/)). The documented nudge is `GOPROXY=proxy.golang.org go list -m example.com/mymodule@v0.1.0` after `git push origin v0.1.0` ([Publishing a module](https://go.dev/doc/modules/publishing)).
- **The proxy keeps what it fetched.** "We do not accept requests to remove cached modules or versions" and a deleted release "may still be available in the mirror" ([proxy.golang.org](https://proxy.golang.org/)).
- **pkg.go.dev reads from the proxy.** "Data for the site is downloaded from proxy.golang.org"; you can also press "Request" on the package page or fetch `https://proxy.golang.org/<module>/@v/<version>.info` ([pkg.go.dev/about](https://pkg.go.dev/about)). Retracted versions are hidden there too.
- **sum.golang.org** records the version's hash; if it isn't in the log yet, "the checksum database will try to fetch it from the origin server before replying" ([ref/mod, Checksum database](https://go.dev/ref/mod#checksum-database)).
- **Private modules.** `GOPRIVATE` sets the default for `GONOPROXY` and `GONOSUMDB`; matched modules are fetched "directly from its version control repository", bypassing the proxy and checksum database ([ref/mod, Environment variables](https://go.dev/ref/mod#environment-variables), [Private modules](https://go.dev/ref/mod#private-modules)). The proxy "can only access publicly available source code" ([proxy.golang.org](https://proxy.golang.org/)). Consumers of a private repo set `GOPRIVATE=github.com/<owner>/*` and need git credentials; nothing on the release side changes.
- **Draft releases don't matter to Go.** The `go` command reads git tags, not GitHub releases. With `force-tag-creation` the tag is real while the release is still a draft, so the module version is fetchable before the `sbom` job publishes the release.

**For "what does `publishes` mean for a Go repo?":** there is no registry upload to switch on. Candidates: (a) `publishes` adds a step that warms the proxy (`go list -m` against proxy.golang.org) for public repos, and/or (b) `publishes` means "attach binaries to the GitHub release". Either way, a public repo's tagged versions become installable whether or not `publishes` is set, because the tag alone is the release.

## release-please

- **The `go` strategy only writes the changelog.** `src/strategies/go.ts` adds a `CHANGELOG.md` update, plus an optional `version-file` whose `const Version = "x.y.z"` line it rewrites (`src/updaters/go/version-go.ts`). It never touches `go.mod`, which is right: Go has no version field in `go.mod`. The docs describe it as "A repository with a CHANGELOG.md" ([customizing.md](https://github.com/googleapis/release-please/blob/main/docs/customizing.md)).
- **It can produce `go/vX.Y.Z`.** Tag names are built in `src/util/tag-name.ts` as `${component}${separator}${'v'}${version}`, default separator `-`. The config schema has a per-package (or top-level) `tag-separator`, wired through `src/manifest.ts` (present at v17.6.0, the version bundled in release-please-action v5.0.0's lockfile). The parser accepts any non-alphanumeric separator, `/` included. So a package
  ```json
  "go": { "release-type": "go", "component": "go", "tag-separator": "/", "package-name": "<slug>" }
  ```
  gets tags `go/v1.2.3`. `googleapis/google-cloud-go` runs release-please with top-level `"tag-separator": "/"` and `include-component-in-tag: true`, and its tags look like `workstations/v1.10.1`.
- **Set the separator per package, not top level.** A top-level `/` would turn `python-v1.2.3` into `python/v1.2.3` in the same repo, which changes existing repos' tag format on `copier update` and risks release-please not matching the previous `python-v…` tag (not tested).
- **The component must equal the directory.** Go needs the prefix to be the module subdirectory, so the component for `go/` is `go`, which matches the template's existing "component = language name = folder" pattern.
- **Single language at the root:** `include-component-in-tag: false` already gives `v1.2.3`, which is the correct Go tag for a root module. No change.
- **Release name.** For a component package it is `go: v1.2.3`; at the root it is `v1.2.3` (`src/strategies/base.ts`). Relevant if a tool looks drafts up by name (GoReleaser does, below).
- **v2 bumps.** release-please would compute `2.0.0` for a breaking change at `>=1.0.0` without editing the module path, producing a tag the `go` command rejects. Options for the spec: document that leaving v1 is a manual step (edit `go.mod`, imports, then `Release-As: 2.0.0`), and keep the starter at `0.1.0` with `bump-minor-pre-major` so breaking changes before 1.0 stay minor. I didn't find a release-please setting that guards against this.
- **Outputs.** release-please-action names per-path outputs `go--release_created` and `go--tag_name`; the template's `out(dir, field)` macro already handles that.

## Binaries

### GoReleaser (open-source edition)

- **Prefixed tags don't work in OSS.** The monorepo feature (`monorepo.tag_prefix`, `dir`) "is exclusively available with GoReleaser Pro" ([monorepo](https://goreleaser.com/customization/monorepo/)). In OSS, `internal/pipe/git/git.go` takes the current tag from `GORELEASER_CURRENT_TAG`, else `git tag --points-at HEAD`, else `git describe`, sets the version to the tag minus a leading `v`, and `internal/pipe/semver/semver.go` fails with "failed to parse tag … as semver" on `go/v1.2.3`. `ignore_tags` and `ignore_tag_prefixes`, which would help in a multi-language repo whose release commit carries several tags, are Pro-only too ([git](https://goreleaser.com/customization/git/)). There is no OSS `release.tag` override (OSS `pkg/config/config.go`).
- **Root `vX.Y.Z` tags work.** For a single-language Go repo, GoReleaser OSS fits the template's draft flow on paper: `release.use_existing_draft: true` looks the draft up by name (`findDraftRelease`), the default `name_template` `{{.Tag}}` equals release-please's root release name `v1.2.3`, `mode: keep-existing` (default) keeps release-please's notes, and `draft: true` leaves publishing to the `sbom` job ([release](https://goreleaser.com/customization/release/)). Without `use_existing_draft` it calls "Get a release by tag name", which only returns published releases ([GitHub REST](https://docs.github.com/en/rest/releases/releases)), so it would try to create a second release. Not tried end to end.
- **What it adds:** archives, a `checksums.txt`, per-archive SBOMs via Syft (OSS; needs `syft` on the runner) ([sbom](https://goreleaser.com/customization/sbom/)), and a `preflight` check (v2.18+) that aborts if the tag is already an immutable release ([release](https://goreleaser.com/customization/release/)). The action (`goreleaser/goreleaser-action` v7.3.0) needs `fetch-depth: 0` and `contents: write`, and has a `workdir` input ([GitHub Actions](https://goreleaser.com/ci/actions/)).
- **Attestations:** GoReleaser has no built-in attestation; its docs run `actions/attest@v4` after it with `subject-checksums: ./dist/checksums.txt` and `id-token: write`, `attestations: write` ([attestations](https://goreleaser.com/customization/attestations/)).
- **Fit:** it would mean one release path for root repos and another (or Pro) for `go/` repos, and a third-party action with a large config surface for the template to pin and keep current.

### Plain `go build` plus attestations

- Cross-compile in one job, `CGO_ENABLED=0 GOOS=… GOARCH=… go build -trimpath -o dist/<name>-<os>-<arch> ./cmd/<name>`, with `working-directory: go` in multi-language repos. Go 1.24+ stamps the main module's version from the VCS tag into the binary, with `+dirty` if the tree isn't clean ([Go 1.24 notes](https://go.dev/doc/go1.24)). I didn't verify how it reads a `go/`-prefixed tag; if it doesn't, `-ldflags "-X main.version=…"` from the release-please output is the fallback.
- Write `sha256sum` output to `checksums.txt`, then `actions/attest` with `subject-path: dist/*` (or `subject-checksums`) when `is_public`. As of v4, `actions/attest-build-provenance` "is simply a wrapper on top of `actions/attest`", and "new implementations should use `actions/attest`" ([README](https://github.com/actions/attest-build-provenance)). The template still pins `attest-build-provenance` v4.2.2 for Python; switching is a separate, small change. Attestations in private repos need GitHub Enterprise Cloud (same README).
- Upload with `gh release upload "$tag" …` into the draft, before the `sbom` job publishes it (the `sbom` job would `need` the Go job). `gh` finds drafts by pending tag through GraphQL (`cli/cli` `pkg/cmd/release/shared/fetch.go`), the same path the template already relies on.
- This is the same shape for root and `go/`, uses only first-party actions, and matches the existing `publish-python` job. It gives up GoReleaser's archives and per-archive SBOMs; the repo-level SBOM from `anchore/sbom-action` stays.

## `go.work`

- "It is generally inadvisable to commit go.work files into version control systems": a checked-in one can override a developer's own `go.work` and can make CI "select and thus test the wrong versions" of dependencies. The exception is modules "developed exclusively with each other" ([ref/mod, go.work files](https://go.dev/ref/mod#go-work-files)).
- The template would have exactly one Go module, so there is nothing for a workspace to join. Recommendation: no `go.work` in the layout; CI runs with `working-directory: go` (in multi-language repos the `go` command can't find `go.mod` from the root). Adding `go.work` and `go.work.sum` to `.gitignore` is optional; setting `GOWORK=off` in CI is a cheap guard.

## Recommendations for the grilling ticket

1. Module path `github.com/<owner>/<repo>` at the root, `github.com/<owner>/<repo>/go` in multi-language repos.
2. release-please package for Go: `release-type: go`, and in multi-language repos `component: go` plus a per-package `tag-separator: "/"`, giving `go/vX.Y.Z`. Leave other languages' separator alone.
3. Treat the tag as the release. Decide whether `publishes` means "warm the proxy", "attach binaries", or both.
4. Binaries via a plain `go build` job plus `actions/attest` (when `is_public`) plus `gh release upload` into the draft, ahead of the `sbom` job. Keep GoReleaser out unless the template is willing to support only root-layout Go repos with it, or pay for Pro.
5. Document v2+ as a manual step; consider `bump-minor-pre-major` for the starter.
6. No committed `go.work`.

## Not verified

- No Go toolchain, GoReleaser or Syft on the research machine; nothing was run. The GoReleaser draft-reuse flow and the failure on `go/v1.2.3` are read from source and docs, not observed.
- Whether Go 1.24+'s VCS version stamping picks up a `go/`-prefixed tag for a module in `go/`.
- `gh release upload` with a tag containing `/`: `gh` escapes path segments and finds drafts via GraphQL, and google-cloud-go publishes releases with slash tags, but this template's flow wasn't tried with one.
- That release-please-action v5.0.0's bundled dist matches its lockfile's release-please 17.6.0 (`tag-separator` exists in 17.6.0's source either way).
