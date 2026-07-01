//
//  AudioModels.swift
//  MacMix
//
//  Created by Jazmin on 2026/6/29.
//

import AppKit
import CoreAudio
import Foundation

enum MixVolumePreference {
    static let enables200PercentVolume = "MacMix.Enables200PercentVolume"
}

enum AudioDeviceDirection {
    case input
    case output

    var scope: AudioObjectPropertyScope {
        switch self {
        case .input:
            return kAudioDevicePropertyScopeInput
        case .output:
            return kAudioDevicePropertyScopeOutput
        }
    }

    var defaultDeviceSelector: AudioObjectPropertySelector {
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
}

struct NowPlayingItem {
    var title: String
    var subtitle: String
    var elapsedText: String
    var remainingText: String
    var progress: Double
    var artwork: NSImage?
}
