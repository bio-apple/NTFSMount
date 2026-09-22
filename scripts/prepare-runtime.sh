#!/bin/bash
# 刷新 runtime/ 里的捆绑依赖（供 build.sh 打进 app）。
# libfuse.2.dylib 若已是可用 shim 则保留；其余从系统拷贝并改 @rpath。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME="$ROOT/runtime"
WORK="$(/usr/bin/mktemp -d /tmp/ntfsmount-prep.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$RUNTIME"

die() { echo "error: $*" >&2; exit 1; }

[[ -f "$RUNTIME/libfuse.2.dylib" ]] || die "缺少 $RUNTIME/libfuse.2.dylib（FUSE-T shim）。请保留现有文件或先完成一次 FUSE-T 安装后再手工放入。"
[[ -x /usr/local/lib/libntfs-3g.90.dylib || -f /usr/local/lib/libntfs-3g.90.dylib ]] || die "缺少 /usr/local/lib/libntfs-3g.90.dylib"
[[ -x /usr/local/bin/ntfs-3g || -x "$RUNTIME/ntfs-3g" ]] || die "缺少 ntfs-3g"
[[ -x /usr/local/sbin/mkntfs || -x "$RUNTIME/mkntfs" ]] || die "缺少 mkntfs"

SRC_NTFS_BIN="$RUNTIME/ntfs-3g"
[[ -x "$SRC_NTFS_BIN" ]] || SRC_NTFS_BIN=/usr/local/bin/ntfs-3g
SRC_MKNTFS="$RUNTIME/mkntfs"
[[ -x "$SRC_MKNTFS" ]] || SRC_MKNTFS=/usr/local/sbin/mkntfs
SRC_NFS="/Library/Application Support/fuse-t/bin/go-nfsv4-1.2.7"
[[ -x "$SRC_NFS" ]] || SRC_NFS=/usr/local/bin/go-nfsv4
[[ -x "$SRC_NFS" ]] || die "缺少 go-nfsv4（请先装 FUSE-T 一次，或把二进制放进 runtime/）"

cp "$RUNTIME/libfuse.2.dylib" "$WORK/libfuse.2.dylib"
cp /usr/local/lib/libntfs-3g.90.dylib "$WORK/libntfs-3g.90.dylib"
cp "$SRC_NTFS_BIN" "$WORK/ntfs-3g"
cp "$SRC_MKNTFS" "$WORK/mkntfs"
cp "$SRC_NFS" "$WORK/go-nfsv4"
chmod 755 "$WORK"/*

install_name_tool -id '@rpath/libntfs-3g.90.dylib' "$WORK/libntfs-3g.90.dylib"
install_name_tool -change /usr/local/lib/libntfs-3g.90.dylib '@rpath/libntfs-3g.90.dylib' "$WORK/ntfs-3g" 2>/dev/null || true
install_name_tool -change /usr/local/lib/libfuse.2.dylib '@rpath/libfuse.2.dylib' "$WORK/ntfs-3g" 2>/dev/null || true
install_name_tool -change /usr/local/lib/libntfs-3g.90.dylib '@rpath/libntfs-3g.90.dylib' "$WORK/mkntfs" 2>/dev/null || true
if ! /usr/bin/otool -l "$WORK/ntfs-3g" | /usr/bin/grep -q 'path @executable_path'; then
  install_name_tool -add_rpath '@executable_path' "$WORK/ntfs-3g"
fi
if ! /usr/bin/otool -l "$WORK/mkntfs" | /usr/bin/grep -q 'path @executable_path'; then
  install_name_tool -add_rpath '@executable_path' "$WORK/mkntfs"
fi

codesign --force --sign - \
  "$WORK/libfuse.2.dylib" \
  "$WORK/libntfs-3g.90.dylib" \
  "$WORK/ntfs-3g" \
  "$WORK/mkntfs" \
  "$WORK/go-nfsv4" >/dev/null

cp -f "$WORK"/* "$RUNTIME/"
chmod 755 "$RUNTIME/libfuse.2.dylib" "$RUNTIME/libntfs-3g.90.dylib" "$RUNTIME/ntfs-3g" "$RUNTIME/mkntfs" "$RUNTIME/go-nfsv4"
"$RUNTIME/ntfs-3g" --version
"$RUNTIME/mkntfs" --version
echo "runtime ready:"
/bin/ls -lh "$RUNTIME"
