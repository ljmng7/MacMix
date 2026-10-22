import XCTest
@testable import MacMixStudio

final class AppOutputRoutingTests: XCTestCase {
    @MainActor func testAirPlayReceiverPersistenceAndSharedHALIdentity() throws {
        let domain = "MacMix.AirPlay.Routing.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = AppOutputRoutingStore(defaults: defaults)
        store.updateAccess(true)
        store.setFeatureEnabled(true)
        let living = AppOutputDestination(uid: "airplay", name: "Living Room", dataSourceIDs: [7])
        let bedroom = AppOutputDestination(uid: "airplay", name: "Bedroom", dataSourceIDs: [9])
        let usb = AppOutputDestination(uid: "usb", name: "USB")
        let group = AppOutputDestination(uid: "airplay", name: "Both", dataSourceIDs: [9, 7, 7])
        XCTAssertEqual(group.dataSourceIDs, [7, 9])
        XCTAssertNotEqual(living.id, bedroom.id)
        XCTAssertTrue(living.matches(.init(uid: "airplay", name: "Renamed", dataSourceIDs: [7])))
        XCTAssertFalse(living.matches(bedroom))
        XCTAssertFalse(living.matches(group))
        store.setSelected(true, destination: living, for: "music")
        store.setSelected(true, destination: usb, for: "music")
        XCTAssertEqual(store.resolvedUIDs(for: "music", availableDestinations: [living, usb]), ["airplay", "usb"])
        XCTAssertEqual(store.resolvedUIDs(for: "music", availableDestinations: [bedroom, usb]), ["usb"])
        XCTAssertEqual(store.resolvedUIDs(for: "music", availableDestinations: [group]), [])
        XCTAssertEqual(store.resolvedUIDs(for: "music", availableUIDs: ["airplay", "usb"]), ["usb"])
        let restored = AppOutputRoutingStore(defaults: defaults)
        restored.updateAccess(true)
        restored.setFeatureEnabled(true)
        XCTAssertEqual(restored.destinations(for: "music"), [living, usb])
        XCTAssertEqual(restored.resolvedUIDs(for: "music", availableDestinations: [bedroom]), [])
        XCTAssertEqual(restored.resolvedUIDs(for: "music", availableDestinations: [living]), ["airplay"])
        restored.setSelected(true, destination: group, for: "music")
        XCTAssertEqual(restored.destinations(for: "music"), [usb, group], "One selection per shared HAL device")
        XCTAssertEqual(restored.resolvedUIDs(for: "music", availableDestinations: [group, usb]), ["airplay", "usb"])
        let decoded = try JSONDecoder().decode(AppOutputDestination.self,
            from: Data(#"{"uid":"airplay","name":"Both","dataSourceIDs":[9,7,7]}"#.utf8))
        XCTAssertEqual(decoded, group)
    }

    @MainActor func testLegacyAirPlayPreferenceBindsOnce() {
        let domain = "MacMix.Legacy.AirPlay.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(Data(#"{"music":[{"uid":"airplay","name":"AirPlay"},{"uid":"usb","name":"USB"}]}"#.utf8), forKey: "MacMix.AppOutputRouting.v1")
        let store = AppOutputRoutingStore(defaults: defaults)
        store.updateAccess(true)
        store.setFeatureEnabled(true)
        let living = AppOutputDestination(uid: "airplay", name: "Living", dataSourceIDs: [7])
        let bedroom = AppOutputDestination(uid: "airplay", name: "Bedroom", dataSourceIDs: [9])
        store.bindLegacyAirPlayDestinations([])
        XCTAssertNil(store.destinations(for: "music")[0].dataSourceIDs)
        store.bindLegacyAirPlayDestinations([living])
        store.bindLegacyAirPlayDestinations([bedroom])
        XCTAssertEqual(store.destinations(for: "music")[0], living)
        XCTAssertEqual(AppOutputRoutingStore(defaults: defaults).destinations(for: "music")[0], living)
        XCTAssertEqual(store.resolvedUIDs(for: "music", availableDestinations: [bedroom]), [])
        XCTAssertNil(store.destinations(for: "music")[1].dataSourceIDs)
    }

    @MainActor func testSelectionDisconnectRestartAndAccessLoss() {
        let domain = "MacMix.Routing.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = AppOutputRoutingStore(defaults: defaults)
        let a = AppOutputDestination(uid: "a", name: "USB")
        let b = AppOutputDestination(uid: "b", name: "Display")
        store.setSelected(true, destination: a, for: "music")
        XCTAssertTrue(store.destinations(for: "music").isEmpty)
        store.updateAccess(true)
        store.setFeatureEnabled(true)
        XCTAssertNil(store.resolvedUIDs(for: "music", availableUIDs: ["a", "b"]))
        store.setSelected(true, destination: a, for: "music")
        store.setSelected(true, destination: b, for: "music")
        store.setSelected(true, destination: b, for: "music")
        XCTAssertEqual(store.destinations(for: "music").count, 2)
        XCTAssertEqual(store.resolvedUIDs(for: "music", availableUIDs: ["a", "b"]), ["a", "b"])
        XCTAssertEqual(store.resolvedUIDs(for: "music", availableUIDs: ["b"]), ["b"])
        XCTAssertEqual(store.resolvedUIDs(for: "music", availableUIDs: []), []) // Never fall back to speakers.
        XCTAssertNil(store.resolvedUIDs(for: "browser", availableUIDs: ["a"]))
        let restored = AppOutputRoutingStore(defaults: defaults)
        XCTAssertEqual(restored.destinations(for: "music"), [a, b])
        restored.updateAccess(true)
        restored.setFeatureEnabled(true)
        XCTAssertEqual(restored.resolvedUIDs(for: "music", availableUIDs: ["a", "b"]), ["a", "b"])
        restored.updateAccess(false)
        XCTAssertNil(restored.resolvedUIDs(for: "music", availableUIDs: ["a", "b"]))
        XCTAssertEqual(restored.destinations(for: "music"), [a, b])
        restored.followSystem(for: "music")
        XCTAssertTrue(AppOutputRoutingStore(defaults: defaults).destinations(for: "music").isEmpty)
    }

    @MainActor func testMultiOutputSettingDefaultsOffAndKeepsSavedRoutes() {
        let domain = "MacMix.Routing.Enabled.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let a = AppOutputDestination(uid: "a", name: "USB")
        let fresh = AppOutputRoutingStore(defaults: defaults)
        fresh.updateAccess(true)
        XCTAssertFalse(fresh.isFeatureActive)
        fresh.setSelected(true, destination: a, for: "music")
        XCTAssertTrue(fresh.destinations(for: "music").isEmpty)

        defaults.set(Data(#"{"music":[{"uid":"a","name":"USB"}]}"#.utf8), forKey: "MacMix.AppOutputRouting.v1")
        let upgraded = AppOutputRoutingStore(defaults: defaults)
        upgraded.updateAccess(true)
        XCTAssertTrue(upgraded.isFeatureActive, "Routes saved before the setting existed stay on")
        upgraded.setFeatureEnabled(false)
        XCTAssertNil(upgraded.resolvedUIDs(for: "music", availableUIDs: ["a"]))
        XCTAssertEqual(upgraded.destinations(for: "music"), [a], "Turning the setting off keeps the choices")
        XCTAssertFalse(AppOutputRoutingStore(defaults: defaults).isEnabled)
    }
}
