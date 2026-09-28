#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$ROOT/helper/ntfs-rw-helper"
[[ "$(/usr/bin/head -1 "$HELPER")" == "#!/bin/bash" ]] || { echo "ntfs-rw-helper must be in-repo bash source" >&2; exit 1; }
echo "helper sha256=$(/usr/bin/shasum -a 256 "$HELPER" | /usr/bin/awk '{print $1}')"

PRIV_SCAN=()
for f in "$ROOT"/helper/*.sh "$ROOT"/helper/ntfs-rw-helper "$ROOT"/scripts/*.sh "$ROOT"/uninstall.sh; do
  [[ -f "$f" ]] || continue
  [[ "${f##*/}" == "test-helper.sh" ]] && continue
  PRIV_SCAN+=("$f")
done
if /usr/bin/grep -nE 'ALL=\(root\) NOPASSWD' "${PRIV_SCAN[@]}" 2>/dev/null; then
  echo "scripts must not write sudoers NOPASSWD" >&2
  exit 1
fi
if /usr/bin/grep -nE 'sudo[[:space:]]+-S\b|SUDO_ASKPASS|[[:space:]]ASKPASS=|^ASKPASS=' "${PRIV_SCAN[@]}" 2>/dev/null; then
  echo "scripts must not feed sudo from stdin or set an ask-pass helper" >&2
  exit 1
fi
if /usr/bin/grep -nE 'echo[[:space:]].*\|[[:space:]]*sudo|printf[[:space:]].*\|[[:space:]]*sudo' "${PRIV_SCAN[@]}" 2>/dev/null; then
  echo "scripts must not pipe a secret into sudo" >&2
  exit 1
fi
# Literal password assignments only. Do not match NSAppleEventsUsageDescription or env names like APPLE_CERTIFICATE_PASSWORD.
if /usr/bin/grep -nE '(password|passwd|PASSWORD)[[:space:]]*=[[:space:]]*["'\''][^"'\'']+["'\'']' "${PRIV_SCAN[@]}" 2>/dev/null; then
  echo "scripts must not hardcode passwords" >&2
  exit 1
fi
if /usr/bin/grep -nE 'osascript|/usr/bin/sudo|[[:space:]]sudo[[:space:]]' \
  "$ROOT"/Sources/NTFSMount/VolumeStore.swift \
  "$ROOT"/Sources/NTFSMount/VolumeStore+Actions.swift 2>/dev/null; then
  echo "mount/unmount/format must go through the helper daemon, not sudo/osascript" >&2
  exit 1
fi
APP_SWIFT=()
while IFS= read -r f; do
  APP_SWIFT+=("$f")
done < <(/usr/bin/find "$ROOT/Sources/NTFSMount" "$ROOT/Sources/NTFSMountCore" -name '*.swift' -print)
if /usr/bin/grep -nE '/usr/bin/sudo|[[:space:]]sudo[[:space:]-]|sudo -S' "${APP_SWIFT[@]}" 2>/dev/null; then
  echo "app Sources must not contain sudo" >&2
  exit 1
fi
if /usr/bin/grep -nE 'osascript|do shell script' \
  "$ROOT/Sources/NTFSMount/Privileged.swift" \
  "$ROOT/Sources/NTFSMount/AdminAuthorization.swift" \
  "$ROOT/Sources/NTFSMount/VolumeStore.swift" \
  "$ROOT/Sources/NTFSMount/VolumeStore+Actions.swift" 2>/dev/null; then
  echo "helper install/uninstall must not use osascript" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'AuthorizationCreate' "$ROOT/Sources/NTFSMount/AdminAuthorization.swift"; then
  echo "ad-hoc helper install must call AuthorizationCreate" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'AuthorizationCopyRights' "$ROOT/Sources/NTFSMount/AdminAuthorization.swift"; then
  echo "ad-hoc helper install must call AuthorizationCopyRights" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'system.privilege.admin' "$ROOT/Sources/NTFSMount/AdminAuthorization.swift"; then
  echo "ad-hoc helper install must request kAuthorizationRightExecute" >&2
  exit 1
fi
if /usr/bin/grep -nE 'with administrator privileges' "$ROOT/uninstall.sh" "$ROOT/helper/install-helper.sh" "$ROOT/helper/uninstall-helper.sh"; then
  echo "user-facing install/uninstall must not use osascript administrator privileges" >&2
  exit 1
fi
if /usr/bin/grep -nE '[[:space:]]sudo[[:space:]]|/usr/bin/sudo|^sudo ' "$ROOT/uninstall.sh" "$ROOT/helper/install-helper.sh" "$ROOT/helper/uninstall-helper.sh"; then
  echo "user-facing install/uninstall scripts must not call sudo" >&2
  exit 1
fi
if /usr/bin/grep -nE 'csrutil[[:space:]]+disable|turn off SIP|关闭 SIP|disable SIP' \
  "$ROOT/README.md" "$ROOT/docs/DISTRIBUTION.md" "$ROOT/docs/DEVELOPMENT.md" \
  "$ROOT/CONTRIBUTING.md" "$ROOT/uninstall.sh" \
  "$ROOT"/Sources/NTFSMount/*.swift "$ROOT"/Sources/NTFSMount/Helpers/*.swift \
  "$ROOT"/Sources/NTFSMountCore/*.swift 2>/dev/null; then
  echo "must not document or script disabling SIP" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'SIP stays enabled' "$ROOT/README.md"; then
  echo "README must say SIP stays enabled" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'Authorization Services' "$ROOT/docs/DISTRIBUTION.md"; then
  echo "DISTRIBUTION.md must document Authorization Services fallback" >&2
  exit 1
fi
if /usr/bin/grep -n 'ln -sf' "$ROOT/helper/install-helper.sh"; then
  echo "install-helper must not recreate /usr/local/sbin symlink" >&2
  exit 1
fi
if /usr/bin/grep -n '/usr/bin/realpath' "$ROOT/helper/install-helper.sh"; then
  echo "install-helper must not invoke /usr/bin/realpath (macOS has no such binary)" >&2
  exit 1
fi
if /usr/bin/grep -nE '/(bin|usr/bin)/launchctl' "$ROOT/helper/install-helper.sh" "$ROOT/helper/uninstall-helper.sh" "$ROOT/helper/ntfs-rw-helper" "$ROOT/uninstall.sh" "$ROOT/scripts/ntfsmount-diagnose.sh" "$ROOT"/Sources/NTFSMount/*.swift "$ROOT"/Sources/NTFSMount/Helpers/*.swift; then
  echo "must resolve launchctl via resolve_cmd / CommandPath, not a hardcoded /bin or /usr/bin path" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'resolve_cmd launchctl' "$ROOT/helper/install-helper.sh"; then
  echo "install-helper must resolve launchctl at runtime" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'resolve_cmd bash' "$ROOT/helper/install-helper.sh"; then
  echo "install-helper must resolve bash at runtime for the LaunchDaemon Program" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'LAUNCHCTL" bootstrap' "$ROOT/helper/install-helper.sh"; then
  echo "install-helper must bootstrap the LaunchDaemon via resolved launchctl" >&2
  exit 1
fi

HELPERD_C="$ROOT/helper/ntfsmount-helperd.c"
if ! /usr/bin/grep -q '/Library/Application Support/NTFSMount' "$HELPERD_C"; then
  echo "helperd must pin files under Application Support" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'HELPER_SEALED' "$HELPERD_C"; then
  echo "helperd must exec the root-owned sealed helper" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'SecCodeCheckValidity' "$HELPERD_C"; then
  echo "helperd must call SecCodeCheckValidity on the peer" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'SecStaticCodeCheckValidity' "$HELPERD_C"; then
  echo "helperd must call SecStaticCodeCheckValidity on the peer" >&2
  exit 1
fi
if /usr/bin/grep -qF '(void)validity_ok' "$HELPERD_C"; then
  echo "helperd must require SecCodeCheckValidity, not ignore validity_ok" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'if (!validity_ok)' "$HELPERD_C"; then
  echo "helperd must reject peers that fail CheckValidity" >&2
  exit 1
fi
if /usr/bin/grep -nE 'snprintf\(helper,.*Contents/Resources/ntfs-rw-helper' "$HELPERD_C"; then
  echo "helperd must not exec the user-writable .app helper" >&2
  exit 1
fi
if /usr/bin/awk '
  $0 ~ /static void handle\(/ { inh=1 }
  inh && $0 ~ /^int main\(/ { inh=0 }
  inh && /ensure_sealed/ { found=1 }
  END { exit found ? 0 : 1 }
' "$HELPERD_C"; then
  echo "handle must not recopy the helper from a user-writable .app" >&2
  exit 1
fi
if /usr/bin/grep -q 'stored_cdhash_matches_app' "$HELPERD_C"; then
  echo "helperd must not re-pin from the live .app CDHash" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'allowed.cdhash' "$HELPERD_C"; then
  echo "helperd must compare stored allowed.cdhash" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'AuthorizationCreate' "$ROOT/Sources/NTFSMount/AdminAuthorization.swift" \
  || ! /usr/bin/grep -q 'sealedHelperMatchesBundle' "$ROOT/Sources/NTFSMount/Privileged.swift"; then
  echo "SMAppService install must confirm sealed helper pins; ad-hoc uses Authorization Services" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'kickstartUntilSocket' "$ROOT/Sources/NTFSMount/Privileged.swift"; then
  echo "installHelper must kickstart until the socket exists" >&2
  exit 1
fi
for key in 'app.path' 'allowed.cdhash' 'helper.stamp' 'ntfs-rw-helper'; do
  /usr/bin/grep -q "$key" "$ROOT/helper/install-helper.sh" || {
    echo "install-helper must write $key" >&2
    exit 1
  }
done
if ! /usr/bin/grep -q '无法读取应用 CDHash' "$ROOT/helper/install-helper.sh"; then
  echo "install-helper must refuse an empty CDHash" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'AssociatedBundleIdentifiers' "$ROOT/helper/install-helper.sh"; then
  echo "install-helper plist must include AssociatedBundleIdentifiers" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'resolve_cmd bash' "$ROOT/helper/install-helper.sh" || ! /usr/bin/grep -q 'run-helperd.sh' "$ROOT/helper/install-helper.sh"; then
  echo "ad-hoc LaunchDaemon must spawn via resolved bash run-helperd.sh" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'xattr -cr' "$ROOT/helper/install-helper.sh"; then
  echo "install-helper must strip quarantine from copied helper binaries" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'Signature=adhoc' "$ROOT/helper/install-helper.sh"; then
  echo "install-helper must re-sign ad-hoc helperd without Hardened Runtime" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'socket 未出现' "$ROOT/helper/install-helper.sh"; then
  echo "install-helper must fail when the helper socket never appears" >&2
  exit 1
fi
if /usr/bin/grep -nF 'ntfs-3g /dev/${ident}"' "$HELPER"; then
  echo "do_format must not pkill a diskN prefix that matches disk40" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'kill_ntfs3g_whole' "$HELPER"; then
  echo "do_format must reuse kill_ntfs3g so disk4 does not match disk40" >&2
  exit 1
fi
if /usr/bin/awk '
  $0 ~ /^installed_helper_path\(\)/ { inh=1 }
  inh && $0 ~ /^[a-z_]+\(\)/ && $0 !~ /^installed_helper_path\(\)/ { inh=0 }
  inh && /Contents\/Resources\/ntfs-rw-helper/ { found=1 }
  END { exit found ? 0 : 1 }
' "$HELPER"; then
  echo "automount must not exec the user-writable .app helper" >&2
  exit 1
fi
if /usr/bin/grep -q 'daemonTimeoutSec' "$ROOT/Sources/NTFSMount/Privileged.swift"; then
  echo "Privileged must not use daemonTimeoutSec; timeouts live in HelperIpc.recvTimeoutSec" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'HelperIpc.recvTimeoutSec' "$ROOT/Sources/NTFSMount/Privileged.swift"; then
  echo "Privileged must use HelperIpc.recvTimeoutSec" >&2
  exit 1
fi
if ! /usr/bin/awk '
  /func recvTimeoutSec/ { inh=1 }
  inh && /case "format", "fix", "ntfsfix": return 600/ { long=1 }
  inh && /default: return 180/ { def=1 }
  END { exit (long && def) ? 0 : 1 }
' "$ROOT/Sources/NTFSMountCore/HelperIpc.swift"; then
  echo "HelperIpc.recvTimeoutSec must be 600 for format/fix/ntfsfix and 180 otherwise" >&2
  exit 1
fi
wait_sec="$(/usr/bin/awk '/^#define WAIT_SEC /{ print $3; exit }' "$HELPERD_C")"
wait_long="$(/usr/bin/awk '/^#define WAIT_SEC_LONG /{ print $3; exit }' "$HELPERD_C")"
if [[ "$wait_sec" != "180" || "$wait_long" != "600" ]]; then
  echo "helperd WAIT_SEC must be 180 and WAIT_SEC_LONG 600, got: ${wait_sec:-missing} ${wait_long:-missing}" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'HEARTBEAT_TENTHS' "$HELPERD_C"; then
  echo "helperd must heartbeat during long helper runs" >&2
  exit 1
fi

# Issue #1: do_automount 不得用 volume_still_mounted 作为唯一入口（未挂载外置 NTFS 也要挂）。
if /usr/bin/awk '
  $0 ~ /^do_automount\(\)/ { inh=1 }
  inh && $0 ~ /^[a-z_]+\(\)/ && $0 !~ /^do_automount\(\)/ { inh=0 }
  inh && $0 !~ /^[[:space:]]*#/ && /volume_still_mounted/ { found=1 }
  END { exit found ? 0 : 1 }
' "$HELPER"; then
  echo "do_automount must not skip unmounted volumes via volume_still_mounted" >&2
  exit 1
fi
if /usr/bin/awk '
  $0 ~ /^do_automount\(\)/ { inh=1 }
  inh && $0 ~ /^[a-z_]+\(\)/ && $0 !~ /^do_automount\(\)/ { inh=0 }
  inh && $0 !~ /^[[:space:]]*#/ && /ntfsfix|remove_hiberfile|do_fix|do_format/ { found=1 }
  END { exit found ? 0 : 1 }
' "$HELPER"; then
  echo "do_automount must not auto-ntfsfix, clear hiberfile, or format" >&2
  exit 1
fi
if /usr/bin/grep -nE 'DISKUTIL" repairVolume|DISKUTIL repairVolume' "$HELPER"; then
  echo "helper must not run diskutil repairVolume" >&2
  exit 1
fi
if /usr/bin/awk '
  $0 ~ /^do_probe\(\)/ { inh=1 }
  inh && $0 ~ /^[a-z_]+\(\)/ && $0 !~ /^do_probe\(\)/ { inh=0 }
  inh && $0 !~ /^[[:space:]]*#/ && /ntfsfix -d|repairVolume|remove_hiberfile|verifyVolume/ { found=1 }
  END { exit found ? 0 : 1 }
' "$HELPER"; then
  echo "do_probe must only run ntfsfix -n; no repair, verifyVolume, or hiberfile clear" >&2
  exit 1
fi
if ! /usr/bin/awk '
  $0 ~ /^do_probe\(\)/ { inh=1 }
  inh && $0 ~ /^[a-z_]+\(\)/ && $0 !~ /^do_probe\(\)/ { inh=0 }
  inh && /NTFSFIX" -n/ { found=1 }
  END { exit found ? 0 : 1 }
' "$HELPER"; then
  echo "do_probe must run ntfsfix -n" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'helper_automount_should_run 0 0 0' "$HELPER"; then
  echo "selftest must cover unmounted automount eligibility" >&2
  exit 1
fi

# 优雅卸载：umount -f 不得再出现。diskutil unmount force 仅 try_unmount_target（ALLOW_FORCE）与 format。
# 注释里写「不 umount -f」不算调用。
if /usr/bin/awk '
  /^[[:space:]]*#/ { next }
  /\$UMOUNT"[[:space:]]+-f|"\$UMOUNT" -f|[[:space:]]umount[[:space:]]+-f/ { found=1 }
  END { exit found ? 0 : 1 }
' "$HELPER"; then
  echo "helper must not call umount -f; use diskutil unmount / unmount force" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'ALLOW_FORCE=0' "$HELPER"; then
  echo "helper ALLOW_FORCE must default to 0" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'log_force_warning' "$HELPER"; then
  echo "helper must log WARNING when force unmount is used" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'resolve_cmd lsof' "$HELPER"; then
  echo "helper must resolve lsof from system dirs" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'resolve_cmd fuser' "$HELPER"; then
  echo "helper must resolve fuser from system dirs" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'guard_unmount_busy' "$HELPER"; then
  echo "helper must probe occupiers before unmount" >&2
  exit 1
fi
if ! /usr/bin/awk '
  $0 ~ /^unmount_any\(\)/ { inh=1 }
  inh && $0 ~ /^[a-z_]+\(\)/ && $0 !~ /^unmount_any\(\)/ { inh=0 }
  inh && /guard_unmount_busy/ { probed=1 }
  inh && probed==0 && /try_unmount_target|DISKUTIL.*unmount/ { bad=1 }
  END { exit (probed && !bad) ? 0 : 1 }
' "$HELPER"; then
  echo "unmount_any must call lsof/fuser busy probe before diskutil unmount" >&2
  exit 1
fi
if ! /usr/bin/awk '
  $0 ~ /^do_unmount\(\)/ { inh=1 }
  inh && $0 ~ /^[a-z_]+\(\)/ && $0 !~ /^do_unmount\(\)/ { inh=0 }
  inh && /guard_unmount_busy/ { probed=1 }
  inh && probed==0 && /unmount_any|DISKUTIL.*unmount/ { bad=1 }
  END { exit (probed && !bad) ? 0 : 1 }
' "$HELPER"; then
  echo "do_unmount must probe occupiers before unmount_any/diskutil" >&2
  exit 1
fi
if ! /usr/bin/awk '
  $0 ~ /^do_eject\(\)/ { inh=1 }
  inh && $0 ~ /^[a-z_]+\(\)/ && $0 !~ /^do_eject\(\)/ { inh=0 }
  inh && /guard_unmount_busy/ { probed=1 }
  inh && probed==0 && /kill_ntfs3g|unmount_any|DISKUTIL/ { bad=1 }
  END { exit (probed && !bad) ? 0 : 1 }
' "$HELPER"; then
  echo "do_eject must probe occupiers before kill/unmount/eject" >&2
  exit 1
fi
if ! /usr/bin/awk '
  $0 ~ /^ensure_unmounted\(\)/ { inh=1 }
  inh && $0 ~ /^[a-z_]+\(\)/ && $0 !~ /^ensure_unmounted\(\)/ { inh=0 }
  inh && /guard_unmount_busy/ { probed=1 }
  inh && probed==0 && /unmount_any|DISKUTIL.*unmount/ { bad=1 }
  END { exit (probed && !bad) ? 0 : 1 }
' "$HELPER"; then
  echo "ensure_unmounted (probe/automount/mount) must probe occupiers before unmount" >&2
  exit 1
fi
if ! /usr/bin/awk '
  $0 ~ /^repair_graceful_unmount_ident\(\)/ { inh=1 }
  inh && $0 ~ /^[a-z_]+\(\)/ && $0 !~ /^repair_graceful_unmount_ident\(\)/ { inh=0 }
  inh && /probe_mp_occupiers/ { probed=1 }
  inh && probed==0 && /try_unmount_target|DISKUTIL.*unmount/ { bad=1 }
  END { exit (probed && !bad) ? 0 : 1 }
' "$HELPER"; then
  echo "repair-env unmount must probe occupiers before diskutil" >&2
  exit 1
fi
if ! /usr/bin/awk '
  $0 ~ /^try_unmount_target\(\)/ { inh=1 }
  inh && $0 ~ /^[a-z_]+\(\)/ && $0 !~ /^try_unmount_target\(\)/ { inh=0 }
  inh && /probe_mp_occupiers/ { probed=1 }
  inh && probed==0 && /DISKUTIL.*unmount/ { bad=1 }
  END { exit (probed && !bad) ? 0 : 1 }
' "$HELPER"; then
  echo "try_unmount_target must probe occupiers before diskutil unmount" >&2
  exit 1
fi
if ! /usr/bin/awk '
  $0 ~ /^try_unmount_target\(\)/ { inh=1 }
  inh && $0 ~ /^[a-z_]+\(\)/ && $0 !~ /^try_unmount_target\(\)/ { inh=0 }
  inh && /DISKUTIL" unmount force/ { found=1 }
  END { exit found ? 0 : 1 }
' "$HELPER"; then
  echo "try_unmount_target must be the volume force-unmount gate" >&2
  exit 1
fi
for fn in do_automount do_probe do_mount ensure_unmounted do_eject probe_volume_state do_repair_env; do
  if /usr/bin/awk -v fn="$fn" '
    $0 ~ "^" fn "\\(\\)" { inh=1 }
    inh && $0 ~ /^[a-z_]+\(\)/ && index($0, fn "(") != 1 { inh=0 }
    inh && $0 !~ /^[[:space:]]*#/ && /ALLOW_FORCE=1|unmount force|unmountDisk force/ { found=1 }
    END { exit found ? 0 : 1 }
  ' "$HELPER"; then
    echo "$fn must not enable force unmount" >&2
    exit 1
  fi
done
if ! /usr/bin/awk '
  $0 ~ /^do_unmount\(\)/ { inh=1 }
  inh && $0 ~ /^[a-z_]+\(\)/ && $0 !~ /^do_unmount\(\)/ { inh=0 }
  inh && /mode" == "force"/ { found=1 }
  END { exit found ? 0 : 1 }
' "$HELPER"; then
  echo "do_unmount must set ALLOW_FORCE only when the extra arg is force" >&2
  exit 1
fi
STORE=(
  "$ROOT/Sources/NTFSMount/VolumeStore.swift"
  "$ROOT/Sources/NTFSMount/VolumeStore+Actions.swift"
)
if ! /usr/bin/grep -q 'confirmForceUnmount' "${STORE[@]}"; then
  echo "VolumeStore must confirm force unmount (Cancel default) before extra force" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'extra: \["force"\]' "${STORE[@]}"; then
  echo "VolumeStore must send unmount force only as an explicit extra arg" >&2
  exit 1
fi
if /usr/bin/grep -nE 'run\("probe".*force|run\("automount".*force|run\("mount".*force|run\("eject".*force|run\("fix".*force|run\("repair-env".*force' "${STORE[@]}"; then
  echo "probe/automount/mount/eject/fix/repair-env must not send force" >&2
  exit 1
fi
if ! /usr/bin/grep -q '!probe.ok' "${STORE[@]}"; then
  echo "probeThenMount must fail closed when probe cannot unmount" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'restoreSystemMount' "${STORE[@]}"; then
  echo "VolumeStore must restore the system mount after a cancelled/failed probe" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'static let forceUnmount' "$ROOT/Sources/NTFSMountCore/AlertDefaultPolicy.swift"; then
  echo "force unmount confirm must use Cancel-default policy" >&2
  exit 1
fi
if ! /usr/bin/awk '
  $0 ~ /func confirmForceUnmount\(/ { inh=1 }
  inh && $0 ~ /^  (private )?func / && $0 !~ /func confirmForceUnmount\(/ { inh=0 }
  inh && /makeCancelDefault/ { found=1 }
  END { exit found ? 0 : 1 }
' "${STORE[@]}"; then
  echo "confirmForceUnmount must make Cancel the default button" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'repair-env' "$HELPERD_C"; then
  echo "helperd must allow repair-env" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'do_repair_env' "$HELPER"; then
  echo "helper must implement do_repair_env" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'repair-env) do_repair_env' "$HELPER"; then
  echo "helper must dispatch repair-env" >&2
  exit 1
fi
if /usr/bin/awk '
  $0 ~ /^do_repair_env\(\)/ { inh=1 }
  inh && $0 ~ /^[a-z_]+\(\)/ && $0 !~ /^do_repair_env\(\)/ { inh=0 }
  inh && $0 !~ /^[[:space:]]*#/ && /pfctl|\/etc\/pf\.conf|vmnet|ALLOW_FORCE=1|unmount force|unmountDisk force|umount[[:space:]]+-f|remove_hiberfile|repairVolume/ { found=1 }
  END { exit found ? 0 : 1 }
' "$HELPER"; then
  echo "do_repair_env must not reset pf, recycle vmnet, force unmount, clear hiberfile, or repairVolume" >&2
  exit 1
fi
if /usr/bin/grep -nE 'pfctl|/etc/pf.conf|vmnet' "${STORE[@]}" \
    "$ROOT/Sources/NTFSMount/Privileged.swift" \
    "$ROOT/Sources/NTFSMount/UI/DiagnoseAlert.swift" \
    "$ROOT/Sources/NTFSMount/UI/MenuRoot.swift" \
    "$ROOT/Sources/NTFSMountCore/FormatPolicy.swift"; then
  echo "repair UI/helper client must not call pfctl or vmnet" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'confirmRepairMountEnvironment' "${STORE[@]}"; then
  echo "VolumeStore must confirm Repair Mount Environment" >&2
  exit 1
fi
if ! /usr/bin/awk '
  $0 ~ /func confirmRepairMountEnvironment\(/ { inh=1 }
  inh && $0 ~ /^  (private )?func / && $0 !~ /func confirmRepairMountEnvironment\(/ { inh=0 }
  inh && /makeCancelDefault/ { found=1 }
  END { exit found ? 0 : 1 }
' "${STORE[@]}"; then
  echo "confirmRepairMountEnvironment must make Cancel the default button" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'Privileged.run("repair-env"' "${STORE[@]}"; then
  echo "VolumeStore must run helper repair-env" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'restartHelper' "${STORE[@]}"; then
  echo "VolumeStore must restart the helper after repair-env" >&2
  exit 1
fi
if /usr/bin/awk '
  $0 ~ /func repairMountEnvironment\(/ { inh=1 }
  inh && $0 ~ /^  func / && $0 !~ /func repairMountEnvironment\(/ { inh=0 }
  inh && /confirmForceUnmount|extra: \["force"\]|umount -f|pfctl|vmnet/ { found=1 }
  END { exit found ? 0 : 1 }
' "${STORE[@]}"; then
  echo "repairMountEnvironment must not force unmount, reset pf, or recycle vmnet" >&2
  exit 1
fi
if /usr/bin/grep -nE '修复挂载|未能修复挂载|正在修复挂载' \
    "${STORE[@]}" \
    "$ROOT/Sources/NTFSMount/UI/DiagnoseAlert.swift" \
    "$ROOT/Sources/NTFSMount/UI/MenuRoot.swift" \
    "$ROOT/Sources/NTFSMountCore/FormatPolicy.swift"; then
  echo "repair UI copy must go through L10n, not Chinese literals" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'RepairMountCopy.userMessage' "${STORE[@]}"; then
  echo "VolumeStore must surface repair results via RepairMountCopy.userMessage" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'static let repairMount' "$ROOT/Sources/NTFSMountCore/AlertDefaultPolicy.swift"; then
  echo "repair confirm must use Cancel-default policy" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'menu.repairEnv' "$ROOT/Sources/NTFSMount/UI/MenuRoot.swift"; then
  echo "menu must offer Repair Mount Environment" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'menu.repairEnv' "$ROOT/Sources/NTFSMount/UI/DiagnoseAlert.swift"; then
  echo "diagnose window must offer Repair Mount Environment" >&2
  exit 1
fi
for loc in en zh-Hans zh-Hant ja; do
  strings="$ROOT/Sources/NTFSMountCore/Resources/${loc}.lproj/Localizable.strings"
  for key in menu.repairEnv repairEnv.title repairEnv.body repairEnv.action repairEnv.working repairEnv.summary repairEnv.summaryBusy repairEnv.summaryNone repairEnv.helperRestarted repairEnv.failed; do
    /usr/bin/grep -q "\"$key\"" "$strings" || {
      echo "missing $key in $loc Localizable.strings" >&2
      exit 1
    }
  done
done
if ! /usr/bin/grep -q '"menu.repairEnv"' "$ROOT/Resources/Localizable.xcstrings"; then
  echo "xcstrings must include menu.repairEnv" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'diagnose.export' "$ROOT/Sources/NTFSMount/UI/DiagnoseAlert.swift"; then
  echo "diagnose window must offer Export Diagnostic Report" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'menu.exportDiagnose' "$ROOT/Sources/NTFSMount/UI/MenuRoot.swift"; then
  echo "menu must offer Export Diagnostic Report" >&2
  exit 1
fi
for loc in en zh-Hans zh-Hant ja; do
  strings="$ROOT/Sources/NTFSMountCore/Resources/${loc}.lproj/Localizable.strings"
  for key in diagnose.export diagnose.exporting diagnose.exportPrivacy diagnose.exportSaved diagnose.exportFailed diagnose.exportFailedSimple diagnose.exportHint diagnose.exportReadmeHeader diagnose.exportReadmeFiles diagnose.exportNoVolumes diagnose.exportDiskutilFailed diagnose.exportLogUnavailable diagnose.exportLogEmpty menu.exportDiagnose; do
    /usr/bin/grep -q "\"$key\"" "$strings" || {
      echo "missing $key in $loc Localizable.strings" >&2
      exit 1
    }
  done
done
if ! /usr/bin/grep -q '"diagnose.export"' "$ROOT/Resources/Localizable.xcstrings"; then
  echo "xcstrings must include diagnose.export" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'unified-log.txt' "$ROOT/Sources/NTFSMountCore/DiagnoseExport.swift"; then
  echo "DiagnoseExport must document unified-log.txt in the zip" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'volume_mount_point "$name"' "$HELPER"; then
  echo "helper volume_mount_point must keep the volume name as one argument" >&2
  exit 1
fi
if /usr/bin/grep -nE 'DISKUTIL[[:space:]]+unmount[[:space:]]+/Volumes/' "$HELPER" "$ROOT"/Sources/NTFSMount/*.swift "$ROOT"/Sources/NTFSMount/Helpers/*.swift "$ROOT"/Sources/NTFSMountCore/*.swift; then
  echo "must not concatenate unquoted /Volumes/name into diskutil" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'Privileged.run("probe"' "${STORE[@]}"; then
  echo "VolumeStore must probe volume health before writable mount" >&2
  exit 1
fi
if /usr/bin/awk '
  $0 ~ /func mountAll\(/ { inh=1 }
  inh && $0 ~ /^  func / && $0 !~ /func mountAll\(/ { inh=0 }
  inh && /run\("mount"/ { found=1 }
  END { exit found ? 0 : 1 }
' "${STORE[@]}"; then
  echo "mountAll must not call run(\"mount\") directly" >&2
  exit 1
fi
if ! /usr/bin/awk '
  $0 ~ /func mountAll\(/ || $0 ~ /func pumpMountAll\(/ { inh=1 }
  inh && $0 ~ /^  func / && $0 !~ /func mountAll\(/ && $0 !~ /func pumpMountAll\(/ { inh=0 }
  inh && /probeThenMount/ { found=1 }
  END { exit found ? 0 : 1 }
' "${STORE[@]}"; then
  echo "mountAll must go through probeThenMount" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'com.bioapple.ntfsmount.helper-client' "$ROOT/Sources/NTFSMount/Privileged.swift"; then
  echo "Privileged must serialize daemon transactions on a helper-client queue" >&2
  exit 1
fi
if ! /usr/bin/grep -q '"probe"' "$HELPERD_C"; then
  echo "helperd must allow probe" >&2
  exit 1
fi
if ! /usr/bin/grep -A30 'func mountDefaultWritableIfNeeded' "${STORE[@]}" | /usr/bin/grep -q 'for vol in volumes'; then
  echo "mountDefaultWritableIfNeeded must iterate every volume, not only volumes.first" >&2
  exit 1
fi
if /usr/bin/awk '
  $0 ~ /func mountDefaultWritableIfNeeded\(/ { inh=1 }
  $0 ~ /func pumpAutoMount\(/ { inh=1 }
  $0 ~ /func markAutoMountFinished\(/ { inh=0 }
  $0 ~ /func toggleAutoMount\(/ { inh=0 }
  inh && /autoMountAttempted.insert/ { found=1 }
  END { exit found ? 0 : 1 }
' "${STORE[@]}"; then
  echo "autoMountAttempted must not be stamped before confirmWritable/Privileged.run" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'shouldRecordAttempt' "${STORE[@]}"; then
  echo "VolumeStore must stamp autoMountAttempted via shouldRecordAttempt" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'shouldAutoEnable' "${STORE[@]}"; then
  echo "enableAutoMountDefault must stay off until helper+legal+writable stamp" >&2
  exit 1
fi
if ! /usr/bin/awk '
  $0 ~ /func mountDefaultWritableIfNeeded\(/ { inh=1 }
  $0 ~ /func pumpAutoMount\(/ { inh=0 }
  inh && /mayAttempt/ { found=1 }
  END { exit found ? 0 : 1 }
' "${STORE[@]}"; then
  echo "mountDefaultWritableIfNeeded must consult AutoMountPolicy.mayAttempt (no mount before legal consent)" >&2
  exit 1
fi
if ! /usr/bin/awk '
  $0 ~ /func mountDefaultWritableIfNeeded\(/ { inh=1 }
  $0 ~ /func pumpAutoMount\(/ { inh=0 }
  inh && /allowsWritableAttempt/ { found=1 }
  END { exit found ? 0 : 1 }
' "${STORE[@]}"; then
  echo "mountDefaultWritableIfNeeded must consult allowsWritableAttempt so dirty/hiber skip RW auto-mount" >&2
  exit 1
fi
SETTINGS="$ROOT/Sources/NTFSMount/UI/SettingsView.swift"
if ! /usr/bin/grep -q 'L10n.t("settings.autoMount")' "$SETTINGS"; then
  echo "settings auto-mount toggle must use L10n.t(\"settings.autoMount\")" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'L10n.t("settings.autoMountNote")' "$SETTINGS"; then
  echo "settings auto-mount note must use L10n.t(\"settings.autoMountNote\")" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'L10n.t("settings.autoMountNeedHelper")' "$SETTINGS"; then
  echo "settings auto-mount helper hint must use L10n.t(\"settings.autoMountNeedHelper\")" >&2
  exit 1
fi
for lang in en zh-Hans zh-Hant ja; do
  strings="$ROOT/Sources/NTFSMountCore/Resources/${lang}.lproj/Localizable.strings"
  for key in settings.autoMount settings.autoMountNote settings.autoMountNeedHelper; do
    if ! /usr/bin/grep -q "\"$key\"" "$strings"; then
      echo "missing $key in $lang Localizable.strings" >&2
      exit 1
    fi
  done
done

# 命令位不得出现未加引号的 /Volumes/$name（"My Passport" 会切成两个 argv）
if /usr/bin/grep -nE '(^|[^"=$])/Volumes/\$name' "$HELPER"; then
  echo "helper contains unquoted /Volumes/\$name" >&2
  exit 1
fi
if /usr/bin/grep -nE 'for[[:space:]]+[^;]+in[[:space:]]+/Volumes/' "$HELPER" "$ROOT"/scripts/*.sh; then
  echo "must not iterate /Volumes by glob (breaks names with spaces)" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'list_slice_idents' "$HELPER"; then
  echo "helper must enumerate diskNsM via list_slice_idents, not directory names" >&2
  exit 1
fi

out="$("$HELPER" selftest)"
echo "$out"
[[ "$out" == ok\ selftest* ]] || { echo "selftest failed" >&2; exit 1; }
ver="$("$HELPER" version)"
[[ "$ver" == HELPER_VERSION=10 ]] || { echo "version mismatch: $ver" >&2; exit 1; }

# shellcheck disable=SC2016 # literal $(whoami) payload the helper must reject
for bad in 'disk12s1;whoami' 'disk 12s1' '../disk1s1' 'disk5s1$(whoami)' 'disk4;id' 'mount'; do
  if "$HELPER" mount "$bad" >/dev/null 2>&1; then
    echo "should reject: $bad" >&2
    exit 1
  fi
  if "$HELPER" format "$bad" >/dev/null 2>&1; then
    echo "format should reject: $bad" >&2
    exit 1
  fi
  if "$HELPER" fix "$bad" >/dev/null 2>&1; then
    echo "fix should reject: $bad" >&2
    exit 1
  fi
  if "$HELPER" ntfsfix "$bad" >/dev/null 2>&1; then
    echo "ntfsfix should reject: $bad" >&2
    exit 1
  fi
  if "$HELPER" probe "$bad" >/dev/null 2>&1; then
    echo "probe should reject: $bad" >&2
    exit 1
  fi
  if "$HELPER" eject "$bad" >/dev/null 2>&1; then
    echo "eject should reject: $bad" >&2
    exit 1
  fi
  if "$HELPER" unmount "$bad" >/dev/null 2>&1; then
    echo "unmount should reject: $bad" >&2
    exit 1
  fi
  if "$HELPER" unmount "$bad" force >/dev/null 2>&1; then
    echo "unmount force should reject: $bad" >&2
    exit 1
  fi
done

# 带空格路径必须作为单一 argv（不真正挂载/格式化）
quote_tmp="$(/usr/bin/mktemp -d /tmp/ntfsmount-space.XXXXXX)"
space_mp="${quote_tmp}/My Passport"
/bin/mkdir -p "$space_mp"
[[ -d "$space_mp" ]] || { echo "quoted mkdir with spaces failed: $space_mp" >&2; exit 1; }
/bin/rm -rf "$quote_tmp"

# format 必须在 mkntfs / eraseDisk 之前拒绝系统盘与 APFS 物理卷。不真正抹盘。
root_plist="$(/usr/sbin/diskutil info -plist / 2>/dev/null || true)"
sys="$(printf '%s' "$root_plist" | /usr/bin/plutil -extract ParentWholeDisk raw - 2>/dev/null || true)"
store="$(printf '%s' "$root_plist" | /usr/bin/plutil -extract APFSPhysicalStores.0.APFSPhysicalStore raw - 2>/dev/null || true)"
refuse_ids=()
if [[ -n "$sys" && "$sys" != "null" ]]; then
  refuse_ids+=("$sys")
  refuse_ids+=("${sys%%s*}")
fi
if [[ -n "$store" && "$store" != "null" ]]; then
  refuse_ids+=("$store")
  refuse_ids+=("${store%%s*}")
fi
[[ ${#refuse_ids[@]} -gt 0 ]] || { echo "cannot identify system disk for format-refusal test" >&2; exit 1; }
seen_refuse=
for ident in "${refuse_ids[@]}"; do
  [[ "$ident" =~ ^disk[0-9]+$ ]] || continue
  fmt_err="$("$HELPER" format "$ident" 2>&1 || true)"
  if printf '%s' "$fmt_err" | /usr/bin/grep -q 'ok formatted'; then
    echo "format must never succeed on system disk $ident: $fmt_err" >&2
    exit 1
  fi
  if printf '%s' "$fmt_err" | /usr/bin/grep -q '拒绝格式化'; then
    seen_refuse=1
  else
    echo "format should refuse system/internal disk $ident: $fmt_err" >&2
    exit 1
  fi
done
[[ -n "$seen_refuse" ]] || { echo "format did not refuse any system/internal whole disk" >&2; exit 1; }

# fix/ntfsfix 必须在真正 ntfsfix 之前拒绝系统盘与 APFS 物理卷。不真正修用户盘。
fix_ids=()
if [[ -n "$store" && "$store" != "null" && "$store" =~ ^disk[0-9]+s[0-9]+$ ]]; then
  fix_ids+=("$store")
fi
for ident in "${refuse_ids[@]}"; do
  if [[ "$ident" =~ ^disk[0-9]+s[0-9]+$ ]]; then
    fix_ids+=("$ident")
  elif [[ "$ident" =~ ^disk[0-9]+$ ]]; then
    fix_ids+=("${ident}s1")
  fi
done
[[ ${#fix_ids[@]} -gt 0 ]] || { echo "cannot identify system partition for fix-refusal test" >&2; exit 1; }
seen_fix_refuse=
for ident in "${fix_ids[@]}"; do
  [[ "$ident" =~ ^disk[0-9]+s[0-9]+$ ]] || continue
  fix_err="$("$HELPER" fix "$ident" 2>&1 || true)"
  if printf '%s' "$fix_err" | /usr/bin/grep -q 'ok fixed'; then
    echo "fix must never succeed on system disk $ident: $fix_err" >&2
    exit 1
  fi
  if printf '%s' "$fix_err" | /usr/bin/grep -q 'ok formatted'; then
    echo "fix must never format $ident: $fix_err" >&2
    exit 1
  fi
  if printf '%s' "$fix_err" | /usr/bin/grep -q '拒绝修复'; then
    seen_fix_refuse=1
  fi
  alias_err="$("$HELPER" ntfsfix "$ident" 2>&1 || true)"
  if printf '%s' "$alias_err" | /usr/bin/grep -q 'ok fixed'; then
    echo "ntfsfix must never succeed on system disk $ident: $alias_err" >&2
    exit 1
  fi
done
[[ -n "$seen_fix_refuse" ]] || { echo "fix did not refuse any system/internal disk" >&2; exit 1; }

# eject：非法 id 已在上面拒绝。系统盘/内置分区不得成功推出（不真正 eject 用户外置盘）。
seen_eject_refuse=
for ident in "${fix_ids[@]}"; do
  [[ "$ident" =~ ^disk[0-9]+s[0-9]+$ ]] || continue
  ej_err="$("$HELPER" eject "$ident" 2>&1 || true)"
  if printf '%s' "$ej_err" | /usr/bin/grep -q 'ok ejected'; then
    echo "eject must never succeed on system disk $ident: $ej_err" >&2
    exit 1
  fi
  if printf '%s' "$ej_err" | /usr/bin/grep -q '拒绝推出'; then
    seen_eject_refuse=1
  fi
done
for ident in "${refuse_ids[@]}"; do
  [[ "$ident" =~ ^disk[0-9]+$ ]] || continue
  ej_err="$("$HELPER" eject "$ident" 2>&1 || true)"
  if printf '%s' "$ej_err" | /usr/bin/grep -q 'ok ejected'; then
    echo "eject must never succeed on system whole disk $ident: $ej_err" >&2
    exit 1
  fi
done
[[ -n "$seen_eject_refuse" ]] || { echo "eject did not refuse any system/internal partition" >&2; exit 1; }

SDK="$(xcrun --sdk macosx --show-sdk-path)"
TMPD="$(/usr/bin/mktemp -d /tmp/ntfsmount-helperd.XXXXXX)"
clang -O2 -arch arm64 -mmacosx-version-min=13.0 -isysroot "$SDK" \
  -framework Security -framework CoreFoundation \
  -o "$TMPD/helperd" "$ROOT/helper/ntfsmount-helperd.c"
file "$TMPD/helperd" | /usr/bin/grep -q 'arm64' || { echo "helperd not arm64" >&2; exit 1; }
/bin/rm -rf "$TMPD"

# README 与界面不得再写「没有程序坞」或「点盘名即可挂载」
if /usr/bin/grep -n '没有程序坞图标' "$ROOT/README.md"; then
  echo "README still says no Dock icon" >&2
  exit 1
fi
if /usr/bin/grep -n '点盘名即可' "$ROOT/README.md"; then
  echo "README still says click the disk name" >&2
  exit 1
fi
if /usr/bin/grep -n '完整英文说明' "$ROOT/README.md"; then
  echo "English README.md must not be the Chinese document" >&2
  exit 1
fi
[[ -f "$ROOT/Resources/NTFSMount.entitlements" ]]
[[ -f "$ROOT/helper/com.bioapple.ntfsmount.helper.plist" ]]
[[ -f "$ROOT/docs/DISTRIBUTION.md" ]]
[[ -f "$ROOT/NOTICE" ]]
[[ -f "$ROOT/docs/MANUAL_TEST.md" ]]
[[ -f "$ROOT/runtime/SHA256SUMS" ]]
[[ -f "$ROOT/runtime/versions.txt" ]]
if ! /usr/bin/grep -q 'ntfs-3g-allow' "$ROOT/runtime/versions.txt"; then
  echo "runtime/versions.txt must document ntfs-3g allow-list" >&2
  exit 1
fi
if ! /usr/bin/grep -q '2026.8.x' "$ROOT/Sources/NTFSMountCore/Ntfs3gVersion.swift"; then
  echo "Ntfs3gVersion.swift must keep 2026.8.x allow-list" >&2
  exit 1
fi
# shellcheck source=ntfs3g-version.sh
. "$ROOT/scripts/ntfs3g-version.sh"
[[ "$(ntfs3g_parse_version 'ntfs-3g 2026.7.7 external FUSE 29')" == "2026.7.7" ]] || { echo "parse 2026.7.7 failed" >&2; exit 1; }
[[ "$(ntfs3g_parse_version 'ntfs-3g 2026.8.1 integrated FUSE 29')" == "2026.8.1" ]] || { echo "parse 2026.8.1 failed" >&2; exit 1; }
ntfs3g_version_allowed 2026.7.7 || { echo "allow 2026.7.7" >&2; exit 1; }
ntfs3g_version_allowed 2026.8.1 || { echo "allow 2026.8.1" >&2; exit 1; }
if ntfs3g_version_allowed 2024.2.1; then echo "2024.x must warn" >&2; exit 1; fi
if ntfs3g_version_allowed 2026.9.0; then echo "2026.9 must warn" >&2; exit 1; fi
if ntfs3g_version_allowed garbage; then echo "garbage must warn" >&2; exit 1; fi
if /usr/bin/grep -nF 'copy_if_exec /usr/local/bin/ntfs-3g' "$ROOT/scripts/prepare-runtime.sh"; then
  echo "prepare-runtime must not copy ntfs-3g only from /usr/local/bin" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'find_ntfs3g_bin' "$ROOT/scripts/prepare-runtime.sh"; then
  echo "prepare-runtime must resolve ntfs-3g dynamically (Apple Silicon /opt/homebrew)" >&2
  exit 1
fi
if ! /usr/bin/grep -q '/opt/homebrew/bin/ntfs-3g' "$ROOT/scripts/prepare-runtime.sh"; then
  echo "prepare-runtime must try /opt/homebrew/bin/ntfs-3g" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'ntfs3g_base_opts' "$HELPER"; then
  echo "helper must build ntfs-3g -o via ntfs3g_base_opts" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'auto_xattr' "$HELPER"; then
  echo "helper must pass auto_xattr so Finder xattr / 中文名 metadata 可用" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'locale=zh_CN.UTF-8' "$HELPER"; then
  echo "helper must default ntfs-3g locale to zh_CN.UTF-8" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'allow_other' "$HELPER"; then
  echo "helper must pass allow_other so the console user can write" >&2
  exit 1
fi
if /usr/bin/grep -nE 'brew install macfuse|请安装 macFUSE|must install macFUSE' "$ROOT/scripts/ntfsmount-diagnose.sh"; then
  echo "diagnose must not require macFUSE" >&2
  exit 1
fi
if [[ ! -f "$ROOT/scripts/ci-shellcheck.sh" ]]; then
  echo "missing scripts/ci-shellcheck.sh" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'helper/ntfs-rw-helper' "$ROOT/scripts/ci-shellcheck.sh"; then
  echo "ci-shellcheck must include helper/ntfs-rw-helper" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'scripts/ci-shellcheck.sh' "$ROOT/.github/workflows/shellcheck.yml"; then
  echo "shellcheck.yml must run scripts/ci-shellcheck.sh" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'uses: ./.github/workflows/shellcheck.yml' "$ROOT/.github/workflows/build.yml"; then
  echo "build.yml must call the ShellCheck reusable workflow" >&2
  exit 1
fi
if /usr/bin/grep -nE 'brew install shellcheck' "$ROOT/.github/workflows/build.yml"; then
  echo "build.yml must not brew install shellcheck in Security Scan; use the ShellCheck job" >&2
  exit 1
fi
CHECK_DEPS="$ROOT/scripts/check-fuse-deps.sh"
if [[ ! -f "$CHECK_DEPS" ]]; then
  echo "missing scripts/check-fuse-deps.sh" >&2
  exit 1
fi
if /usr/bin/grep -nE '\$BREW[[:space:]]+install[[:space:]]+macfuse|"\$BREW" install macfuse' "$CHECK_DEPS"; then
  echo "check-fuse-deps must not brew install macfuse" >&2
  exit 1
fi
if /usr/bin/grep -nE '\$BREW[[:space:]]+install[[:space:]]+fuse-t|"\$BREW" install fuse-t' "$CHECK_DEPS"; then
  echo "check-fuse-deps must not brew install fuse-t" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'brew install ntfs-3g' "$CHECK_DEPS"; then
  echo "check-fuse-deps must brew install ntfs-3g only" >&2
  exit 1
fi
if ! /usr/bin/grep -q '无需关闭 SIP' "$CHECK_DEPS"; then
  echo "check-fuse-deps must say FUSE-T does not require lowering SIP" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'check-fuse-deps.sh' "$ROOT/docs/DEVELOPMENT.md"; then
  echo "docs/DEVELOPMENT.md must document check-fuse-deps.sh" >&2
  exit 1
fi
if /usr/bin/grep -nE '请执行：.*brew install macfuse|推荐.*brew install macfuse' "$ROOT/README.md"; then
  echo "README must not recommend brew install macfuse" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'ntfsmount-diagnose.sh' "$ROOT/scripts/build.sh"; then
  echo "build.sh must copy ntfsmount-diagnose.sh into the app" >&2
  exit 1
fi
CLI="$ROOT/scripts/ntfsmount"
if ! "$CLI" list --json | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("ok") is True; assert isinstance(d.get("volumes"), list)'; then
  echo "ntfsmount list --json must emit {ok, volumes}" >&2
  exit 1
fi
if ! "$CLI" --json list | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); assert "volumes" in d'; then
  echo "ntfsmount --json list must work with flag before command" >&2
  exit 1
fi
mount_json="$("$CLI" mount --json 2>/dev/null || true)"
if ! printf '%s' "$mount_json" | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("ok") is False; assert d.get("error")=="missing_device"'; then
  echo "ntfsmount mount --json without ident must be missing_device JSON" >&2
  echo "$mount_json" >&2
  exit 1
fi
bad_json="$("$CLI" mount 'disk12s1;whoami' --json 2>/dev/null || true)"
if ! printf '%s' "$bad_json" | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("error")=="invalid_device"'; then
  echo "ntfsmount mount must reject injected id as JSON invalid_device" >&2
  echo "$bad_json" >&2
  exit 1
fi
if /usr/bin/id -u | /usr/bin/grep -qx 0; then
  :
else
  noroot="$("$CLI" mount disk4s1 --json 2>/dev/null || true)"
  if ! printf '%s' "$noroot" | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("error")=="not_root"'; then
    echo "ntfsmount mount --json as non-root must be not_root" >&2
    echo "$noroot" >&2
    exit 1
  fi
fi
if /usr/bin/grep -nE 'sudo[[:space:]]+-S\b' "$ROOT/scripts/ntfsmount" "$ROOT/scripts/ntfsmount-volumes.sh"; then
  echo "ntfsmount must not feed sudo a password" >&2
  exit 1
fi
if ! /usr/bin/grep -q '#define MAX_ARGS 32' "$ROOT/helper/ntfsmount-helperd.c"; then
  echo "helperd MAX_ARGS must be at least 32" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'v2 ' "$ROOT/helper/ntfsmount-helperd.c"; then
  echo "helperd must accept length-prefixed v2 argv" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'encodeV2' "$ROOT/Sources/NTFSMount/Privileged.swift"; then
  echo "Privileged must send HelperIpc v2" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'WAIT_SEC_LONG' "$ROOT/helper/ntfsmount-helperd.c"; then
  echo "helperd must wait longer for format/fix" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'peer_disconnected' "$ROOT/helper/ntfsmount-helperd.c"; then
  echo "helperd must skip exec if the client hung up" >&2
  exit 1
fi
if ! /usr/bin/grep -q 'stripHeartbeats' "$ROOT/Sources/NTFSMount/Privileged.swift"; then
  echo "Privileged must ignore daemon NUL heartbeats" >&2
  exit 1
fi
if /usr/bin/grep -n 'replacingOccurrences(of: "\\n", with: " ") + "\\n"' "$ROOT/Sources/NTFSMount/Privileged.swift"; then
  echo "Privileged must not split argv on newlines for the primary protocol" >&2
  exit 1
fi

export MACOSX_DEPLOYMENT_TARGET=13.0
# Xcode 15.4 / SwiftPM cannot form NTFSMountPackageTests.xctest after
# `swift build --target NTFSMountCoreTests` plus `--skip-build`.
swift test --package-path "$ROOT" --filter NTFSMountCoreTests

echo "ok tests"
