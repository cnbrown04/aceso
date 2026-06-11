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

    // MARK: - Observable state (MainActor)

    var connectionState: WhoopConnectionState = .idle
    var liveHR: Int?
    var batteryPct: Int?
    var deviceName: String?
    /// Non-nil when a problem requires user action. Cleared on successful bond or `retry()`.
    var connectionError: String?

    // MARK: - Historical sync state (MainActor)

    var syncToast: AcesoSyncToast?
    var isHistoricalSyncing: Bool = false
    var historicalPacketCount: Int = 0

    // MARK: - Callbacks (MainActor)

    /// Called when a batch of samples is ready to persist or upload.
    var onSamples: ((WhoopSampleBatch) -> Void)?
    /// Called with raw historical data frames for deeper decoding.
    var onHistoricalFrame: (([UInt8]) -> Void)?

    // MARK: - Immutable identity (nonisolated — safe to read from any queue)

    nonisolated let family: WhoopDeviceFamily

    // Per-subsystem loggers — each prefixes output for easy grep in Console.app
    nonisolated private let logConnect  = Logger(subsystem: "com.aceso", category: "ble.connect")
    nonisolated private let logChar     = Logger(subsystem: "com.aceso", category: "ble.char")
    nonisolated private let logNotify   = Logger(subsystem: "com.aceso", category: "ble.notify")
    nonisolated private let logFrame    = Logger(subsystem: "com.aceso", category: "ble.frame")
    nonisolated private let logSync     = Logger(subsystem: "com.aceso", category: "ble.sync")
    nonisolated private let logWrite    = Logger(subsystem: "com.aceso", category: "ble.write")

    // MARK: - BLE processing queue
    //
    // All CoreBluetooth callbacks arrive on bleQueue. Heavy work (reassembly, CRC
    // verification, frame decoding) stays here. Only the final observable-state
    // mutations dispatch back to @MainActor.

    private let bleQueue = DispatchQueue(label: "com.aceso.ble", qos: .utility)

    // MARK: - MainActor state

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var cmdChar: CBCharacteristic?
    private var seq: UInt8 = 0
    private var batchFlushTimer: Timer?
    private var connectHandshakeDone = false
    private var scanTimeoutWork: DispatchWorkItem?
    private var connectTimeoutWork: DispatchWorkItem?
    private var consecutiveConnectTimeouts = 0
    private var pendingNotifyChars: [CBCharacteristic] = []
    private var syncClearWorkItem: DispatchWorkItem?

    // MARK: - bleQueue-only state
    //
    // These are accessed exclusively from bleQueue (a serial queue), so nonisolated(unsafe)
    // is safe — the serial queue provides the necessary mutual exclusion.

    nonisolated(unsafe) private var reassembler: WhoopReassembler
    nonisolated(unsafe) private var pendingBatch = WhoopSampleBatch(
        deviceID: "", hrSamples: [], rrIntervals: [], batterySamples: [])
    nonisolated(unsafe) private var pendingDeviceID: String = ""
    nonisolated(unsafe) private var historicalPacketCountBuffer: Int = 0
    nonisolated(unsafe) private var historicalIdleWorkItem: DispatchWorkItem?

    // MARK: - Init

    init(family: WhoopDeviceFamily = .whoop4) {
        self.family = family
        self.reassembler = WhoopReassembler(family: family)
        super.init()
        logConnect.info("[ble.connect] init — family=\(family == .whoop4 ? "whoop4" : "whoop5", privacy: .public) service=\(family.serviceUUID, privacy: .public)")
        central = CBCentralManager(delegate: self, queue: bleQueue)
    }

    // MARK: - Public API

    func connect() {
        guard central.state == .poweredOn else {
            logConnect.warning("[ble.connect] connect() called but CBManager state=\(self.central.state.rawValue) — skipping")
            return
        }
        guard connectionState == .idle else {
            logConnect.debug("[ble.connect] connect() skipped — already in state \(self.connectionState == .scanning ? "scanning" : "connecting/connected", privacy: .public)")
            return
        }

        if let existing = central.retrieveConnectedPeripherals(withServices: [CBUUID(string: family.serviceUUID)]).first {
            logConnect.info("[ble.connect] found already-connected peripheral \(existing.identifier.uuidString, privacy: .public) — attaching without scan")
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
        logConnect.info("[ble.connect] scanning for WHOOP serviceUUID=\(self.family.serviceUUID, privacy: .public)")
        central.scanForPeripherals(
            withServices: [CBUUID(string: family.serviceUUID)],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        armScanTimeout()
    }

    func disconnect() {
        logConnect.info("[ble.connect] disconnect() called — currentState=\(self.connectionState == .connected ? "connected" : "other", privacy: .public)")
        cancelTimeouts()
        batchFlushTimer?.invalidate()
        batchFlushTimer = nil
        connectHandshakeDone = false
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        resetCharacteristics()
        isHistoricalSyncing = false
        bleQueue.async { [weak self] in
            self?.historicalIdleWorkItem?.cancel()
            self?.historicalIdleWorkItem = nil
            self?.reassembler.reset()
            self?.pendingBatch = WhoopSampleBatch(deviceID: "", hrSamples: [], rrIntervals: [], batterySamples: [])
        }
        connectionState = .idle
    }

    func retry() {
        logConnect.info("[ble.connect] retry() — clearing error and reconnecting")
        connectionError = nil
        consecutiveConnectTimeouts = 0
        connect()
    }

    /// Re-issue sendHistoricalData and reset the app-side packet counter.
    func resyncHistoricalData() {
        guard connectionState == .connected else {
            logSync.warning("[ble.sync] resyncHistoricalData() called but not connected — ignoring")
            return
        }
        logSync.info("[ble.sync] resync requested — resetting packet counter and re-issuing sendHistoricalData")
        historicalPacketCount = 0
        isHistoricalSyncing = true
        bleQueue.async { [weak self] in
            self?.historicalIdleWorkItem?.cancel()
            self?.historicalIdleWorkItem = nil
            self?.historicalPacketCountBuffer = 0
        }
        publishSyncToast(phase: .syncing, title: "Syncing", detail: "Requesting historical data…")
        send(.sendHistoricalData, writeType: .withResponse)
    }

    // MARK: - Command sending

    private func send(_ command: WhoopCommand, payload: [UInt8] = [0x00],
                      writeType: CBCharacteristicWriteType = .withoutResponse) {
        guard let p = peripheral, let ch = cmdChar, p.state == .connected else {
            logWrite.warning("[ble.write] send(\(command.rawValue)) skipped — peripheral not ready")
            return
        }
        seq = seq &+ 1
        let frame = command.frame(seq: seq, payload: payload, family: family)
        let writeDesc = writeType == .withResponse ? "withResponse" : "withoutResponse"
        logWrite.debug("[ble.write] → cmd=\(command.rawValue) seq=\(self.seq) payload=\(payload.count)B writeType=\(writeDesc, privacy: .public)")
        p.writeValue(Data(frame), for: ch, type: writeType)
    }

    // MARK: - Bond completion

    private func onBonded() {
        guard !connectHandshakeDone else { return }
        connectHandshakeDone = true
        consecutiveConnectTimeouts = 0
        connectionError = nil
        cancelTimeouts()

        logConnect.info("[ble.connect] bond complete — sending handshake commands (setClock → sendHistoricalData +1.5s)")
        connectionState = .connected

        if family == .whoop5 {
            for char in pendingNotifyChars where !char.isNotifying {
                peripheral?.setNotifyValue(true, for: char)
            }
            pendingNotifyChars.removeAll()
        }

        send(.setClock, payload: WhoopCommand.setClockPayload())
        if family == .whoop5 {
            send(.toggleRealtimeHR, payload: [0x01])
        }
        // Defer sendHistoricalData 1.5s so SET_CLOCK settles (mirrors NOOP's hardware-validated ordering).
        // exitHighFreqSync is intentionally omitted — NOOP only sends it as watchdog recovery for a
        // stuck strap, not in the normal connect handshake; sending it here was disrupting the offload.
        isHistoricalSyncing = true
        publishSyncToast(phase: .syncing, title: "Syncing", detail: "Requesting historical data…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.connectionState == .connected else { return }
            self.logSync.info("[ble.sync] requesting historical data (sendHistoricalData cmd=22, writeType=withResponse)")
            self.send(.sendHistoricalData, writeType: .withResponse)
            self.bleQueue.async { self.historicalPacketCountBuffer = 0 }
        }

        var batteryTick = 0
        batchFlushTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.bleQueue.async { self.flushBatch() }
            // 0x2A19 is a stub on WHOOP 4.0 (always 100%). Refresh real battery every ~60s.
            batteryTick += 1
            if self.family == .whoop4, batteryTick % 2 == 0 {
                self.logWrite.debug("[ble.write] keepalive → getBatteryLevel")
                self.send(.getBatteryLevel, payload: [0x00])
            }
        }
    }

    // MARK: - Timeouts

    private func armScanTimeout() {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.connectionState == .scanning else { return }
            self.logConnect.warning("[ble.connect] scan timeout (15s) — no WHOOP found; retrying scan")
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
                self.logConnect.warning("[ble.connect] connect timeout — \(self.consecutiveConnectTimeouts) consecutive failures; WHOOP refusing connections (filter list rejection?)")
                self.connectionError = "Your WHOOP isn't accepting connections. Repeatedly tap the top of your WHOOP to enter pairing mode, then tap Retry."
                self.disconnect()
                return
            }
            self.logConnect.warning("[ble.connect] connect timeout — attempt \(self.consecutiveConnectTimeouts) of 2; retrying in 3s")
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

    // MARK: - Frame handling (runs on bleQueue)

    nonisolated private func handleCustomFrame(_ frame: [UInt8]) {
        let now = Int(Date().timeIntervalSince1970)
        guard frame.count >= 5 else {
            logFrame.warning("[ble.frame] received short frame \(frame.count)B — skipping")
            return
        }

        // frame[4] is the packet type for both WHOOP 4.0 and 5.0 (after the 4-byte header)
        let packetType = frame[4]
        logFrame.debug("[ble.frame] type=0x\(String(packetType, radix: 16), privacy: .public) (\(packetType)) length=\(frame.count)B")

        let decoded = decodeWhoopFrame(frame)
        switch decoded {
        case .realtimeHR(let bpm, let rrMs, _):
            logFrame.debug("[ble.frame] realtimeHR bpm=\(bpm) rrCount=\(rrMs.count)")
            pendingBatch.hrSamples.append(WhoopHRSample(ts: now, bpm: bpm))
            for ms in rrMs {
                pendingBatch.rrIntervals.append(WhoopRRInterval(ts: now, rrMs: ms))
            }
            Task { @MainActor [weak self] in self?.liveHR = bpm }

        case .batteryLevel(let pct):
            logFrame.debug("[ble.frame] batteryLevel pct=\(Int(pct.rounded()))%")
            pendingBatch.batterySamples.append(WhoopBatterySample(ts: now, pct: pct))
            Task { @MainActor [weak self] in self?.batteryPct = Int(pct.rounded()) }

        case .historicalData(let raw):
            historicalPacketCountBuffer += 1
            let count = historicalPacketCountBuffer
            logFrame.debug("[ble.frame] historicalData packet #\(count) length=\(raw.count)B")
            scheduleHistoricalIdleCompletion()
            if count == 1 {
                logSync.info("[ble.sync] first historical data packet received — stream is flowing")
            } else if count % 50 == 0 {
                logSync.info("[ble.sync] historical sync progress: \(count) packets received")
            }
            // Throttle MainActor updates to every 10 packets to avoid flooding
            if count == 1 || count % 10 == 0 {
                Task { @MainActor [weak self] in
                    self?.historicalPacketCount = count
                    self?.publishSyncToast(
                        phase: .syncing,
                        title: "Syncing",
                        detail: "\(count) \(count == 1 ? "packet" : "packets")…"
                    )
                }
            }
            Task { @MainActor [weak self] in self?.onHistoricalFrame?(raw) }

        case .historyStart:
            logSync.info("[ble.sync] HISTORY_START received — strap beginning chunk stream")

        case .historyEnd(let trim):
            // WHOOP requires a historicalDataResult ACK to continue streaming the next chunk.
            // Without this ACK the strap sends one chunk then goes silent.
            logSync.info("[ble.sync] HISTORY_END received trim=\(trim) — sending historicalDataResult ACK")
            Task { @MainActor [weak self] in self?.ackHistoryEnd(trim: trim) }

        case .historyComplete:
            // Definitive end-of-stream signal from the strap.
            logSync.info("[ble.sync] HISTORY_COMPLETE received — all chunks delivered, finishing sync")
            historicalIdleWorkItem?.cancel()
            historicalIdleWorkItem = nil
            Task { @MainActor [weak self] in self?.finishHistoricalSync() }

        case .unknown:
            logFrame.debug("[ble.frame] type=0x\(String(packetType, radix: 16), privacy: .public) (\(packetType)) — no handler")
        }
    }

    // MARK: - Historical sync completion (runs on bleQueue / main)

    nonisolated private func scheduleHistoricalIdleCompletion() {
        historicalIdleWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.finishHistoricalSync()
        }
        historicalIdleWorkItem = work
        // 4 s of silence after the last packet = WHOOP is done streaming
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: work)
    }

    private func ackHistoryEnd(trim: UInt32) {
        let payload = WhoopCommand.historicalDataResultPayload(trim: trim)
        logWrite.info("[ble.write] → historicalDataResult ACK trim=\(trim) writeType=withResponse")
        send(.historicalDataResult, payload: payload, writeType: .withResponse)
    }

    // Called on main (DispatchWorkItem fires on main)
    private func finishHistoricalSync() {
        let count = historicalPacketCount
        logSync.info("[ble.sync] sync complete — total=\(count) packets")
        isHistoricalSyncing = false
        let detail = count == 0
            ? "No new data"
            : "\(count) \(count == 1 ? "packet" : "packets") captured"
        publishSyncToast(phase: .synced, title: "Synced", detail: detail, clearAfter: 2.5)
    }

    // MARK: - Sync toast (MainActor)

    private func publishSyncToast(
        phase: AcesoSyncToastPhase,
        title: String,
        detail: String,
        clearAfter: TimeInterval? = nil
    ) {
        syncClearWorkItem?.cancel()
        syncToast = AcesoSyncToast(phase: phase, title: title, detail: detail)
        guard let clearAfter else { return }
        let toastID = syncToast?.id
        let work = DispatchWorkItem { [weak self] in
            guard self?.syncToast?.id == toastID else { return }
            self?.syncToast = nil
        }
        syncClearWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + clearAfter, execute: work)
    }

    nonisolated private func flushBatch() {
        guard !pendingBatch.isEmpty else { return }
        let batch = WhoopSampleBatch(
            deviceID: pendingDeviceID,
            hrSamples: pendingBatch.hrSamples,
            rrIntervals: pendingBatch.rrIntervals,
            batterySamples: pendingBatch.batterySamples
        )
        logFrame.debug("[ble.frame] flushing batch hr=\(batch.hrSamples.count) rr=\(batch.rrIntervals.count) batt=\(batch.batterySamples.count)")
        pendingBatch = WhoopSampleBatch(deviceID: pendingDeviceID, hrSamples: [], rrIntervals: [], batterySamples: [])
        Task { @MainActor [weak self] in self?.onSamples?(batch) }
    }

    // MARK: - Helpers

    private func preparePeripheral(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
        deviceName = p.name
        let id = p.identifier.uuidString
        bleQueue.async { [weak self] in self?.pendingDeviceID = id }
    }

    private func resetCharacteristics() {
        cmdChar = nil
        pendingNotifyChars.removeAll()
    }

    private func allServiceUUIDs() -> [CBUUID] {
        [CBUUID(string: family.serviceUUID),
         CBUUID(string: WhoopDeviceFamily.heartRateServiceUUID),
         CBUUID(string: WhoopDeviceFamily.batteryServiceUUID)]
    }
}

// MARK: - CBCentralManagerDelegate

extension WhoopBLEClient: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let stateStr: String
        switch central.state {
        case .poweredOn:  stateStr = "poweredOn"
        case .poweredOff: stateStr = "poweredOff"
        case .resetting:  stateStr = "resetting"
        case .unauthorized: stateStr = "unauthorized"
        case .unsupported:  stateStr = "unsupported"
        case .unknown:    stateStr = "unknown"
        @unknown default: stateStr = "unknown(\(central.state.rawValue))"
        }
        logConnect.info("[ble.connect] CBCentralManager state → \(stateStr, privacy: .public)")
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
        logConnect.info("[ble.connect] discovered \(name, privacy: .public) id=\(peripheral.identifier.uuidString, privacy: .public) rssi=\(RSSI)dBm — stopping scan and connecting")
        Task { @MainActor in
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
        logConnect.info("[ble.connect] didConnect \(peripheral.name ?? "WHOOP", privacy: .public) — discovering services")
        Task { @MainActor in
            peripheral.discoverServices(self.allServiceUUIDs())
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        if let error {
            logConnect.warning("[ble.connect] didDisconnect with error: \(error.localizedDescription, privacy: .public)")
        } else {
            logConnect.info("[ble.connect] didDisconnect cleanly — will reconnect in 3s if no error")
        }
        Task { @MainActor in
            self.cancelTimeouts()
            self.bleQueue.async { [weak self] in self?.flushBatch() }
            self.batchFlushTimer?.invalidate()
            self.batchFlushTimer = nil
            self.connectHandshakeDone = false
            self.liveHR = nil
            self.isHistoricalSyncing = false
            self.connectionState = .idle
            self.resetCharacteristics()
            self.bleQueue.async { [weak self] in
                self?.historicalIdleWorkItem?.cancel()
                self?.historicalIdleWorkItem = nil
                self?.reassembler.reset()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.connectionState == .idle, self.connectionError == nil else { return }
                self.logConnect.info("[ble.connect] auto-reconnect triggered after disconnect")
                self.connect()
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        logConnect.error("[ble.connect] didFailToConnect \(peripheral.name ?? "WHOOP", privacy: .public): \(error?.localizedDescription ?? "unknown error", privacy: .public)")
        Task { @MainActor in
            self.cancelTimeouts()
            self.connectHandshakeDone = false
            self.connectionState = .idle
            self.resetCharacteristics()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.connectionError == nil else { return }
                self.logConnect.info("[ble.connect] retrying after failed connect")
                self.connect()
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension WhoopBLEClient: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverServices error: Error?) {
        if let error {
            logChar.error("[ble.char] service discovery failed: \(error.localizedDescription, privacy: .public)")
            Task { @MainActor in
                self.logConnect.error("[ble.connect] aborting — service discovery error")
            }
            return
        }
        let serviceUUIDs = (peripheral.services ?? []).map { $0.uuid.uuidString }.joined(separator: ", ")
        logChar.info("[ble.char] discovered \((peripheral.services ?? []).count) services: \(serviceUUIDs, privacy: .public)")
        Task { @MainActor in
            for service in peripheral.services ?? [] {
                switch service.uuid {
                case CBUUID(string: self.family.serviceUUID):
                    let charUUIDs = ([self.family.commandCharUUID] + self.family.notifyCharUUIDs)
                        .map { CBUUID(string: $0) }
                    self.logChar.info("[ble.char] discovering \(charUUIDs.count) custom characteristics for WHOOP service")
                    peripheral.discoverCharacteristics(charUUIDs, for: service)
                case CBUUID(string: WhoopDeviceFamily.heartRateServiceUUID):
                    self.logChar.info("[ble.char] discovering HR characteristic (0x2A37)")
                    peripheral.discoverCharacteristics(
                        [CBUUID(string: WhoopDeviceFamily.heartRateCharUUID)], for: service)
                case CBUUID(string: WhoopDeviceFamily.batteryServiceUUID):
                    self.logChar.info("[ble.char] discovering battery characteristic (0x2A19)")
                    peripheral.discoverCharacteristics(
                        [CBUUID(string: WhoopDeviceFamily.batteryCharUUID)], for: service)
                default:
                    self.logChar.debug("[ble.char] ignoring unknown service \(service.uuid.uuidString, privacy: .public)")
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        if let error {
            logChar.error("[ble.char] characteristic discovery failed for service \(service.uuid.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }
        let charUUIDs = (service.characteristics ?? []).map { $0.uuid.uuidString }.joined(separator: ", ")
        logChar.info("[ble.char] discovered \((service.characteristics ?? []).count) chars in service \(service.uuid.uuidString, privacy: .public): \(charUUIDs, privacy: .public)")
        Task { @MainActor in
            for char in service.characteristics ?? [] {
                let uuidStr = char.uuid.uuidString.lowercased()

                if uuidStr == self.family.commandCharUUID.lowercased() {
                    self.logChar.info("[ble.char] found cmdChar — sending bond initiation write")
                    self.cmdChar = char
                    switch self.family {
                    case .whoop4:
                        self.seq = self.seq &+ 1
                        let frame = WhoopCommand.getBatteryLevel.frame4(seq: self.seq)
                        self.logWrite.info("[ble.write] → getBatteryLevel (bond init) seq=\(self.seq) writeType=withResponse")
                        peripheral.writeValue(Data(frame), for: char, type: .withResponse)
                    case .whoop5:
                        if let hello = self.family.clientHello {
                            self.logWrite.info("[ble.write] → clientHello (bond init) \(hello.count)B writeType=withResponse")
                            peripheral.writeValue(Data(hello), for: char, type: .withResponse)
                        }
                    }

                } else if self.family.notifyCharUUIDs.map({ $0.lowercased() }).contains(uuidStr) {
                    switch self.family {
                    case .whoop4:
                        self.logChar.info("[ble.char] subscribing to notify char \(char.uuid.uuidString, privacy: .public)")
                        peripheral.setNotifyValue(true, for: char)
                    case .whoop5:
                        self.logChar.info("[ble.char] queueing notify char for post-bond subscription: \(char.uuid.uuidString, privacy: .public)")
                        self.pendingNotifyChars.append(char)
                    }

                } else if uuidStr == WhoopDeviceFamily.heartRateCharUUID.lowercased() {
                    self.logChar.info("[ble.char] found standard HR char (0x2A37) — subscribing")
                    peripheral.setNotifyValue(true, for: char)

                } else if uuidStr == WhoopDeviceFamily.batteryCharUUID.lowercased() {
                    self.logChar.info("[ble.char] found standard battery char (0x2A19) — reading + subscribing if notifiable")
                    peripheral.readValue(for: char)
                    if char.properties.contains(.notify) {
                        peripheral.setNotifyValue(true, for: char)
                    }
                } else {
                    self.logChar.debug("[ble.char] ignoring char \(char.uuid.uuidString, privacy: .public)")
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didWriteValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        let uuidStr = characteristic.uuid.uuidString.lowercased()
        Task { @MainActor in
            if let error {
                let desc = error.localizedDescription.lowercased()
                if desc.contains("encryption") || desc.contains("authentication") || desc.contains("insufficient") {
                    self.logWrite.error("[ble.write] bond refused — strap is paired to another device (char=\(characteristic.uuid.uuidString, privacy: .public))")
                    self.connectionError = "Your WHOOP is bonded to another device. Repeatedly tap the top of your WHOOP to enter pairing mode, then tap Retry."
                } else {
                    self.logWrite.warning("[ble.write] write failed for char=\(characteristic.uuid.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
                return
            }

            guard uuidStr == self.family.commandCharUUID.lowercased() else { return }

            if !self.connectHandshakeDone {
                self.logWrite.info("[ble.write] ack received for bond-init write — calling onBonded()")
                self.onBonded()
            } else {
                // Subsequent withResponse acks (e.g. sendHistoricalData, historicalDataResult)
                self.logWrite.debug("[ble.write] ack received for post-bond command write (seq=\(self.seq))")
            }
        }
    }

    // All heavy work (reassembly, CRC checks, frame decoding) runs directly on bleQueue.
    // Only the final state mutations dispatch back to @MainActor.
    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        if let error {
            logNotify.warning("[ble.notify] didUpdateValue error for \(characteristic.uuid.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let data = characteristic.value else {
            logNotify.warning("[ble.notify] nil value for \(characteristic.uuid.uuidString, privacy: .public)")
            return
        }
        let bytes = [UInt8](data)
        let uuidStr = characteristic.uuid.uuidString.lowercased()
        logNotify.debug("[ble.notify] ← char=\(characteristic.uuid.uuidString, privacy: .public) bytes=\(bytes.count) first=0x\(bytes.first.map { String($0, radix: 16) } ?? "--", privacy: .public)")

        // Standard BLE Heart Rate (0x2A37)
        if uuidStr == WhoopDeviceFamily.heartRateCharUUID.lowercased() {
            logNotify.debug("[ble.notify] standard HR notification \(bytes.count)B")
            if let m = StandardHeartRate.parse(bytes), m.hr >= 30, m.hr <= 220 {
                let now = Int(Date().timeIntervalSince1970)
                pendingBatch.hrSamples.append(WhoopHRSample(ts: now, bpm: m.hr))
                for ms in m.rr {
                    pendingBatch.rrIntervals.append(WhoopRRInterval(ts: now, rrMs: ms))
                }
                Task { @MainActor [weak self] in self?.liveHR = m.hr }
            }
            if family == .whoop5 {
                Task { @MainActor [weak self] in
                    guard let self, self.connectionState != .connected else { return }
                    self.logConnect.info("[ble.connect] WHOOP 5.0 HR streaming confirmed — treating as bond complete")
                    self.onBonded()
                }
            }
            return
        }

        // Standard BLE Battery (0x2A19)
        if uuidStr == WhoopDeviceFamily.batteryCharUUID.lowercased() {
            logNotify.debug("[ble.notify] standard battery notification \(bytes.count)B value=\(bytes.first ?? 0)%")
            if family == .whoop5, let pct = bytes.first {
                let now = Int(Date().timeIntervalSince1970)
                pendingBatch.batterySamples.append(WhoopBatterySample(ts: now, pct: Double(pct)))
                Task { @MainActor [weak self] in self?.batteryPct = Int(pct) }
            }
            return
        }

        // Custom WHOOP notify characteristics — ALL three go through the same reassembler (matching
        // NOOP's routing: cmdNotifyChar + eventNotifyChar + dataNotifyChar all feed reassembler.feed).
        // Complete frames pass through as-is; fragmented frames accumulate until complete.
        let notifyUUIDs = family.notifyCharUUIDs.map { $0.lowercased() }
        if notifyUUIDs.contains(uuidStr) {
            // Log first 8 bytes as hex to aid protocol debugging
            let hexHead = bytes.prefix(8).map { String(format: "%02x", $0) }.joined(separator: " ")
            logNotify.debug("[ble.notify] custom char \(bytes.count)B head=[\(hexHead, privacy: .public)]")

            let result = reassembler.feed(bytes)

            if result.crcFailures > 0 {
                logNotify.warning("[ble.notify] reassembler discarded \(result.crcFailures) CRC-failed frame(s) from \(characteristic.uuid.uuidString, privacy: .public)")
            }
            if result.frames.isEmpty && result.crcFailures == 0 {
                // Buffer has data but frame isn't complete yet
                let declared = reassembler.declaredTotal
                let buffered = reassembler.bufferCount
                if let total = declared {
                    logNotify.debug("[ble.notify] reassembler waiting: buffered=\(buffered)B declaredTotal=\(total)B need=\(max(0, total - buffered))B more")
                } else {
                    logNotify.debug("[ble.notify] reassembler waiting: buffered=\(buffered)B (can't yet determine frame length)")
                }
            } else if !result.frames.isEmpty {
                logNotify.debug("[ble.notify] reassembler produced \(result.frames.count) frame(s)")
            }
            for frame in result.frames { handleCustomFrame(frame) }
        } else {
            logNotify.debug("[ble.notify] ignoring notification from unrecognized char \(characteristic.uuid.uuidString, privacy: .public)")
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateNotificationStateFor characteristic: CBCharacteristic,
                                error: Error?) {
        if let error {
            logChar.warning("[ble.char] setNotify failed for \(characteristic.uuid.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        } else {
            logChar.info("[ble.char] notifications \(characteristic.isNotifying ? "enabled" : "disabled", privacy: .public) for \(characteristic.uuid.uuidString, privacy: .public)")
        }
    }
}
