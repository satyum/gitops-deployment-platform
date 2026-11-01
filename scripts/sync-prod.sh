#!/usr/bin/env bash
# Manually sync production: this is the promotion gate, because prod has no automated sync.
set -euo pipefail

# A sync operation does not inherit syncOptions from the Application, so they are repeated here.
kubectl --context kind-local-platform --namespace argocd patch application local-platform-prod \
  --type merge --patch '{"operation":{"initiatedBy":{"username":"operator"},"sync":{"revision":"main","syncOptions":["CreateNamespace=true"]}}}'
