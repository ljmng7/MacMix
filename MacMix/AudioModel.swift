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
    @Published var systemVolume: Double?
    @Published var isSystemMuted = false

    var currentDevice: AudioDevice? {
        devices.first(where: \.isCurrent)
    }

    var menuBarSymbolName: String {
        if isSystemMuted {
            return "speaker.slash.fill"
        }

        guard let systemVolume else {
            return "speaker.wave.3.fill"
        }

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
    @Published var inputVolume: Double?

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
    private let displayVolumeController = DisplayVolumeController()
    private let outputRouteProbe = DefaultOutputRouteProbe()
    private let outputDeviceWriter = DefaultOutputDeviceWriter()
    private let defaults = UserDefaults.standard
    private var deviceObserver: CoreAudioDeviceObserver?
    private var refreshTimer: Timer?
    private var pendingOutputApps: [AudioApp]?
    private var retainedOutputAppsDuringRoute: [AudioApp] = []
    private var outputAppRouteRecoveryDeadline: Date?
    private var outputRouteRefreshTask: Task<Void, Never>?
    private var outputDeviceWriteTimeoutTask: Task<Void, Never>?
    private var displayVolumeActivationTask: Task<Void, Never>?
    private var displayVolumeActivationUID: String?
    private var displayVolumeRouteUID: String?
    private var displayVolumeValue: Double?
    private var displayVolumeLastAudibleValue = 0.15
    private var outputRouteGeneration: UInt64 = 0
    private var outputDeviceSelectionGeneration: UInt64 = 0
    private var mixerCommandRevision: UInt64 = 0
    private var lastSubmittedMixerSnapshot: AppMixerSnapshot?
    private var isOutputRouteTransitioning = false
    private var isMixerLifecycleBusy = false
    private var mixerLifecycleRevision: UInt64?
    private var needsOutputHardwareRefresh = false
    private var needsInputHardwareRefresh = false
    private var hasPendingOutputRouteTransition = false
    private var pendingOutputRouteUID: String?
    private let outputRouteStableReadIntervalNanoseconds: UInt64 = 80_000_000
    private let outputDeviceRouteReleaseGraceNanoseconds: UInt64 = 80_000_000
    private let outputDeviceWriteTimeoutNanoseconds: UInt64 = 12_000_000_000
    private let outputAppRouteRecoveryDuration: TimeInterval = 4
    private let requiredOutputRouteStableReads = 3
    private let maximumOutputRouteStableReadAttempts = 10
    private let systemAudioPermissionNeedsAuthorizationKey = "MacMix.SystemAudioPermissionNeedsAuthorization"
    private let systemAudioPermissionAuthorizedKey = "MacMix.SystemAudioPermissionAuthorized"

    override init() {
        super.init()
        restoreCachedSystemAudioPermissionState()

        deviceObserver = CoreAudioDeviceObserver(
            onOutputChange: { [weak self] in
                self?.handleOutputHardwareChange()
            },
            onInputChange: { [weak self] in
                self?.handleInputHardwareChange()
            },
            onOutputAppsChange: { [weak self] in
                self?.handleOutputAppsChange()
            }
        )

        deviceObserver?.start()
        refresh()
        refreshTimer = Timer.scheduledTimer(
            timeInterval: 0.5,
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
        outputDeviceWriteTimeoutTask?.cancel()
        displayVolumeActivationTask?.cancel()
        displayVolumeController.deactivate()
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

        if let currentDevice = devices.first(where: \.isCurrent),
           let nativeVolume = currentDevice.volume {
            deactivateDisplayVolumeRoute()
            setSystemOutputVolumeIfChanged(nativeVolume)
            setSystemOutputMutedIfChanged(
                hardware.isMuted(for: currentDevice.id, direction: .output) ?? false
            )
        } else if let currentDevice = devices.first(where: \.isCurrent),
                  displayVolumeRouteUID == currentDevice.uid,
                  let displayVolumeValue {
            setSystemOutputVolumeIfChanged(displayVolumeValue)
        } else {
            setSystemOutputVolumeIfChanged(nil)
            setSystemOutputMutedIfChanged(false)
            if let currentDevice = devices.first(where: \.isCurrent) {
                activateDisplayVolumeRoute(for: currentDevice)
            } else {
                deactivateDisplayVolumeRoute()
            }
        }

        let currentOutputUID = devices.first(where: \.isCurrent)?.uid

        if previousOutputUID != currentOutputUID {
            handleOutputRouteChange(to: currentOutputUID)
        }
    }

    private func activateDisplayVolumeRoute(for device: AudioDevice) {
        guard displayVolumeActivationUID != device.uid else {
            return
        }

        displayVolumeActivationTask?.cancel()
        displayVolumeActivationUID = device.uid
        displayVolumeRouteUID = nil
        displayVolumeValue = nil

        let candidate = DisplayAudioRouteCandidate(
            uid: device.uid,
            name: device.name,
            transportType: device.transportType
        )
        let displays = NSScreen.screens.compactMap { screen -> ExternalDisplayDescriptor? in
            let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
            guard let screenNumber = screen.deviceDescription[screenNumberKey] as? NSNumber else {
                return nil
            }

            let displayID = CGDirectDisplayID(screenNumber.uint32Value)
            guard CGDisplayIsBuiltin(displayID) == 0 else {
                return nil
            }

            return ExternalDisplayDescriptor(
                id: displayID,
                name: screen.localizedName,
                vendorID: CGDisplayVendorNumber(displayID),
                productID: CGDisplayModelNumber(displayID),
                serialNumber: CGDisplaySerialNumber(displayID)
            )
        }
        let controller = displayVolumeController

        displayVolumeActivationTask = Task { @MainActor [weak self] in
            let snapshot = await controller.activate(candidate: candidate, displays: displays)
            guard !Task.isCancelled,
                  let self,
                  self.currentOutputDevice?.uid == candidate.uid,
                  self.displayVolumeActivationUID == candidate.uid else {
                return
            }

            self.displayVolumeActivationTask = nil
            guard let snapshot else {
                return
            }

            self.displayVolumeRouteUID = snapshot.routeUID
            self.displayVolumeValue = snapshot.volume
            if snapshot.volume > 0.001 {
                self.displayVolumeLastAudibleValue = snapshot.volume
            }
            self.setSystemOutputVolumeIfChanged(snapshot.volume)
            self.setSystemOutputMutedIfChanged(false)
        }
    }

    private func deactivateDisplayVolumeRoute() {
        guard displayVolumeActivationUID != nil || displayVolumeRouteUID != nil else {
            return
        }

        displayVolumeActivationTask?.cancel()
        displayVolumeActivationTask = nil
        displayVolumeActivationUID = nil
        displayVolumeRouteUID = nil
        displayVolumeValue = nil
        displayVolumeController.deactivate()
    }

    func refreshInputState() {
        let devices = hardware.devices(for: .input)
        setInputDevicesIfChanged(devices)

        setInputVolumeIfChanged(devices.first(where: \.isCurrent)?.volume)
    }

    func refreshOutputApps(stabilize: Bool = true) {
        guard !isOutputRouteTransitioning else {
            return
        }

        let detectedApps = hardware.runningOutputApps(
            storedVolume: { [weak self] bundleID in
                self?.storedAppVolume(for: bundleID) ?? 1
            },
            storedMute: { [weak self] bundleID in
                self?.storedAppMute(for: bundleID) ?? false
            }
        )
        let apps = outputAppsPreservingRouteSnapshot(detectedApps)

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
        let appAudioMixer = appAudioMixer
        Task { @MainActor [weak self] in
            let permissionAvailable = await appAudioMixer.requestSystemAudioPermissionIfNeeded()
            self?.handleSystemAudioPermissionRequest(permissionAvailable)
        }
    }

    func requestSystemAudioPermission() {
        let appAudioMixer = appAudioMixer
        Task { @MainActor [weak self] in
            let permissionAvailable = await appAudioMixer.requestSystemAudioPermission()
            self?.handleSystemAudioPermissionRequest(permissionAvailable)
        }
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
        guard !isMixerLifecycleBusy, !isOutputRouteTransitioning else {
            return
        }

        refreshOutputApps()
    }

    func setSystemOutputVolume(_ volume: Double) {
        guard let currentOutputDevice else {
            return
        }

        if displayVolumeRouteUID == currentOutputDevice.uid {
            let clampedVolume = max(0, min(1, volume))
            displayVolumeController.setVolume(
                clampedVolume,
                routeUID: currentOutputDevice.uid
            )
            displayVolumeValue = clampedVolume
            if clampedVolume > 0.001 {
                displayVolumeLastAudibleValue = clampedVolume
                if outputState.isSystemMuted {
                    displayVolumeController.setMuted(
                        false,
                        audibleVolume: clampedVolume,
                        routeUID: currentOutputDevice.uid
                    )
                    setSystemOutputMutedIfChanged(false)
                }
            }
            setSystemOutputVolumeIfChanged(clampedVolume)
            return
        }

        guard hardware.setVolume(volume, for: currentOutputDevice.id, direction: .output) else {
            refreshOutputState()
            return
        }

        if outputState.isSystemMuted {
            hardware.setMuted(false, for: currentOutputDevice.id, direction: .output)
        }

        let appliedVolume = hardware.volume(for: currentOutputDevice.id, direction: .output) ?? volume
        setSystemOutputVolumeIfChanged(appliedVolume)
        setSystemOutputMutedIfChanged(
            hardware.isMuted(for: currentOutputDevice.id, direction: .output) ?? false
        )
        setCurrentOutputDeviceVolume(appliedVolume)
    }

    func toggleSystemOutputMute() {
        guard let currentOutputDevice else {
            return
        }

        let shouldMute = !outputState.isSystemMuted
        if displayVolumeRouteUID == currentOutputDevice.uid {
            if !shouldMute,
               (displayVolumeValue ?? 0) <= 0.001 {
                displayVolumeValue = displayVolumeLastAudibleValue
                setSystemOutputVolumeIfChanged(displayVolumeLastAudibleValue)
            } else if shouldMute,
                      let displayVolumeValue,
                      displayVolumeValue > 0.001 {
                displayVolumeLastAudibleValue = displayVolumeValue
            }

            displayVolumeController.setMuted(
                shouldMute,
                audibleVolume: displayVolumeLastAudibleValue,
                routeUID: currentOutputDevice.uid
            )
            setSystemOutputMutedIfChanged(shouldMute)
            return
        }

        guard hardware.setMuted(shouldMute, for: currentOutputDevice.id, direction: .output) else {
            refreshOutputState()
            return
        }

        let appliedMute = hardware.isMuted(for: currentOutputDevice.id, direction: .output) ?? shouldMute
        setSystemOutputMutedIfChanged(appliedMute)
    }

    func setInputVolume(_ volume: Double) {
        guard let deviceID = currentInputDevice?.id else {
            return
        }

        guard hardware.setVolume(volume, for: deviceID, direction: .input) else {
            refreshInputState()
            return
        }

        let appliedVolume = hardware.volume(for: deviceID, direction: .input) ?? volume
        setInputVolumeIfChanged(appliedVolume)
        setCurrentInputDeviceVolume(appliedVolume)
    }

    func selectOutputDevice(_ device: AudioDevice) {
        guard !device.isCurrent else {
            return
        }

        outputDeviceSelectionGeneration &+= 1
        outputRouteGeneration &+= 1
        mixerCommandRevision &+= 1
        let selectionGeneration = outputDeviceSelectionGeneration
        let commandRevision = mixerCommandRevision

        outputRouteRefreshTask?.cancel()
        outputRouteRefreshTask = nil
        outputDeviceWriteTimeoutTask?.cancel()
        outputDeviceWriteTimeoutTask = nil
        pendingOutputApps = nil
        hasPendingOutputRouteTransition = false
        pendingOutputRouteUID = nil
        lastSubmittedMixerSnapshot = nil
        isOutputRouteTransitioning = true
        appAudioMixer.noteLatestCommand(revision: commandRevision)
        beginMixerLifecycle(revision: commandRevision)
        beginOutputAppRouteRecovery()
        let switchTargets = outputAppsPreservingRouteSnapshot(outputAppsState.apps)
            .map(mixTarget)
            .sorted { $0.id < $1.id }

        appAudioMixer.submitQuiesceForOutputSwitch(
            revision: commandRevision,
            targets: switchTargets
        ) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                guard outputDeviceSelectionGeneration == selectionGeneration,
                      mixerCommandRevision == commandRevision else {
                    return
                }

                guard result == .applied else {
                    finishMixerLifecycle(revision: commandRevision)
                    recoverFromOutputDeviceSelectionFailure(revision: commandRevision)
                    return
                }

                do {
                    try await Task.sleep(
                        nanoseconds: outputDeviceRouteReleaseGraceNanoseconds
                    )
                } catch {
                    finishMixerLifecycle(revision: commandRevision)
                    recoverFromOutputDeviceSelectionFailure(revision: commandRevision)
                    return
                }

                guard outputDeviceSelectionGeneration == selectionGeneration,
                      mixerCommandRevision == commandRevision else {
                    return
                }

                beginOutputDeviceWrite(
                    device,
                    selectionGeneration: selectionGeneration,
                    commandRevision: commandRevision
                )
            }
        }
    }

    private func beginOutputDeviceWrite(
        _ device: AudioDevice,
        selectionGeneration: UInt64,
        commandRevision: UInt64
    ) {
        let writeTimeoutNanoseconds = outputDeviceWriteTimeoutNanoseconds
        outputDeviceWriteTimeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: writeTimeoutNanoseconds)
            } catch {
                return
            }

            guard let self,
                  outputDeviceSelectionGeneration == selectionGeneration,
                  mixerCommandRevision == commandRevision else {
                return
            }

            outputDeviceWriteTimeoutTask = nil
            outputDeviceSelectionGeneration &+= 1
            let routeGenerationBeforeFinish = outputRouteGeneration
            finishMixerLifecycle(revision: commandRevision)
            if outputRouteGeneration == routeGenerationBeforeFinish {
                refreshOutputState()
            }

            if currentOutputDevice?.uid == device.uid {
                if outputRouteGeneration == routeGenerationBeforeFinish {
                    handleOutputRouteChange(to: device.uid)
                }
            } else {
                recoverFromOutputDeviceSelectionFailure(revision: commandRevision)
            }
        }

        outputDeviceWriter.select(device.id) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      outputDeviceSelectionGeneration == selectionGeneration,
                      mixerCommandRevision == commandRevision else {
                    return
                }

                outputDeviceWriteTimeoutTask?.cancel()
                outputDeviceWriteTimeoutTask = nil

                // Process the one deferred hardware refresh only after the blocking HAL
                // write completes. Intermediate Bluetooth route notifications must not
                // trigger competing aggregate rebuilds.
                let routeGenerationBeforeFinish = outputRouteGeneration
                finishMixerLifecycle(revision: commandRevision)
                if outputRouteGeneration == routeGenerationBeforeFinish {
                    refreshOutputState()
                }

                if currentOutputDevice?.uid == device.uid {
                    if outputRouteGeneration == routeGenerationBeforeFinish {
                        handleOutputRouteChange(to: device.uid)
                    }
                } else {
                    recoverFromOutputDeviceSelectionFailure(revision: commandRevision)
                }
            }
        }
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
            let shouldUnmute = apps[index].isMuted
            guard !nearlyEqual(apps[index].volume, clampedVolume) || shouldUnmute else {
                return
            }

            apps[index].volume = clampedVolume
            apps[index].isMuted = false
            if shouldUnmute {
                defaults.set(false, forKey: muteDefaultsKey(for: app.bundleID))
            }
            outputAppsState.apps = apps
            scheduleMixerReconcile(requestAuthorizationIfDenied: true)
        } else {
            var updatedApp = app
            updatedApp.volume = clampedVolume
            updatedApp.isMuted = false
            defaults.set(false, forKey: muteDefaultsKey(for: app.bundleID))
            scheduleMixerReconcile(
                additionalTarget: updatedApp,
                requestAuthorizationIfDenied: true
            )
        }
    }

    func toggleAppMute(_ app: AudioApp) {
        let isMuted = !app.isMuted
        defaults.set(isMuted, forKey: muteDefaultsKey(for: app.bundleID))

        if let index = outputAppsState.apps.firstIndex(where: { $0.id == app.id }) {
            var apps = outputAppsState.apps
            apps[index].isMuted = isMuted
            outputAppsState.apps = apps
            scheduleMixerReconcile(requestAuthorizationIfDenied: true)
        } else {
            var updatedApp = app
            updatedApp.isMuted = isMuted
            scheduleMixerReconcile(
                additionalTarget: updatedApp,
                requestAuthorizationIfDenied: true
            )
        }
    }

    func clampAppVolumesToUnity() {
        var apps = outputAppsState.apps
        var didChangeVolume = false

        for index in apps.indices where apps[index].volume > 1 {
            apps[index].volume = 1
            defaults.set(1, forKey: defaultsKey(for: apps[index].bundleID))
            didChangeVolume = true
        }

        if didChangeVolume {
            outputAppsState.apps = apps
            scheduleMixerReconcile(requestAuthorizationIfDenied: true)
        }
    }

    private func reconcileOutputApps() {
        scheduleMixerReconcile(requestAuthorizationIfDenied: false)
    }

    private func scheduleMixerReconcile(
        additionalTarget: AudioApp? = nil,
        requestAuthorizationIfDenied: Bool
    ) {
        guard !isOutputRouteTransitioning else {
            return
        }

        var apps = outputAppsState.apps
        if let additionalTarget,
           !apps.contains(where: { $0.id == additionalTarget.id }) {
            apps.append(additionalTarget)
        }

        let outputDeviceUID = currentOutputDevice?.uid
        let targets = outputDeviceUID == nil ? [] : apps.map(mixTarget).sorted { $0.id < $1.id }
        let snapshot = AppMixerSnapshot(
            routeGeneration: outputRouteGeneration,
            outputDeviceUID: outputDeviceUID,
            targets: targets
        )
        guard snapshot != lastSubmittedMixerSnapshot else {
            return
        }

        mixerCommandRevision &+= 1
        let command = AppMixerCommand(
            revision: mixerCommandRevision,
            routeGeneration: snapshot.routeGeneration,
            outputDeviceUID: snapshot.outputDeviceUID,
            targets: snapshot.targets
        )
        let requiresPermission = command.targets.contains {
            appVolumeRequiresSystemAudioPermission($0.volume)
        }
        lastSubmittedMixerSnapshot = snapshot
        appAudioMixer.noteLatestCommand(revision: command.revision)
        beginMixerLifecycle(revision: command.revision)
        appAudioMixer.submitReconcile(command) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                finishMixerLifecycle(revision: command.revision)

                guard mixerCommandRevision == command.revision,
                      outputRouteGeneration == command.routeGeneration,
                      !isOutputRouteTransitioning else {
                    return
                }

                guard result != .superseded else {
                    return
                }

                if result == .failed {
                    lastSubmittedMixerSnapshot = nil
                }
                updateSystemAudioPermissionAfterMixAttempt(
                    result == .applied,
                    requiresPermission: requiresPermission,
                    requestAuthorizationIfDenied: requestAuthorizationIfDenied
                )
            }
        }
    }

    private func mixTarget(_ app: AudioApp) -> AppMixTarget {
        AppMixTarget(
            id: app.id,
            audioObjectIDs: app.audioObjectIDs,
            volume: app.isMuted ? 0 : app.volume
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

    private func handleOutputRouteChange(to outputDeviceUID: String?) {
        beginOutputAppRouteRecovery()
        pendingOutputApps = nil
        hasPendingOutputRouteTransition = false
        pendingOutputRouteUID = nil
        outputRouteGeneration &+= 1
        mixerCommandRevision &+= 1
        let routeGeneration = outputRouteGeneration
        let commandRevision = mixerCommandRevision
        lastSubmittedMixerSnapshot = nil
        appAudioMixer.noteLatestCommand(revision: commandRevision)

        outputRouteRefreshTask?.cancel()
        isOutputRouteTransitioning = true
        // The system route changes first. Rebuild private tap aggregates only after the
        // actual default-output UID has remained stable across consecutive HAL reads.
        outputRouteRefreshTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            var lastObservedUID = outputDeviceUID
            var hasObservedUID = false
            var stableReadCount = 0
            var didReachStableRoute = false
            var stableOutputDeviceUID: String?

            for _ in 0..<maximumOutputRouteStableReadAttempts {
                do {
                    try await Task.sleep(nanoseconds: outputRouteStableReadIntervalNanoseconds)
                } catch {
                    return
                }

                guard outputRouteGeneration == routeGeneration else {
                    return
                }

                let observedUID: String?
                switch await outputRouteProbe.read() {
                case let .device(uid):
                    observedUID = uid
                case .noDevice:
                    observedUID = nil
                case .failed:
                    continue
                }
                if hasObservedUID, observedUID == lastObservedUID {
                    stableReadCount += 1
                } else {
                    lastObservedUID = observedUID
                    hasObservedUID = true
                    stableReadCount = 1
                }

                if stableReadCount >= requiredOutputRouteStableReads {
                    stableOutputDeviceUID = observedUID
                    didReachStableRoute = true
                    break
                }
            }

            guard didReachStableRoute,
                  outputRouteGeneration == routeGeneration else {
                if outputRouteGeneration == routeGeneration {
                    isOutputRouteTransitioning = false
                    if isMixerLifecycleBusy {
                        deferOutputRouteTransition(to: outputDeviceUID)
                        return
                    }
                    appAudioMixer.cancelOutputSwitch(revision: commandRevision)
                    scheduleMixerReconcile(requestAuthorizationIfDenied: false)
                }
                return
            }

            guard !isMixerLifecycleBusy else {
                deferOutputRouteTransition(to: stableOutputDeviceUID)
                return
            }

            refreshOutputState()
            guard outputRouteGeneration == routeGeneration else {
                return
            }

            guard currentOutputDevice?.uid == stableOutputDeviceUID else {
                isOutputRouteTransitioning = false
                handleOutputRouteChange(to: currentOutputDevice?.uid)
                return
            }

            var detectedApps: [AudioApp] = []
            if stableOutputDeviceUID != nil {
                detectedApps = hardware.runningOutputApps(
                    storedVolume: { [weak self] bundleID in
                        self?.storedAppVolume(for: bundleID) ?? 1
                    },
                    storedMute: { [weak self] bundleID in
                        self?.storedAppMute(for: bundleID) ?? false
                    }
                )
            }
            let apps = outputAppsPreservingRouteSnapshot(detectedApps)

            pendingOutputApps = nil
            let command = AppMixerCommand(
                revision: commandRevision,
                routeGeneration: routeGeneration,
                outputDeviceUID: stableOutputDeviceUID,
                targets: apps.map(mixTarget).sorted { $0.id < $1.id }
            )
            let requiresPermission = command.targets.contains {
                self.appVolumeRequiresSystemAudioPermission($0.volume)
            }
            lastSubmittedMixerSnapshot = command.snapshot
            isOutputRouteTransitioning = false
            beginMixerLifecycle(revision: commandRevision)

            let completion: @Sendable (AppMixerResult) -> Void = { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }
                    finishMixerLifecycle(revision: commandRevision)

                    guard outputRouteGeneration == routeGeneration,
                          mixerCommandRevision == commandRevision else {
                        return
                    }

                    guard result != .superseded else {
                        return
                    }

                    if result == .failed {
                        lastSubmittedMixerSnapshot = nil
                    }
                    updateSystemAudioPermissionAfterMixAttempt(
                        result == .applied,
                        requiresPermission: requiresPermission,
                        requestAuthorizationIfDenied: false
                    )
                    refreshOutputApps(stabilize: true)
                }
            }

            if stableOutputDeviceUID == nil {
                appAudioMixer.cancelOutputSwitch(revision: commandRevision)
                appAudioMixer.submitReconcile(command, completion: completion)
            } else {
                appAudioMixer.submitTransitionCompletingOutputSwitch(
                    command,
                    completion: completion
                )
            }
        }
    }

    private func handleOutputHardwareChange() {
        guard !isMixerLifecycleBusy else {
            needsOutputHardwareRefresh = true
            return
        }

        refreshOutputState()
    }

    private func handleInputHardwareChange() {
        guard !isMixerLifecycleBusy else {
            needsInputHardwareRefresh = true
            return
        }

        refreshInputState()
    }

    private func handleOutputAppsChange() {
        guard !isMixerLifecycleBusy, !isOutputRouteTransitioning else {
            return
        }

        // HAL process callbacks represent a real add/start/stop event, so additions can
        // be published and mixed immediately instead of waiting for a second timer poll.
        refreshOutputApps(stabilize: false)
    }

    private func recoverFromOutputDeviceSelectionFailure(revision: UInt64) {
        guard mixerCommandRevision == revision else {
            return
        }

        appAudioMixer.cancelOutputSwitch(revision: revision)
        isOutputRouteTransitioning = false
        lastSubmittedMixerSnapshot = nil
        refreshOutputState()
        scheduleMixerReconcile(requestAuthorizationIfDenied: false)
    }

    private func beginMixerLifecycle(revision: UInt64) {
        mixerLifecycleRevision = revision
        isMixerLifecycleBusy = true
    }

    private func finishMixerLifecycle(revision: UInt64) {
        guard mixerLifecycleRevision == revision else {
            return
        }

        mixerLifecycleRevision = nil
        isMixerLifecycleBusy = false

        if hasPendingOutputRouteTransition {
            let outputDeviceUID = pendingOutputRouteUID
            hasPendingOutputRouteTransition = false
            pendingOutputRouteUID = nil
            needsOutputHardwareRefresh = false
            handleOutputRouteChange(to: outputDeviceUID)
            return
        }

        if needsOutputHardwareRefresh {
            needsOutputHardwareRefresh = false
            refreshOutputState()
        }

        if needsInputHardwareRefresh {
            needsInputHardwareRefresh = false
            refreshInputState()
        }
    }

    private func deferOutputRouteTransition(to outputDeviceUID: String?) {
        pendingOutputRouteUID = outputDeviceUID
        hasPendingOutputRouteTransition = true
        needsOutputHardwareRefresh = true
        isOutputRouteTransitioning = false
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
            transportType: device.transportType,
            isCurrent: device.isCurrent,
            volume: volume
        )

        return updatedDevices
    }

    private func setSystemOutputVolumeIfChanged(_ volume: Double?) {
        guard !optionalVolumesMatch(outputState.systemVolume, volume) else {
            return
        }

        outputState.systemVolume = volume
    }

    private func setSystemOutputMutedIfChanged(_ isMuted: Bool) {
        guard outputState.isSystemMuted != isMuted else {
            return
        }

        outputState.isSystemMuted = isMuted
    }

    private func setInputVolumeIfChanged(_ volume: Double?) {
        guard !optionalVolumesMatch(inputState.inputVolume, volume) else {
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
        outputAppsState.apps.contains {
            appVolumeRequiresSystemAudioPermission($0.isMuted ? 0 : $0.volume)
        }
    }

    private func beginOutputAppRouteRecovery() {
        retainedOutputAppsDuringRoute = mergeOutputApps(
            retaining: retainedOutputAppsDuringRoute,
            updatingWith: outputAppsState.apps
        )
        outputAppRouteRecoveryDeadline = Date().addingTimeInterval(
            outputAppRouteRecoveryDuration
        )
    }

    private func outputAppsPreservingRouteSnapshot(_ detectedApps: [AudioApp]) -> [AudioApp] {
        guard let outputAppRouteRecoveryDeadline,
              Date() < outputAppRouteRecoveryDeadline else {
            self.outputAppRouteRecoveryDeadline = nil
            retainedOutputAppsDuringRoute = []
            return detectedApps
        }

        retainedOutputAppsDuringRoute = mergeOutputApps(
            retaining: retainedOutputAppsDuringRoute,
            updatingWith: detectedApps
        )
        return retainedOutputAppsDuringRoute
    }

    private func mergeOutputApps(
        retaining retainedApps: [AudioApp],
        updatingWith detectedApps: [AudioApp]
    ) -> [AudioApp] {
        var appsByID = Dictionary(uniqueKeysWithValues: retainedApps.map { ($0.id, $0) })
        for app in detectedApps {
            appsByID[app.id] = app
        }

        return appsByID.values.sorted { lhs, rhs in
            let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
            if nameOrder == .orderedSame {
                return lhs.id < rhs.id
            }
            return nameOrder == .orderedAscending
        }
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
                && lhsApp.isMuted == rhsApp.isMuted
        }
    }

    private func nearlyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 0.001
    }

    private func optionalVolumesMatch(_ lhs: Double?, _ rhs: Double?) -> Bool {
        switch (lhs, rhs) {
        case let (.some(lhs), .some(rhs)):
            nearlyEqual(lhs, rhs)
        case (.none, .none):
            true
        default:
            false
        }
    }

    private func storedAppVolume(for bundleID: String) -> Double {
        let key = defaultsKey(for: bundleID)

        if defaults.object(forKey: key) == nil {
            return 1
        }

        return max(0, min(maximumAppVolume, defaults.double(forKey: key)))
    }

    private func storedAppMute(for bundleID: String) -> Bool {
        defaults.bool(forKey: muteDefaultsKey(for: bundleID))
    }

    private func defaultsKey(for bundleID: String) -> String {
        "AppVolume.\(bundleID)"
    }

    private func muteDefaultsKey(for bundleID: String) -> String {
        "AppMuted.\(bundleID)"
    }

    private var maximumAppVolume: Double {
        defaults.bool(forKey: MixVolumePreference.enables200PercentVolume) ? 2 : 1
    }

}
