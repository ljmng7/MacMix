import Observation
import SwiftUI

/// The single source of Studio entitlement. Features read `hasStudioAccess` from the
/// provider or from the `hasStudioAccess` environment value; they never check licenses.
@MainActor
protocol EntitlementProvider: AnyObject, Observable {
    var hasStudioAccess: Bool { get }

    /// Resolves the current entitlement, using a license service when the build has one.
    func refreshEntitlement() async
}

/// Builds without a licensing module have every Studio feature unlocked.
@MainActor
@Observable
final class UnlockedEntitlementProvider: EntitlementProvider {
    let hasStudioAccess = true

    func refreshEntitlement() async {}
}

private struct StudioAccessEnvironmentKey: EnvironmentKey {
    nonisolated static let defaultValue = false
}

extension EnvironmentValues {
    var hasStudioAccess: Bool {
        get { self[StudioAccessEnvironmentKey.self] }
        set { self[StudioAccessEnvironmentKey.self] = newValue }
    }
}
