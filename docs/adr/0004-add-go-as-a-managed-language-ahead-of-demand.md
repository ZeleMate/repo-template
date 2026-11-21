---
status: accepted
---

# Add Go as a managed language ahead of demand

Go becomes the fourth managed language, next to Python, TypeScript and Rust, even though no repo on the account uses it yet. This departs from the rule in [ADR 0001](0001-centralise-ci-and-security-workflows.md) and section 5 of the [central workflows spec](../specs/central-workflows.md): a stack is promoted to a template language when it recurs across baseline repos. Go is promoted before that, because the template is meant for agent apps. Go has every major agent toolkit: the official MCP Go SDK, Google's ADK for Go, Genkit, Eino, and the Anthropic and OpenAI SDKs. The template's security tools already cover Go too: OSV-Scanner, Semgrep `p/default` and CodeQL. The cost is paid up front so that the first Go project starts from the template, not from a baseline repo that is promoted later.

The design to build is in [docs/specs/go.md](../specs/go.md), which comes from the map [Add Go as a managed language](https://github.com/ZeleMate/repo-template/issues/61).

## Considered Options

- **Wait for a Go repo, as the promotion rule says.** The rule keeps the template small. The first Go agent project would then start as a baseline repo with its own CI in `ci-local.yml`, and need a promotion with `copier update` later, when it already has code and habits to migrate. Rejected, because the template exists to start agent projects well, and Go is a likely language for them (MCP servers and CLIs that ship as one binary).
- **Java/Kotlin or C# as the fourth language.** Considered when the map was charted, and rejected in favour of Go on the two grounds above: its agent toolkits, and security tools the template already runs. Adding either is a separate effort, if ever.
- **No new language.** Rejected: Python, TypeScript and Rust leave out the single-binary agent tools (MCP servers, CLIs) that Go is used for.

## Consequences

- **About 40 files change**, as many as Rust touches: `copier.yml`, `template/`, the `repo-standards` skills, `scripts/test-template.sh` and `verify-generated.sh`, and the template's own CI. Every later template change that touches all languages now touches four.
- **A new central workflow, `go.yml`,** ships in the minor central release `v1.1.0` of `ZeleMate/workflows`, with a `tools/go` module that pins govulncheck and gocover-cobertura. The template moves its central pin to `v1.1.0` in the release that adds Go.
- **Every pin refresh has one more ordering rule.** golangci-lint can't lint code for a Go newer than it was built with. At each Go release, the central golangci-lint pin moves first and gets a central release, and only then does the template raise the newest Go version it knows.
- **Go has no registry.** A release is the tag, and `publishes: true` adds raw cross-compiled binaries on the GitHub release, built by a plain `go build` job rather than GoReleaser. GoReleaser's open-source edition can't release from the `go/vX.Y.Z` tags a multi-language repo needs. This is reversible, since the release job can be swapped, so it is recorded in the spec rather than in its own ADR. The same goes for the binary-only starter and the `go-major-version` guard.
- **Dropping Go later would break the `copier update` of every Go repo generated before then.** That is the main reason this is an ADR and not just a spec.
