#!/bin/bash
# Build an installer package that places NTFSMount.app in /Applications.
set -euo pipefail
if [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" != "1" && "$(/usr/bin/uname -m)" != "arm64" ]]; then
  echo "error: NTFSMount supports Apple Silicon (M-series / arm64) only, not Intel Macs (x86_64). This machine: $(/usr/bin/uname -m)" >&2
  exit 1
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/dist/NTFSMount.pkg}"

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

VER="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$APP_SRC/Contents/Info.plist" 2>/dev/null || true)"
VER="$(printf '%s' "${VER:-1.0}" | /usr/bin/tr -d '[:space:]')"
[[ -n "$VER" ]] || VER="1.0"

STAGE="$(/usr/bin/mktemp -d /tmp/ntfsmount-pkg.XXXXXX)"
cleanup() {
  /bin/rm -rf "$STAGE"
}
trap cleanup EXIT

/bin/mkdir -p "$STAGE/root" "$STAGE/resources"
/bin/cp -R "$APP_SRC" "$STAGE/root/NTFSMount.app"
/bin/cp "$ROOT/LICENSE" "$STAGE/resources/license.txt"

/bin/cat >"$STAGE/resources/welcome.txt" <<'EOF'
NTFSMount
Direct download, not Mac App Store. Personal-use pre-release, not notarized.

Apple Silicon (M-series) and macOS 13.0+ only. Intel Macs are not supported.

This installer puts NTFSMount.app in /Applications and installs the mount helper before it finishes. The installer's administrator authorization is used once. No second password prompt.
EOF
if [[ "${FUSE_T_REDISTRIBUTION_OK:-}" != "1" ]]; then
  /bin/cat >>"$STAGE/resources/welcome.txt" <<'EOF'

This package is for personal use only. Bundled FUSE-T go-nfsv4 is not GPL. Before embedding, redistributing, or selling as a product, get a license from FUSE-T:
https://www.fuse-t.org/
EOF
fi

/bin/cat >"$STAGE/resources/readme.txt" <<EOF
NTFSMount v${VER}
Direct download, not Mac App Store. Personal-use pre-release, not notarized.

Apple Silicon (M-series) and macOS 13.0+ only. Intel Macs are not supported.

Install
1. Continue. The installer copies NTFSMount into Applications and installs the mount helper
2. Menu bar shows NTFS. Closing the window keeps the icon; Quit from the Dock to exit
3. Hover the menu-bar icon for disk status; you do not need the window
4. First launch: one confirmation. Return = Agree and Continue, Esc = Quit
5. If macOS cannot verify the developer: Control-click the package or the app → Open; or System Settings → Privacy & Security → Open Anyway. Still quarantined:
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

/bin/cat >"$STAGE/component.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
  <dict>
    <key>BundleHasStrictIdentifier</key>
    <true/>
    <key>BundleIsRelocatable</key>
    <false/>
    <key>BundleIsVersionChecked</key>
    <true/>
    <key>BundleOverwriteAction</key>
    <string>upgrade</string>
    <key>RootRelativeBundlePath</key>
    <string>NTFSMount.app</string>
  </dict>
</array>
</plist>
EOF

/bin/mkdir -p "$STAGE/scripts"
/bin/cp "$ROOT/scripts/pkg-postinstall.sh" "$STAGE/scripts/postinstall"
/bin/chmod 755 "$STAGE/scripts/postinstall"

echo "==> Creating component package"
/usr/bin/pkgbuild \
  --root "$STAGE/root" \
  --component-plist "$STAGE/component.plist" \
  --scripts "$STAGE/scripts" \
  --identifier com.bioapple.ntfsmount.pkg \
  --version "$VER" \
  --install-location /Applications \
  "$STAGE/NTFSMount-component.pkg" >/dev/null

/bin/cat >"$STAGE/distribution.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>NTFSMount</title>
  <welcome file="welcome.txt" mime-type="text/plain"/>
  <readme file="readme.txt" mime-type="text/plain"/>
  <license file="license.txt" mime-type="text/plain"/>
  <options customize="never" require-scripts="true" hostArchitectures="arm64"/>
  <domains enable_localSystem="true"/>
  <volume-check>
    <allowed-os-versions>
      <os-version min="13.0"/>
    </allowed-os-versions>
  </volume-check>
  <choices-outline>
    <line choice="default">
      <line choice="com.bioapple.ntfsmount.pkg"/>
    </line>
  </choices-outline>
  <choice id="default"/>
  <choice id="com.bioapple.ntfsmount.pkg" visible="false">
    <pkg-ref id="com.bioapple.ntfsmount.pkg"/>
  </choice>
  <pkg-ref id="com.bioapple.ntfsmount.pkg" version="${VER}" onConclusion="none">NTFSMount-component.pkg</pkg-ref>
</installer-gui-script>
EOF

mkdir -p "$(/usr/bin/dirname "$OUT")"
UNSIGNED="$STAGE/NTFSMount-unsigned.pkg"
echo "==> Creating $OUT"
/usr/bin/productbuild \
  --distribution "$STAGE/distribution.xml" \
  --package-path "$STAGE" \
  --resources "$STAGE/resources" \
  "$UNSIGNED" >/dev/null

if [[ -n "${INSTALLER_IDENTITY:-}" ]]; then
  /usr/bin/productsign --sign "$INSTALLER_IDENTITY" "$UNSIGNED" "$OUT"
  if [[ -n "${NOTARY_PROFILE:-}" || -n "${APPLE_API_KEY_ID:-}" ]]; then
    bash "$ROOT/scripts/notarize.sh" "$OUT" || echo "warning: package notarize/staple failed (app still usable if already notarized)" >&2
  fi
else
  /bin/mv -f "$UNSIGNED" "$OUT"
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    echo "warning: Developer ID Application does not sign installer packages. Set INSTALLER_IDENTITY to a Developer ID Installer certificate to sign and notarize the pkg." >&2
  fi
fi

echo "ok $OUT"
/bin/ls -lh "$OUT"
# staple rewrites a signed package; hash last
bash "$ROOT/scripts/write-pkg-sha256.sh" "$OUT"
/bin/rm -f \
  "$ROOT/dist/NTFSMount.dmg" \
  "$ROOT/dist/NTFSMount.dmg.sha256" \
  "$ROOT/dist/NTFSMount.dmg.release-notes.md"
if [[ "${FUSE_T_REDISTRIBUTION_OK:-}" != "1" ]]; then
  echo "note: FUSE_T_REDISTRIBUTION_OK unset; package is personal-use only" >&2
fi
