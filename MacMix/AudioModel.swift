//
//  AudioModel.swift
//  MacMix
//
//  Created by Jazmin on 2026/6/29.
//

import AppKit
import Combine
import CoreAudio
import Foundation

@MainActor
final class OutputAudioState: ObservableObject {
    @Published var devices: [AudioDevice] = []
    @Published var systemVolume: Double = 0

    var currentDevice: AudioDevice? {
        devices.first(where: \.isCurrent)
    }

    var menuBarSymbolName: String {
        if systemVolume <= 0.001 {
            return "speaker.slash.fill"
        }

        if systemVolume < 0.34 {
            return "speaker.wave.1.fill"
        }

        if systemVolume < 0.67 {
            return "speaker.wave.2.fill"
        }

        return "speaker.wave.3.fill"
    }
}

@MainActor
final class InputAudioState: ObservableObject {
    @Published var devices: [AudioDevice] = []
    @Published var inputVolume: Double = 0

    var currentDevice: AudioDevice? {
        devices.first(where: \.isCurrent)
    }
}

@MainActor
final class OutputAppsState: ObservableObject {
    @Published var apps: [AudioApp] = []
    @Published var needsSystemAudioPermission = false
    @Published var isSystemAudioPermissionAuthorized = false
}

@MainActor
final class AudioModel: NSObject, ObservableObject {
    let outputState = OutputAudioState()
    let inputState = InputAudioState()
    let outputAppsState = OutputAppsState()

    private let hardware = CoreAudioHardware()
    private let appAudioMixer = AppAudioMixer.shared
    private let defaults = UserDefaults.standard
    private var deviceObserver: CoreAudioDeviceObserver?
    private var refreshTimer: Timer?
    private var pendingOutputApps: [AudioApp]?
    private var outputAppRefreshSuppressedUntil: Date?
    private var outputRouteRefreshTask: Task<Void, Never>?
    private let systemAudioPermissionNeedsAuthorizationKey = "MacMix.SystemAudioPermissionNeedsAuthorization"
    private let systemAudioPermissionAuthorizedKey = "MacMix.SystemAudioPermissionAuthorized"

    override init() {
        super.init()
        restoreCachedSystemAudioPermissionState()

        deviceObserver = CoreAudioDeviceObserver(
            onOutputChange: { [weak self] in
                self?.refreshOutputState()
            },
            onInputChange: { [weak self] in
                self?.refreshInputState()
            }
        )

        deviceObserver?.start()
        refresh()
        refreshTimer = Timer.scheduledTimer(
            timeInterval: 1,
            target: self,
            selector: #selector(refreshFromTimer),
            userInfo: nil,
            repeats: true
        )
    }

    deinit {
        deviceObserver?.stop()
        refreshTimer?.invalidate()
        outputRouteRefreshTask?.cancel()
        appAudioMixer.stopAll()
    }

    var currentOutputDevice: AudioDevice? {
        outputState.currentDevice
    }

    var currentInputDevice: AudioDevice? {
        inputState.currentDevice
    }

    func refresh() {
        refreshOutputState()
        refreshInputState()
        refreshOutputApps(stabilize: false)
    }

    func refreshOutputState() {
        let previousOutputUID = currentOutputDevice?.uid
        let devices = hardware.devices(for: .output)
        setOutputDevicesIfChanged(devices)

        if let outputVolume = devices.first(where: \.isCurrent)?.volume {
            setSystemOutputVolumeIfChanged(outputVolume)
        }

        let currentOutputUID = devices.first(where: \.isCurrent)?.uid

        if let previousOutputUID, previousOutputUID != currentOutputUID {
            handleOutputRouteChange()
        }
    }

    func refreshInputState() {
        let devices = hardware.devices(for: .input)
        setInputDevicesIfChanged(devices)

        if let inputVolume = devices.first(where: \.isCurrent)?.volume {
            setInputVolumeIfChanged(inputVolume)
        }
    }

    func refreshOutputApps(stabilize: Bool = true) {
        if let outputAppRefreshSuppressedUntil,
           Date() < outputAppRefreshSuppressedUntil {
            return
        }

        let apps = hardware.runningOutputApps { [weak self] bundleID in
            self?.storedAppVolume(for: bundleID) ?? 1
        }

        guard !audioAppsMatch(outputAppsState.apps, apps) else {
            pendingOutputApps = nil
            reconcileOutputApps()
            return
        }

        if stabilize {
            guard let pendingOutputApps,
                  audioAppsMatch(pendingOutputApps, apps) else {
                pendingOutputApps = apps
                return
            }
        }

        pendingOutputApps = nil
        outputAppsState.apps = apps
        reconcileOutputApps()
    }

    func requestSystemAudioPermissionIfNeeded() {
        let permissionAvailable = appAudioMixer.requestSystemAudioPermissionIfNeeded()
        handleSystemAudioPermissionRequest(permissionAvailable)
    }

    func requestSystemAudioPermission() {
        let permissionAvailable = appAudioMixer.requestSystemAudioPermission()
        handleSystemAudioPermissionRequest(permissionAvailable)
    }

    func openSystemAudioRecordingSettingsForAuthorization() {
        let privacyURLs = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy",
        ]

        for privacyURL in privacyURLs {
            guard let url = URL(string: privacyURL),
                  NSWorkspace.shared.open(url) else {
                continue
            }

            return
        }
    }

    @objc private func refreshFromTimer() {
        refreshOutputApps()
    }

    func setSystemOutputVolume(_ volume: Double) {
        setSystemOutputVolumeIfChanged(volume)
        guard let deviceID = currentOutputDevice?.id else {
            return
        }

        hardware.setVolume(volume, for: deviceID, direction: .output)
        setCurrentOutputDeviceVolume(volume)
    }

    func setInputVolume(_ volume: Double) {
        setInputVolumeIfChanged(volume)
        guard let deviceID = currentInputDevice?.id else {
            return
        }

        hardware.setVolume(volume, for: deviceID, direction: .input)
        setCurrentInputDeviceVolume(volume)
    }

    func selectOutputDevice(_ device: AudioDevice) {
        guard !device.isCurrent else {
            return
        }

        hardware.setDefaultDevice(device.id, direction: .output)
        refreshOutputState()
    }

    func selectInputDevice(_ device: AudioDevice) {
        guard !device.isCurrent else {
            return
        }

        hardware.setDefaultDevice(device.id, direction: .input)
        refreshInputState()
    }

    func setAppVolume(_ volume: Double, for app: AudioApp) {
        let clampedVolume = max(0, min(maximumAppVolume, volume))
        defaults.set(clampedVolume, forKey: defaultsKey(for: app.bundleID))

        if let index = outputAppsState.apps.firstIndex(where: { $0.id == app.id }) {
            var apps = outputAppsState.apps
            guard !nearlyEqual(apps[index].volume, clampedVolume) else {
                return
            }

            apps[index].volume = clampedVolume
            outputAppsState.apps = apps
            updateSystemAudioPermissionAfterMixAttempt(
                appAudioMixer.apply(
                    clampedVolume,
                    to: apps[index],
                    outputDeviceUID: currentOutputDevice?.uid
                ),
                requiresPermission: appVolumeRequiresSystemAudioPermission(clampedVolume),
                requestAuthorizationIfDenied: true
            )
        } else {
            var updatedApp = app
            updatedApp.volume = clampedVolume
            updateSystemAudioPermissionAfterMixAttempt(
                appAudioMixer.apply(
                    clampedVolume,
                    to: updatedApp,
                    outputDeviceUID: currentOutputDevice?.uid
                ),
                requiresPermission: appVolumeRequiresSystemAudioPermission(clampedVolume),
                requestAuthorizationIfDenied: true
            )
        }
    }

    func clampAppVolumesToUnity() {
        for app in outputAppsState.apps where app.volume > 1 {
            setAppVolume(1, for: app)
        }
    }

    private func reconcileOutputApps() {
        updateSystemAudioPermissionAfterMixAttempt(
            appAudioMixer.reconcile(
                apps: outputAppsState.apps,
                outputDeviceUID: currentOutputDevice?.uid
            ),
            requiresPermission: activeOutputMixRequiresSystemAudioPermission,
            requestAuthorizationIfDenied: false
        )
    }

    private func updateSystemAudioPermissionAfterMixAttempt(
        _ isMixingAvailable: Bool,
        requiresPermission: Bool,
        requestAuthorizationIfDenied: Bool
    ) {
        guard !isMixingAvailable else {
            if requiresPermission {
                setSystemAudioPermissionAuthorized(true)
            }
            setNeedsSystemAudioPermission(false)
            return
        }

        if requiresPermission {
            setSystemAudioPermissionAuthorized(false)
            setNeedsSystemAudioPermission(true)

            if requestAuthorizationIfDenied {
                requestSystemAudioPermission()
            }
        } else {
            setNeedsSystemAudioPermission(false)
        }
    }

    private func suppressOutputAppRefresh() {
        pendingOutputApps = nil
        outputAppRefreshSuppressedUntil = Date().addingTimeInterval(1.25)
    }

    private func handleOutputRouteChange() {
        pendingOutputApps = nil
    }

    private func prepareForOutputRouteChange() {
        suppressOutputAppRefresh()
        appAudioMixer.stopAll()
    }

    private func refreshOutputAppsAfterRouteSettles() {
        outputRouteRefreshTask?.cancel()
        outputRouteRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            guard !Task.isCancelled else {
                return
            }

            self?.refreshOutputApps(stabilize: false)
        }
    }

    private func setOutputDevicesIfChanged(_ devices: [AudioDevice]) {
        guard outputState.devices != devices else {
            return
        }

        outputState.devices = devices
    }

    private func setInputDevicesIfChanged(_ devices: [AudioDevice]) {
        guard inputState.devices != devices else {
            return
        }

        inputState.devices = devices
    }

    private func setCurrentOutputDeviceVolume(_ volume: Double) {
        let devices = devicesWithCurrentVolume(volume, in: outputState.devices)
        setOutputDevicesIfChanged(devices)
    }

    private func setCurrentInputDeviceVolume(_ volume: Double) {
        let devices = devicesWithCurrentVolume(volume, in: inputState.devices)
        setInputDevicesIfChanged(devices)
    }

    private func devicesWithCurrentVolume(_ volume: Double, in devices: [AudioDevice]) -> [AudioDevice] {
        var updatedDevices = devices
        guard let index = devices.firstIndex(where: \.isCurrent),
              let existingVolume = devices[index].volume,
              !nearlyEqual(existingVolume, volume) else {
            return devices
        }

        let device = devices[index]
        updatedDevices[index] = AudioDevice(
            id: device.id,
            uid: device.uid,
            name: device.name,
            iconName: device.iconName,
            isCurrent: device.isCurrent,
            volume: volume
        )

        return updatedDevices
    }

    private func setSystemOutputVolumeIfChanged(_ volume: Double) {
        guard !nearlyEqual(outputState.systemVolume, volume) else {
            return
        }

        outputState.systemVolume = volume
    }

    private func setInputVolumeIfChanged(_ volume: Double) {
        guard !nearlyEqual(inputState.inputVolume, volume) else {
            return
        }

        inputState.inputVolume = volume
    }

    private func setNeedsSystemAudioPermission(_ isNeeded: Bool) {
        if outputAppsState.needsSystemAudioPermission != isNeeded {
            outputAppsState.needsSystemAudioPermission = isNeeded
        }

        defaults.set(isNeeded, forKey: systemAudioPermissionNeedsAuthorizationKey)
    }

    private func setSystemAudioPermissionAuthorized(_ isAuthorized: Bool) {
        if outputAppsState.isSystemAudioPermissionAuthorized != isAuthorized {
            outputAppsState.isSystemAudioPermissionAuthorized = isAuthorized
        }

        defaults.set(isAuthorized, forKey: systemAudioPermissionAuthorizedKey)
    }

    private func handleSystemAudioPermissionRequest(_ permissionAvailable: Bool) {
        if permissionAvailable {
            setSystemAudioPermissionAuthorized(true)
            setNeedsSystemAudioPermission(false)
            reconcileOutputApps()
        } else {
            setSystemAudioPermissionAuthorized(false)
            setNeedsSystemAudioPermission(true)
        }
    }

    private func restoreCachedSystemAudioPermissionState() {
        if defaults.object(forKey: systemAudioPermissionNeedsAuthorizationKey) != nil {
            outputAppsState.needsSystemAudioPermission = defaults.bool(forKey: systemAudioPermissionNeedsAuthorizationKey)
        }

        if defaults.object(forKey: systemAudioPermissionAuthorizedKey) != nil {
            outputAppsState.isSystemAudioPermissionAuthorized = defaults.bool(forKey: systemAudioPermissionAuthorizedKey)
        }
    }

    private var activeOutputMixRequiresSystemAudioPermission: Bool {
        outputAppsState.apps.contains { appVolumeRequiresSystemAudioPermission($0.volume) }
    }

    private func appVolumeRequiresSystemAudioPermission(_ volume: Double) -> Bool {
        !nearlyEqual(volume, 1)
    }

    private func audioAppsMatch(_ lhs: [AudioApp], _ rhs: [AudioApp]) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }

        return zip(lhs, rhs).allSatisfy { lhsApp, rhsApp in
            lhsApp.id == rhsApp.id
                && lhsApp.pid == rhsApp.pid
                && lhsApp.bundleID == rhsApp.bundleID
                && lhsApp.name == rhsApp.name
                && lhsApp.audioObjectIDs == rhsApp.audioObjectIDs
                && nearlyEqual(lhsApp.volume, rhsApp.volume)
        }
    }

    private func nearlyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 0.001
    }

    private func storedAppVolume(for bundleID: String) -> Double {
        let key = defaultsKey(for: bundleID)

        if defaults.object(forKey: key) == nil {
            return 1
        }

        return max(0, min(maximumAppVolume, defaults.double(forKey: key)))
    }

    private func defaultsKey(for bundleID: String) -> String {
        "AppVolume.\(bundleID)"
    }

    private var maximumAppVolume: Double {
        defaults.bool(forKey: MixVolumePreference.enables200PercentVolume) ? 2 : 1
    }

}
