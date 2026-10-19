import AppKit

// Renamed symbols such as airpods.pro are unavailable on macOS 14, so device
// icons resolve to the closest symbol the running system provides.
enum AudioDeviceSFSymbols {
    static func deviceSymbol(preferredName: String) -> String {
        availableSymbol(
            from: [preferredName] + deviceFallbacks(for: preferredName),
            prefersFill: true
        )
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
