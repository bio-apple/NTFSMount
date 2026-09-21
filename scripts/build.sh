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
if [[ ! -x "$ROOT/runtime/ntfs-3g" || ! -x "$ROOT/runtime/go-nfsv4" || ! -f "$ROOT/runtime/libntfs-3g.90.dylib" ]]; then
  bash "$ROOT/scripts/prepare-runtime.sh"
fi

swiftc -parse-as-library -O \
  -target arm64-apple-macosx13.0 \
  -sdk "$SDK" \
  -framework SwiftUI \
  -framework AppKit \
  -framework ServiceManagement \
  "$ROOT/Sources/main.swift" \
  -o "$BIN"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/helper/ntfs-rw-helper" "$APP/Contents/Resources/ntfs-rw-helper"
cp "$ROOT/helper/install-helper.sh" "$APP/Contents/Resources/install-helper.sh"
chmod 755 "$APP/Contents/Resources/ntfs-rw-helper" "$APP/Contents/Resources/install-helper.sh" "$BIN"

for f in ntfs-3g go-nfsv4 libfuse.2.dylib libntfs-3g.90.dylib; do
  [[ -e "$ROOT/runtime/$f" ]] || { echo "error: missing runtime/$f" >&2; exit 1; }
  cp "$ROOT/runtime/$f" "$MACOS/$f"
  chmod 755 "$MACOS/$f"
done
codesign --force --sign - \
  "$MACOS/libfuse.2.dylib" \
  "$MACOS/libntfs-3g.90.dylib" \
  "$MACOS/ntfs-3g" \
  "$MACOS/go-nfsv4" >/dev/null

codesign --force --sign - --identifier local.ntfsmount "$APP" >/dev/null
echo "built $APP"
/bin/ls -lh "$MACOS"
