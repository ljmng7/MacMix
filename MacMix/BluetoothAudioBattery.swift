//
//  BluetoothAudioBattery.swift
//  MacMix
//

import AppKit
import CoreAudio
import CoreBluetooth
import Foundation
import IOBluetooth

nonisolated struct AudioDeviceBattery: Sendable, Equatable {
    let main: Int?
    let left: Int?
    let right: Int?
    let caseLevel: Int?
    let combined: Int?

    var pairedLevel: Int? {
        if let left, let right {
            return min(left, right)
        }

        return left ?? right ?? combined
    }

    var deviceLevel: Int? {
        main ?? pairedLevel
    }

    var hasValue: Bool {
        deviceLevel != nil || caseLevel != nil
    }

    func mergingMissingValues(from other: AudioDeviceBattery) -> AudioDeviceBattery {
        AudioDeviceBattery(
            main: main ?? other.main,
            left: left ?? other.left,
            right: right ?? other.right,
            caseLevel: caseLevel ?? other.caseLevel,
            combined: combined ?? other.combined
        )
    }
}

nonisolated struct BluetoothBatteryRecord: Sendable, Equatable {
    let address: String?
    let normalizedName: String
    let battery: AudioDeviceBattery

    var hasDeviceLevel: Bool {
        battery.deviceLevel != nil
    }
}

nonisolated final class BluetoothBatteryReader: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "MacMix.BluetoothBatteryReader",
        qos: .utility
    )

    func read() async -> [BluetoothBatteryRecord]? {
        guard CBManager.authorization == .allowedAlways else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Self.readSynchronously())
            }
        }
    }

    private static func readSynchronously() -> [BluetoothBatteryRecord]? {
        let profilerRecords = readSystemProfilerRecords()
        let bluetoothRecords = readIOBluetoothRecords()
        guard profilerRecords != nil || bluetoothRecords != nil else {
            return nil
        }

        // Put the richer system_profiler records first. Matching keeps those
        // left/right/case values and fills gaps from IOBluetooth afterward.
        return (profilerRecords ?? []) + (bluetoothRecords ?? [])
    }

    private static func readSystemProfilerRecords() -> [BluetoothBatteryRecord]? {
        let process = Process()
        let standardOutput = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "basic"]
        process.standardOutput = standardOutput
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = standardOutput.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }

        return parse(data)
    }

    private static func parse(_ data: Data) -> [BluetoothBatteryRecord]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let reports = root["SPBluetoothDataType"] as? [[String: Any]] else {
            return nil
        }

        var records: [BluetoothBatteryRecord] = []
        for report in reports {
            guard let connectedDevices = report["device_connected"] as? [[String: Any]] else {
                continue
            }

            for namedDevice in connectedDevices {
                for (name, rawValue) in namedDevice {
                    guard let properties = rawValue as? [String: Any] else {
                        continue
                    }

                    let battery = AudioDeviceBattery(
                        main: percentage(properties["device_batteryLevelMain"]),
                        left: percentage(properties["device_batteryLevelLeft"]),
                        right: percentage(properties["device_batteryLevelRight"]),
                        caseLevel: percentage(properties["device_batteryLevelCase"]),
                        combined: nil
                    )
                    guard battery.hasValue else {
                        continue
                    }

                    records.append(
                        BluetoothBatteryRecord(
                            address: canonicalBluetoothAddress(properties["device_address"] as? String),
                            normalizedName: normalizedAudioAccessoryName(name),
                            battery: battery
                        )
                    )
                }
            }
        }

        return records
    }

    private static func readIOBluetoothRecords() -> [BluetoothBatteryRecord]? {
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() else {
            return nil
        }

        return pairedDevices.compactMap { rawDevice in
            guard let device = rawDevice as? IOBluetoothDevice,
                  device.isConnected() else {
                return nil
            }

            let battery = AudioDeviceBattery(
                main: privateBatteryPercentage(device, key: "batteryPercentSingle"),
                left: privateBatteryPercentage(device, key: "batteryPercentLeft"),
                right: privateBatteryPercentage(device, key: "batteryPercentRight"),
                caseLevel: privateBatteryPercentage(device, key: "batteryPercentCase"),
                combined: privateBatteryPercentage(device, key: "batteryPercentCombined")
            )
            guard battery.hasValue else {
                return nil
            }

            let name = device.nameOrAddress ?? device.addressString ?? ""
            return BluetoothBatteryRecord(
                address: canonicalBluetoothAddress(device.addressString),
                normalizedName: normalizedAudioAccessoryName(name),
                battery: battery
            )
        }
    }

    private static func privateBatteryPercentage(
        _ device: IOBluetoothDevice,
        key: String
    ) -> Int? {
        guard device.responds(to: NSSelectorFromString(key)),
              let number = device.value(forKey: key) as? NSNumber else {
            return nil
        }

        let value = number.intValue
        // These private getters use zero as "not present" for unused fields.
        return (1...100).contains(value) ? value : nil
    }

    private static func percentage(_ rawValue: Any?) -> Int? {
        let value: Int?
        switch rawValue {
        case let number as NSNumber:
            value = number.intValue
        case let string as String:
            value = Int(string.filter(\.isNumber))
        default:
            value = nil
        }

        guard let value, (0...100).contains(value) else {
            return nil
        }
        return value
    }

}

enum BluetoothBatteryMatcher {
    static func batteryByDeviceUID(
        devices: [AudioDevice],
        records: [BluetoothBatteryRecord]
    ) -> [String: AudioDeviceBattery] {
        let recordsByAddress = Dictionary(grouping: records) { $0.address }
        let recordsByName = Dictionary(grouping: records, by: \.normalizedName)
        var result: [String: AudioDeviceBattery] = [:]

        for device in devices {
            let normalizedName = normalizedAudioAccessoryName(device.name)
            var matchedRecords: [BluetoothBatteryRecord] = []

            if let address = canonicalBluetoothAddress(device.uid) {
                matchedRecords = recordsByAddress[address] ?? []
            }

            if matchedRecords.isEmpty {
                let nameMatches = recordsByName[normalizedName] ?? []
                let recordsWithDeviceLevel = nameMatches.filter(\.hasDeviceLevel)
                if recordsWithDeviceLevel.count == 1 {
                    matchedRecords = nameMatches
                }
            } else {
                // Some AirPods expose a second BLE record containing only the case
                // battery. It shares the display name but not the Core Audio address.
                let caseOnlyRecords = (recordsByName[normalizedName] ?? []).filter {
                    !$0.hasDeviceLevel && $0.battery.caseLevel != nil
                }
                matchedRecords.append(contentsOf: caseOnlyRecords)
            }

            guard let battery = mergedBattery(from: matchedRecords), battery.hasValue else {
                continue
            }
            result[device.uid] = battery
        }

        return result
    }

    static func shouldReadBattery(for devices: [AudioDevice]) -> Bool {
        devices.contains { device in
            device.transportType == kAudioDeviceTransportTypeBluetooth
                || device.transportType == kAudioDeviceTransportTypeBluetoothLE
                || device.iconName.hasPrefix("airpods")
                || device.iconName.hasPrefix("beats")
        }
    }

    private static func mergedBattery(
        from records: [BluetoothBatteryRecord]
    ) -> AudioDeviceBattery? {
        records.reduce(nil) { partialResult, record in
            guard let partialResult else {
                return record.battery
            }
            return partialResult.mergingMissingValues(from: record.battery)
        }
    }
}

enum AudioDeviceSFSymbols {
    enum EarbudSide: String {
        case left
        case right
    }

    static func earbudSymbol(deviceSymbolName: String, side: EarbudSide) -> String {
        let suffix = side.rawValue
        let candidates: [String]
        if deviceSymbolName.hasPrefix("airpods.pro") || deviceSymbolName.hasPrefix("airpodspro") {
            candidates = ["\(deviceSymbolName).\(suffix)", "airpods.pro.\(suffix)", "airpodpro.\(suffix)"]
        } else if deviceSymbolName.hasPrefix("airpods.gen4") {
            candidates = ["airpods.gen4.\(suffix)", "airpod.gen3.\(suffix)", "airpod.\(suffix)"]
        } else if deviceSymbolName.hasPrefix("airpods.gen3") {
            candidates = ["airpod.gen3.\(suffix)", "airpod.\(suffix)"]
        } else if deviceSymbolName.hasPrefix("airpods"), usesEarbudsPresentation(deviceSymbolName: deviceSymbolName) {
            candidates = ["airpod.\(suffix)"]
        } else if deviceSymbolName.hasPrefix("beats.powerbeats.pro") || deviceSymbolName.hasPrefix("beats.powerbeatspro") {
            candidates = ["\(deviceSymbolName).\(suffix)", "beats.powerbeats.pro.\(suffix)", "beats.powerbeatspro.\(suffix)"]
        } else if deviceSymbolName.hasPrefix("beats.studiobuds.plus") {
            candidates = ["beats.studiobuds.plus.\(suffix)", "beats.studiobudsplus.\(suffix)", "beats.studiobud.\(suffix)"]
        } else if deviceSymbolName.hasPrefix("beats.studiobuds") {
            candidates = ["beats.studiobuds.\(suffix)", "beats.studiobud.\(suffix)"]
        } else if deviceSymbolName.hasPrefix("beats.solobuds") {
            candidates = ["beats.solobuds.\(suffix)", "beats.studiobud.\(suffix)"]
        } else if deviceSymbolName.hasPrefix("beats.fitpro") {
            candidates = ["beats.fitpro.\(suffix)", "beats.fit.pro.\(suffix)"]
        } else if deviceSymbolName.hasPrefix("beats.powerbeats3") {
            candidates = ["beats.powerbeats3.\(suffix)", "beats.powerbeats.\(suffix)"]
        } else if deviceSymbolName.hasPrefix("beats.powerbeats") {
            candidates = ["beats.powerbeats.\(suffix)"]
        } else {
            candidates = []
        }

        return availableSymbol(
            from: candidates + [side == .left ? "l.circle" : "r.circle"],
            prefersFill: true
        )
    }

    static func deviceSymbol(preferredName: String) -> String {
        availableSymbol(
            from: [preferredName] + deviceFallbacks(for: preferredName),
            prefersFill: true
        )
    }

    static func caseSymbol(deviceSymbolName: String) -> String {
        let candidates: [String]
        if deviceSymbolName.hasPrefix("airpods.pro") || deviceSymbolName.hasPrefix("airpodspro") {
            candidates = [
                "airpodspro.chargingcase.wireless",
                "airpodspro.chargingcase",
                "airpods.chargingcase",
                "case.fill",
            ]
        } else if deviceSymbolName.hasPrefix("airpods") {
            candidates = ["airpods.chargingcase", "case.fill"]
        } else if deviceSymbolName.hasPrefix("beats.fitpro") {
            candidates = ["beats.fitpro.chargingcase", "case.fill"]
        } else if deviceSymbolName.hasPrefix("beats.studiobuds") {
            candidates = ["beats.studiobuds.chargingcase", "case.fill"]
        } else if deviceSymbolName.hasPrefix("beats.solobuds") {
            candidates = ["beats.solobuds.chargingcase", "case.fill"]
        } else if deviceSymbolName.hasPrefix("beats.powerbeats.pro") || deviceSymbolName.hasPrefix("beats.powerbeatspro") {
            candidates = ["beats.powerbeatspro.chargingcase", "case.fill"]
        } else {
            candidates = ["case.fill"]
        }

        return availableSymbol(from: candidates, prefersFill: true)
    }

    static func batterySymbol(level: Int) -> String {
        let clampedLevel = max(0, min(100, level))
        let levelName: String
        switch clampedLevel {
        case ...12:
            levelName = "0"
        case ...37:
            levelName = "25"
        case ...62:
            levelName = "50"
        case ...87:
            levelName = "75"
        default:
            levelName = "100"
        }

        return availableSymbol(
            from: ["battery.\(levelName)percent", "battery.\(levelName)"],
            prefersFill: true
        )
    }

    static func pairedBatterySymbol(
        deviceSymbolName: String,
        level: Int
    ) -> String {
        guard usesEarbudsPresentation(deviceSymbolName: deviceSymbolName) else {
            return batterySymbol(level: level)
        }
        return deviceSymbol(preferredName: deviceSymbolName)
    }

    static func caseBatterySymbol(
        deviceSymbolName: String,
        level: Int
    ) -> String {
        guard hasSpecificCaseSymbol(deviceSymbolName: deviceSymbolName) else {
            return batterySymbol(level: level)
        }
        return caseSymbol(deviceSymbolName: deviceSymbolName)
    }

    static func usesEarbudsPresentation(deviceSymbolName: String) -> Bool {
        if deviceSymbolName.hasPrefix("airpods") {
            return !deviceSymbolName.hasPrefix("airpods.max") && !deviceSymbolName.hasPrefix("airpodsmax")
        }

        return deviceSymbolName.hasPrefix("beats.fitpro")
            || deviceSymbolName.hasPrefix("beats.studiobuds")
            || deviceSymbolName.hasPrefix("beats.solobuds")
            || deviceSymbolName.hasPrefix("beats.powerbeats")
            || deviceSymbolName.hasPrefix("beats.earphones")
    }

    private static func hasSpecificCaseSymbol(deviceSymbolName: String) -> Bool {
        (deviceSymbolName.hasPrefix("airpods")
            && !deviceSymbolName.hasPrefix("airpods.max")
            && !deviceSymbolName.hasPrefix("airpodsmax"))
            || deviceSymbolName.hasPrefix("beats.fitpro")
            || deviceSymbolName.hasPrefix("beats.studiobuds")
            || deviceSymbolName.hasPrefix("beats.solobuds")
            || deviceSymbolName.hasPrefix("beats.powerbeats.pro")
            || deviceSymbolName.hasPrefix("beats.powerbeatspro")
    }

    private static func deviceFallbacks(for symbolName: String) -> [String] {
        // Prefer the older spelling before falling back to a different device.
        // Renamed symbols such as airpods.pro are unavailable on macOS 14.
        if symbolName.hasPrefix("airpods.pro") || symbolName.hasPrefix("airpodspro") {
            return ["airpods.pro", "airpodspro", "airpods", "earbuds", "headphones"]
        }

        if symbolName.hasPrefix("airpods.max") || symbolName.hasPrefix("airpodsmax") {
            return ["airpods.max", "airpodsmax", "headphones"]
        }

        if symbolName.hasPrefix("airpods.gen4") {
            return ["airpods.gen3", "airpods", "earbuds", "headphones"]
        }

        if symbolName.hasPrefix("airpods") {
            return ["airpods", "earbuds", "headphones"]
        }

        if symbolName.hasPrefix("beats.powerbeats.pro") || symbolName.hasPrefix("beats.powerbeatspro") {
            return ["beats.powerbeats.pro", "beats.powerbeatspro", "beats.powerbeats", "earbuds", "headphones"]
        }

        if symbolName.hasPrefix("beats.studiobuds") {
            return ["beats.studiobuds", "earbuds", "headphones"]
        }

        if symbolName.hasPrefix("beats.solobuds") {
            return ["beats.studiobuds", "earbuds", "headphones"]
        }

        if symbolName.hasPrefix("beats.fitpro") {
            return ["earbuds", "headphones"]
        }

        if symbolName.hasPrefix("beats.pill") {
            return ["beats.pill.fill", "beats.pill", "hifispeaker", "speaker", "headphones"]
        }

        if symbolName.hasPrefix("beats") {
            return ["beats.headphones", "headphones"]
        }

        if symbolName.hasPrefix("homepod.mini") || symbolName.hasPrefix("homepodmini") {
            return ["homepod.mini", "homepodmini", "homepod", "hifispeaker", "speaker", "headphones"]
        }

        return ["headphones"]
    }

    private static func availableSymbol(
        from candidates: [String],
        prefersFill: Bool = false
    ) -> String {
        let orderedCandidates = candidates.flatMap { candidate in
            guard prefersFill, !candidate.hasSuffix(".fill") else {
                return [candidate]
            }
            return ["\(candidate).fill", candidate]
        }

        return orderedCandidates.first {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
        } ?? "headphones"
    }
}

nonisolated private func normalizedAudioAccessoryName(_ name: String) -> String {
    name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

nonisolated private func canonicalBluetoothAddress(_ rawValue: String?) -> String? {
    guard let rawValue else {
        return nil
    }

    let addressPortion: Substring
    if let suffixRange = rawValue.range(of: ":output", options: .caseInsensitive) {
        addressPortion = rawValue[..<suffixRange.lowerBound]
    } else {
        addressPortion = rawValue[...]
    }

    let hexadecimalCharacters = addressPortion.uppercased().filter { character in
        character.isHexDigit
    }
    return hexadecimalCharacters.count == 12 ? hexadecimalCharacters : nil
}
