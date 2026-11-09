// Accessibility smoke test for the menu bar panel of a running MacMix.
//
// Reads the panel's accessibility tree the way VoiceOver does and fails when
// a control has no name, a mute button does not say what it mutes, or no
// device is marked as selected. Needs a running MacMix and Accessibility
// permission for the process that runs it. Run tests/run-accessibility-smoke-tests.sh.

import AppKit
import ApplicationServices

private let bundleIdentifier = "jazmin.MacMix"
private let controlRoles: Set<String> = [
    "AXButton", "AXSlider", "AXCheckBox", "AXRadioButton", "AXPopUpButton",
    "AXMenuButton", "AXDisclosureTriangle", "AXTextField",
]

struct Element {
    let role: String
    let name: String
    let isSelected: Bool
    let context: String
}

private func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

private func string(_ element: AXUIElement, _ name: String) -> String {
    (attribute(element, name) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

private func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

/// Collects controls in the panel window, remembering the nearest named
/// ancestor so a failure says where the control is.
private func collect(_ element: AXUIElement, context: String, into result: inout [Element], depth: Int = 0) {
    guard depth < 60 else { return }
    let role = string(element, kAXRoleAttribute)
    let name = [kAXDescriptionAttribute, kAXTitleAttribute]
        .map { string(element, $0) }
        .first { !$0.isEmpty } ?? ""
    if controlRoles.contains(role) {
        result.append(Element(
            role: role,
            name: name,
            isSelected: attribute(element, kAXSelectedAttribute) as? Bool ?? false,
            context: context
        ))
    }
    let textValue = role == "AXStaticText" ? (attribute(element, kAXValueAttribute) as? String ?? "") : ""
    let nextContext = !name.isEmpty ? name : (!textValue.isEmpty ? textValue : context)
    for child in children(element) {
        collect(child, context: nextContext, into: &result, depth: depth + 1)
    }
}

private func panelControls(of app: AXUIElement) -> [Element] {
    var result: [Element] = []
    for window in attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
    where string(window, kAXSubroleAttribute) == "AXSystemDialog" {
        collect(window, context: "panel", into: &result)
    }
    return result.contains { $0.role == "AXSlider" } ? result : []
}

private func pressStatusItem(of app: AXUIElement) -> Bool {
    guard let bar = attribute(app, "AXExtrasMenuBar"),
          let item = children(bar as! AXUIElement).first else { return false }
    return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
}

/// Every translation of a bare "Mute" / "Unmute", so a label that names
/// nothing is caught in any language the app runs in.
private func bareMuteLabels(in bundle: Bundle) -> Set<String> {
    var labels: Set<String> = ["Mute", "Unmute"]
    for localization in bundle.localizations {
        guard let path = bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: localization),
              let table = NSDictionary(contentsOfFile: path) as? [String: String] else { continue }
        for key in ["Mute", "Unmute"] {
            if let value = table[key] { labels.insert(value) }
        }
    }
    return labels
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

guard AXIsProcessTrusted() else {
    fail("this process has no Accessibility permission. Allow the terminal app in System Settings > Privacy & Security > Accessibility.")
}

let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
let preferredPath = CommandLine.arguments.dropFirst().first
guard let target = running.first(where: { preferredPath == nil || $0.bundleURL?.path == preferredPath }) ?? running.first,
      let bundleURL = target.bundleURL,
      let bundle = Bundle(url: bundleURL) else {
    fail("MacMix is not running. Start it with ./script/build_and_run.sh first.")
}
print("Testing \(bundleURL.path) (pid \(target.processIdentifier))")

let app = AXUIElementCreateApplication(target.processIdentifier)
AXUIElementSetMessagingTimeout(app, 3)

// Open the panel if it is closed, and close it again afterwards.
var controls = panelControls(of: app)
let wasOpen = !controls.isEmpty
for _ in 0..<2 where controls.isEmpty {
    guard pressStatusItem(of: app) else { fail("could not press the MacMix menu bar item.") }
    Thread.sleep(forTimeInterval: 1.5)
    controls = panelControls(of: app)
}
defer {
    if !wasOpen { _ = pressStatusItem(of: app) }
}
guard !controls.isEmpty else { fail("the menu bar panel did not open or shows no volume sliders.") }

var failures: [String] = []

for control in controls where control.name.isEmpty {
    failures.append("\(control.role) without an accessibility name, near “\(control.context)”")
}

let bareLabels = bareMuteLabels(in: bundle)
for control in controls where control.role == "AXButton" && bareLabels.contains(control.name) {
    failures.append("mute button labelled only “\(control.name)”, near “\(control.context)”; it should name what it mutes")
}

if !controls.contains(where: \.isSelected) {
    failures.append("no control is marked as selected; the current output device should be")
}

let sliders = controls.filter { $0.role == "AXSlider" }
print("Checked \(controls.count) controls, \(sliders.count) sliders: \(sliders.map(\.name).joined(separator: ", "))")

if failures.isEmpty {
    print("PASS: accessibility smoke test")
} else {
    failures.forEach { FileHandle.standardError.write(Data("FAIL: \($0)\n".utf8)) }
    if !wasOpen { _ = pressStatusItem(of: app) }
    exit(1)
}
