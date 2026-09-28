#!/bin/bash
set -euo pipefail
if [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" != "1" && "$(/usr/bin/uname -m)" != "arm64" ]]; then
  echo "error: NTFSMount 仅支持 Apple Silicon（M 芯片 / arm64），不支持 Intel Mac（x86_64）。当前架构：$(/usr/bin/uname -m)" >&2
  exit 1
fi
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
if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
  ENTITLEMENTS="$ROOT/Resources/NTFSMount-adhoc.entitlements"
fi
mkdir -p "$MACOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchDaemons"

# Ensure bundled userspace stack is present.
if [[ ! -x "$ROOT/runtime/ntfs-3g" || ! -x "$ROOT/runtime/go-nfsv4" || ! -x "$ROOT/runtime/mkntfs" || ! -x "$ROOT/runtime/ntfsfix" || ! -f "$ROOT/runtime/libntfs-3g.90.dylib" ]]; then
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
if [[ -f "$ROOT/Resources/Localizable.xcstrings" ]]; then
  cp "$ROOT/Resources/Localizable.xcstrings" "$APP/Contents/Resources/Localizable.xcstrings"
fi
for lang in en zh-Hans zh-Hant ja; do
  src="$ROOT/Sources/NTFSMountCore/Resources/${lang}.lproj"
  dst="$APP/Contents/Resources/${lang}.lproj"
  mkdir -p "$dst"
  cp "$src/Localizable.strings" "$dst/Localizable.strings"
  if [[ -f "$src/InfoPlist.strings" ]]; then
    cp "$src/InfoPlist.strings" "$dst/InfoPlist.strings"
  fi
done
CORE_BUNDLE=""
for candidate in \
  "$BIN_DIR/NTFSMount_NTFSMountCore.bundle" \
  "$BIN_DIR/NTFSMountCore_NTFSMountCore.bundle"
do
  if [[ -d "$candidate" ]]; then
    CORE_BUNDLE="$candidate"
    break
  fi
done
if [[ -n "$CORE_BUNDLE" ]]; then
  rm -rf "$APP/Contents/Resources/$(basename "$CORE_BUNDLE")"
  cp -R "$CORE_BUNDLE" "$APP/Contents/Resources/"
fi
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"
cp "$ROOT/THIRD_PARTY_LICENSES.md" "$APP/Contents/Resources/THIRD_PARTY_LICENSES.md"
cp "$ROOT/docs/DISTRIBUTION.md" "$APP/Contents/Resources/DISTRIBUTION.md"
cp "$ROOT/helper/ntfs-rw-helper" "$APP/Contents/Resources/ntfs-rw-helper"
cp "$ROOT/helper/install-helper.sh" "$APP/Contents/Resources/install-helper.sh"
cp "$ROOT/helper/uninstall-helper.sh" "$APP/Contents/Resources/uninstall-helper.sh"
cp "$ROOT/scripts/ntfsmount-diagnose.sh" "$APP/Contents/Resources/ntfsmount-diagnose.sh"
cp "$ROOT/scripts/ntfs3g-version.sh" "$APP/Contents/Resources/ntfs3g-version.sh"
cp "$ROOT/runtime/versions.txt" "$APP/Contents/Resources/versions.txt"
cp "$ROOT/helper/com.bioapple.ntfsmount.helper.plist" "$APP/Contents/Library/LaunchDaemons/com.bioapple.ntfsmount.helper.plist"
/usr/bin/shasum -a 256 "$ROOT/helper/ntfs-rw-helper" | /usr/bin/awk '{print $1}' > "$APP/Contents/Resources/ntfs-rw-helper.sha256"
chmod 755 "$APP/Contents/Resources/ntfs-rw-helper" "$APP/Contents/Resources/install-helper.sh" "$APP/Contents/Resources/uninstall-helper.sh" "$APP/Contents/Resources/ntfsmount-diagnose.sh" "$BIN" "$HELPERD"

for f in ntfs-3g mkntfs ntfsfix go-nfsv4 libfuse.2.dylib libntfs-3g.90.dylib; do
  [[ -e "$ROOT/runtime/$f" ]] || { echo "error: missing runtime/$f" >&2; exit 1; }
  cp "$ROOT/runtime/$f" "$MACOS/$f"
  chmod 755 "$MACOS/$f"
done

FRAMEWORKS="$APP/Contents/Frameworks"
mkdir -p "$FRAMEWORKS"
SPARKLE_FW=""
if [[ -d "$BIN_DIR/Sparkle.framework" ]]; then
  SPARKLE_FW="$BIN_DIR/Sparkle.framework"
else
  SPARKLE_FW="$(/usr/bin/find "$ROOT/.build" -path '*Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework' -type d -print -quit 2>/dev/null || true)"
fi
[[ -n "$SPARKLE_FW" && -d "$SPARKLE_FW" ]] || {
  echo "error: Sparkle.framework not found after swift build" >&2
  exit 1
}
/bin/rm -rf "$FRAMEWORKS/Sparkle.framework"
/usr/bin/ditto "$SPARKLE_FW" "$FRAMEWORKS/Sparkle.framework"
if ! /usr/bin/otool -l "$BIN" | /usr/bin/grep -F -q '@executable_path/../Frameworks'; then
  /usr/bin/install_name_tool -add_rpath '@executable_path/../Frameworks' "$BIN"
fi

sign() {
  local id="${CODESIGN_IDENTITY:--}"
  local extra=()
  local nested_extra=(--options runtime)
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    extra+=(--options runtime --timestamp --entitlements "$ENTITLEMENTS")
    nested_extra+=(--timestamp)
  else
    extra+=(--options runtime --entitlements "$ENTITLEMENTS")
  fi
  local sparkle="$APP/Contents/Frameworks/Sparkle.framework"
  if [[ -d "$sparkle" ]]; then
    local nested
    while IFS= read -r nested; do
      [[ -e "$nested" ]] || continue
      codesign --force --sign "$id" "${nested_extra[@]}" "$nested" >/dev/null
    done < <(/usr/bin/find "$sparkle" \( -name '*.xpc' -o -name '*.app' \) -depth)
    if [[ -f "$sparkle/Versions/Current/Autoupdate" ]]; then
      codesign --force --sign "$id" "${nested_extra[@]}" "$sparkle/Versions/Current/Autoupdate" >/dev/null
    fi
    codesign --force --sign "$id" "${nested_extra[@]}" "$sparkle"
  fi
  codesign --force --sign "$id" --identifier com.bioapple.ntfsmount.helperd "${extra[@]}" "$HELPERD"
  codesign --force --sign "$id" --identifier com.bioapple.ntfsmount.helper "${extra[@]}" "$APP/Contents/Resources/ntfs-rw-helper"
  codesign --force --sign "$id" \
    "$MACOS/libfuse.2.dylib" \
    "$MACOS/libntfs-3g.90.dylib" \
    "$MACOS/ntfs-3g" \
    "$MACOS/mkntfs" \
    "$MACOS/ntfsfix" \
    "$MACOS/go-nfsv4" >/dev/null
  codesign --force --sign "$id" --identifier com.bioapple.ntfsmount "${extra[@]}" "$BIN"
  codesign --force --sign "$id" --identifier com.bioapple.ntfsmount "${extra[@]}" "$APP"
}

sign
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  bash "$ROOT/scripts/notarize.sh" "$APP"
fi
echo "built $APP"
/bin/ls -lh "$MACOS"
