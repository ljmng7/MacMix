// Compiled alongside the production scheduler by run-device-volume-tests.sh.
// Invalid HAL identity guarantees this regression cannot change real volume.
struct AudioDevice {
    let id: AudioObjectID
    let uid: String
    let volume: Double?
}
nonisolated enum AudioDeviceDirection { case output }
nonisolated struct CoreAudioHardware {
    func setVolume(_ value: Double, for id: AudioObjectID, direction: AudioDeviceDirection) -> Bool {
        fatalError("A stale device identity must never reach a write")
    }
    func isMuted(for id: AudioObjectID, direction: AudioDeviceDirection) -> Bool? { false }
    func setMuted(_ muted: Bool, for id: AudioObjectID, direction: AudioDeviceDirection) {}
    func volume(for id: AudioObjectID, direction: AudioDeviceDirection) -> Double? { nil }
}
nonisolated final class VolumeReadbackLog: @unchecked Sendable {
    private let lock = NSLock()
    private var revisions: [UInt64] = []
    func append(_ value: Double?, revision: UInt64) {
        precondition(!Thread.isMainThread, "HAL work must run off the main thread")
        precondition(value == nil, "Invalid device must not yield a volume")
        lock.lock(); defer { lock.unlock() }
        revisions.append(revision)
    }
    func snapshot() -> [UInt64] {
        lock.lock(); defer { lock.unlock() }
        return revisions
    }
}
@main struct RoutedDeviceVolumeSchedulerTests {
    static func main() async throws {
        let log = VolumeReadbackLog()
        let worker = RoutedDeviceVolumeWorker(deviceID: .max, uid: "missing-test-device") {
            log.append($0, revision: $1)
        }
        for revision in 1...500 { worker.submit(Double(revision) / 500, revision: UInt64(revision)) }
        try await Task.sleep(for: .milliseconds(150))
        let first = log.snapshot()
        precondition(first.last == 500, "First burst lost its final edit")
        precondition(first.count <= 2, "Slider edits were not coalesced")
        for revision in 501...1000 { worker.submit(Double(1000 - revision) / 500, revision: UInt64(revision)) }
        try await Task.sleep(for: .milliseconds(150))
        let all = log.snapshot()
        precondition(all.last == 1000, "Second burst lost its final edit")
        precondition(all.count - first.count <= 2, "Second burst was not coalesced")
        print("Device volume scheduler: 1,000 edits -> \(all.count) background batches; final revisions retained; stale device writes blocked.")
        withExtendedLifetime(worker) {}
    }
}
