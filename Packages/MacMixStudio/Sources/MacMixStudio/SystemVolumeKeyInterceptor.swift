import AppKit
import ApplicationServices
import CoreGraphics
import IOKit.hidsystem

public enum SystemVolumeKeyAction: Equatable, Sendable {
    case increase
    case decrease
    case toggleMute
}

public final class SystemVolumeKeyInterceptor {
    private static let systemDefinedEventType = CGEventType(rawValue: 14)!

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let onAction: @MainActor (SystemVolumeKeyAction) -> Void
    private let onAppAction: @MainActor (Int, SystemVolumeKeyAction) -> Void
    private var chord = MixVolumeChord()
    private var consumedFunctionKeys: Set<Int64> = []
    private var appMediaKeys: Set<Int> = []

    public var mixShortcutModifier: MixVolumeShortcutModifier = .disabled {
        didSet { chord = MixVolumeChord(modifier: mixShortcutModifier) }
    }

    public init(
        onAction: @escaping @MainActor (SystemVolumeKeyAction) -> Void,
        onAppAction: @escaping @MainActor (Int, SystemVolumeKeyAction) -> Void = { _, _ in }
    ) {
        self.onAction = onAction
        self.onAppAction = onAppAction
    }

    deinit {
        stop()
    }

    public var isRunning: Bool {
        guard let eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: eventTap)
    }

    public static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    public static func requestAccessibilityPermission() -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    public func start() -> Bool {
        if isRunning {
            return true
        }

        stop()

        let eventMask = [Self.systemDefinedEventType, .keyDown, .keyUp].reduce(CGEventMask(0)) {
            $0 | (CGEventMask(1) << $1.rawValue)
        }
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.eventTapCallback,
            userInfo: userInfo
        ) else {
            return false
        }

        guard let runLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventTap,
            0
        ) else {
            CFMachPortInvalidate(eventTap)
            return false
        }

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }

    public func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
        chord = MixVolumeChord(modifier: mixShortcutModifier)
        consumedFunctionKeys.removeAll()
        appMediaKeys.removeAll()
    }

    static func action(forMediaKeyData data: Int) -> SystemVolumeKeyAction? {
        let keyState = (data & 0x0000_FF00) >> 8
        guard keyState == 0xA else {
            return nil
        }

        return volumeAction(forMediaKeyData: data)
    }

    private static func volumeAction(
        forMediaKeyData data: Int
    ) -> SystemVolumeKeyAction? {
        let keyCode = Int32((data & 0xFFFF_0000) >> 16)
        switch keyCode {
        case NX_KEYTYPE_SOUND_UP:
            return .increase
        case NX_KEYTYPE_SOUND_DOWN:
            return .decrease
        case NX_KEYTYPE_MUTE:
            return .toggleMute
        default:
            return nil
        }
    }

    private static let eventTapCallback: CGEventTapCallBack = {
        _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let owner = Unmanaged<SystemVolumeKeyInterceptor>
            .fromOpaque(userInfo)
            .takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            owner.chord = MixVolumeChord(modifier: owner.mixShortcutModifier)
            owner.consumedFunctionKeys.removeAll()
            owner.appMediaKeys.removeAll()
            if let eventTap = owner.eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown || type == .keyUp {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if owner.chord.digit(keyCode: keyCode, isDown: type == .keyDown, flags: event.flags) {
                return nil
            }
            if type == .keyUp, owner.consumedFunctionKeys.remove(keyCode) != nil { return nil }
            if type == .keyDown,
               let action = MixVolumeChord.functionAction(keyCode: keyCode),
               let index = owner.chord.appIndex(flags: event.flags) {
                owner.consumedFunctionKeys.insert(keyCode)
                if action != .toggleMute || event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                    Task { @MainActor in owner.onAppAction(index, action) }
                }
                return nil
            }
            // A held function key remains ours even if the digit/modifier is
            // released first; never leak its repeat into another application.
            if owner.consumedFunctionKeys.contains(keyCode) { return nil }
            return Unmanaged.passUnretained(event)
        }

        guard type == systemDefinedEventType,
              let appKitEvent = NSEvent(cgEvent: event),
              appKitEvent.subtype.rawValue == 8,
              let volumeAction = volumeAction(
                forMediaKeyData: appKitEvent.data1
              ) else {
            return Unmanaged.passUnretained(event)
        }

        let mediaCode = (appKitEvent.data1 >> 16) & 0xFFFF
        if (appKitEvent.data1 & 0xFF00) >> 8 == 0xB {
            owner.appMediaKeys.remove(mediaCode)
        }
        if let action = action(forMediaKeyData: appKitEvent.data1) {
            if let index = owner.chord.appIndex(flags: event.flags) {
                owner.appMediaKeys.insert(mediaCode)
                if action != .toggleMute || appKitEvent.data1 & 1 == 0 {
                    Task { @MainActor in owner.onAppAction(index, action) }
                }
            } else if !owner.appMediaKeys.contains(mediaCode) {
                Task { @MainActor in owner.onAction(action) }
            }
        }

        return nil
    }
}
