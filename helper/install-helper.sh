#!/bin/bash
# 安装 /usr/local/sbin/ntfs-rw-helper 和对应 sudo 规则。必须以 root 运行。
# 用法: install-helper.sh <helper源路径> <允许免密的用户名>
set -euo pipefail
if [[ "$(/usr/bin/id -u)" -ne 0 ]]; then
  echo "需要 root" >&2
  exit 1
fi
HELPER_SRC="${1:?用法: install-helper.sh <helper源路径> <用户名>}"
USER_NAME="${2:?用法: install-helper.sh <helper源路径> <用户名>}"
HELPER_DST="/usr/local/sbin/ntfs-rw-helper"
SUDOERS="/etc/sudoers.d/ntfs-rw"

[[ -f "$HELPER_SRC" ]] || { echo "找不到助手: $HELPER_SRC" >&2; exit 1; }
if [[ "$USER_NAME" == "root" ]]; then
  USER_NAME="$(/usr/bin/stat -f '%Su' /dev/console)"
fi

/bin/mkdir -p /usr/local/sbin
/bin/cp "$HELPER_SRC" "$HELPER_DST"
/usr/sbin/chown root:wheel "$HELPER_DST"
/bin/chmod 755 "$HELPER_DST"

TMP="$(/usr/bin/mktemp)"
trap '/bin/rm -f "$TMP"' EXIT
cat > "$TMP" <<EOF
# NTFS 读写：只允许运行固定助手，不能跑别的命令
Defaults!${HELPER_DST} !requiretty
${USER_NAME} ALL=(root) NOPASSWD: ${HELPER_DST}, ${HELPER_DST} *
EOF
/usr/sbin/visudo -c -f "$TMP" >/dev/null
/bin/cp "$TMP" "$SUDOERS"
/bin/chmod 440 "$SUDOERS"
echo "ok helper $HELPER_DST"
