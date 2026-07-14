import AVFoundation
import Foundation
import OSLog

final class PianoAudioEngine {
    private static let logger = Logger(subsystem: "dunghn2201.PiaKeys-iOS", category: "PianoAudio")

    private struct Sample {
        let noteNumber: Int
        let isHighVelocity: Bool
        let url: URL
    }

    private struct Voice {
        let player: AVAudioPlayerNode
        let varispeed: AVAudioUnitVarispeed?
    }

    private let engine = AVAudioEngine()
    private var samples: [Sample] = []
    private var voices: [UUID: Voice] = [:]
    private(set) var volume: Float = 1

    var sampleCount: Int { samples.count }

    var sampleLibraryStatus: String {
        samples.isEmpty
            ? "Piano samples unavailable — check app resources"
            : "Upright Piano KW · \(samples.count) FLAC samples ready"
    }

    init() {
        samples = loadSamples()
        if samples.isEmpty {
            Self.logger.error("No bundled FLAC piano samples were found")
        } else {
            Self.logger.info("Loaded \(self.samples.count) bundled FLAC piano sample mappings")
        }
        configureSession()
    }

    func setVolume(_ value: Double) {
        volume = Float(value.clamped(to: 0...1))
        engine.mainMixerNode.outputVolume = volume
    }

    func play(noteNumber: Int, velocity: Int, durationMilliseconds: Int64? = nil) {
        prepareEngine()
        if let sample = closestSample(to: noteNumber, velocity: velocity),
           let file = try? AVAudioFile(forReading: sample.url) {
            play(file: file, sampleNote: sample.noteNumber, noteNumber: noteNumber, velocity: velocity, durationMilliseconds: durationMilliseconds)
        } else {
            Self.logger.error("Falling back to synthesized note \(noteNumber); no readable FLAC sample")
            playSynthesizedNote(noteNumber: noteNumber, velocity: velocity, durationMilliseconds: durationMilliseconds ?? 500)
        }
    }

    func playMetronomeClick(accent: Bool, profile: String) {
        prepareEngine()
        let frequency = profile == "Digital" ? (accent ? 1_760.0 : 1_320.0) : (accent ? 1_150.0 : 880.0)
        playTone(frequency: frequency, amplitude: accent ? 0.28 : 0.18, duration: 0.045, harmonics: profile == "Digital" ? 1 : 3)
    }

    func stopAll() {
        for voice in voices.values { voice.player.stop() }
        for id in Array(voices.keys) { removeVoice(id) }
    }

    private func prepareEngine() {
        guard !engine.isRunning else { return }
        try? engine.start()
    }

    private func play(
        file: AVAudioFile,
        sampleNote: Int,
        noteNumber: Int,
        velocity: Int,
        durationMilliseconds: Int64?
    ) {
        let id = UUID()
        let player = AVAudioPlayerNode()
        let varispeed = AVAudioUnitVarispeed()
        varispeed.rate = Float(pow(2, Double(noteNumber - sampleNote) / 12))
        // Keep the same headroom as the Android SFZ renderer.
        player.volume = Float(velocity.clamped(to: 1...127)) / 127 * 0.72
        engine.attach(player)
        engine.attach(varispeed)
        engine.connect(player, to: varispeed, format: file.processingFormat)
        engine.connect(varispeed, to: engine.mainMixerNode, format: nil)
        voices[id] = Voice(player: player, varispeed: varispeed)
        player.scheduleFile(file, at: nil) { [weak self] in
            DispatchQueue.main.async { self?.removeVoice(id) }
        }
        player.play()

        // Android uses 1.1 s for live MIDI plus a 140 ms release tail. This
        // avoids playing each eight-second source sample in full.
        let playbackMilliseconds = (durationMilliseconds ?? 1_100).clamped(to: 80...4_000) + 140
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(playbackMilliseconds) / 1_000) { [weak self] in
            self?.removeVoice(id)
        }
    }

    private func playSynthesizedNote(noteNumber: Int, velocity: Int, durationMilliseconds: Int64) {
        let frequency = 440 * pow(2, Double(noteNumber - 69) / 12)
        playTone(
            frequency: frequency,
            amplitude: Double(velocity.clamped(to: 1...127)) / 127 * 0.22,
            duration: Double(durationMilliseconds.clamped(to: 100...2_400)) / 1_000,
            harmonics: 4
        )
    }

    private func playTone(frequency: Double, amplitude: Double, duration: Double, harmonics: Int) {
        let sampleRate = 44_100.0
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let samples = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = frameCount

        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            let progress = Double(frame) / Double(max(1, Int(frameCount) - 1))
            let envelope = exp(-5.5 * progress) * min(1, progress * 80)
            var value = 0.0
            for harmonic in 1...harmonics {
                value += sin(2 * .pi * frequency * Double(harmonic) * time) / Double(harmonic * harmonic)
            }
            samples[frame] = Float(value * amplitude * envelope)
        }

        let id = UUID()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        voices[id] = Voice(player: player, varispeed: nil)
        player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            DispatchQueue.main.async { self?.removeVoice(id) }
        }
        player.play()
    }

    private func removeVoice(_ id: UUID) {
        guard let voice = voices.removeValue(forKey: id) else { return }
        voice.player.stop()
        engine.disconnectNodeOutput(voice.player)
        engine.detach(voice.player)
        if let varispeed = voice.varispeed {
            engine.disconnectNodeOutput(varispeed)
            engine.detach(varispeed)
        }
    }

    private func closestSample(to noteNumber: Int, velocity: Int) -> Sample? {
        let preferredHighVelocity = velocity >= 82
        return samples.min { lhs, rhs in
            let lhsScore = abs(lhs.noteNumber - noteNumber) * 4 + (lhs.isHighVelocity == preferredHighVelocity ? 0 : 1)
            let rhsScore = abs(rhs.noteNumber - noteNumber) * 4 + (rhs.isHighVelocity == preferredHighVelocity ? 0 : 1)
            return lhsScore < rhsScore
        }
    }

    private func loadSamples() -> [Sample] {
        // Xcode's synchronized resource groups can either preserve this folder or
        // flatten its files into the bundle root, depending on the project version.
        // An empty subdirectory result is non-nil, so `??` previously skipped
        // every flattened sample and sent all piano notes to the synth fallback.
        let nestedURLs = Bundle.main.urls(forResourcesWithExtension: "flac", subdirectory: "PianoSamples") ?? []
        let rootURLs = Bundle.main.urls(forResourcesWithExtension: "flac", subdirectory: nil) ?? []
        let urls = Dictionary(
            (nestedURLs + rootURLs).map { ($0.standardizedFileURL, $0) },
            uniquingKeysWith: { first, _ in first }
        ).values
        return urls.compactMap { url in
            let name = url.deletingPathExtension().lastPathComponent
            guard let markerIndex = name.lastIndex(of: "v") else { return nil }
            let noteText = String(name[..<markerIndex])
            let velocityText = String(name[name.index(after: markerIndex)...])
            guard let noteNumber = Self.noteNumber(from: noteText) else { return nil }
            return Sample(noteNumber: noteNumber, isHighVelocity: velocityText == "H", url: url)
        }
    }

    private static func noteNumber(from value: String) -> Int? {
        let names = ["C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11]
        guard let octaveCharacter = value.last,
              let octave = Int(String(octaveCharacter)) else { return nil }
        let pitch = String(value.dropLast())
        guard let pitchClass = names[pitch] else { return nil }
        return (octave + 1) * 12 + pitchClass
    }

    private func configureSession() {
#if os(iOS) || os(visionOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
#endif
    }
}
