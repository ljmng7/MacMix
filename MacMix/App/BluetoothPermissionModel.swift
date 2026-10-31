import AppKit
import CoreBluetooth
import Observation

@MainActor
@Observable
final class BluetoothPermissionModel: NSObject, CBCentralManagerDelegate {
    private(set) var isRequesting = false
    private(set) var isAuthorized = CBManager.authorization == .allowedAlways

    private var centralManager: CBCentralManager?
    private var authorizationContinuation: CheckedContinuation<Void, Never>?

    func refresh() {
        isAuthorized = CBManager.authorization == .allowedAlways
    }

    /// Shows the system prompt when the user has not decided yet; once they
    /// have denied access, macOS no longer prompts, so open the privacy pane.
    func requestOrOpenSettings() async {
        guard CBManager.authorization != .notDetermined else {
            await requestIfNeeded()
            return
        }

        refresh()
        guard !isAuthorized,
              let url = URL(
                  string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
              ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func requestIfNeeded() async {
        guard !isRequesting,
              CBManager.authorization == .notDetermined else {
            return
        }

        isRequesting = true
        defer {
            authorizationContinuation = nil
            centralManager = nil
            isRequesting = false
            refresh()
        }

        let focusCycle = ApplicationFocusCycleWaiter()

        await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            centralManager = CBCentralManager(delegate: self, queue: .main)
            resumeAuthorizationWaitIfResolved()
        }

        await focusCycle.waitForReturnOrNoPrompt()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        resumeAuthorizationWaitIfResolved()
    }

    private func resumeAuthorizationWaitIfResolved() {
        guard CBManager.authorization != .notDetermined,
              let authorizationContinuation else {
            return
        }

        self.authorizationContinuation = nil
        authorizationContinuation.resume()
    }
}
