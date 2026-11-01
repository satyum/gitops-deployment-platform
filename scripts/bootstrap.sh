#!/usr/bin/env bash
# Install Argo CD and Kyverno into the local kind cluster, then apply policies and applications.
set -euo pipefail

KUBE_CONTEXT=kind-local-platform
ARGOCD_CHART_VERSION=10.11.6
KYVERNO_CHART_VERSION=3.9.2
DEFAULT_REPO_URL=https://github.com/satyum/gitops-deployment-platform.git
GITOPS_REPO_URL="${GITOPS_REPO_URL:-$DEFAULT_REPO_URL}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Argo CD repo-server crashes with "too many open files" when inotify instances run out.
MIN_INOTIFY_INSTANCES=512
inotify_instances="$(sysctl -n fs.inotify.max_user_instances)"
if ((inotify_instances < MIN_INOTIFY_INSTANCES)); then
  printf 'fs.inotify.max_user_instances is %s; need at least %s. Run:\n' \
    "$inotify_instances" "$MIN_INOTIFY_INSTANCES" >&2
  printf '  sudo sysctl fs.inotify.max_user_instances=%s\n' "$MIN_INOTIFY_INSTANCES" >&2
  exit 1
fi

helm --kube-context "$KUBE_CONTEXT" upgrade --install kyverno kyverno \
  --repo https://kyverno.github.io/kyverno/ --version "$KYVERNO_CHART_VERSION" \
  --namespace kyverno --create-namespace \
  --values bootstrap/kyverno-values.yaml --wait --timeout 5m
helm --kube-context "$KUBE_CONTEXT" upgrade --install argocd argo-cd \
  --repo https://argoproj.github.io/argo-helm --version "$ARGOCD_CHART_VERSION" \
  --namespace argocd --create-namespace \
  --values bootstrap/argocd-values.yaml --wait --timeout 5m

kubectl --context "$KUBE_CONTEXT" apply -f policies/
# GITOPS_REPO_URL points Argo CD at another repository, such as the local demo server.
# The AppProject must exist before the Applications that reference it.
for manifest in argocd/project.yaml argocd/app-*.yaml; do
  sed "s|$DEFAULT_REPO_URL|$GITOPS_REPO_URL|" "$manifest" |
    kubectl --context "$KUBE_CONTEXT" apply -f -
done
