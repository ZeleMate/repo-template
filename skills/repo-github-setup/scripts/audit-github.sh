#!/usr/bin/env bash
# Read-only audit: compare a GitHub repo's live settings with what the repo template expects.
#   audit-github.sh [repo-dir] [owner/repo]
# Expectations come from repo-dir/.copier-answers.yml; owner/repo defaults to github_owner/project_slug from it.
# Changes nothing. Exits 1 if any setting has drifted, 0 otherwise.
# Needs: gh (authenticated), jq, uv (to read the YAML answers file).
set -uo pipefail

REPO_DIR="$(cd "${1:-.}" && pwd)"
ANSWERS="$REPO_DIR/.copier-answers.yml"
[ -f "$ANSWERS" ] || { echo "No .copier-answers.yml in $REPO_DIR"; exit 2; }
gh auth status >/dev/null 2>&1 || { echo "gh is not authenticated: run 'gh auth login'"; exit 2; }

# key=value lines for the answers this audit needs.
eval "$(uvx --quiet --from pyyaml python - "$ANSWERS" <<'PY'
import shlex, sys, yaml
a = yaml.safe_load(open(sys.argv[1]))
vis = a.get("visibility", "private")
gov = vis == "public" or a.get("github_plan") == "pro"
out = {
    "OWNER": a.get("github_owner", ""), "SLUG": a.get("project_slug", ""), "VIS": vis,
    "GOV": "yes" if gov else "no", "PUBLISHES": "yes" if a.get("publishes") else "no",
    "AGENTIC": "yes" if a.get("agentic") else "no",
    "CLAUDE": "yes" if "claude" in (a.get("ai_reviewers") or []) else "no",
    "CODERABBIT": "yes" if "coderabbit" in (a.get("ai_reviewers") or []) else "no",
    "SONAR": "yes" if a.get("quality_platform") == "sonarqube-cloud" else "no",
}
for k, v in out.items():
    print(f"{k}={shlex.quote(str(v))}")
PY
)"
FULL="${2:-$OWNER/$SLUG}"
drift=0

ok()    { printf '  \033[32mok\033[0m      %s\n' "$*"; }
bad()   { printf '  \033[31mDRIFT\033[0m   %s\n' "$*"; drift=1; }
skip()  { printf '  \033[33m?\033[0m       %s\n' "$*"; }
api()   { gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "$@" 2>/dev/null; }
# expect <label> <actual> <wanted>
expect() { if [ "$2" = "$3" ]; then ok "$1 = $2"; elif [ -z "$2" ]; then skip "$1: could not read (permissions or plan)"; else bad "$1 = $2 (want $3)"; fi; }

echo "Auditing $FULL against $ANSWERS"
repo=$(api "repos/$FULL") || { bad "repository $FULL does not exist or is not visible to you"; exit 1; }
# jq's // treats false as missing, so map only null to "".
val() { jq -r "($1) | if . == null then \"\" else tostring end" 2>/dev/null; }
jqr() { val "$1" <<<"$repo"; }

echo "==> repository"
expect "visibility" "$(jqr .visibility)" "$VIS"
expect "allow_squash_merge" "$(jqr .allow_squash_merge)" true
expect "allow_merge_commit" "$(jqr .allow_merge_commit)" false
expect "allow_rebase_merge" "$(jqr .allow_rebase_merge)" false
expect "delete_branch_on_merge" "$(jqr .delete_branch_on_merge)" true
expect "allow_auto_merge" "$(jqr .allow_auto_merge)" true
expect "squash_merge_commit_title" "$(jqr .squash_merge_commit_title)" PR_TITLE

echo "==> actions"
wf=$(api "repos/$FULL/actions/permissions/workflow")
expect "default_workflow_permissions" "$(val .default_workflow_permissions <<<"$wf")" read
expect "can_approve_pull_request_reviews" "$(val .can_approve_pull_request_reviews <<<"$wf")" false
ap=$(api "repos/$FULL/actions/permissions")
expect "sha_pinning_required" "$(val .sha_pinning_required <<<"$ap")" true

echo "==> dependabot"
if gh api "repos/$FULL/vulnerability-alerts" >/dev/null 2>&1; then ok "vulnerability alerts enabled"; else bad "vulnerability alerts disabled"; fi
expect "automated security fixes" "$(api "repos/$FULL/automated-security-fixes" | val .enabled)" true
skip "malware alerts: UI-only setting, check Settings -> Advanced Security"

if [ "$VIS" = public ]; then
  echo "==> public-repo security features"
  expect "secret scanning" "$(jqr .security_and_analysis.secret_scanning.status)" enabled
  expect "push protection" "$(jqr .security_and_analysis.secret_scanning_push_protection.status)" enabled
  expect "private vulnerability reporting" "$(api "repos/$FULL/private-vulnerability-reporting" | val .enabled)" true
  expect "CodeQL default setup" "$(api "repos/$FULL/code-scanning/default-setup" | val .state)" configured
  expect "fork PR workflow approval" "$(api "repos/$FULL/actions/permissions/fork-pr-contributor-approval" | val .approval_policy)" all_external_contributors
fi

echo "==> ruleset"
if [ "$GOV" = yes ]; then
  rid=$(api "repos/$FULL/rulesets" | jq -r '.[] | select(.name=="main") | .id' | head -1)
  if [ -z "$rid" ]; then
    bad "ruleset 'main' missing"
  else
    rs=$(api "repos/$FULL/rulesets/$rid")
    expect "ruleset 'main' enforcement" "$(jq -r '.enforcement' <<<"$rs")" active
    expect "ruleset requires ci-ok" "$(jq -r '[.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context] | index("ci-ok") != null' <<<"$rs")" true
    expect "ruleset requires PR" "$(jq -r '[.rules[].type] | index("pull_request") != null' <<<"$rs")" true
    expect "ruleset blocks force-push" "$(jq -r '[.rules[].type] | index("non_fast_forward") != null' <<<"$rs")" true
  fi
else
  skip "private repo on GitHub Free: rulesets unavailable (documented gap in docs/THREAT_MODEL.md)"
fi

if [ "$PUBLISHES" = yes ]; then
  echo "==> releases"
  expect "immutable releases" "$(api "repos/$FULL/immutable-releases" | val .enabled)" true
  if [ "$GOV" = yes ]; then
    if api "repos/$FULL/environments/release" >/dev/null; then ok "environment 'release' exists"; else bad "environment 'release' missing"; fi
  fi
fi

echo "==> secrets (names only)"
names=$(gh secret list -R "$FULL" --json name --jq '.[].name' 2>/dev/null) || { skip "cannot list secrets (needs admin)"; names=""; }
want=(RELEASE_PLEASE_TOKEN)
[ "$CLAUDE" = yes ] && want+=(CLAUDE_CODE_OAUTH_TOKEN)
[ "$AGENTIC" = yes ] && want+=(EVAL_ANTHROPIC_API_KEY)
for s in "${want[@]}"; do
  if grep -qx "$s" <<<"$names"; then ok "secret $s set"; else bad "secret $s missing"; fi
done

echo "==> not checkable from the API (confirm by hand)"
[ "$CODERABBIT" = yes ] && skip "CodeRabbit GitHub App installed on the repo"
[ "$SONAR" = yes ] && skip "SonarQube Cloud project imported with Automatic Analysis on"
[ "$PUBLISHES" = yes ] && skip "trusted publisher registered on each registry"
skip "pre-commit hooks installed locally (uvx pre-commit install)"

echo
if [ "$drift" = 0 ]; then echo "NO DRIFT"; else echo "DRIFT FOUND: re-run ./scripts/bootstrap-github.sh (idempotent) or fix the items above"; exit 1; fi
