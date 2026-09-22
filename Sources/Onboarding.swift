import AppKit
import SwiftUI

enum Step: Int, CaseIterable {
    case welcome, accessibility, previews, shortcut, firstPin, done

    var symbol: String {
        switch self {
        case .welcome:       "pin.fill"
        case .accessibility: "accessibility"
        case .previews:      "photo.on.rectangle.angled"
        case .shortcut:      "keyboard"
        case .firstPin:      "hand.tap.fill"
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
        case .done:          "You're set"
        }
    }

    var body: String {
        switch self {
        case .welcome:
            "Keep any window on top of the others. Pick it from a grid, or pin whatever you're looking at with one shortcut."
        case .accessibility:
            "Aloft needs Accessibility to list your open windows and to raise the ones you pin. It never types or clicks for you."
        case .previews:
            "Screen Recording lets the picker show live thumbnails instead of app icons. Entirely optional — pinning works without it."
        case .shortcut:
            "This pins whichever window you're looking at, from anywhere. Click the key combination to change it."
        case .firstPin:
            "Click any other window to focus it, then press your shortcut. A pin marker appears in its title bar."
        case .done:
            "Aloft lives in your menu bar. Click the pin to open the picker, or use your shortcut anywhere."
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var windows: WindowList
    @ObservedObject var thumbnails: Thumbnails
    let finish: () -> Void

    @State private var step: Step = .welcome
    @State private var celebrating = false
    @State private var entered = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            icon
            copy
            Spacer(minLength: 0)
            controls
            dots
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backdrop)
        .task(id: step) { await watchForCompletion() }
    }

    // MARK: - Chrome

    private var backdrop: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(colors: [.accentColor.opacity(0.22), .clear],
                           center: .init(x: 0.5, y: 0.26),
                           startRadius: 4, endRadius: 320)
                .blur(radius: 24)
                .animation(.easeInOut(duration: 0.6), value: step)
        }
        .ignoresSafeArea()
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.tint.opacity(0.16))
                .frame(width: 92, height: 92)

            Image(systemName: celebrating ? "checkmark" : step.symbol)
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(celebrating ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
                .contentTransition(.symbolEffect(.replace.downUp))
                .symbolEffect(.bounce, value: step)
        }
        .scaleEffect(celebrating ? 1.14 : 1)
        .animation(.spring(response: 0.34, dampingFraction: 0.55), value: celebrating)
        .padding(.bottom, 22)
    }

    private var copy: some View {
        VStack(spacing: 9) {
            Text(step.title)
                .font(.system(size: 23, weight: .semibold, design: .rounded))
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
                    primary("Open Privacy Settings") {
                        AX.requestTrust()
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                    waitingLabel("Waiting for permission…")
                }

            case .previews:
                if thumbnails.granted {
                    grantedLabel("Screen Recording granted")
                } else {
                    primary("Enable Previews") {
                        Task { await thumbnails.requestAccess() }
                    }
                    secondary("Skip — use app icons") { advance() }
                }

            case .shortcut:
                ShortcutRecorder(shortcut: $settings.shortcut)
                primary("Continue") { advance() }

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
        .frame(height: 104)
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
        .padding(.bottom, 26)
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
        advance()
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        Chime.step.play(if: settings.soundsEnabled)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { step = next }
    }
}
