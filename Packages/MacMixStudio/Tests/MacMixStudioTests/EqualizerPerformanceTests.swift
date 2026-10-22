import AppKit
import Observation
import XCTest
@testable import MacMixStudio

private final class ObservationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
@MainActor private final class DragEvents {
    var submitted = 0
    var delivered: [Int] = []
}

final class EqualizerPerformanceTests: XCTestCase {
    @MainActor func testBurstKeepsLastValueAndMouseUpFlushesExactlyOnce() {
        let edits = EqualizerEditCoalescer()
        var delivered: [Int] = []
        for value in 0..<1000 { edits.submit { delivered.append(value) } }
        XCTAssertTrue(delivered.isEmpty)
        edits.flush()
        XCTAssertEqual(delivered, [999])
        edits.flush()
        XCTAssertEqual(delivered, [999])
        edits.submit { delivered.append(1000) }
        edits.cancel()
        edits.flush()
        XCTAssertEqual(delivered, [999])
    }

    @MainActor func testSustainedTrackingModeInputIsCoalescedWithoutLosingFinalValue() {
        // Exercise the same run-loop mode used by a held NSSlider drag. This is
        // a deterministic input-load test, not a claim about real-device frame time.
        CFRunLoopAddCommonMode(CFRunLoopGetMain(), CFRunLoopMode(rawValue: RunLoop.Mode.eventTracking.rawValue as CFString))
        let edits = EqualizerEditCoalescer()
        let events = DragEvents()
        let source = Timer(timeInterval: 0.002, repeats: true) { _ in
            MainActor.assumeIsolated {
                events.submitted += 1
                let value = events.submitted
                edits.submit { events.delivered.append(value) }
            }
        }
        RunLoop.main.add(source, forMode: .eventTracking)
        let start = Date()
        let deadline = start.addingTimeInterval(0.5)
        while Date() < deadline { _ = RunLoop.main.run(mode: .eventTracking, before: deadline) }
        source.invalidate()
        edits.flush() // Native mouse-up follows this same path.
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertGreaterThan(events.submitted, 40)
        XCTAssertGreaterThan(events.delivered.count, 2)
        XCTAssertLessThanOrEqual(events.delivered.count, Int(ceil(elapsed / 0.016)) + 2)
        XCTAssertEqual(events.delivered.last, events.submitted)
        print("EQ tracking-mode load: \(events.submitted) inputs -> \(events.delivered.count) deliveries in \(elapsed)s; final value retained")
    }

    @MainActor func testOtherAppsDoNotInvalidateAndBurstPersistenceKeepsFinalGain() {
        let domain = "MacMix.EQ.PerformanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = AppEqualizerStore(defaults: defaults)
        store.updateAccess(true)
        store.setFeatureEnabled(true)
        let edited = ObservationCounter(), other = ObservationCounter(), presets = ObservationCounter()
        let volumeGate = ObservationCounter()
        withObservationTracking { _ = store.isActive(for: "a") } onChange: { volumeGate.increment() }
        withObservationTracking { _ = store.configuration(for: "a").gains } onChange: { edited.increment() }
        withObservationTracking { _ = store.configuration(for: "b").gains } onChange: { other.increment() }
        withObservationTracking { _ = store.presets } onChange: { presets.increment() }
        for step in 1...1000 {
            var value = store.configuration(for: "a")
            value.setBand(5, gain: Double(step) / 100)
            store.set(value, for: "a")
        }
        XCTAssertEqual(edited.value, 1)
        XCTAssertEqual(other.value, 0)
        XCTAssertEqual(presets.value, 0)
        XCTAssertEqual(volumeGate.value, 0)
        XCTAssertNil(defaults.data(forKey: "MacMix.AppEqualizer.Configurations.v1"))
        store.flush()
        let restored = AppEqualizerStore(defaults: defaults)
        XCTAssertEqual(restored.configuration(for: "a").gains[5], 10)
        XCTAssertNil(defaults.data(forKey: "MacMix.AppEqualizer.Presets.v1"))
    }
}
