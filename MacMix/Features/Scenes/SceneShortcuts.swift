import Carbon
import Observation

enum SceneShortcutModifiers: Int, CaseIterable, Identifiable {
    case disabled = -1
    case controlOption = 0, controlShift, commandOption, commandControl
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .disabled: String(localized: "Off")
        case .controlOption: "⌃⌥"
        case .controlShift: "⌃⇧"
        case .commandOption: "⌥⌘"
        case .commandControl: "⌃⌘"
        }
    }
    var carbonFlags: UInt32 {
        let flags = switch self {
        case .disabled: 0
        case .controlOption: controlKey | optionKey
        case .controlShift: controlKey | shiftKey
        case .commandOption: cmdKey | optionKey
        case .commandControl: cmdKey | controlKey
        }
        return UInt32(flags)
    }
}

// Carbon hot keys work globally without monitoring all keyboard input or
// requesting Accessibility permission. Registration is all-or-nothing.
@MainActor @Observable
final class SceneShortcutController {
    var hasConflict = false
    var onDigit: ((Int) -> Void)?
    @ObservationIgnored nonisolated(unsafe) private var handler: EventHandlerRef?
    @ObservationIgnored nonisolated(unsafe) private var hotKeys: [EventHotKeyRef] = []
    private var registeredModifiers: SceneShortcutModifiers?
    private static let signature: OSType = 0x4D4D5343

    @discardableResult
    func configure(_ modifiers: SceneShortcutModifiers, enabled: Bool) -> Bool {
        guard enabled && modifiers != .disabled else {
            hotKeys.forEach { UnregisterEventHotKey($0) }
            hotKeys.removeAll()
            registeredModifiers = nil
            hasConflict = false
            return true
        }
        if registeredModifiers == modifiers { return true }
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var key = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
                guard status == noErr, key.signature == 0x4D4D5343 else { return OSStatus(eventNotHandledErr) }
                let controller = Unmanaged<SceneShortcutController>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { controller.onDigit?(Int(key.id)) }
                return noErr
            }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { hasConflict = true; return false }
        }
        let digits = [kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
                      kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        var candidates: [EventHotKeyRef] = []
        for (digit, keyCode) in digits.enumerated() {
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(keyCode), modifiers.carbonFlags,
                EventHotKeyID(signature: Self.signature, id: UInt32(digit)), GetApplicationEventTarget(), 0, &reference)
            guard status == noErr, let reference else {
                candidates.forEach { UnregisterEventHotKey($0) }
                hasConflict = true
                return false
            }
            candidates.append(reference)
        }
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys = candidates
        registeredModifiers = modifiers
        hasConflict = false
        return true
    }

    deinit {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
    }
}
