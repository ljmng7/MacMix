import Foundation

/// Main-thread metadata cache. Audio process IDs and PID/bundle identity are
/// checked on every discovery; only expensive AppKit owner/name/icon resolution
/// is cached. A bounded lifetime also catches changes in parent responsibility.
@MainActor
final class AudioProcessIdentityCache<Value> {
    private struct Entry {
        let pid: Int32
        let bundleID: String?
        let value: Value
        let expiresAt: TimeInterval
    }
    private var entries: [UInt32: Entry] = [:]
    private let lifetime: TimeInterval

    init(lifetime: TimeInterval = 10) { self.lifetime = lifetime }

    func value(for objectID: UInt32, pid: Int32, bundleID: String?, now: TimeInterval) -> Value? {
        guard let entry = entries[objectID] else { return nil }
        guard entry.pid == pid, entry.bundleID == bundleID, now < entry.expiresAt else {
            entries.removeValue(forKey: objectID)
            return nil
        }
        return entry.value
    }

    func insert(_ value: Value, for objectID: UInt32, pid: Int32, bundleID: String?, now: TimeInterval) {
        entries[objectID] = Entry(pid: pid, bundleID: bundleID, value: value, expiresAt: now + lifetime)
    }

    func retain(objectIDs: Set<UInt32>) {
        for id in entries.keys where !objectIDs.contains(id) { entries.removeValue(forKey: id) }
    }
}
