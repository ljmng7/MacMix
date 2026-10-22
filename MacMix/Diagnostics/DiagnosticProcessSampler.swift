import Darwin
import Foundation

nonisolated struct DiagnosticProcessUsage: Sendable {
    let pid: Int32
    let role: String
    let started: UInt64
    let cpuTicks: UInt64
    let footprint: UInt64
    let time: UInt64

    func cpuPercent(since previous: Self, nanosecondsPerTick: Double) -> Double? {
        guard pid == previous.pid, started == previous.started, time > previous.time,
              cpuTicks >= previous.cpuTicks else { return nil }
        let percent = Double(cpuTicks - previous.cpuTicks) * nanosecondsPerTick
            / Double(time - previous.time) * 100
        return percent.isFinite ? percent : nil
    }
}

/// Only an allowlist of roles is persisted. Process paths, arguments and the
/// machine-wide process inventory never leave this temporary in-memory scan.
nonisolated final class DiagnosticProcessSampler {
    private var previous: [Int32: DiagnosticProcessUsage] = [:]
    private var selected: [Int32: String] = [:]
    private var lastDiscovery: UInt64?
    private var lastSystemEmission: UInt64?
    private let systemSampler = DiagnosticSystemSampler()
    private let rootPID = getpid()
    private let nanosecondsPerTick: Double
    init() {
        var base = mach_timebase_info_data_t()
        mach_timebase_info(&base)
        nanosecondsPerTick = Double(base.numer) / Double(base.denom)
    }

    deinit { systemSampler.stop() }

    func sample() -> [[String: String]] {
        var rows: [[String: String]] = []
        let now = DispatchTime.now().uptimeNanoseconds
        if lastDiscovery == nil || Double(now - lastDiscovery!) / 1e9 >= DiagnosticSamplingPolicy.discoveryInterval {
            lastDiscovery = now
            let discovery = discover()
            selected = discovery.roles
            let servicePIDs = Set(selected.filter { $0.value == "coreaudiod" || $0.value == "audio_driver_service" }.map(\.key))
            systemSampler.update(pids: servicePIDs)
            if let samplerPID = systemSampler.processID { selected[samplerPID] = "diagnostic_sampler" }
            if let error = discovery.error { rows.append(["role": "discovery", "status": "unavailable", "errno": String(error)]) }
        }
        let emitsSystem = lastSystemEmission == nil || Double(now - lastSystemEmission!) / 1e9 >= DiagnosticSamplingPolicy.systemInterval
        if emitsSystem { lastSystemEmission = now }
        var next: [Int32: DiagnosticProcessUsage] = [:]
        for (pid, role) in selected.sorted(by: { $0.key < $1.key }) {
            let isSystem = role == "coreaudiod" || role == "audio_driver_service"
            if isSystem && !emitsSystem {
                if let old = previous[pid] { next[pid] = old }
                continue
            }
            var info = rusage_info_v2()
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
                }
            }
            guard result == 0 else {
                if role == "coreaudiod" || role == "audio_driver_service" {
                    rows.append(systemSampler.sample(pid: pid).merging(["pid": String(pid), "role": role]) { _, new in new })
                    continue
                }
                rows.append(["pid": String(pid), "role": role, "status": "unavailable", "errno": String(errno)])
                continue
            }
            let usage = DiagnosticProcessUsage(pid: pid, role: role, started: info.ri_proc_start_abstime,
                cpuTicks: info.ri_user_time + info.ri_system_time, footprint: info.ri_phys_footprint,
                time: DispatchTime.now().uptimeNanoseconds)
            var row = ["pid": String(pid), "role": role, "status": "ok",
                "footprintBytes": String(usage.footprint), "source": "proc_pid_rusage"]
            if let old = previous[pid], let cpu = usage.cpuPercent(since: old, nanosecondsPerTick: nanosecondsPerTick) {
                row["cpuPercent"] = String(format: "%.3f", cpu)
                row["intervalMs"] = String((usage.time - old.time) / 1_000_000)
            } else {
                row["cpuStatus"] = "baseline_or_restart"
            }
            next[pid] = usage
            rows.append(row)
        }
        for (pid, old) in previous where next[pid] == nil {
            rows.append(["pid": String(pid), "role": old.role, "status": "exited_or_unreadable"])
        }
        previous = next
        if emitsSystem && !selected.values.contains("coreaudiod") {
            rows.append(["role": "coreaudiod", "status": "not_discovered"])
        }
        return rows
    }

    private func discover() -> (roles: [Int32: String], error: Int32?) {
        let command = Process()
        command.executableURL = URL(fileURLWithPath: "/bin/ps")
        command.arguments = ["-A", "-o", "pid=,ppid=,comm="]
        let output = Pipe()
        command.standardOutput = output
        command.standardError = FileHandle.nullDevice
        do { try command.run() } catch { return ([rootPID: "MacMix"], EPERM) }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        command.waitUntilExit()
        guard command.terminationStatus == 0 else { return ([rootPID: "MacMix"], EPERM) }
        var parents: [Int32: Int32] = [:]
        var roles: [Int32: String] = [rootPID: "MacMix"]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let parts = line.split(maxSplits: 2, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard parts.count == 3, let pid = Int32(parts[0]), let parent = Int32(parts[1]),
                  pid != command.processIdentifier else { continue }
            parents[pid] = parent
            let name = (String(parts[2]) as NSString).lastPathComponent
            if name == "coreaudiod" { roles[pid] = "coreaudiod" }
            if String(parts[2]).hasPrefix("Core Audio Driver") { roles[pid] = "audio_driver_service" }
        }
        var descendants: Set<Int32> = [rootPID]
        while true {
            let next = descendants.union(parents.filter { descendants.contains($0.value) }.map(\.key))
            if next == descendants { break }
            descendants = next
        }
        for pid in descendants where pid != rootPID { roles[pid] = pid == systemSampler.processID ? "diagnostic_sampler" : "MacMix_helper" }
        return (roles, nil)
    }
}

nonisolated final class DiagnosticRecorder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "MacMix.Diagnostics.Sampling", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var sampler: DiagnosticProcessSampler?
    private var sessionID: String?
    private var started = Date.distantPast
    private var began: UInt64 = 0
    private var stateRequestPending = false
    private var lastStateSnapshot: UInt64?
    private var lastSample: UInt64?
    private let heartbeat: DiagnosticHeartbeatMonitor
    private let mixerSnapshot: @Sendable (String) -> Void
    private let log: DiagnosticLog
    private let snapshot: @MainActor @Sendable () -> [String: String]
    private let onStop: @MainActor @Sendable () -> Void
    let maximumDuration: TimeInterval

    init(log: DiagnosticLog = .shared, maximumDuration: TimeInterval = DiagnosticSamplingPolicy.maximumDuration,
         snapshot: @escaping @MainActor @Sendable () -> [String: String],
         mixerSnapshot: @escaping @Sendable (String) -> Void = { _ in },
         onStop: @escaping @MainActor @Sendable () -> Void) {
        self.log = log; self.maximumDuration = maximumDuration
        self.snapshot = snapshot; self.onStop = onStop
        self.heartbeat = DiagnosticHeartbeatMonitor(log: log); self.mixerSnapshot = mixerSnapshot
    }

    func start(id: String) {
        queue.async { [self] in
            guard timer == nil else { return }
            sessionID = id; started = Date(); began = DispatchTime.now().uptimeNanoseconds
            sampler = DiagnosticProcessSampler()
            stateRequestPending = false; lastStateSnapshot = nil; lastSample = nil
            heartbeat.start(id: id)
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now(), repeating: DiagnosticSamplingPolicy.processInterval, leeway: .milliseconds(20))
            source.setEventHandler { [weak self] in self?.sample() }
            timer = source; source.resume()
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in finish(reason: "user"); continuation.resume() }
        }
    }

    private func finish(reason: String) {
        guard let id = sessionID else { return }
        timer?.cancel(); timer = nil; sampler = nil; sessionID = nil
        heartbeat.stop()
        DiagnosticCounters.shared.setEnabled(false)
        log.record("diagnostic", "stopped", fields: ["diagnostic": id, "reason": reason])
        Task { @MainActor [onStop] in onStop() }
    }

    private func sample() {
        guard let id = sessionID else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        if Double(now - began) / 1e9 >= maximumDuration || Date().timeIntervalSince(started) >= maximumDuration {
            finish(reason: "time_limit"); return
        }
        let interval = lastSample.map { (now - $0) / 1_000_000 } ?? 0
        lastSample = now
        for row in sampler?.sample() ?? [] {
            log.record("performance", "process_sample", fields: row.merging([
                "diagnostic": id, "recorderIntervalMs": String(interval)
            ]) { _, new in new })
        }
        mixerSnapshot(id)
        log.record("performance", "work_counters", fields:
            DiagnosticCounters.shared.take().merging(["diagnostic": id, "intervalMs": String(interval)]) { _, new in new })
        guard !stateRequestPending,
              lastStateSnapshot == nil || Double(now - lastStateSnapshot!) / 1e9 >= DiagnosticSamplingPolicy.stateInterval else { return }
        lastStateSnapshot = now
        stateRequestPending = true
        // Configuration reads stay at 1 Hz; heartbeat probes carry no audio/UI reads.
        Task { @MainActor [self] in
            let state = snapshot()
            queue.async { [self] in
                guard sessionID == id else { return }
                stateRequestPending = false
                log.record("performance", "audio_snapshot", fields: state.merging([
                    "diagnostic": id
                ]) { _, new in new })
            }
        }
    }
}
