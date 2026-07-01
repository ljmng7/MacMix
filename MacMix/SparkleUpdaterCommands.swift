//
//  SparkleUpdaterCommands.swift
//  MacMix
//
//  Created by Codex on 2026/6/30.
//

import Combine
import Sparkle
import SwiftUI

struct CheckForUpdatesView: View {
    @StateObject private var viewModel: CheckForUpdatesViewModel
    private let showsIcon: Bool
    private let showsEllipsis: Bool

    init(updater: SPUUpdater, showsIcon: Bool = false, showsEllipsis: Bool = true) {
        _viewModel = StateObject(wrappedValue: CheckForUpdatesViewModel(updater: updater))
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
    @StateObject private var viewModel: AutomaticUpdatesViewModel

    init(updater: SPUUpdater) {
        _viewModel = StateObject(wrappedValue: AutomaticUpdatesViewModel(updater: updater))
    }

    var body: some View {
        Toggle(
            "Automatic Updates",
            isOn: Binding(
                get: { viewModel.isEnabled },
                set: viewModel.setAutomaticUpdatesEnabled
            )
        )
        .toggleStyle(.switch)
        .font(.system(size: 13, weight: .medium))
    }
}

@MainActor
private final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater

        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}

@MainActor
private final class AutomaticUpdatesViewModel: ObservableObject {
    @Published var isEnabled = true

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

    private var cancellables = Set<AnyCancellable>()

    private func refresh() {
        isEnabled = updater.automaticallyChecksForUpdates && updater.automaticallyDownloadsUpdates
    }
}
