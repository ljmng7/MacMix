//
//  NearbyAudioAccessories.swift
//  MacMix
//

import Foundation

// Apple headphones (AirPods and Beats) keep broadcasting a proximity-pairing
// advertisement while they are out of a closed case, including while another
// device owns the connection or nothing does. Core Audio only lists connected
// outputs, so this is how MacMix offers headphones that dropped off the list.
nonisolated struct ProximityPairingAdvertisement: Equatable, Sendable {
    enum Owner: Equatable, Sendable {
        case none
        case device(addressSuffix: [UInt8])
    }

    let modelID: UInt16
    let owner: Owner

    // Manufacturer data: 4C 00 | 07 | 19 | 01 | model (LE) | … | owner address suffix at 17…19.
    // The 21-byte variant carries no owner and is also sent from a closed case,
    // so only the long form counts as "available".
    init?(manufacturerData data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 29,
              bytes[0] == 0x4C, bytes[1] == 0x00,
              bytes[2] == 0x07, bytes[3] == 0x19,
              bytes[4] == 0x01 else {
            return nil
        }

        modelID = UInt16(bytes[5]) | UInt16(bytes[6]) << 8
        let suffix = Array(bytes[17...19])
        owner = suffix == [0, 0, 0] ? .none : .device(addressSuffix: suffix)
    }

    // Matches the "productID vendorID" form AudioDeviceCatalog understands.
    var catalogModelUID: String {
        String(format: "%04X 4C", modelID)
    }
}

nonisolated struct PairedAudioAccessory: Equatable, Sendable {
    let address: String
    let name: String
    let isConnected: Bool
    // Apple product ID, the same value as the advertisement's model.
    var appleProductID: UInt16? = nil

    var addressSuffix: [UInt8]? {
        let octets = address.split(whereSeparator: { $0 == "-" || $0 == ":" }).compactMap { UInt8($0, radix: 16) }
        guard octets.count == 6 else { return nil }
        return Array(octets.suffix(3))
    }
}

nonisolated struct NearbyAudioAccessory: Identifiable, Equatable, Sendable {
    enum Availability: Equatable, Sendable {
        case available
        // The Bluetooth link is still up but Core Audio removed the output,
        // as macOS does when both AirPods leave the ears.
        case linkedWithoutOutput
        // The name is nil when the owner is not one of this Mac's paired devices.
        case inUse(byDeviceNamed: String?)

        var diagnosticName: String {
            switch self {
            case .available: "available"
            case .linkedWithoutOutput: "linked_without_output"
            case .inUse: "in_use"
            }
        }
    }

    var id: String { address }
    let address: String
    let name: String
    let modelUID: String
    let availability: Availability
}

nonisolated enum NearbyAudioAccessoryMatcher {
    // The LE name can differ from the classic paired name ("AirPods Pro 3" for
    // "AirPods Pro", "LE-Pat's Beats Solo 4" for "Beats Solo 4"), so the model
    // decides and the name only separates several headphones of one model.
    static func pairedAccessory(
        forAdvertisedName advertisedName: String,
        modelID: UInt16,
        among accessories: [PairedAudioAccessory]
    ) -> PairedAudioAccessory? {
        let sameModel = accessories.filter { $0.appleProductID == modelID }
        if sameModel.count == 1 {
            return sameModel[0]
        }
        return pairedAccessory(
            forAdvertisedName: advertisedName,
            among: sameModel.isEmpty ? accessories.filter { $0.appleProductID == nil } : sameModel
        )
    }

    // Prefer an exact name, then the single longest paired name the advertised name ends with.
    static func pairedAccessory(
        forAdvertisedName advertisedName: String,
        among accessories: [PairedAudioAccessory]
    ) -> PairedAudioAccessory? {
        let advertised = normalized(advertisedName, dropsLEPrefix: true)
        guard !advertised.isEmpty else { return nil }

        let exact = accessories.filter { normalized($0.name) == advertised }
        if !exact.isEmpty {
            return exact.count == 1 ? exact[0] : nil
        }

        let suffixMatches = accessories.filter {
            let name = normalized($0.name)
            return !name.isEmpty && advertised.hasSuffix(name)
        }
        guard let longest = suffixMatches.map({ normalized($0.name).count }).max() else { return nil }
        let best = suffixMatches.filter { normalized($0.name).count == longest }
        return best.count == 1 ? best[0] : nil
    }

    static func nearbyAccessories(
        advertisements: [String: ProximityPairingAdvertisement],
        paired: [PairedAudioAccessory],
        pairedDevices allPaired: [PairedAudioAccessory],
        localAddressSuffix: [UInt8]?,
        connectedOutputAddresses: Set<String>
    ) -> [NearbyAudioAccessory] {
        var result: [String: NearbyAudioAccessory] = [:]

        for (advertisedName, advertisement) in advertisements {
            guard let accessory = pairedAccessory(
                      forAdvertisedName: advertisedName, modelID: advertisement.modelID, among: paired),
                  !connectedOutputAddresses.contains(canonical(accessory.address)) else {
                continue
            }

            let availability: NearbyAudioAccessory.Availability
            switch advertisement.owner {
            case _ where accessory.isConnected:
                availability = .linkedWithoutOutput
            case .none:
                availability = .available
            case let .device(suffix) where suffix == localAddressSuffix:
                // This Mac still owns it in the advertisement but has already dropped
                // the link; reconnecting is the right offer.
                availability = .available
            case let .device(suffix):
                let owner = allPaired.first { $0.addressSuffix == suffix }
                availability = .inUse(byDeviceNamed: owner?.name)
            }

            result[accessory.address] = NearbyAudioAccessory(
                address: accessory.address,
                name: accessory.name,
                modelUID: advertisement.catalogModelUID,
                availability: availability
            )
        }

        return result.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func canonical(_ address: String) -> String {
        address.uppercased().filter(\.isHexDigit)
    }

    private static func normalized(_ name: String, dropsLEPrefix: Bool = false) -> String {
        var value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if dropsLEPrefix, value.uppercased().hasPrefix("LE-") {
            value = String(value.dropFirst(3))
        }
        return value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "’", with: "'")
    }
}
