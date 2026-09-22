#!/bin/bash
# Developer ID 签名并公证。没有证书时只做 ad-hoc 并警告。
# 用法: CODESIGN_IDENTITY="Developer ID Application: Name (TEAM)" ./scripts/notarize.sh [app]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/dist/NTFSMount.app}"
ID="${CODESIGN_IDENTITY:-}"
[[ -d "$APP" ]] || { echo "error: 找不到 $APP" >&2; exit 1; }

sign_adhoc() {
  echo "warning: 未设置 CODESIGN_IDENTITY，使用 ad-hoc 签名（Gatekeeper 会拦截）" >&2
  codesign --force --sign - --identifier com.bioapple.ntfsmount "$APP"
}

if [[ -z "$ID" ]]; then
  sign_adhoc
  exit 0
fi

codesign --force --options runtime --timestamp --sign "$ID" --identifier com.bioapple.ntfsmount "$APP"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  ZIP="$(/usr/bin/mktemp /tmp/ntfsmount-notary.XXXXXX).zip"
  /usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  /bin/rm -f "$ZIP"
  echo "ok notarized $APP"
else
  echo "warning: 已用 Developer ID 签名，但未设置 NOTARY_PROFILE，跳过公证" >&2
fi
