# Recorded GitHub API responses

`scripts/test-github-settings.sh` checks the GitHub adapters in a generated repo's `scripts/bootstrap-github.sh` (apply, `--dry-run`, `--check`) and the plugin's `audit-github.sh` offline (ADR 0005).

- `bin/gh` stands in for `gh`: it serves `recorded/<state>/<endpoint>.json` for a GET, fails like `gh` for `<endpoint>.status` (an HTTP code) or a missing file (404), and logs every write.
- `recorded/compliant/` is the account `example`'s repo `demo-app` with every requirement met: a public repo that publishes. The shapes, extra fields and field order follow live `gh api` answers. An empty file is an HTTP 204. The tests derive the drifted states from it.
