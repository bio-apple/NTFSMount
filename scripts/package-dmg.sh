#!/bin/bash
# 打包成可双击分发的 DMG：把 NTFSMount.app 拖进「应用程序」即可。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/dist/NTFSMount.dmg}"
VOLNAME="NTFS 读写"

echo "==> 编译 NTFSMount.app"
bash "$ROOT/scripts/build.sh"
APP_SRC="$ROOT/dist/NTFSMount.app"
if [[ ! -d "$APP_SRC" && -d /tmp/NTFSMount.app ]]; then
  APP_SRC="/tmp/NTFSMount.app"
fi
[[ -d "$APP_SRC" ]] || { echo "error: 找不到 NTFSMount.app" >&2; exit 1; }

STAGE="$(/usr/bin/mktemp -d /tmp/ntfsmount-dmg.XXXXXX)"
RW="$(/usr/bin/mktemp /tmp/ntfsmount-rw.XXXXXX).dmg"
MNT=""
cleanup() {
  if [[ -n "$MNT" && -d "$MNT" ]]; then
    /usr/bin/hdiutil detach "$MNT" -quiet >/dev/null 2>&1 || true
  fi
  /bin/rm -rf "$STAGE"
  /bin/rm -f "$RW"
}
trap cleanup EXIT

/bin/cp -R "$APP_SRC" "$STAGE/NTFSMount.app"
/bin/ln -s /Applications "$STAGE/Applications"
/bin/cat > "$STAGE/使用说明.txt" <<'EOF'
NTFS 读写

安装
1. 把 NTFSMount 拖到右边的「应用程序」
2. 打开「应用程序」里的 NTFSMount（菜单栏出现 NTFS）
3. 第一次会询问管理员密码，用来安装挂载助手
   升级后若提示「更新挂载助手」，再输入一次密码

读写
1. 插入 NTFS 硬盘
2. 点菜单栏 NTFS → 以可写方式挂载
3. 用完点「推出（可安全拔出）」，等盘消失后再拔线

格式化
点「格式化为 NTFS…」可把外置整盘抹掉并做成 NTFS。
内置盘 / 系统盘不能格式化。此操作会删除盘上全部文件。

若提示无法打开：按住 Control 点应用 → 打开。
EOF

SIZE_MB="$(/usr/bin/du -sm "$STAGE" | /usr/bin/awk '{print int($1)+30}')"
echo "==> 制作磁盘映像（${SIZE_MB} MB）"
/usr/bin/hdiutil create -ov -quiet -fs HFS+ -volname "$VOLNAME" -size "${SIZE_MB}m" "$RW" >/dev/null

ATTACH="$(/usr/bin/hdiutil attach -readwrite -noverify -noautoopen "$RW")"
MNT="$(printf '%s\n' "$ATTACH" | /usr/bin/awk -F'\t' '/\/Volumes\//{print $NF; exit}')"
[[ -d "$MNT" ]] || { echo "error: 未能挂上临时 DMG" >&2; exit 1; }

/bin/cp -R "$STAGE/NTFSMount.app" "$MNT/NTFSMount.app"
/bin/ln -s /Applications "$MNT/Applications"
/bin/cp "$STAGE/使用说明.txt" "$MNT/使用说明.txt"

# 摆成「左边应用、右边应用程序」的常见安装窗口
/usr/bin/osascript <<EOF
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {280, 160, 920, 600}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 96
    set position of item "NTFSMount.app" of container window to {160, 160}
    set position of item "Applications" of container window to {480, 160}
    set position of item "使用说明.txt" of container window to {320, 340}
    update without registering applications
    delay 1
    close
    open
    delay 1
  end tell
end tell
EOF

sync
/usr/bin/hdiutil detach "$MNT" -quiet
MNT=""

mkdir -p "$(/usr/bin/dirname "$OUT")"
/bin/rm -f "$OUT"
echo "==> 压缩为 $OUT"
/usr/bin/hdiutil convert "$RW" -quiet -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null

echo "ok $OUT"
/bin/ls -lh "$OUT"
