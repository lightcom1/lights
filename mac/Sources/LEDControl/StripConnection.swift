import CoreBluetooth
import Foundation

/// A device seen while scanning.
struct FoundDevice: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rssi: Int
    var likelyStrip: Bool
}

/// Owns the Bluetooth connection and a write queue with flow control.
///
/// Commands (`send`) are queued in order. Animation frames (`stream`) replace any frame that
/// hasn't started sending yet, so a slow link drops stale frames instead of lagging behind.
final class StripConnection: NSObject, ObservableObject {
    static let service = CBUUID(string: "FFFF")
    static let writeUUID = CBUUID(string: "FF01")
    static let notifyUUID = CBUUID(string: "FF02")
    private static let savedKey = "savedStripID"

    @Published private(set) var status = "Starting Bluetooth…"
    @Published private(set) var isConnected = false
    @Published private(set) var isScanning = false
    @Published private(set) var devices: [FoundDevice] = []
    @Published private(set) var deviceName = ""
    @Published private(set) var log: [String] = []
    @Published private(set) var maxWrite = 20

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var seen: [UUID: CBPeripheral] = [:]
    private var userDisconnected = false

    private var framer = Framer()
    private var queue: [Data] = []          // packets waiting to be written, in order
    private var pendingFrame: [UInt8]?      // latest animation frame not yet queued
    private var awaitingResponse = false    // for characteristics without write-without-response
    private(set) var framesSent = 0

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Public API

    func startScan() {
        guard central.state == .poweredOn else { return }
        devices = []
        isScanning = true
        status = "Scanning…"
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.stopScan() }
    }

    func stopScan() {
        guard isScanning else { return }
        central.stopScan()
        isScanning = false
        if !isConnected { status = "Not connected" }
    }

    func connect(_ id: UUID) {
        guard let p = seen[id] ?? central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        stopScan()
        userDisconnected = false
        if let old = peripheral, old.identifier != p.identifier { central.cancelPeripheralConnection(old) }
        peripheral = p
        p.delegate = self
        status = "Connecting to \(displayName(p))…"
        central.connect(p)
        UserDefaults.standard.set(id.uuidString, forKey: Self.savedKey)
    }

    func disconnect() {
        userDisconnected = true
        if let p = peripheral { central.cancelPeripheralConnection(p) }
    }

    func forgetSaved() {
        UserDefaults.standard.removeObject(forKey: Self.savedKey)
    }

    var hasSavedDevice: Bool { UserDefaults.standard.string(forKey: Self.savedKey) != nil }

    /// Queue a command; always delivered, in order.
    func send(_ payload: [UInt8], logIt: Bool = true) {
        guard isConnected else { if logIt { addLog("Not connected") }; return }
        let pkts = framer.packets(for: payload, maxWrite: maxWrite)
        if logIt { pkts.forEach { addLog("→ " + $0.hex) } }
        queue += pkts
        pump()
    }

    /// Offer an animation frame; dropped if a newer one arrives before it starts sending.
    func stream(_ payload: [UInt8]) {
        guard isConnected else { return }
        pendingFrame = payload
        pump()
    }

    /// True while a frame/command is still being written.
    var isBusy: Bool { !queue.isEmpty || awaitingResponse }

    func addLog(_ s: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        log.append("[\(f.string(from: Date()))] \(s)")
        if log.count > 300 { log.removeFirst(log.count - 300) }
    }

    // MARK: - Write pump

    private func pump() {
        guard let p = peripheral, let c = writeChar else { return }
        let noResponse = c.properties.contains(.writeWithoutResponse)
        while true {
            if queue.isEmpty, let frame = pendingFrame {
                pendingFrame = nil
                queue = framer.packets(for: frame, maxWrite: maxWrite)
                framesSent += 1
            }
            guard !queue.isEmpty else { return }
            if noResponse {
                guard p.canSendWriteWithoutResponse else { return } // resumes in peripheralIsReady
                p.writeValue(queue.removeFirst(), for: c, type: .withoutResponse)
            } else {
                guard !awaitingResponse else { return }             // resumes in didWriteValueFor
                awaitingResponse = true
                p.writeValue(queue.removeFirst(), for: c, type: .withResponse)
            }
        }
    }

    private func resetLink() {
        writeChar = nil
        queue = []
        pendingFrame = nil
        awaitingResponse = false
    }

    private func displayName(_ p: CBPeripheral) -> String {
        p.name ?? "LED strip"
    }
}

// MARK: - CBCentralManagerDelegate

extension StripConnection: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            status = "Not connected"
            // reconnect to the strip used last time, no picker needed
            if let s = UserDefaults.standard.string(forKey: Self.savedKey), let id = UUID(uuidString: s),
               let p = central.retrievePeripherals(withIdentifiers: [id]).first {
                seen[id] = p
                connect(id)
            } else {
                startScan()
            }
        case .unauthorized:
            status = "Bluetooth permission denied — allow it in System Settings → Privacy & Security → Bluetooth"
        case .poweredOff:
            status = "Bluetooth is off"
        default:
            status = "Bluetooth unavailable"
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData ad: [String: Any], rssi RSSI: NSNumber) {
        let name = p.name ?? (ad[CBAdvertisementDataLocalNameKey] as? String)
        let services = (ad[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let mfg = ad[CBAdvertisementDataManufacturerDataKey] as? Data
        let zenggeMfg = (mfg?.count ?? 0) >= 2 && mfg![mfg!.startIndex + 1] == 0x5a // company id 0x5Axx (little-endian)
        let likely = services.contains(Self.service) || zenggeMfg
            || (name.map { ["LEDnetWF", "IOTWF", "IOTB", "Zengge"].contains(where: $0.hasPrefix) } ?? false)
        seen[p.identifier] = p
        let dev = FoundDevice(id: p.identifier, name: name ?? "Unnamed device", rssi: RSSI.intValue, likelyStrip: likely)
        if let i = devices.firstIndex(where: { $0.id == dev.id }) { devices[i] = dev } else { devices.append(dev) }
        devices.sort { ($0.likelyStrip ? 1 : 0, $0.rssi) > ($1.likelyStrip ? 1 : 0, $1.rssi) }
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        status = "Discovering services…"
        p.discoverServices([Self.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        status = "Couldn't connect: \(error?.localizedDescription ?? "unknown error")"
        addLog(status)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        resetLink()
        isConnected = false
        addLog("Disconnected")
        if userDisconnected {
            status = "Not connected"
            peripheral = nil
        } else {
            // a pending connect never times out — it completes when the strip is back in range
            status = "Reconnecting…"
            central.connect(p)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension StripConnection: CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let svc = p.services?.first(where: { $0.uuid == Self.service }) else {
            status = "This device isn't a ZENGGE strip (no FFFF service)"
            addLog(status)
            return
        }
        p.discoverCharacteristics([Self.writeUUID, Self.notifyUUID], for: svc)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor svc: CBService, error: Error?) {
        for c in svc.characteristics ?? [] {
            if c.uuid == Self.writeUUID { writeChar = c }
            if c.uuid == Self.notifyUUID { p.setNotifyValue(true, for: c) }
        }
        guard let c = writeChar else {
            status = "Write characteristic missing"
            return
        }
        // biggest single write this link allows (fragment headers must fit in it too).
        // Always the without-response size: the with-response figure (512) relies on
        // "long writes", which this controller doesn't support.
        maxWrite = max(20, min(248, p.maximumWriteValueLength(for: .withoutResponse)))
        isConnected = true
        deviceName = displayName(p)
        status = "Connected"
        addLog("Connected to \(deviceName) — max write \(maxWrite) bytes")
        pump()
    }

    func peripheralIsReady(toSendWriteWithoutResponse p: CBPeripheral) {
        pump()
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor c: CBCharacteristic, error: Error?) {
        awaitingResponse = false
        if let error { addLog("Write failed: \(error.localizedDescription)") }
        pump()
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        if let v = c.value { addLog("← " + v.hex) }
    }
}

extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined(separator: " ") }
}
