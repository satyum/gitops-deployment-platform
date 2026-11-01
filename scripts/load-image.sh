#!/usr/bin/env bash
# Tag the local application image with a version and load it into kind.
set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'Usage: %s <x.y.z>\n' "$0" >&2
  exit 2
fi
docker tag local-platform-app:dev "local-platform-app:$1"
kind load docker-image "local-platform-app:$1" --name local-platform
