import CoreBluetooth
import Foundation
import OSLog
import WhoopProtocol

/// CoreBluetooth engine for WHOOP 4.0 and 5.0.
@Observable
public final class WhoopBLEClient: NSObject, @unchecked Sendable {

    public var connectionState: WhoopConnectionState = .idle
    public var liveHR: Int?
    public var batteryPct: Int?
    public var deviceName: String?
    public var connectionError: String?
    public var syncToast: WhoopSyncToast?
    public var isHistoricalSyncing: Bool = false
    public var historicalPacketCount: Int = 0
    public var isWorn: Bool?
    public var versionInfo: WhoopVersionInfo?
    public var dataRange: WhoopDataRange?

    public var onSamples: ((WhoopSampleBatch) -> Void)?
    public var onHistoricalFrame: (([UInt8]) -> Void)?
    public var onEvent: ((WhoopStrapEvent) -> Void)?
    public var onRawIMU: ((WhoopIMUSample) -> Void)?
    public var onRawOptical: ((WhoopRawOpticalPacket) -> Void)?

    nonisolated public let family: WhoopDeviceFamily

    nonisolated private let logConnect = Logger(subsystem: "dev.aceso.whoop", category: "ble.connect")
    nonisolated private let logChar = Logger(subsystem: "dev.aceso.whoop", category: "ble.char")
    nonisolated private let logNotify = Logger(subsystem: "dev.aceso.whoop", category: "ble.notify")
    nonisolated private let logFrame = Logger(subsystem: "dev.aceso.whoop", category: "ble.frame")
    nonisolated private let logSync = Logger(subsystem: "dev.aceso.whoop", category: "ble.sync")
    nonisolated private let logWrite = Logger(subsystem: "dev.aceso.whoop", category: "ble.write")

    private let bleQueue = DispatchQueue(label: "dev.aceso.whoop.ble", qos: .utility)

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

    nonisolated(unsafe) private var reassembler: WhoopReassembler
    nonisolated(unsafe) private var pendingBatch = WhoopSampleBatch(deviceID: "")
    nonisolated(unsafe) private var pendingDeviceID: String = ""
    nonisolated(unsafe) private var historicalPacketCountBuffer: Int = 0
    nonisolated(unsafe) private var historicalIdleWorkItem: DispatchWorkItem?

    public init(family: WhoopDeviceFamily = .whoop4) {
        self.family = family
        self.reassembler = WhoopReassembler(family: family)
        super.init()
        central = CBCentralManager(delegate: self, queue: bleQueue)
    }

    public func connect() {
        guard central.state == .poweredOn else { return }
        guard connectionState == .idle else { return }

        if let existing = central.retrieveConnectedPeripherals(withServices: [CBUUID(string: family.serviceUUID)]).first {
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
        central.scanForPeripherals(
            withServices: [CBUUID(string: family.serviceUUID)],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        armScanTimeout()
    }

    public func disconnect() {
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
            self?.pendingBatch = WhoopSampleBatch(deviceID: "")
        }
        connectionState = .idle
    }

    public func retry() {
        connectionError = nil
        consecutiveConnectTimeouts = 0
        connect()
    }

    public func resyncHistoricalData() {
        guard connectionState == .connected else { return }
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

    public func startRawData() {
        send(.enableOpticalData, payload: [0x01])
        send(.toggleImuMode, payload: [0x01])
        send(.startRawData, payload: [0x01])
    }

    public func stopRawData() {
        send(.stopRawData, payload: [0x01])
        send(.toggleImuMode, payload: [0x00])
    }

    public func requestDataRange() {
        send(.getDataRange, payload: [0x00])
    }

    public func requestVersionInfo() {
        send(.reportVersionInfo, payload: [0x00])
    }

    public func requestExtendedBattery() {
        send(.getExtendedBatteryInfo, payload: [0x00])
    }

    private func send(_ command: WhoopCommand, payload: [UInt8] = [0x00],
                      writeType: CBCharacteristicWriteType = .withoutResponse) {
        guard let p = peripheral, let ch = cmdChar, p.state == .connected else { return }
        seq = seq &+ 1
        let frame = command.frame(seq: seq, payload: payload, family: family)
        p.writeValue(Data(frame), for: ch, type: writeType)
    }

    private func onBonded() {
        guard !connectHandshakeDone else { return }
        connectHandshakeDone = true
        consecutiveConnectTimeouts = 0
        connectionError = nil
        cancelTimeouts()
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
        send(.sendR10R11Realtime, payload: [0x00])
        requestDataRange()
        requestVersionInfo()

        isHistoricalSyncing = true
        publishSyncToast(phase: .syncing, title: "Syncing", detail: "Requesting historical data…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.connectionState == .connected else { return }
            self.send(.sendHistoricalData, writeType: .withResponse)
            self.bleQueue.async { self.historicalPacketCountBuffer = 0 }
        }

        var batteryTick = 0
        batchFlushTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.bleQueue.async { self.flushBatch() }
            batteryTick += 1
            if self.family == .whoop4, batteryTick % 2 == 0 {
                self.send(.getBatteryLevel, payload: [0x00])
            }
        }
    }

    private func armScanTimeout() {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.connectionState == .scanning else { return }
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
                self.connectionError = "Your WHOOP isn't accepting connections. Repeatedly tap the top of your WHOOP to enter pairing mode, then tap Retry."
                self.disconnect()
                return
            }
            self.disconnect()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.connect() }
        }
        connectTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)
    }

    private func cancelTimeouts() {
        scanTimeoutWork?.cancel(); scanTimeoutWork = nil
        connectTimeoutWork?.cancel(); connectTimeoutWork = nil
    }

    nonisolated private func handleCustomFrame(_ frame: [UInt8]) {
        let now = Int(Date().timeIntervalSince1970)
        guard frame.count >= 5 else { return }

        let decoded = decodeWhoopFrame(frame, family: family)
        switch decoded {
        case .realtimeHR(let bpm, let rrMs, _):
            pendingBatch.hrSamples.append(WhoopHRSample(ts: now, bpm: bpm))
            for ms in rrMs {
                pendingBatch.rrIntervals.append(WhoopRRInterval(ts: now, rrMs: ms))
            }
            Task { @MainActor [weak self] in self?.liveHR = bpm }

        case .batteryLevel(let pct):
            pendingBatch.batterySamples.append(WhoopBatterySample(ts: now, pct: pct))
            Task { @MainActor [weak self] in self?.batteryPct = Int(pct.rounded()) }

        case .extendedBattery(let info):
            pendingBatch.batterySamples.append(WhoopBatterySample(ts: now, pct: info.pct))
            Task { @MainActor [weak self] in self?.batteryPct = Int(info.pct.rounded()) }

        case .versionInfo(let info):
            Task { @MainActor [weak self] in self?.versionInfo = info }

        case .dataRange(let range):
            Task { @MainActor [weak self] in self?.dataRange = range }

        case .rawIMU(let sample):
            pendingBatch.imuSamples.append(sample)
            Task { @MainActor [weak self] in self?.onRawIMU?(sample) }

        case .rawOptical(let packet):
            pendingBatch.opticalPackets.append(packet)
            Task { @MainActor [weak self] in self?.onRawOptical?(packet) }

        case .strapEvent(let event):
            pendingBatch.events.append(event)
            Task { @MainActor [weak self] in
                switch event.event {
                case .wristOn: self?.isWorn = true
                case .wristOff: self?.isWorn = false
                default: break
                }
                self?.onEvent?(event)
            }

        case .historicalData(let raw):
            historicalPacketCountBuffer += 1
            let count = historicalPacketCountBuffer
            scheduleHistoricalIdleCompletion()
            if count == 1 || count % 10 == 0 {
                Task { @MainActor [weak self] in
                    self?.historicalPacketCount = count
                    self?.publishSyncToast(phase: .syncing, title: "Syncing", detail: "\(count) packets…")
                }
            }
            Task { @MainActor [weak self] in self?.onHistoricalFrame?(raw) }

        case .historyEnd(let trim):
            Task { @MainActor [weak self] in self?.ackHistoryEnd(trim: trim) }

        case .historyComplete:
            historicalIdleWorkItem?.cancel()
            historicalIdleWorkItem = nil
            Task { @MainActor [weak self] in self?.finishHistoricalSync() }

        case .historyStart, .deviceClock, .consoleLog, .unknown:
            break
        }
    }

    nonisolated private func scheduleHistoricalIdleCompletion() {
        historicalIdleWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.finishHistoricalSync() }
        historicalIdleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: work)
    }

    private func ackHistoryEnd(trim: UInt32) {
        send(.historicalDataResult, payload: WhoopCommand.historicalDataResultPayload(trim: trim), writeType: .withResponse)
    }

    private func finishHistoricalSync() {
        let count = historicalPacketCount
        isHistoricalSyncing = false
        let detail = count == 0 ? "No new data" : "\(count) packets captured"
        publishSyncToast(phase: .synced, title: "Synced", detail: detail, clearAfter: 2.5)
    }

    private func publishSyncToast(phase: WhoopSyncToastPhase, title: String, detail: String, clearAfter: TimeInterval? = nil) {
        syncClearWorkItem?.cancel()
        syncToast = WhoopSyncToast(phase: phase, title: title, detail: detail)
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
        let batch = pendingBatch
        pendingBatch = WhoopSampleBatch(deviceID: pendingDeviceID)
        Task { @MainActor [weak self] in self?.onSamples?(batch) }
    }

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

extension WhoopBLEClient: CBCentralManagerDelegate {
    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            guard central.state == .poweredOn else {
                self.connectionState = .idle
                return
            }
            self.connect()
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager,
                                           didDiscover peripheral: CBPeripheral,
                                           advertisementData: [String: Any],
                                           rssi RSSI: NSNumber) {
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

    nonisolated public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in peripheral.discoverServices(self.allServiceUUIDs()) }
    }

    nonisolated public func centralManager(_ central: CBCentralManager,
                                           didDisconnectPeripheral peripheral: CBPeripheral,
                                           error: Error?) {
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
                self.connect()
            }
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager,
                                           didFailToConnect peripheral: CBPeripheral,
                                           error: Error?) {
        Task { @MainActor in
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
}

extension WhoopBLEClient: CBPeripheralDelegate {
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { return }
        Task { @MainActor in
            for service in peripheral.services ?? [] {
                switch service.uuid {
                case CBUUID(string: self.family.serviceUUID):
                    let charUUIDs = ([self.family.commandCharUUID] + self.family.notifyCharUUIDs)
                        .map { CBUUID(string: $0) }
                    peripheral.discoverCharacteristics(charUUIDs, for: service)
                case CBUUID(string: WhoopDeviceFamily.heartRateServiceUUID):
                    peripheral.discoverCharacteristics([CBUUID(string: WhoopDeviceFamily.heartRateCharUUID)], for: service)
                case CBUUID(string: WhoopDeviceFamily.batteryServiceUUID):
                    peripheral.discoverCharacteristics([CBUUID(string: WhoopDeviceFamily.batteryCharUUID)], for: service)
                default:
                    break
                }
            }
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral,
                                       didDiscoverCharacteristicsFor service: CBService,
                                       error: Error?) {
        guard error == nil else { return }
        Task { @MainActor in
            for char in service.characteristics ?? [] {
                let uuidStr = char.uuid.uuidString.lowercased()
                if uuidStr == self.family.commandCharUUID.lowercased() {
                    self.cmdChar = char
                    switch self.family {
                    case .whoop4:
                        self.seq = self.seq &+ 1
                        let frame = WhoopCommand.getBatteryLevel.frame4(seq: self.seq)
                        peripheral.writeValue(Data(frame), for: char, type: .withResponse)
                    case .whoop5:
                        if let hello = self.family.clientHello {
                            peripheral.writeValue(Data(hello), for: char, type: .withResponse)
                        }
                    }
                } else if self.family.notifyCharUUIDs.map({ $0.lowercased() }).contains(uuidStr) {
                    switch self.family {
                    case .whoop4:
                        peripheral.setNotifyValue(true, for: char)
                    case .whoop5:
                        self.pendingNotifyChars.append(char)
                    }
                } else if uuidStr == WhoopDeviceFamily.heartRateCharUUID.lowercased() {
                    peripheral.setNotifyValue(true, for: char)
                } else if uuidStr == WhoopDeviceFamily.batteryCharUUID.lowercased() {
                    peripheral.readValue(for: char)
                    if char.properties.contains(.notify) {
                        peripheral.setNotifyValue(true, for: char)
                    }
                }
            }
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral,
                                       didWriteValueFor characteristic: CBCharacteristic,
                                       error: Error?) {
        Task { @MainActor in
            if let error {
                let desc = error.localizedDescription.lowercased()
                if desc.contains("encryption") || desc.contains("authentication") || desc.contains("insufficient") {
                    self.connectionError = "Your WHOOP is bonded to another device. Repeatedly tap the top of your WHOOP to enter pairing mode, then tap Retry."
                }
                return
            }
            guard characteristic.uuid.uuidString.lowercased() == self.family.commandCharUUID.lowercased(),
                  !self.connectHandshakeDone else { return }
            self.onBonded()
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral,
                                       didUpdateValueFor characteristic: CBCharacteristic,
                                       error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        let bytes = [UInt8](data)
        let uuidStr = characteristic.uuid.uuidString.lowercased()

        if uuidStr == WhoopDeviceFamily.heartRateCharUUID.lowercased() {
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
                    self.onBonded()
                }
            }
            return
        }

        if uuidStr == WhoopDeviceFamily.batteryCharUUID.lowercased() {
            if family == .whoop5, let pct = bytes.first {
                let now = Int(Date().timeIntervalSince1970)
                pendingBatch.batterySamples.append(WhoopBatterySample(ts: now, pct: Double(pct)))
                Task { @MainActor [weak self] in self?.batteryPct = Int(pct) }
            }
            return
        }

        let notifyUUIDs = family.notifyCharUUIDs.map { $0.lowercased() }
        if notifyUUIDs.contains(uuidStr) {
            let result = reassembler.feed(bytes)
            for frame in result.frames { handleCustomFrame(frame) }
        }
    }
}
