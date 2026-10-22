import Foundation

/// UTF-8 lines readable in Quick Look/TextEdit, with lossless quoted field values.
/// Tabs delimit columns; JSON string escaping keeps tabs/newlines inside values
/// from becoming extra records. The event envelope remains recoverable for support.
nonisolated enum DiagnosticLogText {
    static func encode(_ event: DiagnosticEvent) -> String {
        let encoder = JSONEncoder()
        var columns = [timestamp(event.timestamp),
            "[\(event.level.uppercased())]", "\(event.category)/\(event.event)",
            "session=\(event.session)", "uptime_ns=\(event.uptimeNanoseconds)", "schema=\(event.schema)"]
        columns += event.fields.sorted { $0.key < $1.key }.map { key, value in
            let quoted = (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
            return "\(key)=\(quoted)"
        }
        return columns.joined(separator: "\t") + "\n"
    }

    static func decode(_ data: Data) -> DiagnosticEvent? {
        guard let line = String(data: data, encoding: .utf8) else { return nil }
        let columns = line.components(separatedBy: "\t")
        guard columns.count >= 6,
              let timestamp = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(columns[0]))
                ?? (try? Date.ISO8601FormatStyle().parse(columns[0])),
              columns[1].hasPrefix("["), columns[1].hasSuffix("]"),
              columns[3].hasPrefix("session="), columns[4].hasPrefix("uptime_ns="),
              let uptime = UInt64(columns[4].dropFirst("uptime_ns=".count)),
              columns[5] == "schema=1" else { return nil }
        let name = columns[2].split(separator: "/", maxSplits: 1)
        guard name.count == 2 else { return nil }
        let decoder = JSONDecoder()
        var fields: [String: String] = [:]
        for column in columns.dropFirst(6) {
            guard let delimiter = column.firstIndex(of: "="), delimiter != column.startIndex,
                  let value = try? decoder.decode(String.self, from: Data(column[column.index(after: delimiter)...].utf8)) else { return nil }
            fields[String(column[..<delimiter])] = value
        }
        return DiagnosticEvent(timestamp: timestamp, uptimeNanoseconds: uptime,
            session: String(columns[3].dropFirst("session=".count)), category: String(name[0]), event: String(name[1]),
            level: String(columns[1].dropFirst().dropLast()).lowercased(), fields: fields)
    }

    /// Local wall-clock time with its UTC offset, matching the daily file names
    /// while staying unambiguous across time zones. Older "Z" records still decode.
    static func timestamp(_ date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: timeZone))
    }

    static func day(_ date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static let recordingPrefix = "MacMix-Diagnostic-"

    /// Daily event logs (and legacy JSONL); saved diagnostic recordings share the
    /// folder but are self-contained reports, never re-read as event sources.
    static func isEventLog(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if url.pathExtension == "jsonl" { return true }
        return url.pathExtension == "log" && name.hasPrefix("MacMix-") && !name.hasPrefix(recordingPrefix)
    }

    static func isRecording(_ url: URL) -> Bool {
        url.pathExtension == "log" && url.lastPathComponent.hasPrefix(recordingPrefix)
    }

    static func recordingFileName(_ date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return recordingPrefix + formatter.string(from: date) + ".log"
    }

    static func fileName(day: String, part: Int) -> String {
        part == 1 ? "MacMix-\(day).log" : "MacMix-\(day)-\(String(format: "%02d", part)).log"
    }
}
