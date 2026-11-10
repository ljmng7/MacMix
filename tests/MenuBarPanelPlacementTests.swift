import Foundation
import CoreGraphics

@main
struct MenuBarPanelPlacementTests {
    static func main() {
        let visible = CGRect(x: 0, y: 111, width: 2560, height: 1299)
        let anchor = CGRect(x: 1877, y: 1410, width: 40, height: 30)
        let expanded = CGRect(x: 1877, y: 150, width: 320, height: 1000)
        func expect(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            print("PASS: \(message)")
        }
        let full = MenuBarPanelPlacement.origin(panel: expanded, anchor: anchor, visibleFrame: visible)!
        expect(full == CGPoint(x: 1877, y: 406), "downshifted panel moves directly below its status item")
        let collapsed = CGRect(origin: full, size: CGSize(width: 320, height: 450))
        let short = MenuBarPanelPlacement.origin(panel: collapsed, anchor: anchor, visibleFrame: visible)!
        expect(short.y + collapsed.height == full.y + expanded.height, "collapsing content preserves the top edge")
        let restored = MenuBarPanelPlacement.origin(panel: CGRect(origin: short, size: expanded.size), anchor: anchor, visibleFrame: visible)!
        expect(restored == full, "expanding content restores the original top-anchored placement")
        let maximum = MenuBarPanelPlacement.maximumHeight(anchor: anchor, visibleFrame: visible)
        expect(maximum == 1295, "available height excludes the menu bar, its gap, and the Dock")
        let tallest = MenuBarPanelPlacement.origin(panel: CGRect(x: 0, y: 0, width: 320, height: maximum), anchor: anchor, visibleFrame: visible)!
        expect(tallest.y == visible.minY, "bounded tall panel stays above the Dock")
        expect(MenuBarPanelPlacement.origin(panel: CGRect(x: 0, y: 0, width: 320, height: 1500), anchor: anchor, visibleFrame: visible) == nil,
            "oversized content resizes before repositioning")
        let edge = MenuBarPanelPlacement.origin(panel: expanded,
            anchor: CGRect(x: 2530, y: 1410, width: 30, height: 30), visibleFrame: visible)!
        expect(edge.x == 2240, "right-edge status items do not push the panel off screen")
        let leftDock = CGRect(x: 80, y: 0, width: 2480, height: 1410)
        let left = MenuBarPanelPlacement.origin(panel: expanded,
            anchor: CGRect(x: 10, y: 1410, width: 40, height: 30), visibleFrame: leftDock)!
        expect(left.x == 80, "a left-side Dock is respected")
        let secondScreen = CGRect(x: -1920, y: -180, width: 1920, height: 1050)
        let second = MenuBarPanelPlacement.origin(panel: CGRect(x: -1700, y: -100, width: 320, height: 600),
            anchor: CGRect(x: -400, y: 870, width: 40, height: 30), visibleFrame: secondScreen)!
        expect(second == CGPoint(x: -400, y: 266), "secondary-screen coordinates retain their original origin")
        expect(MenuBarPanelPlacement.maximumHeight(anchor: nil, visibleFrame: visible) == 1295,
            "the viewport has a safe height before the status item is attached")
        print("All 10 menu-panel placement checks passed.")
    }
}
