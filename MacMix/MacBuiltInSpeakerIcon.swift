import Darwin
import Foundation
import IOKit

nonisolated enum MacBuiltInSpeakerIcon {
    // Hardware identity is fixed for this process; do not query IOKit per row.
    static let currentSymbol = symbol(productName: productName(), modelIdentifier: modelIdentifier())

    static func symbol(productName: String?, modelIdentifier: String?) -> String {
        let product = (productName ?? "").lowercased()
        let model = (modelIdentifier ?? "").lowercased()
        if product.contains("macbook") || model.hasPrefix("macbook") {
            return "macbook"
        }
        if product.contains("mac mini") || model.hasPrefix("macmini") {
            return "macmini"
        }
        if product.contains("mac studio") || model.hasPrefix("macstudio") {
            return "macstudio"
        }
        if product.contains("imac") || model.hasPrefix("imac") {
            return "desktopcomputer"
        }
        if product.contains("mac pro") || model.hasPrefix("macpro") {
            if product.contains("rack") { return "macpro.gen3.server" }
            if model == "macpro6,1" { return "macpro.gen2" }
            if ["macpro1,", "macpro2,", "macpro3,", "macpro4,", "macpro5,"].contains(where: model.hasPrefix) {
                return "macpro.gen1"
            }
            return "macpro.gen3"
        }
        if product.contains("xserve") || model.hasPrefix("xserve") {
            return "xserve"
        }
        // Unknown hardware should not be presented as a MacBook.
        return "speaker.wave.2.fill"
    }

    private static func productName() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(entry) }
        guard let property = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }
        if let name = property as? String { return name }
        guard let data = property as? Data else { return nil }
        return String(data: data.prefix { $0 != 0 }, encoding: .utf8)
    }

    private static func modelIdentifier() -> String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
