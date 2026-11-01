#!/usr/bin/env bash
# Render each environment, then check schemas and Kyverno policies without a cluster.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFORM=ghcr.io/yannh/kubeconform:v0.6.7
KYVERNO=ghcr.io/kyverno/kyverno-cli:v1.19.2
out="$(mktemp -d)"
chmod 755 "$out"
trap 'rm -rf "$out"' EXIT
cd "$ROOT"

helm lint --strict charts/local-platform-app
for env in dev prod; do
  helm template local-platform-app charts/local-platform-app \
    --namespace "gitops-$env" --values "environments/$env/values.yaml" > "$out/$env.yaml"
  docker run --rm -i "$KUBECONFORM" -strict -summary -kubernetes-version 1.37.0 - < "$out/$env.yaml"
  docker run --rm -v "$ROOT:/repo:ro" -v "$out:/out:ro" "$KYVERNO" \
    apply /repo/policies/app-baseline.yaml --resource "/out/$env.yaml" --remove-color
done

# The bad fixture must be rejected, proving the policies actually enforce.
if docker run --rm -v "$ROOT:/repo:ro" "$KYVERNO" \
  apply /repo/policies/app-baseline.yaml \
  --resource /repo/tests/fixtures/bad-deployment.yaml --remove-color; then
  printf 'FAIL: non-compliant fixture passed policy checks\n' >&2
  exit 1
fi
printf 'validation passed\n'
