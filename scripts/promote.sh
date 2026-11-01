#!/usr/bin/env bash
# Copy the image tag from dev to prod in the working tree. Review and commit it through Git.
set -euo pipefail

ROOT="${GITOPS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SOURCE="$ROOT/environments/dev/values.yaml"
TARGET="$ROOT/environments/prod/values.yaml"

tag="$(sed -nE 's/^  tag: "([0-9]+\.[0-9]+\.[0-9]+)"$/\1/p' "$SOURCE")"
if [[ -z "$tag" ]]; then
  printf 'No x.y.z image tag found in %s\n' "$SOURCE" >&2
  exit 1
fi
if ! grep -Eq '^  tag: "[^"]*"$' "$TARGET"; then
  printf 'No image tag line found in %s\n' "$TARGET" >&2
  exit 1
fi
sed -i -E "s/^  tag: \"[^\"]*\"$/  tag: \"$tag\"/" "$TARGET"
printf 'prod image tag set to %s. Commit it, then sync local-platform-prod.\n' "$tag"
