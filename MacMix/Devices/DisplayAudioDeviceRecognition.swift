import CoreAudio
import Foundation

nonisolated enum DisplayAudioDeviceRecognition {
    static func isDisplay(
        name: String,
        modelUID: String?,
        deviceUID: String?,
        transportType: UInt32?,
        connectedDisplayNames: [String]
    ) -> Bool {
        if transportType == kAudioDeviceTransportTypeHDMI
            || transportType == kAudioDeviceTransportTypeDisplayPort {
            return true
        }

        // A Bluetooth accessory or network receiver can share a monitor's name.
        if let transportType,
           ![kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeThunderbolt,
             kAudioDeviceTransportTypeUnknown].contains(transportType) {
            return false
        }

        let identityText = normalized([name, modelUID, deviceUID].compactMap { $0 }.joined(separator: " "))
        let tokens = Set(identityText.split(separator: " ").map(String.init))
        if !tokens.isDisjoint(with: ["display", "monitor", "hdmi", "displayport"])
            || identityText.contains("显示器") || identityText.contains("顯示器") {
            return true
        }

        // Match the connected monitor's actual model rather than a vendor list:
        // display vendors also sell headphones, docks, and audio interfaces.
        let audioName = normalized(name)
        return connectedDisplayNames.contains { displayName in
            let displayName = normalized(displayName)
            guard displayName.count >= 4 else { return false }
            if audioName == displayName { return true }
            return ["audio", "speaker", "speakers"].contains { suffix in
                audioName == "\(displayName) \(suffix)"
            }
        }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }
}
