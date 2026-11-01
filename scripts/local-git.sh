#!/usr/bin/env bash
# Drive the disposable in-cluster Git repository. Nothing here touches this directory's Git state.
set -euo pipefail

KUBE_CONTEXT=kind-local-platform
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
K=(kubectl --context "$KUBE_CONTEXT" --namespace gitops-git)
G=(git -c user.name=local-gitops-demo -c user.email=demo@local.invalid)

in_pod() {
  "${K[@]}" exec -i deploy/local-git -- bash -euc "$1"
}

case "${1:-}" in
  up)
    kubectl --context "$KUBE_CONTEXT" apply -f "$ROOT/demo/local-git-server.yaml"
    "${K[@]}" rollout status deploy/local-git --timeout=120s
    ;;
  seed)
    tar -C "$ROOT" --exclude=.git -cf - . | in_pod '
      git init -q --bare -b main /srv/git/platform.git
      git clone -q /srv/git/platform.git /srv/work/platform 2>/dev/null
      tar -C /srv/work/platform -xf -'
    in_pod "cd /srv/work/platform
      git checkout -q -b main 2>/dev/null || true
      git add -A
      ${G[*]} commit -q -m 'Seed local GitOps demo'
      git push -q origin main
      git log --oneline -1"
    ;;
  set-dev-tag)
    [[ "${2:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'Usage: %s set-dev-tag <x.y.z>\n' "$0" >&2; exit 2; }
    in_pod "cd /srv/work/platform
      sed -i -E 's/^  tag: \"[^\"]*\"$/  tag: \"$2\"/' environments/dev/values.yaml
      git add -A
      ${G[*]} commit -q -m 'Set dev image tag to $2'
      git push -q origin main
      git log --oneline -1"
    ;;
  promote)
    in_pod "cd /srv/work/platform
      scripts/promote.sh
      git add -A
      ${G[*]} commit -q -m 'Promote dev image tag to prod'
      git push -q origin main
      git log --oneline -1"
    ;;
  revert-last)
    in_pod "cd /srv/work/platform
      ${G[*]} revert --no-edit HEAD >/dev/null
      git push -q origin main
      git log --oneline -1"
    ;;
  *)
    printf 'Usage: %s up|seed|set-dev-tag <x.y.z>|promote|revert-last\n' "$0" >&2
    exit 2
    ;;
esac
