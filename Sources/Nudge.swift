import AppKit
import SwiftUI
import os

/// A pointer that parks itself under something the user needs to look at.
/// Used for anything the flow asks for but cannot click on the user's behalf: the
/// menu bar icon arriving in a bar that may already hold twenty others, or the pin
/// marker appearing in a title bar they have never had reason to look at.
@MainActor
final class Coachmark {
    private var panel: NSPanel?
    private let log = Logger(subsystem: "dev.mayron.aloft", category: "nudge")

    /// Anchors are in screen (Cocoa) coordinates: centre x, and the y the mark hangs
    /// below. `seconds: 0` keeps it up until the user acts, which is what a mark
    /// asking for a click needs.
    func show(_ text: String, symbol: String = "pin.fill", centerX: CGFloat, below y: CGFloat,
              seconds: Double = 0) {
        dismiss()
        present(text: text, symbol: symbol, centerX: centerX, below: y, seconds: seconds)
    }

    /// The status item does not exist the instant the scene inserts it, so this polls
    /// briefly for it rather than firing into an empty menu bar.
    func showAtMenuBar(_ text: String) {
        Task {
            for attempt in 0..<12 {
                if let item = Self.statusItemFrame(),
                   let screen = NSScreen.screens.first(where: { $0.frame.intersects(item) })
                    ?? NSScreen.main {
                    show(text, centerX: item.midX, below: screen.visibleFrame.maxY)
                    return
                }
                try? await Task.sleep(for: .milliseconds(attempt < 4 ? 120 : 400))
            }
        }
    }

    func dismiss() {
        panel?.close()
        panel = nil
    }

    private func present(text: String, symbol: String, centerX: CGFloat, below y: CGFloat,
                         seconds: Double) {
        // The anchor decides the screen. NSScreen.main is whichever screen holds the
        // focused window, so on a second display it clamps the mark to the wrong one
        // and the arrow ends up pointing at nothing.
        let anchor = NSPoint(x: centerX, y: y - 1)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) })
            ?? NSScreen.main else {
            log.error("no screen contains anchor \(centerX, privacy: .public),\(y, privacy: .public)")
            return
        }

        let size = NSSize(width: 268, height: 74)
        let originX = min(max(centerX - size.width / 2, screen.visibleFrame.minX + 8),
                          screen.visibleFrame.maxX - size.width - 8)
        // When the screen edge pushes the capsule off its anchor, the arrow slides
        // inside it instead. This has to be known before the view is built.
        let reach = size.width / 2 - 26
        let arrowOffset = min(max(centerX - (originX + size.width / 2), -reach), reach)
        let origin = NSPoint(x: originX, y: y - size.height)
        guard screen.frame.contains(NSPoint(x: origin.x + size.width / 2,
                                            y: origin.y + size.height - 2)) else {
            log.error("refusing off-screen mark at \(origin.x, privacy: .public),\(origin.y, privacy: .public)")
            return
        }

        let window = NSPanel(contentRect: NSRect(origin: origin, size: size),
                             styleMask: [.nonactivatingPanel, .borderless],
                             backing: .buffered, defer: false)
        window.isFloatingPanel = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.hidesOnDeactivate = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: NudgeView(
            text: text, symbol: symbol, arrowOffset: arrowOffset) { [weak self] in self?.dismiss() })
        window.setFrameOrigin(origin)
        window.orderFrontRegardless()
        panel = window

        log.info("mark at \(origin.x, privacy: .public),\(origin.y, privacy: .public) arrow \(arrowOffset, privacy: .public) screen \(screen.frame.debugDescription, privacy: .public)")

        // seconds <= 0 means it stays until the user acts on it.
        guard seconds > 0 else { return }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            dismiss()
        }
    }

    /// Our own status item is the only window this process owns at the status layer.
    private static func statusItemFrame() -> CGRect? {
        let pid = ProcessInfo.processInfo.processIdentifier
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .optionIncludingWindow],
                                                    kCGNullWindowID) as? [[String: Any]]
            ?? CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
        else { return nil }

        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 25,
                  let raw = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let frame = CGRect(dictionaryRepresentation: raw as CFDictionary),
                  frame.width < 200, frame.height < 40
            else { continue }
            return frame
        }
        return nil
    }
}

private struct NudgeView: View {
    let text: String
    let symbol: String
    let arrowOffset: CGFloat
    let dismiss: () -> Void
    @State private var arrived = false
    @State private var bouncing = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 13))
                .foregroundStyle(.tint)
                .offset(x: arrowOffset)

            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tint)
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
            }
            // Glass takes on whatever is behind the window, so the label carries its
            // own legibility rather than trusting one frame of the desktop.
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
            .shadow(color: .black.opacity(0.3), radius: 9, y: 2)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: .capsule)
            .clipShape(.capsule)
            .shadow(color: .black.opacity(0.22), radius: 11, y: 3)
        }
        .padding(.top, 2)
        // The whole mark bobs, not just the arrowhead: movement at this size reads
        // from the corner of the eye, a 4pt twitch does not.
        .offset(y: bouncing ? -7 : 3)
        .animation(.easeInOut(duration: 0.66).repeatForever(autoreverses: true), value: bouncing)
        .scaleEffect(arrived ? 1 : 0.7)
        .opacity(arrived ? 1 : 0)
        .animation(.spring(response: 0.42, dampingFraction: 0.62), value: arrived)
        .contentShape(.rect)
        .onTapGesture(perform: dismiss)
        .onAppear { arrived = true; bouncing = true }
    }
}
