import Foundation

@main
struct AudioDeviceCatalogTests {
    static func main() {
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        guard let bundle = Bundle(url: resources) else { preconditionFailure("Missing catalog bundle") }
        let catalog = AudioDeviceCatalog(bundle: bundle)

        // Bluetooth model UIDs are "product vendor"; USB model UIDs end in ":vendor:product".
        expect(catalog.symbolName(forModelUID: "2014 4C"), "airpods.pro")
        expect(catalog.symbolName(forModelUID: "0x200A 0x004C"), "airpods.max")
        expect(catalog.symbolName(forModelUID: "AppleUSBAudioEngine:004C:200A"), "airpods.max")
        expect(catalog.symbolName(forModelUID: "0000 0000"), nil)
        expect(catalog.symbolName(forModelUID: "not-a-model"), nil)
        expect(catalog.symbolName(forModelUID: nil), nil)
        expect(AudioDeviceCatalog(bundle: Bundle(url: URL(fileURLWithPath: CommandLine.arguments[2]))!)
            .symbolName(forModelUID: "2014 4C"), nil)
        print("Audio device catalog: model UID formats, unknown devices and a missing catalog passed.")
    }

    static func expect(_ actual: String?, _ expected: String?) {
        precondition(actual == expected, "Expected \(expected ?? "nil"), got \(actual ?? "nil")")
    }
}
