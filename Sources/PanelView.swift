import AppKit
import SwiftUI

struct PanelView: View {
    @ObservedObject var windows: WindowList
    @ObservedObject var thumbnails: Thumbnails
    @ObservedObject var settings: Settings
    @ObservedObject var updater: Updater
    @State private var query = ""

    private static let repository = "https://github.com/iammayron/aloft"

    private static func open(_ address: String) {
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
    private static let rowSpacing: CGFloat = 10
    private static let gridPadding: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.5)

            if !windows.trusted {
                requestCard(
                    title: "Accessibility access needed",
                    body: "Aloft reads the list of open windows and keeps the pinned ones raised. It never types or clicks for you.",
                    button: "Grant Access") {
                        if settings.askedAccessibility {
                            AX.openSettings()
                        } else {
                            settings.askedAccessibility = true
                            AX.requestTrust()
                        }
                    }
            } else if !thumbnails.granted {
                // Previews are part of the picker, not a bonus on top of it. Falling
                // back to a grid of app icons is worse than asking for the permission.
                requestCard(
                    title: "Screen Recording turned off",
                    body: "Aloft shows a live preview of every window so you can pick the one you mean. Turn it back on to use the picker.",
                    button: "Enable Previews") {
                        if settings.askedScreenRecording {
                            Thumbnails.openSettings()
                        } else {
                            settings.askedScreenRecording = true
                            Task { await thumbnails.requestAccess() }
                        }
                    }
            } else {
                search
                grid
            }

            updateBanner
                .animation(.spring(response: 0.32, dampingFraction: 0.85), value: updater.phase)
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 452)
        .onChange(of: settings.panelClosed) { query = "" }
        .task {
            settings.panelSeen = true
            query = ""

            windows.refresh()
            await thumbnails.beginSession()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "pin.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tint)
            Text("Aloft").font(.headline)
            if ready, !windows.pinned.isEmpty {
                Text("\(windows.pinned.count) pinned")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if ready, !windows.pinned.isEmpty {
                Button("Unpin All") { windows.unpinAll() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
            Menu {
                Button("Check for Updates") { Task { await updater.check(manual: true) } }
                Toggle("Check Automatically", isOn: $settings.autoUpdate)

                Divider()

                Button("About the Developer") { Self.open("https://mayronalves.com") }
                Button("View on GitHub") { Self.open(Self.repository) }
                Button("Report an Issue") { Self.open("\(Self.repository)/issues/new") }

                Divider()

                Text("Aloft \(Updater.current)")
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Updates")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Search

    private var search: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Search windows", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: query.isEmpty)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 7))
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)     // breathing room before the first row of previews
    }

    private var filtered: [WindowEntry] {
        let matches = query.isEmpty ? windows.windows : windows.windows.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.appName.localizedCaseInsensitiveContains(query)
        }
        // Pinned first so what you are already using never needs scrolling to.
        // A stable partition keeps the app/title ordering within each half.
        return matches.filter { windows.isPinned($0.id) }
            + matches.filter { !windows.isPinned($0.id) }
    }

    // MARK: - Tiles

    /// A ScrollView reports no ideal height, so inside a fitting-size menu bar window
    /// it collapses to nothing and takes its content with it. Size it from the tile
    /// count instead of hoping maxHeight will be taken up.
    private var gridHeight: CGFloat {
        guard !filtered.isEmpty else { return 120 }
        let rows = ceil(Double(filtered.count) / Double(Self.columns.count))
        let content = rows * WindowTile.height
            + (rows - 1) * Self.rowSpacing
            + Self.gridPadding * 2
        return min(420, content)
    }

    private var grid: some View {
        ScrollView {
            if filtered.isEmpty {
                Text(windows.windows.isEmpty ? "No open windows" : "No matches")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                LazyVGrid(columns: Self.columns, spacing: Self.rowSpacing) {
                    ForEach(filtered) { entry in
                        WindowTile(entry: entry,
                                   pinned: windows.isPinned(entry.id),
                                   preview: thumbnails.images[entry.id]) {
                            windows.toggle(entry)
                        }
                        .task(id: thumbnails.sessionToken) { await thumbnails.load(entry.id) }
                    }
                }
                .padding(Self.gridPadding)
            }
        }
        .frame(height: gridHeight)
    }

    // MARK: - Permission

    private var ready: Bool { windows.trusted && thumbnails.granted }

    private func requestCard(title: String, body: String, button: String,
                             action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(body)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(button, action: action)
                .buttonStyle(.glassProminent)
                .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer

    /// Only ever one line, and only when there is something to say. An update notice
    /// that is always present becomes furniture nobody reads.
    @ViewBuilder
    private var updateBanner: some View {
        switch updater.phase {
        case let .available(version):
            bannerRow {
                Text("Aloft \(version) is available")
                Spacer()
                Button("Update") { Task { await updater.install() } }
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
            }
        case .checking:
            bannerRow {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text("Checking for updates…")
                Spacer()
            }
        case .upToDate:
            bannerRow {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Aloft \(Updater.current) is the latest version")
                Spacer()
            }
        case .downloading, .installing:
            bannerRow {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text(updater.phase == .downloading ? "Downloading update…" : "Installing…")
                Spacer()
            }
        case let .failed(reason):
            bannerRow {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(reason)
                Spacer()
            }
        case .idle:
            EmptyView()
        }
    }

    private func bannerRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            HStack(spacing: 7) { content() }
                .font(.system(size: 11))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if ready {
                Text("Pin frontmost")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                ShortcutRecorder(shortcut: $settings.shortcut, compact: true, active: settings.shortcutActive,
                                 conflict: settings.conflictingApp)
                    .controlSize(.mini)
            }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Tile

private struct WindowTile: View {
    let entry: WindowEntry
    let pinned: Bool
    let preview: NSImage?
    let action: () -> Void

    @State private var hovering = false

    static let thumbnailHeight: CGFloat = 116
    static let height: CGFloat = thumbnailHeight + 6 + 15   // thumbnail + spacing + caption

    private static let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    private var appIcon: NSImage? {
        NSRunningApplication(processIdentifier: entry.pid)?.icon
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                thumbnail
                caption
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var thumbnail: some View {
        ZStack {
            Rectangle().fill(.quaternary.opacity(0.5))

            if let preview {
                Image(nsImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(6)
            } else if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 44, height: 44)
                    .opacity(0.85)
            }

            if pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(.tint, in: .circle)
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .topTrailing)
            }
        }
        .frame(height: Self.thumbnailHeight)
        .clipShape(Self.shape)
        .overlay {
            Self.shape.strokeBorder(
                pinned ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                lineWidth: pinned ? 2 : 1)
        }
        .overlay {
            if hovering && !pinned {
                Self.shape.fill(.white.opacity(0.08))
            }
        }
    }

    private var caption: some View {
        HStack(spacing: 5) {
            if let appIcon {
                Image(nsImage: appIcon).resizable().frame(width: 13, height: 13)
            }
            Text(entry.title)
                .font(.system(size: 11))
                .foregroundStyle(pinned ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 2)
    }
}
