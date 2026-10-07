//
//  DisplayVolumeController.swift
//  MacMix
//
//  DDC/CI packet handling and IOKit transport are based on the MCCS protocol
//  and the MIT-licensed MonitorControl project.
//

import CoreAudio
import CoreGraphics
import Foundation
import IOKit
#if arch(x86_64)
import IOKit.i2c
#endif

nonisolated struct ExternalDisplayDescriptor: Sendable {
    let id: CGDirectDisplayID
    let name: String
    let vendorID: UInt32
    let productID: UInt32
    let serialNumber: UInt32

    var cacheIdentifier: String {
        let normalizedName = DisplayVolumeController.normalizedName(name)
        return "\(vendorID)-\(productID)-\(serialNumber)-\(normalizedName)"
    }
}

nonisolated struct DisplayAudioRouteCandidate: Sendable {
    let uid: String
    let name: String
    let transportType: UInt32?

    var canUseDDC: Bool {
        guard let transportType else {
            return false
        }

        return transportType == kAudioDeviceTransportTypeHDMI
            || transportType == kAudioDeviceTransportTypeDisplayPort
            || transportType == kAudioDeviceTransportTypeThunderbolt
    }
}

nonisolated struct DisplayVolumeSnapshot: Sendable {
    let routeUID: String
    let volume: Double
}

nonisolated protocol DDCTransport: AnyObject {
    func read(command: UInt8) -> (current: UInt16, maximum: UInt16)?
    func write(command: UInt8, value: UInt16) -> Bool
}

nonisolated final class DisplayVolumeController: @unchecked Sendable {
    private struct ActiveRoute {
        let uid: String
        let display: ExternalDisplayDescriptor
        let transport: DDCTransport
        let maximumVolume: UInt16
    }

    private enum PendingOperation {
        case volume(routeUID: String, value: Double)
        case mute(routeUID: String, isMuted: Bool, audibleVolume: Double)
    }

    private let queue = DispatchQueue(label: "MacMix.DisplayVolumeController", qos: .userInitiated)
    private let pendingLock = NSLock()
    private let defaults: UserDefaults
    private let transportFactory: (@Sendable (ExternalDisplayDescriptor) -> DDCTransport?)?
    private var activeRoute: ActiveRoute?
    private var pendingOperation: PendingOperation?
    private var isWriteDrainScheduled = false

    private static let speakerVolumeCommand: UInt8 = 0x62
    private static let audioMuteCommand: UInt8 = 0x8D
    private static let safeInitialVolume = 0.15

    init(
        defaults: UserDefaults = .standard,
        transportFactory: (@Sendable (ExternalDisplayDescriptor) -> DDCTransport?)? = nil
    ) {
        self.defaults = defaults
        self.transportFactory = transportFactory
    }

    func activate(
        candidate: DisplayAudioRouteCandidate,
        displays: [ExternalDisplayDescriptor]
    ) async -> DisplayVolumeSnapshot? {
        guard candidate.canUseDDC else {
            deactivate()
            return nil
        }

        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(
                    returning: self.activateSynchronously(candidate: candidate, displays: displays)
                )
            }
        }
    }

    func deactivate() {
        queue.async {
            self.activeRoute = nil
        }
    }

    func setVolume(_ volume: Double, routeUID: String) {
        guard volume.isFinite else { return }
        schedule(.volume(routeUID: routeUID, value: volume))
    }

    func setMuted(_ isMuted: Bool, audibleVolume: Double, routeUID: String) {
        guard isMuted || audibleVolume.isFinite else { return }
        schedule(
            .mute(
                routeUID: routeUID,
                isMuted: isMuted,
                audibleVolume: audibleVolume
            )
        )
    }

    private func activateSynchronously(
        candidate: DisplayAudioRouteCandidate,
        displays: [ExternalDisplayDescriptor]
    ) -> DisplayVolumeSnapshot? {
        guard let display = targetDisplay(for: candidate, displays: displays),
              let transport = makeTransport(for: display) else {
            activeRoute = nil
            return nil
        }

        let cachedVolume = defaults.object(forKey: cacheKey(for: display)) as? Double
        var volume = cachedVolume.flatMap { $0.isFinite ? $0 : nil } ?? Self.safeInitialVolume
        var maximumVolume = DDCVolumeValue.defaultMaximum

        if let values = transport.read(command: Self.speakerVolumeCommand) {
            maximumVolume = DDCVolumeValue.maximum(values.maximum)
            if let readVolume = DDCVolumeValue.volume(current: values.current, maximum: values.maximum) {
                volume = readVolume
            } else {
                NSLog("MacMix DDC ignored speaker-volume current %u (reported maximum %u)",
                      values.current, values.maximum)
            }
            if maximumVolume != values.maximum {
                NSLog("MacMix DDC speaker-volume maximum %u replaced with %u (current %u)",
                      values.maximum, maximumVolume, values.current)
            }
        }

        volume = Self.clampedVolume(volume)
        defaults.set(volume, forKey: cacheKey(for: display))
        activeRoute = ActiveRoute(
            uid: candidate.uid,
            display: display,
            transport: transport,
            maximumVolume: maximumVolume
        )

        return DisplayVolumeSnapshot(routeUID: candidate.uid, volume: volume)
    }

    private func targetDisplay(
        for candidate: DisplayAudioRouteCandidate,
        displays: [ExternalDisplayDescriptor]
    ) -> ExternalDisplayDescriptor? {
        let audioName = Self.normalizedName(candidate.name)
        let nameMatches = displays.filter { display in
            let displayName = Self.normalizedName(display.name)
            return !audioName.isEmpty && displayName == audioName
        }

        if nameMatches.count == 1 {
            return nameMatches[0]
        }

        // A digital display audio route and a single physical external screen
        // are unambiguous even when Core Audio and WindowServer use different names.
        return displays.count == 1 ? displays[0] : nil
    }

    private func makeTransport(for display: ExternalDisplayDescriptor) -> DDCTransport? {
        if let transportFactory { return transportFactory(display) }
        #if arch(arm64)
        return Arm64DDCTransport.transport(for: display)
        #elseif arch(x86_64)
        return IntelDDCTransport(displayID: display.id)
        #else
        return nil
        #endif
    }

    private func schedule(_ operation: PendingOperation) {
        pendingLock.lock()
        pendingOperation = operation
        let shouldSchedule = !isWriteDrainScheduled
        if shouldSchedule {
            isWriteDrainScheduled = true
        }
        pendingLock.unlock()

        guard shouldSchedule else {
            return
        }

        queue.async {
            self.drainPendingWrites()
        }
    }

    private func drainPendingWrites() {
        while true {
            pendingLock.lock()
            guard let operation = pendingOperation else {
                isWriteDrainScheduled = false
                pendingLock.unlock()
                return
            }
            pendingOperation = nil
            pendingLock.unlock()

            guard let activeRoute else {
                continue
            }

            switch operation {
            case let .volume(routeUID, value):
                guard routeUID == activeRoute.uid else {
                    continue
                }

                let volume = Self.clampedVolume(value)
                if volume == 0 { applyMute(true, to: activeRoute) }
                let didWriteVolume = activeRoute.transport.write(
                    command: Self.speakerVolumeCommand,
                    value: Self.ddcValue(for: volume, maximum: activeRoute.maximumVolume)
                )
                // A failed volume write must not unmute the old hardware level.
                if didWriteVolume {
                    if volume > 0 { applyMute(false, to: activeRoute) }
                    defaults.set(volume, forKey: cacheKey(for: activeRoute.display))
                }

            case let .mute(routeUID, isMuted, audibleVolume):
                guard routeUID == activeRoute.uid else {
                    continue
                }

                // MCCS defines 1 as muted and 2 as unmuted for VCP 0x8D.
                // Also write 0x62 so monitors that omit 0x8D still behave correctly.
                if isMuted { applyMute(true, to: activeRoute) }
                let fallbackVolume = isMuted ? 0 : Self.clampedVolume(audibleVolume)
                let didWriteVolume = activeRoute.transport.write(
                    command: Self.speakerVolumeCommand,
                    value: Self.ddcValue(
                        for: fallbackVolume,
                        maximum: activeRoute.maximumVolume
                    )
                )
                if !isMuted && didWriteVolume {
                    applyMute(false, to: activeRoute)
                    defaults.set(fallbackVolume, forKey: cacheKey(for: activeRoute.display))
                }
            }
        }
    }

    private func applyMute(_ muted: Bool, to route: ActiveRoute) {
        guard activeRoute?.uid == route.uid else { return }
        // Diagnostic overrides apply only to the reported U9 model.
        let isU9 = Self.normalizedName(route.display.name) == "r27u91"
        let sendKey = "MacMixDDCU9SendMuteCommands"
        let invertKey = "MacMixDDCU9InvertMuteValues"
        func setting(_ key: String, fallback: Bool) -> Bool {
            (defaults.object(forKey: key) as? Bool)
                ?? (Bundle.main.object(forInfoDictionaryKey: key) as? Bool)
                ?? fallback
        }
        if isU9 && !setting(sendKey, fallback: false) { return }
        let inverted = isU9 && setting(invertKey, fallback: false)
        let value: UInt16 = (muted != inverted) ? 1 : 2
        // The monitor may also be changed using its physical controls; do not
        // treat a cached mute command as authoritative hardware state.
        _ = route.transport.write(command: Self.audioMuteCommand, value: value)
    }

    private func cacheKey(for display: ExternalDisplayDescriptor) -> String {
        "MacMix.DDCVolume.\(display.cacheIdentifier)"
    }

    fileprivate static func normalizedName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private static func clampedVolume(_ volume: Double) -> Double {
        DDCVolumeValue.clamped(volume)
    }

    private static func ddcValue(for volume: Double, maximum: UInt16) -> UInt16 {
        DDCVolumeValue.ddcValue(for: volume, maximum: maximum)
    }
}

#if arch(arm64)

private typealias IOAVServiceRef = CFTypeRef

@_silgen_name("IOAVServiceCreateWithService")
nonisolated private func createIOAVService(
    _ allocator: CFAllocator?,
    _ service: io_service_t
) -> Unmanaged<IOAVServiceRef>?

@_silgen_name("IOAVServiceReadI2C")
nonisolated private func readIOAVI2C(
    _ service: IOAVServiceRef,
    _ chipAddress: UInt32,
    _ offset: UInt32,
    _ outputBuffer: UnsafeMutableRawPointer,
    _ outputBufferSize: UInt32
) -> IOReturn

@_silgen_name("IOAVServiceWriteI2C")
nonisolated private func writeIOAVI2C(
    _ service: IOAVServiceRef,
    _ chipAddress: UInt32,
    _ dataAddress: UInt32,
    _ inputBuffer: UnsafeMutableRawPointer,
    _ inputBufferSize: UInt32
) -> IOReturn

nonisolated private final class Arm64DDCTransport: DDCTransport, @unchecked Sendable {
    private struct RegistryDisplay {
        var edidUUID = ""
        var name = ""
        var serialNumber: UInt32 = 0
        var service: IOAVServiceRef?
    }

    private let service: IOAVServiceRef
    private static let chipAddress = UInt8(0x37)
    private static let dataAddress = UInt8(0x51)

    private init(service: IOAVServiceRef) {
        self.service = service
    }

    static func transport(for display: ExternalDisplayDescriptor) -> Arm64DDCTransport? {
        let candidates = registryDisplays().compactMap { registryDisplay -> (RegistryDisplay, Int)? in
            guard registryDisplay.service != nil else {
                return nil
            }

            let score = matchScore(registryDisplay, display: display)
            return score > 0 ? (registryDisplay, score) : nil
        }
        .sorted { $0.1 > $1.1 }

        guard let best = candidates.first,
              candidates.dropFirst().first?.1 != best.1,
              let service = best.0.service else {
            return nil
        }

        return Arm64DDCTransport(service: service)
    }

    func read(command: UInt8) -> (current: UInt16, maximum: UInt16)? {
        var reply = [UInt8](repeating: 0, count: 11)

        guard communicate(send: [command], reply: &reply) else {
            return nil
        }

        return DDCReplyParser.read(reply, command: command)
    }

    func write(command: UInt8, value: UInt16) -> Bool {
        var unusedReply: [UInt8] = []
        return communicate(
            send: [command, UInt8(value >> 8), UInt8(value & 0xFF)],
            reply: &unusedReply
        )
    }

    private func communicate(send: [UInt8], reply: inout [UInt8]) -> Bool {
        var packet = [UInt8(0x80 | (send.count + 1)), UInt8(send.count)] + send + [0]
        let initialChecksum = send.count == 1
            ? Self.chipAddress << 1
            : Self.chipAddress << 1 ^ Self.dataAddress
        packet[packet.count - 1] = Self.checksum(initial: initialChecksum, bytes: packet.dropLast())

        for _ in 0 ..< 3 {
            let writeSucceeded = DDCWriteRetry.perform {
                usleep(10_000)
                return packet.withUnsafeMutableBytes { bytes in
                    guard let baseAddress = bytes.baseAddress else {
                        return false
                    }
                    return writeIOAVI2C(
                        service,
                        UInt32(Self.chipAddress),
                        UInt32(Self.dataAddress),
                        baseAddress,
                        UInt32(bytes.count)
                    ) == kIOReturnSuccess
                }
            }

            guard !reply.isEmpty else {
                if writeSucceeded {
                    return true
                }
                usleep(20_000)
                continue
            }

            usleep(50_000)
            guard writeSucceeded else {
                usleep(20_000)
                continue
            }
            reply = [UInt8](repeating: 0, count: reply.count)
            let readSucceeded = reply.withUnsafeMutableBytes { bytes in
                guard let baseAddress = bytes.baseAddress else {
                    return false
                }
                return readIOAVI2C(
                    service,
                    UInt32(Self.chipAddress),
                    0,
                    baseAddress,
                    UInt32(bytes.count)
                ) == kIOReturnSuccess
            }
            if readSucceeded,
               let command = send.first,
               DDCReplyParser.read(reply, command: command) != nil {
                return true
            }
            usleep(20_000)
        }

        return false
    }

    private static func checksum<S: Sequence>(initial: UInt8, bytes: S) -> UInt8
    where S.Element == UInt8 {
        bytes.reduce(initial, ^)
    }

    private static func registryDisplays() -> [RegistryDisplay] {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != IO_OBJECT_NULL else {
            return []
        }
        defer { IOObjectRelease(root) }

        var iterator = io_iterator_t()
        guard IORegistryEntryCreateIterator(
            root,
            kIOServicePlane,
            IOOptionBits(kIORegistryIterateRecursively),
            &iterator
        ) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var results: [RegistryDisplay] = []
        var currentDisplay: RegistryDisplay?
        var entry = IOIteratorNext(iterator)

        while entry != IO_OBJECT_NULL {
            var nameBuffer = [CChar](repeating: 0, count: MemoryLayout<io_name_t>.size)
            let hasName = IORegistryEntryGetName(entry, &nameBuffer) == KERN_SUCCESS
            let entryName = hasName ? String(cString: nameBuffer) : ""

            if entryName.contains("AppleCLCD2") || entryName.contains("IOMobileFramebufferShim") {
                currentDisplay = registryDisplayProperties(entry: entry)
            } else if entryName == "DCPAVServiceProxy", var display = currentDisplay {
                let location = stringProperty(entry: entry, key: "Location")
                if location == "External",
                   let unmanagedService = createIOAVService(kCFAllocatorDefault, entry) {
                    display.service = unmanagedService.takeRetainedValue()
                    results.append(display)
                }
            }

            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }

        return results
    }

    private static func registryDisplayProperties(entry: io_registry_entry_t) -> RegistryDisplay {
        var result = RegistryDisplay()
        result.edidUUID = stringProperty(entry: entry, key: "EDID UUID") ?? ""

        guard let attributes = dictionaryProperty(entry: entry, key: "DisplayAttributes"),
              let productAttributes = attributes["ProductAttributes"] as? NSDictionary else {
            return result
        }

        result.name = productAttributes["ProductName"] as? String ?? ""
        if let serial = productAttributes["SerialNumber"] as? NSNumber {
            result.serialNumber = serial.uint32Value
        }
        return result
    }

    private static func stringProperty(entry: io_registry_entry_t, key: String) -> String? {
        guard let property = IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively)
        ) else {
            return nil
        }
        return property.takeRetainedValue() as? String
    }

    private static func dictionaryProperty(
        entry: io_registry_entry_t,
        key: String
    ) -> NSDictionary? {
        guard let property = IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively)
        ) else {
            return nil
        }
        return property.takeRetainedValue() as? NSDictionary
    }

    private static func matchScore(
        _ registryDisplay: RegistryDisplay,
        display: ExternalDisplayDescriptor
    ) -> Int {
        var score = 0
        let edidUUID = registryDisplay.edidUUID.uppercased()
        let vendor = String(format: "%04X", UInt16(truncatingIfNeeded: display.vendorID))
        let productValue = UInt16(truncatingIfNeeded: display.productID)
        let product = String(
            format: "%02X%02X",
            UInt8(productValue & 0xFF),
            UInt8(productValue >> 8)
        )

        if edidUUID.count >= 8,
           edidUUID.prefix(4) == vendor,
           edidUUID.dropFirst(4).prefix(4) == product {
            score += 10
        }
        if !registryDisplay.name.isEmpty,
           DisplayVolumeController.normalizedName(registryDisplay.name)
                == DisplayVolumeController.normalizedName(display.name) {
            score += 4
        }
        if registryDisplay.serialNumber != 0,
           display.serialNumber != 0,
           registryDisplay.serialNumber == display.serialNumber {
            score += 6
        }
        return score
    }
}

#endif

#if arch(x86_64)

@_silgen_name("CGSServiceForDisplayNumber")
nonisolated private func serviceForDisplayNumber(
    _ display: CGDirectDisplayID,
    _ service: UnsafeMutablePointer<io_service_t>
)

nonisolated private final class IntelDDCTransport: DDCTransport, @unchecked Sendable {
    private let framebuffer: io_service_t
    private let replyTransactionType: IOOptionBits

    init?(displayID: CGDirectDisplayID) {
        var framebuffer = io_service_t()
        serviceForDisplayNumber(displayID, &framebuffer)
        guard framebuffer != IO_OBJECT_NULL else {
            return nil
        }
        guard let transactionType = Self.supportedTransactionType() else {
            IOObjectRelease(framebuffer)
            return nil
        }

        var busCount: IOItemCount = 0
        guard IOFBGetI2CInterfaceCount(framebuffer, &busCount) == KERN_SUCCESS,
              busCount > 0 else {
            IOObjectRelease(framebuffer)
            return nil
        }

        self.framebuffer = framebuffer
        replyTransactionType = transactionType
    }

    deinit {
        IOObjectRelease(framebuffer)
    }

    func read(command: UInt8) -> (current: UInt16, maximum: UInt16)? {
        var data: [UInt8] = [0x51, 0x82, 0x01, command, 0]
        data[4] = data.dropLast().reduce(0x6E, ^)

        for _ in 0 ..< 3 {
            usleep(10_000)
            var reply = [UInt8](repeating: 0, count: 11)
            let dataCount = UInt32(data.count)
            let replyCount = UInt32(reply.count)
            let succeeded = data.withUnsafeMutableBufferPointer { dataBuffer in
                reply.withUnsafeMutableBufferPointer { replyBuffer in
                    guard let dataPointer = dataBuffer.baseAddress,
                          let replyPointer = replyBuffer.baseAddress else { return false }
                    var request = IOI2CRequest()
                    request.sendAddress = 0x6E
                    request.sendTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
                    request.sendBuffer = vm_address_t(bitPattern: dataPointer)
                    request.sendBytes = dataCount
                    request.minReplyDelay = 10
                    request.replyAddress = 0x6F
                    request.replySubAddress = 0x51
                    request.replyTransactionType = replyTransactionType
                    request.replyBuffer = vm_address_t(bitPattern: replyPointer)
                    request.replyBytes = replyCount
                    return send(request: &request)
                }
            }

            guard succeeded,
                  let values = DDCReplyParser.read(reply, command: command) else {
                continue
            }

            return values
        }
        return nil
    }

    func write(command: UInt8, value: UInt16) -> Bool {
        var data: [UInt8] = [
            0x51,
            0x84,
            0x03,
            command,
            UInt8(value >> 8),
            UInt8(value & 0xFF),
            0,
        ]
        data[6] = data.dropLast().reduce(0x6E, ^)
        let dataCount = UInt32(data.count)

        return DDCWriteRetry.perform {
            usleep(10_000)
            return data.withUnsafeMutableBufferPointer { dataBuffer in
                guard let pointer = dataBuffer.baseAddress else { return false }
                var request = IOI2CRequest()
                request.sendAddress = 0x6E
                request.sendTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
                request.sendBuffer = vm_address_t(bitPattern: pointer)
                request.sendBytes = dataCount
                request.replyTransactionType = IOOptionBits(kIOI2CNoTransactionType)
                return send(request: &request)
            }
        }
    }

    private func send(request: inout IOI2CRequest) -> Bool {
        var busCount: IOItemCount = 0
        guard IOFBGetI2CInterfaceCount(framebuffer, &busCount) == KERN_SUCCESS else {
            return false
        }

        for bus in 0 ..< busCount {
            var interface = io_service_t()
            guard IOFBCopyI2CInterfaceForBus(framebuffer, bus, &interface) == KERN_SUCCESS else {
                continue
            }
            defer { IOObjectRelease(interface) }

            var connection: IOI2CConnectRef?
            guard IOI2CInterfaceOpen(interface, IOOptionBits(), &connection) == KERN_SUCCESS,
                  let connection else {
                continue
            }
            defer { IOI2CInterfaceClose(connection, IOOptionBits()) }

            guard IOI2CSendRequest(connection, IOOptionBits(), &request) == KERN_SUCCESS,
                  request.result == KERN_SUCCESS else {
                continue
            }
            return true
        }
        return false
    }

    private static func supportedTransactionType() -> IOOptionBits? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceNameMatching("IOFramebufferI2CInterface"),
            &iterator
        ) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != IO_OBJECT_NULL {
            var supportedType: IOOptionBits?
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(
                service,
                &properties,
                kCFAllocatorDefault,
                IOOptionBits()
            ) == KERN_SUCCESS,
               let dictionary = properties?.takeRetainedValue() as NSDictionary?,
               let types = dictionary[kIOI2CTransactionTypesKey] as? UInt64 {
                if (1 << kIOI2CDDCciReplyTransactionType) & types != 0 {
                    supportedType = IOOptionBits(kIOI2CDDCciReplyTransactionType)
                } else if (1 << kIOI2CSimpleTransactionType) & types != 0 {
                    supportedType = IOOptionBits(kIOI2CSimpleTransactionType)
                }
            }
            IOObjectRelease(service)
            if let supportedType {
                return supportedType
            }
            service = IOIteratorNext(iterator)
        }
        return nil
    }
}

#endif
