//
//  NowPlayingModel.swift
//  MacMix
//

import AppKit
import MediaRemoteAdapter
import Observation
import OSLog

@MainActor
@Observable
final class NowPlayingSessionState: Identifiable {
    private struct PendingSeek {
        let position: TimeInterval
        let requestedAt: Date
        let expectedIsPlaying: Bool
        var positionWasConfirmed = false
    }

    private struct SeekReconciliation {
        let acceptsPosition: Bool
        let acceptsPlaybackState: Bool
    }

    let id: String

    private(set) var title: String
    private(set) var artist: String
    private(set) var album: String
    private(set) var applicationName: String
    private(set) var bundleIdentifier: String
    private(set) var processIdentifier: pid_t?
    private(set) var isPlaying: Bool
    private(set) var duration: TimeInterval?
    private(set) var elapsedTime: TimeInterval?
    private(set) var timestamp: Date?
    private(set) var playbackRate: Double
    private(set) var artwork: NSImage?
    private(set) var applicationIcon: NSImage?
    private(set) var isControllable: Bool

    @ObservationIgnored private(set) var playerPathDataBase64: String
    @ObservationIgnored private var artworkDataBase64: String?
    @ObservationIgnored private var pendingSeek: PendingSeek?

    init?(payload: TrackInfo.Payload) {
        guard let id = payload.sessionIdentifier,
              let title = payload.title,
              !title.isEmpty,
              let playerPathDataBase64 = payload.playerPathDataBase64 else {
            return nil
        }

        self.id = id
        self.title = title
        artist = payload.artist ?? ""
        album = payload.album ?? ""
        applicationName = payload.applicationName ?? ""
        bundleIdentifier = payload.bundleIdentifier ?? ""
        processIdentifier = payload.PID
        let initialIsPlaying = payload.isPlaying ?? false
        isPlaying = initialIsPlaying
        duration = payload.durationMicros.map { $0 / 1_000_000 }
        elapsedTime = payload.elapsedTimeMicros.map { $0 / 1_000_000 }
        timestamp = payload.timestampEpochMicros.map {
            Date(timeIntervalSince1970: $0 / 1_000_000)
        }
        playbackRate = payload.playbackRate ?? (initialIsPlaying ? 1 : 0)
        artwork = payload.artwork
        artworkDataBase64 = payload.artworkDataBase64
        self.playerPathDataBase64 = playerPathDataBase64
        isControllable = payload.isControllable ?? false
        applicationIcon = Self.applicationIcon(for: bundleIdentifier)
    }

    var subtitle: String {
        [artist, album]
            .filter { !$0.isEmpty }
            .joined(separator: " – ")
    }

    func elapsedTime(at date: Date) -> TimeInterval {
        let base = elapsedTime ?? 0
        guard isPlaying, playbackRate > 0, let timestamp else {
            return clamped(base)
        }
        return clamped(base + max(0, date.timeIntervalSince(timestamp)) * playbackRate)
    }

    func applySeek(to position: TimeInterval, at date: Date) {
        let target = clamped(position)
        elapsedTime = target
        timestamp = date
        pendingSeek = PendingSeek(
            position: target,
            requestedAt: date,
            expectedIsPlaying: isPlaying
        )
    }

    func update(from payload: TrackInfo.Payload) {
        let previousTrackIdentity = trackIdentity

        if let title = payload.title, !title.isEmpty, title != self.title {
            self.title = title
        }
        update(&artist, with: payload.artist)
        update(&album, with: payload.album)
        update(&applicationName, with: payload.applicationName)
        let trackDidChange = previousTrackIdentity != trackIdentity
        if trackDidChange {
            pendingSeek = nil
        }

        if let bundleIdentifier = payload.bundleIdentifier,
           bundleIdentifier != self.bundleIdentifier {
            self.bundleIdentifier = bundleIdentifier
            applicationIcon = Self.applicationIcon(for: bundleIdentifier)
        }
        if let processIdentifier = payload.PID,
           processIdentifier != self.processIdentifier {
            self.processIdentifier = processIdentifier
        }
        updateSeconds(&duration, micros: payload.durationMicros)
        let reconciliation = reconcilePendingSeek(with: payload)
        if reconciliation.acceptsPlaybackState,
           let isPlaying = payload.isPlaying,
           isPlaying != self.isPlaying {
            self.isPlaying = isPlaying
        }
        if reconciliation.acceptsPosition {
            updateSeconds(&elapsedTime, micros: payload.elapsedTimeMicros)
            if let timestampMicros = payload.timestampEpochMicros {
                let nextTimestamp = Date(
                    timeIntervalSince1970: timestampMicros / 1_000_000
                )
                if timestamp != nextTimestamp {
                    timestamp = nextTimestamp
                }
            }
        }

        if reconciliation.acceptsPlaybackState {
            if let nextRate = payload.playbackRate,
               playbackRate != nextRate {
                playbackRate = nextRate
            } else if let isPlaying = payload.isPlaying {
                let nextRate = isPlaying ? max(playbackRate, 1) : 0
                if playbackRate != nextRate {
                    playbackRate = nextRate
                }
            }
        }
        if let playerPath = payload.playerPathDataBase64,
           playerPath != playerPathDataBase64 {
            playerPathDataBase64 = playerPath
        }
        if let isControllable = payload.isControllable,
           isControllable != self.isControllable {
            self.isControllable = isControllable
        }
        if trackDidChange,
           payload.artworkDataBase64 == nil {
            artworkDataBase64 = nil
            artwork = nil
        } else if let artworkDataBase64 = payload.artworkDataBase64,
                  artworkDataBase64 != self.artworkDataBase64 {
            self.artworkDataBase64 = artworkDataBase64
            artwork = payload.artwork
        }
    }

    private var trackIdentity: String {
        "\(title)\u{1F}\(artist)\u{1F}\(album)"
    }

    private func reconcilePendingSeek(
        with payload: TrackInfo.Payload
    ) -> SeekReconciliation {
        guard var pendingSeek else {
            return SeekReconciliation(
                acceptsPosition: true,
                acceptsPlaybackState: true
            )
        }

        let now = Date()
        let age = max(0, now.timeIntervalSince(pendingSeek.requestedAt))
        if age >= 2.5 {
            self.pendingSeek = nil
            return SeekReconciliation(
                acceptsPosition: true,
                acceptsPlaybackState: true
            )
        }

        var acceptsPosition = false
        if let elapsedMicros = payload.elapsedTimeMicros {
            let reportedPosition = elapsedMicros / 1_000_000
            let reportedAt = payload.timestampEpochMicros.map {
                Date(timeIntervalSince1970: $0 / 1_000_000)
            } ?? now
            let isFreshTimestamp = reportedAt
                >= pendingSeek.requestedAt.addingTimeInterval(-0.05)
            let expectedRate: Double
            if pendingSeek.expectedIsPlaying {
                expectedRate = playbackRate > 0 ? playbackRate : 1
            } else {
                expectedRate = 0
            }
            let expectedPosition = clamped(
                pendingSeek.position
                    + max(
                        0,
                        reportedAt.timeIntervalSince(pendingSeek.requestedAt)
                    ) * expectedRate
            )
            acceptsPosition = isFreshTimestamp
                && abs(reportedPosition - expectedPosition) <= 2
            if acceptsPosition {
                pendingSeek.positionWasConfirmed = true
            }
        }

        let playbackStateWasConfirmed = payload.isPlaying
            == pendingSeek.expectedIsPlaying
        let acceptsPlaybackState = playbackStateWasConfirmed
        if pendingSeek.positionWasConfirmed && playbackStateWasConfirmed {
            self.pendingSeek = nil
        } else {
            self.pendingSeek = pendingSeek
        }
        return SeekReconciliation(
            acceptsPosition: acceptsPosition,
            acceptsPlaybackState: acceptsPlaybackState
        )
    }

    private func clamped(_ value: TimeInterval) -> TimeInterval {
        guard let duration, duration > 0 else {
            return max(0, value)
        }
        return min(max(0, value), duration)
    }

    private func update(_ value: inout String, with nextValue: String?) {
        guard let nextValue, nextValue != value else {
            return
        }
        value = nextValue
    }

    private func updateSeconds(
        _ value: inout TimeInterval?,
        micros: Double?
    ) {
        guard let micros else {
            return
        }
        let seconds = micros / 1_000_000
        if value != seconds {
            value = seconds
        }
    }

    private static func applicationIcon(for bundleIdentifier: String) -> NSImage? {
        guard !bundleIdentifier.isEmpty,
              let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
              ) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: applicationURL.path)
    }
}

@MainActor
@Observable
final class NowPlayingModel {
    private(set) var sessions: [NowPlayingSessionState] = []

    @ObservationIgnored private let controller = MediaController()
    @ObservationIgnored private var sessionsByID: [String: NowPlayingSessionState] = [:]
    @ObservationIgnored private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "jazmin.MacMix",
        category: "NowPlaying"
    )

    init(startsListening: Bool = true) {
        controller.onTrackInfoReceived = { [weak self] trackInfo in
            guard let trackInfo else {
                return
            }
            self?.receive(trackInfo.payload)
        }
        controller.onDecodingError = { [weak self] error, _ in
            self?.logger.error("Could not decode MediaRemote update")
            DiagnosticLog.shared.record("media", "decode_failed", level: "error")
        }
        controller.onListenerTerminated = { [weak self] in
            DiagnosticLog.shared.record("media", "helper_terminated", level: "error")
            guard let self else {
                return
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                DiagnosticLog.shared.record("media", "helper_restart_requested")
                self.controller.startListening()
            }
        }
        if startsListening {
            controller.startListening()
        }
    }

    func refresh() {
        controller.refreshAll()
    }

    func togglePlayback(for session: NowPlayingSessionState) {
        guard session.isControllable else {
            return
        }
        if session.isPlaying {
            controller.pause(
                sessionIdentifier: session.id,
                playerPathDataBase64: session.playerPathDataBase64
            )
        } else {
            controller.play(
                sessionIdentifier: session.id,
                playerPathDataBase64: session.playerPathDataBase64
            )
        }
    }

    func playPrevious(for session: NowPlayingSessionState) {
        guard session.isControllable else {
            return
        }
        controller.previousTrack(
            sessionIdentifier: session.id,
            playerPathDataBase64: session.playerPathDataBase64
        )
    }

    func playNext(for session: NowPlayingSessionState) {
        guard session.isControllable else {
            return
        }
        controller.nextTrack(
            sessionIdentifier: session.id,
            playerPathDataBase64: session.playerPathDataBase64
        )
    }

    func seek(to position: TimeInterval, for session: NowPlayingSessionState) {
        guard session.isControllable,
              position.isFinite,
              let duration = session.duration,
              duration > 0 else {
            return
        }
        let target = min(max(0, position), duration)
        session.applySeek(to: target, at: Date())
        controller.setTime(
            seconds: target,
            sessionIdentifier: session.id,
            playerPathDataBase64: session.playerPathDataBase64
        )
    }

    func openApplication(for session: NowPlayingSessionState) {
        if !session.bundleIdentifier.isEmpty,
           let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: session.bundleIdentifier
           ) {
            NSWorkspace.shared.openApplication(
                at: applicationURL,
                configuration: NSWorkspace.OpenConfiguration()
            )
            return
        }

        if let processIdentifier = session.processIdentifier,
           let application = NSRunningApplication(
            processIdentifier: processIdentifier
           ) {
            application.activate()
        }
    }

    private func receive(_ payload: TrackInfo.Payload) {
        guard let identifier = payload.sessionIdentifier else {
            return
        }
        if payload.removed == true {
            sessionsByID.removeValue(forKey: identifier)
            sessions.removeAll { $0.id == identifier }
            return
        }

        if let session = sessionsByID[identifier] {
            session.update(from: payload)
            return
        }

        guard let session = NowPlayingSessionState(payload: payload) else {
            return
        }
        sessionsByID[identifier] = session
        sessions.append(session)
        sessions.sort {
            $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
    }
}
