#!/usr/bin/env bash
# Run the checks CI runs, locally, on a repo generated from (or adopted into) the repo template.
#   verify-generated.sh [repo-dir]
# Reads .copier-answers.yml to know which languages exist and where. Exits non-zero if any check fails.
# Needs: uv; pnpm + node for TypeScript; cargo for Rust (skipped without it); actionlint/zizmor optional.
set -uo pipefail

REPO="$(cd "${1:-.}" && pwd)"
ANSWERS="$REPO/.copier-answers.yml"
[ -f "$ANSWERS" ] || { echo "No .copier-answers.yml in $REPO; is this a repo-template repo?"; exit 2; }
LOG="$(mktemp)"
fail=0

check() { # name, command...
  local name=$1; shift
  if "$@" >"$LOG" 2>&1; then echo "    ok   $name"; else echo "    FAIL $name"; sed 's/^/         /' "$LOG" | tail -25; fail=1; fi
}

langs=$(uvx --quiet --from pyyaml python -c 'import sys, yaml; print(" ".join(yaml.safe_load(open(sys.argv[1]))["languages"]))' "$ANSWERS")
[ -z "$langs" ] && { echo "Could not read languages from $ANSWERS"; exit 2; }
multi=0; [ "$(wc -w <<<"$langs")" -gt 1 ] && multi=1
dir_for() { if [ "$multi" = 1 ]; then echo "$REPO/$1"; else echo "$REPO"; fi; }

echo "==> repo-wide ($REPO; languages: $langs)"
command -v actionlint >/dev/null && check "actionlint" sh -c "cd \"$REPO\" && actionlint -no-color"
command -v zizmor >/dev/null && check "zizmor" zizmor --offline --min-severity medium "$REPO/.github/workflows"
check "json valid" sh -c "for f in \"$REPO\"/.claude/settings.json \"$REPO\"/.github/rulesets/main.json \"$REPO\"/release-please-config.json \"$REPO\"/.release-please-manifest.json; do [ -f \"\$f\" ] || continue; python3 -m json.tool \"\$f\" >/dev/null || exit 1; done"
if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  # pre-commit only sees tracked or staged files; stage without committing.
  check "pre-commit hooks" sh -c "cd \"$REPO\" && git add -A && SKIP=gitleaks,prettier,cargo-fmt uvx pre-commit@4.7.0 run --all-files"
else
  echo "    skip pre-commit (not a git repo yet; the bootstrap script runs git init)"
fi
check "no unrendered template tags" sh -c "! grep -rIl --exclude-dir=node_modules --exclude-dir=.venv --exclude-dir=target --exclude-dir=.git -e '\[\[ ' -e '\[% ' \"$REPO\" | grep -v pnpm-lock"

for lang in $langs; do
  case $lang in
    python)
      d=$(dir_for python); echo "==> python ($d)"
      ( cd "$d"
        check "uv sync --locked" uv sync --locked
        check "ruff format" uv run ruff format --check .
        check "ruff check" uv run ruff check .
        if grep -q pyright pyproject.toml; then check "pyright" uv run pyright; else check "mypy" uv run mypy; fi
        check "pytest" uv run pytest --cov -q
        [ "$fail" = 0 ] ) || fail=1 ;;
    typescript)
      d=$(dir_for typescript); echo "==> typescript ($d)"
      ( cd "$d"
        check "pnpm install" pnpm install --frozen-lockfile --silent
        check "prettier" pnpm run -s format:check
        check "lint" pnpm run -s lint
        check "typecheck" pnpm run -s typecheck
        check "vitest" pnpm run -s test:coverage
        check "build" pnpm run -s build
        [ "$fail" = 0 ] ) || fail=1 ;;
    rust)
      d=$(dir_for rust); echo "==> rust ($d)"
      if ! command -v cargo >/dev/null; then echo "    skip (cargo not installed)"; continue; fi
      ( cd "$d"
        check "cargo fmt" cargo fmt --check
        check "clippy" cargo clippy --all-targets -- -D warnings
        check "cargo test" cargo test
        [ "$fail" = 0 ] ) || fail=1 ;;
  esac
done

rm -f "$LOG"
echo
if [ "$fail" = 0 ]; then echo "ALL CHECKS PASSED"; else echo "SOME CHECKS FAILED"; exit 1; fi
