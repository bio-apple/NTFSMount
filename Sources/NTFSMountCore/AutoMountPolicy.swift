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

  /// Open the app with no helper socket: ask to install. Skip when the daemon is already up.
  public static func shouldAutoInstallHelper(daemonReady: Bool) -> Bool {
    !daemonReady
  }

  /// First open after install: diagnose, then repair once. A stored finish flag skips it.
  public static func shouldRunFirstLaunchSetup(alreadyFinished: Bool, legalAccepted: Bool) -> Bool {
    legalAccepted && !alreadyFinished
  }

  /// On by default once the helper is installed and the legal copy is accepted.
  /// A stored opt-out stays off.
  public static func shouldAutoEnable(
    helperInstalled: Bool,
    legalAccepted: Bool,
    userOptedOff: Bool
  ) -> Bool {
    helperInstalled && legalAccepted && !userOptedOff
  }
}
