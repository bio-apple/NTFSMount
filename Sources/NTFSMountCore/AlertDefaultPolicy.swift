import Foundation

/// Maps NSAlert button index → `keyEquivalent`.
/// Cancel-default dialogs put Cancel first so Return does not confirm a destructive action.
public enum AlertDefaultPolicy: Equatable, Sendable {
  /// First button is Cancel and receives Return. Later buttons (Format / Fix / Continue) are empty.
  case cancelDefault
  /// First button is the safe action (Return). Last button is Cancel (Escape) when there are 2+ buttons.
  case safeDefault

  public static let format = Self.cancelDefault
  public static let ntfsfix = Self.cancelDefault
  public static let writableConfirm = Self.cancelDefault
  public static let forceUnmount = Self.cancelDefault
  public static let repairMount = Self.cancelDefault

  public static let returnKeyEquivalent = "\r"
  public static let emptyKeyEquivalent = ""
  public static let escapeKeyEquivalent = "\u{1b}"

  public func keyEquivalent(at index: Int, buttonCount: Int) -> String {
    switch self {
    case .cancelDefault:
      return index == 0 ? Self.returnKeyEquivalent : Self.emptyKeyEquivalent
    case .safeDefault:
      if index == 0 { return Self.returnKeyEquivalent }
      if buttonCount > 1, index == buttonCount - 1 { return Self.escapeKeyEquivalent }
      return Self.emptyKeyEquivalent
    }
  }
}
