import XCTest
@testable import MacMixStudio

final class EqualizerFeaturePolicyTests: XCTestCase {
    @MainActor func testBoostRestoresBothOriginalStates() {
        for original in [false, true] {
            let domain = "MacMix.EQ.Policy.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: domain)!
            defer { defaults.removePersistentDomain(forName: domain) }
            defaults.set(original, forKey: "MacMix.Enables200PercentVolume")
            let store = AppEqualizerStore(defaults: defaults)
            XCTAssertFalse(store.isEnabled)
            store.updateAccess(true)
            store.setFeatureEnabled(true)
            XCTAssertTrue(store.isFeatureActive)
            XCTAssertFalse(defaults.bool(forKey: "MacMix.Enables200PercentVolume"))
            store.setFeatureEnabled(true) // Must not overwrite the saved preference with false.
            store.setFeatureEnabled(false)
            XCTAssertEqual(defaults.bool(forKey: "MacMix.Enables200PercentVolume"), original)
        }
    }
    @MainActor func testRestartAndAccessLossPreserveBoostPreference() {
        let domain = "MacMix.EQ.Policy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(true, forKey: "MacMix.Enables200PercentVolume")
        let original = AppEqualizerStore(defaults: defaults)
        original.updateAccess(true)
        original.setFeatureEnabled(true)
        let restarted = AppEqualizerStore(defaults: defaults)
        restarted.updateAccess(true)
        XCTAssertTrue(restarted.isFeatureActive)
        XCTAssertFalse(defaults.bool(forKey: "MacMix.Enables200PercentVolume"))
        restarted.updateAccess(false)
        XCTAssertFalse(restarted.isFeatureActive)
        XCTAssertTrue(defaults.bool(forKey: "MacMix.Enables200PercentVolume"))
        restarted.updateAccess(true)
        XCTAssertFalse(defaults.bool(forKey: "MacMix.Enables200PercentVolume"))
        restarted.setFeatureEnabled(false)
        XCTAssertTrue(defaults.bool(forKey: "MacMix.Enables200PercentVolume"))
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
