import AppKit
import ApplicationServices

/// Private AppKit accessor: maps an AX window element to its CoreGraphics window id.
/// No public API exposes this, and the id is what lets us reason about z-order
/// (CGWindowListCopyWindowInfo returns windows front-to-back).
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

enum AX {
    static func value<T>(_ element: AXUIElement, _ key: String) -> T? {
        try? valueOrThrow(element, key)
    }

    /// Same lookup, but surfaces the AXError so a failure can be logged rather than
    /// silently becoming an empty list.
    static func valueOrThrow<T>(_ element: AXUIElement, _ key: String) throws -> T {
        var raw: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, key as CFString, &raw)
        guard error == .success else { throw Failure.ax(key, error) }
        guard let typed = raw as? T else { throw Failure.wrongType(key, String(describing: raw)) }
        return typed
    }

    enum Failure: Error, CustomStringConvertible {
        case ax(String, AXError)
        case wrongType(String, String)
        var description: String {
            switch self {
            case let .ax(key, error): "\(key): AXError \(error.rawValue)"
            case let .wrongType(key, got): "\(key): unexpected type \(got)"
            }
        }
    }

    static func windowID(_ element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    static func raise(_ element: AXUIElement) {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
