import Foundation

/// Independent of process discovery and sampling: slow ps/top work cannot be
/// mistaken for a main-thread stall. Only one main-thread probe is outstanding.
nonisolated final class DiagnosticHeartbeatMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "MacMix.Diagnostics.Responsiveness", qos: .utility)
    private let log: DiagnosticLog
    private var timer: DispatchSourceTimer?
    private var diagnostic: String?
    private var pending: UInt64?
    private var lastTick: UInt64?

    init(log: DiagnosticLog) { self.log = log }

    func start(id: String) {
        queue.async { [self] in
            diagnostic = id; pending = nil; lastTick = nil
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now(), repeating: DiagnosticSamplingPolicy.heartbeatInterval,
                leeway: .milliseconds(10))
            source.setEventHandler { [weak self] in self?.probe() }
            timer = source; source.resume()
        }
    }

    func stop() {
        queue.sync { [self] in
            timer?.cancel(); timer = nil; diagnostic = nil; pending = nil
        }
    }

    private func probe() {
        guard let id = diagnostic else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        let interval = lastTick.map { (now - $0) / 1_000_000 } ?? 0
        lastTick = now
        if let pending {
            log.record("performance", "main_response_pending", fields: [
                "diagnostic": id, "delayMs": String((now - pending) / 1_000_000),
                "monitorIntervalMs": String(interval)])
            return
        }
        pending = now
        Task { @MainActor [self] in
            let responded = DispatchTime.now().uptimeNanoseconds
            queue.async { [self] in
                guard diagnostic == id, pending == now else { return }
                pending = nil
                log.record("performance", "main_response", fields: [
                    "diagnostic": id, "delayMs": String((responded - now) / 1_000_000),
                    "monitorIntervalMs": String(interval)])
            }
        }
    }
}
