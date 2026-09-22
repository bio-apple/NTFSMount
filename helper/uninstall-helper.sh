#!/bin/bash
# 只卸特权助手 / 守护进程 / 残留 sudo 规则 / 自动挂载，不删除应用。
set -euo pipefail
if [[ "$(/usr/bin/id -u)" -ne 0 ]]; then
  echo "需要 root" >&2
  exit 1
fi
/usr/bin/launchctl bootout system/com.bioapple.ntfsmount.helper >/dev/null 2>&1 || true
/usr/bin/launchctl bootout system/com.bioapple.ntfsmount.automount >/dev/null 2>&1 || true
/usr/bin/launchctl bootout system/local.ntfsmount.automount >/dev/null 2>&1 || true
/bin/rm -f /var/run/com.bioapple.ntfsmount.sock \
  /usr/local/sbin/ntfs-rw-helper \
  /etc/sudoers.d/ntfs-rw \
  /Library/PrivilegedHelperTools/com.bioapple.ntfsmount.helperd \
  /Library/LaunchDaemons/com.bioapple.ntfsmount.helper.plist \
  /Library/LaunchDaemons/com.bioapple.ntfsmount.automount.plist \
  /Library/LaunchDaemons/local.ntfsmount.automount.plist
/bin/rm -rf "/Library/Application Support/NTFSMount"
echo "ok helper uninstalled"
