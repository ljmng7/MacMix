//
//  AudioAccessoryControl.swift
//  MacMix
//
//  Undocumented Core Audio properties exposed by BTAudioHALPlugin.
//  Every property is feature-detected at runtime because these selectors are
//  private implementation details and may change between macOS releases.
//

import CoreAudio
import Foundation

enum ListeningMode: UInt32, CaseIterable, Identifiable, Sendable {
    case noiseCancellation = 2
    case transparency = 3
    case adaptive = 4

    var id: UInt32 { rawValue }

    fileprivate var supportBit: UInt32 {
        1 << (rawValue - Self.noiseCancellation.rawValue)
    }
}

enum SpatialAudioMode: UInt8, CaseIterable, Identifiable, Sendable {
    case off
    case fixed
    case headTracked

    var id: UInt8 { rawValue }
}

enum SpatialAudioContentKind: Equatable, Sendable {
    case spatialAudio
    case spatializeStereo
}

struct AudioAccessoryControlState: Equatable, Sendable {
    let supportedListeningModes: [ListeningMode]
    let listeningMode: ListeningMode?
    let supportsSpatialAudio: Bool
    let spatialAudioContentKind: SpatialAudioContentKind
    let spatialAudioMode: SpatialAudioMode?
    let canSetSpatialAudio: Bool

    var hasControls: Bool {
        !supportedListeningModes.isEmpty || supportsSpatialAudio
    }

    func overridingSpatialAudioMode(_ mode: SpatialAudioMode) -> Self {
        Self(
            supportedListeningModes: supportedListeningModes,
            listeningMode: listeningMode,
            supportsSpatialAudio: supportsSpatialAudio,
            spatialAudioContentKind: spatialAudioContentKind,
            spatialAudioMode: mode,
            canSetSpatialAudio: canSetSpatialAudio
        )
    }
}

struct AudioAccessoryController {
    private enum Property {
        static let listeningMode = fourCC("lstm")
        static let listeningModeSupport = fourCC("lsms")
        static let spatialAudioSupported = fourCC("spap")
        static let spatialAudioEnabled = fourCC("spen")
        static let headTrackingAvailable = fourCC("htav")
        static let headTrackingStatus = fourCC("htst")
        static let spatialControlCenterState = fourCC("spcs")
        static let spatializeStereoControlCenterState = fourCC("spss")
        static let spatialControlCenterAvailable = fourCC("iaap")
        static let spatializeStereoControlCenterAvailable = fourCC("spsv")
        static let isAudioSessionSpatial = fourCC("iass")
    }

    private struct SpatialRequest {
        var processID: Int32
        var headTracking: UInt8
        var enabled: UInt8
        var reserved0: UInt8 = 0
        var reserved1: UInt8 = 0
    }

    func state(
        for deviceID: AudioObjectID,
        activeProcessIDs: [pid_t]
    ) -> AudioAccessoryControlState? {
        let supportedListeningModes = listeningModesSupported(by: deviceID)
        let currentListeningMode = readUInt32(
            from: deviceID,
            selector: Property.listeningMode
        ).flatMap(ListeningMode.init(rawValue:))

        let reportsSpatialSupport = isEnabled(
            on: deviceID,
            selector: Property.spatialAudioSupported
        )
        let supportsSpatialAudio = reportsSpatialSupport
            && hasSettableSpatialProperty(on: deviceID)
        let spatialAudioContentKind = spatialAudioContentKind(for: deviceID)
        let currentSpatialMode = supportsSpatialAudio
            ? spatialAudioMode(for: deviceID)
            : nil

        let state = AudioAccessoryControlState(
            supportedListeningModes: supportedListeningModes,
            listeningMode: currentListeningMode,
            supportsSpatialAudio: supportsSpatialAudio,
            spatialAudioContentKind: spatialAudioContentKind,
            spatialAudioMode: currentSpatialMode,
            canSetSpatialAudio: supportsSpatialAudio && !activeProcessIDs.isEmpty
        )
        return state.hasControls ? state : nil
    }

    @discardableResult
    func setListeningMode(
        _ mode: ListeningMode,
        for deviceID: AudioObjectID
    ) -> Bool {
        guard listeningModesSupported(by: deviceID).contains(mode) else {
            return false
        }

        var value = mode.rawValue
        let didSet = withUnsafePointer(to: &value) { pointer in
            setPropertyData(
                pointer,
                size: UInt32(MemoryLayout<UInt32>.size),
                on: deviceID,
                selector: Property.listeningMode
            )
        }
        return didSet
            && readUInt32(from: deviceID, selector: Property.listeningMode) == value
    }

    @discardableResult
    func setSpatialAudioMode(
        _ mode: SpatialAudioMode,
        for deviceID: AudioObjectID,
        processIDs: [pid_t]
    ) -> Bool {
        guard !processIDs.isEmpty,
              isEnabled(on: deviceID, selector: Property.spatialAudioSupported) else {
            return false
        }

        let selector = spatialSelector(
            for: spatialAudioContentKind(for: deviceID)
        )
        guard isSettable(on: deviceID, selector: selector) else {
            return false
        }

        let enabled = mode != .off
        let headTracking = mode == .headTracked
        var wroteAtLeastOneProcess = false

        for processID in Set(processIDs) {
            guard processID > 0, processID <= pid_t(Int32.max) else {
                continue
            }

            var request = SpatialRequest(
                processID: Int32(processID),
                headTracking: headTracking ? 1 : 0,
                enabled: enabled ? 1 : 0
            )
            let didWrite = withUnsafePointer(to: &request) { pointer in
                setPropertyData(
                    pointer,
                    size: UInt32(MemoryLayout<SpatialRequest>.size),
                    on: deviceID,
                    selector: selector
                )
            }
            wroteAtLeastOneProcess = wroteAtLeastOneProcess || didWrite
        }

        return wroteAtLeastOneProcess
    }

    private func listeningModesSupported(by deviceID: AudioObjectID) -> [ListeningMode] {
        guard isSettable(on: deviceID, selector: Property.listeningMode) else {
            return []
        }

        guard let mask = readUInt32(
            from: deviceID,
            selector: Property.listeningModeSupport
        ) else {
            return []
        }

        return ListeningMode.allCases.filter { mask & $0.supportBit != 0 }
    }

    private func hasSettableSpatialProperty(on deviceID: AudioObjectID) -> Bool {
        isSettable(on: deviceID, selector: Property.spatializeStereoControlCenterState)
            || isSettable(on: deviceID, selector: Property.spatialControlCenterState)
    }

    private func spatialAudioMode(for deviceID: AudioObjectID) -> SpatialAudioMode? {
        let controlCenterStates = [
            readUInt32(from: deviceID, selector: Property.spatialControlCenterState),
            readUInt32(
                from: deviceID,
                selector: Property.spatializeStereoControlCenterState
            ),
        ].compactMap { $0 }

        // These properties store the mode selected in Control Center. `spen`
        // describes the renderer's effective state and can become zero while a
        // Fixed selection is still active, so use it only when neither Control
        // Center property is exposed by the current route.
        let isSpatialAudioEnabled: Bool
        if !controlCenterStates.isEmpty {
            isSpatialAudioEnabled = controlCenterStates.contains { $0 != 0 }
        } else if let enabledValue = readUInt32(
            from: deviceID,
            selector: Property.spatialAudioEnabled
        ) {
            isSpatialAudioEnabled = enabledValue != 0
        } else {
            return nil
        }

        guard isSpatialAudioEnabled else {
            return .off
        }

        let hasHeadTracking = isEnabled(
            on: deviceID,
            selector: Property.headTrackingAvailable
        )
        let isHeadTracking = isEnabled(
            on: deviceID,
            selector: Property.headTrackingStatus
        )
        return hasHeadTracking && isHeadTracking ? .headTracked : .fixed
    }

    private func spatialAudioContentKind(
        for deviceID: AudioObjectID
    ) -> SpatialAudioContentKind {
        let spatialState = readUInt32(
            from: deviceID,
            selector: Property.spatialControlCenterState
        )
        let stereoState = readUInt32(
            from: deviceID,
            selector: Property.spatializeStereoControlCenterState
        )

        // Keep writing to the Control Center channel that is actually active.
        // `iass` can report a spatial session while BTAudioHALPlugin is exposing
        // the current user mode through `spss`; choosing `spcs` in that state
        // turns a Head Tracked -> Fixed request into an effective Off request.
        if spatialState.map({ $0 != 0 }) == true,
           stereoState.map({ $0 != 0 }) != true {
            return .spatialAudio
        }
        if stereoState.map({ $0 != 0 }) == true,
           spatialState.map({ $0 != 0 }) != true {
            return .spatializeStereo
        }

        let spatialControlIsAvailable = isEnabled(
            on: deviceID,
            selector: Property.spatialControlCenterAvailable
        )
        let stereoControlIsAvailable = isEnabled(
            on: deviceID,
            selector: Property.spatializeStereoControlCenterAvailable
        )
        if spatialControlIsAvailable != stereoControlIsAvailable {
            return spatialControlIsAvailable ? .spatialAudio : .spatializeStereo
        }

        if isEnabled(on: deviceID, selector: Property.isAudioSessionSpatial),
           isSettable(on: deviceID, selector: Property.spatialControlCenterState) {
            return .spatialAudio
        }

        return .spatializeStereo
    }

    private func spatialSelector(
        for contentKind: SpatialAudioContentKind
    ) -> AudioObjectPropertySelector {
        if contentKind == .spatialAudio {
            return Property.spatialControlCenterState
        }

        return Property.spatializeStereoControlCenterState
    }

    private func readUInt32(
        from objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> UInt32? {
        var address = propertyAddress(selector)
        guard AudioObjectHasProperty(objectID, &address) else {
            return nil
        }

        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &size,
            &value
        )
        return status == noErr && size == MemoryLayout<UInt32>.size ? value : nil
    }

    private func isSettable(
        on objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> Bool {
        var address = propertyAddress(selector)
        guard AudioObjectHasProperty(objectID, &address) else {
            return false
        }

        var isSettable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(objectID, &address, &isSettable) == noErr
            && isSettable.boolValue
    }

    private func isEnabled(
        on objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> Bool {
        readUInt32(from: objectID, selector: selector).map { $0 != 0 } ?? false
    }

    private func setPropertyData(
        _ value: UnsafeRawPointer,
        size: UInt32,
        on objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> Bool {
        guard isSettable(on: objectID, selector: selector) else {
            return false
        }

        var address = propertyAddress(selector)
        return AudioObjectSetPropertyData(
            objectID,
            &address,
            0,
            nil,
            size,
            value
        ) == noErr
    }

    private func propertyAddress(
        _ selector: AudioObjectPropertySelector
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func fourCC(_ value: StaticString) -> UInt32 {
        precondition(value.utf8CodeUnitCount == 4)
        return value.withUTF8Buffer { bytes in
            bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        }
    }
}
