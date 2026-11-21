#!/usr/bin/env bash
# Generate the template for several answer sets and check the output.
#   ./scripts/test-template.sh [outdir]
# Every answer set goes through skills/repo-new/scripts/verify-generated.sh, the same checker the skills
# run on a real repo; this script adds only the assertions about the template itself.
# Needs: uv, pnpm, node, git; cargo optional (Rust checks are skipped without it); actionlint, zizmor and osv-scanner optional.
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

verify() { # answer set: run the generated-repo checker on it
  bash "$VERIFY" "$OUT/$1" || failed+=("$1 (verify-generated)")
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

echo "==> typescript, private free, eslint, not agentic"
gen ts -d languages='[typescript]' -d visibility=private -d agentic=false
verify ts

echo "==> typescript, oxlint, mypy n/a"
gen ts-ox -d languages='[typescript]' -d ts_linter=oxlint -d agentic=false
verify ts-ox

echo "==> rust, public, publishes"
gen rs -d languages='[rust]' -d visibility=public -d publishes=true -d agentic=false
verify rs

echo "==> python + typescript + rust, private pro, mypy, sonar, publishes"
gen multi -d languages='[python, typescript, rust]' -d visibility=private -d github_plan=pro \
  -d python_type_checker=mypy -d quality_platform=sonarqube-cloud -d publishes=true
verify multi

# Baseline repos (ADR 0002): no managed language, so none of the left-out files may render.
check_baseline() {
  local d=$1
  check "baseline leaves out toolchain, release and ops files" sh -c "cd \"$d\" && for f in README.md CONTRIBUTING.md CHANGELOG.md release-please-config.json .release-please-manifest.json .github/workflows/release.yml docs/slo.md docs/dependencies.md docs/runbooks pyproject.toml package.json Cargo.toml python typescript rust; do [ ! -e \"\$f\" ] || { echo \"unexpected \$f\"; exit 1; }; done"
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
check "uncapped Python still tests up to 3.14" sh -c "grep -q '\"3.14\"' \"$OUT/py/.github/workflows/ci.yml\""

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
for d in py ts ts-ox rs multi base-pub base-priv py-extra cased; do
  check "$d" python3 -c "$SECRETS_CHECK" "$OUT/$d"
done

# verify-generated.sh is the only checker, so prove it fails when it should: a copy of a baseline
# repo with an unrendered tag and an invalid settings.json must fail, naming both checks.
echo "==> verify-generated.sh fails on a broken repo"
rm -rf "${OUT:?}/broken"; cp -R "$OUT/base-priv" "$OUT/broken"
printf '# [[ project_name ]]\n' > "$OUT/broken/NOTES.md"
printf '{\n' > "$OUT/broken/.claude/settings.json"
check "exits 1 and names the unrendered tag and the invalid JSON" sh -c "out=\$(bash \"$VERIFY\" \"$OUT/broken\" 2>&1); rc=\$?; echo \"\$out\" | tail -40; [ \$rc = 1 ] && echo \"\$out\" | grep -q 'FAIL no unrendered template tags' && echo \"\$out\" | grep -q 'FAIL json valid'"

echo
if [[ ${#failed[@]} -eq 0 ]]; then
  echo "ALL CHECKS PASSED  ($OUT)"
else
  printf 'FAILED: %s\n' "${failed[@]}"; echo "($OUT)"; exit 1
fi
