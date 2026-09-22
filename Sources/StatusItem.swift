import AppKit
import SwiftUI

/// The menu bar icon and its panel, managed directly rather than through
/// `MenuBarExtra(isInserted:)`.
///
/// That modifier never inserted the icon when the flag flipped: a Scene body does not
/// reliably re-evaluate for a delegate's published property, so the icon stayed absent
/// no matter what the flag said. An NSStatusItem is created when we say so, and it
/// also hands us the button's real frame, which is what a coachmark needs to point at.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private var item: NSStatusItem?
    private let popover = NSPopover()
    var onOpen: (() -> Void)?

    /// Only once the status item has actually been placed in the menu bar. Straight
    /// after creation its window reports a (0,0) origin, which is a real rect with a
    /// real size and silently anchors anything that trusts it to the bottom-left of
    /// the screen.
    var buttonFrame: CGRect? {
        // The status window is wider than the icon it holds, so its midX is not the
        // icon's centre. Convert the button's own bounds instead. And before the item
        // is placed the window reports a (0,0) origin, a real rect with a real size
        // that silently anchors anything trusting it to the bottom of the screen.
        guard let button = item?.button, let window = button.window else { return nil }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard frame.width > 0, frame.height > 0,
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }),
              frame.maxY > screen.visibleFrame.maxY        // inside the menu bar strip
        else { return nil }
        return frame
    }

    func install<Content: View>(@ViewBuilder content: () -> Content) {
        guard item == nil else { return }

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: content())
        popover.delegate = self

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "Aloft")
        item.button?.image?.isTemplate = true
        item.button?.target = self
        item.button?.action = #selector(toggle)
        self.item = item
    }

    func setPinning(_ pinning: Bool) {
        let name = pinning ? "pin.fill" : "pin"
        item?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Aloft")
        item?.button?.image?.isTemplate = true
    }

    @objc private func toggle() {
        guard let button = item?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
            popover.contentViewController?.view.window?.makeKey()
            onOpen?()
        }
    }

    func close() { popover.performClose(nil) }
}
