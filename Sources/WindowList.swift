import AppKit
import ApplicationServices
import SwiftUI
import os

struct WindowEntry: Identifiable, Hashable {
    let id: CGWindowID
    let title: String
    let appName: String
    let pid: pid_t
    let element: AXUIElement

    static func == (a: WindowEntry, b: WindowEntry) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// Enumerates open windows for the picker.
///
/// Titles come from Accessibility rather than CGWindowListCopyWindowInfo's
/// kCGWindowName, because that one key is gated behind Screen Recording and the
/// picker has to work before the user has granted it.
@MainActor
final class WindowList: ObservableObject {
    @Published private(set) var windows: [WindowEntry] = []
    @Published private(set) var pinned: Set<CGWindowID> = []
    @Published private(set) var trusted = AX.isTrusted

    private let log = Logger(subsystem: "dev.mayron.aloft", category: "scan")
    private var elements: [CGWindowID: AXUIElement] = [:]
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // The z-order the window server reports right at activation is still the
            // old one, so a single tick here decides nothing needs raising. Re-check
            // over the next few frames instead of waiting for the backstop timer.
            Task { @MainActor in
                guard let self else { return }
                self.tick()
                for delay in [40, 100, 200, 380] {
                    try? await Task.sleep(for: .milliseconds(delay))
                    self.tick()
                }
            }
        }
    }

    func refresh() {
        trusted = AX.isTrusted
        guard trusted else { windows = []; return }

        var found: [WindowEntry] = []
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !app.isTerminated {
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { continue }
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            let axWindows: [AXUIElement]
            do {
                axWindows = try AX.valueOrThrow(appElement, kAXWindowsAttribute)
            } catch {
                continue
            }
            for window in axWindows {
                guard let id = AX.windowID(window),
                      AX.value(window, kAXMinimizedAttribute) != true else { continue }
                let title: String = AX.value(window, kAXTitleAttribute) ?? ""
                found.append(WindowEntry(
                    id: id,
                    title: title.isEmpty ? (app.localizedName ?? "Untitled") : title,
                    appName: app.localizedName ?? "Unknown",
                    pid: app.processIdentifier,
                    element: window))
            }
        }
        log.info("refresh: \(found.count, privacy: .public) windows")
        windows = found.sorted { ($0.appName, $0.title) < ($1.appName, $1.title) }
        for entry in found { elements[entry.id] = entry.element }
        pinned.formIntersection(Set(found.map(\.id)))   // drop pins whose window is gone
    }

    // MARK: - Pinning

    func isPinned(_ id: CGWindowID) -> Bool { pinned.contains(id) }

    func toggle(_ entry: WindowEntry) {
        elements[entry.id] = entry.element
        if pinned.remove(entry.id) == nil {
            pinned.insert(entry.id)
            AX.raise(entry.element)
        }
    }

    func unpinAll() { pinned.removeAll() }

    func toggleFrontmost() { if let entry = frontmost() { toggle(entry) } }

    // MARK: - Keeping pinned windows up

    /// macOS gives no usable way to change another process's window level: measured,
    /// SLSSetWindowLevel reports success cross-connection and is ignored, and
    /// SLSSetUniversalOwner is entitlement-gated (rc 1002). So a pin is re-raising a
    /// covered window. Raising only when something actually overlaps keeps the AX
    /// traffic — and the chance of an app's raise handler stealing focus — to when it
    /// is needed.
    private func tick() {
        guard !pinned.isEmpty else { return }
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return }

        let visible: [(id: CGWindowID, frame: CGRect)] = list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 0) > 0,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let raw = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let frame = CGRect(dictionaryRepresentation: raw as CFDictionary)
            else { return nil }
            return (id, frame)
        }

        for id in Self.covered(pinned, in: visible) {
            if let element = elements[id] { AX.raise(element) }
        }
    }

    /// Pure z-order decision, split out so it can be exercised without a window server.
    /// `stack` is front-to-back. A window is covered when any window ahead of it overlaps.
    static func covered(_ pinned: Set<CGWindowID>,
                        in stack: [(id: CGWindowID, frame: CGRect)]) -> [CGWindowID] {
        pinned.filter { id in
            guard let index = stack.firstIndex(where: { $0.id == id }) else { return false }
            let frame = stack[index].frame
            return stack[..<index].contains { $0.frame.intersects(frame) }
        }
    }

    func frontmost() -> WindowEntry? {
        guard AX.isTrusted, let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let window: AXUIElement = AX.value(appElement, kAXFocusedWindowAttribute),
              let id = AX.windowID(window) else { return nil }
        let title: String = AX.value(window, kAXTitleAttribute) ?? ""
        return WindowEntry(id: id,
                           title: title.isEmpty ? (app.localizedName ?? "Untitled") : title,
                           appName: app.localizedName ?? "Unknown",
                           pid: app.processIdentifier,
                           element: window)
    }
}
