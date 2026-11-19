// Tested on the user's Mac in Terminal, 2026-11-19.
// Precondition: FineTune is completely stopped, default output is MacBook speakers,
// and Control Center is closed. Requires Terminal Accessibility permission.
// Uses accessibility UI, not a private or public headless AirPlay API.
// Run: swift ControlCenterAirPlayTest.swift

import ApplicationServices
import CoreGraphics
import Foundation
import Darwin

let targetName = "卧室"

func cf(_ text: String) -> CFString {
    text.withCString {
        CFStringCreateWithCString(
            nil, $0,
            CFStringBuiltInEncodings.UTF8.rawValue
        )!
    }
}

func identifier(_ element: AXUIElement) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
        element,
        cf(kAXIdentifierAttribute),
        &value
    ) == .success else {
        return nil
    }
    return value as? String
}

func matchingElement(
    _ element: AXUIElement,
    id: String
) -> AXUIElement? {
    var current = element

    for _ in 0..<6 {
        if identifier(current) == id {
            return current
        }

        var parent: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            current,
            cf(kAXParentAttribute),
            &parent
        ) == .success,
        let parent,
        CFGetTypeID(parent) == AXUIElementGetTypeID()
        else {
            break
        }
        current = parent as! AXUIElement
    }
    return nil
}

func findControl(
    _ id: String,
    menuBar: Bool = false
) -> AXUIElement? {
    let bounds = CGDisplayBounds(CGMainDisplayID())
    let system = AXUIElementCreateSystemWide()

    let minX = max(
        bounds.minX + 10,
        bounds.maxX - (menuBar ? 700 : 550)
    )
    let maxX = bounds.maxX - 12

    let ys: [CGFloat]

    if menuBar {
        ys = [12, 19, 25].map {
            bounds.minY + CGFloat($0)
        }
    } else {
        let endY = min(
            bounds.maxY - 30,
            bounds.minY + 800
        )
        ys = Array(stride(
            from: bounds.minY + 55,
            through: endY,
            by: 14
        ))
    }

    for y in ys {
        for x in stride(
            from: minX,
            through: maxX,
            by: menuBar ? 10 : 14
        ) {
            var element: AXUIElement?
            let result = AXUIElementCopyElementAtPosition(
                system,
                Float(x),
                Float(y),
                &element
            )

            guard result == .success,
                  let element else {
                continue
            }

            if let found = matchingElement(
                element,
                id: id
            ) {
                return found
            }
        }
    }
    return nil
}

func press(_ element: AXUIElement) -> Bool {
    let result = AXUIElementPerformAction(
        element,
        cf(kAXPressAction)
    )
    print("AXPress 返回：\(result.rawValue)")
    return result == .success
}

func findWithRetry(
    _ id: String,
    menuBar: Bool = false
) -> AXUIElement? {
    for _ in 0..<3 {
        if let found = findControl(
            id,
            menuBar: menuBar
        ) {
            return found
        }
        Thread.sleep(forTimeInterval: 0.4)
    }
    return nil
}

guard AXIsProcessTrusted() else {
    print("❌ 终端缺少无障碍权限")
    exit(1)
}

print("第一步：查找控制中心")

guard let controlCenter = findWithRetry(
    "com.apple.menuextra.controlcenter",
    menuBar: true
) else {
    print("❌ 找不到控制中心图标")
    exit(1)
}

guard press(controlCenter) else {
    print("❌ 无法打开控制中心")
    exit(1)
}

print("✅ 已操作控制中心")
Thread.sleep(forTimeInterval: 0.8)

print("第二步：查找 AirPlay 按钮")

guard let airPlayButton = findWithRetry(
    "controlcenter-airplay"
) else {
    print("❌ 未找到控制中心的 AirPlay 按钮")
    exit(1)
}

guard press(airPlayButton) else {
    print("❌ 无法展开 AirPlay 设备列表")
    exit(1)
}

print("✅ 已操作 AirPlay 按钮")
Thread.sleep(forTimeInterval: 0.7)

print("第三步：查找 \(targetName)")

guard let homePod = findWithRetry(
    "sound-device-\(targetName)"
) else {
    print("❌ 没有找到 \(targetName)")
    exit(1)
}

guard press(homePod) else {
    print("❌ HomePod 选择操作失败")
    exit(1)
}

print("✅ 已向 \(targetName) 发送切换操作")
print("请检查实际系统声音输出是否已切换")
print("========== 测试结束 ==========")
