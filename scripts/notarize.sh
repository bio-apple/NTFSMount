#!/bin/bash
# Developer ID 签名并公证。没有证书时只做 ad-hoc + Hardened Runtime 并警告。
# 用法: CODESIGN_IDENTITY="Developer ID Application: Name (TEAM)" ./scripts/notarize.sh [app]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/dist/NTFSMount.app}"
ID="${CODESIGN_IDENTITY:-}"
ENTITLEMENTS="$ROOT/Resources/NTFSMount.entitlements"
[[ -d "$APP" ]] || { echo "error: 找不到 $APP" >&2; exit 1; }

MACOS="$APP/Contents/MacOS"
HELPERD="$MACOS/ntfsmount-helperd"

sign_nested() {
  local identity="$1"
  shift
  local extra=("$@")
  if [[ -x "$HELPERD" ]]; then
    codesign --force --sign "$identity" --identifier com.bioapple.ntfsmount.helperd "${extra[@]}" "$HELPERD"
  fi
  codesign --force --sign "$identity" \
    "$MACOS/libfuse.2.dylib" \
    "$MACOS/libntfs-3g.90.dylib" \
    "$MACOS/ntfs-3g" \
    "$MACOS/mkntfs" \
    "$MACOS/go-nfsv4"
  codesign --force --sign "$identity" --identifier com.bioapple.ntfsmount "${extra[@]}" "$APP"
}

if [[ -z "$ID" ]]; then
  echo "warning: 未设置 CODESIGN_IDENTITY，使用 ad-hoc 签名（Gatekeeper 会拦截）" >&2
  sign_nested - --options runtime --entitlements "$ENTITLEMENTS"
  exit 0
fi

sign_nested "$ID" --options runtime --timestamp --entitlements "$ENTITLEMENTS"
codesign --verify --strict --deep "$APP"
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
