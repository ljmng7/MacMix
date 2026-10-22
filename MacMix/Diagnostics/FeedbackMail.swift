import Foundation

nonisolated struct FeedbackMailContent: Equatable, Sendable {
    static let recipient = "jasmine@jazminli.com"
    let subject: String
    let body: String
}

nonisolated struct FeedbackSystemInfo: Sendable {
    var appVersion: String
    var appBuild: String
    var macOSVersion: String
    var model: String
    var architecture: String
    var memoryBytes: UInt64
    var language: String

    /// "27.2 (26B5101f)"; operatingSystemVersionString is localized and unsuitable.
    static func macOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var text = "\(version.majorVersion).\(version.minorVersion)"
        if version.patchVersion > 0 { text += ".\(version.patchVersion)" }
        return sysctlString("kern.osversion").map { "\(text) (\($0))" } ?? text
    }

    static func hardwareModel() -> String? { sysctlString("hw.model") }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}

nonisolated struct FeedbackRecordingSummary: Sendable {
    let duration: TimeInterval
    let markerCount: Int
}

/// Builds the pre-filled email. Machine details come first so the person can
/// write freely below them; attachments follow the body in the mail client.
nonisolated enum FeedbackMail {
    static func content(system: FeedbackSystemInfo, recording: FeedbackRecordingSummary?,
                        affected: [DiagnosticIdentificationDetail], attachmentNames: [String],
                        prompt: String) -> FeedbackMailContent {
        var lines = [
            "MacMix \(system.appVersion) (\(system.appBuild))",
            "macOS \(system.macOSVersion)",
            "\(system.model) · \(system.architecture) · \(ByteCountFormatter.string(fromByteCount: Int64(clamping: system.memoryBytes), countStyle: .memory))",
            "Language: \(system.language)"
        ]
        if let recording {
            let seconds = max(0, Int(recording.duration.rounded()))
            var line = "Diagnostic recording: \(seconds / 60):\(String(format: "%02d", seconds % 60))"
            if recording.markerCount > 0 {
                line += " · \(recording.markerCount) problem marker\(recording.markerCount == 1 ? "" : "s")"
            }
            lines.append(line)
        }
        let affectedText = affected.compactMap(describe).joined(separator: "; ")
        if !affectedText.isEmpty { lines.append("Affected: \(affectedText)") }
        if !attachmentNames.isEmpty { lines.append("Attachments: \(attachmentNames.joined(separator: ", "))") }
        let body = lines.joined(separator: "\n") + "\n\n————————————————\n\n" + prompt + "\n\n\n\n"
        return FeedbackMailContent(subject: "MacMix Feedback · \(system.appVersion) (\(system.appBuild))", body: body)
    }

    private static func describe(_ detail: DiagnosticIdentificationDetail) -> String? {
        if detail.kind == "application" {
            guard let name = detail.appName, !name.isEmpty else { return detail.bundleIdentifier }
            return detail.bundleIdentifier.map { "\(name) (\($0))" } ?? name
        }
        let parts = [detail.manufacturer, detail.model].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "Unknown audio device" : parts.joined(separator: " ")
    }

    /// Today is usually enough. Early in the day, or when today has barely any
    /// events yet, yesterday is included so the attachment still has context.
    static func recentLogStart(now: Date, todayEventCount: Int, calendar: Calendar = .autoupdatingCurrent) -> Date {
        let today = calendar.startOfDay(for: now)
        guard now.timeIntervalSince(today) < 6 * 3600 || todayEventCount < 200 else { return today }
        return calendar.date(byAdding: .day, value: -1, to: today) ?? today
    }

    static func mailtoURL(_ content: FeedbackMailContent) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = FeedbackMailContent.recipient
        components.queryItems = [URLQueryItem(name: "subject", value: content.subject),
                                 URLQueryItem(name: "body", value: content.body)]
        // URLComponents leaves "+" unescaped, which some clients decode as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }
}
