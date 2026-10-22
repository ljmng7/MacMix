import Foundation
import XCTest
@testable import MacMixStudio

@MainActor
final class InputDeviceLockControllerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "InputDeviceLockControllerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsToDisabled() {
        let harness = Harness(defaults: defaults, currentUID: "built-in")

        XCTAssertFalse(harness.controller.isEnabled)
        XCTAssertNil(defaults.string(forKey: InputDeviceLockPreference.deviceUID))
        XCTAssertTrue(harness.selections.isEmpty)
    }

    func testEnablingCapturesCurrentInputDevice() {
        let harness = Harness(defaults: defaults, currentUID: "built-in")
        harness.controller.updateProAccess(true)

        harness.controller.isEnabled = true

        XCTAssertEqual(
            defaults.string(forKey: InputDeviceLockPreference.deviceUID),
            "built-in"
        )
        XCTAssertTrue(harness.selections.isEmpty)
    }

    func testRestoresLockedDeviceAfterSystemSwitch() {
        let harness = Harness(defaults: defaults, currentUID: "built-in")
        harness.controller.updateProAccess(true)
        harness.controller.isEnabled = true

        harness.currentUID = "new-microphone"
        harness.availableUIDs = ["built-in", "new-microphone"]
        harness.controller.inputDevicesDidChange()

        XCTAssertEqual(harness.selections, ["built-in"])
    }

    func testUnavailableDeviceAdoptsFallbackAndDoesNotSwitchBack() {
        let harness = Harness(defaults: defaults, currentUID: "usb-microphone")
        harness.availableUIDs = ["usb-microphone", "built-in"]
        harness.controller.updateProAccess(true)
        harness.controller.isEnabled = true

        harness.currentUID = "built-in"
        harness.availableUIDs = ["built-in"]
        harness.controller.inputDevicesDidChange()

        XCTAssertEqual(
            defaults.string(forKey: InputDeviceLockPreference.deviceUID),
            "built-in"
        )

        harness.availableUIDs = ["built-in", "usb-microphone"]
        harness.controller.inputDevicesDidChange()

        XCTAssertTrue(harness.selections.isEmpty)
    }

    func testUserSelectionBecomesNewLockedDevice() {
        let harness = Harness(defaults: defaults, currentUID: "built-in")
        harness.availableUIDs = ["built-in", "usb-microphone"]
        harness.controller.updateProAccess(true)
        harness.controller.isEnabled = true

        harness.controller.userSelectedDevice(uid: "usb-microphone")

        XCTAssertEqual(
            defaults.string(forKey: InputDeviceLockPreference.deviceUID),
            "usb-microphone"
        )
    }

    func testDoesNotEnforceWithoutProAccess() {
        defaults.set(true, forKey: InputDeviceLockPreference.isEnabled)
        defaults.set("built-in", forKey: InputDeviceLockPreference.deviceUID)
        let harness = Harness(defaults: defaults, currentUID: "new-microphone")
        harness.availableUIDs = ["built-in", "new-microphone"]

        harness.controller.inputDevicesDidChange()

        XCTAssertTrue(harness.selections.isEmpty)
    }
}

@MainActor
private final class Harness {
    var currentUID: String?
    var availableUIDs: [String]
    var selections: [String] = []
    private(set) var controller: InputDeviceLockController!

    init(defaults: UserDefaults, currentUID: String?) {
        self.currentUID = currentUID
        availableUIDs = currentUID.map { [$0] } ?? []
        controller = InputDeviceLockController(
            defaults: defaults,
            currentDeviceUID: { [weak self] in self?.currentUID },
            availableDeviceUIDs: { [weak self] in self?.availableUIDs ?? [] },
            selectDevice: { [weak self] uid in self?.selections.append(uid) }
        )
    }
}
