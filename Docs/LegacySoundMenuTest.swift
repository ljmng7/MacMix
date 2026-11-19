// Previous approach: requires the separate native Sound menu-bar icon to be visible.
// Kept as a confirmed historical reference, NOT recommended as the final implementation.
// Run: swift LegacySoundMenuTest.swift
import ApplicationServices
import CoreGraphics
import Foundation

let targetName = "卧室"
let soundIdentifier = "com.apple.menuextra.sound"
let targetIdentifier = "sound-device-\(targetName)"

func cf(_ text: String) -> CFString {
    text.withCString {
        CFStringCreateWithCString(nil, $0, CFStringBuiltInEncodings.UTF8.rawValue)!
    }
}

func readText(_ element: AXUIElement, _ key: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, cf(key), &value) == .success else { return nil }
    return value as? String
}

func elementAt(_ x: CGFloat, _ y: CGFloat) -> AXUIElement? {
    let system = AXUIElementCreateSystemWide()
    var element: AXUIElement?
    let result = AXUIElementCopyElementAtPosition(system, Float(x), Float(y), &element)
    return result == .success ? element : nil
}

func press(_ element: AXUIElement) -> Bool {
    AXUIElementPerformAction(element, cf(kAXPressAction)) == .success
}

let bounds = CGDisplayBounds(CGMainDisplayID())
print("正在查找系统声音按钮...")
fflush(stdout)
var soundButton: AXUIElement?
var soundX: CGFloat = 0

for yOffset in [12.0, 19.0, 25.0] {
    if soundButton != nil { break }
    let y = bounds.minY + CGFloat(yOffset)
    let startX = max(bounds.minX, bounds.maxX - 850)
    for x in stride(from: startX, through: bounds.maxX - 15, by: 10) {
        if let element = elementAt(x, y),
           readText(element, kAXIdentifierAttribute) == soundIdentifier {
            soundButton = element
            soundX = x
            break
        }
    }
}

guard let sound = soundButton else {
    print("❌ 没有找到声音菜单按钮")
    exit(1)
}
print("✅ 找到声音菜单")
guard press(sound) else {
    print("❌ 无法打开声音菜单")
    exit(1)
}
Thread.sleep(forTimeInterval: 0.6)

print("正在寻找 \(targetName)...")
var targetDevice: AXUIElement?
var targetX: CGFloat = 0
var targetY: CGFloat = 0
let candidates: [CGFloat] = [
    soundX + 80, soundX + 130, soundX + 30,
    soundX - 30, soundX - 100, soundX + 200
]
for y in stride(from: bounds.minY + 55, through: bounds.minY + 480, by: 12) {
    if targetDevice != nil { break }
    for x in candidates {
        guard x > bounds.minX, x < bounds.maxX else { continue }
        if let element = elementAt(x, y),
           readText(element, kAXIdentifierAttribute) == targetIdentifier {
            targetDevice = element
            targetX = x
            targetY = y
            break
        }
    }
}

guard let device = targetDevice else {
    print("❌ 没找到 \(targetName)")
    _ = press(sound)
    exit(1)
}
print("✅ 找到设备 \(targetName)")
guard press(device) else {
    print("❌ 设备选择失败")
    exit(1)
}
print("✅ 已执行切换操作")
Thread.sleep(forTimeInterval: 0.5)
if let remaining = elementAt(targetX, targetY),
   readText(remaining, kAXIdentifierAttribute) == targetIdentifier {
    _ = press(sound)
}
print("操作完成，请确认声音是否从 HomePod 播放")
