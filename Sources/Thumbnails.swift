import AppKit
import ScreenCaptureKit
import SwiftUI
import os

/// Live window previews for the picker.
///
/// This is the *only* part of Aloft that wants Screen Recording, and it is optional:
/// with the permission the picker shows real window thumbnails, without it the tiles
/// fall back to app icons and pinning is unaffected. Nothing here is ever streamed or
/// written to disk — a still is captured when a tile scrolls into view and kept in
/// memory until the panel closes.
@MainActor
final class Thumbnails: ObservableObject {
    @Published private(set) var images: [CGWindowID: NSImage] = [:]
    @Published private(set) var granted = CGPreflightScreenCaptureAccess()
    /// Bumped whenever the snapshot is replaced. Tiles key their load on it, so a
    /// permission granted *after* a tile appeared still fills that tile in.
    @Published private(set) var sessionToken = 0

    private let log = Logger(subsystem: "dev.mayron.aloft", category: "preview")
    private var snapshot: [CGWindowID: SCWindow] = [:]
    private var loading: Set<CGWindowID> = []

    /// Longest edge of a captured still. Tiles are ~200pt wide, so this covers 2x.
    private static let targetWidth = 440

    func beginSession() async {
        granted = CGPreflightScreenCaptureAccess()
        guard granted else { snapshot = [:]; images = [:]; return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                true, onScreenWindowsOnly: true)
            snapshot = Dictionary(content.windows.map { ($0.windowID, $0) },
                                  uniquingKeysWith: { first, _ in first })
        } catch {
            log.info("SCShareableContent failed: \(String(describing: error), privacy: .public)")
            granted = false
            snapshot = [:]
        }
        log.info("session: granted=\(self.granted, privacy: .public) windows=\(self.snapshot.count, privacy: .public)")
        images = [:]   // stills go stale the moment the user does anything
        loading = []
        sessionToken += 1
    }

    /// Raises the system prompt and nothing else. Opening the Settings pane in the
    /// same click stacks a second window on top of that dialog, which reads as the
    /// app having fired twice.
    func requestAccess() async {
        _ = CGRequestScreenCaptureAccess()
        granted = CGPreflightScreenCaptureAccess()
        await beginSession()
    }

    static func openSettings() {
        NSWorkspace.shared.open(URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    func load(_ id: CGWindowID) async {
        guard granted, images[id] == nil, !loading.contains(id),
              let window = snapshot[id], window.frame.width > 0 else { return }
        loading.insert(id)
        defer { loading.remove(id) }

        let scale = min(1, CGFloat(Self.targetWidth) / window.frame.width)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(window.frame.width * scale))
        configuration.height = max(1, Int(window.frame.height * scale))
        configuration.showsCursor = false
        configuration.ignoreGlobalClipDisplay = true

        guard let cgImage = try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window),
            configuration: configuration) else {
            log.info("capture failed for \(id, privacy: .public)")
            return
        }

        images[id] = NSImage(cgImage: cgImage,
                             size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
