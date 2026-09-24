#!/bin/bash
# 打印 Sources/NTFSMountCore 的 llvm-cov 行覆盖率（不含 UI、不含 helper bash）。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift test --enable-code-coverage --package-path "$ROOT"

BIN="$(/usr/bin/find "$ROOT/.build" -path '*NTFSMountCoreTests.xctest/Contents/MacOS/NTFSMountCoreTests' -type f | /usr/bin/tail -1)"
PROF="$(/usr/bin/find "$ROOT/.build" -name default.profdata -type f | /usr/bin/tail -1)"
[[ -n "$BIN" && -x "$BIN" ]] || { echo "error: 找不到 NTFSMountCoreTests 二进制" >&2; exit 1; }
[[ -n "$PROF" && -f "$PROF" ]] || { echo "error: 找不到 default.profdata" >&2; exit 1; }

echo
echo "NTFSMountCore (llvm-cov, 不含 UI / helper bash):"
xcrun llvm-cov report "$BIN" -instr-profile "$PROF" "$ROOT/Sources/NTFSMountCore"
echo
echo "写操作相关（磁盘检测 + 格式化 + 挂载分类）:"
xcrun llvm-cov report "$BIN" -instr-profile "$PROF" \
  "$ROOT/Sources/NTFSMountCore/NTFSVolume.swift" \
  "$ROOT/Sources/NTFSMountCore/FormatDisk.swift" \
  "$ROOT/Sources/NTFSMountCore/FormatPolicy.swift" \
  "$ROOT/Sources/NTFSMountCore/VolumeHealth.swift"
