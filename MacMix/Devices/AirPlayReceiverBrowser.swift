//
//  AirPlayReceiverBrowser.swift
//  MacMix
//

import Foundation
import Network
import SystemConfiguration

// Core Audio publishes no AirPlay output until a receiver is connected, so idle
// receivers such as a HomePod are found through Bonjour instead. Browses only
// while an audio interface is visible; without Local Network access the list
// simply stays empty.
@MainActor
final class AirPlayReceiverBrowser {
    var onChange: (() -> Void)?
    private(set) var receivers: [DiscoveredAirPlayReceiver] = []

    private var browser: NWBrowser?
    private var latestReceivers: [DiscoveredAirPlayReceiver] = []
    private var removalTask: Task<Void, Never>?
    // A new browser's first batch can omit services that follow milliseconds later.
    private let removalDelay: Duration = .seconds(5)

    func setActive(_ active: Bool) {
        guard active != (browser != nil) else { return }
        active ? start() : stop()
    }

    private func start() {
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_airplay._tcp", domain: nil), using: .tcp)
        browser.stateUpdateHandler = { state in
            guard case let .failed(error) = state else { return }
            DiagnosticLog.shared.record("route", "airplay_browse_failed", level: "error",
                fields: ["error": String(describing: error)])
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let advertisements = results.compactMap(Self.advertisement)
            MainActor.assumeIsolated { self?.update(advertisements) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    private func stop() {
        browser?.cancel()
        browser = nil
        removalTask?.cancel()
        removalTask = nil
    }

    private func update(_ advertisements: [AirPlayReceiverAdvertisement]) {
        let computerName = SCDynamicStoreCopyComputerName(nil, nil) as String?
        latestReceivers = DiscoveredAirPlayReceiver.receivers(from: advertisements, excludingName: computerName)
        let retained = DiscoveredAirPlayReceiver.retaining(receivers, in: latestReceivers)
        publish(retained)
        removalTask?.cancel()
        removalTask = nil
        guard retained != latestReceivers else { return }
        removalTask = Task { [weak self, removalDelay] in
            try? await Task.sleep(for: removalDelay)
            guard !Task.isCancelled, let self else { return }
            publish(latestReceivers)
        }
    }

    private func publish(_ receivers: [DiscoveredAirPlayReceiver]) {
        guard receivers != self.receivers else { return }
        self.receivers = receivers
        onChange?()
    }

    private nonisolated static func advertisement(_ result: NWBrowser.Result) -> AirPlayReceiverAdvertisement? {
        guard case let .service(name, _, _, _) = result.endpoint else { return nil }
        guard case let .bonjour(record) = result.metadata else {
            return AirPlayReceiverAdvertisement(name: name, txt: [:])
        }
        return AirPlayReceiverAdvertisement(name: name, txt: record.dictionary)
    }
}
