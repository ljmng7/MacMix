//
//  SparkleUpdaterCommands.swift
//  MacMix
//
//  Created by Codex on 2026/6/30.
//

import Combine
import Observation
import Sparkle
import SwiftUI

struct CheckForUpdatesView: View {
    @State private var viewModel: CheckForUpdatesViewModel
    private let showsIcon: Bool
    private let showsEllipsis: Bool

    init(updater: SPUUpdater, showsIcon: Bool = false, showsEllipsis: Bool = true) {
        _viewModel = State(initialValue: CheckForUpdatesViewModel(updater: updater))
        self.showsIcon = showsIcon
        self.showsEllipsis = showsEllipsis
    }

    var body: some View {
        Button {
            viewModel.checkForUpdates()
        } label: {
            if showsIcon {
                Label(title, systemImage: "arrow.triangle.2.circlepath")
            } else {
                Text(title)
            }
        }
        .disabled(!viewModel.canCheckForUpdates)
    }

    private var title: LocalizedStringKey {
        showsEllipsis ? "Check for Updates..." : "Check for Updates"
    }
}

struct AutomaticUpdatesToggle: View {
    @State private var viewModel: AutomaticUpdatesViewModel

    init(updater: SPUUpdater) {
        _viewModel = State(initialValue: AutomaticUpdatesViewModel(updater: updater))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        Toggle(
            "Automatic Updates",
            isOn: $viewModel.automaticUpdatesEnabled
        )
        .toggleStyle(.switch)
        .font(.body.weight(.medium))
    }
}

@MainActor
@Observable
private final class CheckForUpdatesViewModel {
    private(set) var canCheckForUpdates = false

    private let updater: SPUUpdater
    @ObservationIgnored private var cancellable: AnyCancellable?

    init(updater: SPUUpdater) {
        self.updater = updater

        cancellable = updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheckForUpdates in
                self?.canCheckForUpdates = canCheckForUpdates
            }
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}

@MainActor
@Observable
private final class AutomaticUpdatesViewModel {
    private var isEnabled = true

    var automaticUpdatesEnabled: Bool {
        get { isEnabled }
        set { setAutomaticUpdatesEnabled(newValue) }
    }

    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        refresh()

        updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)

        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)

    }

    func setAutomaticUpdatesEnabled(_ shouldEnable: Bool) {
        updater.automaticallyChecksForUpdates = shouldEnable
        updater.automaticallyDownloadsUpdates = shouldEnable
        refresh()
    }

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    private func refresh() {
        isEnabled = updater.automaticallyChecksForUpdates && updater.automaticallyDownloadsUpdates
    }
}
