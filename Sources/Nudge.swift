import AppKit
import SwiftUI
import os

/// A pointer that parks itself under something the user needs to look at, and stays
/// until they act on it.
@MainActor
final class Coachmark {
    private var panel: NSPanel?
    private var host: NSHostingView<NudgeView>?
    private var anchor: (() -> CGRect?)?
    private var text = ""
    private let log = Logger(subsystem: "dev.mayron.aloft", category: "nudge")

    /// The window is deliberately larger than the bubble: a window sized to its
    /// content clips the bob and the shadow at its own edge.
    private static let size = NSSize(width: 290, height: 82)
    /// How far the tip rides up into the menu bar button.
    private static let overlap: CGFloat = 5

    /// `anchor` is re-read while the mark is up: menu bar items shift whenever another
    /// app adds or drops one, and a mark measured once drifts off its target.
    func follow(_ text: String, anchor: @escaping () -> CGRect?) {
        self.text = text
        self.anchor = anchor
        guard place() else { return }
        Task { @MainActor in
            while panel != nil {
                try? await Task.sleep(for: .milliseconds(900))
                _ = place()
            }
        }
    }

    func dismiss() {
        panel?.close()
        panel = nil
        host = nil
        anchor = nil
    }

    @discardableResult
    private func place() -> Bool {
        guard let target = anchor?() else { return false }

        let point = NSPoint(x: target.midX, y: target.minY - 1)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else {
            log.error("no screen at \(target.midX, privacy: .public),\(target.minY, privacy: .public)")
            return false
        }

        let size = Self.size
        let originX = min(max(target.midX - size.width / 2, screen.frame.minX + 6),
                          screen.frame.maxX - size.width - 6)
        // Where the screen edge pushes the bubble off its target, the pointer slides
        // along it instead. Must be known before the view is built.
        let reach = size.width / 2 - 24
        let arrow = min(max(target.midX - (originX + size.width / 2), -reach), reach)
        // Content is pinned to the top of the window, so place the window such that
        // the bubble's top edge lands just inside the button's bottom edge.
        let origin = NSPoint(x: originX, y: target.minY + Self.overlap - size.height)

        if let panel, let host {
            host.rootView = NudgeView(text: text, arrowOffset: arrow) { [weak self] in self?.dismiss() }
            panel.setFrameOrigin(origin)
            return true
        }

        let view = NudgeView(text: text, arrowOffset: arrow) { [weak self] in self?.dismiss() }
        let host = NSHostingView(rootView: view)
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
        window.contentView = host
        window.setFrameOrigin(origin)
        window.orderFrontRegardless()
        panel = window
        self.host = host

        log.info("mark at \(origin.x, privacy: .public),\(origin.y, privacy: .public) arrow \(arrow, privacy: .public) target \(target.debugDescription, privacy: .public)")
        return true
    }
}

/// Capsule and pointer as a single path, so the glass is continuous across both.
/// Drawn as two shapes they read as a blue triangle sitting near a grey pill.
private struct Bubble: Shape {
    var arrowOffset: CGFloat

    static let arrowHeight: CGFloat = 8
    static let arrowWidth: CGFloat = 17

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY + Self.arrowHeight,
                          width: rect.width, height: rect.height - Self.arrowHeight)
        var path = Path(roundedRect: body, cornerRadius: body.height / 2, style: .continuous)

        let tip = min(max(rect.midX + arrowOffset, body.minX + Self.arrowWidth),
                      body.maxX - Self.arrowWidth)
        path.move(to: CGPoint(x: tip - Self.arrowWidth / 2, y: body.minY + 2))
        path.addLine(to: CGPoint(x: tip, y: rect.minY))
        path.addLine(to: CGPoint(x: tip + Self.arrowWidth / 2, y: body.minY + 2))
        path.closeSubpath()
        return path
    }
}

private struct NudgeView: View {
    let text: String
    let arrowOffset: CGFloat
    let dismiss: () -> Void

    @State private var arrived = false
    @State private var bobbing = false

    var body: some View {
        VStack(spacing: 0) {
            bubble
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var bubble: some View {
        let shape = Bubble(arrowOffset: arrowOffset)

        return HStack(spacing: 8) {
            Image(systemName: "pin.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tint)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
        }
        // Glass takes on whatever is behind the window, so the label carries its own
        // legibility rather than trusting one frame of the desktop.
        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
        .shadow(color: .black.opacity(0.3), radius: 9, y: 2)
        .padding(.horizontal, 14)
        .padding(.top, Bubble.arrowHeight + 9)
        .padding(.bottom, 9)
        .glassEffect(.regular, in: shape)
        .clipShape(shape)
        .shadow(color: .black.opacity(0.24), radius: 10, y: 3)
        // Bobs downward only: the tip should stay against the menu bar, not lift off it.
        .offset(y: bobbing ? 4 : 0)
        .animation(.easeInOut(duration: 0.68).repeatForever(autoreverses: true), value: bobbing)
        .scaleEffect(arrived ? 1 : 0.8, anchor: .top)
        .opacity(arrived ? 1 : 0)
        .animation(.spring(response: 0.4, dampingFraction: 0.68), value: arrived)
        .contentShape(.rect)
        .onTapGesture(perform: dismiss)
        .onAppear { arrived = true; bobbing = true }
    }
}
