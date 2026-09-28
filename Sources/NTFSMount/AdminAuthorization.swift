import Darwin
import Foundation
import NTFSMountCore
import Security

/// One-shot root execution for helper install/uninstall when `SMAppService` cannot register.
///
/// Signed/notarized builds use `SMAppService.daemon`. Ad-hoc 1.0 usually cannot, so this
/// obtains `kAuthorizationRightExecute` (`system.privilege.admin`) via Authorization
/// Services and runs the already-bundled installer as root. Daily mount/format never
/// goes through here — those use the LaunchDaemon Unix socket.
///
/// `AuthorizationExecuteWithPrivileges` is deprecated; it is resolved dynamically and
/// used only as this ad-hoc fallback. We do not embed sudo, AppleScript, or a second
/// daemon, and we do not require SIP to be disabled.
enum AdminAuthorization {
  /// `kAuthorizationRightExecute` in Authorization.h.
  private static let executeRight = "system.privilege.admin"

  private typealias ExecuteWithPrivileges = @convention(c) (
    AuthorizationRef,
    UnsafePointer<CChar>,
    AuthorizationFlags,
    UnsafePointer<UnsafeMutablePointer<CChar>?>?,
    UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
  ) -> OSStatus

  static func run(parts: [String]) -> (ok: Bool, text: String) {
    guard let tool = parts.first, !tool.isEmpty else {
      return (false, L10n.t("privileged.commFailed"))
    }
    guard let bash = CommandPath.find("bash") else {
      return (false, L10n.t("privileged.commFailed"))
    }
    // security_authtrampoline is setuid-root and execs bash with euid 0 and the user's
    // real uid. Without -p, bash resets euid to that real uid, so install-helper.sh
    // prints "root is required" after the administrator prompt succeeds.
    let rest = Array(parts.dropFirst())
    let command: [String]
    if (tool as NSString).lastPathComponent == "bash" {
      command = [bash, "-p"] + rest
    } else {
      command = [tool] + rest
    }
    let wrapped = ["-p", "-c", "exec 2>&1; exec \"$@\"", bash] + command
    return execute(tool: bash, arguments: wrapped)
  }

  private static func execute(tool: String, arguments: [String]) -> (ok: Bool, text: String) {
    var authRef: AuthorizationRef?
    var status = AuthorizationCreate(nil, nil, [], &authRef)
    guard status == errAuthorizationSuccess, let authRef else {
      return (false, authorizationFailure(status))
    }
    defer { AuthorizationFree(authRef, [.destroyRights]) }

    status = executeRight.withCString { name in
      var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
      return withUnsafeMutablePointer(to: &item) { itemPtr in
        var rights = AuthorizationRights(count: 1, items: itemPtr)
        let flags: AuthorizationFlags = [.interactionAllowed, .extendRights, .preAuthorize]
        return AuthorizationCopyRights(authRef, &rights, nil, flags, nil)
      }
    }
    if status != errAuthorizationSuccess {
      return (false, authorizationFailure(status))
    }

    guard let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2),
          let symbol = dlsym(defaultHandle, "AuthorizationExecuteWithPrivileges") else {
      return (false, L10n.t("privileged.authUnavailable"))
    }
    let runPrivileged = unsafeBitCast(symbol, to: ExecuteWithPrivileges.self)

    var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) }
    argv.append(nil)
    defer {
      for ptr in argv {
        if let ptr { free(ptr) }
      }
    }

    var pipe: UnsafeMutablePointer<FILE>?
    let execStatus: OSStatus = tool.withCString { path in
      argv.withUnsafeMutableBufferPointer { buf in
        runPrivileged(authRef, path, [], buf.baseAddress, &pipe)
      }
    }
    let output = readAndClose(pipe)
    if execStatus != errAuthorizationSuccess {
      return (false, output.isEmpty ? authorizationFailure(execStatus) : output)
    }
    var wstatus: Int32 = 0
    _ = waitpid(pid_t(-1), &wstatus, 0)
    if didExit(wstatus) {
      let code = exitStatus(wstatus)
      if code == 0 { return (true, output) }
      return (false, output.isEmpty ? "exit \(code)" : output)
    }
    if wasSignaled(wstatus) {
      return (false, output.isEmpty ? "signal \(termSignal(wstatus))" : output)
    }
    return (true, output)
  }

  private static func waitBits(_ status: Int32) -> Int32 { status & 0x7f }
  private static func didExit(_ status: Int32) -> Bool { waitBits(status) == 0 }
  private static func exitStatus(_ status: Int32) -> Int32 { (status >> 8) & 0xff }
  private static func wasSignaled(_ status: Int32) -> Bool {
    let bits = waitBits(status)
    return bits != 0 && bits != 0x7f
  }
  private static func termSignal(_ status: Int32) -> Int32 { waitBits(status) }

  private static func readAndClose(_ pipe: UnsafeMutablePointer<FILE>?) -> String {
    guard let pipe else { return "" }
    defer { fclose(pipe) }
    let fd = fileno(pipe)
    guard fd >= 0 else { return "" }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
    let data = (try? handle.readToEnd()) ?? Data()
    return String(data: data, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      ?? String(decoding: data, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func authorizationFailure(_ status: OSStatus) -> String {
    if status == errAuthorizationCanceled {
      return "User canceled. (-60006)"
    }
    if status == errAuthorizationDenied || status == errAuthorizationInteractionNotAllowed {
      return "authorization denied (\(status))"
    }
    return "authorization failed (\(status))"
  }
}
