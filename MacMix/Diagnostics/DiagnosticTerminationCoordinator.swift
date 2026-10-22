import AppKit
import Foundation

/// Supports AppKit's terminateLater handshake without blocking the main thread.
/// An async deadline bounds best-effort storage waiting; AppKit schedules the reply.
@MainActor
final class DiagnosticTerminationCoordinator {
    private(set) var isPending = false
    private(set) var didFinish = false
    private let maximumDelay: Duration
    private var deadline: Task<Void, Never>?
    private var completion: (@MainActor () -> Void)?

    init(maximumDelay: Duration = .milliseconds(200)) {
        self.maximumDelay = maximumDelay
    }

    func begin(flush: @escaping @Sendable () async -> Void, completion: @escaping @MainActor () -> Void) {
        guard !isPending, !didFinish else { return }
        isPending = true
        self.completion = completion
        deadline = Task.detached { [weak self, maximumDelay] in
            do { try await Task.sleep(for: maximumDelay) } catch { return }
            self?.scheduleFinish()
        }
        Task.detached { [weak self] in
            await flush()
            self?.scheduleFinish()
        }
    }

    nonisolated private func scheduleFinish() {
        // terminateLater runs a modal AppKit loop. Main-actor tasks alone may
        // not be serviced there; explicitly support its run-loop modes.
        RunLoop.main.perform(inModes: [.common, .default, .modalPanel, .eventTracking]) { [weak self] in
            MainActor.assumeIsolated { self?.finish() }
        }
        // Also supports normal main-queue/async-main execution (including tests).
        DispatchQueue.main.async { [weak self] in self?.finish() }
    }

    private func finish() {
        guard isPending else { return }
        isPending = false
        didFinish = true
        deadline?.cancel(); deadline = nil
        let callback = completion
        completion = nil
        callback?()
    }
}
