#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$ROOT/helper/ntfs-rw-helper"
out="$("$HELPER" selftest)"
echo "$out"
[[ "$out" == ok\ selftest* ]] || { echo "selftest failed" >&2; exit 1; }
ver="$("$HELPER" version)"
[[ "$ver" == HELPER_VERSION=4 ]] || { echo "version mismatch: $ver" >&2; exit 1; }
echo "ok tests"
