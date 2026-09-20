import Combine
import CoreMIDI
import Foundation
import OSLog

struct CoreMIDIPort: Identifiable, Hashable {
    let id: MIDIEndpointRef
    let name: String
}

final class CoreMIDIManager: ObservableObject {
    private static let logger = Logger(subsystem: "dunghn2201.PiaKeys-iOS", category: "CoreMIDI")

    @Published private(set) var sources: [CoreMIDIPort] = []
    @Published private(set) var destinations: [CoreMIDIPort] = []

    var onEvents: (([MIDINoteEvent]) -> Void)?
    var onRawPacket: ((RawMIDIPacket) -> Void)?

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var outputPort = MIDIPortRef()
    private var noteDestinations: [Int: MIDIEndpointRef] = [:]
    private var decoders: [MIDIEndpointRef: MIDIMessageDecoder.Stream] = [:]
    private var connectedSources = Set<MIDIEndpointRef>()

    init() {
        MIDIClientCreateWithBlock("PiaKeys MIDI Client" as CFString, &client) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        MIDIInputPortCreateWithBlock(client, "PiaKeys MIDI Input" as CFString, &inputPort) { [weak self] packetList, sourceContext in
            let bytes = Self.bytes(from: packetList)
            let endpoint = MIDIEndpointRef(UInt(bitPattern: sourceContext))
            DispatchQueue.main.async {
                guard let self, self.connectedSources.contains(endpoint) else { return }
                self.onRawPacket?(.init(bytes: bytes, timestamp: Date()))
                let events = self.decoders[endpoint, default: .init()].decode(
                    bytes, sourceID: String(endpoint)
                )
                if !events.isEmpty { self.onEvents?(events) }
            }
        }
        MIDIOutputPortCreate(client, "PiaKeys MIDI Output" as CFString, &outputPort)
        refresh()
    }

    deinit {
        MIDIPortDispose(inputPort)
        MIDIPortDispose(outputPort)
        MIDIClientDispose(client)
    }

    var canSendNotes: Bool { destinations.contains { !Self.isNetworkSession($0.name) } }

    func canSendNotes(to destinationName: String?) -> Bool {
        guard let destinationName else { return canSendNotes }
        return destination(named: destinationName) != nil
    }

    /// Returns the Core MIDI destination that best matches one of the names
    /// reported by the BLE scanner or iOS Bluetooth MIDI picker.
    ///
    /// The system picker may decorate a peripheral name with a suffix, so an
    /// exact string comparison is not sufficient. Never fall back to an
    /// unrelated endpoint: iOS exposes Network Session even without a piano.
    func destinationName(matching candidateNames: [String]) -> String? {
        destination(matching: candidateNames)?.name
    }

    func refresh() {
        let nextSources = (0..<MIDIGetNumberOfSources()).compactMap { index -> CoreMIDIPort? in
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0 else { return nil }
            return CoreMIDIPort(id: endpoint, name: Self.displayName(for: endpoint))
        }
        let nextSourceIDs = Set(nextSources.map(\.id))
        for endpoint in connectedSources.subtracting(nextSourceIDs) {
            MIDIPortDisconnectSource(inputPort, endpoint)
            decoders.removeValue(forKey: endpoint)
        }
        for endpoint in nextSourceIDs.subtracting(connectedSources) {
            MIDIPortConnectSource(inputPort, endpoint, UnsafeMutableRawPointer(bitPattern: UInt(endpoint)))
        }
        connectedSources = nextSourceIDs
        sources = nextSources

        destinations = (0..<MIDIGetNumberOfDestinations()).compactMap { index in
            let endpoint = MIDIGetDestination(index)
            guard endpoint != 0 else { return nil }
            return CoreMIDIPort(id: endpoint, name: Self.displayName(for: endpoint))
        }
        Self.logger.info(
            "Core MIDI refreshed: sources=\(self.sources.map(\.name).joined(separator: ", "), privacy: .public), destinations=\(self.destinations.map(\.name).joined(separator: ", "), privacy: .public)"
        )
        writeDiagnosticSnapshot(event: "refresh")
    }

    func sendNoteOn(
        _ noteNumber: Int,
        velocity: Int,
        channel: Int = 0,
        destinationName: String? = nil
    ) {
        let key = channel.clamped(to: 0...15) * 128 + noteNumber.clamped(to: 0...127)
        let destination = noteDestinations[key] ?? destination(named: destinationName)
        guard let destination else {
            Self.logger.error("Dropped note-on: no Core MIDI destination for \(destinationName ?? "<default>", privacy: .public)")
            return
        }
        noteDestinations[key] = destination
        send([0x90 | UInt8(channel.clamped(to: 0...15)), UInt8(noteNumber.clamped(to: 0...127)), UInt8(velocity.clamped(to: 0...127))], to: destination)
    }

    func sendNoteOff(_ noteNumber: Int, channel: Int = 0) {
        let key = channel.clamped(to: 0...15) * 128 + noteNumber.clamped(to: 0...127)
        guard let destination = noteDestinations.removeValue(forKey: key) else { return }
        send([0x80 | UInt8(channel.clamped(to: 0...15)), UInt8(noteNumber.clamped(to: 0...127)), 0], to: destination)
    }

    private func send(_ bytes: [UInt8], to destination: MIDIEndpointRef) {
        guard outputPort != 0, destinations.contains(where: { $0.id == destination }) else { return }
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
            let status = MIDISend(outputPort, destination, listPointer)
            writeDiagnosticSnapshot(event: "send endpoint=\(destination) bytes=\(bytes) status=\(status)")
            if status != noErr {
                Self.logger.error("MIDISend failed for \(destination, privacy: .public): \(status)")
            } else {
                Self.logger.debug("MIDISend succeeded for \(destination, privacy: .public)")
            }
        }
    }

    private func destination(named name: String?) -> MIDIEndpointRef? {
        guard let name else { return destinations.first(where: { !Self.isNetworkSession($0.name) })?.id }
        return destination(matching: [name])?.id
    }

    /// Debug-only snapshot permits physical-device investigation without
    /// attaching a debugger, which interrupts the active Bluetooth session.
    private func writeDiagnosticSnapshot(event: String) {
#if DEBUG
        func describe(_ port: CoreMIDIPort) -> [String: Any] {
            var entity = MIDIEntityRef()
            var device = MIDIDeviceRef()
            MIDIEndpointGetEntity(port.id, &entity)
            MIDIEntityGetDevice(entity, &device)
            var properties: Unmanaged<CFPropertyList>?
            MIDIObjectGetProperties(device, &properties, true)
            return ["id": port.id, "name": port.name,
                    "device": String(describing: properties?.takeRetainedValue())]
        }
        let snapshot: [String: Any] = [
            "time": Date().description, "event": event,
            "sources": sources.map { describe($0) },
            "destinations": destinations.map { describe($0) }
        ]
        if let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys]),
           let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? data.write(to: directory.appendingPathComponent("midi-diagnostic.json"), options: .atomic)
        }
#endif
    }

    private func destination(matching candidateNames: [String]) -> CoreMIDIPort? {
        let candidates = candidateNames
            .map(Self.normalizedName)
            .filter { !$0.isEmpty }
        if let exactMatch = destinations.first(where: { destination in
            candidates.contains(Self.normalizedName(destination.name))
        }) {
            return exactMatch
        }
        let decoratedMatches = destinations.filter { destination in
            let destinationName = Self.normalizedName(destination.name)
            guard !destinationName.isEmpty else { return false }
            return candidates.contains { candidate in
                destinationName.contains(candidate) || candidate.contains(destinationName)
            }
        }
        return decoratedMatches.count == 1 ? decoratedMatches[0] : nil
    }

    private nonisolated static func normalizedName(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func isNetworkSession(_ value: String) -> Bool {
        normalizedName(value).replacingOccurrences(of: " ", with: "").hasPrefix("networksession")
    }

    /// Walks the original variable-length allocation, never a copied MIDIPacket.
    /// The callback owns this memory, so copy payload bytes before returning.
    nonisolated static func bytes(from packetList: UnsafePointer<MIDIPacketList>) -> [UInt8] {
        var output: [UInt8] = []
        let listBytes = UnsafeRawPointer(packetList)
        var packet = listBytes.advanced(by: MemoryLayout<MIDIPacketList>.offset(of: \.packet)!)
            .assumingMemoryBound(to: MIDIPacket.self)
        let dataOffset = MemoryLayout<MIDIPacket>.offset(of: \.data)!
        for index in 0..<packetList.pointee.numPackets {
            let data = UnsafeRawPointer(packet).advanced(by: dataOffset)
                .assumingMemoryBound(to: UInt8.self)
            output.append(contentsOf: UnsafeBufferPointer(start: data, count: Int(packet.pointee.length)))
            if index + 1 < packetList.pointee.numPackets {
                packet = UnsafePointer(MIDIPacketNext(packet))
            }
        }
        return output
    }

    private static func displayName(for endpoint: MIDIEndpointRef) -> String {
        var value: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &value)
        return value?.takeRetainedValue() as String? ?? "MIDI device"
    }
}
