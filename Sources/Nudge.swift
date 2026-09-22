import AppKit
import SwiftUI

/// A pointer that parks itself under something the user needs to look at.
/// Used for anything the flow asks for but cannot click on the user's behalf: the
/// menu bar icon arriving in a bar that may already hold twenty others, or the pin
/// marker appearing in a title bar they have never had reason to look at.
@MainActor
final class Coachmark {
    private var panel: NSPanel?

    /// Anchors are in screen (Cocoa) coordinates: centre x, and the y the mark hangs
    /// below.
    func show(_ text: String, symbol: String = "pin.fill", centerX: CGFloat, below y: CGFloat,
              seconds: Double = 12) {
        dismiss()
        present(text: text, symbol: symbol, centerX: centerX, below: y, seconds: seconds)
    }

    /// The status item does not exist the instant the scene inserts it, so this polls
    /// briefly for it rather than firing into an empty menu bar.
    func showAtMenuBar(_ text: String) {
        Task {
            for attempt in 0..<12 {
                if let item = Self.statusItemFrame(), let screen = NSScreen.main {
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
        guard let screen = NSScreen.main else { return }
        let size = NSSize(width: 268, height: 78)
        let window = NSPanel(contentRect: NSRect(origin: .zero, size: size),
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
        window.contentView = NSHostingView(rootView: NudgeView(text: text, symbol: symbol) {
            [weak self] in self?.dismiss()
        })

        window.setFrameOrigin(NSPoint(
            x: min(max(centerX - size.width / 2, screen.visibleFrame.minX + 8),
                   screen.visibleFrame.maxX - size.width - 8),
            y: y - size.height + 12))
        window.orderFrontRegardless()
        panel = window

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
    let dismiss: () -> Void
    @State private var arrived = false
    @State private var bouncing = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 13))
                .foregroundStyle(.tint)
                .offset(y: bouncing ? -4 : 1)
                .animation(.easeInOut(duration: 0.62).repeatForever(autoreverses: true),
                           value: bouncing)

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
        .scaleEffect(arrived ? 1 : 0.7)
        .opacity(arrived ? 1 : 0)
        .animation(.spring(response: 0.42, dampingFraction: 0.62), value: arrived)
        .contentShape(.rect)
        .onTapGesture(perform: dismiss)
        .onAppear { arrived = true; bouncing = true }
    }
}
