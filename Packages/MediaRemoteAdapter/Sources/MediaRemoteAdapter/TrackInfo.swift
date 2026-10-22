import AppKit
import Foundation

public struct TrackInfo: Codable {
    public let payload: Payload

    public init(payload: Payload) {
        self.payload = payload
    }

    public enum ShuffleMode: Int, Codable {
        case off = 0
        case songs = 1
        case albums = 2
    }

    public enum RepeatMode: Int, Codable {
        case off = 0
        case one = 1
        case all = 2
    }

    public struct Payload: Codable {
        public let title: String?
        public let artist: String?
        public let album: String?
        public let isPlaying: Bool?
        public let durationMicros: Double?
        public let elapsedTimeMicros: Double?
        public let applicationName: String?
        public let bundleIdentifier: String?
        public let artworkDataBase64: String?
        public let artworkMimeType: String?
        public let timestampEpochMicros: Double?
        public let PID: pid_t?
        public let shuffleMode: ShuffleMode?
        public let repeatMode: RepeatMode?
        public let playbackRate: Double?
        public let sessionIdentifier: String?
        public let playerPathDataBase64: String?
        public let isControllable: Bool?
        public let removed: Bool?

        public let artwork: NSImage?

        public var uniqueIdentifier: String {
            sessionIdentifier ?? "\(title ?? "")-\(artist ?? "")-\(album ?? "")"
        }

        public var currentElapsedTime: TimeInterval? {
            guard let elapsedMicros = elapsedTimeMicros,
                  let timestampMicros = timestampEpochMicros else {
                return nil
            }

            let elapsedSeconds = elapsedMicros / 1_000_000

            if isPlaying != true {
                return elapsedSeconds
            }

            let timestampSeconds = timestampMicros / 1_000_000
            let rate = playbackRate ?? 0.0

            let now = Date().timeIntervalSince1970
            let timeSinceUpdate = now - timestampSeconds

            return elapsedSeconds + (timeSinceUpdate * rate)
        }

        enum CodingKeys: String, CodingKey {
            case title, artist, album, isPlaying, durationMicros, elapsedTimeMicros
            case applicationName, bundleIdentifier, artworkDataBase64, artworkMimeType
            case timestampEpochMicros, PID, shuffleMode, repeatMode, playbackRate
            case sessionIdentifier, playerPathDataBase64, isControllable, removed
        }

        public init(
            title: String? = nil,
            artist: String? = nil,
            album: String? = nil,
            isPlaying: Bool? = nil,
            durationMicros: Double? = nil,
            elapsedTimeMicros: Double? = nil,
            applicationName: String? = nil,
            bundleIdentifier: String? = nil,
            artworkDataBase64: String? = nil,
            artworkMimeType: String? = nil,
            timestampEpochMicros: Double? = nil,
            PID: pid_t? = nil,
            shuffleMode: ShuffleMode? = nil,
            repeatMode: RepeatMode? = nil,
            playbackRate: Double? = nil,
            sessionIdentifier: String? = nil,
            playerPathDataBase64: String? = nil,
            isControllable: Bool? = nil,
            removed: Bool? = nil,
            artwork: NSImage? = nil
        ) {
            self.title = title
            self.artist = artist
            self.album = album
            self.isPlaying = isPlaying
            self.durationMicros = durationMicros
            self.elapsedTimeMicros = elapsedTimeMicros
            self.applicationName = applicationName
            self.bundleIdentifier = bundleIdentifier
            self.artworkDataBase64 = artworkDataBase64
            self.artworkMimeType = artworkMimeType
            self.timestampEpochMicros = timestampEpochMicros
            self.PID = PID
            self.shuffleMode = shuffleMode
            self.repeatMode = repeatMode
            self.playbackRate = playbackRate
            self.sessionIdentifier = sessionIdentifier
            self.playerPathDataBase64 = playerPathDataBase64
            self.isControllable = isControllable
            self.removed = removed
            self.artwork = artwork
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.title = try container.decodeIfPresent(String.self, forKey: .title)
            self.artist = try container.decodeIfPresent(String.self, forKey: .artist)
            self.album = try container.decodeIfPresent(String.self, forKey: .album)
            self.durationMicros = try container.decodeIfPresent(Double.self, forKey: .durationMicros)
            self.elapsedTimeMicros = try container.decodeIfPresent(Double.self, forKey: .elapsedTimeMicros)
            self.applicationName = try container.decodeIfPresent(String.self, forKey: .applicationName)
            self.bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
            self.artworkDataBase64 = try container.decodeIfPresent(String.self, forKey: .artworkDataBase64)
            self.artworkMimeType = try container.decodeIfPresent(String.self, forKey: .artworkMimeType)
            self.timestampEpochMicros = try container.decodeIfPresent(Double.self, forKey: .timestampEpochMicros)

            if let pidNumber = try? container.decodeIfPresent(Int32.self, forKey: .PID) {
                self.PID = pid_t(pidNumber)
            } else if let pidString = try? container.decodeIfPresent(String.self, forKey: .PID),
                      let pidNumber = Int32(pidString) {
                self.PID = pid_t(pidNumber)
            } else {
                self.PID = nil
            }

            self.shuffleMode = try? container.decodeIfPresent(ShuffleMode.self, forKey: .shuffleMode)
            self.repeatMode = try? container.decodeIfPresent(RepeatMode.self, forKey: .repeatMode)
            self.playbackRate = try container.decodeIfPresent(Double.self, forKey: .playbackRate)
            self.sessionIdentifier = try container.decodeIfPresent(String.self, forKey: .sessionIdentifier)
            self.playerPathDataBase64 = try container.decodeIfPresent(String.self, forKey: .playerPathDataBase64)
            self.isControllable = try container.decodeIfPresent(Bool.self, forKey: .isControllable)
            self.removed = try container.decodeIfPresent(Bool.self, forKey: .removed)

            if let boolValue = try? container.decode(Bool.self, forKey: .isPlaying) {
                self.isPlaying = boolValue
            } else if let intValue = try? container.decode(Int.self, forKey: .isPlaying) {
                self.isPlaying = (intValue == 1)
            } else {
                self.isPlaying = nil
            }

            if let base64String = self.artworkDataBase64,
               let data = Data(base64Encoded: base64String) {
                self.artwork = Self.decodeArtwork(data)
            } else {
                self.artwork = nil
            }
        }

        private static func decodeArtwork(_ data: Data) -> NSImage? {
            guard let representation = NSBitmapImageRep(data: data),
                  let cgImage = representation.cgImage else {
                return NSImage(data: data)
            }

            return NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
        }
    }
}
