import AppKit
import SwiftUI

@main
struct AloftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            PanelView(windows: delegate.windows,
                      thumbnails: delegate.thumbnails,
                      settings: delegate.settings)
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
    let settings = Settings()
    @Published var pinning = false

    private var monitor: Any?
    private var onboarding: NSWindow?

    /// Onboarding is a real window rather than a menu-bar popover: it has to survive
    /// the user going into System Settings to grant a permission and coming back.
    private func showOnboarding() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 470),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: OnboardingView(
            settings: settings, windows: windows, thumbnails: thumbnails,
            finish: { [weak self] in
                self?.settings.onboarded = true
                self?.onboarding?.close()
                self?.onboarding = nil
            }))
        onboarding = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        windows.refresh()
        if settings.onboarded {
            if !AX.isTrusted { AX.requestTrust() }
        } else {
            showOnboarding()
        }

        // Only warm previews when the permission already exists: SCShareableContent is
        // what raises the TCC prompt, and an unexplained prompt at launch is exactly
        // what the "Show previews" button is there to avoid.
        if CGPreflightScreenCaptureAccess() {
            Task { await thumbnails.beginSession() }
        }

        // ⌃⌘T mirrors whatever is frontmost. Only reacts to that one combination.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                guard let self, self.settings.shortcut.matches(event) else { return }
                self.windows.toggleFrontmost()
            }
        }

        Task { @MainActor in
            for await value in windows.$pinned.values { pinning = !value.isEmpty }
        }
    }
}
