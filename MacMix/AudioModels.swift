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
    let iconName: String
    let transportType: UInt32?
    let isCurrent: Bool
    let volume: Double?
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
        if abs(self.volume - volume) >= 0.001 {
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
