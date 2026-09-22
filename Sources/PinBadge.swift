import AppKit
import ApplicationServices
import SwiftUI

/// A pin marker parked in the top-right of a pinned window's title bar.
///
/// Injecting a real button into another app's title bar is not possible — same
/// window-server restriction that blocks setting its level. So this is a tiny panel
/// of ours that tracks the window's frame. AX move/resize notifications fire
/// continuously while a window is dragged, so it keeps up rather than trailing at
/// whatever rate a poll would run.
@MainActor
final class PinBadges {
    private var badges: [CGWindowID: BadgePanel] = [:]
    var onUnpin: ((CGWindowID) -> Void)?

    func sync(pinned: Set<CGWindowID>, entries: [CGWindowID: WindowEntry]) {
        for id in badges.keys where !pinned.contains(id) { remove(id) }
        for id in pinned where badges[id] == nil {
            guard let entry = entries[id] else { continue }
            let panel = BadgePanel(entry: entry) { [weak self] in self?.onUnpin?(id) }
            badges[id] = panel
            panel.orderFrontRegardless()
        }
    }

    func setVisible(_ id: CGWindowID, _ visible: Bool) {
        badges[id]?.setVisible(visible)
    }

    func reposition(_ id: CGWindowID) { badges[id]?.reposition() }

    func remove(_ id: CGWindowID) {
        badges.removeValue(forKey: id)?.shutDown()
    }

    func removeAll() { for id in badges.keys { remove(id) } }
}

final class BadgePanel: NSPanel {
    private let element: AXUIElement
    private var observer: AXObserver?
    private var shownState = true

    static let dot: CGFloat = 22
    static let slack: CGFloat = 8          // shadow overdraw room
    private static let side = dot + slack * 2

    init(entry: WindowEntry, onUnpin: @escaping () -> Void) {
        element = entry.element
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.side, height: Self.side),
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered, defer: false)

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false                  // window-shaped; ours is drawn to the circle
        isReleasedWhenClosed = false
        ignoresMouseEvents = false

        contentView = NSHostingView(rootView: BadgeView(onUnpin: onUnpin))

        startObserving(pid: entry.pid)
        reposition()
    }

    override var canBecomeKey: Bool { false }

    private func startObserving(pid: pid_t) {
        var created: AXObserver?
        guard AXObserverCreate(pid, { _, _, _, refcon in
            guard let refcon else { return }
            let panel = Unmanaged<BadgePanel>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { panel.reposition() }
        }, &created) == .success, let observer = created else { return }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXWindowMovedNotification, kAXWindowResizedNotification] {
            AXObserverAddNotification(observer, element, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(),
                           AXObserverGetRunLoopSource(observer), .defaultMode)
        self.observer = observer
    }

    func setVisible(_ shown: Bool) {
        guard shown != shownState else { return }
        shownState = shown
        alphaValue = shown ? 1 : 0
    }

    func reposition() {
        guard let frame = Self.axFrame(element),
              let flipBase = NSScreen.screens.first?.frame.maxY else { return }
        // AX reports top-left origin on the primary display; NSWindow wants bottom-left.
        let x = frame.maxX - Self.dot - 8 - Self.slack
        let yFromTop = frame.minY + 5
        setFrameOrigin(NSPoint(x: x, y: flipBase - (yFromTop + Self.dot) - Self.slack))
    }

    func shutDown() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(),
                                  AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        close()
    }

    static func axFrame(_ element: AXUIElement) -> CGRect? {
        guard let position: AXValue = AX.value(element, kAXPositionAttribute),
              let size: AXValue = AX.value(element, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin),
              AXValueGetValue(size, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }
}

private struct BadgeView: View {
    let onUnpin: () -> Void
    @State private var hovering = false
    @State private var appeared = false

    var body: some View {
        Button(action: onUnpin) {
            Circle()
                .fill(.tint)
                .overlay {
                    Image(systemName: hovering ? "xmark" : "pin.fill")
                        .font(.system(size: hovering ? 9 : 10, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
                .shadow(color: .black.opacity(0.28), radius: 4, y: 1)
                .frame(width: BadgePanel.dot, height: BadgePanel.dot)
        }
        .buttonStyle(.plain)
        .help("Unpin this window")
        .scaleEffect(appeared ? (hovering ? 1.12 : 1) : 0.4)
        .opacity(appeared ? 1 : 0)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.34, dampingFraction: 0.62), value: appeared)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: hovering)
        .onAppear { appeared = true }
        .padding(BadgePanel.slack)
    }
}
