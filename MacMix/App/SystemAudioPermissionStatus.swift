import AppKit
import AudioToolbox
import CoreAudio
import Foundation
import Observation

@MainActor
@Observable
final class SystemAudioPermissionStatusModel {
    private(set) var isAuthorized: Bool
    private(set) var isChecking = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let probe = SystemAudioPermissionProbe()
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var lastCheckedAt: Date?

    private static let authorizationKey = "MacMix.SystemAudioPermissionAuthorized"
    private static let lastCheckedAtKey = "MacMix.SystemAudioPermissionLastCheckedAt"
    private static let refreshInterval: TimeInterval = 24 * 60 * 60

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.now = now
        isAuthorized = defaults.object(forKey: Self.authorizationKey) == nil
            ? false
            : defaults.bool(forKey: Self.authorizationKey)
        lastCheckedAt = defaults.object(forKey: Self.lastCheckedAtKey) as? Date
    }

    func requestDuringOnboarding() async -> Bool? {
        await refresh(force: true)
    }

    func runPeriodicRefreshLoop() async {
        while !Task.isCancelled {
            _ = await refresh(force: false)

            let delay = min(
                Self.refreshInterval,
                max(1, secondsUntilNextRefresh)
            )
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
        }
    }

    private var secondsUntilNextRefresh: TimeInterval {
        guard let lastCheckedAt else { return 0 }
        return Self.refreshInterval - now().timeIntervalSince(lastCheckedAt)
    }

    private func refresh(force: Bool) async -> Bool? {
        guard !isChecking else { return nil }
        guard force || secondsUntilNextRefresh <= 0 else {
            return isAuthorized
        }

        isChecking = true
        defer { isChecking = false }

        guard let result = await detectAuthorization() else {
            DiagnosticLog.shared.record("permission", "audio_probe_cancelled")
            return nil
        }

        let checkedAt = now()
        DiagnosticLog.shared.record("permission", "audio_probe_result", fields: ["authorized": String(result)])
        isAuthorized = result
        lastCheckedAt = checkedAt
        defaults.set(result, forKey: Self.authorizationKey)
        defaults.set(checkedAt, forKey: Self.lastCheckedAtKey)
        return result
    }

    private func detectAuthorization() async -> Bool? {
        let focusCycle = ApplicationFocusCycleWaiter()
        let noPromptDeadline = ContinuousClock.now.advanced(by: .seconds(1))

        while !Task.isCancelled {
            if await probe.checkPermission() {
                focusCycle.cancel()
                return true
            }

            if focusCycle.hasReturnedToApplication {
                let isAuthorized = await probe.checkPermission()
                focusCycle.cancel()
                return isAuthorized
            }

            if !focusCycle.hasResignedFromApplication,
               ContinuousClock.now >= noPromptDeadline {
                focusCycle.cancel()
                return false
            }

            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                break
            }
        }

        focusCycle.cancel()
        return nil
    }
}

private nonisolated final class SystemAudioPermissionProbe: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "MacMix.SystemAudioPermissionProbe",
        qos: .userInitiated
    )

    func checkPermission() async -> Bool {
        await probePermission()
    }

    private func probePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Self.startAndStopSystemAudioCapture())
            }
        }
    }

    private static func startAndStopSystemAudioCapture() -> Bool {
        guard #available(macOS 14.4, *) else {
            return false
        }

        let recorder = SystemAudioPermissionRecorder()
        guard recorder.start() else {
            return false
        }

        Thread.sleep(forTimeInterval: 0.2)
        recorder.stop()
        return true
    }
}

@available(macOS 14.4, *)
private nonisolated final class SystemAudioPermissionRecorder {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    private var isRunning = false

    func start() -> Bool {
        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDescription.name = "MacMix System Audio Permission Check"
        tapDescription.muteBehavior = .unmuted
        tapDescription.isPrivate = true

        guard AudioHardwareCreateProcessTap(tapDescription, &tapID) == noErr,
              tapID != kAudioObjectUnknown else {
            stop()
            return false
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MacMix System Audio Permission Check",
            kAudioAggregateDeviceUIDKey: "MacMix.Permission.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: false,
                ],
            ],
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]

        guard AudioHardwareCreateAggregateDevice(
            aggregateDescription as CFDictionary,
            &aggregateID
        ) == noErr,
              aggregateID != kAudioObjectUnknown else {
            stop()
            return false
        }

        guard AudioDeviceCreateIOProcID(
            aggregateID,
            MacMixNoopAudioDeviceIOProc,
            nil,
            &ioProc
        ) == noErr,
              let ioProc else {
            stop()
            return false
        }

        guard AudioDeviceStart(aggregateID, ioProc) == noErr else {
            stop()
            return false
        }

        isRunning = true
        return true
    }

    func stop() {
        if let ioProc {
            if isRunning {
                AudioDeviceStop(aggregateID, ioProc)
                isRunning = false
            }

            AudioDeviceDestroyIOProcID(aggregateID, ioProc)
            self.ioProc = nil
        }

        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = kAudioObjectUnknown
        }

        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }

    deinit {
        stop()
    }
}

@MainActor
final class ApplicationFocusCycleWaiter {
    private var hasResigned = !NSApp.isActive
    private var hasReturnedAfterResigning = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var notificationTokens: [NSObjectProtocol] = []

    var hasReturnedToApplication: Bool {
        hasReturnedAfterResigning
    }

    var hasResignedFromApplication: Bool {
        hasResigned
    }

    init() {
        notificationTokens.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: NSApp,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.hasResigned = true
                }
            }
        )

        notificationTokens.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: NSApp,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.hasResigned else { return }
                    self.hasReturnedAfterResigning = true
                    self.resume()
                }
            }
        )
    }

    func waitForReturnOrNoPrompt() async {
        guard !hasReturnedAfterResigning else {
            cancel()
            return
        }

        await withCheckedContinuation { continuation in
            self.continuation = continuation

            if hasReturnedAfterResigning {
                resume()
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, !hasResigned else { return }
                resume()
            }
        }
    }

    func cancel() {
        removeObservers()
        resume()
    }

    private func resume() {
        removeObservers()
        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }

    private func removeObservers() {
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        notificationTokens.removeAll()
    }
}
