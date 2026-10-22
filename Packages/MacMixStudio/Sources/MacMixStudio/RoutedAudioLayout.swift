import CoreAudio
import Foundation

/// HAL formats and channel addresses are resolved off the real-time thread.
/// An aggregate concatenates streams; it does not mirror each app to each device.
public struct RoutedAudioLayout {
    /// Keeping an already-correct native path avoids introducing a tap just to
    /// change follow/fixed policy. Do not bypass apps with their own output choice.
    public static func canKeepNativeOutput(processIDs: [AudioObjectID], selectedUIDs: [String], systemUID: String) -> Bool {
        guard selectedUIDs == [systemUID], !processIDs.isEmpty,
              let device: AudioObjectID = value(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice),
              uid(device) == systemUID else { return false }
        var hasOutput = false
        for process in processIDs {
            guard let outputs = ids(process, kAudioProcessPropertyDevices, scope: kAudioDevicePropertyScopeOutput),
                  outputs.allSatisfy({ $0 == device }) else { return false }
            hasOutput = hasOutput || !outputs.isEmpty
        }
        return hasOutput
    }

    public struct Channel {
        public let format: AudioStreamBasicDescription
        public let bufferIndex: UInt32
        public let channelIndex: UInt32
        /// 0/1 = left/right, UInt32.max = mono mixdown.
        public let sourceChannel: UInt32
    }
    public struct Input {
        public let format: AudioStreamBasicDescription
        public let bufferOffset: Int
        public var bufferCount: Int { RoutedAudioLayout.bufferCount(format) }
    }
    public let inputs: [Input]
    public let channelsByDevice: [String: [Channel]]
    public let outputBufferIndices: [UInt32]
    public let physicalInputStreamCount: Int
    public let inputStreamCount: Int

    public var signature: [UInt64] {
        func words(_ f: AudioStreamBasicDescription) -> [UInt64] {
            [f.mSampleRate.bitPattern, UInt64(f.mFormatID), UInt64(f.mFormatFlags),
             UInt64(f.mBytesPerFrame), UInt64(f.mChannelsPerFrame), UInt64(f.mBitsPerChannel)]
        }
        return [UInt64(physicalInputStreamCount), UInt64(inputStreamCount)]
            + inputs.flatMap { [UInt64($0.bufferOffset)] + words($0.format) }
            + channelsByDevice.keys.sorted().flatMap { uid in
                channelsByDevice[uid, default: []].flatMap {
                    [UInt64($0.bufferIndex), UInt64($0.channelIndex), UInt64($0.sourceChannel)] + words($0.format)
                }
            }
    }

    public static func subdevices(_ uids: [String]) -> [[String: Any]] {
        uids.enumerated().map { index, uid in
            [kAudioSubDeviceUIDKey: uid,
             kAudioSubDeviceDriftCompensationKey: index != 0,
             kAudioSubDeviceDriftCompensationQualityKey: kAudioAggregateDriftCompensationMaxQuality]
        }
    }

    public init?(aggregateID: AudioObjectID, deviceUIDs: [String], tapCount: Int) {
        guard let devices = Self.ids(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices),
              let inputStreams = Self.ids(aggregateID, kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeInput),
              let outputStreams = Self.ids(aggregateID, kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput),
              inputStreams.count >= tapCount else { return nil }
        let deviceIDs = deviceUIDs.compactMap { uid in devices.first { Self.uid($0) == uid } }
        guard deviceIDs.count == deviceUIDs.count else { return nil }
        // HAL orders physical streams first, then the taps in the tap-list order.
        physicalInputStreamCount = inputStreams.count - tapCount
        inputStreamCount = inputStreams.count
        var inputs: [Input] = []
        var offset = 0
        for (index, stream) in inputStreams.enumerated() {
            guard let format = Self.format(stream) else { return nil }
            if index >= physicalInputStreamCount {
                guard Self.supports(format), format.mChannelsPerFrame == 2 else { return nil }
                inputs.append(Input(format: format, bufferOffset: offset))
            }
            offset += Self.bufferCount(format)
        }
        self.inputs = inputs

        var outputs: [(format: AudioStreamBasicDescription, firstChannel: UInt32, bufferOffset: Int)] = []
        offset = 0
        for stream in outputStreams {
            guard let format = Self.format(stream), Self.supports(format),
                  let first: UInt32 = Self.value(stream, kAudioStreamPropertyStartingChannel) else { return nil }
            outputs.append((format, first, offset))
            offset += Self.bufferCount(format)
        }
        outputBufferIndices = (0..<offset).map { UInt32($0) }
        var mapping: [String: [Channel]] = [:]
        var deviceChannelOffset: UInt32 = 0
        for (uid, deviceID) in zip(deviceUIDs, deviceIDs) {
            guard let streams = Self.ids(deviceID, kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput) else { return nil }
            let formats = streams.compactMap(Self.format)
            guard formats.count == streams.count else { return nil }
            let count = formats.reduce(UInt32(0)) { $0 + $1.mChannelsPerFrame }
            guard count > 0 else { return nil }
            var preferred: [UInt32] = [1, min(2, count)]
            var address = Self.address(kAudioDevicePropertyPreferredChannelsForStereo, scope: kAudioDevicePropertyScopeOutput)
            var size = UInt32(2 * MemoryLayout<UInt32>.size)
            let read = preferred.withUnsafeMutableBytes {
                AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, $0.baseAddress!)
            }
            if read != noErr || preferred.contains(where: { $0 == 0 || $0 > count }) { preferred = [1, min(2, count)] }
            let mono = count == 1 || preferred[0] == preferred[1]
            var channels: [Channel] = []
            for source in 0..<(mono ? 1 : 2) {
                let absoluteChannel = deviceChannelOffset + preferred[source]
                guard let stream = outputs.first(where: {
                    absoluteChannel >= $0.firstChannel && absoluteChannel < $0.firstChannel + $0.format.mChannelsPerFrame
                }), inputs.allSatisfy({ abs($0.format.mSampleRate - stream.format.mSampleRate) < 1 }) else { return nil }
                let local = absoluteChannel - stream.firstChannel
                let planar = stream.format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
                channels.append(Channel(format: stream.format,
                    bufferIndex: UInt32(stream.bufferOffset) + (planar ? local : 0),
                    channelIndex: planar ? 0 : local, sourceChannel: mono ? .max : UInt32(source)))
            }
            mapping[uid] = channels
            deviceChannelOffset += count
        }
        guard outputs.reduce(UInt32(0), { $0 + $1.format.mChannelsPerFrame }) == deviceChannelOffset else { return nil }
        channelsByDevice = mapping
    }

    private static func bufferCount(_ format: AudioStreamBasicDescription) -> Int {
        format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 ? Int(format.mChannelsPerFrame) : 1
    }
    private static func supports(_ format: AudioStreamBasicDescription) -> Bool {
        guard format.mFormatID == kAudioFormatLinearPCM, format.mSampleRate > 0,
              format.mChannelsPerFrame > 0, format.mChannelsPerFrame <= 64 else { return false }
        let channels = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 ? 1 : format.mChannelsPerFrame
        let bytes = format.mBytesPerFrame / channels
        if format.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            return format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0
                && ((format.mBitsPerChannel == 32 && bytes == 4) || (format.mBitsPerChannel == 64 && bytes == 8))
        }
        guard format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0 else { return false }
        if format.mBitsPerChannel == 24 { return bytes == 3 || bytes == 4 }
        return format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0
            && ((format.mBitsPerChannel == 16 && bytes == 2) || (format.mBitsPerChannel == 32 && bytes == 4))
    }
    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    private static func ids(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                            scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID]? {
        var address = address(selector, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr else { return nil }
        if size == 0 { return [] }
        var values = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let result = values.withUnsafeMutableBytes { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0.baseAddress!) }
        return result == noErr ? values : nil
    }
    private static func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = address(selector)
        let storage = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<T>.size, alignment: MemoryLayout<T>.alignment)
        defer { storage.deallocate() }
        var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, storage) == noErr else { return nil }
        return storage.load(as: T.self)
    }
    private static func uid(_ object: AudioObjectID) -> String? {
        var address = address(kAudioDevicePropertyDeviceUID)
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { return nil }
        return value as String?
    }
    private static func format(_ stream: AudioObjectID) -> AudioStreamBasicDescription? {
        value(stream, kAudioStreamPropertyVirtualFormat)
    }
}
