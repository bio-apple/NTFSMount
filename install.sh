#!/bin/bash
# 安装菜单栏应用 + 仅针对本助手的 sudo 规则。
# 用户态依赖（ntfs-3g / libfuse / libntfs-3g / go-nfsv4）全部打进 app。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
USER_NAME="${SUDO_USER:-$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null || /usr/bin/id -un)}"
if [[ "$USER_NAME" == "root" ]]; then
  USER_NAME="$(/usr/bin/stat -f '%Su' /dev/console)"
fi
HELPER_SRC="$ROOT/helper/ntfs-rw-helper"
HELPER_DST="/usr/local/sbin/ntfs-rw-helper"
SUDOERS="/etc/sudoers.d/ntfs-rw"
APP_SRC="$ROOT/dist/NTFSMount.app"
APP_DST="/Applications/NTFSMount.app"

echo "==> 编译 NTFSMount.app（含捆绑依赖）"
bash "$ROOT/scripts/build.sh"
if [[ ! -d "$APP_SRC" && -d /tmp/NTFSMount.app ]]; then
  APP_SRC="/tmp/NTFSMount.app"
fi

echo "==> 安装挂载助手（需要管理员密码一次）"
sudo mkdir -p /usr/local/sbin
sudo cp "$HELPER_SRC" "$HELPER_DST"
sudo chown root:wheel "$HELPER_DST"
sudo chmod 755 "$HELPER_DST"

TMP="$(mktemp)"
cat > "$TMP" <<EOF
# NTFS 读写：只允许运行固定助手，不能跑别的命令
Defaults!${HELPER_DST} !requiretty
${USER_NAME} ALL=(root) NOPASSWD: ${HELPER_DST}, ${HELPER_DST} *
EOF
sudo visudo -c -f "$TMP" >/dev/null
sudo cp "$TMP" "$SUDOERS"
sudo chmod 440 "$SUDOERS"
rm -f "$TMP"

echo "==> 安装到 /Applications"
sudo rm -rf "$APP_DST"
sudo cp -R "$APP_SRC" "$APP_DST"
sudo chown -R "$USER_NAME:staff" "$APP_DST"

echo "==> 打开应用"
open "$APP_DST"

cat <<EOF

装好了。菜单栏会出现「NTFS」。

日常：
1. 插入 NTFS 移动硬盘
2. 点菜单 → 以可写方式挂载
3. 用完点「推出」再拔线

说明：ntfs-3g / FUSE 用户态库 / go-nfsv4 都在 app 内，不必再单独装 FUSE-T。
仍需一次管理员密码安装挂载助手；若挂载失败，可在系统设置里给 NTFSMount 打开「完全磁盘访问权限」。
EOF
