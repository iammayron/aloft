import AppKit
import Carbon.HIToolbox

/// The global shortcut, registered with Carbon rather than watched with
/// `NSEvent.addGlobalMonitorForEvents`.
///
/// Two reasons. It tells us when a combination is already taken —
/// `RegisterEventHotKey` fails with `eventHotKeyExistsErr` if another app holds it,
/// which is the only way to detect that conflict. And it means Aloft never observes
/// keystrokes it has no business seeing: the system delivers this one combination and
/// nothing else, and consumes it so it does not also reach the focused app.
@MainActor
final class HotKey {
    static let shared = HotKey()

    var onPress: (() -> Void)?
    private(set) var current: Shortcut?

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private static let signature: OSType = 0x414C4654        // 'ALFT'

    private init() { installHandler() }

    // MARK: - Registration

    @discardableResult
    func apply(_ shortcut: Shortcut) -> Bool {
        unregister()
        guard let ref = Self.register(shortcut) else { return false }
        self.ref = ref
        current = shortcut
        return true
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        current = nil
    }

    /// True when nothing else holds this combination. Our own registration is stood
    /// down for the test and restored afterwards, or re-recording the shortcut you
    /// already use would always look like a conflict.
    func isAvailable(_ shortcut: Shortcut) -> Bool {
        let restore = current
        unregister()
        defer { if let restore { apply(restore) } }

        guard let probe = Self.register(shortcut) else { return false }
        UnregisterEventHotKey(probe)
        return true
    }

    private static func register(_ shortcut: Shortcut) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode),
                                         carbonModifiers(shortcut.flags),
                                         id, GetApplicationEventTarget(), 0, &ref)
        return status == noErr ? ref : nil
    }

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var out: UInt32 = 0
        if flags.contains(.command) { out |= UInt32(cmdKey) }
        if flags.contains(.shift)   { out |= UInt32(shiftKey) }
        if flags.contains(.option)  { out |= UInt32(optionKey) }
        if flags.contains(.control) { out |= UInt32(controlKey) }
        return out
    }

    // MARK: - Delivery

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == HotKey.signature else { return noErr }
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKey.shared.onPress?() } }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}
