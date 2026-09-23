#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/NTFSMount.app"
if ! mkdir -p "$ROOT/dist" 2>/dev/null || ! rm -rf "$APP" 2>/dev/null; then
  APP="/tmp/NTFSMount.app"
  rm -rf "$APP"
fi
BIN="$APP/Contents/MacOS/NTFSMount"
HELPERD="$APP/Contents/MacOS/ntfsmount-helperd"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
MACOS="$APP/Contents/MacOS"
ENTITLEMENTS="$ROOT/Resources/NTFSMount.entitlements"
mkdir -p "$MACOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchDaemons"

# Ensure bundled userspace stack is present.
if [[ ! -x "$ROOT/runtime/ntfs-3g" || ! -x "$ROOT/runtime/go-nfsv4" || ! -x "$ROOT/runtime/mkntfs" || ! -f "$ROOT/runtime/libntfs-3g.90.dylib" ]]; then
  bash "$ROOT/scripts/prepare-runtime.sh"
fi

clang -O2 -arch arm64 -mmacosx-version-min=13.0 \
  -isysroot "$SDK" \
  -framework Security -framework CoreFoundation \
  -o "$HELPERD" "$ROOT/helper/ntfsmount-helperd.c"

export MACOSX_DEPLOYMENT_TARGET=13.0
swift build -c release --arch arm64 --product NTFSMount --package-path "$ROOT"
BIN_DIR="$(swift build -c release --arch arm64 --product NTFSMount --package-path "$ROOT" --show-bin-path)"
cp "$BIN_DIR/NTFSMount" "$BIN"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/PrivacyInfo.xcprivacy" "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
cp "$ROOT/Resources/NTFSMount.entitlements" "$APP/Contents/Resources/NTFSMount.entitlements"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"
cp "$ROOT/THIRD_PARTY_LICENSES.md" "$APP/Contents/Resources/THIRD_PARTY_LICENSES.md"
cp "$ROOT/docs/DISTRIBUTION.md" "$APP/Contents/Resources/DISTRIBUTION.md"
cp "$ROOT/helper/ntfs-rw-helper" "$APP/Contents/Resources/ntfs-rw-helper"
cp "$ROOT/helper/install-helper.sh" "$APP/Contents/Resources/install-helper.sh"
cp "$ROOT/helper/uninstall-helper.sh" "$APP/Contents/Resources/uninstall-helper.sh"
cp "$ROOT/helper/com.bioapple.ntfsmount.helper.plist" "$APP/Contents/Library/LaunchDaemons/com.bioapple.ntfsmount.helper.plist"
/usr/bin/shasum -a 256 "$ROOT/helper/ntfs-rw-helper" | /usr/bin/awk '{print $1}' > "$APP/Contents/Resources/ntfs-rw-helper.sha256"
chmod 755 "$APP/Contents/Resources/ntfs-rw-helper" "$APP/Contents/Resources/install-helper.sh" "$APP/Contents/Resources/uninstall-helper.sh" "$BIN" "$HELPERD"

for f in ntfs-3g mkntfs go-nfsv4 libfuse.2.dylib libntfs-3g.90.dylib; do
  [[ -e "$ROOT/runtime/$f" ]] || { echo "error: missing runtime/$f" >&2; exit 1; }
  cp "$ROOT/runtime/$f" "$MACOS/$f"
  chmod 755 "$MACOS/$f"
done

sign() {
  local id="${CODESIGN_IDENTITY:--}"
  local extra=()
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    extra+=(--options runtime --timestamp --entitlements "$ENTITLEMENTS")
  else
    extra+=(--options runtime --entitlements "$ENTITLEMENTS")
  fi
  codesign --force --sign "$id" --identifier com.bioapple.ntfsmount.helperd "${extra[@]}" "$HELPERD"
  codesign --force --sign "$id" --identifier com.bioapple.ntfsmount.helper "${extra[@]}" "$APP/Contents/Resources/ntfs-rw-helper"
  codesign --force --sign "$id" \
    "$MACOS/libfuse.2.dylib" \
    "$MACOS/libntfs-3g.90.dylib" \
    "$MACOS/ntfs-3g" \
    "$MACOS/mkntfs" \
    "$MACOS/go-nfsv4" >/dev/null
  codesign --force --sign "$id" --identifier com.bioapple.ntfsmount "${extra[@]}" "$APP"
}

sign
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  bash "$ROOT/scripts/notarize.sh" "$APP"
fi
echo "built $APP"
/bin/ls -lh "$MACOS"
