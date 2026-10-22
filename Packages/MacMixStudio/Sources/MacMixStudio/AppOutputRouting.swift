import Foundation
import Observation

public struct AppOutputDestination: Codable, Equatable, Identifiable, Sendable {
    public let uid: String
    public let name: String
    public let dataSourceIDs: [UInt32]?
    public var id: String {
        guard let dataSourceIDs else { return uid }
        return "\(uid)#airplay-sources:\(dataSourceIDs.map(String.init).joined(separator: ","))"
    }

    public init(uid: String, name: String, dataSourceIDs: [UInt32]? = nil) {
        self.uid = uid
        self.name = name
        self.dataSourceIDs = dataSourceIDs.map { Array(Set($0)).sorted() }
    }

    public func matches(_ available: Self) -> Bool {
        uid == available.uid && dataSourceIDs == available.dataSourceIDs
    }

    private enum CodingKeys: String, CodingKey { case uid, name, dataSourceIDs }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(uid: try values.decode(String.self, forKey: .uid),
            name: try values.decode(String.self, forKey: .name),
            dataSourceIDs: try values.decodeIfPresent([UInt32].self, forKey: .dataSourceIDs))
    }
}

/// An absent preference follows the system. Saved destinations remain selected
/// while disconnected; an empty resolved list deliberately means silent output.
@MainActor @Observable
public final class AppOutputRoutingStore {
    public private(set) var selections: [String: [AppOutputDestination]]
    public private(set) var hasAccess = false
    /// The Advanced setting that turns multi-device output on.
    public private(set) var isEnabled: Bool
    public var isFeatureActive: Bool { hasAccess && isEnabled }
    public var isApplying = false
    public var applyFailed = false
    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "MacMix.AppOutputRouting.v1"
    private static let enabledKey = "MacMix.AppOutputRouting.Enabled"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoded = defaults.data(forKey: Self.key).flatMap {
            try? JSONDecoder().decode([String: [AppOutputDestination]].self, from: $0)
        } ?? [:]
        let saved = decoded.mapValues { devices in
            var seen = Set<String>()
            return devices.filter { !$0.uid.isEmpty && seen.insert($0.uid).inserted }
        }.filter { !$0.value.isEmpty }
        selections = saved
        // Off by default, but routes saved before the setting existed keep working.
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? !saved.isEmpty
    }

    public func updateAccess(_ enabled: Bool) { hasAccess = enabled }

    public func setFeatureEnabled(_ enabled: Bool) {
        guard !enabled || hasAccess else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
    }

    public func destinations(for bundleID: String) -> [AppOutputDestination] {
        selections[bundleID] ?? []
    }

    public func resolvedUIDs(for bundleID: String, availableUIDs: Set<String>) -> [String]? {
        guard isFeatureActive, let devices = selections[bundleID] else { return nil }
        // UID-only callers cannot validate a pinned AirPlay receiver.
        return devices.filter { $0.dataSourceIDs == nil && availableUIDs.contains($0.uid) }.map(\.uid).sorted()
    }

    public func resolvedUIDs(for bundleID: String, availableDestinations: [AppOutputDestination]) -> [String]? {
        guard isFeatureActive, let devices = selections[bundleID] else { return nil }
        return devices.filter { saved in
            availableDestinations.contains { saved.matches($0) }
        }.map(\.uid).sorted()
    }

    /// Upgrade existing UID-only AirPlay preferences once a connected selection
    /// can be read. Subsequent receiver changes must not silently retarget them.
    public func bindLegacyAirPlayDestinations(_ available: [AppOutputDestination]) {
        var changed = false
        for (bundleID, devices) in selections {
            selections[bundleID] = devices.map { saved in
                guard saved.dataSourceIDs == nil,
                      let connected = available.first(where: {
                          $0.uid == saved.uid && $0.dataSourceIDs?.isEmpty == false
                      }) else { return saved }
                changed = true
                return connected
            }
        }
        if changed { save() }
    }

    public func followSystem(for bundleID: String) {
        // Returning to the Free behavior is always allowed.
        selections.removeValue(forKey: bundleID)
        save()
    }

    public func setSelected(_ selected: Bool, destination: AppOutputDestination, for bundleID: String) {
        guard isFeatureActive, !destination.uid.isEmpty else { return }
        var devices = destinations(for: bundleID).filter { $0.uid != destination.uid }
        if selected { devices.append(destination) }
        selections[bundleID] = devices.isEmpty ? nil : devices
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(selections) { defaults.set(data, forKey: Self.key) }
    }
}

