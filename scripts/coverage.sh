#!/bin/bash
# 打印 Sources/NTFSMountCore 的 llvm-cov 行覆盖率（不含 UI、不含 helper bash）。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift test --enable-code-coverage --package-path "$ROOT"

# Xcode 15.4 / SwiftPM emits NTFSMountPackageTests.xctest; newer toolchains may
# emit NTFSMountCoreTests.xctest. `swift test` already passed — llvm-cov is
# best-effort and must not fail the UnitTest job.
BIN="$(/usr/bin/find "$ROOT/.build" \( \
  -path '*NTFSMountPackageTests.xctest/Contents/MacOS/NTFSMountPackageTests' -o \
  -path '*NTFSMountCoreTests.xctest/Contents/MacOS/NTFSMountCoreTests' \
  \) -type f | /usr/bin/tail -1)"
PROF="$(/usr/bin/find "$ROOT/.build" -name default.profdata -type f | /usr/bin/tail -1)"
if [[ -z "${BIN:-}" || ! -x "$BIN" || -z "${PROF:-}" || ! -f "$PROF" ]]; then
  echo "warning: skip llvm-cov (no NTFSMountPackageTests/NTFSMountCoreTests.xctest or default.profdata)" >&2
  exit 0
fi

echo
echo "NTFSMountCore (llvm-cov, excluding UI / helper bash):"
xcrun llvm-cov report "$BIN" -instr-profile "$PROF" "$ROOT/Sources/NTFSMountCore"
echo
echo "Write path (disk detection + format + mount classification):"
xcrun llvm-cov report "$BIN" -instr-profile "$PROF" \
  "$ROOT/Sources/NTFSMountCore/NTFSVolume.swift" \
  "$ROOT/Sources/NTFSMountCore/FormatDisk.swift" \
  "$ROOT/Sources/NTFSMountCore/FormatPolicy.swift" \
  "$ROOT/Sources/NTFSMountCore/VolumeHealth.swift"
