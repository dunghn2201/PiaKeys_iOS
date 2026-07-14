import Foundation

enum MIDIMessageDecoder {
    static func decodeBLEPacket(
        _ bytes: [UInt8],
        timestamp: Date = Date(),
        source: MIDIInputSource = .ble
    ) -> [MIDINoteEvent] {
        guard bytes.count >= 3, (0x80...0xBF).contains(bytes[0]) else {
            return decodeMIDIBytes(bytes, timestamp: timestamp, source: source)
        }

        var events: [MIDINoteEvent] = []
        var index = 1
        var runningStatus: UInt8?

        while index < bytes.count {
            // Every BLE MIDI event starts with a timestamp-low byte. Consume it
            // before interpreting the following byte as status or running data.
            if (0x80...0xBF).contains(bytes[index]) {
                index += 1
            }
            guard index < bytes.count else { break }

            let statusOrData = bytes[index]
            let status: UInt8
            if (0x80...0xEF).contains(statusOrData) {
                status = statusOrData
                runningStatus = status
                index += 1
            } else if let previous = runningStatus {
                status = previous
            } else {
                index += 1
                continue
            }

            let command = status & 0xF0
            let dataLength = (command == 0xC0 || command == 0xD0) ? 1 : 2
            guard index + dataLength <= bytes.count else { break }

            if (command == 0x80 || command == 0x90), dataLength == 2 {
                let note = Int(bytes[index])
                let velocity = Int(bytes[index + 1])
                if note <= 127, velocity <= 127 {
                    events.append(MIDINoteEvent(
                        noteNumber: note,
                        velocity: velocity,
                        type: command == 0x80 || velocity == 0 ? .noteOff : .noteOn,
                        timestamp: timestamp,
                        source: source
                    ))
                    index += 2
                    continue
                }
            }
            index += max(1, dataLength)
        }
        return events
    }

    static func decodeMIDIBytes(
        _ bytes: [UInt8],
        timestamp: Date = Date(),
        source: MIDIInputSource = .wired
    ) -> [MIDINoteEvent] {
        var events: [MIDINoteEvent] = []
        var index = 0
        var runningStatus: UInt8?

        while index < bytes.count {
            let statusOrData = bytes[index]
            let status: UInt8
            if (0x80...0xEF).contains(statusOrData) {
                status = statusOrData
                runningStatus = status
                index += 1
            } else if let previous = runningStatus {
                status = previous
            } else {
                index += 1
                continue
            }

            let command = status & 0xF0
            let dataLength = (command == 0xC0 || command == 0xD0) ? 1 : 2
            guard index + dataLength <= bytes.count else { break }

            if (command == 0x80 || command == 0x90), dataLength == 2 {
                let note = Int(bytes[index])
                let velocity = Int(bytes[index + 1])
                if note <= 127, velocity <= 127 {
                    events.append(MIDINoteEvent(
                        noteNumber: note,
                        velocity: velocity,
                        type: command == 0x80 || velocity == 0 ? .noteOff : .noteOn,
                        timestamp: timestamp,
                        source: source
                    ))
                }
            }
            index += dataLength
        }
        return events
    }
}
