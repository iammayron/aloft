import AppKit
import SwiftUI

enum Step: Int, CaseIterable {
    case welcome, accessibility, previews, shortcut, firstPin, menuBar, done

    var symbol: String {
        switch self {
        case .welcome:       "pin.fill"
        case .accessibility: "accessibility"
        case .previews:      "photo.on.rectangle.angled"
        case .shortcut:      "keyboard"
        case .firstPin:      "hand.tap.fill"
        case .menuBar:       "menubar.arrow.up.rectangle"
        case .done:          "checkmark.seal.fill"
        }
    }

    var title: String {
        switch self {
        case .welcome:       "Aloft"
        case .accessibility: "Let Aloft see your windows"
        case .previews:      "Show live previews"
        case .shortcut:      "Pick your shortcut"
        case .firstPin:      "Pin your first window"
        case .menuBar:       "The rest lives in the menu bar"
        case .done:          "You're set"
        }
    }

    var body: String {
        switch self {
        case .welcome:
            "Any window, always on top. Pick one from a grid of live previews, or pin whatever you're looking at with a single shortcut."
        case .accessibility:
            "Aloft needs Accessibility to list your open windows and to raise the ones you pin. It never types or clicks for you."
        case .previews:
            "The picker shows a live thumbnail of every open window, so you pick the one you mean at a glance. Screen Recording is what draws them."
        case .shortcut:
            "This pins whichever window you're looking at, from anywhere. Click the key combination to change it."
        case .firstPin:
            "Click any other window to focus it, then press your shortcut. A pin marker appears in its title bar."
        case .menuBar:
            "Open it to pin from a grid of live previews — and to do everything below."
        case .done:
            "Pin from the menu bar grid or with your shortcut — whichever is closer to hand."
        }
    }
}

struct OnboardingView: View {
    static let size = CGSize(width: 540, height: 448)

    @ObservedObject var settings: Settings
    @ObservedObject var windows: WindowList
    @ObservedObject var thumbnails: Thumbnails
    let unlockMenuBar: () -> Void
    let finish: () -> Void

    @State private var step: Step
    @State private var celebrating = false
    @State private var entered = false

    init(settings: Settings, windows: WindowList, thumbnails: Thumbnails,
         unlockMenuBar: @escaping () -> Void, finish: @escaping () -> Void) {
        self.settings = settings
        self.windows = windows
        self.thumbnails = thumbnails
        self.unlockMenuBar = unlockMenuBar
        self.finish = finish
        _step = State(initialValue: Step(rawValue: settings.step) ?? .welcome)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            icon
            copy
            Spacer(minLength: 0)
            controls
            dots
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(backdrop)
        .task(id: step) { await watchForCompletion() }
    }

    // MARK: - Chrome

    private var backdrop: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(colors: [.accentColor.opacity(0.22), .clear],
                           center: .init(x: 0.5, y: 0.26),
                           startRadius: 4, endRadius: 280)
                .blur(radius: 24)
                .animation(.easeInOut(duration: 0.6), value: step)
        }
        .ignoresSafeArea()
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.tint.opacity(0.16))
                .frame(width: 80, height: 80)

            Image(systemName: celebrating ? "checkmark" : step.symbol)
                .font(.system(size: 33, weight: .medium))
                .foregroundStyle(celebrating ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
                .contentTransition(.symbolEffect(.replace.downUp))
                .symbolEffect(.bounce, value: step)
        }
        .scaleEffect(celebrating ? 1.14 : 1)
        .animation(.spring(response: 0.34, dampingFraction: 0.55), value: celebrating)
        .padding(.bottom, 18)
    }

    private var copy: some View {
        VStack(spacing: 9) {
            Text(step.title)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
            Text(step.body)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
        }
        .id(step)                                   // force the transition per step
        .transition(.asymmetric(
            insertion: .offset(x: 26).combined(with: .opacity),
            removal: .offset(x: -26).combined(with: .opacity)))
        .padding(.horizontal, 40)
    }

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 12) {
            switch step {
            case .welcome:
                primary("Get Started") { advance() }

            case .accessibility:
                if AX.isTrusted {
                    grantedLabel("Accessibility granted")
                } else {
                    primary("Grant Access") {
                        if settings.askedAccessibility {
                            AX.openSettings()
                        } else {
                            settings.askedAccessibility = true
                            AX.requestTrust()
                        }
                    }
                    waitingLabel(settings.askedAccessibility
                                 ? "Enable Aloft in the list, then come back"
                                 : "Waiting for permission…")
                }

            case .previews:
                if thumbnails.granted {
                    grantedLabel("Screen Recording granted")
                } else {
                    primary("Enable Previews") {
                        if settings.askedScreenRecording {
                            Thumbnails.openSettings()
                        } else {
                            settings.askedScreenRecording = true
                            Task { await thumbnails.requestAccess() }
                        }
                    }
                    waitingLabel(settings.askedScreenRecording
                                 ? "Enable Aloft in the list, then come back"
                                 : "Waiting for permission…")
                }

            case .shortcut:
                ShortcutRecorder(shortcut: $settings.shortcut)
                    .controlSize(.large)
                primary("Continue") { advance() }

            case .menuBar:
                VStack(alignment: .leading, spacing: 9) {
                    hint("pin", "Click the pin in your menu bar")
                    hint("square.grid.2x2", "Pick any window from the grid to pin it")
                    hint("keyboard", "Change your shortcut in the panel footer")
                    hint("power", "Quit Aloft from that same footer")
                }
                .frame(width: 330)
                waitingLabel("Open the menu bar panel to continue…")

            case .firstPin:
                Text(settings.shortcut.display)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospaced()
                    .foregroundStyle(.tint)
                    .scaleEffect(entered ? 1 : 0.94)
                    .opacity(entered ? 1 : 0.55)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                               value: entered)
                    .onAppear { entered = true }
                    .onDisappear { entered = false }
                waitingLabel("Waiting for your first pin…")

            case .done:
                primary("Start Using Aloft") {
                    Chime.finished.play(if: settings.soundsEnabled)
                    finish()
                }
            }
        }
        .frame(height: step == .menuBar ? 148 : 98)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.rawValue) { item in
                Capsule()
                    .fill(item == step ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: item == step ? 18 : 6, height: 6)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: step)
        .padding(.bottom, 22)
    }

    // MARK: - Pieces

    private func primary(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.glassProminent)
            .controlSize(.large)
    }

    private func secondary(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.glass)
            .controlSize(.small)
    }

    private func hint(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private func grantedLabel(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.green)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    private func waitingLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
    }

    // MARK: - Flow

    /// Steps that gate on something outside the app advance themselves once that
    /// thing is true, so nobody has to come back and press a button they already
    /// earned. Polling beats a notification here: TCC posts none for these.
    private func watchForCompletion() async {
        guard let condition = gate else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(400))
            if condition() { await celebrate(); return }
        }
    }

    private var gate: (() -> Bool)? {
        switch step {
        case .accessibility: { AX.isTrusted }
        case .previews:      { CGPreflightScreenCaptureAccess() }
        case .firstPin:      { !windows.pinned.isEmpty }
        case .menuBar:       { settings.panelSeen }
        default:             nil
        }
    }

    private func celebrate() async {
        if step == .previews { await thumbnails.beginSession() }
        if step == .accessibility { windows.refresh() }
        Chime.granted.play(if: settings.soundsEnabled)
        withAnimation { celebrating = true }
        try? await Task.sleep(for: .milliseconds(900))
        withAnimation { celebrating = false }
        // No step chime here: the grant chime already marked this move, and a second
        // sound with nothing on screen to explain it reads as an error.
        advance(chime: nil)
    }

    private func advance(chime: Chime? = .step) {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        // The menu-bar step asks the user to open the panel, so the icon has to exist
        // by the time they get there.
        if next == .menuBar { unlockMenuBar() }
        settings.step = next.rawValue
        chime?.play(if: settings.soundsEnabled)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { step = next }
    }
}
