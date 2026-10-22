import Foundation

/// A normal user cannot proc_pid_rusage root-owned audio services on some macOS
/// releases. macOS top provides their CPU and physical footprint without a helper
/// installation. Its global headers and process names are never persisted.
nonisolated final class DiagnosticSystemSampler: @unchecked Sendable {
    private var process: Process?
    private var pipe: Pipe?
    private var pids: Set<Int32> = []
    private let lock = NSLock()
    private var buffer = Data()
    private var samples: [Int32: [String: String]] = [:]
    private var generation = 0
    private var frameAt: UInt64 = 0
    private var previousFrameAt: UInt64 = 0
    private var frameCounts: [Int32: Int] = [:]
    private var failure: String?
    var processID: Int32? { process?.isRunning == true ? process?.processIdentifier : nil }

    func update(pids newPIDs: Set<Int32>) {
        guard newPIDs != pids || (!newPIDs.isEmpty && process?.isRunning != true) else { return }
        stop()
        guard !newPIDs.isEmpty else { return }
        lock.lock()
        pids = newPIDs
        let token = generation
        samples.removeAll(); buffer.removeAll(); frameCounts.removeAll()
        previousFrameAt = 0; frameAt = 0; failure = nil
        lock.unlock()
        let output = Pipe()
        let command = Process()
        command.executableURL = URL(fileURLWithPath: "/usr/bin/top")
        command.arguments = ["-l", "0", "-s", "1", "-F", "-R", "-stats", "pid,cpu,mem"]
            + newPIDs.sorted().flatMap { ["-pid", String($0)] }
        command.environment = ["LC_ALL": "C", "LANG": "C", "PATH": "/usr/bin:/bin"]
        command.standardOutput = output
        command.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty { self?.consume(data, generation: token) }
        }
        do {
            try command.run()
            process = command; pipe = output
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            lock.lock(); failure = "launch_failed"; lock.unlock()
        }
    }

    func stop() {
        pipe?.fileHandleForReading.readabilityHandler = nil
        if process?.isRunning == true { process?.terminate() }
        try? pipe?.fileHandleForReading.close()
        process = nil; pipe = nil
        lock.lock(); pids = []; generation += 1; lock.unlock()
    }

    func sample(pid: Int32) -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        if let failure { return ["source": "top", "status": failure] }
        guard var result = samples[pid] else { return ["source": "top", "status": "awaiting_sample"] }
        let now = DispatchTime.now().uptimeNanoseconds
        let sampled = UInt64(result.removeValue(forKey: "sampledUptime") ?? "0") ?? 0
        result["sampleAgeMs"] = String((now - min(now, sampled)) / 1_000_000)
        if now - min(now, sampled) > 3_000_000_000 {
            return ["source": "top", "status": "stale_or_exited", "sampleAgeMs": result["sampleAgeMs"]!]
        }
        return result
    }

    private func consume(_ data: Data, generation token: Int) {
        lock.lock(); defer { lock.unlock() }
        guard generation == token else { return }
        buffer.append(data)
        guard buffer.count < 256 * 1024 else { buffer.removeAll(); failure = "output_limit"; return }
        while let end = buffer.firstIndex(of: 10) {
            let line = String(decoding: buffer[..<end], as: UTF8.self)
            buffer.removeSubrange(...end)
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("PID") {
                previousFrameAt = frameAt; frameAt = DispatchTime.now().uptimeNanoseconds
                continue
            }
            guard var row = Self.parseRow(line), let pid = Int32(row["pid"]!), pids.contains(pid) else { continue }
            let baseline = frameCounts[pid, default: 0] == 0
            frameCounts[pid, default: 0] += 1
            if baseline { row.removeValue(forKey: "cpuPercent"); row["cpuStatus"] = "baseline_or_restart" }
            if previousFrameAt > 0 { row["intervalMs"] = String((frameAt - previousFrameAt) / 1_000_000) }
            row["sampledUptime"] = String(DispatchTime.now().uptimeNanoseconds)
            samples[pid] = row
        }
    }

    static func parseRow(_ line: String) -> [String: String]? {
        let columns = line.split(whereSeparator: \.isWhitespace)
        guard columns.count == 3, let pid = Int32(columns[0]), pid > 0,
              let cpu = Double(columns[1]), cpu.isFinite, cpu >= 0,
              let bytes = memoryBytes(String(columns[2])) else { return nil }
        return ["pid": String(pid), "cpuPercent": String(cpu), "footprintBytes": String(bytes),
            "source": "top", "status": "ok"]
    }

    static func memoryBytes(_ raw: String) -> UInt64? {
        let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: "+-*"))
        let units: [Character: Double] = ["B": 1, "K": 1024, "M": 1024 * 1024, "G": 1024 * 1024 * 1024, "T": 1024 * 1024 * 1024 * 1024]
        guard let suffix = cleaned.last, let multiplier = units[suffix],
              let value = Double(cleaned.dropLast()), value.isFinite, value >= 0,
              value * multiplier < Double(UInt64.max) else { return nil }
        return UInt64(value * multiplier)
    }
}
