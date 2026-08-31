import Foundation
import CoreBluetooth

@MainActor
final class EtekcityScaleManager: NSObject, ObservableObject {
    static let sourceID = "etekcity_ble"

    enum State: Equatable {
        case idle
        case bluetoothUnavailable
        case scanning
        case connecting
        case waitingForMeasurement
        case measured(Double)
        case failed(String)

        var message: String {
            switch self {
            case .idle:
                return "Bereit"
            case .bluetoothUnavailable:
                return "Bluetooth ist nicht verfügbar."
            case .scanning:
                return "Waage wird gesucht … Stell dich auf die Waage."
            case .connecting:
                return "Waage gefunden – Verbindung wird hergestellt …"
            case .waitingForMeasurement:
                return "Verbunden – warte auf einen stabilen Messwert …"
            case .measured(let weight):
                return "Messung übernommen: \(weight.cleanWeight) kg"
            case .failed(let message):
                return message
            }
        }
    }

    @Published private(set) var state: State = .idle

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var timeoutTask: Task<Void, Never>?

    private let notifyCharacteristic = CBUUID(string: "FFF1")
    private let etekcityCompanyID: UInt16 = 1744
    private let esf551ModelID: UInt16 = 2

    var onMeasurement: ((Double) -> Void)?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func startMeasurement() {
        guard central.state == .poweredOn else {
            state = .bluetoothUnavailable
            return
        }

        stop()
        state = .scanning

        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                if case .scanning = self.state {
                    self.fail("Keine ESF-551 gefunden. Öffne VeSync während der Messung nicht und stell dich auf die Waage.")
                } else if case .waitingForMeasurement = self.state {
                    self.fail("Keine stabile Gewichtsmessung empfangen. Bitte erneut auf die Waage stellen.")
                }
            }
        }
    }

    func cancel() {
        stop()
        state = .idle
    }

    private func stop() {
        timeoutTask?.cancel()
        timeoutTask = nil
        central?.stopScan()

        if let peripheral {
            central?.cancelPeripheralConnection(peripheral)
        }

        peripheral = nil
    }

    private func fail(_ message: String) {
        stop()
        state = .failed(message)
    }

    private func isESF551(_ peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
           manufacturerData.count >= 11 {
            let bytes = [UInt8](manufacturerData)
            if bytes.count >= 11 {
                let company = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
                if company == etekcityCompanyID {
                    // CoreBluetooth manufacturerData includes the company identifier in the first 2 bytes.
                    // Etekcity payload: [0]=0x01, [1:7]=MAC LE, [7:9]=model BE16.
                    let payload = Array(bytes.dropFirst(2))
                    if payload.count >= 9,
                       payload[0] == 0x01 {
                        let model = (UInt16(payload[7]) << 8) | UInt16(payload[8])
                        if model == esf551ModelID || model == 1 {
                            return true
                        }
                    }
                }
            }
        }

        let name = (
            advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? peripheral.name
            ?? ""
        ).lowercased()

        return name.contains("etekcity") || name.contains("esf-551") || name.contains("esf551")
    }

    private func parseWeight(_ data: Data) -> Double? {
        let bytes = [UInt8](data)

        guard bytes.count == 22,
              bytes[0] == 0xA5,
              bytes[1] == 0x02,
              bytes[3] == 0x10,
              bytes[4] == 0x00,
              bytes[6] == 0x01,
              bytes[7] == 0x61,
              bytes[8] == 0xA1,
              bytes[9] == 0x00,
              bytes[19] == 0x01 else {
            return nil
        }

        let rawWeight =
            UInt32(bytes[10])
            | (UInt32(bytes[11]) << 8)
            | (UInt32(bytes[12]) << 16)

        let kilograms = Double(rawWeight) / 1000.0
        guard kilograms >= 20, kilograms <= 300 else { return nil }

        return (kilograms * 100).rounded() / 100
    }
}

extension EtekcityScaleManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            if central.state != .poweredOn {
                state = .bluetoothUnavailable
            } else if case .bluetoothUnavailable = state {
                state = .idle
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            guard case .scanning = state,
                  isESF551(peripheral, advertisementData: advertisementData) else {
                return
            }

            self.peripheral = peripheral
            central.stopScan()
            state = .connecting
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            state = .waitingForMeasurement
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            fail("Verbindung zur Waage fehlgeschlagen: \(error?.localizedDescription ?? "Unbekannter Fehler")")
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            guard case .measured = state else {
                if let error {
                    state = .failed("Waage getrennt: \(error.localizedDescription)")
                }
                return
            }
        }
    }
}

extension EtekcityScaleManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error {
                fail("Bluetooth-Dienste konnten nicht gelesen werden: \(error.localizedDescription)")
                return
            }

            for service in peripheral.services ?? [] {
                peripheral.discoverCharacteristics([notifyCharacteristic], for: service)
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                fail("Messkanal konnte nicht gefunden werden: \(error.localizedDescription)")
                return
            }

            if let characteristic = service.characteristics?.first(where: { $0.uuid == notifyCharacteristic }) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            guard error == nil,
                  characteristic.uuid == notifyCharacteristic,
                  let data = characteristic.value,
                  let weight = parseWeight(data) else {
                return
            }

            state = .measured(weight)
            onMeasurement?(weight)

            timeoutTask?.cancel()
            timeoutTask = nil

            // Release BLE immediately so VeSync can reconnect and continue syncing to Apple Health.
            central.cancelPeripheralConnection(peripheral)
            self.peripheral = nil
        }
    }
}
