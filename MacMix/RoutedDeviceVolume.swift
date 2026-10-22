import CoreAudio
import Foundation
import Observation

/// Shared by every app row referring to this physical device.
@MainActor @Observable
final class RoutedDeviceVolumeState {
    let deviceID: AudioObjectID
    let uid: String
    private(set) var volume: Double?
    @ObservationIgnored private var revision: UInt64 = 0
    @ObservationIgnored private var worker: RoutedDeviceVolumeWorker?

    init(device: AudioDevice, onReadback: @escaping @MainActor (Double) -> Void) {
        deviceID = device.id
        uid = device.uid
        volume = device.volume
        worker = RoutedDeviceVolumeWorker(deviceID: device.id, uid: device.uid) { [weak self] value, revision in
            Task { @MainActor [weak self] in
                guard let self, self.revision == revision else { return }
                self.volume = value
                if let value { onReadback(value) }
            }
        }
    }

    func setVolume(_ value: Double) {
        guard value.isFinite else { return }
        let value = max(0, min(1, value))
        volume = value
        revision &+= 1
        worker?.submit(value, revision: revision)
    }
}

/// All HAL calls and listener registration run on this queue, never in a slider
/// binding. Notifications merge into the same batch as writes, so readbacks cannot
/// supersede a newer drag value or trigger device/icon enumeration.
nonisolated private final class RoutedDeviceVolumeWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "MacMix.RoutedDeviceVolume", qos: .userInitiated)
    private let deviceID: AudioObjectID
    private let uid: String
    private let onReadback: @Sendable (Double?, UInt64) -> Void
    private var pendingVolume: Double?
    private var revision: UInt64 = 0
    private var scheduled = false
    private var registrations: [AudioObjectPropertyAddress] = []
    private var listener: AudioObjectPropertyListenerBlock?

    init(deviceID: AudioObjectID, uid: String, onReadback: @escaping @Sendable (Double?, UInt64) -> Void) {
        self.deviceID = deviceID
        self.uid = uid
        self.onReadback = onReadback
        queue.async { [weak self] in self?.start() }
    }

    func submit(_ volume: Double, revision: UInt64) {
        queue.async { [weak self] in
            guard let self else { return }
            pendingVolume = volume
            self.revision = revision
            schedule()
        }
    }

    private func start() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.schedule() }
        listener = block
        for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            var address = AudioObjectPropertyAddress(mSelector: selector,
                mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementWildcard)
            if AudioObjectAddPropertyListenerBlock(deviceID, &address, queue, block) == noErr {
                registrations.append(address)
            }
        }
        schedule()
    }

    private func schedule() {
        guard !scheduled else { return }
        scheduled = true
        queue.asyncAfter(deadline: .now() + .milliseconds(16)) { [weak self] in self?.drain() }
    }

    private func drain() {
        scheduled = false
        let value = pendingVolume
        pendingVolume = nil
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var currentUID: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &currentUID) {
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, $0)
        }
        guard status == noErr, currentUID as String? == uid else { onReadback(nil, revision); return }
        let hardware = CoreAudioHardware()
        if let value, hardware.setVolume(value, for: deviceID, direction: .output) {
            let shouldMute = value == 0
            if hardware.isMuted(for: deviceID, direction: .output) != shouldMute {
                hardware.setMuted(shouldMute, for: deviceID, direction: .output)
            }
        }
        onReadback(hardware.volume(for: deviceID, direction: .output), revision)
    }

    deinit {
        let registrations = registrations
        let deviceID = deviceID
        let listener = listener
        let queue = queue
        // Keep the exact queue/block alive until HAL unregisters them.
        queue.async {
            guard let listener else { return }
            for var address in registrations {
                AudioObjectRemovePropertyListenerBlock(deviceID, &address, queue, listener)
            }
        }
    }
}
