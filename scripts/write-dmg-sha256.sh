#!/bin/bash
# 为 DMG 写 SHA256 sidecar（`HASH  filename`）和 GitHub Release 正文片段。
# 用法: write-dmg-sha256.sh <path-to-dmg>
set -euo pipefail
DMG="${1:?usage: write-dmg-sha256.sh <dmg>}"
[[ -f "$DMG" ]] || { echo "error: 找不到 $DMG" >&2; exit 1; }

DIR="$(cd "$(/usr/bin/dirname "$DMG")" && pwd)"
BASE="$(/usr/bin/basename "$DMG")"
SIDECAR="$DIR/$BASE.sha256"
NOTES="$DIR/$BASE.release-notes.md"

if [[ -x /usr/bin/shasum ]]; then
  (cd "$DIR" && /usr/bin/shasum -a 256 "$BASE" > "$BASE.sha256")
elif command -v sha256sum >/dev/null; then
  (cd "$DIR" && sha256sum "$BASE" > "$BASE.sha256")
else
  echo "error: 需要 shasum 或 sha256sum" >&2
  exit 1
fi

HASH="$(/usr/bin/awk '{print $1; exit}' "$SIDECAR")"
[[ ${#HASH} -eq 64 ]] || { echo "error: 无效 SHA256: $HASH" >&2; exit 1; }

/bin/cat > "$NOTES" <<EOF
$BASE
SHA256:
$HASH

校验完整性 · Verify:

\`\`\`bash
shasum -a 256 $BASE
\`\`\`

结果应与上面的 SHA256 完全一致。也可下载 \`$BASE.sha256\` 后执行 \`shasum -a 256 -c $BASE.sha256\`。
EOF

echo "ok $SIDECAR"
echo "SHA256: $HASH"
echo "Release notes fragment: $NOTES"
/bin/cat "$NOTES"
