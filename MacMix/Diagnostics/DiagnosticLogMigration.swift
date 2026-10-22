import Foundation

/// One-time conversion of old per-launch JSONL files into daily text logs.
/// Durable source backups make a crash during replacement/removal recoverable.
nonisolated enum DiagnosticLogMigration {
    private struct Commit: Codable {
        let inputs: [String]
        let outputs: [String]
        let skippedLines: Int
    }

    static func run(in directory: URL, chunkLimit: Int) throws -> Int {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return 0 }
        let transaction = directory.appendingPathComponent(".format-migration", isDirectory: true)
        let backups = transaction.appendingPathComponent("sources", isDirectory: true)
        let commitURL = transaction.appendingPathComponent("commit.json")
        if let data = try? Data(contentsOf: commitURL), let commit = try? JSONDecoder().decode(Commit.self, from: data) {
            try finish(commit, directory: directory, transaction: transaction)
            return commit.skippedLines
        }
        let inputs = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
            .filter(DiagnosticLogText.isEventLog)
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        guard inputs.contains(where: { $0.pathExtension == "jsonl" }) || fm.fileExists(atPath: transaction.path) else { return 0 }
        let snapshotURL = transaction.appendingPathComponent("snapshot.json")
        let sourceNames: [String]
        if let data = try? Data(contentsOf: snapshotURL), let names = try? JSONDecoder().decode([String].self, from: data) {
            sourceNames = names
        } else {
            try fm.createDirectory(at: backups, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            for input in inputs {
                let backup = backups.appendingPathComponent(input.lastPathComponent)
                // Before the snapshot marker is durable, no output replacement has
                // started; incomplete copies can safely be rebuilt from originals.
                if fm.fileExists(atPath: backup.path) { try fm.removeItem(at: backup) }
                try fm.copyItem(at: input, to: backup)
                let handle = try FileHandle(forWritingTo: backup)
                try handle.synchronize(); try handle.close()
            }
            sourceNames = inputs.map(\.lastPathComponent)
            try JSONEncoder().encode(sourceNames).write(to: snapshotURL, options: .atomic)
            let handle = try FileHandle(forWritingTo: snapshotURL)
            try handle.synchronize(); try handle.close()
        }
        let sourceFiles = sourceNames.map { backups.appendingPathComponent($0) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var events: [DiagnosticEvent] = []
        var seen = Set<String>()
        var skipped = 0
        for file in sourceFiles {
            for line in try Data(contentsOf: file).split(separator: 10) {
                let event = file.pathExtension == "jsonl"
                    ? try? decoder.decode(DiagnosticEvent.self, from: Data(line))
                    : DiagnosticLogText.decode(Data(line))
                guard let event else { skipped += 1; continue }
                let key = "\(event.session):\(event.uptimeNanoseconds):\(event.category):\(event.event)"
                if seen.insert(key).inserted { events.append(event) }
            }
        }
        events.sort {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            if $0.session != $1.session { return $0.session < $1.session }
            return $0.uptimeNanoseconds < $1.uptimeNanoseconds
        }
        let groups = Dictionary(grouping: events, by: { DiagnosticLogText.day($0.timestamp) })
        var outputNames: [String] = []
        for day in groups.keys.sorted() {
            var part = 1
            var contents = Data()
            var modified = Date.distantPast
            func save() throws {
                guard !contents.isEmpty else { return }
                let name = DiagnosticLogText.fileName(day: day, part: part)
                let url = directory.appendingPathComponent(name)
                try contents.write(to: url, options: .atomic)
                try fm.setAttributes([.posixPermissions: 0o600, .modificationDate: modified], ofItemAtPath: url.path)
                let handle = try FileHandle(forWritingTo: url)
                try handle.synchronize(); try handle.close()
                outputNames.append(name)
            }
            for event in groups[day] ?? [] {
                let line = Data(DiagnosticLogText.encode(event).utf8)
                if !contents.isEmpty && contents.count + line.count > chunkLimit {
                    try save(); contents.removeAll(keepingCapacity: true); part += 1
                }
                contents.append(line); modified = event.timestamp
            }
            try save()
        }
        let commit = Commit(inputs: sourceFiles.map(\.lastPathComponent), outputs: outputNames, skippedLines: skipped)
        try JSONEncoder().encode(commit).write(to: commitURL, options: .atomic)
        let commitHandle = try FileHandle(forWritingTo: commitURL)
        try commitHandle.synchronize(); try commitHandle.close()
        try finish(commit, directory: directory, transaction: transaction)
        return skipped
    }

    private static func finish(_ commit: Commit, directory: URL, transaction: URL) throws {
        let fm = FileManager.default
        for name in commit.inputs where !commit.outputs.contains(name) {
            let url = directory.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        }
        try fm.removeItem(at: transaction)
    }
}
