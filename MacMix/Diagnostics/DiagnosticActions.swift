import Foundation

/// Slider bursts keep their first/final values and edit count, without per-step IO.
@MainActor
final class DiagnosticActions {
    static let shared = DiagnosticActions()
    private struct Edit {
        let category: String
        let event: String
        let target: String
        let first: String
        let started: UInt64
        var last: String
        var count: Int
        var task: Task<Void, Never>?
    }
    private var edits: [String: Edit] = [:]

    func coalesce(_ category: String, _ event: String, target: String, value: String) {
        let key = "\(category):\(event):\(target)"
        if edits[key] == nil && edits.count >= 64 { flush() }
        var edit = edits[key] ?? Edit(category: category, event: event, target: target, first: value,
            started: DispatchTime.now().uptimeNanoseconds, last: value, count: 0)
        edit.task?.cancel()
        edit.last = value
        edit.count += 1
        edit.task = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            self?.finish(key)
        }
        edits[key] = edit
    }

    private func finish(_ key: String) {
        guard let edit = edits.removeValue(forKey: key) else { return }
        edit.task?.cancel()
        DiagnosticLog.shared.record(edit.category, edit.event, fields: [
            "target": DiagnosticLog.shared.anonymous(edit.target), "first": edit.first, "final": edit.last,
            "edits": String(edit.count),
            "durationMs": String((DispatchTime.now().uptimeNanoseconds - edit.started) / 1_000_000)
        ])
    }

    func flush() { for key in Array(edits.keys) { finish(key) } }
}
