import XCTest
@testable import MacMixStudio

final class EqualizerFeaturePolicyTests: XCTestCase {
    @MainActor func testCustomEQLeavesBoostPreferenceAlone() {
        for original in [false, true] {
            let domain = "MacMix.EQ.Policy.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: domain)!
            defer { defaults.removePersistentDomain(forName: domain) }
            defaults.set(original, forKey: "MacMix.Enables200PercentVolume")
            let store = AppEqualizerStore(defaults: defaults)
            store.updateAccess(true)
            store.setFeatureEnabled(true)
            XCTAssertTrue(store.isFeatureActive)
            XCTAssertEqual(defaults.bool(forKey: "MacMix.Enables200PercentVolume"), original)
            store.updateAccess(false)
            store.setFeatureEnabled(false)
            XCTAssertEqual(defaults.bool(forKey: "MacMix.Enables200PercentVolume"), original)
        }
    }
    @MainActor func testLaunchRestoresBoostTurnedOffByOlderVersions() {
        for saved in [false, true] {
            let domain = "MacMix.EQ.Policy.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: domain)!
            defer { defaults.removePersistentDomain(forName: domain) }
            // Older versions turned boost off while Custom EQ was on and kept the choice here.
            defaults.set(false, forKey: "MacMix.Enables200PercentVolume")
            defaults.set(saved, forKey: "MacMix.CustomEqualizer.PreviousBoost")
            defaults.set(true, forKey: "MacMix.CustomEqualizer.Enabled")
            let store = AppEqualizerStore(defaults: defaults)
            XCTAssertTrue(store.isEnabled)
            XCTAssertEqual(defaults.bool(forKey: "MacMix.Enables200PercentVolume"), saved)
            XCTAssertNil(defaults.object(forKey: "MacMix.CustomEqualizer.PreviousBoost"))
        }
    }
    @MainActor func testFeatureGateDoesNotDeleteAppCurves() {
        let domain = "MacMix.EQ.Policy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = AppEqualizerStore(defaults: defaults)
        store.setFeatureEnabled(true)
        XCTAssertFalse(store.isEnabled) // Studio is required.
        store.updateAccess(true)
        var curve = EqualizerConfiguration()
        curve.isEnabled = true
        curve.setBand(5, gain: 4)
        store.set(curve, for: "app")
        XCTAssertFalse(store.isActive(for: "app"))
        store.setFeatureEnabled(true)
        XCTAssertTrue(store.isActive(for: "app"))
        store.setFeatureEnabled(false)
        XCTAssertFalse(store.isActive(for: "app"))
        XCTAssertEqual(store.configuration(for: "app").gains[5], 4)
        store.setFeatureEnabled(true)
        XCTAssertTrue(store.isActive(for: "app"))
    }
}
