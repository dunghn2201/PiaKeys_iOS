import AVFoundation
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
    @Published var songOutputRoute: SongOutputRoute = .appOnly {
        willSet {
            if newValue != songOutputRoute {
                stopSong(clearPosition: false)
                stopPreviewOutputs()
            }
        }
    }
    @Published var importMessage: String?

    let ble = BLEMIDIManager()
    let coreMIDI = CoreMIDIManager()
    private let audio = PianoAudioEngine()
    private let libraryStore: SongLibraryStore
    private let defaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    private var metronomeTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?
    private var noteOffTasks: [UUID: Task<Void, Never>] = [:]
    private var activeSongNoteCounts: [Int: Int] = [:]
    private struct InputNote: Hashable {
        let source: MIDIInputSource
        let sourceID: String?
        let channel: Int
        let note: Int
    }
    private var liveVoices: [InputNote: UUID] = [:]
    private var previewTasks: [Int: Task<Void, Never>] = [:]

    init(defaults: UserDefaults = .standard, libraryStore: SongLibraryStore = .init()) {
        self.defaults = defaults
        self.libraryStore = libraryStore
        appearance = AppAppearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        language = PiaKeysLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .english
        audioEnabled = defaults.object(forKey: Keys.audioEnabled) as? Bool ?? true
        audioVolume = defaults.object(forKey: Keys.audioVolume) as? Double ?? 1
        tempo = (defaults.object(forKey: Keys.tempo) as? Int ?? 84).clamped(to: 40...220)
        timeSignature = defaults.string(forKey: Keys.timeSignature) ?? "4/4"
        firstBeatAccent = defaults.object(forKey: Keys.firstBeatAccent) as? Bool ?? true
        visualPulse = defaults.object(forKey: Keys.visualPulse) as? Bool ?? true
        soundProfile = defaults.string(forKey: Keys.soundProfile) ?? "Woodblock"
        showFullKeyboard = defaults.object(forKey: Keys.showFullKeyboard) as? Bool ?? true

        do {
            songs = try libraryStore.load()
            selectedSongID = songs.first?.id ?? PracticeSong.demo.id
        } catch {
            importMessage = "Could not restore the song library: \(error.localizedDescription)"
        }
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
        previewTasks.values.forEach { $0.cancel() }
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
            ?? currentSongNoteEvent
            ?? noteEvents.first(where: { $0.type == .noteOn })
    }

    private var currentSongNoteEvent: MIDINoteEvent? {
        guard !activeSongNotes.isEmpty else { return nil }
        let preferredNumber = latestSongNoteNumber.flatMap { activeSongNotes.contains($0) ? $0 : nil }
            ?? activeSongNotes.sorted().last
        guard let preferredNumber else { return nil }
        return noteEvents.first {
            $0.type == .noteOn && $0.source == .song && $0.noteNumber == preferredNumber
        }
    }

    var inputSourceLabel: String {
        activeNoteEvent?.source.rawValue ?? (wiredSources.isEmpty ? "--" : "MIDI")
    }

    var overallConnectionLabel: String {
        if bleStatus.isConnected || hasExternalWiredMIDI { return "MIDI Live" }
        return bleStatus.label
    }

    var canSendWiredMIDI: Bool { coreMIDI.canSendNotes }
    var canSendBLEMIDI: Bool { bluetoothDestinationName != nil || ble.canSendDirectNotes }
    var hasExternalMIDIConnection: Bool { bleStatus.isConnected || hasExternalWiredMIDI }
    var pianoSampleCount: Int { audio.sampleCount }
    var pianoSampleStatus: String { audio.sampleLibraryStatus }

    private var hasExternalWiredMIDI: Bool {
        (wiredSources + wiredDestinations).contains { !Self.isNetworkSession($0.name) }
    }

    private static func isNetworkSession(_ name: String) -> Bool {
        name.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
            .hasPrefix("networksession")
    }

    func startBLEScan() {
        if songOutputRoute == .ble { stopSong(clearPosition: false) }
        ble.startScan()
    }
    func stopBLEScan() { ble.stopScan() }
    func connectBLE(_ id: UUID) {
        if songOutputRoute == .ble { stopSong(clearPosition: false) }
        ble.connect(to: id)
    }
    func disconnectBLE() {
        if songOutputRoute == .ble { stopSong(clearPosition: false) }
        ble.disconnect()
    }
    func refreshWiredMIDI() { refreshMIDIOutputsAfterBLEActivation() }

    func previewNote(_ noteNumber: Int, heldFor milliseconds: Int64 = 380) {
        beginPreviewNote(noteNumber)
        previewTasks[noteNumber] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(milliseconds.clamped(to: 80...2_400)))
            guard !Task.isCancelled else { return }
            self?.endPreviewNote(noteNumber)
        }
    }

    func beginPreviewNote(_ noteNumber: Int) {
        previewTasks.removeValue(forKey: noteNumber)?.cancel()
        consume(events: [.init(noteNumber: noteNumber, velocity: 104, type: .noteOn, source: .preview)])
    }

    func endPreviewNote(_ noteNumber: Int) {
        previewTasks.removeValue(forKey: noteNumber)?.cancel()
        consume(events: [.init(noteNumber: noteNumber, velocity: 0, type: .noteOff, source: .preview)])
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

    /// Pause on backgrounding/interruption; never silently resume playback after a call.
    func suspendPlayback() {
        stopSong(clearPosition: false)
        metronomeRunning = false
        previewTasks.values.forEach { $0.cancel() }
        previewTasks.removeAll()
        liveVoices.removeAll()
        heldNoteNumbers = []
        audio.stopAll()
    }

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
                selectSong(existing.id)
                importMessage = "\(existing.title) is already in the library."
            } else {
                let updatedSongs = songs + [song]
                try libraryStore.save(updatedSongs)
                songs = updatedSongs
                selectSong(song.id)
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
            let directory = libraryStore.directory.appendingPathComponent("Scores", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // A new URL invalidates the WKWebView cache even when replacing a score
            // with another file of the same extension. Commit the manifest last.
            let destination = directory.appendingPathComponent("\(selectedSongID)-\(UUID().uuidString).\(url.pathExtension)")
            try data.write(to: destination, options: .atomic)
            var updatedSongs = songs
            updatedSongs[index].scoreURL = destination
            do {
                try libraryStore.save(updatedSongs)
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
            let oldURL = songs[index].scoreURL
            songs = updatedSongs
            if let oldURL, oldURL.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL {
                try? FileManager.default.removeItem(at: oldURL)
            }
            importMessage = "MusicXML score attached to \(songs[index].title)."
        } catch {
            importMessage = "Could not import the score: \(error.localizedDescription)"
        }
    }

    func clearImportMessage() { importMessage = nil }

    func showImportError(_ message: String) { importMessage = message }

    private func bindManagers() {
#if os(iOS)
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt == AVAudioSession.InterruptionType.began.rawValue {
                    self?.suspendPlayback()
                }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                    self?.suspendPlayback()
                }
            }
            .store(in: &cancellables)
#endif
        ble.$devices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.bleDevices = $0 }
            .store(in: &cancellables)
        ble.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                if self.bleStatus.isConnected && !status.isConnected {
                    self.clearInput(source: .ble)
                    if self.songOutputRoute == .ble { self.stopSong(clearPosition: false) }
                }
                self.bleStatus = status
                if status.isConnected {
                    // The BLE link is handed to Core MIDI after discovery. Its
                    // source/destination can appear just after activation.
                    self.refreshMIDIOutputsAfterBLEActivation()
                }
            }
            .store(in: &cancellables)
        ble.$compatibilityScanActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.bleCompatibilityScanActive = $0 }
            .store(in: &cancellables)
        coreMIDI.$sources
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sources in
                guard let self else { return }
                for removed in self.wiredSources where !sources.contains(where: { $0.id == removed.id }) {
                    self.clearInput(source: .wired, sourceID: String(removed.id))
                }
                self.wiredSources = sources
            }
            .store(in: &cancellables)
        coreMIDI.$destinations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.wiredDestinations = $0 }
            .store(in: &cancellables)

        coreMIDI.onRawPacket = { [weak self] packet in
            guard let self else { return }
            self.rawPackets.insert(packet, at: 0)
            self.rawPackets = Array(self.rawPackets.prefix(40))
        }
        coreMIDI.onEvents = { [weak self] events in self?.consume(events: events) }
    }

    private func consume(events: [MIDINoteEvent]) {
        for event in events {
            noteEvents.insert(event, at: 0)
            let key = InputNote(source: event.source, sourceID: event.sourceID, channel: event.channel, note: event.noteNumber)
            switch event.type {
            case .noteOn:
                if let previous = liveVoices.removeValue(forKey: key) { audio.releaseNote(previous) }
                liveVoices[key] = event.id
                if event.source == .preview {
                    sendPreviewNoteOn(event)
                } else if audioEnabled {
                    // Live MIDI input is monitored independently from the
                    // output route; the Audio feedback preference controls it.
                    audio.play(noteNumber: event.noteNumber, velocity: event.velocity, voiceID: event.id)
                }
            case .noteOff:
                if let voice = liveVoices.removeValue(forKey: key) { audio.releaseNote(voice) }
                if event.source == .preview { sendPreviewNoteOff(event.noteNumber) }
            }
        }
        heldNoteNumbers = Set(liveVoices.keys.map(\.note))
        noteEvents = Array(noteEvents.prefix(40))
    }

    private func sendPreviewNoteOn(_ event: MIDINoteEvent) {
        switch songOutputRoute {
        case .appOnly:
            guard audioEnabled else { return }
            audio.play(noteNumber: event.noteNumber, velocity: event.velocity, voiceID: event.id)
        case .wired where canSendWiredMIDI:
            coreMIDI.sendNoteOn(event.noteNumber, velocity: event.velocity)
        case .ble where canSendBLEMIDI:
            sendBLEMIDINoteOn(event.noteNumber, velocity: event.velocity)
        default:
            break
        }
    }

    private func sendPreviewNoteOff(_ noteNumber: Int) {
        switch songOutputRoute {
        case .appOnly: break
        case .wired where canSendWiredMIDI: coreMIDI.sendNoteOff(noteNumber)
        case .ble where canSendBLEMIDI: sendBLEMIDINoteOff(noteNumber)
        default: break
        }
    }

    private var bluetoothDestinationName: String? {
        let candidateNames = ["BLE MIDI", "Bluetooth MIDI"] +
            ([ble.connectedDeviceName] + bleDevices.map(\.name)).compactMap { $0 }
        return coreMIDI.destinationName(matching: candidateNames)
    }

    private func sendBLEMIDINoteOn(_ noteNumber: Int, velocity: Int) {
        if let destinationName = bluetoothDestinationName {
            coreMIDI.sendNoteOn(noteNumber, velocity: velocity, destinationName: destinationName)
        } else if ble.canSendDirectNotes {
            ble.sendNoteOn(noteNumber, velocity: velocity)
        }
    }

    private func sendBLEMIDINoteOff(_ noteNumber: Int) {
        if bluetoothDestinationName != nil {
            coreMIDI.sendNoteOff(noteNumber)
        } else if ble.canSendDirectNotes {
            ble.sendNoteOff(noteNumber)
        }
    }

    private func refreshMIDIOutputsAfterBLEActivation() {
        coreMIDI.refresh()
        // Core MIDI registers a Bluetooth endpoint asynchronously after the
        // CoreBluetooth handoff or after the system picker is dismissed.
        for delay in [0.15, 0.5, 1.25] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.coreMIDI.refresh()
            }
        }
    }

    private func stopPreviewOutputs() {
        let previewKeys = liveVoices.keys.filter { $0.source == .preview }
        for key in previewKeys {
            if let voice = liveVoices.removeValue(forKey: key) { audio.releaseNote(voice) }
            sendPreviewNoteOff(key.note)
        }
        previewTasks.values.forEach { $0.cancel() }
        previewTasks.removeAll()
        heldNoteNumbers = Set(liveVoices.keys.map(\.note))
    }

    private func clearInput(source: MIDIInputSource, sourceID: String? = nil) {
        let keys = liveVoices.keys.filter { $0.source == source && (sourceID == nil || $0.sourceID == sourceID) }
        for key in keys {
            if let voice = liveVoices.removeValue(forKey: key) { audio.releaseNote(voice) }
        }
        heldNoteNumbers = Set(liveVoices.keys.map(\.note))
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
                    let note = song.notes[index]
                    let remaining = note.remainingDuration(at: milliseconds)
                    if remaining > 0 { playSongNote(note, durationMilliseconds: remaining) }
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

    private func playSongNote(_ note: SongNote, durationMilliseconds: Int64) {
        activeSongNoteCounts[note.noteNumber, default: 0] += 1
        activeSongNotes.insert(note.noteNumber)
        latestSongNoteNumber = note.noteNumber
        let event = MIDINoteEvent(
            id: note.id,
            noteNumber: note.noteNumber,
            velocity: note.velocity,
            type: .noteOn,
            source: .song
        )
        noteEvents.insert(event, at: 0)
        noteEvents = Array(noteEvents.prefix(40))
        if audioEnabled && songOutputRoute == .appOnly {
            audio.play(
                noteNumber: note.noteNumber,
                velocity: note.velocity,
                durationMilliseconds: durationMilliseconds,
                voiceID: note.id
            )
        }
        // External MIDI uses one gate per pitch while overlapping score voices
        // are active; its note-off is paired with this first note-on.
        if activeSongNoteCounts[note.noteNumber] == 1 { sendSongNoteOn(note) }

        let taskID = UUID()
        noteOffTasks[taskID] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(durationMilliseconds))
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
            sendBLEMIDINoteOn(note.noteNumber, velocity: note.velocity)
        default:
            break
        }
    }

    private func sendSongNoteOff(_ noteNumber: Int) {
        switch songOutputRoute {
        case .appOnly: break
        case .wired where canSendWiredMIDI: coreMIDI.sendNoteOff(noteNumber)
        case .ble where canSendBLEMIDI: sendBLEMIDINoteOff(noteNumber)
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
        audio.stopNotes(Set(selectedSong?.notes.map(\.id) ?? []))
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
            let clock = ContinuousClock()
            var deadline = clock.now
            while !Task.isCancelled {
                metronomeBeat = beat
                audio.playMetronomeClick(
                    accent: firstBeatAccent && beat == 0,
                    profile: soundProfile
                )
                let interval = Int64(60_000 / max(1, tempo)).clamped(to: 260...1_500)
                deadline += .milliseconds(interval)
                try? await clock.sleep(until: deadline)
                if deadline < clock.now - .milliseconds(interval) { deadline = clock.now }
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
