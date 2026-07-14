import Combine
import CoreMIDI
import Foundation

struct CoreMIDIPort: Identifiable, Hashable {
    let id: MIDIEndpointRef
    let name: String
}

final class CoreMIDIManager: ObservableObject {
    @Published private(set) var sources: [CoreMIDIPort] = []
    @Published private(set) var destinations: [CoreMIDIPort] = []

    var onEvents: (([MIDINoteEvent]) -> Void)?

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var outputPort = MIDIPortRef()
    private var connectedSources = Set<MIDIEndpointRef>()

    init() {
        MIDIClientCreateWithBlock("PiaKeys MIDI Client" as CFString, &client) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        MIDIInputPortCreateWithBlock(client, "PiaKeys MIDI Input" as CFString, &inputPort) { [weak self] packetList, _ in
            let bytes = Self.bytes(from: packetList)
            let events = MIDIMessageDecoder.decodeMIDIBytes(bytes)
            guard !events.isEmpty else { return }
            DispatchQueue.main.async { self?.onEvents?(events) }
        }
        MIDIOutputPortCreate(client, "PiaKeys MIDI Output" as CFString, &outputPort)
        refresh()
    }

    deinit {
        MIDIPortDispose(inputPort)
        MIDIPortDispose(outputPort)
        MIDIClientDispose(client)
    }

    var canSendNotes: Bool { !destinations.isEmpty }

    func refresh() {
        let nextSources = (0..<MIDIGetNumberOfSources()).compactMap { index -> CoreMIDIPort? in
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0 else { return nil }
            return CoreMIDIPort(id: endpoint, name: Self.displayName(for: endpoint))
        }
        let nextSourceIDs = Set(nextSources.map(\.id))
        for endpoint in connectedSources.subtracting(nextSourceIDs) {
            MIDIPortDisconnectSource(inputPort, endpoint)
        }
        for endpoint in nextSourceIDs.subtracting(connectedSources) {
            MIDIPortConnectSource(inputPort, endpoint, nil)
        }
        connectedSources = nextSourceIDs
        sources = nextSources

        destinations = (0..<MIDIGetNumberOfDestinations()).compactMap { index in
            let endpoint = MIDIGetDestination(index)
            guard endpoint != 0 else { return nil }
            return CoreMIDIPort(id: endpoint, name: Self.displayName(for: endpoint))
        }
    }

    func sendNoteOn(_ noteNumber: Int, velocity: Int, channel: Int = 0) {
        send([0x90 | UInt8(channel.clamped(to: 0...15)), UInt8(noteNumber.clamped(to: 0...127)), UInt8(velocity.clamped(to: 0...127))])
    }

    func sendNoteOff(_ noteNumber: Int, channel: Int = 0) {
        send([0x80 | UInt8(channel.clamped(to: 0...15)), UInt8(noteNumber.clamped(to: 0...127)), 0])
    }

    private func send(_ bytes: [UInt8]) {
        guard let destination = destinations.first?.id else { return }
        var packetList = MIDIPacketList()
        withUnsafeMutablePointer(to: &packetList) { listPointer in
            var packet = MIDIPacketListInit(listPointer)
            bytes.withUnsafeBufferPointer { buffer in
                packet = MIDIPacketListAdd(
                    listPointer,
                    MemoryLayout<MIDIPacketList>.size,
                    packet,
                    0,
                    bytes.count,
                    buffer.baseAddress!
                )
            }
            MIDISend(outputPort, destination, listPointer)
        }
    }

    private static func bytes(from packetList: UnsafePointer<MIDIPacketList>) -> [UInt8] {
        var output: [UInt8] = []
        var packet = packetList.pointee.packet
        for _ in 0..<packetList.pointee.numPackets {
            withUnsafeBytes(of: packet.data) { rawBuffer in
                output.append(contentsOf: rawBuffer.prefix(Int(packet.length)))
            }
            packet = MIDIPacketNext(&packet).pointee
        }
        return output
    }

    private static func displayName(for endpoint: MIDIEndpointRef) -> String {
        var value: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &value)
        return value?.takeRetainedValue() as String? ?? "MIDI device"
    }
}
