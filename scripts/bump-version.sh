#!/usr/bin/env bash
# Bump CFBundleShortVersionString in project.yml + git tag.
#
# Versioning scheme: v{YY}.{M}.{NNN}
#   YY  = last 2 digits of current year (no zero pad)
#   M   = current month number 1-12 (no zero pad)
#   NNN = release counter for that YY.M, 3-digit zero-padded (001, 002, …)
#
# Usage:
#   bump-version.sh                    Auto: increment NNN if same YY.M, else reset to NNN=001
#   bump-version.sh 26.4.005           Explicit override
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_YML="$ROOT_DIR/ZaDarkHelper/project.yml"

[ -f "$PROJECT_YML" ] || { echo "Not found: $PROJECT_YML" >&2; exit 1; }

# Read current version string from project.yml (CFBundleShortVersionString line).
CURRENT=$(grep -E '^[[:space:]]+CFBundleShortVersionString:' "$PROJECT_YML" \
  | head -1 | sed -E 's/.*"([^"]+)".*/\1/')

# Today's YY.M components.
YY=$(date +%y)             # 26
YY=${YY#0}                 # strip leading zero (handles "06" → "6") — for 2026 stays 26
M=$(date +%-m)             # 4 (no zero pad)

if [ -n "${1:-}" ]; then
  NEW_VERSION="$1"
else
  # Parse current as YY.M.NNN. If matches today, ++NNN; else NNN=001.
  if [[ "$CURRENT" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    CUR_YY="${BASH_REMATCH[1]}"
    CUR_M="${BASH_REMATCH[2]}"
    CUR_NNN="${BASH_REMATCH[3]}"
  else
    CUR_YY=""
    CUR_M=""
    CUR_NNN=0
  fi

  if [ "$CUR_YY" = "$YY" ] && [ "$CUR_M" = "$M" ]; then
    # Same month → increment counter (strip leading zeros for arithmetic).
    NEXT=$(( 10#$CUR_NNN + 1 ))
  else
    NEXT=1
  fi

  printf -v NNN '%03d' "$NEXT"
  NEW_VERSION="${YY}.${M}.${NNN}"
fi

echo "==> Current: $CURRENT"
echo "==> Next:    $NEW_VERSION"

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
