import Foundation

nonisolated struct DiagnosticAudioConfiguration: Codable, Sendable {
    var summary: [String: String] = [:]
    var devices: [DiagnosticConfiguredDevice] = []
    var apps: [DiagnosticConfiguredApp] = []
}

nonisolated struct DiagnosticConfiguredDevice: Codable, Sendable {
    let id: String
    let selection: String
    let direction: String
    let current: Bool
    let transport: UInt32?
    let volume: Double?
    let selectedSourceCount: Int?
}

nonisolated struct DiagnosticConfiguredDestination: Codable, Sendable {
    let device: String
    let selection: String
    let available: Bool
    let selectedSourceCount: Int?
}

nonisolated struct DiagnosticConfiguredApp: Codable, Sendable {
    let id: String
    let instance: String
    let volume: Double
    let muted: Bool
    let appliedGain: Double
    let maximumVolume: Double
    var equalizerEnabled = false
    var equalizerAvailable = false
    var equalizerApplied = false
    var equalizerGains: [Double] = []
    var equalizerToneGains: [Double]?
    var usesSimpleEqualizerControls = false
    var followsSystemOutput = true
    var hasSavedOutputSelection = false
    var routingAvailable = false
    var selectedDestinations: [DiagnosticConfiguredDestination] = []
    // nil follows the system; [] means selected destinations are unresolved/offline.
    var resolvedDestinationDevices: [String]?
}

nonisolated struct DiagnosticConfigurationCapture: Codable, Sendable {
    let id: String
    let phase: String
    let timestamp: Date
    let diagnostic: String?
    var uptimeNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds
    let configuration: DiagnosticAudioConfiguration

    /// One record per item avoids the log's 2048-character field cap silently
    /// truncating a whole application list. The export also contains typed JSON.
    func record(to log: DiagnosticLog) {
        let reference = ["capture": id, "phase": phase, "diagnostic": diagnostic ?? "none"]
        log.record("configuration", "snapshot", fields: configuration.summary.merging(reference) { _, new in new })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for device in configuration.devices {
            if let data = try? encoder.encode(device), let json = String(data: data, encoding: .utf8) {
                log.record("configuration", "device", fields: reference.merging(["configuration": json]) { _, new in new })
            }
        }
        for app in configuration.apps {
            // Destinations are emitted separately, so an unusually long selection
            // cannot truncate EQ or volume information.
            var core = app
            core.selectedDestinations = []
            core.resolvedDestinationDevices = nil
            if let data = try? encoder.encode(core), let json = String(data: data, encoding: .utf8) {
                log.record("configuration", "application", fields: reference.merging(["configuration": json]) { _, new in new })
            }
            for destination in app.selectedDestinations {
                if let data = try? encoder.encode(destination), let json = String(data: data, encoding: .utf8) {
                    log.record("configuration", "destination", fields: reference.merging([
                        "app": app.id, "configuration": json,
                        "resolved": String(app.resolvedDestinationDevices?.contains(destination.device) == true)
                    ]) { _, new in new })
                }
            }
        }
    }
}

/// Names are held only in memory for user review. Device display names and raw
/// model UIDs never enter the attachment, even when a device is selected.
nonisolated struct DiagnosticIdentificationCandidate: Identifiable, Sendable {
    let id: String
    let kind: String
    let displayName: String
    var manufacturer: String?
    var model: String?
    var bundleIdentifier: String?

    func selectedDetail(modelOverride: String?) -> DiagnosticIdentificationDetail {
        DiagnosticIdentificationDetail(id: id, kind: kind,
            appName: kind == "application" ? displayName : nil,
            bundleIdentifier: kind == "application" ? bundleIdentifier : nil,
            manufacturer: kind == "device" ? manufacturer : nil,
            model: kind == "device" ? String((modelOverride ?? model ?? "").prefix(200)) : nil)
    }
}

nonisolated struct DiagnosticIdentificationDetail: Codable, Sendable {
    let id: String
    let kind: String
    let appName: String?
    let bundleIdentifier: String?
    let manufacturer: String?
    let model: String?
}

nonisolated struct DiagnosticIdentificationAttachment: Codable, Sendable {
    let consent: String
    let logSession: String
    let items: [DiagnosticIdentificationDetail]
    static func selected(from candidates: [DiagnosticIdentificationCandidate], ids: Set<String>,
                         modelOverrides: [String: String], logSession: String = DiagnosticLog.shared.session) -> Self? {
        let items = candidates.filter { ids.contains($0.id) }
            .map { $0.selectedDetail(modelOverride: modelOverrides[$0.id]) }
        guard !items.isEmpty else { return nil }
        return Self(consent: "User explicitly selected these items for this export only", logSession: logSession, items: items)
    }
}

nonisolated enum DiagnosticSamplingPolicy {
    static let processInterval: TimeInterval = 0.25
    static let heartbeatInterval: TimeInterval = 0.1
    static let stateInterval: TimeInterval = 1
    static let systemInterval: TimeInterval = 1
    static let discoveryInterval: TimeInterval = 5
    static let maximumDuration: TimeInterval = 300
}
