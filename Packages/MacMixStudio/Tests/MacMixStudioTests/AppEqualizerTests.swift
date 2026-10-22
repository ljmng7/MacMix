import XCTest
@testable import MacMixStudio

final class AppEqualizerTests: XCTestCase {
    func testManualEditAlwaysBecomesCustomEvenWhenReturningToFlat() {
        var value = EqualizerConfiguration()
        XCTAssertEqual(value.presetID, "flat")
        XCTAssertFalse(value.isEnabled)
        value.setBand(4, gain: 3)
        value.setBand(4, gain: 0)
        XCTAssertEqual(value.presetID, "custom")
        XCTAssertEqual(value.normalizedGains, Array(repeating: 0, count: 10))
    }
    func testSwitchingPresentationPreservesDetailedCurve() {
        var value = EqualizerConfiguration()
        value.gains = [-3, 2, 6, 0, -1, 4, 2, -2, 5, 1]
        let before = value.gains
        value.usesSimpleControls = false
        value.usesSimpleControls = true
        XCTAssertEqual(value.gains, before)
        value.setSimpleGain(0, gain: 12)
        XCTAssertEqual(value.normalizedToneGains, [12, 1.25, 4.0 / 3.0])
        let tones = value.normalizedToneGains
        let fitted = value.gains
        value.usesSimpleControls = false
        XCTAssertEqual(value.normalizedToneGains, tones)
        XCTAssertEqual(value.gains, fitted)
        value.setBand(5, gain: 2)
        XCTAssertNil(value.normalizedToneGains)
        XCTAssertEqual(value.gains[4], fitted[4])
    }
    func testInvalidAndExtremeBandsAreSanitized() {
        var value = EqualizerConfiguration()
        value.gains = [.nan, .infinity, -20, 20]
        XCTAssertEqual(value.normalizedGains, [0,0,-12,12,0,0,0,0,0,0])
        value.setBand(15, gain: 8)
        XCTAssertEqual(value.gains.count, 4)
    }
    @MainActor func testPresetsPersistAcrossAppsWithoutSharingAppState() {
        let domain = "MacMix.EQ.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = AppEqualizerStore(defaults: defaults)
        var config = EqualizerConfiguration()
        config.isEnabled = true
        config.setBand(5, gain: 4)
        store.set(config, for: "app.a")
        XCTAssertFalse(store.isActive(for: "app.a"))
        store.updateAccess(true)
        store.setFeatureEnabled(true)
        XCTAssertTrue(store.isActive(for: "app.a"))
        XCTAssertFalse(store.isActive(for: "app.b"))
        XCTAssertFalse(store.savePreset(name: "  ", for: "app.a"))
        XCTAssertTrue(store.savePreset(name: " My voice ", for: "app.a"))
        let restored = AppEqualizerStore(defaults: defaults)
        XCTAssertEqual(restored.presets.first?.name, "My voice")
        XCTAssertEqual(restored.configuration(for: "app.a").normalizedGains[5], 4)
        XCTAssertEqual(restored.configuration(for: "app.b").presetID, "flat")
        XCTAssertFalse(restored.hasAccess)
        let presetID = restored.presets[0].id
        restored.deletePreset(presetID)
        XCTAssertEqual(restored.configuration(for: "app.a").presetID, "custom")
        XCTAssertEqual(restored.configuration(for: "app.a").normalizedGains[5], 4)
    }
    func testLegacyConfigurationStillDecodes() throws {
        let data = Data(#"{"isEnabled":true,"gains":[0,0,0,6,6,6,6,0,0,0],"presetID":"custom","usesSimpleControls":true}"#.utf8)
        let value = try JSONDecoder().decode(EqualizerConfiguration.self, from: data)
        XCTAssertNil(value.toneGains)
        XCTAssertEqual(value.simpleGain(1), 6)
    }
    @MainActor func testTonePresetRetainsItsActualFilters() {
        let domain = "MacMix.EQ.ToneTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = AppEqualizerStore(defaults: defaults)
        var value = EqualizerConfiguration()
        value.isEnabled = true
        value.setSimpleGain(1, gain: 6)
        store.set(value, for: "app")
        XCTAssertTrue(store.savePreset(name: "Voice", for: "app"))
        let restored = AppEqualizerStore(defaults: defaults)
        XCTAssertEqual(restored.presets[0].toneGains, [0,6,0])
        XCTAssertEqual(restored.configuration(for: "app").toneGains, [0,6,0])
    }

    @MainActor func testUserPresetDraftSurvivesRestartButSwitchingReloadsSavedCurve() {
        let domain = "MacMix.EQ.DraftTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = AppEqualizerStore(defaults: defaults)
        var value = EqualizerConfiguration()
        value.setBand(2, gain: 3)
        store.set(value, for: "app")
        XCTAssertTrue(store.savePreset(name: "Original", for: "app"))
        let original = store.presets[0]
        value = store.configuration(for: "app")
        value.setBand(2, gain: 7)
        XCTAssertEqual(value.presetID, original.id)
        store.set(value, for: "app")
        store.flush()
        let restored = AppEqualizerStore(defaults: defaults)
        XCTAssertEqual(restored.configuration(for: "app").presetID, original.id)
        XCTAssertEqual(restored.configuration(for: "app").gains[2], 7)
        XCTAssertEqual(restored.presets[0], original)
        value = restored.configuration(for: "app")
        value.applyPreset(EqualizerPreset.builtIn[1])
        restored.set(value, for: "app")
        value.applyPreset(restored.presets[0])
        restored.set(value, for: "app")
        XCTAssertEqual(restored.configuration(for: "app").gains, original.gains)
    }

    @MainActor func testOverwriteAndSaveAsNewKeepSeparatePresetIdentities() {
        let domain = "MacMix.EQ.OverwriteTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = AppEqualizerStore(defaults: defaults)
        XCTAssertFalse(store.overwritePreset(for: "app"))
        var value = EqualizerConfiguration()
        value.setSimpleGain(1, gain: 2)
        store.set(value, for: "app")
        XCTAssertTrue(store.savePreset(name: "Original", for: "app"))
        let original = store.presets[0]
        value = store.configuration(for: "app")
        value.setSimpleGain(1, gain: 6)
        XCTAssertEqual(value.presetID, original.id)
        store.set(value, for: "app")
        XCTAssertTrue(store.savePreset(name: "New", for: "app"))
        XCTAssertEqual(store.presets[0], original)
        XCTAssertNotEqual(store.presets[1].id, original.id)
        XCTAssertEqual(store.presets[1].toneGains, [0, 6, 0])
        value.presetID = original.id
        store.set(value, for: "app")
        XCTAssertTrue(store.overwritePreset(for: "app"))
        let restored = AppEqualizerStore(defaults: defaults)
        XCTAssertEqual(restored.presets.count, 2)
        XCTAssertEqual(restored.presets[0].id, original.id)
        XCTAssertEqual(restored.presets[0].name, original.name)
        XCTAssertEqual(restored.presets[0].toneGains, [0, 6, 0])
        restored.deletePreset(original.id)
        XCTAssertEqual(restored.configuration(for: "app").presetID, "custom")
        XCTAssertEqual(restored.configuration(for: "app").toneGains, [0, 6, 0])
    }

}
