// Read-only accessibility inspector used to identify the Control Center elements.
// Run: swift AccessibilityInspector.swift
// At each prompt, move the pointer to the indicated control before 12 s elapse.
import ApplicationServices
import CoreGraphics
import Foundation
import Darwin

func cf(_ text: String) -> CFString {
    text.withCString {
        CFStringCreateWithCString(
            nil, $0,
            CFStringBuiltInEncodings.UTF8.rawValue
        )!
    }
}

func readValue(_ element: AXUIElement, _ key: String) -> String {
    var result: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(element, cf(key), &result)
    guard status == .success, let result else {
        return "不可用（错误码：\(status.rawValue)）"
    }
    if let string = result as? String { return string }
    return String(describing: result)
}

func inspect(_ title: String) {
    print("\n========== \(title) ==========")
    guard let point = CGEvent(source: nil)?.location else {
        print("❌ 无法获取鼠标位置")
        return
    }
    let system = AXUIElementCreateSystemWide()
    var element: AXUIElement?
    let status = AXUIElementCopyElementAtPosition(
        system, Float(point.x), Float(point.y), &element
    )
    print("检测状态：\(status.rawValue)")
    guard status == .success, let found = element else {
        print("❌ 无法识别控件")
        return
    }
    var current = found
    for level in 0..<5 {
        print("\n----- 层级 \(level) -----")
        var pid: pid_t = 0
        _ = AXUIElementGetPid(current, &pid)
        print("进程 PID：\(pid)")
        for key in [
            kAXRoleAttribute,
            kAXSubroleAttribute,
            kAXTitleAttribute,
            kAXDescriptionAttribute,
            kAXIdentifierAttribute,
            kAXValueAttribute
        ] {
            print("\(key)：\(readValue(current, key))")
        }
        var actions: CFArray?
        let actionStatus = AXUIElementCopyActionNames(current, &actions)
        print("操作查询状态：\(actionStatus.rawValue)")
        if let actions { print("可执行操作：\(actions)") }
        var parent: CFTypeRef?
        let parentStatus = AXUIElementCopyAttributeValue(
            current, cf(kAXParentAttribute), &parent
        )
        guard parentStatus == .success,
              let parent,
              CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
        current = parent as! AXUIElement
    }
}

let stages = [
    "控制中心菜单栏图标",
    "控制中心里的声音 AirPlay 按钮",
    "声音设备列表中的卧室"
]

print("开始检测控制中心音频控件")
print("本程序只读取控件信息，不执行点击操作")
for (index, stage) in stages.enumerated() {
    print("\n第 \(index + 1) 阶段：\(stage)")
    print("请在 12 秒内打开对应界面，把鼠标停在目标上，不要点击目标")
    fflush(stdout)
    Thread.sleep(forTimeInterval: 12)
    inspect(stage)
}
print("\n========== 全部检测完成 ==========")
