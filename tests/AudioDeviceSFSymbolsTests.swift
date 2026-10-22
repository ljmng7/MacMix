import Foundation

// Model OS-specific symbol availability while compiling the production resolver.
struct NSImage {
    static var availableNames: Set<String> = []

    init?(systemSymbolName: String, accessibilityDescription: String?) {
        guard Self.availableNames.contains(systemSymbolName) else { return nil }
    }
}

@main
struct AudioDeviceSFSymbolsTests {
    static func main() {
        NSImage.availableNames = [
            "airpodspro", "airpodsmax", "airpods.gen3", "airpods",
            "beats.powerbeatspro", "beats.studiobuds", "beats.fitpro",
            "beats.headphones", "homepodmini", "hifispeaker.fill", "headphones",
            "airpodspro.chargingcase.wireless", "beats.powerbeatspro.chargingcase",
        ]
        let macOS14Fallbacks = [
            "airpods.pro": "airpodspro",
            "airpods.pro.gen1": "airpodspro",
            "airpods.pro.gen3": "airpodspro",
            "airpods.max": "airpodsmax",
            "airpods.gen4": "airpods.gen3",
            "beats.powerbeats.pro": "beats.powerbeatspro",
            "beats.powerbeats.pro.2": "beats.powerbeatspro",
            "beats.studiobuds.plus": "beats.studiobuds",
            "beats.solobuds": "beats.studiobuds",
            "beats.pill.fill": "hifispeaker.fill",
            "beats.pill": "hifispeaker.fill",
            "homepod.mini": "homepodmini",
        ]
        for (preferred, expected) in macOS14Fallbacks {
            expect(AudioDeviceSFSymbols.deviceSymbol(preferredName: preferred), expected)
        }
        expect(AudioDeviceSFSymbols.caseSymbol(deviceSymbolName: "airpodspro"), "airpodspro.chargingcase.wireless")
        expect(AudioDeviceSFSymbols.caseSymbol(deviceSymbolName: "beats.powerbeatspro"), "beats.powerbeatspro.chargingcase")
        precondition(!AudioDeviceSFSymbols.usesEarbudsPresentation(deviceSymbolName: "airpodsmax"))
        precondition(!AudioDeviceSFSymbols.usesEarbudsPresentation(deviceSymbolName: "airpods.max"))

        NSImage.availableNames.formUnion(["beats.pill.fill", "beats.solobuds"])
        expect(AudioDeviceSFSymbols.deviceSymbol(preferredName: "beats.pill"), "beats.pill.fill")
        expect(AudioDeviceSFSymbols.deviceSymbol(preferredName: "beats.solobuds"), "beats.solobuds")

        NSImage.availableNames.formUnion(["airpods.pro", "airpods.max", "beats.powerbeats.pro", "homepod.mini"])
        for name in ["airpods.pro", "airpods.max", "beats.powerbeats.pro", "homepod.mini"] {
            expect(AudioDeviceSFSymbols.deviceSymbol(preferredName: name), name)
        }
        expect(AudioDeviceSFSymbols.deviceSymbol(preferredName: "airpods.gen4"), "airpods.gen3")
        NSImage.availableNames.insert("airpods.gen4")
        expect(AudioDeviceSFSymbols.deviceSymbol(preferredName: "airpods.gen4"), "airpods.gen4")
        NSImage.availableNames.insert("beats.powerbeats.pro.2")
        expect(AudioDeviceSFSymbols.deviceSymbol(preferredName: "beats.powerbeats.pro.2"), "beats.powerbeats.pro.2")
        NSImage.availableNames.insert("airpods.pro.gen3")
        expect(AudioDeviceSFSymbols.deviceSymbol(preferredName: "airpods.pro.gen3"), "airpods.pro.gen3")
        expect(AudioDeviceSFSymbols.deviceSymbol(preferredName: "unknown.device"), "headphones")

        NSImage.availableNames = [
            "airpodpro.left", "airpodpro.right", "airpod.gen3.left", "airpod.gen3.right",
            "beats.powerbeatspro.left", "beats.powerbeatspro.right",
            "beats.studiobud.left", "beats.studiobud.right",
            "beats.studiobudsplus.left", "beats.studiobudsplus.right",
            "beats.fitpro.left", "beats.fitpro.right", "l.circle", "r.circle",
        ]
        let sideFallbacks = [
            "airpods.pro.gen3": "airpodpro",
            "airpods.gen4": "airpod.gen3",
            "beats.powerbeats.pro.2": "beats.powerbeatspro",
            "beats.studiobuds": "beats.studiobud",
            "beats.studiobuds.plus": "beats.studiobudsplus",
            "beats.solobuds": "beats.studiobud",
            "beats.fitpro": "beats.fitpro",
        ]
        for (preferred, expectedBase) in sideFallbacks {
            for side in [AudioDeviceSFSymbols.EarbudSide.left, .right] {
                expect(AudioDeviceSFSymbols.earbudSymbol(deviceSymbolName: preferred, side: side), "\(expectedBase).\(side.rawValue)")
            }
        }
        expect(AudioDeviceSFSymbols.earbudSymbol(deviceSymbolName: "unknown.device", side: .left), "l.circle")
        expect(AudioDeviceSFSymbols.earbudSymbol(deviceSymbolName: "unknown.device", side: .right), "r.circle")
        for side in [AudioDeviceSFSymbols.EarbudSide.left, .right] {
            let modern = "airpods.pro.gen3.\(side.rawValue)"
            NSImage.availableNames.insert(modern)
            expect(AudioDeviceSFSymbols.earbudSymbol(deviceSymbolName: "airpods.pro.gen3", side: side), modern)
        }
        print("Audio device symbol compatibility tests passed.")
    }

    static func expect(_ actual: String, _ expected: String) {
        precondition(actual == expected, "Expected \(expected), got \(actual)")
    }
}
