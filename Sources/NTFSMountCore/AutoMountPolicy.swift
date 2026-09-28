import Foundation

/// Shared eligibility for insert-time auto-mount (app queue + helper).
/// Never formats, never clears hiberfile, never auto-ntfsfix.
public enum AutoMountPolicy {
  /// App-side: skip internal, already-writable FUSE, user-unmounted, and finished attempts.
  /// Unmounted external NTFS is eligible (empty mount is not a skip).
  public static func isEligible(
    isInternal: Bool,
    isWritableFuse: Bool,
    userSkippedUnmount: Bool,
    alreadyAttempted: Bool
  ) -> Bool {
    !isInternal && !isWritableFuse && !userSkippedUnmount && !alreadyAttempted
  }

  /// Helper-side: unmounted external NTFS is eligible; already-ours / writable / internal is not.
  /// Dirty/hiber/corrupt volumes are still eligible here; `do_mount` probes then uses RO / skip,
  /// never writable auto-mount and never auto-ntfsfix.
  public static func helperShouldMount(
    isInternal: Bool,
    isOurFuse: Bool,
    isWritable: Bool
  ) -> Bool {
    guard !isInternal else { return false }
    if isOurFuse || isWritable { return false }
    return true
  }

  /// Stamp `autoMountAttempted` only after the user refuses a confirm dialog, or after
  /// `Privileged.run` returns. Never stamp before `confirmWritable` / the helper call.
  public static func shouldRecordAttempt(userRefused: Bool, helperReturned: Bool) -> Bool {
    userRefused || helperReturned
  }

  /// Insert-time writable auto-mount only for clean/unknown probes.
  /// Dirty, hibernated, or corrupt → skip RW (helper then RO or skip).
  public static func allowsWritableAttempt(_ kind: VolumeHealth.ProbeKind) -> Bool {
    switch kind {
    case .healthy, .unknown: return true
    case .dirty, .hibernated, .corrupt: return false
    }
  }

  /// App-side pump: never mount before legal consent, even if the automount plist already exists.
  public static func mayAttempt(
    autoMountEnabled: Bool,
    helperReady: Bool,
    legalAccepted: Bool
  ) -> Bool {
    autoMountEnabled && helperReady && legalAccepted
  }

  /// First launch only: install the mount helper when it is not already running.
  /// A later uninstall stays manual. An attempt is recorded even if the user cancels the password.
  public static func shouldAutoInstallHelper(alreadyAttempted: Bool, daemonReady: Bool) -> Bool {
    !alreadyAttempted && !daemonReady
  }

  /// Toggle stays off until helper is installed, legal copy is accepted, and the writable stamp exists.
  public static func shouldAutoEnable(
    helperInstalled: Bool,
    legalAccepted: Bool,
    writableStampPresent: Bool,
    userOptedOff: Bool
  ) -> Bool {
    helperInstalled && legalAccepted && writableStampPresent && !userOptedOff
  }
}
