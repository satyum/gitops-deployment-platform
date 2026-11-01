#!/usr/bin/env bash
# End-to-end check against the local Git demo: dev auto-sync, prod gate, promotion, rollback,
# self-heal and live policy enforcement. Expects bootstrap with the local Git URL to be complete.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
K=(kubectl --context kind-local-platform)
cd "$ROOT"

image() {
  "${K[@]}" -n "gitops-$1" get deploy local-platform-app \
    -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true
}
field() {
  "${K[@]}" -n argocd get application "local-platform-$1" -o "jsonpath=$2"
}
refresh() {
  "${K[@]}" -n argocd annotate application "local-platform-$1" \
    argocd.argoproj.io/refresh=hard --overwrite >/dev/null
}
wait_for() { # description, command
  local attempt
  for attempt in $(seq 1 45); do
    if eval "$2"; then
      printf 'PASS: %s\n' "$1"
      return 0
    fi
    sleep 4
  done
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}
synced_image() { # env, tag
  [[ "$(image "$1")" == "local-platform-app:$2" ]] &&
    [[ "$(field "$1" '{.status.sync.status}')" == Synced ]] &&
    [[ "$(field "$1" '{.status.health.status}')" == Healthy ]]
}
out_of_sync() {
  refresh "$1"
  [[ "$(field "$1" '{.status.sync.status}')" == OutOfSync ]]
}

scripts/sync-prod.sh >/dev/null
wait_for 'prod first manual sync runs 0.1.0' 'synced_image prod 0.1.0'

scripts/local-git.sh set-dev-tag 0.1.0 >/dev/null
refresh dev
wait_for 'dev auto-syncs a Git change to 0.1.0' 'synced_image dev 0.1.0'
scripts/local-git.sh revert-last >/dev/null
refresh dev
wait_for 'dev auto-syncs the revert back to 0.1.1' 'synced_image dev 0.1.1'

scripts/local-git.sh promote >/dev/null
wait_for 'promotion commit marks prod OutOfSync' 'out_of_sync prod'
[[ "$(image prod)" == local-platform-app:0.1.0 ]] && printf 'PASS: prod gate holds at 0.1.0 before manual sync\n'
scripts/sync-prod.sh >/dev/null
wait_for 'prod runs 0.1.1 after manual sync' 'synced_image prod 0.1.1'

scripts/local-git.sh revert-last >/dev/null
wait_for 'rollback commit marks prod OutOfSync' 'out_of_sync prod'
scripts/sync-prod.sh >/dev/null
wait_for 'prod rolled back to 0.1.0' 'synced_image prod 0.1.0'

"${K[@]}" -n gitops-dev scale deploy/local-platform-app --replicas=3 >/dev/null
wait_for 'dev self-heals manual drift to 1 replica' \
  '[[ "$("${K[@]}" -n gitops-dev get deploy local-platform-app -o "jsonpath={.spec.replicas}")" == 1 ]]'

if "${K[@]}" apply --dry-run=server -f tests/fixtures/bad-deployment.yaml >/dev/null 2>&1; then
  printf 'FAIL: Kyverno admitted the non-compliant Deployment\n' >&2
  exit 1
fi
printf 'PASS: Kyverno rejects the non-compliant Deployment at admission\n'
printf 'All GitOps checks passed\n'
