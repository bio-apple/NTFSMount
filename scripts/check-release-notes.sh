#!/bin/bash
# Validate Release notes markdown (hand-written or generated).
# Generated notes from generate-release-notes.sh are the source of truth on
# a v* tag; a filled docs/RELEASE_NOTES/<version>.md is an optional override.
# Usage:
#   check-release-notes.sh <v1.0|1.0>
#   check-release-notes.sh --file PATH
# Missing docs/RELEASE_NOTES/<version>.md is not a hard fail: notes are
# generated from git log and then validated.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
raw="${1:-}"
file=""
generated=""
cleanup() {
  if [[ -n "$generated" && -f "$generated" ]]; then
    /bin/rm -f "$generated"
  fi
}
trap cleanup EXIT

if [[ "$raw" == "--file" ]]; then
  file="${2:-}"
  if [[ -z "$file" ]]; then
    echo "usage: check-release-notes.sh --file PATH" >&2
    exit 2
  fi
elif [[ -z "$raw" ]]; then
  echo "usage: check-release-notes.sh <version|--file PATH>" >&2
  exit 2
else
  ver="${raw#v}"
  file="$ROOT/docs/RELEASE_NOTES/${ver}.md"
  if [[ ! -f "$file" ]]; then
    echo "note: no hand-written $file; generating from git log" >&2
    generated="$(/usr/bin/mktemp)"
    bash "$ROOT/scripts/generate-release-notes.sh" "$ver" -o "$generated"
    file="$generated"
  fi
fi

if [[ ! -f "$file" ]]; then
  echo "error: missing $file" >&2
  exit 1
fi

required=(
  "## What's new"
  "## Fixes"
  "## Known issues"
  "## Helper: reinstall required?"
  "## Old config compatibility"
)
for h in "${required[@]}"; do
  if ! /usr/bin/grep -Fq "$h" "$file"; then
    echo "error: $file missing heading: $h" >&2
    exit 1
  fi
done

if /usr/bin/grep -Fq '_TBD' "$file" || /usr/bin/grep -Fq '**Yes / No**' "$file"; then
  echo "error: $file still contains template placeholders (_TBD or **Yes / No**)" >&2
  echo "Fill the hand-written file, or delete it so CI can generate notes from git log." >&2
  exit 1
fi

echo "ok $file"
