import Foundation
import Observation

/// Mutes notification and alert sounds through the system alert volume, leaving
/// app playback untouched. Sounds an app plays itself are not covered.
@MainActor
@Observable
final class NotificationSoundController {
    private static let alertVolumeKey = "com.apple.sound.beep.volume" as CFString
    private static let lastAudibleVolumeKey = "MacMix.NotificationSoundLastAudibleVolume"

    private(set) var isMuted = false

    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        refresh()
    }

    /// Re-reads the system value, which System Settings can change at any time.
    func refresh() {
        let volume = Self.currentAlertVolume()
        if volume > 0.001 { defaults.set(volume, forKey: Self.lastAudibleVolumeKey) }
        if isMuted != (volume <= 0.001) { isMuted = volume <= 0.001 }
    }

    func toggleMute() {
        let shouldMute = !isMuted
        let restored = defaults.object(forKey: Self.lastAudibleVolumeKey) as? Double ?? 1
        let target = shouldMute ? 0 : max(0.01, min(1, restored))
        DiagnosticLog.shared.record("audio", "notification_sound_mute_requested", fields: ["muted": String(shouldMute)])

        var error: NSDictionary?
        let script = NSAppleScript(source: "set volume alert volume \(Int((target * 100).rounded()))")
        script?.executeAndReturnError(&error)
        if let error {
            DiagnosticLog.shared.record("audio", "notification_sound_mute_failed", level: "error",
                                        fields: ["code": String(describing: error[NSAppleScript.errorNumber] ?? "unknown")])
        }
        refresh()
    }

    private static func currentAlertVolume() -> Double {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let value = CFPreferencesCopyAppValue(alertVolumeKey, kCFPreferencesAnyApplication)
        // An absent key means the system default, full alert volume.
        return (value as? NSNumber)?.doubleValue ?? 1
    }
}
