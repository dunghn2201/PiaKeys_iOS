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

    init(
        id: UUID = UUID(),
        noteNumber: Int,
        velocity: Int,
        type: MIDIEventType,
        timestamp: Date = Date(),
        source: MIDIInputSource = .preview
    ) {
        self.id = id
        self.noteNumber = noteNumber.clamped(to: 0...127)
        self.velocity = velocity.clamped(to: 0...127)
        self.type = type
        self.timestamp = timestamp
        self.source = source
    }

    var noteName: String { noteNumber.noteName }
    var solfegeName: String { noteNumber.solfegeName }
}

enum MIDIInputSource: String, Sendable {
    case ble = "BLE"
    case wired = "MIDI"
    case preview = "Preview"
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
        switch self {
        case .idle: "Ready"
        case .preparingBluetooth: "Preparing"
        case .scanning: "Scanning"
        case .connecting: "Connecting"
        case .discoveringServices: "Discovering"
        case .enablingNotifications: "Subscribing"
        case .connected: "Live"
        case .unavailable: "Unavailable"
        case .failed: "Error"
        }
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

    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }

    var canSend: Bool {
        if case let .connected(_, canSend) = self { return canSend }
        return false
    }

    var message: String {
        switch self {
        case .idle: "Ready to search for a Bluetooth MIDI piano."
        case .preparingBluetooth: "Waiting for Bluetooth permission and radio readiness…"
        case .scanning: "Searching for nearby BLE MIDI pianos…"
        case let .connecting(name): "Connecting to \(name)…"
        case let .discoveringServices(name): "Connected to \(name). Discovering MIDI services…"
        case let .enablingNotifications(name): "Enabling MIDI notifications on \(name)…"
        case let .connected(name, _): "Receiving MIDI from \(name)."
        case let .unavailable(message), let .failed(message): message
        }
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

enum SongHand: Sendable {
    case left
    case right
}

struct SongNote: Identifiable, Hashable, Sendable {
    let id = UUID()
    let startMilliseconds: Int64
    let durationMilliseconds: Int64
    let noteNumber: Int
    let velocity: Int
    let hand: SongHand
}

struct PracticeSong: Identifiable, Hashable, Sendable {
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

    func positiveModulo(_ divisor: Int) -> Int {
        let remainder = self % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
