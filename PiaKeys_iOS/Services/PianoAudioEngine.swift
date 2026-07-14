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

    private final class Voice {
        let player: AVAudioPlayerNode
        let varispeed: AVAudioUnitVarispeed
        var audioBuffer: AVAudioPCMBuffer?
        var generation = 0
        var isBusy = false
        var sequence: UInt64 = 0
        var fullVolume: Float = 1

        init(player: AVAudioPlayerNode, varispeed: AVAudioUnitVarispeed) {
            self.player = player
            self.varispeed = varispeed
        }
    }

    private static let voiceCount = 48
    private static let sampleCacheLimit = 24
    private static let releaseMilliseconds: Int64 = 220
    private static let fadeMilliseconds: Int64 = 180
    private static let renderFormat = AVAudioFormat(
        standardFormatWithSampleRate: 44_100,
        channels: 2
    )!

    private let engine = AVAudioEngine()
    private let audioQueue = DispatchQueue(label: "dunghn2201.PiaKeys.audio")
    private var samples: [Sample] = []
    private var sampleBuffers: [URL: AVAudioPCMBuffer] = [:]
    private var sampleBufferOrder: [URL] = []
    private var voices: [Voice] = []
    private var voiceSequence: UInt64 = 0
    private var voiceStealCount = 0
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
        configureVoicePool()
    }

    func setVolume(_ value: Double) {
        audioQueue.async { [self] in
            volume = Float(value.clamped(to: 0...1))
            engine.mainMixerNode.outputVolume = volume
        }
    }

    func play(noteNumber: Int, velocity: Int, durationMilliseconds: Int64? = nil) {
        audioQueue.async { [self] in
            playNow(
                noteNumber: noteNumber,
                velocity: velocity,
                durationMilliseconds: durationMilliseconds
            )
        }
    }

    func prepareForPlayback(notes: [(noteNumber: Int, velocity: Int)]) async {
        await withCheckedContinuation { continuation in
            audioQueue.async { [self] in
                preloadSamples(for: notes)
                continuation.resume()
            }
        }
    }

    private func playNow(noteNumber: Int, velocity: Int, durationMilliseconds: Int64?) {
        prepareEngine()
        if let sample = closestSample(to: noteNumber, velocity: velocity),
           let buffer = sampleBuffer(for: sample) {
            play(buffer: buffer, sampleNote: sample.noteNumber, noteNumber: noteNumber, velocity: velocity, durationMilliseconds: durationMilliseconds)
        } else {
            Self.logger.error("Falling back to synthesized note \(noteNumber); no readable FLAC sample")
            playSynthesizedNote(noteNumber: noteNumber, velocity: velocity, durationMilliseconds: durationMilliseconds ?? 500)
        }
    }

    func playMetronomeClick(accent: Bool, profile: String) {
        audioQueue.async { [self] in
            prepareEngine()
            let frequency = profile == "Digital" ? (accent ? 1_760.0 : 1_320.0) : (accent ? 1_150.0 : 880.0)
            playTone(frequency: frequency, amplitude: accent ? 0.28 : 0.18, duration: 0.045, harmonics: profile == "Digital" ? 1 : 3)
        }
    }

    func stopAll() {
        audioQueue.async { [self] in
            for voice in voices {
                voice.generation += 1
                voice.player.stop()
                voice.isBusy = false
            }
        }
    }

#if DEBUG
    func runSelfTest() {
        audioQueue.async { [self] in
            let initialStealCount = voiceStealCount
            let chord = [48, 55, 60, 64, 67, 72, 76, 79]
            preloadSamples(for: chord.map { ($0, 96) })
            for chordIndex in 0..<12 {
                audioQueue.asyncAfter(deadline: .now() + Double(chordIndex) * 0.18) { [self] in
                    for note in chord {
                        playNow(
                            noteNumber: note + chordIndex % 3,
                            velocity: 96,
                            durationMilliseconds: 650
                        )
                    }
                }
            }
            audioQueue.asyncAfter(deadline: .now() + 4) { [self] in
                let busyVoiceCount = voices.filter(\.isBusy).count
                let steals = voiceStealCount - initialStealCount
                print(
                    "PIAKEYS_AUDIO_SELF_TEST scheduled=96 busy=\(busyVoiceCount) " +
                    "stolen=\(steals) engineRunning=\(engine.isRunning)"
                )
            }
        }
    }
#endif

    private func prepareEngine() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            Self.logger.error("Unable to start audio engine: \(error.localizedDescription)")
        }
    }

    private func play(
        buffer: AVAudioPCMBuffer,
        sampleNote: Int,
        noteNumber: Int,
        velocity: Int,
        durationMilliseconds: Int64?
    ) {
        let voice = acquireVoice()
        let generation = voice.generation
        voice.audioBuffer = buffer
        voice.varispeed.rate = Float(pow(2, Double(noteNumber - sampleNote) / 12))
        // Keep the same headroom as the Android SFZ renderer.
        voice.fullVolume = Float(velocity.clamped(to: 1...127)) / 127 * 0.72
        voice.player.volume = voice.fullVolume
        voice.player.scheduleBuffer(buffer, at: nil, options: []) { [weak self, weak voice] in
            guard let self, let voice else { return }
            self.audioQueue.async {
                self.releaseVoice(voice, generation: generation)
            }
        }
        voice.player.play()

        // Keep long score notes intact, then damp them gradually like a released piano key.
        let heldMilliseconds = (durationMilliseconds ?? 1_100).clamped(to: 80...7_500)
        scheduleRelease(
            voice,
            generation: generation,
            after: heldMilliseconds + Self.releaseMilliseconds
        )
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
        let format = Self.renderFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else { return }
        buffer.frameLength = frameCount

        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            let progress = Double(frame) / Double(max(1, Int(frameCount) - 1))
            let envelope = exp(-5.5 * progress) * min(1, progress * 80)
            var value = 0.0
            for harmonic in 1...harmonics {
                value += sin(2 * .pi * frequency * Double(harmonic) * time) / Double(harmonic * harmonic)
            }
            let sample = Float(value * amplitude * envelope)
            channels[0][frame] = sample
            channels[1][frame] = sample
        }

        let voice = acquireVoice()
        let generation = voice.generation
        voice.audioBuffer = buffer
        voice.varispeed.rate = 1
        voice.fullVolume = 1
        voice.player.volume = 1
        voice.player.scheduleBuffer(buffer, at: nil, options: []) { [weak self, weak voice] in
            guard let self, let voice else { return }
            self.audioQueue.async {
                self.releaseVoice(voice, generation: generation)
            }
        }
        voice.player.play()
    }

    private func acquireVoice() -> Voice {
        let idleVoice = voices.first(where: { !$0.isBusy })
        if idleVoice == nil { voiceStealCount += 1 }
        let voice = idleVoice ?? voices.min(by: { $0.sequence < $1.sequence })!
        voice.player.stop()
        voice.audioBuffer = nil
        voice.generation += 1
        voiceSequence &+= 1
        voice.sequence = voiceSequence
        voice.isBusy = true
        return voice
    }

    private func releaseVoice(_ voice: Voice, generation: Int) {
        guard voice.generation == generation else { return }
        voice.player.stop()
        voice.player.volume = 0
        voice.audioBuffer = nil
        voice.isBusy = false
    }

    private func scheduleRelease(_ voice: Voice, generation: Int, after milliseconds: Int64) {
        let fadeStart = max(0, milliseconds - Self.fadeMilliseconds)
        let fadeSteps = 6
        for step in 1...fadeSteps {
            let stepDelay = fadeStart + Self.fadeMilliseconds * Int64(step) / Int64(fadeSteps)
            audioQueue.asyncAfter(deadline: .now() + Double(stepDelay) / 1_000) { [weak voice] in
                guard let voice, voice.generation == generation else { return }
                voice.player.volume = voice.fullVolume * Float(fadeSteps - step) / Float(fadeSteps)
            }
        }
        audioQueue.asyncAfter(deadline: .now() + Double(milliseconds) / 1_000) { [weak self, weak voice] in
            guard let self, let voice else { return }
            self.releaseVoice(voice, generation: generation)
        }
    }

    private func configureVoicePool() {
        for _ in 0..<Self.voiceCount {
            let player = AVAudioPlayerNode()
            let varispeed = AVAudioUnitVarispeed()
            engine.attach(player)
            engine.attach(varispeed)
            engine.connect(player, to: varispeed, format: Self.renderFormat)
            engine.connect(varispeed, to: engine.mainMixerNode, format: Self.renderFormat)
            voices.append(Voice(player: player, varispeed: varispeed))
        }
        engine.prepare()
    }

    private func closestSample(to noteNumber: Int, velocity: Int) -> Sample? {
        let preferredHighVelocity = velocity >= 82
        return samples.min { lhs, rhs in
            let lhsScore = abs(lhs.noteNumber - noteNumber) * 4 + (lhs.isHighVelocity == preferredHighVelocity ? 0 : 1)
            let rhsScore = abs(rhs.noteNumber - noteNumber) * 4 + (rhs.isHighVelocity == preferredHighVelocity ? 0 : 1)
            return lhsScore < rhsScore
        }
    }

    private func preloadSamples(for notes: [(noteNumber: Int, velocity: Int)]) {
        var counts: [URL: (sample: Sample, count: Int)] = [:]
        var firstSamples: [Sample] = []
        var seenURLs = Set<URL>()

        for note in notes {
            guard let sample = closestSample(to: note.noteNumber, velocity: note.velocity) else { continue }
            counts[sample.url] = (sample, (counts[sample.url]?.count ?? 0) + 1)
            if seenURLs.insert(sample.url).inserted {
                firstSamples.append(sample)
            }
        }

        let frequentSamples = counts.values
            .sorted { $0.count > $1.count }
            .map(\.sample)
        var selectedSamples: [Sample] = []
        var selectedURLs = Set<URL>()
        for sample in Array(firstSamples.prefix(8)) + frequentSamples {
            if selectedURLs.insert(sample.url).inserted {
                selectedSamples.append(sample)
            }
            if selectedSamples.count == Self.sampleCacheLimit { break }
        }
        for sample in selectedSamples where sampleBuffers[sample.url] == nil {
            _ = sampleBuffer(for: sample)
        }
    }

    private func sampleBuffer(for sample: Sample) -> AVAudioPCMBuffer? {
        if let buffer = sampleBuffers[sample.url] {
            touchSampleBuffer(sample.url)
            return buffer
        }
        guard let file = try? AVAudioFile(forReading: sample.url),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
              ) else { return nil }
        do {
            try file.read(into: buffer)
        } catch {
            Self.logger.error("Unable to decode \(sample.url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
        if sampleBuffers.count >= Self.sampleCacheLimit,
           let oldestURL = sampleBufferOrder.first {
            sampleBuffers.removeValue(forKey: oldestURL)
            sampleBufferOrder.removeFirst()
        }
        sampleBuffers[sample.url] = buffer
        sampleBufferOrder.append(sample.url)
        return buffer
    }

    private func touchSampleBuffer(_ url: URL) {
        sampleBufferOrder.removeAll(where: { $0 == url })
        sampleBufferOrder.append(url)
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
