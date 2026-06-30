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

    private init() {}

    func hasSystemAudioPermission() -> Bool {
        probeSystemAudioPermission()
    }

    func requestSystemAudioPermissionIfNeeded() -> Bool {
        probeSystemAudioPermission()
    }

    func requestSystemAudioPermission() -> Bool {
        probeSystemAudioPermission()
    }

    private func probeSystemAudioPermission() -> Bool {
        guard #available(macOS 14.4, *) else {
            return false
        }

        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDescription.name = "MacMix Permission Request"
        tapDescription.muteBehavior = .unmuted
        tapDescription.isPrivate = true

        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(tapDescription, &tapID)

        guard status == noErr, tapID != kAudioObjectUnknown else {
            return false
        }

        AudioHardwareDestroyProcessTap(tapID)
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
                guard canCreateProcessTap(
                    audioObjectIDs: app.audioObjectIDs,
                    outputDeviceUID: outputDeviceUID
                ) else {
                    engine.stop()
                    engines.removeValue(forKey: app.id)
                    return false
                }

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

    private func canCreateProcessTap(audioObjectIDs: [AudioObjectID], outputDeviceUID: String) -> Bool {
        guard #available(macOS 14.4, *),
              !audioObjectIDs.isEmpty else {
            return false
        }

        let candidates = [
            Self.configurePermissionCheckTap(
                CATapDescription(stereoMixdownOfProcesses: audioObjectIDs),
                name: "MacMix Permission Recheck"
            ),
            Self.configurePermissionCheckTap(
                CATapDescription(processes: audioObjectIDs, deviceUID: outputDeviceUID, stream: 0),
                name: "MacMix Permission Recheck Output"
            ),
        ]

        for tapDescription in candidates {
            var tapID = AudioObjectID(kAudioObjectUnknown)

            if AudioHardwareCreateProcessTap(tapDescription, &tapID) == noErr,
               tapID != kAudioObjectUnknown {
                AudioHardwareDestroyProcessTap(tapID)
                return true
            }
        }

        return false
    }

    @available(macOS 14.4, *)
    @discardableResult
    private static func configurePermissionCheckTap(
        _ tapDescription: CATapDescription,
        name: String
    ) -> CATapDescription {
        tapDescription.name = name
        tapDescription.muteBehavior = .unmuted
        tapDescription.isPrivate = true
        return tapDescription
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

        guard let tapDescription = Self.createProcessTap(
            audioObjectIDs: audioObjectIDs,
            outputDeviceUID: outputDeviceUID,
            tapID: &tapID
        ) else {
            destroyGainPointer()
            return nil
        }

        guard let tapFormat = Self.tapFormat(for: tapID) else {
            AudioHardwareDestroyProcessTap(tapID)
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
            let gain = gainPointer.pointee

            for (index, inputBuffer) in inputBuffers.enumerated() where index < outputBuffers.count {
                Self.writeScaledAudio(from: inputBuffer, to: outputBuffers[index], gain: gain, format: tapFormat)
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

    private static func createProcessTap(
        audioObjectIDs: [AudioObjectID],
        outputDeviceUID: String,
        tapID: inout AudioObjectID
    ) -> CATapDescription? {
        // Some virtual output devices expose stream 0 but do not route app audio through it.
        let candidates = [
            Self.configure(
                CATapDescription(stereoMixdownOfProcesses: audioObjectIDs),
                name: "MacMix Stereo Mixdown"
            ),
            Self.configure(
                CATapDescription(processes: audioObjectIDs, deviceUID: outputDeviceUID, stream: 0),
                name: "MacMix Output Stream 0"
            ),
        ]

        for tapDescription in candidates {
            tapID = AudioObjectID(kAudioObjectUnknown)

            if AudioHardwareCreateProcessTap(tapDescription, &tapID) == noErr,
               tapID != kAudioObjectUnknown {
                return tapDescription
            }
        }

        tapID = AudioObjectID(kAudioObjectUnknown)
        return nil
    }

    @discardableResult
    private static func configure(_ tapDescription: CATapDescription, name: String) -> CATapDescription {
        tapDescription.name = name
        tapDescription.muteBehavior = .mutedWhenTapped
        tapDescription.isPrivate = true
        return tapDescription
    }

    private static func tapFormat(for tapID: AudioObjectID) -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &dataSize, &format)

        return status == noErr ? format : nil
    }

    private static func writeScaledAudio(
        from inputBuffer: AudioBuffer,
        to outputBuffer: AudioBuffer,
        gain: Float,
        format: AudioStreamBasicDescription
    ) {
        guard let source = inputBuffer.mData,
              let destination = outputBuffer.mData else {
            return
        }

        let inputByteCount = Int(inputBuffer.mDataByteSize)
        let outputByteCount = Int(outputBuffer.mDataByteSize)
        let byteCount = min(inputByteCount, outputByteCount)

        guard byteCount > 0 else {
            return
        }

        guard format.mFormatID == kAudioFormatLinearPCM else {
            copyAudio(from: source, to: destination, byteCount: byteCount, outputByteCount: outputByteCount)
            return
        }

        let flags = format.mFormatFlags
        let isFloat = flags & kAudioFormatFlagIsFloat != 0
        let isSignedInteger = flags & kAudioFormatFlagIsSignedInteger != 0

        if isFloat {
            switch format.mBitsPerChannel {
            case 32:
                writeScaledFloat32(from: source, to: destination, gain: gain, byteCount: byteCount)
            case 64:
                writeScaledFloat64(from: source, to: destination, gain: gain, byteCount: byteCount)
            default:
                copyAudio(from: source, to: destination, byteCount: byteCount, outputByteCount: outputByteCount)
            }
        } else if isSignedInteger {
            switch format.mBitsPerChannel {
            case 16:
                writeScaledInt16(from: source, to: destination, gain: gain, byteCount: byteCount)
            case 32:
                writeScaledInt32(from: source, to: destination, gain: gain, byteCount: byteCount)
            default:
                copyAudio(from: source, to: destination, byteCount: byteCount, outputByteCount: outputByteCount)
            }
        } else {
            copyAudio(from: source, to: destination, byteCount: byteCount, outputByteCount: outputByteCount)
        }

        zeroRemainingAudio(in: destination, byteCount: byteCount, outputByteCount: outputByteCount)
    }

    private static func writeScaledFloat32(
        from source: UnsafeMutableRawPointer,
        to destination: UnsafeMutableRawPointer,
        gain: Float,
        byteCount: Int
    ) {
        let sampleCount = byteCount / MemoryLayout<Float>.size
        guard sampleCount > 0 else {
            return
        }

        var gain = gain
        vDSP_vsmul(
            source.assumingMemoryBound(to: Float.self),
            1,
            &gain,
            destination.assumingMemoryBound(to: Float.self),
            1,
            vDSP_Length(sampleCount)
        )
    }

    private static func writeScaledFloat64(
        from source: UnsafeMutableRawPointer,
        to destination: UnsafeMutableRawPointer,
        gain: Float,
        byteCount: Int
    ) {
        let sampleCount = byteCount / MemoryLayout<Double>.size
        guard sampleCount > 0 else {
            return
        }

        var gain = Double(gain)
        vDSP_vsmulD(
            source.assumingMemoryBound(to: Double.self),
            1,
            &gain,
            destination.assumingMemoryBound(to: Double.self),
            1,
            vDSP_Length(sampleCount)
        )
    }

    private static func writeScaledInt16(
        from source: UnsafeMutableRawPointer,
        to destination: UnsafeMutableRawPointer,
        gain: Float,
        byteCount: Int
    ) {
        let sampleCount = byteCount / MemoryLayout<Int16>.size
        let source = source.assumingMemoryBound(to: Int16.self)
        let destination = destination.assumingMemoryBound(to: Int16.self)
        let gain = Double(gain)

        for index in 0..<sampleCount {
            let scaledSample = (Double(source[index]) * gain).rounded()
            destination[index] = Int16(clamping: Int(scaledSample))
        }
    }

    private static func writeScaledInt32(
        from source: UnsafeMutableRawPointer,
        to destination: UnsafeMutableRawPointer,
        gain: Float,
        byteCount: Int
    ) {
        let sampleCount = byteCount / MemoryLayout<Int32>.size
        let source = source.assumingMemoryBound(to: Int32.self)
        let destination = destination.assumingMemoryBound(to: Int32.self)
        let gain = Double(gain)

        for index in 0..<sampleCount {
            let scaledSample = (Double(source[index]) * gain).rounded()
            destination[index] = Int32(clamping: Int64(scaledSample))
        }
    }

    private static func copyAudio(
        from source: UnsafeMutableRawPointer,
        to destination: UnsafeMutableRawPointer,
        byteCount: Int,
        outputByteCount: Int
    ) {
        memcpy(destination, source, byteCount)
        zeroRemainingAudio(in: destination, byteCount: byteCount, outputByteCount: outputByteCount)
    }

    private static func zeroRemainingAudio(
        in destination: UnsafeMutableRawPointer,
        byteCount: Int,
        outputByteCount: Int
    ) {
        guard outputByteCount > byteCount else {
            return
        }

        memset(destination.advanced(by: byteCount), 0, outputByteCount - byteCount)
    }
}
