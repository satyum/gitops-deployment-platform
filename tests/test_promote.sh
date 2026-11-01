#!/usr/bin/env bash
# Functional test for scripts/promote.sh using a throwaway copy of the environment files.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/environments/dev" "$tmp/environments/prod"

printf 'image:\n  tag: "9.8.7"\n' > "$tmp/environments/dev/values.yaml"
printf 'image:\n  tag: "1.0.0"\n' > "$tmp/environments/prod/values.yaml"
GITOPS_ROOT="$tmp" "$ROOT/scripts/promote.sh" >/dev/null
grep -Fxq '  tag: "9.8.7"' "$tmp/environments/prod/values.yaml"

printf 'image:\n  tag: "dev"\n' > "$tmp/environments/dev/values.yaml"
if GITOPS_ROOT="$tmp" "$ROOT/scripts/promote.sh" >/dev/null 2>&1; then
  printf 'FAIL: a moving tag was promoted\n' >&2
  exit 1
fi
grep -Fxq '  tag: "9.8.7"' "$tmp/environments/prod/values.yaml"
printf 'promote tests passed\n'
