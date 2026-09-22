import AppKit
import SwiftUI

@main
struct AloftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra(isInserted: Binding(
            get: { delegate.menuBarReady },
            set: { delegate.menuBarReady = $0 })) {
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
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {
    let windows = WindowList()
    let thumbnails = Thumbnails()
    let settings = Settings()
    @Published var pinning = false
    @Published var menuBarReady = false

    private var monitor: Any?
    private var onboarding: NSWindow?
    private var intro: NSWindow?

    /// Full-screen title card on first run. It sits above everything including the
    /// menu bar, so it is dismissible by click as well as on its own timer.
    private func showIntro() {
        guard let screen = NSScreen.main else { showOnboarding(); return }
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.backgroundColor = .black
        window.isOpaque = false
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: IntroView(soundsEnabled: settings.soundsEnabled, finish: { [weak self] in
            self?.dismissIntro()
        }))
        intro = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        // Nothing should be able to leave a full-screen window stuck over the desktop.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.dismissIntro()
        }
    }

    private func dismissIntro() {
        guard intro != nil else { return }
        intro?.close()
        intro = nil
        showOnboarding()
    }

    /// Onboarding is a real window rather than a menu-bar popover: it has to survive
    /// the user going into System Settings to grant a permission and coming back.
    private func showOnboarding() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: OnboardingView.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: OnboardingView(
            settings: settings, windows: windows, thumbnails: thumbnails,
            unlockMenuBar: { [weak self] in self?.menuBarReady = true },
            finish: { [weak self] in
                self?.settings.onboarded = true
                self?.settings.step = 0
                self?.onboarding?.close()
                self?.onboarding = nil
            }))
        // Without this the hosting view reports the content's ideal height — which the
        // Spacers make unbounded — and grows the window to match.
        host.sizingOptions = []
        window.contentView = host
        window.setContentSize(OnboardingView.size)
        window.center()
        window.delegate = self
        onboarding = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Closing onboarding early must not strand the app with no menu bar icon and no
    /// window — that would leave no way to use or quit it. It must also not count as
    /// finishing: macOS closes this window when the user takes "Quit & Reopen" from
    /// the Screen Recording prompt, and that is the middle of onboarding, not the end.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === onboarding else { return }
        onboarding = nil
        menuBarReady = true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        windows.refresh()
        if settings.onboarded {
            menuBarReady = true
            if !AX.isTrusted { AX.requestTrust() }
        } else {
            if settings.step >= Step.menuBar.rawValue { menuBarReady = true }
            // Resuming mid-flow should not replay the title card.
            settings.step == 0 ? showIntro() : showOnboarding()
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
