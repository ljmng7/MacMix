// Compiled alongside the actual DDC parser and controller by the runner.
nonisolated final class FakeDDCTransport: DDCTransport, @unchecked Sendable {
    struct Write: Equatable { let command: UInt8; let value: UInt16 }
    private let lock = NSLock()
    private var recorded: [Write] = []
    let reading: (current: UInt16, maximum: UInt16)?
    let failVolumeWrites: Bool

    init(current: UInt16?, maximum: UInt16 = 100, failVolumeWrites: Bool = false) {
        reading = current.map { ($0, maximum) }
        self.failVolumeWrites = failVolumeWrites
    }

    func read(command: UInt8) -> (current: UInt16, maximum: UInt16)? { reading }
    func write(command: UInt8, value: UInt16) -> Bool {
        lock.lock(); defer { lock.unlock() }
        recorded.append(Write(command: command, value: value))
        return !(command == 0x62 && failVolumeWrites)
    }
    func writes() -> [Write] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }
}

extension DisplayVolumeController {
    // Same-file extension in the standalone runner; no test API in the app.
    func flushForTesting() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }
}

@main struct DDCVolumeTests {
    static func packet(current: UInt16 = 50, maximum: UInt16 = 100) -> [UInt8] {
        var reply: [UInt8] = [0x6E, 0x88, 0x02, 0, 0x62, 0,
                             UInt8(maximum >> 8), UInt8(maximum & 0xFF),
                             UInt8(current >> 8), UInt8(current & 0xFF), 0]
        fixChecksum(&reply)
        return reply
    }

    static func fixChecksum(_ reply: inout [UInt8]) {
        reply[10] = reply.dropLast().reduce(UInt8(0x50), ^)
    }

    static func testParserAndConversion() {
        let normal = DDCReplyParser.read(packet(), command: 0x62)!
        precondition(normal.current == 50 && normal.maximum == 100)
        let wide = DDCReplyParser.read(packet(current: 512, maximum: 1024), command: 0x62)!
        precondition(wide.current == 512 && wide.maximum == 1024)
        precondition(DDCVolumeValue.volume(current: wide.current, maximum: wide.maximum) == 0.5)

        for reported: UInt16 in [0, 100, 0xFFFF] {
            let values = DDCReplyParser.read(packet(maximum: reported), command: 0x62)!
            precondition(DDCVolumeValue.volume(current: values.current, maximum: values.maximum) == 0.5)
            precondition(DDCVolumeValue.ddcValue(for: 0.5, maximum: reported) == 50)
            precondition(DDCVolumeValue.ddcValue(for: 1, maximum: reported) == 100)
        }
        precondition(DDCVolumeValue.volume(current: 150, maximum: 200) == 0.75)
        precondition(DDCVolumeValue.ddcValue(for: 0.75, maximum: 200) == 150)
        for reported: UInt16 in [0, 100, 0xFFFF] {
            precondition(DDCVolumeValue.volume(current: 101, maximum: reported) == nil)
            precondition(DDCVolumeValue.volume(current: 0xFFFF, maximum: reported) == nil)
            precondition(DDCVolumeValue.volume(current: 0xFF, maximum: reported) == nil)
        }
        precondition(DDCVolumeValue.volume(current: 0, maximum: 100) == 0)
        precondition(DDCVolumeValue.volume(current: 100, maximum: 100) == 1)
        precondition(DDCVolumeValue.ddcValue(for: -1, maximum: 100) == 0)
        precondition(DDCVolumeValue.ddcValue(for: 2, maximum: 100) == 100)
        for invalid in [Double.nan, .infinity, -.infinity] {
            precondition(DDCVolumeValue.ddcValue(for: invalid, maximum: 100) == 0)
        }
        for step in 0...10_000 {
            let value = DDCVolumeValue.ddcValue(for: Double(step) / 10_000, maximum: 0xFFFF)
            precondition(value <= 100)
        }

        precondition(DDCReplyParser.read([], command: 0x62) == nil)
        precondition(DDCReplyParser.read(Array(packet().dropLast()), command: 0x62) == nil)
        precondition(DDCReplyParser.read(packet() + [0], command: 0x62) == nil)
        // Recompute checksums so these prove semantic validation, not XOR failure.
        for (index, value): (Int, UInt8) in [(0, 0x51), (1, 0x87), (2, 0x03),
                                            (3, 1), (4, 0x10), (5, 2)] {
            var malformed = packet()
            malformed[index] = value
            fixChecksum(&malformed)
            precondition(DDCReplyParser.read(malformed, command: 0x62) == nil)
        }
        var corrupted = packet(); corrupted[10] ^= 1
        precondition(DDCReplyParser.read(corrupted, command: 0x62) == nil)
    }

    static func testWriteRetries() {
        // Exact checksum-valid R27U91 reply from the user's diagnostic log.
        let u9: [UInt8] = [0x6E, 0x88, 0x02, 0, 0x62, 1, 0xFF, 0xFF, 0, 0x32, 0xE5]
        let u9Values = DDCReplyParser.read(u9, command: 0x62)!
        precondition(DDCVolumeValue.volume(current: u9Values.current, maximum: u9Values.maximum) == 0.5)
        precondition(DDCVolumeValue.ddcValue(for: 0.5, maximum: u9Values.maximum) == 50)
        for outcomes in [[true, false], [false, true], [true, true], [false, false]] {
            var calls = 0
            let succeeded = DDCWriteRetry.perform {
                defer { calls += 1 }
                return outcomes[calls]
            }
            precondition(calls == 2) // Do not short-circuit away a write cycle.
            precondition(succeeded == outcomes.contains(true))
        }
        // The successful request still permits consuming a valid reply even
        // when the monitor rejects the duplicate while preparing that reply.
        var calls = 0
        let didWrite = DDCWriteRetry.perform {
            defer { calls += 1 }
            return calls == 0
        }
        let values = didWrite ? DDCReplyParser.read(packet(), command: 0x62) : nil
        precondition(values?.current == 50 && values?.maximum == 100)
    }

    @MainActor static func testController() async {
        let display = ExternalDisplayDescriptor(id: 1, name: "Test Display", vendorID: 1,
                                                productID: 2, serialNumber: 3)
        let route = DisplayAudioRouteCandidate(uid: "test-route", name: "Test Display",
                                                transportType: kAudioDeviceTransportTypeHDMI)
        let cacheKey = "MacMix.DDCVolume.\(display.cacheIdentifier)"
        let suite = "MacMix.DDC.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        for reported: UInt16 in [0, 100, 0xFFFF, 200] {
            let fake = FakeDDCTransport(current: 50, maximum: reported)
            let controller = DisplayVolumeController(defaults: defaults, transportFactory: { _ in fake })
            let snapshot = await controller.activate(candidate: route, displays: [display])
            precondition(snapshot?.volume == (reported == 200 ? 0.25 : 0.5))
            precondition(fake.writes().isEmpty) // Activation must never adjust hardware.
            controller.setVolume(0.5, routeUID: route.uid)
            await controller.flushForTesting()
            precondition(fake.writes() == [.init(command: 0x62, value: reported == 200 ? 100 : 50),
                                           .init(command: 0x8D, value: 2)])
        }

        for current: UInt16? in [nil, 101, 0xFFFF, 0xFF] {
            defaults.set(0.3, forKey: cacheKey)
            let fake = FakeDDCTransport(current: current, maximum: 0xFFFF)
            let controller = DisplayVolumeController(defaults: defaults, transportFactory: { _ in fake })
            let snapshot = await controller.activate(candidate: route, displays: [display])
            precondition(snapshot?.volume == 0.3)
            precondition(fake.writes().isEmpty)
        }

        defaults.removeObject(forKey: cacheKey)
        let invalidCurrent = FakeDDCTransport(current: 201, maximum: 200)
        let validRange = DisplayVolumeController(defaults: defaults, transportFactory: { _ in invalidCurrent })
        let initial = await validRange.activate(candidate: route, displays: [display])
        precondition(initial?.volume == 0.15)
        validRange.setVolume(0.5, routeUID: route.uid)
        await validRange.flushForTesting()
        precondition(invalidCurrent.writes().first == .init(command: 0x62, value: 100))

        defaults.removeObject(forKey: cacheKey)
        let failed = FakeDDCTransport(current: nil, failVolumeWrites: true)
        let controller = DisplayVolumeController(defaults: defaults, transportFactory: { _ in failed })
        let fallback = await controller.activate(candidate: route, displays: [display])
        precondition(fallback?.volume == 0.15)
        controller.setVolume(0.5, routeUID: route.uid)
        await controller.flushForTesting()
        precondition(failed.writes() == [.init(command: 0x62, value: 50)])
        precondition(defaults.double(forKey: cacheKey) == 0.15)
        controller.setMuted(false, audibleVolume: 0.4, routeUID: route.uid)
        await controller.flushForTesting()
        precondition(failed.writes().last == .init(command: 0x62, value: 40))
        precondition(!failed.writes().contains(.init(command: 0x8D, value: 2)))
        precondition(defaults.double(forKey: cacheKey) == 0.15)

        let fake = FakeDDCTransport(current: 50)
        let working = DisplayVolumeController(defaults: defaults, transportFactory: { _ in fake })
        _ = await working.activate(candidate: route, displays: [display])
        working.setVolume(0.9, routeUID: "stale-route")
        working.setVolume(.nan, routeUID: route.uid)
        working.setVolume(.infinity, routeUID: route.uid)
        working.setMuted(false, audibleVolume: .nan, routeUID: route.uid)
        await working.flushForTesting()
        precondition(fake.writes().isEmpty)
        working.setVolume(0, routeUID: route.uid)
        await working.flushForTesting()
        precondition(fake.writes() == [.init(command: 0x8D, value: 1), .init(command: 0x62, value: 0)])
        working.setMuted(false, audibleVolume: 0.4, routeUID: route.uid)
        await working.flushForTesting()
        precondition(Array(fake.writes().suffix(2)) == [.init(command: 0x62, value: 40),
                                                       .init(command: 0x8D, value: 2)])
        precondition(defaults.double(forKey: cacheKey) == 0.4)
        working.setMuted(true, audibleVolume: .nan, routeUID: route.uid)
        await working.flushForTesting()
        precondition(Array(fake.writes().suffix(2)) == [.init(command: 0x8D, value: 1),
                                                       .init(command: 0x62, value: 0)])
        working.deactivate()
        await working.flushForTesting()
        let count = fake.writes().count
        working.setVolume(0.8, routeUID: route.uid)
        await working.flushForTesting()
        precondition(fake.writes().count == count)
    }

    @MainActor static func main() async {
        testParserAndConversion()
        testWriteRetries()
        await testController()
        await testU9Modes()
        print("DDC volume: packet validation, sentinel maximum, conversion, write retries, cache fallback, routing and failed-write mute safety passed.")
    }

    @MainActor static func testU9Modes() async {
        let suite = "MacMix.U9.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let route = DisplayAudioRouteCandidate(uid: "u9", name: "R27U91",
                                               transportType: kAudioDeviceTransportTypeHDMI)
        for name in ["R27U91", "Other Display"] {
            for send in [false, true] {
                for invert in [false, true] {
                    defaults.set(send, forKey: "MacMixDDCU9SendMuteCommands")
                    defaults.set(invert, forKey: "MacMixDDCU9InvertMuteValues")
                    let display = ExternalDisplayDescriptor(id: 1, name: name,
                                                             vendorID: 1, productID: 2, serialNumber: 3)
                    let fake = FakeDDCTransport(current: 50, maximum: 65535)
                    let controller = DisplayVolumeController(defaults: defaults, transportFactory: { _ in fake })
                    _ = await controller.activate(candidate: route, displays: [display])
                    controller.setVolume(0.5, routeUID: route.uid)
                    await controller.flushForTesting()
                    let usesMute = name != "R27U91" || send
                    let isInverted = name == "R27U91" && invert
                    var expected: [FakeDDCTransport.Write] = [.init(command: 0x62, value: 50)]
                    if usesMute { expected.append(.init(command: 0x8D, value: isInverted ? 1 : 2)) }
                    precondition(fake.writes() == expected)
                    controller.setMuted(true, audibleVolume: 0.5, routeUID: route.uid)
                    await controller.flushForTesting()
                    if usesMute { expected.append(.init(command: 0x8D, value: isInverted ? 2 : 1)) }
                    expected.append(.init(command: 0x62, value: 0))
                    controller.setMuted(false, audibleVolume: 0.5, routeUID: route.uid)
                    await controller.flushForTesting()
                    expected.append(.init(command: 0x62, value: 50))
                    if usesMute { expected.append(.init(command: 0x8D, value: isInverted ? 1 : 2)) }
                    precondition(fake.writes() == expected)
                }
            }
        }
    }
}
