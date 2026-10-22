import SwiftUI

/// Where a build that sells Studio may show its own Studio UI.
enum StudioPromptPlacement {
    /// Above the title of the General settings section.
    case settingsHeader
    /// Above the title of the current-apps section on the Blacklist page.
    case blacklistHeader
    /// Below the Blacklist section.
    case blacklistFooter
    /// The Scenes page while Studio is unavailable.
    case scenesPage
    /// Next to the title of a setting that needs Studio.
    case requirementBadge
}

/// What an edition's own windows need from the app.
struct EditionSceneContext {
    /// Nil until the app has finished launching.
    let systemAudioPermissionStatus: SystemAudioPermissionStatusModel?
    let showControlPanel: () -> Void
    let restoreActivationPolicy: () -> Void
}

/// Everything that differs between the open-source build and the official build.
///
/// The open-source edition unlocks every Studio feature and adds nothing else. The
/// official edition adds licensing, purchases, onboarding and updates. Business code
/// reads the entitlement only through `entitlements` and never checks the edition.
@MainActor
protocol AppEdition: AnyObject {
    associatedtype Scenes: Scene

    static var shared: Self { get }

    var entitlements: any EntitlementProvider { get }

    // MARK: Launch

    /// When true, the app waits for `authorizeLaunch` before creating its audio runtime.
    var requiresLaunchAuthorization: Bool { get }
    func authorizeLaunch(onAuthorized: @escaping @MainActor () -> Void) async
    /// Shown when the user opens the app before launch authorization has finished.
    func showLaunchAuthorization()
    /// Called once the audio runtime exists.
    func runtimeDidStart()
    /// Called whenever a primary window or the menu bar panel appears.
    func interfaceDidAppear()
    func entitlementDidChange(from previous: Bool, to current: Bool)

    /// A window to show before the control panel, such as a first-run introduction.
    var pendingIntroWindowID: String? { get }

    // MARK: Interface

    @SceneBuilder func scenes(_ context: EditionSceneContext) -> Scenes
    func appMenuItems() -> AnyView?
    func controlPanel(_ content: AnyView) -> AnyView
    func studioPrompt(_ placement: StudioPromptPlacement) -> AnyView?
    func aboutHeader() -> AnyView?
    func aboutSettingsRows() -> AnyView?
    func aboutToolbarButton() -> AnyView?
    func aboutFooterLinks() -> AnyView?
    /// Extra terms that find the About page in control panel search.
    var aboutSearchLabels: [LocalizedStringResource] { get }
    var displayVersion: String? { get }
    /// Reported in diagnostics, so feedback from self-built copies can be told apart.
    var releaseChannel: String { get }
}


@MainActor
final class OpenSourceEdition: AppEdition {
    static let shared = OpenSourceEdition()

    let entitlements: any EntitlementProvider = UnlockedEntitlementProvider()

    var requiresLaunchAuthorization: Bool { false }
    func authorizeLaunch(onAuthorized: @escaping @MainActor () -> Void) async { onAuthorized() }
    func showLaunchAuthorization() {}
    func runtimeDidStart() {}
    func interfaceDidAppear() {}
    func entitlementDidChange(from previous: Bool, to current: Bool) {}
    var pendingIntroWindowID: String? { nil }

    func scenes(_ context: EditionSceneContext) -> some Scene { _EmptyScene() }
    func appMenuItems() -> AnyView? { nil }
    func controlPanel(_ content: AnyView) -> AnyView { content }
    func studioPrompt(_ placement: StudioPromptPlacement) -> AnyView? { nil }
    func aboutHeader() -> AnyView? { nil }
    func aboutSettingsRows() -> AnyView? { nil }
    func aboutToolbarButton() -> AnyView? { nil }
    func aboutFooterLinks() -> AnyView? { AnyView(StarOnGitHubLink()) }
    var aboutSearchLabels: [LocalizedStringResource] { [] }
    var displayVersion: String? { nil }
    var releaseChannel: String { "source" }
}

/// A section header that shows the edition's Studio prompt, if any, above its title.
struct StudioPromptHeader: View {
    let placement: StudioPromptPlacement
    let title: LocalizedStringKey

    var body: some View {
        if let prompt = Edition.shared.studioPrompt(placement) {
            VStack(alignment: .leading, spacing: 28) {
                prompt
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.primary)
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text(title)
        }
    }
}
