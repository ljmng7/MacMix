import CoreAudio
import Foundation

@main
struct DisplayAudioDeviceRecognitionTests {
    static func main() {
        func check(_ name: String, _ transport: UInt32?, displays: [String] = [], model: String? = nil, uid: String? = nil, expected: Bool) {
            let result = DisplayAudioDeviceRecognition.isDisplay(
                name: name, modelUID: model, deviceUID: uid, transportType: transport,
                connectedDisplayNames: displays
            )
            precondition(result == expected, "Unexpected display classification for \(name)")
        }

        // Model-only names do not need an explicit display keyword.
        for name in ["DELL U2723QE", "LG ULTRAGEAR", "BenQ EX2710U", "R27U91", "SAMSUNG"] {
            check(name, kAudioDeviceTransportTypeHDMI, expected: true)
            check(name, kAudioDeviceTransportTypeDisplayPort, expected: true)
        }
        check("DELL U2723QE", kAudioDeviceTransportTypeUSB, displays: ["DELL U2723QE"], expected: true)
        check("LG UltraFine Audio", kAudioDeviceTransportTypeThunderbolt, displays: ["LG UltraFine"], expected: true)
        check("BENQ EX2710U Speakers", kAudioDeviceTransportTypeUSB, displays: ["BenQ EX2710U"], expected: true)
        check("Dell U2723QE", nil, displays: ["DELL-U2723QE"], expected: true)
        check("USB Monitor Audio", kAudioDeviceTransportTypeUSB, expected: true)
        check("顯示器音訊", nil, expected: true)
        check("显示器音频", nil, expected: true)
        check("Digital Audio", nil, uid: "HDMI:0", expected: true)
        check("Digital Audio", nil, model: "DisplayPort Audio", expected: true)

        // Do not mistake a vendor, substring, or transport alone for a monitor.
        check("Dell Speakerphone", kAudioDeviceTransportTypeUSB, displays: ["DELL U2723QE"], expected: false)
        check("LG Headphones", kAudioDeviceTransportTypeBluetooth, displays: ["LG Headphones"], expected: false)
        check("Studio Display", kAudioDeviceTransportTypeBluetoothLE, expected: false)
        check("DELL U2723QE", kAudioDeviceTransportTypeAirPlay, displays: ["DELL U2723QE"], expected: false)
        check("DELL U2723QE", kAudioDeviceTransportTypeAggregate, displays: ["DELL U2723QE"], expected: false)
        check("Universal Audio Apollo", kAudioDeviceTransportTypeThunderbolt, expected: false)
        check("USB DAC", kAudioDeviceTransportTypeUSB, expected: false)
        check("DELL U2723QE Headphones", kAudioDeviceTransportTypeUSB, displays: ["DELL U2723QE"], expected: false)
        check("HDMIfoo", kAudioDeviceTransportTypeUSB, expected: false)
        check("LG", kAudioDeviceTransportTypeUSB, displays: ["LG"], expected: false)
        print("Display audio device recognition tests passed.")
    }
}
