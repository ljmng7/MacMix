import AppKit
import Carbon

@main
struct SceneShortcutTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let controller = SceneShortcutController()
        guard let modifiers = SceneShortcutModifiers.allCases.first(where: { $0 != .disabled && controller.configure($0, enabled: true) }) else {
            fatalError("No free shortcut combination is available to test")
        }
        var received: [Int] = []
        controller.onDigit = { received.append($0) }
        for digit in [0, 1, 9] {
            var event: EventRef?
            precondition(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed),
                                     0, 0, &event) == noErr)
            var key = EventHotKeyID(signature: 0x4D4D5343, id: UInt32(digit))
            precondition(SetEventParameter(event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &key) == noErr)
            precondition(SendEventToEventTarget(event, GetApplicationEventTarget()) == noErr)
            ReleaseEvent(event)
        }
        precondition(received == [0, 1, 9], "Carbon events deliver the correct scene number")
        let competitor = SceneShortcutController()
        precondition(!competitor.configure(modifiers, enabled: true) && competitor.hasConflict,
                     "Conflicting registration is reported")
        controller.configure(.disabled, enabled: true)
        precondition(competitor.configure(modifiers, enabled: true), "Disabling releases all ten keys")
        competitor.configure(modifiers, enabled: false)
        print("Scene shortcut tests passed")
    }
}
