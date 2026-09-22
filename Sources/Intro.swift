import AppKit
import SwiftUI

/// The first-run title card: drifting blurred colour, then the icon and name.
/// Hands off to the onboarding window when it finishes, or when the user clicks
/// to skip it.
struct IntroView: View {
    let soundsEnabled: Bool
    let finish: () -> Void

    @State private var pad = AmbientPad()

    @State private var showMark = false
    @State private var showName = false
    @State private var leaving = false

    var body: some View {
        ZStack {
            backdrop
            bubbles
            mark
        }
        .opacity(leaving ? 0 : 1)
        .animation(.easeInOut(duration: 0.55), value: leaving)
        .ignoresSafeArea()
        .contentShape(.rect)
        .onTapGesture { exit() }
        .task { await run() }
    }

    // MARK: - Colour

    private static let palette: [Color] = [
        Color(red: 0.02, green: 0.03, blue: 0.12), Color(red: 0.06, green: 0.17, blue: 0.52), Color(red: 0.02, green: 0.04, blue: 0.14),
        Color(red: 0.13, green: 0.31, blue: 0.86), Color(red: 0.36, green: 0.42, blue: 0.98), Color(red: 0.32, green: 0.16, blue: 0.72),
        Color(red: 0.02, green: 0.04, blue: 0.16), Color(red: 0.09, green: 0.22, blue: 0.62), Color(red: 0.03, green: 0.03, blue: 0.10),
    ]

    /// Corners stay pinned; only the edge midpoints and the centre wander, which is
    /// what keeps the drift from looking like the whole image sliding.
    private func meshPoints(_ t: Double) -> [SIMD2<Float>] {
        func w(_ amount: Double, _ speed: Double, _ phase: Double) -> Float {
            Float(amount * sin(t * speed + phase))
        }
        return [
            .init(0, 0), .init(0.5 + w(0.13, 0.31, 0.0), 0), .init(1, 0),
            .init(0, 0.5 + w(0.11, 0.24, 1.1)),
            .init(0.5 + w(0.20, 0.19, 2.2), 0.5 + w(0.17, 0.27, 3.3)),
            .init(1, 0.5 + w(0.11, 0.22, 4.4)),
            .init(0, 1), .init(0.5 + w(0.13, 0.26, 5.5), 1), .init(1, 1),
        ]
    }

    private var backdrop: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            MeshGradient(width: 3, height: 3, points: meshPoints(t), colors: Self.palette)
                .blur(radius: 34)
                .scaleEffect(1.25)          // hide the blur's soft edge past the bounds
        }
    }

    private var bubbles: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geometry in
                ForEach(Array(Self.bubbleSeeds.enumerated()), id: \.offset) { index, seed in
                    Circle()
                        .fill(seed.tint.opacity(0.30))
                        .frame(width: seed.size, height: seed.size)
                        .blur(radius: seed.size * 0.34)
                        .position(
                            x: geometry.size.width * (seed.x + 0.06 * sin(t * seed.speed + Double(index))),
                            y: geometry.size.height * (seed.y + 0.05 * cos(t * seed.speed * 0.8 + Double(index))))
                }
            }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    private struct Bubble { let x, y, size, speed: Double; let tint: Color }

    private static let bubbleSeeds: [Bubble] = [
        .init(x: 0.22, y: 0.30, size: 460, speed: 0.17, tint: Color(red: 0.36, green: 0.52, blue: 1.0)),
        .init(x: 0.78, y: 0.26, size: 380, speed: 0.21, tint: Color(red: 0.55, green: 0.38, blue: 1.0)),
        .init(x: 0.66, y: 0.74, size: 520, speed: 0.14, tint: Color(red: 0.20, green: 0.44, blue: 0.96)),
        .init(x: 0.30, y: 0.78, size: 340, speed: 0.24, tint: Color(red: 0.42, green: 0.64, blue: 1.0)),
        .init(x: 0.50, y: 0.50, size: 620, speed: 0.11, tint: Color(red: 0.16, green: 0.28, blue: 0.86)),
    ]

    // MARK: - Mark

    private var mark: some View {
        VStack(spacing: 26) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 190, height: 190)
                    .shadow(color: .black.opacity(0.35), radius: 34, y: 14)
                    .scaleEffect(showMark ? 1 : 0.62)
                    .opacity(showMark ? 1 : 0)
                    .blur(radius: showMark ? 0 : 22)
            }

            Text("Aloft")
                .font(.system(size: 78, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .kerning(-1)
                // The backdrop is bright and moving, so the name carries its own
                // legibility rather than trusting any one frame of it.
                .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
                .shadow(color: .black.opacity(0.30), radius: 22, y: 6)
                .opacity(showName ? 1 : 0)
                .offset(y: showName ? 0 : 16)
                .blur(radius: showName ? 0 : 10)
        }
        .animation(.spring(response: 0.85, dampingFraction: 0.68), value: showMark)
        .animation(.spring(response: 0.70, dampingFraction: 0.80), value: showName)
    }

    // MARK: - Sequence

    private func run() async {
        if soundsEnabled { pad.start() }
        try? await Task.sleep(for: .milliseconds(320))
        showMark = true
        Chime.intro.play(if: soundsEnabled)
        try? await Task.sleep(for: .milliseconds(430))
        showName = true
        try? await Task.sleep(for: .milliseconds(1900))
        exit()
    }

    @MainActor private func exit() {
        guard !leaving else { return }      // tap and timer can both land here
        leaving = true
        pad.fadeOut()                       // release matches the visual fade
        Task {
            try? await Task.sleep(for: .milliseconds(560))
            finish()
        }
    }
}
