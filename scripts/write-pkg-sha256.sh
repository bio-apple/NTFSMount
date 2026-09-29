#!/bin/bash
# 为安装包写 SHA256 sidecar（`HASH  filename`）和 GitHub Release 的校验附录。
# 这不是完整 Release notes。GitHub Release 正文由 scripts/generate-release-notes.sh
# 在 v* tag 上生成；docs/RELEASE_NOTES/<version>.md 只是可选覆盖。
# 用法: write-pkg-sha256.sh <path-to-pkg>
set -euo pipefail
PKG="${1:?usage: write-pkg-sha256.sh <pkg>}"
[[ -f "$PKG" ]] || {
  echo "error: not found: $PKG" >&2
  exit 1
}

DIR="$(cd "$(/usr/bin/dirname "$PKG")" && pwd)"
BASE="$(/usr/bin/basename "$PKG")"
SIDECAR="$DIR/$BASE.sha256"

if [[ -x /usr/bin/shasum ]]; then
  (cd "$DIR" && /usr/bin/shasum -a 256 "$BASE" >"$BASE.sha256")
elif command -v sha256sum >/dev/null; then
  (cd "$DIR" && sha256sum "$BASE" >"$BASE.sha256")
else
  echo "error: shasum or sha256sum is required" >&2
  exit 1
fi

HASH="$(/usr/bin/awk '{print $1; exit}' "$SIDECAR")"
[[ ${#HASH} -eq 64 ]] || {
  echo "error: invalid SHA256: $HASH" >&2
  exit 1
}

NOTES="$DIR/$BASE.release-notes.md"
/bin/cat >"$NOTES" <<EOF
## Verify the package

$BASE
SHA256:
$HASH

Verify:

\`\`\`bash
shasum -a 256 "$BASE"
\`\`\`

The result must match the SHA256 above. You can also download \`$BASE.sha256\` and run \`shasum -a 256 -c "$BASE.sha256"\`.
EOF

echo "ok $SIDECAR"
echo "SHA256=${HASH}"
echo "SHA256: $HASH"
echo "Release notes fragment: $NOTES"
/bin/cat "$NOTES"
