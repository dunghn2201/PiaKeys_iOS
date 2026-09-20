import CryptoKit
import Foundation

enum StandardMIDIFileParser {
    static func parse(data: Data, fallbackTitle: String) throws -> PracticeSong {
        var reader = MIDIReader(data: data)
        try reader.expectASCII("MThd")
        let headerLength = try reader.readInt()
        guard headerLength >= 6 else { throw MIDIParseError.invalid("Invalid MIDI header") }
        let format = try reader.readUnsignedShort()
        let trackCount = try reader.readUnsignedShort()
        let division = try reader.readUnsignedShort()
        try reader.skip(headerLength - 6)

        guard format == 0 || format == 1 else {
            throw MIDIParseError.invalid("Only MIDI format 0 and 1 are supported")
        }
        guard format != 0 || trackCount == 1 else {
            throw MIDIParseError.invalid("MIDI format 0 must contain exactly one track")
        }
        guard division > 0 else { throw MIDIParseError.invalid("MIDI time division must be positive") }
        guard trackCount > 0 else { throw MIDIParseError.invalid("MIDI file has no tracks") }
        guard division & 0x8000 == 0 else {
            throw MIDIParseError.invalid("SMPTE time division is not supported")
        }

        var tracks: [ParsedTrack] = []
        for trackIndex in 0..<trackCount {
            tracks.append(try parseTrack(reader: &reader, trackIndex: trackIndex))
        }

        let events = tracks.flatMap(\.events).sorted {
            ($0.tick, $0.trackIndex, $0.order) < ($1.tick, $1.trackIndex, $1.order)
        }
        let tempoChanges = normalizeTempoChanges(tracks.flatMap(\.tempoChanges))
        let firstTempo = tempoChanges[0].microsecondsPerQuarter
        let notes = buildNotes(
            events: events,
            tempoChanges: tempoChanges,
            ticksPerQuarter: division
        )
        guard !notes.isEmpty else {
            throw MIDIParseError.invalid("No playable piano notes were found")
        }

        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let title = fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return PracticeSong(
            id: "imported-\(digest)",
            title: title.isEmpty ? (tracks.compactMap(\.title).first ?? "Imported MIDI") : title,
            composer: "Imported MIDI",
            tempo: (60_000_000 / firstTempo).clamped(to: 24...260),
            timeSignature: tracks.compactMap(\.timeSignature).first ?? "4/4",
            notes: notes
        )
    }

    private static func parseTrack(reader fileReader: inout MIDIReader, trackIndex: Int) throws -> ParsedTrack {
        try fileReader.expectASCII("MTrk")
        let length = try fileReader.readInt()
        // A bounded reader prevents malformed events from consuming the next track.
        var reader = MIDIReader(data: try fileReader.readBytes(length))
        let end = reader.data.count
        var tick: Int64 = 0
        var runningStatus: UInt8?
        var order = 0
        var title: String?
        var timeSignature: String?
        var tempoChanges: [TempoChange] = []
        var events: [TimedEvent] = []

        while reader.position < end {
            tick += try reader.readVariableLengthQuantity()
            var status = try reader.readByte()
            if status < 0x80 {
                guard let runningStatus else {
                    throw MIDIParseError.invalid("Running status appeared before a status byte")
                }
                try reader.rewind(1)
                status = runningStatus
            } else if status < 0xF0 {
                runningStatus = status
            }

            switch status {
            case 0xFF:
                runningStatus = nil
                let type = try reader.readByte()
                let count = Int(try reader.readVariableLengthQuantity())
                let payload = try reader.readBytes(count)
                switch type {
                case 0x03:
                    if title == nil {
                        title = String(data: payload, encoding: .isoLatin1)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                case 0x51:
                    guard payload.count == 3 else { throw MIDIParseError.invalid("Invalid tempo event") }
                    let value = Int(payload[0]) << 16 | Int(payload[1]) << 8 | Int(payload[2])
                    guard value > 0 else { throw MIDIParseError.invalid("MIDI tempo must be positive") }
                    tempoChanges.append(.init(tick: tick, microsecondsPerQuarter: value))
                case 0x58:
                    guard payload.count == 4, payload[0] > 0, payload[1] <= 7 else {
                        throw MIDIParseError.invalid("Invalid time signature")
                    }
                    timeSignature = "\(payload[0])/\(1 << Int(payload[1]))"
                default:
                    break
                }
                if type == 0x2F { break }
            case 0xF0, 0xF7:
                runningStatus = nil
                try reader.skip(Int(try reader.readVariableLengthQuantity()))
            case 0x80...0xEF:
                let command = status & 0xF0
                let channel = status & 0x0F
                let data1 = try reader.readByte()
                let data2: UInt8 = command == 0xC0 || command == 0xD0 ? 0 : try reader.readByte()
                guard data1 < 0x80, data2 < 0x80 else {
                    throw MIDIParseError.invalid("Invalid MIDI data byte")
                }
                if command == 0x80 || command == 0x90 {
                    events.append(.init(
                        tick: tick,
                        trackIndex: trackIndex,
                        order: order,
                        noteNumber: Int(data1),
                        velocity: Int(data2),
                        channel: Int(channel),
                        isOn: command == 0x90 && data2 > 0
                    ))
                    order += 1
                }
            default:
                throw MIDIParseError.invalid(String(format: "Unsupported MIDI status 0x%02X", status))
            }
        }
        try reader.move(to: end)
        return ParsedTrack(
            title: title,
            timeSignature: timeSignature,
            tempoChanges: tempoChanges,
            events: events
        )
    }

    private static func buildNotes(
        events: [TimedEvent],
        tempoChanges: [TempoChange],
        ticksPerQuarter: Int
    ) -> [SongNote] {
        struct NoteKey: Hashable { let track: Int; let channel: Int; let note: Int }
        var active: [NoteKey: [TimedEvent]] = [:]
        var notes: [SongNote] = []

        for event in events where event.channel != 9 && (21...108).contains(event.noteNumber) {
            let key = NoteKey(track: event.trackIndex, channel: event.channel, note: event.noteNumber)
            if event.isOn {
                // Pair overlapping same-pitch notes FIFO within their own track/channel.
                active[key, default: []].append(event)
            } else if let started = active[key]?.first {
                notes.append(makeSongNote(
                    start: started,
                    endTick: event.tick,
                    tempoChanges: tempoChanges,
                    ticksPerQuarter: ticksPerQuarter
                ))
                active[key]?.removeFirst()
            }
        }
        return notes.sorted {
            ($0.startMilliseconds, $0.noteNumber) < ($1.startMilliseconds, $1.noteNumber)
        }
    }

    private static func makeSongNote(
        start: TimedEvent,
        endTick: Int64,
        tempoChanges: [TempoChange],
        ticksPerQuarter: Int
    ) -> SongNote {
        let startMilliseconds = tickToMilliseconds(start.tick, tempoChanges, ticksPerQuarter)
        let endMilliseconds = tickToMilliseconds(endTick, tempoChanges, ticksPerQuarter)
        // Preserve MIDI timing. The audio engine owns the acoustic release tail.
        let rawDuration = max(1, endMilliseconds - startMilliseconds)
        return SongNote(
            startMilliseconds: startMilliseconds,
            durationMilliseconds: rawDuration,
            noteNumber: start.noteNumber,
            velocity: start.velocity.clamped(to: 1...127),
            hand: start.noteNumber < 60 ? .left : .right
        )
    }

    private static func normalizeTempoChanges(
        _ changes: [TempoChange]
    ) -> [TempoChange] {
        var values: [Int64: Int] = [:]
        for change in changes.sorted(by: { $0.tick < $1.tick }) {
            values[change.tick] = change.microsecondsPerQuarter
        }
        // MIDI defaults to 120 BPM until an actual tempo event takes effect.
        values[0] = values[0] ?? 500_000
        return values.map { .init(tick: $0.key, microsecondsPerQuarter: $0.value) }
            .sorted { $0.tick < $1.tick }
    }

    private static func tickToMilliseconds(
        _ tick: Int64,
        _ tempoChanges: [TempoChange],
        _ ticksPerQuarter: Int
    ) -> Int64 {
        var elapsedMicroseconds = 0.0
        var lastTick: Int64 = 0
        var currentTempo = 500_000
        for tempo in tempoChanges where tempo.tick <= tick {
            elapsedMicroseconds += Double(tempo.tick - lastTick) * Double(currentTempo) / Double(ticksPerQuarter)
            lastTick = tempo.tick
            currentTempo = tempo.microsecondsPerQuarter
        }
        elapsedMicroseconds += Double(tick - lastTick) * Double(currentTempo) / Double(ticksPerQuarter)
        return Int64((elapsedMicroseconds / 1_000).rounded())
    }
}

private struct ParsedTrack {
    let title: String?
    let timeSignature: String?
    let tempoChanges: [TempoChange]
    let events: [TimedEvent]
}

private struct TempoChange {
    let tick: Int64
    let microsecondsPerQuarter: Int
}

private struct TimedEvent {
    let tick: Int64
    let trackIndex: Int
    let order: Int
    let noteNumber: Int
    let velocity: Int
    let channel: Int
    let isOn: Bool
}

private enum MIDIParseError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        if case let .invalid(message) = self { return message }
        return nil
    }
}

private struct MIDIReader {
    let data: Data
    var position = 0

    mutating func expectASCII(_ value: String) throws {
        let bytes = try readBytes(value.utf8.count)
        guard String(data: bytes, encoding: .ascii) == value else {
            throw MIDIParseError.invalid("Expected MIDI chunk \(value)")
        }
    }

    mutating func readInt() throws -> Int {
        let b0 = Int(try readByte())
        let b1 = Int(try readByte())
        let b2 = Int(try readByte())
        let b3 = Int(try readByte())
        return b0 << 24 | b1 << 16 | b2 << 8 | b3
    }

    mutating func readUnsignedShort() throws -> Int {
        Int(try readByte()) << 8 | Int(try readByte())
    }

    mutating func readByte() throws -> UInt8 {
        guard position < data.count else { throw MIDIParseError.invalid("Unexpected end of MIDI file") }
        defer { position += 1 }
        return data[position]
    }

    mutating func readVariableLengthQuantity() throws -> Int64 {
        var value: Int64 = 0
        for index in 0..<4 {
            let byte = try readByte()
            value = value << 7 | Int64(byte & 0x7F)
            if byte & 0x80 == 0 { return value }
            if index == 3 { throw MIDIParseError.invalid("Invalid MIDI variable-length quantity") }
        }
        return value
    }

    mutating func readBytes(_ count: Int) throws -> Data {
        guard count >= 0, position + count <= data.count else {
            throw MIDIParseError.invalid("Unexpected end of MIDI file")
        }
        defer { position += count }
        return data.subdata(in: position..<(position + count))
    }

    mutating func skip(_ count: Int) throws {
        try move(to: position + count)
    }

    mutating func rewind(_ count: Int) throws {
        try move(to: position - count)
    }

    mutating func move(to value: Int) throws {
        guard (0...data.count).contains(value) else {
            throw MIDIParseError.invalid("Unexpected end of MIDI file")
        }
        position = value
    }
}
