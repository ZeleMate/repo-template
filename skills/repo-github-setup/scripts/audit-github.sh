#!/usr/bin/env bash
# Read-only audit: compare a GitHub repo's live settings with what the repo template expects.
#   audit-github.sh [repo-dir] [owner/repo]
# Expectations come from repo-dir/.copier-answers.yml; owner/repo defaults to github_owner/repo_name from it (project_slug for answers older than v1.0).
# Changes nothing. Exits 1 if any setting has drifted, 0 otherwise.
# Needs: gh (authenticated), jq, uv (to read the YAML answers file).
set -uo pipefail

REPO_DIR="$(cd "${1:-.}" && pwd)"
ANSWERS="$REPO_DIR/.copier-answers.yml"
[[ -f "$ANSWERS" ]] || { echo "No .copier-answers.yml in $REPO_DIR"; exit 2; }
gh auth status >/dev/null 2>&1 || { echo "gh is not authenticated: run 'gh auth login'"; exit 2; }

# key=value lines for the answers this audit needs.
eval "$(uvx --no-build --quiet --from pyyaml python - "$ANSWERS" <<'PY'
import shlex, sys, yaml
a = yaml.safe_load(open(sys.argv[1]))
vis = a.get("visibility", "private")
gov = vis == "public" or a.get("github_plan") == "pro"
out = {
    "OWNER": a.get("github_owner", ""), "SLUG": a.get("repo_name") or a.get("project_slug", ""), "VIS": vis,
    "GOV": "yes" if gov else "no", "PUBLISHES": "yes" if a.get("publishes") else "no",
    "CODERABBIT": "yes" if "coderabbit" in (a.get("ai_reviewers") or []) else "no",
    "SONAR": "yes" if a.get("quality_platform") == "sonarqube-cloud" else "no",
    "SRC": a.get("_src_path", ""),
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
expect() { if [[ "$2" = "$3" ]]; then ok "$1 = $2"; elif [[ -z "$2" ]]; then skip "$1: could not read (permissions or plan)"; else bad "$1 = $2 (want $3)"; fi; }

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
# A repo may keep a stricter allowlist than the bootstrap's `all`, but it must allow what the
# template's workflows call, or ci.yml fails at startup with no job logs.
if [[ "$(val .allowed_actions <<<"$ap")" = selected ]]; then
  sel=$(api "repos/$FULL/actions/permissions/selected-actions")
  for want in "ZeleMate/*" "astral-sh/setup-uv@*" "dependabot/fetch-metadata@*"; do
    if jq -e --arg w "$want" '.patterns_allowed | index($w)' <<<"$sel" >/dev/null; then ok "allowed action $want"; else bad "allowed actions list lacks $want (ci.yml or dependabot-automerge.yml fails at startup)"; fi
  done
fi

echo "==> dependabot"
if gh api "repos/$FULL/vulnerability-alerts" >/dev/null 2>&1; then ok "vulnerability alerts enabled"; else bad "vulnerability alerts disabled"; fi
expect "automated security fixes" "$(api "repos/$FULL/automated-security-fixes" | val .enabled)" true
skip "malware alerts: UI-only setting, check Settings -> Advanced Security"

if [[ "$VIS" = public ]]; then
  echo "==> public-repo security features"
  expect "secret scanning" "$(jqr .security_and_analysis.secret_scanning.status)" enabled
  expect "push protection" "$(jqr .security_and_analysis.secret_scanning_push_protection.status)" enabled
  expect "private vulnerability reporting" "$(api "repos/$FULL/private-vulnerability-reporting" | val .enabled)" true
  expect "CodeQL default setup" "$(api "repos/$FULL/code-scanning/default-setup" | val .state)" configured
  expect "fork PR workflow approval" "$(api "repos/$FULL/actions/permissions/fork-pr-contributor-approval" | val .approval_policy)" all_external_contributors
fi

echo "==> ruleset"
if [[ "$GOV" = yes ]]; then
  rid=$(api "repos/$FULL/rulesets" | jq -r '.[] | select(.name=="main") | .id' | head -1)
  if [[ -z "$rid" ]]; then
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

if [[ "$PUBLISHES" = yes ]]; then
  echo "==> releases"
  expect "immutable releases" "$(api "repos/$FULL/immutable-releases" | val .enabled)" true
  if [[ "$GOV" = yes ]]; then
    if api "repos/$FULL/environments/release" >/dev/null; then ok "environment 'release' exists"; else bad "environment 'release' missing"; fi
  fi
fi

echo "==> secrets (names only)"
# The repo's secret requirements, rendered by the template (ADR 0003). The audit only applies them;
# which secret a repo needs is decided in the template's includes/secrets.jinja, not here.
REQS="$REPO_DIR/.github/secret-requirements.json"
# Sets tpl_private to true, false or unknown: is the template repo private? Asks GitHub once.
tpl_private=""
check_template_private() {
  [[ -n "$tpl_private" ]] && return
  local tpl p
  tpl=$(sed -E -e 's#^gh:##' -e 's#^(https://|git@)github\.com[:/]##' -e 's#\.git$##' <<<"$SRC")
  tpl_private=unknown
  if [[ "$tpl" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    p=$(api "repos/$tpl" --jq .private)
    [[ "$p" = true || "$p" = false ]] && tpl_private=$p
  fi
}
if [[ ! -f "$REQS" ]]; then
  skip "no .github/secret-requirements.json (template older than ADR 0003): run copier update, then audit again"
elif ! names=$(gh secret list -R "$FULL" --json name --jq '.[].name' 2>/dev/null); then
  skip "cannot list secrets (needs admin)"
else
  # One line per Actions secret: name, waiver (kind=value) and condition, "-" when absent.
  # ("-" because read collapses empty tab-separated fields.) fd 3, so gh can't eat the list.
  while IFS=$'\t' read -r -u 3 name waiver cond; do
    case "$waiver" in
      -) ;;
      workflow_disabled=*)
        wf=${waiver#workflow_disabled=}
        if [[ "$(api "repos/$FULL/actions/workflows/$wf" | val .state)" = disabled_manually ]]; then
          ok "$wf disabled, so $name is not needed (re-enable with: gh workflow enable $wf)"; continue
        fi ;;
      *) skip "$name: unknown waiver '$waiver' (update the repo-standards plugin)"; continue ;;
    esac
    case "$cond" in
      -) ;;
      template_private)
        check_template_private
        case "$tpl_private" in
          true) ;;
          false) continue ;;
          *) skip "template source '$SRC': could not tell if it is a private GitHub repo; if so, $name must be set"; continue ;;
        esac ;;
      *) skip "$name: unknown condition '$cond' (update the repo-standards plugin)"; continue ;;
    esac
    if grep -qx "$name" <<<"$names"; then ok "secret $name set"; else bad "secret $name missing"; fi
  done 3< <(jq -r '.secrets[] | select(.store == "actions")
    | [.name, ((.waived_if // {}) | to_entries | map("\(.key)=\(.value)") | join(",") | if . == "" then "-" else . end), (.only_if // "-")] | @tsv' "$REQS")
fi

echo "==> not checkable from the API (confirm by hand)"
[[ "$CODERABBIT" = yes ]] && skip "CodeRabbit GitHub App installed on the repo"
[[ "$SONAR" = yes ]] && skip "SonarQube Cloud project imported with Automatic Analysis on"
[[ "$PUBLISHES" = yes ]] && skip "trusted publisher registered on each registry"
skip "pre-commit hooks installed locally (uvx pre-commit install)"

echo
if [[ "$drift" = 0 ]]; then echo "NO DRIFT"; else echo "DRIFT FOUND: re-run ./scripts/bootstrap-github.sh (idempotent) or fix the items above"; exit 1; fi
