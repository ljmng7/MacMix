// The runner compiles the real value model and OutputVolumeController with this fake HAL.
nonisolated final class ZeroVolumeHardware: @unchecked Sendable {
    static let shared = ZeroVolumeHardware()
    private let lock = NSLock()
    private var level = 0.5
    private var muted = false
    func setLevel(_ value: Double) { lock.lock(); defer { lock.unlock() }; level = value }
    func setMute(_ value: Bool) { lock.lock(); defer { lock.unlock() }; muted = value }
    func snapshot() -> (Double, Bool) { lock.lock(); defer { lock.unlock() }; return (level, muted) }
}
nonisolated struct CoreAudioHardware {
    func defaultDeviceID(for direction: AudioDeviceDirection) -> AudioObjectID? { 1 }
    func setVolume(_ value: Double, for id: AudioObjectID, direction: AudioDeviceDirection) -> Bool {
        ZeroVolumeHardware.shared.setLevel(value); return true
    }
    func isMuted(for id: AudioObjectID, direction: AudioDeviceDirection) -> Bool? { ZeroVolumeHardware.shared.snapshot().1 }
    @discardableResult func setMuted(_ value: Bool, for id: AudioObjectID, direction: AudioDeviceDirection) -> Bool {
        ZeroVolumeHardware.shared.setMute(value); return true
    }
    func volume(for id: AudioObjectID, direction: AudioDeviceDirection) -> Double? { ZeroVolumeHardware.shared.snapshot().0 }
}
@main struct ZeroVolumeTests {
    @MainActor static func main() async {
        let app = AudioApp(id: "test", pid: 0, bundleID: "test", name: "test", audioObjectIDs: [], icon: nil, volume: 0.0006, isMuted: false)
        let state = AudioAppState(app: app)
        for tiny in [0.0006, 0.00001, 0.0009] {
            state.updateControls(volume: 0, isMuted: false)
            precondition(state.volume == 0)
            precondition(!AudioVolumeValue.matches(0, tiny))
            precondition(!AudioVolumeValue.matches(tiny, 0))
            state.updateControls(volume: tiny, isMuted: false)
            precondition(state.volume == tiny)
        }
        precondition(AudioVolumeValue.matches(0.5, 0.5001)) // Preserve jitter suppression away from zero.
        let controller = OutputVolumeController()
        let zero = await controller.update(deviceID: 1, volume: 0, muted: false)
        precondition(zero?.volume == 0 && zero?.isMuted == true)
        let raised = await controller.update(deviceID: 1, volume: 0.0006, muted: nil)
        precondition(raised?.volume == 0.0006 && raised?.isMuted == false)
        let muteOnly = await controller.update(deviceID: 1, volume: nil, muted: true)
        precondition(muteOnly?.volume == 0.0006 && muteOnly?.isMuted == true)
        let editedThenMuted = await controller.update(deviceID: 1, volume: 0.3, muted: true)
        precondition(editedThenMuted?.volume == 0.3 && editedThenMuted?.isMuted == true)
        let restored = await controller.update(deviceID: 1, volume: 0.4, muted: nil)
        precondition(restored?.volume == 0.4 && restored?.isMuted == false)
        print("Zero volume: exact zero entry/exit, near-zero state updates, hardware mute/unmute and explicit mute passed.")
    }
}
