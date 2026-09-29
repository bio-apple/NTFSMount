import Darwin
import Foundation
import NTFSMountCore
import Security

/// Root execution through Authorization Services (`kAuthorizationRightExecute`).
///
/// Two callers:
/// - helper install/uninstall when `SMAppService` cannot register (ad-hoc builds);
/// - the on-demand volume operations (probe / mount / unmount / eject / format / fix), run as a
///   **child of this app**.
///
/// The child-process detail is the point: TCC attributes Full Disk Access to the responsible
/// process, and a launchd daemon is its own subject, so `ntfsmount-helperd` never inherits
/// NTFSMount.app’s grant. A child forked from the app does inherit it, which is why the raw-device
/// operations go through here while auto-mount keeps the LaunchDaemon Unix socket.
///
/// The volume operations launch `ntfsmount-helperd exec-root <sealed helper>`: Authorization
/// Services leaves the real uid at the user, and both ntfs-3g (setuid refusal) and normal root work
/// want a real-root process, so that one-shot mode sets every uid to 0 before exec.
///
/// `AuthorizationExecuteWithPrivileges` is deprecated; it is resolved dynamically. We do not embed
/// sudo, AppleScript, or a second daemon, and we do not require SIP to be disabled.
enum AdminAuthorization {
  /// `kAuthorizationRightExecute` in Authorization.h.
  private static let executeRight = "system.privilege.admin"

  /// Result of one privileged launch.
  struct Launch {
    let ok: Bool
    let text: String
    /// False when the privileged tool never started (no authorization, canceled, AEP missing).
    /// Only then may a caller fall back to another path; a tool that ran must not be re-run.
    let launched: Bool
  }

  /// One `AuthorizationRef` for the process. Rights cached in it are reused until the system
  /// timeout (5 minutes by default), so a burst of mounts asks for the password once.
  private static var sharedRef: AuthorizationRef?

  /// Privileged launches are serialized: `waitpid(-1)` reaps any child, so two runs in flight
  /// would steal each other’s exit status. The security agent only prompts one at a time anyway.
  private static let runner = DispatchQueue(label: "com.bioapple.ntfsmount.auth-run")

  private typealias ExecuteWithPrivileges = @convention(c) (
    AuthorizationRef,
    UnsafePointer<CChar>,
    AuthorizationFlags,
    UnsafePointer<UnsafeMutablePointer<CChar>?>?,
    UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
  ) -> OSStatus

  static func run(parts: [String]) -> (ok: Bool, text: String) {
    let launch = runTool(parts: parts)
    return (launch.ok, launch.text)
  }

  /// Runs `parts[0]` (a root-owned tool) as root with the rest as arguments.
  static func runTool(parts: [String]) -> Launch {
    guard let tool = parts.first, !tool.isEmpty else {
      return Launch(ok: false, text: L10n.t("privileged.commFailed"), launched: false)
    }
    guard let bash = CommandPath.find("bash") else {
      return Launch(ok: false, text: L10n.t("privileged.commFailed"), launched: false)
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
    return runner.sync { execute(tool: bash, arguments: wrapped) }
  }

  /// Reuses the cached right when it is still valid, and prompts again once it expires.
  private static func authorizedRef() -> (AuthorizationRef?, String?) {
    let authRef: AuthorizationRef
    if let sharedRef {
      authRef = sharedRef
    } else {
      var created: AuthorizationRef?
      let createStatus = AuthorizationCreate(nil, nil, [], &created)
      guard createStatus == errAuthorizationSuccess, let created else {
        return (nil, authorizationFailure(createStatus))
      }
      sharedRef = created
      authRef = created
    }
    let status = executeRight.withCString { name in
      var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
      return withUnsafeMutablePointer(to: &item) { itemPtr in
        var rights = AuthorizationRights(count: 1, items: itemPtr)
        let flags: AuthorizationFlags = [.interactionAllowed, .extendRights, .preAuthorize]
        return AuthorizationCopyRights(authRef, &rights, nil, flags, nil)
      }
    }
    if status != errAuthorizationSuccess {
      return (nil, authorizationFailure(status))
    }
    return (authRef, nil)
  }

  private static func execute(tool: String, arguments: [String]) -> Launch {
    let (maybeRef, authError) = authorizedRef()
    guard let authRef = maybeRef else {
      return Launch(ok: false, text: authError ?? L10n.t("privileged.commFailed"), launched: false)
    }

    guard let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2),
          let symbol = dlsym(defaultHandle, "AuthorizationExecuteWithPrivileges") else {
      return Launch(ok: false, text: L10n.t("privileged.authUnavailable"), launched: false)
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
      let text = output.isEmpty ? authorizationFailure(execStatus) : output
      return Launch(ok: false, text: text, launched: false)
    }
    var wstatus: Int32 = 0
    _ = waitpid(pid_t(-1), &wstatus, 0)
    if didExit(wstatus) {
      let code = exitStatus(wstatus)
      if code == 0 { return Launch(ok: true, text: output, launched: true) }
      return Launch(ok: false, text: output.isEmpty ? "exit \(code)" : output, launched: true)
    }
    if wasSignaled(wstatus) {
      let text = output.isEmpty ? "signal \(termSignal(wstatus))" : output
      return Launch(ok: false, text: text, launched: true)
    }
    return Launch(ok: true, text: output, launched: true)
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
