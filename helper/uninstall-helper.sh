#!/bin/bash
# 卸特权助手 / 守护进程 / 残留 sudoers / 自动挂载，不删除应用。不写 sudoers。
set -euo pipefail
resolve_cmd() {
  local n="$1" p
  for p in "/bin/$n" "/usr/bin/$n" "/sbin/$n" "/usr/sbin/$n"; do
    if [[ -x "$p" ]]; then
      printf '%s\n' "$p"
      return 0
    fi
  done
  echo "error: 找不到命令 $n" >&2
  return 1
}
LAUNCHCTL="$(resolve_cmd launchctl || true)"
if [[ "$(/usr/bin/id -u)" -ne 0 ]]; then
  echo "需要 root" >&2
  exit 1
fi
if [[ -n "$LAUNCHCTL" ]]; then
  "$LAUNCHCTL" bootout system/com.bioapple.ntfsmount.helper >/dev/null 2>&1 || true
  "$LAUNCHCTL" bootout system/com.bioapple.ntfsmount.automount >/dev/null 2>&1 || true
  "$LAUNCHCTL" bootout system/local.ntfsmount.automount >/dev/null 2>&1 || true
fi
/bin/rm -f /var/run/com.bioapple.ntfsmount.sock \
  /usr/local/sbin/ntfs-rw-helper \
  /etc/sudoers.d/ntfs-rw \
  /Library/PrivilegedHelperTools/com.bioapple.ntfsmount.helperd \
  /Library/LaunchDaemons/com.bioapple.ntfsmount.helper.plist \
  /Library/LaunchDaemons/com.bioapple.ntfsmount.automount.plist \
  /Library/LaunchDaemons/local.ntfsmount.automount.plist
/bin/rm -rf "/Library/Application Support/NTFSMount"
USER_NAME="$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null || true)"
if [[ -n "$USER_NAME" && "$USER_NAME" != "root" ]]; then
  USER_HOME="$(/usr/bin/dscl . -read "/Users/${USER_NAME}" NFSHomeDirectory 2>/dev/null | /usr/bin/awk '{print $2}')"
  if [[ -n "$USER_HOME" && "$USER_HOME" == /Users/* ]]; then
    /bin/rm -rf "${USER_HOME}/Library/Application Support/com.bioapple.ntfsmount"
  fi
fi
echo "ok helper uninstalled"
