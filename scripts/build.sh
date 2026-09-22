#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/NTFSMount.app"
if ! mkdir -p "$ROOT/dist" 2>/dev/null || ! rm -rf "$APP" 2>/dev/null; then
  APP="/tmp/NTFSMount.app"
  rm -rf "$APP"
fi
BIN="$APP/Contents/MacOS/NTFSMount"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
MACOS="$APP/Contents/MacOS"
mkdir -p "$MACOS" "$APP/Contents/Resources"

# Ensure bundled userspace stack is present.
if [[ ! -x "$ROOT/runtime/ntfs-3g" || ! -x "$ROOT/runtime/go-nfsv4" || ! -x "$ROOT/runtime/mkntfs" || ! -f "$ROOT/runtime/libntfs-3g.90.dylib" ]]; then
  bash "$ROOT/scripts/prepare-runtime.sh"
fi

# shellcheck disable=SC2206
SWIFT_SOURCES=("$ROOT/Sources"/*.swift)
swiftc -parse-as-library -O \
  -target arm64-apple-macosx13.0 \
  -sdk "$SDK" \
  -framework SwiftUI \
  -framework AppKit \
  -framework ServiceManagement \
  -framework DiskArbitration \
  "${SWIFT_SOURCES[@]}" \
  -o "$BIN"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/PrivacyInfo.xcprivacy" "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"
cp "$ROOT/THIRD_PARTY_LICENSES.md" "$APP/Contents/Resources/THIRD_PARTY_LICENSES.md"
cp "$ROOT/helper/ntfs-rw-helper" "$APP/Contents/Resources/ntfs-rw-helper"
cp "$ROOT/helper/install-helper.sh" "$APP/Contents/Resources/install-helper.sh"
cp "$ROOT/helper/uninstall-helper.sh" "$APP/Contents/Resources/uninstall-helper.sh"
chmod 755 "$APP/Contents/Resources/ntfs-rw-helper" "$APP/Contents/Resources/install-helper.sh" "$APP/Contents/Resources/uninstall-helper.sh" "$BIN"

for f in ntfs-3g mkntfs go-nfsv4 libfuse.2.dylib libntfs-3g.90.dylib; do
  [[ -e "$ROOT/runtime/$f" ]] || { echo "error: missing runtime/$f" >&2; exit 1; }
  cp "$ROOT/runtime/$f" "$MACOS/$f"
  chmod 755 "$MACOS/$f"
done
codesign --force --sign - \
  "$MACOS/libfuse.2.dylib" \
  "$MACOS/libntfs-3g.90.dylib" \
  "$MACOS/ntfs-3g" \
  "$MACOS/mkntfs" \
  "$MACOS/go-nfsv4" >/dev/null

codesign --force --sign - --identifier com.bioapple.ntfsmount "$APP" >/dev/null
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  bash "$ROOT/scripts/notarize.sh" "$APP"
fi
echo "built $APP"
/bin/ls -lh "$MACOS"
