import Foundation

/// Decodes note messages, discarding other MIDI messages without losing byte alignment.
enum MIDIMessageDecoder {
    /// BLE timestamps precede status bytes and can use every value in 0x80...0xFF.
    /// Running status is scoped to a BLE packet; SysEx continuation data is ignored.
    static func decodeBLEPacket(
        _ bytes: [UInt8],
        timestamp: Date = Date(),
        source: MIDIInputSource = .ble
    ) -> [MIDINoteEvent] {
        guard let header = bytes.first, header & 0x80 != 0 else { return [] }
        var midiBytes: [UInt8] = []
        var followsTimestamp = false
        for byte in bytes.dropFirst() {
            if byte & 0x80 != 0 && !followsTimestamp {
                followsTimestamp = true
            } else {
                midiBytes.append(byte)
                followsTimestamp = false
            }
        }
        return decodeMIDIBytes(midiBytes, timestamp: timestamp, source: source)
    }

    static func decodeMIDIBytes(
        _ bytes: [UInt8],
        timestamp: Date = Date(),
        source: MIDIInputSource = .wired
    ) -> [MIDINoteEvent] {
        var stream = Stream()
        return stream.decode(bytes, timestamp: timestamp, source: source)
    }

    /// One instance per input endpoint. Retains partial messages and running status
    /// across callbacks. System real-time bytes never consume a message data slot.
    struct Stream {
        private var status: UInt8?
        private var data: [UInt8] = []

        mutating func decode(
            _ bytes: [UInt8],
            timestamp: Date = Date(),
            source: MIDIInputSource = .wired,
            sourceID: String? = nil
        ) -> [MIDINoteEvent] {
            var events: [MIDINoteEvent] = []
            for byte in bytes {
                if byte >= 0xF8 { continue }
                if byte >= 0x80 {
                    data.removeAll(keepingCapacity: true)
                    // System common and SysEx cancel channel running status.
                    status = byte < 0xF0 ? byte : nil
                    continue
                }
                guard let status else { continue }
                data.append(byte)
                let command = status & 0xF0
                let length = command == 0xC0 || command == 0xD0 ? 1 : 2
                guard data.count == length else { continue }
                if command == 0x80 || command == 0x90 {
                    events.append(MIDINoteEvent(
                        noteNumber: Int(data[0]),
                        velocity: Int(data[1]),
                        type: command == 0x80 || data[1] == 0 ? .noteOff : .noteOn,
                        timestamp: timestamp,
                        source: source,
                        channel: Int(status & 0x0F),
                        sourceID: sourceID
                    ))
                }
                data.removeAll(keepingCapacity: true)
            }
            return events
        }
    }
}
