#!/bin/bash
# 安装特权守护进程（LaunchDaemon + 签名钉扎）。必须以 root 运行。
# 用法: install-helper.sh <helper> <helperd> <用户名> <NTFSMount.app路径>
set -euo pipefail
if [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" != "1" && "$(/usr/bin/uname -m)" != "arm64" ]]; then
  echo "error: NTFSMount 仅支持 Apple Silicon（M 芯片 / arm64），不支持 Intel Mac（x86_64）。当前架构：$(/usr/bin/uname -m)" >&2
  exit 1
fi
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
CDHASH="$(/usr/bin/codesign -dv --verbose=4 "$APP" 2>&1 | /usr/bin/sed -n 's/^CDHash=//p' | /usr/bin/head -1 || true)"
if [[ -z "$CDHASH" ]]; then
  echo "无法读取应用 CDHash，请确认应用已签名后再安装助手。" >&2
  exit 1
fi
printf '%s\n' "$CDHASH" >"$SUPPORT/allowed.cdhash"
BUNDLE_VER="$(/usr/bin/defaults read "$APP/Contents/Info" CFBundleVersion 2>/dev/null || echo 0)"
HELPER_SHA="$(/usr/bin/shasum -a 256 "$HELPER_SRC" | /usr/bin/awk '{print $1}')"
printf '%s %s\n' "$BUNDLE_VER" "$HELPER_SHA" >"$SUPPORT/helper.stamp"
/usr/sbin/chown root:wheel "$SUPPORT/app.path" "$SUPPORT/allowed.cdhash" "$SUPPORT/helper.stamp"
/bin/chmod 644 "$SUPPORT/app.path" "$SUPPORT/allowed.cdhash" "$SUPPORT/helper.stamp"

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
SOCK="/var/run/com.bioapple.ntfsmount.sock"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
  /usr/bin/launchctl kickstart -k system/com.bioapple.ntfsmount.helper >/dev/null 2>&1 || true
  if [[ -S "$SOCK" || -e "$SOCK" ]]; then
    break
  fi
  /bin/sleep 0.1
done

# 只清理旧版 sudoers / 符号链接，绝不写入 /etc/sudoers.d
/bin/rm -f "$SUDOERS" "$LEGACY_HELPER"

echo "ok helper daemon $HELPERD_DST"
