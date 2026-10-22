import Foundation
import Observation

enum InputDeviceLockPreference {
    static let isEnabled = "MacMix.Pro.InputDeviceLock.IsEnabled"
    static let deviceUID = "MacMix.Pro.InputDeviceLock.DeviceUID"
}

@MainActor
@Observable
public final class InputDeviceLockController {
    public var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: InputDeviceLockPreference.isEnabled)

            if isEnabled {
                captureCurrentDeviceIfActive()
            } else {
                clearLockedDevice()
            }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let currentDeviceUID: @MainActor () -> String?
    @ObservationIgnored private let availableDeviceUIDs: @MainActor () -> [String]
    @ObservationIgnored private let selectDevice: @MainActor (String) -> Void
    @ObservationIgnored private var lockedDeviceUID: String?
    @ObservationIgnored private var hasProAccess = false

    public init(
        defaults: UserDefaults = .standard,
        currentDeviceUID: @escaping @MainActor () -> String?,
        availableDeviceUIDs: @escaping @MainActor () -> [String],
        selectDevice: @escaping @MainActor (String) -> Void
    ) {
        self.defaults = defaults
        self.currentDeviceUID = currentDeviceUID
        self.availableDeviceUIDs = availableDeviceUIDs
        self.selectDevice = selectDevice
        isEnabled = defaults.bool(forKey: InputDeviceLockPreference.isEnabled)
        lockedDeviceUID = defaults.string(forKey: InputDeviceLockPreference.deviceUID)
    }

    public func updateProAccess(_ hasAccess: Bool) {
        guard hasProAccess != hasAccess else { return }
        hasProAccess = hasAccess

        if hasAccess {
            reconcile()
        }
    }

    public func userSelectedDevice(uid: String) {
        guard isActive else { return }
        lock(to: uid)
    }

    public func inputDevicesDidChange() {
        reconcile()
    }

    private var isActive: Bool {
        isEnabled && hasProAccess
    }

    private func captureCurrentDeviceIfActive() {
        guard isActive else { return }

        if let currentDeviceUID = currentDeviceUID() {
            lock(to: currentDeviceUID)
        } else {
            clearLockedDevice()
        }
    }

    private func reconcile() {
        guard isActive else { return }

        let currentDeviceUID = currentDeviceUID()
        let availableDeviceUIDs = Set(availableDeviceUIDs())

        guard let lockedDeviceUID else {
            if let currentDeviceUID {
                lock(to: currentDeviceUID)
            }
            return
        }

        if availableDeviceUIDs.contains(lockedDeviceUID) {
            if currentDeviceUID != lockedDeviceUID {
                selectDevice(lockedDeviceUID)
            }
            return
        }

        // Once the locked device is unavailable, adopt the system fallback.
        // Reconnecting the old device later must not select it automatically.
        if let currentDeviceUID {
            lock(to: currentDeviceUID)
        }
    }

    private func lock(to deviceUID: String) {
        guard lockedDeviceUID != deviceUID else { return }
        lockedDeviceUID = deviceUID
        defaults.set(deviceUID, forKey: InputDeviceLockPreference.deviceUID)
    }

    private func clearLockedDevice() {
        lockedDeviceUID = nil
        defaults.removeObject(forKey: InputDeviceLockPreference.deviceUID)
    }
}
