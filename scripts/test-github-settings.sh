#!/usr/bin/env bash
# Offline tests for the GitHub adapters of a generated repo (ADR 0005): scripts/bootstrap-github.sh
# applies its settings and secret requirements (default), prints the writes (--dry-run) or reports drift
# (--check), and the plugin's audit-github.sh runs that check. GitHub is played by the recorded API
# responses in tests/github-settings/recorded, served by the fake gh in tests/github-settings/bin.
#   ./scripts/test-github-settings.sh [outdir]
# Needs: uv (for Copier), git, jq; shellcheck optional.
set -euo pipefail

TEMPLATE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$(mktemp -d)}"
FIX="$TEMPLATE/tests/github-settings"
RECORDED="$FIX/recorded/compliant"
AUDIT="$TEMPLATE/skills/repo-github-setup/scripts/audit-github.sh"
LOG="$OUT/gh-writes.log"
export PATH="$FIX/bin:$PATH"
mkdir -p "$OUT"
failed=()

check() { # name, command... (runs in this shell, so test functions see the helpers)
  local name=$1; shift
  if "$@" >"$OUT/.log" 2>&1; then echo "    ok   $name"; else echo "    FAIL $name"; sed 's/^/         /' "$OUT/.log" | tail -40; failed+=("$name"); fi
}

gen() { # dir, extra copier -d args...: render, commit, and name example/repo-template as the source
  local dir=$1; shift
  rm -rf "${OUT:?}/$dir"
  uvx copier copy --trust --defaults --quiet --skip-tasks --vcs-ref HEAD \
    -d project_name="Demo App" -d author_name="Test Author" -d author_email="test@example.com" \
    -d github_owner=example "$@" "$TEMPLATE" "$OUT/$dir" >"$OUT/.log" 2>&1 || { cat "$OUT/.log"; return 1; }
  sed -i.bak 's#^_src_path: .*#_src_path: gh:example/repo-template#' "$OUT/$dir/.copier-answers.yml" && rm "$OUT/$dir/.copier-answers.yml.bak"
  git -C "$OUT/$dir" init -q -b main
  git -C "$OUT/$dir" add -A
  git -C "$OUT/$dir" -c user.name=t -c user.email=t@example.com commit -qm init
}

# state <name> [<endpoint> <jq filter>]...: a copy of the recorded compliant GitHub, edited.
# A filter of "404" deletes the answer, "403" makes it fail as unreadable.
state() {
  local d="$OUT/github/$1"; shift
  rm -rf "$d"; mkdir -p "$OUT/github"; cp -R "$RECORDED" "$d"
  while [[ $# -gt 0 ]]; do
    local f="$d/$1"
    case "$2" in
      404) rm -f "$f.json" ;;
      403) rm -f "$f.json"; echo 403 >"$f.status" ;;
      *) mkdir -p "$(dirname "$f")"; [[ -s "$f.json" ]] || echo null >"$f.json"
         jq "$2" "$f.json" >"$f.tmp" && mv "$f.tmp" "$f.json" ;;
    esac
    shift 2
  done
  echo "$d"
}

# gh_run <github state> <repo dir> <bootstrap args...>: sets OUTPUT (colours stripped) and RC; writes land in $LOG.
gh_run() {
  local gh=$1 repo=$2; shift 2
  : >"$LOG"; RC=0
  OUTPUT=$(GH_FIXTURES="$gh" GH_LOG="$LOG" bash "$repo/scripts/bootstrap-github.sh" "$@" 2>&1 | sed $'s/\x1b\\[[0-9;]*m//g') || RC=$?
}
has()   { grep -qF -- "$1" <<<"$OUTPUT" || { printf 'no line with: %s\n--- output:\n%s\n' "$1" "$OUTPUT"; return 1; }; }
hasnt() { ! grep -qF -- "$1" <<<"$OUTPUT" || { printf 'unexpected line with: %s\n--- output:\n%s\n' "$1" "$OUTPUT"; return 1; }; }
rc_is() { [[ "$RC" = "$1" ]] || { printf 'exit %s, want %s\n--- output:\n%s\n' "$RC" "$1" "$OUTPUT"; return 1; }; }
drift_count() { local n; n=$(grep -c '  DRIFT ' <<<"$OUTPUT" || true); [[ "$n" = "$1" ]] || { printf '%s DRIFT lines, want %s\n--- output:\n%s\n' "$n" "$1" "$OUTPUT"; return 1; }; }
# The writes bootstrap should make for every entry with a method, in order, as the fake gh logs them.
expected_writes() { # repo dir, then jq select() filter on entries to leave out (default: none)
  jq -c --arg r example/demo-app --slurpfile rules "$1/.github/rulesets/main.json" ".settings[] | select(.method) | select(${2:-false} | not)
    | {method, endpoint: (.endpoint | sub(\"[{]repo[}]\"; \$r)), body: (if .body_file then \$rules[0] else (.body // null) end)}" "$1/.github/settings-requirements.json"
}
writes_are() { # expected writes, one JSON line each
  diff <(printf '%s\n' "$1" | sed '/^$/d') <(jq -c . "$LOG") || { echo "--- writes differ (< want, > made)"; return 1; }
}

echo "==> render: public publishing Python; private Free; private Pro; private Free baseline"
gen pub -d languages='[python]' -d visibility=public -d publishes=true -d agentic=false
gen priv -d languages='[python]' -d visibility=private -d publishes=true -d agentic=false
gen pro -d languages='[python]' -d visibility=private -d github_plan=pro -d publishes=true -d agentic=false
gen base -d languages='[]' -d visibility=private -d agentic=false
for d in pub priv pro base; do
  check "$d: bootstrap parses" bash -n "$OUT/$d/scripts/bootstrap-github.sh"
  check "$d: settings requirements are valid JSON" jq -e '.settings | length > 0' "$OUT/$d/.github/settings-requirements.json"
  if command -v shellcheck >/dev/null; then check "$d: shellcheck bootstrap" shellcheck -S warning "$OUT/$d/scripts/bootstrap-github.sh"; fi
done
command -v shellcheck >/dev/null || echo "    skip shellcheck of the rendered bootstrap (shellcheck not installed)"

echo "==> --check"
t_compliant() {
  gh_run "$RECORDED" "$OUT/pub" --check
  rc_is 0 && has "NO DRIFT" && drift_count 0 && has "✓ rules" && has "✓ squash_merge_commit_message = PR_BODY" \
    && has "✓ security_and_analysis" && has "TEMPLATE_READ_TOKEN is not needed: the template repo is public" \
    && has "? the API can't show this: confirm by hand" && hasnt "selected-actions"
}
check "a compliant public repo has no drift, whatever extra fields and rule order GitHub answers with" t_compliant

t_drift() {
  local gh; gh=$(state drift \
    repos/example/demo-app '.allow_merge_commit = true | .security_and_analysis.secret_scanning_push_protection.status = "disabled"' \
    repos/example/demo-app/vulnerability-alerts 404 \
    repos/example/demo-app/rulesets/4101 '.rules |= map(select(.type != "required_status_checks"))' \
    repos/example/demo-app/environments/release/deployment-branch-policies '.total_count = 0 | .branch_policies = []' \
    repos/example/demo-app/actions/permissions '.allowed_actions = "selected"' \
    repos/example/demo-app/actions/permissions/selected-actions '{github_owned_allowed: true, verified_allowed: false, patterns_allowed: ["astral-sh/setup-uv@*", "dependabot/fetch-metadata@*"]}' \
    repos/example/demo-app/actions/secrets '.secrets |= map(select(.name != "RELEASE_PLEASE_TOKEN"))')
  gh_run "$gh" "$OUT/pub" --check
  rc_is 1 && drift_count 7 && has "DRIFT FOUND" \
    && has "DRIFT allow_merge_commit = true (want false)" \
    && has 'DRIFT security_and_analysis.secret_scanning_push_protection.status = disabled (want enabled)' \
    && has "DRIFT missing: repos/example/demo-app/vulnerability-alerts (HTTP 404)" \
    && has 'DRIFT rules lacks {"type":"required_status_checks"' \
    && has 'DRIFT missing: no item matching {"name":"main"} in repos/example/demo-app/environments/release/deployment-branch-policies' \
    && has 'DRIFT patterns_allowed lacks ZeleMate/*' \
    && has "DRIFT RELEASE_PLEASE_TOKEN is not set (not needed while release.yml is disabled): release.yml fails on every push to main"
}
check "each kind of drift is reported once, and nothing else is" t_drift

t_unreadable() {
  local gh; gh=$(state unreadable \
    repos/example/demo-app 'del(.security_and_analysis)' \
    repos/example/demo-app/actions/permissions/workflow 403 \
    repos/example/demo-app/actions/secrets 403)
  gh_run "$gh" "$OUT/pub" --check
  rc_is 0 && drift_count 0 && has "NO DRIFT" \
    && has "? security_and_analysis: not in GitHub's answer" \
    && has "? could not read repos/example/demo-app/actions/permissions/workflow (permissions or plan)" \
    && has "? cannot list secrets (needs admin)"
}
check "what GitHub won't show is ?, not drift" t_unreadable

t_waivers() {
  local gh; gh=$(state waivers \
    repos/example/demo-app/actions/workflows/release.yml '.state = "disabled_manually"' \
    repos/example/repo-template '.private = true | .visibility = "private"' \
    repos/example/demo-app/actions/secrets '.secrets = []')
  rm -rf "$OUT/pub-waivers"; cp -R "$OUT/pub" "$OUT/pub-waivers"; rm "$OUT/pub-waivers/.github/workflows/claude-review.yml"
  gh_run "$gh" "$OUT/pub-waivers" --check
  rc_is 1 && drift_count 1 \
    && has "CLAUDE_CODE_OAUTH_TOKEN is not needed: .github/workflows/claude-review.yml isn't in this repo" \
    && has "RELEASE_PLEASE_TOKEN is not needed: release.yml is disabled (re-enable with: gh workflow enable release.yml)" \
    && has "DRIFT TEMPLATE_READ_TOKEN is not set (the template repo is private): the weekly template update check fails"
}
check "secret waivers: deleted workflow, disabled release.yml, private template repo" t_waivers

t_template_unknown() {
  rm -rf "$OUT/pub-local"; cp -R "$OUT/pub" "$OUT/pub-local"
  sed -i.bak 's#^_src_path: .*#_src_path: /somewhere/repo-template#' "$OUT/pub-local/.copier-answers.yml"
  gh_run "$RECORDED" "$OUT/pub-local" --check
  rc_is 0 && has "? TEMPLATE_READ_TOKEN: could not tell whether the template repo '/somewhere/repo-template' is private"
}
check "a template source that isn't a GitHub repo is ?, not drift" t_template_unknown

t_private_free() {
  gh_run "$RECORDED" "$OUT/priv" --check
  rc_is 1 && drift_count 1 && has "DRIFT visibility = public (want private)" \
    && has "? unavailable: rulesets on private repos need GitHub Pro" && has "? unavailable: environments on private repos need GitHub Pro" \
    && has "? unavailable: private repos need a paid GitHub add-on" && hasnt "CodeQL default setup" && hasnt "Ruleset main:" \
    && ! grep -q 'dependabot/fetch-metadata' "$OUT/priv/.github/settings-requirements.json" || return 1
  local gh; gh=$(state private repos/example/demo-app '.visibility = "private" | .private = true')
  gh_run "$gh" "$OUT/priv" --check
  rc_is 0 && has "NO DRIFT"
}
check "private Free: only the settings the plan allows; visibility is checked" t_private_free

t_pro() {
  local gh; gh=$(state private repos/example/demo-app '.visibility = "private" | .private = true')
  gh_run "$gh" "$OUT/pro" --check
  rc_is 0 && has "NO DRIFT" && has "✓ rules" && has "Environment release deploys from main only" && hasnt "unavailable: rulesets"
}
check "private Pro: ruleset and release environment are checked" t_pro

t_baseline() {
  local gh; gh=$(state private repos/example/demo-app '.visibility = "private" | .private = true')
  gh_run "$gh" "$OUT/base" --check
  rc_is 0 && has "NO DRIFT" && hasnt "RELEASE_PLEASE_TOKEN" && hasnt "Immutable releases" && hasnt "Trusted publisher"
}
check "baseline repo: no release settings or release token" t_baseline

t_other_repo() {
  gh_run "$RECORDED" "$OUT/pub" --check example/renamed
  rc_is 1 && has "DRIFT repository example/renamed does not exist or is not visible to you"
}
check "--check owner/repo checks another name" t_other_repo

echo "==> apply"
t_apply_fresh() {
  local gh; gh=$(state fresh repos/example/demo-app/rulesets '[]' \
    repos/example/demo-app/environments/release 404 repos/example/demo-app/environments/release/deployment-branch-policies 404)
  rm -f "$gh/repos/example/demo-app.json" # the repo doesn't exist yet
  gh_run "$gh" "$OUT/pub"
  rc_is 0 && writes_are "$(printf '{"method":"CREATE","endpoint":"example/demo-app","body":null}\n'; expected_writes "$OUT/pub")" \
    && ! grep -q allowed_actions "$LOG" && has "Remaining manual steps"
}
check "fresh repo: creates it, then writes every setting once, ruleset by POST, never allowed_actions" t_apply_fresh

t_apply_rerun() {
  gh_run "$RECORDED" "$OUT/pub"
  rc_is 0 && writes_are "$(expected_writes "$OUT/pub" '.key')" && has "✓ already set"
}
check "re-run on a compliant repo: the ruleset and branch policy are left alone" t_apply_rerun

t_apply_ruleset_drift() {
  local gh; gh=$(state ruleset-drift repos/example/demo-app/rulesets/4101 '.enforcement = "evaluate"')
  gh_run "$gh" "$OUT/pub"
  rc_is 0 && grep -q '"method":"PUT","endpoint":"repos/example/demo-app/rulesets/4101"' "$LOG" \
    && [[ "$(jq -c 'select(.endpoint == "repos/example/demo-app/rulesets/4101") | .body' "$LOG")" = "$(jq -c . "$OUT/pub/.github/rulesets/main.json")" ]]
}
check "a drifted ruleset is replaced with PUT, by id" t_apply_ruleset_drift

t_apply_private() {
  local gh; gh=$(state private repos/example/demo-app '.visibility = "private" | .private = true')
  gh_run "$gh" "$OUT/priv"
  rc_is 0 && writes_are "$(expected_writes "$OUT/priv")" && has "! Skipped: rulesets on private repos need GitHub Pro"
}
check "private Free: skips what the plan rules out, with a warning" t_apply_private

t_apply_secrets() {
  local gh; gh=$(state no-secrets repos/example/demo-app/actions/secrets '.secrets = []')
  gh_run "$gh" "$OUT/pub"
  rc_is 0 && has "! CLAUDE_CODE_OAUTH_TOKEN is not set: the Claude review job passes with a warning" && hasnt "DRIFT"
}
check "a missing secret is a warning in bootstrap, not a failure" t_apply_secrets

echo "==> --dry-run"
t_dry_run() {
  local n
  gh_run "$RECORDED" "$OUT/pub" --dry-run
  n=$(grep -c '\[dry-run\] gh api' <<<"$OUTPUT" || true)
  rc_is 0 && [[ ! -s "$LOG" ]] && [[ "$n" = "$(expected_writes "$OUT/pub" | wc -l | tr -d ' ')" ]] \
    && has "[dry-run] gh api -X POST repos/example/demo-app/rulesets --input .github/rulesets/main.json" \
    && has "[dry-run] check that RELEASE_PLEASE_TOKEN is set" \
    || { echo "dry-run writes: $n; log:"; cat "$LOG"; return 1; }
}
check "dry run writes nothing and prints every write" t_dry_run

t_usage() { gh_run "$RECORDED" "$OUT/pub" --chek; rc_is 2 && has "usage:"; }
check "an unknown option is a usage error" t_usage

echo "==> the plugin's audit-github.sh"
t_audit() {
  : >"$LOG"; RC=0
  OUTPUT=$(GH_FIXTURES="$RECORDED" bash "$AUDIT" "$OUT/pub" 2>&1) || RC=$?
  rc_is 0 && has "NO DRIFT" || return 1
  OUTPUT=$(GH_FIXTURES="$RECORDED" bash "$AUDIT" "$OUT/pub" example/renamed 2>&1) && RC=0 || RC=$?
  rc_is 1 && has "example/renamed does not exist"
}
check "runs the repo's own check, passing owner/repo" t_audit

t_audit_old() {
  rm -rf "$OUT/old"; cp -R "$OUT/pub" "$OUT/old"; rm "$OUT/old/.github/settings-requirements.json"
  RC=0; OUTPUT=$(GH_FIXTURES="$RECORDED" bash "$AUDIT" "$OUT/old" 2>&1) || RC=$?
  rc_is 2 && has "Run copier update"
}
check "a repo rendered before settings requirements can't be audited (exit 2), with no fallback" t_audit_old

echo
if [[ ${#failed[@]} -eq 0 ]]; then
  echo "ALL GITHUB SETTINGS CHECKS PASSED  ($OUT)"
else
  printf 'FAILED: %s\n' "${failed[@]}"; echo "($OUT)"; exit 1
fi
