#!/bin/bash
# ntfsmount list|status|mount|unmount — 给人读或 --json（稳定英文 snake_case）。
# list / status 只读，不装助手。mount / unmount 只执行已安装的 root 助手，不 sudo、不写 sudoers。
# 调用方须先设置 JSON=0|1；单独执行时默认人读。
# shellcheck shell=bash
set -euo pipefail
: "${JSON:=0}"

valid_slice() {
  local s="${1:-}"
  [[ "$s" == disk[0-9]*s[0-9]* ]] || return 1
  [[ "$s" =~ ^disk[0-9]+s[0-9]+$ ]]
}

plist_raw() {
  printf '%s' "$1" | /usr/bin/plutil -extract "$2" raw - 2>/dev/null || true
}

disk_idents() {
  /usr/sbin/diskutil list 2>/dev/null | /usr/bin/awk '
    /Windows_NTFS/ && $NF ~ /^disk[0-9]+s[0-9]+$/ { print $NF; next }
    /^[[:space:]]+[0-9]+:/ && $NF ~ /^disk[0-9]+s[0-9]+$/ { print $NF }
  ' | /usr/bin/awk 'NF && !seen[$0]++'
}

find_sealed_helper() {
  local p
  p="/Library/Application Support/NTFSMount/ntfs-rw-helper"
  if [[ -x "$p" ]]; then
    printf '%s' "$p"
    return 0
  fi
  p="${NTFSMOUNT_ROOT:-}/helper/ntfs-rw-helper"
  if [[ -n "${NTFSMOUNT_ROOT:-}" && -x "$p" ]]; then
    printf '%s' "$p"
    return 0
  fi
  return 1
}

# stdout: one JSON object. return 1 if not NTFS / missing.
volume_record_json() {
  local ident="$1"
  local info fs name mp writable internal mounted is_ro fuse line kind
  info="$(/usr/sbin/diskutil info -plist "$ident" 2>/dev/null || true)"
  [[ -n "$info" ]] || return 1
  fs="$(plist_raw "$info" FilesystemName)"
  [[ "$fs" == "NTFS" ]] || return 1
  name="$(plist_raw "$info" VolumeName)"
  [[ -n "$name" && "$name" != "null" ]] || name="NTFS-${ident}"
  mp="$(plist_raw "$info" MountPoint)"
  [[ -n "$mp" && "$mp" != "null" ]] || mp=""
  writable="$(plist_raw "$info" Writable)"
  internal="$(plist_raw "$info" Internal)"
  mounted=false
  is_ro=false
  fuse=false
  kind="ntfs"
  if [[ -n "$mp" ]]; then
    mounted=true
    line="$(/sbin/mount | /usr/bin/awk -v mp="$mp" '
      $2 == "on" {
        p = ""
        for (i = 3; i <= NF; i++) {
          if ($i ~ /^\(/) break
          p = (p == "" ? $i : p " " $i)
        }
        if (p == mp) { print; exit }
      }')"
    if printf '%s' "$line" | /usr/bin/grep -qiE 'ntfs-3g|fuse-t|fuset|macfuse|osxfuse| fuse,|\(nfs,|smbfs'; then
      fuse=true
      kind="fuse"
    fi
    if printf '%s' "$line" | /usr/bin/grep -qi 'read-only'; then
      is_ro=true
    elif [[ "$writable" == "false" ]]; then
      is_ro=true
    fi
    if [[ "$fuse" == true && "$is_ro" != true ]]; then
      is_ro=false
    fi
  fi
  [[ "$internal" == "true" ]] || internal=false
  /usr/bin/python3 -c '
import json,sys
print(json.dumps({
  "device": sys.argv[1],
  "name": sys.argv[2],
  "mounted": sys.argv[3] == "true",
  "readonly": sys.argv[4] == "true",
  "filesystem": "ntfs",
  "mount_point": sys.argv[5],
  "writable_fuse": sys.argv[6] == "true",
  "internal": sys.argv[7] == "true",
  "kind": sys.argv[8],
}, ensure_ascii=False, separators=(",", ":")))
' "$ident" "$name" "$mounted" "$is_ro" "$mp" "$fuse" "$internal" "$kind"
}

emit_error() {
  local err="$1" msg="$2" ident="${3:-}"
  local extra=""
  [[ -n "$ident" ]] && extra=",\"device\":$(/usr/bin/python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.argv[1], ensure_ascii=False))' "$ident")"
  if [[ "$JSON" -eq 1 ]]; then
    printf '{"ok":false,"error":%s,"message":%s%s}\n' \
      "$(/usr/bin/python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.argv[1], ensure_ascii=False))' "$err")" \
      "$(/usr/bin/python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.argv[1], ensure_ascii=False))' "$msg")" \
      "$extra"
  else
    echo "error: $msg" >&2
  fi
}

emit_ok_volume() {
  local rec="$1" action="${2:-}"
  if [[ "$JSON" -eq 1 ]]; then
    if [[ -n "$action" ]]; then
      /usr/bin/python3 -c '
import json,sys
d=json.loads(sys.argv[1])
d["ok"]=True
d["action"]=sys.argv[2]
print(json.dumps(d, ensure_ascii=False, separators=(",", ":")))
' "$rec" "$action"
    else
      /usr/bin/python3 -c '
import json,sys
d=json.loads(sys.argv[1])
d["ok"]=True
print(json.dumps(d, ensure_ascii=False, separators=(",", ":")))
' "$rec"
    fi
  else
    /usr/bin/python3 -c '
import json,sys
d=json.loads(sys.argv[1])
print("{device}  {name}  mounted={mounted}  readonly={readonly}  filesystem={filesystem}  mount_point={mp}".format(
  device=d.get("device",""), name=d.get("name",""),
  mounted=str(d.get("mounted", False)).lower(),
  readonly=str(d.get("readonly", False)).lower(),
  filesystem=d.get("filesystem","ntfs"),
  mp=d.get("mount_point") or "-"))
' "$rec"
  fi
}

cmd_list() {
  local ident rec found=0
  if [[ "$JSON" -eq 1 ]]; then
    while IFS= read -r ident; do
      [[ -n "$ident" ]] || continue
      rec="$(volume_record_json "$ident" || true)"
      [[ -n "$rec" ]] || continue
      printf '%s\n' "$rec"
    done < <(disk_idents) | /usr/bin/python3 -c '
import json,sys
vols=[json.loads(line) for line in sys.stdin if line.strip()]
print(json.dumps({"ok": True, "volumes": vols}, ensure_ascii=False, separators=(",", ":")))
'
    return 0
  fi
  while IFS= read -r ident; do
    [[ -n "$ident" ]] || continue
    rec="$(volume_record_json "$ident" || true)"
    [[ -n "$rec" ]] || continue
    found=1
    emit_ok_volume "$rec"
  done < <(disk_idents)
  if [[ "$found" -eq 0 ]]; then
    echo "no NTFS volumes"
  fi
}

cmd_status() {
  local ident="$1" rec
  if [[ -z "$ident" ]]; then
    cmd_list
    return 0
  fi
  if ! valid_slice "$ident"; then
    emit_error "invalid_device" "invalid device: $ident" "$ident"
    return 2
  fi
  rec="$(volume_record_json "$ident" || true)"
  if [[ -z "$rec" ]]; then
    emit_error "not_found" "not a connected NTFS volume: $ident" "$ident"
    return 1
  fi
  emit_ok_volume "$rec"
}

run_helper_cmd() {
  local verb="$1" ident="$2"
  local helper out rc rec
  if [[ "$(/usr/bin/id -u)" -ne 0 ]]; then
    emit_error "not_root" "mount/unmount needs the installed privileged helper (LaunchDaemon). Install the helper from the menu-bar app, then try again." "$ident"
    return 1
  fi
  helper="$(find_sealed_helper)" || {
    emit_error "helper_missing" "installed ntfs-rw-helper not found" "$ident"
    return 1
  }
  set +e
  out="$("$helper" "$verb" "$ident" 2>&1)"
  rc=$?
  set -e
  rec="$(volume_record_json "$ident" || true)"
  if [[ "$rc" -eq 0 ]]; then
    if [[ -n "$rec" ]]; then
      emit_ok_volume "$rec" "$verb"
    elif [[ "$JSON" -eq 1 ]]; then
      /usr/bin/python3 -c '
import json,sys
print(json.dumps({"ok":True,"action":sys.argv[1],"device":sys.argv[2],"detail":sys.argv[3],"filesystem":"ntfs"}, ensure_ascii=False, separators=(",", ":")))
' "$verb" "$ident" "$out"
    else
      printf '%s\n' "$out"
    fi
    return 0
  fi
  emit_error "helper_failed" "$out" "$ident"
  return 1
}

cmd_mount() {
  local ident="$1"
  if [[ -z "$ident" ]]; then
    emit_error "missing_device" "usage: ntfsmount mount <diskNsM> [--json]"
    return 2
  fi
  if ! valid_slice "$ident"; then
    emit_error "invalid_device" "invalid device: $ident" "$ident"
    return 2
  fi
  run_helper_cmd mount "$ident"
}

cmd_unmount() {
  local ident="$1"
  if [[ -z "$ident" ]]; then
    emit_error "missing_device" "usage: ntfsmount unmount <diskNsM> [--json]"
    return 2
  fi
  if ! valid_slice "$ident"; then
    emit_error "invalid_device" "invalid device: $ident" "$ident"
    return 2
  fi
  run_helper_cmd unmount "$ident"
}
