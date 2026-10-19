//
//  AudioDeviceCatalog.swift
//  MacMix
//

import Foundation
import OSLog

struct AudioDeviceCatalog {
    static let shared = AudioDeviceCatalog()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "MacMix",
        category: "AudioDeviceCatalog"
    )

    private let entryByHardwareID: [HardwareID: Entry]

    init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "AudioDeviceCatalog", withExtension: "json") else {
            Self.logger.error("AudioDeviceCatalog.json is missing from the app bundle.")
            entryByHardwareID = [:]
            return
        }

        do {
            let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
            guard catalog.schemaVersion == 2 else {
                Self.logger.error("Unsupported audio device catalog schema: \(catalog.schemaVersion)")
                entryByHardwareID = [:]
                return
            }

            var indexedEntries: [HardwareID: Entry] = [:]
            for entry in catalog.devices {
                guard let hardwareID = entry.hardwareID else {
                    Self.logger.error(
                        "Invalid hardware identifier in audio device catalog: vendor=\(entry.vendorID, privacy: .public), product=\(entry.productID, privacy: .public)"
                    )
                    continue
                }

                if indexedEntries.updateValue(entry, forKey: hardwareID) != nil {
                    Self.logger.error(
                        "Duplicate hardware identifier in audio device catalog: \(hardwareID.description, privacy: .public)"
                    )
                }
            }
            entryByHardwareID = indexedEntries
        } catch {
            Self.logger.error("Unable to load audio device catalog: \(error.localizedDescription, privacy: .public)")
            entryByHardwareID = [:]
        }
    }

    func symbolName(forModelUID modelUID: String?) -> String? {
        guard let hardwareID = Self.hardwareID(fromModelUID: modelUID) else {
            return nil
        }

        return entryByHardwareID[hardwareID]?.symbolName
    }

    private static func hardwareID(fromModelUID modelUID: String?) -> HardwareID? {
        guard let modelUID else {
            return nil
        }

        let whitespaceComponents = modelUID.split(whereSeparator: \.isWhitespace)
        if whitespaceComponents.count == 2,
           let productID = hexadecimalValue(whitespaceComponents[0]),
           let vendorID = hexadecimalValue(whitespaceComponents[1]) {
            return HardwareID(vendorID: vendorID, productID: productID)
        }

        let colonComponents = modelUID.split(separator: ":")
        if colonComponents.count == 3,
           !colonComponents[0].isEmpty,
           let vendorID = hexadecimalValue(colonComponents[1]),
           let productID = hexadecimalValue(colonComponents[2]) {
            return HardwareID(vendorID: vendorID, productID: productID)
        }

        return nil
    }

    private static func hexadecimalValue(_ component: Substring) -> UInt32? {
        var value = component
        if value.hasPrefix("0x") || value.hasPrefix("0X") {
            value = value.dropFirst(2)
        }

        guard !value.isEmpty,
              value.count <= 8,
              value.allSatisfy(\.isHexDigit) else {
            return nil
        }

        return UInt32(value, radix: 16)
    }
}

private extension AudioDeviceCatalog {
    struct HardwareID: Hashable, CustomStringConvertible {
        let vendorID: UInt32
        let productID: UInt32

        var description: String {
            String(format: "vendor=0x%04X product=0x%04X", vendorID, productID)
        }
    }

    struct Catalog: Decodable {
        let schemaVersion: Int
        let devices: [Entry]
    }

    struct Entry: Decodable {
        let vendorID: String
        let productID: String
        let manufacturer: String
        let model: String
        let symbolName: String

        var hardwareID: HardwareID? {
            guard let vendorID = Self.hexadecimalValue(vendorID),
                  let productID = Self.hexadecimalValue(productID) else {
                return nil
            }

            return HardwareID(vendorID: vendorID, productID: productID)
        }

        private static func hexadecimalValue(_ value: String) -> UInt32? {
            AudioDeviceCatalog.hexadecimalValue(Substring(value))
        }
    }
}
