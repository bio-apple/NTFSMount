#!/bin/bash
# 用管理员权限：修正 sudo 规则给登录用户，并尝试把当前 NTFS 盘挂成可写。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
USER_NAME="$(/usr/bin/stat -f '%Su' /dev/console)"
HELPER_SRC="$ROOT/helper/ntfs-rw-helper"
HELPER_DST="/usr/local/sbin/ntfs-rw-helper"
SUDOERS="/etc/sudoers.d/ntfs-rw"

/bin/mkdir -p /usr/local/sbin
/bin/cp "$HELPER_SRC" "$HELPER_DST"
/usr/sbin/chown root:wheel "$HELPER_DST"
/bin/chmod 755 "$HELPER_DST"

if ! /usr/bin/grep -Eq '^[#@]includedir[[:space:]]+/((private/)?etc/sudoers\.d)$' /etc/sudoers; then
  printf '\n#includedir /etc/sudoers.d\n' >> /etc/sudoers
fi

TMP="$(mktemp)"
cat > "$TMP" <<EOF
Defaults!${HELPER_DST} !requiretty
${USER_NAME} ALL=(root) NOPASSWD: ${HELPER_DST}, ${HELPER_DST} *
EOF
/usr/sbin/visudo -c -f "$TMP" >/dev/null
/bin/cp "$TMP" "$SUDOERS"
/bin/chmod 440 "$SUDOERS"
/bin/rm -f "$TMP"

IDENT=""
while read -r ident; do
  fs="$(/usr/sbin/diskutil info -plist "$ident" 2>/dev/null | /usr/bin/plutil -extract FilesystemName raw - 2>/dev/null || true)"
  if [[ "$fs" == "NTFS" ]]; then
    IDENT="$ident"
    break
  fi
done < <(/usr/sbin/diskutil list | /usr/bin/awk '/disk[0-9]+s[0-9]+/ { print $NF }')
if [[ "$IDENT" =~ ^disk[0-9]+s[0-9]+$ ]]; then
  "$HELPER_DST" mount "$IDENT"
else
  echo "ok helper-installed (no NTFS disk found)"
fi
