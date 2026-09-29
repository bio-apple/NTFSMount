#!/bin/bash
# 安装特权守护进程（LaunchDaemon + 签名钉扎）。必须以 root 运行。
# 用法: install-helper.sh <helper> <helperd> <用户名> <NTFSMount.app路径>
set -euo pipefail
# 不写死 /bin vs /usr/bin；不搜 PATH（root 下可被劫持）。
resolve_cmd() {
  local n="$1" p
  for p in "/bin/$n" "/usr/bin/$n" "/sbin/$n" "/usr/sbin/$n"; do
    if [[ -x "$p" ]]; then
      printf '%s\n' "$p"
      return 0
    fi
  done
  echo "error: command not found: $n" >&2
  return 1
}
LAUNCHCTL="$(resolve_cmd launchctl)"
BASH_BIN="$(resolve_cmd bash)"
if [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" != "1" && "$(/usr/bin/uname -m)" != "arm64" ]]; then
  echo "error: NTFSMount supports Apple Silicon (M-series / arm64) only, not Intel Macs (x86_64). This machine: $(/usr/bin/uname -m)" >&2
  exit 1
fi
if [[ "$(/usr/bin/id -u)" -ne 0 ]]; then
  echo "root is required" >&2
  exit 1
fi
HELPER_SRC="${1:?usage: install-helper.sh <helper> <helperd> <username> <app>}"
HELPERD_SRC="${2:?}"
USER_NAME="${3:?}"
APP="${4:?}"
SUPPORT="/Library/Application Support/NTFSMount"
HELPER_DST="$SUPPORT/ntfs-rw-helper"
HELPERD_DST="/Library/PrivilegedHelperTools/com.bioapple.ntfsmount.helperd"
PLIST="/Library/LaunchDaemons/com.bioapple.ntfsmount.helper.plist"
SUDOERS="/etc/sudoers.d/ntfs-rw"
LEGACY_HELPER="/usr/local/sbin/ntfs-rw-helper"

[[ -f "$HELPER_SRC" ]] || {
  echo "helper not found: $HELPER_SRC" >&2
  exit 1
}
[[ -f "$HELPERD_SRC" ]] || {
  echo "daemon not found: $HELPERD_SRC" >&2
  exit 1
}
[[ -d "$APP" ]] || {
  echo "app not found: $APP" >&2
  exit 1
}
if [[ "$USER_NAME" == "root" ]]; then
  USER_NAME="$(/usr/bin/stat -f '%Su' /dev/console)"
fi

APP="$(cd "$APP" && /bin/pwd -P)"
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
  echo "Cannot read the app CDHash. Sign the app, then install the helper again." >&2
  exit 1
fi
printf '%s\n' "$CDHASH" >"$SUPPORT/allowed.cdhash"
BUNDLE_VER="$(/usr/bin/defaults read "$APP/Contents/Info" CFBundleVersion 2>/dev/null || echo 0)"
HELPER_SHA="$(/usr/bin/shasum -a 256 "$HELPER_SRC" | /usr/bin/awk '{print $1}')"
printf '%s %s\n' "$BUNDLE_VER" "$HELPER_SHA" >"$SUPPORT/helper.stamp"
/usr/sbin/chown root:wheel "$SUPPORT/app.path" "$SUPPORT/allowed.cdhash" "$SUPPORT/helper.stamp"
/bin/chmod 644 "$SUPPORT/app.path" "$SUPPORT/allowed.cdhash" "$SUPPORT/helper.stamp"

/bin/cp "$HELPERD_SRC" "$SUPPORT/ntfsmount-helperd"
/usr/sbin/chown root:wheel "$SUPPORT/ntfsmount-helperd"
/bin/chmod 755 "$SUPPORT/ntfsmount-helperd"
# launchd 对 ad-hoc 的 Program 二进制常直接拒绝；job 用系统 bash 再 exec helperd。
/bin/cat >"$SUPPORT/run-helperd.sh" <<'RUN'
#!/bin/bash
echo "run-helperd: exec $(date -u +%Y-%m-%dT%H:%M:%SZ)" >&2
exec "/Library/Application Support/NTFSMount/ntfsmount-helperd"
RUN
/usr/sbin/chown root:wheel "$SUPPORT/run-helperd.sh"
/bin/chmod 755 "$SUPPORT/run-helperd.sh"
/usr/bin/xattr -cr "$HELPER_DST" "$HELPERD_DST" "$SUPPORT/ntfsmount-helperd" "$SUPPORT/run-helperd.sh" 2>/dev/null || true
# Hardened Runtime + ad-hoc 会被 AMFI 杀掉；安装时去掉 runtime 标志（仅 ad-hoc 源）。
if /usr/bin/codesign -dv "$SUPPORT/ntfsmount-helperd" 2>&1 | /usr/bin/grep -q 'Signature=adhoc'; then
  /usr/bin/codesign --force --sign - --identifier com.bioapple.ntfsmount.helperd \
    "$SUPPORT/ntfsmount-helperd" "$HELPERD_DST" >/dev/null
fi

SOCK="/var/run/com.bioapple.ntfsmount.sock"
"$LAUNCHCTL" bootout system/com.bioapple.ntfsmount.helper >/dev/null 2>&1 || true
"$LAUNCHCTL" unload "$PLIST" >/dev/null 2>&1 || true
/bin/rm -f "$SOCK"
/bin/sleep 0.3
cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.bioapple.ntfsmount.helper</string>
  <key>AssociatedBundleIdentifiers</key>
  <array>
    <string>com.bioapple.ntfsmount</string>
  </array>
  <key>Program</key>
  <string>${BASH_BIN}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${BASH_BIN}</string>
    <string>${SUPPORT}/run-helperd.sh</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/Library/Logs/ntfsmount-helperd.log</string>
  <key>StandardErrorPath</key>
  <string>/Library/Logs/ntfsmount-helperd.log</string>
</dict>
</plist>
EOF
/usr/sbin/chown root:wheel "$PLIST"
/bin/chmod 644 "$PLIST"
set +e
BOOT_ERR="$("$LAUNCHCTL" bootstrap system "$PLIST" 2>&1)"
BOOT_RC=$?
set -e
if [[ $BOOT_RC -ne 0 && -n "$BOOT_ERR" ]]; then
  echo "$BOOT_ERR" >&2
fi
"$LAUNCHCTL" enable system/com.bioapple.ntfsmount.helper >/dev/null 2>&1 || true
for _ in $(/usr/bin/seq 1 50); do
  "$LAUNCHCTL" kickstart -k system/com.bioapple.ntfsmount.helper >/dev/null 2>&1 || true
  if [[ -S "$SOCK" || -e "$SOCK" ]]; then
    break
  fi
  /bin/sleep 0.2
done

# 只清理旧版 sudoers / 符号链接，绝不写入 /etc/sudoers.d
/bin/rm -f "$SUDOERS" "$LEGACY_HELPER"

# 自动挂载已改为 app 侧（DiskWatch + 同一个挂载路径），不再需要 root 守护进程。
# 这里顺手卸掉旧版 LaunchDaemon：它是 root 进程，需要自己那份「完全磁盘访问」，
# 而且失败时每 ~50 秒重试一轮，会干扰 app 刚挂好的卷。
"$LAUNCHCTL" bootout system/com.bioapple.ntfsmount.automount >/dev/null 2>&1 || true
"$LAUNCHCTL" bootout system/local.ntfsmount.automount >/dev/null 2>&1 || true
/bin/rm -f /Library/LaunchDaemons/com.bioapple.ntfsmount.automount.plist \
  /Library/LaunchDaemons/local.ntfsmount.automount.plist

if [[ ! -S "$SOCK" && ! -e "$SOCK" ]]; then
  echo "error: helper files were copied, but the socket did not appear ($SOCK)." >&2
  echo "Allow NTFSMount to run in the background under System Settings → General → Login Items & Extensions, then try again." >&2
  "$LAUNCHCTL" print system/com.bioapple.ntfsmount.helper 2>&1 | /usr/bin/tail -n 40 >&2 || true
  if [[ -f /Library/Logs/ntfsmount-helperd.log ]]; then
    echo "--- helperd log ---" >&2
    /usr/bin/tail -n 20 /Library/Logs/ntfsmount-helperd.log >&2
  fi
  exit 1
fi

echo "ok helper daemon $HELPERD_DST"
