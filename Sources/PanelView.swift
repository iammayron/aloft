import AppKit
import SwiftUI

struct PanelView: View {
    @ObservedObject var windows: WindowList
    @ObservedObject var thumbnails: Thumbnails
    @ObservedObject var settings: Settings
    @State private var query = ""

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
    private static let rowSpacing: CGFloat = 10
    private static let gridPadding: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.5)

            if windows.trusted {
                search
                grid
            } else {
                permissionRequest
            }

            Divider().opacity(0.5)
            footer
        }
        .frame(width: 452)
        .task {
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
            if !windows.pinned.isEmpty {
                Text("\(windows.pinned.count) pinned")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !windows.pinned.isEmpty {
                Button("Unpin All") { windows.unpinAll() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
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

    private var permissionRequest: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Accessibility access needed")
                .font(.system(size: 12, weight: .semibold))
            Text("Aloft reads the list of open windows and keeps the pinned ones raised. It never types or clicks for you.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Privacy Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.small)
        }
        .padding(14)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            if windows.trusted && !thumbnails.granted {
                Button {
                    Task { await thumbnails.requestAccess() }
                } label: {
                    Label("Show previews", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("Screen Recording lets Aloft draw live window previews. Pinning works without it.")
            } else {
                Text("Pin frontmost")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                ShortcutRecorder(shortcut: $settings.shortcut)
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
