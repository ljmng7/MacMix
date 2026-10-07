// Shared DDC/CI decoding and speaker-volume conversion for both transports.
import Foundation

nonisolated enum DDCWriteRetry {
    static func perform(_ attempt: () -> Bool) -> Bool {
        var anySucceeded = false
        // Preserve the transport's two write cycles, including when the first
        // one succeeds. A rejected duplicate must not erase that success.
        for _ in 0 ..< 2 {
            let succeeded = attempt()
            anySucceeded = succeeded || anySucceeded
        }
        return anySucceeded
    }
}

nonisolated enum DDCReplyParser {
    static func read(_ reply: [UInt8], command: UInt8) -> (current: UInt16, maximum: UInt16)? {
        // Get VCP reply: source, length, opcode, result, VCP, type,
        // maximum high/low, current high/low, checksum.
        guard reply.count == 11,
              reply[0] == 0x6E,
              reply[1] == 0x88,
              reply[2] == 0x02,
              reply[3] == 0x00,
              reply[4] == command,
              // R27U91 reports type 01 for volume; accept both defined types.
              reply[5] <= 1,
              reply.dropLast().reduce(UInt8(0x50), ^) == reply[10] else {
            return nil
        }

        let maximum = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        return (current, maximum)
    }
}

nonisolated enum DDCVolumeValue {
    static let defaultMaximum: UInt16 = 100

    static func maximum(_ reported: UInt16) -> UInt16 {
        // Some displays report an unspecified maximum (0 or 0xFFFF) for
        // speaker volume while accepting the usual 0...100 range. This is
        // a volume-specific compatibility fallback, not a generic VCP rule.
        reported == 0 || reported == UInt16.max ? defaultMaximum : reported
    }

    static func volume(current: UInt16, maximum reported: UInt16) -> Double? {
        let maximum = maximum(reported)
        // Do not turn a malformed/special current value into full volume.
        guard current <= maximum else { return nil }
        return Double(current) / Double(maximum)
    }

    static func clamped(_ volume: Double) -> Double {
        guard volume.isFinite else { return 0 }
        return max(0, min(1, volume))
    }

    static func ddcValue(for volume: Double, maximum reported: UInt16) -> UInt16 {
        UInt16((clamped(volume) * Double(maximum(reported))).rounded())
    }
}
