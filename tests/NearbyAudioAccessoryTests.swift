import Foundation

@main
struct NearbyAudioAccessoryTests {
    // Advertisements captured from AirPods Pro 3 and Beats Solo 4.
    static let airPodsOnMac = bytes("4c 00 07 19 01 27 20 0b aa 8f 10 00 08 48 64 64 ff 36 eb ea 00 00 00 66 1a 7e da 3d 3f")
    static let airPodsOnPhone = bytes("4c 00 07 19 01 27 20 2b aa 8f 11 00 08 08 64 62 ff 67 23 6d 00 00 00 26 10 88 18 3e 5d")
    static let beatsUnowned = bytes("4c 00 07 19 01 25 20 00 04 80 06 00 00 00 29 ff ff 00 00 00 00 00 00 00 10 df 85 e0 da")
    static let airPodsShort = bytes("4c 00 07 11 06 29 20 0f 5b e4 e3 5b 02 00 00 00 00 19 ae 02 00")

    static let mac: [UInt8] = [0x36, 0xEB, 0xEA]
    static let paired = [
        PairedAudioAccessory(address: "30-7a-d2-57-ac-57", name: "AirPods Pro", isConnected: false, appleProductID: 0x2027),
        PairedAudioAccessory(address: "58-36-53-d6-a6-81", name: "Beats Solo 4", isConnected: false, appleProductID: 0x2025),
    ]
    static let others = paired + [
        PairedAudioAccessory(address: "4c-9f-f1-67-23-6d", name: "Pat's iPhone", isConnected: false),
    ]

    static func main() {
        parsesLongForm()
        rejectsOtherFrames()
        matchesAdvertisedNames()
        classifiesOwners()
        hidesConnectedAccessories()
        print("NearbyAudioAccessoryTests passed")
    }

    static func parsesLongForm() {
        let mac = ProximityPairingAdvertisement(manufacturerData: airPodsOnMac)
        precondition(mac?.modelID == 0x2027)
        precondition(mac?.owner == .device(addressSuffix: Self.mac))
        precondition(mac?.catalogModelUID == "2027 4C")
        precondition(ProximityPairingAdvertisement(manufacturerData: beatsUnowned)?.owner == ProximityPairingAdvertisement.Owner.none)
    }

    static func rejectsOtherFrames() {
        // The short frame is also sent from a closed case, so it never means "available".
        precondition(ProximityPairingAdvertisement(manufacturerData: airPodsShort) == nil)
        var notApple = airPodsOnMac
        notApple[0] = 0x4D
        precondition(ProximityPairingAdvertisement(manufacturerData: notApple) == nil)
        precondition(ProximityPairingAdvertisement(manufacturerData: airPodsOnMac.prefix(20)) == nil)
    }

    static func matchesAdvertisedNames() {
        let byModel = NearbyAudioAccessoryMatcher.pairedAccessory(forAdvertisedName:modelID:among:)
        // The paired name "AirPods Pro" differs from the advertised "AirPods Pro 3"; the model decides.
        precondition(byModel("AirPods Pro 3", 0x2027, paired)?.address == "30-7a-d2-57-ac-57")
        precondition(byModel("Beats Studio Pro", 0x2017, paired) == nil)
        let twoPairs = paired + [PairedAudioAccessory(address: "00-11-22-33-44-55", name: "Work AirPods", isConnected: false, appleProductID: 0x2027)]
        precondition(byModel("Work AirPods", 0x2027, twoPairs)?.address == "00-11-22-33-44-55")
        precondition(byModel("AirPods Pro 3", 0x2027, twoPairs) == nil, "Same model, unmatched name must not guess")

        let match = NearbyAudioAccessoryMatcher.pairedAccessory(forAdvertisedName:among:)
        let unknownModels = [
            PairedAudioAccessory(address: "30-7a-d2-57-ac-57", name: "AirPods Pro 3", isConnected: false),
            PairedAudioAccessory(address: "58-36-53-d6-a6-81", name: "Beats Solo 4", isConnected: false),
        ]
        precondition(byModel("AirPods Pro 3", 0x2027, unknownModels)?.address == "30-7a-d2-57-ac-57")
        precondition(match("LE-Pat’s Beats Solo 4", unknownModels)?.address == "58-36-53-d6-a6-81")
        let twins = unknownModels + [PairedAudioAccessory(address: "00-11-22-33-44-55", name: "AirPods Pro 3", isConnected: false)]
        precondition(match("AirPods Pro 3", twins) == nil, "Ambiguous names must not guess")
        let longer = unknownModels + [PairedAudioAccessory(address: "00-11-22-33-44-55", name: "Pat's Beats Solo 4", isConnected: false)]
        precondition(match("LE-Pat's Beats Solo 4", longer)?.address == "00-11-22-33-44-55")
    }

    static func classifiesOwners() {
        let result = nearby([
            "AirPods Pro 3": airPodsOnPhone,
            "LE-Pat's Beats Solo 4": beatsUnowned,
        ])
        precondition(result.map(\.name) == ["AirPods Pro", "Beats Solo 4"])
        precondition(result[0].availability == .inUse(byDeviceNamed: "Pat's iPhone"))
        precondition(result[1].availability == .available)

        var unknownOwner = airPodsOnPhone
        unknownOwner[17] = 0x01
        precondition(nearby(["AirPods Pro 3": unknownOwner])[0].availability == .inUse(byDeviceNamed: nil))
        // Owned by this Mac in the advertisement but no longer linked: offer a reconnect.
        precondition(nearby(["AirPods Pro 3": airPodsOnMac])[0].availability == .available)
    }

    static func hidesConnectedAccessories() {
        precondition(nearby(["AirPods Pro 3": airPodsOnMac], connected: ["307AD257AC57"]).isEmpty)
        // Out of the ears, macOS keeps the link but drops the Core Audio output.
        let linked = [PairedAudioAccessory(address: "30-7a-d2-57-ac-57", name: "AirPods Pro", isConnected: true, appleProductID: 0x2027)]
        precondition(NearbyAudioAccessoryMatcher.nearbyAccessories(
            advertisements: ["AirPods Pro 3": ProximityPairingAdvertisement(manufacturerData: airPodsOnMac)!],
            paired: linked, pairedDevices: linked, localAddressSuffix: mac, connectedOutputAddresses: []
        ).map(\.availability) == [.linkedWithoutOutput])
    }

    static func nearby(_ frames: [String: Data], connected: Set<String> = []) -> [NearbyAudioAccessory] {
        NearbyAudioAccessoryMatcher.nearbyAccessories(
            advertisements: frames.mapValues { ProximityPairingAdvertisement(manufacturerData: $0)! },
            paired: paired,
            pairedDevices: others,
            localAddressSuffix: mac,
            connectedOutputAddresses: connected
        )
    }

    static func bytes(_ hex: String) -> Data {
        Data(hex.split(separator: " ").map { UInt8($0, radix: 16)! })
    }
}
