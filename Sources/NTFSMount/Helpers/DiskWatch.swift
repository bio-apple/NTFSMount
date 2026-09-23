import DiskArbitration
import Foundation

final class DiskWatch {
  private var session: DASession?
  private var pending: DispatchWorkItem?
  var onChange: (() -> Void)?

  func start() {
    guard session == nil, let session = DASessionCreate(kCFAllocatorDefault) else { return }
    self.session = session
    let ctx = Unmanaged.passUnretained(self).toOpaque()
    DARegisterDiskAppearedCallback(session, nil, diskWatchAppeared, ctx)
    DARegisterDiskDisappearedCallback(session, nil, diskWatchDisappeared, ctx)
    DARegisterDiskDescriptionChangedCallback(session, nil, nil, diskWatchChanged, ctx)
    DASessionSetDispatchQueue(session, DispatchQueue.main)
  }

  func stop() {
    pending?.cancel()
    pending = nil
    guard let session else { return }
    let ctx = Unmanaged.passUnretained(self).toOpaque()
    DAUnregisterCallback(session, unsafeBitCast(diskWatchAppeared, to: UnsafeMutableRawPointer.self), ctx)
    DAUnregisterCallback(session, unsafeBitCast(diskWatchDisappeared, to: UnsafeMutableRawPointer.self), ctx)
    DAUnregisterCallback(session, unsafeBitCast(diskWatchChanged, to: UnsafeMutableRawPointer.self), ctx)
    DASessionSetDispatchQueue(session, nil)
    self.session = nil
  }

  deinit { stop() }

  fileprivate func schedule() {
    pending?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.onChange?() }
    pending = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
  }
}

private func diskWatchAppeared(_ disk: DADisk, _ ctx: UnsafeMutableRawPointer?) {
  guard let ctx else { return }
  Unmanaged<DiskWatch>.fromOpaque(ctx).takeUnretainedValue().schedule()
}

private func diskWatchDisappeared(_ disk: DADisk, _ ctx: UnsafeMutableRawPointer?) {
  guard let ctx else { return }
  Unmanaged<DiskWatch>.fromOpaque(ctx).takeUnretainedValue().schedule()
}

private func diskWatchChanged(_ disk: DADisk, _ keys: CFArray, _ ctx: UnsafeMutableRawPointer?) {
  guard let ctx else { return }
  Unmanaged<DiskWatch>.fromOpaque(ctx).takeUnretainedValue().schedule()
}
