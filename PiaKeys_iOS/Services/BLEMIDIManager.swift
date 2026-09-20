import Combine
import CoreBluetooth
import CoreMIDI
import Foundation
import OSLog

final class BLEMIDIManager: NSObject, ObservableObject {
    static let midiServiceUUID = CBUUID(string: "03B80E5A-EDE8-4B33-A751-6CE34EC4C700")
    static let midiCharacteristicUUID = CBUUID(string: "7772E5DB-3868-4112-A1A9-F2669D106BF3")

    private static let logger = Logger(subsystem: "dunghn2201.PiaKeys-iOS", category: "BLEMIDI")

    @Published private(set) var devices: [MIDIDevice] = []
    @Published private(set) var status: MIDIConnectionStatus = .idle {
        didSet {
#if DEBUG
            let message = "\(Date())\n\(status)\ncharacteristic=\(String(describing: midiCharacteristic))\nperipheral=\(String(describing: connectedPeripheral))\n"
            if let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                try? message.write(to: directory.appendingPathComponent("ble-diagnostic.txt"), atomically: true, encoding: .utf8)
            }
#endif
        }
    }
    @Published private(set) var compatibilityScanActive = false

    private var centralManager: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var midiCharacteristic: CBCharacteristic?
    private var coreMIDIPeripheralID: UUID?
    private var scanRequested = false
    private var scanStopWorkItem: DispatchWorkItem?
    private var compatibilityScanWorkItem: DispatchWorkItem?
    private var connectionTimeoutWorkItem: DispatchWorkItem?
    private var coreMIDIRegistrationWorkItems: [DispatchWorkItem] = []

    override init() {
        super.init()
        centralManager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
    }

    var canSendNotes: Bool {
        guard status.canSend else { return false }
        if coreMIDIPeripheralID != nil { return true }
        guard let midiCharacteristic else { return false }
        return midiCharacteristic.properties.contains(.write) ||
            midiCharacteristic.properties.contains(.writeWithoutResponse)
    }

    var canSendDirectNotes: Bool {
        guard status.canSend, coreMIDIPeripheralID == nil,
              connectedPeripheral != nil, let midiCharacteristic else { return false }
        return midiCharacteristic.properties.contains(.write) ||
            midiCharacteristic.properties.contains(.writeWithoutResponse)
    }

    var connectedDeviceName: String? {
        guard case let .connected(name, _) = status else { return nil }
        return name
    }

    func startScan() {
        scanRequested = true
        switch centralManager.state {
        case .poweredOn:
            beginScan()
        case .unknown, .resetting:
            // Preserve the user's tap while CoreBluetooth starts or while the
            // system Bluetooth permission sheet is being answered.
            status = .preparingBluetooth
        default:
            scanRequested = false
            status = bluetoothUnavailableStatus
        }
    }

    func stopScan() {
        scanRequested = false
        stopScanHardware()
        if status.isScanning { status = .idle }
    }

    func connect(to id: UUID) {
        guard let peripheral = peripherals[id] else {
            status = .failed("The selected piano is no longer available. Scan again.")
            return
        }

        guard peripheral.state != .disconnecting,
              connectedPeripheral?.identifier != peripheral.identifier,
              coreMIDIPeripheralID != peripheral.identifier else { return }
        scanRequested = false
        stopScanHardware()
        cancelConnectionTimeout()
        cancelCoreMIDIRegistrationChecks()
        if let coreMIDIPeripheralID {
            disconnectCoreMIDI(peripheralID: coreMIDIPeripheralID)
            self.coreMIDIPeripheralID = nil
        }
        if let previous = connectedPeripheral {
            centralManager.cancelPeripheralConnection(previous)
        }
        connectedPeripheral = peripheral
        midiCharacteristic = nil
        peripheral.delegate = self
        let name = displayName(for: peripheral)
        status = .connecting(name)
        Self.logger.info("Connecting to BLE peripheral \(name, privacy: .public)")
        centralManager.connect(
            peripheral,
            options: [
                CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
                CBConnectPeripheralOptionNotifyOnNotificationKey: true
            ]
        )
        scheduleConnectionTimeout(for: peripheral)
    }

    func disconnect() {
        scanRequested = false
        stopScanHardware()
        cancelConnectionTimeout()
        cancelCoreMIDIRegistrationChecks()
        midiCharacteristic = nil

        if let coreMIDIPeripheralID {
            disconnectCoreMIDI(peripheralID: coreMIDIPeripheralID)
            self.coreMIDIPeripheralID = nil
            connectedPeripheral = nil
            status = .idle
            return
        }

        guard let peripheral = connectedPeripheral else {
            status = .idle
            return
        }
        connectedPeripheral = nil
        centralManager.cancelPeripheralConnection(peripheral)
        status = .idle
    }

    func sendNoteOn(_ noteNumber: Int, velocity: Int, channel: Int = 0) {
        writeMIDI(
            status: 0x90 | UInt8(channel.clamped(to: 0...15)),
            note: noteNumber,
            velocity: velocity
        )
    }

    func sendNoteOff(_ noteNumber: Int, channel: Int = 0) {
        writeMIDI(
            status: 0x80 | UInt8(channel.clamped(to: 0...15)),
            note: noteNumber,
            velocity: 0
        )
    }

    private func beginScan() {
        guard scanRequested, centralManager.state == .poweredOn else { return }
        stopScanHardware()
        cancelConnectionTimeout()
        cancelCoreMIDIRegistrationChecks()

        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        if let coreMIDIPeripheralID {
            disconnectCoreMIDI(peripheralID: coreMIDIPeripheralID)
            self.coreMIDIPeripheralID = nil
        }
        connectedPeripheral = nil
        midiCharacteristic = nil
        devices = []
        peripherals = [:]
        compatibilityScanActive = false
        status = .scanning

        // Include BLE MIDI peripherals that iOS already knows are connected.
        for peripheral in centralManager.retrieveConnectedPeripherals(withServices: [Self.midiServiceUUID]) {
            peripherals[peripheral.identifier] = peripheral
            upsertDevice(
                id: peripheral.identifier,
                name: displayName(for: peripheral),
                rssi: 0,
                advertisesMIDI: true
            )
        }

        centralManager.scanForPeripherals(
            withServices: [Self.midiServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        Self.logger.info("Started filtered BLE MIDI scan")

        // Some keyboards expose the MIDI service only after connection and omit
        // it from advertising. Fall back to named nearby BLE peripherals so the
        // user can still select the piano; service discovery validates it later.
        let compatibilityWork = DispatchWorkItem { [weak self] in
            guard let self,
                  self.scanRequested,
                  self.status == .scanning,
                  self.devices.isEmpty else { return }
            self.centralManager.stopScan()
            self.compatibilityScanActive = true
            self.centralManager.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
            Self.logger.info("No advertised MIDI service found; started compatibility BLE scan")
        }
        compatibilityScanWorkItem = compatibilityWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: compatibilityWork)

        let stopWork = DispatchWorkItem { [weak self] in self?.stopScan() }
        scanStopWorkItem = stopWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: stopWork)
    }

    private func stopScanHardware() {
        centralManager?.stopScan()
        scanStopWorkItem?.cancel()
        scanStopWorkItem = nil
        compatibilityScanWorkItem?.cancel()
        compatibilityScanWorkItem = nil
        compatibilityScanActive = false
    }

    private func scheduleConnectionTimeout(for peripheral: CBPeripheral) {
        let work = DispatchWorkItem { [weak self, weak peripheral] in
            guard let self,
                  let peripheral,
                  self.connectedPeripheral?.identifier == peripheral.identifier,
                  !self.status.isConnected else { return }
            self.fail("Connection to \(self.displayName(for: peripheral)) timed out.", cancel: peripheral)
        }
        connectionTimeoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
    }

    private func cancelConnectionTimeout() {
        connectionTimeoutWorkItem?.cancel()
        connectionTimeoutWorkItem = nil
    }

    private func cancelCoreMIDIRegistrationChecks() {
        coreMIDIRegistrationWorkItems.forEach { $0.cancel() }
        coreMIDIRegistrationWorkItems.removeAll()
    }

    private func fail(_ message: String, cancel peripheral: CBPeripheral? = nil) {
        cancelConnectionTimeout()
        cancelCoreMIDIRegistrationChecks()
        if let coreMIDIPeripheralID {
            disconnectCoreMIDI(peripheralID: coreMIDIPeripheralID)
            self.coreMIDIPeripheralID = nil
        }
        status = .failed(message)
        Self.logger.error("\(message, privacy: .public)")
        if let peripheral {
            connectedPeripheral = nil
            midiCharacteristic = nil
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    /// Transfers the active CoreBluetooth connection to Apple's BLE MIDI driver.
    ///
    /// Core MIDI owns notification subscription after this handoff. Calling
    /// `setNotifyValue` from the app can fail with `attributeNotFound` on valid
    /// BLE MIDI peripherals because their CCCD is managed by the system driver.
    private func activateCoreMIDI(for peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        let result = MIDIBluetoothDriverActivateAllConnections()
        guard result == noErr else {
            if characteristic.supportsMIDIWrite {
                activateDirectOutput(for: peripheral, characteristic: characteristic)
                Self.logger.error("Core MIDI handoff failed with \(result); using direct BLE MIDI output")
                return
            }
            fail(
                "iOS could not register this BLE MIDI piano with Core MIDI (error \(result)). Disconnect it from other MIDI apps, then try again.",
                cancel: peripheral
            )
            return
        }

        midiCharacteristic = characteristic
        let name = displayName(for: peripheral)
        status = .enablingNotifications(name)
        scheduleCoreMIDIRegistrationChecks(for: peripheral, characteristic: characteristic, name: name)
        Self.logger.info("Waiting for Core MIDI to register destination for \(name, privacy: .public)")
    }

    /// Core MIDI claims BLE links asynchronously. Keep CoreBluetooth alive until
    /// the matching output endpoint actually exists; otherwise cancelling here
    /// can leave the app with an input source but no usable piano destination.
    private func scheduleCoreMIDIRegistrationChecks(
        for peripheral: CBPeripheral,
        characteristic: CBCharacteristic,
        name: String
    ) {
        cancelCoreMIDIRegistrationChecks()
        let delays: [TimeInterval] = [0.1, 0.3, 0.75, 1.5, 2.5]
        for (index, delay) in delays.enumerated() {
            let work = DispatchWorkItem { [weak self, weak peripheral] in
                guard let self, let peripheral,
                      self.connectedPeripheral?.identifier == peripheral.identifier else { return }
                if self.hasCoreMIDIDestination(matching: name) {
                    self.finishCoreMIDIHandoff(for: peripheral, name: name)
                } else if index == delays.indices.last {
                    if characteristic.supportsMIDIWrite {
                        self.activateDirectOutput(for: peripheral, characteristic: characteristic)
                        Self.logger.notice("Core MIDI destination did not appear; using direct BLE MIDI output")
                    } else {
                        self.fail("iOS registered no MIDI output for this piano.", cancel: peripheral)
                    }
                }
            }
            coreMIDIRegistrationWorkItems.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func finishCoreMIDIHandoff(for peripheral: CBPeripheral, name: String) {
        cancelCoreMIDIRegistrationChecks()
        cancelConnectionTimeout()
        coreMIDIPeripheralID = peripheral.identifier
        status = .connected(name, canSend: true)
        Self.logger.info("BLE MIDI connection handed to a confirmed Core MIDI destination")

        connectedPeripheral = nil
        midiCharacteristic = nil
        peripheral.delegate = nil
        centralManager.cancelPeripheralConnection(peripheral)
    }

    private func hasCoreMIDIDestination(matching peripheralName: String) -> Bool {
        let candidates = [peripheralName, "BLE MIDI", "Bluetooth MIDI"]
            .map(Self.normalizedMIDIName)
            .filter { !$0.isEmpty }
        return (0..<MIDIGetNumberOfDestinations()).contains { index in
            let endpoint = MIDIGetDestination(index)
            guard endpoint != 0 else { return false }
            var value: Unmanaged<CFString>?
            guard MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &value) == noErr ||
                    MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &value) == noErr,
                  let value else { return false }
            let endpointName = Self.normalizedMIDIName(value.takeRetainedValue() as String)
            return candidates.contains { endpointName == $0 || endpointName.contains($0) || $0.contains(endpointName) }
        }
    }

    private static func normalizedMIDIName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Keeps the CoreBluetooth link for MIDI output when the peripheral does
    /// not expose a notification descriptor or Core MIDI cannot claim it.
    private func activateDirectOutput(for peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        guard characteristic.supportsMIDIWrite else {
            fail("The BLE MIDI characteristic cannot receive MIDI output.", cancel: peripheral)
            return
        }
        midiCharacteristic = characteristic
        cancelCoreMIDIRegistrationChecks()
        cancelConnectionTimeout()
        status = .connected(displayName(for: peripheral), canSend: true)
        Self.logger.info("BLE MIDI output is using the direct CoreBluetooth fallback")
    }

    private func disconnectCoreMIDI(peripheralID: UUID) {
        let result = MIDIBluetoothDriverDisconnect(peripheralID.uuidString as CFString)
        guard result == noErr else {
            Self.logger.error("Could not disconnect BLE MIDI driver for \(peripheralID.uuidString, privacy: .public): \(result)")
            return
        }
        Self.logger.info("BLE MIDI driver disconnected")
    }

    private var bluetoothUnavailableStatus: MIDIConnectionStatus {
        switch centralManager.state {
        case .unauthorized: .unavailable("Allow Bluetooth access in Settings → PiaKeys, then scan again.")
        case .unsupported: .unavailable("Bluetooth Low Energy is not supported on this device.")
        case .poweredOff: .unavailable("Turn on Bluetooth to scan for MIDI pianos.")
        case .resetting: .unavailable("Bluetooth is restarting. Please try again shortly.")
        default: .unavailable("Bluetooth is not ready yet.")
        }
    }

    private func displayName(for peripheral: CBPeripheral, advertisedName: String? = nil) -> String {
        let trimmedAdvertisedName = advertisedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPeripheralName = peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return [trimmedAdvertisedName, trimmedPeripheralName]
            .compactMap { $0 }
            .first(where: { !$0.isEmpty }) ?? "Unnamed BLE device"
    }

    private func upsertDevice(id: UUID, name: String, rssi: Int, advertisesMIDI: Bool) {
        let item = MIDIDevice(
            id: id,
            name: name,
            signalStrength: rssi,
            advertisesMIDIService: advertisesMIDI
        )
        devices.removeAll { $0.id == id }
        devices.append(item)
        devices.sort {
            if $0.advertisesMIDIService != $1.advertisesMIDIService {
                return $0.advertisesMIDIService
            }
            return $0.signalStrength > $1.signalStrength
        }
    }

}

extension BLEMIDIManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Self.logger.info("Bluetooth state changed to \(central.state.rawValue)")
        if central.state == .poweredOn {
            if scanRequested {
                beginScan()
            } else if case .unavailable = status {
                status = .idle
            } else if status == .preparingBluetooth {
                status = .idle
            }
        } else if (central.state == .unknown || central.state == .resetting), scanRequested {
            status = .preparingBluetooth
        } else {
            scanRequested = false
            stopScanHardware()
            cancelConnectionTimeout()
            cancelCoreMIDIRegistrationChecks()
            connectedPeripheral = nil
            midiCharacteristic = nil
            if let coreMIDIPeripheralID {
                disconnectCoreMIDI(peripheralID: coreMIDIPeripheralID)
                self.coreMIDIPeripheralID = nil
            }
            status = bluetoothUnavailableStatus
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard scanRequested, status.isScanning else { return }
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []) +
            (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? [])
        let advertisesMIDI = serviceUUIDs.contains(Self.midiServiceUUID) || !compatibilityScanActive
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = displayName(for: peripheral, advertisedName: advertisedName)

        // Compatibility scanning is intentionally broad, but anonymous BLE
        // beacons are not actionable and would make the piano list noisy.
        guard advertisesMIDI || name != "Unnamed BLE device" else { return }
        peripherals[peripheral.identifier] = peripheral
        upsertDevice(
            id: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue,
            advertisesMIDI: advertisesMIDI
        )
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard connectedPeripheral?.identifier == peripheral.identifier else { return }
        let name = displayName(for: peripheral)
        connectedPeripheral = peripheral
        peripheral.delegate = self
        status = .discoveringServices(name)
        peripheral.discoverServices([Self.midiServiceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        guard connectedPeripheral?.identifier == peripheral.identifier else { return }
        connectedPeripheral = nil
        midiCharacteristic = nil
        fail(error?.localizedDescription ?? "Could not connect to the MIDI piano.")
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        guard connectedPeripheral?.identifier == peripheral.identifier else { return }
        cancelConnectionTimeout()
        connectedPeripheral = nil
        midiCharacteristic = nil

        if case .failed = status {
            // Keep the useful failure message produced by service discovery.
        } else if let error {
            status = .failed("Disconnected: \(error.localizedDescription)")
        } else if !status.isScanning {
            status = .idle
        }
    }
}

extension BLEMIDIManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard connectedPeripheral?.identifier == peripheral.identifier else { return }
        if let error {
            fail("Service discovery failed: \(error.localizedDescription)", cancel: peripheral)
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.midiServiceUUID }) else {
            fail("This device does not expose the standard BLE MIDI service.", cancel: peripheral)
            return
        }
        status = .discoveringServices(displayName(for: peripheral))
        peripheral.discoverCharacteristics(nil, for: service)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard connectedPeripheral?.identifier == peripheral.identifier else { return }
        if let error {
            fail("Characteristic discovery failed: \(error.localizedDescription)", cancel: peripheral)
            return
        }
        let characteristics = service.characteristics ?? []
        guard let characteristic = characteristics.first(where: { $0.uuid == Self.midiCharacteristicUUID }) else {
            fail("The BLE MIDI characteristic was not found.", cancel: peripheral)
            return
        }
        guard characteristic.supportsMIDINotifications || characteristic.supportsMIDIWrite else {
            fail("The BLE MIDI characteristic cannot receive or send MIDI.", cancel: peripheral)
            return
        }
        if characteristic.supportsMIDINotifications {
            activateCoreMIDI(for: peripheral, characteristic: characteristic)
        } else {
            activateDirectOutput(for: peripheral, characteristic: characteristic)
        }
    }
}

private extension CBCharacteristic {
    var supportsMIDINotifications: Bool {
        properties.contains(.notify) ||
            properties.contains(.indicate) ||
            properties.contains(.notifyEncryptionRequired) ||
            properties.contains(.indicateEncryptionRequired)
    }

    var supportsMIDIWrite: Bool {
        properties.contains(.write) || properties.contains(.writeWithoutResponse)
    }
}

private extension BLEMIDIManager {
    func writeMIDI(status midiStatus: UInt8, note: Int, velocity: Int) {
        guard let peripheral = connectedPeripheral, let characteristic = midiCharacteristic,
              characteristic.supportsMIDIWrite else { return }
        let timestamp = Int(ProcessInfo.processInfo.systemUptime * 1_000) & 0x1FFF
        let data = Data([
            UInt8(0x80 | ((timestamp >> 7) & 0x3F)),
            UInt8(0x80 | (timestamp & 0x7F)),
            midiStatus,
            UInt8(note.clamped(to: 0...127)),
            UInt8(velocity.clamped(to: 0...127))
        ])
        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse)
            ? .withoutResponse
            : .withResponse
        guard data.count <= peripheral.maximumWriteValueLength(for: writeType) else { return }
        peripheral.writeValue(data, for: characteristic, type: writeType)
    }
}
