#!/usr/bin/env bash
# Generate the template for several answer sets and check the output.
#   ./scripts/test-template.sh [outdir]
# Every answer set goes through skills/repo-new/scripts/verify-generated.sh, the same checker the skills
# run on a real repo; this script adds only the assertions about the template itself.
# Needs: uv, pnpm, node, git; cargo and go optional (Rust and Go checks are skipped without them);
# actionlint, zizmor, osv-scanner and golangci-lint optional.
set -euo pipefail

TEMPLATE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$(mktemp -d)}"
VERIFY="$TEMPLATE/skills/repo-new/scripts/verify-generated.sh"
mkdir -p "$OUT"
failed=() # answer sets and template assertions that failed

# pre-commit and Semgrep run from the central workflow repo's tool lock, at the SHA the template pins.
# CENTRAL_DIR=<local clone> skips the download (for testing an unreleased central change).
"$TEMPLATE/scripts/check-central-pins.sh"
CENTRAL_SHA=$("$TEMPLATE/scripts/check-central-pins.sh" --sha)
if [[ -z "${CENTRAL_DIR:-}" ]]; then
  CENTRAL_DIR="$OUT/.central"
  if [[ "$(git -C "$CENTRAL_DIR" rev-parse HEAD 2>/dev/null)" != "$CENTRAL_SHA" ]]; then
    rm -rf "$CENTRAL_DIR"; git init -q "$CENTRAL_DIR"
    git -C "$CENTRAL_DIR" fetch -q --depth 1 https://github.com/ZeleMate/workflows.git "$CENTRAL_SHA"
    git -C "$CENTRAL_DIR" checkout -q FETCH_HEAD
  fi
fi
export CENTRAL_DIR

check() { # name, command... (an assertion about the template, beyond what verify checks)
  local name=$1; shift
  if "$@" >"$OUT/.log" 2>&1; then echo "    ok   $name"; else echo "    FAIL $name"; sed 's/^/         /' "$OUT/.log" | tail -25; failed+=("$name"); fi
}

verify() { # answer set: run the generated-repo checker on it (output kept in $OUT/<set>.verify.log)
  bash "$VERIFY" "$OUT/$1" | tee "$OUT/$1.verify.log" || failed+=("$1 (verify-generated)")
}
ran() { # answer set, check lines...: verify ran each language-profile check and it passed (not skipped)
  local set=$1; shift
  for line; do grep -qF "    ok   $line" "$OUT/$set.verify.log" || { echo "verify didn't pass: $line"; return 1; }; done
}

# The newest known versions (the language profiles in includes/languages.json). The expected CI version lists are
# computed from them and from each answer set's floor, never restated here.
newest() { python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]]["newest"])' "$TEMPLATE/includes/languages.json" "$1"; }
PY_NEWEST=$(newest python); GO_NEWEST=$(newest go)
ci_versions() { # floor, newest: every minor from the floor up to the newest (the floor alone if it is newer)
  python3 -c 'import sys; major, lo = sys.argv[1].split("."); hi = int(sys.argv[2].split(".")[1]); print("[" + ", ".join(f"\"{major}.{m}\"" for m in range(int(lo), max(int(lo), hi) + 1)) + "]")' "$1" "$2"
}
answer() { # answer set, question: the answer Copier recorded in .copier-answers.yml
  sed -nE "s/^$2: '?([^']*)'?$/\1/p" "$OUT/$1/.copier-answers.yml"
}

gen() { # dir, extra copier -d args... (REF=<tag> renders that template version instead of HEAD)
  local dir=$1; shift
  rm -rf "${OUT:?}/$dir"
  uvx copier copy --trust --defaults --quiet --vcs-ref "${REF:-HEAD}" \
    -d project_name="Demo App" -d author_name="Test Author" -d author_email="test@example.com" \
    -d github_owner=example "$@" "$TEMPLATE" "$OUT/$dir" >"$OUT/.log" 2>&1 || { cat "$OUT/.log"; return 1; }
  git -C "$OUT/$dir" init -q -b main
}

echo "==> python, public, agentic, publishes, sonar + coderabbit"
gen py -d languages='[python]' -d visibility=public -d agentic=true -d publishes=true
verify py

check "py: verify ran the profile's Python checks" ran py "typecheck: uv run pyright -p pyproject.toml" "test: uv run pytest --cov" "build: uv build"

echo "==> typescript, private free, eslint, not agentic"
gen ts -d languages='[typescript]' -d visibility=private -d agentic=false
verify ts

check "ts: verify ran the profile's TypeScript checks" ran ts "format: pnpm run format:check" "test: pnpm run test:coverage"

echo "==> typescript, oxlint, mypy n/a"
gen ts-ox -d languages='[typescript]' -d ts_linter=oxlint -d agentic=false
verify ts-ox

echo "==> rust, public, publishes"
gen rs -d languages='[rust]' -d visibility=public -d publishes=true -d agentic=false
verify rs

echo "==> go, public, publishes, not agentic"
gen go -d languages='[go]' -d visibility=public -d publishes=true -d agentic=false
verify go
check "go: CI tests the floor ($(answer go go_version)) up to the newest known Go ($GO_NEWEST)" \
  grep -qF "go-versions: '$(ci_versions "$(answer go go_version)" "$GO_NEWEST")'" "$OUT/go/.github/workflows/ci.yml"
check "go: release binaries build with the newest known Go" grep -qF "go-version: \"$GO_NEWEST\"" "$OUT/go/.github/workflows/release.yml"
check "go: module at the root, root vX.Y.Z tags, 0.x bumps the minor on breaks" sh -c "cd \"$OUT/go\" && head -1 go.mod | grep -qx 'module github.com/example/demo-app' && grep -q '\"include-component-in-tag\": false' release-please-config.json && ! grep -q tag-separator release-please-config.json && grep -q '\"bump-minor-pre-major\": true' release-please-config.json"
check "go: sbom waits for publish-go; public releases attest and warm the proxy" sh -c "f=\"$OUT/go/.github/workflows/release.yml\"; grep -q 'needs: \\[release-please, publish-go\\]' \"\$f\" && grep -q 'uses: actions/attest@' \"\$f\" && grep -q 'Warm the Go module proxy' \"\$f\""
if command -v golangci-lint >/dev/null; then
  # verify-generated.sh and repo-lint both skip this hook, so its entry is only tested here.
  check "go: the golangci-lint-fmt hook runs" sh -c "cd \"$OUT/go\" && git add -A && uv run --locked --no-build --project \"$CENTRAL_DIR/tools\" pre-commit run golangci-lint-fmt --all-files"
else
  echo "    skip the golangci-lint-fmt hook (golangci-lint not installed)"
fi
# go-major-version.sh: manifest version, module suffix, expected exit code.
rm -rf "${OUT:?}/go-major"; cp -R "$OUT/go" "$OUT/go-major"
for row in "2.0.0||1" "2.0.0|/v2|0" "1.4.0|/v2|0" "3.0.0|/v2|1"; do
  IFS='|' read -r ver suffix want <<<"$row"
  check "go-major-version: $ver with module suffix '${suffix:-none}' exits $want" sh -c "cd \"$OUT/go-major\" && printf '{\\n  \".\": \"%s\"\\n}\\n' '$ver' > .release-please-manifest.json && sed -i.bak -E '1s|^module .*|module github.com/example/demo-app$suffix|' go.mod && rm -f go.mod.bak && sh scripts/go-major-version.sh; [ \$? = $want ]"
done

echo "==> go, private, agentic, floor at the newest Go"
gen go-priv -d languages='[go]' -d visibility=private -d agentic=true -d go_version="$GO_NEWEST"
verify go-priv
# shellcheck disable=SC2016 # $1 and $2 belong to the inner sh
check "go-priv: one CI leg; no attestation or proxy warm in a private repo" sh -c 'grep -qF "go-versions: $2" "$1/ci.yml" && ! grep -q "actions/attest@" "$1/release.yml" && ! grep -q "proxy.golang.org" "$1/release.yml"' \
  _ "$OUT/go-priv/.github/workflows" "'$(ci_versions "$GO_NEWEST" "$GO_NEWEST")'"

echo "==> python + typescript + rust + go, private pro, mypy, sonar, publishes"
gen multi -d languages='[python, typescript, rust, go]' -d visibility=private -d github_plan=pro \
  -d python_type_checker=mypy -d quality_platform=sonarqube-cloud -d publishes=true
verify multi
check "multi: the Go module path ends in /go, tagged go/vX.Y.Z" sh -c "cd \"$OUT/multi\" && head -1 go/go.mod | grep -qx 'module github.com/example/demo-app/go' && python3 -c 'import json, sys; p = json.load(open(\"release-please-config.json\"))[\"packages\"]; g = p.pop(\"go\"); sys.exit(not (g[\"component\"] == \"go\" and g[\"tag-separator\"] == \"/\" and g[\"bump-minor-pre-major\"] and not any(\"bump-minor-pre-major\" in o or \"tag-separator\" in o for o in p.values())))'"
check "multi: sbom waits for publish-go" sh -c "grep -q 'needs: \\[release-please, publish-go\\]' \"$OUT/multi/.github/workflows/release.yml\""
# A crate with no licence fails cargo deny, so a proprietary one names its licence and deny.toml
# allows it for that crate only. (cargo deny itself runs only where cargo is installed.)
check "multi: the proprietary Rust crate is licensed for cargo deny" sh -c "cd \"$OUT/multi/rust\" && grep -qx 'license = \"LicenseRef-Proprietary\"' Cargo.toml && grep -qx 'crate = \"demo-app\"' deny.toml && grep -qx 'allow = \\[\"LicenseRef-Proprietary\"\\]' deny.toml && ! grep -q LicenseRef \"$OUT/rs/deny.toml\" \"$OUT/rs/Cargo.toml\""

# Baseline repos (ADR 0002): no managed language, so none of the left-out files may render.
check_baseline() {
  local d=$1
  check "baseline leaves out toolchain, release and ops files" sh -c "cd \"$d\" && for f in README.md CONTRIBUTING.md CHANGELOG.md release-please-config.json .release-please-manifest.json .github/workflows/release.yml docs/slo.md docs/dependencies.md docs/runbooks pyproject.toml package.json Cargo.toml go.mod python typescript rust go; do [ ! -e \"\$f\" ] || { echo \"unexpected \$f\"; exit 1; }; done"
  check "baseline keeps the merge gate and local CI" sh -c "cd \"$d\" && for f in .github/workflows/ci.yml .github/workflows/ci-local.yml .github/workflows/security.yml .github/dependabot.yml AGENTS.md CLAUDE.md SECURITY.md .pre-commit-config.yaml scripts/bootstrap-github.sh docs/SETUP.md; do [ -e \"\$f\" ] || { echo \"missing \$f\"; exit 1; }; done"
}

echo "==> baseline, public, agentic, bun + docker"
gen base-pub -d languages='[]' -d visibility=public -d agentic=true -d extra_ecosystems='[bun, docker]'
verify base-pub; check_baseline "$OUT/base-pub"
check "extra ecosystems reach dependabot" sh -c "grep -q 'package-ecosystem: bun' \"$OUT/base-pub/.github/dependabot.yml\" && grep -q 'package-ecosystem: docker' \"$OUT/base-pub/.github/dependabot.yml\""

echo "==> baseline, private free, not agentic, no extra ecosystems"
gen base-priv -d languages='[]' -d visibility=private -d agentic=false -d ai_reviewers='[]'
verify base-priv; check_baseline "$OUT/base-priv"

echo "==> python with an extra ecosystem that collides (uv) and one that doesn't (docker)"
gen py-extra -d languages='[python]' -d agentic=false -d extra_ecosystems='[uv, docker]'
verify py-extra
check "no duplicate dependabot entry for a managed ecosystem" sh -c "[ \"\$(grep -c 'directory: /\$' \"$OUT/py-extra/.github/dependabot.yml\")\" = 3 ]"
check "ci-local.yml is never overwritten" sh -c "cd \"$OUT/py-extra\" && echo '# mine' >> .github/workflows/ci-local.yml && git add -A && git -c user.name=t -c user.email=t@example.com commit -qm init && uvx copier recopy --trust --defaults --quiet --vcs-ref HEAD --overwrite . >/dev/null 2>&1; grep -q '# mine' .github/workflows/ci-local.yml"

echo "==> repo name with capitals and underscores, capped Python range"
gen cased -d project_name=LegalQA_v2 -d languages='[python]' -d agentic=false -d visibility=public \
  -d python_version=3.11 -d python_max_version=3.12
verify cased
check "repo_name keeps the GitHub name; slug stays lowercase" sh -c "cd \"$OUT/cased\" && grep -qx 'REPO=\"LegalQA_v2\"' scripts/bootstrap-github.sh && grep -q 'example/LegalQA_v2/security' .github/ISSUE_TEMPLATE/config.yml && grep -qx 'name = \"legalqa-v2\"' pyproject.toml"
check "python_max_version caps requires-python and the CI matrix" sh -c "cd \"$OUT/cased\" && grep -qx 'requires-python = \">=3.11,<3.13\"' pyproject.toml && grep -q \"python-versions: '\\[\\\"3.11\\\", \\\"3.12\\\"\\]'\" .github/workflows/ci.yml"
check "gitignore re-includes the CI tools' .python-version last" sh -c "cd \"$OUT/cased\" && [ \"\$(tail -n 1 .gitignore)\" = '!.github/tools/.python-version' ] && printf '.python-version\n' | cat - .gitignore > .gi && mv .gi .gitignore && ! git check-ignore -q .github/tools/.python-version"
check "nothing under .claude/agents (the eval sandbox blocks it)" sh -c "[ ! -e \"$OUT/cased/.claude/agents\" ] && [ ! -e \"$OUT/py/.claude/agents\" ]"
check "release.yml requires RELEASE_PLEASE_TOKEN" sh -c "grep -q 'Require RELEASE_PLEASE_TOKEN' \"$OUT/cased/.github/workflows/release.yml\" && ! grep -q 'RELEASE_PLEASE_TOKEN || github.token' \"$OUT/cased/.github/workflows/release.yml\""
check "release-please bumps uv.lock's own version" sh -c "grep -q \"@.name.value=='legalqa-v2'\" \"$OUT/cased/release-please-config.json\" && grep -q \"@.name.value=='demo-app'\" \"$OUT/multi/release-please-config.json\" && ! grep -q extra-files \"$OUT/ts/release-please-config.json\""
check "releases are drafted, then published after the SBOM is attached" sh -c "grep -q '\"draft\": true' \"$OUT/py/release-please-config.json\" && grep -q '\"force-tag-creation\": true' \"$OUT/py/release-please-config.json\" && grep -q 'gh release edit \"\$tag\" --draft=false' \"$OUT/py/.github/workflows/release.yml\""
check "dependabot automerge uses a merge method the repo and its rulesets allow" sh -c "f=\"$OUT/py/.github/workflows/dependabot-automerge.yml\"; grep -q 'rules/branches/\$BASE' \"\$f\" && grep -q 'gh pr merge --auto \"--\$method\"' \"\$f\" && ! grep -q -- '--squash' \"\$f\""
check "typescript projects ship an expiring osv-scanner accept list" sh -c "grep -q '^ignoreUntil = ' \"$OUT/ts/osv-scanner.toml\" && grep -q '^ignoreUntil = ' \"$OUT/multi/typescript/osv-scanner.toml\" && test ! -e \"$OUT/py/osv-scanner.toml\""
check "uncapped Python tests the floor ($(answer py python_version)) up to the newest known ($PY_NEWEST)" \
  grep -qF "python-versions: '$(ci_versions "$(answer py python_version)" "$PY_NEWEST")'" "$OUT/py/.github/workflows/ci.yml"

# copier update from the newest released tag (what generated repos are on) to HEAD, run the way a
# generated repo runs it: with the Copier locked in its own .github/tools. With no local edits, the
# updated repo must match a fresh copy with the same answers, apart from lockfiles (written at copy
# time) and _commit. PREV_TAG=<tag> starts from another tag.
PREV_TAG="${PREV_TAG:-$(git -C "$TEMPLATE" describe --tags --abbrev=0 2>/dev/null || true)}"
update_from_tag() { # name, copier -d args...
  # A fresh copy of its own, since verify leaves caches and build output in the answer-set dirs.
  local name=$1 fresh="fresh-$1" dir="upd-$1"; shift
  gen "$fresh" "$@"
  REF="$PREV_TAG" gen "$dir" "$@"
  check "$name: copier update from $PREV_TAG matches a fresh copy" sh -c "
    cd \"$OUT/$dir\" && git add -A && git -c user.name=t -c user.email=t@example.com commit -qm 'generated at $PREV_TAG' &&
    uv run --no-build --locked --project .github/tools copier update --trust --defaults --quiet --conflict inline --vcs-ref HEAD &&
    find \"$OUT/$fresh\" . -type d -empty -not -path '*/.git/*' -delete &&
    diff -r -x .git -x .venv -x node_modules -x uv.lock -x pnpm-lock.yaml -x Cargo.lock -x .copier-answers.yml \"$OUT/$fresh\" .
  "
}
if [[ -n "$PREV_TAG" ]]; then
  echo "==> copier update from $PREV_TAG, with the repo's own locked Copier"
  update_from_tag py -d languages='[python]' -d visibility=public -d agentic=true -d publishes=true
  update_from_tag multi -d languages='[python, typescript, rust]' -d visibility=private -d github_plan=pro \
    -d python_type_checker=mypy -d quality_platform=sonarqube-cloud -d publishes=true
  update_from_tag base-pub -d languages='[]' -d visibility=public -d agentic=true -d extra_ecosystems='[bun, docker]'
else
  echo "==> SKIP copier update cases: no tag reachable from HEAD (fetch tags, or set PREV_TAG)"
fi

# Secret requirements (ADR 0003): the rendered list of Actions secrets must match the secrets the
# rendered workflows read, and every file it names as a user must exist.
SECRETS_CHECK='
import json, pathlib, re, sys
d = pathlib.Path(sys.argv[1])
reqs = json.loads((d / ".github/secret-requirements.json").read_text())["secrets"]
listed = {r["name"] for r in reqs if r["store"] == "actions"}
used = set()
for f in (d / ".github/workflows").glob("*.yml"):
    used |= set(re.findall(r"secrets\.([A-Za-z_][A-Za-z0-9_]*)", f.read_text()))
used.discard("GITHUB_TOKEN")
missing_users = [r["used_by"] for r in reqs if r["used_by"] and not (d / r["used_by"]).exists()]
problems = [f"workflows use {sorted(used - listed)} but the secret requirements do not list them"] if used - listed else []
problems += [f"listed but no workflow uses {sorted(listed - used)}"] if listed - used else []
problems += [f"used_by files missing: {missing_users}"] if missing_users else []
sys.exit("\n".join(problems) or None)
'
echo "==> secret requirements match the workflows, for every answer set"
for d in py ts ts-ox rs go go-priv multi base-pub base-priv py-extra cased; do
  check "$d" python3 -c "$SECRETS_CHECK" "$OUT/$d"
done

# verify-generated.sh is the only checker, so prove it fails when it should: a copy of a baseline
# repo with an unrendered tag and an invalid settings.json must fail, naming both checks.
echo "==> verify-generated.sh fails on a broken repo"
rm -rf "${OUT:?}/broken"; cp -R "$OUT/base-priv" "$OUT/broken"
printf '# [[ project_name ]]\n' > "$OUT/broken/NOTES.md"
printf '{\n' > "$OUT/broken/.claude/settings.json"
# ...and, posing as a Python repo, it has no language profiles: verify must not pass it without checks.
sed -i.bak 's/^languages: \[\]$/languages: [python]/' "$OUT/broken/.copier-answers.yml" && rm -f "$OUT/broken/.copier-answers.yml.bak"
rm -f "$OUT/broken/.github/language-profiles.json"
check "exits 1 and names the unrendered tag, the invalid JSON and the missing language profiles" sh -c "out=\$(bash \"$VERIFY\" \"$OUT/broken\" 2>&1); rc=\$?; echo \"\$out\" | tail -40; [ \$rc = 1 ] && echo \"\$out\" | grep -q 'FAIL no unrendered template tags' && echo \"\$out\" | grep -q 'FAIL json valid' && echo \"\$out\" | grep -q 'FAIL language profiles'"

echo
if [[ ${#failed[@]} -eq 0 ]]; then
  echo "ALL CHECKS PASSED  ($OUT)"
else
  printf 'FAILED: %s\n' "${failed[@]}"; echo "($OUT)"; exit 1
fi
