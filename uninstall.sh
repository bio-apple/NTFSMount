#!/bin/bash
set -euo pipefail
osascript -e 'quit app "NTFS 读写"' 2>/dev/null || true
osascript -e 'quit app "NTFSMount"' 2>/dev/null || true
sudo /usr/bin/launchctl bootout system/com.bioapple.ntfsmount.automount >/dev/null 2>&1 || true
sudo /usr/bin/launchctl bootout system/local.ntfsmount.automount >/dev/null 2>&1 || true
sudo rm -f /usr/local/sbin/ntfs-rw-helper /etc/sudoers.d/ntfs-rw \
  /Library/LaunchDaemons/com.bioapple.ntfsmount.automount.plist \
  /Library/LaunchDaemons/local.ntfsmount.automount.plist
sudo rm -rf /Applications/NTFSMount.app
rm -rf "$HOME/Library/LaunchAgents/local.ntfsmount.plist"
echo "已卸载 NTFS 读写（助手 + 应用；系统里若另装过 FUSE-T 不会自动删除）。"
