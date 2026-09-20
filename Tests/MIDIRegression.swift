import Foundation
import CoreMIDI

@main
struct MIDIRegression {
    static func main() throws {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            assertions += 1
        }
        for low in UInt8(0x80)...UInt8(0xFF) {
            let notes = MIDIMessageDecoder.decodeBLEPacket([0x80, low, 0x92, 60, 100])
            check(notes.count == 1 && notes[0].noteNumber == 60 && notes[0].channel == 2, "BLE timestamp \(low)")
        }
        let ble = MIDIMessageDecoder.decodeBLEPacket([0x80, 0xC0, 0x90, 60, 100, 64, 90, 0xC1, 0x80, 60, 0])
        check(ble.map(\.noteNumber) == [60, 64, 60], "BLE running status")
        check(ble.last?.type == .noteOff, "BLE note-off")
        check(MIDIMessageDecoder.decodeBLEPacket([0, 0x90, 60, 100]).isEmpty, "Invalid BLE header")
        var stream = MIDIMessageDecoder.Stream()
        check(stream.decode([0x91, 60]).isEmpty, "Partial message")
        let continued = stream.decode([0xF8, 100, 64, 0], sourceID: "piano")
        check(continued.count == 2 && continued[0].sourceID == "piano", "Continuation with real-time")
        check(continued[1].type == .noteOff, "Zero velocity is note-off")
        check(stream.decode([0xF0, 1, 2, 0xF7, 60, 100]).isEmpty, "SysEx cancels running status")
        check(stream.decode([0x90, 60, 0x80, 60, 0]).count == 1, "Interrupted malformed message")

        // More than one packet, including a payload larger than MIDIPacket.data's
        // imported tuple. ASan catches traversal outside the original allocation.
        let allocation = UnsafeMutableRawPointer.allocate(byteCount: 4096, alignment: 16)
        defer { allocation.deallocate() }
        allocation.initializeMemory(as: UInt8.self, repeating: 0, count: 4096)
        let list = allocation.assumingMemoryBound(to: MIDIPacketList.self)
        var packet = MIDIPacketListInit(list)
        var expected: [UInt8] = []
        for payload in [[UInt8](repeating: 0x3C, count: 300), [0x90, 64, 100], [0x80, 64, 0]] {
            expected += payload
            packet = payload.withUnsafeBufferPointer {
                MIDIPacketListAdd(list, 4096, packet, 0, payload.count, $0.baseAddress!)
            }
        }
        check(CoreMIDIManager.bytes(from: UnsafePointer(list)) == expected, "Variable-length packet traversal")
        list.pointee.numPackets = 0
        check(CoreMIDIManager.bytes(from: UnsafePointer(list)).isEmpty, "Empty packet list")

        func midi(_ tracks: [[UInt8]], division: UInt16 = 96) -> Data {
            var bytes: [UInt8] = [0x4D,0x54,0x68,0x64,0,0,0,6,0,tracks.count == 1 ? 0 : 1,0,UInt8(tracks.count),UInt8(division >> 8),UInt8(division & 255)]
            for track in tracks {
                let count = UInt32(track.count)
                bytes += [0x4D,0x54,0x72,0x6B,UInt8((count >> 24) & 255),UInt8((count >> 16) & 255),UInt8((count >> 8) & 255),UInt8(count & 255)]
                bytes += track
            }
            return Data(bytes)
        }
        let end: [UInt8] = [0,0xFF,0x2F,0]
        let track: [UInt8] = [0,0x90,60,100,96,0xFF,0x51,3,0x0F,0x42,0x40,96,0x80,60,0] + end
        let song = try StandardMIDIFileParser.parse(data: midi([track]), fallbackTitle: "Tempo")
        check(song.tempo == 120, "Default tempo before first event")
        check(song.notes[0].durationMilliseconds == 1500, "Late tempo must not apply at tick zero")
        let short = try StandardMIDIFileParser.parse(data: midi([[0,0x90,60,100,12,0x80,60,0] + end]), fallbackTitle: "Short")
        check(short.notes[0].durationMilliseconds == 63, "Keep original duration, rounded to ms")
        let separateTracks = try StandardMIDIFileParser.parse(data: midi([
            [0,0x90,60,100,96,0x80,60,0] + end,
            [48,0x90,60,90,96,0x80,60,0] + end
        ]), fallbackTitle: "Overlapping tracks")
        check(separateTracks.notes.map(\.durationMilliseconds) == [500,500], "Tracks must not close each other's notes")
        func rejects(_ data: Data) -> Bool {
            do { _ = try StandardMIDIFileParser.parse(data: data, fallbackTitle: "Bad"); return false }
            catch { return true }
        }
        check(rejects(midi([track], division: 0)), "Reject zero PPQ")
        check(rejects(midi([[0,0x90,60],[100] + end])), "Reject event crossing track boundary")
        check(rejects(midi([[0,0x90,0xFF,100] + end])), "Reject invalid note data")
        check(rejects(midi([[0,0xFF,0x51,3,0,0,0] + end])), "Reject zero tempo")
        check(song.notes[0].remainingDuration(at: 1000) == 500, "Resume remaining duration")
        check(song.notes[0].remainingDuration(at: 1500) == 0, "Do not replay expired note")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SongLibraryStore(directory: directory)
        let initialLibrary = try store.load()
        check(initialLibrary.first?.id == PracticeSong.demo.id, "Empty library has demo")
        var storedSong = song
        storedSong.scoreURL = URL(fileURLWithPath: "/old-container/Scores/example.xml")
        try store.save([storedSong])
        let loaded = try store.load()
        check(loaded.first?.notes == song.notes, "Library notes round-trip")
        check(loaded.first?.scoreURL == directory.appendingPathComponent("Scores/example.xml"), "Rebase score path")
        try Data("broken".utf8).write(to: directory.appendingPathComponent("library.json"))
        do { _ = try store.load(); preconditionFailure("Corrupt library accepted") } catch { assertions += 1 }
        do { try store.save([song]); preconditionFailure("Corrupt library overwritten") } catch { assertions += 1 }
        let preserved = try String(contentsOf: directory.appendingPathComponent("library.json"), encoding: .utf8)
        check(preserved == "broken", "Preserve library on failed restore")
        print("PASS: \(assertions) MIDI, memory, timing and persistence regression checks")
    }
}
