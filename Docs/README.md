# MacMix 开发交接文档：控制中心 AirPlay 切换 + 菜单栏面板滚动修复

> **文档类型**：可复现技术报告 / 开发任务说明（Markdown）  
> **记录日期**：2026-11-19  
> **目标工程**：[ljmng7/MacMix](https://github.com/ljmng7/MacMix)  
> **测试设备**：MacBook Neo、HomePod mini（Bonjour / UI 显示名：`卧室`）、中文 macOS  
> **状态说明**：终端中的控制中心自动化已实测成功；**控制中心方案尚未集成、编译、验证到 MacMix 本体**。旧版“独立声音图标”自动化曾集成到本地 MacMix 并成功使用。滚动修复仅为需求和实施建议，尚未实现。

## 一、需要开发者解决的两项问题

### 任务 A：AirPlay 连接不要依赖独立的系统“声音”菜单栏图标

**现象**

- MacMix 可以通过 Core Audio 切换已经作为 HAL 设备出现的输出；但 HomePod mini 未建立 AirPlay 会话时，Core Audio 中暂时没有它对应的普通输出设备。
- MacMix 现有的 `AirPlayReceiverBrowser.swift` 已通过 Bonjour `_airplay._tcp` 发现未连接的 HomePod mini，例如“卧室”。
- 曾实现用系统独立声音按钮 `com.apple.menuextra.sound` 打开原生声音选择界面、按 `AXIdentifier=sound-device-卧室` 自动连接；**此旧方案在终端及本地 MacMix 测试过，确实能切换**。
- 但用户使用 MacMix 就是为了替代原生声音菜单栏入口，隐藏苹果独立声音图标后，旧自动化失效。

**新方案（已在终端验证）**

不用独立声音图标，改走 macOS **控制中心**：

1. AX 查找 `com.apple.menuextra.controlcenter`，执行 `AXPress`。
2. AX 查找控制中心声音模块中的 `controlcenter-airplay`，执行 `AXPress`。
3. AX 查找 `sound-device-<接收器名称>`（本例：`sound-device-卧室`），执行 `AXPress`。
4. **等待 Core Audio 证实系统默认输出确已切换，并且 AirPlay 设备稳定存在**，再在 MacMix UI 中显示“已连接”。
5. 如有必要收起控制中心，并恢复正常焦点；失败时给出状态/重试，勿谎报连接成功。

这是 **Accessibility/UI 自动化**，不是无 UI 的公开 AirPlay 连接 API。控制中心可能短暂出现。相关 AXIdentifier 为本机 macOS 版本实际测得，其他语言/系统版本需探测适配。

### 任务 B：菜单栏面板内容超出屏幕，无法纵向滚动

**复现**

1. 打开 MacMix 菜单栏完整面板。
2. 同时显示输出设备、混音应用、输入设备，以及可选的 Now Playing、场景预设等。
3. 内容增长后，面板向屏幕下方溢出，底部行及操作按钮不可见或不可操作；鼠标滚轮/触控板无法把隐藏部分滚入可见区域。

**当前代码分析（官方源码的 `MacMix/App/MacMixPanel.swift`）**

完整面板主体使用 `VStack(spacing: 12)`，末尾直接挂：

```swift
.frame(width: 320)
.fixedSize(horizontal: false, vertical: true)
```

其外层没有为完整面板建立受屏幕可见高度约束的垂直 `ScrollView`。`fixedSize(..., vertical: true)` 还会鼓励视图按全部内容的理想高度伸展。与屏幕小、应用行多、Now Playing/场景可见时的溢出现象一致。

**修复目标**

- 让完整面板高度不超过 **当前菜单栏弹窗所在屏幕的 `visibleFrame.height`**（预留菜单栏、阴影及边距），不要只用主屏幕高度。
- **输出/混音/输入/媒体/场景等主要内容纵向可滚动**；显示到最后一行。不要给所有内容固定不可滚动的硬编码高度。
- 建议把“打开主窗口 / 退出”等底部主要操作做成可见的固定 footer；若布局需要允许底部随滚动显示，也须保证能通过滚动访问。
- 保持宽度约 320 pt 的原有设计；不破坏音量滑块手势、应用行展开、设备选择、键盘/VoiceOver、临时音量 HUD 和弹窗焦点逻辑。
- 对折叠/展开内容高度变化、分辨率/缩放变化、多显示器、屏幕边缘贴合、面板重定位、触控板与鼠标滚轮进行回归测试。

**实现方向（示意，非已编译补丁）**

```swift
// 在 MacMixPanel 的完整面板层实现：
// 1. 将原先包含所有 section 的 VStack 拆为 scrollContent 与 footer。
// 2. 由菜单栏弹窗当前 NSWindow 所在 screen 的 visibleFrame
//    推导 maxPanelHeight，并在打开/换屏后更新。
// 3. 将 scrollContent 放入 ScrollView(.vertical)，限制可用高度。
// 4. 删除对整块完整面板强制 vertical: true 的 fixedSize。
// 5. footer 放在 ScrollView 外侧，按实际内容预留高度。

VStack(spacing: 0) {
    ScrollView(.vertical) {
        scrollContent
    }
    .scrollIndicators(.automatic)

    Divider()
    footer
}
.frame(width: 320)
.frame(maxHeight: maxPanelHeight)

// 说明：scrollContent / footer / maxPanelHeight 是开发者应提取的新成员，
// 不是当前源码已存在的符号。需要结合 MenuBarPanelCoordinator 实现。
```

要检查 `MenuBarPanelCoordinator.swift` 的面板对齐逻辑，避免高度变化导致超出屏幕或菜单栏锚点错位。

## 二、真实环境下已识别的 AX 控件（终端实测）

| 目标 | AXRole | AXIdentifier | AXDescription | 允许的动作 |
|---|---|---|---|---|
| 控制中心菜单栏入口 | `AXMenuBarItem` | `com.apple.menuextra.controlcenter` | 控制中心 | `AXShowMenu`, `AXPress` |
| 控制中心中的 AirPlay 入口 | `AXCheckBox` | `controlcenter-airplay` | 隔空播放音频 | `AXPress` |
| 控制中心声音模块（父级） | `AXGroup` | `module-Sound` | — | `AXShowMenu`, `AXPress` |
| HomePod mini（卧室）设备行 | `AXCheckBox` | `sound-device-卧室` | 卧室 | `AXPress` |

- 检测时 `sound-device-卧室` 的 `AXValue=0`（未选中），按下后开始连接。
- 三个关键 `AXPress` 的返回码均为 **`0`**。注意这是 AX API 调用成功，不是最终 AirPlay 连接成功的充分条件。
- 使用本文件夹的 `AccessibilityInspector.swift` 可重现上述控件及其父级信息。

## 三、实验过程与结果（非常重要）

| 场景 | 观察 | 结论等级 |
|---|---|---|
| 最早使用原生**独立声音图标**进行 AX 自动化 | 能打开系统声音菜单、选择“卧室”并连接 | **已验证**，但需原生声音图标显示 |
| 原生独立声音图标隐藏，仅用控制中心三步 AX 自动化 | 程序能自动打开控制中心、进入音频列表、按下“卧室”，每次 `AXPress=0` | **已验证**，操作链路成功 |
| 上述测试时 FineTune 仍通过 Xcode 正在运行 | “卧室”转圈一两圈，随后恢复 MacBook 扬声器 | **已观察**，不能据此判断是 AX 失败 |
| 完全停止 FineTune 后再次执行相同控制中心切换 | 用户确认 HomePod mini 切换成功并能维持连接 | **已验证**，实际系统输出成功 |
| 控制中心方案在 MacMix App 中编译、运行 | 尚未进行 | **待开发** |
| 菜单栏完整面板滚动修复 | 源码问题和复现步骤已定位；尚未提供可编译代码 | **待开发** |

**关于 FineTune 冲突**：FineTune 的 `AudioEngine.swift` 含设备优先级和默认输出恢复代码，可能把从系统控制中心发起的切换恢复为 MacBook 扬声器。但目前只有“FineTune 运行时失败、停止运行后成功”的对照测试，**不能把该机制视为已经由日志证明的唯一原因**。MacMix 可能也有相似的状态覆盖问题，需监听和验证。

## 四、提供的三份可运行 Swift 附件

文件均可单独运行，不需要将代码先集成到 MacMix。macOS `swift` + Terminal 无障碍权限即可（路径在本 ZIP 中）。

### 1. `ControlCenterAirPlayTest.swift` — 新方案，重点附件

```bash
cd /path/to/MacMix_AirPlay_ControlCenter_开发资料
swift ControlCenterAirPlayTest.swift
```

默认目标为 `let targetName = "卧室"`；可根据 MacMix Bonjour 发现的接收器名称泛化。测试前：停止可能抢占默认输出的音频软件，系统切回内置扬声器、关闭控制中心。脚本使用**鼠标位置之外的 AX 识别结果**，通过屏幕区域扫描查找控件；不移动鼠标，也不生成点击坐标事件。

已知限制：扫描范围是主屏幕右上区域；控制中心不在此位置、多显示器/不同分辨率时可能找不到；AXIdentifier、菜单内容和延迟可能随 macOS 改动；按成功以后脚本只输出“已发送”，**不包含 Core Audio 成功判定**。

### 2. `AccessibilityInspector.swift` — 原始识别/验收工具

```bash
swift AccessibilityInspector.swift
```

程序每 12 秒检查一项：控制中心菜单栏图标、控制中心内的 AirPlay 按钮、设备列表“卧室”。打印 AXRole、AXSubrole、AXIdentifier、AXDescription、AXValue、支持动作和父级。这是识别表的直接可重复依据。

### 3. `LegacySoundMenuTest.swift` — 旧方案 / 回归参考

```bash
swift LegacySoundMenuTest.swift
```

历史验证的旧方案：`com.apple.menuextra.sound` → `sound-device-卧室`。**必须显示独立的系统声音图标；不应作为新功能依赖**。保留用于解释为什么要改成控制中心方案。

### 4. `AX_实测控件记录.txt` — 终端观察证据

包含识别到的 AXRole、AXIdentifier、控件父级、支持操作，以及“FineTune 运行/停止”对照测试结论。

## 五、建议的 MacMix 代码集成（未实现）

现有代码模块：

- `MacMix/Devices/AirPlayReceiverBrowser.swift`：`NWBrowser(for: .bonjourWithTXTRecord(type: "_airplay._tcp", domain: nil), using: .tcp)`，得到未连接设备。
- `MacMix/Devices/AirPlayAudioRoutes.swift`：`DiscoveredAirPlayReceiver`、`AirPlayDataSources`，负责识别接收器、HAL 数据源。
- `MacMix/App/MacMixPanel.swift`：`AirPlayReceiverRow` 两处系统输出设备列表入口及面板内容结构。
- `MacMix/Features/OutputRouting/AppOutputRoutingView.swift`：应用级 AirPlay 路由入口，**请勿直接替换成全局输出切换，否则会破坏应用独立输出语义**。
- `MacMix/App/MenuBarPanelCoordinator.swift`：弹窗展示、状态和几何重定位；滚动修复需联动。

建议新增如 `ControlCenterAirPlayAutomation.swift` 的系统输出专用服务，包含：

1. `connect(to receiver: DiscoveredAirPlayReceiver) async -> ConnectionResult`，用串行状态机防止重复发起。
2. `AXIsProcessTrusted()` 检查，在权限缺失时提示用户授予 MacMix 本体的无障碍权限（Terminal 权限不会自动授予 MacMix）。
3. 对控制中心入口、`module-Sound` 下的 AirPlay 控件、目标设备行做**可访问性树遍历优先**的查找；坐标扫描只作为回退，不应硬编码 `卧室`。
4. `AXPress` 后先显示“连接中”，等待 HAL AirPlay 设备出现、实际默认输出切换、数据源匹配；加入合理超时、取消及错误分类。
5. 结合 Bonjour 服务 `deviceid` / `model` 与 HAL `AirPlayDataSources`，解决 UI 的 `AirPlay` 和 `卧室` 重复行、错误“未连接”状态，不应仅凭最后点击的名字推断持久连接。
6. 尊重用户手动切换，避免启动或设备变化监听器强制重置默认输出。
7. 将新控制中心方案仅用于**系统输出**的 AirPlay 未连接接收器；维持应用级 `AVRoutePickerView` / route picker 逻辑不变。
8. 控制中心可能自动收起，也可能保持展开；避免贸然重复 `AXPress` 导致重新打开或错误操作。

**明确限制**：以上为实施建议，不应声称其已在 Xcode 中编译或所有 macOS 版本都能使用。AX 是 UI 自动化，对无障碍授权、系统语言与 UI 结构存在依赖。

## 六、验收标准与测试清单

### AirPlay

- [ ] 隐藏苹果独立的“声音”菜单栏图标，MacMix 仍能 Bonjour 发现“卧室”。
- [ ] 点击 MacMix “卧室”时，系统控制中心短暂展开并自动选中对应设备，无需鼠标移动。
- [ ] 以 **Core Audio 实际默认输出**及接收器稳定状态判断成功，而不是 `AXPress` 返回值。
- [ ] 连接成功后声音确实从 HomePod mini 播放，保持 30 秒以上不会自动回到内置扬声器。
- [ ] 从 HomePod 切回本机，再次点击 HomePod 可重复连接。
- [ ] 未连接/连接中/连接成功/连接失败的 UI 准确，不重复显示 `AirPlay` 和“卧室”。
- [ ] HomePod 改名、不可达/断网、未给无障碍权限、控制中心窗口已打开、设备不存在、不同语言、不同显示器布局均有明确处理。
- [ ] 不破坏 MacMix 应用独立路由和当前普通输出设备切换。

### 窗口滚动

- [ ] 完整面板在小屏幕、低分辨率、显示缩放、内容较多时不超出当前屏幕可见区域。
- [ ] 鼠标滚轮和触控板能访问全部应用、设备、底部操作；滚动条可见性合理。
- [ ] 面板内容增减、展开/收起应用、切换输入/输出、Now Playing 和场景显示时仍能滚动。
- [ ] 音量滑块拖动不被 `ScrollView` 误拦截；键盘/VoiceOver 无退化。
- [ ] 不破坏临时系统音量面板与 `MenuBarPanelCoordinator` 锚点对齐。

## 七、建议直接交给开发者 / Codex 的任务摘要

> 请在 MacMix 工程中完成两项独立改动：
>
> **A.** 保留现有 Bonjour `_airplay._tcp` 发现，实现基于系统控制中心 `com.apple.menuextra.controlcenter` → `controlcenter-airplay` → `sound-device-<receiver.name>` 的 AirPlay 系统输出连接，不依赖菜单栏独立声音图标，并以 Core Audio 确认成功；不要破坏每应用的路由选择。
>
> **B.** 修复完整菜单栏面板过高无法滚动：根据弹窗所在屏幕的 visibleFrame 约束高度，使正文可滚动、底部操作可访问、保持原有手势和窗口锚点行为。
>
> 本目录的 Swift 脚本含已验证的独立测试代码：`ControlCenterAirPlayTest.swift` 为新方案，`AccessibilityInspector.swift` 为识别证据，`LegacySoundMenuTest.swift` 为旧方案对照。先备份工作分支，提交前进行 Swift 编译和真机回归。不要把终端脚本直接当作已集成的生产代码。

---

**参考源码**：[MacMixPanel.swift](https://github.com/ljmng7/MacMix/blob/main/MacMix/App/MacMixPanel.swift) · [AirPlayReceiverBrowser.swift](https://github.com/ljmng7/MacMix/blob/main/MacMix/Devices/AirPlayReceiverBrowser.swift) · [AirPlayAudioRoutes.swift](https://github.com/ljmng7/MacMix/blob/main/MacMix/Devices/AirPlayAudioRoutes.swift) · [MenuBarPanelCoordinator.swift](https://github.com/ljmng7/MacMix/blob/main/MacMix/App/MenuBarPanelCoordinator.swift)


## 附录 A：控制中心自动化原始 Swift 代码（终端实测）

以下代码与 `ControlCenterAirPlayTest.swift` 一致。

```swift
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
```


## 附录 B：AX 控件识别原始 Swift 代码（终端实测）

以下代码与 `AccessibilityInspector.swift` 一致。

```swift
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
```


## 附录 C：旧版独立声音菜单栏自动化 Swift 代码（曾在终端验证）

以下代码与 `LegacySoundMenuTest.swift` 一致。

```swift
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
```
