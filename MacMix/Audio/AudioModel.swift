//
//  AudioModel.swift
//  MacMix
//
//  Created by Jazmin on 2026/6/29.
//

import AppKit
import CoreAudio
import CoreBluetooth
import Foundation
import MacMixStudio
import Observation
import OSLog

enum OutputRow: Identifiable {
    case device(AudioDevice)
    case nearby(NearbyAudioAccessory)

    var id: String {
        switch self {
        case let .device(device): "device:\(device.selectionID)"
        case let .nearby(accessory): "nearby:\(accessory.address)"
        }
    }

    var orderKey: String {
        switch self {
        case let .device(device): Self.orderKey(device)
        case let .nearby(accessory): Self.orderKey(accessory)
        }
    }

    static func orderKey(_ device: AudioDevice) -> String {
        device.bluetoothAddress.map { "bt:\($0)" } ?? device.selectionID
    }

    static func orderKey(_ accessory: NearbyAudioAccessory) -> String {
        "bt:\(NearbyAudioAccessoryMatcher.canonical(accessory.address))"
    }
}

extension AudioDevice {
    // Canonical Bluetooth address from the HAL UID ("30-7A-…:output").
    var bluetoothAddress: String? {
        guard transportType == kAudioDeviceTransportTypeBluetooth
            || transportType == kAudioDeviceTransportTypeBluetoothLE else { return nil }
        let address = NearbyAudioAccessoryMatcher.canonical(String(uid.split(separator: ":").first ?? ""))
        return address.count == 12 ? address : nil
    }
}

@MainActor
@Observable
final class OutputAudioState {
    var devices: [AudioDevice] = []
    var airPlayDestinations: [AudioDevice] = []
    // Paired headphones advertising nearby that Core Audio does not list.
    var nearbyAccessories: [NearbyAudioAccessory] = []
    // Canonical (hex-only, uppercase) address of the accessory being connected.
    var connectingAccessoryAddress: String?
    // First-seen order of output rows. Headphones keep their place while they
    // move between the device list and the nearby rows, or reconnect with a
    // new Core Audio object that would otherwise sort last.
    private(set) var rowOrder: [String] = []

    func recordRowOrder() {
        let keys = devices.map(OutputRow.orderKey) + nearbyAccessories.map(OutputRow.orderKey)
        let known = Set(rowOrder)
        let added = keys.filter { !known.contains($0) }
        if !added.isEmpty {
            rowOrder += NSOrderedSet(array: added).array.compactMap { $0 as? String }
        }
    }

    func orderedRows(for devices: [AudioDevice]) -> [OutputRow] {
        let index = Dictionary(rowOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
        let rows = devices.map(OutputRow.device) + nearbyAccessories.map(OutputRow.nearby)
        return rows.enumerated().sorted { lhs, rhs in
            let l = index[lhs.element.orderKey] ?? Int.max, r = index[rhs.element.orderKey] ?? Int.max
            return l != r ? l < r : lhs.offset < rhs.offset
        }.map(\.element)
    }

    var selectionDevices: [AudioDevice] {
        let destinations = Dictionary(grouping: airPlayDestinations, by: \.uid)
        return devices.flatMap { device in
            guard let routes = destinations[device.uid] else { return [device] }
            return routes.map { route in
                var route = route
                route.volume = route.isCurrent ? device.volume : nil
                return route
            }
        }
    }
    var systemVolume: Double?
    var isSystemMuted = false
    private(set) var batteryByDeviceUID: [String: AudioDeviceBattery] = [:]
    private(set) var accessoryControlsByDeviceUID: [String: AudioAccessoryControlState] = [:]

    var currentDevice: AudioDevice? {
        devices.first(where: \.isCurrent)
    }

    // Receiver choices sharing a HAL device are not independent app outputs.
    // Offer its complete connected selection once, rather than individual members.
    var routingDevices: [AudioDevice] {
        devices.filter { $0.selectedDataSourceIDs?.isEmpty != true }
    }

    var routingDestinations: [AppOutputDestination] {
        routingDevices.map {
            AppOutputDestination(uid: $0.uid, name: $0.name, dataSourceIDs: $0.selectedDataSourceIDs)
        }
    }

    // A row can be a member of an active group without being the complete
    // requested output selection. Only the latter should skip a switch.
    func isSelected(_ device: AudioDevice) -> Bool {
        guard let current = currentDevice,
              current.uid == device.uid, current.id == device.id else { return false }
        return device.dataSourceID == nil || current.dataSourceID == device.dataSourceID
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

    /// Level for the menu bar's speaker.wave.3.fill, snapped to the symbol's
    /// three wave stages so the label only changes when a wave does. `nil`
    /// means muted.
    var menuBarVolumeLevel: Double? {
        if isSystemMuted {
            return nil
        }

        guard let systemVolume else {
            return 1
        }

        if systemVolume <= 0.001 {
            return nil
        }

        if systemVolume < 0.34 {
            return 0.25
        }

        if systemVolume < 0.67 {
            return 0.5
        }

        return 1
    }

    func updateBatteryByDeviceUID(_ batteryByDeviceUID: [String: AudioDeviceBattery]) {
        guard self.batteryByDeviceUID != batteryByDeviceUID else {
            return
        }

        self.batteryByDeviceUID = batteryByDeviceUID
    }

    func updateAccessoryControlsByDeviceUID(
        _ accessoryControlsByDeviceUID: [String: AudioAccessoryControlState]
    ) {
        guard self.accessoryControlsByDeviceUID != accessoryControlsByDeviceUID else {
            return
        }

        self.accessoryControlsByDeviceUID = accessoryControlsByDeviceUID
    }
}

@MainActor
@Observable
final class InputAudioState {
    var devices: [AudioDevice] = []
    var inputVolume: Double?
    var isInputMuted = false

    var currentDevice: AudioDevice? {
        devices.first(where: \.isCurrent)
    }
}

@MainActor
@Observable
final class OutputAppsState {
    private(set) var apps: [AudioAppState] = []
    var needsSystemAudioPermission = false

    var snapshots: [AudioApp] {
        apps.map(\.snapshot)
    }

    func replaceApps(with newApps: [AudioApp]) {
        let existingApps = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
        let updatedApps = newApps.map { app in
            if let existingApp = existingApps[app.id],
               existingApp.hasSameStructure(as: app) {
                existingApp.updateControls(volume: app.volume, isMuted: app.isMuted)
                return existingApp
            }

            return AudioAppState(app: app)
        }

        let hasSameInstances = apps.count == updatedApps.count
            && zip(apps, updatedApps).allSatisfy { $0 === $1 }
        if !hasSameInstances {
            apps = updatedApps
        }
    }
}

@MainActor
@Observable
final class AudioAppBlacklistState {
    private(set) var apps: [AudioAppBlacklistEntry]
    @ObservationIgnored private var appIDs: Set<String>

    init(apps: [AudioAppBlacklistEntry] = []) {
        let sortedApps = Self.sorted(apps)
        self.apps = sortedApps
        appIDs = Set(sortedApps.map(\.id))
    }

    func contains(appID: String) -> Bool {
        appIDs.contains(appID)
    }

    @discardableResult
    func add(_ newApps: [AudioApp]) -> Bool {
        add(entries: newApps.map { app in
            AudioAppBlacklistEntry(
                id: app.id,
                bundleID: app.bundleID,
                name: app.name,
                icon: app.icon
            )
        })
    }

    @discardableResult
    func add(entries newEntries: [AudioAppBlacklistEntry]) -> Bool {
        guard !newEntries.isEmpty else {
            return false
        }

        var appsByID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
        var didChange = false
        for entry in newEntries {
            if appsByID[entry.id] != entry {
                appsByID[entry.id] = entry
                didChange = true
            }
        }

        guard didChange else {
            return false
        }

        replaceApps(Array(appsByID.values))
        return true
    }

    @discardableResult
    func remove(appIDs removedAppIDs: Set<String>) -> Bool {
        guard !removedAppIDs.isDisjoint(with: appIDs) else {
            return false
        }

        replaceApps(apps.filter { !removedAppIDs.contains($0.id) })
        return true
    }

    @discardableResult
    func updateMetadata(from detectedApps: [AudioApp]) -> Bool {
        var appsByID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
        var didChange = false

        for app in detectedApps where appIDs.contains(app.id) {
            guard let existingEntry = appsByID[app.id] else {
                continue
            }

            let updatedEntry = AudioAppBlacklistEntry(
                id: existingEntry.id,
                bundleID: app.bundleID,
                name: app.name,
                icon: app.icon ?? existingEntry.icon
            )
            if updatedEntry != existingEntry {
                appsByID[app.id] = updatedEntry
                didChange = true
            }
        }

        if didChange {
            replaceApps(Array(appsByID.values))
        }
        return didChange
    }

    private func replaceApps(_ newApps: [AudioAppBlacklistEntry]) {
        let sortedApps = Self.sorted(newApps)
        guard sortedApps != apps else {
            return
        }

        apps = sortedApps
        appIDs = Set(sortedApps.map(\.id))
    }

    private static func sorted(
        _ apps: [AudioAppBlacklistEntry]
    ) -> [AudioAppBlacklistEntry] {
        apps.sorted { lhs, rhs in
            let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
            if nameOrder == .orderedSame {
                return lhs.id < rhs.id
            }
            return nameOrder == .orderedAscending
        }
    }
}

@MainActor
final class AudioModel: NSObject {
    private struct PersistedAudioAppBlacklistEntry: Codable {
        let id: String
        let bundleID: String
        let name: String
    }

    private struct PendingSpatialAudioSelection {
        let mode: SpatialAudioMode
        let deadline: Date
    }

    let equalizerStore = AppEqualizerStore()
    let outputRoutingStore = AppOutputRoutingStore()
    private var routedDeviceVolumes: [String: RoutedDeviceVolumeState] = [:]

    func routedDeviceVolumeState(for device: AudioDevice) -> RoutedDeviceVolumeState {
        if let state = routedDeviceVolumes[device.uid], state.deviceID == device.id { return state }
        let state = RoutedDeviceVolumeState(device: device) { [weak self] volume in
            guard let self, currentOutputDevice?.uid != device.uid,
                  outputState.devices.contains(where: { $0.uid == device.uid && $0.id == device.id }) else { return }
            setOutputDevicesIfChanged(devicesWithCurrentVolume(volume, in: outputState.devices, deviceUID: device.uid))
        }
        routedDeviceVolumes[device.uid] = state
        return state
    }

    func setRoutedDeviceVolume(_ value: Double, device: AudioDevice) {
        guard outputRoutingStore.isFeatureActive, value.isFinite,
              outputState.devices.contains(where: { $0.uid == device.uid && $0.id == device.id }) else { return }
        if currentOutputDevice?.uid == device.uid {
            setSystemOutputVolume(value)
        } else {
            routedDeviceVolumeState(for: device).setVolume(value)
        }
    }
    private var equalizerSampleRate: Double?
    private var lastRoutingValidation = Date.distantPast

    func updateOutputRoutingAccess(_ enabled: Bool) {
        guard outputRoutingStore.hasAccess != enabled else { return }
        outputRoutingStore.updateAccess(enabled)
        scheduleMixerReconcile(requestAuthorizationIfDenied: false)
    }

    func setMultiOutputEnabled(_ enabled: Bool) {
        guard outputRoutingStore.isEnabled != enabled else { return }
        outputRoutingStore.setFeatureEnabled(enabled)
        scheduleMixerReconcile(requestAuthorizationIfDenied: false)
    }

    func followSystemOutput(for app: AudioAppState) {
        outputRoutingStore.followSystem(for: app.bundleID)
        scheduleMixerReconcile(additionalTarget: app.snapshot, requestAuthorizationIfDenied: true)
    }

    func setOutputDestination(_ destination: AppOutputDestination, selected: Bool, for app: AudioAppState) {
        guard outputRoutingStore.isFeatureActive else { return }
        // Recheck a row which may have gone stale while the picker was open.
        guard !selected || outputState.routingDestinations.contains(where: { destination.matches($0) }) else { return }
        DiagnosticLog.shared.record("route", "app_destination_requested", fields: [
            "app": DiagnosticLog.shared.anonymous(app.bundleID), "device": DiagnosticLog.shared.anonymous(destination.uid),
            "selected": String(selected)])
        outputRoutingStore.setSelected(selected, destination: destination, for: app.bundleID)
        scheduleMixerReconcile(additionalTarget: app.snapshot, requestAuthorizationIfDenied: true)
    }

    func retryAppOutputRouting() {
        lastSubmittedMixerSnapshot = nil
        scheduleMixerReconcile(requestAuthorizationIfDenied: true)
    }

    func setEqualizer(_ configuration: EqualizerConfiguration, for app: AudioAppState) {
        guard equalizerStore.isFeatureActive else { return }
        let previous = equalizerStore.configuration(for: app.bundleID)
        equalizerStore.set(configuration, for: app.bundleID)
        let current = equalizerStore.configuration(for: app.bundleID)
        guard current != previous else { return }
        DiagnosticActions.shared.coalesce("audio", "equalizer_requested", target: app.bundleID,
            value: "enabled=\(current.isEnabled);bands=\(current.normalizedGains);tone=\(current.normalizedToneGains ?? [])")
        let changedEnablement = previous.isEnabled != current.isEnabled
        let needsVolumeClamp = current.isEnabled && app.volume > 1
        // Band drags do not change volume. Avoid UserDefaults notifications and
        // synchronization work for the same volume on every slider event.
        if changedEnablement || needsVolumeClamp {
            defaults.set(current.isEnabled ? min(1, app.volume) : app.volume,
                         forKey: defaultsKey(for: app.bundleID))
        }
        if needsVolumeClamp { app.updateControls(volume: 1, isMuted: app.isMuted) }
        guard changedEnablement || needsVolumeClamp
            || (current.isEnabled && (previous.normalizedGains != current.normalizedGains
                || previous.normalizedToneGains != current.normalizedToneGains)) else { return }
        scheduleMixerReconcile(additionalTarget: app.snapshot, requestAuthorizationIfDenied: true,
                               equalizerParametersOnly: !changedEnablement && !needsVolumeClamp)
    }

    func setCustomEqualizerEnabled(_ enabled: Bool) {
        equalizerStore.setFeatureEnabled(enabled)
        if equalizerStore.isFeatureActive { clampAppVolumesToUnity() }
        scheduleMixerReconcile(requestAuthorizationIfDenied: enabled)
    }

    func updateEqualizerAccess(_ enabled: Bool) {
        let previouslyActive = equalizerStore.isFeatureActive
        equalizerStore.updateAccess(enabled)
        guard previouslyActive != equalizerStore.isFeatureActive else { return }
        if equalizerStore.isFeatureActive { clampAppVolumesToUnity() }
        scheduleMixerReconcile(requestAuthorizationIfDenied: false)
    }

    func maximumVolume(for bundleID: String) -> Double {
        if equalizerStore.isFeatureActive { return 1 }
        return maximumAppVolume
    }

    let outputState = OutputAudioState()
    let inputState = InputAudioState()
    let notificationSound = NotificationSoundController()
    let outputAppsState = OutputAppsState()
    let audioAppBlacklistState: AudioAppBlacklistState

    var inputDevicesDidChange: (() -> Void)?
    var inputDeviceUserSelectionDidChange: ((String) -> Void)?

    private let hardware = CoreAudioHardware()
    private let outputVolumeController = OutputVolumeController()
    private var outputVolumeTask: Task<Void, Never>?
    private var pendingOutputVolume: (deviceID: AudioObjectID, uid: String, volume: Double?, muted: Bool?)?
    private var outputVolumeRevision: UInt64 = 0
    private let audioInterfaceWindows = NSHashTable<NSWindow>.weakObjects()
    private var interfaceVisibilityObservers: [NSObjectProtocol] = []
    private var audioInterfaceIsVisible = false
    private var lastAccessoryRefresh: TimeInterval = 0

    func observeAudioInterfaceWindow(_ window: NSWindow) {
        audioInterfaceWindows.add(window)
        updateAudioInterfaceVisibility()
    }

    private func updateAudioInterfaceVisibility() {
        let visible = audioInterfaceWindows.allObjects.contains {
            $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible)
        }
        guard visible != audioInterfaceIsVisible else { return }
        audioInterfaceIsVisible = visible
        if visible {
            notificationSound.refresh()
            lastAccessoryRefresh = 0
            scheduleBluetoothBatteryRefresh(for: outputState.devices)
        }
        nearbyAccessoryScanner.setActive(visible)
    }

    private let appAudioMixer = AppAudioMixer.shared
    private let displayVolumeController = DisplayVolumeController(diagnosticEvent: { event, succeeded, fields in
        DiagnosticCounters.shared.increment("ddc_operations")
        if !succeeded || event == "activation_read" {
            DiagnosticLog.shared.record("ddc", event, level: succeeded ? "info" : "error", fields: fields)
        }
    })
    private let outputRouteProbe = DefaultOutputRouteProbe()
    private let outputDeviceWriter = DefaultOutputDeviceWriter()
    private let bluetoothBatteryReader = BluetoothBatteryReader()
    private let nearbyAccessoryScanner = NearbyAudioAccessoryScanner()
    private let bluetoothAccessoryConnector = BluetoothAccessoryConnector()
    private var nearbyConnectionTimeoutTask: Task<Void, Never>?
    private let audioAccessoryController = AudioAccessoryController()
    private let defaults = UserDefaults.standard
    private var deviceObserver: CoreAudioDeviceObserver?
    private var refreshTimer: Timer?
    private var pendingOutputApps: [AudioApp]?
    private var retainedOutputAppsDuringRoute: [AudioApp] = []
    private var outputAppRouteRecoveryDeadline: Date?
    private var outputRouteRefreshTask: Task<Void, Never>?
    private var outputDeviceWriteTimeoutTask: Task<Void, Never>?
    private var displayVolumeActivationTask: Task<Void, Never>?
    private var bluetoothBatteryRefreshTask: Task<Void, Never>?
    private var spatialAudioConfirmationTask: Task<Void, Never>?
    private var bluetoothBatteryRecords: [BluetoothBatteryRecord] = []
    private var pendingSpatialAudioSelections: [String: PendingSpatialAudioSelection] = [:]
    private var lastBluetoothBatteryRefresh: Date?
    private var displayVolumeActivationUID: String?
    private var displayVolumeRouteUID: String?
    private var displayVolumeValue: Double?
    private var displayVolumeLastAudibleValue = 0.15
    private var inputLastAudibleVolume = 0.5
    private var outputRouteGeneration: UInt64 = 0
    private var outputDeviceSelectionGeneration: UInt64 = 0
    private var mixerCommandRevision: UInt64 = 0
    private var spatialAudioSelectionRevision: UInt64 = 0
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
    private let routingValidationInterval: TimeInterval = 2
    // Just past the mixer's 0.3 s output stability wait.
    private let deferredRouteRetryDelay: TimeInterval = 0.35
    private let bluetoothBatteryRefreshInterval: TimeInterval = 15
    private let requiredOutputRouteStableReads = 3
    private let maximumOutputRouteStableReadAttempts = 10
    private let systemAudioPermissionNeedsAuthorizationKey = "MacMix.SystemAudioPermissionNeedsAuthorization"
    private static let audioAppBlacklistKey = "MacMix.AudioAppBlacklist"

    override init() {
        audioAppBlacklistState = AudioAppBlacklistState(
            apps: Self.restoredAudioAppBlacklistEntries()
        )
        super.init()
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification, NSWindow.didBecomeKeyNotification,
                     NSWindow.willCloseNotification, NSApplication.didHideNotification,
                     NSApplication.didUnhideNotification] {
            interfaceVisibilityObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                // Defer willClose/didHide until the window has finished updating
                // visibility. Keep weak registrations so retained windows can reopen.
                Task { @MainActor [weak self] in self?.updateAudioInterfaceVisibility() }
            })
        }
        restoreCachedSystemAudioPermissionRequirementState()
        nearbyAccessoryScanner.onChange = { [weak self] in self?.refreshNearbyAccessories() }

        deviceObserver = CoreAudioDeviceObserver(
            onOutputVolumeChange: { [weak self] in self?.handleOutputVolumeChange() },
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
        refreshTimer?.tolerance = 0.05
    }

    deinit {
        for observer in interfaceVisibilityObservers { NotificationCenter.default.removeObserver(observer) }
        outputVolumeTask?.cancel()
        deviceObserver?.stop()
        refreshTimer?.invalidate()
        outputRouteRefreshTask?.cancel()
        outputDeviceWriteTimeoutTask?.cancel()
        displayVolumeActivationTask?.cancel()
        bluetoothBatteryRefreshTask?.cancel()
        spatialAudioConfirmationTask?.cancel()
        nearbyConnectionTimeoutTask?.cancel()
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
        refreshOutputAccessoryControls()
    }

    func refreshOutputState() {
        DiagnosticCounters.shared.increment("output_refresh")
        let previousOutputID = currentOutputDevice?.id
        let previousOutputUID = currentOutputDevice?.uid
        let previousDataSourceID = currentOutputDevice?.dataSourceID
        let previousAirPlaySelection = outputState.airPlayDestinations.filter(\.isCurrent).map(\.selectionID).sorted()
        let previousDeviceUIDs = outputState.devices.map(\.uid)
        let previousRoutingSources = outputState.devices.map(\.selectedDataSourceIDs)
        guard let devices = hardware.devices(for: .output) else {
            return
        }
        setOutputDevicesIfChanged(devices)
        let airPlayDestinations = hardware.airPlayDestinations(in: devices)
        if outputState.airPlayDestinations != airPlayDestinations {
            outputState.airPlayDestinations = airPlayDestinations
        }
        outputRoutingStore.bindLegacyAirPlayDestinations(outputState.routingDestinations)
        routedDeviceVolumes = routedDeviceVolumes.filter { uid, state in
            devices.contains { $0.uid == uid && $0.id == state.deviceID }
        }
        updateBluetoothBatteryMapping(for: devices)
        scheduleBluetoothBatteryRefresh(
            for: devices,
            force: previousDeviceUIDs != devices.map(\.uid)
        )

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

        if previousOutputID != devices.first(where: \.isCurrent)?.id
            || previousOutputUID != currentOutputUID
            || previousDataSourceID != devices.first(where: \.isCurrent)?.dataSourceID
            || previousAirPlaySelection != airPlayDestinations.filter(\.isCurrent).map(\.selectionID).sorted() {
            DiagnosticLog.shared.record("route", "default_output_changed", fields: [
                "reason": previousOutputUID != currentOutputUID ? "uid" : "instance_or_source",
                "previousObject": previousOutputID.map(String.init) ?? "none",
                "object": devices.first(where: \.isCurrent).map { String($0.id) } ?? "none"])
            handleOutputRouteChange(to: currentOutputUID)
        }
        if (previousDeviceUIDs != devices.map(\.uid) || previousRoutingSources != devices.map(\.selectedDataSourceIDs)), previousOutputUID == currentOutputUID,
           outputRoutingStore.isFeatureActive, !outputRoutingStore.selections.isEmpty {
            scheduleMixerReconcile(requestAuthorizationIfDenied: false)
        }
        if let device = currentOutputDevice,
           equalizerStore.isFeatureActive,
           !outputAppsState.apps.isEmpty {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var rate = 0.0
            var size = UInt32(MemoryLayout<Double>.size)
            if AudioObjectGetPropertyData(device.id, &address, 0, nil, &size, &rate) == noErr {
                let changed = equalizerSampleRate != nil && equalizerSampleRate != rate
                equalizerSampleRate = rate
                if changed && previousOutputUID == currentOutputUID {
                    lastSubmittedMixerSnapshot = nil
                    scheduleMixerReconcile(requestAuthorizationIfDenied: false)
                }
            }
        } else { equalizerSampleRate = nil }
        closeSceneIfDeviceUnavailable()
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
        DiagnosticCounters.shared.increment("input_refresh")
        guard let devices = hardware.devices(for: .input) else {
            return
        }
        setInputDevicesIfChanged(devices)

        let current = devices.first(where: \.isCurrent)
        setInputVolumeIfChanged(current?.volume)
        setInputMutedIfChanged(current.map(inputMuteState) ?? false)
        closeSceneIfDeviceUnavailable()
    }

    func refreshOutputApps(stabilize: Bool = true) {
        DiagnosticCounters.shared.increment("process_refresh")
        guard !isOutputRouteTransitioning else {
            return
        }

        guard let detectedApps = hardware.runningOutputApps(
            storedVolume: { [weak self] bundleID in
                self?.storedAppVolume(for: bundleID) ?? 1
            },
            storedMute: { [weak self] bundleID in
                self?.storedAppMute(for: bundleID) ?? false
            }
        ) else {
            return
        }
        let apps = outputAppsExcludingBlacklistedApps(
            outputAppsPreservingRouteSnapshot(detectedApps)
        )

        guard !audioAppsMatch(outputAppsState.snapshots, apps) else {
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
        outputAppsState.replaceApps(with: apps)
        reconcileOutputApps()
    }

    func addAppToBlacklist(_ app: AudioAppState) {
        addAppsToBlacklist(appIDs: [app.id])
    }

    func addAppsToBlacklist(appIDs: Set<String>) {
        let addedApps = outputAppsState.snapshots.filter { appIDs.contains($0.id) }
        guard audioAppBlacklistState.add(addedApps) else {
            return
        }

        didAddAppsToBlacklist(appIDs: appIDs)
    }

    // App ids are bundle ids, so apps chosen on disk match once they play.
    func addApplicationsToBlacklist(at urls: [URL]) {
        let entries = urls.compactMap { url -> AudioAppBlacklistEntry? in
            guard let bundleID = Bundle(url: url)?.bundleIdentifier,
                  bundleID != Bundle.main.bundleIdentifier else {
                return nil
            }
            return AudioAppBlacklistEntry(
                id: bundleID,
                bundleID: bundleID,
                name: FileManager.default.displayName(atPath: url.path),
                icon: NSWorkspace.shared.icon(forFile: url.path)
            )
        }
        guard audioAppBlacklistState.add(entries: entries) else {
            return
        }

        didAddAppsToBlacklist(appIDs: Set(entries.map(\.id)))
    }

    private func didAddAppsToBlacklist(appIDs: Set<String>) {
        persistAudioAppBlacklist()
        pendingOutputApps?.removeAll { appIDs.contains($0.id) }
        retainedOutputAppsDuringRoute.removeAll { appIDs.contains($0.id) }
        outputAppsState.replaceApps(
            with: outputAppsState.snapshots.filter { !appIDs.contains($0.id) }
        )
        reconcileOutputApps()
        refreshOutputAccessoryControls()
    }

    func removeAppFromBlacklist(_ app: AudioAppBlacklistEntry) {
        removeAppsFromBlacklist(appIDs: [app.id])
    }

    func removeAppsFromBlacklist(appIDs: Set<String>) {
        guard audioAppBlacklistState.remove(appIDs: appIDs) else {
            return
        }

        persistAudioAppBlacklist()
        refreshOutputApps(stabilize: false)
        refreshOutputAccessoryControls()
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

        if audioInterfaceIsVisible { scheduleBluetoothBatteryRefresh(for: outputState.devices) }
        refreshOutputApps()
        let now = ProcessInfo.processInfo.systemUptime
        if audioInterfaceIsVisible || pendingSceneControls != nil || !pendingSpatialAudioSelections.isEmpty
            || now - lastAccessoryRefresh >= 5 {
            lastAccessoryRefresh = now
            refreshOutputAccessoryControls()
        }
        if !isMixerLifecycleBusy, Date().timeIntervalSince(lastRoutingValidation) >= routingValidationInterval {
            lastRoutingValidation = Date()
            scheduleMixerReconcile(requestAuthorizationIfDenied: false, validatesRouting: true)
        }
    }

    private func scheduleBluetoothBatteryRefresh(
        for devices: [AudioDevice],
        force: Bool = false
    ) {
        guard CBManager.authorization == .allowedAlways else {
            bluetoothBatteryRefreshTask?.cancel()
            bluetoothBatteryRefreshTask = nil
            bluetoothBatteryRecords = []
            outputState.updateBatteryByDeviceUID([:])
            return
        }

        guard BluetoothBatteryMatcher.shouldReadBattery(for: devices) else {
            outputState.updateBatteryByDeviceUID([:])
            return
        }

        let now = Date()
        if !force,
           let lastBluetoothBatteryRefresh,
           now.timeIntervalSince(lastBluetoothBatteryRefresh) < bluetoothBatteryRefreshInterval {
            return
        }

        guard bluetoothBatteryRefreshTask == nil else {
            return
        }

        lastBluetoothBatteryRefresh = now
        let reader = bluetoothBatteryReader
        bluetoothBatteryRefreshTask = Task { @MainActor [weak self] in
            let records = await reader.read()
            guard !Task.isCancelled, let self else {
                return
            }

            bluetoothBatteryRefreshTask = nil
            guard let records else {
                return
            }

            // A connected Core Audio Bluetooth route paired with an empty report is
            // usually a transient system_profiler controller read. Preserve the last
            // known values until the route disappears or a valid report arrives.
            if !records.isEmpty {
                bluetoothBatteryRecords = records
            }
            updateBluetoothBatteryMapping(for: outputState.devices)
        }
    }

    private func updateBluetoothBatteryMapping(for devices: [AudioDevice]) {
        outputState.updateBatteryByDeviceUID(
            BluetoothBatteryMatcher.batteryByDeviceUID(
                devices: devices,
                records: bluetoothBatteryRecords
            )
        )
    }

    private func refreshOutputAccessoryControls() {
        let activeProcessIDs = spatialAudioProcessIDs()
        let currentDeviceUID = outputState.currentDevice?.uid
        pendingSpatialAudioSelections = pendingSpatialAudioSelections.filter {
            $0.key == currentDeviceUID
        }
        var controlsByDeviceUID: [String: AudioAccessoryControlState] = [:]

        for device in outputState.devices {
            let processIDs = device.isCurrent ? activeProcessIDs : []
            guard let controls = audioAccessoryController.state(
                for: device.id,
                activeProcessIDs: processIDs
            ) else {
                continue
            }

            if let pendingSelection = pendingSpatialAudioSelections[device.uid] {
                if controls.spatialAudioMode == pendingSelection.mode
                    || Date() >= pendingSelection.deadline {
                    pendingSpatialAudioSelections.removeValue(forKey: device.uid)
                    controlsByDeviceUID[device.uid] = controls
                } else {
                    controlsByDeviceUID[device.uid] = controls.overridingSpatialAudioMode(
                        pendingSelection.mode
                    )
                }
            } else {
                controlsByDeviceUID[device.uid] = controls
            }
        }

        outputState.updateAccessoryControlsByDeviceUID(controlsByDeviceUID)
        retryPendingSceneControls()
    }

    func setListeningMode(_ mode: ListeningMode, for device: AudioDevice) {
        if pendingSceneControls?.deviceUID == device.uid {
            pendingSceneControls?.listening = nil
        }
        defer { recordSceneEdit { if $0.output?.uid == device.uid { $0.output?.listeningMode = mode.rawValue } } }
        let succeeded = audioAccessoryController.setListeningMode(mode, for: device.id)
        DiagnosticLog.shared.record("accessory", "listening_mode_write", level: succeeded ? "info" : "error", fields: [
            "device": DiagnosticLog.shared.anonymous(device.uid), "requested": String(mode.rawValue), "writeSucceeded": String(succeeded)])
        refreshOutputAccessoryControls()
    }

    func setSpatialAudioMode(_ mode: SpatialAudioMode, for device: AudioDevice) {
        guard device.isCurrent else {
            return
        }
        if pendingSceneControls?.deviceUID == device.uid {
            pendingSceneControls?.spatial = nil
        }

        let processIDs = spatialAudioProcessIDs()
        let didSet = audioAccessoryController.setSpatialAudioMode(
            mode,
            for: device.id,
            processIDs: processIDs
        )
        DiagnosticLog.shared.record("accessory", "spatial_mode_write", level: didSet ? "info" : "error", fields: [
            "device": DiagnosticLog.shared.anonymous(device.uid), "requested": String(mode.rawValue), "writeSucceeded": String(didSet)])
        guard didSet else {
            refreshOutputAccessoryControls()
            return
        }
        recordSceneEdit { if $0.output?.uid == device.uid { $0.output?.spatialAudioMode = mode.rawValue } }

        spatialAudioSelectionRevision &+= 1
        let revision = spatialAudioSelectionRevision
        pendingSpatialAudioSelections[device.uid] = PendingSpatialAudioSelection(
            mode: mode,
            deadline: Date().addingTimeInterval(2.1)
        )
        refreshOutputAccessoryControls()
        scheduleSpatialAudioConfirmation(for: device.uid, revision: revision)
    }

    private func scheduleSpatialAudioConfirmation(for deviceUID: String, revision: UInt64) {
        spatialAudioConfirmationTask?.cancel()
        spatialAudioConfirmationTask = Task { @MainActor [weak self] in
            let delays: [UInt64] = [50, 100, 150, 250, 400, 500, 750]

            for delay in delays {
                try? await Task.sleep(nanoseconds: delay * 1_000_000)
                guard !Task.isCancelled,
                      let self,
                      self.spatialAudioSelectionRevision == revision else {
                    return
                }

                self.refreshOutputAccessoryControls()
                if self.pendingSpatialAudioSelections[deviceUID] == nil {
                    return
                }
            }
        }
    }

    private func spatialAudioProcessIDs() -> [pid_t] {
        outputAppsState.apps.flatMap { app in
            hardware.runningOutputProcessIDs(
                forAudioProcessObjectIDs: app.audioObjectIDs
            )
        }
    }

    func setSystemOutputVolume(_ volume: Double) {
        defer {
            if let value = outputState.systemVolume {
                recordSceneEdit { $0.output?.recordVolume(value, deviceUID: currentOutputDevice?.uid) }
            }
        }
        guard let currentOutputDevice else {
            return
        }

        let clampedVolume = max(0, min(1, volume))
        DiagnosticActions.shared.coalesce("audio", "system_volume_requested", target: currentOutputDevice.uid,
            value: String(format: "%.4f", clampedVolume))
        let shouldMute = clampedVolume == 0
        if displayVolumeRouteUID == currentOutputDevice.uid {
            // Each coalesced DDC volume operation carries its own mute intent.
            displayVolumeController.setVolume(clampedVolume, routeUID: currentOutputDevice.uid)
            displayVolumeValue = clampedVolume
            if clampedVolume > 0 { displayVolumeLastAudibleValue = clampedVolume }
            setSystemOutputVolumeIfChanged(clampedVolume)
            setSystemOutputMutedIfChanged(shouldMute)
            return
        }

        setSystemOutputVolumeIfChanged(clampedVolume)
        setSystemOutputMutedIfChanged(shouldMute)
        setCurrentOutputDeviceVolume(clampedVolume)
        scheduleOutputVolumeUpdate(volume: clampedVolume, muted: shouldMute)
    }

    func toggleSystemOutputMute() {
        defer { recordPanelSceneState() }
        guard let currentOutputDevice else {
            return
        }

        let shouldMute = !outputState.isSystemMuted
        DiagnosticLog.shared.record("audio", "system_mute_requested", fields: [
            "device": DiagnosticLog.shared.anonymous(currentOutputDevice.uid), "muted": String(shouldMute)])
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

        setSystemOutputMutedIfChanged(shouldMute)
        scheduleOutputVolumeUpdate(muted: shouldMute)
    }

    func setInputVolume(_ volume: Double) {
        defer {
            if let value = inputState.inputVolume { recordSceneEdit { $0.input?.recordVolume(value, deviceUID: currentInputDevice?.uid) } }
        }
        guard let deviceID = currentInputDevice?.id else {
            return
        }

        let clampedVolume = max(0, min(1, volume))
        guard hardware.setVolume(clampedVolume, for: deviceID, direction: .input) else {
            refreshInputState()
            return
        }

        // Match the output slider: exact zero mutes, any audible edit unmutes.
        let shouldMute = clampedVolume == 0
        if let isMuted = hardware.isMuted(for: deviceID, direction: .input), isMuted != shouldMute {
            hardware.setMuted(shouldMute, for: deviceID, direction: .input)
        }

        let appliedVolume = hardware.volume(for: deviceID, direction: .input) ?? clampedVolume
        if appliedVolume > 0.001 { inputLastAudibleVolume = appliedVolume }
        setInputVolumeIfChanged(appliedVolume)
        setCurrentInputDeviceVolume(appliedVolume)
        if let device = currentInputDevice { setInputMutedIfChanged(inputMuteState(device)) }
    }

    func toggleInputMute() {
        defer { recordPanelSceneState() }
        guard let device = currentInputDevice else {
            return
        }

        let shouldMute = !inputState.isInputMuted
        DiagnosticLog.shared.record("audio", "input_mute_requested", fields: [
            "device": DiagnosticLog.shared.anonymous(device.uid), "muted": String(shouldMute)])
        if hardware.isMuted(for: device.id, direction: .input) != nil {
            hardware.setMuted(shouldMute, for: device.id, direction: .input)
            setInputMutedIfChanged(inputMuteState(device))
            return
        }

        // Devices without a mute control are silenced at exact zero, like DDC displays.
        if shouldMute, let volume = inputState.inputVolume, volume > 0.001 {
            inputLastAudibleVolume = volume
        }
        guard hardware.setVolume(shouldMute ? 0 : inputLastAudibleVolume, for: device.id, direction: .input) else {
            refreshInputState()
            return
        }
        let appliedVolume = hardware.volume(for: device.id, direction: .input)
        setInputVolumeIfChanged(appliedVolume)
        if let appliedVolume { setCurrentInputDeviceVolume(appliedVolume) }
        setInputMutedIfChanged(appliedVolume == 0)
    }

    private func inputMuteState(_ device: AudioDevice) -> Bool {
        hardware.isMuted(for: device.id, direction: .input) ?? (device.volume == 0)
    }

    func selectOutputDevice(_ device: AudioDevice) {
        guard !outputSelectionMatches(device) else {
            return
        }

        DiagnosticLog.shared.record("route", "output_selection_requested", fields: [
            "device": DiagnosticLog.shared.anonymous(device.selectionID)])
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
        let switchTargets = outputAppsPreservingRouteSnapshot(outputAppsState.snapshots)
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

            DiagnosticLog.shared.record("route", "output_write_timeout", level: "error", fields: [
                "revision": String(commandRevision), "device": DiagnosticLog.shared.anonymous(device.selectionID)])
            outputDeviceWriteTimeoutTask = nil
            outputDeviceSelectionGeneration &+= 1
            let routeGenerationBeforeFinish = outputRouteGeneration
            finishMixerLifecycle(revision: commandRevision)
            if outputRouteGeneration == routeGenerationBeforeFinish {
                refreshOutputState()
            }

            if outputSelectionMatches(device) {
                if outputRouteGeneration == routeGenerationBeforeFinish {
                    handleOutputRouteChange(to: device.uid)
                }
            } else {
                recoverFromOutputDeviceSelectionFailure(revision: commandRevision)
            }
        }

        outputDeviceWriter.select(device.id, dataSourceID: device.dataSourceID) { [weak self] succeeded in
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

                DiagnosticLog.shared.record("route", "output_write_result", level: succeeded ? "info" : "error", fields: [
                    "revision": String(commandRevision), "writeSucceeded": String(succeeded),
                    "selectionConfirmed": String(outputSelectionMatches(device)),
                    "device": DiagnosticLog.shared.anonymous(device.selectionID)])
                if (device.dataSourceID == nil || succeeded) && outputSelectionMatches(device) {
                    if let current = currentOutputDevice {
                        let saved = sceneDevicePreset(current, direction: .output)
                        recordSceneEdit { $0.output = saved }
                    }
                    if outputRouteGeneration == routeGenerationBeforeFinish {
                        handleOutputRouteChange(to: device.uid)
                    }
                } else {
                    recoverFromOutputDeviceSelectionFailure(revision: commandRevision)
                }
            }
        }
    }

    private func outputSelectionMatches(_ device: AudioDevice) -> Bool {
        outputState.isSelected(device)
    }

    func selectInputDevice(_ device: AudioDevice) {
        inputDeviceUserSelectionDidChange?(device.uid)
        applyInputDeviceSelection(device)
        if let current = currentInputDevice {
            let saved = sceneDevicePreset(current, direction: .input)
            recordSceneEdit { $0.input = saved }
        }
    }

    func restoreInputDevice(uid: String) {
        guard let device = inputState.devices.first(where: { $0.uid == uid }) else {
            return
        }

        applyInputDeviceSelection(device)
    }

    private func applyInputDeviceSelection(_ device: AudioDevice) {
        guard !device.isCurrent else {
            return
        }

        DiagnosticLog.shared.record("route", "input_selection_requested", fields: [
            "device": DiagnosticLog.shared.anonymous(device.uid)])
        hardware.setDefaultDevice(device.id, direction: .input)
        refreshInputState()
        DiagnosticLog.shared.record("route", "input_selection_result", fields: [
            "confirmed": String(currentInputDevice?.uid == device.uid)])
    }

    func setAppVolume(_ volume: Double, for app: AudioAppState) {
        let clampedVolume = max(0, min(maximumVolume(for: app.bundleID), volume))
        DiagnosticActions.shared.coalesce("audio", "app_volume_requested", target: app.bundleID,
            value: String(format: "%.4f", clampedVolume))
        defer {
            recordSceneEdit { scene in
                scene.recordApp(AudioSceneApp(id: app.bundleID, name: app.name,
                    volume: clampedVolume, isMuted: false))
            }
        }
        defaults.set(clampedVolume, forKey: defaultsKey(for: app.bundleID))

        if let currentApp = outputAppsState.apps.first(where: { $0.id == app.id }) {
            let shouldUnmute = currentApp.isMuted
            guard !nearlyEqual(currentApp.volume, clampedVolume) || shouldUnmute else {
                return
            }

            currentApp.updateControls(volume: clampedVolume, isMuted: false)
            if shouldUnmute {
                defaults.set(false, forKey: muteDefaultsKey(for: app.bundleID))
            }
            scheduleMixerReconcile(requestAuthorizationIfDenied: true)
        } else {
            var updatedApp = app.snapshot
            updatedApp.volume = clampedVolume
            updatedApp.isMuted = false
            defaults.set(false, forKey: muteDefaultsKey(for: app.bundleID))
            scheduleMixerReconcile(
                additionalTarget: updatedApp,
                requestAuthorizationIfDenied: true
            )
        }
    }

    // Route switching is asynchronous. Wait for the requested route before writing
    // its volume or reconciling apps, so a scene never changes the previous device.
    private(set) var isApplyingScene = false
    let sceneStore = AudioSceneStore()
    let sceneShortcuts = SceneShortcutController()
    private(set) var activeSceneID: UUID?
    private let sceneNotice = SceneActivationNoticeController()
    var sceneDidSwitch: ((ScenePanelFeedback) -> Void)?
    private var sceneActivationTask: Task<Void, Never>?
    private var sceneAccessEnabled = false
    private var hasScheduledStartupScene = false
    private var startupSceneTask: Task<Void, Never>?
    private static let sceneControlLog = Logger(subsystem: "jazmin.MacMix", category: "SceneListeningMode")
    private struct PendingSceneControls {
        let sceneID: UUID
        let deviceUID: String
        var listening: ListeningMode?
        var spatial: SpatialAudioMode?
        var lastAttempt = Date.distantPast
        var hasWrittenListening = false
        var listeningConfirmedSince: Date?
        var listeningResynchronizationMode: ListeningMode?
    }
    private var pendingSceneControls: PendingSceneControls?

    private func retryPendingSceneControls() {
        if let pending = pendingSceneControls,
           pending.sceneID != activeSceneID || pending.deviceUID != currentOutputDevice?.uid {
            pendingSceneControls = nil
        }
        guard !isApplyingScene, sceneActivationTask == nil,
              var pending = pendingSceneControls,
              pending.sceneID == activeSceneID,
              let device = currentOutputDevice, device.uid == pending.deviceUID,
              Date().timeIntervalSince(pending.lastAttempt) >= 0.5 else { return }
        let processIDs = spatialAudioProcessIDs()
        guard let state = audioAccessoryController.state(for: device.id, activeProcessIDs: processIDs) else { return }
        pending.lastAttempt = Date()
        if let mode = pending.listening {
            if let intermediate = pending.listeningResynchronizationMode,
               state.supportedListeningModes.contains(mode),
               state.supportedListeningModes.contains(intermediate) {
                pending.listeningResynchronizationMode = nil
                _ = audioAccessoryController.setListeningMode(intermediate, for: device.id)
                pending.hasWrittenListening = false
                pending.listeningConfirmedSince = nil
                pendingSceneControls = pending
                Self.sceneControlLog.info("Startup listening resync: target=\(mode.rawValue), intermediate=\(intermediate.rawValue)")
                return
            }
            if pending.hasWrittenListening, state.listeningMode == mode {
                if let since = pending.listeningConfirmedSince, Date().timeIntervalSince(since) >= 2 {
                    pending.listening = nil
                    Self.sceneControlLog.info("Scene listening mode confirmed: \(mode.rawValue)")
                } else if pending.listeningConfirmedSince == nil {
                    pending.listeningConfirmedSince = Date()
                }
            } else if state.supportedListeningModes.contains(mode) {
                pending.listeningConfirmedSince = nil
                let didSet = audioAccessoryController.setListeningMode(mode, for: device.id)
                pending.hasWrittenListening = didSet
                Self.sceneControlLog.info("Scene listening mode write: target=\(mode.rawValue), before=\(state.listeningMode?.rawValue ?? 0), verified=\(didSet)")
            }
        }
        if let mode = pending.spatial, state.canSetSpatialAudio {
            if state.spatialAudioMode == mode {
                pending.spatial = nil
            } else {
                _ = audioAccessoryController.setSpatialAudioMode(mode, for: device.id, processIDs: processIDs)
            }
        }
        pendingSceneControls = pending.listening == nil && pending.spatial == nil ? nil : pending
    }

    func updateSceneAccess(_ enabled: Bool) {
        guard sceneAccessEnabled != enabled else { return }
        sceneAccessEnabled = enabled
        sceneShortcuts.onDigit = { [weak self] digit in
            guard let self, self.sceneAccessEnabled else { return }
            if digit == 0 {
                self.selectScene(nil)
            } else if self.sceneStore.presets.indices.contains(digit - 1) {
                self.selectScene(self.sceneStore.presets[digit - 1].id)
            }
        }
        sceneShortcuts.configure(SceneShortcutModifiers(rawValue: sceneStore.shortcutModifiers) ?? .controlOption,
                                 enabled: enabled)
        if enabled {
            if !hasScheduledStartupScene {
                hasScheduledStartupScene = true
                let savedSelection = sceneStore.selection
                startupSceneTask = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(3)) }
                    catch { return }
                    guard let self, !Task.isCancelled, sceneAccessEnabled,
                          sceneStore.selection == savedSelection else { return }
                    startupSceneTask = nil
                    Self.sceneControlLog.info("Restoring startup scene after delay")
                    selectScene(savedSelection, resynchronizesListeningMode: true)
                }
            } else {
                selectScene(sceneStore.selection)
            }
        } else {
            selectScene(nil)
        }
    }

    func changeSceneShortcut(_ modifiers: SceneShortcutModifiers) {
        if sceneShortcuts.configure(modifiers, enabled: sceneAccessEnabled) {
            sceneStore.shortcutModifiers = modifiers.rawValue
        }
    }

    func selectScene(_ id: UUID?, resynchronizesListeningMode: Bool = false) {
        guard id == nil || sceneAccessEnabled else { return }
        let diagnosticOperation = UUID().uuidString
        let diagnosticStart = DispatchTime.now().uptimeNanoseconds
        DiagnosticLog.shared.record("scene", "selection_requested", fields: [
            "operation": diagnosticOperation, "scene": id.map { DiagnosticLog.shared.anonymous($0.uuidString) } ?? "off"])
        startupSceneTask?.cancel()
        startupSceneTask = nil
        pendingSceneControls = nil
        sceneNotice.dismiss()
        sceneStore.selection = id
        // Retain the last successful scene until the new route is fully applied.
        let previous = sceneActivationTask
        previous?.cancel()
        sceneActivationTask = Task { @MainActor [weak self] in
            var diagnosticResult = "cancelled"
            defer {
                DiagnosticLog.shared.record("scene", "selection_finished", fields: [
                    "operation": diagnosticOperation, "result": diagnosticResult,
                    "durationMs": String((DispatchTime.now().uptimeNanoseconds - diagnosticStart) / 1_000_000)])
            }
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            let previousID = activeSceneID
            let previousPreset = sceneStore.presets.first { $0.id == previousID }
            let result: AudioSceneApplicationResult
            var requestedControls: PendingSceneControls?
            var needsRollback = previous != nil
            // Read the latest preset after the previous route write settles.
            if let id, let scene = sceneStore.presets.first(where: { $0.id == id }) {
                let missingNames = scene.unavailableDeviceNames(
                    outputUIDs: Set(outputState.devices.map(\.uid)), inputUIDs: Set(inputState.devices.map(\.uid)))
                if missingNames.isEmpty {
                    if let output = scene.output {
                        requestedControls = PendingSceneControls(sceneID: id, deviceUID: output.uid,
                            listening: output.listeningMode.flatMap(ListeningMode.init(rawValue:)),
                            spatial: output.spatialAudioMode.flatMap(SpatialAudioMode.init(rawValue:)))
                    }
                    captureSceneBaselineIfNeeded()
                    needsRollback = true
                    result = await applyScene(scene, capturesStartupListeningMode: resynchronizesListeningMode)
                    if resynchronizesListeningMode,
                       startupListeningModeBeforeWrite != requestedControls?.listening {
                        requestedControls?.listeningResynchronizationMode = startupListeningModeBeforeWrite
                    }
                } else {
                    result = .unavailableDevices(missingNames)
                }
            } else {
                needsRollback = true
                result = await restoreSceneBaseline()
            }
            guard !Task.isCancelled, sceneStore.selection == id else { return }
            switch result {
            case .applied: diagnosticResult = "applied"
            case .unavailableDevices: diagnosticResult = "unavailable_devices"
            case .failed: diagnosticResult = "failed"
            }
            if result.succeeded {
                activeSceneID = id
                if sceneStore.launchesMixedApps, let id,
                   let scene = sceneStore.presets.first(where: { $0.id == id }) {
                    launchMissingSceneApps(scene)
                }
                pendingSceneControls = requestedControls
                if id != previousID, let preset = sceneStore.presets.first(where: { $0.id == id }) ?? previousPreset {
                    let index = sceneStore.presets.firstIndex(where: { $0.id == preset.id }) ?? 0
                    sceneDidSwitch?(ScenePanelFeedback(name: preset.displayName(at: index), symbol: preset.symbol,
                                                      color: preset.color, isEnabled: id != nil))
                }
            } else {
                // Missing devices are rejected before writes. Other failures may
                // have changed a route, so restore the last successful selection.
                if needsRollback {
                    DiagnosticLog.shared.record("scene", "rollback_started", fields: ["operation": diagnosticOperation])
                    if let previousID, let previousScene = sceneStore.presets.first(where: { $0.id == previousID }) {
                        _ = await applyScene(previousScene)
                    } else {
                        _ = await restoreSceneBaseline()
                    }
                }
                guard !Task.isCancelled, sceneStore.selection == id else { return }
                sceneStore.selection = previousID
            }
            if result != .applied { sceneNotice.present(message: result.message) }
            sceneActivationTask = nil
            refreshOutputAccessoryControls()
        }
    }
    private var isUpdatingSceneAudio = false
    private var launchingSceneAppIDs: Set<String> = []

    private func launchMissingSceneApps(_ scene: AudioScenePreset) {
        for app in scene.apps {
            guard NSRunningApplication.runningApplications(withBundleIdentifier: app.id).isEmpty,
                  !launchingSceneAppIDs.contains(app.id) else { continue }
            let savedURL = app.path.map { URL(fileURLWithPath: $0) }
            let verifiedURL = savedURL.flatMap { Bundle(url: $0)?.bundleIdentifier == app.id ? $0 : nil }
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.id) ?? verifiedURL else { continue }
            launchingSceneAppIDs.insert(app.id)
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.launchingSceneAppIDs.remove(app.id) }
            }
        }
    }

    private func closeSceneIfDeviceUnavailable() {
        guard sceneActivationTask == nil, !isApplyingScene,
              let id = activeSceneID,
              let preset = sceneStore.presets.first(where: { $0.id == id }) else { return }
        let missing = preset.unavailableDeviceNames(
            outputUIDs: Set(outputState.devices.map(\.uid)),
            inputUIDs: Set(inputState.devices.map(\.uid)))
        guard !missing.isEmpty else { return }
        // Preserve the saved device; the system's fallback is not a user edit.
        activeSceneID = nil
        sceneStore.selection = nil
        sceneActivationTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            _ = await restoreSceneBaseline(keepingCurrentDevices: true)
            guard !Task.isCancelled else { return }
            sceneActivationTask = nil
            sceneNotice.present(message: AudioSceneApplicationResult.unavailableDevices(missing).message
                + "\n" + String(localized: "Scene presets have been turned off."))
        }
    }

    private func recordSceneEdit(_ edit: (inout AudioScenePreset) -> Void) {
        guard sceneActivationTask == nil, !isApplyingScene, !isUpdatingSceneAudio, sceneBaseline != nil,
              let id = activeSceneID, let index = sceneStore.presets.firstIndex(where: { $0.id == id }) else { return }
        var preset = sceneStore.presets[index]
        edit(&preset)
        if preset != sceneStore.presets[index] { sceneStore.updateFromAudio(preset, at: index) }
        sceneAppliedAppIDs.formUnion(preset.apps.map(\.id))
    }

    // Device refreshes must not copy the shared live app mix into a preset.
    // App values are persisted only by explicit app-control edits.
    // Route transitions and scene application are excluded by recordSceneEdit.
    private func recordPanelSceneState() {
        guard !isOutputRouteTransitioning else { return }
        recordSceneEdit { scene in
            if let device = currentOutputDevice,
               scene.output?.uid == device.uid {
                if let volume = outputState.systemVolume { scene.output?.volume = volume }
                scene.output?.isMuted = outputState.isSystemMuted
            }
            if let device = currentInputDevice,
               scene.input?.uid == device.uid {
                if let volume = inputState.inputVolume { scene.input?.volume = volume }
                scene.input?.isMuted = inputState.isInputMuted
            }
        }
    }

    func applySceneEdits(_ scene: AudioScenePreset, previous: AudioScenePreset) -> Bool {
        guard activeSceneID == scene.id, sceneActivationTask == nil, !isApplyingScene, scene.output?.uid == previous.output?.uid,
              scene.input?.uid == previous.input?.uid,
              scene.apps.map(\.id) == previous.apps.map(\.id) else { return false }
        isUpdatingSceneAudio = true
        defer { isUpdatingSceneAudio = false }
        if let output = scene.output, currentOutputDevice?.uid == output.uid {
            if output.volume != previous.output?.volume { setSystemOutputVolume(output.volume) }
            if let muted = output.isMuted, outputState.isSystemMuted != muted {
                toggleSystemOutputMute()
            }
            if output.listeningMode != previous.output?.listeningMode,
               let raw = output.listeningMode, let mode = ListeningMode(rawValue: raw), let device = currentOutputDevice {
                setListeningMode(mode, for: device)
            }
            if output.spatialAudioMode != previous.output?.spatialAudioMode,
               let raw = output.spatialAudioMode, let mode = SpatialAudioMode(rawValue: raw), let device = currentOutputDevice {
                setSpatialAudioMode(mode, for: device)
            }
        }
        if let input = scene.input, currentInputDevice?.uid == input.uid {
            if input.volume != previous.input?.volume { setInputVolume(input.volume) }
            if let muted = input.isMuted, inputState.isInputMuted != muted { toggleInputMute() }
        }
        var mixChanged = false
        for app in scene.apps {
            guard let old = previous.apps.first(where: { $0.id == app.id }),
                  old.volume != app.volume || old.isMuted != app.isMuted else { continue }
            let volume = max(0, min(maximumVolume(for: app.id), app.volume))
            defaults.set(volume, forKey: defaultsKey(for: app.id))
            defaults.set(app.isMuted ?? false, forKey: muteDefaultsKey(for: app.id))
            for current in outputAppsState.apps where current.bundleID == app.id {
                current.updateControls(volume: volume, isMuted: app.isMuted ?? false)
            }
            mixChanged = true
        }
        if mixChanged { scheduleMixerReconcile(requestAuthorizationIfDenied: true) }
        return true
    }
    private struct SceneBaseline {
        let route: AudioScenePreset
        let appPreferences: [String: Any]
        let isMuted: Bool
    }
    private var sceneBaseline: SceneBaseline?
    private var sceneAppliedAppIDs: Set<String> = []

    func captureSceneBaselineIfNeeded() {
        guard sceneBaseline == nil else { return }
        var preferences = defaults.dictionaryRepresentation().filter {
            $0.key.hasPrefix("AppVolume.") || $0.key.hasPrefix("AppMuted.")
        }
        for app in outputAppsState.apps {
            preferences[defaultsKey(for: app.bundleID)] = app.volume
            preferences[muteDefaultsKey(for: app.bundleID)] = app.isMuted
        }
        sceneBaseline = SceneBaseline(
            route: AudioScenePreset(name: "", symbol: "", color: "",
                output: currentOutputDevice.map { sceneDevicePreset($0, direction: .output) },
                input: currentInputDevice.map { sceneDevicePreset($0, direction: .input) }),
            appPreferences: preferences, isMuted: outputState.isSystemMuted)
    }

    func restoreSceneBaseline(keepingCurrentDevices: Bool = false) async -> AudioSceneApplicationResult {
        guard let baseline = sceneBaseline else { return .applied }
        let result: AudioSceneApplicationResult = keepingCurrentDevices ? .applied : await applyScene(baseline.route)
        guard !Task.isCancelled, result.succeeded else { return result }
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("AppVolume.") || key.hasPrefix("AppMuted.") {
            defaults.removeObject(forKey: key)
        }
        for (key, value) in baseline.appPreferences {
            if key.hasPrefix("AppVolume."), let volume = value as? Double {
                let bundleID = String(key.dropFirst("AppVolume.".count))
                defaults.set(max(0, min(maximumVolume(for: bundleID), volume)), forKey: key)
            } else { defaults.set(value, forKey: key) }
        }
        for app in outputAppsState.apps {
            app.updateControls(volume: storedAppVolume(for: app.bundleID),
                               isMuted: baseline.appPreferences[muteDefaultsKey(for: app.bundleID)] as? Bool ?? false)
        }
        if !keepingCurrentDevices, currentOutputDevice?.uid == baseline.route.output?.uid,
           outputState.isSystemMuted != baseline.isMuted { toggleSystemOutputMute() }
        scheduleMixerReconcile(requestAuthorizationIfDenied: true)
        sceneBaseline = nil
        sceneAppliedAppIDs.removeAll()
        return result
    }

    func sceneDevicePreset(_ device: AudioDevice, direction: AudioDeviceDirection) -> AudioSceneDevice {
        let controls = direction == .output ? outputState.accessoryControlsByDeviceUID[device.uid] : nil
        let volume = device.isCurrent
            ? (direction == .output ? outputState.systemVolume : inputState.inputVolume)
            : device.volume
        return AudioSceneDevice(uid: device.uid, name: device.name, volume: volume ?? 1,
                                listeningMode: controls?.listeningMode?.rawValue,
                                spatialAudioMode: controls?.spatialAudioMode?.rawValue,
                                iconName: device.iconName,
                                systemIconData: device.systemIcon?.tiffRepresentation,
                                isMuted: device.isCurrent
                                    ? (direction == .output ? outputState.isSystemMuted : inputState.isInputMuted)
                                    : nil)
    }

    private var startupListeningModeBeforeWrite: ListeningMode?

    func applyScene(_ scene: AudioScenePreset, capturesStartupListeningMode: Bool = false) async -> AudioSceneApplicationResult {
        guard !Task.isCancelled, !isApplyingScene else { return .failed }
        isApplyingScene = true
        if capturesStartupListeningMode { startupListeningModeBeforeWrite = nil }
        defer { isApplyingScene = false }
        var unavailable: [String] = []
        // Let an earlier hardware route write settle before selecting from fresh devices.
        for _ in 0..<100 where isOutputRouteTransitioning {
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { return .failed }
        }
        guard !Task.isCancelled, !isOutputRouteTransitioning else {
            return .failed
        }
        let missingNames = scene.unavailableDeviceNames(
            outputUIDs: Set(outputState.devices.map(\.uid)), inputUIDs: Set(inputState.devices.map(\.uid)))
        guard missingNames.isEmpty else { return .unavailableDevices(missingNames) }
        if let output = scene.output {
            if let device = outputState.devices.first(where: { $0.uid == output.uid }) {
                if currentOutputDevice?.uid != output.uid { selectOutputDevice(device) }
                for _ in 0..<100 {
                    if !isOutputRouteTransitioning { break }
                    do { try await Task.sleep(for: .milliseconds(100)) }
                    catch { return .failed }
                }
                guard !Task.isCancelled, currentOutputDevice?.uid == output.uid, !isOutputRouteTransitioning else {
                    return .failed
                }
                setSystemOutputVolume(output.volume)
                if let muted = output.isMuted, outputState.isSystemMuted != muted {
                    toggleSystemOutputMute()
                }
                refreshOutputAccessoryControls()
                if let activeDevice = currentOutputDevice,
                   let controls = outputState.accessoryControlsByDeviceUID[output.uid] {
                    if let raw = output.listeningMode, let mode = ListeningMode(rawValue: raw),
                       controls.supportedListeningModes.contains(mode) {
                        if capturesStartupListeningMode {
                            // Capture before the first write: HAL can echo a requested
                            // value even when the headphones have not applied it.
                            startupListeningModeBeforeWrite = controls.listeningMode
                        }
                        if !capturesStartupListeningMode || controls.listeningMode != mode {
                            setListeningMode(mode, for: activeDevice)
                        }
                    }
                    if let raw = output.spatialAudioMode, let mode = SpatialAudioMode(rawValue: raw),
                       controls.supportsSpatialAudio, controls.canSetSpatialAudio {
                        setSpatialAudioMode(mode, for: activeDevice)
                    }
                }
            } else { unavailable.append(output.name) }
        }
        if let input = scene.input {
            if let device = inputState.devices.first(where: { $0.uid == input.uid }) {
                if currentInputDevice?.uid != input.uid { selectInputDevice(device) }
                if currentInputDevice?.uid == input.uid {
                    setInputVolume(input.volume)
                    if let muted = input.isMuted, inputState.isInputMuted != muted { toggleInputMute() }
                } else { unavailable.append(input.name) }
            } else { unavailable.append(input.name) }
        }
        let nextAppIDs = Set(scene.apps.map(\.id))
        if let baseline = sceneBaseline {
            for id in sceneAppliedAppIDs.subtracting(nextAppIDs) {
                let volumeKey = defaultsKey(for: id)
                let muteKey = muteDefaultsKey(for: id)
                if let value = baseline.appPreferences[volumeKey] as? Double {
                    defaults.set(max(0, min(maximumVolume(for: id), value)), forKey: volumeKey)
                }
                else { defaults.removeObject(forKey: volumeKey) }
                if let value = baseline.appPreferences[muteKey] { defaults.set(value, forKey: muteKey) }
                else { defaults.removeObject(forKey: muteKey) }
                for current in outputAppsState.apps where current.bundleID == id {
                    current.updateControls(volume: storedAppVolume(for: id),
                                           isMuted: baseline.appPreferences[muteKey] as? Bool ?? false)
                }
            }
        }
        sceneAppliedAppIDs = nextAppIDs
        for app in scene.apps {
            let volume = max(0, min(maximumVolume(for: app.id), app.volume))
            defaults.set(volume, forKey: defaultsKey(for: app.id))
            defaults.set(app.isMuted ?? false, forKey: muteDefaultsKey(for: app.id))
            for current in outputAppsState.apps where current.bundleID == app.id {
                current.updateControls(volume: volume, isMuted: app.isMuted ?? false)
            }
        }
        scheduleMixerReconcile(requestAuthorizationIfDenied: true)
        return unavailable.isEmpty ? .applied : .unavailableDevices(unavailable)
    }

    func toggleAppMute(_ app: AudioAppState) {
        DiagnosticLog.shared.record("audio", "app_mute_requested", fields: [
            "app": DiagnosticLog.shared.anonymous(app.bundleID), "muted": String(!app.isMuted)])
        let isMuted = !app.isMuted
        recordSceneEdit { scene in
            scene.recordApp(AudioSceneApp(id: app.bundleID, name: app.name,
                volume: app.volume, isMuted: isMuted))
        }
        defaults.set(isMuted, forKey: muteDefaultsKey(for: app.bundleID))

        if let currentApp = outputAppsState.apps.first(where: { $0.id == app.id }) {
            currentApp.updateControls(volume: currentApp.volume, isMuted: isMuted)
            scheduleMixerReconcile(requestAuthorizationIfDenied: true)
        } else {
            var updatedApp = app.snapshot
            updatedApp.isMuted = isMuted
            scheduleMixerReconcile(
                additionalTarget: updatedApp,
                requestAuthorizationIfDenied: true
            )
        }
    }

    func clampAppVolumesToUnity() {
        var didChangeVolume = false

        for app in outputAppsState.apps where app.volume > 1 {
            app.updateControls(volume: 1, isMuted: app.isMuted)
            defaults.set(1, forKey: defaultsKey(for: app.bundleID))
            recordSceneEdit { scene in
                scene.recordApp(AudioSceneApp(id: app.bundleID, name: app.name,
                    volume: 1, isMuted: app.isMuted))
            }
            didChangeVolume = true
        }

        if didChangeVolume {
            scheduleMixerReconcile(requestAuthorizationIfDenied: true)
        }
    }

    private func reconcileOutputApps() {
        scheduleMixerReconcile(requestAuthorizationIfDenied: false)
    }

    private func scheduleMixerReconcile(
        additionalTarget: AudioApp? = nil,
        requestAuthorizationIfDenied: Bool,
        equalizerParametersOnly: Bool = false,
        validatesRouting: Bool = false
    ) {
        guard !isOutputRouteTransitioning else {
            return
        }

        var apps = outputAppsState.snapshots
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
        let changesSnapshot = snapshot != lastSubmittedMixerSnapshot
        guard changesSnapshot || validatesRouting else {
            return
        }

        mixerCommandRevision &+= 1
        let command = AppMixerCommand(
            revision: mixerCommandRevision,
            routeGeneration: snapshot.routeGeneration,
            outputDeviceUID: snapshot.outputDeviceUID,
            targets: snapshot.targets,
            equalizerParametersOnly: equalizerParametersOnly
        )
        let requiresPermission = command.targets.contains {
            $0.requiresProcessing
        }
        lastSubmittedMixerSnapshot = snapshot
        if changesSnapshot {
            outputRoutingStore.isApplying = true
            outputRoutingStore.applyFailed = false
        }
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

                if result == .deferred {
                    outputRoutingStore.isApplying = false
                    retrySoonAfterDeferredRouteRecovery()
                    return
                }
                guard result != .superseded else { return }

                if result == .failed, !command.targets.contains(where: { $0.outputDeviceUIDs != nil }) {
                    lastSubmittedMixerSnapshot = nil
                }
                outputRoutingStore.isApplying = false
                outputRoutingStore.applyFailed = result == .failed
                if result == .failed, command.targets.contains(where: { $0.outputDeviceUIDs != nil }) {
                    // A format/device failure is not evidence of denied audio permission.
                    let permitted = await appAudioMixer.hasSystemAudioPermission()
                    guard mixerCommandRevision == command.revision else { return }
                    if !permitted {
                        updateSystemAudioPermissionAfterMixAttempt(false, requiresPermission: true,
                            requestAuthorizationIfDenied: requestAuthorizationIfDenied)
                    }
                    return
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
        var target = AppMixTarget(
            id: app.id,
            audioObjectIDs: app.audioObjectIDs,
            volume: app.isMuted ? 0 : min(maximumVolume(for: app.bundleID), app.volume)
        )
        target.outputDeviceUIDs = outputRoutingStore.resolvedUIDs(for: app.bundleID,
            availableDestinations: outputState.routingDestinations)
        if let selectedUIDs = target.outputDeviceUIDs {
            for device in outputState.routingDevices where selectedUIDs.contains(device.uid) {
                if let sourceIDs = device.selectedDataSourceIDs {
                    target.airPlayRoutes[device.uid] = AirPlayOutputRoute(deviceID: device.id, sourceIDs: sourceIDs)
                }
            }
        }
        if equalizerStore.isFeatureActive {
            let configuration = equalizerStore.configuration(for: app.bundleID)
            // Keep the tap/aggregate ready for apps whose EQ the user has set,
            // even at Flat (Off), so preset changes never rebuild HAL. Untouched
            // apps are not tapped; the mixer releases idle sound-neutral graphs.
            target.keepsEqualizerWarm = equalizerStore.configurations[app.bundleID] != nil
            target.equalizerGains = configuration.isEnabled
                ? configuration.normalizedGains
                : nil
            target.equalizerToneGains = configuration.isEnabled
                ? configuration.normalizedToneGains
                : nil
        }
        return target
    }

    private func updateSystemAudioPermissionAfterMixAttempt(
        _ isMixingAvailable: Bool,
        requiresPermission: Bool,
        requestAuthorizationIfDenied: Bool
    ) {
        guard !isMixingAvailable else {
            setNeedsSystemAudioPermission(false)
            return
        }

        if requiresPermission {
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
        appAudioMixer.submitEarlyRetirement(revision: commandRevision, outputDeviceUID: outputDeviceUID)

        if isOutputRouteTransitioning, outputRouteRefreshTask != nil {
            DiagnosticLog.shared.record("route", "output_route_probe_superseded", fields: [
                "replacementGeneration": String(routeGeneration)])
        }
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
                    stableReadCount = 0
                    hasObservedUID = false
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
                guard let runningApps = hardware.runningOutputApps(
                    storedVolume: { [weak self] bundleID in
                        self?.storedAppVolume(for: bundleID) ?? 1
                    },
                    storedMute: { [weak self] bundleID in
                        self?.storedAppMute(for: bundleID) ?? false
                    }
                ) else {
                    isOutputRouteTransitioning = false
                    appAudioMixer.cancelOutputSwitch(revision: commandRevision)
                    scheduleMixerReconcile(requestAuthorizationIfDenied: false)
                    return
                }
                detectedApps = runningApps
            }
            let apps = outputAppsExcludingBlacklistedApps(
                outputAppsPreservingRouteSnapshot(detectedApps)
            )

            pendingOutputApps = nil
            let command = AppMixerCommand(
                revision: commandRevision,
                routeGeneration: routeGeneration,
                outputDeviceUID: stableOutputDeviceUID,
                targets: apps.map(mixTarget).sorted { $0.id < $1.id }
            )
            let requiresPermission = command.targets.contains {
                $0.requiresProcessing
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

                    if result == .deferred {
                        outputRoutingStore.isApplying = false
                        retrySoonAfterDeferredRouteRecovery()
                        return
                    }
                    guard result != .superseded else { return }

                    if result == .failed, !command.targets.contains(where: { $0.outputDeviceUIDs != nil }) {
                        lastSubmittedMixerSnapshot = nil
                    }
                    outputRoutingStore.isApplying = false
                    outputRoutingStore.applyFailed = result == .failed
                    if result == .failed, command.targets.contains(where: { $0.outputDeviceUIDs != nil }) {
                        let permitted = await appAudioMixer.hasSystemAudioPermission()
                        guard mixerCommandRevision == commandRevision else { return }
                        updateSystemAudioPermissionAfterMixAttempt(permitted, requiresPermission: true,
                            requestAuthorizationIfDenied: false)
                        refreshOutputApps(stabilize: true)
                        return
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

    private func scheduleOutputVolumeUpdate(volume: Double? = nil, muted: Bool? = nil) {
        guard let device = currentOutputDevice, displayVolumeRouteUID != device.uid else { return }
        outputVolumeRevision &+= 1
        // A read notification must not replace a pending explicit slider/mute edit.
        if volume != nil || muted != nil || pendingOutputVolume == nil {
            let retainedVolume = pendingOutputVolume?.uid == device.uid ? pendingOutputVolume?.volume : nil
            pendingOutputVolume = (device.id, device.uid, volume ?? retainedVolume, muted)
        }
        guard outputVolumeTask == nil else { return }
        outputVolumeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                // Bound the write rate without delaying the visible slider value.
                do { try await Task.sleep(for: .milliseconds(16)) } catch { break }
                guard let request = pendingOutputVolume else { break }
                pendingOutputVolume = nil
                guard currentOutputDevice?.uid == request.uid,
                      currentOutputDevice?.id == request.deviceID else { continue }
                let revision = outputVolumeRevision
                DiagnosticCounters.shared.increment("volume_write")
                let snapshot = await outputVolumeController.update(
                    deviceID: request.deviceID, volume: request.volume, muted: request.muted
                )
                guard !Task.isCancelled else { break }
                guard currentOutputDevice?.uid == request.uid,
                      currentOutputDevice?.id == request.deviceID,
                      revision == outputVolumeRevision else { continue }
                if let snapshot {
                    setSystemOutputVolumeIfChanged(snapshot.volume)
                    setSystemOutputMutedIfChanged(snapshot.isMuted)
                    if let volume = snapshot.volume { setCurrentOutputDeviceVolume(volume) }
                    DiagnosticActions.shared.coalesce("audio", "system_volume_confirmed", target: request.uid,
                        value: "\(snapshot.volume.map { String(format: "%.4f", $0) } ?? "unknown");muted=\(snapshot.isMuted)")
                } else {
                    DiagnosticLog.shared.record("audio", "system_volume_readback_failed", level: "error")
                    refreshOutputState()
                }
            }
            outputVolumeTask = nil
        }
    }

    private func handleOutputVolumeChange() {
        // The final write's readback already covers notifications from our own edits.
        guard outputVolumeTask == nil else { return }
        guard !isMixerLifecycleBusy, !isOutputRouteTransitioning else {
            needsOutputHardwareRefresh = true
            return
        }
        scheduleOutputVolumeUpdate()
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
        inputDevicesDidChange?()
    }

    private func handleOutputAppsChange() {
        // A player starting or stopping output gets its graph checked about a
        // second later instead of waiting for the full validation interval.
        lastRoutingValidation = min(lastRoutingValidation, Date().addingTimeInterval(-1))
        guard !isMixerLifecycleBusy, !isOutputRouteTransitioning else {
            return
        }

        // HAL process callbacks represent a real add/start/stop event, so additions can
        // be published and mixed immediately instead of waiting for a second timer poll.
        refreshOutputApps(stabilize: false)
    }

    private func recoverFromOutputDeviceSelectionFailure(revision: UInt64) {
        DiagnosticLog.shared.record("route", "output_recovery_started", level: "error", fields: ["revision": String(revision)])
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

        recordDiagnosticDeviceChanges(from: outputState.devices, to: devices, direction: "output")
        outputState.devices = devices
        selectConnectedNearbyAccessoryIfNeeded(in: devices)
        refreshNearbyAccessories()
    }

    // MARK: Nearby Bluetooth headphones

    func connectNearbyAccessory(_ accessory: NearbyAudioAccessory) {
        guard outputState.connectingAccessoryAddress == nil else { return }
        DiagnosticLog.shared.record("route", "nearby_connect_requested", fields: [
            "device": DiagnosticLog.shared.anonymous(accessory.address),
            "availability": accessory.availability.diagnosticName])
        let address = NearbyAudioAccessoryMatcher.canonical(accessory.address)
        outputState.connectingAccessoryAddress = address
        bluetoothAccessoryConnector.connect(address: accessory.address) { [weak self] succeeded in
            guard let self, outputState.connectingAccessoryAddress == address else { return }
            guard succeeded else {
                DiagnosticLog.shared.record("route", "nearby_connect_failed", level: "error")
                finishNearbyConnection()
                return
            }
            // The link is up; wait for Core Audio to publish the output.
            refreshOutputState()
            nearbyConnectionTimeoutTask?.cancel()
            nearbyConnectionTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled, let self,
                      outputState.connectingAccessoryAddress == address else { return }
                DiagnosticLog.shared.record("route", "nearby_connect_timed_out", level: "error")
                finishNearbyConnection()
            }
        }
    }

    private func selectConnectedNearbyAccessoryIfNeeded(in devices: [AudioDevice]) {
        guard let address = outputState.connectingAccessoryAddress,
              let device = devices.first(where: { $0.bluetoothAddress == address }) else { return }
        finishNearbyConnection()
        selectOutputDevice(device)
    }

    private func finishNearbyConnection() {
        nearbyConnectionTimeoutTask?.cancel()
        nearbyConnectionTimeoutTask = nil
        outputState.connectingAccessoryAddress = nil
        refreshNearbyAccessories()
    }

    private func refreshNearbyAccessories() {
        let advertisements = nearbyAccessoryScanner.advertisements
        var accessories: [NearbyAudioAccessory] = []
        if !advertisements.isEmpty {
            let paired = PairedBluetoothAccessories.read()
            accessories = NearbyAudioAccessoryMatcher.nearbyAccessories(
                advertisements: advertisements,
                paired: paired.audio,
                pairedDevices: paired.all,
                localAddressSuffix: PairedBluetoothAccessories.localAddressSuffix,
                connectedOutputAddresses: Set(outputState.devices.compactMap(\.bluetoothAddress))
            )
        }
        if let connecting = outputState.connectingAccessoryAddress,
           !accessories.contains(where: { NearbyAudioAccessoryMatcher.canonical($0.address) == connecting }),
           let previous = outputState.nearbyAccessories.first(where: {
               NearbyAudioAccessoryMatcher.canonical($0.address) == connecting
           }) {
            // Keep the row (and its progress) while the link comes up.
            accessories.append(previous)
        }
        if outputState.nearbyAccessories != accessories {
            DiagnosticLog.shared.record("bluetooth", "nearby_accessories_changed", fields: [
                "advertised": String(advertisements.count),
                "shown": accessories.map { "\(DiagnosticLog.shared.anonymous($0.address))=\($0.availability.diagnosticName)" }
                    .joined(separator: ",")])
            outputState.nearbyAccessories = accessories
        }
        outputState.recordRowOrder()
    }

    private func setInputDevicesIfChanged(_ devices: [AudioDevice]) {
        guard inputState.devices != devices else {
            return
        }

        recordDiagnosticDeviceChanges(from: inputState.devices, to: devices, direction: "input")
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

    private func devicesWithCurrentVolume(_ volume: Double, in devices: [AudioDevice], deviceUID: String? = nil) -> [AudioDevice] {
        var updatedDevices = devices
        guard let index = devices.firstIndex(where: { device in
            if let deviceUID { return device.uid == deviceUID }
            return device.isCurrent
        }),
              let existingVolume = devices[index].volume,
              !nearlyEqual(existingVolume, volume) else {
            return devices
        }

        let device = devices[index]
        updatedDevices[index] = AudioDevice(
            id: device.id,
            uid: device.uid,
            name: device.name,
            manufacturer: device.manufacturer,
            modelUID: device.modelUID,
            iconName: device.iconName,
            systemIconURL: device.systemIconURL,
            systemIcon: device.systemIcon,
            transportType: device.transportType,
            isCurrent: device.isCurrent,
            volume: volume,
            dataSourceID: device.dataSourceID,
            selectedDataSourceIDs: device.selectedDataSourceIDs
        )

        return updatedDevices
    }

    private func setSystemOutputVolumeIfChanged(_ volume: Double?) {
        guard !optionalVolumesMatch(outputState.systemVolume, volume) else {
            return
        }

        outputState.systemVolume = volume
        recordPanelSceneState()
    }

    private func setSystemOutputMutedIfChanged(_ isMuted: Bool) {
        guard outputState.isSystemMuted != isMuted else {
            return
        }

        outputState.isSystemMuted = isMuted
        recordPanelSceneState()
    }

    private func setInputMutedIfChanged(_ isMuted: Bool) {
        guard inputState.isInputMuted != isMuted else {
            return
        }

        inputState.isInputMuted = isMuted
        recordPanelSceneState()
    }

    private func setInputVolumeIfChanged(_ volume: Double?) {
        guard !optionalVolumesMatch(inputState.inputVolume, volume) else {
            return
        }

        inputState.inputVolume = volume
        recordPanelSceneState()
    }

    private func setNeedsSystemAudioPermission(_ isNeeded: Bool) {
        if outputAppsState.needsSystemAudioPermission != isNeeded {
            DiagnosticLog.shared.record("permission", "audio_authorization_requirement", fields: ["needed": String(isNeeded)])
            outputAppsState.needsSystemAudioPermission = isNeeded
        }

        // Routing validation lands here every 2 s; an unchanged write still posts
        // UserDefaults.didChangeNotification, which rebuilds the App scene.
        if defaults.object(forKey: systemAudioPermissionNeedsAuthorizationKey) as? Bool != isNeeded {
            defaults.set(isNeeded, forKey: systemAudioPermissionNeedsAuthorizationKey)
        }
    }

    private func handleSystemAudioPermissionRequest(_ permissionAvailable: Bool) {
        if permissionAvailable {
            setNeedsSystemAudioPermission(false)
            reconcileOutputApps()
        } else {
            setNeedsSystemAudioPermission(true)
        }
    }

    private func restoreCachedSystemAudioPermissionRequirementState() {
        if defaults.object(forKey: systemAudioPermissionNeedsAuthorizationKey) != nil {
            outputAppsState.needsSystemAudioPermission = defaults.bool(forKey: systemAudioPermissionNeedsAuthorizationKey)
        }
    }

    private var activeOutputMixRequiresSystemAudioPermission: Bool {
        outputAppsState.apps.contains {
            mixTarget($0.snapshot).requiresProcessing
        }
    }

    private func beginOutputAppRouteRecovery() {
        retainedOutputAppsDuringRoute = mergeOutputApps(
            retaining: retainedOutputAppsDuringRoute,
            updatingWith: outputAppsState.snapshots
        )
        outputAppRouteRecoveryDeadline = Date().addingTimeInterval(
            outputAppRouteRecoveryDuration
        )
    }

    // The mixer rebuilds on a new output only after it has stayed stable for a
    // moment, so the first attempt after a switch is usually deferred. Retry as
    // soon as that settles instead of waiting for the next routing validation,
    // which left mixes and EQ off for up to two seconds after headphones returned.
    private func retrySoonAfterDeferredRouteRecovery() {
        guard let outputAppRouteRecoveryDeadline, Date() < outputAppRouteRecoveryDeadline else { return }
        lastRoutingValidation = min(
            lastRoutingValidation,
            Date().addingTimeInterval(deferredRouteRetryDelay - routingValidationInterval)
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

    private func outputAppsExcludingBlacklistedApps(_ apps: [AudioApp]) -> [AudioApp] {
        if audioAppBlacklistState.updateMetadata(from: apps) {
            persistAudioAppBlacklist()
        }

        return apps.filter {
            !audioAppBlacklistState.contains(appID: $0.id)
        }
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

    private func persistAudioAppBlacklist() {
        let persistedApps = audioAppBlacklistState.apps.map { app in
            PersistedAudioAppBlacklistEntry(
                id: app.id,
                bundleID: app.bundleID,
                name: app.name
            )
        }
        guard let data = try? JSONEncoder().encode(persistedApps) else {
            return
        }

        defaults.set(data, forKey: Self.audioAppBlacklistKey)
    }

    private static func restoredAudioAppBlacklistEntries() -> [AudioAppBlacklistEntry] {
        guard let data = UserDefaults.standard.data(forKey: audioAppBlacklistKey),
              let persistedApps = try? JSONDecoder().decode(
                  [PersistedAudioAppBlacklistEntry].self,
                  from: data
              ) else {
            return []
        }

        return persistedApps.map { app in
            let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: app.bundleID
            )
            let icon = applicationURL.map {
                NSWorkspace.shared.icon(forFile: $0.path)
            }
            return AudioAppBlacklistEntry(
                id: app.id,
                bundleID: app.bundleID,
                name: app.name,
                icon: icon
            )
        }
    }

    private func nearlyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        AudioVolumeValue.matches(lhs, rhs)
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

        return max(0, min(maximumVolume(for: bundleID), defaults.double(forKey: key)))
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
        if equalizerStore.isFeatureActive { return 1 }
        return defaults.bool(forKey: MixVolumePreference.enables200PercentVolume) ? 2 : 1
    }

}



extension AudioModel {
    func diagnosticSnapshot() -> [String: String] {
        var state = ["outputDeviceCount": String(outputState.devices.count),
            "inputDeviceCount": String(inputState.devices.count),
            "audioAppCount": String(outputAppsState.apps.count),
            "systemMuted": String(outputState.isSystemMuted),
            "permissionRequired": String(outputAppsState.needsSystemAudioPermission),
            "mixerLifecycleBusy": String(isMixerLifecycleBusy),
            "routeTransitioning": String(isOutputRouteTransitioning),
            "routeGeneration": String(outputRouteGeneration),
            "mixerRevision": String(mixerCommandRevision),
            "sceneApplying": String(isApplyingScene),
            "activeScene": activeSceneID.map { DiagnosticLog.shared.anonymous($0.uuidString) } ?? "off"]
        state["systemVolume"] = outputState.systemVolume.map { String(format: "%.4f", $0) } ?? "unknown"
        state["outputDevice"] = currentOutputDevice.map { DiagnosticLog.shared.anonymous($0.selectionID) } ?? "none"
        state["inputDevice"] = currentInputDevice.map { DiagnosticLog.shared.anonymous($0.uid) } ?? "none"
        state["audioInterfaceVisible"] = String(audioInterfaceIsVisible)
        state["systemVolumeControl"] = displayVolumeRouteUID != nil ? "ddc" : currentOutputDevice?.volume != nil ? "core_audio" : "unavailable"
        return state
    }

    func diagnosticConfiguration() -> DiagnosticAudioConfiguration {
        let log = DiagnosticLog.shared
        var result = DiagnosticAudioConfiguration(summary: diagnosticSnapshot())
        for (direction, devices) in [("output", outputState.devices), ("input", inputState.devices)] {
            result.devices += devices.map {
                DiagnosticConfiguredDevice(id: log.anonymous($0.uid), selection: log.anonymous($0.selectionID),
                    direction: direction, current: $0.isCurrent, transport: $0.transportType, volume: $0.volume,
                    selectedSourceCount: $0.selectedDataSourceIDs?.count)
            }
        }
        result.apps = outputAppsState.apps.map { app in
            let target = mixTarget(app.snapshot)
            var entry = DiagnosticConfiguredApp(id: log.anonymous(app.bundleID), instance: log.anonymous(app.id),
                volume: app.volume, muted: app.isMuted, appliedGain: target.volume,
                maximumVolume: maximumVolume(for: app.bundleID))
            let eq = equalizerStore.configuration(for: app.bundleID)
            entry.equalizerEnabled = eq.isEnabled
            entry.equalizerAvailable = equalizerStore.isFeatureActive
            entry.equalizerApplied = target.equalizerGains != nil
            entry.equalizerGains = eq.normalizedGains
            entry.equalizerToneGains = eq.normalizedToneGains
            entry.usesSimpleEqualizerControls = eq.usesSimpleControls
            entry.routingAvailable = outputRoutingStore.isFeatureActive
            let selected = outputRoutingStore.destinations(for: app.bundleID)
            entry.hasSavedOutputSelection = !selected.isEmpty
            entry.followsSystemOutput = target.outputDeviceUIDs == nil
            entry.selectedDestinations = selected.map { destination in
                DiagnosticConfiguredDestination(device: log.anonymous(destination.uid), selection: log.anonymous(destination.id),
                    available: outputState.routingDestinations.contains { destination.matches($0) },
                    selectedSourceCount: destination.dataSourceIDs?.count)
            }
            entry.resolvedDestinationDevices = target.outputDeviceUIDs.map { $0.map(log.anonymous) }
            return entry
        }
        return result
    }

    func diagnosticIdentificationCandidates() -> [DiagnosticIdentificationCandidate] {
        diagnosticAffectedItems().map(\.candidate)
    }

    /// Same devices and apps as the panel, with the panel's icons, read live.
    func diagnosticAffectedItems() -> [FeedbackAffectedItem] {
        let log = DiagnosticLog.shared
        var seen = Set<String>()
        let catalog = AudioDeviceCatalog.shared
        let devices = (outputState.devices + inputState.devices).filter { seen.insert($0.uid).inserted }
        return devices.map { device in
            let known = catalog.diagnosticModel(forModelUID: device.modelUID)
            return FeedbackAffectedItem(candidate: DiagnosticIdentificationCandidate(id: log.anonymous(device.uid),
                kind: "device", displayName: device.name,
                manufacturer: known?.manufacturer ?? device.manufacturer, model: known?.model),
                icon: .device(symbolName: device.iconName, systemIcon: device.systemIcon, isCurrent: device.isCurrent))
        } + outputAppsState.apps.map {
            FeedbackAffectedItem(candidate: DiagnosticIdentificationCandidate(id: log.anonymous($0.bundleID),
                kind: "application", displayName: $0.name, bundleIdentifier: $0.bundleID),
                icon: .application(image: $0.icon, isMuted: $0.isMuted))
        }
    }

    private func recordDiagnosticDeviceChanges(from old: [AudioDevice], to new: [AudioDevice], direction: String) {
        let oldByUID = Dictionary(old.map { ($0.uid, $0) }, uniquingKeysWith: { first, _ in first })
        let newUIDs = Set(new.map(\.uid))
        for device in old where !newUIDs.contains(device.uid) {
            DiagnosticLog.shared.record("device", "disconnected", fields: [
                "direction": direction, "device": DiagnosticLog.shared.anonymous(device.uid)])
        }
        for device in new {
            let previous = oldByUID[device.uid]
            guard previous == nil || previous?.isCurrent != device.isCurrent
                || previous?.transportType != device.transportType
                || previous?.selectedDataSourceIDs != device.selectedDataSourceIDs else { continue }
            DiagnosticLog.shared.record("device", previous == nil ? "connected" : "route_state_changed", fields: [
                "direction": direction, "device": DiagnosticLog.shared.anonymous(device.uid),
                "current": String(device.isCurrent), "transport": device.transportType.map(String.init) ?? "unknown",
                "volumeSupported": String(device.volume != nil),
                "selectedSourceCount": device.selectedDataSourceIDs.map { String($0.count) } ?? "not_applicable"])
        }
    }
}
