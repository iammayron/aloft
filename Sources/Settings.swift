import AppKit
import SwiftUI

/// A recorded hotkey. The label is captured at record time from the event itself,
/// which sidesteps translating a virtual key code back into a character for whatever
/// layout the user types on.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt
    var label: String

    static let fallback = Shortcut(
        keyCode: 17,
        modifiers: NSEvent.ModifierFlags([.control, .command]).rawValue,
        label: "T")

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == flags
    }

    var display: String {
        var out = ""
        if flags.contains(.control) { out += "⌃" }
        if flags.contains(.option)  { out += "⌥" }
        if flags.contains(.shift)   { out += "⇧" }
        if flags.contains(.command) { out += "⌘" }
        return out + label
    }

    /// A hotkey with no modifier would swallow ordinary typing system-wide.
    static func isUsable(_ flags: NSEvent.ModifierFlags) -> Bool {
        !flags.intersection([.control, .option, .command]).isEmpty
    }
}

@MainActor
final class Settings: ObservableObject {
    @Published var shortcut: Shortcut { didSet { write(shortcut, "shortcut") } }
    @Published var soundsEnabled: Bool { didSet { defaults.set(soundsEnabled, forKey: "sounds") } }
    @Published var onboarded: Bool { didSet { defaults.set(onboarded, forKey: "onboarded") } }

    /// Set when the menu-bar panel is first opened, so onboarding can tell that the
    /// user found it. Deliberately not persisted — it only matters within a run.
    @Published var panelSeen = false

    private let defaults = UserDefaults.standard

    init() {
        shortcut = Settings.read(Shortcut.self, "shortcut", from: defaults) ?? .fallback
        soundsEnabled = defaults.object(forKey: "sounds") as? Bool ?? true
        onboarded = defaults.bool(forKey: "onboarded")
    }

    private func write<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func read<T: Decodable>(_: T.Type, _ key: String, from d: UserDefaults) -> T? {
        guard let data = d.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Sound

enum Chime: String {
    case intro = "Submarine"
    case step = "Tink"
    case granted = "Glass"
    case finished = "Hero"

    /// System sounds rather than bundled audio: they already match what the rest of
    /// macOS sounds like, and they follow the user's alert volume.
    func play(if enabled: Bool) {
        guard enabled else { return }
        NSSound(named: rawValue)?.play()
    }
}

// MARK: - Recorder

struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    @State private var recording = false
    @State private var monitor: Any?
    @State private var rejected = false

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Press keys…" : shortcut.display)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .monospaced()
                .frame(minWidth: 96)
                .contentTransition(.numericText())
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .tint(recording ? .accentColor : nil)
        .overlay(alignment: .bottom) {
            if rejected {
                Text("Needs ⌘, ⌃ or ⌥")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .offset(y: 18)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: recording)
        .animation(.easeOut(duration: 0.2), value: rejected)
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        rejected = false
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }        // Escape cancels
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard Shortcut.isUsable(flags) else {
                rejected = true
                return nil
            }
            shortcut = Shortcut(
                keyCode: event.keyCode,
                modifiers: flags.rawValue,
                label: (event.charactersIgnoringModifiers ?? "?").uppercased())
            stop()
            return nil                                           // never reaches the app
        }
    }

    private func stop() {
        recording = false
        rejected = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
