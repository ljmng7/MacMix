import AppKit
import SwiftUI

@MainActor
final class PanelTestContent: ObservableObject {
    @Published var height: CGFloat = 200
}

struct PanelTestRoot: View {
    @ObservedObject var content: PanelTestContent
    var body: some View {
        MenuBarPanelViewport(maximumHeight: 500) {
            Color.clear.frame(width: 320, height: content.height)
        }
        .frame(width: 320)
    }
}

@main
struct MenuBarPanelViewportTests {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let content = PanelTestContent()
        let host = NSHostingView(rootView: PanelTestRoot(content: content))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 320, height: 500),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        func settle() {
            for _ in 0..<12 {
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.025))
            }
        }
        func expect(_ height: CGFloat, _ message: String) {
            settle()
            let actual = host.fittingSize.height
            precondition(abs(actual - height) <= 1, "\(message): expected \(height), got \(actual)")
            print("PASS: \(message), height=\(actual)")
        }
        expect(200, "short content uses its natural height")
        content.height = 1100
        expect(500, "long content is bounded and scrollable")
        content.height = 70
        expect(70, "collapsing content removes the unused viewport height")
        content.height = 410
        expect(410, "re-expanding content restores its natural height")
        window.close()
        print("All 4 native SwiftUI viewport checks passed.")
    }
}
