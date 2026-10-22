import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class DiagnosticFeedbackModel {
    static let shared = DiagnosticFeedbackModel()
    private(set) var startedAt: Date?
    private(set) var diagnosticID: String?
    private(set) var markerCount = 0
    private(set) var isWorking = false
    private(set) var message: LocalizedStringResource?
    private(set) var failed = false
    private(set) var storageBytes: Int64?
    private(set) var identificationCandidates: [DiagnosticIdentificationCandidate] = []
    /// The finished recording waiting to be sent; always attached to the next email.
    private(set) var recording: DiagnosticRecordingFile?
    private(set) var isSavingRecording = false
    /// Keeps MacMix a regular app while the feedback window is open on its own.
    @ObservationIgnored var isWindowOpen = false
    @ObservationIgnored private var configurationCaptures: [DiagnosticConfigurationCapture] = []
    @ObservationIgnored private var finishing: Task<Void, Never>?
    @ObservationIgnored private var endSnapshotID: String?
    @ObservationIgnored private var recorder: DiagnosticRecorder?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored var snapshot: @MainActor @Sendable () -> [String: String] = { [:] }

    @ObservationIgnored var configuration: @MainActor @Sendable () -> DiagnosticAudioConfiguration = { .init() }
    @ObservationIgnored var identification: @MainActor @Sendable () -> [DiagnosticIdentificationCandidate] = { [] }
    /// Live panel items; reading it inside a view body tracks the audio model.
    @ObservationIgnored var affectedItems: @MainActor @Sendable () -> [FeedbackAffectedItem] = { [] }
    @ObservationIgnored var mixerSnapshot: @Sendable (String) -> Void = { _ in }

    private init() {
        DiagnosticLog.shared.record("application", "launch", fields: Self.environment())
        for (name, event) in [(NSWorkspace.willSleepNotification, "sleep"),
                              (NSWorkspace.didWakeNotification, "wake")] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil,
                queue: .main) { _ in DiagnosticLog.shared.record("application", event) })
        }
    }

    static func environment() -> [String: String] {
        var result = ["appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "appBuild": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "channel": Edition.shared.releaseChannel,
            "macOS": FeedbackSystemInfo.macOSVersion(),
            "physicalMemoryBytes": String(ProcessInfo.processInfo.physicalMemory),
            "logicalCPUCount": String(ProcessInfo.processInfo.processorCount),
            "cpuUnit": "100 percent = one CPU core",
            "sharedServices": "System audio service costs are shared; not attributed to MacMix",
            "processSampling": "MacMix/helpers 250 ms; heartbeat 100 ms; mixer 250 ms; audio state and system services 1 second; discovery 5 seconds",
            "samplingLimit": "Intervals are targets, not guaranteed deadlines. Interval CPU is an average, not an instantaneous peak. No audio or stacks are recorded."]
        #if arch(arm64)
        result["architecture"] = "arm64"
        #else
        result["architecture"] = "x86_64"
        #endif
        return result
    }

    func start() {
        guard startedAt == nil, !isWorking, !isSavingRecording else { return }
        message = nil; failed = false; markerCount = 0
        let id = UUID().uuidString
        diagnosticID = id; startedAt = Date(); endSnapshotID = nil; finishing = nil
        DiagnosticCounters.shared.setEnabled(true)
        DiagnosticLog.shared.record("diagnostic", "started", fields: ["diagnostic": id, "limitSeconds": "300", "processIntervalMs": "250", "heartbeatIntervalMs": "100", "mixerIntervalMs": "250", "systemIntervalMs": "1000"])
        configurationCaptures.removeAll()
        recordSnapshot("start_snapshot")
        let recorder = DiagnosticRecorder(snapshot: { [weak self] in self?.snapshot() ?? [:] }, mixerSnapshot: mixerSnapshot, onStop: { [weak self] in
            // Covers the automatic time limit; a manual stop reaches the same
            // idempotent finish, so the recording is saved exactly once.
            _ = self?.finishRecording(id: id)
        })
        self.recorder = recorder
        recorder.start(id: id)
    }

    func stop() async {
        if let recorder, let id = diagnosticID {
            DiagnosticActions.shared.flush()
            recordEndSnapshot()
            await recorder.stop()
            await finishRecording(id: id)?.value
        } else {
            await finishing?.value
        }
    }

    /// Saves the recording next to the daily logs as one self-contained report.
    private func finishRecording(id: String) -> Task<Void, Never>? {
        guard diagnosticID == id else { return nil }
        if let finishing { return finishing }
        guard let started = startedAt else { return nil }
        recordEndSnapshot()
        let markers = markerCount
        let captures = configurationCaptures
        startedAt = nil
        isSavingRecording = true
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.recorder = nil; self.isSavingRecording = false }
            let ended = Date()
            await DiagnosticLog.shared.flush()
            do {
                let folder = try await DiagnosticLog.shared.prepareDirectory()
                let url = folder.appendingPathComponent(DiagnosticLogText.recordingFileName(started))
                try await DiagnosticFeedbackExporter.write(to: url, title: "MacMix Diagnostic Recording",
                    environment: Self.environment(), snapshot: self.snapshot(), configuration: captures,
                    since: started.addingTimeInterval(-2), until: ended.addingTimeInterval(1))
                self.recording = DiagnosticRecordingFile(url: url, startedAt: started,
                    duration: ended.timeIntervalSince(started), markerCount: markers)
                await self.refreshStorageUsage()
            } catch {
                self.failed = true
                self.message = "Could not save the diagnostic recording."
                DiagnosticLog.shared.record("diagnostic", "recording_save_failed", level: "error")
            }
        }
        finishing = task
        return task
    }

    /// Deletes the finished recording and returns to the idle state.
    func discardRecording() {
        guard let recording else { return }
        try? FileManager.default.removeItem(at: recording.url)
        self.recording = nil
        DiagnosticLog.shared.record("diagnostic", "recording_discarded")
        Task { await refreshStorageUsage() }
    }

    func markProblem() {
        guard startedAt != nil else { return }
        markerCount += 1
        DiagnosticActions.shared.flush()
        DiagnosticLog.shared.record("diagnostic", "problem_marked", fields: [
            "diagnostic": diagnosticID ?? "", "marker": String(markerCount)
        ])
        recordSnapshot("problem_snapshot")
    }

    private func recordEndSnapshot() {
        guard let id = diagnosticID, endSnapshotID != id else { return }
        endSnapshotID = id
        recordSnapshot("end_snapshot")
    }

    func refreshIdentificationCandidates() {
        // Preserve devices/apps that disappeared after the problem occurred.
        var byID = Dictionary(identificationCandidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for candidate in identification() { byID[candidate.id] = candidate }
        identificationCandidates = Array(byID.values).sorted { $0.kind == $1.kind ? $0.displayName < $1.displayName : $0.kind < $1.kind }
    }

    private func captureConfiguration(phase: String) {
        let capture = DiagnosticConfigurationCapture(id: UUID().uuidString, phase: phase, timestamp: Date(),
            diagnostic: diagnosticID, configuration: configuration())
        capture.record(to: .shared)
        // Keep the initial snapshot plus the latest 63 captures for the structured
        // attachment; all captures remain in the bounded event log.
        if configurationCaptures.count >= 64 { configurationCaptures.remove(at: 1) }
        configurationCaptures.append(capture)
        refreshIdentificationCandidates()
    }

    private func recordSnapshot(_ event: String) {
        captureConfiguration(phase: event)
        DiagnosticLog.shared.record("diagnostic", event, fields:
            snapshot().merging(["diagnostic": diagnosticID ?? ""]) { _, new in new })
    }

    /// Opens a pre-filled draft. Returns true once the draft is handed to the mail app.
    func composeEmail(includeRecentLogs: Bool, selectedIdentificationIDs: Set<String>, prompt: String) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true; message = nil; failed = false
        defer { isWorking = false }
        await stop()
        guard !failed else { return false }
        DiagnosticActions.shared.flush()
        let attachment = DiagnosticIdentificationAttachment.selected(from: identificationCandidates,
            ids: selectedIdentificationIDs, modelOverrides: [:])
        var files: [URL] = []
        if let recording, FileManager.default.fileExists(atPath: recording.url.path) { files.append(recording.url) }
        if includeRecentLogs {
            do {
                files.append(try await writeRecentLogs(identification: attachment))
            } catch {
                failed = true
                message = "Could not prepare recent logs."
                DiagnosticLog.shared.record("diagnostic", "feedback_logs_failed", level: "error")
                return false
            }
        }
        let content = FeedbackMail.content(system: .current(),
            recording: recording.map { FeedbackRecordingSummary(duration: $0.duration, markerCount: $0.markerCount) },
            affected: attachment?.items ?? [], attachmentNames: files.map(\.lastPathComponent), prompt: prompt)
        DiagnosticLog.shared.record("diagnostic", "feedback_composed", fields: [
            "attachments": String(files.count), "recording": String(recording != nil),
            "recentLogs": String(includeRecentLogs), "selectedDetails": String(attachment?.items.count ?? 0)])
        switch FeedbackMailComposer.compose(content, attachments: files) {
        case .mail:
            recording = nil
            return true
        case .otherMailApp:
            message = "Your email app doesn't accept attachments from MacMix. Drag the files shown in Finder into the email."
            return false
        case .unavailable:
            failed = true
            message = "No email app is available. Send your feedback to \(FeedbackMailContent.recipient)."
            return false
        }
    }

    private func writeRecentLogs(identification: DiagnosticIdentificationAttachment?) async throws -> URL {
        let now = Date()
        let todayCount = await DiagnosticLog.shared.lineCount(day: DiagnosticLogText.day(now))
        let since = FeedbackMail.recentLogStart(now: now, todayEventCount: todayCount)
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("MacMix Feedback", isDirectory: true)
        // Drafts from earlier feedback have already copied their attachments.
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let first = DiagnosticLogText.day(since), last = DiagnosticLogText.day(now)
        let name = first == last ? "MacMix-Logs-\(last).log" : "MacMix-Logs-\(first)_\(last).log"
        let url = staging.appendingPathComponent(name)
        captureConfiguration(phase: "feedback_snapshot")
        try await DiagnosticFeedbackExporter.write(to: url, title: "MacMix Recent Logs",
            environment: Self.environment(), snapshot: snapshot(), configuration: Array(configurationCaptures.suffix(1)),
            identification: identification, since: since)
        return url
    }

    func refreshStorageUsage() async {
        storageBytes = try? await DiagnosticLog.shared.storageUsage()
    }

    func showLogsInFinder() async {
        guard !isWorking else { return }
        do {
            let directory = try await DiagnosticLog.shared.prepareDirectory()
            guard NSWorkspace.shared.open(directory) else { throw CocoaError(.fileReadUnknown) }
        } catch {
            failed = true; message = "Could not open the log folder."
        }
    }

    func clear() async {
        guard !isWorking else { return }
        isWorking = true; message = nil; failed = false
        defer { isWorking = false }
        // Keep start/export controls disabled throughout stopping and clearing.
        await stop()
        DiagnosticActions.shared.flush()
        do {
            try await DiagnosticLog.shared.clear()
            diagnosticID = nil; markerCount = 0; configurationCaptures.removeAll()
            identificationCandidates.removeAll(); recording = nil
            message = "Local logs cleared."
            await refreshStorageUsage()
        } catch {
            failed = true; message = "Could not clear local logs."
        }
    }
}

struct FeedbackAffectedItem: Identifiable {
    enum Icon {
        case device(symbolName: String, systemIcon: NSImage?, isCurrent: Bool)
        case application(image: NSImage?, isMuted: Bool)
    }
    let candidate: DiagnosticIdentificationCandidate
    let icon: Icon
    var id: String { candidate.id }
}

struct DiagnosticRecordingFile: Equatable {
    let url: URL
    let startedAt: Date
    let duration: TimeInterval
    let markerCount: Int
}

extension FeedbackSystemInfo {
    static func current(bundle: Bundle = .main) -> FeedbackSystemInfo {
        #if arch(arm64)
        let architecture = "Apple Silicon"
        #else
        let architecture = "Intel"
        #endif
        return FeedbackSystemInfo(
            appVersion: Edition.shared.displayVersion
                ?? bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            appBuild: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            macOSVersion: macOSVersion(),
            model: hardwareModel() ?? "Mac",
            architecture: architecture,
            memoryBytes: ProcessInfo.processInfo.physicalMemory,
            language: Locale.preferredLanguages.first ?? Locale.current.identifier)
    }
}

@MainActor
enum FeedbackMailComposer {
    enum Result { case mail, otherMailApp, unavailable }

    /// Apple Mail accepts the body and attachments directly. Other mail apps only
    /// receive a mailto draft, so the attachments are revealed for dragging in.
    static func compose(_ content: FeedbackMailContent, attachments: [URL]) -> Result {
        let handler = URL(string: "mailto:").flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
        let handlerID = handler.flatMap { Bundle(url: $0)?.bundleIdentifier }
        if handlerID == nil || handlerID == "com.apple.mail",
           let service = NSSharingService(named: .composeEmail) {
            let items: [Any] = [content.body as NSString] + attachments.map { $0 as NSURL }
            if service.canPerform(withItems: items) {
                service.recipients = [FeedbackMailContent.recipient]
                service.subject = content.subject
                service.perform(withItems: items)
                return .mail
            }
        }
        guard let url = FeedbackMail.mailtoURL(content), NSWorkspace.shared.open(url) else { return .unavailable }
        if attachments.isEmpty { return .mail }
        NSWorkspace.shared.activateFileViewerSelecting(attachments)
        return .otherMailApp
    }
}
