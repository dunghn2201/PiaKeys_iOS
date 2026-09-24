import AVFoundation
import Combine
import Foundation

/// High-frequency playhead updates are observed only by the slider and score.
/// Keeping them out of MainViewModel prevents every tick invalidating both tabs.
final class PlaybackPosition: ObservableObject {
    @Published var milliseconds: Int64 = 0
}

final class MainViewModel: ObservableObject {
    private static let playbackUIUpdateIntervalMilliseconds: Int64 = 33
    private static let songVisualStateUpdateIntervalNanoseconds: UInt64 = 100_000_000
    private static let songNoteEventUpdateIntervalNanoseconds: UInt64 = 250_000_000

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
    @Published var audioEnabled: Bool {
        didSet {
            if !audioEnabled { audio.stopAll() }
            saveSettings()
            if oldValue != audioEnabled { restartPlaybackIfNeeded() }
        }
    }
    @Published var audioVolume: Double { didSet { audio.setVolume(audioVolume); saveSettings() } }
    @Published private var tempoValue = 84
    var tempo: Int {
        get { tempoValue }
        set {
            let next = newValue.clamped(to: 40...220)
            guard tempoValue != next else { return }
            tempoValue = next
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
    @Published private(set) var metronomeBeatIndex = 0
    @Published private(set) var metronomeBeatStartedAt = Date()

    @Published private(set) var songs: [PracticeSong] = [.demo]
    @Published var selectedSongID = PracticeSong.demo.id
    @Published var songVisualizationMode: SongVisualizationMode {
        didSet { saveSettings() }
    }
    @Published private(set) var songPlaying = false
    let playbackPosition = PlaybackPosition()
    private(set) var songPositionMilliseconds: Int64 {
        get { playbackPosition.milliseconds }
        set { playbackPosition.milliseconds = newValue }
    }
    @Published private(set) var activeSongNotes: Set<Int> = []
    @Published private(set) var latestSongNoteNumber: Int?
    @Published private var playbackSpeedValue = 1.0
    var playbackSpeed: Double {
        get { playbackSpeedValue }
        set {
            let next = newValue.clamped(to: 0.5...1.5)
            guard playbackSpeedValue != next else { return }
            playbackSpeedValue = next
            saveSettings()
            restartPlaybackIfNeeded()
        }
    }
    @Published var loopEnabled: Bool {
        didSet { saveSettings(); restartPlaybackIfNeeded() }
    }
    /// Loop start in musical milliseconds. It is clamped when playback starts.
    @Published private var loopStartValue: Int64 = 0
    var loopStartMilliseconds: Int64 {
        get { loopStartValue }
        set {
            let next = max(0, newValue)
            guard loopStartValue != next else { return }
            loopStartValue = next
            saveSettings()
            restartPlaybackIfNeeded()
        }
    }
    /// Loop end in musical milliseconds. Zero means the end of the selected song.
    @Published private var loopEndValue: Int64 = 0
    var loopEndMilliseconds: Int64 {
        get { loopEndValue }
        set {
            let next = max(0, newValue)
            guard loopEndValue != next else { return }
            loopEndValue = next
            saveSettings()
            restartPlaybackIfNeeded()
        }
    }
    @Published var countInEnabled: Bool { didSet { saveSettings() } }
    @Published private var countInBarsValue = 1
    var countInBars: Int {
        get { countInBarsValue }
        set {
            let next = newValue.clamped(to: 1...2)
            guard countInBarsValue != next else { return }
            countInBarsValue = next
            saveSettings()
        }
    }
    @Published var playbackHand: PracticeHandSelection {
        didSet { saveSettings(); restartPlaybackIfNeeded() }
    }
    @Published var practiceMode: PracticeMode {
        didSet {
            saveSettings()
            if practiceActive { stopPractice() }
        }
    }
    @Published var practiceHand: PracticeHandSelection {
        didSet {
            saveSettings()
            if practiceActive { stopPractice() }
        }
    }
    @Published private(set) var practiceActive = false
    @Published private(set) var practiceCountingIn = false
    @Published private(set) var practiceCountInBeat = 0
    @Published private(set) var practiceTargetNotes: Set<Int> = []
    @Published private(set) var practiceMatchedNotes: Set<Int> = []
    @Published private(set) var lastPracticeEvaluation: PracticeEvaluation?
    @Published private(set) var lastPracticeSummary: PracticeSessionSummary?
    @Published private(set) var practiceHistory: [PracticeSessionSummary] = []
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
    private let historyStore: PracticeHistoryStore
    private let defaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    private var metronomeTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?
    private var playbackGeneration: UInt64 = 0
    private var activeSongNoteCounts: [Int: Int] = [:]
    /// Exact song note state used by the scheduler. The published copies are
    /// throttled because the keyboard is visual feedback, not the timing source.
    private var activeSongNotesValue: Set<Int> = []
    private var latestSongNoteNumberValue: Int?
    /// Musical-time release deadlines for song notes. Keeping these in the
    /// playback scheduler avoids creating one Swift concurrency task per note.
    private var activeSongNoteEndTimes: [Int: [Int64]] = [:]
    private struct InputNote: Hashable {
        let source: MIDIInputSource
        let sourceID: String?
        let channel: Int
        let note: Int
    }
    private var liveVoices: [InputNote: UUID] = [:]
    private var previewTasks: [Int: Task<Void, Never>] = [:]
    private var practiceSession: PracticeSession?
    private var practiceStartedAtNanoseconds: UInt64?
    private var practiceHeldInputs: Set<InputNote> = []
    private var playbackStartedAtNanoseconds: UInt64?
    private var playbackClockSpeed = 1.0
    private var lastPublishedPlaybackPositionMilliseconds: Int64?
    private var lastRawPacketPublishedAtNanoseconds: UInt64 = 0
    private var playbackDurationCache: [String: (hand: PracticeHandSelection, duration: Int64)] = [:]
    private var pendingLiveNoteEvents: [MIDINoteEvent] = []
    private var liveVisualFlushTask: Task<Void, Never>?
    private var lastSongNoteEventPublishedAtNanoseconds: UInt64 = 0
    private var lastSongVisualStatePublishedAtNanoseconds: UInt64 = 0
    private var songVisualStateDirty = false

    init(
        defaults: UserDefaults = .standard,
        libraryStore: SongLibraryStore = .init(),
        historyStore: PracticeHistoryStore = .init()
    ) {
        self.defaults = defaults
        self.libraryStore = libraryStore
        self.historyStore = historyStore
        appearance = AppAppearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        language = PiaKeysLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .english
        audioEnabled = defaults.object(forKey: Keys.audioEnabled) as? Bool ?? true
        audioVolume = defaults.object(forKey: Keys.audioVolume) as? Double ?? 1
        tempoValue = (defaults.object(forKey: Keys.tempo) as? Int ?? 84).clamped(to: 40...220)
        timeSignature = defaults.string(forKey: Keys.timeSignature) ?? "4/4"
        firstBeatAccent = defaults.object(forKey: Keys.firstBeatAccent) as? Bool ?? true
        visualPulse = defaults.object(forKey: Keys.visualPulse) as? Bool ?? true
        soundProfile = defaults.string(forKey: Keys.soundProfile) ?? "Woodblock"
        showFullKeyboard = defaults.object(forKey: Keys.showFullKeyboard) as? Bool ?? true
        playbackSpeedValue = (defaults.object(forKey: Keys.playbackSpeed) as? Double ?? 1).clamped(to: 0.5...1.5)
        loopEnabled = defaults.object(forKey: Keys.loopEnabled) as? Bool ?? false
        loopStartValue = max(0, defaults.object(forKey: Keys.loopStartMilliseconds) as? Int64 ?? 0)
        loopEndValue = max(0, defaults.object(forKey: Keys.loopEndMilliseconds) as? Int64 ?? 0)
        countInEnabled = defaults.object(forKey: Keys.countInEnabled) as? Bool ?? false
        countInBarsValue = (defaults.object(forKey: Keys.countInBars) as? Int ?? 1).clamped(to: 1...2)
        playbackHand = PracticeHandSelection(rawValue: defaults.string(forKey: Keys.playbackHand) ?? "") ?? .both
        practiceMode = PracticeMode(rawValue: defaults.string(forKey: Keys.practiceMode) ?? "") ?? .playback
        practiceHand = PracticeHandSelection(rawValue: defaults.string(forKey: Keys.practiceHand) ?? "") ?? .both
        songVisualizationMode = SongVisualizationMode(
            rawValue: defaults.string(forKey: Keys.songVisualizationMode) ?? ""
        ) ?? .sheetMusic

        do {
            songs = try libraryStore.load()
            selectedSongID = songs.first?.id ?? PracticeSong.demo.id
        } catch {
            importMessage = LocalizedCopy(language: language).restoreLibraryFailed(error.localizedDescription)
        }
        do {
            practiceHistory = try historyStore.load()
        } catch {
            importMessage = importMessage ?? LocalizedCopy(language: language).restoreHistoryFailed(error.localizedDescription)
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
        liveVisualFlushTask?.cancel()
        previewTasks.values.forEach { $0.cancel() }
    }

    var selectedSong: PracticeSong? {
        songs.first { $0.id == selectedSongID } ?? songs.first
    }

    var selectedSongProgress: Double {
        guard let selectedSong, let duration = playbackDurationIfAvailable(for: selectedSong), duration > 0 else { return 0 }
        return (Double(songPositionMilliseconds) / Double(duration)).clamped(to: 0...1)
    }

    var selectedSongDurationMilliseconds: Int64 {
        guard let selectedSong else { return 0 }
        return playbackDuration(for: selectedSong)
    }

    var metronomeBeatsPerBar: Int {
        meterBeatDefinition(timeSignature, tempo: tempo).beatsPerBar
    }

    var metronomeBeatIntervalMilliseconds: Int {
        meterBeatDefinition(timeSignature, tempo: tempo).intervalMilliseconds
    }

    private func playbackDurationIfAvailable(for song: PracticeSong) -> Int64? {
        playbackDuration(for: song)
    }

    private func restartPlaybackIfNeeded() {
        guard songPlaying else { return }
        let position = songPositionMilliseconds
        stopSong(clearPosition: false)
        songPositionMilliseconds = position
        lastPublishedPlaybackPositionMilliseconds = position
        startSong()
    }

    /// Publishes the playhead at a UI-friendly rate while the scheduler keeps
    /// checking note deadlines more frequently. This prevents score/WebView
    /// updates from competing with audio and MIDI scheduling.
    private func publishPlaybackPosition(_ milliseconds: Int64, force: Bool = false) {
        let value = max(0, milliseconds)
        if force ||
            lastPublishedPlaybackPositionMilliseconds == nil ||
            abs(value - (lastPublishedPlaybackPositionMilliseconds ?? value)) >= Self.playbackUIUpdateIntervalMilliseconds {
            songPositionMilliseconds = value
            lastPublishedPlaybackPositionMilliseconds = value
            publishSongUIState()
        }
    }

    /// Publishes keyboard and monitor state at a slower visual budget than the
    /// playhead. Note deadlines and external MIDI output continue to use exact
    /// state.
    private func publishSongUIState(force: Bool = false) {
        let now = DispatchTime.now().uptimeNanoseconds
        guard force || lastSongVisualStatePublishedAtNanoseconds == 0 ||
            now - lastSongVisualStatePublishedAtNanoseconds >= Self.songVisualStateUpdateIntervalNanoseconds else {
            return
        }
        guard force || songVisualStateDirty else { return }
        if activeSongNotes != activeSongNotesValue {
            activeSongNotes = activeSongNotesValue
        }
        if latestSongNoteNumber != latestSongNoteNumberValue {
            latestSongNoteNumber = latestSongNoteNumberValue
        }
        lastSongVisualStatePublishedAtNanoseconds = now
        songVisualStateDirty = false
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
        let source = activeNoteEvent?.source ?? (visibleWiredSources.isEmpty ? nil : .wired)
        return LocalizedCopy(language: language).sourceName(source)
    }

    var overallConnectionLabel: String {
        LocalizedCopy(language: language).overallConnectionLabel(
            status: bleStatus,
            hasExternalMIDI: hasExternalWiredMIDI
        )
    }

    var canSendWiredMIDI: Bool { coreMIDI.canSendNotes }
    var canSendBLEMIDI: Bool { bluetoothDestinationName != nil || ble.canSendDirectNotes }
    var hasExternalMIDIConnection: Bool { bleStatus.isConnected || hasExternalWiredMIDI }
    var pianoSampleCount: Int { audio.sampleCount }

    var visibleWiredSources: [CoreMIDIPort] {
        wiredSources.filter { !CoreMIDIManager.isNetworkSession($0.name) }
    }

    var visibleWiredDestinations: [CoreMIDIPort] {
        wiredDestinations.filter { !CoreMIDIManager.isNetworkSession($0.name) }
    }

    private var hasExternalWiredMIDI: Bool {
        !visibleWiredSources.isEmpty || !visibleWiredDestinations.isEmpty
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
        finishPracticeSession()
        stopSong(clearPosition: true)
        selectedSongID = id
    }

    func toggleSongPlayback() {
        if practiceActive && practiceMode == .waitForNote {
            finishPracticeSession()
            return
        }
        songPlaying ? stopSong(clearPosition: false) : startSong()
    }

    func resetSong() {
        finishPracticeSession()
        stopSong(clearPosition: true)
    }

    /// Moves the playhead while flushing currently sounding song notes.
    func seekSong(to milliseconds: Int64) {
        guard let song = selectedSong else { return }
        let duration = playbackDuration(for: song)
        let target = milliseconds.clamped(to: 0...duration)
        let wasPlaying = songPlaying
        stopSong(clearPosition: false)
        publishPlaybackPosition(target, force: true)
        practiceSession?.start()
        updatePracticeState()
        if wasPlaying { startSong() }
    }

    /// Starts a wait-for-note or timed practice session for the selected song.
    func startPractice() {
        guard let song = selectedSong else { return }
        finishPracticeSession()
        stopSong(clearPosition: true)
        if practiceMode == .playback {
            startSong()
            return
        }
        let session = PracticeSession(
            song: song,
            mode: practiceMode,
            hand: practiceHand,
            speed: playbackSpeed
        )
        practiceSession = session
        practiceActive = true
        lastPracticeEvaluation = nil
        lastPracticeSummary = nil
        if practiceMode == .waitForNote {
            let now = DispatchTime.now().uptimeNanoseconds
            session.start(at: now)
            practiceStartedAtNanoseconds = now
        } else {
            // Timed practice starts after an optional count-in, inside the
            // playback clock, so the count-in is not scored or timed.
            practiceStartedAtNanoseconds = nil
        }
        updatePracticeState()
        if practiceMode == .timed {
            startSong()
        }
    }

    /// Stops the current practice run, persists its summary, and clears targets.
    func stopPractice() {
        finishPracticeSession()
        stopSong(clearPosition: false)
    }

    /// Deletes a song and its app-owned score attachment from the library.
    func deleteSong(_ id: String) {
        guard songs.count > 1, let index = songs.firstIndex(where: { $0.id == id }) else { return }
        if selectedSongID == id { finishPracticeSession(); stopSong(clearPosition: true) }
        let removed = songs[index]
        var updated = songs
        updated.remove(at: index)
        do {
            try libraryStore.save(updated)
            songs = updated
            if selectedSongID == id { selectedSongID = updated.first?.id ?? PracticeSong.demo.id }
            if let scoreURL = removed.scoreURL { try? FileManager.default.removeItem(at: scoreURL) }
        } catch {
            importMessage = LocalizedCopy(language: language).removeSongFailed(error.localizedDescription)
        }
    }

    /// Removes all persisted practice summaries while keeping song data intact.
    func clearPracticeHistory() {
        do {
            try historyStore.save([])
            practiceHistory = []
        } catch {
            importMessage = LocalizedCopy(language: language).clearHistoryFailed(error.localizedDescription)
        }
    }

    /// Pause on backgrounding/interruption; never silently resume playback after a call.
    func suspendPlayback() {
        finishPracticeSession()
        stopSong(clearPosition: false)
        metronomeRunning = false
        previewTasks.values.forEach { $0.cancel() }
        previewTasks.removeAll()
        liveVoices.removeAll()
        cancelLiveVisualFlush()
        heldNoteNumbers = []
        audio.stopAll()
    }

    func importSong(from url: URL) {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }

        do {
            let fileExtension = url.pathExtension.lowercased()
            guard fileExtension == "mid" || fileExtension == "midi" else {
                importMessage = LocalizedCopy(language: language).invalidMIDIFile
                return
            }
            let data = try Data(contentsOf: url)
            let song = try StandardMIDIFileParser.parse(
                data: data,
                fallbackTitle: url.deletingPathExtension().lastPathComponent
            )
            if let existing = songs.first(where: { $0.id == song.id }) {
                selectSong(existing.id)
                importMessage = LocalizedCopy(language: language).songAlreadyInLibrary(existing.title)
            } else {
                let updatedSongs = songs + [song]
                try libraryStore.save(updatedSongs)
                songs = updatedSongs
                selectSong(song.id)
                importMessage = LocalizedCopy(language: language).importedSong(song.title)
            }
        } catch {
            importMessage = LocalizedCopy(language: language).importMIDIFailed(error.localizedDescription)
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
            importMessage = LocalizedCopy(language: language).scoreAttached(songs[index].title)
        } catch {
            importMessage = LocalizedCopy(language: language).importScoreFailed(error.localizedDescription)
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
        NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereLostNotification)
            .merge(with: NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.suspendPlayback() }
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
            // Raw bytes are diagnostic UI, not the timing path. Bound their
            // publication rate so a dense MIDI stream cannot redraw the whole
            // monitor for every packet.
            let now = DispatchTime.now().uptimeNanoseconds
            guard now - self.lastRawPacketPublishedAtNanoseconds >= 50_000_000 else { return }
            self.lastRawPacketPublishedAtNanoseconds = now
            self.rawPackets.insert(packet, at: 0)
            self.rawPackets = Array(self.rawPackets.prefix(40))
        }
        coreMIDI.onEvents = { [weak self] events in self?.consume(events: events) }
    }

    private func consume(events: [MIDINoteEvent]) {
        guard !events.isEmpty else { return }
        for event in events {
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
            if practiceActive,
               event.source == .ble || event.source == .wired || event.source == .preview {
                switch event.type {
                case .noteOn:
                    // A held key must not satisfy the next target until a real
                    // note-off creates a new attack.
                    if practiceHeldInputs.insert(key).inserted, !practiceCountingIn {
                        handlePracticeEvent(event)
                    }
                case .noteOff:
                    practiceHeldInputs.remove(key)
                }
            }
        }
        pendingLiveNoteEvents.append(contentsOf: events)
        scheduleLiveVisualFlush()
    }

    /// Coalesces dense input bursts into one monitor update per display budget.
    /// Audio playback, note ownership, and practice evaluation above remain
    /// immediate; only diagnostic SwiftUI state waits up to 33 ms.
    private func scheduleLiveVisualFlush() {
        guard liveVisualFlushTask == nil else { return }
        liveVisualFlushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(33))
            guard !Task.isCancelled else { return }
            self?.flushLiveVisualState()
        }
    }

    private func flushLiveVisualState() {
        liveVisualFlushTask = nil
        heldNoteNumbers = Set(liveVoices.keys.map(\.note))
        guard !pendingLiveNoteEvents.isEmpty else { return }
        let events = pendingLiveNoteEvents
        pendingLiveNoteEvents.removeAll(keepingCapacity: true)
        recordRecentNoteEvents(events)
    }

    private func cancelLiveVisualFlush() {
        liveVisualFlushTask?.cancel()
        liveVisualFlushTask = nil
        pendingLiveNoteEvents.removeAll(keepingCapacity: true)
    }

    private func recordRecentNoteEvents(_ events: [MIDINoteEvent]) {
        guard !events.isEmpty else { return }
        noteEvents = Array((noteEvents + events).sorted { $0.timestamp > $1.timestamp }.prefix(40))
    }

    private func handlePracticeEvent(_ event: MIDINoteEvent) {
        guard let session = practiceSession else { return }
        let evaluation = session.handle(
            noteOn: event,
            playbackPositionMilliseconds: playbackPosition(at: event.monotonicNanoseconds)
        )
        lastPracticeEvaluation = evaluation
        updatePracticeState()
        if session.isComplete { finishPracticeSession() }
    }

    private func updatePracticeState() {
        practiceTargetNotes = practiceSession?.currentTarget?.notes ?? []
        practiceMatchedNotes = practiceSession?.matchedNotes ?? []
    }

    private func finishPracticeSession() {
        guard let session = practiceSession else {
            practiceActive = false
            practiceHeldInputs.removeAll()
            practiceTargetNotes = []
            practiceMatchedNotes = []
            return
        }
        session.finish()
        let now = DispatchTime.now().uptimeNanoseconds
        let duration = practiceStartedAtNanoseconds.map { Double(now - $0) / 1_000_000_000 } ?? 0
        let summary = session.summary(activeDurationSeconds: duration)
        lastPracticeSummary = summary
        practiceHistory.insert(summary, at: 0)
        practiceHistory = Array(practiceHistory.prefix(100))
        do {
            try historyStore.save(practiceHistory)
        } catch {
            importMessage = LocalizedCopy(language: language).saveHistoryFailed(error.localizedDescription)
        }
        practiceSession = nil
        practiceStartedAtNanoseconds = nil
        practiceHeldInputs.removeAll()
        practiceActive = false
        practiceTargetNotes = []
        practiceMatchedNotes = []
    }

    private func playbackPosition(at nanoseconds: UInt64) -> Int64 {
        guard let started = playbackStartedAtNanoseconds,
              nanoseconds >= started,
              let duration = selectedSong.map({ playbackDuration(for: $0) }) else {
            return songPositionMilliseconds
        }
        let elapsedMilliseconds = Double(nanoseconds - started) / 1_000_000
        return Int64((elapsedMilliseconds * playbackClockSpeed).rounded()).clamped(to: 0...duration)
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
        cancelLiveVisualFlush()
        let previewKeys = liveVoices.keys.filter { $0.source == .preview }
        for key in previewKeys {
            if let voice = liveVoices.removeValue(forKey: key) { audio.releaseNote(voice) }
            sendPreviewNoteOff(key.note)
        }
        previewTasks.values.forEach { $0.cancel() }
        previewTasks.removeAll()
        practiceHeldInputs = practiceHeldInputs.filter { $0.source != .preview }
        heldNoteNumbers = Set(liveVoices.keys.map(\.note))
    }

    private func clearInput(source: MIDIInputSource, sourceID: String? = nil) {
        cancelLiveVisualFlush()
        let keys = liveVoices.keys.filter { $0.source == source && (sourceID == nil || $0.sourceID == sourceID) }
        for key in keys {
            if let voice = liveVoices.removeValue(forKey: key) { audio.releaseNote(voice) }
        }
        practiceHeldInputs = practiceHeldInputs.filter { key in
            key.source != source || (sourceID != nil && key.sourceID != sourceID)
        }
        heldNoteNumbers = Set(liveVoices.keys.map(\.note))
    }

    private func startSong() {
        guard let song = selectedSong else { return }
        stopSong(clearPosition: false)
        songPlaying = true
        let notes = playbackNotes(for: song)
        let duration = playbackDuration(for: song)
        let startingPosition = songPositionMilliseconds.clamped(to: 0...duration)
        let speed = playbackSpeed
        let loop = loopRange(for: duration)
        songPositionMilliseconds = startingPosition
        lastPublishedPlaybackPositionMilliseconds = startingPosition
        playbackStartedAtNanoseconds = nil
        playbackClockSpeed = speed
        playbackGeneration &+= 1
        let generation = playbackGeneration

        playbackTask = Task { [weak self] in
            guard let self else { return }
            await audio.prepareForPlayback(
                notes: notes.map { ($0.noteNumber, $0.velocity) }
            )
            guard !Task.isCancelled, self.playbackGeneration == generation else { return }
            let clock = ContinuousClock()
            var startedAt = clock.now - .milliseconds(Int64(Double(startingPosition) / speed))
            var index = notes.firstIndex {
                $0.startMilliseconds + $0.durationMilliseconds >= startingPosition
            } ?? notes.count

            if startingPosition == 0, countInEnabled {
                guard await performCountIn(for: song, speed: speed, clock: clock) else { return }
                startedAt = clock.now
                index = 0
            }
            let playbackStart = DispatchTime.now().uptimeNanoseconds - UInt64(
                max(0, Double(startingPosition) / speed * 1_000_000)
            )
            playbackStartedAtNanoseconds = playbackStart
            if audioEnabled && songOutputRoute == .appOnly {
                audio.startSongPlayback(
                    notes: notes,
                    positionMilliseconds: startingPosition,
                    speed: speed,
                    loop: loop,
                    startedAtNanoseconds: playbackStart
                )
            }
            if practiceActive, practiceMode == .timed, startingPosition == 0 {
                practiceSession?.start(at: playbackStart)
                practiceStartedAtNanoseconds = playbackStart
                updatePracticeState()
            }

            while !Task.isCancelled, self.playbackGeneration == generation {
                let elapsed = startedAt.duration(to: clock.now)
                let realMilliseconds = Int64(elapsed.components.seconds * 1_000) +
                    Int64(elapsed.components.attoseconds / 1_000_000_000_000_000)
                let milliseconds = Int64(Double(realMilliseconds) * speed)

                if let loop, milliseconds >= loop.upperBound {
                    stopActiveSongNotes()
                    publishPlaybackPosition(loop.lowerBound, force: true)
                    startedAt = clock.now - .milliseconds(Int64(Double(loop.lowerBound) / speed))
                    playbackStartedAtNanoseconds = DispatchTime.now().uptimeNanoseconds - UInt64(
                        max(0, Double(loop.lowerBound) / speed * 1_000_000)
                    )
                    index = notes.firstIndex {
                        $0.startMilliseconds + $0.durationMilliseconds >= loop.lowerBound
                    } ?? notes.count
                    continue
                }

                publishPlaybackPosition(milliseconds.clamped(to: 0...duration))
                releaseExpiredSongNotes(at: milliseconds)

                while index < notes.count, notes[index].startMilliseconds <= milliseconds {
                    guard !Task.isCancelled, self.playbackGeneration == generation else { return }
                    let note = notes[index]
                    let remaining = note.remainingDuration(at: milliseconds)
                    if remaining > 0 {
                        let scaledDuration = max(1, Int64(Double(remaining) / speed))
                        playSongNote(note, durationMilliseconds: scaledDuration)
                    }
                    index += 1
                }
                if practiceActive, let session = practiceSession, practiceMode == .timed {
                    for evaluation in session.advanceTimedSession(to: milliseconds) {
                        lastPracticeEvaluation = evaluation
                    }
                    updatePracticeState()
                }
                if milliseconds >= duration {
                    finishSong()
                    return
                }

                // Sleep until work is actually due. A fixed 12 ms polling loop
                // wakes the main actor more than 80 times per second even
                // during long rests, competing with SwiftUI and audio routing.
                // The note scheduler remains deadline-driven while the UI is
                // refreshed at its independent 30 Hz cadence.
                let nextNoteMilliseconds = index < notes.count
                    ? notes[index].startMilliseconds
                    : duration
                let nextNoteReleaseMilliseconds = activeSongNoteEndTimes.values
                    .flatMap { $0 }
                    .min() ?? duration
                let nextUIUpdateMilliseconds = (lastPublishedPlaybackPositionMilliseconds ?? milliseconds)
                    + Self.playbackUIUpdateIntervalMilliseconds
                let nextWakeMilliseconds = min(
                    nextNoteMilliseconds,
                    min(nextNoteReleaseMilliseconds, min(nextUIUpdateMilliseconds, duration))
                )
                let musicalWaitMilliseconds = max(1, nextWakeMilliseconds - milliseconds)
                let realWaitMilliseconds = max(
                    1,
                    Int64((Double(musicalWaitMilliseconds) / speed).rounded(.up))
                )
                try? await Task.sleep(for: .milliseconds(realWaitMilliseconds))
            }
        }
    }

    private func playbackNotes(for song: PracticeSong) -> [SongNote] {
        song.notes.filter { playbackHand.includes($0.hand) }
    }

    private func playbackDuration(for song: PracticeSong) -> Int64 {
        if let cached = playbackDurationCache[song.id], cached.hand == playbackHand {
            return cached.duration
        }
        let duration = playbackNotes(for: song).map { $0.startMilliseconds + $0.durationMilliseconds }.max() ?? 0
        playbackDurationCache[song.id] = (playbackHand, duration)
        return duration
    }

    private func loopRange(for duration: Int64) -> ClosedRange<Int64>? {
        guard loopEnabled else { return nil }
        let start = loopStartMilliseconds.clamped(to: 0...duration)
        let end = (loopEndMilliseconds == 0 ? duration : loopEndMilliseconds).clamped(to: 0...duration)
        guard end > start else { return nil }
        return start...end
    }

    private func performCountIn(
        for song: PracticeSong,
        speed: Double,
        clock: ContinuousClock
    ) async -> Bool {
        let meter = meterBeatDefinition(song.timeSignature, tempo: song.tempo)
        practiceCountingIn = true
        practiceCountInBeat = 0
        var deadline = clock.now
        for beat in 0..<(meter.beatsPerBar * countInBars) {
            if Task.isCancelled { practiceCountingIn = false; return false }
            practiceCountInBeat = beat
            audio.playMetronomeClick(
                accent: firstBeatAccent && beat % meter.beatsPerBar == 0,
                profile: soundProfile
            )
            deadline += .milliseconds(Int64(Double(meter.intervalMilliseconds) / speed))
            do {
                try await clock.sleep(until: deadline)
            } catch {
                practiceCountingIn = false
                return false
            }
        }
        practiceCountingIn = false
        return true
    }

    private func meterBeatDefinition(_ signature: String, tempo: Int) -> (beatsPerBar: Int, intervalMilliseconds: Int) {
        let parts = signature.split(separator: "/").compactMap { Int($0) }
        let numerator = parts.first ?? 4
        let denominator = parts.count > 1 ? parts[1] : 4
        if denominator == 8, numerator >= 6, numerator % 3 == 0 {
            return (max(1, numerator / 3), max(1, Int((90_000.0 / Double(max(1, tempo)).rounded()))) )
        }
        return (max(1, numerator), max(1, 60_000 / max(1, tempo)))
    }

    private func playSongNote(_ note: SongNote, durationMilliseconds: Int64) {
        activeSongNoteCounts[note.noteNumber, default: 0] += 1
        let startsNewVisibleGroup = activeSongNotesValue.isEmpty
        activeSongNotesValue.insert(note.noteNumber)
        songVisualStateDirty = true
        if startsNewVisibleGroup && lastSongVisualStatePublishedAtNanoseconds == 0 {
            // A resume or a quiet-to-playing transition should show its first
            // key immediately; subsequent chord/dense-song notes stay batched.
            publishSongUIState(force: true)
        }
        activeSongNoteEndTimes[note.noteNumber, default: []].append(
            note.startMilliseconds + note.durationMilliseconds
        )
        latestSongNoteNumberValue = note.noteNumber
        let event = MIDINoteEvent(
            id: note.id,
            noteNumber: note.noteNumber,
            velocity: note.velocity,
            type: .noteOn,
            source: .song
        )
        // The keyboard still receives every note, but the recent-event list is
        // diagnostic UI. Publishing it at a 4 Hz budget avoids a SwiftUI
        // redraw for every note in a dense chord or while the user scrolls.
        let now = DispatchTime.now().uptimeNanoseconds
        if noteEvents.isEmpty || now - lastSongNoteEventPublishedAtNanoseconds >= Self.songNoteEventUpdateIntervalNanoseconds {
            recordRecentNoteEvents([event])
            lastSongNoteEventPublishedAtNanoseconds = now
        }
        // External MIDI uses one gate per pitch while overlapping score voices
        // are active; its note-off is emitted by the same deadline-driven
        // scheduler when the musical end time is reached.
        if activeSongNoteCounts[note.noteNumber] == 1 { sendSongNoteOn(note) }
    }

    /// Releases score notes whose musical end has passed. This runs in the
    /// playback loop so app-only and external routes share one timing source,
    /// without allocating a sleeping task for every note in a dense song.
    private func releaseExpiredSongNotes(at milliseconds: Int64) {
        for noteNumber in Array(activeSongNoteEndTimes.keys) {
            guard let endTimes = activeSongNoteEndTimes[noteNumber] else { continue }
            let remainingEndTimes = endTimes.filter { $0 > milliseconds }
            let expiredCount = endTimes.count - remainingEndTimes.count
            guard expiredCount > 0 else { continue }

            let remainingCount = max(0, (activeSongNoteCounts[noteNumber] ?? 0) - expiredCount)
            if remainingCount == 0 {
                activeSongNoteCounts.removeValue(forKey: noteNumber)
                activeSongNotesValue.remove(noteNumber)
                songVisualStateDirty = true
                sendSongNoteOff(noteNumber)
            } else {
                activeSongNoteCounts[noteNumber] = remainingCount
            }
            if remainingEndTimes.isEmpty {
                activeSongNoteEndTimes.removeValue(forKey: noteNumber)
            } else {
                activeSongNoteEndTimes[noteNumber] = remainingEndTimes
            }
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

    private func stopActiveSongNotes() {
        for note in activeSongNotesValue { sendSongNoteOff(note) }
        activeSongNoteCounts.removeAll()
        activeSongNoteEndTimes.removeAll()
        activeSongNotesValue.removeAll()
        songVisualStateDirty = true
        activeSongNotes = []
        latestSongNoteNumberValue = nil
        latestSongNoteNumber = nil
        // The next playback run should publish its first sounding group
        // immediately, without carrying this run's visual throttle forward.
        lastSongVisualStatePublishedAtNanoseconds = 0
        songVisualStateDirty = false
        lastSongNoteEventPublishedAtNanoseconds = 0
    }

    private func stopSong(clearPosition: Bool) {
        playbackGeneration &+= 1
        audio.stopSongPlayback()
        playbackTask?.cancel()
        playbackTask = nil
        playbackStartedAtNanoseconds = nil
        practiceCountingIn = false
        stopActiveSongNotes()
        songPlaying = false
        if clearPosition {
            publishPlaybackPosition(0, force: true)
        }
    }

    private func finishSong() {
        stopSong(clearPosition: true)
        finishPracticeSession()
    }

    private func updateMetronome() {
        metronomeTask?.cancel()
        metronomeTask = nil
        metronomeBeat = 0
        metronomeBeatIndex = 0
        guard metronomeRunning else { return }
        metronomeTask = Task { [weak self] in
            guard let self else { return }
            let meter = meterBeatDefinition(timeSignature, tempo: tempo)
            var beat = 0
            let clock = ContinuousClock()
            var deadline = clock.now
            while !Task.isCancelled {
                metronomeBeat = beat
                metronomeBeatIndex &+= 1
                metronomeBeatStartedAt = Date()
                audio.playMetronomeClick(
                    accent: firstBeatAccent && beat == 0,
                    profile: soundProfile
                )
                let interval = Int64(meter.intervalMilliseconds).clamped(to: 260...1_500)
                deadline += .milliseconds(interval)
                try? await clock.sleep(until: deadline)
                if deadline < clock.now - .milliseconds(interval) { deadline = clock.now }
                beat = (beat + 1) % max(1, meter.beatsPerBar)
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
        defaults.set(playbackSpeed, forKey: Keys.playbackSpeed)
        defaults.set(loopEnabled, forKey: Keys.loopEnabled)
        defaults.set(loopStartMilliseconds, forKey: Keys.loopStartMilliseconds)
        defaults.set(loopEndMilliseconds, forKey: Keys.loopEndMilliseconds)
        defaults.set(countInEnabled, forKey: Keys.countInEnabled)
        defaults.set(countInBars, forKey: Keys.countInBars)
        defaults.set(playbackHand.rawValue, forKey: Keys.playbackHand)
        defaults.set(songVisualizationMode.rawValue, forKey: Keys.songVisualizationMode)
        defaults.set(practiceMode.rawValue, forKey: Keys.practiceMode)
        defaults.set(practiceHand.rawValue, forKey: Keys.practiceHand)
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
        static let playbackSpeed = "playback_speed"
        static let loopEnabled = "loop_enabled"
        static let loopStartMilliseconds = "loop_start_ms"
        static let loopEndMilliseconds = "loop_end_ms"
        static let countInEnabled = "count_in_enabled"
        static let countInBars = "count_in_bars"
        static let playbackHand = "playback_hand"
        static let songVisualizationMode = "song_visualization_mode"
        static let practiceMode = "practice_mode"
        static let practiceHand = "practice_hand"
    }
}
