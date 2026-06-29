//
//  AppAudioMixer.swift
//  MacMix
//
//  Created by Jazmin on 2026/6/29.
//

import Accelerate
import AudioToolbox
import CoreAudio
import Foundation

nonisolated final class AppAudioMixer {
    static let shared = AppAudioMixer()

    static var isSupported: Bool {
        if #available(macOS 14.4, *) {
            return true
        }

        return false
    }

    private var engines: [String: any AppGainEngine] = [:]
    private var requestedPermissionThisLaunch = false
    private var lastPermissionRequestSucceeded: Bool?

    private init() {}

    func requestSystemAudioPermissionIfNeeded() -> Bool {
        if requestedPermissionThisLaunch {
            return lastPermissionRequestSucceeded ?? false
        }

        return requestSystemAudioPermission()
    }

    func requestSystemAudioPermission() -> Bool {
        requestedPermissionThisLaunch = true

        guard #available(macOS 14.4, *) else {
            lastPermissionRequestSucceeded = false
            return false
        }

        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDescription.name = "MacMix Permission Request"
        tapDescription.muteBehavior = .unmuted
        tapDescription.isPrivate = true

        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(tapDescription, &tapID)

        guard status == noErr, tapID != kAudioObjectUnknown else {
            lastPermissionRequestSucceeded = false
            return false
        }

        AudioHardwareDestroyProcessTap(tapID)
        lastPermissionRequestSucceeded = true
        return true
    }

    func apply(_ volume: Double, to app: AudioApp, outputDeviceUID: String?) -> Bool {
        let clampedVolume = Float(max(0, min(1, volume)))

        guard !isUnity(Double(clampedVolume)), let outputDeviceUID else {
            engines.removeValue(forKey: app.id)?.stop()
            return true
        }

        guard Self.isSupported else {
            return false
        }

        if let engine = engines[app.id] {
            if engine.tappedObjects == app.audioObjectIDs,
               engine.outputDeviceUID == outputDeviceUID {
                engine.gain = clampedVolume
                return true
            }

            engine.stop()
            engines.removeValue(forKey: app.id)
        }

        guard #available(macOS 14.4, *),
              let engine = ProcessTapGainEngine(
                audioObjectIDs: app.audioObjectIDs,
                gain: clampedVolume,
                outputDeviceUID: outputDeviceUID
              ) else {
            return false
        }

        engines[app.id] = engine
        return true
    }

    func reconcile(apps: [AudioApp], outputDeviceUID: String?) -> Bool {
        let currentIDs = Set(apps.map(\.id))
        var success = true

        for (appID, engine) in Array(engines) where !currentIDs.contains(appID) {
            engine.stop()
            engines.removeValue(forKey: appID)
        }

        for app in apps {
            if !apply(app.volume, to: app, outputDeviceUID: outputDeviceUID) {
                success = false
            }
        }

        return success
    }

    func stopAll() {
        for engine in engines.values {
            engine.stop()
        }

        engines.removeAll()
    }

    private func isUnity(_ volume: Double) -> Bool {
        abs(volume - 1) < 0.005
    }
}

private protocol AppGainEngine: AnyObject {
    nonisolated var gain: Float { get set }
    nonisolated var tappedObjects: [AudioObjectID] { get }
    nonisolated var outputDeviceUID: String { get }

    nonisolated func stop()
}

@available(macOS 14.4, *)
nonisolated private final class ProcessTapGainEngine: AppGainEngine {
    nonisolated let tappedObjects: [AudioObjectID]
    nonisolated let outputDeviceUID: String

    nonisolated var gain: Float {
        get { gainPointer.pointee }
        set { gainPointer.pointee = max(0, min(1, newValue)) }
    }

    private let gainPointer: UnsafeMutablePointer<Float>
    private var destroyedGainPointer = false
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?

    init?(audioObjectIDs: [AudioObjectID], gain: Float, outputDeviceUID: String) {
        guard !audioObjectIDs.isEmpty else {
            return nil
        }

        self.tappedObjects = audioObjectIDs
        self.outputDeviceUID = outputDeviceUID
        self.gainPointer = UnsafeMutablePointer<Float>.allocate(capacity: 1)
        self.gainPointer.initialize(to: max(0, min(1, gain)))

        let tapDescription = CATapDescription(stereoMixdownOfProcesses: audioObjectIDs)
        tapDescription.muteBehavior = .mutedWhenTapped
        tapDescription.isPrivate = true

        guard AudioHardwareCreateProcessTap(tapDescription, &tapID) == noErr,
              tapID != kAudioObjectUnknown else {
            destroyGainPointer()
            return nil
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MacMix Mixer",
            kAudioAggregateDeviceUIDKey: "MacMix.Mixer.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputDeviceUID],
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ],
            ],
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]

        guard AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID) == noErr,
              aggregateID != kAudioObjectUnknown else {
            AudioHardwareDestroyProcessTap(tapID)
            destroyGainPointer()
            return nil
        }

        let gainPointer = gainPointer
        let status = AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateID, nil) { _, inputData, _, outputData, _ in
            let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            let outputBuffers = UnsafeMutableAudioBufferListPointer(outputData)
            var gain = gainPointer.pointee
            let isBoosting = gain > 1
            var low: Float = -1
            var high: Float = 1

            for (index, inputBuffer) in inputBuffers.enumerated() where index < outputBuffers.count {
                guard let source = inputBuffer.mData?.assumingMemoryBound(to: Float.self),
                      let destination = outputBuffers[index].mData?.assumingMemoryBound(to: Float.self) else {
                    continue
                }

                let sampleCount = min(Int(inputBuffer.mDataByteSize), Int(outputBuffers[index].mDataByteSize))
                    / MemoryLayout<Float>.size
                vDSP_vsmul(source, 1, &gain, destination, 1, vDSP_Length(sampleCount))

                if isBoosting {
                    vDSP_vclip(destination, 1, &low, &high, destination, 1, vDSP_Length(sampleCount))
                }
            }
        }

        guard status == noErr, let ioProc else {
            stop()
            return nil
        }

        guard AudioDeviceStart(aggregateID, ioProc) == noErr else {
            stop()
            return nil
        }
    }

    nonisolated func stop() {
        if let ioProc {
            AudioDeviceStop(aggregateID, ioProc)
            AudioDeviceDestroyIOProcID(aggregateID, ioProc)
            self.ioProc = nil
        }

        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = kAudioObjectUnknown
        }

        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }

    deinit {
        stop()
        destroyGainPointer()
    }

    private func destroyGainPointer() {
        guard !destroyedGainPointer else {
            return
        }

        gainPointer.deinitialize(count: 1)
        gainPointer.deallocate()
        destroyedGainPointer = true
    }

}
