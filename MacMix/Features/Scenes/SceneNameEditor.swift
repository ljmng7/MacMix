import AppKit
import SwiftUI

/// A borderless, single-line text view. Return commits the name without submitting the popover.
struct SceneNameEditor: NSViewRepresentable {
    @Binding var text: String
    var onTextPresenceChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, onTextPresenceChange: onTextPresenceChange) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        let editor = SceneNameTextView(frame: .zero)
        editor.onTextPresenceChange = { [weak coordinator = context.coordinator] in coordinator?.onTextPresenceChange($0) }
        editor.isRichText = false
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 20, weight: .semibold)
        editor.textColor = .labelColor
        editor.insertionPointColor = .controlAccentColor
        editor.isHorizontallyResizable = true
        editor.isVerticallyResizable = false
        editor.autoresizingMask = [.height]
        editor.textContainerInset = NSSize(width: 0, height: 2)
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 30)
        editor.textContainer?.maximumNumberOfLines = 1
        editor.delegate = context.coordinator
        editor.string = text
        editor.setAccessibilityLabel(String(localized: "Scene Name"))
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onTextPresenceChange = onTextPresenceChange
        guard let editor = scroll.documentView as? NSTextView else { return }
        if !editor.hasMarkedText(), editor.string != text { editor.string = text }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onTextPresenceChange: (Bool) -> Void
        init(text: Binding<String>, onTextPresenceChange: @escaping (Bool) -> Void) {
            self.text = text
            self.onTextPresenceChange = onTextPresenceChange
        }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            onTextPresenceChange(!editor.string.isEmpty)
            guard !editor.hasMarkedText() else { return }
            text.wrappedValue = editor.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            guard !textView.hasMarkedText() else { return false }
            text.wrappedValue = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            textView.string = text.wrappedValue
            textView.window?.makeFirstResponder(nil)
            return true
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                      replacementString: String?) -> Bool {
            guard let replacementString, replacementString.rangeOfCharacter(from: .newlines) != nil else { return true }
            let singleLine = replacementString.components(separatedBy: .newlines).joined(separator: " ")
            textView.insertText(singleLine, replacementRange: affectedCharRange)
            return false
        }
    }
}

/// Marked-text updates do not reliably send textDidChange while an IME is composing.
private final class SceneNameTextView: NSTextView {
    var onTextPresenceChange: ((Bool) -> Void)?

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onTextPresenceChange?(!self.string.isEmpty || hasMarkedText())
    }

    override func unmarkText() {
        super.unmarkText()
        onTextPresenceChange?(!string.isEmpty)
    }
}
