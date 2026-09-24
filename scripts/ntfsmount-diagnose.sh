#!/bin/bash
# ntfsmount diagnose — 只读环境转储，方便贴 Bug / CI 日志。
# 不挂载、不卸载、不格式化、不跑 ntfsfix、不要管理员密码、不安装助手。
# 用法:
#   ./scripts/ntfsmount diagnose [--json]
#   ./scripts/ntfsmount-diagnose.sh [--json]
set -euo pipefail

ROOT="$(cd "$(/usr/bin/dirname "$0")/.." && pwd)"
SOCK="/var/run/com.bioapple.ntfsmount.sock"
HELPER_PLIST="/Library/LaunchDaemons/com.bioapple.ntfsmount.helper.plist"
HELPERD="/Library/PrivilegedHelperTools/com.bioapple.ntfsmount.helperd"
FUSE_T_BIN="/Library/Application Support/fuse-t/bin"
FUSE_T_APP="/Applications/FUSE-T.app"
APP_BUNDLE="/Applications/NTFSMount.app"

JSON=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    diagnose) shift ;;
    --json) JSON=1; shift ;;
    -h|--help)
      echo "用法: ntfsmount diagnose [--json]"
      echo "      $0 [--json]"
      echo "只读诊断。不挂载、不装助手。--json 输出稳定英文 snake_case 键。"
      exit 0
      ;;
    *)
      echo "error: 未知参数: $1" >&2
      echo "用法: ntfsmount diagnose [--json]" >&2
      exit 2
      ;;
  esac
done

# perl alarm 在 exec 后仍作用于同一 PID，用来卡住 showmount / lsof / diskutil。
timeout_run() {
  local sec="$1"
  shift
  /usr/bin/perl -e 'alarm shift; exec @ARGV' "$sec" "$@" 2>/dev/null || true
}

trim() {
  printf '%s' "$1" | /usr/bin/tr -d '\r' | /usr/bin/sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

oneline() {
  printf '%s' "$1" | /usr/bin/tr '\n' ' ' | /usr/bin/sed -e 's/[[:space:]]\{1,\}/ /g' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

json_str() {
  /usr/bin/python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.argv[1], ensure_ascii=False))' "$1"
}

json_obj() {
  /usr/bin/python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1]), ensure_ascii=False, separators=(",", ":")))' "$1"
}

# --- app / helper 版本（读文件，不执行挂载路径） ---
app_version="unknown"
if [[ -f "$ROOT/Resources/Info.plist" ]]; then
  app_version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$ROOT/Resources/Info.plist" 2>/dev/null || true)"
  app_version="$(trim "${app_version:-unknown}")"
fi
installed_version=""
if [[ -f "$APP_BUNDLE/Contents/Info.plist" ]]; then
  installed_version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true)"
  installed_version="$(trim "$installed_version")"
fi

helper_version="unknown"
if [[ -f "$ROOT/helper/ntfs-rw-helper" ]]; then
  helper_version="$(/usr/bin/awk -F= '/^HELPER_VERSION=/{print $2; exit}' "$ROOT/helper/ntfs-rw-helper" 2>/dev/null || true)"
  helper_version="$(trim "${helper_version:-unknown}")"
fi

pinned_fuse_t="unknown"
if [[ -f "$ROOT/runtime/versions.txt" ]]; then
  pinned_fuse_t="$(/usr/bin/awk '/^FUSE-T[[:space:]]/{print $2; exit}' "$ROOT/runtime/versions.txt" 2>/dev/null || true)"
  pinned_fuse_t="$(trim "${pinned_fuse_t:-unknown}")"
fi

# --- macOS ---
macos_product="$(/usr/bin/sw_vers -productName 2>/dev/null || true)"
macos_version="$(/usr/bin/sw_vers -productVersion 2>/dev/null || true)"
macos_build="$(/usr/bin/sw_vers -buildVersion 2>/dev/null || true)"
macos_product="$(trim "${macos_product:-unknown}")"
macos_version="$(trim "${macos_version:-unknown}")"
macos_build="$(trim "${macos_build:-unknown}")"

# --- Apple Silicon ---
arch="$(/usr/bin/uname -m 2>/dev/null || true)"
arch="$(trim "${arch:-unknown}")"
hw_model="$(/usr/sbin/sysctl -n hw.model 2>/dev/null || true)"
hw_model="$(trim "${hw_model:-unknown}")"
arm64_flag="$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)"
arm64_flag="$(trim "${arm64_flag:-unknown}")"
chip="$(/usr/sbin/sysctl -n machdep.cpu.brand_string 2>/dev/null || true)"
chip="$(trim "${chip:-unknown}")"
if [[ "$arch" == "arm64" || "$arm64_flag" == "1" ]]; then
  apple_silicon=true
else
  apple_silicon=false
fi

# --- FUSE-T / go-nfsv4 ---
system_go=""
system_fuse_ver="unknown"
for f in "$FUSE_T_BIN"/go-nfsv4-*; do
  if [[ -x "$f" ]]; then
    system_go="$f"
    system_fuse_ver="$(/usr/bin/basename "$f")"
    system_fuse_ver="${system_fuse_ver#go-nfsv4-}"
    break
  fi
done
if [[ -z "$system_go" && -x "$FUSE_T_BIN/go-nfsv4" ]]; then
  system_go="$FUSE_T_BIN/go-nfsv4"
  if [[ -L "$system_go" ]]; then
    linkt="$(/usr/bin/readlink "$system_go" 2>/dev/null || true)"
    case "$linkt" in
      go-nfsv4-*) system_fuse_ver="${linkt#go-nfsv4-}" ;;
    esac
  fi
fi
if [[ "$system_fuse_ver" == "unknown" && -f "$FUSE_T_APP/Contents/Info.plist" ]]; then
  system_fuse_ver="$(/usr/bin/defaults read "$FUSE_T_APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)"
  system_fuse_ver="$(trim "${system_fuse_ver:-unknown}")"
fi
system_app=false
[[ -d "$FUSE_T_APP" ]] && system_app=true

bundled_go=""
for cand in \
  "$ROOT/runtime/go-nfsv4" \
  "$APP_BUNDLE/Contents/MacOS/go-nfsv4"
do
  if [[ -x "$cand" ]]; then
    bundled_go="$cand"
    break
  fi
done
bundled_present=false
[[ -n "$bundled_go" ]] && bundled_present=true

# --- helper socket ping（存在才连；校验失败说明守护进程活着。不触发安装） ---
socket_exists=false
[[ -e "$SOCK" || -S "$SOCK" ]] && socket_exists=true
plist_exists=false
[[ -e "$HELPER_PLIST" ]] && plist_exists=true
helperd_exists=false
[[ -e "$HELPERD" ]] && helperd_exists=true

ping_result="absent"
if [[ "$socket_exists" == true ]]; then
  ping_out=""
  ping_err=""
  ping_errfile="$(/usr/bin/mktemp /tmp/ntfsmount-diagnose-ping.XXXXXX 2>/dev/null || echo /tmp/ntfsmount-diagnose-ping.$$)"
  ping_out="$(/usr/bin/python3 - "$SOCK" <<'PY' 2>"$ping_errfile" || true
import socket, sys
path = sys.argv[1]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(2)
try:
    s.connect(path)
    s.sendall(b"v1 1\nversion\n")
    s.shutdown(socket.SHUT_WR)
    data = b""
    while True:
        chunk = s.recv(4096)
        if not chunk:
            break
        data += chunk
        if len(data) > 8192:
            break
    sys.stdout.write(data.decode("utf-8", "replace"))
except Exception as e:
    sys.stderr.write(str(e))
    sys.exit(1)
PY
)"
  ping_err="$(/bin/cat "$ping_errfile" 2>/dev/null || true)"
  /bin/rm -f "$ping_errfile"
  ping_out="$(oneline "$ping_out")"
  ping_err="$(oneline "$ping_err")"
  if [[ -n "$ping_out" ]]; then
    if printf '%s' "$ping_out" | /usr/bin/grep -q '调用方未通过签名校验'; then
      ping_result="alive_caller_rejected"
    elif printf '%s' "$ping_out" | /usr/bin/grep -q 'HELPER_VERSION='; then
      ping_result="$(printf '%s' "$ping_out" | /usr/bin/tr -d '\r')"
    else
      ping_result="response: $ping_out"
    fi
  elif [[ -n "$ping_err" ]]; then
    ping_result="connect_failed: $ping_err"
  else
    ping_result="connect_failed: unknown"
  fi
fi

# --- vmnet / FUSE-T 相关守护进程 ---
# 本项目用捆绑 go-nfsv4 本机 NFS，不是 ntfsmac 那种 vmnet 微虚拟机。
# 仍按截图探测 bridge/vmnet，但诚实标注「不依赖」。
vmnet_ifaces_json="[]"
vmnet_status="absent"
vmnet_human_ifaces="无"
iface_list="$(timeout_run 3 /sbin/ifconfig -l || true)"
iface_list="$(oneline "$iface_list")"
vmnet_bits=""
if [[ -n "$iface_list" && "$iface_list" != "unknown" ]]; then
  for iface in $iface_list; do
    case "$iface" in
      vmnet*|vmenet*|bridge10*|bridge11*)
        flags="$(timeout_run 2 /sbin/ifconfig "$iface" || true)"
        flags="$(printf '%s' "$flags" | /usr/bin/head -1 || true)"
        flags="$(oneline "$flags")"
        up=false
        printf '%s' "$flags" | /usr/bin/grep -qw UP && up=true
        if [[ -n "$vmnet_bits" ]]; then
          vmnet_bits="$vmnet_bits,"
        fi
        vmnet_bits="${vmnet_bits}{\"name\":$(json_str "$iface"),\"up\":$up,\"flags\":$(json_str "$flags")}"
        if [[ "$up" == true ]]; then
          vmnet_status="up"
        elif [[ "$vmnet_status" != "up" ]]; then
          vmnet_status="down"
        fi
        ;;
    esac
  done
else
  vmnet_status="unknown"
fi
if [[ -n "$vmnet_bits" ]]; then
  vmnet_ifaces_json="[$vmnet_bits]"
  vmnet_human_ifaces="$(/usr/bin/python3 -c 'import json,sys; arr=json.loads(sys.argv[1]); print(", ".join("%s/%s"% (x.get("name","?"), "up" if x.get("up") else "down") for x in arr) or "无")' "$vmnet_ifaces_json" 2>/dev/null || echo "见 JSON")"
fi

lc_fuse="$(timeout_run 3 /bin/launchctl list || true)"
lc_hits="$(printf '%s\n' "$lc_fuse" | /usr/bin/grep -iE 'vmnet|fuse-t|fuset|nfsd|com\.apple\.nfs' || true)"
lc_json="[]"
if [[ -n "$lc_hits" ]]; then
  lc_json="$(printf '%s\n' "$lc_hits" | /usr/bin/python3 -c 'import json,sys; lines=[ln.strip() for ln in sys.stdin if ln.strip()]; print(json.dumps(lines, ensure_ascii=False, separators=(",", ":")))')"
fi

# --- NFS ---
nfsd_out="$(timeout_run 3 /sbin/nfsd status || true)"
nfsd_out_line="$(oneline "$nfsd_out")"
nfsd_enabled=false
nfsd_running=false
if printf '%s' "$nfsd_out" | /usr/bin/grep -q 'service is enabled'; then
  nfsd_enabled=true
fi
if printf '%s' "$nfsd_out" | /usr/bin/grep -q 'nfsd is running' && \
   ! printf '%s' "$nfsd_out" | /usr/bin/grep -q 'nfsd is not running'; then
  nfsd_running=true
fi
if [[ -z "$nfsd_out_line" ]]; then
  nfsd_out_line="unknown"
fi

nfsstat_out="$(timeout_run 3 /usr/bin/nfsstat -m || true)"
nfsstat_line="$(oneline "$nfsstat_out")"
[[ -n "$nfsstat_line" ]] || nfsstat_line=""

showmount_out="$(timeout_run 3 /usr/bin/showmount -e localhost || true)"
showmount_line="$(oneline "$showmount_out")"
if [[ -z "$showmount_line" ]]; then
  showmount_line="timeout_or_empty"
fi

go_procs="$(timeout_run 3 /usr/bin/pgrep -lf go-nfsv4 || true)"
go_procs_json="[]"
if [[ -n "$go_procs" ]]; then
  go_procs_json="$(printf '%s\n' "$go_procs" | /usr/bin/python3 -c 'import json,sys; lines=[ln.strip() for ln in sys.stdin if ln.strip()]; print(json.dumps(lines, ensure_ascii=False, separators=(",", ":")))')"
fi
go_proc_count="$(printf '%s\n' "$go_procs" | /usr/bin/grep -c . || true)"
[[ -n "$go_proc_count" ]] || go_proc_count=0

listen_json="[]"
if [[ -n "$go_procs" ]]; then
  listen_out="$(timeout_run 3 /usr/sbin/lsof -nP -iTCP -sTCP:LISTEN || true)"
  listen_hits="$(printf '%s\n' "$listen_out" | /usr/bin/grep -i 'go-nfsv4' || true)"
  if [[ -n "$listen_hits" ]]; then
    listen_json="$(printf '%s\n' "$listen_hits" | /usr/bin/python3 -c 'import json,sys; lines=[ln.strip() for ln in sys.stdin if ln.strip()]; print(json.dumps(lines[:12], ensure_ascii=False, separators=(",", ":")))')"
  fi
fi

# --- 挂载点 + 占用 ---
mount_text="$(timeout_run 3 /sbin/mount || true)"
diskutil_list="$(timeout_run 15 /usr/sbin/diskutil list || true)"

occupier_for() {
  local mp="$1"
  local out errfile names
  errfile="$(/usr/bin/mktemp /tmp/ntfsmount-lsof.XXXXXX 2>/dev/null || echo /tmp/ntfsmount-lsof.$$)"
  out="$(/usr/bin/perl -e 'alarm shift; exec @ARGV' 3 /usr/sbin/lsof -nP "$mp" 2>"$errfile" || true)"
  names="$(printf '%s\n' "$out" | /usr/bin/awk 'NR>1 && $1 != "lsof" { print $1 }' | /usr/bin/sort -u | /usr/bin/head -8 || true)"
  names="$(printf '%s' "$names" | /usr/bin/tr '\n' ',' | /usr/bin/sed -e 's/,$//' -e 's/,/, /g')"
  err="$(oneline "$(/bin/cat "$errfile" 2>/dev/null || true)")"
  /bin/rm -f "$errfile"
  if [[ -n "$names" ]]; then
    printf '%s' "$names"
  elif printf '%s' "$err" | /usr/bin/grep -qiE 'permission denied|not permitted|Operation not permitted'; then
    printf '%s' "permission_denied"
  elif [[ -n "$err" ]]; then
    printf '%s' "error: $err"
  else
    printf '%s' ""
  fi
}

mounts_bits=""
mounts_human=""
add_mount() {
  local device="$1" fs="$2" mp="$3" kind="$4"
  local occ item
  occ=""
  if [[ -n "$mp" && "$mp" != "not mounted" ]]; then
    occ="$(occupier_for "$mp")"
  fi
  item="{\"device\":$(json_str "$device"),\"filesystem\":$(json_str "$fs"),\"mount_point\":$(json_str "$mp"),\"kind\":$(json_str "$kind"),\"occupancy\":$(json_str "$occ")}"
  if [[ -n "$mounts_bits" ]]; then
    mounts_bits="$mounts_bits,"
  fi
  mounts_bits="$mounts_bits$item"
  if [[ -z "$occ" ]]; then
    occ="无"
  fi
  mounts_human="${mounts_human}  ${device}  ${mp}  (${kind}/${fs})  占用: ${occ}"$'\n'
}

# diskutil NTFS 卷
while IFS= read -r ident; do
  [[ "$ident" == disk* ]] || continue
  info="$(timeout_run 8 /usr/sbin/diskutil info -plist "$ident" || true)"
  [[ -n "$info" ]] || continue
  fs="$(printf '%s' "$info" | /usr/bin/plutil -extract FilesystemName raw - 2>/dev/null || true)"
  [[ "$fs" == "NTFS" ]] || continue
  mp="$(printf '%s' "$info" | /usr/bin/plutil -extract MountPoint raw - 2>/dev/null || true)"
  mp="$(trim "${mp:-}")"
  [[ -n "$mp" ]] || mp="not mounted"
  kind="ntfs"
  mline="$(printf '%s\n' "$mount_text" | /usr/bin/grep -F " on ${mp} " || true)"
  if printf '%s' "$mline" | /usr/bin/grep -qiE 'ntfs-3g|fuse-t|fuset|macfuse|osxfuse| fuse,|\(nfs,'; then
    kind="fuse"
  fi
  add_mount "$ident" "NTFS" "$mp" "$kind"
done < <(printf '%s\n' "$diskutil_list" | /usr/bin/awk '/^[[:space:]]+[0-9]+:/{print $NF}')

# mount 表里有但 diskutil 没标 NTFS 的 FUSE/NFS 行
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  lower="$(printf '%s' "$line" | /usr/bin/tr '[:upper:]' '[:lower:]')"
  printf '%s' "$lower" | /usr/bin/grep -qE 'ntfs-3g|fuse-t|fuset|macfuse|osxfuse| fuse,| \(nfs,' || continue
  device="$(printf '%s' "$line" | /usr/bin/awk '{print $1}')"
  mp="$(printf '%s' "$line" | /usr/bin/sed -e 's/.* on \(.*\) (.*/\1/')"
  already=0
  if [[ -n "$mounts_bits" ]]; then
    printf '%s' "$mounts_bits" | /usr/bin/grep -q "$(json_str "$mp")" && already=1
  fi
  [[ "$already" -eq 0 ]] || continue
  kind="fuse"
  printf '%s' "$lower" | /usr/bin/grep -q 'nfs' && kind="nfs"
  add_mount "$device" "fuse-or-nfs" "$mp" "$kind"
done < <(printf '%s\n' "$mount_text")

mounts_json="[]"
[[ -n "$mounts_bits" ]] && mounts_json="[$mounts_bits]"
[[ -n "$mounts_human" ]] || mounts_human="  （无 NTFS / FUSE 挂载）"$'\n'

# --- BitLocker：macOS 看不到 Windows 解锁状态；只报 diskutil 线索 ---
bl_bits=""
bl_status="not_seen"
bl_human="未见 diskutil 加密线索（macOS 无法确认 BitLocker，这不是阴性证明）"
while IFS= read -r ident; do
  [[ "$ident" == disk* ]] || continue
  info="$(timeout_run 8 /usr/sbin/diskutil info "$ident" || true)"
  [[ -n "$info" ]] || continue
  content="$(printf '%s' "$info" | /usr/bin/awk -F': *' '/Partition Type:|Content \(IOContent\):|Type \(Bundle\):/{print $2; exit}')"
  content="$(trim "$content")"
  person="$(printf '%s' "$info" | /usr/bin/awk -F': *' '/File System Personality:/{print $2; exit}')"
  person="$(trim "$person")"
  enc="$(printf '%s' "$info" | /usr/bin/awk -F': *' '/^ *Encrypted:/{print $2; exit}')"
  enc="$(trim "$enc")"
  vol="$(printf '%s' "$info" | /usr/bin/awk -F': *' '/Volume Name:/{print $2; exit}')"
  vol="$(trim "$vol")"
  hint=""
  info_l="$(printf '%s' "$info" | /usr/bin/tr '[:upper:]' '[:lower:]')"
  if printf '%s' "$info_l" | /usr/bin/grep -q 'bitlocker'; then
    hint="bitlocker_string"
  elif [[ "$enc" == "Yes" ]] && printf '%s' "$info_l" | /usr/bin/grep -qiE 'ntfs|microsoft|windows'; then
    hint="encrypted_windows_partition"
  elif printf '%s' "$content" | /usr/bin/grep -qi 'Microsoft Basic Data' && \
       [[ "$person" != "NTFS" && -z "$person" ]]; then
    hint="microsoft_basic_data_unrecognized"
  fi
  [[ -n "$hint" ]] || continue
  bl_status="possible"
  item="{\"device\":$(json_str "$ident"),\"hint\":$(json_str "$hint"),\"content\":$(json_str "$content"),\"filesystem\":$(json_str "$person"),\"encrypted\":$(json_str "${enc:-unknown}"),\"volume_name\":$(json_str "$vol")}"
  if [[ -n "$bl_bits" ]]; then
    bl_bits="$bl_bits,"
  fi
  bl_bits="$bl_bits$item"
done < <(printf '%s\n' "$diskutil_list" | /usr/bin/awk '/^[[:space:]]+[0-9]+:/{print $NF}')
bl_json="[]"
[[ -n "$bl_bits" ]] && bl_json="[$bl_bits]"
if [[ "$bl_status" == "possible" ]]; then
  bl_human="可能加密（仅 diskutil 线索，不能当作已确认的 BitLocker）"
fi
if [[ -z "$diskutil_list" ]]; then
  bl_status="unknown"
  bl_human="diskutil list 失败或超时（unknown）"
fi

vmnet_note="This project uses bundled FUSE-T go-nfsv4 over local NFS, not a vmnet microVM. Absent/down vmnet is expected."
nfs_note="FUSE-T does not use system nfsd; go-nfsv4 is spawned per mount. nfsd not running is expected."
bitlocker_note="macOS diskutil cannot reliably confirm BitLocker without Windows. not_seen is not a true negative."

fuse_t_json="$(json_obj "{\"system_app\":$system_app,\"system_bin_dir\":$(json_str "$FUSE_T_BIN"),\"system_go_nfsv4\":$(json_str "$system_go"),\"system_version\":$(json_str "$system_fuse_ver"),\"bundled_go_nfsv4\":$(json_str "$bundled_go"),\"bundled_present\":$bundled_present,\"pinned_version\":$(json_str "$pinned_fuse_t")}")"
helper_json="$(json_obj "{\"socket_path\":$(json_str "$SOCK"),\"socket_exists\":$socket_exists,\"daemon_plist_exists\":$plist_exists,\"helperd_exists\":$helperd_exists,\"bundled_helper_version\":$(json_str "$helper_version"),\"ping\":$(json_str "$ping_result")}")"
vmnet_json="$(json_obj "{\"status\":$(json_str "$vmnet_status"),\"interfaces\":$vmnet_ifaces_json,\"launchctl\":$lc_json,\"note\":$(json_str "$vmnet_note")}")"
nfs_json="$(json_obj "{\"nfsd_enabled\":$nfsd_enabled,\"nfsd_running\":$nfsd_running,\"nfsd_status\":$(json_str "$nfsd_out_line"),\"nfsstat\":$(json_str "$nfsstat_line"),\"showmount\":$(json_str "$showmount_line"),\"go_nfsv4_processes\":$go_procs_json,\"localhost_listeners\":$listen_json,\"note\":$(json_str "$nfs_note")}")"
bitlocker_json="$(json_obj "{\"status\":$(json_str "$bl_status"),\"volumes\":$bl_json,\"note\":$(json_str "$bitlocker_note")}")"

if [[ "$JSON" -eq 1 ]]; then
  /usr/bin/python3 -c 'import json,sys
keys=["schema_version","app_version","installed_app_version","macos_product_name","macos_version","macos_build","hw_model","arch","apple_silicon","chip","fuse_t","helper","vmnet","nfs","mounts","bitlocker"]
vals=sys.argv[1:]
obj={"schema_version":1}
for k,v in zip(keys[1:], vals):
    if k in ("apple_silicon",):
        obj[k] = (v == "true")
    elif k in ("fuse_t","helper","vmnet","nfs","bitlocker") or k=="mounts":
        obj[k] = json.loads(v) if v else None
    else:
        obj[k] = v
json.dump(obj, sys.stdout, ensure_ascii=False, indent=2)
print()' \
    "$app_version" \
    "${installed_version}" \
    "$macos_product" \
    "$macos_version" \
    "$macos_build" \
    "$hw_model" \
    "$arch" \
    "$apple_silicon" \
    "$chip" \
    "$fuse_t_json" \
    "$helper_json" \
    "$vmnet_json" \
    "$nfs_json" \
    "$mounts_json" \
    "$bitlocker_json"
  exit 0
fi

# --- 人读（截图条目用中文标签） ---
silicon_h="$hw_model · $arch"
[[ "$chip" != "unknown" && -n "$chip" ]] && silicon_h="$silicon_h · $chip"
if [[ "$apple_silicon" != true ]]; then
  silicon_h="非 Apple Silicon（${arch} / ${hw_model}）；本应用不支持 Intel"
fi

vmnet_h="$vmnet_status"
if [[ "$vmnet_status" == "absent" ]]; then
  vmnet_h="absent（无 vmnet/vmenet/bridge100；本应用 FUSE-T 走本机 NFS，不依赖 vmnet）"
elif [[ "$vmnet_status" == "down" ]]; then
  vmnet_h="down（${vmnet_human_ifaces}；本应用不依赖 vmnet）"
elif [[ "$vmnet_status" == "up" ]]; then
  vmnet_h="up（${vmnet_human_ifaces}；本应用不依赖 vmnet）"
elif [[ "$vmnet_status" == "unknown" ]]; then
  vmnet_h="unknown（ifconfig 失败或权限不足）"
fi

nfs_h="系统 nfsd: "
if [[ "$nfsd_running" == true ]]; then
  nfs_h="${nfs_h}运行中"
elif [[ "$nfsd_enabled" == true ]]; then
  nfs_h="${nfs_h}已启用但未运行（FUSE-T 不依赖系统 nfsd）"
else
  nfs_h="${nfs_h}${nfsd_out_line}"
fi
nfs_h="${nfs_h}；go-nfsv4 进程 ${go_proc_count}"

helper_h="socket 不存在（未安装或未启动；本命令不会去安装）"
if [[ "$socket_exists" == true ]]; then
  case "$ping_result" in
    alive_caller_rejected) helper_h="socket 在，守护进程活着（CLI 无 App 签名，ping 被拒绝，属预期）" ;;
    HELPER_VERSION=*) helper_h="socket 在，ping ${ping_result}" ;;
    *) helper_h="socket 在，ping: ${ping_result}" ;;
  esac
fi

fuse_h="捆绑 go-nfsv4: "
if [[ "$bundled_present" == true ]]; then
  fuse_h="${fuse_h}有（${bundled_go}）"
else
  fuse_h="${fuse_h}无（需 ./scripts/prepare-runtime.sh）"
fi
if [[ -n "$system_go" ]]; then
  fuse_h="${fuse_h}；系统 FUSE-T: $system_fuse_ver"
else
  fuse_h="${fuse_h}；系统 FUSE-T: 未安装（应用不要求）"
fi

cat <<EOF
NTFSMount 诊断（只读，app ${app_version}）

• macOS 版本: ${macos_product} ${macos_version} (${macos_build})
• Apple Silicon 型号: ${silicon_h}
• vmnet 是否正常: ${vmnet_h}
• NFS 服务状态: ${nfs_h}
• 挂载点占用情况:
${mounts_human}• BitLocker 状态: ${bl_human}

助手: ${helper_h}
捆绑 HELPER_VERSION=${helper_version}
FUSE-T / go-nfsv4: ${fuse_h}

提交 Bug 或给 CI 收日志请附上本输出；机器可读: ./scripts/ntfsmount diagnose --json
EOF
