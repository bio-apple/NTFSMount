#!/bin/bash
# 打包成可双击分发的 DMG：把 NTFSMount.app 拖进「应用程序」即可。
set -euo pipefail
if [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" != "1" && "$(/usr/bin/uname -m)" != "arm64" ]]; then
  echo "error: NTFSMount 仅支持 Apple Silicon（M 芯片 / arm64），不支持 Intel Mac（x86_64）。当前架构：$(/usr/bin/uname -m)" >&2
  exit 1
fi
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
/bin/cp "$ROOT/LICENSE" "$STAGE/LICENSE"
/bin/cp "$ROOT/NOTICE" "$STAGE/NOTICE"
/bin/cp "$ROOT/THIRD_PARTY_LICENSES.md" "$STAGE/THIRD_PARTY_LICENSES.md"
/bin/cp "$ROOT/docs/DISTRIBUTION.md" "$STAGE/DISTRIBUTION.md"
printf '%s\n' "源码: https://github.com/bio-apple/NTFSMount" > "$STAGE/源码.txt"
/bin/cat > "$STAGE/使用说明.txt" <<'EOF'
NTFS 读写（NTFSMount，直发，不上 Mac App Store）

仅支持 Apple Silicon（M 芯片）与 macOS 13.0+。不支持 Intel Mac（x86_64），请勿在 Intel Mac 上安装。

安装
1. 把 NTFS 读写拖到右边的「应用程序」
2. 打开后菜单栏显示 NTFS，并出现主窗口
3. 首次只有一个确认框：备份、个人使用、未公证说明。回车是「同意并继续」，Esc 为「退出」
4. 在窗口点「安装…」。未公证包会要管理员密码；已公证包优先系统服务授权
   升级后若提示「更新挂载助手」，再输入一次密码
5. 若系统提示无法验证开发者：按住 Control 点应用 → 打开；或「系统设置 → 隐私与安全性」点「仍要打开」。仍被隔离时：
   xattr -d com.apple.quarantine /Applications/NTFSMount.app

读写
1. 插入外置 NTFS 硬盘。第一次可写挂载会再确认一次「已备份」
2. 默认以可写方式挂载（内置盘 / Boot Camp 不会自动挂）
3. 用完点「推出（可安全拔出）」，等盘消失后再拔线
4. 自动挂载、登录时打开、程序坞、助手与日志：窗口左侧「设置」

格式化
点「格式化为 NTFS…」可把外置整盘抹掉并做成 NTFS。
必须输入当前卷名确认。内置盘不能格式化。

卸载助手：设置 → 卸载助手
完全卸载：仓库中的 ./uninstall.sh（只删 NTFSMount；不碰系统级 FUSE-T / MacFUSE）
EOF

if [[ "${FUSE_T_REDISTRIBUTION_OK:-}" != "1" ]]; then
  /bin/cat > "$STAGE/个人使用说明.txt" <<'EOF'
本安装包仅供个人使用。仅支持 Apple Silicon（M 芯片）与 macOS 13.0+，不支持 Intel Mac（x86_64）。

捆绑的 FUSE-T go-nfsv4 不是 GPL。作为产品嵌入、分发或销售前，须向 FUSE-T 取得许可：
https://www.fuse-t.org/

未公证的构建会被 Gatekeeper 拦截。按住 Control 点应用 → 打开；也可在「系统设置 → 隐私与安全性」点「仍要打开」。正式发给他人请使用 Developer ID 公证。
详见 DISTRIBUTION.md 与 THIRD_PARTY_LICENSES.md。
EOF
fi

SIZE_MB="$(/usr/bin/du -sm "$STAGE" | /usr/bin/awk '{print int($1)+30}')"
echo "==> 制作磁盘映像（${SIZE_MB} MB）"
/usr/bin/hdiutil create -ov -quiet -fs HFS+ -volname "$VOLNAME" -size "${SIZE_MB}m" "$RW" >/dev/null

ATTACH="$(/usr/bin/hdiutil attach -readwrite -noverify -noautoopen "$RW")"
MNT="$(printf '%s\n' "$ATTACH" | /usr/bin/awk -F'\t' '/\/Volumes\//{print $NF; exit}')"
[[ -d "$MNT" ]] || { echo "error: 未能挂上临时 DMG" >&2; exit 1; }

/bin/cp -R "$STAGE/NTFSMount.app" "$MNT/NTFSMount.app"
/bin/ln -s /Applications "$MNT/Applications"
/bin/cp "$STAGE/使用说明.txt" "$MNT/使用说明.txt"
/bin/cp "$STAGE/LICENSE" "$MNT/LICENSE"
/bin/cp "$STAGE/NOTICE" "$MNT/NOTICE"
/bin/cp "$STAGE/THIRD_PARTY_LICENSES.md" "$MNT/THIRD_PARTY_LICENSES.md"
/bin/cp "$STAGE/DISTRIBUTION.md" "$MNT/DISTRIBUTION.md"
/bin/cp "$STAGE/源码.txt" "$MNT/源码.txt"
if [[ -f "$STAGE/个人使用说明.txt" ]]; then
  /bin/cp "$STAGE/个人使用说明.txt" "$MNT/个人使用说明.txt"
fi

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
    set position of item "NTFSMount.app" of container window to {160, 140}
    set position of item "Applications" of container window to {480, 140}
    set position of item "使用说明.txt" of container window to {160, 320}
    set position of item "LICENSE" of container window to {320, 320}
    set position of item "源码.txt" of container window to {480, 320}
    update without registering applications
    delay 1
    close
    open
    delay 1
  end tell
end tell
EOF

# 访达排版后再写卷图标，避免转换时丢掉不可见文件
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  /bin/cp "$ROOT/Resources/AppIcon.icns" "$MNT/.VolumeIcon.icns"
  /usr/bin/SetFile -c icnC "$MNT/.VolumeIcon.icns"
  /usr/bin/SetFile -a C "$MNT"
  [[ -f "$MNT/.VolumeIcon.icns" ]] || { echo "error: 未能写入 .VolumeIcon.icns" >&2; exit 1; }
fi

sync
/usr/bin/hdiutil detach "$MNT" -quiet
MNT=""

mkdir -p "$(/usr/bin/dirname "$OUT")"
/bin/rm -f "$OUT"
echo "==> 压缩为 $OUT"
/usr/bin/hdiutil convert "$RW" -quiet -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null

echo "ok $OUT"
/bin/ls -lh "$OUT"
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  bash "$ROOT/scripts/notarize.sh" "$OUT" || echo "warning: DMG 公证/staple 失败（应用若已公证仍可用）" >&2
fi
# staple 会改 DMG，哈希必须在最后算
bash "$ROOT/scripts/write-dmg-sha256.sh" "$OUT"
if [[ "${FUSE_T_REDISTRIBUTION_OK:-}" != "1" ]]; then
  echo "note: FUSE_T_REDISTRIBUTION_OK unset; DMG is personal-use only" >&2
fi
