#!/bin/bash
# GitHub Actions：把 Developer ID .p12 导入一次性钥匙串。无证书则跳过（ad-hoc 构建）。
# Secrets: APPLE_CERTIFICATE_BASE64、APPLE_CERTIFICATE_PASSWORD
# 可选: CODESIGN_IDENTITY（否则用钥匙串里第一张 Developer ID Application）
set -euo pipefail

if [[ -z "${APPLE_CERTIFICATE_BASE64:-}" ]]; then
  echo "no APPLE_CERTIFICATE_BASE64; signing skipped (ad-hoc)" >&2
  exit 0
fi
if [[ -z "${APPLE_CERTIFICATE_PASSWORD:-}" ]]; then
  echo "error: APPLE_CERTIFICATE_BASE64 需要 APPLE_CERTIFICATE_PASSWORD" >&2
  exit 1
fi

tmp="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ntfsmount-sign"
/bin/mkdir -p "$tmp"
p12="$tmp/cert.p12"
kc="$tmp/signing.keychain-db"
pass="$(/usr/bin/openssl rand -base64 32)"

printf '%s' "$APPLE_CERTIFICATE_BASE64" | /usr/bin/base64 --decode >"$p12"
/usr/bin/security create-keychain -p "$pass" "$kc"
/usr/bin/security set-keychain-settings -lut 21600 "$kc"
/usr/bin/security unlock-keychain -p "$pass" "$kc"
/usr/bin/security import "$p12" -k "$kc" -P "$APPLE_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -T /usr/bin/codesign -T /usr/bin/security
/usr/bin/security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$pass" "$kc" >/dev/null
/usr/bin/security list-keychains -d user -s "$kc"
/bin/rm -f "$p12"

ident="${CODESIGN_IDENTITY:-}"
if [[ -z "$ident" ]]; then
  ident="$(/usr/bin/security find-identity -v -p codesigning "$kc" | /usr/bin/awk -F'"' '/Developer ID Application/{print $2; exit}')"
fi
[[ -n "$ident" ]] || { echo "error: p12 里没有 Developer ID Application 证书" >&2; exit 1; }

echo "imported $ident"
if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    echo "CODESIGN_IDENTITY=$ident"
    echo "APP_SIGNING_KEYCHAIN=$kc"
  } >>"$GITHUB_ENV"
fi
