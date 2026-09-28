#!/bin/bash
# 完全卸载：应用 + 特权助手 + LaunchDaemon/Agent + 本机配置。不写 sudoers。
# 仅卸助手见 helper/uninstall-helper.sh。
# 必须以 root 运行（应用内「卸载助手」走 Authorization Services）。不调用 sudo。SIP 保持开启。
set -euo pipefail
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
LAUNCHCTL="$(resolve_cmd launchctl || true)"

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

  if [[ -n "$uid" && -n "${LAUNCHCTL:-}" ]]; then
    "$LAUNCHCTL" bootout "gui/${uid}/local.ntfsmount" >/dev/null 2>&1 || true
    "$LAUNCHCTL" bootout "user/${uid}/local.ntfsmount" >/dev/null 2>&1 || true
    "$LAUNCHCTL" bootout "gui/${uid}/com.bioapple.ntfsmount" >/dev/null 2>&1 || true
    "$LAUNCHCTL" bootout "user/${uid}/com.bioapple.ntfsmount" >/dev/null 2>&1 || true
  fi

  /bin/rm -f "${home}/Library/LaunchAgents/local.ntfsmount.plist"
  if [[ -d "${home}/Library/LaunchAgents" ]]; then
    /usr/bin/find "${home}/Library/LaunchAgents" -maxdepth 1 \( -iname '*ntfsmount*' \) ! -type d -delete 2>/dev/null || true
  fi

  /bin/rm -rf \
    "${home}/Library/Application Support/com.bioapple.ntfsmount" \
    "${home}/Library/Application Support/NTFSMount"

  if [[ "$(/usr/bin/id -u)" -eq 0 && -n "$uid" && -n "${LAUNCHCTL:-}" ]]; then
    "$LAUNCHCTL" asuser "$uid" /usr/bin/defaults delete com.bioapple.ntfsmount >/dev/null 2>&1 || true
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

/usr/bin/killall NTFSMount >/dev/null 2>&1 || true

if [[ "$(/usr/bin/id -u)" -ne 0 ]]; then
  echo "Root is required to remove the LaunchDaemon and the mount helper under /Library." >&2
  echo "In the app, choose Settings → Uninstall Helper (macOS Authorization Services), or run this script again from an already-privileged root shell." >&2
  echo "SIP stays enabled. This script does not call sudo." >&2
  clean_user_home "$HOME" "$(/usr/bin/id -u)"
  exit 1
fi

for label in "${SYSTEM_LABELS[@]}"; do
  if [[ -n "${LAUNCHCTL:-}" ]]; then
    "$LAUNCHCTL" bootout "system/${label}" >/dev/null 2>&1 || true
  fi
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

leftover=0
for label in "${SYSTEM_LABELS[@]}"; do
  if [[ -n "${LAUNCHCTL:-}" ]] && "$LAUNCHCTL" print "system/${label}" >/dev/null 2>&1; then
    echo "still in launchd: system/${label}"
    leftover=1
  fi
done
if [[ -e /var/run/com.bioapple.ntfsmount.sock ]]; then
  echo "socket still present: /var/run/com.bioapple.ntfsmount.sock"
  leftover=1
fi

echo "Uninstalled NTFSMount (app, mount helper, LaunchDaemon/Agent, and settings)."
echo "This script removes only NTFSMount and its own components. System FUSE-T / MacFUSE is left untouched."
echo "If you no longer need any NTFS read/write support, manually check and remove global libraries such as /usr/local/lib/libfuse.2.dylib."
echo "Logs were kept: ~/Library/Logs/ntfsmount.log (delete them yourself if you want)."
echo "SMAppService: if System Settings → General → Login Items & Extensions still lists NTFS read/write, turn it off."
echo "SIP stays enabled. This project does not use kernel extensions."

if [[ "$leftover" -ne 0 ]]; then
  echo "The daemon has not fully exited. Log out or restart, then confirm those labels are gone from launchd."
else
  echo "If the menu-bar icon is still there, log out or restart."
fi
