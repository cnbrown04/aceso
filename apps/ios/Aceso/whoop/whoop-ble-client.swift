import CoreBluetooth
import Foundation
import OSLog

// MARK: - Connection state

enum WhoopConnectionState: Equatable {
    case idle
    case scanning
    case connecting
    case connected
}

// MARK: - BLE client

/// CoreBluetooth engine for WHOOP 4.0 and 5.0.
///
/// Usage:
///   1. Set `onSamples` to receive data batches.
///   2. Call `connect()` to start scanning.
///   3. Call `disconnect()` when done.
@Observable
final class WhoopBLEClient: NSObject {

    // MARK: - Observable state

    var connectionState: WhoopConnectionState = .idle
    var liveHR: Int?
    var batteryPct: Int?
    var deviceName: String?
    /// Non-nil when a problem requires user action. Cleared on successful bond or `retry()`.
    var connectionError: String?

    // MARK: - Callbacks

    /// Called when a batch of samples is ready to persist or upload.
    var onSamples: ((WhoopSampleBatch) -> Void)?
    /// Called with raw historical data frames for deeper decoding.
    var onHistoricalFrame: (([UInt8]) -> Void)?

    // MARK: - Private state

    private let family: WhoopDeviceFamily
    private let log = Logger(subsystem: "com.aceso", category: "whoop-ble")

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var cmdChar: CBCharacteristic?
    private var seq: UInt8 = 0
    private var reassembler: WhoopReassembler
    private var pendingBatch = WhoopSampleBatch(deviceID: "", hrSamples: [], rrIntervals: [], batterySamples: [])
    private var batchFlushTimer: Timer?

    // Prevents re-entering the connect handshake on every .withResponse ACK (bond write, history
    // acks, etc.). Without this, onBonded() re-fires in a storm that stops the strap from streaming.
    private var connectHandshakeDone = false
    private var scanTimeoutWork: DispatchWorkItem?
    private var connectTimeoutWork: DispatchWorkItem?
    // Counts attempts where the WHOOP was found but didConnect never fired (filter-list rejection).
    // After 2 consecutive timeouts, connectionError is set and auto-retry stops.
    private var consecutiveConnectTimeouts = 0

    // MARK: - Characteristic references

    private var pendingNotifyChars: [CBCharacteristic] = []
    private var notifyChars: [String: CBCharacteristic] = [:]
    private var hrChar: CBCharacteristic?
    private var batteryChar: CBCharacteristic?

    // MARK: - Init

    init(family: WhoopDeviceFamily = .whoop4) {
        self.family = family
        self.reassembler = WhoopReassembler(family: family)
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Public API

    func connect() {
        guard central.state == .poweredOn else { return }
        guard connectionState == .idle else { return }

        // Reuse a system-level connection the strap already holds.
        if let existing = central.retrieveConnectedPeripherals(withServices: [CBUUID(string: family.serviceUUID)]).first {
            log.info("attaching already-connected WHOOP \(existing.identifier, privacy: .public)")
            connectionState = .connecting
            preparePeripheral(existing)
            if existing.state == .connected {
                existing.discoverServices(allServiceUUIDs())
            } else {
                central.connect(existing, options: nil)
            }
            armConnectTimeout()
            return
        }

        connectionState = .scanning
        log.info("scanning for WHOOP \(self.family.serviceUUID, privacy: .public)")
        central.scanForPeripherals(
            withServices: [CBUUID(string: family.serviceUUID)],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        armScanTimeout()
    }

    func disconnect() {
        cancelTimeouts()
        batchFlushTimer?.invalidate()
        batchFlushTimer = nil
        connectHandshakeDone = false
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        resetCharacteristics()
        reassembler.reset()
        connectionState = .idle
    }

    /// Clear the error and attempt connection again.
    func retry() {
        connectionError = nil
        consecutiveConnectTimeouts = 0
        connect()
    }

    // MARK: - Command sending

    private func send(_ command: WhoopCommand, payload: [UInt8] = [0x00],
                      writeType: CBCharacteristicWriteType = .withoutResponse) {
        guard let p = peripheral, let ch = cmdChar, p.state == .connected else { return }
        seq = seq &+ 1
        let frame = command.frame(seq: seq, payload: payload, family: family)
        p.writeValue(Data(frame), for: ch, type: writeType)
    }

    // MARK: - Bond completion

    private func onBonded() {
        // didWriteValueFor fires on EVERY .withResponse write (bond, history acks, etc.).
        // This guard ensures the handshake runs exactly once per connection.
        guard !connectHandshakeDone else { return }
        connectHandshakeDone = true
        consecutiveConnectTimeouts = 0
        connectionError = nil
        cancelTimeouts()

        log.info("bonded — syncing clock and requesting data")
        connectionState = .connected

        // On WHOOP 5.0 puffin notify chars must be subscribed post-bond
        // (the strap rejects them before encryption is established).
        if family == .whoop5 {
            for char in pendingNotifyChars where !char.isNotifying {
                peripheral?.setNotifyValue(true, for: char)
            }
            pendingNotifyChars.removeAll()
        }

        // Use .withoutResponse for all handshake commands — we don't need ACKs here, and a
        // .withResponse write would re-fire didWriteValueFor and loop back into onBonded().
        send(.setClock, payload: WhoopCommand.setClockPayload())
        send(.exitHighFreqSync, payload: [0x00])
        if family == .whoop5 {
            send(.toggleRealtimeHR, payload: [0x01])
        }
        send(.sendHistoricalData)

        batchFlushTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.flushBatch() }
        }
    }

    // MARK: - Timeouts

    private func armScanTimeout() {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.connectionState == .scanning else { return }
            self.log.warning("scan timeout — no WHOOP found after 15s; retrying")
            self.central.stopScan()
            self.connectionState = .idle
            self.connect()
        }
        scanTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
    }

    private func armConnectTimeout() {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.connectionState == .connecting else { return }
            self.consecutiveConnectTimeouts += 1
            if self.consecutiveConnectTimeouts >= 2 {
                // WHOOP is advertising but refusing the connection — its filter accept list
                // only allows devices it has previously bonded with. The user needs to put the
                // strap into pairing mode so it accepts a new bond.
                self.log.warning("WHOOP visible but refusing connections (\(self.consecutiveConnectTimeouts) attempts) — filter list rejection")
                self.connectionError = "Your WHOOP isn't accepting connections. Repeatedly tap the top of your WHOOP to enter pairing mode, then tap Retry."
                self.disconnect()
                return
            }
            self.log.warning("connect timeout — retrying (\(self.consecutiveConnectTimeouts) of 2)")
            self.disconnect()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.connect() }
        }
        connectTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)
    }

    private func cancelTimeouts() {
        scanTimeoutWork?.cancel()
        scanTimeoutWork = nil
        connectTimeoutWork?.cancel()
        connectTimeoutWork = nil
    }

    // MARK: - Frame handling

    private func handleCustomFrame(_ frame: [UInt8]) {
        // WHOOP 5.0 frames: payload starts at byte 8; rebase offsets for the shared decoder.
        let decodeTarget: [UInt8]
        switch family {
        case .whoop4: decodeTarget = frame
        case .whoop5:
            // Rewrite the 5.0 envelope into a 4.0-style frame so decodeWhoopFrame works unchanged.
            guard frame.count >= 8 else { return }
            let declaredLength = Int(frame[2]) | (Int(frame[3]) << 8)
            let payloadEnd = 8 + declaredLength - 4
            guard payloadEnd <= frame.count else { return }
            let payload = Array(frame[8..<payloadEnd])
            let innerLen = UInt16(payload.count + 4)
            let lenBytes: [UInt8] = [UInt8(innerLen & 0xFF), UInt8(innerLen >> 8)]
            let fakeCRC8 = whoopCRC8(lenBytes)
            decodeTarget = [0xAA] + lenBytes + [fakeCRC8] + payload + [0, 0, 0, 0]
        }

        let now = Int(Date().timeIntervalSince1970)
        let decoded = decodeWhoopFrame(decodeTarget)
        switch decoded {
        case .realtimeHR(let bpm, let rrMs, _):
            liveHR = bpm
            pendingBatch.hrSamples.append(WhoopHRSample(ts: now, bpm: bpm))
            for ms in rrMs {
                pendingBatch.rrIntervals.append(WhoopRRInterval(ts: now, rrMs: ms))
            }
        case .batteryLevel(let pct):
            batteryPct = Int(pct.rounded())
            pendingBatch.batterySamples.append(WhoopBatterySample(ts: now, pct: pct))
        case .historicalData(let raw):
            onHistoricalFrame?(raw)
        case .unknown:
            break
        }
    }

    private func flushBatch() {
        guard !pendingBatch.isEmpty else { return }
        let deviceID = peripheral?.identifier.uuidString ?? "unknown"
        let batch = WhoopSampleBatch(
            deviceID: deviceID,
            hrSamples: pendingBatch.hrSamples,
            rrIntervals: pendingBatch.rrIntervals,
            batterySamples: pendingBatch.batterySamples
        )
        pendingBatch = WhoopSampleBatch(deviceID: deviceID, hrSamples: [], rrIntervals: [], batterySamples: [])
        onSamples?(batch)
    }
}

// MARK: - CBCentralManagerDelegate

extension WhoopBLEClient: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            guard central.state == .poweredOn else {
                self.connectionState = .idle
                return
            }
            self.connect()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name ?? "WHOOP"
        Task { @MainActor in
            self.log.info("discovered \(name, privacy: .public) — connecting")
            self.central.stopScan()
            self.scanTimeoutWork?.cancel()
            self.scanTimeoutWork = nil
            self.connectionState = .connecting
            self.preparePeripheral(peripheral)
            self.central.connect(self.peripheral!, options: nil)
            self.armConnectTimeout()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            peripheral.discoverServices(self.allServiceUUIDs())
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            self.log.info("disconnected\(error.map { ": \($0.localizedDescription)" } ?? "")")
            self.cancelTimeouts()
            self.flushBatch()
            self.batchFlushTimer?.invalidate()
            self.batchFlushTimer = nil
            self.connectHandshakeDone = false
            self.liveHR = nil
            self.connectionState = .idle
            self.resetCharacteristics()
            self.reassembler.reset()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.connectionState == .idle, self.connectionError == nil else { return }
                self.connect()
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            self.log.error("didFailToConnect: \(error?.localizedDescription ?? "unknown", privacy: .public)")
            self.cancelTimeouts()
            self.connectHandshakeDone = false
            self.connectionState = .idle
            self.resetCharacteristics()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.connectionError == nil else { return }
                self.connect()
            }
        }
    }

    // MARK: - Private helpers

    private func preparePeripheral(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
        deviceName = p.name
    }

    private func resetCharacteristics() {
        cmdChar = nil
        pendingNotifyChars.removeAll()
        notifyChars.removeAll()
        hrChar = nil
        batteryChar = nil
    }

    private func allServiceUUIDs() -> [CBUUID] {
        [CBUUID(string: family.serviceUUID),
         CBUUID(string: WhoopDeviceFamily.heartRateServiceUUID),
         CBUUID(string: WhoopDeviceFamily.batteryServiceUUID)]
    }
}

// MARK: - CBPeripheralDelegate

extension WhoopBLEClient: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverServices error: Error?) {
        if let error {
            Task { @MainActor in
                self.log.error("service discovery failed: \(error.localizedDescription, privacy: .public)")
            }
            return
        }
        Task { @MainActor in
            for service in peripheral.services ?? [] {
                switch service.uuid {
                case CBUUID(string: self.family.serviceUUID):
                    let charUUIDs = ([self.family.commandCharUUID] + self.family.notifyCharUUIDs)
                        .map { CBUUID(string: $0) }
                    peripheral.discoverCharacteristics(charUUIDs, for: service)
                case CBUUID(string: WhoopDeviceFamily.heartRateServiceUUID):
                    peripheral.discoverCharacteristics(
                        [CBUUID(string: WhoopDeviceFamily.heartRateCharUUID)], for: service)
                case CBUUID(string: WhoopDeviceFamily.batteryServiceUUID):
                    peripheral.discoverCharacteristics(
                        [CBUUID(string: WhoopDeviceFamily.batteryCharUUID)], for: service)
                default: break
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        if let error {
            Task { @MainActor in
                self.log.error("char discovery failed for \(service.uuid): \(error.localizedDescription, privacy: .public)")
            }
            return
        }
        Task { @MainActor in
            for char in service.characteristics ?? [] {
                let uuidStr = char.uuid.uuidString.lowercased()

                if uuidStr == self.family.commandCharUUID.lowercased() {
                    self.cmdChar = char
                    switch self.family {
                    case .whoop4:
                        // Confirmed write to cmd char triggers just-works bonding on WHOOP 4.0.
                        // If the strap is bonded to another device this write fails with
                        // "Encryption is insufficient" — connectionError is set for the user.
                        self.seq = self.seq &+ 1
                        let frame = WhoopCommand.getBatteryLevel.frame4(seq: self.seq)
                        peripheral.writeValue(Data(frame), for: char, type: .withResponse)

                    case .whoop5:
                        if let hello = self.family.clientHello {
                            peripheral.writeValue(Data(hello), for: char, type: .withResponse)
                        }
                    }

                } else if self.family.notifyCharUUIDs.map({ $0.lowercased() }).contains(uuidStr) {
                    self.notifyChars[uuidStr] = char
                    switch self.family {
                    case .whoop4:
                        peripheral.setNotifyValue(true, for: char)
                    case .whoop5:
                        // Defer subscription: strap rejects these pre-bond on 5.0.
                        self.pendingNotifyChars.append(char)
                    }

                } else if uuidStr == WhoopDeviceFamily.heartRateCharUUID.lowercased() {
                    self.hrChar = char
                    peripheral.setNotifyValue(true, for: char)

                } else if uuidStr == WhoopDeviceFamily.batteryCharUUID.lowercased() {
                    self.batteryChar = char
                    peripheral.readValue(for: char)
                    if char.properties.contains(.notify) {
                        peripheral.setNotifyValue(true, for: char)
                    }
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didWriteValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        Task { @MainActor in
            if let error {
                let desc = error.localizedDescription.lowercased()
                if desc.contains("encryption") || desc.contains("authentication") || desc.contains("insufficient") {
                    self.log.error("bond refused — strap is paired to another device")
                    self.connectionError = "Your WHOOP is bonded to another device. Repeatedly tap the top of your WHOOP to enter pairing mode, then tap Retry."
                } else {
                    self.log.warning("write failed for \(characteristic.uuid): \(error.localizedDescription, privacy: .public)")
                }
                return
            }
            if characteristic.uuid.uuidString.lowercased() == self.family.commandCharUUID.lowercased() {
                self.log.info("bond confirmed")
                self.onBonded()
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        let bytes = [UInt8](data)
        Task { @MainActor in
            let uuidStr = characteristic.uuid.uuidString.lowercased()

            // Standard BLE Heart Rate profile (works pre-bond on both generations).
            if uuidStr == WhoopDeviceFamily.heartRateCharUUID.lowercased() {
                if let m = StandardHeartRate.parse(bytes), m.hr >= 30, m.hr <= 220 {
                    let now = Int(Date().timeIntervalSince1970)
                    self.liveHR = m.hr
                    self.pendingBatch.hrSamples.append(WhoopHRSample(ts: now, bpm: m.hr))
                    for ms in m.rr {
                        self.pendingBatch.rrIntervals.append(WhoopRRInterval(ts: now, rrMs: ms))
                    }
                }
                // On WHOOP 5.0, streaming HR means the link is up.
                if self.family == .whoop5, self.connectionState != .connected {
                    self.log.info("WHOOP 5.0: live HR streaming — link established")
                    self.onBonded()
                }
                return
            }

            // Standard BLE Battery Service.
            if uuidStr == WhoopDeviceFamily.batteryCharUUID.lowercased() {
                // WHOOP 4.0 exposes a stub 100% on 0x2A19; real value comes from GET_BATTERY_LEVEL.
                // WHOOP 5.0 correctly uses 0x2A19.
                if self.family == .whoop5, let pct = bytes.first {
                    self.batteryPct = Int(pct)
                    self.pendingBatch.batterySamples.append(
                        WhoopBatterySample(ts: Int(Date().timeIntervalSince1970), pct: Double(pct)))
                }
                return
            }

            // Custom WHOOP notify characteristics (fragmented data on 0005/fd4b0005;
            // complete frames on cmd-notify and event-notify chars).
            let isDataChar = self.family.notifyCharUUIDs.last.map { uuidStr == $0.lowercased() } ?? false
            if isDataChar {
                // Data char carries fragmented frames — reassemble first.
                let frames = self.reassembler.feed(bytes)
                for frame in frames { self.handleCustomFrame(frame) }
            } else if self.family.notifyCharUUIDs.map({ $0.lowercased() }).contains(uuidStr) {
                // Command-response and event chars carry single complete frames.
                let check = verifyWhoopFrame(bytes, family: self.family)
                if check.ok { self.handleCustomFrame(bytes) }
            }
        }
    }
}
