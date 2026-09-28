import Foundation
import NTFSMountCore
import XCTest

final class AutoMountPolicyTests: XCTestCase {
  func testUnmountedExternalIsEligiblePerVolumeNotOnlyFirst() {
    XCTAssertTrue(
      AutoMountPolicy.isEligible(
        isInternal: false, isWritableFuse: false, userSkippedUnmount: false, alreadyAttempted: false
      )
    )
    XCTAssertTrue(
      AutoMountPolicy.isEligible(
        isInternal: false, isWritableFuse: false, userSkippedUnmount: false, alreadyAttempted: false
      ),
      "second unmounted volume stays eligible independently of volumes.first"
    )
    XCTAssertFalse(
      AutoMountPolicy.isEligible(
        isInternal: true, isWritableFuse: false, userSkippedUnmount: false, alreadyAttempted: false
      )
    )
    XCTAssertFalse(
      AutoMountPolicy.isEligible(
        isInternal: false, isWritableFuse: true, userSkippedUnmount: false, alreadyAttempted: false
      )
    )
    XCTAssertFalse(
      AutoMountPolicy.isEligible(
        isInternal: false, isWritableFuse: false, userSkippedUnmount: true, alreadyAttempted: false
      )
    )
    XCTAssertFalse(
      AutoMountPolicy.isEligible(
        isInternal: false, isWritableFuse: false, userSkippedUnmount: false, alreadyAttempted: true
      )
    )
  }

  func testOpenInstallsHelperWhenSocketMissing() {
    XCTAssertTrue(AutoMountPolicy.shouldAutoInstallHelper(daemonReady: false))
    XCTAssertFalse(AutoMountPolicy.shouldAutoInstallHelper(daemonReady: true))
  }

  func testHelperMountsUnmountedExternalWithoutRequiringStillMounted() {
    XCTAssertTrue(
      AutoMountPolicy.helperShouldMount(isInternal: false, isOurFuse: false, isWritable: false),
      "unmounted external NTFS must auto-mount; do not require volume_still_mounted"
    )
    XCTAssertFalse(AutoMountPolicy.helperShouldMount(isInternal: true, isOurFuse: false, isWritable: false))
    XCTAssertFalse(AutoMountPolicy.helperShouldMount(isInternal: false, isOurFuse: true, isWritable: false))
    XCTAssertFalse(AutoMountPolicy.helperShouldMount(isInternal: false, isOurFuse: false, isWritable: true))
  }

  func testRecordAttemptOnlyAfterRefuseOrHelperReturn() {
    XCTAssertFalse(AutoMountPolicy.shouldRecordAttempt(userRefused: false, helperReturned: false))
    XCTAssertTrue(AutoMountPolicy.shouldRecordAttempt(userRefused: true, helperReturned: false))
    XCTAssertTrue(AutoMountPolicy.shouldRecordAttempt(userRefused: false, helperReturned: true))
  }

  func testToggleStaysOffUntilHelperLegalAndWritableStamp() {
    XCTAssertFalse(
      AutoMountPolicy.shouldAutoEnable(
        helperInstalled: false, legalAccepted: true, writableStampPresent: true, userOptedOff: false
      )
    )
    XCTAssertFalse(
      AutoMountPolicy.shouldAutoEnable(
        helperInstalled: true, legalAccepted: false, writableStampPresent: true, userOptedOff: false
      )
    )
    XCTAssertFalse(
      AutoMountPolicy.shouldAutoEnable(
        helperInstalled: true, legalAccepted: true, writableStampPresent: false, userOptedOff: false
      )
    )
    XCTAssertFalse(
      AutoMountPolicy.shouldAutoEnable(
        helperInstalled: true, legalAccepted: true, writableStampPresent: true, userOptedOff: true
      )
    )
    XCTAssertTrue(
      AutoMountPolicy.shouldAutoEnable(
        helperInstalled: true, legalAccepted: true, writableStampPresent: true, userOptedOff: false
      )
    )
  }

  func testWritableAutoMountSkippedWhenDirtyCorruptOrHiber() {
    XCTAssertTrue(AutoMountPolicy.allowsWritableAttempt(.healthy))
    XCTAssertTrue(AutoMountPolicy.allowsWritableAttempt(.unknown))
    XCTAssertFalse(AutoMountPolicy.allowsWritableAttempt(.dirty))
    XCTAssertFalse(AutoMountPolicy.allowsWritableAttempt(.corrupt))
    XCTAssertFalse(AutoMountPolicy.allowsWritableAttempt(.hibernated))
  }

  func testMayAttemptRequiresLegalConsentEvenIfToggleOn() {
    XCTAssertFalse(
      AutoMountPolicy.mayAttempt(autoMountEnabled: true, helperReady: true, legalAccepted: false),
      "refresh/DiskWatch must not auto-mount before the legal dialog"
    )
    XCTAssertFalse(AutoMountPolicy.mayAttempt(autoMountEnabled: true, helperReady: false, legalAccepted: true))
    XCTAssertFalse(AutoMountPolicy.mayAttempt(autoMountEnabled: false, helperReady: true, legalAccepted: true))
    XCTAssertTrue(AutoMountPolicy.mayAttempt(autoMountEnabled: true, helperReady: true, legalAccepted: true))
  }

  func testQueueUsesAllowsWritableAttemptForKnownDirtyProbe() {
    XCTAssertTrue(
      AutoMountPolicy.isEligible(
        isInternal: false, isWritableFuse: false, userSkippedUnmount: false, alreadyAttempted: false
      )
    )
    XCTAssertTrue(
      AutoMountPolicy.allowsWritableAttempt(.unknown),
      "first insert with no probe still queues; helper then RW or RO"
    )
    XCTAssertFalse(
      AutoMountPolicy.allowsWritableAttempt(.dirty),
      "known dirty/hiber/corrupt must not be queued for RW auto-mount"
    )
    XCTAssertFalse(AutoMountPolicy.allowsWritableAttempt(.hibernated))
    XCTAssertFalse(AutoMountPolicy.allowsWritableAttempt(.corrupt))
  }
}
