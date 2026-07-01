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

    private struct OutputStreamCandidate {
        let index: UInt
        let format: AudioStreamBasicDescription
        let isActive: Bool
    }

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
        // Automatic mode: multichannel devices get first chance to keep the output PCM stream.
        // If that tap cannot be created, fall back to the established stereo mixdown path.
        let stereoMixdownTap = Self.configure(
            CATapDescription(stereoMixdownOfProcesses: audioObjectIDs),
            name: "MacMix Stereo Mixdown"
        )
        let candidates: [CATapDescription]
        if let outputStreamIndex = preferredMultichannelOutputStreamIndex(outputDeviceUID: outputDeviceUID) {
            let outputStreamTap = Self.configure(
                CATapDescription(processes: audioObjectIDs, deviceUID: outputDeviceUID, stream: outputStreamIndex),
                name: "MacMix Output Stream \(outputStreamIndex)"
            )
            candidates = [outputStreamTap, stereoMixdownTap]
        } else {
            candidates = [stereoMixdownTap]
        }

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

    private static func preferredMultichannelOutputStreamIndex(outputDeviceUID: String) -> UInt? {
        guard let deviceID = deviceID(forUID: outputDeviceUID) else {
            return nil
        }

        return outputStreamCandidates(deviceID: deviceID)
            .filter { $0.format.mChannelsPerFrame > 2 }
            .sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive {
                    return lhs.isActive
                }

                if lhs.format.mChannelsPerFrame != rhs.format.mChannelsPerFrame {
                    return lhs.format.mChannelsPerFrame > rhs.format.mChannelsPerFrame
                }

                return lhs.index < rhs.index
            }
            .first?
            .index
    }

    private static func outputStreamCandidates(deviceID: AudioObjectID) -> [OutputStreamCandidate] {
        audioObjectIDs(
            objectID: deviceID,
            selector: kAudioDevicePropertyStreams,
            scope: kAudioDevicePropertyScopeOutput
        )
        .enumerated()
        .compactMap { streamIndex, streamID in
            guard let format = streamFormat(streamID: streamID) else {
                return nil
            }

            return OutputStreamCandidate(
                index: UInt(streamIndex),
                format: format,
                isActive: boolProperty(streamID, selector: kAudioStreamPropertyIsActive)
            )
        }
    }

    private static func deviceID(forUID uid: String) -> AudioObjectID? {
        audioObjectIDs(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDevices
        )
        .first { deviceID in
            stringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID) == uid
        }
    }

    private static func audioObjectIDs(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> [AudioObjectID] {
        var address = propertyAddress(selector: selector, scope: scope)
        var dataSize: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &dataSize) == noErr else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else {
            return []
        }

        var objectIDs = Array(repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &objectIDs)
        return status == noErr ? objectIDs.filter { $0 != kAudioObjectUnknown } : []
    }

    private static func stringProperty(_ objectID: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = propertyAddress(selector: selector)
        var value: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, pointer)
        }

        guard status == noErr else {
            return nil
        }

        return value as String?
    }

    private static func boolProperty(_ objectID: AudioObjectID, selector: AudioObjectPropertySelector) -> Bool {
        var address = propertyAddress(selector: selector)
        var value = UInt32(0)
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value)
        return status == noErr && value != 0
    }

    private static func streamFormat(streamID: AudioStreamID) -> AudioStreamBasicDescription? {
        var address = propertyAddress(selector: kAudioStreamPropertyVirtualFormat)
        var format = AudioStreamBasicDescription()
        var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(streamID, &address, 0, nil, &dataSize, &format)

        return status == noErr ? format : nil
    }

    private static func propertyAddress(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
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
            case 24:
                if !writeScaledInt24(from: source, to: destination, gain: gain, byteCount: byteCount, format: format) {
                    copyAudio(from: source, to: destination, byteCount: byteCount, outputByteCount: outputByteCount)
                }
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

    private static func writeScaledInt24(
        from source: UnsafeMutableRawPointer,
        to destination: UnsafeMutableRawPointer,
        gain: Float,
        byteCount: Int,
        format: AudioStreamBasicDescription
    ) -> Bool {
        let flags = format.mFormatFlags
        let isBigEndian = flags & kAudioFormatFlagIsBigEndian != 0
        let isAlignedHigh = flags & kAudioFormatFlagIsAlignedHigh != 0
        let isNonInterleaved = flags & kAudioFormatFlagIsNonInterleaved != 0
        let channelsPerFrame = max(1, Int(format.mChannelsPerFrame))
        let bytesPerFrame = Int(format.mBytesPerFrame)
        let bytesPerSample = bytesPerFrame > 0
            ? (isNonInterleaved ? bytesPerFrame : max(1, bytesPerFrame / channelsPerFrame))
            : 3

        guard bytesPerSample == 3 || bytesPerSample == 4 else {
            return false
        }

        let sampleCount = byteCount / bytesPerSample
        guard sampleCount > 0 else {
            return true
        }

        let source = source.assumingMemoryBound(to: UInt8.self)
        let destination = destination.assumingMemoryBound(to: UInt8.self)
        let gain = Double(gain)

        for index in 0..<sampleCount {
            let offset = index * bytesPerSample
            let sample = readSignedInt24(
                from: source.advanced(by: offset),
                bytesPerSample: bytesPerSample,
                isBigEndian: isBigEndian,
                isAlignedHigh: isAlignedHigh
            )
            let scaledSample = clampInt24((Double(sample) * gain).rounded())

            writeSignedInt24(
                scaledSample,
                to: destination.advanced(by: offset),
                bytesPerSample: bytesPerSample,
                isBigEndian: isBigEndian,
                isAlignedHigh: isAlignedHigh
            )
        }

        return true
    }

    private static func readSignedInt24(
        from source: UnsafePointer<UInt8>,
        bytesPerSample: Int,
        isBigEndian: Bool,
        isAlignedHigh: Bool
    ) -> Int32 {
        if bytesPerSample == 4 {
            let raw32 = readSignedInt32Bytes(from: source, isBigEndian: isBigEndian)
            return isAlignedHigh ? raw32 >> 8 : signExtendInt24(raw32 & 0x00FF_FFFF)
        }

        let raw24: Int32
        if isBigEndian {
            raw24 = Int32(source[0]) << 16
                | Int32(source[1]) << 8
                | Int32(source[2])
        } else {
            raw24 = Int32(source[0])
                | Int32(source[1]) << 8
                | Int32(source[2]) << 16
        }

        return signExtendInt24(raw24)
    }

    private static func writeSignedInt24(
        _ sample: Int32,
        to destination: UnsafeMutablePointer<UInt8>,
        bytesPerSample: Int,
        isBigEndian: Bool,
        isAlignedHigh: Bool
    ) {
        if bytesPerSample == 4 {
            let raw32 = isAlignedHigh ? sample << 8 : sample & 0x00FF_FFFF
            writeSignedInt32Bytes(raw32, to: destination, isBigEndian: isBigEndian)
            return
        }

        let raw24 = sample & 0x00FF_FFFF
        if isBigEndian {
            destination[0] = UInt8((raw24 >> 16) & 0xFF)
            destination[1] = UInt8((raw24 >> 8) & 0xFF)
            destination[2] = UInt8(raw24 & 0xFF)
        } else {
            destination[0] = UInt8(raw24 & 0xFF)
            destination[1] = UInt8((raw24 >> 8) & 0xFF)
            destination[2] = UInt8((raw24 >> 16) & 0xFF)
        }
    }

    private static func readSignedInt32Bytes(from source: UnsafePointer<UInt8>, isBigEndian: Bool) -> Int32 {
        let raw: UInt32
        if isBigEndian {
            raw = UInt32(source[0]) << 24
                | UInt32(source[1]) << 16
                | UInt32(source[2]) << 8
                | UInt32(source[3])
        } else {
            raw = UInt32(source[0])
                | UInt32(source[1]) << 8
                | UInt32(source[2]) << 16
                | UInt32(source[3]) << 24
        }

        return Int32(bitPattern: raw)
    }

    private static func writeSignedInt32Bytes(
        _ sample: Int32,
        to destination: UnsafeMutablePointer<UInt8>,
        isBigEndian: Bool
    ) {
        let raw = UInt32(bitPattern: sample)
        if isBigEndian {
            destination[0] = UInt8((raw >> 24) & 0xFF)
            destination[1] = UInt8((raw >> 16) & 0xFF)
            destination[2] = UInt8((raw >> 8) & 0xFF)
            destination[3] = UInt8(raw & 0xFF)
        } else {
            destination[0] = UInt8(raw & 0xFF)
            destination[1] = UInt8((raw >> 8) & 0xFF)
            destination[2] = UInt8((raw >> 16) & 0xFF)
            destination[3] = UInt8((raw >> 24) & 0xFF)
        }
    }

    private static func signExtendInt24(_ value: Int32) -> Int32 {
        value & 0x0080_0000 != 0 ? value | ~0x00FF_FFFF : value
    }

    private static func clampInt24(_ value: Double) -> Int32 {
        Int32(max(-8_388_608, min(8_388_607, value)))
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
