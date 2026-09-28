#!/bin/bash
# 完全卸载：应用 + 特权助手 + LaunchDaemon/Agent + 配置 + 日志 + 本应用的隐私授权。
# 当前不是 root 时，先弹出管理员授权再继续。不写 sudoers，不调用 sudo。SIP 保持开启。
# 仅卸助手见 helper/uninstall-helper.sh。不卸载系统级 FUSE-T / MacFUSE。
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
    "${home}/Library/Application Support/NTFSMount" \
    "${home}/Library/Caches/com.bioapple.ntfsmount" \
    "${home}/Library/Saved Application State/com.bioapple.ntfsmount.savedState" \
    "${home}/Library/HTTPStorages/com.bioapple.ntfsmount" \
    "${home}/Library/WebKit/com.bioapple.ntfsmount"
  /bin/rm -f \
    "${home}/Library/Logs/ntfsmount.log" \
    "${home}/Library/Logs/ntfsmount.log.old"

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

# Not root: show the administrator dialog, then re-run this script with euid 0.
# bash -p keeps the privileged euid (a plain bash would drop back to the user).
request_admin_and_reexec() {
  local root src bin compiler bash
  root="$(cd "$(dirname "$0")" && pwd)"
  src="${root}/scripts/auth-run.c"
  if [[ ! -f "$src" ]]; then
    echo "Cannot ask for administrator authorization: missing ${src}" >&2
    return 1
  fi
  compiler="$(resolve_cmd clang || true)"
  if [[ -z "$compiler" ]]; then
    compiler="$(/usr/bin/xcrun --find clang 2>/dev/null || true)"
  fi
  if [[ -z "$compiler" || ! -x "$compiler" ]]; then
    echo "Administrator authorization needs clang, which was not found." >&2
    echo "Run this script again from an already-privileged root shell." >&2
    return 1
  fi
  bash="$(resolve_cmd bash)"
  bin="$(/usr/bin/mktemp /tmp/ntfsmount-uninstall.XXXXXX)"
  if ! "$compiler" -Wno-deprecated-declarations -framework Security -o "$bin" "$src"; then
    /bin/rm -f "$bin"
    echo "Could not build the administrator authorization helper." >&2
    return 1
  fi
  /bin/chmod 755 "$bin"
  # Run this file with bash -p. Executing the script path uses its shebang, and that
  # bash drops the privileged euid back to the logged-in user after the password dialog.
  exec "$bin" "$bash" -p -c \
    'exec 2>&1; export NTFSMOUNT_UNINSTALL_PRIV=1; exec "$1" -p "$2"' \
    bash "$bash" "$0"
}

if [[ "$(/usr/bin/id -u)" -ne 0 ]]; then
  if [[ "${NTFSMOUNT_UNINSTALL_PRIV:-}" == 1 ]]; then
    echo "Administrator authorization did not stay root. Uninstall stopped." >&2
    exit 1
  fi
  request_admin_and_reexec
  exit 1
fi

/usr/bin/killall NTFSMount >/dev/null 2>&1 || true
/usr/bin/killall ntfsmount-helperd >/dev/null 2>&1 || true

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
/bin/rm -f /tmp/ntfsmount.log

if [[ -x /usr/bin/tccutil ]]; then
  /usr/bin/tccutil reset All com.bioapple.ntfsmount >/dev/null 2>&1 || true
fi

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

echo "Uninstalled NTFSMount (app, mount helper, LaunchDaemon/Agent, settings, logs, and privacy grants)."
echo "This script removes only NTFSMount and its own components. System FUSE-T / MacFUSE is left untouched."
echo "If you no longer need any NTFS read/write support, manually check and remove global libraries such as /usr/local/lib/libfuse.2.dylib."
echo "SMAppService: if System Settings → General → Login Items & Extensions still lists NTFS read/write, turn it off."
echo "SIP stays enabled. This project does not use kernel extensions."

if [[ "$leftover" -ne 0 ]]; then
  echo "The daemon has not fully exited. Log out or restart, then confirm those labels are gone from launchd."
else
  echo "If the menu-bar icon is still there, log out or restart."
fi
