import AppKit
import Network
import Observation

// macOS has no API to read Local Network access. A Bonjour browse reports
// PolicyDenied once the user has turned it off; anything else counts as allowed,
// and an undecided user is asked by the system as soon as MacMix browses.
@MainActor
@Observable
final class LocalNetworkPermissionModel {
    private(set) var isAuthorized = true

    @ObservationIgnored private var browser: NWBrowser?

    func refresh() {
        browser?.cancel()
        let browser = NWBrowser(for: .bonjour(type: "_airplay._tcp", domain: nil), using: .tcp)
        browser.stateUpdateHandler = { [weak self] state in
            let denied: Bool?
            switch state {
            case .ready: denied = false
            case let .waiting(error), let .failed(error): denied = Self.isPolicyDenied(error)
            default: denied = nil
            }
            guard let denied else { return }
            MainActor.assumeIsolated { self?.isAuthorized = !denied }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }

    func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") else { return }
        NSWorkspace.shared.open(url)
    }

    private nonisolated static func isPolicyDenied(_ error: NWError) -> Bool {
        guard case let .dns(code) = error else { return false }
        return code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied)
    }
}
