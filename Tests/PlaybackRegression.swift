import Combine
import Foundation

// In-memory boundaries let the real MainViewModel run without opening Bluetooth,
// audio hardware or the user's library. Timing/import/state logic is production code.
struct CoreMIDIPort: Identifiable, Equatable {
    let id: UInt32
    let name: String
}
final class CoreMIDIManager {
    @Published var sources: [CoreMIDIPort] = []
    @Published var destinations: [CoreMIDIPort] = [.init(id: 1, name: "Test")]
    var onEvents: (([MIDINoteEvent]) -> Void)?
    var onRawPacket: ((RawMIDIPacket) -> Void)?
    var canSendNotes: Bool { !destinations.isEmpty }
    var canSendDirectNotes: Bool { false }
    var sent: [String] = []
    func refresh() {}
    func canSendNotes(to destinationName: String?) -> Bool { canSendNotes }
    func destinationName(matching candidateNames: [String]) -> String? { destinations.first?.name }
    func sendNoteOn(_ note: Int, velocity: Int, destinationName: String? = nil) { sent.append("on:\(note)") }
    func sendNoteOff(_ note: Int) { sent.append("off:\(note)") }
}
final class BLEMIDIManager {
    @Published var devices: [MIDIDevice] = []
    @Published var status: MIDIConnectionStatus = .idle
    @Published var compatibilityScanActive = false
    var canSendNotes: Bool { status.canSend }
    var canSendDirectNotes: Bool { false }
    var connectedDeviceName: String? { status.isConnected ? "Test" : nil }
    func startScan() { status = .scanning }
    func stopScan() { status = .idle }
    func connect(to id: UUID) {}
    func disconnect() { status = .idle }
    func sendNoteOn(_ noteNumber: Int, velocity: Int, channel: Int = 0) {}
    func sendNoteOff(_ noteNumber: Int, channel: Int = 0) {}
}
final class PianoAudioEngine {
    static var released: [UUID] = []
    static var played: [Int] = []
    let sampleCount = 0
    let sampleLibraryStatus = "Test"
    func setVolume(_ value: Double) {}
    func stopAll() {}
    func stopNotes(_ ids: Set<UUID>) {}
    func releaseNote(_ id: UUID) { Self.released.append(id) }
    func play(noteNumber: Int, velocity: Int, durationMilliseconds: Int64? = nil, voiceID: UUID? = nil) {
        Self.played.append(noteNumber)
    }
    func prepareForPlayback(notes: [(Int, Int)]) async {}
    func startSongPlayback(notes: [SongNote], positionMilliseconds: Int64, speed: Double, loop: ClosedRange<Int64>?, startedAtNanoseconds: UInt64) {
        Self.played += notes.filter { $0.remainingDuration(at: positionMilliseconds) > 0 }.map(\.noteNumber)
    }
    func stopSongPlayback() {}
    func playMetronomeClick(accent: Bool, profile: String) {}
}

@main
struct PlaybackRegression {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "PiaKeysTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        defaults.set(999, forKey: "tempo")
        let store = SongLibraryStore(directory: directory)
        let historyStore = PracticeHistoryStore(directory: directory)
        let model = MainViewModel(defaults: defaults, libraryStore: store, historyStore: historyStore)
        var broadUpdates = 0
        var playheadUpdates = 0
        let broadSubscription = model.objectWillChange.sink { broadUpdates += 1 }
        let playheadSubscription = model.playbackPosition.objectWillChange.sink { playheadUpdates += 1 }
        for tick in 1...300 { model.playbackPosition.milliseconds = Int64(tick * 33) }
        precondition(broadUpdates == 0, "Playhead ticks must not invalidate both tabs")
        precondition(playheadUpdates == 300, "Slider and score receive every playhead tick")
        model.playbackPosition.milliseconds = 0
        broadSubscription.cancel()
        playheadSubscription.cancel()
        precondition(model.tempo == 220, "Clamp persisted tempo")
        model.tempo = 999
        precondition(model.tempo == 220, "Clamp runtime tempo")
        model.playbackSpeed = 2
        precondition(model.playbackSpeed == 1.5, "Clamp playback speed")
        model.loopStartMilliseconds = -10
        model.countInBars = 3
        precondition(model.loopStartMilliseconds == 0 && model.countInBars == 2, "Clamp playback markers and count-in bars")
        let a = MIDINoteEvent(noteNumber: 60, velocity: 100, type: .noteOn, source: .ble, channel: 1)
        let b = MIDINoteEvent(noteNumber: 60, velocity: 100, type: .noteOn, source: .wired, channel: 1, sourceID: "1")
        model.coreMIDI.onEvents?([a])
        model.coreMIDI.onEvents?([b])
        model.coreMIDI.onEvents?([.init(noteNumber: 60, velocity: 0, type: .noteOff, source: .ble, channel: 1)])
        try await Task.sleep(for: .milliseconds(40))
        precondition(model.heldNoteNumbers == [60], "Other source still holds note")
        precondition(PianoAudioEngine.released == [a.id], "Release only matching source/channel")
        model.coreMIDI.onEvents?([.init(noteNumber: 60, velocity: 0, type: .noteOff, source: .wired, channel: 1, sourceID: "1")])
        try await Task.sleep(for: .milliseconds(40))
        precondition(model.heldNoteNumbers.isEmpty, "Final release clears highlight")
        model.beginPreviewNote(64)
        try await Task.sleep(for: .milliseconds(40))
        precondition(model.heldNoteNumbers == [64], "Touch-down updates the highlight")
        model.endPreviewNote(64)
        try await Task.sleep(for: .milliseconds(40))
        precondition(model.heldNoteNumbers.isEmpty, "Touch-up releases note")
        PianoAudioEngine.played.removeAll()

        model.beginPreviewNote(65)
        precondition(PianoAudioEngine.played == [65], "App-only preview renders app audio")
        model.endPreviewNote(65)
        PianoAudioEngine.played.removeAll()

        model.songOutputRoute = .wired
        model.beginPreviewNote(66)
        precondition(PianoAudioEngine.played.isEmpty, "External preview route must not render app audio")
        precondition(model.coreMIDI.sent.contains("on:66"), "External preview route sends note-on")
        model.endPreviewNote(66)
        precondition(model.coreMIDI.sent.contains("off:66"), "External preview route sends note-off")

        model.songOutputRoute = .wired
        model.toggleSongPlayback()
        try await Task.sleep(for: .milliseconds(50))
        precondition(model.songPlaying && !model.activeSongNotes.isEmpty, "Playback started")
        precondition(model.activeNoteEvent?.source == .song, "Song playback drives live note monitor")
        precondition(model.noteEvents.first?.source == .song, "Song playback is recorded in recent notes")
        precondition(PianoAudioEngine.played.isEmpty, "External MIDI route must not render app audio")
        let active = model.activeSongNotes
        model.songOutputRoute = .appOnly
        precondition(!model.songPlaying && model.activeSongNotes.isEmpty, "Route switch pauses cleanly")
        try await Task.sleep(for: .milliseconds(40))
        precondition(!model.songPlaying && model.activeSongNotes.isEmpty, "Cancelled playback cannot repopulate active notes")
        for note in active {
            precondition(model.coreMIDI.sent.contains("off:\(note)"), "Note-off sent through previous wired route")
        }

        model.toggleSongPlayback()
        try await Task.sleep(for: .milliseconds(20))
        precondition(!PianoAudioEngine.played.isEmpty, "App-only route renders app audio")
        let bytes: [UInt8] = [0x4D,0x54,0x68,0x64,0,0,0,6,0,0,0,1,0,96,0x4D,0x54,0x72,0x6B,0,0,0,12,0,0x90,60,100,96,0x80,60,0,0,0xFF,0x2F,0]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Imported.mid")
        try Data(bytes).write(to: url)
        model.importSong(from: url)
        precondition(!model.songPlaying && model.songPositionMilliseconds == 0, "Import stops old playback")
        precondition(model.selectedSongID != PracticeSong.demo.id && model.songs.count == 2, "Import selects new song")
        let restored = try store.load()
        precondition(restored.count == 2, "Imported library persisted")
        model.importSong(from: url)
        precondition(model.songs.count == 2, "Duplicate import does not duplicate song")
        let score = directory.appendingPathComponent("score.musicxml")
        try Data("<score-partwise/>".utf8).write(to: score)
        model.importScore(from: score)
        let firstScore = model.selectedSong!.scoreURL!
        model.importScore(from: score)
        precondition(model.selectedSong!.scoreURL != firstScore, "Replacing score invalidates renderer URL")
        let savedScore = try store.load().first { $0.id == model.selectedSongID }?.scoreURL
        precondition(savedScore == model.selectedSong!.scoreURL, "Score attachment persists")
        model.beginPreviewNote(67)
        model.metronomeRunning = true
        model.toggleSongPlayback()
        model.suspendPlayback()
        precondition(!model.songPlaying && !model.metronomeRunning && model.heldNoteNumbers.isEmpty, "Background/interruption clears active state")
        let resumeSong = PracticeSong(id: "resume", title: "Resume", composer: "Test", tempo: 120, timeSignature: "4/4", notes: [
            .init(startMilliseconds: 0, durationMilliseconds: 1000, noteNumber: 48, velocity: 100, hand: .left),
            .init(startMilliseconds: 10, durationMilliseconds: 20, noteNumber: 60, velocity: 100, hand: .right)
        ])
        try store.save([resumeSong])
        let resumeModel = MainViewModel(defaults: defaults, libraryStore: store, historyStore: historyStore)
        resumeModel.toggleSongPlayback()
        try await Task.sleep(for: .milliseconds(100))
        resumeModel.toggleSongPlayback()
        precondition(resumeModel.songPositionMilliseconds >= 30, "Pause past expired melody")
        resumeModel.toggleSongPlayback()
        try await Task.sleep(for: .milliseconds(15))
        precondition(resumeModel.activeSongNotes == [48], "Resume skips expired melody behind long bass")
        resumeModel.suspendPlayback()

        let practiceSong = PracticeSong(
            id: "practice",
            title: "Practice",
            composer: "Test",
            tempo: 120,
            timeSignature: "4/4",
            notes: [
                .init(startMilliseconds: 0, durationMilliseconds: 100, noteNumber: 60, velocity: 100, hand: .right),
                .init(startMilliseconds: 20, durationMilliseconds: 100, noteNumber: 64, velocity: 100, hand: .right),
                .init(startMilliseconds: 500, durationMilliseconds: 100, noteNumber: 67, velocity: 100, hand: .right)
            ]
        )
        let waitSession = PracticeSession(song: practiceSong, mode: .waitForNote, hand: .right, speed: 1)
        waitSession.start(at: 10)
        precondition(waitSession.targets.count == 2 && waitSession.targets[0].notes == [60, 64], "Group simultaneous practice targets")
        precondition(waitSession.handle(noteOn: .init(noteNumber: 60, velocity: 100, type: .noteOn), playbackPositionMilliseconds: 0).outcome == .hit, "Wait mode accepts first chord note")
        precondition(waitSession.currentTarget?.notes == [60, 64], "Chord waits for every note")
        precondition(waitSession.handle(noteOn: .init(noteNumber: 64, velocity: 100, type: .noteOn), playbackPositionMilliseconds: 500).outcome == .hit, "Wait mode accepts remaining chord note")
        precondition(waitSession.currentTarget?.notes == [67], "Wait mode advances after chord completion")
        waitSession.finish()
        precondition(waitSession.summary(activeDurationSeconds: 1).missedCount == 1, "Practice finish records missed notes")

        let timedSession = PracticeSession(song: practiceSong, mode: .timed, hand: .right, speed: 1)
        timedSession.start(at: 10)
        precondition(timedSession.handle(noteOn: .init(noteNumber: 60, velocity: 100, type: .noteOn), playbackPositionMilliseconds: 200).outcome == .late, "Timed mode reports late expected pitch")
        precondition(timedSession.handle(noteOn: .init(noteNumber: 65, velocity: 100, type: .noteOn), playbackPositionMilliseconds: 20).outcome == .wrongPitch, "Timed mode rejects wrong pitch")
        precondition(timedSession.advanceTimedSession(to: 900).contains(where: { $0.outcome == .missed }), "Timed mode records missed targets")
        precondition(timedSession.summary(activeDurationSeconds: 1).accuracy > 0, "Pitch accuracy includes correctly pitched late attempts")

        let practiceModel = MainViewModel(
            defaults: defaults,
            libraryStore: store,
            historyStore: historyStore
        )
        practiceModel.practiceMode = .waitForNote
        practiceModel.practiceHand = .right
        practiceModel.startPractice()
        let firstPracticeTarget = practiceModel.practiceTargetNotes
        precondition(!firstPracticeTarget.isEmpty, "Practice exposes initial target")
        let heldPracticeNote = firstPracticeTarget.sorted().first!
        practiceModel.beginPreviewNote(heldPracticeNote)
        let targetAfterFirstAttack = practiceModel.practiceTargetNotes
        practiceModel.beginPreviewNote(heldPracticeNote)
        precondition(practiceModel.practiceTargetNotes == targetAfterFirstAttack, "Held note cannot auto-advance practice target")
        practiceModel.endPreviewNote(heldPracticeNote)
        practiceModel.stopPractice()
        print("PASS: playback, route cleanup, input ownership, import and interruption regression scenarios")
    }
}
