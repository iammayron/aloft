import AppKit
import SwiftUI

@main
struct AloftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            PanelView(windows: delegate.windows, thumbnails: delegate.thumbnails)
        } label: {
            Image(systemName: delegate.pinning ? "pin.fill" : "pin")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let windows = WindowList()
    let thumbnails = Thumbnails()
    @Published var pinning = false

    private var monitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !AX.isTrusted { AX.requestTrust() }
        windows.refresh()

        // Only warm previews when the permission already exists: SCShareableContent is
        // what raises the TCC prompt, and an unexplained prompt at launch is exactly
        // what the "Show previews" button is there to avoid.
        if CGPreflightScreenCaptureAccess() {
            Task { await thumbnails.beginSession() }
        }

        // ⌃⌘T mirrors whatever is frontmost. Only reacts to that one combination.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 17,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.control, .command]
            else { return }
            Task { @MainActor in self?.windows.toggleFrontmost() }
        }

        Task { @MainActor in
            for await value in windows.$pinned.values { pinning = !value.isEmpty }
        }
    }
}
