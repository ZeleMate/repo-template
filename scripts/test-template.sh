#!/usr/bin/env bash
# Generate the template for several answer sets and check the output.
#   ./scripts/test-template.sh [outdir]
# Needs: uv, pnpm, node, git; cargo optional (Rust checks are skipped without it); actionlint, zizmor and osv-scanner optional.
set -euo pipefail

TEMPLATE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$(mktemp -d)}"
mkdir -p "$OUT"
rm -f "$OUT/.failed"

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
TOOLS="$CENTRAL_DIR/tools"

check() { # name, command...
  local name=$1; shift
  # Failures are recorded in a file, because language checks run in subshells.
  if "$@" >"$OUT/.log" 2>&1; then echo "    ok   $name"; else echo "    FAIL $name"; sed 's/^/         /' "$OUT/.log" | tail -25; touch "$OUT/.failed"; fi
}

gen() { # dir, extra copier -d args...
  local dir=$1; shift
  rm -rf "${OUT:?}/$dir"
  uvx copier copy --trust --defaults --quiet --vcs-ref HEAD \
    -d project_name="Demo App" -d author_name="Test Author" -d author_email="test@example.com" \
    -d github_owner=example "$@" "$TEMPLATE" "$OUT/$dir" >"$OUT/.log" 2>&1 || { cat "$OUT/.log"; return 1; }
  git -C "$OUT/$dir" init -q -b main
}

lint_workflows() {
  local d=$1
  command -v actionlint >/dev/null && check "actionlint" sh -c "cd \"$d\" && actionlint -no-color"
  command -v zizmor >/dev/null && check "zizmor" zizmor --offline --min-severity medium "$d/.github/workflows"
  check "bootstrap syntax" bash -n "$d/scripts/bootstrap-github.sh"
  check "json valid" sh -c "for f in \"$d\"/.claude/settings.json \"$d\"/.github/rulesets/main.json \"$d\"/release-please-config.json \"$d\"/.release-please-manifest.json; do python3 -m json.tool \"\$f\" >/dev/null || exit 1; done"
  check "ci tools lock" uv lock --check --project "$d/.github/tools"
  check "pre-commit hooks" sh -c "cd \"$d\" && git add -A && SKIP=gitleaks,prettier,cargo-fmt uv run --locked --no-build --project \"$TOOLS\" pre-commit run --all-files"
  check "merge gate lists every job" uv run --locked --no-build --project "$TOOLS" python "$CENTRAL_DIR/scripts/check_merge_gate.py" "$d/.github/workflows/ci.yml" ci-ok
  grep -q "sast: true" "$d/.github/workflows/security.yml" && check "semgrep (as in the central security workflow)" sh -c "cd \"$d\" && EIO_BACKEND=posix uv run --locked --no-build --project \"$TOOLS\" semgrep scan --config p/default --error --metrics off --disable-version-check --quiet ."
  # Same scan as the central security workflow: a fresh repo must not start with a red merge gate.
  if command -v osv-scanner >/dev/null; then
    osv_args=(scan source --recursive); [[ -f "$d/evals/run.py.lock" ]] && osv_args+=(--lockfile "uv.lock:$d/evals/run.py.lock")
    check "osv-scanner" osv-scanner "${osv_args[@]}" "$d"
  fi
  check "no unrendered tags" sh -c "! grep -rIl --exclude-dir=node_modules --exclude-dir=.venv -e '\[\[ ' -e '\[% ' \"$d\" | grep -v pnpm-lock"
}

check_evals() { # mock evals, as the evals workflow runs them on PRs; catches pins inside the uv cooldown
  local d=$1
  [[ -f "$d/evals/run.py" ]] && check "evals --mock" sh -c "cd \"$d\" && uv run --locked evals/run.py --mock"
  return 0
}

check_python() {
  local d=$1
  ( cd "$d"
    check "uv sync --locked" uv sync --locked
    check "ruff format" uv run ruff format --check .
    check "ruff check" uv run ruff check .
    if grep -q pyright pyproject.toml; then check "pyright" uv run pyright; else check "mypy" uv run mypy; fi
    check "pytest" uv run pytest --cov -q
    check "uv build" uv build -q )
}

check_ts() {
  local d=$1
  ( cd "$d"
    check "pnpm install" pnpm install --frozen-lockfile --silent
    check "prettier" pnpm run -s format:check
    check "lint" pnpm run -s lint
    check "typecheck" pnpm run -s typecheck
    check "vitest" pnpm run -s test:coverage
    check "build" pnpm run -s build )
}

check_rust() {
  local d=$1
  command -v cargo >/dev/null || { echo "    skip rust (cargo not installed)"; return; }
  ( cd "$d"
    check "cargo fmt" cargo fmt --check
    check "clippy" cargo clippy --all-targets -- -D warnings
    check "cargo test" cargo test )
}

echo "==> python, public, agentic, publishes, sonar + coderabbit"
gen py -d languages='[python]' -d visibility=public -d agentic=true -d publishes=true
lint_workflows "$OUT/py"; check_python "$OUT/py"; check_evals "$OUT/py"

echo "==> typescript, private free, eslint, not agentic"
gen ts -d languages='[typescript]' -d visibility=private -d agentic=false
lint_workflows "$OUT/ts"; check_ts "$OUT/ts"

echo "==> typescript, oxlint, mypy n/a"
gen ts-ox -d languages='[typescript]' -d ts_linter=oxlint -d agentic=false
check_ts "$OUT/ts-ox"

echo "==> rust, public, publishes"
gen rs -d languages='[rust]' -d visibility=public -d publishes=true -d agentic=false
lint_workflows "$OUT/rs"; check_rust "$OUT/rs"

echo "==> python + typescript + rust, private pro, mypy, sonar, publishes"
gen multi -d languages='[python, typescript, rust]' -d visibility=private -d github_plan=pro \
  -d python_type_checker=mypy -d quality_platform=sonarqube-cloud -d publishes=true
lint_workflows "$OUT/multi"; check_evals "$OUT/multi"
check_python "$OUT/multi/python"; check_ts "$OUT/multi/typescript"; check_rust "$OUT/multi/rust"

echo
[[ ! -e "$OUT/.failed" ]] && echo "ALL CHECKS PASSED  ($OUT)" || { echo "SOME CHECKS FAILED  ($OUT)"; exit 1; }
