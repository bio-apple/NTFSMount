#!/bin/bash
# Build a double-click DMG: drag NTFSMount.app into Applications.
set -euo pipefail
if [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" != "1" && "$(/usr/bin/uname -m)" != "arm64" ]]; then
  echo "error: NTFSMount supports Apple Silicon (M-series / arm64) only, not Intel Macs (x86_64). This machine: $(/usr/bin/uname -m)" >&2
  exit 1
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/dist/NTFSMount.dmg}"
VOLNAME="NTFSMount"

echo "==> Building NTFSMount.app"
bash "$ROOT/scripts/build.sh"
APP_SRC="$ROOT/dist/NTFSMount.app"
if [[ ! -d "$APP_SRC" && -d /tmp/NTFSMount.app ]]; then
  APP_SRC="/tmp/NTFSMount.app"
fi
[[ -d "$APP_SRC" ]] || {
  echo "error: NTFSMount.app not found" >&2
  exit 1
}

STAGE="$(/usr/bin/mktemp -d /tmp/ntfsmount-dmg.XXXXXX)"
RW="$(/usr/bin/mktemp /tmp/ntfsmount-rw.XXXXXX).dmg"
MNT=""
cleanup() {
  if [[ -n "$MNT" && -d "$MNT" ]]; then
    /usr/bin/hdiutil detach "$MNT" -quiet >/dev/null 2>&1 || true
  fi
  /bin/rm -rf "$STAGE"
  /bin/rm -f "$RW"
}
trap cleanup EXIT

/bin/cp -R "$APP_SRC" "$STAGE/NTFSMount.app"
/bin/ln -s /Applications "$STAGE/Applications"
/bin/cp "$ROOT/LICENSE" "$STAGE/LICENSE"
/bin/cp "$ROOT/NOTICE" "$STAGE/NOTICE"
/bin/cp "$ROOT/THIRD_PARTY_LICENSES.md" "$STAGE/THIRD_PARTY_LICENSES.md"
/bin/cp "$ROOT/docs/DISTRIBUTION.md" "$STAGE/DISTRIBUTION.md"
printf '%s\n' "Source: https://github.com/bio-apple/NTFSMount" >"$STAGE/Source.txt"
/bin/cat >"$STAGE/Read Me.txt" <<'EOF'
NTFSMount v1.0.0
Direct download, not Mac App Store. Personal-use pre-release, not notarized.

Apple Silicon (M-series) and macOS 13.0+ only. Intel Macs are not supported.

Install
1. Drag NTFSMount to Applications on the right
2. Menu bar shows NTFS. Closing the window keeps the icon; Quit from the Dock to exit
3. Hover the menu-bar icon for disk status; you do not need the window
4. First launch: one confirmation. Return = Agree and Continue, Esc = Quit
5. After you agree, the app installs the mount helper. Unnotarized builds ask for an admin password
6. If macOS cannot verify the developer: Control-click → Open; or System Settings → Privacy & Security → Open Anyway. Still quarantined:
   xattr -d com.apple.quarantine /Applications/NTFSMount.app

Read / write
1. Plug in an external NTFS disk. The first writable mount asks you to confirm a backup
2. Submenu: Mount Writable. Built-in / Boot Camp volumes are not auto-mounted
3. When done, Eject (safe to unplug) and wait until the volume disappears
4. Auto-mount, login, Dock, helper: window Settings. This build is not notarized; download updates from GitHub Releases

Format
Root menu: Erase Disk as NTFS… (not in each volume submenu). You must type the current volume name. Return defaults to Cancel. Built-in disks cannot be formatted.

Remove helper: Settings → Remove Helper
Full uninstall: repo ./uninstall.sh (NTFSMount only; does not touch system FUSE-T / MacFUSE)
EOF

if [[ "${FUSE_T_REDISTRIBUTION_OK:-}" != "1" ]]; then
  /bin/cat >"$STAGE/Personal Use.txt" <<'EOF'
This package is for personal use only. Apple Silicon (M-series) and macOS 13.0+ only; Intel Macs (x86_64) are not supported.

Bundled FUSE-T go-nfsv4 is not GPL. Before embedding, redistributing, or selling as a product, get a license from FUSE-T:
https://www.fuse-t.org/

Unnotarized builds are blocked by Gatekeeper. Control-click the app → Open; or System Settings → Privacy & Security → Open Anyway. Notarize with Developer ID before giving this to others.
See DISTRIBUTION.md and THIRD_PARTY_LICENSES.md.
EOF
fi

SIZE_MB="$(/usr/bin/du -sm "$STAGE" | /usr/bin/awk '{print int($1)+30}')"
echo "==> Creating disk image (${SIZE_MB} MB)"
/usr/bin/hdiutil create -ov -quiet -fs HFS+ -volname "$VOLNAME" -size "${SIZE_MB}m" "$RW" >/dev/null

ATTACH="$(/usr/bin/hdiutil attach -readwrite -noverify -noautoopen "$RW")"
MNT="$(printf '%s\n' "$ATTACH" | /usr/bin/awk -F'\t' '/\/Volumes\//{print $NF; exit}')"
[[ -d "$MNT" ]] || {
  echo "error: failed to attach temporary DMG" >&2
  exit 1
}

/bin/cp -R "$STAGE/NTFSMount.app" "$MNT/NTFSMount.app"
/bin/ln -s /Applications "$MNT/Applications"
/bin/cp "$STAGE/Read Me.txt" "$MNT/Read Me.txt"
/bin/cp "$STAGE/LICENSE" "$MNT/LICENSE"
/bin/cp "$STAGE/NOTICE" "$MNT/NOTICE"
/bin/cp "$STAGE/THIRD_PARTY_LICENSES.md" "$MNT/THIRD_PARTY_LICENSES.md"
/bin/cp "$STAGE/DISTRIBUTION.md" "$MNT/DISTRIBUTION.md"
/bin/cp "$STAGE/Source.txt" "$MNT/Source.txt"
if [[ -f "$STAGE/Personal Use.txt" ]]; then
  /bin/cp "$STAGE/Personal Use.txt" "$MNT/Personal Use.txt"
fi

# Common installer window: app on the left, Applications on the right
/usr/bin/osascript <<EOF
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {280, 160, 920, 600}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 96
    set position of item "NTFSMount.app" of container window to {160, 140}
    set position of item "Applications" of container window to {480, 140}
    set position of item "Read Me.txt" of container window to {160, 320}
    set position of item "LICENSE" of container window to {320, 320}
    set position of item "Source.txt" of container window to {480, 320}
    update without registering applications
    delay 1
    close
    open
    delay 1
  end tell
end tell
EOF

# Write the volume icon after Finder layout so conversion keeps the invisible file
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  /bin/cp "$ROOT/Resources/AppIcon.icns" "$MNT/.VolumeIcon.icns"
  /usr/bin/SetFile -c icnC "$MNT/.VolumeIcon.icns"
  /usr/bin/SetFile -a C "$MNT"
  [[ -f "$MNT/.VolumeIcon.icns" ]] || {
    echo "error: failed to write .VolumeIcon.icns" >&2
    exit 1
  }
fi

sync
/usr/bin/hdiutil detach "$MNT" -quiet
MNT=""

mkdir -p "$(/usr/bin/dirname "$OUT")"
/bin/rm -f "$OUT"
echo "==> Compressing $OUT"
/usr/bin/hdiutil convert "$RW" -quiet -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null

echo "ok $OUT"
/bin/ls -lh "$OUT"
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  bash "$ROOT/scripts/notarize.sh" "$OUT" || echo "warning: DMG notarize/staple failed (app still usable if already notarized)" >&2
fi
# staple rewrites the DMG; hash last
bash "$ROOT/scripts/write-dmg-sha256.sh" "$OUT"
if [[ "${FUSE_T_REDISTRIBUTION_OK:-}" != "1" ]]; then
  echo "note: FUSE_T_REDISTRIBUTION_OK unset; DMG is personal-use only" >&2
fi
