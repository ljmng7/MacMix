import AppKit
import Foundation

@main
struct MacBuiltInSpeakerIconTests {
    static func main() {
        let cases: [(String?, String?, String)] = [
            ("MacBook Pro (14-inch, Nov 2024)", "Mac16,1", "macbook"),
            ("MacBook Air", "Mac15,12", "macbook"),
            (nil, "MacBook10,1", "macbook"),
            (nil, "MacBookAir10,1", "macbook"),
            (nil, "MacBookPro18,3", "macbook"),
            ("Mac mini (2024)", "Mac16,10", "macmini"),
            (nil, "Macmini8,1", "macmini"),
            ("Mac Studio", "Mac13,1", "macstudio"),
            ("iMac", "Mac15,4", "desktopcomputer"),
            (nil, "iMac20,1", "desktopcomputer"),
            (nil, "iMacPro1,1", "desktopcomputer"),
            ("Mac Pro", "MacPro5,1", "macpro.gen1"),
            (nil, "MacPro6,1", "macpro.gen2"),
            (nil, "MacPro7,1", "macpro.gen3"),
            ("Mac Pro", "Mac14,8", "macpro.gen3"),
            ("Mac Pro (Rack)", "Mac14,8", "macpro.gen3.server"),
            (nil, "Xserve3,1", "xserve"),
            (nil, "Mac99,1", "speaker.wave.2.fill"),
            (nil, nil, "speaker.wave.2.fill"),
        ]
        for (product, model, expected) in cases {
            let actual = MacBuiltInSpeakerIcon.symbol(productName: product, modelIdentifier: model)
            precondition(actual == expected, "Wrong icon for \(product ?? model ?? "unknown"): \(actual)")
            precondition(NSImage(systemSymbolName: actual, accessibilityDescription: nil) != nil)
        }
        print("Mac built-in speaker icon tests passed (\(cases.count) cases).")
        print("Current Mac symbol: \(MacBuiltInSpeakerIcon.currentSymbol)")
    }
}
