#!/bin/bash
# 安装特权守护进程（LaunchDaemon + 签名钉扎）。必须以 root 运行。
# 用法: install-helper.sh <helper> <helperd> <用户名> <NTFSMount.app路径>
set -euo pipefail
if [[ "$(/usr/bin/id -u)" -ne 0 ]]; then
  echo "需要 root" >&2
  exit 1
fi
HELPER_SRC="${1:?用法: install-helper.sh <helper> <helperd> <用户名> <app>}"
HELPERD_SRC="${2:?}"
USER_NAME="${3:?}"
APP="${4:?}"
SUPPORT="/Library/Application Support/NTFSMount"
HELPER_DST="$SUPPORT/ntfs-rw-helper"
HELPERD_DST="/Library/PrivilegedHelperTools/com.bioapple.ntfsmount.helperd"
PLIST="/Library/LaunchDaemons/com.bioapple.ntfsmount.helper.plist"
SUDOERS="/etc/sudoers.d/ntfs-rw"
LEGACY_HELPER="/usr/local/sbin/ntfs-rw-helper"

[[ -f "$HELPER_SRC" ]] || { echo "找不到助手: $HELPER_SRC" >&2; exit 1; }
[[ -f "$HELPERD_SRC" ]] || { echo "找不到守护进程: $HELPERD_SRC" >&2; exit 1; }
[[ -d "$APP" ]] || { echo "找不到应用: $APP" >&2; exit 1; }
if [[ "$USER_NAME" == "root" ]]; then
  USER_NAME="$(/usr/bin/stat -f '%Su' /dev/console)"
fi

APP="$(/usr/bin/realpath "$APP")"
/bin/mkdir -p "$SUPPORT" /Library/PrivilegedHelperTools

/bin/cp "$HELPER_SRC" "$HELPER_DST"
/usr/sbin/chown root:wheel "$HELPER_DST"
/bin/chmod 755 "$HELPER_DST"

/bin/cp "$HELPERD_SRC" "$HELPERD_DST"
/usr/sbin/chown root:wheel "$HELPERD_DST"
/bin/chmod 755 "$HELPERD_DST"

printf '%s\n' "$APP" >"$SUPPORT/app.path"
/bin/chmod 644 "$SUPPORT/app.path"
CDHASH="$(/usr/bin/codesign -dv --verbose=4 "$APP" 2>&1 | /usr/bin/sed -n 's/^CDHash=//p' | /usr/bin/head -1 || true)"
printf '%s\n' "$CDHASH" >"$SUPPORT/allowed.cdhash"
/bin/chmod 644 "$SUPPORT/allowed.cdhash"
BUNDLE_VER="$(/usr/bin/defaults read "$APP/Contents/Info" CFBundleVersion 2>/dev/null || echo 0)"
HELPER_SHA="$(/usr/bin/shasum -a 256 "$HELPER_SRC" | /usr/bin/awk '{print $1}')"
printf '%s %s\n' "$BUNDLE_VER" "$HELPER_SHA" >"$SUPPORT/helper.stamp"
/bin/chmod 644 "$SUPPORT/helper.stamp"

/usr/bin/launchctl bootout system/com.bioapple.ntfsmount.helper >/dev/null 2>&1 || true
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.bioapple.ntfsmount.helper</string>
  <key>ProgramArguments</key>
  <array>
    <string>${HELPERD_DST}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
</dict>
</plist>
EOF
/usr/sbin/chown root:wheel "$PLIST"
/bin/chmod 644 "$PLIST"
/usr/bin/launchctl bootstrap system "$PLIST" || true
/usr/bin/launchctl kickstart -k system/com.bioapple.ntfsmount.helper >/dev/null 2>&1 || true

# 只清理旧版 sudoers / 符号链接，绝不写入 /etc/sudoers.d
/bin/rm -f "$SUDOERS" "$LEGACY_HELPER"

echo "ok helper daemon $HELPERD_DST"
