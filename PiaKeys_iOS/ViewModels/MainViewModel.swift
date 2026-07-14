import Combine
import Foundation

final class MainViewModel: ObservableObject {
    @Published private(set) var bleDevices: [MIDIDevice] = []
    @Published private(set) var bleStatus: MIDIConnectionStatus = .idle
    @Published private(set) var bleCompatibilityScanActive = false
    @Published private(set) var rawPackets: [RawMIDIPacket] = []
    @Published private(set) var wiredSources: [CoreMIDIPort] = []
    @Published private(set) var wiredDestinations: [CoreMIDIPort] = []
    @Published private(set) var noteEvents: [MIDINoteEvent] = []
    @Published private(set) var heldNoteNumbers: Set<Int> = []

    @Published var appearance: AppAppearance { didSet { saveSettings() } }
    @Published var language: PiaKeysLanguage { didSet { saveSettings() } }
    @Published var audioEnabled: Bool { didSet { if !audioEnabled { audio.stopAll() }; saveSettings() } }
    @Published var audioVolume: Double { didSet { audio.setVolume(audioVolume); saveSettings() } }
    @Published var tempo: Int {
        didSet {
            let next = tempo.clamped(to: 40...220)
            if tempo != next {
                tempo = next
                return
            }
            saveSettings()
            restartMetronomeIfNeeded()
        }
    }
    @Published var timeSignature: String { didSet { saveSettings(); restartMetronomeIfNeeded() } }
    @Published var firstBeatAccent: Bool { didSet { saveSettings(); restartMetronomeIfNeeded() } }
    @Published var visualPulse: Bool { didSet { saveSettings() } }
    @Published var soundProfile: String { didSet { saveSettings(); restartMetronomeIfNeeded() } }
    @Published var showFullKeyboard: Bool { didSet { saveSettings() } }
    @Published var metronomeRunning = false { didSet { updateMetronome() } }
    @Published private(set) var metronomeBeat = 0

    @Published private(set) var songs: [PracticeSong] = [.demo]
    @Published var selectedSongID = PracticeSong.demo.id
    @Published private(set) var songPlaying = false
    @Published private(set) var songPositionMilliseconds: Int64 = 0
    @Published private(set) var activeSongNotes: Set<Int> = []
    @Published private(set) var latestSongNoteNumber: Int?
    @Published var songOutputRoute: SongOutputRoute = .appOnly
    @Published var importMessage: String?

    let ble = BLEMIDIManager()
    let coreMIDI = CoreMIDIManager()
    private let audio = PianoAudioEngine()
    private let defaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    private var metronomeTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?
    private var noteOffTasks: [UUID: Task<Void, Never>] = [:]
    private var activeSongNoteCounts: [Int: Int] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = AppAppearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        language = PiaKeysLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .english
        audioEnabled = defaults.object(forKey: Keys.audioEnabled) as? Bool ?? true
        audioVolume = defaults.object(forKey: Keys.audioVolume) as? Double ?? 1
        tempo = defaults.object(forKey: Keys.tempo) as? Int ?? 84
        timeSignature = defaults.string(forKey: Keys.timeSignature) ?? "4/4"
        firstBeatAccent = defaults.object(forKey: Keys.firstBeatAccent) as? Bool ?? true
        visualPulse = defaults.object(forKey: Keys.visualPulse) as? Bool ?? true
        soundProfile = defaults.string(forKey: Keys.soundProfile) ?? "Woodblock"
        showFullKeyboard = defaults.object(forKey: Keys.showFullKeyboard) as? Bool ?? true

        audio.setVolume(audioVolume)
        bindManagers()
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--audio-self-test") {
            audio.runSelfTest()
        }
#endif
    }

    deinit {
        metronomeTask?.cancel()
        playbackTask?.cancel()
        noteOffTasks.values.forEach { $0.cancel() }
    }

    var selectedSong: PracticeSong? {
        songs.first { $0.id == selectedSongID } ?? songs.first
    }

    var selectedSongProgress: Double {
        guard let duration = selectedSong?.durationMilliseconds, duration > 0 else { return 0 }
        return Double(songPositionMilliseconds) / Double(duration)
    }

    var activeNoteEvent: MIDINoteEvent? {
        noteEvents.first(where: { $0.type == .noteOn && heldNoteNumbers.contains($0.noteNumber) })
            ?? noteEvents.first(where: { $0.type == .noteOn })
    }

    var inputSourceLabel: String {
        activeNoteEvent?.source.rawValue ?? (wiredSources.isEmpty ? "--" : "MIDI")
    }

    var overallConnectionLabel: String {
        if !wiredSources.isEmpty { return "MIDI Live" }
        return bleStatus.label
    }

    var canSendWiredMIDI: Bool { coreMIDI.canSendNotes }
    var canSendBLEMIDI: Bool { ble.canSendNotes }
    var pianoSampleCount: Int { audio.sampleCount }
    var pianoSampleStatus: String { audio.sampleLibraryStatus }

    func startBLEScan() { ble.startScan() }
    func stopBLEScan() { ble.stopScan() }
    func connectBLE(_ id: UUID) { ble.connect(to: id) }
    func disconnectBLE() { ble.disconnect() }
    func refreshWiredMIDI() { coreMIDI.refresh() }

    func previewNote(_ noteNumber: Int, heldFor milliseconds: Int64 = 380) {
        let velocity = milliseconds < 180 ? 84 : milliseconds < 700 ? 104 : 120
        consume(events: [MIDINoteEvent(
            noteNumber: noteNumber,
            velocity: velocity,
            type: .noteOn,
            source: .preview
        )], durationMilliseconds: milliseconds)

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(milliseconds.clamped(to: 140...2_400)))
            guard !Task.isCancelled else { return }
            self?.consume(events: [MIDINoteEvent(
                noteNumber: noteNumber,
                velocity: 0,
                type: .noteOff,
                source: .preview
            )])
        }
    }

    func injectTestC4() { previewNote(60, heldFor: 360) }

    func selectSong(_ id: String) {
        stopSong(clearPosition: true)
        selectedSongID = id
    }

    func toggleSongPlayback() {
        songPlaying ? stopSong(clearPosition: false) : startSong()
    }

    func resetSong() { stopSong(clearPosition: true) }

    func importSong(from url: URL) {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }

        do {
            let fileExtension = url.pathExtension.lowercased()
            guard fileExtension == "mid" || fileExtension == "midi" else {
                importMessage = "Choose a Standard MIDI file (.mid or .midi)."
                return
            }
            let data = try Data(contentsOf: url)
            let song = try StandardMIDIFileParser.parse(
                data: data,
                fallbackTitle: url.deletingPathExtension().lastPathComponent
            )
            if let existing = songs.first(where: { $0.id == song.id }) {
                selectedSongID = existing.id
                importMessage = "\(existing.title) is already in the library."
            } else {
                songs.append(song)
                selectedSongID = song.id
                importMessage = "Imported \(song.title)."
            }
        } catch {
            importMessage = error.localizedDescription
        }
    }

    func importScore(from url: URL) {
        guard let index = songs.firstIndex(where: { $0.id == selectedSongID }) else { return }
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("Scores", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent("\(selectedSongID).\(url.pathExtension)")
            try data.write(to: destination, options: .atomic)
            songs[index].scoreURL = destination
            importMessage = "MusicXML score attached to \(songs[index].title)."
        } catch {
            importMessage = "Could not import the score: \(error.localizedDescription)"
        }
    }

    func clearImportMessage() { importMessage = nil }

    func showImportError(_ message: String) { importMessage = message }

    private func bindManagers() {
        ble.$devices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.bleDevices = $0 }
            .store(in: &cancellables)
        ble.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.bleStatus = $0 }
            .store(in: &cancellables)
        ble.$compatibilityScanActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.bleCompatibilityScanActive = $0 }
            .store(in: &cancellables)
        ble.$rawPackets
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.rawPackets = $0 }
            .store(in: &cancellables)
        coreMIDI.$sources
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.wiredSources = $0 }
            .store(in: &cancellables)
        coreMIDI.$destinations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.wiredDestinations = $0 }
            .store(in: &cancellables)

        ble.onEvents = { [weak self] events in self?.consume(events: events) }
        coreMIDI.onEvents = { [weak self] events in self?.consume(events: events) }
    }

    private func consume(events: [MIDINoteEvent], durationMilliseconds: Int64? = nil) {
        for event in events {
            noteEvents.insert(event, at: 0)
            switch event.type {
            case .noteOn:
                heldNoteNumbers.insert(event.noteNumber)
                if audioEnabled {
                    audio.play(
                        noteNumber: event.noteNumber,
                        velocity: event.velocity,
                        durationMilliseconds: durationMilliseconds
                    )
                }
            case .noteOff:
                heldNoteNumbers.remove(event.noteNumber)
            }
        }
        noteEvents = Array(noteEvents.prefix(40))
    }

    private func startSong() {
        guard let song = selectedSong else { return }
        stopSong(clearPosition: false)
        songPlaying = true
        let startingPosition = songPositionMilliseconds.clamped(to: 0...song.durationMilliseconds)

        playbackTask = Task { [weak self] in
            guard let self else { return }
            await audio.prepareForPlayback(
                notes: song.notes.map { ($0.noteNumber, $0.velocity) }
            )
            guard !Task.isCancelled else { return }
            let clock = ContinuousClock()
            let startedAt = clock.now - .milliseconds(startingPosition)
            var index = song.notes.firstIndex {
                $0.startMilliseconds + $0.durationMilliseconds >= startingPosition
            } ?? song.notes.count

            while !Task.isCancelled {
                let elapsed = startedAt.duration(to: clock.now)
                let milliseconds = Int64(elapsed.components.seconds * 1_000) +
                    Int64(elapsed.components.attoseconds / 1_000_000_000_000_000)
                songPositionMilliseconds = milliseconds.clamped(to: 0...song.durationMilliseconds)

                while index < song.notes.count, song.notes[index].startMilliseconds <= milliseconds {
                    playSongNote(song.notes[index])
                    index += 1
                }
                if milliseconds >= song.durationMilliseconds {
                    finishSong()
                    return
                }
                try? await Task.sleep(for: .milliseconds(12))
            }
        }
    }

    private func playSongNote(_ note: SongNote) {
        activeSongNoteCounts[note.noteNumber, default: 0] += 1
        activeSongNotes.insert(note.noteNumber)
        latestSongNoteNumber = note.noteNumber
        if audioEnabled {
            audio.play(
                noteNumber: note.noteNumber,
                velocity: note.velocity,
                durationMilliseconds: note.durationMilliseconds
            )
        }
        sendSongNoteOn(note)

        let taskID = UUID()
        noteOffTasks[taskID] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(max(140, note.durationMilliseconds)))
            guard let self, !Task.isCancelled else { return }
            let remaining = max(0, (self.activeSongNoteCounts[note.noteNumber] ?? 1) - 1)
            if remaining == 0 {
                self.activeSongNoteCounts.removeValue(forKey: note.noteNumber)
                self.activeSongNotes.remove(note.noteNumber)
                self.sendSongNoteOff(note.noteNumber)
            } else {
                self.activeSongNoteCounts[note.noteNumber] = remaining
            }
            self.noteOffTasks.removeValue(forKey: taskID)
        }
    }

    private func sendSongNoteOn(_ note: SongNote) {
        switch songOutputRoute {
        case .appOnly: break
        case .wired where canSendWiredMIDI:
            coreMIDI.sendNoteOn(note.noteNumber, velocity: note.velocity)
        case .ble where canSendBLEMIDI:
            ble.sendNoteOn(note.noteNumber, velocity: note.velocity)
        default:
            songOutputRoute = .appOnly
        }
    }

    private func sendSongNoteOff(_ noteNumber: Int) {
        switch songOutputRoute {
        case .appOnly: break
        case .wired where canSendWiredMIDI: coreMIDI.sendNoteOff(noteNumber)
        case .ble where canSendBLEMIDI: ble.sendNoteOff(noteNumber)
        default: break
        }
    }

    private func stopSong(clearPosition: Bool) {
        playbackTask?.cancel()
        playbackTask = nil
        noteOffTasks.values.forEach { $0.cancel() }
        noteOffTasks.removeAll()
        for note in activeSongNotes { sendSongNoteOff(note) }
        activeSongNoteCounts.removeAll()
        activeSongNotes = []
        songPlaying = false
        if clearPosition {
            songPositionMilliseconds = 0
            latestSongNoteNumber = nil
        }
        audio.stopAll()
    }

    private func finishSong() {
        stopSong(clearPosition: true)
    }

    private func updateMetronome() {
        metronomeTask?.cancel()
        metronomeTask = nil
        metronomeBeat = 0
        guard metronomeRunning else { return }
        metronomeTask = Task { [weak self] in
            guard let self else { return }
            let beatCount = Int(timeSignature.split(separator: "/").first ?? "4") ?? 4
            var beat = 0
            while !Task.isCancelled {
                metronomeBeat = beat
                audio.playMetronomeClick(
                    accent: firstBeatAccent && beat == 0,
                    profile: soundProfile
                )
                let interval = Int64(60_000 / max(1, tempo)).clamped(to: 260...1_500)
                try? await Task.sleep(for: .milliseconds(interval))
                beat = (beat + 1) % max(1, beatCount)
            }
        }
    }

    private func restartMetronomeIfNeeded() {
        if metronomeRunning { updateMetronome() }
    }

    private func saveSettings() {
        defaults.set(appearance.rawValue, forKey: Keys.appearance)
        defaults.set(language.rawValue, forKey: Keys.language)
        defaults.set(audioEnabled, forKey: Keys.audioEnabled)
        defaults.set(audioVolume, forKey: Keys.audioVolume)
        defaults.set(tempo, forKey: Keys.tempo)
        defaults.set(timeSignature, forKey: Keys.timeSignature)
        defaults.set(firstBeatAccent, forKey: Keys.firstBeatAccent)
        defaults.set(visualPulse, forKey: Keys.visualPulse)
        defaults.set(soundProfile, forKey: Keys.soundProfile)
        defaults.set(showFullKeyboard, forKey: Keys.showFullKeyboard)
    }

    private enum Keys {
        static let appearance = "appearance"
        static let language = "language"
        static let audioEnabled = "audio_enabled"
        static let audioVolume = "audio_volume"
        static let tempo = "tempo"
        static let timeSignature = "time_signature"
        static let firstBeatAccent = "first_beat_accent"
        static let visualPulse = "visual_pulse"
        static let soundProfile = "sound_profile"
        static let showFullKeyboard = "show_full_keyboard"
    }
}
