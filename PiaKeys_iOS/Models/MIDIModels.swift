import Foundation

enum MIDIEventType: String, Sendable {
    case noteOn = "NoteOn"
    case noteOff = "NoteOff"
}

struct MIDINoteEvent: Identifiable, Hashable, Sendable {
    let id: UUID
    let noteNumber: Int
    let velocity: Int
    let type: MIDIEventType
    let timestamp: Date
    let source: MIDIInputSource
    let channel: Int
    let sourceID: String?
    /// Monotonic arrival time used for practice timing. `Date` remains available
    /// for display, while this value is immune to wall-clock adjustments.
    let monotonicNanoseconds: UInt64

    init(
        id: UUID = UUID(),
        noteNumber: Int,
        velocity: Int,
        type: MIDIEventType,
        timestamp: Date = Date(),
        source: MIDIInputSource = .preview,
        channel: Int = 0,
        sourceID: String? = nil,
        monotonicNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) {
        self.id = id
        self.noteNumber = noteNumber.clamped(to: 0...127)
        self.velocity = velocity.clamped(to: 0...127)
        self.type = type
        self.timestamp = timestamp
        self.source = source
        self.channel = channel.clamped(to: 0...15)
        self.sourceID = sourceID
        self.monotonicNanoseconds = monotonicNanoseconds
    }

    var noteName: String { noteNumber.noteName }
    var solfegeName: String { noteNumber.solfegeName }
}

enum MIDIInputSource: String, Sendable {
    case ble = "BLE"
    case wired = "MIDI"
    case preview = "Preview"
    case song = "Song"
}

struct RawMIDIPacket: Identifiable, Hashable, Sendable {
    let id = UUID()
    let bytes: [UInt8]
    let timestamp: Date

    var hex: String { bytes.map { String(format: "%02X", $0) }.joined(separator: " ") }
    var size: Int { bytes.count }
}

struct MIDIDevice: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let signalStrength: Int
    let advertisesMIDIService: Bool
}

enum MIDIConnectionStatus: Equatable, Sendable {
    case idle
    case preparingBluetooth
    case scanning
    case connecting(String)
    case discoveringServices(String)
    case enablingNotifications(String)
    case connected(String, canSend: Bool)
    case unavailable(String)
    case failed(String)

    var label: String {
        LocalizedCopy(language: .english).statusLabel(self)
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var isScanning: Bool {
        switch self {
        case .preparingBluetooth, .scanning: true
        default: false
        }
    }

    var isBusy: Bool {
        switch self {
        case .preparingBluetooth, .scanning, .connecting, .discoveringServices, .enablingNotifications: true
        default: false
        }
    }

    /// Indicates that a selected device is currently being connected. Scanning
    /// may continue while a discovered device is already available to connect.
    var isConnectionInProgress: Bool {
        switch self {
        case .connecting, .discoveringServices, .enablingNotifications: true
        default: false
        }
    }

    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }

    var canSend: Bool {
        if case let .connected(_, canSend) = self { return canSend }
        return false
    }

    var message: String {
        LocalizedCopy(language: .english).statusMessage(self)
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: Self { self }
}

enum PiaKeysLanguage: String, CaseIterable, Identifiable {
    case english = "English"
    case vietnamese = "Tiếng Việt"
    case japanese = "日本語"

    var id: Self { self }
}

enum SongHand: String, Codable, Sendable {
    case left
    case right
}

/// Selects which hand is rendered, played, or evaluated during a practice run.
enum PracticeHandSelection: String, CaseIterable, Identifiable, Codable, Sendable {
    case both
    case left
    case right

    var id: Self { self }

    var label: String {
        localizedLabel(in: .english)
    }

    func localizedLabel(in language: PiaKeysLanguage) -> String {
        let copy = LocalizedCopy(language: language)
        switch self {
        case .both: return copy.bothHands
        case .left: return copy.leftHand
        case .right: return copy.rightHand
        }
    }

    func includes(_ hand: SongHand) -> Bool {
        switch self {
        case .both: true
        case .left: hand == .left
        case .right: hand == .right
        }
    }
}

/// Describes whether a practice session waits for the player or follows a clock.
enum PracticeMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case playback
    case waitForNote
    case timed

    var id: Self { self }

    var label: String {
        localizedLabel(in: .english)
    }

    func localizedLabel(in language: PiaKeysLanguage) -> String {
        let copy = LocalizedCopy(language: language)
        switch self {
        case .playback: return copy.playAlong
        case .waitForNote: return copy.waitForNote
        case .timed: return copy.playWithTiming
        }
    }
}

/// Selects the visual representation used by Song Studio while preserving the
/// same MIDI playback and practice timeline underneath.
enum SongVisualizationMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case sheetMusic
    case fallingNotes

    var id: Self { self }

    /// Returns the user-facing name for the selected visualization.
    func localizedLabel(in language: PiaKeysLanguage) -> String {
        let copy = LocalizedCopy(language: language)
        switch self {
        case .sheetMusic: return copy.sheetMusicMode
        case .fallingNotes: return copy.fallingNotesMode
        }
    }
}

/// A simultaneous group of notes that the player must complete together.
struct PracticeTarget: Identifiable, Hashable, Sendable {
    let id: UUID
    let startMilliseconds: Int64
    let notes: Set<Int>

    init(id: UUID = UUID(), startMilliseconds: Int64, notes: Set<Int>) {
        self.id = id
        self.startMilliseconds = startMilliseconds
        self.notes = notes
    }
}

/// Outcome of one player note against the current target.
enum PracticeNoteOutcome: String, Codable, Sendable {
    case hit
    case early
    case late
    case wrongPitch
    case extra
    case missed
}

/// One immutable result produced by the practice matcher.
struct PracticeEvaluation: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let noteNumber: Int
    let expectedNoteNumber: Int?
    let outcome: PracticeNoteOutcome
    let timingOffsetMilliseconds: Int64?
    let targetID: UUID?
    let monotonicNanoseconds: UInt64

    init(
        id: UUID = UUID(),
        noteNumber: Int,
        expectedNoteNumber: Int? = nil,
        outcome: PracticeNoteOutcome,
        timingOffsetMilliseconds: Int64? = nil,
        targetID: UUID? = nil,
        monotonicNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) {
        self.id = id
        self.noteNumber = noteNumber
        self.expectedNoteNumber = expectedNoteNumber
        self.outcome = outcome
        self.timingOffsetMilliseconds = timingOffsetMilliseconds
        self.targetID = targetID
        self.monotonicNanoseconds = monotonicNanoseconds
    }
}

/// Persisted summary of one completed practice run.
struct PracticeSessionSummary: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let songID: String
    let songTitle: String
    let completedAt: Date
    let mode: PracticeMode
    let hand: PracticeHandSelection
    let speed: Double
    let algorithmVersion: Int
    let totalTargets: Int
    let hitCount: Int
    let missedCount: Int
    let wrongPitchCount: Int
    let extraCount: Int
    let earlyCount: Int
    let lateCount: Int
    let activeDurationSeconds: Double
    let meanTimingOffsetMilliseconds: Double?
    let evaluations: [PracticeEvaluation]

    /// Number of target notes where pitch matched, regardless of onset timing.
    var pitchCorrectCount: Int {
        hitCount + earlyCount + lateCount
    }

    var accuracy: Double {
        guard totalTargets > 0 else { return 0 }
        return Double(pitchCorrectCount) / Double(totalTargets)
    }
}

/// Matches live note-on events to note groups and produces deterministic results.
final class PracticeSession {
    static let algorithmVersion = 1

    let song: PracticeSong
    let mode: PracticeMode
    let hand: PracticeHandSelection
    let speed: Double
    let timingToleranceMilliseconds: Int64
    let targets: [PracticeTarget]

    private(set) var targetIndex = 0
    private(set) var matchedNotes: Set<Int> = []
    private(set) var evaluations: [PracticeEvaluation] = []
    private(set) var startedAtNanoseconds: UInt64?

    var currentTarget: PracticeTarget? {
        guard targets.indices.contains(targetIndex) else { return nil }
        return targets[targetIndex]
    }

    var isComplete: Bool { targetIndex >= targets.count }

    init(
        song: PracticeSong,
        mode: PracticeMode,
        hand: PracticeHandSelection,
        speed: Double,
        timingToleranceMilliseconds: Int64 = 150
    ) {
        self.song = song
        self.mode = mode
        self.hand = hand
        self.speed = speed.clamped(to: 0.5...1.5)
        self.timingToleranceMilliseconds = timingToleranceMilliseconds.clamped(to: 40...500)

        let filtered = song.notes.filter { hand.includes($0.hand) }
        var grouped: [PracticeTarget] = []
        for note in filtered.sorted(by: { ($0.startMilliseconds, $0.noteNumber) < ($1.startMilliseconds, $1.noteNumber) }) {
            if let last = grouped.last,
               abs(last.startMilliseconds - note.startMilliseconds) <= 35 {
                grouped[grouped.count - 1] = PracticeTarget(
                    id: last.id,
                    startMilliseconds: last.startMilliseconds,
                    notes: last.notes.union([note.noteNumber])
                )
            } else {
                grouped.append(PracticeTarget(startMilliseconds: note.startMilliseconds, notes: [note.noteNumber]))
            }
        }
        self.targets = grouped
    }

    /// Starts or restarts matching at a monotonic clock instant.
    func start(at nanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        startedAtNanoseconds = nanoseconds
        targetIndex = 0
        matchedNotes = []
        evaluations = []
    }

    /// Accepts one note-on. Wait mode deliberately does not judge timing.
    func handle(noteOn event: MIDINoteEvent, playbackPositionMilliseconds: Int64) -> PracticeEvaluation {
        guard !isComplete else {
            let result = PracticeEvaluation(
                noteNumber: event.noteNumber,
                outcome: .extra,
                monotonicNanoseconds: event.monotonicNanoseconds
            )
            evaluations.append(result)
            return result
        }

        if mode == .waitForNote {
            return handleWaitMode(event)
        }

        advanceTimedSession(to: playbackPositionMilliseconds)
        guard let target = currentTarget else {
            let result = PracticeEvaluation(noteNumber: event.noteNumber, outcome: .extra, monotonicNanoseconds: event.monotonicNanoseconds)
            evaluations.append(result)
            return result
        }
        guard target.notes.contains(event.noteNumber), !matchedNotes.contains(event.noteNumber) else {
            let expected = target.notes.sorted().first
            let result = PracticeEvaluation(
                noteNumber: event.noteNumber,
                expectedNoteNumber: expected,
                outcome: .wrongPitch,
                targetID: target.id,
                monotonicNanoseconds: event.monotonicNanoseconds
            )
            evaluations.append(result)
            return result
        }

        let offset = playbackPositionMilliseconds - target.startMilliseconds
        let outcome: PracticeNoteOutcome
        if abs(offset) <= timingToleranceMilliseconds {
            outcome = .hit
        } else if offset < 0 {
            outcome = .early
        } else {
            outcome = .late
        }
        let result = PracticeEvaluation(
            noteNumber: event.noteNumber,
            expectedNoteNumber: event.noteNumber,
            outcome: outcome,
            timingOffsetMilliseconds: offset,
            targetID: target.id,
            monotonicNanoseconds: event.monotonicNanoseconds
        )
        evaluations.append(result)
        if outcome == .hit || outcome == .early || outcome == .late {
            matchedNotes.insert(event.noteNumber)
            advanceWhenTargetIsComplete()
        }
        return result
    }

    /// Marks clocked targets as missed. Returns only newly created miss results.
    @discardableResult
    func advanceTimedSession(to playbackPositionMilliseconds: Int64) -> [PracticeEvaluation] {
        guard mode == .timed else { return [] }
        var misses: [PracticeEvaluation] = []
        // Keep a target alive for one additional tolerance window so a player
        // who strikes the expected key late receives a `.late` result instead
        // of an indistinguishable `.extra` result. The next clock tick then
        // records any still-unplayed notes as missed.
        let missGrace = timingToleranceMilliseconds.multipliedReportingOverflow(by: 2)
        let graceMilliseconds = missGrace.overflow ? Int64.max : missGrace.partialValue
        while let target = currentTarget,
              playbackPositionMilliseconds > (target.startMilliseconds > Int64.max - graceMilliseconds
                ? Int64.max
                : target.startMilliseconds + graceMilliseconds) {
            let missing = target.notes.subtracting(matchedNotes)
            for note in missing {
                let result = PracticeEvaluation(
                    noteNumber: note,
                    expectedNoteNumber: note,
                    outcome: .missed,
                    targetID: target.id,
                    monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds
                )
                evaluations.append(result)
                misses.append(result)
            }
            moveToNextTarget()
        }
        return misses
    }

    /// Finishes a wait-mode run by marking the unplayed target notes as missed.
    func finish() {
        while let target = currentTarget {
            for note in target.notes.subtracting(matchedNotes) {
                evaluations.append(.init(noteNumber: note, expectedNoteNumber: note, outcome: .missed, targetID: target.id))
            }
            moveToNextTarget()
        }
    }

    func summary(completedAt: Date = Date(), activeDurationSeconds: Double) -> PracticeSessionSummary {
        let offsets = evaluations.compactMap(\.timingOffsetMilliseconds)
        return PracticeSessionSummary(
            id: UUID(),
            songID: song.id,
            songTitle: song.title,
            completedAt: completedAt,
            mode: mode,
            hand: hand,
            speed: speed,
            algorithmVersion: Self.algorithmVersion,
            totalTargets: targets.reduce(0) { $0 + $1.notes.count },
            hitCount: evaluations.count(where: { $0.outcome == .hit }),
            missedCount: evaluations.count(where: { $0.outcome == .missed }),
            wrongPitchCount: evaluations.count(where: { $0.outcome == .wrongPitch }),
            extraCount: evaluations.count(where: { $0.outcome == .extra }),
            earlyCount: evaluations.count(where: { $0.outcome == .early }),
            lateCount: evaluations.count(where: { $0.outcome == .late }),
            activeDurationSeconds: max(0, activeDurationSeconds),
            meanTimingOffsetMilliseconds: offsets.isEmpty ? nil : Double(offsets.reduce(0, +)) / Double(offsets.count),
            evaluations: evaluations
        )
    }

    private func handleWaitMode(_ event: MIDINoteEvent) -> PracticeEvaluation {
        guard let target = currentTarget, target.notes.contains(event.noteNumber), !matchedNotes.contains(event.noteNumber) else {
            let result = PracticeEvaluation(
                noteNumber: event.noteNumber,
                expectedNoteNumber: currentTarget?.notes.sorted().first,
                outcome: currentTarget == nil ? .extra : .wrongPitch,
                targetID: currentTarget?.id,
                monotonicNanoseconds: event.monotonicNanoseconds
            )
            evaluations.append(result)
            return result
        }
        let result = PracticeEvaluation(
            noteNumber: event.noteNumber,
            expectedNoteNumber: event.noteNumber,
            outcome: .hit,
            targetID: target.id,
            monotonicNanoseconds: event.monotonicNanoseconds
        )
        evaluations.append(result)
        matchedNotes.insert(event.noteNumber)
        advanceWhenTargetIsComplete()
        return result
    }

    private func advanceWhenTargetIsComplete() {
        guard let target = currentTarget, target.notes.isSubset(of: matchedNotes) else { return }
        moveToNextTarget()
    }

    private func moveToNextTarget() {
        targetIndex += 1
        matchedNotes = []
    }
}

struct SongNote: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    let startMilliseconds: Int64
    let durationMilliseconds: Int64
    let noteNumber: Int
    let velocity: Int
    let hand: SongHand

    /// Remaining sounding duration at a playhead in milliseconds. Expired notes
    /// are skipped on resume instead of being replayed behind a sustained bass.
    func remainingDuration(at position: Int64) -> Int64 {
        max(0, startMilliseconds + durationMilliseconds - max(startMilliseconds, position))
    }
}

struct PracticeSong: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let composer: String
    let tempo: Int
    let timeSignature: String
    let notes: [SongNote]
    var scoreURL: URL?

    var durationMilliseconds: Int64 {
        notes.map { $0.startMilliseconds + $0.durationMilliseconds }.max() ?? 0
    }

    static let demo: PracticeSong = {
        let beat: Int64 = 714
        var notes: [SongNote] = []
        let bass = [48, 43, 45, 40]
        let chords = [[55, 60, 64], [55, 59, 62], [57, 60, 64], [52, 55, 60]]

        for (bar, bassNote) in bass.enumerated() {
            let startBeat = bar * 3
            notes.append(.init(
                startMilliseconds: Int64(startBeat) * beat,
                durationMilliseconds: Int64(Double(beat) * 1.05),
                noteNumber: bassNote,
                velocity: 74,
                hand: .left
            ))
            for note in chords[bar] {
                for beatOffset in 1...2 {
                    notes.append(.init(
                        startMilliseconds: Int64(startBeat + beatOffset) * beat,
                        durationMilliseconds: Int64(Double(beat) * 0.62),
                        noteNumber: note,
                        velocity: beatOffset == 1 ? 58 : 54,
                        hand: .left
                    ))
                }
            }
        }

        let melody = [72, 74, 76, 79, 76, 74, 72, 71, 72, 67, 69, 72]
        for (index, note) in melody.enumerated() {
            notes.append(.init(
                startMilliseconds: Int64(index) * beat,
                durationMilliseconds: Int64(Double(beat) * (index % 3 == 0 ? 0.95 : 0.72)),
                noteNumber: note,
                velocity: 92,
                hand: .right
            ))
        }

        for (index, note) in [48, 55, 60, 64, 72].enumerated() {
            notes.append(.init(
                startMilliseconds: 12 * beat,
                durationMilliseconds: 2 * beat,
                noteNumber: note,
                velocity: index == 0 ? 76 : 88,
                hand: index == 0 ? .left : .right
            ))
        }

        return PracticeSong(
            id: "piakeys-waltz-study",
            title: "PiaKeys Waltz Study",
            composer: "Original demo",
            tempo: 84,
            timeSignature: "3/4",
            notes: notes.sorted {
                ($0.startMilliseconds, $0.noteNumber) < ($1.startMilliseconds, $1.noteNumber)
            }
        )
    }()
}

enum SongOutputRoute: String, CaseIterable, Identifiable {
    case appOnly = "App only"
    case wired = "Wired MIDI"
    case ble = "Bluetooth MIDI"

    var id: Self { self }
}

struct PianoChord: Equatable, Sendable {
    enum Quality: String, Sendable {
        case major
        case minor
    }

    let rootPitchClass: Int
    let quality: Quality

    var symbol: String {
        Self.rootSymbols[rootPitchClass] + (quality == .minor ? "m" : "")
    }

    private static let rootSymbols = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
}

enum ChordRecognizer {
    static func recognize(_ noteNumbers: Set<Int>) -> PianoChord? {
        let pitchClasses = Set(noteNumbers.map { $0.positiveModulo(12) })
        guard pitchClasses.count == 3 else { return nil }

        for root in 0..<12 {
            if pitchClasses == Set([root, (root + 4) % 12, (root + 7) % 12]) {
                return PianoChord(rootPitchClass: root, quality: .major)
            }
            if pitchClasses == Set([root, (root + 3) % 12, (root + 7) % 12]) {
                return PianoChord(rootPitchClass: root, quality: .minor)
            }
        }
        return nil
    }
}

extension Int {
    var noteName: String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return "\(names[positiveModulo(12)])\(self / 12 - 1)"
    }

    var solfegeName: String {
        let names = ["Do", "Do♯", "Re", "Re♯", "Mi", "Fa", "Fa♯", "Sol", "Sol♯", "La", "La♯", "Si"]
        return "\(names[positiveModulo(12)])\(self / 12 - 1)"
    }

    var isBlackPianoKey: Bool {
        [1, 3, 6, 8, 10].contains(positiveModulo(12))
    }

    nonisolated func positiveModulo(_ divisor: Int) -> Int {
        let remainder = self % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }
}

extension Comparable {
    nonisolated func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
