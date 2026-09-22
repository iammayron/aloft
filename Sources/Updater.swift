import AppKit
import SwiftUI
import os

/// Checks GitHub Releases and installs a newer build in place.
///
/// No Sparkle: the whole update is one JSON request, one download, and a disk image
/// swap, which is less code than wiring in a framework and leaves nothing running in
/// the background.
@MainActor
final class Updater: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case available(String)
        case downloading
        case installing
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastChecked: Date?

    private let log = Logger(subsystem: "dev.mayron.aloft", category: "update")
    private var timer: Timer?
    private var downloadURL: URL?

    static let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        as? String ?? "0"

    private static let feed = URL(string:
        "https://api.github.com/repos/iammayron/aloft/releases/latest")!

    /// Starts (or stops) the daily check. Called again whenever the preference flips.
    func setAutomatic(_ enabled: Bool) {
        timer?.invalidate()
        timer = nil
        guard enabled else { return }
        Task { await check() }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
    }

    // MARK: - Check

    func check(manual: Bool = false) async {
        if case .downloading = phase { return }
        if case .installing = phase { return }
        phase = .checking

        do {
            var request = URLRequest(url: Self.feed)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15
            let (data, _) = try await URLSession.shared.data(for: request)
            let release = try JSONDecoder().decode(Release.self, from: data)

            let version = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            lastChecked = .now
            downloadURL = release.assets.first { $0.name.hasSuffix(".dmg") }?.browser_download_url

            if Self.isNewer(version, than: Self.current), downloadURL != nil {
                phase = .available(version)
            } else {
                phase = .idle
                if manual { log.info("up to date at \(Self.current, privacy: .public)") }
            }
        } catch {
            log.error("check failed: \(String(describing: error), privacy: .public)")
            phase = manual ? .failed("Could not reach GitHub") : .idle
        }
    }

    /// Numeric component compare, so 1.0.10 beats 1.0.9 where a string compare would not.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let left = index < a.count ? a[index] : 0
            let right = index < b.count ? b[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    // MARK: - Install

    func install() async {
        guard let url = downloadURL else { return }
        phase = .downloading
        do {
            let (file, _) = try await URLSession.shared.download(from: url)
            phase = .installing
            try await Self.swapBundle(usingImageAt: file)
            relaunch()
        } catch {
            log.error("install failed: \(String(describing: error), privacy: .public)")
            phase = .failed(error.localizedDescription)
        }
    }

    private static func swapBundle(usingImageAt image: URL) async throws {
        let mount = try run("/usr/bin/hdiutil",
                            ["attach", image.path, "-nobrowse", "-readonly", "-mountrandom", "/tmp"])
        guard let point = mount.split(separator: "\n").last?
            .split(separator: "\t").last.map(String.init)?
            .trimmingCharacters(in: .whitespaces), !point.isEmpty else {
            throw Failure.message("Could not mount the download")
        }
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", point, "-quiet"]) }

        let source = URL(fileURLWithPath: point).appendingPathComponent("Aloft.app")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw Failure.message("The download did not contain Aloft.app")
        }

        // A download can carry the quarantine flag, and this build is unsigned by
        // Apple, so strip it before the copy becomes the running app.
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", source.path])

        let destination = Bundle.main.bundleURL
        let staged = destination.deletingLastPathComponent()
            .appendingPathComponent("Aloft-update.app")
        try? FileManager.default.removeItem(at: staged)
        try FileManager.default.copyItem(at: source, to: staged)
        _ = try FileManager.default.replaceItemAt(destination, withItemAt: staged)
    }

    private nonisolated static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure.message("\(tool) exited \(process.terminationStatus)")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL,
                                           configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    // MARK: - Types

    private struct Release: Decodable {
        let tag_name: String
        let assets: [Asset]
    }

    private struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
    }

    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case let .message(text) = self { text } else { nil } }
    }
}
