import CoreGraphics

public enum MixVolumeShortcutModifier: String, CaseIterable, Identifiable {
    case disabled, control, option, shift, command
    public var id: Self { self }
    public var symbol: String {
        switch self {
        case .disabled: ""
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        }
    }
    var flags: CGEventFlags {
        switch self {
        case .disabled: []
        case .control: .maskControl
        case .option: .maskAlternate
        case .shift: .maskShift
        case .command: .maskCommand
        }
    }
}

// Tracks held keys rather than registering a modifier + digit hot key: the
// third key can be either a hardware media key or an ordinary F10–F12 event.
struct MixVolumeChord {
    var modifier: MixVolumeShortcutModifier = .disabled
    private var heldDigits: [Int64: Int] = [:]
    private var consumedKeys: Set<Int64> = []
    private static let digits: [Int64: Int] = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4,
        22: 5, 26: 6, 28: 7, 25: 8]

    // Spelled out: before Swift 6.4 the memberwise initializer is private
    // because of the private stored properties above.
    init(modifier: MixVolumeShortcutModifier = .disabled) {
        self.modifier = modifier
    }

    func matches(_ flags: CGEventFlags) -> Bool {
        let relevant: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        return modifier != .disabled && flags.intersection(relevant) == modifier.flags
    }

    func appIndex(flags: CGEventFlags) -> Int? {
        guard matches(flags), heldDigits.count == 1 else { return nil }
        return heldDigits.values.first
    }

    mutating func digit(keyCode: Int64, isDown: Bool, flags: CGEventFlags) -> Bool {
        guard let index = Self.digits[keyCode] else { return false }
        if isDown {
            heldDigits[keyCode] = index
            if matches(flags) { consumedKeys.insert(keyCode) }
            return consumedKeys.contains(keyCode)
        }
        heldDigits.removeValue(forKey: keyCode)
        return consumedKeys.remove(keyCode) != nil
    }

    static func functionAction(keyCode: Int64) -> SystemVolumeKeyAction? {
        switch keyCode {
        case 109: .toggleMute
        case 103: .decrease
        case 111: .increase
        default: nil
        }
    }
}

public enum MixVolumeStep {
    public static func volume(_ volume: Double, action: SystemVolumeKeyAction) -> Double {
        switch action {
        case .increase: max(0, (volume * 10 + 1).rounded() / 10)
        case .decrease: max(0, (volume * 10 - 1).rounded() / 10)
        case .toggleMute: volume
        }
    }
}
