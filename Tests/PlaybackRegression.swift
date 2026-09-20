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
        let model = MainViewModel(defaults: defaults, libraryStore: store)
        precondition(model.tempo == 220, "Clamp persisted tempo")
        let a = MIDINoteEvent(noteNumber: 60, velocity: 100, type: .noteOn, source: .ble, channel: 1)
        let b = MIDINoteEvent(noteNumber: 60, velocity: 100, type: .noteOn, source: .wired, channel: 1, sourceID: "1")
        model.coreMIDI.onEvents?([a])
        model.coreMIDI.onEvents?([b])
        model.coreMIDI.onEvents?([.init(noteNumber: 60, velocity: 0, type: .noteOff, source: .ble, channel: 1)])
        precondition(model.heldNoteNumbers == [60], "Other source still holds note")
        precondition(PianoAudioEngine.released == [a.id], "Release only matching source/channel")
        model.coreMIDI.onEvents?([.init(noteNumber: 60, velocity: 0, type: .noteOff, source: .wired, channel: 1, sourceID: "1")])
        precondition(model.heldNoteNumbers.isEmpty, "Final release clears highlight")
        model.beginPreviewNote(64)
        precondition(model.heldNoteNumbers == [64], "Touch-down immediately starts note")
        model.endPreviewNote(64)
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
        precondition(PianoAudioEngine.played.isEmpty, "External MIDI route must not render app audio")
        let active = model.activeSongNotes
        model.songOutputRoute = .appOnly
        precondition(!model.songPlaying && model.activeSongNotes.isEmpty, "Route switch pauses cleanly")
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
        let resumeModel = MainViewModel(defaults: defaults, libraryStore: store)
        resumeModel.toggleSongPlayback()
        try await Task.sleep(for: .milliseconds(100))
        resumeModel.toggleSongPlayback()
        precondition(resumeModel.songPositionMilliseconds >= 30, "Pause past expired melody")
        resumeModel.toggleSongPlayback()
        try await Task.sleep(for: .milliseconds(15))
        precondition(resumeModel.activeSongNotes == [48], "Resume skips expired melody behind long bass")
        resumeModel.suspendPlayback()
        print("PASS: playback, route cleanup, input ownership, import and interruption regression scenarios")
    }
}
