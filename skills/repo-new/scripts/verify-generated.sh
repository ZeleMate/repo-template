#!/usr/bin/env bash
# Run the checks CI runs, locally, on a repo generated from (or adopted into) the repo template.
# The one checker for a generated repo: the skills run it, and scripts/test-template.sh runs it on
# every answer set, so CI tests it too.
#   verify-generated.sh [repo-dir]
#   CENTRAL_DIR=<clone of ZeleMate/workflows>   reuse a clone instead of fetching the pinned SHA
# Reads .copier-answers.yml to know which languages exist and where.
# Exits 0 if every check passes, 1 if any fails, 2 if repo-dir has no .copier-answers.yml.
# Needs: uv, git; pnpm + node for TypeScript; cargo for Rust (skipped without it);
# actionlint, zizmor and osv-scanner optional (skipped without them).
set -uo pipefail

REPO="$(cd "${1:-.}" && pwd)"
ANSWERS="$REPO/.copier-answers.yml"
[[ -f "$ANSWERS" ]] || { echo "No .copier-answers.yml in $REPO; is this a repo-template repo?"; exit 2; }
LOG="$(mktemp)"
fail=0

check() { # name, command...
  local name=$1; shift
  if "$@" >"$LOG" 2>&1; then echo "    ok   $name"; else echo "    FAIL $name"; sed 's/^/         /' "$LOG" | tail -25; fail=1; fi
}

langs=$(uvx --no-build --quiet --from pyyaml python -c 'import sys, yaml; print(" ".join(yaml.safe_load(open(sys.argv[1]))["languages"]))' "$ANSWERS")
# An empty list is a baseline repo: no managed language, so only the repo-wide checks run.
multi=0; [[ "$(wc -w <<<"$langs")" -gt 1 ]] && multi=1
dir_for() { if [[ "$multi" = 1 ]]; then echo "$REPO/$1"; else echo "$REPO"; fi; }

echo "==> repo-wide ($REPO; languages: ${langs:-none, a baseline repo})"
if command -v actionlint >/dev/null; then
  # Without file arguments actionlint needs a git project, which a fresh scaffold isn't yet.
  cfg=""; [[ -f "$REPO/.github/actionlint.yaml" ]] && cfg="-config-file .github/actionlint.yaml"
  check "actionlint" sh -c "cd \"$REPO\" && actionlint -no-color $cfg .github/workflows/*.yml"
fi
command -v zizmor >/dev/null && check "zizmor" zizmor --offline --min-severity medium "$REPO/.github/workflows"
[[ -f "$REPO/scripts/bootstrap-github.sh" ]] && check "bootstrap syntax" bash -n "$REPO/scripts/bootstrap-github.sh"
check "json valid" sh -c "for f in \"$REPO\"/.claude/settings.json \"$REPO\"/.github/rulesets/main.json \"$REPO\"/release-please-config.json \"$REPO\"/.release-please-manifest.json; do [ -f \"\$f\" ] || continue; python3 -m json.tool \"\$f\" >/dev/null || exit 1; done"
[[ -f "$REPO/.github/tools/pyproject.toml" ]] && check "ci tools lock" uv lock --check --project "$REPO/.github/tools"

# CI runs pre-commit, the merge-gate check and Semgrep from the central workflow repo's hash-locked
# tools, at the SHA ci.yml pins. CENTRAL_DIR=<clone> reuses a clone (test-template.sh passes its own).
central_sha=$(grep -ohE 'ZeleMate/workflows/\.github/workflows/[a-z-]+\.yml@[0-9a-f]{40}' "$REPO"/.github/workflows/ci.yml 2>/dev/null | head -1 | sed 's/.*@//')
if [[ -z "$central_sha" ]]; then
  echo "    FAIL central workflow pin"
  echo "         .github/workflows/ci.yml calls no central workflow at a full SHA; run copier update to restore the template's ci.yml"
  fail=1
else
  central="${CENTRAL_DIR:-}"
  if [[ -z "$central" ]]; then
    central="$(mktemp -d)/central"; git init -q "$central"
    git -C "$central" fetch -q --depth 1 https://github.com/ZeleMate/workflows.git "$central_sha" && git -C "$central" checkout -q FETCH_HEAD
  fi
  # pre-commit only sees tracked or staged files, so it stages without committing. Only when $REPO is
  # the top of its own repo: inside another repo (a monorepo, a dotfiles home), `git add -A` would
  # stage the new files into that repo's index.
  top=$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -n "$top" && "$(cd "$top" && pwd -P)" == "$(cd "$REPO" && pwd -P)" ]]; then
    check "pre-commit hooks" sh -c "cd \"$REPO\" && git add -A && SKIP=gitleaks,prettier,cargo-fmt uv run --locked --no-build --project \"$central/tools\" pre-commit run --all-files"
  else
    echo "    skip pre-commit (not its own git repo yet; the bootstrap script runs git init)"
  fi
  check "merge gate lists every job" uv run --locked --no-build --project "$central/tools" python "$central/scripts/check_merge_gate.py" "$REPO/.github/workflows/ci.yml" ci-ok
  grep -q "sast: true" "$REPO/.github/workflows/security.yml" && check "semgrep (as in the central security workflow)" sh -c "cd \"$REPO\" && EIO_BACKEND=posix uv run --locked --no-build --project \"$central/tools\" semgrep scan --config p/default --error --metrics off --disable-version-check --quiet ."
fi
# Same scan as the central security workflow: a repo must not start with a red merge gate.
if command -v osv-scanner >/dev/null; then
  osv_args=(scan source --recursive); [[ -f "$REPO/evals/run.py.lock" ]] && osv_args+=(--lockfile "uv.lock:$REPO/evals/run.py.lock")
  check "osv-scanner" osv-scanner "${osv_args[@]}" "$REPO"
fi
# A Copier variable starts with a name (`[[ project_name ]]`); bash tests (`[[ -n "$x" ]]`) do not.
check "no unrendered template tags" sh -c "! grep -rIl --exclude-dir=node_modules --exclude-dir=.venv --exclude-dir=target --exclude-dir=.git -E -e '\[\[ [A-Za-z_]' -e '\[% ' \"$REPO\" | grep -v pnpm-lock"

if [[ -f "$REPO/evals/run.py" ]]; then
  # Same command the evals workflow runs on PRs; also catches pins newer than the uv cooldown.
  echo "==> evals (mock)"
  check "evals --mock" sh -c "cd \"$REPO\" && uv run --locked evals/run.py --mock"
fi

for lang in $langs; do
  case $lang in
    python)
      d=$(dir_for python); echo "==> python ($d)"
      ( cd "$d"
        check "uv sync --locked" uv sync --locked
        check "ruff format" uv run ruff format --check .
        check "ruff check" uv run ruff check .
        # -p: a pyrightconfig.json in any parent folder would otherwise win over pyproject.toml.
        if grep -q pyright pyproject.toml; then check "pyright" uv run pyright -p pyproject.toml; else check "mypy" uv run mypy; fi
        check "pytest" uv run pytest --cov -q
        check "uv build" uv build -q
        [[ "$fail" = 0 ]] ) || fail=1 ;;
    typescript)
      d=$(dir_for typescript); echo "==> typescript ($d)"
      ( cd "$d"
        check "pnpm install" pnpm install --frozen-lockfile --silent
        check "prettier" pnpm run -s format:check
        check "lint" pnpm run -s lint
        check "typecheck" pnpm run -s typecheck
        check "vitest" pnpm run -s test:coverage
        check "build" pnpm run -s build
        [[ "$fail" = 0 ]] ) || fail=1 ;;
    rust)
      d=$(dir_for rust); echo "==> rust ($d)"
      if ! command -v cargo >/dev/null; then echo "    skip (cargo not installed)"; continue; fi
      ( cd "$d"
        check "cargo fmt" cargo fmt --check
        check "clippy" cargo clippy --all-targets -- -D warnings
        check "cargo test" cargo test
        [[ "$fail" = 0 ]] ) || fail=1 ;;
  esac
done

email=$(grep -E '^author_email:' "$ANSWERS" | sed 's/^author_email: *//')
case "$email" in
  *@example.com|*@example.org|*.test|*noreply*|"")
    echo; echo "    note: author_email '$email' is the vulnerability-report contact in SECURITY.md; use a monitored address" ;;
esac

rm -f "$LOG"
echo
if [[ "$fail" = 0 ]]; then echo "ALL CHECKS PASSED"; else echo "SOME CHECKS FAILED"; exit 1; fi
