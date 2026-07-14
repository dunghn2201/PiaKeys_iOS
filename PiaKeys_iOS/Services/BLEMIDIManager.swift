import Combine
import CoreBluetooth
import Foundation
import OSLog

final class BLEMIDIManager: NSObject, ObservableObject {
    static let midiServiceUUID = CBUUID(string: "03B80E5A-EDE8-4B33-A751-6CE34EC4C700")
    static let midiCharacteristicUUID = CBUUID(string: "7772E5DB-3868-4112-A1A9-F2669D106BF3")

    private static let logger = Logger(subsystem: "dunghn2201.PiaKeys-iOS", category: "BLEMIDI")

    @Published private(set) var devices: [MIDIDevice] = []
    @Published private(set) var status: MIDIConnectionStatus = .idle
    @Published private(set) var rawPackets: [RawMIDIPacket] = []
    @Published private(set) var compatibilityScanActive = false

    var onEvents: (([MIDINoteEvent]) -> Void)?

    private var centralManager: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var midiCharacteristic: CBCharacteristic?
    private var scanRequested = false
    private var intentionallyDisconnecting = false
    private var scanStopWorkItem: DispatchWorkItem?
    private var compatibilityScanWorkItem: DispatchWorkItem?
    private var connectionTimeoutWorkItem: DispatchWorkItem?

    override init() {
        super.init()
        centralManager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
    }

    var canSendNotes: Bool {
        guard status.canSend, let midiCharacteristic else { return false }
        return midiCharacteristic.properties.contains(.write) ||
            midiCharacteristic.properties.contains(.writeWithoutResponse)
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

        scanRequested = false
        stopScanHardware()
        cancelConnectionTimeout()
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
        midiCharacteristic = nil

        guard let peripheral = connectedPeripheral else {
            status = .idle
            return
        }
        intentionallyDisconnecting = true
        connectedPeripheral = nil
        centralManager.cancelPeripheralConnection(peripheral)
        status = .idle
    }

    func sendNoteOn(_ noteNumber: Int, velocity: Int, channel: Int = 0) {
        writeMIDI(status: 0x90 | UInt8(channel.clamped(to: 0...15)), note: noteNumber, velocity: velocity)
    }

    func sendNoteOff(_ noteNumber: Int, channel: Int = 0) {
        writeMIDI(status: 0x80 | UInt8(channel.clamped(to: 0...15)), note: noteNumber, velocity: 0)
    }

    private func beginScan() {
        guard scanRequested, centralManager.state == .poweredOn else { return }
        stopScanHardware()
        cancelConnectionTimeout()

        if let peripheral = connectedPeripheral {
            intentionallyDisconnecting = true
            centralManager.cancelPeripheralConnection(peripheral)
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

    private func fail(_ message: String, cancel peripheral: CBPeripheral? = nil) {
        cancelConnectionTimeout()
        status = .failed(message)
        Self.logger.error("\(message, privacy: .public)")
        if let peripheral { centralManager.cancelPeripheralConnection(peripheral) }
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

    private func writeMIDI(status midiStatus: UInt8, note: Int, velocity: Int) {
        guard let peripheral = connectedPeripheral, let characteristic = midiCharacteristic else { return }
        let timestamp = Int(ProcessInfo.processInfo.systemUptime * 1_000) & 0x1FFF
        let header = UInt8(0x80 | ((timestamp >> 7) & 0x3F))
        let low = UInt8(0x80 | (timestamp & 0x7F))
        let data = Data([
            header,
            low,
            midiStatus,
            UInt8(note.clamped(to: 0...127)),
            UInt8(velocity.clamped(to: 0...127))
        ])
        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse)
            ? .withoutResponse
            : .withResponse
        peripheral.writeValue(data, for: characteristic, type: writeType)
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
            status = bluetoothUnavailableStatus
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
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
        connectedPeripheral = nil
        midiCharacteristic = nil
        fail(error?.localizedDescription ?? "Could not connect to the MIDI piano.")
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        cancelConnectionTimeout()
        connectedPeripheral = nil
        midiCharacteristic = nil

        if intentionallyDisconnecting {
            intentionallyDisconnecting = false
            if !status.isScanning { status = .idle }
        } else if case .failed = status {
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
        if let error {
            fail("Service discovery failed: \(error.localizedDescription)", cancel: peripheral)
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.midiServiceUUID }) else {
            fail("This device does not expose the standard BLE MIDI service.", cancel: peripheral)
            return
        }
        status = .discoveringServices(displayName(for: peripheral))
        peripheral.discoverCharacteristics([Self.midiCharacteristicUUID], for: service)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            fail("Characteristic discovery failed: \(error.localizedDescription)", cancel: peripheral)
            return
        }
        guard let characteristic = service.characteristics?.first(where: {
            $0.uuid == Self.midiCharacteristicUUID
        }) else {
            fail("The BLE MIDI characteristic was not found.", cancel: peripheral)
            return
        }
        guard characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) else {
            fail("The BLE MIDI characteristic does not support notifications.", cancel: peripheral)
            return
        }
        midiCharacteristic = characteristic
        status = .enablingNotifications(displayName(for: peripheral))
        peripheral.setNotifyValue(true, for: characteristic)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            fail("Could not enable MIDI notifications: \(error.localizedDescription)", cancel: peripheral)
            return
        }
        guard characteristic.isNotifying else {
            fail("The piano did not enable MIDI notifications.", cancel: peripheral)
            return
        }
        cancelConnectionTimeout()
        let supportsWrite = characteristic.properties.contains(.write) ||
            characteristic.properties.contains(.writeWithoutResponse)
        status = .connected(displayName(for: peripheral), canSend: supportsWrite)
        Self.logger.info("BLE MIDI notifications are live")
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            status = .failed("MIDI notification error: \(error.localizedDescription)")
            return
        }
        guard characteristic.uuid == Self.midiCharacteristicUUID,
              let value = characteristic.value else { return }
        let bytes = [UInt8](value)
        rawPackets.insert(.init(bytes: bytes, timestamp: Date()), at: 0)
        rawPackets = Array(rawPackets.prefix(40))
        let events = MIDIMessageDecoder.decodeBLEPacket(bytes)
        if !events.isEmpty { onEvents?(events) }
    }
}
