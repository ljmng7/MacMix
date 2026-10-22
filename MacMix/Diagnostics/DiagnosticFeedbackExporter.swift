import Foundation

/// One directly previewable UTF-8 report. Structured sections preserve complete
/// support data, followed by the readable event timeline; no ZIP or sidecars.
nonisolated enum DiagnosticFeedbackExporter {
    static func write(to destination: URL, title: String = "MacMix Feedback Log", notes: String = "",
                      environment: [String: String], snapshot: [String: String],
                      configuration: [DiagnosticConfigurationCapture] = [],
                      identification: DiagnosticIdentificationAttachment? = nil,
                      since: Date? = nil, until: Date? = nil, log: DiagnosticLog = .shared) async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("MacMix-Feedback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: scratch) }
        let storage = try await log.copyForExport(to: scratch, since: since, until: until)
        try await Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .custom { date, encoder in
                var container = encoder.singleValueContainer()
                try container.encode(DiagnosticLogText.timestamp(date))
            }
            var report = """
            \(title)
            Generated: \(DiagnosticLogText.timestamp(Date()))
            Timeline: \(since.map { DiagnosticLogText.timestamp($0) } ?? "retention start") – \(DiagnosticLogText.timestamp(until ?? Date()))
            Format: UTF-8 text, report version 2
            Timestamps: the Mac's local time with UTC offset, as in the file names.
            CPU: 100% = one core. Memory: physical footprint, bytes.
            System audio services are shared; do not attribute all their cost to MacMix.
            Target sampling: process/mixer 250 ms; response 100 ms; system/state 1 s.
            Actual intervals and sample ages are recorded. Missing data is not zero.
            Short audible glitches cannot be proved or excluded by these interval samples.
            Device/app identities are anonymous within each launch session.
            Selected details appear only when explicitly included by the user.
            No upload is performed by MacMix.

            """
            if !notes.isEmpty {
                report += "\n== USER DESCRIPTION ==\n"
                report += notes.split(separator: "\n", omittingEmptySubsequences: false).map { "  " + $0 }.joined(separator: "\n") + "\n"
            }
            func section<T: Encodable>(_ title: String, _ value: T) throws {
                report += "\n== \(title) ==\n" + String(decoding: try encoder.encode(value), as: UTF8.self) + "\n"
            }
            try section("ENVIRONMENT", environment)
            try section("CURRENT AUDIO STATE", snapshot)
            try section("AUDIO CONFIGURATION", configuration)
            if let identification { try section("SELECTED DETAILS", identification) }
            try section("STORAGE HEALTH", storage)
            report += "\n== EVENT TIMELINE ==\n"
            var data = Data(report.utf8)
            data.append(try Data(contentsOf: scratch.appendingPathComponent("Events.log")))
            // Atomic replacement preserves an existing report if saving fails.
            try data.write(to: destination, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        }.value
    }
}
