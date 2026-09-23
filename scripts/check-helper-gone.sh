#!/bin/bash
# 卸载助手后核对残留。无 root 时系统目录可能读不到，以「不存在」或「权限不足」记录。
set -euo pipefail
paths=(
  /var/run/com.bioapple.ntfsmount.sock
  /Library/LaunchDaemons/com.bioapple.ntfsmount.helper.plist
  /Library/LaunchDaemons/com.bioapple.ntfsmount.automount.plist
  /Library/LaunchDaemons/local.ntfsmount.automount.plist
  /Library/PrivilegedHelperTools/com.bioapple.ntfsmount.helperd
  "/Library/Application Support/NTFSMount"
  /etc/sudoers.d/ntfs-rw
  /usr/local/sbin/ntfs-rw-helper
)
fail=0
for p in "${paths[@]}"; do
  if [[ -e "$p" ]]; then
    echo "still present: $p" >&2
    fail=1
  else
    echo "gone: $p"
  fi
done
if [[ -e "$HOME/Library/Application Support/com.bioapple.ntfsmount" ]]; then
  echo "still present: $HOME/Library/Application Support/com.bioapple.ntfsmount" >&2
  fail=1
else
  echo "gone: $HOME/Library/Application Support/com.bioapple.ntfsmount"
fi
if [[ "$fail" -ne 0 ]]; then
  echo "helper leftovers remain" >&2
  exit 1
fi
echo "ok helper gone"
