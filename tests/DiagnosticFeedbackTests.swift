import Darwin
import Foundation

@main
struct DiagnosticFeedbackTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }

    static func decodedEvents(_ data: Data) throws -> [[String: Any]] {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return try data.split(separator: 10).map { line in
            guard let event = DiagnosticLogText.decode(Data(line)) else { fatalError("Invalid text log record") }
            return try JSONSerialization.jsonObject(with: encoder.encode(event)) as! [String: Any]
        }
    }

    static func events(in folder: URL) throws -> [[String: Any]] {
        try decodedEvents(Data(contentsOf: folder.appendingPathComponent("Events.log")))
    }

    static func section(_ name: String, in report: String) -> Data {
        let start = report.range(of: "\n== \(name) ==\n")!.upperBound
        let remaining = report[start...]
        let end = remaining.range(of: "\n== ")?.lowerBound ?? report.endIndex
        return Data(report[start..<end].utf8)
    }

    @MainActor
    static func verifyAsyncTermination() async throws {
        // A delayed background flush must not block main-actor work or prevent
        // the deadline reply. Its later completion must not reply a second time.
        let slow = DiagnosticTerminationCoordinator(maximumDelay: .milliseconds(60))
        var slowReplies = 0
        slow.begin(flush: { try? await Task.sleep(for: .milliseconds(180)) }, completion: { slowReplies += 1 })
        slow.begin(flush: {}, completion: { slowReplies += 100 })
        var mainActorWorked = false
        Task { @MainActor in mainActorWorked = true }
        try await Task.sleep(for: .milliseconds(25))
        check(mainActorWorked && slow.isPending, "Termination blocked main actor")
        try await Task.sleep(for: .milliseconds(75))
        check(slow.didFinish && slowReplies == 1, "Termination deadline failed")
        try await Task.sleep(for: .milliseconds(120))
        check(slowReplies == 1, "Late flush replied twice")
        let fast = DiagnosticTerminationCoordinator(maximumDelay: .milliseconds(150))
        var fastReplies = 0
        fast.begin(flush: {}, completion: { fastReplies += 1 })
        try await Task.sleep(for: .milliseconds(30))
        check(fast.didFinish && fastReplies == 1, "Successful flush did not reply promptly")
        try await Task.sleep(for: .milliseconds(170))
        check(fastReplies == 1, "Cancelled deadline replied twice")
    }

    static func verifyFeedbackMail(root: URL) async throws {
        let system = FeedbackSystemInfo(appVersion: "2.3.0 Beta 1", appBuild: "22", macOSVersion: "26.1 (Build 25B78)",
            model: "Mac16,1", architecture: "Apple Silicon", memoryBytes: 16 << 30, language: "zh-Hans-CN")
        let device = DiagnosticIdentificationCandidate(id: "d", kind: "device", displayName: "Jasmine's AirPods",
            manufacturer: "Apple Inc.", model: "AirPods Pro").selectedDetail(modelOverride: nil)
        let app = DiagnosticIdentificationCandidate(id: "a", kind: "application", displayName: "Music",
            bundleIdentifier: "com.apple.Music").selectedDetail(modelOverride: nil)
        let mail = FeedbackMail.content(system: system, recording: FeedbackRecordingSummary(duration: 83, markerCount: 2),
            affected: [device, app], attachmentNames: ["MacMix-Diagnostic-2026-10-11-153210.log"], prompt: "PROMPT")
        check(mail.subject.contains("2.3.0 Beta 1") && mail.subject.contains("22"), "Subject lacks version")
        let lines = mail.body.components(separatedBy: "\n")
        check(lines[0] == "MacMix 2.3.0 Beta 1 (22)" && lines[1] == "macOS 26.1 (Build 25B78)", "System header must lead the body")
        check(mail.body.contains("Diagnostic recording: 1:23 · 2 problem markers"), "Recording summary missing")
        check(mail.body.contains("Apple Inc. AirPods Pro") && mail.body.contains("Music (com.apple.Music)"), "Affected items missing")
        check(!mail.body.contains("Jasmine's AirPods"), "Personal device name leaked into email")
        check(mail.body.hasSuffix("PROMPT\n\n\n\n"), "Writing space must follow the details")
        let mailto = FeedbackMail.mailtoURL(FeedbackMailContent(subject: "a+b", body: "x&y"))!.absoluteString
        check(mailto.hasPrefix("mailto:\(FeedbackMailContent.recipient)?") && mailto.contains("a%2Bb") && mailto.contains("x%26y"), "mailto encoding failed: \(mailto)")

        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 11))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        check(FeedbackMail.recentLogStart(now: today.addingTimeInterval(14 * 3600), todayEventCount: 5000, calendar: calendar) == today, "Busy afternoon should send today only")
        check(FeedbackMail.recentLogStart(now: today.addingTimeInterval(1 * 3600), todayEventCount: 5000, calendar: calendar) == yesterday, "Just after midnight should include yesterday")
        check(FeedbackMail.recentLogStart(now: today.addingTimeInterval(14 * 3600), todayEventCount: 20, calendar: calendar) == yesterday, "Quiet day should include yesterday")

        let shanghai = TimeZone(identifier: "Asia/Shanghai")!
        let midnight = Date(timeIntervalSince1970: 1_791_734_700) // 2026-10-12 00:05 +0800
        check(DiagnosticLogText.timestamp(midnight, timeZone: shanghai) == "2026-10-12T00:05:00.000+0800", "Timestamps must use the Mac's time zone")
        let localEvent = DiagnosticEvent(timestamp: midnight, uptimeNanoseconds: 1, session: "s", category: "c", event: "e", level: "info", fields: [:])
        check(DiagnosticLogText.decode(Data(DiagnosticLogText.encode(localEvent).dropLast().utf8))?.timestamp == midnight, "Local timestamp did not round-trip")
        let legacyLine = "2026-10-11T16:05:00.000Z\t[INFO]\tc/e\tsession=s\tuptime_ns=1\tschema=1"
        check(DiagnosticLogText.decode(Data(legacyLine.utf8))?.timestamp == midnight, "UTC records must still decode")
        check(FeedbackSystemInfo.macOSVersion().first?.isNumber == true, "macOS version must not be localized text")

        let folder = root.appendingPathComponent("feedback-logs")
        let log = DiagnosticLog(directory: folder)
        log.record("application", "before_recording")
        await log.flush()
        let started = Date()
        try await Task.sleep(for: .milliseconds(20))
        log.record("diagnostic", "inside_recording")
        await log.flush()
        let recordingURL = folder.appendingPathComponent(DiagnosticLogText.recordingFileName(started))
        check(DiagnosticLogText.isRecording(recordingURL) && !DiagnosticLogText.isEventLog(recordingURL), "Recording name collides with daily logs")
        try await DiagnosticFeedbackExporter.write(to: recordingURL, title: "MacMix Diagnostic Recording",
            environment: [:], snapshot: [:], since: started, log: log)
        let recordingText = try String(contentsOf: recordingURL, encoding: .utf8)
        check(recordingText.contains("inside_recording") && !recordingText.contains("before_recording"), "Recording range not applied")
        check(!recordingText.contains("== USER DESCRIPTION =="), "Empty description section emitted")
        let mode = try FileManager.default.attributesOfItem(atPath: recordingURL.path)[.posixPermissions] as! NSNumber
        check(mode.intValue == 0o600, "Recording must be private")
        // A saved recording in the log folder must not be re-read as event input.
        let export = root.appendingPathComponent("feedback-export")
        try FileManager.default.createDirectory(at: export, withIntermediateDirectories: true)
        let manifest = try await log.copyForExport(to: export)
        check(manifest["invalidLinesSkipped"] == 0, "Recording parsed as an event log")
        let exported = try events(in: export)
        check(exported.count == 2, "Daily timeline changed by recording")
        let usage = try await log.storageUsage()
        let recordingBytes = try FileManager.default.attributesOfItem(atPath: recordingURL.path)[.size] as! Int
        check(usage > Int64(recordingBytes), "Storage usage omits recordings")
        let todayCount = await log.lineCount(day: DiagnosticLogText.day(.now))
        check(todayCount == 2, "Today event count incorrect: \(todayCount)")
        try await log.clear()
        check(!FileManager.default.fileExists(atPath: recordingURL.path), "Clear kept recordings")
    }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacMix-Diagnostics-Tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("logs")
        let log = DiagnosticLog(directory: source)
        let secret = "Jasmine-Headphones-AA:BB:CC-secret"
        let anonymous = log.anonymous(secret)
        check(anonymous == log.anonymous(secret), "Identity must be stable within the launch")
        check(anonymous != DiagnosticLog(directory: root.appendingPathComponent("other")).anonymous(secret), "Identity must differ between launches")
        log.record("device", "connected", fields: ["device": anonymous])
        for _ in 0..<12 { log.record("mixer", "tap_failed", level: "error", fields: ["osStatus": "-50"]) }
        await log.flush()
        let export = root.appendingPathComponent("export")
        try FileManager.default.createDirectory(at: export, withIntermediateDirectories: true)
        let manifest = try await log.copyForExport(to: export)
        let rows = try events(in: export)
        check(rows.filter { $0["event"] as? String == "tap_failed" }.count == 1, "Repeated error must be aggregated")
        let repeated = rows.first { $0["event"] as? String == "repeated_error_summary" }
        check((repeated?["fields"] as? [String: String])?["additionalOccurrences"] == "11", "Repeat count lost")
        check(manifest["writeFailures"] == 0, "Storage failed")
        let text = try String(contentsOf: export.appendingPathComponent("Events.log"), encoding: .utf8)
        check(!text.contains(secret), "Raw device identity leaked")
        check(rows.allSatisfy { $0["session"] as? String == log.session && $0["uptimeNanoseconds"] != nil }, "Timeline missing")
        let usedBytes = try await log.storageUsage()
        let actualBytes = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: [.fileSizeKey])
            .filter { $0.pathExtension == "log" }.reduce(Int64(0)) { $0 + Int64(try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        check(usedBytes == actualBytes && usedBytes > 0, "Displayed storage usage does not match log files")
        let mode = try FileManager.default.attributesOfItem(atPath: source.path)[.posixPermissions] as! NSNumber
        check(mode.intValue == 0o700, "Log directory must be private")

        // Retention removes old sessions and bounds disk use, including the active chunk.
        let limitedFolder = root.appendingPathComponent("limited")
        try FileManager.default.createDirectory(at: limitedFolder, withIntermediateDirectories: true)
        let old = limitedFolder.appendingPathComponent("old.jsonl")
        try Data("old\n".utf8).write(to: old)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-8 * 86400)], ofItemAtPath: old.path)
        let limited = DiagnosticLog(directory: limitedFolder, byteLimit: 3000, chunkLimit: 900)
        for index in 0..<40 { limited.record("test", "event", fields: ["index": String(index), "payload": String(repeating: "x", count: 80)]) }
        await limited.flush()
        check(!FileManager.default.fileExists(atPath: old.path), "Expired file retained")
        let bytes = try FileManager.default.contentsOfDirectory(at: limitedFolder, includingPropertiesForKeys: [.fileSizeKey])
            .reduce(0) { sum, file in sum + (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        check(bytes <= 3000, "Storage exceeded limit: \(bytes)")
        let broken = source.appendingPathComponent("MacMix-interrupted.log")
        try Data("{\"incomplete\":\n".utf8).write(to: broken)
        let filtered = root.appendingPathComponent("filtered")
        try FileManager.default.createDirectory(at: filtered, withIntermediateDirectories: true)
        let filteredManifest = try await log.copyForExport(to: filtered)
        check(filteredManifest["invalidLinesSkipped"] == 1, "Truncated crash tail not reported")
        _ = try events(in: filtered)

        var configuration = DiagnosticAudioConfiguration(summary: ["systemMuted": "false"])
        configuration.devices = [DiagnosticConfiguredDevice(id: anonymous, selection: anonymous, direction: "output",
            current: true, transport: 1, volume: 0.5, selectedSourceCount: nil)]
        configuration.apps = (0..<100).map { index in
            var app = DiagnosticConfiguredApp(id: "app_\(index)", instance: "instance_\(index)", volume: 0.7,
                muted: false, appliedGain: 0.7, maximumVolume: 1)
            app.equalizerEnabled = true; app.equalizerAvailable = true; app.equalizerApplied = true
            app.equalizerGains = Array(repeating: 3, count: 10)
            app.followsSystemOutput = false; app.hasSavedOutputSelection = true; app.routingAvailable = true
            app.selectedDestinations = [DiagnosticConfiguredDestination(device: anonymous, selection: anonymous,
                available: false, selectedSourceCount: nil)]
            app.resolvedDestinationDevices = []
            return app
        }
        let capture = DiagnosticConfigurationCapture(id: "capture-start", phase: "start_snapshot", timestamp: Date(),
            diagnostic: "test-recording", configuration: configuration)
        capture.record(to: log)
        let deviceCandidate = DiagnosticIdentificationCandidate(id: anonymous, kind: "device", displayName: secret,
            manufacturer: "Example Manufacturer", model: "Example Headphones")
        let appCandidate = DiagnosticIdentificationCandidate(id: "app_0", kind: "application", displayName: "Selected Player",
            bundleIdentifier: "example.selected.player")
        check(DiagnosticIdentificationAttachment.selected(from: [deviceCandidate, appCandidate], ids: [], modelOverrides: [:]) == nil,
            "Identifying details must be opt-in")
        let attachment = DiagnosticIdentificationAttachment.selected(from: [deviceCandidate, appCandidate],
            ids: [anonymous, "app_0"], modelOverrides: [anonymous: "Reviewed Model"])!
        let attachmentText = String(decoding: try JSONEncoder().encode(attachment), as: UTF8.self)
        check(!attachmentText.contains(secret), "Personal device name leaked in optional attachment")
        check(attachmentText.contains("Reviewed Model") && attachmentText.contains("example.selected.player"), "Selected details lost")
        let reportURL = root.appendingPathComponent("feedback.log")
        try await DiagnosticFeedbackExporter.write(to: reportURL, notes: "Audio stopped after switching outputs.",
            environment: ["cpuUnit": "100 percent = one CPU core"], snapshot: ["outputDevice": anonymous], configuration: [capture], log: log)
        let report = try String(contentsOf: reportURL, encoding: .utf8)
        let configurationDecoder = JSONDecoder(); configurationDecoder.dateDecodingStrategy = .iso8601
        let completeCaptures = try configurationDecoder.decode([DiagnosticConfigurationCapture].self, from: section("AUDIO CONFIGURATION", in: report))
        check(completeCaptures[0].configuration.apps.count == 100, "Configuration report truncated")
        check(completeCaptures[0].configuration.apps[0].equalizerGains.count == 10, "EQ state missing")
        check(completeCaptures[0].configuration.apps[0].resolvedDestinationDevices == [], "Offline destination semantics lost")
        check(!report.contains(secret) && !report.contains("== SELECTED DETAILS =="), "Unselected identity leaked")
        let appRecords = try decodedEvents(section("EVENT TIMELINE", in: report)).filter { $0["event"] as? String == "application" }
        check(appRecords.count == 100, "Large app list truncated in timeline")
        check(report.contains("Audio stopped after switching outputs."), "Notes lost")
        let selectedURL = root.appendingPathComponent("selected-feedback.log")
        try await DiagnosticFeedbackExporter.write(to: selectedURL, notes: "", environment: [:], snapshot: [:],
            configuration: [capture], identification: attachment, log: log)
        let selectedText = try String(contentsOf: selectedURL, encoding: .utf8)
        check(selectedText.contains("Selected Player") && !selectedText.contains(secret), "Opt-in report privacy failed")
        await log.flush()
        try await log.clear()
        check(!FileManager.default.fileExists(atPath: source.path), "Clear did not remove logs")
        let emptyBytes = try await log.storageUsage()
        check(emptyBytes == 0, "Storage usage did not reset after clearing")
        let finderFolder = try await log.prepareDirectory()
        check(finderFolder.resolvingSymlinksInPath() == source.resolvingSymlinksInPath() && FileManager.default.fileExists(atPath: finderFolder.path), "Finder destination not prepared")
        log.record("application", "after_clear")
        await log.flush()
        check(FileManager.default.fileExists(atPath: source.path), "Logging did not resume after clear")

        let quoted = DiagnosticEvent(timestamp: Date(), uptimeNanoseconds: 777, session: "codec-session",
            category: "test", event: "quoted", level: "info", fields: ["value": "line1\nline2\tquote=\"中文\"\\end"])
        let textLine = DiagnosticLogText.encode(quoted)
        check(textLine.split(separator: "\n").count == 1, "A field created additional log records")
        check(DiagnosticLogText.decode(Data(textLine.dropLast().utf8))?.fields == quoted.fields, "Text codec lost escaped values")

        let boundary = Date(timeIntervalSince1970: 1791678600)
        check(DiagnosticLogText.day(boundary, timeZone: TimeZone(secondsFromGMT: -8 * 3600)!) != DiagnosticLogText.day(boundary, timeZone: TimeZone(secondsFromGMT: 8 * 3600)!), "Filename ignored user timezone")
        let oldDirectory = root.appendingPathComponent("Diagnostics")
        let newDirectory = root.appendingPathComponent("Log")
        try FileManager.default.createDirectory(at: oldDirectory, withIntermediateDirectories: true)
        let oldEncoder = JSONEncoder(); oldEncoder.dateEncodingStrategy = .iso8601
        try (oldEncoder.encode(quoted) + Data([10])).write(to: oldDirectory.appendingPathComponent("old.jsonl"))
        let movedLog = DiagnosticLog(directory: newDirectory, legacyDirectory: oldDirectory)
        movedLog.record("test", "after_move"); await movedLog.flush()
        check(!FileManager.default.fileExists(atPath: oldDirectory.path), "Old Diagnostics folder was not moved")
        let movedFiles = try FileManager.default.contentsOfDirectory(at: newDirectory, includingPropertiesForKeys: nil)
        let movedEvents = try decodedEvents(Data(contentsOf: movedFiles[0]))
        check(movedEvents.count == 2, "Folder migration lost logs")
        let dailyFolder = root.appendingPathComponent("daily")
        let firstLaunch = DiagnosticLog(directory: dailyFolder)
        firstLaunch.record("application", "first_launch")
        await firstLaunch.flush()
        let secondLaunch = DiagnosticLog(directory: dailyFolder)
        secondLaunch.record("application", "second_launch")
        await secondLaunch.flush()
        firstLaunch.record("application", "first_launch_continues")
        await firstLaunch.flush()
        let dailyFiles = try FileManager.default.contentsOfDirectory(at: dailyFolder, includingPropertiesForKeys: nil)
        check(dailyFiles.count == 1 && dailyFiles[0].lastPathComponent == DiagnosticLogText.fileName(day: DiagnosticLogText.day(.now), part: 1),
            "Relaunch created another random log file")
        let dailyEvents = try decodedEvents(Data(contentsOf: dailyFiles[0]))
        check(dailyEvents.count == 3, "Relaunch/concurrent handle overwrote the existing day")

        let legacyFolder = root.appendingPathComponent("legacy")
        try FileManager.default.createDirectory(at: legacyFolder, withIntermediateDirectories: true)
        let legacyEncoder = JSONEncoder(); legacyEncoder.dateEncodingStrategy = .iso8601
        for index in 0..<2 {
            let event = DiagnosticEvent(timestamp: Date(), uptimeNanoseconds: UInt64(index), session: "old-session-\(index)",
                category: "legacy", event: "retained", level: "info", fields: ["index": String(index)])
            try (legacyEncoder.encode(event) + Data([10])).write(to: legacyFolder.appendingPathComponent("old-\(index).jsonl"))
        }
        let legacyLog = DiagnosticLog(directory: legacyFolder)
        legacyLog.record("application", "new_format")
        await legacyLog.flush()
        let migratedFiles = try FileManager.default.contentsOfDirectory(at: legacyFolder, includingPropertiesForKeys: nil)
        check(migratedFiles.count == 1 && migratedFiles[0].pathExtension == "log", "Legacy fragments not consolidated")
        let migratedEvents = try decodedEvents(Data(contentsOf: migratedFiles[0]))
        check(migratedEvents.count == 3, "Legacy records lost")

        // Simulate a crash after source backups but during output replacement.
        let recovery = root.appendingPathComponent("migration-recovery")
        let backups = recovery.appendingPathComponent(".format-migration/sources")
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let recoveryEvent = DiagnosticEvent(timestamp: Date(), uptimeNanoseconds: 1, session: "recover", category: "test", event: "retained", level: "info", fields: [:])
        try (legacyEncoder.encode(recoveryEvent) + Data([10])).write(to: backups.appendingPathComponent("recover.jsonl"))
        try JSONEncoder().encode(["recover.jsonl"]).write(to: recovery.appendingPathComponent(".format-migration/snapshot.json"))
        try Data(DiagnosticLogText.encode(recoveryEvent).utf8).write(to: recovery.appendingPathComponent(DiagnosticLogText.fileName(day: DiagnosticLogText.day(.now), part: 1)))
        _ = try DiagnosticLogMigration.run(in: recovery, chunkLimit: 5 * 1024 * 1024)
        let recovered = try FileManager.default.contentsOfDirectory(at: recovery, includingPropertiesForKeys: nil)
        check(recovered.count == 1, "Migration recovery left temporary fragments")
        let recoveredEvents = try decodedEvents(Data(contentsOf: recovered[0]))
        check(recoveredEvents.count == 1, "Migration retry duplicated data")

        // Real proc reads plus numerical/PID-reuse safeguards.
        check(DiagnosticSystemSampler.parseRow(" 581  3.5  25M ")?["footprintBytes"] == "26214400", "System memory units incorrect")
        check(DiagnosticSystemSampler.parseRow("PID %CPU MEM") == nil, "System header leaked into samples")
        check(DiagnosticSystemSampler.memoryBytes("2G+") == 2147483648, "System memory marker parse failed")
        let sampler = DiagnosticProcessSampler()
        let initial = sampler.sample()
        check(initial.contains { $0["role"] == "MacMix" && $0["status"] == "ok" && $0["cpuStatus"] != nil }, "Self process baseline missing")
        // Compare measured CPU time with getrusage, independently of Mach ticks.
        _ = sampler.sample()
        var before = rusage(); getrusage(RUSAGE_SELF, &before)
        let deadline = DispatchTime.now().uptimeNanoseconds + 100_000_000
        var accumulator = 0.0
        while DispatchTime.now().uptimeNanoseconds < deadline { accumulator += sin(accumulator + 0.01) }
        let busy = sampler.sample().first { $0["role"] == "MacMix" }!
        var after = rusage(); getrusage(RUSAGE_SELF, &after)
        func seconds(_ usage: rusage) -> Double {
            Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
                + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
        }
        let observedCPU = Double(busy["cpuPercent"]!)! / 100 * Double(busy["intervalMs"]!)! / 1000
        let posixCPU = seconds(after) - seconds(before)
        check(abs(observedCPU - posixCPU) < 0.015, "Mach CPU conversion disagrees with getrusage: \(observedCPU) vs \(posixCPU)")
        check(accumulator.isFinite, "Calibration work failed")
        let a = DiagnosticProcessUsage(pid: 1, role: "MacMix", started: 7, cpuTicks: 10, footprint: 1, time: 100)
        let b = DiagnosticProcessUsage(pid: 1, role: "MacMix", started: 7, cpuTicks: 20, footprint: 1, time: 200)
        check(b.cpuPercent(since: a, nanosecondsPerTick: 10) == 100, "CPU unit is incorrect")
        let reused = DiagnosticProcessUsage(pid: 1, role: "MacMix", started: 8, cpuTicks: 20, footprint: 1, time: 200)
        check(reused.cpuPercent(since: a, nanosecondsPerTick: 10) == nil, "PID reuse produced a false spike")
        let reset = DiagnosticProcessUsage(pid: 1, role: "MacMix", started: 7, cpuTicks: 5, footprint: 1, time: 200)
        check(reset.cpuPercent(since: a, nanosecondsPerTick: 10) == nil, "Counter reset underflow")

        let recordingLog = DiagnosticLog(directory: root.appendingPathComponent("recording"))
        let recorder = DiagnosticRecorder(log: recordingLog, maximumDuration: 1.5, snapshot: { ["device": "anonymous"] }, onStop: {})
        recorder.start(id: "bounded-test")
        try await Task.sleep(for: .milliseconds(250))
        DispatchQueue.main.async { Thread.sleep(forTimeInterval: 0.32) }
        try await Task.sleep(for: .seconds(3))
        await recorder.stop()
        await recordingLog.flush()
        let recording = root.appendingPathComponent("recording-export")
        try FileManager.default.createDirectory(at: recording, withIntermediateDirectories: true)
        _ = try await recordingLog.copyForExport(to: recording)
        let recordingEvents = try events(in: recording)
        check(recordingEvents.contains { $0["event"] as? String == "process_sample" }, "Recording did not sample")
        check(recordingEvents.contains { ($0["fields"] as? [String: String])?["reason"] == "time_limit" }, "Recording did not auto-stop")
        let ownSamples = recordingEvents.filter { $0["event"] as? String == "process_sample" && ($0["fields"] as? [String: String])?["role"] == "MacMix" }
        check(ownSamples.count >= 4, "250 ms sampling did not increase resolution")
        let responses = recordingEvents.filter { $0["event"] as? String == "main_response" }
        check(responses.count >= 6, "100 ms heartbeat did not run")
        check(recordingEvents.contains { event in
            let fields = event["fields"] as? [String: String]
            return (event["event"] as? String == "main_response_pending" || event["event"] as? String == "main_response")
                && Double(fields?["delayMs"] ?? "0")! >= 180
        }, "Short main-thread stall was not captured")
        check(recordingEvents.filter { $0["event"] as? String == "audio_snapshot" }.count <= 3, "Full state reads became high-frequency")
        try await verifyAsyncTermination()
        try await verifyFeedbackMail(root: root)
        print("PASS: email draft content, recent-log window, recordings kept out of event logs, range export; async bounded termination and duplicate/late completion guards; full EQ/routing configuration, large app lists, opt-in privacy, 250 ms CPU, 100 ms heartbeat/stall, 1 Hz state, and legacy checks; private identities, repeat aggregation, retention/cap, crash tail, single readable report, daily append, legacy migration/recovery, text escaping, clear/resume, process reads, CPU/PID guards, recording/automatic stop")
    }
}
