import CryptoKit
import Darwin
import Foundation
import OSLog

nonisolated struct DiagnosticEvent: Codable, Sendable {
    var schema = 1
    let timestamp: Date
    let uptimeNanoseconds: UInt64
    let session: String
    let category: String
    let event: String
    let level: String
    let fields: [String: String]
}

/// Never call from an audio IOProc. Admission is bounded; all encoding and disk IO
/// are serialized off the main thread. The directory contains only sanitized data.
nonisolated final class DiagnosticLog: @unchecked Sendable {
    static let shared = DiagnosticLog()
    static let retentionDays = 7
    static let maximumBytes = 20 * 1024 * 1024
    static let maximumRecordings = 10
    let session = UUID().uuidString
    let directory: URL
    private let queue = DispatchQueue(label: "MacMix.Diagnostics.Storage", qos: .utility)
    private let lock = NSLock()
    private var pending = 0
    private var dropped = 0
    private var aliases: [String: String] = [:]
    private let salt = SymmetricKey(size: .bits256)
    private let logger = Logger(subsystem: "jazmin.MacMix", category: "Diagnostics")
    private let byteLimit: Int
    private let chunkLimit: Int
    private let ageLimit: TimeInterval
    private let legacyDirectory: URL?
    private var handle: FileHandle?
    private var currentURL: URL?
    private var currentBytes = 0
    private var chunk = 0
    private var currentDay: String?
    private var preparedFormat = false
    private var legacySkippedLines = 0
    private var writeFailures = 0
    private var lastCleanup = Date.distantPast
    private struct Repeat {
        let entry: DiagnosticEvent
        var last: Date
        var count: Int
    }
    private var repeats: [String: Repeat] = [:]

    init(directory: URL? = nil, byteLimit: Int = DiagnosticLog.maximumBytes,
         chunkLimit: Int = 5 * 1024 * 1024, ageLimit: TimeInterval = 7 * 86400, legacyDirectory: URL? = nil) {
        self.legacyDirectory = legacyDirectory ?? (directory == nil ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MacMix/Diagnostics", isDirectory: true) : nil)
        self.directory = (directory ?? FileManager.default.urls(for: .applicationSupportDirectory,
            in: .userDomainMask)[0].appendingPathComponent("MacMix/Log", isDirectory: true)).resolvingSymlinksInPath()
        self.byteLimit = byteLimit
        self.chunkLimit = min(chunkLimit, byteLimit)
        self.ageLimit = ageLimit
    }

    /// A random per-launch HMAC prevents dictionary attacks against device names/UIDs.
    func anonymous(_ identity: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        if let value = aliases[identity] { return value }
        let digest = HMAC<SHA256>.authenticationCode(for: Data(identity.utf8), using: salt)
        let value = digest.prefix(10).map { String(format: "%02x", $0) }.joined()
        if aliases.count < 1024 { aliases[identity] = value }
        return value
    }

    func record(_ category: String, _ event: String, level: String = "info", fields: [String: String] = [:]) {
        let entry = DiagnosticEvent(timestamp: Date(), uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
            session: session, category: category, event: event, level: level,
            fields: fields.mapValues { String($0.prefix(2048)) })
        lock.lock()
        guard pending < 512 else { dropped += 1; lock.unlock(); return }
        pending += 1
        lock.unlock()
        queue.async { [self] in
            defer { lock.lock(); pending -= 1; lock.unlock() }
            do {
                if entry.level == "error" {
                    let key = category + ":" + event + ":" + entry.fields.sorted { $0.key < $1.key }.description
                    if var repeated = repeats[key], entry.timestamp.timeIntervalSince(repeated.entry.timestamp) < 10 {
                        repeated.count += 1; repeated.last = entry.timestamp; repeats[key] = repeated
                        return
                    }
                    try flushRepeats(before: entry.timestamp.addingTimeInterval(-10))
                    if repeats.count >= 128 { try flushRepeats(before: .distantFuture) }
                    repeats[key] = Repeat(entry: entry, last: entry.timestamp, count: 0)
                }
                try append(entry)
                // Mirror only event names; private fields never become public unified logs.
                if level == "error" { logger.error("\(category, privacy: .public): \(event, privacy: .public)") }
                else { logger.info("\(category, privacy: .public): \(event, privacy: .public)") }
            } catch {
                writeFailures += 1
                logger.error("Diagnostic storage write failed")
            }
        }
    }

    private func prepareFormat() throws {
        guard !preparedFormat else { return }
        if let legacyDirectory, FileManager.default.fileExists(atPath: legacyDirectory.path) {
            let fm = FileManager.default
            if !fm.fileExists(atPath: directory.path) {
                try fm.moveItem(at: legacyDirectory, to: directory)
            } else {
                for source in try fm.contentsOfDirectory(at: legacyDirectory, includingPropertiesForKeys: nil) {
                    let target = directory.appendingPathComponent(source.lastPathComponent)
                    if !fm.fileExists(atPath: target.path) { try fm.moveItem(at: source, to: target) }
                    else if source.pathExtension == "jsonl" {
                        try fm.moveItem(at: source, to: directory.appendingPathComponent("Imported-\(UUID().uuidString).jsonl"))
                    } else if source.pathExtension == "log" {
                        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
                        var data = Data()
                        for line in try Data(contentsOf: source).split(separator: 10) {
                            if let event = DiagnosticLogText.decode(Data(line)) { data.append(try encoder.encode(event)); data.append(10) }
                        }
                        try data.write(to: directory.appendingPathComponent("Imported-\(UUID().uuidString).jsonl"), options: .atomic)
                        try fm.removeItem(at: source)
                    }
                }
                if try fm.contentsOfDirectory(atPath: legacyDirectory.path).isEmpty { try fm.removeItem(at: legacyDirectory) }
            }
        }
        legacySkippedLines = try DiagnosticLogMigration.run(in: directory, chunkLimit: chunkLimit)
        preparedFormat = true
    }

    private func append(_ event: DiagnosticEvent) throws {
        try prepareFormat()
        let data = Data(DiagnosticLogText.encode(event).utf8)
        let day = DiagnosticLogText.day(event.timestamp)
        if let handle {
            var status = stat()
            if fstat(handle.fileDescriptor, &status) == 0 { currentBytes = Int(status.st_size) }
        }
        let rotates = handle == nil || currentDay != day || currentBytes + data.count > chunkLimit
        if rotates {
            try handle?.close(); handle = nil
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let prefix = "MacMix-\(day)"
            let parts = try files().compactMap { entry -> (part: Int, url: URL, bytes: Int)? in
                let name = entry.url.deletingPathExtension().lastPathComponent
                if name == prefix { return (1, entry.url, entry.bytes) }
                if name.hasPrefix(prefix + "-"), let part = Int(name.dropFirst(prefix.count + 1)) {
                    return (part, entry.url, entry.bytes)
                }
                return nil
            }.sorted { $0.part < $1.part }
            let latest = parts.last
            chunk = latest?.part ?? 1
            if let latest, latest.bytes + data.count > chunkLimit { chunk += 1 }
            let url = directory.appendingPathComponent(DiagnosticLogText.fileName(day: day, part: chunk))
            if !FileManager.default.fileExists(atPath: url.path) {
                guard FileManager.default.createFile(atPath: url.path, contents: nil,
                    attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
            }
            let descriptor = Darwin.open(url.path, O_WRONLY | O_APPEND)
            guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
            handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            currentBytes = Int(try handle!.seekToEnd())
            // A crash can leave an unfinished tail. Keep it on its own line so
            // subsequent records remain decodable; export reports/skips that tail.
            if currentBytes > 0 {
                let reader = try FileHandle(forReadingFrom: url)
                try reader.seek(toOffset: UInt64(currentBytes - 1))
                let last = try reader.read(upToCount: 1)
                try reader.close()
                if last != Data([10]) { try handle?.write(contentsOf: Data([10])); currentBytes += 1 }
            }
            currentURL = url; currentDay = day
            try prune()
        }
        try handle?.write(contentsOf: data)
        currentBytes += data.count
        if event.level == "error" || event.event == "problem_marked" || event.event == "exit" { try handle?.synchronize() }
        if rotates || Date().timeIntervalSince(lastCleanup) > 60 || currentBytes >= chunkLimit { try prune() }
    }

    private func files(matching include: (URL) -> Bool = DiagnosticLogText.isEventLog) throws -> [(url: URL, modified: Date, bytes: Int)] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
            .filter(include)
            .compactMap { url in
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular else { return nil }
                return (url, attributes[.modificationDate] as? Date ?? .distantPast,
                    (attributes[.size] as? NSNumber)?.intValue ?? 0)
            }.sorted { $0.modified < $1.modified }
    }

    private func prune() throws {
        var entries = try files()
        let cutoff = Date().addingTimeInterval(-ageLimit)
        for entry in entries where entry.url.path != currentURL?.path && entry.modified < cutoff {
            try FileManager.default.removeItem(at: entry.url)
        }
        // Recordings are user-initiated reports: same age limit, newest 10 kept.
        let recordings = try files(matching: DiagnosticLogText.isRecording)
        for (index, recording) in recordings.reversed().enumerated()
            where recording.modified < cutoff || index >= Self.maximumRecordings {
            try FileManager.default.removeItem(at: recording.url)
        }
        entries = try files()
        // Reserve space for the active chunk so the configured total stays bounded.
        var total = entries.reduce(0) { $0 + ($1.url.path == currentURL?.path ? chunkLimit : $1.bytes) }
        for entry in entries where entry.url.path != currentURL?.path && total > byteLimit {
            try FileManager.default.removeItem(at: entry.url)
            total -= entry.bytes
        }
        lastCleanup = Date()
    }

    private func flushRepeats(before cutoff: Date) throws {
        for key in Array(repeats.keys) {
            guard let repeated = repeats[key], repeated.entry.timestamp <= cutoff else { continue }
            repeats.removeValue(forKey: key)
            guard repeated.count > 0 else { continue }
            var fields = repeated.entry.fields
            fields["repeatedEvent"] = repeated.entry.event
            fields["additionalOccurrences"] = String(repeated.count)
            fields["firstTimestamp"] = repeated.entry.timestamp.ISO8601Format()
            fields["lastTimestamp"] = repeated.last.ISO8601Format()
            try append(DiagnosticEvent(timestamp: Date(), uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
                session: session, category: repeated.entry.category, event: "repeated_error_summary", level: "error", fields: fields))
        }
    }

    func storageUsage() async throws -> Int64 {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    try prepareFormat()
                    try prune()
                    let bytes = try files { DiagnosticLogText.isEventLog($0) || DiagnosticLogText.isRecording($0) }
                        .reduce(Int64(0)) { $0 + Int64($1.bytes) }
                    continuation.resume(returning: bytes)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func prepareDirectory() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    try prepareFormat()
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                        attributes: [.posixPermissions: 0o700])
                    continuation.resume(returning: directory)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func flush() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                do { try flushRepeats(before: .distantFuture); try handle?.synchronize(); try prune() } catch { writeFailures += 1 }
                continuation.resume()
            }
        }
    }

    /// The serial barrier gives export a coherent snapshot while logging continues.
    /// `since`/`until` limit the copied timeline; retention still applies.
    func copyForExport(to folder: URL, since: Date? = nil, until: Date? = nil) async throws -> [String: Int] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    try prepareFormat()
                    try flushRepeats(before: .distantFuture)
                    try handle?.synchronize()
                    try prune()
                    let entries = try files()
                    let output = folder.appendingPathComponent("Events.log")
                    FileManager.default.createFile(atPath: output.path, contents: nil)
                    let destination = try FileHandle(forWritingTo: output)
                    defer { try? destination.close() }
                    var invalidLines = 0
                    var expiredEvents = 0
                    let cutoff = Date().addingTimeInterval(-ageLimit)
                    var excludedByRange = 0
                    // Sort by launch-relative filenames only inside each session;
                    // consumers order events by timestamp, session and monotonic time.
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    for entry in entries {
                        let data = try Data(contentsOf: entry.url)
                        for line in data.split(separator: 10) {
                            let event = entry.url.pathExtension == "jsonl"
                                ? try? decoder.decode(DiagnosticEvent.self, from: Data(line))
                                : DiagnosticLogText.decode(Data(line))
                            guard let event else {
                                invalidLines += 1; continue
                            }
                            guard event.timestamp >= cutoff else { expiredEvents += 1; continue }
                            if let since, event.timestamp < since { excludedByRange += 1; continue }
                            if let until, event.timestamp > until { excludedByRange += 1; continue }
                            try destination.write(contentsOf: Data(DiagnosticLogText.encode(event).utf8))
                        }
                    }
                    lock.lock(); let loss = dropped; lock.unlock()
                    continuation.resume(returning: ["droppedEvents": loss, "writeFailures": writeFailures,
                        "retainedFiles": entries.count, "invalidLinesSkipped": invalidLines, "legacyInvalidLinesSkipped": legacySkippedLines, "expiredEventsSkipped": expiredEvents, "outsideRequestedRange": excludedByRange, "retentionDays": Self.retentionDays,
                        "maximumBytes": byteLimit])
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    /// Cheap record count for one local day: one line per event in daily files.
    func lineCount(day: String) async -> Int {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                try? handle?.synchronize()
                let prefix = "MacMix-\(day)"
                let count = ((try? files()) ?? []).filter {
                    let name = $0.url.deletingPathExtension().lastPathComponent
                    return name == prefix || name.hasPrefix(prefix + "-")
                }.reduce(0) { total, entry in
                    total + ((try? Data(contentsOf: entry.url))?.reduce(0) { $1 == 10 ? $0 + 1 : $0 } ?? 0)
                }
                continuation.resume(returning: count)
            }
        }
    }

    func clear() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    try handle?.close(); handle = nil; currentURL = nil; currentBytes = 0; currentDay = nil
                    if FileManager.default.fileExists(atPath: directory.path) {
                        try FileManager.default.removeItem(at: directory)
                    }
                    lock.lock(); dropped = 0; lock.unlock()
                    writeFailures = 0; repeats.removeAll()
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}

/// Cheap counters are enabled only for manual diagnostics. No realtime IO hooks.
nonisolated final class DiagnosticCounters: @unchecked Sendable {
    static let shared = DiagnosticCounters()
    private let lock = NSLock()
    private var enabled = false
    private var values: [String: UInt64] = [:]
    func setEnabled(_ value: Bool) {
        lock.lock(); enabled = value; values.removeAll(); lock.unlock()
    }
    func increment(_ key: String, by amount: UInt64 = 1) {
        lock.lock(); defer { lock.unlock() }
        if enabled { values[key, default: 0] &+= amount }
    }
    func take() -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        let result = values.mapValues(String.init)
        values.removeAll(keepingCapacity: true)
        return result
    }
}
