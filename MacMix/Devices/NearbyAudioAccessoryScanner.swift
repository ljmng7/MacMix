//
//  NearbyAudioAccessoryScanner.swift
//  MacMix
//

import CoreBluetooth
import Foundation
import IOBluetooth

// Scans only while an audio interface is visible. It never asks for Bluetooth
// permission itself; without it the nearby section simply stays empty.
@MainActor
final class NearbyAudioAccessoryScanner: NSObject, CBCentralManagerDelegate {
    var onChange: (() -> Void)?
    private(set) var advertisements: [String: ProximityPairingAdvertisement] = [:]

    private var centralManager: CBCentralManager?
    private var lastSeen: [String: Date] = [:]
    private var pruneTimer: Timer?
    private var isActive = false
    // Out-of-case headphones advertise several times per second.
    private let staleInterval: TimeInterval = 8

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        active ? start() : stop()
    }

    private func start() {
        guard CBManager.authorization == .allowedAlways else {
            DiagnosticLog.shared.record("bluetooth", "nearby_scan_skipped", fields: [
                "authorization": String(CBManager.authorization.rawValue)])
            return
        }
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: .main)
        } else {
            beginScanIfPossible()
        }
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pruneStaleAdvertisements() }
        }
    }

    private func stop() {
        centralManager?.stopScan()
        pruneTimer?.invalidate()
        pruneTimer = nil
        lastSeen = [:]
        if !advertisements.isEmpty {
            advertisements = [:]
            onChange?()
        }
    }

    private func beginScanIfPossible() {
        guard isActive, let centralManager, centralManager.state == .poweredOn,
              !centralManager.isScanning else { return }
        DiagnosticLog.shared.record("bluetooth", "nearby_scan_started")
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DiagnosticLog.shared.record("bluetooth", "nearby_central_state", fields: [
            "state": String(central.state.rawValue)])
        beginScanIfPossible()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              let advertisement = ProximityPairingAdvertisement(manufacturerData: data),
              let name = peripheral.name, !name.isEmpty else { return }
        lastSeen[name] = Date()
        guard advertisements[name] != advertisement else { return }
        if advertisements[name] == nil {
            DiagnosticLog.shared.record("bluetooth", "nearby_advertiser_seen", fields: [
                "advertiser": DiagnosticLog.shared.anonymous(name),
                "model": advertisement.catalogModelUID])
        }
        advertisements[name] = advertisement
        onChange?()
    }

    private func pruneStaleAdvertisements() {
        let cutoff = Date().addingTimeInterval(-staleInterval)
        let stale = lastSeen.filter { $0.value < cutoff }.map(\.key)
        guard !stale.isEmpty else { return }
        for name in stale {
            lastSeen[name] = nil
            advertisements[name] = nil
        }
        onChange?()
    }
}

@MainActor
enum PairedBluetoothAccessories {
    static func read() -> (audio: [PairedAudioAccessory], all: [PairedAudioAccessory]) {
        var audio: [PairedAudioAccessory] = []
        var all: [PairedAudioAccessory] = []
        for case let device as IOBluetoothDevice in IOBluetoothDevice.pairedDevices() ?? [] {
            guard let address = device.addressString else { continue }
            let accessory = PairedAudioAccessory(
                address: address,
                name: device.name ?? device.nameOrAddress ?? address,
                isConnected: device.isConnected(),
                appleProductID: appleProductID(of: device)
            )
            all.append(accessory)
            if device.deviceClassMajor == BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorAudio) {
                audio.append(accessory)
            }
        }
        return (audio, all)
    }

    // Private getters, read defensively like the battery ones.
    private static func appleProductID(of device: IOBluetoothDevice) -> UInt16? {
        guard device.responds(to: NSSelectorFromString("vendorID")),
              device.responds(to: NSSelectorFromString("productID")),
              (device.value(forKey: "vendorID") as? NSNumber)?.intValue == 0x4C,
              let productID = (device.value(forKey: "productID") as? NSNumber)?.intValue,
              (1...Int(UInt16.max)).contains(productID) else { return nil }
        return UInt16(productID)
    }

    // The controller address does not change while MacMix runs.
    static let localAddressSuffix: [UInt8]? = {
        guard let address = IOBluetoothHostController.default()?.addressAsString() else { return nil }
        return PairedAudioAccessory(address: address, name: "", isConnected: false).addressSuffix
    }()
}

// Opening the baseband link is what the Bluetooth menu does; the headphones then
// bring up their audio profiles and appear in Core Audio. It also takes them
// back from another device. A link that is already up is left alone: AirPods
// out of the ears keep it and bring their output back once worn, while cycling
// it made that reconnect slow or fail.
@MainActor
final class BluetoothAccessoryConnector: NSObject {
    private var completions: [String: (Bool) -> Void] = [:]

    func connect(address: String, completion: @escaping (Bool) -> Void) {
        guard let device = IOBluetoothDevice(addressString: address) else {
            completion(false)
            return
        }
        guard !device.isConnected() else {
            completion(true)
            return
        }
        completions[address] = completion
        if device.openConnection(self) != kIOReturnSuccess {
            completions.removeValue(forKey: address)?(false)
        }
    }

    @objc func connectionComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        guard let address = device.addressString,
              let completion = completions.removeValue(forKey: address) else { return }
        completion(status == kIOReturnSuccess)
    }
}
