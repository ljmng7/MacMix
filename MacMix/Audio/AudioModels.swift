//
//  AudioModels.swift
//  MacMix
//
//  Created by Jazmin on 2026/6/29.
//

import AppKit
import CoreAudio
import Foundation
import Observation

enum MixVolumePreference {
    static let enables200PercentVolume = "MacMix.Enables200PercentVolume"
}

// Zero is a semantic boundary: never discard entry to or exit from silence.
nonisolated enum AudioVolumeValue {
    static func matches(_ lhs: Double, _ rhs: Double) -> Bool {
        if lhs == 0 || rhs == 0 { return lhs == rhs }
        return abs(lhs - rhs) < 0.001
    }
}

enum AudioDeviceDirection {
    case input
    case output

    nonisolated var scope: AudioObjectPropertyScope {
        switch self {
        case .input:
            return kAudioDevicePropertyScopeInput
        case .output:
            return kAudioDevicePropertyScopeOutput
        }
    }

    nonisolated var defaultDeviceSelector: AudioObjectPropertySelector {
        switch self {
        case .input:
            return kAudioHardwarePropertyDefaultInputDevice
        case .output:
            return kAudioHardwarePropertyDefaultOutputDevice
        }
    }
}

struct AudioDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let manufacturer: String?
    let modelUID: String?
    let iconName: String
    let systemIconURL: URL?
    let systemIcon: NSImage?
    let transportType: UInt32?
    let isCurrent: Bool
    var volume: Double?

    // Keep uid as the HAL identity used by the mixer and saved routes.
    var dataSourceID: UInt32? = nil
    // The complete connected selection, including an AirPlay receiver group.
    // nil is a regular HAL output; [] is an unreadable/unconnected AirPlay route.
    var selectedDataSourceIDs: [UInt32]? = nil

    var selectionID: String {
        guard let dataSourceID else { return uid }
        return "\(uid)#airplay-source:\(dataSourceID)"
    }

    static func == (lhs: AudioDevice, rhs: AudioDevice) -> Bool {
        lhs.id == rhs.id
            && lhs.uid == rhs.uid
            && lhs.name == rhs.name
            && lhs.manufacturer == rhs.manufacturer
            && lhs.modelUID == rhs.modelUID
            && lhs.iconName == rhs.iconName
            && lhs.systemIconURL == rhs.systemIconURL
            && lhs.transportType == rhs.transportType
            && lhs.isCurrent == rhs.isCurrent
            && lhs.volume == rhs.volume
            && lhs.dataSourceID == rhs.dataSourceID
            && lhs.selectedDataSourceIDs == rhs.selectedDataSourceIDs
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(uid)
        hasher.combine(name)
        hasher.combine(manufacturer)
        hasher.combine(modelUID)
        hasher.combine(iconName)
        hasher.combine(systemIconURL)
        hasher.combine(transportType)
        hasher.combine(isCurrent)
        hasher.combine(volume)
        hasher.combine(dataSourceID)
        hasher.combine(selectedDataSourceIDs)
    }

}

struct AudioApp: Identifiable {
    let id: String
    let pid: pid_t
    let bundleID: String
    let name: String
    let audioObjectIDs: [AudioObjectID]
    let icon: NSImage?
    var volume: Double
    var isMuted: Bool
}

struct AudioAppBlacklistEntry: Identifiable, Equatable {
    let id: String
    let bundleID: String
    let name: String
    let icon: NSImage?

    static func == (lhs: AudioAppBlacklistEntry, rhs: AudioAppBlacklistEntry) -> Bool {
        lhs.id == rhs.id
            && lhs.bundleID == rhs.bundleID
            && lhs.name == rhs.name
            && (lhs.icon == nil) == (rhs.icon == nil)
    }
}

@MainActor
@Observable
final class AudioAppState: Identifiable {
    let id: String
    let pid: pid_t
    let bundleID: String
    let name: String
    let audioObjectIDs: [AudioObjectID]
    let icon: NSImage?
    var volume: Double
    var isMuted: Bool

    init(app: AudioApp) {
        id = app.id
        pid = app.pid
        bundleID = app.bundleID
        name = app.name
        audioObjectIDs = app.audioObjectIDs
        icon = app.icon
        volume = app.volume
        isMuted = app.isMuted
    }

    var snapshot: AudioApp {
        AudioApp(
            id: id,
            pid: pid,
            bundleID: bundleID,
            name: name,
            audioObjectIDs: audioObjectIDs,
            icon: icon,
            volume: volume,
            isMuted: isMuted
        )
    }

    func hasSameStructure(as app: AudioApp) -> Bool {
        id == app.id
            && pid == app.pid
            && bundleID == app.bundleID
            && name == app.name
            && audioObjectIDs == app.audioObjectIDs
            && (icon == nil) == (app.icon == nil)
    }

    func updateControls(volume: Double, isMuted: Bool) {
        if !AudioVolumeValue.matches(self.volume, volume) {
            self.volume = volume
        }

        if self.isMuted != isMuted {
            self.isMuted = isMuted
        }
    }
}

struct NowPlayingItem {
    var title: String
    var subtitle: String
    var elapsedText: String
    var remainingText: String
    var progress: Double
    var artwork: NSImage?
}

