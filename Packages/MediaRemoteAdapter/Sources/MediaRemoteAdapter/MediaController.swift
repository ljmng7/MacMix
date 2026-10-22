import Foundation

public class MediaController {

    private var perlScriptPath: String? {
        guard let path = Bundle.module.path(forResource: "run", ofType: "pl") else {
            assertionFailure("run.pl script not found in bundle resources.")
            return nil
        }
        return path
    }

    private var listeningProcess: Process?
    private var listeningInputPipe: Pipe?
    private var dataBuffer = Data()
    private var dataBufferSearchStart = 0
    private var lastTrackInfoBySession: [String: TrackInfo] = [:]
    private var eventCount = 0
    private let bufferLock = NSLock()
    private let restartThreshold = 1_000
    private let commandQueue = DispatchQueue(label: "mediaremote-adapter.commands")
    private static let sigpipeIgnored: Void = {
        signal(SIGPIPE, SIG_IGN)
    }()

    public var onTrackInfoReceived: ((TrackInfo?) -> Void)?
    public var onListenerTerminated: (() -> Void)?
    public var onDecodingError: ((Error, Data) -> Void)?

    public init() {
        _ = MediaController.sigpipeIgnored
    }

    private var libraryPath: String? {
        let bundle = Bundle(for: MediaController.self)
        guard let path = bundle.executablePath else {
            assertionFailure("Could not locate the executable path for the MediaRemoteAdapter framework.")
            return nil
        }
        return path
    }

    @discardableResult
    private func runPerlCommand(arguments: [String]) -> (output: String?, error: String?, terminationStatus: Int32) {
        guard let scriptPath = perlScriptPath else {
            return (nil, "Perl script not found.", -1)
        }
        guard let libraryPath = libraryPath else {
            return (nil, "Dynamic library path not found.", -1)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptPath, libraryPath] + arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        let errorPipe = Pipe()
        process.standardError = errorPipe

        var outputBuffer = Data()
        var errorBuffer = Data()
        let lock = NSLock()

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            lock.lock()
            outputBuffer.append(data)
            lock.unlock()
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            lock.lock()
            errorBuffer.append(data)
            lock.unlock()
        }

        do {
            try process.run()
            process.waitUntilExit()

            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil

            lock.lock()
            outputBuffer.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
            errorBuffer.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
            lock.unlock()

            let output = String(data: outputBuffer, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let errorOutput = String(data: errorBuffer, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

            return (output, errorOutput, process.terminationStatus)
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            return (nil, error.localizedDescription, -1)
        }
    }

    public func getTrackInfo(_ onReceive: @escaping (TrackInfo?) -> Void) {
        guard let scriptPath = perlScriptPath else {
            onReceive(nil)
            return
        }
        guard let libraryPath = libraryPath else {
            onReceive(nil)
            return
        }

        let getProcess = Process()
        getProcess.executableURL = URL(fileURLWithPath: "/usr/bin/perl")

        var getDataBuffer = Data()
        var getDataBufferSearchStart = 0
        var callbackExecuted = false

        getProcess.arguments = [scriptPath, libraryPath, "get"]

        let outputPipe = Pipe()
        getProcess.standardOutput = outputPipe

        outputPipe.fileHandleForReading.readabilityHandler = { fileHandle in
            let incomingData = fileHandle.availableData
            if incomingData.isEmpty {
                fileHandle.readabilityHandler = nil
                return
            }

            getDataBuffer.append(incomingData)

            guard let newlineData = "\n".data(using: .utf8),
                  let range = getDataBuffer.firstRange(of: newlineData, in: getDataBufferSearchStart..<getDataBuffer.count),
                  range.lowerBound <= getDataBuffer.count else {
                getDataBufferSearchStart = getDataBuffer.count
                return
            }

            let lineData = getDataBuffer.subdata(in: 0..<range.lowerBound)
            getDataBuffer.removeSubrange(0..<range.upperBound)
            getDataBufferSearchStart = 0

            if !lineData.isEmpty && !callbackExecuted {
                callbackExecuted = true
                if lineData == "NIL".data(using: .utf8) {
                    DispatchQueue.main.async { onReceive(nil) }
                    return
                }
                do {
                    let trackInfo = try JSONDecoder().decode(TrackInfo.self, from: lineData)
                    DispatchQueue.main.async { onReceive(trackInfo) }
                } catch {
                    DispatchQueue.main.async { onReceive(nil) }
                }
            }
        }

        getProcess.terminationHandler = { _ in
            if !callbackExecuted {
                DispatchQueue.main.async { onReceive(nil) }
            }
        }

        do {
            try getProcess.run()
        } catch {
            onReceive(nil)
        }
    }

    public func startListening() {
        guard listeningProcess == nil else {
            return
        }

        eventCount = 0
        startListeningInternal()
    }

    private func startListeningInternal() {
        guard let scriptPath = perlScriptPath else {
            return
        }
        guard let libraryPath = libraryPath else {
            return
        }

        listeningProcess = Process()
        listeningProcess?.executableURL = URL(fileURLWithPath: "/usr/bin/perl")

        listeningProcess?.arguments = [scriptPath, libraryPath, "loop"]

        let inputPipe = Pipe()
        listeningProcess?.standardInput = inputPipe
        self.listeningInputPipe = inputPipe

        let outputPipe = Pipe()
        listeningProcess?.standardOutput = outputPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] fileHandle in
            guard let self = self else { return }

            let incomingData = fileHandle.availableData
            if incomingData.isEmpty {
                fileHandle.readabilityHandler = nil
                return
            }
            
            self.bufferLock.lock()
            defer { self.bufferLock.unlock() }

            self.dataBuffer.append(incomingData)

            guard let newlineData = "\n".data(using: .utf8) else { return }
            while let range = self.dataBuffer.firstRange(of: newlineData, in: self.dataBufferSearchStart..<self.dataBuffer.count) {
                guard range.lowerBound <= self.dataBuffer.count else {
                    break
                }

                let lineData = self.dataBuffer.subdata(in: 0..<range.lowerBound)

                self.dataBuffer.removeSubrange(0..<range.upperBound)
                self.dataBufferSearchStart = 0

                if lineData == "NIL".data(using: .utf8) {
                    DispatchQueue.main.async {
                        self.onTrackInfoReceived?(nil)
                    }
                    continue
                }

                if !lineData.isEmpty {
                    self.eventCount += 1

                    do {
                        let trackInfo = try JSONDecoder().decode(TrackInfo.self, from: lineData)
                        DispatchQueue.main.async {
                            let emitted = self.preservingArtworkIfDowngrade(trackInfo)
                            if let identifier = emitted.payload.sessionIdentifier {
                                if emitted.payload.removed == true {
                                    self.lastTrackInfoBySession.removeValue(forKey: identifier)
                                } else {
                                    self.lastTrackInfoBySession[identifier] = emitted
                                }
                            }
                            self.onTrackInfoReceived?(emitted)

                            if self.eventCount >= self.restartThreshold {
                                self.restartListeningProcess()
                            }
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.onDecodingError?(error, lineData)
                        }
                    }
                }
            }

            self.dataBufferSearchStart = self.dataBuffer.count
        }

        listeningProcess?.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.listeningProcess = nil
                self?.listeningInputPipe = nil
                if self?.eventCount != 0 {
                    self?.onListenerTerminated?()
                }
            }
        }

        do {
            try listeningProcess?.run()
        } catch {
            print("Failed to start listening process: \(error)")
            listeningProcess = nil
        }
    }

    public func stopListening() {
        (listeningProcess?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        listeningProcess?.terminate()
        listeningProcess = nil
        listeningInputPipe = nil
        
        bufferLock.lock()
        defer { bufferLock.unlock() }
        dataBuffer.removeAll()
        dataBufferSearchStart = 0
    }

    private func sendCommand(_ arguments: [String]) {
        guard !arguments.isEmpty else { return }
        let line = arguments.joined(separator: " ") + "\n"
        guard let data = line.data(using: .utf8) else { return }

        commandQueue.async { [weak self] in
            guard let self = self else { return }
            if let process = self.listeningProcess,
               process.isRunning,
               let pipe = self.listeningInputPipe {
                let handle = pipe.fileHandleForWriting
                do {
                    if #available(macOS 10.15.4, *) {
                        try handle.write(contentsOf: data)
                    } else {
                        handle.write(data)
                    }
                    return
                } catch {
                    // Pipe closed under us; fall through to spawn.
                }
            }
            _ = self.runPerlCommand(arguments: arguments)
        }
    }

    public func play() { sendCommand(["play"]) }

    public func play(playerPathDataBase64: String) {
        sendCommand(["play", playerPathDataBase64])
    }

    public func play(
        sessionIdentifier: String,
        playerPathDataBase64: String
    ) {
        sendSessionCommand(
            "play",
            sessionIdentifier: sessionIdentifier,
            playerPathDataBase64: playerPathDataBase64
        )
    }

    public func pause() { sendCommand(["pause"]) }

    public func pause(playerPathDataBase64: String) {
        sendCommand(["pause", playerPathDataBase64])
    }

    public func pause(
        sessionIdentifier: String,
        playerPathDataBase64: String
    ) {
        sendSessionCommand(
            "pause",
            sessionIdentifier: sessionIdentifier,
            playerPathDataBase64: playerPathDataBase64
        )
    }

    public func togglePlayPause() { sendCommand(["toggle_play_pause"]) }

    public func togglePlayPause(playerPathDataBase64: String) {
        sendCommand(["toggle_play_pause", playerPathDataBase64])
    }

    public func togglePlayPause(
        sessionIdentifier: String,
        playerPathDataBase64: String
    ) {
        sendSessionCommand(
            "toggle_play_pause",
            sessionIdentifier: sessionIdentifier,
            playerPathDataBase64: playerPathDataBase64
        )
    }

    public func nextTrack() { sendCommand(["next_track"]) }

    public func nextTrack(playerPathDataBase64: String) {
        sendCommand(["next_track", playerPathDataBase64])
    }

    public func nextTrack(
        sessionIdentifier: String,
        playerPathDataBase64: String
    ) {
        sendSessionCommand(
            "next_track",
            sessionIdentifier: sessionIdentifier,
            playerPathDataBase64: playerPathDataBase64
        )
    }

    public func previousTrack() { sendCommand(["previous_track"]) }

    public func previousTrack(playerPathDataBase64: String) {
        sendCommand(["previous_track", playerPathDataBase64])
    }

    public func previousTrack(
        sessionIdentifier: String,
        playerPathDataBase64: String
    ) {
        sendSessionCommand(
            "previous_track",
            sessionIdentifier: sessionIdentifier,
            playerPathDataBase64: playerPathDataBase64
        )
    }

    private func sendSessionCommand(
        _ command: String,
        sessionIdentifier: String,
        playerPathDataBase64: String,
        additionalArguments: [String] = []
    ) {
        let encodedIdentifier = Data(sessionIdentifier.utf8).base64EncodedString()
        sendCommand(
            [command, playerPathDataBase64, encodedIdentifier]
                + additionalArguments
        )
    }

    public func refreshAll() { sendCommand(["refresh_all"]) }

    public func stop() { sendCommand(["stop"]) }

    public func setTime(seconds: Double) { sendCommand(["set_time", String(seconds)]) }

    public func setTime(
        seconds: Double,
        sessionIdentifier: String,
        playerPathDataBase64: String
    ) {
        sendSessionCommand(
            "set_time",
            sessionIdentifier: sessionIdentifier,
            playerPathDataBase64: playerPathDataBase64,
            additionalArguments: [String(seconds)]
        )
    }

    public func toggleShuffle() { sendCommand(["toggle_shuffle"]) }

    public func toggleRepeat() { sendCommand(["toggle_repeat"]) }

    public func startForwardSeek() { sendCommand(["start_forward_seek"]) }

    public func endForwardSeek() { sendCommand(["end_forward_seek"]) }

    public func startBackwardSeek() { sendCommand(["start_backward_seek"]) }

    public func endBackwardSeek() { sendCommand(["end_backward_seek"]) }

    public func goBackFifteenSeconds() { sendCommand(["go_back_fifteen_seconds"]) }

    public func skipFifteenSeconds() { sendCommand(["skip_fifteen_seconds"]) }

    public func likeTrack() { sendCommand(["like_track"]) }

    public func banTrack() { sendCommand(["ban_track"]) }

    public func addToWishList() { sendCommand(["add_to_wish_list"]) }

    public func removeFromWishList() { sendCommand(["remove_from_wish_list"]) }

    public func setShuffleMode(_ mode: TrackInfo.ShuffleMode) {
        sendCommand(["set_shuffle_mode", String(mode.rawValue)])
    }

    public func setRepeatMode(_ mode: TrackInfo.RepeatMode) {
        sendCommand(["set_repeat_mode", String(mode.rawValue)])
    }

    private func isSameTrack(_ a: TrackInfo.Payload, _ b: TrackInfo.Payload) -> Bool {
        guard a.title == b.title, a.artist == b.artist else { return false }
        let aAlbum = a.album ?? ""
        let bAlbum = b.album ?? ""
        return aAlbum == bAlbum || aAlbum.isEmpty || bAlbum.isEmpty
    }

    private func preservingArtworkIfDowngrade(_ incoming: TrackInfo) -> TrackInfo {
        guard incoming.payload.removed != true,
              let identifier = incoming.payload.sessionIdentifier,
              let previous = lastTrackInfoBySession[identifier],
              isSameTrack(previous.payload, incoming.payload) else {
            return incoming
        }

        let previousLen = previous.payload.artworkDataBase64?.count ?? 0
        let incomingLen = incoming.payload.artworkDataBase64?.count ?? 0
        guard incomingLen < previousLen else {
            return incoming
        }

        let p = incoming.payload
        let merged = TrackInfo.Payload(
            title: p.title,
            artist: p.artist,
            album: p.album,
            isPlaying: p.isPlaying,
            durationMicros: p.durationMicros,
            elapsedTimeMicros: p.elapsedTimeMicros,
            applicationName: p.applicationName,
            bundleIdentifier: p.bundleIdentifier,
            artworkDataBase64: previous.payload.artworkDataBase64,
            artworkMimeType: previous.payload.artworkMimeType,
            timestampEpochMicros: p.timestampEpochMicros,
            PID: p.PID,
            shuffleMode: p.shuffleMode,
            repeatMode: p.repeatMode,
            playbackRate: p.playbackRate,
            sessionIdentifier: p.sessionIdentifier,
            playerPathDataBase64: p.playerPathDataBase64,
            isControllable: p.isControllable,
            removed: p.removed,
            artwork: previous.payload.artwork
        )
        return TrackInfo(payload: merged)
    }

    private func restartListeningProcess() {
        (listeningProcess?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        listeningProcess?.terminate()
        listeningProcess = nil
        listeningInputPipe = nil
        
        bufferLock.lock()
        defer { bufferLock.unlock() }
        dataBuffer.removeAll()
        dataBufferSearchStart = 0
        eventCount = 0

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.startListeningInternal()
        }
    }
}
