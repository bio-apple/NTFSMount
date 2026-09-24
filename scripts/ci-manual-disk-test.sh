#!/bin/bash
# docs/MANUAL_TEST.md 的可脚本化子集。无 GUI、不公证、不抹盘、不静默清 hiberfile。
# 无 NTFS 卷时立刻失败，不空等插盘。
set -euo pipefail
if [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" != "1" && "$(/usr/bin/uname -m)" != "arm64" ]]; then
  echo "error: 仅支持 Apple Silicon（arm64）。当前：$(/usr/bin/uname -m)" >&2
  exit 1
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOCK="/var/run/com.bioapple.ntfsmount.sock"
SUDOERS="/etc/sudoers.d/ntfs-rw"

echo "==> macOS $(/usr/bin/sw_vers -productVersion)  arch=$(/usr/bin/uname -m)"
echo
echo "==> docs/MANUAL_TEST.md 全文（人工勾选仍以该文件为准）"
/bin/cat "$ROOT/docs/MANUAL_TEST.md"
echo

echo "==> diskutil list"
/usr/sbin/diskutil list
echo

echo "==> NTFS 卷（diskutil info FilesystemName=NTFS）"
found=0
while IFS= read -r ident; do
  [[ "$ident" == disk* ]] || continue
  fs="$(/usr/sbin/diskutil info -plist "$ident" 2>/dev/null | /usr/bin/plutil -extract FilesystemName raw - 2>/dev/null || true)"
  [[ "$fs" == "NTFS" ]] || continue
  found=1
  echo "---- $ident ----"
  /usr/sbin/diskutil info "$ident" | /usr/bin/grep -E 'Device Identifier:|Volume Name:|Mount Point:|File System Personality:|Protocol:|Internal:|Removable Media:' || true
done < <(/usr/sbin/diskutil list | /usr/bin/awk '/^[[:space:]]+[0-9]+:/{print $NF}')

if [[ "$found" -eq 0 ]]; then
  echo "error: 本机没有 NTFS 卷。GitHub-hosted runner 无法插入 USB。" >&2
  echo "请在已插入外置 NTFS 的 self-hosted Apple Silicon runner 上再手动触发 .github/workflows/manual-disk-test.yml。" >&2
  exit 1
fi

echo
echo "==> /sbin/mount（ntfs-3g / FUSE 行）"
/sbin/mount | /usr/bin/grep -iE 'ntfs-3g|fuse-t|fuset|macfuse|osxfuse| nfs,' || echo "(当前没有 FUSE/ntfs-3g 挂载行)"

echo
echo "==> 仓库 helper selftest / version（不经特权守护进程，不挂载）"
"$ROOT/helper/ntfs-rw-helper" selftest
"$ROOT/helper/ntfs-rw-helper" version

echo
echo "==> 助手 ping（socket / LaunchDaemon / 禁止 sudoers）"
if [[ -e "$SUDOERS" ]]; then
  echo "error: 不应存在 $SUDOERS（本项目不写 sudoers NOPASSWD）" >&2
  exit 1
fi
echo "gone or absent: $SUDOERS"

if [[ -S "$SOCK" || -e "$SOCK" ]]; then
  echo "helper socket present: $SOCK"
  ls -l "$SOCK"
else
  echo "error: 没有 $SOCK。请在 runner 上先打开 NTFSMount，窗口点「安装…」装好挂载助手，再触发本 workflow。不在 CI 里弹 GUI / 要管理员密码。" >&2
  exit 1
fi
for p in \
  /Library/LaunchDaemons/com.bioapple.ntfsmount.helper.plist \
  /Library/PrivilegedHelperTools/com.bioapple.ntfsmount.helperd
do
  if [[ -e "$p" ]]; then
    echo "present: $p"
  else
    echo "missing: $p"
  fi
done

echo
echo "==> 以下 MANUAL_TEST.md 步骤无法在无头 CI 安全完成，须人工勾选："
cat <<'EOF'
- Gatekeeper / 未公证：Control-click 打开，「系统设置 → 隐私与安全性 → 仍要打开」，xattr 清隔离
- 首次确认框（回车同意 / Esc 退出）、主窗口「安装…」横幅
- 插入后自动可写、菜单栏「可写」、访达拷贝
- 「推出（可安全拔出）」后访达消失再拔线
- 系统 NTFS 只读 → 子菜单改可写
- 脏盘 / 休眠只读、尝试修复脏卷（默认取消）；不要静默清 hiberfile
- 内置 / Boot Camp 不自动挂；格式化对话框（会抹盘，CI 不跑）
- 设置 → 卸载助手后 bash scripts/check-helper-gone.sh
- 升级旧 sudoers 机器
EOF
echo "ok scriptable manual-disk-test"
