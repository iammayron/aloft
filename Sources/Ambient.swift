import AVFoundation
import Foundation

/// A soft chord that swells under the intro and fades with it.
///
/// Synthesised rather than shipped as an audio file: it is five sine partials, so
/// generating it costs less than the bytes a recording would add to the bundle, and
/// the fade can follow the animation exactly instead of being baked in.
final class AmbientPad {
    private let engine = AVAudioEngine()
    private let sampleRate: Double
    private let format: AVAudioFormat

    /// A major with the ninth on top — open and unresolved, so it does not sound like
    /// it has finished before the animation has.
    private let voices: [Double] = [110.00, 164.81, 220.00, 277.18, 329.63, 415.30]
    private let weights: [Double] = [0.30, 0.22, 0.20, 0.13, 0.10, 0.05]
    private var phases: [Double]
    private var drift: [Double]

    private var level: Double = 0
    private var target: Double = 0
    private var smoothing: Double = 0
    private var node: AVAudioSourceNode?

    init() {
        sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        phases = Array(repeating: 0, count: voices.count)
        drift = (0..<voices.count).map { Double($0) * 0.9 }
    }

    func start(attack: Double = 1.6, peak: Double = 0.11) {
        guard node == nil else { return }
        smoothing = 1.0 / (sampleRate * attack)
        target = peak

        let source = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList in
            guard let self else { return noErr }
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                self.level += (self.target - self.level) * self.smoothing

                var sample = 0.0
                for index in self.voices.indices {
                    // A slow per-voice wobble keeps it breathing instead of buzzing.
                    self.drift[index] += 0.00000037 * Double(index + 1)
                    let shimmer = 1.0 + 0.004 * sin(self.drift[index])
                    self.phases[index] += 2 * .pi * self.voices[index] * shimmer / self.sampleRate
                    if self.phases[index] > 2 * .pi { self.phases[index] -= 2 * .pi }
                    sample += sin(self.phases[index]) * self.weights[index]
                }

                let value = Float(sample * self.level)
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = value
                }
            }
            return noErr
        }

        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        node = source
        try? engine.start()
    }

    func fadeOut(release: Double = 0.7) {
        guard node != nil else { return }
        smoothing = 1.0 / (sampleRate * release)
        target = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + release + 0.15) { [self] in stop() }
    }

    func stop() {
        guard let node else { return }
        engine.stop()
        engine.detach(node)
        self.node = nil
    }

    deinit { stop() }
}
