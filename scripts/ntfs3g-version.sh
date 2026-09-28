#!/bin/bash
# 捆绑 ntfs-3g 版本解析与允许列表。
# 与 Sources/NTFSMountCore/Ntfs3gVersion.swift、runtime/versions.txt 保持一致。
# 允许：精确 2026.7.7，或 2026.8.x（2026.8.0–2026.8.99）。未知版本只警告，不硬拦。
# 供 diagnose / prepare-runtime source；不要用 PATH 里的 ntfs-3g。

NTFS3G_PINNED="${NTFS3G_PINNED:-2026.7.7}"
NTFS3G_ALLOW_LIST="${NTFS3G_ALLOW_LIST:-2026.7.7,2026.8.x}"
NTFS3G_ALLOW_HUMAN="${NTFS3G_ALLOW_HUMAN:-2026.7.7, 2026.8.x}"

ntfs3g_parse_version() {
  local text="$1" ver
  ver="$(printf '%s' "$text" | /usr/bin/grep -oiE 'ntfs-3g[[:space:]]+v?[0-9]{4}\.[0-9]{1,2}\.[0-9]{1,3}' |
    /usr/bin/head -1 | /usr/bin/grep -oE '[0-9]{4}\.[0-9]{1,2}\.[0-9]{1,3}' || true)"
  if [[ -z "$ver" ]]; then
    ver="$(printf '%s' "$text" | /usr/bin/grep -oE '[0-9]{4}\.[0-9]{1,2}\.[0-9]{1,3}' | /usr/bin/head -1 || true)"
  fi
  printf '%s' "$ver"
}

ntfs3g_version_allowed() {
  local ver="$1" y m p
  [[ -n "$ver" ]] || return 1
  case "$ver" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) return 1 ;;
  esac
  IFS=. read -r y m p <<EOF
$ver
EOF
  [[ "$y" =~ ^[0-9]+$ && "$m" =~ ^[0-9]+$ && "$p" =~ ^[0-9]+$ ]] || return 1
  y=$((10#$y))
  m=$((10#$m))
  p=$((10#$p))
  if [[ "$y" -eq 2026 && "$m" -eq 7 && "$p" -eq 7 ]]; then
    return 0
  fi
  if [[ "$y" -eq 2026 && "$m" -eq 8 && "$p" -ge 0 && "$p" -le 99 ]]; then
    return 0
  fi
  return 1
}

ntfs3g_human_line() {
  local present="$1" ver="$2" allowed="$3"
  if [[ "$present" != true ]]; then
    printf '%s' "Bundled ntfs-3g not found, so the version was not checked (PATH was not searched)"
    return 0
  fi
  if [[ "$allowed" == true ]]; then
    printf '%s' "ntfs-3g ${ver} (tested; allowed ${NTFS3G_ALLOW_HUMAN})"
    return 0
  fi
  printf '%s' "ntfs-3g ${ver:-unknown} is untested (allowed ${NTFS3G_ALLOW_HUMAN}); an unknown version is risky, but mounting can continue"
}
