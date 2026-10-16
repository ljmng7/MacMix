import Foundation

@main struct AudioProcessIdentityCacheTests {
    @MainActor static func main() {
        let cache = AudioProcessIdentityCache<String>(lifetime: 10)
        var resolutions = 0
        for tick in 0..<1000 {
            let now = Double(tick) * 0.01
            if cache.value(for: 1, pid: 10, bundleID: "music", now: now) == nil {
                resolutions += 1
                cache.insert("Music", for: 1, pid: 10, bundleID: "music", now: now)
            }
        }
        precondition(resolutions == 1)
        precondition(cache.value(for: 1, pid: 10, bundleID: "music", now: 10) == nil)
        cache.insert("Music", for: 1, pid: 10, bundleID: "music", now: 10)
        precondition(cache.value(for: 1, pid: 11, bundleID: "music", now: 11) == nil)
        cache.insert("New owner", for: 1, pid: 11, bundleID: "music", now: 11)
        precondition(cache.value(for: 1, pid: 11, bundleID: "browser", now: 12) == nil)
        cache.insert("Browser", for: 2, pid: 20, bundleID: "browser", now: 12)
        cache.retain(objectIDs: [])
        precondition(cache.value(for: 2, pid: 20, bundleID: "browser", now: 12) == nil)
        print("Audio identity cache: 1,000 stable lookups -> 1 resolution; expiry, PID reuse, bundle change and removal passed.")
    }
}
