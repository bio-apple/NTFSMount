#!/bin/bash
# Developer ID 签名并公证。没有证书时只做 ad-hoc + Hardened Runtime 并警告。
# 用法:
#   CODESIGN_IDENTITY="Developer ID Application: Name (TEAM)" ./scripts/notarize.sh [app]
#   ./scripts/notarize.sh dist/NTFSMount.dmg
# 公证凭据（任选）:
#   NOTARY_PROFILE=钥匙串里的 notarytool profile（本机）
#   或 APPLE_API_KEY_ID + APPLE_API_ISSUER + APPLE_API_KEY（p8 全文，CI）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-$ROOT/dist/NTFSMount.app}"
ID="${CODESIGN_IDENTITY:-}"
ENTITLEMENTS="$ROOT/Resources/NTFSMount.entitlements"

has_notary_creds() {
  [[ -n "${NOTARY_PROFILE:-}" ]] && return 0
  [[ -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_API_ISSUER:-}" ]] || return 1
  [[ -n "${APPLE_API_KEY:-}" || -f "${APPLE_API_KEY_PATH:-}" ]]
}

submit_notary() {
  local artifact="$1"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$artifact" --keychain-profile "$NOTARY_PROFILE" --wait
    return
  fi
  local keyf cleanup=0
  if [[ -n "${APPLE_API_KEY_PATH:-}" && -f "${APPLE_API_KEY_PATH}" ]]; then
    keyf="$APPLE_API_KEY_PATH"
  else
    keyf="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/AuthKey.XXXXXX.p8")"
    cleanup=1
    printf '%s\n' "$APPLE_API_KEY" >"$keyf"
  fi
  local st=0
  set +e
  xcrun notarytool submit "$artifact" --key "$keyf" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER" --wait
  st=$?
  set -e
  [[ "$cleanup" -eq 1 ]] && /bin/rm -f "$keyf"
  return "$st"
}

if [[ -f "$TARGET" ]]; then
  if ! has_notary_creds; then
    echo "warning: 无公证凭据，跳过 $TARGET" >&2
    exit 0
  fi
  submit_notary "$TARGET"
  xcrun stapler staple "$TARGET"
  echo "ok notarized $TARGET"
  exit 0
fi

APP="$TARGET"
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
  if [[ -x "$APP/Contents/Resources/ntfs-rw-helper" ]]; then
    codesign --force --sign "$identity" --identifier com.bioapple.ntfsmount.helper "${extra[@]}" "$APP/Contents/Resources/ntfs-rw-helper"
  fi
  codesign --force --sign "$identity" \
    "$MACOS/libfuse.2.dylib" \
    "$MACOS/libntfs-3g.90.dylib" \
    "$MACOS/ntfs-3g" \
    "$MACOS/mkntfs" \
    "$MACOS/ntfsfix" \
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

if ! has_notary_creds; then
  echo "warning: 已用 Developer ID 签名，但未设置 NOTARY_PROFILE / APPLE_API_KEY_*，跳过公证" >&2
  exit 0
fi

ZIP="$(/usr/bin/mktemp /tmp/ntfsmount-notary.XXXXXX).zip"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
submit_notary "$ZIP"
xcrun stapler staple "$APP"
/bin/rm -f "$ZIP"
echo "ok notarized $APP"
