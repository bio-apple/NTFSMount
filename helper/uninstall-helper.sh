#!/bin/bash
# 只卸特权助手 / sudo 规则 / 自动挂载守护进程，不删除应用。
set -euo pipefail
if [[ "$(/usr/bin/id -u)" -ne 0 ]]; then
  echo "需要 root" >&2
  exit 1
fi
/usr/bin/launchctl bootout system/com.bioapple.ntfsmount.automount >/dev/null 2>&1 || true
/usr/bin/launchctl bootout system/local.ntfsmount.automount >/dev/null 2>&1 || true
/bin/rm -f /usr/local/sbin/ntfs-rw-helper \
  /etc/sudoers.d/ntfs-rw \
  /Library/LaunchDaemons/com.bioapple.ntfsmount.automount.plist \
  /Library/LaunchDaemons/local.ntfsmount.automount.plist
echo "ok helper uninstalled"
