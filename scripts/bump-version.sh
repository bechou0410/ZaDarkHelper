#!/usr/bin/env bash
# Bump CFBundleShortVersionString in project.yml + git tag.
# Usage: bump-version.sh <new-version>
set -euo pipefail

NEW_VERSION="${1:?new version required (e.g. 0.2.0)}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_YML="$ROOT_DIR/ZaDarkHelper/project.yml"

if [ ! -f "$PROJECT_YML" ]; then
  echo "Not found: $PROJECT_YML" >&2
  exit 1
fi

# Update version strings in project.yml.
sed -i.bak \
  -e "s/CFBundleShortVersionString: .*/CFBundleShortVersionString: \"$NEW_VERSION\"/" \
  -e "s/MARKETING_VERSION: .*/MARKETING_VERSION: \"$NEW_VERSION\"/" \
  "$PROJECT_YML"
rm -f "$PROJECT_YML.bak"

echo "==> Updated project.yml to $NEW_VERSION"

if command -v git >/dev/null 2>&1 && git -C "$ROOT_DIR" rev-parse >/dev/null 2>&1; then
  git -C "$ROOT_DIR" add "$PROJECT_YML"
  git -C "$ROOT_DIR" commit -m "chore: bump version to $NEW_VERSION"
  git -C "$ROOT_DIR" tag -a "v$NEW_VERSION" -m "v$NEW_VERSION"
  echo "==> Tagged v$NEW_VERSION"
else
  echo "(skip git tag — not a git repo)"
fi
