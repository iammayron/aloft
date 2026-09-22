import AppKit
import SwiftUI
import os

@main
struct AloftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // The menu bar icon is an NSStatusItem owned by the delegate, not a MenuBarExtra.
    // This scene exists only because an App must declare one.
    var body: some Scene {
        SwiftUI.Settings { EmptyView() }   // our own Settings class shadows the scene
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {
    let windows = WindowList()
    let thumbnails = Thumbnails()
    let settings = Settings()
    @Published var pinning = false
    @Published var menuBarReady = false {
        didSet {
            guard menuBarReady, !oldValue else { return }
            installStatusItem()
        }
    }

    private let coachmark = Coachmark()
    private let statusItem = StatusItemController()

    private var onboarding: NSWindow?
    private var intro: NSWindow?

    private func installStatusItem() {
        statusItem.onOpen = { [weak self] in self?.coachmark.dismiss() }
        statusItem.onClose = { [weak self] in self?.settings.panelClosed += 1 }
        statusItem.install { [self] in
            PanelView(windows: windows, thumbnails: thumbnails, settings: settings)
        }
        // The mark teaches where the icon is. Once onboarding is done it would just be
        // noise on every launch.
        guard !settings.onboarded else { return }

        // The button has no placed window the instant it is created, so wait for a
        // real frame rather than anchoring the mark to a zero rect.
        Task { @MainActor in
            for attempt in 0..<12 {
                if statusItem.buttonFrame != nil {
                    coachmark.follow("Click here to open Aloft") { [weak self] in
                        self?.statusItem.buttonFrame
                    }
                    return
                }
                try? await Task.sleep(for: .milliseconds(attempt < 3 ? 120 : 400))
            }
        }
    }

    /// Pinning never changes which app is in front, so if something else is frontmost
    /// a moment later, another app answered the same key press. That is the only
    /// detectable trace of a conflict with an event-tap hotkey.
    private func pinFrontmost() {
        let before = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        windows.toggleFrontmost()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(550))
            guard let now = NSWorkspace.shared.frontmostApplication,
                  now.bundleIdentifier != before,
                  now.processIdentifier != ProcessInfo.processInfo.processIdentifier
            else { return }
            settings.conflictingApp = now.localizedName
        }
    }

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
            refocus: { [weak self] in
                NSApp.activate(ignoringOtherApps: true)
                self?.onboarding?.makeKeyAndOrderFront(nil)
            },
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

        // Only warm previews when the permission already exists. SCShareableContent is
        // what raises the TCC prompt, and a prompt at launch, before anything has
        // explained why, is the one place it should never appear.
        if CGPreflightScreenCaptureAccess() {
            Task { await thumbnails.beginSession() }
        }

        HotKey.shared.onPress = { [weak self] in self?.pinFrontmost() }
        if !settings.hasStoredShortcut { settings.shortcut = Shortcut.firstAvailable() }
        settings.shortcutActive = HotKey.shared.apply(settings.shortcut)

        Task { @MainActor in
            for await seen in settings.$panelSeen.values where seen { coachmark.dismiss() }
        }

        Task { @MainActor in
            for await shortcut in settings.$shortcut.values {
                settings.conflictingApp = nil        // a new combination is unproven, not guilty
                settings.shortcutActive = HotKey.shared.apply(shortcut)
            }
        }

        Task { @MainActor in
            for await value in windows.$pinned.values {
                pinning = !value.isEmpty
                statusItem.setPinning(pinning)
            }
        }
    }
}
