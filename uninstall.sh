#!/bin/bash
# 完全卸载：应用 + 特权助手 + LaunchDaemon/Agent + 本机配置。不写 sudoers。
# 仅卸助手见 helper/uninstall-helper.sh。
set -euo pipefail

SYSTEM_LABELS=(
  com.bioapple.ntfsmount.helper
  com.bioapple.ntfsmount.automount
  local.ntfsmount.automount
)

# 用户目录残留（幂等）。uid 用于 bootout gui/user 域；空则只删文件。
clean_user_home() {
  local home="$1"
  local uid="${2:-}"
  [[ -n "$home" && -d "$home" ]] || return 0

  if [[ -n "$uid" ]]; then
    /usr/bin/launchctl bootout "gui/${uid}/local.ntfsmount" >/dev/null 2>&1 || true
    /usr/bin/launchctl bootout "user/${uid}/local.ntfsmount" >/dev/null 2>&1 || true
    /usr/bin/launchctl bootout "gui/${uid}/com.bioapple.ntfsmount" >/dev/null 2>&1 || true
    /usr/bin/launchctl bootout "user/${uid}/com.bioapple.ntfsmount" >/dev/null 2>&1 || true
  fi

  /bin/rm -f "${home}/Library/LaunchAgents/local.ntfsmount.plist"
  if [[ -d "${home}/Library/LaunchAgents" ]]; then
    /usr/bin/find "${home}/Library/LaunchAgents" -maxdepth 1 \( -iname '*ntfsmount*' \) ! -type d -delete 2>/dev/null || true
  fi

  /bin/rm -rf \
    "${home}/Library/Application Support/com.bioapple.ntfsmount" \
    "${home}/Library/Application Support/NTFSMount"

  if [[ "$(/usr/bin/id -u)" -eq 0 && -n "$uid" ]]; then
    /usr/bin/launchctl asuser "$uid" /usr/bin/defaults delete com.bioapple.ntfsmount >/dev/null 2>&1 || true
  else
    /usr/bin/defaults delete com.bioapple.ntfsmount >/dev/null 2>&1 || true
  fi
  /bin/rm -f "${home}/Library/Preferences/com.bioapple.ntfsmount.plist"
}

clean_named_user() {
  local name="$1"
  [[ -n "$name" && "$name" != "root" ]] || return 0
  local home uid
  home="$(/usr/bin/dscl . -read "/Users/${name}" NFSHomeDirectory 2>/dev/null | /usr/bin/awk '{print $2}')"
  uid="$(/usr/bin/id -u "$name" 2>/dev/null || true)"
  [[ -n "$home" && "$home" == /Users/* ]] || return 0
  clean_user_home "$home" "${uid:-}"
}

/usr/bin/osascript -e 'quit app "NTFS 读写"' 2>/dev/null || true
/usr/bin/osascript -e 'quit app "NTFSMount"' 2>/dev/null || true

if [[ "$(/usr/bin/id -u)" -ne 0 ]]; then
  SCRIPT="$(/usr/bin/realpath "$0")"
  /usr/bin/osascript - "$SCRIPT" <<'APPLESCRIPT'
on run argv
  do shell script quoted form of (item 1 of argv) with administrator privileges
end run
APPLESCRIPT
  clean_user_home "$HOME" "$(/usr/bin/id -u)"
  exit 0
fi

for label in "${SYSTEM_LABELS[@]}"; do
  /usr/bin/launchctl bootout "system/${label}" >/dev/null 2>&1 || true
done

/bin/rm -f \
  /var/run/com.bioapple.ntfsmount.sock \
  /usr/local/sbin/ntfs-rw-helper \
  /etc/sudoers.d/ntfs-rw \
  /Library/PrivilegedHelperTools/com.bioapple.ntfsmount.helperd \
  /Library/LaunchDaemons/com.bioapple.ntfsmount.helper.plist \
  /Library/LaunchDaemons/com.bioapple.ntfsmount.automount.plist \
  /Library/LaunchDaemons/local.ntfsmount.automount.plist

/bin/rm -rf "/Library/Application Support/NTFSMount" /Applications/NTFSMount.app

clean_named_user "$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null || true)"
clean_named_user "${SUDO_USER:-}"

leftover=0
for label in "${SYSTEM_LABELS[@]}"; do
  if /usr/bin/launchctl print "system/${label}" >/dev/null 2>&1; then
    echo "仍在 launchd：system/${label}"
    leftover=1
  fi
done
if [[ -e /var/run/com.bioapple.ntfsmount.sock ]]; then
  echo "仍有 socket：/var/run/com.bioapple.ntfsmount.sock"
  leftover=1
fi

echo "已卸载 NTFSMount（应用 + 挂载助手 + LaunchDaemon/Agent + 配置）。"
echo "本脚本仅移除 NTFSMount 及其专属组件。系统级 FUSE-T / MacFUSE 不会被触碰。"
echo "如果您不再需要任何 NTFS 读写功能，请手动检查并移除 /usr/local/lib/libfuse.2.dylib 等全局依赖。"
echo "未删除日志：~/Library/Logs/ntfsmount.log（可自行删）。"
echo "SMAppService：若「系统设置 → 通用 → 登录项与后台项目」里仍有 NTFS 读写，请关掉。"

if [[ "$leftover" -ne 0 ]]; then
  echo "守护进程未完全退出。请执行："
  echo "  sudo launchctl bootout system/com.bioapple.ntfsmount.helper"
  echo "  sudo launchctl bootout system/com.bioapple.ntfsmount.automount"
  echo "  sudo launchctl bootout system/local.ntfsmount.automount"
  echo "若 socket 或 launchctl 仍列出上述标签，请注销或重启。"
else
  echo "若菜单栏图标仍在，注销或重启即可。"
fi
